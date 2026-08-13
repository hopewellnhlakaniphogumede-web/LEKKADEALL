import { REQUEST_PRIVACY_WARNING } from './request-draft.js';
import {
  CUSTOMER_REQUEST_STATUSES,
  activeCategoryLabel,
  customerRequestDetailHref,
  customerRequestEditHref,
  customerRequestStatusLabel,
  formatSastDateTime,
  formatZarBudgetMinor,
  isAllowedCustomerRequestStatus,
  isCustomerRequestId,
} from './customer-requests.js';
import {
  DRAFT_CANCELLATION_CONFIRM_TEXT,
  DRAFT_CANCELLATION_CONFIRM_TITLE,
} from './request-cancellation.js';
import {
  DRAFT_PUBLICATION_CONFIRM_TEXT,
  DRAFT_PUBLICATION_CONFIRM_TITLE,
} from './request-publication.js';
import {
  PROVIDER_APPLICATION_CONFIRM_TEXT,
  PROVIDER_APPLICATION_CONFIRM_TITLE,
  PROVIDER_APPLICATION_TERMS_VERSION,
} from './provider-application.js';
import { PROVIDER_DISCOVERY_UNAVAILABLE_MESSAGE } from './provider-discovery.js';

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
  '/app/customer/requests',
  '/app/customer/requests/detail',
  '/app/customer/requests/edit',
  '/app/customer/requests/new',
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
      <div class="app-context"><span>Protected marketplace access</span><strong>${escapeHtml(section)}</strong></div>
      <nav class="app-nav" aria-label="Application navigation">
        <a href="/app/customer" data-nav>Customer</a>
        <a href="/app/customer/requests" data-nav>Requests</a>
        <a href="/app/provider" data-nav>Provider</a>
        <a href="/app/settings" data-nav>Settings</a>
        <button type="button" data-auth-action="sign-out">Sign out</button>
      </nav>
    </div></header>`;
}

function footer() {
  return `
    <footer class="site-footer">
      <div>${brand()}<p>A careful account and marketplace layer for local services.</p></div>
      <div class="footer-links"><a href="/services" data-nav>Services</a><a href="/auth/sign-in" data-nav>Sign in</a><span>South Africa</span></div>
      <small>Ticket 9A-6. No real payments, publication, or sensitive marketplace actions are connected.</small>
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
        <p class="hero-note">This release creates private drafts only; it does not publish requests, accept bids or process payments.</p>
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

function providerApplicationFieldError(name, errors = {}) {
  return errors[name]
    ? `<small id="provider-${escapeHtml(name)}-error" class="field-error">${escapeHtml(errors[name])}</small>`
    : '';
}

