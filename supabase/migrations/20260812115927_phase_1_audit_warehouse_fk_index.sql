drop index if exists public.audit_logs_warehouse_id_idx;

create index audit_logs_warehouse_company_idx
  on public.audit_logs (warehouse_id, company_id);
