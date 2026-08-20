# Phase 6 manager controls

Status: implemented and verified against the frozen Version 1 scope.

## Manager progress and variances

Progress uses the immutable snapshot product universe as its denominator. A product becomes covered after at least one immutable initial count exists. Counts are grouped by product, so Bulk, Pick Face, and preserved duplicate records cannot lift progress above 100%.

Variance is always derived, never edited. Initial physical units are the sum of every preserved initial count for a snapshot product. The latest completed full-product recount becomes the effective physical result while all prior rows remain immutable. Signed variance is physical units minus snapshot units; warehouse controls use the absolute whole-unit difference.

Only management RPCs return snapshot, physical, threshold, or variance values. Stock-taker APIs and direct RLS paths remain blind.

## Threshold precedence

The company default applies unless an active warehouse override exists. An active product override within the warehouse wins over both. Thresholds are inclusive tolerances: a line requires recount only when absolute variance is greater than its effective threshold.

Admins and explicitly authorised Super Admins may change warehouse/product thresholds through one audited RPC. Managers can inspect effective thresholds but cannot change policy.

## Recount control

A Manager/Admin may generate tasks from above-threshold variance lines and optionally filter by minimum unit difference, brand, or product. Tasks may be assigned to one active warehouse stock taker or left in the pool. A partial unique index prevents concurrent open tasks for the same stock-take/product pair.

Pool claims are a single conditional database update. Under simultaneous claims, one caller transitions the row and the other receives `task_unavailable`. Assigned tasks can be claimed only by their assignee.

Recounts are full-product blind counts rather than Bulk/Pick Face increments. Submission is idempotent, recalculates packaging on the server, creates one immutable result per task, and retains the original count history and generation-time variance snapshot.

## Duplicate flags and finalisation

Count flags are immutable except for one controlled `OPEN -> RESOLVED` transition with actor, timestamp, and required note. The transition is enforced by a narrow trigger and audited RPC.

Stock-take completion requires REVIEW state, no open recount tasks, and no open count flags. A privileged reopen still follows `REOPENED -> RECOUNT -> REVIEW -> COMPLETED`.

## Security boundaries

- Phase 6 tenant tables use enabled and forced RLS.
- Management reads require an active allocated Admin/Manager or explicitly authorised Super Admin path.
- Stock Takers never receive `recount_tasks` directly; `get_recount_work` returns only task identity, product/search/packaging fields, and claim state.
- No authenticated browser role can insert/update/delete Phase 6 control or recount rows directly.
- All privileged functions use an empty search path, explicit scope checks, narrow grants, and append-only audit events.

## Verification gate

- Threshold precedence and audit.
- Distinct-product progress capped at 100%.
- Derived variance and latest recount replacement semantics.
- Brand/product/user/pool generation and assignment.
- Atomic claim conflict behavior.
- Idempotent immutable recount submission.
- Full role/tenant negative RLS and blind payload assertions.
- Finalisation blocked by open recounts or count flags.
