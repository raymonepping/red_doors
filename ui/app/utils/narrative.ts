// What the presenter says at each door (corridor). Facts only — the door
// itself shows what Vault actually did.
export const NARRATIVE: Record<number, { line: string, watch: string }> = {
  1: { line: 'A pod knocks. It has no password — only the service-account token OpenShift gave it.', watch: 'Vault checks the token with OpenShift, maps it to one role, and grants one read.' },
  3: { line: 'A partner integration logs in with AppRole. Its secret-id was handed over sealed, for one use only.', watch: 'If anyone had opened the envelope first, the opener would know — and the door would stay shut.' },
  5: { line: 'The Treasury wire room. The opener may cut a key that lives ten minutes — but only the key opens the door.', watch: 'Two identities, one after the other: the key cutter, then the certificate itself.' },
  2: { line: 'A person this time. Sign-in goes through Keycloak; LDAP says who is on the board.', watch: 'Same Vault, same door — the group decides. A colleague not on the board is refused.' },
  4: { line: 'Nobody has the payroll password. Vault mints a database login for this knock and kills it afterwards.', watch: 'Watch the generated username and its lifetime — gone from PostgreSQL right after.' },
  6: { line: 'The merger memo is stored only as ciphertext. One identity may decrypt; nothing else.', watch: 'The same identity tries to encrypt — and is refused. Decrypt-only means exactly that.' },
  7: { line: 'This application never talks to Vault. The Vault Secrets Operator syncs the secret into OpenShift for it.', watch: 'Rotate it in Vault and the new value arrives in the pod within seconds.' },
  8: { line: 'The launch codes. Knocking is not enough: a second, different person must approve.', watch: 'Approving your own request does not count — Vault enforces it, not this screen.' },
}

export const STATE_WORDS: Record<string, string> = {
  opened: 'Opened by Vault',
  denied: 'Refused by Vault',
  pending: 'Waiting for a second person',
  approved: 'Approved',
  not_counted: 'Not counted — you cannot approve yourself',
  recorded: 'Authorization recorded',
  error: 'Something broke (not a Vault decision)',
}
