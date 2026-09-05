// Fixture source for the code-metrics suites: one exported function with two
// branches and a comment, so every collector has something to report.

export function classify(value: number): string {
  if (value > 0) {
    return "positive";
  }
  if (value === 0) {
    return "zero";
  }
  return "negative";
}
