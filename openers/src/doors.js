// One codebase, one identity per deployment (DOOR_ID). Every knock returns
// what Vault decided — taken from Vault's own responses — and the opener
// revokes its token afterwards (for door 4 that also revokes the DB lease).
import fs from 'node:fs';
import pg from 'pg';
import { vault, VaultError } from './vault.js';

export const DOOR_ID = process.env.DOOR_ID ?? 'unset'; // 1|3|4|5|6|7|impostor
const SA_TOKEN = process.env.VAULT_SA_TOKEN_FILE ?? '/var/run/secrets/vault/token';
const SA_NAME = process.env.SERVICE_ACCOUNT ?? `opener-${DOOR_ID}`;
const SUBJECT = `system:serviceaccount:rd-doors:${SA_NAME}`;
const DOOR7_DIR = process.env.DOOR7_SECRET_DIR ?? '/secrets/door-7';
const FORGED_DIR = process.env.FORGED_CERT_DIR ?? '/forged';

// ── result builder ──────────────────────────────────────────────────────────
function newResult(door, identity) {
  return {
    door,
    knocked_as: DOOR_ID,
    outcome: 'error',
    identity,
    vault: { request_ids: [], token_accessor: null, policies: [], token_ttl: null, entity_id: null, revoked_after_use: false },
    released: null,
    denial: null,
    steps: [],
    started_at: new Date().toISOString(),
    timings_ms: {},
  };
}

async function step(r, name, fn) {
  const t0 = performance.now();
  try {
    const out = await fn();
    if (out && typeof out === 'object' && out.request_id) r.vault.request_ids.push(out.request_id);
    r.steps.push({ step: name, ok: true });
    return out;
  } catch (err) {
    r.steps.push({ step: name, ok: false });
    throw Object.assign(err, { step: name });
  } finally {
    r.timings_ms[name] = Math.round(performance.now() - t0);
  }
}

function recordAuth(r, auth) {
  r.vault.token_accessor = auth.accessor;
  r.vault.policies = auth.token_policies ?? auth.policies ?? [];
  r.vault.identity_policies = auth.identity_policies ?? [];
  r.vault.token_ttl = auth.lease_duration;
  r.vault.entity_id = auth.entity_id || null;
  r.vault.auth_metadata = auth.metadata ?? {};
}

// A Vault refusal at any step is the door saying no; anything else is an error.
function settle(r, err) {
  if (err instanceof VaultError) {
    r.outcome = 'denied';
    r.denial = { step: err.step, status: err.status, path: err.path, errors: err.errors };
  } else if (err?.denied) {
    r.outcome = 'denied';
    r.denial = { step: err.step, status: null, path: null, errors: [err.message] };
  } else {
    r.outcome = 'error';
    r.denial = { step: err?.step ?? null, status: null, path: null, errors: [String(err?.message ?? err)] };
  }
}

async function revoke(r, token) {
  if (!token) return;
  try {
    await vault('POST', 'auth/token/revoke-self', { token });
    r.vault.revoked_after_use = true;
    r.vault.revoked_at = new Date().toISOString();
  } catch {
    /* already gone (e.g. login failed) */
  }
}

async function k8sLogin(r, role) {
  const jwt = fs.readFileSync(SA_TOKEN, 'utf8').trim();
  const res = await step(r, 'login', () => vault('POST', 'auth/kubernetes/login', { body: { role, jwt } }));
  recordAuth(r, res.auth);
  return res.auth.client_token;
}

const kvRead = (r, token, path) => step(r, 'read', () => vault('GET', `doors/data/${path}`, { token }));

// ── door 1: Kubernetes auth ─────────────────────────────────────────────────
async function door1(role = 'opener-1') {
  const r = newResult(1, { method: 'kubernetes', subject: SUBJECT, role });
  let token;
  try {
    token = await k8sLogin(r, role);
    const res = await kvRead(r, token, '1-production-deploy-key');
    r.released = { item: 'Production deploy key', ...res.data.data, kv_version: res.data.metadata.version };
    r.outcome = 'opened';
  } catch (err) {
    settle(r, err);
  } finally {
    await revoke(r, token);
  }
  return r;
}