function providerApplicationPanel(view) {
  if (view.access?.role !== 'customer' || view.accountStatus !== 'active') return '';
  const application = view.providerApplication ?? {};
  let content;
  if (application.loadStatus === 'loading' || application.loadStatus === 'idle') {
    content = pageState('loading', 'Checking application eligibility', 'Fresh protected account and provider-status reads are required.');
  } else if (application.loadStatus !== 'eligible') {
    content = pageState('empty', 'Provider application unavailable', 'This account is not eligible for the controlled provider application flow.');
  } else if (application.blocked) {
    content = `<p class="form-message" role="status">${escapeHtml(application.message)}</p>`;
  } else if (application.confirming) {
    content = `<section class="draft-cancellation-confirmation provider-application-confirmation" role="alertdialog" aria-labelledby="provider-application-confirm-title" aria-describedby="provider-application-confirm-description">
      <h3 id="provider-application-confirm-title">${escapeHtml(PROVIDER_APPLICATION_CONFIRM_TITLE)}</h3>
      <p id="provider-application-confirm-description">${escapeHtml(PROVIDER_APPLICATION_CONFIRM_TEXT)}</p>
      <form data-provider-application-confirm-form>
        <button class="button button-secondary" type="button" data-provider-application-action="edit" ${application.submitting ? 'disabled' : ''}>Review details</button>
        <button class="button button-primary" type="submit" ${application.submitting ? 'disabled' : ''}>${application.submitting ? 'Submitting application...' : 'Submit provider application'}</button>
      </form>
    </section>`;
  } else {
    const values = application.values ?? {};
    const errors = application.errors ?? {};
    const categoryIds = new Set(values.categoryIds ?? []);
    const categoryOptions = (view.categories ?? []).map((category) => `<label><input name="category" type="checkbox" value="${escapeHtml(category.id)}" ${categoryIds.has(category.id) ? 'checked' : ''}>${escapeHtml(category.name)}</label>`).join('');
    content = `<form class="request-form provider-application-form" data-provider-application-form autocomplete="off" novalidate>
      <div class="form-field-grid">
        <label class="full-field">Business name<input name="business-name" type="text" minlength="3" maxlength="120" value="${escapeHtml(values.businessName ?? '')}" required>${providerApplicationFieldError('businessName', errors)}</label>
        <label>Service radius in kilometres<input name="service-radius-km" type="number" min="1" max="250" step="1" value="${escapeHtml(values.serviceRadiusKm ?? '')}" required>${providerApplicationFieldError('serviceRadiusKm', errors)}</label>
      </div>
      <fieldset><legend>Proposed service categories</legend><div class="category-choice-grid">${categoryOptions}</div>${providerApplicationFieldError('categoryIds', errors)}</fieldset>
      <label class="full-field"><input name="accept-terms" type="checkbox" value="accepted" ${values.acceptedTerms ? 'checked' : ''}>I accept provider application terms ${escapeHtml(PROVIDER_APPLICATION_TERMS_VERSION)}.</label>
      ${providerApplicationFieldError('acceptedTerms', errors)}
      <p class="form-message" role="status">${escapeHtml(application.message ?? '')}</p>
      <button class="button button-primary" type="submit">Review provider application</button>
    </form>`;
  }

  return `<section class="panel provider-application-panel"><div class="panel-heading"><div><span>PROVIDER APPLICATION</span><h2>Apply to provide services</h2></div><span class="status-chip">Controlled review</span></div><p>Applications remain pending and unverified until separately reviewed. No provider marketplace capability is granted here.</p>${content}</section>`;
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
    : dataList(requests, (request) => `<article><span>${escapeHtml(request.status)}</span><strong>${escapeHtml(request.title)}</strong><small>${escapeHtml(request.suburb)}, ${escapeHtml(request.city)}</small></article>`, 'No requests to show', 'Create a private draft when you are ready.');
  const bookingContent = view.customer?.bookings?.ok === false
    ? pageState('error', 'Bookings unavailable', 'No broader booking query was attempted.')
    : dataList(bookings, (booking) => `<article><span>${escapeHtml(booking.status)}</span><strong>${escapeHtml(booking.public_reference)}</strong><small>${formatMoney(booking.service_amount_minor, booking.currency)}</small></article>`, 'No bookings to show', 'Booking actions and completion are intentionally not implemented.');

  return appPage('Customer workspace', `
    <section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER WORKSPACE</p><h1>Your safe account view.</h1><p>Only RLS-protected request, booking and sandbox-payment summaries are read.</p></div><div class="dashboard-actions"><a class="button button-secondary" href="/app/customer/requests" data-nav>View all requests</a><a class="button button-primary" href="/app/customer/requests/new" data-nav>Create request draft</a></div></section>
    <section class="metrics-grid" aria-label="Customer summary"><div>${metricCard('Requests', String(requests.length), 'Own rows only')}</div><div>${metricCard('Bookings', String(bookings.length), 'Booking-party rows only')}</div><div>${metricCard('Payments', String(payments.length), 'Read-only sandbox statuses')}</div></section>
    ${mockPaymentBanner()}
    <section class="dashboard-grid"><article class="panel"><div class="panel-heading"><div><span>REQUESTS</span><h2>Your requests</h2></div><span class="status-chip">Read-only</span></div>${requestContent}</article><article class="panel"><div class="panel-heading"><div><span>BOOKINGS</span><h2>Your timeline</h2></div><span class="status-chip">Read-only</span></div>${bookingContent}</article></section>
    ${providerApplicationPanel(view)}
  `);
}

