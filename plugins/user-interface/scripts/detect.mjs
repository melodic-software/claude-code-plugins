#!/usr/bin/env node
// Prints the project's design-system signals and the routed tools that are installed, as JSON:
//   {"project": {...}, "installed": [row ids] | null, "reachable": {row id: true | false | null},
//    "reason"?: "why installed is null, or why a list was matched by name",
//    "uncertain"?: {row id: "why it was left out of installed"}}
// A bare plugin detect means this plugin's own marketplace: the one in the plugin-list record whose
// installPath is this plugin's root. Without that record, or when its marketplace is inline,
// skills-dir or synced, a bare name matches in any marketplace and `reason` says so; a bare name
// some row also detects qualified is then left out of installed and listed in `uncertain`.
// Usage: detect.mjs [--project DIR] [--home DIR] [--plugin-list-json FILE] [--mcp-list FILE]
// The two list flags replace the live `claude plugin list --json` and `claude mcp list` calls.
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ROUTING = join(ROOT, "reference/routing.json");
// Marketplace names that do not identify a marketplace a sibling plugin could come from.
const NO_MARKETPLACE = ["inline", "skills-dir", "synced"];

// Design-system, component and terminal-styling packages. An entry ending in "/" is a scope prefix.
const PACKAGES = [
  "@mui/", "@chakra-ui/", "@mantine/", "@radix-ui/", "@fluentui/", "@carbon/", "@primer/", "@storybook/",
  "@angular/material", "@material/web", "@headlessui/react", "@adobe/react-spectrum", "antd", "bootstrap",
  "react-bootstrap", "vuetify", "tailwindcss", "daisyui", "styled-components", "@emotion/react",
  "chalk", "kleur", "picocolors", "ink", "@clack/prompts", "@inquirer/prompts", "ora", "boxen", "cli-table3", "blessed", "figlet",
];
const TOKEN_FILE = /(^|[.-])tokens?\.json$|\.tokens$|^style-dictionary\.config\./i;
const TOKEN_DIRS = ["", "tokens", "design", "styles", "src/styles"];
const DOC_FILE = /^(design|design-system|styleguide|style-guide)\.md$/i;
const DOC_DIRS = ["", "docs"];

const { values: opts } = parseArgs({
  options: {
    project: { type: "string", default: process.cwd() },
    home: { type: "string", default: homedir() },
    "plugin-list-json": { type: "string" },
    "mcp-list": { type: "string" },
  },
});

const readJson = (file) => {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    return null;
  }
};
const isDir = (p) => existsSync(p) && statSync(p).isDirectory();
const filesIn = (dir, re) => (isDir(join(opts.project, dir)) ? readdirSync(join(opts.project, dir)).filter((f) => re.test(f)).map((f) => (dir ? `${dir}/${f}` : f)) : []);

function projectSignals() {
  const pkg = readJson(join(opts.project, "package.json")) ?? {};
  const deps = Object.keys({ ...pkg.dependencies, ...pkg.devDependencies, ...pkg.peerDependencies });
  const match = (d) => PACKAGES.some((p) => (p.endsWith("/") ? d.startsWith(p) : d === p));
  return {
    tokens: TOKEN_DIRS.flatMap((d) => filesIn(d, TOKEN_FILE)),
    packages: deps.filter(match).sort(),
    components_json: existsSync(join(opts.project, "components.json")),
    storybook: isDir(join(opts.project, ".storybook")),
    docs: DOC_DIRS.flatMap((d) => filesIn(d, DOC_FILE)),
    mcp_servers: Object.keys(readJson(join(opts.project, ".mcp.json"))?.mcpServers ?? {}).sort(),
  };
}

/** stdout of `claude <args>`, or an Error naming why it could not run.
 * The project is the cwd (scope resolution needs it), so on Windows the lookup skips the cwd:
 * a `claude.cmd` planted in a cloned project must not run. */
function claude(args) {
  const win = process.platform === "win32";
  const env = win ? { ...process.env, NoDefaultCurrentDirectoryInExePath: "1" } : process.env;
  const r = spawnSync("claude", args, { cwd: opts.project, encoding: "utf8", shell: win, env, timeout: 60_000 });
  if (r.error || r.status !== 0) return new Error(`claude ${args.join(" ")} failed: ${r.error?.code || r.stderr?.trim() || `exit ${r.status}`}`);
  return r.stdout;
}
const fromFileOr = (file, args) => (file ? readFileSync(file, "utf8") : claude(args));

