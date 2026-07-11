-- Ticket 5: strengthen exact-address privacy after the initial isolation work.
-- This migration keeps exact addresses out of public request rows, adds the
-- customer owner to the private address record, requires safe functions for
-- address access, and blocks likely exact-address material in public request
-- descriptions before publication.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;

alter table private.service_request_addresses
  add column if not exists customer_id uuid references public.profiles(id) on delete cascade;

update private.service_request_addresses sra
set customer_id = sr.customer_id
from public.service_requests sr
where sr.id = sra.request_id
  and sra.customer_id is null;

alter table private.service_request_addresses
  alter column customer_id set not null;

create index if not exists service_request_addresses_customer_idx
on private.service_request_addresses(customer_id);

create or replace function private.enforce_service_request_address_owner()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_customer_id uuid;
begin
  select sr.customer_id
    into v_customer_id
  from public.service_requests sr
  where sr.id = new.request_id;

  if not found then
    raise exception 'Service request % does not exist', new.request_id
      using errcode = '23503';
  end if;

  if new.customer_id is null then
    new.customer_id := v_customer_id;
  elsif new.customer_id <> v_customer_id then
    raise exception 'Address customer_id must match service request customer_id'
      using errcode = '23514';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists enforce_service_request_address_owner on private.service_request_addresses;
create trigger enforce_service_request_address_owner
before insert or update of request_id, customer_id, precise_address_ciphertext
on private.service_request_addresses
for each row execute function private.enforce_service_request_address_owner();

comment on column private.service_request_addresses.customer_id is
  'Owner copied from public.service_requests.customer_id for private address ownership checks. Maintained by trigger.';

-- No frontend or service-role direct table access. Server/admin access must go
-- through audited SECURITY DEFINER functions.
revoke all on private.service_request_addresses from public, anon, authenticated, service_role;

create or replace function public.service_request_description_has_exact_address_risk(
  p_description text
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select
    coalesce(p_description, '') ~* '(^|[^[:alnum:]])[0-9]{1,5}[[:space:]]+[[:alpha:]][[:alnum:] .-]{1,80}[[:space:]]+(street|st|road|rd|avenue|ave|drive|dr|lane|ln|way|close|crescent|cres|boulevard|blvd|place|pl|terrace|terr)([^[:alnum:]]|$)'
    or coalesce(p_description, '') ~* '(^|[^[:alnum:]])(unit|flat|room|apt|apartment|suite)[[:space:]]*(no\.?|number|#)?[[:space:]]*[[:alnum:]-]{1,10}([^[:alnum:]]|$)'
    or coalesce(p_description, '') ~* '[-+]?[0-9]{1,2}\.[0-9]{4,}[[:space:]]*,[[:space:]]*[-+]?[0-9]{1,3}\.[0-9]{4,}'
    or coalesce(p_description, '') ~* '(^|[^[:alnum:]])(\+27|0)[0-9][0-9[:space:]-]{7,}[0-9]([^[:alnum:]]|$)'
    or coalesce(p_description, '') ~* '(^|[^[:alnum:]])(house|stand|erf)[[:space:]]*(no\.?|number|#)?[[:space:]]*[0-9]{1,6}([^[:alnum:]]|$)';
$$;

comment on function public.service_request_description_has_exact_address_risk(text) is
  'Conservative public-description detector for likely exact addresses, unit/room references, GPS coordinates, and phone numbers. False negatives remain possible; application UX should still guide users not to include exact addresses in public text.';

create or replace function private.prevent_public_request_description_exact_address_material()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'open'
     and public.service_request_description_has_exact_address_risk(new.description) then
    raise exception 'Public request description appears to contain exact address, GPS, unit/room, or phone material'
      using errcode = '22023';
  end if;

  return new;
end;
$$;

drop trigger if exists prevent_public_request_description_exact_address_material on public.service_requests;
create trigger prevent_public_request_description_exact_address_material
before insert or update of description, status
on public.service_requests
for each row execute function private.prevent_public_request_description_exact_address_material();

create or replace function public.customer_get_service_request_address(
  p_request_id uuid
)
returns table (
  precise_address_ciphertext text
)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to read a request address'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.service_requests sr
    where sr.id = p_request_id
      and sr.customer_id = v_actor_id
  ) then
    raise exception 'Request not found or not owned by caller'
      using errcode = '42501';
  end if;

  return query
  select sra.precise_address_ciphertext
  from private.service_request_addresses sra
  where sra.request_id = p_request_id
    and sra.customer_id = v_actor_id;
end;
$$;

