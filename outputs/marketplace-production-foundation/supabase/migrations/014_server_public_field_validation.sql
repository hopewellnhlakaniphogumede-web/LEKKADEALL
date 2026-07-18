-- Ticket 9A-5: authoritative server-side validation for eventually public
-- service-request text. Frontend validation remains defence in depth only.

create or replace function private.canonicalize_service_request_public_field(
  p_field_name text,
  p_value text
)
returns text
language plpgsql
immutable
security definer
set search_path = pg_catalog
as $$
declare
  v_value text;
begin
  if p_field_name not in ('title', 'description', 'suburb', 'city') then
    raise exception 'Unsupported service request public field'
      using errcode = '22023';
  end if;

  if p_value is null then
    return null;
  end if;

  -- PostgreSQL 15 normalizes to NFC by default. Only CRLF is canonicalized for
  -- the multiline description; lone CR and all other controls are rejected by
  -- the structural validator.
  v_value := normalize(p_value);
  if p_field_name = 'description' then
    v_value := pg_catalog.replace(v_value, E'\r\n', E'\n');
  end if;

  v_value := pg_catalog.regexp_replace(v_value, '^[[:space:]]+', '');
  v_value := pg_catalog.regexp_replace(v_value, '[[:space:]]+$', '');
  return v_value;
end;
$$;

create or replace function private.service_request_public_field_has_forbidden_unicode(
  p_value text
)
returns boolean
language sql
immutable
security definer
set search_path = pg_catalog
as $$
  select case
    when p_value is null then false
    else
      pg_catalog.strpos(p_value, pg_catalog.chr(173)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8203)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8204)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8205)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8232)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8233)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8234)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8235)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8236)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8237)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8238)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8288)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8294)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8295)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8296)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(8297)) > 0
      or pg_catalog.strpos(p_value, pg_catalog.chr(65279)) > 0
  end;
$$;

create or replace function private.service_request_public_field_privacy_risk(
  p_field_name text,
  p_value text
)
returns boolean
language plpgsql
immutable
security definer
set search_path = pg_catalog
as $$
declare
  v_detection text;
