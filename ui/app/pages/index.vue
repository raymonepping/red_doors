<script setup lang="ts">
// The corridor — guided, in story order. Keyboard: ← → move · K knock · W wrong key · D decision panel.
definePageMeta({ title: 'Corridor' })
const doors = ref<any[]>([])
const focus = ref(0)
const results = useState<Record<number, any>>('rd-corridor-results', () => ({}))
const stage = ref<any>(null)
const details = ref<any>(null)
const decisionEl = ref<HTMLElement | null>(null)
const loadError = ref('')

onMounted(async () => {
  try { doors.value = (await api('/doors')).doors }
  catch (e) { loadError.value = errorText(e) }
})
const door = computed(() => doors.value[focus.value])
watch(door, async (d) => {
  details.value = null
  if (d) details.value = await api(`/doors/${d.id}`).catch(() => null)
}, { immediate: false })
const opened = computed(() => Object.values(results.value).filter((r: any) => r?.outcome === 'opened').length)
const current = computed(() => (door.value ? results.value[door.value.id] : null))
function onResult(r: any) { if (door.value) results.value = { ...results.value, [door.value.id]: r } }
function move(n: number) { focus.value = Math.min(doors.value.length - 1, Math.max(0, focus.value + n)) }

function onKey(e: KeyboardEvent) {
  const tag = (e.target as HTMLElement)?.tagName
  if (tag === 'INPUT' || tag === 'TEXTAREA' || e.metaKey || e.ctrlKey || e.altKey) return
  if (e.key === 'ArrowRight') move(1)
  else if (e.key === 'ArrowLeft') move(-1)
  else if (e.key.toLowerCase() === 'k') stage.value?.primary()
  else if (e.key.toLowerCase() === 'w') stage.value?.wrongKey()
  else if (e.key.toLowerCase() === 'd') decisionEl.value?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  else return
  e.preventDefault()
}
onMounted(() => window.addEventListener('keydown', onKey))
onBeforeUnmount(() => window.removeEventListener('keydown', onKey))
const tilt = (i: number) => {
  const d = i - focus.value
  return { transform: `translateZ(${-Math.min(Math.abs(d), 3) * 40}px) rotateY(${Math.max(-24, Math.min(24, -d * 8))}deg) scale(${d === 0 ? 1 : 0.92})` }
}
</script>

<template>
  <div class="rd-corridor">
    <section class="vg-hero rd-corridor__hero">
      <div>
        <h2>Eight doors. Eight ways in.</h2>
        <p>Every door opens for exactly one kind of identity. Knock with the right one, then try the wrong key — the refusal comes from Vault, not from this screen.</p>
      </div>
      <div class="rd-corridor__progress" role="status">
        <span class="vg-tile__value">{{ opened }}<span class="rd-of">/8</span></span>
        <span>doors opened this session</span>
      </div>
    </section>

    <p v-if="loadError" class="inline-notice error">{{ loadError }}</p>

    <nav class="rd-hall vg-glass" aria-label="The corridor">
      <button v-for="(d, i) in doors" :key="d.id" type="button" class="rd-hall__door" :class="{ 'is-focus': i === focus }" :style="tilt(i)"
        :aria-current="i === focus ? 'step' : undefined" :aria-label="`Door ${d.id}: ${d.title} — ${d.method}`" @click="focus = i">
        <RedDoor :number="d.id" :method="d.method.split(' (')[0].split(' — ')[0]" size="sm"
          :state="results[d.id]?.outcome === 'opened' ? 'open' : results[d.id]?.outcome === 'denied' ? 'refused' : results[d.id]?.outcome === 'pending' ? 'pending' : 'closed'" />
        <span class="rd-hall__label">{{ d.title }}</span>
      </button>
    </nav>

    <div v-if="door" class="rd-corridor__body">
      <section class="vg-glass rd-corridor__door">
        <p class="rd-step">Door {{ door.id }} · step {{ door.story }} of 8 · {{ door.method }}</p>
        <h2 class="rd-title">{{ door.title }}</h2>
        <p class="rd-line">{{ NARRATIVE[door.id]?.line }}</p>
        <DoorStage ref="stage" :key="door.id" :door="door" @result="onResult" />
        <p class="rd-watch"><strong>Watch:</strong> {{ NARRATIVE[door.id]?.watch }}</p>
        <div class="rd-corridor__nav">
          <button class="vg-btn vg-btn--ghost" type="button" :disabled="focus === 0" @click="move(-1)">← Previous door</button>
          <NuxtLink class="vg-btn vg-btn--ghost" :to="`/doors/${door.id}`">Door details</NuxtLink>
          <button class="vg-btn vg-btn--ghost" type="button" :disabled="focus === doors.length - 1" @click="move(1)">Next door →</button>
        </div>
        <p class="rd-keys">Keys: <kbd>←</kbd> <kbd>→</kbd> move · <kbd>K</kbd> knock · <kbd>W</kbd> wrong key · <kbd>D</kbd> decision</p>
      </section>

      <div ref="decisionEl" class="rd-corridor__side">
        <section v-if="current?.released" class="vg-glass rd-panel">
          <RoomValue :released="current.released" :at="current.at" />
        </section>
        <section v-if="current" class="vg-glass rd-panel">
          <IdentityChips :triggered-by="current.triggered_by" :opened-by="current.identity" />
          <div class="rd-panel__row"><AuditDrawer :attempt-id="current.attempt_id" /></div>
        </section>
        <DecisionPanel v-if="current" :result="current" :policy-texts="details?.policy_texts" :egp="details?.egp" />
        <section v-else class="vg-glass rd-panel rd-empty">
          <p><strong>Nobody has knocked yet.</strong></p>
          <p>Owner: {{ door.owner }}</p>
          <p>Wrong key: {{ door.wrong_key }}</p>
        </section>
      </div>
    </div>
  </div>
