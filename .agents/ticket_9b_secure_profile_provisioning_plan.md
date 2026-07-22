# Ticket 9B Planning Document — Secure Profile Provisioning

## Goal

Plan a trusted backend mechanism that creates the minimum safe `public.profiles` row for each normal Supabase Auth registration without allowing the browser, Auth metadata, or registration input to choose application authority.

Ticket 9B resolves the blocker identified by Ticket 9A-2: an `auth.users` record can currently exist without a corresponding `public.profiles` record, while the frontend is correctly prohibited from inserting that application row itself.

## Planning-only status

This document makes an architecture recommendation and defines a future implementation and test contract. It does not implement a migration, trigger, function, RLS policy, frontend change, credential, or service-role client.

## Existing security foundation

The current schema and hardening tickets establish the following constraints:

- `public.profiles.id` is a primary key and foreign key to `auth.users.id` with `on delete cascade`.
- `public.profiles.role` is a `public.user_role` enum with `customer`, `provider`, `support`, and `admin` values.
- `public.profiles.account_status` permits `active`, `restricted`, `suspended`, and `closed`.
- Ticket 1 makes `role` and `account_status` privileged, trigger-protected fields and supplies audited admin-only transition functions.
- Ticket 1 also protects provider verification and review fields from direct client changes.
- Ticket 2 enables RLS and allows authenticated users to select their own profile, while denying direct profile insert/delete to frontend roles.
- `display_name` is required and must contain between 2 and 100 characters.
- No trusted Auth-to-profile provisioning trigger or function currently exists.

Ticket 9B must extend this foundation without replacing or bypassing it.

## Recommended architecture

### Decision: database trigger on `auth.users`

Use a narrowly scoped, `SECURITY DEFINER` PostgreSQL trigger function invoked by an `AFTER INSERT` trigger on `auth.users`.

The future function should:

1. receive the new Auth user only through the trigger context;
2. insert one `public.profiles` row keyed by `NEW.id`;
3. set every authority-bearing value from fixed constants owned by the database;
4. ignore all user-supplied Auth metadata for provisioning authority;
5. be idempotent and never overwrite an existing profile;
6. optionally append a minimal, non-sensitive provisioning audit event; and
7. return `NEW` without performing any provider, admin, support, payment, or marketplace setup.

Recommended future database objects:

- a private trigger function, such as `private.provision_auth_user_profile()`;
- an `AFTER INSERT ON auth.users FOR EACH ROW` trigger; and
- if needed for backfill, a separate private/admin-only helper or migration-local statement that uses the same fixed-value insert contract.

The exact object names must be reviewed against the final migration sequence before implementation.

### Why the trigger is preferred

- Provisioning occurs in the same database transaction as Auth-user creation, avoiding an eventual-consistency window.
- Normal registration needs no service-role key, webhook, queue, or externally deployed function.
- The browser never receives permission to insert profiles.
- The database, not request metadata, owns the initial role and account state.
- A database failure can fail registration closed instead of silently leaving an authenticated user with ambiguous application authority.
- Idempotent backfill can use the same insert rules as live registration.

### Server/Edge Function alternative

A server or Edge Function is not recommended for normal initial provisioning because it introduces a second request, elevated-secret management, retry/orphan handling, and a period in which `auth.users` may exist without `public.profiles`.

An admin-controlled server process may still be appropriate for exceptional repair or migration operations, but it must not become a public registration endpoint and must not accept privileged fields from the caller. Any such repair path requires separate authorization, audit, and test review.

### Managed-Auth compatibility gate

Before implementation, validate in an isolated Supabase environment that the project migration role may safely create the trigger on `auth.users` and that the selected Supabase Auth version supports this pattern. If the managed platform prevents it, stop and redesign a trusted, server-only provisioning path; do not grant profile insert permission to `anon` or `authenticated` as a workaround.

## Initial role and provider-onboarding decision

