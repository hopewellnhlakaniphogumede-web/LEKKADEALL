# Ticket 9A-6 — Customer request list and detail plan

## Status

Planning only. This document does not implement UI, add a frontend call, change the database, or enable any marketplace workflow.

## Goal

Plan safe customer request list and request-detail screens after Ticket 9A-3 draft creation and Ticket 9A-5 authoritative server validation. A future implementation may let an active customer read a bounded list of their own `draft`, `open`, and `cancelled` requests and open an RLS-protected detail view containing only the approved public fields.

Publication and exact-address handling remain blocked. Request editing remains a separate future ticket.

## Verified existing boundary and planning decisions

1. `public.service_requests` has an owner-select RLS policy using `auth.uid() = customer_id`.
2. Authenticated users have column-level SELECT access to the safe request fields needed by this ticket. They do not have direct INSERT, UPDATE, UPSERT, or DELETE authority.
3. Ticket 9A-6 must rely on RLS for ownership. It must not select or filter on `customer_id`, add it to the projection, or treat a client-supplied user ID as authorization.
4. Ticket 9A-5 validates and canonicalises `title`, `description`, `suburb`, and `city` at draft creation and at the table backstop. The frontend must still render all database text as untrusted text, never as HTML.
5. The existing `SAFE_PROJECTIONS.customerRequests` includes `closes_at`. The future Ticket 9A-6 implementation must split or narrow this projection because `closes_at` is not in the approved display scope for this ticket.
6. The list and detail baseline is read-only. No request mutation is required to complete the first safe implementation slice.
7. `customer_cancel_request(uuid, text)` is a trusted Ticket 6 function that authenticates the caller, locks the request, verifies ownership, permits only `draft` or `open`, rejects requests with bookings, changes state through the protected state-machine boundary, declines submitted bids, and appends an audit event.
8. A strict **draft-only** cancellation rule is not currently enforced by that function because it intentionally also permits owned `open` requests. Therefore:
   - the initial Ticket 9A-6 implementation should remain read-only by default;
   - a draft-only cancel control may be included only after explicit approval of the existing broader backend contract;
   - hiding the control for `open` requests is a UX restriction, not a security boundary;
   - if strict server-enforced draft-only cancellation is a product requirement, cancellation remains blocked pending a separate reviewed backend ticket. This planning document does not change the function.

## 1. Route map

| Route | Access | Planned behavior | Data boundary |
|---|---|---|---|
| `/app/customer` | Active customer | Keep the existing customer workspace; add a “View all requests” link or a bounded recent-request section | Own request summaries through the same explicit projection and RLS |
| `/app/customer/requests` | Active customer | Dedicated bounded list of own `draft`, `open`, and `cancelled` requests | Own RLS-visible `service_requests` rows plus active category lookup |
| `/app/customer/requests/:requestId` | Active customer | Read-only detail for one own request in an allowed status | Validated UUID, explicit projection, RLS, `maybeSingle()` semantics |
| `/app/customer/requests/new` | Active customer | Existing Ticket 9A-3 draft-creation page | Existing active-category read and `customer_create_draft_request(...)` only |
| `/auth/sign-in` | Public | Existing signed-out destination | Supabase Auth only |
| `/access-denied` | Safe public state | Missing profile, wrong/unknown role, or unknown non-active account status | No request query |
| `/account-restricted` | Restricted signed-in account | Restricted, suspended, or closed account state | No request query or mutation |

### Route rules

- Add the list route and dynamic detail-route pattern to the existing Ticket 9A-2 protected-route guard.
- Allow both only when the session exists and the caller's own RLS-protected `profiles` row says `role = 'customer'` and `account_status = 'active'`.
- Treat a malformed `requestId` as not found without querying Supabase.
- The URL may contain only the opaque request UUID. It must never contain title, description, suburb, city, schedule, budget, status, address, or contact data.
- A request UUID is an identifier, not an authorization token. Every detail navigation must re-read through RLS; never trust data passed from the list or draft-success state as proof of access.
- Support direct load, refresh, back/forward navigation, session expiry, and a request changing status between list and detail reads.
- Do not add provider, bid, booking, payment, refund, payout, dispute, review, support, chat, onboarding, admin, publication, edit, or address routes.

