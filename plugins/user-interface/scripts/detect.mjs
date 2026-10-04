#!/usr/bin/env node
// Prints the project's design-system signals and the routed tools that are installed, as JSON:
//   {"project": {...}, "installed": [row ids] | null, "reachable": {row id: true | false | null},
//    "reason"?: "why installed is null"}
// Usage: detect.mjs [--project DIR] [--home DIR] [--plugin-list-json FILE] [--mcp-list FILE]
// The two list flags replace the live `claude plugin list --json` and `claude mcp list` calls.
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { fileURLToPath } from "node:url";

const ROUTING = join(dirname(fileURLToPath(import.meta.url)), "../reference/routing.json");

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

/** stdout of `claude <args>`, or an Error naming why it could not run. */
function claude(args) {
  const r = spawnSync("claude", args, { encoding: "utf8", shell: process.platform === "win32", timeout: 60_000 });
  if (r.error || r.status !== 0) return new Error(`claude ${args.join(" ")} failed: ${r.error?.code ?? r.stderr?.trim() ?? r.status}`);
  return r.stdout;
}
const fromFileOr = (file, args) => (file ? readFileSync(file, "utf8") : claude(args));

/** Plugin ids in effect here: user scope enabled, or a project or local record enabled for this project.
 * A fresh local install reads `enabled: true, projectEnabled: false` with this project as `projectPath`. */
function enabledPlugins(text) {
  const here = resolve(opts.project);
  const forHere = (r) => r.projectEnabled || (r.enabled && r.projectPath !== undefined && resolve(r.projectPath) === here);
  const records = JSON.parse(text);
  return new Set(records.filter((r) => (r.scope === "user" ? r.enabled : forHere(r))).map((r) => r.id));
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
  let plugins;
  try {
    plugins = enabledPlugins(pluginText);
  } catch (e) {
    return { installed: null, reason: `unreadable plugin list: ${e.message}` };
  }
  const mcpText = fromFileOr(opts["mcp-list"], ["mcp", "list"]);
  if (mcpText instanceof Error) return { installed: null, reason: mcpText.message };
  const listed = mcpStatus(mcpText);
  const servers = [...listed.keys(), ...project.mcp_servers];
  const server = (row) => servers.find((s) => s === row.detect || s.endsWith(`:${row.detect}`));
  const skillDirs = [join(opts.home, ".claude/skills"), join(opts.project, ".claude/skills")];

  const present = (row) => {
    if (row.detect.includes("@")) return plugins.has(row.detect);
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
  };
}

const project = projectSignals();
const { rows } = JSON.parse(readFileSync(ROUTING, "utf8"));
console.log(JSON.stringify({ project, ...installed(rows, project) }));
