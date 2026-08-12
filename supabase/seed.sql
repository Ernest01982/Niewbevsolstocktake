-- Deterministic development fixtures only. Never seed production with this file.
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'super.a@example.test', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'platform.unallocated@example.test', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'admin.a@example.test', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000020', 'authenticated', 'authenticated', 'manager.a@example.test', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000030', 'authenticated', 'authenticated', 'taker.a@example.test', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000040', 'authenticated', 'authenticated', 'admin.b@example.test', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000050', 'authenticated', 'authenticated', 'inactive.a@example.test', '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.profiles (user_id, display_name, platform_role)
values
  ('10000000-0000-4000-8000-000000000001', 'Explicit Super Admin', 'super_admin'),
  ('10000000-0000-4000-8000-000000000002', 'Unallocated Platform Admin', 'super_admin'),
  ('10000000-0000-4000-8000-000000000010', 'Company A Admin', null),
  ('10000000-0000-4000-8000-000000000020', 'Warehouse A Manager', null),
  ('10000000-0000-4000-8000-000000000030', 'Warehouse A Stock Taker', null),
  ('10000000-0000-4000-8000-000000000040', 'Company B Admin', null),
  ('10000000-0000-4000-8000-000000000050', 'Inactive Company A User', null);

insert into public.companies (id, name)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Fixture Company A'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Fixture Company B');

insert into public.warehouses (id, company_id, warehouse_code, name)
values
  ('a1000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A-JHB', 'Company A Johannesburg'),
  ('a1000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A-CPT', 'Company A Cape Town'),
  ('b1000000-0000-4000-8000-000000000001', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'B-JHB', 'Company B Johannesburg');

insert into public.company_memberships (company_id, user_id, role, status)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '10000000-0000-4000-8000-000000000001', 'super_admin', 'active'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '10000000-0000-4000-8000-000000000010', 'admin', 'active'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '10000000-0000-4000-8000-000000000020', 'manager', 'active'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '10000000-0000-4000-8000-000000000030', 'stock_taker', 'active'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '10000000-0000-4000-8000-000000000040', 'admin', 'active'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '10000000-0000-4000-8000-000000000050', 'stock_taker', 'inactive');

insert into public.warehouse_memberships (company_id, warehouse_id, user_id, role, status)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000010', 'admin', 'active'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000020', 'manager', 'active'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000030', 'stock_taker', 'active'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b1000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000040', 'admin', 'active');

insert into public.audit_logs (
  id,
  company_id,
  warehouse_id,
  actor_user_id,
  action,
  entity_type,
  entity_id,
  metadata
)
values
  ('aa000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '10000000-0000-4000-8000-000000000001', 'company.created', 'company', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '{"fixture":true}'),
  ('aa000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000010', 'warehouse.allocated', 'warehouse', 'a1000000-0000-4000-8000-000000000001', '{"fixture":true}'),
  ('bb000000-0000-4000-8000-000000000001', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b1000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000040', 'warehouse.allocated', 'warehouse', 'b1000000-0000-4000-8000-000000000001', '{"fixture":true}');
