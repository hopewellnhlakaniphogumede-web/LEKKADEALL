# Ticket 9A-9 — Customer draft lifecycle E2E plan

## Status

Planning only. This document does not add Playwright, browser tests, dependencies, test users, fixtures, credentials, migrations, frontend behavior, database behavior, grants, policies, functions, or CI steps.

The existing Node frontend tests, Deno webhook tests, and pgTAP database tests remain the current executable verification boundary. A future implementation ticket must be reviewed before adding the E2E tooling described here.

## Goal

Plan an end-to-end verification boundary for the completed safe customer draft lifecycle delivered by Tickets 9A-1 through 9A-8 and Ticket 9B:

```text
register or sign in
  → receive the Ticket 9B customer/active profile
  → enter the customer dashboard
  → create a validated draft
  → find the draft in the own-request list
  → view the draft detail
  → edit the exact owned draft
  → cancel the exact owned draft
  → confirm the cancelled state through a fresh RLS-backed read
```

The future tests must exercise the real frontend, local Supabase Auth, applied migrations, trusted RPCs, RLS, database validation, and browser behavior together. They must not create a second application implementation inside the test suite or substitute mocked authorization for the real local security boundary.

Publication, exact-address handling, provider bidding, booking actions, payments, admin functionality, and profile editing remain outside this ticket and must be verified as absent.

## Existing foundation under test

The E2E suite must treat the following implemented behavior as the system under test, not reimplement it in fixtures:

1. Ticket 9A-1 provides the static frontend shell, routes, safe states, navigation, and exact mock-payment banner wording.
2. Ticket 9A-2 provides the anon-only Supabase browser client, Auth flows, session/profile route guards, active-category reads, and explicit safe projections.
3. Ticket 9B provisions exactly one `public.profiles` row for a normal Auth registration using fixed `customer` and `active` defaults without trusting Auth metadata.
4. Ticket 9A-3 creates a draft only through `customer_create_draft_request(...)`, with exact-address ciphertext fixed to null.
5. Ticket 9A-5 validates and canonicalises every eventually public request text field at the database boundary and retains a table-trigger backstop.
6. Ticket 9A-6 reads only the customer's RLS-visible request list/detail fields with explicit projections.
7. Ticket 9A-7 cancels only an owned, internally consistent draft through `customer_cancel_draft_request(...)`.
8. Ticket 9A-8 updates only an owned, internally consistent draft through `customer_update_draft_request(...)` and reuses the Ticket 9A-5 validator.
9. Tickets 1, 2, 5, and 6 continue to protect role/account authority, RLS, exact addresses, and marketplace state transitions.

## Executive recommendation

### Add Playwright Test in the future implementation ticket

Use a pinned version of `@playwright/test` as a frontend development dependency and start with the bundled Chromium project only.

Playwright is recommended because this ticket needs capabilities that the current Node tests do not provide together:

- real navigation across the static route files;
- real Supabase PKCE Auth/session behavior;
- form interaction and visible-state assertions;
- multiple isolated browser contexts for two customers;
- request/response observation without changing application code;
- storage, history, console, and Cache Storage inspection;
- single-flight and stale-state interaction checks; and
- deterministic control of a local frontend server from the test runner.

The existing Node tests remain the fast component/contract layer. Playwright must not replace the 53 frontend tests, pgTAP suites, or Deno webhook tests.

Do not adopt a general-purpose browser automation wrapper, Cypress, or a custom Selenium harness at the same time. One pinned browser framework and one Chromium project are enough for the first E2E boundary. Cross-browser expansion should be a later reliability ticket after the security journey is stable.

### Test the real local stack

The core lifecycle must run against:

- the static frontend served from `outputs/lekkadeall-frontend-shell`;
- the pinned local `@supabase/supabase-js` bundle already used by the browser;
- a fresh disposable Supabase CLI stack;
- a database reset from committed migrations;
- local Supabase Auth and Inbucket only;
- synthetic fixture rows created after reset; and
- the real RLS policies, grants, triggers, private validators, and trusted functions.

