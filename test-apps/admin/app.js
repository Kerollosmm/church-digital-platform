/**
 * ============================================================================
 * Church Digital Platform — Admin Web Dashboard Application Logic
 * ============================================================================
 */

(function () {
  'use strict';

  // Application State
  const state = {
    currentUser: null,
    userRole: null,
    pinVerified: false,
    bookings: [],
    services: [],
    slots: [],
    complaints: [],
    outbox: [],
    failedOutbox: [],
    announcements: [],
    proofs: [],
    activeTab: 'tab-queue',
    autoRefreshTimer: null,
    currentActionBookingId: null,
    currentActionProofId: null,
    currentActionProofBookingId: null,
    currentActionProofAmount: null
  };

  /**
   * Format ISO date to readable Arabic locale string
   */
  function formatDate(isoStr) {
    if (!isoStr) return '--';
    try {
      const d = new Date(isoStr);
      return d.toLocaleDateString('ar-EG', {
        weekday: 'short',
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch {
      return isoStr;
    }
  }

  function formatTimeOnly(isoStr) {
    if (!isoStr) return '--';
    try {
      const d = new Date(isoStr);
      return d.toLocaleTimeString('ar-EG', {
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch {
      return isoStr;
    }
  }

  /**
   * Returns HTML for status badge based on booking status
   */
  function getBookingBadgeHtml(status) {
    const map = {
      'PENDING_PAYMENT': { label: 'قيد انتظار الدفع', cls: 'badge-pending-payment' },
      'AWAITING_CALL': { label: 'قيد الاتصال الهاتفي', cls: 'badge-awaiting-call' },
      'CONFIRMED': { label: 'مؤكد', cls: 'badge-confirmed' },
      'COMPLETED': { label: 'مكتمل الحضور', cls: 'badge-completed' },
      'CANCELLED': { label: 'ملغي', cls: 'badge-cancelled' },
      'RESCHEDULED': { label: 'معاد جدولته', cls: 'badge-rescheduled' }
    };
    const s = map[status] || { label: status || 'غير معروف', cls: 'badge-pending' };
    return `<span class="badge ${s.cls}"><span class="badge-dot"></span>${s.label}</span>`;
  }

  /**
   * Returns HTML for outbox status badge
   */
  function getOutboxBadgeHtml(status) {
    const map = {
      'PENDING': { label: 'معلق', cls: 'badge-pending' },
      'PROCESSING': { label: 'قيد المعالجة', cls: 'badge-awaiting-call' },
      'SENT': { label: 'تم الإرسال', cls: 'badge-confirmed' },
      'FAILED': { label: 'فشل الإرسال', cls: 'badge-cancelled' }
    };
    const s = map[status] || { label: status || 'غير معروف', cls: 'badge-pending' };
    return `<span class="badge ${s.cls}"><span class="badge-dot"></span>${s.label}</span>`;
  }

  /**
   * Returns HTML for complaint status badge
   */
  function getComplaintBadgeHtml(status) {
    const map = {
      'NEW': { label: 'جديدة', cls: 'badge-pending-payment' },
      'ASSIGNED': { label: 'مُسندة للمتابعة', cls: 'badge-awaiting-call' },
      'RESOLVED': { label: 'تم الحل', cls: 'badge-confirmed' }
    };
    const s = map[status] || { label: status || 'غير معروف', cls: 'badge-pending' };
    return `<span class="badge ${s.cls}"><span class="badge-dot"></span>${s.label}</span>`;
  }

  /**
   * Initialize Admin Application
   */
  async function init() {
    console.log('[AdminApp] Initializing Church Admin Dashboard...');

    // Initialize shared client
    if (window.ChurchSupabase) {
      window.ChurchSupabase.init();
      window.ChurchSupabase.initAdmin();
    }

    // Render top user banner
    if (window.TestAccounts) {
      window.TestAccounts.renderUserBanner('top-user-banner', {
        onLogout: handleLogout
      });

      // Render 1-click admin login accounts
      window.TestAccounts.renderGrid('login-accounts-grid', {
        role: 'ADMIN',
        onSuccess: async () => {
          await checkAuthAndRole();
        }
      });
    }

    // Check auth and role
    await checkAuthAndRole();

    // Start auto-refresh timer if enabled
    const autoRefreshCheckbox = document.getElementById('chk-auto-refresh');
    if (autoRefreshCheckbox && autoRefreshCheckbox.checked) {
      toggleAutoRefresh(true);
    }

    // Modal escape key listener
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closeAllModals();
      }
    });
  }

  /**
   * Check Auth & PIN Role Gate
   */
  async function checkAuthAndRole() {
    const sb = window.ChurchSupabase;
    if (!sb) return;

    const secLogin = document.getElementById('sec-login');
    const secForbidden = document.getElementById('sec-forbidden');
    const secPinGate = document.getElementById('sec-pin-gate');
    const secDashboard = document.getElementById('sec-dashboard');

    // Hide all main sections initially
    secLogin.style.display = 'none';
    secForbidden.style.display = 'none';
    secPinGate.style.display = 'none';
    secDashboard.style.display = 'none';

    const user = await sb.auth.getUser();
    state.currentUser = user;

    if (!user) {
      // 1. Not logged in -> Show Login Section
      secLogin.style.display = 'block';
      if (window.TestAccounts) {
        window.TestAccounts.renderUserBanner('top-user-banner');
      }
      return;
    }

    // Update banner
    if (window.TestAccounts) {
      window.TestAccounts.renderUserBanner('top-user-banner', {
        onLogout: handleLogout
      });
    }

    // 2. Fetch User Role
    const role = await sb.auth.getCurrentUserRole();
    state.userRole = role;
    console.log('[AdminApp] User authenticated:', user.email, 'Role:', role);

    // 3. Gate check: Must be ADMIN or SUPER_ADMIN
    if (role !== 'ADMIN' && role !== 'SUPER_ADMIN') {
      secForbidden.style.display = 'block';
      sb.showToast('حساب رعية (USER) غير مصرح له بدخول لوحة الإدارة', 'warning');
      return;
    }

    // 4. Admin 2FA PIN Gate Challenge
    const sessionPinVerified = sessionStorage.getItem('admin_pin_verified') === 'true';
    
    // Check pin status via RPC
    const { data: pinStatus, error: pinErr } = await sb.invokeRpc('admin_pin_status');
    console.log('[AdminApp] PIN Status:', pinStatus, pinErr);

    if (pinStatus === 'UNSET') {
      secPinGate.style.display = 'block';
      document.getElementById('pin-status-banner').className = 'alert alert-warning';
      document.getElementById('pin-status-text').textContent = '⚠️ لم يتم ضبط رمز PIN الإداري لهذا الحساب بعد.';
      document.getElementById('pin-verify-box').style.display = 'none';
      document.getElementById('pin-setup-box').style.display = 'block';
      document.getElementById('pin-locked-box').style.display = 'none';
      return;
    }

    if (pinStatus === 'LOCKED') {
      secPinGate.style.display = 'block';
      document.getElementById('pin-status-banner').className = 'alert alert-danger';
      document.getElementById('pin-status-text').textContent = '⛔ تم قفل رمز PIN الإداري مؤقتاً بسبب تكرار المحاولات الخاطئة.';
      document.getElementById('pin-verify-box').style.display = 'none';
      document.getElementById('pin-setup-box').style.display = 'none';
      document.getElementById('pin-locked-box').style.display = 'block';
      return;
    }

    // If PIN is SET but not verified in this browser session
    if (!sessionPinVerified) {
      secPinGate.style.display = 'block';
      document.getElementById('pin-status-banner').className = 'alert alert-info';
      document.getElementById('pin-status-text').textContent = '🔒 تم تفعيل التحقق بخطوتين (PIN 2FA) لحماية العمليات الإدارية.';
      document.getElementById('pin-verify-box').style.display = 'block';
      document.getElementById('pin-setup-box').style.display = 'none';
      document.getElementById('pin-locked-box').style.display = 'none';
      return;
    }

    // 5. Fully Verified & Authorized -> Show Dashboard
    state.pinVerified = true;
    secDashboard.style.display = 'block';
    await loadAllDashboardData();
  }

  /**
   * Handle PIN Verification
   */
  async function handleVerifyPin() {
    const pinInput = document.getElementById('pin-input');
    const pin = (pinInput ? pinInput.value : '').trim();

    if (!pin || pin.length < 4) {
      window.ChurchSupabase.showToast('يرجى إدخال رمز PIN مكون من 4 إلى 6 أرقام', 'warning');
      return;
    }

    const btn = document.getElementById('btn-verify-pin');
    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner"></span> <span>جاري التحقق...</span>';
    }

    try {
      const { data: verified, error } = await window.ChurchSupabase.invokeRpc('verify_admin_pin', { p_pin: pin });
      
      if (error || !verified) {
        window.ChurchSupabase.showToast('رمز PIN غير صحيح أو تم قفل الحساب لتكرار المحاولات', 'error');
        if (pinInput) {
          pinInput.value = '';
          pinInput.focus();
        }
        await checkAuthAndRole();
        return;
      }

      // Success
      sessionStorage.setItem('admin_pin_verified', 'true');
      state.pinVerified = true;
      window.ChurchSupabase.showToast('تم التحقق من رمز PIN بنجاح! مرحباً بك في لوحة الإدارة', 'success');
      await checkAuthAndRole();
    } catch (e) {
      window.ChurchSupabase.showToast(e.message || 'حدث خطأ أثناء التحقق من PIN', 'error');
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = '<span>تأكيد رمز PIN</span>';
      }
    }
  }

  /**
   * Handle Setting New Admin PIN
   */
  async function handleSetPin() {
    const pinNewInput = document.getElementById('pin-new-input');
    const pin = (pinNewInput ? pinNewInput.value : '').trim();

    if (!pin || pin.length < 4 || !/^[0-9]{4,6}$/.test(pin)) {
      window.ChurchSupabase.showToast('يجب أن يتكون رمز PIN من 4 إلى 6 أرقام عددية فقط', 'warning');
      return;
    }

    const btn = document.getElementById('btn-set-pin');
    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner"></span> <span>جاري الحفظ...</span>';
    }

    try {
      const { error } = await window.ChurchSupabase.invokeRpc('set_admin_pin', { p_pin: pin });
      if (error) {
        throw new Error(window.ChurchSupabase.mapErrorMessage(error));
      }

      sessionStorage.setItem('admin_pin_verified', 'true');
      state.pinVerified = true;
      window.ChurchSupabase.showToast('تم حفظ وتفعيل رمز PIN بنجاح!', 'success');
      await checkAuthAndRole();
    } catch (e) {
      window.ChurchSupabase.showToast(e.message || 'فشل حفظ رمز PIN', 'error');
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = '<span>حفظ وتفعيل PIN</span>';
      }
    }
  }

  /**
   * Handle Password Login
   */
  async function handlePasswordLogin() {
    const email = document.getElementById('login-email').value;
    const pass = document.getElementById('login-password').value;
    const btn = document.getElementById('btn-submit-login');

    if (!email || !pass) return;

    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> <span>جاري تسجيل الدخول...</span>';

    try {
      await window.ChurchSupabase.auth.loginWithPassword(email, pass);
      window.ChurchSupabase.showToast('تم تسجيل الدخول بنجاح', 'success');
      await checkAuthAndRole();
    } catch (err) {
      window.ChurchSupabase.showToast(err.message, 'error');
    } finally {
      btn.disabled = false;
      btn.innerHTML = '<span>تسجيل الدخول</span>';
    }
  }

  /**
   * Switch account
   */
  async function switchAccount(accountId) {
    sessionStorage.removeItem('admin_pin_verified');
    state.pinVerified = false;
    await window.TestAccounts.loginAs(accountId);
    await checkAuthAndRole();
  }

  /**
   * Handle Logout
   */
  async function handleLogout() {
    sessionStorage.removeItem('admin_pin_verified');
    state.pinVerified = false;
    await window.ChurchSupabase.auth.logout();
    await checkAuthAndRole();
  }

  /**
   * Load All Dashboard Data in Parallel
   */
  async function loadAllDashboardData() {
    try {
      await Promise.all([
        loadBookings(),
        loadServicesAndSlots(),
        loadComplaints(),
        loadOutboxEvents(),
        loadAnnouncements(),
        loadPendingProofs()
      ]);
      updateTopStats();
    } catch (e) {
      console.error('[AdminApp] Error loading dashboard data:', e);
    }
  }

  /**
   * Refresh all data manually
   */
  async function refreshAllData() {
    window.ChurchSupabase.showToast('جاري تحديث بيانات المنظومة...', 'info', 1500);
    await loadAllDashboardData();
  }

  /**
   * Toggle Auto Refresh Timer
   */
  function toggleAutoRefresh(enabled) {
    if (state.autoRefreshTimer) {
      clearInterval(state.autoRefreshTimer);
      state.autoRefreshTimer = null;
    }
    if (enabled) {
      state.autoRefreshTimer = setInterval(async () => {
        if (state.pinVerified && state.currentUser) {
          await Promise.all([
            loadBookings(true),
            loadComplaints(true),
            loadOutboxEvents(true),
            loadPendingProofs(true)
          ]);
          updateTopStats();
        }
      }, 8000);
    }
  }

  /**
   * Update top stats metrics
   */
  function updateTopStats() {
    const totalEl = document.getElementById('stat-total-bookings');
    const awaitingEl = document.getElementById('stat-awaiting-call');
    const confirmedEl = document.getElementById('stat-confirmed-bookings');
    const failedOutboxEl = document.getElementById('stat-outbox-failed');

    const awaitingCount = state.bookings.filter(b => b.status === 'AWAITING_CALL').length;
    const confirmedCount = state.bookings.filter(b => b.status === 'CONFIRMED' || b.status === 'COMPLETED').length;
    const failedOutboxCount = state.failedOutbox.length;

    if (totalEl) totalEl.textContent = state.bookings.length;
    if (awaitingEl) awaitingEl.textContent = awaitingCount;
    if (confirmedEl) confirmedEl.textContent = confirmedCount;
    if (failedOutboxEl) failedOutboxEl.textContent = failedOutboxCount;

    // Badges in tab header
    const tabBadgeAwaiting = document.getElementById('tab-badge-awaiting');
    if (tabBadgeAwaiting) {
      tabBadgeAwaiting.textContent = awaitingCount;
      tabBadgeAwaiting.style.display = awaitingCount > 0 ? 'inline-flex' : 'none';
    }

    const newComplaintsCount = state.complaints.filter(c => c.status === 'NEW').length;
    const tabBadgeComplaints = document.getElementById('tab-badge-complaints');
    if (tabBadgeComplaints) {
      tabBadgeComplaints.textContent = newComplaintsCount;
      tabBadgeComplaints.style.display = newComplaintsCount > 0 ? 'inline-flex' : 'none';
    }

    const pendingProofsCount = state.proofs.filter(p => p.status === 'PENDING').length;
    const tabBadgeProofs = document.getElementById('tab-badge-proofs');
    if (tabBadgeProofs) {
      tabBadgeProofs.textContent = pendingProofsCount;
      tabBadgeProofs.style.display = pendingProofsCount > 0 ? 'inline-flex' : 'none';
    }
  }

  /**
   * =========================================================================
   * TAB 1: BOOKING REVIEW & CONFIRMATION QUEUE
   * =========================================================================
   */
  async function loadBookings(silent = false) {
    const client = window.ChurchSupabase.getClient();
    const { data, error } = await client
      .from('bookings')
      .select(`
        *,
        users (id, name, phone, role),
        service_slots (
          id, starts_at, ends_at, location, price, capacity,
          services (id, title_ar)
        )
      `)
      .order('id', { ascending: false });

    if (error) {
      if (!silent) window.ChurchSupabase.showToast('تعذر تحميل الحجوزات: ' + error.message, 'error');
      return;
    }

    state.bookings = data || [];
    renderBookings();
  }

  function filterBookings() {
    renderBookings();
  }

  function renderBookings() {
    const tbody = document.getElementById('tbody-bookings');
    if (!tbody) return;

    const statusFilter = document.getElementById('filter-booking-status').value;
    const searchQuery = (document.getElementById('search-booking').value || '').trim().toLowerCase();

    let filtered = state.bookings;

    if (statusFilter !== 'ALL') {
      filtered = filtered.filter(b => b.status === statusFilter);
    }

    if (searchQuery) {
      filtered = filtered.filter(b => {
        const name = (b.users?.name || '').toLowerCase();
        const phone = (b.users?.phone || '').toLowerCase();
        const idStr = String(b.id);
        const service = (b.service_slots?.services?.title_ar || '').toLowerCase();
        return name.includes(searchQuery) || phone.includes(searchQuery) || idStr.includes(searchQuery) || service.includes(searchQuery);
      });
    }

    if (filtered.length === 0) {
      tbody.innerHTML = `
        <tr>
          <td colspan="8" style="text-align:center; padding:30px;" class="text-muted">
            لا توجد حجوزات مطابقة للفلاتر المحددة
          </td>
        </tr>
      `;
      return;
    }

    let html = '';
    filtered.forEach(b => {
      const userName = b.users?.name || 'مخدوم';
      const userPhone = b.users?.phone || '--';
      const serviceTitle = b.service_slots?.services?.title_ar || 'قداس إلهي';
      const slotTime = formatDate(b.service_slots?.starts_at);
      const slotLocation = b.service_slots?.location || 'الكنيسة الرئيسية';
      const paidAmount = b.paid_amount ? `${b.paid_amount} ج.م` : 'مجاني';

      // Action buttons according to state
      let actionButtons = '';

      if (b.status === 'AWAITING_CALL') {
        actionButtons += `
          <button onclick="window.AdminApp.confirmBooking(${b.id})" class="btn btn-sm btn-success" title="تأكيد الحجز بعد إجراء المكالمة الهاتفية">
            <span>📞 تأكيد الحجز</span>
          </button>
        `;
      }

      if (b.status === 'CONFIRMED') {
        actionButtons += `
          <button onclick="window.AdminApp.completeBooking(${b.id})" class="btn btn-sm btn-primary" title="تسجيل اكتمال الحضور">
            <span>✅ تم الحضور</span>
          </button>
        `;
      }

      if (b.status !== 'CANCELLED' && b.status !== 'COMPLETED') {
        actionButtons += `
          <button onclick="window.AdminApp.openEmergencyOverrideModal(${b.id})" class="btn btn-sm btn-warning" title="إعادة جدولة طارئة للموعد">
            <span>🔄 إعادة جدولة</span>
          </button>
          <button onclick="window.AdminApp.openCancelModal(${b.id})" class="btn btn-sm btn-outline" style="color:var(--danger); border-color:var(--danger-border);" title="إلغاء أو رفض الحجز">
            <span>❌ إلغاء</span>
          </button>
        `;
      }

      html += `
        <tr>
          <td><strong class="font-mono" style="color:var(--gold);">#${b.id}</strong></td>
          <td>
            <div style="font-weight:700; color:var(--text-primary);">${userName}</div>
            <div class="text-xs text-muted font-mono">${b.user_id ? b.user_id.slice(0, 8) + '...' : ''}</div>
          </td>
          <td>
            <div class="flex items-center gap-1">
              <a href="tel:${userPhone}" class="btn btn-xs btn-outline font-mono" style="font-size:0.78rem; padding:2px 8px;">
                📞 ${userPhone}
              </a>
            </div>
          </td>
          <td>
            <strong style="color:var(--text-primary);">${serviceTitle}</strong>
          </td>
          <td>
            <div style="font-size:0.85rem;">${slotTime}</div>
            <div class="text-xs text-muted">${slotLocation}</div>
          </td>
          <td>
            <span class="badge ${b.paid_amount > 0 ? 'badge-paid' : 'badge-open'}">${paidAmount}</span>
          </td>
          <td>
            ${getBookingBadgeHtml(b.status)}
          </td>
          <td style="text-align:center;">
            <div class="action-btn-group" style="justify-content:center;">
              ${actionButtons}
            </div>
          </td>
        </tr>
      `;
    });

    tbody.innerHTML = html;
  }

  /**
   * Confirm Booking (Calls confirm_booking RPC)
   */
  async function confirmBooking(bookingId) {
    window.ChurchSupabase.showToast(`جاري تأكيد الحجز #${bookingId}...`, 'info', 2000);
    const { error, messageAr } = await window.ChurchSupabase.invokeRpc('confirm_booking', {
      p_booking_id: bookingId
    });

    if (error) {
      window.ChurchSupabase.showToast(messageAr || 'تعذر تأكيد الحجز', 'error');
      return;
    }

    window.ChurchSupabase.showToast(`تم تأكيد الحجز #${bookingId} بنجاح! تم نقل الحالة إلى CONFIRMED`, 'success');
    await loadBookings();
    updateTopStats();
  }

  /**
   * Complete Booking (Calls complete_booking RPC)
   */
  async function completeBooking(bookingId) {
    window.ChurchSupabase.showToast(`جاري تسجيل اكتمال الحضور للحجز #${bookingId}...`, 'info', 2000);
    const { error, messageAr } = await window.ChurchSupabase.invokeRpc('complete_booking', {
      p_booking_id: bookingId
    });

    if (error) {
      window.ChurchSupabase.showToast(messageAr || 'تعذر تسجيل اكتمال الحضور', 'error');
      return;
    }

    window.ChurchSupabase.showToast(`تم تسجيل اكتمال الحضور للحجز #${bookingId} (COMPLETED)`, 'success');
    await loadBookings();
    updateTopStats();
  }

  /**
   * Cancel / Reject Modal & Execution
   */
  function openCancelModal(bookingId) {
    state.currentActionBookingId = bookingId;
    const textEl = document.getElementById('cancel-booking-id-text');
    if (textEl) textEl.textContent = `#${bookingId}`;
    const reasonInput = document.getElementById('cancel-reason');
    if (reasonInput) reasonInput.value = '';
    openModal('modal-cancel-booking');
  }

  async function executeCancelBooking() {
    const bookingId = state.currentActionBookingId;
    if (!bookingId) return;

    const reason = (document.getElementById('cancel-reason').value || 'admin_reject').trim();
    const btn = document.getElementById('btn-confirm-cancel');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> <span>جاري الإلغاء...</span>';

    try {
      const { error, messageAr } = await window.ChurchSupabase.invokeRpc('transition_booking_status', {
        p_booking_id: bookingId,
        p_new_status: 'CANCELLED',
        p_action: 'admin_reject',
        p_reason: reason
      });

      if (error) {
        throw new Error(messageAr || 'تعذر إلغاء الحجز');
      }

      window.ChurchSupabase.showToast(`تم إلغاء الحجز #${bookingId} بنجاح`, 'info');
      closeModal('modal-cancel-booking');
      await loadBookings();
      updateTopStats();
    } catch (e) {
      window.ChurchSupabase.showToast(e.message, 'error');
    } finally {
      btn.disabled = false;
      btn.innerHTML = '<span>تأكيد الإلغاء</span>';
    }
  }

  /**
   * Emergency Override Modal & Execution
   */
  async function openEmergencyOverrideModal(bookingId) {
    state.currentActionBookingId = bookingId;
    const textEl = document.getElementById('override-booking-id-text');
    if (textEl) textEl.textContent = `#${bookingId}`;

    const selectEl = document.getElementById('override-new-slot-select');
    selectEl.innerHTML = '<option value="">جاري تحميل المواعيد المتاحة...</option>';

    openModal('modal-emergency-override');

    // Fetch open future slots
    const client = window.ChurchSupabase.getClient();
    const { data: slots } = await client
      .from('service_slots')
      .select('id, starts_at, location, capacity, services(title_ar)')
      .gt('starts_at', new Date().toISOString())
      .eq('status', 'OPEN')
      .order('starts_at', { ascending: true });

    if (!slots || slots.length === 0) {
      selectEl.innerHTML = '<option value="">لا توجد مواعيد مستقبلية مفتوحة</option>';
      return;
    }

    let opts = '<option value="">-- اختر موعداً بديلاً --</option>';
    slots.forEach(s => {
      const svc = s.services?.title_ar || 'خدمة';
      opts += `<option value="${s.id}">${svc} — ${formatDate(s.starts_at)} (${s.location})</option>`;
    });
    selectEl.innerHTML = opts;
  }

  async function executeEmergencyOverride() {
    const bookingId = state.currentActionBookingId;
    const selectEl = document.getElementById('override-new-slot-select');
    const newSlotId = selectEl ? parseInt(selectEl.value, 10) : null;
    const refundChecked = document.getElementById('override-refund-check').checked;

    if (!bookingId || !newSlotId) {
      window.ChurchSupabase.showToast('يرجى اختيار الموعد البديل', 'warning');
      return;
    }

    const btn = document.getElementById('btn-confirm-override');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> <span>جاري التنفيذ...</span>';

    try {
      const { data: newBookingId, error, messageAr } = await window.ChurchSupabase.invokeRpc('emergency_override', {
        p_booking_id: bookingId,
        p_new_slot_id: newSlotId,
        p_refund: refundChecked
      });

      if (error) {
        throw new Error(messageAr || 'تعذر تنفيذ الإعادة الجدولة الطارئة');
      }

      window.ChurchSupabase.showToast(`تمت إعادة الجدولة بنجاح! تم إنشاء الحجز البديل #${newBookingId} وإرسال إشعار WhatsApp`, 'success');
      closeModal('modal-emergency-override');
      await Promise.all([loadBookings(), loadOutboxEvents()]);
      updateTopStats();
    } catch (e) {
      window.ChurchSupabase.showToast(e.message, 'error');
    } finally {
      btn.disabled = false;
      btn.innerHTML = '<span>تنفيذ الإعادة الجدولة الطارئة</span>';
    }
  }

  /**
   * =========================================================================
   * TAB 2: MANUAL / CASH BOOKING IN-PERSON
   * =========================================================================
   */
  async function loadServicesAndSlots() {
    const client = window.ChurchSupabase.getClient();

    // 1. Load services
    const { data: servicesData } = await client
      .from('services')
      .select('*')
      .order('id', { ascending: true });
    state.services = servicesData || [];

    // Populate service dropdowns
    const manualSelect = document.getElementById('manual-service-select');
    const slotCreateSelect = document.getElementById('slot-service-select');

    if (manualSelect) {
      let opts = '<option value="">-- اختر الخدمة --</option>';
      state.services.forEach(s => {
        opts += `<option value="${s.id}">${s.title_ar}</option>`;
      });
      manualSelect.innerHTML = opts;
    }

    if (slotCreateSelect) {
      let opts = '<option value="">-- اختر الخدمة --</option>';
      state.services.forEach(s => {
        opts += `<option value="${s.id}">${s.title_ar}</option>`;
      });
      slotCreateSelect.innerHTML = opts;
    }

    // 2. Load slots
    await loadSlots();
  }

  async function loadSlotsForService(serviceId) {
    const slotSelect = document.getElementById('manual-slot-select');
    const previewEl = document.getElementById('manual-slot-preview');
    previewEl.style.display = 'none';

    if (!serviceId) {
      slotSelect.innerHTML = '<option value="">-- اختر الخدمة أولاً --</option>';
      return;
    }

    slotSelect.innerHTML = '<option value="">جاري تحميل المواعيد...</option>';

    const client = window.ChurchSupabase.getClient();
    const { data: slots, error } = await client
      .from('v_available_slots')
      .select('*')
      .eq('service_id', serviceId)
      .order('starts_at', { ascending: true });

    if (error || !slots || slots.length === 0) {
      slotSelect.innerHTML = '<option value="">لا توجد مواعيد متاحة لهذه الخدمة حالياً</option>';
      return;
    }

    let opts = '<option value="">-- اختر الموعد المتاح --</option>';
    slots.forEach(s => {
      const dateStr = formatDate(s.starts_at);
      const avail = s.available_seats;
      const statusBadge = s.slot_status;
      opts += `<option value="${s.slot_id}">${dateStr} (${s.location}) — المتاح: ${avail} مقعد [${statusBadge}]</option>`;
    });
    slotSelect.innerHTML = opts;
  }

  async function onSlotSelected(slotId) {
    const previewEl = document.getElementById('manual-slot-preview');
    const contentEl = document.getElementById('manual-slot-preview-content');

    if (!slotId) {
      previewEl.style.display = 'none';
      return;
    }

    const client = window.ChurchSupabase.getClient();
    const { data: slot } = await client
      .from('v_available_slots')
      .select('*')
      .eq('slot_id', slotId)
      .maybeSingle();

    if (!slot) return;

    contentEl.innerHTML = `
      <div style="font-weight:700; font-size:0.95rem; margin-bottom:6px; color:var(--text-primary);">${slot.title_ar}</div>
      <div class="text-xs text-muted" style="line-height:1.7;">
        <div>📅 <strong>الموعد:</strong> ${formatDate(slot.starts_at)} إلى ${formatTimeOnly(slot.ends_at)}</div>
        <div>📍 <strong>المكان:</strong> ${slot.location || 'الكنيسة الرئيسية'}</div>
        <div>🪑 <strong>السعة الإجمالية:</strong> ${slot.capacity} مقعد | <strong>المحجوز:</strong> ${slot.booked_count} | <strong>المتاح:</strong> ${slot.available_seats} مقعد</div>
        <div>💰 <strong>السعر:</strong> ${slot.price > 0 ? `${slot.price} ج.م` : 'مجاني'}</div>
      </div>
    `;
    previewEl.style.display = 'block';
  }

  async function handleManualBooking() {
    const slotId = parseInt(document.getElementById('manual-slot-select').value, 10);
    const phone = (document.getElementById('manual-phone').value || '').trim();
    const optIn = document.getElementById('manual-opt-in').checked;
    const notes = (document.getElementById('manual-notes').value || 'حجز يدوي من لوحة التحكم').trim();
    const btn = document.getElementById('btn-submit-manual-book');
    const resultBox = document.getElementById('manual-book-result');
    const resultDetails = document.getElementById('manual-result-details');

    if (!slotId) {
      window.ChurchSupabase.showToast('يرجى اختيار الموعد المتاح', 'warning');
      return;
    }
    if (!phone) {
      window.ChurchSupabase.showToast('يرجى إدخال رقم هاتف المخدوم', 'warning');
      return;
    }

    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> <span>جاري تسجيل الحجز وتأكيده...</span>';
    resultBox.style.display = 'none';

    try {
      const { data: booking, error, messageAr } = await window.ChurchSupabase.invokeRpc('manual_book', {
        p_slot_id: slotId,
        p_phone: phone,
        p_opt_in: optIn,
        p_notes: notes
      });

      if (error) {
        throw new Error(messageAr || 'تعذر إتمام الحجز اليدوي');
      }

      // Display result
      resultDetails.innerHTML = `
        <div>📌 <strong>رقم الحجز:</strong> #${booking.id}</div>
        <div>👤 <strong>الهاتف المسجل:</strong> ${phone}</div>
        <div>🏷️ <strong>الحالة:</strong> <span class="badge badge-confirmed">مؤكد فوراً (CONFIRMED)</span></div>
        <div>📝 <strong>الملاحظات:</strong> ${booking.notes || notes}</div>
        <div>⏰ <strong>تاريخ التسجيل:</strong> ${formatDate(booking.created_at)}</div>
      `;
      resultBox.style.display = 'block';

      window.ChurchSupabase.showToast(`تم إصدار وتأكيد الحجز #${booking.id} بنجاح!`, 'success');
      
      // Refresh queues & slots
      await Promise.all([loadBookings(), loadSlots()]);
      updateTopStats();
    } catch (e) {
      window.ChurchSupabase.showToast(e.message, 'error');
    } finally {
      btn.disabled = false;
      btn.innerHTML = '<span>⚡ تسجيل وتأكيد الحجز فوراً (manual_book)</span>';
    }
  }

  /**
   * =========================================================================
   * TAB 3: CAPACITY, SLOTS & ANNOUNCEMENTS
   * =========================================================================
   */
  async function loadSlots() {
    const client = window.ChurchSupabase.getClient();
    const { data: slots, error } = await client
      .from('service_slots')
      .select('*, services(title_ar)')
      .order('starts_at', { ascending: true });

    if (error) {
      console.warn('Error loading slots:', error);
      return;
    }

    state.slots = slots || [];
    renderSlots();
  }

  function renderSlots() {
    const tbody = document.getElementById('tbody-slots');
    if (!tbody) return;

    if (state.slots.length === 0) {
      tbody.innerHTML = `
        <tr>
          <td colspan="9" style="text-align:center; padding:30px;" class="text-muted">
            لا توجد مواعيد مسجلة حالياً
          </td>
        </tr>
      `;
      return;
    }

    let html = '';
    state.slots.forEach(s => {
      const svcTitle = s.services?.title_ar || 'خدمة';
      const startsStr = formatDate(s.starts_at);
      const endsStr = formatTimeOnly(s.ends_at);
      const isOpen = s.status === 'OPEN';
      const statusBadge = isOpen
        ? '<span class="badge badge-open">مفتوح OPEN</span>'
        : '<span class="badge badge-closed">مغلق CLOSED</span>';

      html += `
        <tr>
          <td><strong class="font-mono" style="color:var(--gold);">#${s.id}</strong></td>
          <td><strong>${svcTitle}</strong></td>
          <td>${s.location || 'الكنيسة الرئيسية'}</td>
          <td style="font-size:0.85rem;">${startsStr}</td>
          <td style="font-size:0.85rem;">${endsStr}</td>
          <td>
            <div style="font-size:0.85rem; font-weight:700;">${s.capacity} مقعد</div>
            <div class="slot-capacity-bar">
              <div class="slot-capacity-fill" style="width:${Math.min(100, Math.round(((s.capacity - (s.remaining_capacity ?? s.capacity)) / s.capacity) * 100))}%;"></div>
            </div>
          </td>
          <td>${s.price > 0 ? `${s.price} ج.م` : 'مجاني'}</td>
          <td>${statusBadge}</td>
          <td style="text-align:center;">
            <button onclick="window.AdminApp.toggleSlotStatus(${s.id}, '${s.status}')" class="btn btn-xs ${isOpen ? 'btn-outline' : 'btn-success'}" style="font-size:0.78rem;">
              ${isOpen ? 'إغلاق الموعد' : 'فتح الموعد'}
            </button>
          </td>
        </tr>
      `;
    });

    tbody.innerHTML = html;
  }

  async function toggleSlotStatus(slotId, currentStatus) {
    const newStatus = currentStatus === 'OPEN' ? 'CLOSED' : 'OPEN';
    window.ChurchSupabase.showToast(`جاري تحويل حالة الموعد #${slotId} إلى ${newStatus}...`, 'info', 1500);

    const client = window.ChurchSupabase.getClient();
    const { error } = await client
      .from('service_slots')
      .update({ status: newStatus, updated_at: new Date().toISOString() })
      .eq('id', slotId);

    if (error) {
      window.ChurchSupabase.showToast('تعذر تعديل حالة الموعد: ' + error.message, 'error');
      return;
    }

    window.ChurchSupabase.showToast(`تم تعديل حالة الموعد #${slotId} إلى ${newStatus}`, 'success');
    await loadSlots();
  }

  function openCreateSlotModal() {
    // Set default times (tomorrow 08:00 - 10:00)
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(8, 0, 0, 0);

    const tomorrowEnd = new Date(tomorrow);
    tomorrowEnd.setHours(10, 0, 0, 0);

    // Format for datetime-local input
    const toLocalISO = (d) => {
      const tzOffset = d.getTimezoneOffset() * 60000;
      return new Date(d.getTime() - tzOffset).toISOString().slice(0, 16);
    };

    document.getElementById('slot-starts-at').value = toLocalISO(tomorrow);
    document.getElementById('slot-ends-at').value = toLocalISO(tomorrowEnd);

    openModal('modal-create-slot');
  }

  async function handleCreateSlot() {
    const serviceId = parseInt(document.getElementById('slot-service-select').value, 10);
    const startsAt = new Date(document.getElementById('slot-starts-at').value).toISOString();
    const endsAt = new Date(document.getElementById('slot-ends-at').value).toISOString();
    const capacity = parseInt(document.getElementById('slot-capacity').value, 10);
    const price = parseInt(document.getElementById('slot-price').value, 10) || 0;
    const location = (document.getElementById('slot-location').value || 'الكنيسة الرئيسية').trim();
    const btn = document.getElementById('btn-save-slot');

    if (!serviceId || !startsAt || !endsAt || !capacity) {
      window.ChurchSupabase.showToast('يرجى ملء كافة بيانات الموعد المطلوبة', 'warning');
      return;
    }

    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> <span>جاري الحفظ...</span>';

    try {
      const client = window.ChurchSupabase.getClient();
      const scheduleRange = `[${startsAt},${endsAt})`;

      const { data, error } = await client
        .from('service_slots')
        .insert({
          service_id: serviceId,
          starts_at: startsAt,
          ends_at: endsAt,
          capacity: capacity,
          remaining_capacity: capacity,
          price: price,
          location: location,
          status: 'OPEN',
          schedule_range: scheduleRange,
          tenant_id: 1
        })
        .select()
        .single();

      if (error) {
        if (error.code === '23P01' || error.message.includes('overlap') || error.message.includes('no_location_schedule_overlap')) {
          throw new Error('⚠️ تعارض في الموعد (GiST Exclusion): يوجد موعد آخر محجوز في نفس القاعة / المذبح خلال هذه الفترة الزمنية.');
        }
        throw new Error(window.ChurchSupabase.mapErrorMessage(error));
      }

      window.ChurchSupabase.showToast(`تم إنشاء الموعد الجديد بنجاح #${data.id}`, 'success');
      closeModal('modal-create-slot');
      await loadSlots();
    } catch (e) {
      window.ChurchSupabase.showToast(e.message, 'error');
    } finally {
      btn.disabled = false;
      btn.innerHTML = '<span>حفظ الموعد</span>';
    }
  }

  /**
   * Announcements & Alt-Text Validation
   */
  async function loadAnnouncements() {
    const client = window.ChurchSupabase.getClient();
    const { data: annData, error } = await client
      .from('announcements')
      .select('*')
      .order('id', { ascending: false });

    if (error) {
      console.warn('Error loading announcements:', error);
      return;
    }

    state.announcements = annData || [];
    renderAnnouncements();
  }

  function renderAnnouncements() {
    const tbody = document.getElementById('tbody-announcements');
    if (!tbody) return;

    if (state.announcements.length === 0) {
      tbody.innerHTML = `
        <tr>
          <td colspan="7" style="text-align:center; padding:20px;" class="text-muted">
            لا توجد إعلانات منشورة أو مسودات حالياً
          </td>
        </tr>
      `;
      return;
    }

    let html = '';
    state.announcements.forEach(a => {
      const isPublished = Boolean(a.published_at);
      const pubDate = isPublished ? formatDate(a.published_at) : 'غير منشور (مسودة)';
      const roleStr = a.target_role || 'العامة';

      html += `
        <tr>
          <td><strong class="font-mono" style="color:var(--gold);">#${a.id}</strong></td>
          <td><strong>${a.title_ar}</strong></td>
          <td style="max-width:280px; font-size:0.85rem; color:var(--text-secondary);">${a.body_ar}</td>
          <td><span class="badge badge-role-user">${roleStr}</span></td>
          <td style="font-size:0.82rem;">${pubDate}</td>
          <td>
            <span class="badge ${isPublished ? 'badge-confirmed' : 'badge-pending'}">
              ${isPublished ? 'منشور' : 'مسودة'}
            </span>
          </td>
          <td style="text-align:center;">
            <button onclick="window.AdminApp.handlePublishAnnouncement(${a.id})" class="btn btn-xs ${isPublished ? 'btn-outline' : 'btn-primary'}" style="font-size:0.75rem;">
              <span>${isPublished ? 'إعادة نشر' : 'نشر الآن (Publish)'}</span>
            </button>
          </td>
        </tr>
      `;
    });

    tbody.innerHTML = html;
  }

  function toggleAnnouncementForm() {
    const box = document.getElementById('announcement-form-box');
    if (!box) return;
    box.style.display = box.style.display === 'none' ? 'block' : 'none';
  }

  async function handleCreateAnnouncement() {
    const title = (document.getElementById('ann-title').value || '').trim();
    const role = document.getElementById('ann-role').value || null;
    const body = (document.getElementById('ann-body').value || '').trim();

    if (!title || !body) {
      window.ChurchSupabase.showToast('يرجى إدخال عنوان الإعلان ونصه', 'warning');
      return;
    }

    const client = window.ChurchSupabase.getClient();
    const { data, error } = await client
      .from('announcements')
      .insert({
        title_ar: title,
        body_ar: body,
        target_role: role,
        published_at: null, // Draft
        tenant_id: 1
      })
      .select()
      .single();

    if (error) {
      window.ChurchSupabase.showToast('تعذر حفظ الإعلان: ' + error.message, 'error');
      return;
    }

    window.ChurchSupabase.showToast(`تم حفظ مسودة الإعلان #${data.id} بنجاح`, 'success');
    toggleAnnouncementForm();
    await loadAnnouncements();
  }

  async function handlePublishAnnouncement(announcementId) {
    window.ChurchSupabase.showToast(`جاري فحص إتاحة الوصول ونشر الإعلان #${announcementId}...`, 'info', 1500);

    const { error, messageAr } = await window.ChurchSupabase.invokeRpc('publish_announcement', {
      p_id: announcementId
    });

    if (error) {
      if (error.code === 'P0001' || error.message.includes('ALT_TEXT_REQUIRED')) {
        window.ChurchSupabase.showToast('⚠️ تم إيقاف النشر: يتطلب الإعلان نصاً بديلاً (alt_text_ar) للصور المرتبطة وفقاً لمعايير إتاحة الوصول.', 'error', 6000);
        return;
      }
      window.ChurchSupabase.showToast(messageAr || 'تعذر نشر الإعلان', 'error');
      return;
    }

    window.ChurchSupabase.showToast(`تم نشر الإعلان #${announcementId} بنجاح واجتياز فحص إتاحة الوصول!`, 'success');
    await loadAnnouncements();
  }

  /**
   * =========================================================================
   * TAB 4: ENCRYPTED COMPLAINTS & DECRYPTION
   * =========================================================================
   */
  async function loadComplaints(silent = false) {
    const client = window.ChurchSupabase.getClient();
    const { data: compData, error } = await client
      .from('v_complaints')
      .select('*')
      .order('id', { ascending: false });

    if (error) {
      if (!silent) window.ChurchSupabase.showToast('تعذر تحميل الشكاوى: ' + error.message, 'error');
      return;
    }

    state.complaints = compData || [];
    renderComplaints();
  }

  function filterComplaints() {
    renderComplaints();
  }

  function renderComplaints() {
    const tbody = document.getElementById('tbody-complaints');
    if (!tbody) return;

    const filterStatus = document.getElementById('filter-complaint-status').value;
    let filtered = state.complaints;

    if (filterStatus !== 'ALL') {
      filtered = filtered.filter(c => c.status === filterStatus);
    }

    if (filtered.length === 0) {
      tbody.innerHTML = `
        <tr>
          <td colspan="7" style="text-align:center; padding:30px;" class="text-muted">
            لا توجد شكاوى مسجلة في هذا التصنيف
          </td>
        </tr>
      `;
      return;
    }

    let html = '';
    filtered.forEach(c => {
      const assignedLabel = c.assigned_to ? `<span class="badge badge-role-admin">مُسندة #${c.assigned_to.slice(0, 6)}</span>` : '<span class="text-muted">غير مسند</span>';
      
      html += `
        <tr>
          <td><strong class="font-mono" style="color:var(--gold);">#${c.id}</strong></td>
          <td><strong style="color:var(--text-primary);">${c.category || 'عامة'}</strong></td>
          <td><span class="font-mono text-xs text-muted">${c.user_id ? c.user_id.slice(0, 8) + '...' : '--'}</span></td>
          <td>${getComplaintBadgeHtml(c.status)}</td>
          <td>${assignedLabel}</td>
          <td style="font-size:0.82rem;">${formatDate(c.created_at)}</td>
          <td style="text-align:center;">
            <div class="action-btn-group" style="justify-content:center;">
              <button onclick="window.AdminApp.handleDecryptComplaint(${c.id}, '${c.category || 'عامة'}')" class="btn btn-xs btn-primary" title="فك التشفير وقراءة نص الشكوى">
                <span>🔓 فك التشفير</span>
              </button>
              ${c.status !== 'RESOLVED' ? `
                <button onclick="window.AdminApp.updateComplaintStatus(${c.id}, 'RESOLVED')" class="btn btn-xs btn-success" title="تحديد كتم الحل">
                  <span>✔️ تم الحل</span>
                </button>
              ` : ''}
              ${c.status === 'NEW' ? `
                <button onclick="window.AdminApp.updateComplaintStatus(${c.id}, 'ASSIGNED')" class="btn btn-xs btn-outline" title="إسناد للمتابعة">
                  <span>👤 إسناد</span>
                </button>
              ` : ''}
            </div>
          </td>
        </tr>
      `;
    });

    tbody.innerHTML = html;
  }

  async function handleDecryptComplaint(complaintId, category) {
    window.ChurchSupabase.showToast(`جاري استرجاع مفتاح Vault وفك تشفير الشكوى #${complaintId}...`, 'info', 1500);

    const { data: decryptedText, error, messageAr } = await window.ChurchSupabase.invokeRpc('decrypt_complaint', {
      p_complaint_id: complaintId
    });

    if (error) {
      window.ChurchSupabase.showToast(messageAr || 'تعذر فك تشفير الشكوى (تأكد من توفر COMPLAINTS_KEY في Vault)', 'error');
      return;
    }

    document.getElementById('dec-complaint-id').textContent = `#${complaintId}`;
    document.getElementById('dec-complaint-category').textContent = category;
    document.getElementById('dec-complaint-text').textContent = decryptedText || '(نص الشكوى فارغ)';
    openModal('modal-decrypt-complaint');
  }

  async function updateComplaintStatus(complaintId, newStatus) {
    window.ChurchSupabase.showToast(`جاري تحديث حالة الشكوى إلى ${newStatus}...`, 'info', 1500);

    const adminClient = window.ChurchSupabase.getAdminClient();
    const { error } = await adminClient
      .from('complaints')
      .update({ status: newStatus, updated_at: new Date().toISOString() })
      .eq('id', complaintId);

    if (error) {
      window.ChurchSupabase.showToast('تعذر تحديث حالة الشكوى: ' + error.message, 'error');
      return;
    }

    window.ChurchSupabase.showToast(`تم تحديث حالة الشكوى #${complaintId} إلى ${newStatus}`, 'success');
    await loadComplaints();
    updateTopStats();
  }

  /**
   * =========================================================================
   * TAB 5: OUTBOX QUEUE INSPECTOR
   * =========================================================================
   */
  async function loadOutboxEvents(silent = false) {
    const client = window.ChurchSupabase.getClient();

    // 1. Fetch failed outbox view
    const { data: failedData } = await client
      .from('v_failed_outbox_events')
      .select('*')
      .order('id', { ascending: false });
    state.failedOutbox = failedData || [];

    // 2. Fetch full outbox stream
    const { data: outboxData, error } = await client
      .from('event_outbox')
      .select('*')
      .order('id', { ascending: false })
      .limit(40);

    if (error) {
      if (!silent) console.warn('Error loading outbox:', error);
      return;
    }

    state.outbox = outboxData || [];
    renderOutbox();
  }

  function renderOutbox() {
    // 1. Render Failed Box
    const failedSec = document.getElementById('failed-outbox-section');
    const failedTbody = document.getElementById('tbody-failed-outbox');

    if (state.failedOutbox.length > 0) {
      failedSec.style.display = 'block';
      let fHtml = '';
      state.failedOutbox.forEach(fe => {
        fHtml += `
          <tr>
            <td><strong class="font-mono text-gold">#${fe.id}</strong></td>
            <td><span class="badge ${fe.handler_type === 'WHATSAPP' ? 'outbox-badge-whatsapp' : 'outbox-badge-refund'}">${fe.handler_type}</span></td>
            <td><span class="font-mono">${fe.recipient_phone || fe.payload?.phone || '--'}</span></td>
            <td><code>${fe.template_name || fe.payload?.template_name || '--'}</code></td>
            <td style="color:#f87171; max-width:260px; font-size:0.75rem; word-break:break-all;">${fe.last_error || 'Unknown error'}</td>
            <td><span class="badge badge-cancelled">${fe.attempts} محاولات</span></td>
            <td>
              <button onclick="window.AdminApp.handleResendOutboxEvent(${fe.id})" class="btn btn-xs btn-warning" style="font-size:0.75rem;">
                <span>🔄 إعادة الإرسال</span>
              </button>
            </td>
          </tr>
        `;
      });
      failedTbody.innerHTML = fHtml;
    } else {
      failedSec.style.display = 'none';
    }

    // 2. Render Full Outbox Table
    const tbody = document.getElementById('tbody-outbox');
    if (!tbody) return;

    if (state.outbox.length === 0) {
      tbody.innerHTML = `
        <tr>
          <td colspan="7" style="text-align:center; padding:30px;" class="text-muted">
            صندوق الإرسال فارغ حالياً
          </td>
        </tr>
      `;
      return;
    }

    let html = '';
    state.outbox.forEach(ev => {
      const handlerClass = ev.handler_type === 'WHATSAPP' ? 'outbox-badge-whatsapp' : (ev.handler_type === 'PAYMOB_REFUND' ? 'outbox-badge-refund' : 'outbox-badge-fcm');
      const payloadSummary = JSON.stringify(ev.payload || {}).slice(0, 90) + (JSON.stringify(ev.payload || {}).length > 90 ? '...' : '');

      html += `
        <tr>
          <td><strong class="font-mono text-gold">#${ev.id}</strong></td>
          <td><span class="badge ${handlerClass}">${ev.handler_type}</span></td>
          <td><div class="code-preview-box" style="padding:4px 8px; font-size:0.75rem; max-height:50px;">${payloadSummary}</div></td>
          <td>${getOutboxBadgeHtml(ev.status)}</td>
          <td><span class="badge badge-outline">${ev.attempts || 0}</span></td>
          <td style="font-size:0.8rem;">${formatDate(ev.created_at)}</td>
          <td style="color:#f87171; font-size:0.75rem; max-width:200px; word-break:break-all;">${ev.last_error || '--'}</td>
        </tr>
      `;
    });

    tbody.innerHTML = html;
  }

  async function handleResendOutboxEvent(eventId) {
    window.ChurchSupabase.showToast(`جاري إعادة تعيين الحدث #${eventId} إلى PENDING...`, 'info', 1500);

    const { data, error, messageAr } = await window.ChurchSupabase.invokeRpc('admin_resend_outbox_event', {
      p_event_id: eventId
    });

    if (error) {
      window.ChurchSupabase.showToast(messageAr || 'تعذر إعادة جدولة الحدث', 'error');
      return;
    }

    window.ChurchSupabase.showToast(`تمت إعادة تعيين الحدث #${eventId} في الصندوق بنجاح (PENDING)`, 'success');
    await loadOutboxEvents();
    updateTopStats();
  }

  async function handleTriggerEventDispatcher() {
    const btn = document.getElementById('btn-trigger-dispatcher');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> <span>جاري تفريغ الصندوق...</span>';

    try {
      const url = `${window.ChurchSupabase.CONFIG.url}/functions/v1/event-dispatcher`;
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${window.ChurchSupabase.CONFIG.serviceRoleKey}`
        }
      });

      const json = await res.json();
      console.log('[AdminApp] Event Dispatcher Response:', json);

      const handledCount = json.handled ?? 0;
      window.ChurchSupabase.showToast(`⚡ تم تشغيل موزع الأحداث بنجاح! تم معالجة وإرسال ${handledCount} حدث.`, 'success', 4000);
      
      await Promise.all([loadOutboxEvents(), loadBookings(true)]);
      updateTopStats();
    } catch (e) {
      window.ChurchSupabase.showToast('فشل استدعاء موزع الأحداث: ' + e.message, 'error');
    } finally {
      btn.disabled = false;
      btn.innerHTML = '<span>⚡ تشغيل موزع الأحداث (Trigger Dispatcher)</span>';
    }
  }

  /**
   * =========================================================================
   * TAB 6: PAYMENT PROOFS REVIEW QUEUE
   * =========================================================================
   */
  async function loadPendingProofs(silent = false) {
    const client = window.ChurchSupabase.getClient();
    const { data: proofsData, error } = await client
      .from('payment_proofs')
      .select('*')
      .order('id', { ascending: false });

    if (error) {
      if (!silent) console.warn('Error loading payment proofs:', error);
      return;
    }

    state.proofs = proofsData || [];
    renderPendingProofs();
  }

  function filterProofs() {
    renderPendingProofs();
  }

  function renderPendingProofs() {
    const tbody = document.getElementById('tbody-proofs');
    if (!tbody) return;

    const filterEl = document.getElementById('filter-proof-status');
    const filter = filterEl ? filterEl.value : 'PENDING';

    let list = state.proofs;
    if (filter !== 'ALL') {
      list = list.filter(p => p.status === filter);
    }

    if (list.length === 0) {
      tbody.innerHTML = `
        <tr>
          <td colspan="10" style="text-align:center; padding:30px;" class="text-muted">
            لا توجد إثباتات دفع مطابقة للفلاتر المحددة
          </td>
        </tr>
      `;
      return;
    }

    const channelMap = {
      'VODAFONE_CASH': 'فودافون كاش',
      'INSTAPAY': 'إنستاباي',
      'CASH': 'نقداً'
    };

    const statusBadgeMap = {
      'PENDING': '<span class="badge badge-pending-payment">قيد المراجعة</span>',
      'APPROVED': '<span class="badge badge-confirmed">مقبول (APPROVED)</span>',
      'REJECTED': '<span class="badge badge-cancelled">مرفوض (REJECTED)</span>'
    };

    let html = '';
    list.forEach(p => {
      const channelLabel = channelMap[p.channel] || p.channel;
      const statusHtml = statusBadgeMap[p.status] || `<span class="badge">${p.status}</span>`;
      const dateStr = formatDate(p.created_at);

      let imageHtml = '<span class="text-xs text-muted">بدون مرفق</span>';
      if (p.image_path) {
        const client = window.ChurchSupabase.getClient();
        const { data: { publicUrl } } = client.storage.from('payment-proofs').getPublicUrl(p.image_path);
        imageHtml = `<a href="${publicUrl}" target="_blank" class="btn btn-xs btn-outline" style="font-size:0.75rem;">🖼️ عرض الإشعار</a>`;
      }

      let actionsHtml = '--';
      if (p.status === 'PENDING') {
        actionsHtml = `
          <div class="action-btn-group" style="justify-content:center;">
            <button onclick="window.AdminApp.approveProof(${p.id}, '${p.channel}', ${p.booking_id}, ${p.amount_claimed})" class="btn btn-xs btn-success" title="اعتماد إثبات الدفع وتأكيد الحجز">
              <span>✅ قبول</span>
            </button>
            <button onclick="window.AdminApp.openRejectProofModal(${p.id}, ${p.booking_id}, ${p.amount_claimed})" class="btn btn-xs btn-outline" style="color:var(--danger); border-color:var(--danger-border);" title="رفض إثبات الدفع مع توضيح السبب">
              <span>❌ رفض</span>
            </button>
          </div>
        `;
      }

      html += `
        <tr>
          <td><strong class="font-mono text-gold">#${p.id}</strong></td>
          <td><strong class="font-mono">#${p.booking_id}</strong></td>
          <td><span class="badge badge-open">${channelLabel}</span></td>
          <td><span class="font-mono text-xs">${p.sender_phone || '--'}</span></td>
          <td><span class="font-mono text-xs">${p.reference_number || '--'}</span></td>
          <td><strong>${p.amount_claimed} ج.م</strong></td>
          <td>${imageHtml}</td>
          <td style="font-size:0.8rem;">${dateStr}</td>
          <td>${statusHtml}</td>
          <td style="text-align:center;">${actionsHtml}</td>
        </tr>
      `;
    });

    tbody.innerHTML = html;
  }

  async function approveProof(proofId, channel, bookingId, amount) {
    if (channel === 'CASH') {
      state.currentActionProofId = proofId;
      const textEl = document.getElementById('cash-proof-id-text');
      if (textEl) textEl.textContent = `#${proofId} (حجز #${bookingId})`;
      const noteInput = document.getElementById('cash-collector-note');
      if (noteInput) noteInput.value = '';
      openModal('modal-approve-cash');
      return;
    }

    const confirm = window.confirm(`هل أنت متأكد من قبول إثبات الدفع #${proofId} للحجز #${bookingId} بمبلغ ${amount} ج.م؟`);
    if (!confirm) return;

    window.ChurchSupabase.showToast(`جاري قبول واعتماد الإثبات #${proofId}...`, 'info', 2000);

    try {
      const { error, messageAr } = await window.ChurchSupabase.invokeRpc('approve_payment_proof', {
        p_proof_id: proofId
      });

      if (error) {
        throw new Error(messageAr || 'تعذر اعتماد إثبات الدفع');
      }

      window.ChurchSupabase.showToast(`تم قبول إثبات الدفع #${proofId} وتأكيد الحجز بنجاح!`, 'success');
      await Promise.all([loadPendingProofs(), loadBookings(true), loadOutboxEvents(true)]);
      updateTopStats();
    } catch (e) {
      window.ChurchSupabase.showToast(e.message, 'error');
    }
  }

  async function executeApproveCashProof() {
    const proofId = state.currentActionProofId;
    if (!proofId) return;

    const note = (document.getElementById('cash-collector-note').value || 'استلام نقدي بالخزينة').trim();
    const btn = document.getElementById('btn-confirm-approve-cash');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> <span>جاري الاعتماد...</span>';

    try {
      const { error, messageAr } = await window.ChurchSupabase.invokeRpc('approve_payment_proof', {
        p_proof_id: proofId,
        p_collector_note: note
      });

      if (error) {
        throw new Error(messageAr || 'تعذر اعتماد الدفع النقدي');
      }

      window.ChurchSupabase.showToast(`تم اعتماد استلام النقدية للإثبات #${proofId} بنجاح!`, 'success');
      closeModal('modal-approve-cash');
      await Promise.all([loadPendingProofs(), loadBookings(true), loadOutboxEvents(true)]);
      updateTopStats();
    } catch (e) {
      window.ChurchSupabase.showToast(e.message, 'error');
    } finally {
      btn.disabled = false;
      btn.innerHTML = '<span>تأكيد الاستلام والاعتماد</span>';
    }
  }

  function openRejectProofModal(proofId, bookingId, amount) {
    state.currentActionProofId = proofId;
    state.currentActionProofBookingId = bookingId;
    state.currentActionProofAmount = amount;

    const idEl = document.getElementById('reject-proof-id-text');
    const bookEl = document.getElementById('reject-proof-booking-id-text');
    const amtEl = document.getElementById('reject-proof-amount-text');

    if (idEl) idEl.textContent = `#${proofId}`;
    if (bookEl) bookEl.textContent = `#${bookingId}`;
    if (amtEl) amtEl.textContent = amount;

    openModal('modal-reject-proof');
  }

  async function executeRejectProof() {
    const proofId = state.currentActionProofId;
    if (!proofId) return;

    const reasonSelect = document.getElementById('reject-proof-reason-select');
    const reasonCode = reasonSelect ? reasonSelect.value : 'BAD_REQUEST';

    const btn = document.getElementById('btn-confirm-reject-proof');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> <span>جاري الرفض...</span>';

    try {
      const { error, messageAr } = await window.ChurchSupabase.invokeRpc('reject_payment_proof', {
        p_proof_id: proofId,
        p_reason_code: reasonCode
      });

      if (error) {
        throw new Error(messageAr || 'تعذر رفض إثبات الدفع');
      }

      window.ChurchSupabase.showToast(`تم رفض إثبات الدفع #${proofId}. يمكن للمخدوم إعادة إرسال إثبات جديد`, 'info');
      closeModal('modal-reject-proof');
      await loadPendingProofs();
      updateTopStats();
    } catch (e) {
      window.ChurchSupabase.showToast(e.message, 'error');
    } finally {
      btn.disabled = false;
      btn.innerHTML = '<span>تأكيد رفض الإثبات</span>';
    }
  }

  /**
   * =========================================================================
   * TAB SWITCHING & MODAL HELPERS
   * =========================================================================
   */
  function switchTab(tabId) {
    state.activeTab = tabId;

    // Toggle button active state
    document.querySelectorAll('.tab-btn').forEach(btn => {
      btn.classList.toggle('active', btn.getAttribute('data-tab') === tabId);
    });

    // Toggle tab contents
    document.querySelectorAll('.tab-content').forEach(content => {
      content.style.display = content.id === tabId ? 'block' : 'none';
    });

    // Scroll to top of content smoothly
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function openModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
      modal.classList.add('active');
    }
  }

  function closeModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
      modal.classList.remove('active');
    }
  }

  function closeAllModals() {
    document.querySelectorAll('.modal-backdrop.active').forEach(m => m.classList.remove('active'));
  }

  // Public Interface attached to window.AdminApp
  window.AdminApp = {
    init,
    checkAuthAndRole,
    handleVerifyPin,
    handleSetPin,
    handlePasswordLogin,
    switchAccount,
    handleLogout,
    refreshAllData,
    toggleAutoRefresh,
    switchTab,
    openModal,
    closeModal,
    // Tab 1: Bookings
    loadBookings,
    filterBookings,
    confirmBooking,
    completeBooking,
    openCancelModal,
    executeCancelBooking,
    openEmergencyOverrideModal,
    executeEmergencyOverride,
    // Tab 2: Manual Booking
    loadSlotsForService,
    onSlotSelected,
    handleManualBooking,
    // Tab 3: Slots & Announcements
    loadSlots,
    toggleSlotStatus,
    openCreateSlotModal,
    handleCreateSlot,
    toggleAnnouncementForm,
    handleCreateAnnouncement,
    handlePublishAnnouncement,
    // Tab 4: Complaints
    loadComplaints,
    filterComplaints,
    handleDecryptComplaint,
    updateComplaintStatus,
    // Tab 5: Outbox
    loadOutboxEvents,
    handleResendOutboxEvent,
    handleTriggerEventDispatcher,
    // Tab 6: Payment Proofs
    loadPendingProofs,
    filterProofs,
    approveProof,
    executeApproveCashProof,
    openRejectProofModal,
    executeRejectProof
  };

  // Bootstrap when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

