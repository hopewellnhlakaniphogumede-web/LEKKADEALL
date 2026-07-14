# Ticket 9A Planning Document — Customer and Provider Frontend Shell

## Goal

Plan the first safe LEKKADEALL customer/provider frontend implementation step without implementing UI or changing the Tickets 1–8B security foundation.

Ticket 9A covers:

- public landing and service-category discovery;
- authentication screens;
- customer and provider dashboard shells;
- a read-only profile/settings shell;
- customer request-creation flow design;
- provider open-request feed design;
- customer/provider booking timeline design; and
- mock/sandbox payment display only.

## Planning-only status

This document is planning-only. Do not implement UI under Ticket 9A.

Ticket 9A does not add real payment-provider code, real checkout, an admin dashboard, credentials, migrations, RLS changes, database functions, direct privileged writes, cash/off-platform payment UI, or exact-address exposure.

The required mock-payment label is exactly:

> **Mock/sandbox — no real money moved**

## Non-negotiable implementation rules

1. All application-database mutations must use existing trusted public functions listed in this plan. No screen may fall back to direct table insert/update/delete.
2. Supabase Auth screens may use the supported Supabase Auth client operations for sign-up, sign-in, password recovery, session refresh, and sign-out. Auth operations do not authorise database workflow mutations.
3. Route guards and hidden buttons are UX controls only. RLS, grants, and trusted functions remain the authority.
4. No service-role key, webhook secret, provider key, identity secret, or other server-only value may enter browser code, source maps, logs, analytics, or network responses.
5. Exact address plaintext must not appear in provider feeds, request summaries, URLs, analytics, logs, notifications, error reports, or browser persistence.
6. A field named `precise_address_ciphertext` must receive ciphertext only. The UI must not rename plaintext as ciphertext or submit plaintext to that parameter.
7. Profile/settings remains read-only in Ticket 9A because the current foundation has no trusted customer/provider profile-update function. Existing column-level direct update grants do not override this ticket's trusted-function-only rule.
8. Mock payment state must always display **“Mock/sandbox — no real money moved”** and must be unavailable when the application is running as production.
9. Do not render a cash option, off-platform payment option, manual “I paid” control, payment override, refund outcome control, payout control, or webhook trigger.
10. Unknown, missing, or unauthorised state fails closed. The shell shows a safe error/empty state and does not infer access or success.

## Ticket 9A boundary

### In scope for the future implementation ticket

- layouts, navigation, route guards, loading/error/empty states;
- public active-category reads;
- Supabase Auth screens and session handling;
- authorised customer/provider read models using existing RLS;
- customer request workflow through existing trusted functions;
- provider request discovery and bid workflow through existing trusted functions;
- customer bid acceptance through the existing trusted function;
- booking progress/completion through existing trusted functions;
- deliberate provider address reveal through the existing audited function, only after all address-handling prerequisites below are satisfied;
- customer mock-checkout session creation in non-production sandbox only;
- safe display of mock payment/release status.

### Out of scope

- admin routes or admin dashboard implementation;
- provider verification submission or identity-document handling;
- real checkout, payment methods, payment receipt, refund execution, payout execution, or reconciliation;
- real payment-provider webhooks or changes to the mock webhook foundation;
- profile editing, role/account-status editing, provider-status editing, or provider-service mutation;
- disputes/evidence, reviews, consent workflow, data-subject-request workflow, support cases, notifications, or chat;
- new database queries/functions, migrations, RLS/grant changes, storage policies, or tests in this planning ticket.

## 1. Route map

Route names are proposed and can be adapted to the future framework, but the access and data boundaries are mandatory.

### Public and auth routes

