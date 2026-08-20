create function private.effective_variance_threshold(
  target_company_id uuid,
  target_warehouse_id uuid,
  target_product_id uuid
)
returns table (
  threshold_units bigint,
  threshold_source public.variance_threshold_source
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    case
      when product_setting.variance_threshold_active then product_setting.variance_threshold_units
      when warehouse_setting.variance_threshold_active then warehouse_setting.variance_threshold_units
      else company_setting.default_variance_threshold_units
    end,
    case
      when product_setting.variance_threshold_active then 'PRODUCT'::public.variance_threshold_source
      when warehouse_setting.variance_threshold_active then 'WAREHOUSE'::public.variance_threshold_source
      else 'COMPANY'::public.variance_threshold_source
    end
  from public.company_settings as company_setting
  left join public.warehouse_settings as warehouse_setting
    on warehouse_setting.company_id = company_setting.company_id
    and warehouse_setting.warehouse_id = target_warehouse_id
  left join public.product_warehouse_settings as product_setting
    on product_setting.company_id = company_setting.company_id
    and product_setting.warehouse_id = target_warehouse_id
    and product_setting.product_id = target_product_id
  where company_setting.company_id = target_company_id;
$$;

create function private.stock_take_variances(target_stock_take_id uuid)
returns table (
  company_id uuid,
  warehouse_id uuid,
  stock_take_id uuid,
  product_id uuid,
  product_code text,
  product_name text,
  brand_id uuid,
  brand_name text,
  snapshot_units bigint,
  initial_physical_units bigint,
  physical_units bigint,
  signed_variance_units bigint,
  absolute_variance_units bigint,
  effective_threshold_units bigint,
  threshold_source public.variance_threshold_source,
  recount_status public.recount_task_status,
  duplicate_flag_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with initial_counts as (
    select count_row.stock_take_id, count_row.product_id, sum(count_row.total_units)::bigint as total_units
    from public.counts as count_row
    where count_row.stock_take_id = target_stock_take_id
    group by count_row.stock_take_id, count_row.product_id
  ), latest_recount as (
    select distinct on (recount_count.stock_take_id, recount_count.product_id)
      recount_count.stock_take_id, recount_count.product_id, recount_count.total_units
    from public.recount_counts as recount_count
    where recount_count.stock_take_id = target_stock_take_id
    order by recount_count.stock_take_id, recount_count.product_id, recount_count.submitted_at desc, recount_count.id desc
  ), latest_task as (
    select distinct on (task.stock_take_id, task.product_id)
      task.stock_take_id, task.product_id, task.status
    from public.recount_tasks as task
    where task.stock_take_id = target_stock_take_id
    order by task.stock_take_id, task.product_id, task.created_at desc, task.id desc
  ), duplicate_flags as (
    select flag.stock_take_id, count_row.product_id, count(*)::integer as flag_count
    from public.count_flags as flag
    join public.counts as count_row on count_row.id = flag.count_id
    where flag.stock_take_id = target_stock_take_id
      and flag.flag_type = 'DUPLICATE_PRODUCT_COUNT_TYPE'
      and flag.status = 'OPEN'
    group by flag.stock_take_id, count_row.product_id
  )
  select
    snapshot.company_id,
    snapshot.warehouse_id,
    snapshot.stock_take_id,
    snapshot.product_id,
    product.product_code,
    product.name,
    product.brand_id,
    brand.name,
    snapshot.quantity_on_hand,
    coalesce(initial_count.total_units, 0),
    coalesce(recount.total_units, initial_count.total_units, 0),
    coalesce(recount.total_units, initial_count.total_units, 0) - snapshot.quantity_on_hand,
    abs(coalesce(recount.total_units, initial_count.total_units, 0) - snapshot.quantity_on_hand),
    threshold.threshold_units,
    threshold.threshold_source,
    task.status,
    coalesce(duplicate.flag_count, 0)
  from public.stock_snapshot_lines as snapshot
  join public.products as product
    on product.id = snapshot.product_id and product.company_id = snapshot.company_id
  left join public.brands as brand
    on brand.id = product.brand_id and brand.company_id = product.company_id
  left join initial_counts as initial_count
    on initial_count.stock_take_id = snapshot.stock_take_id and initial_count.product_id = snapshot.product_id
  left join latest_recount as recount
    on recount.stock_take_id = snapshot.stock_take_id and recount.product_id = snapshot.product_id
  left join latest_task as task
    on task.stock_take_id = snapshot.stock_take_id and task.product_id = snapshot.product_id
  left join duplicate_flags as duplicate
    on duplicate.stock_take_id = snapshot.stock_take_id and duplicate.product_id = snapshot.product_id
  cross join lateral private.effective_variance_threshold(
    snapshot.company_id, snapshot.warehouse_id, snapshot.product_id
  ) as threshold
  where snapshot.stock_take_id = target_stock_take_id;
$$;

revoke all on function private.effective_variance_threshold(uuid, uuid, uuid)
from public, anon, authenticated;
revoke all on function private.stock_take_variances(uuid)
from public, anon, authenticated;

create function public.get_manager_progress(
  p_company_id uuid, p_warehouse_id uuid, p_stock_take_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  snapshot_products integer;
  covered_products integer;
  initial_count_records integer;
  completed_recounts integer;
  open_duplicate_flags integer;
  open_recounts integer;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Manager progress requires allocated management access.'
    ));
  end if;
  if not exists (
    select 1 from public.stock_takes
    where id = p_stock_take_id and company_id = p_company_id and warehouse_id = p_warehouse_id
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_found', 'message', 'The stock take was not found.'
    ));
  end if;

  select count(distinct line.product_id)::integer into snapshot_products
  from public.stock_snapshot_lines as line where line.stock_take_id = p_stock_take_id;
  select count(distinct count_row.product_id)::integer into covered_products
  from public.counts as count_row where count_row.stock_take_id = p_stock_take_id;
  select count(*)::integer into initial_count_records
  from public.counts as count_row where count_row.stock_take_id = p_stock_take_id;
  select count(*)::integer into completed_recounts
  from public.recount_tasks as task where task.stock_take_id = p_stock_take_id and task.status = 'COMPLETED';
  select count(*)::integer into open_recounts
  from public.recount_tasks as task where task.stock_take_id = p_stock_take_id and task.status <> 'COMPLETED';
  select count(*)::integer into open_duplicate_flags
  from public.count_flags as flag
  where flag.stock_take_id = p_stock_take_id and flag.status = 'OPEN';

  return jsonb_build_object(
    'success', true,
    'stock_take_id', p_stock_take_id,
    'snapshot_products', snapshot_products,
    'covered_products', least(covered_products, snapshot_products),
    'progress_percent', case when snapshot_products = 0 then 0
      else least(100, round((covered_products::numeric * 100) / snapshot_products, 2)) end,
    'initial_count_records', initial_count_records,
    'completed_recounts', completed_recounts,
    'open_recounts', open_recounts,
    'open_duplicate_flags', open_duplicate_flags
  );