begin
  if p_field_name not in ('title', 'description', 'suburb', 'city') then
    raise exception 'Unsupported service request public field'
      using errcode = '22023';
  end if;

  if p_value is null or p_value = '' then
    return false;
  end if;

  v_detection := pg_catalog.lower(p_value);
  v_detection := pg_catalog.replace(v_detection, pg_catalog.chr(160), ' ');
  v_detection := pg_catalog.replace(v_detection, pg_catalog.chr(8208), '-');
  v_detection := pg_catalog.replace(v_detection, pg_catalog.chr(8209), '-');
  v_detection := pg_catalog.replace(v_detection, pg_catalog.chr(8210), '-');
  v_detection := pg_catalog.replace(v_detection, pg_catalog.chr(8211), '-');
  v_detection := pg_catalog.replace(v_detection, pg_catalog.chr(8212), '-');
  v_detection := pg_catalog.replace(v_detection, pg_catalog.chr(8213), '-');
  v_detection := pg_catalog.regexp_replace(v_detection, '[[:space:]]+', ' ', 'g');

  return
    -- Numbered street addresses, including reviewed English/Afrikaans forms.
    v_detection ~* '(^|[^[:alnum:]_])[0-9]{1,6}[[:alpha:]]?[[:space:]]+[[:alpha:]][[:alnum:] .''-]{0,80}[[:space:]]+(street|straat|st|road|rd|weg|avenue|ave|laan|drive|dr|rylaan|lane|ln|way|close|crescent|cres|boulevard|blvd|place|pl|terrace|terr|highway)([^[:alnum:]_]|$)'

    -- Unit/room/floor identifiers. Requiring a following digit avoids phrases
    -- such as "paint 3 rooms" and "block paving".
    or v_detection ~* '(^|[^[:alnum:]_])(unit|flat|room|apt|apartment|suite|floor|block)[[:space:]]*(no[.]?|number|#)?[[:space:]]*[[:alpha:]]{0,2}[0-9][[:alnum:]-]{0,10}([^[:alnum:]_]|$)'

    -- House/stand/erf/plot/farm/site identifiers. A marker or digit is required
    -- so ordinary phrases such as "stand mixer repair" remain safe.
    or v_detection ~* '(^|[^[:alnum:]_])(house|stand|erf|plot|farm|site)[[:space:]]*(no[.]?|number|#)[[:space:]]*[[:alnum:]-]{1,20}([^[:alnum:]_]|$)'
    or v_detection ~* '(^|[^[:alnum:]_])(house|stand|erf|plot|farm|site)[[:space:]]*[0-9][[:alnum:]-]{0,19}([^[:alnum:]_]|$)'

    -- Named complex/building details require an explicit location cue to avoid
    -- rejecting "complex electrical fault" and similar service text.
    or v_detection ~* '(^|[^[:alnum:]_])(at|in|inside|located[[:space:]]+at|come[[:space:]]+to)[[:space:]]+(the[[:space:]]+)?(complex|estate|residence|hostel|lodge|building)[[:space:]]+[[:alnum:]][[:alnum:] .''-]{1,60}([^[:alnum:]_]|$)'
    or v_detection ~* '(^|[^[:alnum:]_])(at|in|inside|located[[:space:]]+at|come[[:space:]]+to)[[:space:]]+(the[[:space:]]+)?[[:alpha:]][[:alnum:] .''-]{1,60}[[:space:]]+(complex|estate|residence|hostel|lodge|building)([^[:alnum:]_]|$)'

    -- Decimal pairs, DMS-like coordinates, and labelled location coordinates.
    or v_detection ~* '[-+]?[0-9]{1,2}[.][0-9]{4,}[[:space:]]*,[[:space:]]*[-+]?[0-9]{1,3}[.][0-9]{4,}'
    or v_detection ~* '[0-9]{1,3}[[:space:]]*°[[:space:]]*[0-9]{1,2}([.][0-9]+)?[[:space:]]*[''’]?[[:space:]]*[nsew][^[:alnum:]]+[0-9]{1,3}[[:space:]]*°'
    or v_detection ~* '(^|[^[:alnum:]_])(gps|coordinates|latitude|longitude|lat|lng|location[[:space:]]+pin|map[[:space:]]+pin|plus[[:space:]]+code)[[:space:]]*[:=-]?[[:space:]]*[-+]?[0-9]'

    -- South African phone numbers and contact-cued international numbers.
    or v_detection ~* '(^|[^[:alnum:]_])(\+27|0)[0-9][0-9[:space:]().-]{7,}[0-9]([^[:alnum:]_]|$)'
    or v_detection ~* '(^|[^[:alnum:]_])(call|phone|whats[[:space:]]*app|sms|contact)[[:space:]]+(me[[:space:]]+)?(on[[:space:]]+)?\+[1-9][0-9[:space:]().-]{7,}[0-9]([^[:alnum:]_]|$)'

    -- Email addresses and a conservative contact-cued word-obfuscated form.
    or v_detection ~* '[[:alnum:]_.%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,}'
    or v_detection ~* '(^|[^[:alnum:]_])(email|mail|contact)[[:space:]]+(me[[:space:]]+)?(at[[:space:]]+)?[[:alnum:]_.%+-]+[[:space:]]+at[[:space:]]+[[:alnum:].-]+[[:space:]]+dot[[:space:]]+[[:alpha:]]{2,}'

    -- Schemed links, bare common/South African domains, and contact schemes.
    or v_detection ~* '(^|[^[:alnum:]_])(https?://|www[.]|mailto:|tel:|javascript:)'
    or v_detection ~* '(^|[^[:alnum:]_])[[:alnum:]][[:alnum:].-]{0,100}[.](co[.]za|org[.]za|net[.]za|com|org|net|io|app|dev|me|za)([^[:alnum:]_]|$)'

    -- Social handles and instructions to communicate off platform.
    or v_detection ~* '(^|[[:space:]])@[[:alnum:]_]{2,}([^[:alnum:]_]|$)'
    or v_detection ~* '(^|[^[:alnum:]_])(whats[[:space:]]*app|telegram|signal|facebook|instagram|tiktok|twitter|contact[[:space:]]+me|call[[:space:]]+me|email[[:space:]]+me|dm[[:space:]]+me|inbox[[:space:]]+me|message[[:space:]]+me|sms[[:space:]]+me)([^[:alnum:]_]|$)'

    -- Access/gate/security credentials. Requiring a digit avoids rejecting the
    -- safe sentence "access code will be shared securely after booking".
    or v_detection ~* '(^|[^[:alnum:]_])(gate|access|security|alarm|intercom|door|keypad)[[:space:]]*(code|pin|password)[[:space:]]*[:#=-]?[[:space:]]*[[:alpha:]-]{0,4}[0-9][[:alnum:]-]{1,19}([^[:alnum:]_]|$)';
