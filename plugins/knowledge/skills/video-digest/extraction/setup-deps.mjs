#!/usr/bin/env node
/**
 * Install the video extraction pipeline's node dependencies into
 * `${CLAUDE_PLUGIN_DATA}/node_modules` — a per-plugin directory that survives
 * plugin updates (plugins-reference, persistent data directory). The plugin
 * ships without a committed `node_modules`; this runs once on first use and
 * again after an update whose `package.json` changed.
 *
 * Idempotent: a stored fingerprint gates reinstalls. Because the `file:` vendor
 * packages are installed from bundled SOURCE (not fetched by version), the
 * fingerprint hashes `package.json` AND the entire shared `vendor/` tree — a plugin
 * update that changes vendored code without touching the top-level manifest must
 * still trigger a reinstall. `--install-links` packs the vendored packages as
 * real installs so they resolve from the data directory rather than a symlink
 * back into the plugin cache.
 *
 * The data directory comes from `--data-dir`, resolved like `run.mjs` resolves it
 * (`resolvePluginData`), and nothing is written until it resolves.
 *
 * Usage: node setup-deps.mjs --data-dir <dir>
 */
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import { parseRunArgs, resolvePluginData } from "./lib/run-args.js";

const here = import.meta.dirname;
const usage = "Usage: node setup-deps.mjs --data-dir <dir>\n";

let data;
try {
  const { dataDir, script, rest: _rest, ...otherFlags } = parseRunArgs(process.argv.slice(2));
  if (script !== undefined || Object.keys(otherFlags).length > 0) {
    throw new Error("setup-deps.mjs takes only `--data-dir <dir>`");
  }
  data = resolvePluginData(dataDir, process.env);
} catch (error) {
  process.stderr.write(`${error.message}\n${usage}`);
  process.exit(2);
}

if (!data) {
  process.stderr.write(
    'The knowledge plugin data directory is unknown. Pass --data-dir "${CLAUDE_PLUGIN_DATA}" from the skill; ' +
      "an inherited CLAUDE_PLUGIN_DATA that names another plugin is ignored.\n",
  );
  process.exit(1);
}

fs.mkdirSync(data, { recursive: true });

/** Fingerprint the install inputs: package.json + every file under vendor/. */
function computeStamp() {
  const hash = createHash("sha256");
  const files = ["package.json"];
  // Vendored libs are shared plugin-wide (both video-digest and course-digest consume
  // them), so they live at the plugin root, not under this skill.
  const vendorRoot = path.join(here, "..", "..", "..", "vendor");
  if (fs.existsSync(vendorRoot)) {
    // Traversal order is irrelevant: files.sort() below fixes the hash order.
    const walk = (dir) => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const abs = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(abs);
        else files.push(path.relative(here, abs).split(path.sep).join("/"));
      }
    };
    walk(vendorRoot);
  }
  for (const rel of files.sort()) {
    hash.update(rel);
    hash.update("\0");
    hash.update(fs.readFileSync(path.join(here, rel)));
    hash.update("\0");
  }
  return hash.digest("hex");
}

const stamp = computeStamp();
const stampPath = path.join(data, ".video-extraction.stamp");
const installed = fs.existsSync(path.join(data, "node_modules", "@melodic", "video-digestion"));

if (installed && fs.existsSync(stampPath) && fs.readFileSync(stampPath, "utf8") === stamp) {
  process.stdout.write("video extraction deps already current.\n");
  process.exit(0);
}

// npm is a `.cmd` shim on Windows, which node refuses to spawn without a shell
// (CVE-2024-27980); a shell with a separate args array trips DEP0190. Passing a
// single quoted command string with shell:true satisfies both. `here` is a
// plugin-owned path with no untrusted input, and JSON.stringify quotes it for
// both cmd.exe and POSIX sh.
const npmCommand = process.platform === "win32" ? "npm.cmd" : "npm";
const result = spawnSync(
  `${npmCommand} install --omit=dev --install-links ${JSON.stringify(here)}`,
  { cwd: data, stdio: "inherit", shell: true },
);

if (result.status !== 0) {
  process.stderr.write("npm install failed — see output above.\n");
  process.exit(result.status ?? 1);
}

fs.writeFileSync(stampPath, stamp);
process.stdout.write(`video extraction deps installed to ${path.join(data, "node_modules")}.\n`);
