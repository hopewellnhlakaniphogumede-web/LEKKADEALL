# Ticket 9A-2 Planning Document — Supabase Auth and Safe Read-Only Data

## Goal

Plan how to connect the Ticket 9A-1 customer/provider frontend shell to Supabase Auth and narrowly scoped, read-only application data without implementing sensitive marketplace mutations.

Ticket 9A-2 should establish:

- one public Supabase browser-client boundary using the project URL and anon key only;
- sign-in, registration, password recovery/reset, sign-out, and session handling;
- session-backed customer/provider route guards;
- active service-category reads;
- own-profile, own-account-status, own-provider-status, and minimal own-dashboard reads where current RLS and column grants already permit them; and
- safe loading, empty, restricted, unknown-role, missing-profile, and error behavior.

## Planning-only status

This document is planning-only. Do not implement code under this planning ticket.

Do not add credentials, a service-role key, admin UI, profile editing, exact-address handling, sensitive marketplace actions, real payment-provider code, migrations, RLS/grant/policy changes, or database functions.

## Current foundation and confirmed blocker

Ticket 9A-1 currently provides a dependency-free static shell under `outputs/lekkadeall-frontend-shell` with:

- public, auth, customer, provider, settings, access-denied, restricted, and not-found routes;
- non-transmitting auth forms;
- safe signed-out/empty dashboard states;
- read-only settings;
- no Supabase browser client; and
- no application-table mutations.

The current schema has `public.profiles.id` referencing `auth.users.id`, but it has **no trusted trigger or function that creates a `public.profiles` row after Supabase Auth registration**.

This is a hard blocker for a complete new-user journey:

- Ticket 9A-2 may call Supabase Auth `signUp(...)` because it is an auth operation, not an application-table write.
- Ticket 9A-2 must not directly insert a `public.profiles` row.
- Auth user metadata must not be treated as the source of truth for application `role`, `account_status`, provider approval, or verification.
- A newly registered auth user with no `public.profiles` row must fail closed into an “account setup unavailable” state and cannot enter customer/provider application routes.
- A separate explicitly authorised backend ticket must later add and test secure profile provisioning. Ticket 9A-2 must not add that migration/function itself.

## Hard security rules

1. The browser client uses only the Supabase project URL and anon key.
2. No `SUPABASE_SERVICE_ROLE_KEY`, service-role client, provider secret, webhook secret, identity secret, admin credential, or real secret value may appear in the frontend, `.env.example`, bundle, source map, log, analytics, test fixture, or static file.
3. The anon key is public by design but must still be supplied through deployment/runtime configuration; do not commit a real project value.
4. Every application-data query uses an explicit column projection. Do not use `select('*')`.
5. Reads rely on current RLS and column grants. Client-side filters improve correctness but never replace RLS.
6. An empty RLS result is a valid “no data available” state. Do not retry with broader columns, a different table, an RPC, or elevated credentials.
7. Ticket 9A-2 adds no application-table `insert`, `update`, `upsert`, or `delete`.
8. Ticket 9A-2 calls no `admin_*`, `private.*`, mock webhook, payment outcome, cash marker, exact-address, marketplace mutation, or unreviewed RPC.
9. Auth query parameters and user metadata never determine `role`, `account_status`, provider verification, or review status.
10. Support/admin roles have no frontend route in this ticket and resolve to access denied.
11. Restricted, suspended, closed, missing-profile, and unknown-role states fail closed.
12. Tokens, sessions, user objects, keys, raw Supabase errors, and query results must not be logged or sent to analytics.
13. Profile/settings remains read-only.
14. The required payment label remains **“Mock/sandbox — no real money moved”** anywhere payment status is shown.

## 1. Route and session flow

### Route classes