Do not mock Supabase Auth, PostgREST, RPC results, RLS, or database state for the main happy-path journey. Focused UI error tests may intercept a response only where the purpose is to test an ambiguous transport failure; they must be clearly separate from security-boundary tests.

### Separate browser authority from fixture authority

Use two deliberately separate processes:

1. **Browser data plane:** receives only the local Supabase URL and local anon key. It signs up and signs in normally and can perform only the reads and three reviewed customer draft RPCs available to the application.
2. **Local fixture controller:** runs outside the browser, connects only to the disposable local PostgreSQL instance, inserts synthetic setup rows, creates negative-state fixtures, and verifies private postconditions. It must refuse every non-loopback database/API host.

The fixture controller must not be bundled into browser code or served by the frontend. Prefer a local PostgreSQL test connection over a Supabase service-role client so no service-role key is needed at all. Local connection values must be discovered at runtime, held in process memory, never committed, never printed, and never exported to the browser.

Fixture SQL is test setup, not a migration. A future implementation must not add E2E-only schema, production functions, grants, policies, triggers, or persistent seed data.

## Proposed future file layout

The exact names may be adjusted during implementation review, but the recommended boundary is:

```text
outputs/lekkadeall-frontend-shell/
  playwright.config.mjs
  tests/e2e/
    customer-draft-lifecycle.spec.mjs
    auth-and-route-guards.spec.mjs
    rls-and-privacy.spec.mjs
    blocked-features.spec.mjs
    support/
      local-environment.mjs
      local-fixtures.mjs
      network-policy.mjs
      privacy-audit.mjs
```

Expected future updates are limited to the frontend package/lock file, ignored local runtime configuration, `TESTING.md`, `hardening_progress.md`, and the CI workflow. No migration or application feature should be required for Ticket 9A-9. If an E2E test cannot be written without changing production authority, stop and document the blocker.

## Disposable local environment

### Preconditions

The future implementation requires:

- Docker Desktop or Docker Engine;
- the same pinned Supabase CLI approach used by GitHub Actions;
- Node.js and pnpm;
- the existing locked frontend dependencies;
- the pinned Playwright package and Chromium binary; and
- ports dedicated to the local Supabase project and frontend server.

The test bootstrap must fail before opening a browser unless all Supabase API, database, Auth, Inbucket, and application URLs resolve to `localhost`, `127.0.0.1`, or the isolated runner's approved loopback equivalent. Production and remote Supabase project references must be rejected even if supplied accidentally.

### Reset and startup order

The recommended order is:

1. Install dependencies from the committed lock file.
2. Start the local Supabase stack from `outputs/marketplace-production-foundation`.
3. Run `supabase db reset` so every committed migration, including Tickets 9B and 9A-5/7/8, is applied from a clean database.
4. Run the local-only fixture controller to add the minimum active service category and negative-state synthetic accounts required by the suite.
5. Generate an ignored `runtime-config.local.js` containing only:
   - `PUBLIC_APP_ENV=e2e`;
   - the loopback frontend URL;
   - the loopback Supabase API URL; and
   - the local anon key.
6. Start the static frontend server and wait for an HTTP health check.
7. Run Playwright with one worker and no retries for mutation tests.
8. Run local database postcondition checks.
9. Close browser contexts, delete the generated runtime configuration and temporary test files, reset or stop Supabase with `--no-backup`, and terminate the frontend server in an always-run cleanup block.

The proposed future local command should be a single reviewed script such as `pnpm run test:e2e:local`. That script does not exist yet. It should orchestrate the steps above and refuse to run against a non-loopback target.

### Auth redirect configuration

Use one canonical loopback origin consistently, preferably `http://127.0.0.1:4173`, for the frontend base URL, runtime configuration, Playwright base URL, Auth site URL, and redirect allowlist.

The disposable local Supabase Auth configuration must allow only the exact local callback and recovery routes needed by these tests:

```text
http://127.0.0.1:4173/auth/callback
http://127.0.0.1:4173/auth/reset-password
```

Do not add a production origin, wildcard redirect, deployment preview origin, or remote callback to support E2E. Any future local `config.toml` adjustment must remain credential-free and must not loosen production redirect configuration.

