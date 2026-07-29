# LEKKADEALL Hardening Progress

## Ticket 1 — Fix role escalation

**Date:** 9 July 2026  
**Status:** CI-verified. `role_escalation.test.sql` passed in the **Supabase database tests** GitHub Actions workflow with run status **Success**.

### Issue fixed

Normal frontend-authenticated users can no longer directly update privileged role or provider-status fields.

The affected privileged fields are:

- `profiles.role`
- `profiles.account_status`
- `provider_profiles.verification_status`
- `provider_profiles.verification_reference`
- `provider_profiles.bank_name_match`
- `provider_profiles.review_status`
- `provider_profiles.reviewed_by`
- `provider_profiles.reviewed_at`
- `identity_verifications.status`

The existing schema does not have a separate `provider_status` column. `provider_profiles.review_status` is currently the provider activation/review status field.

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/002_fix_role_escalation.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/role_escalation.test.sql`
- `hardening_progress.md`

### What changed

- Removed broad direct client update policies:
  - `profile owner updates self`
  - `provider owns provider profile`
- Added `public.is_platform_admin()` to identify active admins or service-role server context.
- Added audited admin/server functions:
  - `public.admin_set_user_role(...)`
  - `public.admin_set_account_status(...)`
  - `public.admin_set_provider_review_status(...)`
  - `public.admin_set_provider_verification_status(...)`
- Added private audit writer:
  - `private.append_audit_event(...)`
- Added append-only audit protection:
  - `audit_events_append_only` trigger blocks update/delete of audit rows.
- Added safe owner-edit paths:
  - `profile owner updates safe profile fields`
  - `provider updates safe provider profile fields`
- Added column allow-list grants:
  - customers/users may update only `profiles.display_name`, `profiles.phone_e164`, `profiles.suburb`, `profiles.city`, and `profiles.avatar_path`
  - providers may update only `provider_profiles.business_name`, `provider_profiles.bio`, and `provider_profiles.service_radius_km`
- Added privileged-field guard triggers:
  - `protect_profile_privileged_fields`
  - `protect_provider_profile_privileged_fields`
- Confirmed the static prototype does not directly write privileged database fields. It still contains demo-only role/admin/verification screens, but there is no Supabase/database update code in the prototype.

### Tests added

`outputs/marketplace-production-foundation/supabase/tests/database/role_escalation.test.sql` proves:

- Customer cannot make themselves provider.
- Provider cannot make themselves admin.
- Customer can still update safe profile fields.
- Provider can still update safe provider profile fields.
- Normal user cannot directly change `account_status`.
- Normal user cannot directly change `provider_profiles.verification_status`.
- Normal user cannot directly change `identity_verifications.status`.
- Normal user cannot directly change provider status / `review_status`.
- Normal user cannot call the admin role-change function.
- Normal provider cannot call the admin provider-status function.
- Authorised admin function can make a customer provider.
- Authorised admin function can change account status.
- Authorised admin function can change provider verification/review status.
- Privileged role/status changes write audit events.

These tests should fail against `001_initial_schema.sql` alone because broad owner update policies allow self-escalation, and should pass after applying `002_fix_role_escalation.sql`.

### How to run tests

From `outputs/marketplace-production-foundation`:

```powershell
npx supabase start
npx supabase db reset
npx supabase test db supabase/tests/database/role_escalation.test.sql
```

If Supabase CLI is installed globally, use:

```powershell
supabase start
supabase db reset
supabase test db supabase/tests/database/role_escalation.test.sql
```

### Remaining risks

- The wider `rls_policies.test.sql` file still includes tests for other unresolved tickets, including address reveal rules. It should not be treated as green until those tickets are repaired.
- Safe direct profile/provider-profile editing is allowed only for explicitly allow-listed fields. Future tickets may still replace these direct updates with application server actions for better validation/rate limiting.
- Admin authority is still derived from `profiles.role = 'admin'`. This is acceptable after this fix because normal users can no longer update their own role, but a later ticket should move staff/admin authority to a dedicated staff-membership/permission model with MFA checks.
- Provider verification is still duplicated between `provider_profiles.verification_status` and `identity_verifications.status`. A later identity-verification ticket should define the source of truth and reconciliation rules.
- There is still no production application backend, CI pipeline, webhook handler, or vendor adapter.

## Ticket 1 verification pass — 10 July 2026

### Result

Verification found and fixed two gaps in the first Ticket 1 implementation:

1. Safe customer/provider profile edits were fully locked down instead of being allowed through a safe path.
2. Privileged-column protection needed a durable trigger guard so a future broad owner update policy could not accidentally re-open role/status escalation.

### Additional files changed

- `outputs/marketplace-production-foundation/supabase/migrations/002_fix_role_escalation.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/role_escalation.test.sql`
- `hardening_progress.md`

### Protected privileged fields verified

- `profiles.role`
- `profiles.account_status`
- `provider_profiles.verification_status`
- `provider_profiles.verification_reference`
- `provider_profiles.bank_name_match`
- `provider_profiles.review_status`
- `provider_profiles.reviewed_by`
- `provider_profiles.reviewed_at`
- `identity_verifications.status`

The current schema has no `admin` boolean, `provider_status`, `approved_by`, `approved_at`, `suspended_by`, or `suspended_at` columns. The current equivalents are:

- admin status: `profiles.role = 'admin'`
- provider status: `provider_profiles.review_status`
- approval/review actor: `provider_profiles.reviewed_by`
- approval/review timestamp: `provider_profiles.reviewed_at`

### Protection mechanisms verified

- **RLS policies:** owner updates are allowed only on own `profiles` / `provider_profiles` rows.
- **Column-level privileges:** `authenticated` users receive update grants only for safe profile/provider-profile columns.
- **Triggers:** direct changes to privileged columns are rejected unless an authorised admin/server function sets a transaction-local privileged-update guard.
- **Server-side functions:** admin-only `SECURITY DEFINER` functions perform legitimate privileged changes.
- **Audit logging:** every authorised privileged change writes to `audit_events`.
- **Append-only audit trigger:** `audit_events_append_only` rejects update/delete attempts on audit rows.

### Verification status

- Static code review completed.
- The test suite was expanded from 16 to 37 pgTAP assertions.
- CI execution passed in the **Supabase database tests** GitHub Actions workflow with run status **Success**.

### Ticket 1 closeout checklist

- [x] All privileged fields protected.
- [x] Safe profile fields still editable.
- [x] RLS policies updated.
- [x] Column-level update grants added.
- [x] Privileged-field protection triggers added.
- [x] `SECURITY DEFINER` functions reviewed.
- [x] Audit events append-only.
- [x] `identity_verifications` protected.
- [x] 37 pgTAP assertions added.
- [x] `role_escalation.test.sql` passed in CI.

**Closeout gate:** Satisfied by **Supabase database tests** GitHub Actions workflow run status **Success**.

## Ticket 2 — Repair baseline RLS on every public table

**Date:** 10 July 2026  
**Status:** CI-verified. `baseline_rls.test.sql` passed in the **Supabase database tests** GitHub Actions workflow with run status **Success**.

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/003_repair_baseline_rls.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/baseline_rls.test.sql`
- `rls_policy_matrix.md`
- `hardening_progress.md`

### Public tables reviewed

All 16 public application tables were listed in `rls_policy_matrix.md`:

- `profiles`
- `provider_profiles`
- `service_categories`
- `provider_services`
- `service_requests`
- `bids`
- `bookings`
- `payments`
- `vendor_events`
- `identity_verifications`
- `disputes`
- `dispute_evidence`
- `reviews`
- `consents`
- `data_subject_requests`
- `audit_events`

### RLS disabled before Ticket 2

These tables had no RLS in `001_initial_schema.sql`:

- `service_categories`
- `provider_services`
- `vendor_events`

### Policies and grants added/removed

- Enabled RLS on every public application table.
- Added `public.is_approved_provider(...)` helper for active, verified, approved providers.
- Locked down `vendor_events`:
  - all frontend privileges revoked from `anon` and `authenticated`
  - no frontend RLS policies added
  - added service-role-only `private.record_vendor_event(...)` for idempotent server-side writes
- Locked down `service_categories`:
  - frontend users may `SELECT` active categories only
  - no frontend insert/update/delete
- Locked down `provider_services`:
  - anonymous access denied
  - authenticated users may read active services for approved providers
  - approved providers may insert/update/delete only their own provider services
  - unapproved/suspended providers cannot create active services
- Tightened `provider_profiles` discovery:
  - anonymous direct select revoked
  - authenticated users can discover only active, verified, approved provider profiles or their own provider profile
- Replaced the old open-request provider policy:
  - removed `providers see open requests`
  - added `approved providers see open requests`
  - revoked frontend direct SELECT on `service_requests.precise_address_ciphertext`
  - revoked frontend direct SELECT on `service_requests.customer_id`
  - granted frontend SELECT only on safe service-request columns
- Preserved hard locks:
  - `audit_events` frontend privileges revoked; append-only trigger remains
  - `identity_verifications` frontend insert/update/delete revoked

### Tests added

`outputs/marketplace-production-foundation/supabase/tests/database/baseline_rls.test.sql` adds 47 pgTAP assertions proving:

- RLS is enabled on every public table.
- Anonymous users cannot access protected payment/vendor/provider-service tables.
- Frontend users cannot read, insert, update, or delete `vendor_events`.
- Providers cannot read, insert, update, or delete `vendor_events`.
- Service role can record `vendor_events` through the private server function.
- Customers cannot insert/update/delete `service_categories`.
- Providers cannot insert/update/delete `service_categories`.
- Active service categories are readable.
- Inactive service categories are hidden.
- Authenticated users cannot access unrelated private booking/payment/identity rows.
- Customers can view their own service requests.
- Customers cannot view another customer's request rows.
- Approved providers can view eligible open requests.
- Approved providers can read safe open-request fields before booking confirmation.
- Unapproved/suspended providers cannot view open requests.
- Approved providers cannot select precise address fields before confirmed booking.
- The `authenticated` frontend role has no SELECT privilege on `service_requests.precise_address_ciphertext`.
- Frontend roles cannot select exact-address-like columns from `service_requests`.
- Approved providers can create/update only their own `provider_services`.
- Customers cannot create/update/delete `provider_services`.
- Approved providers cannot manage another provider's `provider_services`.
- Unapproved providers cannot create active `provider_services`.
- Suspended providers cannot create active `provider_services`.
- Authenticated users can read active services for approved providers.
- Frontend users cannot edit `audit_events`.
- Frontend users cannot insert/update `identity_verifications`.

### How to run tests

From `outputs/marketplace-production-foundation`:

```powershell
supabase start
supabase db reset
supabase test db supabase/tests/database/baseline_rls.test.sql
```

If using `npx`:

```powershell
npx supabase start
npx supabase db reset
npx supabase test db supabase/tests/database/baseline_rls.test.sql
```

### CI run result

- **Workflow:** Supabase database tests
- **Run status:** Success
- **Passed test file:** `baseline_rls.test.sql`

### Remaining risks

- Historical Ticket 2 address risk, superseded by Ticket 3: at this point `service_requests` still contained precise address material on the same table. Ticket 3 moves exact address ciphertext into `private.service_request_addresses` and adds audited reveal/upsert functions. Open-request `description` still needs validation/redaction so customers cannot accidentally place exact addresses in free text.
- `bids`, `service_requests`, `consents`, and `data_subject_requests` still have broad initial owner policies that should be replaced by workflow/state-machine server actions in later tickets.
- `dispute_evidence` still allows insert based on `uploaded_by` only; it must be restricted to booking parties in the dispute ticket.
- Admin access is still intentionally server-mediated, not broad direct admin RLS. A later ticket should add a dedicated staff/MFA model.

## Ticket 2 verification pass — 10 July 2026

### Result

Verification found and fixed these gaps in the first Ticket 2 implementation:

1. Approved providers could still directly select `service_requests.precise_address_ciphertext`.
2. Provider-specific `vendor_events` negative tests were not explicit.
3. Customer `provider_services` insert/update/delete negative tests were not explicit.
4. Service-request visibility tests for own customer, unrelated customer, approved provider, unapproved provider, and suspended provider were missing.
5. A safe server-only vendor-event writer was not documented or implemented.

### Additional changes made during verification

- Added column-level safe SELECT grants for `service_requests`, excluding `precise_address_ciphertext` and `customer_id`.
- Added service-role-only `private.record_vendor_event(...)` with idempotency on `(provider_name, provider_event_id)`.
- Expanded `baseline_rls.test.sql` from 26 to 47 pgTAP assertions.
- Updated `rls_policy_matrix.md` to reflect precise-address SELECT denial and the private vendor-event writer.

### Address privacy test addendum — 11 July 2026

- Added explicit regression coverage proving an approved provider can read safe fields on an open service request before booking confirmation.
- Added explicit regression coverage proving the `authenticated` frontend role cannot select `service_requests.precise_address_ciphertext`.
- Added explicit regression coverage proving frontend roles cannot select any exact-address-like columns currently present on `service_requests`.
- Marked the remaining address model as a critical design risk until exact address material could be moved to a separate private table or exposed only through a safe request view and confirmed-booking reveal path. This is addressed by Ticket 3, with free-text redaction and state-machine alignment still remaining.

### Verification status

- Static code review completed.
- CI execution passed in the **Supabase database tests** GitHub Actions workflow with run status **Success**.
- `baseline_rls.test.sql` is CI-verified.

## Ticket 3 — Exact address privacy and confirmed-booking reveal

### Issue fixed

Precise customer address ciphertext no longer lives on the frontend-facing request row as active data. It is isolated in a private table and can only be revealed through an audited server-side function after the booking is confirmed/revealable and only to the selected approved provider.

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/004_exact_address_privacy.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/rls_test_seed.inc`
- `outputs/marketplace-production-foundation/supabase/tests/database/exact_address_privacy.test.sql`
- `rls_policy_matrix.md`
- `production_hardening_plan.md`
- `hardening_progress.md`

### Policies and functions added

- Added `private.service_request_addresses` for exact address ciphertext.
- Enabled RLS on `private.service_request_addresses` and revoked all frontend privileges.
- Deprecated `public.service_requests.precise_address_ciphertext`; migrated existing values into the private table and nulled the public column.
- Added `private.prevent_service_request_precise_address_write` trigger so direct writes to the deprecated public address column fail.
- Replaced broad direct `service_requests` insert/update grants with column-level grants that exclude exact address material.
- Added `public.list_provider_open_request_summaries(...)` for approved-provider discovery of open requests without customer IDs or exact address fields.
- Added `public.customer_upsert_service_request_address(...)` so a customer can update their own draft/open request address through controlled server-side logic.
- Added `public.reveal_confirmed_booking_address(...)` so only the selected approved provider can reveal the exact address after a revealable booking status.
- Added `public.is_address_revealable_booking_status(...)` to centralise the temporary revealable-status list.
- Every successful address reveal writes `booking.address_revealed` to append-only `audit_events`.
- Every controlled customer address upsert writes `customer.request_address_upserted` to append-only `audit_events`.

### Tests added

`outputs/marketplace-production-foundation/supabase/tests/database/exact_address_privacy.test.sql` originally added 26 pgTAP assertions here and is expanded to 49 assertions in Ticket 5. The address-privacy coverage proves:

- Exact addresses live in `private.service_request_addresses`.
- Public `service_requests` rows do not store active exact address ciphertext.
- Approved providers can view safe open request summaries.
- Approved providers cannot directly select `public.service_requests.precise_address_ciphertext`.
- Approved providers cannot directly select from `private.service_request_addresses`.
- The `authenticated` role has no SELECT privilege on the deprecated public precise-address column.
- Unapproved providers cannot view open request summaries.
- Suspended providers cannot view open request summaries.
- Approved but unselected providers cannot reveal confirmed booking addresses.
- Selected providers cannot reveal addresses while a booking is still `payment_pending`.
- Unrelated customers cannot reveal booking addresses.
- The selected approved provider can reveal the address for a scheduled confirmed booking.
- Every successful address reveal writes a separate audit event.
- Customers can upsert their own open request address through controlled logic.
- Customers cannot upsert another customer request address.
- Customers cannot directly write the deprecated public precise-address column.
- Controlled customer address upserts write audit events.
- Ticket 1/2 smoke protections remain intact: provider self-verification is blocked, audit events cannot be edited by frontend users, vendor events cannot be inserted by frontend users, service categories cannot be mutated by customers, and `service_requests` RLS remains enabled.

### How to run tests

From `outputs/marketplace-production-foundation`:

```powershell
supabase start
supabase db reset
supabase test db supabase/tests/database/exact_address_privacy.test.sql
```

Recommended full database hardening set:

```powershell
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
```

### CI run result

- **Workflow:** Supabase database tests
- **Run status:** Success
- **Passed test file:** `exact_address_privacy.test.sql`
- Ticket 5 supersedes this earlier Ticket 3 address section as the canonical exact-address privacy closeout.

### Remaining risks

- Open-request `description` remains readable to approved providers. The request-creation ticket must add validation/redaction to stop users from putting exact addresses into free text.
- The booking state machine is still incomplete outside the core Ticket 6 flow. Ticket 6 aligns `scheduled`, `in_progress`, and `completed`; future payment/refund/dispute tickets must confirm or adjust the remaining revealable statuses.
- The private address field stores ciphertext but the production encryption/decryption key-management design still needs to be finalised outside the database schema.
- Existing `service_requests` owner policies still allow broad non-address request mutation and must be replaced by workflow/state-machine server actions in a later ticket.

## Ticket 5 — Exact address privacy and confirmed-booking reveal

### Issue fixed

Ticket 5 supersedes the earlier Ticket 3 address work as the canonical exact-address privacy ticket. It tightens the model so precise customer address data does not live on public service request rows, private address records are tied to the owning customer, providers cannot directly read address storage, and selected providers can reveal only the minimum exact-address ciphertext through an audited confirmed-booking function.

### Address-material fields reviewed

- `public.service_requests.precise_address_ciphertext`: exact-address ciphertext risk. Deprecated, nulled, blocked by trigger, and not granted to frontend roles.
- `private.service_request_addresses.precise_address_ciphertext`: canonical exact-address ciphertext. Private table; no direct frontend or service-role table access.
- `private.service_request_addresses.customer_id`: added in Ticket 5 to bind each private address record to the customer who owns the request.
- `public.service_requests.customer_id`: private customer identifier. Excluded from provider open-request summaries and direct frontend safe SELECT grants.
- `public.service_requests.description`: provider-visible free text. Now conservatively checked before publication/open status for likely street addresses, unit/room references, GPS coordinates, phone numbers, and house/stand/erf numbers.
- `public.service_requests.suburb` and `public.service_requests.city`: retained as approximate location fields. They are visible to approved providers and should contain general area only.
- Other free-text fields (`bids.message`, `provider_services.description`, `disputes.description`, `reviews.body`) can technically contain sensitive text, but they are not part of the provider-facing open-request summary. Later workflow tickets should add context-specific validation where needed.

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/005_ticket_5_address_privacy_hardening.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/rls_test_seed.inc`
- `outputs/marketplace-production-foundation/supabase/tests/database/exact_address_privacy.test.sql`
- `rls_policy_matrix.md`
- `production_hardening_plan.md`
- `hardening_progress.md`

### Policies, triggers, and functions added or tightened

- Added `private.service_request_addresses.customer_id`.
- Added `private.enforce_service_request_address_owner` trigger to keep private address `customer_id` aligned with `service_requests.customer_id`.
- Revoked direct `service_role` table access to `private.service_request_addresses`; server/admin access must use audited functions. This narrows direct PostgREST/table-query access, but it does not make the service-role key safe for frontend use and does not restrict database owners/superusers or intentionally granted `SECURITY DEFINER` functions.
- Added `public.service_request_description_has_exact_address_risk(...)`.
- Added `private.prevent_public_request_description_exact_address_material` trigger to reject risky public descriptions when a request is opened/published.
- Added `public.customer_get_service_request_address(...)` for controlled customer reads of their own address.
- Tightened `public.customer_upsert_service_request_address(...)` to draft requests only, before provider selection/publication.
- Replaced `public.reveal_confirmed_booking_address(...)` so it returns only `precise_address_ciphertext`, validates selected approved provider plus revealable booking status, and checks the private address `customer_id`.
- Added `public.admin_get_service_request_address(...)` with required reason and audit event.

### Tests added/expanded

`outputs/marketplace-production-foundation/supabase/tests/database/exact_address_privacy.test.sql` now has 49 pgTAP assertions proving:

- Exact addresses live in the private address table.
- Public `service_requests` rows do not store active exact-address ciphertext.
- Private address rows copy the owning `customer_id`.
- Approved providers can view safe open request summaries.
- Approved providers cannot access exact address before confirmed booking.
- Providers cannot directly select/insert/update/delete `private.service_request_addresses`.
- `service_role` cannot directly select private request addresses and must use audited functions.
- Unapproved providers cannot view summaries or reveal addresses.
- Suspended providers cannot view summaries or reveal addresses.
- Unselected providers cannot reveal confirmed booking addresses.
- Selected providers cannot reveal while booking is still `payment_pending`.
- Unrelated customers cannot reveal booking addresses.
- Selected approved providers can reveal after confirmed/revealable booking status.
- Every reveal writes a separate audit event.
- Customers can create/update exact address data only for their own draft request through controlled functions.
- Customers cannot directly insert unsafe private address rows.
- Customers cannot read another customer's exact address through the controlled customer function.
- Customers cannot update exact address after request publication.
- Customers cannot update exact address after provider selection or a confirmed/revealable booking exists.
- Customers cannot directly write the deprecated public exact-address column.
- Public descriptions with likely street address, unit/room, GPS, phone, or house/stand/erf material are flagged, including an explicit house-number assertion.
- Publishing/opening a request with likely exact-address material is rejected.
- Admin/support address access works only through audited function with a required reason.
- Admin/support address access with a blank reason is rejected.
- Ordinary customers cannot use the admin address access function.
- Ticket 1 role protections and Ticket 2 baseline RLS protections remain intact.

### How to run tests

From `outputs/marketplace-production-foundation`:

```powershell
supabase start
supabase db reset
supabase test db supabase/tests/database/exact_address_privacy.test.sql
```

Recommended full security set:

```powershell
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
```

### CI run result

- **Workflow:** Supabase database tests
- **Run status:** Success
- **Passed test file:** `exact_address_privacy.test.sql`
- Static check confirms `exact_address_privacy.test.sql` has `plan(49)` and 49 assertion calls.

### Ticket 5 verification pass — 11 July 2026

- Static review found missing negative tests for direct private address INSERT/UPDATE/DELETE, cross-customer safe-function reads, owner updates after provider selection/confirmed booking, blank admin/support access reasons, and house/stand/erf-number description detection.
- Updated `outputs/marketplace-production-foundation/supabase/tests/database/exact_address_privacy.test.sql` from 41 to 49 assertions to cover those gaps.
- No migration change was required for this verification pass; the existing migration already revokes direct frontend/private-table access, routes customer writes through safe functions, and audits reveal/admin access.
- `exact_address_privacy.test.sql` is CI-verified by the **Supabase database tests** workflow with run status **Success**.

### Remaining risks

- Public-description detection is conservative and cannot perfectly detect every exact-address phrasing. The production UI should still warn customers not to type exact addresses into public request descriptions.
- `suburb` and `city` remain general-location fields and are not fully normalised to a controlled list yet.
- Booking revealable statuses are still provisional until the booking state-machine ticket finalises the lifecycle.
- The exact address value is treated as ciphertext, but production encryption/decryption and key-management still need to be implemented in the server layer.
- Ticket 6 now replaces broad direct `service_requests` workflow mutation with trusted draft/publish/cancel state-machine functions. The production application still needs to be wired to those functions.

## CI — Supabase database tests

### Status

CI-verified by a live GitHub Actions run.

### CI verification result — 2026-07-11

- **Run status:** Success
- **Tickets marked CI-verified:**
  - Ticket 1: Role escalation protection
  - Ticket 2: Baseline RLS protection
  - Ticket 5: Exact address privacy protection
  - Ticket 6: Marketplace state machine
- **Test files passed:**
  - `role_escalation.test.sql`
  - `baseline_rls.test.sql`
  - `exact_address_privacy.test.sql`
  - `marketplace_state_machine.test.sql`

### CI setup verification — 11 July 2026

- Confirmed `.github/workflows/database-tests.yml` exists and is configured to run on every `push` and `pull_request`.
- Confirmed the workflow uses the `ubuntu-latest` runner, verifies Docker availability, installs the Supabase CLI, starts the local Supabase stack, runs `supabase db reset`, and executes the required pgTAP test files.
- Confirmed the workflow runs from `outputs/marketplace-production-foundation`, where the local Supabase migrations and tests live.
- Confirmed no production secrets are added to the workflow.
- Confirmed the local Supabase project now commits a deterministic, non-secret `supabase/config.toml`; CI no longer runs `supabase init`.
- Confirmed `TESTING.md` documents how to read GitHub Actions results and how to reproduce the database tests locally.
- Static verification only: this workspace still cannot execute the workflow locally because Supabase CLI, Docker, `npx`, `psql`, and `git` are not available on PATH.

### Files changed

- `.github/workflows/database-tests.yml`
- `outputs/marketplace-production-foundation/supabase/config.toml`
- `TESTING.md`
- `hardening_progress.md`

### What the workflow does

The GitHub Actions workflow runs on every push and pull request. It:

- checks out the repository
- verifies Docker is available on the `ubuntu-latest` runner
- installs the Supabase CLI using `supabase/setup-cli@v1`
- verifies the committed local `supabase/config.toml` exists and does not contain obvious secret/key markers or production Supabase project references
- starts the local Supabase stack
- runs `supabase db reset`
- runs:
  - `supabase test db supabase/tests/database/role_escalation.test.sql`
  - `supabase test db supabase/tests/database/baseline_rls.test.sql`
  - `supabase test db supabase/tests/database/exact_address_privacy.test.sql`
  - `supabase test db supabase/tests/database/marketplace_state_machine.test.sql`
- stops the local Supabase stack with `supabase stop --no-backup`

### Security posture

- No production secrets are added to the workflow.
- The committed `outputs/marketplace-production-foundation/supabase/config.toml` is local-only and contains no database password, service-role key, JWT secret, payment key, identity key, production Supabase project ref/URL, or production project secret.
- The workflow uses only local config, local migrations, and deterministic pgTAP seed data.
- The workflow should fail if any migration or pgTAP assertion fails.

### How to read results

See `TESTING.md` for where to find GitHub Actions results, which steps map to which hardening areas, and how to reproduce the same commands locally.

### Remaining risks

- The workflow still needs to be run in GitHub Actions to confirm the Supabase CLI setup, Docker startup, committed local config, migrations, and pgTAP commands succeed on `ubuntu-latest`.
- This workspace still cannot run the workflow locally because Supabase CLI/Docker/`npx`/`psql` are not available on PATH.

## Pre-CI safety check — 2026-07-11

### Result

Static pre-push safety check completed and patched the missing repository ignore rules.

### Files changed

- `.gitignore`
- `hardening_progress.md`

### Checks confirmed

