# Ticket 9A-3 — Customer request creation plan

## Status

Planning only. This document does not implement UI, add a frontend RPC call, change the database, or enable request publication.

## Goal

Plan the first authenticated customer request-creation workflow using the existing trusted `public.customer_create_draft_request(...)` function. The future implementation may create a safe **draft only**. It must not collect an exact address, publish the request, or perform a direct application-table write.

This ticket extends the Ticket 9A-2 Auth and safe-read boundary. Session, role, and `account_status` remain authoritative only when resolved from the signed-in user's RLS-protected `public.profiles` row.

## 1. Security decisions and release boundary

1. The only marketplace mutation planned for Ticket 9A-3 is draft creation through `customer_create_draft_request(...)`.
2. The caller must be an authenticated profile with `role = 'customer'` and `account_status = 'active'`.
3. `p_precise_address_ciphertext` must always be passed as `null`. The UI must not display an exact-address input or relabel plaintext as ciphertext.
4. The draft remains in `status = 'draft'` after creation.
5. `customer_publish_request(...)` remains blocked because the existing backend requires a safely stored private address before publication and the client/server encryption boundary has not been verified.
6. `customer_upsert_service_request_address(...)`, address reads, and address reveal functions remain blocked.
7. No direct `insert`, `update`, `upsert`, or `delete` against `service_requests` or any other application table is permitted.
8. The current draft-creation RPC has no client idempotency key. The future UI must prevent double submission and must never automatically retry an ambiguous request.
9. Title, description, suburb, and city are treated as potentially public content even while the row is still a draft.

## 2. Existing backend contract

The existing trusted mutation is:

```sql
public.customer_create_draft_request(
  p_category_id uuid,
  p_title text,
  p_description text,
  p_suburb text,
  p_city text,
  p_requested_start timestamptz,
  p_budget_minor integer default null,
  p_precise_address_ciphertext text default null
) returns uuid
```

The function already verifies that:

- the caller is authenticated;
- the caller has an active customer profile;
- the category exists and is active;
- the requested start is in the future;
- the optional budget is not negative;
- the created row starts as `draft`;
- direct workflow table mutation remains blocked;
- an audit event is written by the trusted backend.

The underlying table constrains title length to 3–120 characters and description length to 10–3000 characters. Client validation must mirror those limits, but backend rejection remains authoritative.

Important limitation: the backend exact-address risk check is enforced when a request becomes open, not as a complete guarantee for every draft field. In particular, the public title is not covered by the existing description detector. Ticket 9A-3 therefore creates drafts only, validates all public text before transmission, and keeps publishing blocked. A future publication ticket must review server-side coverage for every public field before enabling publication.

## 3. Route map

| Route | Access | Ticket 9A-3 behavior | Data/function boundary |
|---|---|---|---|
| `/app/customer` | Active customer | Add a “Create request draft” entry point | Existing safe dashboard reads only |
| `/app/customer/requests/new` | Active customer only | Multi-step draft form and draft-created result | Active categories, own route profile, privacy preflight if used, and `customer_create_draft_request(...)` only |
| `/auth/sign-in` | Public | Existing sign-in route when no valid session exists | Supabase Auth only |
| `/access-denied` | Public safe state | Missing profile, wrong role, unknown role, or inactive unrecognised status | No request read or mutation |
| `/account-restricted` | Restricted signed-in account | Restricted/suspended/closed state | No request read or mutation |

Ticket 9A-3 must not add:

- an address route;
- a publish route or publish button;
- a provider route or provider onboarding route;
- an admin route;
- a bid, booking, payment, refund, payout, dispute, review, support, consent, notification, or chat route.

If a signed-out user navigates directly to `/app/customer/requests/new`, show the existing signed-out state and sign-in link. Do not preserve form content in a query string or browser storage. After sign-in, the customer may intentionally restart the form.

## 4. Page and component design

### `CustomerRequestCreatePage`

Responsibilities:

- invoke the existing Ticket 9A-2 session/profile guard;
- render only for an active customer;
- load active categories through the existing safe category read;
- keep unsaved form state in memory only;
- coordinate validation and a single trusted draft-creation call;
- show safe loading, empty, validation, submitting, success, and generic failure states.

### Proposed steps

1. **Service category** — select one active category returned by the safe category query.
2. **Public job summary** — enter title and description beneath a persistent privacy warning.
3. **Approximate area** — enter suburb and city only.
4. **Schedule and budget** — enter requested start in SAST and an optional ZAR budget.
5. **Review and create draft** — show the exact public fields and the converted budget; call the trusted function once.
6. **Draft created** — show the returned request ID or safe public reference if one becomes available through an approved read model, state that it remains private as a draft, and explain why publication is unavailable.

### Components

- `RequestCreationProgress` — identifies the current non-sensitive step.
- `ActiveCategorySelect` — category ID, name, and slug from active categories only.
- `PublicContentFields` — title and description with character counters.
- `PublicContentPrivacyWarning` — persistent warning beside public text fields.
- `ApproximateAreaFields` — suburb and city only; no street, building, unit, room, landmark pin, or GPS fields.
- `RequestedStartField` — labelled “South Africa time (SAST, UTC+2)”.
- `ZarBudgetField` — text input with decimal input mode; conversion does not use floating-point arithmetic.
- `DraftReviewPanel` — safe summary of exactly what will be submitted.
- `DraftSubmitButton` — disabled while invalid or in flight; says “Create private draft”, never “Publish”.
- `DraftCreatedPanel` — success message, read-only draft summary, and blocked-publication explanation.
- `AddressAndPublishingBlockedNotice` — no inputs; explains that the exact-address and publication steps are unavailable until the encryption boundary is approved.

There must be no exact-address field, hidden address field, map, geolocation request, file upload, contact field, or payment control anywhere on this page.

## 5. Allowed reads

The future implementation may use only these existing safe reads:

| Source | Explicit projection/purpose | Conditions |
|---|---|---|
| Supabase Auth session | Current session and user ID | Existing Ticket 9A-2 Auth boundary |
| `public.profiles` | `id,role,account_status` | Own row only; route authority |
| `public.service_categories` | `id,slug,name` | `active = true`, ordered and bounded as in Ticket 9A-2 |
| `public.service_requests` | Existing explicit own-request safe projection | Own RLS-visible row only, after creation; no broad select and no exact-address field |

The implementation must not use `select('*')`.

Blocked reads include:

- `private.service_request_addresses`;
- deprecated `service_requests.precise_address_ciphertext`;
- customer or provider profiles other than the caller's allowed own profile;
- address, identity, audit, vendor-event, payment-event, refund-event, payout, dispute, support, consent, review, notification, or chat data;
- provider feed or bid data;
- admin/private schemas or functions.

If an allowed read is denied by existing RLS or column grants, show a safe placeholder and document the blocker. Do not change RLS, grants, policies, or projections to work around it.

## 6. Allowed trusted function calls

### Required mutation

The only allowed marketplace mutation is:

```js
supabase.rpc('customer_create_draft_request', {
  p_category_id: selectedCategoryId,
  p_title: trimmedTitle,
  p_description: trimmedDescription,
  p_suburb: trimmedSuburb,
  p_city: trimmedCity,
  p_requested_start: requestedStartSastIso,
  p_budget_minor: budgetMinorOrNull,
  p_precise_address_ciphertext: null,
})
```

The explicit final argument is a safety invariant. It must be tested as `null`; omitting it must not become a future opportunity to insert address data implicitly.

### Optional read-only privacy preflight

After local privacy checks pass, the implementation may call the existing authenticated function:

```text
service_request_description_has_exact_address_risk(text)
```

If used, a `true` result blocks draft creation. A failure of the preflight fails closed rather than proceeding. This function is supplemental: it does not replace local warnings or validation, and it does not cover every possible disclosure or the title field.

No other application RPC is allowed in Ticket 9A-3. Specifically blocked:

- `customer_publish_request(...)`;
- `customer_upsert_service_request_address(...)`;
- `customer_get_service_request_address(...)`;
- `reveal_confirmed_booking_address(...)`;
- request cancellation or bid acceptance;
- admin, provider, payment, refund, payout, dispute, identity, support, webhook, private, or mock-payment functions.

## 7. Blocked fields and actions

### Fields that must not exist

- street address, street number, complex/building, floor, unit, room, house, stand, erf, postcode tied to an address, landmark instructions, gate/access code, GPS coordinates, map pin, latitude, or longitude;
- `precise_address_ciphertext` input of any kind;
- customer phone, email, WhatsApp, social handle, or other private contact field;
- role, `account_status`, provider approval, verification/review status, customer ID, request status, close time, published time, or audit fields;
- card, CVV, bank-login, payment method, cash, or off-platform payment fields.

### Actions that remain blocked

- publish, open, cancel, edit, or delete the created request;
- exact-address save, encryption, reveal, or decryption;
- direct application-table insert/update/upsert/delete;
- automatic retry of draft creation;
- provider onboarding, bidding, booking completion, refund, payout/release, dispute, review, support, consent, notification, chat, identity, or payment actions;
- admin or service-role operations.

## 8. Validation rules

Validation improves usability and privacy but never replaces backend authorization or constraints.

### Category

- Required UUID selected from the currently loaded active-category result.
- Do not accept a category ID typed into the URL, hidden field, or restored storage without confirming it is still in the active result.
- Revalidate on submit; the backend remains authoritative if a category becomes inactive.

### Public title

- Trim leading and trailing whitespace.
- Required; 3–120 Unicode characters after trimming.
- Reject control characters and line breaks.
- Run the local privacy-risk checks applied to public description, including phone, GPS, street-number, unit/room, house/stand/erf, email, URL, and social/contact patterns.
- Clearly label it “Public job title”.

### Public description

- Trim leading and trailing whitespace.
- Required; 10–3000 Unicode characters after trimming.
- Preserve ordinary paragraph breaks but reject control characters other than approved newline/tab handling.
- Block locally recognised exact-address, phone, GPS, unit/room, house/stand/erf, email, URL, access-code, or private-contact patterns before any RPC.
- If the existing backend description-risk preflight is used, require a safe result before draft creation.
- Clearly label it “Public description”.

### Suburb and city

- Both required and trimmed.
- Plan a conservative UI limit of 2–120 characters for each because the current table does not define equivalent length constraints.
- Single-line text only; reject control characters.
- Reject content that appears to include a street address, street number, unit/room, GPS coordinate, phone number, access code, email, or contact instruction.
- Labels must say “Suburb only” and “City only”.
- Do not combine these fields with a street-address autocomplete or map provider in Ticket 9A-3.

### Requested start

- Required.
- Input and confirmation must state “South Africa time (SAST, UTC+2)”.
- Convert a validated local calendar value to an ISO 8601 timestamp carrying the explicit `+02:00` offset; do not depend silently on the browser's timezone.
- Reject invalid calendar values and times not strictly in the future.
- Use a small client safety buffer, such as 15 minutes, to reduce race-condition failures; the backend's `> now()` check remains authoritative.
- Revalidate immediately before submission.

### Budget

- Optional; blank becomes `null`.
- Label as ZAR and use a text input with `inputmode="decimal"`; do not rely on an HTML number value or binary floating-point multiplication.
- Accept only ASCII digits with an optional decimal point and one or two decimal digits, for example `1500`, `1500.5`, or `1500.50`.
- Reject signs, exponent notation, commas, spaces, currency symbols, more than two decimal places, and negative values.
- Convert using string parts: `major * 100 + paddedMinor`, using integer/BigInt-safe logic.
- Require the result to fit the PostgreSQL `integer` range and therefore not exceed `2147483647` minor units (`ZAR 21,474,836.47`).
- `0` is valid because the current trusted backend permits a non-negative budget; the UI must not reinterpret it as cash or an off-platform arrangement.

### Submit behavior

