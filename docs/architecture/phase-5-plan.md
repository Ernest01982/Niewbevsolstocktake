# Phase 5 recognition

Status: implemented against the frozen Version 1 scope.

## Recognition contract

The browser captures a JPEG from the environment-facing camera and invokes the authenticated `recognize-product` Edge Function. Recognition is behind the `RecognitionProvider` interface. The default deployment uses `manual_fallback` until these server-only secrets are configured:

- `RECOGNITION_PROVIDER_URL`
- `RECOGNITION_PROVIDER_API_KEY`
- `RECOGNITION_PROVIDER_NAME`
- `RECOGNITION_PROVIDER_MODEL`

The remote adapter receives the image plus company, warehouse, and stock-take context, and may return no more than three product UUID/confidence candidates. Business logic is not coupled to a provider. Provider absence, timeout, failure, low confidence, or no match returns immediately to cached manual search.

## Confidence and confirmation

Company settings default to a high threshold of 0.85 and medium threshold of 0.55. The database validates, deduplicates, and sorts candidates by confidence before assigning:

- `HIGH`: preselect the top product, but require operator confirmation.
- `MEDIUM`: show up to three candidates for confirmation.
- `LOW` / `NO_MATCH`: require cached manual search.

`recognition_events` logs the provider/model, top confidence, server-owned tier, candidate IDs/confidences, selected product, selection method, session, and timestamps. Selection is controlled and permanently locked. The payload contains no SOH or variance.

Manual cached selection also saves a durable IndexedDB recognition event before product counting starts. Offline records restart safely, use client-generated idempotency keys, sync in partial-result batches, and remain local until acknowledged.

## Transient media

`recognition-media` is a private 8 MB Storage bucket allowing JPEG, PNG, and WebP. The function uploads under the authenticated user's event path, calls the provider, records a deletion deadline no later than 48 hours after capture, and attempts deletion before returning.

A Vault-generated scheduler token never enters source control or the browser. `pg_cron` calls the cleanup function every 15 minutes through `pg_net`. The function validates the token through a server-only constant-length hash comparison, claims due work with `SKIP LOCKED`, retries failures with bounded backoff, and appends an immutable audit event for every cleanup failure.

## Verification

- 29 Phase 5 schema, threshold, Storage, schedule, grant, index, and immutability assertions.
- 15 Phase 5 role/tenant/warehouse RLS assertions.
- 31 Phase 5 recognition-tier, ordering, idempotency, confirmation, offline-event, batch, and cleanup assertions.
- 366 cumulative database assertions through Phase 5.
- 23 application tests including offline recognition restart recovery.
