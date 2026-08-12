create function private.has_active_stock_taker_allocation(
  target_company_id uuid,
  target_warehouse_id uuid,
  target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_permanent_user()
    and target_user_id = (select auth.uid())
    and exists (
      select 1
      from public.warehouse_memberships as allocation
      join public.company_memberships as membership
        on membership.company_id = allocation.company_id
        and membership.user_id = allocation.user_id
        and membership.role = allocation.role
      join public.profiles as profile on profile.user_id = allocation.user_id
      join public.warehouses as warehouse
        on warehouse.id = allocation.warehouse_id
        and warehouse.company_id = allocation.company_id
      where allocation.company_id = target_company_id
        and allocation.warehouse_id = target_warehouse_id
        and allocation.user_id = target_user_id
        and allocation.role = 'stock_taker'
        and allocation.status = 'active'
        and membership.status = 'active'
        and profile.status = 'active'
        and warehouse.status = 'active'
    );
$$;

create function public.start_stock_take(
  p_company_id uuid, p_warehouse_id uuid, p_stock_take_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  current_status public.stock_take_status;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Starting a stock take requires an allocated Admin or Manager.'
    ));
  end if;
  select status into current_status from public.stock_takes
  where id = p_stock_take_id and company_id = p_company_id
    and warehouse_id = p_warehouse_id for update;
  if not found then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_found', 'message', 'The stock take was not found.'
    ));
  end if;
  if current_status <> 'READY' then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_state', 'message', 'Only a READY stock take can start.'
    ));
  end if;
  update public.stock_takes set status = 'ACTIVE' where id = p_stock_take_id;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'stock_take.started',
    'stock_take', p_stock_take_id, '{}'::jsonb
  );
  return jsonb_build_object('success', true, 'stock_take_id', p_stock_take_id, 'status', 'ACTIVE');
exception when unique_violation then
  return jsonb_build_object('success', false, 'error', jsonb_build_object(
    'code', 'warehouse_stock_take_active', 'message', 'This warehouse already has an open stock take.'
  ));
end;
$$;

create function public.move_stock_take_to_review(
  p_company_id uuid, p_warehouse_id uuid, p_stock_take_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  current_status public.stock_take_status;
  ended_sessions integer;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Review requires an allocated Admin or Manager.'
    ));
  end if;
  select status into current_status from public.stock_takes
  where id = p_stock_take_id and company_id = p_company_id
    and warehouse_id = p_warehouse_id for update;
  if not found then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_found', 'message', 'The stock take was not found.'
    ));
  end if;
  if current_status not in ('ACTIVE', 'RECOUNT') then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_state', 'message', 'Only ACTIVE or RECOUNT stock takes can enter REVIEW.'
    ));
  end if;
  update public.stock_taker_sessions
  set status = 'ENDED', ended_at = now(), last_active_at = now()
  where stock_take_id = p_stock_take_id and status = 'ACTIVE';
  get diagnostics ended_sessions = row_count;
  update public.stock_takes set status = 'REVIEW' where id = p_stock_take_id;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'stock_take.review_started',
    'stock_take', p_stock_take_id, jsonb_build_object('ended_sessions', ended_sessions)
  );
  return jsonb_build_object(
    'success', true, 'stock_take_id', p_stock_take_id,
    'status', 'REVIEW', 'ended_sessions', ended_sessions
  );
end;
$$;

create function public.complete_stock_take(
  p_company_id uuid, p_warehouse_id uuid, p_stock_take_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  current_status public.stock_take_status;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Completion requires an allocated Admin or Manager.'
    ));
  end if;
  select status into current_status from public.stock_takes
  where id = p_stock_take_id and company_id = p_company_id
    and warehouse_id = p_warehouse_id for update;
  if not found then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_found', 'message', 'The stock take was not found.'
    ));
  end if;
  if current_status <> 'REVIEW' then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_state', 'message', 'Only a REVIEW stock take can be completed.'
    ));
  end if;
  update public.stock_takes
  set status = 'COMPLETED', completed_by = actor_id
  where id = p_stock_take_id;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'stock_take.completed',
    'stock_take', p_stock_take_id, '{}'::jsonb
  );
  return jsonb_build_object('success', true, 'stock_take_id', p_stock_take_id, 'status', 'COMPLETED');
