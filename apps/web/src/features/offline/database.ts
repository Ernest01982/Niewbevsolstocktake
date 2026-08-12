import type {
  CachedProduct,
  CountQuantities,
  CountType,
} from '../counting/count';

const DATABASE_NAME = 'stock-take-offline-v1';
const DATABASE_VERSION = 2;
const PRODUCT_STORE = 'products';
const COUNT_STORE = 'counts';
const RECOGNITION_STORE = 'recognition-events';

export type LocalCountStatus = 'acknowledged' | 'failed' | 'queued' | 'syncing';

export interface LocalCountRecord extends CountQuantities {
  acknowledged_at?: string;
  attempts: number;
  company_id: string;
  count_id?: string;
  count_type: CountType;
  created_at: string;
  duration_ms: number | null;
  duplicate?: boolean;
  idempotency_key: string;
  last_error?: string;
  next_attempt_at: number;
  product_id: string;
  product_name: string;
  status: LocalCountStatus;
  stock_take_id: string;
  stock_taker_session_id: string;
  total_units: number;
  warehouse_id: string;
}

export type LocalRecognitionStatus =
  'acknowledged' | 'failed' | 'queued' | 'syncing';

export interface LocalRecognitionRecord {
  acknowledged_at?: string;
  attempts: number;
  candidates: { confidence: number; product_id: string }[];
  captured_at: string;
  company_id: string;
  idempotency_key: string;
  last_error?: string;
  model: string;
  next_attempt_at: number;
  provider: string;
  recognition_event_id?: string;
  selected_product_id: string;
  selection_method: 'MANUAL_SEARCH';
  status: LocalRecognitionStatus;
  stock_take_id: string;
  stock_taker_session_id: string;
  warehouse_id: string;
}

interface StoredProduct extends CachedProduct {
  normalized_search: string;
}

function requestResult<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () =>
      reject(request.error ?? new Error('IndexedDB request failed.'));
  });
}

function transactionComplete(transaction: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () =>
      reject(transaction.error ?? new Error('IndexedDB transaction failed.'));
    transaction.onabort = () =>
      reject(
        transaction.error ?? new Error('IndexedDB transaction was aborted.'),
      );
  });
}

async function openDatabase(): Promise<IDBDatabase> {
  const request = indexedDB.open(DATABASE_NAME, DATABASE_VERSION);
  request.onupgradeneeded = () => {
    const database = request.result;
    if (!database.objectStoreNames.contains(PRODUCT_STORE)) {
      const products = database.createObjectStore(PRODUCT_STORE, {
        keyPath: 'id',
      });
      products.createIndex('company_id', 'company_id');
    }
    if (!database.objectStoreNames.contains(COUNT_STORE)) {
      const counts = database.createObjectStore(COUNT_STORE, {
        keyPath: 'idempotency_key',
      });
      counts.createIndex('status', 'status');
      counts.createIndex('stock_take_id', 'stock_take_id');
    }
    if (!database.objectStoreNames.contains(RECOGNITION_STORE)) {
      const recognitionEvents = database.createObjectStore(RECOGNITION_STORE, {
        keyPath: 'idempotency_key',
      });
      recognitionEvents.createIndex('status', 'status');
    }
  };
  return requestResult(request);
}

export async function getCachedProductsByIds(
  companyId: string,
  productIds: string[],
): Promise<CachedProduct[]> {
  if (productIds.length === 0) return [];
  const wanted = new Set(productIds);
  const products = await searchCachedProducts(companyId, '', 10_000);
  const byId = new Map(products.map((product) => [product.id, product]));
  return productIds.flatMap((id) => {
    const product = byId.get(id);
    return product && wanted.has(id) ? [product] : [];
  });
}

export async function cacheProducts(products: CachedProduct[]): Promise<void> {
  const database = await openDatabase();
  const transaction = database.transaction(PRODUCT_STORE, 'readwrite');
  const store = transaction.objectStore(PRODUCT_STORE);
  for (const product of products) {
    const stored: StoredProduct = {
      ...product,
      normalized_search:
        `${product.product_code} ${product.name} ${product.barcode ?? ''}`.toLowerCase(),
    };
    store.put(stored);
  }
  await transactionComplete(transaction);
  database.close();
}

export async function searchCachedProducts(
  companyId: string,
  query: string,
  limit = 20,
): Promise<CachedProduct[]> {
  const database = await openDatabase();
  const transaction = database.transaction(PRODUCT_STORE, 'readonly');
  const stored = await requestResult(
    transaction
      .objectStore(PRODUCT_STORE)
      .index('company_id')
      .getAll(companyId),
  );
  await transactionComplete(transaction);
  database.close();
  const normalizedQuery = query.trim().toLowerCase();
  return (stored as StoredProduct[])
    .filter((product) =>
      normalizedQuery === ''
        ? true
        : product.normalized_search.includes(normalizedQuery),
    )
    .slice(0, limit)
    .map((product) => ({
      barcode: product.barcode,
      cases_per_layer: product.cases_per_layer,
      cases_per_pallet: product.cases_per_pallet,
      company_id: product.company_id,
      id: product.id,
      name: product.name,
      product_code: product.product_code,
      units_per_case: product.units_per_case,
      updated_at: product.updated_at,
    }));
}