| Route | Audience | Purpose | Data/action boundary |
|---|---|---|---|
| `/` | Public | Landing page, value proposition, trust/safety and mock-payment limitation | Static content plus active `service_categories` only |
| `/services` | Public or authenticated | Active service-category discovery | Read active categories only; no mutation |
| `/auth/sign-in` | Signed out | Sign in | Supabase Auth only |
| `/auth/register` | Signed out | Create an auth account | Supabase Auth only; no client-selected privileged role |
| `/auth/forgot-password` | Signed out | Request recovery | Supabase Auth only; neutral response to reduce account enumeration |
| `/auth/reset-password` | Recovery session | Set a new password | Supabase Auth only |
| `/auth/callback` | Auth callback | Complete supported auth redirect/session exchange | Validate expected flow; never accept a role/status from query parameters |
| `/access-denied` | Any | Safe unauthorised-state page | No sensitive data |
| `/account-restricted` | Authenticated restricted account | Explain restricted status and support path | Own safe profile/account status only |

### Customer routes

| Route | Audience | Purpose | Allowed mutations |
|---|---|---|---|
| `/app/customer` | Authenticated customer | Dashboard shell | None |
| `/app/customer/requests/new` | Authenticated customer | Request-creation wizard | `customer_create_draft_request(...)`; address/publish actions only at gated steps |
| `/app/customer/requests/:requestId` | Owning customer | Own request and bid detail | `customer_publish_request(...)`, `customer_cancel_request(...)`, `customer_accept_bid(...)` when state permits |
| `/app/customer/bookings/:bookingId` | Booking customer | Booking timeline and mock payment display | `customer_create_mock_checkout_session(...)` in non-production sandbox; `customer_confirm_completion(...)` when allowed |
| `/app/settings` | Authenticated customer/provider | Read-only profile/settings shell | None in Ticket 9A |

### Provider routes

| Route | Audience | Purpose | Allowed mutations |
|---|---|---|---|
| `/app/provider` | Authenticated provider | Provider dashboard shell | None |
| `/app/provider/requests` | Approved active provider | Safe open-request feed | None |
| `/app/provider/requests/:requestId` | Approved active provider with feed visibility | Safe request detail and bid form | `provider_submit_bid(...)` |
| `/app/provider/bids/:bidId` | Owning provider | Own bid detail | `provider_withdraw_bid(...)` when state permits |
| `/app/provider/bookings/:bookingId` | Selected booking provider | Booking timeline and deliberate address reveal | `reveal_confirmed_booking_address(...)`, `booking_mark_in_progress(...)`, `provider_confirm_completion(...)` when authorised |

### Route resolution rules

- Signed-out users requesting `/app/**` go to sign-in with a safe internal return path.
- The return path must be allow-listed; never redirect to an arbitrary external URL from a query parameter.
- Authenticated users with an unsupported/unknown role go to `/access-denied`.
- Suspended/restricted users go to `/account-restricted` and cannot rely on client-side navigation to regain access.
- Provider routes do not assume that `role = provider` means approved. Feed and bid eligibility must be determined by the trusted function/RLS response.
- Customer and provider detail routes must handle an RLS-hidden row as “not found or unavailable,” without confirming that another user's record exists.
- There is no `/admin` route in Ticket 9A.

## 2. Page and component list

### Shared application shell

- `PublicHeader`: logo, service discovery, sign-in/register links.
- `AuthenticatedHeader`: role-appropriate navigation and sign-out.
- `AppSidebar` or compact navigation: customer/provider links only.
- `SessionBoundary`: loading, signed-out, recovery, expired-session, and authenticated states.
- `RoleRouteBoundary`: selects customer/provider shell without granting authority.
- `AccountStatusBanner`: safe restricted/suspended messaging.
- `PageState`: loading, empty, error, unauthorised/not-found, retry.
- `SafeErrorMessage`: maps database errors to user guidance without leaking SQL, policies, IDs, or sensitive inputs.
- `ConfirmationDialog`: explicit confirmation for publish, cancel, accept bid, withdraw bid, mark in progress, completion, and address reveal.
- `MockPaymentBanner`: always renders **“Mock/sandbox — no real money moved”**.
- `StatusBadge`: allow-listed request, bid, booking, payment, and release statuses; unknown values render as “Unavailable,” not as success.

