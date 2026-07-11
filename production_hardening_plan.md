# LEKKADEALL Production Hardening Plan

**Audit date:** 9 July 2026  
**Scope reviewed:** `launch_gap_report.md`, `outputs/marketplace-production-foundation/architecture.md`, `outputs/marketplace-production-foundation/supabase/migrations/001_initial_schema.sql`, `outputs/marketplace-production-foundation/src/integrations/contracts.ts`, and the static prototype in `outputs/potchly-prototype/index.html` / `outputs/potchly-prototype/app.js`.

## Current production readiness verdict

**NO-GO for production, live payments, collection of identity documents, or public customer/provider onboarding.**

The repository is a useful foundation, but it is not yet a production-ready MVP. The current app is a static browser prototype using hard-coded data and `localStorage`. The Supabase schema and integration contracts show the right direction, but the security-critical paths are not executable yet and several current RLS policies are unsafe.

The highest priority is to harden the database, RLS model, server-side state transitions, webhooks, payments/refunds, disputes, and admin/audit workflows before adding cosmetic features.

## Critical blockers

1. **Self-role escalation is possible.**  
   `profiles` allows users to update their own full row, including `role` and `account_status`.

2. **Provider self-verification and self-approval are possible.**  
   `provider_profiles` lets providers update compliance/admin fields including `verification_status`, `bank_name_match`, `review_status`, `reviewed_by`, and `reviewed_at`.

3. **RLS is not enabled on every public table.**  
   `service_categories`, `provider_services`, and `vendor_events` are public-schema tables without RLS enabled.

4. **Exact-address privacy was not enforceable in the initial schema; Ticket 5 now adds the database repair.**  
   `004_exact_address_privacy.sql` and `005_ticket_5_address_privacy_hardening.sql` move exact address ciphertext into `private.service_request_addresses`, bind private addresses to the owning customer, block direct writes to the deprecated public address column, add a safe provider open-request summary RPC, add conservative public-description address detection, and add audited customer/provider/admin address functions. Remaining launch work: run pgTAP locally/CI, wire the application to the safe functions, finalise encryption/key management, and align revealable booking statuses with the final booking state machine.

5. **Marketplace state transitions are partially server-controlled after Ticket 6.**  
   `006_marketplace_state_machine.sql` adds transactional database functions for draft creation, publication, cancellation, provider bid submission/withdrawal, bid acceptance, booking creation, in-progress marking, and two-party completion confirmation after `in_progress`. Remaining launch work: run pgTAP locally/CI, wire the production app to these functions, and complete payment confirmation, cancellation after booking, payout, refund, dispute, expiry-job, and webhook transitions.

6. **Payment, refund, and webhook handling are still not production-complete.**  
   Ticket 7A constrains payment status values, separates `release_status`, adds an append-only `payment_events` ledger, and adds an audited internal/admin payment-event function. Card/bank credentials are still not stored in the schema, which is good. Remaining production blockers: hosted-checkout adapter, signed webhook route, real provider idempotency/reconciliation, refund workflow/ledger, cash policy, payout release/freeze workflow, and dispute-aware release blocking.

7. **Disputes and evidence are not safely private or atomic.**  
   Opening a dispute does not pause release atomically. Evidence insertion only checks `uploaded_by`, not whether the uploader is a booking party.

8. **Audit logging is not operational or append-only.**  
   `audit_events` exists, but no trusted append function, trigger coverage, privilege model, or tamper test exists.

9. **Admin actions are only prototype UI.**  
   The admin screen is reachable from the static prototype and has no real auth, MFA, staff membership, least-privilege checks, or server-side action handlers.

10. **No production application/backend exists yet.**  
    There is no package manifest, app routes, API routes, Supabase client setup, server-only config module, CI, deployment config, or real frontend-to-backend integration.

## High-risk blockers