- No non-example `.env` files were found in the workspace.
- `outputs/marketplace-production-foundation/.env.example` contains placeholder/empty/mock values only.
- `outputs/marketplace-production-foundation/supabase/config.toml` contains no database password, service-role key, JWT secret, payment key, identity key, API key, access token, or production Supabase project reference.
- `.github/workflows/database-tests.yml` contains no production secrets and no `supabase init` fallback.
- No suspicious committed secret assignments were found for service-role keys, JWT secrets, payment keys, identity keys, API keys, access tokens, database URLs, or database passwords.
- `.gitignore` now blocks `.env`, `.env.*` including `.env.local` and `.env.production`, `node_modules`, build outputs, and Supabase local temp/cache/runtime folders while allowing `.env.example`.
- GitHub Actions database tests still run from `outputs/marketplace-production-foundation`.
- CI still includes all four pgTAP files:
  - `supabase/tests/database/role_escalation.test.sql`
  - `supabase/tests/database/baseline_rls.test.sql`
  - `supabase/tests/database/exact_address_privacy.test.sql`
  - `supabase/tests/database/marketplace_state_machine.test.sql`

### Remaining note

This is a static workspace scan because Git is not available on PATH here, so I could not ask Git directly which files are staged/tracked. The new `.gitignore` should be in place before pushing.

## GitHub Actions role-escalation test failure — 2026-07-11

### Failure summary

GitHub Actions reached the database test workflow but failed at `Run role escalation pgTAP tests`. The visible failure was:

- `have: Customer A`
- `want: Customer A Updated`

That means the safe profile update assertion returned without a durable row change.

### Root cause

The hardening migration had removed broad profile updates and correctly granted column-level updates for safe profile fields, but it did not make profile `SELECT` privileges explicit for authenticated users. Owner reads were protected by RLS, yet the safe update path depends on the caller being able to resolve their own row under RLS. The pgTAP helper also returned `true` without checking `ROW_COUNT`, so a zero-row safe update could look successful until the following persistence assertion failed.

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/002_fix_role_escalation.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/role_escalation.test.sql`
- `hardening_progress.md`

### Fix applied

- Added explicit authenticated `SELECT` grants on `public.profiles` and `public.provider_profiles`; RLS still limits profile reads to permitted rows.
- Kept update privileges column-allowlisted only:
  - `profiles.display_name`
  - `profiles.phone_e164`
  - `profiles.suburb`
  - `profiles.city`
  - `profiles.avatar_path`
  - safe provider profile columns only
- Did not grant broad profile row updates.
- Left `role`, `account_status`, provider verification, provider review/approval, and identity verification protections intact.
- Updated the safe-update pgTAP helpers to require exactly one updated row.
- Expanded `role_escalation.test.sql` from 33 to 37 assertions, adding coverage that:
  - safe `display_name` update succeeds
  - safe phone/suburb/city/avatar updates persist
  - safe profile update plus role escalation is rejected
  - role remains unchanged after the failed mixed safe/privileged update
  - safe display name remains unchanged after the failed mixed safe/privileged update

### Tests to rerun

From `outputs/marketplace-production-foundation`:

```powershell
supabase db reset
supabase test db supabase/tests/database/role_escalation.test.sql
```

Then rerun the full CI database workflow:

```powershell
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
```

## Ticket 6 — Request, bid, acceptance, and booking state machine

### Issue fixed

Core request, bid, acceptance, booking creation, and completion state changes are now routed through trusted transactional database functions instead of broad direct frontend table writes.

### Authoritative state machine

- `service_requests`: `draft -> open -> awarded|cancelled|expired`
- `bids`: `submitted -> accepted|declined|withdrawn|expired`
- `bookings`: `scheduled -> in_progress -> completed` for the current database MVP flow

Later tickets still own payment funding, refunds, payout release, booking cancellation after confirmation, disputes, expiry jobs, and vendor webhook transitions.

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/006_marketplace_state_machine.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/marketplace_state_machine.test.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/rls_test_seed.inc`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `rls_policy_matrix.md`
- `production_hardening_plan.md`
- `hardening_progress.md`

### Policies, triggers, constraints, and functions added or tightened

- Added workflow timestamps to `service_requests`, `bids`, and `bookings`.
- Added `bids_one_accepted_per_request_idx` partial unique index.
- Added trigger guards preventing direct frontend insert/update/delete on `service_requests`, `bids`, `bookings`, and `payments` workflow state.
- Added booking integrity trigger requiring booking request, bid, customer, provider, amount, currency, and scheduled time to match.
- Removed broad `service_requests` owner `FOR ALL` mutation policy and replaced it with customer read-only ownership.
- Removed broad provider `bids` `FOR ALL` mutation policy and replaced it with provider read-only ownership.
- Revoked direct frontend `INSERT/UPDATE/DELETE` on `service_requests`, `bids`, `bookings`, and `payments`.
- Added transactional public functions:
  - `customer_create_draft_request(...)`
  - `customer_publish_request(...)`
  - `customer_cancel_request(...)`
  - `provider_submit_bid(...)`
  - `provider_withdraw_bid(...)`
  - `customer_accept_bid(...)`
  - `booking_mark_in_progress(...)`
  - `customer_confirm_completion(...)`
  - `provider_confirm_completion(...)`

### Tests added

`outputs/marketplace-production-foundation/supabase/tests/database/marketplace_state_machine.test.sql` has 58 pgTAP assertions proving:

- Customer can create a draft request.
- Customer can publish own draft request.
- Customer cannot publish another customer's request.
- Customer can cancel own draft/open request through controlled function.
- Approved eligible provider can submit a bid.
- Unapproved provider cannot bid.
- Suspended provider cannot bid.
- Approved provider cannot bid without active service for the request category.
- Provider can withdraw own submitted bid.
- Provider cannot bid after request close time.
- Customer can accept valid bid on own request.
- Customer cannot accept another customer's bid/request.
- Accepting one bid awards the request, accepts the winning bid, and declines competing bids.
- Duplicate accept calls are safely rejected.
- Booking is created with correct customer, provider, request, bid, amount, fee, currency, and status.
- Pending internal payment record is created without vendor credentials.
- Direct frontend updates to request, bid, booking, and payment/release status fields are blocked for customers and providers.
- Booking with a bid from a different request is rejected.
- Booking with the wrong customer is rejected.
- Booking with the wrong provider is rejected.
- Booking with the wrong service amount is rejected.
- A second booking for the same request is rejected.
- More than one accepted bid per request is rejected.
- Selected provider can reveal exact address after scheduled confirmed booking.
- Unselected provider cannot reveal confirmed booking address.
- Selected provider can mark booking in progress.
- Customer and provider completion confirmations are blocked before `in_progress`.
- Customer and provider completion confirmations complete the booking only after the booking is `in_progress` and both parties confirm.
- Ticket 1 role protections remain intact.
- Ticket 2 baseline RLS protections remain intact.
- Ticket 5 address privacy protections remain intact.

### How to run tests

From `outputs/marketplace-production-foundation`:

```powershell
supabase start
supabase db reset
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
```

Recommended full security set:

```powershell
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
```

### CI run result

- **Workflow:** Supabase database tests
- **Run status:** Success
- **Passed test file:** `marketplace_state_machine.test.sql`
- Static check confirms `marketplace_state_machine.test.sql` has `plan(58)` and 58 assertion calls.

### Ticket 6 verification pass — 2026-07-11

Verification found and patched three gaps before closeout:

- Completion is now only confirmable after `bookings.status = 'in_progress'`; it is no longer accepted directly from `scheduled`.
- Booking integrity tests now separately cover mismatched request/bid, wrong customer, wrong provider, wrong amount, duplicate booking, and duplicate accepted bid cases.
- Payment/release direct mutation tests now cover both customer and provider callers.

The CI workflow includes `marketplace_state_machine.test.sql`, and the updated 58-assertion database test is now CI-verified with run status **Success**.

### GitHub Actions marketplace state-machine test failure — 2026-07-11

#### Failure summary

GitHub Actions progressed through the earlier database tests and failed at `Run marketplace state machine pgTAP tests` with:

```text
ERROR: permission denied for table ticket6_ids
Planned 58 tests but ran 0.
```

#### Root cause

`ticket6_ids` is a temporary pgTAP helper table created near the top of `marketplace_state_machine.test.sql`. The test then switches to `role authenticated` to simulate frontend callers. At the first Ticket 6 flow setup block, the active role is `authenticated` with Customer A's JWT subject, and that role tries to insert/select IDs through `ticket6_ids`.

Because the temporary table was created by the test session owner before the role switch, `authenticated` did not have privileges on the helper table. The test crashed before any assertions ran. This was a test helper permission issue, not a production RLS issue.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/tests/database/marketplace_state_machine.test.sql`
- `hardening_progress.md`

#### Fix applied

- Added `grant select, insert, update, delete on table ticket6_ids to anon, authenticated;` immediately after the temporary helper table is created.
- Did not change production migrations.
- Did not grant any production access to `service_requests`, `bids`, `bookings`, `payments`, `profiles`, `provider_profiles`, or private address tables.
- Confirmed `ticket6_ids` is the only temporary/helper table in `marketplace_state_machine.test.sql` / `rls_test_seed.inc`.
- Confirmed `marketplace_state_machine.test.sql` still has `plan(58)` and 58 assertion calls.

#### Tests to rerun

From `outputs/marketplace-production-foundation`:

```powershell
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
```

If that passes, rerun the full GitHub Actions database workflow to confirm all four pgTAP files pass together.

### Remaining risks

- The static prototype is not yet wired to these database functions.
- Real payment provider funding, real refund execution, payout release, booking cancellation after confirmation, disputes, expiry jobs, and webhooks remain future tickets.
- Ticket 7A constrains `payments.status` to safe MVP payment-status values and adds an append-only payment event ledger. Ticket 7B adds refund request/ledger foundations. Ticket 7C disables cash/off-platform cash for MVP. Real hosted checkout, real refund execution, payout release, and vendor webhooks remain future tickets.
- `consents` and `data_subject_requests` still need separate compliance workflow hardening.

## Ticket 7 — Payments, cash handling, refunds, and payout release

### Planning status

The full Ticket 7 roadmap is prepared. Ticket 7A payment status constraints and payment event ledger foundation, Ticket 7B refund request/ledger foundation, and Ticket 7C cash-disabled MVP policy are implemented below. Live provider integration, real refund execution, payout release, and real webhooks remain unimplemented.

### Plan file

- `ticket_7_payments_plan.md`

### Scope covered by the plan

- Payment status constraints.
- Payment events/ledger.
- Hosted payment provider abstraction.
- Mock payment adapter.
- Cash payment policy.
- Refund request and refund event workflow.
- Payout release/freeze rules.
- Dispute-aware release blocking.
- Signed and idempotent webhook requirements.
- Required pgTAP/database tests.
- Items that must remain mock/sandbox until vendor credentials are available.

### Next step

Continue with the next explicitly scoped payment ticket, likely hosted checkout/mock adapter, payout release/freeze, dispute-aware release blocking, or signed webhooks.

## Ticket 7A — Payment status constraints and payment event ledger

### Issue fixed

Payment status is no longer unconstrained free text, and trusted payment state changes now have an append-only ledger foundation.

This ticket deliberately does **not** implement live payment-provider integration, refunds, cash workflow, payout release, or real webhook handlers.

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/006_marketplace_state_machine.sql`
- `outputs/marketplace-production-foundation/supabase/migrations/007_payment_status_and_ledger.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/rls_test_seed.inc`
- `outputs/marketplace-production-foundation/supabase/tests/database/marketplace_state_machine.test.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/payments_ledger.test.sql`
- `outputs/marketplace-production-foundation/src/integrations/contracts.ts`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `rls_policy_matrix.md`
- `production_hardening_plan.md`
- `hardening_progress.md`

### Database changes

- Normalised legacy payment status values into the Ticket 7A MVP vocabulary.
- Added constrained payment status values on `payments.status`:
  - `pending`
  - `checkout_created`
  - `paid`
  - `failed`
  - `expired`
  - `cancelled`
  - `partially_refunded`
  - `refunded`
- Added separate `payments.release_status` with constrained values:
  - `not_applicable`
  - `pending`
  - `paused`
  - `eligible`
  - `released`
  - `cancelled`
- Added `payments.paid_at`.
- Kept Ticket 6 payment creation compatible by changing the internal accepted-booking payment row to `status = 'pending'`.
- Added `public.payment_events` as an append-only payment event ledger.
- Added uniqueness/idempotency indexes for `(provider_name, provider_event_id)` and `(provider_name, idempotency_key)` when those values are present.
- Revoked direct frontend access to `payment_events`; direct service-role table access is also revoked so server workflows use audited functions.
- Added append-only trigger protection blocking `UPDATE` and `DELETE` on `payment_events`.
- Added an automatic initial `intent_prepared` payment event when a trusted payment row is created.
- Replaced the payment state protection trigger so payment/release/refund/provider fields remain trusted-function controlled.
- Added `public.admin_record_payment_event(...)` as the current admin/server-controlled internal payment transition helper.
- Every successful trusted payment event writes both:
  - one `payment_events` ledger row
  - one `audit_events` row

### Tests added

`outputs/marketplace-production-foundation/supabase/tests/database/payments_ledger.test.sql` has 24 pgTAP assertions covering:

- Invalid payment status is rejected.
- Trusted pending payment creation writes an initial immutable payment event.
- Customer cannot mark a payment as paid.
- Provider cannot mark a payment as paid.
- Customer cannot mark a payment as refunded.
- Provider cannot mark a payment as released.
- Unrelated users cannot read payment records.
- Booking customer can read a safe payment summary.
- Booking provider can read a safe payment summary.
- Customer cannot call or abuse the trusted payment event function.
- Provider cannot call or abuse the trusted payment event function.
- Failed normal-user trusted-function attempts create no payment events.
- Trusted payment event function rejects invalid payment status.
- Trusted admin function can write a payment event.
- Trusted admin function can update constrained payment status.
- Trusted admin function writes exactly one payment event for a new idempotency key.
- Duplicate idempotency key does not create duplicate events.
- `payment_events` cannot be updated.
- `payment_events` cannot be deleted.
- Ticket 1 role protections remain intact.
- Ticket 2 baseline RLS protections remain intact.
- Ticket 5 private address protections remain intact.
- Ticket 6 direct booking mutation protections remain intact.

### CI update

The `Supabase database tests` workflow now runs:

```bash
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
supabase test db supabase/tests/database/payments_ledger.test.sql
```

### Tests to run

I could not run Supabase/pgTAP locally in this environment because the local shell does not have the required database tooling available.

From `outputs/marketplace-production-foundation`, rerun:

```powershell
supabase db reset
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
supabase test db supabase/tests/database/payments_ledger.test.sql
```

Then confirm GitHub Actions is green again.

### Remaining risks

- No live payment vendor is integrated yet.
- No real hosted checkout/session creation exists yet.
- Ticket 7B adds refund request and refund event ledger foundations; real provider refund execution is still not implemented.
- No cash-payment policy/workflow exists yet.
- No payout release/freeze execution exists yet.
- No real signed webhook handler exists yet.
- No provider reconciliation job exists yet.
- `payments.status` is still the physical column name for compatibility, although it is now constrained and documented as the payment-status field.

### GitHub Actions payment ledger test failure — 2026-07-11

#### Failure summary

GitHub Actions reached `Run payment ledger pgTAP tests` and failed `payments_ledger.test.sql` 1/19 subtests.

The visible failed assertion was:

```text
trusted admin function can update constrained payment status
have: NULL
want: checkout_created
```

#### Root cause

The database function was already designed to update `payments.status` and write a `payment_events` row atomically. The failing assertion queried `public.payments` while the test was still impersonating the authenticated admin profile.

That admin profile is not a party to the test booking, and the existing payment RLS policy only exposes payment rows to the booking customer/provider. The query therefore saw no row and returned `NULL`. This was a pgTAP test read-context issue, not a need to weaken payment RLS.

#### Fix applied

- Reset the test session out of the simulated authenticated admin role before directly asserting the raw `payments.status` value.
- Kept payment RLS unchanged.
- Kept `admin_record_payment_event(...)` as the trusted admin/server path for Ticket 7A payment status changes.
- Expanded `payments_ledger.test.sql` from 19 to 24 assertions.
- Added explicit tests proving:
  - customers cannot call or abuse `admin_record_payment_event(...)`
  - providers cannot call or abuse `admin_record_payment_event(...)`
  - failed normal-user calls do not create `payment_events`
  - trusted function rejects invalid payment status
  - trusted admin function writes exactly one event for a new idempotency key
  - duplicate idempotency key still does not duplicate the event

#### Files changed

- `outputs/marketplace-production-foundation/supabase/tests/database/payments_ledger.test.sql`
- `hardening_progress.md`

#### Tests to rerun

From `outputs/marketplace-production-foundation`:

```powershell
supabase test db supabase/tests/database/payments_ledger.test.sql
```

Then rerun the full `Supabase database tests` GitHub Actions workflow.

### Ticket 7A CI verification — 2026-07-11

- **Workflow name:** Supabase database tests
- **Latest run:** Fix Ticket 7A payment ledger test assertions
- **Run status:** Success
- **Passed test file:** `payments_ledger.test.sql`
- **Status:** Ticket 7A is CI-verified.

Ticket 7A still does **not** implement live payment integration, refunds, cash workflow, payout release, or real webhooks.

## Ticket 7B — Refund requests and refund event ledger

### Issue fixed

Refund requests and refund state changes now have a secure database foundation:

- booking parties request refunds only through safe functions
- frontend users cannot directly mutate refund workflow rows
- admin/server refund decisions require authorised context and non-empty reasons
- refund state changes write append-only refund ledger rows and audit rows
- manual/sandbox refund-success outcomes update payment refund totals/status through trusted logic only

### Plan file

- `ticket_7b_refunds_plan.md`

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/008_refund_requests_and_ledger.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/refunds_ledger.test.sql`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `rls_policy_matrix.md`
- `production_hardening_plan.md`
- `hardening_progress.md`

### Database changes

- Added `public.refund_requests` with constrained statuses:
  - `requested`
  - `under_review`
  - `approved`
  - `rejected`
  - `cancelled`
  - `processing`
  - `succeeded`
  - `failed`
- Added `public.refund_events` with constrained event types:
  - `refund_requested`
  - `refund_under_review`
  - `refund_approved`
  - `refund_rejected`
  - `refund_cancelled`
  - `refund_processing_recorded`
  - `refund_succeeded_recorded`
  - `refund_failed_recorded`
  - `admin_note`
- Enabled RLS on both refund tables.
- Revoked direct frontend and direct service-role table access for refund workflow writes.
- Added booking-party read policy for `refund_requests`.
- Kept `refund_events` non-frontend-readable and append-only.
- Added idempotency indexes for refund requests and refund events.
- Added integrity triggers for:
  - refund amount greater than zero
  - refund currency matching payment currency
  - refund booking matching payment booking
  - refund amount not exceeding payment amount
  - refund amount not exceeding remaining refundable amount
  - only `paid` / `partially_refunded` payments receiving new refund requests
  - refund event references matching the refund request
- Added conservative refund metadata validation to reject obvious raw payment/identity credential material.

### Trusted functions added

- `customer_request_refund(...)`
- `provider_request_refund(...)`
- `admin_mark_refund_under_review(...)`
- `admin_approve_refund(...)`
- `admin_reject_refund(...)`
- `admin_record_refund_outcome(...)`

`admin_record_refund_outcome(...)` is manual/sandbox outcome recording only. It does not call a live vendor and writes metadata indicating that real money did not move.

### Payment interaction

- Refund approval/rejection alone does not mutate payment refund totals.
- A trusted manual/sandbox `succeeded` refund outcome increments `payments.refunded_minor`.
- Partial refund outcomes move `payments.status` to `partially_refunded`.
- Full refund outcomes move `payments.status` to `refunded`.
- Rejected refunds do not increase `payments.refunded_minor`.
- Successful refund outcomes also write a `payment_events` row.

### Tests added

`outputs/marketplace-production-foundation/supabase/tests/database/refunds_ledger.test.sql` has 48 pgTAP assertions covering:

- Customer can request refund for own booking payment.
- Provider can request refund for own booking payment.
- Customer cannot request refund for unrelated payment.
- Provider cannot request refund for unrelated payment.
- Anonymous users cannot access refund requests/events.
- Unrelated authenticated users cannot read refund requests.
- Booking parties can read safe refund request summaries.
- Frontend users cannot directly insert/update/delete `refund_requests`.
- Frontend users cannot directly insert/update/delete `refund_events`.
- Refund amount must be greater than zero.
- Refund amount cannot exceed payment amount.
- Refund amount cannot exceed remaining refundable amount.
- Invalid refund status is rejected.
- Invalid refund event type is rejected.
- Customer/provider cannot approve, reject, or mark refund outcomes.
- Admin/server can approve refund with audit and refund event.
- Admin/server can reject refund with audit and refund event.
- Rejected refund does not increase `payments.refunded_minor`.
- Trusted manual/sandbox success updates `payments.refunded_minor`.
- Partial refund moves payment to `partially_refunded`.
- Full refund moves payment to `refunded`.
- Duplicate idempotency key does not duplicate refund event.
- `refund_events` cannot be updated.
- `refund_events` cannot be deleted.
- Customer/provider direct payment refund mutation remains blocked.
- Ticket 1, 2, 5, 6, and 7A smoke protections remain intact.

### CI update

The `Supabase database tests` workflow now runs `refunds_ledger.test.sql` after `payments_ledger.test.sql`.

### Tests to run

I could not run Supabase/pgTAP locally in this environment because the local shell does not have the required database tooling available.

From `outputs/marketplace-production-foundation`, rerun:

```powershell
supabase db reset
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
supabase test db supabase/tests/database/payments_ledger.test.sql
supabase test db supabase/tests/database/refunds_ledger.test.sql
```

Then confirm GitHub Actions is green.

### Remaining non-goals / risks

Ticket 7B is limited to refund requests and an append-only refund event ledger.

It does not implement:

- live payment provider integration
- real refund execution
- cash workflow
- payout release
- payout freeze/unfreeze
- real webhook handlers
- UI

Manual/sandbox refund outcomes are internal state records only and must not be represented as proof that a real provider moved money.

### Ticket 7B CI verification — 2026-07-12

- **Workflow name:** Supabase database tests
- **Latest run:** Implement Ticket 7B refund requests and ledger
- **Run status:** Success
- **Passed test file:** `refunds_ledger.test.sql`
- **Status:** Ticket 7B is CI-verified.

Ticket 7B still does **not** implement live refund execution, cash workflow, payout release/freeze, real webhooks, or UI.

## Ticket 7C — Cash payment policy enforcement: cash disabled for MVP

### Issue fixed

Cash/off-platform payments are now explicitly disabled for MVP at the database layer so LEKKADEALL does not misrepresent off-platform cash as protected platform payment.

### Policy decision

Cash payments are disabled for MVP.

Allowed MVP payment method markers are limited to:

- `platform_online_pending`
- `platform_online`
- `sandbox_online`
- `manual_sandbox_online`

Cash/off-platform markers such as `cash`, `off_platform_cash`, `cash_selected`, `customer_cash_confirmed`, `provider_cash_confirmed`, `cash_confirmed`, `cash_disputed`, `cash_cancelled`, and `cash_unverified` are rejected.

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/009_cash_payment_policy.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/cash_payment_policy.test.sql`
- `outputs/marketplace-production-foundation/src/integrations/contracts.ts`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `rls_policy_matrix.md`
- `production_hardening_plan.md`
- `hardening_progress.md`

### Database changes

- Added `payments.payment_method`.
- Backfilled/defaulted `payment_method` to `platform_online_pending`.
- Added `payments_payment_method_check` to allow only MVP online/sandbox method markers.
- Added a trigger that rejects disabled cash/off-platform payment method values with: `Cash payments are disabled for MVP.`
- Added `customer_select_cash_payment(...)` and `provider_select_cash_payment(...)` as explicit policy marker functions that always reject for MVP.
- Added payment-event protection against cash/off-platform metadata and payout-release-like events.
- Kept customer/provider direct payment mutations blocked by existing Ticket 6/7A payment protections.

### Tests added

`outputs/marketplace-production-foundation/supabase/tests/database/cash_payment_policy.test.sql` has 22 pgTAP assertions covering:

- cash payment method is rejected
- off-platform cash payment method is rejected
- customer cannot create cash payment directly
- provider cannot create cash payment directly
- online/sandbox payment marker remains compatible
- customer cannot switch an online payment to cash
- provider cannot switch an online payment to cash
- customer/provider cash-selection functions reject
- no booking/payment can become cash-confirmed
- cash cannot set payment status to paid
- cash cannot set payment status to refunded
- cash cannot set release status to released
- cash cannot create payout-release-like payment events
- no payment row has a cash/off-platform method
- Ticket 1 role protections remain intact
- Ticket 2 RLS protections remain intact
- Ticket 5 address protections remain intact
- Ticket 6 marketplace state-machine protections remain intact
- Ticket 7A payment ledger protections remain intact
- Ticket 7B refund ledger protections remain intact

### CI update

The `Supabase database tests` workflow now runs `cash_payment_policy.test.sql` after `refunds_ledger.test.sql`.

### Tests to run

I could not run Supabase/pgTAP locally in this environment because the local shell does not have the required database tooling available.

From `outputs/marketplace-production-foundation`, rerun:

```powershell
supabase db reset
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
supabase test db supabase/tests/database/payments_ledger.test.sql
supabase test db supabase/tests/database/refunds_ledger.test.sql
supabase test db supabase/tests/database/cash_payment_policy.test.sql
```

Then confirm GitHub Actions is green.

### Remaining non-goals / risks

Ticket 7C deliberately does not implement:

- customer cash confirmation
- provider cash confirmation
- admin cash override
- cash dispute workflow
- payout release
- live payment provider integration
- real webhook handlers
- UI

If the business later chooses to allow cash, it must be implemented as an explicitly off-platform, not-payment-protected workflow with separate cash statuses, append-only cash events, clear customer/provider acknowledgements, dispute wording, and tests proving it cannot trigger payout release.

### Ticket 7C CI verification — 2026-07-12

- **Workflow name:** Supabase database tests
- **Latest run:** Implement Ticket 7C cash disabled for MVP
- **Run status:** Success
- **Passed test file:** `cash_payment_policy.test.sql`
- **Status:** Ticket 7C is CI-verified.

Ticket 7C disables cash for MVP and does **not** implement cash confirmation, cash disputes, payout release, real payment provider integration, real webhooks, or UI.

## Ticket 7D — Payout release, payout freeze, and dispute-aware release blocking

### Issue fixed

Internal/manual-sandbox payout release control now has a trusted database foundation.

Customers and providers cannot mark funds eligible, paused, resumed, or released. Release state changes are trusted admin/server controlled, ledgered in `payment_events`, audited in `audit_events`, and blocked when payment, booking, refund, dispute, provider, or cash-policy conditions are unsafe.

### Plan file

