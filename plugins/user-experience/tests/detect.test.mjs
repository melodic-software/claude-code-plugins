import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
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

describe("team file", () => {
  const TEAM = join(FIX, "team");
  const EXISTING = join(FIX, "existing");
  const SKIPPED = /Built-in routes used; team overrides and the deny floor were not applied\. Run \/user-experience:setup/;
  const withTeam = (file, project = EXISTING) => detect(["--project", project, ...seams, "--team", file]);
  const fixture = (name) => withTeam(join(TEAM, name));
  /** Writes `text` as a scratch team file and returns its path. */
  const scratchTeam = (name, text) => {
    const file = join(scratch, name);
    writeFileSync(file, text);
    return file;
  };
  const builtIn = (routes) => assert.deepEqual(routes.map(({ present, ...row }) => row), ROWS);
  const ids = (routes, job) => routes.filter((r) => r.job === job).map((r) => r.id);

  test("a valid file loads its settings and leaves the bundled routes as they are", () => {
    const { team, routes } = fixture("valid.yaml");
    assert.deepEqual(team, {
      path: join(TEAM, "valid.yaml"),
      loaded: true,
      warnings: [],
      jtbd_school: "outcome-driven-innovation",
      research_paths: ["research"],
      persona_paths: ["personas.md"],
      output_home: "docs/ux",
    });
    builtIn(routes);
  });

  test("re-rank: a team row overrides the bundled row with the same job and id, key by key", () => {
    const { routes } = fixture("re-rank.yaml");
    const row = routes.find((r) => r.job === "synthesis" && r.id === "/design:research-synthesis");
    assert.equal(row.rank, 1);
    assert.equal(row.pointer, ROWS.find((r) => r.id === "/design:research-synthesis").pointer, "keys the team row omits keep the bundled value");
    assert.deepEqual(ids(routes, "synthesis"), ["/design:research-synthesis", "/product-management:synthesize-research", "miro@claude-plugins-official"]);
  });

  test("add: a row whose id is an installed plugin skill joins its job, marked present", () => {
    const { routes, team } = fixture("re-rank.yaml");
    const added = routes.find((r) => r.id === "/product-management:write-spec");
    assert.equal(added.job, "flows-ia");
    assert.equal(added.present, true);
    assert.equal(ids(routes, "flows-ia")[0], "/product-management:write-spec");
    assert.equal(team.loaded, true);
  });

  test("disable: every listed job and id is skipped, and a repeated entry is one entry", () => {
    const { routes } = fixture("re-rank.yaml");
    assert.ok(!ids(routes, "synthesis").includes("dovetail"));
    assert.ok(!ids(routes, "flows-ia").includes("optimal"));
    assert.equal(routes.length, ROWS.length + 1 - 2 - 2, "one added, two disabled, two denied");
  });

  test("deny: every listed name is skipped and the team file is named as the source", () => {
    const file = join(TEAM, "re-rank.yaml");
    const { routes, team } = withTeam(file);
    assert.ok(!routes.some((r) => r.id === "mixpanel" || r.id === "usertesting"));
    for (const name of ["mixpanel", "usertesting"]) {
      const notes = team.warnings.filter((w) => w.includes(`deny "${name}"`));
      assert.equal(notes.length, 1, `one disclosure for ${name}: ${team.warnings}`);
      assert.ok(notes[0].includes(`source: ${file}`), notes[0]);
    }
  });

  test("an unknown key in a team row drops only that key, with a warning naming it", () => {
    const { routes, team } = fixture("unknown-key.yaml");
    const row = routes.find((r) => r.job === "evaluation" && r.id === "/design:design-critique");
    assert.equal(row.rank, 3);
    assert.ok(!("color" in row));
    assert.ok(team.warnings.some((w) => w.includes('unknown key "color" dropped')), team.warnings.join("\n"));
  });

  test("a row drops, with disclosure, only when what remains fails the row schema", () => {
    const { routes, team } = fixture("unknown-key.yaml");
    const row = routes.find((r) => r.id === "contentsquare");
    assert.equal(row.rank, ROWS.find((r) => r.id === "contentsquare").rank, "the bundled row stands");
    assert.ok(team.warnings.some((w) => w.includes("contentsquare") && w.includes("dropped") && w.includes("rank")), team.warnings.join("\n"));
  });

  test("an unknown routing.version major degrades and names the version", () => {
    const { team, routes } = fixture("unknown-major.yaml");
    assert.equal(team.loaded, false);
    assert.match(team.skipped_reason, /routing\.version 2/);
    assert.match(team.skipped_reason, SKIPPED);
    builtIn(routes);
  });

  test("an unknown top-level version degrades and names the version", () => {
    const { team, routes } = withTeam(scratchTeam("future.yaml", "version: 2\n"));
    assert.equal(team.loaded, false);
    assert.match(team.skipped_reason, /version 2/);
    assert.match(team.skipped_reason, SKIPPED);
    builtIn(routes);
  });

  test("a missing file degrades: built-in routes, the skipped file named, setup suggested", () => {
    const file = join(scratch, "absent.yaml");
    const { team, routes } = withTeam(file);
    assert.equal(team.loaded, false);
    assert.equal(team.path, file);
    assert.ok(team.skipped_reason.startsWith(`${file} skipped: not found.`), team.skipped_reason);
    assert.match(team.skipped_reason, SKIPPED);
    builtIn(routes);
  });

  test("a malformed file degrades and names the line", () => {
    const { team, routes } = fixture("flow-mapping.yaml");
    assert.equal(team.loaded, false);
    assert.match(team.skipped_reason, /malformed: line 6: flow mapping/);
    assert.match(team.skipped_reason, SKIPPED);
    builtIn(routes);
  });

  test("an unreadable file (a directory at the path) degrades", () => {
    const dir = join(scratch, "team-dir.yaml");
    mkdirSync(dir, { recursive: true });
    const { team, routes } = withTeam(dir);
    assert.equal(team.loaded, false);
    assert.match(team.skipped_reason, /unreadable/);
    assert.match(team.skipped_reason, SKIPPED);
    builtIn(routes);
  });

  test("an added kind: tool row is dropped by no-new-tool-rows, with disclosure", () => {
    const { routes, team } = fixture("tool-row.yaml");
    assert.ok(!routes.some((r) => r.id === "card-sort-cli"));
    assert.ok(team.warnings.some((w) => w.includes("card-sort-cli") && w.includes("no-new-tool-rows")), team.warnings.join("\n"));
  });

  test("an added row with an unknown id is dropped by id-matches-bundled-or-installed, with disclosure", () => {
    const { routes, team } = fixture("unknown-id.yaml");
    assert.ok(!routes.some((r) => r.id === "/journey-mapper:map"));
    assert.ok(team.warnings.some((w) => w.includes("/journey-mapper:map") && w.includes("id-matches-bundled-or-installed")), team.warnings.join("\n"));
    builtIn(routes);
  });

  test("path values outside the project are dropped with a warning each", () => {
    const { team } = fixture("path-escape.yaml");
    assert.equal(team.loaded, true);
    assert.deepEqual(team.research_paths, ["research"]);
    assert.deepEqual(team.persona_paths, []);
    assert.equal(team.output_home, null);
    for (const value of ["../outside", "/etc", "../../personas", "../out"]) {
      assert.ok(team.warnings.some((w) => w.includes(JSON.stringify(value)) && w.includes("outside the project")), `${value}: ${team.warnings}`);
    }
  });

  test("a path that leaves the project through a symlink is dropped", { skip: process.platform === "win32" && "symlinks need privileges on Windows" }, () => {
    const project = join(scratch, "linked-project");
    mkdirSync(project, { recursive: true });
    symlinkSync(scratch, join(project, "research-link"));
    const file = scratchTeam("linked.yaml", "version: 1\nresearch_paths:\n  - research-link\n");
    const { team } = withTeam(file, project);
    assert.deepEqual(team.research_paths, []);
    assert.ok(team.warnings.some((w) => w.includes('"research-link"')), team.warnings.join("\n"));
  });

  test("a missing path under an outward symlink is dropped (research_paths and output_home)", { skip: process.platform === "win32" && "symlinks need privileges on Windows" }, () => {
    const project = join(scratch, "linked-missing");
    mkdirSync(project, { recursive: true });
    symlinkSync(scratch, join(project, "out-link"));
    const file = scratchTeam("linked-missing.yaml", "version: 1\nresearch_paths:\n  - out-link/new-subdir\noutput_home: out-link/ux\n");
    const { team } = withTeam(file, project);
    assert.deepEqual(team.research_paths, []);
    assert.equal(team.output_home, null);
    assert.ok(team.warnings.some((w) => w.includes('"out-link/new-subdir"')), team.warnings.join("\n"));
    assert.ok(team.warnings.some((w) => w.includes('"out-link/ux"')), team.warnings.join("\n"));
  });

  test("a dangling symlink on a path is dropped", { skip: process.platform === "win32" && "symlinks need privileges on Windows" }, () => {
    const project = join(scratch, "dangling-project");
    mkdirSync(project, { recursive: true });
    symlinkSync(join(scratch, "no-such-target"), join(project, "dangle"));
    const file = scratchTeam("dangling.yaml", "version: 1\nresearch_paths:\n  - dangle\n  - dangle/child\n");
    const { team } = withTeam(file, project);
    assert.deepEqual(team.research_paths, []);
  });

  test("a missing path inside the project is kept", () => {
    const file = scratchTeam("missing-inside.yaml", "version: 1\noutput_home: docs/ux/new\n");
    assert.equal(withTeam(file).team.output_home, "docs/ux/new");
  });

  test("an unknown key under routing drops only that key, with a warning", () => {
    const file = scratchTeam("routing-key.yaml", "version: 1\nrouting:\n  version: 1\n  tint: blue\n  deny:\n    - mixpanel\n");
    const { team, routes } = withTeam(file);
    assert.equal(team.loaded, true);
    assert.ok(team.warnings.some((w) => w.includes('routing: unknown key "tint" dropped')), team.warnings.join("\n"));
    assert.ok(!routes.some((r) => r.id === "mixpanel"), "the rest of routing still applies");
  });

  test("an unknown key in a disable entry drops only that key, with a warning", () => {
    const file = scratchTeam("disable-key.yaml", "version: 1\nrouting:\n  version: 1\n  disable:\n    - job: synthesis\n      id: dovetail\n      why: noisy\n");
    const { team, routes } = withTeam(file);
    assert.ok(team.warnings.some((w) => w.includes('routing.disable[0]: unknown key "why" dropped')), team.warnings.join("\n"));
    assert.ok(!routes.some((r) => r.id === "dovetail"), "the entry still disables");
  });

  test("a deny entry that is a mapping, not a name, is ignored with a warning", () => {
    const file = scratchTeam("deny-map.yaml", "version: 1\nrouting:\n  version: 1\n  deny:\n    - name: mixpanel\n");
    const { team, routes } = withTeam(file);
    assert.ok(team.warnings.some((w) => w.includes("routing.deny[0]")), team.warnings.join("\n"));
    assert.ok(routes.some((r) => r.id === "mixpanel"));
  });

  test("a skill detect that is a path is dropped before installed() looks it up", () => {
    mkdirSync(join(HOME, ".claude/escape-skill"), { recursive: true });
    const file = scratchTeam(
      "detect-path.yaml",
      "version: 1\nrouting:\n  version: 1\n  rows:\n    - job: journeys\n      rank: 1\n      id: /escape-skill\n      kind: skill\n      detect: ../escape-skill\n      account: none\n      status: unconfirmed\n      as_of: 2026-10-09\n      pointer: https://example.com/escape-skill\n      recheck: the skill moves\n",
    );
    const { team, routes } = withTeam(file);
    assert.ok(!routes.some((r) => r.id === "/escape-skill"));
    const note = team.warnings.find((w) => w.includes('"/escape-skill"'));
    assert.match(note, /detect/);
    assert.doesNotMatch(note, /id-matches-bundled-or-installed/, "dropped by the detect check, before the policy");
  });

  test("an invalid jtbd_school falls back to unset with a warning", () => {
    const { team } = withTeam(scratchTeam("school.yaml", "version: 1\njtbd_school: lean-canvas\n"));
    assert.equal(team.loaded, true);
    assert.equal(team.jtbd_school, "unset");
    assert.ok(team.warnings.some((w) => w.includes('"lean-canvas"')), team.warnings.join("\n"));
  });
});

