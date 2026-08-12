create policy company_settings_select_management
on public.company_settings
for select
to authenticated
using (
  (select private.can_access_company(
    company_id,
    array['super_admin', 'admin']::public.membership_role[]
  ))
);

create policy stock_taker_sessions_select_authorised
on public.stock_taker_sessions
for select
to authenticated
using (
  (
    (select private.is_permanent_user())
    and user_id = (select auth.uid())
  )
  or (select private.can_access_warehouse(
    company_id,
    warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ))
);

revoke all on table public.company_settings, public.stock_taker_sessions
from anon, authenticated;

grant select on table public.company_settings, public.stock_taker_sessions
to authenticated;

revoke all on all sequences in schema public from anon, authenticated;
