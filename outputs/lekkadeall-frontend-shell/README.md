# LEKKADEALL frontend shell — Ticket 9A-1

This dependency-free static shell contains the first public, authentication, customer, provider, settings, and safe-state routes for LEKKADEALL.

It deliberately has no Supabase client, database mutations, real payment integration, real checkout, identity integration, exact-address flow, profile editing, sensitive marketplace workflows, or admin route.

## Preview

From the repository root:

```powershell
python -m http.server 4173 --directory outputs/lekkadeall-frontend-shell
```

Open `http://localhost:4173/`.

The clean-path entry files allow direct preview of routes such as:

- `http://localhost:4173/services/`
- `http://localhost:4173/auth/sign-in/`
- `http://localhost:4173/app/customer/`
- `http://localhost:4173/app/provider/`
- `http://localhost:4173/app/settings/`

Stop the preview with `Ctrl+C`.

## Frontend shell tests

No frontend test framework previously existed. Ticket 9A-1 uses Node's built-in test runner so there are no package dependencies or lockfile changes.

```powershell
node --test outputs/lekkadeall-frontend-shell/tests/frontend-shell.test.mjs
```

The tests verify route coverage, exact mock-payment wording, safe states, absence of an admin route, non-transmitting auth shells, absence of database writes and sensitive function calls, and clean-path entry files.

## Database and webhook regression tests

The existing GitHub Actions workflow continues to run the Deno webhook route test, reset the local Supabase database, and run every existing pgTAP database test. Ticket 9A-1 does not change migrations, RLS, grants, policies, database functions, or webhook code.
