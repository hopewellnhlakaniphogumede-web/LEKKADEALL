# Ticket 9A-4: Exact-address and publication readiness plan

## Status

Planning only. This ticket does not implement an address form, encryption service, key, migration, database change, provider reveal flow, or request-publication action.

Publication remains blocked after this planning ticket.

## Goal

Define the security boundary that must exist before a Ticket 9A-3 draft can accept an exact address or become `open` to providers. The eventual implementation must ensure that:

- only genuine, authenticated ciphertext reaches `p_precise_address_ciphertext`;
- exact-address plaintext never enters public tables, URLs, browser persistence, logs, analytics, telemetry, or error reports;
- every eventually public request field is validated by the trusted backend at publication time; and
- any provider reveal is authorised, deliberate, audited, non-cacheable, and limited to the minimum necessary booking states.

## 1. Current controls and readiness gaps

### Controls already available

- Ticket 5 isolates address ciphertext in `private.service_request_addresses` rather than exposing it through `public.service_requests`.
- The deprecated public exact-address compatibility column is forced to remain null and is not granted to browser roles.
- `customer_upsert_service_request_address(...)` checks authentication, customer ownership, draft state, absence of a booking, nonblank input, and the existing ciphertext-size limit.
- `customer_publish_request(...)` checks important ownership and state conditions, requires an address row, and applies the existing description privacy check.
- `reveal_confirmed_booking_address(...)` restricts ciphertext reveal to the selected eligible provider and writes a privacy-safe audit event.
- Ticket 9A-3 creates drafts only, passes `p_precise_address_ciphertext: null`, and exposes no exact-address or publication action.

### Gaps that block address collection and publication

1. The existing address upsert accepts a text value but cannot prove that the value is genuine ciphertext. A custom client could submit plaintext, malformed data, or a fake encryption prefix.
2. Hiding the RPC in the frontend is insufficient while an authenticated browser can call the same database boundary directly.
3. The encryption algorithm, ciphertext-envelope format, key custody, key rotation, recovery, and compromise procedures are not yet approved.
4. Publication does not yet apply equivalent server-side privacy validation to `title`, `suburb`, and `city` in addition to `description`.
5. Address-row existence does not prove that the stored envelope is authentic, correctly bound to the request/customer/environment, supported, and decryptable.
6. A reviewed server-side decryption and plaintext-delivery boundary for eligible providers does not yet exist.
7. The minimum revealable booking-status set and the retention/deletion rules still need product, privacy, and security approval.

These are hard blockers. The future UI must not call the existing address or publication functions until the trusted boundaries below are implemented and tested.

## 2. Recommended architecture

Use a dedicated, same-origin, authenticated server or Edge address boundary with server-side envelope encryption backed by a managed KMS/HSM.

The browser may collect plaintext only on a dedicated private-address page and transmit it once over TLS to this boundary. Encryption keys must never enter browser code, frontend environment variables, static files, source maps, Supabase Auth metadata, logs, or error reports.

The trusted boundary must:

1. accept only authenticated `POST` requests with a small, strictly typed body;
2. validate origin/CORS, content type, payload size, rate limit, session freshness, active customer status, ownership, and draft state;
3. validate and canonicalise the minimum private address fields;
4. encrypt with a fresh per-address-version data-encryption key and nonce;
5. create a versioned authenticated ciphertext envelope bound to the correct request, customer, purpose, and environment;
6. store only that verified envelope through a reviewed restricted database boundary;
7. return only opaque saved/readiness state, never plaintext or ciphertext; and
8. suppress request and response bodies at every proxy, runtime, APM, analytics, replay, and error-reporting layer.

### Required database-boundary decision

Before implementation, choose and test one of these patterns:

1. **Preferred: restricted server-only writer.** Revoke direct browser execution of the ciphertext writer and expose a replacement/internal write path only to a dedicated least-privileged address workload. Use short-lived workload identity or an equivalently managed credential. Do not embed a service-role key in browser or general application code.
2. **Acceptable alternative: signed encryption envelopes.** A KMS-held asymmetric signing key signs the canonical envelope, while the database verifies it with a public verification key before storage. Authenticated users can submit an envelope but cannot forge a valid one.
3. **Conditional fallback: encryption inside a narrow database boundary.** Use an approved database/Vault/KMS integration only if plaintext parameter and statement logging, key rotation, backup, and operational isolation are proven safe.

