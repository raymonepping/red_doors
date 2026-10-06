<script setup lang="ts">
// Door 8 — two different people. Requesters ask and later open; approvers
// authorize; Vault (control group + Sentinel EGP) decides who counts.
import { Send, Check, DoorOpen } from 'lucide-vue-next'
definePageMeta({ title: 'Approvals' })
const { user } = useSession()
const data = ref<any>(null)
const busy = ref('')
const msg = ref<{ kind: 'ok' | 'error' | 'info', text: string } | null>(null)
const released = ref<any>(null)
async function load() { data.value = await api('/doors/8/requests').catch((e) => { msg.value = { kind: 'error', text: errorText(e) }; return null }) }
usePolling(load, 8000)

async function act(key: string, fn: () => Promise<any>) {
  busy.value = key
  msg.value = null
  try {
    const r = await fn()
    if (r.outcome === 'opened') { released.value = r.released; msg.value = { kind: 'ok', text: 'Opened — Vault released the launch codes once.' } }
    else if (r.outcome === 'denied') msg.value = { kind: 'error', text: `Refused by Vault: ${(r.denial?.errors ?? []).join(' ').replace(/\s+/g, ' ')}` }
    else if (r.explanation) msg.value = { kind: r.outcome === 'not_counted' ? 'info' : 'ok', text: r.explanation }
    else if (r.outcome === 'pending') msg.value = { kind: 'info', text: 'Requested. Vault returned a wrapped, pending answer — it is held in your server-side session until a different approver signs.' }
    await load()
  }
  catch (e) { msg.value = { kind: 'error', text: errorText(e) } }
  finally { busy.value = '' }
}
const request = () => act('request', () => api('/doors/8/requests', { method: 'POST' }))
const approve = (a: string) => act(`approve-${a}`, () => api(`/doors/8/requests/${encodeURIComponent(a)}/approve`, { method: 'POST' }))
const open = (a: string) => act(`open-${a}`, () => api(`/doors/8/requests/${encodeURIComponent(a)}/open`, { method: 'POST' }))
const left = (iso: string) => { const s = Math.round((Date.parse(iso) - Date.now()) / 1000); return s <= 0 ? 'expired' : s >= 60 ? `${Math.floor(s / 60)} min left` : `${s} s left` }
const status = (r: any) => (r.opened_at ? 'opened' : r.expired ? 'expired' : r.vault?.approved ? 'approved' : 'pending')
</script>

<template>
  <div class="rd-appr">
    <section class="vg-hero rd-appr__hero">
      <RedDoor :number="8" method="Two-person" size="sm" state="pending" />
      <div>
        <h2>Launch codes — two different people</h2>
        <p>A requester asks; Vault answers with a sealed, pending response. One member of <em>approvers</em> — not the requester — must authorize before it opens, once.</p>
      </div>
    </section>

    <p v-if="msg" class="inline-notice" :class="{ error: msg.kind === 'error' }" :data-kind="msg.kind" role="status">{{ msg.text }}</p>
    <section v-if="released" class="vg-glass rd-panel"><RoomValue :released="released" /></section>

    <section class="vg-glass rd-panel">
      <div class="vg-section-header">
        <h2 class="vg-section-title">{{ data?.viewer?.approver ? 'Requests (you can approve others’ requests)' : 'Your requests' }}</h2>
        <button v-if="user?.roles.requester" class="primary-button" type="button" :disabled="busy === 'request'" @click="request">
          <Send :size="15" aria-hidden="true" /> Request the launch codes
        </button>
      </div>
      <p v-if="user?.roles.auditor && !user.roles.approver && !user.roles.requester" class="rd-note">You are an auditor: you can see that this workflow exists, not take part in it.</p>
      <div class="vg-table-wrap">
        <table class="vg-table">
          <thead><tr><th>Requested by</th><th>When</th><th>Lifetime</th><th>Vault status</th><th>Approved by</th><th>Action</th></tr></thead>
          <tbody>
            <tr v-for="r in data?.requests ?? []" :key="r.accessor" :class="{ 'rd-row--pending': status(r) === 'pending' }">
              <td><strong>{{ r.requester_name }}</strong><span v-if="r.mine" class="rd-you">you</span></td>
              <td class="vg-table__mono">{{ new Date(r.created_at).toLocaleTimeString() }}</td>
              <td>{{ r.opened_at ? '—' : left(r.expires_at) }}</td>
              <td>
                <OutcomePill :outcome="status(r) === 'expired' ? 'error' : status(r) === 'opened' ? 'opened' : status(r) === 'approved' ? 'approved' : 'pending'" />
                <span v-if="r.self_approval_present && !r.vault?.approved" class="rd-self">self-approval recorded, not counted</span>
              </td>
              <td>{{ r.vault?.authorizations?.map((a: any) => a.name).join(', ') || (r.vault ? 'nobody yet' : '—') }}</td>
              <td class="rd-actions">
                <button v-if="data?.viewer?.approver && !r.opened_at && !r.expired" class="vg-btn vg-btn--approve" type="button" :disabled="busy === `approve-${r.accessor}`" @click="approve(r.accessor)">
                  <Check :size="14" aria-hidden="true" /> Approve
                </button>
                <button v-if="r.mine && r.can_open && !r.opened_at && !r.expired" class="primary-button" type="button" :disabled="busy === `open-${r.accessor}`" @click="open(r.accessor)">
                  <DoorOpen :size="14" aria-hidden="true" /> Open
                </button>
              </td>
            </tr>
            <tr v-if="data && !data.requests.length"><td colspan="6">No requests yet.</td></tr>
          </tbody>
        </table>
      </div>
      <p class="rd-note">Approving your own request is accepted by Vault but does not count: the Sentinel policy <code class="vg-mono">door-8-two-different-people</code> ignores it. A different approver has to sign.</p>
    </section>
  </div>
</template>

<style scoped>
.rd-appr { display: grid; gap: 18px; max-width: 1360px; margin: 0 auto; }
.rd-appr__hero { display: flex; gap: 18px; align-items: center; }
.rd-appr__hero h2 { margin: 0 0 4px; font-size: 22px; font-weight: 800; letter-spacing: -0.02em; }
.rd-appr__hero p { margin: 0; color: var(--vg-text-secondary); max-width: 70ch; }
.rd-panel { padding: 16px 20px; display: grid; gap: 12px; }
.rd-note { margin: 0; font-size: 12.5px; color: var(--vg-text-secondary); }
.rd-you { margin-left: 6px; font-size: 11px; padding: 1px 7px; border-radius: 999px; background: color-mix(in srgb, var(--vg-hue-blue) 12%, transparent); color: var(--vg-action-bright); }
.rd-self { display: block; margin-top: 4px; font-size: 11.5px; color: var(--vg-governance); }
.rd-row--pending td { background: color-mix(in srgb, var(--vg-hue-amber) 5%, transparent); }
.rd-actions { display: flex; gap: 8px; flex-wrap: wrap; }
.inline-notice[data-kind='info'] { background: var(--vg-pending-bg); color: var(--vg-governance); border-color: color-mix(in srgb, var(--vg-hue-amber) 30%, transparent); }
</style>
