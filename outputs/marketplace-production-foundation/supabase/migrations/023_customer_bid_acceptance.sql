-- Ticket 10F: customer-owned bid selection without booking, payment, contact,
-- or exact-address authority. The legacy acceptance path remains unavailable.

create table private.customer_bid_acceptance_receipts (
  request_id pg_catalog.uuid primary key
    references public.service_requests(id) on delete restrict,
  customer_id pg_catalog.uuid not null
    references public.profiles(id) on delete restrict,
  bid_id pg_catalog.uuid not null unique
    references public.bids(id) on delete restrict,
  idempotency_key pg_catalog.uuid not null,
  contract_version pg_catalog.text not null
    check (contract_version = 'customer-bid-acceptance-v1'),
  expected_request_updated_at pg_catalog.timestamptz not null,
  expected_bid_submitted_at pg_catalog.timestamptz not null,
  intent_fingerprint pg_catalog.text not null
    check (intent_fingerprint ~ '^[0-9a-f]{32}$'),
  accepted_at pg_catalog.timestamptz not null,
  awarded_at pg_catalog.timestamptz not null,
  created_at pg_catalog.timestamptz not null
    default pg_catalog.transaction_timestamp(),
  unique (customer_id, idempotency_key),
  check (idempotency_key <> '00000000-0000-0000-0000-000000000000'::pg_catalog.uuid),
  check (accepted_at = awarded_at)
);

alter table private.customer_bid_acceptance_receipts enable row level security;

revoke all on private.customer_bid_acceptance_receipts
  from public, anon, authenticated, service_role;

create function private.prevent_customer_bid_acceptance_receipt_mutation()
returns pg_catalog.trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'Customer bid acceptance receipts are append-only'
    using errcode = '42501';
end;
$$;

create trigger customer_bid_acceptance_receipts_append_only
before update or delete on private.customer_bid_acceptance_receipts
for each row execute function private.prevent_customer_bid_acceptance_receipt_mutation();

revoke all on function private.prevent_customer_bid_acceptance_receipt_mutation()
  from public, anon, authenticated, service_role;

create function public.customer_accept_current_bid(
  p_request_id pg_catalog.uuid,
  p_bid_id pg_catalog.uuid,
  p_expected_request_updated_at pg_catalog.timestamptz,
  p_expected_bid_submitted_at pg_catalog.timestamptz,
  p_idempotency_key pg_catalog.uuid
)
returns table (
  request_id pg_catalog.uuid,
  accepted_bid_id pg_catalog.uuid,
  request_status public.request_status,
  bid_status public.bid_status,
  awarded_at pg_catalog.timestamptz,
  accepted_at pg_catalog.timestamptz
)
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id pg_catalog.uuid;
  v_request_customer_id pg_catalog.uuid;
  v_category_id pg_catalog.uuid;
  v_request_title pg_catalog.text;
  v_request_description pg_catalog.text;
  v_request_suburb pg_catalog.text;
  v_request_city pg_catalog.text;
  v_requested_start pg_catalog.timestamptz;
  v_request_status public.request_status;
  v_closes_at pg_catalog.timestamptz;
  v_published_at pg_catalog.timestamptz;
  v_request_updated_at pg_catalog.timestamptz;
  v_request_awarded_at pg_catalog.timestamptz;
  v_request_cancelled_at pg_catalog.timestamptz;
  v_bid_request_id pg_catalog.uuid;
  v_provider_id pg_catalog.uuid;
  v_amount_minor pg_catalog.int4;
  v_currency pg_catalog.bpchar;
  v_proposed_start pg_catalog.timestamptz;
  v_message pg_catalog.text;
  v_perks pg_catalog.text[];
  v_bid_status public.bid_status;
  v_expires_at pg_catalog.timestamptz;
  v_bid_created_at pg_catalog.timestamptz;
  v_bid_updated_at pg_catalog.timestamptz;
  v_bid_accepted_at pg_catalog.timestamptz;
  v_bid_declined_at pg_catalog.timestamptz;
  v_bid_withdrawn_at pg_catalog.timestamptz;
  v_category_active pg_catalog.bool;
  v_service_active pg_catalog.bool;
  v_decision_at pg_catalog.timestamptz;
  v_fingerprint pg_catalog.text;
  v_receipt_request_id pg_catalog.uuid;
  v_receipt_customer_id pg_catalog.uuid;
  v_receipt_bid_id pg_catalog.uuid;
  v_receipt_idempotency_key pg_catalog.uuid;
  v_receipt_fingerprint pg_catalog.text;
  v_receipt_accepted_at pg_catalog.timestamptz;
  v_receipt_awarded_at pg_catalog.timestamptz;
  v_transition_enabled pg_catalog.bool := false;
  v_affected_rows pg_catalog.int4;
  v_competing_bid_count pg_catalog.int4;
