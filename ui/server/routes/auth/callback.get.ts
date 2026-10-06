// Keycloak → here → Vault exchanges the code and returns the person's Vault token.
export default defineEventHandler(async (event) => {
  const cfg = useRuntimeConfig()
  const { state, code, error, error_description: desc } = getQuery(event) as Record<string, string>
  if (error) return sendRedirect(event, `/login?error=${encodeURIComponent(desc || error)}`)
  const nonce = getCookie(event, 'rd_oidc_nonce') ?? ''
  deleteCookie(event, 'rd_oidc_nonce', { path: '/auth' })
  const r = await vaultCall('GET', 'auth/oidc/oidc/callback', { query: { state, code, client_nonce: nonce } })
  const auth = r.json?.auth
  if (r.status !== 200 || !auth?.client_token) return sendRedirect(event, `/login?error=${encodeURIComponent(r.json?.errors?.[0] ?? 'Vault rejected the sign-in')}`)

  // Ask the API (which can read identity group names) who this is.
  const who: any = await $fetch(`${cfg.apiInternalUrl}/api/v1/whoami`, { headers: { 'X-Vault-Token': auth.client_token } }).catch(() => null)
  await createSession(event, {
    vaultToken: auth.client_token,
    username: who?.username ?? auth.metadata?.username ?? 'unknown',
    displayName: auth.metadata?.name ?? who?.username ?? 'unknown',
    entityId: auth.entity_id || who?.entity_id || null,
    groups: who?.groups ?? [],
    policies: auth.token_policies ?? [],
    identityPolicies: auth.identity_policies ?? who?.identity_policies ?? [],
    expiresAt: Date.now() + (auth.lease_duration ?? 1800) * 1000,
  })
  return sendRedirect(event, '/')
})