- Validate every field again at submit time.
- Disable the submit button and enforce an in-memory single-flight guard while the RPC is pending.
- Send one RPC call only.
- Do not optimistically display success before receiving the request UUID.
- Do not automatically retry timeouts or network failures. An ambiguous result must tell the customer to refresh their own draft list before attempting another submission.
- After success, discard the unsaved in-memory form content and render a safe draft confirmation.

## 9. Privacy rules and customer warnings

The following warning must remain visible beside the title/description and again in the review step:

> This title and description may later be shown to service providers. Do not include your exact address, street or house number, complex, unit or room number, GPS location, phone number, email address, access code, or private contact details. Enter suburb and city only.

Additional rules:

- Never place form values in URLs, query parameters, route state visible in history, referrers, logs, analytics, error reports, console output, or telemetry.
- Do not persist form values in `localStorage`, `sessionStorage`, IndexedDB, service-worker caches, or offline queues.
- Do not include public text or location values in thrown error messages.
- Do not echo raw Supabase/PostgREST error details to the customer.
- Do not request browser geolocation.
- Do not infer or enrich an exact address from suburb/city.
- Do not introduce third-party address, map, analytics, or support widgets on this form without a separate privacy review.
- Treat local pattern detection as defence in depth, not a guarantee. Publication remains blocked until backend public-field validation and the encryption boundary are both approved.

## 10. Safe error handling

Map failures to a small allowlist of user-safe outcomes:

| Condition | User-facing behavior |
|---|---|
| Signed out/expired | Clear form state and show the existing sign-in-required state |
| Missing profile or wrong role | Access denied; no RPC call |
| Restricted/suspended/closed | Account restricted; no RPC call |
| Category unavailable | Ask the customer to choose from refreshed active categories |
| Start not in future | Return to schedule step with a safe validation message |
| Public-content privacy risk | Identify the field generically and repeat the no-private-details warning; do not echo the matched text |
| Constraint/validation rejection | Show a field-level safe message where known |
| Network/timeout/unknown error | “The draft could not be confirmed. Refresh your drafts before trying again.” |

Do not display SQLSTATE values, SQL, schema/table/policy/function internals, stack traces, access tokens, request payloads, or another record's existence. Error handling must not retry with a direct table write, broader role, service key, or different function.

## 11. Tests required for the future implementation ticket

No tests are added by this planning document. The future implementation must add or update tests in the existing Node test setup and keep every Deno webhook and pgTAP suite green.

### Unit tests

- title boundaries: 2/3/120/121 characters and whitespace-only values;
- description boundaries: 9/10/3000/3001 characters;
- suburb/city trimming, length limits, single-line enforcement, and rejected sensitive patterns;
- privacy detection for common South African phone formats, street numbers, unit/room/house/stand/erf references, GPS coordinates, emails, URLs, access codes, and contact instructions in every public field;
- privacy-safe ordinary text is accepted without false mutation;
- SAST conversion includes explicit `+02:00`, rejects invalid dates, and rejects past/too-near values;
- budget conversions including blank → `null`, `0` → `0`, `0.01` → `1`, `12.3` → `1230`, and `1500.50` → `150050`;
- budget rejection for negative, comma-formatted, exponent, currency-symbol, whitespace, more-than-two-decimal, and integer-overflow values;
- safe error mapping never exposes raw errors or submitted content.

### Route/component tests

- signed-out, expired, missing-profile, restricted, suspended, closed, wrong-role, unknown-role, loading, category-empty, category-error, submitting, ambiguous-failure, and success states;
- only active categories appear and the submitted ID must be from the loaded allowlist;
- no exact-address, phone, GPS, map, geolocation, contact, payment, cash, or off-platform field/control exists;
- the persistent privacy warning contains every required prohibited detail;
- there is no publish button or publish/address function call;
- a successful response displays draft-only status and blocked-publication guidance;
- refresh/navigation does not recover sensitive unsaved form content from browser storage or URLs.

### RPC boundary tests

