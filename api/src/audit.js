// Vault audit collector: a TCP listener for Vault's `socket` audit device.
//
// Vault writes one JSON object per line per request/response. HMAC'd fields
// stay HMAC'd — the collector stores what Vault sent, nothing more. It must
// never block Vault: lines are parsed on arrival and written in batches; if
// the database is slow the queue is bounded and the oldest entries dropped
// (counted, and shown in the UI as a gap).
import net from 'node:net';
import { q } from './db.js';
import { parse } from './audit-parse.js';

const PORT = Number(process.env.AUDIT_PORT ?? 9090);
const MAX_QUEUE = 5000;
const RETAIN = 50_000;
const queue = [];
export const collector = { listening: false, connections: 0, received: 0, stored: 0, dropped: 0, last_entry_at: null, last_error: null };

async function flush() {
  if (!queue.length) return;
  const batch = queue.splice(0, 200);
  const values = [];
  const params = [];
  batch.forEach((r, i) => {
    const o = i * 11;
    values.push(`($${o + 1},$${o + 2},$${o + 3},$${o + 4},$${o + 5},$${o + 6},$${o + 7},$${o + 8},$${o + 9},$${o + 10},$${o + 11})`);
    params.push(r.time, r.type, r.request_id, r.operation, r.path, r.namespace, r.display_name, r.policies, r.error, r.door, r.raw);
  });
  try {
    await q(`INSERT INTO api.audit_entries (time,type,request_id,operation,path,namespace,display_name,policies,error,door,raw) VALUES ${values.join(',')}`, params);
    collector.stored += batch.length;
  } catch (err) {
    collector.last_error = String(err.message);
    collector.dropped += batch.length;
  }
}

export function startCollector() {
  const server = net.createServer((sock) => {
    collector.connections += 1;
    let buf = '';
    sock.setEncoding('utf8');
    sock.on('data', (chunk) => {
      buf += chunk;
      let nl;
      while ((nl = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, nl);
        buf = buf.slice(nl + 1);
        const row = parse(line);
        if (!row) continue;
        collector.received += 1;
        collector.last_entry_at = new Date().toISOString();
        if (queue.length >= MAX_QUEUE) {
          queue.shift();
          collector.dropped += 1;
        }
        queue.push(row);
      }
    });
    sock.on('close', () => (collector.connections -= 1));
    sock.on('error', () => {});
  });
  server.listen(PORT, () => (collector.listening = true));
  setInterval(() => flush().catch(() => {}), 500).unref();
  // bounded retention
  setInterval(() => q(`DELETE FROM api.audit_entries WHERE id < (SELECT max(id) - ${RETAIN} FROM api.audit_entries)`).catch(() => {}), 60_000).unref();
  return server;
}

/** Audit entries for a set of Vault request ids (request + response records). */
export async function entriesFor(requestIds) {
  if (!requestIds?.length) return [];
  const { rows } = await q(
    `SELECT id, time, type, request_id, operation, path, namespace, display_name, policies, error, raw
       FROM api.audit_entries WHERE request_id = ANY($1) ORDER BY time, type DESC`,
    [requestIds],
  );
  return rows;
}
