// Cluster view: what the Cluster page shows, read live.
//
// The API's Vault token lives in the `red-doors` namespace, so root-only
// endpoints (licence status, seal-token lookup, Raft configuration) are out
// of its reach by design. Per node it uses Vault's UNAUTHENTICATED
// sys/health + sys/leader (direct pod DNS) and Kubernetes pod status.
import fs from 'node:fs';
import https from 'node:https';
import { vaultRequest } from './vault.js';

const K8S = 'https://kubernetes.default.svc';
const SA = '/var/run/secrets/kubernetes.io/serviceaccount';
const k8sCa = fs.existsSync(`${SA}/ca.crt`) ? fs.readFileSync(`${SA}/ca.crt`) : undefined;

function k8s(path) {
  const token = fs.readFileSync(`${SA}/token`, 'utf8').trim();
  return new Promise((resolve, reject) => {
    https
      .get(`${K8S}${path}`, { ca: k8sCa, headers: { Authorization: `Bearer ${token}` }, timeout: 5000 }, (res) => {
        let raw = '';
        res.on('data', (c) => (raw += c));
        res.on('end', () => (res.statusCode === 200 ? resolve(JSON.parse(raw)) : reject(new Error(`k8s ${res.statusCode} ${path}`))));
      })
      .on('error', reject);
  });
}

const health = (base) =>
  vaultRequest('GET', 'sys/health?standbyok=true&perfstandbyok=true&sealedcode=200&uninitcode=200', { base, namespace: '', timeout: 3000 });
const leader = (base) => vaultRequest('GET', 'sys/leader', { base, namespace: '', timeout: 3000 });

async function node(name) {
  const base = `https://${name}.vault-internal.rd-vault.svc:8200`;
  const out = { name, reachable: false };
  try {
    const [h, l] = await Promise.all([health(base), leader(base)]);
    Object.assign(out, {
      reachable: true,
      initialized: h.initialized,
      sealed: h.sealed,
      role: h.sealed ? 'sealed' : l.is_self ? 'leader' : 'standby',
      version: h.version,
      license_expiry: h.license?.expiry_time ?? null,
      raft_committed_index: l.raft_committed_index ?? null,
      raft_applied_index: l.raft_applied_index ?? null,
      leader_address: l.leader_address || null,
    });
  } catch (err) {
    out.error = String(err.message);
  }
  return out;
}

async function pods(ns, selector) {
  try {
    const list = await k8s(`/api/v1/namespaces/${ns}/pods?labelSelector=${encodeURIComponent(selector)}`);
    return list.items.map((p) => ({
      name: p.metadata.name,
      phase: p.status.phase,
      ready: (p.status.conditions ?? []).some((c) => c.type === 'Ready' && c.status === 'True'),
      restarts: (p.status.containerStatuses ?? []).reduce((n, c) => n + c.restartCount, 0),
      started: p.status.startTime,
      labels: p.metadata.labels,
    }));
  } catch (err) {
    return { error: String(err.message) };
  }
}

export async function clusterStatus() {
  const [nodes, seal, vaultPods, sealPods, openers, vss] = await Promise.all([
    Promise.all(['vault-0', 'vault-1', 'vault-2'].map(node)),
    vaultRequest('GET', 'sys/seal-status', { base: 'https://vault-seal.rd-vault-seal.svc:8200', namespace: '', timeout: 3000 })
      .then((s) => ({ reachable: true, sealed: s.sealed, type: s.type, version: s.version, initialized: s.initialized }))
      .catch((e) => ({ reachable: false, error: String(e.message) })),
    pods('rd-vault', 'app.kubernetes.io/name=vault'),
    pods('rd-vault-seal', 'app.kubernetes.io/name=vault'),
    pods('rd-doors', 'app=opener'),
    k8s('/apis/secrets.hashicorp.com/v1beta1/namespaces/rd-doors/vaultstaticsecrets/door-7-customer-db')
      .then((v) => ({
        name: v.metadata.name,
        path: `${v.spec.mount}/${v.spec.path}`,
        refresh_after: v.spec.refreshAfter,
        last_generation: v.status?.lastGeneration ?? null,
        secret_mac: v.status?.secretMAC ? `${v.status.secretMAC.slice(0, 12)}…` : null,
        conditions: v.status?.conditions ?? [],
      }))
      .catch((e) => ({ error: String(e.message) })),
  ]);
  const lead = nodes.find((n) => n.role === 'leader');
  return {
    observed_at: new Date().toISOString(),
    seal_chain: {
      seal_vault: { ...seal, pods: sealPods },
      main_seal_type: 'transit (key autounseal on the seal Vault)',
      note: 'seal-token TTL and Raft configuration are root-namespace endpoints — see `make vault-status`',
    },
    vault: {
      leader: lead?.name ?? null,
      unsealed: nodes.filter((n) => n.reachable && !n.sealed).length,
      total: nodes.length,
      license_expiry: lead?.license_expiry ?? nodes.find((n) => n.license_expiry)?.license_expiry ?? null,
      nodes,
      pods: vaultPods,
    },
    openers,
    vso_door_7: vss,
  };
}