export async function enqueueCount(
  record: Omit<LocalCountRecord, 'attempts' | 'next_attempt_at' | 'status'>,
): Promise<LocalCountRecord> {
  const database = await openDatabase();
  const transaction = database.transaction(COUNT_STORE, 'readwrite');
  const store = transaction.objectStore(COUNT_STORE);
  const existing = await requestResult<LocalCountRecord | undefined>(
    store.get(record.idempotency_key),
  );
  const queued: LocalCountRecord = existing ?? {
    ...record,
    attempts: 0,
    next_attempt_at: 0,
    status: 'queued',
  };
  if (!existing) store.add(queued);
  await transactionComplete(transaction);
  database.close();
  return queued;
}

export async function recoverInterruptedCounts(): Promise<number> {
  const database = await openDatabase();
  const transaction = database.transaction(COUNT_STORE, 'readwrite');
  const store = transaction.objectStore(COUNT_STORE);
  const records = (await requestResult(store.getAll())) as LocalCountRecord[];
  let recovered = 0;
  for (const record of records) {
    if (record.status === 'syncing') {
      store.put({ ...record, status: 'queued' });
      recovered += 1;
    }
  }
  await transactionComplete(transaction);
  database.close();
  return recovered;
}

export async function enqueueManualRecognition(
  record: Omit<
    LocalRecognitionRecord,
    'attempts' | 'next_attempt_at' | 'status'
  >,
): Promise<LocalRecognitionRecord> {
  const database = await openDatabase();
  const transaction = database.transaction(RECOGNITION_STORE, 'readwrite');
  const store = transaction.objectStore(RECOGNITION_STORE);
  const existing = await requestResult<LocalRecognitionRecord | undefined>(
    store.get(record.idempotency_key),
  );
  const queued: LocalRecognitionRecord = existing ?? {
    ...record,
    attempts: 0,
    next_attempt_at: 0,
    status: 'queued',
  };
  if (!existing) store.add(queued);
  await transactionComplete(transaction);
  database.close();
  return queued;
}

export async function recoverInterruptedRecognitions(): Promise<number> {
  const database = await openDatabase();
  const transaction = database.transaction(RECOGNITION_STORE, 'readwrite');
  const store = transaction.objectStore(RECOGNITION_STORE);
  const records = (await requestResult(
    store.getAll(),
  )) as LocalRecognitionRecord[];
  let recovered = 0;
  for (const record of records) {
    if (record.status === 'syncing') {
      store.put({ ...record, status: 'queued' });
      recovered += 1;
    }
  }
  await transactionComplete(transaction);
  database.close();
  return recovered;
}

export async function listSyncableRecognitions(
  now = Date.now(),
  limit = 50,
): Promise<LocalRecognitionRecord[]> {
  const database = await openDatabase();
  const transaction = database.transaction(RECOGNITION_STORE, 'readonly');
  const records = (await requestResult(
    transaction.objectStore(RECOGNITION_STORE).getAll(),
  )) as LocalRecognitionRecord[];
  await transactionComplete(transaction);
  database.close();
  return records
    .filter(
      (record) =>
        record.status === 'queued' ||
        (record.status === 'failed' && record.next_attempt_at <= now),
    )
    .sort((left, right) => left.captured_at.localeCompare(right.captured_at))
    .slice(0, limit);
}

async function updateRecognitions(
  keys: string[],
  update: (record: LocalRecognitionRecord) => LocalRecognitionRecord,
): Promise<void> {
  if (keys.length === 0) return;
  const database = await openDatabase();
  const transaction = database.transaction(RECOGNITION_STORE, 'readwrite');
  const store = transaction.objectStore(RECOGNITION_STORE);
  for (const key of keys) {
    const record = await requestResult<LocalRecognitionRecord | undefined>(
      store.get(key),
    );
    if (record) store.put(update(record));
  }
  await transactionComplete(transaction);
  database.close();
}

export async function markRecognitionsSyncing(keys: string[]): Promise<void> {
  await updateRecognitions(keys, (record) => ({
    ...record,
    status: 'syncing',
  }));
}

export async function acknowledgeRecognition(
  key: string,
  recognitionEventId: string,
): Promise<void> {
  await updateRecognitions([key], (record) => {
    const acknowledged: LocalRecognitionRecord = {
      ...record,
      acknowledged_at: new Date().toISOString(),
      recognition_event_id: recognitionEventId,
      status: 'acknowledged',
    };
    delete acknowledged.last_error;
    return acknowledged;
  });
}

