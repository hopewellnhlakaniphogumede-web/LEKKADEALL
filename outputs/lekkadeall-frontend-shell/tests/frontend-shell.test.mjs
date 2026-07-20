import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  MOCK_PAYMENT_LABEL,
  ROUTES,
  isKnownRoute,
  mockPaymentBanner,
  pageState,
  renderRoute,
} from '../shell.js';

const here = dirname(fileURLToPath(import.meta.url));
const shellRoot = join(here, '..');

test('required routes exist and no admin route is registered', () => {
  const required = [
    '/', '/services', '/auth/sign-in', '/auth/register', '/auth/forgot-password',
    '/auth/reset-password', '/auth/callback', '/app/customer', '/app/provider',
    '/app/settings', '/access-denied', '/account-restricted',
  ];
  required.splice(
    required.indexOf('/app/provider'),
    0,
    '/app/customer/requests',
    '/app/customer/requests/detail',
    '/app/customer/requests/edit',
    '/app/customer/requests/new',
  );
  assert.deepEqual(ROUTES, required);
  assert.equal(ROUTES.some((route) => route.startsWith('/admin')), false);
  assert.equal(isKnownRoute('/services/'), true);
  assert.equal(isKnownRoute('/not-real'), false);
});

test('MockPaymentBanner uses the exact required wording', () => {
  assert.equal(MOCK_PAYMENT_LABEL, 'Mock/sandbox — no real money moved');
  assert.match(mockPaymentBanner(), /Mock\/sandbox — no real money moved/);
  assert.match(renderRoute('/app/customer'), /Mock\/sandbox — no real money moved/);
  assert.match(renderRoute('/app/provider'), /Mock\/sandbox — no real money moved/);
});

test('safe application states are available', () => {
  for (const state of ['loading', 'empty', 'error', 'signedOut', 'expired', 'restricted', 'notFound']) {
    assert.match(pageState(state, 'Title', 'Message'), new RegExp(`data-state="${state}"`));
  }
  assert.match(renderRoute('/missing-page'), /data-state="notFound"/);
  assert.match(renderRoute('/account-restricted'), /data-state="restricted"/);
  assert.match(renderRoute('/app/customer'), /data-state="signedOut"/);
});

test('service discovery defaults to a safe empty state without data', () => {
  const page = renderRoute('/services');
  assert.match(page, /data-state="empty"/);
  assert.match(page, /Only active categories permitted by existing RLS/);
  assert.doesNotMatch(page, /customer_id|precise_address_ciphertext|provider_reference/);
});

test('registration form contains no privileged application fields', () => {
  const register = renderRoute('/auth/register');
  assert.match(register, /data-auth-form="register"/);
  assert.doesNotMatch(register, /name="role"|account_status|verification_status|review_status/);
});

test('client source contains no application writes or sensitive function calls', async () => {
  const sources = await Promise.all([
    'app.js', 'shell.js', 'safe-reads.js', 'route-guards.js', 'supabase-public-client.js',
  ].map((name) => readFile(join(shellRoot, name), 'utf8')));
  const source = sources.join('\n');
  const forbidden = [
    '.insert(', '.upsert(', '.delete(', '.rpc(', 'admin_process_verified_mock_payment_webhook',
    'admin_set_', 'private.', 'service_role', 'webhook_secret', 'provider_secret',
    'identity_secret', '/admin', 'customer_select_cash_payment', 'provider_select_cash_payment',
  ];
  for (const token of forbidden) assert.equal(source.includes(token), false, `forbidden client token: ${token}`);
});

test('client has no payment credential or payment-method form fields', async () => {
  const source = await readFile(join(shellRoot, 'shell.js'), 'utf8');
  assert.doesNotMatch(source, /name="(?:card|cvv|bank|payment_method)"/i);
  assert.doesNotMatch(source, /type="(?:file)"/i);
});

test('clean-path entry files exist for every non-root route', async () => {
  for (const route of ROUTES.filter((route) => route !== '/')) {
    const html = await readFile(join(shellRoot, route.slice(1), 'index.html'), 'utf8');
    assert.match(html, /id="app"/);
    assert.match(html, /src="\/app\.js"/);
  }
});
