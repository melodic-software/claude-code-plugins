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
  for (const file of ["docs/conventions/pr-pipeline/pr-pipeline.schema.json", ".github/standards/github-actions-conventions/vocabulary.json"]) {
    mkdirSync(dirname(join(base, file)), { recursive: true });
    cpSync(join(ROOT, file), join(base, file));
  }
  writeFileSync(join(base, "docs/conventions/pr-pipeline.yaml"), text);
  return base;
}

const api = (dispatched) => ({
  listOpenPulls: async () => ({
    nodes: [{ number: 40, isDraft: false, isCrossRepository: false, mergeable: "CONFLICTING", baseRefName: "main", headRefOid: HEAD }],
    pageInfo: { hasNextPage: false, endCursor: null },
  }),
  getPulls: async () => [],
  listCheckRuns: async () => [STOPPED],
  listWorkflowRuns: async () => [],
  dispatchWorkflow: async ({ inputs }) => {
    dispatched.push(inputs["pr-number"]);
    return { workflowRunId: 9040 };
  },
});

async function run(text) {
  const base = baseWith(text);
  const output = join(base, "output");
  writeFileSync(output, "");
  const dispatched = [];
  try {
    const code = await main(
      { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "4242", GITHUB_OUTPUT: output, BASE_PATH: base },
      { api: api(dispatched), sleep: async () => {}, log: () => {}, now: Date.parse("2026-10-17T12:00:00Z") },
    );
    return { code, dispatched };
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
}

test("the base config's limits.limit-stops-per-head decides whether a reset limit stop still holds the head", async () => {
  assert.deepEqual(await run(LIVE), { code: 0, dispatched: ["40"] });
  assert.deepEqual(await run(`${LIVE}\nlimits:\n  limit-stops-per-head: 1\n`), { code: 0, dispatched: [] });
});

test("a base config the resolver refuses fails the run before any dispatch", async () => {
  const dispatched = [];
  const base = baseWith(`${LIVE}\nlimits:\n  limit-stops-per-head: 0\n`);
  try {
    await assert.rejects(
      main(
        { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "4242", GITHUB_OUTPUT: join(base, "output"), BASE_PATH: base },
        { api: api(dispatched), sleep: async () => {}, log: () => {} },
      ),
      /fails the schema/,
    );
    assert.deepEqual(dispatched, []);
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});