- Ticket 6 removes broad direct `service_requests` and `bids` workflow mutation for the core request/bid/booking path, but the production app still needs to call the new trusted functions instead of the static prototype/localStorage flow.
- Ticket 7A constrains `payments.status` to safe MVP payment-status values and updates the TypeScript `PaymentStatus` contract; live provider confirmation, refunds, cash handling, payout release, and webhooks are still not implemented.
- There is no dedicated `refunds` / `refund_events` table.
- Ticket 5 adds a dedicated private address table, audited reveal/admin access path, and conservative free-text address detection; encryption/decryption key management, retention rules, controlled location lists, and application integration still need production design.
- Reviews can target an unrelated `subject_id` as long as the reviewer participated in a completed booking.
- Consent and data-subject-request rows are user-controlled with broad `FOR ALL` policies, allowing users to mutate workflow/status evidence.
- Provider category/service management is not protected by ownership and approval checks.
- Vendor event storage is not protected from frontend access.
- Environment variables are only listed in `.env.example`; there is no validation, production fail-closed check, or secret scanning.
- Existing RLS tests have been started but are incomplete and likely red against the current schema, which is expected until policies are repaired.

## Medium-risk blockers

- The prototype still uses Potchly branding and hard-coded marketplace claims while the production marketplace is LEKKADEALL.
- Categories are hard-coded in the frontend and not sourced from the database.
- The prototype makes trust claims about verification, 2FA, audit logs, payment protection, ratings, provider counts, and response times that are not backed by real systems.
- There is no monitoring, alerting, backup/restore drill, incident response runbook, or POPIA operational process wired into the app.
- There is no production-ready storage policy for dispute evidence, profile avatars, provider portfolios, or verification-related documents.

## Ordered repair tickets

Note: this plan was drafted before the current execution-ticket numbering. The current completed/implemented-in-code sequence is Ticket 1 role escalation, Ticket 2 baseline RLS, and Ticket 5 exact-address privacy. Some older headings below are retained as roadmap items and should be renumbered during the next planning cleanup.

### Ticket 1 — Establish the security test harness and make red tests explicit

**Goal:** Turn security requirements into automated tests before weakening or replacing policies.

**Files likely affected:**
- `outputs/marketplace-production-foundation/supabase/tests/database/rls_policies.test.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/rls_test_seed.inc`
- `outputs/marketplace-production-foundation/supabase/tests/README.md`
- Future CI config

**Tests required:**
- Finish pgTAP RLS tests for bookings, private provider data, exact-address reveal, provider self-verification, audit immutability, admin-only updates, payments, and refunds.
- Add expected-failure notes for current known-bad policies until the repair migrations are written.
- Add local run instructions using `supabase test db`.

### Ticket 2 — Repair baseline RLS and privileged-column ownership

**Goal:** Ensure no frontend user can escalate role, self-verify, self-approve, or mutate server-controlled workflow fields.

**Files likely affected:**
- `outputs/marketplace-production-foundation/supabase/migrations/001_initial_schema.sql`
- New follow-up migration, preferably `002_security_hardening.sql`
- RLS test files

**Tests required:**
- Customer cannot change `profiles.role` or `account_status`.
- Provider cannot change `provider_profiles.verification_status`, `verification_reference`, `bank_name_match`, `review_status`, `reviewed_by`, or `reviewed_at`.
- Normal users cannot insert/update/delete `audit_events`.
- RLS is enabled on every public table exposed to frontend clients.
- `vendor_events` has no frontend-readable or frontend-writable policy.

### Ticket 3 — Add server-owned admin/staff model and audited admin actions

**Goal:** Move privileged authority out of user-editable profile rows.

**Files likely affected:**
- Supabase migrations
- New server/admin action layer
- Future admin route/components
- `audit_events` functions

**Tests required:**
- Only staff/admin users can approve, reject, suspend, or reinstate providers.
- Support users cannot perform payout/refund-only actions unless explicitly allowed.
- Every admin action writes exactly one audit event with actor, object, action, reason, and metadata.
- Admin action attempts by normal customer/provider users fail.