// ── door 3: AppRole with a response-wrapped, single-use secret-id ───────────
async function door3({ wrapping_token } = {}) {
  const roleIdFile = process.env.ROLE_ID_FILE ?? '/approle/role_id';
  const r = newResult(3, { method: 'approle', subject: 'role door-3', role: 'door-3' });
  let token;
  try {
    if (!wrapping_token) throw Object.assign(new Error('no wrapping token supplied'), { step: 'input' });
    // Tamper evidence: the token must still exist and must have wrapped a door-3 secret-id.
    const look = await step(r, 'wrap_lookup', () => vault('POST', 'sys/wrapping/lookup', { body: { token: wrapping_token } }));
    r.wrapping = { creation_path: look.data.creation_path, creation_ttl: look.data.creation_ttl, creation_time: look.data.creation_time };
    if (look.data.creation_path !== 'auth/approle/role/door-3/secret-id') {
      throw Object.assign(new Error(`wrapping token was created at ${look.data.creation_path}, not door-3's secret-id`), { denied: true, step: 'wrap_lookup' });
    }
    const unwrapped = await step(r, 'unwrap', () => vault('POST', 'sys/wrapping/unwrap', { token: wrapping_token }));
    const roleId = fs.readFileSync(roleIdFile, 'utf8').trim();
    const res = await step(r, 'login', () =>
      vault('POST', 'auth/approle/login', { body: { role_id: roleId, secret_id: unwrapped.data.secret_id } }));
    recordAuth(r, res.auth);
    token = res.auth.client_token;
    const kv = await kvRead(r, token, '3-partner-api-key');
    r.released = { item: 'Partner API key', ...kv.data.data, kv_version: kv.data.metadata.version };
    r.outcome = 'opened';
  } catch (err) {
    settle(r, err);
    if (err.step === 'wrap_lookup' || err.step === 'unwrap') r.tampered = true;
  } finally {
    await revoke(r, token);
  }
  return r;
}

// ── door 4: dynamic PostgreSQL credentials ──────────────────────────────────
async function door4(role = 'opener-4') {
  const r = newResult(4, { method: 'kubernetes', subject: SUBJECT, role });
  let token;
  try {
    token = await k8sLogin(r, role);
    const creds = await step(r, 'mint_db_login', () => vault('GET', 'database/creds/payroll-reader', { token }));
    const { username, password } = creds.data;
    const client = new pg.Client({
      host: process.env.PGHOST ?? 'postgres.rd-data.svc', // network hostname, never loopback (lesson 8)
      port: 5432,
      database: 'reddoors',
      user: username,
      password,
      connectionTimeoutMillis: 5000,
    });
    const rows = await step(r, 'query', async () => {
      await client.connect();
      try {
        const count = await client.query('SELECT count(*)::int AS n FROM payroll');
        const sample = await client.query(
          'SELECT employee_id, name, department, monthly_salary_eur, iban_masked FROM payroll ORDER BY employee_id LIMIT 5');
        return { count: count.rows[0].n, sample: sample.rows };
      } finally {
        await client.end();
      }
    });
    r.released = {
      item: 'Payroll database',
      db_username: username,
      lease_id: `${creds.lease_id.split('/').slice(0, -1).join('/')}/…${creds.lease_id.slice(-6)}`,
      lease_ttl: creds.lease_duration,
      row_count: rows.count,
      rows: rows.sample,
    };
    r.outcome = 'opened';
  } catch (err) {
    settle(r, err);
  } finally {
    await revoke(r, token); // revoking the token revokes its DB lease → the role is dropped
    if (r.released) r.released.revoked_at = r.vault.revoked_at ?? null;
  }
  return r;
}

// ── door 5: Vault PKI client certificate + TLS cert auth ────────────────────
async function door5() {
  const r = newResult(5, { method: 'cert', subject: 'CN=opener-5.rd-doors', role: 'treasury' });
  let issuerToken;
  let token;
  try {
    // Step 1: the key cutter — this SA may ISSUE a certificate, not open the door.
    issuerToken = await k8sLogin(r, 'opener-5-issuer');
    r.key_cutter = { role: 'opener-5-issuer', policies: r.vault.policies };
    const issued = await step(r, 'issue_cert', () =>
      vault('POST', 'pki-int/issue/treasury-client', { token: issuerToken, body: { common_name: 'opener-5.rd-doors', ttl: '10m' } }));
    await revoke(r, issuerToken);
    issuerToken = null;
    r.certificate = { serial: issued.data.serial_number, not_after: new Date(issued.data.expiration * 1000).toISOString(), issuer: 'Red Doors Treasury Issuing CA' };
    // Step 2: the certificate is the key — presented in a NEW TLS handshake.
    const login = await step(r, 'login', () =>
      vault('POST', 'auth/cert/login', { body: { name: 'treasury' }, cert: issued.data.certificate, key: issued.data.private_key }));
    recordAuth(r, login.auth);
    token = login.auth.client_token;
    const kv = await kvRead(r, token, '5-treasury-wire-room');
    r.released = { item: 'Treasury wire room', ...kv.data.data, kv_version: kv.data.metadata.version };
    r.outcome = 'opened';
  } catch (err) {
    settle(r, err);
  } finally {
    await revoke(r, issuerToken);
    await revoke(r, token);
  }
  return r;
}

// ── door 6: Transit decrypt-only ────────────────────────────────────────────
async function door6({ ciphertext } = {}, role = 'opener-6') {
  const r = newResult(6, { method: 'kubernetes', subject: SUBJECT, role });
  let token;
  try {
    if (!ciphertext) throw Object.assign(new Error('no ciphertext supplied'), { step: 'input' });
    token = await k8sLogin(r, role);
    const dec = await step(r, 'decrypt', () => vault('POST', 'transit/decrypt/merger-docs', { token, body: { ciphertext } }));
    r.released = {
      item: 'Merger documents',
      ciphertext,
      key_version: Number(/^vault:v(\d+):/.exec(ciphertext)?.[1] ?? 0),
      plaintext: Buffer.from(dec.data.plaintext, 'base64').toString('utf8'),
    };
    r.outcome = 'opened';
    // Show decrypt-only: the same identity may not encrypt.
    try {
      await vault('POST', 'transit/encrypt/merger-docs', { token, body: { plaintext: Buffer.from('x').toString('base64') } });
      r.encrypt_attempt = { allowed: true };
    } catch (e) {
      r.encrypt_attempt = { allowed: false, status: e.status ?? null, errors: e.errors ?? [String(e.message)] };
    }
  } catch (err) {
    settle(r, err);
  } finally {
    await revoke(r, token);
  }
  return r;
}

