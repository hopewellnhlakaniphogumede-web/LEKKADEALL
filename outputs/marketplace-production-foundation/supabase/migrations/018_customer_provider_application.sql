-- Ticket 10A: trusted closed-pilot provider application boundary.
-- Normal Auth registration remains customer-first. Only this actor-derived,
-- audited RPC may convert an eligible pristine customer into a pending,
-- unverified provider applicant with inactive category proposals.

-- Application and approval fields must not remain directly browser-editable,
-- and approved-provider discovery must not expose verification references,
-- bank-match state, or reviewer metadata.
revoke update (business_name, bio, service_radius_km)
  on public.provider_profiles from anon, authenticated;

revoke select on public.provider_profiles from anon, authenticated;
grant select (
  user_id,
  business_name,
  bio,
  service_radius_km,
  verification_status,
  review_status,
  created_at,
  updated_at
) on public.provider_profiles to authenticated;

-- The general consent table previously allowed owner-controlled mutation.
-- Ticket 10A reserves one fixed provider-terms shape, prevents browser DML,
-- makes the record immutable, and enforces one accepted version per actor.
revoke insert, update, delete on public.consents from anon, authenticated;

alter table public.consents
  drop constraint if exists provider_application_terms_shape;

alter table public.consents
  add constraint provider_application_terms_shape
  check (
    purpose <> 'provider_application_terms'
    or (
      policy_version = 'provider-application-v1'
      and granted = true
      and source = 'customer_provider_application_rpc'
      and withdrawn_at is null
    )
  );

drop index if exists public.provider_application_terms_one_per_user_uidx;
create unique index provider_application_terms_one_per_user_uidx
on public.consents(user_id)
where purpose = 'provider_application_terms';

create or replace function private.prevent_provider_application_terms_mutation()
returns pg_catalog.trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if old.purpose = 'provider_application_terms'
     or (
       tg_op = 'UPDATE'
       and new.purpose = 'provider_application_terms'
     ) then
    raise exception 'Provider application terms are append-only'
      using errcode = '42501';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

drop trigger if exists protect_provider_application_terms
  on public.consents;
create trigger protect_provider_application_terms
before update or delete on public.consents
for each row execute function private.prevent_provider_application_terms_mutation();

revoke all on function private.prevent_provider_application_terms_mutation()
  from public, anon, authenticated, service_role;

create or replace function public.customer_submit_provider_application(
  p_business_name pg_catalog.text,
  p_service_radius_km pg_catalog.numeric,
  p_category_ids pg_catalog.uuid[],
  p_terms_version pg_catalog.text
)
returns pg_catalog.text
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id pg_catalog.uuid := auth.uid();
  v_actor_role public.user_role;
  v_account_status pg_catalog.text;
  v_business_name pg_catalog.text;
  v_category_id pg_catalog.uuid;
  v_category_count pg_catalog.int4;
  v_active_category_count pg_catalog.int4 := 0;
  v_changed_rows pg_catalog.int4;
  v_changed_at pg_catalog.timestamptz;
  v_existing_business_name pg_catalog.text;
  v_existing_service_radius_km pg_catalog.numeric;
  v_existing_verification_status public.verification_status;
  v_existing_verification_reference pg_catalog.text;
  v_existing_bank_name_match pg_catalog.boolean;
  v_existing_review_status pg_catalog.text;
  v_existing_reviewed_by pg_catalog.uuid;
  v_existing_reviewed_at pg_catalog.timestamptz;
