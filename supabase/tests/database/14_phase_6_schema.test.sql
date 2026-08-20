begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

select has_type('public', 'variance_threshold_source', 'variance threshold source type exists');
select has_type('public', 'recount_batch_status', 'recount batch status type exists');
select has_type('public', 'recount_task_status', 'recount task status type exists');
select has_column('public', 'company_settings', 'default_variance_threshold_units', 'company fallback threshold exists');
select has_table('public', 'warehouse_settings', 'warehouse threshold settings exists');
select has_table('public', 'product_warehouse_settings', 'product threshold settings exists');
select has_table('public', 'recount_batches', 'recount batches exists');
select has_table('public', 'recount_tasks', 'recount tasks exists');
select has_table('public', 'recount_counts', 'recount results exists');

select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.warehouse_settings'::regclass), 'warehouse settings has enabled and forced RLS');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.product_warehouse_settings'::regclass), 'product settings has enabled and forced RLS');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.recount_batches'::regclass), 'recount batches has enabled and forced RLS');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.recount_tasks'::regclass), 'recount tasks has enabled and forced RLS');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.recount_counts'::regclass), 'recount results has enabled and forced RLS');

select has_index('public', 'recount_tasks', 'recount_tasks_one_open_product_idx', 'only one open task is allowed per stock take and product');
select has_index('public', 'recount_counts', 'recount_counts_idempotency_key_key', 'recount idempotency keys are unique');
select has_index('public', 'recount_counts', 'recount_counts_task_scope_idx', 'recount task foreign key is covered');
select has_index('public', 'recount_counts', 'recount_counts_session_scope_idx', 'recount session foreign key is covered');
select has_index('public', 'product_warehouse_settings', 'product_warehouse_settings_warehouse_scope_idx', 'product setting warehouse scope foreign key is covered');
select has_index('public', 'product_warehouse_settings', 'product_warehouse_settings_product_scope_idx', 'product setting product scope foreign key is covered');
select has_index('public', 'recount_batches', 'recount_batches_stock_take_scope_idx', 'recount batch stock-take scope foreign key is covered');

select throws_ok(
  $$insert into public.warehouse_settings (warehouse_id, company_id, variance_threshold_units) values ('a1000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',-1)$$,
  '23514',
  'new row for relation "warehouse_settings" violates check constraint "warehouse_settings_variance_threshold_units_check"',
  'negative thresholds are rejected'
);

update public.stock_takes set status = 'READY' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'ACTIVE' where id = 'a4000000-0000-4000-8000-000000000001';
insert into public.stock_taker_sessions (id, company_id, warehouse_id, stock_take_id, user_id)
values ('ae000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030');
insert into public.recount_batches (id, company_id, warehouse_id, stock_take_id, created_by, status, completed_at)
values ('ae100000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000020','COMPLETED',now());
insert into public.recount_tasks (
  id, company_id, warehouse_id, stock_take_id, recount_batch_id, product_id, brand_id,
  source_physical_units, source_signed_variance_units, source_absolute_variance_units,
  effective_threshold_units, threshold_source, claimed_by, claimed_at, status, completed_at
) values (
  'ae200000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001','ae100000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000001',700,-20,20,5,'COMPANY','10000000-0000-4000-8000-000000000030',now(),'COMPLETED',now()
);
insert into public.recount_counts (
  id, company_id, warehouse_id, stock_take_id, recount_task_id, stock_taker_session_id,
  product_id, submitted_by, pallets, layers, cases, units, total_units, idempotency_key
) values (
  'ae300000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001','ae200000-0000-4000-8000-000000000001','ae000000-0000-4000-8000-000000000001',
  'a3000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030',0,0,0,700,700,'ae400000-0000-4000-8000-000000000001'
);
select throws_ok($$update public.recount_counts set units = 1 where id = 'ae300000-0000-4000-8000-000000000001'$$, '55000', 'recount_counts rows are immutable.', 'recount results reject updates');
select throws_ok($$delete from public.recount_counts where id = 'ae300000-0000-4000-8000-000000000001'$$, '55000', 'recount_counts rows are immutable.', 'recount results reject deletes');

select ok(has_function_privilege('authenticated', 'public.get_manager_progress(uuid,uuid,uuid)', 'EXECUTE'), 'authenticated can call manager progress RPC');
select ok(has_function_privilege('authenticated', 'public.get_recount_work()', 'EXECUTE'), 'authenticated can call blind recount work RPC');
select ok(has_function_privilege('authenticated', 'public.submit_recount(jsonb)', 'EXECUTE'), 'authenticated can call recount submission RPC');
select ok(not has_function_privilege('anon', 'public.submit_recount(jsonb)', 'EXECUTE'), 'anon cannot submit recounts');
select ok(not has_table_privilege('authenticated', 'public.recount_tasks', 'INSERT'), 'authenticated cannot insert recount tasks directly');
select ok(not has_table_privilege('authenticated', 'public.recount_tasks', 'UPDATE'), 'authenticated cannot update recount tasks directly');
select ok(not has_table_privilege('authenticated', 'public.recount_counts', 'INSERT'), 'authenticated cannot insert recount results directly');
select ok(not has_table_privilege('authenticated', 'public.recount_counts', 'UPDATE'), 'authenticated cannot update recount results directly');
select ok(not has_table_privilege('authenticated', 'public.recount_counts', 'DELETE'), 'authenticated cannot delete recount results directly');
select ok(not has_function_privilege('authenticated', 'private.effective_variance_threshold(uuid,uuid,uuid)', 'EXECUTE'), 'private threshold resolver is not directly callable');
select ok(not has_function_privilege('authenticated', 'private.stock_take_variances(uuid)', 'EXECUTE'), 'private variance derivation is not directly callable');

select * from finish();
rollback;
