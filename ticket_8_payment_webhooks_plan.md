# Ticket 8 Planning Document — Signed and Idempotent Payment Webhook Handling

## Goal

Plan secure payment webhook handling for LEKKADEALL without implementing live provider routes yet.

Ticket 8 should turn payment-provider callbacks into trusted, idempotent, auditable state transitions while preserving the protections from Tickets 1, 2, 5, 6, and 7A-7E.

## Current implementation status

Ticket 8A and Ticket 8B have now implemented the mock/sandbox webhook foundation:

- `outputs/marketplace-production-foundation/supabase/migrations/012_mock_payment_webhook_processing.sql`
- `admin_process_verified_mock_payment_webhook(...)`
- `outputs/marketplace-production-foundation/supabase/tests/database/payment_webhooks.test.sql`
- `outputs/marketplace-production-foundation/supabase/functions/payment-webhook/index.ts`
- `outputs/marketplace-production-foundation/supabase/functions/payment-webhook/index.test.ts`

This implements mock/sandbox raw-body signature verification and database-side mock processing only. It does not implement live provider adapters, real webhook secrets, real provider webhooks, real card/EFT processing, real refund/payout webhooks, reconciliation, or UI. Those remain future Ticket 8 work.

## Current starting point

Already implemented:

- `vendor_events` is frontend-inaccessible and idempotent on `(provider_name, provider_event_id)`.
- `payment_events` is append-only and frontend-inaccessible.
- `audit_events` is append-only and frontend-inaccessible.
- `payments.status` and `payments.release_status` are constrained.
- Cash/off-platform payments are disabled for MVP.
- Mock/sandbox checkout and mock paid/failed outcome recording exist through trusted database functions.
- Mock mode fails closed in production through `validate_payment_provider_mode(...)`.
- Mock/sandbox database webhook processing exists for already signature-verified events through `admin_process_verified_mock_payment_webhook(...)`.
- The mock/sandbox `payment-webhook` route verifies deterministic mock HMAC signatures against exact raw request body bytes before JSON parsing.
- `payment_webhooks.test.sql` covers mock paid/failed processing, duplicate provider event IDs, different-payload-hash duplicates, out-of-order events, paid-after-refunded manual review, raw webhook metadata rejection, append-only ledgers, and Ticket 1/2/5/6/7A/7B/7C/7D/7E smoke protections.
- `index.test.ts` covers mock route valid/invalid signatures, missing signatures, stale timestamps, raw-body mismatch, exact payload hashing, safe metadata forwarding, runtime-only mock secret config, and production + mock fail-closed behavior.

Still missing:

- live provider webhook HTTP endpoints/adapters
- live provider-specific raw body signature verification
- provider-specific signature adapters
- live provider replay protection rules
- live provider event parsing
- webhook reconciliation against provider lookup APIs
- safe production secret loading
- application/server tests for live provider webhook adapters

## 1. Signed webhook verification

Every payment webhook must be signature-verified before any database mutation.

Recommended rule:

- The server route receives provider name, headers, raw body, and request timestamp.
- Provider-specific adapter verifies the signature with a server-only webhook secret.
- If signature verification fails, the handler must return a safe non-success response and must not mutate `payments`, `vendor_events`, `payment_events`, `refund_requests`, `refund_events`, or `audit_events`.
- Signature verification code must be provider-specific behind a common interface, because each South African/payment vendor may sign differently.

The verification result should produce a normalized internal event only after signature success.

## 2. Raw body verification requirements

Signature verification must use the exact raw request body bytes received by the server.

Rules:

- Do not verify signatures against parsed JSON.
- Do not reserialize JSON before verification.
- Disable automatic body parsing for webhook routes, or use a runtime that exposes raw bytes.
- Preserve the provider timestamp/signature headers exactly.
- Enforce a timestamp tolerance window where the provider supports it, for example five minutes, to reduce replay risk.
- Log only safe metadata; never log raw payloads that may contain personal data or provider-sensitive details.

## 3. `vendor_events` idempotency

