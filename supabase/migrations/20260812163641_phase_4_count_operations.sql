create function private.parse_count_quantity(raw_value jsonb)
returns table (parsed_value bigint, is_valid boolean)
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare candidate numeric;
begin
  if raw_value is null or jsonb_typeof(raw_value) <> 'number' then
    return query select null::bigint, false;
    return;
  end if;
  begin
    candidate := (raw_value #>> '{}')::numeric;
  exception when others then
    return query select null::bigint, false;
    return;
  end;
  if candidate < 0 or trunc(candidate) <> candidate or candidate > 9223372036854775807 then
    return query select null::bigint, false;
    return;
  end if;
  return query select candidate::bigint, true;
end;
$$;

revoke all on function private.parse_count_quantity(jsonb)
from public, anon, authenticated;

create function public.submit_count(p_record jsonb)
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
  product_value uuid;
  idempotency_value uuid;
  count_type_value public.count_type;
  pallets_value bigint;
  layers_value bigint;
  cases_value bigint;
  units_value bigint;
  duration_value integer;
  quantity_valid boolean;
  product_row public.products%rowtype;
  existing_count public.counts%rowtype;
  created_count_id uuid;
  calculated_total bigint;
  duplicate_value boolean;
begin
  if not private.is_permanent_user() then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error',
      jsonb_build_object('code', 'unauthenticated', 'message', 'Authentication is required.'));
  end if;
  if jsonb_typeof(p_record) is distinct from 'object' then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error',
      jsonb_build_object('code', 'invalid_record', 'message', 'The count record must be a JSON object.'));
  end if;

  begin
    company_value := (p_record ->> 'company_id')::uuid;
    warehouse_value := (p_record ->> 'warehouse_id')::uuid;
    stock_take_value := (p_record ->> 'stock_take_id')::uuid;
    session_value := (p_record ->> 'stock_taker_session_id')::uuid;
    product_value := (p_record ->> 'product_id')::uuid;
    idempotency_value := (p_record ->> 'idempotency_key')::uuid;
    count_type_value := (p_record ->> 'count_type')::public.count_type;
  exception when others then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error',
      jsonb_build_object('code', 'invalid_identity', 'message', 'Count identity fields are invalid.'));
  end;
  if company_value is null or warehouse_value is null or stock_take_value is null
    or session_value is null or product_value is null or idempotency_value is null
    or count_type_value is null then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error',
      jsonb_build_object('code', 'invalid_identity', 'message', 'Count identity fields are required.'));
  end if;

  select parsed_value, is_valid into pallets_value, quantity_valid
  from private.parse_count_quantity(p_record -> 'pallets');
  if not quantity_valid then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'invalid_quantity', 'field', 'pallets', 'message', 'Pallets must be a non-negative whole number.'));
  end if;
  select parsed_value, is_valid into layers_value, quantity_valid
  from private.parse_count_quantity(p_record -> 'layers');
  if not quantity_valid then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'invalid_quantity', 'field', 'layers', 'message', 'Layers must be a non-negative whole number.'));
  end if;
  select parsed_value, is_valid into cases_value, quantity_valid
  from private.parse_count_quantity(p_record -> 'cases');
  if not quantity_valid then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'invalid_quantity', 'field', 'cases', 'message', 'Cases must be a non-negative whole number.'));
  end if;
  select parsed_value, is_valid into units_value, quantity_valid
  from private.parse_count_quantity(p_record -> 'units');
  if not quantity_valid then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'invalid_quantity', 'field', 'units', 'message', 'Units must be a non-negative whole number.'));
  end if;

  begin
    duration_value := nullif(p_record ->> 'duration_ms', '')::integer;
    if duration_value is not null and duration_value < 0 then raise numeric_value_out_of_range; end if;
  exception when others then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'invalid_duration', 'message', 'Duration must be a non-negative integer.'));
  end;

  perform pg_advisory_xact_lock(hashtextextended(idempotency_value::text, 0));
  select * into existing_count from public.counts where idempotency_key = idempotency_value;
  if existing_count.id is not null then
    if existing_count.submitted_by <> actor_id then
      return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
        'error', jsonb_build_object('code', 'idempotency_conflict', 'message', 'The idempotency key belongs to another count.'));
    end if;
    return jsonb_build_object(
      'success', true, 'acknowledged', true, 'existing', true,
      'idempotency_key', idempotency_value, 'count_id', existing_count.id,
      'total_units', existing_count.total_units,
      'duplicate', exists (select 1 from public.count_flags where count_id = existing_count.id)
    );
  end if;

  if not exists (
    select 1 from public.stock_taker_sessions as session
    join public.stock_takes as stock_take
      on stock_take.id = session.stock_take_id
      and stock_take.company_id = session.company_id
      and stock_take.warehouse_id = session.warehouse_id
    where session.id = session_value and session.company_id = company_value
      and session.warehouse_id = warehouse_value and session.stock_take_id = stock_take_value
      and session.user_id = actor_id and session.status = 'ACTIVE'
      and stock_take.status = 'ACTIVE'
  ) then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'counting_closed', 'message', 'The active stock-taker session or stock take is no longer countable.'));
  end if;

  select * into product_row from public.products
  where id = product_value and company_id = company_value and status = 'active';
  if product_row.id is null then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'product_unavailable', 'message', 'The selected product is not active in this company.'));
  end if;
  if pallets_value > 0 and (product_row.cases_per_pallet is null or product_row.units_per_case is null) then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'missing_packaging', 'field', 'pallets', 'message', 'Add cases per pallet and units per case before counting pallets.'));
  end if;
  if layers_value > 0 and (product_row.cases_per_layer is null or product_row.units_per_case is null) then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'missing_packaging', 'field', 'layers', 'message', 'Add cases per layer and units per case before counting layers.'));
  end if;
  if cases_value > 0 and product_row.units_per_case is null then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'missing_packaging', 'field', 'cases', 'message', 'Add units per case before counting cases.'));
  end if;

  begin
    calculated_total :=
      pallets_value * coalesce(product_row.cases_per_pallet, 0)::bigint * coalesce(product_row.units_per_case, 0)::bigint
      + layers_value * coalesce(product_row.cases_per_layer, 0)::bigint * coalesce(product_row.units_per_case, 0)::bigint
      + cases_value * coalesce(product_row.units_per_case, 0)::bigint
      + units_value;
  exception when numeric_value_out_of_range then
    return jsonb_build_object('success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
      'error', jsonb_build_object('code', 'quantity_overflow', 'message', 'The calculated unit total is too large.'));
  end;

  perform pg_advisory_xact_lock(hashtextextended(
    stock_take_value::text || ':' || product_value::text || ':' || count_type_value::text, 0
  ));
  duplicate_value := exists (
    select 1 from public.counts
    where stock_take_id = stock_take_value and product_id = product_value
      and count_type = count_type_value
  );

  insert into public.counts (
    company_id, warehouse_id, stock_take_id, stock_taker_session_id, product_id,
    submitted_by, count_type, pallets, layers, cases, units, total_units,
    duration_ms, idempotency_key
  ) values (
    company_value, warehouse_value, stock_take_value, session_value, product_value,
    actor_id, count_type_value, pallets_value, layers_value, cases_value, units_value,
    calculated_total, duration_value, idempotency_value
  ) returning id into created_count_id;

  if duplicate_value then
    insert into public.count_flags (
      company_id, warehouse_id, stock_take_id, count_id, flag_type
    ) values (
      company_value, warehouse_value, stock_take_value, created_count_id,
      'DUPLICATE_PRODUCT_COUNT_TYPE'
    );
  end if;

  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    company_value, warehouse_value, actor_id, 'count.submitted', 'count', created_count_id,
    jsonb_build_object('stock_take_id', stock_take_value, 'product_id', product_value,
      'count_type', count_type_value, 'total_units', calculated_total,
      'duplicate', duplicate_value, 'idempotency_key', idempotency_value)
  );

  return jsonb_build_object(
    'success', true, 'acknowledged', true, 'existing', false,
    'idempotency_key', idempotency_value, 'count_id', created_count_id,
    'total_units', calculated_total, 'duplicate', duplicate_value
  );
