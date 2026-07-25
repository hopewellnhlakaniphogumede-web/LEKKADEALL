# LEKKADEALL testing guide

## Frontend shell, database, and webhook route tests in CI

GitHub Actions runs the Ticket 9A-7 strict draft-cancellation tests, Ticket 9A-6 customer request read tests, Ticket 9A-5 server public-field validation tests, Ticket 9A-3 draft-creation tests, Ticket 9A-1/9A-2 frontend regressions, mock payment webhook route tests, and Supabase database hardening tests on every push and pull request.

Workflow file:

- `.github/workflows/database-tests.yml`

The workflow runs on `ubuntu-latest`, installs the exact locked Supabase browser package with pnpm, uses Node's built-in test runner for the frontend, installs Deno, runs the mock payment webhook route tests, verifies Docker is available, installs the Supabase CLI, verifies the committed local Supabase config, starts the local Supabase stack, applies all local migrations with `supabase db reset`, then runs the pgTAP database tests.

It does not use production secrets. It uses only:

- a frozen frontend lockfile, the pinned public Supabase browser package, and Node built-in tests under `outputs/lekkadeall-frontend-shell`
- deterministic mock webhook test values in application tests
- local Supabase migrations under `outputs/marketplace-production-foundation/supabase/migrations`
- committed non-secret local Supabase config at `outputs/marketplace-production-foundation/supabase/config.toml`
- mock payment webhook route tests under `outputs/marketplace-production-foundation/supabase/functions/payment-webhook`
- local pgTAP tests under `outputs/marketplace-production-foundation/supabase/tests/database`
- deterministic test seed data from `rls_test_seed.inc`

CI does not run `supabase init`. The local config is committed so the test environment is deterministic and repeatable. The workflow also checks that the config does not contain obvious secret markers or production Supabase project references.

## Tests run by CI

From `outputs/marketplace-production-foundation`, CI runs:

```bash
pnpm install --dir ../lekkadeall-frontend-shell --frozen-lockfile
node --test ../lekkadeall-frontend-shell/tests/*.test.mjs
deno test supabase/functions/payment-webhook/index.test.ts
supabase db reset
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/profile_provisioning.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
supabase test db supabase/tests/database/public_field_validation.test.sql
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
supabase test db supabase/tests/database/customer_draft_cancellation.test.sql
supabase test db supabase/tests/database/customer_draft_update.test.sql
supabase test db supabase/tests/database/payments_ledger.test.sql
supabase test db supabase/tests/database/refunds_ledger.test.sql
supabase test db supabase/tests/database/cash_payment_policy.test.sql
supabase test db supabase/tests/database/payout_release_controls.test.sql
supabase test db supabase/tests/database/mock_payment_checkout.test.sql
supabase test db supabase/tests/database/payment_webhooks.test.sql
```

The workflow fails if any migration or pgTAP test fails.

## How to read CI results

In GitHub:

1. Open the repository.
2. Go to the **Actions** tab.
3. Open the **Supabase database tests** workflow run for your push or pull request.
4. Open the **Run webhook route, Supabase migrations, and pgTAP tests** job.
5. Review the failing step.

Common useful steps:

- **Run Ticket 9A-7 cancellation and existing frontend tests**: all earlier shell/Auth/draft/read regressions plus detail-only draft cancellation, fixed confirmation without a reason field, the exact allowlisted RPC payload, single-flight behavior, no optimistic update or automatic retry, a fresh RLS-backed detail re-read before success, generic safe errors, and no legacy cancellation/publication/direct DML/broad selects/blocked features.
- **Apply migrations with database reset**: migration/schema errors usually appear here.
- **Run mock payment webhook route tests**: raw-body HMAC verification, missing/invalid signatures, stale timestamps, exact payload hashing, no database call before verification, safe metadata forwarding, runtime-only mock secret/app-env config, and production mock-mode fail-closed behavior.
- **Run role escalation pgTAP tests**: role, provider verification, privileged-column, and audit protections.
- **Run baseline RLS pgTAP tests**: table-level RLS, service categories, provider services, vendor events, and baseline privacy protections.
- **Run secure profile provisioning pgTAP tests**: `auth.users` trigger provisioning, fixed customer/active defaults, hostile metadata rejection, idempotency/no-overwrite behavior, privacy-safe audit events, existing-user backfill, frontend insert/delete denial, own-profile RLS, and Ticket 1/2 regression checks.
- **Run exact address privacy pgTAP tests**: exact address isolation, safe request summaries, confirmed-booking reveal, address audit events, and public-description address checks.
- **Run server public-field validation pgTAP tests**: private helper permissions/search paths, canonical and structural validation, exact-location/contact/GPS/URL/social/access-code detection across title/description/suburb/city, South African false-positive fixtures, hostile draft-RPC calls, trigger backstops, safe errors, and atomic rejection when an unsafe legacy draft attempts to become open.
- **Run marketplace state machine pgTAP tests**: request draft/publish/cancel, provider bid submission/withdrawal, bid acceptance, booking creation, direct workflow mutation denial, booking integrity constraints, completion confirmation after `in_progress`, and Ticket 1/2/5 smoke protections.
- **Run customer draft cancellation pgTAP tests**: function contract/search path/authority, restrictive grants and legacy revoke, role/account/ownership checks, exact draft-only state enforcement, bid/booking/inconsistent-row rejection, minimal update, fixed privacy-safe audit, audit rollback, duplicate-call handling, state-guard cleanup, and RLS regressions.
- **Run payment ledger pgTAP tests**: constrained payment status values, payment/release direct mutation denial, booking-party payment visibility, append-only payment events, idempotent trusted payment event recording, and Ticket 1/2/5/6 smoke protections.
- **Run refund ledger pgTAP tests**: booking-party refund requests, refund amount constraints, admin-only refund decisions, manual/sandbox refund outcomes, payment refunded totals/status transitions, append-only refund events, idempotency, and Ticket 1/2/5/6/7A smoke protections.
- **Run cash payment policy pgTAP tests**: MVP cash-disabled enforcement, cash/off-platform payment method rejection, customer/provider cash mutation denial, payout-release-like cash event blocking, and Ticket 1/2/5/6/7A/7B smoke protections.
- **Run payout release controls pgTAP tests**: internal/manual-sandbox release eligibility, release pause/resume, active refund/dispute/provider blocker enforcement, append-only payment/audit ledgers, idempotency, and Ticket 1/2/5/6/7A/7B/7C smoke protections.
- **Run mock payment checkout pgTAP tests**: mock/sandbox hosted-checkout creation, production fail-closed mock-mode validation, mock paid/failed outcome recording, vendor/payment/audit event idempotency, no credential storage, and Ticket 1/2/5/6/7A/7B/7C/7D smoke protections.
- **Run payment webhook pgTAP tests**: trusted mock/sandbox webhook database processing after signature verification, `vendor_events` idempotency, duplicate/out-of-order handling, no raw webhook body storage, append-only ledgers, frontend mutation denial, and Ticket 1/2/5/6/7A/7B/7C/7D/7E smoke protections.

pgTAP failures usually show which assertion failed and the assertion message. Use that message to find the relevant block in the `.test.sql` file.

## Running the same tests locally

Requirements:

- Docker Desktop or Docker Engine
- Supabase CLI
- Deno, for the mock payment webhook route tests