describe("team surface", () => {
  const POINTER = join(FIX, "pointer-home");

  test("--team wins over the convention-home pointer", () => {
    const file = join(FIX, "team", "valid.yaml");
    const { team } = detect(["--project", POINTER, ...seams, "--team", file]);
    assert.equal(team.path, file);
    assert.equal(team.jtbd_school, "outcome-driven-innovation");
  });

  test("with no pointer, the team file is docs/conventions/user-experience.yaml", () => {
    const { team } = detect(["--project", join(FIX, "idea"), ...seams]);
    assert.equal(team.path, "docs/conventions/user-experience.yaml");
    assert.equal(team.loaded, false);
    assert.match(team.skipped_reason, /not found/);
  });

  test("a bound pointer gives <home>/user-experience.yaml", () => {
    const { team } = detect(["--project", POINTER, ...seams]);
    assert.equal(team.path, "team-conventions/user-experience.yaml");
    assert.equal(team.loaded, true);
    assert.equal(team.jtbd_school, "jobs-to-be-done-theory");
  });

  test("a failing resolver (exit 3) degrades with its cause", () => {
    const project = join(scratch, "broken-pointer");
    mkdirSync(project, { recursive: true });
    writeFileSync(join(project, "AGENTS.md"), "<!-- BEGIN GENERATED: convention-home -->\nHome: `no-such-dir`\n<!-- END GENERATED: convention-home -->\n");
    const { team, routes } = detect(["--project", project, ...seams]);
    assert.equal(team.loaded, false);
    assert.equal(team.path, null);
    assert.match(team.skipped_reason, /pointer target directory missing/);
    assert.match(team.skipped_reason, /Built-in routes used/);
    assert.deepEqual(routes.map(({ present, ...row }) => row), ROWS);
  });

  test("a team file that resolves outside the project through a symlink is skipped", { skip: process.platform === "win32" && "symlinks need privileges on Windows" }, () => {
    const outside = join(scratch, "outside-conventions");
    mkdirSync(outside, { recursive: true });
    writeFileSync(join(outside, "user-experience.yaml"), "version: 1\njtbd_school: outcome-driven-innovation\n");
    const project = join(scratch, "linked-home");
    mkdirSync(join(project, "docs"), { recursive: true });
    symlinkSync(outside, join(project, "docs/conventions"));
    const { team } = detect(["--project", project, ...seams]);
    assert.equal(team.loaded, false);
    assert.match(team.skipped_reason, /outside the project/);
  });
});

