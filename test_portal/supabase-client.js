// test_portal/supabase-client.js: Shared Supabase client & utilities for test portals

export const SUPABASE_URL = 'http://127.0.0.1:54321';
export const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
export const SUPABASE_SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

// Demo Credentials
export const DEMO_USERS = [
  { email: 'mariam@church.test', role: 'USER', name: 'مريم جورج (مستخدم)', phone: '+201000000002' },
  { email: 'peter@church.test', role: 'USER', name: 'بيتر عادل (مستخدم)', phone: '+201000000003' },
  { email: 'admin@church.test', role: 'ADMIN', name: 'مدير النظام (مسؤول خادم)', phone: '+201000000001' },
  { email: 'priest@church.test', role: 'ADMIN', name: 'أب كيرلس (كاهن / مسؤول)', phone: '+201000000004' },
  { email: 'superadmin@church.local', role: 'SUPER_ADMIN', name: 'مسؤول النظام العام', phone: '+201000000005' }
];

// Initialize Supabase Client
export const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true
  }
});

// Admin elevated client for Super Admin maintenance
export const supabaseAdmin = window.supabase.createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    persistSession: false,
    autoRefreshToken: false
  }
});

// Arabic Error Catalog per AGENTS.md locked contract
const ERROR_CATALOG = {
  'AUTH_REQUIRED': 'يجب تسجيل الدخول أولاً لإتمام هذه العملية.',
  'FORBIDDEN': 'ليس لديك صلاحية لتنفيذ هذا الإجراء.',
  'SLOT_UNAVAILABLE': 'الموعد المحدد غير متاح حالياً أو انتهى وقته.',
  'SLOT_FULL': 'عفواً، اكتمل العدد الأقصى للحجز في هذا الموعد.',
  'ALREADY_BOOKED_SLOT': 'لقد قمت بحجز هذا الموعد بالفعل مسبقاً.',
  'TOO_MANY_ACTIVE_BOOKINGS': 'تجاوزت الحد الأقصى للحجوزات النشطة (3 حجوزات كحد أقصى).',
  'BOOKING_NOT_FOUND': 'لم يتم العثور على الحجز المطلوب.',
  'INVALID_PIN': 'رمز PIN غير صحيح أو غير متطابق.',
  'PIN_LOCKED': 'تم قفل إدخال PIN مؤقتاً بسبب تكرار المحاولات الخاطئة (15 دقيقة).',
  'ANNOUNCEMENT_NOT_FOUND': 'الإعلان غير موجود.',
  'ALT_TEXT_REQUIRED': 'يجب توفير نص بديل توضيحي للصور (Accessibility).',
  'UPSTREAM_ERROR': 'حدث خطأ أثناء الاتصال بالخدمة الخارجية (Paymob/Meta).',
  'INTERNAL': 'حدث خطأ غير متوقع بالخادم، يرجى المحاولة لاحقاً.'
};

export function parseError(err) {
  if (!err) return 'عملية غير معروفة';
  const msg = err.message || err.details || String(err);
  for (const [code, arText] of Object.entries(ERROR_CATALOG)) {
    if (msg.includes(code)) return `${arText} (${code})`;
  }
  return msg;
}

// Toast Notifications
export function showToast(message, type = 'info') {
  let container = document.getElementById('toast-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toast-container';
    document.body.appendChild(container);
  }
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.innerHTML = `
    <span>${message}</span>
    <button style="background:none;border:none;color:#94a3b8;cursor:pointer;font-size:1.1rem;" onclick="this.parentElement.remove()">&times;</button>
  `;
  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    setTimeout(() => toast.remove(), 300);
  }, 4500);
}

// Get Active Profile & Role
export async function getProfile() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.user) return null;
  const { data, error } = await supabase
    .from('users')
    .select('*')
    .eq('id', session.user.id)
    .single();
  if (error || !data) {
    return {
      id: session.user.id,
      email: session.user.email,
      role: 'USER',
      name: session.user.user_metadata?.name || session.user.email
    };
  }
  return { ...data, email: session.user.email };
}

// Quick Switcher UI Component Builder
export function renderQuickLoginBar(targetElementId, onLoginSuccess) {
  const el = document.getElementById(targetElementId);
  if (!el) return;
  el.className = 'quick-login-bar';
  el.innerHTML = `
    <span style="font-size:0.85rem; font-weight:700; color:var(--text-muted);">⚡ تبديل الحساب السريع (Demo Users):</span>
    ${DEMO_USERS.map(u => `
      <button class="quick-chip" data-email="${u.email}" data-role="${u.role}">
        <span class="badge ${u.role === 'SUPER_ADMIN' ? 'badge-purple' : u.role === 'ADMIN' ? 'badge-yellow' : 'badge-blue'}">${u.role}</span>
        <span>${u.name}</span>
      </button>
    `).join('')}
  `;

  el.querySelectorAll('.quick-chip').forEach(btn => {
    btn.onclick = async () => {
      const email = btn.dataset.email;
      btn.style.opacity = '0.5';
      const { data, error } = await supabase.auth.signInWithPassword({
        email: email,
        password: 'password123'
      });
      btn.style.opacity = '1';
      if (error) {
        showToast(`فشل الدخول: ${parseError(error)}`, 'error');
      } else {
        showToast(`تم تسجيل الدخول بنجاح كـ ${email}`, 'success');
        if (onLoginSuccess) onLoginSuccess(data.user);
      }
    };
  });
}

// Format Dates
export function formatDate(isoStr) {
  if (!isoStr) return '-';
  const d = new Date(isoStr);
  return d.toLocaleString('ar-EG', {
    dateStyle: 'medium',
    timeStyle: 'short'
  });
}

// Translate Status Badges
export function renderStatusBadge(status) {
  switch (status) {
    case 'PENDING_PAYMENT':
      return `<span class="badge badge-yellow">في انتظار الدفع (PENDING_PAYMENT)</span>`;
    case 'AWAITING_CALL':
      return `<span class="badge badge-blue">قيد المراجعة الهاتفية (AWAITING_CALL)</span>`;
    case 'CONFIRMED':
      return `<span class="badge badge-green">مؤكد (CONFIRMED)</span>`;
    case 'COMPLETED':
      return `<span class="badge badge-purple">مكتمل (COMPLETED)</span>`;
    case 'CANCELLED':
      return `<span class="badge badge-red">ملغي (CANCELLED)</span>`;
    case 'REJECTED':
      return `<span class="badge badge-red">مرفوض (REJECTED)</span>`;
    case 'AVAILABLE':
      return `<span class="badge badge-green">متاح (AVAILABLE)</span>`;
    case 'BOOKED':
      return `<span class="badge badge-red">مكتمل (BOOKED)</span>`;
    case 'CLOSED':
      return `<span class="badge badge-yellow">مغلق (CLOSED)</span>`;
    default:
      return `<span class="badge">${status || '-'}</span>`;
  }
}
