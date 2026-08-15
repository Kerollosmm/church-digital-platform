import { createClient } from "npm:@supabase/supabase-js@2";

export function makeServiceClient(url: string | undefined, key: string | undefined) {
  return createClient(url ?? "", key ?? "", { auth: { persistSession: false } });
}
export function makeAnonClient(url: string | undefined, key: string | undefined) {
  return createClient(url ?? "", key ?? "", { auth: { persistSession: false } });
}