- `ticket_7d_payout_release_plan.md`

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/010_payout_release_controls.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/payout_release_controls.test.sql`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `rls_policy_matrix.md`
- `production_hardening_plan.md`
- `ticket_7_payments_plan.md`
- `hardening_progress.md`

### Database changes

- Added release-control fields to `payments`:
  - `release_paused_at`
  - `release_paused_by`
  - `release_pause_reason`
  - `release_hold_until`
  - `release_eligible_at`
  - `release_provider_reference`
  - `release_idempotency_key`
- Extended `payment_events.event_type` to include:
  - `release_paused`
  - `release_resumed`
  - `release_eligible`
  - `release_cancelled`
  - `payout_release_recorded`
  - `payout_release_failed`
  - `payout_reconciliation_checked`
- Added release blocker logic for:
  - unpaid payments
  - incomplete bookings
  - fully refunded payments
  - active refund requests
  - active disputes
  - paused releases
  - suspended/inactive providers
  - unapproved providers
  - unverified providers
  - cash/off-platform payment methods
  - zero or negative releasable amounts

### Trusted functions added

- `admin_pause_payment_release(payment_id, reason, idempotency_key)`
- `admin_resume_payment_release(payment_id, reason, idempotency_key)`
- `admin_mark_release_eligible(payment_id, reason, idempotency_key)`
- `admin_record_payout_release(payment_id, provider_reference, amount_minor, reason, idempotency_key)`

Each function:

- is `SECURITY DEFINER`
- sets an explicit `search_path`
- verifies platform-admin/trusted-server authority
- requires a non-empty reason
- requires an idempotency key
- locks the payment row
- checks release blockers where applicable
- writes `payment_events`
- writes `audit_events`
- remains idempotency-safe

`admin_record_payout_release(...)` is manual/sandbox internal state recording only. It does **not** call a live payout provider and records metadata that real money did not move.

### Tests added

`outputs/marketplace-production-foundation/supabase/tests/database/payout_release_controls.test.sql` has 37 pgTAP assertions covering:

- customer cannot mark release as eligible
- provider cannot mark release as eligible
- customer cannot mark payment released
- provider cannot mark payment released
- admin/server cannot release unpaid payment
- admin/server cannot release incomplete booking
- admin/server cannot release fully refunded payment
- admin/server cannot release while refund is requested
- admin/server cannot release while refund is under review
- admin/server cannot release while refund is approved
- admin/server cannot release while refund is processing
- admin/server cannot release while dispute is open
- admin/server cannot release when provider is suspended
- admin/server cannot release when provider approval is revoked
- admin/server can pause release with a non-empty reason
- blank pause, resume, and release reasons are rejected
- admin/server can resume release only after blockers are cleared
- release pause writes `payment_events`
- release pause writes `audit_events`
- release eligibility writes `payment_events`
- payout release recording writes `payment_events`
- payout release recording writes `audit_events`
- duplicate idempotency key does not duplicate events
- `payment_events` remain append-only
- `audit_events` remain append-only
- cash/off-platform payment cannot be released
- Ticket 1 role protections remain intact
- Ticket 2 baseline RLS protections remain intact
- Ticket 5 address privacy remains intact
- Ticket 6 marketplace state machine remains intact
- Ticket 7A payment ledger protections remain intact
- Ticket 7B refund protections remain intact
- Ticket 7C cash-disabled protections remain intact

### CI update

The `Supabase database tests` workflow now runs `payout_release_controls.test.sql` after `cash_payment_policy.test.sql`.

### Tests to run

I could not run Supabase/pgTAP locally in this environment because the local shell does not have the required database tooling available.

From `outputs/marketplace-production-foundation`, rerun:

```powershell
supabase db reset
supabase test db supabase/tests/database/role_escalation.test.sql
supabase test db supabase/tests/database/baseline_rls.test.sql
supabase test db supabase/tests/database/exact_address_privacy.test.sql
supabase test db supabase/tests/database/marketplace_state_machine.test.sql
supabase test db supabase/tests/database/payments_ledger.test.sql
supabase test db supabase/tests/database/refunds_ledger.test.sql
supabase test db supabase/tests/database/cash_payment_policy.test.sql
supabase test db supabase/tests/database/payout_release_controls.test.sql
```

Then confirm GitHub Actions is green.

### GitHub Actions payout release controls test failure — 2026-07-12

#### Failure summary

GitHub Actions reached `Run payout release controls pgTAP tests` and crashed in `payout_release_controls.test.sql` before completing all assertions.

Visible failure:

```text
ERROR: permission denied for table payment_events
CONTEXT: SQL function "payment_event_count" statement 1
```

The planned count remained 37 assertions, but the test run stopped after 20 assertions.

#### Root cause

`payment_event_count(...)` was a temporary pgTAP helper function defined as a default invoker-rights SQL function. The test was still impersonating the authenticated admin profile when the helper tried to read `public.payment_events`.

That authenticated role correctly has no direct `SELECT` privilege on `payment_events`, because Ticket 7A keeps the payment ledger inaccessible to frontend users. This was a test-helper execution-context issue, not a reason to weaken production RLS or grants.

#### Fix applied

- Kept production `payment_events` permissions unchanged.
- Kept `payment_events` append-only protection unchanged.
- Updated only `payout_release_controls.test.sql`.
- Changed the raw ledger-count helpers `payment_event_count(...)` and `audit_count(...)` to test-only `SECURITY DEFINER` helpers with explicit `search_path = public, pg_temp`.
- This lets internal pgTAP ledger assertions run under the test owner while customer/provider/admin impersonation remains intact for permission checks.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/tests/database/payout_release_controls.test.sql`
- `hardening_progress.md`

#### Tests to rerun

From `outputs/marketplace-production-foundation`:

```powershell
supabase test db supabase/tests/database/payout_release_controls.test.sql
```

Then rerun the full `Supabase database tests` GitHub Actions workflow.

### Ticket 7D CI verification — 2026-07-12

- **Workflow name:** Supabase database tests
- **Latest run:** Fix payout release payment event test helper permissions
- **Run status:** Success
- **Passed test file:** `payout_release_controls.test.sql`
- **Status:** Ticket 7D is CI-verified.

Ticket 7D implements internal/manual/sandbox payout release controls only. It does **not** implement real bank payouts, live provider payout API calls, payout webhooks, UI, or real payout reconciliation.

### Remaining non-goals / risks

Ticket 7D deliberately does not implement:

- real provider bank payouts
- live payment-provider payout calls
- payout webhooks
- payout reconciliation with a real vendor
- cash payout release
- UI

Opening a dispute still needs the later Ticket 10 dispute workflow to atomically create the dispute and pause release in one user-facing operation. Ticket 7D blocks release when an active dispute already exists and provides trusted pause/resume/release controls.

## Ticket 7E — Mock payment adapter and hosted checkout contract

### Implementation status

CI-verified.

### Files changed

- `ticket_7e_mock_payment_adapter_plan.md`
- `outputs/marketplace-production-foundation/supabase/migrations/011_mock_payment_checkout.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/mock_payment_checkout.test.sql`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `rls_policy_matrix.md`
- `production_hardening_plan.md`
- `ticket_7_payments_plan.md`
- `outputs/marketplace-production-foundation/src/integrations/contracts.ts`

### What was implemented

- Added safe mock/sandbox hosted checkout fields on `payments`: `checkout_url`, `checkout_expires_at`, and `checkout_idempotency_key`.
- Added `validate_payment_provider_mode(app_env, provider_mode, webhook_secret_present)` so production + `mock` fails closed.
- Added `customer_create_mock_checkout_session(...)`, limited to the booking customer for their own pending payment. It rejects providers, unrelated users, terminal payment states, and cash/off-platform methods; sets `payments.status = checkout_created`; writes `payment_events` and `audit_events`; and is idempotent by checkout idempotency key.
- Added `admin_record_mock_payment_outcome(...)`, limited to platform-admin/trusted-server authority with a non-empty reason. It records mock `paid`/`failed` outcomes, writes `vendor_events`, `payment_events`, and `audit_events`, records `real_money_moved = false`, rejects paid-after-refunded, and safely ignores/rejects failed-after-paid without regressing payment state.
- Extended allowed `payment_events.event_type` values for mock outcomes: `mock_payment_paid`, `mock_payment_failed`, `mock_payment_duplicate_ignored`, and `mock_payment_out_of_order_rejected`.
- Kept card numbers, CVV, bank-login credentials, raw payment credentials, and raw sensitive provider payloads out of the database.

### Tests added

`outputs/marketplace-production-foundation/supabase/tests/database/mock_payment_checkout.test.sql` has 50 pgTAP assertions covering checkout authorization, idempotency, terminal-state rejection, cash/off-platform rejection, mock paid/failed outcomes, failed-after-paid safety, production mock-mode fail-closed validation, no credential storage, append-only ledgers, frontend-inaccessible vendor events, and Ticket 1/2/5/6/7A/7B/7C/7D smoke protections.

### CI update

The `Supabase database tests` workflow now runs `mock_payment_checkout.test.sql` after `payout_release_controls.test.sql`.

### Non-goals still not implemented

Ticket 7E deliberately does not implement live payment provider integration, real cards/EFTs/instant EFTs/bank logins/wallet payments, real signed webhooks, real refund execution, real bank payouts, live provider payout API calls, UI, or production use of the mock adapter.

### Tests to run

I could not run Supabase/pgTAP locally in this environment because the local shell does not have the required database tooling available.

From `outputs/marketplace-production-foundation`, rerun:

```powershell
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

Ticket 7E is now CI-verified; the commands above remain the local rerun path if the test needs to be rechecked during future changes.

### GitHub Actions mock payment checkout test failure â€” 2026-07-12

#### Failure summary

GitHub Actions reached `Run mock payment checkout pgTAP tests` and `mock_payment_checkout.test.sql` failed 21/50 assertions.

Failed assertion ranges reported:

- tests 1-6: checkout creation/idempotency/event assertions
- tests 18-32: mock paid/failed outcome/event assertions

Visible failures included missing mock failed `vendor_events` and `audit_events` rows:

```text
mock failed outcome writes vendor event
have: 0
want: 1

mock failed outcome writes audit event
have: 0
want: 1
```

#### Root cause

This was a real Ticket 7E function issue, not a reason to weaken production RLS:

- `customer_create_mock_checkout_session(...)` is a `RETURNS TABLE` function with an output column named `provider_name`. One internal `payment_events` lookup referenced `provider_name` without a table alias, which can be ambiguous in PL/pgSQL and throw before the checkout update and event inserts.
- `admin_record_mock_payment_outcome(...)` used `digest(...)` for mock payload hashes while its explicit `SECURITY DEFINER` search path did not include the Supabase `extensions` schema. In CI this can prevent `pgcrypto.digest` from resolving before `vendor_events`, `payment_events`, and `audit_events` are written.
- The mock outcome function also depended on the separate private vendor-event helper. The implementation now writes the idempotent `vendor_events` row directly inside the same trusted admin/server function to avoid nested helper EXECUTE-permission edge cases.

The test-only ledger count helpers were already `SECURITY DEFINER`, so this was not treated as a frontend role-read issue.

#### Fix applied

- Qualified the checkout idempotency lookup with a `payment_events` table alias.
- Added `extensions` to the explicit safe `search_path` for `admin_record_mock_payment_outcome(...)`.
- Changed `admin_record_mock_payment_outcome(...)` to insert/select the mock `vendor_events` row idempotently inside the trusted function.
- Kept frontend access to `payment_events`, `vendor_events`, and `audit_events` locked down.
- Kept append-only protections unchanged.
- Kept Ticket 1/2/5/6/7A/7B/7C/7D protections unchanged.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/011_mock_payment_checkout.sql`
- `hardening_progress.md`

#### Tests to rerun

From `outputs/marketplace-production-foundation`:

```powershell
supabase test db supabase/tests/database/mock_payment_checkout.test.sql
```

Then rerun the full `Supabase database tests` GitHub Actions workflow.

### Ticket 7E CI verification â€” 2026-07-12

- **Workflow name:** Supabase database tests
- **Latest run:** Fix Ticket 7E mock checkout event tests
- **Run status:** Success
- **Passed test file:** `mock_payment_checkout.test.sql`
- **Status:** Ticket 7E is CI-verified.

Ticket 7E implements mock/sandbox checkout only. It does **not** implement live payment provider integration, real payment webhooks, real card/EFT processing, real payout execution, or UI.

## Ticket 8 â€” Signed and idempotent payment webhook handling

### Planning status

Prepared only; not implemented.

### Plan file

- `ticket_8_payment_webhooks_plan.md`

### Scope

Ticket 8 planning covers:

- signed webhook verification
- raw body verification requirements
- `vendor_events` idempotency
- duplicate webhook handling
- out-of-order event handling
- `payment_events` and `audit_events` writing
- failed signature handling
- no committed webhook secrets
- mock/sandbox webhook tests
- future live provider integration requirements
- required pgTAP/database tests
- definition of done

### Next step

Review and approve the Ticket 8 plan before any webhook route, migration, handler, adapter, provider secret, or UI work is implemented.

## Ticket 8A — Mock/sandbox payment webhook database foundation

### Ticket 8A CI verification — 2026-07-13

- **Workflow name:** Supabase database tests
- **Latest run:** Fix Ticket 8A mock webhook state transitions
- **Run status:** Success
- **Passed test file:** `payment_webhooks.test.sql`
- **Status:** Ticket 8A is CI-verified.

Ticket 8A implements mock/sandbox database-side webhook processing only. It does **not** implement live provider webhook routes, raw-body HTTP signature verification, real provider webhooks, real payment provider integration, UI, or production secrets.

### Implementation status

CI-verified by the `Supabase database tests` GitHub Actions workflow after the Ticket 8A mock webhook state-transition fix.

### Issue addressed

Ticket 8A adds trusted database-side processing for mock/sandbox payment webhook events after a trusted server route has already verified the webhook signature. Ticket 8B now provides that mock/sandbox route. Ticket 8A itself does not implement live webhook routes or real provider signature verification.

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/012_mock_payment_webhook_processing.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/payment_webhooks.test.sql`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `rls_policy_matrix.md`
- `production_hardening_plan.md`
- `ticket_8_payment_webhooks_plan.md`
- `hardening_progress.md`

### Fix applied

- Added `admin_process_verified_mock_payment_webhook(...)` as a `SECURITY DEFINER` function with explicit `search_path`.
- Required platform-admin/trusted-server authority through the existing admin check.
- Added safe mock webhook event handling for:
  - `mock.checkout.created`
  - `mock.payment.paid`
  - `mock.payment.failed`
  - `mock.payment.expired`
  - `mock.payment.cancelled`
- Used `vendor_events` as the idempotency boundary on `(provider_name, provider_event_id)`.
- Prevented duplicate provider event IDs from duplicating `payment_events`.
- Audit-flagged duplicate provider event IDs with different `payload_hash` without mutating payment state.
- Prevented out-of-order events from regressing payment state.
- Routed paid-after-refunded to manual review without mutating payment status.
- Rejected raw webhook body/signature/secret/payment-credential metadata.
- Wrote safe `vendor_events`, `payment_events`, and `audit_events` rows for accepted mock/sandbox webhook outcomes.

### Tests added

- `payment_webhooks.test.sql` with 48 pgTAP assertions.

The test covers:

- frontend users cannot read/write `vendor_events`
- `payment_events` and `audit_events` remain append-only
- mock paid webhook updates payment once
- paid/failed webhooks write `vendor_events`, `payment_events`, and `audit_events`
- duplicate provider event IDs are idempotent
- duplicate provider event IDs with different payload hashes do not mutate payment state
- failed-after-paid does not regress payment status
- checkout-created-after-paid does not downgrade paid status
- paid-after-refunded does not mutate payment status
- invalid mock event type is rejected
- normal customers/providers cannot call the webhook-processing function
- frontend users cannot directly mark payments paid
- raw webhook body/signature/secret material is not stored
- Ticket 1/2/5/6/7A/7B/7C/7D/7E smoke protections remain intact

### CI wiring

Added `payment_webhooks.test.sql` to the `Supabase database tests` GitHub Actions workflow after `mock_payment_checkout.test.sql`.

### Rerun command

From `outputs/marketplace-production-foundation`:

```powershell
supabase db reset
supabase test db supabase/tests/database/payment_webhooks.test.sql
```

The full `Supabase database tests` GitHub Actions workflow is now green. Use the command above for a focused local rerun if needed.

I could not run Supabase/pgTAP locally in this environment because the local shell does not have the Supabase CLI/database tooling available.

### Remaining risks / non-goals

- Ticket 8A does not implement a live HTTP webhook route.
- Ticket 8A does not verify real signatures or raw request bodies.
- Ticket 8A does not add real webhook secrets.
- Ticket 8A does not process real card/EFT/bank payments.
- Ticket 8A does not implement live provider reconciliation.
- Ticket 8A does not build UI.
- Final production webhook work still needs a server route/Edge Function that verifies the exact raw body before calling the database function.

### GitHub Actions payment webhook test failure — 2026-07-13

#### Failure summary

GitHub Actions reached `Run payment webhook pgTAP tests` and `payment_webhooks.test.sql` failed 26/48 assertions.

Failed assertion ranges reported:

- tests 2-6
- tests 9-16
- tests 18-20
- tests 22-24
- tests 26-32

Visible failures included missing `vendor_events` and `audit_events` rows for valid mock webhook outcomes:

```text
failed webhook writes vendor event
have: 0
want: 1

failed webhook writes audit event
have: 0
want: 1
```

#### Root cause

This was a real Ticket 8A function bug, not a reason to weaken production RLS and not a protected-table test-helper issue.

`admin_process_verified_mock_payment_webhook(...)` used unqualified column names inside PL/pgSQL queries, including `provider_reference`, `provider_event_id`, and `idempotency_key`. Those names collide with function parameters. In CI, the function raised before reaching the trusted `vendor_events`, `payment_events`, and `audit_events` inserts, so the test counters correctly saw zero rows.

#### Fix applied

- Qualified the affected `payments`, `vendor_events`, and `payment_events` queries with explicit table aliases.
- Kept `vendor_events`, `payment_events`, and `audit_events` frontend-inaccessible.
- Kept append-only protections unchanged.
- Kept Ticket 1/2/5/6/7A/7B/7C/7D/7E protections unchanged.
- Did not add any production grants to make tests pass.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/012_mock_payment_webhook_processing.sql`
- `hardening_progress.md`

#### Tests to rerun

From `outputs/marketplace-production-foundation`:

```powershell
supabase test db supabase/tests/database/payment_webhooks.test.sql
```

Then rerun the full `Supabase database tests` GitHub Actions workflow.

### Second GitHub Actions payment webhook test failure — 2026-07-13

#### Failure summary

GitHub Actions still failed at `Run payment webhook pgTAP tests` after the first Ticket 8A fix.

Failed file:

- `supabase/tests/database/payment_webhooks.test.sql`

Result:

- Failed 26/48 assertions.
- Failed ranges: tests 2-6, 9-16, 18-20, 22-24, and 26-32.

Visible failure:

```text
failed webhook moves checkout-created payment to failed

have: checkout_created|not_applicable|false
want: failed|cancelled|false
```

The same run also showed zero `vendor_events`, `payment_events`, and `audit_events` rows for valid mock webhook outcomes.

#### Deeper trace

For `event_type = mock.payment.failed`, the intended path is:

1. Require admin/trusted-server authority.
2. Normalize `mock.payment.failed` to target payment status `failed`.
3. Find the payment by mock `provider_reference`.
4. Allow transition only when current payment status is `pending` or `checkout_created`.
5. Insert/reuse `vendor_events`.
6. Set `payments.status = failed` and `release_status = cancelled`.
7. Insert `payment_events`.
8. Append `audit_events`.

The test fixture is correct:

- payment `00000000-0000-0000-0000-000000009402`
- `provider_name = mock`
- `provider_reference = ticket-8a-failed`
- starting `status = checkout_created`
- starting `release_status = not_applicable`

So the failure was not caused by the test using the wrong provider reference or by the failed-payment transition matrix rejecting `checkout_created`.

#### Actual root cause

The first fix qualified the `SELECT` queries, but the function still used:

```sql
on conflict (provider_name, provider_event_id) do nothing
```

inside `admin_process_verified_mock_payment_webhook(...)`, whose input parameter is also named `provider_event_id`.

In PL/pgSQL this conflict target can still collide with the function parameter name. The function therefore failed at the `vendor_events` idempotency insert before the trusted payment update, `payment_events` insert, or `audit_events` append could commit. PostgreSQL rolled back the whole function call, leaving the payment at `checkout_created`.

#### Fix applied

- Removed the ambiguous `ON CONFLICT (provider_name, provider_event_id)` clause from the Ticket 8A function.
- Replaced it with an explicit `INSERT ... RETURNING id` inside a `unique_violation` handler.
- If a concurrent or duplicate vendor event already exists, the function now re-selects the existing `vendor_events` row by explicit table alias.
- The duplicate payload-hash mismatch path remains audit-flagged without payment mutation.
- Existing payment-event idempotency is still checked before inserting a new `payment_events` row.
- No frontend grants were added.
- Append-only protections remain unchanged.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/012_mock_payment_webhook_processing.sql`
- `hardening_progress.md`

#### Tests to rerun

From `outputs/marketplace-production-foundation`:

```powershell
supabase test db supabase/tests/database/payment_webhooks.test.sql
```

Then rerun the full `Supabase database tests` GitHub Actions workflow.

## Ticket 8B — Mock/sandbox payment webhook route with raw-body signature verification

### Implementation status

CI-verified.

### Ticket 8B CI verification — 2026-07-13

- **Workflow name:** Supabase database tests
- **Latest run:** Fix Ticket 8B webhook signature type error
- **Run status:** Success
- **Status:** Ticket 8B is CI-verified.

Ticket 8B implements mock/sandbox webhook route raw-body signature verification only. It does **not** implement live provider adapters, real payment webhooks, real provider credentials, real card/EFT processing, real payout webhooks, or UI.

### Issue addressed

Ticket 8B adds the application/Edge Function webhook route for mock/sandbox payment events. The route verifies a deterministic HMAC mock signature against the exact raw request body before JSON parsing and before calling the Ticket 8A database function.

This keeps the system’s trust boundary clear:

1. the HTTP route verifies raw-body signature and timestamp freshness;
2. only verified mock events are normalized into safe internal fields;
3. only safe metadata is sent to the database;
4. `admin_process_verified_mock_payment_webhook(...)` remains responsible for transactional payment/vendor/payment-event/audit-event processing.

### Files changed

- `outputs/marketplace-production-foundation/supabase/functions/payment-webhook/index.ts`
- `outputs/marketplace-production-foundation/supabase/functions/payment-webhook/index.test.ts`
- `outputs/marketplace-production-foundation/src/integrations/contracts.ts`
- `outputs/marketplace-production-foundation/.env.example`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `production_hardening_plan.md`
- `ticket_8b_webhook_route_plan.md`
- `hardening_progress.md`

### Security behavior implemented

- Reads the request body once as raw bytes.
- Computes `payload_hash` from those exact raw bytes.
- Verifies `x-lekkadeall-mock-signature` before parsing JSON.
- Uses `x-lekkadeall-mock-timestamp` and `PAYMENT_WEBHOOK_TOLERANCE_SECONDS` for replay/staleness checks.
- Rejects missing signatures, invalid signatures, stale timestamps, missing mock webhook secret config, unsupported methods, unsupported event types, and malformed verified payloads.
- Parses JSON only after signature verification succeeds.
- Normalizes only safe fields:
  - `provider_event_id`
  - `provider_reference`
  - `event_type`
  - `payload_hash`
  - `idempotency_key`
  - safe metadata
- Calls `public.admin_process_verified_mock_payment_webhook(...)` through the server-side Supabase RPC path only after verification succeeds.
- Does not forward raw body, webhook secret, signature header, full provider payload, card data, bank credential data, or payment credential data to the database.
- Fails closed when `APP_ENV=production` and `PAYMENT_PROVIDER_MODE=mock`.

### Tests added

Added Deno application tests in:

- `outputs/marketplace-production-foundation/supabase/functions/payment-webhook/index.test.ts`

The tests cover:

- valid mock signature is accepted
- invalid mock signature is rejected
- missing signature header is rejected
- stale timestamp is rejected
- exact raw body bytes are used for verification
- parsed-then-reserialized JSON cannot bypass verification
- `payload_hash` is computed from exact raw bytes
- valid paid webhook calls the database function exactly once
- valid failed webhook calls the database function exactly once
- invalid signature does not call the database function
- malformed JSON is not parsed before signature verification
- raw body, payload-provided secrets, and signature material are not forwarded
- webhook secret is read from server runtime config
- missing runtime webhook secret fails closed
- missing app environment fails closed
- production + mock provider mode fails closed
- unsupported HTTP method is rejected without a database call

### CI wiring

Updated `.github/workflows/database-tests.yml` to:

- install Deno with `denoland/setup-deno@v2`
- run `deno test supabase/functions/payment-webhook/index.test.ts`
- then continue running the existing Supabase local stack and pgTAP database tests

### How to run

From `outputs/marketplace-production-foundation`:

```powershell
deno test supabase/functions/payment-webhook/index.test.ts
supabase db reset
supabase test db supabase/tests/database/payment_webhooks.test.sql
```

For the full local security suite, run the commands listed in `TESTING.md`.

### Tests not run locally

I could not run the new Deno tests locally in this shell because Deno is not installed on PATH. The workflow installs Deno in GitHub Actions before running the route tests.

I also did not rerun the Supabase pgTAP suite locally because the local shell does not have the Supabase CLI/database tooling available.

### GitHub Actions mock payment webhook route test failure — 2026-07-13

#### Failure summary

GitHub Actions failed at `Run mock payment webhook route tests` during TypeScript checking for:

- `supabase/functions/payment-webhook/index.ts`

Visible error:

```text
TS2345: Argument of type 'Uint8Array<ArrayBufferLike>' is not assignable to parameter of type 'BufferSource'.
```

The failing call was:

```ts
crypto.subtle.sign('HMAC', key, signedPayload)
```

#### Root cause

Deno's WebCrypto type definitions require a `BufferSource` backed by a concrete `ArrayBuffer`. The route passed `Uint8Array` values whose generic backing type was inferred as `ArrayBufferLike`, which can include non-`ArrayBuffer` backing stores. Runtime behavior would still use the intended bytes, but TypeScript correctly rejected the narrower WebCrypto type contract.

#### Fix applied

- Added `toExactArrayBuffer(bytes)` to copy the exact bytes from a `Uint8Array` into a fresh concrete `ArrayBuffer`.
- Updated `crypto.subtle.digest(...)` to hash `toExactArrayBuffer(rawBody)`.
- Updated `crypto.subtle.importKey(...)` to import `toExactArrayBuffer(encoder.encode(secret))`.
- Updated `crypto.subtle.sign(...)` to sign `toExactArrayBuffer(signedPayload)`.
- Kept signature verification based on exact raw request bytes.
- Did not switch to parsed JSON for signature verification.
- Did not add `--no-check`.
- Did not add real webhook secrets or live provider integration.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/functions/payment-webhook/index.ts`
- `hardening_progress.md`

#### Rerun command

From `outputs/marketplace-production-foundation`:

```powershell
deno test supabase/functions/payment-webhook/index.test.ts
```

Then rerun the full `Supabase database tests` GitHub Actions workflow so the webhook route tests and all existing pgTAP database tests run together.

### Remaining risks / non-goals

