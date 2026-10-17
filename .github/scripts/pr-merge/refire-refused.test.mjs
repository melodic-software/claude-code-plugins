// Expected values come from issue #7849 and the broker's refusal format in
// .github/actions/request-lane-token/action.yml: a lane run on a PR's current
// head that failed at "Request the lane token" with reason workflow-modified
// gets a new head (an empty commit) within one run, at most once per version
// of the named workflow file, and only for a PR whose head
// check-trusted-trigger would trust.
import assert from "node:assert/strict";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { REFIRES_PER_RUN, main, refireComment } from "./refire-refused.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TRUSTED = join(HERE, "fixtures/trusted-actors.json");
const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton" };
const STRANGER = { id: 999, login: "stranger" };
const BOT = { id: 337595936, login: "melodic-automation-lanes[bot]" };
const NOW = Date.parse("2026-10-17T22:00:00Z");
const BLOB = "b".repeat(40);
const NEW_BLOB = "c".repeat(40);
const TREE = "e".repeat(40);
const NEW_SHA = "f".repeat(40);
const sha = (n) => String(n).padStart(40, "0");
const MAIN_TIP = "a".repeat(40);
const REFINE = ".github/workflows/pr-refine.yml";
const WRITER = ".github/workflows/pr-run-activity-write.yml";
const MERGE = ".github/workflows/pr-merge.yml";
const ACTIONS_BOT = { id: 41898282, login: "github-actions[bot]" };
const FILES = [REFINE, WRITER, MERGE, ".github/workflows/pr-unblock.yml", ".github/workflows/pr-unblock-dispatch.yml", ".github/workflows/pr-feedback-dispatch.yml"];
const MAIN_BLOBS = Object.fromEntries(FILES.map((file) => [file, BLOB]));

const pr = (number, { user = OWNER, draft = false, repo = REPO, ref = `fix/${number}` } = {}) => ({
  number,
  state: "open",
  draft,
  user,
  base: { ref: "main" },
  head: { sha: sha(number), ref, repo: { full_name: repo } },
});
const denial = (path) => `lane-token-denied: the broker answered 403 with reason workflow-modified: ${path} differs from refs/heads/main`;
// A failed lane run; `job` is its failed job, `annotations` that job's.
const run = (
  id,
  { head, event = "pull_request", title = "", headBranch = "fix", step = "Request the lane token", messages = [denial(REFINE)], actor = OWNER, rerunner = actor, attempt = 1 } = {},
) => ({
  id,
  event,
  actor,
  triggering_actor: rerunner,
  run_attempt: attempt,
  head_sha: head,
  head_branch: headBranch,
  display_title: title,
  repository: { full_name: REPO },
  head_repository: { full_name: REPO },
  job: { id: id * 10, conclusion: "failure", steps: [{ name: "Check the trigger", conclusion: "success" }, { name: step, conclusion: "failure" }] },
  annotations: messages.map((message) => ({ annotation_level: "failure", message })),
});
const marker = (path, blob, head, { user = BOT, at = "2026-10-17T21:50:00Z" } = {}) => ({ user, created_at: at, body: refireComment(path, blob, head) });