### Initial role

Every normal registration receives:

- `role = customer`
- `account_status = active`

These values must be written explicitly by the provisioning function rather than copied from metadata or request input. Explicit constants make the security contract visible even though the table currently has matching defaults.

`active` means the new customer may enter the customer shell subject to email/session requirements and all existing RLS. It does not mean provider-approved, identity-verified, payment-enabled, or administratively trusted.

If product policy later requires manual activation for all customers, that must be a separate reviewed ticket with an explicit schema/state decision. Ticket 9B must not silently overload `restricted` or another status.

### Provider onboarding

Provider onboarding starts separately after customer registration. Registration must not create a provider role or `public.provider_profiles` row.

A future provider-onboarding ticket should define:

1. a customer request to become a provider;
2. trusted creation of a provider-onboarding record or `provider_profiles` row;
3. identity/business/bank verification states;
4. admin review and rejection behavior;
5. the audited point at which `admin_set_user_role(...)` changes the role to `provider`; and
6. the conditions under which provider marketplace actions become available.

Until that workflow is approved, the user remains a customer. Provider intent in Auth metadata, URL parameters, form fields, or client state has no authority.

## Fields populated in `public.profiles`

The future trigger should insert only the following values:

| Field | Provisioned value | Reason |
|---|---|---|
| `id` | `NEW.id` from `auth.users` | Trusted Auth identity and required foreign-key match |
| `role` | fixed `customer` | Least-privileged normal registration role |
| `display_name` | fixed neutral value such as `New customer` | Meets the current non-null/length constraint without trusting metadata or exposing the email local part |
| `phone_e164` | `NULL` | Must not trust unverified metadata |
| `phone_verified_at` | `NULL` | Verification cannot be asserted by registration input |
| `email_verified_at` | `NEW.email_confirmed_at` only if confirmed and semantically compatible; otherwise `NULL` | May reflect Auth-owned confirmation state, never metadata; final implementation must test confirmation timing |
| `suburb` | `NULL` | Optional profile data is collected later through an approved safe-field workflow |
| `city` | fixed schema default (`Potchefstroom`) or another separately approved fixed default | Never copied from metadata during provisioning |
| `avatar_path` | `NULL` | No unreviewed storage reference is accepted |
| `account_status` | fixed `active` | Safe customer default; not caller-selectable |
| `created_at` | database transaction time/default | Server-owned timestamp |
| `updated_at` | database transaction time/default | Server-owned timestamp |

Implementation must explicitly decide whether to omit defaulted non-authority columns or write the approved constants. Role and account status should be explicit.

The fixed placeholder display name is intentionally not personalized. A future profile-editing ticket may allow the owner to change only the already-approved safe fields under existing column grants and RLS.

## Fields never accepted from user metadata

The provisioning path must not read, copy, deserialize, dynamically map, or trust `raw_user_meta_data`, `raw_app_meta_data`, registration query parameters, redirect parameters, or browser payloads for any of the following:

- `id` or another user's UUID;
- `role`, including `provider`, `support`, or `admin`;
- `account_status`;
- admin/support flags, permissions, scopes, claims, or groups;
- provider intent as an immediate role assignment;
- provider verification status or verification reference;
- provider review/approval status, reviewer, or review time;
- bank-name-match or payout eligibility;
- identity-verification status or references;
- phone/email verification timestamps;
- audit actor identity;
- service-role or JWT claims;
- payment, refund, release, payout, dispute, or cash state;
- trusted address, exact address, consent, or age status;
- `created_at` or `updated_at`;
- storage paths or external URLs; or
- arbitrary column names or JSON to merge into the profile.

For the safest first implementation, no user metadata should populate even non-privileged profile fields. Personalization can happen later through narrowly granted owner updates and validation.

## Function and trigger security contract

The future trigger function must meet all of these requirements:

- reside outside the public API surface, preferably in `private`;
- use `SECURITY DEFINER` only because the Auth insert context needs controlled access to `public.profiles`;
- be owned by a non-login migration/database owner appropriate to the Supabase project;
- have an explicit safe `search_path`, with all referenced relations/functions schema-qualified;
- have all direct execution revoked from `public`, `anon`, and `authenticated`;
- not expose parameters that allow callers to choose ID, role, account status, or profile content;
- operate only for an `INSERT` trigger on `auth.users` and reject/avoid unexpected invocation contexts;
- use fixed constants rather than table defaults for authority-bearing fields;
- use an idempotent insert that does nothing on an existing `profiles.id` conflict;
- never update or repair an existing profile during normal trigger execution;
- never set the Ticket 1 privileged-update bypass setting;
- never call the Ticket 1 admin role/status functions;
- never create `provider_profiles`, identity checks, payment records, or other application rows; and
- allow unexpected database errors to abort the Auth insert transaction rather than silently creating an orphaned Auth user.

Idempotency must not mean `upsert` with updates. Replaying provisioning for an existing ID must preserve its role, account status, display name, timestamps, and all other profile values.

## Ticket 1 and Ticket 2 preservation

### Ticket 1 role-escalation protection

The future migration must preserve:

- `private.protect_profile_privileged_fields()` and its trigger;
- audited `admin_set_user_role(...)` transitions;
- audited `admin_set_account_status(...)` transitions;
- provider verification/review protection triggers and admin functions;
- prohibition on admin self-promotion and normal registration of admin/support accounts; and
- revocation of privileged function access from unauthenticated callers.

Provisioning is an insert with fixed values, not an exception to the protected update path. It must not introduce a general privileged insert API.

### Ticket 2 RLS protection

The future migration must preserve:

- RLS enabled on `public.profiles` and every other application table;
- authenticated own-profile read behavior;
- no `INSERT` or `DELETE` grant/policy on `public.profiles` for `anon` or `authenticated`;
- safe-field-only profile update grants;
- private trigger function invisibility to frontend roles; and
- existing application-table policies and grants unchanged unless a separate ticket explicitly authorizes a reviewed change.

The trigger's trusted execution does not justify a frontend insert policy.

## Audit and event logging

Recommended: append one minimal audit event only when a new profile row is actually created.

Suggested event contract:

- action: `system.profile_provisioned`;
- actor: `NULL` to represent an internal system action;
- object type: `profile`;
- object ID: the new Auth user UUID;
- reason: fixed text such as `auth user registration` or `existing auth user backfill`;
- metadata: a fixed source/version marker only.

Do not log email, phone, IP address, tokens, Auth metadata, passwords, provider intent, or raw registration payloads. An idempotent replay that creates no row must create no duplicate audit event.

Before implementation, verify that `private.append_audit_event(...)` safely accepts a null system actor and remains available in the migration order. If audit failure would block all registration, explicitly test that behavior and decide whether atomic audit is operationally acceptable. Do not weaken the append-only audit protection.

## Existing Auth users without profiles

### Pre-deployment assessment

The future implementation ticket must produce counts, not personal data, for:

- total Auth users;
- Auth users missing a profile;
- existing profiles with matching Auth users;
- any unexpected integrity condition; and
- missing-profile accounts that may already have application-related records.

The assessment output must not print emails, phone numbers, tokens, metadata, or credentials to CI logs.

### Safe deployment order

Recommended order inside one migration transaction where the platform permits:

1. create the private idempotent trigger function;
2. revoke frontend/public execution;
3. create the `auth.users` insert trigger;
4. backfill only Auth IDs for which no profile exists, using the same fixed defaults;
5. write one minimal audit event per profile actually created, if audit logging is approved; and
6. run postconditions that fail the migration if missing-profile rows remain.

Creating the trigger before backfill closes the race for registrations occurring during deployment. Conflict-do-nothing behavior prevents the backfill and trigger from overwriting each other.

