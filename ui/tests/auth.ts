// Sign-in helpers — the real Keycloak login page, nothing stubbed.
import type { Browser, Page } from '@playwright/test'
import { passwordOf, stateFile, type User } from './users'

export const BASE = process.env.RED_DOORS_UI_URL ?? 'https://doors.apps-crc.testing'

export async function signIn(page: Page, user: User) {
  await page.goto(`${BASE}/login`)
  await page.getByTestId('sign-in').click()
  await page.waitForURL(/\/realms\//)
  await page.locator('#username').fill(user)
  await page.locator('#password').fill(passwordOf(user))
  await page.locator('#kc-login').click()
  await page.waitForURL(u => u.href.startsWith(BASE) && !/^\/(login|auth)/.test(u.pathname), { timeout: 30_000 })
}

/** A signed-in page for `user`, restored from global-setup's storageState. */
export async function pageAs(browser: Browser, user: User, opts: Parameters<Browser['newContext']>[0] = {}) {
  const context = await browser.newContext({ storageState: stateFile(user), ignoreHTTPSErrors: true, ...opts })
  const page = await context.newPage()
  return { context, page }
}
