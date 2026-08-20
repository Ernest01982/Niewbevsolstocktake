begin;

create extension if not exists pgtap with schema extensions;

select plan(33);

select has_table('public', 'brands', 'brands exists');
select has_table('public', 'products', 'products exists');
select has_table('public', 'stock_takes', 'stock_takes exists');
select has_table('public', 'import_jobs', 'import_jobs exists');
select has_table('public', 'import_issues', 'import_issues exists');
select has_table('public', 'stock_snapshot_lines', 'stock_snapshot_lines exists');
select has_type('public', 'stock_take_status', 'stock_take_status exists');
select has_type('public', 'import_kind', 'import_kind exists');
select has_type('public', 'import_job_status', 'import_job_status exists');
select has_type('public', 'import_issue_disposition', 'import_issue_disposition exists');

select ok(
  (
    select bool_and(class.relrowsecurity and class.relforcerowsecurity)
    from pg_class as class
    join pg_namespace as namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'public'
      and class.relname = any (
        array[
          'brands',
          'products',
          'stock_takes',
          'import_jobs',
          'import_issues',
          'stock_snapshot_lines'
        ]
      )
  ),
  'RLS is enabled and forced on every Phase 2 public table'
);

select throws_ok(
  $$
    insert into public.products (company_id, product_code, name)
    values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a-001', 'Duplicate Code')
  $$,
  '23505'::character(5),
  'duplicate key value violates unique constraint "products_company_normalized_code_key"',
  'product codes are unique case-insensitively within a company'
);

select throws_ok(
  $$
    insert into public.products (company_id, product_code, name, barcode)
    values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A-003', 'Duplicate Barcode', '6000000000001')
  $$,
  '23505'::character(5),
  'duplicate key value violates unique constraint "products_company_barcode_key"',
  'nonblank barcodes are unique within a company'
);

select throws_ok(
  $$
    insert into public.products (company_id, brand_id, product_code, name)
    values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'b2000000-0000-4000-8000-000000000001',
      'A-CROSS',
      'Cross-company Brand'
    )
  $$,
  '23503'::character(5),
  'insert or update on table "products" violates foreign key constraint "products_brand_company_fkey"',
  'a product cannot reference another company brand'
);

select throws_ok(
  $$
    insert into public.products (company_id, product_code, name, units_per_case)
    values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A-ZERO', 'Invalid Packaging', 0)
  $$,
  '23514'::character(5),
  'new row for relation "products" violates check constraint "products_units_per_case_check"',
  'packaging values must be positive when present'
);

select lives_ok(
  $$
    insert into public.stock_takes (
      id, company_id, warehouse_id, status, created_by, ready_at, started_at
    )
    values (
      'a4000000-0000-4000-8000-000000000010',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'a1000000-0000-4000-8000-000000000001',
      'ACTIVE',
      '10000000-0000-4000-8000-000000000020',
      now(),
      now()
    )
  $$,
  'the first open stock take is allowed for a warehouse'
);

select throws_ok(
  $$
    insert into public.stock_takes (
      company_id, warehouse_id, status, created_by, ready_at, started_at
    )
    values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'a1000000-0000-4000-8000-000000000001',
      'REVIEW',
      '10000000-0000-4000-8000-000000000020',
      now(),
      now()
    )
  $$,
  '23505'::character(5),
  'duplicate key value violates unique constraint "stock_takes_one_open_per_warehouse_idx"',
  'only one open stock take is allowed per warehouse'
);

select throws_ok(
  $$
    insert into public.import_jobs (
      company_id, warehouse_id, kind, source_filename, column_mapping, created_by
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'a1000000-0000-4000-8000-000000000001',
      'product_master',
      'invalid.csv',
      '{}',
      '10000000-0000-4000-8000-000000000010'
    )
  $$,
  '23514'::character(5),
  'new row for relation "import_jobs" violates check constraint "import_jobs_scope_check"',
  'product imports cannot claim a warehouse scope'
);

