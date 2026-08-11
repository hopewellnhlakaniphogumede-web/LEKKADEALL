-- Ticket 10B: separate marketplace eligibility from identity verification.
-- Manual-pilot eligibility is a short-lived, reviewed marketplace decision;
-- it never sets or implies vendor-backed identity verification.

create table private.provider_marketplace_eligibility (
  provider_id pg_catalog.uuid primary key
    references public.provider_profiles(user_id) on delete cascade,
  status pg_catalog.text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'suspended', 'expired')),
  basis pg_catalog.text
    check (basis is null or basis in ('manual_pilot', 'verified_identity')),
  policy_version pg_catalog.text not null default 'provider-eligibility-v1',
  expires_at pg_catalog.timestamptz,
  current_decision_id pg_catalog.uuid,
  reviewer_id pg_catalog.uuid references public.profiles(id),
  reason_code pg_catalog.text,
  created_at pg_catalog.timestamptz not null default pg_catalog.transaction_timestamp(),
  updated_at pg_catalog.timestamptz not null default pg_catalog.transaction_timestamp(),
  check (
    (status in ('pending', 'rejected') and basis is null and expires_at is null)
    or
    (status in ('approved', 'suspended', 'expired') and basis is not null and expires_at is not null)
  ),
  check (
    (current_decision_id is null and reviewer_id is null and reason_code is null)
    or
    (current_decision_id is not null and reviewer_id is not null and reason_code is not null)
  )
);

create table private.provider_eligibility_decisions (
  id pg_catalog.uuid primary key,
  provider_id pg_catalog.uuid not null
    references public.provider_profiles(user_id) on delete cascade,
  reviewer_id pg_catalog.uuid not null references public.profiles(id),
  action pg_catalog.text not null
    check (action in (
      'approve_manual_pilot',
      'approve_verified_identity',
      'reject',
      'suspend',
      'reinstate_manual_pilot',
      'reopen',
      'renew_manual_pilot',
      'expire'
    )),
  previous_status pg_catalog.text not null
    check (previous_status in ('pending', 'approved', 'rejected', 'suspended', 'expired')),
  new_status pg_catalog.text not null
    check (new_status in ('pending', 'approved', 'rejected', 'suspended', 'expired')),
  basis pg_catalog.text
    check (basis is null or basis in ('manual_pilot', 'verified_identity')),
  policy_version pg_catalog.text not null,
  expires_at pg_catalog.timestamptz,
  reason_code pg_catalog.text not null,
  idempotency_key pg_catalog.uuid not null,
  intent_fingerprint pg_catalog.text not null,
  decided_at pg_catalog.timestamptz not null,
  unique (reviewer_id, idempotency_key)
);

alter table private.provider_marketplace_eligibility
  add constraint provider_marketplace_eligibility_current_decision_fkey
  foreign key (current_decision_id)
  references private.provider_eligibility_decisions(id);

create index provider_eligibility_decisions_provider_idx
  on private.provider_eligibility_decisions(provider_id, decided_at desc);

alter table private.provider_marketplace_eligibility enable row level security;
alter table private.provider_eligibility_decisions enable row level security;

revoke all on private.provider_marketplace_eligibility
  from public, anon, authenticated, service_role;
revoke all on private.provider_eligibility_decisions
  from public, anon, authenticated, service_role;

create or replace function private.prevent_provider_eligibility_decision_mutation()
returns pg_catalog.trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'Provider eligibility decisions are append-only'
    using errcode = '42501';
end;
$$;

create trigger provider_eligibility_decisions_append_only
before update or delete on private.provider_eligibility_decisions
for each row execute function private.prevent_provider_eligibility_decision_mutation();

revoke all on function private.prevent_provider_eligibility_decision_mutation()
  from public, anon, authenticated, service_role;

create or replace function private.initialize_provider_marketplace_eligibility()
returns pg_catalog.trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into private.provider_marketplace_eligibility (
    provider_id,
    status,
    basis,
    policy_version,
    expires_at,
    current_decision_id,
    reviewer_id,
    reason_code,
    created_at,
    updated_at
  ) values (
    new.user_id,
    'pending',
    null,
    'provider-eligibility-v1',
    null,
    null,
    null,
    null,
    pg_catalog.transaction_timestamp(),
    pg_catalog.transaction_timestamp()
  )
  on conflict (provider_id) do nothing;

  return new;
