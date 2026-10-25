// failing-checks.mjs <run id> <attempt> [--baseline]: the checks one attempt
// of a full run failed, one per line, as post-merge-demotion-alert.yml's alert
// step judges them: red-main.mjs failingChecks with ALERT_FAILED. --baseline
// leaves out a job counted only because its steps were unknown. Reads through
// `gh api` with the step's GH_TOKEN; a failed read exits non-zero, which fails
// the step, as the reads it replaced did.
//
// Environment: GITHUB_REPOSITORY, GH_TOKEN.
import { execFileSync } from "node:child_process";
import { realpathSync } from "node:fs";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { ALERT_FAILED, failingChecks } from "./red-main.mjs";

// `gh api` with a filter that prints one JSON value per line.
const ghLines = (args) =>
  execFileSync("gh", ["api", ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] })
    .split("\n")
    .filter((line) => line.trim() !== "")
    .map((line) => JSON.parse(line));

export function attemptFailingChecks(repo, runId, attempt, { baseline = false, api = ghLines } = {}) {
  const jobs = api(["--paginate", `repos/${repo}/actions/runs/${runId}/attempts/${attempt}/jobs?per_page=100`, "--jq", ".jobs[] | @json"]);
  const annotations = {};
  for (const job of jobs.filter((j) => ALERT_FAILED.includes(j.conclusion))) {
    annotations[job.id] = api([`repos/${repo}/check-runs/${job.id}/annotations?per_page=100`, "--jq", ".[] | @json"]);
  }
  return failingChecks(jobs, annotations, { failed: ALERT_FAILED, baseline, noFailedJobs: true });
}

function main(argv = process.argv.slice(2), env = process.env) {
  const [runId, attempt, flag, ...rest] = argv;
  if (!/^[1-9][0-9]{0,14}$/.test(runId ?? "") || !/^[1-9][0-9]*$/.test(attempt ?? "") || ![undefined, "--baseline"].includes(flag) || rest.length > 0) {
    throw new Error("usage: failing-checks.mjs <run id> <attempt> [--baseline]");
  }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
    throw new Error("GITHUB_REPOSITORY is not owner/repo");
  }
  const checks = attemptFailingChecks(env.GITHUB_REPOSITORY, runId, attempt, { baseline: flag === "--baseline" });
  if (checks.length > 0) process.stdout.write(`${checks.join("\n")}\n`);
}

// Real paths on both sides: run through a symlink, a plain comparison would
// skip main and print no check, which the step reads as nothing failing.
const invoked = process.argv[1] ? pathToFileURL(realpathSync(process.argv[1])).href : "";
if (pathToFileURL(realpathSync(fileURLToPath(import.meta.url))).href === invoked) {
  try {
    main();
  } catch (error) {
    console.error(`::error::failing-checks: ${error.message}`);
    process.exitCode = 1;
  }
}
