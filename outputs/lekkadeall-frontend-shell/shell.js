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
        <span>Payment and release information in this shell is illustrative only.</span>
      </div>
    </aside>`;
}

export function pageState(kind, title, message, action = '') {
  const symbols = { loading: '···', empty: '○', error: '!', signedOut: '→', restricted: '—', notFound: '?' };
  const actionMarkup = action
    ? `<a class="button button-secondary" href="${action}" data-nav>Continue</a>`
    : '';
  return `
    <section class="page-state page-state-${kind}" data-state="${kind}" aria-busy="${kind === 'loading'}">
      <span class="state-symbol" aria-hidden="true">${symbols[kind] ?? '○'}</span>
      <div>
        <h2>${title}</h2>
        <p>${message}</p>
        ${actionMarkup}
      </div>
    </section>`;
}

function brand() {
  return `<a class="brand" href="/" data-nav aria-label="LEKKADEALL home"><span>LD</span><b>LEKKADEALL</b></a>`;
}

function publicHeader() {
  return `
    <header class="site-header">
      <div class="header-inner">
        ${brand()}
        <button class="menu-toggle" type="button" data-menu-toggle aria-expanded="false" aria-controls="primary-nav">Menu</button>
        <nav id="primary-nav" class="primary-nav" aria-label="Primary navigation">
          <a href="/services" data-nav>Browse services</a>
          <a href="/app/customer" data-nav>Customer</a>
          <a href="/app/provider" data-nav>Provider</a>
          <a class="nav-sign-in" href="/auth/sign-in" data-nav>Sign in</a>
        </nav>
      </div>
    </header>`;
}

function appHeader(section) {
  return `
    <header class="app-header">
      <div class="header-inner">
        ${brand()}
        <div class="app-context"><span>Preview shell</span><strong>${section}</strong></div>
        <nav class="app-nav" aria-label="Application navigation">
          <a href="/app/customer" data-nav>Customer</a>
          <a href="/app/provider" data-nav>Provider</a>
          <a href="/app/settings" data-nav>Settings</a>
          <a href="/" data-nav>Exit preview</a>
        </nav>
      </div>
    </header>`;
}

function footer() {
  return `
    <footer class="site-footer">
      <div>${brand()}<p>A careful first shell for local service bookings.</p></div>
      <div class="footer-links"><a href="/services" data-nav>Services</a><a href="/auth/sign-in" data-nav>Sign in</a><span>South Africa</span></div>
      <small>Ticket 9A-1 preview. No real payments or sensitive workflows are connected.</small>
    </footer>`;
}

function publicPage(content, className = '') {
  return `${publicHeader()}<main id="main-content" class="${className}">${content}</main>${footer()}`;
}

function appPage(section, content) {
  return `${appHeader(section)}<main id="main-content" class="app-main">${content}</main>`;
}

function landingPage() {
  return publicPage(`
    <section class="hero-section">
      <div class="hero-copy">
        <p class="eyebrow">LOCAL SERVICES · CLEARLY ARRANGED</p>
        <h1>Good work starts with a <em>clear request.</em></h1>
        <p class="hero-lead">LEKKADEALL is being built to help customers describe a job, compare offers and keep every step easy to follow.</p>
        <div class="hero-actions">
          <a class="button button-primary" href="/services" data-nav>Browse services <span aria-hidden="true">→</span></a>
          <a class="button button-secondary" href="/auth/register" data-nav>Create an account</a>
        </div>
        <p class="hero-note">This first shell does not create requests, accept bids or process payments.</p>
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

    <section class="trust-strip" aria-label="Current shell boundaries">
      <article><span>01</span><strong>Private by design</strong><p>Exact addresses are not collected or displayed in this shell.</p></article>
      <article><span>02</span><strong>Read before write</strong><p>Dashboards begin with safe placeholders while read models are prepared.</p></article>
      <article><span>03</span><strong>Honest payment state</strong><p>There is no real checkout, cash option or off-platform payment flow.</p></article>
    </section>

    <section class="split-section">
      <div>
        <p class="eyebrow">THE FIRST SAFE LAYER</p>
        <h2>Useful structure now.<br> Sensitive actions later.</h2>
      </div>
      <div class="boundary-copy">
        <p>This release establishes navigation, authentication shells, customer and provider workspaces, and clear system states without pretending that unfinished marketplace capabilities are live.</p>
        ${mockPaymentBanner()}
      </div>
    </section>

    <section class="role-cards">
      <a href="/app/customer" data-nav><span>CUSTOMER SHELL</span><h3>Keep requests and bookings in one calm view.</h3><b>Preview customer workspace →</b></a>
      <a href="/app/provider" data-nav><span>PROVIDER SHELL</span><h3>See readiness, opportunities and work at a glance.</h3><b>Preview provider workspace →</b></a>
    </section>
  `, 'landing-main');
}

function servicesPage(searchParams) {
  const requestedState = searchParams.get('state');
  const state = ['loading', 'error'].includes(requestedState) ? requestedState : 'empty';
  const states = {
    loading: pageState('loading', 'Loading service categories', 'Only active public categories will be shown here.'),
    error: pageState('error', 'Categories are unavailable', 'Nothing sensitive was loaded. Please try again later.', '/services'),
    empty: pageState('empty', 'Category discovery is ready for data', 'No Supabase browser client exists in the project yet, so this shell does not make a network request.'),
  };
  return publicPage(`
    <section class="page-intro">
      <p class="eyebrow">SERVICE DISCOVERY</p>
      <h1>Find the right starting point.</h1>
      <p>When the public Supabase client is added in a later ticket, this page may read active service categories only.</p>
    </section>
    <section class="filter-shell" aria-label="Service category filters">
      <label><span>Search services</span><input type="search" placeholder="Search will activate with category data" disabled></label>
      <button type="button" disabled>All active categories</button>
    </section>
    ${states[state]}
    <section class="safety-note"><strong>Public-data boundary</strong><p>This screen does not query users, requests, bookings, payments, verification records or exact addresses.</p></section>
  `, 'content-main');
}

const authCopy = {
  '/auth/sign-in': {
    eyebrow: 'WELCOME BACK',
    title: 'Sign in to your workspace.',
    description: 'Authentication is not connected in this shell. Details entered here are not transmitted.',
    fields: '<label>Email address<input name="email" type="email" autocomplete="email" required></label><label>Password<input name="password" type="password" autocomplete="current-password" required></label>',
    submit: 'Sign in',
    links: '<a href="/auth/forgot-password" data-nav>Forgot password?</a><a href="/auth/register" data-nav>Create an account</a>',
  },
  '/auth/register': {
    eyebrow: 'START HERE',
    title: 'Create your account shell.',
    description: 'Registration is not connected yet. No role, approval or verification state can be selected here.',
    fields: '<label>Email address<input name="email" type="email" autocomplete="email" required></label><label>Create password<input name="password" type="password" autocomplete="new-password" minlength="10" required></label>',
    submit: 'Create account',
    links: '<a href="/auth/sign-in" data-nav>Already have an account?</a>',
  },
  '/auth/forgot-password': {
    eyebrow: 'ACCOUNT RECOVERY',
    title: 'Reset access safely.',
    description: 'The connected experience will always return a neutral response to protect account privacy.',
    fields: '<label>Email address<input name="email" type="email" autocomplete="email" required></label>',
    submit: 'Request reset link',
    links: '<a href="/auth/sign-in" data-nav>Back to sign in</a>',
  },
  '/auth/reset-password': {
    eyebrow: 'CHOOSE A NEW PASSWORD',
    title: 'Finish your password reset.',
    description: 'A valid recovery session will be required before this form is connected.',
    fields: '<label>New password<input name="password" type="password" autocomplete="new-password" minlength="10" required></label><label>Confirm new password<input name="password-confirmation" type="password" autocomplete="new-password" minlength="10" required></label>',
    submit: 'Update password',
    links: '<a href="/auth/sign-in" data-nav>Return to sign in</a>',
  },
};

function authPage(pathname) {
  const content = authCopy[pathname];
  return publicPage(`
    <section class="auth-layout">
      <div class="auth-aside">
        <p class="eyebrow">ACCOUNT ACCESS</p>
        <h2>One quiet place for every next step.</h2>
        <ul><li>Customer and provider routes stay separate.</li><li>Unknown access fails closed.</li><li>No privileged state comes from a form.</li></ul>
      </div>
      <div class="auth-card">
        <p class="eyebrow">${content.eyebrow}</p>
        <h1>${content.title}</h1>
        <p>${content.description}</p>
        <form data-shell-form="auth" novalidate>
          ${content.fields}
          <button class="button button-primary" type="submit">${content.submit}</button>
        </form>
        <div class="form-message" data-form-message role="status"></div>
        <div class="auth-links">${content.links}</div>
      </div>
    </section>
  `, 'auth-main');
}

function authCallbackPage() {
  return publicPage(`
    <section class="narrow-page">
      <p class="eyebrow">AUTHENTICATION CALLBACK</p>
      <h1>Checking the sign-in response.</h1>
      ${pageState('loading', 'Validating session', 'No role or account status is accepted from this URL.')}
      <div class="inline-warning"><strong>Shell only</strong><p>No authentication provider is configured, so this preview cannot establish a session.</p></div>
    </section>
  `, 'content-main');
}

function metricCard(label, value, note) {
  return `<article class="metric-card"><span>${label}</span><strong>${value}</strong><small>${note}</small></article>`;
}

function customerDashboard() {
  return appPage('Customer workspace', `
    <section class="dashboard-heading">
      <div><p class="eyebrow">CUSTOMER WORKSPACE</p><h1>Your next job starts here.</h1><p>The secure read model will populate this shell in a later ticket.</p></div>
      <a class="button button-disabled" href="#" aria-disabled="true">New request — coming later</a>
    </section>
    ${pageState('signedOut', 'Sign in required', 'This shell never treats a preview route as proof of identity.', '/auth/sign-in')}
    <section class="metrics-grid" aria-label="Customer summary placeholders">
      ${metricCard('Open requests', '—', 'No customer data loaded')}
      ${metricCard('Upcoming bookings', '—', 'No booking data loaded')}
      ${metricCard('Payment status', '—', 'No payment data loaded')}
    </section>
    ${mockPaymentBanner()}
    <section class="dashboard-grid">
      <article class="panel"><div class="panel-heading"><div><span>REQUESTS</span><h2>Your requests</h2></div><span class="status-chip">Empty</span></div>${pageState('empty', 'No requests to show', 'Request creation is intentionally not part of Ticket 9A-1.')}</article>
      <article class="panel"><div class="panel-heading"><div><span>BOOKINGS</span><h2>Your timeline</h2></div><span class="status-chip">Empty</span></div>${pageState('empty', 'No bookings to show', 'Booking actions and completion are intentionally not connected.')}</article>
    </section>
  `);
}

function providerDashboard() {
  return appPage('Provider workspace', `
    <section class="dashboard-heading">
      <div><p class="eyebrow">PROVIDER WORKSPACE</p><h1>A clear view of work ahead.</h1><p>This shell does not imply provider approval, verification or payout readiness.</p></div>
      <a class="button button-disabled" href="#" aria-disabled="true">Open-request feed — later</a>
    </section>
    ${pageState('signedOut', 'Sign in required', 'Provider access and approval must be confirmed by the secured backend.', '/auth/sign-in')}
    <section class="metrics-grid" aria-label="Provider summary placeholders">
      ${metricCard('Approval', '—', 'No provider status loaded')}
      ${metricCard('Active bids', '—', 'No bid data loaded')}
      ${metricCard('Upcoming work', '—', 'No booking data loaded')}
    </section>
    ${mockPaymentBanner()}
    <section class="dashboard-grid">
      <article class="panel"><div class="panel-heading"><div><span>OPPORTUNITIES</span><h2>Open requests</h2></div><span class="status-chip">Not connected</span></div>${pageState('empty', 'Feed not connected', 'A later ticket will use the safe provider summary function only.')}</article>
      <article class="panel"><div class="panel-heading"><div><span>WORK</span><h2>Booking timeline</h2></div><span class="status-chip">Empty</span></div>${pageState('empty', 'No bookings to show', 'Address reveal and completion actions are not implemented.')}</article>
    </section>
  `);
}

function settingsPage() {
  const field = (label) => `<div class="read-field"><span>${label}</span><strong>Not loaded</strong><small>Read-only</small></div>`;
  return appPage('Settings', `
    <section class="dashboard-heading compact-heading"><div><p class="eyebrow">PROFILE & SETTINGS</p><h1>Read-only account shell.</h1><p>Profile editing waits for a reviewed trusted update function.</p></div><span class="read-only-pill">Read-only</span></section>
    ${pageState('signedOut', 'No profile session', 'Sign in will be required before safe profile fields can be read.', '/auth/sign-in')}
    <section class="settings-grid">
      <article class="panel"><div class="panel-heading"><div><span>PERSONAL</span><h2>Profile</h2></div></div><div class="read-grid">${field('Display name')}${field('Phone')}${field('Suburb')}${field('City')}</div></article>
      <article class="panel"><div class="panel-heading"><div><span>PROVIDER</span><h2>Business profile</h2></div></div><div class="read-grid">${field('Business name')}${field('Service radius')}${field('Verification')}${field('Review status')}</div></article>
    </section>
    <section class="inline-warning"><strong>Editing is unavailable</strong><p>No direct profile or provider-profile writes are permitted by this shell.</p></section>
  `);
}

function accessDeniedPage() {
  return publicPage(`<section class="narrow-page"><p class="eyebrow">ACCESS DENIED</p><h1>This area is not available.</h1>${pageState('error', 'Permission required', 'The shell cannot grant access. Sign in with an authorised account or return home.', '/')}</section>`, 'content-main');
}

function accountRestrictedPage() {
  return publicPage(`<section class="narrow-page"><p class="eyebrow">ACCOUNT RESTRICTED</p><h1>Account access is limited.</h1>${pageState('restricted', 'Actions are unavailable', 'The secured backend remains authoritative. This page does not offer a bypass or status change.') }<a class="button button-secondary" href="/" data-nav>Return home</a></section>`, 'content-main');
}

function notFoundPage() {
  return publicPage(`<section class="narrow-page"><p class="eyebrow">NOT FOUND</p><h1>That page is not part of this shell.</h1>${pageState('notFound', 'Page unavailable', 'Check the address or return to the public landing page.', '/')}</section>`, 'content-main');
}

export function renderRoute(pathname, searchParams = new URLSearchParams()) {
  const path = normalizePath(pathname);
  if (path === '/') return landingPage();
  if (path === '/services') return servicesPage(searchParams);
  if (authCopy[path]) return authPage(path);
  if (path === '/auth/callback') return authCallbackPage();
  if (path === '/app/customer') return customerDashboard();
  if (path === '/app/provider') return providerDashboard();
  if (path === '/app/settings') return settingsPage();
  if (path === '/access-denied') return accessDeniedPage();
  if (path === '/account-restricted') return accountRestrictedPage();
  return notFoundPage();
}
