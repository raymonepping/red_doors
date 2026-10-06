// Parse one line of Vault's JSON audit stream into a row (pure; unit-tested).
// HMAC'd fields stay HMAC'd — only Vault's own plain fields are lifted out.
import { doorForPath } from './registry.js';

export function parse(line) {
  let e;
  try {
    e = JSON.parse(line);
  } catch {
    return null;
  }
  if (!e || !e.request) return null;
  const path = e.request.path ?? '';
  return {
    time: e.time ?? null,
    type: e.type ?? null,
    request_id: e.request.id ?? null,
    operation: e.request.operation ?? null,
    path,
    namespace: e.request.namespace?.path ?? '',
    display_name: e.auth?.display_name ?? null,
    policies: e.auth?.policies ?? null,
    error: e.error || null,
    door: doorForPath(path),
    raw: e,
  };
}
