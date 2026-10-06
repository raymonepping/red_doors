<script setup lang="ts">
// The trust chain and the cluster, read live every 5 s.
import { ArrowRight, Lock, KeyRound } from 'lucide-vue-next'
definePageMeta({ title: 'Cluster' })
const c = ref<any>(null)
const err = ref('')
async function load() {
  try { c.value = await api('/cluster'); err.value = '' }
  catch (e) { err.value = errorText(e) }
}
usePolling(load, 5000)
const seal = computed(() => c.value?.seal_chain?.seal_vault)
</script>

<template>
  <div class="rd-cl">
    <section class="vg-hero">
      <h2 class="rd-h">Seal chain and cluster</h2>
      <p class="rd-sub">The seal Vault is the root of trust: an operator unseals it; it unseals the main cluster through Transit. Killing the leader moves leadership; the doors keep opening.</p>
    </section>
    <p v-if="err" class="inline-notice error">{{ err }}</p>

    <section v-if="c" class="vg-glass rd-panel" aria-label="Seal chain">
      <div class="vg-section-header"><h2 class="vg-section-title">Seal chain</h2><span class="rd-obs">observed {{ new Date(c.observed_at).toLocaleTimeString() }}</span></div>
      <div class="rd-chain">
        <div class="rd-node rd-node--root">
          <KeyRound :size="18" aria-hidden="true" />
          <strong>Operator</strong>
          <span>Shamir key in .secrets/ (make vault-unseal)</span>
        </div>
        <ArrowRight class="rd-arrow" aria-hidden="true" />
        <div class="rd-node" :data-sealed="seal?.sealed">
          <Lock :size="18" aria-hidden="true" />
          <strong>Seal Vault</strong>
          <span>rd-vault-seal · {{ seal?.version ?? '—' }}</span>
          <span class="vg-pill" :class="seal?.reachable && !seal?.sealed ? 'vg-pill--healthy' : 'vg-pill--rejected'">{{ !seal?.reachable ? 'unreachable' : seal?.sealed ? 'SEALED — run make vault-unseal' : 'unsealed' }}</span>
        </div>
        <ArrowRight class="rd-arrow" aria-hidden="true" />
        <div class="rd-node rd-node--wide">
          <strong>Transit key autounseal</strong>
          <span>periodic orphan token, policy autounseal (encrypt/decrypt only)</span>
          <span class="rd-small">{{ c.seal_chain.note }}</span>
        </div>
        <ArrowRight class="rd-arrow" aria-hidden="true" />
        <div class="rd-nodes">
          <div v-for="n in c.vault.nodes" :key="n.name" class="rd-node" :data-role="n.role">
            <strong>{{ n.name }}</strong>
            <span class="vg-pill" :class="!n.reachable ? 'vg-pill--rejected' : n.sealed ? 'vg-pill--rejected' : n.role === 'leader' ? 'vg-pill--approved' : 'vg-pill--healthy'">
              {{ !n.reachable ? 'unreachable' : n.sealed ? 'sealed' : n.role === 'leader' ? 'leader' : 'standby' }}
            </span>
            <span class="vg-mono rd-small">{{ n.version ?? '' }} · raft {{ n.raft_applied_index ?? '—' }}</span>
          </div>
        </div>
      </div>
    </section>

    <div v-if="c" class="vg-grid-3">
      <section class="vg-tile">
        <span class="vg-tile__label">Main cluster</span>
        <span class="vg-tile__value">{{ c.vault.unsealed }}/{{ c.vault.total }}</span>
        <span class="vg-tile__sub">unsealed · leader {{ c.vault.leader ?? 'none' }}</span>
      </section>
      <section class="vg-tile vg-tile--gold">
        <span class="vg-tile__label">Licence</span>
        <span class="vg-tile__value rd-lic">{{ c.vault.license_expiry ? new Date(c.vault.license_expiry).toLocaleDateString() : '—' }}</span>
        <span class="vg-tile__sub">Vault Enterprise expiry</span>
      </section>
      <section class="vg-tile">
        <span class="vg-tile__label">Audit collector</span>
        <span class="vg-tile__value">{{ c.audit_collector.connections }}</span>
        <span class="vg-tile__sub">connections from Vault · {{ c.audit_collector.received }} records</span>
      </section>
    </div>

    <div v-if="c" class="vg-grid-2">
      <section class="vg-glass rd-panel">
        <div class="vg-section-header"><h2 class="vg-section-title">Door openers</h2></div>
        <ul class="rd-list">
          <li v-for="p in (Array.isArray(c.openers) ? c.openers : [])" :key="p.name">
            <span class="vg-mono">{{ p.labels?.['red-doors/opener'] ? `opener-${p.labels['red-doors/opener']}` : p.name }}</span>
            <span class="vg-pill" :class="p.ready ? 'vg-pill--healthy' : 'vg-pill--rejected'">{{ p.ready ? 'ready' : p.phase }}</span>
            <span class="rd-small">{{ p.restarts }} restarts</span>
          </li>
        </ul>
      </section>
      <section class="vg-glass rd-panel">
        <div class="vg-section-header"><h2 class="vg-section-title">Vault Secrets Operator — door 7</h2></div>
        <p class="rd-small">Syncs <code class="vg-mono">{{ c.vso_door_7.path }}</code> into Secret <code class="vg-mono">rd-doors/door-7-customer-db</code> every {{ c.vso_door_7.refresh_after }}.</p>
        <p class="rd-small">Last generation {{ c.vso_door_7.last_generation ?? '—' }} · secret MAC <span class="vg-mono">{{ c.vso_door_7.secret_mac ?? '—' }}</span></p>
      </section>
    </div>
  </div>
</template>

<style scoped>
.rd-cl { display: grid; gap: 18px; max-width: 1360px; margin: 0 auto; }
.rd-h { margin: 0 0 6px; font-size: 24px; font-weight: 800; letter-spacing: -0.025em; }
.rd-sub { margin: 0; color: var(--vg-text-secondary); max-width: 70ch; }
.rd-panel { padding: 16px 20px; display: grid; gap: 12px; }
.rd-obs, .rd-small { font-size: 12px; color: var(--vg-text-muted); }
.rd-chain { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.rd-arrow { color: var(--vg-text-muted); flex-shrink: 0; }
.rd-node { display: grid; gap: 4px; justify-items: start; padding: 12px 14px; border-radius: 12px; background: var(--vg-well); box-shadow: inset 0 0 0 1px var(--vg-border-subtle); font-size: 12.5px; min-width: 150px; }
.rd-node strong { font-size: 14px; }
.rd-node--wide { max-width: 230px; }
.rd-node[data-role='leader'] { box-shadow: inset 0 0 0 2px color-mix(in srgb, var(--vg-hue-blue) 45%, transparent); }
.rd-nodes { display: flex; gap: 10px; flex-wrap: wrap; }
.rd-lic { font-size: 22px; }
.rd-list { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
.rd-list li { display: flex; gap: 10px; align-items: center; font-size: 13px; }
</style>
