export const MOCK_PAYMENT_LABEL = 'Mock/sandbox — no real money moved';

export const ROUTES = Object.freeze([
  '/',
  '/services',
  '/auth/sign-in',
  '/auth/register',
  '/auth/forgot-password',
  '/auth/reset-password',
  '/auth/callback',
  '/app/customer',
  '/app/provider',
  '/app/settings',
  '/access-denied',
  '/account-restricted',
]);

const icon = (name) => `<span class="icon" aria-hidden="true">${name}</span>`;

export function escapeHtml(value = '') {
  return String(value).replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
  })[character]);
}

export function normalizePath(pathname = '/') {
  const cleaned = pathname.replace(/\/{2,}/g, '/').replace(/\/$/, '');
  return cleaned || '/';
}

export function isKnownRoute(pathname) {
  return ROUTES.includes(normalizePath(pathname));
}

export function mockPaymentBanner() {
  return `
    <aside class="mock-banner" role="note" aria-label="Payment environment notice">
      ${icon('i')}
      <div>
        <strong>${MOCK_PAYMENT_LABEL}</strong>
        <span>Payment and release information is read-only sandbox data.</span>
      </div>
    </aside>`;
}

export function pageState(kind, title, message, action = '') {
  const symbols = { loading: '···', empty: '○', error: '!', signedOut: '→', expired: '→', restricted: '—', notFound: '?' };
  const actionMarkup = action
    ? `<a class="button button-secondary" href="${escapeHtml(action)}" data-nav>Continue</a>`
    : '';
  return `
    <section class="page-state page-state-${escapeHtml(kind)}" data-state="${escapeHtml(kind)}" aria-busy="${kind === 'loading'}">
      <span class="state-symbol" aria-hidden="true">${symbols[kind] ?? '○'}</span>
      <div><h2>${escapeHtml(title)}</h2><p>${escapeHtml(message)}</p>${actionMarkup}</div>
    </section>`;
}

function brand() {
  return '<a class="brand" href="/" data-nav aria-label="LEKKADEALL home"><span>LD</span><b>LEKKADEALL</b></a>';
}

function sessionControl(view = {}) {
  return view.sessionReady
    ? '<button class="nav-session-action" type="button" data-auth-action="sign-out">Sign out</button>'
    : '<a class="nav-sign-in" href="/auth/sign-in" data-nav>Sign in</a>';
}

function publicHeader(view = {}) {
  return `
    <header class="site-header"><div class="header-inner">
      ${brand()}
      <button class="menu-toggle" type="button" data-menu-toggle aria-expanded="false" aria-controls="primary-nav">Menu</button>
      <nav id="primary-nav" class="primary-nav" aria-label="Primary navigation">
        <a href="/services" data-nav>Browse services</a>
        <a href="/app/customer" data-nav>Customer</a>
        <a href="/app/provider" data-nav>Provider</a>
        ${sessionControl(view)}
      </nav>
    </div></header>`;
}

function appHeader(section) {
  return `
    <header class="app-header"><div class="header-inner">
      ${brand()}
      <div class="app-context"><span>Safe read-only access</span><strong>${escapeHtml(section)}</strong></div>
      <nav class="app-nav" aria-label="Application navigation">
        <a href="/app/customer" data-nav>Customer</a>
        <a href="/app/provider" data-nav>Provider</a>
        <a href="/app/settings" data-nav>Settings</a>
        <button type="button" data-auth-action="sign-out">Sign out</button>
      </nav>
    </div></header>`;
}

function footer() {
  return `
    <footer class="site-footer">
      <div>${brand()}<p>A careful read-only layer for local service bookings.</p></div>
      <div class="footer-links"><a href="/services" data-nav>Services</a><a href="/auth/sign-in" data-nav>Sign in</a><span>South Africa</span></div>
      <small>Ticket 9A-2. No real payments or sensitive marketplace mutations are connected.</small>
    </footer>`;
}

function publicPage(content, className = '', view = {}) {
  return `${publicHeader(view)}<main id="main-content" class="${className}">${content}</main>${footer()}`;
}

function appPage(section, content) {
  return `${appHeader(section)}<main id="main-content" class="app-main">${content}</main>`;
}

