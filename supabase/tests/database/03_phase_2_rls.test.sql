begin;

create extension if not exists pgtap with schema extensions;

select plan(39);

create function private.test_set_auth_phase_2(test_user_id uuid, anonymous_user boolean default false)
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
      'sub', test_user_id,
      'role', 'authenticated',
      'is_anonymous', anonymous_user
    )::text,
    true
  );
end;
$$;

grant execute on function private.test_set_auth_phase_2(uuid, boolean) to authenticated;

set local role authenticated;

select private.test_set_auth_phase_2('10000000-0000-4000-8000-000000000030');
select is((select count(*)::integer from public.brands), 1, 'stock taker sees own company brands');
select is((select count(*)::integer from public.products), 2, 'stock taker sees own company products for offline cache');
select is((select count(*)::integer from public.stock_takes), 0, 'stock taker cannot query stock takes directly');
select is((select count(*)::integer from public.import_jobs), 0, 'stock taker sees no import jobs');
select is((select count(*)::integer from public.import_issues), 0, 'stock taker sees no import issues');
select is((select count(*)::integer from public.stock_snapshot_lines), 0, 'stock taker sees no SOH snapshot lines');
select is(
  (select count(*)::integer from public.products where company_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  0,
  'stock taker cannot query another company product'
);

select private.test_set_auth_phase_2('10000000-0000-4000-8000-000000000020');
select is((select count(*)::integer from public.brands), 1, 'manager sees own company brands');
select is((select count(*)::integer from public.products), 2, 'manager sees own company products');
select is((select count(*)::integer from public.stock_takes), 1, 'manager sees allocated warehouse stock take only');
select is((select count(*)::integer from public.import_jobs), 1, 'manager sees allocated warehouse snapshot import only');
select is((select count(*)::integer from public.import_issues), 1, 'manager sees allocated warehouse issues');
select is((select count(*)::integer from public.stock_snapshot_lines), 1, 'manager sees allocated warehouse SOH');
select is(
  (select count(*)::integer from public.stock_snapshot_lines where warehouse_id = 'a1000000-0000-4000-8000-000000000002'),
  0,
  'manager cannot query another warehouse SOH'
);
select is(
  (select count(*)::integer from public.products where company_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  0,
  'manager cannot query another company product'
);

select private.test_set_auth_phase_2('10000000-0000-4000-8000-000000000010');
select is((select count(*)::integer from public.products), 2, 'admin sees company-global products');
select is((select count(*)::integer from public.stock_takes), 1, 'admin sees allocated warehouse stock take only');
select is((select count(*)::integer from public.import_jobs), 2, 'admin sees company product import and allocated snapshot import');
select is((select count(*)::integer from public.import_issues), 1, 'admin sees allocated warehouse issues');
select is((select count(*)::integer from public.stock_snapshot_lines), 1, 'admin sees allocated warehouse SOH');
select is(
  (select count(*)::integer from public.stock_takes where warehouse_id = 'a1000000-0000-4000-8000-000000000002'),
  0,
  'admin cannot query an unallocated warehouse stock take'
);
select is(
  (select count(*)::integer from public.import_jobs where company_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  0,
  'admin cannot query another company import'
);

select private.test_set_auth_phase_2('10000000-0000-4000-8000-000000000001');
select is((select count(*)::integer from public.products), 2, 'explicit super admin sees authorised company products');
select is((select count(*)::integer from public.stock_takes), 2, 'explicit super admin sees authorised company stock takes');
select is((select count(*)::integer from public.import_jobs), 3, 'explicit super admin sees authorised company imports');
select is((select count(*)::integer from public.import_issues), 1, 'explicit super admin sees authorised company issues');
select is((select count(*)::integer from public.stock_snapshot_lines), 2, 'explicit super admin sees authorised company SOH');

select private.test_set_auth_phase_2('10000000-0000-4000-8000-000000000040');
select is((select count(*)::integer from public.products), 1, 'company B admin sees company B products');
select is((select count(*)::integer from public.stock_takes), 1, 'company B admin sees allocated stock take');
select is((select count(*)::integer from public.import_jobs), 2, 'company B admin sees own product and snapshot imports');
select is((select count(*)::integer from public.stock_snapshot_lines), 1, 'company B admin sees own warehouse SOH');
select is(
  (select count(*)::integer from public.products where company_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'company B admin cannot query company A products'
);

select private.test_set_auth_phase_2('10000000-0000-4000-8000-000000000002');
select is((select count(*)::integer from public.products), 0, 'unallocated platform admin sees no products');
select is((select count(*)::integer from public.import_jobs), 0, 'unallocated platform admin sees no imports');
select is((select count(*)::integer from public.stock_snapshot_lines), 0, 'unallocated platform admin sees no SOH');

select private.test_set_auth_phase_2('10000000-0000-4000-8000-000000000050');
select is((select count(*)::integer from public.products), 0, 'inactive company member sees no products');
select is((select count(*)::integer from public.stock_snapshot_lines), 0, 'inactive company member sees no SOH');

select private.test_set_auth_phase_2('10000000-0000-4000-8000-000000000030', true);
select is((select count(*)::integer from public.brands), 0, 'anonymous-auth user sees no brands');
select is((select count(*)::integer from public.products), 0, 'anonymous-auth user sees no products');

reset role;
select * from finish();
rollback;
