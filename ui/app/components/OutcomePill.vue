<script setup lang="ts">
// Outcome in words + icon — never colour alone.
import { DoorOpen, Lock, Hourglass, CheckCircle2, CircleSlash, AlertTriangle } from 'lucide-vue-next'
const props = defineProps<{ outcome: string }>()
const map: Record<string, { cls: string, icon: any }> = {
  opened: { cls: 'vg-pill--healthy', icon: DoorOpen },
  denied: { cls: 'vg-pill--rejected', icon: Lock },
  pending: { cls: 'vg-pill--pending', icon: Hourglass },
  approved: { cls: 'vg-pill--approved', icon: CheckCircle2 },
  not_counted: { cls: 'vg-pill--pending', icon: CircleSlash },
  recorded: { cls: 'vg-pill--approved', icon: CheckCircle2 },
  error: { cls: 'vg-pill--rejected', icon: AlertTriangle },
}
const m = computed(() => map[props.outcome] ?? map.error!)
</script>

<template>
  <span class="vg-pill rd-outcome" :class="m.cls" :data-outcome="outcome">
    <component :is="m.icon" :size="13" :stroke-width="2.2" aria-hidden="true" />
    {{ STATE_WORDS[outcome] ?? outcome }}
  </span>
</template>

<style scoped>
.rd-outcome { font-size: 12px; padding: 3px 10px; }
</style>
