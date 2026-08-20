create function private.normalize_recognition_candidates(
  target_company_id uuid,
  raw_candidates jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  candidate jsonb;
  candidate_product_id uuid;
  candidate_confidence numeric;
  normalized jsonb := '[]'::jsonb;
  seen_ids uuid[] := '{}'::uuid[];
begin
  if raw_candidates is null then
    return normalized;
  end if;
  if jsonb_typeof(raw_candidates) <> 'array' or jsonb_array_length(raw_candidates) > 3 then
    raise exception 'Candidate products must be an array containing at most three products.'
      using errcode = '22023';
  end if;
  for candidate in select value from jsonb_array_elements(raw_candidates)
  loop
    if jsonb_typeof(candidate) <> 'object' then
      raise exception 'Each recognition candidate must be an object.'
        using errcode = '22023';
    end if;
    begin
      candidate_product_id := (candidate ->> 'product_id')::uuid;
      candidate_confidence := (candidate ->> 'confidence')::numeric;
    exception when others then
      raise exception 'Recognition candidate identity or confidence is invalid.'
        using errcode = '22023';
    end;
    if candidate_product_id is null or candidate_confidence is null
      or candidate_confidence < 0 or candidate_confidence > 1 then
      raise exception 'Recognition candidate confidence must be between zero and one.'
        using errcode = '22023';
    end if;
    if candidate_product_id = any(seen_ids) then
      raise exception 'Recognition candidates must be unique.'
        using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.products
      where id = candidate_product_id and company_id = target_company_id and status = 'active'
    ) then
      raise exception 'Recognition candidate is not an active company product.'
        using errcode = '22023';
    end if;
    seen_ids := array_append(seen_ids, candidate_product_id);
    normalized := normalized || jsonb_build_array(jsonb_build_object(
      'product_id', candidate_product_id,
      'confidence', round(candidate_confidence, 4)
    ));
  end loop;
  return normalized;
end;
$$;

revoke all on function private.normalize_recognition_candidates(uuid, jsonb)
from public, anon, authenticated;

create function private.recognition_confidence_tier(
  target_company_id uuid,
  candidate_count integer,
  top_confidence numeric
)
returns public.recognition_confidence_tier
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when candidate_count = 0 or top_confidence is null then 'NO_MATCH'::public.recognition_confidence_tier
    when top_confidence >= settings.recognition_high_confidence then 'HIGH'::public.recognition_confidence_tier
    when top_confidence >= settings.recognition_medium_confidence then 'MEDIUM'::public.recognition_confidence_tier
    else 'LOW'::public.recognition_confidence_tier
  end
  from public.company_settings as settings
  where settings.company_id = target_company_id;
$$;

revoke all on function private.recognition_confidence_tier(uuid, integer, numeric)
from public, anon, authenticated;

