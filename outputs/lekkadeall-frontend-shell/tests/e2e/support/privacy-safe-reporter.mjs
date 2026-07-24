const SAFE_GUARD_PHASE = /^guard-state:(restricted|suspended|closed|provider|missing-profile)$/u;

function failedGuardPhase(steps = []) {
  for (const step of steps) {
    const nested = failedGuardPhase(step.steps);
    if (nested) return nested;
    if (step.error && SAFE_GUARD_PHASE.test(step.title)) return step.title;
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
    const guardPhase = status === 'FAIL' ? failedGuardPhase(result.steps) : null;
    const phase = guardPhase ? ` [${guardPhase}]` : '';
    process.stdout.write(`${status} [${category}]${phase} ${test.titlePath().slice(1).join(' > ')}\n`);
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
