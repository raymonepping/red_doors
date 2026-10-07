// PostgreSQL access for the API's own schema (`api`), with credentials minted
// by Vault (database/creds/api-rw) — the API dogfoods dynamic secrets.
// Credentials are re-minted at 2/3 of their lease and the pool is swapped.
// The deadline is checked against the wall clock: a single long setTimeout
// pauses while the host sleeps and wakes after Vault already revoked the user
// (seen on CRC after the Mac slept). A refused login also re-mints once.
import pg from 'pg';
import { asApi } from './vault.js';

const HOST = process.env.PGHOST ?? 'postgres.rd-data.svc';
let pool = null;
let renewAt = 0; // wall-clock ms at which to re-mint
let minting = null;
export const dbState = { username: null, lease_ttl: null, minted_at: null, last_error: null };

async function mintPool() {
  const creds = await asApi('GET', 'database/creds/api-rw');
  const next = new pg.Pool({
    host: HOST,
    port: 5432,
    database: 'reddoors',
    user: creds.data.username,
    password: creds.data.password,
    max: 5,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
  });
  // Lesson (AppRole/pg incident): an idle client error without a listener
  // crashes the process. Log and let the pool replace the client.
  next.on('error', (err) => {
    dbState.last_error = String(err.message);
    console.error(`[db] idle client error: ${err.message}`);
  });
  // Tables belong to api_owner, so every minted login sees the same schema.
  next.on('connect', (client) => client.query('SET ROLE api_owner').catch(() => {}));
  await next.query('SELECT 1');
  const old = pool;
  pool = next;
  Object.assign(dbState, { username: creds.data.username, lease_ttl: creds.lease_duration, minted_at: new Date().toISOString(), last_error: null });
  if (old) old.end().catch(() => {});
  renewAt = Date.now() + Math.max(60, Math.floor(creds.lease_duration * (2 / 3))) * 1000;
}

/** One mint at a time; callers share the in-flight one. */
function remint() {
  minting ??= mintPool().catch((e) => {
    dbState.last_error = String(e.message);
    renewAt = Date.now() + 30_000;
    throw e;
  }).finally(() => { minting = null; });
  return minting;
}

setInterval(() => {
  if (pool && Date.now() >= renewAt) remint().catch(() => {});
}, 15_000).unref();

export async function initDb() {
  await remint();
  await migrate();
}

// 28P01 invalid_password / 28000 invalid_authorization: Vault revoked the login.
const AUTH_FAILED = new Set(['28P01', '28000']);

export async function q(text, params) {
  if (!pool) throw new Error('database not initialised');
  try {
    return await pool.query(text, params);
  } catch (err) {
    if (!AUTH_FAILED.has(err.code)) throw err;
    console.error(`[db] login ${dbState.username} refused (${err.code}) — minting new credentials`);
    await remint();
    return pool.query(text, params);
  }
}

async function migrate() {
  await q(`
    CREATE TABLE IF NOT EXISTS api.attempts (
      id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      created_at    timestamptz NOT NULL DEFAULT now(),
      door          integer NOT NULL,
      mode          text NOT NULL,                -- owner | impostor | human | request | approve | open
      triggered_by  text,                         -- the signed-in person who pressed the button
      opened_by     jsonb NOT NULL DEFAULT '{}',  -- the identity Vault evaluated
      outcome       text NOT NULL,                -- opened | denied | pending | error
      decision      jsonb NOT NULL DEFAULT '{}',  -- what Vault reported (policies, ttl, accessor, …)
      denial        jsonb,
      request_ids   text[] NOT NULL DEFAULT '{}', -- Vault request ids → audit join
      extra         jsonb NOT NULL DEFAULT '{}'
      -- released values are returned to the caller once and NEVER stored
    );
    CREATE INDEX IF NOT EXISTS attempts_door_time ON api.attempts (door, created_at DESC);

    CREATE TABLE IF NOT EXISTS api.audit_entries (
      id            bigserial PRIMARY KEY,
      received_at   timestamptz NOT NULL DEFAULT now(),
      time          timestamptz,
      type          text,
      request_id    text,
      operation     text,
      path          text,
      namespace     text,
      display_name  text,
      policies      text[],
      error         text,
      door          integer,
      raw           jsonb NOT NULL
    );
    CREATE INDEX IF NOT EXISTS audit_request_id ON api.audit_entries (request_id);
    CREATE INDEX IF NOT EXISTS audit_door_time ON api.audit_entries (door, time DESC);

    CREATE TABLE IF NOT EXISTS api.door8_requests (
      accessor          text PRIMARY KEY,         -- the ONLY handle stored; the wrapping token stays in the requester's session
      requester_entity  text NOT NULL,
      requester_name    text,
      created_at        timestamptz NOT NULL DEFAULT now(),
      expires_at        timestamptz NOT NULL,
      opened_at         timestamptz,
      request_id        text
    );
  `);
}
