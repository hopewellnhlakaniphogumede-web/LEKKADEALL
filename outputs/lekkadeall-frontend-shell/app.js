import { renderRoute } from './shell.js';

const root = document.querySelector('#app');

function render() {
  root.innerHTML = renderRoute(window.location.pathname, new URLSearchParams(window.location.search));
  document.title = `LEKKADEALL — ${pageTitle(window.location.pathname)}`;
  window.scrollTo({ top: 0, behavior: 'auto' });
}

function pageTitle(pathname) {
  const titles = {
    '/': 'Local services, clearly arranged',
    '/services': 'Browse services',
    '/auth/sign-in': 'Sign in',
    '/auth/register': 'Register',
    '/auth/forgot-password': 'Forgot password',
    '/auth/reset-password': 'Reset password',
    '/auth/callback': 'Authentication callback',
    '/app/customer': 'Customer workspace',
    '/app/provider': 'Provider workspace',
    '/app/settings': 'Settings',
    '/access-denied': 'Access denied',
    '/account-restricted': 'Account restricted',
  };
  return titles[pathname.replace(/\/$/, '') || '/'] ?? 'Page not found';
}

function navigate(url) {
  const next = new URL(url, window.location.origin);
  if (next.origin !== window.location.origin) return;
  window.history.pushState({}, '', `${next.pathname}${next.search}`);
  render();
}

document.addEventListener('click', (event) => {
  const link = event.target.closest('a[data-nav]');
  if (link) {
    event.preventDefault();
    navigate(link.href);
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

document.addEventListener('submit', (event) => {
  const form = event.target.closest('[data-shell-form]');
  if (!form) return;
  event.preventDefault();
  const message = document.querySelector('[data-form-message]');
  if (message) {
    message.textContent = 'Shell only — nothing was transmitted. Authentication will be connected in a later ticket.';
  }
  form.reset();
});

window.addEventListener('popstate', render);
render();