### Public landing page

- hero and primary customer/provider calls to action;
- how-it-works steps for customer request, provider bid, booking, and completion;
- service-category preview;
- trust/safety section explaining exact-address privacy;
- payment limitation section explaining that the current interface is mock/sandbox only;
- no testimonials, provider counts, payment guarantees, or trust claims unless backed by approved content/data;
- footer with privacy, terms, and support placeholders.

### Authentication pages

- sign-in form;
- registration form;
- forgot-password form;
- reset-password form;
- callback/session completion state;
- email verification/pending state if enabled by the future auth configuration;
- generic success/error messaging that avoids account enumeration;
- no customer-selectable admin role or provider approval/verification state.

### Customer dashboard shell

- greeting using safe own display name;
- primary action to create a request;
- own request summary cards;
- own booking summary cards;
- mock payment-status summary with mandatory label;
- empty states for no requests/no bookings;
- no admin metrics, provider private data, payment ledger, vendor events, audit events, or exact addresses.

### Provider dashboard shell

- provider onboarding/readiness status using own safe status fields;
- eligibility banner for pending/rejected/suspended providers;
- link to open-request feed only when the server permits it;
- own bid summary cards;
- own booking summary cards;
- mock/internal release-status summary with mandatory label;
- no real earnings/balance claim and no provider-bank onboarding.

### Profile/settings shell

- own safe profile data: display name, phone, suburb, city, avatar reference;
- provider-only safe business data: business name, bio, service radius;
- read-only account/provider verification and review status;
- sign-out and password-management link;
- every edit/save control disabled or omitted in Ticket 9A because no trusted profile-update function exists;
- no role, account-status, verification, review, bank, identity-evidence, payment, refund, release, or admin fields.

### Service-category discovery

- active-category grid/list;
- category name, slug, icon, and safe description if present in the current schema;
- search/filter performed against the active category result only;
- category selection can start the authenticated customer request wizard;
- inactive categories and all mutation controls remain hidden and inaccessible.

### Customer request-creation wizard

Proposed steps:

1. **Service** — select an active category.
2. **Job summary** — title and public description with explicit no-address/no-phone warning.
3. **Approximate area** — suburb and city only.
4. **Schedule and budget** — requested start and optional budget in ZAR, converted to integer minor units without floating-point arithmetic.
5. **Create draft** — call `customer_create_draft_request(...)` with no plaintext exact address.
6. **Exact address** — designed as a separate private step. Submission remains blocked until an approved client/server encryption boundary can produce genuine ciphertext for `customer_upsert_service_request_address(...)` without leaking plaintext.
7. **Review and publish** — show only the safe public summary plus a masked confirmation that a private address exists. Call `customer_publish_request(...)` only when the backend prerequisites are satisfied.

The wizard must not store exact address, phone, or request drafts in localStorage/sessionStorage. If the user leaves before secure address handling is available, keep the database request in draft and explain that publication is unavailable.

### Provider open-request feed

- call `list_provider_open_request_summaries(...)` with optional city, category, and bounded limit;
- cards display only the function's returned safe fields;
- filters: city, category, and safe client-side sort over returned results;
- no customer profile lookup or direct broad `service_requests` query;
- no exact address, customer ID, phone, email, payment, bid competitor, internal/admin, or dispute data;
- pending/unapproved/suspended providers receive a safe ineligible state, not a fallback query.

### Provider request detail and bid form

- reuse only the safe summary returned by `list_provider_open_request_summaries(...)` or a matching safe result already held in memory;
- show bid amount, proposed start, optional message/perks, and expiry inputs;
- convert amount to integer minor units safely;
- call `provider_submit_bid(...)` once per explicit submission;
- disable repeat submission while pending and handle database rejection as authoritative;
- do not reveal competing bid amounts or customer identity unless a future authorised read model explicitly allows it.