### Isolation and determinism

- Run the state-changing lifecycle serially with one Playwright worker.
- Use a unique run ID in every synthetic email and database fixture.
- Never depend on rows left by a previous local or CI execution.
- Use condition-based waits for routes, DOM states, and observed network completion. Do not use arbitrary sleeps.
- Freeze or explicitly calculate future SAST fixtures so requested dates cannot become past during a run.
- Keep one browser context per actor and never reuse authentication storage between Customer A and Customer B.
- Do not save Playwright `storageState` files to disk.

## Synthetic accounts and data

### Account set

| Actor | Creation method | Purpose |
|---|---|---|
| Fresh Customer A | Register through the real UI | Full lifecycle and Ticket 9B provisioning |
| Customer B | Register through the real UI in an isolated context | Cross-customer RLS checks |
| Restricted customer | Synthetic local Auth user/profile fixture | Restricted route state |
| Suspended customer | Synthetic local Auth user/profile fixture | Suspended route state |
| Closed customer | Synthetic local Auth user/profile fixture | Closed route state |
| Missing-profile user | Register normally, then remove only the synthetic profile through the local fixture controller | Fail-closed missing-profile behavior |
| Provider-role fixture | Synthetic local-only protected profile state | Customer-route wrong-role behavior |

Use reserved `.test` email domains, for example `customer-a+<run-id>@lekkadeall.invalid`, and randomly generated test passwords held only in process memory. Do not print passwords, access tokens, refresh tokens, PKCE verifiers, Auth codes, local database passwords, or complete request bodies.

Normal registration must not submit role, account status, provider status, verification state, admin/support authority, identity data, payment state, address data, or arbitrary metadata.

An unknown role cannot be persisted through the current `public.user_role` enum without corrupting the schema boundary. Keep the existing unit test for the defensive unknown-role branch; do not alter the enum or bypass constraints merely to create an E2E fixture.

### Minimum marketplace fixture data

After every database reset, add only:

- one active synthetic service category for successful create/edit tests;
- one inactive synthetic category for denied/stale-category behavior where needed; and
- narrowly scoped negative-state requests needed for RLS or stale-state tests.

The main Customer A request must be created through the UI and `customer_create_draft_request(...)`, not inserted by the fixture controller.

Use clearly synthetic, Ticket 9A-5-safe values such as a generic service title, description, suburb, and city. Do not use real names, phone numbers, emails inside public fields, street addresses, GPS coordinates, access codes, or real customer descriptions.

## Customer journey test cases

### E2E-01 — Signed-out route protection

1. Open the customer dashboard, request list, new-request route, detail route, and edit route without a session.
2. Confirm each fails closed into the existing signed-out/sign-in-required behavior.
3. Confirm no profile, request, or mutation network call is made before the session decision permits it.
4. Confirm `/admin` is not an implemented application route.

### E2E-02 — Registration and Ticket 9B provisioning

1. Register Fresh Customer A through `/auth/register` with only synthetic email and password.
2. Observe the Auth request in memory and assert that no role, account status, provider status, verification status, admin/support authority, identity/payment/address value, or arbitrary user/app metadata is submitted.
3. Complete the local confirmation/session behavior configured for the disposable Auth service.
4. Confirm the browser reaches the customer route only after resolving the own RLS-protected profile.
5. Through the local postcondition inspector, verify exactly one matching profile exists with:
   - `id` equal to the Auth user ID;
   - `role = customer`;
   - `account_status = active`;
   - the approved neutral display name; and
   - no provider profile.
6. Confirm no browser request directly inserts or deletes `public.profiles`.

### E2E-03 — Sign out and sign in

1. Sign Customer A out through the UI.
2. Confirm personal in-memory views are cleared and protected navigation fails closed.
3. Sign in again through `/auth/sign-in`.
4. Confirm the route decision again comes from the own protected profile, not Auth metadata or a query parameter.

### E2E-04 — Customer dashboard and active categories

