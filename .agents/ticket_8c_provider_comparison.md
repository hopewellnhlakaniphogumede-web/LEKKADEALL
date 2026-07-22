# Ticket 8C Provider Comparison — South African Payment Providers

## Purpose and status

This is a planning-only comparison for LEKKADEALL's first provider-specific sandbox webhook adapter. It does not select or integrate a live provider and does not add credentials, migrations, tests, payment processing, refund execution, payout execution, reconciliation jobs, or UI.

Research date: **13 July 2026**.

Provider products, documentation, pricing, onboarding requirements, and regulatory arrangements can change. A statement is treated as verified only where the provider's current public documentation supports it. Every unresolved item is marked **needs vendor confirmation**.

## LEKKADEALL hard gates

A provider is ready for selection only if all of these are confirmed:

- hosted checkout or a provider-hosted payment page, so card, CVV, bank-login, and other raw payment credentials do not enter LEKKADEALL systems;
- ZAR support;
- a marketplace/provider payout path, escrow-like holding, split payment, or another legally and operationally compliant arrangement for collecting customer funds and later releasing the provider's share;
- authenticated webhooks with documented verification over the exact provider-defined message, a unique event or webhook ID, and replay protection suitable for the Ticket 8B fail-closed route;
- deterministic sandbox flows that deliver provider-shaped webhooks;
- payment lookup or reconciliation API;
- refund API and refund status notifications, even though implementation is later;
- payout/release API and payout status notifications, even though implementation is later;
- South African marketplace onboarding, commercial acceptance, and settlement terms;
- POPIA-compatible data-processing terms and an incident/support escalation path.

“Split payment” is not automatically equivalent to escrow or delayed release. LEKKADEALL must not collect or hold provider money in its own ordinary account unless the vendor and South African legal advice confirm that structure is permitted.

## Executive decision

**Decision: no provider is ready for selection yet.**

The ranked shortlist for vendor confirmation is:

1. **Stitch — next technical candidate.** Public documentation covers Stitch-hosted card UI, signed webhook delivery, event IDs/timestamps, test payment simulation, refunds, payout APIs, payout lookup, and payout webhooks. A compliant marketplace hold/release or split-settlement structure and product availability/commercial terms for LEKKADEALL are **needs vendor confirmation**.
2. **TradeSafe — marketplace/escrow model candidate, webhook-security blocker.** Public material explicitly describes marketplace integration, escrow holding, allocations, release, refunds, disputes, a sandbox application, GraphQL API, and callbacks. Its public callback security documentation describes IP allowlisting or a secret embedded in the callback URL; it does not document a signed raw-body callback with timestamp replay protection. A stronger signed callback mechanism is **needs vendor confirmation** and is a hard blocker for the Ticket 8C adapter.
3. **Netcash / PayFast / Ozow — lower-priority candidates.** Each remains unsuitable for first-adapter selection unless it confirms both a compliant marketplace hold/release model and signed webhook suitability. All unresolved requirements remain **needs vendor confirmation**.

**Peach Payments is removed from the shortlist. Peach Payments is not suitable for LEKKADEALL marketplace model — vendor confirmed no marketplace support.** Its documented technical capabilities do not overcome this business-model hard-gate failure.

## Provider comparison

