// Ticket 8B: mock/sandbox payment webhook route.
//
// This Edge Function verifies a deterministic mock webhook signature against
// the exact raw request body before it parses JSON or calls the Ticket 8A
// database-side processor. It is intentionally mock/sandbox only.

export const MOCK_SIGNATURE_HEADER = 'x-lekkadeall-mock-signature';
export const MOCK_TIMESTAMP_HEADER = 'x-lekkadeall-mock-timestamp';
export const DEFAULT_WEBHOOK_TOLERANCE_SECONDS = 300;

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export type MockPaymentWebhookEventType =
  | 'mock.checkout.created'
  | 'mock.payment.paid'
  | 'mock.payment.failed'
  | 'mock.payment.expired'
  | 'mock.payment.cancelled';

export interface VerifiedMockPaymentWebhook {
  provider_event_id: string;
  provider_reference: string;
  event_type: MockPaymentWebhookEventType;
  payload_hash: string;
  idempotency_key: string;
  metadata: Record<string, unknown>;
}

export type EnvReader = (name: string) => string | undefined;
export type VerifiedMockWebhookProcessor = (event: VerifiedMockPaymentWebhook) => Promise<unknown>;
export type FetchLike = typeof fetch;

export interface PaymentWebhookHandlerOptions {
  env?: EnvReader;
  now?: () => number;
  processVerifiedWebhook?: VerifiedMockWebhookProcessor;
  fetchImpl?: FetchLike;
}

interface MockWebhookPayload {
  id?: unknown;
  event_id?: unknown;
  type?: unknown;
  event_type?: unknown;
  provider_reference?: unknown;
  idempotency_key?: unknown;
  occurred_at?: unknown;
  data?: {
    provider_reference?: unknown;
    idempotency_key?: unknown;
  };
}

function defaultEnv(name: string): string | undefined {
  return Deno.env.get(name);
}

function getConfig(env: EnvReader) {
  return {
    appEnv: (env('APP_ENV') ?? env('LEKKADEALL_APP_ENV') ?? '').trim().toLowerCase(),
    providerMode: (env('PAYMENT_PROVIDER_MODE') ?? env('PAYMENT_PROVIDER') ?? 'mock').trim().toLowerCase(),
    webhookSecret: env('PAYMENT_WEBHOOK_SECRET_MOCK') ?? env('PAYMENT_WEBHOOK_SECRET'),
    toleranceSeconds: parseTolerance(env('PAYMENT_WEBHOOK_TOLERANCE_SECONDS')),
    supabaseUrl: env('SUPABASE_URL'),
    supabaseServiceRoleKey: env('SUPABASE_SERVICE_ROLE_KEY'),
  };
}

function parseTolerance(raw: string | undefined): number {
  if (raw === undefined || raw.trim() === '') {
    return DEFAULT_WEBHOOK_TOLERANCE_SECONDS;
  }

  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_WEBHOOK_TOLERANCE_SECONDS;
  }

  return Math.floor(parsed);
}

function isProductionEnvironment(appEnv: string): boolean {
  return appEnv === 'production' || appEnv === 'prod';
}

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}

function toHex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function toExactArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const exactBuffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(exactBuffer).set(bytes);
  return exactBuffer;
}

function concatBytes(...chunks: Uint8Array[]): Uint8Array {
  const totalLength = chunks.reduce((length, chunk) => length + chunk.length, 0);
  const output = new Uint8Array(totalLength);
  let offset = 0;

  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.length;
  }

  return output;
}

export async function sha256PayloadHash(rawBody: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', toExactArrayBuffer(rawBody));
  return `sha256:${toHex(digest)}`;
}

export async function createMockWebhookSignature(
  secret: string,
  timestamp: string,
  rawBody: Uint8Array,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    toExactArrayBuffer(encoder.encode(secret)),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signedPayload = concatBytes(encoder.encode(`${timestamp}.`), rawBody);
  const signature = await crypto.subtle.sign('HMAC', key, toExactArrayBuffer(signedPayload));

  return `sha256=${toHex(signature)}`;
}

