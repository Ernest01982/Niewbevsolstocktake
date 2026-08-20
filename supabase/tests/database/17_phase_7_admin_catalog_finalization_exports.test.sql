begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

create function private.test_set_auth_phase_7(test_user_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  perform set_config('request.jwt.claim.sub', test_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', test_user_id, 'role', 'authenticated', 'is_anonymous', false
  )::text, true);
end;
$$;
grant execute on function private.test_set_auth_phase_7(uuid) to authenticated;

select has_table('public', 'stock_take_exports', 'export history table exists');
select has_column('public', 'stock_takes', 'completion_mode', 'completion mode is stored');
select has_column('public', 'stock_takes', 'completion_reason', 'override reason is stored');
select has_function('public', 'save_product', array['uuid','uuid','text','text','text','text','integer','integer','integer','record_status'], 'controlled product save exists');
select has_function('public', 'force_complete_stock_take', array['uuid','uuid','uuid','text'], 'controlled Admin override exists');
select has_function('public', 'create_stock_take_export', array['uuid','uuid','uuid','text'], 'controlled SAGE export exists');

set local role authenticated;
select private.test_set_auth_phase_7('10000000-0000-4000-8000-000000000020');
select is(public.save_product(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',null,'A-NEW','New Item','New Brand',null,12,10,60,'active'
) #>> '{error,code}', 'forbidden', 'manager cannot add products');

select private.test_set_auth_phase_7('10000000-0000-4000-8000-000000000010');
select is(public.save_product(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',null,'A-NEW','New Item','New Brand','6000000000099',12,10,60,'active'
) ->> 'success', 'true', 'admin adds a stock item');
select is((select name from public.products where product_code = 'A-NEW'), 'New Item', 'new product is stored');
select is((select name from public.brands where normalized_name = 'new brand'), 'New Brand', 'new brand is stored');
select is(public.save_product(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',(select id from public.products where product_code = 'A-NEW'),
  'A-NEW','Updated Item','New Brand','6000000000099',12,10,60,'inactive'
) ->> 'success', 'true', 'admin edits and archives a stock item');
select is((select status::text from public.products where product_code = 'A-NEW'), 'inactive', 'archive state is stored');
select is((select count(*)::integer from public.audit_logs where action in ('product.created','product.archived') and metadata ->> 'product_code' = 'A-NEW'), 2, 'product changes are audited');

reset role;
update public.stock_takes set status = 'READY' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'ACTIVE' where id = 'a4000000-0000-4000-8000-000000000001';
update public.stock_takes set status = 'REVIEW' where id = 'a4000000-0000-4000-8000-000000000001';

set local role authenticated;
select private.test_set_auth_phase_7('10000000-0000-4000-8000-000000000020');
select is(public.complete_stock_take(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001'
) #>> '{error,code}', 'forbidden', 'manager cannot give final approval');
select is(public.force_complete_stock_take(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','Manager attempt'
) #>> '{error,code}', 'forbidden', 'manager cannot force final approval');

select private.test_set_auth_phase_7('10000000-0000-4000-8000-000000000010');
select is(public.force_complete_stock_take(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','   '
) #>> '{error,code}', 'reason_required', 'override requires a reason');
select is(public.force_complete_stock_take(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','Financial controller accepted the counted result.'
) ->> 'success', 'true', 'admin finalises with accepted variances');
select is((select completion_mode from public.stock_takes where id = 'a4000000-0000-4000-8000-000000000001'), 'override', 'override mode is stored');
select is((select completion_reason from public.stock_takes where id = 'a4000000-0000-4000-8000-000000000001'), 'Financial controller accepted the counted result.', 'override reason is stored');
select is((select count(*)::integer from public.audit_logs where action = 'stock_take.force_completed'), 1, 'forced completion is audited once');
select ok((select metadata ?& array['reason','variance_line_count','absolute_variance_units','open_recount_ids','open_flag_ids'] from public.audit_logs where action = 'stock_take.force_completed'), 'override audit captures unresolved summary');

select is(public.create_stock_take_export(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','sage_physical_count'
) ->> 'success', 'true', 'admin creates a completed SAGE export');
select is((select count(*)::integer from public.stock_take_exports), 1, 'export history is immutable server data');
select is((select row_count from public.stock_take_exports), 1, 'export records its row count');
select is((select count(*)::integer from public.audit_logs where action = 'stock_take.exported'), 1, 'export is audited');

select private.test_set_auth_phase_7('10000000-0000-4000-8000-000000000020');
select is((select count(*)::integer from public.stock_take_exports), 0, 'manager cannot read Admin export history');
select is(public.create_stock_take_export(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a1000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','sage_physical_count'
) #>> '{error,code}', 'forbidden', 'manager cannot create a SAGE export');

reset role;
select * from finish();
rollback;
