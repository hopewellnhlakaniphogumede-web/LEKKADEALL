# LEKKADEALL Project Rules

## Scope and source of truth

These rules apply to the entire repository.

- The active browser application is `outputs/lekkadeall-frontend-shell`.
- The active database, RLS, trusted RPC, integration-contract, and Edge Function work is in `outputs/marketplace-production-foundation`.
- Treat `outputs/potchly-prototype` as a legacy prototype, not a production source. Do not copy its hard-coded data or `localStorage` patterns into the active application.
- `hardening_progress.md` and `TESTING.md` describe the current implemented state. Ticket plans and `production_hardening_plan.md` provide design context but may contain superseded statements.
- Keep the marketplace data model vendor-neutral. Branding belongs in presentation/configuration, not database contracts.
- This repository is a production-hardening foundation, not proof of a deployed or production-ready marketplace. Do not overstate implementation, verification, provider, payment, or launch status.

## Working method

- Read the affected migration, application module, tests, and relevant current-status documentation before changing behavior.
- Keep changes narrowly scoped to the requested ticket or defect. Do not unlock adjacent features merely because schema or UI placeholders exist.
- Preserve established security boundaries. If a requested change conflicts with them, stop and describe the conflict instead of weakening a guard.
- Make the smallest complete change across implementation, tests, and documentation.
- Update `hardening_progress.md` and `TESTING.md` when implementation or verified test status materially changes. Record commands actually run and distinguish passing, failing, skipped, and unavailable checks.
- Never claim a test passed unless it ran successfully in the current environment. GitHub Actions remains authoritative for Docker/Supabase/Playwright coverage that cannot run locally.
- Do not commit generated files, dependencies, secrets, local runtime configuration, test artifacts, or Supabase runtime state.

## Security and privacy invariants

- Fail closed on missing configuration, missing/expired sessions, missing profiles, unknown roles or statuses, malformed identifiers, RLS-hidden records, stale state, ambiguous mutations, and provider failures.
- Derive application authority from the authenticated identity and the protected `public.profiles` row. Never trust URL parameters, Auth metadata, form fields, or browser state for role, ownership, verification, or account status.
- The browser may contain only the public Supabase URL and anon key. Never expose or bundle service-role keys, database credentials, webhook secrets, provider credentials, identity secrets, payment secrets, or admin credentials.
- Keep secrets out of source, fixtures, logs, errors, screenshots, traces, browser storage, URLs, analytics, audit metadata, and test output. Use `.env.example` and `runtime-config.example.js` only for placeholder names and browser-safe examples.
- RLS must remain enabled on every frontend-exposed application table. Grants and RLS are both part of the authorization boundary; review both.
- Do not use broad reads such as `select('*')`. Declare the minimum reviewed projection and rely on RLS for ownership filtering. Do not add browser ownership filters as a substitute for RLS.
- Browser application code must not perform direct insert/update/upsert/delete operations on protected marketplace tables. Use the reviewed RPC boundary for each mutation.
- Privileged and workflow-changing operations must be server-owned, transactional, least-privilege, and audited. The browser must not set workflow state, ownership, verification, payment, payout, refund, provider selection, or admin fields directly.
- `SECURITY DEFINER` functions must use a fixed safe `search_path`, derive the actor from `auth.uid()` or an explicitly reviewed server boundary, validate role/status/ownership and current state, lock relevant rows, make the minimum mutation, and write a fixed privacy-safe audit event atomically.
- Revoke function execution broadly, then grant it only to the intended role. Do not make `service_role` a browser or general table-access escape hatch.
- Audit events and financial/vendor ledgers are append-only. Never log raw webhook bodies, signatures, credentials, identity evidence, exact addresses, free-form private content, or sensitive database rows.
- Verify webhook signatures against the exact raw body before parsing. Enforce timestamp tolerance, idempotency, safe normalization, and reconciliation. Production must reject mock providers and missing secrets.
- Never collect or store card data or bank-login credentials. Store only reviewed provider references, state, and reconciliation metadata.
- Keep raw identity/biometric material out of the application where feasible. Production identity handling remains blocked until its legal, consent, retention, and vendor controls are approved.
- Precise service addresses belong only in the private encrypted boundary and may be revealed only through the reviewed audited function to the selected provider for an eligible confirmed booking. Never put exact addresses in public request fields.
- Public request fields must use the canonical server validator and must not contain contact details, URLs, credentials, precise addresses, or other prohibited sensitive content.
- Return generic user-facing errors for authorization, ownership, account existence, hidden records, and server failures. Do not leak whether another user's record or account exists.
- Do not automatically retry a mutation after an ambiguous transport outcome. Reconcile through a fresh authorized read before showing success or allowing another action.
- Do not optimistically render workflow success. Confirm the canonical server state with a fresh RLS-backed read.
- Do not persist marketplace/request content in `localStorage`, `sessionStorage`, IndexedDB, Cache Storage, cookies, service-worker caches, URLs, or telemetry. The existing Supabase SDK Auth-session entry is the only reviewed signed-in storage exception, and sign-out must remove it.