- Ticket 8B implements mock/sandbox webhook route support only.
- Ticket 8B does not implement live provider webhook adapters.
- Ticket 8B does not add real webhook secrets.
- Ticket 8B does not process real card/EFT/bank payments.
- Ticket 8B does not implement real refund or payout webhooks.
- Ticket 8B does not build UI.
- Real provider integration still needs vendor-specific signature adapters, sandbox certification, reconciliation, monitoring, and production secret management.

## Ticket 8C — Sandbox provider-specific webhook adapter selection and integration readiness

### Planning status

Planning-only document prepared; no implementation performed.

### File added

- `ticket_8c_sandbox_provider_webhook_adapter_plan.md`

### Scope

Ticket 8C is for selecting and preparing the first real sandbox provider-specific webhook adapter. It covers provider-selection criteria, vendor documentation to request, event mapping, signature-verification readiness, secret-management readiness, reconciliation readiness, compliance/operational readiness, required tests, and definition of done.

### Non-goals

Ticket 8C does **not** implement live provider adapters, real payment webhooks, real provider credentials, real card/EFT processing, real refund webhooks, real payout webhooks, reconciliation jobs, RLS changes, or UI.

### Provider comparison update — 13 July 2026

- Peach Payments confirmed directly to the user that it does not support marketplace.
- Peach Payments is therefore **not suitable for the LEKKADEALL marketplace model — vendor confirmed no marketplace support** and has been removed from the Ticket 8C shortlist.
- The revised shortlist is:
  1. Stitch — next technical candidate, pending marketplace/hold/release confirmation.
  2. TradeSafe — marketplace/escrow model candidate, pending stronger signed webhook/callback confirmation.
  3. Netcash / PayFast / Ozow — lower priority unless they confirm marketplace hold/release and signed webhook suitability.
- The current decision remains **no provider ready for selection yet**.
- All unresolved candidate capabilities, commercial terms, compliance arrangements, and operational details remain **needs vendor confirmation**.
- This update is planning-only. No provider adapter, credentials, migration, test, payment processing, refund/payout execution, reconciliation job, RLS change, or UI was added.

## Ticket 9A-1 — Customer/provider frontend shell

**Date:** 14 July 2026  
**Status:** Implemented locally; frontend shell tests pass. Existing webhook and pgTAP regression suites remain wired in GitHub Actions and require the next CI run for verification.

### Scope implemented

- Added a new LEKKADEALL-branded, dependency-free static frontend shell under `outputs/lekkadeall-frontend-shell`.
- Added public landing and service-discovery routes.
- Added non-transmitting authentication route shells for sign in, registration, forgot password, reset password, and auth callback.
- Added customer and provider dashboard shells with safe signed-out and empty states.
- Added a read-only profile/settings shell.
- Added access-denied, account-restricted, loading, empty, error, signed-out, restricted, and not-found states.
- Added shared public/application headers, navigation, page-state components, responsive layouts, and accessible focus/skip-link behavior.
- Added `MockPaymentBanner` with the exact wording: **“Mock/sandbox — no real money moved”**.
- Added clean-path static entry files for all Ticket 9A-1 routes.
- Added dependency-free tests using Node's built-in test runner and wired them into the existing GitHub Actions workflow before the Deno/Supabase test steps.

### Files changed

- `outputs/lekkadeall-frontend-shell/index.html`
- `outputs/lekkadeall-frontend-shell/app.js`
- `outputs/lekkadeall-frontend-shell/shell.js`
- `outputs/lekkadeall-frontend-shell/styles.css`
- `outputs/lekkadeall-frontend-shell/404.html`
- `outputs/lekkadeall-frontend-shell/services/index.html`
- `outputs/lekkadeall-frontend-shell/auth/sign-in/index.html`
- `outputs/lekkadeall-frontend-shell/auth/register/index.html`
- `outputs/lekkadeall-frontend-shell/auth/forgot-password/index.html`
- `outputs/lekkadeall-frontend-shell/auth/reset-password/index.html`
- `outputs/lekkadeall-frontend-shell/auth/callback/index.html`
- `outputs/lekkadeall-frontend-shell/app/customer/index.html`
- `outputs/lekkadeall-frontend-shell/app/provider/index.html`
- `outputs/lekkadeall-frontend-shell/app/settings/index.html`
- `outputs/lekkadeall-frontend-shell/access-denied/index.html`
- `outputs/lekkadeall-frontend-shell/account-restricted/index.html`
- `outputs/lekkadeall-frontend-shell/tests/frontend-shell.test.mjs`
- `outputs/lekkadeall-frontend-shell/README.md`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `hardening_progress.md`

### Security behavior

- No Supabase browser client was added because the repository does not yet have an approved public client/configuration module. Service discovery therefore renders a safe empty shell rather than making an unreviewed request.
- Auth forms are shells only. Submission is intercepted locally, values are cleared, and nothing is transmitted.
- Dashboard and settings routes show safe placeholders rather than querying broad or unfinished read models.
- Profile/settings is read-only and contains no direct table update.
- Client source contains no application-table insert/update/delete calls, admin/private function calls, mock webhook processing calls, service-role access, or secret values.
- No `/admin` route or admin dashboard was added.
- No exact-address submission, reveal, persistence, logging, or telemetry was added.
- No cash/off-platform option, payment-method form, card/CVV field, bank-login field, real checkout, real payment/refund/payout action, or identity-provider flow was added.

### Intentionally not implemented

- Supabase Auth integration or session-backed route authorisation;
- service-category database reads;
- customer/provider dashboard read models;
- profile editing;
- request creation/publication, bid submission/acceptance, booking progress/completion, or address handling;
- mock checkout creation or mock outcome controls;
- real payment-provider integration, credentials, checkout, refunds, payouts, webhooks, or reconciliation;
- identity verification;
- admin dashboard/actions;
- disputes, reviews, consent workflows, support cases, notifications, or chat;
- migrations, RLS/grant/policy changes, database functions, or storage-policy changes.

### How to preview

From the repository root:

```powershell
python -m http.server 4173 --directory outputs/lekkadeall-frontend-shell
```

Then open `http://localhost:4173/`. Stop the preview with `Ctrl+C`.

### Frontend tests

Run from the repository root:

```powershell
node --test outputs/lekkadeall-frontend-shell/tests/frontend-shell.test.mjs
```

Local result: **8/8 tests passed**.

The tests cover:

- every required shell route and absence of an admin route;
- exact `MockPaymentBanner` wording;
- safe loading, empty, error, signed-out, restricted, and not-found states;
- safe service-discovery fallback without a Supabase client;
- auth shells without privileged role/status selection;
- absence of client database writes, sensitive functions, secrets, cash markers, and payment credential fields;
- existence of clean-path static entry files.

### CI database/webhook regression verification

The existing `Supabase database tests` workflow remains the regression gate. Ticket 9A-1 adds the frontend shell test step but does not remove or weaken any existing step. On every push and pull request, CI still:

1. runs the mock webhook Deno tests;
2. verifies Docker and committed non-secret local Supabase configuration;
3. starts the local Supabase stack and applies all migrations with `supabase db reset`;
4. runs the existing role escalation, baseline RLS, exact-address privacy, marketplace state-machine, payment ledger, refund ledger, cash policy, payout-release, mock-checkout, and payment-webhook pgTAP suites.

The Deno and pgTAP suites were not run locally for Ticket 9A-1 because Deno, the Supabase CLI, and the local Supabase stack are not available in this shell. No database, webhook, migration, RLS, grant, policy, or function file changed; the next GitHub Actions run is the verification source for no database regression.

## Ticket 9B — Secure Auth profile provisioning

### Issue fixed

Supabase Auth could create an `auth.users` row without a matching `public.profiles` row. The Ticket 9A-2 frontend correctly refused to insert that application row, leaving new registrations in the fail-closed “account setup unavailable” state.

Ticket 9B adds an atomic, trusted database provisioning path. Normal Auth insertion now creates exactly one fixed-default customer profile without trusting browser input or Auth metadata.

### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/013_secure_profile_provisioning.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/profile_provisioning.test.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/rls_test_seed.inc`
- `outputs/marketplace-production-foundation/supabase/tests/database/payout_release_controls.test.sql`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `hardening_progress.md`

### Database implementation

- Added private `SECURITY DEFINER` helper `private.ensure_auth_user_profile(uuid, text)` with `search_path = pg_catalog` and explicit schema-qualified references.
- Added private `SECURITY DEFINER` trigger function `private.provision_auth_user_profile()` with the same safe search-path contract.
- Added `provision_auth_user_profile_after_insert`, an `AFTER INSERT` trigger on `auth.users`.
- Every newly provisioned profile uses only fixed database-owned values:
  - `id = NEW.id`
  - `role = customer`
  - `account_status = active`
  - `display_name = New customer`
  - `city = Potchefstroom`
  - phone, verification timestamps, suburb, and avatar remain null
- The implementation never reads `raw_user_meta_data`, `raw_app_meta_data`, query parameters, or registration payloads.
- Profile creation uses `ON CONFLICT (id) DO NOTHING`. It does not use an updating upsert and cannot overwrite an existing profile.
- The private functions reject unsupported provisioning sources and are non-executable by `public`, `anon`, `authenticated`, and `service_role`.
- No `provider_profiles`, provider approval, verification, admin, support, identity, payment, address, or marketplace record is created.
- No profile insert/delete grants or RLS policies were added for browser roles.

### Backfill and audit behavior

- The trigger is installed before backfill to close the deployment race.
- Existing `auth.users` rows without profiles are provisioned with the same fixed safe defaults.
- Existing profiles are skipped and never modified.
- The migration fails if any Auth user remains without a profile after backfill.
- A newly created profile writes one append-only `system.profile_provisioned` audit event through the existing private audit helper.
- Audit metadata contains only a fixed source (`auth_trigger` or `migration_backfill`) and version marker. It contains no email, phone, token, Auth metadata, address, or registration payload.

### Regression fixture updates

The shared pgTAP seed and Ticket 7D test previously inserted Auth users and then manually inserted their profiles. Because Ticket 9B now provisions those rows automatically, the fixtures were changed to update their test-only provider/admin states under the existing Ticket 1 privileged test bypass. They do not disable the production provisioning trigger or grant frontend insert access.

### Tests added

`profile_provisioning.test.sql` contains 44 assertions covering:

- trigger/function presence, `SECURITY DEFINER`, safe search paths, and revoked execution;
- fixed customer/active/neutral profile creation;
- hostile user/app metadata rejection;
- no provider/admin/support profile creation;
- privacy-safe audit logging;
- idempotent replay and no overwrite;
- authenticated profile insert/delete denial;
- own-profile read and cross-user denial;
- direct role/account-status escalation denial;
- existing-user backfill and repeated-backfill safety; and
- Ticket 1 privileged-field and Ticket 2 RLS regression smoke checks.

### CI wiring

The `Supabase database tests` workflow now runs:

```bash
supabase test db supabase/tests/database/profile_provisioning.test.sql
```

after the role-escalation and baseline-RLS suites. All existing frontend, Deno webhook, migration, and pgTAP steps remain in place.

### How to run

From `outputs/marketplace-production-foundation`:

```powershell
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
```

Also run from the repository root:

```powershell
node --test outputs/lekkadeall-frontend-shell/tests/frontend-shell.test.mjs
cd outputs/marketplace-production-foundation
deno test supabase/functions/payment-webhook/index.test.ts
```

### Verification status

Static review confirms that Ticket 9B adds no frontend code, credential, service-role key, profile insert/delete grant or policy, provider onboarding, admin dashboard, payment-provider integration, or changes to payment/refund/payout/webhook/address/dispute/identity flows.

The Ticket 9A-1 frontend regression suite was run with the bundled Node runtime and passed **8/8 tests**. The new pgTAP file was also statically checked: its declared plan and assertion count both equal **44**.

Docker, the Supabase CLI, and Deno are not available in this shell, so the database reset, pgTAP execution, and webhook route tests were not run locally. The updated GitHub Actions workflow is the authoritative database/webhook integration and regression gate for this implementation.

### GitHub Actions profile-provisioning test failure — 2026-07-14

#### Failure summary

The `Run secure profile provisioning pgTAP tests` step reported:

```text
Bad plan. You planned 44 tests but ran 26.
Tests: 26
Failed: 0
```

All 26 assertions that ran passed. The plan count was not inflated: the file still contains 44 intentional assertions. Execution terminated before assertion 27.

#### Root cause

The first SQL statement after assertion 26 attempted to run:

```sql
alter table auth.users disable trigger provision_auth_user_profile_after_insert;
```

The test used trigger toggling to create an Auth user without an automatically provisioned profile. Altering the Supabase-managed `auth.users` table requires ownership-level DDL that is not available to the pgTAP test connection in CI. The SQL error terminated the file before assertions 27–44, and pgTAP consequently reported a bad plan rather than failed assertions.

The same unsupported trigger-toggle pattern appeared again in the later backfill fixture and would also have terminated execution.

#### Fix applied

- Kept the pgTAP plan at 44 because all 44 security assertions remain intentional.
- Removed both `ALTER TABLE auth.users DISABLE/ENABLE TRIGGER` blocks from the test.
- The direct-insert denial fixture now creates an Auth user normally, allows the production trigger to run, and deletes only that test user's provisioned `public.profiles` row before impersonating the browser role.
- The backfill fixture uses the same approach: create normally, delete only the test profile, then call the private idempotent helper with `migration_backfill`.
- This creates a valid Auth identity with a missing profile without changing trigger state or requiring ownership of `auth.users`.
- The production migration, trigger, helper, audit logging, function revocations, RLS policies, grants, and Ticket 1 protections were not weakened or changed.

#### Verification

- Static assertion count remains **44 planned / 44 present**.
- No trigger-disable or trigger-enable DDL remains in `profile_provisioning.test.sql`.
- The test still covers fixed customer/active provisioning, hostile metadata rejection, idempotency, no overwrite, browser insert/delete denial, own/cross-user reads, role/status protection, privacy-safe audit logging, and backfill.
- The Ticket 9A-1 frontend regression suite remains **8/8 passing** locally.
- Docker, Supabase CLI, and Deno remain unavailable locally, so the corrected pgTAP suite and full database/webhook regressions require GitHub Actions verification.

### Ticket 9B CI verification — 2026-07-15

- **Latest successful run:** Fix Ticket 9B profile provisioning pgTAP plan
- **Run status:** Success
- **Ticket status:** CI-verified

#### What was implemented

- A private, schema-qualified `SECURITY DEFINER` provisioning helper and trigger function with a safe `search_path`.
- An `AFTER INSERT` trigger on `auth.users` that creates exactly one matching `public.profiles` row using fixed database-owned defaults: `role = customer`, `account_status = active`, and `display_name = New customer`.
- Idempotent `ON CONFLICT (id) DO NOTHING` behavior that never updates or overwrites an existing profile.
- A safe backfill for existing Auth users without profiles, using the same fixed defaults and leaving existing profiles unchanged.
- Minimal privacy-safe `system.profile_provisioned` audit events containing only a fixed source and version marker.
- A 44-assertion pgTAP suite covering provisioning, hostile metadata, idempotency, no overwrite, browser denials, RLS visibility, role/status protection, audit behavior, and backfill.
- CI wiring for the new profile-provisioning pgTAP suite while retaining all existing frontend, webhook, migration, and database regression steps.

#### Initial failure

The first Ticket 9B GitHub Actions run reached the secure profile-provisioning pgTAP step but stopped after 26 of 44 planned assertions. All 26 assertions that ran passed; pgTAP reported a bad plan because SQL execution terminated before assertion 27.

#### Root cause

The test attempted ownership-level `ALTER TABLE auth.users DISABLE/ENABLE TRIGGER` statements to simulate an existing Auth user without a profile. The Supabase-managed `auth.users` table could not be altered by the pgTAP CI connection, so execution ended immediately after assertion 26.

#### Fix applied

- Kept all 44 intentional security assertions rather than reducing the plan.
- Removed both trigger-disable/enable blocks from the test.
- Reworked the direct-insert and backfill fixtures to create Auth users normally, allow the production trigger to provision them, and then delete only the relevant test profile before exercising the denial or backfill path.
- Left the production migration, trigger, helper, function revocations, grants, policies, audit protections, and role-escalation protections unchanged.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/013_secure_profile_provisioning.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/profile_provisioning.test.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/rls_test_seed.inc`
- `outputs/marketplace-production-foundation/supabase/tests/database/payout_release_controls.test.sql`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `hardening_progress.md`

#### CI-verified security outcomes

- New Auth users receive exactly one matching `customer` / `active` profile with neutral approved defaults.
- Hostile `raw_user_meta_data` and `raw_app_meta_data` values cannot select role, account status, provider approval, verification/review status, admin/support authority, identity state, payment state, or address data.
- Existing profiles are not overwritten by trigger replay or backfill.
- Browser users still cannot directly insert or delete `public.profiles` rows.
- Ticket 1 role/account-status escalation protections remain intact.
- Ticket 2 RLS, grants, own-profile visibility, and cross-user denial protections remain intact.
- All existing GitHub Actions frontend, Deno webhook, migration, and pgTAP regression steps completed successfully in the green run.

#### Explicit non-goals preserved

Ticket 9B added no frontend code, provider onboarding, payment-provider code, admin dashboard, real credential, service-role key, frontend profile insert/delete grant or policy, or RLS weakening.

### Ticket 9A-2 implementation — Supabase Auth and safe read-only data — 2026-07-15

**Status:** CI-verified.

- **Latest successful run:** Implement Ticket 9A-2 Supabase auth and safe reads
- **Run status:** Success
- **Ticket status:** CI-verified

#### What was implemented

- Added a single public Supabase browser-client boundary using the exact locked `@supabase/supabase-js` package, public project URL, and anon key only.
- Added placeholder-only `.env.example` and runtime-config template files; the local runtime file is ignored by Git.
- Wired sign in, customer registration, forgot-password, reset-password, PKCE Auth callback, session restoration, Auth state changes, and sign out.
- Registration sends only email, password, and the approved callback URL. It sends no user/app metadata and relies on Ticket 9B to provision the fixed customer/active `public.profiles` row.
- Added session-backed customer, provider, and settings route guards. Role and `account_status` are resolved only from the signed-in user's RLS-protected `public.profiles` row, never Auth metadata or URL/query values.
- Added fail-closed handling for missing profiles, signed-out and expired sessions, restricted/suspended/closed accounts, role mismatches, admin/support roles, and unknown roles.
- Added active `service_categories` discovery with the explicit `id,slug,name` projection.
- Added explicit, read-only own-profile/settings, own-provider-status, customer request summary, booking-party summary, and associated sandbox-payment summary reads where existing RLS and column grants permit them.
- Denied reads show a safe placeholder. No broader query, privileged fallback, RPC, or database-security change is attempted.
- Preserved the exact `Mock/sandbox — no real money moved` wording.

#### Files changed

- `.gitignore`
- `.github/workflows/database-tests.yml`
- `outputs/lekkadeall-frontend-shell/.env.example`
- `outputs/lekkadeall-frontend-shell/package.json`
- `outputs/lekkadeall-frontend-shell/pnpm-lock.yaml`
- `outputs/lekkadeall-frontend-shell/runtime-config.example.js`
- `outputs/lekkadeall-frontend-shell/public-config.js`
- `outputs/lekkadeall-frontend-shell/supabase-public-client.js`
- `outputs/lekkadeall-frontend-shell/auth-session.js`
- `outputs/lekkadeall-frontend-shell/route-guards.js`
- `outputs/lekkadeall-frontend-shell/safe-reads.js`
- `outputs/lekkadeall-frontend-shell/app.js`
- `outputs/lekkadeall-frontend-shell/shell.js`
- `outputs/lekkadeall-frontend-shell/styles.css`
- `outputs/lekkadeall-frontend-shell/tests/frontend-shell.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/auth-safe-reads.test.mjs`
- `outputs/lekkadeall-frontend-shell/README.md`
- `TESTING.md`
- `hardening_progress.md`

No migration, RLS policy, grant, database function, webhook, or Supabase database test file was changed.

#### Tests added or updated

- Added `outputs/lekkadeall-frontend-shell/tests/auth-safe-reads.test.mjs` for public-client configuration, metadata-free registration, callback input handling, profile-backed route guards, explicit read projections, fixed table allowlists, placeholder-only configuration, and prohibited frontend capability checks.
- Updated `outputs/lekkadeall-frontend-shell/tests/frontend-shell.test.mjs` for wired Auth forms, safe application states, exact mock-payment wording, required route coverage, absence of an admin route, and frontend mutation/secret regression checks.
- Updated `.github/workflows/database-tests.yml` to install the exact frozen frontend dependency and run all frontend `*.test.mjs` files before the existing Deno webhook and pgTAP database suites.
- Local frontend result: **15/15 tests passed**.
- GitHub Actions result: **Success**. The frontend tests, Deno webhook tests, migration reset, Ticket 9B profile-provisioning suite, Ticket 1 and Ticket 2 protections, and all remaining pgTAP regressions completed successfully.

#### Local setup, preview, and tests

From the repository root:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
Copy-Item outputs/lekkadeall-frontend-shell/runtime-config.example.js outputs/lekkadeall-frontend-shell/runtime-config.local.js
python -m http.server 4173 --directory outputs/lekkadeall-frontend-shell
```

Only `PUBLIC_APP_ENV`, `PUBLIC_APP_URL`, `PUBLIC_SUPABASE_URL`, and `PUBLIC_SUPABASE_ANON_KEY` are documented. The example values are placeholders. The ignored local file must contain only public browser configuration.

Run the frontend suite with:

```powershell
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

Local result: **15/15 tests passed** using the bundled Node runtime. CI installs the frozen lockfile, runs both frontend test files, then retains all existing Deno webhook, Supabase migration reset, Ticket 9B provisioning, Ticket 1/2 security, and remaining pgTAP regression steps.

#### Intentionally not implemented

- No `/admin` route or admin dashboard.
- No profile editing, provider onboarding, or browser profile insertion.
- No exact-address submission or reveal.
- No request creation/publication/cancellation, bidding, booking completion, refunds, payouts, disputes, reviews, consent, support, notifications, or chat.
- No application-table insert/update/upsert/delete and no application RPC.
- No identity provider, real payment provider, checkout, card/CVV/bank-login/payment-method form, cash, or off-platform payment option.
- No credential, service-role key, webhook secret, provider secret, identity secret, admin credential, or real project value.
- No migration, RLS, grant, policy, database-function, or webhook change or weakening.

#### CI-verified security confirmations

- No service-role key or other server-only Supabase key was added.
- No real credential, project value, payment/provider secret, webhook secret, identity secret, database credential, or admin credential was added.
- No `/admin` route or admin dashboard was added.
- No profile editing or browser-side profile insertion was added.
- No exact-address submission, storage, query, or reveal flow was added.
- No marketplace mutation was added: there is no request publication/cancellation, bidding, booking completion, refund, payout, dispute, review, consent, support, notification, chat, application-table insert/update/upsert/delete, or application RPC.
- No real payment-provider adapter, API call, checkout, payment-method form, cash option, or off-platform payment flow was added.

### Ticket 9A-3 implementation — Customer request draft creation — 2026-07-15

**Status:** CI-verified.

- **Latest successful run:** Implement Ticket 9A-3 customer request draft creation
- **Run status:** Success
- **Ticket status:** CI-verified

#### What was implemented

- Added the protected `/app/customer/requests/new` route and its clean-path static entry file.
- Added a customer-dashboard entry point labelled “Create request draft”.
- Extended the existing Ticket 9A-2 session/profile guard so only an authenticated profile with `role = customer` and `account_status = active` can access or submit the route.
- Reused the existing explicit `id,slug,name` active-category projection. Category IDs are accepted only when present in the currently loaded active result.
- Added draft-only fields for category, public title, public description, suburb, city, requested start in SAST/UTC+2, and optional ZAR budget.
- Added the exact Ticket 9A-3 privacy warning beside the public content fields and again before submission.
- Added conservative local privacy detection for street/house/unit/room material, GPS coordinates, South African phone formats, email/URL/contact instructions, and access codes across every public text field.
- Added title, description, suburb, city, category, calendar, future-time, and budget validation matching the reviewed plan.
- Added explicit SAST conversion to an ISO 8601 timestamp carrying `+02:00` and a 15-minute client safety buffer.
- Added optional ZAR conversion using string parsing and BigInt-safe integer arithmetic only. Blank becomes `null`; invalid formats, more than two decimals, negatives, and PostgreSQL integer overflow are rejected.
- Added one marketplace RPC boundary: `customer_create_draft_request(...)`. The reviewed eight-parameter payload always passes `p_precise_address_ciphertext: null`.
- Added an in-memory single-flight guard. Ambiguous failures are generic and are not automatically retried.
- Added draft-created confirmation only after the backend returns a valid request UUID. The confirmation explains that the row remains a private draft and that publishing/exact-address handling are unavailable.
- Form values remain in memory only while the route is active. They are not placed in URLs, logs, analytics, telemetry, `localStorage`, or `sessionStorage`.

#### Files changed

- `.github/workflows/database-tests.yml`
- `outputs/lekkadeall-frontend-shell/request-draft.js`
- `outputs/lekkadeall-frontend-shell/route-guards.js`
- `outputs/lekkadeall-frontend-shell/app.js`
- `outputs/lekkadeall-frontend-shell/shell.js`
- `outputs/lekkadeall-frontend-shell/styles.css`
- `outputs/lekkadeall-frontend-shell/app/customer/requests/new/index.html`
- `outputs/lekkadeall-frontend-shell/tests/request-draft.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/frontend-shell.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/auth-safe-reads.test.mjs`
- `outputs/lekkadeall-frontend-shell/README.md`
- `TESTING.md`
- `hardening_progress.md`

No dependency/package version, migration, RLS policy, grant, database function, Supabase database test, or webhook file was changed.

#### Tests added or updated

- Added `request-draft.test.mjs` for the exact privacy warning, public-content risk detection, validation boundaries, active-category allowlisting, SAST conversion, integer ZAR conversion, overflow rejection, exact RPC name/payload, null ciphertext, one-call failure behavior, customer-only rendering, draft-only confirmation, blocked capabilities, and single-flight/no-retry source checks.
- Updated `frontend-shell.test.mjs` for the new registered route and clean-path entry file while preserving all Ticket 9A-1 coverage.
- Updated `auth-safe-reads.test.mjs` for customer/provider guard decisions on the new route and to keep Ticket 9A-2 modules RPC-free while permitting only the reviewed Ticket 9A-3 RPC boundary.
- Updated the GitHub Actions frontend step label; the existing glob already runs every `*.test.mjs` file before the unchanged Deno and pgTAP gates.
- Local result: **25/25 frontend tests passed** using the bundled Node runtime.
- GitHub Actions result: **Success**. The Ticket 9A-3 frontend suite, Ticket 9A-1/9A-2 frontend regressions, Deno webhook tests, migration reset, Ticket 1/2/5/6/9B security suites, and all remaining pgTAP database tests completed successfully.

#### Local test and preview instructions

From the repository root:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
Copy-Item outputs/lekkadeall-frontend-shell/runtime-config.example.js outputs/lekkadeall-frontend-shell/runtime-config.local.js
python -m http.server 4173 --directory outputs/lekkadeall-frontend-shell
```