function customerRequestSummary(request, categories) {
  const detailHref = customerRequestDetailHref(request.id);
  if (!detailHref || !isAllowedCustomerRequestStatus(request.status)) return '';
  const category = activeCategoryLabel(categories, request.category_id);
  return `
    <a class="request-summary-card" href="${escapeHtml(detailHref)}" data-nav>
      <div class="request-summary-top"><span class="status-chip">${escapeHtml(customerRequestStatusLabel(request.status))}</span><time>${escapeHtml(formatSastDateTime(request.created_at))}</time></div>
      <h2>${escapeHtml(request.title)}</h2>
      <p>${escapeHtml(category)} · ${escapeHtml(request.suburb)}, ${escapeHtml(request.city)}</p>
      <dl class="request-summary-meta"><div><dt>Requested start</dt><dd>${escapeHtml(formatSastDateTime(request.requested_start))}</dd></div><div><dt>Budget</dt><dd>${escapeHtml(formatZarBudgetMinor(request.budget_minor))}</dd></div></dl>
      <span class="request-summary-link">View request <span aria-hidden="true">→</span></span>
    </a>`;
}

function customerRequestListPage(view) {
  if (view.access?.kind !== 'allowed' || view.access?.role !== 'customer') {
    const deniedAccess = view.access?.kind === 'allowed' ? { kind: 'accessDenied' } : view.access;
    return appPage('Your requests', `<section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUESTS</p><h1>Your requests.</h1></div></section>${accessState(deniedAccess)}`);
  }

  let content;
  if (!view.customerRequestList) {
    content = pageState('loading', 'Loading your requests', 'Only your RLS-visible draft, open, and cancelled requests will be shown.');
  } else if (!view.customerRequestList.ok) {
    content = pageState('error', 'Requests are unavailable right now', 'No broader read or elevated fallback was attempted.');
  } else {
    const requests = (view.customerRequestList.data ?? [])
      .filter((request) => isAllowedCustomerRequestStatus(request?.status));
    content = requests.length
      ? `<section class="request-list" aria-label="Your requests">${requests.map((request) => customerRequestSummary(request, view.categories)).join('')}</section>`
      : pageState('empty', 'No requests to show', 'Create a private draft when you are ready.');
  }

  return appPage('Your requests', `
    <section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUESTS</p><h1>Your requests.</h1><p>Newest first · up to 20 own rows · ${escapeHtml(CUSTOMER_REQUEST_STATUSES.join(', '))} only.</p></div><div class="dashboard-actions"><a class="button button-secondary" href="/app/customer" data-nav>Customer dashboard</a><a class="button button-primary" href="/app/customer/requests/new" data-nav>Create request draft</a></div></section>
    ${content}
    <section class="inline-warning request-boundary-note"><strong>Read-only request history</strong><p>Editing, cancellation, publication, exact-address handling, provider bidding and payment actions are not available here.</p></section>
  `);
}

