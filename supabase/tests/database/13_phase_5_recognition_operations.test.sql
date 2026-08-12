begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

create function private.test_set_auth_phase_5_operations(test_user_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  perform set_config('request.jwt.claim.sub', test_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', test_user_id, 'role', 'authenticated', 'is_anonymous', false
  )::text, true);
end;
$$;
grant execute on function private.test_set_auth_phase_5_operations(uuid) to authenticated;

update public.stock_takes set status = 'READY' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'ACTIVE' where id = 'a4000000-0000-4000-8000-000000000001';
insert into public.stock_taker_sessions (id, company_id, warehouse_id, stock_take_id, user_id)
values ('a8000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030');

set local role authenticated;
select private.test_set_auth_phase_5_operations('10000000-0000-4000-8000-000000000030');

create temporary table high_result as select public.record_recognition_event(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'idempotency_key','ae100000-0000-4000-8000-000000000001','provider','test-provider','model','test-model',
  'candidates',jsonb_build_array(jsonb_build_object('product_id','a3000000-0000-4000-8000-000000000001','confidence',0.91)),
  'captured_at',now()
)) as result;
select is((select result ->> 'success' from high_result), 'true', 'high-confidence event succeeds');
select is((select result ->> 'acknowledged' from high_result), 'true', 'recognition event receives durable acknowledgement');
select is((select result ->> 'confidence_tier' from high_result), 'HIGH', 'high threshold preselect tier is server classified');
select is((select (result ->> 'confidence')::numeric from high_result), 0.9100::numeric, 'top candidate confidence is normalized');
select is((select jsonb_array_length(candidate_products) from public.recognition_events where idempotency_key = 'ae100000-0000-4000-8000-000000000001'), 1, 'candidate products are persisted');

select is(public.record_recognition_event(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'idempotency_key','ae100000-0000-4000-8000-000000000002','provider','test','model','test',
  'candidates',jsonb_build_array(jsonb_build_object('product_id','a3000000-0000-4000-8000-000000000001','confidence',0.7))
)) ->> 'confidence_tier', 'MEDIUM', 'medium confidence returns candidate confirmation tier');
select is(public.record_recognition_event(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'idempotency_key','ae100000-0000-4000-8000-000000000003','provider','test','model','test',
  'candidates',jsonb_build_array(jsonb_build_object('product_id','a3000000-0000-4000-8000-000000000001','confidence',0.3))
)) ->> 'confidence_tier', 'LOW', 'low confidence requires manual search');
select is(public.record_recognition_event(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'idempotency_key','ae100000-0000-4000-8000-000000000004','provider','manual_fallback','model','none','candidates','[]'::jsonb
)) ->> 'confidence_tier', 'NO_MATCH', 'no-match response requires manual search');
select is(public.record_recognition_event(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'idempotency_key','ae100000-0000-4000-8000-000000000012','provider','test','model','test',
  'candidates',jsonb_build_array(
    jsonb_build_object('product_id','a3000000-0000-4000-8000-000000000002','confidence',0.2),
    jsonb_build_object('product_id','a3000000-0000-4000-8000-000000000001','confidence',0.9)
  )
)) ->> 'confidence_tier', 'HIGH', 'server classifies from the highest confidence regardless of provider order');
select is(
  (select candidate_products #>> '{0,product_id}' from public.recognition_events where idempotency_key = 'ae100000-0000-4000-8000-000000000012'),
  'a3000000-0000-4000-8000-000000000001',
  'server persists candidates in descending confidence order'
);

select is(public.record_recognition_event(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'idempotency_key','ae100000-0000-4000-8000-000000000005','provider','test','model','test',
  'candidates',jsonb_build_array(jsonb_build_object('product_id','b3000000-0000-4000-8000-000000000001','confidence',0.9))
)) #>> '{error,code}', 'invalid_candidates', 'cross-company recognition candidate is rejected');
select is(public.record_recognition_event(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'idempotency_key','ae100000-0000-4000-8000-000000000006','provider','test','model','test',
  'candidates',jsonb_build_array(
    jsonb_build_object('product_id','a3000000-0000-4000-8000-000000000001','confidence',0.9),
    jsonb_build_object('product_id','a3000000-0000-4000-8000-000000000002','confidence',0.8),
    jsonb_build_object('product_id','a3000000-0000-4000-8000-000000000001','confidence',0.7),
    jsonb_build_object('product_id','a3000000-0000-4000-8000-000000000002','confidence',0.6)
  )
)) #>> '{error,code}', 'invalid_candidates', 'more than three candidates is rejected');

select is(public.record_recognition_event(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'idempotency_key','ae100000-0000-4000-8000-000000000001','provider','changed','model','changed','candidates','[]'::jsonb
)) ->> 'existing', 'true', 'recognition retry returns existing acknowledgement');
select is((select count(*)::integer from public.recognition_events where idempotency_key = 'ae100000-0000-4000-8000-000000000001'), 1, 'recognition retry creates no duplicate');

