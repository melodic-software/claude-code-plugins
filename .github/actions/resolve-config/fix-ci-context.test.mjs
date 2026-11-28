import assert from "node:assert/strict";
import { readFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { standardsCheckout } from "../../scripts/lib/trusted-actors.fixtures.mjs";
import { main } from "../../scripts/pr-unblock/fix-ci-context.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const APP = 337595936;
const fixCommit = {
  sha: "c".repeat(40),
  author: { id: APP },
  commit: { message: "Fix failing CI checks\n\nLane-Activity: pr-unblock/fix-ci\n" },
};
const api = {
  getPull: async () => ({ state: "open", head: { sha: "a".repeat(40), repo: { full_name: "o/r" } } }),
  listPullCommits: async () => [fixCommit, fixCommit, fixCommit],
  listCommitCheckRuns: async () =>
    Object.assign([{ id: 11, name: "Lint Shell", status: "completed", conclusion: "failure", app: { slug: "github-actions" } }], { complete: true }),
};

test("with no FIX_CI_ROUNDS, main reads loop.fix-ci-rounds from the base config", async () => {
  const dir = tempDir("fix-ci-context-");
  try {
    const env = {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: "o/r",
      GITHUB_OUTPUT: join(dir, "out"),
      PR_NUMBER: "42",
      APP_SENDER_ID: String(APP),
      CONTEXT_FILE: join(dir, "context.json"),
      BASE_PATH: ROOT,
      STANDARDS_DIR: standardsCheckout(),
    };
    await main(env, { api, log: () => {} });
    assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^escalation-reason=ci-fix-round-cap$/m);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