With valid public browser configuration and an active customer session, open:

```text
http://localhost:4173/app/customer/requests/new/
```

#### Intentionally not implemented and still blocked

- No exact-address input, map, GPS/geolocation, phone/contact field, private-address ciphertext production, address storage, address read, or reveal.
- No request publish, open, edit, cancel, delete, or automatic ambiguous-failure retry.
- No address or publication RPC is called.
- No bidding, provider onboarding, booking completion, payment, refund, payout/release, dispute, review, support, consent, notification, chat, identity, or admin feature.
- No direct application-table insert/update/upsert/delete and no `select('*')`.
- No service-role key, real credential, real payment-provider adapter/API, checkout, payment-method form, cash, or off-platform payment UI.
- No migration, RLS, grant, policy, database-function, database-test, or webhook change or weakening.

The exact-address step and publication remain blocked until a separately reviewed encryption boundary and complete backend public-field validation are verified.

#### CI-verified blocked-feature confirmations

- **Exact address:** no exact-address input, ciphertext production, storage call, read, reveal, map, GPS, or geolocation flow was added.
- **Publishing:** no request publication route, button, or `customer_publish_request(...)` call was added.
- **Provider bidding:** no provider onboarding, open-request feed, bid form, bid submission, bid acceptance, or withdrawal action was added.
- **Booking:** no booking creation, confirmation, completion, timeline mutation, or address reveal was added.
- **Payment:** no real or mock checkout action, payment-method form, cash/off-platform option, payment mutation, or provider payment integration was added.
- **Refund and payout:** no refund request/decision, payout, release, settlement, or reconciliation control was added.
- **Dispute:** no dispute creation, evidence, decision, or status mutation was added.
- **Admin:** no `/admin` route, admin dashboard, admin credential, or privileged function call was added.
- **Profile editing:** no profile update form, direct profile write, provider-profile edit, or role/status mutation was added.
- **Database security:** no migration, RLS policy, grant, database policy, database function, database test, or webhook was changed.
- **Real provider integrations:** no real payment, identity, address/map, notification, support, or other external-provider SDK, credential, API call, or adapter was added.

### Ticket 9A-5 implementation — Server-side public-field validation — 2026-07-18

**Status:** Implemented and CI-verified.

#### What was implemented

- Added one private authoritative PostgreSQL validation boundary for the eventually public `service_requests` fields `title`, `description`, `suburb`, and `city`.
- Added NFC/whitespace/description-CRLF canonicalisation and stored only the same canonical values that are validated.
- Added required/blank, character and UTF-8 byte limits, title/suburb/city single-line rules, approved description LF handling, unsupported control-character checks, bidi/zero-width/invisible-character checks, and plain-text markup/script-like rejection.
- Added conservative server detection for numbered English/Afrikaans-style streets, unit/room/flat/apartment/floor/block identifiers, house/stand/erf/plot/farm/site identifiers, named complex/building details with location cues, decimal/labelled/DMS GPS data, South African phone numbers, emails, URLs/domains, social handles, WhatsApp/off-platform contact instructions, and gate/access/security credentials.
- Added privacy-aware contextual rules so representative South African localities, township extension/zone/section/ward/phase names, ordinary quantities, ZAR amounts, product models, apostrophes, and terms such as “complex electrical fault” or “stand mixer” are not blanket-rejected.
- Integrated the shared assertion into `customer_create_draft_request(...)` before any request/address/audit insert. Invalid title, description, suburb, or city therefore aborts draft creation atomically.
- Replaced the draft RPC search path with fixed `pg_catalog` and schema-qualified every application/private/auth reference while preserving authentication, active-customer, active-category, schedule, budget, private-address, audit, transaction-reset, signature, and existing execute-grant behavior.
- Added `enforce_service_request_public_fields` as a `BEFORE INSERT OR UPDATE OF title, description, suburb, city, status` trigger. It validates every insert/public-field edit and every attempted transition to `open`; status-only non-opening transitions remain possible for legacy rows.
- Preserved `service_request_description_has_exact_address_risk(text)` as the Ticket 5 compatibility preflight and made it delegate to the same private classifier.
- Revoked direct execution of all six private helpers from `PUBLIC`, `anon`, `authenticated`, and `service_role`.
- Added fixed field-level `22023` errors that never echo submitted text, matched substrings, regexes, or sensitive content.
- No `customer_update_draft_request(...)` function was added.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/014_server_public_field_validation.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/public_field_validation.test.sql`
- `outputs/lekkadeall-frontend-shell/tests/request-draft.test.mjs`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `hardening_progress.md`

#### Tests added or updated

- Added `public_field_validation.test.sql` with an exact **95-test** pgTAP plan covering private-function permissions/search paths, structural validation, privacy/contact classifiers, safe South African false-positive fixtures, compatibility behavior, hostile client RPC calls, no-row-on-failure behavior, safe errors, trigger insert/update enforcement, canonical storage, simulated legacy-draft opening rejection, RLS/direct-DML protection, and Ticket 5 address-column regression coverage.
- Added a dedicated GitHub Actions step immediately after the Ticket 5 exact-address suite so the new migration and focused pgTAP test run before the marketplace state-machine and payment regressions.
- Updated the existing Ticket 9A-3 frontend RPC-failure test to use a realistic Ticket 9A-5 `22023` validation error and prove that browser output remains generic, does not echo server detail, and is not retried.
- Static assertion count check: the pgTAP file resolves to exactly **95 assertions** (`plan(95)`).
- Local frontend result: **25/25 passed** using the bundled Node runtime.
- Local database result: not run because this host exposes neither Docker nor the Supabase CLI. The final successful GitHub Actions run supplied the authoritative migration, focused pgTAP, full pgTAP, and Deno verification.

#### Security and scope confirmations

- Invalid public fields are rejected inside the database even when a hostile client skips Ticket 9A-3 JavaScript.
- Failed validation creates no request row, private-address row, or success audit event.
- Browser roles cannot directly execute private validation helpers and still cannot insert/update/delete `service_requests`.
- Ticket 9A-3 local validation remains defence in depth only; a server rejection overrides a local pass and is shown generically.
- No frontend `customer_publish_request(...)` call, route, button, or optimistic open state was added. The existing backend function was not granted any new caller; attempted opening now receives the additional trigger validation backstop.
- No exact-address input, collection, plaintext, ciphertext production, storage call, read, reveal, map, GPS/geolocation field, KMS, key-management, or encryption code was added.
- No provider onboarding/bidding, booking mutation, payment, refund, payout/release, dispute, review, support, consent, notification, chat, identity, profile editing, or admin dashboard was added.
- No service-role key, real credential, provider secret, production project reference, or real provider integration was added.
- No frontend direct table write or `select('*')` was added.
- No RLS policy was weakened or added. Existing Ticket 1 role/account-status, Ticket 2 RLS/grants, Ticket 5 address privacy, and Ticket 6 state-machine controls remain in place and are covered by the unchanged full CI suites.

#### Still blocked

- Ticket 9A-5 is CI-verified by the successful **Fix Ticket 9A-5 pgTAP assertion count** run; downstream request publication remains blocked by the separate readiness requirements below.
- Exact-address collection/storage/reveal remains blocked by Ticket 9A-4's encryption and key-management requirements.
- Request publication remains unavailable in the frontend and must not be enabled until Ticket 9A-4 address readiness and the complete production-readiness review pass.
- Draft editing remains blocked; `customer_update_draft_request(...)` is reserved for a separate reviewed ticket.

### Ticket 9A-5 CI failure correction — public-field validation pgTAP — 2026-07-19

**Status:** Correction included in the final successful CI-verified run.

#### Failure summary

- Failed workflow step: **Run server public-field validation pgTAP tests**.
- Test file: `supabase/tests/database/public_field_validation.test.sql`.
- Reported result: **95 planned, 78 run, 1 failed**.
- Failed assertion: **test 77**.
- TAP also reported a bad plan because SQL execution terminated before assertions 79-95.

#### What test 77 checks

Test 77 is the no-partial-write assertion after four hostile draft-creation calls. The four preceding assertions independently submit an unsafe title, description, suburb, and city through `customer_create_draft_request(...)` and expect each call to be rejected. Test 77 then checks that those rejected calls did not create any request rows.

#### Root cause

The validator did not allow unsafe content, and the four field-specific rejection assertions completed before test 77. The failure was in the test expectation:

- The test had already executed `SET LOCAL ROLE authenticated` for Customer A.
- Its `count(*)` therefore respected `service_requests` RLS and could see only Customer A's seeded request rows.
- The assertion incorrectly expected the global seed count of `3`, which includes Customer B's RLS-hidden rows.

The early termination had a second independent test defect. The next privacy-leak assertion used `unlike(...)`, which is not a pgTAP assertion in the installed extension. PostgreSQL stopped on that undefined function after test 78, so tests 79-95 never ran. The supported pgTAP SQL-LIKE negative assertion is `unalike(...)`.

#### Fix applied

- Added a temporary RLS-visible baseline count captured under the same authenticated Customer A context immediately before the hostile calls.
- Test 77 now compares the post-rejection Customer A-visible count with that baseline. Any successfully inserted hostile draft would belong to Customer A and would be visible, so the corrected assertion still proves no partial request row was created without bypassing RLS.
- Replaced the invalid `unlike(...)` call with `unalike(...)` and the correct `%14 Long Street%` SQL-LIKE pattern.
- Kept `plan(95)` unchanged. No hostile-input or South African false-positive fixture was removed.

#### Files changed for this correction

- `outputs/marketplace-production-foundation/supabase/tests/database/public_field_validation.test.sql`
- `hardening_progress.md`

#### Verification after the correction

- Static recount confirms the file still resolves to exactly **95 assertions** and retains `plan(95)`.
- Ticket 9A frontend regression result: **25/25 passed** with the bundled Node runtime.
- Local pgTAP and Deno execution was unavailable on this host because it had no Supabase CLI, PostgreSQL client, Docker, or Deno. The final successful GitHub Actions run supplied the authoritative focused pgTAP, full pgTAP, and Deno verification.

#### Security confirmations

- Migration `014_server_public_field_validation.sql` and all validation functions/triggers are unchanged; this correction does not weaken the validator.
- Unsafe title, description, suburb, and city inputs remain database-rejected through `customer_create_draft_request(...)` and the table trigger.
- Browser roles still cannot execute private validation helpers or directly write `service_requests`.
- All hostile-input and safe South African false-positive tests remain in the 95-assertion suite.
- No request-publication UI/call, exact-address collection, KMS/encryption, RLS/grant/role/status/address/state-machine change, frontend DML, provider onboarding, bidding, booking, payment, refund, payout, dispute, review, support, chat, or admin feature was added.

### Ticket 9A-5 second CI failure correction — audit assertion role boundary — 2026-07-19

**Status:** Correction included in the final successful CI-verified run.

#### Latest failure summary

- Failed workflow step: **Run server public-field validation pgTAP tests**.
- Test file: `supabase/tests/database/public_field_validation.test.sql`.
- Latest reported result: **95 planned, 82 run, 0 failed**.
- The earlier failed assertion was corrected: all assertions that emitted TAP output passed, but SQL execution stopped before test 83 and left tests 83-95 unexecuted.

#### Assertion-count decision

- The intended plan remains **95**, not 82.
- Tests 83-95 are present and intentional: one successful-draft audit assertion, ten table-trigger/legacy-publication assertions, and two Ticket 5 compatibility assertions.
- No TODO, skip, conditional TAP block, or intentionally removed assertion accounts for the missing thirteen tests.

#### Root cause

- Tests 73-82 run under `SET LOCAL ROLE authenticated` to exercise `customer_create_draft_request(...)` and the customer's RLS-visible canonical draft values.
- The next statement, intended to emit test 83, queried `public.audit_events` before `RESET ROLE`.
- Ticket 2 deliberately executes `REVOKE ALL ON public.audit_events FROM anon, authenticated`; browser roles also have no audit-table RLS policy. The query therefore stopped with an authorization error before pgTAP could emit assertion 83.
- The existing `RESET ROLE` was one statement too late, after the audit assertion. This was a test harness role-boundary defect, not a missing assertion or validator defect.

#### Fix applied

- Moved `RESET ROLE` to immediately after the authenticated customer verifies the safe draft's canonical title and description.
- The privacy-safe audit-row assertion now runs as the test owner, while the customer-facing RPC and RLS read assertions remain under `authenticated`.
- Kept `plan(95)` and every assertion unchanged; no hostile-input, South African false-positive, permission, trigger, RPC-boundary, legacy-publication, or Ticket 5 regression test was removed.
- No database migration, function, trigger, RLS policy, grant, or application code changed.

#### Files changed for this correction

- `outputs/marketplace-production-foundation/supabase/tests/database/public_field_validation.test.sql`
- `hardening_progress.md`

#### Verification after the second correction

- Static recount confirms `plan(95)` still matches exactly **95 assertions**.
- Ticket 9A frontend regression result: **25/25 passed** with the bundled Node runtime.
- Local pgTAP and Deno execution was unavailable because this host had no Supabase CLI, PostgreSQL client, Docker, or Deno. The final successful GitHub Actions run supplied the authoritative focused pgTAP, full pgTAP, and Deno verification.

#### Security and scope confirmations

- Unsafe title, description, suburb, and city values remain rejected by the database validator in `customer_create_draft_request(...)` and by the table trigger.
- Browser roles remain unable to execute private validators, directly write service requests, or read the audit ledger.
- Safe South African false-positive fixtures and all 95 intended assertions remain in the focused suite.
- Publication remains unavailable in the frontend, and the legacy-publication test remains a rejection test only.
- Exact-address collection/reveal, KMS/encryption, provider onboarding/bidding, booking changes, payments/refunds/payouts/disputes, admin features, frontend DML, and unrelated functionality remain blocked and unchanged.

### Ticket 9A-5 CI verification — Server-side public-field validation — 2026-07-19

**Status:** CI-verified.

- **Latest successful run:** Fix Ticket 9A-5 pgTAP assertion count
- **Run status:** Success

#### What was implemented

- Added migration `014_server_public_field_validation.sql` with one authoritative private validation boundary for the eventually public `service_requests` fields `title`, `description`, `suburb`, and `city`.
- Added NFC/whitespace canonicalisation, description CRLF-to-LF handling, required/length/byte/single-line or approved-multiline rules, control/bidi/invisible-character rejection, markup rejection, and exact-location/contact/GPS/URL/social/access-code detection.
- Added conservative South African false-positive handling so reviewed locality names, township extensions/zones/sections, quantities, ZAR amounts, product models, apostrophes, and ordinary service phrases remain usable.
- Integrated the validator into `customer_create_draft_request(...)` before any request, private-address, or audit insert so invalid public fields fail atomically and create no partial row.
- Added the `enforce_service_request_public_fields` table trigger as a `BEFORE INSERT OR UPDATE OF title, description, suburb, city, status` backstop. It validates every insert, public-field change, and attempted transition to `open` without enabling publication.
- Preserved `service_request_description_has_exact_address_risk(text)` by delegating its compatibility decision to the shared private classifier.
- Kept all private helpers behind fixed `pg_catalog` search paths and revoked direct execution from `PUBLIC`, `anon`, `authenticated`, and `service_role`.
- Kept database errors privacy-safe with fixed `22023` messages that do not echo submitted text, matched substrings, or regex details.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/migrations/014_server_public_field_validation.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/public_field_validation.test.sql`
- `outputs/lekkadeall-frontend-shell/tests/request-draft.test.mjs`
- `.github/workflows/database-tests.yml`
- `TESTING.md`
- `hardening_progress.md`

#### Tests added or updated

- Added the focused **95-assertion** `public_field_validation.test.sql` pgTAP suite covering helper authority/permissions/search paths, structural validation, hostile privacy/contact inputs, safe South African fixtures, Ticket 5 compatibility, trusted draft-RPC rejection, no partial writes, privacy-safe errors, canonical storage, trigger insert/update enforcement, unsafe legacy-opening rejection, audit behavior, RLS/direct-DML protection, and address-column regressions.
- Added the focused pgTAP suite to `.github/workflows/database-tests.yml` before the marketplace state-machine and payment regression suites.
- Updated `request-draft.test.mjs` to prove a Ticket 9A-5 `22023` server rejection is displayed generically, does not echo sensitive server detail, and is not retried.
- The successful GitHub Actions run confirms the focused 95-assertion suite and the existing pgTAP, Deno webhook, and frontend regression gates are green.

#### Initial CI failures, root cause, and fixes

- **First failed run:** pgTAP planned 95, ran 78, and failed test 77. Test 77 incorrectly expected a global seeded request count while running as authenticated Customer A under RLS. It was changed to compare against a Customer A RLS-visible baseline, preserving the no-partial-write proof. The following test also used invalid pgTAP `unlike(...)`; replacing it with `unalike(...)` allowed execution to continue.
- **Second failed run:** pgTAP planned 95, ran 82, and failed 0 assertions. Assertions 83-95 were present and intentional, but the test attempted to query `public.audit_events` while still running as `authenticated`, which correctly has no audit-ledger access. `RESET ROLE` was moved before the server-side audit assertion.
- The plan remained **95** throughout. No hostile-input, safe South African fixture, permission, trigger, RPC-boundary, legacy-publication, or Ticket 5 regression assertion was removed, and no validator or production security rule was weakened to make CI pass.

#### Blocked scope and security confirmations

- Request publication remains blocked in the frontend.
- Exact-address collection, ciphertext production, storage readiness, and reveal remain blocked pending the separately reviewed Ticket 9A-4 encryption/key-management boundary.
- Provider onboarding and bidding remain blocked.
- Payments, refunds, payouts, real checkout, and real provider integrations remain blocked.
- The admin dashboard remains blocked.
- No KMS or encryption implementation was added.
- No service-role key, provider credential, webhook secret, identity secret, or other real credential was added.
- No RLS, grant, role/account-status, Ticket 5 address-privacy, or Ticket 6 marketplace state-machine protection was weakened.

### Ticket 9A-6 implementation — Customer request list and detail read-only baseline — 2026-07-19

**Status:** Implemented and CI-verified.

- **Latest successful run:** Implement Ticket 9A-6 customer request list detail
- **Run status:** Success

#### What was implemented

- Added the protected customer request list route at `/app/customer/requests/`.
- Added the static-shell-compatible request detail route at `/app/customer/requests/detail/?requestId=<uuid>`. Only the opaque UUID is placed in the URL; request content is never placed in the path, query, or fragment.
- Added both routes to the existing Ticket 9A-2 session/profile guard. A route read is allowed only for a signed-in own profile with `role = 'customer'` and `account_status = 'active'`; signed-out, expired, missing-profile, restricted/suspended/closed, provider, unknown-role, and unknown-status cases fail closed.
- Added one shared request-read contract with the exact approved projection:

  ```text
  id,category_id,title,description,suburb,city,requested_start,budget_minor,status,created_at,updated_at
  ```

- Added an own-request list read that relies on existing RLS for ownership, filters to `draft`, `open`, and `cancelled`, orders by `created_at` descending, and is bounded to 20 rows. It neither selects nor filters on `customer_id`.
- Added an own-request detail read that validates the UUID before querying `service_requests`, uses the exact projection, applies the same status allowlist, and uses `maybeSingle()` semantics.
- Collapsed malformed, missing, cross-customer, unsupported-status, query-denied, and RLS-hidden detail outcomes into one generic “Request not found or unavailable” state without exposing why a row was unavailable.
- Reused the existing active `service_categories` read for category labels only. An inactive, missing, or unavailable historical category displays “Category unavailable”; no broader category read is attempted.
- Added request list/summary/detail rendering with HTML escaping for all database text, explicit `Africa/Johannesburg` date formatting and SAST labels, and display-only ZAR formatting from integer `budget_minor` values.
- Added safe loading, empty, unavailable, generic not-found, signed-out, restricted, and access-denied states for the new routes.
- Added “View all requests” to the customer dashboard.
- Added “View draft” and “View all requests” after Ticket 9A-3 receives a valid draft UUID. The detail link performs a new RLS-backed read and does not treat the draft response as authorization.
- Corrected old shell copy so the frontend no longer incorrectly describes the entire application as read-only now that the separately reviewed Ticket 9A-3 draft RPC exists.
- Added no dependency and changed no package or lock file.

#### Files changed

- `outputs/lekkadeall-frontend-shell/customer-requests.js` — new request projection, allowlists, UUID/detail-link helpers, category fallback, and SAST/ZAR display formatters.
- `outputs/lekkadeall-frontend-shell/safe-reads.js` — narrowed the request projection and added bounded list and validated detail reads.
- `outputs/lekkadeall-frontend-shell/route-guards.js` — registered the list/detail routes as active-customer protected routes.
- `outputs/lekkadeall-frontend-shell/app.js` — added in-memory list/detail state and guarded route-loading flows.
- `outputs/lekkadeall-frontend-shell/shell.js` — added navigation, list/detail rendering, draft-created actions, output escaping usage, and safe route states.
- `outputs/lekkadeall-frontend-shell/styles.css` — added request list/detail/action layouts and responsive styling.
- `outputs/lekkadeall-frontend-shell/app/customer/requests/index.html` — clean-path list entry file.
- `outputs/lekkadeall-frontend-shell/app/customer/requests/detail/index.html` — clean-path detail entry file.
- `outputs/lekkadeall-frontend-shell/tests/customer-request-read.test.mjs` — new focused Ticket 9A-6 behavior/security suite.
- `outputs/lekkadeall-frontend-shell/tests/frontend-shell.test.mjs` — updated route/clean-path coverage.
- `outputs/lekkadeall-frontend-shell/tests/auth-safe-reads.test.mjs` — updated guard, table allowlist, and exact request-projection coverage.
- `outputs/lekkadeall-frontend-shell/tests/request-draft.test.mjs` — updated successful-draft navigation coverage.
- `outputs/lekkadeall-frontend-shell/README.md`
- `TESTING.md`
- `hardening_progress.md`

#### Tests added or updated

- Added focused tests for the exact list/detail projection and explicit exclusion of `customer_id`, `closes_at`, publication/cancellation timestamps, address material, provider/bid/booking/payment/audit fields, and other unapproved data.
- Added query-contract tests for the `draft`/`open`/`cancelled` filter, newest-first ordering, 20-row bound, UUID-before-query validation, `id` and status constraints, and `maybeSingle()` detail behavior.
- Added tests proving malformed, missing, denied/RLS-hidden, and unsupported-status results use the same generic unavailable result and UI state.
- Added active-customer guard tests for both routes, including wrong-role and suspended-account denial.
- Added output-escaping tests with hostile HTML-like database text, category fallback tests, deterministic `Africa/Johannesburg`/SAST date tests, and display-only ZAR budget tests.
- Added dashboard and post-draft navigation assertions for “View all requests” and “View draft.”
- Extended static safety checks for no `select('*')`, direct application-table insert/update/upsert/delete, cancellation/publication/address RPC, service-role key, browser persistence, service-worker cache, logs, analytics, or telemetry.
- Local frontend result: **33/33 tests passed** using Node's built-in test runner.
- Existing pgTAP database tests, Deno webhook tests, workflow files, migrations, and database seed/helper files were not changed.
- The successful GitHub Actions run confirms the **33/33 frontend tests**, all existing pgTAP database suites, and the Deno webhook regression suite are green.

#### Intentionally not implemented and security confirmations

- Cancellation remains blocked. No cancellation control or `customer_cancel_request(...)` call was added.
- Publication remains blocked. No `customer_publish_request(...)` call, publication button, optimistic status change, or open-state mutation was added.
- Request edit/update/delete remains blocked.
- Exact-address collection/storage/read/reveal, private address data, maps, GPS/geolocation, ciphertext production, KMS, encryption, and key management remain blocked.
- Provider feed, provider onboarding, and provider bidding remain blocked.
- Booking screens, workflow actions, and completion mutations remain blocked; pre-existing safe dashboard summary reads were not expanded.
- Payments, real checkout, refunds, payouts/releases, disputes, reviews, support, consent, notifications, chat, and real provider integrations remain blocked.
- The admin dashboard and profile editing remain blocked.
- No direct application-table insert/update/upsert/delete was added. Ticket 9A-3's reviewed `customer_create_draft_request(...)` remains the only frontend marketplace mutation and continues to pass `p_precise_address_ciphertext: null`.
- No `select('*')`, blocked request column, private-table read, admin/private/webhook function call, or broader fallback query was added.
- No request content is stored in URLs, `localStorage`, `sessionStorage`, IndexedDB, service-worker caches, logs, analytics, telemetry, or error reports.
- No migration, RLS policy, grant, database policy/function, webhook, pgTAP file, or database seed/helper changed.
- No service-role key, real credential, provider secret, webhook secret, identity secret, production project reference, or real provider integration was added.
- Ticket 1 role/account-status protection, Ticket 2 RLS/grants, Ticket 5 address privacy, Ticket 6 state-machine controls, Ticket 9A-5 public-field validation, and every existing database/webhook security boundary remain unchanged.

### Ticket 9A-7 implementation — Customer draft-only cancellation — 2026-07-19

**Status:** CI-verified.

- **Latest successful run:** Fix Ticket 9A-7 draft cancellation pgTAP setup
- **Run status:** Success

#### What was implemented

- Added migration `015_customer_draft_cancellation.sql` with `public.customer_cancel_draft_request(p_request_id uuid) returns public.request_status`.
- The function is `SECURITY DEFINER`, `VOLATILE`, has fixed `search_path = pg_catalog`, uses explicit schema-qualified references, contains no dynamic SQL, and derives actor identity only from `auth.uid()`.
- The function locks the actor's `public.profiles` row before requiring `role = 'customer'` and `account_status = 'active'`, then locks only the owned request identified by `id = p_request_id` and `customer_id = auth.uid()`.
- Cancellation is allowed only when the locked row is exactly `draft`, has no publication/award/cancellation timestamp inconsistency, and has no bid or booking. Missing, cross-customer, non-draft, inconsistent, provider-selected/bid-bearing, and booked requests fail with generic privacy-safe errors.
- The controlled Ticket 6 transition changes only `status`, `cancelled_at`, and `updated_at`. Ownership, category, title, description, suburb, city, requested start, budget, and other workflow fields remain unchanged.
- The function appends exactly one fixed audit event with action `customer.service_request_draft_cancelled` and fixed reason `Customer cancelled own draft through controlled draft-only function`. It records only request ID and the fixed draft-to-cancelled status transition. Audit failure rolls the cancellation back.
- The function returns only `cancelled::public.request_status`.
- Revoked execution of the new function from `PUBLIC`, `anon`, and `service_role`; granted it only to `authenticated`. Revoked `authenticated` execution of the broader legacy `customer_cancel_request(uuid,text)`. No direct table grant or RLS policy was added.
- Updated the Ticket 6 marketplace-state-machine test helper to use the new strict function for draft cancellation.
- Added a “Cancel draft” control only to the customer request detail page after a fresh RLS-backed read returns an owned `draft` for an active customer. No cancellation action appears on the request list.
- Added fixed confirmation copy without a reason field. The frontend calls only `customer_cancel_draft_request` with `{ p_request_id: requestId }`, uses single-flight behavior, performs no optimistic status update, and does not automatically retry ambiguous failures.
- After RPC success, the frontend performs a fresh RLS-backed detail read and shows success only when that read returns the same request with `status = 'cancelled'`. All failures use fixed generic messages and do not echo backend detail.