### Booking timeline

Shared timeline stages:

1. bid accepted / booking created;
2. payment pending or mock checkout created;
3. mock payment status;
4. scheduled;
5. in progress;
6. completion confirmations;
7. completed;
8. internal/mock release status.

Timeline rules:

- derive every stage from authorised `bookings` and `payments` data, never browser-only state;
- do not infer real funding, refund, or payout from a mock/internal status;
- show the mandatory mock label beside every payment/release section;
- provider exact-address reveal is a separate deliberate audited action, not automatic page-load data;
- do not persist the revealed ciphertext or future decrypted address in client storage or telemetry;
- customer and provider completion buttons appear only when relevant, but the trusted function remains authoritative;
- no cash/off-platform steps.

## 3. Supabase calls permitted by page

All reads remain subject to current RLS and column grants. “Table read” below is not permission to broaden the schema, grant, or policy.

| Page | Permitted reads | Permitted function/Auth calls | Prohibited calls |
|---|---|---|---|
| Landing | Active `service_categories` | None | Any mutation; private/authenticated data |
| Service discovery | Active `service_categories` | None | Category mutation |
| Sign in/register/recovery | None from app tables before session | Supabase Auth operations only | Role/status/provider approval assignment |
| Customer dashboard | Own safe `profiles`, `service_requests`, `bookings`, `payments`; own visible bid summaries where current RLS permits | None | Direct writes; event/audit/vendor reads |
| New request | Active categories; newly created own request | `customer_create_draft_request(...)`; gated `customer_upsert_service_request_address(...)`; gated `customer_publish_request(...)` | Direct request/address insert/update; plaintext passed as ciphertext |
| Customer request detail | Own request and authorised bids | `customer_publish_request(...)`, `customer_cancel_request(...)`, `customer_accept_bid(...)` | Direct request/bid/booking/payment writes |
| Customer booking | Own booking/payment safe fields | Non-production `customer_create_mock_checkout_session(...)`; `customer_confirm_completion(...)` | Mock outcome/admin/webhook/refund/payout functions |
| Provider dashboard | Own safe `profiles`, `provider_profiles`, own `bids`, own `bookings`, permitted `payments` | `is_approved_provider(...)` may support readiness checks | Direct privileged/provider/workflow writes |
| Provider feed | Active categories plus function result | `list_provider_open_request_summaries(...)` | Direct broad open-request/customer lookup |
| Provider request detail | Safe summary already returned | `provider_submit_bid(...)` | Direct bid insert; customer/exact-address query |
| Provider bid detail | Own bid and safe related status | `provider_withdraw_bid(...)` | Direct bid update/delete |
| Provider booking | Own selected booking/payment safe fields | `reveal_confirmed_booking_address(...)`, `booking_mark_in_progress(...)`, `provider_confirm_completion(...)` | Private address-table read; direct booking/payment/release write |
| Profile/settings | Own allow-listed display fields/status | Supabase Auth password/sign-out actions only | Direct table update in Ticket 9A; all privileged/admin actions |

### Existing trusted mutation functions in Ticket 9A

- `customer_create_draft_request(...)`
- `customer_upsert_service_request_address(...)` — gated until ciphertext generation/handling is approved
- `customer_publish_request(...)` — gated by complete safe draft/address prerequisites
- `customer_cancel_request(...)`
- `customer_accept_bid(...)`
- `customer_confirm_completion(...)`
- `customer_create_mock_checkout_session(...)` — non-production sandbox only
- `provider_submit_bid(...)`
- `provider_withdraw_bid(...)`
- `booking_mark_in_progress(...)`
- `provider_confirm_completion(...)`

`reveal_confirmed_booking_address(...)` is a trusted read with an audit side effect and must be treated as a sensitive action.

