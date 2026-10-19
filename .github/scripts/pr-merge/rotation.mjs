#!/usr/bin/env node
// rotation.mjs: orders a pr-merge `merge` job's candidates so its gate loop
// starts after the last candidate the previous gate loop reached, wrapping
// round to the lowest PR number. Under merge.gate-budget-minutes a loop can
// stop before the end of the list; starting where the last one stopped means
// every candidate is reached across runs.
//
// The previous position is the `pr-merge-gate-cursor` artifact each gate loop
// uploads, `{"last": <PR number>}`. Only the newest one from a pr-merge.yml run
// that ran main's copy of this workflow counts: a scheduled or hand-started run
// on main, or a pull_request_target run, which always runs main's copy. The
// cursor sets only the order, never a verdict. Any failure leaves the listing
// order (ascending PR number) and warns.
//
// Environment:
//   ACTIONS_TOKEN        the job's GITHUB_TOKEN (actions: read)
//   GITHUB_REPOSITORY    owner/repo
//   CANDIDATES_PATH      candidates.json, rewritten in rotated order
//   RUNNER_TEMP          where the cursor artifact is downloaded
//   GITHUB_OUTPUT        receives last=<PR number> or last=
//   GITHUB_API_URL
import { execFileSync } from "node:child_process";
import { appendFileSync, mkdtempSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const CURSOR_ARTIFACT = "pr-merge-gate-cursor";
const WORKFLOW_PATH = ".github/workflows/pr-merge.yml";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
// Artifacts read before giving up on finding a trusted cursor.
const MAX_ARTIFACTS = 5;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// Ascending by PR number, starting at the first number above `last`.
export function rotate(candidates, last) {
  const sorted = [...candidates].sort((a, b) => a.number - b.number);
  const start = Number.isInteger(last) ? sorted.findIndex((c) => c.number > last) : -1;
  return start <= 0 ? sorted : [...sorted.slice(start), ...sorted.slice(0, start)];
}

// A run of main's copy of pr-merge.yml.
export function trustedRun(run) {
  return (
    run?.path === WORKFLOW_PATH &&
    (run.event === "pull_request_target" ||
      ((run.event === "schedule" || run.event === "workflow_dispatch") && run.head_branch === "main"))
  );
}

function ghDownload({ repo, token, dir }) {
  return (runId) => {
    const target = mkdtempSync(join(dir, "gate-cursor-"));
    execFileSync("gh", ["run", "download", String(runId), "-R", repo, "-n", CURSOR_ARTIFACT, "-D", target], {
      env: { ...process.env, GH_TOKEN: token },
      stdio: ["ignore", "ignore", "inherit"],
    });
    return readFileSync(join(target, "cursor.json"), "utf8");
  };
}

// The newest trusted cursor's PR number, or undefined when there is none.
export async function readCursor({ repo, actions, download }) {
  const listing = await actions("GET", `/repos/${repo}/actions/artifacts?name=${CURSOR_ARTIFACT}&per_page=${MAX_ARTIFACTS}`);
  if (!Array.isArray(listing?.artifacts)) {
    throw new Error("the cursor artifact listing has an unexpected shape");
  }
  const newest = listing.artifacts
    .filter((a) => a?.expired === false && Number.isInteger(a.workflow_run?.id))
    .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))
    .slice(0, MAX_ARTIFACTS);
  for (const artifact of newest) {
    const run = await actions("GET", `/repos/${repo}/actions/runs/${artifact.workflow_run.id}`);
    if (!trustedRun(run)) {
      continue;
    }
    const last = JSON.parse(download(artifact.workflow_run.id))?.last;
    if (!Number.isInteger(last) || last < 1) {
      throw new Error(`the cursor of run ${artifact.workflow_run.id} is not a PR number`);
    }
    return last;
  }
  return undefined;
}

export async function main({ env = process.env, actions, download } = {}) {
  let last;
  try {
    const repo = env.GITHUB_REPOSITORY ?? "";
    if (!REPO.test(repo)) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const path = env.CANDIDATES_PATH;
    const candidates = JSON.parse(readFileSync(path, "utf8"));
    if (!Array.isArray(candidates) || !candidates.every((c) => Number.isInteger(c?.number))) {
      throw new Error("candidates.json is not a list of PRs");
    }
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP });
    last = await readCursor({ repo, actions, download });
    const ordered = rotate(candidates, last);
    writeFileSync(`${path}.tmp`, JSON.stringify(ordered));
    renameSync(`${path}.tmp`, path);
    const first = ordered[0]?.number;
    console.log(
      last === undefined
        ? "no earlier gate cursor; the gate starts at the lowest PR number"
        : `the last run's gate reached #${last}; this run starts at ${first === undefined ? "no candidate" : `#${first}`}`,
    );
  } catch (error) {
    last = undefined;
    console.log(`::warning title=rotation::${escapeCommand(error?.message ?? error)}; the gate runs in listing order`);
  }
  appendFileSync(env.GITHUB_OUTPUT, `last=${last ?? ""}\n`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
