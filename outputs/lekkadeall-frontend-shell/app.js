import { loadRuntimeConfig, readPublicConfig } from './public-config.js';
import { getPublicSupabaseClient } from './supabase-public-client.js';
import {
  exchangeAuthCode,
  getCurrentSession,
  registerWithPassword,
  requestPasswordReset,
  signInWithPassword,
  signOut,
  subscribeToAuthChanges,
  updateRecoveryPassword,
} from './auth-session.js';
import {
  readActiveServiceCategories,
  readOwnCustomerBookings,
  readOwnCustomerDraftForEdit,
  readOwnCustomerPayments,
  readOwnCustomerRequestDetail,
  readOwnCustomerRequests,
  readOwnProviderStatus,
  readOwnRouteProfile,
  readOwnSettingsProfile,
} from './safe-reads.js';
import { defaultRouteForProfile, isProtectedRoute, resolveRouteAccess } from './route-guards.js';
import { createCustomerDraftRequest, validateCustomerDraft } from './request-draft.js';
import {
  DRAFT_CANCELLATION_AMBIGUOUS_MESSAGE,
  DRAFT_CANCELLATION_SUCCESS_MESSAGE,
  DRAFT_CANCELLATION_UNAVAILABLE_MESSAGE,
  cancelCustomerDraft,
} from './request-cancellation.js';
import {
  DRAFT_PUBLICATION_AMBIGUOUS_MESSAGE,
  DRAFT_PUBLICATION_SUCCESS_MESSAGE,
  DRAFT_PUBLICATION_UNAVAILABLE_MESSAGE,
  publishCustomerDraft,
} from './request-publication.js';
import {
  DRAFT_EDIT_AMBIGUOUS_MESSAGE,
  DRAFT_EDIT_SUCCESS_MESSAGE,
  DRAFT_EDIT_UNAVAILABLE_MESSAGE,
  customerDraftToEditValues,
  updateCustomerDraft,
} from './request-update.js';
import {
  PROVIDER_APPLICATION_AMBIGUOUS_MESSAGE,
  PROVIDER_APPLICATION_SUCCESS_MESSAGE,
  PROVIDER_APPLICATION_UNAVAILABLE_MESSAGE,
  isConfirmedPendingProviderApplication,
  isEligibleCustomerProviderApplication,
  submitCustomerProviderApplication,
  validateProviderApplication,
} from './provider-application.js';
import {
  PROVIDER_DISCOVERY_PAGE_SIZE,
  readProviderDiscoveryPage,
} from './provider-discovery.js';
import {
  PROVIDER_BID_AMBIGUOUS_MESSAGE,
  PROVIDER_BID_SUBMITTED_MESSAGE,
  PROVIDER_BID_UNAVAILABLE_MESSAGE,
  PROVIDER_BID_WITHDRAWN_MESSAGE,
  parseProviderBidAmount,
  readOwnProviderBid,
  submitProviderBid,
  withdrawProviderBid,
} from './provider-bidding.js';
import { readCustomerCurrentBids } from './customer-bid-viewing.js';
import { isCustomerRequestId } from './customer-requests.js';
import { normalizePath, renderRoute } from './shell.js';

const root = document.querySelector('#app');
const state = {
  client: null,
  config: null,
  session: null,
  routeProfile: null,
  sessionExpired: false,
  recoveryReady: false,
  callbackStatus: 'loading',
  formMessage: '',
  access: { kind: 'loading' },
  categoriesStatus: 'idle',
  categories: [],
  customer: null,
  customerRequestList: null,
  customerRequestDetail: null,
  customerDraftCancellation: {
    requestId: null, confirming: false, submitting: false, confirmed: false, blocked: false, message: '',
  },
  customerDraftPublication: {
    requestId: null, confirming: false, submitting: false, confirmed: false, blocked: false, message: '',
  },
  customerBidViewing: {
    requestId: null, status: 'idle', items: [], cursor: null, hasMore: false, loadingMore: false,
  },
  customerDraftEdit: null,
  providerStatus: null,
  providerDiscovery: {
    status: 'idle', items: [], cursor: null, hasMore: false, loadingMore: false,
  },
  providerBidding: { entries: {}, action: null },
  providerApplication: {
    loadStatus: 'idle', values: {}, errors: {}, confirming: false, submitting: false,
    confirmed: false, blocked: false, message: '', validatedValues: null,
  },
  settingsProfile: null,
  requestDraft: {
    values: {}, errors: {}, message: '', submitting: false, requestId: null,
  },
};
let refreshSequence = 0;
let authSubmissionInFlight = false;
let draftSubmissionInFlight = false;
let draftCancellationInFlight = false;
let draftCancellationSequence = 0;
let draftPublicationInFlight = false;
let draftPublicationSequence = 0;
let draftEditInFlight = false;
let draftEditSequence = 0;
let providerApplicationInFlight = false;
let providerApplicationSequence = 0;
let providerDiscoveryInFlight = false;
let providerDiscoverySequence = 0;
let providerBidMutationInFlight = false;
let providerBidMutationSequence = 0;
let customerBidViewInFlight = false;
let customerBidViewSequence = 0;

const pageTitles = Object.freeze({
  '/': 'Local services, clearly arranged',
  '/services': 'Browse services',
  '/auth/sign-in': 'Sign in',
  '/auth/register': 'Register',
  '/auth/forgot-password': 'Forgot password',
  '/auth/reset-password': 'Reset password',
  '/auth/callback': 'Authentication callback',
  '/app/customer': 'Customer workspace',
  '/app/customer/requests': 'Your requests',
  '/app/customer/requests/detail': 'Request details',
  '/app/customer/requests/edit': 'Edit request draft',
  '/app/customer/requests/new': 'Create request draft',
  '/app/provider': 'Provider workspace',
  '/app/settings': 'Settings',
  '/access-denied': 'Access denied',
  '/account-restricted': 'Account restricted',
});

function currentPath() {
  return normalizePath(window.location.pathname);
}

function view() {
  return {
    sessionReady: Boolean(state.session),
    recoveryReady: state.recoveryReady,
    callbackStatus: state.callbackStatus,
    formMessage: state.formMessage,
    access: state.access,
    accountStatus: state.routeProfile?.account_status,
    categoriesStatus: state.categoriesStatus,
    categories: state.categories,
    customer: state.customer,
    customerRequestList: state.customerRequestList,
    customerRequestDetail: state.customerRequestDetail,
    customerDraftCancellation: state.customerDraftCancellation,
    customerDraftPublication: state.customerDraftPublication,
    customerBidViewing: state.customerBidViewing,
    customerDraftEdit: state.customerDraftEdit,
    providerStatus: state.providerStatus,
    providerDiscovery: state.providerDiscovery,
    providerBidding: state.providerBidding,
    providerApplication: state.providerApplication,
    settingsProfile: state.settingsProfile,
    requestDraft: state.requestDraft,
  };
}

