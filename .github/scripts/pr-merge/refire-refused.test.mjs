// Expected values come from the broker's refusal format in
// .github/actions/request-lane-token/action.yml: a lane run on a PR's current
// head that failed at "Request the lane token" with reason workflow-modified
// gets a new head (an empty commit) within one run, at most once per version
// of the named workflow file, and only for a PR whose head
// check-trusted-trigger would trust.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";
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
const LANE = "pr-unblock.yml";
const UNBLOCK = ".github/workflows/pr-unblock.yml";
const WRITER = ".github/workflows/pr-run-activity-write.yml";
const ACTIONS_BOT = { id: 41898282, login: "github-actions[bot]" };
const FILES = [UNBLOCK, WRITER, ".github/workflows/pr-unblock-dispatch.yml", ".github/workflows/pr-feedback-dispatch.yml"];
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
const TOKEN_STEP = "Request the lane token";
// A failed job's steps as the jobs API lists them in full: a job failing at a
// later step ran the token step first, and it succeeded.
const fullSteps = (step) => [
  { name: "Check the trigger", conclusion: "success" },
  ...(step === TOKEN_STEP ? [] : [{ name: TOKEN_STEP, conclusion: "success" }]),
  { name: step, conclusion: "failure" },
];
// A failed pr-unblock run dispatched on main for PR `number`; `job` is its
// failed job, `annotations` that job's. `steps` replaces the job's step list.
const run = (
  id,
  {
    number,
    event = "workflow_dispatch",
    title = `pr-unblock resolve-conflicts #${number}`,
    headBranch = "main",
    step = TOKEN_STEP,
    steps = fullSteps(step),
    // The write runner's job as the jobs API names it (`<caller> / run`).
    jobName = "apply-conflict-patch / run",
    conclusion = "failure",
    messages = [denial(UNBLOCK)],
    actor = ACTIONS_BOT,
    rerunner = actor,
    attempt = 1,
  } = {},
) => ({
  id,
  event,
  actor,
  triggering_actor: rerunner,
  run_attempt: attempt,
  head_sha: sha(1),
  head_branch: headBranch,
  display_title: title,
  repository: { full_name: REPO },
  head_repository: { full_name: REPO },
  job: { id: id * 10, name: jobName, conclusion, steps },
  annotations: messages.map((message) => ({ annotation_level: "failure", message })),
});
// The failed check a dispatched run's report job posts on the PR's head, as
// the API returns it (check run 122864732692 on #10583): details_url is the
// check run's own page, and only external_id names the posting run.
const linkedCheck = (id) => ({
  conclusion: "failure",
  details_url: `https://github.com/${REPO}/runs/${id + 5000}`,
  external_id: `pr-unblock:apply-conflict-patch:${id}:1`,
});
const marker = (path, blob, head, { user = BOT, at = "2026-10-17T21:50:00Z" } = {}) => ({ user, created_at: at, body: refireComment(path, blob, head, LANE) });