// ── door 7: Vault Secrets Operator (this pod never talks to Vault) ──────────
function door7() {
  const r = newResult(7, { method: 'vault-secrets-operator', subject: 'Secret rd-doors/door-7-customer-db (synced by VSO)', role: 'vso-door-7' });
  try {
    if (!fs.existsSync(`${DOOR7_DIR}/password`)) {
      throw Object.assign(new Error('no Secret door-7-customer-db is mounted in this pod — VSO syncs it only for opener-7'), { denied: true, step: 'read_mounted_secret' });
    }
    const read = (k) => (fs.existsSync(`${DOOR7_DIR}/${k}`) ? fs.readFileSync(`${DOOR7_DIR}/${k}`, 'utf8') : null);
    const stat = fs.statSync(`${DOOR7_DIR}/password`);
    r.released = {
      item: 'Customer database password',
      username: read('username'),
      password: read('password'),
      rotated: read('rotated'),
      file_mtime: stat.mtime.toISOString(),
    };
    r.vault.note = 'this pod has no Vault address, token or role';
    r.steps.push({ step: 'read_mounted_secret', ok: true });
    r.outcome = 'opened';
  } catch (err) {
    r.steps.push({ step: 'read_mounted_secret', ok: false });
    settle(r, err);
  }
  return r;
}

// ── the impostor: same doors, wrong identity ────────────────────────────────
async function impostor(input = {}) {
  const door = Number(input.door);
  switch (door) {
    case 1:
      return door1('impostor');
    case 3: {
      // replays a wrapping token that was already consumed (or forged)
      const r = await door3({ wrapping_token: input.wrapping_token ?? 'hvs.not-a-real-wrapping-token' });
      r.identity = { method: 'approle', subject: 'impostor replaying a wrapping token', role: 'door-3' };
      return r;
    }
    case 4:
      return door4('impostor');
    case 5: {
      // a self-signed certificate with exactly the right CN — not from the Treasury CA
      const r = newResult(5, { method: 'cert', subject: 'CN=opener-5.rd-doors (self-signed forgery)', role: 'treasury' });
      try {
        const cert = fs.readFileSync(`${FORGED_DIR}/tls.crt`, 'utf8');
        const key = fs.readFileSync(`${FORGED_DIR}/tls.key`, 'utf8');
        const login = await step(r, 'login', () => vault('POST', 'auth/cert/login', { body: { name: 'treasury' }, cert, key }));
        recordAuth(r, login.auth);
        r.outcome = 'opened';
        await revoke(r, login.auth.client_token);
      } catch (err) {
        settle(r, err);
      }
      return r;
    }
    case 6:
      return door6(input, 'impostor');
    case 7: {
      const r = door7();
      r.identity = { method: 'none', subject: SUBJECT, role: null };
      return r;
    }
    default:
      throw new Error(`the impostor has no way to knock on door ${input.door}`);
  }
}

// ── dispatch + health ───────────────────────────────────────────────────────
export async function knock(input) {
  switch (DOOR_ID) {
    case '1':
      return door1();
    case '3':
      return door3(input);
    case '4':
      return door4();
    case '5':
      return door5();
    case '6':
      return door6(input);
    case '7':
      return door7();
    case 'impostor':
      return impostor(input);
    default:
      throw new Error(`DOOR_ID ${DOOR_ID} is not a machine door`);
  }
}

export function health() {
  const h = { status: 'ok', door: DOOR_ID, identity: SA_NAME };
  if (DOOR_ID === '7') {
    // No Vault here: the only thing that can go stale is the synced Secret.
    const p = `${DOOR7_DIR}/password`;
    if (!fs.existsSync(p)) return { ...h, status: 'secret_missing', detail: 'Secret door-7-customer-db not mounted (VSO not synced?)' };
    h.secret_mtime = fs.statSync(p).mtime.toISOString();
    h.vault = 'none — this pod never talks to Vault';
  } else if (DOOR_ID === '3') {
    h.credential = 'role-id only (secret-id arrives response-wrapped per knock)';
  } else if (DOOR_ID === '5') {
    h.credential = 'none at rest — a fresh 10-minute certificate is issued per knock';
  } else {
    h.credential = fs.existsSync(SA_TOKEN) ? 'projected service-account token (audience vault)' : 'MISSING projected token';
    if (!fs.existsSync(SA_TOKEN)) h.status = 'token_missing';
  }
  return h;
}
