<script setup lang="ts">
// A door plus what you can do with it. The door's state follows Vault's
// answer: opened → swing, denied → bolt, pending → seal. Nothing is decided
// here; everything shown comes from the API's response.
import { Hand, KeyRound, ShieldAlert, Send, ArrowRight } from 'lucide-vue-next'

const props = withDefaults(defineProps<{ door: any, size?: 'lg' | 'md' }>(), { size: 'lg' })
const emit = defineEmits<{ result: [any] }>()
const { user, readOnly } = useSession()

type DoorState = 'closed' | 'knocking' | 'opening' | 'open' | 'refused' | 'pending'
const state = ref<DoorState>('closed')
const result = ref<any>(null)
const busy = ref(false)
const error = ref('')

function settle(r: any) {
  result.value = r
  emit('result', r)
  if (r.outcome === 'opened') {
    state.value = 'opening'
    setTimeout(() => (state.value = 'open'), 260)
  }
  else if (r.outcome === 'pending') state.value = 'pending'
  else state.value = 'refused'
}

async function run(fn: () => Promise<any>) {
  if (busy.value) return
  busy.value = true
  error.value = ''
  state.value = 'knocking'
  try {
    const [r] = await Promise.all([fn(), new Promise(res => setTimeout(res, 900))])
    settle(r)
  }
  catch (e) {
    state.value = 'closed'
    error.value = errorText(e)
  }
  finally {
    busy.value = false
  }
}

const isMachine = computed(() => props.door.kind === 'machine')
const knock = () => isMachine.value && run(() => api(`/doors/${props.door.id}/knock`, { method: 'POST', body: { as: 'owner' } }))
const wrongKey = () => isMachine.value && run(() => api(`/doors/${props.door.id}/knock`, { method: 'POST', body: { as: 'impostor' } }))
const openAsMe = () => run(() => api('/doors/2/open', { method: 'POST' }))
const requestCodes = () => run(() => api('/doors/8/requests', { method: 'POST' }))
const reset = () => { state.value = 'closed'; result.value = null; error.value = '' }

defineExpose({ knock, wrongKey, reset, primary: () => (props.door.id === 2 ? openAsMe() : props.door.id === 8 ? requestCodes() : knock()) })
watch(() => props.door.id, reset)
</script>

<template>
  <div class="rd-stage">
    <RedDoor :number="door.id" :method="door.method.split(' (')[0].split(' — ')[0]" :title="door.title" :state="state" :size="size">
      <template #room>
        <div class="rd-stage__room">
          <strong>{{ door.title }}</strong>
          <span>{{ result?.outcome === 'opened' ? 'released — see below' : '' }}</span>
        </div>
      </template>
    </RedDoor>

    <div class="rd-stage__actions">
      <template v-if="isMachine">
        <button class="primary-button" type="button" :disabled="busy || readOnly" @click="knock">
          <Hand :size="15" aria-hidden="true" /> Knock
        </button>
        <button class="secondary-button" type="button" :disabled="busy || readOnly" @click="wrongKey">
          <ShieldAlert :size="15" aria-hidden="true" /> Try the wrong key
        </button>
      </template>
      <template v-else-if="door.id === 2">
        <button class="primary-button" type="button" :disabled="busy" @click="openAsMe">
          <KeyRound :size="15" aria-hidden="true" /> Open as {{ user?.username }}
        </button>
      </template>
      <template v-else-if="door.id === 8">
        <button v-if="user?.roles.requester" class="primary-button" type="button" :disabled="busy" @click="requestCodes">
          <Send :size="15" aria-hidden="true" /> Request the launch codes
        </button>
        <NuxtLink class="secondary-button" to="/approvals">Approvals <ArrowRight :size="15" aria-hidden="true" /></NuxtLink>
      </template>
      <p v-if="readOnly && isMachine" class="rd-stage__hint">Auditors are read-only here — sign in as ada to knock.</p>
      <p v-if="door.id === 2" class="rd-stage__hint">Vault decides with <em>your</em> token: board members open it; others are refused.</p>
      <p v-if="door.id === 8 && !user?.roles.requester" class="rd-stage__hint">Only requesters (cleo, eve) can ask; approvers act on the Approvals page.</p>
    </div>

    <div class="rd-stage__status" aria-live="polite">
      <OutcomePill v-if="result" :outcome="result.outcome" />
      <span v-if="busy" class="rd-stage__busy">Knocking…</span>
      <p v-if="error" class="inline-notice error">{{ error }}</p>
      <p v-if="result?.outcome === 'pending'" class="rd-stage__hint">Your request is waiting for a second person. It stays in your session — open it from <NuxtLink to="/approvals">Approvals</NuxtLink> once approved.</p>
    </div>
  </div>
</template>

<style scoped>
.rd-stage { display: grid; justify-items: center; gap: 14px; }
.rd-stage__room { display: grid; gap: 4px; font-size: 12px; text-align: right; color: var(--vg-text-primary); }
.rd-stage__actions { display: flex; flex-wrap: wrap; gap: 10px; justify-content: center; }
.rd-stage__actions .secondary-button { text-decoration: none; }
.rd-stage__hint { flex-basis: 100%; margin: 0; text-align: center; font-size: 12.5px; color: var(--vg-text-secondary); max-width: 44ch; justify-self: center; }
.rd-stage__status { display: grid; justify-items: center; gap: 8px; min-height: 26px; }
.rd-stage__busy { font-size: 12.5px; color: var(--vg-text-secondary); }
</style>
