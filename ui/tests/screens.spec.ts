// @screens — every screen at 1440×900 and 390×844 → docs/screenshots/ui/.
// npx playwright test --grep @screens  (RD_ALL=1 lifts the default grepInvert)
import { mkdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { test } from '@playwright/test'
import { BASE, pageAs } from './auth'
import { ROOT } from './users'

const OUT = resolve(ROOT, 'docs/screenshots/ui')
const SCREENS: [string, string][] = [
  ['corridor', '/'], ['doors', '/doors'], ['door-1', '/doors/1'], ['door-2', '/doors/2'], ['door-5', '/doors/5'],
  ['door-8', '/doors/8'], ['approvals', '/approvals'], ['audit', '/audit'], ['cluster', '/cluster'],
]

for (const [w, h, suffix] of [[1440, 900, 'desktop'], [390, 844, 'mobile']] as const) {
  test(`@screens ${suffix}`, async ({ browser }) => {
    test.setTimeout(180_000)
    mkdirSync(OUT, { recursive: true })
    const anon = await browser.newContext({ viewport: { width: w, height: h }, ignoreHTTPSErrors: true })
    const lp = await anon.newPage()
    await lp.goto(`${BASE}/login`)
    await lp.waitForLoadState('networkidle')
    await lp.screenshot({ path: `${OUT}/login-${suffix}.png`, fullPage: true })
    await anon.close()

    const { context, page } = await pageAs(browser, 'ada', { viewport: { width: w, height: h } })
    for (const [name, route] of SCREENS) {
      await page.goto(route)
      await page.waitForLoadState('networkidle')
      await page.waitForTimeout(800)
      await page.screenshot({ path: `${OUT}/${name}-${suffix}.png`, fullPage: true })
    }
    await context.close()
  })
}
