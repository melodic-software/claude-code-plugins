#!/usr/bin/env node
/**
 * Install the youtube extraction pipeline's node dependencies into
 * `${CLAUDE_PLUGIN_DATA}/node_modules` — a per-plugin directory that survives
 * plugin updates (plugins-reference, persistent data directory). The plugin
 * ships without a committed `node_modules`; this runs once on first use and
 * again after an update whose `package.json` changed.
 *
 * Idempotent: a stored fingerprint gates reinstalls. Because the `file:./vendor/*`
 * packages are installed from bundled SOURCE (not fetched by version), the
 * fingerprint hashes `package.json` AND the entire `vendor/` tree — a plugin
 * update that changes vendored code without touching the top-level manifest must
 * still trigger a reinstall. `--install-links` packs the vendored packages as
 * real installs so they resolve from the data directory rather than a symlink
 * back into the plugin cache.
 *
 * Usage: node setup-deps.mjs
 */
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const data = process.env.CLAUDE_PLUGIN_DATA;

if (!data) {
  process.stderr.write(
    "CLAUDE_PLUGIN_DATA is not set. Run this inside Claude Code with the knowledge plugin installed.\n",
  );
  process.exit(1);
}

fs.mkdirSync(data, { recursive: true });

/** Fingerprint the install inputs: package.json + every file under vendor/. */
function computeStamp() {
  const hash = createHash("sha256");
  const files = ["package.json"];
  const vendorRoot = path.join(here, "vendor");
  if (fs.existsSync(vendorRoot)) {
    const walk = (dir) => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
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
const stampPath = path.join(data, ".youtube-extraction.stamp");
const installed = fs.existsSync(path.join(data, "node_modules", "@melodic", "video-digestion"));

if (installed && fs.existsSync(stampPath) && fs.readFileSync(stampPath, "utf8") === stamp) {
  process.stdout.write("youtube extraction deps already current.\n");
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
process.stdout.write(`youtube extraction deps installed to ${path.join(data, "node_modules")}.\n`);
