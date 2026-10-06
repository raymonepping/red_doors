// nuxt.config.ts — Red Doors UI.
//
// SPA (ssr: false) served by Nitro, which is also the BFF: sign-in IS a Vault
// OIDC login (Vault ↔ Keycloak), the person's Vault token stays in a
// server-side session, and the browser only talks to this origin.
// (Durin's model; Arcanium's SSR cost hydration + CSP trouble for no gain here.)
import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '2026-10-01',
  ssr: false,
  devtools: { enabled: false },
  css: ['~/assets/css/main.css'],
  vite: { plugins: [tailwindcss()] },
  app: {
    head: {
      title: 'Red Doors',
      htmlAttrs: { lang: 'en' },
      meta: [
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        { name: 'color-scheme', content: 'light' },
        { name: 'description', content: 'Red Doors — eight doors, eight ways in. Vault Enterprise on OpenShift.' },
      ],
      link: [{ rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
    },
  },
  runtimeConfig: {
    // Server-only. Override with NUXT_<NAME> env vars.
    apiInternalUrl: 'http://red-doors-api.rd-app.svc:3001', // NUXT_API_INTERNAL_URL
    vaultAddr: 'https://vault-active.rd-vault.svc:8200',   // NUXT_VAULT_ADDR (BFF → Vault OIDC)
    vaultNamespace: 'red-doors',
    vaultCaFile: '/ca/ca.crt',
    oidcRedirectUri: 'https://doors.apps-crc.testing/auth/callback',
    public: {
      designSheet: false, // NUXT_PUBLIC_DESIGN_SHEET=true exposes /_design (component sheet)
    },
  },
  nitro: {
    storage: { sessions: { driver: 'memory' } },
  },
  routeRules: {
    '/**': {
      headers: {
        // Nuxt's SPA bootstrap needs inline script/style (see Arcanium's
        // nuxt.config.ts for the long story); everything else is same-origin.
        'Content-Security-Policy':
          "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; "
          + "script-src 'self' 'unsafe-inline'; font-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; object-src 'none'",
        'X-Frame-Options': 'DENY',
        'X-Content-Type-Options': 'nosniff',
        'Referrer-Policy': 'no-referrer',
        'Cache-Control': 'no-store',
      },
    },
    '/_nuxt/**': { headers: { 'Cache-Control': 'public, max-age=31536000, immutable' } },
  },
})
