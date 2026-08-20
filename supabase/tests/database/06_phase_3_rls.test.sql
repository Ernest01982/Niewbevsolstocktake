begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

create function private.test_set_auth_phase_3(test_user_id uuid, anonymous_user boolean default false)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', test_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', test_user_id, 'role', 'authenticated', 'is_anonymous', anonymous_user
    )::text,
    true
  );
end;
$$;

grant execute on function private.test_set_auth_phase_3(uuid, boolean) to authenticated;

insert into public.stock_taker_sessions (
  id, company_id, warehouse_id, stock_take_id, user_id,
  status, started_at, last_active_at, ended_at
) values (
  'a8000000-0000-4000-8000-000000000010',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000030',
  'ENDED', now() - interval '1 hour', now(), now()
);

set local role authenticated;

select private.test_set_auth_phase_3('10000000-0000-4000-8000-000000000030');
select is((select count(*)::integer from public.stock_taker_sessions), 1, 'stock taker sees own session history');
select is((select count(*)::integer from public.company_settings), 0, 'stock taker sees no company settings');
select is((select count(*)::integer from public.stock_snapshot_lines), 0, 'stock taker still sees no SOH');

select private.test_set_auth_phase_3('10000000-0000-4000-8000-000000000020');
select is((select count(*)::integer from public.stock_taker_sessions), 1, 'manager sees sessions in allocated warehouse');
select is((select count(*)::integer from public.company_settings), 0, 'manager cannot read company-level reopen settings');
select is((select count(*)::integer from public.stock_taker_sessions where warehouse_id = 'a1000000-0000-4000-8000-000000000002'), 0, 'manager cannot see another warehouse session');

select private.test_set_auth_phase_3('10000000-0000-4000-8000-000000000010');
select is((select count(*)::integer from public.stock_taker_sessions), 1, 'allocated admin sees warehouse sessions');
select is((select count(*)::integer from public.company_settings), 1, 'admin sees own company settings');

select private.test_set_auth_phase_3('10000000-0000-4000-8000-000000000001');
select is((select count(*)::integer from public.stock_taker_sessions), 1, 'authorised Super Admin sees company sessions');
select is((select count(*)::integer from public.company_settings), 1, 'authorised Super Admin sees company settings');

select private.test_set_auth_phase_3('10000000-0000-4000-8000-000000000040');
select is((select count(*)::integer from public.stock_taker_sessions), 0, 'company B admin sees no company A sessions');
select is((select count(*)::integer from public.company_settings), 1, 'company B admin sees only company B settings');

select private.test_set_auth_phase_3('10000000-0000-4000-8000-000000000002');
select is((select count(*)::integer from public.stock_taker_sessions), 0, 'unallocated platform admin sees no sessions');
select is((select count(*)::integer from public.company_settings), 0, 'unallocated platform admin sees no settings');

select private.test_set_auth_phase_3('10000000-0000-4000-8000-000000000030', true);
select is((select count(*)::integer from public.stock_taker_sessions), 0, 'anonymous-auth user sees no sessions');

reset role;
select * from finish();
rollback;
