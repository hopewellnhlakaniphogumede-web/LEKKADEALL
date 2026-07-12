# Ticket 7 Implementation Plan — Payments, Cash Handling, Refunds, and Payout Release

## Goal

Build the payment layer toward a secure production-ready MVP without storing card, bank, or payment credentials in the LEKKADEALL database.

Ticket 7 should make payment state trustworthy, auditable, vendor-neutral, and dispute-aware while remaining safe to run with mock/sandbox providers until real vendor credentials are approved.

## Current starting point

Status note as of 12 July 2026:

- Ticket 7A now constrains payment status and adds `payment_events`.
- Ticket 7B now adds `refund_requests` and append-only `refund_events`.
- Ticket 7C now disables cash/off-platform cash for MVP at the database layer.
- Ticket 7D now adds internal/manual-sandbox payout release controls and blocker checks.
- Ticket 7E now adds the mock/sandbox hosted-checkout contract and deterministic mock paid/failed outcome recording.
- Real hosted checkout provider integration, real provider refund execution, real provider payout execution/reconciliation, signed webhooks, and reconciliation are still not implemented.

Original starting point before Ticket 7A/7B:

- Ticket 6 creates an internal pending payment row when a customer accepts a bid.
- Direct frontend mutation of payment/release fields is blocked.
- `payments.status` is still text and needs stricter constraints.
- There was no refund ledger, payout ledger, hosted-checkout abstraction, real webhook reconciliation, or cash policy enforcement yet.

## 1. Payment status constraints

Recommended database direction:

- Replace free-text `payments.status` with a constrained enum or strict check constraint.
- Define the MVP state set explicitly, for example:
  - `payment_pending`
  - `checkout_created`
  - `awaiting_cash_confirmation`
  - `paid`
  - `failed`
  - `expired`
  - `cancelled`
  - `refund_pending`
  - `partially_refunded`
  - `refunded`
  - `release_pending`
  - `release_paused`
  - `released`
- Add constraints so impossible combinations fail, e.g.:
  - `paid_at` must be null unless status is paid/release/refund related.
  - `refunded_minor <= amount_minor`.
  - `released_at` must be null unless payout is released.
  - `release_paused = true` when an open dispute exists.

## 2. Payment events / ledger

Add an append-only payment ledger table, likely `payment_events`.

Minimum fields:

- `id`
- `payment_id`
- `booking_id`
- `event_type`
- `amount_minor`
- `currency`
- `provider_name`
- `provider_event_id`
- `idempotency_key`
- `actor_id`
- `source`
- `metadata`
- `occurred_at`

Rules:

- Frontend users cannot insert/update/delete ledger rows.
- Every trusted payment status change writes one ledger event.
- Ledger rows are append-only.
- Vendor event IDs and idempotency keys are unique where applicable.

## 3. Hosted payment provider abstraction

Implementation status as of 12 July 2026: Ticket 7E adds the database-side hosted-checkout contract for mock/sandbox only through `customer_create_mock_checkout_session(...)`. This creates a safe mock checkout URL/reference, sets `payments.status = checkout_created`, writes `payment_events`, and writes `audit_events`. It does not call a live hosted payment provider.

Create a vendor-neutral server-side payment contract before integrating any real provider.

Core operations:

- `create_checkout_session(booking_id, idempotency_key)`
- `get_payment_status(provider_reference)`
- `request_refund(payment_id, amount_minor, reason, idempotency_key)`
- `verify_webhook_signature(headers, raw_body)`
- `parse_webhook_event(raw_body)`

Important:

- Card/bank credentials must never touch frontend database tables.
- The app should store only safe references, statuses, amounts, timestamps, and reconciliation metadata.
- Production must fail closed if provider mode is `mock`.

## 4. Mock payment adapter

Implementation status as of 12 July 2026: Ticket 7E adds deterministic database-level mock checkout and mock outcome functions for CI/local/sandbox:

- `validate_payment_provider_mode(...)`
- `customer_create_mock_checkout_session(...)`
- `admin_record_mock_payment_outcome(...)`

The mock adapter records safe payment references only, writes `vendor_events`, `payment_events`, and `audit_events`, records `real_money_moved = false`, rejects paid-after-refunded, and does not regress paid payments if a later failed event arrives.

Mock mode must be explicitly marked non-production. Production + `mock` fails closed through the provider-mode validation path.

Future server adapter work should call these database functions in local/CI/sandbox, then swap to a real hosted-checkout provider only after credentials, webhook secrets, and reconciliation are available.

The mock/sandbox adapter supports deterministic test scenarios:

It should support deterministic test scenarios:

- checkout created
- payment paid
- payment failed
- duplicate webhook event
- out-of-order webhook event
- partial refund
- full refund
- release paused by dispute
- release approved after completion/dispute resolution

## 5. Cash payment policy

Implementation status as of 12 July 2026: Ticket 7C chose the MVP policy and disables cash/off-platform cash at the database layer. The notes below are retained for future product discussion only if the business later chooses to allow an explicitly off-platform, not-payment-protected cash workflow.

Recommended future approach if cash is ever reconsidered:

- Online payment is the protected default.
- Cash jobs are disabled for MVP.
- If cash is ever allowed later, it may be allowed only if clearly labelled as “cash/off-platform, not payment-protected”.
- Cash status should be tracked separately from online payment status.
- Cash confirmation should require both customer and provider confirmation or admin override.
- Cash bookings should not trigger payout release logic because the platform did not hold funds.
- Cash disputes should still be possible, but refund handling differs because LEKKADEALL may not control the money.

