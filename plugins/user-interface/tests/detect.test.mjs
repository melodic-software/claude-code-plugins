import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const TESTS = dirname(fileURLToPath(import.meta.url));
const PLUGIN = join(TESTS, "..");
const DETECT = join(PLUGIN, "scripts/detect.mjs");
const FIX = join(TESTS, "fixtures");
const MCP = join(FIX, "mcp-list.txt");

const scratch = mkdtempSync(join(tmpdir(), "ui-detect-"));
after(() => rmSync(scratch, { recursive: true, force: true }));
const HOME = join(scratch, "home");
mkdirSync(join(HOME, ".claude/skills/animate"), { recursive: true });

/** Runs detect.mjs as a CLI; `env` replaces the child's environment when given. */
function detect(args, env) {
  const r = spawnSync(process.execPath, [DETECT, ...args], { encoding: "utf8", env });
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}
/** A `claude plugin list --json` record, enabled at user scope unless `fields` says otherwise. */
const record = (id, fields) => ({ id, scope: "user", enabled: true, projectEnabled: false, ...fields });
/** This plugin's own record: its installPath is this checkout's plugin root. */
const self = (id = "user-interface@fixture-market", installPath = PLUGIN) => record(id, { installPath });
let lists = 0;
/** Writes `records` as a plugin list file and returns its path. */
function pluginList(records) {
  const file = join(scratch, `plugin-list-${++lists}.json`);
  writeFileSync(file, JSON.stringify(records));
  return file;
}
/** detect.mjs output for the no-ds project with `records` as the plugin list. */
const detectWith = (records) => detect(["--project", join(FIX, "no-ds"), "--home", HOME, "--plugin-list-json", pluginList(records), "--mcp-list", MCP]);
const PLUGINS = pluginList([...JSON.parse(readFileSync(join(FIX, "plugin-list.json"), "utf8")), self()]);
const seams = ["--home", HOME, "--plugin-list-json", PLUGINS, "--mcp-list", MCP];

describe("project signals", () => {
  test("a project with a design system reports each signal", () => {
    const { project } = detect(["--project", join(FIX, "with-ds"), ...seams]);
    assert.deepEqual(project.tokens, ["design-tokens.json"]);
    assert.deepEqual(project.packages, ["@mui/material", "@storybook/react", "chalk"]);
    assert.equal(project.components_json, true);
    assert.equal(project.storybook, true);
    assert.deepEqual(project.docs, ["DESIGN.md"]);
    assert.deepEqual(project.mcp_servers, ["shadcn"]);
  });

  test("a project without one reports nothing", () => {
    const { project } = detect(["--project", join(FIX, "no-ds"), ...seams]);
    assert.deepEqual(project, { tokens: [], packages: [], components_json: false, storybook: false, docs: [], mcp_servers: [] });
  });
});