If none can be implemented without a broadly privileged long-lived credential, exact-address collection and publication remain blocked.

### Why browser-side encryption alone is insufficient

Browser encryption with a public key can be defence in depth, but browser-side shape checks cannot establish genuine ciphertext at the database boundary. A hostile caller can bypass application JavaScript and call a browser-accessible RPC directly. The trusted origin and integrity of the envelope must therefore be enforced by the server/database boundary.

## 3. Exact-address collection design

Collect only the minimum private information required to locate the service:

- street address and number;
- complex or building name, if required;
- unit, flat, or room identifier, if required;
- private suburb and city values if necessary for the complete address; and
- province or postal code only if operationally necessary.

Do not collect phone numbers, email addresses, identity data, payment information, GPS coordinates, gate/access codes, or free-form contact instructions in this ticket. Access instructions need a separate threat, disclosure, and retention review.

Collection requirements:

- render the future form only for the owning active customer and an existing draft;
- use a dedicated same-origin page without third-party analytics, map SDKs, support widgets, ads, or session-replay scripts;
- keep plaintext only in active input elements and short-lived in-memory variables;
- never place plaintext in a URL, query, fragment, route state, referrer, DOM data attribute, console, thrown error, telemetry event, or browser persistence;
- do not use localStorage, sessionStorage, IndexedDB, Cache Storage, service-worker caching, autosave, offline mode, draft recovery, or background sync;
- use `autocomplete="off"` and `spellcheck="false"` as privacy hints, not as security guarantees;
- return generic validation errors that identify a field without echoing its value; and
- clear inputs and in-memory references after confirmed encrypted storage, sign-out, session expiry, route exit, inactivity timeout, or account restriction.

## 4. Encryption and key-management options

### Recommended envelope encryption

- Generate a random 256-bit data-encryption key (DEK) for every address version.
- Encrypt canonical UTF-8 JSON with AES-256-GCM and a unique cryptographically random 96-bit nonce.
- Use additional authenticated data (AAD) containing the environment/project identifier, purpose (`service_request_address`), request ID, customer ID, and envelope version.
- Wrap the DEK with a non-exportable KMS key-encryption key (KEK).
- Store a canonical versioned envelope containing only its format version, algorithm, KMS key identifier/version, nonce, ciphertext, authentication tag, wrapped DEK, and any required signature.
- Do not put plaintext address fragments, names, phone numbers, or contact data in envelope metadata.
- Use one documented canonical encoding, such as base64url for binary values.
- Prove with automated tests that the largest permitted address fits within the existing ciphertext limit.

### Key-management requirements

- Use separate development, test, staging, and production keys. Production must reject test keys and mock envelope versions.
- Keep KMS keys non-exportable and usable only by the dedicated address workload identity.
- Never place a KMS credential, unwrap token, service-role key, DEK, or decryption key in browser code or the repository.
- Restrict encrypt/decrypt/unwrap permissions by environment, workload, and purpose.
- Audit KMS operation metadata without logging plaintext, DEKs, request bodies, or decrypted results.
- Maintain a versioned key registry so approved older envelopes remain decryptable during rotation.
- Use the current approved key version for new writes.
- Make re-encryption resumable, audited, rate-limited, and confined to trusted memory.
- Define key backup, restore, disable, compromise, regional failure, and cryptographic-erasure procedures before launch.
- Fail closed during a KMS outage or when an envelope/key version is unknown, disabled, malformed, or fails authentication.

### Options comparison

| Option | Decision | Reason |
|---|---|---|
| Managed KMS/HSM server-side envelope encryption | Recommended | Strong key isolation, rotation, auditability, and no browser secret |
| Approved database Vault/KMS integration | Conditional fallback | May enforce encryption at storage, but plaintext logging and rotation behavior must be proven safe |
| Browser hybrid encryption with a public key | Defence in depth only | Reduces exposure before the server, but does not stop direct RPC bypass or XSS reading the form |
| Browser symmetric/shared application key | Blocked | The key is extractable and shared across clients |
| Base64, hashing, reversible obfuscation, or TLS-only storage | Blocked | These do not provide authenticated encryption at rest |
| General service-role key in browser or ordinary server code | Blocked | Excessive privilege and credential-exposure risk |

