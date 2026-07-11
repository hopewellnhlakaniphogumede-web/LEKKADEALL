# Ticket 7C Planning Document - Cash payment policy and confirmation flow

## Goal

Define whether LEKKADEALL will allow cash payments in the MVP, and if allowed, how cash jobs are clearly separated from protected online payments.

Implementation status as of 12 July 2026: the MVP policy has been chosen and implemented as **cash disabled for MVP** in `009_cash_payment_policy.sql`, with pgTAP coverage in `cash_payment_policy.test.sql`.

The future-cash sections below are retained only for later product discussion if the business chooses to allow explicitly off-platform, not-payment-protected cash jobs after MVP.

## 1. MVP policy recommendation

Chosen MVP position: **disable cash payments for launch**.

Reasoning:

- Cash creates trust, safety, fraud, dispute, and support complexity before the marketplace has mature operations.
- LEKKADEALL cannot verify that money changed hands without relying on customer/provider claims.
- Cash cannot use platform-controlled payout release, refund execution, or automated provider disbursement.
- Early MVP trust is easier to explain if protected online payment is the default.

If business strategy requires cash for early adoption, allow it only as an explicitly labelled off-platform option with reduced protection and strict confirmation rules.

## 2. If cash is allowed: required user-facing label

Cash jobs must be labelled everywhere as:

- **Off-platform cash payment**
- **Not LEKKADEALL payment-protected**
- **No platform-held funds**
- **No automatic refund or payout release**

Suggested copy:

> Cash is paid directly between customer and provider. LEKKADEALL does not hold or release these funds, cannot automatically refund cash, and can only help review disputes based on evidence.

This label should appear before booking confirmation, on booking details, in dispute flow, and on receipts/summaries.

## 3. Cash-specific statuses

Keep cash state separate from online `payments.status`.

Suggested `cash_payment_status` values:

- `not_applicable`
- `cash_selected`
- `customer_cash_confirmed`
- `provider_cash_confirmed`
- `cash_confirmed`
- `cash_disputed`
- `cash_cancelled`
- `cash_unverified`

Avoid reusing online statuses like `paid`, `released`, or `refunded` without a cash prefix because those imply platform-controlled money movement.

## 4. Customer/provider confirmation requirements

If cash is allowed:

- Customer and provider must both confirm cash payment before the booking is treated as cash-confirmed.
- Customer confirmation alone should not mark payment complete.
- Provider confirmation alone should not mark payment complete.
- Each confirmation must be timestamped and audited.
- Confirmation should record actor ID, booking ID, cash amount, currency, and a user acknowledgement that payment happened off-platform.

Suggested functions for a later implementation:

- `customer_select_cash_payment(booking_id, acknowledgement_version)`
- `customer_confirm_cash_paid(booking_id, amount_minor, acknowledgement_version)`
- `provider_confirm_cash_received(booking_id, amount_minor, acknowledgement_version)`

## 5. Admin override rules

Admin override should be rare and evidence-based.

Admin may:

- mark cash as disputed
- mark cash as unverified
- override to cash-confirmed only with a non-empty reason and evidence reference
- reverse an incorrect confirmation to `cash_unverified`

Admin must not:

- pretend LEKKADEALL held funds
- create payout release for cash
- mark a provider payout as released for cash
- mark a platform refund as executed for cash

Every admin override must write:

- `cash_payment_events` or equivalent cash ledger event
- `audit_events`

## 6. Dispute handling for cash jobs

Cash disputes should be allowed, but the wording and outcomes must be different from online protected payments.

For cash jobs:

- LEKKADEALL can review evidence and record an outcome.
- LEKKADEALL cannot automatically refund the customer unless the platform separately chooses to compensate them.
- LEKKADEALL cannot claw back cash already paid to a provider through the app.
- Outcome options should include evidence-based recommendations, provider warning/suspension, customer warning, or voluntary repayment tracking.

Opening a cash dispute should:

- set `cash_payment_status = 'cash_disputed'`
- prevent review/rating publication until resolved if abuse risk exists
- write audit and dispute events

## 7. Why cash must not trigger payout release

Cash must never trigger payout release because LEKKADEALL does not hold the money.

Online payout release means the platform or payment provider held funds and then released them to the provider. Cash bypasses that custody path completely.

Therefore:

- no `release_status = released` for cash
- no provider payout ledger event for cash
- no platform-held balance changes for cash
- no payout/release webhook for cash

Cash confirmation should be a booking/payment-note state only, not a payout state.

## 8. RLS and privilege model

Recommended future table:

- `cash_payment_events`

Recommended access:

- customers/providers can read cash payment state for their own bookings
- customers/providers cannot directly insert/update/delete cash state rows
- customer/provider confirmations must go through safe functions
- admin overrides must go through admin-only functions
- `cash_payment_events` must be append-only
- unrelated users cannot read cash events
- service-role direct table use should be avoided in favour of audited functions

Privileged fields must be trigger-protected, including:

- `cash_payment_status`
- `customer_cash_confirmed_at`
- `provider_cash_confirmed_at`
- `admin_override_by`
- `admin_override_at`
- `admin_override_reason`

## 9. Required pgTAP tests

If cash is disabled in MVP:

- cash selection function does not exist or rejects all calls
- customers cannot create cash payment rows directly
- providers cannot create cash payment rows directly
- no booking can move to a cash-confirmed state
- payout release cannot occur for cash

If cash is allowed:

- customer can select cash only for own booking if booking is eligible
- customer cannot select cash for another customer’s booking
- provider cannot select cash on behalf of customer unless policy explicitly allows it
- customer confirmation alone does not mark cash confirmed
- provider confirmation alone does not mark cash confirmed
- both confirmations mark cash as `cash_confirmed`
- mismatched amounts are rejected or mark `cash_unverified`
- admin override requires platform admin/server context
- admin override requires non-empty reason
- normal users cannot admin-override cash status
- cash events are append-only
- unrelated users cannot read cash events
- cash disputes move status to `cash_disputed`
- cash payment never updates `payments.release_status` to `released`
- cash payment never creates payout-release events
- Ticket 1, 2, 5, 6, 7A, and 7B smoke protections remain intact

## 10. Definition of done

For planning:

- Cash MVP policy is explicitly chosen: disabled or allowed.
- If allowed, user-facing protection warnings are approved.
- Cash statuses are defined separately from online payment statuses.
- Confirmation and admin override rules are agreed.
- Cash dispute language and outcomes are agreed.
- It is documented that cash never triggers payout release.

For future implementation:

- pgTAP tests prove the selected policy.
- No frontend role can directly mutate cash payment state.
- Cash ledger/events are append-only.
- Cash disputes are private and audited.
- Cash state cannot create platform payout or refund claims.
- Production copy clearly says cash is off-platform and not payment-protected.
