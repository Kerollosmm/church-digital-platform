#!/usr/bin/env node

/**
 * Staging Smoke Test Script
 * Zero external dependencies (ESM, global fetch).
 *
 * Usage:
 *   node scripts/staging-smoke.mjs <url> <service-key> <anon-key>
 *   node scripts/staging-smoke.mjs --url=<url> --service-key=<key> --anon-key=<key>
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... SUPABASE_ANON_KEY=... node scripts/staging-smoke.mjs
 */

const args = process.argv.slice(2);

let url = process.env.SUPABASE_URL;
let serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
let anonKey = process.env.SUPABASE_ANON_KEY;

const positionalArgs = [];

for (let i = 0; i < args.length; i++) {
  const arg = args[i];
  if (arg.startsWith('--url=')) {
    url = arg.slice('--url='.length);
  } else if (arg === '--url') {
    url = args[++i];
  } else if (arg.startsWith('--service-key=')) {
    serviceKey = arg.slice('--service-key='.length);
  } else if (arg === '--service-key') {
    serviceKey = args[++i];
  } else if (arg.startsWith('--anon-key=')) {
    anonKey = arg.slice('--anon-key='.length);
  } else if (arg === '--anon-key') {
    anonKey = args[++i];
  } else if (!arg.startsWith('--')) {
    positionalArgs.push(arg);
  }
}

if (!url && positionalArgs[0]) url = positionalArgs[0];
if (!serviceKey && positionalArgs[1]) serviceKey = positionalArgs[1];
if (!anonKey && positionalArgs[2]) anonKey = positionalArgs[2];

if (!url || !serviceKey || !anonKey) {
  console.error('Error: Missing required configuration (url, service-key, anon-key).');
  console.error('Usage:');
  console.error('  node scripts/staging-smoke.mjs <url> <service-key> <anon-key>');
  console.error('  node scripts/staging-smoke.mjs --url=<url> --service-key=<key> --anon-key=<key>');
  console.error('  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... SUPABASE_ANON_KEY=... node scripts/staging-smoke.mjs');
  process.exit(1);
}

url = url.replace(/\/+$/, '');

function getHeaders(key, contentType = null) {
  const headers = {
    apikey: key,
    Authorization: `Bearer ${key}`
  };
  if (contentType) {
    headers['Content-Type'] = contentType;
  }
  return headers;
}

function snippet(text, maxLen = 140) {
  if (typeof text !== 'string') {
    try {
      text = JSON.stringify(text);
    } catch {
      text = String(text);
    }
  }
  const clean = text.replace(/\s+/g, ' ').trim();
  if (clean.length <= maxLen) return clean;
  return clean.slice(0, maxLen) + '...';
}

const results = [];

async function runCheck(id, name, fn) {
  process.stdout.write(`[CHECK ${id}/7] ${name}: `);
  try {
    const { pass, detail } = await fn();
    if (pass) {
      console.log(`\x1b[32mPASS\x1b[0m -> ${detail}`);
      results.push({ id, name, pass: true, detail });
    } else {
      console.log(`\x1b[31mFAIL\x1b[0m -> ${detail}`);
      results.push({ id, name, pass: false, detail });
    }
  } catch (err) {
    const detail = `Exception: ${err.message}`;
    console.log(`\x1b[31mFAIL\x1b[0m -> ${detail}`);
    results.push({ id, name, pass: false, detail });
  }
}

console.log(`======================================================`);
console.log(`Starting Supabase Staging Smoke Test`);
console.log(`Target URL: ${url}`);
console.log(`======================================================\n`);

// Check 1: REST reachable
await runCheck(1, 'REST reachable', async () => {
  const res = await fetch(`${url}/rest/v1/`, {
    headers: getHeaders(serviceKey || anonKey)
  });
  const text = await res.text();
  const pass = res.status >= 200 && res.status <= 499;
  return {
    pass,
    detail: `HTTP ${res.status} | Snippet: ${snippet(text)}`
  };
});