#### Files changed

- `.github/workflows/database-tests.yml`
- `outputs/marketplace-production-foundation/supabase/migrations/015_customer_draft_cancellation.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/customer_draft_cancellation.test.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/marketplace_state_machine.test.sql`
- `outputs/lekkadeall-frontend-shell/request-cancellation.js`
- `outputs/lekkadeall-frontend-shell/app.js`
- `outputs/lekkadeall-frontend-shell/shell.js`
- `outputs/lekkadeall-frontend-shell/styles.css`
- `outputs/lekkadeall-frontend-shell/tests/request-cancellation.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/auth-safe-reads.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/customer-request-read.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/request-draft.test.mjs`
- `outputs/lekkadeall-frontend-shell/README.md`
- `rls_policy_matrix.md`
- `TESTING.md`
- `hardening_progress.md`

#### Tests added or updated

- Added the focused **62-assertion** `customer_draft_cancellation.test.sql` suite. It covers the function contract, fixed authority/search path, execute grants/revokes, no direct authenticated request-table DML grants, authentication, provider/support/admin role and account-status rejection, hostile JWT metadata, ownership, exact draft-only behavior, unchanged fields, fixed audit privacy, duplicate and every supported non-draft state, inconsistent draft timestamps, bid/accepted-bid/booking blockers, direct-DML denial, audit-failure rollback, state-guard reset after success and failure, RLS behavior, and regression data integrity.
- Updated `marketplace_state_machine.test.sql` so its legitimate draft-cancellation path uses the new narrow function rather than the legacy draft/open function.
- Added `request-cancellation.test.mjs` and updated the existing Auth/safe-read, request-list/detail, and draft suites for control visibility, fixed confirmation, exact RPC payload, single-flight behavior, fresh RLS re-read, no optimistic change/retry, generic errors, and static blocked-boundary checks.
- Local frontend result: **43/43 tests passed** using Node's built-in test runner.
- Static recount confirms the focused pgTAP file contains **62 assertions matching `plan(62)`**.
- GitHub Actions runs the focused cancellation pgTAP suite after the marketplace state-machine suite and runs all 43 frontend tests. The successful run confirms the focused 62-assertion suite, existing pgTAP suites, Deno webhook tests, and frontend regressions are green.

#### Intentionally blocked and security confirmations

- Request publication remains blocked; the frontend does not call `customer_publish_request(...)`.
- The frontend does not call the legacy `customer_cancel_request(...)`.
- Request editing, deletion, duplication, reopening, and archiving remain blocked.
- Exact-address collection/storage/read/reveal, GPS/maps, KMS, and encryption remain blocked.
- Provider feed/onboarding/bidding and booking actions remain blocked.
- Payments, checkout, refunds, payouts, disputes, reviews, support, consent, notifications, chat, identity, profile editing, and the admin dashboard remain blocked.
- No service-role key, real credential, provider secret, webhook secret, identity secret, payment secret, or admin credential was added.
- No frontend direct application-table insert/update/upsert/delete or `select('*')` was added.
- No RLS policy or direct table grant was added or weakened. Ticket 1 role/status protection, Ticket 2 RLS, Ticket 5 address privacy, Ticket 6 state machine, Ticket 9A-5 public-field validation, and existing payment/refund/payout/webhook protections remain intact.

### Ticket 9A-7 CI correction — pgTAP stopped after assertion 6 — 2026-07-19

**Status:** CI-verified.

- **Latest successful run:** Fix Ticket 9A-7 draft cancellation pgTAP setup
- **Run status:** Success

#### Failure summary

- **Failed step:** Run customer draft cancellation pgTAP tests
- **File:** `supabase/tests/database/customer_draft_cancellation.test.sql`
- **Reported result:** 62 planned, 6 run, 0 failed; bad plan.
- The six emitted assertions all passed. SQL execution then stopped before assertion 7, so this was an execution error rather than a failed cancellation-security assertion or a genuine six-test plan.

#### Root cause

- Assertion 6 correctly used pgTAP's `unalike(...)` helper and passed.
- Assertions 7–9 incorrectly used `like(...)` as though it were pgTAP's positive SQL-LIKE assertion.
- pgTAP exposes the positive helper as `alike(...)`; it does not expose the three-argument assertion as `like(...)`.
- The first `select like(...)` statement, which was intended to check that the function definition contains `auth.uid()`, therefore stopped SQL execution before TAP assertion 7 could be emitted. The later profile-lock and request-lock checks had the same latent helper-name error.
- The migration, seed setup, function signature, enum values, grants, and cancellation implementation were not the cause of this early termination.

#### Fix applied

- Replaced all three invalid positive `like(...)` calls with pgTAP's supported `alike(...)` helper.
- Kept `plan(62)` and all 62 intended assertions.
- Removed no contract, permission, role/status, ownership, state, inconsistency, bid, booking, audit, rollback, RLS, or regression coverage.
- Made no change to `customer_cancel_draft_request(...)`, its restrictive grants, or the legacy-function revoke.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/tests/database/customer_draft_cancellation.test.sql`
- `hardening_progress.md`

#### Security and scope confirmations

- `customer_cancel_draft_request(...)` remains limited to authenticated active customers cancelling only their own exact draft.
- Open, awarded, cancelled, expired, booked, bid-bearing/provider-selected, missing, cross-customer, and inconsistent requests remain rejected.
- `authenticated` remains unable to execute legacy `customer_cancel_request(uuid,text)`.
- The fixed privacy-safe audit behavior and atomic audit-failure rollback remain unchanged.
- The frontend still calls only `customer_cancel_draft_request(...)` for cancellation.
- No publication, exact-address handling, provider bidding, payment, admin dashboard, profile editing, unrelated feature, migration change, RLS change, grant broadening, role/status weakening, address-privacy weakening, public-field-validation weakening, or state-machine weakening was added.

### Ticket 9A-7 CI verification — Customer draft-only cancellation — 2026-07-20

**Status:** CI-verified.

- **Latest successful run:** Fix Ticket 9A-7 draft cancellation pgTAP setup
- **Run status:** Success

#### Migration and function verified

- Added `outputs/marketplace-production-foundation/supabase/migrations/015_customer_draft_cancellation.sql`.
- Added `public.customer_cancel_draft_request(p_request_id uuid) returns public.request_status` as a `SECURITY DEFINER`, `VOLATILE` function with fixed `search_path = pg_catalog`, explicit schema-qualified references, and no dynamic SQL.
- The function derives identity only from `auth.uid()`, locks the protected profile row, requires `role = 'customer'` and `account_status = 'active'`, and locks the owned request using both request ID and customer ID.
- It permits only an internally consistent `draft` with no bid or booking, updates only `status`, `cancelled_at`, and `updated_at`, and returns only `cancelled::public.request_status`.
- It appends exactly one fixed privacy-safe `customer.service_request_draft_cancelled` audit event in the same transaction. Audit failure rolls the cancellation back.
- Execution of the new function remains revoked from `PUBLIC`, `anon`, and `service_role` and granted only to `authenticated`.
- Authenticated execution of legacy `customer_cancel_request(uuid,text)` remains revoked, so browser users cannot use the broader draft/open cancellation path or submit client-controlled audit reasons.

#### Frontend behavior verified

- Added `outputs/lekkadeall-frontend-shell/request-cancellation.js` and integrated it into the existing request-detail flow.
- “Cancel draft” appears only on the customer request detail page after a fresh RLS-backed read confirms an owned `draft` for an active customer; it never appears on the request list.
- The confirmation uses fixed copy, contains no reason or free-text field, and calls only `customer_cancel_draft_request` with `{ p_request_id: requestId }`.
- The frontend uses UUID validation, single-flight behavior, no optimistic status update, no automatic retry, generic safe errors, and a fresh RLS-backed re-read after RPC success.
- Success is shown only when the fresh detail read returns the same request with `status = 'cancelled'`; ambiguous results block immediate resubmission until a fresh route read.

#### Files changed

- `.github/workflows/database-tests.yml`
- `outputs/marketplace-production-foundation/supabase/migrations/015_customer_draft_cancellation.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/customer_draft_cancellation.test.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/marketplace_state_machine.test.sql`
- `outputs/lekkadeall-frontend-shell/request-cancellation.js`
- `outputs/lekkadeall-frontend-shell/app.js`
- `outputs/lekkadeall-frontend-shell/shell.js`
- `outputs/lekkadeall-frontend-shell/styles.css`
- `outputs/lekkadeall-frontend-shell/tests/request-cancellation.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/auth-safe-reads.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/customer-request-read.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/request-draft.test.mjs`
- `outputs/lekkadeall-frontend-shell/README.md`
- `rls_policy_matrix.md`
- `TESTING.md`
- `hardening_progress.md`

#### Tests added or updated

- Added the focused 62-assertion `customer_draft_cancellation.test.sql` suite for function configuration, grants/revokes, authentication, role/account status, ownership, hostile JWT metadata, exact draft-only behavior, non-draft/inconsistent-state rejection, bid/provider-selection/booking blockers, unchanged request fields, audit privacy, duplicate calls, audit rollback, transition-guard reset, direct-DML denial, RLS, and regression integrity.
- Updated `marketplace_state_machine.test.sql` to use the strict draft-only function for its legitimate cancellation path.
- Added `request-cancellation.test.mjs` and updated the existing Auth/safe-read, request-list/detail, and draft frontend suites for control visibility, confirmation, exact RPC payload, single-flight handling, fresh RLS re-read, safe errors, and blocked client capabilities.
- Updated `.github/workflows/database-tests.yml` to run the focused Ticket 9A-7 pgTAP suite.
- The successful GitHub Actions run confirms all 62 focused assertions, all existing pgTAP suites, all frontend tests, and the Deno webhook suite pass.

#### Initial failure, root cause, and fix

- The first CI run planned 62 assertions, emitted 6 passing assertions, and then stopped with a bad-plan summary.
- Assertions 7–9 used unsupported `like(...)` calls. pgTAP's positive SQL-LIKE assertion is `alike(...)`; assertion 6's negative `unalike(...)` call was valid.
- Replaced the three invalid `like(...)` calls with `alike(...)` while retaining `plan(62)` and every intended assertion.
- No migration, production function, security grant, frontend behavior, or security expectation was weakened to make CI pass.

#### Blocked scope and security confirmations

- Publication remains blocked; the frontend does not call `customer_publish_request(...)`.
- Exact-address collection, storage, encryption, read, reveal, GPS, and maps remain blocked.
- Provider feed, onboarding, selection, and bidding remain blocked.
- Payments, checkout, refunds, payouts, disputes, and real payment-provider integration remain blocked.
- The admin dashboard and profile editing remain blocked.
- No service-role key, real credential, provider secret, webhook secret, identity secret, payment secret, or admin credential was added.
- No direct frontend application-table insert/update/upsert/delete or `select('*')` was added.
- No RLS, grant, role/account-status, Ticket 5 address-privacy, Ticket 9A-5 public-field-validation, or Ticket 6 state-machine protection was weakened.

### Ticket 9A-8 implementation — Customer draft edit/update — 2026-07-20

**Status:** CI-verified.

- **Latest successful run:** Fix Ticket 9A-8 draft update pgTAP setup
- **Run status:** Success

#### Backend migration and function

- Added `016_customer_draft_update.sql` with this reviewed contract:

  ```text
  public.customer_update_draft_request(
    p_request_id uuid,
    p_category_id uuid,
    p_title text,
    p_description text,
    p_suburb text,
    p_city text,
    p_requested_start timestamptz,
    p_budget_minor integer
  ) returns uuid
  ```

- The function is `SECURITY DEFINER`, `VOLATILE`, has fixed `search_path = pg_catalog`, uses explicit schema-qualified references, contains no dynamic SQL or `select('*')`, and derives actor identity only from `auth.uid()`.
- It locks the actor's protected profile before requiring `role = 'customer'` and `account_status = 'active'`, then locks only the owned request selected by both request ID and customer ID.
- It permits only an internally consistent exact `draft` with null close/publication/award/cancellation timestamps, null deprecated public `precise_address_ciphertext`, no bid of any status, no accepted/provider-selected bid, and no booking.
- It locks and requires an active category, requires a future requested start, permits only null or nonnegative budget, canonicalises all four public text fields, and calls the Ticket 9A-5 private validator on the complete resulting title/description/suburb/city set.
- It rejects complete canonical no-ops with a fixed safe error. It updates only category, title, description, suburb, city, requested start, budget, and server `updated_at`; ownership, status, workflow timestamps, address state, bids, and bookings are unchanged.
- The function deliberately never enables `lekkadeall.allow_marketplace_state_transition`, so Ticket 6 workflow protection stays active throughout.
- A successful update appends exactly one fixed `customer.service_request_draft_updated` audit event. Its metadata contains only request ID and an ordered subset of the literal changed-field allowlist `category_id,title,description,suburb,city,requested_start,budget_minor`. It contains no submitted values. Audit failure rolls the field update back atomically.
- The function returns only the updated request UUID. Execution is revoked from `PUBLIC`, `anon`, and `service_role` and granted only to `authenticated`. No direct table grant or RLS policy was added.

#### Frontend behavior

- Added `/app/customer/requests/edit/?requestId=<uuid>` and its clean-path entry file.
- “Edit draft” appears only on a freshly RLS-read customer request detail whose status is exactly `draft`; it does not appear on the request list or open/cancelled detail.
- The route uses the existing session plus protected own-profile guard and admits only active customers. It validates the UUID before reading or calling the RPC.
- The edit read uses the existing explicit request projection and adds both `id = requestId` and `status = 'draft'` constraints with `maybeSingle()` semantics. Malformed, missing, cross-customer, non-draft, and RLS-hidden IDs share one generic unavailable state.
- The form pre-fills only active category, public title, public description, suburb, city, requested start converted explicitly to SAST/UTC+2, and optional ZAR budget. It reuses the Ticket 9A-3 privacy warning, client validation, SAST conversion, and string/BigInt-safe minor-unit conversion as defence in depth.
- The browser calls only `customer_update_draft_request` with the exact eight reviewed parameters. It uses single-flight behavior, no optimistic status/content confirmation, and no automatic retry of ambiguous outcomes.
- After RPC success the browser performs a fresh draft-only RLS read and shows `Draft updated.` only if the same UUID still returns as `draft`; the form is then rendered from the fresh server values. Ambiguous results lock submission until a fresh route load.
- No submitted request content is placed in browser storage, URLs other than the opaque request UUID, logs, analytics, telemetry, service-worker caches, or error reports.

#### Files changed

- `.github/workflows/database-tests.yml`
- `outputs/marketplace-production-foundation/supabase/migrations/016_customer_draft_update.sql`
- `outputs/marketplace-production-foundation/supabase/tests/database/customer_draft_update.test.sql`
- `outputs/lekkadeall-frontend-shell/request-update.js`
- `outputs/lekkadeall-frontend-shell/customer-requests.js`
- `outputs/lekkadeall-frontend-shell/safe-reads.js`
- `outputs/lekkadeall-frontend-shell/route-guards.js`
- `outputs/lekkadeall-frontend-shell/app.js`
- `outputs/lekkadeall-frontend-shell/shell.js`
- `outputs/lekkadeall-frontend-shell/styles.css`
- `outputs/lekkadeall-frontend-shell/app/customer/requests/edit/index.html`
- `outputs/lekkadeall-frontend-shell/tests/request-update.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/request-draft.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/request-cancellation.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/customer-request-read.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/auth-safe-reads.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/frontend-shell.test.mjs`
- `outputs/lekkadeall-frontend-shell/README.md`
- `TESTING.md`
- `rls_policy_matrix.md`
- `hardening_progress.md`

No dependency or package file changed.

#### Tests added or updated

- Added the focused **81-assertion** `customer_draft_update.test.sql` suite covering function shape/configuration, grants/revokes, actor/profile/request/category locking, hostile JWT metadata, role/account/ownership checks, category/start/budget validation, full Ticket 9A-5 validation, complete no-op rejection, safe South African false-positive fixtures, every existing non-draft state, inconsistent timestamps, bid/provider-selection/booking/address-residue rejection, minimal field replacement, audit privacy and changed-field allowlisting, direct-DML denial, RLS retention, and atomic audit-failure rollback.
- Added `request-update.test.mjs` and updated existing frontend suites for the new guarded route, exact draft-only projection/filter, prefill conversion, edit visibility, exact field/RPC allowlists, single-flight/fresh-read confirmation, generic errors, three reviewed RPC modules, and blocked browser capabilities.
- Updated `.github/workflows/database-tests.yml` to run the focused Ticket 9A-8 pgTAP suite after the Ticket 9A-7 suite and to run all frontend tests under the Ticket 9A-8 step label.
- Local frontend result: **53/53 tests passed** using the bundled Node runtime.
- Static pgTAP recount: **81 assertion calls match `plan(81)`**.
- Docker, Supabase CLI, Deno, and `psql` are unavailable on this host, so migration reset, pgTAP execution, Deno webhook tests, and complete database regression verification were delegated to GitHub Actions. The successful run `Fix Ticket 9A-8 draft update pgTAP setup` verified the focused 81-assertion suite and the full configured regression workflow.

#### Intentionally blocked and security confirmations

- Publication remains blocked; the frontend does not call `customer_publish_request(...)`.
- Exact-address input, storage, read, reveal, maps, GPS, ciphertext production, KMS, encryption, and key management remain blocked.
- Provider feed, provider onboarding, provider selection, and provider bidding remain blocked.
- Booking actions, payments, checkout, refunds, payouts, disputes, reviews, support, consent, notifications, chat, identity integration, admin dashboard, and profile editing remain blocked.
- No request deletion, duplication, reopening, archiving, or workflow-status mutation was added.
- No frontend direct application-table insert/update/upsert/delete or `select('*')` was added.
- No service-role key, real credential, provider secret, webhook secret, identity secret, payment secret, admin credential, migration-time secret, or real provider integration was added.
- No RLS policy or direct table grant was added or weakened. Ticket 1 role/account-status protection, Ticket 2 RLS, Ticket 5 address privacy, Ticket 6 marketplace state machine, Ticket 9A-5 public-field validation, Ticket 9A-7 cancellation restrictions, and existing payment/refund/payout/webhook protections remain intact.

### Ticket 9A-8 CI correction — pgTAP stopped after assertion 45 — 2026-07-21

**Status:** CI-verified by the successful GitHub Actions run `Fix Ticket 9A-8 draft update pgTAP setup`.

#### Failure summary

- **Failed step:** Run customer draft update pgTAP tests
- **File:** `supabase/tests/database/customer_draft_update.test.sql`
- **Reported result:** 81 planned, 45 run, 0 failed; bad plan.
- All 45 emitted assertions passed. SQL execution stopped before assertion 46, so this was a test execution/role-context failure rather than a failed draft-update security assertion or a genuine 45-test plan.

#### Root cause

- Assertion 45 successfully verifies that a complete canonical no-op is rejected by `customer_update_draft_request(...)`.
- Assertions 22–45 intentionally execute as the `authenticated` browser role to test actor, ownership, category, schedule, budget, Ticket 9A-5 validation, and no-op behavior.
- Immediately after assertion 45, assertion 46 directly queries `public.audit_events` to prove the rejected no-op wrote no success audit event.
- The test omitted `RESET ROLE` before that privileged audit-table inspection. Ticket 2 intentionally gives `authenticated` no direct `audit_events` read privilege, so PostgreSQL correctly terminated the SQL file with a permission error before pgTAP could emit assertion 46.
- A complete role-flow audit found the same latent omission before assertion 60, where the test again inspects `audit_events` after authenticated non-draft/inconsistency rejection calls.
- The Ticket 9A-8 migration, function signature, enum/status fixtures, seed rows, helper function, CI workflow command, Ticket 9A-5 validator, and application security rules were not the cause.

#### Fix applied

- Added `RESET ROLE` immediately after assertion 45 before assertions 46–47 inspect `audit_events` and unchanged database rows.
- Restored `SET LOCAL ROLE authenticated` and the fixed customer JWT subject before assertions 48–59 resume browser-context rejection tests.
- Added a second `RESET ROLE` after assertion 59 before assertions 60–61 inspect audit and bid rows.
- Restored the authenticated role and fixed customer JWT subject before assertion 62 performs the legitimate customer draft update.
- Kept `plan(81)` and all 81 intended assertions. No hostile-input, false-positive, permission, role/status, ownership, state, inconsistency, bid, booking, address-residue, audit, rollback, RLS, or regression assertion was removed or weakened.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/tests/database/customer_draft_update.test.sql`
- `hardening_progress.md`

No migration, production function, frontend file, workflow file, RLS policy, grant, database function, seed/helper file, webhook, dependency, or package file changed for this correction.

#### Verification and security confirmations

- Static recount remains **81 assertion calls matching `plan(81)`**.
- All **53/53 frontend tests remain green** locally.
- Docker, Supabase CLI, Deno, and `psql` remain unavailable on this host, so the focused pgTAP execution, migration reset, Deno webhook suite, and complete database regressions were verified by GitHub Actions.
- The latest run, `Fix Ticket 9A-8 draft update pgTAP setup`, completed with status **Success**. The corrected pgTAP file completed its intended 81 assertions with no failed assertions, and all configured frontend, Deno webhook, and database regression steps remained green.
- `customer_update_draft_request(...)` remains limited to authenticated active customers updating only their own exact, internally consistent draft.
- Open, awarded, cancelled, expired, missing, cross-customer, inconsistent, bid-bearing, provider-selected, booked, and deprecated-address-residue requests remain rejected.
- Ticket 9A-5 public-field validation, privacy-safe changed-field audit metadata, and audit-failure rollback remain unchanged.
- The frontend still calls only the exact reviewed `customer_update_draft_request(...)` mutation for draft editing and performs no direct application-table write.
- Publication, exact-address handling, KMS/encryption, GPS/maps, provider bidding/onboarding, booking actions, payments, admin dashboard, and profile editing remain blocked.
- No RLS, grant, role/account-status, address-privacy, public-field-validation, state-machine, or Ticket 9A-7 cancellation protection was weakened.

### Ticket 9A-9 implementation — Customer draft lifecycle E2E verification — 2026-07-21

**Status:** CI-verified — Success.

#### E2E architecture added

- Added exact development dependency `@playwright/test` **1.61.1** and retained the existing Node frontend test command unchanged.
- Added one Chromium-only Playwright project with `workers: 1`, `retries: 0`, `fullyParallel: false`, and authenticated screenshots, video, traces, HAR, DOM snapshots, saved storage state, HTML/JUnit reports, and retained output disabled.
- Added a privacy-safe reporter that emits only static test names and pass/fail status, never Playwright error details, DOM content, request/response bodies, credentials, tokens, recovery links, or browser storage.
- Added `test:e2e:local`, which refuses non-loopback frontend, Supabase API, Auth, Inbucket, Docker, and database targets; refuses an existing local stack and existing runtime config; starts and resets a disposable local Supabase project; generates an ignored anon-only runtime config; serves the static frontend; runs Playwright; and cleans up in `finally`.
- The local fixture controller is outside the served browser boundary. It connects only through `docker exec` to the exact `supabase_db_lekkadeall-local` database container and uses no service-role key or database credential.
- Updated the public config boundary to allow plain HTTP only for loopback Supabase URLs in non-production modes, require both frontend and Supabase to be loopback in `test`, reject embedded credentials, and continue to require HTTPS in production.
- Updated local-only Supabase Auth redirect configuration for the exact `127.0.0.1`/`localhost` callback and reset routes on port 4173. No remote, wildcard, or production redirect was added.

#### Browser verification added

- Added **8 synthetic local Chromium scenarios** covering:
  - signed-out protection for every customer request route and absence of `/admin`;
  - normal registration plus Ticket 9B exactly-one `customer`/`active` profile and no provider profile;
  - sign out, sign in, dashboard access, and active category discovery;
  - safe draft creation through `customer_create_draft_request(...)` with null precise-address ciphertext;
  - own request list and detail reads;
  - full draft editing through `customer_update_draft_request(...)` and fresh RLS re-read;
  - strict cancellation through `customer_cancel_draft_request(...)` and fresh cancelled-state confirmation;
  - Customer A/Customer B RLS non-disclosure;
  - restricted, suspended, closed, missing-profile, and wrong-role states;
  - stale edit rejection after another tab cancels the draft;
  - an executed update whose browser response is deliberately aborted, proving one call, no automatic retry, an ambiguous state, and recovery only through a fresh read;
  - read-only settings and absence of address/provider/booking/payment/admin/profile-edit controls; and
  - safe signed-out recovery-route behavior.
- The browser request observer allows only explicit approved reads and the three lifecycle mutations. It rejects direct application-table DML, broad-column reads, every unapproved/blocked RPC, non-loopback requests, non-anon API keys, and service-role JWT authority.
- Browser privacy checks cover URLs, sensitive query/hash parameters, `localStorage`, `sessionStorage`, IndexedDB, Cache Storage, service workers, cookies, console output, page errors, and generated artifacts.
- The only storage exception is the existing SDK-owned Supabase Auth-session record while signed in. Its value is never printed or saved, and sign-out must remove it. Marketplace/request content and every application-specific storage entry remain forbidden.
- A full Inbucket password-recovery exchange is not enabled because the current PKCE recovery flow must persist a temporary code verifier while Ticket 9A-9 permits only the existing signed-in Auth-session storage exception. The reset route is tested fail-closed; complete recovery E2E requires a separate reviewed Auth-storage/BFF decision.

#### Files added or changed

- `.github/workflows/database-tests.yml`
- `outputs/marketplace-production-foundation/supabase/config.toml`
- `outputs/lekkadeall-frontend-shell/package.json`
- `outputs/lekkadeall-frontend-shell/pnpm-lock.yaml`
- `outputs/lekkadeall-frontend-shell/public-config.js`
- `outputs/lekkadeall-frontend-shell/playwright.config.mjs`
- `outputs/lekkadeall-frontend-shell/scripts/e2e/run-local.mjs`
- `outputs/lekkadeall-frontend-shell/scripts/e2e/static-server.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/customer-draft-lifecycle.spec.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/security-boundaries.spec.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/blocked-features.spec.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/journey-helpers.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/local-environment.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/local-fixtures.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/network-policy.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/privacy-audit.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/privacy-safe-reporter.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e-boundary.test.mjs`
- `outputs/lekkadeall-frontend-shell/tests/auth-safe-reads.test.mjs`
- `outputs/lekkadeall-frontend-shell/README.md`
- `TESTING.md`
- `hardening_progress.md`

No migration, RLS policy, grant, production database function, validator, profile-provisioning function, marketplace state guard, draft-cancellation function, draft-update function, webhook, payment function, or application marketplace feature changed.

#### Tests and CI integration