function normalizeSignatureHeader(signatureHeader: string | null): string | null {
  if (signatureHeader === null) {
    return null;
  }

  const trimmed = signatureHeader.trim().toLowerCase();
  const normalized = trimmed.startsWith('sha256=') ? trimmed.slice('sha256='.length) : trimmed;

  if (!/^[a-f0-9]{64}$/.test(normalized)) {
    return null;
  }

  return normalized;
}

function timingSafeHexEqual(left: string, right: string): boolean {
  const maxLength = Math.max(left.length, right.length);
  let difference = left.length ^ right.length;

  for (let index = 0; index < maxLength; index += 1) {
    difference |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
  }

  return difference === 0;
}

async function verifyMockSignature(args: {
  secret: string;
  timestamp: string;
  signatureHeader: string;
  rawBody: Uint8Array;
}): Promise<boolean> {
  const expected = normalizeSignatureHeader(
    await createMockWebhookSignature(args.secret, args.timestamp, args.rawBody),
  );
  const received = normalizeSignatureHeader(args.signatureHeader);

  if (expected === null || received === null) {
    return false;
  }

  return timingSafeHexEqual(expected, received);
}

function parseTimestampSeconds(timestampHeader: string | null): number | null {
  if (timestampHeader === null || timestampHeader.trim() === '') {
    return null;
  }

  if (!/^-?\d+$/.test(timestampHeader.trim())) {
    return null;
  }

  const parsed = Number(timestampHeader);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    return null;
  }

  return parsed;
}

function isTimestampFresh(timestampSeconds: number, nowMs: number, toleranceSeconds: number): boolean {
  const nowSeconds = Math.floor(nowMs / 1000);
  return Math.abs(nowSeconds - timestampSeconds) <= toleranceSeconds;
}