function customerRequestDetailPage(view) {
  if (view.access?.kind !== 'allowed' || view.access?.role !== 'customer') {
    const deniedAccess = view.access?.kind === 'allowed' ? { kind: 'accessDenied' } : view.access;
    return appPage('Request details', `<section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUEST</p><h1>Request details.</h1></div></section>${accessState(deniedAccess)}`);
  }

  const result = view.customerRequestDetail;
  if (!result) {
    return appPage('Request details', `<section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUEST</p><h1>Request details.</h1></div><a class="button button-secondary" href="/app/customer/requests" data-nav>View all requests</a></section>${pageState('loading', 'Loading request', 'The request ID is validated before the RLS-backed read.')}`);
  }
  if (!result.ok || !result.data || !isAllowedCustomerRequestStatus(result.data.status)) {
    return appPage('Request details', `<section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUEST</p><h1>Request details.</h1></div><a class="button button-secondary" href="/app/customer/requests" data-nav>View all requests</a></section>${pageState('notFound', 'Request not found or unavailable', 'The request could not be shown from this account and route.', '/app/customer/requests')}`);
  }

  const request = result.data;
  const category = activeCategoryLabel(view.categories, request.category_id);
  const cancellation = view.customerDraftCancellation ?? {};
  const publication = view.customerDraftPublication ?? {};
  const editHref = customerRequestEditHref(request.id);
  let draftActionsContent = '';
  if (publication.message) {
    draftActionsContent = `<p class="draft-cancellation-message draft-publication-message ${publication.confirmed ? 'is-success' : ''}" role="status">${escapeHtml(publication.message)}</p>`;
  }
  if (cancellation.message) {
    draftActionsContent += `<p class="draft-cancellation-message ${cancellation.confirmed ? 'is-success' : ''}" role="status">${escapeHtml(cancellation.message)}</p>`;
  }
  if (request.status === 'draft') {
    if (publication.confirming && !publication.blocked) {
      draftActionsContent += `<section class="draft-cancellation-confirmation draft-publication-confirmation" role="alertdialog" aria-labelledby="publish-draft-title" aria-describedby="publish-draft-description">
          <h2 id="publish-draft-title">${escapeHtml(DRAFT_PUBLICATION_CONFIRM_TITLE)}</h2>
          <p id="publish-draft-description">${escapeHtml(DRAFT_PUBLICATION_CONFIRM_TEXT)}</p>
          <form data-publish-draft-form>
            <button class="button button-secondary" type="button" data-publish-draft-action="keep" ${publication.submitting ? 'disabled' : ''}>Keep draft</button>
            <button class="button button-primary" type="submit" ${publication.submitting ? 'disabled' : ''}>${publication.submitting ? 'Publishing requestâ€¦' : 'Publish request'}</button>
          </form>
        </section>`;
    } else if (cancellation.confirming && !cancellation.blocked) {
      draftActionsContent += `<section class="draft-cancellation-confirmation" role="alertdialog" aria-labelledby="cancel-draft-title" aria-describedby="cancel-draft-description">
          <h2 id="cancel-draft-title">${escapeHtml(DRAFT_CANCELLATION_CONFIRM_TITLE)}</h2>
          <p id="cancel-draft-description">${escapeHtml(DRAFT_CANCELLATION_CONFIRM_TEXT)}</p>
          <form data-cancel-draft-form>
            <button class="button button-secondary" type="button" data-cancel-draft-action="keep" ${cancellation.submitting ? 'disabled' : ''}>Keep draft</button>
            <button class="button button-danger" type="submit" ${cancellation.submitting ? 'disabled' : ''}>${cancellation.submitting ? 'Cancelling draftâ€¦' : 'Cancel draft'}</button>
          </form>
        </section>`;
    } else if (!publication.blocked) {
      const cancellationButton = cancellation.blocked
        ? ''
        : '<button class="button button-danger-outline" type="button" data-cancel-draft-action="open">Cancel draft</button>';
      const publicationButton = cancellation.blocked
        ? ''
        : '<button class="button button-primary" type="button" data-publish-draft-action="open">Publish request</button>';
      draftActionsContent += `<section class="draft-cancellation-control" aria-label="Draft actions">
          <div><h2>Draft actions</h2><p>Editing, cancellation and publication are enforced as draft-only by the database.</p></div>
          <div class="draft-action-buttons"><a class="button button-primary" href="${escapeHtml(editHref)}" data-nav>Edit draft</a>${cancellationButton}${publicationButton}</div>
        </section>`;
    }
  }
  return appPage('Request details', `
    <section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUEST</p><h1>${escapeHtml(request.title)}</h1><p>Protected details returned through your existing RLS boundary.</p></div><a class="button button-secondary" href="/app/customer/requests" data-nav>View all requests</a></section>
    <article class="request-detail-card">
      <div class="request-detail-status"><span class="status-chip">${escapeHtml(customerRequestStatusLabel(request.status))}</span><span>${escapeHtml(category)}</span></div>
      <section class="request-detail-description"><h2>Public description</h2><p>${escapeHtml(request.description)}</p></section>
      <dl class="request-detail-grid">
        <div><dt>Suburb</dt><dd>${escapeHtml(request.suburb)}</dd></div>
        <div><dt>City</dt><dd>${escapeHtml(request.city)}</dd></div>
        <div><dt>Requested start</dt><dd>${escapeHtml(formatSastDateTime(request.requested_start))}</dd></div>
        <div><dt>Budget</dt><dd>${escapeHtml(formatZarBudgetMinor(request.budget_minor))}</dd></div>
        <div><dt>Created</dt><dd>${escapeHtml(formatSastDateTime(request.created_at))}</dd></div>
        <div><dt>Updated</dt><dd>${escapeHtml(formatSastDateTime(request.updated_at))}</dd></div>
      </dl>
    </article>
    ${draftActionsContent}
    <section class="inline-warning request-boundary-note"><strong>Strict workflow boundary</strong><p>Only an owned eligible draft may be edited, cancelled or published. Exact-address handling, provider bidding and payment actions remain unavailable.</p></section>
  `);
}

