#!/usr/bin/env node
// Prints the project's design-system signals and the routed tools that are installed, as JSON:
//   {"project": {...}, "installed": [row ids] | null, "reachable": {row id: true | false | null},
//    "reason"?: "why installed is null, or why a list was matched by name",
//    "uncertain"?: {row id: "why it was left out of installed"}}
// project also carries browserslist {query, source}, lint {stylelint, eslint_css, config_paths} and
// style_files [kinds]. With --config, a top-level "config" holds the resolved settings
// (lib/config-cascade.mjs output: values, provenance, prose, layers, legacy) plus "home", the
// convention home. When the project's pointer line is unusable, "home" is null, "home_error" says
// why, and the team and local layers are not read.
// Detection rules live in lib/installed.mjs.
// Usage: detect.mjs [--project DIR] [--home DIR] [--plugin-list-json FILE] [--mcp-list FILE]
//                   [--config [--team FILE] [--user-config FILE]]
// The two list flags replace the live `claude plugin list --json` and `claude mcp list` calls.
// --team replaces the team file the convention home resolves to (a test seam); --user-config is a
// JSON file of the plugin's css_* userConfig values, read as data and never passed to a shell.
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, lstatSync, mkdtempSync, readdirSync, readFileSync, readlinkSync, realpathSync, rmSync, statSync, symlinkSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, extname, isAbsolute, join, relative, resolve as resolvePath } from "node:path";
import { parseArgs } from "node:util";
import { fileURLToPath } from "node:url";
import { resolve } from "./lib/config-cascade.mjs";
import { installed } from "./lib/installed.mjs";
import { validate } from "./lib/routing-validate.mjs";
import { parse as parseYaml } from "./lib/yaml-subset.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ROUTING = join(ROOT, "reference/routing.json");
const PLUGIN = "user-interface";
const DEFAULT_HOME = "docs/conventions";

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
const BROWSERSLIST_FILES = [".browserslistrc", "browserslist"];
const STYLELINT_CONFIG = /^(\.stylelintrc(\.(json|ya?ml|js|cjs|mjs))?|stylelint\.config\.(js|cjs|mjs|ts|cts|mts))$/;
const ESLINT_CONFIG = /^eslint\.config\.(js|cjs|mjs|ts|cts|mts)$/;
const ESLINT_CSS = ["@eslint/css", "eslint-plugin-css"];
const CSS_IN_JS = ["styled-components", "@emotion/react", "@emotion/styled", "@vanilla-extract/css", "@stitches/react", "@linaria/core", "@pandacss/dev"];
// Style kind by lowercased extension; a component kind counts only when the file holds a <style> block.
const STYLE_EXT = { ".css": "css", ".scss": "scss", ".sass": "sass", ".less": "less", ".styl": "stylus" };
const COMPONENT_EXT = { ".vue": "vue", ".svelte": "svelte", ".astro": "astro" };
const SKIP_DIRS = new Set(["node_modules", "dist", "build", "coverage", "out"]);
const MAX_ENTRIES = 20_000;

const { values: opts } = parseArgs({
  options: {
    project: { type: "string", default: process.cwd() },
    home: { type: "string", default: homedir() },
    "plugin-list-json": { type: "string" },
    "mcp-list": { type: "string" },
    config: { type: "boolean", default: false },
    team: { type: "string" },
    "user-config": { type: "string" },
  },
});

const readJson = (file) => {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    return null;
  }
};
const isMapping = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const isDir = (p) => existsSync(p) && statSync(p).isDirectory();
const isFile = (p) => existsSync(p) && statSync(p).isFile();
const filesIn = (dir, re) => (isDir(join(opts.project, dir)) ? readdirSync(join(opts.project, dir)).filter((f) => re.test(f)).map((f) => (dir ? `${dir}/${f}` : f)) : []);

