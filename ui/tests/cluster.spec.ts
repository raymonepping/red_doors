// Cluster page: three nodes, one leader, the seal chain. @failover deletes the
// active pod (RD_FAILOVER=1 / make ui-test-failover) and waits for a new leader.
import { execFileSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { homedir } from 'node:os'
import { resolve } from 'node:path'
import { expect, test } from '@playwright/test'
import { pageAs } from './auth'
import { ROOT } from './users'

// CRC ships its own oc (crc oc-env); fall back to PATH.
const CRC_OC = resolve(homedir(), '.crc/bin/oc/oc')
const OC = process.env.OC ?? (existsSync(CRC_OC) ? CRC_OC : 'oc')

test('3 nodes, one leader, seal chain unsealed', async ({ browser }) => {
  const { context, page } = await pageAs(browser, 'finn')
  await page.goto('/cluster')
  const chain = page.getByRole('region', { name: 'Seal chain' })
  await expect(chain).toContainText('Seal Vault')
  await expect(chain.locator('.vg-pill', { hasText: /^\s*unsealed\s*$/ })).toBeVisible()
  const nodes = chain.locator('.rd-nodes .rd-node')
  await expect(nodes).toHaveCount(3)
  await expect(chain.locator('.rd-node[data-role="leader"]')).toHaveCount(1)
  await expect(page.locator('.vg-tile', { hasText: 'Main cluster' })).toContainText('3/3')
  await context.close()
})

test('@failover deleting the leader moves leadership', async ({ browser }) => {
  test.skip(!process.env.RD_FAILOVER, 'set RD_FAILOVER=1 to delete the active Vault pod')
  test.setTimeout(240_000)
  const { context, page } = await pageAs(browser, 'finn')
  await page.goto('/cluster')
  const leaderNode = page.locator('.rd-node[data-role="leader"] strong')
  const before = (await leaderNode.innerText()).trim()
  execFileSync(OC, ['-n', 'rd-vault', 'delete', 'pod', before, '--wait=false'], {
    env: { ...process.env, KUBECONFIG: resolve(ROOT, '.secrets/kube/config') },
  })
  await expect(async () => {
    await page.reload()
    const now = (await leaderNode.innerText({ timeout: 4_000 })).trim()
    expect(now).not.toBe(before)
  }).toPass({ timeout: 120_000, intervals: [5_000] })
  await expect(async () => {
    await page.reload()
    await expect(page.locator('.vg-tile', { hasText: 'Main cluster' })).toContainText('3/3', { timeout: 4_000 })
  }).toPass({ timeout: 150_000, intervals: [5_000] })
  await context.close()
})
