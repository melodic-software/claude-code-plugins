#!/usr/bin/env node
// recent-sweep.mjs: tells a pr-merge `merge` job woken by pull_request_target
// whether to skip its sweep because another one finished within
// merge.event-sweep-min-minutes. Such a sweep already read every candidate,
// and the next scheduled run, at most 15 minutes away, reads them again, so
// the event's change waits at most that long. Scheduled and hand-started runs
// always sweep.
//
// A sweep finished when its run uploaded the pr-merge-summary artifact, which
// a run that ran the gate does even when the gate stopped early (its budget,
// a failure, a cancel). So the newest unexpired one counts only when its run
// is main's pr-merge.yml (scheduled or hand-started on main, or
// pull_request_target) and its pr-merge-sweep.json shows the gate reached
// every candidate: budget_stop null and one non-held row per listed candidate
// (sweep-summary.mjs). A skip prints one line for counting saved sweeps:
//   event-sweep-skip: last-sweep-finished=<iso> age-min=<n> min-minutes=<N>
//
// Any failure, or a summary missing a field, answers `skip=false`: the run
// sweeps, as every run did before this check. Two REST calls, and a third, the
// artifact download, only when the sweep is inside the window; all with the
// job's own token (actions: read).
//
// Environment:
//   ACTIONS_TOKEN        the job's GITHUB_TOKEN
//   GITHUB_REPOSITORY    owner/repo
//   GITHUB_RUN_ID        this run, never its own last sweep
//   GITHUB_EVENT_NAME    this run's event
//   MIN_MINUTES          merge.event-sweep-min-minutes; empty is 10, 0 never skips
//   GITHUB_OUTPUT        receives skip=true or skip=false
//   GITHUB_STEP_SUMMARY  the skip is listed there when set
//   RUNNER_TEMP          where the artifact is downloaded
//   GITHUB_API_URL
import { execFileSync } from "node:child_process";
import { appendFileSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

const ARTIFACT = "pr-merge-summary";
const WORKFLOW_PATH = ".github/workflows/pr-merge.yml";
const DEFAULT_MINUTES = 10;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

const SUMMARY_FILE = "pr-merge-sweep.json";

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// A run of main's copy of pr-merge.yml that sweeps.
function sweepRun(run) {
  return (
    run?.path === WORKFLOW_PATH &&
    (run.event === "pull_request_target" ||
      ((run.event === "schedule" || run.event === "workflow_dispatch") && run.head_branch === "main"))
  );
}

// Whether a pr-merge-sweep.json shows the gate reached every candidate it
// listed: no budget stop, and the rows less the held ones match the listed
// count (gated rows plus carried ones). Any missing field is incomplete.
export function sweptAll(sweep) {
  return (
    sweep?.budget_stop === null &&
    Number.isInteger(sweep.candidates) &&
    Number.isInteger(sweep.held) &&
    Array.isArray(sweep.results) &&
    sweep.results.length - sweep.held === sweep.candidates
  );
}

function ghDownload({ repo, token, dir }) {
  return (artifactId) => {
    const zip = join(mkdtempSync(join(dir, "recent-sweep-")), "artifact.zip");
    const bytes = execFileSync("gh", ["api", `repos/${repo}/actions/artifacts/${artifactId}/zip`], {
      env: { ...process.env, GH_TOKEN: token },
      maxBuffer: 64 * 1024 * 1024,
      stdio: ["ignore", "pipe", "inherit"],
    });
    writeFileSync(zip, bytes);
    return execFileSync("unzip", ["-p", zip, SUMMARY_FILE], { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] });
  };
}

export async function main({ env = process.env, actions, download, now = Date.now() } = {}) {
  let skip = false;
  try {
    if (env.GITHUB_EVENT_NAME !== "pull_request_target") {
      return 0;
    }
    const setting = env.MIN_MINUTES ?? "";
    if (setting !== "" && !/^\d+$/.test(setting)) {
      throw new Error(`merge.event-sweep-min-minutes is not a whole number: ${setting}`);
    }
    const min = setting === "" ? DEFAULT_MINUTES : Number(setting);
    if (min === 0) {
      return 0;
    }
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const listing = await actions("GET", `/repos/${env.GITHUB_REPOSITORY}/actions/artifacts?name=${ARTIFACT}&per_page=10`);
    if (!Array.isArray(listing?.artifacts)) {
      throw new Error("the artifact listing has an unexpected shape");
    }
    const newest = listing.artifacts
      .filter((a) => a?.expired === false && String(a.workflow_run?.id) !== String(env.GITHUB_RUN_ID))
      .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))[0];
    if (newest === undefined) {
      console.log("no finished pr-merge sweep found; this run sweeps");
      return 0;
    }
    const finished = Date.parse(newest.created_at);
    if (Number.isNaN(finished)) {
      throw new Error(`artifact ${newest.id} has no readable created_at`);
    }
    const run = await actions("GET", `/repos/${env.GITHUB_REPOSITORY}/actions/runs/${newest.workflow_run.id}`);
    if (!sweepRun(run)) {
      console.log(`the newest ${ARTIFACT} artifact is not from a pr-merge sweep on main; this run sweeps`);
      return 0;
    }
    const age = Math.max(0, Math.floor((now - finished) / 60_000));
    if (age >= min) {
      console.log(`the last pr-merge sweep finished ${age} minutes ago, not within ${min}; this run sweeps`);
      return 0;
    }
    download ??= ghDownload({ repo: env.GITHUB_REPOSITORY, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP || tmpdir() });
    if (!sweptAll(JSON.parse(download(newest.id)))) {
      console.log(`run ${run.id}'s sweep did not reach every candidate; this run sweeps`);
      return 0;
    }
    skip = true;
    console.log(`event-sweep-skip: last-sweep-finished=${new Date(finished).toISOString()} age-min=${age} min-minutes=${min}`);
    const msg = `run ${run.id} (${run.event}) finished a sweep ${age} minutes ago, within merge.event-sweep-min-minutes (${min}), so this run skips its sweep; the next scheduled run checks every candidate`;
    console.log(`::notice::${escapeCommand(msg)}`);
    if (env.GITHUB_STEP_SUMMARY) {
      appendFileSync(env.GITHUB_STEP_SUMMARY, `- ${msg}\n`);
    }
  } catch (error) {
    skip = false;
    console.log(`::warning title=recent-sweep::${escapeCommand(error?.message ?? error)}; the sweep runs`);
  } finally {
    appendFileSync(env.GITHUB_OUTPUT, `skip=${skip}\n`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
