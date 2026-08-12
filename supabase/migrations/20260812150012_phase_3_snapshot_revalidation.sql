create or replace function public.import_stock_snapshot(
  p_company_id uuid,
  p_warehouse_id uuid,
  p_stock_take_id uuid,
  p_source_filename text,
  p_source_sha256 text,
  p_column_mapping jsonb,
  p_rows jsonb,
  p_snapshot_as_of timestamptz,
  p_source_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  job_id uuid;
  total_count integer;
  accepted_count integer := 0;
  rejected_count integer := 0;
  source_row jsonb;
  source_row_number integer;
  product_code_value text;
  quantity_raw_value text;
  quantity_value bigint;
  quantity_is_valid boolean;
  product_value_id uuid;
  final_status public.import_job_status;
  existing_import_job_id uuid;
  existing_quantity bigint;
begin
  if not private.can_access_warehouse(
    p_company_id,
    p_warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object(
      'success', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Snapshot imports require an allocated Admin or Manager.')
    );
  end if;

  if nullif(btrim(p_source_filename), '') is null or p_snapshot_as_of is null then
    return jsonb_build_object(
      'success', false,
      'error', jsonb_build_object('code', 'invalid_snapshot_source', 'message', 'A source filename and snapshot timestamp are required.')
    );
  end if;

  if p_source_sha256 is not null and p_source_sha256 !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object(
      'success', false,
      'error', jsonb_build_object('code', 'invalid_source_hash', 'message', 'source_sha256 must be a lowercase 64-character hexadecimal hash.')
    );
  end if;

  if jsonb_typeof(p_source_metadata) is distinct from 'object'
    or jsonb_typeof(p_column_mapping) is distinct from 'object'
    or jsonb_typeof(p_rows) is distinct from 'array' then
    return jsonb_build_object(
      'success', false,
      'error', jsonb_build_object('code', 'invalid_import_payload', 'message', 'Metadata and mapping must be objects and rows must be an array.')
    );
  end if;

  if jsonb_typeof(p_column_mapping -> 'product_code') is distinct from 'string'
    or nullif(btrim(p_column_mapping ->> 'product_code'), '') is null
    or jsonb_typeof(p_column_mapping -> 'quantity_on_hand') is distinct from 'string'
    or nullif(btrim(p_column_mapping ->> 'quantity_on_hand'), '') is null then
    return jsonb_build_object(
      'success', false,
      'error', jsonb_build_object('code', 'invalid_column_mapping', 'message', 'product_code and quantity_on_hand source columns must be mapped explicitly.')
    );
  end if;

  perform 1
  from public.stock_takes as stock_take
  where stock_take.id = p_stock_take_id
    and stock_take.company_id = p_company_id
    and stock_take.warehouse_id = p_warehouse_id
    and stock_take.status = 'DRAFT'
  for update;

  if not found then
    return jsonb_build_object(
      'success', false,
      'error', jsonb_build_object('code', 'stock_take_not_draft', 'message', 'The stock take must be DRAFT and belong to the selected warehouse.')
    );
  end if;

  total_count := jsonb_array_length(p_rows);

  insert into public.import_jobs (
    company_id,
    warehouse_id,
    stock_take_id,
    kind,
    source_filename,
    source_sha256,
    source_metadata,
    column_mapping,
    snapshot_as_of,
    total_rows,
    created_by
  ) values (
    p_company_id,
    p_warehouse_id,
    p_stock_take_id,
    'stock_snapshot',
    btrim(p_source_filename),
    p_source_sha256,
    p_source_metadata,
    p_column_mapping,
    p_snapshot_as_of,
    total_count,
    actor_id
  )
  returning id into job_id;

  for source_row, source_row_number in
    select element.value, element.ordinality::integer
    from jsonb_array_elements(p_rows) with ordinality as element(value, ordinality)
  loop
    begin
      if jsonb_typeof(source_row) is distinct from 'object' then
        insert into public.import_issues (
          company_id, warehouse_id, stock_take_id, import_job_id, row_number,
          disposition, issue_code, message, raw_row
        ) values (
          p_company_id, p_warehouse_id, p_stock_take_id, job_id, source_row_number,
          'rejected', 'row_not_object', 'The source row must be a JSON object.', source_row
        );
        rejected_count := rejected_count + 1;
        continue;
      end if;

      product_code_value := private.import_mapped_text(source_row, p_column_mapping, 'product_code');
      quantity_raw_value := private.import_mapped_text(source_row, p_column_mapping, 'quantity_on_hand');

      if product_code_value is null then
        insert into public.import_issues (
          company_id, warehouse_id, stock_take_id, import_job_id, row_number,
          disposition, issue_code, field_name, message, raw_row
        ) values (
          p_company_id, p_warehouse_id, p_stock_take_id, job_id, source_row_number,
          'rejected', 'required_value_missing', 'product_code', 'The mapped product code is missing.', source_row
        );
        rejected_count := rejected_count + 1;
        continue;
      end if;

      select parsed_value, is_valid
      into quantity_value, quantity_is_valid
      from private.parse_required_bigint(quantity_raw_value);

      if not quantity_is_valid then
        insert into public.import_issues (
          company_id, warehouse_id, stock_take_id, import_job_id, row_number,
          disposition, issue_code, field_name, message, raw_row
        ) values (
          p_company_id, p_warehouse_id, p_stock_take_id, job_id, source_row_number,
          'rejected', 'invalid_whole_number', 'quantity_on_hand',
          'quantity_on_hand must be a whole number.', source_row
        );
        rejected_count := rejected_count + 1;
        continue;
      end if;

      select product.id
      into product_value_id
      from public.products as product
      where product.company_id = p_company_id
        and product.normalized_product_code = lower(btrim(product_code_value))
        and product.status = 'active';

      if not found then
        insert into public.import_issues (
          company_id, warehouse_id, stock_take_id, import_job_id, row_number,
          disposition, issue_code, field_name, message, raw_row
        ) values (
          p_company_id, p_warehouse_id, p_stock_take_id, job_id, source_row_number,
          'rejected', 'product_not_found', 'product_code',
          'The product code does not match an active company product.', source_row
        );
        rejected_count := rejected_count + 1;
        continue;
      end if;

      insert into public.stock_snapshot_lines (
        company_id,
        warehouse_id,
        stock_take_id,
        product_id,
        import_job_id,
        quantity_on_hand,
        source_row_number,
        source_row,
        snapshot_as_of
      ) values (
        p_company_id,
        p_warehouse_id,
        p_stock_take_id,
        product_value_id,
        job_id,
        quantity_value,
        source_row_number,
        source_row,
        p_snapshot_as_of
      );

      accepted_count := accepted_count + 1;
    exception
      when unique_violation then
        select line.import_job_id, line.quantity_on_hand
        into existing_import_job_id, existing_quantity
        from public.stock_snapshot_lines as line
        where line.stock_take_id = p_stock_take_id
          and line.product_id = product_value_id;

        if existing_import_job_id <> job_id and existing_quantity = quantity_value then
          accepted_count := accepted_count + 1;
        else
          insert into public.import_issues (
            company_id, warehouse_id, stock_take_id, import_job_id, row_number,
            disposition, issue_code, message, raw_row
          ) values (
            p_company_id, p_warehouse_id, p_stock_take_id, job_id, source_row_number,
            'rejected',
            case when existing_import_job_id = job_id
              then 'duplicate_snapshot_product'
              else 'snapshot_quantity_conflict'
            end,
            case when existing_import_job_id = job_id
              then 'The product appears more than once in this snapshot import.'
              else 'The retry quantity conflicts with the immutable snapshot line.'
            end,
            source_row
          );
          rejected_count := rejected_count + 1;
        end if;
      when others then
        insert into public.import_issues (
          company_id, warehouse_id, stock_take_id, import_job_id, row_number,
          disposition, issue_code, message, raw_row
        ) values (
          p_company_id, p_warehouse_id, p_stock_take_id, job_id, source_row_number,
          'rejected', 'row_rejected', 'The row could not be imported safely.', source_row
        );
        rejected_count := rejected_count + 1;
    end;
  end loop;

  final_status := case
    when rejected_count > 0 then 'completed_with_issues'::public.import_job_status
    else 'completed'::public.import_job_status
  end;

  update public.import_jobs
  set status = final_status,
      accepted_rows = accepted_count,
      flagged_rows = 0,
      rejected_rows = rejected_count,
      completed_at = now()
  where id = job_id;

  insert into public.audit_logs (
    company_id,
    warehouse_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    metadata
  ) values (
    p_company_id,
    p_warehouse_id,
    actor_id,
    'import.stock_snapshot.completed',
    'import_job',
    job_id,
    jsonb_build_object(
      'stock_take_id', p_stock_take_id,
      'snapshot_as_of', p_snapshot_as_of,
      'total', total_count,
      'accepted', accepted_count,
      'flagged', 0,
      'rejected', rejected_count,
      'source_sha256', p_source_sha256
    )
  );

  return jsonb_build_object(
    'success', true,
    'import_job_id', job_id,
    'status', final_status,
    'has_unresolved_errors', rejected_count > 0,
    'totals', jsonb_build_object(
      'total', total_count,
      'accepted', accepted_count,
      'flagged', 0,
      'rejected', rejected_count
    )
  );
exception when others then
  return jsonb_build_object(
    'success', false,
    'error', jsonb_build_object('code', sqlstate, 'message', 'The stock snapshot import could not be completed.')
  );
end;
$$;

comment on function public.import_product_master(uuid, text, text, jsonb, jsonb, jsonb) is
  'Audited flexible product import. Logical fields map explicitly to arbitrary source headings; row failures are isolated.';
comment on function public.import_stock_snapshot(uuid, uuid, uuid, text, text, jsonb, jsonb, timestamptz, jsonb) is
  'Audited warehouse and stock-take-specific SOH import. Snapshot rows are append-only and row failures are isolated.';
