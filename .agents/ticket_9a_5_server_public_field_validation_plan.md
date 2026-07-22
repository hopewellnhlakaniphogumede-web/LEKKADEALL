# Ticket 9A-5: Server public-field validation plan

## Status

Planning only. This document does not add a migration, function, trigger, policy, grant, UI change, test, exact-address flow, encryption/KMS integration, provider workflow, payment feature, or admin dashboard.

Request publication remains blocked after Ticket 9A-5. Publication may be considered only after this validation boundary and the separate Ticket 9A-4 exact-address boundary are implemented, reviewed, and verified together.

## Goal

Define one authoritative server/database validation boundary for every eventually public service-request text field:

- `title`;
- `description`;
- `suburb`; and
- `city`.

The boundary must stop exact-location, contact, access-code, and unsafe markup/control material from entering new drafts, draft updates, or an `open` request. Ticket 9A-3 browser validation remains defence in depth for customer feedback only; it must never be treated as an authorisation or publication control.

## 1. Current state and gaps

### Existing controls

- `public.service_requests` enforces title length of 3-120 characters and description length of 10-3000 characters.
- Ticket 5 provides `service_request_description_has_exact_address_risk(text)`, which detects several street-address, unit/room, GPS, South African phone, house, stand, and erf patterns.
- Ticket 5 blocks an `open` row when its `description` matches that detector.
- `customer_publish_request(...)` checks the current description detector before changing a draft to `open`.
- Ticket 9A-3 validates all four public fields in the browser, displays the privacy warning, creates drafts only, and uses `customer_create_draft_request(...)` as its sole marketplace mutation.
- Browser roles cannot directly insert, update, or delete service-request rows.

### Gaps

1. The current database privacy detector covers `description`, not all four eventually public fields.
2. Its pattern set does not yet cover email addresses, URLs, social handles, WhatsApp/contact instructions, access/gate codes, complex details, dangerous markup, or the complete control/invisible-character set.
3. `customer_create_draft_request(...)` trims values but does not invoke a shared privacy validator. An attacker can bypass Ticket 9A-3 JavaScript and store risky content in a draft through the RPC.
4. No future draft-update function exists, and its validation contract is not yet defined.
5. Publication checks must be consolidated so validation cannot diverge between creation, update, table backstops, and publication.
6. Existing drafts and privileged/internal writes need a safe handling plan when the stricter validator is introduced.

## 2. Decisions

### Decision A: one private database authority

Create one private, schema-qualified validation subsystem in a future reviewed migration. The authoritative rules must execute inside PostgreSQL, in the same trust boundary as service-request writes and publication.

Recommended conceptual interfaces:

```text
private.service_request_public_field_violation(field_name, value)
  -> null or stable privacy-safe violation code

private.assert_service_request_public_fields(title, description, suburb, city)
  -> void; raises a stable safe error when any field is invalid

private.enforce_service_request_public_fields()
  -> trigger function calling the same assertion helper
```

Names and exact signatures must be reviewed during implementation. The important requirement is a single rule implementation, not these exact names.

The validator must:

- use explicit schema-qualified references and a safe fixed `search_path`;
- avoid dynamic SQL;
- be callable only from reviewed trusted database functions/triggers;
- have direct execution revoked from `public`, `anon`, and `authenticated`;
- not expose submitted text, matched substrings, pattern internals, or match offsets;
- be deterministic for a given validator version; and
- return or raise only stable, privacy-safe field/reason codes.

Do not create a browser-callable validation RPC as a prerequisite. The write RPC itself must validate. A separate preflight endpoint would be advisory and must not become a publication gate.

### Decision B: validate on every trusted write and at publication

The same validator must run in all of these places:

| Boundary | Decision | Reason |
|---|---|---|
| `customer_create_draft_request(...)` | Required | Prevent a custom browser client from storing risky eventually public content in a new draft |
| Future `customer_update_draft_request(...)` | Required | Prevent risky content from being introduced after creation; update must remain owner-only and draft-only |
| Table-level `BEFORE INSERT OR UPDATE OF title, description, suburb, city` backstop | Required | Cover privileged/internal paths and prevent future trusted functions from accidentally bypassing validation |
| Future hardened `customer_publish_request(...)` | Required again, under row lock and in the publication transaction | Catch legacy rows, validator-version changes, internal/bulk data, and concurrent edits before `draft -> open` |

