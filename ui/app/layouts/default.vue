<script setup lang="ts">
// App shell: frosted rail, floating glass topbar, footer (vault-ui-design shell).
import { DoorOpen, LayoutGrid, Gavel, ScrollText, Server, Search, ChevronLeft, ChevronRight, LogOut, Hourglass, Menu } from 'lucide-vue-next'

const route = useRoute()
const { user, signOut } = useSession()
const collapsed = ref(false)
const menuOpen = ref(false)
const navOpen = ref(false) // mobile: the rail as a sheet

const DOOR_NAV = [
  { id: 1, t: 'Deploy key' }, { id: 3, t: 'Partner API key' }, { id: 5, t: 'Treasury wire room' }, { id: 2, t: 'Board minutes' },
  { id: 4, t: 'Payroll database' }, { id: 6, t: 'Merger documents' }, { id: 7, t: 'Customer DB password' }, { id: 8, t: 'Launch codes' },
]
const isActive = (to: string) => (to === '/' ? route.path === '/' : route.path === to || route.path.startsWith(`${to}/`))

// live status for the topbar
const cluster = ref<any>(null)
const pending = ref(0)
async function refresh() {
  cluster.value = await api('/cluster').catch(() => null)
  if (user.value?.roles.approver) {
    const r: any = await api('/doors/8/requests').catch(() => null)
    pending.value = (r?.requests ?? []).filter((x: any) => !x.expired && !x.opened_at && x.vault && !x.vault.approved && !x.mine).length
  }
}
usePolling(refresh, 15000)
const clusterClass = computed(() => {
  const v = cluster.value?.vault
  if (!v) return 'unknown'
  return v.unsealed === v.total && v.leader ? 'healthy' : v.unsealed > 0 ? 'degraded' : 'critical'
})
const clusterText = computed(() => {
  const v = cluster.value?.vault
  return v ? `${v.leader ?? 'no leader'} · ${v.unsealed}/${v.total} unsealed` : 'Cluster unknown'
})

// ⌘K palette
const cmdOpen = ref(false)
const cmdQ = ref('')
const cmdIdx = ref(0)
const cmdItems = computed(() => {
  const all = [
    { label: 'Corridor', to: '/', cat: 'Page' }, { label: 'All doors', to: '/doors', cat: 'Page' },
    ...DOOR_NAV.map(d => ({ label: `Door ${d.id} — ${d.t}`, to: `/doors/${d.id}`, cat: 'Door' })),
    { label: 'Approvals', to: '/approvals', cat: 'Page' }, { label: 'Audit', to: '/audit', cat: 'Page' }, { label: 'Cluster', to: '/cluster', cat: 'Page' },
  ]
  const q = cmdQ.value.toLowerCase().trim()
  return q ? all.filter(i => i.label.toLowerCase().includes(q)) : all
})
function go(to: string) { cmdOpen.value = false; cmdQ.value = ''; navigateTo(to) }
function onKey(e: KeyboardEvent) {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); cmdOpen.value = !cmdOpen.value; cmdIdx.value = 0 }
  if (e.key === 'Escape') { cmdOpen.value = false; menuOpen.value = false }
}
onMounted(() => window.addEventListener('keydown', onKey))
onBeforeUnmount(() => window.removeEventListener('keydown', onKey))
watch(() => route.fullPath, () => { menuOpen.value = false; navOpen.value = false })
const title = computed(() => (route.meta.title as string) ?? 'Red Doors')
</script>