### Ticket 4 — Make audit logs append-only

**Goal:** Create a trusted audit append function and prevent tampering.

**Files likely affected:**
- Supabase migrations
- Server action modules
- RLS tests

**Tests required:**
- Normal users cannot create, update, or delete audit events.
- Admin/server actions can append audit events only through a trusted function.
- No role used by the frontend can update or delete existing audit rows.
- Critical state transitions produce audit rows.

### Ticket 5 — Isolate exact addresses and implement confirmed-booking reveal

**Goal:** Protect precise customer addresses before booking confirmation.

**Status update — 11 July 2026:** Implemented at the database/RLS layer by `004_exact_address_privacy.sql`, strengthened by `005_ticket_5_address_privacy_hardening.sql`, and covered by `exact_address_privacy.test.sql`. Keep this ticket open until tests pass locally/CI and the application uses only the safe functions.

**Files likely affected:**
- Supabase migrations
- New safe request view/RPC
- New address table or encrypted-address model
- Customer request creation route/action
- Provider request/bid route/action

**Tests required:**
- Providers can view open request suburb/city/category/time/description, but not precise address material.
- Unselected providers can never view precise address material.
- Selected provider can view precise address only after confirmed booking.
- Address reveal is audited.
- Customer can view/edit own address before publication through an allowed server action.

**Remaining follow-up tests/tasks:**
- Run `exact_address_privacy.test.sql` locally or in CI.
- Wire request-description validation errors into the production app UX so users understand why address-like public descriptions are rejected.
- Confirm the revealable booking-status list during the booking state-machine ticket.
- Wire frontend/backend request creation and provider booking screens to `customer_upsert_service_request_address(...)`, `list_provider_open_request_summaries(...)`, and `reveal_confirmed_booking_address(...)`.

### Ticket 6 — Implement request, bid, acceptance, and booking state machine

**Goal:** Replace direct table writes with transactional server functions.

**Status update — 11 July 2026:** Implemented at the database/RLS layer by `006_marketplace_state_machine.sql` and covered by `marketplace_state_machine.test.sql`. A verification pass tightened completion so it is only confirmable after `in_progress` and expanded booking/payment integrity coverage to 58 pgTAP assertions. Keep this ticket open until the new pgTAP test passes locally/CI and the production application uses only the trusted functions for request creation, publishing, bidding, acceptance, booking progress, and completion.

**Files likely affected:**
- Supabase migrations
- Server action/RPC modules
- Customer request screens
- Provider bidding screens
- Booking screens

**Tests required:**
- Customer can create draft request and publish only their own request.
- Approved provider can bid only on open eligible requests.
- Provider cannot bid if unverified, unapproved, suspended, outside category, or after closing time.
- Customer can accept only a valid bid on their own open request.
- Accepting one bid atomically declines/locks competing bids and creates a booking/payment intent.
- Mismatched request/bid/customer/provider records are rejected.
- Duplicate accept calls are idempotent.

**Implemented database functions:**
- `customer_create_draft_request(...)`
- `customer_publish_request(...)`
- `customer_cancel_request(...)`
- `provider_submit_bid(...)`
- `provider_withdraw_bid(...)`
- `customer_accept_bid(...)`
- `booking_mark_in_progress(...)`
- `customer_confirm_completion(...)`
- `provider_confirm_completion(...)`

**Remaining follow-up tests/tasks:**
- Run `marketplace_state_machine.test.sql` locally or in CI.
- Wire the production frontend/backend to these functions; the static prototype still uses demo/localStorage behaviour.
- Add scheduled expiry jobs for stale requests and bids.
- Complete real payment funding, cash policy, refunds, payout release, cancellation after booking, disputes, and webhook-driven state transitions in later tickets.

### Ticket 7 — Harden payments, cash handling, refunds, and payout release

**Goal:** Keep payment credentials out of the database while tracking safe payment/refund state.

