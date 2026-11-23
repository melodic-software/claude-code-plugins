import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const SKILL_ROOT = path.resolve(__dirname, "..", "..", "..");

const DEFAULT_CONFIG_DIR = path.join(SKILL_ROOT, "profile-defaults");

function envDir(name) {
  const value = process.env[name]?.trim();
  return value || null;
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

export function configDir(profile = activeProfile()) {
  const safeProfile = validateProfileName(profile);
  const proj = envDir("CLAUDE_PROJECT_DIR");
  if (!proj) return DEFAULT_CONFIG_DIR;
  const base = path.join(proj, ".claude", "ai-briefing");
  return safeProfile === "default" ? base : path.join(base, safeProfile);
}

function pluginDataDir() {
  const data = envDir("CLAUDE_PLUGIN_DATA");
  const lastSegment = data?.replace(/[\\/]+$/, "").split(/[\\/]/).pop() ?? "";
  return /^ai-briefing(-|$)/.test(lastSegment) ? data : null;
}

export function stateRoot(profile = activeProfile()) {
  const safeProfile = validateProfileName(profile);
  const data = pluginDataDir();
  return data ? path.join(data, safeProfile) : SKILL_ROOT;
}

export function meetingsDir(profile) {
  return path.join(stateRoot(profile), "output", "meetings");
}

export function deckPath(meetingNumber, extension, profile) {
  return path.join(meetingsDir(profile), `ai-meeting-${meetingNumber}.${extension}`);
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

export async function loadSlidesData(profile) {
  return import(pathToFileURL(slidesDataPath(profile)).href);
}