exception when others then
  return jsonb_build_object(
    'success', false, 'acknowledged', false, 'idempotency_key', idempotency_value,
    'error', jsonb_build_object('code', sqlstate, 'message', 'The count could not be submitted safely.')
  );
end;
$$;

create function public.sync_counts_batch(p_records jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_record jsonb;
  record_result jsonb;
  results jsonb := '[]'::jsonb;
  acknowledged_count integer := 0;
  failed_count integer := 0;
begin
  if not private.is_permanent_user() then
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'unauthenticated', 'message', 'Authentication is required.'));
  end if;
  if jsonb_typeof(p_records) is distinct from 'array' then
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'invalid_batch', 'message', 'Count records must be a JSON array.'));
  end if;
  if jsonb_array_length(p_records) > 100 then
    return jsonb_build_object('success', false, 'error',
      jsonb_build_object('code', 'batch_too_large', 'message', 'A count sync batch may contain at most 100 records.'));
  end if;

  for source_record in select value from jsonb_array_elements(p_records)
  loop
    begin
      record_result := public.submit_count(source_record);
    exception when others then
      record_result := jsonb_build_object(
        'success', false, 'acknowledged', false,
        'idempotency_key', source_record ->> 'idempotency_key',
        'error', jsonb_build_object('code', sqlstate, 'message', 'This record could not be synchronized.')
      );
    end;
    results := results || jsonb_build_array(record_result);
    if coalesce((record_result ->> 'acknowledged')::boolean, false) then
      acknowledged_count := acknowledged_count + 1;
    else
      failed_count := failed_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'success', true, 'results', results,
    'totals', jsonb_build_object('total', jsonb_array_length(p_records),
      'acknowledged', acknowledged_count, 'failed', failed_count)
  );