1. Confirm Customer A reaches `/app/customer`.
2. Confirm active service categories are displayed from the approved explicit projection.
3. Confirm the inactive fixture category is not offered.
4. Confirm loading, empty, and safe error states do not expose query details or hidden fields.

### E2E-05 — Draft creation

1. Navigate from the dashboard to `/app/customer/requests/new/`.
2. Confirm only category, title, description, suburb, city, requested start in SAST/UTC+2, and optional ZAR budget are present.
3. Confirm the exact privacy warning is visible.
4. Enter synthetic safe content and submit once.
5. Assert exactly one `customer_create_draft_request(...)` request occurs, its reviewed payload is complete, and `p_precise_address_ciphertext` is null.
6. Confirm the UI displays success only after the RPC responds with a valid request UUID.
7. Confirm “View draft” and “View all requests” are available.
8. Through local postcondition inspection, confirm exactly one owned `draft` exists and no private address, bid, booking, payment, refund, payout, dispute, provider-selection, or publication state was created.

### E2E-06 — Own-request list

1. Open `/app/customer/requests` through the dashboard and post-create action.
2. Confirm the new draft is visible with only the approved summary fields.
3. Confirm list ordering is newest-first and the request count never exceeds the 20-row boundary when bounded synthetic fixtures are used.
4. Confirm category label fallback remains safe if a historical category is unavailable.
5. Confirm database text is rendered as text and not interpreted as HTML.

### E2E-07 — Draft detail

1. Navigate using only the opaque request UUID.
2. Confirm the detail route re-reads through RLS and shows the approved projection only.
3. Confirm dates are labelled/formatted for Africa/Johannesburg and the budget is display-only ZAR.
4. Confirm a draft exposes “Edit draft” and “Cancel draft,” but no publication or other workflow action.

### E2E-08 — Draft edit

1. Open the dedicated edit route from the freshly read draft detail.
2. Confirm only the seven reviewed editable fields are prefilled.
3. Change several safe public fields, requested start, category, and budget.
4. Assert exactly one `customer_update_draft_request(...)` call with the exact reviewed eight-parameter payload.
5. Confirm there is no optimistic success and no automatic retry.
6. Confirm success appears only after a fresh draft-only RLS read returns the same UUID and server values.
7. Confirm the detail and list display the canonical updated values.
8. Through local postcondition inspection, confirm ownership, status, workflow timestamps, address state, bids, bookings, and payment state remain unchanged, and the audit event contains only the approved fixed metadata.

### E2E-09 — Draft cancellation

1. Return to the freshly read draft detail.
2. Confirm cancellation is absent from the list and present only on the eligible detail.
3. Confirm the fixed confirmation copy is used and no reason/free-text field exists.
4. Submit once and assert exactly one `customer_cancel_draft_request(...)` call containing only `p_request_id`.
5. Confirm no optimistic state change and no automatic retry.
6. Confirm success appears only after a fresh RLS read reports `cancelled`.
7. Confirm edit and cancellation controls disappear after cancellation.
8. Confirm the cancelled request remains readable in the own-request list/detail but cannot be edited or cancelled again.
9. Through local inspection, confirm exactly one privacy-safe cancellation audit event and no change to request content or ownership.

### E2E-10 — Recovery route smoke test

Use a separate synthetic account to verify forgot-password, local Inbucket delivery, recovery callback, URL cleanup, reset-password submission, and subsequent sign-in. Keep the recovery token and link in test-runner memory only. Never print or attach the Inbucket message or complete recovery URL.

This test is separate from the Customer A mutation journey so a recovery failure cannot leave the main lifecycle half-complete.

## Negative and security test cases

### Route and account-state failures

- Missing profile fails closed without creating a browser profile row.
- Restricted, suspended, and closed profiles reach the existing restricted state and cannot read or mutate customer requests.
- A provider-role fixture cannot enter customer routes or call customer draft functions successfully.
- Clearing or invalidating the synthetic local session causes protected routes to fail closed.
- Malformed and missing request IDs produce the same generic unavailable state without a request query for malformed input.

### Cross-customer RLS

