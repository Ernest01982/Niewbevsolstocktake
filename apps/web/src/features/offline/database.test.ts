import 'fake-indexeddb/auto';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  cacheProducts,
  countPendingRecords,
  enqueueManualRecognition,
  enqueueCount,
  getLocalCount,
  hasLocalDuplicate,
  markCountsSyncing,
  markRecognitionsSyncing,
  recoverInterruptedCounts,
  recoverInterruptedRecognitions,
  resetOfflineDatabaseForTests,
  searchCachedProducts,
  listSyncableRecognitions,
} from './database';
import { syncPendingCounts } from './sync';

const baseCount = {
  cases: 0,
  company_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  count_type: 'BULK' as const,
  created_at: '2026-08-12T12:00:00.000Z',
  duration_ms: 2500,
  idempotency_key: 'c1000000-0000-4000-8000-000000000001',
  layers: 0,
  pallets: 1,
  product_id: 'a3000000-0000-4000-8000-000000000001',
  product_name: 'Product One',
  stock_take_id: 'a4000000-0000-4000-8000-000000000001',
  stock_taker_session_id: 'a8000000-0000-4000-8000-000000000001',
  total_units: 720,
  units: 0,
  warehouse_id: 'a1000000-0000-4000-8000-000000000001',
};

beforeEach(async () => resetOfflineDatabaseForTests());

describe('offline database', () => {
  it('persists queued counts and recovers interrupted sync after restart', async () => {
    await enqueueCount(baseCount);
    await markCountsSyncing([baseCount.idempotency_key]);
    expect((await getLocalCount(baseCount.idempotency_key))?.status).toBe(
      'syncing',
    );

    expect(await recoverInterruptedCounts()).toBe(1);
    expect((await getLocalCount(baseCount.idempotency_key))?.status).toBe(
      'queued',
    );
    expect(await countPendingRecords()).toBe(1);
  });

  it('retains acknowledged local history for duplicate warning without resending it', async () => {
    await enqueueCount(baseCount);
    const summary = await syncPendingCounts(async () => ({
      success: true,
      results: [
        {
          acknowledged: true,
          count_id: 'a9000000-0000-4000-8000-000000000001',
          duplicate: false,
          idempotency_key: baseCount.idempotency_key,
          success: true,
        },
      ],
    }));

    expect(summary.acknowledged).toBe(1);
    expect((await getLocalCount(baseCount.idempotency_key))?.status).toBe(
      'acknowledged',
    );
    expect(await countPendingRecords()).toBe(0);
    expect(
      await hasLocalDuplicate(
        baseCount.stock_take_id,
        baseCount.product_id,
        baseCount.count_type,
      ),
    ).toBe(true);
  });

  it('keeps only failed records pending after a partial batch acknowledgement', async () => {
    const second = {
      ...baseCount,
      idempotency_key: 'c1000000-0000-4000-8000-000000000002',
      product_id: 'a3000000-0000-4000-8000-000000000002',
    };
    await enqueueCount(baseCount);
    await enqueueCount(second);

    const summary = await syncPendingCounts(async () => ({
      success: true,
      results: [
        {
          acknowledged: true,
          count_id: 'a9000000-0000-4000-8000-000000000001',
          idempotency_key: baseCount.idempotency_key,
          success: true,
        },
        {
          acknowledged: false,
          error: { message: 'Packaging metadata is missing.' },
          idempotency_key: second.idempotency_key,
          success: false,
        },
      ],
    }));

    expect(summary).toEqual({ acknowledged: 1, attempted: 2, failed: 1 });
    expect((await getLocalCount(baseCount.idempotency_key))?.status).toBe(
      'acknowledged',
    );
    expect((await getLocalCount(second.idempotency_key))?.status).toBe(
      'failed',
    );
    expect(await countPendingRecords()).toBe(1);
  });

  it('preserves every record when the network request fails', async () => {
    await enqueueCount(baseCount);
    const summary = await syncPendingCounts(async () => {
      throw new Error('Offline');
    });
    expect(summary.failed).toBe(1);
    expect((await getLocalCount(baseCount.idempotency_key))?.last_error).toBe(
      'Offline',
    );
  });

  it('serves typed product search from the offline cache', async () => {
    await cacheProducts([
      {
        barcode: '6001',
        cases_per_layer: 10,
        cases_per_pallet: 60,
        company_id: baseCount.company_id,
        id: baseCount.product_id,
        name: 'Sparkling Water',
        product_code: 'WATER-1',
        units_per_case: 12,
        updated_at: '2026-08-12T12:00:00.000Z',
      },
    ]);
    expect(
      (await searchCachedProducts(baseCount.company_id, 'spark')).length,
    ).toBe(1);
    expect(
      (await searchCachedProducts(baseCount.company_id, '6001'))[0]
        ?.product_code,
    ).toBe('WATER-1');
  });
});

describe('durable offline recognition queue', () => {
  it('recovers a manual recognition event after an interrupted sync', async () => {
    const event = await enqueueManualRecognition({
      candidates: [],
      captured_at: '2026-08-12T10:00:00.000Z',
      company_id: 'company-a',
      idempotency_key: 'recognition-1',
      model: 'cached-products-v1',
      provider: 'offline_manual_cache',
      selected_product_id: 'product-a',
      selection_method: 'MANUAL_SEARCH',
      stock_take_id: 'take-a',
      stock_taker_session_id: 'session-a',
      warehouse_id: 'warehouse-a',
    });
    await markRecognitionsSyncing([event.idempotency_key]);

    expect(await recoverInterruptedRecognitions()).toBe(1);
    expect(await listSyncableRecognitions()).toEqual([
      expect.objectContaining({
        idempotency_key: 'recognition-1',
        status: 'queued',
      }),
    ]);
    expect(await countPendingRecords()).toBe(1);
  });
});
