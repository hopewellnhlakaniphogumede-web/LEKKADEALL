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
    process.stdout.write(`${status} [${category}] ${test.titlePath().slice(1).join(' > ')}\n`);
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
