# Version 1 test matrix

This matrix separates tests automated in Phase 0/1 from mandatory later-phase coverage. A later-phase row is not marked passed merely because its table or workflow does not yet exist.

## Phase 0 and Phase 1 automated tests

| ID           | Area         | Scenario                                              | Expected result                  | Automation |
| ------------ | ------------ | ----------------------------------------------------- | -------------------------------- | ---------- |
| P0-ENV-01    | Environment  | Missing Supabase URL or publishable key               | Startup validation fails clearly | Vitest     |
| P0-ENV-02    | Environment  | HTTP or malformed project URL                         | Rejected before client creation  | Vitest     |
| P0-ENV-03    | Secrets      | Service-role/secret-looking browser key               | Rejected before client creation  | Vitest     |
| P1-SCHEMA-01 | Schema       | Required Phase 1 tables and tenant columns            | All exist with expected types    | pgTAP      |
| P1-SCHEMA-02 | Schema       | Duplicate warehouse code in one company               | Rejected                         | pgTAP      |
| P1-SCHEMA-03 | Tenancy      | Warehouse membership references another company       | Rejected by composite FK         | pgTAP      |
| P1-SCHEMA-04 | Roles        | Manager receives two active warehouse allocations     | Rejected by partial unique index | pgTAP      |
| P1-RLS-01    | Anonymous    | Anonymous/unauthenticated select on any Phase 1 table | No rows                          | pgTAP      |
| P1-RLS-02    | Company      | Member reads own company                              | Allowed                          | pgTAP      |
| P1-RLS-03    | Company      | Member reads another company                          | Denied                           | pgTAP      |
| P1-RLS-04    | Warehouse    | Admin reads allocated warehouse                       | Allowed                          | pgTAP      |
| P1-RLS-05    | Warehouse    | Admin reads unallocated warehouse                     | Denied                           | pgTAP      |
| P1-RLS-06    | Warehouse    | Manager reads allocated warehouse                     | Allowed                          | pgTAP      |
| P1-RLS-07    | Warehouse    | Manager reads another warehouse/company               | Denied                           | pgTAP      |
| P1-RLS-08    | Membership   | Stock Taker reads another user's allocations          | Denied                           | pgTAP      |
| P1-RLS-09    | Super Admin  | Platform role without explicit company membership     | Tenant data denied               | pgTAP      |
| P1-RLS-10    | Super Admin  | Explicit super-admin company membership               | Company tenant data allowed      | pgTAP      |
| P1-RLS-11    | Inactive     | Inactive company or warehouse membership              | Access denied                    | pgTAP      |
| P1-AUDIT-01  | Audit        | Manager reads own warehouse audit                     | Allowed                          | pgTAP      |
| P1-AUDIT-02  | Audit        | Stock Taker reads audit                               | Denied                           | pgTAP      |
| P1-AUDIT-03  | Immutability | Authenticated UPDATE/DELETE audit row                 | Rejected                         | pgTAP      |
| P1-HARD-01   | RLS          | Every public Phase 1 table has RLS enabled/forced     | Pass                             | pgTAP      |
| P1-HARD-02   | Grants       | `anon` has no tenant table privileges                 | Pass                             | pgTAP      |

## Mandatory later-phase matrix

| Phase | Required coverage                                                                                                                                         |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2     | Packaging calculations; product tenant keys; flexible mapping; row-level import issues; immutable snapshot; import traceability                           |
| 3     | State transitions; one active stock take per warehouse; one active stock-taker session per user; completed rejection; reopen window/privilege/audit       |
| 4     | Local-first save; UUID idempotency; restart recovery; partial batch failure; duplicate retry; two devices counting same product/type; no lost valid count |
| 5     | High/medium/low/no-match recognition; wrong suggestion correction; offline cached search; 48-hour media cleanup and retry/failure reporting               |
| 6     | Threshold precedence; progress capped at 100%; duplicate flags; blind recount data; concurrent recount claim; brand/item/user/pool allocation             |
| 7     | Historical reports; exports; management-only activity insights; executive shrinkage units and percentage                                                  |
| 8     | Full RLS negative suite; offline chaos; concurrency; accessibility; performance; cleanup and production telemetry                                         |

## Full role/tenant RLS dimensions

Every new table is tested across unauthenticated, anonymous-auth, Stock Taker, Manager, Admin, explicitly authorised Super Admin, and service/server contexts. Each applicable role is tested against own row, same warehouse, other warehouse in same company, other company, inactive membership, forged tenant identifier, and direct REST-style table access. Restricted SOH/variance tests assert both zero row access and absence from stock-taker server payload contracts.