function render({ scroll = false } = {}) {
  const path = currentPath();
  root.innerHTML = renderRoute(path, new URLSearchParams(window.location.search), view());
  document.title = `LEKKADEALL — ${pageTitles[path] ?? 'Page not found'}`;
  if (scroll) window.scrollTo({ top: 0, behavior: 'auto' });
}

function clearPersonalState() {
  state.routeProfile = null;
  state.customer = null;
  state.customerRequestList = null;
  state.customerRequestDetail = null;
  state.providerStatus = null;
  resetProviderDiscovery();
  resetProviderBidding();
  state.settingsProfile = null;
  resetProviderApplication();
  resetCustomerDraftCancellation();
  resetCustomerDraftPublication();
  resetCustomerBidViewing();
  resetCustomerDraftEdit();
}

function resetCustomerDraftCancellation(requestId = null) {
  draftCancellationSequence += 1;
  draftCancellationInFlight = false;
  state.customerDraftCancellation = {
    requestId, confirming: false, submitting: false, confirmed: false, blocked: false, message: '',
  };
}

function resetCustomerDraftPublication(requestId = null) {
  draftPublicationSequence += 1;
  draftPublicationInFlight = false;
  state.customerDraftPublication = {
    requestId, confirming: false, submitting: false, confirmed: false, blocked: false, message: '',
  };
}

function resetRequestDraft() {
  state.requestDraft = {
    values: {}, errors: {}, message: '', submitting: false, requestId: null,
  };
}

function resetCustomerBidViewing(requestId = null, status = 'idle') {
  customerBidViewSequence += 1;
  customerBidViewInFlight = false;
  state.customerBidViewing = {
    requestId, status, items: [], cursor: null, hasMore: false, loadingMore: false,
  };
}

function resetProviderApplication(loadStatus = 'idle') {
  providerApplicationSequence += 1;
  providerApplicationInFlight = false;
  state.providerApplication = {
    loadStatus,
    values: {},
    errors: {},
    confirming: false,
    submitting: false,
    confirmed: false,
    blocked: false,
    message: '',
    validatedValues: null,
  };
}

function resetProviderDiscovery(status = 'idle') {
  providerDiscoverySequence += 1;
  providerDiscoveryInFlight = false;
  state.providerDiscovery = {
    status, items: [], cursor: null, hasMore: false, loadingMore: false,
  };
}

function resetProviderBidding() {
  providerBidMutationSequence += 1;
  providerBidMutationInFlight = false;
  state.providerBidding = { entries: {}, action: null };
}

async function loadProviderDiscovery({ append = false } = {}) {
  if (providerDiscoveryInFlight || !state.client || currentPath() !== '/app/provider'
      || state.access?.kind !== 'allowed' || state.access?.role !== 'provider'
      || providerBidMutationInFlight) return;

  const cursor = append ? state.providerDiscovery.cursor : null;
  if (append && (!state.providerDiscovery.hasMore || !cursor)) return;
  const sequence = ++providerDiscoverySequence;
  providerDiscoveryInFlight = true;
  state.providerDiscovery = append
    ? { ...state.providerDiscovery, loadingMore: true }
    : { status: 'loading', items: [], cursor: null, hasMore: false, loadingMore: false };
  render();

  let result;
  try {
    result = await readProviderDiscoveryPage(state.client, {
      pageSize: PROVIDER_DISCOVERY_PAGE_SIZE,
      cursor,
    });
  } catch {
    result = { ok: false, data: [], cursor: null, hasMore: false };
  }
  if (sequence !== providerDiscoverySequence) return;
  if (currentPath() !== '/app/provider' || state.access?.kind !== 'allowed'
      || state.access?.role !== 'provider') {
    resetProviderDiscovery();
    return;
  }
  if (!result.ok) {
    resetProviderDiscovery('unavailable');
    resetProviderBidding();
    render();
    return;
  }
  const items = append ? [...state.providerDiscovery.items, ...result.data] : result.data;
  const entries = append ? { ...state.providerBidding.entries } : {};
  const newRequests = append ? result.data : items;
  const reconciliations = await Promise.all(newRequests.map(async (request) => [
    request.request_id,
    await readOwnProviderBid(state.client, request.request_id),
  ]));
  if (sequence !== providerDiscoverySequence) return;
  providerDiscoveryInFlight = false;
  for (const [requestId, ownBid] of reconciliations) entries[requestId] = ownBid;
  state.providerDiscovery = {
    status: items.length ? 'ready' : 'empty',
    items,
    cursor: result.cursor,
    hasMore: result.hasMore,
    loadingMore: false,
  };
  state.providerBidding = { entries, action: null };
  render();
}

function providerBidActionIsEligible(requestId) {
  return currentPath() === '/app/provider'
    && !providerDiscoveryInFlight
    && Boolean(state.client)
    && Boolean(state.session?.user?.id)
    && state.access?.kind === 'allowed'
    && state.access?.role === 'provider'
    && state.routeProfile?.role === 'provider'
    && state.routeProfile?.account_status === 'active'
    && state.providerDiscovery.status === 'ready'
    && state.providerDiscovery.items.some((request) => request.request_id === requestId)
    && state.providerBidding.entries[requestId]?.ok === true;
}

function reviewProviderBid(form) {
  const requestId = String(form.dataset.providerBidRequest ?? '');
  const entry = state.providerBidding.entries[requestId];
  if (providerBidMutationInFlight || !providerBidActionIsEligible(requestId)
      || entry?.data !== null) return;
  const amountMinor = parseProviderBidAmount(new FormData(form).get('bid-amount'));
  if (amountMinor === null) {
    state.providerBidding.action = {
      requestId, kind: 'submit', confirming: false, submitting: false,
      blocked: false, confirmed: false, message: PROVIDER_BID_UNAVAILABLE_MESSAGE,
    };
  } else {
    state.providerBidding.action = {
      requestId, kind: 'submit', amountMinor, confirming: true, submitting: false,
      blocked: false, confirmed: false, message: '',
    };
  }
  render();
}

function openProviderBidWithdrawal(requestId) {
  const bid = state.providerBidding.entries[requestId]?.data;
  if (providerBidMutationInFlight || !providerBidActionIsEligible(requestId)
      || !bid || bid.request_id !== requestId || bid.status !== 'submitted') return;
  state.providerBidding.action = {
    requestId, bidId: bid.bid_id, kind: 'withdraw', confirming: true, submitting: false,
    blocked: false, confirmed: false, message: '',
  };
  render();
}

