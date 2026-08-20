begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

select has_table('public', 'company_settings', 'company_settings exists');
select has_table('public', 'stock_taker_sessions', 'stock_taker_sessions exists');
select has_type('public', 'stock_taker_session_status', 'session status type exists');
select has_column('public', 'stock_takes', 'ready_at', 'stock takes record READY time');
select has_column('public', 'stock_takes', 'completed_by', 'stock takes record completing actor');
select has_column('public', 'stock_takes', 'reopen_reason', 'stock takes record reopen reason');
select has_column('public', 'stock_takes', 'reopen_count', 'stock takes preserve reopen count');

select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.company_settings'::regclass),
  'company_settings has enabled and forced RLS'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.stock_taker_sessions'::regclass),
  'stock_taker_sessions has enabled and forced RLS'
);
select has_index(
  'public', 'stock_taker_sessions', 'stock_taker_sessions_one_active_per_user_idx',
  'one-active-session partial unique index exists'
);
select has_index(
  'public', 'stock_taker_sessions', 'stock_taker_sessions_membership_idx',
  'session membership foreign key has a covering index'
);
select has_index(
  'public', 'stock_taker_sessions', 'stock_taker_sessions_stock_take_scope_idx',
  'session stock-take scope foreign key has a covering index'
);
select has_index(
  'public', 'stock_takes', 'stock_takes_company_completed_by_idx',
  'completion actor foreign key has a covering index'
);
select has_index(
  'public', 'stock_takes', 'stock_takes_company_reopened_by_idx',
  'reopen actor foreign key has a covering index'
);

select throws_ok(
  $$
    update public.stock_takes set status = 'ACTIVE'
    where id = 'a4000000-0000-4000-8000-000000000001'
  $$,
  '23514'::character(5),
  'Invalid stock take transition from DRAFT to ACTIVE.',
  'DRAFT cannot skip READY'
);
select lives_ok(
  $$update public.stock_takes set status = 'READY' where id = 'a4000000-0000-4000-8000-000000000001'$$,
  'DRAFT can become READY'
);
select ok(
  (select ready_at is not null from public.stock_takes where id = 'a4000000-0000-4000-8000-000000000001'),
  'READY transition timestamps itself'
);
select lives_ok(
  $$update public.stock_takes set status = 'ACTIVE' where id = 'a4000000-0000-4000-8000-000000000001'$$,
  'READY can become ACTIVE'
);
select ok(
  (select started_at is not null from public.stock_takes where id = 'a4000000-0000-4000-8000-000000000001'),
  'ACTIVE transition timestamps itself'
);
select throws_ok(
  $$
    update public.stock_takes set company_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    where id = 'a4000000-0000-4000-8000-000000000001'
  $$,
  '55000'::character(5),
  'Stock take identity and scope are immutable.',
  'stock take tenant scope cannot be rewritten'
);
select throws_ok(
  $$
    update public.stock_takes set started_at = now() + interval '1 hour'
    where id = 'a4000000-0000-4000-8000-000000000001'
  $$,
  '55000'::character(5),
  'Stock take lifecycle metadata is immutable outside a state transition.',
  'lifecycle metadata cannot be edited in place'
);

select lives_ok(
  $$
    insert into public.stock_taker_sessions (
      id, company_id, warehouse_id, stock_take_id, user_id
    ) values (
      'a8000000-0000-4000-8000-000000000001',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'a1000000-0000-4000-8000-000000000001',
      'a4000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000030'
    )
  $$,
  'first active session is allowed'
);
select throws_ok(
  $$
    insert into public.stock_taker_sessions (
      company_id, warehouse_id, stock_take_id, user_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'a1000000-0000-4000-8000-000000000001',
      'a4000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000030'
    )
  $$,
  '23505'::character(5),
  'duplicate key value violates unique constraint "stock_taker_sessions_one_active_per_user_idx"',
  'a user cannot have two active sessions'
);
select throws_ok(
  $$
    insert into public.stock_taker_sessions (
      company_id, warehouse_id, stock_take_id, user_id
    ) values (
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'b1000000-0000-4000-8000-000000000001',
      'b4000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000050'
    )
  $$,
  '23503'::character(5),
  'insert or update on table "stock_taker_sessions" violates foreign key constraint "stock_taker_sessions_membership_fkey"',
  'session scope must match an allocated Stock Taker membership'
);
select throws_ok(
  $$update public.stock_taker_sessions set status = 'ENDED' where id = 'a8000000-0000-4000-8000-000000000001'$$,
  '23514'::character(5),
  'new row for relation "stock_taker_sessions" violates check constraint "stock_taker_sessions_status_timestamps_check"',
  'ENDED sessions require an end timestamp'
);

select ok(not has_table_privilege('authenticated', 'public.stock_taker_sessions', 'INSERT'), 'sessions cannot be inserted directly');
select ok(not has_table_privilege('authenticated', 'public.stock_takes', 'UPDATE'), 'stock take states cannot be updated directly');
select ok(has_function_privilege('authenticated', 'public.start_stock_take(uuid,uuid,uuid)', 'EXECUTE'), 'authenticated may call start RPC');
select ok(not has_function_privilege('anon', 'public.start_stock_take(uuid,uuid,uuid)', 'EXECUTE'), 'anon cannot call start RPC');
select ok(has_function_privilege('authenticated', 'public.get_stock_taker_context()', 'EXECUTE'), 'authenticated may request safe context');

select * from finish();
rollback;
