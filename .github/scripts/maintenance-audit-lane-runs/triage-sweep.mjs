// The hourly triage sweep: finds open issues intake triage never reached and
// dispatches intake-triage.yml for them, with the job's own token only. An
// issue qualifies when it has no intake comment and no triage or status
// label, is no pull request, was not born triaged, is over an hour old, and
// its author is a listed human or the lanes App, as the intake lane admits on
// open. The needs-triage floor label is no triage label: it lands on open
// whether or not intake runs, so an issue whose intake run failed still
// qualifies. github-actions[bot] issues are left out: the lane sweep's can
// quote fork-controlled log lines. Per issue, one comment holds the runs
// dispatched; after 2 that left it untriaged the sweep files one needs-triage
// issue and labels the original needs-triage. No model.
//
// Accepted exposure: intake reads an issue's comments, and anyone can comment
// in the hour before the sweep dispatches. Intake treats them as untrusted
// data and applies only allowlisted labels, never agent-ready.
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { BORN_TRIAGED_MARKER, humanIds } from "../../actions/check-born-triaged/check-born-triaged.mjs";
import { createBudget } from "./collect.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";

// Every GitHub call goes through the rate guard (rate-guard.mjs); the fetch
// is read at call time, so a test's stub is guarded too.
const guardedFetch = (url, init) => rateLimitLatch.guard(globalThis.fetch)(url, init);

export const MAX_DISPATCHES = 5;
const MAX_FILED = 5;
const MAX_CHECKED = 20;
const MAX_ISSUE_PAGES = 15;
const COMMENT_PAGES = 3;
const ATTEMPTS = 2;
const MIN_AGE_MS = 3_600_000;
const BOT = "github-actions[bot]";
const INTAKE_MARKER = "<!-- claude-lane intake-triage -->";
// `filed` holds the filed issue's number, or FILING while the filing is under way.
export const FILING = "?";
const STATE = /^<!-- claude-lane triage-sweep runs=([0-9,]*) filed=([0-9]*|\?) -->/;
const FLOOR = "needs-triage";
// Labels intake triage or a person applies once an issue is triaged.
const TRIAGED = /^(needs-human|needs-spec|agent-ready)$|^(status|priority|work-class): /;

export function selectCandidates({ issues, now, authorIds }) {
  return issues
    .filter(
      (i) =>
        !i.pull_request &&
        authorIds.has(String(i.user?.id)) &&
        !(i.labels ?? []).some((l) => TRIAGED.test(l.name ?? "")) &&
        !String(i.body ?? "")
          .trimEnd()
          .endsWith(BORN_TRIAGED_MARKER) &&
        now - new Date(i.created_at) >= MIN_AGE_MS,
    )
    .sort((a, b) => new Date(a.created_at) - new Date(b.created_at) || a.number - b.number);
}

// The intake lane's own lookup for its earlier comment.
export const hasIntakeComment = (comments) =>
  comments.some((c) => c.user?.login === BOT && String(c.body ?? "").startsWith(INTAKE_MARKER));

export function readState(comments) {
  for (const c of comments) {
    const m = c.user?.login === BOT ? STATE.exec(String(c.body ?? "")) : null;
    if (m) {
      return {
        commentId: c.id,
        runs: m[1] ? m[1].split(",").map(Number) : [],
        filed: m[2] === FILING ? FILING : m[2] ? Number(m[2]) : null,
      };
    }
  }
  return { commentId: null, runs: [], filed: null };
}

export const renderState = ({ runs, filed, runUrl }) =>
  `<!-- claude-lane triage-sweep runs=${runs.join(",")} filed=${filed ?? ""} -->\n` +
  (filed === FILING
    ? `Intake triage did not triage this issue after ${runs.length} dispatches; the sweep labeled it needs-triage for a maintainer.`
    : filed
    ? `Intake triage did not triage this issue after ${runs.length} dispatches; #${filed} hands it to a maintainer.`
    : `The triage sweep dispatched [intake triage](${runUrl}) for this issue (attempt ${runs.length} of ${ATTEMPTS}).`);

export function decide({ state, latest }) {
  if (state.filed) return "stop";
  if (state.runs.length === 0) return "dispatch";
  if (latest?.status !== "completed") return "wait";
  return state.runs.length >= ATTEMPTS ? "file" : "dispatch";
}

const FILED_TITLE = /^Intake triage left #([1-9][0-9]*) untriaged after /;
const SEARCH_PAGES = 10;

