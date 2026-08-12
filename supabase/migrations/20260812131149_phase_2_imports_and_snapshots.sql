create table public.stock_takes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid not null,
  status public.stock_take_status not null default 'DRAFT',
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_takes_warehouse_company_fkey
    foreign key (warehouse_id, company_id)
    references public.warehouses (id, company_id)
    on delete restrict,
  constraint stock_takes_company_creator_fkey
    foreign key (company_id, created_by)
    references public.company_memberships (company_id, user_id)
    on delete restrict,
  constraint stock_takes_id_company_warehouse_key
    unique (id, company_id, warehouse_id)
);

comment on table public.stock_takes is
  'Phase 2 identity and snapshot target. Lifecycle transitions and session operations are added in Phase 3.';

create unique index stock_takes_one_open_per_warehouse_idx
  on public.stock_takes (warehouse_id)
  where status in ('ACTIVE', 'RECOUNT', 'REVIEW', 'REOPENED');
create index stock_takes_company_id_idx on public.stock_takes (company_id);
create index stock_takes_warehouse_id_idx on public.stock_takes (warehouse_id);
create index stock_takes_status_idx on public.stock_takes (status);
create index stock_takes_created_by_idx on public.stock_takes (created_by);

create trigger stock_takes_set_updated_at
before update on public.stock_takes
for each row execute function private.set_updated_at();

create table public.import_jobs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid,
  stock_take_id uuid,
  kind public.import_kind not null,
  status public.import_job_status not null default 'processing',
  source_filename text not null check (length(btrim(source_filename)) between 1 and 255),
  source_sha256 text check (source_sha256 is null or source_sha256 ~ '^[0-9a-f]{64}$'),
  source_metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_metadata) = 'object'),
  column_mapping jsonb not null check (jsonb_typeof(column_mapping) = 'object'),
  snapshot_as_of timestamptz,
  total_rows integer not null default 0 check (total_rows >= 0),
  accepted_rows integer not null default 0 check (accepted_rows >= 0),
  flagged_rows integer not null default 0 check (flagged_rows >= 0),
  rejected_rows integer not null default 0 check (rejected_rows >= 0),
  created_by uuid not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint import_jobs_warehouse_company_fkey
    foreign key (warehouse_id, company_id)
    references public.warehouses (id, company_id)
    on delete restrict,
  constraint import_jobs_stock_take_scope_fkey
    foreign key (stock_take_id, company_id, warehouse_id)
    references public.stock_takes (id, company_id, warehouse_id)
    on delete restrict,
  constraint import_jobs_company_creator_fkey
    foreign key (company_id, created_by)
    references public.company_memberships (company_id, user_id)
    on delete restrict,
  constraint import_jobs_scope_check check (
    (
      kind = 'product_master'
      and warehouse_id is null
      and stock_take_id is null
      and snapshot_as_of is null
    )
    or (
      kind = 'stock_snapshot'
      and warehouse_id is not null
      and stock_take_id is not null
      and snapshot_as_of is not null
    )
  ),
  constraint import_jobs_completed_totals_check check (
    status in ('processing', 'failed')
    or total_rows = accepted_rows + flagged_rows + rejected_rows
  ),
  constraint import_jobs_id_company_key unique (id, company_id),
  constraint import_jobs_id_full_scope_key
    unique (id, company_id, warehouse_id, stock_take_id)
);

create table public.import_issues (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid,
  stock_take_id uuid,
  import_job_id uuid not null,
  row_number integer not null check (row_number > 0),
  disposition public.import_issue_disposition not null,
  issue_code text not null check (length(btrim(issue_code)) between 1 and 80),
  field_name text check (field_name is null or length(btrim(field_name)) between 1 and 120),
  message text not null check (length(btrim(message)) between 1 and 500),
  raw_row jsonb not null check (jsonb_typeof(raw_row) in ('object', 'array', 'string', 'number', 'boolean', 'null')),
  created_at timestamptz not null default now(),
  constraint import_issues_job_company_fkey
    foreign key (import_job_id, company_id)
    references public.import_jobs (id, company_id)
    on delete restrict,
  constraint import_issues_warehouse_company_fkey
    foreign key (warehouse_id, company_id)
    references public.warehouses (id, company_id)
    on delete restrict,
  constraint import_issues_stock_take_scope_fkey
    foreign key (stock_take_id, company_id, warehouse_id)
    references public.stock_takes (id, company_id, warehouse_id)
    on delete restrict
);

