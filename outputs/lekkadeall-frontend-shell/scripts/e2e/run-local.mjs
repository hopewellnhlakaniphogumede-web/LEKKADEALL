import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { access, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  assertLocalDockerConfiguration,
  assertLoopbackUrl,
  parseLocalFixtureAdminEnv,
  parseSupabaseStatusEnv,
  runCaptured,
  waitForLoopbackHttp,
} from '../../tests/e2e/support/local-environment.mjs';
import { seedBaseFixtures } from '../../tests/e2e/support/local-fixtures.mjs';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const frontendRoot = resolve(scriptDirectory, '../..');
const foundationRoot = resolve(frontendRoot, '../marketplace-production-foundation');
const runtimeConfigPath = join(frontendRoot, 'runtime-config.local.js');
const staticServerPath = join(scriptDirectory, 'static-server.mjs');
const appUrl = 'http://127.0.0.1:4173';
const outputDirectory = join(tmpdir(), `lekkadeall-e2e-output-${process.pid}`);
const WORKFLOW_RUN_PATTERN = /^[0-9]{1,20}$/u;
const WORKFLOW_ATTEMPT_PATTERN = /^[0-9]{1,6}$/u;
const TEST_SCOPE_ARGS = Object.freeze({
  full: ['--grep-invert', '(?:eligible provider discovers one safe matching request and loses it after revocation|eligible provider submits and withdraws one server-reconciled bid)'],
  discovery: ['--grep', 'eligible provider discovers one safe matching request and loses it after revocation'],
  bidding: ['--grep', 'eligible provider submits and withdraws one server-reconciled bid'],
  lifecycle: ['--grep', 'customer registration through cancelled draft completes against real local RLS and RPCs'],
  aborted: ['--grep', 'an executed update with an aborted response is not retried and requires a fresh read'],
  affected: ['--grep', '(?:customer registration through cancelled draft completes against real local RLS and RPCs|an executed update with an aborted response is not retried and requires a fresh read)'],
});
const testScope = String(process.env.E2E_TEST_SCOPE ?? 'full');

function buildRunId(scope) {
  const workflowRun = WORKFLOW_RUN_PATTERN.test(String(process.env.GITHUB_RUN_ID ?? ''))
    ? String(process.env.GITHUB_RUN_ID)
    : `local${process.pid}`;
  const workflowAttempt = WORKFLOW_ATTEMPT_PATTERN.test(String(process.env.GITHUB_RUN_ATTEMPT ?? ''))
    ? String(process.env.GITHUB_RUN_ATTEMPT)
    : '0';
  const scopeComponent = createHash('sha256')
    .update(`${workflowRun}:${workflowAttempt}:${scope}`)
    .digest('hex')
    .slice(0, 8);
  return `r${workflowRun}-a${workflowAttempt}-${scopeComponent}`;
}

const runId = buildRunId(testScope);
let frontendServer;
let supabaseStarted = false;
let runtimeConfigCreated = false;

function safeChildEnvironment(extra = {}) {
  const allowedNames = [
    'APPDATA', 'CI', 'HOME', 'LOCALAPPDATA', 'PATH', 'PATHEXT',
    'PLAYWRIGHT_BROWSERS_PATH', 'SystemRoot', 'TEMP', 'TMP', 'USERPROFILE', 'WINDIR',
  ];
  const safe = {};
  for (const name of allowedNames) {
    if (process.env[name] !== undefined) safe[name] = process.env[name];
  }
  return { ...safe, ...extra };
}

function assertCleanupPath(target) {
  const resolved = resolve(target);
  const temporaryRoot = resolve(tmpdir());
  if (!resolved.startsWith(`${temporaryRoot}${sep}`)
      || !basename(resolved).startsWith('lekkadeall-e2e-output-')) {
    throw new Error('e2e-cleanup-path-rejected');
  }
  return resolved;
}

function runPlaywright(environment) {
  return new Promise((resolvePromise, reject) => {
    const scopeArgs = TEST_SCOPE_ARGS[testScope];
    if (!scopeArgs) {
      reject(new Error('e2e-test-scope-invalid'));
      return;
    }
    const command = process.platform === 'win32' ? 'pnpm.cmd' : 'pnpm';
    const child = spawn(command, ['exec', 'playwright', 'test', ...scopeArgs], {
      cwd: frontendRoot,
      env: environment,
      shell: false,
      stdio: ['ignore', 'inherit', 'inherit'],
      windowsHide: true,
    });
    child.once('error', () => reject(new Error('playwright-command-unavailable')));
    child.once('close', (code) => {
      if (code === 0) resolvePromise();
      else reject(new Error('playwright-e2e-failed'));
    });
  });
}