## 5. Exact-address lifecycle

1. **Draft creation:** Ticket 9A-3 creates a request with status `draft` and no address ciphertext.
2. **Private-step readiness:** the server confirms a current session, active customer role/status, request ownership, draft status, and absence of a booking.
3. **Plaintext entry:** the customer enters only the minimum address fields; values remain in volatile page memory.
4. **Secure submission:** the browser sends one authenticated same-origin TLS request. It does not automatically retry an ambiguous result.
5. **Validation and canonicalisation:** the trusted boundary applies length, structure, Unicode/control-character, and canonical JSON rules.
6. **Encryption:** the boundary produces a KMS-backed authenticated envelope with request/customer/environment/purpose AAD.
7. **Storage:** the restricted database boundary verifies and stores only the envelope in `private.service_request_addresses` and records privacy-safe audit metadata.
8. **Browser clearing:** after confirmed success, the browser clears plaintext and shows only a non-sensitive saved/readiness state.
9. **Publication readiness:** a trusted server check verifies the envelope and all public fields without returning plaintext.
10. **Publication:** a later separately reviewed action may perform the complete checks and `draft -> open` transition atomically. This plan does not enable it.
11. **Provider discovery:** provider summaries expose only approved public fields, including approximate suburb/city. They never expose address ciphertext, exact address, customer contact details, or an address-presence signal.
12. **Selected-provider reveal:** after an approved booking state and deliberate action, a trusted server authorises the provider, obtains the audited ciphertext, verifies/decrypts it, and returns plaintext once with no-store headers.
13. **Ephemeral display:** the provider client holds plaintext in memory only and clears it on route exit, sign-out, session expiry, timeout, account restriction, or loss of booking eligibility.
14. **Retention and erasure:** a future controlled job/function removes or cryptographically erases addresses under the approved cancellation, completion, refund, dispute, legal-hold, and account-deletion schedule.

The first implementation should not decrypt a saved address back to the customer. Editing should replace the complete address after re-entry, limiting avoidable plaintext exposure.

## 6. Allowed frontend and server responsibilities

### Frontend may

- apply the Ticket 9A-2 session/profile route guard as a user-experience defence;
- render the private form only after server-confirmed readiness;
- apply conservative field and length validation;
- send one same-origin authenticated request;
- show generic saved, error, and publication-blocked states;
- request a deliberate provider reveal only after server-confirmed eligibility; and
- clear all plaintext state promptly.

### Frontend must not

- hold encryption/decryption keys or privileged credentials;
- call `customer_upsert_service_request_address(...)`, `customer_get_service_request_address(...)`, or `reveal_confirmed_booking_address(...)` directly under the recommended architecture;
- pass plaintext to any parameter named ciphertext;
- persist, cache, prefetch, index, automatically copy, or log the address;
- send the address to maps, chat, notifications, analytics, telemetry, or other third parties; or
- infer publication readiness from local state or the mere existence of an address row.

### Trusted server/Edge boundary must

- independently authenticate and authorise every store, readiness, and reveal operation;
- enforce strict method, origin, content-type, body-size, timeout, and rate controls;
- redact bodies and sensitive headers at proxy, runtime, APM, error-reporting, and support layers;
- use KMS through least-privileged workload identity;
- validate, canonicalise, encrypt, authenticate, and promptly release plaintext references;
- call only reviewed restricted database functions;
- set `Cache-Control: no-store, private`, `Pragma: no-cache`, `Referrer-Policy: no-referrer`, and an appropriate CSP/permissions policy on plaintext responses;
- return generic errors and PII-free correlation identifiers; and
- fail closed on authentication, authorisation, validation, storage, KMS, integrity, version, or audit failure.

## 7. Safe future use of trusted functions

### `customer_upsert_service_request_address(...)`

