# LEKKADEALL Production-Readiness Launch Gap Report

**Audit date:** 7 July 2026  
**Verdict:** **NO-GO for a production launch, live payments, or collection of identity documents.**  
**Current maturity:** Static demonstration prototype plus a database and integration design foundation.

## Scope and grading method

Reviewed:

- `outputs/marketplace-production-foundation/supabase/migrations/001_initial_schema.sql`
- `outputs/marketplace-production-foundation/src/integrations/contracts.ts`
- `outputs/marketplace-production-foundation/architecture.md`
- `outputs/marketplace-production-foundation/.env.example`
- `outputs/marketplace-production-foundation/README.md`
- All application UI and behaviour in `outputs/potchly-prototype/index.html` and `outputs/potchly-prototype/app.js`

There are no framework routes, components, API handlers, Supabase client, vendor adapters, package manifest, build pipeline, or test files in the repository. The application is a single static HTML page whose demo actions use browser `localStorage` or display a toast.

Status means:

1. **Fully implemented** - executable, authorised, persisted, error-handled, and tested end to end.
2. **Partially implemented** - some schema, contract, or prototype UI exists, but the production workflow is incomplete.
3. **Missing** - no executable implementation exists.
4. **Unsafe or unclear** - an implementation or design exists, but its current authorisation, privacy, integrity, or operating model is unsafe or ambiguous.

## Summary

| Status | Count |
|---|---:|
| Fully implemented | 0 |
| Partially implemented | 8 |
| Missing | 4 |
| Unsafe or unclear | 8 |

The highest-risk defects are:

1. Users can update their own `profiles.role`, creating a privilege-escalation path if the role is trusted by future server code.
2. Providers can update their own verification, bank-match, and review/approval fields.
3. `vendor_events`, `service_categories`, and `provider_services` do not have row-level security enabled.
4. No real authentication, booking transaction, payment integration, webhook handler, admin action, or audit writer exists.
5. Disputes do not atomically pause payout, and unrelated users can insert evidence against a dispute if they know its identifier.
6. There is no automated test coverage, including no negative RLS tests.

## Feature audit

### 1. Customer registration and profile - Partially implemented

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `outputs/potchly-prototype/index.html:28-32`; `app.js:52-63` | `authForm`, `otpForm` | Registration is a demo. It stores only a name in `localStorage`, uses the universal OTP `246810`, and creates no authenticated session or database profile. | Critical | Implement Supabase Auth registration, email/phone verification, login, logout, password reset, session handling, abuse throttling, and error states. |
| `001_initial_schema.sql:10-23,244-245` | `profiles`; `profile owner updates self` | No insert policy or `auth.users` trigger creates a profile. The update policy permits the owner to change every column, including `role` and `account_status`. | Critical | Add a secure `auth.users` profile-creation trigger; remove client write access to privileged columns; move roles/status to server-controlled claims or a private staff-membership table. |
| `index.html:58` | `profile` screen | Profile data and verification badges are hard-coded and are not tied to the logged-in user. | High | Build a protected profile route that reads and updates an allow-listed set of profile fields from Supabase. |

### 2. Provider registration and profile - Unsafe or unclear

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `index.html:50-56`; `app.js:85-92` | `joinForm`, `provider-verify`, provider dashboard | Onboarding stores only the provider name in `localStorage`. Services, business information, portfolio, location, availability, and payout details are not persisted. | High | Implement a staged provider application with draft persistence, service selection, secure portfolio storage, consent/version records, and server-side submission for review. |
| `001_initial_schema.sql:25-38,246-247` | `provider_profiles`; `provider owns provider profile` | There is no client insert path. More seriously, an existing provider can update `verification_status`, `verification_reference`, `bank_name_match`, `review_status`, `reviewed_by`, and `reviewed_at`. | Critical | Split provider-editable data from compliance/review data, or expose allow-listed RPCs; revoke direct writes to verification and approval fields. |
| `001_initial_schema.sql:49-56` | `provider_services` | No RLS or ownership policy protects provider service records. | Critical | Enable RLS and add policies/RPCs that allow approved providers to manage only their own service offerings. |

