# Security and integration architecture

## Trust boundaries

The browser/mobile client may use only the public application API and short-lived user session. It must never contain service-role keys or vendor API secrets.

The application backend validates authorisation, applies rate limits, creates marketplace records and calls vendor adapters. Payment, identity and messaging credentials exist only in the server secret store.

The payment partner hosts sensitive payment entry and returns a transaction reference and status. The identity partner should receive identity evidence directly and return a status, reference, assurance level and minimal extracted attributes.

## Booking state machine

`draft -> open -> offered -> accepted -> payment_pending -> funded -> scheduled -> in_progress -> completed -> payout_released`

Exception states: `cancelled`, `disputed`, `refunded`, `partially_refunded`, `expired`.

State transitions occur only through server actions. Vendor webhooks are verified, stored once using their unique event ID, and reconciled against internal records.

## Data minimisation

- Public request: category, approximate area, requested time and customer-provided description.
- Accepted provider: booking contact and service address only when required.
- Platform: payment references and status, never card data.
- Identity: verification result/reference; raw evidence retained only if the final legal and vendor design requires it.

## Launch gates

- Payment production credentials: blocked until merchant approval, signed agreement, refunds and dispute freeze tested.
- Identity production credentials: blocked until operator/privacy agreement, consent wording and retention confirmed.
- Public provider onboarding: blocked until human review and appeals are operational.
- Public customer launch: blocked until policies, Information Officer contact, monitoring, backups and incident response are active.
