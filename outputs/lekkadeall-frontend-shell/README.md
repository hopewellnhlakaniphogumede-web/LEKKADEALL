# LEKKADEALL frontend — Ticket 9A-6

This static ES-module frontend connects the Ticket 9A-1 shell to Supabase Auth, narrowly scoped RLS-backed reads, Ticket 9A-3 customer draft creation, and the Ticket 9A-6 read-only customer request list/detail baseline. It uses the pinned `@supabase/supabase-js` browser package with a public project URL and anon key only. Ticket 9A-6 adds no dependency or package-file change.

Role and account status are read from the signed-in user's RLS-protected `public.profiles` row. Auth metadata and callback/query parameters are never used as application authority. Registration sends only email, password, and the approved callback URL; Ticket 9B provisions the matching customer/active profile on the backend.

## Local configuration and preview

From the repository root:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
Copy-Item outputs/lekkadeall-frontend-shell/runtime-config.example.js outputs/lekkadeall-frontend-shell/runtime-config.local.js
```

Edit only the ignored `runtime-config.local.js` and replace the placeholders with the browser-safe project values corresponding to:

- `PUBLIC_APP_ENV=development`
- `PUBLIC_APP_URL=http://localhost:4173`
- `PUBLIC_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co`
- `PUBLIC_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY`

Never place a service-role key or any provider, webhook, identity, admin, payment, or database secret in frontend configuration.

Preview with this exact command from the repository root:

```powershell
python -m http.server 4173 --directory outputs/lekkadeall-frontend-shell
```

Open `http://localhost:4173/`. The Supabase Auth redirect allowlist must include `http://localhost:4173/auth/callback` and `http://localhost:4173/auth/reset-password` for the corresponding local flows.

Without `runtime-config.local.js`, public static pages remain visible while authentication and database reads fail closed with a configuration-required state.

## Customer request routes

- `/app/customer/requests/` — read-only list of the active customer's RLS-visible requests.
- `/app/customer/requests/detail/?requestId=<uuid>` — static-shell-compatible detail route. Only the opaque validated UUID enters the URL; request content does not.
- `/app/customer/requests/new/` — existing draft-only creation route.

The customer dashboard links to “View all requests.” After the trusted draft RPC returns a valid UUID, the confirmation page offers “View draft” and “View all requests.” Opening the detail route always performs a fresh RLS-backed read; it does not trust the creation response as authorization.

Only a session whose own protected profile says `role = 'customer'` and `account_status = 'active'` may use the new routes. Signed-out, expired, missing-profile, restricted, suspended, closed, wrong-role, and unknown-role/status states fail closed.

## Ticket 9A-6 read boundary

Both list and detail use exactly this request projection:

```text
id,category_id,title,description,suburb,city,requested_start,budget_minor,status,created_at,updated_at
```

The list filters to `draft`, `open`, and `cancelled`, orders by `created_at` descending, and is limited to 20 rows. Ownership is supplied only by existing RLS; the browser neither selects nor filters on `customer_id`.

The detail route validates the UUID before querying `service_requests`, applies the same status allowlist, and uses `maybeSingle()`. Malformed, missing, cross-customer, unsupported-status, and RLS-hidden IDs share one generic “Request not found or unavailable” state.

Category labels come only from the existing active `service_categories` projection `id,slug,name`. An inactive or unavailable historical category displays “Category unavailable”; the query is not broadened. Database strings are HTML-escaped, dates are explicitly formatted in `Africa/Johannesburg` with a SAST label, and integer `budget_minor` values are display-only ZAR amounts with no payment instructions.

No request content is written to a URL, `localStorage`, `sessionStorage`, IndexedDB, a service-worker cache, logs, analytics, telemetry, or error reports.

## Customer request draft

An active customer can select an active category, enter public job details, suburb/city, a future SAST start, and an optional ZAR budget. Budget conversion uses string/integer logic.

The only marketplace mutation in the frontend remains `customer_create_draft_request`. Its reviewed payload always sends `p_precise_address_ciphertext: null`. The form is single-flight, does not automatically retry ambiguous failures, keeps values in memory only, and renders success only after the backend returns a valid request UUID.

## Intentionally not implemented

Ticket 9A-6 does not add cancellation or call `customer_cancel_request(...)`. There is no request publication/edit/update/delete, exact-address collection/storage/read/reveal, map, GPS, KMS/encryption, provider feed/onboarding/bidding, booking mutation/completion, payment/checkout/refund/payout, dispute, review, support, consent, notification, chat, profile editing, identity-provider integration, real payment-provider integration, cash/off-platform option, admin route/dashboard, or direct application-table insert/update/upsert/delete.

No migration, RLS policy, grant, database policy/function, or webhook changed. No service-role key or real credential was added, and no request read uses `select('*')` or an unapproved column.

## Tests

The frontend continues to use Node's built-in test runner; no separate frontend test framework was introduced.

```powershell
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

Ticket 9A-6 adds `tests/customer-request-read.test.mjs` and updates the existing shell, Auth/safe-read, and draft tests. The 33-test suite verifies:

- active-customer route guards and safe signed-out/restricted/wrong-role states;
- the exact request projection, status filters, descending order, and limit of 20;
- UUID validation before a request query, exact detail projection, and `maybeSingle()` behavior;
- one generic detail-unavailable state, active-category fallback, output escaping, explicit SAST dates, and ZAR display formatting;
- customer dashboard and post-draft list/detail navigation;
- no `select('*')`, direct application DML, cancellation/publication/address RPC, blocked request field, browser persistence, admin route, service-role key, or secret.

GitHub Actions installs the exact locked Supabase browser dependency, runs every frontend test file, and then runs all existing Deno webhook and pgTAP database regression suites.
