import { readFileSync } from "node:fs";
import { join } from "node:path";

export const usageFile = ({ env, home }) => (env.CLAUDE_CONFIG_DIR ? join(env.CLAUDE_CONFIG_DIR, ".claude.json") : join(home, ".claude.json"));

function counts(section) {
  if (section === null || typeof section !== "object" || Array.isArray(section)) return [];
  return Object.entries(section)
    .filter(([, v]) => Number.isFinite(v?.usageCount) && v.usageCount > 0)
    .map(([name, v]) => ({ name, count: v.usageCount, lastUsedAt: Number.isFinite(v.lastUsedAt) ? new Date(v.lastUsedAt).toISOString() : null }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
}

function readDoc(path, read) {
  try {
    return JSON.parse(read(path));
  } catch {
    return null;
  }
}

export function knownFolders(path, read = (p) => readFileSync(p, "utf8")) {
  const projects = readDoc(path, read)?.projects;
  return projects !== null && typeof projects === "object" && !Array.isArray(projects) ? Object.keys(projects) : [];
}

export function readUsage(path, read = (p) => readFileSync(p, "utf8")) {
  const doc = readDoc(path, read);
  if (doc === null) return { source: null, skills: [], plugins: [] };
  const skills = counts(doc?.skillUsage);
  const plugins = counts(doc?.pluginUsage);
  return { source: skills.length || plugins.length ? path : null, skills, plugins };
}
