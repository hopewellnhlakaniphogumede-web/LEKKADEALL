# Ticket 9A-7 — Customer draft cancellation plan

## Status

Planning only. This document does not add a migration, function, grant, frontend control, RPC call, test, credential, or cancellation capability.

Cancellation remains disabled until a future implementation ticket satisfies the database, frontend, test, and deployment requirements below.

## Goal

Plan a strict customer-owned **draft-only** cancellation workflow whose security boundary is enforced by a trusted database function rather than by conditional frontend rendering.

The future workflow may let an authenticated active customer cancel one owned request only while its locked database state is exactly `draft`. It must reject `open`, `awarded`, `cancelled`, `expired`, booked, provider-selected, inconsistent, missing, and cross-customer requests without revealing protected state.

Publication, exact-address handling, provider bidding, booking actions, payments, and all other sensitive workflows remain outside this ticket.

## Existing boundary and reason for a new function

The reviewed Ticket 6 function currently has this contract:

```text
customer_cancel_request(p_request_id uuid, p_reason text default null) returns void
```

It currently:

- is `SECURITY DEFINER`;
- locks the request row;
- verifies caller ownership;
- accepts both `draft` and `open` requests;
- rejects a request that already has a booking;
- changes the request to `cancelled` through the protected state-machine boundary;
- declines submitted bids;
- accepts caller-supplied audit-reason text; and
- is executable by `authenticated` and `service_role`.

That function is intentionally broader than Ticket 9A-7. Hiding a cancellation control for `open` requests would not stop an authenticated hostile client from calling the broader function directly. Therefore a frontend-only `status === 'draft'` rule cannot meet the strict draft-only goal.

Ticket 9A-6 correctly left cancellation unimplemented.

## Executive decision

Add a separate trusted function in a future reviewed migration:

```text
public.customer_cancel_draft_request(p_request_id uuid)
returns public.request_status
```

The new function is the only cancellation RPC that the future customer frontend may call. It accepts no reason, status, customer ID, provider ID, booking ID, audit metadata, or other client-controlled field.

The same migration must revoke `authenticated` execution of the broader legacy `customer_cancel_request(uuid,text)` function. Leaving that function callable by browser users would defeat the new strict boundary. It may remain available to `service_role` temporarily only if a real internal server-side caller is documented and tested; it must never be included in browser code or browser configuration. If no internal caller exists, revoke its `service_role` execution as well.

Future open-request cancellation, if required by product policy, must receive a separate reviewed server contract. It must not be reintroduced through the draft-only UI.

## Security invariants

The future implementation must preserve all of these invariants:

1. The browser can request cancellation only through `customer_cancel_draft_request(uuid)`.
2. `auth.uid()` is the sole actor identity. No user ID is accepted as a parameter.
3. The caller's protected `public.profiles` row must say `role = 'customer'` and `account_status = 'active'` at mutation time.
4. The function must lock the actor profile row before relying on role/status and lock the request row before evaluating or changing request state.
5. The locked request must be owned by `auth.uid()` and have status exactly `draft`.
6. Every non-draft status is rejected by the database, even if the UI is stale or bypassed.
7. A draft with a booking, accepted bid, provider-selection signal, or any inconsistent workflow residue fails closed.
8. The transition uses the existing Ticket 6 protected state-machine mechanism. Direct browser updates remain denied.
9. Cancellation, timestamp changes, and the audit event succeed or roll back atomically.
10. The caller cannot provide audit text or metadata.
11. The function returns only the safe final status and never returns another user's data, internal workflow details, audit IDs, private addresses, bid data, booking data, or payment data.
12. A second call is not idempotent success: after the first transition, the request is no longer a draft and must be rejected generically.

## Recommended backend function contract

### Signature and execution properties

Recommended contract:

```text
schema: public
name: customer_cancel_draft_request
arguments: p_request_id uuid
return: public.request_status
language: plpgsql
security: SECURITY DEFINER
volatility: VOLATILE
search_path: pg_catalog only
```

Implementation requirements for the future migration:

- use explicit schema qualification for every `auth`, `public`, and `private` object;
- use a fixed `search_path = pg_catalog`;
- do not use dynamic SQL;
- do not trust JWT/Auth metadata for application role or account status;
- do not use a client-provided reason or metadata object;
- do not use `select *` in the function; select only the fields required for the decision;
- revoke default `PUBLIC` execution before granting any browser role;
- revoke execution from `PUBLIC`, `anon`, and `service_role` for the new customer-only function;
- grant execution only to `authenticated`;
- retain the internal table triggers and state-transition guard; and
- add no new direct table grants or RLS policies.

