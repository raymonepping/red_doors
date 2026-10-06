<script setup lang="ts">
// One door: the door and its room, how Vault decided, who knocked, the audit trail.
definePageMeta({ title: 'Door' })
const route = useRoute()
const id = computed(() => Number(route.params.id))
const detail = ref<any>(null)
const result = ref<any>(null)
const err = ref('')
async function load() {
  try { detail.value = await api(`/doors/${id.value}`) }
  catch (e) { err.value = errorText(e) }
}
onMounted(load)
watch(id, () => { result.value = null; load() })
function onResult(r: any) { result.value = r; load() }
useHead(() => ({ title: detail.value ? `Door ${detail.value.id} — ${detail.value.title} · Red Doors` : 'Red Doors' }))
</script>

<template>
  <div v-if="detail" class="rd-detail">
    <section class="vg-hero rd-detail__hero">
      <RedDoor :number="detail.id" :method="detail.method" size="sm" :state="result?.outcome === 'opened' ? 'open' : 'closed'" />
      <div>
        <h2>Door {{ detail.id }} — {{ detail.title }}</h2>
        <p>{{ detail.method }} · {{ detail.summary }}</p>
      </div>
    </section>

    <div class="rd-detail__body">
      <section class="vg-glass rd-detail__door">
        <DoorStage :door="detail" @result="onResult" />
        <dl class="rd-who">
          <dt>Owner</dt><dd>{{ detail.owner }}</dd>
          <dt>Wrong key</dt><dd>{{ detail.wrong_key }}</dd>
        </dl>
      </section>

      <div class="rd-detail__side">
        <section v-if="result?.released" class="vg-glass rd-panel"><RoomValue :released="result.released" :at="result.at" /></section>
        <section v-if="result" class="vg-glass rd-panel">
          <IdentityChips :triggered-by="result.triggered_by" :opened-by="result.identity" />
          <div><AuditDrawer :attempt-id="result.attempt_id" /></div>
        </section>
        <DecisionPanel :result="result ?? {}" :policy-texts="detail.policy_texts" :egp="detail.egp" />
      </div>
    </div>

    <section class="vg-glass rd-panel">
      <div class="vg-section-header"><h2 class="vg-section-title">Recent attempts at this door</h2></div>
      <div class="vg-table-wrap">
        <table class="vg-table">
          <thead><tr><th>When</th><th>Mode</th><th>Triggered by</th><th>Opened by</th><th>Outcome</th><th>Vault's reason</th></tr></thead>
          <tbody>
            <tr v-for="a in detail.attempts" :key="a.id">
              <td class="vg-table__mono">{{ new Date(a.created_at).toLocaleTimeString() }}</td>
              <td>{{ a.mode }}</td>
              <td>{{ a.triggered_by ?? 'not reported' }}</td>
              <td class="vg-table__mono">{{ a.opened_by?.subject ?? '—' }}</td>
              <td><OutcomePill :outcome="a.outcome" /></td>
              <td class="rd-reason">{{ a.denial ? (a.denial.errors ?? []).join(' ').replace(/\s+/g, ' ').slice(0, 90) : '—' }}</td>
            </tr>
            <tr v-if="!detail.attempts.length"><td colspan="6">Nobody has knocked yet.</td></tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
  <p v-else-if="err" class="inline-notice error">{{ err }}</p>
  <p v-else class="state-loading">Loading…</p>
</template>

<style scoped>
.rd-detail { display: grid; gap: 18px; max-width: 1360px; margin: 0 auto; }
.rd-detail__hero { display: flex; gap: 18px; align-items: center; }
.rd-detail__hero h2 { margin: 0 0 4px; font-size: 22px; font-weight: 800; letter-spacing: -0.02em; }
.rd-detail__hero p { margin: 0; color: var(--vg-text-secondary); }
.rd-detail__body { display: grid; grid-template-columns: minmax(300px, 420px) 1fr; gap: 18px; align-items: start; }
.rd-detail__door { padding: 20px; display: grid; gap: 16px; }
.rd-detail__side { display: grid; gap: 14px; }
.rd-panel { padding: 16px 20px; display: grid; gap: 12px; }
.rd-who { margin: 0; display: grid; grid-template-columns: max-content 1fr; gap: 4px 12px; font-size: 13px; }
.rd-who dt { color: var(--vg-text-muted); }
.rd-who dd { margin: 0; }
.rd-reason { font-size: 12.5px; color: var(--vg-text-secondary); max-width: 40ch; }
@media (max-width: 960px) { .rd-detail__body { grid-template-columns: 1fr; } }
</style>