From the repository root:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
cd outputs/marketplace-production-foundation
deno test supabase/functions/payment-webhook/index.test.ts
supabase start
supabase db reset
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/profile_provisioning.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
supabase test db supabase/tests/database/public_field_validation.test.sql
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
supabase test db supabase/tests/database/customer_draft_cancellation.test.sql
supabase test db supabase/tests/database/customer_draft_update.test.sql
supabase test db supabase/tests/database/payments_ledger.test.sql
supabase test db supabase/tests/database/refunds_ledger.test.sql
supabase test db supabase/tests/database/cash_payment_policy.test.sql
supabase test db supabase/tests/database/payout_release_controls.test.sql
supabase test db supabase/tests/database/mock_payment_checkout.test.sql
supabase test db supabase/tests/database/payment_webhooks.test.sql
supabase stop --no-backup
```

Do not run `supabase init` in CI and do not add production credentials or production project references to local test configuration. The committed `supabase/config.toml` is local-only and must not contain database passwords, service-role keys, JWT signing secrets, payment keys, identity-verification keys, production Supabase project refs/URLs, or production project secrets. The mock webhook route tests use deterministic local test values only; do not replace them with live provider secrets.

## Ticket 9A-2 frontend Auth and safe-read verification

Ticket 9A-2 uses Node's built-in test runner and the exact `@supabase/supabase-js` version locked in `outputs/lekkadeall-frontend-shell/pnpm-lock.yaml`. No separate browser-test framework was added.

From the repository root:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

For a local preview, copy the placeholder template to the ignored runtime file and supply only public browser values:

```powershell
Copy-Item outputs/lekkadeall-frontend-shell/runtime-config.example.js outputs/lekkadeall-frontend-shell/runtime-config.local.js
python -m http.server 4173 --directory outputs/lekkadeall-frontend-shell
```

The documented placeholder names are `PUBLIC_APP_ENV`, `PUBLIC_APP_URL`, `PUBLIC_SUPABASE_URL`, and `PUBLIC_SUPABASE_ANON_KEY`. A service-role key or any payment, webhook, provider, identity, database, or admin secret is forbidden in browser configuration.

The frontend tests verify:

- the anon-only browser-client boundary and pinned local package;
- sign-in/registration/recovery wiring without registration metadata;
- route decisions from session plus the own `public.profiles` row, including missing-profile, expired-session, restricted/suspended/closed, wrong-role, and unknown-role fail-closed states;
- active-category reads and own profile/provider/customer summary reads through explicit projections only;
- no `select('*')`, application-table insert/update/upsert/delete, application RPC, admin route, blocked-table read, frontend secret, exact-address field, payment-method form, or privileged workflow call;
- the exact `Mock/sandbox — no real money moved` banner wording.

GitHub Actions installs the locked frontend dependency, runs all `*.test.mjs` files, and then continues through the existing Deno webhook, migration reset, and pgTAP suites. A denied safe read remains a placeholder; it is not grounds to modify RLS, grants, policies, or database functions.

## Ticket 9A-3 customer draft-creation verification

Ticket 9A-3 adds `outputs/lekkadeall-frontend-shell/tests/request-draft.test.mjs` and updates the existing shell/Auth tests. The frontend still uses Node's built-in test runner.

From the repository root:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

Preview the route after copying the public runtime-config template as documented above:

```powershell
python -m http.server 4173 --directory outputs/lekkadeall-frontend-shell
```

Open `http://localhost:4173/app/customer/requests/new/`. A valid configured Supabase project and active customer session are required to submit. Never use a service-role key or real server secret in the browser configuration.

The Ticket 9A-3 tests verify:

- the route is protected by the existing session plus own-profile role/status guard;
- only IDs from the active category projection are accepted;
- title, description, suburb, city, requested start, and optional budget validation;
- required exact-address/contact privacy warnings and local sensitive-pattern detection;
- budget conversion by string/BigInt-safe integer logic, including overflow rejection;
- requested-start conversion to an explicit SAST `+02:00` timestamp;
- exactly one allowlisted marketplace RPC: `customer_create_draft_request`;
- `p_precise_address_ciphertext` is always `null`;
- success is rendered only after a returned request UUID;
- RPC failures are generic and are never automatically retried;
- no publish/address RPC, direct application-table DML, `select('*')`, persistent form storage, geolocation, admin/service-role capability, exact-address/contact/payment field, or real payment code exists.

