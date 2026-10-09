#!/usr/bin/env node
// Prints the project's user-experience signals, the routed tools that are installed, and the routes,
// as JSON:
//   {"project": {...}, "installed": [row ids] | null, "reachable": {row id: true | false | null},
//    "reason"?: "why installed is null, or why a list was matched by name",
//    "uncertain"?: {row id: "why it was left out of installed"},
//    "routes": [bundled rows in rank order, each with "present": true | false | null]}
// `present` is null when installed is null. Detection rules live in lib/installed.mjs.
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

const project = projectSignals();
const { rows } = JSON.parse(readFileSync(ROUTING, "utf8"));
const found = installed(rows, {
  pluginRoot: ROOT,
  home: opts.home,
  projectDir: opts.project,
  projectMcpServers: project.mcp_servers,
  pluginList: fromFileOr(opts["plugin-list-json"], ["plugin", "list", "--json"]),
  mcpList: fromFileOr(opts["mcp-list"], ["mcp", "list"]),
});
const jobs = [...new Set(rows.map((r) => r.job))];
const routes = rows
  .map((r) => ({ ...r, present: found.installed ? found.installed.includes(r.id) : null }))
  .sort((a, b) => jobs.indexOf(a.job) - jobs.indexOf(b.job) || a.rank - b.rank);
console.log(JSON.stringify({ project, ...found, routes }));