end;
$$;

create trigger initialize_provider_marketplace_eligibility
after insert on public.provider_profiles
for each row execute function private.initialize_provider_marketplace_eligibility();

revoke all on function private.initialize_provider_marketplace_eligibility()
  from public, anon, authenticated, service_role;

-- Existing rows are deliberately reintroduced as pending. No historical
-- review or verification value is silently converted into Ticket 10B
-- marketplace eligibility.
insert into private.provider_marketplace_eligibility (
  provider_id,
  status,
  basis,
  policy_version,
  expires_at,
  current_decision_id,
  reviewer_id,
  reason_code,
  created_at,
  updated_at
)
select
  pp.user_id,
  'pending',
  null,
  'provider-eligibility-v1',
  null,
  null,
  null,
  null,
  pg_catalog.transaction_timestamp(),
  pg_catalog.transaction_timestamp()
from public.provider_profiles as pp
on conflict (provider_id) do nothing;

create or replace function private.is_provider_marketplace_eligible(
  p_provider_id pg_catalog.uuid
)
returns pg_catalog.bool
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case when (
    select
      p.role = 'provider'::public.user_role
      and p.account_status = 'active'
      and pp.review_status = 'approved'
      and eligibility.status = 'approved'
      and eligibility.policy_version = 'provider-eligibility-v1'
      and eligibility.expires_at > pg_catalog.statement_timestamp()
      and eligibility.current_decision_id is not null
      and eligibility.reviewer_id is not null
      and eligibility.reason_code is not null
      and eligibility.basis = 'manual_pilot'
      and pp.verification_status not in (
        'rejected'::public.verification_status,
        'expired'::public.verification_status
      )
    from public.profiles as p
    join public.provider_profiles as pp
      on pp.user_id = p.id
    join private.provider_marketplace_eligibility as eligibility
      on eligibility.provider_id = pp.user_id
    where p.id = p_provider_id
  ) is true then true else false end
$$;

create or replace function private.require_provider_marketplace_eligibility(
  p_provider_id pg_catalog.uuid
)
returns pg_catalog.void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_role public.user_role;
  v_account_status pg_catalog.text;
  v_review_status pg_catalog.text;
  v_verification_status public.verification_status;
  v_status pg_catalog.text;
  v_basis pg_catalog.text;
  v_policy_version pg_catalog.text;
  v_expires_at pg_catalog.timestamptz;
  v_current_decision_id pg_catalog.uuid;
  v_reviewer_id pg_catalog.uuid;
  v_reason_code pg_catalog.text;
