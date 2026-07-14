# Ticket 9 Planning Document — LEKKADEALL MVP Frontend and Admin Dashboard

## Goal

Plan the customer, provider, and admin interfaces for the LEKKADEALL MVP without implementing UI or changing the secured database foundation.

This plan separates:

- screens that can use the CI-verified marketplace and mock/sandbox payment foundation from Tickets 1–8B;
- screens that require additional backend hardening before they can be implemented safely; and
- screens that must remain unavailable until a real marketplace-capable payment provider is confirmed and proven in sandbox.

## Planning-only status

This document is planning-only.

Do not implement frontend or admin UI under this ticket. Do not add or change payment-provider adapters, payment webhooks, credentials, migrations, tests, RLS policies, database functions, or production configuration.

The current provider decision remains **no real payment provider ready for selection**. Peach Payments is not suitable for the LEKKADEALL marketplace model because the vendor confirmed that it does not support marketplace. Stitch and TradeSafe remain conditional candidates; unresolved provider capabilities remain **needs vendor confirmation**.

## MVP interface principles

- The frontend is a client of the existing trusted database functions; it must not recreate marketplace state transitions in browser code.
- RLS and column grants remain the security boundary. Hidden controls and route guards improve UX but do not grant authority.
- Every screen must render only data the signed-in user is authorised to read.
- Exact address, identity, payment, refund, dispute, payout, and audit information must be minimised.
- Mock/sandbox payment state must be visibly labelled and must never be presented as proof that real money moved.
- Cash and off-platform payment options remain disabled for MVP.
- Features without a safe backend action remain disabled or omitted; the frontend must not work around missing functions with direct table writes.
- Production admin access must use a dedicated staff/MFA/least-privilege model before launch. The current `profiles.role = 'admin'` protection is a hardened interim database authority, not the final staff-access design.

## 1. Customer user journey

### A. Account and profile

1. Register or sign in through Supabase Auth.
2. Complete the safe customer profile fields: display name, phone, suburb, city, and avatar path.
3. See account status and a clear support path if the account is suspended or restricted.
4. Review required notices and consent records when the future consent flow is hardened.

The UI must never allow the customer to edit `role`, `account_status`, provider verification, provider review, identity verification, payment, refund-decision, release, dispute-resolution, or audit fields directly.

### B. Create and publish a service request

1. Start a draft by choosing an active service category and entering approximate location, description, schedule, and budget.
2. Save the exact address separately through the controlled address function while the request remains a draft.
3. Show a warning that the public description, suburb, and city must not contain an exact address, phone number, GPS coordinate, unit/room number, or other sensitive location detail.
4. Publish the draft through the trusted publish function.
5. If publication is rejected by the address-risk detector, show a specific correction message without echoing sensitive text into logs.
6. Allow cancellation only while the current state machine permits it.

### C. Review bids and accept a provider

1. View bids only for the customer's own requests.
2. Compare provider identity/display information, amount, schedule, message, and permitted service information.
3. Accept one valid bid through the trusted acceptance function.
4. On success, show the created booking and pending payment record.
5. Refresh from the database after mutation; do not infer successful state from a button click alone.

### D. Mock checkout and booking progress

1. For local/CI/sandbox demonstration only, let the booking customer create a mock checkout session for their own pending payment.
2. Open only the safe mock checkout URL/reference produced by the trusted function.
3. Show payment status as `Mock/sandbox — no real money moved`.
4. Show the booking timeline from scheduled to in progress to completed.
5. Allow completion confirmation only after the booking is in progress and only through the trusted completion function.

The customer interface must not expose a real card form, CVV field, bank-login form, cash option, manual “I paid” button, payment-status override, payout control, webhook trigger, or provider secret.

### E. Refund and support

1. Display the customer's payment and permitted refund-request status for the customer's own booking.
2. Allow the customer to submit a refund request through `customer_request_refund(...)` when the database permits it.
3. Clearly distinguish a requested/approved refund from a completed refund.
4. In mock/sandbox mode, a completed outcome must say that no real money moved.
5. Provide a support contact/case entry point, but do not claim that the current database has a complete support-case workflow.
6. A customer dispute-opening flow must wait for the atomic dispute-and-release-pause backend described under blocked screens.

## 2. Provider user journey

### A. Account and provider profile

