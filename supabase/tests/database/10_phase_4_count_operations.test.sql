begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

create function private.test_set_auth_phase_4_count(test_user_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  perform set_config('request.jwt.claim.sub', test_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', test_user_id, 'role', 'authenticated', 'is_anonymous', false
  )::text, true);
end;
$$;
grant execute on function private.test_set_auth_phase_4_count(uuid) to authenticated;

update public.stock_takes set status = 'READY' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'ACTIVE' where id = 'a4000000-0000-4000-8000-000000000001';
insert into public.stock_taker_sessions (id, company_id, warehouse_id, stock_take_id, user_id)
values ('a8000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030');

set local role authenticated;
select private.test_set_auth_phase_4_count('10000000-0000-4000-8000-000000000030');

create temporary table first_count_result as select public.submit_count(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'product_id','a3000000-0000-4000-8000-000000000001','count_type','BULK',
  'pallets',1,'layers',2,'cases',3,'units',4,'duration_ms',12500,
  'idempotency_key','c1000000-0000-4000-8000-000000000001'
)) as result;
select is((select result ->> 'success' from first_count_result), 'true', 'valid count succeeds');
select is((select result ->> 'acknowledged' from first_count_result), 'true', 'successful count receives durable acknowledgement');
select is((select (result ->> 'total_units')::bigint from first_count_result), 1000::bigint, 'server calculates canonical total units');
select is((select result ->> 'duplicate' from first_count_result), 'false', 'first product/type count is not duplicate');
select is((select total_units from public.counts where idempotency_key = 'c1000000-0000-4000-8000-000000000001'), 1000::bigint, 'calculated total is persisted');
select is((select duration_ms from public.counts where idempotency_key = 'c1000000-0000-4000-8000-000000000001'), 12500, 'count duration is persisted');
reset role;
select is((select count(*)::integer from public.audit_logs where action = 'count.submitted'), 1, 'successful count is audited');
set local role authenticated;

create temporary table retry_result as select public.submit_count(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'product_id','a3000000-0000-4000-8000-000000000001','count_type','BULK',
  'pallets',99,'layers',0,'cases',0,'units',0,'duration_ms',1,
  'idempotency_key','c1000000-0000-4000-8000-000000000001'
)) as result;
select is((select result ->> 'existing' from retry_result), 'true', 'idempotent retry returns existing acknowledgement');
select is((select count(*)::integer from public.counts), 1, 'idempotent retry does not duplicate the count');
reset role;
select is((select count(*)::integer from public.audit_logs where action = 'count.submitted'), 1, 'idempotent retry does not duplicate audit');
set local role authenticated;

create temporary table duplicate_result as select public.submit_count(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'product_id','a3000000-0000-4000-8000-000000000001','count_type','BULK',
  'pallets',0,'layers',0,'cases',1,'units',0,'duration_ms',5000,
  'idempotency_key','c1000000-0000-4000-8000-000000000002'
)) as result;
select is((select result ->> 'success' from duplicate_result), 'true', 'duplicate product/type count is preserved');
select is((select result ->> 'duplicate' from duplicate_result), 'true', 'duplicate response warns the client');
select is((select count(*)::integer from public.counts), 2, 'both valid duplicate counts remain immutable');
reset role;
select is((select count(*)::integer from public.count_flags), 1, 'duplicate count creates a manager flag');
set local role authenticated;

create temporary table pick_face_result as select public.submit_count(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'product_id','a3000000-0000-4000-8000-000000000001','count_type','PICK_FACE',
  'pallets',0,'layers',0,'cases',0,'units',6,'duration_ms',4000,
  'idempotency_key','c1000000-0000-4000-8000-000000000003'
)) as result;
select is((select result ->> 'duplicate' from pick_face_result), 'false', 'Bulk and Pick Face are separate legitimate counts');
reset role;
select is((select count(*)::integer from public.count_flags), 1, 'separate count type creates no duplicate flag');
set local role authenticated;

