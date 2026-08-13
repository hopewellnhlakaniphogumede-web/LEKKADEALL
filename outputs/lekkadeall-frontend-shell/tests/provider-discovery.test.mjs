import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  PROVIDER_DISCOVERY_FIELDS,
  PROVIDER_DISCOVERY_PAGE_SIZE,
  PROVIDER_DISCOVERY_RPC,
  readProviderDiscoveryPage,
} from '../provider-discovery.js';
import { renderRoute } from '../shell.js';

const here = dirname(fileURLToPath(import.meta.url));
const frontendRoot = resolve(here, '..');
const request = Object.freeze({
  request_id: '11111111-1111-4111-8111-111111111111',
  category_id: '22222222-2222-4222-8222-222222222222',
  title: 'Repair a safe synthetic fixture',
  description: 'Repair the reviewed synthetic fixture without private information.',
  suburb: 'Woodstock',
  city: 'Cape Town',
  requested_start: '2030-01-05T10:00:00.000Z',
  budget_minor: 125000,
  closes_at: '2030-01-03T10:00:00.000Z',
  published_at: '2030-01-01T10:00:00.000Z',
});

function rpcClient(response = { data: [request], error: null }) {
  const calls = [];
  return {
    calls,
    client: {
      async rpc(name, payload) {
        calls.push({ name, payload });
        return response;
      },
    },
  };
}

function providerView(discovery) {
  return {
    sessionReady: true,
    access: { kind: 'allowed', role: 'provider' },
    providerStatus: {
      ok: true,
      data: {
        business_name: 'Synthetic services',
        verification_status: 'not_started',
        review_status: 'approved',
        service_radius_km: 20,
      },
    },
    providerApplication: {},
    providerDiscovery: discovery,
  };
}

test('provider discovery calls only the approved RPC with the exact initial payload', async () => {
  const mock = rpcClient();
  const result = await readProviderDiscoveryPage(mock.client);
  assert.equal(result.ok, true);
  assert.equal(PROVIDER_DISCOVERY_RPC, 'provider_list_discoverable_requests');
  assert.equal(PROVIDER_DISCOVERY_PAGE_SIZE, 20);
  assert.deepEqual(mock.calls, [{
    name: 'provider_list_discoverable_requests',
    payload: {
      p_page_size: 20,
      p_cursor_published_at: null,
      p_cursor_request_id: null,
    },
  }]);
});

test('provider discovery uses only the last row keyset cursor and never sends offset or authority input', async () => {
  const mock = rpcClient({ data: [], error: null });
  const cursor = { publishedAt: request.published_at, requestId: request.request_id };
  const result = await readProviderDiscoveryPage(mock.client, { pageSize: 1, cursor });
  assert.equal(result.ok, true);
  assert.deepEqual(mock.calls[0].payload, {
    p_page_size: 1,
    p_cursor_published_at: request.published_at,
    p_cursor_request_id: request.request_id,
  });
  assert.deepEqual(Object.keys(mock.calls[0].payload).sort(), [
    'p_cursor_published_at', 'p_cursor_request_id', 'p_page_size',
  ]);
});

test('provider discovery consumes and returns exactly the ten reviewed fields', async () => {
  const extraFields = {
    ...request,
    customer_id: '33333333-3333-4333-8333-333333333333',
    precise_address_ciphertext: 'forbidden-fixture-value',
    payment_status: 'forbidden-fixture-value',
  };
  const mock = rpcClient({ data: [extraFields], error: null });
  const result = await readProviderDiscoveryPage(mock.client);
  assert.equal(result.ok, true);
  assert.deepEqual(Object.keys(result.data[0]), PROVIDER_DISCOVERY_FIELDS);
  assert.deepEqual(result.data[0], request);
  assert.deepEqual(result.cursor, {
    publishedAt: request.published_at,
    requestId: request.request_id,
  });
});

test('invalid bounds, partial cursors, malformed rows and server failures fail closed without another call', async () => {
  for (const options of [
    { pageSize: 0 },
    { pageSize: 51 },
    { pageSize: null },
    { cursor: { publishedAt: request.published_at } },
    { cursor: { requestId: request.request_id } },
  ]) {
    const mock = rpcClient();
    const result = await readProviderDiscoveryPage(mock.client, options);
    assert.deepEqual(result, {
      ok: false, data: [], cursor: null, hasMore: false, reason: 'discovery-unavailable',
    });
    assert.equal(mock.calls.length, 0);
  }

  const malformed = rpcClient({ data: [{ ...request, published_at: '' }], error: null });
  assert.equal((await readProviderDiscoveryPage(malformed.client)).ok, false);
  const denied = rpcClient({ data: null, error: { code: '42501' } });
  assert.equal((await readProviderDiscoveryPage(denied.client)).ok, false);
});