async function submitProviderBidConfirmation() {
  const action = state.providerBidding.action;
  const requestId = action?.requestId ?? '';
  const entry = state.providerBidding.entries[requestId];
  const actorId = state.session?.user?.id;
  const validSubmit = action?.kind === 'submit' && entry?.data === null
    && Number.isSafeInteger(action.amountMinor);
  const validWithdraw = action?.kind === 'withdraw'
    && entry?.data?.bid_id === action.bidId && entry.data.status === 'submitted';
  if (providerBidMutationInFlight || !action?.confirming || action.blocked
      || !providerBidActionIsEligible(requestId) || (!validSubmit && !validWithdraw)) return;

  const mutationSequence = ++providerBidMutationSequence;
  providerBidMutationInFlight = true;
  state.providerBidding.action = { ...action, submitting: true, message: '' };
  render();

  const result = validSubmit
    ? await submitProviderBid(state.client, requestId, action.amountMinor)
    : await withdrawProviderBid(state.client, action.bidId);
  if (mutationSequence !== providerBidMutationSequence) return;

  if (!providerBidActionIsEligible(requestId) || state.session?.user?.id !== actorId) {
    resetProviderBidding();
    return;
  }
  if (!result.ok) {
    providerBidMutationInFlight = false;
    state.providerBidding.action = {
      ...action,
      confirming: false,
      submitting: false,
      blocked: true,
      confirmed: false,
      message: result.message,
    };
    render();
    return;
  }

  const freshBid = await readOwnProviderBid(state.client, requestId);
  if (mutationSequence !== providerBidMutationSequence) return;
  providerBidMutationInFlight = false;
  const canonicalBid = freshBid.ok ? freshBid.data : null;
  const confirmed = validSubmit
    ? canonicalBid?.bid_id === result.bidId
      && canonicalBid.request_id === requestId
      && canonicalBid.amount_minor === action.amountMinor
      && canonicalBid.status === 'submitted'
    : canonicalBid?.bid_id === action.bidId
      && canonicalBid.request_id === requestId
      && canonicalBid.status === 'withdrawn';
  if (!confirmed) {
    state.providerBidding.action = {
      ...action,
      confirming: false,
      submitting: false,
      blocked: true,
      confirmed: false,
      message: PROVIDER_BID_AMBIGUOUS_MESSAGE,
    };
    render();
    return;
  }

  state.providerBidding.entries = {
    ...state.providerBidding.entries,
    [requestId]: freshBid,
  };
  state.providerBidding.action = {
    requestId,
    kind: action.kind,
    confirming: false,
    submitting: false,
    blocked: false,
    confirmed: true,
    message: validSubmit ? PROVIDER_BID_SUBMITTED_MESSAGE : PROVIDER_BID_WITHDRAWN_MESSAGE,
  };
  render();
}

function customerBidViewIsEligible(requestId) {
  return currentPath() === '/app/customer/requests/detail'
    && new URLSearchParams(window.location.search).get('requestId') === requestId
    && Boolean(state.client && state.session?.user?.id)
    && state.access?.kind === 'allowed'
    && state.access?.role === 'customer'
    && state.routeProfile?.role === 'customer'
    && state.routeProfile?.account_status === 'active'
    && state.customerRequestDetail?.ok === true
    && state.customerRequestDetail.data?.id === requestId
    && state.customerRequestDetail.data?.status === 'open'
    && state.customerBidViewing.requestId === requestId;
}

async function loadCustomerBidView({ append = false } = {}) {
  const requestId = new URLSearchParams(window.location.search).get('requestId') ?? '';
  if (customerBidViewInFlight || !isCustomerRequestId(requestId)
      || !customerBidViewIsEligible(requestId)) return;

  const cursor = append ? state.customerBidViewing.cursor : null;
  if (append && (!state.customerBidViewing.hasMore || !cursor)) return;
  const actorId = state.session.user.id;
  const bidViewSequence = ++customerBidViewSequence;
  customerBidViewInFlight = true;
  state.customerBidViewing = append
    ? { ...state.customerBidViewing, loadingMore: true }
    : {
      requestId, status: 'loading', items: [], cursor: null, hasMore: false, loadingMore: false,
    };
  render();

  const result = await readCustomerCurrentBids(state.client, requestId, { cursor });
  if (bidViewSequence !== customerBidViewSequence) return;
  customerBidViewInFlight = false;

  if (state.session?.user?.id !== actorId || !customerBidViewIsEligible(requestId)) {
    resetCustomerBidViewing();
    return;
  }
  if (!result.ok) {
    resetCustomerBidViewing(requestId, 'unavailable');
    render();
    return;
  }

  const items = append ? [...state.customerBidViewing.items, ...result.data] : result.data;
  if (new Set(items.map((bid) => bid.bid_id)).size !== items.length) {
    resetCustomerBidViewing(requestId, 'unavailable');
    render();
    return;
  }
  state.customerBidViewing = {
    requestId,
    status: items.length ? 'ready' : 'empty',
    items,
    cursor: result.cursor,
    hasMore: result.hasMore,
    loadingMore: false,
  };
  render();
}

function resetCustomerDraftEdit(requestId = null, loadStatus = 'loading') {
  draftEditSequence += 1;
  draftEditInFlight = false;
  state.customerDraftEdit = requestId === null ? null : {
    requestId,
    loadStatus,
    request: null,
    values: {},
    errors: {},
    message: '',
    submitting: false,
    confirmed: false,
    blocked: false,
  };
}

async function loadRouteProfile() {
  if (!state.session?.user?.id || !state.client) return null;
  const result = await readOwnRouteProfile(state.client, state.session.user.id);
  state.routeProfile = result.ok ? result.data : null;
  return result.ok ? result.data : null;
}

async function loadCustomerData(sequence) {
  const [requests, bookings] = await Promise.all([
    readOwnCustomerRequests(state.client),
    readOwnCustomerBookings(state.client),
  ]);
  if (sequence !== refreshSequence) return;
  const bookingIds = bookings.ok ? bookings.data.map(({ id }) => id) : [];
  const payments = await readOwnCustomerPayments(state.client, bookingIds);
  if (sequence !== refreshSequence) return;
  state.customer = { requests, bookings, payments };
}

async function loadRequestCategories(sequence) {
  const categories = await readActiveServiceCategories(state.client);
  if (sequence !== refreshSequence) return false;
  state.categoriesStatus = categories.ok ? 'ready' : 'error';
  state.categories = categories.ok ? categories.data : [];
  return true;
}