end;
$$;

revoke all on function private.has_active_stock_taker_allocation(uuid, uuid, uuid)
from public, anon, authenticated;

create function public.create_stock_take(p_company_id uuid, p_warehouse_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  stock_take_id uuid;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Creating a stock take requires an allocated Admin or Manager.'
    ));
  end if;

  if not exists (
    select 1 from public.warehouses as warehouse
    where warehouse.id = p_warehouse_id and warehouse.company_id = p_company_id
      and warehouse.status = 'active'
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'warehouse_unavailable', 'message', 'The selected warehouse is not active.'
    ));
  end if;

  insert into public.stock_takes (company_id, warehouse_id, created_by)
  values (p_company_id, p_warehouse_id, actor_id)
  returning id into stock_take_id;

  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'stock_take.created', 'stock_take', stock_take_id,
    jsonb_build_object('status', 'DRAFT')
  );

  return jsonb_build_object('success', true, 'stock_take_id', stock_take_id, 'status', 'DRAFT');
exception when others then
  return jsonb_build_object('success', false, 'error', jsonb_build_object(
    'code', sqlstate, 'message', 'The stock take could not be created.'
  ));
end;
$$;

create function public.mark_stock_take_ready(
  p_company_id uuid,
  p_warehouse_id uuid,
  p_stock_take_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  current_status public.stock_take_status;
  latest_job public.import_jobs%rowtype;
  snapshot_count integer;
begin
  if not private.can_access_warehouse(
    p_company_id, p_warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Preparing a stock take requires an allocated Admin or Manager.'
    ));
  end if;

  select stock_take.status into current_status
  from public.stock_takes as stock_take
  where stock_take.id = p_stock_take_id
    and stock_take.company_id = p_company_id
    and stock_take.warehouse_id = p_warehouse_id
  for update;

  if not found then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_found', 'message', 'The stock take was not found in the selected warehouse.'
    ));
  end if;
  if current_status <> 'DRAFT' then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_state', 'message', 'Only a DRAFT stock take can become READY.'
    ));
  end if;
  if exists (
    select 1 from public.import_jobs as job
    where job.stock_take_id = p_stock_take_id and job.kind = 'stock_snapshot'
      and job.status = 'processing'
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'snapshot_import_in_progress', 'message', 'Wait for the active snapshot import to finish.'
    ));
  end if;

  select * into latest_job
  from public.import_jobs as job
  where job.company_id = p_company_id and job.warehouse_id = p_warehouse_id
    and job.stock_take_id = p_stock_take_id and job.kind = 'stock_snapshot'
  order by job.started_at desc, job.id desc
  limit 1;

  select count(*)::integer into snapshot_count
  from public.stock_snapshot_lines as line
  where line.stock_take_id = p_stock_take_id;

  if latest_job.id is null or snapshot_count = 0 then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'snapshot_required', 'message', 'A non-empty stock-on-hand snapshot is required.'
    ));
  end if;
  if latest_job.status <> 'completed' or latest_job.rejected_rows <> 0
    or latest_job.flagged_rows <> 0 or latest_job.accepted_rows <> snapshot_count
    or latest_job.total_rows <> snapshot_count then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'snapshot_unresolved',
      'message', 'Resolve all snapshot import errors and validate every snapshot line before continuing.'
    ));
  end if;

  update public.stock_takes set status = 'READY' where id = p_stock_take_id;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'stock_take.ready', 'stock_take', p_stock_take_id,
    jsonb_build_object('snapshot_import_job_id', latest_job.id, 'snapshot_lines', snapshot_count)
  );
  return jsonb_build_object('success', true, 'stock_take_id', p_stock_take_id, 'status', 'READY');
end;
$$;