function requestFieldError(name, errors = {}) {
  return errors[name]
    ? `<small id="${escapeHtml(name)}-error" class="field-error">${escapeHtml(errors[name])}</small>`
    : '';
}

function requestDraftForm(view, mode = 'create') {
  const isEdit = mode === 'edit';
  const draft = isEdit ? (view.customerDraftEdit ?? {}) : (view.requestDraft ?? {});
  const values = draft.values ?? {};
  const errors = draft.errors ?? {};
  const disabled = draft.submitting || draft.blocked;
  const options = (view.categories ?? []).map((category) => `
    <option value="${escapeHtml(category.id)}" ${values.category === category.id ? 'selected' : ''}>${escapeHtml(category.name)}</option>`).join('');

  return `
    <form class="request-form" ${isEdit ? 'data-draft-edit-form' : 'data-draft-request-form'} autocomplete="off" novalidate>
      <section class="request-form-section">
        <div class="section-number">01</div><div><h2>Choose a service</h2><p>Only active service categories are available.</p></div>
        <label class="full-field">Service category<select name="category" required ${disabled ? 'disabled' : ''}><option value="">Choose a category</option>${options}</select>${requestFieldError('category', errors)}</label>
      </section>
      <section class="request-form-section">
        <div class="section-number">02</div><div><h2>Describe the public job</h2><p>Use general work details only.</p></div>
        <aside class="privacy-warning" role="note"><strong>Public information warning</strong><p>${escapeHtml(REQUEST_PRIVACY_WARNING)}</p></aside>
        <div class="form-field-grid">
          <label class="full-field">Public job title<input name="title" type="text" minlength="3" maxlength="120" value="${escapeHtml(values.title ?? '')}" required ${disabled ? 'disabled' : ''}>${requestFieldError('title', errors)}</label>
          <label class="full-field">Public description<textarea name="description" minlength="10" maxlength="3000" rows="7" required ${disabled ? 'disabled' : ''}>${escapeHtml(values.description ?? '')}</textarea>${requestFieldError('description', errors)}</label>
        </div>
      </section>
      <section class="request-form-section">
        <div class="section-number">03</div><div><h2>Add the approximate area</h2><p>Suburb and city only.</p></div>
        <div class="form-field-grid">
          <label>Suburb only<input name="suburb" type="text" minlength="2" maxlength="120" value="${escapeHtml(values.suburb ?? '')}" required ${disabled ? 'disabled' : ''}>${requestFieldError('suburb', errors)}</label>
          <label>City only<input name="city" type="text" minlength="2" maxlength="120" value="${escapeHtml(values.city ?? '')}" required ${disabled ? 'disabled' : ''}>${requestFieldError('city', errors)}</label>
        </div>
      </section>
      <section class="request-form-section">
        <div class="section-number">04</div><div><h2>Schedule and budget</h2><p>The requested start is entered in South Africa time.</p></div>
        <div class="form-field-grid">
          <label>Requested start — South Africa time (SAST, UTC+2)<input name="requested-start" type="datetime-local" value="${escapeHtml(values.requestedStart ?? '')}" required ${disabled ? 'disabled' : ''}>${requestFieldError('requestedStart', errors)}</label>
          <label>Optional budget in ZAR<input name="budget" type="text" inputmode="decimal" placeholder="1500.00" value="${escapeHtml(values.budget ?? '')}" ${disabled ? 'disabled' : ''}>${requestFieldError('budget', errors)}</label>
        </div>
      </section>
      <section class="request-review">
        <p>${escapeHtml(REQUEST_PRIVACY_WARNING)}</p>
        <div class="blocked-notice"><strong>Draft only</strong><span>Publishing and the private exact-address step are not available until the encryption boundary is verified.</span></div>
        <button class="button button-primary" type="submit" ${disabled ? 'disabled' : ''}>${draft.submitting ? (isEdit ? 'Saving draft…' : 'Creating draft…') : (isEdit ? 'Save draft changes' : 'Create private draft')}</button>
        <p class="form-message ${draft.confirmed ? 'is-success' : ''}" ${isEdit ? 'data-draft-edit-message' : 'data-draft-message'} role="status">${escapeHtml(draft.message ?? '')}</p>
      </section>
    </form>`;
}