export async function failRecognition(
  key: string,
  message: string,
  now = Date.now(),
): Promise<void> {
  await updateRecognitions([key], (record) => {
    const attempts = record.attempts + 1;
    return {
      ...record,
      attempts,
      last_error: message,
      next_attempt_at: now + retryDelayMs(attempts),
      status: 'failed',
    };
  });
}

export async function listSyncableCounts(
  now = Date.now(),
  limit = 50,
): Promise<LocalCountRecord[]> {
  const database = await openDatabase();
  const transaction = database.transaction(COUNT_STORE, 'readonly');
  const records = (await requestResult(
    transaction.objectStore(COUNT_STORE).getAll(),
  )) as LocalCountRecord[];
  await transactionComplete(transaction);
  database.close();
  return records
    .filter(
      (record) =>
        record.status === 'queued' ||
        (record.status === 'failed' && record.next_attempt_at <= now),
    )
    .sort((left, right) => left.created_at.localeCompare(right.created_at))
    .slice(0, limit);
}

async function updateCounts(
  keys: string[],
  update: (record: LocalCountRecord) => LocalCountRecord,
): Promise<void> {
  if (keys.length === 0) return;
  const database = await openDatabase();
  const transaction = database.transaction(COUNT_STORE, 'readwrite');
  const store = transaction.objectStore(COUNT_STORE);
  for (const key of keys) {
    const record = await requestResult<LocalCountRecord | undefined>(
      store.get(key),
    );
    if (record) store.put(update(record));
  }
  await transactionComplete(transaction);
  database.close();
}

export async function markCountsSyncing(keys: string[]): Promise<void> {
  await updateCounts(keys, (record) => ({ ...record, status: 'syncing' }));
}

export async function acknowledgeCount(
  key: string,
  acknowledgement: { count_id: string; duplicate: boolean },
): Promise<void> {
  await updateCounts([key], (record) => {
    const acknowledged: LocalCountRecord = {
      ...record,
      acknowledged_at: new Date().toISOString(),
      count_id: acknowledgement.count_id,
      duplicate: acknowledgement.duplicate,
      status: 'acknowledged',
    };
    delete acknowledged.last_error;
    return acknowledged;
  });
}

export function retryDelayMs(attempt: number): number {
  return Math.min(60_000, 1_000 * 2 ** Math.min(attempt, 6));
}

export async function failCount(
  key: string,
  message: string,
  now = Date.now(),
): Promise<void> {
  await updateCounts([key], (record) => {
    const attempts = record.attempts + 1;
    return {
      ...record,
      attempts,
      last_error: message,
      next_attempt_at: now + retryDelayMs(attempts),
      status: 'failed',
    };
  });
}

export async function countPendingRecords(): Promise<number> {
  const database = await openDatabase();
  const transaction = database.transaction(
    [COUNT_STORE, RECOGNITION_STORE],
    'readonly',
  );
  const countRecords = (await requestResult(
    transaction.objectStore(COUNT_STORE).getAll(),
  )) as LocalCountRecord[];
  const recognitionRecords = (await requestResult(
    transaction.objectStore(RECOGNITION_STORE).getAll(),
  )) as LocalRecognitionRecord[];
  await transactionComplete(transaction);
  database.close();
  return (
    countRecords.filter((record) => record.status !== 'acknowledged').length +
    recognitionRecords.filter((record) => record.status !== 'acknowledged')
      .length
  );
}

export async function hasLocalDuplicate(
  stockTakeId: string,
  productId: string,
  countType: CountType,
): Promise<boolean> {
  const database = await openDatabase();
  const transaction = database.transaction(COUNT_STORE, 'readonly');
  const records = (await requestResult(
    transaction
      .objectStore(COUNT_STORE)
      .index('stock_take_id')
      .getAll(stockTakeId),
  )) as LocalCountRecord[];
  await transactionComplete(transaction);
  database.close();
  return records.some(
    (record) =>
      record.product_id === productId && record.count_type === countType,
  );
}

export async function getLocalCount(
  key: string,
): Promise<LocalCountRecord | undefined> {
  const database = await openDatabase();
  const transaction = database.transaction(COUNT_STORE, 'readonly');
  const record = await requestResult<LocalCountRecord | undefined>(
    transaction.objectStore(COUNT_STORE).get(key),
  );
  await transactionComplete(transaction);
  database.close();
  return record;
}

export async function resetOfflineDatabaseForTests(): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const request = indexedDB.deleteDatabase(DATABASE_NAME);
    request.onsuccess = () => resolve();
    request.onerror = () =>
      reject(request.error ?? new Error('Could not reset IndexedDB.'));
    request.onblocked = () => reject(new Error('IndexedDB reset was blocked.'));
  });
}
