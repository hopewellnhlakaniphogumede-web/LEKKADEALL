# LEKKADEALL testing guide

## Database security tests in CI

GitHub Actions runs the Supabase database hardening tests on every push and pull request.

Workflow file:

- `.github/workflows/database-tests.yml`

The workflow runs on `ubuntu-latest`, verifies Docker is available, installs the Supabase CLI, verifies the committed local Supabase config, starts the local Supabase stack, applies all local migrations with `supabase db reset`, then runs the pgTAP database tests.

It does not use production secrets. It uses only:

- local Supabase migrations under `outputs/marketplace-production-foundation/supabase/migrations`
- committed non-secret local Supabase config at `outputs/marketplace-production-foundation/supabase/config.toml`
- local pgTAP tests under `outputs/marketplace-production-foundation/supabase/tests/database`
- deterministic test seed data from `rls_test_seed.inc`

CI does not run `supabase init`. The local config is committed so the test environment is deterministic and repeatable. The workflow also checks that the config does not contain obvious secret markers or production Supabase project references.

## Tests run by CI

From `outputs/marketplace-production-foundation`, CI runs:

```bash
supabase db reset
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
supabase test db supabase/tests/database/payments_ledger.test.sql
supabase test db supabase/tests/database/refunds_ledger.test.sql
supabase test db supabase/tests/database/cash_payment_policy.test.sql
supabase test db supabase/tests/database/payout_release_controls.test.sql
supabase test db supabase/tests/database/mock_payment_checkout.test.sql
```

The workflow fails if any migration or pgTAP test fails.

## How to read CI results

In GitHub:

1. Open the repository.
2. Go to the **Actions** tab.
3. Open the **Supabase database tests** workflow run for your push or pull request.
4. Open the **Run Supabase migrations and pgTAP tests** job.
5. Review the failing step.

Common useful steps:

- **Apply migrations with database reset**: migration/schema errors usually appear here.
- **Run role escalation pgTAP tests**: role, provider verification, privileged-column, and audit protections.
- **Run baseline RLS pgTAP tests**: table-level RLS, service categories, provider services, vendor events, and baseline privacy protections.
- **Run exact address privacy pgTAP tests**: exact address isolation, safe request summaries, confirmed-booking reveal, address audit events, and public-description address checks.
- **Run marketplace state machine pgTAP tests**: request draft/publish/cancel, provider bid submission/withdrawal, bid acceptance, booking creation, direct workflow mutation denial, booking integrity constraints, completion confirmation after `in_progress`, and Ticket 1/2/5 smoke protections.
- **Run payment ledger pgTAP tests**: constrained payment status values, payment/release direct mutation denial, booking-party payment visibility, append-only payment events, idempotent trusted payment event recording, and Ticket 1/2/5/6 smoke protections.
- **Run refund ledger pgTAP tests**: booking-party refund requests, refund amount constraints, admin-only refund decisions, manual/sandbox refund outcomes, payment refunded totals/status transitions, append-only refund events, idempotency, and Ticket 1/2/5/6/7A smoke protections.
- **Run cash payment policy pgTAP tests**: MVP cash-disabled enforcement, cash/off-platform payment method rejection, customer/provider cash mutation denial, payout-release-like cash event blocking, and Ticket 1/2/5/6/7A/7B smoke protections.
- **Run payout release controls pgTAP tests**: internal/manual-sandbox release eligibility, release pause/resume, active refund/dispute/provider blocker enforcement, append-only payment/audit ledgers, idempotency, and Ticket 1/2/5/6/7A/7B/7C smoke protections.
- **Run mock payment checkout pgTAP tests**: mock/sandbox hosted-checkout creation, production fail-closed mock-mode validation, mock paid/failed outcome recording, vendor/payment/audit event idempotency, no credential storage, and Ticket 1/2/5/6/7A/7B/7C/7D smoke protections.

pgTAP failures usually show which assertion failed and the assertion message. Use that message to find the relevant block in the `.test.sql` file.

## Running the same tests locally

Requirements:

- Docker Desktop or Docker Engine
- Supabase CLI

From the repository root:

```powershell
cd outputs/marketplace-production-foundation
supabase start
supabase db reset
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
supabase test db supabase/tests/database/payments_ledger.test.sql
supabase test db supabase/tests/database/refunds_ledger.test.sql
supabase test db supabase/tests/database/cash_payment_policy.test.sql
supabase test db supabase/tests/database/payout_release_controls.test.sql
supabase test db supabase/tests/database/mock_payment_checkout.test.sql
supabase stop --no-backup
```

Do not run `supabase init` in CI and do not add production credentials or production project references to local test configuration. The committed `supabase/config.toml` is local-only and must not contain database passwords, service-role keys, JWT signing secrets, payment keys, identity-verification keys, production Supabase project refs/URLs, or production project secrets.
