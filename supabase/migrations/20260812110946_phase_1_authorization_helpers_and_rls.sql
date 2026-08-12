create function private.is_permanent_user()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false;
$$;

create function private.can_access_company(
  target_company_id uuid,
  allowed_roles public.membership_role[] default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_permanent_user()
    and exists (
      select 1
      from public.company_memberships as membership
      join public.profiles as profile
        on profile.user_id = membership.user_id
      where membership.company_id = target_company_id
        and membership.user_id = (select auth.uid())
        and membership.status = 'active'
        and profile.status = 'active'
        and (
          allowed_roles is null
          or membership.role = any (allowed_roles)
          or membership.role = 'super_admin'
        )
    );
$$;

create function private.can_access_warehouse(
  target_company_id uuid,
  target_warehouse_id uuid,
  allowed_roles public.membership_role[] default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_permanent_user()
    and (
      private.can_access_company(
        target_company_id,
        array['super_admin']::public.membership_role[]
      )
      or exists (
        select 1
        from public.warehouse_memberships as allocation
        join public.company_memberships as membership
          on membership.company_id = allocation.company_id
          and membership.user_id = allocation.user_id
          and membership.role = allocation.role
        join public.profiles as profile
          on profile.user_id = allocation.user_id
        where allocation.company_id = target_company_id
          and allocation.warehouse_id = target_warehouse_id
          and allocation.user_id = (select auth.uid())
          and allocation.status = 'active'
          and membership.status = 'active'
          and profile.status = 'active'
          and (allowed_roles is null or allocation.role = any (allowed_roles))
      )
    );
$$;

create function private.shares_accessible_warehouse(
  target_company_id uuid,
  target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.warehouse_memberships as target
    where target.company_id = target_company_id
      and target.user_id = target_user_id
      and target.status = 'active'
      and private.can_access_warehouse(
        target.company_id,
        target.warehouse_id,
        array['admin', 'manager']::public.membership_role[]
      )
  );
$$;

revoke all on function private.is_permanent_user() from public;
revoke all on function private.can_access_company(uuid, public.membership_role[]) from public;
revoke all on function private.can_access_warehouse(uuid, uuid, public.membership_role[]) from public;
revoke all on function private.shares_accessible_warehouse(uuid, uuid) from public;

grant usage on schema private to authenticated;
grant execute on function private.is_permanent_user() to authenticated;
grant execute on function private.can_access_company(uuid, public.membership_role[]) to authenticated;
grant execute on function private.can_access_warehouse(uuid, uuid, public.membership_role[]) to authenticated;
grant execute on function private.shares_accessible_warehouse(uuid, uuid) to authenticated;

create policy profiles_select_own
on public.profiles
for select
to authenticated
using (
  private.is_permanent_user()
  and user_id = (select auth.uid())
);

create policy companies_select_active_member
on public.companies
for select
to authenticated
using (private.can_access_company(id));

create policy warehouses_select_allocated_or_authorised_super_admin
on public.warehouses
for select
to authenticated
using (private.can_access_warehouse(company_id, id));

create policy company_memberships_select_authorised
on public.company_memberships
for select
to authenticated
using (
  (
    private.is_permanent_user()
    and user_id = (select auth.uid())
  )
  or private.can_access_company(
    company_id,
    array['super_admin']::public.membership_role[]
  )
  or private.shares_accessible_warehouse(company_id, user_id)
);

create policy warehouse_memberships_select_authorised
on public.warehouse_memberships
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
    array['admin', 'manager']::public.membership_role[]
  )
);
