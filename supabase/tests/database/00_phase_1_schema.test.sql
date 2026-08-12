begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'companies', 'companies exists');
select has_table('public', 'warehouses', 'warehouses exists');
select has_table('public', 'company_memberships', 'company_memberships exists');
select has_table('public', 'warehouse_memberships', 'warehouse_memberships exists');
select has_table('public', 'audit_logs', 'audit_logs exists');
select has_type('public', 'membership_role', 'membership_role exists');

select ok(
  (
    select bool_and(class.relrowsecurity and class.relforcerowsecurity)
    from pg_class as class
    join pg_namespace as namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'public'
      and class.relname = any (
        array[
          'profiles',
          'companies',
          'warehouses',
          'company_memberships',
          'warehouse_memberships',
          'audit_logs'
        ]
      )
  ),
  'RLS is enabled and forced on every Phase 1 public table'
);

select throws_ok(
  $$
    insert into public.warehouses (company_id, warehouse_code, name)
    values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A-JHB', 'Duplicate')
  $$,
  '23505'::character(5),
  'duplicate key value violates unique constraint "warehouses_company_code_key"',
  'duplicate warehouse codes inside one company are rejected'
);

select throws_ok(
  $$
    insert into public.warehouse_memberships (
      company_id,
      warehouse_id,
      user_id,
      role
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'b1000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000010',
      'admin'
    )
  $$,
  '23503'::character(5),
  'insert or update on table "warehouse_memberships" violates foreign key constraint "warehouse_memberships_warehouse_company_fkey"',
  'cross-company warehouse allocations are rejected'
);

select throws_ok(
  $$
    insert into public.warehouse_memberships (
      company_id,
      warehouse_id,
      user_id,
      role
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'a1000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000020',
      'manager'
    )
  $$,
  '23505'::character(5),
  'duplicate key value violates unique constraint "warehouse_memberships_one_active_manager_per_user_idx"',
  'a manager cannot have two active warehouse allocations'
);

select throws_ok(
  $$
    update public.audit_logs
    set metadata = '{"changed":true}'
    where id = 'aa000000-0000-4000-8000-000000000001'
  $$,
  '55000'::character(5),
  'audit_logs rows are immutable.',
  'audit rows reject updates'
);

select throws_ok(
  $$
    delete from public.audit_logs
    where id = 'aa000000-0000-4000-8000-000000000001'
  $$,
  '55000'::character(5),
  'audit_logs rows are immutable.',
  'audit rows reject deletes'
);

select ok(not has_table_privilege('anon', 'public.companies', 'SELECT'), 'anon cannot select companies');
select ok(not has_table_privilege('anon', 'public.warehouses', 'SELECT'), 'anon cannot select warehouses');
select ok(not has_table_privilege('anon', 'public.audit_logs', 'SELECT'), 'anon cannot select audit logs');
select ok(not has_table_privilege('authenticated', 'public.companies', 'INSERT'), 'authenticated cannot insert companies directly');
select ok(not has_table_privilege('authenticated', 'public.audit_logs', 'UPDATE'), 'authenticated cannot update audit logs');

select * from finish();
rollback;
