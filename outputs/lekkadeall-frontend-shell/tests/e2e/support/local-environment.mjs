import { spawn } from 'node:child_process';

const LOOPBACK_HOSTS = new Set(['127.0.0.1', 'localhost', '[::1]']);
const MAX_CAPTURE_BYTES = 2 * 1024 * 1024;

export function assertLoopbackUrl(value, label = 'target') {
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error(`${label}-url-invalid`);
  }
  if (!['http:', 'https:'].includes(parsed.protocol)
      || !LOOPBACK_HOSTS.has(parsed.hostname)
      || parsed.username
      || parsed.password) {
    throw new Error(`${label}-url-must-be-loopback`);
  }
  return parsed;
}

export function assertLocalDockerConfiguration(environment = process.env) {
  const dockerHost = String(environment.DOCKER_HOST ?? '').trim();
  if (dockerHost && !dockerHost.startsWith('unix://') && !dockerHost.startsWith('npipe://')) {
    throw new Error('e2e-refuses-remote-docker-host');
  }
}

export function parseSupabaseStatusEnv(output) {
  const approved = new Map();
  for (const line of String(output ?? '').split(/\r?\n/u)) {
    const match = /^([A-Z0-9_]+)=(?:"([^"]*)"|'([^']*)'|(.*))$/u.exec(line.trim());
    if (!match) continue;
    const key = match[1];
    if (!['ANON_KEY', 'API_URL', 'INBUCKET_URL'].includes(key)) continue;
    approved.set(key, match[2] ?? match[3] ?? match[4] ?? '');
  }

  const apiUrl = approved.get('API_URL');
  const inbucketUrl = approved.get('INBUCKET_URL') ?? 'http://127.0.0.1:54324';
  const anonKey = approved.get('ANON_KEY');
  assertLoopbackUrl(apiUrl, 'supabase');
  assertLoopbackUrl(`${apiUrl.replace(/\/$/u, '')}/auth/v1`, 'auth');
  assertLoopbackUrl(inbucketUrl, 'inbucket');
  if (!anonKey || anonKey.length < 40 || /service[_-]?role/iu.test(anonKey)) {
    throw new Error('local-anon-key-unavailable');
  }
  return Object.freeze({ apiUrl, inbucketUrl, anonKey });
}

function commandName(name) {
  return process.platform === 'win32' && ['npm', 'npx', 'pnpm'].includes(name)
    ? `${name}.cmd`
    : name;
}

export function runCaptured(name, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(commandName(name), args, {
      cwd: options.cwd,
      env: options.env ?? process.env,
      shell: false,
      stdio: ['pipe', 'pipe', 'pipe'],
      windowsHide: true,
    });
    const stdout = [];
    const stderr = [];
    let capturedBytes = 0;
    let overflow = false;

    const capture = (collection) => (chunk) => {
      capturedBytes += chunk.length;
      if (capturedBytes > MAX_CAPTURE_BYTES) {
        overflow = true;
        child.kill();
        return;
      }
      collection.push(chunk);
    };
    child.stdout.on('data', capture(stdout));
    child.stderr.on('data', capture(stderr));
    child.once('error', () => reject(new Error(`${name}-command-unavailable`)));
    child.once('close', (code) => {
      const result = {
        ok: code === 0 && !overflow,
        code,
        stdout: Buffer.concat(stdout).toString('utf8'),
        stderr: Buffer.concat(stderr).toString('utf8'),
      };
      if (!result.ok && !options.allowFailure) {
        reject(new Error(`${name}-command-failed`));
      } else {
        resolve(result);
      }
    });
    if (options.input !== undefined) child.stdin.end(options.input);
    else child.stdin.end();
  });
}

export async function waitForLoopbackHttp(url, timeoutMs = 20_000) {
  const parsed = assertLoopbackUrl(url, 'health-check');
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(parsed, { redirect: 'manual' });
      if (response.ok) return;
    } catch {
      // The local process may still be binding its loopback port.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('loopback-health-check-failed');
}

export { LOOPBACK_HOSTS };