describe("installed tools", () => {
  const installed = detect(["--project", join(FIX, "with-ds"), ...seams]).installed;

  test("an enabled user-scope plugin counts", () => {
    assert.ok(installed.includes("frontend-design@claude-plugins-official"));
  });

  test("a project or local record counts only when projectEnabled", () => {
    assert.ok(installed.includes("chrome-devtools-mcp@claude-plugins-official"), "disabled at user scope, enabled locally");
    assert.ok(!installed.includes("figma@claude-plugins-official"), "project record enabled elsewhere, not here");
  });

  test("a local record for this project counts though projectEnabled is false", () => {
    // `claude plugin list --json` run in the project shows a fresh local install this way.
    const project = join(FIX, "with-ds");
    const list = join(scratch, "local-install.json");
    writeFileSync(list, JSON.stringify([
      { id: "playwright@claude-plugins-official", scope: "local", enabled: true, projectEnabled: false, projectPath: project },
      { id: "canva@claude-plugins-official", scope: "local", enabled: true, projectEnabled: false, projectPath: "/elsewhere" },
    ]));
    const out = detect(["--project", project, "--home", HOME, "--plugin-list-json", list, "--mcp-list", MCP]).installed;
    assert.ok(out.includes("playwright@claude-plugins-official"));
    assert.ok(!out.includes("canva@claude-plugins-official"), "a local record for another project");
  });

  test("a record with no project path neither throws nor binds to a project", () => {
    // The live CLI emits projectPath: null; a scope other than project or local applies everywhere.
    const list = join(scratch, "null-path.json");
    writeFileSync(list, JSON.stringify([
      { id: "playwright@claude-plugins-official", scope: "local", enabled: true, projectEnabled: false, projectPath: null },
      { id: "frontend-design@claude-plugins-official", scope: "managed", enabled: true, projectEnabled: false, projectPath: null },
    ]));
    const out = detect(["--project", join(FIX, "with-ds"), "--home", HOME, "--plugin-list-json", list, "--mcp-list", MCP]).installed;
    assert.ok(Array.isArray(out), "installed must not collapse to null");
    assert.ok(!out.includes("playwright@claude-plugins-official"), "a local record with no project is not this project's");
    assert.ok(out.includes("frontend-design@claude-plugins-official"), "an enabled managed record counts");
  });

  test("an installed but disabled plugin does not count, nor does an absent one", () => {
    assert.ok(!installed.includes("canva@claude-plugins-official"));
    assert.ok(!installed.includes("superdesign@claude-plugins-official"));
  });

  test("a repo skill counts through its plugin", () => {
    assert.ok(installed.includes("/playgrounds:use"));
    assert.ok(!installed.includes("/writing:be-concise"));
  });

  test("a skill counts when its directory is in the user or project skills folder", () => {
    assert.ok(installed.includes("/animate"));
    assert.ok(!installed.includes("/design-taste-frontend"));
    const project = join(scratch, "proj");
    mkdirSync(join(project, ".claude/skills/design-taste-frontend"), { recursive: true });
    assert.ok(detect(["--project", project, ...seams]).installed.includes("/design-taste-frontend"));
  });

  test("an mcp server counts from claude mcp list or the project's .mcp.json", () => {
    assert.ok(installed.includes("storybook"), "from mcp list");
    assert.ok(installed.includes("magic"), "plugin-provided server, listed though not connected");
    assert.ok(installed.includes("shadcn"), "from .mcp.json");
    assert.ok(!detect(["--project", join(FIX, "no-ds"), ...seams]).installed.includes("shadcn"));
  });

  test("each id appears once though several concerns route to it", () => {
    assert.equal(installed.filter((id) => id === "frontend-design@claude-plugins-official").length, 1);
  });
});

describe("reachable", () => {
  const { installed, reachable } = detect(["--project", join(FIX, "with-ds"), ...seams]);

  test("covers exactly the installed ids", () => {
    assert.deepEqual(Object.keys(reachable).sort(), [...installed].sort());
  });

  test("an mcp server is reachable only when claude mcp list shows it connected", () => {
    assert.equal(reachable.storybook, true);
    assert.equal(reachable.magic, false);
  });

  test("a server known only from .mcp.json is unknown", () => {
    assert.equal(reachable.shadcn, null);
  });

  test("an installed route that needs no account is reachable", () => {
    assert.equal(reachable["frontend-design@claude-plugins-official"], true);
    assert.equal(reachable["/playgrounds:use"], true);
  });
});

