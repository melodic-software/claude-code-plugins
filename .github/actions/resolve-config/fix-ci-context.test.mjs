// fix-ci-context.mjs's round cap read through the real resolver: with no
// FIX_CI_ROUNDS, main takes loop.fix-ci-rounds from the base's
// pr-pipeline.yaml. Lives here because it needs resolve-config's dependencies.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { main } from "../../scripts/pr-unblock/fix-ci-context.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../..");
// The lanes App bot's id (.github/standards/trusted-actors/trusted-actors.json).
const APP = 337595936;
const fixCommit = {
  sha: "c".repeat(40),
  author: { id: APP },
  commit: { message: "Fix failing CI checks\n\nLane-Activity: pr-unblock/fix-ci\n" },
};
const api = {
  getPull: async () => ({ state: "open", head: { sha: "a".repeat(40) } }),
  listPullCommits: async () => [fixCommit, fixCommit, fixCommit],
};

test("with no FIX_CI_ROUNDS, main reads loop.fix-ci-rounds from the base config", async () => {
  const dir = mkdtempSync(join(tmpdir(), "fix-ci-context-"));
  try {
    const env = {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: "o/r",
      GITHUB_OUTPUT: join(dir, "out"),
      PR_NUMBER: "42",
      APP_SENDER_ID: String(APP),
      CONTEXT_FILE: join(dir, "context.json"),
      // This checkout stands in for the base: its config sets 3.
      BASE_PATH: ROOT,
    };
    await main(env, { api, log: () => {} });
    assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^escalation-reason=ci-fix-round-cap$/m);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
