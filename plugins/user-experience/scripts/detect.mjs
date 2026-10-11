#!/usr/bin/env node
// Prints the project's user-experience signals, the routed tools that are installed, the routes and
// the team file's settings, as JSON:
//   {"project": {...}, "installed": [row ids] | null, "reachable": {row id: true | false | null},
//    "reason"?: "why installed is null, or why a list was matched by name",
//    "uncertain"?: {row id: "why it was left out of installed"},
//    "routes": [bundled rows merged with the team file's, in rank order, each with "present": true | false | null],
//    "team": {"path", "loaded", "warnings": [...], "skipped_reason"?, "jtbd_school", "research_paths",
//             "persona_paths", "output_home"}}
// `present` comes from the row's own kind and detect, and is null when installed is null. Detection rules live in lib/installed.mjs; which team
// rows are admitted lives in lib/team-policy.mjs. A team file that is missing, malformed, unreadable
// or of an unknown version leaves the built-in routes and default settings, with skipped_reason
// naming the file and the cause. Team-file text appears in warnings only as JSON-quoted data.
// Usage: detect.mjs [--project DIR] [--home DIR] [--plugin-list-json FILE] [--mcp-list FILE] [--team FILE]
// The two list flags replace the live `claude plugin list --json` and `claude mcp list` calls;
// --team replaces the team file the convention home resolves to.
import { spawnSync } from "node:child_process";
import { existsSync, lstatSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { parseArgs } from "node:util";
import { fileURLToPath } from "node:url";
import { installed } from "./lib/installed.mjs";
import { rejections } from "./lib/team-policy.mjs";
import { parse as parseYaml } from "./lib/yaml-subset.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ROUTING = join(ROOT, "reference/routing.json");
const ROW_SCHEMA = JSON.parse(readFileSync(join(ROOT, "reference/routing.schema.json"), "utf8")).properties.rows.items;
const TEAM_SCHEMA = JSON.parse(readFileSync(join(ROOT, "reference/team.schema.json"), "utf8"));
const TEAM_FILE = "user-experience.yaml";
const DEFAULT_HOME = "docs/conventions";
const SETUP = "/user-experience:setup";

const MANIFEST = /^(package\.json|pyproject\.toml|requirements\.txt|setup\.py|Pipfile|Cargo\.toml|go\.mod|Gemfile|composer\.json|pom\.xml|build\.gradle(\.kts)?|Package\.swift|pubspec\.yaml|mix\.exs|deno\.jsonc?|.+\.(csproj|fsproj|vbproj|sln|slnx))$/;
const RESEARCH_DIRS = ["research", "user-research", "ux-research", "docs/research", "docs/user-research", "docs/ux-research"];
const PERSONA_DIRS = ["personas", "docs/personas"];
const PERSONA_FILE = /^personas?\.md$/i;
const PERSONA_FILE_DIRS = ["", "docs"];
// Product-analytics and session-replay SDKs. An entry ending in "/" is a scope prefix.
const ANALYTICS = [
  "@amplitude/", "@segment/", "@rudderstack/", "@snowplow/", "@fullstory/", "@hotjar/", "@heap/", "@vercel/analytics",
  "@datadog/browser-rum", "mixpanel", "mixpanel-browser", "posthog-js", "posthog-node", "analytics-node", "rudder-sdk-js",
  "react-ga4", "ga-4-react", "plausible-tracker", "logrocket", "heap-api", "@microsoft/clarity", "@google-analytics/data",
];

const { values: opts } = parseArgs({
  options: {
    project: { type: "string", default: process.cwd() },
    home: { type: "string", default: homedir() },
    "plugin-list-json": { type: "string" },
    "mcp-list": { type: "string" },
    team: { type: "string" },
  },
});

const readJson = (file) => {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    return null;
  }
};
const at = (p) => join(opts.project, p);
const isDir = (p) => existsSync(p) && statSync(p).isDirectory();
const filesIn = (dir, re) => (isDir(at(dir)) ? readdirSync(at(dir)).filter((f) => re.test(f)).map((f) => (dir ? `${dir}/${f}` : f)) : []);

