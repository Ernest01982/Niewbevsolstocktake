begin;

create extension if not exists pgtap with schema extensions;

select plan(34);

create function private.test_set_auth_phase_3_lifecycle(test_user_id uuid)
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
      'sub', test_user_id, 'role', 'authenticated', 'is_anonymous', false
    )::text,
    true
  );
end;
$$;

grant execute on function private.test_set_auth_phase_3_lifecycle(uuid) to authenticated;

insert into public.stock_takes (
  id, company_id, warehouse_id, status, created_by,
  ready_at, started_at, completed_at, completed_by
) values (
  'a4000000-0000-4000-8000-000000000099',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'a1000000-0000-4000-8000-000000000001',
  'COMPLETED',
  '10000000-0000-4000-8000-000000000001',
  now() - interval '10 days',
  now() - interval '10 days',
  now() - interval '10 days',
  '10000000-0000-4000-8000-000000000001'
);

set local role authenticated;

select private.test_set_auth_phase_3_lifecycle('10000000-0000-4000-8000-000000000030');
select is(
  public.create_stock_take(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000001'
  ) #>> '{error,code}',
  'forbidden',
  'stock taker cannot create a stock take'
);

select private.test_set_auth_phase_3_lifecycle('10000000-0000-4000-8000-000000000020');
create temporary table created_stock_take_result as
select public.create_stock_take(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'a1000000-0000-4000-8000-000000000001'
) as result;
select is((select result ->> 'success' from created_stock_take_result), 'true', 'manager can create a DRAFT stock take');
select is(
  (select count(*)::integer from public.audit_logs where action = 'stock_take.created'),
  1,
  'stock take creation is audited'
);
select is(
  public.mark_stock_take_ready(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001'
  ) #>> '{error,code}',
  'snapshot_unresolved',
  'unresolved snapshot rows block READY'
);

