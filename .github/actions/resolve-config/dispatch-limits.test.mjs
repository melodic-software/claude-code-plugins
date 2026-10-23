// pr-unblock-dispatch.yml's limits read through the real resolver: dispatch.mjs
// takes `limits` from the base's pr-pipeline.yaml, so a set
// `limits.limit-stops-per-head` changes which heads it dispatches again, and a
// config the resolver refuses fails the run before anything is dispatched.
// Lives here because it needs resolve-config's dependencies.
import assert from "node:assert/strict";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { parse } from "yaml";

import { main } from "../../scripts/pr-unblock/dispatch.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const LIVE = readFileSync(join(ROOT, "docs/conventions/pr-pipeline.yaml"), "utf8");
const HEAD = "a".repeat(40);
// A resolve-conflicts run the usage limit stopped six hours ago with no stated
// reset: past the default five-hour fallback, so it no longer holds the head.
const STOPPED = {
  name: "pr-unblock / resolve-conflicts",
  status: "completed",
  conclusion: "failure",
  completed_at: "2026-10-17T06:00:00Z",
  output: { title: "Failed", summary: "lane=pr-unblock activity=resolve-conflicts class=rate-limit\n\nThe activity step failed." },
};

function baseWith(text) {
  const base = mkdtempSync(join(tmpdir(), "dispatch-limits-base-"));
  for (const file of [
    "docs/conventions/pr-pipeline/pr-pipeline.schema.json",
    ".github/standards/github-actions-conventions/vocabulary.json",
    ".github/standards/trusted-actors/trusted-actors.json",
  ]) {
    mkdirSync(dirname(join(base, file)), { recursive: true });
    cpSync(join(ROOT, file), join(base, file));
  }
  writeFileSync(join(base, "docs/conventions/pr-pipeline.yaml"), text);
  return base;
}

// The lanes App bot's user id (.github/standards/trusted-actors/trusted-actors.json).
const LANES_APP = 337595936;
// Lanes App PRs whose head's lanes failed, as fix-ci-dispatch.mjs lists them.
const ciFixPull = (number) => {
  const head = String(number).padStart(40, "c");
  const ciStatus = { __typename: "CheckRun", name: "ci-status", status: "COMPLETED", conclusion: "FAILURE", checkSuite: { app: { databaseId: 15368 } } };
  const ciLanes = { __typename: "StatusContext", context: "ci-lanes", state: "FAILURE", creator: { login: "github-actions[bot]" } };
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: head,
    author: { databaseId: LANES_APP },
    labels: { nodes: [] },
    commits: { nodes: [{ commit: { oid: head, statusCheckRollup: { contexts: { nodes: [ciStatus, ciLanes] } } } }] },
  };
};

// Ready PRs a person opened that change Markdown and never had fix-docs, as
// fix-docs-dispatch.mjs lists them.
const docsPull = (number) => {
  const head = String(number).padStart(40, "d");
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: head,
    author: { __typename: "User", login: "someone" },
    labels: { nodes: [] },
    files: { nodes: [{ path: "README.md" }], pageInfo: { hasNextPage: false } },
    commits: { nodes: [{ commit: { oid: head, statusCheckRollup: { contexts: { nodes: [] } } } }] },
  };
};

const api = (dispatched, ciFixPulls = [], docsPulls = []) => ({
  listDocsFixCandidates: async () => ({
    rateLimit: { cost: 1, remaining: 4999 },
    pullRequests: { nodes: docsPulls, pageInfo: { hasNextPage: false, endCursor: null } },
  }),
  readDocsFixHistory: async () => ({ rateLimit: { cost: 1, remaining: 4999 }, pullRequest: { commits: { nodes: [] } } }),
  listCiFixCandidates: async () => ({
    rateLimit: { cost: 1, remaining: 4999 },
    pullRequests: { nodes: ciFixPulls, pageInfo: { hasNextPage: false, endCursor: null } },
  }),
  listOpenPulls: async () => ({
    nodes: [{ number: 40, isDraft: false, isCrossRepository: false, mergeable: "CONFLICTING", baseRefName: "main", headRefOid: HEAD }],
    pageInfo: { hasNextPage: false, endCursor: null },
  }),
  getPulls: async () => [],
  listCheckRuns: async () => [STOPPED],
  listWorkflowRuns: async () => [],
  readRequiredRun: async () => ({ run: null, jobs: [] }),
  dispatchWorkflow: async ({ inputs }) => {
    dispatched.push(inputs["pr-number"]);
    return { workflowRunId: 9040 };
  },
});