| Route | Session requirement | Ticket 9A-2 behavior |
|---|---|---|
| `/` | Public | Render without waiting for a session; optional signed-in navigation may update after session resolution |
| `/services` | Public | Read active `service_categories` with anon or authenticated session |
| `/auth/sign-in` | Signed out preferred | Submit to Supabase Auth; signed-in user is routed through profile/account/role resolution |
| `/auth/register` | Signed out preferred | May create an auth account only; application entry remains blocked until trusted profile provisioning exists |
| `/auth/forgot-password` | Public | Request recovery with a neutral response regardless of whether the email exists |
| `/auth/reset-password` | Valid recovery session | Accept a new password only after Supabase confirms a recovery session |
| `/auth/callback` | Auth callback | Complete the supported PKCE/session exchange, then resolve trusted profile/account/role state |
| `/app/customer` | Authenticated active customer profile | Read minimal own customer data only |
| `/app/provider` | Authenticated active provider profile | Read own provider status and minimal own provider shell data only |
| `/app/settings` | Authenticated active customer/provider profile | Read own safe profile/status fields; no editing |
| `/access-denied` | Any | Show a generic denial without confirming protected record existence |
| `/account-restricted` | Authenticated restricted/suspended/closed profile | Show own safe account status and no bypass action |

### Initial application boot

1. Load and validate public runtime configuration.
2. Create or reuse the singleton public Supabase client.
3. Resolve `auth.getSession()` once.
4. Subscribe to `auth.onAuthStateChange(...)` for sign-in, sign-out, token refresh, password recovery, and session expiry.
5. Keep public routes usable while session resolution is pending; do not block the landing page or active-category discovery unnecessarily.
6. For `/app/**`, render the safe loading state until session and profile resolution finish.
7. If no session exists, render/redirect to sign in using an allow-listed same-origin relative `returnTo` value.
8. If a session exists, use `session.user.id` only to request the user's own `profiles` row.
9. Resolve account status and role exclusively from the RLS-protected `public.profiles` row.
10. Clear in-memory account/read-model state whenever the auth user changes or signs out.

### Trusted route-resolution decision tree

```text
No valid session
  -> signed-out state / sign-in

Valid session, no own profiles row
  -> access denied: account setup unavailable
  -> no profile insert, no role fallback, no metadata fallback

Own profile account_status = restricted | suspended | closed
  -> /account-restricted
  -> no customer/provider reads beyond the minimum own status already resolved

Own profile account_status = active and role = customer
  -> /app/customer or /app/settings

Own profile account_status = active and role = provider
  -> read own provider_profiles status
  -> /app/provider or /app/settings

Own profile role = support | admin | unknown | null
  -> /access-denied
  -> no admin route
```

### Sign-in flow

1. Validate only required form shape in the browser.
2. Call Supabase Auth password sign-in through the public client.
3. Return a generic “Unable to sign in with those details” message for invalid credentials.
4. Do not reveal whether an email exists, whether a profile exists, or what role/status belongs to an account.
5. After success, resolve the own `profiles` row and apply the trusted route decision tree.
6. Honor `returnTo` only when it exactly matches an allow-listed internal route or an allowed `/app/...` prefix; otherwise use the role dashboard default.

### Registration flow and profile-provisioning blocker

1. Call Supabase Auth registration using email/password and the approved same-origin callback URL.
2. Do not send `role`, `account_status`, provider verification, provider review, or admin fields as auth metadata.
3. Show a neutral email-confirmation/pending message when confirmation is required.
4. After confirmation/sign-in, query the own `profiles` row.
5. If the row is absent, show “Your sign-in exists, but application setup is not available yet.”
6. Do not create the missing row from the browser.
7. Do not default the user to customer in client state.

Full registration cannot meet production definition of done until a separate backend ticket provides tested, least-privilege profile provisioning.

### Forgot-password flow

1. Construct the recovery redirect from the configured public application origin, not from user input.
2. Call Supabase Auth password-reset email.
3. Always show a neutral response such as “If an account matches, recovery instructions will be sent.”
4. Do not log the email or auth response.

### Reset-password flow

1. Accept only a Supabase-established recovery session.
2. Reject direct access without a recovery session.
3. Validate password/confirmation locally, then call the Supabase Auth password-update operation.
4. Clear form values and recovery-only state after success or terminal failure.
5. Resolve the normal session/profile route only after the auth operation succeeds.

