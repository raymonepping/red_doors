// Minimal Vault HTTP client: TLS with the project CA, optional client
// certificate (door 5), Enterprise namespace header. Every response carries
// Vault's request_id so the API can join it to the audit stream.
import fs from 'node:fs';
import https from 'node:https';

const ADDR = new URL(process.env.VAULT_ADDR ?? 'https://vault-active.rd-vault.svc:8200');
const NAMESPACE = process.env.VAULT_NAMESPACE ?? 'red-doors';
const CA_FILE = process.env.VAULT_CACERT ?? '/ca/ca.crt';
const CA = fs.existsSync(CA_FILE) ? fs.readFileSync(CA_FILE) : undefined;

export class VaultError extends Error {
  constructor(status, errors, path) {
    super(`${status} ${path}: ${errors.join('; ')}`);
    this.status = status;
    this.errors = errors;
    this.path = path;
  }
}

/**
 * Call Vault. Returns the parsed JSON body (or {} for 204).
 * @param {string} method
 * @param {string} path      e.g. "auth/kubernetes/login" (no /v1/)
 * @param {{token?: string, body?: object, cert?: string, key?: string}} [opts]
 */
export function vault(method, path, { token, body, cert, key } = {}) {
  const payload = body === undefined ? undefined : JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: ADDR.hostname,
        port: ADDR.port || 443,
        path: `/v1/${path}`,
        method,
        ca: CA,
        // door 5: the client certificate IS the credential, presented in the TLS handshake
        cert,
        key,
        headers: {
          'X-Vault-Namespace': NAMESPACE,
          ...(token ? { 'X-Vault-Token': token } : {}),
          ...(payload ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) } : {}),
        },
        timeout: 10_000,
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

export const vaultAddress = ADDR.origin;
export const vaultNamespace = NAMESPACE;
