const CONFIG_GLOBAL = '__LEKKADEALL_PUBLIC_CONFIG__';
const ALLOWED_ENVIRONMENTS = new Set(['development', 'test', 'production']);

function isPlaceholder(value) {
  return !value || /YOUR_|PLACEHOLDER|CHANGEME/i.test(value);
}

export async function loadRuntimeConfig(importModule = (path) => import(path)) {
  if (globalThis[CONFIG_GLOBAL]) return;

  try {
    await importModule('./runtime-config.local.js');
  } catch {
    await importModule('./runtime-config.example.js');
  }
}

export function readPublicConfig(source = globalThis[CONFIG_GLOBAL]) {
  if (!source || typeof source !== 'object') {
    return { ok: false, reason: 'missing' };
  }

  const config = {
    appEnv: String(source.appEnv ?? '').trim(),
    appUrl: String(source.appUrl ?? '').trim(),
    supabaseUrl: String(source.supabaseUrl ?? '').trim(),
    supabaseAnonKey: String(source.supabaseAnonKey ?? '').trim(),
  };

  if (!ALLOWED_ENVIRONMENTS.has(config.appEnv)) {
    return { ok: false, reason: 'invalid-environment' };
  }

  if (isPlaceholder(config.supabaseUrl) || isPlaceholder(config.supabaseAnonKey)) {
    return { ok: false, reason: 'placeholder' };
  }

  try {
    const appUrl = new URL(config.appUrl);
    const supabaseUrl = new URL(config.supabaseUrl);
    const localApp = ['localhost', '127.0.0.1'].includes(appUrl.hostname);

    if (appUrl.pathname !== '/' || appUrl.search || appUrl.hash) {
      return { ok: false, reason: 'invalid-app-url' };
    }
    if (config.appEnv === 'production' && appUrl.protocol !== 'https:') {
      return { ok: false, reason: 'insecure-app-url' };
    }
    if (!localApp && !['http:', 'https:'].includes(appUrl.protocol)) {
      return { ok: false, reason: 'invalid-app-url' };
    }
    if (supabaseUrl.protocol !== 'https:' || supabaseUrl.username || supabaseUrl.password) {
      return { ok: false, reason: 'invalid-supabase-url' };
    }
  } catch {
    return { ok: false, reason: 'invalid-url' };
  }

  return { ok: true, config: Object.freeze(config) };
}

export const PUBLIC_CONFIG_KEYS = Object.freeze([
  'PUBLIC_APP_ENV',
  'PUBLIC_APP_URL',
  'PUBLIC_SUPABASE_URL',
  'PUBLIC_SUPABASE_ANON_KEY',
]);