/** The browserslist query the project declares, production environment first, and where. */
function browserslist(pkg) {
  const join_ = (q) => [q].flat().filter((s) => typeof s === "string" && s.trim()).map((s) => s.trim()).join(", ") || null;
  const own = pkg.browserslist;
  if (typeof own === "string" || Array.isArray(own)) return { query: join_(own), source: "package.json" };
  if (isMapping(own)) return { query: join_(own.production ?? own.defaults ?? []), source: "package.json" };
  for (const name of BROWSERSLIST_FILES) {
    const file = join(opts.project, name);
    if (!isFile(file)) continue;
    const plain = [];
    const production = [];
    let into = plain; // lines before any [env] section are the defaults
    for (const raw of readFileSync(file, "utf8").split(/\r?\n/)) {
      const line = raw.replace(/#.*$/, "").trim();
      const section = line.match(/^\[(.*)\]$/);
      if (section) into = section[1].trim().split(/\s+/).includes("production") ? production : null;
      else if (line && into) into.push(line);
    }
    return { query: join_(production.length ? production : plain), source: name };
  }
  return { query: null, source: null };
}

function lint(pkg, deps) {
  const stylelintFiles = filesIn("", STYLELINT_CONFIG);
  const inPackage = Object.hasOwn(pkg, "stylelint");
  const eslintCss = deps.some((d) => ESLINT_CSS.includes(d));
  return {
    stylelint: deps.includes("stylelint") || inPackage || stylelintFiles.length > 0,
    eslint_css: eslintCss,
    config_paths: [...stylelintFiles, ...(inPackage ? ["package.json"] : []), ...(eslintCss ? filesIn("", ESLINT_CONFIG) : [])].sort(),
  };
}

function hasStyleBlock(file) {
  try {
    return /<style[\s>]/i.test(readFileSync(file, "utf8"));
  } catch {
    return false;
  }
}

/** The kinds of styling the project holds, from file extensions (any case) and css-in-js packages.
 * Skips dot-directories, dependency and build output folders, and stops after MAX_ENTRIES entries. */
function styleFiles(deps) {
  const kinds = new Set(deps.some((d) => CSS_IN_JS.includes(d)) ? ["css-in-js"] : []);
  const stack = [opts.project];
  let seen = 0;
  while (stack.length && seen < MAX_ENTRIES) {
    let entries;
    const dir = stack.pop();
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      if (++seen > MAX_ENTRIES) break;
      const path = join(dir, e.name);
      const lower = e.name.toLowerCase();
      if (e.isDirectory()) {
        if (!lower.startsWith(".") && !SKIP_DIRS.has(lower)) stack.push(path);
        continue;
      }
      if (!e.isFile()) continue;
      const ext = extname(lower);
      if (STYLE_EXT[ext]) kinds.add(STYLE_EXT[ext]);
      else if (lower.endsWith(".css.ts")) kinds.add("css-in-js");
      else if (COMPONENT_EXT[ext] && !kinds.has(COMPONENT_EXT[ext]) && hasStyleBlock(path)) kinds.add(COMPONENT_EXT[ext]);
    }
  }
  return [...kinds].sort();
}

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
    browserslist: browserslist(isMapping(pkg) ? pkg : {}),
    lint: lint(isMapping(pkg) ? pkg : {}, deps),
    style_files: styleFiles(deps),
  };
}

/** {home, error?}: the convention home the project's pointer line names, the default when there is
 * none, or null with the error when the line is unusable. The resolver gets --root, so
 * CLAUDE_PROJECT_DIR never chooses the project. */
function conventionHome() {
  const r = spawnSync("bash", [join(ROOT, "lib/resolve-convention-home.sh"), "--root", opts.project], { cwd: ROOT, encoding: "utf8", timeout: 15_000 });
  if (r.status === 0) return { home: r.stdout.trim() };
  if (r.status === 1) return { home: DEFAULT_HOME };
  const cause = r.error?.code || r.stderr?.trim().split("\n").at(-1) || `exit ${r.status}`;
  return { home: null, error: `convention home unresolved (${cause}); the team and local layers are not read` };
}

/** True when `dir` exists and its real path lies outside the project's, as the resolver judges a home. */
function escapesProject(dir) {
  try {
    const rel = relative(realpathSync(opts.project), realpathSync(dir));
    return rel.startsWith("..") || isAbsolute(rel);
  } catch {
    return false;
  }
}

/** {value} parsed from the --user-config file, {error} when it cannot be read, {} without one. */
function readUserConfig(file) {
  if (!file) return {};
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch (e) {
    return { error: `userConfig (${file}): unreadable (${e.code ?? "error"})` };
  }
  try {
    return { value: JSON.parse(text) };
  } catch {
    return { error: `userConfig (${file}): not valid JSON` };
  }
}