begin
  begin
    v_actor_id := auth.uid();

    if v_actor_id is null
       or p_request_id is null
       or p_request_id = '00000000-0000-0000-0000-000000000000'::pg_catalog.uuid
       or p_bid_id is null
       or p_bid_id = '00000000-0000-0000-0000-000000000000'::pg_catalog.uuid
       or p_expected_request_updated_at is null
       or p_expected_bid_submitted_at is null
       or p_idempotency_key is null
       or p_idempotency_key = '00000000-0000-0000-0000-000000000000'::pg_catalog.uuid then
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
    end if;

    v_fingerprint := pg_catalog.md5(
      pg_catalog.convert_to('customer-bid-acceptance-v1', 'UTF8')
      || pg_catalog.uuid_send(v_actor_id)
      || pg_catalog.uuid_send(p_request_id)
      || pg_catalog.uuid_send(p_bid_id)
      || pg_catalog.timestamptz_send(p_expected_request_updated_at)
      || pg_catalog.timestamptz_send(p_expected_bid_submitted_at)
    );

    perform profile.id
    from public.profiles as profile
    where profile.id = v_actor_id
      and profile.role = 'customer'::public.user_role
      and profile.account_status = 'active'
    for share;

    if not found then
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
    end if;

    select
      request.customer_id,
      request.category_id,
      request.title,
      request.description,
      request.suburb,
      request.city,
      request.requested_start,
      request.status,
      request.closes_at,
      request.published_at,
      request.updated_at,
      request.awarded_at,
      request.cancelled_at
      into
        v_request_customer_id,
        v_category_id,
        v_request_title,
        v_request_description,
        v_request_suburb,
        v_request_city,
        v_requested_start,
        v_request_status,
        v_closes_at,
        v_published_at,
        v_request_updated_at,
        v_request_awarded_at,
        v_request_cancelled_at
    from public.service_requests as request
    where request.id = p_request_id
      and request.customer_id = v_actor_id
    for update;

    if not found then
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
    end if;

    select
      bid.request_id,
      bid.provider_id,
      bid.amount_minor,
      bid.currency,
      bid.proposed_start,
      bid.message,
      bid.perks,
      bid.status,
      bid.expires_at,
      bid.created_at,
      bid.updated_at,
      bid.accepted_at,
      bid.declined_at,
      bid.withdrawn_at
      into
        v_bid_request_id,
        v_provider_id,
        v_amount_minor,
        v_currency,
        v_proposed_start,
        v_message,
        v_perks,
        v_bid_status,
        v_expires_at,
        v_bid_created_at,
        v_bid_updated_at,
        v_bid_accepted_at,
        v_bid_declined_at,
        v_bid_withdrawn_at
    from public.bids as bid
    where bid.id = p_bid_id
      and bid.request_id = p_request_id
    for update;

    if not found then
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
    end if;

    perform bid.id
    from public.bids as bid
    where bid.request_id = p_request_id
      and bid.id <> p_bid_id
      and bid.status = 'submitted'::public.bid_status
    order by bid.id asc
    for update;

    get diagnostics v_competing_bid_count = row_count;

    if v_request_status = 'awarded'::public.request_status
       or v_bid_status = 'accepted'::public.bid_status then
      select
        receipt.request_id,
        receipt.customer_id,
        receipt.bid_id,
        receipt.idempotency_key,
        receipt.intent_fingerprint,
        receipt.accepted_at,
        receipt.awarded_at
        into
          v_receipt_request_id,
          v_receipt_customer_id,
          v_receipt_bid_id,
          v_receipt_idempotency_key,
          v_receipt_fingerprint,
          v_receipt_accepted_at,
          v_receipt_awarded_at
      from private.customer_bid_acceptance_receipts as receipt
      where receipt.request_id = p_request_id
         or (
           receipt.customer_id = v_actor_id
           and receipt.idempotency_key = p_idempotency_key
         )
      order by receipt.request_id asc
      for update;

      if not found
         or v_receipt_request_id <> p_request_id
         or v_receipt_customer_id <> v_actor_id
         or v_receipt_bid_id <> p_bid_id
         or v_receipt_idempotency_key <> p_idempotency_key
         or v_receipt_fingerprint <> v_fingerprint
         or v_competing_bid_count <> 0
         or v_request_status <> 'awarded'::public.request_status
         or v_request_awarded_at is distinct from v_receipt_awarded_at
         or v_request_cancelled_at is not null
         or v_bid_status <> 'accepted'::public.bid_status
         or v_bid_accepted_at is distinct from v_receipt_accepted_at
         or v_bid_declined_at is not null
         or v_bid_withdrawn_at is not null then
        raise exception 'Customer bid acceptance is unavailable'
          using errcode = '42501';
      end if;

      return query select
        v_receipt_request_id,
        v_receipt_bid_id,
        'awarded'::public.request_status,
        'accepted'::public.bid_status,
        v_receipt_awarded_at,
        v_receipt_accepted_at;
      return;
    end if;

    perform provider_profile.id
    from public.profiles as provider_profile
    where provider_profile.id = v_provider_id
    for share;

    if not found then
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
    end if;

    perform provider.user_id
    from public.provider_profiles as provider
    where provider.user_id = v_provider_id
    for share;

    if not found then
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
    end if;

    perform eligibility.provider_id
    from private.provider_marketplace_eligibility as eligibility
    where eligibility.provider_id = v_provider_id
    for share;

    if not found then
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
    end if;

    select category.active
      into v_category_active
    from public.service_categories as category
    where category.id = v_category_id
    for share;

    if not found then
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
    end if;

    select service.active
      into v_service_active
    from public.provider_services as service
    where service.provider_id = v_provider_id
      and service.category_id = v_category_id
    for share;

    if not found then
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
    end if;

    select
      receipt.request_id,
      receipt.customer_id,
      receipt.bid_id,
      receipt.idempotency_key,
      receipt.intent_fingerprint,
      receipt.accepted_at,
      receipt.awarded_at
      into
        v_receipt_request_id,
        v_receipt_customer_id,
        v_receipt_bid_id,
        v_receipt_idempotency_key,
        v_receipt_fingerprint,
        v_receipt_accepted_at,
        v_receipt_awarded_at
    from private.customer_bid_acceptance_receipts as receipt
    where receipt.request_id = p_request_id
       or (
         receipt.customer_id = v_actor_id
         and receipt.idempotency_key = p_idempotency_key
       )
    order by receipt.request_id asc
    for update;

    if found then
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
    end if;

    v_decision_at := pg_catalog.clock_timestamp();

    if v_request_customer_id <> v_actor_id
       or v_request_status <> 'open'::public.request_status
       or v_published_at is null
       or v_published_at > v_decision_at
       or v_closes_at is null
       or v_closes_at <= v_decision_at
       or v_requested_start <= v_decision_at
       or v_closes_at >= v_requested_start
       or v_request_awarded_at is not null
       or v_request_cancelled_at is not null
       or v_request_updated_at is distinct from p_expected_request_updated_at
       or v_request_title is distinct from private.canonicalize_service_request_public_field(
         'title', v_request_title
       )
       or v_request_description is distinct from private.canonicalize_service_request_public_field(
         'description', v_request_description
       )
       or v_request_suburb is distinct from private.canonicalize_service_request_public_field(
         'suburb', v_request_suburb
       )
       or v_request_city is distinct from private.canonicalize_service_request_public_field(
         'city', v_request_city
       )
       or private.service_request_public_field_violation('title', v_request_title) is not null
       or private.service_request_public_field_violation(
         'description', v_request_description
       ) is not null
       or private.service_request_public_field_violation('suburb', v_request_suburb) is not null
       or private.service_request_public_field_violation('city', v_request_city) is not null
       or v_bid_request_id <> p_request_id
       or v_bid_status <> 'submitted'::public.bid_status
       or v_amount_minor < 1
       or v_amount_minor > 100000000
       or v_currency <> 'ZAR'::pg_catalog.bpchar
       or v_proposed_start is distinct from v_requested_start
       or v_expires_at is distinct from v_closes_at
       or v_expires_at <= v_decision_at
       or v_bid_created_at > v_decision_at
       or v_bid_updated_at is distinct from v_bid_created_at
       or v_bid_created_at is distinct from p_expected_bid_submitted_at
       or v_message is not null
       or coalesce(pg_catalog.cardinality(v_perks), 0) <> 0
       or v_bid_accepted_at is not null
       or v_bid_declined_at is not null
       or v_bid_withdrawn_at is not null
       or v_category_active is distinct from true
       or v_service_active is distinct from true
       or not private.provider_marketplace_eligibility_is_current(
         v_provider_id,
         v_decision_at
       ) then
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
    end if;

    perform pg_catalog.set_config(
      'lekkadeall.allow_marketplace_state_transition',
      'on',
      true
    );
    v_transition_enabled := true;

    begin
      update public.bids as bid
      set status = 'accepted'::public.bid_status,
          accepted_at = v_decision_at
      where bid.id = p_bid_id
        and bid.request_id = p_request_id
        and bid.status = 'submitted'::public.bid_status
        and bid.accepted_at is null
        and bid.declined_at is null
        and bid.withdrawn_at is null;

      get diagnostics v_affected_rows = row_count;
      if v_affected_rows <> 1 then
        raise exception 'Customer bid acceptance is unavailable'
          using errcode = '42501';
      end if;

      update public.bids as bid
      set status = 'declined'::public.bid_status,
          declined_at = v_decision_at
      where bid.request_id = p_request_id
        and bid.id <> p_bid_id
        and bid.status = 'submitted'::public.bid_status;

      get diagnostics v_affected_rows = row_count;
      if v_affected_rows <> v_competing_bid_count then
        raise exception 'Customer bid acceptance is unavailable'
          using errcode = '42501';
      end if;

      update public.service_requests as request
      set status = 'awarded'::public.request_status,
          awarded_at = v_decision_at
      where request.id = p_request_id
        and request.customer_id = v_actor_id
        and request.status = 'open'::public.request_status
        and request.awarded_at is null
        and request.cancelled_at is null;

      get diagnostics v_affected_rows = row_count;
      if v_affected_rows <> 1 then
        raise exception 'Customer bid acceptance is unavailable'
          using errcode = '42501';
      end if;

      insert into private.customer_bid_acceptance_receipts (
        request_id,
        customer_id,
        bid_id,
        idempotency_key,
        contract_version,
        expected_request_updated_at,
        expected_bid_submitted_at,
        intent_fingerprint,
        accepted_at,
        awarded_at,
        created_at
      ) values (
        p_request_id,
        v_actor_id,
        p_bid_id,
        p_idempotency_key,
        'customer-bid-acceptance-v1',
        p_expected_request_updated_at,
        p_expected_bid_submitted_at,
        v_fingerprint,
        v_decision_at,
        v_decision_at,
        v_decision_at
      );

      perform private.append_audit_event(
        v_actor_id,
        'customer.bid_accepted',
        'bid',
        p_bid_id::pg_catalog.text,
        null,
        pg_catalog.jsonb_build_object('request_id', p_request_id)
      );
    exception
      when others then
        if v_transition_enabled then
          perform pg_catalog.set_config(
            'lekkadeall.allow_marketplace_state_transition',
            'off',
            true
          );
          v_transition_enabled := false;
        end if;
        raise;
    end;

    perform pg_catalog.set_config(
      'lekkadeall.allow_marketplace_state_transition',
      'off',
      true
    );
    v_transition_enabled := false;

    return query select
      p_request_id,
      p_bid_id,
      'awarded'::public.request_status,
      'accepted'::public.bid_status,
      v_decision_at,
      v_decision_at;
  exception
    when others then
      if v_transition_enabled then
        perform pg_catalog.set_config(
          'lekkadeall.allow_marketplace_state_transition',
          'off',
          true
        );
      end if;
      raise exception 'Customer bid acceptance is unavailable'
        using errcode = '42501';
  end;