<template>
  <div class="vg-shell">
    <a class="skip-link" href="#main-content">Skip to content</a>
    <div v-if="navOpen" class="rd-scrim" @click="navOpen = false" />
    <aside class="vg-sidebar" :class="{ collapsed, 'rd-open': navOpen }" data-testid="sidebar">
      <div class="sidebar-brand">
        <svg class="brand-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="2" width="14" height="20" rx="1.4" fill="var(--rd-lacquer)" stroke="var(--rd-edge)" /><rect x="7.5" y="4.5" width="9" height="7" rx="0.6" fill="none" stroke="var(--rd-lacquer-light)" /><circle cx="15.5" cy="13.5" r="1.3" fill="var(--rd-brass-light)" /></svg>
        <span v-if="!collapsed" class="brand-name">Red Doors</span>
      </div>
      <nav class="sidebar-nav" aria-label="Primary">
        <NuxtLink to="/" class="nav-item" :class="{ active: isActive('/') }"><span class="nav-icon"><DoorOpen :size="16" /></span><span v-if="!collapsed" class="nav-label">Corridor</span></NuxtLink>
        <NuxtLink to="/doors" class="nav-item" :class="{ active: route.path === '/doors' }"><span class="nav-icon"><LayoutGrid :size="16" /></span><span v-if="!collapsed" class="nav-label">All doors</span></NuxtLink>
        <div class="nav-divider" />
        <NuxtLink v-for="d in DOOR_NAV" :key="d.id" :to="`/doors/${d.id}`" class="nav-item" :class="{ active: route.path === `/doors/${d.id}` }">
          <span class="nav-icon rd-num" aria-hidden="true">{{ d.id }}</span><span v-if="!collapsed" class="nav-label">{{ d.t }}</span>
        </NuxtLink>
        <div class="nav-divider" />
        <NuxtLink to="/approvals" class="nav-item" :class="{ active: isActive('/approvals') }">
          <span class="nav-icon"><Gavel :size="16" /></span><span v-if="!collapsed" class="nav-label">Approvals</span>
          <span v-if="pending && !collapsed" class="nav-badge governance" :aria-label="`${pending} pending`">{{ pending }}</span>
        </NuxtLink>
        <NuxtLink to="/audit" class="nav-item" :class="{ active: isActive('/audit') }"><span class="nav-icon"><ScrollText :size="16" /></span><span v-if="!collapsed" class="nav-label">Audit</span></NuxtLink>
        <div class="nav-divider" />
        <NuxtLink to="/cluster" class="nav-item" :class="{ active: isActive('/cluster') }"><span class="nav-icon"><Server :size="16" /></span><span v-if="!collapsed" class="nav-label">Cluster</span></NuxtLink>
      </nav>
      <div class="sidebar-footer">
        <button class="sidebar-toggle" type="button" :aria-label="collapsed ? 'Expand navigation' : 'Collapse navigation'" @click="collapsed = !collapsed">
          <ChevronRight v-if="collapsed" /><ChevronLeft v-else />
        </button>
      </div>
    </aside>

    <div class="vg-main">
      <header class="vg-topbar rd-topbar" data-testid="topbar">
        <div class="topbar-left"><button class="rd-menu" type="button" aria-label="Open navigation" :aria-expanded="navOpen" @click="navOpen = true"><Menu :size="18" /></button><h1 class="page-title" data-testid="page-title">{{ title }}</h1></div>
        <div class="topbar-centre">
          <button class="cmd-trigger" type="button" @click="cmdOpen = true"><Search aria-hidden="true" /><span>Go to a door…</span><kbd>⌘K</kbd></button>
        </div>
        <div class="topbar-right">
          <div class="cluster-pill" :class="clusterClass" role="status" :title="clusterText">
            <span class="cluster-dot" :class="{ live: clusterClass === 'healthy' }" />
            <span class="cluster-label">{{ clusterText }}</span>
          </div>
          <NuxtLink v-if="pending" to="/approvals" class="pending-pill"><Hourglass aria-hidden="true" /><span>{{ pending }}</span><span class="pending-pill__label">waiting</span></NuxtLink>
          <div class="user-menu">
            <button class="persona" type="button" :aria-expanded="menuOpen" aria-haspopup="menu" @click="menuOpen = !menuOpen">
              <span class="persona-dot persona-dot--auth" />{{ user?.display_name ?? user?.username }}
            </button>
            <div v-if="menuOpen" class="user-menu-panel" role="menu">
              <div class="umf-row umf-user">{{ user?.display_name }} <span class="umf-meta">({{ user?.username }})</span></div>
              <div class="umf-row umf-meta">Signed in through Vault OIDC · Keycloak · LDAP</div>
              <div class="umf-groups"><span v-for="g in user?.groups ?? []" :key="g" class="umf-chip">{{ g }}</span></div>
              <button class="umf-signout" type="button" role="menuitem" @click="signOut"><LogOut :size="13" aria-hidden="true" /> Sign out</button>
            </div>
          </div>
        </div>
      </header>

      <main id="main-content" class="vg-content" tabindex="-1">
        <slot />
      </main>

      <footer class="rd-footer vg-glass">
        <span>Red Doors — Vault Enterprise on OpenShift. Every outcome on this page was decided by Vault.</span>
      </footer>
    </div>

    <Transition name="cmd-fade">
      <div v-if="cmdOpen" class="cmd-overlay" @click.self="cmdOpen = false">
        <div class="cmd-panel" role="dialog" aria-modal="true" aria-label="Go to">
          <div class="cmd-search-row">
            <Search class="cmd-search-icon" aria-hidden="true" />
            <input v-model="cmdQ" class="cmd-input" placeholder="Door, page…" aria-label="Search doors and pages" autofocus
              @keydown.enter="cmdItems[cmdIdx] && go(cmdItems[cmdIdx]!.to)"
              @keydown.arrow-down.prevent="cmdIdx = Math.min(cmdItems.length - 1, cmdIdx + 1)"
              @keydown.arrow-up.prevent="cmdIdx = Math.max(0, cmdIdx - 1)">
            <span class="cmd-esc">esc</span>
          </div>
          <div class="cmd-results">
            <button v-for="(i, n) in cmdItems" :key="i.to" class="cmd-result" :class="{ active: n === cmdIdx }" type="button" @click="go(i.to)">
              <span class="cmd-result-label">{{ i.label }}</span><span class="cmd-result-category">{{ i.cat }}</span>
            </button>
            <p v-if="!cmdItems.length" class="cmd-empty">Nothing matches.</p>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.vg-shell {
  display: flex;
  min-height: 100vh;
  background: transparent;
}