// `blobs` is main's blob per file; `changed` lists the files each head SHA
// changes against its merge base with main.
// `compare` is the status of a run's head against main; `moved` is a PR as a
// fresh GET /pulls/{n} answers it, when it changed since the listing.
function world({ pulls = [], runs = {}, comments = {}, checks = {}, blobs = MAIN_BLOBS, changed = {}, compare = "ahead", moved = {}, mainTag = false, failOn } = {}) {
  const calls = [];
  const all = Object.values(runs).flat();
  const answer = (method, path, body) => {
    calls.push(body === undefined ? `${method} ${path}` : `${method} ${path} ${JSON.stringify(body)}`);
    if (failOn && `${method} ${path}`.startsWith(failOn)) {
      throw new Error(`${method} ${path} failed with status 422`);
    }
    const route = path.replace(/\?.*$/, "");
    const page = Number(new URL(path, "https://x").searchParams.get("page") ?? "1");
    const listed = (items) => (page === 1 ? items : []);
    let match;
    if (route === `/repos/${REPO}/pulls`) {
      return listed(pulls);
    }
    if ((match = /\/actions\/workflows\/([a-z-]+\.yml)\/runs$/.exec(route))) {
      return { workflow_runs: listed(runs[match[1]] ?? []) };
    }
    if ((match = /\/actions\/runs\/(\d+)\/jobs$/.exec(route))) {
      return { jobs: [all.find((item) => item.id === Number(match[1])).job] };
    }
    if ((match = /\/check-runs\/(\d+)\/annotations$/.exec(route))) {
      return all.find((item) => item.job.id === Number(match[1])).annotations;
    }
    if ((match = /\/commits\/([0-9a-f]{40})\/check-runs$/.exec(route))) {
      return { check_runs: checks[match[1]] ?? [] };
    }
    if (route === `/repos/${REPO}/git/ref/tags/main`) {
      if (mainTag) {
        return { ref: "refs/tags/main", object: { sha: sha(1) } };
      }
      throw new GitHubError(404, `${method} ${path}`);
    }
    if (route === `/repos/${REPO}/git/ref/heads/main`) {
      return { ref: "refs/heads/main", object: { sha: MAIN_TIP } };
    }
    // Every main-side read names main's tip, never the name main.
    if ((match = /\/contents\/(.+)$/.exec(route))) {
      assert.equal(new URL(path, "https://x").searchParams.get("ref"), MAIN_TIP);
      return { sha: blobs[match[1]] };
    }
    if ((match = new RegExp(`/compare/${MAIN_TIP}\\.\\.\\.([0-9a-f]{40})$`).exec(route))) {
      return { files: (changed[match[1]] ?? ["README.md"]).map((filename) => ({ filename })) };
    }
    if (new RegExp(`/compare/[0-9a-f]{40}\\.\\.\\.${MAIN_TIP}$`).test(route)) {
      return { status: compare };
    }
    if ((match = /\/pulls\/(\d+)$/.exec(route))) {
      return moved[match[1]] ?? pulls.find((pull) => pull.number === Number(match[1]));
    }
    if ((match = /\/issues\/(\d+)\/comments$/.exec(route))) {
      return method === "POST" ? {} : listed(comments[match[1]] ?? []);
    }
    if (/\/git\/commits\/[0-9a-f]{40}$/.test(route)) {
      return { tree: { sha: TREE } };
    }
    if (route.endsWith("/git/commits")) {
      return { sha: NEW_SHA };
    }
    if (route.includes("/git/refs/heads/")) {
      return {};
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  const fn = async (method, path, body) => answer(method, path, body);
  return { github: fn, actions: fn, calls };
}

const env = { GITHUB_REPOSITORY: REPO, KILL_SWITCH: "proceed", TRUSTED_ACTORS_PATH: TRUSTED, LANES_APP_SENDER_ID: String(BOT.id) };
const pushes = (calls) => calls.filter((call) => call.startsWith("PATCH "));
const posts = (calls) => calls.filter((call) => call.startsWith(`POST /repos/${REPO}/issues/`));

test("a pr-refine run refused as workflow-modified on the current head gets one empty commit on that branch", async () => {
  const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { head: sha(7) })] } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(posts(w.calls), [`POST /repos/${REPO}/issues/7/comments ${JSON.stringify({ body: refireComment(REFINE, BLOB, sha(7)) })}`]);
  const commit = w.calls.find((call) => call.startsWith(`POST /repos/${REPO}/git/commits `));
  assert.ok(commit.includes(`"tree":"${TREE}"`) && commit.includes(`"parents":["${sha(7)}"]`));
  assert.deepEqual(pushes(w.calls), [`PATCH /repos/${REPO}/git/refs/heads/fix/7 {"sha":"${NEW_SHA}","force":false}`]);
  // The marker is posted before the branch moves.
  assert.ok(w.calls.indexOf(posts(w.calls)[0]) < w.calls.indexOf(pushes(w.calls)[0]));
});

test("a pr-merge pull_request_target run refused for pr-merge.yml re-fires too", async () => {
  const w = world({
    pulls: [pr(8)],
    runs: { "pr-merge.yml": [run(80, { head: sha(8), event: "pull_request_target", messages: [denial(MERGE)] })] },
  });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.equal(pushes(w.calls).length, 1);
});

