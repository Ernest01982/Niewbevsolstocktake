begin;
create extension if not exists pgtap with schema extensions;
select plan(56);

create function private.test_set_auth_phase_6_ops(test_user_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  perform set_config('request.jwt.claim.sub', test_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', test_user_id, 'role', 'authenticated', 'is_anonymous', false
  )::text, true);
end;
$$;
grant execute on function private.test_set_auth_phase_6_ops(uuid) to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000','10000000-0000-4000-8000-000000000031',
  'authenticated','authenticated','taker.two@example.test',
  '{"provider":"email","providers":["email"]}','{}',now(),now()
);
insert into public.profiles (user_id, display_name)
values ('10000000-0000-4000-8000-000000000031','Warehouse A Stock Taker Two');
insert into public.company_memberships (company_id, user_id, role, status)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','10000000-0000-4000-8000-000000000031','stock_taker','active');
insert into public.warehouse_memberships (company_id, warehouse_id, user_id, role, status)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000031','stock_taker','active');

update public.stock_takes set status = 'READY' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'ACTIVE' where id = 'a4000000-0000-4000-8000-000000000001';
insert into public.stock_snapshot_lines (
  id, company_id, warehouse_id, stock_take_id, product_id, import_job_id,
  quantity_on_hand, source_row_number, source_row, snapshot_as_of
) values (
  'ba700000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001',
  'a3000000-0000-4000-8000-000000000002','a5000000-0000-4000-8000-000000000002',
  10,3,'{"Item":"A-002","SOH":"10"}','2026-08-12T08:00:00+02:00'
);
insert into public.stock_taker_sessions (id, company_id, warehouse_id, stock_take_id, user_id)
values
  ('ba800000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030'),
  ('ba800000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000031');
insert into public.counts (
  id, company_id, warehouse_id, stock_take_id, stock_taker_session_id, product_id,
  submitted_by, count_type, pallets, layers, cases, units, total_units, idempotency_key
) values
  ('ba900000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','ba800000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030','BULK',0,0,0,600,600,'baa00000-0000-4000-8000-000000000001'),
  ('ba900000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','ba800000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030','BULK',0,0,0,100,100,'baa00000-0000-4000-8000-000000000002'),
  ('ba900000-0000-4000-8000-000000000003','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','ba800000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000030','BULK',0,0,0,12,12,'baa00000-0000-4000-8000-000000000003');
insert into public.count_flags (id, company_id, warehouse_id, stock_take_id, count_id, flag_type)
values ('bab00000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','ba900000-0000-4000-8000-000000000002','DUPLICATE_PRODUCT_COUNT_TYPE');

set local role authenticated;
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000020');
select is(public.get_manager_progress('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') ->> 'success', 'true', 'manager progress succeeds');
select is((public.get_manager_progress('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') ->> 'snapshot_products')::integer, 2, 'progress denominator is the snapshot product universe');
select is((public.get_manager_progress('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') ->> 'covered_products')::integer, 2, 'duplicate records do not inflate covered products');
select is((public.get_manager_progress('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') ->> 'progress_percent')::numeric, 100::numeric, 'progress is capped at 100 percent');
select is((public.get_manager_progress('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') ->> 'initial_count_records')::integer, 3, 'all immutable initial records remain visible to management');