/* ── Sidebar ─────────────────────────────────────────────── */
.vg-sidebar {
  width: var(--sidebar-w);
  min-height: 100vh;
  background: var(--vg-bg-shell);
  backdrop-filter: blur(22px) saturate(150%);
  -webkit-backdrop-filter: blur(22px) saturate(150%);
  border-right: 1px solid var(--vg-glass-border);
  box-shadow: inset -1px 0 0 rgba(255, 255, 255, 0.6), 8px 0 32px -24px rgba(15, 26, 42, 0.35);
  display: flex;
  flex-direction: column;
  flex-shrink: 0;
  transition: width 0.2s ease;
  position: sticky;
  top: 0;
  height: 100vh;
  overflow: hidden;
}
.vg-sidebar.collapsed { width: 52px; }

.sidebar-brand {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 14px;
  height: var(--topbar-h);
  border-bottom: 1px solid var(--vg-border-subtle);
  flex-shrink: 0;
}
.brand-icon { width: 22px; height: 22px; flex-shrink: 0; }
.brand-name {
  font-size: 22px;
  font-weight: 800;
  letter-spacing: -0.03em;
  color: var(--vg-text-primary);
  white-space: nowrap;
  font-family: var(--font-sans);
}

.sidebar-nav {
  flex: 1;
  padding: 12px 0;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.nav-item {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 0 8px;
  padding: 0 10px;
  height: 36px;
  font-size: 13px;
  font-weight: 550;
  color: var(--vg-text-secondary);
  text-decoration: none;
  border-radius: 8px;
  transition: background 0.18s var(--vg-ease-out), color 0.18s, box-shadow 0.18s;
  white-space: nowrap;
  position: relative;
}
.nav-divider {
  height: 0;
  margin: 4px 14px;
  border-top: 1px solid var(--vg-border-subtle);
}
.nav-item:hover { background: rgba(255, 255, 255, 0.55); color: var(--vg-text-primary); }
.nav-item.active {
  background: rgba(255, 255, 255, 0.85);
  color: var(--vg-text-primary);
  font-weight: 650;
  box-shadow: inset 0 0 0 1px rgba(15, 26, 42, 0.08), 0 4px 12px -8px rgba(15, 26, 42, 0.35);
}
.nav-item.active .nav-icon { color: var(--vg-action-primary); }
.nav-icon { width: 16px; height: 16px; flex-shrink: 0; display: flex; align-items: center; }
.nav-icon :deep(svg) { width: 16px; height: 16px; }
.nav-label { flex: 1; }
.nav-badge {
  font-size: 10px;
  font-weight: 700;
  padding: 1px 6px;
  border-radius: 10px;
  line-height: 1.6;
}
.nav-badge.governance {
  background: var(--vg-pending-bg);
  color: var(--vg-governance);
  border: 1px solid color-mix(in srgb, var(--vg-hue-amber) 30%, transparent);
}
.nav-badge.critical {
  background: var(--vg-critical-bg);
  color: var(--vg-critical);
  border: 1px solid color-mix(in srgb, var(--vg-hue-red) 30%, transparent);
}

.sidebar-footer {
  padding: 12px;
  border-top: 1px solid var(--vg-border-subtle);
}
.sidebar-toggle {
  background: none;
  border: 1px solid var(--vg-border-subtle);
  border-radius: 6px;
  width: 28px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  color: var(--vg-text-muted);
  transition: background 0.12s, color 0.12s;
}
.sidebar-toggle:hover { background: var(--vg-hover); color: var(--vg-text-secondary); }
.sidebar-toggle svg { width: 14px; height: 14px; }

/* ── Main area ───────────────────────────────────────────── */
.vg-main {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
}

/* ── Topbar ──────────────────────────────────────────────── */
.vg-topbar {
  height: var(--topbar-h);
  background: var(--vg-bg-shell);
  backdrop-filter: blur(22px) saturate(150%);
  -webkit-backdrop-filter: blur(22px) saturate(150%);
  border: 1px solid var(--vg-glass-border);
  border-radius: 14px;
  box-shadow: var(--vg-shadow-md), inset 0 1px 0 var(--vg-glass-hi);
  display: flex;
  align-items: center;
  padding: 0 24px;
  gap: 14px;
  position: sticky;
  top: 0;
  z-index: 10;
  flex-shrink: 0;
}
.topbar-left { flex: 0 1 auto; min-width: 0; }
.page-title { font-size: 15px; font-weight: 700; letter-spacing: -0.01em; color: var(--vg-text-primary); margin: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.topbar-centre { flex: 1 1 auto; min-width: 120px; max-width: 360px; }
.topbar-right { flex: 0 0 auto; display: flex; align-items: center; justify-content: flex-end; gap: 8px; }
.topbar-right > * { white-space: nowrap; flex-shrink: 0; }

.cmd-trigger {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  background: var(--vg-bg-surface);
  border: 1px solid var(--vg-border-subtle);
  border-radius: 8px;
  padding: 0 12px;
  height: 34px;
  cursor: pointer;
  color: var(--vg-text-muted);
  font-size: 13px;
  transition: border-color 0.12s;
}
.cmd-trigger:hover { border-color: var(--vg-border-strong); color: var(--vg-text-secondary); }
.cmd-trigger svg { width: 14px; height: 14px; flex-shrink: 0; }
.cmd-trigger span { flex: 1; text-align: left; }
.cmd-trigger kbd { font-size: 11px; color: var(--vg-text-dim); font-family: var(--font-mono); }

.cluster-pill {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 12px;
  border-radius: 100px;
  font-size: 12px;
  line-height: 1.2;
  white-space: nowrap;
  cursor: default;
}
.cluster-pill.healthy { background: var(--vg-healthy-bg); color: var(--vg-healthy); border: 1px solid color-mix(in srgb, var(--vg-hue-green) 20%, transparent); }
.cluster-pill.degraded { background: color-mix(in srgb, var(--vg-hue-orange) 10%, transparent); color: var(--vg-warning); border: 1px solid color-mix(in srgb, var(--vg-hue-orange) 20%, transparent); }
.cluster-pill.critical { background: var(--vg-critical-bg); color: var(--vg-critical); border: 1px solid color-mix(in srgb, var(--vg-hue-red) 20%, transparent); }
.cluster-pill.unknown { background: color-mix(in srgb, var(--vg-hue-slate) 10%, transparent); color: var(--vg-text-muted); border: 1px solid color-mix(in srgb, var(--vg-hue-slate) 20%, transparent); }
.cluster-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
}
.cluster-dot.live { animation: vgPulse 2.4s ease infinite; box-shadow: 0 0 8px currentColor; }

.env-badge {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.12em;
  color: var(--vg-text-muted);
  border: 1px solid var(--vg-glass-border);
  border-radius: 5px;
  padding: 3px 8px;
}

.vault-link {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--vg-text-muted);
  padding: 4px 10px;
  border: 1px solid var(--vg-glass-border);
  border-radius: 100px;
  transition: color 0.15s, border-color 0.15s;
}
.vault-link:hover { color: var(--vg-action-bright); border-color: color-mix(in srgb, var(--vg-hue-blue) 35%, transparent); }
.vault-link svg { width: 13px; height: 13px; }

