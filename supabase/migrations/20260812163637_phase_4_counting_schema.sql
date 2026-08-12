create type public.count_type as enum ('BULK', 'PICK_FACE');
create type public.count_flag_type as enum ('DUPLICATE_PRODUCT_COUNT_TYPE');
create type public.count_flag_status as enum ('OPEN', 'RESOLVED');

create table public.counts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid not null,
  stock_take_id uuid not null,
  stock_taker_session_id uuid not null,
  product_id uuid not null,
  submitted_by uuid not null,
  count_type public.count_type not null,
  pallets bigint not null check (pallets >= 0),
  layers bigint not null check (layers >= 0),
  cases bigint not null check (cases >= 0),
  units bigint not null check (units >= 0),
  total_units bigint not null check (total_units >= 0),
  duration_ms integer check (duration_ms is null or duration_ms >= 0),
  idempotency_key uuid not null,
  submitted_at timestamptz not null default now(),
  constraint counts_stock_take_scope_fkey
    foreign key (stock_take_id, company_id, warehouse_id)
    references public.stock_takes (id, company_id, warehouse_id) on delete restrict,
  constraint counts_session_scope_fkey
    foreign key (stock_taker_session_id, company_id, warehouse_id, stock_take_id)
    references public.stock_taker_sessions (id, company_id, warehouse_id, stock_take_id)
    on delete restrict,
  constraint counts_product_company_fkey
    foreign key (product_id, company_id)
    references public.products (id, company_id) on delete restrict,
  constraint counts_company_submitter_fkey
    foreign key (company_id, submitted_by)
    references public.company_memberships (company_id, user_id) on delete restrict,
  constraint counts_idempotency_key_key unique (idempotency_key),
  constraint counts_id_scope_key unique (id, company_id, warehouse_id, stock_take_id)
);

comment on table public.counts is
  'Immutable initial physical counts. Duplicate product/count-type rows are preserved and flagged.';
comment on column public.counts.idempotency_key is
  'Client-generated durable queue identity. Acknowledged retries return the original immutable count.';

create table public.count_flags (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid not null,
  stock_take_id uuid not null,
  count_id uuid not null,
  flag_type public.count_flag_type not null,
  status public.count_flag_status not null default 'OPEN',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid,
  resolution_note text check (
    resolution_note is null or length(btrim(resolution_note)) between 1 and 500
  ),
  constraint count_flags_count_scope_fkey
    foreign key (count_id, company_id, warehouse_id, stock_take_id)
    references public.counts (id, company_id, warehouse_id, stock_take_id)
    on delete restrict,
  constraint count_flags_company_resolver_fkey
    foreign key (company_id, resolved_by)
    references public.company_memberships (company_id, user_id) on delete restrict,
  constraint count_flags_resolution_check check (
    (status = 'OPEN' and resolved_at is null and resolved_by is null and resolution_note is null)
    or (status = 'RESOLVED' and resolved_at is not null and resolved_by is not null
      and resolution_note is not null)
  ),
  constraint count_flags_count_type_key unique (count_id, flag_type)
);

comment on table public.count_flags is
  'Manager-review flags. Phase 4 creates duplicate flags; controlled resolution is added with manager controls.';

create trigger counts_reject_update_or_delete
before update or delete on public.counts
for each row execute function private.reject_immutable_mutation();

create trigger count_flags_reject_update_or_delete
before update or delete on public.count_flags
for each row execute function private.reject_immutable_mutation();

create index counts_company_id_idx on public.counts (company_id);
create index counts_warehouse_id_idx on public.counts (warehouse_id);
create index counts_stock_take_id_idx on public.counts (stock_take_id);
create index counts_product_id_idx on public.counts (product_id);
create index counts_submitted_by_idx on public.counts (submitted_by);
create index counts_session_scope_idx
  on public.counts (stock_taker_session_id, company_id, warehouse_id, stock_take_id);
create index counts_stock_take_scope_idx
  on public.counts (stock_take_id, company_id, warehouse_id);
create index counts_product_company_idx on public.counts (product_id, company_id);
create index counts_company_submitter_idx on public.counts (company_id, submitted_by);
create index counts_duplicate_lookup_idx
  on public.counts (stock_take_id, product_id, count_type, submitted_at);
create index counts_submitted_at_idx on public.counts (submitted_at desc);

create index count_flags_company_id_idx on public.count_flags (company_id);
create index count_flags_warehouse_id_idx on public.count_flags (warehouse_id);
create index count_flags_stock_take_id_idx on public.count_flags (stock_take_id);
create index count_flags_count_scope_idx
  on public.count_flags (count_id, company_id, warehouse_id, stock_take_id);
create index count_flags_company_resolver_idx on public.count_flags (company_id, resolved_by);
create index count_flags_status_idx on public.count_flags (status, created_at desc);

alter table public.counts enable row level security;
alter table public.counts force row level security;
alter table public.count_flags enable row level security;
alter table public.count_flags force row level security;
