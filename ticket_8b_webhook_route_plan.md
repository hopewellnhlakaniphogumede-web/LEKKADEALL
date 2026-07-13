# Ticket 8B Planning Document — Application/Edge Function Webhook Route with Raw-Body Signature Verification

## Goal

Plan the application/server route that receives payment-provider webhooks, verifies signatures against the exact raw HTTP body, normalizes safe mock/sandbox events, and only then calls the Ticket 8A trusted database function.

Ticket 8B must bridge the gap between:

- Ticket 8A database-side mock/sandbox webhook processing, and
- a future production payment provider webhook integration.

## Planning-only status

This document is planning-only.

Do not implement an Edge Function, server route, provider adapter, migration, production secret, UI, or live payment-provider integration in Ticket 8B until an explicit implementation ticket is requested.

## Current starting point

Already implemented by Ticket 8A:

- `admin_process_verified_mock_payment_webhook(...)`
- mock/sandbox database-side webhook processing
- safe payment-state transitions for already verified mock events
- `vendor_events` idempotency boundary
- `payment_events` and `audit_events` writing
- duplicate provider-event handling
- different-payload-hash duplicate audit flagging
- out-of-order protection
- no raw webhook body storage
- pgTAP coverage in `payment_webhooks.test.sql`

Still missing before production:

- real HTTP webhook route
- raw request body capture
- provider-specific signature verification
- replay/timestamp checks
- provider event normalization
- safe route-level error handling
- application/server tests proving raw-body verification
- runtime-only secret loading
- live provider sandbox integration
- reconciliation against provider lookup APIs

## Non-goals for Ticket 8B

Ticket 8B should not:

- add live provider credentials
- process real cards, EFTs, bank logins, or instant EFT credentials
- store raw webhook request bodies
- store webhook secrets in Git
- expose any webhook secret to the frontend
- grant frontend users access to `vendor_events`, `payment_events`, or `audit_events`
- weaken Ticket 1/2/5/6/7A/7B/7C/7D/7E/8A protections
- implement payout webhooks
- implement refund webhooks unless explicitly included in a later ticket
- build UI

## Proposed route shape

Recommended route name:

- Supabase Edge Function: `payment-webhook`
- Future app route alternative: `/api/webhooks/payment/:provider`

Recommended request inputs:

- provider identifier from route path or header
- raw request body bytes
- provider signature header(s)
- provider timestamp header where supported
- request ID / trace ID from infrastructure if available

The route must never trust a provider name supplied only inside the parsed JSON body before signature verification.

## Raw-body verification requirements

The route must verify signatures against the exact bytes received over HTTP.

Rules:

- Read the request body once as raw bytes.
- Do not parse JSON before signature verification.
- Do not verify signatures against reserialized JSON.
- Do not trim, normalize, prettify, or change line endings before verification.
- Compute `payload_hash` from the same raw bytes used for verification.
- Only parse JSON after signature verification succeeds.
- Do not log raw request bodies.
- Do not store raw request bodies in the database.

For Supabase Edge Functions, the implementation should use the runtime’s raw `Request` body APIs directly, for example raw bytes from `request.arrayBuffer()`, then decode/parse only after verification.

## Provider adapter contract

Create a provider-neutral interface in the application/server layer.

Suggested conceptual contract:

```ts
type VerifiedWebhookEnvelope = {
  providerName: string
  providerEventId: string
  providerReference: string
  eventType: string
  payloadHash: string
  occurredAt?: string
  safeMetadata: Record<string, unknown>
}

type PaymentWebhookVerifier = {
  providerName: string
  verifyRawBody(args: {
    rawBody: Uint8Array
    headers: Headers
    secret: string
    toleranceSeconds: number
  }): Promise<boolean>
  parseVerifiedEvent(args: {
    rawBody: Uint8Array
    headers: Headers
    payloadHash: string
  }): Promise<VerifiedWebhookEnvelope>
}
```

The exact TypeScript shape can change during implementation, but the separation must remain:

1. verify raw bytes first;
2. parse only after verification succeeds;
3. normalize to a safe internal envelope;
4. call the database function.

## Mock/sandbox adapter behaviour

For mock/sandbox mode:

- Use a deterministic mock signing scheme only in local/CI/sandbox.
- Production must fail closed if provider mode is `mock`.
- Mock verification must still use raw bytes, not parsed JSON.
- The mock adapter should support the same event types Ticket 8A supports:
  - `mock.checkout.created`
  - `mock.payment.paid`
  - `mock.payment.failed`
  - `mock.payment.expired`
  - `mock.payment.cancelled`

Mock mode must not claim that real money moved.

## Signature verification flow

Recommended flow:

1. Receive request.
2. Identify configured provider from the route or trusted config.
3. Load provider webhook secret from server-only runtime environment.
4. Read raw body bytes.
5. Compute `payload_hash`, preferably `sha256:<hex>`.
6. Verify provider signature using raw bytes and provider timestamp headers.
7. If verification fails:
   - return `400` or `401`;
   - do not call the database processing function;
   - do not write `vendor_events`;
   - do not write `payment_events`;
   - do not write `audit_events`;
   - log only safe operational metadata.
8. Parse the verified body.
9. Normalize to a safe internal event envelope.
10. Call `admin_process_verified_mock_payment_webhook(...)` for mock/sandbox payment events.
11. Return a provider-appropriate success response for accepted and idempotent duplicate events.

