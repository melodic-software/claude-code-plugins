// The orphan-file control for the knip capture: nothing in the fixture project
// imports this module, so knip reports the whole file, not its exports.

export function parseLegacyManifest(text: string): string[] {
  return text.split("\n").filter((line) => line.length > 0);
}