async function refreshRoute() {
  const sequence = ++refreshSequence;
  const path = currentPath();
  state.formMessage = '';
  if (path !== '/app/customer/requests/new') resetRequestDraft();
  if (path !== '/app/customer/requests/edit') resetCustomerDraftEdit();

  if (path === '/services' || path === '/app/customer/requests/new') {
    if (!state.client) {
      state.categoriesStatus = 'unconfigured';
    } else {
      state.categoriesStatus = 'loading';
      render();
      const result = await readActiveServiceCategories(state.client);
      if (sequence !== refreshSequence) return;
      state.categoriesStatus = result.ok ? 'ready' : 'error';
      state.categories = result.ok ? result.data : [];
    }
  }

  if (isProtectedRoute(path)) {
    clearPersonalState();
    if (!state.client) {
      state.access = { kind: 'unconfigured' };
      render();
      return;
    }

    state.access = resolveRouteAccess(path, state.session, null, { expired: state.sessionExpired });
    render();
    if (!state.session?.user?.id) return;

    const profile = await loadRouteProfile();
    if (sequence !== refreshSequence) return;
    state.access = resolveRouteAccess(path, state.session, profile);
    if (state.access.kind !== 'allowed') {
      render();
      return;
    }

    if (path === '/app/customer') {
      resetProviderApplication('loading');
      state.categoriesStatus = 'loading';
      state.categories = [];
      render();
      const [providerStatus] = await Promise.all([
        readOwnProviderStatus(state.client, state.session.user.id),
        loadCustomerData(sequence),
        loadRequestCategories(sequence),
      ]);
      if (sequence !== refreshSequence) return;
      state.providerStatus = providerStatus;
      const customerReadsReady = state.customer?.requests?.ok === true
        && state.customer?.bookings?.ok === true;
      if (!providerStatus.ok || !customerReadsReady || state.categoriesStatus === 'error') {
        state.providerApplication.loadStatus = 'unavailable';
      } else {
        state.providerApplication.loadStatus = isEligibleCustomerProviderApplication(
          profile,
          providerStatus,
          state.customer.requests,
          state.customer.bookings,
          state.categories,
        ) ? 'eligible' : 'ineligible';
      }
    } else if (path === '/app/customer/requests') {
      state.customerRequestList = null;
      state.categoriesStatus = 'loading';
      state.categories = [];
      render();
      const [requests] = await Promise.all([
        readOwnCustomerRequests(state.client),
        loadRequestCategories(sequence),
      ]);
      if (sequence !== refreshSequence) return;
      state.customerRequestList = requests;
    } else if (path === '/app/customer/requests/detail') {
      state.customerRequestDetail = null;
      state.categoriesStatus = 'loading';
      state.categories = [];
      render();
      const requestId = new URLSearchParams(window.location.search).get('requestId') ?? '';
      resetCustomerDraftCancellation(requestId);
      resetCustomerDraftPublication(requestId);
      resetCustomerBidViewing(requestId);
      const [request] = await Promise.all([
        readOwnCustomerRequestDetail(state.client, requestId),
        loadRequestCategories(sequence),
      ]);
      if (sequence !== refreshSequence) return;
      state.customerRequestDetail = request;
    } else if (path === '/app/customer/requests/edit') {
      const requestId = new URLSearchParams(window.location.search).get('requestId') ?? '';
      resetCustomerDraftEdit(requestId, 'loading');
      state.categoriesStatus = 'loading';
      state.categories = [];
      render();
      const [request] = await Promise.all([
        readOwnCustomerDraftForEdit(state.client, requestId),
        loadRequestCategories(sequence),
      ]);
      if (sequence !== refreshSequence) return;
      const values = request.ok ? customerDraftToEditValues(request.data) : null;
      state.customerDraftEdit = values ? {
        requestId,
        loadStatus: 'ready',
        request: request.data,
        values,
        errors: {},
        message: '',
        submitting: false,
        confirmed: false,
        blocked: false,
      } : {
        requestId,
        loadStatus: 'unavailable',
        request: null,
        values: {},
        errors: {},
        message: DRAFT_EDIT_UNAVAILABLE_MESSAGE,
        submitting: false,
        confirmed: false,
        blocked: true,
      };
    } else if (path === '/app/customer/requests/new') {
      // Categories were loaded above. Draft state remains in memory only while this route is active.
    } else if (path === '/app/provider') {
      const [providerStatus] = await Promise.all([
        readOwnProviderStatus(state.client, state.session.user.id),
        loadProviderDiscovery(),
      ]);
      if (sequence !== refreshSequence) return;
      state.providerStatus = providerStatus;
    } else if (path === '/app/settings') {
      const reads = [readOwnSettingsProfile(state.client, state.session.user.id)];
      if (profile.role === 'provider') reads.push(readOwnProviderStatus(state.client, state.session.user.id));
      const [settingsProfile, providerStatus] = await Promise.all(reads);
      if (sequence !== refreshSequence) return;
      state.settingsProfile = settingsProfile;
      state.providerStatus = providerStatus ?? null;
    }
  }

  if (sequence === refreshSequence) render();
}

async function navigate(url, { replace = false } = {}) {
  const next = new URL(url, window.location.origin);
  if (next.origin !== window.location.origin) return;
  if (currentPath() === '/app/customer/requests/new' && normalizePath(next.pathname) !== '/app/customer/requests/new') {
    resetRequestDraft();
  }
  window.history[replace ? 'replaceState' : 'pushState']({}, '', `${next.pathname}${next.search}`);
  render({ scroll: true });
  await refreshRoute();
}

async function routeAfterAuthentication(session) {
  state.session = session;
  state.sessionExpired = false;
  const profile = await loadRouteProfile();
  await navigate(defaultRouteForProfile(profile), { replace: true });
}

async function handleAuthCallback() {
  if (currentPath() !== '/auth/callback') return false;
  state.callbackStatus = 'loading';
  render();
  const result = await exchangeAuthCode(state.client, window.location.href);
  window.history.replaceState({}, '', '/auth/callback');
  if (!result.ok || !result.session) {
    state.callbackStatus = 'error';
    render();
    return true;
  }
  await routeAfterAuthentication(result.session);
  return true;
}

async function handleRecoveryCallback() {
  if (currentPath() !== '/auth/reset-password' || !new URLSearchParams(window.location.search).has('code')) return false;
  const result = await exchangeAuthCode(state.client, window.location.href);
  window.history.replaceState({}, '', '/auth/reset-password');
  state.session = result.session;
  state.recoveryReady = Boolean(result.ok && result.session);
  state.formMessage = result.ok ? '' : result.message;
  render();
  return true;
}

