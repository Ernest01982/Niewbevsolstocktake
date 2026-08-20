create function private.enforce_stock_take_lifecycle()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.company_id is distinct from old.company_id
    or new.warehouse_id is distinct from old.warehouse_id
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'Stock take identity and scope are immutable.' using errcode = '55000';
  end if;

  if new.status = old.status then
    if new.ready_at is distinct from old.ready_at
      or new.started_at is distinct from old.started_at
      or new.completed_at is distinct from old.completed_at
      or new.completed_by is distinct from old.completed_by
      or new.reopened_at is distinct from old.reopened_at
      or new.reopened_by is distinct from old.reopened_by
      or new.reopen_reason is distinct from old.reopen_reason
      or new.reopen_count is distinct from old.reopen_count then
      raise exception 'Stock take lifecycle metadata is immutable outside a state transition.'
        using errcode = '55000';
    end if;
    return new;
  end if;

  if not (
    (old.status = 'DRAFT' and new.status = 'READY')
    or (old.status = 'READY' and new.status = 'ACTIVE')
    or (old.status = 'ACTIVE' and new.status in ('RECOUNT', 'REVIEW'))
    or (old.status = 'RECOUNT' and new.status = 'REVIEW')
    or (old.status = 'REVIEW' and new.status = 'COMPLETED')
    or (old.status = 'COMPLETED' and new.status = 'REOPENED')
    or (old.status = 'REOPENED' and new.status = 'RECOUNT')
  ) then
    raise exception 'Invalid stock take transition from % to %.', old.status, new.status
      using errcode = '23514';
  end if;

  case new.status
    when 'READY' then new.ready_at := now();
    when 'ACTIVE' then new.started_at := now();
    when 'COMPLETED' then
      if new.completed_by is null then
        raise exception 'A completing actor is required.' using errcode = '23514';
      end if;
      new.completed_at := now();
    when 'REOPENED' then
      if new.reopened_by is null or nullif(btrim(new.reopen_reason), '') is null then
        raise exception 'A reopening actor and reason are required.' using errcode = '23514';
      end if;
      new.reopened_at := now();
      new.reopen_count := old.reopen_count + 1;
    else null;
  end case;

  return new;
end;
$$;

revoke all on function private.enforce_stock_take_lifecycle()
from public, anon, authenticated;

create trigger stock_takes_enforce_lifecycle
before update on public.stock_takes
for each row execute function private.enforce_stock_take_lifecycle();

comment on table public.stock_takes is
  'Explicit immutable-scope lifecycle. REOPENED may only enter RECOUNT, preserving the recount-only reopen rule.';
