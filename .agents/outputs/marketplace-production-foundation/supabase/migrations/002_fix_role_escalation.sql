-- Ticket 1: block role/provider-status escalation through direct client writes.
-- Privileged changes must use audited SECURITY DEFINER functions.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;

drop policy if exists "profile owner updates self" on public.profiles;
drop policy if exists "provider owns provider profile" on public.provider_profiles;

comment on column public.profiles.role is
  'Privileged account role. Never client-editable; change only through audited admin functions.';
comment on column public.profiles.account_status is
  'Privileged account lifecycle status. Never client-editable; change only through audited admin functions.';
comment on column public.provider_profiles.verification_status is
  'Provider verification status. Never client-editable; set only through trusted identity/admin flows.';
comment on column public.provider_profiles.review_status is
  'Provider review/approval status. Never client-editable; set only through audited admin functions.';

revoke update on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, phone_e164, suburb, city, avatar_path) on public.profiles to authenticated;

revoke update on public.provider_profiles from anon, authenticated;
grant select on public.provider_profiles to authenticated;
grant update (business_name, bio, service_radius_km) on public.provider_profiles to authenticated;

revoke insert, update, delete on public.identity_verifications from anon, authenticated;

create policy "profile owner updates safe profile fields"
on public.profiles
for update
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "provider updates safe provider profile fields"
on public.provider_profiles
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create or replace function private.protect_profile_privileged_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('lekkadeall.allow_privileged_profile_update', true), 'off') <> 'on' then
    if new.role is distinct from old.role then
      raise exception 'profiles.role is privileged and cannot be changed directly'
        using errcode = '42501';
    end if;

    if new.account_status is distinct from old.account_status then
      raise exception 'profiles.account_status is privileged and cannot be changed directly'
        using errcode = '42501';
    end if;
  end if;

  new.updated_at = now();
  return new;
end;
$$;

create or replace function private.protect_provider_profile_privileged_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('lekkadeall.allow_privileged_provider_profile_update', true), 'off') <> 'on' then
    if new.verification_status is distinct from old.verification_status
       or new.verification_reference is distinct from old.verification_reference
       or new.bank_name_match is distinct from old.bank_name_match
       or new.review_status is distinct from old.review_status
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'provider verification/review fields are privileged and cannot be changed directly'
        using errcode = '42501';
    end if;
  end if;

  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists protect_profile_privileged_fields on public.profiles;
create trigger protect_profile_privileged_fields
before update on public.profiles
for each row execute function private.protect_profile_privileged_fields();

drop trigger if exists protect_provider_profile_privileged_fields on public.provider_profiles;
create trigger protect_provider_profile_privileged_fields
before update on public.provider_profiles
for each row execute function private.protect_provider_profile_privileged_fields();

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    coalesce(current_setting('request.jwt.claim.role', true) = 'service_role', false)
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
        and p.account_status = 'active'
    );
$$;