## 2. Page and component design

### `CustomerRequestListPage`

Responsibilities:

- run the existing session/profile guard before any request read;
- load a bounded, newest-first request list;
- include only `draft`, `open`, and `cancelled` rows;
- resolve active category names through the approved category read;
- render safe loading, empty, error, signed-out, restricted, access-denied, and ready states;
- link each RLS-returned row to its own detail route;
- provide the existing “Create request draft” entry point without adding publication or editing controls.

The first implementation should fetch at most 20 rows. “Load more” may use a bounded cursor or reviewed range query later; it must not fetch an unbounded account history. Status filtering should happen in the database query and may also be offered as an in-memory display filter. No customer text belongs in a filter URL.

### `CustomerRequestDetailPage`

Responsibilities:

- validate the route UUID before querying;
- re-run the active-customer route guard;
- read one allowed-status row with the exact detail projection and RLS;
- use one generic not-found state for malformed, missing, cross-customer, disallowed-status, and RLS-hidden IDs;
- display only the approved fields;
- explain that draft editing, publication, and exact address are unavailable;
- optionally show a draft-cancellation section only if the conditional cancellation decision is separately approved.

### Shared components

- `CustomerRequestList` — accessible list semantics and bounded rows.
- `CustomerRequestSummaryCard` — category label, title, suburb/city, requested start, optional budget, status, and created/updated timestamps. Description may be omitted or safely truncated in the summary, but never inserted as HTML.
- `CustomerRequestStatusBadge` — allowlisted labels for `draft`, `open`, and `cancelled`; an unknown value fails closed instead of creating a new action.
- `CustomerRequestDetail` — full approved public-field display using escaped text or `textContent`.
- `RequestCategoryLabel` — active category name/slug lookup. If the historical category is inactive or unavailable under existing RLS, show “Category unavailable” without broadening the query.
- `SastDateTime` — formats `requested_start`, `created_at`, and `updated_at` explicitly in `Africa/Johannesburg`; it does not silently use the browser timezone.
- `ZarMinorAmount` — displays integer minor units as ZAR without accepting or generating payment instructions. `null` displays “Budget not specified.”
- `RequestListState` and `RequestDetailState` — safe loading, empty, not-found, read-unavailable, signed-out, restricted, and access-denied states.
- `DraftCreatedActions` — after Ticket 9A-3 receives a request UUID, show “View draft” and “View all requests.” The detail page must fetch the row again through RLS.
- `DraftCancellationPanel` — conditional future component only; status `draft`, explicit confirmation, fixed privacy-safe reason, and no free-text field.

### Approved detail display

The customer detail screen may show only:

- category label derived from `category_id` through the active-category lookup;
- title;
- description;
- suburb;
- city;
- requested start;
- optional budget in ZAR;
- status;
- created timestamp;
- updated timestamp.

`id` and `category_id` are permitted only as routing/lookup keys. The raw request UUID need not be displayed as customer content.

## 3. Allowed reads

All reads use the Ticket 9A-2 public anon-key client, the signed-in user's session, explicit projections, existing column grants, and existing RLS. No `select('*')` is permitted.

### Route authority

```text
profiles: id,role,account_status
filter: id = current authenticated user ID
cardinality: maybeSingle
```

The profile row, not auth metadata, determines application role and account status.

### Active category lookup

```text
service_categories: id,slug,name
filter: active = true
order: name ascending
limit: 100
```

Use a separate in-memory lookup keyed by `category_id`. Do not broaden category RLS to reveal inactive or administrative category data. An unresolved historical category receives the generic fallback label.

### Own request list

Exact projection:

```text
id,category_id,title,description,suburb,city,requested_start,budget_minor,status,created_at,updated_at
```

Required query constraints:

```text
status IN (draft, open, cancelled)
order created_at descending
limit 20
```

Do not add a `customer_id` projection or filter. Existing RLS supplies the ownership boundary.

### Own request detail

Use the same exact projection with:

```text
id = validated route UUID
status IN (draft, open, cancelled)
maybeSingle
```

The detail query must not fall back to a broader query when no row is returned.

### Explicitly blocked reads

- `customer_id`, `closes_at`, `published_at`, `cancelled_at`, workflow flags, internal references, audit fields, or any other `service_requests` column outside the approved projection;
- `service_requests.precise_address_ciphertext` and every field or row in `private.service_request_addresses`;
- `audit_events`, `vendor_events`, payment/refund/payout ledgers, disputes, evidence, reviews, support, chat, consent, notification, identity, verification, or provider-onboarding data;
- bids, provider feed, provider identities, bookings, and payments for these new routes;
- other users' profiles or requests;
- private schemas, admin functions, mock webhook functions, or service-role reads;
- nested relationship selections that implicitly request unreviewed columns.

If an allowed read is denied, show the safe unavailable state and document the blocker. Do not add grants, policies, functions, views, migrations, or a service-role client as a workaround.

## 4. Allowed trusted function calls, if any

### Read-only baseline — recommended

The initial list/detail implementation needs **no marketplace RPC**. It uses only the allowed RLS-backed SELECT queries above. Ticket 9A-3 remains the only implemented customer request mutation and continues to call only `customer_create_draft_request(...)` from the creation route.

The new list/detail routes must not call `customer_create_draft_request(...)` themselves.

### Conditional draft cancellation decision

The existing candidate is:

```text
customer_cancel_request(p_request_id uuid, p_reason text default null)
```

It may be exposed in a later approved portion of Ticket 9A-6 only with all of these controls:

1. The existing session/profile guard resolves an active customer.
2. The detail row was freshly returned through RLS and currently has `status = 'draft'`.
3. The control is absent for `open`, `cancelled`, unknown, missing, stale, or read-error states.
4. The customer confirms the irreversible cancellation in an accessible confirmation dialog.
5. The client passes only the validated route UUID and a fixed privacy-safe reason such as `Customer cancelled draft from request detail`; there is no free-text reason field.
6. Use one RPC call, an in-memory single-flight guard, and no optimistic status change.
7. Do not automatically retry a timeout or ambiguous failure. Re-read the detail/list before allowing a later deliberate attempt.
8. On confirmed success, re-read through RLS and render the returned `cancelled` status.
9. Map errors generically without revealing whether another request exists, whether bids exist, or database internals.

Important limitation: these controls make the planned UI draft-only, but the current trusted function also accepts an owned `open` request. If strict draft-only enforcement is required at the server boundary, do not expose cancellation in Ticket 9A-6; create a separate reviewed backend ticket instead. No migration or function change is part of this plan.

### Always blocked function calls

- `customer_publish_request(...)`;
- `customer_upsert_service_request_address(...)`;
- `customer_get_service_request_address(...)`;
- `reveal_confirmed_booking_address(...)`;
- any request edit/update/delete function;
- bid, booking, payment, checkout, refund, payout, dispute, review, support, chat, consent, notification, identity, provider-onboarding, admin, private, webhook, or mock-payment function.

## 5. Blocked actions and fields

### Blocked request actions

- publication or transition to `open` from the frontend;
- edit/update of title, description, suburb, city, category, schedule, budget, status, or timestamps;
- direct request insert/update/upsert/delete;
- exact-address collection, encryption, storage, read, reveal, deletion, map, geolocation, or access instructions;
- cancellation unless the conditional decision and controls above are explicitly approved;
- duplicate, copy, reopen, archive, delete, accept-bid, or contact-provider actions.

### Blocked fields and UI

