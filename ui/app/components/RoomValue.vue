<script setup lang="ts">
// What Vault released, shown once. Mono only for the values themselves.
// Lifetimes count down from what Vault returned; they never fake a change.
const props = defineProps<{ released: Record<string, any> | null, at?: string }>()
const hidden = new Set(['item', 'rows', 'kv_version', 'lease_id', 'lease_ttl', 'revoked_at'])
const LABELS: Record<string, string> = { db_username: 'Database login (minted for this knock)', row_count: 'Rows in payroll', key_id: 'Key ID', api_key: 'API key', limit_eur: 'Limit (EUR)', file_mtime: 'Synced into the pod at', plaintext: 'Plaintext', ciphertext: 'Stored ciphertext', key_version: 'Key version' }
const fields = computed(() => Object.entries(props.released ?? {}).filter(([k, v]) => !hidden.has(k) && v !== null && typeof v !== 'object'))
const label = (k: string) => LABELS[k] ?? k.replace(/_/g, ' ')
const now = ref(Date.now())
let t: ReturnType<typeof setInterval> | undefined
onMounted(() => (t = setInterval(() => (now.value = Date.now()), 1000)))
onBeforeUnmount(() => clearInterval(t))
const leaseLeft = computed(() => {
  const ttl = props.released?.lease_ttl
  if (!ttl || !props.at) return null
  return Math.max(0, Math.round(ttl - (now.value - Date.parse(props.at)) / 1000))
})
</script>

<template>
  <div class="rd-room">
    <p class="rd-room__item">{{ released?.item ?? 'Behind the door' }}</p>
    <dl class="rd-room__fields">
      <template v-for="[k, v] in fields" :key="k">
        <dt>{{ label(k) }}</dt>
        <dd :class="{ 'vg-mono': k !== 'plaintext' && k !== 'minutes' && k !== 'notice' }">{{ v }}</dd>
      </template>
    </dl>
    <p v-if="released?.revoked_at" class="rd-room__life">Database login revoked by the opener at {{ new Date(released.revoked_at).toLocaleTimeString() }} — the lease would have lasted {{ released.lease_ttl }} s.</p>
    <p v-else-if="leaseLeft !== null" class="rd-room__life">Lease: {{ leaseLeft > 0 ? `${leaseLeft} s left` : 'expired' }}</p>
    <div v-if="released?.rows?.length" class="vg-table-wrap rd-room__rows">
      <table class="vg-table">
        <caption class="visually-hidden">Payroll rows read with the minted login</caption>
        <thead><tr><th>ID</th><th>Name</th><th>Department</th><th>Monthly (EUR)</th><th>IBAN</th></tr></thead>
        <tbody>
          <tr v-for="row in released.rows" :key="row.employee_id">
            <td class="vg-table__mono">{{ row.employee_id }}</td><td>{{ row.name }}</td><td>{{ row.department }}</td>
            <td class="vg-table__mono">{{ row.monthly_salary_eur }}</td><td class="vg-table__mono">{{ row.iban_masked }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped>
.rd-room { display: grid; gap: 10px; }
.rd-room__item { margin: 0; font-size: 16px; font-weight: 750; letter-spacing: -0.01em; }
.rd-room__fields { margin: 0; display: grid; grid-template-columns: minmax(110px, max-content) 1fr; gap: 6px 14px; font-size: 13.5px; }
.rd-room__fields dt { color: var(--vg-text-muted); }
.rd-room__fields dt::first-letter { text-transform: uppercase; }
.rd-room__fields dd { margin: 0; color: var(--vg-text-primary); overflow-wrap: anywhere; }
.rd-room__life { margin: 0; font-size: 12.5px; color: var(--vg-text-secondary); }
.rd-room__rows { overflow-x: auto; }
.visually-hidden { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
</style>