### Trusted read/helper functions

- `is_approved_provider(...)`
- `list_provider_open_request_summaries(...)`
- `reveal_confirmed_booking_address(...)`

No page may call:

- `admin_*` functions;
- `admin_process_verified_mock_payment_webhook(...)`;
- `private.*` functions;
- webhook routes as a way to force status;
- service-role-only paths;
- customer/provider cash-selection marker functions;
- any new/unreviewed RPC added outside this plan.

## 4. Display allow-list by page

### Landing and category discovery

Allowed:

- product copy approved for MVP;
- active category ID/slug/name/icon/safe description;
- general city/service-area copy if static and approved.

Blocked:

- user/provider records;
- request, bid, booking, payment, verification, dispute, event, or audit data;
- exact address or private customer/provider information;
- claims of real payment protection while only mock/sandbox exists.

### Customer dashboard and request pages

Allowed for the signed-in customer only:

- own safe profile display fields;
- own request ID, category, title, description, suburb, city, requested start, budget, status, closing/created/updated timestamps;
- own request bids that current RLS permits, including safe provider/bid presentation data needed for selection;
- own booking identifiers, schedule, amount/currency, state, and completion-confirmation state;
- own payment amount/currency, payment status, release status, safe mock provider/checkout references and expiry where granted;
- required mock label.

Blocked:

- another customer's records;
- provider identity or financial data beyond the approved bid/provider presentation;
- raw event ledgers, vendor events, audit events, webhook metadata, secrets, or provider credentials;
- exact address on public/request-summary pages;
- plaintext exact address in logs, telemetry, URL, or persistence;
- real-money, real-refund, or real-payout claims.

### Provider dashboard and bid pages

Allowed for the signed-in provider only:

- own safe profile/business fields and status indicators;
- own services as read-only in Ticket 9A;
- own bids, bid status, amount, proposed start, message/perks, expiry, and safe related request status;
- own selected bookings and permitted payment/release summary;
- mock/internal release state with required mock label.

Blocked:

- other providers' private profiles, bids, bookings, payment/release data, or bank information;
- customer identity/contact details unless a later authorised booking read model explicitly supplies the minimum necessary fields;
- exact address except the result of the deliberate authorised reveal function;
- real balance, earnings deposited, settlement date, or payout-sent claims.

### Provider open-request feed

The allow-list is exactly the safe function result:

- `request_id`
- `category_id`
- `title`
- `description`
- `suburb`
- `city`
- `requested_start`
- `budget_minor`
- `status`
- `closes_at`
- `created_at`
- `updated_at`

Do not enrich cards by querying customer profiles or direct private request columns. In particular, do not display customer ID, name, avatar, phone, email, exact address/ciphertext, GPS coordinates, payment data, dispute data, or internal/admin fields.

### Booking timeline

Allowed:

- own booking ID, party-appropriate display context, schedule, agreed amount/currency, booking status, and completion confirmations;
- own permitted payment status and release status;
- safe mock checkout reference/expiry if granted;
- exact mock label;
- selected provider's on-demand address reveal result only when authorised.

Blocked:

- payment/refund/vendor/audit ledger rows;
- webhook signatures, raw bodies, payload hashes, secrets, or internal mismatch/security metadata;
- refund or payout outcome controls;
- exact address on customer/provider dashboards, feed, analytics, or automatic page preload;
- language implying real funds moved.

## 5. Blocked actions

### Blocked throughout Ticket 9A

- any direct `insert`, `update`, or `delete` against application tables;
- profile or provider-profile save/edit actions;
- provider-service create/update/delete;
- role, account-status, verification, review, identity, payment, refund, release, dispute, or audit mutation;
- admin function calls or admin dashboard routes;
- access to `vendor_events`, `payment_events`, `refund_events`, or `audit_events`;
- private exact-address table reads/writes;
- real checkout or real provider API calls;
- payment-method picker, card/CVV input, bank-login input, cash selection, off-platform confirmation, “I paid,” or “mark paid”;
- real refund, payout, release, reconciliation, chargeback, or settlement controls;
- identity-document upload or verification-result submission;
- dispute/evidence, review, consent, data-subject-request, support-case, or chat mutation;
- arbitrary redirect URLs, unbounded feed requests, raw SQL, service-role access, or secrets in the browser.