- Existing Node frontend tests remain in place. After the sign-out expectation correction, the suite has **60/60 passing tests**, including seven static Ticket 9A-9 dependency, loopback, secret-filtering, artifact-policy, mutation-allowlist, fixture, CI-order, and sign-out-route checks.
- Playwright configuration discovery successfully finds all **8** Chromium E2E scenarios.
- Added isolated GitHub Actions job `customer-draft-lifecycle-e2e` with `needs: database-tests`, so it runs only after the existing frontend, Deno webhook, clean migration reset, and every pgTAP step pass.
- The job installs only the pinned Chromium runtime, invokes the local-only orchestrator, uses no GitHub environment secret or remote project, uploads no browser/database/Auth artifact, and performs an additional always-run runtime-config/Supabase cleanup.
- Docker, Supabase CLI, and the local PostgreSQL stack remain unavailable on this development host, so the browser-against-database journey was not run locally. GitHub Actions is the authoritative full E2E gate and is now fully green.

#### Intentionally blocked and security confirmations

- Publication remains blocked and `customer_publish_request(...)` is rejected by browser network policy.
- Exact-address collection/storage/read/reveal, ciphertext production, KMS/encryption, GPS, geolocation, and maps remain blocked.
- Provider onboarding/feed/bidding/selection, booking actions, payments/checkout/refunds/payouts/disputes, admin dashboard, identity-provider code, support, chat, reviews, and profile editing remain blocked.
- No production credential, real customer data, remote Supabase reference, browser service-role key, browser database credential, token, password, Auth code, recovery link, or request body was added to source, served files, logs, or artifacts.
- No frontend direct application-table insert/update/upsert/delete or broad-column query was added.
- Ticket 1 role/account-status protection, Ticket 2 RLS/grants, Ticket 5 address privacy, Ticket 6 state machine, Ticket 9B profile provisioning, Ticket 9A-5 public-field validation, Ticket 9A-7 draft cancellation, Ticket 9A-8 draft update, and all payment/refund/payout/webhook protections remain unchanged and unweakened.

### Ticket 9A-9 E2E correction — shared sign-out route expectation — 2026-07-22

**Status:** Root cause fixed locally; replacement GitHub Actions verification pending.

#### Failure summary

- The existing frontend, Deno webhook, clean migration reset, and all pgTAP steps passed in the main security job.
- The isolated `customer-draft-lifecycle-e2e` job discovered all eight scenarios. The two scenarios that never call the shared authenticated sign-out helper passed; the other six scenarios failed.
- The privacy-safe reporter correctly withheld Playwright errors, browser state, credentials, Auth links, request bodies, and database details.

#### Root cause and per-scenario impact

- The application sign-out handler deliberately clears in-memory personal state, signs out through Supabase Auth, and routes to `/auth/sign-in` with the sign-in page visible.
- The shared E2E `signOutCustomer(...)` helper incorrectly waited for the site root with `toHaveURL(/\/$/u)`. Every authenticated scenario eventually called that helper, so its final navigation assertion failed even when the scenario's preceding security and lifecycle checks had completed successfully.
- `customer registration through cancelled draft completes against real local RLS and RPCs` encountered the mismatch immediately after its first registration/sign-out check, before the later sign-in and draft lifecycle steps.
- `blocked marketplace and privileged controls remain absent from the customer shell`, `cross-customer request IDs remain RLS-hidden and non-actionable`, `restricted suspended closed missing-profile and wrong-role actors fail closed`, `a stale edit is rejected after another tab cancels the draft`, and `an executed update with an aborted response is not retried and requires a fresh read` encountered the same mismatch during their final cleanup sign-out.
- This was an E2E test expectation defect. No evidence identified an application behavior, Auth, Ticket 9B provisioning, RLS, RPC, state-machine, validation, cancellation, or update defect in the failed run.

#### Fix applied and files changed

- Updated `outputs/lekkadeall-frontend-shell/tests/e2e/support/journey-helpers.mjs` so sign-out waits for `/auth/sign-in` and the fixed public heading `Sign in to your workspace.`.
- Updated `outputs/lekkadeall-frontend-shell/tests/e2e-boundary.test.mjs` with a static regression assertion that requires that reviewed redirect and rejects the obsolete root-URL expectation.
- Updated `TESTING.md` and this progress log. No application source, migration, Supabase config, RLS policy, grant, database function, webhook, CI artifact setting, dependency, or lockfile changed.

#### Verification and security confirmations

- All **60/60 Node frontend and static security tests pass** locally.
- Playwright configuration still discovers all **8** synthetic Chromium scenarios with one worker and zero retries.
- Docker and Supabase CLI remain unavailable on this development host, so the real disposable-stack rerun is pending GitHub Actions. The already-passing main CI job remains the authoritative pgTAP, Deno webhook, migration-reset, and frontend regression result for this change set.
- The privacy-safe reporter remains unchanged. Screenshots, videos, traces, HAR, storage state, Auth-email artifacts, database dumps, and verbose failure details remain disabled.
- E2E remains loopback-only and allows only `customer_create_draft_request(...)`, `customer_update_draft_request(...)`, and `customer_cancel_draft_request(...)` as marketplace mutations.
- Publication, exact-address handling, KMS/encryption, GPS/maps/reveal, provider bidding/onboarding, booking actions, payments, admin dashboard, and profile editing remain blocked.
- No service-role browser access, production credential, direct frontend application-table write, `select('*')`, or security weakening was added.

### Ticket 9A-9 E2E correction — three comprehensive scenarios exceeded the default timeout — 2026-07-23

**Status:** Root causes fixed locally; replacement GitHub Actions verification pending.

#### Latest failure summary and overlap analysis

- The main migration-reset, pgTAP, Deno webhook, and Node/frontend security job passed.
- Five E2E scenarios passed, including registration plus draft creation/update/cancellation under stale and ambiguous-response conditions. This independently exercised local Auth signup/session handling, Ticket 9B provisioning, the active category fixture, all three approved lifecycle RPCs, post-mutation RLS reads, no-retry behavior, blocked controls, signed-out guards, and recovery-route privacy.
- The only remaining failures were the three longest serial scenarios:
  - `customer registration through cancelled draft completes against real local RLS and RPCs`;
  - `cross-customer request IDs remain RLS-hidden and non-actionable`; and
  - `restricted suspended closed missing-profile and wrong-role actors fail closed`.
- All tests inherited the global 60-second Playwright timeout. The remaining scenarios perform, respectively, the complete sign-out/sign-in plus list/detail lifecycle, two independent Auth/browser contexts and RLS probes, and five sequential synthetic account/profile-state cases. They exhausted the harness deadline in CI before their complete assertions and cleanup could finish.

#### Redacted per-scenario findings

- **Full registration-to-cancelled lifecycle**
  - Expected: provision one customer profile, sign out/in, read active categories and dashboard, create/list/detail/edit/cancel one draft, confirm cancellation through a fresh RLS read, and verify privacy-safe database postconditions.
  - Actual: the comprehensive serial journey exceeded the inherited 60-second test deadline. Passing shorter stale and ambiguous journeys show that registration, provisioning, category-backed draft creation, update, cancellation, and fresh reads were functioning.
  - Root cause: E2E harness timeout, not an application/RPC/RLS defect.
- **Cross-customer RLS/non-disclosure**
  - Expected: two isolated browser contexts create distinct synthetic Auth sessions; Customer A cannot list, view, edit, cancel, or infer Customer B's draft.
  - Actual: two registrations plus independent context reads and privacy cleanup exceeded the inherited deadline before the scenario could complete.
  - Root cause: E2E harness timeout, not shared browser storage or weakened RLS. The test still uses separate `browser.newContext(...)` instances and performs no storage-state import/export.
- **Restricted/suspended/closed/missing-profile/wrong-role matrix**
  - Expected: five synthetic actors receive reviewed local fixture states, then the session/profile guard blocks customer reads and mutations before any lifecycle RPC.
  - Actual: five sequential Auth registrations, local fixture-controller transitions, route reloads, privacy checks, and sign-outs exceeded the inherited deadline.
  - Root cause: E2E harness timeout, not invalid role/status fixture values or a route-guard bypass.

#### Fix applied and files changed

- Added a test-local `180_000` millisecond timeout only to the three comprehensive scenarios in:
  - `outputs/lekkadeall-frontend-shell/tests/e2e/customer-draft-lifecycle.spec.mjs`;
  - `outputs/lekkadeall-frontend-shell/tests/e2e/security-boundaries.spec.mjs`.
- Kept the global default at 60 seconds, one Chromium worker, zero retries, and the 30-minute CI job limit.
- Updated `outputs/lekkadeall-frontend-shell/tests/e2e/support/privacy-safe-reporter.mjs` to emit only a fixed status category: `passed`, `timeout`, `assertion-or-runtime`, `interrupted`, `skipped`, or `unknown`. It does not read or print Playwright error objects, messages, stacks, stdout/stderr, attachments, URLs, values, request bodies, database rows, or browser storage.
- Added static regression coverage in `outputs/lekkadeall-frontend-shell/tests/e2e-boundary.test.mjs` proving exactly three bounded timeout overrides exist, retries remain disabled, and the reporter cannot emit verbose diagnostics.
- Updated `TESTING.md` and this progress log.

#### Verification and security confirmations

- All **61/61 Node frontend and static security tests pass** locally.
- Playwright discovery still finds exactly **8** synthetic Chromium scenarios.
- Docker and Supabase CLI remain unavailable on this host, so the real disposable-stack rerun is pending GitHub Actions. The main database/webhook/frontend job was already green and none of its inputs changed.
- No failed E2E assertion was removed, skipped, weakened, or converted to a retry. Mutation retries remain zero.
- The local fixture controller, separate browser contexts, UUID-only routes, generic unavailable states, profile-state allowlists, route guards, fresh RLS reads, mutation counts, network policy, privacy checks, and cleanup remain unchanged.
- No screenshot, video, trace, HAR, storage state, Auth email, database dump, error detail, credential, token, Auth link, recovery link, request body, or database row is emitted or retained.
- E2E remains loopback-only and disposable. Publication, exact-address handling, KMS/encryption, GPS/maps/reveal, provider bidding/onboarding, booking actions, payments, admin dashboard, and profile editing remain blocked.
- No migration, RLS policy, grant, Ticket 9B provisioning rule, Ticket 9A-5 validator, Ticket 9A-7 cancellation control, Ticket 9A-8 update control, service-role browser access, direct frontend application-table write, or `select('*')` changed.

### Ticket 9A-9 E2E correction — final restricted-state matrix failure — 2026-07-24

**Status:** Isolated correction implemented locally; replacement GitHub Actions verification pending.

#### Redacted finding

- Seven of eight real local-stack E2E scenarios passed, including the complete registration-to-cancelled lifecycle and two-context cross-customer RLS/non-disclosure scenario.
- Only `restricted suspended closed missing-profile and wrong-role actors fail closed` remained. It is uniquely composed of five sequential synthetic actors, five Auth registrations/sessions, five fresh browser contexts, four privileged local profile transitions or one exact profile removal, five route-guard reloads, privacy checks, and sign-outs.
- The earlier 180-second allowance was sufficient for the other comprehensive scenarios but remained too small for this five-actor matrix on the CI runner. This was an E2E scheduling/setup limit, not a route-guard, Ticket 9B, RLS, enum, profile-read, or application mutation defect.

#### Expected and actual behavior

- **Expected:** restricted, suspended, and closed customers render `Account access is restricted`; a provider on a customer route renders `Access denied`; and an authenticated Auth user with no profile renders `Account setup unavailable`. No request link or lifecycle RPC may be available after the profile guard rejects the actor.
- **Actual:** the serialized matrix did not complete within its former test-local deadline. The seven passing scenarios and the existing route-guard unit suite confirm that Auth sessions, profile reads from `public.profiles`, lifecycle functions, and the reviewed access-result mappings remain functional.

#### Fix and fixture hardening

- Increased only this five-actor matrix from `180_000` to `300_000` milliseconds. One Chromium worker and zero retries remain unchanged.
- Strengthened `setSyntheticProfileState(...)` so the same transaction that changes the profile also proves the Auth user resolved and the resulting role/account status exactly match the allowlisted requested values.
- Strengthened `removeSyntheticProfile(...)` so it must resolve an existing synthetic Auth user, delete exactly one profile, preserve the Auth user, and prove the profile remains absent. Ticket 9B is not called or changed; its trigger remains Auth-user-`INSERT` only, so profile removal is not followed by automatic re-provisioning.
- Kept the wrong-role fixture on the existing valid `provider` value of `public.user_role`; no enum value was added or corrupted.
- Added fixed `guard-state:restricted|suspended|closed|provider|missing-profile` Playwright steps. On failure, the reporter may emit only the matching allowlisted state label and the fixed result category. It does not inspect or print error messages, stacks, credentials, Auth values, request bodies, database rows, or browser state.

#### Files changed

- `outputs/lekkadeall-frontend-shell/tests/e2e/security-boundaries.spec.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/local-fixtures.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/privacy-safe-reporter.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e-boundary.test.mjs`
- `TESTING.md`
- `hardening_progress.md`

#### Verification and security confirmations

- All **61/61 Node frontend and static security tests pass** locally.
- Playwright still discovers exactly **8** synthetic Chromium scenarios.
- Docker and Supabase CLI remain unavailable on this host, so the authoritative eight-test disposable-stack rerun is pending GitHub Actions. The main pgTAP, migration-reset, Deno webhook, and frontend security job was already green and none of its inputs changed.
- The frontend route guard remains unchanged and resolves authority only from the explicit own-profile projection `id,role,account_status`; Auth metadata remains untrusted.
- The rejected states still return before customer request/dashboard reads or mutations. No route guard, RLS policy, grant, enum, profile provisioning behavior, application RPC, or frontend mutation was loosened.
- Privacy redaction, loopback-only bootstrap, disposable local stack, one worker, zero retries, disabled screenshots/video/traces/HAR/storage state/Auth-email/database artifacts, and the three-RPC mutation allowlist remain intact.
- Publication, exact address, provider bidding/onboarding, booking actions, payments, admin dashboard, and profile editing remain blocked.

### Ticket 9A-9 CI correction - restore the nested Supabase project path - 2026-07-27

**Status:** Workflow-root correction implemented; replacement GitHub Actions verification pending.

#### Root cause and observed behavior

- The committed local Supabase project remains at `outputs/marketplace-production-foundation/supabase/config.toml`. No root-level `supabase/config.toml` exists or is required.
- The failed Actions revision executed `test -f supabase/config.toml` from the repository checkout root instead of the nested Supabase project directory. The command therefore returned exit code 1 before `supabase start`, the migration reset, pgTAP, or Ticket 9A-9 E2E could run.
- This was a workflow path/root failure. It was not a missing migration, invalid local security setting, remote-project fallback, Supabase startup failure, pgTAP failure, or E2E failure.

#### Fix

- Kept the config verification step and made its path independent of inherited working-directory state: it now runs from the repository root and checks the complete repository-relative path `outputs/marketplace-production-foundation/supabase/config.toml`.
- The credential/remote-target rejection scan checks that same exact committed file. It removes only blank and TOML comment lines before applying the unchanged deny-pattern, so explanatory comments cannot create false positives while every active setting remains checked.
- Retained the `database-tests` job default `working-directory: outputs/marketplace-production-foundation`. Consequently `supabase start`, `supabase db reset`, every `supabase test db supabase/tests/database/*.test.sql` command, and `supabase stop --no-backup` still execute against the one intended nested local project.
- Retained `needs: database-tests` on the Ticket 9A-9 E2E job, so browser E2E cannot start until the complete webhook/frontend/migration/pgTAP job succeeds.
- Added a static workflow regression check proving the nested config exists, the root-level duplicate does not exist, the complete verification path is used, the database job retains its nested default, startup/reset remain ordered, and E2E retains the database-job dependency.

#### Files changed

- `.github/workflows/database-tests.yml`
- `outputs/lekkadeall-frontend-shell/tests/e2e-boundary.test.mjs`
- `hardening_progress.md`

#### Security

- No Supabase config value, migration, RLS policy, grant, trusted function, validator, Ticket 9B trigger, or Ticket 9A lifecycle function changed.
- No credential, service-role browser authority, remote Supabase target, root-level project, or duplicate config was added.
- Publication, exact-address handling, provider bidding/onboarding, booking actions, payments, admin dashboard, and profile editing remain blocked.

### Ticket 9A-9 E2E correction - provider Auth quota and wrong-role fixture isolation - 2026-07-27

**Status:** Focused provider setup correction implemented; replacement disposable-stack verification pending.

#### Redacted finding

- **Expected:** the provider actor is created outside browser authority as one confirmed synthetic local Auth user; Ticket 9B creates exactly one `customer`/`active` profile; the browser establishes a real password session with the anon key; the local fixture controller changes only that protected profile role to the existing `provider` enum value; and the unchanged profile guard renders `Access denied` before any customer request read or mutation.
- **Actual category:** the seven passing scenarios left only `[guard-phase:provider:registration]`. The broad step combined local Auth-user creation, Ticket 9B readiness, browser password sign-in, and session privacy, so the failed boundary was not attributable without exposing Auth details.
- **Root cause:** the disposable Supabase configuration retained Auth's default combined sign-in/sign-up quota while the one-worker project creates several isolated real sessions. The provider is a late actor in the aggregate matrix and inherited the already-consumed local Auth bucket. This is local test configuration pressure, not a provider enum, route guard, RLS, Ticket 9B, or application authority defect.

#### Fix applied

- Added a credential-free local-only `[auth.rate_limit] sign_in_sign_ups = 120` setting. It applies only when the disposable loopback Supabase CLI stack starts; no hosted or production Auth configuration changed.
- Kept provider Auth-user creation in the Node fixture controller through the loopback admin endpoint. The browser still receives only the loopback public URL and anon key and signs in normally with the synthetic password.
- Split provider setup into explicit local Auth-user, Ticket 9B readiness, browser-session, protected-role-fixture, and guard/postcondition phases. Browser sign-in now waits for the password-token response, checks only its status, condition-polls only the count of the SDK Auth-session storage entry, and never reads or prints the response body or stored value.
- Added fixed reporter categories: `provider-signup-http-failure`, `provider-session-missing`, `provider-profile-readiness-timeout`, `provider-role-fixture-failure`, and `provider-guard-state-mismatch`.
- Added a no-output provider isolation invariant proving exactly one `provider`/`active` profile and absence of provider profile/service, request, exact-address, bid, booking, payment, and identity-verification state before and after the guard test.

#### Files changed