select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000030');
select is(public.get_manager_progress('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{error,code}', 'forbidden', 'stock taker cannot access manager progress');
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000020');
select is(public.set_company_variance_threshold('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',5) #>> '{error,code}', 'forbidden', 'manager cannot change company threshold policy');

select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000010');
select is(public.set_company_variance_threshold('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',5) ->> 'success', 'true', 'admin sets company fallback threshold');
select is(public.set_variance_threshold('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',10,true,null) ->> 'success', 'true', 'admin sets warehouse threshold');
select is(public.set_variance_threshold('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',3,true,'a3000000-0000-4000-8000-000000000001') ->> 'success', 'true', 'admin sets product threshold');
reset role;
select is((select count(*)::integer from public.audit_logs where action = 'variance_threshold.changed'), 3, 'threshold changes are audited');

set local role authenticated;
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000020');
select is(public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,0,threshold_source}', 'PRODUCT', 'product threshold has highest precedence');
select is((public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,0,effective_threshold_units}')::bigint, 3::bigint, 'product threshold value is effective');
select is((public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,0,absolute_variance_units}')::bigint, 20::bigint, 'variance is derived from summed immutable counts');
select is(public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,0,recount_required}', 'true', 'above-threshold product requires recount');
select is(public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,1,threshold_source}', 'WAREHOUSE', 'warehouse threshold applies without product override');
select is((public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,1,effective_threshold_units}')::bigint, 10::bigint, 'warehouse threshold value is effective');
select is(public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,1,recount_required}', 'false', 'within-threshold product does not require recount');

select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000010');
select is(public.set_variance_threshold('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',10,false,null) ->> 'success', 'true', 'admin can deactivate warehouse override');
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000020');
select is(public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,1,threshold_source}', 'COMPANY', 'company fallback applies when warehouse override is inactive');
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000010');
select is(public.set_variance_threshold('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',10,true,null) ->> 'success', 'true', 'admin can reactivate warehouse override');

select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000020');
select is(public.create_recount_batch('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001',null,null,'a3000000-0000-4000-8000-000000000001',null) ->> 'success', 'true', 'manager creates variance-driven recount work');
select is((select count(*)::integer from public.recount_tasks), 1, 'one filtered recount task is generated');
select is((select status::text from public.stock_takes where id = 'a4000000-0000-4000-8000-000000000001'), 'RECOUNT', 'recount creation moves stock take to RECOUNT');
select is((public.assign_recount_tasks('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',array[(select id from public.recount_tasks)]::uuid[],'10000000-0000-4000-8000-000000000030') ->> 'changed_count')::integer, 1, 'manager assigns recount task to an active stock taker');
select is((select status::text from public.recount_tasks), 'ASSIGNED', 'assigned task records assigned state');
select is((public.assign_recount_tasks('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',array[(select id from public.recount_tasks)]::uuid[],null) ->> 'changed_count')::integer, 1, 'manager can return assigned task to the pool');
select is((select status::text from public.recount_tasks), 'UNASSIGNED', 'unassigned task returns to claimable pool');
select is(public.create_recount_batch('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001',null,null,'a3000000-0000-4000-8000-000000000001',null) #>> '{error,code}', 'no_recount_candidates', 'partial unique open-task rule prevents duplicate recount work');
create temporary table phase6_task_ref as select id from public.recount_tasks;

select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000030');
select is(jsonb_array_length(public.get_recount_work() -> 'tasks'), 1, 'stock taker sees one blind pool task');
select ok(not ((public.get_recount_work() #> '{tasks,0}') ?| array['source_physical_units','source_signed_variance_units','source_absolute_variance_units','effective_threshold_units','threshold_source','snapshot_units']), 'stock taker work remains blind');
select is(public.claim_recount_task((select id from phase6_task_ref)) ->> 'success', 'true', 'first claimant atomically claims pool task');
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000031');
select is(public.claim_recount_task((select id from phase6_task_ref)) #>> '{error,code}', 'task_unavailable', 'second claimant loses the claim conflict');
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000030');
select is(public.claim_recount_task((select id from phase6_task_ref)) ->> 'existing', 'true', 'winning claimant can retry claim idempotently');
select is(public.submit_recount(jsonb_build_object(
  'recount_task_id',(select id from phase6_task_ref),'stock_taker_session_id','ba800000-0000-4000-8000-000000000001',
  'pallets',-1,'layers',0,'cases',0,'units',0,'idempotency_key','bac00000-0000-4000-8000-000000000001'
)) #>> '{error,code}', 'invalid_quantity', 'negative recount quantity is rejected');
select is(public.submit_recount(jsonb_build_object(
  'recount_task_id',(select id from phase6_task_ref),'stock_taker_session_id','ba800000-0000-4000-8000-000000000001',
  'pallets',1,'layers',0,'cases',0,'units',5,'duration_ms',9000,'idempotency_key','bac00000-0000-4000-8000-000000000002'
)) ->> 'success', 'true', 'claimed blind recount is submitted');
select is((select total_units from public.recount_counts), 725::bigint, 'server calculates canonical full-product recount total');
select is(public.submit_recount(jsonb_build_object(
  'recount_task_id',(select id from phase6_task_ref),'stock_taker_session_id','ba800000-0000-4000-8000-000000000001',
  'pallets',0,'layers',0,'cases',0,'units',0,'idempotency_key','bac00000-0000-4000-8000-000000000002'
)) ->> 'existing', 'true', 'recount retry returns the existing immutable result');
select is(public.submit_recount(jsonb_build_object(
  'recount_task_id','bac00000-0000-4000-8000-000000000099','stock_taker_session_id','ba800000-0000-4000-8000-000000000001',
  'pallets',0,'layers',0,'cases',0,'units',0,'idempotency_key','bac00000-0000-4000-8000-000000000002'
)) #>> '{error,code}', 'idempotency_conflict', 'an idempotency key cannot acknowledge a different recount task');
select is((select count(*)::integer from public.recount_counts), 1, 'idempotent retry creates no duplicate result');
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000020');
select is((select status::text from public.recount_tasks), 'COMPLETED', 'successful recount completes its task');
select is((select status::text from public.recount_batches), 'COMPLETED', 'last task completion closes its batch');

reset role;
select throws_ok($$update public.recount_counts set units = 0$$, '55000', 'recount_counts rows are immutable.', 'submitted recount result remains immutable');
set local role authenticated;
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000020');
select is((public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,0,physical_units}')::bigint, 725::bigint, 'latest recount replaces effective physical units');
select is((public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,0,initial_physical_units}')::bigint, 700::bigint, 'initial immutable count history remains visible');
select is((public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,0,signed_variance_units}')::bigint, 5::bigint, 'variance is recalculated from latest recount');
select is(public.get_variances('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{variances,0,recount_status}', 'COMPLETED', 'management sees completed recount state');
select is(public.move_stock_take_to_review('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') ->> 'success', 'true', 'manager moves completed recount to review');

reset role;
insert into public.recount_batches (id, company_id, warehouse_id, stock_take_id, created_by)
values ('bad00000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000020');
insert into public.recount_tasks (
  id, company_id, warehouse_id, stock_take_id, recount_batch_id, product_id, brand_id,
  source_physical_units, source_signed_variance_units, source_absolute_variance_units,
  effective_threshold_units, threshold_source
) values (
  'bae00000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001','bad00000-0000-4000-8000-000000000002','a3000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000001',725,5,5,3,'PRODUCT'
);
set local role authenticated;
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000020');
select is(public.complete_stock_take('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{error,code}', 'recounts_outstanding', 'open recount blocks finalisation');

reset role;
update public.recount_tasks set status = 'COMPLETED', claimed_by = '10000000-0000-4000-8000-000000000030', claimed_at = now(), completed_at = now()
where id = 'bae00000-0000-4000-8000-000000000002';
update public.recount_batches set status = 'COMPLETED', completed_at = now() where id = 'bad00000-0000-4000-8000-000000000002';
set local role authenticated;
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000020');
select is(public.complete_stock_take('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') #>> '{error,code}', 'count_flags_outstanding', 'open duplicate flag blocks finalisation');
select is(public.resolve_count_flag('bab00000-0000-4000-8000-000000000001','   ') #>> '{error,code}', 'resolution_note_required', 'flag resolution requires a management note');
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000030');
select is(public.resolve_count_flag('bab00000-0000-4000-8000-000000000001','Reviewed duplicate') #>> '{error,code}', 'forbidden', 'stock taker cannot resolve count flag');
select private.test_set_auth_phase_6_ops('10000000-0000-4000-8000-000000000020');
select is(public.resolve_count_flag('bab00000-0000-4000-8000-000000000001','Reviewed duplicate records before finalisation.') ->> 'success', 'true', 'manager resolves count flag through controlled RPC');
select is(public.resolve_count_flag('bab00000-0000-4000-8000-000000000001','Reviewed duplicate records before finalisation.') ->> 'existing', 'true', 'flag resolution retry is idempotent');
select is(public.complete_stock_take('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') ->> 'success', 'true', 'manager completes after all guards are clear');
reset role;
select is((select count(*)::integer from public.audit_logs where action = 'count_flag.resolved' and entity_id = 'bab00000-0000-4000-8000-000000000001'), 1, 'controlled flag resolution is audited once');

select * from finish();
rollback;
