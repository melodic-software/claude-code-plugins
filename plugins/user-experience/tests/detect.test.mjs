import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const TESTS = dirname(fileURLToPath(import.meta.url));
const PLUGIN = join(TESTS, "..");
const DETECT = join(PLUGIN, "scripts/detect.mjs");
const FIX = join(TESTS, "fixtures");
const MCP = join(FIX, "mcp-list.txt");
const ROWS = JSON.parse(readFileSync(join(PLUGIN, "reference/routing.json"), "utf8")).rows;

const scratch = mkdtempSync(join(tmpdir(), "ux-detect-"));
after(() => rmSync(scratch, { recursive: true, force: true }));
const HOME = join(scratch, "home");
mkdirSync(HOME, { recursive: true });

/** Runs detect.mjs as a CLI; `env` replaces the child's environment when given. */
function detect(args, env) {
  const r = spawnSync(process.execPath, [DETECT, ...args], { encoding: "utf8", env });
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}
/** A `claude plugin list --json` record, enabled at user scope unless `fields` says otherwise. */
const record = (id, fields) => ({ id, scope: "user", enabled: true, projectEnabled: false, ...fields });
/** This plugin's own record: its installPath is this checkout's plugin root. */
const self = () => record("user-experience@fixture-market", { installPath: PLUGIN });
let lists = 0;
/** Writes `records` as a plugin list file and returns its path. */
function pluginList(records) {
  const file = join(scratch, `plugin-list-${++lists}.json`);
  writeFileSync(file, JSON.stringify(records));
  return file;
}
const PLUGINS = pluginList([...JSON.parse(readFileSync(join(FIX, "plugin-list.json"), "utf8")), self()]);
const seams = ["--home", HOME, "--plugin-list-json", PLUGINS, "--mcp-list", MCP];

describe("project signals", () => {
  test("an idea with no code reports no manifest, research, personas or analytics", () => {
    const { project } = detect(["--project", join(FIX, "idea"), ...seams]);
    assert.deepEqual(project.manifests, []);
    assert.deepEqual(project.research, []);
    assert.deepEqual(project.personas, []);
    assert.deepEqual(project.analytics, []);
    assert.deepEqual(project.mcp_servers, []);
  });

  test("an existing app reports its manifest, research folder, personas file and analytics SDKs", () => {
    const { project } = detect(["--project", join(FIX, "existing"), ...seams]);
    assert.deepEqual(project.manifests, ["package.json"]);
    assert.deepEqual(project.research, ["research"]);
    assert.deepEqual(project.personas, ["personas.md"]);
    assert.deepEqual(project.analytics, ["@amplitude/analytics-browser", "mixpanel-browser"]);
  });

  test("the last commit touching the project is reported in whole days", { skip: spawnSync("git", ["--version"]).status !== 0 && "git not installed" }, () => {
    const repo = join(scratch, "aged-repo");
    mkdirSync(repo, { recursive: true });
    writeFileSync(join(repo, "README.md"), "app\n");
    const tenDaysAgo = new Date(Date.now() - (10 * 24 + 1) * 3600 * 1000).toISOString();
    const git = (...args) => {
      const r = spawnSync("git", ["-C", repo, "-c", "user.name=t", "-c", "user.email=t@example.test", "-c", "commit.gpgsign=false", ...args], {
        encoding: "utf8",
        env: { ...process.env, GIT_AUTHOR_DATE: tenDaysAgo, GIT_COMMITTER_DATE: tenDaysAgo },
      });
      assert.equal(r.status, 0, r.stderr);
    };
    git("init", "-q");
    git("add", "README.md");
    git("commit", "-q", "-m", "init");
    assert.equal(detect(["--project", repo, ...seams]).project.last_commit_days, 10);
    const bare = join(scratch, "not-a-repo");
    mkdirSync(bare, { recursive: true });
    assert.equal(detect(["--project", bare, ...seams]).project.last_commit_days, null);
  });
});

describe("installed and routes", () => {
  test("installed ids come from the plugin list and the mcp list", () => {
    const out = detect(["--project", join(FIX, "idea"), ...seams]);
    assert.ok(out.installed.includes("/user-interface:design"), "plugin-list id");
    assert.ok(out.installed.includes("dovetail"), "mcp-list id");
    assert.ok(out.installed.includes("mixpanel"), "plugin-bundled mcp-list id");
    assert.ok(!out.installed.includes("/design:user-research"), "a disabled plugin's row");
    assert.equal(out.reachable["/user-interface:design"], true);
    assert.equal(out.reachable.dovetail, true);
    assert.equal(out.reachable.mixpanel, false);
    assert.ok(!("reason" in out), out.reason);
  });

  test("routes are the bundled rows, each marked present when installed", () => {
    // Enabled in plugin-list.json (user-interface, product-management) or listed in mcp-list.txt (dovetail, mixpanel).
    const expected = new Set(["/user-interface:design", "/product-management:synthesize-research", "/product-management:metrics-review", "dovetail", "mixpanel"]);
    const { routes } = detect(["--project", join(FIX, "idea"), ...seams]);
    assert.deepEqual(routes, ROWS.map((r) => ({ ...r, present: expected.has(r.id) })));
  });

  test("a route whose plugin is not enabled is marked absent", () => {
    const list = pluginList([self(), record("user-interface@fixture-market", { enabled: false })]);
    const noMcp = join(FIX, "mcp-list-empty.txt");
    const { installed, routes } = detect(["--project", join(FIX, "idea"), "--home", HOME, "--plugin-list-json", list, "--mcp-list", noMcp]);
    assert.deepEqual(installed, []);
    assert.deepEqual(routes, ROWS.map((r) => ({ ...r, present: false })));
  });

  test("a malformed plugin list is reported, and presence is unknown", () => {
    const bad = join(scratch, "bad.json");
    writeFileSync(bad, "[{");
    const out = detect(["--project", join(FIX, "idea"), "--home", HOME, "--plugin-list-json", bad, "--mcp-list", MCP]);
    assert.equal(out.installed, null);
    assert.match(out.reason, /plugin list/);
    assert.deepEqual(out.routes, ROWS.map((r) => ({ ...r, present: null })));
  });
});

test("without the claude CLI, installed is null with a reason", () => {
  const out = detect(["--project", join(FIX, "idea"), "--home", HOME], { PATH: join(scratch, "empty-path") });
  assert.equal(out.installed, null);
  assert.match(out.reason, /claude/);
  assert.ok(out.routes.length > 0);
});

test("mcp list is not read when the plugin list fails", { skip: process.platform === "win32" && "the fake CLI is a sh script" }, () => {
  const bin = join(scratch, "failing-plugin-bin");
  const log = join(scratch, "mcp-calls.log");
  mkdirSync(bin, { recursive: true });
  writeFileSync(join(bin, "claude"), `#!/bin/sh\n[ "$1" = mcp ] && echo "$*" >> '${log}'\n[ "$1" = plugin ] && exit 4\nexit 0\n`, { mode: 0o755 });
  const out = detect(["--project", join(FIX, "idea"), "--home", HOME], { PATH: `${bin}:${process.env.PATH}` });
  assert.equal(out.installed, null);
  assert.match(out.reason, /plugin list.*exit 4/);
  assert.equal(existsSync(log), false, "claude mcp list was called");
});
