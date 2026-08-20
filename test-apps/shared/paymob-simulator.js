/**
 * ============================================================================
 * Church Digital Platform — Paymob Webhook Simulator & HMAC-SHA512 Calculator
 * ============================================================================
 */

(function () {
  'use strict';

  const DEFAULT_HMAC_KEY = '38A2FEAE52EECCFC41F9982EDCCBF43F';
  const DEFAULT_SUPABASE_URL = 'http://127.0.0.1:54321';

  /**
   * Concatenate 21 transaction fields according to Paymob specification
   */
  function hmacFields(txn) {
    if (!txn) return '';
    const o = txn.order || {};
    const s = txn.source_data || {};
    const str = (v) => (v == null ? '' : String(v));

    const fieldValues = [
      txn.amount_cents,
      txn.created_at,
      txn.currency,
      txn.error_occured,
      txn.has_parent_transaction,
      txn.id,
      txn.integration_id,
      txn.is_3d_secure,
      txn.is_auth,
      txn.is_capture,
      txn.is_refunded,
      txn.is_standalone_payment,
      txn.is_voided,
      o.id,
      txn.owner,
      txn.pending,
      s.pan,
      s.sub_type,
      s.type,
      txn.success
    ];

    return fieldValues.map(str).join('');
  }

  /**
   * Compute HMAC-SHA512 hex string
   */
  async function computeHmacSha512(secret, payload) {
    // Node.js environment
    if (typeof process !== 'undefined' && process.versions && process.versions.node) {
      try {
        const crypto = await import('crypto');
        return crypto.createHmac('sha512', secret).update(payload).digest('hex');
      } catch (e) {
        // Fall back to WebCrypto
      }
    }

    // Browser WebCrypto environment
    const cryptoObj = (typeof window !== 'undefined' && window.crypto) ? window.crypto : (typeof crypto !== 'undefined' ? crypto : null);
    if (!cryptoObj || !cryptoObj.subtle) {
      throw new Error('WebCrypto API (crypto.subtle) is required to compute HMAC-SHA512.');
    }

    const encoder = new TextEncoder();
    const key = await cryptoObj.subtle.importKey(
      'raw',
      encoder.encode(secret),
      { name: 'HMAC', hash: 'SHA-512' },
      false,
      ['sign']
    );

    const signature = await cryptoObj.subtle.sign('HMAC', key, encoder.encode(payload));
    return Array.from(new Uint8Array(signature))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }

  /**
   * Generate canonical Paymob webhook payload structure
   */
  async function buildWebhookPayload(options = {}) {
    const transactionId = options.transactionId || Math.floor(1000000 + Math.random() * 9000000);
    const orderId = options.orderId || Math.floor(100000 + Math.random() * 900000);
    const merchantOrderId = options.merchantOrderId ? String(options.merchantOrderId) : String(orderId);
    const amountCents = options.amountCents != null ? Number(options.amountCents) : 5000;
    const isSuccess = options.success !== false;
    const createdAt = options.createdAt || new Date().toISOString();
    const currency = options.currency || 'EGP';
    const integrationId = options.integrationId || 428019;
    const secretKey = options.hmacKey || DEFAULT_HMAC_KEY;

    const txnObj = {
      id: transactionId,
      pending: false,
      amount_cents: amountCents,
      success: isSuccess,
      is_auth: false,
      is_capture: false,
      is_standalone_payment: true,
      is_voided: false,
      is_refunded: false,
      is_3d_secure: true,
      integration_id: integrationId,
      owner: 10452,
      currency: currency,
      error_occured: false,
      has_parent_transaction: false,
      created_at: createdAt,
      order: {
        id: orderId,
        created_at: createdAt,
        delivery_needed: 'false',
        merchant_order_id: merchantOrderId,
        collector: null,
        amount_cents: amountCents,
        shipping_data: null,
        currency: currency,
        is_payment_locked: 'false',
        is_return: 'false',
        is_cancel: 'false',
        is_returned: 'false',
        is_canceled: 'false',
        merchant_staff_tag: null,
        updated_at: createdAt,
        items: []
      },
      source_data: {
        pan: options.pan || '2345',
        sub_type: options.subType || 'MasterCard',
        type: options.type || 'card',
        tenure: null
      },
      data: {
        message: isSuccess ? 'Approved' : 'Declined'
      }
    };

    const concatenated = hmacFields(txnObj);
    const hmac = await computeHmacSha512(secretKey, concatenated);

    return {
      type: 'TRANSACTION',
      obj: txnObj,
      hmac,
      concatenated
    };
  }

  /**
   * Send simulated Paymob webhook to local Edge Function
   */
  async function sendWebhook(payload, hmac, customSupabaseUrl) {
    const baseUrl = customSupabaseUrl || DEFAULT_SUPABASE_URL;
    const endpoint = `${baseUrl}/functions/v1/paymob-webhook?hmac=${encodeURIComponent(hmac)}`;

    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      let json = null;
      try {
        json = await response.json();
      } catch (e) {
        json = { raw: await response.text() };
      }

      return {
        ok: response.ok,
        status: response.status,
        data: json,
        endpoint
      };
    } catch (err) {
      return {
        ok: false,
        status: 0,
        error: err.message || 'Network request failed',
        endpoint
      };
    }
  }

  const PaymobSimulator = {
    DEFAULT_HMAC_KEY,
    DEFAULT_SUPABASE_URL,
    hmacFields,
    computeHmacSha512,
    buildWebhookPayload,
    sendWebhook
  };

  if (typeof window !== 'undefined') {
    window.PaymobSimulator = PaymobSimulator;
  }
  if (typeof globalThis !== 'undefined') {
    globalThis.PaymobSimulator = PaymobSimulator;
  }
})();