Local implementation result: **25/25 frontend tests passed**. The Deno webhook and pgTAP suites were not changed; GitHub Actions remains the complete integration and database-security regression gate.

## Ticket 9A-5 server public-field validation verification

Ticket 9A-5 adds migration `014_server_public_field_validation.sql` and the dedicated `public_field_validation.test.sql` pgTAP suite. The migration creates one private authoritative classifier/assertion boundary for `title`, `description`, `suburb`, and `city`; integrates it into `customer_create_draft_request(...)`; adds a table trigger for inserts, public-field changes, and transitions to `open`; and keeps the Ticket 5 description preflight by delegating it to the shared classifier.

From the repository root, run the frontend regression suite:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

From `outputs/marketplace-production-foundation`, run the migration and focused database suite:

```powershell
supabase start
supabase db reset
supabase test db supabase/tests/database/public_field_validation.test.sql
supabase stop --no-backup
```

Then run every pgTAP command listed in **Running the same tests locally** above for the full regression gate.

The focused Ticket 9A-5 suite plans exactly **95 assertions** covering:

- private helper existence, `SECURITY DEFINER` configuration, fixed `pg_catalog` search paths, and denied direct execution for `PUBLIC`, `anon`, `authenticated`, and `service_role`;
- retained RLS and denied browser insert/update/delete privileges;
- null/blank, character/byte length, NFC/trim/CRLF canonicalisation, single-line/multiline, control, bidi/invisible, and markup rules;
- street/property/unit/complex, GPS, South African phone, email, URL, social/contact, and gate/security-code detection;
- representative South African locality, numbered-locality, quantity, model, punctuation, and context-sensitive false-positive fixtures;
- compatibility behavior for `service_request_description_has_exact_address_risk(...)`;
- hostile direct RPC calls rejecting each public field without creating a row or leaking the matched value;
- table-trigger rejection of privileged/internal unsafe insert/update attempts; and
- atomic rejection when a simulated legacy unsafe draft attempts to transition to `open`.

The existing frontend rejection test now supplies a Ticket 9A-5-style `22023` database error and proves the browser returns its fixed generic message without echoing the server field/reason text or retrying. Local frontend result: **25/25 passed** using the bundled Node runtime.

This host did not expose Docker or the Supabase CLI, so the migration and pgTAP suite were not executed locally. GitHub Actions runs `supabase db reset`, the focused 95-assertion suite, and every existing pgTAP/Deno/frontend regression before Ticket 9A-5 may be marked CI-verified.

Ticket 9A-5 does not add a frontend publication call, exact-address collection, KMS/encryption, a draft-update RPC, direct frontend table DML, provider bidding, payments, admin features, credentials, or service-role keys. The existing database publication function is not newly exposed in the frontend; the new trigger only adds a fail-closed validation backstop for any attempted transition to `open`.

## Ticket 9A-6 customer request list/detail verification

Ticket 9A-6 adds `outputs/lekkadeall-frontend-shell/tests/customer-request-read.test.mjs` and updates the existing frontend shell, Auth/safe-read, and draft tests. It introduces no new dependency or package-file change and continues to use Node's built-in test runner.

From the repository root:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

For a local preview, copy the public placeholder template as documented above and run:

```powershell
python -m http.server 4173 --directory outputs/lekkadeall-frontend-shell
```

The implemented routes are:

- `http://localhost:4173/app/customer/requests/`
- `http://localhost:4173/app/customer/requests/detail/?requestId=<valid-request-uuid>`

Both routes require a session plus an own RLS-protected profile with `role = 'customer'` and `account_status = 'active'`. The static-shell-compatible detail URL contains only the opaque UUID; it does not contain title, description, suburb, city, schedule, budget, status, or other request content.

List and detail use exactly:

```text
id,category_id,title,description,suburb,city,requested_start,budget_minor,status,created_at,updated_at
```

