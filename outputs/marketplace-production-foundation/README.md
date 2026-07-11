# National Services Marketplace - Production Foundation

This folder begins the conversion of the Potchly prototype into a real, vendor-neutral marketplace. The working brand is intentionally not hard-coded into the data model.

## What is included

- `supabase/migrations/001_initial_schema.sql`: PostgreSQL schema, constraints, indexes, row-level security and initial policies.
- `src/integrations/contracts.ts`: interfaces for payment, identity and messaging partners.
- `.env.example`: names of required configuration values; no secrets.
- `architecture.md`: security boundaries and launch gates.

## Recommended build sequence

1. Create separate development, staging and production projects.
2. Apply the migration to development.
3. Configure email/phone authentication and mandatory MFA for administrators.
4. Build customer and provider screens against the schema.
5. Implement mock vendor adapters first.
6. Replace mocks with sandbox adapters after contracts and credentials arrive.
7. Complete refund, payout-freeze and reconciliation tests before live payments.
8. Complete privacy impact and security reviews before collecting identity documents.

## Non-negotiable rules

- Card and bank-login credentials never enter the application database.
- Raw identity or biometric material should go directly to the verification partner where feasible.
- Precise addresses are revealed only to the selected provider for a confirmed booking.
- Every privileged action is written to an append-only audit stream.
- Vendor webhooks must be signed, idempotent and reconciled.
- No production secrets are committed to source control.

This is an implementation foundation, not yet a deployed production system.