### Address-dependent blocked actions

Until the future implementation ticket documents and verifies how genuine ciphertext is produced and later safely consumed:

- do not submit exact-address plaintext to `customer_create_draft_request(...)` or `customer_upsert_service_request_address(...)`;
- do not enable final publication when a required private address has not been safely stored;
- do not automatically call `reveal_confirmed_booking_address(...)` on page load;
- do not attempt browser-side decryption with a committed/shared application key;
- do not store revealed ciphertext/plaintext in localStorage, sessionStorage, cache persistence, analytics, or error reports.

### Mock-payment blocked actions

- no mock outcome controls for customers/providers;
- no client call to the mock webhook processor;
- no fake success written to local state as authoritative payment status;
- no mock checkout in production;
- no display of “paid,” “refunded,” “released,” or similar without the adjacent label **“Mock/sandbox — no real money moved”**;
- no real receipt, payout confirmation, or payment-protection promise.

## 6. Test plan for the future implementation ticket

No tests are added by this planning document. The future implementation ticket must add tests proportionate to the frontend framework while keeping every existing Deno and pgTAP test green.

### Unit/component tests

- route/session boundaries render loading, signed-out, expired, restricted, wrong-role, and authorised states correctly;
- status components allow-list known states and fail safely on unknown values;
- `MockPaymentBanner` renders the exact phrase **“Mock/sandbox — no real money moved”** in every payment/release context;
- production configuration cannot render mock checkout actions;
- category and request cards render only their display allow-lists;
- amount input converts ZAR to integer minor units without floating-point errors;
- safe error mapping does not expose SQL, policy names, secrets, sensitive inputs, or another record's existence;
- exact-address fields are excluded from generic form persistence and telemetry;
- profile/settings has no working database save action;
- no cash/off-platform/manual-payment component exists.

### Supabase integration tests

- each mutation page calls only its listed trusted function with the expected argument shape;
- no frontend module performs direct application-table writes;
- customer draft creation, cancellation, publication, bid acceptance, completion, and sandbox checkout handle success and database rejection correctly;
- provider feed uses only `list_provider_open_request_summaries(...)` and respects its bounded limit;
- provider bid submission/withdrawal and booking actions use only trusted functions;
- invalid or duplicate submissions remain safe and do not create duplicate workflow state;
- failed mutations refresh/reconcile from the database rather than retaining optimistic success;
- address RPC calls remain disabled until the approved ciphertext boundary test suite exists;
- ordinary clients cannot import/call admin, private, service-role, or webhook-processing paths.

### RLS and privacy end-to-end tests

- signed-out users cannot access `/app/**` data;
- one customer cannot discover another customer's requests, bids, bookings, payments, or address;
- one provider cannot discover another provider's bids, bookings, payments, or release data;
- unapproved, unverified, or suspended providers cannot use the open-request feed or submit a bid;
- provider feed cards never contain customer ID/contact or exact address fields;
- unselected providers cannot reveal an address;
- selected providers cannot reveal before an authorised booking state;
- authorised reveal is deliberate, audited by the existing backend, and excluded from logs/analytics/storage;
- URL/query/referrer data never contains exact addresses or secrets;
- browser storage contains no exact address, token beyond the approved auth/session mechanism, or payment-sensitive data.

### Journey tests

Customer:

1. register/sign in;
2. view active categories;
3. create a safe draft without address leakage;
4. safely complete the gated address step once enabled;
5. publish through the trusted function;
6. review and accept a bid;
7. view booking timeline;
8. create mock checkout in non-production sandbox;
9. see the required mock label;
10. confirm completion only when the backend permits.

