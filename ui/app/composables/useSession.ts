// The signed-in person as the BFF reports them (never the Vault token).
export interface RdUser {
  username: string
  display_name: string
  groups: string[]
  policies: string[]
  identity_policies: string[]
  expires_at: string
  roles: { board: boolean, requester: boolean, approver: boolean, auditor: boolean }
}

export function useSession() {
  const user = useState<RdUser | null>('rd-user', () => null)
  const loaded = useState<boolean>('rd-user-loaded', () => false)

  async function load(force = false) {
    if (loaded.value && !force) return user.value
    try {
      user.value = await $fetch<RdUser>('/api/session')
    }
    catch {
      user.value = null
    }
    loaded.value = true
    return user.value
  }

  async function signOut() {
    await $fetch('/auth/logout', { method: 'POST' }).catch(() => {})
    user.value = null
    await navigateTo('/login')
  }

  const readOnly = computed(() => !!user.value && user.value.identity_policies.every(p => p === 'auditor') && user.value.identity_policies.length > 0)
  return { user, load, signOut, readOnly }
}