end;
$$;

create function public.customer_reconcile_bid_acceptance(
  p_request_id pg_catalog.uuid,
  p_idempotency_key pg_catalog.uuid
)
returns table (
  request_id pg_catalog.uuid,
  accepted_bid_id pg_catalog.uuid,
  request_status public.request_status,
  bid_status public.bid_status,
  awarded_at pg_catalog.timestamptz,
  accepted_at pg_catalog.timestamptz
)
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id pg_catalog.uuid;
begin
  begin
    v_actor_id := auth.uid();

    if v_actor_id is null
       or p_request_id is null
       or p_request_id = '00000000-0000-0000-0000-000000000000'::pg_catalog.uuid
       or p_idempotency_key is null
       or p_idempotency_key = '00000000-0000-0000-0000-000000000000'::pg_catalog.uuid then
      raise exception 'Customer bid acceptance reconciliation is unavailable'
        using errcode = '42501';
    end if;

    return query
    select
      receipt.request_id,
      receipt.bid_id,
      request.status,
      bid.status,
      receipt.awarded_at,
      receipt.accepted_at
    from public.profiles as profile
    join private.customer_bid_acceptance_receipts as receipt
      on receipt.customer_id = profile.id
     and receipt.request_id = p_request_id
     and receipt.idempotency_key = p_idempotency_key
    join public.service_requests as request
      on request.id = receipt.request_id
     and request.customer_id = profile.id
     and request.status = 'awarded'::public.request_status
     and request.awarded_at = receipt.awarded_at
     and request.cancelled_at is null
    join public.bids as bid
      on bid.id = receipt.bid_id
     and bid.request_id = receipt.request_id
     and bid.status = 'accepted'::public.bid_status
     and bid.accepted_at = receipt.accepted_at
     and bid.declined_at is null
     and bid.withdrawn_at is null
    where profile.id = v_actor_id
      and profile.role = 'customer'::public.user_role
      and profile.account_status = 'active';

    if not found then
      raise exception 'Customer bid acceptance reconciliation is unavailable'
        using errcode = '42501';
    end if;
  exception
    when others then
      raise exception 'Customer bid acceptance reconciliation is unavailable'
        using errcode = '42501';
  end;
