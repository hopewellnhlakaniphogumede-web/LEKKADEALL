# LEKKADEALL RLS Policy Matrix

**Date:** 12 July 2026  
**Ticket:** Ticket 2 baseline RLS + Ticket 5 exact-address privacy + Ticket 6 marketplace state-machine update + Ticket 7A payment ledger foundation + Ticket 7B refund ledger foundation + Ticket 7C cash-disabled MVP policy + Ticket 7D payout release controls + Ticket 8A mock webhook database processing + Ticket 8B mock webhook route verification

## Public schema table inventory

The public schema currently contains 19 application tables:

1. `profiles`
2. `provider_profiles`
3. `service_categories`
4. `provider_services`
5. `service_requests`
6. `bids`
7. `bookings`
8. `payments`
9. `payment_events`
10. `refund_requests`
11. `refund_events`
12. `vendor_events`
13. `identity_verifications`
14. `disputes`
15. `dispute_evidence`
16. `reviews`
17. `consents`
18. `data_subject_requests`
19. `audit_events`

## RLS status

Before Ticket 2, these public tables did **not** have RLS enabled in `001_initial_schema.sql`:

- `service_categories`
- `provider_services`
- `vendor_events`

After `003_repair_baseline_rls.sql`, the original public tables had RLS enabled. `007_payment_status_and_ledger.sql` adds `payment_events` with RLS enabled, and `008_refund_requests_and_ledger.sql` adds `refund_requests` / `refund_events` with RLS enabled, so every current public application table above has RLS enabled.

## Access matrix

Legend:

- `S` = SELECT
- `I` = INSERT
- `U` = UPDATE
- `D` = DELETE
- `own` = only records owned by `auth.uid()`
- `party` = only booking parties
- `approved` = active, verified, approved provider
- `server` = service role / trusted server function only
- `none` = no direct frontend access