1. Register or sign in through Supabase Auth.
2. Complete safe profile and provider-business fields.
3. View provider onboarding status: account status, verification status, and review status.
4. See clear pending, approved, rejected, or suspended messaging.
5. Approved providers can manage their own service offerings where current RLS permits it.

The provider cannot approve or verify themselves. The UI must not write privileged provider fields or identity-verification results.

### B. Verification and approval

The MVP can show a read-only onboarding checklist and current status. A production verification-start screen, hosted identity session, consent capture, webhook result, evidence review, and provider appeal flow must wait for the secure identity-verification ticket and vendor selection. Raw identity evidence must never be stored in the application database or exposed in general admin UI.

### C. Find work and bid

1. Approved, active, verified providers view open work through `list_provider_open_request_summaries(...)`.
2. Results show only safe approximate location and request summary fields—never customer ID or exact address.
3. The provider submits a bid through `provider_submit_bid(...)`.
4. The provider can withdraw a submitted bid through `provider_withdraw_bid(...)` when allowed.
5. Unapproved, unverified, or suspended providers see an eligibility explanation and cannot browse or bid through a bypass route.

### D. Booking delivery and address reveal

1. The selected provider sees only their own bookings.
2. Exact address reveal is a deliberate action available only when `reveal_confirmed_booking_address(...)` authorises it for a revealable booking state.
3. The UI should warn that each successful reveal is audited.
4. The provider can mark a booking in progress through `booking_mark_in_progress(...)` when authorised.
5. The provider can confirm completion through `provider_confirm_completion(...)` only after the booking is in progress.

The exact address must not be cached in analytics, error reporting, notifications, browser persistence, search indexes, or general page state longer than needed.

### E. Earnings, refunds, and payout state

1. Show only the provider's permitted booking/payment summary.
2. During the mock phase, label payment and release information as simulated/internal status.
3. Allow a provider refund request through `provider_request_refund(...)` when permitted.
4. Show whether release is pending, paused, eligible, cancelled, or recorded as mock/manual sandbox.
5. Do not call a release “paid out” unless a future real provider integration and reconciliation prove that funds moved.

Provider bank onboarding, beneficiary verification, real balance, real settlement dates, real payout initiation, and real payout history must wait for provider confirmation and implementation.

## 3. Admin user journey

### A. Secure staff entry

1. Sign in through a separate admin route/application boundary.
2. Require active authorised staff status and MFA before production use.
3. Deny by default if the staff model, MFA assertion, or required server configuration is missing.
4. Show only modules allowed by least-privilege staff permissions.
5. Require a non-empty reason for sensitive actions and show the resulting safe audit reference.

Until a dedicated staff/MFA/permission model exists, the production admin dashboard is not launch-ready. The existing `is_platform_admin()` and admin functions can support controlled development and future server actions, but should not be treated as the complete staff security model.

### B. Operations overview

The dashboard home should show safe counts and queues, not unrestricted table dumps:

- provider reviews awaiting action;
- accounts restricted or suspended;
- bookings by operational state;
- mock/sandbox payments needing review;
- refund requests by state;
- payments with release paused or blockers;
- disputes requiring attention once the full workflow exists;
- webhook/hash mismatch or unknown-event alerts from safe operational telemetry, not raw webhook bodies;
- aging queues and SLA warnings.

Aggregate/admin query endpoints may need a future backend ticket. The frontend must not gain broad table access merely to build dashboard counts.

### C. Provider verification and approval

1. Open a provider review record containing only necessary profile, business, verification-status, and consent metadata.
2. Never display raw identity evidence from the application database.
3. Record verification and review decisions through audited trusted functions.
4. Require a reason for rejection, suspension, or reversal.
5. Keep provider verification status and identity-verification status visibly distinct until a later ticket defines the source of truth and reconciliation rule.

Existing interim actions include `admin_set_provider_verification_status(...)` and `admin_set_provider_review_status(...)`. A complete production workflow must wait for hosted identity verification, signed identity webhooks, consent evidence, staff permissions/MFA, and a defined source of truth.

### D. Refund operations

1. View refund requests and relevant booking/payment context through a least-privilege server query.
2. Move a request under review with `admin_mark_refund_under_review(...)`.
3. Approve or reject through `admin_approve_refund(...)` or `admin_reject_refund(...)` with a required reason.
4. In local/sandbox demonstrations only, record the simulated outcome through `admin_record_refund_outcome(...)` and show `No real money moved`.
5. Do not expose a production “refund completed” action until a real provider refund API, signed webhook, and reconciliation path exist.