Validation at creation does not remove the publication re-check. A stored draft is not proof that the current policy still accepts its contents.

### Decision C: preserve the existing compatibility helper temporarily

The future migration should preserve existing Ticket 5 behavior and pgTAP coverage while removing rule duplication. Prefer making `service_request_description_has_exact_address_risk(text)` delegate to the new classifier for the `description` field or deprecate it only after every caller and regression test has moved to the shared validator.

Do not leave two independent regex suites that can drift.

### Decision D: PostgreSQL is authoritative; frontend behavior is advisory

Ticket 9A-3's `containsRequestPrivacyRisk(...)` remains valuable for immediate feedback and reduced rejected RPC calls. It does not need to share PostgreSQL regex source verbatim because JavaScript and PostgreSQL regex engines differ. It must share the same behavioural fixture categories and be no less protective for common known cases.

The frontend must always handle a safe server rejection, even when its local validation passed. No frontend flag, hidden field, metadata value, or prior successful preflight may bypass database validation.

## 3. Canonicalisation and validation pipeline

The future validator should process each field in this order.

### Step 1: null and type boundary

- All four values are required for a publishable request.
- Trusted RPCs must reject null rather than coercing it to an empty string.
- The database receives text through typed parameters only; never construct SQL from submitted content.

### Step 2: canonical display value

- Apply a documented Unicode normalisation form, preferably NFC, after confirming support in the CI PostgreSQL version.
- Convert CRLF to LF only for `description`.
- Trim leading and trailing Unicode whitespace.
- Do not silently remove internal control, bidi, zero-width, or markup characters; reject them.
- Do not aggressively collapse internal spaces or change customer-visible spelling without an explicit product decision.

The canonical value that is validated must be the value stored. Validation of one representation followed by storage of another is prohibited.

### Step 3: structural rules

- Apply field-specific character and byte limits.
- Reject NUL, C0/C1 controls, unapproved line separators, bidi overrides/isolates, zero-width characters, and other invisible formatting controls.
- Permit LF line breaks only in `description`; reject CR, tabs, and line breaks in title/suburb/city.
- Treat all four fields as plain text. Reject `<` and `>` and HTML/script-like markup rather than attempting to sanitise it into a different value.
- Output encoding/escaping remains mandatory wherever these fields are rendered. Content validation is not an XSS substitute.

### Step 4: privacy/contact classifier

Run the complete classifier against a case-folded detection representation while retaining the canonical display value for storage. Normalise common Unicode spaces and dash variants for matching. Reject invisible obfuscation instead of deleting it and proceeding.

The classifier must detect the categories in Section 4. Patterns must use PostgreSQL-supported syntax and be verified in the exact local/CI PostgreSQL image. Do not copy JavaScript Unicode-property regexes into PostgreSQL without review.

### Step 5: safe result

- Success returns no derived public data and permits the trusted operation to continue.
- Failure identifies only the field and a broad stable category such as `private_or_unsafe_content`, `invalid_format`, or `invalid_length`.
- Failure must not echo input, a matched substring, a normalised value, regex text, or location within the input.

## 4. Required privacy and unsafe-content detection

### Exact street or physical-location material

Detect context-rich combinations rather than every number or every road word:

- street/house number followed by a street name and designator;
- street designators and abbreviations used in South Africa, including English and reviewed Afrikaans forms such as street/straat, road/rd/weg, avenue/ave/laan, drive/dr/rylaan, lane, close, crescent/cres, boulevard, place, terrace, highway, and route where accompanied by address-like context;
- house, stand, erf, plot, farm, or site plus an identifying number/name where it identifies a physical property;
- PO Box/private bag or other precise delivery-location identifiers if they are not required public marketplace data; and
- landmark-plus-instruction phrases that identify an exact property, such as explicit turn-by-turn or "opposite/behind/next to" directions combined with a property identifier.

### Unit, room, apartment, and complex details

Detect:

- unit, flat, room, apartment/apt, suite, floor, block, section, or building plus an identifier when used as a location;
- complex, estate, residence, hostel, lodge, or building names introduced as the customer's location; and
- combinations such as complex name plus unit/block/floor, even without a street number.