### Existing profiles

Never overwrite an existing profile during backfill, even if it has a non-customer role, non-active status, customized display name, or older timestamps. Existing privileged states require separate investigation and audited correction, not normalization by Ticket 9B.

### Backfill safety

- Backfill only the missing `public.profiles` row.
- Assign the same `customer`/`active` defaults as new registration.
- Do not infer role from historical Auth metadata or email domain.
- Do not create provider profiles.
- Do not activate, unsuspend, or change existing profiles.
- Fail and investigate if an unexpected constraint or referential-integrity condition occurs.

### Rollback behavior

Migration failure should roll back the trigger, function, backfill, and audit inserts together when transactional DDL permits.

After a successful deployment, rollback should be non-destructive:

- disabling/removing the trigger stops future provisioning;
- removing the private function occurs only after the trigger is removed;
- already-created profiles and audit events are retained;
- rollback must not delete customer profiles or Auth users; and
- users created after a rollback again fail closed in the Ticket 9A-2 missing-profile state.

A corrective forward migration is preferred to destructive rollback once real profiles have been provisioned.

## Failure and operational behavior

- If profile insertion fails during registration, Auth-user creation should fail atomically and return a generic registration error.
- Never expose PostgreSQL internals, constraint names, schema names, user existence, or metadata in frontend errors.
- Alert on sustained provisioning failures using sanitized operational telemetry.
- Do not retry by granting the browser profile insert access.
- An existing Auth session with no profile continues to receive Ticket 9A-2's fail-closed “account setup unavailable” state.
- A duplicate trigger invocation succeeds without modifying the existing profile or producing a duplicate audit event.
- Rate limiting, bot controls, email confirmation, and password policy remain Supabase Auth concerns and are not replaced by this trigger.

## Test matrix for the future implementation ticket

### pgTAP database tests

| Area | Required assertion |
|---|---|
| New Auth user | Creating a normal Auth user creates exactly one matching profile |
| Identity binding | Profile `id` equals the trusted Auth user ID |
| Default role | New profile role is exactly `customer` |
| Default account status | New profile account status is exactly `active` |
| Required fields | Neutral display name satisfies schema constraints; timestamps/default city are valid |
| Optional fields | Phone, verification timestamps not backed by Auth, suburb, and avatar remain null/approved defaults |
| Metadata injection: role | Metadata requesting provider/support/admin is ignored |
| Metadata injection: status | Metadata requesting restricted/suspended/closed or other status is ignored |
| Metadata injection: provider | Verification/review/bank/provider fields are ignored and no provider profile is created |
| Metadata injection: identity/payment | Identity, payout, payment, address, consent, and arbitrary JSON fields are ignored |
| App metadata injection | `raw_app_meta_data` cannot affect the profile authority fields |
| Idempotency | Replaying provisioning leaves exactly one profile |
| No overwrite | Replay preserves an existing profile's role, status, safe fields, and timestamps |
| Audit creation | One approved audit event is written only when a profile is first created |
| Audit privacy | Audit metadata contains no email, phone, tokens, or raw Auth metadata |
| Trigger privacy | `anon` and `authenticated` cannot execute the private trigger function |
| Direct insert denial | `anon` and authenticated users still cannot insert profiles directly |
| Direct delete denial | Authenticated users still cannot delete profiles directly |
| Own read | Authenticated user can read only their own profile under existing RLS |
| Cross-user read | Another authenticated user cannot read the new private profile |
| Role update protection | Direct role changes remain blocked by Ticket 1 |
| Status update protection | Direct account-status changes remain blocked by Ticket 1 |
| Admin path | Existing audited admin role/status functions retain their authorization and audit behavior |
| Admin/support registration | Normal registration cannot create either privileged role |
| Provider protections | Existing verification/review protections remain intact |
| Other RLS | Ticket 2 baseline RLS regression suite remains green |
| Cascade behavior | Approved Auth-user deletion behavior remains consistent with the existing FK/cascade contract |

