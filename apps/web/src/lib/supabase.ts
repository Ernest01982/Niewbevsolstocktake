import { createClient } from '@supabase/supabase-js';
import { parsePublicEnvironment } from './env';
import type { Database } from '../types/database.types';

const publicEnvironment = parsePublicEnvironment(import.meta.env);

export const supabase = createClient<Database>(
  publicEnvironment.supabaseUrl,
  publicEnvironment.supabasePublishableKey,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  },
);