Do not flag an ordinary service description merely because it uses words such as "complex", "unit", "room", "block", or "stand" in a non-location meaning. Context and identifier order matter.

### GPS and map location

Detect:

- latitude/longitude decimal pairs, signed or unsigned when accompanied by coordinate context;
- degrees/minutes/seconds coordinate forms;
- labels such as latitude, longitude, lat, lng, GPS, coordinates, location pin, plus code, or map pin followed by coordinate-like content; and
- map/location URLs under the general URL rules.

### Phone numbers

Detect:

- South African `+27` and leading-zero numbers with spaces, hyphens, parentheses, or common obfuscation;
- compact 10-digit South African phone forms;
- plausible international phone numbers when accompanied by call/contact/WhatsApp instructions; and
- spelled or split number evasion when coupled with an explicit contact instruction, using conservative reviewed cases.

Avoid treating ordinary budgets, dates, times, counts, model numbers, request identifiers, or measurements as phone numbers without the necessary length/context.

### Email addresses

Detect:

- standard email syntax;
- common spaced/obfuscated forms such as `name at domain dot co dot za` when the context clearly requests contact; and
- `mailto:` links.

### URLs

Detect:

- `http://`, `https://`, `www.`, and protocol-relative links;
- recognised domain-like names with a plausible public suffix, including common South African suffixes such as `.co.za`, `.org.za`, and `.net.za`;
- URL shorteners and map links; and
- schemes that can carry contact or script content, including `mailto:`, `tel:`, and `javascript:`.

Do not rely on a permanent hand-written TLD allowlist as the sole control. Keep fixtures for permitted punctuation and locality names containing periods.

### Social handles and private contact instructions

Detect:

- `@handle` patterns and platform-prefixed handles;
- WhatsApp, Telegram, Signal, Facebook, Instagram, TikTok, X/Twitter, DM, inbox, message, call, SMS, email, or "contact me" instructions when they direct off-platform contact;
- attempts to move the transaction or conversation off platform; and
- contact instructions combined with an otherwise obfuscated phone/email/handle.

Ordinary mentions of a communication task, such as requesting repair of a phone, must not be rejected without contact-direction context.

### Access and gate codes

Detect gate/access/security/alarm/intercom/door/keypad/code/PIN/password phrases that include or clearly disclose a credential. A statement such as "access details will be shared securely after booking" may remain safe if it contains no credential, phone, link, or exact-location material.

### Dangerous markup and control characters

Reject:

- HTML/XML tags, script/event-handler fragments, iframe/object/embed markup, and encoded markup intended to execute or alter rendering;
- NUL and unapproved C0/C1 control characters;
- bidi overrides/isolates, zero-width joiners/non-joiners/spaces, word joiners, and other invisible characters used to hide matches;
- unsupported Unicode line/paragraph separators; and
- CRLF/header-style injection sequences outside the approved description newline model.

Do not reject SQL-like words or apostrophes as an injection defence. Parameterised SQL, fixed identifiers, and output encoding are the correct controls; ordinary text such as `O'Reilly` must remain usable.

## 5. Validation rules by field

| Field | Canonical/length rules | Privacy rules | Notes |
|---|---|---|---|
| `title` | Required; trimmed NFC; 3-120 Unicode characters and a reviewed byte cap; single line; no controls, bidi/invisible characters, or markup | Run every privacy/contact/access detector | Short summaries should be strict; numbers remain allowed for legitimate quantities such as "Paint 3 rooms" |
| `description` | Required; trimmed NFC; 10-3000 Unicode characters and a reviewed byte cap; LF paragraph breaks only; no other controls, bidi/invisible characters, or markup | Run every detector, including multiline and cross-line obfuscation | Apply matching to a joined detection view so a phone/address cannot be split across lines to evade checks |
| `suburb` | Required; trimmed NFC; 2-120 Unicode characters and a reviewed byte cap; single line; no controls, bidi/invisible characters, or markup | Reject exact address, unit/complex/property identifiers, GPS, contact, URL/social, and access-code material | Approximate locality only; do not blanket-reject digits because valid township/locality names may contain zone/extension/section numbers |
| `city` | Required; trimmed NFC; 2-120 Unicode characters and a reviewed byte cap; single line; no controls, bidi/invisible characters, or markup | Same as suburb | Prefer a controlled locality reference in a later ticket, but never silently broaden public data |