async function submitAuthForm(form) {
  if (authSubmissionInFlight) return;
  authSubmissionInFlight = true;
  try {
    await submitAuthFormOnce(form);
  } finally {
    authSubmissionInFlight = false;
  }
}

async function submitAuthFormOnce(form) {
  if (!state.client || !state.config) {
    state.formMessage = 'Authentication is unavailable until public configuration is supplied.';
    render();
    return;
  }
  const action = form.dataset.authForm;
  const values = new FormData(form);
  const email = String(values.get('email') ?? '').trim();
  const password = String(values.get('password') ?? '');
  state.formMessage = 'Working…';
  render();

  if (action === 'sign-in') {
    const result = await signInWithPassword(state.client, email, password);
    if (result.ok && result.session) return routeAfterAuthentication(result.session);
    state.formMessage = result.message;
  } else if (action === 'register') {
    const result = await registerWithPassword(state.client, email, password, state.config.appUrl);
    if (result.ok && result.session) return routeAfterAuthentication(result.session);
    state.formMessage = result.ok
      ? 'Check your email to confirm the account. Your application profile is provisioned by the trusted Ticket 9B trigger.'
      : result.message;
  } else if (action === 'forgot-password') {
    const result = await requestPasswordReset(state.client, email, state.config.appUrl);
    state.formMessage = result.message;
  } else if (action === 'reset-password') {
    const confirmation = String(values.get('password-confirmation') ?? '');
    if (!state.recoveryReady) {
      state.formMessage = 'A valid recovery session is required.';
    } else if (password.length < 10 || password !== confirmation) {
      state.formMessage = 'Use matching passwords of at least 10 characters.';
    } else {
      const result = await updateRecoveryPassword(state.client, password);
      state.formMessage = result.message;
      if (result.ok) state.recoveryReady = false;
    }
  }
  form.reset();
  render();
}

function providerApplicationIsEligible() {
  return currentPath() === '/app/customer'
    && Boolean(state.client && state.session?.user?.id)
    && state.access?.kind === 'allowed'
    && state.access?.role === 'customer'
    && state.routeProfile?.role === 'customer'
    && state.routeProfile?.account_status === 'active'
    && state.providerApplication.loadStatus === 'eligible'
    && !state.providerApplication.blocked
    && state.providerStatus?.ok === true
    && state.providerStatus.data === null
    && state.customer?.requests?.ok === true
    && state.customer.requests.data.length === 0
    && state.customer?.bookings?.ok === true
    && state.customer.bookings.data.length === 0
    && state.categoriesStatus === 'ready'
    && state.categories.length > 0;
}

function reviewProviderApplication(form) {
  if (!providerApplicationIsEligible() || providerApplicationInFlight) {
    resetProviderApplication('ineligible');
    state.providerApplication.blocked = true;
    state.providerApplication.message = PROVIDER_APPLICATION_UNAVAILABLE_MESSAGE;
    render();
    return;
  }

  const formData = new FormData(form);
  const values = {
    businessName: String(formData.get('business-name') ?? ''),
    serviceRadiusKm: String(formData.get('service-radius-km') ?? ''),
    categoryIds: formData.getAll('category').map((value) => String(value)),
    acceptedTerms: formData.get('accept-terms') === 'accepted',
  };
  const validation = validateProviderApplication(values, state.categories);
  state.providerApplication.values = values;
  state.providerApplication.errors = validation.errors;
  state.providerApplication.message = validation.ok
    ? ''
    : 'Review the highlighted application fields before continuing.';
  state.providerApplication.confirming = validation.ok;
  state.providerApplication.validatedValues = validation.ok ? validation.values : null;
  render();
}

async function submitProviderApplicationConfirmation() {
  if (providerApplicationInFlight || !providerApplicationIsEligible()
      || !state.providerApplication.confirming
      || !state.providerApplication.validatedValues) return;

  const actorId = state.session.user.id;
  const applicationSequence = ++providerApplicationSequence;
  providerApplicationInFlight = true;
  state.providerApplication.submitting = true;
  state.providerApplication.message = '';
  render();

  const result = await submitCustomerProviderApplication(
    state.client,
    state.providerApplication.validatedValues,
  );
  if (applicationSequence !== providerApplicationSequence) return;

  if (currentPath() !== '/app/customer' || state.session?.user?.id !== actorId) {
    resetProviderApplication();
    return;
  }

  if (!result.ok) {
    providerApplicationInFlight = false;
    state.providerApplication.confirming = false;
    state.providerApplication.submitting = false;
    state.providerApplication.blocked = true;
    state.providerApplication.message = result.message;
    render();
    return;
  }

  let freshProfile;
  let freshProviderStatus;
  try {
    [freshProfile, freshProviderStatus] = await Promise.all([
      readOwnRouteProfile(state.client, actorId),
      readOwnProviderStatus(state.client, actorId),
    ]);
  } catch {
    freshProfile = { ok: false, data: null };
    freshProviderStatus = { ok: false, data: null };
  }
  if (applicationSequence !== providerApplicationSequence) return;
  providerApplicationInFlight = false;

  if (currentPath() !== '/app/customer' || state.session?.user?.id !== actorId) {
    resetProviderApplication();
    return;
  }

  if (!isConfirmedPendingProviderApplication(actorId, freshProfile, freshProviderStatus)) {
    state.providerApplication.confirming = false;
    state.providerApplication.submitting = false;
    state.providerApplication.blocked = true;
    state.providerApplication.message = PROVIDER_APPLICATION_AMBIGUOUS_MESSAGE;
    render();
    return;
  }

  state.routeProfile = freshProfile.data;
  state.providerStatus = freshProviderStatus;
  state.access = resolveRouteAccess('/app/provider', state.session, freshProfile.data);
  state.providerApplication = {
    loadStatus: 'confirmed',
    values: {},
    errors: {},
    confirming: false,
    submitting: false,
    confirmed: true,
    blocked: false,
    message: PROVIDER_APPLICATION_SUCCESS_MESSAGE,
    validatedValues: null,
  };
  window.history.replaceState({}, '', '/app/provider');
  render({ scroll: true });
}