### 3. Provider verification status - Unsafe or unclear

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `contracts.ts:56-94` | `IdentityGateway`, `VerificationResult` | Interfaces are well scoped, but no vendor adapter, hosted verification session, callback route, webhook handler, retry, or deletion workflow exists. | High | Implement a mock adapter, then a sandbox identity adapter and signed webhook route with replay protection and reconciliation. |
| `001_initial_schema.sql:25-38,137-150,246-247` | `provider_profiles.verification_status`; `identity_verifications` | Verification status is duplicated across two tables and no source-of-truth or reconciliation rule is defined. A provider can self-edit the copy on `provider_profiles`. | Critical | Make `identity_verifications` server-owned; derive the public provider status from the latest verified result plus human approval; prevent provider updates. |
| `index.html:52-54`; `app.js:92` | `verifyDemo` | Clicking the button always passes the simulated verification. | High | Replace the simulation with a hosted vendor redirect/SDK flow and explicit pending, manual-review, rejection, appeal, and expiry states. |

### 4. Service categories - Unsafe or unclear

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `001_initial_schema.sql:40-56,230-242` | `service_categories`, `provider_services` | RLS is not enabled for either table. In a normal Supabase public-schema grant model, clients may be able to read or modify them directly. | Critical | Add a migration enabling RLS; allow public/authenticated reads of active categories only; restrict category mutation to audited admin server actions. |
| `index.html:34,50`; `app.js:4-14` | Category arrays and `<option>` lists | Categories are hard-coded in multiple places and are inconsistent (`Home cleaning` versus `Cleaning`, and some request categories are absent from the home screen). | Medium | Seed canonical categories in the database and make every customer/provider selector load the same active category source. |
| Repository-wide | Category administration | No seed file, moderation rule, restricted-category configuration, or admin workflow exists. | Medium | Add category seed data, lifecycle rules, risk flags, and audited admin management. |

### 5. Customer job/request posting - Partially implemented

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `index.html:34-36`; `app.js:65-72` | `requestForm` | Posting stores the request only in browser `localStorage`; no authenticated ownership, database insert, notification, moderation, or expiry occurs. | High | Implement `create_request` and `publish_request` server actions/RPCs with validation, rate limits, category checks, and notification dispatch. |
| `001_initial_schema.sql:58-73,248-249` | `service_requests`; `providers see open requests` | The open-request read policy applies without checking that the caller is an authenticated, approved provider and returns the complete row. | High | Publish a safe request view containing only permitted fields; require an authenticated approved provider for detailed access. |
| `001_initial_schema.sql:248` | `customer owns requests` (`FOR ALL`) | Customers can directly perform every operation and control business-state fields such as `status` and `closes_at`, bypassing a server state machine. | High | Replace broad table mutation with narrow draft-edit, publish, cancel, and close RPCs that enforce allowed transitions. |

### 6. Provider quote/bid submission - Partially implemented

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `index.html:56`; `app.js:98-101` | Provider dashboard `Make an offer` button | The provider cannot enter or submit a real quote; the button only displays a demo toast. Customer-visible bids are hard-coded in `app.js:16-21`. | High | Build a bid form and server action with amount, schedule, scope, expiry, inclusions, exclusions, and perks. |
| `001_initial_schema.sql:75-89,250` | `bids`; `provider owns bids` | The policy does not require the provider to be approved/verified, offer the category, or bid on an open request. It also allows direct updates to status and commercial terms. | High | Add an eligibility-checked `submit_bid` RPC; make accepted/expired bids immutable; allow only a controlled withdrawal action. |

### 7. Customer provider selection - Missing

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `app.js:74`; `index.html:38-40` | `.offer` click handler and checkout screen | Every offer opens the same hard-coded checkout. No bid is selected, locked, accepted, or linked to a request. | Critical | Implement an idempotent `accept_bid` transaction that locks the request, validates ownership and bid expiry, marks one bid accepted, declines competing bids, and creates the booking/payment intent. |
| `001_initial_schema.sql:75-107` | `bids`, `bookings` | No database function ensures that the booking request, bid, customer, provider, price, and schedule all agree. | Critical | Add transactional invariants in a security-definer function and supporting composite constraints where practical. |

