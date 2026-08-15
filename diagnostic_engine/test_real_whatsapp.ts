import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";

const SUPABASE_URL = "https://qksgphryemrdrkwaqnxp.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFrc2dwaHJ5ZW1yZHJrd2FxbnhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5NTA2MjgsImV4cCI6MjEwMTUyNjYyOH0.ebxE042EdeYMHbkJnst8aq5K6RtlYgUXEpoeHuYNHvA";

const WHATSAPP_TOKEN = "EAAOci7sowW0BSKPjP74DDP7HMT2BZCZBZAZBcwS9BpehKTUAVjy6ei0QspvMIUDXPkHfzeHGOC9G2gCocreEmkHgYFxG7dltr5SjiD9Cq1ltS06yiZBCrzVZCli5CMA7dRIZAGxxWShaA5Ac4dMOSIXW2X06Ic67KoiQyenT08yJWnX8UIXPnxlHreHVMpUYB8jp34ZAHcnDvBvs0Fi2gzH1ZBdZCzZC2EKZBBFkQZAd2lI2lzUdrMRoZAJ8uBvzxwQUZC14leipEu0ZCf3C7nBT1lvF0E7O";
const WHATSAPP_PHONE_ID = "1275518218977849";
const TARGET_PHONE_FORMATTED = "201274173806";
const TARGET_PHONE_PLUS = "+201274173806";

async function runLiveWhatsAppTest() {
  console.log("\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m  REAL-WORLD BOOKING & LIVE WHATSAPP DISPATCH TEST                  \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  // 1. Opt-in setup
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
    console.log(`\x1b[32m[Step 3 OK]\x1b[0m Event enqueued with Outbox ID: ${outboxEntry.id}`);
  }

  // 4. Direct Meta Graph API Dispatch
  console.log(`\x1b[36m[Step 4]\x1b[0m Sending live WhatsApp message to ${TARGET_PHONE_FORMATTED} via Meta Cloud API...`);
  
  const metaUrl = `https://graph.facebook.com/v20.0/${WHATSAPP_PHONE_ID}/messages`;
  const metaPayload = {
    messaging_product: "whatsapp",
    to: TARGET_PHONE_FORMATTED,
    type: "template",
    template: {
      name: "booking_confirmed",
      language: { code: "ar" },
      components: [
        {
          type: "body",
          parameters: [
            { type: "text", text: `حجز قداس رقم ${slot.id}` }
          ]
        }
      ]
    }
  };

  const metaRes = await fetch(metaUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${WHATSAPP_TOKEN}`
    },
    body: JSON.stringify(metaPayload)
  });

  const metaJson = await metaRes.json();

  if (metaRes.ok) {
    console.log("\x1b[32m[SUCCESS - WhatsApp Message Dispatched!]\x1b[0m");
    console.log("Meta API Response:", JSON.stringify(metaJson, null, 2));
    if (outboxEntry?.id) {
      await supabase.from("event_outbox").update({ status: "SENT" }).eq("id", outboxEntry.id);
    }
  } else {
    // Check available message templates on WABA
    console.log("\n\x1b[36m[Checking WABA Message Templates]\x1b[0m");
    const tplRes = await fetch(`https://graph.facebook.com/v20.0/1028518760161166/message_templates`, {
      headers: { "Authorization": `Bearer ${WHATSAPP_TOKEN}` }
    });
    const tplJson = await tplRes.json();
    console.log("Registered Templates:", JSON.stringify(tplJson, null, 2));

    // Test sending default hello_world template
    console.log("\n\x1b[36m[Sending hello_world test template to verify device delivery]\x1b[0m");
    const hwRes = await fetch(metaUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${WHATSAPP_TOKEN}`
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: TARGET_PHONE_FORMATTED,
        type: "template",
        template: {
          name: "hello_world",
          language: { code: "en_US" }
        }
      })
    });
    console.log("hello_world Dispatch Status:", hwRes.status, await hwRes.json());
  }
}

runLiveWhatsAppTest().catch(console.error);