end;
$$;

create or replace function private.service_request_public_field_violation(
  p_field_name text,
  p_value text
)
returns text
language plpgsql
immutable
security definer
set search_path = pg_catalog
as $$
declare
  v_value text;
  v_min_chars integer;
  v_max_chars integer;
  v_max_bytes integer;
  v_multiline boolean;
begin
  if p_field_name = 'title' then
    v_min_chars := 3;
    v_max_chars := 120;
    v_max_bytes := 480;
    v_multiline := false;
  elsif p_field_name = 'description' then
    v_min_chars := 10;
    v_max_chars := 3000;
    v_max_bytes := 12000;
    v_multiline := true;
  elsif p_field_name in ('suburb', 'city') then
    v_min_chars := 2;
    v_max_chars := 120;
    v_max_bytes := 480;
    v_multiline := false;
  else
    raise exception 'Unsupported service request public field'
      using errcode = '22023';
  end if;

  v_value := private.canonicalize_service_request_public_field(p_field_name, p_value);

  if v_value is null or v_value = '' then
    return 'required';
  end if;

  if pg_catalog.char_length(v_value) < v_min_chars
     or pg_catalog.char_length(v_value) > v_max_chars
     or pg_catalog.octet_length(v_value) > v_max_bytes then
    return 'invalid_length';
  end if;

  if (not v_multiline and v_value ~ '[[:cntrl:]]')
     or (v_multiline and pg_catalog.replace(v_value, E'\n', '') ~ '[[:cntrl:]]')
     or private.service_request_public_field_has_forbidden_unicode(v_value) then
    return 'unsupported_format';
  end if;

  if pg_catalog.strpos(v_value, '<') > 0
     or pg_catalog.strpos(v_value, '>') > 0
     or v_value ~* '(&lt;|&#0*60;|&#x0*3c;)[[:space:]]*/?[[:space:]]*(script|iframe|object|embed|style|svg|img|form|meta|link)'
     or v_value ~* '(^|[^[:alnum:]_])on(error|load|click|focus|mouseover)[[:space:]]*=' then
    return 'unsafe_markup';
  end if;

  if private.service_request_public_field_privacy_risk(p_field_name, v_value) then
    return 'private_or_unsafe_content';
  end if;

  return null;
end;
$$;

create or replace function private.assert_service_request_public_fields(
  p_title text,
  p_description text,
  p_suburb text,
  p_city text
)
returns void
language plpgsql
immutable
security definer
set search_path = pg_catalog
as $$
declare
  v_violation text;