</template>

<style scoped>
.rd-corridor { display: grid; gap: 18px; max-width: 1360px; margin: 0 auto; }
.rd-corridor__hero { display: flex; justify-content: space-between; gap: 24px; align-items: center; flex-wrap: wrap; }
.rd-corridor__hero h2 { margin: 0 0 6px; font-size: 24px; font-weight: 800; letter-spacing: -0.025em; }
.rd-corridor__hero p { margin: 0; max-width: 62ch; color: var(--vg-text-secondary); }
.rd-corridor__progress { display: grid; justify-items: end; font-size: 12.5px; color: var(--vg-text-muted); }
.rd-of { font-size: 18px; color: var(--vg-text-muted); }

.rd-hall { display: flex; justify-content: center; gap: clamp(6px, 1.6vw, 22px); padding: 18px 12px 12px; perspective: 900px; overflow-x: auto; }
.rd-hall__door {
  display: grid; justify-items: center; gap: 6px; padding: 8px 6px; min-width: 76px; border: 0; border-radius: 12px;
  background: transparent; cursor: pointer; transition: transform 300ms var(--vg-ease-out), background 180ms;
  font: inherit; color: var(--vg-text-secondary);
}
.rd-hall__door:hover { background: rgba(255, 255, 255, 0.55); }
.rd-hall__door.is-focus { background: rgba(255, 255, 255, 0.85); box-shadow: inset 0 0 0 1px var(--vg-border-subtle), 0 8px 20px -14px rgba(15, 26, 42, 0.5); color: var(--vg-text-primary); }
.rd-hall__door.is-focus :deep(.rd-door) { --w: 56px; }
.rd-hall__label { font-size: 11.5px; font-weight: 600; max-width: 11ch; text-align: center; line-height: 1.25; }

.rd-corridor__body { display: grid; grid-template-columns: minmax(320px, 440px) 1fr; gap: 18px; align-items: start; }
.rd-corridor__door { padding: 20px 22px; display: grid; gap: 12px; justify-items: center; text-align: center; }
.rd-step { margin: 0; font-size: 12px; color: var(--vg-text-muted); }
.rd-title { margin: 0; font-size: 24px; font-weight: 800; letter-spacing: -0.025em; }
.rd-line { margin: 0; color: var(--vg-text-secondary); max-width: 46ch; }
.rd-watch { margin: 0; font-size: 13px; color: var(--vg-text-secondary); max-width: 46ch; }
.rd-corridor__nav { display: flex; gap: 6px; flex-wrap: wrap; justify-content: center; }
.rd-corridor__nav a { text-decoration: none; }
.rd-keys { margin: 0; font-size: 12px; color: var(--vg-text-muted); }
.rd-keys kbd { font-family: var(--font-mono); font-size: 11px; padding: 1px 5px; border-radius: 4px; background: #fff; box-shadow: inset 0 0 0 1px var(--vg-border-strong); }
.rd-corridor__side { display: grid; gap: 14px; scroll-margin-top: 90px; }
.rd-panel { padding: 16px 20px; display: grid; gap: 12px; }
.rd-panel__row { display: flex; gap: 10px; flex-wrap: wrap; }
.rd-empty p { margin: 0; color: var(--vg-text-secondary); font-size: 13.5px; }
.rd-empty strong { color: var(--vg-text-primary); }
@media (max-width: 960px) {
  .rd-corridor__body { grid-template-columns: 1fr; }
  .rd-hall { justify-content: flex-start; perspective: none; }
  .rd-hall__door { transform: none !important; }
}
</style>
