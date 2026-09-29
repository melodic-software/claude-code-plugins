import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

/**
 * True only when this process was started with the caller's file as the
 * entrypoint (`node harvesting/run-harvest.js`), false when it was imported.
 * Importing a CLI module must not parse argv or run main. Real paths are
 * compared because Node resolves import.meta.url through symlinks while
 * argv[1] keeps the path as typed, so a symlinked plugin root would otherwise
 * skip main and exit 0 without doing anything.
 *
 * @param {string} importMetaUrl - the caller's `import.meta.url`
 * @returns {boolean}
 */
export function isMainModule(importMetaUrl) {
  const entry = process.argv[1];
  if (!entry) return false;
  try {
    return realpathSync(entry) === realpathSync(fileURLToPath(importMetaUrl));
  } catch {
    return false;
  }
}
