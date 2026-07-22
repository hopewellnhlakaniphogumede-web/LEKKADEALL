const SUPABASE_BROWSER_BUNDLE = '/node_modules/@supabase/supabase-js/dist/umd/supabase.js';
let clientPromise;

async function loadBrowserFactory(documentRef = globalThis.document, globalRef = globalThis) {
  if (typeof globalRef.supabase?.createClient === 'function') {
    return globalRef.supabase.createClient;
  }
  if (!documentRef?.head) throw new Error('browser-client-unavailable');

  await new Promise((resolve, reject) => {
    const existing = documentRef.querySelector('script[data-supabase-browser-bundle]');
    if (existing) {
      existing.addEventListener('load', resolve, { once: true });
      existing.addEventListener('error', reject, { once: true });
      return;
    }

    const script = documentRef.createElement('script');
    script.src = SUPABASE_BROWSER_BUNDLE;
    script.async = true;
    script.dataset.supabaseBrowserBundle = 'pinned-local-package';
    script.addEventListener('load', resolve, { once: true });
    script.addEventListener('error', reject, { once: true });
    documentRef.head.append(script);
  });

  if (typeof globalRef.supabase?.createClient !== 'function') {
    throw new Error('browser-client-unavailable');
  }
  return globalRef.supabase.createClient;
}

export function createPublicSupabaseClient(config, createClientImpl) {
  if (!config?.supabaseUrl || !config?.supabaseAnonKey || typeof createClientImpl !== 'function') {
    throw new Error('invalid-public-client-configuration');
  }

  return createClientImpl(config.supabaseUrl, config.supabaseAnonKey, {
    db: { schema: 'public' },
    auth: {
      flowType: 'pkce',
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  });
}

export function getPublicSupabaseClient(config, dependencies = {}) {
  if (!clientPromise) {
    clientPromise = (async () => {
      const factory = dependencies.createClient
        ?? await loadBrowserFactory(dependencies.documentRef, dependencies.globalRef);
      return createPublicSupabaseClient(config, factory);
    })();
  }
  return clientPromise;
}

export function resetPublicClientForTests() {
  clientPromise = undefined;
}

export { SUPABASE_BROWSER_BUNDLE };
