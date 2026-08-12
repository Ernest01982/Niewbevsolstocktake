import 'fake-indexeddb/auto';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  cacheProducts,
  countPendingRecords,
  enqueueCount,
  getLocalCount,
  hasLocalDuplicate,
  markCountsSyncing,
  recoverInterruptedCounts,
  resetOfflineDatabaseForTests,
  searchCachedProducts,
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