end;
$$;

comment on function public.submit_count(jsonb) is
  'Idempotent immutable initial-count submission. Server recalculates units and preserves duplicates.';
comment on function public.sync_counts_batch(jsonb) is
  'Per-record acknowledged count sync. Failed records do not roll back or hide successful records.';

revoke execute on function public.submit_count(jsonb) from public, anon;
revoke execute on function public.sync_counts_batch(jsonb) from public, anon;
grant execute on function public.submit_count(jsonb) to authenticated;
grant execute on function public.sync_counts_batch(jsonb) to authenticated;

create or replace function public.get_stock_taker_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  context_result jsonb;
  available_result jsonb;
begin
  if not private.is_permanent_user() then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'unauthenticated', 'message', 'Authentication is required.'
    ));
  end if;

  select jsonb_build_object(
    'id', session.id, 'status', session.status,
    'started_at', session.started_at, 'last_active_at', session.last_active_at,
    'company', jsonb_build_object('id', company.id, 'name', company.name),
    'warehouse', jsonb_build_object(
      'id', warehouse.id, 'code', warehouse.warehouse_code, 'name', warehouse.name
    ),
    'stock_take', jsonb_build_object('id', stock_take.id, 'status', stock_take.status)
  ) into context_result
  from public.stock_taker_sessions as session
  join public.companies as company on company.id = session.company_id
  join public.warehouses as warehouse
    on warehouse.id = session.warehouse_id and warehouse.company_id = session.company_id
  join public.stock_takes as stock_take on stock_take.id = session.stock_take_id
  where session.user_id = actor_id and session.status = 'ACTIVE';

  select coalesce(jsonb_agg(jsonb_build_object(
    'company', jsonb_build_object('id', company.id, 'name', company.name),
    'warehouse', jsonb_build_object(
      'id', warehouse.id, 'code', warehouse.warehouse_code, 'name', warehouse.name
    ),
    'stock_take', jsonb_build_object('id', stock_take.id, 'status', stock_take.status)
  ) order by warehouse.name), '[]'::jsonb) into available_result
  from public.warehouse_memberships as allocation
  join public.company_memberships as membership
    on membership.company_id = allocation.company_id
    and membership.user_id = allocation.user_id
    and membership.role = allocation.role
  join public.profiles as profile on profile.user_id = allocation.user_id
  join public.companies as company on company.id = allocation.company_id
  join public.warehouses as warehouse
    on warehouse.id = allocation.warehouse_id and warehouse.company_id = allocation.company_id
  join public.stock_takes as stock_take
    on stock_take.company_id = allocation.company_id
    and stock_take.warehouse_id = allocation.warehouse_id
    and stock_take.status in ('ACTIVE', 'RECOUNT')
  where allocation.user_id = actor_id and allocation.role = 'stock_taker'
    and allocation.status = 'active' and membership.status = 'active'
    and profile.status = 'active' and warehouse.status = 'active';

  return jsonb_build_object(
    'success', true, 'session', context_result, 'available_contexts', available_result
  );
end;
$$;

comment on function public.get_stock_taker_context() is
  'Stock-taker-safe active and available warehouse context. It returns no SOH, variance, snapshot, or management metrics.';
