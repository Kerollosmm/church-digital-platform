/**
 * ============================================================================
 * Church Digital Platform — Supabase JavaScript Client & Auth Helper
 * ============================================================================
 */

(function () {
  'use strict';

  const SUPABASE_CONFIG = {
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
    serviceRoleKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU'
  };

  // Error catalog matching public.error_messages and backend contracts
  const ARABIC_ERROR_CATALOG = {
    'UNAUTHORIZED': 'انتهت الجلسة، من فضلك سجل الدخول مرة أخرى.',
    'FORBIDDEN': 'ليس لديك صلاحية للوصول إلى هذه الخدمة.',
    'BAD_REQUEST': 'البيانات المرسلة غير صحيحة، يرجى التأكد والمحاولة مرة أخرى.',
    'UPSTREAM_ERROR': 'تعذر الاتصال بالخدمة الخارجية، يرجى المحاولة لاحقاً.',
    'INTERNAL': 'حدث خطأ في النظام، يرجى المحاولة لاحقاً.',
    'FALLBACK': 'حدث خطأ غير متوقع، حاول مرة أخرى.',
    'SLOT_FULL': 'عذراً، هذا الموعد ممتلئ بالكامل.',
    'TOO_MANY_ACTIVE_BOOKINGS': 'لديك الحد الأقصى من الحجوزات النشطة (3 حجوزات).',
    'ALREADY_BOOKED_SLOT': 'لقد قمت بحجز هذا الموعد بالفعل مسبقاً.',
    'SLOT_UNAVAILABLE': 'هذا الموعد غير متاح حالياً للحجز.',
    'SLOT_TAKEN': 'الموعد محجوز بالكامل من قبل شخص آخر.',
    'USER_NOT_FOUND': 'المستخدم غير مسجل في قاعدة البيانات بهذا الرقم.',
    'ALT_TEXT_REQUIRED': 'يجب إدخال النص البديل للصورة لضمان إمكانية الوصول.',
    'COMPLAINT_KEY_MISSING': 'مفتاح تشفير الشكاوى غير متوفر في الخزينة.',
    'COMPLAINTS_KEY_MISSING': 'مفتاح تشفير الشكاوى غير متوفر في الخزينة.',
    'INVALID_PIN': 'رمز PIN غير صحيح، يرجى المحاولة مرة أخرى.',
    'PIN_LOCKED': 'تم قفل رمز PIN مؤقتاً لمدة 15 دقيقة لتجاوز عدد المحاولات المسموح بها.',
    'PIN_ALREADY_SET': 'تم تعيين رمز PIN بالفعل لهذا الحساب.',
    'PHONE_REQUIRED': 'رقم الهاتف مطلوب لإتمام الحجز.',
    'INVALID_CREDENTIALS': 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
    'Invalid login credentials': 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
    'User already registered': 'هذا البريد الإلكتروني مسجل بالفعل مسبقاً.',
    'Email not confirmed': 'يرجى تأكيد البريد الإلكتروني أولاً.',
    'PGRST116': 'لم يتم العثور على السجل المطلوب.',
    '23505': 'هذا السجل مكرر ومسجل بالفعل في المنظومة.',
    '23503': 'يتعذر إتمام العملية لوجود ارتباطات ببيانات أخرى.'
  };

  let clientInstance = null;
  let adminClientInstance = null;

  /**
   * Initialize Supabase client
   */
  function initClient(customUrl, customKey) {
    const sbGlobal = typeof window !== 'undefined' ? window.supabase : ((typeof globalThis !== 'undefined' && globalThis.supabase) ? globalThis.supabase : null);
    if (!sbGlobal) {
      console.warn('Supabase JS SDK not loaded! Make sure @supabase/supabase-js is loaded.');
      return null;
    }
    const url = customUrl || SUPABASE_CONFIG.url;
    const key = customKey || SUPABASE_CONFIG.anonKey;
    clientInstance = sbGlobal.createClient(url, key, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    });
    return clientInstance;
  }

  /**
   * Initialize Admin client using service_role key
   */
  function initAdminClient(customUrl, customKey) {
    const sbGlobal = typeof window !== 'undefined' ? window.supabase : ((typeof globalThis !== 'undefined' && globalThis.supabase) ? globalThis.supabase : null);
    if (!sbGlobal) {
      console.warn('Supabase JS SDK not loaded!');
      return null;
    }
    const url = customUrl || SUPABASE_CONFIG.url;
    const key = customKey || SUPABASE_CONFIG.serviceRoleKey;
    adminClientInstance = sbGlobal.createClient(url, key, {
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    });
    return adminClientInstance;
  }

  function getClient() {
    if (!clientInstance) {
      initClient();
    }
    return clientInstance;
  }

  function getAdminClient() {
    if (!adminClientInstance) {
      initAdminClient();
    }
    return adminClientInstance;
  }

  /**
   * Map raw error to Arabic user-facing text
   */
  function mapErrorMessage(error) {
    if (!error) return ARABIC_ERROR_CATALOG['FALLBACK'];
    if (typeof error === 'string') {
      return ARABIC_ERROR_CATALOG[error] || error;
    }
    
    // Check message property
    const msg = error.message || error.error_description || error.code || '';
    
    // Check known exact strings
    for (const [key, ar] of Object.entries(ARABIC_ERROR_CATALOG)) {
      if (msg.includes(key)) return ar;
    }
    
    // Check details / hint
    if (error.details && typeof error.details === 'string') {
      for (const [key, ar] of Object.entries(ARABIC_ERROR_CATALOG)) {
        if (error.details.includes(key)) return ar;
      }
    }
    
    return msg || ARABIC_ERROR_CATALOG['FALLBACK'];
  }

  /**
   * Display modern toast notification
   */
  function showToast(message, type = 'info', duration = 4000) {
    if (typeof document === 'undefined') {
      console.log(`[TOAST:${type}] ${message}`);
      return;
    }
    let container = document.getElementById('toast-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'toast-container';
      document.body.appendChild(container);
    }

    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    
    const iconMap = {
      success: '✓',
      error: '✕',
      warning: '⚠',
      info: 'ℹ'
    };

    toast.innerHTML = `
      <span style="font-weight:bold; font-size:1.1rem;">${iconMap[type] || 'ℹ'}</span>
      <span class="toast-message" style="flex:1;">${message}</span>
      <span class="toast-close" style="cursor:pointer; opacity:0.6; padding:0 4px;">&times;</span>
    `;

    const closeBtn = toast.querySelector('.toast-close');
    closeBtn.addEventListener('click', () => {
      toast.remove();
    });

    container.appendChild(toast);

    if (duration > 0) {
      setTimeout(() => {
        if (toast.parentElement) {
          toast.style.opacity = '0';
          toast.style.transform = 'translateY(10px)';
          toast.style.transition = 'all 0.25s ease';
          setTimeout(() => toast.remove(), 250);
        }
      }, duration);
    }
  }

  /**
   * Authentication Helpers
   */
  const auth = {
    async loginWithPassword(email, password) {
      const client = getClient();
      const { data, error } = await client.auth.signInWithPassword({
        email: email.trim(),
        password: password
      });
      if (error) {
        throw new Error(mapErrorMessage(error));
      }
      return data;
    },

    async loginWithPhone(phone, password) {
      const client = getClient();
      const { data, error } = await client.auth.signInWithPassword({
        phone: phone.trim(),
        password: password
      });
      if (error) {
        throw new Error(mapErrorMessage(error));
      }
      return data;
    },

    async sendPhoneOtp(phone) {
      const client = getClient();
      const { data, error } = await client.auth.signInWithOtp({
        phone: phone.trim()
      });
      if (error) {
        throw new Error(mapErrorMessage(error));
      }
      return data;
    },

    async verifyPhoneOtp(phone, token = '123456') {
      const client = getClient();
      const { data, error } = await client.auth.verifyOtp({
        phone: phone.trim(),
        token: token.trim(),
        type: 'sms'
      });
      if (error) {
        throw new Error(mapErrorMessage(error));
      }
      return data;
    },

    async signUpWithEmail(email, password, metadata = {}) {
      const client = getClient();
      const { data, error } = await client.auth.signUp({
        email: email.trim(),
        password: password,
        options: {
          data: metadata
        }
      });
      if (error) {
        throw new Error(mapErrorMessage(error));
      }
      return data;
    },

    async logout() {
      const client = getClient();
      const { error } = await client.auth.signOut();
      if (error) {
        console.warn('Sign out warning:', error);
      }
      return true;
    },

    async getSession() {
      const client = getClient();
      const { data, error } = await client.auth.getSession();
      if (error) return null;
      return data.session;
    },

    async getUser() {
      const client = getClient();
      const { data, error } = await client.auth.getUser();
      if (error) return null;
      return data.user;
    },

    async getCurrentUserRole() {
      const client = getClient();
      const { data: { user } } = await client.auth.getUser();
      if (!user) return null;

      // First check public.users role column
      const { data: userData, error } = await client
        .from('users')
        .select('role, name, phone')
        .eq('id', user.id)
        .maybeSingle();

      if (!error && userData && userData.role) {
        return userData.role;
      }

      // Fallback to RPC current_user_role()
      const { data: rpcRole } = await client.rpc('current_user_role');
      if (rpcRole && rpcRole !== 'anon') {
        return rpcRole;
      }

      return 'USER';
    },

    onAuthStateChange(callback) {
      const client = getClient();
      return client.auth.onAuthStateChange(callback);
    }
  };

  /**
   * Helper to invoke RPC safely
   */
  async function invokeRpc(rpcName, params = {}, options = {}) {
    const targetClient = options.useAdmin ? getAdminClient() : getClient();
    const { data, error } = await targetClient.rpc(rpcName, params);
    if (error) {
      const arMessage = mapErrorMessage(error);
      return { data: null, error, messageAr: arMessage, success: false };
    }
    return { data, error: null, messageAr: null, success: true };
  }

  const ChurchSupabase = {
    CONFIG: SUPABASE_CONFIG,
    ERROR_CATALOG: ARABIC_ERROR_CATALOG,
    init: initClient,
    initAdmin: initAdminClient,
    getClient,
    getAdminClient,
    mapErrorMessage,
    showToast,
    auth,
    invokeRpc
  };

  if (typeof window !== 'undefined') {
    window.ChurchSupabase = ChurchSupabase;
  }
  if (typeof globalThis !== 'undefined') {
    globalThis.ChurchSupabase = ChurchSupabase;
  }
})();
