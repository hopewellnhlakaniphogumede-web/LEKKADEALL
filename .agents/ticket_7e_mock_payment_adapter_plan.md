# Ticket 7E Planning Document — Mock payment adapter and hosted checkout contract

## Goal

Plan the hosted checkout contract and mock payment adapter for LEKKADEALL without implementing live payment-provider integration yet.

Ticket 7E should create a safe path from booking payment intent to hosted checkout state and deterministic sandbox outcomes while preserving the existing payment ledger, refund ledger, cash-disabled policy, and payout-release controls.

## Implementation status

Implemented locally on 12 July 2026; awaiting local/CI pgTAP verification.

Implementation files:

- `outputs/marketplace-production-foundation/supabase/migrations/011_mock_payment_checkout.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/mock_payment_checkout.test.sql`

Ticket 7E now creates the database-side mock/sandbox checkout contract and deterministic mock paid/failed outcome recorder. It still does not create app routes, live payment adapters, real signed webhook handlers, provider credentials, or UI.

## Current starting point

Already implemented:

- Ticket 6 creates pending payment rows when a customer accepts a bid.
- Ticket 7A constrains `payments.status` and adds append-only `payment_events`.
- Ticket 7B adds refund request and refund event foundations.
- Ticket 7C disables cash/off-platform cash for MVP.
- Ticket 7D adds internal/manual/sandbox payout release controls.
- `src/integrations/contracts.ts` already contains a vendor-neutral `PaymentGateway` interface.

Still missing:

- signed/idempotent webhook processing
- real provider reconciliation
- UI that opens hosted checkout

## 1. Hosted checkout abstraction

Ticket 7E should define the server-side hosted checkout boundary before integrating any real provider.

Recommended operation:

- `create_checkout_session(payment_id, idempotency_key, return_url, cancel_url)`

It should:

- load the existing `payments` row
- verify the caller is the booking customer or trusted server/admin context
- verify the booking belongs to that customer
- verify `payments.status` is `pending` or already `checkout_created`
- verify `payment_method` is an allowed online/sandbox method
- never accept or store card numbers, CVV, bank-login credentials, or raw payment credentials
- create or reuse a provider checkout reference idempotently
- set `payments.status = 'checkout_created'`
- store only safe provider references and checkout metadata
- write `payment_events`
- write `audit_events`

Suggested internal result shape:

- `payment_id`
- `booking_id`
- `provider_name`
- `provider_reference`
- `checkout_url`
- `payment_status`
- `amount_minor`
- `currency`
- `expires_at`
- `idempotency_key`

## 2. Mock payment adapter

The mock adapter should be deterministic and local/CI friendly.

It should support:

- checkout creation
- paid outcome
- failed outcome
- expired/cancelled outcome if needed
- duplicate event/idempotency simulation
- out-of-order event simulation

Mock references should be obviously non-production, for example:

- provider name: `mock`
- checkout URL host/path: local or test-only
- provider reference prefix: `mock_checkout_`
- provider event prefix: `mock_event_`

Mock adapter output must never be presented as a real payment-provider confirmation.

## 3. Sandbox-only behaviour

Mock payment adapter behaviour must be sandbox-only.

Rules:

- Mock mode is allowed in local development, CI, and explicit sandbox deployments only.
- Mock mode must be visibly marked in metadata and logs.
- Mock paid/failed outcomes are internal test outcomes only.
- Mock mode must not imply that real money moved.
- Mock mode must not trigger real payout release.
- Mock mode may drive internal state transitions for CI and pilot testing only when clearly labelled.

Recommended metadata for mock events:

```json
{
  "mock_adapter": true,
  "sandbox_only": true,
  "real_money_moved": false
}
```

## 4. Production fail-closed rule if provider mode is mock

Production startup or server action execution must fail closed if:

- environment is production and payment provider mode is `mock`
- required real-provider secrets are missing
- webhook signing secret is missing for a non-mock provider
- provider mode is unknown
- provider configuration mixes mock and live settings

Recommended rule:

- `PAYMENT_PROVIDER_MODE=mock` is allowed only when `APP_ENV` / deployment environment is not production.

Failure should be loud and blocking. Do not silently fall back to mock in production.

## 5. No card/bank credentials stored

LEKKADEALL must never store:

- card number
- CVV
- bank-login username/password
- raw bank account login credentials
- raw payment-provider credential payloads
- full payment-provider webhook payloads containing sensitive data

Allowed stored data:

- safe provider references
- status values
- amount/currency
- checkout URL if safe and temporary
- timestamps
- idempotency keys
- raw payload hash
- redacted/safe metadata

Customers should enter payment credentials only on the hosted provider page or provider-controlled secure component, not into LEKKADEALL database fields.

## 6. How `checkout_created` connects to `payments.status`

Checkout creation should transition:

- from `pending`
- to `checkout_created`

Allowed idempotent behaviour:

- repeated checkout creation with the same idempotency key returns the existing checkout event/reference
- repeated checkout creation for an already `checkout_created` payment returns the existing safe checkout summary if not expired

Not allowed:

- checkout creation for `paid`, `refunded`, `failed`, `cancelled`, or `expired` payments
- checkout creation for cash/off-platform methods
- customer/provider direct table updates to `payments.status`

The transition must happen through trusted server logic only and must write:

- one `payment_events` row
- one `audit_events` row

## 7. How mock paid/failed outcomes are recorded

Mock outcomes should be recorded through trusted server/admin/sandbox-only functions, not direct frontend updates.

Mock paid outcome should:

- verify payment is `checkout_created` or pending in a specifically allowed sandbox path
- set `payments.status = 'paid'`
- set `paid_at`
- set `funded_at` if appropriate
- set `release_status = 'pending'` unless release is paused
- write `payment_events`
- write `audit_events`
- include metadata that real money did not move

Mock failed outcome should:

- verify payment is `pending` or `checkout_created`
- set `payments.status = 'failed'`
- set `release_status = 'cancelled'`
- write `payment_events`
- write `audit_events`
- include metadata that real money did not move

Mock outcomes must be idempotent by provider event ID or idempotency key.

## 8. How `payment_events`, `vendor_events`, and `audit_events` are written

Checkout creation and mock outcomes should write:

- `payment_events` for internal payment-state history
- `audit_events` for privileged/trusted action history
- `vendor_events` when simulating webhook-like provider events or when processing real provider webhooks in a later ticket

`payment_events` should capture:

- payment ID
- booking ID
- event type
- amount/currency
- provider name
- provider event/reference IDs
- idempotency key
- actor/source
- safe metadata

`vendor_events` should capture:

- provider name
- provider event ID
- event type
- related provider reference
- payload hash
- received/processed timestamps

`audit_events` should capture:

- actor ID where available
- action
- object type and ID
- reason
- safe metadata

All three event streams must remain append-only or server-controlled according to existing policies.

## 9. Idempotency requirements

Required idempotency keys:

- checkout creation idempotency key
- mock paid outcome idempotency key or provider event ID
- mock failed outcome idempotency key or provider event ID
- vendor event provider event ID

Rules:

- duplicate checkout creation must not create duplicate checkout events
- duplicate mock paid/failed outcome must not duplicate payment events
- duplicate vendor event ID must not process state twice
- idempotency should be scoped by provider name where appropriate
- idempotency result should return the existing event/reference safely

Out-of-order events must not regress state. For example:

- failed after paid should be ignored or rejected
- paid after refunded should be rejected
- checkout_created after paid should not downgrade payment

## 10. Required pgTAP tests

Ticket 7E implementation tests should prove:

- customer can create hosted checkout for own pending payment
- customer cannot create checkout for another customer's payment
- provider cannot create checkout for customer payment unless explicitly allowed by policy
- checkout creation moves payment status to `checkout_created`
- checkout creation writes exactly one `payment_events` row
- checkout creation writes an `audit_events` row
- duplicate checkout idempotency key does not duplicate events
- checkout cannot be created for paid payment
- checkout cannot be created for refunded payment
- checkout cannot be created for failed/cancelled/expired payment
- checkout cannot be created for cash/off-platform method
- normal user cannot directly set `payments.status = 'checkout_created'`
- mock paid outcome sets payment status to `paid`
- mock paid outcome sets `paid_at`
- mock paid outcome writes payment event and audit event
- mock failed outcome sets payment status to `failed`
- mock failed outcome writes payment event and audit event
- duplicate mock provider event does not duplicate payment events
- out-of-order failed-after-paid is rejected or ignored safely
- mock mode cannot run when production environment flag is true
- no test creates card/CVV/bank credential columns or data
- `payment_events` remain append-only
- `vendor_events` remain frontend-inaccessible
- `audit_events` remain append-only
- Ticket 1 role protections remain intact
- Ticket 2 baseline RLS protections remain intact
- Ticket 5 address privacy remains intact
- Ticket 6 marketplace state machine remains intact
- Ticket 7A payment ledger protections remain intact
- Ticket 7B refund protections remain intact
- Ticket 7C cash-disabled protections remain intact
- Ticket 7D payout release controls remain intact

## 11. Definition of done

Ticket 7E implementation may be considered ready for closeout when:

- hosted checkout contract is defined server-side
- mock adapter is deterministic and sandbox-only
- production fail-closed provider-mode validation exists
- checkout creation updates `payments.status` only through trusted logic
- mock paid/failed outcomes update payment state only through trusted logic
- no card/bank credential fields or raw credential data are stored
- `payment_events`, `vendor_events`, and `audit_events` are written safely
- idempotency is enforced for checkout creation and mock outcomes
- pgTAP tests prove positive and negative paths
- all previous database tests remain green

Ticket 7E must not be marked complete until its implementation tests pass locally or in CI.