create or replace function private.append_audit_event(
  p_actor_id uuid,
  p_action text,
  p_object_type text,
  p_object_id text,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_audit_id bigint;
begin
  insert into public.audit_events (
    actor_id, action, object_type, object_id, reason, metadata
  ) values (
    p_actor_id,
    p_action,
    p_object_type,
    p_object_id,
    nullif(trim(coalesce(p_reason, '')), ''),
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_audit_id;

  return v_audit_id;
end;
$$;

create or replace function private.prevent_audit_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'audit_events are append-only'
    using errcode = '42501';
end;
$$;

drop trigger if exists audit_events_append_only on public.audit_events;
create trigger audit_events_append_only
before update or delete on public.audit_events
for each row execute function private.prevent_audit_event_mutation();

create or replace function public.admin_set_user_role(
  p_user_id uuid,
  p_role public.user_role,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_old_role public.user_role;
begin
  if not public.is_platform_admin() then
    raise exception 'Only platform admins may change user roles'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required for privileged role changes'
      using errcode = '22023';
  end if;

  if v_actor_id is not null and p_user_id = v_actor_id then
    raise exception 'Admins may not change their own role'
      using errcode = '42501';
  end if;

  select role
    into v_old_role
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'Profile % does not exist', p_user_id
      using errcode = '02000';
  end if;

  if v_old_role is distinct from p_role then
    perform set_config('lekkadeall.allow_privileged_profile_update', 'on', true);

    update public.profiles
    set role = p_role,
        updated_at = now()
    where id = p_user_id;

    perform set_config('lekkadeall.allow_privileged_profile_update', 'off', true);

    perform private.append_audit_event(
      v_actor_id,
      'admin.user_role_changed',
      'profile',
      p_user_id::text,
      p_reason,
      jsonb_build_object(
        'old_role', v_old_role,
        'new_role', p_role
      )
    );
  end if;
end;
$$;

create or replace function public.admin_set_account_status(
  p_user_id uuid,
  p_account_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_old_status text;
begin
  if not public.is_platform_admin() then
    raise exception 'Only platform admins may change account status'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required for privileged account-status changes'
      using errcode = '22023';
  end if;

  select account_status
    into v_old_status
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'Profile % does not exist', p_user_id
      using errcode = '02000';
  end if;

  if v_old_status is distinct from p_account_status then
    perform set_config('lekkadeall.allow_privileged_profile_update', 'on', true);

    update public.profiles
    set account_status = p_account_status,
        updated_at = now()
    where id = p_user_id;

    perform set_config('lekkadeall.allow_privileged_profile_update', 'off', true);

    perform private.append_audit_event(
      v_actor_id,
      'admin.account_status_changed',
      'profile',
      p_user_id::text,
      p_reason,
      jsonb_build_object(
        'old_account_status', v_old_status,
        'new_account_status', p_account_status
      )
    );
  end if;
end;
$$;

create or replace function public.admin_set_provider_review_status(
  p_provider_id uuid,
  p_review_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_old_status text;
begin
  if not public.is_platform_admin() then
    raise exception 'Only platform admins may change provider review status'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required for privileged provider-status changes'
      using errcode = '22023';
  end if;

  select review_status
    into v_old_status
  from public.provider_profiles
  where user_id = p_provider_id
  for update;

  if not found then
    raise exception 'Provider profile % does not exist', p_provider_id
      using errcode = '02000';
  end if;

  if v_old_status is distinct from p_review_status then
    perform set_config('lekkadeall.allow_privileged_provider_profile_update', 'on', true);

    update public.provider_profiles
    set review_status = p_review_status,
        reviewed_by = v_actor_id,
        reviewed_at = now(),
        updated_at = now()
    where user_id = p_provider_id;

    perform set_config('lekkadeall.allow_privileged_provider_profile_update', 'off', true);

    perform private.append_audit_event(
      v_actor_id,
      'admin.provider_review_status_changed',
      'provider_profile',
      p_provider_id::text,
      p_reason,
      jsonb_build_object(
        'old_review_status', v_old_status,
        'new_review_status', p_review_status
      )
    );
  end if;
end;
$$;

create or replace function public.admin_set_provider_verification_status(
  p_provider_id uuid,
  p_verification_status public.verification_status,
  p_verification_reference text,
  p_bank_name_match boolean,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_old_status public.verification_status;
  v_old_reference text;
  v_old_bank_name_match boolean;
begin
  if not public.is_platform_admin() then
    raise exception 'Only platform admins may change provider verification status'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required for privileged verification changes'
      using errcode = '22023';
  end if;

  select verification_status, verification_reference, bank_name_match
    into v_old_status, v_old_reference, v_old_bank_name_match
  from public.provider_profiles
  where user_id = p_provider_id
  for update;

  if not found then
    raise exception 'Provider profile % does not exist', p_provider_id
      using errcode = '02000';
  end if;

  if v_old_status is distinct from p_verification_status
     or v_old_reference is distinct from p_verification_reference
     or v_old_bank_name_match is distinct from p_bank_name_match then
    perform set_config('lekkadeall.allow_privileged_provider_profile_update', 'on', true);

    update public.provider_profiles
    set verification_status = p_verification_status,
        verification_reference = p_verification_reference,
        bank_name_match = p_bank_name_match,
        updated_at = now()
    where user_id = p_provider_id;

    perform set_config('lekkadeall.allow_privileged_provider_profile_update', 'off', true);

    perform private.append_audit_event(
      v_actor_id,
      'admin.provider_verification_status_changed',
      'provider_profile',
      p_provider_id::text,
      p_reason,
      jsonb_build_object(
        'old_verification_status', v_old_status,
        'new_verification_status', p_verification_status,
        'old_verification_reference', v_old_reference,
        'new_verification_reference', p_verification_reference,
        'old_bank_name_match', v_old_bank_name_match,
        'new_bank_name_match', p_bank_name_match
      )
    );
  end if;
end;
$$;

revoke all on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated, service_role;

revoke all on function public.admin_set_user_role(uuid, public.user_role, text) from public, anon;
grant execute on function public.admin_set_user_role(uuid, public.user_role, text) to authenticated, service_role;

revoke all on function public.admin_set_account_status(uuid, text, text) from public, anon;
grant execute on function public.admin_set_account_status(uuid, text, text) to authenticated, service_role;

revoke all on function public.admin_set_provider_review_status(uuid, text, text) from public, anon;
grant execute on function public.admin_set_provider_review_status(uuid, text, text) to authenticated, service_role;

revoke all on function public.admin_set_provider_verification_status(uuid, public.verification_status, text, boolean, text) from public, anon;
grant execute on function public.admin_set_provider_verification_status(uuid, public.verification_status, text, boolean, text) to authenticated, service_role;

revoke all on function private.append_audit_event(uuid, text, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function private.prevent_audit_event_mutation() from public, anon, authenticated;
revoke all on function private.protect_profile_privileged_fields() from public, anon, authenticated;
revoke all on function private.protect_provider_profile_privileged_fields() from public, anon, authenticated;