// The issues the sweep already filed a hand-off for, read from one search of
// its own hand-off issues, open or closed, so their originals cost no comment
// reads. Only a title the bot wrote counts. A failed or incomplete search
// excludes nothing: those issues are then read and skipped by their state.
async function handedOff(call, repo) {
  const q = encodeURIComponent(`repo:${repo} is:issue author:app/github-actions in:title "Intake triage left"`);
  const numbers = new Set();
  try {
    for (let page = 1; page <= SEARCH_PAGES; page += 1) {
      const found = await call("GET", `/search/issues?q=${q}&per_page=100&page=${page}`);
      if (found?.incomplete_results !== false) return new Set();
      for (const item of found.items ?? []) {
        const m = item.user?.login === BOT ? FILED_TITLE.exec(String(item.title ?? "")) : null;
        if (m) numbers.add(Number(m[1]));
      }
      if ((found.items ?? []).length < 100) break;
    }
  } catch (error) {
    if (/call budget/.test(error.message)) throw error;
    return new Set();
  }
  return numbers;
}

export const renderFiledIssue = ({ number, runs, repoUrl }) => ({
  title: `Intake triage left #${number} untriaged after ${runs.length} dispatches`,
  labels: ["needs-triage"],
  body: [
    `The hourly triage sweep dispatched intake triage for #${number} ${runs.length} times, and the issue still has no intake comment. The sweep no longer dispatches it.`,
    "",
    ...runs.map((r) => `- ${repoUrl}/actions/runs/${r.id} (${r.conclusion ?? "unknown"})`),
    "",
    "Triage the issue by hand, and read the runs for why intake did not.",
  ].join("\n"),
});

// One pass. `call` returns null for a GET that 404s.
export async function runSweep({ call, remaining = () => Infinity, repo, serverUrl, now, authorIds }) {
  const repoUrl = `${serverUrl}/${repo}`;
  const issues = [];
  for (let page = 1; page <= MAX_ISSUE_PAGES; page += 1) {
    const batch = await call("GET", `/repos/${repo}/issues?state=open&per_page=100&page=${page}`);
    issues.push(...batch);
    if (batch.length < 100) break;
  }
  const result = { candidates: 0, dispatched: [], filed: [], handedOff: [], waiting: [], failed: [], truncated: null };
  const selected = selectCandidates({ issues, now, authorIds });
  const filed = selected.length > 0 ? await handedOff(call, repo) : new Set();
  const candidates = selected.filter((i) => !filed.has(i.number));
  result.candidates = candidates.length;
  const handOff = (number) => call("POST", `/repos/${repo}/issues/${number}/labels`, { labels: [FLOOR] });
  // Issues intake already commented on, and ones the sweep already handed
  // off, cost their reads and do not count toward MAX_CHECKED, so they cannot
  // starve the issues behind them.
  let checked = 0;
  for (const { number, labels } of candidates) {
    if (checked >= MAX_CHECKED) break;
    if (result.dispatched.length >= MAX_DISPATCHES && result.filed.length >= MAX_FILED) break;
    try {
      const comments = [];
      let full = false;
      for (let page = 1; page <= COMMENT_PAGES; page += 1) {
        const batch = (await call("GET", `/repos/${repo}/issues/${number}/comments?per_page=100&page=${page}`)) ?? [];
        comments.push(...batch);
        full = batch.length === 100;
        if (!full) break;
      }
      if (hasIntakeComment(comments)) continue;
      // Past the pages read, the state comment may be hidden: a person
      // decides, so the label goes on once.
      if (full) {
        if ((labels ?? []).some((l) => l.name === FLOOR)) continue;
        checked += 1;
        await handOff(number);
        result.handedOff.push(number);
        continue;
      }
      const state = readState(comments);
      // Filed, or a filing under way: the needs-triage label hands it to a person.
      if (state.filed) continue;
      checked += 1;
      const latest = state.runs.length > 0 ? await call("GET", `/repos/${repo}/actions/runs/${state.runs.at(-1)}`) : null;
      // A run the API no longer has counts as finished.
      let action = decide({ state, latest: state.runs.length > 0 && latest === null ? { status: "completed" } : latest });
      if (action === "wait") result.waiting.push(number);
      if (action === "dispatch" && result.dispatched.length >= MAX_DISPATCHES) action = "stop";
      if (action === "file" && result.filed.length >= MAX_FILED) action = "stop";
      // Never start a run the budget left cannot record, or a filing it cannot finish.
      if ((action === "dispatch" && remaining() < 2) || (action === "file" && remaining() < state.runs.length + 3)) {
        result.truncated = `stopped at #${number}: too little call budget left`;
        break;
      }
      // intake-triage.yml admits this token's dispatch whoever wrote the
      // issue, so the author check in selectCandidates is the only one.
      if (action === "dispatch") {
        const sent = await call("POST", `/repos/${repo}/actions/workflows/intake-triage.yml/dispatches`, {
          ref: "main",
          inputs: { "issue-number": String(number) },
          // Without it, API version 2022-11-28 answers 204 with no run id.
          return_run_details: true,
        });
        const id = Number(sent?.workflow_run_id);
        if (!Number.isInteger(id) || id <= 0) throw new Error("the dispatch returned no run id");
        result.dispatched.push(number);
        await writeState(call, repo, number, state, {
          runs: [...state.runs, id],
          filed: null,
          runUrl: `${repoUrl}/actions/runs/${id}`,
        });
      }
      if (action === "file") {
        const runs = [];
        for (const id of state.runs) {
          const run = id === state.runs.at(-1) ? latest : await call("GET", `/repos/${repo}/actions/runs/${id}`);
          runs.push({ id, conclusion: run?.conclusion ?? null });
        }
        // The label and the in-progress record go first: the record stops
        // later passes, so a write that fails after it can never file a second
        // issue, and the label hands the original to a person either way.
        await handOff(number);
        await writeState(call, repo, number, state, { runs: state.runs, filed: FILING });
        const filed = await call("POST", `/repos/${repo}/issues`, renderFiledIssue({ number, runs, repoUrl }));
        result.filed.push(filed.number);
        await writeState(call, repo, number, state, { runs: state.runs, filed: filed.number });
      }
    } catch (error) {
      if (/call budget/.test(error.message)) {
        result.truncated = `stopped at #${number}: ${error.message}`;
        break;
      }
      result.failed.push({ number, error: error.message });
    }
  }
  return result;
}