begin
  v_violation := private.service_request_public_field_violation('title', p_title);
  if v_violation is not null then
    if v_violation = 'required' then
      raise exception 'Public title is required' using errcode = '22023';
    elsif v_violation = 'invalid_length' then
      raise exception 'Public title has an invalid length' using errcode = '22023';
    elsif v_violation = 'unsupported_format' then
      raise exception 'Public title contains unsupported formatting' using errcode = '22023';
    else
      raise exception 'Public title contains private or unsupported information' using errcode = '22023';
    end if;
  end if;

  v_violation := private.service_request_public_field_violation('description', p_description);
  if v_violation is not null then
    if v_violation = 'required' then
      raise exception 'Public description is required' using errcode = '22023';
    elsif v_violation = 'invalid_length' then
      raise exception 'Public description has an invalid length' using errcode = '22023';
    elsif v_violation = 'unsupported_format' then
      raise exception 'Public description contains unsupported formatting' using errcode = '22023';
    else
      raise exception 'Public description contains private or unsupported information' using errcode = '22023';
    end if;
  end if;

  v_violation := private.service_request_public_field_violation('suburb', p_suburb);
  if v_violation is not null then
    if v_violation = 'required' then
      raise exception 'Suburb is required' using errcode = '22023';
    elsif v_violation = 'invalid_length' then
      raise exception 'Suburb has an invalid length' using errcode = '22023';
    elsif v_violation = 'unsupported_format' then
      raise exception 'Suburb contains unsupported formatting' using errcode = '22023';
    else
      raise exception 'Suburb contains private or unsupported information' using errcode = '22023';
    end if;
  end if;

  v_violation := private.service_request_public_field_violation('city', p_city);
  if v_violation is not null then
    if v_violation = 'required' then
      raise exception 'City is required' using errcode = '22023';
    elsif v_violation = 'invalid_length' then
      raise exception 'City has an invalid length' using errcode = '22023';
    elsif v_violation = 'unsupported_format' then
      raise exception 'City contains unsupported formatting' using errcode = '22023';
    else
      raise exception 'City contains private or unsupported information' using errcode = '22023';
    end if;
  end if;
end;
$$;

create or replace function private.enforce_service_request_public_fields()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  -- Status-only transitions other than opening remain possible for legacy rows.
  -- Every insert, public-field edit, and transition to open is validated.
  if tg_op = 'UPDATE'
     and new.title is not distinct from old.title
     and new.description is not distinct from old.description
     and new.suburb is not distinct from old.suburb
     and new.city is not distinct from old.city
     and new.status <> 'open' then
    return new;
  end if;

  new.title := private.canonicalize_service_request_public_field('title', new.title);
  new.description := private.canonicalize_service_request_public_field('description', new.description);
  new.suburb := private.canonicalize_service_request_public_field('suburb', new.suburb);
  new.city := private.canonicalize_service_request_public_field('city', new.city);

  perform private.assert_service_request_public_fields(
    new.title,
    new.description,
    new.suburb,
    new.city
  );

  return new;
end;
$$;

drop trigger if exists enforce_service_request_public_fields on public.service_requests;
create trigger enforce_service_request_public_fields
before insert or update of title, description, suburb, city, status
on public.service_requests
for each row execute function private.enforce_service_request_public_fields();

-- Keep Ticket 5's browser-compatible description preflight and open-row
-- trigger behavior, while delegating its risk decision to the new authority.
create or replace function public.service_request_description_has_exact_address_risk(
  p_description text
)
returns boolean
language sql
immutable
security definer
set search_path = pg_catalog
as $$
  select private.service_request_public_field_privacy_risk('description', p_description);
$$;

