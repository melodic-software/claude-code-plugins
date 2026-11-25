// GENERATED from lib/session-attended.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
import { readFileSync } from "node:fs";

const NAME = /^[A-Za-z_][A-Za-z0-9_]*$/;

function load() {
  try {
    const config = {};
    for (const raw of readFileSync(new URL("./session-attended.env", import.meta.url), "utf8").split("\n")) {
      const line = raw.trim();
      if (!line || line.startsWith("#")) continue;
      const eq = line.indexOf("=");
      if (eq < 1) return null;
      config[line.slice(0, eq)] = line.slice(eq + 1).replace(/^"(.*)"$/, "$1");
    }
    return config;
  } catch {
    return null;
  }
}

const config = load();

/**
 * Whether a person attends the session `env` describes, by the names and values in the
 * session-attended.env beside this file. False when that file is missing or malformed; never throws.
 * @param {Record<string, string | undefined>} env
 * @returns {boolean}
 */
export function sessionAttended(env) {
  try {
    const { SESSION_ATTENDED_VAR: attendedVar, SESSION_ATTENDED_VALUE: value, SESSION_ATTENDED_ENTRYPOINT_VAR: entrypointVar } = config ?? {};
    if (!NAME.test(attendedVar ?? "") || !NAME.test(entrypointVar ?? "") || !value) return false;
    if (env?.[attendedVar] !== value) return false;
    const entrypoint = env[entrypointVar] ?? "";
    return !entrypoint || !(config.SESSION_ATTENDED_HEADLESS_ENTRYPOINTS ?? "").split(/\s+/).includes(entrypoint);
  } catch {
    return false;
  }
}
