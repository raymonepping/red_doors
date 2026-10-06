// BFF → API proxy. The browser never talks to the API or to Vault directly.
// Injects X-Triggered-By (the person who pressed the button) and, for human
// doors only, the person's Vault token. Door 8 wrapping tokens are kept in
// the requester's session and stripped from what the browser receives.
const HUMAN = [/^whoami$/, /^doors\/2\/open$/, /^doors\/8\/requests(\/[^/]+\/(approve|open))?$/]

export default defineEventHandler(async (event) => {
  const s = await requireSession(event)
  const cfg = useRuntimeConfig()
  const path = (getRouterParam(event, 'path') ?? '').replace(/^\/+/, '')
  const method = event.method
  const human = HUMAN.some(re => re.test(path))

  // Auditors are read-only in this demo (Vault still decides every door).
  if (method === 'POST' && /^doors\/\d+\/knock$/.test(path) && s.identityPolicies.every(p => p === 'auditor')) {
    throw createError({ statusCode: 403, statusMessage: 'auditors are read-only in this demo' })
  }

  let body: any = method === 'GET' ? undefined : await readBody(event).catch(() => undefined)
  const open = /^doors\/8\/requests\/([^/]+)\/open$/.exec(path)
  if (open) {
    const wrap = s.door8[decodeURIComponent(open[1]!)]
    if (!wrap) throw createError({ statusCode: 409, statusMessage: 'This request was made in another session — only the requester who asked can open it.' })
    body = { wrapping_token: wrap }
  }

  const query = getRequestURL(event).search
  const res = await $fetch.raw(`${cfg.apiInternalUrl}/api/v1/${path}${query}`, {
    method: method as any,
    body,
    headers: {
      'X-Triggered-By': s.username,
      ...(human ? { 'X-Vault-Token': s.vaultToken } : {}),
    },
    ignoreResponseError: true,
  })
  let data: any = res._data

  if (method === 'POST' && path === 'doors/8/requests' && data?.wrapping_token) {
    s.door8[data.accessor] = data.wrapping_token
    await saveSession(s)
    data = { ...data, wrapping_token: undefined, held_in: 'your server-side session' }
  }
  if (open && data?.outcome === 'opened') {
    delete s.door8[decodeURIComponent(open[1]!)]
    await saveSession(s)
  }
  if (method === 'GET' && path === 'doors/8/requests' && Array.isArray(data?.requests)) {
    data.requests = data.requests.map((r: any) => ({ ...r, can_open: Boolean(s.door8[r.accessor]) }))
  }

  setResponseStatus(event, res.status)
  return data
})
