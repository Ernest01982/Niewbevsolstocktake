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

insert into public.company_settings (company_id, reopen_window_days)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 3),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 3)
on conflict (company_id) do update
set reopen_window_days = excluded.reopen_window_days;

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

insert into public.brands (id, company_id, name)
values
  ('a2000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Company A Brand'),
  ('b2000000-0000-4000-8000-000000000001', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Company B Brand');

insert into public.products (
  id,
  company_id,
  brand_id,
  product_code,
  name,
  barcode,
  units_per_case,
  cases_per_layer,
  cases_per_pallet
)
values
  ('a3000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a2000000-0000-4000-8000-000000000001', 'A-001', 'Company A Product One', '6000000000001', 12, 10, 60),
  ('a3000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a2000000-0000-4000-8000-000000000001', 'A-002', 'Company A Product Two', '6000000000002', null, null, null),
  ('b3000000-0000-4000-8000-000000000001', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b2000000-0000-4000-8000-000000000001', 'B-001', 'Company B Product One', '7000000000001', 6, 8, 48);

insert into public.stock_takes (
  id,
  company_id,
  warehouse_id,
  status,
  created_by,
  ready_at,
  started_at,
  completed_at,
  completed_by
)
values
  ('a4000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1000000-0000-4000-8000-000000000001', 'DRAFT', '10000000-0000-4000-8000-000000000020', null, null, null, null),
  ('a4000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1000000-0000-4000-8000-000000000002', 'COMPLETED', '10000000-0000-4000-8000-000000000001', '2026-08-01T07:00:00+02:00', '2026-08-01T08:00:00+02:00', now(), '10000000-0000-4000-8000-000000000001'),
  ('b4000000-0000-4000-8000-000000000001', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b1000000-0000-4000-8000-000000000001', 'DRAFT', '10000000-0000-4000-8000-000000000040', null, null, null, null);

insert into public.import_jobs (
  id,
  company_id,
  warehouse_id,
  stock_take_id,
  kind,
  status,
  source_filename,
  source_metadata,
  column_mapping,
  snapshot_as_of,
  total_rows,
  accepted_rows,
  flagged_rows,
  rejected_rows,
  created_by,
  completed_at
)
values
  ('a5000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, null, 'product_master', 'completed', 'company-a-products.csv', '{"fixture":true}', '{"product_code":"Code","name":"Description"}', null, 2, 2, 0, 0, '10000000-0000-4000-8000-000000000010', now()),
  ('a5000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1000000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-000000000001', 'stock_snapshot', 'completed_with_issues', 'company-a-jhb-soh.csv', '{"fixture":true}', '{"product_code":"Item","quantity_on_hand":"SOH"}', '2026-08-12T08:00:00+02:00', 2, 1, 0, 1, '10000000-0000-4000-8000-000000000020', now()),
  ('a5000000-0000-4000-8000-000000000003', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1000000-0000-4000-8000-000000000002', 'a4000000-0000-4000-8000-000000000002', 'stock_snapshot', 'completed', 'company-a-cpt-soh.csv', '{"fixture":true}', '{"product_code":"Item","quantity_on_hand":"SOH"}', '2026-08-01T08:00:00+02:00', 1, 1, 0, 0, '10000000-0000-4000-8000-000000000001', now()),
  ('b5000000-0000-4000-8000-000000000001', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', null, null, 'product_master', 'completed', 'company-b-products.csv', '{"fixture":true}', '{"product_code":"Code","name":"Description"}', null, 1, 1, 0, 0, '10000000-0000-4000-8000-000000000040', now()),
  ('b5000000-0000-4000-8000-000000000002', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b1000000-0000-4000-8000-000000000001', 'b4000000-0000-4000-8000-000000000001', 'stock_snapshot', 'completed', 'company-b-jhb-soh.csv', '{"fixture":true}', '{"product_code":"Item","quantity_on_hand":"SOH"}', '2026-08-12T08:00:00+02:00', 1, 1, 0, 0, '10000000-0000-4000-8000-000000000040', now());

insert into public.import_issues (
  id,
  company_id,
  warehouse_id,
  stock_take_id,
  import_job_id,
  row_number,
  disposition,
  issue_code,
  field_name,
  message,
  raw_row
)
values
  ('a6000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1000000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-000000000001', 'a5000000-0000-4000-8000-000000000002', 2, 'rejected', 'product_not_found', 'product_code', 'Fixture rejected row.', '{"Item":"UNKNOWN","SOH":"5"}');

insert into public.stock_snapshot_lines (
  id,
  company_id,
  warehouse_id,
  stock_take_id,
  product_id,
  import_job_id,
  quantity_on_hand,
  source_row_number,
  source_row,
  snapshot_as_of
)
values
  ('a7000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1000000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-000000000001', 'a5000000-0000-4000-8000-000000000002', 720, 1, '{"Item":"A-001","SOH":"720"}', '2026-08-12T08:00:00+02:00'),
  ('a7000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1000000-0000-4000-8000-000000000002', 'a4000000-0000-4000-8000-000000000002', 'a3000000-0000-4000-8000-000000000002', 'a5000000-0000-4000-8000-000000000003', 0, 1, '{"Item":"A-002","SOH":"0"}', '2026-08-01T08:00:00+02:00'),
  ('b7000000-0000-4000-8000-000000000001', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b1000000-0000-4000-8000-000000000001', 'b4000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001', 'b5000000-0000-4000-8000-000000000002', 96, 1, '{"Item":"B-001","SOH":"96"}', '2026-08-12T08:00:00+02:00');