create temporary table clean_snapshot_retry_result as
select public.import_stock_snapshot(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001',
  'company-a-jhb-soh-corrected.csv',
  repeat('c', 64),
  '{"product_code":"Item","quantity_on_hand":"SOH"}',
  '[{"Item":"A-001","SOH":"720"}]',
  '2026-08-12T08:00:00+02:00'
) as result;
select is((select result ->> 'success' from clean_snapshot_retry_result), 'true', 'clean snapshot retry succeeds');
select is((select (result #>> '{totals,accepted}')::integer from clean_snapshot_retry_result), 1, 'identical immutable line is revalidated as accepted');
select is((select (result #>> '{totals,rejected}')::integer from clean_snapshot_retry_result), 0, 'clean retry has no rejected rows');
select is(
  (select count(*)::integer from public.stock_snapshot_lines where stock_take_id = 'a4000000-0000-4000-8000-000000000001'),
  1,
  'snapshot retry does not duplicate immutable lines'
);

select is(
  public.mark_stock_take_ready(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001'
  ) ->> 'success',
  'true',
  'clean full snapshot validation unlocks READY'
);
select is(
  (select status::text from public.stock_takes where id = 'a4000000-0000-4000-8000-000000000001'),
  'READY',
  'READY state is persisted'
);
select is(
  public.start_stock_take(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001'
  ) ->> 'success',
  'true',
  'manager starts a READY stock take'
);
select is(
  public.start_stock_take(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001'
  ) #>> '{error,code}',
  'invalid_state',
  'duplicate start is rejected safely'
);
select is(
  public.start_stock_take(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000002',
    'a4000000-0000-4000-8000-000000000002'
  ) #>> '{error,code}',
  'forbidden',
  'manager cannot start an unallocated warehouse stock take'
);

select private.test_set_auth_phase_3_lifecycle('10000000-0000-4000-8000-000000000030');
create temporary table session_start_result as
select public.start_stock_taker_session(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001'
) as result;
select is((select result ->> 'success' from session_start_result), 'true', 'allocated Stock Taker starts a session');
select is(
  public.start_stock_taker_session(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001'
  ) ->> 'existing',
  'true',
  'repeating the same session start recovers idempotently'
);
select is((select count(*)::integer from public.stock_taker_sessions where status = 'ACTIVE'), 1, 'only one active session exists');

create temporary table safe_context_result as select public.get_stock_taker_context() as result;
select is((select result ->> 'success' from safe_context_result), 'true', 'stock taker context succeeds');
select is((select result #>> '{session,stock_take,status}' from safe_context_result), 'ACTIVE', 'safe context includes countable lifecycle status');
select ok(
  (select result::text !~* 'quantity|snapshot|variance|soh' from safe_context_result),
  'safe context contains no SOH or variance fields'
);

select private.test_set_auth_phase_3_lifecycle('10000000-0000-4000-8000-000000000020');
select is(
  public.move_stock_take_to_review(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001'
  ) ->> 'success',
  'true',
  'manager moves ACTIVE stock take to REVIEW'
);
select is((select status::text from public.stock_taker_sessions limit 1), 'ENDED', 'entering REVIEW closes active sessions');
select private.test_set_auth_phase_3_lifecycle('10000000-0000-4000-8000-000000000010');
select is(
  public.complete_stock_take(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001'
  ) ->> 'success',
  'true',
  'admin completes a REVIEW stock take'
);
select ok(
  (select status = 'COMPLETED' and completed_at is not null and completed_by = '10000000-0000-4000-8000-000000000010'
   from public.stock_takes where id = 'a4000000-0000-4000-8000-000000000001'),
  'completion records state, time, and actor'
);

select private.test_set_auth_phase_3_lifecycle('10000000-0000-4000-8000-000000000030');
select is(
  public.start_stock_taker_session(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001'
  ) #>> '{error,code}',
  'stock_take_not_countable',
  'COMPLETED stock take rejects new sessions'
);
select is(
  public.end_stock_taker_session((select (result ->> 'session_id')::uuid from session_start_result)) ->> 'existing',
  'true',
  'session end is idempotent after manager closure'
);
select is((select count(*)::integer from public.stock_takes), 0, 'stock taker still cannot query management stock-take rows directly');

select private.test_set_auth_phase_3_lifecycle('10000000-0000-4000-8000-000000000010');
select is(
  public.reopen_stock_take(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000002',
    'a4000000-0000-4000-8000-000000000002',
    'Admin attempt'
  ) #>> '{error,code}',
  'forbidden',
  'Admin cannot use the privileged reopen flow'
);

select private.test_set_auth_phase_3_lifecycle('10000000-0000-4000-8000-000000000001');
select is(
  public.reopen_stock_take(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000002',
    'a4000000-0000-4000-8000-000000000002',
    '   '
  ) #>> '{error,code}',
  'reason_required',
  'reopen requires a nonblank reason'
);
select is(
  public.reopen_stock_take(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000002',
    'a4000000-0000-4000-8000-000000000002',
    'Controlled recount requested'
  ) ->> 'success',
  'true',
  'authorised platform Super Admin can reopen within the window'
);
select ok(
  (select status = 'REOPENED' and reopen_count = 1 and reopen_reason = 'Controlled recount requested'
   from public.stock_takes where id = 'a4000000-0000-4000-8000-000000000002'),
  'reopen preserves state, count, and reason'
);
select is((select count(*)::integer from public.audit_logs where action = 'stock_take.reopened'), 1, 'privileged reopen is audited');
select is(
  public.complete_stock_take(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000002',
    'a4000000-0000-4000-8000-000000000002'
  ) #>> '{error,code}',
  'invalid_state',
  'REOPENED cannot skip the recount and review path'
);
select is(
  public.reopen_stock_take(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000002',
    'a4000000-0000-4000-8000-000000000002',
    'Second attempt'
  ) #>> '{error,code}',
  'invalid_state',
  'already reopened stock take cannot be reopened again'
);
select is(
  public.reopen_stock_take(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000099',
    'Expired attempt'
  ) #>> '{error,code}',
  'reopen_window_expired',
  'expired reopen window is enforced'
);

reset role;
select * from finish();
rollback;
