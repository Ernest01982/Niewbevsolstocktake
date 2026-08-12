import { supabase } from '../../lib/supabase';
import type { BatchSender, BatchSyncResult } from './sync';

export const sendCountBatchToSupabase: BatchSender = async (records) => {
  const { data, error } = await supabase.rpc('sync_counts_batch', {
    p_records: records,
  });
  if (error) throw new Error(error.message);
  return data as unknown as BatchSyncResult;
};
