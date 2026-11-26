import { detectEntry, loadManifest } from "./prerequisites.mjs";

const FAILED = new Set(["missing", "outdated"]);

export function missingRequired(plugins, { env, platform, cwd, dataDirOf }) {
  const out = [];
  for (const { id, installPath } of plugins) {
    if (!installPath) continue;
    const { manifest, errors, absent } = loadManifest(installPath);
    if (absent) continue;
    if (errors.length) {
      out.push({ plugin: id, tool: null, detail: `prerequisites.json fails the schema: ${errors.join("; ")}`, degrade: null, install: [] });
      continue;
    }
    const ctx = { env, platform, cwd, root: installPath, dataDir: dataDirOf(id) };
    for (const entry of manifest.requires.filter((e) => e.need === "required")) {
      const { status, detail } = detectEntry(entry, ctx);
      if (!FAILED.has(status)) continue;
      const install = Object.entries(entry.install).map(([manager, hint]) => `${manager}: ${hint}`);
      out.push({ plugin: id, tool: entry.id, detail, degrade: entry.degrade, install });
    }
  }
  return out;
}
