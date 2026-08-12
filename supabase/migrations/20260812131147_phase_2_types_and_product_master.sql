create type public.stock_take_status as enum (
  'DRAFT',
  'READY',
  'ACTIVE',
  'RECOUNT',
  'REVIEW',
  'COMPLETED',
  'REOPENED'
);

create type public.import_kind as enum ('product_master', 'stock_snapshot');
create type public.import_job_status as enum (
  'processing',
  'completed',
  'completed_with_issues',
  'failed'
);
create type public.import_issue_disposition as enum ('flagged', 'rejected');

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  name text not null check (length(btrim(name)) between 1 and 160),
  normalized_name text generated always as (lower(btrim(name))) stored,
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint brands_company_normalized_name_key unique (company_id, normalized_name),
  constraint brands_id_company_key unique (id, company_id)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  brand_id uuid,
  product_code text not null check (length(btrim(product_code)) between 1 and 120),
  normalized_product_code text generated always as (lower(btrim(product_code))) stored,
  name text not null check (length(btrim(name)) between 1 and 240),
  normalized_name text generated always as (lower(btrim(name))) stored,
  barcode text check (barcode is null or length(btrim(barcode)) between 1 and 120),
  normalized_barcode text generated always as (nullif(lower(btrim(barcode)), '')) stored,
  units_per_case integer check (units_per_case is null or units_per_case > 0),
  cases_per_layer integer check (cases_per_layer is null or cases_per_layer > 0),
  cases_per_pallet integer check (cases_per_pallet is null or cases_per_pallet > 0),
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_brand_company_fkey
    foreign key (brand_id, company_id)
    references public.brands (id, company_id)
    on delete restrict,
  constraint products_company_normalized_code_key
    unique (company_id, normalized_product_code),
  constraint products_id_company_key unique (id, company_id)
);

comment on table public.products is
  'Company-global canonical product master. Customer source headings are mapped at import time; they are never inferred.';
comment on column public.products.units_per_case is
  'Nullable by design. Count paths requiring missing packaging metadata must be blocked.';
comment on column public.products.cases_per_layer is
  'Nullable by design. Count paths requiring missing packaging metadata must be blocked.';
comment on column public.products.cases_per_pallet is
  'Nullable by design. Count paths requiring missing packaging metadata must be blocked.';

create trigger brands_set_updated_at
before update on public.brands
for each row execute function private.set_updated_at();

create trigger products_set_updated_at
before update on public.products
for each row execute function private.set_updated_at();

create index brands_company_id_idx on public.brands (company_id);
create index brands_status_idx on public.brands (status);
create index products_company_id_idx on public.products (company_id);
create index products_brand_id_idx on public.products (brand_id);
create index products_status_idx on public.products (status);
create index products_company_name_idx on public.products (company_id, normalized_name);
create unique index products_company_barcode_key
  on public.products (company_id, normalized_barcode)
  where normalized_barcode is not null;

alter table public.brands enable row level security;
alter table public.brands force row level security;
alter table public.products enable row level security;
alter table public.products force row level security;