describe("own marketplace", () => {
  test("a bare sibling resolves in its own marketplace", () => {
    const out = detectWith([self(), record("pixel-art@fixture-market")]);
    assert.ok(out.installed.includes("/pixel-art:ui"), JSON.stringify(out));
    assert.ok(!("reason" in out), out.reason);
  });

  test("playgrounds@other-market alone does not resolve", () => {
    const out = detectWith([self(), record("playgrounds@other-market")]);
    assert.ok(Array.isArray(out.installed), out.reason);
    assert.ok(!out.installed.includes("/playgrounds:use"));
  });

  test("no self record falls back to a name match with a reason beside the list", () => {
    const out = detectWith([record("playgrounds@other-market")]);
    assert.notEqual(out.installed, null);
    assert.ok(out.installed.includes("/playgrounds:use"), JSON.stringify(out));
    assert.match(out.reason, /own marketplace unresolved/);
  });

  test("an inline self record names inline in the reason", () => {
    const out = detectWith([self("user-interface@inline"), record("playgrounds@other-market")]);
    assert.notEqual(out.installed, null);
    assert.ok(out.installed.includes("/playgrounds:use"), JSON.stringify(out));
    assert.match(out.reason, /own marketplace unresolved.*inline/);
  });

  test("a name also listed as a qualified detect is uncertain on the fallback", () => {
    const out = detectWith([record("playwright@claude-plugins-official")]);
    assert.notEqual(out.installed, null);
    assert.match(out.reason, /own marketplace unresolved/);
    assert.ok(out.installed.includes("playwright@claude-plugins-official"), JSON.stringify(out));
    assert.ok(!out.installed.includes("/playwright:playwright"));
    assert.match(out.uncertain?.["/playwright:playwright"] ?? "", /playwright@claude-plugins-official/);
  });

  test("a record with a missing installPath does not null detection", () => {
    const out = detectWith([
      record("ghost@fixture-market", { installPath: join(scratch, "no-such-dir") }),
      { id: "no-path@fixture-market", scope: "user", enabled: true },
      { scope: "user", enabled: true },
      self(),
      record("pixel-art@fixture-market"),
      record("frontend-design@claude-plugins-official"),
    ]);
    assert.ok(Array.isArray(out.installed), out.reason);
    assert.ok(out.installed.includes("frontend-design@claude-plugins-official"));
    assert.ok(out.installed.includes("/pixel-art:ui"), JSON.stringify(out));
    assert.ok(!("reason" in out), out.reason);
  });

  test("two records for one id resolve against the one whose path matches", () => {
    const out = detectWith([
      self("user-interface@market-a", join(scratch, "no-such-dir")),
      self("user-interface@market-b"),
      record("playgrounds@market-a"),
      record("pixel-art@market-b"),
    ]);
    assert.ok(out.installed.includes("/pixel-art:ui"), JSON.stringify(out));
    assert.ok(!out.installed.includes("/playgrounds:use"));
    assert.ok(!("reason" in out), out.reason);
  });

  test("a symlinked installPath matches", () => {
    const link = join(scratch, "linked-plugin");
    symlinkSync(PLUGIN, link, "junction");
    const out = detectWith([self(undefined, link), record("pixel-art@fixture-market")]);
    assert.ok(out.installed.includes("/pixel-art:ui"), JSON.stringify(out));
    assert.ok(!("reason" in out), out.reason);
  });

  test("a bare third-party plugin detect does not match another marketplace once the own marketplace resolves", () => {
    const out = detectWith([self(), record("axe-accessibility@deque-market")]);
    assert.ok(Array.isArray(out.installed), out.reason);
    assert.ok(!out.installed.includes("axe-accessibility"));
  });
});

test("without the claude CLI, installed is null with a reason", () => {
  const out = detect(["--project", join(FIX, "no-ds"), "--home", HOME], { PATH: join(scratch, "empty-path") });
  assert.equal(out.installed, null);
  assert.match(out.reason, /claude/);
  assert.deepEqual(out.project.tokens, []);
});

test("the claude CLI runs in the requested project, not the caller's directory", { skip: process.platform === "win32" && "the fake CLI is a sh script" }, () => {
  const bin = join(scratch, "fake-bin");
  mkdirSync(bin, { recursive: true });
  // Reports the plugin as enabled for a project only when run from with-ds, as the real CLI scopes by cwd.
  writeFileSync(
    join(bin, "claude"),
    `#!/bin/sh\n[ "$1" = plugin ] || exit 0\ncase "$PWD" in */with-ds) e=true ;; *) e=false ;; esac\n` +
      `echo "[{\\"id\\":\\"frontend-design@claude-plugins-official\\",\\"scope\\":\\"project\\",\\"enabled\\":true,\\"projectEnabled\\":$e}]"\n`,
    { mode: 0o755 },
  );
  const out = detect(["--project", join(FIX, "with-ds"), "--home", HOME], { PATH: `${bin}:${process.env.PATH}` });
  assert.ok(out.installed.includes("frontend-design@claude-plugins-official"), JSON.stringify(out));
});

test("a CLI failure with no stderr still names the exit status", { skip: process.platform === "win32" && "the fake CLI is a sh script" }, () => {
  const bin = join(scratch, "failing-bin");
  mkdirSync(bin, { recursive: true });
  writeFileSync(join(bin, "claude"), "#!/bin/sh\nexit 3\n", { mode: 0o755 });
  const out = detect(["--project", join(FIX, "no-ds"), "--home", HOME], { PATH: `${bin}:${process.env.PATH}` });
  assert.equal(out.installed, null);
  assert.match(out.reason, /exit 3/);
});

test("a malformed plugin list is reported, not thrown", () => {
  const bad = join(scratch, "bad.json");
  writeFileSync(bad, "{not json");
  const out = detect(["--project", join(FIX, "no-ds"), "--home", HOME, "--plugin-list-json", bad, "--mcp-list", MCP]);
  assert.equal(out.installed, null);
  assert.match(out.reason, /plugin list/);
});