end;
$$;

create function public.get_variances(
  p_company_id uuid, p_warehouse_id uuid, p_stock_take_id uuid,
  p_minimum_absolute_variance_units bigint default null,
  p_brand_id uuid default null,
  p_product_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result_rows jsonb;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Variance access requires allocated management access.'
    ));
  end if;
  if p_minimum_absolute_variance_units is not null and p_minimum_absolute_variance_units < 0 then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_threshold', 'message', 'The variance filter must be a non-negative whole number.'
    ));
  end if;
  if not exists (
    select 1 from public.stock_takes
    where id = p_stock_take_id and company_id = p_company_id and warehouse_id = p_warehouse_id
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_found', 'message', 'The stock take was not found.'
    ));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'product_id', variance.product_id,
    'product_code', variance.product_code,
    'product_name', variance.product_name,
    'brand_id', variance.brand_id,
    'brand_name', variance.brand_name,
    'snapshot_units', variance.snapshot_units,
    'initial_physical_units', variance.initial_physical_units,
    'physical_units', variance.physical_units,
    'signed_variance_units', variance.signed_variance_units,
    'absolute_variance_units', variance.absolute_variance_units,
    'effective_threshold_units', variance.effective_threshold_units,
    'threshold_source', variance.threshold_source,
    'recount_required', variance.absolute_variance_units > variance.effective_threshold_units,
    'recount_status', variance.recount_status,
    'open_duplicate_flags', variance.duplicate_flag_count
  ) order by variance.absolute_variance_units desc, variance.product_code), '[]'::jsonb)
  into result_rows
  from private.stock_take_variances(p_stock_take_id) as variance
  where variance.company_id = p_company_id and variance.warehouse_id = p_warehouse_id
    and (p_minimum_absolute_variance_units is null
      or variance.absolute_variance_units >= p_minimum_absolute_variance_units)
    and (p_brand_id is null or variance.brand_id = p_brand_id)
    and (p_product_id is null or variance.product_id = p_product_id);

  return jsonb_build_object('success', true, 'stock_take_id', p_stock_take_id, 'variances', result_rows);
