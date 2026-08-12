create policy counts_select_submitter_or_management
on public.counts
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

create policy count_flags_select_management
on public.count_flags
for select
to authenticated
using (
  (select private.can_access_warehouse(
    company_id, warehouse_id,
    array['admin', 'manager']::public.membership_role[]
  ))
);

revoke all on table public.counts, public.count_flags from anon, authenticated;
grant select on table public.counts, public.count_flags to authenticated;

revoke all on function private.parse_count_quantity(jsonb)
from public, anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
