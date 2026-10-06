<script setup lang="ts">
// Sign-in IS a Vault login: Vault is the OIDC client of Keycloak (LDAP).
import { LogIn } from 'lucide-vue-next'
definePageMeta({ layout: 'bare', title: 'Sign in' })
const route = useRoute()
const error = computed(() => (route.query.error as string) || '')
</script>

<template>
  <div class="rd-login">
    <section class="vg-hero rd-login__hero">
      <div class="rd-login__doors" aria-hidden="true">
        <RedDoor :number="1" method="Kubernetes" size="md" />
        <RedDoor :number="2" method="OIDC" size="md" />
        <RedDoor :number="8" method="Two-person" size="md" />
      </div>
      <h1>Eight doors. Eight ways in.</h1>
      <p>Behind each red door is something a business guards. Each opens for exactly one kind of identity — and Vault is the only one who decides.</p>
      <a class="primary-button rd-login__btn" href="/auth/login" data-testid="sign-in"><LogIn :size="16" aria-hidden="true" /> Sign in</a>
      <p class="rd-login__how">Signing in is a Vault login: Vault asks Keycloak who you are, and your LDAP groups become Vault policies.</p>
      <p v-if="error" class="inline-notice error" role="alert">{{ error }}</p>
    </section>
  </div>
</template>

<style scoped>
.rd-login { min-height: calc(100vh - 80px); display: grid; place-items: center; }
.rd-login__hero { width: min(640px, 100%); padding: 32px clamp(20px, 5vw, 44px); display: grid; gap: 14px; justify-items: start; }
.rd-login__doors { display: flex; gap: 14px; margin-bottom: 8px; }
.rd-login__hero h1 { margin: 0; font-size: clamp(26px, 4vw, 34px); font-weight: 800; letter-spacing: -0.03em; }
.rd-login__hero p { margin: 0; max-width: 56ch; color: var(--vg-text-secondary); line-height: 1.55; }
.rd-login__btn { margin-top: 8px; text-decoration: none; background: #fff; color: var(--vg-ink); }
.rd-login__btn:hover { background: #f1f4f8; }
.rd-login__how { font-size: 13px; }
@media (max-width: 480px) { .rd-login__doors :deep(.rd-door[data-size='md']) { --w: 84px; } }
</style>
