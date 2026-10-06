// Server-side sessions. The person's Vault token and door-8 wrapping tokens
// live here — never in the browser. Cookie: opaque id, httpOnly, SameSite=Lax.
import { randomBytes } from 'node:crypto'
import type { H3Event } from 'h3'

export interface RdSession {
  id: string
  vaultToken: string
  username: string
  displayName: string
  entityId: string | null
  groups: string[]
  policies: string[]
  identityPolicies: string[]
  expiresAt: number
  door8: Record<string, string> // accessor → wrapping token (this person's requests only)
}

const COOKIE = 'rd_session'
const store = () => useStorage<RdSession>('sessions')
const secure = (event: H3Event) => getRequestProtocol(event, { xForwardedProto: true }) === 'https'

export async function createSession(event: H3Event, data: Omit<RdSession, 'id' | 'door8'>) {
  const id = randomBytes(32).toString('base64url')
  const session: RdSession = { ...data, id, door8: {} }
  await store().setItem(id, session)
  setCookie(event, COOKIE, id, { httpOnly: true, sameSite: 'lax', secure: secure(event), path: '/', maxAge: Math.max(60, Math.floor((data.expiresAt - Date.now()) / 1000)) })
  return session
}

export async function getSession(event: H3Event): Promise<RdSession | null> {
  const id = getCookie(event, COOKIE)
  if (!id) return null
  const s = await store().getItem(id)
  if (!s) return null
  if (s.expiresAt < Date.now()) {
    await store().removeItem(id)
    return null
  }
  return s
}

export const saveSession = (s: RdSession) => store().setItem(s.id, s)

export async function destroySession(event: H3Event) {
  const id = getCookie(event, COOKIE)
  if (id) await store().removeItem(id)
  deleteCookie(event, COOKIE, { path: '/' })
}

export async function requireSession(event: H3Event) {
  const s = await getSession(event)
  if (!s) throw createError({ statusCode: 401, statusMessage: 'sign in first' })
  return s
}