function customerRequestEditPage(view) {
  if (view.access?.kind !== 'allowed' || view.access?.role !== 'customer') {
    const deniedAccess = view.access?.kind === 'allowed' ? { kind: 'accessDenied' } : view.access;
    return appPage('Edit request draft', `<section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUEST</p><h1>Edit a private draft.</h1></div></section>${accessState(deniedAccess)}`);
  }

  const edit = view.customerDraftEdit;
  const listAction = '<a class="button button-secondary" href="/app/customer/requests" data-nav>View all requests</a>';
  if (!edit || edit.loadStatus === 'loading') {
    return appPage('Edit request draft', `<section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUEST</p><h1>Edit a private draft.</h1></div>${listAction}</section>${pageState('loading', 'Loading draft', 'The request ID is validated before a fresh draft-only RLS read.')}`);
  }
  if (edit.loadStatus !== 'ready' || !edit.request || edit.request.status !== 'draft') {
    return appPage('Edit request draft', `<section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUEST</p><h1>Edit a private draft.</h1></div>${listAction}</section>${pageState('notFound', 'Draft not found or unavailable', 'This draft is not available for editing.', '/app/customer/requests')}`);
  }
  if (view.categoriesStatus === 'error' || !view.categories?.length) {
    return appPage('Edit request draft', `<section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUEST</p><h1>Edit a private draft.</h1></div>${listAction}</section>${pageState('error', 'Categories are unavailable', 'The draft cannot be edited without the active category allowlist.')}`);
  }

  return appPage('Edit request draft', `
    <section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUEST</p><h1>Edit your private draft.</h1><p>The complete reviewed field set will be validated again by the database. This action cannot change workflow status.</p></div><a class="button button-secondary" href="${escapeHtml(customerRequestDetailHref(edit.requestId))}" data-nav>Back to draft</a></section>
    ${requestDraftForm(view, 'edit')}
  `);
}