/** A scratch convention home standing in for the real one: empty when the home is unresolved, else
 * --team as the team file beside copies of the real home's team prose and local files. Returns the
 * map from each scratch path back to the path it stands for, and `refused` when the real home
 * resolves outside the project, so its files are not copied. */
function scratchHome(home) {
  const dir = mkdtempSync(join(tmpdir(), "ui-home-"));
  const names = new Map();
  if (opts.team) {
    names.set(join(dir, `${PLUGIN}.yaml`), resolvePath(opts.team));
    try {
      copyFileSync(opts.team, join(dir, `${PLUGIN}.yaml`));
    } catch {
      // a missing team file leaves the team layer absent
    }
  }
  if (home === null) return { dir, names };
  const real = resolvePath(opts.project, home);
  if (escapesProject(real)) return { dir, names, refused: real };
  for (const name of [`${PLUGIN}.md`, `${PLUGIN}.local.yaml`, `${PLUGIN}.local.md`]) {
    const from = join(real, name);
    const to = join(dir, name);
    let st;
    try {
      st = lstatSync(from);
    } catch {
      continue;
    }
    if (st.isSymbolicLink()) symlinkSync(readlinkSync(from), to); // the resolver refuses it as it would the original
    else if (st.isFile()) copyFileSync(from, to);
    else continue;
    names.set(to, from);
  }
  return { dir, names };
}

const relabel = (v, names) => {
  if (typeof v === "string") return [...names].reduce((s, [from, to]) => s.replaceAll(from, to), v);
  if (Array.isArray(v)) return v.map((x) => relabel(x, names));
  return isMapping(v) ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, relabel(x, names)])) : v;
};

/** Drops each team routing row that breaks the bundled row schema, naming it on the team layer. A
 * team row may re-rank a bundled row, so it needs only concern and id; every field it sets must fit. */
function checkRoutingRows(out) {
  const rows = out.values.routing?.rows;
  if (!Array.isArray(rows)) return;
  const { properties } = JSON.parse(readFileSync(join(ROOT, "reference/routing.schema.json"), "utf8")).properties.rows.items;
  const rowSchema = { type: "object", required: ["concern", "id"], additionalProperties: false, properties };
  const team = out.layers.find((l) => l.name === "team");
  out.values.routing.rows = rows.filter((row, i) => {
    const errors = validate(rowSchema, row, `routing.rows[${i}]`);
    team.errors.push(...errors.map((e) => `team (${team.path}): ${e}`));
    return errors.length === 0;
  });
}

function config() {
  const { home, error } = conventionHome();
  const user = readUserConfig(opts["user-config"]);
  const seam = opts.team || home === null ? scratchHome(home) : null;
  try {
    const out = resolve({
      plugin: PLUGIN,
      projectRoot: opts.project,
      home: seam?.dir ?? home,
      schema: JSON.parse(readFileSync(join(ROOT, "reference/team.schema.json"), "utf8")),
      defaults: parseYaml(readFileSync(join(ROOT, "reference/defaults.yaml"), "utf8")),
      userConfig: user.value,
      teamOnly: ["routing"],
      userHome: opts.home,
    });
    if (user.error) Object.assign(out.layers.find((l) => l.name === "userConfig"), { state: "invalid", errors: [user.error] });
    if (seam) {
      for (const key of ["prose", "layers", "legacy"]) out[key] = relabel(out[key], seam.names);
      const local = out.layers.find((l) => l.name === "local");
      if (home === null) for (const l of out.layers) if (l.name === "team" ? !opts.team : l === local) l.path = null;
      if (seam.refused) {
        const why = "the convention home resolves outside the project; a repository layer stays inside it";
        Object.assign(local, { path: join(seam.refused, `${PLUGIN}.local.yaml`), state: "invalid", errors: [`local (${seam.refused}): ${why}`] });
      }
    }
    checkRoutingRows(out);
    return { ...out, home, ...(error && { home_error: error }) };
  } finally {
    if (seam) rmSync(seam.dir, { recursive: true, force: true });
  }
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
console.log(JSON.stringify({ project, ...found, ...(opts.config && { config: config() }) }));
