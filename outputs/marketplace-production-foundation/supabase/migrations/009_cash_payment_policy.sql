-- Ticket 7C: cash payment policy enforcement.
-- MVP policy decision: cash/off-platform cash payments are disabled.
-- This migration deliberately does not implement customer/provider cash
-- confirmation, admin cash override, cash disputes, payout release, real payment
-- provider integration, real webhooks, or UI.

create schema if not exists private;

alter table public.payments
  add column if not exists payment_method text;

update public.payments
set payment_method = 'platform_online_pending'
where payment_method is null;

alter table public.payments
  alter column payment_method set default 'platform_online_pending',
  alter column payment_method set not null;

alter table public.payments
  drop constraint if exists payments_payment_method_check,
  add constraint payments_payment_method_check
    check (payment_method in (
      'platform_online_pending',
      'platform_online',
      'sandbox_online',
      'manual_sandbox_online'
    ));

comment on column public.payments.payment_method is
  'Ticket 7C MVP payment method marker. Cash/off_platform_cash is disabled for MVP; only protected online/sandbox methods are allowed.';

create or replace function private.reject_disabled_cash_payment_method()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(coalesce(new.payment_method, '')) in (
    'cash',
    'off_platform_cash',
    'cash_selected',
    'customer_cash_confirmed',
    'provider_cash_confirmed',
    'cash_confirmed',
    'cash_disputed',
    'cash_cancelled',
    'cash_unverified'
  ) then
    raise exception 'Cash payments are disabled for MVP.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists reject_disabled_cash_payment_method on public.payments;
create trigger reject_disabled_cash_payment_method
before insert or update of payment_method on public.payments
for each row execute function private.reject_disabled_cash_payment_method();

create or replace function private.prevent_cash_or_payout_release_payment_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment_method text := lower(coalesce(new.metadata ->> 'payment_method', ''));
  v_cash_status text := lower(coalesce(new.metadata ->> 'cash_payment_status', ''));
  v_release_status text := lower(coalesce(new.metadata ->> 'release_status', ''));
begin
  if v_payment_method in (
       'cash',
       'off_platform_cash',
       'cash_selected',
       'customer_cash_confirmed',
       'provider_cash_confirmed',
       'cash_confirmed',
       'cash_disputed',
       'cash_cancelled',
       'cash_unverified'
     )
     or v_cash_status in (
       'cash_selected',
       'customer_cash_confirmed',
       'provider_cash_confirmed',
       'cash_confirmed',
       'cash_disputed',
       'cash_cancelled',
       'cash_unverified'
     ) then
    raise exception 'Cash payments are disabled for MVP.'
      using errcode = '42501';
  end if;

  if v_release_status = 'released'
     or lower(new.event_type) in ('payout_released', 'release_released') then
    raise exception 'Payout release is not implemented for MVP.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists prevent_cash_or_payout_release_payment_event on public.payment_events;
create trigger prevent_cash_or_payout_release_payment_event
before insert on public.payment_events
for each row execute function private.prevent_cash_or_payout_release_payment_event();

create or replace function public.customer_select_cash_payment(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  raise exception 'Cash payments are disabled for MVP.'
    using errcode = '42501';
end;
$$;

create or replace function public.provider_select_cash_payment(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  raise exception 'Cash payments are disabled for MVP.'
    using errcode = '42501';
end;
$$;

comment on function public.customer_select_cash_payment(uuid) is
  'Ticket 7C explicit MVP cash policy function. Always rejects because cash payments are disabled for MVP.';
comment on function public.provider_select_cash_payment(uuid) is
  'Ticket 7C explicit MVP cash policy function. Always rejects because cash payments are disabled for MVP.';

revoke all on function private.reject_disabled_cash_payment_method() from public, anon, authenticated, service_role;
revoke all on function private.prevent_cash_or_payout_release_payment_event() from public, anon, authenticated, service_role;

revoke all on function public.customer_select_cash_payment(uuid) from public, anon;
revoke all on function public.provider_select_cash_payment(uuid) from public, anon;
grant execute on function public.customer_select_cash_payment(uuid) to authenticated, service_role;
grant execute on function public.provider_select_cash_payment(uuid) to authenticated, service_role;