end;
$$;

comment on function public.get_manager_progress(uuid, uuid, uuid) is
  'Distinct snapshot-product progress capped at 100 percent; Bulk/Pick Face and duplicate records cannot inflate it.';
comment on function public.get_variances(uuid, uuid, uuid, bigint, uuid, uuid) is
  'Management-only derived snapshot versus effective physical results with layered threshold precedence.';

create function public.set_variance_threshold(
  p_company_id uuid,
  p_warehouse_id uuid,
  p_threshold_units bigint,
  p_active boolean default true,
  p_product_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor_id uuid := (select auth.uid());
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Threshold changes require an allocated Admin or authorised Super Admin.'
    ));
  end if;
  if p_threshold_units is null or p_threshold_units < 0 then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_threshold', 'message', 'Threshold units must be a non-negative whole number.'
    ));
  end if;
  if p_product_id is null then
    insert into public.warehouse_settings (
      warehouse_id, company_id, variance_threshold_units, variance_threshold_active, updated_by
    ) values (p_warehouse_id, p_company_id, p_threshold_units, p_active, actor_id)
    on conflict (warehouse_id) do update set
      variance_threshold_units = excluded.variance_threshold_units,
      variance_threshold_active = excluded.variance_threshold_active,
      updated_by = excluded.updated_by;
  else
    if not exists (
      select 1 from public.products
      where id = p_product_id and company_id = p_company_id
    ) then
      return jsonb_build_object('success', false, 'error', jsonb_build_object(
        'code', 'product_not_found', 'message', 'The product was not found in this company.'
      ));
    end if;
    insert into public.product_warehouse_settings (
      company_id, warehouse_id, product_id,
      variance_threshold_units, variance_threshold_active, updated_by
    ) values (
      p_company_id, p_warehouse_id, p_product_id,
      p_threshold_units, p_active, actor_id
    ) on conflict (company_id, warehouse_id, product_id) do update set
      variance_threshold_units = excluded.variance_threshold_units,
      variance_threshold_active = excluded.variance_threshold_active,
      updated_by = excluded.updated_by;
  end if;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'variance_threshold.changed',
    case when p_product_id is null then 'warehouse' else 'product' end,
    coalesce(p_product_id, p_warehouse_id),
    jsonb_build_object('product_id', p_product_id, 'threshold_units', p_threshold_units, 'active', p_active)
  );
  return jsonb_build_object(
    'success', true, 'scope', case when p_product_id is null then 'WAREHOUSE' else 'PRODUCT' end,
    'threshold_units', p_threshold_units, 'active', p_active
  );
end;
$$;

create function public.set_company_variance_threshold(
  p_company_id uuid, p_threshold_units bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor_id uuid := (select auth.uid());
begin
  if not private.can_access_company(
    p_company_id, array['admin']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Company threshold changes require an Admin or authorised Super Admin.'
    ));
  end if;
  if p_threshold_units is null or p_threshold_units < 0 then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_threshold', 'message', 'Threshold units must be a non-negative whole number.'
    ));
  end if;
  update public.company_settings set
    default_variance_threshold_units = p_threshold_units
  where company_id = p_company_id;
  insert into public.audit_logs (
    company_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, actor_id, 'variance_threshold.changed', 'company', p_company_id,
    jsonb_build_object('threshold_units', p_threshold_units)
  );
  return jsonb_build_object(
    'success', true, 'scope', 'COMPANY', 'threshold_units', p_threshold_units, 'active', true
  );
