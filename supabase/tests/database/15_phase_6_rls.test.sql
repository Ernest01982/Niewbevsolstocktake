begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

create function private.test_set_auth_phase_6_rls(test_user_id uuid, anonymous_user boolean default false)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  perform set_config('request.jwt.claim.sub', test_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', test_user_id, 'role', 'authenticated', 'is_anonymous', anonymous_user
  )::text, true);
end;
$$;
grant execute on function private.test_set_auth_phase_6_rls(uuid, boolean) to authenticated;

update public.stock_takes set status = 'READY' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'ACTIVE' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'RECOUNT' where id = 'a4000000-0000-4000-8000-000000000001';
insert into public.stock_taker_sessions (id, company_id, warehouse_id, stock_take_id, user_id)
values ('af000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030');
insert into public.warehouse_settings (warehouse_id, company_id, variance_threshold_units, variance_threshold_active, updated_by)
values ('a1000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',5,true,'10000000-0000-4000-8000-000000000010');
insert into public.product_warehouse_settings (company_id, warehouse_id, product_id, variance_threshold_units, variance_threshold_active, updated_by)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001',2,true,'10000000-0000-4000-8000-000000000010');

insert into public.recount_batches (id, company_id, warehouse_id, stock_take_id, created_by, status, completed_at)
values ('af100000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000020','COMPLETED',now());
insert into public.recount_tasks (
  id, company_id, warehouse_id, stock_take_id, recount_batch_id, product_id, brand_id,
  source_physical_units, source_signed_variance_units, source_absolute_variance_units,
  effective_threshold_units, threshold_source, claimed_by, claimed_at, status, completed_at
) values (
  'af200000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001','af100000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000001',700,-20,20,2,'PRODUCT','10000000-0000-4000-8000-000000000030',now(),'COMPLETED',now()
);
insert into public.recount_counts (
  id, company_id, warehouse_id, stock_take_id, recount_task_id, stock_taker_session_id,
  product_id, submitted_by, pallets, layers, cases, units, total_units, idempotency_key
) values (
  'af300000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001','af200000-0000-4000-8000-000000000001','af000000-0000-4000-8000-000000000001',
  'a3000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030',0,0,0,700,700,'af400000-0000-4000-8000-000000000001'
);
insert into public.recount_batches (id, company_id, warehouse_id, stock_take_id, created_by)
values ('af100000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000020');
insert into public.recount_tasks (
  id, company_id, warehouse_id, stock_take_id, recount_batch_id, product_id, brand_id,
  source_physical_units, source_signed_variance_units, source_absolute_variance_units,
  effective_threshold_units, threshold_source
) values (
  'af200000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001','af100000-0000-4000-8000-000000000002','a3000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000001',700,-20,20,2,'PRODUCT'
);

set local role authenticated;
select private.test_set_auth_phase_6_rls('10000000-0000-4000-8000-000000000030');
select is((select count(*)::integer from public.warehouse_settings), 0, 'stock taker cannot read warehouse thresholds directly');
select is((select count(*)::integer from public.product_warehouse_settings), 0, 'stock taker cannot read product thresholds directly');
select is((select count(*)::integer from public.recount_batches), 0, 'stock taker cannot read recount batches directly');
select is((select count(*)::integer from public.recount_tasks), 0, 'stock taker cannot read management recount tasks directly');
select is((select count(*)::integer from public.recount_counts), 1, 'stock taker sees only own submitted recount result');
select is(public.get_recount_work() ->> 'success', 'true', 'stock taker can request blind recount work');
select is(jsonb_array_length(public.get_recount_work() -> 'tasks'), 1, 'stock taker sees available blind work');
select ok(
  not ((public.get_recount_work() #> '{tasks,0}') ?| array[
    'source_physical_units','source_signed_variance_units','source_absolute_variance_units',
    'effective_threshold_units','threshold_source','snapshot_units','variance_units'
  ]),
  'blind work omits source counts, SOH, variance, and threshold fields'
);

select private.test_set_auth_phase_6_rls('10000000-0000-4000-8000-000000000020');
select is((select count(*)::integer from public.warehouse_settings), 1, 'allocated manager sees warehouse thresholds');
select is((select count(*)::integer from public.product_warehouse_settings), 1, 'allocated manager sees product thresholds');
select is((select count(*)::integer from public.recount_batches), 2, 'allocated manager sees recount batches');
select is((select count(*)::integer from public.recount_tasks), 2, 'allocated manager sees recount tasks');
select is((select count(*)::integer from public.recount_counts), 1, 'allocated manager sees recount results');
select private.test_set_auth_phase_6_rls('10000000-0000-4000-8000-000000000010');
select is((select count(*)::integer from public.recount_tasks), 2, 'allocated admin sees recount tasks');
select private.test_set_auth_phase_6_rls('10000000-0000-4000-8000-000000000001');
select is((select count(*)::integer from public.recount_tasks), 2, 'authorised Super Admin sees company recount tasks');
select private.test_set_auth_phase_6_rls('10000000-0000-4000-8000-000000000040');
select is((select count(*)::integer from public.recount_tasks), 0, 'other company admin sees no recount tasks');
select private.test_set_auth_phase_6_rls('10000000-0000-4000-8000-000000000002');
select is((select count(*)::integer from public.recount_tasks), 0, 'unallocated platform admin sees no recount tasks');
select private.test_set_auth_phase_6_rls('10000000-0000-4000-8000-000000000030', true);
select is((select count(*)::integer from public.recount_tasks), 0, 'anonymous-auth user sees no recount tasks');

select throws_ok(
  $$insert into public.recount_tasks (company_id,warehouse_id,stock_take_id,recount_batch_id,product_id,source_physical_units,source_signed_variance_units,source_absolute_variance_units,effective_threshold_units,threshold_source) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','af100000-0000-4000-8000-000000000002','a3000000-0000-4000-8000-000000000001',0,0,0,0,'COMPANY')$$,
  '42501', 'permission denied for table recount_tasks', 'authenticated cannot insert recount tasks directly'
);
select throws_ok(
  $$update public.recount_tasks set status = 'ASSIGNED' where id = 'af200000-0000-4000-8000-000000000002'$$,
  '42501', 'permission denied for table recount_tasks', 'authenticated cannot update recount tasks directly'
);

reset role;
set local role anon;
select throws_ok($$select * from public.recount_tasks$$, '42501', 'permission denied for table recount_tasks', 'anon cannot query recount tasks');
select ok(not has_function_privilege('anon', 'public.get_recount_work()', 'EXECUTE'), 'anon cannot request recount work');

reset role;
select * from finish();
rollback;
