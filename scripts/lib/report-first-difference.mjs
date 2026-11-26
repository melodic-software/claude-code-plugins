export function reportFirstDifference(expected, existing) {
  const expectedLines = expected.split("\n");
  const existingLines = existing.split("\n");
  const at = expectedLines.findIndex((line, i) => line !== existingLines[i]);
  if (at === -1) return;
  console.error(`First difference at generated line ${at + 1}:`);
  console.error(`  expected: ${JSON.stringify(expectedLines[at] ?? null)}`);
  console.error(`  found:    ${JSON.stringify(existingLines[at] ?? null)}`);
}
