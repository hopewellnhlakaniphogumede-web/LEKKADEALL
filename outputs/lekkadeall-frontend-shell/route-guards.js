const CUSTOMER_ROUTES = new Set([
  '/app/customer',
  '/app/customer/requests',
  '/app/customer/requests/detail',
  '/app/customer/requests/new',
  '/app/settings',
]);
const PROTECTED_ROUTES = new Set([...CUSTOMER_ROUTES, '/app/provider']);
const RESTRICTED_STATUSES = new Set(['restricted', 'suspended', 'closed']);

export function isProtectedRoute(pathname) {
  return PROTECTED_ROUTES.has(pathname);
}

export function resolveRouteAccess(pathname, session, profile, options = {}) {
  if (!isProtectedRoute(pathname)) return { kind: 'public' };
  if (!session?.user?.id) {
    return { kind: options.expired ? 'expired' : 'signedOut' };
  }
  if (!profile) return { kind: 'missingProfile' };
  if (RESTRICTED_STATUSES.has(profile.account_status)) {
    return { kind: 'restricted', accountStatus: profile.account_status };
  }
  if (profile.account_status !== 'active') return { kind: 'accessDenied' };

  if (profile.role === 'customer') {
    return CUSTOMER_ROUTES.has(pathname)
      ? { kind: 'allowed', role: 'customer' }
      : { kind: 'accessDenied' };
  }
  if (profile.role === 'provider') {
    return ['/app/provider', '/app/settings'].includes(pathname)
      ? { kind: 'allowed', role: 'provider' }
      : { kind: 'accessDenied' };
  }
  return { kind: 'accessDenied' };
}

export function defaultRouteForProfile(profile) {
  if (!profile || profile.account_status !== 'active') return '/access-denied';
  if (profile.role === 'customer') return '/app/customer';
  if (profile.role === 'provider') return '/app/provider';
  return '/access-denied';
}

export { CUSTOMER_ROUTES, PROTECTED_ROUTES, RESTRICTED_STATUSES };
