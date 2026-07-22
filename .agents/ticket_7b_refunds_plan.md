# Ticket 7B Implementation Plan - Refund requests and refund event ledger

## Goal

Add a secure, auditable refund-request foundation without executing real refunds through a live payment provider.

Ticket 7B should let booking parties request refunds, let authorised admins/server logic approve or reject those requests, and record every trusted refund state change in an append-only refund event ledger.

## Explicit non-goals

Do not implement these in Ticket 7B:

- live payment provider integration
- real refund execution with a bank/card/payment vendor
- cash workflow
- payout release
- payout release freeze/unfreeze
- real webhook handlers
- provider disbursement
- UI features beyond later wiring requirements

## Starting point

Ticket 7A already provides:

- constrained `payments.status`
- separate `payments.release_status`
- `payments.refunded_minor`
- append-only `payment_events`
- trusted/admin payment event path through `admin_record_payment_event(...)`
- direct customer/provider payment mutation blocked
- CI coverage in `payments_ledger.test.sql`

Ticket 7B should build on that foundation without weakening any Ticket 1, 2, 5, 6, or 7A protections.

## Proposed database model

### `public.refund_requests`

Recommended fields:

- `id uuid primary key`
- `payment_id uuid not null references public.payments(id)`
- `booking_id uuid not null references public.bookings(id)`
- `requested_by uuid not null references public.profiles(id)`
- `requested_by_role text not null`
- `amount_minor integer not null`
- `currency char(3) not null default 'ZAR'`
- `reason_code text not null`
- `reason_text text`
- `status text not null`
- `admin_decision_by uuid references public.profiles(id)`
- `admin_decision_at timestamptz`
- `admin_decision_reason text`
- `idempotency_key text`
- `provider_name text`
- `provider_refund_reference text`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Suggested status values:

- `requested`
- `under_review`
- `approved`
- `rejected`
- `cancelled`
- `processing`
- `succeeded`
- `failed`

Ticket 7B may include `processing`, `succeeded`, and `failed` as constrained future-safe statuses, but must not pretend real provider execution exists yet.

### `public.refund_events`

Recommended fields:

- `id uuid primary key`
- `refund_request_id uuid not null references public.refund_requests(id)`
- `payment_id uuid not null references public.payments(id)`
- `booking_id uuid not null references public.bookings(id)`
- `event_type text not null`
- `amount_minor integer not null`
- `currency char(3) not null default 'ZAR'`
- `provider_name text`
- `provider_refund_reference text`
- `provider_event_id text`
- `idempotency_key text`
- `actor_id uuid references public.profiles(id)`
- `source text not null`
- `metadata jsonb not null default '{}'::jsonb`
- `occurred_at timestamptz not null default now()`

Suggested event types:

- `refund_requested`
- `refund_under_review`
- `refund_approved`
- `refund_rejected`
- `refund_cancelled`
- `refund_processing_recorded`
- `refund_succeeded_recorded`
- `refund_failed_recorded`
- `admin_note`

## Constraints and integrity rules

- `refund_requests.amount_minor > 0`.
- Refund currency must match payment currency.
- Refund request booking must match payment booking.
- Refund amount cannot exceed payment amount minus already-refunded amount.
- Total succeeded/refund-counted amount across refund requests must not exceed `payments.amount_minor`.
- Only payments in refund-eligible statuses may receive refund requests, likely `paid` or `partially_refunded`.
- A rejected/cancelled refund must not increase `payments.refunded_minor`.
- A full successful refund should move `payments.status` to `refunded`.
- A partial successful refund should move `payments.status` to `partially_refunded`.
- `payments.refunded_minor` must remain trusted-function controlled.
- `refund_events` must be append-only.
- Duplicate idempotency keys and provider event IDs must not create duplicate events.

## RLS and privilege model

### Booking parties

Customers/providers may:

- read refund requests for bookings where they are a booking party
- create a refund request for their own booking through a safe function only

Customers/providers must not:

- directly insert/update/delete refund table rows
- approve refunds
- reject refunds
- mark refunds as succeeded/failed
- update `payments.refunded_minor`
- update `payments.status`
- insert/update/delete `refund_events`

### Admin/server logic

Authorised admin/server functions may:

- move a refund request to `under_review`
- approve a refund request
- reject a refund request
- record sandbox/manual provider outcome metadata
- update `payments.refunded_minor` and `payments.status` only after a trusted refund-success transition
- write `refund_events`
- write `payment_events`
- write `audit_events`

All admin/server refund actions must require an authenticated platform admin or trusted server context and a non-empty reason where appropriate.

