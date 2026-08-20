import type { CachedProduct } from '../counting/count';
import { supabase } from '../../lib/supabase';
import {
  acknowledgeRecognition,
  failRecognition,
  getCachedProductsByIds,
  listSyncableRecognitions,
  markRecognitionsSyncing,
} from '../offline/database';

export type RecognitionTier = 'HIGH' | 'LOW' | 'MEDIUM' | 'NO_MATCH';

export interface RecognitionCandidate {
  confidence: number;
  product: CachedProduct;
}

export interface RecognitionResult {
  candidates: RecognitionCandidate[];
  confidence_tier: RecognitionTier;
  recognition_event_id: string;
}

interface RecognitionResponse {
  candidates?: { confidence: number; product_id: string }[];
  confidence_tier?: RecognitionTier;
  error?: { message?: string };
  recognition_event_id?: string;
  success?: boolean;
}

export async function recognizeProduct(
  companyId: string,
  image: Blob,
): Promise<RecognitionResult> {
  const body = new FormData();
  body.set('captured_at', new Date().toISOString());
  body.set('idempotency_key', crypto.randomUUID());
  body.set('image', image, 'capture.jpg');
  const { data, error } = await supabase.functions.invoke<RecognitionResponse>(
    'recognize-product',
    { body },
  );
  if (error || !data?.success || !data.recognition_event_id) {
    throw new Error(
      error?.message ??
        data?.error?.message ??
        'Recognition is unavailable. Use manual search.',
    );
  }
  const rawCandidates = data.candidates ?? [];
  const products = await getCachedProductsByIds(
    companyId,
    rawCandidates.map((candidate) => candidate.product_id),
  );
  const productsById = new Map(
    products.map((product) => [product.id, product]),
  );
  return {
    candidates: rawCandidates.flatMap((candidate) => {
      const product = productsById.get(candidate.product_id);
      return product ? [{ confidence: candidate.confidence, product }] : [];
    }),
    confidence_tier: data.confidence_tier ?? 'NO_MATCH',
    recognition_event_id: data.recognition_event_id,
  };
}

export async function confirmRecognition(
  recognitionEventId: string,
  productId: string,
  method: 'AUTO_PRESELECT' | 'CANDIDATE_CONFIRMATION' | 'MANUAL_SEARCH',
): Promise<void> {
  const { data, error } = await supabase.rpc('confirm_recognition_selection', {
    p_product_id: productId,
    p_recognition_event_id: recognitionEventId,
    p_selection_method: method,
  });
  if (error || !(data as { success?: boolean })?.success) {
    throw new Error(
      error?.message ?? 'The product confirmation was not saved.',
    );
  }
}

export async function syncPendingRecognitions(now = Date.now()): Promise<void> {
  const records = await listSyncableRecognitions(now);
  if (records.length === 0) return;
  const keys = records.map((record) => record.idempotency_key);
  await markRecognitionsSyncing(keys);
  try {
    const { data, error } = await supabase.rpc(
      'sync_recognition_events_batch',
      {
        p_records: records.map((record) => ({
          candidates: record.candidates,
          captured_at: record.captured_at,
          company_id: record.company_id,
          idempotency_key: record.idempotency_key,
          model: record.model,
          provider: record.provider,
          selected_product_id: record.selected_product_id,
          selection_method: record.selection_method,
          stock_take_id: record.stock_take_id,
          stock_taker_session_id: record.stock_taker_session_id,
          warehouse_id: record.warehouse_id,
        })),
      },
    );
    if (error) throw error;
    const results = (
      data as {
        results?: {
          acknowledged?: boolean;
          error?: { message?: string };
          idempotency_key?: string;
          recognition_event_id?: string;
        }[];
      }
    )?.results;
    const byKey = new Map(
      (results ?? []).map((result) => [result.idempotency_key, result]),
    );
    await Promise.all(
      records.map((record) => {
        const result = byKey.get(record.idempotency_key);
        return result?.acknowledged && result.recognition_event_id
          ? acknowledgeRecognition(
              record.idempotency_key,
              result.recognition_event_id,
            )
          : failRecognition(
              record.idempotency_key,
              result?.error?.message ??
                'The server did not acknowledge this recognition event.',
              now,
            );
      }),
    );
  } catch (error) {
    const message =
      error instanceof Error ? error.message : 'Recognition sync failed.';
    await Promise.all(keys.map((key) => failRecognition(key, message, now)));
  }
}