async function submitCustomerDraftForm(form) {
  if (draftSubmissionInFlight || currentPath() !== '/app/customer/requests/new') return;
  if (!state.client || !state.session?.user?.id || state.access?.kind !== 'allowed'
      || state.routeProfile?.role !== 'customer' || state.routeProfile?.account_status !== 'active') {
    state.requestDraft.message = 'Only an active customer can create a request draft.';
    render();
    return;
  }

  const formData = new FormData(form);
  const values = {
    category: String(formData.get('category') ?? ''),
    title: String(formData.get('title') ?? ''),
    description: String(formData.get('description') ?? ''),
    suburb: String(formData.get('suburb') ?? ''),
    city: String(formData.get('city') ?? ''),
    requestedStart: String(formData.get('requested-start') ?? ''),
    budget: String(formData.get('budget') ?? ''),
  };
  const validation = validateCustomerDraft(values, state.categories);
  state.requestDraft = {
    values, errors: validation.errors, message: validation.ok ? '' : 'Review the highlighted fields before creating the draft.',
    submitting: false, requestId: null,
  };
  if (!validation.ok) {
    render();
    return;
  }

  const actorId = state.session.user.id;
  draftSubmissionInFlight = true;
  state.requestDraft.submitting = true;
  state.requestDraft.errors = {};
  state.requestDraft.message = 'Creating your private draft…';
  render();

  let result;
  try {
    result = await createCustomerDraftRequest(state.client, validation.values);
  } catch {
    result = {
      ok: false,
      requestId: null,
      message: 'The draft could not be confirmed. Refresh your drafts before trying again.',
    };
  }
  draftSubmissionInFlight = false;

  if (currentPath() !== '/app/customer/requests/new' || state.session?.user?.id !== actorId
      || state.access?.kind !== 'allowed' || state.routeProfile?.role !== 'customer'
      || state.routeProfile?.account_status !== 'active') {
    resetRequestDraft();
    return;
  }
  if (result.ok) {
    state.requestDraft = {
      values: {}, errors: {}, message: '', submitting: false, requestId: result.requestId,
    };
  } else {
    state.requestDraft.submitting = false;
    state.requestDraft.message = result.message;
  }
  render();
}

async function submitCustomerDraftEdit(form) {
  const path = currentPath();
  const requestId = new URLSearchParams(window.location.search).get('requestId') ?? '';
  const edit = state.customerDraftEdit;
  if (draftEditInFlight || path !== '/app/customer/requests/edit') return;
  if (!state.client || !state.session?.user?.id || !isCustomerRequestId(requestId)
      || state.access?.kind !== 'allowed' || state.routeProfile?.role !== 'customer'
      || state.routeProfile?.account_status !== 'active' || edit?.loadStatus !== 'ready'
      || edit.requestId !== requestId || edit.request?.id !== requestId
      || edit.request?.status !== 'draft' || edit.blocked) {
    resetCustomerDraftEdit(requestId, 'unavailable');
    state.customerDraftEdit.message = DRAFT_EDIT_UNAVAILABLE_MESSAGE;
    state.customerDraftEdit.blocked = true;
    render();
    return;
  }

  const formData = new FormData(form);
  const values = {
    category: String(formData.get('category') ?? ''),
    title: String(formData.get('title') ?? ''),
    description: String(formData.get('description') ?? ''),
    suburb: String(formData.get('suburb') ?? ''),
    city: String(formData.get('city') ?? ''),
    requestedStart: String(formData.get('requested-start') ?? ''),
    budget: String(formData.get('budget') ?? ''),
  };
  const validation = validateCustomerDraft(values, state.categories);
  state.customerDraftEdit.values = values;
  state.customerDraftEdit.errors = validation.errors;
  state.customerDraftEdit.message = validation.ok ? '' : 'Review the highlighted fields before saving the draft.';
  state.customerDraftEdit.confirmed = false;
  if (!validation.ok) {
    render();
    return;
  }

  const actorId = state.session.user.id;
  const editSequence = ++draftEditSequence;
  draftEditInFlight = true;
  state.customerDraftEdit.submitting = true;
  state.customerDraftEdit.errors = {};
  state.customerDraftEdit.message = 'Saving your private draft…';
  render();

  const result = await updateCustomerDraft(state.client, requestId, validation.values);
  if (editSequence !== draftEditSequence) return;

  if (currentPath() !== '/app/customer/requests/edit'
      || new URLSearchParams(window.location.search).get('requestId') !== requestId
      || state.session?.user?.id !== actorId || state.access?.kind !== 'allowed'
      || state.routeProfile?.role !== 'customer'
      || state.routeProfile?.account_status !== 'active') {
    resetCustomerDraftEdit();
    return;
  }

  if (!result.ok) {
    draftEditInFlight = false;
    state.customerDraftEdit.submitting = false;
    state.customerDraftEdit.confirmed = false;
    state.customerDraftEdit.blocked = true;
    state.customerDraftEdit.message = result.message;
    render();
    return;
  }

  let freshDraft;
  try {
    freshDraft = await readOwnCustomerDraftForEdit(state.client, requestId);
  } catch {
    freshDraft = { ok: false, data: null };
  }
  if (editSequence !== draftEditSequence) return;
  draftEditInFlight = false;

  const freshValues = freshDraft.ok ? customerDraftToEditValues(freshDraft.data) : null;
  if (currentPath() !== '/app/customer/requests/edit'
      || new URLSearchParams(window.location.search).get('requestId') !== requestId
      || state.session?.user?.id !== actorId || state.access?.kind !== 'allowed') {
    resetCustomerDraftEdit();
    return;
  }

  if (freshValues && freshDraft.data?.id === requestId && freshDraft.data?.status === 'draft') {
    state.customerDraftEdit = {
      requestId,
      loadStatus: 'ready',
      request: freshDraft.data,
      values: freshValues,
      errors: {},
      message: DRAFT_EDIT_SUCCESS_MESSAGE,
      submitting: false,
      confirmed: true,
      blocked: false,
    };
  } else {
    state.customerDraftEdit.submitting = false;
    state.customerDraftEdit.confirmed = false;
    state.customerDraftEdit.blocked = true;
    state.customerDraftEdit.message = DRAFT_EDIT_AMBIGUOUS_MESSAGE;
  }
  render();
}