### E. Release holds and payout operations

1. Display release status and blocker reasons for the selected payment.
2. Pause release through `admin_pause_payment_release(...)` with reason and idempotency key.
3. Resume through `admin_resume_payment_release(...)` only after reviewing blockers.
4. Mark eligibility through `admin_mark_release_eligible(...)` only when the database confirms every release condition.
5. In local/sandbox demonstrations only, use `admin_record_payout_release(...)` to record a manual/sandbox outcome and visibly state that no provider bank payout occurred.
6. Real payout execution and “funds sent” status must wait for a confirmed provider, signed payout webhooks, lookup, and reconciliation.

### F. Disputes

A complete dispute admin module is blocked. The current schema has `disputes` and `dispute_evidence`, and release blockers recognise active disputes, but the required atomic workflow is not implemented.

Before the UI is enabled, a future backend ticket must ensure:

- only booking parties can open a dispute;
- opening a dispute atomically creates one case, updates related state as designed, pauses release, and writes an audit event;
- only booking parties and authorised staff can read the case/evidence;
- evidence upload uses constrained signed paths, file type/size checks, and malware scanning;
- resolution, refund, and release decisions are authorised and audited;
- dispute evidence cannot be accessed through broad storage URLs or frontend table writes.

The frontend must not implement a temporary direct insert into `disputes` or `dispute_evidence`.

### G. Account and support actions

1. View the minimum customer/provider context necessary to handle a case.
2. Suspend or reactivate an account only through `admin_set_account_status(...)` with a documented reason.
3. Treat role changes through `admin_set_user_role(...)` as exceptional high-privilege actions, not routine support tools.
4. Use `admin_get_service_request_address(...)` only for an authorised support purpose with a required reason; every access is audited.
5. Avoid impersonation. If future support impersonation is approved, it requires a separate design with explicit consent, time limits, banners, and audit trails.
6. Never expose audit-event mutation, vendor-event mutation, payment overrides, service-role credentials, secrets, raw webhook bodies, or raw identity/payment credentials.

## 4. Pages and screens needed for MVP

### Shared and public

| Page/screen | Purpose | Readiness |
|---|---|---|
| Landing and service-category discovery | Explain marketplace and show active categories | Can be implemented against safe category reads |
| Register, sign in, password recovery, sign out | Supabase Auth session flow | Requires production auth/config hardening; no provider dependency |
| Access denied / suspended account | Safe route and account-status handling | Can be implemented |
| Privacy, terms, payment limitations, support | Required notices and contact routes | Content/legal review required |

### Customer

| Page/screen | Purpose | Readiness |
|---|---|---|
| Customer dashboard | Own requests, bids, bookings, payment/refund summaries | Can use existing own-row reads; aggregate endpoint design may be needed |
| Profile settings | Safe allow-listed profile edits | Can be implemented without privileged fields |
| New request wizard | Create draft and exact address separately | Can use existing trusted functions |
| Request detail | View own request state and cancellation action | Can use existing state machine |
| Bid comparison | Compare and accept one bid | Can use existing trusted acceptance function |
| Booking detail/timeline | Show booking, completion controls, safe payment state | Can use existing foundation |
| Mock checkout status | Create/show mock checkout for local/CI/sandbox | Can use mock foundation only; never production mock mode |
| Refund request/status | Request and track internal refund workflow | Request/status can use existing foundation; real execution must wait |
| Open dispute/evidence | Create case and upload evidence | Blocked until full atomic dispute/evidence backend |
| Review provider | Submit a post-completion review | Wait until review workflow/moderation rules are hardened |

### Provider