end;
$$;

create function private.enforce_count_flag_resolution()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'count_flags rows are immutable.' using errcode = '55000';
  end if;
  if current_setting('app.phase_6_resolve_count_flag', true) is distinct from 'on'
    or old.id is distinct from new.id
    or old.company_id is distinct from new.company_id
    or old.warehouse_id is distinct from new.warehouse_id
    or old.stock_take_id is distinct from new.stock_take_id
    or old.count_id is distinct from new.count_id
    or old.flag_type is distinct from new.flag_type
    or old.created_at is distinct from new.created_at
    or old.status <> 'OPEN' or new.status <> 'RESOLVED'
    or new.resolved_at is null or new.resolved_by is null
    or nullif(btrim(new.resolution_note), '') is null then
    raise exception 'count_flags rows are immutable.'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

drop trigger count_flags_reject_update_or_delete on public.count_flags;
create trigger count_flags_enforce_resolution
before update or delete on public.count_flags
for each row execute function private.enforce_count_flag_resolution();
revoke all on function private.enforce_count_flag_resolution()
from public, anon, authenticated;

create function public.resolve_count_flag(p_count_flag_id uuid, p_resolution_note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  flag_row public.count_flags%rowtype;
begin
  if nullif(btrim(p_resolution_note), '') is null then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'resolution_note_required', 'message', 'A management resolution note is required.'
    ));
  end if;
  select * into flag_row from public.count_flags where id = p_count_flag_id for update;
  if flag_row.id is null then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'flag_not_found', 'message', 'The count flag was not found.'
    ));
  end if;
  if not private.can_access_warehouse(
    flag_row.company_id, flag_row.warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Flag resolution requires allocated management access.'
    ));
  end if;
  if flag_row.status = 'RESOLVED' then
    return jsonb_build_object('success', true, 'existing', true, 'count_flag_id', flag_row.id, 'status', flag_row.status);
  end if;
  perform set_config('app.phase_6_resolve_count_flag', 'on', true);
  update public.count_flags set
    status = 'RESOLVED', resolved_at = now(), resolved_by = actor_id,
    resolution_note = btrim(p_resolution_note)
  where id = flag_row.id;
  perform set_config('app.phase_6_resolve_count_flag', 'off', true);
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    flag_row.company_id, flag_row.warehouse_id, actor_id, 'count_flag.resolved',
    'count_flag', flag_row.id, jsonb_build_object('note', btrim(p_resolution_note))
  );
  return jsonb_build_object('success', true, 'existing', false, 'count_flag_id', flag_row.id, 'status', 'RESOLVED');
end;
$$;

