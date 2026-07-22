import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { defineConfig, devices } from '@playwright/test';
import { assertLoopbackUrl } from './tests/e2e/support/local-environment.mjs';

const baseURL = process.env.E2E_APP_URL ?? 'http://127.0.0.1:4173';
assertLoopbackUrl(baseURL, 'frontend');

export default defineConfig({
  testDir: './tests/e2e',
  testMatch: '**/*.spec.mjs',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  forbidOnly: Boolean(process.env.CI),
  preserveOutput: 'never',
  outputDir: process.env.E2E_OUTPUT_DIR
    ?? join(tmpdir(), `lekkadeall-playwright-${process.pid}`),
  reporter: [['./tests/e2e/support/privacy-safe-reporter.mjs']],
  use: {
    baseURL,
    browserName: 'chromium',
    headless: true,
    screenshot: 'off',
    video: 'off',
    trace: 'off',
    acceptDownloads: false,
    serviceWorkers: 'allow',
  },
  projects: [{
    name: 'chromium',
    use: {
      ...devices['Desktop Chrome'],
      browserName: 'chromium',
    },
  }],
});