Potential statuses:

- `cash_selected`
- `cash_customer_confirmed`
- `cash_provider_confirmed`
- `cash_disputed`
- `cash_unverified`

## 6. Refund requests and refund events

Add refund workflow tables, likely:

- `refund_requests`
- `refund_events`

Refund request fields:

- `payment_id`
- `booking_id`
- `requested_by`
- `amount_minor`
- `reason_code`
- `reason_text`
- `status`
- `admin_decision_by`
- `admin_decision_at`
- `idempotency_key`

Refund event fields:

- `refund_request_id`
- `event_type`
- `amount_minor`
- `provider_reference`
- `provider_event_id`
- `metadata`
- `occurred_at`

Rules:

- Customers/providers may request refunds only for their own booking.
- Normal users cannot approve, reject, or execute refunds.
- Refund execution is trusted server/admin only.
- Every refund state change is audited and ledgered.

## 7. Payout release / freeze rules

Implementation status as of 12 July 2026: Ticket 7D adds internal/manual-sandbox release eligibility, pause/resume, blocker checks, audit/payment ledger events, and manual/sandbox payout-release recording. It does not execute real provider payouts.

Payout release must be server/admin controlled and dispute-aware.

Recommended MVP release rules:

- No payout release until payment is confirmed paid.
- No payout release before booking completion.
- No payout release while:
  - booking is disputed
  - payment `release_paused = true`
  - refund is pending
  - provider is suspended
  - provider verification/review status is no longer approved
- Release can be:
  - automatically scheduled after a configurable hold period, or
  - manually approved by admin for MVP.

Every release/freeze/unfreeze action must write:

- `payment_events`
- `audit_events`

Remaining future work:

- integrate real provider payout execution only after credentials are available
- verify signed payout webhooks
- reconcile against provider payout status
- connect the full dispute-opening workflow so dispute creation and release pause are atomic

## 8. Dispute-aware release blocking

Opening a dispute must atomically pause payment release.

Ticket 7 should prepare the payment-side rules even if full dispute implementation remains Ticket 10:

- Add or enforce `release_paused`.
- Add `release_pause_reason`.
- Add `release_paused_at`.
- Add `release_paused_by`.
- Prevent release while an open dispute exists.
- Add tests proving dispute rows block release.

If the dispute schema is not ready for full integration, keep this as a guarded stub with tests for existing dispute states.

## 9. Signed and idempotent webhook requirements

Ticket 7 should define the database and contract requirements; full vendor webhook handlers may remain Ticket 8 if needed.

Requirements:

- Webhook handlers must verify signatures against server-side secrets.
- Raw request body must be used for signature verification.
- Duplicate vendor event IDs must be ignored safely.
- Processing must be idempotent by `(provider_name, provider_event_id)` or equivalent.
- Out-of-order events must not regress payment state.
- Webhook processing must write to `vendor_events`, `payment_events`, and `audit_events`.
- Failed webhook verification must not mutate payment state.

No webhook secret may be committed.

## 10. Database tests required

Add pgTAP tests covering:

- `payments.status` rejects invalid values.
- Normal customers/providers cannot directly mark payments paid/refunded/released.
- Customers/providers can read only payments for their own bookings.
- Unrelated users cannot read payment records.
- Payment ledger is append-only.
- Trusted payment function can create hosted checkout state.
- Duplicate idempotency key does not create duplicate checkout/payment events.
- Mock paid webhook updates payment once.
- Duplicate mock paid webhook is idempotent.
- Invalid webhook signature simulation does not mutate state.
- Customer can request refund for own booking.
- Customer cannot request refund for another booking.
- Provider cannot approve/execute refund.
- Admin/server can approve/reject refund with audit event.
- Refund amount cannot exceed paid amount.
- Partial and full refund statuses are correct.
- Payout release is blocked before payment confirmation.
- Payout release is blocked before booking completion.
- Payout release is blocked while release is paused or dispute is open.
- Payout release is blocked if provider is suspended/unapproved.
- Manual/sandbox payout release recording writes payment ledger and audit event.
- Cash bookings do not pretend to be platform-protected online payments.
- Ticket 1, 2, 5, and 6 smoke protections remain intact.

## 11. What remains mock/sandbox until vendor credentials are available

Keep these mock/sandbox only:

- Real hosted checkout provider calls.
- Real payment webhook signature verification secrets.
- Real card/EFT/instant EFT confirmation.
- Real refund execution.
- Real payout/disbursement execution.
- Real reconciliation against provider APIs.
- Real cash collection verification, if any.

Production readiness gate:

- Production deployment must fail if payment provider is set to `mock`.
- Production deployment must fail if required payment webhook secrets are missing.
- No test provider references should appear as production payment options.

## Proposed files likely affected when Ticket 7 is implemented

- `outputs/marketplace-production-foundation/supabase/migrations/007_payments_refunds_release.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/payments_refunds_release.test.sql`
- `outputs/marketplace-production-foundation/src/integrations/contracts.ts`
- Future server/payment adapter modules
- `rls_policy_matrix.md`
- `hardening_progress.md`
- `TESTING.md`

## Definition of Done for Ticket 7

- Payment/refund/release state is constrained and cannot be directly mutated by frontend users.
- Payment events and refund events are append-only.
- Hosted checkout path is vendor-neutral and mockable.
- Cash policy is explicit and does not misrepresent protection.
- Refunds are server/admin controlled, idempotent, and audited.
- Payout release is blocked by disputes, refunds, provider suspension, and incomplete bookings.
- pgTAP tests pass locally/CI.
- No production secrets are committed.