The list applies `status IN (draft, open, cancelled)`, `created_at` descending, and `limit(20)`. The detail validates the UUID before querying `service_requests`, applies the same status allowlist, and uses `maybeSingle()`. Malformed, missing, cross-customer, unsupported-status, and RLS-hidden IDs render the same generic unavailable state. Ownership continues to come only from existing RLS; neither query selects or filters on `customer_id`.

The Ticket 9A-6 frontend tests verify:

- session/profile guards for active customer, signed-out, restricted/suspended, and wrong-role states;
- the exact request projection and exclusion of address, customer, workflow-internal, provider, bid, booking, payment, and audit columns;
- newest-first ordering, the three-status allowlist, and the 20-row limit;
- UUID validation before the request query, exact detail filters, and `maybeSingle()` semantics;
- one generic not-found/unavailable state for every non-visible detail outcome;
- active-category labels with a safe “Category unavailable” fallback;
- database-text escaping, explicit `Africa/Johannesburg`/SAST dates, and display-only ZAR budget formatting;
- dashboard and draft-success navigation to “View all requests” and “View draft”;
- no `select('*')`, direct application-table insert/update/upsert/delete, cancellation/publication/address RPC, exact-address/payment/admin/provider control, service-role key, credential, browser persistence, logging, analytics, or telemetry.

Local implementation result: **33/33 frontend tests passed**. Ticket 9A-6 changes no migration, RLS policy, grant, database policy/function, pgTAP test, Deno webhook function/test, or workflow. GitHub Actions remains the authoritative full pgTAP and Deno regression gate.

Cancellation and `customer_cancel_request(...)` remain intentionally absent. Publication, request editing, exact-address handling, maps/GPS, KMS/encryption, provider feed/onboarding/bidding, booking actions, payments/refunds/payouts, disputes/reviews/support/chat, profile editing, and the admin dashboard also remain blocked.

## Ticket 9A-7 customer draft-only cancellation verification

Ticket 9A-7 adds migration `015_customer_draft_cancellation.sql`, the focused `customer_draft_cancellation.test.sql` pgTAP suite, `request-cancellation.js`, and `tests/request-cancellation.test.mjs`. It updates the detail page and existing frontend regression suites without adding a dependency or changing a package file.

From the repository root, run all frontend tests:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

For a local preview:

```powershell
Copy-Item outputs/lekkadeall-frontend-shell/runtime-config.example.js outputs/lekkadeall-frontend-shell/runtime-config.local.js
python -m http.server 4173 --directory outputs/lekkadeall-frontend-shell
```

Open `http://localhost:4173/app/customer/requests/detail/?requestId=<owned-draft-uuid>` while signed in as the active customer who owns that draft.

From `outputs/marketplace-production-foundation`, run the migration and focused database suite:

```powershell
supabase start
supabase db reset
supabase test db supabase/tests/database/customer_draft_cancellation.test.sql
supabase stop --no-backup
```

The focused pgTAP suite plans exactly **62 assertions** covering:

- the `public.customer_cancel_draft_request(uuid) returns public.request_status` contract, `SECURITY DEFINER`, `VOLATILE`, fixed `pg_catalog` search path, explicit actor/request locks, one UUID argument, and absence of dynamic SQL or broad selects;
- denied execution for `PUBLIC`, `anon`, and `service_role`, authenticated-only execution of the new function, revoked authenticated execution of `customer_cancel_request(uuid,text)`, and no direct authenticated insert/update/delete request-table privileges;
- signed-out, missing-profile, provider/admin role, restricted/suspended/closed status, hostile JWT-role metadata, and cross-customer rejection;
- successful exact-draft cancellation, unchanged ownership/public/workflow fields, exactly one fixed privacy-safe audit event, and no email/phone/token/reason/metadata leakage;
- duplicate calls and open/awarded/cancelled/expired/inconsistent draft rows rejecting without mutation;
- any bid, accepted bid, or booking rejecting cancellation;
- direct DML denial, cancellation rollback when audit insertion fails, transition-guard reset, own/cross-customer RLS behavior, and unchanged bid/booking rows.