function asNonEmptyString(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function isSupportedMockEventType(value: string): value is MockPaymentWebhookEventType {
  return [
    'mock.checkout.created',
    'mock.payment.paid',
    'mock.payment.failed',
    'mock.payment.expired',
    'mock.payment.cancelled',
  ].includes(value);
}

function parseVerifiedMockWebhook(rawBody: Uint8Array, payloadHash: string, nowMs: number): VerifiedMockPaymentWebhook {
  let parsed: MockWebhookPayload;

  try {
    parsed = JSON.parse(decoder.decode(rawBody)) as MockWebhookPayload;
  } catch {
    throw new Error('invalid_json');
  }

  const providerEventId = asNonEmptyString(parsed.id) ?? asNonEmptyString(parsed.event_id);
  const rawEventType = (asNonEmptyString(parsed.type) ?? asNonEmptyString(parsed.event_type))?.toLowerCase();
  const providerReference =
    asNonEmptyString(parsed.provider_reference) ?? asNonEmptyString(parsed.data?.provider_reference);
  const idempotencyKey =
    asNonEmptyString(parsed.idempotency_key) ??
    asNonEmptyString(parsed.data?.idempotency_key) ??
    (providerEventId ? `mock-webhook:${providerEventId}` : null);

  if (providerEventId === null) {
    throw new Error('missing_provider_event_id');
  }

  if (rawEventType === undefined || !isSupportedMockEventType(rawEventType)) {
    throw new Error('unsupported_event_type');
  }

  if (providerReference === null) {
    throw new Error('missing_provider_reference');
  }

  if (idempotencyKey === null) {
    throw new Error('missing_idempotency_key');
  }

  const occurredAt = asNonEmptyString(parsed.occurred_at);

  return {
    provider_event_id: providerEventId,
    provider_reference: providerReference,
    event_type: rawEventType,
    payload_hash: payloadHash,
    idempotency_key: idempotencyKey,
    metadata: {
      route: 'payment-webhook',
      provider_name: 'mock',
      provider_event_id: providerEventId,
      provider_event_type: rawEventType,
      occurred_at: occurredAt,
      received_at: new Date(nowMs).toISOString(),
      mock_adapter: true,
      sandbox_only: true,
      real_money_moved: false,
    },
  };
}

export async function processVerifiedMockWebhookWithSupabase(
  event: VerifiedMockPaymentWebhook,
  env: EnvReader = defaultEnv,
  fetchImpl: FetchLike = fetch,
): Promise<unknown> {
  const config = getConfig(env);
  const supabaseUrl = config.supabaseUrl?.replace(/\/+$/, '');
  const serviceRoleKey = config.supabaseServiceRoleKey;

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error('missing_supabase_server_config');
  }

  const response = await fetchImpl(`${supabaseUrl}/rest/v1/rpc/admin_process_verified_mock_payment_webhook`, {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      authorization: `Bearer ${serviceRoleKey}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(event),
  });

  if (!response.ok) {
    throw new Error('webhook_database_processing_failed');
  }

  const text = await response.text();
  return text === '' ? null : JSON.parse(text);
}

export function createPaymentWebhookHandler(options: PaymentWebhookHandlerOptions = {}) {
  const env = options.env ?? defaultEnv;
  const now = options.now ?? (() => Date.now());
  const processVerifiedWebhook =
    options.processVerifiedWebhook ??
      ((event: VerifiedMockPaymentWebhook) =>
        processVerifiedMockWebhookWithSupabase(event, env, options.fetchImpl ?? fetch));

  return async function paymentWebhookHandler(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return jsonResponse(405, { ok: false, code: 'method_not_allowed' });
    }

    const config = getConfig(env);

    if (config.appEnv === '') {
      return jsonResponse(500, { ok: false, code: 'missing_app_env' });
    }

    if (config.providerMode !== 'mock') {
      return jsonResponse(404, { ok: false, code: 'mock_webhook_not_enabled' });
    }

    if (isProductionEnvironment(config.appEnv) && config.providerMode === 'mock') {
      return jsonResponse(503, { ok: false, code: 'mock_provider_disabled_in_production' });
    }

    if (!config.webhookSecret || config.webhookSecret.trim() === '') {
      return jsonResponse(500, { ok: false, code: 'missing_mock_webhook_secret' });
    }

    const timestampHeader = request.headers.get(MOCK_TIMESTAMP_HEADER);
    const timestampSeconds = parseTimestampSeconds(timestampHeader);
    const timestampForSignature = timestampHeader?.trim() ?? '';

    if (timestampSeconds === null) {
      return jsonResponse(400, { ok: false, code: 'missing_or_invalid_timestamp' });
    }

    if (!isTimestampFresh(timestampSeconds, now(), config.toleranceSeconds)) {
      return jsonResponse(401, { ok: false, code: 'stale_webhook_timestamp' });
    }

    const signatureHeader = request.headers.get(MOCK_SIGNATURE_HEADER);
    if (signatureHeader === null || signatureHeader.trim() === '') {
      return jsonResponse(401, { ok: false, code: 'missing_signature' });
    }

    const rawBody = new Uint8Array(await request.arrayBuffer());
    const signatureValid = await verifyMockSignature({
      secret: config.webhookSecret,
      timestamp: timestampForSignature,
      signatureHeader,
      rawBody,
    });

    if (!signatureValid) {
      return jsonResponse(401, { ok: false, code: 'invalid_signature' });
    }

    const payloadHash = await sha256PayloadHash(rawBody);
    let verifiedEvent: VerifiedMockPaymentWebhook;

    try {
      verifiedEvent = parseVerifiedMockWebhook(rawBody, payloadHash, now());
    } catch (error) {
      const code = error instanceof Error ? error.message : 'invalid_payload';
      return jsonResponse(400, { ok: false, code });
    }

    try {
      const paymentEventId = await processVerifiedWebhook(verifiedEvent);
      return jsonResponse(200, {
        ok: true,
        provider: 'mock',
        provider_event_id: verifiedEvent.provider_event_id,
        event_type: verifiedEvent.event_type,
        payload_hash: verifiedEvent.payload_hash,
        payment_event_id: paymentEventId,
      });
    } catch {
      return jsonResponse(500, { ok: false, code: 'webhook_processing_failed' });
    }
  };
}

if (import.meta.main) {
  Deno.serve(createPaymentWebhookHandler());
}
