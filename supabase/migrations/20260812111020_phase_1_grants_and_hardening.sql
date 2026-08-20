revoke all on table
  public.profiles,
  public.companies,
  public.warehouses,
  public.company_memberships,
  public.warehouse_memberships,
  public.audit_logs
from anon, authenticated;

grant select on table
  public.profiles,
  public.companies,
  public.warehouses,
  public.company_memberships,
  public.warehouse_memberships,
  public.audit_logs
to authenticated;

revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
revoke all on function private.set_updated_at() from public, anon, authenticated;
revoke all on function private.reject_immutable_mutation() from public, anon, authenticated;

alter default privileges in schema public
  revoke all on tables from anon, authenticated;
alter default privileges in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges in schema public
  revoke execute on functions from public, anon, authenticated;

grant usage on schema public to anon, authenticated;

comment on schema private is
  'Non-exposed authorisation and trigger helpers. Never add this schema to the Data API exposed schemas.';
