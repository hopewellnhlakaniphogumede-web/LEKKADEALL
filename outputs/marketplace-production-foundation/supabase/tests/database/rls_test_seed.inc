-- Deterministic test-only fixtures for the database hardening pgTAP tests.
-- Included inside the test transaction and rolled back.

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'customer-a@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000000002', 'customer-b@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000000011', 'provider-a@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000000012', 'provider-b@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000000099', 'admin@lekkadeall.test');

-- Ticket 9B provisions every Auth user as a customer/active profile. Tests that
-- need historical provider/admin fixtures adjust those rows through the same
-- test-only privileged bypass already used by the Ticket 1 regression suite.
set local lekkadeall.allow_privileged_profile_update = 'on';

update public.profiles as p
set role = v.role::public.user_role,
    display_name = v.display_name,
    city = v.city,
    account_status = v.account_status
from (values
  ('00000000-0000-0000-0000-000000000001'::uuid, 'customer', 'Customer A', 'Potchefstroom', 'active'),
  ('00000000-0000-0000-0000-000000000002'::uuid, 'customer', 'Customer B', 'Potchefstroom', 'active'),
  ('00000000-0000-0000-0000-000000000011'::uuid, 'provider', 'Provider A', 'Potchefstroom', 'active'),
  ('00000000-0000-0000-0000-000000000012'::uuid, 'provider', 'Provider B', 'Potchefstroom', 'active'),
  ('00000000-0000-0000-0000-000000000099'::uuid, 'admin', 'Admin User', 'Potchefstroom', 'active')
) as v(id, role, display_name, city, account_status)
where p.id = v.id;

set local lekkadeall.allow_privileged_profile_update = 'off';

insert into public.provider_profiles (
  user_id, business_name, verification_status, verification_reference,
  bank_name_match, review_status
) values
  ('00000000-0000-0000-0000-000000000011', 'Provider A Services', 'pending', 'test-verification-provider-a', false, 'pending'),
  ('00000000-0000-0000-0000-000000000012', 'Provider B Services', 'pending', 'test-verification-provider-b', false, 'pending');

insert into public.identity_verifications (
  id, user_id, provider_name, provider_reference, status,
  assurance_level, consent_version, consent_recorded_at
) values
  ('00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000011', 'mock', 'identity-provider-a', 'pending', 'test-private-provider-a', 'test-v1', now()),
  ('00000000-0000-0000-0000-000000000602', '00000000-0000-0000-0000-000000000012', 'mock', 'identity-provider-b', 'pending', 'test-private-provider-b', 'test-v1', now());

insert into public.service_categories (id, slug, name, active) values
  ('00000000-0000-0000-0000-000000000100', 'test-cleaning', 'Test Cleaning', true);

set local lekkadeall.allow_marketplace_state_transition = 'on';

insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at
) values
  (
    '00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000100', 'Confirmed cleaning request',
    'Confirmed request belonging to Customer A.', 'Die Bult', 'Potchefstroom',
    now() + interval '2 days', 60000,
    'awarded', now() + interval '1 day'
  ),
  (
    '00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000100', 'Unconfirmed cleaning request',
    'Unconfirmed request belonging to Customer B.', 'Baillie Park', 'Potchefstroom',
    now() + interval '3 days', 70000,
    'open', now() + interval '2 days'
  ),
  (
    '00000000-0000-0000-0000-000000000203', '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000100', 'Draft cleaning request',
    'Draft request with safe public description for Customer B.', 'Baillie Park', 'Potchefstroom',
    now() + interval '4 days', 80000,
    'draft', null
  );

insert into private.service_request_addresses (
  request_id, precise_address_ciphertext
) values
  (
    '00000000-0000-0000-0000-000000000201',
    'enc:test-customer-a-confirmed-address'
  ),
  (
    '00000000-0000-0000-0000-000000000202',
    'enc:test-customer-b-unconfirmed-address'
  );

insert into public.bids (
  id, request_id, provider_id, amount_minor, proposed_start,
  message, status, expires_at
) values
  (
    '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000011', 55000, now() + interval '2 days',
    'Accepted test bid from Provider A.', 'accepted', now() + interval '1 day'
  ),
  (
    '00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000202',
    '00000000-0000-0000-0000-000000000012', 65000, now() + interval '3 days',
    'Test bid awaiting payment confirmation.', 'accepted', now() + interval '2 days'
  );

insert into public.bookings (
  id, public_reference, request_id, bid_id, customer_id, provider_id,
  service_amount_minor, platform_fee_minor, scheduled_start, status
) values
  (
    '00000000-0000-0000-0000-000000000401', 'TEST-CONFIRMED-BOOKING',
    '00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011',
    55000, 2750, now() + interval '2 days', 'scheduled'
  ),
  (
    '00000000-0000-0000-0000-000000000402', 'TEST-UNCONFIRMED-BOOKING',
    '00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000302',
    '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000012',
    65000, 3250, now() + interval '3 days', 'payment_pending'
  );

insert into public.payments (
  id, booking_id, provider_name, provider_reference, status,
  amount_minor, release_paused, funded_at, paid_at, refunded_minor
) values (
  '00000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-000000000401',
  'mock', 'test-payment-confirmed-booking', 'paid', 57750, true, now(), now(), 0
);

set local lekkadeall.allow_marketplace_state_transition = 'off';

insert into public.disputes (
  id, public_reference, booking_id, opened_by, issue_code,
  description, status, assigned_to
) values (
  '00000000-0000-0000-0000-000000000701', 'TEST-DISPUTE-001',
  '00000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000001',
  'service_incomplete', 'Test dispute opened by Customer A for RLS coverage.',
  'under_review', '00000000-0000-0000-0000-000000000099'
);

insert into public.audit_events (actor_id, action, object_type, object_id, reason) values (
  '00000000-0000-0000-0000-000000000099',
  'test.seeded', 'booking', 'TEST-AUDIT-EVENT', 'RLS fixture'
);
