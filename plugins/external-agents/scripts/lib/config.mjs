import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, isAbsolute, join, posix, win32 } from "node:path";
import { fileURLToPath } from "node:url";
import { resolve } from "../../lib/config-cascade.mjs";

export const pluginRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const readJson = (file) => JSON.parse(readFileSync(join(pluginRoot, file), "utf8"));

const HELPER_FAIL = 3;
const HELPER_NO_HOME = [1, 4, 5];

/** The convention home the repository's pointer region binds; an unbound repository gets the default. */
export function conventionHome(projectRoot, helper = join(pluginRoot, "lib", "resolve-convention-home.sh")) {
  const done = spawnSync("bash", [helper, "--root", projectRoot], { cwd: pluginRoot, encoding: "utf8", timeout: 15_000, windowsHide: true });
  if (done.status === 0 && done.stdout.trim()) return { home: done.stdout.trim(), problem: null };
  const fallback = { home: "docs/conventions", problem: null };
  if (HELPER_NO_HOME.includes(done.status)) return fallback;
  if (done.status === HELPER_FAIL) return { ...fallback, problem: done.stderr.trim() };
  const how = done.error?.message ?? `exit ${done.status}: ${done.stderr.trim().split(/\r?\n/).at(-1) ?? ""}`;
  return { ...fallback, problem: `the convention-home helper did not run (${how})` };
}

const isTracked = (root, file) =>
  spawnSync("git", ["-C", root, "ls-files", "--error-unmatch", "--", file], { stdio: "ignore", windowsHide: true, cwd: pluginRoot }).status === 0;

/** The file names a binary_path may end in: the CLI's own name, with an executable extension on Windows. */
export const binaryNames = (name, platform = process.platform) =>
  platform === "win32" ? [".exe", ".cmd", ".bat"].map((ext) => `${name}${ext}`) : [name];

export function loadConfig({ projectRoot, home = "docs/conventions", userConfig } = {}) {
  const result = resolve({
    plugin: "external-agents",
    projectRoot,
    home,
    schema: readJson("schemas/external-agents.schema.json"),
    defaults: readJson("defaults.json"),
    userConfig,
  });
  const errors = result.layers.flatMap((layer) => layer.errors ?? []);
  for (const [product, settings] of Object.entries(result.values)) {
    const path = settings?.binary_path;
    if (path === undefined) continue;
    const key = `${product}.binary_path`;
    const why = result.provenance[key] !== "local"
      ? "is set only in the personal layer, never a committed team file, since it picks the executable that runs"
      : isTracked(projectRoot, join(isAbsolute(home) ? home : join(projectRoot, home), "external-agents.local.yaml"))
        ? "comes from a personal file tracked by git, so a branch could choose the executable that runs"
        : !(posix.isAbsolute(path) || win32.isAbsolute(path)) && "must be an absolute path";
    if (!why) continue;
    errors.push(`${result.provenance[key]}: ${key} ${why}; ignored`);
    delete settings.binary_path;
    delete result.provenance[key];
  }
  return { values: result.values, provenance: result.provenance, layers: result.layers, errors };
}