function customerRequestCreatePage(view) {
  if (view.access?.kind !== 'allowed' || view.access?.role !== 'customer') {
    const deniedAccess = view.access?.kind === 'allowed' ? { kind: 'accessDenied' } : view.access;
    return appPage('Create request draft', `<section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUEST</p><h1>Create a private draft.</h1></div></section>${accessState(deniedAccess)}`);
  }
  if (isCustomerRequestId(view.requestDraft?.requestId)) {
    const detailHref = customerRequestDetailHref(view.requestDraft.requestId);
    return appPage('Create request draft', `
      <section class="draft-created"><p class="eyebrow">DRAFT CREATED</p><h1>Your request draft is saved.</h1><p>The trusted backend confirmed the request. It remains a private draft.</p><div class="blocked-notice"><strong>Publishing remains unavailable</strong><span>Exact-address collection and publishing are blocked until the encryption boundary is verified.</span></div><div class="draft-created-actions"><a class="button button-primary" href="${escapeHtml(detailHref)}" data-nav>View draft</a><a class="button button-secondary" href="/app/customer/requests" data-nav>View all requests</a></div></section>`);
  }
  let content;
  if (view.categoriesStatus === 'loading' || view.categoriesStatus === 'idle') {
    content = pageState('loading', 'Loading active categories', 'The form will open after the safe category read completes.');
  } else if (view.categoriesStatus === 'error') {
    content = pageState('error', 'Categories are unavailable', 'No draft can be created without an active category.');
  } else if (!view.categories?.length) {
    content = pageState('empty', 'No active categories', 'Draft creation is unavailable until an active category exists.');
  } else {
    content = requestDraftForm(view);
  }
  return appPage('Create request draft', `
    <section class="dashboard-heading"><div><p class="eyebrow">CUSTOMER REQUEST</p><h1>Create a private draft.</h1><p>This workflow creates a draft only. It cannot publish, collect an exact address, or contact providers.</p></div><a class="button button-secondary" href="/app/customer" data-nav>Back to dashboard</a></section>${content}`);
}

