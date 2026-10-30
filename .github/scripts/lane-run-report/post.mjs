// The report jobs of pr-run-activity-read.yml and -write.yml: one comment per
// lane run on the pull request, naming the activity, its outcome, the commits
// it pushed and each GitHub API call that failed, edited in place when the
// run is re-run. The marker names the activity and the run id, not the
// attempt. No model runs here, but the run job that carried the failure rows
// shared RUNNER_TEMP with one, so every row is checked again, and a forged
// outcome or commit renders as unknown or none. A failure to post warns and
// never fails the job.
//
// Env: LANE, ACTIVITY, RUN_ID, PULL, REPOSITORY, GITHUB_SERVER_URL,
// RUN_RESULT, ACT_OUTCOME, PUSHED_COMMIT, READ_LANE, API_FAILURES (the run
// job's api-failures output), GITHUB_TOKEN (issues: write).
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { upsert } from "../lib/upsert-comment.mjs";

export const MAX_ROWS = 50;
const METHODS = new Set(["GET", "POST", "PATCH", "PUT", "DELETE"]);
const PATH = /^\/[A-Za-z0-9/_.-]{1,200}$/;
const NAME = /^[a-z0-9][a-z0-9-]{0,63}$/;
const OUTCOME = /^[a-z_-]{1,32}$/;

export const marker = ({ lane, activity, runId }) => `<!-- lane-run-report activity=${lane}/${activity} run=${runId} -->`;

const validRow = (row) =>
  row !== null &&
  typeof row === "object" &&
  METHODS.has(row.method) &&
  typeof row.path === "string" &&
  PATH.test(row.path) &&
  Number.isInteger(row.status) &&
  row.status >= 0 &&
  row.status <= 599;

// The carried rows that have the recorded shape, each distinct row once, at
// most MAX_ROWS; dropped counts the rest and the run job's own dropped count.
export function failureRows(text) {
  let carried;
  try {
    carried = JSON.parse(text ?? "");
  } catch {
    return { rows: [], dropped: 0 };
  }
  const given = Array.isArray(carried?.rows) ? carried.rows : [];
  const before = Number.isSafeInteger(carried?.dropped) && carried.dropped >= 0 ? carried.dropped : 0;
  const seen = new Set();
  const rows = [];
  for (const row of given) {
    if (!validRow(row)) continue;
    const key = `${row.method} ${row.path} ${row.status}`;
    if (seen.has(key) || rows.length >= MAX_ROWS) continue;
    seen.add(key);
    rows.push({ method: row.method, path: row.path, status: row.status });
  }
  return { rows, dropped: before + given.length - rows.length };
}

const ENTITIES = { "&": "&amp;", "<": "&lt;", ">": "&gt;" };
export const escapeCell = (value) => String(value).replace(/[&<>|`*_[\]\\~]/g, (c) => ENTITIES[c] ?? `&#${c.codePointAt(0)};`);

const outcome = (value) => (OUTCOME.test(value ?? "") ? value : "unknown");

export function render({ lane, activity, runId, runUrl, runResult, actOutcome, commit, readLane, failures }) {
  const commits = readLane ? "none (read lane)" : /^[0-9a-f]{40}$/.test(commit ?? "") ? commit : "none recorded";
  const lines = [
    marker({ lane, activity, runId }),
    "## Lane run report",
    "",
    "| Field | Value |",
    "| --- | --- |",
    `| Activity | ${escapeCell(`${lane}/${activity}`)} |`,
    `| Run job | ${escapeCell(outcome(runResult))} |`,
    `| Activity step | ${escapeCell(outcome(actOutcome))} |`,
    `| Commits pushed | ${escapeCell(commits)} |`,
  ];
  if (runUrl) lines.push(`| Run | [${escapeCell(runId)}](${runUrl}) |`);
  lines.push("", "### Failed GitHub API calls", "");
  if (failures.rows.length === 0) {
    lines.push("No GitHub API call failed.");
  } else {
    lines.push("| Method | Path | Status |", "| --- | --- | --- |");
    for (const row of failures.rows) lines.push(`| ${escapeCell(row.method)} | ${escapeCell(row.path)} | ${escapeCell(row.status === 0 ? "0 (network)" : row.status)} |`);
  }
  if (failures.dropped > 0) lines.push("", `${failures.dropped} more not shown: repeated, malformed, or past the cap of ${MAX_ROWS}.`);
  return `${lines.join("\n")}\n`;
}

export async function main(env = process.env, { github } = {}) {
  if (!/^[1-9][0-9]*$/.test(env.PULL ?? "")) {
    console.log("::notice::no pull request to put the lane run report on");
    return 0;
  }
  if (!NAME.test(env.LANE ?? "") || !NAME.test(env.ACTIVITY ?? "") || !/^[1-9][0-9]{0,19}$/.test(env.RUN_ID ?? "") || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.REPOSITORY ?? "")) {
    console.log("::warning::the lane, activity, run id or repository is not of its shape; no lane run report is posted");
    return 0;
  }
  const server = /^https:\/\/[A-Za-z0-9.-]+$/.test(env.GITHUB_SERVER_URL ?? "") ? env.GITHUB_SERVER_URL : "";
  const args = { lane: env.LANE, activity: env.ACTIVITY, runId: env.RUN_ID };
  const body = render({
    ...args,
    runUrl: server && `${server}/${env.REPOSITORY}/actions/runs/${env.RUN_ID}`,
    runResult: env.RUN_RESULT,
    actOutcome: env.ACT_OUTCOME,
    commit: env.PUSHED_COMMIT,
    readLane: env.READ_LANE === "true",
    failures: failureRows(env.API_FAILURES),
  });
  try {
    const client = github ?? createGitHub({ token: env.GITHUB_TOKEN });
    const done = await upsert({ github: client, repository: env.REPOSITORY, pull: env.PULL, marker: marker(args), body });
    console.log(`::notice::${done} the lane run report on #${env.PULL}`);
  } catch (error) {
    console.log(`::warning::could not post the lane run report on #${env.PULL}: ${error?.message ?? error}`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