create function public.reopen_stock_take(
  p_company_id uuid,
  p_warehouse_id uuid,
  p_stock_take_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  current_status public.stock_take_status;
  completion_time timestamptz;
  allowed_days integer;
begin
  if not exists (
    select 1 from public.profiles as profile
    where profile.user_id = actor_id
      and profile.platform_role = 'super_admin'
      and profile.status = 'active'
  ) or not private.can_access_company(
    p_company_id, array['super_admin']::public.membership_role[]
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'Reopen requires an authorised platform Super Admin.'
    ));
  end if;
  if nullif(btrim(p_reason), '') is null then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'reason_required', 'message', 'A reopen reason is required.'
    ));
  end if;
  select status, completed_at into current_status, completion_time
  from public.stock_takes
  where id = p_stock_take_id and company_id = p_company_id
    and warehouse_id = p_warehouse_id for update;
  if not found then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_found', 'message', 'The stock take was not found.'
    ));
  end if;
  if current_status <> 'COMPLETED' then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'invalid_state', 'message', 'Only a COMPLETED stock take can be reopened.'
    ));
  end if;
  select settings.reopen_window_days into allowed_days
  from public.company_settings as settings
  where settings.company_id = p_company_id;
  allowed_days := coalesce(allowed_days, 3);
  if now() > completion_time + make_interval(days => allowed_days) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'reopen_window_expired', 'message', 'The configured reopen window has expired.'
    ));
  end if;
  update public.stock_takes
  set status = 'REOPENED', reopened_by = actor_id, reopen_reason = btrim(p_reason)
  where id = p_stock_take_id;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'stock_take.reopened',
    'stock_take', p_stock_take_id,
    jsonb_build_object('reason', btrim(p_reason), 'reopen_window_days', allowed_days)
  );
  return jsonb_build_object('success', true, 'stock_take_id', p_stock_take_id, 'status', 'REOPENED');
exception when unique_violation then
  return jsonb_build_object('success', false, 'error', jsonb_build_object(
    'code', 'warehouse_stock_take_active', 'message', 'This warehouse already has an open stock take.'
  ));
end;
$$;

create function public.start_stock_taker_session(
  p_company_id uuid, p_warehouse_id uuid, p_stock_take_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  current_status public.stock_take_status;
  active_session public.stock_taker_sessions%rowtype;
  new_session_id uuid;
begin
  if not private.has_active_stock_taker_allocation(
    p_company_id, p_warehouse_id, actor_id
  ) then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'forbidden', 'message', 'An active Stock Taker allocation is required.'
    ));
  end if;
  select status into current_status from public.stock_takes
  where id = p_stock_take_id and company_id = p_company_id
    and warehouse_id = p_warehouse_id for update;
  if not found then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_found', 'message', 'The stock take was not found.'
    ));
  end if;
  if current_status not in ('ACTIVE', 'RECOUNT') then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'stock_take_not_countable', 'message', 'A session requires an ACTIVE or RECOUNT stock take.'
    ));
  end if;
  select * into active_session from public.stock_taker_sessions
  where user_id = actor_id and status = 'ACTIVE' for update;
  if active_session.id is not null then
    if active_session.stock_take_id = p_stock_take_id then
      update public.stock_taker_sessions
      set last_active_at = now() where id = active_session.id;
      return jsonb_build_object(
        'success', true, 'session_id', active_session.id,
        'existing', true, 'stock_take_status', current_status
      );
    end if;
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'active_session_exists',
      'message', 'End the existing warehouse session before starting another.'
    ));
  end if;
  insert into public.stock_taker_sessions (
    company_id, warehouse_id, stock_take_id, user_id
  ) values (
    p_company_id, p_warehouse_id, p_stock_take_id, actor_id
  ) returning id into new_session_id;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_company_id, p_warehouse_id, actor_id, 'stock_taker_session.started',
    'stock_taker_session', new_session_id, jsonb_build_object('stock_take_id', p_stock_take_id)
  );
  return jsonb_build_object(
    'success', true, 'session_id', new_session_id,
    'existing', false, 'stock_take_status', current_status
  );
