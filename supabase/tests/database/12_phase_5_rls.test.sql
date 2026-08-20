begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

create function private.test_set_auth_phase_5(test_user_id uuid, anonymous_user boolean default false)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  perform set_config('request.jwt.claim.sub', test_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', test_user_id, 'role', 'authenticated', 'is_anonymous', anonymous_user
  )::text, true);
end;
$$;
grant execute on function private.test_set_auth_phase_5(uuid, boolean) to authenticated;

update public.stock_takes set status = 'READY' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'ACTIVE' where id = 'a4000000-0000-4000-8000-000000000001';
insert into public.stock_taker_sessions (id, company_id, warehouse_id, stock_take_id, user_id)
values ('a8000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030');
insert into public.recognition_events (
  id, idempotency_key, company_id, warehouse_id, stock_take_id,
  stock_taker_session_id, user_id, provider, model, confidence,
  confidence_tier, candidate_products, captured_at
) values (
  'ad000000-0000-4000-8000-000000000001','ad100000-0000-4000-8000-000000000001',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000030','test','test-model',0.9,'HIGH',
  '[{"product_id":"a3000000-0000-4000-8000-000000000001","confidence":0.9}]',now()
);

set local role authenticated;
select private.test_set_auth_phase_5('10000000-0000-4000-8000-000000000030');
select is((select count(*)::integer from public.recognition_events), 1, 'stock taker sees own recognition events');
select is((select count(*)::integer from public.stock_snapshot_lines), 0, 'stock taker still sees no SOH');
select throws_ok(
  $$insert into public.recognition_events (idempotency_key,company_id,warehouse_id,stock_take_id,stock_taker_session_id,user_id,provider,model,confidence_tier,captured_at) values ('ad100000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030','forged','forged','NO_MATCH',now())$$,
  '42501',
  'permission denied for table recognition_events',
  'stock taker cannot insert recognition events directly'
);
select throws_ok(
  $$update public.recognition_events set provider = 'forged' where id = 'ad000000-0000-4000-8000-000000000001'$$,
  '42501',
  'permission denied for table recognition_events',
  'stock taker cannot update recognition events directly'
);
select throws_ok(
  $$delete from public.recognition_events where id = 'ad000000-0000-4000-8000-000000000001'$$,
  '42501',
  'permission denied for table recognition_events',
  'stock taker cannot delete recognition events'
);

select private.test_set_auth_phase_5('10000000-0000-4000-8000-000000000020');
select is((select count(*)::integer from public.recognition_events), 1, 'allocated manager sees warehouse recognition events');
select private.test_set_auth_phase_5('10000000-0000-4000-8000-000000000010');
select is((select count(*)::integer from public.recognition_events), 1, 'allocated admin sees warehouse recognition events');
select private.test_set_auth_phase_5('10000000-0000-4000-8000-000000000001');
select is((select count(*)::integer from public.recognition_events), 1, 'authorised Super Admin sees company recognition events');
select private.test_set_auth_phase_5('10000000-0000-4000-8000-000000000040');
select is((select count(*)::integer from public.recognition_events), 0, 'other company admin sees no recognition events');
select private.test_set_auth_phase_5('10000000-0000-4000-8000-000000000002');
select is((select count(*)::integer from public.recognition_events), 0, 'unallocated platform admin sees no recognition events');
select private.test_set_auth_phase_5('10000000-0000-4000-8000-000000000030', true);
select is((select count(*)::integer from public.recognition_events), 0, 'anonymous-auth user sees no recognition events');

reset role;
set local role anon;
select throws_ok(
  $$select * from public.recognition_events$$,
  '42501',
  'permission denied for table recognition_events',
  'anon cannot query recognition events'
);
select ok(not has_function_privilege('anon', 'public.record_recognition_event(jsonb)', 'EXECUTE'), 'anon cannot record recognition events');
select ok(not has_function_privilege('authenticated', 'public.complete_recognition_media_cleanup(uuid,boolean,text)', 'EXECUTE'), 'authenticated cannot complete cleanup');
select ok(not has_table_privilege('authenticated', 'public.recognition_events', 'UPDATE'), 'authenticated has no recognition update grant');

reset role;
select * from finish();
rollback;
