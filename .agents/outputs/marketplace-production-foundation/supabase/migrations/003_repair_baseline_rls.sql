-- Ticket 2: ensure every public table has RLS enabled and add explicit
-- baseline policies for category, provider-service, and vendor-event access.

create schema if not exists private;

alter table public.profiles enable row level security;
alter table public.provider_profiles enable row level security;
alter table public.service_categories enable row level security;
alter table public.provider_services enable row level security;
alter table public.service_requests enable row level security;
alter table public.bids enable row level security;
alter table public.bookings enable row level security;
alter table public.payments enable row level security;
alter table public.vendor_events enable row level security;
alter table public.identity_verifications enable row level security;
alter table public.disputes enable row level security;
alter table public.dispute_evidence enable row level security;
alter table public.reviews enable row level security;
alter table public.consents enable row level security;
alter table public.data_subject_requests enable row level security;
alter table public.audit_events enable row level security;

create or replace function public.is_approved_provider(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.profiles p
    join public.provider_profiles pp on pp.user_id = p.id
    where p.id = p_user_id
      and p.role = 'provider'
      and p.account_status = 'active'
      and pp.verification_status = 'verified'
      and pp.review_status = 'approved'
  );
$$;

revoke all on function public.is_approved_provider(uuid) from public, anon;
grant execute on function public.is_approved_provider(uuid) to authenticated, service_role;

revoke all on public.vendor_events from anon, authenticated;

grant usage on schema private to service_role;

create or replace function private.record_vendor_event(
  p_provider_name text,
  p_provider_event_id text,
  p_event_type text,
  p_related_reference text,
  p_payload_hash text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
begin
  insert into public.vendor_events (
    provider_name,
    provider_event_id,
    event_type,
    related_reference,
    payload_hash
  ) values (
    p_provider_name,
    p_provider_event_id,
    p_event_type,
    p_related_reference,
    p_payload_hash
  )
  on conflict (provider_name, provider_event_id) do nothing
  returning id into v_event_id;

  if v_event_id is null then
    select id
      into v_event_id
    from public.vendor_events
    where provider_name = p_provider_name
      and provider_event_id = p_provider_event_id;
  end if;

  return v_event_id;
end;
$$;

revoke all on function private.record_vendor_event(text, text, text, text, text) from public, anon, authenticated;
grant execute on function private.record_vendor_event(text, text, text, text, text) to service_role;

revoke select on public.provider_profiles from anon;
grant select on public.provider_profiles to authenticated;

drop policy if exists "approved providers are discoverable" on public.provider_profiles;
create policy "approved providers are discoverable"
on public.provider_profiles
for select
using (
  public.is_approved_provider(user_id)
  or auth.uid() = user_id
);

revoke all on public.service_categories from anon, authenticated;
grant select on public.service_categories to anon, authenticated;

drop policy if exists "active service categories are readable" on public.service_categories;
create policy "active service categories are readable"
on public.service_categories
for select
using (active = true);

revoke all on public.provider_services from anon, authenticated;
grant select on public.provider_services to authenticated;
grant insert, update, delete on public.provider_services to authenticated;

drop policy if exists "approved provider services are readable" on public.provider_services;
create policy "approved provider services are readable"
on public.provider_services
for select
using (
  (active = true and public.is_approved_provider(provider_id))
  or auth.uid() = provider_id
);

drop policy if exists "approved provider manages own services" on public.provider_services;
create policy "approved provider manages own services"
on public.provider_services
for insert
with check (
  auth.uid() = provider_id
  and public.is_approved_provider(auth.uid())
);

drop policy if exists "approved provider updates own services" on public.provider_services;
create policy "approved provider updates own services"
on public.provider_services
for update
using (
  auth.uid() = provider_id
  and public.is_approved_provider(auth.uid())
)
with check (
  auth.uid() = provider_id
  and public.is_approved_provider(auth.uid())
);

drop policy if exists "approved provider deletes own services" on public.provider_services;
create policy "approved provider deletes own services"
on public.provider_services
for delete
using (
  auth.uid() = provider_id
  and public.is_approved_provider(auth.uid())
);

drop policy if exists "providers see open requests" on public.service_requests;
drop policy if exists "approved providers see open requests" on public.service_requests;
create policy "approved providers see open requests"
on public.service_requests
for select
using (
  status = 'open'
  and public.is_approved_provider(auth.uid())
);

revoke select on public.service_requests from anon, authenticated;
grant select (
  id,
  category_id,
  title,
  description,
  suburb,
  city,
  requested_start,
  budget_minor,
  status,
  closes_at,
  created_at,
  updated_at
) on public.service_requests to authenticated;

revoke all on public.audit_events from anon, authenticated;
revoke insert, update, delete on public.identity_verifications from anon, authenticated;
grant select on public.identity_verifications to authenticated;
