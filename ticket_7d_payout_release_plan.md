# Ticket 7D Planning Document — Payout release, payout freeze, and dispute-aware release blocking

## Goal

Plan the secure payout-release layer for LEKKADEALL without implementing it yet.

Ticket 7D must make provider payout release server/admin controlled, dispute-aware, refund-aware, auditable, and idempotent. It must not allow customers, providers, or frontend clients to mark funds released.

## Planning-only status

This document is planning-only.

Do not create migrations, database functions, tests, webhook handlers, provider-payout adapters, or UI for Ticket 7D until the implementation ticket is explicitly requested.

## Current starting point

Already implemented before Ticket 7D:

- Ticket 7A added constrained `payments.status` values.
- Ticket 7A added separate `payments.release_status`.
- Ticket 7A added append-only `payment_events`.
- Ticket 7B added refund requests and append-only refund events.
- Ticket 7C disabled cash/off-platform cash for MVP.
- `payments.release_paused` and `payments.released_at` already exist from the initial schema.

Still missing:

- release eligibility calculation
- payout freeze/unfreeze rules
- dispute-aware release blocking
- refund-aware release blocking
- trusted release/freeze functions
- real provider payout execution
- payout reconciliation
- payout webhook handling

## 1. MVP payout-release policy

Recommended MVP policy:

- Payout release is allowed only for protected online/sandbox platform payments.
- Cash/off-platform payments are not eligible because Ticket 7C disables cash for MVP.
- A payment must be confirmed paid before any release eligibility.
- The booking must be completed before release eligibility.
- Release should not happen automatically at first; MVP should use trusted admin/server approval after all blockers are checked.
- Real money movement must remain sandbox/mock/manual until payment-provider payout credentials and webhook reconciliation are available.

Important user-facing rule:

- Do not tell providers that funds have been released unless the payout provider confirms release or the app is clearly in sandbox/manual mode.

## 2. Release statuses

Existing allowed `payments.release_status` values from Ticket 7A:

- `not_applicable`
- `pending`
- `paused`
- `eligible`
- `released`
- `cancelled`

Recommended semantics:

- `not_applicable`: payment is not yet paid or is not eligible for release tracking.
- `pending`: payment is paid but not yet eligible for release.
- `paused`: release is frozen due to dispute, refund, provider risk, admin hold, or reconciliation issue.
- `eligible`: all release conditions are satisfied, but money has not been released yet.
- `released`: trusted provider/admin logic has recorded a release.
- `cancelled`: release will not happen, usually because payment failed, expired, cancelled, or fully refunded.

## 3. Release eligibility rules

A payment may become `eligible` only if all conditions are true:

- `payments.status` is `paid` or, if business rules allow it, `partially_refunded`.
- `payments.payment_method` is one of the allowed online/sandbox MVP methods.
- `payments.release_status` is not `released` or `cancelled`.
- booking status is `completed`.
- payment is not fully refunded.
- no refund request for the payment is in `requested`, `under_review`, `approved`, or `processing`.
- no open dispute exists for the booking.
- `payments.release_paused = false`.
- provider account is active.
- provider is still approved, verified, and not suspended.
- provider is not under admin hold.
- configured hold period has elapsed, if a hold period is adopted.
- amount to release is greater than zero after refund/platform-fee calculations.

For MVP, if any condition is uncertain, fail closed and keep release `pending` or `paused`.

## 4. Payout freeze / pause rules

Release must be paused or frozen when:

- a dispute is opened for the booking
- a refund is requested or approved
- provider is suspended
- provider verification/review status is revoked
- payment reconciliation is stale or inconsistent
- webhook/provider data conflicts with internal state
- admin places a manual hold with a reason

Recommended future fields if not already present:

- `release_paused_at`
- `release_paused_by`
- `release_pause_reason`
- `release_hold_until`
- `release_eligible_at`
- `release_provider_reference`
- `release_idempotency_key`

These should be changed only through trusted functions.

## 5. Dispute-aware release blocking

Opening a dispute should atomically:

- create the dispute record
- set `payments.release_paused = true`
- set `payments.release_status = 'paused'` unless already released/cancelled
- write a `payment_events` release-pause event
- write an `audit_events` record

Release must remain blocked while any dispute for the booking is open or under review.

Recommended dispute statuses that should block release:

- `open`
- `under_review`
- `awaiting_customer`
- `awaiting_provider`
- `escalated`

Existing status values must be confirmed before implementation because the current dispute schema may use different names.

## 6. Refund-aware release blocking

Refund activity should block release when:

- a refund request is `requested`
- a refund request is `under_review`
- a refund request is `approved`
- a refund outcome is `processing`
- a refund outcome is uncertain or failed and needs admin review

If a refund succeeds:

- full refund should move release to `cancelled`
- partial refund should recalculate releasable amount before eligibility

Rejected refunds may allow release again only after the release eligibility function re-checks all blockers.

## 7. Trusted functions to implement later

Recommended future functions:

- `admin_pause_payment_release(payment_id, reason, idempotency_key)`
- `admin_resume_payment_release(payment_id, reason, idempotency_key)`
- `system_mark_release_eligible(payment_id, idempotency_key)`
- `admin_mark_release_eligible(payment_id, reason, idempotency_key)`
- `admin_record_payout_release(payment_id, provider_reference, amount_minor, reason, idempotency_key)`
- `system_reconcile_payout_release(payment_id, provider_event_id, provider_reference, status, metadata)`

All functions must:

- be `SECURITY DEFINER`
- set an explicit safe `search_path`
- verify authenticated caller or trusted server context
- verify platform-admin authority where required
- require non-empty reason for admin actions
- use row locks for payment/booking/refund/dispute rows
- be idempotent by idempotency key/provider event ID
- write `payment_events`
- write `audit_events`

## 8. Direct mutation lockdown

Frontend users must not directly update:

- `payments.release_status`
- `payments.release_paused`
- `payments.released_at`
- future release pause/hold/reference fields
- payment event rows
- audit rows

Customers and providers may read safe payment summaries for their own booking only, but they must not control release state.

## 9. Payment event ledger requirements

Ticket 7D should extend allowed payment event types if needed.

Candidate event types:

- `release_paused`
- `release_resumed`
- `release_eligible`
- `release_cancelled`
- `payout_release_recorded`
- `payout_release_failed`
- `payout_reconciliation_checked`

Every event should include:

- `payment_id`
- `booking_id`
- `amount_minor`
- `currency`
- `provider_name`
- `provider_event_id` where applicable
- `idempotency_key`
- `actor_id`
- `source`
- safe metadata
- `occurred_at`

No raw payment credentials, bank credentials, provider secrets, or full webhook payloads may be stored.

## 10. Provider payout abstraction

Real payout execution should remain mock/sandbox/manual until vendor credentials, signed webhooks, and reconciliation are ready.

Future vendor-neutral operations:

- `create_payout_release(payment_id, amount, provider_id, idempotency_key)`
- `get_payout_status(provider_reference)`
- `verify_payout_webhook(raw_body, signature)`
- `parse_payout_webhook(raw_body)`
- `reconcile_payout(provider_reference)`

Production must fail closed if configured in mock payout mode.

## 11. RLS and privilege model

Recommended access:

- Customers: read own booking payment summary only.
- Providers: read own booking payment summary only.
- Admin frontend: no broad direct table mutation.
- Service/server functions: trusted release actions only.
- `payment_events`: append-only through trusted functions.
- `audit_events`: append-only through trusted audit function.

Policies and grants must preserve Tickets 1, 2, 5, 6, 7A, 7B, and 7C.

## 12. Required pgTAP tests

Ticket 7D implementation tests should prove:

- customer cannot mark release as eligible
- provider cannot mark release as eligible
- customer cannot mark payment released
- provider cannot mark payment released
- admin/server cannot release unpaid payment
- admin/server cannot release incomplete booking
- admin/server cannot release fully refunded payment
- admin/server cannot release while refund is requested
- admin/server cannot release while refund is under review
- admin/server cannot release while refund is approved/processing
- admin/server cannot release while dispute is open
- admin/server cannot release when provider is suspended
- admin/server cannot release when provider approval is revoked
- admin/server can pause release with a reason
- admin/server can resume release only after blockers are cleared
- release pause writes `payment_events`
- release pause writes `audit_events`
- release eligibility writes `payment_events`
- payout release recording writes `payment_events`
- payout release recording writes `audit_events`
- duplicate idempotency key does not duplicate events
- payment events remain append-only
- audit events remain append-only
- cash/off-platform payment cannot be released
- Ticket 1 role protections remain intact
- Ticket 2 baseline RLS protections remain intact
- Ticket 5 address privacy remains intact
- Ticket 6 marketplace state machine remains intact
- Ticket 7A payment ledger protections remain intact
- Ticket 7B refund protections remain intact
- Ticket 7C cash-disabled protections remain intact

## 13. Definition of done

Ticket 7D may be considered implementation-ready when:

- release eligibility rules are approved
- dispute statuses that block release are confirmed
- refund statuses that block release are confirmed
- provider eligibility checks are confirmed
- payout release remains server/admin controlled
- idempotency strategy is defined
- audit and payment-ledger events are defined
- real-provider payout execution is explicitly separated from manual/sandbox state recording
- pgTAP tests are written before or alongside migration implementation
- all prior security tests remain green

Ticket 7D may be marked complete only after implementation tests pass locally or in CI.