An `authenticated` execute grant is only an entry point. The function must still perform every actor, profile, ownership, state, and related-record check itself.

### Required transaction flow

The future function should perform these steps in order:

1. Reject a null `p_request_id` with a fixed message.
2. Read `auth.uid()` and reject a missing actor.
3. Select the actor's `role` and `account_status` from `public.profiles` and lock that row with `FOR SHARE` or an equivalent lock that conflicts with a concurrent role/status update.
4. Require exactly `role = 'customer'` and `account_status = 'active'`.
5. Select the minimum required request fields using both `id = p_request_id` and `customer_id = auth.uid()`, then lock the row `FOR UPDATE`.
6. Use the same generic failure for missing and non-owned requests.
7. Require `status = 'draft'` exactly.
8. Fail closed if draft invariants are inconsistent, including non-null `published_at`, `awarded_at`, `cancelled_at`, or `closes_at`.
9. Reject the request if any booking references it.
10. Reject the request if an accepted bid, non-null `accepted_at`, or any other provider-selection evidence references it.
11. Recommended stronger invariant: reject a draft if **any** bid row references it. A valid draft cannot receive a bid, and this prevents the draft-only function from silently changing or deleting provider-side records in an inconsistent database state.
12. Enable the existing transaction-local `lekkadeall.allow_marketplace_state_transition` setting only immediately before the controlled update.
13. Update the locked row to `status = 'cancelled'`, set `cancelled_at` and `updated_at` to the server time, and keep every public/request-content field unchanged.
14. Use a defensive update predicate that repeats `id`, `customer_id`, and `status = 'draft'`, then require exactly one changed row.
15. Append one fixed audit event in the same transaction.
16. Reset the internal transition setting on success and in the exception path, following the existing state-machine safety pattern.
17. Return only `cancelled::public.request_status`.

The function must not decline, accept, withdraw, update, or delete bids. A valid draft has no provider interaction; finding such interaction is a fail-closed consistency error.

### Concurrency behavior

Request publication, bid acceptance, and draft cancellation must serialize on the request row.

- If cancellation obtains the row lock first, it changes the request to `cancelled`; a later publication attempt must reject the now non-draft request.
- If publication obtains the row lock first, it changes the request to `open`; the draft-cancellation function must re-evaluate the locked row and reject it.
- Concurrent duplicate cancellation calls must not produce two success results or two audit events.
- A concurrent account suspension/role change must serialize with the profile lock so a caller cannot pass the active-customer check using stale authority.

The UI must not be treated as the concurrency boundary.

## Legacy function containment

The future migration must include an explicit call-site review for:

```text
public.customer_cancel_request(uuid,text)
```

Required browser-facing decision:

- revoke `authenticated` execution;
- keep it absent from all frontend modules and static files;
- add a regression test proving an authenticated browser role cannot execute it; and
- do not re-grant it merely as a rollback shortcut.

Any retained `service_role` execution must be justified by a named internal caller and must remain server-only. A future open-cancellation workflow should use a purpose-specific function with its own policy rather than exposing the legacy mixed draft/open contract to customers.

## Allowed UI behavior

The future frontend change should be limited to the existing Ticket 9A-6 customer request detail route.

### Visibility

Show a `Cancel draft` control only when all of these are true:

- the existing Ticket 9A-2 session/profile guard allows the route;
- the protected profile is an active customer;
- the route UUID passed local validation;
- a fresh Ticket 9A-6 RLS-backed detail read succeeded; and
- the returned request status is exactly `draft`.

The control should not appear on the request list in the first implementation. Keeping the mutation on the detail page reduces accidental activation and ensures the customer sees the current request status before confirming.

### Confirmation

Use an accessible confirmation dialog with fixed copy, for example:

```text
Cancel this draft?
This will mark the draft as cancelled. It will not publish the request or contact providers.
```

Allowed actions:

- `Keep draft`
- `Cancel draft`

Do not collect a cancellation reason or any free text. Do not include title, description, suburb, city, address, contact data, or other request content in the RPC payload, URL, log, analytics event, or error report.

### RPC and result handling