end;
$$;

comment on table private.customer_bid_acceptance_receipts is
  'Ticket 10F private append-only idempotency receipts for customer-owned bid selection; never browser-readable.';

comment on function public.customer_accept_current_bid(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.timestamptz,
  pg_catalog.timestamptz,
  pg_catalog.uuid
) is
  'Ticket 10F authenticated customer selection: accepts one current bid and awards its owned request without creating booking, payment, contact, or address authority.';

comment on function public.customer_reconcile_bid_acceptance(
  pg_catalog.uuid,
  pg_catalog.uuid
) is
  'Ticket 10F owner-only reconciliation: returns only the minimal canonical acceptance result tied to one private receipt.';

revoke all on function public.customer_accept_current_bid(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.timestamptz,
  pg_catalog.timestamptz,
  pg_catalog.uuid
) from public, anon, authenticated, service_role;

revoke all on function public.customer_reconcile_bid_acceptance(
  pg_catalog.uuid,
  pg_catalog.uuid
) from public, anon, authenticated, service_role;

grant execute on function public.customer_accept_current_bid(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.timestamptz,
  pg_catalog.timestamptz,
  pg_catalog.uuid
) to authenticated;

grant execute on function public.customer_reconcile_bid_acceptance(
  pg_catalog.uuid,
  pg_catalog.uuid
) to authenticated;

revoke all on function public.customer_accept_bid(pg_catalog.uuid)
  from public, anon, authenticated, service_role;
