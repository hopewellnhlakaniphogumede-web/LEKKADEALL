import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CUSTOMER_PUBLISH_DRAFT_RPC,
  DRAFT_PUBLICATION_AMBIGUOUS_MESSAGE,
  DRAFT_PUBLICATION_CONFIRM_TEXT,
  DRAFT_PUBLICATION_CONFIRM_TITLE,
  DRAFT_PUBLICATION_SUCCESS_MESSAGE,
  DRAFT_PUBLICATION_UNAVAILABLE_MESSAGE,
  publishCustomerDraft,
} from '../request-publication.js';
import { renderRoute } from '../shell.js';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const categoryId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const allowedAccess = { kind: 'allowed', role: 'customer' };

function request(status = 'draft') {
  return {
    id: requestId,
    category_id: categoryId,
    title: 'Paint living room',
    description: 'Paint the living room walls and ceiling.',
    suburb: 'Woodstock',
    city: 'Cape Town',
    requested_start: '2026-08-20T07:30:00Z',
    budget_minor: 250050,
    status,
    created_at: '2026-08-08T08:15:00Z',
    updated_at: '2026-08-09T10:45:00Z',
  };
}

function detailView(status = 'draft', publication = {}, overrides = {}) {
  return {
    access: allowedAccess,
    accountStatus: 'active',
    categories: [{ id: categoryId, name: 'Painting' }],
    customerRequestDetail: { ok: true, data: request(status) },
    customerDraftCancellation: {
      requestId,
      confirming: false,
      submitting: false,
      confirmed: false,
      blocked: false,
      message: '',
    },
    customerDraftPublication: {
      requestId,
      confirming: false,
      submitting: false,
      confirmed: false,
      blocked: false,
      message: '',
      ...publication,
    },
    ...overrides,
  };
}

test('publication RPC sends exactly one request ID field', async () => {
  const calls = [];
  const client = {
    rpc: async (...args) => {
      calls.push(args);
      return { data: 'open', error: null };
    },
  };

  assert.deepEqual(await publishCustomerDraft(client, requestId), { ok: true, status: 'open' });
  assert.equal(CUSTOMER_PUBLISH_DRAFT_RPC, 'customer_publish_draft_request');
  assert.deepEqual(calls, [['customer_publish_draft_request', { p_request_id: requestId }]]);
});

test('invalid IDs and server or transport failures remain generic and are never retried', async () => {
  let invalidCalls = 0;
  const invalid = await publishCustomerDraft({
    rpc: async () => { invalidCalls += 1; },
  }, 'not-a-uuid');
  assert.deepEqual(invalid, {
    ok: false,
    kind: 'unavailable',
    message: DRAFT_PUBLICATION_UNAVAILABLE_MESSAGE,
  });
  assert.equal(invalidCalls, 0);

  const denied = await publishCustomerDraft({
    rpc: async () => ({ data: null, error: { code: '42501', message: 'private ownership detail' } }),
  }, requestId);
  assert.deepEqual(denied, {
    ok: false,
    kind: 'unavailable',
    message: DRAFT_PUBLICATION_UNAVAILABLE_MESSAGE,
  });

  for (const client of [
    { rpc: async () => ({ data: null, error: { code: '08006', message: 'network detail' } }) },
    { rpc: async () => ({ data: 'draft', error: null }) },
    { rpc: async () => { throw new Error('transport detail'); } },
  ]) {
    let calls = 0;
    const result = await publishCustomerDraft({
      rpc: async (...args) => {
        calls += 1;
        return client.rpc(...args);
      },
    }, requestId);
    assert.deepEqual(result, {
      ok: false,
      kind: 'ambiguous',
      message: DRAFT_PUBLICATION_AMBIGUOUS_MESSAGE,
    });
    assert.equal(calls, 1);
  }

  assert.doesNotMatch(
    `${denied.message} ${DRAFT_PUBLICATION_AMBIGUOUS_MESSAGE}`,
    /private ownership|network detail|transport detail|42501|08006|failed|succeeded/i,
  );
});

test('Publish request appears only for an eligible fresh draft detail', () => {
  const draft = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView());
  assert.match(draft, /data-publish-draft-action="open"/);
  assert.match(draft, />Publish request</);
  assert.doesNotMatch(draft, /data-publish-draft-form/);

  for (const status of ['open', 'cancelled']) {
    const page = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView(status));
    assert.doesNotMatch(page, /data-publish-draft-action|data-publish-draft-form/);
  }

  for (const access of [
    { kind: 'signedOut' },
    { kind: 'accessDenied' },
    { kind: 'restricted', accountStatus: 'restricted' },
    { kind: 'restricted', accountStatus: 'suspended' },
    { kind: 'restricted', accountStatus: 'closed' },
    { kind: 'allowed', role: 'provider' },
  ]) {
    const page = renderRoute('/app/customer/requests/detail', new URLSearchParams(), {
      ...detailView(),
      access,
    });
    assert.doesNotMatch(page, /data-publish-draft-action|data-publish-draft-form/);
  }

  const unavailable = renderRoute('/app/customer/requests/detail', new URLSearchParams(), {
    access: allowedAccess,
    accountStatus: 'active',
    customerRequestDetail: { ok: false, data: null, reason: 'not-found-or-unavailable' },
  });
  assert.doesNotMatch(unavailable, /data-publish-draft-action|data-publish-draft-form/);
});

