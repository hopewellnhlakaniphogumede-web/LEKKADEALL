# LEKKADEALL frontend — Ticket 9A-8

This static ES-module frontend connects the Ticket 9A-1 shell to Supabase Auth, narrowly scoped RLS-backed reads, customer draft creation, customer request list/detail reads, strict draft-only cancellation, and strict draft-only editing. It uses the pinned `@supabase/supabase-js` browser package with a public project URL and anon key only. Ticket 9A-8 adds no dependency or package-file change.

Role and account status are read from the signed-in user's RLS-protected `public.profiles` row. Auth metadata and callback/query parameters are never application authority. Registration sends only email, password, and the approved callback URL; Ticket 9B provisions the matching customer/active profile on the backend.

## Local configuration and preview

From the repository root:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
Copy-Item outputs/lekkadeall-frontend-shell/runtime-config.example.js outputs/lekkadeall-frontend-shell/runtime-config.local.js
```

Edit only the ignored `runtime-config.local.js` and replace these placeholders with the corresponding browser-safe project values:

- `PUBLIC_APP_ENV=development`
- `PUBLIC_APP_URL=http://localhost:4173`
- `PUBLIC_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co`
- `PUBLIC_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY`

Never place a service-role key or provider, webhook, identity, admin, payment, or database secret in frontend configuration.

Preview with this exact command from the repository root:

```powershell
python -m http.server 4173 --directory outputs/lekkadeall-frontend-shell
```

Open `http://localhost:4173/`. The Supabase Auth redirect allowlist must include `http://localhost:4173/auth/callback` and `http://localhost:4173/auth/reset-password` for the corresponding local flows.

Without `runtime-config.local.js`, public static pages remain visible while authentication and database reads fail closed with a configuration-required state.

## Customer request routes

- `/app/customer/requests/` — list of the active customer's RLS-visible requests.
- `/app/customer/requests/detail/?requestId=<uuid>` — static-shell-compatible detail route and the only location with draft cancellation.
- `/app/customer/requests/edit/?requestId=<uuid>` — draft-only edit route reached only from a freshly read owned draft detail.
- `/app/customer/requests/new/` — draft-only creation route.

The customer dashboard links to “View all requests.” After a valid draft UUID is returned, the confirmation page offers “View draft” and “View all requests.” Opening the detail route always performs a fresh RLS-backed read.

Only a session whose own protected profile says `role = 'customer'` and `account_status = 'active'` may use these routes. Signed-out, expired, missing-profile, restricted, suspended, closed, wrong-role, and unknown-role/status states fail closed.

## Safe request read boundary

List and detail use exactly this request projection:

```text
id,category_id,title,description,suburb,city,requested_start,budget_minor,status,created_at,updated_at
```

The list filters to `draft`, `open`, and `cancelled`, orders by `created_at` descending, and is limited to 20 rows. Ownership is supplied only by existing RLS; the browser neither selects nor filters on `customer_id`.

The detail route validates the UUID before querying `service_requests`, applies the same status allowlist, and uses `maybeSingle()`. Malformed, missing, cross-customer, unsupported-status, and RLS-hidden IDs share one generic “Request not found or unavailable” state.

Category labels come only from the active `service_categories` projection `id,slug,name`. An unavailable historical category displays “Category unavailable.” Database strings are HTML-escaped, dates are formatted explicitly in `Africa/Johannesburg` with a SAST label, and `budget_minor` is displayed only as ZAR with no payment instructions.

No request content is written to URLs, browser storage, service-worker caches, logs, analytics, telemetry, or error reports.

## Ticket 9A-7 strict draft cancellation

Migration `015_customer_draft_cancellation.sql` creates this trusted contract:

```text
public.customer_cancel_draft_request(p_request_id uuid)
returns public.request_status
```

The `SECURITY DEFINER` function derives identity only from `auth.uid()`, locks the actor's protected profile and owned request, and allows only an active customer to cancel an exact `draft`. It rejects missing/cross-customer/non-draft requests, inconsistent draft workflow timestamps, and drafts with bids or bookings. A controlled Ticket 6 state transition changes only `status`, `cancelled_at`, and `updated_at`, then appends one fixed privacy-safe audit event in the same transaction. Audit failure rolls back cancellation.

Only `authenticated` may execute the new function. `PUBLIC`, `anon`, and `service_role` cannot execute it, and `authenticated` can no longer execute the broader legacy `customer_cancel_request(uuid,text)` function. No direct table grant or RLS policy was added.

