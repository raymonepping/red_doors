// Red Doors API (prompt 07). Internal only: no Route; NetworkPolicy admits the
// UI's server side (BFF), which injects X-Triggered-By and — for human doors —
// the signed-in person's Vault token (X-Vault-Token). Contract: openapi/red-doors.yaml.
import express from 'express';
import { asApi, asUser, apiIdentity, initVaultIdentity, VaultError, vaultConfig } from './vault.js';
import { initDb, q, dbState } from './db.js';
import { startCollector, collector, entriesFor } from './audit.js';
import { clusterStatus } from './cluster.js';
import { DOORS, doorById } from './registry.js';

const PORT = Number(process.env.PORT ?? 3001);
const OPENER_TIMEOUT_MS = 20_000;
const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '64kb' }));

// ── helpers ─────────────────────────────────────────────────────────────────
const triggeredBy = (req) => req.get('X-Triggered-By') || null;
const userToken = (req) => req.get('X-Vault-Token') || null;

class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/** A Vault refusal is a successful demo (outcome: denied), not an API error. */
function vaultDenial(err, step) {
  return { step, status: err.status ?? null, path: err.path ?? null, errors: err.errors ?? [String(err.message)] };
}

async function record({ door, mode, triggered_by, opened_by, outcome, decision = {}, denial = null, request_ids = [], extra = {} }) {
  const { rows } = await q(
    `INSERT INTO api.attempts (door, mode, triggered_by, opened_by, outcome, decision, denial, request_ids, extra)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id, created_at`,
    [door, mode, triggered_by, opened_by, outcome, decision, denial, request_ids, extra],
  );
  return rows[0];
}