Provider:

1. sign in;
2. see read-only approval status;
3. approved provider views safe feed;
4. submit and withdraw a bid through trusted functions;
5. selected provider views own booking;
6. reveal address only through deliberate authorised action once enabled;
7. mark in progress and confirm completion through trusted functions;
8. see mock/internal payment/release status with the required label.

### Security/build tests

- bundle and source-map scan finds no service-role key, webhook/provider/identity secret, or credential-like value;
- static scan finds no direct `.insert()`, `.update()`, `.delete()`, admin RPC, private RPC, or webhook processor call in Ticket 9A client code;
- production build fails closed if mock mode is enabled;
- content security policy and output escaping prevent untrusted HTML/script execution;
- auth return URLs are allow-listed and open redirects are rejected;
- accessibility checks cover keyboard navigation, focus management, names/labels, error association, contrast, and status announcements;
- responsive tests cover agreed mobile, tablet, and desktop breakpoints;
- existing mock webhook route tests and all pgTAP suites remain green.

## 7. Definition of done for the future Ticket 9A implementation

Ticket 9A implementation is complete only when:

### Routes and shells

- all in-scope public, auth, customer, provider, and settings routes exist with correct session/role/account boundaries;
- no admin route or admin dashboard is implemented;
- loading, empty, safe error, access-denied, restricted, retry, and not-found states are complete;
- navigation never exposes an action unavailable to the current user, while server/database enforcement remains authoritative.

### Data and functions

- every page displays only the allow-listed data in this plan;
- public discovery reads only active service categories;
- provider discovery uses only `list_provider_open_request_summaries(...)`;
- every application-database mutation uses an existing trusted function listed in this plan;
- there are no direct application-table inserts, updates, or deletes in Ticket 9A client code;
- profile/settings is read-only unless a separately reviewed future ticket adds a trusted profile-update function;
- stale/failed mutations reconcile from trusted database state.

### Address privacy

- request descriptions and approximate locations warn against exact-address/contact disclosure;
- exact address is not present in provider feeds, request summaries, URLs, telemetry, notifications, logs, or persistent browser storage;
- the address submission/reveal UI is not enabled until genuine ciphertext handling and safe consumption are documented and tested;
- once enabled, exact address storage and reveal use only the existing controlled functions and reveal remains deliberate/audited;
- no browser or repository contains a shared decryption key.

### Mock payments

- only mock/sandbox checkout display exists;
- every payment/release surface says **“Mock/sandbox — no real money moved”**;
- mock checkout actions are available only to the booking customer in a non-production sandbox and call only `customer_create_mock_checkout_session(...)`;
- no customer/provider UI can set mock outcomes, call webhook processing, or mutate payment/release state;
- production cannot render or enable mock checkout;
- no real provider code, checkout, payment method, credential, API call, refund, payout, or reconciliation UI exists.

### Security and quality

- no credentials or server-only secrets are shipped to the browser;
- no RLS, grant, migration, or database security change was made merely to satisfy the shell;
- cash/off-platform payment UI is absent;
- all Ticket 9A unit, integration, journey, privacy, security, accessibility, and responsive tests pass;
- all existing Tickets 1–8B Deno and pgTAP CI tests remain green;
- implementation documentation maps routes to reads/functions and records every deliberately blocked action.

## Explicit non-goals

This plan does not:

- implement UI;
- implement an admin dashboard;
- select or integrate a real payment provider;
- implement real checkout, refunds, payouts, reconciliation, or real webhooks;
- add credentials or call real payment APIs;
- add migrations, RLS/grant changes, tables, functions, tests, or storage policies;
- authorise direct privileged or workflow table writes;
- expose exact addresses;
- add cash or off-platform payment options;
- weaken any protection delivered by Tickets 1–8B.