.user-menu { position: relative; }

.persona {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--vg-text-secondary);
  padding: 4px 10px 4px 8px;
  border: 1px solid var(--vg-glass-border);
  border-radius: 100px;
  background: none;
  font-family: inherit;
  cursor: pointer;
}
.persona:hover { color: var(--vg-text-primary); border-color: color-mix(in srgb, var(--vg-hue-blue) 35%, transparent); }
.persona-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--vg-text-dim); }
.persona-dot--auth { background: var(--vg-action-bright); box-shadow: 0 0 0 2px color-mix(in srgb, var(--vg-hue-blue) 18%, transparent); }

.user-menu-panel {
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  min-width: 220px;
  background: rgba(255, 255, 255, 0.9);
  border: 1px solid var(--vg-glass-border);
  border-radius: 12px;
  box-shadow: var(--vg-shadow-lg);
  backdrop-filter: blur(22px) saturate(150%);
  padding: 10px 12px;
  z-index: 40;
}
.umf-row { font-size: 12px; line-height: 1.5; }
.umf-row + .umf-row { margin-top: 4px; }
.umf-user { font-weight: 650; color: var(--vg-text-primary); font-size: 13px; }
.umf-meta { color: var(--vg-text-muted); }
.umf-groups { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 6px; }
.umf-chip {
  font-size: 10.5px;
  color: var(--vg-text-muted);
  background: var(--vg-hover);
  border: 1px solid var(--vg-glass-border);
  border-radius: 100px;
  padding: 1px 8px;
}
.umf-signout {
  width: 100%;
  margin-top: 10px;
  padding: 6px 10px;
  font-size: 12px;
  font-family: inherit;
  color: var(--vg-text-secondary);
  background: none;
  border: 1px solid var(--vg-glass-border);
  border-radius: 6px;
  cursor: pointer;
}
.umf-signout:hover { color: var(--vg-text-primary); border-color: color-mix(in srgb, var(--vg-hue-red) 40%, transparent); }

