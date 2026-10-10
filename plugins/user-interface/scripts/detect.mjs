#!/usr/bin/env node
// Prints the project's design-system signals and the routed tools that are installed, as JSON:
//   {"project": {...}, "installed": [row ids] | null, "reachable": {row id: true | false | null},
//    "reason"?: "why installed is null, or why a list was matched by name",
//    "uncertain"?: {row id: "why it was left out of installed"}}
// Detection rules live in lib/installed.mjs.
// Usage: detect.mjs [--project DIR] [--home DIR] [--plugin-list-json FILE] [--mcp-list FILE]
// The two list flags replace the live `claude plugin list --json` and `claude mcp list` calls.
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { parseArgs } from "node:util";
import { fileURLToPath } from "node:url";
import { installed } from "./lib/installed.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ROUTING = join(ROOT, "reference/routing.json");

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

const project = projectSignals();
const { rows } = JSON.parse(readFileSync(ROUTING, "utf8"));
const found = installed(rows, {
  pluginRoot: ROOT,
  home: opts.home,
  projectDir: opts.project,
  projectMcpServers: project.mcp_servers,
  pluginList: () => fromFileOr(opts["plugin-list-json"], ["plugin", "list", "--json"]),
  mcpList: () => fromFileOr(opts["mcp-list"], ["mcp", "list"]),
});
console.log(JSON.stringify({ project, ...found }));
