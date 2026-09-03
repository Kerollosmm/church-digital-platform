/**
 * ============================================================================
 * Church Digital Platform — Parishioner / User Web Portal Logic (app.js)
 * ============================================================================
 */

(function () {
  'use strict';

  // Application State
  const state = {
    user: null,
    role: null,
    allSlots: [],
    slotsById: new Map(),
    services: [],
    myBookings: [],
    lockInterval: null
  };

  // Helper: Format Date & Time in Arabic Locale
  function formatDateTime(isoString) {
    if (!isoString) return '—';
    try {
      const d = new Date(isoString);
      return d.toLocaleDateString('ar-EG', {
        weekday: 'short',
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch (e) {
      return isoString;
    }
  }

  function formatTimeOnly(isoString) {
    if (!isoString) return '—';
    try {
      const d = new Date(isoString);
      return d.toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' });
    } catch (e) {
      return isoString;
    }
  }

  function formatPrice(amount) {
    const num = Number(amount || 0);
    if (num === 0) return '<span style="color:var(--emerald); font-weight:700;">مجاني</span>';
    return `<span style="font-weight:700;">${num}</span> <span style="font-size:0.8rem; color:var(--text-muted);">ج.م</span>`;
  }

  function getStatusBadge(status) {
    const s = String(status || '').toUpperCase();
    const map = {
      'AVAILABLE': { label: 'متاح للحجز', cls: 'badge-available' },
      'BOOKED': { label: 'ممتلئ (قائمة انتظار)', cls: 'badge-booked' },
      'CLOSED': { label: 'مغلق', cls: 'badge-closed' },
      'PENDING_PAYMENT': { label: 'في انتظار الدفع', cls: 'badge-pending-payment' },
      'AWAITING_CALL': { label: 'قيد تأكيد الاتصال', cls: 'badge-awaiting-call' },
      'CONFIRMED': { label: 'مؤكد', cls: 'badge-confirmed' },
      'COMPLETED': { label: 'مكتمل', cls: 'badge-completed' },
      'CANCELLED': { label: 'ملغي', cls: 'badge-cancelled' },
      'RESCHEDULED': { label: 'معاد جدولته', cls: 'badge-rescheduled' },
      'NEW': { label: 'جديدة', cls: 'badge-pending-payment' },
      'ASSIGNED': { label: 'قيد المتابعة', cls: 'badge-awaiting-call' },
      'RESOLVED': { label: 'تم الحل', cls: 'badge-confirmed' },
      'WAITING': { label: 'قيد الانتظار', cls: 'badge-awaiting-call' },
      'OFFERED': { label: 'تم توفير مقعد', cls: 'badge-confirmed' }
    };

    const item = map[s] || { label: s, cls: 'badge-closed' };
    return `<span class="badge ${item.cls}">${item.label}</span>`;
  }

  // =========================================================================
  // INITIALIZATION & AUTHENTICATION
  // =========================================================================

  async function initApp() {
    setupTabNavigation();
    setupAuthEvents();
    setupModals();
    setupForms();

    // Check existing session
    const sb = window.ChurchSupabase;
    if (!sb) {
      console.error('ChurchSupabase client not loaded!');
      return;
    }

    // Auth state listener
    sb.auth.onAuthStateChange(async (event, session) => {
      await refreshUserState();
    });

    await refreshUserState();

    // Load public feeds
    await Promise.all([
      loadAnnouncements(),
      loadScheduleToday(),
      loadServicesCatalog(),
      loadFaq(),
      loadSlots(),
      loadPriests()
    ]);
  }

  async function refreshUserState() {
    const sb = window.ChurchSupabase;
    const user = await sb.auth.getUser();
    state.user = user;

    const authSection = document.getElementById('auth-section');

    if (user) {
      state.role = await sb.auth.getCurrentUserRole();
      if (authSection) authSection.style.display = 'none';
      await window.TestAccounts.renderUserBanner('top-user-banner', {
        onLogout: async () => {
          await refreshUserState();
          loadMyBookings();
          loadMyComplaints();
        }
      });
      loadMyBookings();
      loadMyComplaints();
      loadMyWaitlist();
    } else {
      state.role = null;
      if (authSection) authSection.style.display = 'block';
      await window.TestAccounts.renderUserBanner('top-user-banner');
      window.TestAccounts.renderGrid('quick-accounts-container', {
        role: 'USER',
        onSuccess: async () => {
          await refreshUserState();
          loadSlots();
        }
      });
      renderLoggedOutTables();
    }
  }

  function renderLoggedOutTables() {
    const bTbody = document.getElementById('my-bookings-tbody');
    if (bTbody) {
      bTbody.innerHTML = `
        <tr>
          <td colspan="7" style="text-align:center; color:var(--text-muted); padding:24px;">
            🔒 يرجى تسجيل الدخول لعرض وتتبع حجوزاتك السابقة
          </td>
        </tr>
      `;
    }
    const cTbody = document.getElementById('my-complaints-tbody');
    if (cTbody) {
      cTbody.innerHTML = `
        <tr>
          <td colspan="4" style="text-align:center; color:var(--text-muted); padding:24px;">
            🔒 يرجى تسجيل الدخول لعرض الشكاوى والمقترحات السابقة
          </td>
        </tr>
      `;
    }
    const wTbody = document.getElementById('my-waitlist-tbody');
    if (wTbody) {
      wTbody.innerHTML = `
        <tr>
          <td colspan="5" style="text-align:center; color:var(--text-muted); padding:24px;">
            لا توجد طلبات انتظار
          </td>
        </tr>
      `;
    }
    const lockAlert = document.getElementById('lock-alert-container');
    if (lockAlert) lockAlert.innerHTML = '';
  }

  // =========================================================================
  // TAB NAVIGATION
  // =========================================================================

  function setupTabNavigation() {
    const tabBtns = document.querySelectorAll('.tab-btn');
    const tabContents = document.querySelectorAll('.tab-content');
    tabBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        const targetId = btn.getAttribute('data-tab');
        
        tabBtns.forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');

        tabContents.forEach((sec) => {
          sec.style.display = 'none';
          sec.classList.remove('active');
        });

        const activeSec = document.getElementById(targetId);
        if (activeSec) {
          activeSec.style.display = 'block';
          activeSec.classList.add('active');
        }

        // Trigger refreshes
        if (targetId === 'tab-booking') loadSlots();
        if (targetId === 'tab-my-bookings') {
          loadMyBookings();
          loadMyWaitlist();
        }
        if (targetId === 'tab-complaints') loadMyComplaints();
      });
    });
  }

  // =========================================================================
  // AUTH FORMS & HANDLERS
  // =========================================================================

  function setupAuthEvents() {
    const btnTabEmail = document.getElementById('btn-tab-email');
    const btnTabPhone = document.getElementById('btn-tab-phone');
    const btnTabRegister = document.getElementById('btn-tab-register');

    const formEmail = document.getElementById('form-email-login');
    const formPhone = document.getElementById('form-phone-login');
    const formRegister = document.getElementById('form-register');

    function switchAuthTab(activeBtn, activeForm) {
      [btnTabEmail, btnTabPhone, btnTabRegister].forEach(b => {
        b.className = 'btn btn-sm btn-outline';
      });
      [formEmail, formPhone, formRegister].forEach(f => {
        f.style.display = 'none';
      });
      activeBtn.className = 'btn btn-sm btn-primary';
      activeForm.style.display = 'flex';
    }

    btnTabEmail.addEventListener('click', () => switchAuthTab(btnTabEmail, formEmail));
    btnTabPhone.addEventListener('click', () => switchAuthTab(btnTabPhone, formPhone));
    btnTabRegister.addEventListener('click', () => switchAuthTab(btnTabRegister, formRegister));

    // Email Login
    formEmail.addEventListener('submit', async (e) => {
      e.preventDefault();
      const email = document.getElementById('login-email').value;
      const pass = document.getElementById('login-password').value;
      const sb = window.ChurchSupabase;

      try {
        await sb.auth.loginWithPassword(email, pass);
        sb.showToast('تم تسجيل الدخول بنجاح', 'success');
        await refreshUserState();
      } catch (err) {
        sb.showToast(err.message, 'error');
      }
    });

    // Phone OTP Flow
    const btnSendOtp = document.getElementById('btn-send-otp');
    const otpGroup = document.getElementById('otp-verify-group');

    btnSendOtp.addEventListener('click', async () => {
      const phone = document.getElementById('login-phone').value;
      const sb = window.ChurchSupabase;
      if (!phone) {
        sb.showToast('يرجى إدخال رقم الهاتف أولاً', 'warning');
        return;
      }
      try {
        await sb.auth.sendPhoneOtp(phone);
        sb.showToast('تم إرسال رمز التحقق OTP (رمز الاختبار: 123456)', 'info');
        otpGroup.style.display = 'block';
      } catch (err) {
        sb.showToast(err.message, 'error');
      }
    });

    formPhone.addEventListener('submit', async (e) => {
      e.preventDefault();
      const phone = document.getElementById('login-phone').value;
      const otp = document.getElementById('login-otp').value;
      const sb = window.ChurchSupabase;

      try {
        await sb.auth.verifyPhoneOtp(phone, otp);
        sb.showToast('تم التحقق بنجاح وتسجيل الدخول', 'success');
        await refreshUserState();
      } catch (err) {
        sb.showToast(err.message, 'error');
      }
    });

    // Registration Form
    formRegister.addEventListener('submit', async (e) => {
      e.preventDefault();
      const name = document.getElementById('reg-name').value;
      const phone = document.getElementById('reg-phone').value;
      const email = document.getElementById('reg-email').value;
      const password = document.getElementById('reg-password').value;
      const sb = window.ChurchSupabase;

      try {
        await sb.auth.signUpWithEmail(email, password, { name, phone });
        sb.showToast('تم إنشاء الحساب بنجاح! تم تسجيل دخولك تلقائياً', 'success');
        await refreshUserState();
      } catch (err) {
        sb.showToast(err.message, 'error');
      }
    });
  }

  // =========================================================================
  // TAB 1: TODAY & SERVICES LOADERS
  // =========================================================================

  async function loadAnnouncements() {
    const sb = window.ChurchSupabase;
    const client = sb.getClient();
    const container = document.getElementById('announcements-container');
    if (!container) return;

    try {
      const { data, error } = await client
        .from('announcements')
        .select('*')
        .lte('published_at', new Date().toISOString())
        .order('published_at', { ascending: false })
        .limit(3);

      if (error || !data || data.length === 0) {
        container.innerHTML = '';
        return;
      }

      let html = '<div style="display:flex; flex-direction:column; gap:10px;">';
      data.forEach((ann) => {
        html += `
          <div class="card" style="border-right:4px solid var(--gold); padding:12px 16px; background:linear-gradient(90deg, var(--bg-surface), var(--bg-card));">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:4px;">
              <div style="font-weight:700; color:var(--gold); font-size:0.95rem; display:flex; align-items:center; gap:6px;">
                <span>📢</span>
                <span>${ann.title_ar}</span>
              </div>
              <div style="font-size:0.75rem; color:var(--text-muted);">${formatDateTime(ann.published_at)}</div>
            </div>
            <div style="font-size:0.85rem; color:var(--text-secondary); line-height:1.5;">${ann.body_ar}</div>
          </div>
        `;
      });
      html += '</div>';
      container.innerHTML = html;
    } catch (e) {
      console.warn('loadAnnouncements error:', e);
    }
  }

  async function loadScheduleToday() {
    const sb = window.ChurchSupabase;
    const client = sb.getClient();
    const list = document.getElementById('today-schedule-list');
    if (!list) return;

    try {
      const { data, error } = await client.from('v_schedule_today').select('*');
      if (error) throw error;

      if (!data || data.length === 0) {
        list.innerHTML = '<div style="text-align:center; color:var(--text-muted); padding:16px;">لا توجد صلوات أو مواعيد مجدولة لباقي اليوم.</div>';
        return;
      }

      let html = '';
      data.forEach((item) => {
        html += `
          <div style="display:flex; justify-content:space-between; align-items:center; padding:10px 14px; background:var(--bg-surface); border-radius:8px; border:1px solid var(--border-color);">
            <div>
              <div style="font-weight:700; font-size:0.9rem; color:var(--text-primary);">${item.title_ar}</div>
              <div style="font-size:0.78rem; color:var(--text-muted);">${item.location || 'الكنيسة'}</div>
            </div>
            <div style="display:flex; flex-direction:column; align-items:flex-end; gap:4px;">
              <div style="font-size:0.85rem; font-weight:600; color:var(--gold);">${formatTimeOnly(item.starts_at)} - ${formatTimeOnly(item.ends_at)}</div>
              ${getStatusBadge(item.display_status)}
            </div>
          </div>
        `;
      });
      list.innerHTML = html;
    } catch (err) {
      list.innerHTML = `<div style="color:var(--ruby); padding:12px;">تعذر تحميل جدول اليوم: ${sb.mapErrorMessage(err)}</div>`;
    }
  }

  async function loadServicesCatalog() {
    const sb = window.ChurchSupabase;
    const client = sb.getClient();
    const list = document.getElementById('services-catalog-list');
    if (!list) return;

    try {
      const { data, error } = await client.from('v_services').select('*');
      if (error) throw error;

      state.services = data || [];
      updateServiceFilterOptions();

      if (!data || data.length === 0) {
        list.innerHTML = '<div style="text-align:center; color:var(--text-muted); padding:16px;">لا توجد خدمات متاحة حالياً.</div>';
        return;
      }

      let html = '';
      data.forEach((srv) => {
        html += `
          <div style="padding:12px 14px; background:var(--bg-surface); border-radius:8px; border:1px solid var(--border-color); display:flex; justify-content:space-between; align-items:center; gap:10px;">
            <div>
              <div style="font-weight:700; font-size:0.92rem; color:var(--text-primary);">${srv.title_ar}</div>
              <div style="font-size:0.8rem; color:var(--text-secondary); margin-top:2px;">${srv.description || ''}</div>
              <div style="font-size:0.75rem; color:var(--text-muted); margin-top:4px;">المكان: ${srv.location || 'الكاتدرائية'}</div>
            </div>
            <div style="display:flex; flex-direction:column; align-items:flex-end; gap:6px; min-width:90px;">
              <div>${formatPrice(srv.price_from)}</div>
              <button class="btn btn-sm btn-outline btn-book-service" data-service-id="${srv.id}" style="padding:4px 8px; font-size:0.75rem;">
                حجز موعد
              </button>
            </div>
          </div>
        `;
      });
      list.innerHTML = html;

      // Attach direct service booking jump
      list.querySelectorAll('.btn-book-service').forEach((btn) => {
        btn.addEventListener('click', () => {
          const srvId = btn.getAttribute('data-service-id');
          const filterDropdown = document.getElementById('filter-service');
          if (filterDropdown) filterDropdown.value = srvId;
          
          // Switch to booking tab
          const bookTabBtn = document.querySelector('.tab-btn[data-tab="tab-booking"]');
          if (bookTabBtn) bookTabBtn.click();
        });
      });
    } catch (err) {
      list.innerHTML = `<div style="color:var(--ruby); padding:12px;">تعذر تحميل دليل الخدمات: ${sb.mapErrorMessage(err)}</div>`;
    }
  }

  async function loadFaq() {
    const sb = window.ChurchSupabase;
    const client = sb.getClient();
    const container = document.getElementById('faq-accordion-list');
    if (!container) return;

    try {
      const { data, error } = await client.from('v_faq').select('*');
      if (error || !data || data.length === 0) {
        container.innerHTML = '<div style="text-align:center; color:var(--text-muted); padding:12px;">لا توجد أسئلة شائعة حالياً.</div>';
        return;
      }

      let html = '';
      data.forEach((item, idx) => {
        html += `
          <div class="faq-item" style="background:var(--bg-surface); border:1px solid var(--border-color); border-radius:8px; overflow:hidden;">
            <div class="faq-question" style="padding:12px 16px; font-weight:700; cursor:pointer; display:flex; justify-content:space-between; align-items:center; user-select:none;">
              <span>${item.question_ar}</span>
              <span class="faq-icon" style="font-size:0.9rem; color:var(--gold); transition:transform 0.2s ease;">▼</span>
            </div>
            <div class="faq-answer" style="display:none; padding:0 16px 14px 16px; font-size:0.85rem; color:var(--text-secondary); line-height:1.6; border-top:1px dashed var(--border-color); margin-top:6px; padding-top:10px;">
              ${item.answer_ar}
            </div>
          </div>
        `;
      });
      container.innerHTML = html;

      // Attach accordion toggle
      container.querySelectorAll('.faq-question').forEach((q) => {
        q.addEventListener('click', () => {
          const ans = q.nextElementSibling;
          const icon = q.querySelector('.faq-icon');
          if (ans.style.display === 'block') {
            ans.style.display = 'none';
            icon.style.transform = 'rotate(0deg)';
          } else {
            ans.style.display = 'block';
            icon.style.transform = 'rotate(180deg)';
          }
        });
      });
    } catch (e) {
      console.warn('loadFaq error:', e);
    }
  }

  function updateServiceFilterOptions() {
    const select = document.getElementById('filter-service');
    if (!select) return;
    const currentVal = select.value;
    let html = '<option value="ALL">جميع الخدمات</option>';
    state.services.forEach((s) => {
      html += `<option value="${s.id}">${s.title_ar}</option>`;
    });
    select.innerHTML = html;
    if (currentVal) select.value = currentVal;
  }

  // =========================================================================
  // TAB 2: SLOT BROWSING & ATOMIC BOOKING
  // =========================================================================

  async function loadSlots() {
    const sb = window.ChurchSupabase;
    const client = sb.getClient();
    const grid = document.getElementById('slots-grid');
    if (!grid) return;

    try {
      const { data, error } = await client
        .from('v_available_slots')
        .select('*')
        .order('starts_at', { ascending: true });

      if (error) throw error;
      state.allSlots = data || [];
      state.slotsById = new Map(state.allSlots.map((s) => [s.slot_id, s]));
      renderFilteredSlots();
    } catch (err) {
      grid.innerHTML = `<div style="color:var(--ruby); padding:20px; grid-column:1/-1; text-align:center;">تعذر تحميل المواعيد: ${sb.mapErrorMessage(err)}</div>`;
    }
  }

  function renderFilteredSlots() {
    const grid = document.getElementById('slots-grid');
    if (!grid) return;

    const srvFilter = document.getElementById('filter-service')?.value || 'ALL';
    const dateFilter = document.getElementById('filter-date')?.value || '';
    const statusFilter = document.getElementById('filter-status')?.value || 'ALL';

    const filtered = state.allSlots.filter((slot) => {
      if (srvFilter !== 'ALL' && String(slot.service_id) !== String(srvFilter)) {
        return false;
      }
      if (dateFilter) {
        const slotDate = new Date(slot.starts_at).toISOString().split('T')[0];
        if (slotDate !== dateFilter) return false;
      }
      if (statusFilter !== 'ALL') {
        if (statusFilter === 'AVAILABLE' && slot.slot_status !== 'AVAILABLE') return false;
        if (statusFilter === 'BOOKED' && slot.slot_status !== 'BOOKED') return false;
      }
      return true;
    });

    if (filtered.length === 0) {
      grid.innerHTML = `
        <div class="card" style="text-align:center; padding:40px 20px; grid-column:1/-1; color:var(--text-muted);">
          <div style="font-size:2.4rem; margin-bottom:8px;">🎟</div>
          <div style="font-weight:700; font-size:1.1rem; color:var(--text-primary);">لا توجد مواعيد تطابق شروط البحث</div>
          <div style="font-size:0.85rem; margin-top:4px;">يرجى تغيير الفلتر أو اختيار تاريخ مختلف لاستعراض المواعيد.</div>
        </div>
      `;
      return;
    }

    let html = '';
    filtered.forEach((slot) => {
      const isAvailable = slot.slot_status === 'AVAILABLE';
      const isBooked = slot.slot_status === 'BOOKED';
      const isClosed = slot.slot_status === 'CLOSED';

      let actionBtn = '';
      if (isAvailable) {
        actionBtn = `<button class="btn btn-primary btn-open-booking" data-slot-id="${slot.slot_id}" style="width:100%;">احجز الآن</button>`;
      } else if (isBooked) {
        actionBtn = `<button class="btn btn-outline btn-join-waitlist" data-slot-id="${slot.slot_id}" style="width:100%; border-color:var(--amber); color:var(--amber);">انضم لقائمة الانتظار</button>`;
      } else {
        actionBtn = `<button class="btn btn-outline" disabled style="width:100%; opacity:0.5;">الموعد مغلق</button>`;
      }

      html += `
        <div class="card card-interactive slot-card" style="display:flex; flex-direction:column; justify-content:space-between; gap:14px; border-top:3px solid ${isAvailable ? 'var(--emerald)' : (isBooked ? 'var(--amber)' : 'var(--border-color)')};">
          <div>
            <div style="display:flex; justify-content:space-between; align-items:flex-start; gap:10px; margin-bottom:8px;">
              <h4 style="margin:0; font-size:1.05rem; font-weight:800; color:var(--text-primary);">${slot.title_ar}</h4>
              ${getStatusBadge(slot.slot_status)}
            </div>

            <div style="font-size:0.82rem; color:var(--text-secondary); margin-bottom:8px; display:flex; align-items:center; gap:6px;">
              <span>📍</span>
              <span>${slot.location || 'المقر الرئيسي للكنيسة'}</span>
            </div>

            <div style="background:var(--bg-surface); padding:10px 12px; border-radius:8px; border:1px solid var(--border-color); display:flex; flex-direction:column; gap:6px;">
              <div style="display:flex; justify-content:space-between; font-size:0.82rem;">
                <span style="color:var(--text-muted);">التاريخ والوقت:</span>
                <span style="font-weight:700; color:var(--gold);">${formatDateTime(slot.starts_at)}</span>
              </div>
              <div style="display:flex; justify-content:space-between; font-size:0.82rem;">
                <span style="color:var(--text-muted);">المقاعد المتاحة:</span>
                <span style="font-weight:700; color:${isAvailable ? 'var(--emerald)' : 'var(--ruby)'};">${slot.available_seats} من أصل ${slot.capacity}</span>
              </div>
              <div style="display:flex; justify-content:space-between; font-size:0.82rem;">
                <span style="color:var(--text-muted);">المبلغ المطلوب:</span>
                <span>${formatPrice(slot.price)}</span>
              </div>
            </div>
          </div>

          <div style="margin-top:4px;">
            ${actionBtn}
          </div>
        </div>
      `;
    });

    grid.innerHTML = html;

    // Attach Booking Modal triggers
    grid.querySelectorAll('.btn-open-booking').forEach((btn) => {
      btn.addEventListener('click', () => {
        const slotId = Number(btn.getAttribute('data-slot-id'));
        openBookingModal(slotId);
      });
    });

    // Attach Join Waitlist triggers
    grid.querySelectorAll('.btn-join-waitlist').forEach((btn) => {
      btn.addEventListener('click', () => {
        const slotId = Number(btn.getAttribute('data-slot-id'));
        handleJoinWaitlist(slotId);
      });
    });
  }

  // Booking Modal Logic
  let activeSelectedSlot = null;

  function openBookingModal(slotId) {
    const sb = window.ChurchSupabase;
    if (!state.user) {
      sb.showToast('يرجى تسجيل الدخول أولاً لإتمام الحجز', 'warning');
      const authSec = document.getElementById('auth-section');
      if (authSec) {
        authSec.style.display = 'block';
        authSec.scrollIntoView({ behavior: 'smooth' });
      }
      return;
    }

    const slot = state.slotsById?.get(slotId) || state.allSlots.find((s) => s.slot_id === slotId);
    if (!slot) return;

    activeSelectedSlot = slot;
    const modal = document.getElementById('booking-modal');
    const detailsContainer = document.getElementById('modal-slot-details');

    detailsContainer.innerHTML = `
      <div style="background:var(--bg-surface); padding:14px; border-radius:8px; border:1px solid var(--border-color); display:flex; flex-direction:column; gap:8px;">
        <div style="font-size:1.05rem; font-weight:800; color:var(--text-primary);">${slot.title_ar}</div>
        <div style="font-size:0.85rem; color:var(--text-secondary);">📍 ${slot.location || 'الكنيسة'}</div>
        <div style="font-size:0.85rem; color:var(--gold); font-weight:700;">⏰ ${formatDateTime(slot.starts_at)}</div>
        <div style="display:flex; justify-content:space-between; font-size:0.85rem; padding-top:6px; border-top:1px dashed var(--border-color);">
          <span style="color:var(--text-muted);">المبلغ المطلوب:</span>
          <span>${formatPrice(slot.price)}</span>
        </div>
      </div>
    `;

    modal.style.display = 'flex';
  }

  function setupModals() {
    const modal = document.getElementById('booking-modal');
    const btnClose = document.getElementById('btn-close-modal');
    const btnCancel = document.getElementById('btn-cancel-modal');
    const btnConfirm = document.getElementById('btn-confirm-book');

    function closeModal() {
      if (modal) modal.style.display = 'none';
      activeSelectedSlot = null;
    }

    if (btnClose) btnClose.addEventListener('click', closeModal);
    if (btnCancel) btnCancel.addEventListener('click', closeModal);

    if (btnConfirm) {
      btnConfirm.addEventListener('click', async () => {
        if (!activeSelectedSlot) return;
        const slot = activeSelectedSlot;
        const optIn = document.getElementById('modal-opt-in')?.checked ?? true;
        const sb = window.ChurchSupabase;

        btnConfirm.disabled = true;
        btnConfirm.innerText = 'جاري تأكيد الحجز...';

        try {
          const idempotencyKey = crypto.randomUUID ? crypto.randomUUID() : ('idemp-' + Date.now());
          const res = await sb.invokeRpc('book_slot', {
            p_slot_id: slot.slot_id,
            p_opt_in: optIn,
            p_idempotency_key: idempotencyKey
          });

          if (!res.success) {
            throw new Error(res.messageAr || 'تعذر إتمام الحجز');
          }

          sb.showToast('تم حجز الموعد بنجاح! تم قفل المقعد لمدة 20 دقيقة.', 'success');
          closeModal();
          
          // Switch to My Bookings tab and refresh
          const myBookingsTab = document.querySelector('.tab-btn[data-tab="tab-my-bookings"]');
          if (myBookingsTab) myBookingsTab.click();

          await loadSlots();
        } catch (err) {
          sb.showToast(err.message, 'error');
        } finally {
          btnConfirm.disabled = false;
          btnConfirm.innerText = 'تأكيد وحجز الموعد';
        }
      });
    }

    setupProofModal();
  }

  async function openProofModal(bookingId, amount) {
    const sb = window.ChurchSupabase;
    const client = sb.getClient();
    const modal = document.getElementById('proof-modal');
    if (!modal) return;

    document.getElementById('proof-booking-id').value = bookingId;
    document.getElementById('proof-amount').value = amount || 50;

    const channelsContainer = document.getElementById('proof-payout-channels-list');
    if (channelsContainer) {
      channelsContainer.innerHTML = 'جاري تحميل أرقام الحسابات...';
      try {
        const { data, error } = await client.from('payout_channels').select('*');
        if (error || !data || data.length === 0) {
          channelsContainer.innerHTML = '<div>فودافون كاش: 01000000000 | إنستاباي: church@instapay</div>';
        } else {
          let html = '';
          data.forEach((ch) => {
            html += `<div><strong>${ch.display_name_ar}:</strong> <span style="font-family:'JetBrains Mono';">${ch.account_number}</span> (${ch.holder_name})</div>`;
          });
          channelsContainer.innerHTML = html;
        }
      } catch (e) {
        channelsContainer.innerHTML = '<div>فودافون كاش: 01000000000 | إنستاباي: church@instapay</div>';
      }
    }

    modal.style.display = 'flex';
  }

  function setupProofModal() {
    const modal = document.getElementById('proof-modal');
    const btnClose = document.getElementById('btn-close-proof-modal');
    const btnCancel = document.getElementById('btn-cancel-proof');
    const form = document.getElementById('form-submit-proof');
    const channelSelect = document.getElementById('proof-channel');
    const imageGroup = document.getElementById('proof-image-group');

    function closeModal() {
      if (modal) modal.style.display = 'none';
      if (form) form.reset();
    }

    if (btnClose) btnClose.addEventListener('click', closeModal);
    if (btnCancel) btnCancel.addEventListener('click', closeModal);

    if (channelSelect && imageGroup) {
      channelSelect.addEventListener('change', () => {
        if (channelSelect.value === 'CASH') {
          imageGroup.style.display = 'none';
        } else {
          imageGroup.style.display = 'block';
        }
      });
    }

    if (form) {
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const sb = window.ChurchSupabase;
        const client = sb.getClient();
        const bookingId = Number(document.getElementById('proof-booking-id').value);
        const channel = document.getElementById('proof-channel').value;
        const phone = document.getElementById('proof-sender-phone').value;
        const ref = document.getElementById('proof-reference').value;
        const amount = Number(document.getElementById('proof-amount').value);
        const fileInput = document.getElementById('proof-image-file');
        const submitBtn = document.getElementById('btn-confirm-proof');

        if (channel !== 'CASH' && (!fileInput.files || fileInput.files.length === 0)) {
          sb.showToast('يرجى إرفاق صورة إشعار التحويل', 'error');
          return;
        }

        submitBtn.disabled = true;
        submitBtn.innerText = 'جاري رفع الإثبات...';

        try {
          let imagePath = null;
          if (channel !== 'CASH' && fileInput.files && fileInput.files.length > 0) {
            const file = fileInput.files[0];
            const ext = file.name.split('.').pop() || 'jpg';
            const filename = `1/${bookingId}/${Date.now()}_proof.${ext}`;
            const { data: uploadData, error: upErr } = await client.storage
              .from('payment-proofs')
              .upload(filename, file, { upsert: true });

            if (upErr) throw upErr;
            imagePath = filename;
          }

          const res = await sb.invokeRpc('submit_payment_proof', {
            p_booking_id: bookingId,
            p_channel: channel,
            p_sender_phone: phone,
            p_reference: ref,
            p_amount: amount,
            p_image_path: imagePath,
          });

          if (!res.success) {
            throw new Error(res.messageAr || 'تعذر إرسال إثبات الدفع');
          }

          sb.showToast('✓ تم إرسال إثبات الدفع بنجاح — بانتظار المراجعة من الإدارة', 'success');
          closeModal();
          await loadMyBookings();
        } catch (err) {
          sb.showToast(err.message, 'error');
        } finally {
          submitBtn.disabled = false;
          submitBtn.innerText = 'إرسال الإثبات للمراجعة';
        }
      });
    }
  }

  async function handleJoinWaitlist(slotId) {
    const sb = window.ChurchSupabase;
    if (!state.user) {
      sb.showToast('يرجى تسجيل الدخول أولاً للانضمام لقائمة الانتظار', 'warning');
      return;
    }

    try {
      const res = await sb.invokeRpc('join_waiting_list', { p_slot_id: slotId });
      if (!res.success) {
        throw new Error(res.messageAr || 'تعذر الانضمام لقائمة الانتظار');
      }
      sb.showToast('تم تسجيلك بنجاح في قائمة الانتظار! سيتم إخطارك فور توفر مقعد.', 'success');
      loadMyWaitlist();
      loadSlots();
    } catch (err) {
      sb.showToast(err.message, 'error');
    }
  }

  // =========================================================================
  // TAB 3: MY BOOKINGS, LOCK TIMER & PAYMOB SIMULATOR
  // =========================================================================

  async function loadMyBookings() {
    if (!state.user) return;
    const sb = window.ChurchSupabase;
    const client = sb.getClient();
    const tbody = document.getElementById('my-bookings-tbody');
    const badgeCount = document.getElementById('my-bookings-count-badge');

    try {
      const { data, error } = await client
        .from('v_my_bookings')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;
      state.myBookings = data || [];

      if (badgeCount) {
        const activeCount = state.myBookings.filter(b => ['PENDING_PAYMENT', 'AWAITING_CALL', 'CONFIRMED'].includes(b.status)).length;
        if (activeCount > 0) {
          badgeCount.innerText = activeCount;
          badgeCount.style.display = 'inline-block';
        } else {
          badgeCount.style.display = 'none';
        }
      }

      if (state.myBookings.length === 0) {
        tbody.innerHTML = `
          <tr>
            <td colspan="7" style="text-align:center; color:var(--text-muted); padding:24px;">
              لا توجد حجوزات مسجلة لك حتى الآن. يمكنك تصفح المواعيد وحجز قداسك الآن!
            </td>
          </tr>
        `;
        checkLockCountdown();
        return;
      }

      let html = '';
      state.myBookings.forEach((b) => {
        const isPendingPayment = b.status === 'PENDING_PAYMENT';
        const canCancel = ['PENDING_PAYMENT', 'AWAITING_CALL', 'CONFIRMED'].includes(b.status);

        let actions = '<div style="display:flex; gap:6px; flex-wrap:wrap;">';
        if (isPendingPayment) {
          actions += `
            <button class="btn btn-sm btn-primary btn-submit-proof" data-booking-id="${b.id}" data-amount="${b.paid_amount || 0}" style="padding:4px 8px; font-size:0.75rem;">
              📸 إرسال إثبات الدفع
            </button>
            <button class="btn btn-sm btn-outline btn-paymob-checkout" data-booking-id="${b.id}" style="padding:4px 8px; font-size:0.75rem;">
              💳 دفع Paymob
            </button>
            <button class="btn btn-sm btn-outline btn-simulate-paymob" data-booking-id="${b.id}" data-amount="${b.paid_amount || 0}" style="padding:4px 8px; font-size:0.75rem; border-color:var(--gold); color:var(--gold);">
              ⚡ محاكاة دفع
            </button>
          `;
        }
        if (canCancel) {
          actions += `
            <button class="btn btn-sm btn-outline btn-cancel-booking" data-booking-id="${b.id}" style="padding:4px 8px; font-size:0.75rem; border-color:var(--ruby); color:var(--ruby);">
              إلغاء
            </button>
          `;
        }
        actions += '</div>';

        html += `
          <tr>
            <td style="font-family:'JetBrains Mono'; font-weight:700; color:var(--gold);">#${b.id}</td>
            <td style="font-weight:700;">${b.service_name || 'خدمة كنسية'}</td>
            <td style="font-size:0.82rem;">${formatDateTime(b.starts_at)}</td>
            <td style="font-size:0.82rem; color:var(--text-secondary);">${b.location || 'الكنيسة'}</td>
            <td>${formatPrice(b.paid_amount)}</td>
            <td>${getStatusBadge(b.status)}</td>
            <td>${actions}</td>
          </tr>
        `;
      });
      tbody.innerHTML = html;

      // Attach Submit Proof
      tbody.querySelectorAll('.btn-submit-proof').forEach((btn) => {
        btn.addEventListener('click', () => {
          const bookingId = Number(btn.getAttribute('data-booking-id'));
          const amount = Number(btn.getAttribute('data-amount') || 0);
          openProofModal(bookingId, amount);
        });
      });

      // Attach Paymob Checkout
      tbody.querySelectorAll('.btn-paymob-checkout').forEach((btn) => {
        btn.addEventListener('click', () => {
          const bookingId = Number(btn.getAttribute('data-booking-id'));
          handlePaymobCheckout(bookingId);
        });
      });

      // Attach Simulate Paymob Webhook
      tbody.querySelectorAll('.btn-simulate-paymob').forEach((btn) => {
        btn.addEventListener('click', () => {
          const bookingId = Number(btn.getAttribute('data-booking-id'));
          const amount = Number(btn.getAttribute('data-amount') || 0);
          handleSimulatePaymob(bookingId, amount);
        });
      });

      // Attach Cancel Booking
      tbody.querySelectorAll('.btn-cancel-booking').forEach((btn) => {
        btn.addEventListener('click', () => {
          const bookingId = Number(btn.getAttribute('data-booking-id'));
          handleCancelBooking(bookingId);
        });
      });

      checkLockCountdown();
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="7" style="color:var(--ruby); padding:16px;">تعذر تحميل الحجوزات: ${sb.mapErrorMessage(err)}</td></tr>`;
    }
  }

  function checkLockCountdown() {
    if (state.lockInterval) {
      clearInterval(state.lockInterval);
      state.lockInterval = null;
    }

    const alertContainer = document.getElementById('lock-alert-container');
    if (!alertContainer) return;

    const pendingBooking = state.myBookings.find(
      (b) => b.status === 'PENDING_PAYMENT' && b.locked_until && new Date(b.locked_until) > new Date()
    );

    if (!pendingBooking) {
      alertContainer.innerHTML = '';
      return;
    }

    function updateAlert() {
      const now = new Date();
      const lockEnd = new Date(pendingBooking.locked_until);
      const diffMs = lockEnd - now;

      if (diffMs <= 0) {
        alertContainer.innerHTML = `
          <div style="background:rgba(239, 68, 68, 0.15); border:1px solid var(--ruby); border-radius:10px; padding:12px 16px; margin-bottom:16px; display:flex; justify-content:space-between; align-items:center;">
            <div style="display:flex; align-items:center; gap:10px; color:var(--ruby);">
              <span>⚠️</span>
              <span>انتهت مهلة الـ 20 دقيقة لقفل الحجز #${pendingBooking.id}. يرجى تحديث الصفحة لإعادة الحجز.</span>
            </div>
            <button onclick="window.location.reload()" class="btn btn-sm btn-outline">تحديث</button>
          </div>
        `;
        clearInterval(state.lockInterval);
        return;
      }

      const totalSec = Math.floor(diffMs / 1000);
      const mins = Math.floor(totalSec / 60);
      const secs = totalSec % 60;
      const timeStr = `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;

      alertContainer.innerHTML = `
        <div style="background:linear-gradient(90deg, rgba(217, 119, 6, 0.15), rgba(30, 41, 59, 0.6)); border:1px solid var(--gold); border-radius:10px; padding:12px 16px; margin-bottom:16px; display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px;">
          <div style="display:flex; align-items:center; gap:10px;">
            <span style="font-size:1.3rem;">⏳</span>
            <div>
              <div style="font-weight:700; color:var(--gold);">تنبيه قفل الحجز #${pendingBooking.id} (${pendingBooking.service_name})</div>
              <div style="font-size:0.8rem; color:var(--text-secondary);">المقعد محجوز لك مؤقتاً لحين تأكيد الدفع الإلكتروني أو إتمام الطلب.</div>
            </div>
          </div>
          <div style="display:flex; align-items:center; gap:10px;">
            <div style="font-family:'JetBrains Mono'; font-size:1.2rem; font-weight:800; color:var(--gold); background:rgba(0,0,0,0.4); padding:4px 10px; border-radius:6px;">
              ${timeStr}
            </div>
            <button class="btn btn-sm btn-primary" onclick="document.querySelector('.btn-simulate-paymob[data-booking-id=\\'${pendingBooking.id}\\']')?.click()">
              إتمام الدفع الفوري
            </button>
          </div>
        </div>
      `;
    }

    updateAlert();
    state.lockInterval = setInterval(updateAlert, 1000);
  }

  async function handlePaymobCheckout(bookingId) {
    const sb = window.ChurchSupabase;
    const session = await sb.auth.getSession();
    if (!session || !session.access_token) {
      sb.showToast('يرجى تسجيل الدخول أولاً', 'error');
      return;
    }

    sb.showToast('جاري الاتصال ببوابة Paymob...', 'info');

    try {
      const res = await fetch('http://127.0.0.1:54321/functions/v1/paymob-checkout', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({ booking_id: bookingId })
      });

      const json = await res.json();
      if (!res.ok) {
        throw new Error(json.message_ar || json.message || 'تعذر إنشاء جلسة الدفع');
      }

      if (json.checkout_url) {
        sb.showToast('تم إنشاء رابط الدفع بنجاح! جاري التوجيه...', 'success');
        window.open(json.checkout_url, '_blank');
      } else {
        sb.showToast('تم تجهيز سجل الدفع برقم ' + json.payment_id, 'info');
      }
    } catch (err) {
      sb.showToast(err.message, 'error');
    }
  }

  async function handleSimulatePaymob(bookingId, amount) {
    const sb = window.ChurchSupabase;
    const sim = window.PaymobSimulator;
    if (!sim) {
      sb.showToast('محاكي Paymob غير متوفر', 'error');
      return;
    }

    sb.showToast(`جاري محاكاة دفع Paymob للحجز #${bookingId}...`, 'info');

    try {
      const client = sb.getClient();
      
      // Check if payment row exists for this booking or create one
      let { data: existingPay } = await client
        .from('payments')
        .select('id, status')
        .eq('booking_id', bookingId)
        .maybeSingle();

      let paymentId = existingPay?.id;

      if (!paymentId) {
        // Create payment record
        const { data: newPay, error: pErr } = await client
          .from('payments')
          .insert({
            booking_id: bookingId,
            amount: amount,
            status: 'CREATED'
          })
          .select()
          .single();

        if (pErr) throw pErr;
        paymentId = newPay.id;

        // Set merchant_order_id to payment.id
        await client
          .from('payments')
          .update({ merchant_order_id: String(paymentId) })
          .eq('id', paymentId);
      } else {
        // Ensure merchant_order_id is set
        await client
          .from('payments')
          .update({ merchant_order_id: String(paymentId) })
          .eq('id', paymentId);
      }

      // Build genuine SHA-512 Paymob Webhook payload
      const webhookPayload = await sim.buildWebhookPayload({
        merchantOrderId: String(paymentId),
        amountCents: Math.round((amount || 50) * 100),
        success: true
      });

      // Dispatch webhook to Edge Function
      const hookRes = await sim.sendWebhook(
        webhookPayload,
        webhookPayload.hmac,
        'http://127.0.0.1:54321'
      );

      if (!hookRes.ok) {
        const errMsg = hookRes.data?.message_ar || hookRes.data?.message || 'فشل معالجة الـ Webhook';
        throw new Error(errMsg);
      }

      sb.showToast('✓ تم تأكيد الدفع بنجاح وتحويل الحجز إلى: قيد تأكيد الاتصال (AWAITING_CALL)', 'success');
      await loadMyBookings();
      await loadSlots();
    } catch (err) {
      sb.showToast(err.message, 'error');
    }
  }

  async function handleCancelBooking(bookingId) {
    const sb = window.ChurchSupabase;
    if (!confirm(`هل أنت متأكد من رغبتك في إلغاء الحجز #${bookingId}؟`)) {
      return;
    }

    try {
      const res = await sb.invokeRpc('cancel_booking', { p_booking_id: bookingId });
      if (!res.success) {
        throw new Error(res.messageAr || 'تعذر إلغاء الحجز');
      }
      sb.showToast(`تم إلغاء الحجز #${bookingId} بنجاح.`, 'info');
      await loadMyBookings();
      await loadSlots();
    } catch (err) {
      sb.showToast(err.message, 'error');
    }
  }

  async function loadMyWaitlist() {
    if (!state.user) return;
    const sb = window.ChurchSupabase;
    const client = sb.getClient();
    const tbody = document.getElementById('my-waitlist-tbody');
    if (!tbody) return;

    try {
      const { data, error } = await client
        .from('waiting_list')
        .select('*, service_slots(starts_at, ends_at, services(title_ar))')
        .order('created_at', { ascending: false });

      if (error) throw error;

      if (!data || data.length === 0) {
        tbody.innerHTML = `
          <tr>
            <td colspan="5" style="text-align:center; color:var(--text-muted); padding:20px;">
              لا توجد طلبات انتظار حالية.
            </td>
          </tr>
        `;
        return;
      }

      let html = '';
      data.forEach((w) => {
        const slot = w.service_slots;
        const srvTitle = slot?.services?.title_ar || 'خدمة كنسية';
        html += `
          <tr>
            <td style="font-family:'JetBrains Mono'; font-weight:700; color:var(--gold);">#${w.id}</td>
            <td style="font-weight:700;">${srvTitle}</td>
            <td style="font-size:0.82rem;">${slot ? formatDateTime(slot.starts_at) : '—'}</td>
            <td style="font-weight:700; color:var(--amber);">الترتيب: ${w.position || 1}</td>
            <td>${getStatusBadge(w.status)}</td>
          </tr>
        `;
      });
      tbody.innerHTML = html;
    } catch (e) {
      console.warn('loadMyWaitlist error:', e);
    }
  }

  // =========================================================================
  // TAB 4: COMMUNITY & PRIESTS
  // =========================================================================

  async function loadPriests() {
    const sb = window.ChurchSupabase;
    const client = sb.getClient();
    const grid = document.getElementById('priests-directory-grid');
    if (!grid) return;

    try {
      const { data, error } = await client.from('v_priests').select('*');
      if (error) throw error;

      if (!data || data.length === 0) {
        grid.innerHTML = '<div style="text-align:center; color:var(--text-muted); padding:20px; grid-column:1/-1;">لا يوجد بيانات حالياً.</div>';
        return;
      }

      let html = '';
      data.forEach((p) => {
        const hours = p.visitation_hours?.available || 'حسب الموعد المسبق';
        html += `
          <div class="card card-interactive" style="display:flex; flex-direction:column; gap:12px; border-top:3px solid var(--gold);">
            <div style="display:flex; align-items:center; gap:14px;">
              <img src="${p.photo_url || 'https://images.unsplash.com/photo-1544005313-94ddf0286df2'}" alt="${p.name}" style="width:60px; height:60px; border-radius:50%; object-fit:cover; border:2px solid var(--gold);">
              <div>
                <h4 style="margin:0; font-size:1.05rem; font-weight:800; color:var(--text-primary);">${p.name}</h4>
                <span class="badge badge-role-admin" style="font-size:0.7rem; margin-top:2px;">كاهن الكنيسة</span>
              </div>
            </div>
            <div style="font-size:0.85rem; color:var(--text-secondary); line-height:1.5;">
              ${p.bio || 'كاهن مبارك وخادم لرعية الكنيسة.'}
            </div>
            <div style="background:var(--bg-surface); padding:8px 12px; border-radius:6px; border:1px solid var(--border-color); font-size:0.8rem; display:flex; align-items:center; gap:6px;">
              <span>🕒</span>
              <span style="color:var(--text-muted);">مواعيد المقابلات:</span>
              <strong style="color:var(--gold);">${hours}</strong>
            </div>
          </div>
        `;
      });
      grid.innerHTML = html;
    } catch (err) {
      grid.innerHTML = `<div style="color:var(--ruby); padding:16px; grid-column:1/-1;">تعذر تحميل دليل الكهنة: ${sb.mapErrorMessage(err)}</div>`;
    }
  }

  // =========================================================================
  // TAB 5: MINISTRY RECRUITMENT & TAB 6: ENCRYPTED COMPLAINTS
  // =========================================================================

  function setupForms() {
    // Ministry Recruitment Form
    const formRecruitment = document.getElementById('form-recruitment');
    if (formRecruitment) {
      formRecruitment.addEventListener('submit', (e) => {
        e.preventDefault();
        const sb = window.ChurchSupabase;
        const name = document.getElementById('recruit-name').value;
        const ministry = document.getElementById('recruit-ministry').value;
        
        sb.showToast(`شكراً لك يا ${name}! تم استلام طلب التطوع في الخدمة وسيتواصل معك أمين الخدمة قريباً.`, 'success', 6000);
        formRecruitment.reset();
      });
    }

    // Complaints Character Counter
    const complaintBody = document.getElementById('complaint-body');
    const charCounter = document.getElementById('complaint-char-count');
    if (complaintBody && charCounter) {
      complaintBody.addEventListener('input', () => {
        charCounter.innerText = `${complaintBody.value.length} / 4000`;
      });
    }

    // Submit Encrypted Complaint
    const formComplaint = document.getElementById('form-submit-complaint');
    if (formComplaint) {
      formComplaint.addEventListener('submit', async (e) => {
        e.preventDefault();
        const sb = window.ChurchSupabase;
        if (!state.user) {
          sb.showToast('يرجى تسجيل الدخول أولاً لتقديم الشكوى', 'warning');
          return;
        }

        const category = document.getElementById('complaint-category').value;
        const body = document.getElementById('complaint-body').value;
        const btnSubmit = document.getElementById('btn-submit-complaint');

        btnSubmit.disabled = true;
        btnSubmit.innerText = 'جاري التشفير والإرسال...';

        try {
          const res = await sb.invokeRpc('submit_complaint_secure', {
            p_category: category,
            p_body: body
          });

          if (!res.success) {
            throw new Error(res.messageAr || 'تعذر إرسال الشكوى');
          }

          sb.showToast('✓ تم تشفير الشكوى وحفظها بنجاح برقم: ' + res.data, 'success');
          formComplaint.reset();
          if (charCounter) charCounter.innerText = '0 / 4000';
          await loadMyComplaints();
        } catch (err) {
          sb.showToast(err.message, 'error');
        } finally {
          btnSubmit.disabled = false;
          btnSubmit.innerText = 'تشفير وإرسال الشكوى';
        }
      });
    }

    // Refresh buttons
    document.getElementById('btn-refresh-today')?.addEventListener('click', () => {
      loadScheduleToday();
      loadAnnouncements();
    });
    document.getElementById('btn-refresh-slots')?.addEventListener('click', loadSlots);
    document.getElementById('btn-refresh-my-bookings')?.addEventListener('click', () => {
      loadMyBookings();
      loadMyWaitlist();
    });
    document.getElementById('btn-refresh-complaints')?.addEventListener('click', loadMyComplaints);

    // Filters on change
    document.getElementById('filter-service')?.addEventListener('change', renderFilteredSlots);
    document.getElementById('filter-date')?.addEventListener('input', renderFilteredSlots);
    document.getElementById('filter-status')?.addEventListener('change', renderFilteredSlots);
  }

  async function loadMyComplaints() {
    if (!state.user) return;
    const sb = window.ChurchSupabase;
    const client = sb.getClient();
    const tbody = document.getElementById('my-complaints-tbody');
    if (!tbody) return;

    try {
      const { data, error } = await client
        .from('v_my_complaints')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;

      if (!data || data.length === 0) {
        tbody.innerHTML = `
          <tr>
            <td colspan="4" style="text-align:center; color:var(--text-muted); padding:20px;">
              لا توجد شكاوى أو مقترحات مسجلة لك حالياً.
            </td>
          </tr>
        `;
        return;
      }

      let html = '';
      data.forEach((c) => {
        const catMap = {
          'GENERAL': 'عام ومقترحات',
          'SPIRITUAL': 'رعاية وافتقاد',
          'ORGANIZATIONAL': 'تنظيم وخدمات',
          'FINANCIAL': 'مساعدات',
          'CONFIDENTIAL': 'سري وخاص'
        };
        const catLabel = catMap[c.category] || c.category;

        html += `
          <tr>
            <td style="font-family:'JetBrains Mono'; font-weight:700; color:var(--gold);">#${c.id}</td>
            <td><span class="badge badge-role-user">${catLabel}</span></td>
            <td>${getStatusBadge(c.status)}</td>
            <td style="font-size:0.82rem;">${formatDateTime(c.created_at)}</td>
          </tr>
        `;
      });
      tbody.innerHTML = html;
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="4" style="color:var(--ruby); padding:16px;">تعذر تحميل الشكاوى: ${sb.mapErrorMessage(err)}</td></tr>`;
    }
  }

  // Launch when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initApp);
  } else {
    initApp();
  }

})();