1. Customer B creates a synthetic draft through the same trusted UI flow in a separate context.
2. Customer A attempts to open Customer B's UUID through list/detail/edit URLs.
3. Confirm the row is absent from Customer A's list and detail/edit return the same generic unavailable state used for a missing UUID.
4. Confirm no owner identity, title, status, category, or existence signal leaks.
5. Confirm Customer A cannot edit or cancel Customer B's draft.

### Validation and stale-state behavior

- Unsafe public-field examples are stopped by frontend defence-in-depth without a mutation request.
- A focused permitted-RPC probe using an authenticated synthetic test client may confirm the Ticket 9A-5 database boundary rejects a hostile value; it must not use direct table DML and must not log the value. pgTAP remains the exhaustive hostile-input and South African false-positive suite.
- If the request changes away from `draft` after the page read, edit and cancellation must receive the generic safe rejection and must not claim success.
- If a bid, provider-selection signal, booking, inconsistent timestamp, or deprecated address residue is inserted by the local fixture controller after the page read, edit/cancellation must fail closed. These fixtures remain local and synthetic.
- An inactive category or a requested start that has become past must fail safely.
- Double-click or repeated submit events must result in one mutation request.
- A deliberately aborted/offline mutation response must show the ambiguous safe message, must not retry automatically, and must require a fresh route read before another attempt.

### Network policy assertions

Attach an in-memory Playwright request observer that fails the test if browser application traffic includes:

- POST, PATCH, PUT, or DELETE requests to application-table REST endpoints;
- a broad-column selection instead of an explicit projection;
- `customer_publish_request(...)`;
- exact-address upsert/read/reveal functions;
- legacy `customer_cancel_request(...)`;
- provider, bid, booking, completion, payment, checkout, refund, payout, dispute, review, consent, support, notification, chat, identity, profile-update, or admin functions;
- a non-loopback API host; or
- a service-role authorization value.

The observer may record method, loopback host, endpoint class, status, and timing in memory. It must not record authorization headers, query values containing user data, request bodies, response bodies, Auth codes, or tokens.

The expected application mutation allowlist is exactly:

- `customer_create_draft_request(...)` during creation;
- `customer_update_draft_request(...)` during editing; and
- `customer_cancel_draft_request(...)` during cancellation.

## Browser storage and privacy verification

### Required checks

Before registration, after each lifecycle step, after sign-out, and during cleanup, inspect:

- the current URL and browser history entries available to the test;
- `localStorage` keys and values;
- `sessionStorage` keys and values;
- IndexedDB database names and records;
- Cache Storage names and entries;
- registered service workers;
- cookies;
- console messages and page errors; and
- generated Playwright output/artifacts.

Assert that none contains request title, description, suburb, city, requested start, budget, category label, exact address, contact data, profile role/status, audit details, email/password, Auth code, PKCE verifier, access token, refresh token, or RPC body, except for the narrowly documented Auth-session exception below.

Only an opaque request UUID may appear in the approved detail/edit query parameter. Form content must never appear in a URL. Auth callback and recovery `code` parameters are necessarily transient inputs from Supabase PKCE; the application must remove them immediately with history replacement before rendering the authenticated destination. The complete callback/recovery URL must never enter logs or artifacts.

### Existing persisted Auth-session exception

The current reviewed Supabase browser client sets `persistSession: true`. Supabase therefore stores its Auth session in browser storage. An E2E assertion claiming that **no sensitive value of any kind** is ever present in browser storage would be false under the current architecture.

Ticket 9A-9 should interpret the privacy requirement as:

- no marketplace request content, private profile content, exact address, contact/payment data, application authorization state, or custom form state is persisted by LEKKADEALL; and
- the only permitted browser-storage entry while signed in is the expected Supabase SDK Auth-session record required by the existing session design.

The storage audit must allowlist the exact SDK-owned Auth key shape without snapshotting or printing its value. It must confirm that sign-out removes the persisted session and that no application-specific storage entry remains.

If product policy requires zero bearer tokens in browser storage, that is a separate Auth architecture change—likely a reviewed server/BFF and secure HttpOnly cookie boundary. It must be planned and implemented in another ticket before the E2E suite can assert zero sensitive browser storage. Ticket 9A-9 must not silently change `persistSession`, break the existing session flow, or claim the stronger property prematurely.

