
import process from "node:process";

export function createFixtureHarness() {
  const counts = { cases: 0, failed: 0 };
  const pass = (name) => {
    counts.cases += 1;
    process.stdout.write(`PASS: ${name}\n`);
  };
  const fail = (name, detail) => {
    counts.cases += 1;
    counts.failed += 1;
    process.stderr.write(`FAIL: ${name}\n  detail: ${detail}\n`);
  };
  const finish = (passedSummary, failedSummary) => {
    if (counts.failed === 0) {
      process.stdout.write(passedSummary);
      process.exit(0);
    }
    process.stderr.write(failedSummary);
    process.exit(1);
  };
  return { counts, pass, fail, finish };
}