- the only marketplace mutation RPC is exactly `customer_create_draft_request`;
- the payload contains only the eight named parameters in the reviewed contract;
- `p_precise_address_ciphertext` is exactly `null` in every call;
- trimmed values and integer budget minor units are submitted;
- no customer ID, role, status, close time, published time, address, contact, or payment field is submitted;
- double-click and repeated submit events produce one in-flight call;
- a timeout or unknown result does not trigger an automatic retry;
- no direct application-table insert/update/upsert/delete is present;
- no `select('*')` is present;
- no other application RPC is present except an explicitly tested optional description-risk preflight;
- no admin/private/webhook/mock-payment/service-role module can be imported by the page.

### Integration and regression tests

- an active customer can create one draft and receives its UUID;
- the created row is owned by the authenticated customer and remains `draft`;
- category, requested-start, budget, role, and account-status backend rejections are handled safely;
- signed-out, provider, restricted, and cross-user attempts remain denied by existing backend protections;
- hostile metadata cannot change request ownership, role, or status;
- the deprecated public exact-address column remains null and the private address table receives no row from Ticket 9A-3;
- publication is never called and the draft cannot become open through this UI;
- Ticket 1, Ticket 2, Ticket 5, Ticket 6, Ticket 9B, Ticket 9A-1, and Ticket 9A-2 regressions remain green;
- all existing pgTAP database tests and Deno webhook tests remain green.

### Static safety scans

Update the frontend safety scan so that it permits only the reviewed Ticket 9A-3 RPC name in the request-creation module while continuing to reject:

- direct application-table DML;
- broad selects;
- address/private/admin/payment/webhook/provider functions;
- `/admin` routes;
- service-role keys and secret markers;
- real payment-provider SDKs or endpoints;
- exact-address/contact/payment form fields;
- browser-storage writes containing form data.

## 12. Definition of done for a future implementation ticket

The future Ticket 9A-3 implementation is complete only when:

1. `/app/customer/requests/new` exists and uses the Ticket 9A-2 session/profile guard.
2. Only an active customer can render and submit the form.
3. Category selection uses active `service_categories` with an explicit projection.
4. Title, description, suburb, city, requested SAST start, and optional ZAR budget follow the reviewed validation rules.
5. The required privacy warning is visible during entry and review.
6. No exact-address, GPS, phone, contact, map, payment, cash, or off-platform field exists.
7. Budget conversion uses string/integer logic and sends integer minor units or `null`.
8. The sole marketplace mutation is one call to `customer_create_draft_request(...)` with `p_precise_address_ciphertext = null`.
9. The returned request remains an own `draft`; no publication, cancellation, edit, address, provider, bid, booking, admin, identity, payment, refund, payout, dispute, review, support, consent, notification, or chat action is added.
10. No direct application-table insert/update/upsert/delete, broad select, or unapproved RPC is present.
11. Ambiguous failures never automatically retry, and safe error messages expose no payload or backend internals.
12. No form value is placed in URLs, logs, analytics, telemetry, or persistent browser storage.
13. Exact-address handling and `customer_publish_request(...)` remain visibly blocked until a separately reviewed encryption boundary and full public-field server validation are verified.
14. No service-role key, real credential, admin dashboard, provider onboarding, profile editing, migration, RLS/grant/policy/function change, real payment-provider code, checkout, or cash/off-platform UI is added.
15. New frontend unit, route, RPC-boundary, privacy, and regression tests pass.
16. All existing frontend, Deno webhook, migration, and pgTAP GitHub Actions steps remain green.

## 13. Explicit non-goals

Ticket 9A-3 does not implement UI or code. Its future implementation also does not authorize:

- exact-address collection, encryption, storage, or reveal;
- request publication, editing, cancellation, or deletion;
- provider onboarding or bidding;
- booking creation/completion;
- admin dashboard/actions;
- profile editing;
- identity verification;
- refunds, payouts, releases, disputes, reviews, consent, support, notifications, or chat;
- mock checkout controls or real payment-provider integration;
- cash or off-platform payment UI;
- credentials, service-role access, migrations, RLS changes, grants, policies, or database-function changes.
