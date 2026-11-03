import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { areaOf, detectAreas, parseCount, parseLog, plan, readPulls, slugOf } from "./upkeep.mjs";

const NOW = Date.parse("2026-11-20T06:00:00Z");
const daysAgo = (days) => NOW - days * 86_400_000;
const pull = (slug, days, state = "MERGED") => ({
  headRefName: `chore/tidy-adhoc-${slug}-2026-11-01`,
  createdAt: new Date(daysAgo(days)).toISOString(),
  state,
});
const base = { paths: [], commits: [], pulls: [], cadence: "daily", backstop: "weekly", limit: 3, open: 0, throttled: false, now: NOW };

test("an area is plugins/<name>, docs/<dir>, else the first path segment", () => {
  assert.equal(areaOf("plugins/bugs/skills/scan/SKILL.md").area, "plugins/bugs");
  assert.equal(areaOf("docs/adr/0001-x.md").area, "docs/adr");
  assert.equal(areaOf("scripts/run.sh").area, "scripts");
  assert.equal(areaOf("lib/a/b.sh").area, "lib");
});

test("each area's glob and tidy branch slug", () => {
  assert.equal(areaOf("plugins/bugs/README.md").glob, "plugins/bugs/**");
  assert.equal(slugOf("plugins/code-tidying"), "plugins-code-tidying");
  assert.deepEqual(areaOf("docs/README.md"), { area: "docs", glob: "docs/*" });
  assert.deepEqual(areaOf("README.md"), { area: "root", glob: "*" });
});

test("dot directories and unsafe names are not areas", () => {
  assert.equal(areaOf(".github/workflows/a.yml"), null);
  assert.equal(areaOf(".gitignore"), null);
  assert.equal(areaOf("plugins/$(id)/x"), null);
});

test("detect names each changed area once, in order", () => {
  assert.deepEqual(detectAreas(["scripts/a.sh", "plugins/bugs/a", ".github/x", "plugins/bugs/b"]), ["plugins/bugs", "scripts"]);
});

test("a churned area swept before the commit is due; one swept after it is not", () => {
  const result = plan({
    ...base,
    cadence: "daily",
    paths: ["plugins/a/x", "plugins/b/x"],
    pulls: [pull("plugins-a", 3), pull("plugins-b", 1)],
    commits: [{ at: daysAgo(2), paths: ["plugins/a/x", "plugins/b/x"] }],
  });
  assert.deepEqual(result.areas, [{ area: "plugins/a", glob: "plugins/a/**", slug: "plugins-a", overdue: false }]);
  assert.equal(result.proceed, true);
});

test("an unchanged area stays out however old its sweep", () => {
  const result = plan({ ...base, paths: ["plugins/a/x", "plugins/b/x"], pulls: [pull("plugins-a", 13)] });
  assert.deepEqual(result, { proceed: false, reason: "nothing-due", areas: [] });
});

test("churn is overdue at 7 days under a weekly backstop, not at 6", () => {
  const paths = ["plugins/a/x", "plugins/b/x"];
  const commits = [
    { at: daysAgo(7), paths: ["plugins/a/x"] },
    { at: daysAgo(6), paths: ["plugins/b/x"] },
  ];
  const overdue = Object.fromEntries(plan({ ...base, paths, commits }).areas.map((row) => [row.area, row.overdue]));
  assert.deepEqual(overdue, { "plugins/a": true, "plugins/b": false });
});

test("a monthly backstop does not call 7-day-old churn overdue", () => {
  const result = plan({ ...base, backstop: "monthly", paths: ["plugins/a/x"], commits: [{ at: daysAgo(7), paths: ["plugins/a/x"] }] });
  assert.equal(result.areas[0].overdue, false);
});

test("overdue is judged from the oldest unswept commit, not a newer one", () => {
  const commits = [
    { at: daysAgo(1), paths: ["plugins/a/x"] },
    { at: daysAgo(8), paths: ["plugins/a/x"] },
  ];
  assert.equal(plan({ ...base, paths: ["plugins/a/x"], commits }).areas[0].overdue, true);
});

test("a churned area past the window goes ahead of newly churned ones, within the cap", () => {
  const result = plan({
    ...base,
    limit: 3,
    open: 1,
    paths: ["plugins/a/x", "plugins/b/x", "plugins/c/x", "plugins/d/x"],
    commits: [
      { at: daysAgo(1), paths: ["plugins/a/x"] },
      { at: daysAgo(2), paths: ["plugins/b/x"] },
      { at: daysAgo(9), paths: ["plugins/c/x"] },
    ],
  });
  assert.deepEqual(result.areas.map((row) => [row.area, row.overdue]), [
    ["plugins/c", true],
    ["plugins/b", false],
  ]);
});