function landingPage(view) {
  return publicPage(`
    <section class="hero-section">
      <div class="hero-copy">
        <p class="eyebrow">LOCAL SERVICES · CLEARLY ARRANGED</p>
        <h1>Good work starts with a <em>clear request.</em></h1>
        <p class="hero-lead">LEKKADEALL helps customers and providers keep safe account and marketplace information easy to follow.</p>
        <div class="hero-actions"><a class="button button-primary" href="/services" data-nav>Browse services <span aria-hidden="true">→</span></a><a class="button button-secondary" href="/auth/register" data-nav>Create an account</a></div>
        <p class="hero-note">This release does not create requests, accept bids or process payments.</p>
      </div>
      <div class="hero-board" aria-label="Marketplace journey preview">
        <div class="board-top"><span>HOW IT WILL FLOW</span><b>01—04</b></div>
        <ol class="journey-list">
          <li><span>01</span><div><strong>Describe the work</strong><small>Share the service, general area and timing.</small></div></li>
          <li><span>02</span><div><strong>Review offers</strong><small>Compare the details that matter to you.</small></div></li>
          <li><span>03</span><div><strong>Follow the booking</strong><small>See one clear status from start to finish.</small></div></li>
          <li><span>04</span><div><strong>Confirm completion</strong><small>Sensitive actions arrive only when safely supported.</small></div></li>
        </ol>
      </div>
    </section>
    <section class="trust-strip" aria-label="Current boundaries">
      <article><span>01</span><strong>Private by design</strong><p>Exact addresses are not collected or displayed here.</p></article>
      <article><span>02</span><strong>RLS-backed reads</strong><p>Account screens use narrow projections and existing row security.</p></article>
      <article><span>03</span><strong>Honest payment state</strong><p>There is no real checkout, cash option or payment-method form.</p></article>
    </section>
    <section class="split-section"><div><p class="eyebrow">THE NEXT SAFE LAYER</p><h2>Real authentication.<br> Narrow reads only.</h2></div><div class="boundary-copy"><p>Sessions resolve role and account status only from the protected application profile created by Ticket 9B.</p>${mockPaymentBanner()}</div></section>
  `, 'landing-main', view);
}

function categoryCards(categories) {
  return `<section class="category-grid" aria-label="Active service categories">${categories.map((category) => `
    <article class="category-card"><span>ACTIVE CATEGORY</span><h2>${escapeHtml(category.name)}</h2><p>${escapeHtml(category.slug)}</p></article>`).join('')}</section>`;
}

function servicesPage(searchParams, view) {
  let content;
  if (searchParams.get('state') === 'loading' || view.categoriesStatus === 'loading') {
    content = pageState('loading', 'Loading service categories', 'Only active public categories will be shown.');
  } else if (view.categoriesStatus === 'error') {
    content = pageState('error', 'Categories are unavailable', 'No protected data was broadened or retried.', '/services');
  } else if (view.categoriesStatus === 'ready' && view.categories?.length) {
    content = categoryCards(view.categories);
  } else if (view.categoriesStatus === 'unconfigured') {
    content = pageState('empty', 'Public configuration required', 'Add local placeholder-derived public configuration to load active categories.');
  } else {
    content = pageState('empty', 'No active categories available', 'Only active categories permitted by existing RLS can appear here.');
  }

  return publicPage(`
    <section class="page-intro"><p class="eyebrow">SERVICE DISCOVERY</p><h1>Find the right starting point.</h1><p>This page reads only active service category IDs, slugs and names.</p></section>
    <section class="filter-shell" aria-label="Service category filters"><label><span>Search services</span><input type="search" placeholder="Browse the active categories below" disabled></label><button type="button" disabled>Active categories only</button></section>
    ${content}
    <section class="safety-note"><strong>Public-data boundary</strong><p>This screen does not query users, requests, bookings, payments, verification records or exact addresses.</p></section>
  `, 'content-main', view);
}

