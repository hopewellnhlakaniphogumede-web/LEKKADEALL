import {
  createMockWebhookSignature,
  createPaymentWebhookHandler,
  MOCK_SIGNATURE_HEADER,
  MOCK_TIMESTAMP_HEADER,
  sha256PayloadHash,
  type VerifiedMockPaymentWebhook,
} from './index.ts';

const encoder = new TextEncoder();
const FIXED_NOW_MS = Date.parse('2026-07-13T12:00:00.000Z');
const FIXED_TIMESTAMP = String(Math.floor(FIXED_NOW_MS / 1000));
const MOCK_SECRET = 'ticket-8b-local-ci-mock-secret';

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}\nactual: ${String(actual)}\nexpected: ${String(expected)}`);
  }
}

function assertNotIncludes(haystack: string, needle: string, message: string): void {
  if (haystack.includes(needle)) {
    throw new Error(message);
  }
}

function makeEnv(overrides: Record<string, string | undefined> = {}) {
  const values: Record<string, string | undefined> = {
    APP_ENV: 'test',
    PAYMENT_PROVIDER_MODE: 'mock',
    PAYMENT_WEBHOOK_SECRET_MOCK: MOCK_SECRET,
    PAYMENT_WEBHOOK_TOLERANCE_SECONDS: '300',
    SUPABASE_URL: 'http://127.0.0.1:54321',
    SUPABASE_SERVICE_ROLE_KEY: 'test-service-role-placeholder',
    ...overrides,
  };
  const requested: string[] = [];

  return {
    requested,
    env(name: string) {
      requested.push(name);
      return values[name];
    },
  };
}

function paidPayload(providerReference = 'ticket-8b-paid'): string {
  return [
    '{',
    '  "id": "evt_ticket_8b_paid",',
    '  "type": "mock.payment.paid",',
    `  "provider_reference": "${providerReference}",`,
    '  "idempotency_key": "idem_ticket_8b_paid",',
    '  "occurred_at": "2026-07-13T12:00:00.000Z",',
    '  "data": { "safe_note": "metadata outside data is intentionally ignored" }',
    '}',
  ].join('\n');
}

function failedPayload(): string {
  return JSON.stringify({
    id: 'evt_ticket_8b_failed',
    type: 'mock.payment.failed',
    provider_reference: 'ticket-8b-failed',
    idempotency_key: 'idem_ticket_8b_failed',
    occurred_at: '2026-07-13T12:01:00.000Z',
  });
}

async function makeRequest(args: {
  rawBody: string;
  secret?: string;
  timestamp?: string;
  signature?: string | null;
  method?: string;
}): Promise<Request> {
  const timestamp = args.timestamp ?? FIXED_TIMESTAMP;
  const rawBytes = encoder.encode(args.rawBody);
  const signature = args.signature === undefined
    ? await createMockWebhookSignature(args.secret ?? MOCK_SECRET, timestamp, rawBytes)
    : args.signature;
  const headers = new Headers({
    'content-type': 'application/json',
    [MOCK_TIMESTAMP_HEADER]: timestamp,
  });

  if (signature !== null) {
    headers.set(MOCK_SIGNATURE_HEADER, signature);
  }

  const method = args.method ?? 'POST';
  const init: RequestInit = { method, headers };

  if (method !== 'GET' && method !== 'HEAD') {
    init.body = args.rawBody;
  }

  return new Request('http://localhost/functions/v1/payment-webhook', init);
}

async function invoke(args: {
  rawBody: string;
  envOverrides?: Record<string, string | undefined>;
  timestamp?: string;
  signature?: string | null;
  signatureSecret?: string;
}) {
  const env = makeEnv(args.envOverrides);
  const calls: VerifiedMockPaymentWebhook[] = [];
  const handler = createPaymentWebhookHandler({
    env: env.env,
    now: () => FIXED_NOW_MS,
    processVerifiedWebhook: (event) => {
      calls.push(event);
      return Promise.resolve('00000000-0000-0000-0000-0000000088b0');
    },
  });
  const request = await makeRequest({
    rawBody: args.rawBody,
    timestamp: args.timestamp,
    signature: args.signature,
    secret: args.signatureSecret,
  });
  const response = await handler(request);
  const body = await response.json();

  return { response, body, calls, requestedEnv: env.requested };
}

Deno.test('valid mock signature is accepted', async () => {
  const { response, body, calls } = await invoke({ rawBody: paidPayload() });

  assertEquals(response.status, 200, 'valid signed mock webhook should be accepted');
  assertEquals(body.ok, true, 'response should be successful');
  assertEquals(calls.length, 1, 'database function should be called once');
  assertEquals(calls[0].event_type, 'mock.payment.paid', 'paid event should be normalized');
});

Deno.test('invalid mock signature is rejected before database call', async () => {
  const { response, body, calls } = await invoke({
    rawBody: paidPayload(),
    signature: `sha256=${'0'.repeat(64)}`,
  });

  assertEquals(response.status, 401, 'invalid signature should fail closed');
  assertEquals(body.code, 'invalid_signature', 'response should identify safe failure category');
  assertEquals(calls.length, 0, 'invalid signature must not call database function');
});

Deno.test('missing signature header is rejected before database call', async () => {
  const { response, body, calls } = await invoke({
    rawBody: paidPayload(),
    signature: null,
  });

  assertEquals(response.status, 401, 'missing signature should fail closed');
  assertEquals(body.code, 'missing_signature', 'response should identify missing signature');
  assertEquals(calls.length, 0, 'missing signature must not call database function');
});

Deno.test('stale timestamp is rejected before database call', async () => {
  const staleTimestamp = String(Number(FIXED_TIMESTAMP) - 301);
  const { response, body, calls } = await invoke({
    rawBody: paidPayload(),
    timestamp: staleTimestamp,
  });

  assertEquals(response.status, 401, 'stale timestamp should fail closed');
  assertEquals(body.code, 'stale_webhook_timestamp', 'response should identify stale webhook timestamp');
  assertEquals(calls.length, 0, 'stale timestamp must not call database function');
});

Deno.test('raw body bytes are used for verification and payload_hash', async () => {
  const rawBody = paidPayload('ticket-8b-raw-body');
  const expectedHash = await sha256PayloadHash(encoder.encode(rawBody));
  const { response, calls } = await invoke({ rawBody });

  assertEquals(response.status, 200, 'signature over exact raw body should be accepted');
  assertEquals(calls.length, 1, 'database function should be called once');
  assertEquals(calls[0].payload_hash, expectedHash, 'payload_hash must be computed from exact raw bytes');
});

Deno.test('parsed-then-reserialized JSON cannot bypass raw-body verification', async () => {
  const rawBody = paidPayload('ticket-8b-reserialize');
  const reserialized = JSON.stringify(JSON.parse(rawBody));
  const signatureForReserialized = await createMockWebhookSignature(
    MOCK_SECRET,
    FIXED_TIMESTAMP,
    encoder.encode(reserialized),
  );
  const { response, body, calls } = await invoke({
    rawBody,
    signature: signatureForReserialized,
  });

  assertEquals(response.status, 401, 'signature over reserialized JSON must not verify raw body');
  assertEquals(body.code, 'invalid_signature', 'raw-body mismatch should be an invalid signature');
  assertEquals(calls.length, 0, 'raw-body mismatch must not call database function');
});

Deno.test('valid paid webhook calls database function exactly once', async () => {
  const { response, calls } = await invoke({ rawBody: paidPayload('ticket-8b-paid-once') });

  assertEquals(response.status, 200, 'valid paid webhook should be accepted');
  assertEquals(calls.length, 1, 'valid paid webhook should call database once');
  assertEquals(calls[0].provider_event_id, 'evt_ticket_8b_paid', 'provider event ID should be normalized');
  assertEquals(calls[0].provider_reference, 'ticket-8b-paid-once', 'provider reference should be normalized');
});

Deno.test('valid failed webhook calls database function exactly once', async () => {
  const { response, calls } = await invoke({ rawBody: failedPayload() });

  assertEquals(response.status, 200, 'valid failed webhook should be accepted');
  assertEquals(calls.length, 1, 'valid failed webhook should call database once');
  assertEquals(calls[0].event_type, 'mock.payment.failed', 'failed event should be normalized');
  assertEquals(calls[0].provider_reference, 'ticket-8b-failed', 'failed provider reference should be normalized');
});

Deno.test('invalid signature with malformed JSON is rejected before parsing', async () => {
  const { response, body, calls } = await invoke({
    rawBody: '{not-valid-json',
    signature: `sha256=${'f'.repeat(64)}`,
  });

  assertEquals(response.status, 401, 'invalid signature should be checked before JSON parsing');
  assertEquals(body.code, 'invalid_signature', 'malformed JSON should not be parsed before signature verification');
  assertEquals(calls.length, 0, 'invalid signature with malformed JSON must not call database');
});

Deno.test('raw body and payload-provided secrets are not forwarded or stored', async () => {
  const rawBody = JSON.stringify({
    id: 'evt_ticket_8b_safe_metadata',
    type: 'mock.payment.paid',
    provider_reference: 'ticket-8b-safe-metadata',
    idempotency_key: 'idem_ticket_8b_safe_metadata',
    raw_body: 'do-not-forward-raw-body',
    webhook_secret: 'payload-secret-must-be-ignored',
    signature_header: 'signature-must-not-be-forwarded',
  });
  const { response, calls } = await invoke({ rawBody });

  assertEquals(response.status, 200, 'valid signature should still be accepted');
  assertEquals(calls.length, 1, 'database function should be called once');
  const forwarded = JSON.stringify(calls[0]) ?? '';
  assertNotIncludes(forwarded, 'do-not-forward-raw-body', 'raw body content must not be forwarded');
  assertNotIncludes(forwarded, 'payload-secret-must-be-ignored', 'payload-provided secret must not be forwarded');
  assertNotIncludes(forwarded, 'signature-must-not-be-forwarded', 'signature header must not be forwarded');
  assertNotIncludes(forwarded, 'raw_body', 'raw_body field name must not be forwarded');
  assertNotIncludes(forwarded, 'webhook_secret', 'webhook_secret field name must not be forwarded');
  assertNotIncludes(forwarded, 'signature_header', 'signature header field name must not be forwarded');
});

Deno.test('webhook secret is read only from server runtime config', async () => {
  const rawBody = JSON.stringify({
    id: 'evt_ticket_8b_runtime_secret',
    type: 'mock.payment.paid',
    provider_reference: 'ticket-8b-runtime-secret',
    idempotency_key: 'idem_ticket_8b_runtime_secret',
    data: {
      webhook_secret: 'payload-secret-must-not-be-used',
    },
  });
  const { response, calls, requestedEnv } = await invoke({ rawBody });

  assertEquals(response.status, 200, 'signature using runtime secret should be accepted');
  assertEquals(calls.length, 1, 'database function should be called once');
  assert(
    requestedEnv.includes('PAYMENT_WEBHOOK_SECRET_MOCK'),
    'handler should read mock webhook secret from runtime environment',
  );
  assertNotIncludes(JSON.stringify(calls[0]) ?? '', 'payload-secret-must-not-be-used', 'payload secret must not be used');
});

Deno.test('missing runtime webhook secret fails closed', async () => {
  const { response, body, calls } = await invoke({
    rawBody: paidPayload(),
    envOverrides: {
      PAYMENT_WEBHOOK_SECRET_MOCK: undefined,
      PAYMENT_WEBHOOK_SECRET: undefined,
    },
  });

  assertEquals(response.status, 500, 'missing runtime secret should fail closed');
  assertEquals(body.code, 'missing_mock_webhook_secret', 'response should identify missing server config');
  assertEquals(calls.length, 0, 'missing secret must not call database');
});

Deno.test('production plus mock provider mode fails closed', async () => {
  const { response, body, calls } = await invoke({
    rawBody: paidPayload(),
    envOverrides: {
      APP_ENV: 'production',
      PAYMENT_PROVIDER_MODE: 'mock',
    },
  });

  assertEquals(response.status, 503, 'production mock mode should fail closed');
  assertEquals(body.code, 'mock_provider_disabled_in_production', 'response should identify fail-closed config');
  assertEquals(calls.length, 0, 'production mock mode must not call database');
});

Deno.test('missing app environment fails closed', async () => {
  const { response, body, calls } = await invoke({
    rawBody: paidPayload(),
    envOverrides: {
      APP_ENV: undefined,
      LEKKADEALL_APP_ENV: undefined,
    },
  });

  assertEquals(response.status, 500, 'missing app environment should fail closed');
  assertEquals(body.code, 'missing_app_env', 'response should identify missing app environment');
  assertEquals(calls.length, 0, 'missing app environment must not call database');
});

Deno.test('unsupported method is rejected without database call', async () => {
  const env = makeEnv();
  const calls: VerifiedMockPaymentWebhook[] = [];
  const handler = createPaymentWebhookHandler({
    env: env.env,
    now: () => FIXED_NOW_MS,
    processVerifiedWebhook: (event) => {
      calls.push(event);
      return Promise.resolve(null);
    },
  });
  const request = await makeRequest({
    rawBody: paidPayload(),
    method: 'GET',
  });
  const response = await handler(request);
  const body = await response.json();

  assertEquals(response.status, 405, 'GET should be rejected');
  assertEquals(body.code, 'method_not_allowed', 'response should identify unsupported method');
  assertEquals(calls.length, 0, 'unsupported method must not call database');
});
