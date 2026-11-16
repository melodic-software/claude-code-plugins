// The required prerequisites a set of plugins declares and this machine lacks, read through the
// prerequisites contract (docs/contracts/prerequisites/README.md) with its vendored checker.
//
//   missingRequired(plugins, {env, platform, cwd, dataDirOf}) -> [{plugin, tool, detail, degrade, install}]
//
// plugins: [{id, installPath}]. A plugin with no prerequisites.json declares nothing; one whose
// file fails the schema is reported with that as its detail, since its needs cannot be read.
// install is the declared hints as "manager: hint" lines.
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