begin
  perform pg_catalog.set_config(
    'lekkadeall.allow_privileged_profile_update',
    'off',
    true
  );

  if v_actor_id is null then
    raise exception 'Authentication is required to submit a provider application'
      using errcode = '42501';
  end if;

  v_business_name := private.canonicalize_service_request_public_field(
    'title',
    p_business_name
  );

  if private.service_request_public_field_violation(
       'title',
       v_business_name
     ) is not null
     or p_service_radius_km is null
     or p_service_radius_km < 1
     or p_service_radius_km > 250
     or p_terms_version is distinct from 'provider-application-v1'
     or p_category_ids is null
     or pg_catalog.cardinality(p_category_ids) < 1
     or pg_catalog.cardinality(p_category_ids) > 10
     or pg_catalog.array_position(p_category_ids, null) is not null then
    raise exception 'Provider application is invalid'
      using errcode = '22023';
  end if;

  select
    pg_catalog.count(requested.category_id)::pg_catalog.int4,
    pg_catalog.count(distinct requested.category_id)::pg_catalog.int4
    into v_category_count, v_changed_rows
  from pg_catalog.unnest(p_category_ids) as requested(category_id);

  if v_category_count <> v_changed_rows then
    raise exception 'Provider application is invalid'
      using errcode = '22023';
  end if;

  select p.role, p.account_status
    into v_actor_role, v_account_status
  from public.profiles as p
  where p.id = v_actor_id
  for update;

  if not found then
    raise exception 'Provider application is unavailable'
      using errcode = '42501';
  end if;

  -- An identical replay of a completed pending application is a no-op. It
  -- cannot modify the original application or create another audit event.
  if v_actor_role = 'provider'::public.user_role
     and v_account_status = 'active' then
    select
      pp.business_name,
      pp.service_radius_km,
      pp.verification_status,
      pp.verification_reference,
      pp.bank_name_match,
      pp.review_status,
      pp.reviewed_by,
      pp.reviewed_at
      into
        v_existing_business_name,
        v_existing_service_radius_km,
        v_existing_verification_status,
        v_existing_verification_reference,
        v_existing_bank_name_match,
        v_existing_review_status,
        v_existing_reviewed_by,
        v_existing_reviewed_at
    from public.provider_profiles as pp
    where pp.user_id = v_actor_id
    for update;

    if found
       and v_existing_business_name = v_business_name
       and v_existing_service_radius_km = p_service_radius_km
       and v_existing_verification_status = 'not_started'::public.verification_status
       and v_existing_verification_reference is null
       and v_existing_bank_name_match is null
       and v_existing_review_status = 'pending'
       and v_existing_reviewed_by is null
       and v_existing_reviewed_at is null
       and (
         select pg_catalog.count(*)
         from public.provider_services as ps
         where ps.provider_id = v_actor_id
           and ps.active = false
           and ps.description is null
           and ps.base_price_minor is null
       ) = v_category_count
       and not exists (
         select 1
         from pg_catalog.unnest(p_category_ids) as requested(category_id)
         where not exists (
           select 1
           from public.provider_services as ps
           where ps.provider_id = v_actor_id
             and ps.category_id = requested.category_id
             and ps.active = false
             and ps.description is null
             and ps.base_price_minor is null
         )
       )
       and exists (
         select 1
         from public.consents as c
         where c.user_id = v_actor_id
           and c.purpose = 'provider_application_terms'
           and c.policy_version = 'provider-application-v1'
           and c.granted = true
           and c.source = 'customer_provider_application_rpc'
           and c.withdrawn_at is null
       )
       and exists (
         select 1
         from public.audit_events as ae
         where ae.actor_id = v_actor_id
           and ae.action = 'customer.provider_application_submitted'
           and ae.object_type = 'provider_profile'
           and ae.object_id = v_actor_id::pg_catalog.text
           and ae.reason = 'Customer submitted closed-pilot provider application'
           and ae.metadata = pg_catalog.jsonb_build_object(
             'source', 'customer_provider_application_rpc',
             'version', '1',
             'terms_version', 'provider-application-v1'
           )
       ) then
      return 'pending'::pg_catalog.text;
    end if;

    raise exception 'Provider application is unavailable'
      using errcode = '42501';
  end if;

  if v_actor_role <> 'customer'::public.user_role
     or v_account_status <> 'active'
     or exists (
       select 1
       from public.provider_profiles as pp
       where pp.user_id = v_actor_id
     )
     or exists (
       select 1
       from public.provider_services as ps
       where ps.provider_id = v_actor_id
     )
     or exists (
       select 1
       from public.service_requests as sr
       where sr.customer_id = v_actor_id
     )
     or exists (
       select 1
       from public.bids as b
       where b.provider_id = v_actor_id
     )
     or exists (
       select 1
       from public.bookings as b
       where b.customer_id = v_actor_id
          or b.provider_id = v_actor_id
     )
     or exists (
       select 1
       from public.identity_verifications as iv
       where iv.user_id = v_actor_id
     )
     or exists (
       select 1
       from public.payment_events as pe
       where pe.actor_id = v_actor_id
     )
     or exists (
       select 1
       from public.refund_requests as rr
       where rr.requested_by = v_actor_id
          or rr.admin_decision_by = v_actor_id
     )
     or exists (
       select 1
       from public.refund_events as re
       where re.actor_id = v_actor_id
     )
     or exists (
       select 1
       from public.disputes as d
       where d.opened_by = v_actor_id
     )
     or exists (
       select 1
       from public.dispute_evidence as de
       where de.uploaded_by = v_actor_id
     )
     or exists (
       select 1
       from public.reviews as r
       where r.reviewer_id = v_actor_id
          or r.subject_id = v_actor_id
     ) then
    raise exception 'Provider application is unavailable'
      using errcode = '42501';
  end if;

  for v_category_id in
    select sc.id
    from public.service_categories as sc
    join pg_catalog.unnest(p_category_ids) as requested(category_id)
      on requested.category_id = sc.id
    where sc.active = true
    order by sc.id
    for share of sc
  loop
    v_active_category_count := v_active_category_count + 1;
  end loop;

  if v_active_category_count <> v_category_count then
    raise exception 'Provider application is invalid'
      using errcode = '22023';
  end if;

  v_changed_at := pg_catalog.transaction_timestamp();

  perform pg_catalog.set_config(
    'lekkadeall.allow_privileged_profile_update',
    'on',
    true
  );

  begin
    update public.profiles as p
    set role = 'provider'::public.user_role,
        updated_at = v_changed_at
    where p.id = v_actor_id
      and p.role = 'customer'::public.user_role
      and p.account_status = 'active';

    get diagnostics v_changed_rows = row_count;
    if v_changed_rows <> 1 then
      raise exception 'Provider application is unavailable'
        using errcode = '42501';
    end if;

    perform pg_catalog.set_config(
      'lekkadeall.allow_privileged_profile_update',
      'off',
      true
    );
  exception
    when others then
      perform pg_catalog.set_config(
        'lekkadeall.allow_privileged_profile_update',
        'off',
        true
      );
      raise;
  end;

  insert into public.provider_profiles (
    user_id,
    business_name,
    bio,
    service_radius_km,
    verification_status,
    verification_reference,
    bank_name_match,
    review_status,
    reviewed_by,
    reviewed_at,
    created_at,
    updated_at
  ) values (
    v_actor_id,
    v_business_name,
    null,
    p_service_radius_km,
    'not_started'::public.verification_status,
    null,
    null,
    'pending',
    null,
    null,
    v_changed_at,
    v_changed_at
  );

  insert into public.provider_services (
    provider_id,
    category_id,
    description,
    base_price_minor,
    active
  )
  select
    v_actor_id,
    requested.category_id,
    null,
    null,
    false
  from pg_catalog.unnest(p_category_ids) as requested(category_id);

  insert into public.consents (
    user_id,
    purpose,
    policy_version,
    granted,
    source,
    recorded_at,
    withdrawn_at
  ) values (
    v_actor_id,
    'provider_application_terms',
    'provider-application-v1',
    true,
    'customer_provider_application_rpc',
    v_changed_at,
    null
  );

  perform private.append_audit_event(
    v_actor_id,
    'customer.provider_application_submitted',
    'provider_profile',
    v_actor_id::pg_catalog.text,
    'Customer submitted closed-pilot provider application',
    pg_catalog.jsonb_build_object(
      'source', 'customer_provider_application_rpc',
      'version', '1',
      'terms_version', 'provider-application-v1'
    )
  );

  perform pg_catalog.set_config(
    'lekkadeall.allow_privileged_profile_update',
    'off',
    true
  );

  return 'pending'::pg_catalog.text;
end;
$$;

comment on function public.customer_submit_provider_application(
  pg_catalog.text,
  pg_catalog.numeric,
  pg_catalog.uuid[],
  pg_catalog.text
) is
  'Ticket 10A authenticated closed-pilot boundary: converts one active pristine customer into a pending, unverified provider applicant and atomically records inactive category proposals, one immutable terms record, and one fixed audit event.';

revoke all on function public.customer_submit_provider_application(
  pg_catalog.text,
  pg_catalog.numeric,
  pg_catalog.uuid[],
  pg_catalog.text
) from public, anon, authenticated, service_role;

grant execute on function public.customer_submit_provider_application(
  pg_catalog.text,
  pg_catalog.numeric,
  pg_catalog.uuid[],
  pg_catalog.text
) to authenticated;