test("a dispatched pr-unblock run re-fires only when its failed check is on the PR's current head", async () => {
  const dispatched = run(90, { head: sha(1), event: "workflow_dispatch", title: "pr-unblock resolve-conflicts #9", headBranch: "main", messages: [denial(WRITER)], actor: ACTIONS_BOT });
  const linked = { conclusion: "failure", details_url: `https://github.com/${REPO}/actions/runs/90` };
  const onHead = world({ pulls: [pr(9)], runs: { "pr-unblock.yml": [dispatched] }, checks: { [sha(9)]: [linked] } });
  assert.equal(await main({ env, github: onHead.github, actions: onHead.actions, now: NOW }), 0);
  assert.equal(pushes(onHead.calls).length, 1);
  const elsewhere = world({ pulls: [pr(9)], runs: { "pr-unblock.yml": [dispatched] }, checks: { [sha(9)]: [] } });
  assert.equal(await main({ env, github: elsewhere.github, actions: elsewhere.actions, now: NOW }), 0);
  assert.equal(pushes(elsewhere.calls).length, 0);
  // A run on a tag named main: its commit is not on the branch.
  const tag = world({ pulls: [pr(9)], runs: { "pr-unblock.yml": [dispatched] }, checks: { [sha(9)]: [linked] }, compare: "diverged" });
  assert.equal(await main({ env, github: tag.github, actions: tag.actions, now: NOW }), 0);
  assert.equal(pushes(tag.calls).length, 0);
  // github-actions[bot] stands in only on a first attempt; a rerun needs a listed account.
  const rerun = world({
    pulls: [pr(9)],
    runs: { "pr-unblock.yml": [{ ...dispatched, run_attempt: 2 }] },
    checks: { [sha(9)]: [linked] },
  });
  assert.equal(await main({ env, github: rerun.github, actions: rerun.actions, now: NOW }), 0);
  assert.equal(pushes(rerun.calls).length, 0);
});

test("a run started or rerun by an unlisted account or by the lanes App re-fires nothing", async () => {
  for (const failedRun of [
    run(75, { head: sha(7), actor: STRANGER }),
    run(76, { head: sha(7), rerunner: STRANGER }),
    run(77, { head: sha(7), actor: BOT }),
    run(78, { head: sha(7), actor: ACTIONS_BOT }),
  ]) {
    const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [failedRun] } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.deepEqual(pushes(w.calls), [], `run ${failedRun.id}`);
  }
});

test("a head that changes a file the broker compares is not re-fired: the refusal may come from that file, and no empty commit fixes it", async () => {
  for (const file of [REFINE, WRITER]) {
    const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { head: sha(7) })] }, changed: { [sha(7)]: ["README.md", file] } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.deepEqual(pushes(w.calls), [], file);
    assert.deepEqual(posts(w.calls), [], file);
  }
});

test("a PR whose changed files cannot be listed in full is not re-fired", async () => {
  const many = Array.from({ length: 300 }, (_, index) => `docs/${index}.md`);
  const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { head: sha(7) })] }, changed: { [sha(7)]: many } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(pushes(w.calls), []);
});

test("a tag named main stops the run before any run is read or anything pushed", async () => {
  const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { head: sha(7) })] }, mainTag: true });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 1);
  assert.deepEqual(pushes(w.calls), []);
  assert.deepEqual(posts(w.calls), []);
  assert.equal(w.calls.some((call) => call.includes("/actions/")), false);
});

test("the fresh PR read and the tree read come before the marker, and the marker before the ref update", async () => {
  const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { head: sha(7) })] } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  const at = (prefix) => w.calls.findIndex((call) => call.startsWith(prefix));
  const reread = at(`GET /repos/${REPO}/pulls/7`);
  const tree = at(`GET /repos/${REPO}/git/commits/${sha(7)}`);
  const comment = at(`POST /repos/${REPO}/issues/7/comments`);
  const ref = at("PATCH ");
  assert.ok(reread >= 0 && reread < tree && tree < comment && comment < ref, JSON.stringify({ reread, tree, comment, ref }));
});

test("a PR pushed, drafted or closed since the listing is not pushed to", async () => {
  for (const change of [{ head: { ...pr(7).head, sha: sha(70) } }, { draft: true }, { state: "closed" }]) {
    const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { head: sha(7) })] }, moved: { 7: { ...pr(7), ...change } } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 1);
    assert.deepEqual(pushes(w.calls), [], JSON.stringify(change));
    assert.deepEqual(posts(w.calls), [], JSON.stringify(change));
  }
});