/** Plugin ids in effect here: a project or local record enabled for this project, or any other scope
 * (user, managed) enabled. A fresh local install reads `enabled: true, projectEnabled: false` with this
 * project as `projectPath`; the CLI may emit `projectPath: null`. */
function enabledPlugins(records) {
  const here = resolve(opts.project);
  const forHere = (r) => r.projectEnabled || (r.enabled && r.projectPath != null && resolve(r.projectPath) === here);
  return new Set(records.filter((r) => (["project", "local"].includes(r.scope) ? forHere(r) : r.enabled)).map((r) => r.id));
}

/** The marketplace of the record installed at this plugin's root, or null. Each record resolves in its own
 * try, so a missing or unreadable installPath skips only that record. */
function ownMarketplace(records) {
  const real = (p) => (process.platform === "win32" ? realpathSync.native(p).toLowerCase() : realpathSync.native(p));
  const root = real(ROOT);
  for (const r of records) {
    try {
      if (r.installPath && real(r.installPath) === root) return r.id.slice(r.id.lastIndexOf("@") + 1);
    } catch {
      // skip this record
    }
  }
  return null;
}

/** Server name to connected (true or false) from `claude mcp list` lines shaped `name: target - status`. */
function mcpStatus(text) {
  const status = new Map();
  for (const line of text.split("\n")) {
    const m = line.match(/^(.+?): .* - (.*)$/);
    if (m) status.set(m[1], /Connected$/.test(m[2]) && !/Not connected$/i.test(m[2]));
  }
  return status;
}

function installed(rows, project) {
  const pluginText = fromFileOr(opts["plugin-list-json"], ["plugin", "list", "--json"]);
  if (pluginText instanceof Error) return { installed: null, reason: pluginText.message };
  let plugins, own;
  try {
    const records = JSON.parse(pluginText);
    plugins = enabledPlugins(records);
    own = ownMarketplace(records);
  } catch (e) {
    return { installed: null, reason: `unreadable plugin list: ${e.message}` };
  }
  const mcpText = fromFileOr(opts["mcp-list"], ["mcp", "list"]);
  if (mcpText instanceof Error) return { installed: null, reason: mcpText.message };
  const listed = mcpStatus(mcpText);
  const servers = [...listed.keys(), ...project.mcp_servers];
  const server = (row) => servers.find((s) => s === row.detect || s.endsWith(`:${row.detect}`));
  const skillDirs = [join(opts.home, ".claude/skills"), join(opts.project, ".claude/skills")];
  const resolved = own && !NO_MARKETPLACE.includes(own);
  const names = new Set([...plugins].filter((id) => typeof id === "string").map((id) => id.slice(0, id.lastIndexOf("@"))));
  const qualified = new Map(rows.filter((r) => r.detect.includes("@")).map((r) => [r.detect.slice(0, r.detect.lastIndexOf("@")), r.detect]));
  const uncertain = {};
  const barePlugin = (row) => row.kind === "plugin" || (row.kind === "skill" && /^\/[^:]+:/.test(row.id));
  const byName = (row) => {
    if (!names.has(row.detect)) return false;
    if (!qualified.has(row.detect)) return true;
    uncertain[row.id] = `${row.detect} also used by ${qualified.get(row.detect)}`;
    return false;
  };

  const present = (row) => {
    if (row.detect.includes("@")) return plugins.has(row.detect);
    if (barePlugin(row)) return resolved ? plugins.has(`${row.detect}@${own}`) : byName(row);
    if (row.kind === "mcp") return server(row) !== undefined;
    if (row.kind === "skill") return skillDirs.some((d) => isDir(join(d, row.detect)));
    return false; // kind tool: only the session's own tool listing can tell
  };
  // true or false when this script can tell; null when only an account, a key or the session can.
  const reach = (row) => {
    if (row.kind === "mcp") return listed.get(server(row)) ?? null;
    return row.account === "none" ? true : null;
  };
  const found = rows.filter(present);
  return {
    installed: [...new Set(found.map((r) => r.id))],
    reachable: Object.fromEntries(found.map((r) => [r.id, reach(r)])),
    ...(!resolved && { reason: `own marketplace unresolved (${own ?? "no record at this plugin's path"}); matched by name` }),
    ...(Object.keys(uncertain).length && { uncertain }),
  };
}

const project = projectSignals();
const { rows } = JSON.parse(readFileSync(ROUTING, "utf8"));
console.log(JSON.stringify({ project, ...installed(rows, project) }));