const authCopy = {
  '/auth/sign-in': {
    eyebrow: 'WELCOME BACK', title: 'Sign in to your workspace.', description: 'Your session is resolved by Supabase Auth; application authority comes only from your protected profile.', action: 'sign-in',
    fields: '<label>Email address<input name="email" type="email" autocomplete="email" required></label><label>Password<input name="password" type="password" autocomplete="current-password" required></label>', submit: 'Sign in',
    links: '<a href="/auth/forgot-password" data-nav>Forgot password?</a><a href="/auth/register" data-nav>Create an account</a>',
  },
  '/auth/register': {
    eyebrow: 'START HERE', title: 'Create a customer account.', description: 'Ticket 9B creates the customer/active application profile. Registration sends no role or approval metadata.', action: 'register',
    fields: '<label>Email address<input name="email" type="email" autocomplete="email" required></label><label>Create password<input name="password" type="password" autocomplete="new-password" minlength="10" required></label>', submit: 'Create account',
    links: '<a href="/auth/sign-in" data-nav>Already have an account?</a>',
  },
  '/auth/forgot-password': {
    eyebrow: 'ACCOUNT RECOVERY', title: 'Reset access safely.', description: 'The response stays neutral and does not disclose whether an account exists.', action: 'forgot-password',
    fields: '<label>Email address<input name="email" type="email" autocomplete="email" required></label>', submit: 'Request reset link', links: '<a href="/auth/sign-in" data-nav>Back to sign in</a>',
  },
  '/auth/reset-password': {
    eyebrow: 'CHOOSE A NEW PASSWORD', title: 'Finish your password reset.', description: 'A Supabase-established recovery session is required.', action: 'reset-password',
    fields: '<label>New password<input name="password" type="password" autocomplete="new-password" minlength="10" required></label><label>Confirm new password<input name="password-confirmation" type="password" autocomplete="new-password" minlength="10" required></label>', submit: 'Update password', links: '<a href="/auth/sign-in" data-nav>Return to sign in</a>',
  },
};

function authPage(pathname, view) {
  const content = authCopy[pathname];
  const recoveryWarning = pathname === '/auth/reset-password' && !view.recoveryReady
    ? pageState('error', 'Recovery session required', 'Open the valid recovery link sent by Supabase Auth.', '/auth/forgot-password')
    : '';
  return publicPage(`
    <section class="auth-layout">
      <div class="auth-aside"><p class="eyebrow">ACCOUNT ACCESS</p><h2>One quiet place for every next step.</h2><ul><li>Customer and provider routes stay separate.</li><li>Unknown access fails closed.</li><li>No privileged state comes from Auth metadata.</li></ul></div>
      <div class="auth-card"><p class="eyebrow">${content.eyebrow}</p><h1>${content.title}</h1><p>${content.description}</p>${recoveryWarning}
        <form data-auth-form="${content.action}" novalidate ${pathname === '/auth/reset-password' && !view.recoveryReady ? 'hidden' : ''}>${content.fields}<button class="button button-primary" type="submit">${content.submit}</button></form>
        <div class="form-message" data-form-message role="status">${escapeHtml(view.formMessage ?? '')}</div><div class="auth-links">${content.links}</div>
      </div>
    </section>`, 'auth-main', view);
}

function authCallbackPage(view) {
  const status = view.callbackStatus === 'error'
    ? pageState('error', 'Unable to complete authentication', 'The callback was rejected safely. No role or account status was accepted from the URL.', '/auth/sign-in')
    : pageState('loading', 'Validating session', 'No role or account status is accepted from this URL.');
  return publicPage(`<section class="narrow-page"><p class="eyebrow">AUTHENTICATION CALLBACK</p><h1>Checking the sign-in response.</h1>${status}</section>`, 'content-main', view);
}

function metricCard(label, value, note) {
  return `<article class="metric-card"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong><small>${escapeHtml(note)}</small></article>`;
}

function accessState(access = { kind: 'signedOut' }) {
  const states = {
    loading: ['loading', 'Checking account access', 'Session and protected profile status are loading.', ''],
    signedOut: ['signedOut', 'Sign in required', 'A preview route is never treated as proof of identity.', '/auth/sign-in'],
    expired: ['expired', 'Session expired', 'Sign in again to continue safely.', '/auth/sign-in'],
    missingProfile: ['error', 'Account setup unavailable', 'Your sign-in exists, but the protected application profile could not be resolved.', '/access-denied'],
    restricted: ['restricted', 'Account access is restricted', 'Sensitive actions and dashboard reads remain unavailable.', '/account-restricted'],
    accessDenied: ['error', 'Access denied', 'This account is not authorised for the requested workspace.', '/access-denied'],
    error: ['error', 'Account data unavailable', 'No broader read or elevated fallback was attempted.', ''],
    unconfigured: ['error', 'Public configuration required', 'Authentication is unavailable until valid public runtime values are supplied.', ''],
  };
  const [kind, title, message, action] = states[access.kind] ?? states.error;
  return pageState(kind, title, message, action);
}

function formatMoney(minor, currency = 'ZAR') {
  if (!Number.isInteger(minor)) return '—';
  return new Intl.NumberFormat('en-ZA', { style: 'currency', currency }).format(minor / 100);
}