### 8. Confirmed booking - Partially implemented

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `index.html:42-44`; `app.js:75-76` | `paid`, `booking`, `payDemo`, `completeDemo` | Booking confirmation, payment protection, and completion are hard-coded UI states with no server record or vendor confirmation. | Critical | Build booking detail routes backed by server-created records; confirm only after an authenticated vendor event; implement completion confirmation and timeout rules. |
| `001_initial_schema.sql:91-107` | `bookings` | The schema does not enforce that `bid_id` belongs to `request_id`, `customer_id` owns the request, `provider_id` owns the bid, or booking amounts match the accepted bid. | High | Enforce all cross-record invariants in the booking-creation transaction and add tests that reject mismatched records. |
| `architecture.md:11-17`; schema enums | Booking state machine | The architecture mentions `offered` and `accepted`, but the request/booking enums use different states. No executable transition guard exists. | High | Define one authoritative state machine and implement transition RPCs with actor, precondition, idempotency, and audit requirements. |

### 9. Address privacy before booking confirmation - Unsafe or unclear

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `001_initial_schema.sql:58-73` | `service_requests.precise_address_ciphertext` | A ciphertext column exists, but there is no encryption/decryption implementation, key management, rotation, or deletion job. | Critical | Move exact addresses to a dedicated private table; encrypt server-side with managed keys; define access, rotation, and retention deletion jobs. |
| `001_initial_schema.sql:249` | `providers see open requests` | The policy exposes the whole open request row to any role covered by the policy; there is no column-level safe view and no approved-provider condition. | High | Serve pre-booking requests through a safe view/RPC that omits exact-address material and unnecessary identifiers. |
| `architecture.md:19-24`; `index.html:44,60` | Address-minimisation claims | The intended privacy rule exists only in documentation/UI. No confirmed-booking access grant or revocation is implemented. | High | Implement time-bound address access for confirmed booking parties and log every reveal; test that all other actors are denied. |

### 10. Payment status tracking - Partially implemented

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `001_initial_schema.sql:109-123`; `contracts.ts:4-54` | `payments`, `PaymentStatus`, `PaymentGateway` | The database uses unrestricted text for status while TypeScript defines an enum. There is no adapter, status transition guard, reconciliation job, or payment history ledger. | Critical | Add a constrained database payment-status type and immutable payment-event/ledger records; implement a sandbox gateway adapter and reconciliation worker. |
| `app.js:75`; `index.html:40-44` | `payDemo`, payment/booking screens | The client marks payment protected in `localStorage` without a provider callback. | Critical | Redirect to hosted checkout and show funded/protected status only after a verified webhook or server-side provider lookup. |

### 11. Cash payment handling - Missing

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| Repository-wide; `index.html:40` | Payment methods and booking/payment schema | No cash policy, payment method, cash receipt flow, off-platform warning, fee treatment, or dispute limitation exists. The UI offers only card and Instant EFT. | High | Make an explicit launch decision. Recommended: prohibit cash for protected bookings, enforce `payment_method`, and clearly label off-platform/cash payments as unprotected. |
| `001_initial_schema.sql:91-123` | `bookings`, `payments` | The model cannot distinguish cash, hosted card, EFT, failed payment, or an unpaid booking. | High | Add payment-method and protection-scope fields with constrained values and corresponding state rules. |

### 12. Refund handling - Partially implemented

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `contracts.ts:29-35,47-53`; `001_initial_schema.sql:109-123` | `RefundInput`, `PaymentGateway.refund`, `payments.refunded_minor` | Only an interface and aggregate amount exist. There is no refund request/attempt record, approval workflow, idempotent server action, vendor implementation, or reconciliation. | Critical | Add `refunds` and `refund_events` tables and an audited, idempotent refund service that calls the vendor and reconciles webhooks. |
| `index.html:62`; `app.js:98-101` | Admin refund action | The refund button only displays a toast and does not check role, amount, payout state, or vendor response. | Critical | Implement server-authorised full/partial refund actions with reason codes, four-eyes approval thresholds, and immutable audit events. |

### 13. Dispute handling - Unsafe or unclear

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `001_initial_schema.sql:152-176,255-258` | `disputes`, `dispute_evidence` | Opening a dispute does not atomically change booking status or set `payments.release_paused`. Duplicate/open-window rules are absent. | Critical | Implement an atomic `open_dispute` RPC that validates the party/window, creates one case, pauses release, updates booking status, and writes an audit event. |
| `001_initial_schema.sql:257` | `evidence owner inserts` | Any authenticated user can insert evidence for any dispute if `uploaded_by` equals their own ID; the policy does not require them to be a booking party. | Critical | Replace the policy with a booking-party check and use signed, MIME/size-limited, malware-scanned storage uploads. |
| `index.html:46-48,62`; `app.js:78-83,98-101` | Dispute form, evidence upload, admin resolution | Case opening uses `localStorage`; upload and resolution are simulated. There is no response, assignment, decision, appeal, notification, or SLA enforcement. | High | Build party response/evidence flows and audited support/admin assignment, decision, refund/release, appeal, and notification actions. |

