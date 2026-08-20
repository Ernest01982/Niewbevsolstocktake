# Phase 7: Admin catalogue, final approval, and exports

## Outcome

Phase 7 gives Admin and Super Admin users the controls needed to maintain the stock-item catalogue, accept a reviewed result with a fully audited exception, and download completed physical counts for downstream processing.

## Role boundary

- Stock Takers submit immutable blind counts and recounts.
- Managers monitor progress, manage recount work, resolve flags, and move the stock take to REVIEW.
- Admin and authorised Super Admin users give final approval.
- Only Admin and authorised Super Admin users can maintain products, override outstanding review work, create SAGE files, or read export history.

## Product catalogue

- Single-item create and update operations use the controlled `save_product` RPC.
- Products are archived with the existing inactive status; no product is hard-deleted.
- Product code and barcode uniqueness remain company-scoped database constraints.
- CSV uploads require explicit Product code and Product name column mapping.
- Bulk import results preserve accepted, flagged, and rejected row totals and row-level issues.
- Every single-item and bulk change writes an audit event.

## Final approval

- Normal completion is restricted to Admin and authorised Super Admin users.
- Normal completion still requires all recounts and flags to be closed.
- The exception path requires a non-blank approval reason and REVIEW state.
- The audit record preserves the variance summary and identifiers of every open recount and flag at approval time.
- Completed stock takes remain locked against later count submission.

## Exports

- Export creation is restricted to completed stock takes and Admin/Super Admin users.
- The generic SAGE count CSV contains `ItemCode` and `Quantity`.
- The reconciliation CSV contains product, warehouse, system quantity, counted quantity, and variance.
- Each download creates a server-owned immutable history row and audit event.
- A customer-supplied SAGE template is still required before claiming compatibility with a specific SAGE product, module, or multi-store layout.

## Verification

- Database tests cover role denial, product create/archive, override reasons, audit metadata, completed-only exports, and export-history RLS.
- Frontend tests cover CSV parsing and safe CSV quoting.
- The full typecheck, lint, unit test, database test, and production build gates must pass before deployment.