### Byte limits

Character limits prevent poor UX but do not bound UTF-8 storage or regex work. The future migration must choose explicit byte caps at least large enough for valid maximum Unicode input and small enough to prevent abuse. pgTAP must cover both character and byte boundaries.

### No silent sanitisation

Except for the explicitly approved canonicalisation steps, reject invalid content rather than silently stripping pieces. Silent removal can change meaning, validate a different string than the stored string, or conceal an evasion attempt.

## 6. South African false-positive considerations

The validator must favour privacy without making ordinary South African service requests unusable.

### Safe locality fixtures to preserve

Include representative non-sensitive locality names and forms such as:

- Cape Town, Johannesburg, Pretoria, Durban, Gqeberha, Makhanda, Mbombela, Polokwane, Bloemfontein, Potchefstroom, and eThekwini;
- Die Bult, Cape Town CBD, Bo-Kaap, uMhlanga, and names containing spaces, hyphens, apostrophes, or diacritics; and
- legitimate township/locality forms using `Extension`/`Ext`, `Zone`, `Section`, `Ward`, or `Phase` plus a number.

These are test examples, not a security allowlist. An attacker must not be able to prefix an exact address with an approved locality to bypass the classifier.

### Common safe service text

Do not flag these concepts without additional location/contact context:

- quantities: "paint 3 rooms", "replace 2 taps", or "install 4 lights";
- prices/budgets: `R500` or `R1 250`;
- dates and times;
- product/model identifiers such as a gate-motor or appliance model;
- "complex electrical fault", "stand mixer repair", "apartment cleaning", or "block paving" where no property identifier/name is supplied;
- "the exact address will be shared securely after booking"; and
- ordinary apostrophes or punctuation in names and descriptions.

### Context-sensitive terms

Words including `room`, `unit`, `flat`, `block`, `complex`, `estate`, `stand`, `plot`, `farm`, `drive`, and `close` can be either ordinary words or address components. Prefer patterns that require a location cue, address designator, identifier position, or a combination of signals.

For ambiguous high-risk input, fail closed and ask the customer to rephrase without the potentially private detail. Do not send the text to a third-party AI/LLM moderation service; that would create a new disclosure and nondeterministic security boundary requiring a separate privacy review.

### Maintaining accuracy

- Use synthetic fixtures only; never copy real customer addresses or contacts into tests.
- Track false positives and false negatives by stable category/count without storing rejected content.
- Require security/privacy review for pattern changes.
- Version the rule set in code comments or audit-safe metadata so a production incident can identify which rules were active without recording input.
- Re-run the canonical fixture corpus in both PostgreSQL and frontend tests when rules change.

## 7. Function integration plan

### `customer_create_draft_request(...)`

Future implementation must:

1. authenticate and verify the active customer/category as it does today;
2. canonicalise all four public fields;
3. invoke the shared assertion helper before inserting;
4. insert exactly the validated canonical values; and
5. rely on the table trigger as a final backstop.

If validation fails, no request row, address row, or success audit event may be created. `p_precise_address_ciphertext` remains null from Ticket 9A-3, and Ticket 9A-5 does not alter the exact-address plan.

### Future `customer_update_draft_request(...)`

Do not implement this function in Ticket 9A-5 planning. Its future contract must:

- authenticate an active customer;
- lock and verify ownership of a `draft` with no booking/provider selection;
- accept only explicitly reviewed editable fields;
- canonicalise and validate the complete resulting set of four public fields, not only changed fields;
- use one atomic update;
- write a privacy-safe audit event only after success; and
- return no submitted content in errors.

No direct frontend table update may be granted.

### Future hardened `customer_publish_request(...)`

Publication must remain blocked until Ticket 9A-4 is also ready. Its future transaction must:

1. authenticate an active customer;
2. select the request `FOR UPDATE` and verify owner/draft/no-conflict state;
3. run the current shared validator against the locked stored `title`, `description`, `suburb`, and `city`;
4. perform all separate category, schedule, close-time, exact-address authenticity/decryptability, and state-machine readiness checks;
5. change `draft -> open` and write the audit event atomically; and
6. roll back every effect if any check fails.