select is(public.submit_count(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'product_id','a3000000-0000-4000-8000-000000000002','count_type','BULK',
  'pallets',0,'layers',0,'cases',0,'units',0,'idempotency_key','c1000000-0000-4000-8000-000000000004'
)) ->> 'success', 'true', 'explicit all-zero physical count is valid');
select is(public.submit_count(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'product_id','a3000000-0000-4000-8000-000000000002','count_type','BULK',
  'pallets',0,'layers',0,'cases',1,'units',0,'idempotency_key','c1000000-0000-4000-8000-000000000005'
)) #>> '{error,code}', 'missing_packaging', 'count path requiring missing packaging is blocked');
select is(public.submit_count(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'product_id','a3000000-0000-4000-8000-000000000002','count_type','BULK',
  'pallets',0,'layers',0,'cases',0,'units',1.5,'idempotency_key','c1000000-0000-4000-8000-000000000006'
)) #>> '{error,code}', 'invalid_quantity', 'fractional quantity is rejected');

create temporary table batch_result as select public.sync_counts_batch(jsonb_build_array(
  jsonb_build_object('company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001','stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001','product_id','a3000000-0000-4000-8000-000000000002','count_type','PICK_FACE','pallets',0,'layers',0,'cases',0,'units',5,'idempotency_key','c1000000-0000-4000-8000-000000000007'),
  jsonb_build_object('company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001','stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001','product_id','ffffffff-ffff-4fff-8fff-ffffffffffff','count_type','BULK','pallets',0,'layers',0,'cases',0,'units',5,'idempotency_key','c1000000-0000-4000-8000-000000000008')
)) as result;
select is((select (result #>> '{totals,total}')::integer from batch_result), 2, 'batch reports total records');
select is((select (result #>> '{totals,acknowledged}')::integer from batch_result), 1, 'batch acknowledges successful records individually');
select is((select (result #>> '{totals,failed}')::integer from batch_result), 1, 'batch reports failed records individually');
select is((select result #>> '{results,1,error,code}' from batch_result), 'product_unavailable', 'partial batch retains structured record failure');
select is((select count(*)::integer from public.counts where idempotency_key = 'c1000000-0000-4000-8000-000000000007'), 1, 'partial batch commits successful record');
select is((select count(*)::integer from public.counts where idempotency_key = 'c1000000-0000-4000-8000-000000000008'), 0, 'partial batch does not create failed record');

select private.test_set_auth_phase_4_count('10000000-0000-4000-8000-000000000020');
select is(public.submit_count('{}'::jsonb) #>> '{error,code}', 'invalid_identity', 'manager cannot forge a valid count record');
select is(public.submit_count(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001','stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001','product_id','a3000000-0000-4000-8000-000000000001','count_type','BULK','pallets',0,'layers',0,'cases',0,'units',1,'idempotency_key','c1000000-0000-4000-8000-000000000009'
)) #>> '{error,code}', 'counting_closed', 'a manager cannot submit through another user session');

select is(public.move_stock_take_to_review('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') ->> 'success', 'true', 'manager moves stock take to review');
select is(public.resolve_count_flag(
  (select id from public.count_flags where stock_take_id = 'a4000000-0000-4000-8000-000000000001' and status = 'OPEN' limit 1),
  'Duplicate records reviewed before finalisation.'
) ->> 'success', 'true', 'manager resolves the duplicate flag before finalisation');
select is(public.complete_stock_take('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001') ->> 'success', 'true', 'manager completes stock take');
select private.test_set_auth_phase_4_count('10000000-0000-4000-8000-000000000030');
select is(public.submit_count(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001','stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001','product_id','a3000000-0000-4000-8000-000000000001','count_type','BULK','pallets',0,'layers',0,'cases',0,'units',1,'idempotency_key','c1000000-0000-4000-8000-000000000010'
)) #>> '{error,code}', 'counting_closed', 'COMPLETED stock take rejects late counts');

reset role;
select * from finish();
rollback;
