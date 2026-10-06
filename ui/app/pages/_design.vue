<script setup lang="ts">
// Component sheet for sign-off (frontend 01_00). Exposed only with
// NUXT_PUBLIC_DESIGN_SHEET=true.
definePageMeta({ layout: 'bare' })
const enabled = useRuntimeConfig().public.designSheet
const states = ['closed', 'knocking', 'opening', 'open', 'refused', 'pending'] as const
const notes: Record<(typeof states)[number], string> = {
  closed: 'Resting. Brass plate + engraved method.',
  knocking: 'Three short pulses on the latch side.',
  opening: 'Mid-swing (35°): the lit room shows.',
  open: 'Swung on the hinge (68°): the released value sits in the room.',
  refused: 'A steel bolt slides across. Never shown by red alone.',
  pending: 'Amber governance seal: waiting for a second person.',
}
const swing = ref<'closed' | 'open'>('closed')
const replay = ref(0)
</script>

<template>
  <div v-if="!enabled" class="state-empty">
    <h3>Component sheet disabled</h3>
    <p>Set NUXT_PUBLIC_DESIGN_SHEET=true to view it.</p>
  </div>
  <div v-else class="sheet">
    <section class="vg-hero sheet__hero">
      <h1>Red Doors — component sheet</h1>
      <p>Daylight glass, black ink, and eight lacquered doors. Door red is a material, not a status: refusal is a bolt and words, approval is a lit room.</p>
    </section>

    <section class="vg-glass sheet__panel">
      <div class="vg-section-header"><h2 class="vg-section-title">States</h2></div>
      <div class="sheet__states">
        <figure v-for="s in states" :key="s" class="sheet__state">
          <RedDoor :key="`${s}-${replay}`" :number="4" method="Dynamic DB creds" title="Payroll database" :state="s" size="lg">
            <template #room>
              <div class="sheet__room"><strong>Payroll database</strong><span class="vg-mono">v-red-door-payroll-…</span></div>
            </template>
          </RedDoor>
          <figcaption><strong>{{ s }}</strong><span>{{ notes[s] }}</span></figcaption>
        </figure>
      </div>
      <button class="secondary-button" type="button" @click="replay++">Replay animations</button>
    </section>

    <section class="vg-glass sheet__panel">
      <div class="vg-section-header"><h2 class="vg-section-title">The one motion moment</h2></div>
      <div class="sheet__swing">
        <RedDoor :number="6" method="Transit" title="Merger documents" :state="swing" size="lg">
          <template #room>
            <div class="sheet__room"><strong>Merger documents</strong><span>plaintext appears here</span></div>
          </template>
        </RedDoor>
        <div>
          <p class="sheet__copy">700&nbsp;ms, <code class="vg-mono">cubic-bezier(0.16, 1, 0.3, 1)</code>, rotateY on the hinge. With <em>prefers-reduced-motion</em> the leaf fades instead.</p>
          <button class="primary-button" type="button" @click="swing = swing === 'open' ? 'closed' : 'open'">
            {{ swing === 'open' ? 'Close the door' : 'Open the door' }}
          </button>
        </div>
      </div>
    </section>

    <section class="vg-glass sheet__panel">
      <div class="vg-section-header"><h2 class="vg-section-title">Sizes — corridor · grid card · header icon</h2></div>
      <div class="sheet__sizes">
        <RedDoor :number="1" method="Kubernetes" size="lg" />
        <RedDoor :number="2" method="OIDC" size="md" />
        <RedDoor :number="8" method="Two-person" size="sm" state="pending" />
      </div>
    </section>

    <section class="vg-glass sheet__panel">
      <div class="vg-section-header"><h2 class="vg-section-title">Signal colours beside the doors</h2></div>
      <div class="sheet__pills">
        <span class="vg-pill vg-pill--healthy">Opened by Vault</span>
        <span class="vg-pill vg-pill--rejected">Refused by Vault</span>
        <span class="vg-pill vg-pill--pending">Waiting for a second person</span>
        <span class="vg-pill vg-pill--approved">Approved</span>
      </div>
    </section>
  </div>
</template>

<style scoped>
.sheet { display: grid; gap: 20px; max-width: 1280px; margin: 0 auto; }
.sheet__hero h1 { margin: 0 0 8px; font-size: 26px; font-weight: 750; letter-spacing: -0.02em; }
.sheet__hero p { margin: 0; max-width: 68ch; color: var(--vg-text-secondary); }
.sheet__panel { padding: 20px 22px; }
.sheet__states { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 28px 20px; margin: 8px 0 18px; }
.sheet__state { margin: 0; display: grid; justify-items: center; gap: 10px; text-align: center; }
.sheet__state figcaption { display: grid; gap: 2px; font-size: 13px; color: var(--vg-text-secondary); max-width: 26ch; }
.sheet__state figcaption strong { color: var(--vg-text-primary); text-transform: capitalize; }
.sheet__room { display: grid; gap: 4px; padding: 10px 0; text-align: right; font-size: 12px; color: var(--vg-text-primary); }
.sheet__swing { display: flex; align-items: center; gap: 32px; flex-wrap: wrap; }
.sheet__copy { max-width: 48ch; color: var(--vg-text-secondary); margin: 0 0 14px; }
.sheet__sizes { display: flex; align-items: flex-end; gap: 32px; flex-wrap: wrap; }
.sheet__pills { display: flex; gap: 10px; flex-wrap: wrap; }
</style>