### Artifact policy

CI must disable authenticated-flow screenshots, video, traces, HAR files, DOM snapshots, and saved storage state by default, including on failure. Synthetic data reduces privacy impact but does not make Auth tokens or recovery links safe to publish as artifacts.

Use a text/line reporter with static test names and redacted fixed failure messages. Do not attach browser console output, network bodies, Inbucket messages, database dumps, or runtime configuration. A future opt-in local debug mode may capture artifacts only outside CI and must display a warning that the developer is responsible for deletion and redaction.

## Blocked-feature verification

The future suite must assert that the customer journey contains no:

- publication button, route action, or publish RPC;
- exact-address input, storage, ciphertext creation, read, reveal, KMS, encryption, GPS, geolocation, or map control;
- provider feed, onboarding, selection, profile, contact, or bidding control;
- booking creation, confirmation, completion, cancellation, or dispute control;
- payment method, card, CVV, bank-login, checkout, cash, off-platform payment, refund, or payout control;
- admin route/dashboard/action;
- profile editing form or mutation;
- request deletion, duplication, reopening, archiving, or post-cancellation edit;
- service-role key or privileged browser client;
- direct application-table insert/update/upsert/delete; or
- broad-column query.

Absence checks should combine DOM assertions with the in-memory network policy. Searching only visible button text is insufficient.

## CI integration approach

### Separate isolated job

In the future implementation, add a dedicated `customer-draft-lifecycle-e2e` job to the existing GitHub Actions workflow or a narrowly scoped companion workflow. It should run only after the existing frontend, Deno, migration-reset, and pgTAP security job succeeds.

The E2E job should:

1. use read-only repository permissions;
2. install dependencies from lock files;
3. install only the pinned Playwright Chromium build;
4. start a new disposable local Supabase stack;
5. reset migrations from scratch;
6. create only synthetic fixtures;
7. serve the static frontend on loopback;
8. run one worker with mutation retries disabled;
9. run privacy-safe local postcondition checks;
10. perform always-run cleanup; and
11. upload no authenticated browser artifact, database dump, Auth email, trace, video, screenshot, HAR, storage state, or secret-bearing log.

Do not configure GitHub environment secrets, production Supabase variables, production payment/provider values, or a remote deployment URL. The job must derive local endpoints and the local anon key from the disposable Supabase process and must verify they are loopback before use.

### Failure handling

- A failed mutation test must not be retried automatically at the Playwright or workflow level.
- The lifecycle spec should stop after an ambiguous mutation result rather than create duplicates.
- The cleanup step must run even when setup or a test fails.
- CI output should report only the static case ID and a fixed diagnostic category such as route mismatch, unexpected endpoint class, storage-policy violation, or postcondition mismatch.
- Do not print DOM content, request/response bodies, tokens, recovery links, passwords, or database rows to make CI debugging easier.

### Gate ordering

The future pull-request gate should remain:

```text
Node frontend contract tests
  → Deno mock-webhook tests
  → clean migration reset and all pgTAP suites
  → isolated Playwright customer lifecycle E2E
```

The E2E suite is an additional integration signal. It must never replace the lower-level database tests that prove denied execution, RLS, trigger, audit rollback, locking, and hostile-client behavior more precisely.

## Risks and limitations