- exact address, street or house number, complex, unit, room, stand, erf, GPS coordinate, map pin, landmark, gate/access code, phone, email, WhatsApp, social handle, or private contact data;
- deprecated or private address ciphertext;
- customer/provider IDs, `closes_at`, published/cancelled workflow timestamps, internal audit data, or administrative notes;
- bid, provider, booking, payment, refund, payout, dispute, review, support, chat, identity, consent, or notification data;
- card, CVV, bank-login, payment-method, checkout, cash, or off-platform payment controls;
- profile editing, provider onboarding, or admin navigation.

No data from these pages may be used to infer, request, or reveal an exact address.

## 6. Privacy and safe error rules

### Rendering and persistence

- Treat all request and category strings as untrusted. Use `textContent` or the existing reviewed HTML-escaping helper; never render database text with raw `innerHTML`.
- Never put title, description, suburb, city, requested start, budget, status, or timestamps in URLs, query strings, fragments, document titles, referrers, analytics, telemetry, console logs, or error reports.
- Do not persist request rows or detail content in `localStorage`, `sessionStorage`, IndexedDB, service-worker caches, offline queues, or custom browser caches.
- Keep only the minimal in-memory state needed for the current route and clear it on sign-out, session expiry, role/status denial, and navigation to a different account context.
- Do not add third-party analytics, maps, support widgets, or remote assets to the request pages without a separate privacy review.
- Do not treat server-validated public text as safe HTML. Ticket 9A-5 reduces disclosure/markup risk but does not remove the need for output encoding.

### Safe errors

| Condition | Safe behavior |
|---|---|
| Signed out or expired session | Clear request state and show the existing sign-in-required state |
| Missing profile, wrong role, or unknown role/status | Access denied; perform no request query |
| Restricted, suspended, or closed account | Account restricted; perform no request query or mutation |
| List read denied/unavailable | “Requests are unavailable right now.” Do not retry with broader access |
| Invalid, missing, cross-customer, unsupported-status, or RLS-hidden detail ID | One generic “Request not found or unavailable” state |
| Category unavailable | Show “Category unavailable”; do not expose inactive category internals |
| Cancellation conflict or stale status | Re-read and show a generic “This draft could not be cancelled” outcome |
| Network/timeout/unknown mutation result | Do not claim cancellation; ask the customer to refresh their requests before trying again |

Never expose SQLSTATE values, schema/table/policy/function names, stack traces, access tokens, raw Supabase errors, request payloads, another record's existence, bid counts, booking existence, or submitted text in errors.

## 7. Tests required for the future implementation ticket

This planning document adds no tests. The future implementation must extend the existing Node frontend suite and keep every existing pgTAP database and Deno webhook suite green.

### Route and guard tests

- `/app/customer/requests` and the validated detail-route pattern are protected routes.
- Active customer is allowed; signed-out, expired, missing-profile, provider, unknown-role, restricted, suspended, closed, and unknown-status states do not query requests.
- Direct load and refresh of an own detail work after a fresh RLS read.
- Malformed UUID is rejected locally without a database call.
- Cross-customer, nonexistent, disallowed-status, and RLS-hidden IDs render the same generic not-found state.
- No `/admin`, provider-feed, bid, booking, payment, publication, edit, or address route is added.

### Read-boundary tests

- List and detail use exactly `id,category_id,title,description,suburb,city,requested_start,budget_minor,status,created_at,updated_at`.
- Neither query uses `select('*')`, `customer_id`, `closes_at`, deprecated address ciphertext, a private table, or a blocked relationship.
- List and detail filter to `draft`, `open`, and `cancelled` and rely on RLS for ownership.
- List is newest-first and bounded to 20 rows.
- Detail uses a validated UUID and `maybeSingle()` with no broad fallback.
- Category lookup requests only active `id,slug,name` rows and safely handles an unresolved historical category.
- No direct application-table INSERT, UPDATE, UPSERT, or DELETE is introduced.

### Rendering and privacy tests

- Every approved field renders correctly, including multiline description, `null` budget, zero budget, SAST requested start, and created/updated timestamps.
- Database text containing HTML-like characters is escaped and never executed or interpreted as markup.
- Unknown status fails closed and produces no action.
- No exact-address, GPS, map, phone/contact, payment, cash/off-platform, bid, provider, booking, admin, edit, or publication field/control exists.
- Request content is absent from URLs, browser persistence, logs, analytics, telemetry, and error output.

