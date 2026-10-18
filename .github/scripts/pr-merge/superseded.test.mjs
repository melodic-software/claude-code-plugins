// Expected values come from pr-merge.yml: a run that is pending in the
// `pr-merge` concurrency group starts after the running one, and it sweeps
// every candidate when it is scheduled or a listed human started it (the
// "Check who started the run" step). Only schedule runs re-fire refused lane
// runs, and pull_request_target runs start no full CI run, so a run is
// superseded only by one that does at least what it does.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { main } from "./superseded.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton" };
const LANES_BOT = { id: 337595936, login: "melodic-automation-lanes[bot]" };
const QUEUE_BOT = { id: 79413782, login: "github-merge-queue[bot]" };
const THIS_RUN = "500";
const LISTING = `/repos/${REPO}/actions/workflows/pr-merge.yml/runs?status=pending&exclude_pull_requests=true&per_page=100`;
const dir = mkdtempSync(join(tmpdir(), "superseded-"));
after(() => rmSync(dir, { recursive: true, force: true }));

const pending = (id, event, actor = OWNER) => ({ id, event, status: "pending", triggering_actor: actor });

let n = 0;
async function check({ event = "schedule", runs = [], fail, body } = {}) {
  n += 1;
  const output = join(dir, `output-${n}`);
  const calls = [];
  const actions = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (fail) {
      throw fail;
    }
    return body ?? { total_count: runs.length, workflow_runs: runs };
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  let status;
  try {
    status = await main({
      env: {
        GITHUB_REPOSITORY: REPO,
        GITHUB_RUN_ID: THIS_RUN,
        GITHUB_EVENT_NAME: event,
        GITHUB_OUTPUT: output,
        TRUSTED_ACTORS_PATH: join(HERE, "fixtures/trusted-actors.json"),
      },
      actions,
    });
  } finally {
    console.log = log;
  }
  let written = "";
  try {
    written = readFileSync(output, "utf8");
  } catch {}
  return { status, calls, stdout: lines.join("\n"), superseded: /^superseded=true$/m.test(written), written };
}

test("a pending scheduled run supersedes a scheduled run, with one listing call and a notice", async () => {
  const run = await check({ runs: [pending(600, "schedule", QUEUE_BOT)] });
  assert.equal(run.status, 0);
  assert.equal(run.superseded, true);
  assert.deepEqual(run.calls, [`GET ${LISTING}`]);
  assert.match(run.stdout, /^::notice::.*run 600 \(schedule\)/m);
});

test("no other pending run: the gate runs", async () => {
  const run = await check({ runs: [] });
  assert.equal(run.superseded, false);
  assert.match(run.written, /^superseded=false$/m);
});

test("the run itself in the listing never supersedes it", async () => {
  const run = await check({ runs: [pending(Number(THIS_RUN), "schedule")] });
  assert.equal(run.superseded, false);
});

test("a pending run a listed human started by hand supersedes a pull_request_target run", async () => {
  const run = await check({ event: "pull_request_target", runs: [pending(600, "workflow_dispatch")] });
  assert.equal(run.superseded, true);
});

test("a pending pull_request_target run by a listed human supersedes another pull_request_target run", async () => {
  const run = await check({ event: "pull_request_target", runs: [pending(600, "pull_request_target")] });
  assert.equal(run.superseded, true);
});

test("a pending run a bot started stops before its sweep, so it supersedes nothing", async () => {
  const run = await check({ event: "pull_request_target", runs: [pending(600, "pull_request_target", LANES_BOT)] });
  assert.equal(run.superseded, false);
});

test("a listed id with another login does not count as the listed human", async () => {
  const run = await check({ event: "pull_request_target", runs: [pending(600, "workflow_dispatch", { id: OWNER.id, login: "someone-else" })] });
  assert.equal(run.superseded, false);
});

test("a pull_request_target run never supersedes a scheduled or hand-started run, which do more", async () => {
  for (const event of ["schedule", "workflow_dispatch"]) {
    const run = await check({ event, runs: [pending(600, "pull_request_target")] });
    assert.equal(run.superseded, false, event);
  }
});

test("a hand-started run never supersedes a scheduled run, which alone re-fires refused lane runs", async () => {
  const run = await check({ event: "schedule", runs: [pending(600, "workflow_dispatch")] });
  assert.equal(run.superseded, false);
});

test("a run of any other event, or with no actor, supersedes nothing", async () => {
  const run = await check({ runs: [pending(600, "push"), { id: 601, event: "workflow_dispatch", status: "pending" }] });
  assert.equal(run.superseded, false);
});

test("a run whose listed status is not pending supersedes nothing", async () => {
  const run = await check({ runs: [{ ...pending(600, "schedule"), status: "in_progress" }] });
  assert.equal(run.superseded, false);
});

test("a failed listing runs the gate, with a warning", async () => {
  const run = await check({ fail: new GitHubError(503, `GET ${LISTING}`) });
  assert.equal(run.status, 0);
  assert.equal(run.superseded, false);
  assert.match(run.stdout, /^::warning title=superseded::.*status 503.*the gate runs$/m);
});

test("an unreadable listing runs the gate, with a warning", async () => {
  const run = await check({ body: { workflow_runs: "nope" } });
  assert.equal(run.superseded, false);
  assert.match(run.stdout, /^::warning title=superseded::.*unexpected shape/m);
});

test("an unknown current event runs the gate without a listing call", async () => {
  const run = await check({ event: "push", runs: [pending(600, "schedule")] });
  assert.equal(run.superseded, false);
  assert.deepEqual(run.calls, []);
});
