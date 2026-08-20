create policy brands_select_company_members
on public.brands
for select
to authenticated
using ((select private.can_access_company(company_id)));

create policy products_select_company_members
on public.products
for select
to authenticated
using ((select private.can_access_company(company_id)));

create policy stock_takes_select_management
on public.stock_takes
for select
to authenticated
using (
  (select private.can_access_warehouse(
    company_id,
    warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ))
);

create policy import_jobs_select_management
on public.import_jobs
for select
to authenticated
using (
  case
    when warehouse_id is null then (select private.can_access_company(
      company_id,
      array['admin']::public.membership_role[]
    ))
    else (select private.can_access_warehouse(
      company_id,
      warehouse_id,
      array['admin', 'manager']::public.membership_role[]
    ))
  end
);

create policy import_issues_select_management
on public.import_issues
for select
to authenticated
using (
  case
    when warehouse_id is null then (select private.can_access_company(
      company_id,
      array['admin']::public.membership_role[]
    ))
    else (select private.can_access_warehouse(
      company_id,
      warehouse_id,
      array['admin', 'manager']::public.membership_role[]
    ))
  end
);

create policy stock_snapshot_lines_select_management
on public.stock_snapshot_lines
for select
to authenticated
using (
  (select private.can_access_warehouse(
    company_id,
    warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ))
);

revoke all on table
  public.brands,
  public.products,
  public.stock_takes,
  public.import_jobs,
  public.import_issues,
  public.stock_snapshot_lines
from anon, authenticated;

grant select on table
  public.brands,
  public.products,
  public.stock_takes,
  public.import_jobs,
  public.import_issues,
  public.stock_snapshot_lines
to authenticated;

revoke execute on function
  public.import_product_master(uuid, text, text, jsonb, jsonb, jsonb),
  public.import_stock_snapshot(uuid, uuid, uuid, text, text, jsonb, jsonb, timestamptz, jsonb)
from public, anon;

grant execute on function
  public.import_product_master(uuid, text, text, jsonb, jsonb, jsonb),
  public.import_stock_snapshot(uuid, uuid, uuid, text, text, jsonb, jsonb, timestamptz, jsonb)
to authenticated;

revoke all on function private.import_mapped_text(jsonb, jsonb, text)
from public, anon, authenticated;
revoke all on function private.parse_optional_positive_integer(text)
from public, anon, authenticated;
revoke all on function private.parse_required_bigint(text)
from public, anon, authenticated;
revoke all on function private.validate_import_issue_scope()
from public, anon, authenticated;

revoke all on all sequences in schema public from anon, authenticated;