create function public.record_recognition_event(p_record jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  company_value uuid;
  warehouse_value uuid;
  stock_take_value uuid;
  session_value uuid;
  idempotency_value uuid;
  selected_product_value uuid;
  provider_value text;
  model_value text;
  media_path_value text;
  captured_at_value timestamptz;
  selection_method_value public.recognition_selection_method := 'NO_SELECTION';
  normalized_candidates jsonb;
  confidence_value numeric;
  confidence_tier_value public.recognition_confidence_tier;
  existing_event public.recognition_events%rowtype;
  created_event_id uuid;
begin
  if not private.is_permanent_user() then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error',
      jsonb_build_object('code', 'unauthenticated', 'message', 'Authentication is required.'));
  end if;
  if jsonb_typeof(p_record) is distinct from 'object' then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error',
      jsonb_build_object('code', 'invalid_record', 'message', 'The recognition event must be a JSON object.'));
  end if;
  begin
    company_value := (p_record ->> 'company_id')::uuid;
    warehouse_value := (p_record ->> 'warehouse_id')::uuid;
    stock_take_value := (p_record ->> 'stock_take_id')::uuid;
    session_value := (p_record ->> 'stock_taker_session_id')::uuid;
    idempotency_value := (p_record ->> 'idempotency_key')::uuid;
    selected_product_value := nullif(p_record ->> 'selected_product_id', '')::uuid;
    captured_at_value := coalesce(nullif(p_record ->> 'captured_at', '')::timestamptz, now());
    if p_record ? 'selection_method' then
      selection_method_value := (p_record ->> 'selection_method')::public.recognition_selection_method;
    end if;
  exception when others then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error',
      jsonb_build_object('code', 'invalid_identity', 'message', 'Recognition event identity fields are invalid.'));
  end;
  if company_value is null or warehouse_value is null or stock_take_value is null
    or session_value is null or idempotency_value is null then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error',
      jsonb_build_object('code', 'invalid_identity', 'message', 'Recognition event identity fields are required.'));
  end if;

  provider_value := btrim(coalesce(p_record ->> 'provider', ''));
  model_value := btrim(coalesce(p_record ->> 'model', ''));
  media_path_value := nullif(btrim(coalesce(p_record ->> 'media_path', '')), '');
  if length(provider_value) not between 1 and 100 or length(model_value) not between 1 and 160 then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'invalid_provider', 'message', 'Provider and model are required.'));
  end if;

  perform pg_advisory_xact_lock(hashtextextended(idempotency_value::text, 0));
  select * into existing_event
  from public.recognition_events where idempotency_key = idempotency_value;
  if existing_event.id is not null then
    if existing_event.user_id <> actor_id then
      return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
        'error', jsonb_build_object('code', 'idempotency_conflict', 'message', 'The idempotency key belongs to another recognition event.'));
    end if;
    return jsonb_build_object(
      'success', true, 'acknowledged', true, 'existing', true,
      'idempotency_key', idempotency_value, 'recognition_event_id', existing_event.id,
      'confidence', existing_event.confidence, 'confidence_tier', existing_event.confidence_tier,
      'candidates', existing_event.candidate_products,
      'selected_product_id', existing_event.selected_product_id
    );
  end if;

  if not exists (
    select 1
    from public.stock_taker_sessions as session
    join public.stock_takes as stock_take
      on stock_take.id = session.stock_take_id
      and stock_take.company_id = session.company_id
      and stock_take.warehouse_id = session.warehouse_id
    where session.id = session_value
      and session.company_id = company_value
      and session.warehouse_id = warehouse_value
      and session.stock_take_id = stock_take_value
      and session.user_id = actor_id
      and session.status = 'ACTIVE'
      and stock_take.status = 'ACTIVE'
  ) then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'recognition_closed', 'message', 'The active stock-taker session or stock take is no longer available.'));
  end if;

  begin
    normalized_candidates := private.normalize_recognition_candidates(
      company_value, coalesce(p_record -> 'candidates', '[]'::jsonb)
    );
  exception when sqlstate '22023' then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'invalid_candidates', 'message', sqlerrm));
  end;
  confidence_value := nullif(normalized_candidates #>> '{0,confidence}', '')::numeric;
  confidence_tier_value := private.recognition_confidence_tier(
    company_value, jsonb_array_length(normalized_candidates), confidence_value
  );

  if selected_product_value is not null and not exists (
    select 1 from public.products
    where id = selected_product_value and company_id = company_value and status = 'active'
  ) then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'product_unavailable', 'message', 'The selected product is not active in this company.'));
  end if;
  if (selected_product_value is null) <> (selection_method_value = 'NO_SELECTION') then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'invalid_selection', 'message', 'Selection method and selected product must be supplied together.'));
  end if;
  if selection_method_value in ('AUTO_PRESELECT', 'CANDIDATE_CONFIRMATION')
    and not exists (
      select 1 from jsonb_array_elements(normalized_candidates) as candidate
      where (candidate ->> 'product_id')::uuid = selected_product_value
    ) then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'invalid_selection', 'message', 'Candidate confirmation must select a returned candidate.'));
  end if;
  if media_path_value is not null and media_path_value not like actor_id::text || '/' || idempotency_value::text || '/%' then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'invalid_media_path', 'message', 'Recognition media path does not belong to this event.'));
  end if;

  insert into public.recognition_events (
    idempotency_key, company_id, warehouse_id, stock_take_id,
    stock_taker_session_id, user_id, provider, model, confidence,
    confidence_tier, candidate_products, selected_product_id, selection_method,
    media_bucket, media_path, media_expires_at, media_status, next_cleanup_at,
    captured_at, selected_at
  ) values (
    idempotency_value, company_value, warehouse_value, stock_take_value,
    session_value, actor_id, provider_value, model_value, confidence_value,
    confidence_tier_value, normalized_candidates, selected_product_value, selection_method_value,
    case when media_path_value is null then null else 'recognition-media' end,
    media_path_value,
    case when media_path_value is null then null else least(captured_at_value + interval '48 hours', now() + interval '48 hours') end,
    case when media_path_value is null then 'NOT_STORED'::public.recognition_media_status else 'PENDING'::public.recognition_media_status end,
    case when media_path_value is null then null else now() end,
    captured_at_value,
    case when selected_product_value is null then null else now() end
  )
  returning id into created_event_id;

  return jsonb_build_object(
    'success', true, 'acknowledged', true, 'existing', false,
    'idempotency_key', idempotency_value, 'recognition_event_id', created_event_id,
    'confidence', confidence_value, 'confidence_tier', confidence_tier_value,
    'candidates', normalized_candidates, 'selected_product_id', selected_product_value
  );