async function writeState(call, repo, number, state, next) {
  const body = { body: renderState(next) };
  if (state.commentId) await call("PATCH", `/repos/${repo}/issues/comments/${state.commentId}`, body);
  else await call("POST", `/repos/${repo}/issues/${number}/comments`, body);
}

async function main() {
  const env = process.env;
  const budget = createBudget(Number(env.CALL_BUDGET ?? 120));
  const call = async (method, path, body) => {
    budget.spend();
    const response = await guardedFetch(`${env.GITHUB_API_URL}${path}`, {
      method,
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${env.GITHUB_TOKEN}`,
        "x-github-api-version": "2022-11-28",
        ...(body ? { "content-type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (response.status === 404 && method === "GET") return null;
    if (!response.ok) throw new Error(`${method} ${path}: HTTP ${response.status}`);
    return response.status === 204 ? null : response.json();
  };
  const list = JSON.parse(readFileSync(env.TRUSTED_ACTORS_PATH, "utf8"));
  const authorIds = new Set(humanIds(list).split(",").filter(Boolean));
  if (/^[1-9][0-9]*$/.test(env.LANES_APP_ID ?? "")) authorIds.add(env.LANES_APP_ID);
  const result = await runSweep({
    call,
    remaining: () => budget.limit - budget.used,
    repo: env.REPOSITORY,
    serverUrl: env.GITHUB_SERVER_URL,
    now: new Date(),
    authorIds,
  });
  const numbers = (xs) => xs.map((n) => `#${n}`).join(", ") || "none";
  const lines = [
    "### Triage sweep",
    "",
    `Candidates: ${result.candidates}. Dispatched: ${numbers(result.dispatched)}. Filed: ${numbers(result.filed)}. Handed off for too many comments: ${numbers(result.handedOff)}. Waiting on a run: ${numbers(result.waiting)}. Calls: ${budget.used}.`,
    "",
    ...(result.truncated ? [`- ${result.truncated}`] : []),
    ...result.failed.map((f) => `- failed #${f.number}: ${f.error}`),
  ];
  appendFileSync(env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
  console.log(
    `triage-sweep: candidates ${result.candidates}, dispatched ${result.dispatched.length}, filed ${result.filed.length}, waiting ${result.waiting.length}, failed ${result.failed.length}, calls ${budget.used}`,
  );
  if (result.failed.length > 0) {
    console.log(`::error::${result.failed.length} triage sweep issue(s) failed; see the step summary`);
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