// `blobs` is main's blob per file; `changed` lists the files each head SHA
// changes against its merge base with main.
// `compare` is the status of a run's head against main; `moved` is a PR as a
// fresh GET /pulls/{n} answers it, when it changed since the listing; `refs`
// is each branch's tip as GET git/ref/heads/{branch} answers it: a SHA, null
// for a 404, {status} for that error, or {} for an answer with no SHA.
function world({ pulls = [], runs = {}, comments = {}, checks = {}, blobs = MAIN_BLOBS, changed = {}, compare = "ahead", moved = {}, refs = {}, mainTag = false, failOn } = {}) {
  const calls = [];
  const all = Object.values(runs).flat();
  const answer = (method, path, body) => {
    calls.push(body === undefined ? `${method} ${path}` : `${method} ${path} ${JSON.stringify(body)}`);
    // `failOn` is a call prefix that answers 422, or {prefix, status}.
    const fail = typeof failOn === "string" ? { prefix: failOn, status: 422 } : failOn;
    if (fail && `${method} ${path}`.startsWith(fail.prefix)) {
      throw new GitHubError(fail.status, `${method} ${path}`);
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
    if ((match = new RegExp(`^/repos/${REPO}/git/ref/heads/(.+)$`).exec(route)) && match[1] in refs) {
      const tip = refs[match[1]];
      if (tip === null || tip?.status !== undefined) {
        throw new GitHubError(tip?.status ?? 404, `${method} ${path}`);
      }
      return typeof tip === "string" ? { ref: `refs/heads/${match[1]}`, object: { sha: tip } } : { ref: `refs/heads/${match[1]}` };
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

// Each PR in `pulls` has one refused pr-unblock run whose failed check is on
// the PR's current head; `runOptions` changes every run.
const refusedWorld = (pulls, { runOptions = {}, ...options } = {}) =>
  world({
    pulls,
    runs: { [LANE]: pulls.map((pull) => run(pull.number * 10, { number: pull.number, ...runOptions })) },
    checks: Object.fromEntries(pulls.map((pull) => [pull.head.sha, [linkedCheck(pull.number * 10)]])),
    ...options,
  });

// resolve-config's output file, holding merge.refire-skip-branches as the
// repository's pr-pipeline.yaml sets it.
const OWNED = "release/plugins";
const resolvedConfig = (skip) => {
  const file = join(tempDir("refire-config-"), "resolved-config.json");
  writeFileSync(file, JSON.stringify({ merge: { "refire-skip-branches": skip } }));
  return file;
};
const env = {
  GITHUB_REPOSITORY: REPO,
  KILL_SWITCH: "proceed",
  TRUSTED_ACTORS_PATH: TRUSTED,
  LANES_APP_SENDER_ID: String(BOT.id),
  RESOLVED_CONFIG_PATH: resolvedConfig([OWNED]),
};
// The lines main() logs, with its exit code.
const logged = async (t, w, options = {}) => {
  const log = t.mock.method(console, "log", () => {});
  const code = await main({ env, github: w.github, actions: w.actions, now: NOW, ...options });
  return { code, lines: log.mock.calls.map((call) => String(call.arguments[0])) };
};
const pushes = (calls) => calls.filter((call) => call.startsWith("PATCH "));
const posts = (calls) => calls.filter((call) => call.startsWith(`POST /repos/${REPO}/issues/`));

test("a pr-unblock run refused as workflow-modified on the current head gets one empty commit on that branch", async () => {
  const w = refusedWorld([pr(9)]);
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(posts(w.calls), [`POST /repos/${REPO}/issues/9/comments ${JSON.stringify({ body: refireComment(UNBLOCK, BLOB, sha(9), LANE) })}`]);
  const commit = w.calls.find((call) => call.startsWith(`POST /repos/${REPO}/git/commits `));
  assert.ok(commit.includes(`"tree":"${TREE}"`) && commit.includes(`"parents":["${sha(9)}"]`));
  assert.deepEqual(pushes(w.calls), [`PATCH /repos/${REPO}/git/refs/heads/fix/9 {"sha":"${NEW_SHA}","force":false}`]);
  // The marker is posted before the branch moves.
  assert.ok(w.calls.indexOf(posts(w.calls)[0]) < w.calls.indexOf(pushes(w.calls)[0]));
});

test("a dispatched pr-unblock run re-fires only when its failed check is on the PR's current head", async () => {
  const dispatched = run(90, { number: 9, messages: [denial(WRITER)] });
  const linked = linkedCheck(90);
  const onHead = world({ pulls: [pr(9)], runs: { [LANE]: [dispatched] }, checks: { [sha(9)]: [linked] } });
  assert.equal(await main({ env, github: onHead.github, actions: onHead.actions, now: NOW }), 0);
  assert.equal(pushes(onHead.calls).length, 1);
  const elsewhere = world({ pulls: [pr(9)], runs: { [LANE]: [dispatched] }, checks: { [sha(9)]: [] } });
  assert.equal(await main({ env, github: elsewhere.github, actions: elsewhere.actions, now: NOW }), 0);
  assert.equal(pushes(elsewhere.calls).length, 0);
  // A run on a tag named main: its commit is not on the branch.
  const tag = world({ pulls: [pr(9)], runs: { [LANE]: [dispatched] }, checks: { [sha(9)]: [linked] }, compare: "diverged" });
  assert.equal(await main({ env, github: tag.github, actions: tag.actions, now: NOW }), 0);
  assert.equal(pushes(tag.calls).length, 0);
  // github-actions[bot] stands in only on a first attempt; a rerun needs a listed account.
  const rerun = world({
    pulls: [pr(9)],
    runs: { [LANE]: [{ ...dispatched, run_attempt: 2 }] },
    checks: { [sha(9)]: [linked] },
  });
  assert.equal(await main({ env, github: rerun.github, actions: rerun.actions, now: NOW }), 0);
  assert.equal(pushes(rerun.calls).length, 0);
});

test("a refused run links to its PR through the check's external_id, or a details_url naming the run's page, never the check run's own page", async () => {
  const dispatched = run(90, { number: 9, messages: [denial(WRITER)] });
  const refires = async (check) => {
    const w = world({ pulls: [pr(9)], runs: { [LANE]: [dispatched] }, checks: { [sha(9)]: [check] } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    return pushes(w.calls).length;
  };
  assert.equal(await refires({ conclusion: "failure", details_url: `https://github.com/${REPO}/runs/122864732692`, external_id: "pr-unblock:apply-feedback-patch:90:1" }), 1);
  assert.equal(await refires({ conclusion: "failure", details_url: `https://github.com/${REPO}/runs/90`, external_id: "" }), 0);
  assert.equal(await refires({ conclusion: "failure", details_url: `https://github.com/${REPO}/runs/5090`, external_id: "pr-unblock:apply-feedback-patch:91:1" }), 0);
  assert.equal(await refires({ conclusion: "failure", details_url: `https://github.com/${REPO}/actions/runs/90` }), 1);
  assert.equal(await refires({ conclusion: "success", external_id: "pr-unblock:apply-feedback-patch:90:1" }), 0);
});

test("a pr-refine.yml run is no longer read or re-fired", async () => {
  const w = world({ pulls: [pr(7)], runs: { "pr-refine.yml": [run(70, { number: 7 })] }, checks: { [sha(7)]: [linkedCheck(70)] } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.equal(w.calls.some((call) => call.includes("/actions/workflows/pr-refine.yml/")), false);
  assert.deepEqual(pushes(w.calls), []);
  assert.deepEqual(posts(w.calls), []);
});

// The comment text pr-merge posted for every lane until now, verbatim: markers
// already on open PRs carry it.
const POSTED = (path, blob, head) =>
  `<!-- pr-lane-refire ${path}@${blob} head ${head} -->\nA lane run on this pull request's head failed because the token broker refused it as workflow-modified: \`${path}\` changed on main after the run's event, and a rerun keeps the old file. pr-merge pushes an empty commit so new runs start on main's files. It does this once per version of that file, so if a run fails the same way again, a person looks at it.`;
const UNBLOCK_START =
  "the conflict-resolution run starts at the next push to main or half-hourly `pr-unblock-dispatch` tick, or when a listed person runs it by hand";
const postedBody = (calls) => JSON.parse(posts(calls)[0].replace(/^POST \S+ /, "")).body;

test("a pr-unblock re-fire says its conflict-resolution run waits for the next push to main, the next dispatcher tick or a listed person's dispatch", async () => {
  const w = refusedWorld([pr(9)], { runOptions: { messages: [denial(WRITER)] } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  const body = postedBody(w.calls);
  assert.equal(body.split("\n")[0], `<!-- pr-lane-refire ${WRITER}@${BLOB} head ${sha(9)} -->`);
  assert.ok(body.includes(UNBLOCK_START), body);
  assert.ok(!body.includes("so new runs start on main's files"), body);
});

test("a marker posted in the earlier wording still stops a second pr-unblock re-fire", async () => {
  const w = refusedWorld([pr(9)], {
    runOptions: { messages: [denial(WRITER)] },
    comments: { 9: [{ user: BOT, created_at: "2026-10-17T21:50:00Z", body: POSTED(WRITER, BLOB, sha(8)) }] },
  });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(pushes(w.calls), []);
  assert.deepEqual(posts(w.calls), []);
});

test("a run started or rerun by an unlisted account or by the lanes App re-fires nothing; a listed person's dispatch does", async () => {
  for (const runOptions of [{ actor: STRANGER }, { rerunner: STRANGER }, { actor: BOT }]) {
    const w = refusedWorld([pr(9)], { runOptions });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.deepEqual(pushes(w.calls), [], JSON.stringify(runOptions));
  }
  const listed = refusedWorld([pr(9)], { runOptions: { actor: OWNER, attempt: 2 } });
  assert.equal(await main({ env, github: listed.github, actions: listed.actions, now: NOW }), 0);
  assert.equal(pushes(listed.calls).length, 1);
});

test("a head that changes a file the broker compares is not re-fired: the refusal may come from that file, and no empty commit fixes it", async () => {
  for (const file of FILES) {
    const w = refusedWorld([pr(9)], { changed: { [sha(9)]: ["README.md", file] } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.deepEqual(pushes(w.calls), [], file);
    assert.deepEqual(posts(w.calls), [], file);
  }
});

test("a PR whose changed files cannot be listed in full is not re-fired", async () => {
  const many = Array.from({ length: 300 }, (_, index) => `docs/${index}.md`);
  const w = refusedWorld([pr(9)], { changed: { [sha(9)]: many } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(pushes(w.calls), []);
});

test("a tag named main stops the run before any run is read or anything pushed", async () => {
  const w = refusedWorld([pr(9)], { mainTag: true });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 1);
  assert.deepEqual(pushes(w.calls), []);
  assert.deepEqual(posts(w.calls), []);
  assert.equal(w.calls.some((call) => call.includes("/actions/")), false);
});

test("the fresh PR read and the tree read come before the marker, and the marker before the ref update", async () => {
  const w = refusedWorld([pr(9)]);
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  const at = (prefix) => w.calls.findIndex((call) => call.startsWith(prefix));
  const reread = at(`GET /repos/${REPO}/pulls/9`);
  const tree = at(`GET /repos/${REPO}/git/commits/${sha(9)}`);
  const comment = at(`POST /repos/${REPO}/issues/9/comments`);
  const ref = at("PATCH ");
  assert.ok(reread >= 0 && reread < tree && tree < comment && comment < ref, JSON.stringify({ reread, tree, comment, ref }));
});

test("a PR pushed, drafted or closed since the listing is not pushed to, and warns for that PR alone", async (t) => {
  for (const change of [{ head: { ...pr(9).head, sha: sha(90) } }, { draft: true }, { state: "closed" }]) {
    const w = refusedWorld([pr(9)], { moved: { 9: { ...pr(9), ...change } } });
    const { code, lines } = await logged(t, w);
    assert.equal(code, 0, JSON.stringify(change));
    assert.ok(lines.includes("::warning title=refire-refused::#9: the PR changed since it was listed; nothing pushed"), lines.join("\n"));
    assert.deepEqual(pushes(w.calls), [], JSON.stringify(change));
    assert.deepEqual(posts(w.calls), [], JSON.stringify(change));
  }
});

test("a run for another PR or off main, a failure at another step, or another broker reason re-fires nothing", async () => {
  for (const runOptions of [
    // The title names a PR that is not open.
    { title: "pr-unblock resolve-conflicts #10" },
    { headBranch: "fix" },
    { event: "pull_request" },
    { step: "Run the skill activity" },
    { messages: ["lane-token-denied: the broker answered 403 with reason untrusted-actor"] },
    // The broker named a file this lane is not compared on.
    { messages: [denial(".github/workflows/release.yml")] },
  ]) {
    const w = refusedWorld([pr(9)], { runOptions });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.deepEqual(pushes(w.calls), [], JSON.stringify(runOptions));
    assert.deepEqual(posts(w.calls), [], JSON.stringify(runOptions));
  }
});

test("a failed job whose step list lacks the token step is judged by its annotations; one listing the token step as passed is not", async () => {
  // The jobs API can answer a completed job with no steps or a cut list.
  for (const steps of [[], [{ name: "Check the trigger", conclusion: "success" }]]) {
    const w = refusedWorld([pr(9)], { runOptions: { steps } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.equal(pushes(w.calls).length, 1, JSON.stringify(steps));
    assert.equal(posts(w.calls).length, 1, JSON.stringify(steps));
  }
  // The full list shows the token step passed, so even a refusal annotation
  // re-fires nothing.
  const full = refusedWorld([pr(9)], { runOptions: { step: "Run the skill activity" } });
  assert.equal(await main({ env, github: full.github, actions: full.actions, now: NOW }), 0);
  assert.deepEqual(pushes(full.calls), []);
  assert.deepEqual(posts(full.calls), []);
});

const annotationReads = (calls) => calls.filter((call) => /\/check-runs\/\d+\/annotations/.test(call));

test("a job that is no write runner job, or did not fail, has its annotations unread even with no steps listed", async () => {
  // fix-ci / run is the read runner's job: it runs the model over PR content
  // and requests no lane token, so its annotations are never trusted.
  for (const runOptions of [
    { jobName: "fix-ci / run", steps: [] },
    { jobName: "apply-conflict-patch / report", steps: [] },
    { conclusion: "success", steps: [] },
  ]) {
    const w = refusedWorld([pr(9)], { runOptions });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.deepEqual(annotationReads(w.calls), [], JSON.stringify(runOptions));
    assert.deepEqual(pushes(w.calls), [], JSON.stringify(runOptions));
    assert.deepEqual(posts(w.calls), [], JSON.stringify(runOptions));
  }
});

test("every pr-unblock job that calls the write runner is read when its steps are missing", async () => {
  // The callers come from pr-unblock.yml itself, so a new one is covered.
  const yml = readFileSync(join(HERE, "../../workflows/pr-unblock.yml"), "utf8");
  const callers = [...yml.matchAll(/^ {2}([a-z0-9-]+):\n(?:(?! {2}\S).*\n)*? {4}uses: \.\/\.github\/workflows\/pr-run-activity-write\.yml/gm)].map((m) => m[1]);
  assert.ok(callers.includes("apply-conflict-patch") && callers.length >= 8, JSON.stringify(callers));
  for (const caller of callers) {
    const w = refusedWorld([pr(9)], { runOptions: { jobName: `${caller} / run`, steps: [] } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.equal(pushes(w.calls).length, 1, caller);
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
  const w = refusedWorld(pulls);
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(pushes(w.calls), []);
});

test("a PR already re-fired for this version of the file is never re-fired again, so a failing run cannot loop", async () => {
  // The marker names the old head: the push landed, and the new head failed the same way.
  const w = refusedWorld([pr(9)], { comments: { 9: [marker(UNBLOCK, BLOB, sha(8))] } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(pushes(w.calls), []);
  assert.deepEqual(posts(w.calls), []);
});

test("a new version of the file on main re-fires once more", async () => {
  const w = refusedWorld([pr(9)], { comments: { 9: [marker(UNBLOCK, BLOB, sha(8))] }, blobs: { ...MAIN_BLOBS, [UNBLOCK]: NEW_BLOB } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.equal(pushes(w.calls).length, 1);
});

test("a marker at the current head means the push did not land: it retries the push without a second marker", async () => {
  const w = refusedWorld([pr(9)], { comments: { 9: [marker(UNBLOCK, BLOB, sha(9))] } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(posts(w.calls), []);
  assert.equal(pushes(w.calls).length, 1);
});

test("a push that has not landed an hour after its marker is not retried again, and warns so a person looks", async (t) => {
  const w = refusedWorld([pr(9)], { comments: { 9: [marker(UNBLOCK, BLOB, sha(9), { at: "2026-10-17T20:59:00Z" })] } });
  const { code, lines } = await logged(t, w);
  assert.equal(code, 0);
  assert.deepEqual(pushes(w.calls), []);
  assert.ok(lines.includes(`::warning title=refire-refused::#9 not re-fired: its push for ${UNBLOCK} at ${BLOB} did not land; a person looks`), lines.join("\n"));
});

test("a marker by anyone but the lanes App counts for nothing", async () => {
  const w = refusedWorld([pr(9)], { comments: { 9: [marker(UNBLOCK, BLOB, sha(8), { user: OWNER })] } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.equal(pushes(w.calls).length, 1);
});

test("a failed marker comment pushes nothing and fails the run", async (t) => {
  const w = refusedWorld([pr(9)], { failOn: `POST /repos/${REPO}/issues/9/comments` });
  const { code, lines } = await logged(t, w);
  assert.equal(code, 1);
  assert.deepEqual(pushes(w.calls), []);
  assert.ok(lines.includes(`::error title=refire-refused::#9: POST /repos/${REPO}/issues/9/comments failed with status 422`), lines.join("\n"));
});

// A new commit object names only its tree and parent, so no branch move can
// refuse it: any error writing it would hit every PR the same way.
test("a 409 on the commit write fails the run at the first PR instead of warning for each", async (t) => {
  const w = refusedWorld([pr(9), pr(30)], { failOn: { prefix: `POST /repos/${REPO}/git/commits`, status: 409 } });
  const { code, lines } = await logged(t, w);
  assert.equal(code, 1);
  assert.deepEqual(pushes(w.calls), []);
  assert.equal(w.calls.filter((call) => call.startsWith(`POST /repos/${REPO}/git/commits `)).length, 1);
  assert.ok(lines.includes(`::error title=refire-refused::#9: POST /repos/${REPO}/git/commits failed with status 409`), lines.join("\n"));
  assert.equal(lines.some((line) => line.startsWith("::warning")), false, lines.join("\n"));
});

test("a 403 on the ref update fails the run at the first PR instead of warning for each", async (t) => {
  const w = refusedWorld([pr(9), pr(30), pr(41)], { failOn: { prefix: "PATCH ", status: 403 } });
  const { code, lines } = await logged(t, w);
  assert.equal(code, 1);
  assert.equal(pushes(w.calls).length, 1);
  assert.ok(lines.includes(`::error title=refire-refused::#9: PATCH /repos/${REPO}/git/refs/heads/fix/9 failed with status 403`), lines.join("\n"));
  assert.equal(lines.some((line) => line.startsWith("::warning")), false, lines.join("\n"));
});

test("a named file with no blob SHA on main fails the run before anything is posted or pushed", async (t) => {
  const w = refusedWorld([pr(9)], { blobs: { ...MAIN_BLOBS, [UNBLOCK]: undefined } });
  const { code, lines } = await logged(t, w);
  assert.equal(code, 1);
  assert.deepEqual(pushes(w.calls), []);
  assert.deepEqual(posts(w.calls), []);
  assert.ok(lines.includes(`::error title=refire-refused::${UNBLOCK} on main has no blob SHA`), lines.join("\n"));
});

test("a failed run listing for a lane fails the run and pushes nothing", async (t) => {
  const w = refusedWorld([pr(9)], { failOn: `GET /repos/${REPO}/actions/workflows/${LANE}/runs` });
  const { code, lines } = await logged(t, w);
  assert.equal(code, 1);
  assert.deepEqual(pushes(w.calls), []);
  assert.deepEqual(posts(w.calls), []);
  assert.ok(lines.some((line) => line.startsWith(`::error title=refire-refused::${LANE}:`)), lines.join("\n"));
});

// Run 41065454536: one PR's ref update answered 422, and the step failed the
// whole merge job.
// A 409 or 422 on the ref update is that branch moving under the push only
// when a fresh read of the branch shows it moved or gone.
test("one PR's failed ref update is a warning for that PR alone: the rest still re-fire and the run passes", async (t) => {
  const w = refusedWorld([pr(9), pr(30), pr(41)], { failOn: `PATCH /repos/${REPO}/git/refs/heads/fix/30`, refs: { "fix/30": sha(31) } });
  const { code, lines } = await logged(t, w);
  assert.equal(code, 0);
  assert.deepEqual(
    pushes(w.calls).map((call) => /heads\/fix\/(\d+)/.exec(call)[1]),
    ["9", "30", "41"],
  );
  assert.ok(lines.includes(`::warning title=refire-refused::#30: PATCH /repos/${REPO}/git/refs/heads/fix/30 failed with status 422`), lines.join("\n"));
  assert.equal(lines.some((line) => line.startsWith("::error")), false, lines.join("\n"));
  assert.equal(lines.at(-1), "refire-refused: outcome re-fired=2 failed=1 skipped-owned=0 deferred=0");
});

test("a 409 on the ref update of a branch deleted under the push warns for that PR alone", async (t) => {
  const w = refusedWorld([pr(9), pr(30)], { failOn: { prefix: `PATCH /repos/${REPO}/git/refs/heads/fix/9`, status: 409 }, refs: { "fix/9": null } });
  const { code, lines } = await logged(t, w);
  assert.equal(code, 0);
  assert.equal(pushes(w.calls).length, 2);
  assert.ok(lines.includes(`::warning title=refire-refused::#9: PATCH /repos/${REPO}/git/refs/heads/fix/9 failed with status 409`), lines.join("\n"));
  assert.equal(lines.at(-1), "refire-refused: outcome re-fired=1 failed=1 skipped-owned=0 deferred=0");
});

test("a 422 on the ref update of a branch still at the head it was read at fails the run at that PR", async (t) => {
  const w = refusedWorld([pr(9), pr(30), pr(41)], { failOn: `PATCH /repos/${REPO}/git/refs/heads/fix/30`, refs: { "fix/30": sha(30) } });
  const { code, lines } = await logged(t, w);
  assert.equal(code, 1);
  assert.deepEqual(
    pushes(w.calls).map((call) => /heads\/fix\/(\d+)/.exec(call)[1]),
    ["9", "30"],
  );
  assert.ok(lines.some((line) => line.startsWith(`::error title=refire-refused::#30: PATCH /repos/${REPO}/git/refs/heads/fix/30 failed with status 422`)), lines.join("\n"));
  assert.equal(lines.some((line) => line.startsWith("::warning")), false, lines.join("\n"));
});

test("a ref update refused with a 409 whose branch cannot be read again fails the run at that PR", async (t) => {
  for (const [tip, cause] of [
    [{ status: 500 }, `GET /repos/${REPO}/git/ref/heads/fix/9 failed with status 500`],
    [{}, `PATCH /repos/${REPO}/git/refs/heads/fix/9 failed with status 409; the branch's tip cannot be read`],
  ]) {
    const w = refusedWorld([pr(9), pr(30)], { failOn: { prefix: `PATCH /repos/${REPO}/git/refs/heads/fix/9`, status: 409 }, refs: { "fix/9": tip } });
    const { code, lines } = await logged(t, w);
    assert.equal(code, 1, JSON.stringify(tip));
    assert.equal(pushes(w.calls).length, 1, JSON.stringify(tip));
    assert.ok(lines.includes(`::error title=refire-refused::#9: ${cause}`), lines.join("\n"));
    assert.equal(lines.some((line) => line.startsWith("::warning")), false, lines.join("\n"));
  }
});

test("a PR from a branch the config names as workflow-owned is never commented on or pushed to; the others still are", async (t) => {
  const w = refusedWorld([pr(9), pr(31, { ref: OWNED })]);
  const { code, lines } = await logged(t, w);
  assert.equal(code, 0);
  assert.deepEqual(pushes(w.calls), [`PATCH /repos/${REPO}/git/refs/heads/fix/9 {"sha":"${NEW_SHA}","force":false}`]);
  assert.deepEqual(posts(w.calls).map((call) => /issues\/(\d+)\//.exec(call)[1]), ["9"]);
  assert.ok(lines.includes(`refire-refused: #31 not re-fired: its branch ${OWNED} is owned by a workflow that rebuilds it`), lines.join("\n"));
  assert.equal(lines.at(-1), "refire-refused: outcome re-fired=1 failed=0 skipped-owned=1 deferred=0");
});

test("the skip list is the config's: a branch it does not name re-fires, and a branch added to it does not", async (t) => {
  const unlisted = refusedWorld([pr(31, { ref: OWNED })]);
  assert.equal((await logged(t, unlisted, { env: { ...env, RESOLVED_CONFIG_PATH: resolvedConfig([]) } })).code, 0);
  assert.deepEqual(pushes(unlisted.calls), [`PATCH /repos/${REPO}/git/refs/heads/${OWNED} {"sha":"${NEW_SHA}","force":false}`]);
  const added = refusedWorld([pr(9)]);
  assert.equal((await logged(t, added, { env: { ...env, RESOLVED_CONFIG_PATH: resolvedConfig([OWNED, "fix/9"]) } })).code, 0);
  assert.deepEqual(pushes(added.calls), []);
  assert.deepEqual(posts(added.calls), []);
});

test("an unreadable or malformed resolved config stops the run before anything is pushed", async (t) => {
  const dir = tempDir("refire-bad-config-");
  const malformed = join(dir, "bad.json");
  writeFileSync(malformed, JSON.stringify({ merge: { "refire-skip-branches": "release/plugins" } }));
  for (const path of [join(dir, "missing.json"), malformed, ""]) {
    const w = refusedWorld([pr(9)]);
    const { code } = await logged(t, w, { env: { ...env, RESOLVED_CONFIG_PATH: path } });
    assert.equal(code, 1, path);
    assert.deepEqual(pushes(w.calls), [], path);
    assert.deepEqual(posts(w.calls), [], path);
  }
});

test("at most REFIRES_PER_RUN PRs are re-fired in one run, lowest number first", async () => {
  const pulls = Array.from({ length: 7 }, (_, index) => pr(index + 20));
  const w = refusedWorld(pulls);
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.equal(REFIRES_PER_RUN, 5);
  assert.deepEqual(
    pushes(w.calls).map((call) => /heads\/fix\/(\d+)/.exec(call)[1]),
    ["20", "21", "22", "23", "24"],
  );
});

test("the kill switch stops the run before any API call", async () => {
  const w = refusedWorld([pr(9)]);
  assert.equal(await main({ env: { ...env, KILL_SWITCH: "" }, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.deepEqual(w.calls, []);
});

// The Re-fire step names lanes-app (its GH_TOKEN, the lane token); the job
// token's client still counts and plans as github-token: the reading lands in
// api-budget/github-token, and its read floor uses github-token's limit-cap of
// 1000 (rate-limits.json), so 950 of 5000 used is under a tenth of the plan
// left (50 of 1000), where lanes-app's uncapped plan of 5000 would not be.
test("the job token's client counts its readings and plans its read floor as github-token", async () => {
  const { actionsClient } = await import("./refire-refused.mjs");
  const { createRateLimitLatch } = await import("../../actions/log-api-budget/rate-guard.mjs");
  const { tempDir } = await import("../../../lib/test-tmp.mjs");
  const { rmSync, existsSync } = await import("node:fs");
  const dir = tempDir("refire-budget-");
  const saved = { RUNNER_TEMP: process.env.RUNNER_TEMP, API_BUDGET_TOKEN: process.env.API_BUDGET_TOKEN };
  Object.assign(process.env, { RUNNER_TEMP: dir, API_BUDGET_TOKEN: "lanes-app" });
  try {
    const lines = [];
    const latch = createRateLimitLatch({ log: (line) => lines.push(line), fail: () => {}, stopFile: null });
    const headers = { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4050", "x-ratelimit-used": "950", "x-ratelimit-reset": "1792751600", "x-ratelimit-resource": "core" };
    const fetchImpl = async () => new Response("{}", { status: 200, headers });
    await actionsClient({ ACTIONS_TOKEN: "job" }, { latch, fetchImpl })("GET", "/repos/o/r/actions/runs");
    assert.equal(readFileSync(join(dir, "api-budget", "github-token"), "utf8"), "200 5000 4050 950 1792751600 core repos/{repo}/actions/runs\n");
    assert.equal(existsSync(join(dir, "api-budget", "lanes-app")), false);
    assert.deepEqual(lines, ["::warning::GitHub's core API has under its read floor left (50 of the planned 1000; header remaining 4050 of 5000); reads continue"]);
  } finally {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    rmSync(dir, { recursive: true, force: true });
  }
});

// A token step that failed transiently, in request-lane-token/action.yml's
// wording: no broker response, or a 5xx after the action's own retries.
const UNREACHABLE = "broker-unreachable: the lanes token broker gave no response, after 503 with reason github-unavailable";
const DENIED_5XX = "lane-token-denied: the broker answered 502 with reason internal-error: upstream timed out";
const FEEDBACK = { title: "pr-unblock address-feedback #9", jobName: "apply-feedback-patch / run" };
const transientMarker = (runId, head, { tree = TREE, at = "2026-10-17T21:50:00Z" } = {}) => ({
  user: BOT,
  created_at: at,
  body: `<!-- pr-lane-refire transient run ${runId} tree ${tree} head ${head} -->\nre-fired`,
});

test("an address-feedback run whose token step got no broker response or a 5xx gets one empty commit and a transient marker", async () => {
  for (const [message, label] of [
    [UNREACHABLE, "broker-unreachable"],
    [DENIED_5XX, "lane-token-denied 502 internal-error"],
  ]) {
    const w = refusedWorld([pr(9)], { runOptions: { ...FEEDBACK, messages: [message] } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.deepEqual(pushes(w.calls), [`PATCH /repos/${REPO}/git/refs/heads/fix/9 {"sha":"${NEW_SHA}","force":false}`], label);
    const body = postedBody(w.calls);
    assert.equal(body.split("\n")[0], `<!-- pr-lane-refire transient run 90 tree ${TREE} head ${sha(9)} -->`);
    assert.ok(body.includes(`\`${label}\``), body);
    const commit = w.calls.find((call) => call.startsWith(`POST /repos/${REPO}/git/commits `));
    assert.ok(commit.includes(label) && commit.includes(`"parents":["${sha(9)}"]`), commit);
  }
});

test("a token 403 for any reason other than workflow-modified is not re-fired, and neither is a 4xx or a garbled 5xx", async () => {
  for (const message of [
    "lane-token-denied: the broker answered 403 with reason actor-untrusted",
    "lane-token-denied: the broker answered 403 with reason kill-switch",
    "lane-token-denied: the broker answered 429 with reason github-rate-limited",
    "lane-token-denied: the broker answered 5xx with reason internal-error",
    `note: ${UNREACHABLE}`,
  ]) {
    const w = refusedWorld([pr(9)], { runOptions: { ...FEEDBACK, messages: [message] } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.deepEqual(pushes(w.calls), [], message);
    assert.deepEqual(posts(w.calls), [], message);
  }
});

test("a transient token failure of an activity pr-unblock-dispatch retries itself is left to that tick", async () => {
  for (const activity of ["resolve-conflicts", "review-dependency", "fix-ci"]) {
    const w = refusedWorld([pr(9)], { runOptions: { title: `pr-unblock ${activity} #9`, messages: [DENIED_5XX] } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.deepEqual(pushes(w.calls), [], activity);
    assert.deepEqual(posts(w.calls), [], activity);
  }
});

test("a transient re-fire is capped at one per failed run and two per head tree", async (t) => {
  // This run was already re-fired: its marker names an older head.
  const sameRun = refusedWorld([pr(9)], { runOptions: { ...FEEDBACK, messages: [DENIED_5XX] }, comments: { 9: [transientMarker(90, sha(8))] } });
  assert.equal(await main({ env, github: sameRun.github, actions: sameRun.actions, now: NOW }), 0);
  assert.deepEqual(pushes(sameRun.calls), []);
  assert.deepEqual(posts(sameRun.calls), []);
  // Two earlier runs were re-fired on the same tree (empty commits keep it).
  const atCap = refusedWorld([pr(9)], {
    runOptions: { ...FEEDBACK, messages: [DENIED_5XX] },
    comments: { 9: [transientMarker(70, sha(7)), transientMarker(80, sha(8))] },
  });
  const { code, lines } = await logged(t, atCap);
  t.mock.restoreAll();
  assert.equal(code, 0);
  assert.deepEqual(pushes(atCap.calls), []);
  assert.ok(lines.some((line) => line.startsWith("::warning title=refire-refused::#9 not re-fired: re-fired 2 times")), lines.join("\n"));
  // One earlier re-fire on this tree, or two on another tree, leave room.
  for (const comments of [[transientMarker(80, sha(8))], [transientMarker(70, sha(7), { tree: "d".repeat(40) }), transientMarker(80, sha(8), { tree: "d".repeat(40) })]]) {
    const w = refusedWorld([pr(9)], { runOptions: { ...FEEDBACK, messages: [DENIED_5XX] }, comments: { 9: comments } });
    assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
    assert.equal(pushes(w.calls).length, 1);
  }
});

test("a transient marker at the current head retries only the push, within the retry window", async () => {
  const w = refusedWorld([pr(9)], { runOptions: { ...FEEDBACK, messages: [DENIED_5XX] }, comments: { 9: [transientMarker(90, sha(9))] } });
  assert.equal(await main({ env, github: w.github, actions: w.actions, now: NOW }), 0);
  assert.equal(pushes(w.calls).length, 1);
  assert.deepEqual(posts(w.calls), []);
  const stale = refusedWorld([pr(9)], {
    runOptions: { ...FEEDBACK, messages: [DENIED_5XX] },
    comments: { 9: [transientMarker(90, sha(9), { at: "2026-10-17T20:00:00Z" })] },
  });
  assert.equal(await main({ env, github: stale.github, actions: stale.actions, now: NOW }), 0);
  assert.deepEqual(pushes(stale.calls), []);
});