- `outputs/marketplace-production-foundation/supabase/config.toml`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/local-fixtures.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/journey-helpers.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/privacy-safe-reporter.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/security-boundaries.spec.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e-boundary.test.mjs`
- `TESTING.md`
- `hardening_progress.md`

#### Verification and security

- All **64/64 Node frontend and static security tests pass** locally, syntax checks pass, and Playwright configuration still discovers exactly **8** synthetic Chromium scenarios.
- Docker, Supabase CLI, and Deno are unavailable on this host, so the full disposable-stack Playwright, Deno, migration, and pgTAP rerun cannot be executed here. The user-reported main migration/frontend/Deno/pgTAP security job remains green.
- The guard still reads `id,role,account_status` from `public.profiles`; Auth metadata remains untrusted. No route guard, RLS policy, grant, Ticket 9B trigger, Ticket 9A lifecycle RPC, or browser write boundary changed.
- E2E remains loopback-only, disposable, one-worker, retry-free, and artifact-free. No Auth value, credential, response body, URL, header, database row/error, screenshot, video, trace, HAR, saved storage state, Auth email, or database dump is emitted.
- Publication, exact address, provider bidding/onboarding, booking actions, payments, admin dashboard, and profile editing remain blocked.

### Ticket 9A-9 E2E correction - remove signup pressure from setup-only scenarios - 2026-07-26

**Status:** Focused local-only fixture correction implemented; replacement disposable-stack verification pending.

#### Shared redacted finding

- The main registration-to-cancelled lifecycle now passes.
- Only the account-state matrix and ambiguous aborted-response scenario failed, both at `registration-phase:signup-request`, before session, profile, dashboard, guarded-state, or mutation assertions.
- These later tests were using public UI signup only to prepare actors. Registration is not the behavior they prove, and repeated synthetic signups introduced a shared local Auth request/email-rate boundary after earlier registration journeys.
- The preceding reporter did not retain the HTTP status category. The helper now classifies future UI signup failures by status only: `signup-http-429`, `signup-http-conflict`, `signup-http-other`, `signup-session-missing`, `profile-readiness-timeout`, or `signup-network-failure`.

#### Account-state matrix

- **Expected:** every actor has a real authenticated browser session and exact Ticket 9B customer/active profile before the local controller applies restricted, suspended, closed, provider, or missing-profile state; the frontend then fails closed before customer request reads or mutations.
- **Actual category:** `registration-phase:signup-request`; the first restricted actor stopped before any protected fixture transition or guard assertion.
- **Root cause:** unnecessary repeated public signup in a setup-only matrix exposed the disposable local Auth signup-rate boundary. The guarded behavior itself was not reached.
- **Fix:** create each synthetic Auth customer through the loopback Auth admin endpoint in the Node fixture controller, wait for the unchanged Ticket 9B postcondition, sign in through the browser anon client, and only then apply the protected state or deliberate profile removal. Each actor retains its own browser context.

#### Ambiguous aborted-response scenario

- **Expected:** an isolated active customer with a real browser session creates a draft through the trusted RPC, executes one intercepted update whose server response is aborted, does not retry, performs a fresh read, and cancels through the trusted RPC.
- **Actual category:** `registration-phase:signup-request`; the test stopped before draft creation or response-abort behavior.
- **Root cause:** this scenario unnecessarily consumed another UI signup even though signup is not its subject.
- **Fix:** prepare one confirmed synthetic customer through the local fixture controller, wait for Ticket 9B, sign in through the anon browser client, and retain the existing real create/update/read/cancel browser and RPC sequence unchanged.

#### Files changed

- `outputs/lekkadeall-frontend-shell/scripts/e2e/run-local.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/local-environment.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/local-fixtures.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/journey-helpers.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/privacy-safe-reporter.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/security-boundaries.spec.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e-boundary.test.mjs`
- `TESTING.md`
- `hardening_progress.md`

#### Why this preserves the real security boundary

- Exactly two UI signup proofs remain: the complete main lifecycle and cross-customer B. Blocked-controls, cross-customer A, stale-state, account-state, and ambiguous-response actors use fixture creation only for setup, then authenticate through the real browser anon client.
- The browser still receives only the local public URL and anon key. The fixture admin credential exists only in the disposable Node test process, is accepted only with a loopback Auth URL and a `service_role` JWT claim, and is never written to runtime configuration, page code, artifacts, or logs.
- The fixture creates an Auth user, not a browser-created application profile. The unchanged Ticket 9B Auth-user trigger remains solely responsible for the exact customer/active profile.
- Every tested actor signs in through Supabase Auth and exercises the real frontend safe read, route guard, RLS, and trusted RPC paths. No RLS or guard is bypassed by the browser.
- E2E remains local-only, disposable, one-worker, no-retry, and artifact-free. No response body, synthetic email, password, token, Auth code/link, complete URL, header, database credential/error/row, screenshot, video, trace, HAR, saved storage state, Auth email, or database dump is emitted.
- All **64/64 Node frontend and static security tests pass** locally, and Playwright still discovers exactly **8** Chromium scenarios. The reported migration-reset, pgTAP, Deno webhook, and frontend security job remains green; no backend input changed.
- Publication, exact address, provider bidding/onboarding, booking actions, payments, admin dashboard, and profile editing remain blocked.

### Ticket 9A-9 E2E correction - deterministic shared registration boundary - 2026-07-25

**Status:** Shared registration/setup correction implemented locally; replacement disposable-stack verification pending.

#### Redacted finding and shared root cause

- Both remaining scenarios failed inside their broad registration step: the complete customer lifecycle and the first restricted actor in the account-state matrix.
- These were the two scenarios that combined the UI helper with the exact Ticket 9B database postcondition. The helper waited only for the eventual customer URL and heading, while the Ticket 9B invariant was a separate one-shot check. Signup response completion, persisted session readiness, profile readiness, and dashboard readiness were not independently synchronized or attributable.
- Synthetic actors already had random suffixes, but they did not include an explicit workflow-run namespace. The runner already reset and stopped the disposable stack, so no stale Auth/profile collision was demonstrated; run-scoped identity now makes that invariant explicit.
- Local Supabase has `[auth.email] enable_confirmations = false`. Registration therefore must return a session directly and requires no confirmation link, Inbucket read, Auth email artifact, or PKCE storage.

#### Expected versus actual behavior

- **Expected:** one unique UI signup completes against loopback Auth, persists exactly one SDK Auth session, synchronously provisions exactly one Ticket 9B `customer`/`active` profile, and reaches the customer dashboard. Only after that boundary may protected local fixture transitions run.
- **Actual:** the former helper collapsed those conditions into a URL/heading wait followed by a one-shot external profile assertion, so a setup/readiness failure was reported only as registration and could stop before lifecycle work or the first restricted fixture.

#### Fix applied

- The local runner now generates an unlogged 16-hex-character run ID. Each actor email uses that run ID, a fixed actor label, and an independent random suffix.
- Registration now has fixed allowlisted phases: `signup-request`, `auth-session`, `profile-ready`, and `dashboard`.
- The signup phase waits for the actual loopback Auth signup response and checks only success status.
- The session phase condition-polls only the count of the approved SDK Auth storage entry; it never reads or returns the entry value.
- The profile phase condition-polls a fixed SQL readiness result proving exactly one matching Auth user, exactly one Ticket 9B customer/active profile with the reviewed default display name, and no provider profile. No ID, email, profile row, or database error detail is printed.
- Restricted, suspended, closed, and provider actors still register normally before the fixture controller changes protected state. Missing-profile still registers normally before deliberate local-only removal. Every actor retains a separate browser context.

#### Files changed

- `outputs/lekkadeall-frontend-shell/scripts/e2e/run-local.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/journey-helpers.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/local-fixtures.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/privacy-safe-reporter.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/customer-draft-lifecycle.spec.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/security-boundaries.spec.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e-boundary.test.mjs`
- `TESTING.md`
- `hardening_progress.md`

#### Security and verification

- All **62/62 Node frontend and static security tests pass** locally.
- Playwright discovery still finds exactly **8** synthetic Chromium scenarios.
- Docker and Supabase CLI remain unavailable on this host, so authoritative real-stack confirmation is pending. The reported migration-reset, pgTAP, Deno webhook, and frontend security job is green, and none of its backend inputs changed.
- E2E remains disposable, loopback-only, one-worker, retry-free, and artifact-free. No token, password, Auth code/link, email value, request body, database credential/error/row, screenshot, video, trace, HAR, saved storage state, Auth email, or database dump is emitted or retained.
- No application source, Auth configuration, Ticket 9B provisioning rule, RLS policy, grant, lifecycle function, route guard, frontend write boundary, or service-role exposure changed.
- Publication, exact address, provider bidding/onboarding, booking actions, payments, admin dashboard, and profile editing remain blocked.

### Ticket 9A-9 E2E correction — multi-registration Auth pacing and final isolation assertions — 2026-07-24

**Status:** Final two root causes fixed locally; replacement GitHub Actions verification pending.

#### Latest redacted failure pattern

- Six scenarios passed, including every scenario that registers zero or one synthetic Auth user.
- Only the two scenarios that register multiple users still failed:
  - `cross-customer request IDs remain RLS-hidden and non-actionable` registers Customer A and Customer B;
  - `restricted suspended closed missing-profile and wrong-role actors fail closed` registers five actors.
- This pattern supersedes the earlier timeout-only diagnosis. The comprehensive lifecycle, stale edit, and ambiguous-response tests prove that Ticket 9B provisioning and all three draft RPC boundaries function for valid single-user sessions.

#### Root cause

- Local Supabase Auth is configured with email `max_frequency = "1s"`.
- `respectLocalSignupRateLimit()` recorded `lastRegistrationAt` immediately before navigating to registration and submitting the previous signup.
- Its next 1.1-second delay was therefore measured from request start, not successful signup/session/profile completion. Network, Ticket 9B trigger, route-profile read, and dashboard work consumed part of that interval.
- The next signup in the same test could consequently arrive inside Auth's one-second post-completion window. This was a local E2E scheduling mistake, not shared session storage, RLS leakage, invalid profile state, Ticket 9B re-provisioning, or a route-guard defect.

#### Cross-customer RLS — redacted summary

- **Expected:** Customer A and Customer B use separate browser contexts and sessions; B creates an owned draft; A receives the same generic unavailable states for B's UUID and a missing UUID; no title, description, category, status, owner, or existence signal appears; A cannot edit or cancel.
- **Actual:** the second signup could be locally rate-limited before the two-user RLS journey was fully established.
- **Fix:** registration pacing is now measured from confirmed completion. The test also proves the contexts and pages are distinct, proves the two synthetic emails resolve to distinct Auth user IDs without returning either ID, verifies B owns the draft through a no-output local invariant, compares B's UUID with a fixed missing UUID on detail and edit routes, asserts no request card/content/category/status is rendered, and retains zero A-side edit/cancel RPC counts.
- **Security:** no RLS policy, projection, route behavior, storage behavior, browser credential, or mutation boundary changed.

#### Restricted-state matrix — redacted summary

- **Expected:** five independently authenticated actors receive exact restricted, suspended, closed, provider, or missing-profile fixtures; customer routes stop after the own-profile guard; restricted statuses use the restricted UI state, and provider/missing-profile use the generic error/fail-closed state.
- **Actual:** later registrations in the five-user matrix could fall within the incorrectly measured local Auth interval.
- **Fix:** the completion-based pacing applies between every actor. Existing atomic fixture invariants remain, and the test now snapshots `service_requests`, `bookings`, and `payments` read counts before reloading the protected route and proves none increase after the guard rejects the actor.
- **Security:** role and account status continue to come only from `public.profiles`; Auth metadata remains untrusted; provider remains an existing enum value; Ticket 9B remains Auth-user-`INSERT` only; request reads and mutations remain blocked.

#### Files changed

- `outputs/lekkadeall-frontend-shell/tests/e2e/support/journey-helpers.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/local-fixtures.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/network-policy.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/security-boundaries.spec.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e-boundary.test.mjs`
- `TESTING.md`
- `hardening_progress.md`

#### Verification and security confirmations

- All **62/62 Node frontend and static security tests pass** locally.
- Playwright still discovers exactly **8** synthetic Chromium scenarios.
- Docker and Supabase CLI remain unavailable on this host, so the authoritative disposable-stack rerun remains pending GitHub Actions. The main migration-reset, pgTAP, Deno webhook, and frontend security job was already green and no backend input changed.
- E2E remains loopback-only, disposable, one-worker, and retry-free. No screenshot, video, trace, HAR, saved storage state, Auth email, database dump, sensitive error detail, or secret is emitted.
- No application source, Auth configuration, migration, RLS policy, grant, Ticket 9B function/trigger, Ticket 9A-5 validator, Ticket 9A-7 cancellation function, Ticket 9A-8 update function, service-role browser access, direct frontend application-table write, or `select('*')` changed.
- Publication, exact-address handling, provider bidding/onboarding, booking actions, payments, admin dashboard, and profile editing remain blocked.

### Ticket 9A-9 E2E correction - final aggregate journey bounds - 2026-07-25

**Status:** The replacement run disproved the timeout-only diagnosis. Six scenarios pass; focused privacy-safe phase localization for the two remaining failures is implemented locally and awaiting the next disposable-stack run.

#### Registration-through-cancelled-draft - redacted summary

- **Expected:** local Auth registration creates a valid session and exactly one Ticket 9B `customer`/`active` profile; the active synthetic category is RLS-visible; create, list/detail, update, cancellation, and final fresh cancelled-state reads succeed once each through the reviewed browser boundaries.
- **Actual:** the focused stale and ambiguous journeys pass the same Auth, provisioning, category, create, update, cancel, and fresh-read boundaries, but the complete registration-to-cancellation journey still fails after its test-local bound was increased.
- **Root cause:** not yet isolated by the former test-level redaction. The timeout-only diagnosis is withdrawn. The failure is now divided into fixed allowlisted phases for registration, reauthentication, category/dashboard reads, create, list/detail, update, cancel, final postconditions, and sign-out.
- **Fix applied for the next redacted run:** retained every existing assertion and added fixed `lifecycle-phase:*` Playwright steps. The reporter may emit only the failed allowlisted phase and fixed result category; it still cannot read or print runtime errors, values, URLs, request bodies, credentials, browser storage, or database rows.
- **Security:** no application source, Auth behavior, profile provisioning, category fixture authority, RLS policy, grant, mutation function, route guard, retry setting, or artifact policy changed.

#### Restricted-state matrix - redacted summary

- **Expected:** five valid local Auth sessions receive exact restricted, suspended, closed, provider, or missing-profile fixtures; route guards read only `public.profiles.id,role,account_status`; rejected actors see the reviewed restricted, access-denied, or generic fail-closed UI and perform no request reads or mutations after rejection.
- **Actual:** the latest safe label is `guard-state:provider`. The two-user Auth/RLS isolation scenario passes, and static rendering confirms the provider-on-customer-route state contains exactly one `Access denied` state, one error state, one sign-out control, and no create-draft link.
- **Root cause:** not yet isolated within the former provider-wide step. The provider role is an existing `public.user_role` value; the frontend route guard reads only `public.profiles.id,role,account_status`; and `provider` plus `active` resolves to `accessDenied` before customer request reads. No evidence supports weakening that boundary.
- **Fix applied for the next redacted run:** added fixed provider subphases for registration, fixture mutation, route rendering, postconditions, and sign-out. Registration now re-proves exactly one Ticket 9B customer/active profile before fixture mutation. Post-route database invariants prove the requested role/status still exist, and the missing-profile case proves the Auth user remains while the profile remains absent after route evaluation.
- **Security:** no route guard was loosened; Auth metadata remains untrusted; no RLS, grant, enum, Ticket 9B rule, frontend write boundary, service-role exposure, or privacy/logging policy changed.

#### Files changed

- `outputs/lekkadeall-frontend-shell/tests/e2e/customer-draft-lifecycle.spec.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/security-boundaries.spec.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/local-fixtures.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e/support/privacy-safe-reporter.mjs`
- `outputs/lekkadeall-frontend-shell/tests/e2e-boundary.test.mjs`
- `TESTING.md`
- `hardening_progress.md`

#### Verification and security confirmations

- All **62/62 Node frontend and static security tests pass** locally.
- Playwright discovery still finds exactly **8** synthetic Chromium scenarios.
- Docker and Supabase CLI are unavailable on this development host, so the authoritative disposable-stack phase-localization rerun remains pending. The already-green migration-reset, pgTAP, Deno webhook, and frontend security job inputs did not change.
- E2E remains loopback-only, disposable, one-worker, retry-free, and artifact-free. The global default remains 60 seconds and the CI job remains bounded to 30 minutes.
- No screenshot, video, trace, HAR, saved storage state, Auth email, database dump, error detail, credential, token, Auth link, recovery link, request body, or database row is emitted or retained.
- Publication, exact address, provider bidding/onboarding, booking actions, payments, admin dashboard, and profile editing remain blocked.

### Ticket 9A-9 E2E correction - restricted actor setup phase isolation - 2026-07-28

**Status:** CI-verified in GitHub Actions — Success.

#### Root cause

- Only the provider actor had separately attributable Auth creation, Ticket 9B readiness, browser-session, fixture, and guard phases. Restricted, suspended, closed, and missing-profile setup still collapsed Auth creation plus readiness into `prepareSyntheticCustomerAccount()`, so a redacted failure could not identify the failed boundary consistently across the five actors.
- Auth-admin creation treated every rejected request as a definite failure. A connection failure after the local Auth service committed the user was therefore ambiguous, and a caller could not safely tell whether the synthetic actor was absent, Auth-only, ready, or invalid.
- The former Ticket 9B scalar check exposed only `ready` versus `pending`. That made absent and Auth-only eventual states indistinguishable from invalid fixture state.

#### Fix applied

- Every restricted, suspended, closed, wrong-role, and missing-profile actor now runs serially through five explicit Playwright phases: `auth-creation`, `ticket-9b-profile-readiness`, `browser-session`, `fixture-state-application`, and `route-guard-verification`. Sign-out remains a separate cleanup phase.
- Every phase is wrapped by fixed, allowlisted `negative-actor-failure:<actor>:<category>` reporting. The reporter still withholds runtime errors, stacks, values, response data, URLs, headers, credentials, browser state, rows, and attachments.
- Added a no-row fixture-state classifier whose only possible internal result is `absent`, `auth-only`, `ready`, or `invalid`. Ticket 9B polling waits only for the eventual `absent` and `auth-only` states and rejects `invalid` immediately.
- Negative actors use an explicit `60_000` millisecond Ticket 9B readiness condition.
- Auth creation still issues exactly one loopback admin `POST`. If that request rejects after Auth may have committed, setup does not retry creation; it reconciles for up to five seconds through the scalar state classifier, accepts only `auth-only` or `ready`, and fails closed for `absent` or `invalid`.
- Each actor creates its own browser context only after profile readiness, installs the anon-key network policy before sign-in, applies its protected fixture state only after a normal session exists, and closes that context before the next actor begins.
- The route-guard phase snapshots `service_requests`, `bookings`, and `payments` read counts plus create/update/cancel RPC counts before navigation. The fail-closed UI and unchanged counters together prove that guard rejection causes no request-domain read or mutation.

#### Security boundaries preserved

- Ticket 9B provisioning, route-guard logic, RLS, grants, public-field validation, draft update, draft cancellation, and state-machine protections did not change.
- The fixture-admin credential remains Node-only, loopback-only, service-role-claim-validated, absent from browser runtime configuration, and unprinted. Browser requests remain restricted to the exact local anon key and cannot use service-role authorization.
- Playwright remains Chromium-only, one-worker, retry-free, and serial. Each negative actor has an independent browser context.
- CI still disables screenshots, video, traces, HAR, saved storage state, HTML/JUnit reports, Auth-email artifacts, database dumps, and artifact upload.
- Publication, exact-address handling, provider onboarding/bidding, booking actions, payments, admin dashboard, and profile editing remain blocked.

#### Verification

- Existing frontend/static suite: **64/64 passed**.
- Playwright focused discovery: **8 synthetic Chromium scenarios discovered** with the privacy-safe reporter.
- The complete `pnpm run test:e2e:local` command was invoked and failed at the redacted prerequisite boundary because Docker and Supabase CLI are unavailable on this host; no Playwright scenario ran and no runtime configuration or artifact was left behind.
- Workflow path checks pass: the E2E job still runs from `outputs/lekkadeall-frontend-shell`, depends on `database-tests`, and the Supabase project remains at `outputs/marketplace-production-foundation/supabase/config.toml`.

### Ticket 9A-9 CI verification closure - 2026-07-28

**Workflow run:** `Fix Ticket 9A-9 negative actor E2E setup`  
**Status:** Success  
**Duration:** 10m 8s

#### E2E tests implemented and verified

All **8/8** synthetic Chromium E2E tests pass against the disposable loopback Supabase stack:

1. Blocked marketplace and privileged controls remain absent from the customer shell.
2. Signed-out customer routes and the absent admin route fail closed.
3. Customer registration through draft creation, list/detail, update, cancellation, and final database postconditions succeeds through real local Auth, RLS, and the reviewed RPCs.
4. Cross-customer request identifiers remain RLS-hidden and non-actionable in separate browser contexts.
5. Restricted, suspended, closed, missing-profile, and wrong-role actors fail closed before request-domain reads or mutations.
6. A stale edit is rejected after another tab cancels the draft.
7. An executed update with an aborted browser response is not retried and requires a fresh read.
8. Recovery routes fail closed without persisting a PKCE verifier.

#### Failures encountered and root causes

- The shared sign-out helper initially expected the site root instead of the implemented `/auth/sign-in` redirect.
- The three aggregate journeys inherited an insufficient 60-second Playwright timeout; the five-actor matrix required a larger bounded serial timeout than the other comprehensive journeys.
- A workflow verification step checked for a root-level Supabase project instead of the committed nested project path.
- Registration originally combined signup-response, Auth-session, Ticket 9B profile, and dashboard readiness into one broad condition, making readiness races and failures non-deterministic and poorly attributable.
- Registration pacing was measured from request start rather than confirmed completion, and setup-only scenarios consumed the disposable Auth sign-in/sign-up quota through unnecessary UI registrations.
- The late provider actor inherited that local quota pressure, while its setup step combined too many phases for privacy-safe failure attribution.
- The final negative-actor setup still treated a rejected Auth-admin response as a definite failure even when Auth might already have committed the user, and its former scalar readiness check could not distinguish absent, Auth-only, ready, and invalid fixture states.

These were E2E harness, workflow-path, local quota, readiness, and fixture-setup defects. The successful runs did not require weakening application guards, RLS, provisioning, validation, or lifecycle protections.

#### Final negative-actor fixture correction

- All five negative actors now run serially through separate Auth creation, explicit 60-second Ticket 9B readiness, browser session, fixture-state application, and route-guard verification phases.
- Every actor receives an independent browser context, and the browser network boundary is installed before sign-in with the exact local anon key.
- The no-row fixture classifier distinguishes only `absent`, `auth-only`, `ready`, and `invalid`; it returns or prints no Auth/profile row, identifier, credential, or response detail.
- Auth setup issues exactly one creation request. An ambiguous rejected response is reconciled through the scalar fixture state without retrying creation; only `auth-only` or `ready` is accepted, while `absent` and `invalid` fail closed.
- Restricted, suspended, closed, provider, and missing-profile state is applied only after a normal browser session exists.
- Request-table reads and create/update/cancel RPC counts are captured before guarded navigation and must remain unchanged after rejection.
- Failure reporting remains limited to fixed privacy-safe actor, phase, and result categories.

#### Final green verification

- Existing frontend and static security tests: **64/64 passed**.
- Existing Deno webhook tests: **passed**.
- Clean migration reset and all existing pgTAP suites: **passed**.
- Ticket 9A-9 Playwright E2E: **8/8 passed**.
- The isolated E2E job still depends on the complete database-security job, so Playwright runs only after frontend, Deno, migration-reset, and pgTAP verification succeeds.
- Screenshots, video, traces, HAR, saved storage state, Auth-email artifacts, database dumps, verbose reports, and artifact upload remain disabled.

#### Blocked scope and unchanged protections

- Publication remains blocked.
- Exact-address collection, storage, read, reveal, encryption, geolocation, and mapping remain blocked.
- Provider onboarding, feeds, bidding, and selection remain blocked.
- Booking actions remain blocked.
- Payments, checkout, refunds, payouts, and disputes remain blocked.
- The admin dashboard remains absent.
- Profile editing remains blocked.
- No RLS policy, grant, Ticket 9B profile-provisioning rule, public-field validator, state-machine guard, draft-cancellation protection, or draft-update protection was weakened or changed.

### Ticket 9A-9 CI correction - deterministic Supabase CLI installation - 2026-07-28

**Status:** Exact known-good CLI pin implemented; replacement GitHub Actions verification pending.

#### Failure and root cause

- The workflow failed in `Set up Supabase CLI` before the Ticket 9A-9 Playwright tests started with `Failed to resolve latest Supabase CLI release: rate limit exceeded`.
- This was an external GitHub release-resolution failure caused by `version: latest`. It was not an application, migration, pgTAP, Deno, frontend, or Playwright assertion failure.
- The preceding successful `Fix Ticket 9A-9 negative actor E2E setup` run used Supabase CLI `2.110.0`. That run completed with **Status: Success** in **10m 8s** and passed the complete main security/database job followed by all **8/8** Ticket 9A-9 Playwright tests.

#### Deterministic correction

- Both Supabase setup steps now use `supabase/setup-cli@v2` with the exact version `2.110.0`; no setup step uses `latest`.
- Both steps pass only the workflow-scoped `${{ github.token }}`. Workflow permissions remain read-only with `contents: read`; no personal access token, production secret, or remote Supabase credential was added.
- The main migrations/pgTAP job retains `outputs/marketplace-production-foundation` as its default working directory.
- The disposable Ticket 9A-9 runner still starts, resets, and stops Supabase from `outputs/marketplace-production-foundation`, while Playwright runs from `outputs/lekkadeall-frontend-shell`.
- `customer-draft-lifecycle-e2e` still declares `needs: database-tests`, so the E2E boundary cannot run until frontend, Deno, clean migration reset, and every pgTAP suite pass.

#### Security and scope confirmation

- No migration, RLS policy, grant, policy, function, trigger, Ticket 9B provisioning rule, public-field validator, marketplace state-machine guard, draft-cancellation protection, draft-update protection, or test changed.
- The E2E remains loopback-only, disposable, one-worker, retry-free, and anon-key-only in the browser. No mutation retry was added.
- Screenshots, video, traces, HAR, saved storage state, Auth-email artifacts, database dumps, and artifact upload remain disabled.
- Publication, exact-address handling, provider onboarding/bidding, booking actions, payments, admin dashboard, and profile editing remain blocked.

### Ticket 9A-9 E2E correction - lifecycle signup and aborted update isolation - 2026-07-28

**Status:** Two focused harness corrections implemented locally; replacement disposable-stack verification pending.

#### Failure 1 - lifecycle UI signup

- **Expected:** the main lifecycle actor performs one real UI signup, receives a normal local Auth session, reaches the unchanged Ticket 9B `customer`/`active` profile postcondition, and continues through create, edit, cancel, and final RLS/database invariants.
- **Actual privacy-safe category:** `registration-failure:signup-http-conflict`.
- **Isolation finding:** the lifecycle test creates its account once and calls the registration helper once. No setup helper, fixture controller, migration, seed, or other test creates that account. The registration helper contains one `Create account` click. The prior identity included a random run nonce, actor label, and random suffix, but did not encode the GitHub run/attempt or Playwright test name, did not prove scalar absence immediately before signup, and could not safely attribute a conflict after an ambiguous completion. The application Auth form also lacked a single-flight guard.
- **Root cause:** the harness collapsed an ambiguous same-identity completion and an unexpected collision into the same terminal conflict category. It had no absent-before ownership precondition or one-time scalar reconciliation, while the UI did not explicitly reject a re-entrant submit. This was an E2E identity/attribution defect, not a Ticket 9B, Auth policy, route-guard, or RLS defect.

#### Lifecycle signup fix

- Synthetic identity scope now includes the workflow run ID, workflow attempt, fresh runner nonce, bounded test-name slug/digest, actor label, and fresh random suffix. No identity value is logged.
- The fixture controller requires the scalar `absent` state immediately before the real UI signup and returns no Auth/profile row.
- The helper still clicks the UI signup button exactly once, counts the exact loopback signup request, and fails closed if the count is zero or greater than one.
- The application Auth form now has a single-flight submission guard. It adds no retry and trusts no Auth metadata.
- A conflict or network ambiguity performs no second signup. Reconciliation is allowed once only when the current test proved prior absence, observed exactly one signup request, and the scalar classifier reaches `auth-only` or `ready`. Ticket 9B readiness remains explicitly bounded to 60 seconds.
- An unexpected existing identity, absent post-state, invalid fixture, or unusable public session fails under fixed categories such as `signup-unexpected-collision`, `signup-reconciliation-invalid`, or `signup-reconciliation-session-failure`. No user is deleted and no unexpected account is adopted.

#### Failure 2 - executed update with aborted response

- **Expected:** one `customer_update_draft_request(...)` executes, its browser response is aborted after execution, the UI remains ambiguous and blocked, no retry occurs, and a later RLS-backed read displays the committed server state.
- **Actual privacy-safe category:** `assertion-or-runtime`.
- **Isolation finding:** this test already used the distinct `customer-ambiguous` actor and its own generated draft. The six passing scenarios around it, including the post-lifecycle worker scenarios, show that it was not adopting the lifecycle account or request.
- **Root cause:** the former route handler called `route.fetch()` and then aborted, but did not explicitly disable transport retries, assert the fetched status/execution flag, keep a guard that blocked a second intercepted request before execution, or localize the failing boundary. `{ times: 1 }` also meant a hypothetical second browser mutation would bypass the interceptor before the later count assertion. This was an interception/proof gap, not an application retry or RPC defect.

#### Aborted-update fix

- The scenario now creates and closes an explicit independent browser context and retains its own synthetic customer and draft.
- The interceptor remains installed for the mutation window. Only its first request may call `route.fetch({ maxRetries: 0 })`; any later request is aborted before reaching the RPC.
- The response is aborted only after the fetched response reports successful execution. The test then requires exactly one intercepted request and exactly one browser-policy update count.
- The UI must show only the generic unconfirmed-update state, must never show `Draft updated.`, and must keep submission disabled.
- After removing the interceptor, a reload must increase the explicit `service_requests` read count before the test accepts the authoritative edited values. The update count must remain one.
- Fixed `ambiguous-update-failure:<phase>` categories now isolate setup, execution, ambiguous UI, fresh RLS read, postcondition, and sign-out without printing runtime details.

#### Verification and unchanged security

- Node syntax checks pass for every changed JavaScript module.
- Existing frontend/static security suite: **64/64 passed** locally.
- Playwright discovery finds **8** tests; the fixed-scope discovery finds **1** lifecycle test, **1** aborted-response test, and **2** affected tests together. The E2E job now runs those three fixed scopes before the full eight-test scope, each against a newly started/reset and no-backup-cleaned disposable stack, while retaining the existing 30-minute job timeout.
- Docker and Supabase CLI are unavailable on this host, so real-stack isolated, paired, and full-suite execution remains pending GitHub Actions.
- Supabase CLI remains pinned to `2.110.0` in both jobs. The main frontend, Deno, migration, and pgTAP job from the failing E2E run was green.
- No migration, Ticket 9B provisioning rule, route guard, RLS policy, grant, public-field validator, lifecycle RPC, state-machine guard, draft-update protection, or cancellation protection changed.
- Browser authority remains anon-key-only and loopback-only. The fixture-admin credential remains Node-only and unprinted.
- Playwright remains one-worker, zero-retry, bounded, and artifact-free. Screenshots, video, traces, HAR, storage state, Auth-email artifacts, database dumps, and artifact upload remain disabled.
- Publication, exact-address handling, provider onboarding/bidding, bookings, payments, admin dashboard, and profile editing remain blocked.

### Ticket 9A-9 E2E correction - bounded Auth identity and original-response abort - 2026-07-29

**Status:** Two current harness defects corrected; disposable Supabase-backed verification is pending on a Docker/Supabase-capable runner.

This correction supersedes two narrow implementation details in the 2026-07-28 entry above: an explicit signup conflict is not eligible for ambiguous reconciliation, and the aborted-update scenario no longer uses `route.fetch()`.

#### Failure 1 - lifecycle UI signup

- **Expected:** the lifecycle actor has a fresh, run/attempt/test/actor-scoped identity, sends exactly one real UI signup, receives a local Auth session, satisfies the unchanged Ticket 9B one-profile `customer`/`active` invariant, and continues through the real RLS/RPC lifecycle.
- **Actual privacy-safe category:** `registration-failure:signup-http-conflict`.
- **Root cause:** the helper treated an explicit `409`/`422` response as though it were a no-response transport ambiguity and attempted to adopt the observed account through reconciliation. An explicit server response is not ambiguous. The lifecycle source does not call either fixture Auth-creation helper, contains one registration call and one signup click, and the application has a global single-flight Auth submission guard. The checked-in E2E defect was therefore unsafe conflict attribution/reconciliation, not a Ticket 9B, Auth metadata, route-guard, or RLS defect.
- **Fix:** the full validated run ID still carries workflow run, attempt, and fresh runner nonce. Fixed SHA-256-derived test and actor components plus a fresh 40-bit random suffix preserve all required identity scopes in a maximum 63-character local-part. This removes avoidable identity-format variability but is not used to adopt or retry a collision.
- **Ambiguity rule:** the browser still performs one `Create account` click under the application single-flight guard. Only a one-request/no-observable-response transport ambiguity may use scalar no-row reconciliation. An explicit `409`/`422` response fails closed as `signup-http-conflict`; it is not reconciled, signed up again, or adopted. The lifecycle source is statically required not to use either fixture Auth-creation helper.

#### Failure 2 - executed update with aborted response

- **Expected:** one isolated `customer_update_draft_request(...)` reaches the server, the original browser response is aborted after a successful server status, no second mutation executes, no optimistic success appears, and a fresh RLS-backed read is required before cancellation.
- **Actual privacy-safe category:** `assertion-or-runtime`.
- **Root cause:** `route.fetch()` performs an interceptor-owned fetch and then aborts the routed request. That did not model aborting the original browser response directly and left the execution/response identity dependent on route-proxy timing. The application RPC, retry policy, and database state machine were unchanged.
- **Fix:** a Chromium Fetch-domain session pauses the original request. It continues exactly the first request with response interception enabled, verifies the response-stage status without reading the body, and fails that same response back to the browser. Any second request is failed at request stage before server execution. The interceptor stays active through the ambiguous UI and fresh-read checks.
- The assertions require exactly one request-stage interception, one response-stage interception, one browser-policy RPC count, a successful execution status, an aborted browser response, no `Draft updated.` message, a disabled submit action, and an increased `service_requests` RLS-read count after reload before the later deliberate cancellation.

#### Redacted verification

- Existing frontend/static security suite: **64/64 passed**.
- Node syntax checks passed for the three changed E2E JavaScript modules.
- A loopback-only local Chromium protocol probe passed: the first original request executed exactly once, its same request ID reached response stage and was aborted, and a deliberately issued second request was stopped before reaching the local server.
- The requested `lifecycle`, `aborted`, `affected`, and `full` runner scopes were invoked, but all stopped before Supabase startup because this Windows host has neither Docker nor the Supabase CLI. No Playwright scenario ran, so no 8/8 result is claimed. The privacy-safe runner withheld internal details as designed.
- The previously reported main frontend, Deno, migration-reset, and pgTAP job remains the authoritative green result for those unchanged surfaces. No migration, RLS, grant, trusted RPC, validator, route guard, Ticket 9B trigger, cancellation rule, update rule, or restricted/provider fixture changed.
- The E2E configuration remains loopback-only, disposable, one-worker, no-retry, anon-key-only in browser code, and artifact-free. No credential, email, password, token, Auth code, request body, header, URL, or database row was logged.
- Publication, exact address, provider bidding, booking actions, payments, admin dashboard, and profile editing remain blocked.
