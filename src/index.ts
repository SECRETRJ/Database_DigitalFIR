import { createClient, SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './types/database.types.js';

export type { Database } from './types/database.types.js';

export interface SupabaseConfig {
  supabaseUrl: string;
  supabaseAnonKey: string;
}

/**
 * Creates a strongly-typed Supabase client for the Secure Digital Document Management System.
 */
export function createDocumentManagementClient(
  supabaseUrl: string,
  supabaseAnonKey: string
): SupabaseClient<Database> {
  return createClient<Database>(supabaseUrl, supabaseAnonKey, {
    auth: {
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  });
}