Do not expose this function directly to the Ticket 9A-4 browser. It may be used only after a future reviewed migration enforces one of the trusted-envelope patterns in Section 2. Its ownership, draft, booking, and audit protections must remain intact.

Before enabling it, tests must prove that:

- authenticated plaintext, random strings, fake prefixes, malformed envelopes, and unsigned/downgrade envelopes are rejected;
- no browser-callable bypass remains;
- request/customer/environment/purpose AAD cannot be swapped;
- replacement is limited to the owning draft before provider selection; and
- database, proxy, and audit logs contain neither plaintext nor ciphertext bodies.

### `customer_publish_request(...)`

Do not expose this function in Ticket 9A-4. A future implementation must harden or wrap publication so a custom authenticated client cannot bypass readiness checks.

Publication must atomically require:

- active customer ownership of a `draft` request;
- an active category;
- a valid future requested start and valid close time;
- complete server validation of `title`, `description`, `suburb`, and `city`;
- an authentic, supported address envelope bound to the same request, customer, purpose, and environment;
- successful integrity and decryptability verification without returning plaintext;
- no booking/provider selection and no conflicting state transition; and
- successful privacy-safe audit recording.

If any condition fails, the request remains `draft`. The frontend must reconcile from server state and must not optimistically display `open`.

## 8. Server-side validation of public fields

Frontend validation is advisory. The future trusted creation/update and publication boundaries must apply the same canonical server validator to every eventually public field.

### Common validation rules

- trim and Unicode-normalise consistently;
- reject unsupported control, bidi, and invisible characters and dangerous markup;
- enforce both byte and Unicode-character limits;
- reject phone numbers, email addresses, URLs, social/contact handles, GPS coordinates, access codes, street/house/unit/room/stand/erf details, or other exact-location patterns;
- return generic field errors without echoing submitted values;
- validate at creation/update and again in the same transaction as publication; and
- maintain hostile-input and false-positive regression fixtures for South African formats.

### Field-specific rules

| Field | Required server rules before publication |
|---|---|
| `title` | Required; 3-120 characters; single line; no address, contact, GPS, URL, or social patterns |
| `description` | Required; 10-3000 characters; approved multiline controls only; existing detector plus contact, URL, GPS, and access-code coverage |
| `suburb` | Required; 2-120 characters; single-line approximate locality only; no street, unit, GPS, or contact data |
| `city` | Required; 2-120 characters; single-line approximate locality only; no street, unit, GPS, or contact data |

An approved controlled South African locality dataset or stable place identifier would reduce free-text leakage. Until its provenance and update process are reviewed, suburb/city remain tightly constrained text and publication remains subject to conservative server validation.

## 9. Provider address reveal and leakage controls

### Authorisation requirements

- the caller is the selected provider for the booking;
- the provider profile is active, approved, and not suspended or restricted;
- request, customer, provider, and booking bindings match;
- the booking/payment state is explicitly approved for reveal;
- the caller has a recent authenticated session, with step-up authentication if approved and proportionate; and
- reveal follows a deliberate `POST` action, never page load, prefetch, link preview, notification, or background request.

### Revealable-status review

Ticket 5 currently permits reveal across multiple funded, fulfilment, completion, dispute, partial-refund, and payout states. Before launch, product, privacy, and security must approve the minimum necessary set.

The recommended default is just-in-time provider access during active fulfilment, such as funded/scheduled/in-progress, with routine reveal stopped after cancellation, full refund, completion, or payout. Dispute/support access should use a separate reasoned and audited privileged path rather than extending provider access indefinitely. This plan does not change any status rule.

### Plaintext delivery requirements

- verify authorisation and obtain the ciphertext through the existing audited boundary before decryption;
- verify envelope integrity and AAD before producing plaintext;
- record only approved PII-free reveal metadata and outcome;
- return plaintext with no-store/referrer/CSP protections and no CDN, proxy, browser, or service-worker caching;
- show it only inside the eligible booking detail following deliberate reveal;
- never put it in URLs, static HTML, structured data, automated clipboard operations, print templates, notifications, email/SMS, chat, maps, analytics, telemetry, or error reports;
- rate-limit repeated reveals while preserving one privacy-safe audit event for each deliberate permitted reveal; and
- use generic denial responses that do not disclose whether another address or booking exists.

