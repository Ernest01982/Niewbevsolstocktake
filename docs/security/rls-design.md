# Phase 1 RLS design

## Trust boundaries

The browser is untrusted. A supplied `company_id`, `warehouse_id`, role, or user ID never proves access. RLS resolves the caller from `auth.uid()` and checks active membership rows owned by the database. Auth anonymous users are treated as unauthorised even though Supabase maps them to the `authenticated` Postgres role.

The `private` schema is not exposed through the Data API. Small security-definer membership helpers live there solely to prevent recursive RLS checks. Each helper:

- validates a non-null caller and rejects an anonymous-auth JWT;
- queries fully qualified relations;
- uses `set search_path = ''`;
- is revoked from `PUBLIC` and granted only to `authenticated` for policy evaluation.

No helper trusts user metadata or client-provided role claims.

## Direct read policy matrix

| Table                   | Super Admin                                         | Admin                                          | Manager                                   | Stock Taker               |
| ----------------------- | --------------------------------------------------- | ---------------------------------------------- | ----------------------------------------- | ------------------------- |
| `companies`             | Active explicitly authorised company memberships    | Active member companies                        | Active member company                     | Active member company     |
| `warehouses`            | All warehouses in explicitly authorised company     | Allocated warehouses only                      | Allocated warehouse only                  | Allocated warehouses only |
| `profiles`              | Own profile                                         | Own profile                                    | Own profile                               | Own profile               |
| `company_memberships`   | All members in explicitly authorised company        | Self plus users sharing an allocated warehouse | Self plus users sharing managed warehouse | Self only                 |
| `warehouse_memberships` | All allocations in explicitly authorised company    | Allocations in own allocated warehouses        | Allocations in own managed warehouse      | Self only                 |
| `audit_logs`            | Company-wide within explicitly authorised companies | Company-level and allocated-warehouse events   | Allocated-warehouse events                | Denied                    |

An inactive company membership invalidates all access beneath it. An inactive warehouse membership invalidates warehouse-scoped access.

## Mutations

Phase 1 grants no direct INSERT, UPDATE, or DELETE access to the frontend for tenant/membership/audit tables. Development fixtures run as the database owner. Later management workflows must call narrow transactional functions with actor, scope, validation, and audit behavior tested together.

Audit rows have both privilege denial and a trigger that rejects UPDATE/DELETE. The trigger provides defense in depth for future privileged code that accidentally attempts mutation.

## Restricted stock data

SOH snapshots and variance views do not exist until later phases. When added, Stock Takers will receive neither table grants nor policies for those relations. Stock-taker context will be a narrow server contract that omits restricted columns entirely; filtering fields in the UI is prohibited as a control.

## Policy review checklist

- RLS enabled and forced on every exposed Phase 1 table.
- Explicit `TO authenticated`; no `auth.role()` checks.
- SELECT is separately granted because RLS does not provide table privileges.
- No policy contains an unconditional `true` predicate.
- Update policies, if added later, require both `USING` and `WITH CHECK`.
- Views added later use `security_invoker = true` or remain outside exposed schemas.
- Security-definer functions are never placed in `public` and have execution privileges reviewed.
