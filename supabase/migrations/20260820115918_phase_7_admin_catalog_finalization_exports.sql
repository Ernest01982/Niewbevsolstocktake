alter table public.stock_takes
  add column completion_mode text,
  add column completion_reason text,
  add constraint stock_takes_completion_mode_check
    check (completion_mode is null or completion_mode in ('standard', 'override')),
  add constraint stock_takes_completion_reason_check
    check (completion_mode <> 'override' or nullif(btrim(completion_reason), '') is not null);

update public.stock_takes
set completion_mode = 'standard'
where status in ('COMPLETED', 'REOPENED');

create table public.stock_take_exports (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid not null,
  stock_take_id uuid not null,
  export_kind text not null check (export_kind in ('sage_physical_count', 'reconciliation')),
  export_format text not null default 'generic_sage_csv_v1',
  filename text not null check (length(btrim(filename)) between 1 and 240),
  row_count integer not null check (row_count >= 0),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  constraint stock_take_exports_stock_take_scope_fkey
    foreign key (stock_take_id, company_id, warehouse_id)
    references public.stock_takes (id, company_id, warehouse_id)
    on delete restrict,
  constraint stock_take_exports_creator_fkey
    foreign key (company_id, created_by)
    references public.company_memberships (company_id, user_id)
    on delete restrict
);

create index stock_take_exports_scope_idx
  on public.stock_take_exports (company_id, warehouse_id, stock_take_id, created_at desc);

alter table public.stock_take_exports enable row level security;
alter table public.stock_take_exports force row level security;

create policy stock_take_exports_select_admin
on public.stock_take_exports
for select
to authenticated
using (
  (select private.can_access_warehouse(
    company_id,
    warehouse_id,
    array['admin']::public.membership_role[]
  ))
);

revoke all on table public.stock_take_exports from anon, authenticated;
grant select on table public.stock_take_exports to authenticated;

create function public.save_product(
  p_company_id uuid,
  p_product_id uuid default null,
  p_product_code text default null,
  p_name text default null,
  p_brand_name text default null,
  p_barcode text default null,
  p_units_per_case integer default null,
  p_cases_per_layer integer default null,
  p_cases_per_pallet integer default null,
  p_status public.record_status default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  saved_product_id uuid;
  saved_brand_id uuid;
  action_name text;
begin
  if not private.can_access_company(
    p_company_id,
    array['admin']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Product changes require an active Admin allocation.'
    ));
  end if;

  if nullif(btrim(p_product_code), '') is null or nullif(btrim(p_name), '') is null then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'required_value_missing', 'message', 'Product code and product name are required.'
    ));
  end if;

  if p_units_per_case is not null and p_units_per_case <= 0
    or p_cases_per_layer is not null and p_cases_per_layer <= 0
    or p_cases_per_pallet is not null and p_cases_per_pallet <= 0 then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_packaging', 'message', 'Packaging values must be positive whole numbers or blank.'
    ));
  end if;

  saved_brand_id := null;
  if nullif(btrim(p_brand_name), '') is not null then
    insert into public.brands (company_id, name, status)
    values (p_company_id, btrim(p_brand_name), 'active')
    on conflict on constraint brands_company_normalized_name_key
    do update set name = excluded.name, status = 'active'
    returning id into saved_brand_id;
  end if;

  if p_product_id is null then
    insert into public.products (
      company_id, brand_id, product_code, name, barcode,
      units_per_case, cases_per_layer, cases_per_pallet, status
    ) values (
      p_company_id, saved_brand_id, btrim(p_product_code), btrim(p_name),
      nullif(btrim(p_barcode), ''), p_units_per_case, p_cases_per_layer,
      p_cases_per_pallet, p_status
    ) returning id into saved_product_id;
    action_name := 'product.created';
  else
    update public.products
    set brand_id = saved_brand_id,
        product_code = btrim(p_product_code),
        name = btrim(p_name),
        barcode = nullif(btrim(p_barcode), ''),
        units_per_case = p_units_per_case,
        cases_per_layer = p_cases_per_layer,
        cases_per_pallet = p_cases_per_pallet,
        status = p_status
    where id = p_product_id and company_id = p_company_id
    returning id into saved_product_id;
    if saved_product_id is null then
      return jsonb_build_object('success', false, 'error', jsonb_build_object(
        'code', 'product_not_found', 'message', 'The product was not found in this company.'
      ));
    end if;
    action_name := case when p_status = 'inactive' then 'product.archived' else 'product.updated' end;
  end if;

  insert into public.audit_logs (
    company_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, actor_id, action_name, 'product', saved_product_id,
    jsonb_build_object('product_code', btrim(p_product_code), 'status', p_status)
  );

  return jsonb_build_object('success', true, 'product_id', saved_product_id, 'status', p_status);
