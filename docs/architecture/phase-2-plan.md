# Phase 2 product and import layer

Status: implemented against the frozen Version 1 scope.

## Boundaries

The product master is company-global. Source files remain customer-owned and their headings are never inferred: callers supply an explicit mapping from source headings to the canonical logical fields. Product identity requires `product_code` and `name`; brand, barcode, and packaging fields are optional. Present packaging factors must be positive whole numbers. Missing packaging remains `null` so later counting screens can block only the affected pallet/layer/case entry path.

SOH snapshots are warehouse and stock-take specific. Phase 2 introduces the minimum `stock_takes` identity/state record needed to enforce that relationship; Phase 3 owns lifecycle RPCs, sessions, and transition rules. The database already enforces one open `ACTIVE`/`RECOUNT`/`REVIEW`/`REOPENED` stock take per warehouse.

## Migration sequence

1. `phase_2_types_and_product_master`
2. `phase_2_imports_and_snapshots`
3. `phase_2_import_operations`
4. `phase_2_rls_grants_and_hardening`
5. `phase_2_foreign_key_indexes`

## Import contract

`import_product_master` accepts an array of JSON objects plus a logical-to-source column map. Required-field failures and identifier conflicts reject only that row. Invalid optional packaging is stored as missing metadata and flags the row. Existing products are atomically updated by normalized company/product code.

`import_stock_snapshot` requires an allocated Admin or Manager, an existing DRAFT stock take in the selected warehouse, a snapshot timestamp, and explicit mappings for product code and SOH units. Unknown products, invalid whole numbers, and duplicate product lines reject only that row. Negative whole-number ERP stock is preserved; the frozen rules do not prohibit it.

Both operations return `success`, job/status information, and exact `total`, `accepted`, `flagged`, and `rejected` counts. Snapshot results also expose `has_unresolved_errors`; Phase 3 must refuse READY while unresolved snapshot errors remain. Each successful batch writes one immutable audit summary.

## Immutability and traceability

Snapshot lines and row-level issues reject UPDATE and DELETE through defense-in-depth triggers. Import headers retain source filename, optional SHA-256, source metadata, the explicit mapping, actor, timestamps, scope, and totals. Issues retain disposition, code, field, source row number, message, and raw row. Accepted snapshot lines retain their raw source row and source row number.

## Security

All Phase 2 tables have RLS enabled and forced. Brands and products are readable by active members of their company for later offline caching. Import metadata, issues, stock-take rows, and SOH are management-only and warehouse-scoped where applicable. Stock Takers receive zero SOH rows. No browser role has direct mutation privileges.

## Verification

- 33 Phase 2 schema, constraint, privilege, and immutability assertions.
- 39 Phase 2 tenant/warehouse/role RLS assertions.
- 24 Phase 2 partial-import, mapping, authorization, and audit assertions.
- Client mapping validation covers required fields, arbitrary headings, duplicate assignments, and unsupported-field rejection.
