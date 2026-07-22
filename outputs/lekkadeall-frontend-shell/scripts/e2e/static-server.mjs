import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const frontendRoot = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const host = process.env.E2E_FRONTEND_HOST ?? '127.0.0.1';
const port = Number(process.env.E2E_FRONTEND_PORT ?? '4173');

if (host !== '127.0.0.1' || port !== 4173) {
  throw new Error('e2e-static-server-requires-reviewed-loopback-target');
}

const contentTypes = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
]);

function allowedFile(pathname) {
  if (pathname === '/node_modules/@supabase/supabase-js/dist/umd/supabase.js') return true;
  if (pathname.startsWith('/node_modules/') || pathname.startsWith('/tests/') || pathname.startsWith('/scripts/')) return false;
  if (pathname.includes('/.') || /(?:package|pnpm-lock|playwright\.config|\.env)/i.test(pathname)) return false;
  if (pathname === '/runtime-config.local.js') return true;
  if (pathname === '/runtime-config.example.js') return false;
  if (/^\/[a-z0-9-]+\.js$/i.test(pathname) || pathname === '/styles.css') return true;
  return pathname === '/' || pathname.endsWith('/') || !extname(pathname);
}

function resolveRequestFile(pathname) {
  if (!allowedFile(pathname)) return null;
  let relative = decodeURIComponent(pathname).replace(/^\/+/, '');
  if (!relative || pathname.endsWith('/')) relative = join(relative, 'index.html');
  let target = resolve(frontendRoot, normalize(relative));
  if (target !== frontendRoot && !target.startsWith(`${frontendRoot}${sep}`)) return null;
  try {
    if (statSync(target).isDirectory()) target = join(target, 'index.html');
    if (!statSync(target).isFile()) return null;
  } catch {
    return null;
  }
  return target;
}

const server = createServer((request, response) => {
  if (!request.url || request.method !== 'GET') {
    response.writeHead(405, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Method not allowed');
    return;
  }

  let pathname;
  try {
    pathname = new URL(request.url, `http://${host}:${port}`).pathname;
  } catch {
    response.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Bad request');
    return;
  }

  const target = resolveRequestFile(pathname);
  if (!target) {
    response.writeHead(404, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
    createReadStream(join(frontendRoot, '404.html')).pipe(response);
    return;
  }

  response.writeHead(200, {
    'content-type': contentTypes.get(extname(target)) ?? 'application/octet-stream',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
  });
  createReadStream(target).pipe(response);
});

server.listen(port, host, () => {
  process.stdout.write('Ticket 9A-9 local frontend ready\n');
});

function stop() {
  server.close(() => process.exit(0));
}

process.once('SIGINT', stop);
process.once('SIGTERM', stop);
