begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

create function private.test_set_auth_phase_2_import(test_user_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', test_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', test_user_id, 'role', 'authenticated', 'is_anonymous', false)::text,
    true
  );
end;
$$;

grant execute on function private.test_set_auth_phase_2_import(uuid) to authenticated;

set local role authenticated;

select private.test_set_auth_phase_2_import('10000000-0000-4000-8000-000000000030');
create temporary table forbidden_product_result as
select public.import_product_master(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'forbidden.csv',
  null,
  '{"product_code":"Item","name":"Description"}',
  '[{"Item":"NOPE","Description":"Forbidden"}]'
) as result;
select is((select result ->> 'success' from forbidden_product_result), 'false', 'stock taker product import is denied');
select is((select count(*)::integer from public.import_jobs), 0, 'stock taker cannot create an import job');

select private.test_set_auth_phase_2_import('10000000-0000-4000-8000-000000000010');
create temporary table product_import_result as
select public.import_product_master(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'mapped-products.csv',
  repeat('a', 64),
  '{"product_code":"Customer Item","name":"Long Description","brand":"Brand Heading","barcode":"EAN","units_per_case":"Units Case","cases_per_layer":"Cases Layer","cases_per_pallet":"Cases Pallet"}',
  '[
    {"Customer Item":"NEW-1","Long Description":"Mapped Product One","Brand Heading":"Mapped Brand","EAN":"6000000000099","Units Case":"12","Cases Layer":"10","Cases Pallet":"60"},
    {"Customer Item":"NEW-2","Long Description":"Mapped Product Two","Brand Heading":"Mapped Brand","EAN":"6000000000098","Units Case":"0","Cases Layer":"","Cases Pallet":""},
    {"Customer Item":"NEW-3","Long Description":"","Brand Heading":"Mapped Brand"},
    {"Customer Item":"NEW-4","Long Description":"Barcode Conflict","EAN":"6000000000099"}
  ]'
) as result;

select is((select result ->> 'success' from product_import_result), 'true', 'admin product import succeeds');
select is((select (result #>> '{totals,total}')::integer from product_import_result), 4, 'product import reports total rows');
select is((select (result #>> '{totals,accepted}')::integer from product_import_result), 1, 'product import reports accepted rows');
select is((select (result #>> '{totals,flagged}')::integer from product_import_result), 1, 'product import reports flagged rows');
select is((select (result #>> '{totals,rejected}')::integer from product_import_result), 2, 'product import reports rejected rows');
select is(
  (select count(*)::integer from public.products where normalized_product_code = 'new-1' and units_per_case = 12),
  1,
  'arbitrary source headings map into the canonical product fields'
);
select is(
  (select count(*)::integer from public.products where normalized_product_code = 'new-2' and units_per_case is null),
  1,
  'invalid optional packaging is flagged and stored as missing metadata'
);
select is(
  (select count(*)::integer from public.products where normalized_product_code in ('new-3', 'new-4')),
  0,
  'rejected product rows do not mutate the product master'
);
select is(
  (select count(*)::integer from public.import_issues where import_job_id = (select (result ->> 'import_job_id')::uuid from product_import_result)),
  3,
  'product import persists each flagged or rejected row issue'
);
select is(
  (select count(*)::integer from public.audit_logs where action = 'import.product_master.completed'),
  1,
  'product import writes an audit summary'
);

select private.test_set_auth_phase_2_import('10000000-0000-4000-8000-000000000020');
create temporary table snapshot_import_result as
select public.import_stock_snapshot(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001',
  'mapped-soh.csv',
  repeat('b', 64),
  '{"product_code":"ERP Item","quantity_on_hand":"Warehouse Qty"}',
  '[
    {"ERP Item":"NEW-1","Warehouse Qty":"-5"},
    {"ERP Item":"UNKNOWN","Warehouse Qty":"10"},
    {"ERP Item":"NEW-2","Warehouse Qty":"1.5"},
    {"ERP Item":"NEW-1","Warehouse Qty":"7"}
  ]',
  '2026-08-12T09:00:00+02:00'
) as result;

select is((select result ->> 'success' from snapshot_import_result), 'true', 'manager snapshot import succeeds for allocated warehouse');
select is((select (result #>> '{totals,total}')::integer from snapshot_import_result), 4, 'snapshot import reports total rows');
select is((select (result #>> '{totals,accepted}')::integer from snapshot_import_result), 1, 'snapshot import reports accepted rows');
select is((select (result #>> '{totals,rejected}')::integer from snapshot_import_result), 3, 'snapshot import reports rejected rows');
select is((select result ->> 'has_unresolved_errors' from snapshot_import_result), 'true', 'snapshot import surfaces unresolved errors');
select is(
  (select count(*)::integer from public.stock_snapshot_lines where quantity_on_hand = -5 and product_id = (select id from public.products where normalized_product_code = 'new-1')),
  1,
  'valid whole-number SOH is preserved exactly, including negative ERP stock'
);
select is(
  (select count(*)::integer from public.import_issues where import_job_id = (select (result ->> 'import_job_id')::uuid from snapshot_import_result)),
  3,
  'snapshot import persists all rejected row issues'
);
select is(
  (select count(*)::integer from public.audit_logs where action = 'import.stock_snapshot.completed'),
  1,
  'snapshot import writes an audit summary'
);

select private.test_set_auth_phase_2_import('10000000-0000-4000-8000-000000000030');
select is(
  public.import_stock_snapshot(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001',
    'forbidden-soh.csv',
    null,
    '{"product_code":"Item","quantity_on_hand":"SOH"}',
    '[]',
    now()
  ) #>> '{error,code}',
  'forbidden',
  'stock taker cannot import a snapshot'
);

select private.test_set_auth_phase_2_import('10000000-0000-4000-8000-000000000020');
select is(
  public.import_stock_snapshot(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000002',
    'a4000000-0000-4000-8000-000000000002',
    'cross-warehouse.csv',
    null,
    '{"product_code":"Item","quantity_on_hand":"SOH"}',
    '[]',
    now()
  ) #>> '{error,code}',
  'forbidden',
  'manager cannot import into another warehouse'
);

select private.test_set_auth_phase_2_import('10000000-0000-4000-8000-000000000001');
select is(
  public.import_stock_snapshot(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000002',
    'a4000000-0000-4000-8000-000000000002',
    'completed.csv',
    null,
    '{"product_code":"Item","quantity_on_hand":"SOH"}',
    '[]',
    now()
  ) #>> '{error,code}',
  'stock_take_not_draft',
  'completed stock takes reject snapshot imports'
);

select private.test_set_auth_phase_2_import('10000000-0000-4000-8000-000000000010');
select is(
  public.import_product_master(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'invalid-map.csv',
    null,
    '{"name":"Description"}',
    '[]'
  ) #>> '{error,code}',
  'invalid_column_mapping',
  'missing required mappings return a structured error without creating a job'
);

reset role;
select * from finish();
rollback;