### Auth callback flow

- Use the Supabase-supported browser PKCE/session callback behavior.
- Treat callback `code`/error parameters as authentication transport only.
- Never accept `role`, `account_status`, `provider`, `verified`, `returnTo`, or similar authority from callback parameters.
- Use a fixed/allow-listed post-callback destination.
- Remove sensitive callback parameters from the visible URL after successful exchange.
- On failure, clear partial state and show a safe generic error with a sign-in link.

### Sign-out flow

1. Call Supabase Auth `signOut()` through the public client.
2. Clear in-memory profile, provider-status, customer-dashboard, and provider-dashboard state immediately.
3. Do not manually copy, enumerate, or log stored auth tokens.
4. Navigate to `/` or `/auth/sign-in` using a fixed internal route.
5. A sign-out failure still clears local rendered personal data and fails closed while the client reconciles session state.

## 2. Environment variable names and placeholder values

The future implementation may add a frontend-specific placeholder file at:

- `outputs/lekkadeall-frontend-shell/.env.example`

Recommended placeholder-only contents:

```dotenv
PUBLIC_APP_ENV=development
PUBLIC_APP_URL=http://localhost:4173
PUBLIC_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
PUBLIC_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

Rules:

- Placeholder strings only; never commit a real URL/key.
- Do not add `SUPABASE_SERVICE_ROLE_KEY` or any service-role variable name to the frontend `.env.example`.
- Do not copy payment, webhook, identity, messaging, admin, database-password, or JWT-signing variables from the backend `.env.example`.
- `PUBLIC_APP_ENV` must allow only `development`, `test`, or `production`.
- `PUBLIC_APP_URL` must be an absolute expected origin. Production must use HTTPS.
- `PUBLIC_SUPABASE_URL` must be HTTPS in production and must match the approved Supabase project host.
- `PUBLIC_SUPABASE_ANON_KEY` is the anon/public client credential only.
- The configuration loader must reject missing values and obvious placeholders before creating a client.
- Do not print values in console output, error messages, DOM data attributes, test snapshots, or analytics.

### Static-shell runtime configuration decision

Ticket 9A-1 has no bundler, so `.env` values are not automatically available to browser modules. Ticket 9A-2 implementation must choose and document one safe mechanism:

1. **Preferred while dependency-free:** deployment generates a non-secret `runtime-config.js` from the four public variables and serves it before `app.js`; real values remain uncommitted.
2. **If a production frontend framework is adopted:** use its documented public-variable mechanism, with only the four public values exposed.

Do not fetch environment configuration from an endpoint that also returns server-only configuration. Do not introduce a custom secret proxy.

## 3. Supabase public-client boundary

### Recommended module boundary

Create one future module, for example:

- `outputs/lekkadeall-frontend-shell/supabase-public-client.js`

Only this module may:

- import/load the Supabase browser library;
- read validated public runtime configuration;
- call `createClient(publicUrl, anonKey, authOptions)`; and
- export the singleton public client or narrow auth/read helpers.

No page component should create its own client.

### Client configuration rules

- Use the anon key only.
- Use browser PKCE flow for recovery/callback handling.
- Allow the Supabase client to manage its normal session lifecycle; do not create a second custom token store.
- Enable session persistence/refresh only through the library's reviewed defaults/options.
- Do not pass service-role, payment, webhook, identity, or admin configuration.
- Do not set global headers claiming a user ID, role, account status, provider approval, or admin authority.
- Do not override the authenticated user's JWT or RLS identity.
- Do not add a generic query helper that accepts arbitrary table names, column strings, filters, RPC names, or write methods.

### Narrow helper modules

Future helpers should be explicit and read-only, for example:

- `auth-session.js` — auth calls and session subscription only;
- `read-service-categories.js` — active-category projection only;
- `read-own-profile.js` — own profile projections only;
- `read-customer-dashboard.js` — minimal own customer lists only;
- `read-provider-status.js` — own provider status projection only.

Each helper should own a fixed table name, explicit column list, fixed safety filters, bounded limit, and safe error mapping.

### Dependency decision

Ticket 9A-1 deliberately has no package manifest or third-party dependencies. Before Ticket 9A-2 implementation, choose one reviewed Supabase JS delivery method:

- adopt a minimal package manifest and lock the official `@supabase/supabase-js` dependency; or
- use another integrity-pinned, reviewed delivery mechanism appropriate to the final hosting model.

Do not load an unpinned third-party script from a public CDN. Document and scan any new dependency in CI.

## 4. Allowed read queries

All examples below are plans for explicit projections, not implementation code. Queries must remain bounded and rely on current RLS.

### Public active service categories

Route:

- `/services`

Allowed table and projection:

```text
service_categories:
  id, slug, name