create function public.create_recount_batch(
  p_company_id uuid,
  p_warehouse_id uuid,
  p_stock_take_id uuid,
  p_minimum_absolute_variance_units bigint default null,
  p_brand_id uuid default null,
  p_product_id uuid default null,
  p_assigned_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  stock_take_status public.stock_take_status;
  batch_id uuid;
  created_tasks integer;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Recount creation requires allocated management access.'
    ));
  end if;
  if p_minimum_absolute_variance_units is not null and p_minimum_absolute_variance_units < 0 then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_threshold', 'message', 'The batch filter must be a non-negative whole number.'
    ));
  end if;
  if p_assigned_user_id is not null and not exists (
    select 1 from public.warehouse_memberships as allocation
    join public.company_memberships as membership
      on membership.company_id = allocation.company_id
      and membership.user_id = allocation.user_id and membership.role = allocation.role
    join public.profiles as profile on profile.user_id = allocation.user_id
    where allocation.company_id = p_company_id and allocation.warehouse_id = p_warehouse_id
      and allocation.user_id = p_assigned_user_id and allocation.role = 'stock_taker'
      and allocation.status = 'active' and membership.status = 'active' and profile.status = 'active'
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'assignee_unavailable', 'message', 'The assigned stock taker is not active in this warehouse.'
    ));
  end if;

  select status into stock_take_status from public.stock_takes
  where id = p_stock_take_id and company_id = p_company_id and warehouse_id = p_warehouse_id
  for update;
  if not found then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_found', 'message', 'The stock take was not found.'
    ));
  end if;
  if stock_take_status not in ('ACTIVE', 'RECOUNT', 'REOPENED') then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_state', 'message', 'Recount work can be generated only after initial counting or a controlled reopen.'
    ));
  end if;

  insert into public.recount_batches (
    company_id, warehouse_id, stock_take_id, created_by, minimum_absolute_variance_units
  ) values (
    p_company_id, p_warehouse_id, p_stock_take_id, actor_id, p_minimum_absolute_variance_units
  ) returning id into batch_id;

  insert into public.recount_tasks (
    company_id, warehouse_id, stock_take_id, recount_batch_id,
    product_id, brand_id, source_physical_units, source_signed_variance_units,
    source_absolute_variance_units, effective_threshold_units, threshold_source,
    assigned_user_id, status
  )
  select
    variance.company_id, variance.warehouse_id, variance.stock_take_id, batch_id,
    variance.product_id, variance.brand_id, variance.physical_units, variance.signed_variance_units,
    variance.absolute_variance_units, variance.effective_threshold_units, variance.threshold_source,
    p_assigned_user_id,
    case when p_assigned_user_id is null then 'UNASSIGNED'::public.recount_task_status
      else 'ASSIGNED'::public.recount_task_status end
  from private.stock_take_variances(p_stock_take_id) as variance
  where variance.company_id = p_company_id and variance.warehouse_id = p_warehouse_id
    and variance.absolute_variance_units > variance.effective_threshold_units
    and (p_minimum_absolute_variance_units is null
      or variance.absolute_variance_units >= p_minimum_absolute_variance_units)
    and (p_brand_id is null or variance.brand_id = p_brand_id)
    and (p_product_id is null or variance.product_id = p_product_id)
  on conflict do nothing;
  get diagnostics created_tasks = row_count;

  if created_tasks = 0 then
    delete from public.recount_batches where id = batch_id;
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'no_recount_candidates', 'message', 'No unmatched variance lines require recount for these filters.'
    ));
  end if;

  if stock_take_status in ('ACTIVE', 'REOPENED') then
    update public.stock_takes set status = 'RECOUNT' where id = p_stock_take_id;
  end if;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'recount_batch.created', 'recount_batch', batch_id,
    jsonb_build_object('stock_take_id', p_stock_take_id, 'task_count', created_tasks,
      'brand_id', p_brand_id, 'product_id', p_product_id,
      'assigned_user_id', p_assigned_user_id,
      'minimum_absolute_variance_units', p_minimum_absolute_variance_units)
  );
  return jsonb_build_object(
    'success', true, 'recount_batch_id', batch_id, 'task_count', created_tasks,
    'stock_take_status', 'RECOUNT'
  );
exception when unique_violation then
  return jsonb_build_object('success', false, 'error', jsonb_build_object(
    'code', 'recount_conflict', 'message', 'Open recount work already exists for one or more selected products.'
  ));
end;
$$;

create function public.assign_recount_tasks(
  p_company_id uuid, p_warehouse_id uuid, p_recount_task_ids uuid[], p_assigned_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor_id uuid := (select auth.uid()); changed_count integer;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Recount assignment requires allocated management access.'
    ));
  end if;
  if coalesce(array_length(p_recount_task_ids, 1), 0) = 0 then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'tasks_required', 'message', 'Select at least one recount task.'
    ));
  end if;
  if p_assigned_user_id is not null and not exists (
    select 1 from public.warehouse_memberships as allocation
    join public.company_memberships as membership
      on membership.company_id = allocation.company_id
      and membership.user_id = allocation.user_id and membership.role = allocation.role
    join public.profiles as profile on profile.user_id = allocation.user_id
    where allocation.company_id = p_company_id and allocation.warehouse_id = p_warehouse_id
      and allocation.user_id = p_assigned_user_id and allocation.role = 'stock_taker'
      and allocation.status = 'active' and membership.status = 'active' and profile.status = 'active'
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'assignee_unavailable', 'message', 'The assigned stock taker is not active in this warehouse.'
    ));
  end if;
  update public.recount_tasks set
    assigned_user_id = p_assigned_user_id,
    status = case
      when p_assigned_user_id is null then 'UNASSIGNED'::public.recount_task_status
      else 'ASSIGNED'::public.recount_task_status
    end
  where company_id = p_company_id and warehouse_id = p_warehouse_id
    and id = any(p_recount_task_ids) and status in ('UNASSIGNED', 'ASSIGNED');
  get diagnostics changed_count = row_count;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'recount_tasks.assigned', 'recount_task',
    jsonb_build_object('task_ids', to_jsonb(p_recount_task_ids),
      'assigned_user_id', p_assigned_user_id, 'changed_count', changed_count)
  );
  return jsonb_build_object('success', true, 'changed_count', changed_count, 'assigned_user_id', p_assigned_user_id);
