// Decides whether a hosted review run reviews its head now or leaves it to
// the review a Refine push starts. Run by the wait-refine job of
// pr-review-hosted.yml and pr-review-security-hosted.yml before the review
// spends a model turn.
//
// It finds this head's pull_request_target runs of pr-unblock-dispatch.yml
// (the newest five), waits for each, reads the
// pr-unblock-target-dispatched-<commit>-<run id> records their refine jobs
// upload, and waits for the newest pr-refine.yml run they name. Then it reads
// the pull request: a head that moved (Refine pushed, or anyone else did) is
// left to the newer head's own review (proceed=false); otherwise the review
// runs (proceed=true). Every poll also reads the pull request, so a head that
// moves mid-wait ends the wait at once rather than holding the newer head's
// review in the per-PR queue. No dispatcher run, no record, a record naming
// any other run, a wait past its cap, or any read that fails runs the review,
// as it ran before this job existed.
//
// Reads PR_NUMBER and HEAD_SHA from env only; logs carry the PR number, SHAs
// and run ids only. Writes proceed and reason to GITHUB_OUTPUT.

import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { budgetedFetch } from "../pr-unblock/request-budget.mjs";

export const DEFAULTS = Object.freeze({ appearSeconds: 300, capSeconds: 2400, pollSeconds: 30 });
// A re-run or a later pull_request_target event adds a dispatcher run per
// head; the record may sit on any of them.
const DISPATCHER_RUNS = 5;
const MOVED = Symbol("head moved");
// A poll read the head as moved and the wait stopped; finish confirms it, and
// a confirming read that finds this head again reviews under this reason.
const HEAD_READ_MOVED = "head-read-moved";
export const DISPATCHER = ".github/workflows/pr-unblock-dispatch.yml";
export const REFINE = ".github/workflows/pr-refine.yml";
const RECORD = /^pr-unblock-target-dispatched-[0-9a-f]{40}-([1-9][0-9]{0,14})$/;
const SECONDS = /^[1-9][0-9]{0,5}$/;