**Status update — 11 July 2026:** Ticket 7A implemented the payment foundation only. `007_payment_status_and_ledger.sql` constrains payment status values, adds separate `release_status`, creates the append-only `payment_events` ledger, records an initial `intent_prepared` event for trusted pending payment creation, adds idempotency uniqueness, and adds `admin_record_payment_event(...)` for audited internal/admin payment state changes. It deliberately does not implement live payment-provider integration, refunds, cash workflow, payout release, or real webhook handlers.

**Files likely affected:**
- Supabase migrations
- `outputs/marketplace-production-foundation/src/integrations/contracts.ts`
- New payment adapter modules
- Payment/booking UI
- Webhook handlers

**Tests required:**
- Payment records are visible only to booking parties and authorised staff.
- Unrelated users cannot view payment records.
- Normal users cannot mutate payment status, release state, or refund totals.
- Invalid payment status values are rejected by constraints.
- Trusted internal/admin payment events are append-only and idempotent.
- Refunds require trusted server/admin action and idempotency key.
- Cash/off-platform bookings are clearly marked as unprotected or blocked, depending on launch policy.
- Payout release cannot occur while a dispute is open or release is paused.
- Card/bank credential fields do not exist in public tables.

**Implemented in Ticket 7A:**
- constrained MVP payment-status values on `payments.status`
- separate `payments.release_status`
- `payments.paid_at`
- append-only `payment_events`
- automatic initial `intent_prepared` ledger event on trusted payment creation
- idempotency indexes for provider event ID and idempotency key
- audited `admin_record_payment_event(...)`
- `payments_ledger.test.sql`

**Remaining follow-up tasks:**
- Integrate a hosted payment provider through the vendor-neutral contract.
- Add sandbox/mock checkout adapter behaviour.
- Add signed/idempotent webhook routes.
- Add reconciliation from provider lookup.
- Add cash payment policy/workflow.
- Add refund request/refund event workflow.
- Add payout release/freeze rules and dispute-aware release blocking.

### Ticket 8 — Implement signed, idempotent vendor webhook handling

**Goal:** Make payments, identity, and messaging vendor-neutral but production-safe.

**Files likely affected:**
- New server API routes for webhooks
- `src/integrations/contracts.ts`
- New mock/sandbox adapters
- `vendor_events` schema and policies
- Reconciliation worker/runbook

**Tests required:**
- Invalid signatures are rejected.
- Duplicate webhook event IDs are ignored/idempotent.
- Out-of-order events do not corrupt state.
- Raw payload hashes are stored without leaking secrets.
- Reconciliation can correct stale internal state using vendor lookup.
- Production startup fails if provider is `mock` or required secrets are missing.

### Ticket 9 — Secure identity verification and provider approval

**Goal:** Prevent providers from activating themselves and minimise identity data held by LEKKADEALL.

**Files likely affected:**
- Supabase migrations
- Provider onboarding screens
- Identity adapter modules
- Admin review screens/actions
- Consent records

**Tests required:**
- Provider can start a hosted verification session but cannot set the result.
- Identity webhook can update server-owned verification result after signature validation.
- Human/admin review is required before public provider approval.
- Rejected/suspended providers cannot bid.
- Raw identity evidence is not stored in the application database.
- Consent version and timestamp are recorded before verification starts.

### Ticket 10 — Secure disputes, evidence, and payout pause

**Goal:** Keep disputes private and make opening a dispute atomically pause release.

**Files likely affected:**
- Supabase migrations
- Dispute creation/action modules
- Evidence upload/storage policies
- Admin/support dispute screens
- Payment pause/release modules

**Tests required:**
- Only booking parties can open a dispute.
- Opening a dispute creates one case, updates booking status, pauses payment release, and writes an audit event in one transaction.
- Only booking parties and authorised staff can read disputes/evidence.
- Users cannot upload evidence for disputes unrelated to them.
- Evidence upload requires signed storage paths, type/size checks, and malware-scan workflow.
- Resolution/refund/release actions are admin-only and audited.