The frontend suite verifies the detail-only control, fresh-read `draft` requirement, fixed confirmation copy, absence of a cancellation reason field, exact `{ p_request_id: requestId }` payload, single-flight handling, no optimistic status change, no automatic retry, fresh RLS re-read after RPC success, success only when the re-read says `cancelled`, and generic safe errors. Static boundaries prove the frontend does not call the legacy cancellation or publication RPC, use direct application-table DML, use `select('*')`, or add blocked address/provider/booking/payment/admin features.

Local frontend result: **43/43 passed** using Node's built-in test runner. The SQL suite contains **62 assertions matching `plan(62)`**. This host did not expose Docker, the Supabase CLI, PostgreSQL client, or Deno, so the pgTAP and webhook suites could not be executed locally. GitHub Actions remains the authoritative migration, focused pgTAP, full pgTAP, and webhook regression gate. Ticket 9A-7's CI result is **pending** until the workflow completes successfully.

Publication, editing/deletion/duplication/reopening, exact-address handling, KMS/encryption, provider feed/onboarding/bidding, booking actions, payments/refunds/payouts, disputes/reviews/support/chat, identity/profile editing, and the admin dashboard remain blocked. No service-role key, real credential, direct frontend table write, RLS policy, or direct table grant was added, and existing role/status, address privacy, public-field validation, marketplace state-machine, and payment protections were not weakened.

## Ticket 9A-8 customer draft edit/update verification

Ticket 9A-8 adds migration `016_customer_draft_update.sql`, the focused `customer_draft_update.test.sql` pgTAP suite, `request-update.js`, the clean edit route, and `tests/request-update.test.mjs`. It changes no dependency or package file and continues to use Node's built-in test runner.

From the repository root, install the existing pinned browser dependency and run all frontend tests:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

For a local preview:

```powershell
Copy-Item outputs/lekkadeall-frontend-shell/runtime-config.example.js outputs/lekkadeall-frontend-shell/runtime-config.local.js
python -m http.server 4173 --directory outputs/lekkadeall-frontend-shell
```

Open `http://localhost:4173/app/customer/requests/detail/?requestId=<owned-draft-uuid>`, then use “Edit draft,” or open `http://localhost:4173/app/customer/requests/edit/?requestId=<owned-draft-uuid>` directly. A configured public Supabase URL/anon key and an active customer session owning an exact draft are required. Never place a service-role key or another secret in browser configuration.

From `outputs/marketplace-production-foundation`, run the reset and focused database suite:

```powershell
supabase start
supabase db reset
supabase test db supabase/tests/database/customer_draft_update.test.sql
supabase stop --no-backup
```

The focused pgTAP suite plans exactly **81 assertions** covering:

- the eight-parameter `public.customer_update_draft_request(...) returns uuid` contract, `SECURITY DEFINER`, `VOLATILE`, fixed `pg_catalog` search path, explicit schema references, actor/profile/request/category locks, and absence of dynamic SQL, broad selects, or state-transition bypass;
- denied execution for `PUBLIC`, `anon`, and `service_role`, authenticated-only function execution, no direct authenticated request-table DML grants, and retained private-validator denial;
- authentication, protected customer/active status, hostile JWT metadata, ownership, and generic missing/cross-customer rejection;
- active-category, future-start, null/nonnegative budget, complete Ticket 9A-5 public-field validation, canonicalisation, safe South African false-positive fixtures, and complete no-op rejection;
- open/awarded/cancelled/expired and inconsistent draft rejection, including any bid, accepted/provider-selected bid, booking, or deprecated public address residue;
- replacement of only category, title, description, suburb, city, requested start, budget, and server `updated_at`, with workflow/ownership/address state unchanged;
- exactly one fixed privacy-safe audit event containing only request ID and an ordered allowlist of changed field names; and
- direct-DML denial plus atomic rollback of every field change when audit insertion fails.

