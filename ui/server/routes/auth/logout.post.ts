export default defineEventHandler(async (event) => {
  const s = await getSession(event)
  if (s) await vaultCall('POST', 'auth/token/revoke-self', { token: s.vaultToken }).catch(() => {})
  await destroySession(event)
  return { signed_out: true }
})