The UI shows “Cancel draft” only on the detail page after a fresh RLS-backed read reports `status = 'draft'`. It uses fixed confirmation copy, collects no reason, sends only `{ p_request_id: requestId }`, permits one in-flight call, does not optimistically change status, does not retry ambiguous failures, and shows success only after a fresh RLS-backed detail read returns `cancelled`.

## Reviewed frontend mutations

The frontend has only these reviewed marketplace RPC boundaries:

- `customer_create_draft_request`, whose payload always sends `p_precise_address_ciphertext: null`.
- `customer_cancel_draft_request`, whose payload contains only `p_request_id`.
- `customer_update_draft_request`, whose payload contains the request UUID and the complete seven-field reviewed draft replacement set only.

The frontend does not call the legacy cancellation function or the publication function and performs no direct application-table insert/update/upsert/delete.

## Ticket 9A-8 strict draft editing

Migration `016_customer_draft_update.sql` adds this trusted contract:

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

The `SECURITY DEFINER`, `VOLATILE` function derives identity only from `auth.uid()`, locks the actor profile and owned request, requires an active customer and exact internally consistent `draft`, rejects any bid, provider selection, booking, deprecated public address residue, inactive category, past start, negative budget, or complete no-op, and reuses the Ticket 9A-5 canonical public-field validator. It changes only category, title, description, suburb, city, requested start, budget, and server `updated_at`; it does not enable the marketplace state-transition flag. Exactly one fixed audit event records only the request UUID and an ordered allowlist of changed field names. Audit failure rolls the update back.

Only `authenticated` may execute the function. `PUBLIC`, `anon`, and `service_role` may not execute it. No direct table grant or RLS policy was added.

The edit page first validates the UUID and performs a fresh RLS-backed `service_requests` read constrained to `status = 'draft'`, using the same explicit request projection as detail. It pre-fills only category, title, description, suburb, city, requested start in SAST, and optional ZAR budget; reuses the Ticket 9A-3 validation/privacy warning; submits one exact RPC payload; uses single-flight behavior; never optimistically changes status; never automatically retries; and shows “Draft updated.” only after a fresh draft-only RLS re-read returns the same UUID and fresh server values.

## Intentionally not implemented

Ticket 9A-8 does not add publication, request deletion/duplication/reopening/archiving, exact-address collection/storage/read/reveal, maps, GPS, KMS/encryption, provider feed/onboarding/bidding, booking actions, payment/checkout/refund/payout, disputes, reviews, support, consent, notifications, chat, identity integration, profile editing, real provider integration, cash/off-platform options, or an admin route/dashboard.

No service-role key or real credential was added. Existing RLS, role/account-status protection, Ticket 5 address privacy, Ticket 6 state-machine protection, Ticket 9A-5 public-field validation, payment/refund/payout/webhook protections, and all read projections remain intact. No `select('*')` was added.

## Tests

The frontend uses Node's built-in test runner; no separate frontend test framework was introduced.

```powershell
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

Ticket 9A-8 adds `tests/request-update.test.mjs` and updates existing shell, Auth/safe-read, request-read, draft, and cancellation tests. The 53-test suite verifies draft-detail-only edit visibility, exact draft-only reads, prefill/SAST/ZAR conversion, shared validation/privacy rules, the exact eight-parameter RPC payload, single-flight behavior, no optimistic workflow change or automatic retry, fresh RLS confirmation, safe errors, and absence of publication/address/direct-DML/broad-select/blocked-feature boundaries.

The focused database suite is:

```powershell
cd outputs/marketplace-production-foundation
supabase test db supabase/tests/database/customer_draft_cancellation.test.sql
```

Its 62 assertions cover the function contract, restrictive grants, role/account/ownership checks, exact draft-only transition, unchanged public/ownership fields, fixed private audit event, duplicate/non-draft/inconsistent/bid/booking rejection, audit rollback, state-guard cleanup after success and failure, RLS, and regression boundaries. GitHub Actions runs this suite after `supabase db reset`, along with every existing frontend, Deno webhook, and pgTAP test.

The focused Ticket 9A-8 database suite is:

```powershell
cd outputs/marketplace-production-foundation
supabase test db supabase/tests/database/customer_draft_update.test.sql
```

Its 81 assertions cover the function contract and restrictive grants; authentication, protected role/status, ownership and locking; active-category, schedule, budget, complete-set validation and no-op handling; non-draft/inconsistent/bid/booking/address-residue rejection; canonical safe South African fixtures; minimal field updates; fixed privacy-safe changed-field audit metadata; direct-DML denial; and atomic audit-failure rollback. GitHub Actions runs it after `supabase db reset` with all existing suites.
