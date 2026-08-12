# Phase 1 and Phase 2 RLS design

## Trust boundaries

The browser is untrusted. A supplied `company_id`, `warehouse_id`, role, or user ID never proves access. RLS resolves the caller from `auth.uid()` and checks active membership rows owned by the database. Auth anonymous users are treated as unauthorised even though Supabase maps them to the `authenticated` Postgres role.

The `private` schema is not exposed through the Data API. Small security-definer membership helpers live there solely to prevent recursive RLS checks. Each helper:

- validates a non-null caller and rejects an anonymous-auth JWT;
- queries fully qualified relations;
- uses `set search_path = ''`;
- is revoked from `PUBLIC` and granted only to `authenticated` for policy evaluation.

No helper trusts user metadata or client-provided role claims.

## Direct read policy matrix

| Table                           | Super Admin                                         | Admin                                            | Manager                                   | Stock Taker               |
| ------------------------------- | --------------------------------------------------- | ------------------------------------------------ | ----------------------------------------- | ------------------------- |
| `companies`                     | Active explicitly authorised company memberships    | Active member companies                          | Active member company                     | Active member company     |
| `warehouses`                    | All warehouses in explicitly authorised company     | Allocated warehouses only                        | Allocated warehouse only                  | Allocated warehouses only |
| `profiles`                      | Own profile                                         | Own profile                                      | Own profile                               | Own profile               |
| `company_memberships`           | All members in explicitly authorised company        | Self plus users sharing an allocated warehouse   | Self plus users sharing managed warehouse | Self only                 |
| `warehouse_memberships`         | All allocations in explicitly authorised company    | Allocations in own allocated warehouses          | Allocations in own managed warehouse      | Self only                 |
| `audit_logs`                    | Company-wide within explicitly authorised companies | Company-level and allocated-warehouse events     | Allocated-warehouse events                | Denied                    |
| `brands` / `products`           | Authorised company                                  | Company-global                                   | Company-global                            | Company-global            |
| `stock_takes`                   | Authorised company warehouses                       | Allocated warehouses                             | Allocated warehouse                       | Denied                    |
| `import_jobs` / `import_issues` | Company and warehouse scope                         | Company product imports plus allocated snapshots | Allocated snapshot imports only           | Denied                    |
| `stock_snapshot_lines`          | Authorised company warehouses                       | Allocated warehouses                             | Allocated warehouse                       | Denied                    |

An inactive company membership invalidates all access beneath it. An inactive warehouse membership invalidates warehouse-scoped access.

## Mutations

Phase 1 and Phase 2 grant no direct INSERT, UPDATE, or DELETE access to the frontend for tenant, membership, product, import, snapshot, or audit tables. Development fixtures run as the database owner. Management imports call narrow transactional functions with actor, scope, validation, partial-row handling, and audit behavior tested together.

The two import RPCs are the deliberate exception to the rule that security-definer helpers remain outside `public`: PostgREST must expose these named server operations. Both use an empty search path, fully qualified objects, explicit permanent-user membership checks, structured errors, and immediate `PUBLIC`/`anon` EXECUTE revocation. Only `authenticated` receives EXECUTE; direct table writes remain denied.

Audit rows have both privilege denial and a trigger that rejects UPDATE/DELETE. The trigger provides defense in depth for future privileged code that accidentally attempts mutation.

## Restricted stock data

SOH snapshot rows exist in Phase 2 but Stock Takers receive no matching RLS policy, so direct queries return zero rows. Stock-taker context will be a narrow server contract that omits restricted columns entirely; filtering fields in the UI is prohibited as a control. Variance views remain deferred and will be management-only.

## Policy review checklist

- RLS enabled and forced on every exposed Phase 1/2 table.
- Explicit `TO authenticated`; no `auth.role()` checks.
- SELECT is separately granted because RLS does not provide table privileges.
- No policy contains an unconditional `true` predicate.
- Update policies, if added later, require both `USING` and `WITH CHECK`.
- Views added later use `security_invoker = true` or remain outside exposed schemas.
- Security-definer helpers stay in `private`; exposed RPC exceptions are documented, explicitly authorised, and have execution privileges reviewed.
