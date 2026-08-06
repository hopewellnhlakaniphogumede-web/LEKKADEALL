-- Ticket 9A-11: strict customer-owned draft publication.
-- Publication exposes only the already reviewed public request fields. Exact
-- address collection and reveal remain outside this transition and ticket.

create or replace function public.customer_publish_draft_request(
  p_request_id pg_catalog.uuid
)
returns public.request_status
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id pg_catalog.uuid := auth.uid();
  v_actor_role public.user_role;
  v_account_status pg_catalog.text;
  v_category_id pg_catalog.uuid;
  v_title pg_catalog.text;
  v_description pg_catalog.text;
  v_suburb pg_catalog.text;
  v_city pg_catalog.text;
  v_requested_start pg_catalog.timestamptz;
  v_budget_minor pg_catalog.int4;
  v_request_status public.request_status;
  v_closes_at pg_catalog.timestamptz;
  v_published_at pg_catalog.timestamptz;
  v_awarded_at pg_catalog.timestamptz;
  v_cancelled_at pg_catalog.timestamptz;
  v_deprecated_address pg_catalog.text;
  v_changed_at pg_catalog.timestamptz;
  v_changed_rows pg_catalog.int4;
begin
  if p_request_id is null then
    raise exception 'Draft request ID is required'
      using errcode = '22023';
  end if;

  if v_actor_id is null then
    raise exception 'Authentication is required to publish a draft'
      using errcode = '42501';
  end if;

  select p.role, p.account_status
    into v_actor_role, v_account_status
  from public.profiles as p
  where p.id = v_actor_id
  for share;

  if not found
     or v_actor_role <> 'customer'::public.user_role
     or v_account_status <> 'active' then
    raise exception 'Draft publication is unavailable'
      using errcode = '42501';
  end if;

  select
    sr.category_id,
    sr.title,
    sr.description,
    sr.suburb,
    sr.city,
    sr.requested_start,
    sr.budget_minor,
    sr.status,
    sr.closes_at,
    sr.published_at,
    sr.awarded_at,
    sr.cancelled_at,
    sr.precise_address_ciphertext
    into
      v_category_id,
      v_title,
      v_description,
      v_suburb,
      v_city,
      v_requested_start,
      v_budget_minor,
      v_request_status,
      v_closes_at,
      v_published_at,
      v_awarded_at,
      v_cancelled_at,
      v_deprecated_address
  from public.service_requests as sr
  where sr.id = p_request_id
    and sr.customer_id = v_actor_id
  for update;

  if not found
     or v_request_status <> 'draft'::public.request_status
     or v_closes_at is not null
     or v_published_at is not null
     or v_awarded_at is not null
     or v_cancelled_at is not null
     or v_deprecated_address is not null then
    raise exception 'Draft is not available for publication'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.bids as b
    where b.request_id = p_request_id
  ) or exists (
    select 1
    from public.bookings as b
    where b.request_id = p_request_id
  ) then
    raise exception 'Draft is not available for publication'
      using errcode = '42501';
  end if;

  perform sc.id
  from public.service_categories as sc
  where sc.id = v_category_id
    and sc.active = true
  for share;

  if not found then
    raise exception 'Draft publication is unavailable'
      using errcode = '22023';
  end if;

  v_changed_at := pg_catalog.transaction_timestamp();

  if v_requested_start is null or v_requested_start <= v_changed_at then
    raise exception 'Draft publication is unavailable'
      using errcode = '22023';
  end if;

  if v_budget_minor is not null and v_budget_minor < 0 then
    raise exception 'Draft publication is unavailable'
      using errcode = '22023';
  end if;

  perform private.assert_service_request_public_fields(
    v_title,
    v_description,
    v_suburb,
    v_city
  );

  -- Preserve the established Ticket 6 timing rule without accepting a
  -- browser-controlled close time.
  v_closes_at := v_changed_at + '3 days'::pg_catalog.interval;
  if v_requested_start - '1 hour'::pg_catalog.interval < v_closes_at then
    v_closes_at := v_requested_start - '1 hour'::pg_catalog.interval;
  end if;

  if v_closes_at <= v_changed_at or v_closes_at >= v_requested_start then
    raise exception 'Draft publication is unavailable'
      using errcode = '22023';
  end if;

  perform pg_catalog.set_config(
    'lekkadeall.allow_marketplace_state_transition',
    'on',
    true
  );

  begin
    update public.service_requests as sr
    set status = 'open'::public.request_status,
        closes_at = v_closes_at,
        published_at = v_changed_at,
        updated_at = v_changed_at
    where sr.id = p_request_id
      and sr.customer_id = v_actor_id
      and sr.status = 'draft'::public.request_status
      and sr.closes_at is null
      and sr.published_at is null
      and sr.awarded_at is null
      and sr.cancelled_at is null
      and sr.precise_address_ciphertext is null;

    get diagnostics v_changed_rows = row_count;
    if v_changed_rows <> 1 then
      raise exception 'Draft is not available for publication'
        using errcode = '42501';
    end if;

    -- Keep the privileged transition flag scoped to the guarded row update.
    -- The audit append remains atomic but does not execute with the flag on.
    perform pg_catalog.set_config(
      'lekkadeall.allow_marketplace_state_transition',
      'off',
      true
    );

    perform private.append_audit_event(
      v_actor_id,
      'customer.service_request_draft_published',
      'service_request',
      p_request_id::pg_catalog.text,
      'Customer published own draft service request',
      pg_catalog.jsonb_build_object(
        'request_id', p_request_id,
        'previous_status', 'draft',
        'new_status', 'open'
      )
    );
  exception
    when others then
      perform pg_catalog.set_config(
        'lekkadeall.allow_marketplace_state_transition',
        'off',
        true
      );
      raise;
  end;

  perform pg_catalog.set_config(
    'lekkadeall.allow_marketplace_state_transition',
    'off',
    true
  );

  return 'open'::public.request_status;
end;
$$;

comment on function public.customer_publish_draft_request(pg_catalog.uuid) is
  'Ticket 9A-11 customer-only RPC: atomically publishes one owned, internally consistent, address-independent draft after authoritative public-field validation and writes a fixed privacy-safe audit event.';

comment on table public.service_requests is
  'Ticket 6/9A-7/9A-8/9A-11 controlled workflow: browser clients create, edit, publish, and cancel owned drafts only through reviewed RPCs. Publication exposes reviewed public fields and does not require or reveal an exact address.';

revoke all on function public.customer_publish_draft_request(pg_catalog.uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.customer_publish_draft_request(pg_catalog.uuid)
  to authenticated;

revoke all on function public.customer_publish_request(
  pg_catalog.uuid,
  pg_catalog.timestamptz
)
  from public, anon, authenticated;
