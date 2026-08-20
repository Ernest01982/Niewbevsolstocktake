create type public.stock_taker_session_status as enum ('ACTIVE', 'ENDED');

create table public.company_settings (
  company_id uuid primary key references public.companies (id) on delete restrict,
  reopen_window_days integer not null default 3 check (reopen_window_days >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column public.company_settings.reopen_window_days is
  'Calendar days after completion during which a privileged Super Admin may reopen a stock take.';

insert into public.company_settings (company_id)
select company.id from public.companies as company
on conflict (company_id) do nothing;

create trigger company_settings_set_updated_at
before update on public.company_settings
for each row execute function private.set_updated_at();

alter table public.stock_takes
  add column ready_at timestamptz,
  add column started_at timestamptz,
  add column completed_at timestamptz,
  add column completed_by uuid,
  add column reopened_at timestamptz,
  add column reopened_by uuid,
  add column reopen_reason text,
  add column reopen_count integer not null default 0 check (reopen_count >= 0);

update public.stock_takes
set ready_at = created_at, started_at = created_at,
    completed_at = updated_at, completed_by = created_by
where status = 'COMPLETED';

alter table public.stock_takes
  add constraint stock_takes_company_completed_by_fkey
    foreign key (company_id, completed_by)
    references public.company_memberships (company_id, user_id) on delete restrict,
  add constraint stock_takes_company_reopened_by_fkey
    foreign key (company_id, reopened_by)
    references public.company_memberships (company_id, user_id) on delete restrict,
  add constraint stock_takes_reopen_reason_check
    check (reopen_reason is null or length(btrim(reopen_reason)) between 1 and 500),
  add constraint stock_takes_lifecycle_metadata_check check (
    case status
      when 'DRAFT' then ready_at is null and started_at is null and completed_at is null
        and completed_by is null and reopened_at is null and reopened_by is null
        and reopen_reason is null and reopen_count = 0
      when 'READY' then ready_at is not null and started_at is null and completed_at is null
        and completed_by is null and reopened_at is null and reopened_by is null
        and reopen_reason is null and reopen_count = 0
      when 'ACTIVE' then ready_at is not null and started_at is not null and completed_at is null
        and completed_by is null and reopened_at is null and reopened_by is null
        and reopen_reason is null and reopen_count = 0
      when 'RECOUNT' then ready_at is not null and started_at is not null
        and completed_at is null and completed_by is null
      when 'REVIEW' then ready_at is not null and started_at is not null
        and completed_at is null and completed_by is null
      when 'COMPLETED' then ready_at is not null and started_at is not null
        and completed_at is not null and completed_by is not null
      when 'REOPENED' then ready_at is not null and started_at is not null
        and completed_at is not null and completed_by is not null
        and reopened_at is not null and reopened_by is not null
        and reopen_reason is not null and reopen_count > 0
    end
  );

create index stock_takes_completed_by_idx on public.stock_takes (completed_by);
create index stock_takes_reopened_by_idx on public.stock_takes (reopened_by);
create index stock_takes_completed_at_idx on public.stock_takes (completed_at desc);

alter table public.warehouse_memberships
  add constraint warehouse_memberships_full_role_key
  unique (company_id, warehouse_id, user_id, role);

create table public.stock_taker_sessions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid not null,
  stock_take_id uuid not null,
  user_id uuid not null,
  membership_role public.membership_role not null default 'stock_taker'
    check (membership_role = 'stock_taker'),
  status public.stock_taker_session_status not null default 'ACTIVE',
  started_at timestamptz not null default now(),
  last_active_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_taker_sessions_stock_take_scope_fkey
    foreign key (stock_take_id, company_id, warehouse_id)
    references public.stock_takes (id, company_id, warehouse_id) on delete restrict,
  constraint stock_taker_sessions_membership_fkey
    foreign key (company_id, warehouse_id, user_id, membership_role)
    references public.warehouse_memberships (company_id, warehouse_id, user_id, role)
    on delete restrict,
  constraint stock_taker_sessions_status_timestamps_check check (
    (status = 'ACTIVE' and ended_at is null)
    or (status = 'ENDED' and ended_at is not null)
  ),
  constraint stock_taker_sessions_id_scope_key
    unique (id, company_id, warehouse_id, stock_take_id)
);

comment on table public.stock_taker_sessions is
  'Durable warehouse stock-taker sessions. A user may have only one ACTIVE session globally.';

create unique index stock_taker_sessions_one_active_per_user_idx
  on public.stock_taker_sessions (user_id) where status = 'ACTIVE';
create index stock_taker_sessions_company_id_idx on public.stock_taker_sessions (company_id);
create index stock_taker_sessions_warehouse_id_idx on public.stock_taker_sessions (warehouse_id);
create index stock_taker_sessions_stock_take_id_idx on public.stock_taker_sessions (stock_take_id);
create index stock_taker_sessions_user_id_idx on public.stock_taker_sessions (user_id);
create index stock_taker_sessions_status_idx on public.stock_taker_sessions (status);
create index stock_taker_sessions_last_active_at_idx on public.stock_taker_sessions (last_active_at desc);

create trigger stock_taker_sessions_set_updated_at
before update on public.stock_taker_sessions
for each row execute function private.set_updated_at();

alter table public.company_settings enable row level security;
alter table public.company_settings force row level security;
alter table public.stock_taker_sessions enable row level security;
alter table public.stock_taker_sessions force row level security;