async function callOpener(name, body) {
  const res = await fetch(`http://${name}.rd-doors.svc:8080/knock`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body ?? {}),
    signal: AbortSignal.timeout(OPENER_TIMEOUT_MS),
  });
  if (!res.ok) throw new ApiError(502, 'opener_failed', `${name} answered ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return res.json();
}

async function policyText(name) {
  try {
    const r = await asApi('GET', `sys/policies/acl/${name}`);
    return r.data.policy;
  } catch {
    return null;
  }
}

async function tokenInfo(token) {
  const r = await asUser(token, 'GET', 'auth/token/lookup-self');
  const d = r.data;
  let groups = [];
  if (d.entity_id) {
    try {
      const ent = await asApi('GET', `identity/entity/id/${d.entity_id}`);
      const ids = ent.data.group_ids ?? [];
      groups = (await Promise.all(ids.map((id) => asApi('GET', `identity/group/id/${id}`).then((g) => g.data.name).catch(() => null)))).filter(Boolean);
    } catch {
      /* names are a nicety; the policies below are what Vault decides on */
    }
  }
  return {
    display_name: d.display_name,
    username: d.meta?.username ?? d.display_name,
    entity_id: d.entity_id || null,
    policies: d.policies ?? [],
    identity_policies: d.identity_policies ?? [],
    groups,
    ttl: d.ttl,
    accessor: d.accessor,
    request_id: r.request_id,
  };
}

// door 3: the API is the trusted orchestrator — it may WRAP a secret-id
// (rd-api enforces 30s–2m wrapping), it never has the role-id.
let lastConsumedWrap = null;
async function mintWrappedSecretId() {
  const r = await asApi('POST', 'auth/approle/role/door-3/secret-id', { body: {}, wrapTtl: '60s' });
  return r;
}

// ── health / meta ───────────────────────────────────────────────────────────
app.get('/api/v1/health', (_req, res) => {
  res.json({
    status: apiIdentity.accessor && dbState.username ? 'ok' : 'degraded',
    vault: { ...vaultConfig, role: apiIdentity.role, policies: apiIdentity.policies, ttl: apiIdentity.ttl, last_login: apiIdentity.last_login, last_error: apiIdentity.last_error },
    database: dbState,
    audit_collector: collector,
  });
});

app.get('/api/v1/whoami', async (req, res, next) => {
  try {
    const token = userToken(req);
    if (!token) throw new ApiError(401, 'no_token', 'no Vault token in X-Vault-Token');
    res.json(await tokenInfo(token));
  } catch (err) {
    next(err);
  }
});

// ── doors ───────────────────────────────────────────────────────────────────
async function lastAttempt(door) {
  const { rows } = await q('SELECT id, created_at, mode, outcome, triggered_by FROM api.attempts WHERE door=$1 ORDER BY created_at DESC LIMIT 1', [door]);
  return rows[0] ?? null;
}

app.get('/api/v1/doors', async (_req, res, next) => {
  try {
    const doors = await Promise.all(
      [...DOORS].sort((a, b) => a.story - b.story).map(async (d) => ({ ...d, paths: undefined, last_attempt: await lastAttempt(d.id) })),
    );
    res.json({ doors });
  } catch (err) {
    next(err);
  }
});

app.get('/api/v1/doors/:id', async (req, res, next) => {
  try {
    const d = doorById(req.params.id);
    if (!d) throw new ApiError(404, 'no_such_door', `no door ${req.params.id}`);
    const policies = await Promise.all(d.policies.map(async (name) => ({ name, text: await policyText(name) })));
    let egp = [];
    if (d.egp) {
      egp = await Promise.all(d.egp.map((name) =>
        asApi('GET', `sys/policies/egp/${name}`)
          .then((r) => ({ name, text: r.data.policy, paths: r.data.paths, enforcement_level: r.data.enforcement_level }))
          .catch(() => ({ name, text: null }))));
    }
    const { rows: attempts } = await q(
      'SELECT id, created_at, mode, outcome, triggered_by, opened_by, denial FROM api.attempts WHERE door=$1 ORDER BY created_at DESC LIMIT 10',
      [d.id],
    );
    res.json({ ...d, paths: undefined, policy_texts: policies, egp, attempts });
  } catch (err) {
    next(err);
  }
});

app.post('/api/v1/doors/:id/knock', async (req, res, next) => {
  try {
    const d = doorById(req.params.id);
    if (!d) throw new ApiError(404, 'no_such_door', `no door ${req.params.id}`);
    if (d.kind !== 'machine') throw new ApiError(409, 'not_a_machine_door', `door ${d.id} opens for people, not workloads`);
    const as = req.body?.as === 'impostor' ? 'impostor' : 'owner';
    const body = {};
    const orchestration = {};

    if (d.id === 3) {
      if (as === 'owner') {
        const wrap = await mintWrappedSecretId();
        body.wrapping_token = wrap.wrap_info.token;
        orchestration.wrapped_by = { identity: 'red-doors-api', request_id: wrap.request_id, creation_path: wrap.wrap_info.creation_path, ttl: wrap.wrap_info.ttl };
      } else {
        // replay a wrapping token the rightful opener already consumed
        if (!lastConsumedWrap) {
          const wrap = await mintWrappedSecretId();
          await callOpener('opener-3', { wrapping_token: wrap.wrap_info.token });
          lastConsumedWrap = wrap.wrap_info.token;
        }
        body.wrapping_token = lastConsumedWrap;
        orchestration.replayed = 'a wrapping token that opener-3 already consumed';
      }
    }
    if (d.id === 6) {
      const { rows } = await q('SELECT id, title, ciphertext FROM merger_docs ORDER BY id LIMIT 1');
      if (!rows.length) throw new ApiError(409, 'no_ciphertext', 'merger_docs is empty — run make data-up');
      body.ciphertext = rows[0].ciphertext;
      orchestration.document = { id: rows[0].id, title: rows[0].title, stored_as: 'ciphertext only (PostgreSQL rd-data/reddoors.merger_docs)' };
    }
    if (as === 'impostor') body.door = d.id;

    const result = await callOpener(as === 'owner' ? `opener-${d.id}` : 'opener-impostor', body);
    if (d.id === 3 && as === 'owner') lastConsumedWrap = body.wrapping_token;

    const saved = await record({
      door: d.id,
      mode: as,
      triggered_by: triggeredBy(req),
      opened_by: result.identity,
      outcome: result.outcome,
      decision: { ...result.vault, steps: result.steps, certificate: result.certificate ?? null, wrapping: result.wrapping ?? null, encrypt_attempt: result.encrypt_attempt ?? null, timings_ms: result.timings_ms },
      denial: result.denial,
      request_ids: [...(result.vault?.request_ids ?? []), ...(orchestration.wrapped_by ? [orchestration.wrapped_by.request_id] : [])],
      extra: { orchestration, tampered: result.tampered ?? false },
    });
    res.json({ attempt_id: saved.id, at: saved.created_at, door: d.id, as, triggered_by: triggeredBy(req), orchestration, ...result });
  } catch (err) {
    next(err);
  }
});

// ── door 2: a person, with their own token ─────────────────────────────────
app.post('/api/v1/doors/2/open', async (req, res, next) => {
  try {
    const token = userToken(req);
    if (!token) throw new ApiError(401, 'no_token', 'sign in first');
    const who = await tokenInfo(token);
    const opened_by = { method: 'oidc', subject: who.username, role: 'visitor', groups: who.groups };
    const decision = { policies: who.policies, identity_policies: who.identity_policies, entity_id: who.entity_id, token_ttl: who.ttl, token_accessor: who.accessor };
    let outcome = 'opened';
    let denial = null;
    let released = null;
    const request_ids = [who.request_id];
    try {
      const r = await asUser(token, 'GET', 'doors/data/2-board-minutes');
      request_ids.push(r.request_id);
      released = { item: 'Board minutes', ...r.data.data, kv_version: r.data.metadata.version };
    } catch (err) {
      if (!(err instanceof VaultError)) throw err;
      outcome = 'denied';
      denial = vaultDenial(err, 'read');
    }
    const saved = await record({ door: 2, mode: 'human', triggered_by: who.username, opened_by, outcome, decision, denial, request_ids });
    res.json({ attempt_id: saved.id, at: saved.created_at, door: 2, outcome, identity: opened_by, vault: { ...decision, request_ids }, released, denial });
  } catch (err) {
    next(err);
  }
});

// ── door 8: two different people ────────────────────────────────────────────
app.post('/api/v1/doors/8/requests', async (req, res, next) => {
  try {
    const token = userToken(req);
    if (!token) throw new ApiError(401, 'no_token', 'sign in first');
    const who = await tokenInfo(token);
    const opened_by = { method: 'oidc', subject: who.username, role: 'visitor', groups: who.groups };
    try {
      const r = await asUser(token, 'GET', 'doors/data/8-launch-codes');
      if (!r.wrap_info) throw new ApiError(500, 'no_control_group', 'Vault returned the codes without a control group — check policy door-8-request');
      const expires = new Date(Date.parse(r.wrap_info.creation_time) + r.wrap_info.ttl * 1000);
      await q(
        `INSERT INTO api.door8_requests (accessor, requester_entity, requester_name, expires_at, request_id) VALUES ($1,$2,$3,$4,$5)`,
        [r.wrap_info.accessor, who.entity_id, who.username, expires, r.request_id],
      );
      const saved = await record({
        door: 8, mode: 'request', triggered_by: who.username, opened_by, outcome: 'pending',
        decision: { policies: who.policies, identity_policies: who.identity_policies, entity_id: who.entity_id, control_group: { accessor: r.wrap_info.accessor, ttl: r.wrap_info.ttl } },
        request_ids: [who.request_id, r.request_id],
      });
      // The wrapping token goes back to the requester's server-side session only.
      res.status(201).json({ attempt_id: saved.id, door: 8, outcome: 'pending', accessor: r.wrap_info.accessor, wrapping_token: r.wrap_info.token, expires_at: expires.toISOString(), identity: opened_by });
    } catch (err) {
      if (!(err instanceof VaultError)) throw err;
      const denial = vaultDenial(err, 'request');
      const saved = await record({ door: 8, mode: 'request', triggered_by: who.username, opened_by, outcome: 'denied', decision: { policies: who.policies, identity_policies: who.identity_policies }, denial, request_ids: [who.request_id] });
      res.json({ attempt_id: saved.id, door: 8, outcome: 'denied', identity: opened_by, denial });
    }
  } catch (err) {
    next(err);
  }
});

async function requestStatus(token, accessor) {
  const r = await asUser(token, 'POST', 'sys/control-group/request', { body: { accessor } });
  return {
    approved: r.data.approved,
    request_path: r.data.request_path,
    requester: { entity_id: r.data.request_entity?.id, name: r.data.request_entity?.name },
    authorizations: (r.data.authorizations ?? []).map((a) => ({ entity_id: a.entity_id, name: a.entity_name })),
    request_id: r.request_id,
  };
}

app.get('/api/v1/doors/8/requests', async (req, res, next) => {
  try {
    const token = userToken(req);
    if (!token) throw new ApiError(401, 'no_token', 'sign in first');
    const who = await tokenInfo(token);
    const isApprover = who.identity_policies.includes('door-8-approve');
    const { rows } = await q(
      `SELECT accessor, requester_entity, requester_name, created_at, expires_at, opened_at FROM api.door8_requests
        WHERE ($1 OR requester_entity = $2) ORDER BY created_at DESC LIMIT 25`,
      [isApprover, who.entity_id],
    );
    const items = await Promise.all(rows.map(async (row) => {
      const out = { ...row, mine: row.requester_entity === who.entity_id, expired: new Date(row.expires_at) < new Date() };
      if (isApprover && !out.expired && !row.opened_at) {
        try {
          out.vault = await requestStatus(token, row.accessor);
          out.self_approval_present = out.vault.authorizations.some((a) => a.entity_id === row.requester_entity);
        } catch (err) {
          out.vault = { error: (err.errors ?? [String(err.message)]).join('; ') };
        }
      }
      return out;
    }));
    res.json({ viewer: { username: who.username, approver: isApprover, requester: who.identity_policies.includes('door-8-request') }, requests: items });
  } catch (err) {
    next(err);
  }
});

app.post('/api/v1/doors/8/requests/:accessor/approve', async (req, res, next) => {
  try {
    const token = userToken(req);
    if (!token) throw new ApiError(401, 'no_token', 'sign in first');
    const who = await tokenInfo(token);
    const { rows } = await q('SELECT * FROM api.door8_requests WHERE accessor=$1', [req.params.accessor]);
    const reqRow = rows[0] ?? null;
    const opened_by = { method: 'oidc', subject: who.username, role: 'visitor', groups: who.groups };
    try {
      const r = await asUser(token, 'POST', 'sys/control-group/authorize', { body: { accessor: req.params.accessor } });
      const self = reqRow && reqRow.requester_entity === who.entity_id;
      const outcome = r.data.approved ? 'approved' : self ? 'not_counted' : 'recorded';
      const saved = await record({
        door: 8, mode: 'approve', triggered_by: who.username, opened_by, outcome,
        decision: { approved: r.data.approved, self_approval: self, enforced_by: self ? 'Sentinel EGP door-8-two-different-people' : 'control-group factor two-person', identity_policies: who.identity_policies },
        request_ids: [who.request_id, r.request_id], extra: { accessor: req.params.accessor },
      });
      res.json({
        attempt_id: saved.id, door: 8, outcome, approved: r.data.approved, self_approval: self,
        explanation: self && !r.data.approved
          ? 'Vault recorded your authorization but did not count it: approving your own request does not satisfy the two-person rule (Sentinel EGP door-8-two-different-people).'
          : r.data.approved ? 'Approved — the requester can now open the door once.' : 'Authorization recorded; more approvals needed.',
      });
    } catch (err) {
      if (!(err instanceof VaultError)) throw err;
      const denial = vaultDenial(err, 'authorize');
      const saved = await record({ door: 8, mode: 'approve', triggered_by: who.username, opened_by, outcome: 'denied', decision: { identity_policies: who.identity_policies }, denial, request_ids: [who.request_id], extra: { accessor: req.params.accessor } });
      res.json({ attempt_id: saved.id, door: 8, outcome: 'denied', denial });
    }
  } catch (err) {
    next(err);
  }
});

app.post('/api/v1/doors/8/requests/:accessor/open', async (req, res, next) => {
  try {
    const token = userToken(req);
    const wrapping = req.body?.wrapping_token;
    if (!token || !wrapping) throw new ApiError(400, 'missing', 'requester token and wrapping token are both required');
    const who = await tokenInfo(token);
    const opened_by = { method: 'oidc', subject: who.username, role: 'visitor', groups: who.groups };
    try {
      const r = await asUser(token, 'POST', 'sys/wrapping/unwrap', { body: { token: wrapping } });
      await q('UPDATE api.door8_requests SET opened_at = now() WHERE accessor=$1', [req.params.accessor]);
      const saved = await record({ door: 8, mode: 'open', triggered_by: who.username, opened_by, outcome: 'opened', decision: { identity_policies: who.identity_policies, entity_id: who.entity_id }, request_ids: [who.request_id, r.request_id], extra: { accessor: req.params.accessor } });
      res.json({ attempt_id: saved.id, door: 8, outcome: 'opened', identity: opened_by, released: { item: 'Launch codes', ...(r.data?.data ?? r.data) } });
    } catch (err) {
      if (!(err instanceof VaultError)) throw err;
      const denial = vaultDenial(err, 'unwrap');
      const saved = await record({ door: 8, mode: 'open', triggered_by: who.username, opened_by, outcome: 'denied', decision: { identity_policies: who.identity_policies }, denial, request_ids: [who.request_id], extra: { accessor: req.params.accessor } });
      res.json({ attempt_id: saved.id, door: 8, outcome: 'denied', identity: opened_by, denial });
    }
  } catch (err) {
    next(err);
  }
});

// ── attempts + audit ────────────────────────────────────────────────────────
app.get('/api/v1/attempts', async (req, res, next) => {
  try {
    const door = req.query.door ? Number(req.query.door) : null;
    const limit = Math.min(Number(req.query.limit ?? 25), 100);
    const { rows } = await q(
      `SELECT id, created_at, door, mode, triggered_by, opened_by, outcome, denial FROM api.attempts
        WHERE ($1::int IS NULL OR door = $1) ORDER BY created_at DESC LIMIT $2`,
      [door, limit],
    );
    res.json({ attempts: rows });
  } catch (err) {
    next(err);
  }
});

app.get('/api/v1/attempts/:id', async (req, res, next) => {
  try {
    const { rows } = await q('SELECT * FROM api.attempts WHERE id::text = $1', [req.params.id]);
    if (!rows.length) throw new ApiError(404, 'no_such_attempt', 'attempt not found');
    const a = rows[0];
    res.json({ ...a, audit: await entriesFor(a.request_ids), collector: { listening: collector.listening, last_entry_at: collector.last_entry_at } });
  } catch (err) {
    next(err);
  }
});

app.get('/api/v1/audit', async (req, res, next) => {
  try {
    const door = req.query.door ? Number(req.query.door) : null;
    const limit = Math.min(Number(req.query.limit ?? 50), 200);
    const { rows } = await q(
      `SELECT id, time, type, request_id, operation, path, namespace, display_name, policies, error, door FROM api.audit_entries
        WHERE ($1::int IS NULL OR door = $1) ORDER BY id DESC LIMIT $2`,
      [door, limit],
    );
    res.json({ collector, entries: rows });
  } catch (err) {
    next(err);
  }
});

app.get('/api/v1/audit/:id', async (req, res, next) => {
  try {
    const { rows } = await q('SELECT * FROM api.audit_entries WHERE id = $1', [Number(req.params.id)]);
    if (!rows.length) throw new ApiError(404, 'no_such_entry', 'audit entry not found');
    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
});

// ── platform ────────────────────────────────────────────────────────────────
app.get('/api/v1/cluster', async (_req, res, next) => {
  try {
    res.json({ ...(await clusterStatus()), audit_collector: collector });
  } catch (err) {
    next(err);
  }
});

app.get('/api/v1/policies/:name', async (req, res, next) => {
  try {
    const text = await policyText(req.params.name);
    if (text === null) throw new ApiError(404, 'no_such_policy', `policy ${req.params.name} not readable`);
    res.json({ name: req.params.name, text });
  } catch (err) {
    next(err);
  }
});

// ── errors ──────────────────────────────────────────────────────────────────
app.use((_req, _res, next) => next(new ApiError(404, 'not_found', 'no such route')));
app.use((err, req, res, _next) => {
  const status = err instanceof ApiError ? err.status : err instanceof VaultError ? 502 : 500;
  const code = err instanceof ApiError ? err.code : err instanceof VaultError ? 'vault_error' : 'internal';
  if (status >= 500) console.error(`[api] ${req.method} ${req.path}: ${err.message}`);
  res.status(status).json({ error: err.message, code, request_id: err.request_id ?? null });
});

// ── start ───────────────────────────────────────────────────────────────────
async function main() {
  startCollector();
  await initVaultIdentity();
  await initDb();
  app.listen(PORT, () => console.log(`red-doors-api on :${PORT}; audit collector on :${process.env.AUDIT_PORT ?? 9090}`));
}
main().catch((err) => {
  console.error(`[api] startup failed: ${err.message}`);
  process.exit(1);
});
