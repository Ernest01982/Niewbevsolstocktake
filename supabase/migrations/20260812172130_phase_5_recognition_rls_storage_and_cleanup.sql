insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'recognition-media',
  'recognition-media',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

comment on table public.recognition_events is
  'Recognition telemetry; private recognition-media objects are transient and deleted immediately after provider processing where possible.';

create policy recognition_events_select_owner_or_management
on public.recognition_events
for select
to authenticated
using (
  (
    private.is_permanent_user()
    and user_id = (select auth.uid())
  )
  or private.can_access_warehouse(
    company_id,
    warehouse_id,
    array['super_admin', 'admin', 'manager']::public.membership_role[]
  )
);

revoke all on table public.recognition_events from public, anon, authenticated;
grant select on table public.recognition_events to authenticated;

revoke all on function public.record_recognition_event(jsonb)
from public, anon, authenticated;
revoke all on function public.sync_recognition_events_batch(jsonb)
from public, anon, authenticated;
revoke all on function public.confirm_recognition_selection(
  uuid,
  uuid,
  public.recognition_selection_method
) from public, anon, authenticated;
revoke all on function public.claim_recognition_media_cleanup(integer)
from public, anon, authenticated;
revoke all on function public.complete_recognition_media_cleanup(uuid, boolean, text)
from public, anon, authenticated;

grant execute on function public.record_recognition_event(jsonb) to authenticated;
grant execute on function public.sync_recognition_events_batch(jsonb) to authenticated;
grant execute on function public.confirm_recognition_selection(
  uuid,
  uuid,
  public.recognition_selection_method
) to authenticated;
grant execute on function public.claim_recognition_media_cleanup(integer) to service_role;
grant execute on function public.complete_recognition_media_cleanup(uuid, boolean, text)
to service_role;

revoke all on table public.recognition_events from service_role;
grant select on table public.recognition_events to service_role;