| Table | Sensitivity | Customer S/I/U/D | Provider S/I/U/D | Admin S/I/U/D | Service role / server permissions | Notes |
|---|---|---|---|---|---|---|
| `profiles` | High - account identity, role/status fields | S own; U safe own fields only; I/D none | S own; U safe own fields only; I/D none | Direct broad admin access none; privileged role/status via server functions | Full trusted access through server/admin functions | `role` and `account_status` are trigger-protected and audited through Ticket 1 functions. |
| `provider_profiles` | High - provider compliance/approval state | S approved provider profiles only; I/U/D none | S own; U safe own fields only; I/D none | Direct broad admin access none; privileged review/verification via server functions | Full trusted access through server/admin functions | Public discovery now requires active account, verified status, and approved review status. |
| `service_categories` | Low/medium - public taxonomy, admin-controlled | S active only; I/U/D none | S active only; I/U/D none | Direct frontend mutation none | Server/admin may seed or mutate categories | Active category read is safe for anonymous/authenticated users; inactive categories are hidden. |
| `provider_services` | Medium - provider service offerings and prices | S active services for approved providers; I/U/D none | S own plus active approved-provider services; I/U/D own only if approved | Direct frontend mutation none | Server/admin may moderate or repair records | Mutation requires `auth.uid() = provider_id` and approved provider status. Anonymous access is denied. |
| `service_requests` | High - customer request details and address material | S own safe request columns; I/U/D none directly; draft creation through `customer_create_draft_request(...)`; reviewed owned-draft content replacement through `customer_update_draft_request(...)`; strict owned-draft cancellation through `customer_cancel_draft_request(...)`; publication remains a separate trusted backend function and is not enabled in the frontend; exact address via controlled address functions | S eligible open safe columns/summaries; I/U/D none directly | Direct frontend access none | Trusted state-machine and admin/server functions only | Ticket 6 removed the broad owner `FOR ALL` mutation policy. Ticket 9A-7 revokes authenticated execution of legacy `customer_cancel_request(uuid,text)`. Ticket 9A-8 exposes only a full reviewed-field draft update RPC, reuses Ticket 9A-5 validation, rejects bids/bookings/inconsistent rows, and never enables the state-transition flag. `status`, `closes_at`, ownership, address material, and workflow timestamps remain protected. |
| `bids` | High - commercial offers and bid state | S bids on own requests; I/U/D none | S own bids; I/U/D none directly; submit/withdraw through `provider_submit_bid(...)` and `provider_withdraw_bid(...)` | Direct frontend access none | Trusted state-machine functions only | Ticket 6 removed broad provider bid mutation. One accepted bid per request is enforced by partial unique index; acceptance/decline happens inside `customer_accept_bid(...)`. |
| `bookings` | High - booking parties, schedule, commercial amounts | S party only; I/U/D none; completion confirmation through `customer_confirm_completion(...)` after `in_progress` | S party only; I/U/D none; progress/completion through `booking_mark_in_progress(...)` and `provider_confirm_completion(...)` after `in_progress` | Direct frontend access none | Trusted state-machine functions only | Ticket 6 creates bookings only from accepted bids and validates request/bid/customer/provider/amount/schedule consistency by trigger. |
| `payments` | Critical - payment references/status, no card data | S party only; I/U/D none | S party only; I/U/D none | Direct frontend access none | Ticket 6 marketplace functions may prepare pending rows; Ticket 7A trusted admin/server function may update payment status; Ticket 7D trusted admin/server functions may pause/resume/mark eligible/record manual-sandbox payout release; Ticket 8A trusted mock/sandbox webhook function may process already verified mock events | Ticket 7A constrains `status` to safe MVP payment-status values and adds separate `release_status`. Ticket 7C adds `payment_method` and permits only protected online/sandbox method markers for MVP; `cash`, `off_platform_cash`, and cash-confirmation markers are rejected. Ticket 7D adds internal release-control fields and blocker checks. Ticket 8B verifies mock webhook signatures before Ticket 8A handles mock/sandbox webhook transitions. Frontend users cannot directly mutate payment/release/refund/provider fields. Real hosted checkout funding, live provider webhooks, real payout provider execution, and reconciliation remain future tickets. |
| `payment_events` | Critical - append-only payment status/release ledger | none | none | Direct frontend access none | Append through trusted payment/release/refund/admin/mock-webhook functions only | RLS enabled; frontend and direct service-role table privileges revoked; UPDATE/DELETE blocked by append-only trigger; idempotency protected by unique indexes on provider event ID and idempotency key. Ticket 7D extends event types for release pause/resume/eligibility/manual-sandbox payout release recording. Ticket 8A adds mock/sandbox webhook event types for processed, out-of-order, and manual-review outcomes. |
| `refund_requests` | Critical - refund workflow/commercial amounts | S party only; I/U/D none directly; request through `customer_request_refund(...)` | S party only; I/U/D none directly; request through `provider_request_refund(...)` | Direct frontend access none | Trusted refund functions only | Ticket 7B constrains refund statuses, requires booking-party ownership for request functions, and makes admin decisions server/admin-function controlled with required reasons. No live refund provider execution. |
| `refund_events` | Critical - append-only refund ledger | none | none | Direct frontend access none | Append through trusted refund functions only | RLS enabled; frontend and direct service-role table privileges revoked; UPDATE/DELETE blocked by append-only trigger; idempotency protected by unique indexes on provider event ID and idempotency key. |
| `vendor_events` | Critical - webhook idempotency and safe provider-event metadata | none | none | Direct frontend access none | Server/webhook handlers only through trusted private/admin functions; Ticket 8B verifies mock webhook signatures before Ticket 8A uses `admin_process_verified_mock_payment_webhook(...)` for mock/sandbox events | RLS enabled; all frontend table privileges revoked; no frontend policies. Stores safe event metadata and `payload_hash` only; raw webhook bodies are not stored. |
| `identity_verifications` | Critical - identity verification result metadata | S own status only; I/U/D none | S own status only; I/U/D none | Direct frontend access none | Identity webhook/admin server actions only | Frontend insert/update/delete revoked. Raw identity evidence should remain outside app DB. |
| `disputes` | High - private case details | S party only; I own party dispute via existing policy; U/D none | S party only; I own party dispute via existing policy; U/D none | Direct frontend access none | Server/admin resolves and audits | Ticket 7D blocks payout release when an active dispute exists. Ticket 10 still needs the full atomic dispute-opening workflow that creates the dispute and pauses release together. |
| `dispute_evidence` | High - private evidence metadata | S party only; I currently uploaded_by only | S party only; I currently uploaded_by only | Direct frontend access none | Server/storage policies should control evidence uploads | Existing insert policy is still too broad because it does not require booking-party membership. |
| `reviews` | Medium/high - public trust content | S published; I only after participated completed booking | S published; I only after participated completed booking | Direct frontend moderation none | Server/admin moderation | Existing review insert still needs subject derivation and moderation hardening. |
| `consents` | High - compliance evidence | S/I/U/D own via existing policy | S/I/U/D own via existing policy | Direct frontend access none | Server should preserve consent evidence | Existing broad owner mutation remains a compliance risk; future ticket should make consent evidence append-oriented. |
| `data_subject_requests` | High - POPIA workflow | S/I/U/D own via existing policy | S/I/U/D own via existing policy | Direct frontend access none | Server/admin workflow processing | Existing owner mutation allows users to change workflow status; future ticket should restrict status fields. |
| `audit_events` | Critical - privileged action log | none | none | Direct frontend access none | Append through trusted private function only | `audit_events_append_only` blocks UPDATE/DELETE; frontend privileges revoked. |

