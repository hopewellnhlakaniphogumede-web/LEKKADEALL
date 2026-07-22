const JWT_PATTERN = /eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}/u;
const AUTH_STORAGE_KEY_PATTERN = /^sb-[a-z0-9-]+-auth-token$/iu;

export function attachSensitiveEmissionAudit(page, initialMarkers = []) {
  const markers = new Set(initialMarkers.map((value) => String(value)).filter((value) => value.length >= 4));
  let emittedSensitiveData = false;
  let pageError = false;

  function containsSensitive(value) {
    const text = String(value ?? '');
    return JWT_PATTERN.test(text) || [...markers].some((marker) => text.includes(marker));
  }

  page.on('console', (message) => {
    if (containsSensitive(message.text())) emittedSensitiveData = true;
  });
  page.on('pageerror', () => {
    pageError = true;
  });

  return Object.freeze({
    addMarkers(values) {
      for (const value of values) {
        const marker = String(value ?? '');
        if (marker.length >= 4) markers.add(marker);
      }
    },
    assertClean() {
      if (emittedSensitiveData || pageError) throw new Error('browser-sensitive-emission-detected');
    },
  });
}

export async function assertBrowserPrivacy(page, {
  markers = [],
  expectAuthSession = true,
} = {}) {
  const result = await page.evaluate(async ({ markerValues, authExpected }) => {
    const violations = [];
    const authKeyPattern = /^sb-[a-z0-9-]+-auth-token$/iu;
    const jwtPattern = /eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}/u;
    const sensitiveMarkers = markerValues.map(String).filter((value) => value.length >= 4);
    const containsSensitive = (value) => {
      const text = String(value ?? '');
      return jwtPattern.test(text) || sensitiveMarkers.some((marker) => text.includes(marker));
    };

    let authEntries = 0;
    for (let index = 0; index < localStorage.length; index += 1) {
      const key = localStorage.key(index) ?? '';
      const value = localStorage.getItem(key) ?? '';
      if (authKeyPattern.test(key)) {
        authEntries += 1;
        continue;
      }
      violations.push('unexpected-local-storage-entry');
      if (containsSensitive(`${key}\n${value}`)) violations.push('sensitive-local-storage-entry');
    }
    if (authExpected && authEntries !== 1) violations.push('expected-auth-session-missing');
    if (!authExpected && authEntries !== 0) violations.push('signed-out-auth-session-retained');

    if (sessionStorage.length !== 0) violations.push('unexpected-session-storage-entry');

    if (typeof indexedDB.databases === 'function') {
      const databases = await indexedDB.databases();
      if (databases.length !== 0) violations.push('unexpected-indexeddb-entry');
    }
    if ('caches' in globalThis) {
      const cacheNames = await caches.keys();
      if (cacheNames.length !== 0) violations.push('unexpected-cache-storage-entry');
    }
    if ('serviceWorker' in navigator) {
      const registrations = await navigator.serviceWorker.getRegistrations();
      if (registrations.length !== 0) violations.push('unexpected-service-worker');
    }
    if (document.cookie) violations.push('unexpected-application-cookie');

    const current = new URL(window.location.href);
    for (const key of ['code', 'access_token', 'refresh_token', 'token', 'token_hash', 'password']) {
      if (current.searchParams.has(key) || current.hash.includes(`${key}=`)) {
        violations.push('sensitive-url-parameter');
      }
    }
    if (containsSensitive(`${current.pathname}${current.search}${current.hash}`)) {
      violations.push('sensitive-url-content');
    }

    return { violations: [...new Set(violations)], authEntries };
  }, { markerValues: markers, authExpected: expectAuthSession });

  if (result.violations.length) throw new Error('browser-storage-privacy-violation');
  return result.authEntries;
}

export { AUTH_STORAGE_KEY_PATTERN };