// Check 2: Schema sanity
await runCheck(2, 'Schema sanity', async () => {
  const tables = ['event_bookings', 'event_types', 'payment_proofs', 'payout_channels'];
  for (const table of tables) {
    const res = await fetch(`${url}/rest/v1/${table}?limit=0`, {
      headers: getHeaders(serviceKey)
    });
    if (res.status !== 200) {
      const text = await res.text();
      return {
        pass: false,
        detail: `Table ${table} query returned HTTP ${res.status} (expected 200) | ${snippet(text)}`
      };
    }
  }

  // offline_sync_log has tenant_id column
  const syncLogRes = await fetch(`${url}/rest/v1/offline_sync_log?select=tenant_id&limit=0`, {
    headers: getHeaders(serviceKey)
  });
  if (syncLogRes.status !== 200) {
    const text = await syncLogRes.text();
    return {
      pass: false,
      detail: `offline_sync_log?select=tenant_id returned HTTP ${syncLogRes.status} (expected 200) | ${snippet(text)}`
    };
  }

  // audit_log has entity_uuid column
  const auditRes = await fetch(`${url}/rest/v1/audit_log?select=entity_uuid&limit=0`, {
    headers: getHeaders(serviceKey)
  });
  if (auditRes.status !== 200) {
    const text = await auditRes.text();
    return {
      pass: false,
      detail: `audit_log?select=entity_uuid returned HTTP ${auditRes.status} (expected 200) | ${snippet(text)}`
    };
  }

  // v_services view present (mobile booking home screen reads it)
  const vServicesRes = await fetch(`${url}/rest/v1/v_services?limit=0`, {
    headers: getHeaders(serviceKey)
  });
  if (vServicesRes.status !== 200) {
    const text = await vServicesRes.text();
    return {
      pass: false,
      detail: `v_services query returned HTTP ${vServicesRes.status} (expected 200) | ${snippet(text)}`
    };
  }

  // sunday_school_classes does NOT exist
  const sundayRes = await fetch(`${url}/rest/v1/sunday_school_classes?limit=0`, {
    headers: getHeaders(serviceKey)
  });
  if (sundayRes.status === 200) {
    return {
      pass: false,
      detail: `sunday_school_classes returned HTTP 200 (expected 404 or non-200)`
    };
  }

  return {
    pass: true,
    detail: `Tables present, columns verified, v_services present, sunday_school_classes absent (HTTP ${sundayRes.status})`
  };
});

// Check 3: Money sanity
await runCheck(3, 'Money sanity (service_slots.price integer piastres)', async () => {
  const res = await fetch(`${url}/rest/v1/service_slots?select=id,price&price=eq.2000&limit=1`, {
    headers: getHeaders(serviceKey)
  });
  const text = await res.text();
  if (res.status !== 200) {
    return {
      pass: false,
      detail: `Query returned HTTP ${res.status} | Snippet: ${snippet(text)}`
    };
  }
  let data;
  try {
    data = JSON.parse(text);
  } catch (err) {
    return {
      pass: false,
      detail: `Failed to parse JSON response: ${err.message}`
    };
  }
  if (!Array.isArray(data) || data.length === 0) {
    return {
      pass: false,
      detail: `Expected at least 1 row with price=2000, got: ${snippet(text)}`
    };
  }
  const row = data[0];
  const isInteger = Number.isInteger(row.price);
  const is2000 = row.price === 2000;
  return {
    pass: isInteger && is2000,
    detail: `HTTP 200 | price=${row.price} (isInteger=${isInteger}, is2000=${is2000}) | row=${snippet(text)}`
  };
});

// Check 4: RLS sanity
await runCheck(4, 'RLS sanity (anon GET /rest/v1/bookings)', async () => {
  const res = await fetch(`${url}/rest/v1/bookings`, {
    headers: getHeaders(anonKey)
  });
  const text = await res.text();
  if (res.status === 401 || res.status === 403) {
    return {
      pass: true,
      detail: `HTTP ${res.status} (Access Denied as expected) | Snippet: ${snippet(text)}`
    };
  }
  if (res.status === 200) {
    try {
      const data = JSON.parse(text);
      if (Array.isArray(data) && data.length === 0) {
        return {
          pass: true,
          detail: `HTTP 200 with empty array [] (RLS filtered all rows) | Snippet: ${snippet(text)}`
        };
      }
      return {
        pass: false,
        detail: `HTTP 200 returned non-empty rows for anon | Snippet: ${snippet(text)}`
      };
    } catch (err) {
      return {
        pass: false,
        detail: `HTTP 200 returned invalid JSON | Snippet: ${snippet(text)}`
      };
    }
  }
  return {
    pass: false,
    detail: `Unexpected status HTTP ${res.status} (expected [] or 401/403) | Snippet: ${snippet(text)}`
  };
});