| Page/screen | Purpose | Readiness |
|---|---|---|
| Provider dashboard | Own bids, bookings, simulated earnings/release states | Can use permitted data; mock labels required |
| Provider profile and services | Edit safe business fields and own approved services | Can use current safe paths/RLS |
| Verification/onboarding status | Read-only checklist and status | Status shell can be implemented; production verification flow blocked |
| Open request feed | Safe provider-facing request summaries | Can use `list_provider_open_request_summaries(...)` |
| Submit/withdraw bid | Controlled bid workflow | Can use existing trusted functions |
| Provider booking detail | In-progress/completion controls | Can use existing trusted functions |
| Exact-address reveal | Deliberate audited reveal for selected booking | Can use existing reveal function only when authorised |
| Refund request/status | Provider-initiated request and status | Can use existing request foundation; real execution must wait |
| Earnings/release status | Internal/mock release state | Can show simulated/internal status; real payout screen blocked |
| Bank/beneficiary onboarding | Real provider payout destination | Blocked until provider and compliance model confirmed |
| Dispute/evidence | Participate in a case | Blocked until full dispute/evidence backend |

### Admin

| Page/screen | Purpose | Readiness |
|---|---|---|
| Staff sign-in and MFA | Secure admin entry | Blocked for production until dedicated staff/MFA model |
| Operations dashboard | Queues and safe metrics | Requires least-privilege aggregate/query endpoints |
| Provider review queue/detail | Verification and human approval | Interim functions exist; production flow blocked on identity/staff hardening |
| Account support detail | Suspend/reactivate, limited support context | Trusted account function exists; staff permissions/query design still required |
| Booking support detail | Inspect safe booking/request state | Requires least-privilege admin query design |
| Exact-address support reveal | Exceptional audited address access | Existing audited function available; staff/MFA gate required |
| Refund queue/detail | Review, approve, reject, record sandbox outcome | Internal workflow available; real provider execution blocked |
| Release hold queue/detail | Pause/resume/eligibility and sandbox record | Internal controls available; real payout execution blocked |
| Dispute queue/detail/evidence | Investigate and resolve disputes | Blocked until full dispute workflow and storage security |
| Payment event/reconciliation view | Safe ledger and mismatch review | Mock/internal view possible via server query; real reconciliation blocked |
| Audit search | Read-only investigation of audit events | Requires dedicated least-privilege staff query; never direct mutation |
| Role administration | Exceptional role management | Separate high-privilege permission/MFA design required |

## 5. Screens that can use mock payment status for now

The following screens may use the existing mock/sandbox database foundation in local development, CI, or an explicitly non-production sandbox:

- customer booking payment panel;
- mock checkout-session screen;
- customer booking timeline;
- provider booking and simulated earnings summary;
- customer/provider refund-request status;
- admin payment detail;
- admin refund queue and simulated outcome display;
- admin release-hold queue;
- admin simulated payout-release record;
- support view of safe payment/payment-event references;
- webhook test/demo status using safe normalized event metadata.

Every such screen must:

- display `Mock/sandbox — no real money moved` prominently;
- derive state from `payments`, `refund_requests`, and authorised server responses, not browser-local flags;
- never label `manual_sandbox_online` or a mock release event as real payment or payout;
- never appear when production provider mode is configured;
- never offer cash/off-platform confirmation;
- never call `admin_record_mock_payment_outcome(...)` or `admin_process_verified_mock_payment_webhook(...)` from an ordinary customer/provider client;
- keep mock webhook secrets and service-role access server-only.

## 6. Screens that must wait for real payment-provider confirmation

Do not implement or enable these as real-money screens until a marketplace-capable provider closes the Ticket 8C gates and a future implementation ticket passes sandbox verification:

- real hosted checkout launch and return flow;
- payment-method selection based on a real provider catalogue;
- “payment received” or real-money receipt/confirmation;
- provider/sub-merchant/beneficiary onboarding and bank-account verification;
- real provider balance, settlement, fee, reserve, or payout schedule;
- real refund initiation, refund completion, and refund receipt;
- real payout/release initiation and “funds sent” confirmation;
- chargeback/payment-dispute status sourced from a provider;
- payment/refund/payout reconciliation and mismatch correction;
- production payment incident and signed-webhook delivery monitoring;
- provider-specific support references or vendor escalation controls.

These screens require, at minimum, confirmed marketplace support, hosted checkout, ZAR, signed replay-resistant webhooks, unique event IDs, deterministic sandbox flows, lookup/reconciliation APIs, refund/payout APIs and events, provider onboarding rules, settlement terms, POPIA/DPA review, and incident support.

## 7. Supabase tables and functions already available from Tickets 1–8B

### Frontend-relevant tables

