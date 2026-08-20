create type public.variance_threshold_source as enum ('COMPANY', 'WAREHOUSE', 'PRODUCT');
create type public.recount_batch_status as enum ('OPEN', 'COMPLETED');
create type public.recount_task_status as enum ('UNASSIGNED', 'ASSIGNED', 'CLAIMED', 'COMPLETED');

alter table public.company_settings
  add column default_variance_threshold_units bigint not null default 0
    check (default_variance_threshold_units >= 0);

comment on column public.company_settings.default_variance_threshold_units is
  'Company fallback. A variance must be greater than this whole-unit threshold to require recount.';

create table public.warehouse_settings (
  warehouse_id uuid primary key,
  company_id uuid not null,
  variance_threshold_units bigint not null default 0 check (variance_threshold_units >= 0),
  variance_threshold_active boolean not null default false,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouse_settings_warehouse_scope_fkey
    foreign key (warehouse_id, company_id)
    references public.warehouses (id, company_id) on delete restrict,
  constraint warehouse_settings_company_updater_fkey
    foreign key (company_id, updated_by)
    references public.company_memberships (company_id, user_id) on delete restrict,
  constraint warehouse_settings_id_scope_key unique (warehouse_id, company_id)
);

create table public.product_warehouse_settings (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid not null,
  product_id uuid not null,
  variance_threshold_units bigint not null default 0 check (variance_threshold_units >= 0),
  variance_threshold_active boolean not null default false,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_warehouse_settings_warehouse_scope_fkey
    foreign key (warehouse_id, company_id)
    references public.warehouses (id, company_id) on delete restrict,
  constraint product_warehouse_settings_product_scope_fkey
    foreign key (product_id, company_id)
    references public.products (id, company_id) on delete restrict,
  constraint product_warehouse_settings_company_updater_fkey
    foreign key (company_id, updated_by)
    references public.company_memberships (company_id, user_id) on delete restrict,
  constraint product_warehouse_settings_scope_key unique (company_id, warehouse_id, product_id),
  constraint product_warehouse_settings_id_scope_key
    unique (id, company_id, warehouse_id, product_id)
);

comment on table public.warehouse_settings is
  'Optional active warehouse variance threshold override, managed only through audited RPCs.';
comment on table public.product_warehouse_settings is
  'Most-specific optional product threshold override within one warehouse.';

create trigger warehouse_settings_set_updated_at
before update on public.warehouse_settings
for each row execute function private.set_updated_at();

create trigger product_warehouse_settings_set_updated_at
before update on public.product_warehouse_settings
for each row execute function private.set_updated_at();

create table public.recount_batches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid not null,
  stock_take_id uuid not null,
  created_by uuid not null,
  minimum_absolute_variance_units bigint check (minimum_absolute_variance_units is null or minimum_absolute_variance_units >= 0),
  status public.recount_batch_status not null default 'OPEN',
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint recount_batches_stock_take_scope_fkey
    foreign key (stock_take_id, company_id, warehouse_id)
    references public.stock_takes (id, company_id, warehouse_id) on delete restrict,
  constraint recount_batches_company_creator_fkey
    foreign key (company_id, created_by)
    references public.company_memberships (company_id, user_id) on delete restrict,
  constraint recount_batches_status_timestamps_check check (
    (status = 'OPEN' and completed_at is null)
    or (status = 'COMPLETED' and completed_at is not null)
  ),
  constraint recount_batches_id_scope_key
    unique (id, company_id, warehouse_id, stock_take_id)
);

