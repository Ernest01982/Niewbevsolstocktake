create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete restrict,
  warehouse_id uuid,
  actor_user_id uuid references public.profiles (user_id) on delete restrict,
  action text not null check (length(btrim(action)) between 1 and 120),
  entity_type text not null check (length(btrim(entity_type)) between 1 and 80),
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  occurred_at timestamptz not null default now(),
  constraint audit_logs_warehouse_company_fkey
    foreign key (warehouse_id, company_id)
    references public.warehouses (id, company_id)
    on delete restrict
);

comment on table public.audit_logs is
  'Append-only audit foundation. Application mutations must use narrow audited server operations.';

create index audit_logs_company_id_idx on public.audit_logs (company_id);
create index audit_logs_warehouse_id_idx on public.audit_logs (warehouse_id);
create index audit_logs_actor_user_id_idx on public.audit_logs (actor_user_id);
create index audit_logs_entity_idx on public.audit_logs (entity_type, entity_id);
create index audit_logs_occurred_at_idx on public.audit_logs (occurred_at desc);

create function private.reject_immutable_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception '% rows are immutable.', tg_table_name
    using errcode = '55000';
end;
$$;

revoke all on function private.reject_immutable_mutation() from public;

create trigger audit_logs_reject_update_or_delete
before update or delete on public.audit_logs
for each row execute function private.reject_immutable_mutation();

alter table public.audit_logs enable row level security;
alter table public.audit_logs force row level security;

create policy audit_logs_select_management
on public.audit_logs
for select
to authenticated
using (
  case
    when warehouse_id is null then private.can_access_company(
      company_id,
      array['super_admin', 'admin']::public.membership_role[]
    )
    else private.can_access_warehouse(
      company_id,
      warehouse_id,
      array['admin', 'manager']::public.membership_role[]
    )
  end
);
