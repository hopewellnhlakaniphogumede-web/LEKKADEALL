# Ticket 8C Planning Document — Sandbox Provider-Specific Webhook Adapter Selection and Integration Readiness

## Goal

Prepare LEKKADEALL to select and integrate a sandbox payment-provider-specific webhook adapter without implementing that adapter yet.

Ticket 8C should bridge the gap between:

- Ticket 8A database-side mock/sandbox webhook processing;
- Ticket 8B mock/sandbox raw-body webhook route verification; and
- a future real payment provider sandbox integration.

The outcome of Ticket 8C should be a provider-selection and readiness decision, not production webhook code.

## Planning-only status

This document is planning-only.

Do not implement provider-specific webhook adapters, live provider routes, production credentials, sandbox credentials, real card/EFT processing, real refund webhooks, payout webhooks, reconciliation jobs, or UI until an explicit implementation ticket is requested.

## Current foundation

Already implemented:

- `admin_process_verified_mock_payment_webhook(...)` for database-side mock/sandbox processing after verification.
- `payment-webhook` Edge Function route for deterministic mock HMAC raw-body verification.
- `vendor_events` idempotency boundary.
- `payment_events` and `audit_events` ledger writing.
- Duplicate, different-payload-hash, out-of-order, and manual-review database protections.
- Mock route tests proving invalid signatures fail before database calls.
- Production + mock provider mode fails closed.

Still missing before a real provider sandbox adapter:

- chosen payment provider;
- provider sandbox account;
- provider webhook documentation review;
- provider signature verification implementation;
- provider event-to-internal-event mapping;
- provider reconciliation lookup API design;
- sandbox webhook secret management;
- webhook replay/timestamp validation rules;
- sandbox test cards/EFT flows where provider supports them;
- application tests using provider-shaped sample payloads.

## Candidate provider selection scope

No provider is selected by this plan.

The existing TypeScript contract already contains provider placeholders such as:

- `mock`
- `tradesafe`
- `netcash`

Ticket 8C should evaluate real candidate payment vendors against LEKKADEALL’s marketplace requirements before choosing the first sandbox adapter.

Important: vendor capabilities, pricing, compliance obligations, and API terms can change. Before choosing a vendor, verify current provider documentation and commercial terms directly with the vendor.

## Provider selection criteria

Choose the first sandbox provider only if it supports the MVP payment model:

- hosted checkout or hosted payment page;
- no card, CVV, bank-login, or raw payment credentials entering LEKKADEALL systems;
- ZAR payments;
- marketplace/provider payout path, escrow-like holding, split payment, or a clearly compliant alternative suitable for the business model;
- signed webhooks with documented raw-body verification;
- unique provider event IDs suitable for idempotency;
- clear event lifecycle for checkout created, payment paid, failed, expired, cancelled, refunded, and chargeback/dispute-like events if supported;
- sandbox environment with deterministic test flows;
- reconciliation or payment lookup API;
- refund API and refund webhooks, even if implemented later;
- payout/release API and payout webhooks, even if implemented later;
- support and commercial onboarding for a South African marketplace;
- data-processing terms compatible with POPIA and LEKKADEALL’s privacy commitments.

## Information to request from candidate vendors

Before implementation, request:

- sandbox account access;
- hosted checkout API documentation;
- webhook signature verification documentation;
- exact raw-body signing rules;
- required webhook headers;
- timestamp/replay tolerance guidance;
- sample webhook payloads for success, failure, expiry, cancellation, refund, chargeback/dispute, payout/release, and duplicate delivery;
- retry behavior and timeout expectations;
- event ordering guarantees or lack thereof;
- event ID uniqueness rules;
- payment lookup/reconciliation API documentation;
- refund API documentation;
- payout/release API documentation;
- list of supported payment methods for South Africa;
- settlement/payout timing;
- fees and commercial terms;
- data-processing agreement or operator agreement;
- support escalation route for payment incidents.

## Adapter architecture

Future provider-specific adapters should sit behind the existing vendor-neutral contract.

Recommended shape:

```ts
interface ProviderWebhookAdapter {
  providerName: string;
  verifyRawBody(args: {
    rawBody: Uint8Array;
    headers: Headers;
    secret: string;
    toleranceSeconds: number;
    now: () => number;
  }): Promise<ProviderVerifiedWebhook>;

  normalizeVerifiedEvent(args: {
    rawBody: Uint8Array;
    headers: Headers;
    payloadHash: string;
  }): Promise<NormalizedPaymentWebhookEvent>;
}
```

Hard rules:

- verify raw body bytes before parsing JSON;
- never verify against parsed or reserialized JSON;
- never store raw provider payloads;
- never forward webhook secrets or signatures to the database;
- normalize only safe fields needed by database functions;
- keep provider-specific logic out of frontend bundles;
- fail closed if required provider config is missing.

## Event mapping readiness

For the chosen provider, define a mapping table before coding.

At minimum, map:

| Provider event | Internal event | Payment status effect | Release status effect | Ledger event | Notes |
|---|---|---|---|---|---|
| checkout/session created | checkout created | `checkout_created` | unchanged | provider-specific checkout event | Must not mark paid. |
| payment succeeded | paid | `paid` | `pending` or `paused` | provider payment paid event | Must be idempotent. |
| payment failed | failed | `failed` | `cancelled` | provider payment failed event | Must not regress paid/refunded. |
| payment expired | expired | `expired` | `cancelled` | provider payment expired event | Only from pending/checkout-created. |
| payment cancelled | cancelled | `cancelled` | `cancelled` | provider payment cancelled event | Only from pending/checkout-created. |
| refund succeeded | future refund event | future Ticket refund handling | maybe cancelled/paused | future refund ledger | Not Ticket 8C implementation. |
| payout/release succeeded | future payout event | unchanged | released | future payout ledger | Not Ticket 8C implementation. |

