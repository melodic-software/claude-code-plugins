/**
 * Static course-platform adapter registry.
 *
 * Maps each platform id a course.json `platform` field may name to a
 * statically imported adapter module. Module resolution never depends on input
 * or configuration: there is no computed dynamic import, and a name the map
 * does not own (including prototype keys and path fragments) resolves to null.
 * Adding a platform means adding its import and entry here.
 */

import * as dometrain from "./dometrain.js";
import * as teachable from "./teachable.js";

/** Platform id to adapter module. */
export const PLATFORM_ADAPTERS = Object.freeze({ dometrain, teachable });

/**
 * @param {string} platform - e.g., "dometrain"
 * @returns {object|null} the registered adapter module, or null when none owns the name
 */
export function lookupAdapter(platform) {
  return Object.hasOwn(PLATFORM_ADAPTERS, platform) ? PLATFORM_ADAPTERS[platform] : null;
}