## Immediate baseline policy decisions

- `vendor_events`: no frontend read/write access.
- `vendor_events`: trusted server/admin functions write idempotently on `(provider_name, provider_event_id)`; Ticket 8A uses this as the mock webhook idempotency boundary.
- `service_categories`: read-only active categories for frontend; all mutation server/admin-only.
- `provider_services`: authenticated read of active approved-provider services; owner mutation only for approved providers.
- `audit_events`: no frontend access; append-only through trusted function.
- `identity_verifications`: owner read only; no frontend insert/update/delete.
- `payment_events`: no frontend direct read/write access; append-only through trusted payment/release/admin/webhook functions.
- `refund_requests`: booking-party read only; all creation/decision/outcome changes through trusted functions.
- `refund_events`: no frontend direct read/write access; append-only through trusted refund functions.
- `payments.payment_method`: cash/off-platform cash is disabled for MVP; allowed values are online/sandbox markers only.
- `payments.checkout_url`, `payments.checkout_expires_at`, and `payments.checkout_idempotency_key`: safe mock/sandbox hosted-checkout references only; frontend users cannot mutate them directly.
- Mock checkout/outcome state changes: only through `customer_create_mock_checkout_session(...)` for the booking customer or `admin_record_mock_payment_outcome(...)` for platform-admin/trusted-server contexts.
- Mock webhook state changes: the Ticket 8B `payment-webhook` route verifies the mock signature against the exact raw request body first, then calls `admin_process_verified_mock_payment_webhook(...)`. This function stores `payload_hash` and safe metadata only.

## Private exact-address model after Ticket 5

- Exact address ciphertext is stored in `private.service_request_addresses`, not in frontend-facing `public.service_requests`.
- `private.service_request_addresses.customer_id` copies the owning `service_requests.customer_id` and is enforced by trigger.
- `public.service_requests.precise_address_ciphertext` remains only as a deprecated compatibility column and is forced to stay null by `prevent_service_request_precise_address_write`.
- Approved providers should discover open work through `list_provider_open_request_summaries(...)`, which excludes exact address material, private customer identifiers, internal/admin fields, payment-sensitive fields, and dispute-sensitive fields.
- Selected approved providers reveal exact address material through `reveal_confirmed_booking_address(...)` only after a revealable confirmed booking status.
- Every successful reveal writes `booking.address_revealed` to `audit_events`.
- Customer address creation/update goes through `customer_upsert_service_request_address(...)` and is limited to the customer's own draft request before publication/provider selection.
- Administrative address access goes through `admin_get_service_request_address(...)` with a required reason and audit event. Direct service-role table access is revoked so server workflows use audited functions.
- `service_request_description_has_exact_address_risk(...)` and the public-request description trigger reject likely street addresses, unit/room references, GPS coordinates, phone numbers, and house/stand/erf numbers when a request is published/open.

