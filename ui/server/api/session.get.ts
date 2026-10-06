// What the browser may know about the signed-in person (never the token).
export default defineEventHandler(async (event) => {
  const s = await requireSession(event)
  return {
    username: s.username,
    display_name: s.displayName,
    groups: s.groups,
    policies: s.policies,
    identity_policies: s.identityPolicies,
    expires_at: new Date(s.expiresAt).toISOString(),
    roles: {
      board: s.identityPolicies.includes('door-2'),
      requester: s.identityPolicies.includes('door-8-request'),
      approver: s.identityPolicies.includes('door-8-approve'),
      auditor: s.identityPolicies.includes('auditor'),
    },
  }
})