| Table | Intended interface use | Important restriction |
|---|---|---|
| `profiles` | Own safe profile and account/role status display | Privileged fields are guarded; frontend updates only allow-listed fields |
| `provider_profiles` | Provider business profile and public approved-provider information | Verification/review fields are admin/server controlled |
| `service_categories` | Active category discovery | Frontend read-only; admin mutation needs a future safe action |
| `provider_services` | Approved provider offerings | Owner management only under current approval/RLS rules |
| `service_requests` | Customer's own requests and safe workflow display | Direct workflow mutation is revoked/guarded; exact address is not stored here |
| `bids` | Customer/provider bid views | Use trusted submit/withdraw/accept functions for state changes |
| `bookings` | Booking timeline and party views | Direct workflow mutation is guarded |
| `payments` | Booking-party safe payment/release summary | Direct status/release mutation is denied |
| `payment_events` | Internal append-only payment ledger | No direct frontend access; expose only through a future safe server query if needed |
| `refund_requests` | Booking-party refund status | Creation/decisions/outcomes use trusted functions |
| `refund_events` | Internal append-only refund ledger | No direct frontend access |
| `vendor_events` | Webhook idempotency/safe provider-event metadata | No frontend access |
| `identity_verifications` | Own verification-status metadata | No frontend result mutation; raw evidence must remain outside app DB |
| `disputes` | Existing dispute case rows | Full safe atomic workflow is not implemented |
| `dispute_evidence` | Existing evidence metadata | Current insert model is not ready for MVP UI |
| `reviews` | Existing review rows | Creation/moderation workflow still requires hardening |
| `consents` | Existing consent rows | Broad owner mutation is a compliance risk; do not build final consent UI yet |
| `data_subject_requests` | Existing privacy-request rows | Broad owner mutation/workflow still requires hardening |
| `audit_events` | Append-only security/operation evidence | No frontend access or mutation; future staff query must be least privilege |

Exact addresses are stored in `private.service_request_addresses`, not in a frontend-facing public table. The frontend must use controlled functions and must never query the private table directly.

### Customer and marketplace functions

- `customer_create_draft_request(...)`
- `customer_upsert_service_request_address(...)`
- `customer_get_service_request_address(...)`
- `customer_publish_request(...)`
- `customer_cancel_request(...)`
- `customer_accept_bid(...)`
- `customer_confirm_completion(...)`
- `customer_request_refund(...)`
- `customer_create_mock_checkout_session(...)` — local/CI/sandbox only

### Provider functions

- `is_approved_provider(...)`
- `list_provider_open_request_summaries(...)`
- `provider_submit_bid(...)`
- `provider_withdraw_bid(...)`
- `reveal_confirmed_booking_address(...)`
- `booking_mark_in_progress(...)`
- `provider_confirm_completion(...)`
- `provider_request_refund(...)`

### Admin/trusted functions

- `is_platform_admin()` — hardened interim authority, not the final staff/MFA model
- `admin_set_user_role(...)`
- `admin_set_account_status(...)`
- `admin_set_provider_review_status(...)`
- `admin_set_provider_verification_status(...)`
- `admin_get_service_request_address(...)`
- `admin_record_payment_event(...)` — trusted internal/manual state recording, not live provider execution
- `admin_mark_refund_under_review(...)`
- `admin_approve_refund(...)`
- `admin_reject_refund(...)`
- `admin_record_refund_outcome(...)` — manual/sandbox only
- `admin_pause_payment_release(...)`
- `admin_resume_payment_release(...)`
- `admin_mark_release_eligible(...)`
- `admin_record_payout_release(...)` — manual/sandbox only
- `admin_record_mock_payment_outcome(...)` — mock/sandbox only
- `admin_process_verified_mock_payment_webhook(...)` — server route only after mock signature verification; never an admin-page/client RPC
- `validate_payment_provider_mode(...)` — production must fail closed for mock mode

### Missing backend capabilities that UI must not invent

- production staff membership, granular permissions, and MFA enforcement;
- secure hosted identity-verification session and signed result webhook;
- identity-verification source-of-truth/reconciliation model;
- atomic dispute opening, evidence security, resolution, and release pause workflow;
- hardened review creation and moderation;
- append-oriented consent evidence and controlled data-subject-request workflow;
- safe admin list/search/aggregate functions for dashboard queues;
- real checkout, refund, payout, webhook, lookup, and reconciliation integration;
- scheduled expiry/reconciliation/operations jobs;
- notification service and secure support-case workflow.