test('publication requires fixed explicit confirmation with no submitted fields', () => {
  const confirmation = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView('draft', {
    confirming: true,
  }));
  assert.match(confirmation, new RegExp(DRAFT_PUBLICATION_CONFIRM_TITLE.replace('?', '\\?')));
  assert.match(confirmation, new RegExp(DRAFT_PUBLICATION_CONFIRM_TEXT.replace('.', '\\.')));
  assert.match(confirmation, /data-publish-draft-form/);
  assert.match(confirmation, /data-publish-draft-action="keep"/);
  assert.match(confirmation, />Keep draft</);
  assert.match(confirmation, />Publish request</);
  assert.doesNotMatch(confirmation, /<(?:input|textarea|select)[^>]*name=/i);
  assert.doesNotMatch(confirmation, /data-cancel-draft-action|>Edit draft</);
});

test('submitting is disabled and never renders optimistic open status or success', () => {
  const submitting = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView('draft', {
    confirming: true,
    submitting: true,
  }));
  assert.match(submitting, /Publishing request/);
  assert.equal((submitting.match(/disabled/g) ?? []).length >= 2, true);
  assert.match(submitting, />Draft</);
  assert.doesNotMatch(submitting, />Open</);
  assert.doesNotMatch(submitting, new RegExp(DRAFT_PUBLICATION_SUCCESS_MESSAGE.replace('.', '\\.')));
});

test('confirmed publication shows authoritative open status and removes all draft controls', () => {
  const confirmed = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView('open', {
    confirmed: true,
    message: DRAFT_PUBLICATION_SUCCESS_MESSAGE,
  }));
  assert.match(confirmed, />Open</);
  assert.match(confirmed, /Request published\./);
  assert.match(confirmed, /draft-publication-message is-success/);
  assert.doesNotMatch(confirmed, /data-publish-draft-action|data-publish-draft-form/);
  assert.doesNotMatch(confirmed, /data-cancel-draft-action|data-cancel-draft-form|>Edit draft</);
});

test('ambiguous publication blocks every draft mutation until a fresh view', () => {
  const blocked = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView('draft', {
    blocked: true,
    message: DRAFT_PUBLICATION_AMBIGUOUS_MESSAGE,
  }));
  assert.match(blocked, /Publication could not be confirmed/);
  assert.match(blocked, />Draft</);
  assert.doesNotMatch(blocked, /Request published\.|>Open</);
  assert.doesNotMatch(blocked, /data-publish-draft-action|data-publish-draft-form/);
  assert.doesNotMatch(blocked, /data-cancel-draft-action|data-cancel-draft-form|>Edit draft</);
});

test('app uses dedicated single-flight publication and verifies through a fresh own-detail read', async () => {
  const source = await readFile(join(root, 'app.js'), 'utf8');
  assert.match(source, /let draftPublicationInFlight = false;/);
  assert.match(source, /if \(draftPublicationInFlight \|\| path !== '\/app\/customer\/requests\/detail'\) return;/);
  assert.match(source, /draftPublicationInFlight = true;[\s\S]*const result = await publishCustomerDraft\(state\.client, requestId\);/);
  assert.match(source, /const result = await publishCustomerDraft\(state\.client, requestId\);[\s\S]*freshDetail = await readOwnCustomerRequestDetail\(state\.client, requestId\);/);
  assert.match(source, /freshDetail\.data\?\.id === requestId[\s\S]*freshDetail\.data\?\.status === 'open'/);
  assert.match(source, /state\.customerRequestDetail = freshDetail;/);
  assert.match(source, /state\.customerDraftPublication\.blocked = true;/);
  assert.equal((source.match(/await publishCustomerDraft\(state\.client, requestId\)/g) ?? []).length, 1);
  assert.doesNotMatch(source, /customerRequestDetail[^\n]*status\s*=\s*['"]open/);
  assert.doesNotMatch(source, /setTimeout|setInterval|\bretry\b/i);
});

test('publication is the only new RPC boundary and adds no DML, address or credential surface', async () => {
  const moduleNames = (await readdir(root)).filter((name) => name.endsWith('.js') && !name.startsWith('runtime-config'));
  const entries = await Promise.all(moduleNames.map(async (name) => [name, await readFile(join(root, name), 'utf8')]));
  const rpcModules = entries.filter(([, source]) => source.includes('.rpc(')).map(([name]) => name).sort();
  assert.deepEqual(rpcModules, [
    'provider-application.js',
    'provider-bidding.js',
    'provider-discovery.js',
    'request-cancellation.js',
    'request-draft.js',
    'request-publication.js',
    'request-update.js',
  ]);

  const publicationSource = entries.find(([name]) => name === 'request-publication.js')[1];
  assert.equal((publicationSource.match(/\.rpc\(/g) ?? []).length, 1);
  assert.match(publicationSource, /client\.rpc\('customer_publish_draft_request', \{\s*p_request_id: requestId,?\s*\}\)/);
  assert.doesNotMatch(publicationSource, /p_(?:status|customer|provider|booking|address|metadata)|address|ciphertext|select\(|from\(/i);

  const productionSource = entries.map(([, source]) => source).join('\n');
  for (const token of [
    '.insert(', '.update(', '.upsert(', '.delete(', ".select('*')", '.select("*")',
    'service_request_addresses', 'customer_get_service_request_address',
    'reveal_confirmed_booking_address', 'SUPABASE_SERVICE_ROLE_KEY', 'service_role',
    'localStorage', 'sessionStorage', 'indexedDB', 'console.log', 'analytics', 'telemetry',
  ]) {
    assert.equal(productionSource.includes(token), false, `forbidden frontend token: ${token}`);
  }
});