end;
$$;

create function public.get_recount_work()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare actor_id uuid := (select auth.uid()); work_rows jsonb;
begin
  if not private.is_permanent_user() then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'unauthenticated', 'message', 'Authentication is required.'
    ));
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'task_id', task.id,
    'status', task.status,
    'claimable', task.status = 'UNASSIGNED',
    'product', jsonb_build_object(
      'id', product.id,
      'product_code', product.product_code,
      'name', product.name,
      'barcode', product.barcode,
      'units_per_case', product.units_per_case,
      'cases_per_layer', product.cases_per_layer,
      'cases_per_pallet', product.cases_per_pallet
    )
  ) order by product.name), '[]'::jsonb) into work_rows
  from public.recount_tasks as task
  join public.products as product on product.id = task.product_id and product.company_id = task.company_id
  join public.stock_taker_sessions as session
    on session.company_id = task.company_id and session.warehouse_id = task.warehouse_id
    and session.stock_take_id = task.stock_take_id
    and session.user_id = actor_id and session.status = 'ACTIVE'
  where task.status in ('UNASSIGNED', 'ASSIGNED', 'CLAIMED')
    and (task.status = 'UNASSIGNED' or task.assigned_user_id = actor_id or task.claimed_by = actor_id);
  return jsonb_build_object('success', true, 'tasks', work_rows);
end;
$$;

create function public.claim_recount_task(p_recount_task_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor_id uuid := (select auth.uid()); claimed_task public.recount_tasks%rowtype;
begin
  if not private.is_permanent_user() then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'unauthenticated', 'message', 'Authentication is required.'
    ));
  end if;
  update public.recount_tasks as task set
    claimed_by = actor_id, claimed_at = now(), status = 'CLAIMED'
  where task.id = p_recount_task_id
    and task.status in ('UNASSIGNED', 'ASSIGNED')
    and (task.assigned_user_id is null or task.assigned_user_id = actor_id)
    and exists (
      select 1 from public.stock_taker_sessions as session
      join public.stock_takes as stock_take
        on stock_take.id = session.stock_take_id and stock_take.company_id = session.company_id
        and stock_take.warehouse_id = session.warehouse_id
      where session.company_id = task.company_id and session.warehouse_id = task.warehouse_id
        and session.stock_take_id = task.stock_take_id and session.user_id = actor_id
        and session.status = 'ACTIVE' and stock_take.status = 'RECOUNT'
    )
  returning task.* into claimed_task;
  if claimed_task.id is null then
    select * into claimed_task from public.recount_tasks where id = p_recount_task_id;
    if claimed_task.claimed_by = actor_id and claimed_task.status = 'CLAIMED' then
      return jsonb_build_object('success', true, 'existing', true, 'recount_task_id', claimed_task.id, 'status', claimed_task.status);
    end if;
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'task_unavailable', 'message', 'This blind recount task is assigned elsewhere or was already claimed.'
    ));
  end if;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    claimed_task.company_id, claimed_task.warehouse_id, actor_id, 'recount_task.claimed',
    'recount_task', claimed_task.id, jsonb_build_object('stock_take_id', claimed_task.stock_take_id)
  );
  return jsonb_build_object('success', true, 'existing', false, 'recount_task_id', claimed_task.id, 'status', claimed_task.status);
end;
$$;