create or replace function public.customer_upsert_service_request_address(
  p_request_id uuid,
  p_precise_address_ciphertext text
)
returns void
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_request public.service_requests%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to update a request address'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_precise_address_ciphertext, '')), '') is null then
    raise exception 'Precise address ciphertext is required'
      using errcode = '22023';
  end if;

  if char_length(trim(p_precise_address_ciphertext)) > 4096 then
    raise exception 'Precise address ciphertext is too long'
      using errcode = '22023';
  end if;

  select *
    into v_request
  from public.service_requests
  where id = p_request_id
  for update;

  if not found or v_request.customer_id <> v_actor_id then
    raise exception 'Request not found or not owned by caller'
      using errcode = '42501';
  end if;

  if v_request.status <> 'draft' then
    raise exception 'Precise address may only be updated while the request is still draft'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.bookings b
    where b.request_id = p_request_id
  ) then
    raise exception 'Precise address may not be changed after provider selection'
      using errcode = '42501';
  end if;

  insert into private.service_request_addresses (
    request_id,
    customer_id,
    precise_address_ciphertext
  ) values (
    p_request_id,
    v_request.customer_id,
    trim(p_precise_address_ciphertext)
  )
  on conflict (request_id) do update
  set customer_id = excluded.customer_id,
      precise_address_ciphertext = excluded.precise_address_ciphertext,
      updated_at = now();

  perform private.append_audit_event(
    v_actor_id,
    'customer.request_address_upserted',
    'service_request',
    p_request_id::text,
    'Customer updated draft request precise address through controlled function',
    jsonb_build_object(
      'request_id', p_request_id,
      'customer_id', v_request.customer_id
    )
  );
end;
$$;

drop function if exists public.reveal_confirmed_booking_address(uuid);
create function public.reveal_confirmed_booking_address(
  p_booking_id uuid
)
returns table (
  precise_address_ciphertext text
)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_booking record;
  v_precise_address_ciphertext text;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to reveal a booking address'
      using errcode = '42501';
  end if;

  if not public.is_approved_provider(v_actor_id) then
    raise exception 'Only an active, approved provider may reveal a confirmed booking address'
      using errcode = '42501';
  end if;

  select
    b.id,
    b.request_id,
    b.customer_id,
    b.provider_id,
    b.status
    into v_booking
  from public.bookings b
  where b.id = p_booking_id;

  if not found or v_booking.provider_id <> v_actor_id then
    raise exception 'Booking not found for selected provider'
      using errcode = '42501';
  end if;

  if not public.is_address_revealable_booking_status(v_booking.status) then
    raise exception 'Booking is not confirmed for address reveal'
      using errcode = '42501';
  end if;

  select sra.precise_address_ciphertext
    into v_precise_address_ciphertext
  from private.service_request_addresses sra
  where sra.request_id = v_booking.request_id
    and sra.customer_id = v_booking.customer_id;

  if v_precise_address_ciphertext is null then
    raise exception 'Precise address is unavailable for this booking'
      using errcode = '02000';
  end if;

  perform private.append_audit_event(
    v_actor_id,
    'booking.address_revealed',
    'booking',
    p_booking_id::text,
    'Selected provider revealed confirmed booking address',
    jsonb_build_object(
      'booking_id', p_booking_id,
      'request_id', v_booking.request_id,
      'provider_id', v_actor_id,
      'booking_status', v_booking.status
    )
  );

  return query
  select v_precise_address_ciphertext;
end;
$$;

create or replace function public.admin_get_service_request_address(
  p_request_id uuid,
  p_reason text
)
returns table (
  precise_address_ciphertext text
)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_precise_address_ciphertext text;
  v_customer_id uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'Only platform admins or service-role server context may access request addresses administratively'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required for administrative address access'
      using errcode = '22023';
  end if;

  select sra.precise_address_ciphertext, sra.customer_id
    into v_precise_address_ciphertext, v_customer_id
  from private.service_request_addresses sra
  where sra.request_id = p_request_id;

  if v_precise_address_ciphertext is null then
    raise exception 'Precise address is unavailable for this request'
      using errcode = '02000';
  end if;

  perform private.append_audit_event(
    v_actor_id,
    'admin.service_request_address_accessed',
    'service_request',
    p_request_id::text,
    p_reason,
    jsonb_build_object(
      'request_id', p_request_id,
      'customer_id', v_customer_id
    )
  );

  return query
  select v_precise_address_ciphertext;
end;
$$;

comment on function public.customer_get_service_request_address(uuid) is
  'Controlled customer exact-address read for the customer who owns the request. Providers cannot use this function.';
comment on function public.customer_upsert_service_request_address(uuid, text) is
  'Controlled customer exact-address upsert for draft requests only. Stores ciphertext in the private address table.';
comment on function public.reveal_confirmed_booking_address(uuid) is
  'Audited exact-address reveal. Returns only address ciphertext and only for the selected approved provider after confirmed/revealable booking status.';
comment on function public.admin_get_service_request_address(uuid, text) is
  'Audited administrative exact-address access. Use for support/server workflows only with a reason.';

revoke all on function private.enforce_service_request_address_owner() from public, anon, authenticated;
revoke all on function private.prevent_public_request_description_exact_address_material() from public, anon, authenticated;

revoke all on function public.service_request_description_has_exact_address_risk(text) from public, anon;
grant execute on function public.service_request_description_has_exact_address_risk(text) to authenticated, service_role;

revoke all on function public.customer_get_service_request_address(uuid) from public, anon;
grant execute on function public.customer_get_service_request_address(uuid) to authenticated, service_role;

revoke all on function public.customer_upsert_service_request_address(uuid, text) from public, anon;
grant execute on function public.customer_upsert_service_request_address(uuid, text) to authenticated, service_role;

revoke all on function public.reveal_confirmed_booking_address(uuid) from public, anon;
grant execute on function public.reveal_confirmed_booking_address(uuid) to authenticated, service_role;

revoke all on function public.admin_get_service_request_address(uuid, text) from public, anon;
grant execute on function public.admin_get_service_request_address(uuid, text) to authenticated, service_role;