exception when unique_violation then
  return jsonb_build_object('success', false, 'error', jsonb_build_object(
    'code', 'active_session_exists', 'message', 'The user already has an active warehouse session.'
  ));
end;
$$;

create function public.end_stock_taker_session(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  target public.stock_taker_sessions%rowtype;
begin
  select * into target from public.stock_taker_sessions
  where id = p_session_id for update;
  if target.id is null or target.user_id <> actor_id then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'session_not_found', 'message', 'The active session was not found.'
    ));
  end if;
  if target.status = 'ENDED' then
    return jsonb_build_object(
      'success', true, 'session_id', target.id, 'status', 'ENDED', 'existing', true
    );
  end if;
  update public.stock_taker_sessions
  set status = 'ENDED', ended_at = now(), last_active_at = now()
  where id = target.id;
  insert into public.audit_logs (
    company_id, warehouse_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    target.company_id, target.warehouse_id, actor_id, 'stock_taker_session.ended',
    'stock_taker_session', target.id, jsonb_build_object('stock_take_id', target.stock_take_id)
  );
  return jsonb_build_object(
    'success', true, 'session_id', target.id, 'status', 'ENDED', 'existing', false
  );
end;
$$;

create function public.get_stock_taker_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  context_result jsonb;
begin
  if not private.is_permanent_user() then
    return jsonb_build_object('success', false, 'error', jsonb_build_object(
      'code', 'unauthenticated', 'message', 'Authentication is required.'
    ));
  end if;
  select jsonb_build_object(
    'success', true,
    'session', jsonb_build_object(
      'id', session.id, 'status', session.status,
      'started_at', session.started_at, 'last_active_at', session.last_active_at
    ),
    'company', jsonb_build_object('id', company.id, 'name', company.name),
    'warehouse', jsonb_build_object(
      'id', warehouse.id, 'code', warehouse.warehouse_code, 'name', warehouse.name
    ),
    'stock_take', jsonb_build_object('id', stock_take.id, 'status', stock_take.status)
  ) into context_result
  from public.stock_taker_sessions as session
  join public.companies as company on company.id = session.company_id
  join public.warehouses as warehouse
    on warehouse.id = session.warehouse_id and warehouse.company_id = session.company_id
  join public.stock_takes as stock_take on stock_take.id = session.stock_take_id
  where session.user_id = actor_id and session.status = 'ACTIVE';
  return coalesce(context_result, jsonb_build_object('success', true, 'session', null));
end;
$$;

comment on function public.get_stock_taker_context() is
  'Stock-taker-safe context. It returns no SOH, variance, snapshot, or management metrics.';

revoke execute on function public.create_stock_take(uuid, uuid) from public, anon;
revoke execute on function public.mark_stock_take_ready(uuid, uuid, uuid) from public, anon;
revoke execute on function public.start_stock_take(uuid, uuid, uuid) from public, anon;
revoke execute on function public.move_stock_take_to_review(uuid, uuid, uuid) from public, anon;
revoke execute on function public.complete_stock_take(uuid, uuid, uuid) from public, anon;
revoke execute on function public.reopen_stock_take(uuid, uuid, uuid, text) from public, anon;
revoke execute on function public.start_stock_taker_session(uuid, uuid, uuid) from public, anon;
revoke execute on function public.end_stock_taker_session(uuid) from public, anon;
revoke execute on function public.get_stock_taker_context() from public, anon;

grant execute on function public.create_stock_take(uuid, uuid) to authenticated;
grant execute on function public.mark_stock_take_ready(uuid, uuid, uuid) to authenticated;
grant execute on function public.start_stock_take(uuid, uuid, uuid) to authenticated;
grant execute on function public.move_stock_take_to_review(uuid, uuid, uuid) to authenticated;
grant execute on function public.complete_stock_take(uuid, uuid, uuid) to authenticated;
grant execute on function public.reopen_stock_take(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.start_stock_taker_session(uuid, uuid, uuid) to authenticated;
grant execute on function public.end_stock_taker_session(uuid) to authenticated;
grant execute on function public.get_stock_taker_context() to authenticated;
