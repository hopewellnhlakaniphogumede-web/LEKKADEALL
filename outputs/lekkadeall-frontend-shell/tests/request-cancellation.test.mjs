import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CUSTOMER_CANCEL_DRAFT_RPC,
  DRAFT_CANCELLATION_AMBIGUOUS_MESSAGE,
  DRAFT_CANCELLATION_CONFIRM_TEXT,
  DRAFT_CANCELLATION_CONFIRM_TITLE,
  DRAFT_CANCELLATION_SUCCESS_MESSAGE,
  DRAFT_CANCELLATION_UNAVAILABLE_MESSAGE,
  cancelCustomerDraft,
} from '../request-cancellation.js';
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
    requested_start: '2026-07-20T07:30:00Z',
    budget_minor: 250050,
    status,
    created_at: '2026-07-18T08:15:00Z',
    updated_at: '2026-07-19T10:45:00Z',
  };
}

function detailView(status = 'draft', cancellation = {}) {
  return {
    access: allowedAccess,
    categories: [{ id: categoryId, name: 'Painting' }],
    customerRequestDetail: { ok: true, data: request(status) },
    customerDraftCancellation: {
      requestId,
      confirming: false,
      submitting: false,
      confirmed: false,
      blocked: false,
      message: '',
      ...cancellation,
    },
  };
}

test('strict cancellation RPC sends only the validated request UUID', async () => {
  const calls = [];
  const client = {
    rpc: async (...args) => {
      calls.push(args);
      return { data: 'cancelled', error: null };
    },
  };
  assert.deepEqual(await cancelCustomerDraft(client, requestId), {
    ok: true,
    status: 'cancelled',
  });
  assert.equal(CUSTOMER_CANCEL_DRAFT_RPC, 'customer_cancel_draft_request');
  assert.deepEqual(calls, [[CUSTOMER_CANCEL_DRAFT_RPC, { p_request_id: requestId }]]);
});

test('invalid UUID fails before the RPC boundary', async () => {
  let calls = 0;
  const client = { rpc: async () => { calls += 1; return { data: 'cancelled', error: null }; } };
  assert.deepEqual(await cancelCustomerDraft(client, 'not-a-uuid'), {
    ok: false,
    kind: 'unavailable',
    message: DRAFT_CANCELLATION_UNAVAILABLE_MESSAGE,
  });
  assert.equal(calls, 0);
});

test('database policy failures and ambiguous failures remain generic', async () => {
  const denied = await cancelCustomerDraft({
    rpc: async () => ({
      data: null,
      error: { code: '42501', message: 'Draft is not available for cancellation', details: 'private detail' },
    }),
  }, requestId);
  assert.deepEqual(denied, {
    ok: false,
    kind: 'unavailable',
    message: DRAFT_CANCELLATION_UNAVAILABLE_MESSAGE,
  });

  for (const client of [
    { rpc: async () => ({ data: null, error: { code: '08006', message: 'network detail' } }) },
    { rpc: async () => ({ data: 'draft', error: null }) },
    { rpc: async () => { throw new Error('transport detail'); } },
  ]) {
    assert.deepEqual(await cancelCustomerDraft(client, requestId), {
      ok: false,
      kind: 'ambiguous',
      message: DRAFT_CANCELLATION_AMBIGUOUS_MESSAGE,
    });
  }
  assert.doesNotMatch(`${denied.message} ${DRAFT_CANCELLATION_AMBIGUOUS_MESSAGE}`, /private detail|network detail|transport detail|42501|08006/);
});

test('cancel control appears only on an active-customer draft detail', () => {
  const draft = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView('draft'));
  assert.match(draft, /data-cancel-draft-action="open"/);
  assert.match(draft, />Cancel draft</);

  for (const status of ['open', 'cancelled']) {
    const page = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView(status));
    assert.doesNotMatch(page, /data-cancel-draft-action|data-cancel-draft-form/);
  }

  const provider = renderRoute('/app/customer/requests/detail', new URLSearchParams(), {
    ...detailView('draft'),
    access: { kind: 'allowed', role: 'provider' },
  });
  assert.doesNotMatch(provider, /data-cancel-draft-action|data-cancel-draft-form/);

  const unavailable = renderRoute('/app/customer/requests/detail', new URLSearchParams(), {
    access: allowedAccess,
    customerRequestDetail: { ok: false, data: null, reason: 'not-found-or-unavailable' },
  });
  assert.doesNotMatch(unavailable, /data-cancel-draft-action|data-cancel-draft-form/);
});

test('request list never renders a cancellation control', () => {
  const list = renderRoute('/app/customer/requests', new URLSearchParams(), {
    access: allowedAccess,
    categories: [{ id: categoryId, name: 'Painting' }],
    customerRequestList: { ok: true, data: [request('draft')] },
  });
  assert.doesNotMatch(list, /data-cancel-draft-action|data-cancel-draft-form/);
});

