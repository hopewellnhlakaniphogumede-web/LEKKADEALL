-- Ticket 9B: securely provision the minimum public profile for each Auth user.
-- The browser never inserts profiles and Auth metadata is deliberately ignored.

create or replace function private.ensure_auth_user_profile(
  p_user_id uuid,
  p_source text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_created boolean := false;
begin
  if p_source is null
     or p_source not in ('auth_trigger', 'migration_backfill') then
    raise exception 'Unsupported profile provisioning source'
      using errcode = '22023';
  end if;

  insert into public.profiles (
    id,
    role,
    display_name,
    phone_e164,
    phone_verified_at,
    email_verified_at,
    suburb,
    city,
    avatar_path,
    account_status
  ) values (
    p_user_id,
    'customer'::public.user_role,
    'New customer',
    null,
    null,
    null,
    null,
    'Potchefstroom',
    null,
    'active'
  )
  on conflict (id) do nothing
  returning true into v_created;

  v_created := coalesce(v_created, false);

  if v_created then
    perform private.append_audit_event(
      null,
      'system.profile_provisioned',
      'profile',
      p_user_id::text,
      case p_source
        when 'auth_trigger' then 'auth user registration'
        else 'existing auth user backfill'
      end,
      pg_catalog.jsonb_build_object(
        'source', p_source,
        'version', 1
      )
    );
  end if;

  return v_created;
end;
$$;

create or replace function private.provision_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op <> 'INSERT'
     or tg_when <> 'AFTER'
     or tg_table_schema <> 'auth'
     or tg_table_name <> 'users' then
    raise exception 'Invalid profile provisioning trigger context'
      using errcode = '55000';
  end if;

  perform private.ensure_auth_user_profile(new.id, 'auth_trigger');
  return new;
end;
$$;

revoke all on function private.ensure_auth_user_profile(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function private.provision_auth_user_profile()
  from public, anon, authenticated, service_role;

drop trigger if exists provision_auth_user_profile_after_insert on auth.users;
create trigger provision_auth_user_profile_after_insert
after insert on auth.users
for each row execute function private.provision_auth_user_profile();

-- Close the deployment race by installing the trigger before the idempotent
-- backfill. Existing profiles are never updated or otherwise normalized.
do $$
declare
  v_user_id uuid;
begin
  for v_user_id in
    select u.id
    from auth.users as u
    left join public.profiles as p on p.id = u.id
    where p.id is null
    order by u.id
  loop
    perform private.ensure_auth_user_profile(v_user_id, 'migration_backfill');
  end loop;

  if exists (
    select 1
    from auth.users as u
    left join public.profiles as p on p.id = u.id
    where p.id is null
  ) then
    raise exception 'Profile provisioning backfill left Auth users without profiles'
      using errcode = '23514';
  end if;
end;
$$;