The frontend suite now has **53 tests**. Ticket 9A-8 coverage verifies UUID-before-read/RPC validation, the exact draft-only RLS query and explicit projection, active-customer guards, edit visibility only on fresh draft detail, no list/non-draft edit control, safe prefill/SAST/ZAR conversion, the exact privacy warning and field allowlist, exact eight-key RPC payload, single-flight behavior, no optimistic status change or automatic retry, fresh draft-only RLS confirmation, fresh server values, generic safe errors, and browser-source exclusions for direct DML, `select('*')`, address/publication/payment/admin capabilities, persistence, logs, telemetry, service-role keys, and real credentials.

Local result on this host: **53/53 frontend tests passed**. Docker, Supabase CLI, Deno, and `psql` are unavailable on this host, so the 81-assertion pgTAP suite, migration reset, and Deno webhook regressions require GitHub Actions. CI remains pending until that workflow succeeds.

Publication, exact-address collection/storage/read/reveal, KMS/encryption, provider feed/onboarding/bidding, booking actions, payments/refunds/payouts/disputes, admin dashboard, profile editing, direct frontend application-table writes, and security-policy weakening remain intentionally blocked.

## Ticket 9A-9 customer draft lifecycle E2E verification

Ticket 9A-9 adds Playwright Test `1.61.1` as an exact development dependency while retaining the existing Node frontend test command. The initial E2E project is Chromium-only, serial (`workers: 1`), and retry-free. Screenshots, video, traces, HAR, DOM snapshots, saved storage state, HTML/JUnit reports, database dumps, and Auth-email artifacts are not produced in CI.

Run the fast frontend/static boundary first:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

The local result for Ticket 9A-9 is **62/62 Node tests passed**. Playwright configuration discovery finds **8 synthetic local Chromium scenarios**. The regression checks cover the reviewed `/auth/sign-in` sign-out redirect, local Auth pacing, bounded per-scenario timing, atomic profile/request fixture invariants, guard-before-read behavior, and privacy-safe failure classification. The Playwright project remains one-worker and retry-free; shorter tests retain the default 60-second timeout.

The complete registration-to-cancellation scenario uses a test-local `300_000` millisecond timeout, and the five-actor restricted/suspended/closed/missing-profile/wrong-role matrix uses `600_000` milliseconds. These are the two aggregate journeys: the first includes registration, sign-out/sign-in, category and dashboard reads, all three lifecycle RPCs, repeated fresh RLS reads, privacy checks, and final database invariants; the second performs five sequential real Auth registrations, five fresh contexts, local fixture transitions, route reloads, privacy assertions, and sign-outs. The two-context cross-customer RLS scenario and the stale/ambiguous mutation scenarios use `180_000` millisecond bounds. This changes no assertion, mutation count, network allowlist, application behavior, retry policy, global 60-second default, or 30-minute CI job timeout. The privacy-safe reporter emits only a fixed failure category and, for the account-state matrix, an allowlisted state label; it never emits errors, stacks, values, payloads, URLs, credentials, browser state, database rows, or attachments.

The local fixture controller now validates each profile transition inside the same database transaction. Restricted, suspended, and closed cases must remain `customer` profiles with the exact requested `account_status`; the wrong-role case must use the existing `provider` enum value; and the missing-profile case must delete exactly one profile while preserving the corresponding Auth user and proving that no profile row remains. Ticket 9B is unchanged: its provisioning trigger remains `AFTER INSERT` on `auth.users`, so deleting a profile does not cause re-provisioning on a route read or token refresh.

The local runner generates a cryptographically random per-run identifier and every synthetic actor adds a separate random suffix, so Auth emails cannot be reused across tests or workflow runs. The disposable runner still refuses a pre-existing local stack, performs a clean database reset, and stops without a backup. Local Auth has email confirmation disabled, so registration must establish a session directly and does not read Inbucket or retain an Auth email.

