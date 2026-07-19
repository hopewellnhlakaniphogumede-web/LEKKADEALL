-- Ticket 9A-7: strict customer-owned draft-only cancellation.
-- Browser callers receive one narrowly scoped RPC. The older Ticket 6
-- draft/open cancellation function is no longer executable by authenticated
-- users because a UI-only draft restriction would not be a security boundary.

create or replace function public.customer_cancel_draft_request(
  p_request_id uuid
)
returns public.request_status
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_account_status text;
  v_request_status public.request_status;
  v_closes_at timestamptz;
  v_published_at timestamptz;
  v_awarded_at timestamptz;
  v_cancelled_at timestamptz;
  v_changed_rows integer;
  v_changed_at timestamptz;
begin
  if p_request_id is null then
    raise exception 'Draft request ID is required'
      using errcode = '22023';
  end if;

  if v_actor_id is null then
    raise exception 'Authentication is required to cancel a draft'
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
    raise exception 'Draft cancellation is unavailable'
      using errcode = '42501';
  end if;

  select
    sr.status,
    sr.closes_at,
    sr.published_at,
    sr.awarded_at,
    sr.cancelled_at
    into
      v_request_status,
      v_closes_at,
      v_published_at,
      v_awarded_at,
      v_cancelled_at
  from public.service_requests as sr
  where sr.id = p_request_id
    and sr.customer_id = v_actor_id
  for update;

  if not found
     or v_request_status <> 'draft'::public.request_status
     or v_closes_at is not null
     or v_published_at is not null
     or v_awarded_at is not null
     or v_cancelled_at is not null then
    raise exception 'Draft is not available for cancellation'
      using errcode = '42501';
  end if;

  -- A valid draft cannot have a bid or a booking. Reject any related row
  -- instead of mutating provider/booking state from this customer-only path.
  if exists (
    select 1
    from public.bids as b
    where b.request_id = p_request_id
  ) or exists (
    select 1
    from public.bookings as b
    where b.request_id = p_request_id
  ) then
    raise exception 'Draft is not available for cancellation'
      using errcode = '42501';
  end if;

  v_changed_at := pg_catalog.clock_timestamp();
  perform pg_catalog.set_config(
    'lekkadeall.allow_marketplace_state_transition',
    'on',
    true
  );

  begin
    update public.service_requests as sr
    set status = 'cancelled'::public.request_status,
        cancelled_at = v_changed_at,
        updated_at = v_changed_at
    where sr.id = p_request_id
      and sr.customer_id = v_actor_id
      and sr.status = 'draft'::public.request_status
      and sr.closes_at is null
      and sr.published_at is null
      and sr.awarded_at is null
      and sr.cancelled_at is null;

    get diagnostics v_changed_rows = row_count;
    if v_changed_rows <> 1 then
      raise exception 'Draft is not available for cancellation'
        using errcode = '42501';
    end if;

    -- Keep the privileged Ticket 6 transition flag scoped to the status update.
    -- The audit append is atomic with the update but does not need this flag.
    perform pg_catalog.set_config(
      'lekkadeall.allow_marketplace_state_transition',
      'off',
      true
    );

    perform private.append_audit_event(
      v_actor_id,
      'customer.service_request_draft_cancelled',
      'service_request',
      p_request_id::text,
      'Customer cancelled own draft through controlled draft-only function',
      pg_catalog.jsonb_build_object(
        'request_id', p_request_id,
        'previous_status', 'draft',
        'new_status', 'cancelled'
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

  return 'cancelled'::public.request_status;
end;
$$;

comment on function public.customer_cancel_draft_request(uuid) is
  'Ticket 9A-7 customer-only RPC: atomically cancels one owned, internally consistent draft with no bids or bookings and writes a fixed privacy-safe audit event.';

comment on function public.customer_cancel_request(uuid, text) is
  'Legacy Ticket 6 draft/open cancellation function. Not browser-executable after Ticket 9A-7; any future open-request cancellation requires a separate reviewed contract.';

comment on table public.service_requests is
  'Ticket 6/9A-7 state machine: browser clients create drafts through customer_create_draft_request and may cancel only owned drafts through customer_cancel_draft_request. Publication and other state changes remain separately controlled.';

revoke all on function public.customer_cancel_draft_request(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_cancel_draft_request(uuid)
  to authenticated;

revoke all on function public.customer_cancel_request(uuid, text)
  from public, anon, authenticated;
