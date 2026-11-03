// who.mjs: a scheduled run's first attempt and pr-verify's PR-scoped wake
// proceed with no read; every other run proceeds only when its actor and the
// starter of this attempt are listed humans, by id. github-actions[bot]'s id
// is 41898282 (GET /users/github-actions%5Bbot%5D).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { main } from "./who.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = "melodic-software/claude-code-plugins";
const OWNER_ID = 153232337;
const dir = tempDir("who-");

const WAKE = {
  GITHUB_EVENT_NAME: "workflow_dispatch",
  GITHUB_RUN_ATTEMPT: "1",
  GITHUB_REF: "refs/heads/main",
  ACTOR_ID: "41898282",
  DISPATCH_PR: "42",
};

let n = 0;
// `rerunner`: the triggering actor this run's own record names.
async function who(env, { rerunner = OWNER_ID } = {}) {
  n += 1;
  const output = join(dir, `output-${n}`);
  const calls = [];
  const actions = async (method, path) => {
    calls.push(`${method} ${path}`);
    return { id: 700, run_attempt: Number(env.GITHUB_RUN_ATTEMPT), triggering_actor: { id: rerunner } };
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    await main({
      env: { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "700", GITHUB_OUTPUT: output, TRUSTED_ACTORS_PATH: join(HERE, "fixtures/trusted-actors.json"), ...env },
      actions,
    });
  } finally {
    console.log = log;
  }
  return { proceed: /^proceed=true$/m.test(readFileSync(output, "utf8")), calls, stdout: lines.join("\n") };
}

test("pr-verify's wake proceeds with no read: github-actions[bot], attempt 1, on main, with a pull request", async () => {
  const run = await who(WAKE);
  assert.equal(run.proceed, true);
  assert.deepEqual(run.calls, []);
});

test("a near miss of the wake stops", async () => {
  for (const [why, change] of [
    ["another bot", { ACTOR_ID: "337595936" }],
    ["attempt 2", { GITHUB_RUN_ATTEMPT: "2" }],
    ["no pr input", { DISPATCH_PR: "" }],
    ["no pr input at all", { DISPATCH_PR: undefined }],
    ["a pr input that is no number", { DISPATCH_PR: "42 " }],
    ["a pr input of 0", { DISPATCH_PR: "0" }],
    ["not main", { GITHUB_REF: "refs/heads/fix/other" }],
    ["another event", { GITHUB_EVENT_NAME: "pull_request_target" }],
  ]) {
    const run = await who({ ...WAKE, ...change }, { rerunner: 41898282 });
    assert.equal(run.proceed, false, why);
    assert.match(run.stdout, /^::notice::started by an account that is not a listed human/m, why);
  }
});

test("a re-run of the wake proceeds only when a listed human started it", async () => {
  assert.equal((await who({ ...WAKE, GITHUB_RUN_ATTEMPT: "2" }, { rerunner: 41898282 })).proceed, false);
  // The bot is no listed human, so even a listed human's re-run of its run stops.
  assert.equal((await who({ ...WAKE, GITHUB_RUN_ATTEMPT: "2" }, { rerunner: OWNER_ID })).proceed, false);
});

test("a listed human's hand-started run, with or without a pull request, proceeds after its record read", async () => {
  for (const pr of ["", "42"]) {
    const run = await who({ ...WAKE, ACTOR_ID: String(OWNER_ID), DISPATCH_PR: pr });
    assert.equal(run.proceed, true, pr);
    assert.deepEqual(run.calls, [`GET /repos/${REPO}/actions/runs/700`], pr);
  }
});

test("a scheduled run's first attempt proceeds with no read", async () => {
  const run = await who({ GITHUB_EVENT_NAME: "schedule", GITHUB_RUN_ATTEMPT: "1", ACTOR_ID: "1" });
  assert.equal(run.proceed, true);
  assert.deepEqual(run.calls, []);
});
