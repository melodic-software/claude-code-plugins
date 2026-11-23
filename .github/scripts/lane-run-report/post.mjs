// The report jobs of pr-run-activity-read.yml and -write.yml. A report job
// whose run did not succeed or recorded a failed GitHub API call puts its
// section in one comment per workflow run on the pull request (the
// lane-run-report kind of lib/pr-messages): the activity's outcome, the
// commits it pushed and each GitHub API call that failed. A clean report job
// writes its report to the job summary only. No model runs here, but the run
// job that carried the failure rows shared RUNNER_TEMP with one, so every row
// is checked again, a forged outcome or commit renders as unknown or none,
// and no count the run job carried is shown. A secondary rate limit's refusal is retried once after its
// retry-after (a minute when absent, when it is at most MAX_WAIT_SECONDS,
// https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#about-secondary-rate-limits).
// A failure to post warns with GitHub's answer, writes the report to the job
// summary instead, and never fails the job.
//
// Env: LANE, ACTIVITY, RUN_ID, GITHUB_RUN_ATTEMPT, MODEL_RUNG, LEG (the read
// runner's fallback input; empty for the write runner), PULL, REPOSITORY, GITHUB_SERVER_URL,
// RUN_RESULT, ACT_OUTCOME, PUSHED_COMMIT, READ_LANE, API_FAILURES (the run
// job's api-failures output), GITHUB_TOKEN (pull-requests: write), GITHUB_STEP_SUMMARY.
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, detailSuffix } from "../lib/github-client.mjs";
import { createRateLimitLatch, REST_PATH_WORDS, SIGNALS } from "../../actions/log-api-budget/rate-guard.mjs";
import { prMessages, sectionHeading } from "../lib/pr-messages/pr-messages.mjs";
import { graphqlStore } from "../lib/pr-messages/stores.mjs";

export const MAX_ROWS = 50;
export const MAX_BODY = 60000;
export const LIST_TIMEOUT_MS = 5000;
export const LATCH_BUDGET_MS = 5000;
const KIND = "lane-run-report";
const METHODS = new Set(["GET", "POST", "PATCH", "PUT", "DELETE"]);
const PATH = /^\/[A-Za-z0-9/_.-]{1,200}$/;
const TEMPLATED = /^\/[A-Za-z0-9/_.{}*-]{1,200}$/;
const NAME = /^[a-z0-9][a-z0-9-]{0,63}$/;
const OUTCOMES = new Set(["success", "failure", "cancelled", "skipped"]);
const COMMITS = /^(?:[0-9a-f]{40}|none \(read lane\)|none recorded)$/;
// Well inside the report job's 10-minute timeout.
export const MAX_WAIT_SECONDS = 300;

// The seconds to wait before one more try when GitHub's refusal is a secondary
// rate limit (a 403 or 429 naming it, or carrying retry-after, with primary
// quota left), else undefined. The client's rate latch stops every call until
// that time (rate-guard.mjs SIGNALS, the minute when no time is given), so a
// wait past MAX_WAIT_SECONDS is not taken: its retry could never be sent. A
// primary limit's reset can be an hour away.
export function secondaryWait(error) {
  const detail = typeof error?.detail === "string" ? error.detail : "";
  if (!SIGNALS.statuses.includes(error?.status) || /x-ratelimit-remaining=0\b/.test(detail)) return undefined;
  const after = /retry-after=([0-9]{1,6})\b/.exec(detail);
  if (!after && !SIGNALS.secondary.test(detail)) return undefined;
  const wait = after ? Number(after[1]) : SIGNALS.fallbackSeconds;
  return wait <= MAX_WAIT_SECONDS ? wait : undefined;
}

const LEGS = new Map([["", "base"], ...["handoff", "credit-stop", "no-key", "fallback"].map((leg) => [leg, leg])]);

