# LEKKADEALL frontend — Ticket 9A-3

This static ES-module frontend connects the Ticket 9A-1 shell to Supabase Auth, narrowly scoped reads, and the first active-customer draft-creation workflow. It uses the pinned `@supabase/supabase-js` browser package with a public project URL and anon key only.

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

## Read boundary

The frontend can attempt only these explicit, RLS-backed projections:

- active `service_categories`: ID, slug, and name;
- the signed-in user's `profiles` route fields and safe settings fields;
- the signed-in provider's own safe `provider_profiles` status fields;
- the customer's own service-request summary rows;
- booking-party booking summary rows;
- payment summary rows for booking IDs already returned to that customer.

If existing RLS or column grants deny a query, the interface shows a read-unavailable placeholder. It does not retry with a broader projection or weaken security.

## Customer request draft

An active customer can open `/app/customer/requests/new/`, select an active category, enter public job details, suburb/city, a future SAST start, and an optional ZAR budget. Budget conversion uses string/integer logic.

The only marketplace RPC is `customer_create_draft_request`. Its reviewed payload always sends `p_precise_address_ciphertext: null`. The form is single-flight, does not automatically retry ambiguous failures, keeps values in memory only, and renders success only after the backend returns a request UUID.

Publishing and exact-address collection remain unavailable.

## Intentionally not implemented

There is no admin route, profile editing, exact-address flow, request publication/edit/cancel/delete, bidding, booking completion, refund, payout, dispute, review, consent, support, notification, chat, identity-provider integration, real payment-provider integration, checkout, payment-method form, cash option, or direct application-table insert/update/upsert/delete. No application RPC exists beyond the single reviewed draft-creation function.

## Tests

Ticket 9A-3 continues to use Node's built-in test runner; no separate frontend test framework was introduced.

```powershell
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

The tests verify routes and safe states, exact mock-payment wording, the anon-only client boundary, metadata-free registration, profile-backed route guards, request validation/privacy rules, integer ZAR and SAST conversion, the exact allowlisted draft RPC payload, null ciphertext, explicit read projections, no blocked RPCs/direct DML/`select('*')`, no admin route, no sensitive form fields, and no browser secrets.

GitHub Actions installs the exact locked Supabase browser dependency, runs every frontend test file, then runs all existing Deno webhook and pgTAP database regression suites. Ticket 9A-3 changes no migration, RLS policy, grant, database function, or webhook.
