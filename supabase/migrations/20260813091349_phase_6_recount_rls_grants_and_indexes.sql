create policy warehouse_settings_select_management
on public.warehouse_settings
for select
to authenticated
using (
  (select private.can_access_warehouse(
    company_id, warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ))
);

create policy product_warehouse_settings_select_management
on public.product_warehouse_settings
for select
to authenticated
using (
  (select private.can_access_warehouse(
    company_id, warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ))
);

create policy recount_batches_select_management
on public.recount_batches
for select
to authenticated
using (
  (select private.can_access_warehouse(
    company_id, warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ))
);

create policy recount_tasks_select_management
on public.recount_tasks
for select
to authenticated
using (
  (select private.can_access_warehouse(
    company_id, warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ))
);

create policy recount_counts_select_submitter_or_management
on public.recount_counts
for select
to authenticated
using (
  (
    (select private.is_permanent_user())
    and submitted_by = (select auth.uid())
  )
  or (select private.can_access_warehouse(
    company_id, warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ))
);

revoke all on table
  public.warehouse_settings,
  public.product_warehouse_settings,
  public.recount_batches,
  public.recount_tasks,
  public.recount_counts
from anon, authenticated;

grant select on table
  public.warehouse_settings,
  public.product_warehouse_settings,
  public.recount_batches,
  public.recount_tasks,
  public.recount_counts
to authenticated;

revoke execute on function public.get_manager_progress(uuid, uuid, uuid) from public, anon;
revoke execute on function public.get_variances(uuid, uuid, uuid, bigint, uuid, uuid) from public, anon;
revoke execute on function public.set_variance_threshold(uuid, uuid, bigint, boolean, uuid) from public, anon;
revoke execute on function public.set_company_variance_threshold(uuid, bigint) from public, anon;
revoke execute on function public.resolve_count_flag(uuid, text) from public, anon;
revoke execute on function public.create_recount_batch(uuid, uuid, uuid, bigint, uuid, uuid, uuid) from public, anon;
revoke execute on function public.assign_recount_tasks(uuid, uuid, uuid[], uuid) from public, anon;
revoke execute on function public.get_recount_work() from public, anon;
revoke execute on function public.claim_recount_task(uuid) from public, anon;
revoke execute on function public.submit_recount(jsonb) from public, anon;

grant execute on function public.get_manager_progress(uuid, uuid, uuid) to authenticated;
grant execute on function public.get_variances(uuid, uuid, uuid, bigint, uuid, uuid) to authenticated;
grant execute on function public.set_variance_threshold(uuid, uuid, bigint, boolean, uuid) to authenticated;
grant execute on function public.set_company_variance_threshold(uuid, bigint) to authenticated;
grant execute on function public.resolve_count_flag(uuid, text) to authenticated;
grant execute on function public.create_recount_batch(uuid, uuid, uuid, bigint, uuid, uuid, uuid) to authenticated;
grant execute on function public.assign_recount_tasks(uuid, uuid, uuid[], uuid) to authenticated;
grant execute on function public.get_recount_work() to authenticated;
grant execute on function public.claim_recount_task(uuid) to authenticated;
grant execute on function public.submit_recount(jsonb) to authenticated;

create index warehouse_settings_company_id_idx on public.warehouse_settings (company_id);
create index warehouse_settings_company_updater_idx on public.warehouse_settings (company_id, updated_by);
create index product_warehouse_settings_warehouse_scope_idx
  on public.product_warehouse_settings (warehouse_id, company_id);
create index product_warehouse_settings_product_scope_idx
  on public.product_warehouse_settings (product_id, company_id);
create index product_warehouse_settings_company_updater_idx on public.product_warehouse_settings (company_id, updated_by);

create index recount_batches_company_id_idx on public.recount_batches (company_id);
create index recount_batches_warehouse_id_idx on public.recount_batches (warehouse_id);
create index recount_batches_stock_take_scope_idx
  on public.recount_batches (stock_take_id, company_id, warehouse_id);
create index recount_batches_company_creator_idx on public.recount_batches (company_id, created_by);
create index recount_batches_status_idx on public.recount_batches (status, created_at desc);

create index recount_tasks_company_id_idx on public.recount_tasks (company_id);
create index recount_tasks_warehouse_id_idx on public.recount_tasks (warehouse_id);
create index recount_tasks_stock_take_id_idx on public.recount_tasks (stock_take_id);
create index recount_tasks_batch_scope_idx
  on public.recount_tasks (recount_batch_id, company_id, warehouse_id, stock_take_id);
create index recount_tasks_product_company_idx on public.recount_tasks (product_id, company_id);
create index recount_tasks_brand_company_idx on public.recount_tasks (brand_id, company_id);
create index recount_tasks_assignee_scope_idx
  on public.recount_tasks (company_id, warehouse_id, assigned_user_id, assignment_role);
create index recount_tasks_claimant_scope_idx
  on public.recount_tasks (company_id, warehouse_id, claimed_by, claim_role);
create index recount_tasks_claim_queue_idx
  on public.recount_tasks (stock_take_id, status, assigned_user_id, created_at);

create index recount_counts_company_id_idx on public.recount_counts (company_id);
create index recount_counts_warehouse_id_idx on public.recount_counts (warehouse_id);
create index recount_counts_stock_take_id_idx on public.recount_counts (stock_take_id);
create index recount_counts_task_scope_idx
  on public.recount_counts (recount_task_id, company_id, warehouse_id, stock_take_id, product_id);
create index recount_counts_session_scope_idx
  on public.recount_counts (stock_taker_session_id, company_id, warehouse_id, stock_take_id);
create index recount_counts_product_company_idx on public.recount_counts (product_id, company_id);
create index recount_counts_company_submitter_idx on public.recount_counts (company_id, submitted_by);
create index recount_counts_submitted_at_idx on public.recount_counts (submitted_at desc);

revoke all on all sequences in schema public from anon, authenticated;