The table trigger remains a final backstop on the status update. It does not replace explicit publication validation because the publication function needs a clear fail-closed readiness sequence.

### Existing drafts during rollout

Before applying the future migration:

- run a privacy-safe preflight that reports counts by violation category only, never values;
- do not automatically publish, rewrite, truncate, or log invalid legacy content;
- leave invalid rows as `draft` and require the owning customer to re-enter/rephrase public fields through the future trusted update function;
- ensure the migration can add the trigger without exposing invalid content in errors; and
- preserve rollback safety without restoring a publication bypass.

## 8. Atomic publication requirement

Validation must run against the same locked row version that becomes `open`. The implementation must prevent this race:

1. safe fields are checked;
2. another path changes a field to unsafe content; and
3. the first transaction publishes the changed row.

Use row locking and one transaction. Do not validate in a browser, Edge function, or separate database call and later treat that result as durable approval. No `validated=true` browser flag or timestamp can substitute for re-validating the locked values.

If the validator version changes, all still-draft requests are subject to the new rules the next time they are updated or published. Publication never relies solely on a historical validation result.

## 9. Safe errors, audit, and telemetry

### Database errors

Use a stable invalid-parameter SQLSTATE such as `22023` and a privacy-safe message. Recommended message shape:

```text
Public title contains private or unsupported information.
Public description contains private or unsupported information.
Suburb contains private or unsupported information.
City contains private or unsupported information.
```

Length/format messages may identify the allowed range or that the field must be single-line. They must never include:

- submitted or canonicalised text;
- the matched substring;
- a phone, email, address, handle, URL, coordinate, or access code;
- regex/pattern details or a match offset; or
- the full database exception context.

Do not put raw values into `DETAIL`, `HINT`, constraint names, audit metadata, structured logs, or correlation IDs.

### Frontend mapping

The frontend should map a safe server rejection to the affected field when the server provides a reviewed stable field identifier. Otherwise it should show:

> One or more public fields contain private or unsupported information. Remove exact-location, contact, link, social-handle, access-code, or unsupported formatting details and try again.

The UI may repeat the Ticket 9A-3 privacy warning. It must not echo server payloads or submitted text into error reports, analytics, console output, or URLs.

### Audit and monitoring

Successful create/update/publish actions may retain their existing privacy-safe audit semantics. Rejected-validation monitoring, if required, may record only actor/request identifiers where appropriate, operation stage, field identifier, broad violation code, validator version, and timestamp. It must not record input, captured matches, normalised text, or request bodies.

Rate-limit abuse reporting and store aggregate counts where individual rejection events are unnecessary.

## 10. Blocked approaches

- Client-side validation as the sole control.
- Separate validators with different rules for create, update, trigger, and publish.
- Publication based on a previous browser/server preflight or a client-provided validation flag.
- Direct frontend insert/update/delete/upsert against `service_requests` or any other application table.
- Granting browser roles direct execution of private validation helpers or privileged write functions.
- Silently sanitising risky content and storing the altered result.
- Returning or logging matched sensitive text.
- Treating HTML sanitisation as sufficient protection while allowing exact address/contact data.
- Treating privacy regexes as SQL-injection protection.
- Third-party AI, geocoding, mapping, analytics, or moderation calls with submitted public fields without a separate approved privacy design.
- Enabling publication before Ticket 9A-4 exact-address readiness and Ticket 9A-5 validation implementation both pass.
- Any RLS, grant, Ticket 1 role/status, Ticket 2 baseline, Ticket 5 privacy, or Ticket 6 state-machine weakening.

## 11. Test matrix for a future implementation ticket

No tests are added by this plan. The future implementation must add focused pgTAP and frontend regression coverage and keep every existing database, Deno webhook, and frontend test green.

### A. Validator structure and permissions - pgTAP

| Case | Expected result |
|---|---|
| Private classifier/assertion and trigger functions exist with reviewed signatures | Pass |
| Helpers use fixed safe search paths and no dynamic SQL | Pass |
| `public`, `anon`, and `authenticated` cannot execute private helpers directly | Pass |
| Browser roles retain no direct service-request DML | Pass |
| Table trigger covers insert and updates to all four public fields/status as designed | Pass |
| Existing description helper delegates consistently or remains compatibility-safe | Pass |

