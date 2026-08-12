import {
  acknowledgeCount,
  failCount,
  listSyncableCounts,
  markCountsSyncing,
  type LocalCountRecord,
} from './database';

export interface RecordAcknowledgement {
  acknowledged: boolean;
  count_id?: string;
  duplicate?: boolean;
  error?: { code?: string; message?: string };
  idempotency_key?: string;
  success: boolean;
}

export interface BatchSyncResult {
  results: RecordAcknowledgement[];
  success: boolean;
}

export interface CountServerRecord {
  [key: string]: null | number | string;
}

export type BatchSender = (
  records: CountServerRecord[],
) => Promise<BatchSyncResult>;

export interface SyncSummary {
  acknowledged: number;
  attempted: number;
  failed: number;
}

let activeSync: Promise<SyncSummary> | undefined;

function toServerRecord(record: LocalCountRecord): CountServerRecord {
  return {
    cases: record.cases,
    company_id: record.company_id,
    count_type: record.count_type,
    duration_ms: record.duration_ms,
    idempotency_key: record.idempotency_key,
    layers: record.layers,
    pallets: record.pallets,
    product_id: record.product_id,
    stock_take_id: record.stock_take_id,
    stock_taker_session_id: record.stock_taker_session_id,
    units: record.units,
    warehouse_id: record.warehouse_id,
  };
}

async function performSync(
  sendBatch: BatchSender,
  now = Date.now(),
): Promise<SyncSummary> {
  const records = await listSyncableCounts(now);
  if (records.length === 0) return { acknowledged: 0, attempted: 0, failed: 0 };

  const keys = records.map((record) => record.idempotency_key);
  await markCountsSyncing(keys);

  let batch: BatchSyncResult;
  try {
    batch = await sendBatch(records.map(toServerRecord));
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : 'Network synchronization failed.';
    await Promise.all(keys.map((key) => failCount(key, message, now)));
    return {
      acknowledged: 0,
      attempted: records.length,
      failed: records.length,
    };
  }

  const resultsByKey = new Map(
    batch.results.map((result) => [result.idempotency_key, result]),
  );
  let acknowledged = 0;
  let failed = 0;
  for (const record of records) {
    const result = resultsByKey.get(record.idempotency_key);
    if (
      result?.acknowledged &&
      result.success &&
      typeof result.count_id === 'string'
    ) {
      await acknowledgeCount(record.idempotency_key, {
        count_id: result.count_id,
        duplicate: result.duplicate ?? false,
      });
      acknowledged += 1;
    } else {
      await failCount(
        record.idempotency_key,
        result?.error?.message ?? 'The server did not acknowledge this count.',
        now,
      );
      failed += 1;
    }
  }
  return { acknowledged, attempted: records.length, failed };
}

export function syncPendingCounts(
  sendBatch: BatchSender,
  now = Date.now(),
): Promise<SyncSummary> {
  if (activeSync) return activeSync;
  activeSync = performSync(sendBatch, now).finally(() => {
    activeSync = undefined;
  });
  return activeSync;
}
