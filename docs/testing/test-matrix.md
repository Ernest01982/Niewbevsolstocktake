# Version 1 test matrix

This matrix separates tests automated through Phase 5 from mandatory later-phase coverage. A later-phase row is not marked passed merely because its table or workflow does not yet exist.

## Phase 0 through Phase 5 automated tests

| ID           | Area          | Scenario                                               | Expected result                      | Automation   |
| ------------ | ------------- | ------------------------------------------------------ | ------------------------------------ | ------------ |
| P0-ENV-01    | Environment   | Missing Supabase URL or publishable key                | Startup validation fails clearly     | Vitest       |
| P0-ENV-02    | Environment   | HTTP or malformed project URL                          | Rejected before client creation      | Vitest       |
| P0-ENV-03    | Secrets       | Service-role/secret-looking browser key                | Rejected before client creation      | Vitest       |
| P1-SCHEMA-01 | Schema        | Required Phase 1 tables and tenant columns             | All exist with expected types        | pgTAP        |
| P1-SCHEMA-02 | Schema        | Duplicate warehouse code in one company                | Rejected                             | pgTAP        |
| P1-SCHEMA-03 | Tenancy       | Warehouse membership references another company        | Rejected by composite FK             | pgTAP        |
| P1-SCHEMA-04 | Roles         | Manager receives two active warehouse allocations      | Rejected by partial unique index     | pgTAP        |
| P1-RLS-01    | Anonymous     | Anonymous/unauthenticated select on any Phase 1 table  | No rows                              | pgTAP        |
| P1-RLS-02    | Company       | Member reads own company                               | Allowed                              | pgTAP        |
| P1-RLS-03    | Company       | Member reads another company                           | Denied                               | pgTAP        |
| P1-RLS-04    | Warehouse     | Admin reads allocated warehouse                        | Allowed                              | pgTAP        |
| P1-RLS-05    | Warehouse     | Admin reads unallocated warehouse                      | Denied                               | pgTAP        |
| P1-RLS-06    | Warehouse     | Manager reads allocated warehouse                      | Allowed                              | pgTAP        |
| P1-RLS-07    | Warehouse     | Manager reads another warehouse/company                | Denied                               | pgTAP        |
| P1-RLS-08    | Membership    | Stock Taker reads another user's allocations           | Denied                               | pgTAP        |
| P1-RLS-09    | Super Admin   | Platform role without explicit company membership      | Tenant data denied                   | pgTAP        |
| P1-RLS-10    | Super Admin   | Explicit super-admin company membership                | Company tenant data allowed          | pgTAP        |
| P1-RLS-11    | Inactive      | Inactive company or warehouse membership               | Access denied                        | pgTAP        |
| P1-AUDIT-01  | Audit         | Manager reads own warehouse audit                      | Allowed                              | pgTAP        |
| P1-AUDIT-02  | Audit         | Stock Taker reads audit                                | Denied                               | pgTAP        |
| P1-AUDIT-03  | Immutability  | Authenticated UPDATE/DELETE audit row                  | Rejected                             | pgTAP        |
| P1-HARD-01   | RLS           | Every public Phase 1 table has RLS enabled/forced      | Pass                                 | pgTAP        |
| P1-HARD-02   | Grants        | `anon` has no tenant table privileges                  | Pass                                 | pgTAP        |
| P2-SCHEMA-01 | Products      | Company product codes/barcodes are unique              | Rejected on conflict                 | pgTAP        |
| P2-SCHEMA-02 | Tenancy       | Product references another company brand               | Rejected by composite FK             | pgTAP        |
| P2-SCHEMA-03 | Packaging     | Present packaging value is not positive                | Rejected                             | pgTAP        |
| P2-SCHEMA-04 | Stock take    | Two open stock takes in one warehouse                  | Rejected by partial index            | pgTAP        |
| P2-IMPORT-01 | Mapping       | Arbitrary source headings map to logical fields        | Accepted                             | Vitest/pgTAP |
| P2-IMPORT-02 | Partial rows  | Valid, flagged, and rejected rows share one import     | Valid rows preserved; totals exact   | pgTAP        |
| P2-IMPORT-03 | Traceability  | Import mapping, source hash, raw issue rows, audit     | Persisted                            | pgTAP        |
| P2-IMPORT-04 | Readiness     | Snapshot contains rejected rows                        | Unresolved-error result surfaced     | pgTAP        |
| P2-IMMUT-01  | Snapshot      | UPDATE/DELETE snapshot line                            | Rejected                             | pgTAP        |
| P2-IMMUT-02  | Issues        | UPDATE/DELETE import issue                             | Rejected                             | pgTAP        |
| P2-RLS-01    | Products      | Member reads own company product cache                 | Allowed                              | pgTAP        |
| P2-RLS-02    | Products      | Member reads another company products                  | Denied                               | pgTAP        |
| P2-RLS-03    | Restricted    | Stock Taker queries imports, stock takes, or SOH       | Zero rows                            | pgTAP        |
| P2-RLS-04    | Warehouse     | Manager/Admin queries another warehouse SOH            | Denied                               | pgTAP        |
| P2-RPC-01    | Authorisation | Stock Taker invokes either import RPC                  | Structured forbidden result          | pgTAP        |
| P3-STATE-01  | Lifecycle     | Invalid or skipped lifecycle transition                | Rejected by database trigger         | pgTAP        |
| P3-STATE-02  | Lifecycle     | READY with missing/unresolved snapshot                 | Rejected with structured result      | pgTAP        |
| P3-STATE-03  | Snapshot      | Clean retry revalidates identical immutable line       | Accepted without replacement         | pgTAP        |
| P3-CONC-01   | Stock take    | Second open stock take in warehouse                    | Rejected by partial unique index     | pgTAP        |
| P3-CONC-02   | Session       | User starts a second active warehouse session          | Rejected/recovered idempotently      | pgTAP        |
| P3-RLS-01    | Sessions      | Stock Taker reads another user's session               | Denied                               | pgTAP        |
| P3-RLS-02    | Sessions      | Manager/Admin reads unallocated warehouse sessions     | Denied                               | pgTAP        |
| P3-RLS-03    | Restricted    | Stock-taker context requests restricted stock fields   | Fields absent                        | pgTAP        |
| P3-CLOSE-01  | Completion    | COMPLETED stock take receives a new session            | Rejected                             | pgTAP        |
| P3-REOPEN-01 | Reopen        | Non-Super-Admin or unallocated platform admin reopens  | Forbidden                            | pgTAP        |
| P3-REOPEN-02 | Reopen        | Missing reason or expired window                       | Rejected                             | pgTAP        |
| P3-REOPEN-03 | Reopen        | Authorised reopen within window                        | Preserved and audited                | pgTAP        |
| P3-REOPEN-04 | Reopen        | REOPENED skips recount/review                          | Rejected                             | pgTAP        |
| P4-CALC-01   | Packaging     | Canonical pallet/layer/case/unit calculation           | Exact server/client total            | Vitest/pgTAP |
| P4-CALC-02   | Packaging     | Required packaging metadata is missing                 | Affected path blocked clearly        | Vitest/pgTAP |
| P4-COUNT-01  | Validation    | Negative or fractional quantity                        | Rejected                             | Vitest/pgTAP |
| P4-COUNT-02  | Zero count    | Operator explicitly enters zero physical stock         | Accepted as immutable zero count     | Vitest/pgTAP |
| P4-COUNT-03  | Duplicate     | Same product and count type submitted again            | Preserved, warned, and flagged       | Vitest/pgTAP |
| P4-COUNT-04  | Count type    | Same product counted as Bulk and Pick Face             | Both accepted without false flag     | pgTAP        |
| P4-SYNC-01   | Local first   | Count saved while offline                              | Durable IndexedDB record exists      | Vitest       |
| P4-SYNC-02   | Restart       | App restarts during sync                               | Record recovers to queued            | Vitest       |
| P4-SYNC-03   | Idempotency   | Same acknowledged UUID is retried                      | Original server count returned       | pgTAP        |
| P4-SYNC-04   | Partial batch | One record succeeds and one fails                      | Success acknowledged; failure kept   | Vitest/pgTAP |
| P4-SYNC-05   | Network       | Batch request loses connectivity                       | Local records retained/backoff       | Vitest       |
| P4-RLS-01    | Restricted    | Stock Taker queries count flags or SOH                 | Zero rows                            | pgTAP        |
| P4-RLS-02    | Tenancy       | Management queries unallocated warehouse/company count | Denied                               | pgTAP        |
| P4-CLOSE-01  | Completion    | Count sync arrives after completion                    | Rejected; local record retained      | Vitest/pgTAP |
| P5-REC-01    | Recognition   | Top confidence meets high threshold                    | High tier and confirmable preselect  | pgTAP        |
| P5-REC-02    | Recognition   | Top confidence meets medium threshold                  | Up to three confirmation candidates  | pgTAP        |
| P5-REC-03    | Recognition   | Low confidence or no match                             | Cached manual search required        | pgTAP        |
| P5-REC-04    | Correction    | Suggested product is wrong                             | Manual product confirmation logged   | pgTAP        |
| P5-REC-05    | Ordering      | Provider returns candidates out of order               | Database sorts before classification | pgTAP        |
| P5-SYNC-01   | Offline       | Manual cached selection made offline                   | Durable event syncs idempotently     | Vitest/pgTAP |
| P5-RLS-01    | Tenancy       | User queries another user's/company's recognition      | Denied                               | pgTAP        |
| P5-MEDIA-01  | Media         | Recognition image is captured                          | Private with deadline <= 48 hours    | pgTAP        |
| P5-MEDIA-02  | Cleanup       | Immediate deletion fails                               | Retried and immutable audit appended | pgTAP        |
| P5-MEDIA-03  | Scheduler     | Cleanup schedule/token is inspected                    | 15-minute Vault-authenticated job    | pgTAP        |

## Mandatory later-phase matrix

| Phase | Required coverage                                                                                                                             |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 6     | Threshold precedence; progress capped at 100%; duplicate flags; blind recount data; concurrent recount claim; brand/item/user/pool allocation |
| 7     | Historical reports; exports; management-only activity insights; executive shrinkage units and percentage                                      |
| 8     | Full RLS negative suite; offline chaos; concurrency; accessibility; performance; cleanup and production telemetry                             |

## Full role/tenant RLS dimensions

Every new table is tested across unauthenticated, anonymous-auth, Stock Taker, Manager, Admin, explicitly authorised Super Admin, and service/server contexts. Each applicable role is tested against own row, same warehouse, other warehouse in same company, other company, inactive membership, forged tenant identifier, and direct REST-style table access. Restricted SOH/variance tests assert both zero row access and absence from stock-taker server payload contracts.
