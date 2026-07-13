/**
 * Platform config validation and adapter resolution.
 *
 * Validates platformConfig at startup (fail-fast) and dynamically imports
 * the correct adapter module for the course platform.
 */

import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { fail, ok } from "@melodic/video-digestion/shared/result";

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
 * Dynamically import an adapter module by platform name.
 * Returns the adapter module or null if not found.
 *
 * @param {string} platform — e.g., "dometrain"
 * @returns {Promise<object|null>}
 */
export async function resolveAdapter(platform) {
  const thisDir = dirname(fileURLToPath(import.meta.url));
  const adapterPath = join(thisDir, "..", "adapters", `${platform}.js`);
  if (!existsSync(adapterPath)) {
    return null;
  }
  return import(`../adapters/${platform}.js`);
}