@media (max-width: 1180px) {
  .env-badge, .vault-link span, .persona { display: none; }
}

/* Baseline audit finding (docs/frontend/UI_AUDIT.md) — below ~640px the
   topbar had no further narrowing beyond the 1180px step above, so the
   search trigger, cluster status text, and pending-count label collided
   with the (now-truncating) page title and were clipped at the viewport
   edge. Confirmed live via Playwright at 390x844 on every route. */
@media (max-width: 640px) {
  .vg-topbar { gap: 8px; padding: 0 14px; }
  .topbar-centre { display: none; }
  .cluster-label { display: none; }
  .cluster-pill { padding: 4px 8px; }
  .pending-pill__label { display: none; }
}

.pending-pill {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 3px 10px;
  border-radius: 100px;
  font-size: 12px;
  font-family: inherit;
  background: var(--vg-pending-bg);
  color: var(--vg-governance);
  border: 1px solid color-mix(in srgb, var(--vg-hue-amber) 30%, transparent);
  cursor: pointer;
  transition: background 0.12s;
}
.pending-pill:hover { background: color-mix(in srgb, var(--vg-hue-amber) 20%, transparent); }
.pending-pill svg { width: 14px; height: 14px; }

/* ── Content ─────────────────────────────────────────────── */
.vg-content {
  flex: 1;
  padding: 24px;
  overflow-y: auto;
}
.tenant-banner {
  display: flex; align-items: center; gap: 10px;
  margin-bottom: 18px; padding: 10px 16px; border-radius: 10px;
  font-size: 12px; color: var(--vg-text-secondary);
  background: color-mix(in srgb, var(--vg-hue-blue) 8%, transparent); border: 1px solid var(--vg-glass-border);
}
.tenant-banner strong { color: var(--vg-action-bright); font-family: var(--font-mono); }
.tb-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--vg-action-bright); flex-shrink: 0; }

