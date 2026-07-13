/**
 * Resolve where a platform's Playwright session cookies persist.
 *
 * Auth state is a platform-level login session (reused across every course on
 * that platform), re-homed out of the consumer repo into the plugin's persistent
 * data directory so credentials survive plugin updates and never land in a
 * tracked course directory. Keyed by platform.
 *
 * `${CLAUDE_PLUGIN_DATA}/auth/<platform>.auth-state.json` under Claude Code; for
 * direct dev / test runs where the harness has not set CLAUDE_PLUGIN_DATA, a
 * machine-local `${home}/.claude/course-digest/auth/…` fallback keeps the same
 * out-of-repo, persistent shape. The directory is created on resolve so Playwright's
 * `storageState({ path })` — which does not create parent directories — can write.
 */
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export function resolveAuthDir() {
  const base = process.env.CLAUDE_PLUGIN_DATA || join(homedir(), ".claude", "course-digest");
  const dir = join(base, "auth");
  mkdirSync(dir, { recursive: true });
  return dir;
}

/**
 * @param {string} platform — e.g. "dometrain", "teachable"
 * @returns {string} absolute path to the platform's auth-state file
 */
export function resolveAuthStatePath(platform) {
  const safe = String(platform).replace(/[^a-z0-9_-]/gi, "-");
  return join(resolveAuthDir(), `${safe}.auth-state.json`);
}
