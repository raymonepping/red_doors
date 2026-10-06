<script setup lang="ts">
// Two different things, always shown apart: who pressed the button vs the
// identity Vault actually evaluated.
import { MousePointerClick, KeyRound } from 'lucide-vue-next'
defineProps<{ triggeredBy?: string | null, openedBy?: { method?: string, subject?: string, role?: string | null } | null }>()
</script>

<template>
  <div class="rd-chips">
    <span class="rd-chip" title="The signed-in person who pressed the button">
      <MousePointerClick :size="13" aria-hidden="true" />
      <span class="rd-chip__k">Triggered by</span>
      <strong>{{ triggeredBy || 'not reported' }}</strong>
    </span>
    <span class="rd-chip rd-chip--identity" title="The identity Vault evaluated">
      <KeyRound :size="13" aria-hidden="true" />
      <span class="rd-chip__k">Opened by</span>
      <strong>{{ openedBy?.subject || 'not reported' }}</strong>
      <span v-if="openedBy?.method" class="rd-chip__m">{{ openedBy.method }}<template v-if="openedBy.role"> · {{ openedBy.role }}</template></span>
    </span>
  </div>
</template>

<style scoped>
.rd-chips { display: flex; flex-wrap: wrap; gap: 8px; }
.rd-chip {
  display: inline-flex; align-items: center; flex-wrap: wrap; gap: 4px 6px; max-width: 100%; min-width: 0;
  padding: 5px 11px; border-radius: 999px; font-size: 12.5px;
  background: rgba(255, 255, 255, 0.7); color: var(--vg-text-secondary);
  box-shadow: inset 0 0 0 1px var(--vg-border-subtle);
}
.rd-chip strong { color: var(--vg-text-primary); font-weight: 650; overflow-wrap: anywhere; min-width: 0; }
.rd-chip__k { color: var(--vg-text-muted); }
.rd-chip--identity { background: color-mix(in srgb, var(--vg-hue-blue) 9%, white); }
.rd-chip__m { font-family: var(--font-mono); font-size: 11.5px; color: var(--vg-action-bright); }
</style>