end;
$$;

create function public.sync_recognition_events_batch(p_records jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  record_value jsonb;
  result_value jsonb;
  results jsonb := '[]'::jsonb;
  acknowledged_count integer := 0;
  failed_count integer := 0;
begin
  if jsonb_typeof(p_records) is distinct from 'array' then
    return jsonb_build_object('success', false, 'results', results, 'totals',
      jsonb_build_object('total', 0, 'acknowledged', 0, 'failed', 0),
      'error', jsonb_build_object('code', 'invalid_batch', 'message', 'Records must be a JSON array.'));
  end if;
  if jsonb_array_length(p_records) > 100 then
    return jsonb_build_object('success', false, 'results', results, 'totals',
      jsonb_build_object('total', jsonb_array_length(p_records), 'acknowledged', 0, 'failed', jsonb_array_length(p_records)),
      'error', jsonb_build_object('code', 'batch_too_large', 'message', 'A recognition sync batch may contain at most 100 records.'));
  end if;
  for record_value in select value from jsonb_array_elements(p_records)
  loop
    result_value := public.record_recognition_event(record_value);
    results := results || jsonb_build_array(result_value);
    if coalesce((result_value ->> 'acknowledged')::boolean, false) then
      acknowledged_count := acknowledged_count + 1;
    else
      failed_count := failed_count + 1;
    end if;
  end loop;
  return jsonb_build_object(
    'success', failed_count = 0,
    'results', results,
    'totals', jsonb_build_object(
      'total', jsonb_array_length(p_records),
      'acknowledged', acknowledged_count,
      'failed', failed_count
    )
  );
end;
$$;

create function public.confirm_recognition_selection(
  p_recognition_event_id uuid,
  p_product_id uuid,
  p_selection_method public.recognition_selection_method
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  event_row public.recognition_events%rowtype;
begin
  if not private.is_permanent_user() then
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'unauthenticated', 'message', 'Authentication is required.'));
  end if;
  select * into event_row
  from public.recognition_events where id = p_recognition_event_id for update;
  if event_row.id is null or event_row.user_id <> actor_id then
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'event_unavailable', 'message', 'Recognition event is not available.'));
  end if;
  if event_row.selected_product_id is not null then
    if event_row.selected_product_id = p_product_id and event_row.selection_method = p_selection_method then
      return jsonb_build_object('success', true, 'existing', true, 'recognition_event_id', event_row.id);
    end if;
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'selection_locked', 'message', 'The recognition selection is already locked.'));
  end if;
  if p_selection_method not in ('AUTO_PRESELECT', 'CANDIDATE_CONFIRMATION', 'MANUAL_SEARCH') then
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'invalid_selection', 'message', 'A confirming selection method is required.'));
  end if;
  if not exists (
    select 1 from public.products
    where id = p_product_id and company_id = event_row.company_id and status = 'active'
  ) then
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'product_unavailable', 'message', 'The selected product is not active in this company.'));
  end if;
  if p_selection_method in ('AUTO_PRESELECT', 'CANDIDATE_CONFIRMATION')
    and not exists (
      select 1 from jsonb_array_elements(event_row.candidate_products) as candidate
      where (candidate ->> 'product_id')::uuid = p_product_id
    ) then
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'invalid_selection', 'message', 'Select one of the recognition candidates or use manual search.'));
  end if;
  if not exists (
    select 1 from public.stock_taker_sessions as session
    join public.stock_takes as stock_take
      on stock_take.id = session.stock_take_id
      and stock_take.company_id = session.company_id
      and stock_take.warehouse_id = session.warehouse_id
    where session.id = event_row.stock_taker_session_id
      and session.user_id = actor_id and session.status = 'ACTIVE'
      and stock_take.status = 'ACTIVE'
  ) then
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'recognition_closed', 'message', 'The stock take is no longer available.'));
  end if;
  perform set_config('app.recognition_event_mutation', 'allowed', true);
  update public.recognition_events
  set selected_product_id = p_product_id,
      selection_method = p_selection_method,
      selected_at = now()
  where id = event_row.id;
  return jsonb_build_object(
    'success', true, 'existing', false, 'recognition_event_id', event_row.id,
    'selected_product_id', p_product_id, 'selection_method', p_selection_method
  );