| Criterion | Peach Payments | Stitch | TradeSafe | Netcash | PayFast | Ozow |
|---|---|---|---|---|---|---|
| South African/ZAR fit | Public docs list South Africa and ZAR | Public refund/payment examples use ZAR; South African commercial availability for this use case is **needs vendor confirmation** | South African marketplace/escrow service | Pay Now transaction amount is documented as ZAR | South African payment product; exact LEKKADEALL onboarding scope is **needs vendor confirmation** | Public integration docs say only ZA banks and ZAR are supported |
| Hosted customer payment surface | Hosted Checkout and hosted Payment Links documented | Stitch-hosted once-off card UI documented; hosted coverage for every proposed payment method is **needs vendor confirmation** | Payment link/payment page described | Pay Now hosted form and payment links documented | Redirected PayFast payment flow documented | Hosted payment page/payment-link API documented |
| Marketplace hold/release suitability | **Not suitable for LEKKADEALL marketplace model — vendor confirmed no marketplace support** | Payouts/refunds exist, but compliant marketplace holding, split settlement, beneficiary onboarding, and delayed release are **needs vendor confirmation** | Explicit escrow, allocations, buyer acceptance, seller/marketplace release, amendment/refund, and dispute model | Split payments between Netcash accounts are documented; delayed conditional release, refund/dispute holds, and legal marketplace structure are **needs vendor confirmation** | One receiving merchant per split transaction is documented; delayed release, provider onboarding, refund/dispute holds, and legal marketplace structure are **needs vendor confirmation** | Payout API is documented; split settlement, compliant holding, provider onboarding, and delayed release are **needs vendor confirmation** |
| Webhook/callback authentication | Optional webhook HMAC-SHA256 uses timestamp, webhook ID, URL, and payload; activation and exact production configuration are **needs vendor confirmation** | Signed webhooks documented; current Svix signing/replay rules and stable event-ID contract for selected products are **needs vendor confirmation** | Public docs show IP allowlisting or a URL secret, not signed raw-body verification; stronger mechanism is **needs vendor confirmation** | Public evidence reviewed did not establish signed exact-message webhooks, timestamp replay protection, or unique event IDs: **needs vendor confirmation** | ITN uses an MD5 field signature plus IP, amount, and server-confirmation checks; no modern raw-body HMAC/timestamp contract was found | Response uses an ordered-field SHA-512 hash; exact raw-body signing, timestamp replay protection, and unique event IDs are **needs vendor confirmation** |
| Durable event ID for `vendor_events` | `x-webhook-id` documented | Event ID documented in webhook guidance | Transaction/allocation/drawdown IDs exist; a unique callback-delivery ID is **needs vendor confirmation** | **needs vendor confirmation** | `pf_payment_id` exists, but uniqueness and stability across all event types/retries are **needs vendor confirmation** | Transaction ID exists; unique notification-delivery ID and retry semantics are **needs vendor confirmation** |
| Sandbox webhook determinism | Sandbox and payment-method testing documented; deterministic webhook scenarios for all required states are **needs vendor confirmation** | Test-client completion simulation triggers a webhook; complete deterministic matrices are **needs vendor confirmation** | Sandbox application/playground documented; signed callback fixtures and deterministic state simulations are **needs vendor confirmation** | Test account and provider-shaped webhook fixtures are **needs vendor confirmation** | Sandbox/test flow exists; deterministic webhook fixtures for all LEKKADEALL states are **needs vendor confirmation** | Public docs state notification responses are not sent for test transactions, which blocks representative sandbox webhook testing unless the vendor supplies another facility: **needs vendor confirmation** |
| Payment lookup/reconciliation | Checkout status query and reconciliation tooling documented | API queries/status retrieval documented; formal reconciliation exports/job support are **needs vendor confirmation** | Transaction query through GraphQL documented; formal reconciliation reports and mismatch procedures are **needs vendor confirmation** | Payment reference and reconciliation capabilities appear in product material; exact API contract is **needs vendor confirmation** | ITN server validation exists; general payment lookup/reconciliation API suitable for scheduled reconciliation is **needs vendor confirmation** | Transaction lookup by provider ID or merchant reference documented |
| Refund API/status events | Checkout refund API and refund webhook states documented | Refund API, status lookup, test scenarios, and signed refund webhooks documented | Amendment/refund workflow documented; exact API states and callback authentication are **needs vendor confirmation** | **needs vendor confirmation** | Refund API and refund notifications across chosen methods are **needs vendor confirmation** | Refund capability and automated outcome notifications are **needs vendor confirmation** |
| Payout API/status events | Payout API and signed payout status webhooks documented | Payout/disbursement API, status query, and webhook updates documented | Release/drawdown and payout behavior documented; callback authentication remains a blocker | Split payments documented; later bank payout/release API and status webhooks are **needs vendor confirmation** | Split payment is documented; later payout/release API and status webhooks are **needs vendor confirmation** | Payout API and outcome notifications are advertised; signed status webhook details are **needs vendor confirmation** |
| Pricing and settlement timing | **needs vendor confirmation** | **needs vendor confirmation** | **needs vendor confirmation** | **needs vendor confirmation** | **needs vendor confirmation** | **needs vendor confirmation** |
| POPIA/DPA/operator terms | **needs vendor confirmation** | **needs vendor confirmation** | **needs vendor confirmation** | **needs vendor confirmation** | **needs vendor confirmation** | **needs vendor confirmation** |
| Overall readiness | **Not suitable — vendor-confirmed marketplace-model failure** | **Conditional shortlist #1** | **Conditional shortlist #2; security blocker** | **Lower priority; not ready** | **Lower priority; not ready** | **Lower priority; not ready** |

## Provider-specific findings

### 1. Stitch

Why it remains a strong alternative:

- Stitch documents a hosted UI for once-off card payments.
- Webhooks are signed and retried. Published webhook guidance describes event IDs and timestamps for duplicate/replay handling, and exact body-byte HMAC verification in its legacy signing documentation; current selected-product Svix verification details must be frozen from the vendor's current contract before coding.
- Test clients can simulate a completed Pay by Bank request and trigger the corresponding webhook.
- Refunds, refund status queries, signed refund webhooks, payout/disbursement APIs, payout lookup, and payout webhooks are documented.

Open gates:

- marketplace/sub-merchant model, compliant holding or delayed release, split settlement, and provider KYC: **needs vendor confirmation**;
- one hosted checkout surface covering the MVP's selected payment methods without LEKKADEALL receiving sensitive credentials: **needs vendor confirmation**;
- current Svix signed-message construction, tolerance, event-ID uniqueness, secret rotation, test fixtures, and event ordering: **needs vendor confirmation**;
- pricing, reserves, settlement timing, DPA/operator terms, onboarding approval, support SLA, and incident escalation: **needs vendor confirmation**.

### 2. TradeSafe

Why it best matches the marketplace state model:

- TradeSafe explicitly markets integration for marketplaces through GraphQL.
- Its documented flow includes buyer funding, escrow holding, seller performance, buyer/client acceptance, allocations, marketplace commission, release, amendment/refund, and dispute-related fund locking.
- A sandbox application, playground, API documentation, payment links, transaction queries, and callbacks on state changes are described.

Hard blocker:

- Public callback security documentation offers source-IP allowlisting or a secret placed in the callback URL. Neither proves integrity of the exact body, supplies a signed timestamp, or gives LEKKADEALL a cryptographic replay-resistant event envelope. A signed HMAC or asymmetric callback scheme covering exact bytes, with timestamp and unique delivery ID, is **needs vendor confirmation**.

Other open gates:

- deterministic signed sandbox callbacks for every required transaction/allocation/drawdown state: **needs vendor confirmation**;
- callback retry schedule, event ordering, delivery-ID uniqueness, secret rotation, and reconciliation procedures: **needs vendor confirmation**;
- suitability for services rather than only goods, inspection/release timing, cancellation/refund handling, provider KYC, dispute roles, fees, settlement timing, DPA/operator terms, and support SLA: **needs vendor confirmation**.

### Excluded from shortlist: Peach Payments

Peach Payments confirmed directly to the user that it does not support marketplace. Therefore:

- **Peach Payments is not suitable for LEKKADEALL marketplace model — vendor confirmed no marketplace support.**
- Peach is no longer the provisional technical leader and is not a candidate for the first provider-specific sandbox adapter.
- Its documented hosted checkout, HMAC webhook, lookup, refund, payout, reconciliation, ZAR, and sandbox capabilities remain technically relevant, but they cannot satisfy LEKKADEALL's marketplace-model hard gate.
- No further Peach technical confirmation is required for Ticket 8C unless Peach later provides a materially different, written marketplace product position.
- Historical unresolved commercial details such as fees, reserves, settlement timing, DPA/operator terms, support SLA, and incident escalation remain **needs vendor confirmation**, but resolving them would not change the current exclusion.

### 3. Netcash

Public documentation supports Pay Now hosted payment collection in ZAR and split payments to another Netcash account. That may support commissions, but it does not by itself establish LEKKADEALL's required conditional hold/release model.

Before reconsidering Netcash, obtain confirmation of signed exact-message webhooks, timestamp/replay rules, unique event IDs, retry semantics, deterministic sandbox delivery, payment lookup, refunds, chargebacks, later provider payouts, conditional release/holds, provider onboarding, pricing, settlement, DPA/operator terms, and marketplace approval. All are **needs vendor confirmation**.

### 4. PayFast

PayFast documents redirected payment processing, ZAR identifiers, ITN notifications, and split payments to one receiving merchant. Its ITN security model uses an MD5 signature over URL-encoded fields together with IP validation, amount validation, and a server validation call. This can be authenticated when implemented exactly, but it does not match the preferred modern raw-body HMAC plus timestamp/event-ID model.

Before reconsidering PayFast, obtain a current signed-webhook product with exact-message verification, replay tolerance, unique delivery IDs, deterministic fixtures, refund and payout lifecycle events, compliant delayed provider release, provider onboarding, reconciliation API, pricing, settlement, DPA/operator terms, and marketplace approval. All are **needs vendor confirmation**.

### 5. Ozow

Ozow documents a hosted payment flow, ZAR/ZA bank support, a response hash, and transaction lookup by Ozow ID or merchant reference. It also advertises payout APIs and outcome notifications.

The public integration page says normal test transactions do not send notification responses. That prevents Ticket 8C from proving a provider-shaped signed webhook through a realistic sandbox flow. Exact raw-body signing, timestamp replay protection, unique delivery IDs, retry semantics, refund API/events, split or hold/release capability, provider onboarding, pricing, settlement, DPA/operator terms, and marketplace approval are **needs vendor confirmation**.

## Questions for the vendor calls

Ask Stitch and TradeSafe the same written questions so answers are comparable. Ask Netcash, PayFast, or Ozow only if LEKKADEALL decides to investigate the lower-priority group:

1. Will you contractually approve a South African services marketplace where the customer pays at booking and the provider is paid only after completion, subject to refund/dispute/release holds?
2. Who is merchant of record, who legally holds funds, and what licence/regulated arrangement covers the flow?
3. Can one transaction allocate LEKKADEALL's fee and the provider's share? Can release be delayed, paused, cancelled, partially refunded, or disputed?
4. Must each provider be onboarded as a sub-merchant/beneficiary? What KYC, bank-account verification, sanctions screening, and ongoing monitoring apply?
5. Does hosted checkout ensure that card, CVV, bank-login, and other raw payment credentials never enter LEKKADEALL systems?
6. Supply the exact current sandbox webhook signing specification, required headers, signed-byte/message construction, algorithm, timestamp tolerance, unique event-ID rules, retry schedule, ordering guarantees, and secret-rotation procedure.
7. Supply provider-shaped signed sandbox fixtures and deterministic triggers for checkout created, pending, paid, failed, expired, cancelled, refund states, dispute/chargeback states, payout/release states, duplicates, and out-of-order delivery.
8. Supply payment, refund, and payout lookup APIs and reconciliation reports. Explain corrections when lookup and webhook state disagree.
9. Confirm supported ZAR methods, method-specific finality/chargeback behavior, partial refunds, payout rails, settlement times, reserves, limits, and all fees.
10. Supply the DPA/operator terms, data location/subprocessor list, retention rules, breach notification terms, support SLA, and payment-incident escalation contacts.

## Selection gate for the next ticket

Ticket 8C should select the first sandbox adapter only after written answers close every hard gate.

- Do not select **Peach Payments**: it is not suitable for LEKKADEALL marketplace model — vendor confirmed no marketplace support.
- Select **Stitch** if it confirms the marketplace fund flow and supplies the current signed-webhook and sandbox contract.
- Select **TradeSafe** only if it supplies a cryptographically signed, replay-resistant callback mechanism meeting the Ticket 8B security properties.
- Consider **Netcash, PayFast, or Ozow** only if a candidate confirms both a compliant marketplace hold/release structure and signed webhook suitability, along with the other hard gates.
- If none closes those gates, retain the current **no provider ready** decision and do not implement a provider adapter.

The future implementation ticket must freeze the selected provider documentation version, event mapping, signature vector fixtures, secret names (placeholders only in source control), reconciliation behavior, and the complete test matrix before code is merged.

## Primary sources reviewed

### Peach Payments

- [Product portfolio overview](https://developer.peachpayments.com/docs/product-portfolio-overview)
- [Hosted Checkout overview](https://developer.peachpayments.com/docs/checkout-overview)
- [Checkout webhooks and HMAC security](https://developer.peachpayments.com/docs/checkout-webhooks)
- [Checkout status lookup](https://developer.peachpayments.com/docs/checkout-payment-status)
- [Checkout refunds](https://developer.peachpayments.com/docs/checkout-refund)
- [Payouts API and payout webhooks](https://developer.peachpayments.com/docs/payouts-api-1)

### Stitch

- [Stitch-hosted once-off card UI](https://docs.stitch.money/payment-products/payins/card/once-off/hosted-ui)
- [Webhook event subscriptions](https://docs.stitch.money/webhooks)
- [Signed webhook verification details](https://docs.stitch.money/webhooks_legacy)
- [Pay by Bank test flow](https://docs.stitch.money/payment-products/payins/paybybank/integration-process)
- [Refunds and refund webhooks](https://docs.stitch.money/payment-products/payouts/refunds)
- [Payouts overview](https://docs.stitch.money/payment-products/payouts/introduction)

### TradeSafe

- [TradeSafe marketplace and escrow overview](https://www.tradesafe.co.za/)
- [GraphQL API workflow](https://docs.tradesafe.co.za/api/)
- [Callbacks and public callback security options](https://docs.tradesafe.co.za/api/callbacks/)
- [Managing payout/refund options](https://docs.tradesafe.co.za/api/managing-funds/)

### Netcash

- [Pay Now eCommerce integration](https://api.netcash.co.za/inbound-payments/pay-now/pay-now-ecommerce/)
- [Split Payments](https://netcash.co.za/services/payment-gateway/split-payments/)

### PayFast

- [Instant Transaction Notification and split payments](https://developers.payfast.co.za/docs/itn-instant-transaction-notification/)

### Ozow

- [Payment gateway integration, response hashing, testing, and transaction lookup](https://ozow.com/integrations)
- [Ozow Payouts](https://ozow.com/our-products/ozow-payouts)

## Explicit non-goals

This comparison does not:

- select a production provider;
- implement or change a webhook route or adapter;
- add credentials or secret values;
- add or change migrations, RLS policies, database functions, or tests;
- process real or sandbox money;
- implement refunds, payouts, release, reconciliation, disputes, or UI;
- mark Ticket 8C implementation-ready before vendor confirmation.
