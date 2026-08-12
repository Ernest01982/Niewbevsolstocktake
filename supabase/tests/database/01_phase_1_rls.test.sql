begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

create function private.test_set_auth(test_user_id uuid, anonymous_user boolean default false)
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

grant execute on function private.test_set_auth(uuid, boolean) to authenticated;

set local role authenticated;

select private.test_set_auth('10000000-0000-4000-8000-000000000030');
select is((select count(*)::integer from public.companies), 1, 'stock taker sees own company');
select is((select count(*)::integer from public.warehouses), 1, 'stock taker sees allocated warehouse');
select is((select count(*)::integer from public.profiles), 1, 'stock taker sees only own profile');
select is((select count(*)::integer from public.company_memberships), 1, 'stock taker sees only own company membership');
select is((select count(*)::integer from public.warehouse_memberships), 1, 'stock taker sees only own warehouse membership');
select is((select count(*)::integer from public.audit_logs), 0, 'stock taker sees no audit rows');
select is(
  (select count(*)::integer from public.warehouses where company_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  0,
  'stock taker cannot forge access to another company warehouse'
);
select is(
  (select count(*)::integer from public.profiles where user_id <> '10000000-0000-4000-8000-000000000030'),
  0,
  'stock taker cannot read another profile'
);

select private.test_set_auth('10000000-0000-4000-8000-000000000020');
select is((select count(*)::integer from public.warehouses), 1, 'manager sees allocated warehouse only');
select is((select count(*)::integer from public.audit_logs), 1, 'manager sees allocated warehouse audit only');
select is((select count(*)::integer from public.company_memberships), 3, 'manager sees users sharing managed warehouse');

select private.test_set_auth('10000000-0000-4000-8000-000000000010');
select is((select count(*)::integer from public.warehouses), 1, 'admin sees allocated warehouse only');
select is(
  (select count(*)::integer from public.warehouses where id = 'a1000000-0000-4000-8000-000000000002'),
  0,
  'admin cannot see unallocated warehouse in own company'
);
select is(
  (select count(*)::integer from public.warehouses where id = 'b1000000-0000-4000-8000-000000000001'),
  0,
  'admin cannot see another company warehouse'
);
select is((select count(*)::integer from public.company_memberships), 3, 'admin sees users sharing allocated warehouse');
select is((select count(*)::integer from public.audit_logs), 2, 'admin sees company and allocated warehouse audit rows');

select private.test_set_auth('10000000-0000-4000-8000-000000000040');
select is((select count(*)::integer from public.companies), 1, 'company B admin sees one company');
select is(
  (select count(*)::integer from public.companies where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'company B admin cannot see company A'
);

select private.test_set_auth('10000000-0000-4000-8000-000000000001');
select is((select count(*)::integer from public.companies), 1, 'explicit super admin sees authorised company');
select is((select count(*)::integer from public.warehouses), 2, 'explicit super admin sees all warehouses in authorised company');
select is((select count(*)::integer from public.audit_logs), 2, 'explicit super admin sees authorised company audit');

select private.test_set_auth('10000000-0000-4000-8000-000000000002');
select is((select count(*)::integer from public.companies), 0, 'platform role without explicit company membership has no tenant access');

select private.test_set_auth('10000000-0000-4000-8000-000000000050');
select is((select count(*)::integer from public.companies), 0, 'inactive company membership grants no access');

select private.test_set_auth('10000000-0000-4000-8000-000000000030', true);
select is((select count(*)::integer from public.companies), 0, 'anonymous-auth user receives no company access');
select is((select count(*)::integer from public.profiles), 0, 'anonymous-auth user receives no profile access');

select private.test_set_auth('10000000-0000-4000-8000-000000000030');
select is(
  (select count(*)::integer from public.company_memberships where user_id = '10000000-0000-4000-8000-000000000010'),
  0,
  'stock taker cannot query an admin membership directly'
);

reset role;
select * from finish();
rollback;