export function readEnv(env) {
  if (!/^[1-9][0-9]{0,9}$/.test(env.PR_NUMBER ?? "")) throw new Error("PR_NUMBER is not a pull request number");
  if (!/^[0-9a-f]{40}$/.test(env.HEAD_SHA ?? "")) throw new Error("HEAD_SHA is not a commit SHA");
  if (!/^[A-Za-z0-9-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) throw new Error("GITHUB_REPOSITORY is not owner/name");
  for (const key of ["GITHUB_TOKEN", "GITHUB_OUTPUT"]) {
    if (!env[key]) throw new Error(`${key} is not set`);
  }
  const bound = (key, fallback) => {
    if (env[key] === undefined || env[key] === "") return fallback * 1000;
    if (!SECONDS.test(env[key])) throw new Error(`${key} is not a whole number of seconds`);
    return Number(env[key]) * 1000;
  };
  return {
    number: Number(env.PR_NUMBER),
    head: env.HEAD_SHA,
    repository: env.GITHUB_REPOSITORY,
    appearMs: bound("WAIT_APPEAR_SECONDS", DEFAULTS.appearSeconds),
    capMs: bound("WAIT_CAP_SECONDS", DEFAULTS.capSeconds),
    pollMs: bound("WAIT_POLL_SECONDS", DEFAULTS.pollSeconds),
  };
}

export async function decide({ number, head, repository, appearMs, capMs, pollMs }, { api, now, sleep, log }) {
  const start = now();
  const deadline = start + capMs;
  const say = (level, text) => log(`::${level}::wait-refine #${number} ${head}: ${text}`);

  // One pulls read per poll: true once the pull request is closed or its head
  // is no longer this one.
  async function headMoved() {
    const pr = await api.get(`pulls/${number}`);
    return pr.state !== "open" || pr.head?.sha !== head;
  }

  // Re-reads run <id> until it completes; returns null once the next poll
  // would pass the cap, or MOVED once the head moves.
  async function completed(run) {
    while (run.status !== "completed") {
      if (now() + pollMs > deadline) return null;
      await sleep(pollMs);
      if (await headMoved()) return MOVED;
      run = await api.get(`actions/runs/${run.id}`);
    }
    return run;
  }

  // A head that reads as moved is read again after one poll before the skip,
  // so one lagging read cannot leave this head with no review.
  async function finish(reason) {
    let pr = await api.get(`pulls/${number}`);
    if (pr.state === "open" && pr.head?.sha !== head) {
      await sleep(pollMs);
      pr = await api.get(`pulls/${number}`);
    }
    if (pr.state !== "open" || pr.head?.sha !== head) {
      say("notice", `skip the review: the head is now ${pr.head?.sha ?? "unknown"} (${pr.state}), whose own review runs (after ${reason})`);
      return { proceed: false, reason: "head-moved" };
    }
    say("notice", `review: ${reason}`);
    return { proceed: true, reason };
  }

  try {
    // The dispatcher's refine job runs only for a same-repository PR into
    // main, so any other PR is reviewed without waiting out the window, and
    // a head already moved is skipped at once.
    const pr = await api.get(`pulls/${number}`);
    if (pr.state !== "open" || pr.head?.sha !== head || pr.base?.ref !== "main" || pr.head?.repo?.full_name !== repository) {
      return await finish("no-refine");
    }
    let runs = [];
    for (;;) {
      const listing = await api.get(`actions/workflows/pr-unblock-dispatch.yml/runs?event=pull_request_target&head_sha=${head}&per_page=100`);
      runs = (listing.workflow_runs ?? []).filter(
        (run) => run.path === DISPATCHER && run.event === "pull_request_target" && run.head_sha === head && run.head_repository?.full_name === repository,
      );
      if (runs.length > 0 || now() + pollMs > start + appearMs) break;
      await sleep(pollMs);
      if (await headMoved()) return await finish(HEAD_READ_MOVED);
    }
    if (runs.length === 0) return await finish("no-dispatcher");

    let id = 0;
    let source = 0;
    for (const run of runs.sort((a, b) => b.id - a.id).slice(0, DISPATCHER_RUNS)) {
      const dispatcher = await completed(run);
      if (dispatcher === MOVED) return await finish(HEAD_READ_MOVED);
      if (!dispatcher) return await finish("dispatcher-timeout");
      const { artifacts = [] } = await api.get(`actions/runs/${dispatcher.id}/artifacts?per_page=100`);
      for (const artifact of artifacts) {
        const found = Number(RECORD.exec(artifact.name ?? "")?.[1] ?? 0);
        if (found > id) [id, source] = [found, dispatcher.id];
      }
    }
    if (id === 0) return await finish("no-dispatch");
    say("notice", `dispatcher run ${source} started pr-refine run ${id}`);

    const refine = await api.get(`actions/runs/${id}`);
    // pr-refine.yml's run-name ends with the PR number it refines.
    if (refine.path !== REFINE || refine.event !== "workflow_dispatch" || refine.head_branch !== "main" || !String(refine.display_title ?? "").endsWith(` #${number}`)) {
      say("warning", `run ${id} named by dispatcher run ${source} is not a pr-refine.yml dispatch on main for #${number}; not waiting for it`);
      return await finish("not-refine");
    }
    const done = await completed(refine);
    if (done === MOVED) return await finish(HEAD_READ_MOVED);
    if (!done) return await finish("refine-timeout");
    return await finish(`refine-${/^[a-z_]+$/.test(done.conclusion ?? "") ? done.conclusion : "unknown"}`);
  } catch (error) {
    say("warning", `a read failed (${error.message}); the review runs`);
    return { proceed: true, reason: "read-error" };
  }
}

// A REST reader over budgetedFetch: ETag reuse keeps each repeat poll a 304
// off the primary rate limit, and the rate guard records spend.
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