create function public.submit_recount(p_record jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  task_id uuid; session_id uuid; idempotency_value uuid;
  pallets_value bigint; layers_value bigint; cases_value bigint; units_value bigint;
  duration_value integer; quantity_valid boolean; calculated_total bigint;
  task_row public.recount_tasks%rowtype; product_row public.products%rowtype;
  existing_count public.recount_counts%rowtype; created_count_id uuid;
begin
  if not private.is_permanent_user() or jsonb_typeof(p_record) is distinct from 'object' then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object(
      'code', 'invalid_record', 'message', 'An authenticated recount record is required.'
    ));
  end if;
  begin
    task_id := (p_record ->> 'recount_task_id')::uuid;
    session_id := (p_record ->> 'stock_taker_session_id')::uuid;
    idempotency_value := (p_record ->> 'idempotency_key')::uuid;
  exception when others then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object(
      'code', 'invalid_identity', 'message', 'Recount identity fields are invalid.'
    ));
  end;
  if task_id is null or session_id is null or idempotency_value is null then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object(
      'code', 'invalid_identity', 'message', 'Recount identity fields are required.'
    ));
  end if;
  perform pg_advisory_xact_lock(hashtextextended(idempotency_value::text, 0));
  select * into existing_count from public.recount_counts where idempotency_key = idempotency_value;
  if existing_count.id is not null then
    if existing_count.submitted_by <> actor_id
      or existing_count.recount_task_id <> task_id
      or existing_count.stock_taker_session_id <> session_id then
      return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object(
        'code', 'idempotency_conflict', 'message', 'The idempotency key belongs to a different recount request.'
      ));
    end if;
    return jsonb_build_object('success', true, 'acknowledged', true, 'existing', true,
      'recount_count_id', existing_count.id, 'total_units', existing_count.total_units);
  end if;
  select * into task_row from public.recount_tasks where id = task_id for update;
  if task_row.id is null or task_row.status <> 'CLAIMED' or task_row.claimed_by <> actor_id then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object(
      'code', 'task_not_claimed', 'message', 'Claim this blind recount task before submitting it.'
    ));
  end if;
  if not exists (
    select 1 from public.stock_taker_sessions as session
    join public.stock_takes as stock_take
      on stock_take.id = session.stock_take_id and stock_take.company_id = session.company_id
      and stock_take.warehouse_id = session.warehouse_id
    where session.id = session_id and session.user_id = actor_id and session.status = 'ACTIVE'
      and session.company_id = task_row.company_id and session.warehouse_id = task_row.warehouse_id
      and session.stock_take_id = task_row.stock_take_id and stock_take.status = 'RECOUNT'
  ) then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object(
      'code', 'recount_closed', 'message', 'The recount session is no longer active.'
    ));
  end if;
  select parsed_value, is_valid into pallets_value, quantity_valid from private.parse_count_quantity(p_record -> 'pallets');
  if not quantity_valid then return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object('code', 'invalid_quantity', 'field', 'pallets')); end if;
  select parsed_value, is_valid into layers_value, quantity_valid from private.parse_count_quantity(p_record -> 'layers');
  if not quantity_valid then return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object('code', 'invalid_quantity', 'field', 'layers')); end if;
  select parsed_value, is_valid into cases_value, quantity_valid from private.parse_count_quantity(p_record -> 'cases');
  if not quantity_valid then return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object('code', 'invalid_quantity', 'field', 'cases')); end if;
  select parsed_value, is_valid into units_value, quantity_valid from private.parse_count_quantity(p_record -> 'units');
  if not quantity_valid then return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object('code', 'invalid_quantity', 'field', 'units')); end if;
  begin
    duration_value := nullif(p_record ->> 'duration_ms', '')::integer;
    if duration_value is not null and duration_value < 0 then raise numeric_value_out_of_range; end if;
  exception when others then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object('code', 'invalid_duration'));
  end;
  select * into product_row from public.products where id = task_row.product_id and company_id = task_row.company_id;
  if pallets_value > 0 and (product_row.cases_per_pallet is null or product_row.units_per_case is null) then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object('code', 'missing_packaging', 'field', 'pallets'));
  end if;
  if layers_value > 0 and (product_row.cases_per_layer is null or product_row.units_per_case is null) then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object('code', 'missing_packaging', 'field', 'layers'));
  end if;
  if cases_value > 0 and product_row.units_per_case is null then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object('code', 'missing_packaging', 'field', 'cases'));
  end if;
  begin
    calculated_total := pallets_value * coalesce(product_row.cases_per_pallet, 0)::bigint * coalesce(product_row.units_per_case, 0)::bigint
      + layers_value * coalesce(product_row.cases_per_layer, 0)::bigint * coalesce(product_row.units_per_case, 0)::bigint
      + cases_value * coalesce(product_row.units_per_case, 0)::bigint + units_value;
  exception when numeric_value_out_of_range then
    return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object('code', 'quantity_overflow'));
  end;
  insert into public.recount_counts (
    company_id, warehouse_id, stock_take_id, recount_task_id, stock_taker_session_id,
    product_id, submitted_by, pallets, layers, cases, units, total_units, duration_ms, idempotency_key
  ) values (
    task_row.company_id, task_row.warehouse_id, task_row.stock_take_id, task_row.id, session_id,
    task_row.product_id, actor_id, pallets_value, layers_value, cases_value, units_value,
    calculated_total, duration_value, idempotency_value
  ) returning id into created_count_id;
  update public.recount_tasks set status = 'COMPLETED', completed_at = now() where id = task_row.id;
  update public.recount_batches set status = 'COMPLETED', completed_at = now()
  where id = task_row.recount_batch_id and status = 'OPEN'
    and not exists (select 1 from public.recount_tasks where recount_batch_id = task_row.recount_batch_id and status <> 'COMPLETED');
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    task_row.company_id, task_row.warehouse_id, actor_id, 'recount.submitted', 'recount_count', created_count_id,
    jsonb_build_object('recount_task_id', task_row.id, 'stock_take_id', task_row.stock_take_id,
      'product_id', task_row.product_id, 'total_units', calculated_total, 'idempotency_key', idempotency_value)
  );
  return jsonb_build_object('success', true, 'acknowledged', true, 'existing', false,
    'recount_count_id', created_count_id, 'total_units', calculated_total);
