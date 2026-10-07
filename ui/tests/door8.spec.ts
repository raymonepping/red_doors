// Door 8 — a control group plus a Sentinel EGP: two *different* people.
// Each persona has their own browser context and their own Vault token.
import { expect, test, type Page } from '@playwright/test'
import { pageAs } from './auth'

const notice = (p: Page) => p.locator('.inline-notice').first()
async function reload(p: Page) { await p.reload(); await p.waitForLoadState('networkidle') }
const myNewest = (p: Page) => p.locator('tbody tr', { hasText: 'you' }).first()

test('cleo requests, dirk approves, cleo opens — once', async ({ browser }) => {
  const cleo = await pageAs(browser, 'cleo')
  const dirk = await pageAs(browser, 'dirk')
  await cleo.page.goto('/approvals')
  await cleo.page.getByRole('button', { name: 'Request the launch codes' }).click()
  await expect(notice(cleo.page)).toContainText('Requested')
  const before = await cleo.page.locator('tbody tr').count()
  expect(before).toBeGreaterThan(0)

  await dirk.page.goto('/approvals')
  await dirk.page.locator('tbody tr', { hasText: 'cleo' }).first().getByRole('button', { name: 'Approve' }).click()
  await expect(notice(dirk.page)).not.toHaveClass(/error/)

  await reload(cleo.page)
  await myNewest(cleo.page).getByRole('button', { name: 'Open' }).click()
  await expect(cleo.page.locator('.rd-room')).toBeVisible()
  await expect(cleo.page.locator('.rd-room__fields dd').first()).not.toBeEmpty()
  await expect(notice(cleo.page)).toContainText('Opened')
  await reload(cleo.page)
  await expect(myNewest(cleo.page).getByRole('button', { name: 'Open' })).toHaveCount(0)
  await cleo.context.close(); await dirk.context.close()
})

test('eve approves herself → not counted, refused; dirk approves → she opens', async ({ browser, request }) => {
  const eve = await pageAs(browser, 'eve')
  const dirk = await pageAs(browser, 'dirk')
  await eve.page.goto('/approvals')
  await eve.page.getByRole('button', { name: 'Request the launch codes' }).click()
  await expect(notice(eve.page)).toContainText('Requested')
  await reload(eve.page)

  await myNewest(eve.page).getByRole('button', { name: 'Approve' }).click()
  await expect(notice(eve.page)).toContainText(/not count/i)
  await reload(eve.page)
  await expect(myNewest(eve.page)).toContainText('self-approval recorded, not counted')

  // Her Open — if offered at all — is refused by Vault (approved: false).
  const openBtn = myNewest(eve.page).getByRole('button', { name: 'Open' })
  if (await openBtn.count()) {
    await openBtn.click()
    await expect(notice(eve.page)).toHaveClass(/error/)
  }

  await dirk.page.goto('/approvals')
  await dirk.page.locator('tbody tr', { hasText: 'eve' }).first().getByRole('button', { name: 'Approve' }).click()
  await expect(notice(dirk.page)).not.toHaveClass(/error/)

  await reload(eve.page)
  await myNewest(eve.page).getByRole('button', { name: 'Open' }).click()
  await expect(eve.page.locator('.rd-room')).toBeVisible()
  await eve.context.close(); await dirk.context.close()
})

test('finn has no approve button, and Vault refuses a direct approve', async ({ browser }) => {
  const cleo = await pageAs(browser, 'cleo')
  await cleo.page.goto('/approvals')
  await cleo.page.getByRole('button', { name: 'Request the launch codes' }).click()
  await expect(notice(cleo.page)).toContainText('Requested')

  const finn = await pageAs(browser, 'finn')
  await finn.page.goto('/approvals')
  await expect(finn.page.getByRole('button', { name: 'Approve' })).toHaveCount(0)
  await expect(finn.page.getByRole('button', { name: 'Request the launch codes' })).toHaveCount(0)

  // Bypass the UI: finn's own session calls the BFF directly. The API asks
  // Vault with finn's token; Vault (not the UI) refuses.
  const res = await finn.page.request.get('/api/v1/doors/8/requests')
  const accessor = ((await res.json()).requests ?? [])[0]?.accessor ?? 'unknown-accessor'
  const r = await finn.page.request.post(`/api/v1/doors/8/requests/${encodeURIComponent(accessor)}/approve`)
  const body = await r.json().catch(() => ({}))
  expect(r.ok() && body.outcome !== 'denied' && !body.error).toBeFalsy()
  await cleo.context.close(); await finn.context.close()
})