describe("team rows cannot repoint a route", () => {
  const EXISTING = join(FIX, "existing");
  let n = 0;
  const run = (text, mcp = MCP) => {
    const file = join(scratch, `repoint-${++n}.yaml`);
    writeFileSync(file, text);
    return detect(["--project", EXISTING, "--home", HOME, "--plugin-list-json", PLUGINS, "--mcp-list", mcp, "--team", file]);
  };
  const row = (fields) =>
    `    - ${Object.entries(fields)
      .map(([k, v]) => `${k}: ${v}`)
      .join("\n      ")}\n`;
  const rows = (...list) => `version: 1\nrouting:\n  version: 1\n  rows:\n${list.map(row).join("")}`;
  const full = { account: "none", status: "unconfirmed", as_of: "2026-10-09", pointer: "https://example.com/p", recheck: "it moves" };

  test("a bundled job and id whose detect is changed to a connected server is dropped, and the bundled row stands", () => {
    const { routes, team } = run(rows({ job: "synthesis", id: "dovetail", detect: "slack", status: "confirmed", rank: 1 }), join(FIX, "mcp-list-slack.txt"));
    const r = routes.find((x) => x.job === "synthesis" && x.id === "dovetail");
    assert.equal(r.detect, "dovetail");
    assert.equal(r.status, "deferred");
    assert.equal(r.present, false);
    assert.ok(team.warnings.some((w) => w.includes('"dovetail"') && w.includes("bundled-id-keeps-kind-detect-account")), team.warnings.join("\n"));
  });

  test("a bundled id reused under another job with another kind and detect is dropped", () => {
    const { routes, team } = run(rows({ job: "analytics", rank: 1, id: "dovetail", kind: "plugin", detect: "not-installed@nowhere", ...full }));
    assert.ok(!routes.some((x) => x.job === "analytics" && x.id === "dovetail"));
    assert.ok(team.warnings.some((w) => w.includes("bundled-id-keeps-kind-detect-account")), team.warnings.join("\n"));
  });

  test("a row is admitted and marked present by its own detect, not by another row with its id", () => {
    const id = "/product-management:write-spec";
    const { routes, team } = run(
      rows(
        { job: "flows-ia", rank: 1, id, kind: "skill", detect: "product-management@knowledge-work-plugins", ...full },
        { job: "journeys", rank: 1, id, kind: "skill", detect: "product-management@other-market", ...full },
      ),
    );
    assert.equal(routes.find((x) => x.job === "flows-ia" && x.id === id).present, true);
    assert.ok(!routes.some((x) => x.job === "journeys" && x.id === id && x.present !== false), JSON.stringify(routes.filter((x) => x.id === id)));
    assert.ok(team.warnings.some((w) => w.includes("routing.rows[1]") && w.includes("id-matches-bundled-or-installed")), team.warnings.join("\n"));
  });
});

