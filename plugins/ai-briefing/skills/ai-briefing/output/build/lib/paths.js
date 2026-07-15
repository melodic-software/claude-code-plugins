// Build-pipeline root resolution — mirrors scripts/lib/paths.js. Bundled build
// scripts live under a read-only plugin cache, so every generated artifact
// (slides-data.js, deck files, validation screenshots) is written under the
// machine-local state root, keyed per profile. In-repo (no plugin env) these
// fall back to the skill tree so the pipeline runs unchanged outside a plugin.

import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// output/build/lib/paths.js -> build dir is one up, skill root three up.
export const BUILD_DIR = path.resolve(__dirname, "..");
export const SKILL_ROOT = path.resolve(__dirname, "..", "..", "..");

// Empty fallback used when no consumer project is present (in-repo / test runs).
export const DEFAULT_CONFIG_DIR = path.join(SKILL_ROOT, "profile-defaults");

function envDir(name) {
  const v = process.env[name];
  return v && v.trim() ? v.trim() : null;
}

export function validateProfileName(value) {
  const windowsDeviceName = /^(?:con|prn|aux|nul|clock\$|com[1-9]|lpt[1-9])$/i;
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > 63 ||
    !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value) ||
    windowsDeviceName.test(value)
  ) {
    throw new Error(
      "AI_BRIEFING_PROFILE must be a 1-63 character lowercase-kebab slug and not a reserved Windows device name",
    );
  }
  return value;
}

export function activeProfile() {
  return validateProfileName(envDir("AI_BRIEFING_PROFILE") ?? "default");
}

// Tracked per-profile config directory under the consumer's project — the home
// of the profile's brand.json overlay + logo assets. The default profile lives at
// the folder root; a named profile overlays it in a subfolder. Mirrors
// scripts/lib/paths.js configDir() so the build resolves the same config seam.
export function configDir(profile = activeProfile()) {
  const safeProfile = validateProfileName(profile);
  const proj = envDir("CLAUDE_PROJECT_DIR");
  if (!proj) return DEFAULT_CONFIG_DIR;
  const base = path.join(proj, ".claude", "ai-briefing");
  return safeProfile === "default" ? base : path.join(base, safeProfile);
}

export function stateRoot(profile = activeProfile()) {
  const safeProfile = validateProfileName(profile);
  const data = envDir("CLAUDE_PLUGIN_DATA");
  return data ? path.join(data, safeProfile) : SKILL_ROOT;
}

export function meetingsDir(profile) {
  return path.join(stateRoot(profile), "output", "meetings");
}

export function buildOutDir(profile) {
  return path.join(stateRoot(profile), "output", "build");
}

export function slidesDataPath(profile) {
  return path.join(buildOutDir(profile), "slides-data.js");
}

export function shotsDir(profile) {
  return path.join(buildOutDir(profile), "shots");
}

// Dynamic import of the generated deck module from the state root — the emitted
// slides-data.js is machine state, not a bundled module, so it cannot be a
// static `import "./slides-data.js"`.
export async function loadSlidesData(profile) {
  return import(pathToFileURL(slidesDataPath(profile)).href);
}
