# LEKKADEALL RLS Policy Matrix

**Date:** 11 July 2026  
**Ticket:** Ticket 2 baseline RLS + Ticket 5 exact-address privacy + Ticket 6 marketplace state-machine update + Ticket 7A payment ledger foundation

## Public schema table inventory

The public schema currently contains 17 application tables:

1. `profiles`
2. `provider_profiles`
3. `service_categories`
4. `provider_services`
5. `service_requests`
6. `bids`
7. `bookings`
8. `payments`
9. `payment_events`
10. `vendor_events`
11. `identity_verifications`
12. `disputes`
13. `dispute_evidence`
14. `reviews`
15. `consents`
16. `data_subject_requests`
17. `audit_events`

## RLS status

Before Ticket 2, these public tables did **not** have RLS enabled in `001_initial_schema.sql`:

- `service_categories`
- `provider_services`
- `vendor_events`

After `003_repair_baseline_rls.sql`, the original public tables had RLS enabled. `007_payment_status_and_ledger.sql` adds `payment_events` with RLS enabled, so every current public application table above has RLS enabled.

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
| `service_requests` | High - customer request details and address material | S own safe request columns; I/U/D none directly; create/publish/cancel through `customer_create_draft_request(...)`, `customer_publish_request(...)`, `customer_cancel_request(...)`; exact address via controlled address functions | S eligible open safe columns/summaries; I/U/D none directly | Direct frontend access none | Trusted state-machine and admin/server functions only | Ticket 6 removed the broad owner `FOR ALL` mutation policy. `status`, `closes_at`, and workflow timestamps are trigger-protected and changed only through marketplace functions. |
| `bids` | High - commercial offers and bid state | S bids on own requests; I/U/D none | S own bids; I/U/D none directly; submit/withdraw through `provider_submit_bid(...)` and `provider_withdraw_bid(...)` | Direct frontend access none | Trusted state-machine functions only | Ticket 6 removed broad provider bid mutation. One accepted bid per request is enforced by partial unique index; acceptance/decline happens inside `customer_accept_bid(...)`. |
| `bookings` | High - booking parties, schedule, commercial amounts | S party only; I/U/D none; completion confirmation through `customer_confirm_completion(...)` after `in_progress` | S party only; I/U/D none; progress/completion through `booking_mark_in_progress(...)` and `provider_confirm_completion(...)` after `in_progress` | Direct frontend access none | Trusted state-machine functions only | Ticket 6 creates bookings only from accepted bids and validates request/bid/customer/provider/amount/schedule consistency by trigger. |
| `payments` | Critical - payment references/status, no card data | S party only; I/U/D none | S party only; I/U/D none | Direct frontend access none | Ticket 6 marketplace functions may prepare pending rows; Ticket 7A trusted admin/server function may update payment status/release status and append ledger events | Ticket 7A constrains `status` to safe MVP payment-status values and adds separate `release_status`. Frontend users cannot directly mutate payment/release/refund/provider fields. Real hosted checkout, refunds, cash policy, payout release, and webhooks remain future tickets. |
| `payment_events` | Critical - append-only payment status ledger | none | none | Direct frontend access none | Append through trusted `admin_record_payment_event(...)` / future signed webhook functions only | RLS enabled; frontend and direct service-role table privileges revoked; UPDATE/DELETE blocked by append-only trigger; idempotency protected by unique indexes on provider event ID and idempotency key. |
| `vendor_events` | Critical - webhook idempotency and raw-event metadata | none | none | Direct frontend access none | Server/webhook handlers only via `private.record_vendor_event(...)` or service role | RLS enabled; all frontend table privileges revoked; no frontend policies. |
| `identity_verifications` | Critical - identity verification result metadata | S own status only; I/U/D none | S own status only; I/U/D none | Direct frontend access none | Identity webhook/admin server actions only | Frontend insert/update/delete revoked. Raw identity evidence should remain outside app DB. |
| `disputes` | High - private case details | S party only; I own party dispute via existing policy; U/D none | S party only; I own party dispute via existing policy; U/D none | Direct frontend access none | Server/admin resolves and audits | Opening disputes still needs atomic payout-pause server action in a later ticket. |
| `dispute_evidence` | High - private evidence metadata | S party only; I currently uploaded_by only | S party only; I currently uploaded_by only | Direct frontend access none | Server/storage policies should control evidence uploads | Existing insert policy is still too broad because it does not require booking-party membership. |
| `reviews` | Medium/high - public trust content | S published; I only after participated completed booking | S published; I only after participated completed booking | Direct frontend moderation none | Server/admin moderation | Existing review insert still needs subject derivation and moderation hardening. |
| `consents` | High - compliance evidence | S/I/U/D own via existing policy | S/I/U/D own via existing policy | Direct frontend access none | Server should preserve consent evidence | Existing broad owner mutation remains a compliance risk; future ticket should make consent evidence append-oriented. |
| `data_subject_requests` | High - POPIA workflow | S/I/U/D own via existing policy | S/I/U/D own via existing policy | Direct frontend access none | Server/admin workflow processing | Existing owner mutation allows users to change workflow status; future ticket should restrict status fields. |
| `audit_events` | Critical - privileged action log | none | none | Direct frontend access none | Append through trusted private function only | `audit_events_append_only` blocks UPDATE/DELETE; frontend privileges revoked. |

## Immediate baseline policy decisions

- `vendor_events`: no frontend read/write access.
- `vendor_events`: service role may write through `private.record_vendor_event(...)`, which is idempotent on `(provider_name, provider_event_id)`.
- `service_categories`: read-only active categories for frontend; all mutation server/admin-only.
- `provider_services`: authenticated read of active approved-provider services; owner mutation only for approved providers.
- `audit_events`: no frontend access; append-only through trusted function.
- `identity_verifications`: owner read only; no frontend insert/update/delete.
- `payment_events`: no frontend direct read/write access; append-only through trusted payment/admin/webhook functions.

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

- `service_requests`: `draft -> open -> awarded|cancelled|expired`. Customers create drafts, publish drafts, and cancel draft/open requests through trusted functions. Direct frontend insert/update/delete is revoked and workflow fields are protected by trigger.
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

## Remaining RLS risks after Tickets 2-6

- Public-description detection is conservative but not perfect. It blocks common street-number, unit/room, GPS, phone, and house/stand/erf patterns, but application UX and moderation should still warn users not to place exact addresses in public text.
- Booking status semantics are now aligned for the core marketplace flow (`scheduled`, `in_progress`, `completed` remain revealable), but future payment/refund/dispute tickets must confirm the final revealable status list.
- `consents` and `data_subject_requests` still have broad owner `FOR ALL` style policies from the initial schema. They require separate compliance/workflow tickets.
- Ticket 6 hardens the database state machine, but the production application still needs to be wired to these functions; until then the static prototype remains a demo.
- Ticket 7A hardens payment status constraints and the payment event ledger. Real hosted checkout funding, cash handling, refunds, payout release, dispute-aware release blocking, reconciliation, and signed vendor webhook transitions remain future tickets.
- Admin access is still intentionally server-mediated rather than broad direct admin RLS. A later staff/MFA ticket should formalise admin roles outside normal user-editable profile data.