async function run(text, ciFixPulls = [], docsPulls = [], tracker = null) {
  const base = baseWith(text);
  if (tracker !== null) {
    writeFileSync(join(base, ".work-item-tracker.json"), tracker);
  }
  const output = join(base, "output");
  writeFileSync(output, "");
  const dispatched = [];
  try {
    const code = await main(
      { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "4242", GITHUB_OUTPUT: output, BASE_PATH: base, APP_SENDER_ID: String(LANES_APP) },
      { api: api(dispatched, ciFixPulls, docsPulls), sleep: async () => {}, log: () => {}, now: Date.parse("2026-10-17T12:00:00Z") },
    );
    return { code, dispatched };
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
}

// The live config with one more line in its own `limits` block.
const withLimit = (line) => {
  assert.match(LIVE, /^limits:\n/m, "the live config has a limits block");
  return LIVE.replace(/^limits:\n/m, `limits:\n  ${line}\n`);
};

test("the base config's limits.limit-stops-per-head decides whether a reset limit stop still holds the head", async () => {
  assert.deepEqual(await run(LIVE), { code: 0, dispatched: ["40"] });
  assert.deepEqual(await run(withLimit("limit-stops-per-head: 1")), { code: 0, dispatched: [] });
});

test("the base config's limits.fix-ci-per-run caps the fix-ci dispatches", async () => {
  const pulls = [ciFixPull(51), ciFixPull(52), ciFixPull(53)];
  assert.match(LIVE, /^ {2}fix-ci-per-run: 2$/m, "the live config sets the per-run cap");
  assert.deepEqual(await run(LIVE, pulls), { code: 0, dispatched: ["40", "51", "52"] });
  const one = LIVE.replace(/^ {2}fix-ci-per-run: 2$/m, "  fix-ci-per-run: 1");
  assert.deepEqual(await run(one, pulls), { code: 0, dispatched: ["40", "51"] });
});

test("the base config's adoption section lets fix-ci adopt an idle owner PR", async () => {
  // kyle-sexton (trusted-actors.json), 25 hours idle at run()'s clock.
  const idle = "2026-10-16T11:00:00Z";
  const owner = ciFixPull(61);
  owner.author = { databaseId: 153232337 };
  owner.updatedAt = idle;
  owner.commits.nodes[0].commit.committedDate = idle;
  assert.equal(parse(LIVE).adoption["idle-hours"], 24, "the live config adopts a trusted person after 24 hours");
  assert.deepEqual(await run(LIVE, [owner]), { code: 0, dispatched: ["40", "61"] });
  // Every trusted-actors.json entry is adoptable: the release App, a Bot, at once.
  const release = ciFixPull(65);
  release.author = { __typename: "Bot", databaseId: 337859524 };
  release.updatedAt = "2026-10-17T11:59:00Z";
  assert.deepEqual(await run(LIVE, [release]), { code: 0, dispatched: ["40", "65"] });
  // Dependabot's red PR is review-dependency's, never fix-ci's.
  const dependabot = ciFixPull(67);
  dependabot.author = { __typename: "Bot", databaseId: 49699333 };
  assert.deepEqual(await run(LIVE, [dependabot]), { code: 0, dispatched: ["40"] });
  const stranger = ciFixPull(66);
  stranger.author = { __typename: "User", databaseId: 4242 };
  stranger.updatedAt = idle;
  stranger.commits.nodes[0].commit.committedDate = idle;
  assert.deepEqual(await run(LIVE, [stranger]), { code: 0, dispatched: ["40"] });
  const without = LIVE.replace(/^adoption:\n( {2}.*\n)*/m, "");
  assert.doesNotMatch(without, /^adoption:/m);
  assert.deepEqual(await run(without, [owner]), { code: 0, dispatched: ["40"] });
  // A section without idle-hours adopts nothing, as in pr-merge.
  const noIdle = LIVE.replace(/^ {2}idle-hours: 24\n/m, "");
  assert.match(noIdle, /^adoption:\n {2}#/m);
  assert.deepEqual(await run(noIdle, [owner, release]), { code: 0, dispatched: ["40"] });
});

test("the base tracker config's human-gated label holds an adopted PR from fix-ci", async () => {
  const idle = "2026-10-16T11:00:00Z";
  const owner = ciFixPull(62);
  owner.author = { databaseId: 153232337 };
  owner.updatedAt = idle;
  owner.commits.nodes[0].commit.committedDate = idle;
  owner.labels = { nodes: [{ name: "awaiting-owner" }] };
  const mapped = JSON.stringify({ config: { role_labels: { "human-gated": "awaiting-owner" } } });
  assert.deepEqual(await run(LIVE, [owner], [], mapped), { code: 0, dispatched: ["40"] });
  assert.deepEqual(await run(LIVE, [owner]), { code: 0, dispatched: ["40", "62"] }, "with no tracker file the label is needs-human");
});

test("an unreadable base tracker config holds adopted owner PRs only, and no adoption section skips the read", async () => {
  const idle = "2026-10-16T11:00:00Z";
  const owner = ciFixPull(64);
  owner.author = { databaseId: 153232337 };
  owner.updatedAt = idle;
  owner.commits.nodes[0].commit.committedDate = idle;
  // The lanes App PR proceeds under the default hold labels; the failure still shows.
  assert.deepEqual(await run(LIVE, [ciFixPull(63), owner], [], "{not json"), { code: 1, dispatched: ["40", "63"] });
  const without = LIVE.replace(/^adoption:\n( {2}.*\n)*/m, "");
  assert.deepEqual(await run(without, [ciFixPull(63)], [], "{not json"), { code: 0, dispatched: ["40", "63"] });
});

test("the base config's limits.fix-docs-per-run caps the fix-docs dispatches", async () => {
  const pulls = [docsPull(61), docsPull(62), docsPull(63)];
  assert.match(LIVE, /^ {2}fix-docs-per-run: 2$/m, "the live config sets the per-run cap");
  assert.deepEqual(await run(LIVE, [], pulls), { code: 0, dispatched: ["40", "61", "62"] });
  const one = LIVE.replace(/^ {2}fix-docs-per-run: 2$/m, "  fix-docs-per-run: 1");
  assert.deepEqual(await run(one, [], pulls), { code: 0, dispatched: ["40", "61"] });
});

test("a base config the resolver refuses fails the run before any dispatch", async () => {
  const dispatched = [];
  const base = baseWith(withLimit("limit-stops-per-head: 0"));
  try {
    await assert.rejects(
      main(
        { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "4242", GITHUB_OUTPUT: join(base, "output"), BASE_PATH: base, APP_SENDER_ID: String(LANES_APP) },
        { api: api(dispatched), sleep: async () => {}, log: () => {} },
      ),
      /fails the schema/,
    );
    assert.deepEqual(dispatched, []);
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});
