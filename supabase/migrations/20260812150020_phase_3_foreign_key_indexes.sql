create index stock_taker_sessions_membership_idx
  on public.stock_taker_sessions (company_id, warehouse_id, user_id, membership_role);

create index stock_taker_sessions_stock_take_scope_idx
  on public.stock_taker_sessions (stock_take_id, company_id, warehouse_id);

create index stock_takes_company_completed_by_idx
  on public.stock_takes (company_id, completed_by);

create index stock_takes_company_reopened_by_idx
  on public.stock_takes (company_id, reopened_by);

drop index public.stock_takes_completed_by_idx;
drop index public.stock_takes_reopened_by_idx;