## 10. Blocked approaches and actions

The following remain prohibited:

- plaintext exact address in any public table, public/private log, Auth metadata, URL, browser persistence, cache, analytics event, trace, error report, support widget, notification, or source map;
- plaintext passed as `p_precise_address_ciphertext`;
- base64, hashing, encoding, or obfuscation represented as encryption;
- browser symmetric/shared keys, committed keys, service-role keys, KMS secrets, or decryption keys;
- direct browser access to private tables or direct application-table DML;
- relying on RLS, UI hiding, or client-side envelope-shape checks to establish genuine ciphertext;
- address collection before KMS, server-boundary, and full log-redaction tests pass;
- autosave, offline cache, automatic retry, background sync, address prefetch, or automatic reveal;
- third-party map/geocoding integration in the initial exact-address boundary;
- publication based only on address-row existence;
- publication before all four public fields have canonical server validation;
- provider bidding, payments, refunds, payouts, disputes, reviews, support, chat, admin dashboard, or other out-of-scope workflows; and
- weakening any Ticket 5 table isolation, ownership, reveal, audit, RLS, grant, or append-only protection.

## 11. Required tests for a future implementation ticket

No tests are added by this planning ticket. The future implementation must add tests at every relevant layer while keeping all existing frontend, Deno webhook, migration, and pgTAP suites green.

### Cryptography and envelope tests

- approved algorithm/key sizes and cryptographically random DEK/nonce generation;
- same plaintext produces different ciphertext;
- round-trip decryption for each supported envelope and key version;
- tampering with ciphertext, tag, nonce, wrapped key, algorithm, version, signature, or AAD fails closed;
- envelopes cannot be copied between requests, customers, environments, or purposes;
- plaintext fragments never appear in the envelope;
- malformed, truncated, oversized, unknown-version, downgrade, and test-environment envelopes are rejected;
- KMS denial, timeout, and disabled-key failures are closed and non-destructive;
- old-key decrypt/new-key write and resumable rotation are verified; and
- maximum accepted plaintext produces an envelope within the database limit.

### Store-boundary tests

- signed-out, expired, provider, cross-customer, missing-profile, restricted/suspended/closed, non-draft, and already-booked requests are denied;
- only the owning active customer can store or replace an address for an eligible draft;
- plaintext, random strings, fake encryption prefixes, unsigned envelopes, and downgrade envelopes cannot be stored;
- no browser-callable unrestricted upsert path remains;
- ambiguous network failure is not retried automatically;
- KMS, storage, or audit failure leaves no partial state and returns a generic error;
- successful responses contain neither plaintext nor ciphertext; and
- audit events contain only approved identifiers, action, outcome, and envelope version.

### Storage and pgTAP tests

- the public compatibility exact-address column remains null and ungranted;
- the private address table contains only authentic versioned envelopes;
- direct private-table reads/writes remain denied to browser roles;
- owner binding cannot change and cross-request/customer swaps fail;
- address replacement remains owner-only, draft-only, and pre-booking;
- Ticket 5 cross-user, reveal, and audit protections remain intact; and
- retention/erasure affects only eligible rows and does not disclose plaintext.

### Publication and hostile-input tests

- missing, malformed, unauthentic, wrong-AAD, unknown-key, or undecryptable address envelopes block publication;
- `title`, `description`, `suburb`, and `city` independently reject address, contact, GPS, URL, access-code, control-character, and markup attacks;
- Unicode obfuscation, bidi/invisible characters, CRLF, XSS/HTML, SQL-like input, oversized values, and South African phone/address variants are covered;
- stale category, past start, invalid close, wrong owner/role/status, duplicate publish, and concurrent state changes fail safely;
- validation, address readiness, audit, and `draft -> open` are atomic;
- any failure leaves the request in `draft`; and
- successful publication exposes neither exact address, ciphertext, nor an address-presence signal in discovery responses.

### Provider reveal tests

