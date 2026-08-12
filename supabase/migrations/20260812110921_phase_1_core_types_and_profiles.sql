create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

create type public.record_status as enum ('active', 'inactive');
create type public.membership_role as enum (
  'super_admin',
  'admin',
  'manager',
  'stock_taker'
);
create type public.platform_role as enum ('super_admin');

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (length(btrim(display_name)) between 1 and 120),
  platform_role public.platform_role,
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column public.profiles.platform_role is
  'Platform eligibility only. Tenant access still requires an active company membership.';

create function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create index profiles_status_idx on public.profiles (status);

alter table public.profiles enable row level security;
alter table public.profiles force row level security;