/** Whole days since the last commit touching the project, or null outside a git work tree. git runs
 * from this plugin's root with -C, so a git binary planted in the project is never the one found. */
function lastCommitDays() {
  const r = spawnSync("git", ["-C", opts.project, "log", "-1", "--format=%ct", "--", "."], { cwd: ROOT, encoding: "utf8", timeout: 15_000 });
  const seconds = Number.parseInt(r.stdout ?? "", 10);
  if (r.error || r.status !== 0 || Number.isNaN(seconds)) return null;
  return Math.floor((Date.now() / 1000 - seconds) / 86400);
}

function projectSignals() {
  const pkg = readJson(at("package.json")) ?? {};
  const deps = Object.keys({ ...pkg.dependencies, ...pkg.devDependencies, ...pkg.peerDependencies });
  const match = (d) => ANALYTICS.some((p) => (p.endsWith("/") ? d.startsWith(p) : d === p));
  return {
    manifests: filesIn("", MANIFEST).sort(),
    research: RESEARCH_DIRS.filter((d) => isDir(at(d))),
    personas: [...PERSONA_DIRS.filter((d) => isDir(at(d))), ...PERSONA_FILE_DIRS.flatMap((d) => filesIn(d, PERSONA_FILE))],
    analytics: deps.filter(match).sort(),
    mcp_servers: Object.keys(readJson(at(".mcp.json"))?.mcpServers ?? {}).sort(),
    last_commit_days: lastCommitDays(),
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
const fromFileOr = (file, args) => () => (file ? readFileSync(file, "utf8") : claude(args));
/** A reader that runs once: installed() is asked twice when a team file adds rows. */
const once = (read) => {
  let text;
  return () => (text ??= read());
};

/** A team-file value as JSON data, cut short, for a warning or a reason. */
const quote = (value) => {
  const cut = (text) => (text.length > 80 ? `${text.slice(0, 80)}...` : text);
  return typeof value === "string" ? JSON.stringify(cut(value)) : cut(String(JSON.stringify(value)));
};
const isMapping = (v) => typeof v === "object" && v !== null && !Array.isArray(v);
const nameOf = (detect) => (detect.includes("@") ? detect.slice(0, detect.lastIndexOf("@")) : detect);

/** `p` as a project-relative path when it resolves inside the project, else null. Every existing
 * symlink along the path must resolve inside the project; a dangling one counts as an escape, and
 * the part of the path that does not exist yet cannot leave the deepest existing ancestor. */
function inside(p) {
  if (typeof p !== "string" || p === "" || isAbsolute(p) || /^[A-Za-z]:|\\/.test(p)) return null;
  const escapes = (rel) => rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel);
  const root = resolve(opts.project);
  const abs = resolve(root, p);
  if (escapes(relative(root, abs))) return null;
  try {
    const realRoot = realpathSync(root);
    let at = root;
    for (const part of relative(root, abs).split(sep).filter(Boolean)) {
      at = join(at, part);
      let stat;
      try {
        stat = lstatSync(at);
      } catch (err) {
        if (err.code === "ENOENT" || err.code === "ENOTDIR") break; // the rest does not exist yet
        return null; // any other error leaves containment unproven
      }
      if (stat.isSymbolicLink() && escapes(relative(realRoot, realpathSync(at)))) return null;
    }
  } catch {
    return null; // a dangling symlink, or a root that cannot be resolved
  }
  return relative(root, abs).split(sep).join("/") || ".";
}

/** Where the team surface is: {path, file} or {path, cause}. The one function that knows the
 * surface's form, a file at <home>/user-experience.yaml; a later folder form changes only this.
 * The resolver gets --root, so CLAUDE_PROJECT_DIR never chooses the project. */
function teamSurface() {
  if (opts.team) return { path: opts.team, file: resolve(opts.team) };
  const r = spawnSync("bash", [join(ROOT, "lib/resolve-convention-home.sh"), "--root", opts.project], { cwd: ROOT, encoding: "utf8", timeout: 15_000 });
  if (r.status !== 0 && r.status !== 1) {
    const cause = r.error?.code || r.stderr?.trim().split("\n").at(-1) || `exit ${r.status}`;
    return { path: null, cause: `convention home unresolved (${cause})` };
  }
  const path = `${r.status === 0 ? r.stdout.trim() : DEFAULT_HOME}/${TEAM_FILE}`;
  if (inside(path) === null) return { path, cause: "resolves outside the project" };
  return { path, file: join(opts.project, path) };
}

/** {path, doc} for a team file that parses at a known version, or {path, cause}. */
function readTeam({ path, file, cause }) {
  if (cause) return { path, cause };
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch (e) {
    return { path, cause: e.code === "ENOENT" ? "not found" : `unreadable (${e.code ?? e.message})` };
  }
  let doc;
  try {
    doc = parseYaml(text);
  } catch (e) {
    return { path, cause: `malformed: ${e.message}` };
  }
  if (!isMapping(doc)) return { path, cause: "malformed: the top level is not a mapping" };
  const { version, routing: routingSchema } = TEAM_SCHEMA.properties;
  if (doc.version !== version.const) return { path, cause: `version ${quote(doc.version ?? null)} is not one this plugin reads (${version.const})` };
  const { routing } = doc;
  if (routing == null) return { path, doc };
  if (!isMapping(routing)) return { path, cause: "malformed: routing is not a mapping" };
  const major = typeof routing.version === "number" ? Math.trunc(routing.version) : routing.version;
  const known = routingSchema.properties.version.const;
  if (major !== known) return { path, cause: `routing.version ${quote(routing.version ?? null)} is not one this plugin reads (${known})` };
  return { path, doc };
}

/** Errors for `value` against the row-schema keywords routing.schema.json uses. */
function violations(s, value, at = "row") {
  const errors = [];
  const fail = (msg) => errors.push(`${at} ${msg}`);
  if ("const" in s && value !== s.const) fail(`must be ${s.const}`);
  if (s.enum && !s.enum.includes(value)) fail(`must be one of ${s.enum.join(", ")}`);
  if (s.type === "string" && typeof value !== "string") return [`${at} must be a string`];
  if (s.type === "integer" && (!Number.isInteger(value) || value < (s.minimum ?? -Infinity))) fail(`must be an integer >= ${s.minimum}`);
  if (typeof value === "string") {
    if (value.length < (s.minLength ?? 0)) fail("is too short");
    if (s.pattern && !new RegExp(s.pattern).test(value)) fail(`must match ${s.pattern}`);
  }
  if (isMapping(value)) {
    for (const k of s.required ?? []) if (!Object.hasOwn(value, k)) fail(`is missing ${k}`);
    for (const [k, sub] of Object.entries(s.properties ?? {})) if (Object.hasOwn(value, k)) errors.push(...violations(sub, value[k], k));
  }
  for (const sub of s.allOf ?? []) errors.push(...violations(sub, value, at));
  if (s.if) {
    const branch = violations(s.if, value, at).length === 0 ? s.then : s.else;
    if (branch) errors.push(...violations(branch, value, at));
  }
  if (s.not && violations(s.not, value, at).length === 0) fail(`must not carry ${s.not.required?.join(", ") ?? "this shape"}`);
  return errors;
}

/** The team file's list at `label`, or [] with a warning when it is not a list. */
function listAt(value, label, warn) {
  if (value == null) return [];
  if (Array.isArray(value)) return value;
  warn(`${label} is not a list; ignored`);
  return [];
}

/** A copy of `entry` holding only `allowed` keys; each other key drops with a warning naming it. */
function knownKeys(entry, allowed, label, warn) {
  const kept = {};
  for (const [k, v] of Object.entries(entry)) {
    if (allowed.includes(k)) kept[k] = v;
    else warn(`${label}: unknown key ${quote(k)} dropped`);
  }
  return kept;
}

// A skill or plugin detect names a skill directory or a plugin, never a path: installed() joins a
// skill detect onto the skills directories, so a team row must not reach outside them.
const DETECT_NAME = /^(?!\.\.?(?:@|$))[A-Za-z0-9._-]+(?:@[A-Za-z0-9._-]+)?$/;

/** Bundled rows with the team's routing applied: `rows` re-rank or add (each admitted by
 * team-policy), `disable` and `deny` skip. Returns the rows and the set the team changed, which win
 * rank ties. `presence` maps a row list to each row's own presence. */
function mergeRoutes(bundled, teamRouting, path, warn, presence) {
  const key = (r) => `${r.job}\u0000${r.id}`;
  const routingProps = TEAM_SCHEMA.properties.routing.properties;
  const routing = knownKeys(teamRouting, Object.keys(routingProps), "routing", warn);
  const candidates = [];
  listAt(routing.rows, "routing.rows", warn).forEach((entry, i) => {
    const label = `routing.rows[${i}]`;
    if (!isMapping(entry)) return warn(`${label} is not a mapping; dropped`);
    const row = knownKeys(entry, Object.keys(ROW_SCHEMA.properties), label, warn);
    const merged = { ...bundled.find((b) => b.job === row.job && b.id === row.id), ...row };
    const errors = violations(ROW_SCHEMA, merged);
    if (["skill", "plugin"].includes(merged.kind) && typeof merged.detect === "string" && !DETECT_NAME.test(merged.detect)) {
      errors.push("detect must be a plugin or skill name (name or name@marketplace), not a path");
    }
    if (errors.length) return warn(`${label} ${quote(row.id ?? null)} dropped: ${errors.join("; ")}`);
    candidates.push({ label, merged });
  });

  const byKey = new Map(bundled.map((r) => [key(r), r]));
  const touched = new Set();
  if (candidates.length) {
    const present = presence([...bundled, ...candidates.map((c) => c.merged)]).slice(bundled.length);
    for (const [i, { label, merged }] of candidates.entries()) {
      const ctx = { bundled, installed: present[i] === null ? null : present[i] ? [merged.id] : [] };
      const failed = rejections(merged, ctx);
      for (const f of failed) warn(`${label} ${quote(merged.id)} dropped by ${f.rule}: ${f.reason}`);
      if (!failed.length) {
        byKey.set(key(merged), merged);
        touched.add(merged);
      }
    }
  }

  const disabled = new Set();
  listAt(routing.disable, "routing.disable", warn).forEach((entry, i) => {
    const label = `routing.disable[${i}]`;
    const fields = isMapping(entry) ? knownKeys(entry, Object.keys(routingProps.disable.items.properties), label, warn) : {};
    if (typeof fields.job === "string" && typeof fields.id === "string") disabled.add(key(fields));
    else warn(`${label} is not a mapping of job and id; ignored`);
  });
  const deny = new Set();
  listAt(routing.deny, "routing.deny", warn).forEach((name, i) => {
    if (typeof name === "string" && name) deny.add(name);
    else warn(`routing.deny[${i}] is not a name; ignored`);
  });

  const rows = [];
  for (const r of byKey.values()) {
    if (disabled.has(key(r))) continue;
    const name = [r.id, r.detect, nameOf(r.detect)].find((n) => deny.has(n));
    if (name) warn(`route ${r.job} ${quote(r.id)} skipped by deny ${quote(name)}; source: ${path}`);
    else rows.push(r);
  }
  return { rows, touched };
}

const RESERVED = [".claude", ".git"];
const DEFAULTS = { jtbd_school: "unset", research_paths: [], persona_paths: [], output_home: null };

/** The team file's settings beyond routing; a bad value falls back to its default with a warning. */
function teamSettings(doc, warn) {
  const props = TEAM_SCHEMA.properties;
  for (const k of Object.keys(doc)) if (!Object.hasOwn(props, k)) warn(`unknown key ${quote(k)} ignored`);
  let school = doc.jtbd_school ?? DEFAULTS.jtbd_school;
  if (!props.jtbd_school.enum.includes(school)) {
    warn(`jtbd_school ${quote(school)} is not one of ${props.jtbd_school.enum.join(", ")}; unset used`);
    school = DEFAULTS.jtbd_school;
  }
  // A project path outside .claude and .git: a deliverable there would become a standing project
  // rule, and research read from there is configuration, not research.
  const reserved = (rel) => RESERVED.includes(rel.split(/[\\/]/)[0].toLowerCase());
  // Checked as written and as resolved, so a symlink inside the project that points at .claude
  // or .git cannot carry a path there.
  const resolvesReserved = (rel) => {
    const root = realpathSync(resolve(opts.project));
    let at = resolve(opts.project, rel);
    while (!existsSync(at)) at = dirname(at);
    return reserved(relative(root, realpathSync(at)));
  };
  const usable = (p) => {
    const rel = inside(p);
    return rel === null || reserved(rel) || resolvesReserved(rel) ? null : rel;
  };
  const paths = (k) =>
    listAt(doc[k], k, warn).flatMap((p) => {
      const rel = usable(p);
      if (rel === null) warn(`${k} entry ${quote(p)} is outside the project, under .claude or .git, or not a path; dropped`);
      return rel === null ? [] : [rel];
    });
  let home = DEFAULTS.output_home;
  if (doc.output_home != null) {
    home = usable(doc.output_home);
    if (home === null) warn(`output_home ${quote(doc.output_home)} is outside the project, under .claude or .git, or not a path; default used`);
  }
  return { jtbd_school: school, research_paths: paths("research_paths"), persona_paths: paths("persona_paths"), output_home: home };
}

const project = projectSignals();
const { rows: bundled } = JSON.parse(readFileSync(ROUTING, "utf8"));
const lists = {
  pluginList: once(fromFileOr(opts["plugin-list-json"], ["plugin", "list", "--json"])),
  mcpList: once(fromFileOr(opts["mcp-list"], ["mcp", "list"])),
};
const detectRows = (rows) => installed(rows, { pluginRoot: ROOT, home: opts.home, projectDir: opts.project, projectMcpServers: project.mcp_servers, ...lists });
/** Each row's presence (true, false, or null when unknown) from its own kind and detect: installed()
 * answers by id, so each row gets an id no other row shares, keeping its prefix for the skill shape. */
const presence = (rows) => {
  const { installed: ids } = detectRows(rows.map((r, i) => ({ ...r, id: `${r.id}\u0000${i}` })));
  return rows.map((r, i) => (ids ? ids.includes(`${r.id}\u0000${i}`) : null));
};

const source = readTeam(teamSurface());
let rows = bundled;
let touched = new Set();
let team;
if (source.doc) {
  const warnings = [];
  const warn = (w) => warnings.push(w);
  ({ rows, touched } = mergeRoutes(bundled, source.doc.routing ?? {}, source.path, warn, presence));
  team = { path: source.path, loaded: true, warnings, ...teamSettings(source.doc, warn) };
} else {
  const named = source.path ?? `the ${TEAM_FILE} team file`;
  const skipped_reason = `${named} skipped: ${source.cause}. Built-in routes used; team overrides and the deny floor were not applied. Run ${SETUP} to create or repair it.`;
  team = { path: source.path, loaded: false, warnings: [], skipped_reason, ...DEFAULTS };
}

const found = detectRows(rows);
const own = new Map(presence(rows).map((p, i) => [rows[i], p]));
const jobs = [...new Set(bundled.map((r) => r.job))];
const jobOrder = (r) => (jobs.includes(r.job) ? jobs.indexOf(r.job) : jobs.length);
const routes = [...rows]
  .sort((a, b) => jobOrder(a) - jobOrder(b) || a.rank - b.rank || touched.has(b) - touched.has(a))
  .map((r) => ({ ...r, present: own.get(r) }));
console.log(JSON.stringify({ project, ...found, routes, team }));