`vendor_events` is the first durable idempotency boundary after signature verification.

Recommended flow:

1. Verify signature using raw body.
2. Parse minimal provider event envelope.
3. Compute `payload_hash` from the raw body.
4. Insert `vendor_events(provider_name, provider_event_id, event_type, related_reference, payload_hash)`.
5. If `(provider_name, provider_event_id)` already exists, treat it as duplicate and return success without changing payment state again.

The raw body should not be stored in the database. Store only:

- provider name
- provider event ID
- event type
- related provider/payment reference
- payload hash
- received/processed timestamps
- safe processing metadata

## 4. Duplicate webhook handling

Duplicate provider events must be safe and idempotent.

Rules:

- A duplicate webhook with the same `(provider_name, provider_event_id)` must not create duplicate `payment_events`.
- A duplicate webhook must not move payment state a second time.
- If the duplicate has a different payload hash for the same provider event ID, the handler should flag it for admin/security review and avoid state mutation.
- The HTTP response for a true duplicate should usually be a success response so the provider stops retrying.

Recommended ledger event:

- True duplicate: no new payment state event, or optionally a safe `mock_payment_duplicate_ignored` / future `webhook_duplicate_ignored` event if the event type set is extended.
- Suspicious duplicate hash mismatch: audit/security event, no payment mutation.

## 5. Out-of-order event handling

Provider webhooks may arrive late or out of order.

Rules:

- Failed-after-paid must not regress `payments.status` from `paid` to `failed`.
- Checkout-created-after-paid must not downgrade `paid`.
- Paid-after-refunded must be rejected or routed to manual review.
- Refunded events must not exceed remaining refundable amount.
- Release/payout events must not run before payment is paid and booking/release blockers are cleared.

Recommended approach:

- Add a state-transition matrix for webhook-driven payment statuses.
- Lock the payment row before applying any transition.
- Compare current status, incoming event type, provider status, and event timestamp.
- If event is stale/out-of-order, write a safe audit/payment event only if useful, but do not regress state.

## 6. `payment_events` and `audit_events` writing

Every accepted webhook that changes trusted payment state must write:

- one `vendor_events` row or reuse the existing duplicate row
- one `payment_events` row for a real state transition
- one `audit_events` row describing the trusted webhook processing outcome

Payment events must include:

- `payment_id`
- `booking_id`
- normalized event type
- amount/currency
- provider name
- provider event ID
- idempotency key
- source = `webhook`
- safe metadata only

Audit events must include:

- actor as `null` or a system/server actor reference
- action such as `payment.webhook_processed`
- object type `payment`
- payment ID as object ID
- reason describing the provider event and transition
- safe metadata with vendor event/payment event IDs

## 7. Failed signature handling

Failed signatures must fail closed.

Rules:

- No payment mutation.
- No `payment_events` mutation.
- No refund mutation.
- No payout/release mutation.
- No `vendor_events` row unless the product deliberately creates a separate security-log table for rejected webhook attempts.
- Return an appropriate HTTP error, usually `400` or `401`, without leaking secrets or verification details.
- Record operational logs through server logging/monitoring, not public database tables, unless a later security-event table is designed.

Do not store raw failed webhook bodies in the application database.

## 8. No committed webhook secrets

Webhook secrets must be server-only runtime configuration.

Rules:

- No webhook secret in Git.
- No webhook secret in `.env.example` except placeholder names.
- No webhook secret in Supabase migrations, pgTAP files, frontend code, or docs.
- Production startup must fail if provider mode is live/sandbox but required webhook secrets are missing.
- Frontend bundles must never include webhook secrets.

Recommended environment names:

- `PAYMENT_PROVIDER_MODE`
- `PAYMENT_WEBHOOK_SECRET_<PROVIDER>`
- `PAYMENT_WEBHOOK_TOLERANCE_SECONDS`

The actual provider secret names can be finalized when vendors are chosen.

## 9. Mock/sandbox webhook tests

Ticket 8A started with database-side mock/sandbox webhook processing before live provider support.