async function startFrontendServer() {
  frontendServer = spawn(process.execPath, [staticServerPath], {
    cwd: frontendRoot,
    env: safeChildEnvironment({
      E2E_FRONTEND_HOST: '127.0.0.1',
      E2E_FRONTEND_PORT: '4173',
    }),
    shell: false,
    stdio: ['ignore', 'ignore', 'ignore'],
    windowsHide: true,
  });
  frontendServer.once('error', () => {});
  await waitForLoopbackHttp(appUrl);
}

async function stopFrontendServer() {
  if (!frontendServer || frontendServer.exitCode !== null) return;
  frontendServer.kill('SIGTERM');
  await new Promise((resolvePromise) => {
    const fallback = setTimeout(resolvePromise, 2_000);
    frontendServer.once('close', () => {
      clearTimeout(fallback);
      resolvePromise();
    });
  });
}

async function cleanup() {
  await stopFrontendServer();
  if (runtimeConfigCreated) await rm(runtimeConfigPath, { force: true });
  await rm(assertCleanupPath(outputDirectory), { recursive: true, force: true });
  if (supabaseStarted) {
    await runCaptured('supabase', ['stop', '--no-backup'], {
      cwd: foundationRoot,
      env: safeChildEnvironment(),
      allowFailure: true,
    });
  }
}

async function main() {
  assertLoopbackUrl(appUrl, 'frontend');
  assertLocalDockerConfiguration();
  try {
    await access(runtimeConfigPath);
    throw new Error('e2e-refuses-existing-runtime-config');
  } catch (error) {
    if (error?.message === 'e2e-refuses-existing-runtime-config') throw error;
    if (error?.code !== 'ENOENT') throw new Error('e2e-runtime-config-check-failed');
  }

  const existing = await runCaptured('supabase', ['status'], {
    cwd: foundationRoot,
    env: safeChildEnvironment(),
    allowFailure: true,
  });
  if (existing.ok) throw new Error('e2e-refuses-preexisting-supabase-stack');

  process.stdout.write('Ticket 9A-9: starting disposable local Supabase\n');
  await runCaptured('supabase', ['start'], { cwd: foundationRoot, env: safeChildEnvironment() });
  supabaseStarted = true;
  await runCaptured('supabase', ['db', 'reset'], { cwd: foundationRoot, env: safeChildEnvironment() });

  const statusResult = await runCaptured('supabase', ['status', '-o', 'env'], {
    cwd: foundationRoot,
    env: safeChildEnvironment(),
  });
  const local = parseSupabaseStatusEnv(statusResult.stdout);
  const localFixtureAdmin = parseLocalFixtureAdminEnv(statusResult.stdout);
  statusResult.stdout = '';
  statusResult.stderr = '';

  await seedBaseFixtures();
  const runtimeConfig = `// Generated for disposable local Ticket 9A-9 E2E only.\n`
    + `globalThis.__LEKKADEALL_PUBLIC_CONFIG__ = Object.freeze(${JSON.stringify({
      appEnv: 'test',
      appUrl,
      supabaseUrl: local.apiUrl,
      supabaseAnonKey: local.anonKey,
    })});\n`;
  await writeFile(runtimeConfigPath, runtimeConfig, { encoding: 'utf8', flag: 'wx' });
  runtimeConfigCreated = true;

  await startFrontendServer();
  process.stdout.write('Ticket 9A-9: running Chromium E2E against loopback only\n');
  await runPlaywright(safeChildEnvironment({
    E2E_LOCAL_STACK_READY: '1',
    E2E_APP_URL: appUrl,
    E2E_SUPABASE_URL: local.apiUrl,
    E2E_INBUCKET_URL: local.inbucketUrl,
    E2E_ANON_KEY: local.anonKey,
    E2E_LOCAL_FIXTURE_ADMIN_KEY: localFixtureAdmin.adminKey,
    E2E_OUTPUT_DIR: outputDirectory,
    E2E_RUN_ID: runId,
  }));
}

try {
  await main();
  process.stdout.write('Ticket 9A-9: local E2E completed\n');
} catch {
  process.stderr.write('Ticket 9A-9 local E2E failed (details withheld by privacy policy)\n');
  process.exitCode = 1;
} finally {
  await cleanup();
}