/* ── Command palette ─────────────────────────────────────── */
.cmd-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: var(--vg-scrim);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding-top: 80px;
}
.cmd-panel {
  width: 100%;
  max-width: 560px;
  background: rgba(255, 255, 255, 0.9);
  backdrop-filter: blur(22px) saturate(150%);
  -webkit-backdrop-filter: blur(22px) saturate(150%);
  border: 1px solid var(--vg-glass-border);
  border-radius: 14px;
  overflow: hidden;
  box-shadow: var(--vg-shadow-lg);
}
.cmd-search-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 16px;
  height: 52px;
  border-bottom: 1px solid var(--vg-border-subtle);
}
.cmd-search-icon { width: 16px; height: 16px; color: var(--vg-text-muted); flex-shrink: 0; }
.cmd-input {
  flex: 1;
  background: none;
  border: none;
  outline: none;
  font-size: 15px;
  color: var(--vg-text-primary);
  font-family: inherit;
}
.cmd-input::placeholder { color: var(--vg-text-muted); }
.cmd-esc {
  font-size: 11px;
  color: var(--vg-text-muted);
  background: var(--vg-hover);
  border: 1px solid var(--vg-border-subtle);
  border-radius: 4px;
  padding: 2px 6px;
}
.cmd-results { padding: 6px 0; max-height: 360px; overflow-y: auto; }
.cmd-result {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  padding: 0 16px;
  height: 44px;
  background: none;
  border: none;
  cursor: pointer;
  color: var(--vg-text-secondary);
  font-size: 13px;
  font-family: inherit;
  text-align: left;
  transition: background 0.1s;
}
.cmd-result:hover, .cmd-result.active { background: color-mix(in srgb, var(--vg-hue-blue) 15%, transparent); color: var(--vg-text-primary); }
.cmd-result-icon { width: 16px; height: 16px; color: var(--vg-action-bright); flex-shrink: 0; }
.cmd-result-icon :deep(svg) { width: 16px; height: 16px; }
.cmd-result-label { flex: 1; }
.cmd-result-category { font-size: 11px; color: var(--vg-text-muted); text-transform: uppercase; letter-spacing: 0.06em; }
.cmd-empty, .cmd-hint {
  padding: 20px 16px;
  font-size: 13px;
  color: var(--vg-text-muted);
  text-align: center;
}
.cmd-empty em { color: var(--vg-text-secondary); }

/* ── Transitions ─────────────────────────────────────────── */
.cmd-fade-enter-active, .cmd-fade-leave-active { transition: opacity 0.15s; }
.cmd-fade-enter-from, .cmd-fade-leave-to { opacity: 0; }

/* ── Responsive: hide sidebar at ≤900px within the scoped style so the
   rule wins over the global baseline (scoped styles carry attribute
   specificity that the global reset cannot override on its own). */
@media (max-width: 900px) {
  .vg-sidebar { display: none !important; }
}

/* ── Red Doors shell tweaks ── */
.topbar-left { display: flex; align-items: center; gap: 10px; }
.rd-menu { display: none; border: 0; background: transparent; padding: 6px; border-radius: 8px; color: var(--vg-text-primary); cursor: pointer; }
.rd-menu:hover { background: var(--vg-hover); }
.rd-scrim { display: none; }
@media (max-width: 1180px) {
  /* keep the user menu (sign-out) reachable; show it compactly */
  .persona { display: flex !important; max-width: 160px; overflow: hidden; text-overflow: ellipsis; }
}
@media (max-width: 900px) {
  .rd-menu { display: inline-flex; }
  .vg-sidebar.rd-open { display: flex !important; position: fixed; inset: 0 auto 0 0; z-index: 60; width: min(280px, 86vw); }
  .rd-scrim { display: block; position: fixed; inset: 0; z-index: 55; background: var(--vg-scrim); }
  .rd-topbar { margin: 10px 12px 0; padding: 0 12px; }
  .rd-footer { margin: 0 12px 12px; }
}
.rd-topbar { margin: 14px 20px 0; }
.rd-num { font-family: var(--font-mono); font-weight: 750; font-size: 12px; justify-content: center; width: 16px; }
.rd-footer { margin: 0 20px 16px; padding: 10px 18px; font-size: 12px; color: var(--vg-text-secondary); border-radius: 14px; }
.pending-pill { text-decoration: none; }
</style>