function dataList(items, renderItem, emptyTitle, emptyMessage) {
  if (!items?.length) return pageState('empty', emptyTitle, emptyMessage);
  return `<div class="data-list">${items.map(renderItem).join('')}</div>`;
}

function customerDashboard(view) {
  if (view.access?.kind !== 'allowed') {
    return appPage('Customer workspace', `<section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER WORKSPACE</p><h1>Your next job starts here.</h1></div></section>${accessState(view.access)}${mockPaymentBanner()}`);
  }
  const requests = view.customer?.requests?.data ?? [];
  const bookings = view.customer?.bookings?.data ?? [];
  const payments = view.customer?.payments?.data ?? [];
  const requestContent = view.customer?.requests?.ok === false
    ? pageState('error', 'Requests unavailable', 'Existing RLS or column grants did not permit this read.')
    : dataList(requests, (request) => `<article><span>${escapeHtml(request.status)}</span><strong>${escapeHtml(request.title)}</strong><small>${escapeHtml(request.suburb)}, ${escapeHtml(request.city)}</small></article>`, 'No requests to show', 'Request creation is intentionally not implemented.');
  const bookingContent = view.customer?.bookings?.ok === false
    ? pageState('error', 'Bookings unavailable', 'No broader booking query was attempted.')
    : dataList(bookings, (booking) => `<article><span>${escapeHtml(booking.status)}</span><strong>${escapeHtml(booking.public_reference)}</strong><small>${formatMoney(booking.service_amount_minor, booking.currency)}</small></article>`, 'No bookings to show', 'Booking actions and completion are intentionally not implemented.');

  return appPage('Customer workspace', `
    <section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER WORKSPACE</p><h1>Your safe account view.</h1><p>Only RLS-protected request, booking and sandbox-payment summaries are read.</p></div><span class="button button-disabled" aria-disabled="true">New request — later</span></section>
    <section class="metrics-grid" aria-label="Customer summary"><div>${metricCard('Requests', String(requests.length), 'Own rows only')}</div><div>${metricCard('Bookings', String(bookings.length), 'Booking-party rows only')}</div><div>${metricCard('Payments', String(payments.length), 'Read-only sandbox statuses')}</div></section>
    ${mockPaymentBanner()}
    <section class="dashboard-grid"><article class="panel"><div class="panel-heading"><div><span>REQUESTS</span><h2>Your requests</h2></div><span class="status-chip">Read-only</span></div>${requestContent}</article><article class="panel"><div class="panel-heading"><div><span>BOOKINGS</span><h2>Your timeline</h2></div><span class="status-chip">Read-only</span></div>${bookingContent}</article></section>
  `);
}

function providerDashboard(view) {
  if (view.access?.kind !== 'allowed') {
    return appPage('Provider workspace', `<section class="dashboard-heading"><div><p class="eyebrow">PROVIDER WORKSPACE</p><h1>A clear view of readiness.</h1></div></section>${accessState(view.access)}${mockPaymentBanner()}`);
  }
  const status = view.providerStatus;
  const statusContent = status?.ok === false
    ? pageState('error', 'Provider status unavailable', 'No broader provider query was attempted.')
    : status?.data
      ? `<div class="read-grid"><div class="read-field"><span>Business</span><strong>${escapeHtml(status.data.business_name)}</strong><small>Read-only</small></div><div class="read-field"><span>Verification</span><strong>${escapeHtml(status.data.verification_status)}</strong><small>Server-owned</small></div><div class="read-field"><span>Review</span><strong>${escapeHtml(status.data.review_status)}</strong><small>Admin-owned</small></div><div class="read-field"><span>Service radius</span><strong>${escapeHtml(status.data.service_radius_km ?? 'Not set')}</strong><small>Read-only</small></div></div>`
      : pageState('empty', 'Provider setup unavailable', 'No provider profile was created or inferred by the browser.');

  return appPage('Provider workspace', `
    <section class="dashboard-heading"><div><p class="eyebrow">PROVIDER WORKSPACE</p><h1>Your provider status.</h1><p>This view does not imply approval, verification or payout readiness.</p></div><span class="button button-disabled" aria-disabled="true">Open-request feed — later</span></section>
    <section class="panel"><div class="panel-heading"><div><span>PROVIDER STATUS</span><h2>Readiness</h2></div><span class="status-chip">Read-only</span></div>${statusContent}</section>
    ${mockPaymentBanner()}
    <section class="inline-warning"><strong>Sensitive workflows remain blocked</strong><p>No bids, bookings, earnings, releases or payouts are queried here.</p></section>
  `);
}

