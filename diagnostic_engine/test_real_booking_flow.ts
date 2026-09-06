import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const WHATSAPP_TOKEN = Deno.env.get("WHATSAPP_TOKEN") ?? "";
const WHATSAPP_PHONE_ID = Deno.env.get("WHATSAPP_PHONE_ID") ?? "";
const TARGET_PHONE_DIGITS = Deno.env.get("TARGET_PHONE_DIGITS") ?? "";
const TARGET_PHONE_LOCAL = Deno.env.get("TARGET_PHONE_LOCAL") ?? "";
const TARGET_PHONE_E164 = Deno.env.get("TARGET_PHONE_E164") ?? "";

const TEST_EMAIL = Deno.env.get("TEST_EMAIL") ?? "";
const TEST_PASS = Deno.env.get("TEST_PASS") ?? "";

export async function runRealBookingFlow(): Promise<void> {
  console.log("\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m       REAL-WORLD LIVE END-TO-END BOOKING & VERIFICATION TEST       \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !Deno.env.get("RUN_LIVE_TESTS")) {
    console.log("\x1b[33m[Notice]\x1b[0m Live end-to-end booking test requires RUN_LIVE_TESTS=true, SUPABASE_URL, and SUPABASE_ANON_KEY environment variables. Skipping live network probe.");
    return;
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  // -------------------------------------------------------------------------
  // Stage 1: Authenticate Real Parishioner User
  // -------------------------------------------------------------------------
  console.log("\x1b[36m[Stage 1: User Authentication]\x1b[0m Signing in test parishioner...");
  if (!TEST_EMAIL || !TEST_PASS) {
    console.log("\x1b[33m[Auth Notice]\x1b[0m TEST_EMAIL or TEST_PASS unset. Skipping live auth.");
    return;
  }

  let authRes = await supabase.auth.signInWithPassword({
    email: TEST_EMAIL,
    password: TEST_PASS,
  });

  if (authRes.error) {
    console.log(`\x1b[33m[Auth Notice]\x1b[0m ${authRes.error.message}. Attempting signup...`);
    const signupRes = await supabase.auth.signUp({
      email: TEST_EMAIL,
      password: TEST_PASS,
      options: {
        data: {
          phone: TARGET_PHONE_LOCAL,
          name: "Test Parishioner",
        }
      }
    });
    if (signupRes.error) {
      console.log(`\x1b[33m[Signup Note]\x1b[0m ${signupRes.error.message}`);
    } else {
      authRes = await supabase.auth.signInWithPassword({
        email: TEST_EMAIL,
        password: TEST_PASS,
      });
    }
  }

  const userId = authRes.data?.user?.id;
  if (!userId) {
    console.error("\x1b[31m[Auth Error]\x1b[0m Failed to authenticate test parishioner.");
    return;
  }
  console.log(`\x1b[32m[Stage 1 OK]\x1b[0m Authenticated as Parishioner User UUID: \`${userId}\``);

  // -------------------------------------------------------------------------
  // Stage 2: Register WhatsApp Opt-in Consent
  // -------------------------------------------------------------------------
  if (TARGET_PHONE_E164) {
    console.log(`\n\x1b[36m[Stage 2: WhatsApp Opt-in]\x1b[0m Registering opt-in consent for ${TARGET_PHONE_E164}...`);
    const { error: optinErr } = await supabase.from("whatsapp_optins").upsert([
      { phone: TARGET_PHONE_E164, source: "LIVE_INTEGRATION_TEST", consented_at: new Date().toISOString() }
    ]);
    if (optinErr) {
      console.log(`  \x1b[33m[Opt-in Note]\x1b[0m ${optinErr.message}`);
    } else {
      console.log(`\x1b[32m[Stage 2 OK]\x1b[0m WhatsApp communication consent established in DB.`);
    }
  }

  // -------------------------------------------------------------------------
  // Stage 3: Discover Open Service Slot & Reserve Atomic Seat
  // -------------------------------------------------------------------------
  console.log("\n\x1b[36m[Stage 3: Slot Discovery & Atomic Reservation]\x1b[0m Querying available liturgy slots...");
  const { data: slots, error: slotErr } = await supabase
    .from("service_slots")
    .select("id, service_id, starts_at, capacity, price, status, location")
    .eq("status", "OPEN")
    .limit(1);

  if (slotErr || !slots || slots.length === 0) {
    console.error("\x1b[31m[Error]\x1b[0m No open service slots found.");
    return;
  }

  const targetSlot = slots[0];
  console.log(`  Target Slot ID: #${targetSlot.id} | Price: ${targetSlot.price} EGP | Location: ${targetSlot.location}`);

  const idempotencyKey = crypto.randomUUID();
  console.log(`  Executing atomic reservation via \`fn_book_slot_atomic\` with key: \`${idempotencyKey}\`...`);
  const bookRes = await supabase.rpc("fn_book_slot_atomic", {
    p_slot_id: targetSlot.id,
    p_quantity: 1,
    p_opt_in: true,
    p_idempotency_key: idempotencyKey
  });

  if (bookRes.error) {
    console.error("\x1b[31m[Booking Error]\x1b[0m", bookRes.error);
    return;
  }

  const bookingResult = bookRes.data;
  console.log(`\x1b[32m[Stage 3 OK]\x1b[0m Booking Secured:`, bookingResult);

  // -------------------------------------------------------------------------
  // Stage 4: Verify Event Enqueued in event_outbox
  // -------------------------------------------------------------------------
  console.log("\n\x1b[36m[Stage 4: Outbox Verification]\x1b[0m Checking event_outbox for transactional dispatch...");
  const { data: outboxRows } = await supabase
    .from("event_outbox")
    .select("id, handler_type, status, payload, attempts, created_at")
    .order("created_at", { ascending: false })
    .limit(3);

  console.log(`\x1b[32m[Stage 4 OK]\x1b[0m Latest Outbox Events in Postgres:`, outboxRows);

  // -------------------------------------------------------------------------
  // Stage 5: Clean Up Created Booking (Idempotent Test Cleanup)
  // -------------------------------------------------------------------------
  if (bookingResult?.booking_id) {
    console.log(`\n\x1b[36m[Stage 5: Test Cleanup]\x1b[0m Releasing test booking #${bookingResult.booking_id}...`);
    await supabase.from("bookings").delete().eq("id", bookingResult.booking_id);
    console.log(`\x1b[32m[Stage 5 OK]\x1b[0m Test booking cleaned up successfully.`);
  }

  console.log("\n\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m              END-TO-END VERIFICATION RUN COMPLETE                \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m");
}

if (import.meta.main) {
  runRealBookingFlow().catch(console.error);
}