function providerDashboard(view) {
  if (view.access?.kind !== 'allowed') {
    return appPage('Provider workspace', `<section class="dashboard-heading"><div><p class="eyebrow">PROVIDER WORKSPACE</p><h1>A clear view of readiness.</h1></div></section>${accessState(view.access)}${mockPaymentBanner()}`);
  }
  const status = view.providerStatus;
  const applicationMessage = view.providerApplication?.confirmed
    ? `<p class="form-message is-success" data-provider-application-message role="status">${escapeHtml(view.providerApplication.message)}</p>`
    : '';
  const statusContent = status?.ok === false
    ? pageState('error', 'Provider status unavailable', 'No broader provider query was attempted.')
    : status?.data
      ? `<div class="read-grid"><div class="read-field"><span>Business</span><strong>${escapeHtml(status.data.business_name)}</strong><small>Read-only</small></div><div class="read-field"><span>Verification</span><strong>${escapeHtml(status.data.verification_status)}</strong><small>Server-owned</small></div><div class="read-field"><span>Review</span><strong>${escapeHtml(status.data.review_status)}</strong><small>Admin-owned</small></div><div class="read-field"><span>Service radius</span><strong>${escapeHtml(status.data.service_radius_km ?? 'Not set')}</strong><small>Read-only</small></div></div>`
      : pageState('empty', 'Provider setup unavailable', 'No provider profile was created or inferred by the browser.');
  const discovery = view.providerDiscovery ?? {};
  let discoveryContent;
  if (discovery.status === 'loading' || discovery.status === 'idle') {
    discoveryContent = pageState('loading', 'Loading discoverable requests', 'The server is checking current provider eligibility and active service matches.');
  } else if (discovery.status === 'unavailable') {
    discoveryContent = pageState('error', 'Request discovery unavailable', PROVIDER_DISCOVERY_UNAVAILABLE_MESSAGE);
  } else if (discovery.status === 'empty') {
    discoveryContent = pageState('empty', 'No requests to show', 'No currently discoverable request matched the server-authorized service set.');
  } else {
    const requests = Array.isArray(discovery.items) ? discovery.items : [];
    discoveryContent = requests.length
      ? `<section class="request-list" aria-label="Discoverable requests">${requests.map((request) => `
          <article class="request-summary-card provider-discovery-card">
            <div class="request-summary-top"><span class="status-chip">Open request</span><time>${escapeHtml(formatSastDateTime(request.published_at))}</time></div>
            <h2>${escapeHtml(request.title)}</h2>
            <p>${escapeHtml(request.description)}</p>
            <dl class="request-summary-meta">
              <div><dt>Suburb</dt><dd>${escapeHtml(request.suburb)}</dd></div>
              <div><dt>City</dt><dd>${escapeHtml(request.city)}</dd></div>
              <div><dt>Requested start</dt><dd>${escapeHtml(formatSastDateTime(request.requested_start))}</dd></div>
              <div><dt>Budget</dt><dd>${escapeHtml(formatZarBudgetMinor(request.budget_minor))}</dd></div>
              <div><dt>Closes</dt><dd>${escapeHtml(formatSastDateTime(request.closes_at))}</dd></div>
              <div><dt>Published</dt><dd>${escapeHtml(formatSastDateTime(request.published_at))}</dd></div>
              <div><dt>Category reference</dt><dd>${escapeHtml(request.category_id)}</dd></div>
              <div><dt>Request reference</dt><dd>${escapeHtml(request.request_id)}</dd></div>
            </dl>
          </article>`).join('')}</section>`
      : pageState('empty', 'No requests to show', 'No currently discoverable request matched the server-authorized service set.');
    if (discovery.hasMore) {
      discoveryContent += `<div class="dashboard-actions"><button class="button button-secondary" type="button" data-provider-discovery-action="load-more" ${discovery.loadingMore ? 'disabled' : ''}>${discovery.loadingMore ? 'Loading requests…' : 'Load more'}</button></div>`;
    }
  }

  return appPage('Provider workspace', `
    <section class="dashboard-heading"><div><p class="eyebrow">PROVIDER WORKSPACE</p><h1>Your provider status.</h1><p>This view does not imply approval, verification or payout readiness.</p></div><button class="button button-secondary" type="button" data-provider-discovery-action="refresh" ${discovery.status === 'loading' || discovery.loadingMore ? 'disabled' : ''}>Refresh requests</button></section>
    ${applicationMessage}
    <section class="panel"><div class="panel-heading"><div><span>PROVIDER STATUS</span><h2>Readiness</h2></div><span class="status-chip">Read-only</span></div>${statusContent}</section>
    <section class="panel" data-provider-discovery><div class="panel-heading"><div><span>PROVIDER DISCOVERY</span><h2>Matching open requests</h2></div><span class="status-chip">Server-authorized</span></div>${discoveryContent}</section>
    ${mockPaymentBanner()}
    <section class="inline-warning"><strong>Discovery remains read-only</strong><p>No customer contact, exact address, bid, booking, message, payment or payout action is queried or available here.</p></section>
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
  if (path === '/app/customer/requests') return customerRequestListPage(view);
  if (path === '/app/customer/requests/detail') return customerRequestDetailPage(view);
  if (path === '/app/customer/requests/edit') return customerRequestEditPage(view);
  if (path === '/app/customer/requests/new') return customerRequestCreatePage(view);
  if (path === '/app/provider') return providerDashboard(view);
  if (path === '/app/settings') return settingsPage(view);
  if (path === '/access-denied') return accessDeniedPage(view);
  if (path === '/account-restricted') return accountRestrictedPage(view);
  return notFoundPage(view);
}