The shared registration helper uses fixed, privacy-safe readiness phases rather than a nominal signup delay. It waits for the actual loopback `/auth/v1/signup` response, condition-polls for exactly one SDK-owned Auth-session storage entry without reading its value, condition-polls a no-row-output database invariant proving exactly one Auth user and one Ticket 9B `customer`/`active` profile with no provider profile, and then waits for the customer dashboard route and heading. Restricted, suspended, closed, and provider cases complete this normal registration boundary before the local fixture controller changes protected profile state. The missing-profile case completes the same boundary before its profile is deliberately removed.

For the real local-stack E2E boundary, install Chromium and run the single orchestrated command:

```powershell
pnpm --dir outputs/lekkadeall-frontend-shell exec playwright install chromium
pnpm --dir outputs/lekkadeall-frontend-shell run test:e2e:local
```

Do not start Supabase separately. The runner refuses an existing stack so it cannot reset or stop a developer-owned local session. It performs this sequence:

1. Validate that Docker is local and every application/API/Auth/Inbucket target is loopback.
2. Refuse an existing `runtime-config.local.js` and an already-running Supabase stack.
3. Start Supabase from the committed local config and run `supabase db reset`.
4. Seed only one active and one inactive synthetic category through the exact local database container.
5. Generate the ignored browser runtime config with `appEnv = test`, the loopback URLs, and local anon key only.
6. Serve the static frontend through the restricted Node server on `127.0.0.1:4173`.
7. Run the eight Chromium scenarios with one worker and no retries.
8. Remove generated runtime/output files, stop the frontend server, and stop Supabase with no backup in `finally` cleanup.

The browser E2E scenarios cover:

- signed-out customer-route protection and absence of `/admin`;
- UI registration and the Ticket 9B one-row `customer`/`active` profile postcondition;
- sign out, sign in, and removal of the persisted SDK Auth session on sign-out;
- active-category discovery and customer dashboard access;
- draft creation, list, detail, edit, cancellation, fresh-read confirmation, and privacy-safe audit postconditions;
- Customer A versus Customer B RLS non-disclosure;
- restricted, suspended, closed, missing-profile, and wrong-role guards;
- stale edit rejection after cancellation in another tab;
- an update that commits while its response is aborted, proving no automatic retry and requiring a fresh read;
- the exact browser mutation allowlist and rejection of direct table DML, broad selects, blocked RPCs, non-loopback requests, and service-role authorization;
- absence of address, provider, booking, payment, admin, and profile-edit controls; and
- URL, `localStorage`, `sessionStorage`, IndexedDB, Cache Storage, service-worker, cookie, console, and browser-artifact privacy checks.

The only allowed browser-storage entry while signed in is the existing Supabase SDK Auth-session key created by `persistSession: true`. The E2E check never reads that value into output and proves sign-out removes it. Marketplace/request content and application-specific storage remain forbidden.

A complete password-recovery/Inbucket exchange is intentionally not implemented in this ticket. Supabase PKCE recovery must temporarily persist a code verifier between the recovery request and callback, while Ticket 9A-9 authorizes only the existing signed-in Auth-session storage exception. The E2E suite verifies that the signed-out reset route fails closed without a recovery session. A future recovery E2E requires a reviewed decision to permit temporary PKCE storage or move recovery behind a server/HttpOnly-cookie boundary.

GitHub Actions adds a separate `customer-draft-lifecycle-e2e` job with `needs: database-tests`. Therefore E2E runs only after the existing Node, Deno webhook, clean migration reset, and every pgTAP suite pass. The E2E job starts another disposable local stack and uses no GitHub environment secret, production Supabase reference, real customer data, or production credential.

Docker and Supabase CLI are unavailable on the current development host, so the real local-stack Playwright execution could not be run here. GitHub Actions remains the authoritative full E2E verification gate. No migration, RLS policy, grant, production database function, validator, state-machine guard, profile-provisioning function, cancellation function, or update function changed for Ticket 9A-9.
