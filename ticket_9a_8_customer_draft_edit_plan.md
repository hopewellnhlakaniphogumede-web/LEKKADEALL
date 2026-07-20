# Ticket 9A-8 — Customer draft edit plan

## Status

Planning only. This document does not add a migration, function, grant, frontend route, component, RPC call, test, credential, or draft-edit capability.

Customer draft editing remains unavailable until a future implementation ticket satisfies the database, frontend, test, documentation, and CI requirements below.

## Goal

Plan a trusted customer-owned draft update workflow after:

- Ticket 9A-3 introduced draft-only creation;
- Ticket 9A-5 made server-side validation authoritative for every eventually public text field;
- Ticket 9A-6 added safe own-request list/detail reads; and
- Ticket 9A-7 added database-enforced draft-only cancellation.

The future workflow may update only one authenticated active customer's own request while its locked database state is exactly `draft`. It must never rely on a rendered status, URL parameter, Auth metadata, or frontend-only condition as authority.

Publication, exact-address handling, provider interaction, bookings, payments, profile editing, and admin functionality remain outside Ticket 9A-8.

## Existing security foundation

The future implementation must preserve these existing boundaries:

1. `public.service_requests` is RLS-protected, and browser roles have no approved direct application-table insert/update/delete path for this workflow.
2. `customer_create_draft_request(...)` creates drafts through a trusted function.
3. `private.canonicalize_service_request_public_field(...)` and `private.assert_service_request_public_fields(...)` are the Ticket 9A-5 authoritative boundary for `title`, `description`, `suburb`, and `city`.
4. `private.enforce_service_request_public_fields()` is the table-trigger backstop for public-field writes.
5. The deprecated `public.service_requests.precise_address_ciphertext` column must remain null, and exact-address material belongs only to the separately controlled Ticket 5 boundary.
6. Ticket 6 protects workflow fields and state transitions. A draft edit must not change status or enable the internal state-transition flag.
7. Ticket 9A-7 demonstrates the required profile-lock, request-lock, ownership, exact-draft, consistency, restrictive-grant, safe-error, and audit-rollback pattern.
8. The Ticket 9A-6 detail projection already provides the editable public fields without customer IDs, address data, bid data, booking data, payment data, or audit data.

## Executive decisions

### Add a purpose-specific trusted function