describe("team paths may not point into .claude or .git", () => {
  const EXISTING = join(FIX, "existing");
  let n = 0;
  const run = (text) => {
    const file = join(scratch, `reserved-${++n}.yaml`);
    writeFileSync(file, text);
    return detect(["--project", EXISTING, ...seams, "--team", file]).team;
  };

  for (const value of [".claude/rules", ".git/hooks", "./.claude"]) {
    test(`output_home ${value} falls back to the default with a warning`, () => {
      const team = run(`version: 1\noutput_home: ${value}\n`);
      assert.equal(team.output_home, null);
      assert.ok(team.warnings.some((w) => w.includes(JSON.stringify(value)) && w.includes("output_home")), team.warnings.join("\n"));
    });
  }

  test("research_paths and persona_paths entries under .claude or .git are dropped with a warning each, others kept", () => {
    const team = run("version: 1\nresearch_paths:\n  - .claude\n  - research\npersona_paths:\n  - .git\n  - .claude/agents\n");
    assert.deepEqual(team.research_paths, ["research"]);
    assert.deepEqual(team.persona_paths, []);
    for (const value of [".claude", ".git", ".claude/agents"]) {
      assert.ok(team.warnings.some((w) => w.includes(JSON.stringify(value))), `${value}: ${team.warnings}`);
    }
  });

  test("a path whose first segment only starts with .claude is kept", () => {
    assert.equal(run("version: 1\noutput_home: .claude-notes/ux\n").output_home, ".claude-notes/ux");
  });

  test("a symlink inside the project that points at .claude cannot carry a path there", { skip: process.platform === "win32" && "symlinks need privileges on Windows" }, () => {
    const project = mkdtempSync(join(scratch, "reserved-link-"));
    mkdirSync(join(project, ".claude"));
    symlinkSync(join(project, ".claude"), join(project, "ux"));
    const file = join(scratch, `reserved-${++n}.yaml`);
    writeFileSync(file, "version: 1\noutput_home: ux/rules\nresearch_paths:\n  - ux\n");
    const { team } = detect(["--project", project, ...seams, "--team", file]);
    assert.equal(team.output_home, null);
    assert.deepEqual(team.research_paths, []);
  });
});