test("a batch at the cap waits", () => {
  assert.deepEqual(plan({ ...base, open: 3, paths: ["scripts/x"] }), { proceed: false, reason: "cap", areas: [] });
  assert.equal(plan({ ...base, open: 5, paths: ["scripts/x"] }).reason, "cap");
  assert.equal(plan({ ...base, open: 0, throttled: true, paths: ["scripts/x"] }).reason, "cap");
});

test("an area with an open sweep is skipped", () => {
  const result = plan({
    ...base,
    paths: ["plugins/a/x", "plugins/b/x"],
    pulls: [pull("plugins-a", 9, "OPEN")],
    commits: [{ at: daysAgo(1), paths: ["plugins/a/x", "plugins/b/x"] }],
  });
  assert.deepEqual(result.areas.map((row) => row.area), ["plugins/b"]);
});

test("a weekly cadence waits until 7 calendar days after the last sweep", () => {
  const paths = ["scripts/x", "plugins/a/x"];
  const commits = [{ at: daysAgo(1), paths: ["plugins/a/x"] }];
  assert.equal(plan({ ...base, cadence: "weekly", paths, commits, pulls: [pull("scripts", 6)] }).reason, "cadence");
  assert.equal(plan({ ...base, cadence: "weekly", paths, commits, pulls: [pull("scripts", 7)] }).proceed, true);
});

test("a daily cadence waits the same UTC day and runs the next, under 24 hours later", () => {
  const paths = ["plugins/a/x"];
  const commits = [{ at: daysAgo(1), paths }];
  const sameDay = { headRefName: "chore/tidy-adhoc-scripts-2026-11-20", createdAt: "2026-11-20T00:10:00Z", state: "MERGED" };
  assert.equal(plan({ ...base, paths, commits, pulls: [sameDay] }).reason, "cadence");
  const yesterday = { headRefName: "chore/tidy-adhoc-scripts-2026-11-19", createdAt: "2026-11-19T06:30:00Z", state: "MERGED" };
  assert.equal(plan({ ...base, paths, commits, pulls: [yesterday] }).proceed, true);
});

test("a tidy lane's branch is not an area sweep", () => {
  const lane = { headRefName: "chore/tidy-docs-prose-2026-11-20", createdAt: new Date(NOW).toISOString(), state: "OPEN" };
  assert.equal(plan({ ...base, paths: ["scripts/x"], commits: [{ at: daysAgo(1), paths: ["scripts/x"] }], pulls: [lane] }).proceed, true);
});

test("a sweep history the page cap cut plans nothing", () => {
  assert.deepEqual(plan({ ...base, paths: ["scripts/x"], truncated: true }), { proceed: false, reason: "sweep-history-truncated", areas: [] });
});

test("readPulls stops at the first page that reaches past the window", () => {
  const pages = [];
  const fetchPage = (page) => {
    pages.push(page);
    return page === 1 ? [pull("a", 1), pull("b", 2)] : [pull("c", 3), pull("d", 8)];
  };
  const { pulls, truncated } = readPulls(fetchPage, daysAgo(7));
  assert.deepEqual(pages, [1, 2]);
  assert.equal(pulls.length, 4);
  assert.equal(truncated, false);
});

test("readPulls stops at an empty page and reports the page cap", () => {
  assert.deepEqual(readPulls(() => [], daysAgo(7)), { pulls: [], truncated: false });
  let calls = 0;
  const always = () => {
    calls += 1;
    return [pull("a", 1)];
  };
  assert.equal(readPulls(always, daysAgo(7)).truncated, true);
  assert.equal(calls, 100);
});

test("parseCount reads open-pr-count.sh's lines and refuses an unknown count", () => {
  const text = "Throttle limit: 3, team\nOpen tidy PR count: 2\nThrottle active: no\nDetail: backlog below 3\n";
  assert.deepEqual(parseCount(text), { open: 2, limit: 3, throttled: false });
  const floor = "Throttle limit: 3, default\nOpen tidy PR count: 0 or more\nThrottle active: yes\n";
  assert.deepEqual(parseCount(floor), { open: 0, limit: 3, throttled: true });
  assert.throws(() => parseCount("Throttle limit: 3, team\nOpen tidy PR count: unknown\nThrottle active: unknown\n"));
});

