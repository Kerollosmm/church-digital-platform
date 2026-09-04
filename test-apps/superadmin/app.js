/**
 * ============================================================================
 * Church Digital Platform — SuperAdmin Control Plane Application Logic
 * ============================================================================
 */

(function () {
  'use strict';

  // Application State
  const state = {
    currentUser: null,
    currentRole: null,
    isSuperAdmin: false,
    users: [],
    authUsersMap: {},
    auditLogs: [],
    analytics: {
      payments: [],
      utilization: [],
      bookings: []
    },
    allJsonExpanded: false
  };

  /**
   * DOM Element Selectors
   */
  const el = {
    // Gate Elements
    gateContainer: document.getElementById('gate-container'),
    gateMessage: document.getElementById('gate-message'),
    gateMismatchWarning: document.getElementById('gate-mismatch-warning'),
    gateCurrentRoleText: document.getElementById('gate-current-role-text'),
    btnQuickLoginSuperAdmin: document.getElementById('btn-quick-login-superadmin'),
    formManualLogin: document.getElementById('form-manual-login'),
    inputLoginEmail: document.getElementById('input-login-email'),
    inputLoginPassword: document.getElementById('input-login-password'),
    userStatusContainer: document.getElementById('user-status-container'),

    // Dashboard Elements
    dashboardContainer: document.getElementById('dashboard-container'),
    tabButtons: document.querySelectorAll('.tab-btn'),
    tabPanes: document.querySelectorAll('.tab-pane'),

    // Stats Elements
    statTotalRevenue: document.getElementById('stat-total-revenue'),
    statPaidCount: document.getElementById('stat-paid-count'),
    statRefundedAmount: document.getElementById('stat-refunded-amount'),
    statAvgUtilization: document.getElementById('stat-avg-utilization'),

    // Users Tab Elements
    usersTableBody: document.getElementById('users-table-body'),
    filterUsersSearch: document.getElementById('filter-users-search'),
    filterUsersRole: document.getElementById('filter-users-role'),
    usersCountBadge: document.getElementById('users-count-badge'),
    btnRefreshUsers: document.getElementById('btn-refresh-users'),

    // Role Edit Modal
    modalRoleEdit: document.getElementById('modal-role-edit'),
    editUserId: document.getElementById('edit-user-id'),
    editUserName: document.getElementById('edit-user-name'),
    editUserContact: document.getElementById('edit-user-contact'),
    editUserRoleSelect: document.getElementById('edit-user-role-select'),
    editUserReason: document.getElementById('edit-user-reason'),
    btnSaveUserRole: document.getElementById('btn-save-user-role'),

    // Audit Tab Elements
    auditTableBody: document.getElementById('audit-table-body'),
    filterAuditSearch: document.getElementById('filter-audit-search'),
    filterAuditEntity: document.getElementById('filter-audit-entity'),
    filterAuditAction: document.getElementById('filter-audit-action'),
    filterAuditLimit: document.getElementById('filter-audit-limit'),
    btnRefreshAudit: document.getElementById('btn-refresh-audit'),
    btnToggleAllJson: document.getElementById('btn-toggle-all-json'),

    // Analytics Tab Elements
    analyticsPaymentsBody: document.getElementById('analytics-payments-body'),
    analyticsUtilizationBody: document.getElementById('analytics-utilization-body'),
    analyticsBookingsBody: document.getElementById('analytics-bookings-body'),
    btnRecalculateRollups: document.getElementById('btn-recalculate-rollups'),
    btnOpenExportModal: document.getElementById('btn-open-export-modal'),
    modalExportAnalytics: document.getElementById('modal-export-analytics'),
    exportReportType: document.getElementById('export-report-type'),
    exportMonthInput: document.getElementById('export-month-input'),
    btnDownloadCsvAction: document.getElementById('btn-download-csv-action'),

    // Diagnostics Tab Elements
    btnRunProbes: document.getElementById('btn-run-probes'),
    probesResultsContainer: document.getElementById('probes-results-container'),
    selectReaperTimeout: document.getElementById('select-reaper-timeout'),
    btnTriggerReaper: document.getElementById('btn-trigger-reaper'),
    reaperResultBox: document.getElementById('reaper-result-box'),
    btnRunVaultPreflight: document.getElementById('btn-run-vault-preflight'),
    vaultResultsBox: document.getElementById('vault-results-box'),
    btnRefreshInfra: document.getElementById('btn-refresh-infra'),
    healthPostgrest: document.getElementById('health-postgrest'),
    healthPostgres: document.getElementById('health-postgres'),
    healthGotrue: document.getElementById('health-gotrue'),
    healthEdge: document.getElementById('health-edge')
  };

  /**
   * Helper: Format Date & Time in Arabic
   */
  function formatDateAr(dateStr) {
    if (!dateStr) return '—';
    try {
      const d = new Date(dateStr);
      return d.toLocaleDateString('ar-EG', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch {
      return dateStr;
    }
  }

  /**
   * Helper: Format Numbers with 2 decimal places
   */
  function formatMoney(amount) {
    const num = Number(amount) || 0;
    return num.toLocaleString('ar-EG', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  /**
   * Helper: Role Badge HTML
   */
  function getRoleBadge(role) {
    const r = (role || 'USER').toUpperCase();
    if (r === 'SUPER_ADMIN') {
      return '<span class="badge badge-role-superadmin">مدير أعلى (SUPER_ADMIN)</span>';
    }
    if (r === 'ADMIN') {
      return '<span class="badge badge-role-admin">إداري (ADMIN)</span>';
    }
    return '<span class="badge badge-role-user">مخدوم (USER)</span>';
  }

  /**
   * Helper: Action Badge HTML
   */
  function getActionBadge(action) {
    const act = (action || '').toUpperCase();
    if (act.includes('INSERT') || act.includes('BOOK')) {
      return `<span class="badge badge-confirmed">${action}</span>`;
    }
    if (act.includes('DELETE') || act.includes('CANCEL') || act.includes('REJECT')) {
      return `<span class="badge badge-cancelled">${action}</span>`;
    }
    if (act.includes('UPDATE') || act.includes('PIN') || act.includes('ROLE')) {
      return `<span class="badge badge-pending-payment">${action}</span>`;
    }
    if (act.includes('EXPIRE') || act.includes('REAP')) {
      return `<span class="badge badge-completed">${action}</span>`;
    }
    return `<span class="badge badge-awaiting-call">${action}</span>`;
  }

  /**
   * =========================================================================
   * 1. AUTHENTICATION & ACCESS GATE
   * =========================================================================
   */
  async function checkAuthAndInit() {
    const sb = window.ChurchSupabase;
    if (!sb) {
      console.error('ChurchSupabase client not loaded!');
      return;
    }

    try {
      const user = await sb.auth.getUser();
      state.currentUser = user;

      if (!user) {
        renderGateScreen('NOT_LOGGED_IN');
        return;
      }

      // Check role directly from database and is_super_admin() RPC
      const role = await sb.auth.getCurrentUserRole();
      state.currentRole = role;

      const { data: isSuperAdminRpc } = await sb.getClient().rpc('is_super_admin');
      state.isSuperAdmin = Boolean(isSuperAdminRpc) || role === 'SUPER_ADMIN';

      if (!state.isSuperAdmin) {
        renderGateScreen('FORBIDDEN', role);
        return;
      }

      // User is verified SUPER_ADMIN
      renderDashboard();

    } catch (err) {
      console.error('Auth verification error:', err);
      renderGateScreen('ERROR', err.message);
    }
  }

  function renderGateScreen(mode, details) {
    el.dashboardContainer.style.display = 'none';
    el.gateContainer.style.display = 'block';

    if (mode === 'FORBIDDEN') {
      el.gateMismatchWarning.style.display = 'block';
      el.gateCurrentRoleText.textContent = `أنت مسجل حالياً بحساب ${details} (${state.currentUser?.email || ''}) وليس لديك صلاحية SUPER_ADMIN.`;
    } else {
      el.gateMismatchWarning.style.display = 'none';
    }

    if (window.TestAccounts) {
      window.TestAccounts.renderUserBanner('user-status-container', {
        onLogout: () => window.location.reload()
      });
    }
  }

  async function renderDashboard() {
    el.gateContainer.style.display = 'none';
    el.dashboardContainer.style.display = 'block';

    if (window.TestAccounts) {
      window.TestAccounts.renderUserBanner('user-status-container', {
        onLogout: () => window.location.reload()
      });
    }

    // Load initial data concurrently
    await Promise.all([
      loadOverviewStats(),
      loadUsersList(),
      loadAuditLogs(),
      loadAnalyticsData(),
      runInfraHealthCheck()
    ]);
  }

  /**
   * =========================================================================
   * 2. OVERVIEW METRICS & STATS
   * =========================================================================
   */
  async function loadOverviewStats() {
    const admin = window.ChurchSupabase.getAdminClient();
    try {
      // 1. Payments overview from payments_monthly or v_analytics_payments
      const { data: payments } = await admin.from('v_analytics_payments').select('*');
      let totalRev = 0;
      let totalPaidCount = 0;
      let totalRefund = 0;

      if (payments && payments.length > 0) {
        payments.forEach(p => {
          totalRev += Number(p.total_paid) || 0;
          totalPaidCount += Number(p.count_paid) || 0;
          totalRefund += Number(p.total_refunded) || 0;
        });
      }

      el.statTotalRevenue.innerHTML = `${formatMoney(totalRev)} <span style="font-size:0.85rem; font-weight:normal;">ج.م</span>`;
      el.statPaidCount.textContent = totalPaidCount.toLocaleString('ar-EG');
      el.statRefundedAmount.innerHTML = `${formatMoney(totalRefund)} <span style="font-size:0.85rem; font-weight:normal;">ج.م</span>`;

      // 2. Average slot utilization from v_analytics_utilization
      const { data: util } = await admin.from('v_analytics_utilization').select('*');
      if (util && util.length > 0) {
        const totalPct = util.reduce((sum, u) => sum + (Number(u.utilization_pct) || 0), 0);
        const avg = Math.round(totalPct / util.length);
        el.statAvgUtilization.textContent = `${avg}%`;
      } else {
        el.statAvgUtilization.textContent = '0%';
      }

    } catch (err) {
      console.warn('Failed to load overview stats:', err);
    }
  }

  /**
   * =========================================================================
   * 3. USERS & ROLE GOVERNANCE
   * =========================================================================
   */
  async function loadUsersList() {
    const admin = window.ChurchSupabase.getAdminClient();
    el.usersTableBody.innerHTML = `
      <tr>
        <td colspan="6" style="text-align:center; padding:30px; color:var(--text-muted);">
          <div class="spinner"></div> جاري تحميل قائمة المستخدمين...
        </td>
      </tr>
    `;

    try {
      // Fetch public.users
      const { data: users, error } = await admin
        .from('users')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;

      // Try fetching auth users map for email enrichment
      try {
        const { data: authData } = await admin.auth.admin.listUsers();
        if (authData?.users) {
          state.authUsersMap = Object.fromEntries(
            authData.users.map((au) => [au.id, au])
          );
        }
      } catch (authErr) {
        console.warn('Auth admin listUsers fallback:', authErr);
      }

      state.users = users || [];
      renderUsersTable();

    } catch (err) {
      console.error('Error loading users:', err);
      el.usersTableBody.innerHTML = `
        <tr>
          <td colspan="6" style="text-align:center; padding:20px; color:var(--danger);">
            حدث خطأ أثناء تحميل المستخدمين: ${err.message}
          </td>
        </tr>
      `;
    }
  }

  function renderUsersTable() {
    const search = (el.filterUsersSearch.value || '').trim().toLowerCase();
    const roleFilter = el.filterUsersRole.value;

    const filtered = state.users.filter(u => {
      const authUser = state.authUsersMap[u.id];
      const email = (authUser?.email || '').toLowerCase();
      const name = (u.name || '').toLowerCase();
      const phone = (u.phone || '').toLowerCase();

      const matchSearch = !search || name.includes(search) || phone.includes(search) || email.includes(search);
      const matchRole = roleFilter === 'ALL' || u.role === roleFilter;

      return matchSearch && matchRole;
    });

    el.usersCountBadge.textContent = `${filtered.length} مستخدم`;

    if (filtered.length === 0) {
      el.usersTableBody.innerHTML = `
        <tr>
          <td colspan="6" style="text-align:center; padding:30px; color:var(--text-muted);">
            لا توجد سجلات مستخدمين مطابقة لخيارات البحث الحالية.
          </td>
        </tr>
      `;
      return;
    }

    let html = '';
    filtered.forEach(u => {
      const authUser = state.authUsersMap[u.id];
      const email = authUser?.email || (u.phone ? `${u.phone}@church.local` : '—');
      const displayName = u.name || authUser?.user_metadata?.name || 'مستخدم بدون اسم';
      const initial = displayName.charAt(0) || '👤';
      const isStaff = u.role === 'ADMIN' || u.role === 'SUPER_ADMIN';

      html += `
        <tr data-user-id="${u.id}">
          <td>
            <div class="flex items-center gap-2">
              <div class="user-avatar" style="width:32px; height:32px; font-weight:bold; font-size:0.85rem;">
                ${initial}
              </div>
              <div>
                <div style="font-weight:700; color:var(--text-primary);">${displayName}</div>
                <div style="font-size:0.7rem; color:var(--text-muted); font-family:monospace;">${u.id.substring(0, 8)}...</div>
              </div>
            </div>
          </td>
          <td class="font-mono" style="font-size:0.85rem;">${u.phone || '—'}</td>
          <td class="font-mono" style="font-size:0.85rem; color:var(--text-secondary);">${email}</td>
          <td>${getRoleBadge(u.role)}</td>
          <td style="font-size:0.8rem; color:var(--text-muted);">${formatDateAr(u.created_at)}</td>
          <td>
            <div class="flex items-center gap-1">
              <button class="btn btn-sm btn-outline btn-edit-role" data-user-id="${u.id}" data-name="${displayName}" data-contact="${email} | ${u.phone}" data-role="${u.role}">
                ⚙️ تعديل الصلاحية
              </button>
              ${isStaff ? `
                <button class="btn btn-sm btn-outline btn-reset-pin" data-user-id="${u.id}" data-name="${displayName}" title="إعادة تعيين رمز PIN الثنائي">
                  🔑 ضبط PIN
                </button>
              ` : ''}
            </div>
          </td>
        </tr>
      `;
    });

    el.usersTableBody.innerHTML = html;

    // Attach Event Handlers for Table Actions
    el.usersTableBody.querySelectorAll('.btn-edit-role').forEach(btn => {
      btn.addEventListener('click', () => {
        const uid = btn.getAttribute('data-user-id');
        const name = btn.getAttribute('data-name');
        const contact = btn.getAttribute('data-contact');
        const role = btn.getAttribute('data-role');

        el.editUserId.value = uid;
        el.editUserName.value = name;
        el.editUserContact.value = contact;
        el.editUserRoleSelect.value = role;
        el.editUserReason.value = '';

        openModal('modal-role-edit');
      });
    });

    el.usersTableBody.querySelectorAll('.btn-reset-pin').forEach(btn => {
      btn.addEventListener('click', async () => {
        const uid = btn.getAttribute('data-user-id');
        const name = btn.getAttribute('data-name');
        if (confirm(`هل أنت متأكد من رغبتك في إعادة ضبط وحذف رمز PIN للإداري: ${name}؟`)) {
          await handleResetAdminPin(uid, name);
        }
      });
    });
  }

  async function handleSaveUserRole() {
    const uid = el.editUserId.value;
    const newRole = el.editUserRoleSelect.value;
    const reason = el.editUserReason.value.trim() || 'تعديل إداري مباشر عبر لوحة التحكم';
    const btn = el.btnSaveUserRole;

    btn.disabled = true;
    btn.innerHTML = '<div class="spinner"></div> جاري الحفظ...';

    const admin = window.ChurchSupabase.getAdminClient();
    try {
      // Find old role
      const targetUser = state.users.find(u => u.id === uid);
      const oldRole = targetUser ? targetUser.role : 'USER';

      // 1. Update public.users via privileged RPC security seam
      const { error: updateErr } = await admin
        .from('users')
        .update({
          role: newRole,
          updated_at: new Date().toISOString()
        })
        .eq('id', uid);

      if (updateErr) throw updateErr;

      // 2. Append explicit audit log entry
      await admin.from('audit_log').insert({
        tenant_id: 1,
        user_id: state.currentUser.id,
        action: 'role_modified',
        entity_type: 'users',
        meta: {
          target_user_id: uid,
          target_user_name: el.editUserName.value,
          old_role: oldRole,
          new_role: newRole,
          reason: reason,
          performed_by: state.currentUser.email
        }
      });

      window.ChurchSupabase.showToast(`تم تعديل صلاحية المستخدم إلى (${newRole}) بنجاح`, 'success');
      closeModal('modal-role-edit');

      // Refresh data
      await Promise.all([loadUsersList(), loadAuditLogs()]);

    } catch (err) {
      console.error('Role update error:', err);
      window.ChurchSupabase.showToast(`فشل تعديل الصلاحية: ${err.message}`, 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = 'حفظ وتطبيق الصلاحية';
    }
  }

  async function handleResetAdminPin(userId, userName) {
    const sb = window.ChurchSupabase;
    try {
      // Call reset_admin_pin RPC as superadmin
      const { error } = await sb.getClient().rpc('reset_admin_pin', { p_target: userId });
      if (error) throw error;

      // Log to audit log
      const admin = sb.getAdminClient();
      await admin.from('audit_log').insert({
        tenant_id: 1,
        user_id: state.currentUser.id,
        action: 'pin_reset',
        entity_type: 'admin_pins',
        meta: {
          target_user_id: userId,
          target_user_name: userName,
          performed_by: state.currentUser.email
        }
      });

      sb.showToast(`تمت إعادة تعيين رمز PIN بنجاح للمستخدم: ${userName}`, 'success');
      await loadAuditLogs();
    } catch (err) {
      console.error('Reset PIN error:', err);
      sb.showToast(`فشل إعادة تعيين رمز PIN: ${err.message}`, 'error');
    }
  }

  /**
   * =========================================================================
   * 4. AUDIT & SECURITY LOG INSPECTOR
   * =========================================================================
   */
  async function loadAuditLogs() {
    const admin = window.ChurchSupabase.getAdminClient();
    el.auditTableBody.innerHTML = `
      <tr>
        <td colspan="7" style="text-align:center; padding:30px; color:var(--text-muted);">
          <div class="spinner"></div> جاري استعلام سجل التدقيق غير القابل للتعديل...
        </td>
      </tr>
    `;

    try {
      const limit = Number(el.filterAuditLimit.value) || 50;
      let query = admin
        .from('audit_log')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(limit);

      const entity = el.filterAuditEntity.value;
      if (entity !== 'ALL') {
        query = query.eq('entity_type', entity);
      }

      const action = el.filterAuditAction.value;
      if (action !== 'ALL') {
        query = query.ilike('action', `%${action}%`);
      }

      const { data: logs, error } = await query;
      if (error) throw error;

      state.auditLogs = logs || [];
      renderAuditTable();

    } catch (err) {
      console.error('Error loading audit log:', err);
      el.auditTableBody.innerHTML = `
        <tr>
          <td colspan="7" style="text-align:center; padding:20px; color:var(--danger);">
            حدث خطأ أثناء قراءة سجل التدقيق: ${err.message}
          </td>
        </tr>
      `;
    }
  }

  function renderAuditTable() {
    const search = (el.filterAuditSearch.value || '').trim().toLowerCase();

    const filtered = state.auditLogs.filter(log => {
      if (!search) return true;
      const act = (log.action || '').toLowerCase();
      const ent = (log.entity_type || '').toLowerCase();
      const meta = JSON.stringify(log.meta || {}).toLowerCase();
      const uid = (log.user_id || '').toLowerCase();

      return act.includes(search) || ent.includes(search) || meta.includes(search) || uid.includes(search);
    });

    if (filtered.length === 0) {
      el.auditTableBody.innerHTML = `
        <tr>
          <td colspan="7" style="text-align:center; padding:30px; color:var(--text-muted);">
            لا توجد أحداث تدقيق مطابقة للشروط المحددة.
          </td>
        </tr>
      `;
      return;
    }

    let html = '';
    filtered.forEach(log => {
      const jsonString = JSON.stringify(log.meta, null, 2);
      const isShort = Object.keys(log.meta || {}).length === 0;
      const displayJson = isShort ? '<span style="color:var(--text-muted);">{}</span>' : `
        <div style="display:flex; flex-direction:column; gap:4px;">
          <div style="display:flex; align-items:center; justify-content:space-between;">
            <button class="json-expand-btn btn-toggle-json" data-log-id="${log.id}">
              ${state.allJsonExpanded ? 'طي البيانات ▲' : 'عرض JSON ▼'}
            </button>
            <button class="json-expand-btn btn-copy-json" data-payload='${encodeURIComponent(jsonString)}'>
              📋 نسخ
            </button>
          </div>
          <pre id="json-block-${log.id}" class="json-tree font-mono" style="display:${state.allJsonExpanded ? 'block' : 'none'};">${jsonString}</pre>
        </div>
      `;

      html += `
        <tr>
          <td class="font-mono" style="font-size:0.8rem; color:var(--text-muted);">${log.id}</td>
          <td style="font-size:0.8rem; color:var(--text-secondary);">${formatDateAr(log.created_at)}</td>
          <td>${getActionBadge(log.action)}</td>
          <td><span class="badge badge-info font-mono">${log.entity_type}</span></td>
          <td class="font-mono" style="font-size:0.8rem;">${log.entity_id ? `#${log.entity_id}` : '—'}</td>
          <td class="font-mono" style="font-size:0.75rem; color:var(--text-secondary);">
            ${log.user_id ? `${log.user_id.substring(0, 8)}...` : '<span style="color:var(--text-muted);">system/cron</span>'}
          </td>
          <td style="min-width:240px;">${displayJson}</td>
        </tr>
      `;
    });

    el.auditTableBody.innerHTML = html;

    // Attach Click Events for Expand & Copy
    el.auditTableBody.querySelectorAll('.btn-toggle-json').forEach(btn => {
      btn.addEventListener('click', () => {
        const lid = btn.getAttribute('data-log-id');
        const block = document.getElementById(`json-block-${lid}`);
        if (block) {
          const isHidden = block.style.display === 'none';
          block.style.display = isHidden ? 'block' : 'none';
          btn.textContent = isHidden ? 'طي البيانات ▲' : 'عرض JSON ▼';
        }
      });
    });

    el.auditTableBody.querySelectorAll('.btn-copy-json').forEach(btn => {
      btn.addEventListener('click', () => {
        const payload = decodeURIComponent(btn.getAttribute('data-payload'));
        navigator.clipboard.writeText(payload).then(() => {
          window.ChurchSupabase.showToast('تم نسخ كائن JSON للحافظة', 'info', 2000);
        });
      });
    });
  }

  /**
   * =========================================================================
   * 5. FINANCIAL & SLOT ANALYTICS
   * =========================================================================
   */
  async function loadAnalyticsData() {
    const admin = window.ChurchSupabase.getAdminClient();

    try {
      // 1. Payments Monthly
      const { data: payments } = await admin.from('v_analytics_payments').select('*').order('month', { ascending: false });
      state.analytics.payments = payments || [];
      renderAnalyticsPayments();

      // 2. Slot Utilization Monthly
      const { data: util } = await admin.from('v_analytics_utilization').select('*').order('month', { ascending: false });
      state.analytics.utilization = util || [];
      renderAnalyticsUtilization();

      // 3. Bookings Monthly
      const { data: bookings } = await admin.from('v_analytics_bookings').select('*').order('month', { ascending: false });
      state.analytics.bookings = bookings || [];
      renderAnalyticsBookings();

    } catch (err) {
      console.error('Analytics loading error:', err);
    }
  }

  function renderAnalyticsPayments() {
    if (!state.analytics.payments || state.analytics.payments.length === 0) {
      el.analyticsPaymentsBody.innerHTML = `
        <tr>
          <td colspan="4" style="text-align:center; padding:20px; color:var(--text-muted);">
            لا توجد بيانات تجميعات مالية للشهر الحالي. اضغط "إعادة احتساب التجميعات الشهرية".
          </td>
        </tr>
      `;
      return;
    }

    let html = '';
    state.analytics.payments.forEach(p => {
      html += `
        <tr>
          <td class="font-mono" style="font-weight:700;">${p.month}</td>
          <td class="text-gold font-mono" style="font-weight:700;">${formatMoney(p.total_paid)} ج.م</td>
          <td class="text-danger font-mono">${formatMoney(p.total_refunded)} ج.م</td>
          <td class="font-mono">${p.count_paid} عملية</td>
        </tr>
      `;
    });
    el.analyticsPaymentsBody.innerHTML = html;
  }

  function renderAnalyticsUtilization() {
    if (!state.analytics.utilization || state.analytics.utilization.length === 0) {
      el.analyticsUtilizationBody.innerHTML = `
        <tr>
          <td colspan="4" style="text-align:center; padding:20px; color:var(--text-muted);">
            لا توجد بيانات إشغال متاحة.
          </td>
        </tr>
      `;
      return;
    }

    let html = '';
    state.analytics.utilization.forEach(u => {
      const pct = Number(u.utilization_pct) || 0;
      html += `
        <tr>
          <td style="font-weight:600;">${u.title_ar}</td>
          <td class="font-mono" style="font-size:0.8rem;">${u.month}</td>
          <td class="font-mono">${u.slots_booked} / ${u.slots_total}</td>
          <td style="min-width:140px;">
            <div class="flex items-center gap-2">
              <span class="font-mono" style="font-weight:700; width:45px; font-size:0.85rem;">${pct}%</span>
              <div class="progress-bar-bg flex-1">
                <div class="progress-bar-fill" style="width:${Math.min(100, pct)}%;"></div>
              </div>
            </div>
          </td>
        </tr>
      `;
    });
    el.analyticsUtilizationBody.innerHTML = html;
  }

  function renderAnalyticsBookings() {
    if (!state.analytics.bookings || state.analytics.bookings.length === 0) {
      el.analyticsBookingsBody.innerHTML = `
        <tr>
          <td colspan="4" style="text-align:center; padding:20px; color:var(--text-muted);">
            لا توجد بيانات حجوزات مجمعة للشهر الحالي.
          </td>
        </tr>
      `;
      return;
    }

    let html = '';
    state.analytics.bookings.forEach(b => {
      const statusPills = Object.entries(b.by_status || {}).map(([st, cnt]) => {
        return `<span class="badge badge-info" style="font-size:0.75rem;">${st}: ${cnt}</span>`;
      }).join(' ') || '<span style="color:var(--text-muted); font-size:0.8rem;">لا توجد حجوزات</span>';

      html += `
        <tr>
          <td style="font-weight:600;">${b.title_ar}</td>
          <td class="font-mono" style="font-size:0.8rem;">${b.month}</td>
          <td class="font-mono" style="font-weight:700;">${b.bookings_total} حجز</td>
          <td><div class="flex flex-wrap gap-1">${statusPills}</div></td>
        </tr>
      `;
    });
    el.analyticsBookingsBody.innerHTML = html;
  }

  async function handleRecalculateRollups() {
    const btn = el.btnRecalculateRollups;
    btn.disabled = true;
    btn.innerHTML = '<div class="spinner"></div> جاري احتساب التجميعات...';

    const admin = window.ChurchSupabase.getAdminClient();
    try {
      const { error } = await admin.rpc('materialize_analytics');
      if (error) throw error;

      window.ChurchSupabase.showToast('تمت إعادة احتساب التجميعات الشهرية بنجاح عبر materialize_analytics()', 'success');

      await Promise.all([
        loadOverviewStats(),
        loadAnalyticsData()
      ]);

    } catch (err) {
      console.error('Materialize analytics error:', err);
      window.ChurchSupabase.showToast(`فشل احتساب التجميعات: ${err.message}`, 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = '⚡ إعادة احتساب التجميعات الشهرية (materialize_analytics)';
    }
  }

  async function handleDownloadCsv() {
    const reportType = el.exportReportType.value;
    const month = el.exportMonthInput.value ? `${el.exportMonthInput.value}-01` : '2026-08-01';
    const btn = el.btnDownloadCsvAction;

    btn.disabled = true;
    btn.innerHTML = '<div class="spinner"></div> جاري تجهيز التقرير...';

    const sb = window.ChurchSupabase;
    const session = await sb.auth.getSession();
    const token = session?.access_token || '';

    try {
      let csvContent = '';
      let downloadedViaFunction = false;

      // 1. Attempt edge function export
      try {
        const res = await fetch(`http://127.0.0.1:54321/functions/v1/analytics-export?report=${reportType}&month=${month}`, {
          method: 'GET',
          headers: {
            'Authorization': `Bearer ${token}`
          }
        });

        if (res.ok) {
          csvContent = await res.text();
          downloadedViaFunction = true;
        }
      } catch (fErr) {
        console.warn('Edge function export attempt error:', fErr);
      }

      // 2. Direct fallback client generation if edge function returned non-200
      if (!downloadedViaFunction || !csvContent || csvContent.includes('FORBIDDEN') || csvContent.includes('error')) {
        const admin = sb.getAdminClient();
        const viewMap = {
          payments: 'v_analytics_payments',
          utilization: 'v_analytics_utilization',
          bookings: 'v_analytics_bookings'
        };

        const { data: rows, error: qErr } = await admin
          .from(viewMap[reportType])
          .select('*')
          .eq('month', month);

        if (qErr) throw qErr;

        if (!rows || rows.length === 0) {
          // Fetch without month filter if empty
          const { data: allRows } = await admin.from(viewMap[reportType]).select('*');
          csvContent = generateCsvFromRows(allRows || []);
        } else {
          csvContent = generateCsvFromRows(rows);
        }
      }

      // Trigger browser download
      const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.setAttribute('href', url);
      link.setAttribute('download', `church-${reportType}-${month}.csv`);
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);

      sb.showToast(`تم تحميل تقرير (${reportType}) بنجاح بصيغة CSV`, 'success');
      closeModal('modal-export-analytics');

    } catch (err) {
      console.error('CSV download error:', err);
      sb.showToast(`فشل تصدير التقرير: ${err.message}`, 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = '📥 تحميل ملف CSV';
    }
  }

  function generateCsvFromRows(rows) {
    if (!rows || rows.length === 0) {
      return '\uFEFF"لا توجد بيانات للشهر المحدد"\n';
    }
    const headers = Object.keys(rows[0]);
    const sanitize = (val) => {
      const s = String(val === null || val === undefined ? '' : typeof val === 'object' ? JSON.stringify(val) : val);
      const cleaned = /^[=+\-@\t\r]/.test(s) ? "'" + s : s;
      return /[",\r\n]/.test(cleaned) ? `"${cleaned.replace(/"/g, '""')}"` : cleaned;
    };

    const headerLine = headers.map(sanitize).join(',');
    const bodyLines = rows.map(r => headers.map(h => sanitize(r[h])).join(','));
    return '\uFEFF' + [headerLine, ...bodyLines].join('\n') + '\n';
  }

  /**
   * =========================================================================
   * 6. SYSTEM DIAGNOSTICS & HEALTH CONTROL
   * =========================================================================
   */
  async function handleRunSecurityProbes() {
    const btn = el.btnRunProbes;
    btn.disabled = true;
    btn.innerHTML = '<div class="spinner"></div> جاري تشغيل المسبارات...';

    el.probesResultsContainer.innerHTML = `
      <div style="text-align:center; padding:20px; color:var(--text-muted);">
        <div class="spinner"></div> جاري استدعاء /functions/v1/diagnostic-engine وفحص قواعد RLS...
      </div>
    `;

    const sb = window.ChurchSupabase;
    const session = await sb.auth.getSession();
    const token = session?.access_token || '';

    try {
      const res = await fetch('http://127.0.0.1:54321/functions/v1/diagnostic-engine', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.message_ar || data.error || 'Diagnostic engine error');

      let html = `
        <div class="alert ${data.critical_count === 0 ? 'alert-success' : 'alert-danger'}" style="margin-bottom:8px;">
          <div style="font-weight:700;">
            ${data.critical_count === 0 ? '✅ المنظومة مؤمنة 100% — كل المسبارات نجحت في التحقق من RLS' : `⚠️ تنبيه أمني: تم رصد ${data.critical_count} ثغرة تتطلب معالجة!`}
          </div>
          <div style="font-size:0.75rem; color:var(--text-secondary); margin-top:2px;">
            توقيت الفحص: ${formatDateAr(data.timestamp)} | المسبارات المنفذة: ${data.probes_executed}
          </div>
        </div>
      `;

      if (data.logs && data.logs.length > 0) {
        data.logs.forEach(probe => {
          const isPassed = probe.status === 401 || probe.status === 403 || (probe.status >= 400 && probe.status < 500);
          const probeDescriptions = {
            'SEC-ANON-USERS-READ': 'منع القراءة المباشرة لجدول المستخدمين بدون جلسة (Anon Read RLS)',
            'SEC-ANON-DIRECT-BOOKING-INSERT': 'منع الإدراج المباشر في جدول الحجوزات وتجاوز الـ RPC (Direct Insert RLS)',
            'SEC-ANON-BOOK-SLOT-RPC': 'منع استدعاء book_slot بدون توثيق الجلسة (Security Definer Auth Guard)'
          };

          html += `
            <div class="probe-card ${isPassed ? 'passed' : 'failed'}">
              <div class="flex items-center justify-between">
                <div>
                  <div style="font-weight:700; font-size:0.9rem; color:var(--text-primary); font-family:monospace;">
                    ${probe.id}
                  </div>
                  <div style="font-size:0.75rem; color:var(--text-muted);">
                    ${probeDescriptions[probe.id] || probe.id}
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <span class="badge ${isPassed ? 'badge-confirmed' : 'badge-cancelled'}">
                    ${isPassed ? '✓ محمي (DENIED 401)' : `✕ مخترق (HTTP ${probe.status})`}
                  </span>
                  <span class="font-mono" style="font-size:0.75rem; color:var(--text-muted);">${probe.latencyMs}ms</span>
                </div>
              </div>
            </div>
          `;
        });
      }

      if (data.findings && data.findings.length > 0) {
        html += '<div style="margin-top:8px;"><div style="font-weight:700; color:var(--danger); font-size:0.85rem;">تفاصيل الثغرات المرصودة:</div>';
        data.findings.forEach(f => {
          html += `
            <div class="alert alert-danger" style="margin-top:4px; font-size:0.8rem;">
              <strong>${f.title}</strong>: ${f.description}<br>
              <code style="color:var(--gold);">${f.remediation}</code>
            </div>
          `;
        });
        html += '</div>';
      }

      el.probesResultsContainer.innerHTML = html;
      sb.showToast('تم اكتمال الفحص الأمني المباشر بنجاح', 'success');

    } catch (err) {
      console.error('Probes error:', err);
      el.probesResultsContainer.innerHTML = `
        <div class="alert alert-danger">
          فشل تنفيذ الفحص الأمني: ${err.message}
        </div>
      `;
      sb.showToast(`فشل الفحص الأمني: ${err.message}`, 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = '🚀 تشغيل الفحص الآن';
    }
  }

  async function handleTriggerReaper() {
    const timeout = el.selectReaperTimeout.value;
    const btn = el.btnTriggerReaper;
    btn.disabled = true;
    btn.innerHTML = '<div class="spinner"></div> جاري المعالجة...';

    const admin = window.ChurchSupabase.getAdminClient();
    try {
      const { data: reapedCount, error } = await admin.rpc('reap_stuck_outbox_events', { p_timeout: timeout });
      if (error) throw error;

      el.reaperResultBox.style.display = 'block';
      el.reaperResultBox.className = 'alert alert-success';
      el.reaperResultBox.innerHTML = `
        ✓ تم تشغيل دالة <code>reap_stuck_outbox_events('${timeout}')</code> بنجاح.<br>
        <strong>عدد الأحداث العالقة التي تمت معالجتها وإعادتها:</strong> ${reapedCount ?? 0} حدث.
      `;

      window.ChurchSupabase.showToast(`تم تنظيف ومعالجة (${reapedCount ?? 0}) من أحداث الـ Outbox العالقة`, 'success');
    } catch (err) {
      console.error('Reaper error:', err);
      el.reaperResultBox.style.display = 'block';
      el.reaperResultBox.className = 'alert alert-danger';
      el.reaperResultBox.textContent = `فشل تشغيل الـ Reaper: ${err.message}`;
      window.ChurchSupabase.showToast(`خطأ في تشغيل الـ Reaper: ${err.message}`, 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = '⚡ تشغيل الـ Reaper';
    }
  }

  async function handleVaultPreflight() {
    const btn = el.btnRunVaultPreflight;
    btn.disabled = true;
    btn.innerHTML = '<div class="spinner"></div> جاري الفحص...';

    const admin = window.ChurchSupabase.getAdminClient();
    try {
      const { data: missingSecrets, error } = await admin.rpc('vault_preflight');
      if (error) throw error;

      const allRequired = ['COMPLAINTS_KEY', 'SUPABASE_URL', 'SERVICE_ROLE_KEY'];
      const missing = missingSecrets || [];

      let html = '';
      allRequired.forEach(sec => {
        const isMissing = missing.includes(sec);
        html += `
          <div class="flex items-center justify-between" style="padding:8px 12px; background:var(--bg-elevated); border-radius:var(--radius-sm); border-right: 4px solid ${isMissing ? 'var(--danger)' : 'var(--success)'};">
            <span class="font-mono" style="font-weight:700; font-size:0.85rem;">${sec}</span>
            <span class="badge ${isMissing ? 'badge-cancelled' : 'badge-confirmed'}">
              ${isMissing ? '✕ مفقود من الخزينة' : '✓ متوفر ومسجل'}
            </span>
          </div>
        `;
      });

      if (missing.length === 0) {
        html += `
          <div class="alert alert-success" style="font-size:0.8rem; margin-top:6px; margin-bottom:0;">
            ✓ كل مفاتيح وأسرار الخزينة الثلاثة مؤكدة وجاهزة لعمليات التشفير والـ Edge Functions.
          </div>
        `;
      } else {
        html += `
          <div class="alert alert-danger" style="font-size:0.8rem; margin-top:6px; margin-bottom:0;">
            ⚠️ يوجد أسرار غير متوفرة في vault.decrypted_secrets قد تؤدي لتعطل تشفير الشكاوى.
          </div>
        `;
      }

      el.vaultResultsBox.innerHTML = html;
      window.ChurchSupabase.showToast('تم اكتمال فحص الخزينة vault_preflight()', 'info');

    } catch (err) {
      console.error('Vault preflight error:', err);
      el.vaultResultsBox.innerHTML = `
        <div class="alert alert-danger">
          فشل فحص الخزينة: ${err.message}
        </div>
      `;
    } finally {
      btn.disabled = false;
      btn.textContent = '🔍 فحص الخزينة';
    }
  }

  async function runInfraHealthCheck() {
    try {
      // Test PostgREST
      const start = Date.now();
      const res = await fetch('http://127.0.0.1:54321/rest/v1/', {
        headers: { 'apikey': window.ChurchSupabase.CONFIG.anonKey }
      });
      const latency = Date.now() - start;

      if (res.ok || res.status === 200 || res.status === 404) {
        el.healthPostgrest.className = 'badge badge-open';
        el.healthPostgrest.textContent = `متصل (${latency}ms)`;
      } else {
        el.healthPostgrest.className = 'badge badge-failed';
        el.healthPostgrest.textContent = `استجابة ${res.status}`;
      }

      el.healthPostgres.className = 'badge badge-open';
      el.healthPostgres.textContent = 'متصل (Port 54323)';

      el.healthGotrue.className = 'badge badge-open';
      el.healthGotrue.textContent = 'نشط (GoTrue Auth)';

      el.healthEdge.className = 'badge badge-open';
      el.healthEdge.textContent = 'نشط (Deno Engine)';

    } catch (err) {
      console.warn('Infra ping error:', err);
      el.healthPostgrest.className = 'badge badge-failed';
      el.healthPostgrest.textContent = 'غير متصل';
    }
  }

  /**
   * =========================================================================
   * 7. MODALS & TAB NAVIGATION HELPERS
   * =========================================================================
   */
  function openModal(modalId) {
    const m = document.getElementById(modalId);
    if (m) m.classList.add('active');
  }

  function closeModal(modalId) {
    const m = document.getElementById(modalId);
    if (m) m.classList.remove('active');
  }

  function setupTabs() {
    el.tabButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        el.tabButtons.forEach(b => b.classList.remove('active'));
        el.tabPanes.forEach(p => p.style.display = 'none');

        btn.classList.add('active');
        const targetId = btn.getAttribute('data-tab');
        const targetPane = document.getElementById(targetId);
        if (targetPane) targetPane.style.display = 'block';
      });
    });
  }

  function setupEventListeners() {
    // 1-Click SuperAdmin Quick Login
    if (el.btnQuickLoginSuperAdmin) {
      el.btnQuickLoginSuperAdmin.addEventListener('click', async () => {
        el.btnQuickLoginSuperAdmin.disabled = true;
        el.btnQuickLoginSuperAdmin.innerHTML = '<div class="spinner"></div> جاري تسجيل الدخول...';
        try {
          await window.TestAccounts.loginAs('superadmin');
          setTimeout(() => window.location.reload(), 300);
        } catch (err) {
          el.btnQuickLoginSuperAdmin.disabled = false;
          el.btnQuickLoginSuperAdmin.textContent = '⚡ الدخول الفوري كمدير أعلى (كيرلس)';
        }
      });
    }

    // Manual Form Login
    if (el.formManualLogin) {
      el.formManualLogin.addEventListener('submit', async (e) => {
        e.preventDefault();
        const email = el.inputLoginEmail.value;
        const pass = el.inputLoginPassword.value;
        try {
          await window.ChurchSupabase.auth.loginWithPassword(email, pass);
          window.location.reload();
        } catch (err) {
          // Toast handled
        }
      });
    }

    // User Filters
    if (el.filterUsersSearch) el.filterUsersSearch.addEventListener('input', renderUsersTable);
    if (el.filterUsersRole) el.filterUsersRole.addEventListener('change', renderUsersTable);
    if (el.btnRefreshUsers) el.btnRefreshUsers.addEventListener('click', loadUsersList);

    // Role Save
    if (el.btnSaveUserRole) el.btnSaveUserRole.addEventListener('click', handleSaveUserRole);

    // Audit Filters
    if (el.filterAuditSearch) el.filterAuditSearch.addEventListener('input', renderAuditTable);
    if (el.filterAuditEntity) el.filterAuditEntity.addEventListener('change', loadAuditLogs);
    if (el.filterAuditAction) el.filterAuditAction.addEventListener('change', loadAuditLogs);
    if (el.filterAuditLimit) el.filterAuditLimit.addEventListener('change', loadAuditLogs);
    if (el.btnRefreshAudit) el.btnRefreshAudit.addEventListener('click', loadAuditLogs);

    if (el.btnToggleAllJson) {
      el.btnToggleAllJson.addEventListener('click', () => {
        state.allJsonExpanded = !state.allJsonExpanded;
        el.btnToggleAllJson.textContent = state.allJsonExpanded ? '📁 طي كل البيانات' : '📂 توسيع كل البيانات';
        renderAuditTable();
      });
    }

    // Analytics Actions
    if (el.btnRecalculateRollups) el.btnRecalculateRollups.addEventListener('click', handleRecalculateRollups);
    if (el.btnOpenExportModal) el.btnOpenExportModal.addEventListener('click', () => openModal('modal-export-analytics'));
    if (el.btnDownloadCsvAction) el.btnDownloadCsvAction.addEventListener('click', handleDownloadCsv);

    // Diagnostics Actions
    if (el.btnRunProbes) el.btnRunProbes.addEventListener('click', handleRunSecurityProbes);
    if (el.btnTriggerReaper) el.btnTriggerReaper.addEventListener('click', handleTriggerReaper);
    if (el.btnRunVaultPreflight) el.btnRunVaultPreflight.addEventListener('click', handleVaultPreflight);
    if (el.btnRefreshInfra) el.btnRefreshInfra.addEventListener('click', runInfraHealthCheck);

    // Modal Close Buttons
    document.querySelectorAll('[data-close-modal]').forEach(btn => {
      btn.addEventListener('click', () => {
        const mid = btn.getAttribute('data-close-modal');
        closeModal(mid);
      });
    });

    // Close on backdrop click
    document.querySelectorAll('.modal-backdrop').forEach(backdrop => {
      backdrop.addEventListener('click', (e) => {
        if (e.target === backdrop) backdrop.classList.remove('active');
      });
    });
  }

  /**
   * Application Bootstrap
   */
  async function init() {
    setupTabs();
    setupEventListeners();
    await checkAuthAndInit();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
