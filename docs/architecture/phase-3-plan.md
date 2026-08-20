# Phase 3 stock-take lifecycle

Status: implemented against the frozen Version 1 scope.

## Boundaries and decisions

Phase 3 owns stock-take lifecycle transitions and durable warehouse stock-taker sessions. It does not add counts, recount tasks, variance data, or offline queues. The database remains the source of truth for state and concurrency; the frontend cannot update lifecycle or session rows directly.

A privileged reopen is recount-only. `REOPENED` can move only to `RECOUNT`, after which the normal `RECOUNT -> REVIEW -> COMPLETED` path applies. This prevents reopened stock takes from accepting new initial counts and guarantees explicit re-completion. Recount creation and its `REOPENED -> RECOUNT` operation belong to Phase 6.

## Migration sequence

1. `phase_3_settings_and_sessions`
2. `phase_3_state_machine`
3. `phase_3_lifecycle_operations`
4. `phase_3_snapshot_revalidation`
5. `phase_3_rls_grants_and_indexes`
6. `phase_3_foreign_key_indexes`

## Lifecycle contract

The database transition guard allows only:

- `DRAFT -> READY -> ACTIVE`
- `ACTIVE -> REVIEW` or `ACTIVE -> RECOUNT -> REVIEW`
- `REVIEW -> COMPLETED`
- `COMPLETED -> REOPENED -> RECOUNT`

Tenant/warehouse/creator identity and lifecycle timestamps are immutable outside a valid transition. READY requires the latest snapshot import to be complete, issue-free, non-empty, and a full validation of every immutable snapshot line. A clean retry may revalidate an identical prior line without duplicating or replacing it; a changed quantity conflicts with the immutable snapshot.

The existing partial unique index remains the concurrency authority for one `ACTIVE`/`RECOUNT`/`REVIEW`/`REOPENED` stock take per warehouse. Lifecycle operations lock the target row for short, deterministic transitions.

## Session contract

`stock_taker_sessions` has a global partial unique index on `user_id` for `ACTIVE` rows. A session is valid only for an active Stock Taker warehouse allocation and an `ACTIVE` or `RECOUNT` stock take. Repeating the same start is idempotent; trying to enter another warehouse returns a structured conflict. Entering REVIEW closes all active sessions for that stock take.

`get_stock_taker_context` returns only safe session, company, warehouse, and stock-take identity/status fields. It never returns SOH, snapshots, variance, or management metrics.

## Operations and audit

Phase 3 exposes narrow authenticated operations for create, READY, start, review, complete, reopen, session start/end, and safe context. Every mutation authorises from `auth.uid()` plus active database memberships, uses an empty search path and fully qualified relations, and writes an audit event where appropriate.

Reopen requires both an active platform `super_admin` profile and an active `super_admin` membership in the target company. It requires a nonblank reason and enforces `company_settings.reopen_window_days`, defaulting to three days.

## Verification

- 30 Phase 3 schema, transition, constraint, index, and privilege assertions.
- 15 Phase 3 tenant/warehouse/role RLS assertions.
- 34 Phase 3 lifecycle, snapshot retry, session, completion, reopen, and audit assertions.
- 219 cumulative database assertions through Phase 3.
