# LEKKADEALL frontend — Ticket 9A-7

This static ES-module frontend connects the Ticket 9A-1 shell to Supabase Auth, narrowly scoped RLS-backed reads, customer draft creation, customer request list/detail reads, and strict draft-only cancellation. It uses the pinned `@supabase/supabase-js` browser package with a public project URL and anon key only. Ticket 9A-7 adds no dependency or package-file change.

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

The frontend does not call the legacy cancellation function or the publication function and performs no direct application-table insert/update/upsert/delete.

## Intentionally not implemented

Ticket 9A-7 does not add publication, request editing/deletion/duplication/reopening/archiving, exact-address collection/storage/read/reveal, maps, GPS, KMS/encryption, provider feed/onboarding/bidding, booking actions, payment/checkout/refund/payout, disputes, reviews, support, consent, notifications, chat, identity integration, profile editing, real provider integration, cash/off-platform options, or an admin route/dashboard.

No service-role key or real credential was added. Existing RLS, role/account-status protection, Ticket 5 address privacy, Ticket 6 state-machine protection, Ticket 9A-5 public-field validation, payment/refund/payout/webhook protections, and all read projections remain intact. No `select('*')` was added.

## Tests

The frontend uses Node's built-in test runner; no separate frontend test framework was introduced.

```powershell
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

Ticket 9A-7 adds `tests/request-cancellation.test.mjs` and updates existing safe-read, request-read, and draft tests. The 43-test suite verifies detail-only visibility, fixed confirmation without a reason field, the exact RPC payload, single-flight behavior, no optimistic update/retry, the required fresh RLS re-read, safe errors, and absence of the legacy cancellation/publication/direct-DML/broad-select/blocked-feature boundaries.

The focused database suite is:

```powershell
cd outputs/marketplace-production-foundation
supabase test db supabase/tests/database/customer_draft_cancellation.test.sql
```

Its 62 assertions cover the function contract, restrictive grants, role/account/ownership checks, exact draft-only transition, unchanged public/ownership fields, fixed private audit event, duplicate/non-draft/inconsistent/bid/booking rejection, audit rollback, state-guard cleanup after success and failure, RLS, and regression boundaries. GitHub Actions runs this suite after `supabase db reset`, along with every existing frontend, Deno webhook, and pgTAP test.
