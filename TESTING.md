# LEKKADEALL testing guide

## Frontend shell, database, and webhook route tests in CI

GitHub Actions runs the Ticket 9A-2 frontend Auth/safe-read tests, mock payment webhook route tests, and Supabase database hardening tests on every push and pull request.

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
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
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

- **Run Ticket 9A-2 frontend auth and safe-read tests**: required routes and safe states, exact mock-payment wording, anon-only client configuration, metadata-free registration, protected-profile route decisions, explicit projections, fixed read sources, absence of an admin route, no application writes/RPC/broad selects, and clean-path entry files.
- **Apply migrations with database reset**: migration/schema errors usually appear here.
- **Run mock payment webhook route tests**: raw-body HMAC verification, missing/invalid signatures, stale timestamps, exact payload hashing, no database call before verification, safe metadata forwarding, runtime-only mock secret/app-env config, and production mock-mode fail-closed behavior.
- **Run role escalation pgTAP tests**: role, provider verification, privileged-column, and audit protections.
- **Run baseline RLS pgTAP tests**: table-level RLS, service categories, provider services, vendor events, and baseline privacy protections.
- **Run secure profile provisioning pgTAP tests**: `auth.users` trigger provisioning, fixed customer/active defaults, hostile metadata rejection, idempotency/no-overwrite behavior, privacy-safe audit events, existing-user backfill, frontend insert/delete denial, own-profile RLS, and Ticket 1/2 regression checks.
- **Run exact address privacy pgTAP tests**: exact address isolation, safe request summaries, confirmed-booking reveal, address audit events, and public-description address checks.
- **Run marketplace state machine pgTAP tests**: request draft/publish/cancel, provider bid submission/withdrawal, bid acceptance, booking creation, direct workflow mutation denial, booking integrity constraints, completion confirmation after `in_progress`, and Ticket 1/2/5 smoke protections.
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
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
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