### Backfill tests

| Area | Required assertion |
|---|---|
| Missing profile | Backfill creates one fixed-default customer profile |
| Existing profile | Backfill does not alter or duplicate the row |
| Mixed population | Only missing IDs are provisioned |
| Concurrent-safe contract | Trigger/backfill conflict path leaves one unmodified row |
| Repeated backfill | A second execution creates no profiles or duplicate audits |
| Postcondition | No Auth user remains without a profile after successful migration |
| Privacy | Backfill output/logging exposes counts only |

### Integration tests

- Register through Supabase Auth with no metadata and confirm the customer profile is available after the supported confirmation/session flow.
- Register with hostile user/app metadata and confirm all privileged values remain fixed.
- Confirm Ticket 9A-2 route resolution sees `customer`/`active` from `public.profiles`, not metadata.
- Confirm no service-role key or direct profile insert is present in the browser request path.
- Confirm duplicate/retry behavior is safe.
- Confirm an intentionally induced profile constraint failure fails registration closed and exposes only a generic client error.
- Confirm sign-in for an existing backfilled user resolves the profile normally.
- Confirm a pre-existing missing-profile session remains safely blocked until backfill completes.

### Regression suites

The future implementation must keep all existing tests green, including at minimum:

- Ticket 1 role-escalation pgTAP tests;
- Ticket 2 baseline RLS pgTAP tests;
- exact-address privacy tests;
- marketplace state-machine tests;
- payment/refund/cash/payout/mock-checkout/webhook database tests;
- mock webhook Deno tests; and
- Ticket 9A frontend-shell tests.

The new profile-provisioning pgTAP suite must be added to the existing GitHub Actions database workflow in the future implementation ticket.

## Definition of done for a future Ticket 9B implementation

Ticket 9B implementation is complete only when:

1. A reviewed migration adds the trusted, private, idempotent Auth-user provisioning mechanism.
2. Normal registration atomically creates exactly one `public.profiles` row.
3. The row uses fixed `customer` and `active` values and an approved neutral display name.
4. No Auth metadata or browser input can select role, account status, provider state, verification, review, admin, or support authority.
5. Registration creates no `provider_profiles` row; provider onboarding remains separate.
6. Existing Auth users missing profiles are backfilled safely without modifying existing profiles.
7. Replays and concurrent trigger/backfill execution cannot duplicate or overwrite profiles or audits.
8. The trigger function is not executable by `public`, `anon`, or `authenticated`.
9. No profile insert/delete grant or policy is added for frontend roles.
10. Ticket 1 privileged-field triggers and audited admin functions remain intact and tested.
11. Ticket 2 RLS and column-grant protections remain intact and tested.
12. Minimal provisioning audit events are append-only and contain no sensitive registration data, if audit logging is adopted.
13. Failure behavior is atomic, fail-closed, sanitized, and operationally observable.
14. pgTAP and Auth integration tests cover the full test matrix, including hostile metadata.
15. The existing database, webhook, and frontend regression suites remain green in GitHub Actions.
16. No frontend code, real credential, service-role key, provider adapter, payment integration, or unrelated workflow is included.
17. Deployment, backfill verification, forward-fix, and non-destructive rollback procedures are documented.

## Explicit non-goals

Ticket 9B does not plan or authorize:

- frontend profile insertion or profile editing;
- registration-time selection of customer/provider/admin/support roles;
- provider onboarding, approval, or verification implementation;
- admin/support account creation;
- exact-address submission or reveal;
- request publishing, bidding, booking completion, refunds, payouts, disputes, reviews, consent, support, or chat;
- real payment-provider code or credentials;
- service-role credentials in browser or repository files;
- weakening any RLS policy, grant, privileged-field trigger, audit protection, or database function authorization; or
- implementing the migration described by this plan.