test('provider UI renders only reviewed discovery fields with escaped database text', () => {
  const hostile = { ...request, title: '<script>unsafe</script>', description: '<img src=x>' };
  const page = renderRoute('/app/provider', new URLSearchParams(), providerView({
    status: 'ready', items: [hostile], cursor: null, hasMore: true, loadingMore: false,
  }));
  assert.match(page, /data-provider-discovery/);
  assert.match(page, /&lt;script&gt;unsafe&lt;\/script&gt;/);
  assert.match(page, /&lt;img src=x&gt;/);
  assert.doesNotMatch(page, /<script>unsafe<\/script>|<img src=x>/u);
  for (const value of [
    request.request_id,
    request.category_id,
    request.suburb,
    request.city,
  ]) assert.match(page, new RegExp(value));
  assert.match(page, /Load more/);
  const discoveryStart = page.indexOf('data-provider-discovery');
  const discoveryEnd = page.indexOf('class="mock-banner"');
  assert.ok(discoveryStart >= 0 && discoveryEnd > discoveryStart);
  assert.doesNotMatch(
    page.slice(discoveryStart, discoveryEnd),
    /customer_id|customer email|exact address|ciphertext|coordinates|payment_status|booking_id|audit_metadata|created_at|updated_at/iu,
  );
});

test('failed fresh discovery clears stale cards and shows one generic unavailable state', () => {
  const page = renderRoute('/app/provider', new URLSearchParams(), providerView({
    status: 'unavailable', items: [], cursor: null, hasMore: false, loadingMore: false,
  }));
  assert.match(page, /Request discovery unavailable/);
  assert.match(page, /Request discovery is unavailable right now\./);
  assert.doesNotMatch(page, new RegExp(request.title));
  assert.doesNotMatch(page, /suspended|restricted|expired|not approved|missing service|42501/iu);
});

test('signed-out and wrong-role routes render no provider discovery boundary', () => {
  const signedOut = renderRoute('/app/provider', new URLSearchParams(), {
    access: { kind: 'signedOut' }, providerDiscovery: { status: 'ready', items: [request] },
  });
  const customer = renderRoute('/app/provider', new URLSearchParams(), {
    access: { kind: 'accessDenied' }, providerDiscovery: { status: 'ready', items: [request] },
  });
  for (const page of [signedOut, customer]) {
    assert.doesNotMatch(page, /data-provider-discovery|Refresh requests|Load more/u);
    assert.doesNotMatch(page, new RegExp(request.title));
  }
});

test('application wiring is single-flight, fresh-action-only and contains no alternate discovery path', async () => {
  const [moduleSource, appSource] = await Promise.all([
    readFile(join(frontendRoot, 'provider-discovery.js'), 'utf8'),
    readFile(join(frontendRoot, 'app.js'), 'utf8'),
  ]);
  assert.equal((moduleSource.match(/client\.rpc\(PROVIDER_DISCOVERY_RPC/gu) ?? []).length, 1);
  assert.doesNotMatch(
    moduleSource,
    /\.from\(|service_requests|list_provider_open_request_summaries|select\(|offset|total_count|p_(?:provider|category|role|status|eligibility)/iu,
  );
  assert.match(appSource, /let providerDiscoveryInFlight = false;/);
  assert.match(appSource, /if \(providerDiscoveryInFlight[\s\S]*return;/u);
  assert.match(appSource, /providerDiscoveryInFlight = true;[\s\S]*await readProviderDiscoveryPage[\s\S]*providerDiscoveryInFlight = false;/u);
  assert.match(appSource, /action === 'refresh'[\s\S]*loadProviderDiscovery\(\)/u);
  assert.match(appSource, /action === 'load-more'[\s\S]*loadProviderDiscovery\(\{ append: true \}\)/u);
  assert.doesNotMatch(`${moduleSource}\n${appSource}`, /setInterval|setTimeout|requestAnimationFrame|MutationObserver|prefetch|maxRetries|\bretry\b/iu);
  assert.doesNotMatch(moduleSource, /localStorage|sessionStorage|indexedDB|caches|cookie|console\.|location\./iu);
});
