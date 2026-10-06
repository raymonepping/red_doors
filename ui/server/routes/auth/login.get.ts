// Sign-in IS a Vault OIDC login: Vault (the OIDC client) hands us Keycloak's
// authorize URL; Keycloak checks the person against LDAP.
import { randomBytes } from 'node:crypto'

export default defineEventHandler(async (event) => {
  const cfg = useRuntimeConfig()
  const nonce = randomBytes(16).toString('hex')
  const r = await vaultCall('POST', 'auth/oidc/oidc/auth_url', { body: { role: 'visitor', redirect_uri: cfg.oidcRedirectUri, client_nonce: nonce } })
  const url = r.json?.data?.auth_url
  if (r.status !== 200 || !url) return sendRedirect(event, `/login?error=${encodeURIComponent(r.json?.errors?.[0] ?? 'Vault did not return a sign-in URL')}`)
  setCookie(event, 'rd_oidc_nonce', nonce, { httpOnly: true, sameSite: 'lax', secure: getRequestProtocol(event, { xForwardedProto: true }) === 'https', path: '/auth', maxAge: 600 })
  return sendRedirect(event, url)
})