## Trusted functions to add

Recommended functions:

- `customer_request_refund(payment_id, amount_minor, reason_code, reason_text, idempotency_key)`
- `provider_request_refund(payment_id, amount_minor, reason_code, reason_text, idempotency_key)`
- `admin_mark_refund_under_review(refund_request_id, reason)`
- `admin_approve_refund(refund_request_id, reason)`
- `admin_reject_refund(refund_request_id, reason)`
- `admin_record_refund_outcome(refund_request_id, outcome_status, provider_reference, idempotency_key, reason, metadata)`

Important: `admin_record_refund_outcome(...)` may record sandbox/manual outcomes only in Ticket 7B. It must not call a live payment vendor.

## Payment-status interaction

Ticket 7B should update payment state only through trusted logic:

- `payments.refunded_minor` increases only when a trusted refund-success outcome is recorded.
- `payments.status = 'partially_refunded'` when `0 < refunded_minor < amount_minor`.
- `payments.status = 'refunded'` when `refunded_minor = amount_minor`.
- Invalid refund outcomes must not change `payments`.
- Refund approval alone should not mark the payment refunded unless Ticket 7B intentionally models manual/sandbox success as a separate trusted outcome.

## Audit and ledger requirements

Every trusted refund state change should write:

- one `refund_events` row
- one `audit_events` row

Refund success/failure outcomes that affect payment state should also write:

- one `payment_events` row

`refund_events.metadata` must not contain card numbers, CVV, bank-login credentials, raw payment credentials, identity documents, or unredacted provider payloads.

## Required pgTAP tests

Add a new test file, likely:

- `outputs/marketplace-production-foundation/supabase/tests/database/refunds_ledger.test.sql`

Required coverage:

- customer can request refund for own booking payment through safe function
- provider can request refund for own booking payment through safe function, if product policy allows
- customer cannot request refund for unrelated payment
- provider cannot request refund for unrelated payment
- anonymous user cannot access refund requests/events
- unrelated authenticated user cannot read refund requests
- booking parties can read safe refund request summary
- frontend users cannot directly insert/update/delete `refund_requests`
- frontend users cannot insert/update/delete `refund_events`
- refund amount must be greater than zero
- refund amount cannot exceed payment amount
- refund amount cannot exceed remaining refundable amount
- invalid refund status is rejected
- invalid refund event type is rejected
- normal customer/provider cannot approve refund
- normal customer/provider cannot reject refund
- normal customer/provider cannot mark refund succeeded/failed
- admin/server can approve refund with audit and refund event
- admin/server can reject refund with audit and refund event
- trusted refund-success outcome updates `payments.refunded_minor`
- partial refund moves payment to `partially_refunded`
- full refund moves payment to `refunded`
- duplicate idempotency key does not duplicate refund event
- `refund_events` cannot be updated
- `refund_events` cannot be deleted
- customer/provider direct payment mutation remains blocked
- Ticket 1 role protections remain intact
- Ticket 2 baseline RLS protections remain intact
- Ticket 5 address protections remain intact
- Ticket 6 marketplace state machine remains intact
- Ticket 7A payment ledger protections remain intact

## Files likely affected when implemented

- `outputs/marketplace-production-foundation/supabase/migrations/008_refund_requests_and_ledger.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/refunds_ledger.test.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/rls_test_seed.inc`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `rls_policy_matrix.md`
- `production_hardening_plan.md`
- `hardening_progress.md`
- possibly `outputs/marketplace-production-foundation/src/integrations/contracts.ts`

## CI requirements

Add the new refund pgTAP file to the existing `Supabase database tests` workflow after `payments_ledger.test.sql`.

The workflow should still run all prior suites:

- `role_escalation.test.sql`
- `baseline_rls.test.sql`
- `exact_address_privacy.test.sql`
- `marketplace_state_machine.test.sql`
- `payments_ledger.test.sql`
- `refunds_ledger.test.sql`

## Definition of Done

- Refund request tables and refund event ledger exist with RLS enabled.
- Frontend users cannot directly mutate refund workflow or payment refund totals.
- Booking parties can request refunds only for their own booking/payment through safe functions.
- Admin/server refund decisions are trusted-function controlled.
- Every refund state change is audited and ledgered.
- Refund events are append-only.
- Payment `refunded_minor` and `status` are updated only by trusted refund outcome logic.
- Duplicate idempotency keys do not duplicate refund events.
- Ticket 1, 2, 5, 6, and 7A tests remain green.
- No live provider refund execution, cash workflow, payout release, or real webhooks are introduced.
