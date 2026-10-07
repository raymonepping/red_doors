// The corridor: keyboard walk and progress.
import { expect, test } from '@playwright/test'
import { pageAs } from './auth'

test('keyboard: → moves, K knocks, W tries the wrong key, D shows the decision', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'ada')
  await page.goto('/')
  const current = page.locator('.rd-hall__door[aria-current="step"]')
  await expect(current).toHaveAttribute('aria-label', /^Door 1:/)
  const progress = page.locator('.rd-corridor__progress .vg-tile__value')
  const start = Number((await progress.innerText()).split('/')[0])

  await page.locator('body').press('k')
  await expect(page.locator('.rd-stage .rd-door')).toHaveAttribute('data-state', 'open')
  await expect(page.locator('.rd-hall__door').first().locator('.rd-door')).toHaveAttribute('data-state', 'open')
  await expect(progress).toHaveText(new RegExp(`^${Math.max(start, 1)}`))

  await page.locator('body').press('w')
  await expect(page.locator('.rd-stage .rd-door')).toHaveAttribute('data-state', 'refused')

  await page.locator('body').press('d')
  await expect(page.getByRole('region', { name: 'How Vault decided' })).toBeInViewport()

  await page.locator('body').press('ArrowRight')
  await expect(current).toHaveAttribute('aria-label', /^Door 3:/)
  await page.locator('body').press('ArrowLeft')
  await expect(current).toHaveAttribute('aria-label', /^Door 1:/)
  await context.close()
})
