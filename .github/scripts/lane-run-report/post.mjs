// The report jobs of pr-run-activity-read.yml and -write.yml: one comment per
// lane run on the pull request, naming the activity, its outcome, the commits
// it pushed and each GitHub API call that failed, edited in place when the
// run is re-run. The marker names the activity, the run id, the model rung
// and the leg (pr-unblock calls the read runner more than once per run: its
// rung-up call at rung 1, and each call's subscription and fallback legs with
// the runner's fallback input), not the attempt; a first attempt posts
// without a lookup. No model runs here, but the run job that carried the failure rows
// shared RUNNER_TEMP with one, so every row is checked again, and a forged
// outcome or commit renders as unknown or none, and no count the run job
// carried is shown. A failure to post warns and
// never fails the job.
//
// Env: LANE, ACTIVITY, RUN_ID, GITHUB_RUN_ATTEMPT, MODEL_RUNG, LEG (the read
// runner's fallback input; empty for the write runner), PULL, REPOSITORY, GITHUB_SERVER_URL,
// RUN_RESULT, ACT_OUTCOME, PUSHED_COMMIT, READ_LANE, API_FAILURES (the run
// job's api-failures output), GITHUB_TOKEN (issues: write).
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { REST_PATH_WORDS } from "../../actions/log-api-budget/rate-guard.mjs";
import { upsert } from "../lib/upsert-comment.mjs";

export const MAX_ROWS = 50;
const METHODS = new Set(["GET", "POST", "PATCH", "PUT", "DELETE"]);
const PATH = /^\/[A-Za-z0-9/_.-]{1,200}$/;
const NAME = /^[a-z0-9][a-z0-9-]{0,63}$/;
const OUTCOMES = new Set(["success", "failure", "cancelled", "skipped"]);

// The read runner's fallback input to the leg named in the marker; the first
// call's empty value is base.
const LEGS = new Map([
  ["", "base"],
  ["handoff", "handoff"],
  ["credit-stop", "credit-stop"],
  ["no-key", "no-key"],
  ["fallback", "fallback"],
]);

export const marker = ({ lane, activity, runId, rung = "0", leg = "base" }) => `<!-- lane-run-report activity=${lane}/${activity} run=${runId} rung=${rung} leg=${leg} -->`;

// Only GitHub REST path words (REST_PATH_WORDS) may appear in the comment.
// The model shares RUNNER_TEMP, so any other segment could be planted text (a
// key split across rows): it renders as *, and the owner/name pair after
// repos as {repo}.
const WORDS = REST_PATH_WORDS;
export function templatePath(path) {
  const parts = path.split("/").slice(1);
  const out = [];
  for (let i = 0; i < parts.length; i++) {
    if (parts[i] === "repos" && i + 2 < parts.length) {
      out.push("repos", "{repo}");
      i += 2;
    } else {
      out.push(WORDS.has(parts[i]) ? parts[i] : "*");
    }
  }
  return `/${out.join("/")}`;
}

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
// most MAX_ROWS, each path as its template (templatePath); dropped counts the rest and the run job's own dropped count.
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
    const path = templatePath(row.path);
    const key = `${row.method} ${path} ${row.status}`;
    if (seen.has(key) || rows.length >= MAX_ROWS) continue;
    seen.add(key);
    rows.push({ method: row.method, path, status: row.status });
  }
  return { rows, dropped: before + given.length - rows.length };
}

const ENTITIES = { "&": "&amp;", "<": "&lt;", ">": "&gt;" };
export const escapeCell = (value) => String(value).replace(/[&<>|`*_[\]\\~]/g, (c) => ENTITIES[c] ?? `&#${c.codePointAt(0)};`);

const outcome = (value) => (OUTCOMES.has(value) ? value : "unknown");

export function render({ lane, activity, runId, rung = "0", leg, runUrl, runResult, actOutcome, commit, readLane, failures }) {
  const commits = readLane ? "none (read lane)" : /^[0-9a-f]{40}$/.test(commit ?? "") ? commit : "none recorded";
  const lines = [
    marker({ lane, activity, runId, rung, leg }),
    "## Lane run report",
    "",
    "| Field | Value |",
    "| --- | --- |",
    `| Activity | ${escapeCell(`${lane}/${activity}`)} |`,
    `| Model rung | ${rung === "1" ? "1" : "0"} |`,
    `| Leg | ${leg ?? "base"} |`,
    `| Run job | ${escapeCell(outcome(runResult))} |`,
    `| Activity step | ${escapeCell(outcome(actOutcome))} |`,
    `| Commits pushed | ${escapeCell(commits)} |`,
  ];
  if (runUrl) lines.push(`| Run | [${escapeCell(runId)}](${runUrl}) |`);
  lines.push("", "### Failed GitHub API calls", "");
  if (failures.rows.length === 0) {
    lines.push("No failed call recorded by the run job's scripts.");
  } else {
    lines.push("| Method | Path | Status |", "| --- | --- | --- |");
    for (const row of failures.rows) lines.push(`| ${escapeCell(row.method)} | ${escapeCell(row.path)} | ${escapeCell(row.status === 0 ? "0 (network)" : row.status)} |`);
  }
  if (failures.dropped > 0) lines.push("", `More rows not shown: repeated, malformed, or past the cap of ${MAX_ROWS}.`);
  return `${lines.join("\n")}\n`;
}

export async function main(env = process.env, { github } = {}) {
  if (!/^[1-9][0-9]*$/.test(env.PULL ?? "")) {
    console.log("::notice::no pull request to put the lane run report on");
    return 0;
  }
  if (!NAME.test(env.LANE ?? "") || !NAME.test(env.ACTIVITY ?? "") || !/^[1-9][0-9]{0,19}$/.test(env.RUN_ID ?? "") || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.REPOSITORY ?? "") || !/^[01]?$/.test(env.MODEL_RUNG ?? "") || !LEGS.has(env.LEG ?? "")) {
    console.log("::warning::the lane, activity, run id, model rung, leg or repository is not of its shape; no lane run report is posted");
    return 0;
  }
  const server = /^https:\/\/[A-Za-z0-9.-]+$/.test(env.GITHUB_SERVER_URL ?? "") ? env.GITHUB_SERVER_URL : "";
  const args = { lane: env.LANE, activity: env.ACTIVITY, runId: env.RUN_ID, rung: env.MODEL_RUNG || "0", leg: LEGS.get(env.LEG ?? "") };
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
    // A first attempt's run id is new, so no comment can carry its marker yet.
    let done = "posted";
    if (env.GITHUB_RUN_ATTEMPT === "1") await client("POST", `/repos/${env.REPOSITORY}/issues/${env.PULL}/comments`, { body });
    else done = await upsert({ github: client, repository: env.REPOSITORY, pull: env.PULL, marker: marker(args), body });
    console.log(`::notice::${done} the lane run report on #${env.PULL}`);
  } catch (error) {
    console.log(`::warning::could not post the lane run report on #${env.PULL}: ${error?.message ?? error}`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