// Check 5: RPC reachability & structured error contract
await runCheck(5, 'RPC reachability & structured error contract', async () => {
  let certPassed = false;
  let certDetail = '';
  try {
    const resCert = await fetch(`${url}/rest/v1/rpc/verify_certificate`, {
      method: 'POST',
      headers: getHeaders(anonKey, 'application/json'),
      body: JSON.stringify({ p_token: '' })
    });
    const textCert = await resCert.text();
    if (resCert.status === 200) {
      const json = JSON.parse(textCert);
      if (json && 'error' in json && 'message_ar' in json) {
        certPassed = true;
        certDetail = `verify_certificate HTTP 200 (error=${json.error}, message_ar=${json.message_ar})`;
      } else {
        certDetail = `verify_certificate HTTP 200 missing error/message_ar keys: ${snippet(textCert)}`;
      }
    } else {
      certDetail = `verify_certificate HTTP ${resCert.status}: ${snippet(textCert)}`;
    }
  } catch (err) {
    certDetail = `verify_certificate error: ${err.message}`;
  }

  let slotsPassed = false;
  let slotsDetail = '';
  try {
    const resSlots = await fetch(`${url}/rest/v1/rpc/available_slots`, {
      method: 'POST',
      headers: getHeaders(anonKey, 'application/json'),
      body: JSON.stringify({ bogus: 1 })
    });
    const textSlots = await resSlots.text();
    if (resSlots.status >= 400 && resSlots.status < 500) {
      try {
        const json = JSON.parse(textSlots);
        if (typeof json === 'object' && json !== null) {
          slotsPassed = true;
          slotsDetail = `available_slots HTTP ${resSlots.status} JSON: ${snippet(textSlots)}`;
        } else {
          slotsDetail = `available_slots HTTP ${resSlots.status} non-object JSON: ${snippet(textSlots)}`;
        }
      } catch {
        slotsDetail = `available_slots HTTP ${resSlots.status} invalid JSON: ${snippet(textSlots)}`;
      }
    } else {
      slotsDetail = `available_slots HTTP ${resSlots.status}: ${snippet(textSlots)}`;
    }
  } catch (err) {
    slotsDetail = `available_slots error: ${err.message}`;
  }

  const pass = certPassed || slotsPassed;
  return {
    pass,
    detail: `[verify_certificate: ${certPassed ? 'OK' : 'FAIL'} (${certDetail})] | [available_slots: ${slotsPassed ? 'OK' : 'FAIL'} (${slotsDetail})]`
  };
});

// Check 6: Edge function reachability
await runCheck(6, 'Edge function reachability (analytics-export 401)', async () => {
  const res = await fetch(`${url}/functions/v1/analytics-export`, {
    method: 'GET',
    headers: {
      apikey: anonKey,
      Authorization: 'Bearer invalid-token'
    }
  });
  const text = await res.text();
  let isJson = false;
  try {
    JSON.parse(text);
    isJson = true;
  } catch {}

  const pass = res.status === 401 && isJson;
  return {
    pass,
    detail: `HTTP ${res.status} (isJson=${isJson}) | Snippet: ${snippet(text)}`
  };
});

// Check 7: Auth service reachable
await runCheck(7, 'Auth service reachable (token grant_type=password 400/401)', async () => {
  const res = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: {
      apikey: anonKey,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      email: 'bogus@example.com',
      password: 'boguspassword123'
    })
  });
  const text = await res.text();
  let isJson = false;
  try {
    JSON.parse(text);
    isJson = true;
  } catch {}

  const pass = (res.status === 400 || res.status === 401) && isJson;
  return {
    pass,
    detail: `HTTP ${res.status} (isJson=${isJson}) | Snippet: ${snippet(text)}`
  };
});

console.log(`\n======================================================`);
const passedCount = results.filter(r => r.pass).length;
const failedCount = results.filter(r => !r.pass).length;
console.log(`TOTAL CHECKS: ${results.length} | PASSED: ${passedCount} | FAILED: ${failedCount}`);
console.log(`======================================================\n`);

if (failedCount > 0) {
  console.error(`\x1b[31mSmoke test failed: ${failedCount} check(s) did not pass.\x1b[0m`);
  process.exit(1);
} else {
  console.log(`\x1b[32mAll smoke checks passed successfully!\x1b[0m`);
  process.exit(0);
}