## Address-material field review

- `service_requests.precise_address_ciphertext`: deprecated compatibility column; forced null and not granted to frontend roles.
- `private.service_request_addresses.precise_address_ciphertext`: exact address ciphertext; private table, no frontend direct access, no direct service-role table access, accessed only through controlled/audited functions.
- `service_requests.customer_id`: private customer identifier; not returned by provider open-request summary and not included in frontend safe SELECT grants.
- `service_requests.description`: provider-visible free text for open summaries; now conservatively validated before publication/open status to block likely exact-address, GPS, unit/room, and phone material.
- `service_requests.suburb` and `service_requests.city`: retained as general location fields. They remain visible because providers need approximate service area; users must not place exact addresses in these fields.
- Other free-text fields (`bids.message`, `provider_services.description`, `disputes.description`, `reviews.body`) can technically contain address-like text, but they are not part of the provider-facing open-request summary. Later workflow tickets should add context-specific validation where those fields could leak sensitive data.

## Marketplace state-machine model after Ticket 6

- `service_requests`: `draft -> open -> awarded|cancelled|expired`. Customers create drafts through a trusted function. The frontend may edit only the seven reviewed content fields of an exact owned draft through `customer_update_draft_request(...)` and may cancel only an exact owned draft through `customer_cancel_draft_request(...)`. Although older backend functions exist, frontend publication and broader draft/open cancellation remain blocked/revoked. Direct frontend insert/update/delete is revoked and workflow fields are protected by trigger.
- `bids`: `submitted -> accepted|declined|withdrawn|expired`. Approved eligible providers submit/withdraw bids through trusted functions. Customers accept one valid bid through `customer_accept_bid(...)`, which declines competing submitted bids.
- `bookings`: `scheduled -> in_progress -> completed` for the current MVP database flow. Completion confirmations are rejected before `in_progress`. Later payment/refund/dispute tickets will extend the booking lifecycle for cancellation, refund, payout, and dispute states.
- `customer_accept_bid(...)` locks the bid/request, validates customer ownership, provider approval and category eligibility, bid/request expiry, duplicate booking prevention, and then creates the booking and pending payment record in one transaction.
- Direct frontend mutation of `service_requests`, `bids`, `bookings`, and payment/release workflow state is denied through revoked DML privileges plus trigger guards.
- Booking integrity is enforced by trigger: booking bid must belong to the booking request, booking customer must match the request customer, booking provider must match the bid provider, currency/schedule must match the bid, and service amount must match the accepted bid amount.

## Payment status and ledger model after Ticket 7A

- `payments.status` remains the physical column name for compatibility, but is now constrained as the payment status with allowed values: `pending`, `checkout_created`, `paid`, `failed`, `expired`, `cancelled`, `partially_refunded`, and `refunded`.
- `payments.release_status` is separate from payment status with allowed values: `not_applicable`, `pending`, `paused`, `eligible`, `released`, and `cancelled`. Ticket 7A does not implement real payout release.
- `payment_events` records trusted payment state events with payment/booking references, safe amount/currency metadata, provider event/idempotency references, actor/source, metadata, and `occurred_at`.
- `payment_events` is append-only: no frontend SELECT/INSERT/UPDATE/DELETE, no direct service-role table access, and a trigger rejects UPDATE/DELETE.
- Trusted pending payment row creation writes an initial `intent_prepared` event with a deterministic idempotency key.
- `admin_record_payment_event(...)` is the current trusted internal/admin path for recording MVP payment events. It verifies platform-admin/server authority, updates constrained payment/release status where allowed, writes one ledger event, and writes an audit event.
- Duplicate provider event IDs or idempotency keys return the existing ledger event instead of creating duplicates.

## Refund request and ledger model after Ticket 7B