exception
  when unique_violation then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'identifier_conflict', 'message', 'That product code or barcode is already used by another stock item.'
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
    array['admin']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Final approval requires an allocated Admin or authorised Super Admin.'
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
      'code', 'recounts_outstanding', 'message', 'Complete every open recount task or use the Admin variance override.'
    ));
  end if;
  if exists (
    select 1 from public.count_flags
    where stock_take_id = p_stock_take_id and status = 'OPEN'
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'count_flags_outstanding', 'message', 'Resolve every open count flag or use the Admin variance override.'
    ));
  end if;
  update public.stock_takes
  set status = 'COMPLETED', completed_by = actor_id,
      completion_mode = 'standard', completion_reason = null
  where id = p_stock_take_id;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'stock_take.completed',
    'stock_take', p_stock_take_id, jsonb_build_object('completion_mode', 'standard')
  );
  return jsonb_build_object('success', true, 'stock_take_id', p_stock_take_id,
    'status', 'COMPLETED', 'completion_mode', 'standard');
end;
$$;

create function public.force_complete_stock_take(
  p_company_id uuid,
  p_warehouse_id uuid,
  p_stock_take_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  current_status public.stock_take_status;
  open_recount_count integer;
  open_flag_count integer;
  variance_line_count integer;
  absolute_variance_units bigint;
  open_recount_ids jsonb;
  open_flag_ids jsonb;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Variance override requires an allocated Admin or authorised Super Admin.'
    ));
  end if;
  if nullif(btrim(p_reason), '') is null then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'reason_required', 'message', 'Record why the outstanding variances are being accepted.'
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

  select count(*)::integer,
         coalesce(jsonb_agg(task.id order by task.created_at), '[]'::jsonb)
  into open_recount_count, open_recount_ids
  from public.recount_tasks as task
  where task.stock_take_id = p_stock_take_id and task.status <> 'COMPLETED';

  select count(*)::integer,
         coalesce(jsonb_agg(flag.id order by flag.created_at), '[]'::jsonb)
  into open_flag_count, open_flag_ids
  from public.count_flags as flag
  where flag.stock_take_id = p_stock_take_id and flag.status = 'OPEN';

  select count(*) filter (where variance.signed_variance_units <> 0)::integer,
         coalesce(sum(variance.absolute_variance_units), 0)::bigint
  into variance_line_count, absolute_variance_units
  from private.stock_take_variances(p_stock_take_id) as variance;

  update public.stock_takes
  set status = 'COMPLETED', completed_by = actor_id,
      completion_mode = 'override', completion_reason = btrim(p_reason)
  where id = p_stock_take_id;

  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'stock_take.force_completed',
    'stock_take', p_stock_take_id,
    jsonb_build_object(
      'completion_mode', 'override',
      'reason', btrim(p_reason),
      'variance_line_count', variance_line_count,
      'absolute_variance_units', absolute_variance_units,
      'open_recount_count', open_recount_count,
      'open_recount_ids', open_recount_ids,
      'open_flag_count', open_flag_count,
      'open_flag_ids', open_flag_ids
    )
  );

  return jsonb_build_object(
    'success', true, 'stock_take_id', p_stock_take_id, 'status', 'COMPLETED',
    'completion_mode', 'override', 'variance_line_count', variance_line_count,
    'absolute_variance_units', absolute_variance_units,
    'open_recount_count', open_recount_count, 'open_flag_count', open_flag_count
  );