## 8. Frontend security rules

1. **Use trusted functions for workflow mutations.** Do not insert/update/delete request, bid, booking, payment, refund, release, verification, dispute, or audit state directly when a trusted action is required.
2. **Do not weaken RLS or grants for UI convenience.** Missing data means a safe server query/function must be designed and tested; it does not justify broad table access.
3. **Keep secrets server-only.** Never bundle the Supabase service-role key, webhook secrets, provider API keys, identity secrets, or admin credentials into browser code, static files, source maps, logs, or analytics.
4. **Treat route guards as UX only.** The database/server must independently authorise every read and mutation.
5. **Respect least privilege.** Customer, provider, support, verification reviewer, finance/refund, dispute, and role-admin capabilities should be separate.
6. **Do not trust client-supplied ownership or status.** Use `auth.uid()` and server/database relationships; never let the browser choose an actor, owner, provider, privileged status, or payment outcome.
7. **Protect exact addresses.** Use the controlled address functions, reveal only to the selected approved provider in an authorised booking state, and avoid telemetry/persistence leakage.
8. **Protect identity data.** Store/status-display only necessary verification metadata; no raw identity documents or biometric evidence in the public application database.
9. **Protect payment data.** No card, CVV, bank-login credential, raw provider payload, webhook signature, or webhook secret may enter application tables or frontend logging.
10. **Preserve append-only ledgers.** The UI never edits/deletes `audit_events`, `payment_events`, or `refund_events`, and never writes `vendor_events`.
11. **Fail closed.** Missing session, stale session, missing staff/MFA assertion, missing runtime config, unknown status, or rejected function call must deny the action and refresh trusted state.
12. **Use idempotency.** Disable duplicate submissions while pending, supply required idempotency keys for admin/refund/release operations, and safely handle retries/timeouts.
13. **Avoid optimistic security claims.** The UI may optimistically show a spinner, but must not announce accepted bids, payment, refund, release, address access, or verification until the trusted response confirms it.
14. **Sanitise output and uploads.** Escape user text, use strict content security policy, validate file types/sizes server-side, and do not render untrusted HTML.
15. **Minimise telemetry.** Exclude exact addresses, phone numbers, identity data, dispute evidence, secrets, raw webhook payloads, and payment-sensitive details from analytics and error reports.
16. **Label mock state.** Mock/sandbox status must be unmistakable and unavailable in production.
17. **Keep cash disabled.** Do not render a cash method, off-platform confirmation, or workflow that implies platform protection for cash.
18. **Audit sensitive admin actions.** Require reasons where supported and present safe audit references without exposing or mutating the audit ledger.

## 9. Admin actions required for MVP operations

| Area | Required action | Existing foundation | Production/UI gate |
|---|---|---|---|
| Provider verification | Review status, approve/reject/suspend provider | Admin verification/review functions exist | Hosted identity flow, source of truth, staff/MFA, consent and least-privilege queries still required |
| Account support | Suspend/reactivate account | `admin_set_account_status(...)` | Staff permissions, reason UX, safe case context and appeal/runbook required |
| Role administration | Exceptional authorised role change | `admin_set_user_role(...)` | Separate high-privilege permission and MFA; omit from routine support UI |
| Address support | Exceptional exact-address access | `admin_get_service_request_address(...)` | Required reason, staff/MFA, minimum display and no telemetry |
| Refund review | Mark under review, approve, reject | Trusted refund decision functions exist | Least-privilege queue/detail query and runbook required |
| Refund outcome | Record mock/manual sandbox outcome | `admin_record_refund_outcome(...)` | Real completion waits for provider API, signed webhooks and reconciliation |
| Release hold | Pause and resume | Trusted pause/resume functions exist | Reason, idempotency, blocker display, finance permission and audit confirmation |
| Release eligibility | Mark eligible after blockers clear | `admin_mark_release_eligible(...)` | Finance permission and safe blocker query required |
| Payout release | Record mock/manual sandbox release | `admin_record_payout_release(...)` | Real payout waits for provider onboarding, API, signed events and reconciliation |
| Disputes | Open/review/resolve case and control release | Tables and release blocker awareness exist | Full atomic dispute/evidence backend is required before UI |
| Payment support | View safe payment ledger and mismatch state | Append-only ledger exists | Safe staff query needed; no direct override or raw webhook access |
| Audit/support investigation | Search safe audit trail | Append-only audit ledger exists | Dedicated read-only, least-privilege query and retention/redaction rules needed |