### Draft-created navigation tests

- “View draft” appears only after `customer_create_draft_request(...)` returns a valid request UUID.
- The link contains only the encoded/validated UUID and no submitted form values.
- Opening the link performs a fresh RLS-backed detail read; it does not trust the draft form's success object.
- Ambiguous creation failures direct the customer to the own-request list without claiming a new row exists.

### Conditional cancellation tests

If cancellation is approved for implementation, tests must additionally prove:

- the control is rendered only for a freshly read own `draft` row;
- no cancellation control or RPC call exists for `open`, `cancelled`, unknown, missing, stale, or read-error rows;
- the only new marketplace RPC is `customer_cancel_request` with the route UUID and fixed privacy-safe reason;
- one confirmation produces one call, with a single-flight guard and no automatic retry;
- there is no free-text cancellation reason or direct table write;
- success is shown only after the RPC succeeds and the row is re-read as `cancelled`;
- raw errors, record-existence details, bid/booking information, and the fixed audit reason are not exposed;
- existing pgTAP coverage confirms authentication, ownership, eligible status, booking rejection, state-machine protection, bid decline, and audit behavior. Any missing server-side assertion must be added without changing production rules.

### Regression and static safety tests

- Ticket 9A-1 shell, Ticket 9A-2 Auth/safe-read, Ticket 9A-3 draft creation, and Ticket 9A-5 server-rejection tests remain green.
- Static tests reject `select('*')`, direct application DML, blocked RPC names, service-role configuration, secrets, private tables, exact-address fields, admin routes, payment UI, and browser persistence.
- All pgTAP suites, Deno webhook tests, and frontend tests pass in GitHub Actions.

## 8. Definition of done for a future implementation ticket

The future implementation is complete only when:

1. The list and dynamic detail routes exist and use the existing session plus own-profile route guard.
2. Only active customers can initiate the new reads; all signed-out, expired, missing-profile, restricted, wrong-role, and unknown states fail closed before querying request data.
3. The list shows a bounded newest-first set of only the caller's RLS-visible `draft`, `open`, and `cancelled` requests.
4. The detail page re-reads one validated UUID through RLS and uses the same generic state for missing, cross-user, disallowed-status, and unavailable rows.
5. Both reads use the exact approved projection with no `select('*')`, `customer_id`, `closes_at`, exact-address material, private data, or nested unreviewed columns.
6. Category labels come only from the existing active-category read; inaccessible historical categories use a safe fallback.
7. Only category, title, description, suburb, city, requested start, optional ZAR budget, status, and created/updated timestamps are rendered.
8. Ticket 9A-3 draft success can navigate to the own detail route only after a valid returned UUID, and the detail performs a fresh RLS read.
9. Publication, editing, exact-address handling, provider bidding, bookings, payments, refunds, payouts, disputes, reviews, support, chat, provider onboarding, and admin features remain absent.
10. The read-only baseline adds no new marketplace mutation. If cancellation is included, its conditional controls and tests are satisfied and the pre-existing draft/open backend scope is explicitly documented; otherwise cancellation remains blocked.
11. No migration, RLS/grant/policy/function/webhook change, service-role key, real credential, direct frontend application-table write, or `select('*')` is added.
12. Output encoding, safe errors, no browser persistence, no sensitive telemetry, bounded queries, loading/empty/error states, and accessible navigation are tested.
13. Ticket 9A-1 through Ticket 9A-5 frontend regressions, every pgTAP database suite, and every Deno webhook test pass in GitHub Actions.
14. `README.md`, `TESTING.md`, and `hardening_progress.md` document the implemented routes, projections, commands, intentional blockers, test results, and CI status.

Until every applicable item above is met, request publication, exact-address handling, request editing, and any unapproved cancellation control remain unavailable.
