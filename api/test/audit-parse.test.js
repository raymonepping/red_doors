// Fixture tests for the audit parser + door tagger. Records are SYNTHETIC
// (shape of Vault's JSON audit device; HMAC values are fake) — never captured
// from a real cluster (gitleaks would rightly flag real ones).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parse } from '../src/audit-parse.js';
import { doorForPath, DOORS } from '../src/registry.js';

const line = (o) => JSON.stringify(o);
const req = (path, extra = {}) => ({
  time: '2026-10-06T19:00:00.000000Z',
  type: 'request',
  auth: { display_name: 'kubernetes-rd-doors-opener-4', policies: ['default', 'door-4'], client_token: 'hmac-sha256:aaaa' },
  request: { id: 'req-0001', operation: 'read', path, namespace: { id: 'abc12', path: 'red-doors/' } },
  ...extra,
});

test('tags door paths, leaves logins to the request-id join', () => {
  assert.equal(doorForPath('database/creds/payroll-reader'), 4);
  assert.equal(doorForPath('doors/data/8-launch-codes'), 8);
  assert.equal(doorForPath('transit/decrypt/merger-docs'), 6);
  assert.equal(doorForPath('pki-int/issue/treasury-client'), 5);
  assert.equal(doorForPath('auth/kubernetes/login'), null);
  assert.equal(doorForPath('doors/data/0-lobby'), null);
});

test('parses a request record and keeps HMAC fields as-is', () => {
  const row = parse(line(req('database/creds/payroll-reader')));
  assert.equal(row.door, 4);
  assert.equal(row.request_id, 'req-0001');
  assert.equal(row.namespace, 'red-doors/');
  assert.deepEqual(row.policies, ['default', 'door-4']);
  assert.equal(row.raw.auth.client_token, 'hmac-sha256:aaaa');
});

test('captures Vault errors on response records', () => {
  const row = parse(line({ ...req('doors/data/1-production-deploy-key'), type: 'response', error: '1 error occurred:\n\t* permission denied\n\n' }));
  assert.equal(row.type, 'response');
  assert.match(row.error, /permission denied/);
  assert.equal(row.door, 1);
});

test('ignores junk and non-request lines', () => {
  assert.equal(parse('not json'), null);
  assert.equal(parse(line({ type: 'request' })), null);
});

test('every door has a story position, a method and at least one policy', () => {
  assert.equal(DOORS.length, 8);
  assert.deepEqual([...DOORS].map((d) => d.story).sort((a, b) => a - b), [1, 2, 3, 4, 5, 6, 7, 8]);
  for (const d of DOORS) assert.ok(d.method && d.policies.length, `door ${d.id}`);
});