begin
  select p.role, p.account_status
    into v_role, v_account_status
  from public.profiles as p
  where p.id = p_provider_id
  for share;

  if not found then
    raise exception 'Provider marketplace capability is unavailable'
      using errcode = '42501';
  end if;

  select pp.review_status, pp.verification_status
    into v_review_status, v_verification_status
  from public.provider_profiles as pp
  where pp.user_id = p_provider_id
  for share;

  if not found then
    raise exception 'Provider marketplace capability is unavailable'
      using errcode = '42501';
  end if;

  select
    eligibility.status,
    eligibility.basis,
    eligibility.policy_version,
    eligibility.expires_at,
    eligibility.current_decision_id,
    eligibility.reviewer_id,
    eligibility.reason_code
    into
      v_status,
      v_basis,
      v_policy_version,
      v_expires_at,
      v_current_decision_id,
      v_reviewer_id,
      v_reason_code
  from private.provider_marketplace_eligibility as eligibility
  where eligibility.provider_id = p_provider_id
  for share;

  if not found
     or v_role <> 'provider'::public.user_role
     or v_account_status <> 'active'
     or v_review_status <> 'approved'
     or v_status <> 'approved'
     or v_basis <> 'manual_pilot'
     or v_verification_status in (
       'rejected'::public.verification_status,
       'expired'::public.verification_status
     )
     or v_policy_version <> 'provider-eligibility-v1'
     or v_expires_at is null
     or v_expires_at <= pg_catalog.statement_timestamp()
     or v_current_decision_id is null
     or v_reviewer_id is null
     or v_reason_code is null then
    raise exception 'Provider marketplace capability is unavailable'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.is_provider_marketplace_eligible(pg_catalog.uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.require_provider_marketplace_eligibility(pg_catalog.uuid)
  from public, anon, authenticated, service_role;

create or replace function public.is_approved_provider(
  p_user_id pg_catalog.uuid default auth.uid()
)
returns pg_catalog.bool
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.is_provider_marketplace_eligible(p_user_id)
$$;

revoke all on function public.is_approved_provider(pg_catalog.uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.is_approved_provider(pg_catalog.uuid)
  to authenticated, service_role;

create or replace function private.protect_provider_service_eligibility()
returns pg_catalog.trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_provider_id pg_catalog.uuid;
begin
  if tg_op = 'INSERT'
     and new.active = false
     and new.description is null
     and new.base_price_minor is null then
    return new;
  end if;

  v_provider_id := case when tg_op = 'DELETE' then old.provider_id else new.provider_id end;
  perform private.require_provider_marketplace_eligibility(v_provider_id);

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create trigger protect_provider_service_eligibility
before insert or update or delete on public.provider_services
for each row execute function private.protect_provider_service_eligibility();

revoke all on function private.protect_provider_service_eligibility()
  from public, anon, authenticated, service_role;

create or replace function public.admin_transition_provider_marketplace_review(
  p_provider_id pg_catalog.uuid,
  p_action pg_catalog.text,
  p_expected_status pg_catalog.text,
  p_idempotency_key pg_catalog.uuid
)
returns pg_catalog.text
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_reviewer_id pg_catalog.uuid := auth.uid();
  v_reviewer_role public.user_role;
  v_reviewer_account_status pg_catalog.text;
  v_target_role public.user_role;
  v_target_account_status pg_catalog.text;
  v_provider_review_status pg_catalog.text;
  v_status pg_catalog.text;
  v_effective_status pg_catalog.text;
  v_basis pg_catalog.text;
  v_policy_version pg_catalog.text;
  v_expires_at pg_catalog.timestamptz;
  v_current_decision_id pg_catalog.uuid;
  v_new_status pg_catalog.text;
  v_new_basis pg_catalog.text;
  v_new_expires_at pg_catalog.timestamptz;
  v_reason_code pg_catalog.text;
  v_audit_action pg_catalog.text;
  v_intent_fingerprint pg_catalog.text;
  v_decision_id pg_catalog.uuid;
  v_decided_at pg_catalog.timestamptz := pg_catalog.transaction_timestamp();
  v_replay record;
  v_claims pg_catalog.jsonb;
begin
  if v_reviewer_id is null
     or p_provider_id is null
     or p_action is null
     or p_expected_status is null
     or p_idempotency_key is null
     or v_reviewer_id = p_provider_id then
    raise exception 'Provider marketplace review is unavailable'
      using errcode = '42501';
  end if;

  begin
    v_claims := case
      when pg_catalog.current_setting('request.jwt.claims', true) = '' then null
      else pg_catalog.current_setting('request.jwt.claims', true)::pg_catalog.jsonb
    end;
  exception
    when others then
      v_claims := null;
  end;

  if case
       when v_claims ->> 'aal' is null then ''
       else v_claims ->> 'aal'
     end <> 'aal2' then
    raise exception 'Provider marketplace review is unavailable'
      using errcode = '42501';
  end if;

  if p_action not in (
       'approve_manual_pilot',
       'approve_verified_identity',
       'reject',
       'suspend',
       'reinstate_manual_pilot',
       'reopen',
       'renew_manual_pilot',
       'expire'
     )
     or p_expected_status not in (
       'pending', 'approved', 'rejected', 'suspended', 'expired'
     ) then
    raise exception 'Provider marketplace review is unavailable'
      using errcode = '22023';
  end if;

  -- Lock order is reviewer profile, target profile, provider profile, then
  -- current eligibility. Capability mutations use the same target/profile/
  -- eligibility order through the requirement helper.
  select p.role, p.account_status
    into v_reviewer_role, v_reviewer_account_status
  from public.profiles as p
  where p.id = v_reviewer_id
  for update;

  if not found
     or v_reviewer_role <> 'admin'::public.user_role
     or v_reviewer_account_status <> 'active' then
    raise exception 'Provider marketplace review is unavailable'
      using errcode = '42501';
  end if;

  select p.role, p.account_status
    into v_target_role, v_target_account_status
  from public.profiles as p
  where p.id = p_provider_id
  for update;

  if not found or v_target_role <> 'provider'::public.user_role then
    raise exception 'Provider marketplace review is unavailable'
      using errcode = '42501';
  end if;

  select pp.review_status
    into v_provider_review_status
  from public.provider_profiles as pp
  where pp.user_id = p_provider_id
  for update;

  if not found then
    raise exception 'Provider marketplace review is unavailable'
      using errcode = '42501';
  end if;

  select
    eligibility.status,
    eligibility.basis,
    eligibility.policy_version,
    eligibility.expires_at,
    eligibility.current_decision_id
    into
      v_status,
      v_basis,
      v_policy_version,
      v_expires_at,
      v_current_decision_id
  from private.provider_marketplace_eligibility as eligibility
  where eligibility.provider_id = p_provider_id
  for update;

  if not found or v_policy_version <> 'provider-eligibility-v1' then
    raise exception 'Provider marketplace review is unavailable'
      using errcode = '42501';
  end if;

  v_effective_status := case
    when v_status = 'approved'
     and (v_expires_at is null or v_expires_at <= v_decided_at)
      then 'expired'
    else v_status
  end;

  v_intent_fingerprint := pg_catalog.md5(
    p_provider_id::pg_catalog.text || '|' ||
    p_action || '|' ||
    p_expected_status || '|provider-eligibility-v1'
  );

  select
    decision.provider_id,
    decision.action,
    decision.previous_status,
    decision.new_status,
    decision.intent_fingerprint
    into v_replay
  from private.provider_eligibility_decisions as decision
  where decision.reviewer_id = v_reviewer_id
    and decision.idempotency_key = p_idempotency_key;

  if found then
    if v_replay.provider_id = p_provider_id
       and v_replay.action = p_action
       and v_replay.previous_status = p_expected_status
       and v_replay.intent_fingerprint = v_intent_fingerprint then
      return v_replay.new_status;
    end if;

    raise exception 'Provider marketplace review is unavailable'
      using errcode = '23505';
  end if;

  if v_effective_status <> p_expected_status then
    raise exception 'Provider marketplace review is unavailable'
      using errcode = '40001';
  end if;

  if not exists (
       select 1
       from public.consents as consent
       where consent.user_id = p_provider_id
         and consent.purpose = 'provider_application_terms'
         and consent.policy_version = 'provider-application-v1'
         and consent.granted = true
         and consent.source = 'customer_provider_application_rpc'
         and consent.withdrawn_at is null
     )
     or not exists (
       select 1
       from public.audit_events as audit
       where audit.actor_id = p_provider_id
         and audit.action = 'customer.provider_application_submitted'
         and audit.object_type = 'provider_profile'
         and audit.object_id = p_provider_id::pg_catalog.text
     )
     or not exists (
       select 1
       from public.provider_services as service
       join public.service_categories as category
         on category.id = service.category_id
       where service.provider_id = p_provider_id
         and category.active = true
     ) then
    raise exception 'Provider marketplace review is unavailable'
      using errcode = '42501';
  end if;

  if p_action in (
       'approve_manual_pilot',
       'reinstate_manual_pilot',
       'renew_manual_pilot'
     )
     and v_target_account_status <> 'active' then
    raise exception 'Provider marketplace review is unavailable'
      using errcode = '42501';
  end if;

  case p_action
    when 'approve_manual_pilot' then
      if v_effective_status <> 'pending' then
        raise exception 'Provider marketplace review is unavailable'
          using errcode = '42501';
      end if;
      v_new_status := 'approved';
      v_new_basis := 'manual_pilot';
      v_new_expires_at := v_decided_at + pg_catalog.make_interval(days => 30);
      v_reason_code := 'manual_pilot_approved';
      v_audit_action := 'admin.provider_marketplace_approved';
    when 'approve_verified_identity' then
      -- No authoritative identity adapter/evidence boundary exists yet.
      raise exception 'Provider marketplace review is unavailable'
        using errcode = '42501';
    when 'reject' then
      if v_effective_status <> 'pending' then
        raise exception 'Provider marketplace review is unavailable'
          using errcode = '42501';
      end if;
      v_new_status := 'rejected';
      v_new_basis := null;
      v_new_expires_at := null;
      v_reason_code := 'marketplace_review_rejected';
      v_audit_action := 'admin.provider_marketplace_rejected';
    when 'suspend' then
      if v_effective_status <> 'approved' then
        raise exception 'Provider marketplace review is unavailable'
          using errcode = '42501';
      end if;
      v_new_status := 'suspended';
      v_new_basis := v_basis;
      v_new_expires_at := v_expires_at;
      v_reason_code := 'marketplace_eligibility_suspended';
      v_audit_action := 'admin.provider_marketplace_suspended';
    when 'reinstate_manual_pilot' then
      if v_effective_status <> 'suspended' then
        raise exception 'Provider marketplace review is unavailable'
          using errcode = '42501';
      end if;
      v_new_status := 'approved';
      v_new_basis := 'manual_pilot';
      v_new_expires_at := v_decided_at + pg_catalog.make_interval(days => 30);
      v_reason_code := 'manual_pilot_reinstated';
      v_audit_action := 'admin.provider_marketplace_reinstated';
    when 'reopen' then
      if v_effective_status <> 'rejected' then
        raise exception 'Provider marketplace review is unavailable'
          using errcode = '42501';
      end if;
      v_new_status := 'pending';
      v_new_basis := null;
      v_new_expires_at := null;
      v_reason_code := 'marketplace_review_reopened';
      v_audit_action := 'admin.provider_marketplace_reopened';
    when 'renew_manual_pilot' then
      if v_effective_status <> 'expired' then
        raise exception 'Provider marketplace review is unavailable'
          using errcode = '42501';
      end if;
      v_new_status := 'approved';
      v_new_basis := 'manual_pilot';
      v_new_expires_at := v_decided_at + pg_catalog.make_interval(days => 30);
      v_reason_code := 'manual_pilot_renewed';
      v_audit_action := 'admin.provider_marketplace_renewed';
    when 'expire' then
      if v_effective_status <> 'approved' then
        raise exception 'Provider marketplace review is unavailable'
          using errcode = '42501';
      end if;
      v_new_status := 'expired';
      v_new_basis := v_basis;
      v_new_expires_at := v_expires_at;
      v_reason_code := 'marketplace_eligibility_expired';
      v_audit_action := 'admin.provider_marketplace_expired';
  end case;

  v_decision_id := pg_catalog.gen_random_uuid();

  insert into private.provider_eligibility_decisions (
    id,
    provider_id,
    reviewer_id,
    action,
    previous_status,
    new_status,
    basis,
    policy_version,
    expires_at,
    reason_code,
    idempotency_key,
    intent_fingerprint,
    decided_at
  ) values (
    v_decision_id,
    p_provider_id,
    v_reviewer_id,
    p_action,
    v_effective_status,
    v_new_status,
    v_new_basis,
    'provider-eligibility-v1',
    v_new_expires_at,
    v_reason_code,
    p_idempotency_key,
    v_intent_fingerprint,
    v_decided_at
  );

  update private.provider_marketplace_eligibility as eligibility
  set status = v_new_status,
      basis = v_new_basis,
      policy_version = 'provider-eligibility-v1',
      expires_at = v_new_expires_at,
      current_decision_id = v_decision_id,
      reviewer_id = v_reviewer_id,
      reason_code = v_reason_code,
      updated_at = v_decided_at
  where eligibility.provider_id = p_provider_id;

  perform pg_catalog.set_config(
    'lekkadeall.allow_privileged_provider_profile_update',
    'on',
    true
  );

  begin
    update public.provider_profiles as pp
    set review_status = v_new_status,
        reviewed_by = v_reviewer_id,
        reviewed_at = v_decided_at,
        updated_at = v_decided_at
    where pp.user_id = p_provider_id;

    perform pg_catalog.set_config(
      'lekkadeall.allow_privileged_provider_profile_update',
      'off',
      true
    );
  exception
    when others then
      perform pg_catalog.set_config(
        'lekkadeall.allow_privileged_provider_profile_update',
        'off',
        true
      );
      raise;
  end;

  perform private.append_audit_event(
    v_reviewer_id,
    v_audit_action,
    'provider_eligibility_decision',
    v_decision_id::pg_catalog.text,
    v_reason_code,
    pg_catalog.jsonb_build_object(
      'provider_id', p_provider_id,
      'previous_status', v_effective_status,
      'new_status', v_new_status,
      'basis', v_new_basis,
      'policy_version', 'provider-eligibility-v1',
      'expires_at', v_new_expires_at,
      'decision_id', v_decision_id
    )
  );

  return v_new_status;
end;
$$;

comment on function public.admin_transition_provider_marketplace_review(
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.uuid
) is
  'Ticket 10B AAL2 active-admin boundary for fixed, audited marketplace eligibility transitions. Manual-pilot approval never changes identity-verification state.';

revoke all on function public.admin_transition_provider_marketplace_review(
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.uuid
) from public, anon, authenticated, service_role;

grant execute on function public.admin_transition_provider_marketplace_review(
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.uuid
) to authenticated;

-- Remove the legacy alternate authorities. Identity transitions require a
-- separately reviewed real adapter/operator boundary and are not implemented
-- by Ticket 10B.
revoke all on function public.admin_set_provider_review_status(
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text
) from public, anon, authenticated, service_role;

revoke all on function public.admin_set_provider_verification_status(
  pg_catalog.uuid,
  public.verification_status,
  pg_catalog.text,
  pg_catalog.bool,
  pg_catalog.text
) from public, anon, authenticated, service_role;

-- Raw identity-adapter rows contain vendor references and failure detail.
-- No browser role receives them while no real reviewed adapter exists.
revoke select on public.identity_verifications from public, anon, authenticated;

-- Keep the existing coarse review field aligned with the protected state.
alter table public.provider_profiles
  drop constraint if exists provider_profiles_review_status_check;
alter table public.provider_profiles
  add constraint provider_profiles_review_status_check
  check (review_status in ('pending', 'approved', 'rejected', 'suspended', 'expired'));

-- These transaction-time guards close approve/suspend/action races. Direct
-- fixture maintenance by the database owner with no authenticated actor is
-- outside the browser/server capability boundary and remains possible.
create or replace function private.require_bid_insert_provider_eligibility()
returns pg_catalog.trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if session_user = 'postgres' and auth.uid() is null then
    return new;
  end if;

  perform private.require_provider_marketplace_eligibility(new.provider_id);
  return new;
end;
$$;

create trigger require_bid_insert_provider_eligibility
before insert on public.bids
for each row execute function private.require_bid_insert_provider_eligibility();

revoke all on function private.require_bid_insert_provider_eligibility()
  from public, anon, authenticated, service_role;

create or replace function private.require_booking_provider_eligibility()
returns pg_catalog.trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id pg_catalog.uuid := auth.uid();
begin
  if session_user = 'postgres' and v_actor_id is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    perform private.require_provider_marketplace_eligibility(new.provider_id);
  elsif v_actor_id = new.provider_id
        and (
          new.status is distinct from old.status
          or new.provider_completed_at is distinct from old.provider_completed_at
        ) then
    perform private.require_provider_marketplace_eligibility(new.provider_id);
  end if;

  return new;
end;
$$;

create trigger require_booking_provider_eligibility
before insert or update on public.bookings
for each row execute function private.require_booking_provider_eligibility();

revoke all on function private.require_booking_provider_eligibility()
  from public, anon, authenticated, service_role;

create or replace function public.reveal_confirmed_booking_address(
  p_booking_id pg_catalog.uuid
)
returns table (
  precise_address_ciphertext pg_catalog.text
)
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id pg_catalog.uuid := auth.uid();
  v_booking_id pg_catalog.uuid;
  v_request_id pg_catalog.uuid;
  v_customer_id pg_catalog.uuid;
  v_provider_id pg_catalog.uuid;
  v_booking_status public.booking_status;
  v_precise_address_ciphertext pg_catalog.text;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to reveal a booking address'
      using errcode = '42501';
  end if;

  perform private.require_provider_marketplace_eligibility(v_actor_id);

  select
    booking.id,
    booking.request_id,
    booking.customer_id,
    booking.provider_id,
    booking.status
    into
      v_booking_id,
      v_request_id,
      v_customer_id,
      v_provider_id,
      v_booking_status
  from public.bookings as booking
  where booking.id = p_booking_id;

  if not found or v_provider_id <> v_actor_id then
    raise exception 'Booking not found for selected provider'
      using errcode = '42501';
  end if;

  if not public.is_address_revealable_booking_status(v_booking_status) then
    raise exception 'Booking is not confirmed for address reveal'
      using errcode = '42501';
  end if;

  select address.precise_address_ciphertext
    into v_precise_address_ciphertext
  from private.service_request_addresses as address
  where address.request_id = v_request_id
    and address.customer_id = v_customer_id;

  if v_precise_address_ciphertext is null then
    raise exception 'Precise address is unavailable for this booking'
      using errcode = '02000';
  end if;

  perform private.append_audit_event(
    v_actor_id,
    'booking.address_revealed',
    'booking',
    p_booking_id::pg_catalog.text,
    'Selected provider revealed confirmed booking address',
    pg_catalog.jsonb_build_object(
      'booking_id', p_booking_id,
      'request_id', v_request_id,
      'provider_id', v_actor_id,
      'booking_status', v_booking_status
    )
  );

  return query select v_precise_address_ciphertext;
end;
$$;

revoke all on function public.reveal_confirmed_booking_address(pg_catalog.uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.reveal_confirmed_booking_address(pg_catalog.uuid)
  to authenticated, service_role;

create or replace function private.payout_release_blockers(
  p_payment_id pg_catalog.uuid,
  p_ignore_release_paused pg_catalog.bool default false
)
returns pg_catalog.text[]
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_booking_id pg_catalog.uuid;
  v_payment_status pg_catalog.text;
  v_payment_method pg_catalog.text;
  v_release_status pg_catalog.text;
  v_release_paused pg_catalog.bool;
  v_refunded_minor pg_catalog.int4;
  v_amount_minor pg_catalog.int4;
  v_booking_status public.booking_status;
  v_provider_id pg_catalog.uuid;
  v_blockers pg_catalog.text[] := '{}'::pg_catalog.text[];
begin
  select
    payment.booking_id,
    payment.status,
    payment.payment_method,
    payment.release_status,
    payment.release_paused,
    payment.refunded_minor,
    payment.amount_minor
    into
      v_booking_id,
      v_payment_status,
      v_payment_method,
      v_release_status,
      v_release_paused,
      v_refunded_minor,
      v_amount_minor
  from public.payments as payment
  where payment.id = p_payment_id;

  if not found then
    return pg_catalog.array_append(v_blockers, 'payment_not_found');
  end if;

  select booking.status, booking.provider_id
    into v_booking_status, v_provider_id
  from public.bookings as booking
  where booking.id = v_booking_id;

  if not found then
    v_blockers := pg_catalog.array_append(v_blockers, 'booking_not_found');
  else
    if v_booking_status <> 'completed'::public.booking_status then
      v_blockers := pg_catalog.array_append(v_blockers, 'booking_not_completed');
    end if;

    if not private.is_provider_marketplace_eligible(v_provider_id) then
      v_blockers := pg_catalog.array_append(v_blockers, 'provider_not_eligible');
    end if;
  end if;

  if v_payment_status not in ('paid', 'partially_refunded') then
    v_blockers := pg_catalog.array_append(v_blockers, 'payment_not_paid');
  end if;

  if v_payment_method not in (
    'platform_online_pending',
    'platform_online',
    'sandbox_online',
    'manual_sandbox_online'
  ) then
    v_blockers := pg_catalog.array_append(v_blockers, 'payment_method_not_releasable');
  end if;

  if v_release_status in ('released', 'cancelled') then
    v_blockers := pg_catalog.array_append(v_blockers, 'release_terminal');
  end if;

  if not p_ignore_release_paused and v_release_paused then
    v_blockers := pg_catalog.array_append(v_blockers, 'release_paused');
  end if;

  if v_refunded_minor >= v_amount_minor then
    v_blockers := pg_catalog.array_append(v_blockers, 'fully_refunded');
  end if;

  if (v_amount_minor - v_refunded_minor) <= 0 then
    v_blockers := pg_catalog.array_append(v_blockers, 'no_releasable_amount');
  end if;

  if exists (
    select 1
    from public.refund_requests as request
    where request.payment_id = p_payment_id
      and request.status in ('requested', 'under_review', 'approved', 'processing')
  ) then
    v_blockers := pg_catalog.array_append(v_blockers, 'active_refund');
  end if;

  if exists (
    select 1
    from public.disputes as dispute
    where dispute.booking_id = v_booking_id
      and dispute.status in (
        'open',
        'awaiting_customer',
        'awaiting_provider',
        'under_review',
        'appealed'
      )
  ) then
    v_blockers := pg_catalog.array_append(v_blockers, 'active_dispute');
  end if;

  return v_blockers;
end;
$$;

revoke all on function private.payout_release_blockers(
  pg_catalog.uuid,
  pg_catalog.bool
) from public, anon, authenticated, service_role;