end;
$$;

create function public.create_stock_take_export(
  p_company_id uuid,
  p_warehouse_id uuid,
  p_stock_take_id uuid,
  p_export_kind text default 'sage_physical_count'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  current_status public.stock_take_status;
  warehouse_code_value text;
  export_id uuid;
  export_filename text;
  export_rows jsonb;
  export_row_count integer;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Stock-take exports require an allocated Admin or authorised Super Admin.'
    ));
  end if;
  if p_export_kind not in ('sage_physical_count', 'reconciliation') then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_export_kind', 'message', 'The requested export format is not supported.'
    ));
  end if;

  select stock_take.status, warehouse.warehouse_code
  into current_status, warehouse_code_value
  from public.stock_takes as stock_take
  join public.warehouses as warehouse
    on warehouse.id = stock_take.warehouse_id and warehouse.company_id = stock_take.company_id
  where stock_take.id = p_stock_take_id
    and stock_take.company_id = p_company_id
    and stock_take.warehouse_id = p_warehouse_id;
  if not found then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_found', 'message', 'The stock take was not found.'
    ));
  end if;
  if current_status <> 'COMPLETED' then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_completed', 'message', 'Only a completed stock take can be exported.'
    ));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'product_code', variance.product_code,
    'product_name', variance.product_name,
    'warehouse_code', warehouse_code_value,
    'counted_quantity', variance.physical_units,
    'system_quantity', variance.snapshot_units,
    'variance_quantity', variance.signed_variance_units
  ) order by variance.product_code), '[]'::jsonb), count(*)::integer
  into export_rows, export_row_count
  from private.stock_take_variances(p_stock_take_id) as variance;

  export_filename := concat(
    lower(regexp_replace(warehouse_code_value, '[^a-zA-Z0-9]+', '-', 'g')),
    '-stock-count-', to_char(now(), 'YYYYMMDD-HH24MISS'), '.csv'
  );

  insert into public.stock_take_exports (
    company_id, warehouse_id, stock_take_id, export_kind, filename,
    row_count, created_by, metadata
  ) values (
    p_company_id, p_warehouse_id, p_stock_take_id, p_export_kind,
    export_filename, export_row_count, actor_id,
    jsonb_build_object('warehouse_code', warehouse_code_value, 'version', 1)
  ) returning id into export_id;

  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'stock_take.exported',
    'stock_take_export', export_id,
    jsonb_build_object(
      'stock_take_id', p_stock_take_id, 'export_kind', p_export_kind,
      'filename', export_filename, 'row_count', export_row_count
    )
  );

  return jsonb_build_object(
    'success', true, 'export_id', export_id, 'filename', export_filename,
    'export_kind', p_export_kind, 'format', 'generic_sage_csv_v1',
    'row_count', export_row_count, 'rows', export_rows
  );
end;
$$;

comment on function public.force_complete_stock_take(uuid, uuid, uuid, text) is
  'Admin-only completion override. Outstanding recount and flag identifiers are preserved in immutable audit metadata.';
comment on function public.create_stock_take_export(uuid, uuid, uuid, text) is
  'Admin-only completed count export. Returns final effective quantities and creates an immutable export history record.';

revoke execute on function public.save_product(uuid, uuid, text, text, text, text, integer, integer, integer, public.record_status)
from public, anon;
revoke execute on function public.force_complete_stock_take(uuid, uuid, uuid, text)
from public, anon;
revoke execute on function public.create_stock_take_export(uuid, uuid, uuid, text)
from public, anon;

grant execute on function public.save_product(uuid, uuid, text, text, text, text, integer, integer, integer, public.record_status)
to authenticated;
grant execute on function public.force_complete_stock_take(uuid, uuid, uuid, text)
to authenticated;
grant execute on function public.create_stock_take_export(uuid, uuid, uuid, text)
to authenticated;