test('confirmation uses fixed copy, no reason field and single submit action', () => {
  const confirmation = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView('draft', {
    confirming: true,
  }));
  assert.match(confirmation, new RegExp(DRAFT_CANCELLATION_CONFIRM_TITLE.replace('?', '\\?')));
  assert.match(confirmation, new RegExp(DRAFT_CANCELLATION_CONFIRM_TEXT.replace('.', '\\.')));
  assert.match(confirmation, /data-cancel-draft-form/);
  assert.match(confirmation, /data-cancel-draft-action="keep"/);
  assert.match(confirmation, />Keep draft</);
  assert.match(confirmation, />Cancel draft</);
  assert.doesNotMatch(confirmation, /<(?:input|textarea|select)[^>]*name="(?:reason|status|customer|provider|booking|address)/i);
});

test('submitting disables both confirmation actions without optimistic status', () => {
  const submitting = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView('draft', {
    confirming: true,
    submitting: true,
  }));
  assert.match(submitting, /Cancelling draft/);
  assert.equal((submitting.match(/disabled/g) ?? []).length >= 2, true);
  assert.match(submitting, />Draft</);
  assert.doesNotMatch(submitting, new RegExp(DRAFT_CANCELLATION_SUCCESS_MESSAGE.replace('.', '\\.')));
});

test('success is shown only with a freshly read cancelled detail result', () => {
  const confirmed = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView('cancelled', {
    confirmed: true,
    message: DRAFT_CANCELLATION_SUCCESS_MESSAGE,
  }));
  assert.match(confirmed, /Draft cancelled\./);
  assert.match(confirmed, /draft-cancellation-message is-success/);
  assert.doesNotMatch(confirmed, /data-cancel-draft-action|data-cancel-draft-form/);

  const unconfirmed = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView('draft', {
    blocked: true,
    message: DRAFT_CANCELLATION_AMBIGUOUS_MESSAGE,
  }));
  assert.match(unconfirmed, /Cancellation could not be confirmed/);
  assert.doesNotMatch(unconfirmed, /Draft cancelled\./);
  assert.doesNotMatch(unconfirmed, /data-cancel-draft-action|data-cancel-draft-form/);
});

test('app orchestration is single-flight and re-reads through the existing RLS helper', async () => {
  const source = await readFile(join(root, 'app.js'), 'utf8');
  assert.match(source, /draftCancellationInFlight/);
  assert.match(source, /if \(draftCancellationInFlight/);
  assert.match(source, /const result = await cancelCustomerDraft\(state\.client, requestId\);[\s\S]*freshDetail = await readOwnCustomerRequestDetail\(state\.client, requestId\);/);
  assert.match(source, /freshDetail\.data\?\.status === 'cancelled'/);
  assert.match(source, /state\.customerDraftCancellation\.blocked = true/);
  assert.doesNotMatch(source, /customerRequestDetail[^\n]*status\s*=\s*['"]cancelled/);
  assert.doesNotMatch(source, /setTimeout|setInterval|\bretry\b/i);
});

test('only the two reviewed frontend RPC boundaries exist and blocked capabilities remain absent', async () => {
  const moduleNames = (await readdir(root))
    .filter((name) => name.endsWith('.js') && !name.startsWith('runtime-config'));
  const entries = await Promise.all(moduleNames.map(async (name) => [name, await readFile(join(root, name), 'utf8')]));
  const rpcModules = entries
    .filter(([, source]) => source.includes('.rpc('))
    .map(([name]) => name)
    .sort();
  assert.deepEqual(rpcModules, ['request-cancellation.js', 'request-draft.js']);

  const cancellationSource = entries.find(([name]) => name === 'request-cancellation.js')[1];
  assert.equal((cancellationSource.match(/\.rpc\(/g) ?? []).length, 1);
  assert.match(cancellationSource, /\.rpc\(CUSTOMER_CANCEL_DRAFT_RPC, \{/);
  assert.doesNotMatch(cancellationSource, /p_reason|p_status|p_customer|p_provider|p_booking|metadata/);

  const allSource = entries.map(([, source]) => source).join('\n');
  const forbidden = [
    '.insert(', '.update(', '.upsert(', '.delete(', ".select('*')", '.select("*")',
    'customer_cancel_request', 'customer_publish_request',
    'customer_upsert_service_request_address', 'customer_get_service_request_address',
    'reveal_confirmed_booking_address', 'localStorage', 'sessionStorage', 'indexedDB',
    'serviceWorker', 'navigator.geolocation', 'SUPABASE_SERVICE_ROLE_KEY', 'service_role',
  ];
  for (const token of forbidden) {
    assert.equal(allSource.includes(token), false, `forbidden frontend token: ${token}`);
  }
});
