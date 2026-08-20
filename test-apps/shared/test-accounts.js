/**
 * ============================================================================
 * Church Digital Platform — Predefined Seed Test Accounts & Switcher UI
 * ============================================================================
 */

(function () {
  'use strict';

  const TEST_ACCOUNTS = [
    {
      id: 'mariam',
      name: 'مريم يوسف',
      email: 'mariam@church.test',
      phone: '+201000000002',
      password: 'password123',
      otp: '123456',
      role: 'USER',
      roleLabel: 'مخدومة / رعية',
      badgeClass: 'badge-role-user',
      avatar: 'م',
      description: 'حساب مستخدم لاختبار حجز المواعيد والقداسات ودفع Paymob والشكاوى'
    },
    {
      id: 'peter',
      name: 'بيتر سمير',
      email: 'peter@church.test',
      phone: '+201000000003',
      password: 'password123',
      otp: '123456',
      role: 'USER',
      roleLabel: 'مخدوم / رعية',
      badgeClass: 'badge-role-user',
      avatar: 'ب',
      description: 'حساب مستخدم ثانٍ لاختبار التنافس على المقاعد والحجز المتزامن'
    },
    {
      id: 'admin',
      name: 'أ/ مينا موريس',
      email: 'admin@church.test',
      phone: '+201000000001',
      password: 'password123',
      otp: '123456',
      role: 'ADMIN',
      roleLabel: 'سكرتير إداري',
      badgeClass: 'badge-role-admin',
      avatar: 'م',
      description: 'حساب إداري لاختبار تأكيد الحجوزات بعد الاتصال وإدارة السعة والحجز النقدي'
    },
    {
      id: 'priest',
      name: 'أبونا بولا',
      email: 'priest@church.test',
      phone: '+201000000004',
      password: 'password123',
      otp: '123456',
      role: 'ADMIN',
      roleLabel: 'كاهن الكنيسة',
      badgeClass: 'badge-role-admin',
      avatar: '✝',
      description: 'حساب كاهن لمتابعة المواعيد وفك تشفير وقراءة شكاوى المخدومين'
    },
    {
      id: 'superadmin',
      name: 'م/ كيرلس - مدير النظام',
      email: 'superadmin@church.local',
      phone: '+201000000005',
      password: 'password123',
      otp: '123456',
      role: 'SUPER_ADMIN',
      roleLabel: 'مدير المنظومة الأعلى',
      badgeClass: 'badge-role-superadmin',
      avatar: '⚡',
      description: 'حساب إدارة عليا لضبط الصلاحيات ومطالعة سجل التدقيق والتحليلات المالية'
    }
  ];

  /**
   * Log in directly with predefined account
   */
  async function loginAsAccount(accountIdOrEmail) {
    const acc = TEST_ACCOUNTS.find(
      (a) => a.id === accountIdOrEmail || a.email.toLowerCase() === accountIdOrEmail.toLowerCase()
    );

    if (!acc) {
      throw new Error(`حساب غير معروف: ${accountIdOrEmail}`);
    }

    const sb = (typeof window !== 'undefined' && window.ChurchSupabase) ? window.ChurchSupabase : ((typeof globalThis !== 'undefined' && globalThis.ChurchSupabase) ? globalThis.ChurchSupabase : null);
    if (!sb || !sb.auth) {
      throw new Error('ChurchSupabase client is not loaded.');
    }

    try {
      const data = await sb.auth.loginWithPassword(acc.email, acc.password);
      sb.showToast(`تم تسجيل الدخول بنجاح كـ: ${acc.name} (${acc.roleLabel})`, 'success');
      return { success: true, account: acc, data };
    } catch (err) {
      const msg = err.message || 'فشل تسجيل الدخول';
      sb.showToast(msg, 'error');
      throw err;
    }
  }

  /**
   * Render interactive test account picker inside container
   */
  function renderAccountGrid(containerIdOrElement, options = {}) {
    const container = typeof containerIdOrElement === 'string'
      ? document.getElementById(containerIdOrElement)
      : containerIdOrElement;

    if (!container) return;

    const onLoginSuccess = options.onSuccess || (() => window.location.reload());
    const filterRole = options.role || null;

    const accountsToShow = filterRole
      ? TEST_ACCOUNTS.filter(a => a.role === filterRole || (filterRole === 'ADMIN' && a.role === 'SUPER_ADMIN'))
      : TEST_ACCOUNTS;

    let html = `
      <div class="test-accounts-wrapper" style="display:flex; flex-direction:column; gap:12px;">
        <div style="font-size:0.85rem; color:var(--text-muted); margin-bottom:4px;">
          ⚡ اضغط على أي حساب لتسجيل الدخول الفوري بكلمة مرور <code style="color:var(--gold);">password123</code> و OTP <code style="color:var(--gold);">123456</code>:
        </div>
        <div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap:10px;">
    `;

    accountsToShow.forEach((acc) => {
      html += `
        <div class="card card-interactive account-btn" data-account-id="${acc.id}" style="padding:12px 14px; cursor:pointer; display:flex; align-items:center; justify-content:space-between; gap:10px;">
          <div style="display:flex; align-items:center; gap:10px;">
            <div class="user-avatar" style="width:34px; height:34px; font-size:0.95rem; font-weight:bold;">${acc.avatar}</div>
            <div>
              <div style="font-weight:700; font-size:0.9rem; color:var(--text-primary);">${acc.name}</div>
              <div style="font-size:0.75rem; color:var(--text-secondary); direction:ltr; text-align:right;">${acc.email}</div>
            </div>
          </div>
          <div style="display:flex; flex-direction:column; align-items:flex-end; gap:4px;">
            <span class="badge ${acc.badgeClass}">${acc.roleLabel}</span>
            <span style="font-size:0.7rem; color:var(--text-muted); direction:ltr;">${acc.phone}</span>
          </div>
        </div>
      `;
    });

    html += `
        </div>
      </div>
    `;

    container.innerHTML = html;

    // Attach click listeners
    const buttons = container.querySelectorAll('.account-btn');
    buttons.forEach((btn) => {
      btn.addEventListener('click', async () => {
        const accountId = btn.getAttribute('data-account-id');
        btn.style.opacity = '0.6';
        btn.style.pointerEvents = 'none';
        try {
          const res = await loginAsAccount(accountId);
          if (onLoginSuccess) {
            onLoginSuccess(res);
          }
        } catch (e) {
          // Toast handled in loginAsAccount
        } finally {
          btn.style.opacity = '1';
          btn.style.pointerEvents = 'auto';
        }
      });
    });
  }

  /**
   * Render top user banner / status pill
   */
  async function renderTopUserBanner(containerIdOrElement, options = {}) {
    const container = typeof containerIdOrElement === 'string'
      ? document.getElementById(containerIdOrElement)
      : containerIdOrElement;

    if (!container) return;

    const sb = (typeof window !== 'undefined' && window.ChurchSupabase) ? window.ChurchSupabase : ((typeof globalThis !== 'undefined' && globalThis.ChurchSupabase) ? globalThis.ChurchSupabase : null);
    if (!sb) return;

    const user = await sb.auth.getUser();
    if (!user) {
      container.innerHTML = `
        <div style="display:flex; align-items:center; gap:8px;">
          <span class="badge badge-closed">غير مسجل الدخول</span>
          <a href="/index.html" class="btn btn-sm btn-outline">تسجيل الدخول</a>
        </div>
      `;
      return;
    }

    const role = await sb.auth.getCurrentUserRole();
    const matchedAccount = TEST_ACCOUNTS.find(a => a.email.toLowerCase() === (user.email || '').toLowerCase());
    const displayName = matchedAccount ? matchedAccount.name : (user.user_metadata?.name || user.email || 'مستخدم');
    const badgeClass = role === 'SUPER_ADMIN' ? 'badge-role-superadmin' : (role === 'ADMIN' ? 'badge-role-admin' : 'badge-role-user');
    const roleLabel = role === 'SUPER_ADMIN' ? 'مدير أعلى' : (role === 'ADMIN' ? 'إداري' : 'مخدوم');

    container.innerHTML = `
      <div style="display:flex; align-items:center; gap:10px;">
        <div class="user-pill">
          <div class="user-avatar">${matchedAccount ? matchedAccount.avatar : '👤'}</div>
          <span>${displayName}</span>
          <span class="badge ${badgeClass}">${roleLabel}</span>
        </div>
        <button id="btn-logout" class="btn btn-sm btn-outline" style="padding:4px 8px; font-size:0.75rem;">خروج</button>
      </div>
    `;

    const logoutBtn = container.querySelector('#btn-logout');
    if (logoutBtn) {
      logoutBtn.addEventListener('click', async () => {
        await sb.auth.logout();
        sb.showToast('تم تسجيل الخروج بنجاح', 'info');
        setTimeout(() => {
          if (options.onLogout) {
            options.onLogout();
          } else {
            window.location.reload();
          }
        }, 400);
      });
    }
  }

  const TestAccounts = {
    ACCOUNTS: TEST_ACCOUNTS,
    loginAs: loginAsAccount,
    renderGrid: renderAccountGrid,
    renderUserBanner: renderTopUserBanner
  };

  if (typeof window !== 'undefined') {
    window.TestAccounts = TestAccounts;
  }
  if (typeof globalThis !== 'undefined') {
    globalThis.TestAccounts = TestAccounts;
  }
})();
