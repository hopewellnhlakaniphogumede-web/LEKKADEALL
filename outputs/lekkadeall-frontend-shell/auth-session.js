const GENERIC_SIGN_IN_ERROR = 'Unable to sign in with those details.';
const GENERIC_AUTH_ERROR = 'Authentication is temporarily unavailable. Please try again.';
const NEUTRAL_RECOVERY_MESSAGE = 'If an account matches, recovery instructions will be sent.';

export async function getCurrentSession(client) {
  const { data, error } = await client.auth.getSession();
  if (error) return { ok: false, session: null, message: GENERIC_AUTH_ERROR };
  return { ok: true, session: data.session ?? null };
}

export async function signInWithPassword(client, email, password) {
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error) return { ok: false, session: null, message: GENERIC_SIGN_IN_ERROR };
  return { ok: true, session: data.session ?? null };
}

export async function registerWithPassword(client, email, password, appUrl) {
  const { data, error } = await client.auth.signUp({
    email,
    password,
    options: { emailRedirectTo: `${appUrl}/auth/callback` },
  });
  if (error) return { ok: false, session: null, message: GENERIC_AUTH_ERROR };
  return {
    ok: true,
    session: data.session ?? null,
    requiresEmailConfirmation: !data.session,
  };
}

export async function requestPasswordReset(client, email, appUrl) {
  try {
    await client.auth.resetPasswordForEmail(email, {
      redirectTo: `${appUrl}/auth/reset-password`,
    });
  } catch {
    // The response remains neutral so account existence and provider errors are not exposed.
  }
  return { ok: true, message: NEUTRAL_RECOVERY_MESSAGE };
}

export async function updateRecoveryPassword(client, password) {
  const { error } = await client.auth.updateUser({ password });
  if (error) return { ok: false, message: GENERIC_AUTH_ERROR };
  return { ok: true, message: 'Password updated. You can continue to your account.' };
}

export function extractAuthCode(url) {
  try {
    const code = new URL(url).searchParams.get('code');
    return code && code.length <= 4096 ? code : null;
  } catch {
    return null;
  }
}

export async function exchangeAuthCode(client, url) {
  const code = extractAuthCode(url);
  if (!code) return { ok: false, session: null, message: GENERIC_AUTH_ERROR };
  const { data, error } = await client.auth.exchangeCodeForSession(code);
  if (error) return { ok: false, session: null, message: GENERIC_AUTH_ERROR };
  return { ok: true, session: data.session ?? null };
}

export async function signOut(client) {
  try {
    await client.auth.signOut();
  } catch {
    // The UI clears personal state and fails closed even when remote sign-out fails.
  }
  return { ok: true };
}

export function subscribeToAuthChanges(client, listener) {
  const { data } = client.auth.onAuthStateChange((event, session) => {
    queueMicrotask(() => listener(event, session ?? null));
  });
  return () => data.subscription.unsubscribe();
}

export { GENERIC_AUTH_ERROR, GENERIC_SIGN_IN_ERROR, NEUTRAL_RECOVERY_MESSAGE };