create table public.stock_snapshot_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid not null,
  stock_take_id uuid not null,
  product_id uuid not null,
  import_job_id uuid not null,
  quantity_on_hand bigint not null,
  source_row_number integer not null check (source_row_number > 0),
  source_row jsonb not null check (jsonb_typeof(source_row) = 'object'),
  snapshot_as_of timestamptz not null,
  created_at timestamptz not null default now(),
  constraint stock_snapshot_lines_stock_take_scope_fkey
    foreign key (stock_take_id, company_id, warehouse_id)
    references public.stock_takes (id, company_id, warehouse_id)
    on delete restrict,
  constraint stock_snapshot_lines_product_company_fkey
    foreign key (product_id, company_id)
    references public.products (id, company_id)
    on delete restrict,
  constraint stock_snapshot_lines_import_job_scope_fkey
    foreign key (import_job_id, company_id, warehouse_id, stock_take_id)
    references public.import_jobs (id, company_id, warehouse_id, stock_take_id)
    on delete restrict,
  constraint stock_snapshot_lines_stock_take_product_key
    unique (stock_take_id, product_id)
);

comment on table public.import_jobs is
  'Traceable import header containing the explicit source-to-logical column mapping and aggregate row outcomes.';
comment on table public.import_issues is
  'Append-only row-level flagged/rejected import outcomes. Bad rows do not fail the whole import.';
comment on table public.stock_snapshot_lines is
  'Immutable warehouse and stock-take-specific stock-on-hand snapshot. Never expose to Stock Takers.';

create function private.validate_import_issue_scope()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  job_company_id uuid;
  job_warehouse_id uuid;
  job_stock_take_id uuid;
begin
  select job.company_id, job.warehouse_id, job.stock_take_id
  into job_company_id, job_warehouse_id, job_stock_take_id
  from public.import_jobs as job
  where job.id = new.import_job_id;

  if not found
    or new.company_id is distinct from job_company_id
    or new.warehouse_id is distinct from job_warehouse_id
    or new.stock_take_id is distinct from job_stock_take_id then
    raise exception 'Import issue scope must match its import job.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_import_issue_scope() from public;

create trigger import_issues_validate_scope
before insert on public.import_issues
for each row execute function private.validate_import_issue_scope();

create trigger import_issues_reject_update_or_delete
before update or delete on public.import_issues
for each row execute function private.reject_immutable_mutation();

create trigger stock_snapshot_lines_reject_update_or_delete
before update or delete on public.stock_snapshot_lines
for each row execute function private.reject_immutable_mutation();

create index import_jobs_company_id_idx on public.import_jobs (company_id);
create index import_jobs_warehouse_id_idx on public.import_jobs (warehouse_id);
create index import_jobs_stock_take_id_idx on public.import_jobs (stock_take_id);
create index import_jobs_status_started_idx on public.import_jobs (status, started_at desc);
create index import_jobs_created_by_idx on public.import_jobs (created_by);
create index import_issues_company_id_idx on public.import_issues (company_id);
create index import_issues_warehouse_id_idx on public.import_issues (warehouse_id);
create index import_issues_stock_take_id_idx on public.import_issues (stock_take_id);
create index import_issues_job_row_idx on public.import_issues (import_job_id, row_number);
create index import_issues_disposition_idx on public.import_issues (disposition);
create index stock_snapshot_lines_company_id_idx on public.stock_snapshot_lines (company_id);
create index stock_snapshot_lines_warehouse_id_idx on public.stock_snapshot_lines (warehouse_id);
create index stock_snapshot_lines_stock_take_id_idx on public.stock_snapshot_lines (stock_take_id);
create index stock_snapshot_lines_product_id_idx on public.stock_snapshot_lines (product_id);
create index stock_snapshot_lines_import_job_id_idx on public.stock_snapshot_lines (import_job_id);

alter table public.stock_takes enable row level security;
alter table public.stock_takes force row level security;
alter table public.import_jobs enable row level security;
alter table public.import_jobs force row level security;
alter table public.import_issues enable row level security;
alter table public.import_issues force row level security;
alter table public.stock_snapshot_lines enable row level security;
alter table public.stock_snapshot_lines force row level security;