### 14. Reviews and ratings - Unsafe or unclear

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `001_initial_schema.sql:178-189,259-260` | `reviews`; `reviewer creates review` | The insert policy checks that the reviewer participated in a completed booking but does not require `subject_id` to be the other booking party. A user can review an unrelated profile. | High | Replace direct insert with a `create_review` RPC that derives the subject from the booking and enforces a review window and one review per side. |
| `001_initial_schema.sql:185,260` | `moderation_status` | Client-created reviews default to `published`; no spam, retaliation, abuse-reporting, moderation, or appeal workflow exists. | High | Add review reporting/moderation actions, server-controlled publication state, and audited decisions. |
| `app.js:16-21`; `index.html:21,38,40` | Hard-coded ratings and counts | Ratings, review counts, provider verification badges, and marketplace metrics are fabricated demo data. No review form or aggregate query exists. | High | Build verified-booking review UI and a safe aggregate rating view; remove or clearly label all seeded/demo statistics in any public recruitment build. |

### 15. Admin actions - Unsafe or unclear

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `index.html:58,62`; `app.js:98-101` | `admin` screen and `.demo` handlers | Any visitor can open the admin demo. The displayed 2FA, role separation, application review, dispute resolution, refunds, and risk flags are not real. | Critical | Create a separate protected admin application/route with server-side staff membership checks, mandatory MFA, least-privilege roles, and no demo claims in production. |
| `001_initial_schema.sql:244-247,264-266` | `profiles.role`; planned privileged functions | A user can edit their own role, while the privileged server functions mentioned in comments do not exist. | Critical | Remove user control of roles and implement narrowly scoped security-definer/admin API actions that re-check staff authority and append audit events. |

### 16. Audit logging - Partially implemented

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `001_initial_schema.sql:212-220,242,264-266` | `audit_events` | The table and RLS denial exist, but no function, trigger, or application code writes events. It is not demonstrably append-only for privileged/service-role code. | High | Add a private append function used inside every privileged transaction; revoke update/delete; define retention, export, alert, and redaction rules. |
| `app.js:98-101`; `index.html:62` | Demo action handler/admin claim | The UI says actions are recorded, but the handler only shows a toast. | High | Remove the claim until real audit persistence exists, then display read-only audit history to authorised staff. |

### 17. Row-level security policies - Unsafe or unclear

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `001_initial_schema.sql:40-56,125-135,230-242` | `service_categories`, `provider_services`, `vendor_events` | These public-schema tables do not have RLS enabled. The comment that clients receive no `vendor_events` policy is ineffective because that table's RLS is not enabled. | Critical | Immediately enable RLS on every exposed table, revoke unnecessary grants, and add explicit minimum policies. |
| `001_initial_schema.sql:244-247` | Profile/provider policies | Owners can change privileged role, account, verification, bank-match, and approval columns. | Critical | Remove broad table updates and expose allow-listed profile/provider update functions; keep privileged columns server-only. |
| `001_initial_schema.sql:248-262` | Request, bid, evidence, review, consent, and privacy-request policies | Several `FOR ALL` policies expose business-state changes. Consent evidence can be modified/deleted, and users can set their own data-request status to completed or refused. | High | Replace broad CRUD with purpose-specific policies/RPCs; make compliance evidence append-oriented and workflow statuses server-controlled. |
| Repository-wide | RLS verification | No automated RLS tests prove positive and negative access for anonymous, customer, provider, support, admin, and service roles. | Critical | Add pgTAP/Supabase policy tests covering every table, actor, column, and prohibited cross-tenant operation. |

