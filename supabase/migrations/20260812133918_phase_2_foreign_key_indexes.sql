create index products_brand_company_idx
  on public.products (brand_id, company_id);

create index stock_takes_warehouse_company_idx
  on public.stock_takes (warehouse_id, company_id);
create index stock_takes_company_creator_idx
  on public.stock_takes (company_id, created_by);

create index import_jobs_warehouse_company_idx
  on public.import_jobs (warehouse_id, company_id);
create index import_jobs_stock_take_scope_idx
  on public.import_jobs (stock_take_id, company_id, warehouse_id);
create index import_jobs_company_creator_idx
  on public.import_jobs (company_id, created_by);

create index import_issues_job_company_idx
  on public.import_issues (import_job_id, company_id);
create index import_issues_warehouse_company_idx
  on public.import_issues (warehouse_id, company_id);
create index import_issues_stock_take_scope_idx
  on public.import_issues (stock_take_id, company_id, warehouse_id);

create index stock_snapshot_lines_stock_take_scope_idx
  on public.stock_snapshot_lines (stock_take_id, company_id, warehouse_id);
create index stock_snapshot_lines_product_company_idx
  on public.stock_snapshot_lines (product_id, company_id);
create index stock_snapshot_lines_import_job_scope_idx
  on public.stock_snapshot_lines (
    import_job_id,
    company_id,
    warehouse_id,
    stock_take_id
  );