- unselected, unapproved, restricted/suspended, unrelated, payment-pending, cancelled, refunded, expired-session, and other disallowed states are denied under the final approved policy;
- reveal requires deliberate interaction and never occurs during route load or prefetch;
- tampered, wrong-AAD, unknown-key, or unsupported ciphertext cannot reveal;
- each allowed attempt/outcome follows the approved privacy-safe audit behavior;
- plaintext responses are non-cacheable and never reach URLs, caches, service workers, notifications, chat, maps, analytics, logs, or error reports;
- plaintext clears on navigation, sign-out, expiry, inactivity, and eligibility loss; and
- repeated reveal is rate-limited without losing required audit coverage.

### Browser persistence and telemetry tests

- scan localStorage, sessionStorage, IndexedDB, Cache Storage, history state, URL/referrer, console, network errors, performance entries, service workers, and downloads for canary address fragments;
- scan server/Edge/proxy/CDN/KMS/APM/error-monitoring logs and traces using canary values;
- confirm that CSP blocks unapproved third-party scripts and connections on sensitive pages;
- confirm that form plaintext clears after success, safe failure, navigation, sign-out, and session expiry;
- confirm that screenshots, session replay, and analytics are disabled on collection/reveal pages; and
- scan source maps and static bundles for keys, credentials, test plaintext, and live ciphertext.

### Operational tests

- key rotation, key disable, compromise response, restore, regional outage, and cryptographic erasure runbooks;
- rate-limit and abuse-alert events contain no plaintext;
- rollback cannot re-enable an unrestricted authenticated ciphertext writer;
- production rejects local/test keys and mock encryption modes; and
- retention and legal-hold behavior is documented and exercised.

## 12. Definition of done for a future implementation ticket

A future implementation is complete only when:

1. A threat model and privacy review approve the collected fields, retention period, provider reveal states, and operational access.
2. Managed KMS/HSM configuration, environment-separated keys, workload identity, rotation, restore, and compromise procedures are approved and tested.
3. A dedicated authenticated same-origin boundary collects plaintext without request-body logging, third-party scripts, persistent storage, or automatic retries.
4. Genuine versioned authenticated ciphertext is enforced at the database boundary and direct browser plaintext/fake-envelope bypass is impossible.
5. `p_precise_address_ciphertext` receives only an envelope produced and verified through the trusted boundary.
6. No service-role key, KMS secret, or real credential appears in frontend code, repository files, logs, source maps, or ordinary application configuration.
7. Public tables remain free of exact-address plaintext and ciphertext, and every Ticket 5 protection remains intact.
8. Address storage is owner-bound, draft-only, pre-booking, atomic, privacy-safe in its errors, and audited without PII.
9. Server-side validation covers `title`, `description`, `suburb`, and `city` at creation/update and atomically at publication.
10. A custom authenticated client cannot bypass address-readiness or public-field validation.
11. The final revealable-status set is explicitly approved; provider reveal is selected-provider-only, deliberate, server-decrypted, audited, rate-limited, and non-cacheable.
12. Exact-address plaintext never enters URLs, browser persistence/cache, logs, analytics, telemetry, errors, notifications, chat, maps, or source maps.
13. Retention, deletion/cryptographic erasure, legal-hold, and account-deletion handling are implemented and tested.
14. All cryptography, storage, publication, hostile-input, reveal, persistence, telemetry, audit, rotation, and operational tests pass.
15. All existing Ticket 1/2/5/6/7/8/9A/9B frontend, Deno, migration, and pgTAP regression tests remain green.
16. Address collection and publication receive separate explicit production-readiness approval after every applicable gate passes.

## 13. What remains blocked after this plan

- exact-address UI, submission, storage, customer readback, decryption, and provider plaintext reveal;
- browser calls to the current address upsert/get/reveal functions;
- request publication/opening and provider discovery of newly created drafts;
- provider bidding, bid acceptance, and booking changes;
- payments, refunds, payouts, disputes, reviews, support, consent, notifications, chat, identity, maps, and admin dashboard;
- migrations, RLS/grant/policy/function changes, server/Edge code, KMS resources, keys, credentials, service-role access, retention jobs, and real-provider integrations.

Ticket 9A-4 is a readiness design only. Ticket 9A-3 draft-only behavior remains the maximum enabled workflow until a separately reviewed implementation satisfies the complete definition of done.