### 18. Webhook handling - Missing

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `contracts.ts:37-53,89-93,109-112`; `architecture.md:17` | Vendor webhook interfaces | Verification methods are declarations only. There are no HTTP routes, raw-body capture, signature verification implementations, timestamp tolerance, replay protection, retry, dead-letter, or reconciliation processing. | Critical | Implement server-only `/api/webhooks/{provider}` handlers with raw-body verification, event uniqueness, idempotent state transitions, retry/dead-letter handling, and provider reconciliation. |
| `001_initial_schema.sql:125-135` | `vendor_events` | The intended idempotency table has no RLS and no processing worker. `processed_at` is never set. | Critical | Enable RLS/revoke client access; write events and state transitions in controlled transactions; add replay and out-of-order event tests. |

### 19. Environment variable handling - Partially implemented

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| `.env.example:1-18`; `architecture.md:3-9` | Environment names and trust-boundary guidance | Secret names and sound guidance exist, but there is no application configuration module, startup validation, environment separation, secret manager, rotation process, or evidence that service-role/vendor keys stay server-only. | High | Add typed server-only configuration validation, secret-manager deployment, dev/staging/prod separation, rotation runbook, and automated secret scanning. |
| `.env.example:5,9,13` | `*_PROVIDER=mock` | A production deployment could silently run mock providers because there is no fail-closed production check. | High | Fail startup when production has empty secrets or any mock provider; expose a non-secret health/readiness check. |
| Repository root | `.gitignore`, package/build configuration | No `.gitignore` or build system is present to protect `.env` files and constrain client/server bundling. | High | Add the chosen application framework, `.gitignore`, server-only module boundaries, CI secret scanning, and deployment configuration. |

### 20. Test coverage - Missing

| File | Table/component/function | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|---|
| Repository-wide | Tests and CI | There is no package manifest, test runner, migration test, unit test, integration test, E2E test, security test, or CI workflow. | Critical | Establish CI and a test pyramid: SQL/constraint tests, pgTAP RLS tests, unit tests for state machines/adapters, webhook fixtures, integration tests, and E2E customer/provider/admin flows. |
| `app.js` and all schema policies | Negative-path coverage | No tests cover unauthorised access, replayed webhooks, duplicate acceptance, failed payment, payout/dispute races, mismatched booking records, or identity callback tampering. | Critical | Add adversarial test cases before any live credential or real personal information is introduced. |

## Cross-cutting launch gaps

| File | Gap | Risk | Recommended next task for Codex |
|---|---|---|---|
| `outputs/potchly-prototype/index.html`; `app.js` | The application is still branded Potchly throughout, including title, copy, hard-coded statistics, identifiers, and `localStorage` keys. It is not branded LEKKADEALL. | Medium | Create a single brand/config source, replace legacy branding, and remove unsupported marketplace statistics and trust claims. |
| Repository-wide | There is no deployable production application, backend, package manifest, source routing structure, or Supabase client. | Critical | Scaffold the production web application with authenticated customer/provider/admin routes and a server-only integration layer; keep the prototype as a separate demo artifact. |
| `index.html:21,32,40-44,52,58,62` | The UI presents provider counts, ratings, verification badges, payment protection, login alerts, 2FA, audit logging, and protected balances that are not backed by real systems. | High | Clearly mark the entire prototype as demonstration-only and remove unsupported claims from any public-facing recruitment version. |
| `README.md:32` | The repository itself states that it is an implementation foundation and not a deployed production system. | Critical | Treat all features as launch-gated until implementation, security review, sandbox testing, and controlled-pilot acceptance criteria pass. |

## Recommended implementation order

1. **Security migration first:** repair RLS, role/approval column ownership, `vendor_events`, evidence insertion, review subject integrity, and compliance-workflow mutability.
2. **Production application shell:** create customer, provider, and separately protected admin routes with Supabase Auth and server-only configuration.
3. **Transactional marketplace core:** implement request publishing, bid submission, bid acceptance, booking creation, and guarded state transitions.
4. **Mock integrations plus tests:** implement payment/identity/messaging adapters against mock providers and build SQL, RLS, unit, integration, and E2E coverage.
5. **Sandbox vendors:** integrate hosted payment and identity flows, signed webhooks, refunds, payout pause/release, reconciliation, and failure recovery.
6. **Privacy and operations:** implement address isolation, consent evidence, data-subject workflows, retention jobs, incident response, admin audit tools, and support/dispute procedures.
7. **Controlled pilot only after gates pass:** no real identity evidence or live payment should be accepted before vendor contracts, lawyer-approved disclosures, tested refunds/disputes, monitoring, backups, and incident response are operational.
