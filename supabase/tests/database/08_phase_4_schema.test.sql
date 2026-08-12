begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

select has_table('public', 'counts', 'counts exists');
select has_table('public', 'count_flags', 'count_flags exists');
select has_type('public', 'count_type', 'count type exists');
select has_type('public', 'count_flag_type', 'count flag type exists');
select has_column('public', 'counts', 'idempotency_key', 'counts carry idempotency keys');
select has_column('public', 'counts', 'total_units', 'counts persist canonical total units');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.counts'::regclass), 'counts has enabled and forced RLS');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.count_flags'::regclass), 'count flags has enabled and forced RLS');
select has_index('public', 'counts', 'counts_idempotency_key_key', 'idempotency key is unique');
select has_index('public', 'counts', 'counts_duplicate_lookup_idx', 'duplicate lookup is indexed');

update public.stock_takes set status = 'READY' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'ACTIVE' where id = 'a4000000-0000-4000-8000-000000000001';
insert into public.stock_taker_sessions (
  id, company_id, warehouse_id, stock_take_id, user_id
) values (
  'a8000000-0000-4000-8000-000000000001',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000030'
);
insert into public.counts (
  id, company_id, warehouse_id, stock_take_id, stock_taker_session_id,
  product_id, submitted_by, count_type, pallets, layers, cases, units,
  total_units, idempotency_key
) values (
  'a9000000-0000-4000-8000-000000000001',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001',
  'a8000000-0000-4000-8000-000000000001',
  'a3000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000030',
  'BULK', 1, 0, 0, 0, 720,
  'c0000000-0000-4000-8000-000000000001'
);

select throws_ok($$update public.counts set units = 1 where id = 'a9000000-0000-4000-8000-000000000001'$$, '55000', 'counts rows are immutable.', 'counts reject updates');
select throws_ok($$delete from public.counts where id = 'a9000000-0000-4000-8000-000000000001'$$, '55000', 'counts rows are immutable.', 'counts reject deletes');
select throws_ok($$insert into public.counts (company_id, warehouse_id, stock_take_id, stock_taker_session_id, product_id, submitted_by, count_type, pallets, layers, cases, units, total_units, idempotency_key) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030','BULK',-1,0,0,0,0,'c0000000-0000-4000-8000-000000000002')$$, '23514', 'new row for relation "counts" violates check constraint "counts_pallets_check"', 'negative quantities are rejected');
select throws_ok($$insert into public.counts (company_id, warehouse_id, stock_take_id, stock_taker_session_id, product_id, submitted_by, count_type, pallets, layers, cases, units, total_units, idempotency_key) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030','BULK',0,0,0,0,0,'c0000000-0000-4000-8000-000000000001')$$, '23505', 'duplicate key value violates unique constraint "counts_idempotency_key_key"', 'duplicate idempotency keys are rejected by the database');
select throws_ok($$insert into public.counts (company_id, warehouse_id, stock_take_id, stock_taker_session_id, product_id, submitted_by, count_type, pallets, layers, cases, units, total_units, idempotency_key) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','b1000000-0000-4000-8000-000000000001','b4000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000040','BULK',0,0,0,0,0,'c0000000-0000-4000-8000-000000000003')$$, '23503', 'insert or update on table "counts" violates foreign key constraint "counts_session_scope_fkey"', 'count session scope cannot cross tenants');

insert into public.count_flags (id, company_id, warehouse_id, stock_take_id, count_id, flag_type)
values ('aa900000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001','DUPLICATE_PRODUCT_COUNT_TYPE');
select throws_ok($$update public.count_flags set status = 'RESOLVED' where id = 'aa900000-0000-4000-8000-000000000001'$$, '55000', 'count_flags rows are immutable.', 'flags cannot be mutated directly');
select throws_ok($$delete from public.count_flags where id = 'aa900000-0000-4000-8000-000000000001'$$, '55000', 'count_flags rows are immutable.', 'flags cannot be deleted');

select ok(has_function_privilege('authenticated', 'public.submit_count(jsonb)', 'EXECUTE'), 'authenticated can call submit_count');
select ok(has_function_privilege('authenticated', 'public.sync_counts_batch(jsonb)', 'EXECUTE'), 'authenticated can call batch sync');
select ok(not has_function_privilege('anon', 'public.submit_count(jsonb)', 'EXECUTE'), 'anon cannot submit counts');
select ok(not has_table_privilege('authenticated', 'public.counts', 'INSERT'), 'authenticated cannot insert counts directly');
select ok(not has_table_privilege('authenticated', 'public.counts', 'UPDATE'), 'authenticated cannot update counts');
select ok(not has_table_privilege('authenticated', 'public.count_flags', 'INSERT'), 'authenticated cannot insert flags directly');
select has_index('public', 'counts', 'counts_session_scope_idx', 'session foreign key is covered');
select has_index('public', 'count_flags', 'count_flags_count_scope_idx', 'flag count foreign key is covered');
select has_index('public', 'count_flags', 'count_flags_company_resolver_idx', 'flag resolver foreign key is covered');

select * from finish();
rollback;
