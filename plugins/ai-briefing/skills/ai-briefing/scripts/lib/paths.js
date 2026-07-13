// Root resolution — separates the three homes a run touches:
//   - SKILL_ROOT  bundled, read-only plugin content (scripts, seed, build assets)
//   - stateRoot() machine-local per-profile state (seen-items, runs, generated decks)
//   - configDir() tracked per-profile config (following-list, brand overlay)
//
// In plugin form these resolve to ${CLAUDE_PLUGIN_DATA} / ${CLAUDE_PROJECT_DIR};
// running in-repo (no plugin env) they fall back to the skill's own tree so the
// engine and its tests work unchanged outside a plugin install.

import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// scripts/lib/paths.js -> skill root is two directories up.
export const SKILL_ROOT = path.resolve(__dirname, "..", "..");

// Bundled default-profile config seed shipped with the plugin.
export const SEED_DIR = path.join(SKILL_ROOT, "seed");

function envDir(name) {
  const v = process.env[name];
  return v && v.trim() ? v.trim() : null;
}

export function activeProfile() {
  return envDir("AI_BRIEFING_PROFILE") ?? "default";
}

// Machine-local per-profile state root. Never tracked, never in the plugin cache.
export function stateRoot(profile = activeProfile()) {
  const data = envDir("CLAUDE_PLUGIN_DATA");
  return data ? path.join(data, profile) : SKILL_ROOT;
}

// Tracked per-profile config directory under the consumer's project. The default
// profile lives at the folder root; a named profile overlays it in a subfolder.
export function configDir(profile = activeProfile()) {
  const proj = envDir("CLAUDE_PROJECT_DIR");
  if (!proj) return SEED_DIR;
  const base = path.join(proj, ".claude", "ai-briefing");
  return profile === "default" ? base : path.join(base, profile);
}