select throws_ok(
  $$
    insert into public.import_issues (
      company_id, warehouse_id, stock_take_id, import_job_id, row_number,
      disposition, issue_code, message, raw_row
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'a1000000-0000-4000-8000-000000000002',
      'a4000000-0000-4000-8000-000000000002',
      'a5000000-0000-4000-8000-000000000002',
      10,
      'rejected',
      'scope_test',
      'Scope mismatch test.',
      '{}'
    )
  $$,
  '23514'::character(5),
  'Import issue scope must match its import job.',
  'an import issue must inherit its job scope'
);

select throws_ok(
  $$update public.stock_snapshot_lines set quantity_on_hand = 1 where id = 'a7000000-0000-4000-8000-000000000001'$$,
  '55000'::character(5),
  'stock_snapshot_lines rows are immutable.',
  'snapshot rows reject updates'
);
select throws_ok(
  $$delete from public.stock_snapshot_lines where id = 'a7000000-0000-4000-8000-000000000001'$$,
  '55000'::character(5),
  'stock_snapshot_lines rows are immutable.',
  'snapshot rows reject deletes'
);
select throws_ok(
  $$update public.import_issues set message = 'changed' where id = 'a6000000-0000-4000-8000-000000000001'$$,
  '55000'::character(5),
  'import_issues rows are immutable.',
  'import issue rows reject updates'
);
select throws_ok(
  $$delete from public.import_issues where id = 'a6000000-0000-4000-8000-000000000001'$$,
  '55000'::character(5),
  'import_issues rows are immutable.',
  'import issue rows reject deletes'
);

select ok(not has_table_privilege('anon', 'public.products', 'SELECT'), 'anon cannot select products');
select ok(has_table_privilege('authenticated', 'public.products', 'SELECT'), 'authenticated may select products through RLS');
select ok(not has_table_privilege('authenticated', 'public.products', 'INSERT'), 'authenticated cannot insert products directly');
select ok(not has_table_privilege('authenticated', 'public.stock_snapshot_lines', 'UPDATE'), 'authenticated cannot update snapshots');
select ok(
  not has_function_privilege(
    'anon',
    'public.import_product_master(uuid,text,text,jsonb,jsonb,jsonb)',
    'EXECUTE'
  ),
  'anon cannot call product import'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.import_product_master(uuid,text,text,jsonb,jsonb,jsonb)',
    'EXECUTE'
  ),
  'authenticated can call product import subject to function authorization'
);

select throws_ok(
  $$
    insert into public.stock_snapshot_lines (
      company_id, warehouse_id, stock_take_id, product_id, import_job_id,
      quantity_on_hand, source_row_number, source_row, snapshot_as_of
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'a1000000-0000-4000-8000-000000000001',
      'a4000000-0000-4000-8000-000000000001',
      'a3000000-0000-4000-8000-000000000001',
      'a5000000-0000-4000-8000-000000000002',
      999,
      3,
      '{"Item":"A-001","SOH":"999"}',
      '2026-08-12T08:00:00+02:00'
    )
  $$,
  '23505'::character(5),
  'duplicate key value violates unique constraint "stock_snapshot_lines_stock_take_product_key"',
  'a stock take has one immutable snapshot line per product'
);

select throws_ok(
  $$
    insert into public.stock_snapshot_lines (
      company_id, warehouse_id, stock_take_id, product_id, import_job_id,
      quantity_on_hand, source_row_number, source_row, snapshot_as_of
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'a1000000-0000-4000-8000-000000000001',
      'a4000000-0000-4000-8000-000000000001',
      'b3000000-0000-4000-8000-000000000001',
      'a5000000-0000-4000-8000-000000000002',
      10,
      3,
      '{"Item":"B-001","SOH":"10"}',
      '2026-08-12T08:00:00+02:00'
    )
  $$,
  '23503'::character(5),
  'insert or update on table "stock_snapshot_lines" violates foreign key constraint "stock_snapshot_lines_product_company_fkey"',
  'snapshot lines cannot reference another company product'
);

select ok(not has_table_privilege('authenticated', 'public.import_issues', 'DELETE'), 'authenticated cannot delete import issues');
select ok(not has_table_privilege('authenticated', 'public.import_jobs', 'UPDATE'), 'authenticated cannot update import jobs directly');

select * from finish();
rollback;
