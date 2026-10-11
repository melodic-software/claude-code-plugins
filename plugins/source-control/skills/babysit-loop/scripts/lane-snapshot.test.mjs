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

// A PATH-stub `gh` that answers from a fixture map keyed by REST endpoint, or for
// `gh api graphql` by the connection the query reads (pullRequests or issues): key ->
// {out, code}, or key -> [{out, code}, ...] served one per call in order (the last
// repeats). A key missing from the map is a read failure.
const ghPath = join(base, "gh");
writeFileSync(
  ghPath,
  `#!/usr/bin/env node
const fs = require("node:fs");
const fixtures = JSON.parse(fs.readFileSync(process.env.FAKE_GH_FIXTURES, "utf8"));
const args = process.argv.slice(2);
const query = args.find((arg) => arg.startsWith("query=")) ?? "";
const key = args.includes("graphql") ? (/pullRequests\\(/.test(query) ? "pullRequests" : "issues") : args.filter((arg) => arg !== "api" && !arg.startsWith("-")).pop();
let hit = fixtures[key];
if (Array.isArray(hit)) {
  const countFile = process.env.FAKE_GH_FIXTURES + "." + Buffer.from(key).toString("hex");
  const calls = fs.existsSync(countFile) ? Number(fs.readFileSync(countFile, "utf8")) : 0;
  fs.writeFileSync(countFile, String(calls + 1));
  hit = hit[Math.min(calls, hit.length - 1)];
}
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
    env: {
      ...process.env,
      PATH: `${base}${delimiter}${process.env.PATH}`,
      FAKE_GH_FIXTURES: file,
    },
  });
}

const labelSet = (...names) => ({
  totalCount: names.length,
  nodes: names.map((name) => ({ name })),
});
const pr = (number, extra = {}) => ({
  number,
  title: `PR ${number}`,
  isDraft: false,
  labels: labelSet(),
  headRefOid: `sha${number}`,
  updatedAt: "2026-10-01T00:00:00Z",
  isCrossRepository: false,
  headRepositoryOwner: { login: "acme" },
  authorAssociation: "MEMBER",
  author: { __typename: "User", login: "dev" },
  ...extra,
});
const issue = (number, extra = {}) => ({
  number,
  title: `Issue ${number}`,
  labels: labelSet("bug"),
  updatedAt: "2026-10-01T00:00:00Z",
  authorAssociation: "NONE",
  author: { __typename: "User", login: "someone" },
  ...extra,
});

// The `--paginate --slurp` output for one connection: one response object per page, each
// carrying the totalCount GitHub reported when that page was read.
function pages(connection, total, ...pageNodes) {
  return {
    out: pageNodes.map((nodes, i) => ({
      data: {
        repository: {
          [connection]: {
            totalCount: total,
            pageInfo: {
              hasNextPage: i < pageNodes.length - 1,
              endCursor: `c${i}`,
            },
            nodes,
          },
        },
      },
    })),
  };
}

// Three PRs across two pages and two issues across two pages.
const complete = () => ({
  [`repos/${REPO}`]: { out: { has_issues: true } },
  pullRequests: pages("pullRequests", 3, [pr(1), pr(2)], [pr(3)]),
  issues: pages("issues", 2, [issue(10)], [issue(11)]),
});

test("a complete read across pages exits 0 with every PR and issue", () => {
  const result = run(complete());
  assert.equal(result.status, 0, result.stderr);
  const snap = JSON.parse(result.stdout);
  assert.equal(snap.complete, true);
  assert.deepEqual(
    snap.prs.map((p) => p.number),
    [1, 2, 3],
  );
  assert.deepEqual(
    snap.issues.map((i) => i.number),
    [10, 11],
  );
  assert.deepEqual(snap.issues[0].labels, ["bug"]);
  assert.equal(snap.prs[0].headRefOid, "sha1");
  assert.equal(snap.prs[0].isCrossRepository, false);
  assert.deepEqual(snap.prs[0].author, { login: "dev", type: "User" });
});

test("a bot author keeps the REST login and type the trust test matches", () => {
  const fixtures = complete();
  fixtures.issues = pages("issues", 1, [issue(12, { author: { __typename: "Bot", login: "melodic-lane-bot" } })]);
  const result = run(fixtures);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout).issues[0].author, {
    login: "melodic-lane-bot[bot]",
    type: "Bot",
  });
});

test("a failed pull-request read exits 3 and prints no snapshot", () => {
  const fixtures = complete();
  fixtures.pullRequests = { out: "", code: 1 };
  const result = run(fixtures);
  assert.equal(result.status, 3);
  assert.equal(result.stdout, "");
});

test("a failed issue read exits 3 and prints no snapshot", () => {
  const fixtures = complete();
  delete fixtures.issues;
  const result = run(fixtures);
  assert.equal(result.status, 3);
  assert.equal(result.stdout, "");
});

test("a read whose last page still reports a next page exits 3", () => {
  const fixtures = complete();
  fixtures.issues.out[1].data.repository.issues.pageInfo.hasNextPage = true;
  const result = run(fixtures);
  assert.equal(result.status, 3);
  assert.equal(result.stdout, "");
});

test("an ordinary issue skipped between pages on both reads exits 4, never complete", () => {
  const fixtures = complete();
  fixtures.issues = pages("issues", 3, [issue(10)], [issue(11)]);
  const result = run(fixtures);
  assert.equal(result.status, 4);
  assert.equal(result.stdout, "");
});

test("an ordinary issue duplicated between pages on both reads exits 4, never complete", () => {
  const fixtures = complete();
  fixtures.issues = pages("issues", 2, [issue(10)], [issue(10)]);
  const result = run(fixtures);
  assert.equal(result.status, 4);
  assert.equal(result.stdout, "");
});

test("an issue list whose totalCount moved between pages exits 4", () => {
  const fixtures = complete();
  fixtures.issues = pages("issues", 2, [issue(10)], [issue(11)]);
  fixtures.issues.out[1].data.repository.issues.totalCount = 3;
  const result = run(fixtures);
  assert.equal(result.status, 4);
});

test("an incomplete first read is re-read, and the whole second read is used", () => {
  const fixtures = complete();
  fixtures.issues = [
    pages("issues", 3, [issue(10)], [issue(11)]),
    pages("issues", 3, [issue(10)], [issue(11), issue(12)]),
  ];
  const result = run(fixtures);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(
    JSON.parse(result.stdout).issues.map((i) => i.number),
    [10, 11, 12],
  );
});

test("a pull-request list incomplete on both reads exits 4 and prints no snapshot", () => {
  const fixtures = complete();
  fixtures.pullRequests = pages("pullRequests", 4, [pr(1), pr(2)], [pr(3)]);
  const result = run(fixtures);
  assert.equal(result.status, 4);
  assert.equal(result.stdout, "");
});

test("an item with more labels than one read returns exits 3", () => {
  const fixtures = complete();
  fixtures.issues = pages("issues", 1, [issue(10, { labels: { totalCount: 101, nodes: [{ name: "bug" }] } })]);
  const result = run(fixtures);
  assert.equal(result.status, 3);
});

test("a drifted open_issues_count does not block a whole read", () => {
  const fixtures = complete();
  fixtures[`repos/${REPO}`].out.open_issues_count = 999;
  const result = run(fixtures);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).prs.length, 3);
});

test("a repository with issues disabled reads pull requests alone", () => {
  const fixtures = complete();
  fixtures[`repos/${REPO}`].out.has_issues = false;
  delete fixtures.issues;
  const result = run(fixtures);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout).issues, []);
});

test("a deleted fork head or author leaves the provenance fields null", () => {
  const fixtures = complete();
  fixtures.pullRequests = pages("pullRequests", 3, [pr(1), pr(2), pr(3, { headRepositoryOwner: null, author: null })]);
  const result = run(fixtures);
  assert.equal(result.status, 0, result.stderr);
  const forked = JSON.parse(result.stdout).prs[2];
  assert.equal(forked.headRepositoryOwner, null);
  assert.deepEqual(forked.author, { login: null, type: null });
});

test("a malformed --repo exits 2 before any read", () => {
  const result = spawnSync(process.execPath, [SCRIPT, "--repo", "../x"], {
    encoding: "utf8",
  });
  assert.equal(result.status, 2);
});
