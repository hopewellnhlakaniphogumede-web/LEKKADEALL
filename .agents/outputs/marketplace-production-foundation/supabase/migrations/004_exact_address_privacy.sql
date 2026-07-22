-- Ticket 3: isolate exact customer addresses and reveal them only to the
-- selected provider after a booking reaches a confirmed/revealable state.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;
grant usage on schema private to service_role;

create table if not exists private.service_request_addresses (
  request_id uuid primary key references public.service_requests(id) on delete cascade,
  precise_address_ciphertext text not null check (
    char_length(trim(precise_address_ciphertext)) between 1 and 4096
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table private.service_request_addresses is
  'Private exact-address store. Frontend roles must never access this table directly; use audited server-side functions only.';

alter table private.service_request_addresses enable row level security;
revoke all on private.service_request_addresses from public, anon, authenticated;
grant select, insert, update, delete on private.service_request_addresses to service_role;

-- Migrate any existing precise addresses out of the frontend-facing request row.
insert into private.service_request_addresses (
  request_id,
  precise_address_ciphertext,
  created_at,
  updated_at
)
select
  id,
  precise_address_ciphertext,
  created_at,
  updated_at
from public.service_requests
where precise_address_ciphertext is not null
on conflict (request_id) do update
set precise_address_ciphertext = excluded.precise_address_ciphertext,
    updated_at = now();

update public.service_requests
set precise_address_ciphertext = null
where precise_address_ciphertext is not null;

comment on column public.service_requests.precise_address_ciphertext is
  'Deprecated compatibility column. Must remain null in production; exact addresses are stored in private.service_request_addresses and revealed only through audited functions.';

create or replace function private.prevent_service_request_precise_address_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.precise_address_ciphertext is not null then
      raise exception 'service_requests.precise_address_ciphertext is deprecated; use public.customer_upsert_service_request_address'
        using errcode = '42501';
    end if;
  elsif tg_op = 'UPDATE' then
    if new.precise_address_ciphertext is distinct from old.precise_address_ciphertext then
      raise exception 'service_requests.precise_address_ciphertext is deprecated; use public.customer_upsert_service_request_address'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists prevent_service_request_precise_address_write on public.service_requests;
create trigger prevent_service_request_precise_address_write
before insert or update of precise_address_ciphertext on public.service_requests
for each row execute function private.prevent_service_request_precise_address_write();

-- Remove broad direct INSERT/UPDATE table privileges, then re-grant only
-- non-exact-address columns. RLS owner policies still decide which rows a
-- customer may create/update; this narrows the address column surface.
revoke insert, update on public.service_requests from anon, authenticated;

grant insert (
  customer_id,
  category_id,
  title,
  description,
  suburb,
  city,
  requested_start,
  budget_minor,
  status,
  closes_at
) on public.service_requests to authenticated;

grant update (
  category_id,
  title,
  description,
  suburb,
  city,
  requested_start,
  budget_minor,
  status,
  closes_at,
  updated_at
) on public.service_requests to authenticated;

create or replace function public.is_address_revealable_booking_status(
  p_status public.booking_status
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_status in (
    'funded',
    'scheduled',
    'in_progress',
    'completed',
    'disputed',
    'partially_refunded',
    'payout_released'
  );
$$;

comment on function public.is_address_revealable_booking_status(public.booking_status) is
  'Defines booking states where the selected provider may reveal the private exact address. payment_pending, cancelled, and fully refunded bookings are not revealable.';

create or replace function public.list_provider_open_request_summaries(
  p_city text default null,
  p_category_id uuid default null,
  p_limit integer default 50
)
returns table (
  request_id uuid,
  category_id uuid,
  title text,
  description text,
  suburb text,
  city text,
  requested_start timestamptz,
  budget_minor integer,
  status public.request_status,
  closes_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_approved_provider(auth.uid()) then
    return;
  end if;

  return query
  select
    sr.id,
    sr.category_id,
    sr.title,
    sr.description,
    sr.suburb,
    sr.city,
    sr.requested_start,
    sr.budget_minor,
    sr.status,
    sr.closes_at,
    sr.created_at,
    sr.updated_at
  from public.service_requests sr
  where sr.status = 'open'
    and (sr.closes_at is null or sr.closes_at > now())
    and (p_city is null or sr.city = p_city)
    and (p_category_id is null or sr.category_id = p_category_id)
  order by sr.created_at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
end;
$$;

comment on function public.list_provider_open_request_summaries(text, uuid, integer) is
  'Provider-facing open request summary. Returns only safe request fields and never exposes customer_id or exact address material.';

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

  if v_request.status not in ('draft', 'open') then
    raise exception 'Precise address may only be updated before provider selection/confirmation'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.bookings b
    where b.request_id = p_request_id
      and public.is_address_revealable_booking_status(b.status)
  ) then
    raise exception 'Precise address may not be changed after confirmed booking'
      using errcode = '42501';
  end if;

  insert into private.service_request_addresses (
    request_id,
    precise_address_ciphertext
  ) values (
    p_request_id,
    trim(p_precise_address_ciphertext)
  )
  on conflict (request_id) do update
  set precise_address_ciphertext = excluded.precise_address_ciphertext,
      updated_at = now();

  perform private.append_audit_event(
    v_actor_id,
    'customer.request_address_upserted',
    'service_request',
    p_request_id::text,
    'Customer updated precise request address through controlled function',
    jsonb_build_object('request_id', p_request_id)
  );
end;
$$;

comment on function public.customer_upsert_service_request_address(uuid, text) is
  'Controlled customer address upsert. Stores exact address ciphertext in the private table and never in public.service_requests.';

create or replace function public.reveal_confirmed_booking_address(
  p_booking_id uuid
)
returns table (
  booking_id uuid,
  request_id uuid,
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
  where sra.request_id = v_booking.request_id;

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
  select
    v_booking.id,
    v_booking.request_id,
    v_precise_address_ciphertext;
end;
$$;

comment on function public.reveal_confirmed_booking_address(uuid) is
  'Audited exact-address reveal for the selected approved provider only, and only after booking confirmation/revealable status.';

revoke all on function private.prevent_service_request_precise_address_write() from public, anon, authenticated;

revoke all on function public.is_address_revealable_booking_status(public.booking_status) from public, anon;
grant execute on function public.is_address_revealable_booking_status(public.booking_status) to authenticated, service_role;

revoke all on function public.list_provider_open_request_summaries(text, uuid, integer) from public, anon;
grant execute on function public.list_provider_open_request_summaries(text, uuid, integer) to authenticated, service_role;

revoke all on function public.customer_upsert_service_request_address(uuid, text) from public, anon;
grant execute on function public.customer_upsert_service_request_address(uuid, text) to authenticated, service_role;

revoke all on function public.reveal_confirmed_booking_address(uuid) from public, anon;
grant execute on function public.reveal_confirmed_booking_address(uuid) to authenticated, service_role;