### Ticket 11 — Repair reviews and public provider discovery

**Goal:** Ensure public trust signals are real, derived, and safe.

**Files likely affected:**
- Supabase migrations
- Review creation RPC/action
- Provider discovery view
- Frontend provider cards

**Tests required:**
- Reviews can be created only after completed/payout-released bookings.
- Reviewer can review only the other party in that booking.
- One review per side per booking.
- Moderation status is server/admin-controlled.
- Public provider cards show only approved providers and safe aggregate ratings.

### Ticket 12 — Build production app shell with real auth and server-only config

**Goal:** Move from static prototype to a real deployable MVP application.

**Files likely affected:**
- New package/build files
- New app routes/components
- Supabase client/server modules
- Environment config validation
- `.gitignore`
- Deployment config

**Tests required:**
- Registration/login/logout/session handling work for customer and provider accounts.
- Server-only secrets cannot be bundled into frontend code.
- Production startup fails when required env vars are missing or any provider is set to `mock`.
- Anonymous users cannot access protected customer/provider/admin pages.
- Admin pages require staff membership and MFA policy.

### Ticket 13 — Replace prototype claims with live data or explicit pilot labels

**Goal:** Avoid misleading users during recruitment and pilot testing.

**Files likely affected:**
- `outputs/potchly-prototype/index.html`
- `outputs/potchly-prototype/app.js`
- Future production frontend routes/components
- Brand/config files

**Tests required:**
- No unsupported production claims appear in the recruitment build.
- Demo-only data is clearly labelled as demo/pilot data.
- LEKKADEALL branding is consistent.
- Provider counts, ratings, response times, protected balances, and audit claims come from real data or are removed.

### Ticket 14 — Add operational launch controls

**Goal:** Prepare for a controlled South African MVP launch, not just code deployment.

**Files likely affected:**
- `README.md`
- `architecture.md`
- New runbooks
- CI/deployment config
- Legal/policy documents

**Tests required:**
- Backup/restore drill documented and tested.
- Monitoring and security alerts configured.
- Secret scanning and dependency checks run in CI.
- Incident response, data-subject request, refund, dispute, and provider appeal runbooks exist.
- POPIA notices, terms, vendor operator agreements, and provider agreements are lawyer-reviewed before launch.

## Definition of Done for production-ready MVP

LEKKADEALL is production-ready for a controlled MVP only when all of the following are true:

- Supabase RLS is enabled on every frontend-exposed public table and all critical negative/positive RLS tests pass.
- No user can change their own role, verification, approval, payout, payment, refund, dispute, or audit state directly.
- All sensitive marketplace transitions happen through trusted server-side functions/actions with validation, idempotency, and audit logging.
- Exact customer address data is isolated and revealed only to the selected provider after confirmed booking.
- Payment credentials never enter the app database; only vendor references, statuses, and reconciliation metadata are stored.
- Webhooks are signed, idempotent, replay-resistant, and reconciled.
- Refunds and payout releases are server/admin-controlled, dispute-aware, and audited.
- Provider onboarding requires hosted verification plus human/admin approval before providers can bid publicly.
- Disputes and evidence are private to booking parties and authorised staff.
- Admin access is separated from normal app access, protected by staff membership and MFA, and least-privilege permissions are enforced.
- CI runs schema, RLS, unit, webhook, integration, and key end-to-end tests before deployment.
- Production config fails closed if secrets are missing or mock providers are enabled.
- POPIA/legal documents, vendor agreements, provider agreements, support processes, monitoring, backups, and incident response are complete enough for a controlled pilot.

## Immediate next step

Continue with the next security-hardening ticket only after `role_escalation.test.sql`, `baseline_rls.test.sql`, `exact_address_privacy.test.sql`, and `marketplace_state_machine.test.sql` pass locally or in CI.