### B. Canonical and structural validation - pgTAP

For each field test:

- null, blank, whitespace-only, below-minimum, minimum, maximum, above-maximum, and byte-limit cases;
- NFC-equivalent Unicode behavior;
- leading/trailing trim and approved internal spacing;
- NUL, C0/C1 controls, CR, LF, tab, Unicode line separators, bidi controls, and zero-width characters;
- `<script>`, event-handler, iframe/object/embed, encoded markup, and harmless angle-bracket edge cases under the chosen plain-text rule; and
- description-only approved LF paragraph breaks versus all single-line fields.

### C. Required privacy detections - pgTAP and frontend fixtures

Test every category in every field where it is prohibited:

- numbered English/Afrikaans-style street addresses and abbreviations;
- house, stand, erf, plot, farm, and site identifiers;
- unit, room, flat, apartment, suite, floor, block, building, estate, residence, and named complex forms;
- decimal and DMS GPS coordinates, latitude/longitude labels, plus codes, and map links;
- `+27`, `0xx`, spaced, hyphenated, parenthesised, compact, and contact-cued international phone forms;
- standard and safely selected obfuscated email forms;
- scheme, `www`, bare-domain, `.co.za`, shortener, `mailto:`, `tel:`, map, and dangerous-scheme URLs;
- social handles and WhatsApp/Telegram/Signal/DM/call/email/contact instructions;
- gate/access/security/intercom/alarm/door/PIN/password credentials; and
- newline, Unicode separator, punctuation, or invisible-character evasion attempts.

Use only synthetic values reserved for tests.

### D. South African false-positive fixtures - pgTAP and frontend

Verify acceptance of:

- representative city/suburb names and language/case/diacritic variants listed in Section 6;
- `Extension`/`Ext`, `Zone`, `Section`, `Ward`, or `Phase` locality numbers after review;
- "Paint 3 rooms", "Replace 2 taps", and similar quantities;
- ZAR amounts, ordinary dates/times, measurements, and product model numbers;
- "complex electrical fault", "stand mixer repair", "apartment cleaning", and "block paving";
- apostrophes, hyphens, parentheses, and ordinary punctuation; and
- "Exact address/access details will be shared securely after booking" without an actual secret or location.

### E. Draft creation - pgTAP

| Case | Expected result |
|---|---|
| Each field independently contains risky material | RPC rejects with safe field message and no row |
| Multiple fields are risky | RPC fails without echoing any value and no row is written |
| Valid canonical content | One draft is created with canonical values |
| Hostile client bypasses frontend validation | Database still rejects |
| Failed validation | No address row or success audit event is created |
| Existing auth/role/category/schedule/budget rules | Continue to behave as before |

### F. Future draft update - pgTAP

- active owner can update a draft only with a fully valid resulting field set;
- cross-customer, provider, restricted/suspended/closed, non-draft, and booked requests are denied;
- partial updates cannot preserve or introduce a risky unvalidated field;
- failure is atomic and leaves every stored value unchanged;
- direct table update remains denied; and
- audit content is privacy-safe.

### G. Publication - pgTAP/integration

- an unsafe legacy draft cannot publish even if it predates the validator;
- each field independently blocks publication;
- status, `published_at`, `closes_at`, and publication audit remain unchanged on failure;
- safe validation occurs against a row lock in the publication transaction;
- concurrent update/publish attempts cannot open an unvalidated row;
- current category/schedule/address/state-machine gates still apply;
- trigger and explicit publication checks cannot be bypassed through a privileged/internal path; and
- a fully valid request still remains blocked until all Ticket 9A-4 address requirements are satisfied.

### H. Safe-error and leakage tests

- responses contain only approved field/generic messages and stable SQLSTATEs;
- no input or matched substring appears in error message, detail, hint, audit event, server log, frontend console, analytics, URL, or telemetry;
- multiline and Unicode hostile inputs do not leak through exception context; and
- monitoring uses only approved field/reason/version metadata.

### I. Frontend regression tests

