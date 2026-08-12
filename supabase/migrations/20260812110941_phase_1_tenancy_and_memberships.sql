create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 160),
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_code text not null check (length(btrim(warehouse_code)) between 1 and 40),
  name text not null check (length(btrim(name)) between 1 and 160),
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouses_company_code_key unique (company_id, warehouse_code),
  constraint warehouses_id_company_key unique (id, company_id)
);

create table public.company_memberships (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  user_id uuid not null references public.profiles (user_id) on delete restrict,
  role public.membership_role not null,
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint company_memberships_company_user_key unique (company_id, user_id),
  constraint company_memberships_company_user_role_key unique (company_id, user_id, role)
);

create table public.warehouse_memberships (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  warehouse_id uuid not null,
  user_id uuid not null,
  role public.membership_role not null,
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouse_memberships_non_platform_role_check
    check (role in ('admin', 'manager', 'stock_taker')),
  constraint warehouse_memberships_warehouse_company_fkey
    foreign key (warehouse_id, company_id)
    references public.warehouses (id, company_id)
    on delete restrict,
  constraint warehouse_memberships_company_user_role_fkey
    foreign key (company_id, user_id, role)
    references public.company_memberships (company_id, user_id, role)
    on delete restrict,
  constraint warehouse_memberships_warehouse_user_key unique (warehouse_id, user_id)
);

comment on constraint warehouse_memberships_company_user_role_fkey
  on public.warehouse_memberships is
  'Prevents a client or privileged workflow from assigning a warehouse in another tenant or with a role different from the company membership.';

create trigger companies_set_updated_at
before update on public.companies
for each row execute function private.set_updated_at();

create trigger warehouses_set_updated_at
before update on public.warehouses
for each row execute function private.set_updated_at();

create trigger company_memberships_set_updated_at
before update on public.company_memberships
for each row execute function private.set_updated_at();

create trigger warehouse_memberships_set_updated_at
before update on public.warehouse_memberships
for each row execute function private.set_updated_at();

create unique index warehouse_memberships_one_active_manager_per_user_idx
  on public.warehouse_memberships (user_id)
  where role = 'manager' and status = 'active';

create index companies_status_idx on public.companies (status);
create index warehouses_company_id_idx on public.warehouses (company_id);
create index warehouses_status_idx on public.warehouses (status);
create index company_memberships_company_id_idx on public.company_memberships (company_id);
create index company_memberships_user_id_idx on public.company_memberships (user_id);
create index company_memberships_role_status_idx on public.company_memberships (role, status);
create index warehouse_memberships_company_id_idx on public.warehouse_memberships (company_id);
create index warehouse_memberships_warehouse_id_idx on public.warehouse_memberships (warehouse_id);
create index warehouse_memberships_user_id_idx on public.warehouse_memberships (user_id);
create index warehouse_memberships_role_status_idx on public.warehouse_memberships (role, status);
create index warehouse_memberships_warehouse_company_idx
  on public.warehouse_memberships (warehouse_id, company_id);
create index warehouse_memberships_company_user_role_idx
  on public.warehouse_memberships (company_id, user_id, role);

alter table public.companies enable row level security;
alter table public.companies force row level security;
alter table public.warehouses enable row level security;
alter table public.warehouses force row level security;
alter table public.company_memberships enable row level security;
alter table public.company_memberships force row level security;
alter table public.warehouse_memberships enable row level security;
alter table public.warehouse_memberships force row level security;