create table public.recount_tasks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid not null,
  stock_take_id uuid not null,
  recount_batch_id uuid not null,
  product_id uuid not null,
  brand_id uuid,
  source_physical_units bigint not null check (source_physical_units >= 0),
  source_signed_variance_units bigint not null,
  source_absolute_variance_units bigint not null check (source_absolute_variance_units >= 0),
  effective_threshold_units bigint not null check (effective_threshold_units >= 0),
  threshold_source public.variance_threshold_source not null,
  assigned_user_id uuid,
  assignment_role public.membership_role not null default 'stock_taker'
    check (assignment_role = 'stock_taker'),
  claimed_by uuid,
  claim_role public.membership_role not null default 'stock_taker'
    check (claim_role = 'stock_taker'),
  status public.recount_task_status not null default 'UNASSIGNED',
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  completed_at timestamptz,
  constraint recount_tasks_batch_scope_fkey
    foreign key (recount_batch_id, company_id, warehouse_id, stock_take_id)
    references public.recount_batches (id, company_id, warehouse_id, stock_take_id)
    on delete restrict,
  constraint recount_tasks_product_scope_fkey
    foreign key (product_id, company_id)
    references public.products (id, company_id) on delete restrict,
  constraint recount_tasks_brand_scope_fkey
    foreign key (brand_id, company_id)
    references public.brands (id, company_id) on delete restrict,
  constraint recount_tasks_assigned_membership_fkey
    foreign key (company_id, warehouse_id, assigned_user_id, assignment_role)
    references public.warehouse_memberships (company_id, warehouse_id, user_id, role)
    on delete restrict,
  constraint recount_tasks_claimed_membership_fkey
    foreign key (company_id, warehouse_id, claimed_by, claim_role)
    references public.warehouse_memberships (company_id, warehouse_id, user_id, role)
    on delete restrict,
  constraint recount_tasks_status_metadata_check check (
    (status = 'UNASSIGNED' and assigned_user_id is null and claimed_by is null
      and claimed_at is null and completed_at is null)
    or (status = 'ASSIGNED' and assigned_user_id is not null and claimed_by is null
      and claimed_at is null and completed_at is null)
    or (status = 'CLAIMED' and claimed_by is not null and claimed_at is not null
      and completed_at is null and (assigned_user_id is null or assigned_user_id = claimed_by))
    or (status = 'COMPLETED' and claimed_by is not null and claimed_at is not null
      and completed_at is not null and (assigned_user_id is null or assigned_user_id = claimed_by))
  ),
  constraint recount_tasks_batch_product_key unique (recount_batch_id, product_id),
  constraint recount_tasks_id_scope_key
    unique (id, company_id, warehouse_id, stock_take_id, product_id)
);

create unique index recount_tasks_one_open_product_idx
  on public.recount_tasks (stock_take_id, product_id)
  where status in ('UNASSIGNED', 'ASSIGNED', 'CLAIMED');

create table public.recount_counts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid not null,
  stock_take_id uuid not null,
  recount_task_id uuid not null,
  stock_taker_session_id uuid not null,
  product_id uuid not null,
  submitted_by uuid not null,
  pallets bigint not null check (pallets >= 0),
  layers bigint not null check (layers >= 0),
  cases bigint not null check (cases >= 0),
  units bigint not null check (units >= 0),
  total_units bigint not null check (total_units >= 0),
  duration_ms integer check (duration_ms is null or duration_ms >= 0),
  idempotency_key uuid not null,
  submitted_at timestamptz not null default now(),
  constraint recount_counts_task_scope_fkey
    foreign key (recount_task_id, company_id, warehouse_id, stock_take_id, product_id)
    references public.recount_tasks (id, company_id, warehouse_id, stock_take_id, product_id)
    on delete restrict,
  constraint recount_counts_session_scope_fkey
    foreign key (stock_taker_session_id, company_id, warehouse_id, stock_take_id)
    references public.stock_taker_sessions (id, company_id, warehouse_id, stock_take_id)
    on delete restrict,
  constraint recount_counts_product_scope_fkey
    foreign key (product_id, company_id)
    references public.products (id, company_id) on delete restrict,
  constraint recount_counts_company_submitter_fkey
    foreign key (company_id, submitted_by)
    references public.company_memberships (company_id, user_id) on delete restrict,
  constraint recount_counts_idempotency_key_key unique (idempotency_key),
  constraint recount_counts_task_key unique (recount_task_id),
  constraint recount_counts_id_scope_key unique (id, company_id, warehouse_id, stock_take_id)
);

comment on table public.recount_batches is
  'Audited manager-generated groups of variance-driven blind recount work.';
comment on table public.recount_tasks is
  'Recount control rows. Source variance and threshold fields are management-only.';
comment on table public.recount_counts is
  'Immutable full-product recount results linked to their blind task and prior variance history.';

create trigger recount_counts_reject_update_or_delete
before update or delete on public.recount_counts
for each row execute function private.reject_immutable_mutation();

alter table public.warehouse_settings enable row level security;
alter table public.warehouse_settings force row level security;
alter table public.product_warehouse_settings enable row level security;
alter table public.product_warehouse_settings force row level security;
alter table public.recount_batches enable row level security;
alter table public.recount_batches force row level security;
alter table public.recount_tasks enable row level security;
alter table public.recount_tasks force row level security;
alter table public.recount_counts enable row level security;
alter table public.recount_counts force row level security;