- Ticket 9A-3 warning text and local risk detection remain present;
- the local detector covers the shared common fixture corpus;
- safe South African fixtures are not incorrectly rejected by the frontend;
- a server rejection overrides a local pass and is mapped to a privacy-safe message;
- submitted field values are never added to logs, URLs, storage, analytics, or error reports;
- `customer_create_draft_request(...)` remains the only marketplace mutation;
- `p_precise_address_ciphertext` remains null;
- no direct DML, `select('*')`, publish RPC, address RPC, payment, bidding, provider onboarding, or admin route is introduced; and
- all Ticket 9A-1, 9A-2, and 9A-3 tests stay green.

### J. Security regressions

- Ticket 1 role/account-status escalation tests pass;
- Ticket 2 RLS and grants tests pass;
- Ticket 5 exact-address isolation/reveal/audit tests pass;
- Ticket 6 state-machine and trusted-mutation tests pass; and
- payment/refund/payout/webhook/profile-provisioning regressions remain green.

## 12. Future implementation sequence

1. Approve the threat model, field rules, South African fixture corpus, and safe error contract.
2. Inventory existing drafts using counts only and resolve migration compatibility without exposing content.
3. Add the private classifier, aggregate assertion helper, grants/revokes, comments, and table trigger in one reviewed migration.
4. Integrate the shared validator into `customer_create_draft_request(...)` while preserving all current security checks.
5. Add pgTAP structure, positive, hostile, false-positive, leakage, and regression coverage.
6. Update Ticket 9A-3 frontend tests only as needed to align behavioural fixtures and safe server-error handling.
7. Design and implement `customer_update_draft_request(...)` as a separate trusted, owner-only, draft-only mutation ticket.
8. Harden `customer_publish_request(...)` to re-run the validator atomically, but keep publication unavailable until Ticket 9A-4 address readiness is independently complete.
9. Review full CI evidence and obtain explicit publication-readiness approval.

## 13. Definition of done for a future implementation ticket

A future server-validation implementation is complete only when:

1. One private authoritative validator covers title, description, suburb, and city.
2. The validator implements approved canonicalisation, length/byte, line, control/invisible, markup, exact-location, GPS, phone, email, URL, social/contact, and access-code rules.
3. `customer_create_draft_request(...)` validates all four fields before inserting and stores only the same canonical values it validated.
4. Any future `customer_update_draft_request(...)` validates the complete resulting field set and remains owner-only, active-customer-only, draft-only, and atomic.
5. The table trigger prevents trusted/internal write paths from bypassing the same rules.
6. Future `customer_publish_request(...)` re-validates the locked row atomically immediately before `draft -> open`.
7. Legacy or newly invalid drafts remain drafts and can be corrected only through a trusted function.
8. Safe errors identify at most the affected field and broad category, never submitted or matched content.
9. Logs, audits, analytics, telemetry, and frontend errors contain no rejected field values or matched substrings.
10. South African positive and false-positive fixtures pass in PostgreSQL and the frontend behavioural suite.
11. Hostile clients cannot bypass validation by skipping JavaScript or calling RPCs directly.
12. Browser roles receive no direct table-write capability or private-helper execution.
13. Ticket 9A-3 frontend validation is documented and tested as defence in depth only.
14. All new pgTAP/frontend tests and all existing database, Deno webhook, and frontend regressions pass.
15. Ticket 1, Ticket 2, Ticket 5, and Ticket 6 protections remain intact.
16. No exact-address collection, KMS/encryption code, bidding, payment, admin dashboard, service-role key, or real credential is introduced by the validation ticket.
17. Publication remains disabled until the separate Ticket 9A-4 address boundary also meets its definition of done and explicit readiness approval is recorded.

## 14. What remains blocked after this plan

- migrations and implementation of the validator, trigger, update RPC, or hardened publish RPC;
- exact-address collection, encryption, KMS/key management, storage, decryption, and reveal;
- request publication/opening and provider discovery of Ticket 9A-3 drafts;
- provider bidding, booking changes, payments, refunds, payouts, disputes, reviews, support, chat, admin, and other sensitive workflows;
- direct frontend application-table writes; and
- any weakening of current RLS, grants, role/status protections, address privacy, or state-machine controls.

Ticket 9A-5 establishes the validation design only. Ticket 9A-3 remains draft-only, and Ticket 9A-4 remains the independent exact-address/publication readiness gate.
