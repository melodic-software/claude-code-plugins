// Drift detail for the generated-block CI generators
// (scripts/generate-catalog.mjs, scripts/generate-cheatsheet.mjs), reached
// through the shared flow in scripts/lib/marker-block.mjs. On drift it points the
// reader at the first generated line where the committed and freshly generated
// blocks part company; the header message ("<thing> drift: ...") stays with each
// generator, because it names that generator's output file and rerun command.
//
// Emits nothing when findIndex finds no differing line (the blocks differ only in
// lines past the end of the generated one).
export function reportFirstDifference(expected, existing) {
  const expectedLines = expected.split("\n");
  const existingLines = existing.split("\n");
  const at = expectedLines.findIndex((line, i) => line !== existingLines[i]);
  if (at === -1) return;
  console.error(`First difference at generated line ${at + 1}:`);
  console.error(`  expected: ${JSON.stringify(expectedLines[at] ?? null)}`);
  console.error(`  found:    ${JSON.stringify(existingLines[at] ?? null)}`);
}
