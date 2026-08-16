/**
 * Shared "was this module run directly?" test for the package's CLI entrypoints.
 */

import path from "node:path";
import { fileURLToPath } from "node:url";

/**
 * True when the module is the script node was invoked with
 * (`node harvesting/run-harvest.js`), false when it was imported.
 *
 * @param {string} importMetaUrl - the caller's `import.meta.url`
 * @returns {boolean}
 */
export function isMainModule(importMetaUrl) {
  const invoked = process.argv[1];
  if (!invoked) return false;
  return path.resolve(invoked) === path.resolve(fileURLToPath(importMetaUrl));
}