- `refund_requests` tracks booking-party refund requests with constrained statuses: `requested`, `under_review`, `approved`, `rejected`, `cancelled`, `processing`, `succeeded`, and `failed`.
- Customers request refunds only for their own booking payment through `customer_request_refund(...)`.
- Providers request refunds only for their own booking payment through `provider_request_refund(...)`.
- Frontend users cannot directly insert/update/delete refund workflow rows.
- Admin/server decisions require `public.is_platform_admin()` or trusted service context plus a non-empty reason.
- Trusted admin functions include `admin_mark_refund_under_review(...)`, `admin_approve_refund(...)`, `admin_reject_refund(...)`, and `admin_record_refund_outcome(...)`.
- `admin_record_refund_outcome(...)` is manual/sandbox outcome recording only. It does not call a live payment provider and records metadata that real money did not move.
- Refund amount validation prevents zero/negative refunds, refunds above the payment amount, and requests above the remaining refundable amount.
- Successful manual/sandbox outcomes update `payments.refunded_minor` and move payment status to `partially_refunded` or `refunded`.
- Every trusted refund state change writes a `refund_events` row and an `audit_events` row.
- Successful refund outcomes that affect payment state also write a `payment_events` row.
- `refund_events` is append-only and not frontend-readable or frontend-writable.

## Cash payment policy after Ticket 7C

- MVP policy decision: cash payments are explicitly disabled.
- `payments.payment_method` is required and defaults to `platform_online_pending`.
- Allowed MVP `payment_method` values are:
  - `platform_online_pending`
  - `platform_online`
  - `sandbox_online`
  - `manual_sandbox_online`
- Rejected cash/off-platform markers include `cash`, `off_platform_cash`, `cash_selected`, `customer_cash_confirmed`, `provider_cash_confirmed`, `cash_confirmed`, `cash_disputed`, `cash_cancelled`, and `cash_unverified`.
- `customer_select_cash_payment(...)` and `provider_select_cash_payment(...)` exist only as explicit policy markers and always raise: `Cash payments are disabled for MVP.`
- Cash cannot be used to mark payments as paid/refunded/released, create payout-release-like payment events, or bypass the Ticket 7A/7B payment and refund ledgers.
- Ticket 7C deliberately does not implement customer cash confirmation, provider cash confirmation, admin cash override, cash dispute workflow, payout release, live payment provider integration, real webhooks, or UI.

## Payout release controls after Ticket 7D

- Ticket 7D implements internal/manual-sandbox payout release controls only. It does not execute real provider bank payouts.
- New `payments` release-control fields are server/admin controlled:
  - `release_paused_at`
  - `release_paused_by`
  - `release_pause_reason`
  - `release_hold_until`
  - `release_eligible_at`
  - `release_provider_reference`
  - `release_idempotency_key`
- Trusted functions:
  - `admin_pause_payment_release(...)`
  - `admin_resume_payment_release(...)`
  - `admin_mark_release_eligible(...)`
  - `admin_record_payout_release(...)`
- Release is blocked unless payment is paid or partially refunded, booking is completed, payment method is platform online/sandbox, provider is active/verified/approved, no active refund exists, no active dispute exists, release is not paused, and the releasable amount is greater than zero.
- Full refunds, active refunds, active disputes, suspended providers, unapproved providers, unverified providers, and cash/off-platform methods block release.
- Pause/resume/eligibility/release recording functions require platform-admin/trusted-server authority, non-empty reason, idempotency key, and row locks.
- Every trusted release action writes `payment_events` and `audit_events`.
- `admin_record_payout_release(...)` records manual/sandbox internal release state only and includes metadata that no live provider payout was executed.

## Mock hosted checkout after Ticket 7E