async function submitCustomerDraftCancellation() {
  const path = currentPath();
  const requestId = new URLSearchParams(window.location.search).get('requestId') ?? '';
  const detail = state.customerRequestDetail;
  if (draftCancellationInFlight || path !== '/app/customer/requests/detail') return;
  if (!state.client || !state.session?.user?.id || !isCustomerRequestId(requestId)
      || state.access?.kind !== 'allowed' || state.routeProfile?.role !== 'customer'
      || state.routeProfile?.account_status !== 'active' || !detail?.ok
      || detail.data?.id !== requestId || detail.data?.status !== 'draft'
      || state.customerDraftCancellation.requestId !== requestId
      || state.customerDraftPublication.requestId !== requestId
      || state.customerDraftPublication.blocked
      || state.customerDraftPublication.confirming
      || state.customerDraftPublication.submitting
      || !state.customerDraftCancellation.confirming) {
    resetCustomerDraftCancellation(requestId);
    state.customerDraftCancellation.message = DRAFT_CANCELLATION_UNAVAILABLE_MESSAGE;
    render();
    return;
  }

  const actorId = state.session.user.id;
  const cancellationSequence = ++draftCancellationSequence;
  draftCancellationInFlight = true;
  state.customerDraftCancellation.submitting = true;
  state.customerDraftCancellation.message = '';
  render();

  const result = await cancelCustomerDraft(state.client, requestId);

  if (cancellationSequence !== draftCancellationSequence) return;

  if (currentPath() !== '/app/customer/requests/detail'
      || new URLSearchParams(window.location.search).get('requestId') !== requestId
      || state.session?.user?.id !== actorId || state.access?.kind !== 'allowed'
      || state.routeProfile?.role !== 'customer'
      || state.routeProfile?.account_status !== 'active') {
    resetCustomerDraftCancellation();
    return;
  }

  if (!result.ok) {
    draftCancellationInFlight = false;
    state.customerDraftCancellation.confirming = false;
    state.customerDraftCancellation.submitting = false;
    state.customerDraftCancellation.blocked = true;
    state.customerDraftCancellation.message = result.message;
    render();
    return;
  }

  let freshDetail;
  try {
    freshDetail = await readOwnCustomerRequestDetail(state.client, requestId);
  } catch {
    freshDetail = { ok: false, data: null };
  }
  if (cancellationSequence !== draftCancellationSequence) return;
  draftCancellationInFlight = false;

  if (currentPath() !== '/app/customer/requests/detail'
      || new URLSearchParams(window.location.search).get('requestId') !== requestId
      || state.session?.user?.id !== actorId || state.access?.kind !== 'allowed') {
    resetCustomerDraftCancellation();
    return;
  }

  state.customerDraftCancellation.confirming = false;
  state.customerDraftCancellation.submitting = false;
  if (freshDetail.ok && freshDetail.data?.id === requestId
      && freshDetail.data?.status === 'cancelled') {
    state.customerRequestDetail = freshDetail;
    state.customerDraftCancellation.confirmed = true;
    state.customerDraftCancellation.message = DRAFT_CANCELLATION_SUCCESS_MESSAGE;
  } else {
    state.customerDraftCancellation.confirmed = false;
    state.customerDraftCancellation.blocked = true;
    state.customerDraftCancellation.message = DRAFT_CANCELLATION_AMBIGUOUS_MESSAGE;
  }
  render();
}

async function submitCustomerDraftPublication() {
  const path = currentPath();
  const requestId = new URLSearchParams(window.location.search).get('requestId') ?? '';
  const detail = state.customerRequestDetail;
  const publication = state.customerDraftPublication;
  if (draftPublicationInFlight || path !== '/app/customer/requests/detail') return;
  if (!state.client || !state.session?.user?.id || !isCustomerRequestId(requestId)
      || state.access?.kind !== 'allowed' || state.routeProfile?.role !== 'customer'
      || state.routeProfile?.account_status !== 'active' || !detail?.ok
      || detail.data?.id !== requestId || detail.data?.status !== 'draft'
      || publication.requestId !== requestId || publication.blocked
      || !publication.confirming || state.customerDraftCancellation.confirming
      || state.customerDraftCancellation.submitting || state.customerDraftCancellation.blocked) {
    resetCustomerDraftPublication(requestId);
    state.customerDraftPublication.blocked = true;
    state.customerDraftPublication.message = DRAFT_PUBLICATION_UNAVAILABLE_MESSAGE;
    render();
    return;
  }

  const actorId = state.session.user.id;
  const publicationSequence = ++draftPublicationSequence;
  draftPublicationInFlight = true;
  state.customerDraftPublication.submitting = true;
  state.customerDraftPublication.message = '';
  render();

  const result = await publishCustomerDraft(state.client, requestId);

  if (publicationSequence !== draftPublicationSequence) return;

  if (currentPath() !== '/app/customer/requests/detail'
      || new URLSearchParams(window.location.search).get('requestId') !== requestId
      || state.session?.user?.id !== actorId || state.access?.kind !== 'allowed'
      || state.routeProfile?.role !== 'customer'
      || state.routeProfile?.account_status !== 'active') {
    resetCustomerDraftPublication();
    return;
  }

  if (!result.ok) {
    draftPublicationInFlight = false;
    state.customerDraftPublication.confirming = false;
    state.customerDraftPublication.submitting = false;
    state.customerDraftPublication.confirmed = false;
    state.customerDraftPublication.blocked = true;
    state.customerDraftPublication.message = result.message;
    render();
    return;
  }

  let freshDetail;
  try {
    freshDetail = await readOwnCustomerRequestDetail(state.client, requestId);
  } catch {
    freshDetail = { ok: false, data: null };
  }
  if (publicationSequence !== draftPublicationSequence) return;
  draftPublicationInFlight = false;

  if (currentPath() !== '/app/customer/requests/detail'
      || new URLSearchParams(window.location.search).get('requestId') !== requestId
      || state.session?.user?.id !== actorId || state.access?.kind !== 'allowed') {
    resetCustomerDraftPublication();
    return;
  }

  state.customerDraftPublication.confirming = false;
  state.customerDraftPublication.submitting = false;
  if (freshDetail.ok && freshDetail.data?.id === requestId
      && freshDetail.data?.status === 'open') {
    state.customerRequestDetail = freshDetail;
    state.customerDraftPublication.confirmed = true;
    state.customerDraftPublication.blocked = false;
    state.customerDraftPublication.message = DRAFT_PUBLICATION_SUCCESS_MESSAGE;
  } else {
    state.customerDraftPublication.confirmed = false;
    state.customerDraftPublication.blocked = true;
    state.customerDraftPublication.message = DRAFT_PUBLICATION_AMBIGUOUS_MESSAGE;
  }
  render();
}

async function initialize() {
  await loadRuntimeConfig();
  const publicConfig = readPublicConfig();
  if (!publicConfig.ok) {
    state.access = { kind: 'unconfigured' };
    if (currentPath() === '/services') state.categoriesStatus = 'unconfigured';
    render();
    return;
  }

  state.config = publicConfig.config;
  try {
    state.client = await getPublicSupabaseClient(state.config);
  } catch {
    state.access = { kind: 'unconfigured' };
    render();
    return;
  }

  const sessionResult = await getCurrentSession(state.client);
  state.session = sessionResult.ok ? sessionResult.session : null;
  subscribeToAuthChanges(state.client, async (event, session) => {
    const hadSession = Boolean(state.session);
    state.session = session;
    state.sessionExpired = event === 'SIGNED_OUT' && hadSession;
    if (event === 'PASSWORD_RECOVERY') state.recoveryReady = true;
    if (!session) {
      clearPersonalState();
      resetRequestDraft();
    }
    await refreshRoute();
  });

  if (await handleAuthCallback()) return;
  if (await handleRecoveryCallback()) return;
  await refreshRoute();
}