- Validate the route UUID again before calling the RPC.
- Call only `customer_cancel_draft_request` with `{ p_request_id: requestId }`.
- Use an in-memory single-flight guard so one confirmation produces at most one call.
- Disable the confirmation action while the call is in flight.
- Do not optimistically change the displayed status.
- Do not automatically retry a timeout, network error, or ambiguous response.
- Treat the scalar `cancelled` result as a transaction acknowledgement, not as the final display source.
- After a successful RPC response, re-read the detail through the existing RLS-backed Ticket 9A-6 query.
- Show `Draft cancelled` only after the fresh read returns `status = 'cancelled'`.
- Update or revisit the list using another RLS-backed read; do not mutate cached request rows into a success state.
- Clear pending mutation state on sign-out, session expiry, account restriction, role mismatch, or navigation away.

No request content or cancellation state may be stored in `localStorage`, `sessionStorage`, IndexedDB, service-worker caches, URLs, logs, analytics, telemetry, or error-report payloads.

## Blocked states and actions

### Function-level blocked states

The database function must reject:

- unauthenticated calls;
- null request IDs;
- missing profiles;
- provider, support, admin, or unknown application roles;
- restricted, suspended, closed, or unknown account statuses;
- missing request IDs;
- requests owned by another customer;
- `open` requests;
- `awarded` requests;
- `cancelled` requests, including repeat calls;
- `expired` requests;
- any future non-draft status;
- any request with a booking;
- any request with an accepted bid or other provider-selection evidence;
- any inconsistent draft carrying publication, award, close, or cancellation timestamps; and
- preferably, any draft with any bid row at all.

The check must use the locked database row. A client-supplied or previously rendered status is never authoritative.

### UI-level blocked states

Do not render or enable cancellation for:

- signed-out or expired sessions;
- missing profiles;
- non-customer roles;
- non-active accounts;
- malformed or missing route UUIDs;
- loading, read-error, generic-unavailable, or category-unavailable-only states where the request itself is not safely confirmed;
- `open`, `awarded`, `cancelled`, `expired`, unknown, or missing status;
- an in-flight cancellation; or
- stale state after any mutation ambiguity.

### Features outside Ticket 9A-7

The future implementation must not add:

- publication or a `customer_publish_request(...)` client call;
- the legacy `customer_cancel_request(...)` client call;
- request editing, updating, deletion, duplication, reopening, or archiving;
- exact-address input, encryption, storage, deletion, read, reveal, maps, GPS, KMS, or key management;
- provider feed, onboarding, bidding, selection, or contact;
- booking actions or completion;
- payments, checkout, cash/off-platform options, refunds, payouts/releases, or disputes;
- reviews, support, consent, notifications, chat, or identity-provider code;
- profile editing or an admin dashboard;
- direct frontend table insert/update/upsert/delete;
- `select('*')`;
- a service-role key or any credential in browser code; or
- RLS/grant/policy changes that broaden browser data access.

The cancellation function must not read, delete, return, reveal, or audit exact-address content. Any retention/deletion policy for encrypted address rows belongs to the separate exact-address privacy work and remains blocked here.

## Audit behavior

Create exactly one append-only audit event after the controlled update and before returning success.

Recommended fixed event:

```text
action: customer.service_request_draft_cancelled
object_type: service_request
object_id: request UUID converted to text
reason: Customer cancelled own draft through controlled draft-only function
metadata: { request_id, previous_status: "draft", new_status: "cancelled" }
```

Audit requirements:

- `actor_id` comes only from `auth.uid()`;
- the reason is a server constant, not a function parameter;
- metadata is built server-side;
- do not include email, phone, title, description, suburb, city, exact address, ciphertext, Auth metadata, tokens, IP data, user-agent data, bid details, booking details, or payment data;
- do not create a success audit event for a rejected attempt;
- if the audit insert fails, the request transition must roll back; and
- repeat or concurrent calls must not create duplicate success audit events.

Rejected-attempt security monitoring, if later required, must use a separate reviewed privacy-safe design. It must not leak record existence through the customer response.

## Safe error messages

Database errors must be fixed and privacy-safe. They must not echo the UUID, current status, owner, profile state, booking/provider-selection existence, SQL, policy names, table names, or raw submitted data.

Recommended server errors:

| Condition | SQLSTATE | Fixed database message |
|---|---:|---|
| Missing authentication | `42501` | `Authentication is required to cancel a draft` |
| Null request ID | `22023` | `Draft request ID is required` |
| Missing/inactive/non-customer profile | `42501` | `Draft cancellation is unavailable` |
| Missing, non-owned, non-draft, booked, selected, or inconsistent request | `42501` | `Draft is not available for cancellation` |
| Defensive update changed no row | `42501` | `Draft is not available for cancellation` |

The frontend must not display raw Supabase/PostgreSQL errors or SQLSTATE values. Recommended customer-facing outcomes:

| Situation | UI message |
|---|---|
| Signed out/expired | Use the existing sign-in-required state |
| Restricted/wrong role | Use the existing restricted/access-denied state |
| Definite policy/state rejection | `This draft is not available for cancellation.` |
| Network, timeout, or ambiguous result | `Cancellation could not be confirmed. Refresh your requests before trying again.` |
| Confirmed by RPC and fresh RLS read | `Draft cancelled.` |

An ambiguous outcome must never be labelled successful and must not be retried automatically.

## Test matrix for the future implementation

### pgTAP database tests

#### Contract and permissions

- The new function exists with the exact `uuid` signature and returns `public.request_status`.
- It is `SECURITY DEFINER`, `VOLATILE`, and has a fixed `pg_catalog` search path.
- Its definition contains no dynamic SQL.
- `PUBLIC`, `anon`, and `service_role` cannot execute it.
- `authenticated` has execute privilege.
- The legacy `customer_cancel_request(uuid,text)` is no longer executable by `authenticated`, `anon`, or `PUBLIC`.
- Direct authenticated insert/update/upsert/delete permissions and RLS behavior remain unchanged.

#### Successful cancellation

- An authenticated active customer can cancel exactly one owned draft.
- The function returns only `cancelled`.
- The request becomes `cancelled`.
- `cancelled_at` is populated by the server.
- `updated_at` advances.
- Title, description, category, suburb, city, requested start, budget, and ownership remain unchanged.
- No bid, booking, payment, address, or other workflow row is created, changed, or deleted.
- Exactly one audit event is appended with the fixed action/reason and allowlisted metadata.
- The audit event contains no request text, contact data, exact-address material, Auth metadata, or client-provided reason.

#### Authentication, role, status, and ownership

- Unauthenticated execution is rejected.
- An active provider is rejected.
- Support/admin/unknown normal registration roles cannot use the customer function.
- Restricted, suspended, and closed customers are rejected.
- A missing profile is rejected.
- A customer cannot cancel another customer's draft.
- Missing and cross-customer IDs produce the same safe error contract.
- Hostile Auth metadata claiming `customer`, `active`, `admin`, or ownership has no effect.

#### Strict request-state rejection

- `open` is rejected and unchanged.
- `awarded` is rejected and unchanged.
- `cancelled` is rejected and unchanged.
- `expired` is rejected and unchanged.
- A second call after successful cancellation is rejected and creates no second audit event.
- An inconsistent `draft` with `published_at`, `awarded_at`, `cancelled_at`, or `closes_at` populated is rejected.
- A draft with a booking is rejected.
- A draft with an accepted bid/provider selection is rejected.
- If the stronger invariant is implemented, a draft with any submitted/other bid row is rejected.
- Rejections do not mutate request, bid, booking, payment, or audit success state.

#### Transaction and concurrency safety

- A cancellation/publication race serializes: only the transition that locks the draft first can succeed under its preconditions.
- Two concurrent cancellation calls yield exactly one transition and one success audit event.
- A concurrent account suspension/role change cannot leave a cancellation committed for an authority check that should have failed after serialization.
- A forced audit failure rolls back the request transition, where testable without weakening production protections.
- The transaction-local state-transition flag is not left enabled after success or failure.
- Direct attempts to reproduce the status/timestamp update remain blocked by Ticket 6 triggers and grants.

#### Regression coverage

- Ticket 1 role/account-status protections remain intact.
- Ticket 2 RLS and direct-DML denial remain intact.
- Ticket 5 exact-address privacy and audit privacy remain intact.
- Ticket 6 state-machine protections remain intact.
- Ticket 9A-5 server public-field validation remains intact.
- Every existing payment, refund, payout, webhook, and profile-provisioning pgTAP suite remains green.

### Frontend tests

