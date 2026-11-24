// Decides whether a hosted review run reviews its head now or leaves it to
// the review a Refine push starts. Run by the wait-for-refine job of
// pr-review-hosted.yml and pr-review-security-hosted.yml before the review
// spends a model turn.
//
// It finds this head's pull_request_target runs of pr-unblock-dispatch.yml
// (the newest five), waits for each, reads the
// pr-unblock-target-dispatched-<commit>-<run id> records their refine jobs
// upload, and waits for the newest pr-refine.yml run they name. Then it reads
// the pull request: a head that moved (Refine pushed, or anyone else did) is
// left to the newer head's own review (proceed=false); otherwise the review
// runs (proceed=true). Every poll also reads the head, so a head that moves
// mid-wait ends the wait at that poll rather than holding the newer head's
// review in the per-PR queue. A poll reads the head from refs/pull/<n>/head,
// which answers 304 while the head holds; the pull request itself never does,
// since its body embeds the repository, whose pushed_at moves on every push.
// A ref read that shows another head, or fails, falls back to reading the
// pull request. The ref outlives a close or merge, so a pull request closed
// before or during the wait is caught at the final read, once the wait ends;
// a start read, made only when the event lacks the base ref or head
// repository, catches one closed before. A head read there
// as moved is read again after one poll before anything ends on it; a second
// read that shows this head again resumes the wait. No dispatcher run, no record, a record naming
// any other run, a wait past its cap, or any read that fails runs the review,
// as it ran before this job existed.
//
// Reads PR_NUMBER, HEAD_SHA, PR_BASE_REF and PR_HEAD_REPO from env, and the
// sender's and author's numeric ids from the event file; logs carry the PR
// number, SHAs and run ids only. Writes proceed and reason to GITHUB_OUTPUT.
// An event that an account in NO_REFINE_ACCOUNTS sent, on a pull request one
// opened, has no refine run due: it is reviewed after the finish read alone
// (https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#lanes).

import { appendFileSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { budgetedFetch } from "../pr-unblock/request-budget.mjs";

export const DEFAULTS = Object.freeze({ appearSeconds: 300, capSeconds: 1800, pollSeconds: 60 });
// A re-run or a later pull_request_target event adds a dispatcher run per
// head; the record may sit on any of them.
const DISPATCHER_RUNS = 5;
export const DISPATCHER = ".github/workflows/pr-unblock-dispatch.yml";
export const REFINE = ".github/workflows/pr-refine.yml";
const RECORD = /^pr-unblock-target-dispatched-[0-9a-f]{40}-([1-9][0-9]{0,14})$/;
const SECONDS = /^[1-9][0-9]{0,5}$/;
/**
 * fix-docs-dispatch.mjs's excludedAuthorIds, inline because this job's sparse
 * checkout holds no other pr-unblock module. refine-event-dispatch.mjs starts
 * no run on an event these accounts send, since none is the lanes App or a
 * listed human, and fix-docs never starts for a PR one opened. A
 * refine-dispatch activity can still start on a human's later event on the
 * same head; the test pins the live config's list empty.
 */
export const NO_REFINE_ACCOUNTS = Object.freeze([49699333, 337859524, 300666570]);

/** Whether this pull_request event, for this PR and head, has no refine run due. */
export function noRefineDue(event, { number, head }) {
  const pr = event?.pull_request;
  if (pr?.number !== number || pr?.head?.sha !== head) return false;
  return [event.sender?.id, pr.user?.id].every((id) => Number.isSafeInteger(id) && NO_REFINE_ACCOUNTS.includes(id));
}

function readEvent(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

export function readEnv(env) {
  if (!/^[1-9][0-9]{0,9}$/.test(env.PR_NUMBER ?? "")) throw new Error("PR_NUMBER is not a pull request number");
  if (!/^[0-9a-f]{40}$/.test(env.HEAD_SHA ?? "")) throw new Error("HEAD_SHA is not a commit SHA");
  if (!/^[A-Za-z0-9-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) throw new Error("GITHUB_REPOSITORY is not owner/name");
  for (const key of ["GITHUB_TOKEN", "GITHUB_OUTPUT"]) {
    if (!env[key]) throw new Error(`${key} is not set`);
  }
  const bound = (key, fallback) => {
    const value = env[key];
    if (value === undefined || value === "") return fallback * 1000;
    if (!SECONDS.test(value)) throw new Error(`${key} is not a whole number of seconds`);
    return Number(value) * 1000;
  };
  return {
    number: Number(env.PR_NUMBER),
    head: env.HEAD_SHA,
    repository: env.GITHUB_REPOSITORY,
    appearMs: bound("WAIT_APPEAR_SECONDS", DEFAULTS.appearSeconds),
    capMs: bound("WAIT_CAP_SECONDS", DEFAULTS.capSeconds),
    pollMs: bound("WAIT_POLL_SECONDS", DEFAULTS.pollSeconds),
    baseRef: env.PR_BASE_REF || null,
    headRepository: env.PR_HEAD_REPO || null,
  };
}

export async function decide({ number, head, repository, appearMs, capMs, pollMs, baseRef, headRepository, noRefine = false }, { api, now, sleep, log }) {
  const start = now();
  const deadline = start + capMs;
  const say = (level, text) => log(`::${level}::wait-refine #${number} ${head}: ${text}`);

  async function moved(pr) {
    pr ??= await api.get(`pulls/${number}`);
    if (pr.state === "open" && pr.head?.sha !== head) {
      await sleep(pollMs);
      pr = await api.get(`pulls/${number}`);
    }
    return pr.state !== "open" || pr.head?.sha !== head ? pr : null;
  }

  let refFailed = false;
  async function movedAtPoll() {
    let failure = null;
    try {
      const sha = (await api.get(`git/ref/pull/${number}/head`)).object?.sha;
      if (sha === head) return null;
      if (typeof sha !== "string") failure = "it named no commit";
    } catch (error) {
      failure = error.message;
    }
    if (failure && !refFailed) {
      refFailed = true;
      say("warning", `the head ref read failed (${failure}); polls read the pull request instead`);
    }
    return moved();
  }

  function skip(pr, after) {
    say("notice", `skip the review: the head is now ${pr.head?.sha ?? "unknown"} (${pr.state}), whose own review runs (after ${after})`);
    return { proceed: false, reason: "head-moved" };
  }

  async function poll() {
    await sleep(pollMs);
    return movedAtPoll();
  }

  async function completed(run, polls = 0) {
    while (run.status !== "completed") {
      if (now() + pollMs > deadline) return null;
      const pr = await poll();
      if (pr) return { moved: pr };
      polls += 1;
      if (polls % 2 === 1 || now() + pollMs > deadline) run = await api.get(`actions/runs/${run.id}`);
    }
    return { run };
  }

  async function finish(reason) {
    const pr = await moved();
    if (pr) return skip(pr, reason);
    say("notice", `review: ${reason}`);
    return { proceed: true, reason };
  }

  try {
    const pr = baseRef && headRepository ? null : await api.get(`pulls/${number}`);
    const [base, from] = pr ? [pr.base?.ref, pr.head?.repo?.full_name] : [baseRef, headRepository];
    if (base !== "main" || from !== repository) {
      return await finish("no-refine");
    }
    const gone = pr && (await moved(pr));
    if (gone) return skip(gone, "the start");
    if (noRefine) return await finish("no-refine-account");
    let runs;
    for (;;) {
      const listing = await api.get(`actions/workflows/pr-unblock-dispatch.yml/runs?event=pull_request_target&head_sha=${head}&per_page=100`);
      runs = (listing.workflow_runs ?? []).filter(
        (run) => run.path === DISPATCHER && run.event === "pull_request_target" && run.head_sha === head && run.head_repository?.full_name === repository,
      );
      if (runs.length > 0 || now() + pollMs > start + appearMs) break;
      const current = await poll();
      if (current) return skip(current, "waiting for a dispatcher run");
    }
    if (runs.length === 0) return await finish("no-dispatcher");

    let id = 0;
    let source = 0;
    for (const run of runs.sort((a, b) => b.id - a.id).slice(0, DISPATCHER_RUNS)) {
      const waited = await completed(run);
      if (!waited) return await finish("dispatcher-timeout");
      if (waited.moved) return skip(waited.moved, `waiting for dispatcher run ${run.id}`);
      const { artifacts = [] } = await api.get(`actions/runs/${run.id}/artifacts?per_page=100`);
      for (const artifact of artifacts) {
        const found = Number(RECORD.exec(artifact.name ?? "")?.[1] ?? 0);
        if (found > id) [id, source] = [found, run.id];
      }
    }
    if (id === 0) return await finish("no-dispatch");
    say("notice", `dispatcher run ${source} started pr-refine run ${id}`);

    const deferred = now() + pollMs <= deadline;
    if (deferred) {
      const pr = await poll();
      if (pr) return skip(pr, `waiting for pr-refine run ${id}`);
    }
    const refine = await api.get(`actions/runs/${id}`);
    if (refine.path !== REFINE || refine.event !== "workflow_dispatch" || refine.head_branch !== "main" || !String(refine.display_title ?? "").endsWith(` #${number}`)) {
      say("warning", `run ${id} named by dispatcher run ${source} is not a pr-refine.yml dispatch on main for #${number}; not waiting for it`);
      return await finish("not-refine");
    }
    const refined = await completed(refine, deferred ? 1 : 0);
    if (!refined) return await finish("refine-timeout");
    if (refined.moved) return skip(refined.moved, `waiting for pr-refine run ${id}`);
    const { conclusion } = refined.run;
    return await finish(`refine-${/^[a-z_]+$/.test(conclusion ?? "") ? conclusion : "unknown"}`);
  } catch (error) {
    say("warning", `a read failed (${error.message}); the review runs`);
    return { proceed: true, reason: "read-error" };
  }
}

// A REST reader over budgetedFetch: ETag reuse turns a repeat read of an
// unchanged resource (the head's ref, a completed run) into a 304 off the
// primary rate limit, and the rate guard records spend.
export function createApi({ token, repository, apiUrl = "https://api.github.com", budget }) {
  return {
    async get(path) {
      const response = await budget.fetch(`${apiUrl}/repos/${repository}/${path}`, {
        headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28" },
      });
      if (!response.ok) throw new Error(`GET ${path} returned ${response.status}`);
      return response.json();
    },
  };
}

export async function main(env, { api, now = () => Date.now(), sleep = (ms) => new Promise((r) => setTimeout(r, ms)), log = (line) => console.log(line) } = {}) {
  const input = readEnv(env);
  input.noRefine = Boolean(env.GITHUB_EVENT_PATH) && noRefineDue(readEvent(env.GITHUB_EVENT_PATH), input);
  const budget = api ? null : budgetedFetch({ log });
  const client = api ?? createApi({ token: env.GITHUB_TOKEN, repository: input.repository, apiUrl: env.GITHUB_API_URL || undefined, budget });
  const result = await decide(input, { api: client, now, sleep, log });
  appendFileSync(env.GITHUB_OUTPUT, `proceed=${result.proceed}\nreason=${result.reason}\n`);
  if (budget) log(budget.summary());
  return result;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).catch((error) => {
    console.log(`::error::wait-refine failed: ${error.message}`);
    process.exitCode = 1;
  });
}