create or replace function public.customer_create_draft_request(
  p_category_id uuid,
  p_title text,
  p_description text,
  p_suburb text,
  p_city text,
  p_requested_start timestamptz,
  p_budget_minor integer default null,
  p_precise_address_ciphertext text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id uuid := auth.uid();
  v_request_id uuid;
  v_title text;
  v_description text;
  v_suburb text;
  v_city text;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to create a request'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_actor_id
      and p.role = 'customer'
      and p.account_status = 'active'
  ) then
    raise exception 'Only active customers may create service requests'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.service_categories sc
    where sc.id = p_category_id
      and sc.active = true
  ) then
    raise exception 'Service category is unavailable'
      using errcode = '22023';
  end if;

  if p_requested_start is null or p_requested_start <= pg_catalog.now() then
    raise exception 'Requested start must be in the future'
      using errcode = '22023';
  end if;

  if p_budget_minor is not null and p_budget_minor < 0 then
    raise exception 'Budget cannot be negative'
      using errcode = '22023';
  end if;

  if p_precise_address_ciphertext is not null
     and nullif(pg_catalog.btrim(p_precise_address_ciphertext), '') is null then
    raise exception 'Precise address ciphertext cannot be blank'
      using errcode = '22023';
  end if;

  v_title := private.canonicalize_service_request_public_field('title', p_title);
  v_description := private.canonicalize_service_request_public_field('description', p_description);
  v_suburb := private.canonicalize_service_request_public_field('suburb', p_suburb);
  v_city := private.canonicalize_service_request_public_field('city', p_city);

  perform private.assert_service_request_public_fields(
    v_title,
    v_description,
    v_suburb,
    v_city
  );

  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  begin
    insert into public.service_requests (
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
    ) values (
      v_actor_id,
      p_category_id,
      v_title,
      v_description,
      v_suburb,
      v_city,
      p_requested_start,
      p_budget_minor,
      'draft',
      null
    )
    returning id into v_request_id;

    if nullif(pg_catalog.btrim(coalesce(p_precise_address_ciphertext, '')), '') is not null then
      insert into private.service_request_addresses (
        request_id,
        customer_id,
        precise_address_ciphertext
      ) values (
        v_request_id,
        v_actor_id,
        pg_catalog.btrim(p_precise_address_ciphertext)
      );

      perform private.append_audit_event(
        v_actor_id,
        'customer.request_address_upserted',
        'service_request',
        v_request_id::text,
        'Customer added draft request precise address during request creation',
        pg_catalog.jsonb_build_object('request_id', v_request_id, 'customer_id', v_actor_id)
      );
    end if;

    perform private.append_audit_event(
      v_actor_id,
      'customer.service_request_draft_created',
      'service_request',
      v_request_id::text,
      'Customer created draft service request',
      pg_catalog.jsonb_build_object('request_id', v_request_id, 'category_id', p_category_id)
    );
  exception
    when others then
      perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
      raise;
  end;

  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
  return v_request_id;
end;
$$;

comment on function private.canonicalize_service_request_public_field(text, text) is
  'Ticket 9A-5 NFC/whitespace canonicalization for the four eventually public service-request fields.';
comment on function private.service_request_public_field_has_forbidden_unicode(text) is
  'Ticket 9A-5 detector for bidi, zero-width, soft-hyphen, and unsupported Unicode formatting characters.';
comment on function private.service_request_public_field_privacy_risk(text, text) is
  'Ticket 9A-5 shared private classifier for exact-location, contact, URL/social, GPS, and access-code risk.';
comment on function private.service_request_public_field_violation(text, text) is
  'Ticket 9A-5 structural and privacy validator returning only privacy-safe violation codes.';
comment on function private.assert_service_request_public_fields(text, text, text, text) is
  'Ticket 9A-5 authoritative assertion boundary for title, description, suburb, and city.';
comment on function private.enforce_service_request_public_fields() is
  'Ticket 9A-5 table trigger backstop for public-field writes and transitions to open.';
comment on function public.service_request_description_has_exact_address_risk(text) is
  'Compatibility preflight delegating to the Ticket 9A-5 shared private public-field privacy classifier.';
comment on function public.customer_create_draft_request(uuid, text, text, text, text, timestamptz, integer, text) is
  'Creates an active customer draft only after Ticket 9A-5 server validation of every eventually public text field.';

revoke all on function private.canonicalize_service_request_public_field(text, text) from public, anon, authenticated, service_role;
revoke all on function private.service_request_public_field_has_forbidden_unicode(text) from public, anon, authenticated, service_role;
revoke all on function private.service_request_public_field_privacy_risk(text, text) from public, anon, authenticated, service_role;
revoke all on function private.service_request_public_field_violation(text, text) from public, anon, authenticated, service_role;
revoke all on function private.assert_service_request_public_fields(text, text, text, text) from public, anon, authenticated, service_role;
revoke all on function private.enforce_service_request_public_fields() from public, anon, authenticated, service_role;

revoke all on function public.service_request_description_has_exact_address_risk(text) from public, anon;
grant execute on function public.service_request_description_has_exact_address_risk(text) to authenticated, service_role;

revoke all on function public.customer_create_draft_request(uuid, text, text, text, text, timestamptz, integer, text) from public, anon;
grant execute on function public.customer_create_draft_request(uuid, text, text, text, text, timestamptz, integer, text) to authenticated, service_role;