create temporary table confirmation_result as
select public.confirm_recognition_selection(
  (select (result ->> 'recognition_event_id')::uuid from high_result),
  'a3000000-0000-4000-8000-000000000001',
  'AUTO_PRESELECT'
) as result;
select is((select result ->> 'success' from confirmation_result), 'true', 'high-confidence candidate can be confirmed');
select is((select selected_product_id from public.recognition_events where idempotency_key = 'ae100000-0000-4000-8000-000000000001'), 'a3000000-0000-4000-8000-000000000001'::uuid, 'confirmed product is locked');
select is(public.confirm_recognition_selection(
  (select (result ->> 'recognition_event_id')::uuid from high_result),
  'a3000000-0000-4000-8000-000000000002',
  'MANUAL_SEARCH'
) #>> '{error,code}', 'selection_locked', 'a different second confirmation is rejected');

select is(public.record_recognition_event(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'idempotency_key','ae100000-0000-4000-8000-000000000007','provider','offline_manual_cache','model','cached-products-v1',
  'candidates','[]'::jsonb,'selected_product_id','a3000000-0000-4000-8000-000000000002','selection_method','MANUAL_SEARCH',
  'captured_at',now() - interval '1 day'
)) ->> 'success', 'true', 'offline cached manual selection can sync later');
select is((select selection_method::text from public.recognition_events where idempotency_key = 'ae100000-0000-4000-8000-000000000007'), 'MANUAL_SEARCH', 'offline manual selection method is logged');

create temporary table media_result as select public.record_recognition_event(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'idempotency_key','ae100000-0000-4000-8000-000000000008','provider','test','model','test','candidates','[]'::jsonb,
  'media_path','10000000-0000-4000-8000-000000000030/ae100000-0000-4000-8000-000000000008/capture.jpg',
  'captured_at',now()
)) as result;
grant select on table media_result to service_role;
select is((select media_status::text from public.recognition_events where idempotency_key = 'ae100000-0000-4000-8000-000000000008'), 'PENDING', 'stored media begins pending deletion');
select ok((select media_expires_at <= captured_at + interval '48 hours' from public.recognition_events where idempotency_key = 'ae100000-0000-4000-8000-000000000008'), 'media deadline is no later than 48 hours');

reset role;
set local role service_role;
create temporary table cleanup_claim as select public.claim_recognition_media_cleanup(10) as result;
select is((select jsonb_array_length(result -> 'items') from cleanup_claim), 1, 'cleanup worker claims due media');
select is(public.complete_recognition_media_cleanup(
  (select (result ->> 'recognition_event_id')::uuid from media_result), false, 'fixture delete failure'
) ->> 'media_status', 'FAILED', 'failed media deletion is retained for retry');
select is((select count(*)::integer from public.audit_logs where action = 'recognition_media.cleanup_failed'), 1, 'cleanup failure is surfaced in append-only audit');
select is(public.complete_recognition_media_cleanup(
  (select (result ->> 'recognition_event_id')::uuid from media_result), true, null
) ->> 'media_status', 'DELETED', 'successful retry marks media deleted');
select is((select media_status::text from public.recognition_events where idempotency_key = 'ae100000-0000-4000-8000-000000000008'), 'DELETED', 'deleted media state is persisted');

reset role;
set local role authenticated;
select private.test_set_auth_phase_5_operations('10000000-0000-4000-8000-000000000030');
create temporary table batch_result as select public.sync_recognition_events_batch(jsonb_build_array(
  jsonb_build_object('company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001','stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001','idempotency_key','ae100000-0000-4000-8000-000000000009','provider','offline_manual_cache','model','cached-products-v1','candidates','[]'::jsonb,'selected_product_id','a3000000-0000-4000-8000-000000000001','selection_method','MANUAL_SEARCH'),
  jsonb_build_object('company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001','stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001','idempotency_key','ae100000-0000-4000-8000-000000000010','provider','offline_manual_cache','model','cached-products-v1','candidates',jsonb_build_array(jsonb_build_object('product_id','b3000000-0000-4000-8000-000000000001','confidence',0.9)))
)) as result;
select is((select (result #>> '{totals,total}')::integer from batch_result), 2, 'recognition batch reports total records');
select is((select (result #>> '{totals,acknowledged}')::integer from batch_result), 1, 'recognition batch acknowledges successful records individually');
select is((select (result #>> '{totals,failed}')::integer from batch_result), 1, 'recognition batch preserves partial failures');
select is((select count(*)::integer from public.recognition_events where idempotency_key = 'ae100000-0000-4000-8000-000000000009'), 1, 'successful recognition batch record persists');

select private.test_set_auth_phase_5_operations('10000000-0000-4000-8000-000000000020');
select is(public.record_recognition_event(jsonb_build_object(
  'company_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','warehouse_id','a1000000-0000-4000-8000-000000000001',
  'stock_take_id','a4000000-0000-4000-8000-000000000001','stock_taker_session_id','a8000000-0000-4000-8000-000000000001',
  'idempotency_key','ae100000-0000-4000-8000-000000000011','provider','forged','model','forged','candidates','[]'::jsonb
)) #>> '{error,code}', 'recognition_closed', 'manager cannot record through another user session');

select * from finish();
rollback;