document.addEventListener('click', async (event) => {
  const signOutButton = event.target.closest('[data-auth-action="sign-out"]');
  if (signOutButton) {
    clearPersonalState();
    resetRequestDraft();
    state.session = null;
    state.sessionExpired = false;
    render();
    if (state.client) await signOut(state.client);
    await navigate('/auth/sign-in', { replace: true });
    return;
  }

  const link = event.target.closest('a[data-nav]');
  if (link) {
    event.preventDefault();
    await navigate(link.href);
    return;
  }

  const providerApplicationAction = event.target.closest('[data-provider-application-action]');
  if (providerApplicationAction) {
    if (providerApplicationAction.dataset.providerApplicationAction === 'edit'
        && !state.providerApplication.submitting && providerApplicationIsEligible()) {
      state.providerApplication.confirming = false;
      state.providerApplication.message = '';
      state.providerApplication.validatedValues = null;
      render();
    }
    return;
  }

  const cancellationAction = event.target.closest('[data-cancel-draft-action]');
  if (cancellationAction) {
    const requestId = new URLSearchParams(window.location.search).get('requestId') ?? '';
    const action = cancellationAction.dataset.cancelDraftAction;
    if (action === 'open' && state.customerRequestDetail?.ok
        && state.customerRequestDetail.data?.id === requestId
        && state.customerRequestDetail.data?.status === 'draft'
        && state.access?.kind === 'allowed' && state.access?.role === 'customer'
        && state.routeProfile?.account_status === 'active'
        && !state.customerDraftPublication.blocked
        && !state.customerDraftPublication.confirming
        && !state.customerDraftPublication.submitting) {
      state.customerDraftCancellation = {
        requestId, confirming: true, submitting: false, confirmed: false, blocked: false, message: '',
      };
      render();
    } else if (action === 'keep') {
      resetCustomerDraftCancellation(requestId);
      render();
    }
    return;
  }

  const publicationAction = event.target.closest('[data-publish-draft-action]');
  if (publicationAction) {
    const requestId = new URLSearchParams(window.location.search).get('requestId') ?? '';
    const action = publicationAction.dataset.publishDraftAction;
    if (action === 'open' && state.customerRequestDetail?.ok
        && state.customerRequestDetail.data?.id === requestId
        && state.customerRequestDetail.data?.status === 'draft'
        && state.access?.kind === 'allowed' && state.access?.role === 'customer'
        && state.routeProfile?.account_status === 'active'
        && state.customerDraftPublication.requestId === requestId
        && !state.customerDraftPublication.blocked
        && !state.customerDraftCancellation.blocked
        && !state.customerDraftCancellation.confirming
        && !state.customerDraftCancellation.submitting) {
      state.customerDraftPublication = {
        requestId, confirming: true, submitting: false, confirmed: false, blocked: false, message: '',
      };
      render();
    } else if (action === 'keep') {
      resetCustomerDraftPublication(requestId);
      render();
    }
    return;
  }

  const providerDiscoveryAction = event.target.closest('[data-provider-discovery-action]');
  const customerBidViewAction = event.target.closest('[data-customer-bid-view-action]');
  if (customerBidViewAction) {
    const action = customerBidViewAction.dataset.customerBidViewAction;
    if (action === 'view' || action === 'refresh') await loadCustomerBidView();
    if (action === 'load-more') await loadCustomerBidView({ append: true });
    return;
  }

  if (providerDiscoveryAction) {
    const action = providerDiscoveryAction.dataset.providerDiscoveryAction;
    if (action === 'refresh') await loadProviderDiscovery();
    if (action === 'load-more') await loadProviderDiscovery({ append: true });
    return;
  }

  const providerBidAction = event.target.closest('[data-provider-bid-action]');
  if (providerBidAction) {
    const requestId = String(providerBidAction.dataset.providerBidRequest ?? '');
    const action = providerBidAction.dataset.providerBidAction;
    if (action === 'cancel' && !providerBidMutationInFlight) {
      state.providerBidding.action = null;
      render();
    }
    if (action === 'withdraw') openProviderBidWithdrawal(requestId);
    return;
  }

  const toggle = event.target.closest('[data-menu-toggle]');
  if (toggle) {
    const nav = document.querySelector('#primary-nav');
    const expanded = toggle.getAttribute('aria-expanded') === 'true';
    toggle.setAttribute('aria-expanded', String(!expanded));
    nav?.classList.toggle('is-open', !expanded);
  }
});

document.addEventListener('submit', async (event) => {
  const providerBidConfirmation = event.target.closest('[data-provider-bid-confirm-form]');
  if (providerBidConfirmation) {
    event.preventDefault();
    await submitProviderBidConfirmation();
    return;
  }
  const providerBidForm = event.target.closest('[data-provider-bid-form]');
  if (providerBidForm) {
    event.preventDefault();
    reviewProviderBid(providerBidForm);
    return;
  }
  const providerApplicationConfirmation = event.target.closest('[data-provider-application-confirm-form]');
  if (providerApplicationConfirmation) {
    event.preventDefault();
    await submitProviderApplicationConfirmation();
    return;
  }
  const providerApplicationForm = event.target.closest('[data-provider-application-form]');
  if (providerApplicationForm) {
    event.preventDefault();
    reviewProviderApplication(providerApplicationForm);
    return;
  }
  const publicationForm = event.target.closest('[data-publish-draft-form]');
  if (publicationForm) {
    event.preventDefault();
    await submitCustomerDraftPublication();
    return;
  }
  const cancellationForm = event.target.closest('[data-cancel-draft-form]');
  if (cancellationForm) {
    event.preventDefault();
    await submitCustomerDraftCancellation();
    return;
  }
  const editForm = event.target.closest('[data-draft-edit-form]');
  if (editForm) {
    event.preventDefault();
    await submitCustomerDraftEdit(editForm);
    return;
  }
  const requestForm = event.target.closest('[data-draft-request-form]');
  if (requestForm) {
    event.preventDefault();
    await submitCustomerDraftForm(requestForm);
    return;
  }
  const form = event.target.closest('[data-auth-form]');
  if (!form) return;
  event.preventDefault();
  await submitAuthForm(form);
});

window.addEventListener('popstate', refreshRoute);
render();
initialize();