// Only GitHub REST path words (REST_PATH_WORDS) may appear in the comment.
// The model shares RUNNER_TEMP, so any other segment could be planted text (a
// key split across rows): it renders as *, and the owner/name pair after
// repos as {repo}.
export function templatePath(path) {
  const parts = path.split("/").slice(1);
  const out = [];
  for (let i = 0; i < parts.length; i++) {
    if (parts[i] === "repos" && i + 2 < parts.length) {
      out.push("repos", "{repo}");
      i += 2;
    } else {
      out.push(REST_PATH_WORDS.has(parts[i]) ? parts[i] : "*");
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

// A 404 on a tag-ref lookup means the tag does not exist yet
// (check-trusted-trigger.mjs readDefaultBranchTip), not a failure, so
// failureRows neither lists it nor counts it as dropped:
// https://docs.github.com/en/rest/git/refs#get-a-reference
const TAG_REF = /^(\/api\/v3)?\/repos\/\{repo\}\/git\/ref\/tags(\/\*)+$/;
const expectedMiss = (row) => row.method === "GET" && row.status === 404 && TAG_REF.test(row.path);

function foldRows(candidates, before = 0) {
  const seen = new Set();
  const rows = [];
  let skipped = 0;
  for (const row of candidates) {
    const key = `${row.method} ${row.path} ${row.status}`;
    if (seen.has(key) || rows.length >= MAX_ROWS) {
      skipped += 1;
      continue;
    }
    seen.add(key);
    rows.push(row);
  }
  return { rows, dropped: before + skipped };
}

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
  const shaped = given.filter(validRow).map((row) => ({ method: row.method, path: templatePath(row.path), status: row.status }));
  const kept = shaped.filter((row) => !expectedMiss(row));
  const folded = foldRows(kept);
  return { rows: folded.rows, dropped: before + given.length - shaped.length + folded.dropped };
}

const ENTITIES = { "&": "&amp;", "<": "&lt;", ">": "&gt;" };
export const escapeCell = (value) => String(value).replace(/[&<>|`*_[\]\\~]/g, (c) => ENTITIES[c] ?? `&#${c.codePointAt(0)};`);
const NAMED = { "&amp;": "&", "&lt;": "<", "&gt;": ">" };
const unescapeCell = (value) => value.replace(/&(?:#([0-9]{1,7})|amp|lt|gt);/g, (entity, code) => (code ? String.fromCodePoint(Number(code)) : NAMED[entity]));

const outcome = (value) => (OUTCOMES.has(value) ? value : "unknown");

export function reportOf({ activity, attempt, rung = "0", leg = "base", runResult, actOutcome, commit, readLane, failures }) {
  return {
    fields: { activity, attempt, rung: rung === "1" ? "1" : "0", leg },
    runResult: outcome(runResult),
    actOutcome: outcome(actOutcome),
    commits: readLane ? "none (read lane)" : /^[0-9a-f]{40}$/.test(commit ?? "") ? commit : "none recorded",
    failures,
  };
}

const CLEAN = new Set(["success", "skipped"]);

export const failed = (section) =>
  !CLEAN.has(section.runResult) || !CLEAN.has(section.actOutcome) || section.failures.rows.length > 0 || section.failures.dropped > 0;

export function renderSection(section) {
  const { activity, attempt, rung, leg } = section.fields;
  const lines = [
    sectionHeading(KIND, section.fields),
    `### ${escapeCell(activity)}, attempt ${attempt}`,
    "",
    "| Field | Value |",
    "| --- | --- |",
    `| Model rung | ${rung} |`,
    `| Leg | ${leg} |`,
    `| Run job | ${escapeCell(section.runResult)} |`,
    `| Activity step | ${escapeCell(section.actOutcome)} |`,
    `| Commits pushed | ${escapeCell(section.commits)} |`,
  ];
  lines.push("", "#### Failed GitHub API calls", "");
  const { rows, dropped } = section.failures;
  if (rows.length === 0) {
    lines.push("No failed call recorded by the run job's scripts.");
  } else {
    lines.push("| Method | Path | Status |", "| --- | --- | --- |");
    for (const row of rows) lines.push(`| ${escapeCell(row.method)} | ${escapeCell(row.path)} | ${escapeCell(row.status === 0 ? "0 (network)" : row.status)} |`);
  }
  if (dropped > 0) lines.push("", `More rows not shown: repeated, malformed, past the cap of ${MAX_ROWS}, or trimmed to keep the comment short.`);
  return `${lines.join("\n")}\n`;
}

const ROW = /^\| (GET|POST|PATCH|PUT|DELETE) \| (\S{1,1400}) \| (0 \(network\)|[1-9][0-9]{0,2}) \|$/;
const cell = (text, name) => new RegExp(`^\\| ${name} \\| (.{1,200}) \\|$`, "m").exec(text)?.[1] ?? "";

export function parseSection({ fields, text }) {
  const candidates = [];
  let rejected = 0;
  for (const line of text.split("\n")) {
    const m = ROW.exec(line);
    if (!m) continue;
    const path = unescapeCell(m[2]);
    const status = m[3] === "0 (network)" ? 0 : Number(m[3]);
    if (!TEMPLATED.test(path) || templatePath(path.replaceAll("{repo}", "o/r")) !== path || status > 599) {
      rejected += 1;
      continue;
    }
    candidates.push({ method: m[1], path, status });
  }
  const folded = foldRows(candidates, rejected);
  const commits = unescapeCell(cell(text, "Commits pushed"));
  return {
    fields,
    runResult: outcome(cell(text, "Run job")),
    actOutcome: outcome(cell(text, "Activity step")),
    commits: COMMITS.test(commits) ? commits : "none recorded",
    failures: { rows: folded.rows, dropped: /^More rows not shown/m.test(text) ? Math.max(folded.dropped, 1) : folded.dropped },
  };
}

const NOTE = /^Not shown, to keep this comment under 60,000 characters: ([0-9]{1,9}) failure rows and ([0-9]{1,9}) sections\.$/m;

export function merge(kept, mine) {
  const { activity, rung, leg } = mine.fields;
  const attempt = Number(mine.fields.attempt);
  let at = -1;
  kept.forEach((s, i) => {
    if (s.fields.activity !== activity || s.fields.rung !== rung || s.fields.leg !== leg || Number(s.fields.attempt) >= attempt) return;
    if (at === -1 || Number(s.fields.attempt) >= Number(kept[at].fields.attempt)) at = i;
  });
  return at === -1 ? { sections: [...kept, mine], own: kept.length } : { sections: kept.with(at, mine), own: at };
}

export function renderBody({ run, sections, own, runUrlOf, cut = { rows: 0, sections: 0 } }) {
  const list = [...sections];
  const texts = list.map(renderSection);
  let mine = own;
  let rowsCut = cut.rows;
  let sectionsCut = cut.sections;
  const head = () => {
    const runUrl = runUrlOf(run);
    const lines = ["## Lane run report", "", "| Field | Value |", "| --- | --- |", `| Run | ${runUrl ? `[${run}](${runUrl})` : run} |`, ""];
    if (rowsCut + sectionsCut > 0) lines.push(`Not shown, to keep this comment under 60,000 characters: ${rowsCut} failure rows and ${sectionsCut} sections.`, "");
    return `${lines.join("\n")}\n`;
  };
  const size = () => head().length + texts.reduce((n, t) => n + t.length + 1, 0);
  for (let i = 0; size() > MAX_BODY && i < list.length; i++) {
    if (i === mine || list[i].failures.rows.length === 0) continue;
    rowsCut += list[i].failures.rows.length;
    list[i] = { ...list[i], failures: { rows: [], dropped: Math.max(list[i].failures.dropped, 1) } };
    texts[i] = renderSection(list[i]);
  }
  while (size() > MAX_BODY && list.length > 1) {
    const oldest = mine === 0 ? 1 : 0;
    list.splice(oldest, 1);
    texts.splice(oldest, 1);
    sectionsCut += 1;
    if (oldest < mine) mine -= 1;
  }
  return `${head()}${texts.join("\n")}`;
}

const causeOf = (error) => error?.cause ?? error;

export async function main(env = process.env, { github, store, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)), listTimeoutMs = LIST_TIMEOUT_MS } = {}) {
  if (!/^[1-9][0-9]*$/.test(env.PULL ?? "")) {
    console.log("::notice::no pull request to put the lane run report on");
    return 0;
  }
  if (
    !NAME.test(env.LANE ?? "") ||
    !NAME.test(env.ACTIVITY ?? "") ||
    !/^[1-9][0-9]{0,19}$/.test(env.RUN_ID ?? "") ||
    !/^[1-9][0-9]{0,4}$/.test(env.GITHUB_RUN_ATTEMPT ?? "") ||
    !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.REPOSITORY ?? "") ||
    !/^[01]?$/.test(env.MODEL_RUNG ?? "") ||
    !LEGS.has(env.LEG ?? "")
  ) {
    console.log("::warning::the lane, activity, run id, run attempt, model rung, leg or repository is not of its shape; no lane run report is posted");
    return 0;
  }
  const server = /^https:\/\/[A-Za-z0-9.-]+$/.test(env.GITHUB_SERVER_URL ?? "") ? env.GITHUB_SERVER_URL : "";
  const runUrlOf = (run) => (server ? `${server}/${env.REPOSITORY}/actions/runs/${run}` : "");
  const activity = `${env.LANE}/${env.ACTIVITY}`;
  const mine = reportOf({
    activity,
    attempt: env.GITHUB_RUN_ATTEMPT,
    rung: env.MODEL_RUNG || "0",
    leg: LEGS.get(env.LEG ?? ""),
    runResult: env.RUN_RESULT,
    actOutcome: env.ACT_OUTCOME,
    commit: env.PUSHED_COMMIT,
    readLane: env.READ_LANE === "true",
    failures: failureRows(env.API_FAILURES),
  });
  const alone = renderBody({ run: env.RUN_ID, sections: [mine], own: 0, runUrlOf });
  const toSummary = () => {
    try {
      if (!env.GITHUB_STEP_SUMMARY) return "";
      appendFileSync(env.GITHUB_STEP_SUMMARY, alone);
      return "; the report is in this job's summary";
    } catch {
      return "";
    }
  };
  if (!failed(mine)) {
    console.log(`::notice::${activity} succeeded with no failed GitHub API call, so no lane run report comment is posted${toSummary()}`);
    return 0;
  }
  try {
    const client = store ? undefined : (github ?? createGitHub({ token: env.GITHUB_TOKEN, latch: createRateLimitLatch({ budgetMs: LATCH_BUDGET_MS, hold: true }) }));
    const post = async () => {
      const thread = prMessages({ store: store ?? graphqlStore(client, { timeoutMs: listTimeoutMs }), repo: env.REPOSITORY, number: Number(env.PULL) });
      const current = await thread.read(KIND, { run: env.RUN_ID });
      const merged = merge((current?.sections ?? []).map(parseSection), mine);
      const note = NOTE.exec(current?.preamble ?? "");
      const cut = note ? { rows: Number(note[1]), sections: Number(note[2]) } : undefined;
      return thread.write(KIND, { run: env.RUN_ID }, {}, renderBody({ run: env.RUN_ID, ...merged, runUrlOf, cut }));
    };
    let done;
    try {
      done = await post();
    } catch (error) {
      const wait = secondaryWait(causeOf(error));
      if (wait === undefined) throw error;
      console.log(`::notice::GitHub's secondary rate limit refused the lane run report on #${env.PULL}${detailSuffix(causeOf(error))}; trying once more in ${wait}s`);
      await sleep(wait * 1000);
      done = await post();
    }
    console.log(`::notice::${done === "unchanged" ? "left unchanged" : done} the lane run report on #${env.PULL}`);
  } catch (error) {
    console.log(`::warning::could not post the lane run report on #${env.PULL}: ${error?.message ?? error}${detailSuffix(causeOf(error))}${toSummary()}`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
