const SAFE_FAILURE_PHASE = /^(?:registration-failure:(signup-http-429|signup-http-conflict|signup-http-other|signup-session-missing|profile-readiness-timeout|signup-network-failure|signup-duplicate-request|signup-unexpected-collision|signup-reconciliation-invalid|signup-reconciliation-session-failure)|registration-phase:(identity-precondition|signup-request|auth-session|profile-ready|dashboard)|ambiguous-update-failure:(isolated-setup|single-update-execution|ambiguous-ui|interception-release|detail-navigation|fresh-rls-read|canonical-values|postcondition|sign-out|cleanup)|guard-state:(restricted|suspended|closed|provider|missing-profile)|negative-actor-phase:(restricted|suspended|closed|provider|missing-profile):(auth-creation|ticket-9b-profile-readiness|browser-session|fixture-state-application|route-guard-verification|sign-out)|negative-actor-failure:(restricted|suspended|closed|provider|missing-profile):(auth-creation|ticket-9b-profile-readiness|browser-session|fixture-state-application|route-guard-verification|sign-out)|lifecycle-phase:(registration|reauthentication|category-dashboard|create|list-detail|update|cancel|postcondition|sign-out))$/u;
const SAFE_PROGRESS_PHASE = /^ambiguous-update:(?:mutation-executed|interceptor-release-start|fetch-disabled|cdp-detached|detail-navigation|rls-read-observed|canonical-values-verified|cleanup)$/u;

function failedSafePhase(steps = []) {
  for (const step of steps) {
    const nested = failedSafePhase(step.steps);
    if (nested) return nested;
    if (step.error && SAFE_FAILURE_PHASE.test(step.title)) return step.title;
  }
  return null;
}

export default class PrivacySafeReporter {
  onBegin(_config, suite) {
    process.stdout.write(`Ticket 9A-9 E2E: ${suite.allTests().length} synthetic local tests\n`);
  }

  onTestEnd(test, result) {
    const status = result.status === 'passed' ? 'PASS' : 'FAIL';
    const category = {
      passed: 'passed',
      timedOut: 'timeout',
      failed: 'assertion-or-runtime',
      interrupted: 'interrupted',
      skipped: 'skipped',
    }[result.status] ?? 'unknown';
    const safePhase = status === 'FAIL' ? failedSafePhase(result.steps) : null;
    const phase = safePhase ? ` [${safePhase}]` : '';
    process.stdout.write(`${status} [${category}]${phase} ${test.titlePath().slice(1).join(' > ')}\n`);
  }

  onStepEnd(_test, _result, step) {
    if (!step.error && SAFE_PROGRESS_PHASE.test(step.title)) {
      process.stdout.write(`PHASE ${step.title}\n`);
    }
  }

  onError() {
    process.stdout.write('FAIL E2E runner error (details withheld by privacy policy)\n');
  }

  onEnd(result) {
    process.stdout.write(`Ticket 9A-9 E2E result: ${result.status}\n`);
  }

  printsToStdio() {
    return true;
  }
}