end;
$$;

create function public.claim_recognition_media_cleanup(p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare claimed jsonb;
begin
  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'Cleanup limit must be between 1 and 500.' using errcode = '22023';
  end if;
  perform set_config('app.recognition_event_mutation', 'allowed', true);
  with due as (
    select id
    from public.recognition_events
    where media_status in ('PENDING', 'FAILED') and next_cleanup_at <= now()
    order by next_cleanup_at, created_at
    for update skip locked
    limit p_limit
  ), updated as (
    update public.recognition_events as event
    set cleanup_attempts = event.cleanup_attempts + 1,
        last_cleanup_attempt_at = now(),
        next_cleanup_at = now() + interval '5 minutes'
    from due
    where event.id = due.id
    returning event.id, event.media_bucket, event.media_path, event.media_expires_at,
      event.cleanup_attempts
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'recognition_event_id', id,
    'bucket', media_bucket,
    'path', media_path,
    'expires_at', media_expires_at,
    'attempt', cleanup_attempts
  )), '[]'::jsonb)
  into claimed
  from updated;
  return jsonb_build_object('success', true, 'items', claimed);
end;
$$;

create function public.complete_recognition_media_cleanup(
  p_recognition_event_id uuid,
  p_success boolean,
  p_error text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare event_row public.recognition_events%rowtype;
declare error_value text;
begin
  select * into event_row
  from public.recognition_events where id = p_recognition_event_id for update;
  if event_row.id is null then
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'event_unavailable', 'message', 'Recognition event is not available.'));
  end if;
  if event_row.media_status = 'NOT_STORED' then
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'media_not_stored', 'message', 'This event has no stored media.'));
  end if;
  if event_row.media_status = 'DELETED' then
    return jsonb_build_object('success', true, 'existing', true, 'recognition_event_id', event_row.id);
  end if;
  perform set_config('app.recognition_event_mutation', 'allowed', true);
  if p_success then
    update public.recognition_events
    set media_status = 'DELETED', next_cleanup_at = null,
        cleanup_error = null, cleaned_at = now()
    where id = event_row.id;
  else
    error_value := left(coalesce(nullif(btrim(p_error), ''), 'Recognition media deletion failed.'), 1000);
    update public.recognition_events
    set media_status = 'FAILED', cleanup_error = error_value,
        next_cleanup_at = least(
          media_expires_at,
          now() + make_interval(secs => least(3600, 30 * (2 ^ least(cleanup_attempts, 7))::integer))
        )
    where id = event_row.id;
    insert into public.audit_logs (
      company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
    ) values (
      event_row.company_id, event_row.warehouse_id, null,
      'recognition_media.cleanup_failed', 'recognition_event', event_row.id,
      jsonb_build_object(
        'attempt', event_row.cleanup_attempts,
        'media_expires_at', event_row.media_expires_at,
        'error', error_value
      )
    );
  end if;
  return jsonb_build_object(
    'success', true, 'existing', false, 'recognition_event_id', event_row.id,
    'media_status', case when p_success then 'DELETED' else 'FAILED' end
  );
end;
$$;
