// Public browser configuration only. Copy to runtime-config.local.js and
// replace placeholders locally or during deployment. Never put server secrets here.
globalThis.__LEKKADEALL_PUBLIC_CONFIG__ = Object.freeze({
  appEnv: 'development',
  appUrl: 'http://localhost:4173',
  supabaseUrl: 'https://YOUR_PROJECT_REF.supabase.co',
  supabaseAnonKey: 'YOUR_SUPABASE_ANON_KEY',
});