- The detail page renders `Cancel draft` only for a freshly read own `draft` under an active-customer guard.
- The list page has no cancellation control in the first implementation.
- No control appears for `open`, `awarded`, `cancelled`, `expired`, unknown, loading, unavailable, read-error, signed-out, restricted, wrong-role, or malformed-ID states.
- The confirmation dialog has fixed copy and no free-text field.
- One confirmation produces exactly one `customer_cancel_draft_request` RPC call.
- The payload contains only `p_request_id` with the validated route UUID.
- No client call references `customer_cancel_request(...)` or `customer_publish_request(...)`.
- A single-flight guard prevents duplicate calls.
- No automatic retry, timer retry, optimistic cancellation, or local status mutation exists.
- Success is displayed only after the RPC succeeds and a fresh RLS-backed detail read returns `cancelled`.
- Ambiguous failures remain unconfirmed and direct the customer to refresh.
- Raw SQLSTATEs, Supabase errors, schema/function names, current hidden status, bookings, provider selection, and record existence are never displayed.
- No direct application-table DML or `select('*')` is added.
- No exact-address, provider, booking, payment, admin, profile-editing, service-role, credential, browser-persistence, logging, analytics, or telemetry capability is added.
- Ticket 9A-1 through Ticket 9A-6 frontend tests remain green.

### CI and documentation tests

- Add the focused pgTAP file to `.github/workflows/database-tests.yml` in the future implementation ticket.
- Run all frontend tests, the Deno webhook suite, `supabase db reset`, the new focused pgTAP suite, and every existing pgTAP suite.
- Update `README.md`, `TESTING.md`, and `hardening_progress.md` with the implemented contract, files, tests, local commands, CI status, and blocked scope.
- CI must contain no real credentials or production project references.

## Deployment and rollback safety

Deploy the future change in this order:

1. Apply and verify the database migration first.
2. Confirm the new function grants and the legacy authenticated revoke in pgTAP.
3. Run the full database regression suite.
4. Deploy the frontend control only after the database boundary is available.
5. Keep the UI disabled if the migration or contract verification fails.

Rolling back the frontend leaves an unused strict function and is safe. Do not re-grant authenticated access to the broader legacy function merely to restore a UI. Any database rollback that removes the new function must also remove/disable the frontend caller first.

## Definition of done for a future implementation ticket

Ticket 9A-7 implementation is complete only when:

1. A reviewed migration creates `public.customer_cancel_draft_request(uuid)` with the exact minimal contract and safe scalar return.
2. The function uses `auth.uid()`, the protected profile row, explicit schema qualification, a fixed `pg_catalog` search path, profile/request row locking, and no dynamic SQL.
3. Only authenticated active customers can pass the server checks, and the request must be owned by the caller.
4. The locked request must be exactly `draft`; every current or future non-draft state is rejected.
5. Bookings, provider selection, accepted bids, and inconsistent draft workflow residue fail closed.
6. The transition uses the existing Ticket 6 state-machine mechanism and is atomic with its fixed privacy-safe audit event.
7. The function accepts no customer-supplied reason or metadata and returns only `cancelled`.
8. Authenticated browser users can execute the new function but can no longer execute the broader legacy `customer_cancel_request(uuid,text)` function.
9. The detail page shows a confirmation control only for a freshly read own draft and calls only the new function with the validated UUID.
10. The frontend uses single-flight behavior, no optimistic state change, no automatic retry, generic safe errors, and a fresh RLS read before showing success.
11. No cancellation control appears for open, awarded, cancelled, expired, unknown, unavailable, wrong-role, restricted, or signed-out states.
12. No publication, editing, exact-address handling, provider bidding/onboarding, booking action, payment/refund/payout/dispute, admin dashboard, profile editing, direct frontend DML, `select('*')`, service-role key, or credential is added.
13. No RLS, grant, policy, role/status, address-privacy, public-field-validation, or state-machine protection is weakened. The only grant change involving the legacy function is restrictive.
14. Focused pgTAP and frontend tests cover permissions, authentication, role/status, ownership, every non-draft state, bookings/provider selection, concurrency, audit privacy, safe errors, and blocked client capabilities.
15. All existing frontend, Deno webhook, migration-reset, and pgTAP suites pass in GitHub Actions.
16. `README.md`, `TESTING.md`, and `hardening_progress.md` accurately record the implementation and every remaining blocker.

Until every item is satisfied, customer draft cancellation remains unavailable.
