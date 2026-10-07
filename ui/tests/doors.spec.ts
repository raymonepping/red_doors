// Every door: its owner opens it, the wrong key is refused — by Vault.
import { expect, test, type Page } from '@playwright/test'
import { pageAs } from './auth'

const MACHINE: { id: number, method: string, role: string, policy: string | null, noAudit?: boolean }[] = [
  { id: 1, method: 'kubernetes', role: 'opener-1', policy: 'door-1' },
  { id: 3, method: 'approle', role: 'door-3', policy: 'door-3' },
  { id: 4, method: 'kubernetes', role: 'opener-4', policy: 'door-4' },
  { id: 5, method: 'cert', role: 'treasury', policy: 'door-5' },
  { id: 6, method: 'kubernetes', role: 'opener-6', policy: 'door-6' },
  // door 7's opener never calls Vault (VSO mounted the Secret) — so no audit entry per knock
  { id: 7, method: 'vault-secrets-operator', role: 'vso-door-7', policy: null, noAudit: true },
]

const decision = (p: Page) => p.getByRole('region', { name: 'How Vault decided' })

async function expectAudit(p: Page) {
  // Audit entries are joined by Vault request id; they arrive within a second or two.
  await expect(async () => {
    await p.getByRole('button', { name: 'Vault audit entries' }).click()
    const drawer = p.getByRole('dialog', { name: 'Vault audit entries' })
    await expect(drawer.locator('.rd-entry').first()).toBeVisible({ timeout: 3_000 })
  }).toPass({ timeout: 20_000, intervals: [1_500] })
  await p.getByRole('button', { name: 'Close' }).click()
}

async function expectRefused(p: Page) {
  await expect(p.locator('.rd-stage .rd-door')).toHaveAttribute('data-state', 'refused')
  await expect(decision(p).locator('.rd-denial')).toContainText(/permission denied|expired|certificate|invalid|not|denied|no Secret/i)
}

test.describe('machine doors — ada knocks', () => {
  for (const d of MACHINE) {
    test(`door ${d.id}: owner opens, wrong key refused`, async ({ browser }) => {
      const { context, page } = await pageAs(browser, 'ada')
      await page.goto(`/doors/${d.id}`)
      await page.getByRole('button', { name: 'Knock' }).click()
      await expect(page.locator('.rd-stage .rd-door')).toHaveAttribute('data-state', 'open')
      const values = page.locator('.rd-room__fields dd')
      await expect(values.first()).not.toBeEmpty()
      const dec = decision(page)
      await expect(dec).toContainText(d.method)
      await expect(dec).toContainText(d.role)
      if (d.policy) await expect(dec).toContainText(d.policy)
      await expect(dec.locator('.rd-steps__outcome')).toHaveAttribute('data-outcome', 'opened')
      if (d.noAudit) {
        await page.getByRole('button', { name: 'Vault audit entries' }).click()
        await expect(page.getByRole('dialog', { name: 'Vault audit entries' })).toContainText('No audit entries joined')
        await page.getByRole('button', { name: 'Close' }).click()
      }
      else await expectAudit(page)

      await page.getByRole('button', { name: 'Try the wrong key' }).click()
      await expectRefused(page)
      await expect(dec.locator('.rd-steps__outcome')).toHaveAttribute('data-outcome', 'denied')
      await context.close()
    })
  }
})

test('door 2: ada (board) opens with her own token, ben is refused', async ({ browser }) => {
  const ada = await pageAs(browser, 'ada')
  await ada.page.goto('/doors/2')
  await ada.page.getByRole('button', { name: 'Open as ada' }).click()
  await expect(ada.page.locator('.rd-stage .rd-door')).toHaveAttribute('data-state', 'open')
  await expect(ada.page.locator('.rd-room__fields dd').first()).not.toBeEmpty()
  await expect(decision(ada.page)).toContainText('oidc')
  await expect(decision(ada.page)).toContainText('board')
  await expectAudit(ada.page)
  await ada.context.close()

  const ben = await pageAs(browser, 'ben')
  await ben.page.goto('/doors/2')
  await ben.page.getByRole('button', { name: 'Open as ben' }).click()
  await expectRefused(ben.page)
  await ben.context.close()
})

test('finn (auditor) can look but not knock', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'finn')
  await page.goto('/doors/1')
  await expect(page.getByRole('button', { name: 'Knock' })).toBeDisabled()
  await expect(page.getByText('Auditors are read-only here')).toBeVisible()
  await context.close()
})
