<script setup lang="ts">
// What Vault's socket audit device streamed to the API's collector.
definePageMeta({ title: 'Audit' })
const door = ref<string>('')
const data = ref<any>(null)
const err = ref('')
async function load() {
  try { data.value = await api(`/audit?limit=100${door.value ? `&door=${door.value}` : ''}`); err.value = '' }
  catch (e) { err.value = errorText(e) }
}
usePolling(load, 5000)
watch(door, load)
const offline = computed(() => data.value && (!data.value.collector?.listening || !data.value.collector?.connections))
</script>

<template>
  <div class="rd-audit">
    <section class="vg-hero">
      <h2 class="rd-h">Vault's own record</h2>
      <p class="rd-sub">Every request and response, as Vault's audit device sent it. Tokens and values are HMAC'd by Vault — it never logs them in the clear.</p>
    </section>
    <p v-if="offline" class="inline-notice error" role="status">The audit collector has no connection from Vault right now. Vault keeps serving — its stdout audit device still records everything — but this feed has a gap until the collector reconnects.</p>
    <p v-if="err" class="inline-notice error">{{ err }}</p>
    <section class="vg-glass rd-panel">
      <div class="filter-bar">
        <label for="rd-door-filter">Door</label>
        <select id="rd-door-filter" v-model="door">
          <option value="">All doors</option>
          <option v-for="n in [1, 2, 3, 4, 5, 6, 7, 8]" :key="n" :value="String(n)">Door {{ n }}</option>
        </select>
        <span v-if="data">{{ data.collector.received }} received · {{ data.collector.stored }} stored · {{ data.collector.dropped }} dropped</span>
      </div>
      <div class="vg-table-wrap">
        <table class="vg-table">
          <thead><tr><th>Time</th><th>Type</th><th>Door</th><th>Operation · path</th><th>Who (display name)</th><th>Policies</th><th>Error</th></tr></thead>
          <tbody>
            <tr v-for="e in data?.entries ?? []" :key="e.id">
              <td class="vg-table__mono">{{ new Date(e.time).toLocaleTimeString() }}</td>
              <td>{{ e.type }}</td>
              <td>{{ e.door ?? '—' }}</td>
              <td class="vg-table__mono rd-path">{{ e.operation }} {{ e.namespace }}{{ e.path }}</td>
              <td class="vg-table__mono">{{ e.display_name ?? 'unauthenticated' }}</td>
              <td class="vg-table__mono">{{ (e.policies ?? []).join(', ') }}</td>
              <td class="rd-err">{{ e.error ? e.error.replace(/\s+/g, ' ').slice(0, 80) : '' }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>

<style scoped>
.rd-audit { display: grid; gap: 18px; max-width: 1360px; margin: 0 auto; }
.rd-h { margin: 0 0 6px; font-size: 24px; font-weight: 800; letter-spacing: -0.025em; }
.rd-sub { margin: 0; color: var(--vg-text-secondary); max-width: 70ch; }
.rd-panel { padding: 16px 20px; display: grid; gap: 12px; }
.rd-path { max-width: 40ch; overflow-wrap: anywhere; }
.rd-err { color: var(--vg-critical); font-size: 12px; max-width: 30ch; }
.filter-bar label { font-size: 12.5px; font-weight: 600; color: var(--vg-text-secondary); }
</style>