The real mapping must be provider-documentation-specific.

## Signature verification readiness

For the chosen provider, document:

- exact signed payload format;
- whether timestamp is included in the signed string;
- whether the raw body is signed directly or with prefixes;
- signature algorithm;
- header names;
- whether multiple signatures are sent;
- replay/timestamp tolerance recommendation;
- how clock skew is handled;
- how to rotate webhook secrets;
- how to verify in sandbox and production separately.

Implementation must include tests proving that:

- valid provider sample signature passes;
- invalid signature fails before database call;
- missing signature fails before database call;
- stale timestamp fails before database call where provider supports timestamp;
- parsed/reserialized JSON does not verify;
- payload hash matches exact raw bytes.

## Secrets and environment readiness

No real secrets should be committed.

Future provider-specific environment variables should be server-only, for example:

- `PAYMENT_PROVIDER_MODE=sandbox`
- `PAYMENT_PROVIDER=<provider_name>`
- `PAYMENT_WEBHOOK_SECRET_<PROVIDER>`
- `PAYMENT_API_BASE_URL_<PROVIDER>`
- `PAYMENT_API_KEY_<PROVIDER>`
- `PAYMENT_WEBHOOK_TOLERANCE_SECONDS`

Readiness rules:

- local `.env.example` may contain placeholder names only;
- GitHub Actions must not contain production credentials;
- sandbox credentials must be configured only through secure CI/deployment secret storage;
- frontend code must not reference provider webhook secrets or service-role credentials;
- production must fail closed if provider mode is `mock`;
- production must fail closed if live/sandbox provider secrets are missing.

## Database readiness

Before provider-specific webhook implementation, decide whether the current Ticket 8A database function should be:

1. extended into a generic trusted provider webhook processor, or
2. kept mock-only while adding a new provider-specific trusted database function.

Preferred direction:

- keep `admin_process_verified_mock_payment_webhook(...)` mock-only;
- add a future provider-neutral trusted processor such as `admin_process_verified_payment_webhook(...)`;
- use provider-specific route adapters to normalize into the provider-neutral database function;
- keep `vendor_events` as the idempotency boundary;
- keep `payment_events` append-only;
- keep `audit_events` append-only.

Any future database migration must preserve Tickets 1/2/5/6/7A/7B/7C/7D/7E/8A/8B protections.

## Reconciliation readiness

Webhook handling alone is not enough for production payment safety.

Before live provider use, define:

- provider payment lookup API;
- reconciliation job schedule;
- retry policy;
- manual review queue for mismatched events;
- behavior for webhook received but lookup disagrees;
- behavior for lookup paid but webhook missing;
- behavior for duplicate provider references;
- audit and ledger rules for reconciliation corrections.

Ticket 8C should not implement reconciliation, but it should require that the chosen provider supports lookup/reconciliation before implementation proceeds.

## Compliance and operational readiness

Before implementation, confirm:

- vendor commercial agreement reviewed;
- POPIA/data-processing obligations reviewed;
- settlement/payout terms understood;
- chargeback and dispute process understood;
- refund SLA understood;
- support escalation route documented;
- incident-response path for webhook failure spikes documented;
- monitoring requirements defined;
- sandbox-to-production promotion checklist drafted.

## Required tests for future Ticket 8D/implementation

Application/server tests:

- valid provider sandbox signature is accepted;
- invalid provider signature is rejected;
- missing signature is rejected;
- stale timestamp is rejected where supported;
- raw body bytes are verified exactly;
- parsed/reserialized JSON cannot bypass verification;
- payload hash is computed from exact raw bytes;
- valid paid sandbox webhook calls the trusted database function exactly once;
- valid failed sandbox webhook calls the trusted database function exactly once;
- invalid signature does not call the database;
- duplicate provider event does not duplicate state;
- different payload hash for same provider event is flagged without mutation;
- production fails closed when required provider secrets are missing;
- frontend bundle contains no provider webhook secrets.

Database tests:

- provider-specific webhook processing preserves `vendor_events` idempotency;
- `payment_events` remains append-only;
- `audit_events` remains append-only;
- failed-after-paid does not regress payment;
- checkout-created-after-paid does not downgrade payment;
- paid-after-refunded routes to manual review or rejects safely;
- unrelated users cannot mutate payment state;
- all previous pgTAP files remain green.

## Ticket 8C definition of done

Ticket 8C is complete only when:

- candidate providers are compared against the MVP marketplace payment requirements;
- one sandbox provider is selected for the next implementation ticket, or a clear “no provider ready” decision is documented;
- current vendor docs and commercial requirements are reviewed directly with the vendor;
- provider webhook signature rules are documented;
- provider event mapping is drafted;
- sandbox credentials and secret-management approach are defined without committing secrets;
- reconciliation capability is confirmed or marked as a blocker;
- required tests for implementation are listed;
- no provider-specific code, live credentials, real payment processing, refund webhooks, payout webhooks, or UI are implemented in Ticket 8C.

## Explicit non-goals

Ticket 8C does not:

- implement a live/sandbox provider adapter;
- call a real payment provider;
- add real provider credentials;
- process real card/EFT/bank payments;
- implement real payment webhooks;
- implement refund webhooks;
- implement payout webhooks;
- implement reconciliation jobs;
- change RLS policies;
- build UI.
