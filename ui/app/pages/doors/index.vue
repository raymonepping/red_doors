<script setup lang="ts">
// All eight doors at once — for Q&A.
definePageMeta({ title: 'All doors' })
const doors = ref<any[]>([])
const err = ref('')
onMounted(async () => {
  try { doors.value = (await api('/doors')).doors }
  catch (e) { err.value = errorText(e) }
})
const stateOf = (d: any) => (d.last_attempt?.outcome === 'opened' ? 'open' : d.last_attempt?.outcome === 'denied' ? 'refused' : d.last_attempt?.outcome === 'pending' ? 'pending' : 'closed')
</script>

<template>
  <div class="rd-all">
    <section class="vg-hero">
      <h2 class="rd-h">The whole corridor</h2>
      <p class="rd-sub">Eight business items, eight Vault methods. Each card shows the last thing Vault decided at that door.</p>
    </section>
    <p v-if="err" class="inline-notice error">{{ err }}</p>
    <div class="rd-grid">
      <NuxtLink v-for="d in doors" :key="d.id" :to="`/doors/${d.id}`" class="vg-glass rd-card">
        <RedDoor :number="d.id" :method="d.method.split(' (')[0].split(' — ')[0]" :title="d.title" size="md" :state="stateOf(d)" />
        <div class="rd-card__body">
          <h3>{{ d.title }}</h3>
          <p class="rd-card__method">{{ d.method }}</p>
          <p class="rd-card__sum">{{ d.summary }}</p>
          <div class="rd-card__last">
            <OutcomePill v-if="d.last_attempt" :outcome="d.last_attempt.outcome" />
            <span v-else class="rd-card__none">Nobody has knocked yet</span>
            <span v-if="d.last_attempt" class="rd-card__when">{{ d.last_attempt.mode }} · {{ new Date(d.last_attempt.created_at).toLocaleTimeString() }}</span>
          </div>
        </div>
      </NuxtLink>
    </div>
  </div>
</template>

<style scoped>
.rd-all { display: grid; gap: 18px; max-width: 1360px; margin: 0 auto; }
.rd-h { margin: 0 0 6px; font-size: 24px; font-weight: 800; letter-spacing: -0.025em; }
.rd-sub { margin: 0; color: var(--vg-text-secondary); }
.rd-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(330px, 1fr)); gap: 16px; }
.rd-card { display: flex; gap: 18px; padding: 18px; text-decoration: none; color: inherit; transition: transform 180ms var(--vg-ease-out), box-shadow 180ms var(--vg-ease-out); }
.rd-card:hover { transform: translateY(-2px); box-shadow: var(--vg-shadow-lg), inset 0 1px 0 var(--vg-glass-hi); }
.rd-card__body { display: grid; gap: 6px; align-content: start; min-width: 0; }
.rd-card h3 { margin: 0; font-size: 17px; font-weight: 750; letter-spacing: -0.01em; }
.rd-card__method { margin: 0; font-size: 12.5px; font-weight: 650; color: var(--vg-action-bright); }
.rd-card__sum { margin: 0; font-size: 13px; color: var(--vg-text-secondary); line-height: 1.45; }
.rd-card__last { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 4px; }
.rd-card__none, .rd-card__when { font-size: 12px; color: var(--vg-text-muted); }
</style>