exception when unique_violation then
  return jsonb_build_object('success', false, 'acknowledged', false, 'error', jsonb_build_object(
    'code', 'recount_already_completed', 'message', 'This blind recount task already has an immutable result.'
  ));
end;
$$;

create or replace function public.complete_stock_take(
  p_company_id uuid, p_warehouse_id uuid, p_stock_take_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  current_status public.stock_take_status;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Completion requires an allocated Admin or Manager.'
    ));
  end if;
  select status into current_status from public.stock_takes
  where id = p_stock_take_id and company_id = p_company_id
    and warehouse_id = p_warehouse_id for update;
  if not found then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_found', 'message', 'The stock take was not found.'
    ));
  end if;
  if current_status <> 'REVIEW' then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_state', 'message', 'Only a REVIEW stock take can be completed.'
    ));
  end if;
  if exists (
    select 1 from public.recount_tasks
    where stock_take_id = p_stock_take_id and status <> 'COMPLETED'
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'recounts_outstanding', 'message', 'Complete every open recount task before finalising.'
    ));
  end if;
  if exists (
    select 1 from public.count_flags
    where stock_take_id = p_stock_take_id and status = 'OPEN'
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'count_flags_outstanding', 'message', 'Resolve every open count flag before finalising.'
    ));
  end if;
  update public.stock_takes set status = 'COMPLETED', completed_by = actor_id
  where id = p_stock_take_id;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'stock_take.completed',
    'stock_take', p_stock_take_id, '{}'::jsonb
  );
  return jsonb_build_object('success', true, 'stock_take_id', p_stock_take_id, 'status', 'COMPLETED');
end;
$$;

comment on function public.get_recount_work() is
  'Blind stock-taker work list. It intentionally omits SOH, variance, thresholds, prior counts, and assignment history.';
comment on function public.claim_recount_task(uuid) is
  'Atomic claim/update: exactly one concurrent claimant can transition an available task.';
comment on function public.submit_recount(jsonb) is
  'Idempotent immutable blind recount submission with server-owned packaging calculation.';
