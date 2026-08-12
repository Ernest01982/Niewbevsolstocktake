# Phase 4 offline counting core

Status: implemented against the frozen Version 1 scope.

## Safety contract

A submitted count is first committed to durable IndexedDB. Only after that transaction completes does the interface confirm success and return to the next-product search. Each record carries a client-generated UUID idempotency key and remains in local storage after acknowledgement as non-syncable history for duplicate warnings. Queued, syncing, or failed records are never removed.

At startup, interrupted `syncing` records return to `queued`. Online and reconnect triggers use one coalesced sync operation, batches are capped at 50 client-side and 100 server-side, and retries use bounded exponential backoff. The server returns a result for every record; only individually acknowledged records become `acknowledged`. Network and record failures retain their full local payload and error.

## Canonical quantities

The client and server independently validate non-negative whole numbers and use the frozen formula:

```text
pallets × cases_per_pallet × units_per_case
+ layers × cases_per_layer × units_per_case
+ cases × units_per_case
+ units
```

The server is authoritative and recalculates `total_units` from the current company product master. A path requiring missing packaging metadata is rejected with the affected field and a correction message. At least one input must be explicitly entered in the UI; entering `0` is a valid zero physical count.

## Count and duplicate model

`counts` is immutable and tenant/warehouse/session/product relationships use composite foreign keys. `idempotency_key` is globally unique. Initial counts require the caller's active Stock Taker session and an `ACTIVE` stock take; REVIEW, COMPLETED, REOPENED, and ended sessions reject late counts.

Bulk and Pick Face are distinct count types. A transaction-level advisory lock serializes duplicate detection for a stock-take/product/type key. Every valid count is inserted. A later matching product/type count receives a warning and an immutable manager-only `count_flags` row; it is never replaced or discarded.

## Offline product cache and UI

Active company products are cached in paginated 1,000-row pages. Typed product code, name, and barcode search reads IndexedDB and continues working when refresh or connectivity fails. Recognition/camera handling remains Phase 5.

The mobile flow includes session recovery, safe warehouse context selection, text-labelled Online/Syncing/Offline state, cached search, product confirmation, Bulk/Pick Face selection, four quantity inputs, total preview, local duplicate warning, durable save, and immediate reset for the next product. The PWA remains prompt-update based so a normal update does not reload an active count.

## Security

Stock Takers may read only their own count rows and never receive count flags, SOH, snapshots, or variance. Management may read counts and flags only in allocated warehouses. No browser role can insert, update, or delete count/flag rows directly. `submit_count` and `sync_counts_batch` are narrow authenticated RPCs with explicit caller/session/scope validation, empty search paths, and denied anonymous execution.

## Verification

- 26 Phase 4 schema, constraint, immutability, grant, and index assertions.
- 16 Phase 4 role/tenant/warehouse RLS assertions.
- 30 Phase 4 calculation, idempotency, duplicate, partial-batch, authorization, audit, and completion assertions.
- 291 cumulative database assertions through Phase 4.
- 22 application tests, including packaging calculations and IndexedDB restart/partial-failure recovery.