1. **Persisted Auth tokens:** the existing session architecture stores the Supabase Auth session in browser storage. The suite can prove no extra application/request data is stored, but zero sensitive browser storage requires a separate Auth architecture decision.
2. **Local versus hosted parity:** local Supabase Auth, PostgREST, and PostgreSQL are strong integration coverage but do not prove production redirect, email, proxy, CDN, CSP, or deployment configuration.
3. **Chromium-only first pass:** Chromium verifies the security journey but does not establish Safari/WebKit or Firefox compatibility.
4. **E2E cannot replace pgTAP:** browser-visible generic failures cannot prove every internal lock, grant, audit rollback, trigger, or race invariant. Those remain database-test responsibilities.
5. **Recovery timing:** Inbucket and PKCE events are asynchronous. Tests must poll deterministic local endpoints with deadlines and keep links in memory, not use sleeps or logs.
6. **RLS non-disclosure:** missing and cross-customer rows intentionally look identical. Tests must assert the generic outcome, not attempt to reveal the hidden reason through UI diagnostics.
7. **Fixture authority:** local owner-level fixture setup can create impossible negative states. It must stay outside application bundles and may only prepare/inspect a disposable local database.
8. **Shared-state races:** parallel workers can make draft counts, current status, and synthetic email reuse nondeterministic. The state-changing journey must remain serial until each test owns a fully independent database.
9. **Artifacts:** standard Playwright failure artifacts can expose synthetic credentials, tokens, request content, or recovery links. They remain disabled in CI.
10. **Provider/payment coverage:** the mock-payment banner may be checked for exact wording, but no checkout, webhook, real provider, refund, payout, or financial lifecycle belongs in this ticket.
11. **Publication readiness:** a green draft lifecycle does not make publication or exact-address handling ready. Ticket 9A-4 blockers remain unchanged.

## Definition of done for a future implementation ticket

Ticket 9A-9 implementation is complete only when all of the following are true:

1. A pinned Playwright Test dependency and Chromium project are reviewed and locked without removing the existing Node test runner.
2. One command starts a disposable local-only Supabase stack, resets all migrations, creates synthetic fixtures, serves the frontend, runs E2E, and cleans up without production credentials.
3. The bootstrap refuses non-loopback Supabase, database, Auth, Inbucket, and frontend targets.
4. The browser receives only the local public URL and anon key; no service-role key, database credential, webhook secret, payment/provider credential, identity secret, or admin credential enters browser code or served files.
5. Fresh UI registration creates exactly one matching `customer`/`active` profile through Ticket 9B, ignores client authority metadata, and creates no provider profile.
6. Registration, sign out, sign in, dashboard access, draft creation, list, detail, edit, cancellation, and fresh cancelled-state confirmation pass against the real local stack.
7. Customer A cannot discover, read, edit, or cancel Customer B's request, and generic RLS-hidden/not-found behavior is preserved.
8. Restricted, suspended, closed, missing-profile, wrong-role, signed-out, invalid-session, malformed-ID, stale-state, validation, and ambiguous-network states fail closed with safe UI messages.
9. The request observer proves there is no direct application-table DML, broad-column query, blocked RPC, service-role authorization, or non-loopback backend request.
10. Creation calls only `customer_create_draft_request(...)` and always sends null exact-address ciphertext; editing calls only `customer_update_draft_request(...)`; cancellation calls only `customer_cancel_draft_request(...)` with its fixed payload.
11. Database postconditions confirm no publication, address, provider-selection, bid, booking, payment, refund, payout, dispute, identity, profile-edit, or admin state is created by the journey.
12. URL, history, storage, IndexedDB, Cache Storage, service-worker, cookie, console, and artifact checks prove no marketplace/private form content is persisted or emitted.
13. The expected Supabase persisted Auth-session entry is narrowly allowlisted, never printed or saved, and removed on sign-out; any requirement for zero stored bearer tokens is documented as a separate blocker rather than misreported as passing.
14. CI runs the E2E job only against a fresh local stack, with one worker, no mutation retries, always-run cleanup, and no authenticated screenshots, video, traces, HAR, storage state, Auth emails, or database dumps.
15. All existing frontend, Deno webhook, profile provisioning, public-field validation, RLS, state-machine, address-privacy, draft cancellation, draft update, payment, refund, payout, and webhook tests remain green.
16. Publication, exact-address handling, provider bidding, booking actions, payments, admin dashboard, and profile editing remain absent.
17. No migration, RLS policy, grant, production function, security trigger, role/status protection, address-privacy control, public-field validator, state-machine guard, draft-cancellation boundary, or draft-update boundary is weakened to make E2E pass.

Until every item above is implemented and CI-verified, Ticket 9A-9 remains planning-only and cannot be used as evidence that publication, exact-address handling, provider interaction, booking, or payment features are ready.
