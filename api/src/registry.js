// The eight doors. Door numbers are stable IDs; `story` is the corridor order
// (machine identity → humans → data → governance). `paths` tag Vault audit
// entries to a door; logins are joined by request id instead (their bodies
// are HMAC'd in the audit log).
export const DOORS = [
  {
    id: 1, story: 1, kind: 'machine', title: 'Production deploy key', method: 'Kubernetes auth',
    summary: "A pod's service-account token is its only credential.",
    owner: 'opener-1 (system:serviceaccount:rd-doors:opener-1)', wrong_key: 'the impostor — a real service account with no business here',
    policies: ['door-1'], paths: ['doors/data/1-production-deploy-key'],
  },
  {
    id: 3, story: 2, kind: 'machine', title: 'Partner API key', method: 'AppRole (response-wrapped secret-id)',
    summary: 'The opener holds a role-id; the secret-id arrives wrapped, single-use, from an orchestrator that can wrap but not use it.',
    owner: 'opener-3 (role door-3)', wrong_key: 'a replayed, already-consumed wrapping token',
    policies: ['door-3'], paths: ['doors/data/3-partner-api-key', 'auth/approle/role/door-3/secret-id', 'sys/wrapping/lookup', 'sys/wrapping/unwrap'],
  },
  {
    id: 5, story: 3, kind: 'machine', title: 'Treasury wire room', method: 'PKI certificate + TLS cert auth',
    summary: 'The opener may only cut a 10-minute key; the certificate itself is what opens the door.',
    owner: 'opener-5 (issuer role) → CN=opener-5.rd-doors (cert role treasury)', wrong_key: 'a self-signed certificate with exactly the right name',
    policies: ['door-5-issuer', 'door-5'], paths: ['pki-int/issue/treasury-client', 'auth/cert/login', 'doors/data/5-treasury-wire-room'],
  },
  {
    id: 2, story: 4, kind: 'human', title: 'Board minutes', method: 'OIDC — a person signs in',
    summary: 'Keycloak vouches for the person; LDAP group "board" becomes a Vault policy.',
    owner: 'members of LDAP group board (ada)', wrong_key: 'a signed-in colleague who is not on the board (ben)',
    policies: ['door-2'], paths: ['doors/data/2-board-minutes'],
  },
  {
    id: 4, story: 5, kind: 'machine', title: 'Payroll database', method: 'Dynamic database credentials',
    summary: 'Nobody has a password: Vault mints a PostgreSQL login for this knock and kills it afterwards.',
    owner: 'opener-4 (role opener-4)', wrong_key: 'the impostor asking for payroll credentials',
    policies: ['door-4'], paths: ['database/creds/payroll-reader'],
  },
  {
    id: 6, story: 6, kind: 'machine', title: 'Merger documents', method: 'Transit (decrypt-only)',
    summary: 'The database only ever stores ciphertext; one identity may decrypt and nothing else.',
    owner: 'opener-6 (role opener-6)', wrong_key: 'the impostor trying to decrypt',
    policies: ['door-6'], paths: ['transit/decrypt/merger-docs', 'transit/encrypt/merger-docs'],
  },
  {
    id: 7, story: 7, kind: 'machine', title: 'Customer database password', method: 'Vault Secrets Operator',
    summary: 'Vault syncs the secret into OpenShift; the app never talks to Vault.',
    owner: 'opener-7 (mounted Secret, synced by VSO as vso-door-7)', wrong_key: 'a pod the operator never synced the Secret into',
    policies: ['door-7'], paths: ['doors/data/7-customer-db-password'],
  },
  {
    id: 8, story: 8, kind: 'governance', title: 'Launch codes', method: 'Control group — two different people',
    summary: 'Knocking is not enough: a second person from "approvers" must authorize, and approving yourself does not count.',
    owner: 'a requester (cleo) + a different approver (dirk)', wrong_key: 'a requester approving her own request (eve)',
    policies: ['door-8-request', 'door-8-approve'], egp: ['door-8-two-different-people'], paths: ['doors/data/8-launch-codes', 'sys/control-group/request', 'sys/control-group/authorize'],
  },
];

export const doorById = (id) => DOORS.find((d) => d.id === Number(id));

/** Tag an audit request path to a door number (or null). */
export function doorForPath(path = '') {
  for (const d of DOORS) if (d.paths.some((p) => path === p || path.startsWith(`${p}/`))) return d.id;
  return null;
}