test("parseLog splits git log output by commit", () => {
  assert.deepEqual(parseLog("\x00100\n\nscripts/a\nscripts/b\n\x00200\n\nlib/c\n"), [
    { at: 100_000, paths: ["scripts/a", "scripts/b"] },
    { at: 200_000, paths: ["lib/c"] },
  ]);
});

// End to end against a real repository, with gh stubbed.
const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "upkeep.mjs");
const dir = mkdtempSync(join(tmpdir(), "upkeep-"));
after(() => rmSync(dir, { recursive: true, force: true }));

const git = (cwd, ...args) => execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", ...args], { cwd, encoding: "utf8" }).trim();

function fixture(name, yaml) {
  const repo = join(dir, name);
  mkdirSync(join(repo, "docs/conventions"), { recursive: true });
  mkdirSync(join(repo, "plugins/a"), { recursive: true });
  writeFileSync(join(repo, "docs/conventions/code-tidying.yaml"), yaml);
  writeFileSync(join(repo, "plugins/a/x"), "1\n");
  git(repo, "init", "-q");
  git(repo, "add", ".");
  git(repo, "commit", "-qm", "first");
  return repo;
}

function stubGh(name, script) {
  const bin = join(dir, `bin-${name}`);
  mkdirSync(bin);
  writeFileSync(join(bin, "gh"), `#!/usr/bin/env bash\n${script}\n`);
  chmodSync(join(bin, "gh"), 0o755);
  return `${bin}:${process.env.PATH}`;
}

const runCli = (args, PATH, extraEnv = {}) => spawnSync("node", [SCRIPT, ...args], { encoding: "utf8", env: { ...process.env, PATH, ...extraEnv } });

test("gate: the setting sets the cap, and the plan names the area", () => {
  const repo = fixture("gate-ok", "upkeep_max_open: 1\n");
  const PATH = stubGh("ok", `case "$*" in api*) echo '[]' ;; *--jq*) echo "4 0" ;; *) echo '[]' ;; esac`);
  const result = runCli(["gate", "--root", repo], PATH);
  assert.equal(result.status, 0, result.stderr);
  const out = JSON.parse(result.stdout);
  assert.equal(out.proceed, true);
  assert.deepEqual(out.settings.upkeep_max_open, 1);
  assert.deepEqual(out.settings.upkeep_cadence, { value: "daily", source: "default" });
  assert.deepEqual(out.areas, [{ area: "docs/conventions", glob: "docs/conventions/**", slug: "docs-conventions", overdue: false }]);
});

test("gate: at the cap the batch waits", () => {
  const repo = fixture("gate-cap", "upkeep_max_open: 1\n");
  const PATH = stubGh("cap", `case "$*" in api*) echo '[]' ;; *--jq*) echo "4 1" ;; *) echo '[]' ;; esac`);
  const out = JSON.parse(runCli(["gate", "--root", repo], PATH).stdout);
  assert.deepEqual([out.proceed, out.reason, out.areas], [false, "cap", []]);
});

test("gate: an unknown open count fails and plans nothing", () => {
  const repo = fixture("gate-fail", "");
  const PATH = stubGh("fail", "exit 4");
  const result = runCli(["gate", "--root", repo], PATH);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, "");
});

test("detect: names the range's areas and writes the summary", () => {
  const repo = fixture("detect", "");
  const before = git(repo, "rev-parse", "HEAD");
  mkdirSync(join(repo, "scripts"));
  writeFileSync(join(repo, "scripts/y"), "1\n");
  writeFileSync(join(repo, "plugins/a/x"), "2\n");
  git(repo, "add", ".");
  git(repo, "commit", "-qm", "second");
  const head = git(repo, "rev-parse", "HEAD");
  const summary = join(dir, "summary.md");
  const result = runCli(["detect", "--root", repo, "--before", before, "--after", head], process.env.PATH, { GITHUB_STEP_SUMMARY: summary });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, "plugins/a\nscripts\n");
  assert.equal(readFileSync(summary, "utf8"), "Upkeep areas changed: plugins/a, scripts\n");
});

test("detect: a push with no start warns and stays green", () => {
  const repo = fixture("detect-zero", "");
  const head = git(repo, "rev-parse", "HEAD");
  const result = runCli(["detect", "--root", repo, "--before", "0".repeat(40), "--after", head], process.env.PATH);
  assert.equal(result.status, 0);
  assert.match(result.stdout, /^::warning::/);
});