## Frontend rules

- The frontend is static, dependency-light, browser-native ES modules. Follow the existing two-space JavaScript style, semicolons, single quotes, named exports, and small pure helpers.
- Keep dependencies pinned exactly in `package.json` and `pnpm-lock.yaml`. Do not add or upgrade dependencies without a concrete need and matching lockfile/test changes.
- Use the shared modules for public configuration, Supabase client creation, Auth session handling, route guards, safe reads, request validation, and mutation wrappers. Do not create alternate authorization or data-access paths.
- Validate identifiers and public fields before network calls, then repeat authoritative validation on the server.
- Escape database/user strings before rendering HTML. Do not interpolate untrusted values into markup, URLs, logs, or error text without the established validation/escaping boundary.
- Dates and times are explicit `Africa/Johannesburg` / SAST values. Money is integer minor units and displayed as ZAR; avoid floating-point storage or calculation.
- Protected routes require a fresh session and protected profile decision. Signed-out, missing-profile, restricted, suspended, closed, wrong-role, and unknown states must route to an established fail-closed page.
- Preserve single-flight form/mutation behavior. Disable re-entrant submission and avoid implicit retries.
- Keep blocked capabilities blocked unless a separately reviewed ticket authorizes them. This includes publication, exact-address UI, maps/GPS, provider onboarding/bidding, bookings beyond approved RPCs, live payments, disputes, reviews, chat/support, identity integration, profile editing, and admin UI.

## Database and Edge Function rules

- Never edit an already applied numbered migration to change deployed behavior. Add the next sequential migration and corresponding pgTAP coverage. Update an old migration only when explicitly repairing an unreleased baseline and document why.
- Preserve the established SQL style: lowercase keywords, schema-qualified objects, explicit casts for enums, explicit column lists, narrow updates, fixed error categories, and comments that explain security intent.
- State changes must follow the authoritative database state machine and its trusted functions. Do not bypass transition guards, internal consistency checks, row locks, or audit requirements.
- Treat changes to tables, columns, functions, triggers, grants, RLS policies, status enums, audit metadata, payment ledgers, or address access as security-sensitive. Add positive and negative tests, including wrong role, wrong status, wrong owner, missing profile, duplicate/replay, and rollback behavior as applicable.
- Edge Functions are Deno/TypeScript modules. Keep request handlers testable through injected environment, clock, fetch, and processor dependencies; keep responses privacy-safe and `no-store`.
- Mock and sandbox behavior must be visibly and technically distinct from live provider behavior. Never represent a database status update as proof that real money moved.

## Tests and verification

Run the smallest relevant check while iterating, then the broader affected suites before handoff.

Install pinned frontend dependencies from the repository root:

```powershell
pnpm install --dir outputs/lekkadeall-frontend-shell --frozen-lockfile
```

Run all static frontend tests:

```powershell
node --test outputs/lekkadeall-frontend-shell/tests/*.test.mjs
```

Run a focused frontend test:

```powershell
node --test outputs/lekkadeall-frontend-shell/tests/<name>.test.mjs
```

Run the webhook Edge Function tests:

```powershell
cd outputs/marketplace-production-foundation
deno test supabase/functions/payment-webhook/index.test.ts
```

Database tests require Docker and Supabase CLI `2.110.0`. From `outputs/marketplace-production-foundation`:

```powershell
supabase start
supabase db reset
supabase test db supabase/tests/database/<suite>.test.sql
supabase stop --no-backup
```

Run every relevant pgTAP suite when changing shared schema, grants, RLS, validators, workflow guards, audit functions, or financial/address boundaries. The complete CI matrix is defined in `.github/workflows/database-tests.yml`.

The local customer lifecycle E2E owns a fresh disposable loopback Supabase stack. It requires Docker, Supabase CLI, Node.js, pnpm, and pinned Chromium:

```powershell
pnpm --dir outputs/lekkadeall-frontend-shell exec playwright install chromium
pnpm --dir outputs/lekkadeall-frontend-shell run test:e2e:local
```

- Do not point the E2E runner at remote, shared, staging, or production resources.
- Do not run it over an already-running local Supabase stack or overwrite an existing `runtime-config.local.js`.
- Keep one Chromium worker, zero retries, and screenshots/video/traces/HAR/storage-state output disabled unless a separately reviewed privacy decision changes that boundary.
- Ensure cleanup removes generated runtime configuration and stops the disposable stack without a backup.

## Completion checklist

Before handing off a change:

- Confirm no secret or production identifier was introduced.
- Confirm authorization remains server/RLS enforced and least-privilege.
- Confirm sensitive reads use explicit projections.
- Confirm mutations use only reviewed RPC/server boundaries.
- Confirm failure, stale, unauthorized, cross-owner, and ambiguous outcomes fail closed.
- Add or update focused regression tests and run every locally available affected suite.
- Update current-status/testing documentation without rewriting historical records or claiming unrun verification.
- State any unavailable checks and the exact reason.
