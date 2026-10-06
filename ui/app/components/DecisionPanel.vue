<script setup lang="ts">
// "How Vault decided" — numbered steps, all taken from what Vault reported.
// Missing data reads "not reported"; nothing is inferred.
import { Check, X } from 'lucide-vue-next'
const props = defineProps<{
  result: any
  policyTexts?: { name: string, text: string | null }[]
  egp?: { name: string, text: string | null }[]
}>()
const r = computed(() => props.result ?? {})
const v = computed(() => r.value.vault ?? r.value.decision ?? {})
const policies = computed<string[]>(() => [...new Set([...(v.value.policies ?? []), ...(v.value.identity_policies ?? [])])])
const shownTexts = computed(() => (props.policyTexts ?? []).filter(p => p.text && (policies.value.includes(p.name) || r.value.outcome === 'denied')))
const ttl = (s?: number | null) => (s == null ? 'not reported' : s >= 3600 ? `${Math.round(s / 360) / 10} h` : s >= 60 ? `${Math.round(s / 6) / 10} min` : `${s} s`)
</script>

<template>
  <section class="vg-glass rd-decision" aria-labelledby="rd-decision-h">
    <div class="vg-section-header"><h2 id="rd-decision-h" class="vg-section-title">How Vault decided</h2></div>
    <ol class="rd-steps">
      <li>
        <span class="rd-steps__k">Identity</span>
        <span class="rd-steps__v vg-mono">{{ r.identity?.subject ?? 'not reported' }}</span>
      </li>
      <li>
        <span class="rd-steps__k">Auth method</span>
        <span class="rd-steps__v">{{ r.identity?.method ?? 'not reported' }}<template v-if="r.identity?.role"> — role <code class="vg-mono">{{ r.identity.role }}</code></template></span>
      </li>
      <li v-if="r.identity?.groups?.length">
        <span class="rd-steps__k">Groups (LDAP → Keycloak → Vault)</span>
        <span class="rd-steps__v">{{ r.identity.groups.join(', ') }}</span>
      </li>
      <li>
        <span class="rd-steps__k">Policies attached</span>
        <span class="rd-steps__v vg-mono">{{ policies.length ? policies.join(', ') : 'not reported' }}</span>
      </li>
      <li v-if="r.certificate">
        <span class="rd-steps__k">Client certificate</span>
        <span class="rd-steps__v vg-mono">serial {{ r.certificate.serial.slice(0, 23) }}… · not after {{ new Date(r.certificate.not_after).toLocaleTimeString() }}</span>
      </li>
      <li v-if="r.wrapping">
        <span class="rd-steps__k">Wrapped secret-id</span>
        <span class="rd-steps__v">created at <code class="vg-mono">{{ r.wrapping.creation_path }}</code>, TTL {{ ttl(r.wrapping.creation_ttl) }}, unwrapped once</span>
      </li>
      <li>
        <span class="rd-steps__k">Token</span>
        <span class="rd-steps__v">TTL {{ ttl(v.token_ttl ?? v.ttl) }}<template v-if="v.revoked_after_use"> · revoked right after use</template></span>
      </li>
      <li class="rd-steps__outcome" :data-outcome="r.outcome">
        <span class="rd-steps__k">Outcome</span>
        <span class="rd-steps__v">
          <OutcomePill v-if="r.outcome" :outcome="r.outcome" />
          <span v-if="r.denial" class="rd-denial">
            <X :size="14" aria-hidden="true" />
            {{ r.denial.status ? `HTTP ${r.denial.status} at step "${r.denial.step}": ` : '' }}{{ (r.denial.errors ?? []).join(' · ').replace(/\s+/g, ' ').trim() }}
          </span>
          <span v-else-if="r.outcome === 'opened'" class="rd-allow"><Check :size="14" aria-hidden="true" />Every step allowed by policy</span>
        </span>
      </li>
      <li v-if="r.encrypt_attempt">
        <span class="rd-steps__k">Same identity tries to encrypt</span>
        <span class="rd-steps__v">{{ r.encrypt_attempt.allowed ? 'allowed (!)' : `refused by Vault — HTTP ${r.encrypt_attempt.status}` }}</span>
      </li>
    </ol>

    <div v-if="shownTexts.length || egp?.length" class="rd-policies">
      <details v-for="p in shownTexts" :key="p.name" open>
        <summary>Policy <code class="vg-mono">{{ p.name }}</code> — as Vault holds it</summary>
        <pre class="rd-code">{{ p.text }}</pre>
      </details>
      <details v-for="p in egp ?? []" :key="p.name">
        <summary>Sentinel EGP <code class="vg-mono">{{ p.name }}</code></summary>
        <pre class="rd-code">{{ p.text }}</pre>
      </details>
    </div>
  </section>
</template>

<style scoped>
.rd-decision { padding: 18px 20px; min-width: 0; }
.rd-decision :deep(details), .rd-policies { min-width: 0; max-width: 100%; }
.rd-steps { list-style: none; counter-reset: step; margin: 0; padding: 0; display: grid; gap: 10px; }
.rd-steps li { counter-increment: step; display: grid; grid-template-columns: 26px 1fr; column-gap: 10px; row-gap: 2px; align-items: baseline; }
.rd-steps li::before {
  content: counter(step); grid-row: span 2; align-self: start;
  width: 22px; height: 22px; border-radius: 50%; display: grid; place-items: center;
  font-size: 11.5px; font-weight: 750; color: var(--vg-text-primary);
  background: rgba(255, 255, 255, 0.85); box-shadow: inset 0 0 0 1px var(--vg-border-strong);
}
.rd-steps__k { font-size: 11.5px; font-weight: 700; letter-spacing: 0.05em; text-transform: uppercase; color: var(--vg-text-muted); }
.rd-steps__v { font-size: 13.5px; color: var(--vg-text-primary); overflow-wrap: anywhere; display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.rd-denial, .rd-allow { display: inline-flex; gap: 6px; align-items: baseline; font-size: 13px; }
.rd-denial { color: var(--vg-critical); }
.rd-allow { color: var(--vg-healthy); }
.rd-policies { margin-top: 16px; display: grid; gap: 8px; }
.rd-policies summary { cursor: pointer; font-size: 13px; font-weight: 600; color: var(--vg-text-secondary); }
.rd-code {
  margin: 8px 0 0; padding: 12px 14px; border-radius: 10px; overflow-x: auto; max-width: 100%; white-space: pre-wrap; overflow-wrap: anywhere;
  font-family: var(--font-mono); font-size: 12px; line-height: 1.55; color: var(--vg-text-primary);
  background: var(--vg-well); box-shadow: inset 0 0 0 1px var(--vg-border-subtle);
}
</style>
