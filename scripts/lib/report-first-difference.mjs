// Shared drift detail for the generated-block CI generators
// (scripts/generate-catalog.mjs, scripts/generate-cheatsheet.mjs). Both compare a
// freshly generated block against the committed one and, on drift, point the
// reader at the first generated line where the two part company -- the header
// message ("<thing> drift: ...") stays with each generator, because it names that
// generator's output file and rerun command.
//
// Emits nothing when findIndex finds no differing line (the blocks differ only in
// lines past the end of the generated one), exactly as both call sites did inline.
export function reportFirstDifference(expected, existing) {
  const expectedLines = expected.split("\n");
  const existingLines = existing.split("\n");
  const at = expectedLines.findIndex((line, i) => line !== existingLines[i]);
  if (at === -1) return;
  console.error(`First difference at generated line ${at + 1}:`);
  console.error(`  expected: ${JSON.stringify(expectedLines[at] ?? null)}`);
  console.error(`  found:    ${JSON.stringify(existingLines[at] ?? null)}`);
}