The current pgTAP tests prove:

- trusted mock/sandbox webhook processing accepts already verified events only through an admin/server function
- duplicate mock provider event ID is idempotent
- duplicate provider event with different payload hash does not mutate state
- paid event updates payment once
- failed-after-paid does not regress status
- checkout-created-after-paid does not downgrade status
- paid-after-refunded is rejected or manual-review only
- accepted webhook writes `vendor_events`, `payment_events`, and `audit_events`
- raw webhook body/signature/secret metadata is rejected and not stored
- normal customers/providers cannot call the webhook-processing function

Still needed outside pgTAP/application-server tests:

- valid mock signature is accepted by a future HTTP route
- invalid mock signature is rejected before database mutation
- raw body hash is computed from exact raw request bytes
- parsed-but-reserialized JSON does not bypass verification
- failed signature writes no payment state

## 10. Future live provider integration requirements

Before enabling a live payment provider:

- Vendor contract must be reviewed.
- Hosted checkout creation must use provider sandbox first.
- Webhook signature docs must be implemented exactly.
- Reconciliation lookup API must be available for uncertain events.
- Idempotency rules must match provider event semantics.
- Currency must remain `ZAR` for the MVP unless the product explicitly expands.
- Provider references must be safe to store.
- No card, CVV, bank-login credentials, or raw payment credentials may enter LEKKADEALL tables.
- Production config must fail closed if provider mode is `mock`.
- Production config must fail closed if webhook secret is absent.
- Operational alerting must exist for failed verification spikes, hash mismatches, and unknown event types.

## 11. pgTAP/database tests required

Implemented Ticket 8A database test file:

- `outputs/marketplace-production-foundation/supabase/tests/database/payment_webhooks.test.sql`

Implemented database assertions:

- `vendor_events` remains frontend-inaccessible.
- `vendor_events` remains idempotent on `(provider_name, provider_event_id)`.
- `payment_events` remains append-only.
- `audit_events` remains append-only.
- trusted webhook function can record an already-verified mock/sandbox paid event.
- trusted webhook function writes exactly one `vendor_events` row.
- trusted webhook function writes exactly one `payment_events` row.
- trusted webhook function writes exactly one `audit_events` row.
- duplicate provider event ID does not duplicate `payment_events`.
- duplicate provider event ID with different payload hash is rejected or flagged without payment mutation.
- failed-after-paid does not regress payment status.
- checkout-created-after-paid does not downgrade payment status.
- paid-after-refunded is rejected or does not mutate payment status.
- invalid provider event type is rejected or held for review.
- normal customer/provider cannot call webhook-processing functions directly.
- frontend users cannot mark payments as paid through direct table update.
- Ticket 1 role protections remain intact.
- Ticket 2 RLS protections remain intact.
- Ticket 5 address privacy remains intact.
- Ticket 6 marketplace state machine remains intact.
- Ticket 7A payment ledger protections remain intact.
- Ticket 7B refund protections remain intact.
- Ticket 7C cash-disabled protections remain intact.
- Ticket 7D payout release controls remain intact.
- Ticket 7E mock checkout protections remain intact.

HTTP/raw-body signature tests still require application/server tests in addition to pgTAP because pgTAP cannot fully prove framework raw-body handling.

## 12. Definition of done

Ticket 8 is done only when:

- payment webhook route verifies signatures using raw body bytes
- invalid signatures fail closed with no payment mutation
- webhook secrets are runtime-only and never committed
- provider event IDs are idempotent
- duplicate events do not duplicate payment/audit state
- out-of-order events do not regress payment status
- accepted webhook transitions lock the payment row transactionally
- accepted webhook transitions write `vendor_events`, `payment_events`, and `audit_events`
- raw provider payloads and payment credentials are not stored
- mock/sandbox webhook tests pass
- database pgTAP tests pass
- all previous Ticket 1/2/5/6/7A/7B/7C/7D/7E CI tests remain green
- live provider mode remains disabled until real credentials, signed webhook verification, and reconciliation are proven in sandbox