A future reviewed migration should add:

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
)
returns uuid
```

`p_budget_minor` is required as a named argument but may be SQL `NULL` to represent “budget not specified.” No parameter has patch/omission semantics.

The function should accept the **complete replacement set** of reviewed editable fields. It should not accept nullable “leave unchanged” parameters or a JSON patch because those designs create ambiguity, broaden the input surface, and make full-result validation easier to bypass accidentally.

The returned UUID is only a transaction acknowledgement. The frontend must re-read the request through the existing RLS-backed detail query before displaying saved values or a confirmed-success state.

### Use a separate edit route

The recommended frontend is a dedicated static-shell-compatible route:

```text
/app/customer/requests/edit/?requestId=<uuid>
```

This keeps edit loading, validation, mutation, ambiguity, and unsaved-state handling separate from Ticket 9A-7 cancellation. The existing detail page may expose an `Edit draft` link only after a fresh RLS-backed read confirms `status = 'draft'` for an active customer.

An inline edit mode on the detail page is not recommended for the first implementation because cancellation and edit mutation state would share one screen and increase stale-state and double-action risk.

## Security invariants

The future implementation must preserve all of these invariants:

1. `auth.uid()` is the sole actor identity.
2. No customer ID, role, account status, request status, provider ID, bid ID, booking ID, audit reason, audit metadata, address value, or authority flag is accepted from the client.
3. The protected actor profile is locked before relying on `role` or `account_status`.
4. The request is selected and locked using both `id = p_request_id` and `customer_id = auth.uid()`.
5. The locked request status must be exactly `draft`.
6. Every existing or future non-draft status is rejected at the database boundary.
7. Draft workflow timestamps and deprecated public address state must be internally consistent.
8. A draft with any bid or booking is rejected; the edit path must not alter provider or booking state.
9. Only the seven reviewed editable business fields may change. `updated_at` is the only system-managed field that may also advance.
10. Ticket 9A-5 canonicalization and validation run against the complete resulting `title`, `description`, `suburb`, and `city` set before the update.
11. The Ticket 9A-5 table trigger remains a second fail-closed backstop.
12. Status, ownership, workflow timestamps, address fields, publication state, bids, bookings, payments, and audit history cannot be changed by the edit payload.
13. The update and its fixed audit event succeed or roll back atomically.
14. An ambiguous frontend result is never retried automatically and is never labelled successful without a fresh RLS read.

## Recommended backend function contract

### Function properties

Recommended properties for the future migration:

```text
schema: public
name: customer_update_draft_request
arguments: uuid, uuid, text, text, text, text, timestamptz, integer
return: uuid
language: plpgsql
volatility: VOLATILE
security: SECURITY DEFINER
search_path: pg_catalog only
```

The function must:

- explicitly schema-qualify every `auth`, `public`, `private`, and `pg_catalog` reference;
- contain no dynamic SQL;
- use no `select *`;
- trust no raw Auth/JWT metadata for role, status, or ownership;
- revoke default execution from `PUBLIC`;
- revoke execution from `PUBLIC`, `anon`, and `service_role`;
- grant execution only to `authenticated`;
- add no direct table grant or RLS policy;
- leave all private Ticket 9A-5 validators non-executable by browser roles; and
- leave the legacy cancellation and publication grants unchanged or more restrictive.

### Required transaction flow

The function should perform these steps in order:

1. Reject null `p_request_id` and null `p_category_id` using fixed safe messages.
2. Resolve `v_actor_id := auth.uid()` and reject a missing actor.
3. Select `role` and `account_status` from `public.profiles` using `id = v_actor_id`, and lock that profile row with `FOR SHARE` or an equivalent lock that conflicts with a concurrent role/status update.
4. Require exactly `role = 'customer'` and `account_status = 'active'`.
5. Select only the required current request fields using `id = p_request_id` and `customer_id = v_actor_id`, then lock the row `FOR UPDATE`.
6. Use the same generic failure for a missing and cross-customer request.
7. Require `status = 'draft'` exactly.
8. Reject an inconsistent draft if any of `closes_at`, `published_at`, `awarded_at`, or `cancelled_at` is non-null.
9. Reject an inconsistent draft if the deprecated `public.service_requests.precise_address_ciphertext` value is non-null. Do not read, return, insert, update, or delete a row from `private.service_request_addresses`.
10. Reject the draft if any `public.bids` row references it. This covers submitted bids and accepted/provider-selection evidence without mutating provider state.
11. Reject the draft if any `public.bookings` row references it.
12. Select and lock the proposed `public.service_categories` row, requiring `id = p_category_id` and `active = true`. The lock should conflict with concurrent deactivation while the update is being decided.
13. Validate `p_requested_start` as non-null and strictly in the future at the time of the locked update.
14. Validate `p_budget_minor` as either null or a non-negative PostgreSQL integer. Any future product maximum must be a reviewed server rule, not a frontend-only rule.
15. Canonicalize all four public text inputs with `private.canonicalize_service_request_public_field(...)`.
16. Call `private.assert_service_request_public_fields(...)` once with the complete canonical title, description, suburb, and city set.
17. Compare the canonical proposed values with the current locked values. Reject a complete no-op with a fixed safe validation error so it does not advance `updated_at` or create audit noise.
18. Update only `category_id`, `title`, `description`, `suburb`, `city`, `requested_start`, `budget_minor`, and server-controlled `updated_at`.
19. Repeat `id`, `customer_id`, exact `status = 'draft'`, consistency, and deprecated-address-null conditions in the defensive update predicate; require exactly one changed row.
20. Append exactly one fixed privacy-safe audit event in the same transaction.
21. Return only `p_request_id` after the update and audit both succeed.

The function must **not** enable `lekkadeall.allow_marketplace_state_transition`. Editing public draft content is not a state transition. If the edit requires that flag, the implementation has crossed the intended boundary and must stop for review.

### Lock ordering and concurrency

Use one documented lock order consistently:

```text
actor profile → owned request → active category
```

Expected race behavior:

- If edit locks the draft first, it may commit the validated content update; later cancellation or publication must re-evaluate the request state.
- If cancellation locks first and changes the request to `cancelled`, edit must reject the now non-draft row.
- If publication locks first and changes the request to `open`, edit must reject the now non-draft row.
- If an account role/status change obtains its conflicting profile lock first, edit must re-evaluate and reject a caller who is no longer an active customer.
- If category deactivation obtains its conflicting lock first, edit must reject the inactive category.
- Two concurrent edits serialize. The second call must evaluate the current locked row and either apply its complete replacement or reject as a no-op; the UI must not claim conflict-free merging.

The browser is never the concurrency boundary.

## Allowed editable fields

| Field | Server rule | Frontend rule |
|---|---|---|
| `category_id` | Required active category UUID, checked and locked at mutation time | Select only from the fresh active-category result |
| `title` | Ticket 9A-5 canonicalization and authoritative structural/privacy validation | Reuse Ticket 9A-3 validation and privacy warning as defence in depth |
| `description` | Ticket 9A-5 canonicalization and authoritative structural/privacy validation | Reuse Ticket 9A-3 validation and privacy warning as defence in depth |
| `suburb` | Ticket 9A-5 canonicalization and authoritative structural/privacy validation | Single-line approximate area only |
| `city` | Ticket 9A-5 canonicalization and authoritative structural/privacy validation | Single-line approximate area only |
| `requested_start` | Required and strictly future at update time | Enter as SAST/UTC+2 and convert explicitly to a timestamp |
| `budget_minor` | Null or non-negative integer minor units | Convert ZAR text using string/integer logic only; no floating point |

The function accepts the complete values every time. It must never merge client input into hidden or non-editable fields.

## Blocked fields and actions

### Fields that must never be accepted by the update function or form

- `customer_id`, user ID, owner ID, role, or `account_status`;
- request `status`, `closes_at`, `published_at`, `awarded_at`, `cancelled_at`, `created_at`, or client-selected `updated_at`;
- `p_precise_address_ciphertext`, `precise_address_ciphertext`, street address, house/street number, complex, unit, room, stand, erf, plot, farm identifier, postcode tied to an exact address, gate/access code, GPS coordinates, map pin, latitude, or longitude;
- provider ID, provider-selection value, bid ID/status, booking ID/status, payment/refund/payout/dispute fields, or audit data;
- phone, email, WhatsApp, URL, social handle, or private contact field;
- card, CVV, bank-login, payment-method, cash, or off-platform payment field;
- arbitrary JSON, metadata, changed-field lists, audit reasons, or state-transition flags.

### Actions that remain blocked

- request publication or `customer_publish_request(...)`;
- exact-address submission, update, deletion, encryption, decryption, read, or reveal;
- `customer_upsert_service_request_address(...)`, address-read RPCs, KMS, GPS, or maps;
- direct application-table insert/update/upsert/delete;
- edit of open, awarded, cancelled, expired, booked, bid-bearing, provider-selected, missing, non-owned, or inconsistent requests;
- request deletion, duplication, reopening, archiving, status changes, or cancellation from the edit route;
- provider feed/onboarding/bidding/selection/contact;
- booking actions or completion;
- payments, checkout, cash/off-platform options, refunds, payouts/releases, disputes, reviews, support, consent, notifications, chat, or identity-provider code;
- profile editing or an admin dashboard;
- service-role clients, service-role keys, or any real credential in browser code.

## Validation rules

### Complete-result validation

Ticket 9A-5 validation is authoritative. The future function must canonicalize and validate all four eventually public text fields together even if only one appears changed. It must not validate only the changed field because a hostile client or legacy row could otherwise preserve unsafe content in the resulting draft.

The table trigger remains a second backstop; it does not replace the explicit function-level call.

### Title, description, suburb, and city

Use the existing Ticket 9A-5 rules without creating a weaker edit-specific validator:

- null/blank, character length, and byte limits;
- single-line title/suburb/city and approved multiline description rules;
- unsupported control characters;
- bidi, zero-width, soft-hyphen, and other forbidden invisible/formatting characters;
- markup, HTML, script-like, and dangerous encoded content;
- street/house numbers and property identifiers;
- unit, room, flat, apartment, complex, stand, erf, plot, or farm identifiers;
- GPS coordinates;
- South African phone numbers;
- emails, URLs, and social handles;
- WhatsApp/contact instructions; and
- access, gate, or security codes.

Safe South African locality and ordinary service-description false-positive behavior must remain identical to Ticket 9A-5. The frontend must not introduce a more permissive exception that the database does not share.

### Category

- Require a non-null UUID.
- Require a currently active category at mutation time.
- Do not trust a hidden input, URL value, stale label, or category cached from an earlier session.
- If the current historical category is inactive, the edit page may show `Category unavailable`, but submission remains disabled until the customer selects a fresh active category.

### Requested start

- Required.
- Must be strictly later than server `now()` at the locked update.
- Frontend label: `South Africa time (SAST, UTC+2)`.
- Convert with an explicit `+02:00` offset; do not silently use the browser timezone.
- Reject invalid/nonexistent date-time values and a value that becomes past while the form is open.

### Budget

- Optional; blank becomes SQL `NULL`.
- ZAR display/input only.
- Convert decimal text to integer minor units using string/integer logic, never binary floating point.
- Reject negatives, excess fractional digits, malformed separators, exponent notation, non-finite values, and PostgreSQL integer overflow.
- Do not show payment instructions, cash options, or off-platform payment text.

### Frontend privacy validation

Reuse the Ticket 9A-3 privacy warning and local detectors before calling the RPC. They remain defence in depth only. A skipped or modified JavaScript validator must not bypass the Ticket 9A-5 database boundary.

## Privacy-safe audit behavior

Append exactly one event only after a successful changed-row update and before returning:

```text
action: customer.service_request_draft_updated
object_type: service_request
object_id: request UUID converted to text
reason: Customer updated own draft service request
metadata: { request_id, changed_fields }
```

`changed_fields` may contain only a server-generated ordered subset of these literal names:

```text
category_id, title, description, suburb, city, requested_start, budget_minor
```

Audit requirements:

- `actor_id` comes only from `auth.uid()`;
- the reason is a server constant;
- changed-field names are computed from the locked old row and canonical proposed values;
- metadata contains no old or new values;
- do not log title, description, suburb, city, exact address, ciphertext, contact data, dates, budget amounts, category labels, Auth metadata, tokens, IP, user agent, bid, booking, or payment data;
- rejected and no-op calls create no success event;
- one successful update creates exactly one event; and
- audit failure rolls the request update back.

Rejected-attempt monitoring, if later required, needs a separate reviewed design and must not change the customer-facing error contract.

## Safe error messages

Database errors must be fixed and must not echo UUIDs, submitted text, matched substrings, category state, owner, current request status, bid/booking presence, SQL, policy names, table names, or validator internals.

Recommended server contract:

| Condition | SQLSTATE | Fixed message |
|---|---:|---|
| Missing authentication | `42501` | `Authentication is required to update a draft` |
| Null request ID | `22023` | `Draft request ID is required` |
| Null category ID | `22023` | `Service category is required` |
| Missing/inactive/non-customer profile | `42501` | `Draft update is unavailable` |
| Missing, cross-customer, non-draft, inconsistent, bid-bearing, or booked request | `42501` | `Draft is not available for update` |
| Inactive/missing category | `22023` | `Service category is unavailable` |
| Invalid start | `22023` | `Requested start must be in the future` |
| Invalid budget | `22023` | `Budget is invalid` |
| No effective change | `22023` | `No draft changes were provided` |
| Unsafe public field | existing Ticket 9A-5 SQLSTATE/message contract | Do not echo the value or matched pattern |

Recommended frontend outcomes:

| Situation | UI behavior |
|---|---|
| Signed out/expired | Existing sign-in-required state |
| Restricted/wrong role | Existing restricted/access-denied state |
| Malformed, missing, hidden, or non-editable request | Generic `Draft not found or unavailable` state |
| Definite validation failure | Fixed field guidance without raw server detail |
| Definite state/ownership rejection | `This draft is not available for editing.` |
| Network, timeout, or ambiguous response | `The update could not be confirmed. Refresh the draft before trying again.` |
| RPC acknowledgement plus successful fresh read | `Draft updated.` and render only the fresh server values |

Do not automatically retry an ambiguous mutation.

## Frontend route and component plan

### Route map

| Route | Access | Planned Ticket 9A-8 behavior |
|---|---|---|
| `/app/customer/requests/detail/?requestId=<uuid>` | Active customer and own RLS-visible request | Show `Edit draft` only for a fresh `draft`; keep Ticket 9A-7 cancellation separate |
| `/app/customer/requests/edit/?requestId=<uuid>` | Active customer and own fresh `draft` only | Load, edit, validate, submit once, re-read, and display confirmed result |
| `/app/customer/requests/` | Active customer | No edit form or mutation control in the initial implementation |
| `/auth/sign-in` | Public | Existing destination for signed-out/expired sessions |
| `/access-denied` | Safe public state | Wrong/missing/unknown role/profile |
| `/account-restricted` | Restricted signed-in account | No request read or mutation |

Only the opaque validated request UUID may enter the edit URL. No request content or form value belongs in the path, query string, fragment, navigation state persisted to disk, or referrer-generating external link.

### Proposed components

- `CustomerDraftEditPage` — owns guarded load, in-memory form state, validation, mutation, and fresh-read confirmation.
- `DraftEditRouteState` — safe loading, not-found/unavailable, signed-out, restricted, access-denied, ready, submitting, ambiguous, and confirmed states.
- `ActiveCategorySelect` — reuses the active `id,slug,name` category read.
- `PublicContentFields` — title and description with Ticket 9A-3 warning and validation.
- `ApproximateAreaFields` — suburb and city only.
- `RequestedStartField` — explicit SAST input and conversion.
- `ZarBudgetField` — optional budget with string/integer minor-unit conversion.
- `DraftEditReview` — shows only the seven reviewed proposed fields as escaped text.
- `DraftEditActions` — `Discard changes` and `Save draft changes`; no publish, address, payment, provider, or cancellation action.
- `DraftEditBlockedNotice` — explains that exact address and publication remain unavailable.

### Allowed reads

Use only existing Ticket 9A-2/9A-6 boundaries:

```text
profiles: id,role,account_status (own row only)
service_categories: id,slug,name where active = true, bounded
service_requests: id,category_id,title,description,suburb,city,requested_start,budget_minor,status,created_at,updated_at
```

The request detail read must:

- validate the UUID before querying;
- use existing RLS for ownership;
- constrain to `status = draft` for the edit route;
- use `maybeSingle()` semantics; and
- collapse malformed, missing, cross-customer, non-draft, unsupported, and RLS-hidden IDs into one unavailable result.

Do not select `customer_id`, workflow timestamps, precise-address fields, private address data, bids, bookings, payments, audit data, or provider data. Do not use `select('*')`.

### Submission flow

1. Run the existing session and protected-profile guard.
2. Validate the route UUID.
3. Perform a fresh RLS-backed detail read restricted to `draft`.
4. Load active categories.
5. Initialize form state from the fresh safe projection in memory only.
6. Reuse Ticket 9A-3 local validation and privacy warnings.
7. Convert requested start with explicit SAST offset and budget with string/integer logic.
8. Disable submit unless a reviewed field changed and all local validation passes.
9. Revalidate session, profile, route UUID, loaded draft ID/status, category membership, and form state immediately before mutation.
10. Call only `customer_update_draft_request` with all eight named arguments.
11. Use an in-memory single-flight guard and disable both save/discard actions while pending.
12. Do not optimistically mutate the detail cache, list cache, status, or timestamps.
13. Do not automatically retry a transport error, timeout, or ambiguous result.
14. After the RPC returns the expected request UUID, perform a fresh RLS-backed detail read.
15. Show `Draft updated.` only when the fresh row has the same ID and remains `draft`; render only the fresh server-canonical values.
16. If the fresh read does not confirm the row, show the ambiguous message and block resubmission until the customer refreshes/reloads the edit route.
17. Clear all form and mutation state on discard, navigation away, sign-out, session expiry, role/status change, or route-ID change.

The form and server response must not be written to `localStorage`, `sessionStorage`, IndexedDB, service-worker caches, URLs, logs, analytics, telemetry, or error reports.

## Test matrix for a future implementation

### pgTAP contract and permissions

- Function exists with the exact eight-argument signature and returns `uuid`.
- Function is `SECURITY DEFINER`, `VOLATILE`, and fixed to `search_path = pg_catalog`.
- Function uses `auth.uid()`, explicit schema qualification, profile/request/category locks, and no dynamic SQL or `select *`.
- `PUBLIC`, `anon`, and `service_role` cannot execute it; only `authenticated` can enter the boundary.
- Authenticated users retain no direct request insert/update/delete table privilege usable by the frontend.
- Private Ticket 9A-5 helpers remain non-executable by browser roles.
- Legacy cancellation remains unavailable to `authenticated`; publication grants are not broadened.

### Authentication, role, status, and ownership

- Signed-out execution is rejected.
- Missing profile is rejected.
- Provider, support, and admin profiles are rejected.
- Restricted, suspended, closed, and unknown/non-active customer status is rejected.
- Hostile Auth metadata claiming customer/active/ownership has no effect.
- An active customer cannot update another customer's draft.
- Missing and cross-customer IDs produce the same safe error.

### Successful complete update

- An active customer can update all seven reviewed fields on one owned valid draft.
- Each reviewed field can be changed individually while the complete resulting set is revalidated.
- The function returns only the same request UUID.
- Category, title, description, suburb, city, requested start, budget, and `updated_at` reflect server-approved values.
- `customer_id`, status, workflow timestamps, creation timestamp, deprecated address column, and every unrelated column remain unchanged.
- Budget can be changed from null to an integer, integer to another integer, and integer to null.
- Canonical whitespace/NFC/line-ending behavior matches Ticket 9A-5.
- Safe South African false-positive fixtures remain accepted.
- A no-op is rejected and does not change `updated_at` or create an audit event.

### Authoritative validation

- Null/blank/overlength/over-byte public fields are rejected.
- Line-break, control, bidi, invisible, markup, and script-like hostile inputs are rejected.
- Exact address/property/unit/room/complex, GPS, South African phone, email, URL, social/contact, WhatsApp, and access-code fixtures are rejected in every applicable public field.
- A hostile client bypassing JavaScript still receives database rejection.
- Invalid complete input changes no request row and creates no audit event.
- Inactive/missing category, past/null requested start, negative budget, and integer overflow are rejected.
- The table trigger still rejects unsafe direct/internal public-field writes independently of the RPC.

### Strict draft and consistency rejection

- `open`, `awarded`, `cancelled`, and `expired` are rejected and unchanged.
- Every future non-draft status is rejected by the exact status predicate.
- Drafts with `closes_at`, `published_at`, `awarded_at`, or `cancelled_at` residue are rejected.
- A draft with deprecated public `precise_address_ciphertext` residue is rejected.
- A draft with any bid is rejected.
- A draft with an accepted/provider-selected bid is rejected.
- A draft with any booking is rejected.
- Rejections do not change request, bid, booking, payment, address, or audit state.

### Audit, rollback, and concurrency

- Exactly one successful edit produces exactly one fixed audit event.
- Actor, action, object type, object ID, fixed reason, and allowlisted changed-field names are exact.
- Audit metadata contains no old/new values, request text, locality, date, amount, address, contact, Auth metadata, token, bid, booking, or payment data.
- Rejected and no-op calls produce no success event.
- A forced audit failure rolls back the request update.
- Concurrent edit/cancel and edit/publish paths serialize on the request row; edit cannot commit after the row becomes non-draft.
- Concurrent role/account-status change conflicts with the profile lock.
- Concurrent category deactivation conflicts with the category lock.
- Two concurrent edits do not merge hidden or stale fields silently.

### Ticket regression coverage

- Ticket 1 role/account-status protections remain intact.
- Ticket 2 RLS and direct-DML denial remain intact.
- Ticket 5 deprecated/public and private exact-address protections remain intact.
- Ticket 6 workflow-state protections remain intact without using the transition flag.
- Ticket 9B profile provisioning remains unchanged.
- Ticket 9A-5 validator permissions, hostile fixtures, false-positive fixtures, and trigger backstop remain green.
- Ticket 9A-7 strict cancellation remains green before and after a valid edit.
- Payment, refund, payout, and webhook ledgers remain unchanged.

### Frontend tests

- Edit route is registered and guarded for active customers only.
- Edit link appears only on a fresh own `draft` detail and not on list, open, cancelled, unavailable, signed-out, wrong-role, or restricted states.
- Route UUID is validated before reads or RPC calls.
- Exact request and category projections are used; no `select('*')` or blocked column is present.
- Form contains only category, title, description, suburb, city, requested start, and budget.
- Existing privacy detection, SAST conversion, and ZAR integer-minor conversion are reused and regression-tested.
- RPC name is exactly `customer_update_draft_request` and the payload contains exactly the eight approved keys.
- Payload contains no customer ID, status, address/ciphertext, provider, bid, booking, audit, payment, or metadata field.
- Single-flight behavior prevents duplicate submissions.
- No optimistic mutation or automatic retry exists.
- Fresh RLS re-read is required before success and supplies the rendered canonical values.
- Ambiguous results block another submission until a fresh route read.
- Database errors remain generic and do not echo submitted or internal data.
- No request/form content enters browser persistence, URLs, logs, analytics, telemetry, or error reports.
- No direct application-table insert/update/upsert/delete exists.
- No publish, address, cancellation, provider, booking, payment, admin, profile-editing, private, or webhook RPC is called from the edit module.
- Existing Ticket 9A-1 through 9A-7 frontend tests remain green.

## Future implementation sequence

1. Add one reviewed migration for the trusted update function and restrictive execute privileges.
2. Add the focused pgTAP suite and run it after the Ticket 9A-5 and Ticket 9A-7 suites in CI.
3. Implement the protected edit route and clean-path entry file.
4. Reuse/refactor Ticket 9A-3 validation utilities without weakening them.
5. Add the reviewed RPC client boundary and single-flight/fresh-read orchestration.
6. Add frontend behavior and static security tests.
7. Update `README.md`, `TESTING.md`, `rls_policy_matrix.md`, and `hardening_progress.md`.
8. Require a green migration reset, focused pgTAP suite, every existing pgTAP suite, frontend suite, and Deno webhook suite before marking Ticket 9A-8 CI-verified.

## Definition of done for a future implementation ticket

Ticket 9A-8 implementation is complete only when all of the following are true:

1. The new function has the exact full-replacement contract and accepts no authority, state, address, provider, booking, payment, or audit parameter.
2. It uses `auth.uid()`, a locked protected profile, a locked owned request, an active-category check/lock, explicit schemas, fixed `pg_catalog` search path, and no dynamic SQL or `select *`.
3. Only authenticated active customers can update their own exact draft.
4. Open, awarded, cancelled, expired, future non-draft, inconsistent, bid-bearing/provider-selected, and booked requests are rejected at the database boundary.
5. Only category, title, description, suburb, city, requested start, budget, and server-controlled `updated_at` can change.
6. Ticket 9A-5 canonicalization and validation run against the complete resulting public-field set, with the table trigger retained as a backstop.
7. Exact-address parameters, collection, storage, encryption, reveal, KMS, GPS, and maps remain absent and blocked.
8. Publication remains blocked and the edit frontend never calls `customer_publish_request(...)`.
9. The fixed privacy-safe audit event is atomic with the update and contains no field values or private data.
10. The frontend exposes edit only from a fresh own-draft detail, calls only the reviewed update RPC, uses single-flight behavior, performs no optimistic mutation/retry, and requires a fresh RLS read before success.
11. No direct frontend table DML, `select('*')`, service-role key, credential, provider workflow, booking action, payment workflow, profile editing, or admin dashboard is added.
12. No RLS, grant, role/status, address-privacy, public-field-validation, or state-machine protection is weakened.
13. Focused pgTAP and frontend tests cover the full contract, authority, validation, state, consistency, audit, rollback, concurrency, privacy, and blocked capabilities.
14. All existing frontend, Deno webhook, migration, and pgTAP suites pass in GitHub Actions.
15. Documentation records the exact files, migration/function contract, UI behavior, tests, CI result, and every intentionally blocked feature.

Until every item is satisfied, customer draft editing remains unavailable.
