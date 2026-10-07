// playwright.config.ts — Red Doors UI journeys. Real OIDC (Keycloak → Vault),
// real Vault decisions on OpenShift Local. Nothing is mocked.
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './tests',
  globalSetup: './tests/global-setup.ts',
  fullyParallel: false,
  workers: 1, // journeys share one estate (door 8 requests, corridor progress)
  timeout: 90_000,
  expect: { timeout: 15_000 },
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'tests/.report' }]],
  outputDir: 'tests/.results',
  grepInvert: process.env.RD_ALL ? undefined : /@failover|@screens/,
  use: {
    baseURL: process.env.RED_DOORS_UI_URL ?? 'https://doors.apps-crc.testing',
    ...devices['Desktop Chrome'],
    viewport: { width: 1440, height: 900 },
    // The CRC Routes are signed by OpenShift Local's own ingress CA, which the
    // test browser does not trust. Only *.apps-crc.testing is visited.
    ignoreHTTPSErrors: true,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
})