test("a run on an older head, a failure at another step, or another broker reason re-fires nothing", async () => {
  for (const failedRun of [
    run(71, { head: sha(1234) }),
    run(72, { head: sha(7), step: "Run the skill activity" }),
    run(73, { head: sha(7), messages: ["lane-token-denied: the broker answered 403 with reason untrusted-actor"] }),
    // The broker named a file this lane is not compared on.
    run(74, { head: sha(7), messages: [denial(".github/workflows/release.yml")] }),
  ]) {
    const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [failedRun] } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.deepEqual(pushes(w.calls), [], `run ${failedRun.id}`);
    assert.deepEqual(posts(w.calls), [], `run ${failedRun.id}`);
  }
});

test("only a head check-trusted-trigger trusts qualifies: no untrusted author, fork, draft or Dependabot PR is pushed to", async () => {
  const pulls = [
    pr(11, { user: STRANGER }),
    pr(12, { repo: "someone/fork" }),
    pr(13, { draft: true }),
    pr(14, { user: { id: 49699333, login: "dependabot[bot]" } }),
    pr(15, { ref: "fix/$(boom)" }),
  ];
  const runs = { "pr-refine.yml": pulls.map((pull) => run(pull.number * 10, { head: pull.head.sha })) };
  const w = world({ pulls, runs });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(pushes(w.calls), []);
});

test("a PR already re-fired for this version of the file is never re-fired again, so a failing run cannot loop", async () => {
  // The marker names the old head: the push landed, and the new head failed the same way.
  const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { head: sha(7) })] }, comments: { 7: [marker(REFINE, BLOB, sha(6))] } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(pushes(w.calls), []);
  assert.deepEqual(posts(w.calls), []);
});

test("a new version of the file on main re-fires once more", async () => {
  const w = world({
    pulls: [pr(7)],
    runs: { "pr-refine.yml": [run(70, { head: sha(7) })] },
    comments: { 7: [marker(REFINE, BLOB, sha(6))] },
    blobs: { ...MAIN_BLOBS, [REFINE]: NEW_BLOB },
  });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.equal(pushes(w.calls).length, 1);
});

test("a marker at the current head means the push did not land: it retries the push without a second marker", async () => {
  const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { head: sha(7) })] }, comments: { 7: [marker(REFINE, BLOB, sha(7))] } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(posts(w.calls), []);
  assert.equal(pushes(w.calls).length, 1);
});

test("a push that has not landed an hour after its marker is not retried again", async () => {
  const w = world({
    pulls: [pr(7)],
    runs: { "pr-refine.yml": [run(70, { head: sha(7) })] },
    comments: { 7: [marker(REFINE, BLOB, sha(7), { at: "2026-10-17T20:59:00Z" })] },
  });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(pushes(w.calls), []);
});

test("a marker by anyone but the lanes App counts for nothing", async () => {
  const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { head: sha(7) })] }, comments: { 7: [marker(REFINE, BLOB, sha(6), { user: OWNER })] } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.equal(pushes(w.calls).length, 1);
});

test("a failed marker comment pushes nothing and fails the run", async () => {
  const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { head: sha(7) })] }, failOn: `POST /repos/${REPO}/issues/7/comments` });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 1);
  assert.deepEqual(pushes(w.calls), []);
});

test("at most REFIRES_PER_RUN PRs are re-fired in one run, lowest number first", async () => {
  const pulls = Array.from({ length: 7 }, (_, index) => pr(index + 20));
  const w = world({ pulls, runs: { "pr-refine.yml": pulls.map((pull) => run(pull.number * 10, { head: pull.head.sha })) } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.equal(REFIRES_PER_RUN, 5);
  assert.deepEqual(
    pushes(w.calls).map((call) => /heads\/fix\/(\d+)/.exec(call)[1]),
    ["20", "21", "22", "23", "24"],
  );
});

test("the kill switch stops the run before any API call", async () => {
  const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { head: sha(7) })] } });
  assert.equal(await main({ env: { ...env, KILL_SWITCH: "" }, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(w.calls, []);
});
