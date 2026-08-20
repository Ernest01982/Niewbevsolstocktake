begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

create function private.test_set_auth_phase_4(test_user_id uuid, anonymous_user boolean default false)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  perform set_config('request.jwt.claim.sub', test_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', test_user_id, 'role', 'authenticated', 'is_anonymous', anonymous_user
  )::text, true);
end;
$$;
grant execute on function private.test_set_auth_phase_4(uuid, boolean) to authenticated;

update public.stock_takes set status = 'READY' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'ACTIVE' where id = 'a4000000-0000-4000-8000-000000000001';
insert into public.stock_taker_sessions (id, company_id, warehouse_id, stock_take_id, user_id)
values ('a8000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030');
insert into public.counts (
  id, company_id, warehouse_id, stock_take_id, stock_taker_session_id, product_id,
  submitted_by, count_type, pallets, layers, cases, units, total_units, idempotency_key
) values (
  'a9000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000030','BULK',1,0,0,0,720,'c0000000-0000-4000-8000-000000000001'
);
insert into public.count_flags (company_id, warehouse_id, stock_take_id, count_id, flag_type)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001','DUPLICATE_PRODUCT_COUNT_TYPE');

set local role authenticated;
select private.test_set_auth_phase_4('10000000-0000-4000-8000-000000000030');
select is((select count(*)::integer from public.counts), 1, 'stock taker sees own submitted counts');
select is((select count(*)::integer from public.count_flags), 0, 'stock taker sees no duplicate flags');
select is((select count(*)::integer from public.stock_snapshot_lines), 0, 'stock taker still sees no SOH');

select private.test_set_auth_phase_4('10000000-0000-4000-8000-000000000020');
select is((select count(*)::integer from public.counts), 1, 'manager sees allocated warehouse counts');
select is((select count(*)::integer from public.count_flags), 1, 'manager sees allocated warehouse flags');
select is((select count(*)::integer from public.counts where warehouse_id = 'a1000000-0000-4000-8000-000000000002'), 0, 'manager sees no other warehouse counts');

select private.test_set_auth_phase_4('10000000-0000-4000-8000-000000000010');
select is((select count(*)::integer from public.counts), 1, 'allocated admin sees warehouse counts');
select is((select count(*)::integer from public.count_flags), 1, 'allocated admin sees warehouse flags');

select private.test_set_auth_phase_4('10000000-0000-4000-8000-000000000001');
select is((select count(*)::integer from public.counts), 1, 'authorised Super Admin sees company counts');
select is((select count(*)::integer from public.count_flags), 1, 'authorised Super Admin sees company flags');

select private.test_set_auth_phase_4('10000000-0000-4000-8000-000000000040');
select is((select count(*)::integer from public.counts), 0, 'company B admin sees no company A counts');
select is((select count(*)::integer from public.count_flags), 0, 'company B admin sees no company A flags');

select private.test_set_auth_phase_4('10000000-0000-4000-8000-000000000002');
select is((select count(*)::integer from public.counts), 0, 'unallocated platform admin sees no counts');
select is((select count(*)::integer from public.count_flags), 0, 'unallocated platform admin sees no flags');

select private.test_set_auth_phase_4('10000000-0000-4000-8000-000000000030', true);
select is((select count(*)::integer from public.counts), 0, 'anonymous-auth user sees no counts');
select is((select count(*)::integer from public.count_flags), 0, 'anonymous-auth user sees no flags');

reset role;
select * from finish();
rollback;