filter:
  active = true
order:
  name ascending
limit:
  bounded, for example 100
```

Notes:

- Current RLS already returns active categories only to anon/authenticated users.
- The client still adds `active = true` for clarity and defense in depth.
- Do not display or use inactive categories.
- `requires_manual_review` is not needed for Ticket 9A-2 display and should not be selected.

### Own route-resolution profile

Routes:

- all `/app/**`
- `/account-restricted`

Allowed projection:

```text
profiles:
  id, role, account_status
filter:
  id = authenticated user id
cardinality:
  zero or one
```

Purpose:

- determine whether an application profile exists;
- resolve active/restricted/suspended/closed state; and
- route customer/provider roles while denying support/admin/unknown roles.

Never use auth metadata as a fallback when this row is absent.

### Own safe settings profile

Route:

- `/app/settings`

Allowed projection:

```text
profiles:
  id, display_name, phone_e164, phone_verified_at, email_verified_at,
  suburb, city, avatar_path, role, account_status, created_at, updated_at
filter:
  id = authenticated user id
cardinality:
  zero or one
```

Display rules:

- read-only only;
- phone may be masked in summary contexts;
- avatar path must not be converted into a broad/public storage URL without a reviewed storage policy;
- role/status are labels, not editable controls.

### Own provider status

Routes:

- `/app/provider`
- provider view within `/app/settings`

Allowed projection:

```text
provider_profiles:
  user_id, business_name, bio, service_radius_km,
  verification_status, review_status, created_at, updated_at
filter:
  user_id = authenticated user id
cardinality:
  zero or one
```

Deliberately exclude:

- `verification_reference`;
- `bank_name_match`;
- `reviewed_by`;
- `reviewed_at`.

If no provider row exists, show “Provider setup is unavailable” and do not insert one.

### Minimal own customer request list

Route:

- `/app/customer`

Allowed projection, matching existing safe column grants:

```text
service_requests:
  id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at,
  created_at, updated_at
order:
  created_at descending
limit:
  bounded, for example 10 or 20
```

RLS limits customers to their own rows. Do not select:

- `customer_id`;
- deprecated `precise_address_ciphertext`;
- private address storage;
- any field not granted to the authenticated frontend role.

### Minimal own customer booking list

Route:

- `/app/customer`

Allowed projection:

```text
bookings:
  id, public_reference, request_id, bid_id,
  service_amount_minor, platform_fee_minor, currency,
  scheduled_start, status, completion_confirmed_at,
  created_at, updated_at
order:
  created_at descending
limit:
  bounded, for example 10 or 20
```

Current RLS permits booking parties to read only their bookings. Ticket 9A-2 should use this only for placeholder counts/cards. It should not join to another user's private `profiles` row or infer contact/address information.

### Minimal own customer payment-status list

Route:

- `/app/customer`

Allowed projection:

```text
payments:
  id, booking_id, status, amount_minor, currency,
  release_status, release_paused, refunded_minor,
  checkout_expires_at, created_at, updated_at
limit/order:
  bounded and aligned to the already-loaded own booking IDs
```

Rules:

- Read only when the current schema/grants expose each named field; verify the final migration result in integration tests before shipping.
- Do not select provider credentials, secrets, raw payloads, ledger rows, or internal release-control actor/reason fields.
- Do not follow or launch `checkout_url` in Ticket 9A-2.
- Every rendered payment/release state must display **“Mock/sandbox — no real money moved”**.
- If the explicit projection is rejected by current column grants, omit payment data and document the blocker. Do not broaden grants.

### Provider dashboard data in Ticket 9A-2

Ticket 9A-2 may read:

- own route-resolution profile;
- own provider status projection; and
- active service categories if needed for non-editable labels.

Do not add provider bids, open-request feed, booking, earnings, payment, release, or payout queries in Ticket 9A-2. Those require a separate reviewed read-model ticket even where existing RLS may permit some rows.

### Read orchestration rules

- Resolve session and own route profile before protected dashboard reads.
- Cancel/ignore stale responses when the auth user changes.
- Use bounded queries; no unbounded table scans.
- Avoid nested joins unless every relation and column has been separately reviewed under current RLS/grants.
- Parallelise independent own-dashboard reads only after route authorisation succeeds.
- Treat zero rows as an empty state, not as a reason to weaken security.
- Do not cache personal query results in localStorage, sessionStorage, a service worker, or persistent browser databases.

## 5. Blocked reads and actions

### Tables/data blocked from Ticket 9A-2

- `vendor_events`
- `payment_events`
- `refund_events`
- `audit_events`
- `identity_verifications`
- `disputes`
- `dispute_evidence`
- `reviews`
- `consents`
- `data_subject_requests`
- `private.service_request_addresses`
- deprecated `service_requests.precise_address_ciphertext`
- exact-address, identity-evidence, webhook, provider-secret, admin, bank, or payment-credential data

Even if a legacy policy permits some read, the feature remains out of scope and must not be queried.

### Blocked relations/joins

- arbitrary user/profile discovery;
- another customer's profile or account status;
- another provider's private provider profile;
- customer identity/contact enrichment for provider feeds;
- provider bank or verification-reference enrichment;
- unrestricted joins from bookings/payments into profiles;
- joins into event, audit, refund, dispute, review, consent, or identity tables.

### Blocked application actions

- all application-table insert/update/upsert/delete operations;
- profile or provider-profile editing;
- application profile creation after auth registration;
- service/provider-service mutation;
- request creation/publication/cancellation;
- bid submission/withdrawal/acceptance;
- booking progress/completion;
- exact-address submission/read/reveal;
- mock checkout creation or outcome recording;
- real checkout/payment-provider operations;
- refund request/decision/outcome;
- release/payout action;
- dispute/evidence;
- review;
- consent/data-subject-request;
- support case/chat/notification;
- identity verification;
- admin route/action;
- any RPC, including otherwise trusted marketplace functions, because Ticket 9A-2 is auth-and-read-only.

### Blocked auth behavior

- client-selected role;
- defaulting a missing profile to customer;
- treating `user_metadata.role` or `app_metadata.role` as application authority;
- redirecting to an arbitrary user-supplied URL;
- revealing whether an email/account exists in registration/recovery errors;
- storing a second copy of the session/token;
- exposing session/access/refresh tokens to logs, DOM, analytics, URLs, or application state snapshots.

### Missing safe read models

If implementation discovers that an intended projection is denied, ambiguous, overly broad, or requires an unsafe join:

1. keep the current Ticket 9A-1 placeholder/empty state;
2. record the exact missing UI field and denied projection;
3. open a separate planning/security review for a narrow view/RPC or column grant;
4. do not change migrations, RLS, grants, policies, or database functions inside Ticket 9A-2.

## 6. Safe error handling

### User-facing error categories

| Category | UI behavior |
|---|---|
| Configuration missing/placeholder | Fail closed before client creation; show “This environment is not configured” |
| Signed out/session expired | Clear personal data and show sign-in state |
| Invalid credentials | Generic sign-in failure; no account enumeration |
| Recovery requested | Always show neutral success text |
| Missing own profile | “Account setup is not available yet”; no client insert/fallback role |
| Restricted/suspended/closed | Route to restricted page with own status only |
| Unknown/support/admin role | Access denied; no admin route hint |
| RLS returns zero rows | Safe empty state |
| RLS/permission denial | Generic unavailable message; no policy/schema details |
| Network timeout/offline | Preserve no personal data, show retry for idempotent reads only |
| Malformed/unknown status | Display “Unavailable” and deny role-specific actions |

### Logging and telemetry rules

- No raw Supabase error object in production logs.
- No SQL, table policy name, JWT/session, key, email, phone, profile data, provider status, request description, booking/payment details, or query result in analytics.
- If operational logging is later added, record only a generated correlation ID, safe error category, route name, and non-sensitive timing.
- Do not include query strings from auth callback/recovery URLs.
- Clear rendered personal data immediately on sign-out, user change, or terminal session error.

### Race and stale-state handling

- Associate each protected read batch with the current authenticated user ID.
- Ignore/abort results if the session changes before completion.
- Never render previous-user data while a new session resolves.
- Use one route-resolution state machine rather than independent page guesses.
- Retry only safe GET/select operations, with a small bounded retry policy; never loop on permission errors.

## 7. Tests required for the future implementation ticket

No tests are added by this planning document.

### Public configuration tests

- missing public URL fails closed;
- missing anon key fails closed;
- obvious placeholder values fail closed outside explicit test mode;
- production requires HTTPS application and Supabase URLs;
- frontend configuration contains no service-role/payment/webhook/identity/admin variables;
- secret/value scanners find no real credential in source, static output, logs, snapshots, or source maps.

### Client-boundary tests

- exactly one public Supabase client is created;
- only public URL and anon key reach `createClient(...)`;
- no service-role client/module exists;
- auth uses the reviewed PKCE/session configuration;
- no generic arbitrary table/RPC/write helper exists;
- no page creates a client directly.

### Auth tests

- sign-in success resolves the own profile before selecting a dashboard;
- invalid sign-in is generic and does not enumerate accounts;
- registration does not send role/status/verification metadata;
- registration with no provisioned profile fails closed to account-setup unavailable;
- forgot-password response is neutral for existing and non-existing addresses;
- reset-password requires a valid recovery session;
- callback ignores authority-like query parameters;
- external/open redirect attempts are rejected;
- sign-out clears all rendered/in-memory personal data;
- expired/refreshed sessions update route state safely;
- switching users cannot briefly show the previous user's data.

### Route-guard tests

- signed-out users cannot render protected dashboard/settings data;
- active customer reaches customer/settings only;
- active provider reaches provider/settings only;
- customer cannot render provider status;
- provider cannot render the customer dashboard;
- restricted, suspended, and closed accounts route to restricted state;
- support, admin, null, and unknown roles route to access denied;
- missing profile does not default to customer;
- no `/admin` route is registered.

### Read-query contract tests

- active-category query uses only `id, slug, name`, active filter, name order, and bounded limit;
- own-profile route query uses only `id, role, account_status` and authenticated user ID;
- settings query uses only the explicit own-profile projection;
- provider-status query uses only the explicit own provider projection and excludes verification/bank/reviewer internals;
- customer request/booking/payment queries use the explicit projections and bounded limits;
- no query uses `select('*')`;
- no query references blocked tables/columns;
- RLS empty results render empty states without broader retries;
- permission errors do not trigger an RPC or elevated-client fallback.

### Static security tests

- frontend contains no `.insert(...)`, `.update(...)`, `.upsert(...)`, or `.delete(...)` application-data calls;
- frontend contains no application RPC calls;
- frontend contains no `admin_*`, `private.*`, mock webhook, cash marker, exact-address, payment-provider, or identity-provider calls;
- no payment method/card/CVV/bank-login forms exist;
- profile/settings has no save/edit mutation;
- required mock banner wording remains exact.

### Local Supabase integration/RLS tests

Use deterministic local test users/data only:

- anon can read active categories and cannot read inactive categories;
- signed-in user reads only their own profile;
- customer reads only their own requests/bookings/payments under current grants;
- provider reads only their own provider status;
- unrelated customer/provider rows remain hidden;
- restricted account route resolution uses only its own profile status;
- blocked tables remain unread from the browser role;
- no application table can be mutated through Ticket 9A-2 frontend paths.

### Regression and CI tests

- extend the dependency-free Node frontend tests or adopt a justified minimal frontend test setup;
- keep the Ticket 9A-1 route/safety tests green;
- run existing Deno mock-webhook tests;
- run `supabase db reset` and every existing pgTAP file;
- add dependency/lockfile and production-bundle secret scans if Supabase JS introduces a package/build step.

## 8. Definition of done for a future Ticket 9A-2 implementation

Ticket 9A-2 implementation is complete only when all applicable conditions below are satisfied.

### Public client and configuration

- A single reviewed Supabase public-client boundary exists.
- It uses only `PUBLIC_SUPABASE_URL` and `PUBLIC_SUPABASE_ANON_KEY` from validated public configuration.
- `.env.example` contains placeholders only and no frontend service-role/provider/webhook/identity/admin variable.
- Real values are uncommitted and supplied through the approved local/deployment mechanism.
- Missing/placeholder configuration fails closed.

### Authentication and sessions

- Sign-in, forgot-password, reset-password, callback, and sign-out work through Supabase Auth.
- Registration creates only an auth user unless secure profile provisioning has already been delivered by a separate authorised backend ticket.
- Registration never directly inserts `public.profiles` and never selects a role/status.
- A registered user without a profile receives an honest account-setup-unavailable state.
- Session-backed route guards resolve own profile/account/role before protected data is displayed.
- Restricted/suspended/closed, missing-profile, support/admin, and unknown-role states fail closed.
- Open redirects and authority-like callback parameters are rejected.

### Safe reads

- `/services` reads active category `id, slug, name` only.
- `/app/settings` reads own explicitly projected profile/status fields only and remains read-only.
- `/app/provider` reads only the own minimal provider-status projection.
- `/app/customer` reads only the approved minimal own request/booking/payment placeholder projections that pass current RLS/grants.
- Any unavailable projection remains a documented placeholder instead of triggering a security change.
- No query uses `select('*')`, unbounded results, unsafe joins, or persistent browser caching of personal data.

### Prohibited capability confirmation

- No application-table insert/update/upsert/delete exists in frontend code.
- No application RPC is called.
- No admin route/dashboard/function exists.
- No profile editing exists.
- No exact-address submission/read/reveal exists.
- No request, bid, booking-completion, refund, payout, dispute, review, consent, support-case, chat, identity, mock-checkout, real-payment, or real-provider workflow exists.
- No migrations, RLS, grants, policies, database functions, private functions, or webhook code changed.
- No service-role key or real credential is present.

### Testing and documentation

- All configuration, client-boundary, auth, route-guard, query-contract, static-security, integration, and stale-session tests pass.
- Ticket 9A-1 frontend tests remain green.
- Existing Deno webhook and pgTAP database suites remain green in CI.
- Documentation records environment setup, allowed queries, registration/profile-provisioning blocker, local preview/test commands, and every deliberately blocked capability.

### Profile-provisioning dependency

Ticket 9A-2 may be considered complete with registration visibly blocked after auth-account creation if secure application-profile provisioning is still unavailable. It must not claim that onboarding is complete.

A later full-registration milestone requires a separate backend ticket that:

- creates the application profile through a trusted server/database path;
- fixes/defaults the allowed initial role through reviewed business rules;
- prevents privileged metadata injection;
- is idempotent and audited where appropriate; and
- has positive and negative pgTAP/integration tests.

## Explicit non-goals

This planning ticket does not:

- implement code;
- add a Supabase dependency or client;
- add environment files or credentials;
- add a service-role key;
- add or change migrations, RLS, grants, policies, database functions, or webhooks;
- create application profiles;
- implement profile editing;
- implement admin UI/actions;
- implement exact-address submission/reveal;
- implement marketplace mutations;
- implement identity, payment-provider, refund, payout, dispute, review, consent, support, notification, or chat workflows;
- weaken any protection delivered through Tickets 1–9A-1.
