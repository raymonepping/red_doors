<script setup lang="ts">
// The Vault audit records for one attempt, joined by request id.
import { ScrollText, X } from 'lucide-vue-next'
const props = defineProps<{ attemptId: string | null }>()
const open = ref(false)
const data = ref<any>(null)
const err = ref('')
async function show() {
  open.value = true
  err.value = ''
  data.value = null
  try { data.value = await api(`/attempts/${props.attemptId}`) }
  catch (e) { err.value = errorText(e) }
}
const hmac = (raw: any) => JSON.stringify(raw, null, 2)
</script>

<template>
  <button class="secondary-button" type="button" :disabled="!attemptId" @click="show">
    <ScrollText :size="15" aria-hidden="true" /> Vault audit entries
  </button>
  <Teleport to="body">
    <div v-if="open" class="vg-drawer-backdrop" @click="open = false" />
    <aside v-if="open" class="vg-drawer" role="dialog" aria-modal="true" aria-labelledby="rd-audit-h">
      <div class="vg-drawer__header">
        <h2 id="rd-audit-h" class="vg-drawer__title">Vault audit entries</h2>
        <button class="vg-btn vg-btn--ghost" type="button" aria-label="Close" @click="open = false"><X :size="16" /></button>
      </div>
      <div class="vg-drawer__body">
        <p class="rd-note">Joined by Vault request id. Fields marked <code class="vg-mono">hmac-sha256:</code> are HMAC'd by Vault — it never logs the value.</p>
        <p v-if="err" class="inline-notice error">{{ err }}</p>
        <p v-else-if="!data" class="state-loading">Loading…</p>
        <p v-else-if="!data.audit.length" class="rd-note">No audit entries joined yet{{ data.collector?.listening ? ' — they arrive within a second or two; reopen.' : ' — the audit collector is offline.' }}</p>
        <article v-for="e in data?.audit ?? []" :key="e.id" class="rd-entry">
          <header>
            <span class="vg-pill" :class="e.error ? 'vg-pill--rejected' : 'vg-pill--local'">{{ e.type }}</span>
            <code class="vg-mono">{{ e.operation }} {{ e.path }}</code>
          </header>
          <p class="rd-entry__meta">{{ new Date(e.time).toLocaleTimeString() }} · {{ e.display_name || 'unauthenticated' }} · {{ (e.policies ?? []).join(', ') || 'no policies' }}</p>
          <p v-if="e.error" class="rd-entry__err">{{ e.error.replace(/\s+/g, ' ') }}</p>
          <details><summary>Raw record</summary><pre class="rd-raw">{{ hmac(e.raw) }}</pre></details>
        </article>
      </div>
    </aside>
  </Teleport>
</template>

<style scoped>
.rd-note { font-size: 12.5px; color: var(--vg-text-secondary); margin: 0 0 12px; }
.rd-entry { padding: 12px 0; border-bottom: 1px solid var(--vg-border-subtle); display: grid; gap: 6px; }
.rd-entry header { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; font-size: 12.5px; }
.rd-entry__meta { margin: 0; font-size: 12px; color: var(--vg-text-muted); }
.rd-entry__err { margin: 0; font-size: 12.5px; color: var(--vg-critical); }
.rd-entry summary { cursor: pointer; font-size: 12px; color: var(--vg-text-secondary); }
.rd-raw { margin: 6px 0 0; padding: 10px; border-radius: 8px; max-height: 320px; overflow: auto; font-family: var(--font-mono); font-size: 11.5px; background: var(--vg-well); box-shadow: inset 0 0 0 1px var(--vg-border-subtle); }
</style>
