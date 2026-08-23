// The orphan-file control for the knip capture: nothing in the fixture project
// imports this module, so knip reports the whole file, not its exports.
// Orphaned-file coverage is a TS/JS-only capability of the roster.

export function parseLegacyManifest(text: string): string[] {
  return text.split("\n").filter((line) => line.length > 0);
}
