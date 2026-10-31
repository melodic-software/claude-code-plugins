/**
 * Platform config validation and adapter resolution.
 *
 * Validates platformConfig at startup (fail-fast) and looks up the adapter
 * module for the course platform in the static registry.
 */

import { fail, ok } from "@melodic/video-digestion/shared/result";

import { lookupAdapter } from "../adapters/registry.js";

const REQUIRED_FIELDS = ["videoPlayerSelector", "loginUrl", "authEnvPrefix"];

/**
 * Validate that platformConfig contains all required fields.
 * Returns a Result — fail-fast at startup, not mid-extraction.
 *
 * @param {object} platformCfg
 * @param {string} platform
 * @returns {import('@melodic/video-digestion/shared/result').Result}
 */
export function validatePlatformConfig(platformCfg, platform) {
  const missing = REQUIRED_FIELDS.filter((f) => !platformCfg[f]);
  if (missing.length > 0) {
    return fail(
      `Platform "${platform}" missing required platformConfig fields: ${missing.join(", ")}`,
      "validate-config",
      null,
      0,
    );
  }
  return ok(platformCfg, "validate-config", null, 0);
}

/**
 * Look up the registered adapter module for a platform name.
 * Returns the adapter module or null when the registry has no such platform.
 *
 * @param {string} platform - e.g., "dometrain"
 * @returns {Promise<object|null>}
 */
export async function resolveAdapter(platform) {
  return lookupAdapter(platform);
}