Admin buttons must reflect authority and readiness:

- `Approve` is not `Verified`; show the distinct statuses.
- `Approve refund` is not `Refund completed`.
- `Mark release eligible` is not `Payout sent`.
- `Record sandbox outcome` is not evidence of real money movement.
- `Pause release` does not replace the missing atomic dispute-opening workflow.

## 10. Definition of done for a future implementation ticket

A future Ticket 9 implementation is complete only when all in-scope items below are implemented and verified without weakening Tickets 1–8B:

### Product and UX

- Customer and provider authentication, safe profile, request, bid, acceptance, booking, address, completion, and refund-request journeys work end to end against Supabase.
- Approved providers discover only safe open-request summaries and exact address reveal occurs only through the audited function in authorised booking states.
- Every mock payment/refund/release screen is prominently labelled and cannot appear in production.
- Blocked real-provider, identity, dispute, review, consent, and payout capabilities remain disabled or omitted until their backend gates are complete.
- Empty, loading, retry, timeout, conflict, stale-session, access-denied, suspended, and validation-error states are designed and accessible.
- Responsive and keyboard-accessible customer/provider interfaces pass agreed accessibility checks.

### Admin

- Production admin entry uses dedicated staff membership, MFA, least-privilege permissions, and server-side enforcement.
- Admin list/search/queue data comes from reviewed least-privilege server functions or endpoints, not broad table grants.
- Provider, account, address, refund, and release actions call only the authorised trusted functions and require reasons/idempotency where applicable.
- Real refund/payout completion controls are absent until provider integration is ready.
- Dispute UI remains absent until atomic dispute/evidence/release-pause controls are implemented and tested.
- Sensitive actions produce and display safe audit confirmation.

### Security and privacy

- No service-role key, provider credential, webhook secret, identity secret, or other server-only configuration appears in browser bundles, static assets, logs, source maps, or network responses.
- No direct frontend mutation path can change privileged role/account/provider status, workflow state, payment/refund/release state, dispute resolution, vendor events, or append-only ledgers.
- RLS negative tests and all existing Tickets 1–8B CI tests remain green.
- Exact addresses, identity metadata, dispute data, and payment-sensitive metadata are excluded from analytics and error telemetry.
- Production fails closed when mock provider mode or required secure configuration is invalid.
- Cash and off-platform payment flows remain unavailable.

### Testing required in the future implementation ticket

- component tests for status/action rendering and validation;
- integration tests proving each UI mutation calls the intended trusted function and handles denial safely;
- end-to-end customer request → bid acceptance → booking → mock checkout/status → completion flow;
- end-to-end provider discovery → bid → booking → authorised address reveal → completion flow;
- admin permission/MFA tests and negative tests for every sensitive module;
- tests proving unrelated customers/providers cannot see or mutate another party's data;
- tests proving unapproved/suspended providers cannot discover work or bid;
- tests proving mock state is labelled and production cannot enable mock UI;
- tests proving invalid/duplicate admin submissions remain safe and idempotent;
- bundle/secret scanning and telemetry redaction tests;
- accessibility, responsive-layout, and critical browser tests;
- full existing Deno webhook and pgTAP suite remains green.

### Documentation and operations

- Route, role, data-source, and trusted-action mappings are documented.
- Mock/sandbox limitations are documented for staff and testers.
- Support, provider-review, refund, release-hold, access-denial, and incident runbooks exist for every enabled admin action.
- No UI copy claims real payment protection, refund completion, or payout completion while the system remains mock/sandbox only.

## Explicit non-goals

This planning ticket does not:

- implement any customer, provider, or admin UI;
- select or integrate a real payment provider;
- add or call a real payment, refund, payout, or reconciliation API;
- add provider, identity, Supabase, or webhook credentials;
- change the existing mock/sandbox webhook route or database processor;
- add migrations, tests, RLS policies, database functions, storage policies, or Edge Functions;
- implement identity verification, disputes/evidence, reviews/moderation, consent hardening, or data-subject-request workflows;
- weaken role, RLS, address, state-machine, payment, refund, cash, payout-release, ledger, or webhook protections.
