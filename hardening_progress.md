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

### Implementation status

Implemented locally; awaiting GitHub Actions verification.

### Issue addressed

Ticket 8A adds trusted database-side processing for mock/sandbox payment webhook events after a future server route has already verified the webhook signature. It does not implement live webhook routes or real signature verification.

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

### Tests to rerun

From `outputs/marketplace-production-foundation`:

```powershell
supabase db reset
supabase test db supabase/tests/database/payment_webhooks.test.sql
```

Then rerun the full `Supabase database tests` GitHub Actions workflow.

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