function maskPhone(phone) {
  if (!phone) return 'Not provided';
  const value = String(phone);
  return value.length > 4 ? `${value.slice(0, 3)}••••${value.slice(-2)}` : '••••';
}

function readField(label, value, note = 'Read-only') {
  return `<div class="read-field"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value ?? 'Not provided')}</strong><small>${escapeHtml(note)}</small></div>`;
}

function settingsPage(view) {
  if (view.access?.kind !== 'allowed') {
    return appPage('Settings', `<section class="dashboard-heading"><div><p class="eyebrow">PROFILE & SETTINGS</p><h1>Read-only account view.</h1></div></section>${accessState(view.access)}`);
  }
  if (view.settingsProfile?.ok === false || !view.settingsProfile?.data) {
    return appPage('Settings', `<section class="dashboard-heading"><div><p class="eyebrow">PROFILE & SETTINGS</p><h1>Read-only account view.</h1></div></section>${accessState({ kind: 'error' })}`);
  }
  const profile = view.settingsProfile.data;
  const provider = view.providerStatus?.data;
  return appPage('Settings', `
    <section class="dashboard-heading compact-heading"><div><p class="eyebrow">PROFILE & SETTINGS</p><h1>Read-only account view.</h1><p>Role and account status come only from the protected profile row.</p></div><span class="read-only-pill">Read-only</span></section>
    <section class="settings-grid"><article class="panel"><div class="panel-heading"><div><span>PERSONAL</span><h2>Profile</h2></div></div><div class="read-grid">${readField('Display name', profile.display_name)}${readField('Phone', maskPhone(profile.phone_e164))}${readField('Suburb', profile.suburb)}${readField('City', profile.city)}${readField('Role', profile.role, 'Server-owned')}${readField('Account status', profile.account_status, 'Server-owned')}</div></article><article class="panel"><div class="panel-heading"><div><span>PROVIDER</span><h2>Business status</h2></div></div><div class="read-grid">${provider ? `${readField('Business name', provider.business_name)}${readField('Service radius', provider.service_radius_km)}${readField('Verification', provider.verification_status, 'Server-owned')}${readField('Review status', provider.review_status, 'Admin-owned')}` : readField('Provider profile', 'Not applicable')}</div></article></section>
    <section class="inline-warning"><strong>Editing is unavailable</strong><p>No direct profile or provider-profile writes are permitted.</p></section>
  `);
}

function accessDeniedPage(view) {
  const message = view.access?.kind === 'missingProfile'
    ? 'Your sign-in exists, but application setup is unavailable. No browser-side profile was created.'
    : 'The frontend cannot grant or infer access for this account.';
  return publicPage(`<section class="narrow-page"><p class="eyebrow">ACCESS DENIED</p><h1>This area is not available.</h1>${pageState('error', 'Permission required', message, '/')}</section>`, 'content-main', view);
}

function accountRestrictedPage(view) {
  const status = ['restricted', 'suspended', 'closed'].includes(view.accountStatus) ? view.accountStatus : 'restricted';
  return publicPage(`<section class="narrow-page"><p class="eyebrow">ACCOUNT RESTRICTED</p><h1>Account access is limited.</h1>${pageState('restricted', `Account ${status}`, 'The backend remains authoritative. This page offers no bypass or status change.')}<button class="button button-secondary" type="button" data-auth-action="sign-out">Sign out</button></section>`, 'content-main', view);
}

function notFoundPage(view) {
  return publicPage(`<section class="narrow-page"><p class="eyebrow">NOT FOUND</p><h1>That page is not available.</h1>${pageState('notFound', 'Page unavailable', 'Check the address or return to the public landing page.', '/')}</section>`, 'content-main', view);
}

export function renderRoute(pathname, searchParams = new URLSearchParams(), view = {}) {
  const path = normalizePath(pathname);
  if (path === '/') return landingPage(view);
  if (path === '/services') return servicesPage(searchParams, view);
  if (authCopy[path]) return authPage(path, view);
  if (path === '/auth/callback') return authCallbackPage(view);
  if (path === '/app/customer') return customerDashboard(view);
  if (path === '/app/provider') return providerDashboard(view);
  if (path === '/app/settings') return settingsPage(view);
  if (path === '/access-denied') return accessDeniedPage(view);
  if (path === '/account-restricted') return accountRestrictedPage(view);
  return notFoundPage(view);
}
