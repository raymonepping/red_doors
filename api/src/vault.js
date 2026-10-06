// Vault HTTP client + the API's own Vault identity.
//
// The API logs in with ITS OWN Kubernetes service account (role red-doors-api).
// Policy rd-api lets it wrap door-3 secret-ids, read policy text and identity
// names — never anything behind a door. Human doors use the USER's token,
// passed per request by the UI's server side and never stored.
import fs from 'node:fs';
import https from 'node:https';

const VAULT_ADDR = process.env.VAULT_ADDR ?? 'https://vault-active.rd-vault.svc:8200';
const NAMESPACE = process.env.VAULT_NAMESPACE ?? 'red-doors';
const CA = fs.readFileSync(process.env.VAULT_CACERT ?? '/ca/ca.crt');
const SA_TOKEN_FILE = process.env.VAULT_SA_TOKEN_FILE ?? '/var/run/secrets/vault/token';
const ROLE = process.env.VAULT_ROLE ?? 'red-doors-api';

export class VaultError extends Error {
  constructor(status, errors, path) {
    super(`${status} ${path}: ${errors.join('; ')}`);
    this.status = status;
    this.errors = errors;
    this.path = path;
  }
}

/** Raw call. `base` overrides the address (per-node health probes). */
export function vaultRequest(method, path, { token, body, base = VAULT_ADDR, namespace = NAMESPACE, timeout = 10_000, wrapTtl } = {}) {
  const url = new URL(`/v1/${path}`, base);
  const payload = body === undefined ? undefined : JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const req = https.request(
      url,
      {
        method,
        ca: CA,
        headers: {
          ...(namespace ? { 'X-Vault-Namespace': namespace } : {}),
          ...(token ? { 'X-Vault-Token': token } : {}),
          // response wrapping (door 3): Vault returns a single-use wrapping token instead of the data
          ...(wrapTtl ? { 'X-Vault-Wrap-TTL': wrapTtl } : {}),
          ...(payload ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) } : {}),
        },
        timeout,
      },
      (res) => {
        let raw = '';
        res.setEncoding('utf8');
        res.on('data', (c) => (raw += c));
        res.on('end', () => {
          let json = {};
          try {
            json = raw ? JSON.parse(raw) : {};
          } catch {
            json = { errors: [raw.slice(0, 300)] };
          }
          json.__status = res.statusCode;
          if (res.statusCode >= 200 && res.statusCode < 300) resolve(json);
          else reject(new VaultError(res.statusCode, json.errors ?? [`HTTP ${res.statusCode}`], path));
        });
      },
    );
    req.on('timeout', () => req.destroy(new Error(`timeout calling Vault ${path}`)));
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

// ── the API's own identity ──────────────────────────────────────────────────
let apiToken = null;
let renewTimer = null;
export const apiIdentity = { role: ROLE, policies: [], accessor: null, ttl: null, last_login: null, last_error: null };

async function login() {
  const jwt = fs.readFileSync(SA_TOKEN_FILE, 'utf8').trim();
  const res = await vaultRequest('POST', 'auth/kubernetes/login', { body: { role: ROLE, jwt } });
  apiToken = res.auth.client_token;
  Object.assign(apiIdentity, {
    policies: res.auth.token_policies,
    accessor: res.auth.accessor,
    ttl: res.auth.lease_duration,
    last_login: new Date().toISOString(),
    last_error: null,
  });
  schedule(res.auth.lease_duration);
}

function schedule(ttl) {
  clearTimeout(renewTimer);
  renewTimer = setTimeout(async () => {
    try {
      const r = await vaultRequest('POST', 'auth/token/renew-self', { token: apiToken });
      apiIdentity.ttl = r.auth.lease_duration;
      // renewal can't pass token_max_ttl: log in again when it stops growing
      if (r.auth.lease_duration < 60) await login();
      else schedule(r.auth.lease_duration);
    } catch (err) {
      apiIdentity.last_error = String(err.message);
      await login().catch((e) => {
        apiIdentity.last_error = String(e.message);
        schedule(30);
      });
    }
  }, Math.max(5, Math.floor(ttl * (2 / 3))) * 1000);
  renewTimer.unref();
}

export async function initVaultIdentity() {
  await login();
}

/** Call Vault as the API itself. Re-logs in once on 403 (expired token). */
export async function asApi(method, path, opts = {}) {
  if (!apiToken) await login();
  try {
    return await vaultRequest(method, path, { ...opts, token: apiToken });
  } catch (err) {
    if (err instanceof VaultError && err.status === 403 && /invalid token|permission denied/.test(err.errors.join(' '))) {
      await login();
      return vaultRequest(method, path, { ...opts, token: apiToken });
    }
    throw err;
  }
}

/** Call Vault as the signed-in PERSON (token from the UI's server-side session). */
export const asUser = (token, method, path, opts = {}) => vaultRequest(method, path, { ...opts, token });

export const vaultConfig = { address: VAULT_ADDR, namespace: NAMESPACE };
