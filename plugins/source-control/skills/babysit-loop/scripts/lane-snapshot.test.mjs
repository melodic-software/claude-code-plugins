#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "lane-snapshot.mjs");
const REPO = "acme/widgets";
const base = mkdtempSync(join(tmpdir(), "lane-snapshot-"));
after(() => rmSync(base, { recursive: true, force: true }));

// A PATH-stub `gh` that answers `gh api [--paginate --slurp] <endpoint>` from a fixture
// map: endpoint -> {out, code}. An endpoint missing from the map is a read failure.
const ghPath = join(base, "gh");
writeFileSync(
  ghPath,
  `#!/usr/bin/env node
const fixtures = JSON.parse(require("node:fs").readFileSync(process.env.FAKE_GH_FIXTURES, "utf8"));
const endpoint = process.argv.slice(2).filter((arg) => arg !== "api" && !arg.startsWith("--")).pop();
const hit = fixtures[endpoint];
if (!hit) { process.stderr.write("gh: Not Found (HTTP 404)\\n"); process.exit(1); }
process.stdout.write(typeof hit.out === "string" ? hit.out : JSON.stringify(hit.out));
process.exit(hit.code ?? 0);
`,
);
chmodSync(ghPath, 0o755);

let n = 0;
function run(fixtures) {
  n += 1;
  const file = join(base, `fixtures-${n}.json`);
  writeFileSync(file, JSON.stringify(fixtures));
  return spawnSync(process.execPath, [SCRIPT, "--repo", REPO], {
    encoding: "utf8",
    env: { ...process.env, PATH: `${base}${delimiter}${process.env.PATH}`, FAKE_GH_FIXTURES: file },
  });
}

const pr = (number, extra = {}) => ({
  number,
  title: `PR ${number}`,
  draft: false,
  labels: [],
  updated_at: "2026-10-01T00:00:00Z",
  author_association: "MEMBER",
  user: { login: "dev", type: "User" },
  head: { sha: `sha${number}`, repo: { full_name: REPO, owner: { login: "acme" } } },
  base: { repo: { full_name: REPO } },
  ...extra,
});
const issue = (number) => ({ number, title: `Issue ${number}`, labels: [{ name: "bug" }], author_association: "NONE", user: { login: "someone", type: "User" } });
const prAsIssue = (number) => ({ number, title: `PR ${number}`, pull_request: {} });

const PULLS = `repos/${REPO}/pulls?state=open&per_page=100`;
const ISSUES = `repos/${REPO}/issues?state=open&per_page=100`;

// Three PRs across two pages and two issues; the repository reports five open.
const complete = () => ({
  [`repos/${REPO}`]: { out: { open_issues_count: 5, has_issues: true } },
  [PULLS]: { out: [[pr(1), pr(2)], [pr(3)]] },
  [ISSUES]: { out: [[issue(10), prAsIssue(1), prAsIssue(2)], [prAsIssue(3), issue(11)]] },
});

test("a complete read across pages exits 0 with every PR and issue", () => {
  const result = run(complete());
  assert.equal(result.status, 0, result.stderr);
  const snap = JSON.parse(result.stdout);
  assert.equal(snap.complete, true);
  assert.deepEqual(snap.prs.map((p) => p.number), [1, 2, 3]);
  assert.deepEqual(snap.issues.map((i) => i.number), [10, 11]);
  assert.deepEqual(snap.issues[0].labels, ["bug"]);
  assert.equal(snap.prs[0].headRefOid, "sha1");
  assert.equal(snap.prs[0].isCrossRepository, false);
});

test("a failed pull-request read exits 3 and prints no snapshot", () => {
  const fixtures = complete();
  fixtures[PULLS] = { out: "", code: 1 };
  const result = run(fixtures);
  assert.equal(result.status, 3);
  assert.equal(result.stdout, "");
});

test("a failed issue read exits 3 and prints no snapshot", () => {
  const fixtures = complete();
  delete fixtures[ISSUES];
  const result = run(fixtures);
  assert.equal(result.status, 3);
  assert.equal(result.stdout, "");
});

test("fewer items listed than the repository reports open exits 4 (truncated)", () => {
  const fixtures = complete();
  fixtures[`repos/${REPO}`].out.open_issues_count = 6;
  const result = run(fixtures);
  assert.equal(result.status, 4);
  assert.equal(result.stdout, "");
});

test("a pull-request list missing a PR the issue list names exits 4", () => {
  const fixtures = complete();
  fixtures[PULLS] = { out: [[pr(1), pr(2)], [pr(4)]] };
  const result = run(fixtures);
  assert.equal(result.status, 4);
  assert.equal(result.stdout, "");
});

test("a deleted fork head leaves the provenance fields null", () => {
  const fixtures = complete();
  fixtures[PULLS] = { out: [[pr(1), pr(2), pr(3, { head: { sha: "x", repo: null } })]] };
  const result = run(fixtures);
  assert.equal(result.status, 0, result.stderr);
  const forked = JSON.parse(result.stdout).prs[2];
  assert.equal(forked.isCrossRepository, null);
  assert.equal(forked.headRepositoryOwner, null);
});

test("a malformed --repo exits 2 before any read", () => {
  const result = spawnSync(process.execPath, [SCRIPT, "--repo", "../x"], { encoding: "utf8" });
  assert.equal(result.status, 2);
});