## Replay protection

Where the provider supplies timestamps:

- verify timestamp is present;
- reject events outside the configured tolerance window;
- default tolerance should be conservative, for example 300 seconds;
- never rely only on timestamp tolerance; still use `vendor_events` idempotency.

For providers without timestamp headers:

- rely on signature verification plus provider event ID idempotency;
- consider a provider-specific replay risk note before production enablement.

## Database call requirements

The route may call the trusted database function only after signature verification succeeds.

For Ticket 8B mock/sandbox processing, call:

```sql
public.admin_process_verified_mock_payment_webhook(
  provider_event_id,
  provider_reference,
  event_type,
  payload_hash,
  idempotency_key,
  metadata
)
```

Rules:

- Use server-side Supabase credentials only in the route/Edge Function.
- Never expose service-role credentials to the frontend.
- Pass safe metadata only.
- Do not pass raw body.
- Do not pass signature headers.
- Do not pass webhook secrets.
- Treat duplicate successful calls as idempotent success.

## HTTP response policy

Recommended response behaviour:

- Valid processed event: `200 OK`
- Valid duplicate event: `200 OK`
- Valid but out-of-order/manual-review event: `200 OK` if recorded safely and no provider retry is useful
- Invalid signature: `400` or `401`
- Missing required headers: `400`
- Unknown provider: `404` or `400`
- Unsupported event type: provider-specific; usually `200 OK` after safe ignore only if intentionally logged/handled, otherwise `400`
- Internal unexpected error: `500`, with no secret/error-detail leakage

Do not return stack traces, SQL errors, signing details, or secret names to the provider.

## Secrets and environment variables

No real secrets should be committed.

Recommended placeholder names only:

- `PAYMENT_PROVIDER_MODE`
- `PAYMENT_WEBHOOK_SECRET_MOCK`
- `PAYMENT_WEBHOOK_SECRET_<PROVIDER>`
- `PAYMENT_WEBHOOK_TOLERANCE_SECONDS`
- `SUPABASE_URL`
- server-only Supabase service credential reference, if the final platform requires it

Production fail-closed rules:

- production must reject `PAYMENT_PROVIDER_MODE=mock`;
- live/sandbox provider mode must require the relevant webhook secret;
- missing tolerance config should fall back to a safe default, not disable timestamp checks;
- frontend builds must not contain webhook secrets.

## Logging and monitoring

Log safe operational metadata only:

- provider name
- provider event ID
- payload hash
- normalized event type
- database function result ID where safe
- request trace ID
- outcome category: processed, duplicate, signature_failed, replay_rejected, unsupported, internal_error

Never log:

- raw webhook body
- full customer personal data
- card/bank data
- webhook secret
- signature value
- service role key

Future production monitoring should alert on:

- signature failure spikes
- payload hash mismatch events
- unknown provider event types
- repeated internal errors
- webhook processing latency or retries
- reconciliation mismatches

## Required tests

Ticket 8B should add application/server tests in addition to existing pgTAP tests.

Required tests:

- valid mock webhook signature is accepted
- invalid mock webhook signature is rejected
- missing signature header is rejected
- stale timestamp is rejected
- raw body bytes are used for verification
- parsed-then-reserialized JSON cannot bypass verification
- payload hash is computed from exact raw body bytes
- valid paid webhook calls the database function exactly once
- valid failed webhook calls the database function exactly once
- duplicate provider event returns success without duplicate database mutation
- invalid signature does not call `admin_process_verified_mock_payment_webhook(...)`
- raw request body is not stored or logged
- webhook secret is read only from server runtime config
- production + mock provider mode fails closed
- frontend bundle does not include webhook secret names/values beyond harmless placeholders
- existing pgTAP file `payment_webhooks.test.sql` remains green

## Manual verification checklist

Before Ticket 8B can be considered implemented:

- Confirm the route reads raw bytes before parsing JSON.
- Confirm provider signature verification uses exact raw bytes.
- Confirm failed signatures do not mutate the database.
- Confirm successful mock events call the Ticket 8A database function.
- Confirm route does not store raw body.
- Confirm route does not log raw body or secrets.
- Confirm service credentials are server-only.
- Confirm CI runs both application webhook tests and database pgTAP tests.

## Definition of done

Ticket 8B is done only when:

- a mock/sandbox webhook route exists in the server/Edge Function layer;
- raw-body signature verification is implemented and tested;
- invalid signatures fail closed before any database mutation;
- replay/timestamp checks are implemented where supported;
- verified mock/sandbox events call `admin_process_verified_mock_payment_webhook(...)`;
- duplicate and out-of-order events remain safe through Ticket 8A database idempotency;
- no raw webhook bodies are stored;
- no production secrets are committed;
- no frontend code can access webhook secrets or service credentials;
- application/server webhook tests pass;
- `payment_webhooks.test.sql` remains green;
- all previous Supabase database tests remain green.

## Explicit remaining future work after Ticket 8B

Even after Ticket 8B, the platform will still need later tickets for:

- live provider-specific webhook adapters;
- provider sandbox certification;
- real hosted checkout integration;
- real refund webhook processing;
- real payout webhook processing;
- reconciliation against provider lookup APIs;
- production monitoring and incident runbooks;
- vendor-specific contract/compliance review.