- Ticket 7E implements a mock/sandbox hosted-checkout contract only. It does not process real cards, EFTs, instant EFTs, bank logins, wallet payments, signed webhooks, or live provider calls.
- `payments.checkout_url`, `payments.checkout_expires_at`, and `payments.checkout_idempotency_key` are server-controlled safe checkout reference fields.
- `customer_create_mock_checkout_session(...)` can be executed only by the booking customer for their own pending payment.
- Providers, unrelated users, and normal users cannot create checkout sessions for customer payments.
- Checkout creation rejects paid, refunded, failed, cancelled, expired, cash, or off-platform payments.
- Checkout creation sets `payments.status = checkout_created`, assigns deterministic `mock_checkout_...` references, writes `payment_events`, and writes `audit_events`.
- `admin_record_mock_payment_outcome(...)` is admin/trusted-server only and records mock `paid` or `failed` outcomes with `real_money_moved = false`.
- Mock paid/failed outcomes write `vendor_events`, `payment_events`, and `audit_events`, and are idempotent by provider event ID or idempotency key.
- Failed-after-paid is safely rejected/ignored without regressing payment status; paid-after-refunded is rejected.
- `validate_payment_provider_mode(...)` fails closed for production + `mock`.
- Mock mode remains local/CI/sandbox only until a real hosted-checkout provider and signed webhook handler are implemented.

## Mock/sandbox webhook processing after Ticket 8A and Ticket 8B

- Ticket 8A implements database-side processing for verified mock/sandbox payment webhook events only. Ticket 8B adds the mock/sandbox HTTP Edge Function route that verifies the deterministic mock signature against the exact raw body before calling Ticket 8A. These tickets do not add live provider webhooks, real webhook secrets, real card/EFT processing, or UI.
- `admin_process_verified_mock_payment_webhook(...)` requires platform-admin/trusted-server authority, runs as `SECURITY DEFINER`, has an explicit `search_path`, locks the matching `payments` row by `provider_reference`, validates safe event type and `payload_hash`, and rejects raw body/signature/secret/payment-credential metadata.
- Supported mock event types are `mock.checkout.created`, `mock.payment.paid`, `mock.payment.failed`, `mock.payment.expired`, and `mock.payment.cancelled`.
- `vendor_events` is the idempotency boundary on `(provider_name, provider_event_id)`. Duplicate provider event IDs do not duplicate `payment_events`; duplicate provider event IDs with a different `payload_hash` are audit-flagged without payment-state mutation.
- Safe webhook transitions can move `pending`/`checkout_created` to `checkout_created`, `paid`, `failed`, `expired`, or `cancelled` as appropriate. Failed-after-paid and checkout-created-after-paid write out-of-order ledger/audit events without downgrading. Paid-after-refunded is routed to manual-review ledger/audit without mutating payment status.
- Every accepted mock webhook processing outcome writes safe `vendor_events`, `payment_events`, and `audit_events` rows with `real_money_moved = false`.

## Remaining RLS risks after Tickets 2-6

- Public-description detection is conservative but not perfect. It blocks common street-number, unit/room, GPS, phone, and house/stand/erf patterns, but application UX and moderation should still warn users not to place exact addresses in public text.
- Booking status semantics are now aligned for the core marketplace flow (`scheduled`, `in_progress`, `completed` remain revealable), but future payment/refund/dispute tickets must confirm the final revealable status list.
- `consents` and `data_subject_requests` still have broad owner `FOR ALL` style policies from the initial schema. They require separate compliance/workflow tickets.
- Ticket 6 hardens the database state machine, but the production application still needs to be wired to these functions; until then the static prototype remains a demo.
- Ticket 7A hardens payment status constraints and the payment event ledger. Ticket 7B adds refund request and refund event ledger foundations. Ticket 7C disables cash for MVP. Ticket 7D adds internal/manual-sandbox payout release controls and blocker checks. Ticket 7E adds mock/sandbox hosted checkout and mock payment outcome recording only. Ticket 8A adds mock/sandbox database-side webhook processing and Ticket 8B adds mock/sandbox raw-body signature verification at the route. Live provider webhook transitions, real hosted checkout funding, real provider refund execution, real provider payout execution, reconciliation, and the full dispute workflow remain future tickets.
- Admin access is still intentionally server-mediated rather than broad direct admin RLS. A later staff/MFA ticket should formalise admin roles outside normal user-editable profile data.
