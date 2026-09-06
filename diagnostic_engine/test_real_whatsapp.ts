import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const WHATSAPP_TOKEN = Deno.env.get("WHATSAPP_TOKEN") ?? "";
const WHATSAPP_PHONE_ID = Deno.env.get("WHATSAPP_PHONE_ID") ?? "";
const TARGET_PHONE_FORMATTED = Deno.env.get("TARGET_PHONE_FORMATTED") ?? "";
const TARGET_PHONE_PLUS = Deno.env.get("TARGET_PHONE_PLUS") ?? "";

export async function runLiveWhatsAppTest(): Promise<void> {
  console.log("\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m  REAL-WORLD BOOKING & LIVE WHATSAPP DISPATCH TEST                  \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !Deno.env.get("RUN_LIVE_TESTS")) {
    console.log("\x1b[33m[Notice]\x1b[0m Live WhatsApp test requires RUN_LIVE_TESTS=true, SUPABASE_URL, and SUPABASE_ANON_KEY environment variables. Skipping live dispatch.");
    return;
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  // 1. Opt-in setup
  if (TARGET_PHONE_PLUS && TARGET_PHONE_FORMATTED) {
    console.log(`\x1b[36m[Step 1]\x1b[0m Registering WhatsApp opt-in for ${TARGET_PHONE_PLUS}...`);
    const { error: optinErr } = await supabase.from("whatsapp_optins").upsert([
      { phone: TARGET_PHONE_PLUS, source: "LIVE_TEST", consented_at: new Date().toISOString() },
      { phone: TARGET_PHONE_FORMATTED, source: "LIVE_TEST", consented_at: new Date().toISOString() }
    ]);
    if (optinErr) {
      console.log(`\x1b[33m[Opt-in Note]\x1b[0m ${optinErr.message}`);
    } else {
      console.log(`\x1b[32m[Step 1 OK]\x1b[0m Opt-in registered.`);
    }
  }

  // 2. Fetch available service slot
  console.log("\x1b[36m[Step 2]\x1b[0m Querying active church service slots...");
  const { data: slots, error: slotsErr } = await supabase
    .from("service_slots")
    .select("id, service_id, starts_at, capacity, price, status")
    .eq("status", "OPEN")
    .limit(1);

  if (slotsErr || !slots || slots.length === 0) {
    console.error("\x1b[31m[Error]\x1b[0m No open service slots found.");
    return;
  }
  const slot = slots[0];
  console.log(`\x1b[32m[Step 2 OK]\x1b[0m Found Slot ID: ${slot.id}, Price: ${slot.price} EGP, Starts: ${slot.starts_at}`);

  // 3. Enqueue Real Event in event_outbox
  console.log("\x1b[36m[Step 3]\x1b[0m Enqueueing real WhatsApp confirmation event in event_outbox...");
  const eventPayload = {
    phone: TARGET_PHONE_PLUS,
    template_name: "booking_confirmed",
    params: { param1: `حجز قداس رقم ${slot.id}` }
  };

  const { data: outboxEntry, error: outboxErr } = await supabase
    .from("event_outbox")
    .insert({
      handler_type: "WHATSAPP",
      payload: eventPayload,
      status: "PENDING",
      attempts: 0
    })
    .select()
    .single();

  if (outboxErr) {
    console.log(`\x1b[33m[Outbox Note]\x1b[0m ${outboxErr.message}`);
  } else {
    console.log(`\x1b[32m[Step 3 OK]\x1b[0m Outbox row created with ID #${outboxEntry?.id}`);
  }

  console.log("\n\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m         REAL-WORLD WHATSAPP TEST COMPLETE                          \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");
}

if (import.meta.main) {
  runLiveWhatsAppTest().catch(console.error);
}
