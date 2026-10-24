// The hourly triage sweep: finds open issues no intake verdict holds and
// dispatches intake-triage.yml for them, with the job's own token only. An
// issue qualifies when it is no pull request, is over an hour old, its author
// is a listed human or the lanes App (as the intake lane admits on open), and
// either:
//
// - it has no `status:` label and no agent-ready, needs-human or needs-spec,
//   whatever comments intake left: a triage that posted no comment or two, a
//   verdict apply-verdict could not write (an issue the lanes App opened,
//   whose --check refuses the App as actor while a github-actions[bot]
//   dispatch passes), or an issue work-unblock handed back after its lane PR
//   ended; or
// - /work-items:decompose published it born triaged in `status: ready`, with
//   no agent-ready, admission-deferred or hold and no open blocker: nothing
//   ran admission on it, and intake's dispatch runs it (a dispatch skips the
//   born-triaged gate).
//
// The needs-triage floor label is no triage label: it lands on open whether
// or not intake runs. github-actions[bot] issues are left out: the lane
// sweep's can quote fork-controlled log lines. Per issue, one comment holds the runs
// dispatched; after 2 that left it untriaged the sweep labels it needs-triage
// and rewrites that comment to hand it to a maintainer, listing the runs. It
// files no issue. No model. The count is per triage cycle: a work-unblock
// hand-back comment the lanes App posted after the state comment's last edit
// starts a new cycle with no runs, in the same comment. An issue still
// carrying needs-triage whose own state comment hands it off is skipped
// without a REST read, found by one GraphQL search that returns the hits'
// comments, so hand-offs cannot use up the call budget.
//
// Accepted exposure: intake reads an issue's comments, and anyone can comment
// in the hour before the sweep dispatches. Intake treats them as untrusted
// data and applies only allowlisted labels, never agent-ready.
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { BORN_TRIAGED_MARKER, humanIds } from "../../actions/check-born-triaged/check-born-triaged.mjs";
import { createBudget } from "./collect.mjs";

export const MAX_DISPATCHES = 5;
const MAX_HANDED = 5;
const MAX_CHECKED = 20;
const MAX_ISSUE_PAGES = 15;
const COMMENT_PAGES = 3;
const ATTEMPTS = 2;
const MIN_AGE_MS = 3_600_000;
const BOT = "github-actions[bot]";
// `filed` is HANDED once the comment hands the issue to a maintainer. An older
// sweep's record holds the number of the issue it filed, or FILING while that
// filing was under way; both stop the sweep too.
export const FILING = "?";
export const HANDED = "handed";
const STATE = /^<!-- claude-lane triage-sweep runs=([0-9,]*) filed=([0-9]*|\?|handed) -->/;
// work-unblock's comment when it hands an issue back to triage after its lane
// PR merged with Refs: or closed unmerged (label-unblocked.mjs handedMarker).
const HAND_BACK = /^<!-- work-unblock handed triage #[1-9][0-9]* -->/;
// The visible text of the hand-off comment, which the search matches.
const HANDED_TEXT = "so the sweep no longer dispatches it";
const FLOOR = "needs-triage";
// Labels a verdict or a person leaves: an issue with one is triaged.
const TRIAGED = /^(needs-human|needs-spec|agent-ready)$|^status: /;
// What keeps a born-triaged `status: ready` issue out of admission on purpose.
const ADMISSION_HOLDS = new Set(["agent-ready", "admission-deferred", "needs-human", "needs-owner-decision", "status: needs-decision", "status: needs-info", "work-class: untrusted-provenance"]);

const names = (i) => (i.labels ?? []).map((l) => String(l.name ?? "").toLowerCase());
const bornReady = (i) =>
  String(i.body ?? "")
    .trimEnd()
    .endsWith(BORN_TRIAGED_MARKER) &&
  names(i).includes("status: ready") &&
  !names(i).some((n) => ADMISSION_HOLDS.has(n)) &&
  !(i.issue_dependencies_summary?.blocked_by > 0);

export function selectCandidates({ issues, now, authorIds }) {
  return issues
    .filter(
      (i) =>
        !i.pull_request &&
        authorIds.has(String(i.user?.id)) &&
        (!names(i).some((n) => TRIAGED.test(n)) || bornReady(i)) &&
        now - new Date(i.created_at) >= MIN_AGE_MS,
    )
    .sort((a, b) => new Date(a.created_at) - new Date(b.created_at) || a.number - b.number);
}

// `appId` is the lanes App's account id: only its hand-back starts a new
// cycle, so no one else can reset the dispatch count.
export function readState(comments, appId = null) {
  const handBack = Math.max(
    ...comments
      .filter((c) => appId !== null && String(c.user?.id) === String(appId) && HAND_BACK.test(String(c.body ?? "")))
      .map((c) => Date.parse(c.created_at))
      .filter(Number.isFinite),
  );
  for (const c of comments) {
    const m = c.user?.login === BOT ? STATE.exec(String(c.body ?? "")) : null;
    if (m) {
      if (handBack > Date.parse(c.updated_at ?? c.created_at)) {
        return { commentId: c.id, runs: [], filed: null };
      }
      return {
        commentId: c.id,
        runs: m[1] ? m[1].split(",").map(Number) : [],
        filed: m[2] === FILING || m[2] === HANDED ? m[2] : m[2] ? Number(m[2]) : null,
      };
    }
  }
  return { commentId: null, runs: [], filed: null };
}

// `details` lists each run as {id, conclusion}, for the hand-off.
export const renderState = ({ runs, filed, runUrl, repoUrl, details = [] }) =>
  `<!-- claude-lane triage-sweep runs=${runs.join(",")} filed=${filed ?? ""} -->\n` +
  (filed === HANDED
    ? [
        `Intake triage did not triage this issue after ${runs.length} dispatches, ${HANDED_TEXT} and labeled it needs-triage for a maintainer. Triage it by hand, and read the runs for why intake did not:`,
        "",
        ...details.map((r) => `- ${repoUrl}/actions/runs/${r.id} (${r.conclusion ?? "unknown"})`),
      ].join("\n")
    : filed === FILING
    ? `Intake triage did not triage this issue after ${runs.length} dispatches; the sweep labeled it needs-triage for a maintainer.`
    : filed
    ? `Intake triage did not triage this issue after ${runs.length} dispatches; #${filed} hands it to a maintainer.`
    : `The triage sweep dispatched [intake triage](${runUrl}) for this issue (attempt ${runs.length} of ${ATTEMPTS}).`);

export function decide({ state, latest }) {
  if (state.filed) return "stop";
  if (state.runs.length === 0) return "dispatch";
  if (latest?.status !== "completed") return "wait";
  return state.runs.length >= ATTEMPTS ? "hand" : "dispatch";
}

const FILED_TITLE = /^Intake triage left #([1-9][0-9]*) untriaged after /;
const SEARCH_PAGES = 10;

// The numbers `pick` takes from one search's items. A failed or incomplete
// search excludes nothing: those issues are then read and skipped by their state.
async function search(call, query, pick) {
  const q = encodeURIComponent(query);
  const numbers = new Set();
  try {
    for (let page = 1; page <= SEARCH_PAGES; page += 1) {
      const found = await call("GET", `/search/issues?q=${q}&per_page=100&page=${page}`);
      if (found?.incomplete_results !== false) return new Set();
      for (const item of found.items ?? []) {
        const number = pick(item);
        if (number) numbers.add(number);
      }
      if ((found.items ?? []).length < 100) break;
    }
  } catch (error) {
    if (/call budget/.test(error.message)) throw error;
    return new Set();
  }
  return numbers;
}

// The issues this sweep handed off in a comment, from one GraphQL search per
// 50 issues that also returns each hit's first 100 comments, so a hit costs no
// REST read. The search only finds issues where github-actions commented and
// some comment, by anyone, holds the hand-off text, so a hit counts only when
// the bot's own state comment reads filed=handed and no Bot's work-unblock
// hand-back is newer than it; anything else is read and judged as usual. A
// failed search excludes nothing.
const HANDED_QUERY = `query($q: String!, $after: String) {
  search(query: $q, type: ISSUE, first: 50, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { ... on Issue { number comments(first: 100) { nodes { author { __typename login } body createdAt updatedAt } } } }
  }
}`;
const isActionsBot = (author) => author?.__typename === "Bot" && author.login === "github-actions";

export function handedInComments(comments) {
  const state = comments.find((c) => isActionsBot(c.author) && STATE.test(String(c.body ?? "")));
  if (STATE.exec(String(state?.body ?? ""))?.[2] !== HANDED) return false;
  const at = Date.parse(state.updatedAt ?? state.createdAt);
  return !comments.some((c) => c.author?.__typename === "Bot" && HAND_BACK.test(String(c.body ?? "")) && !(Date.parse(c.createdAt) <= at));
}

async function handedInSweepComments(call, repo) {
  const numbers = new Set();
  const q = `repo:${repo} is:issue is:open commenter:app/github-actions in:comments "${HANDED_TEXT}"`;
  let after = null;
  try {
    for (let page = 1; page <= SEARCH_PAGES; page += 1) {
      const answer = await call("POST", "/graphql", { query: HANDED_QUERY, variables: { q, after } });
      const found = answer?.data?.search;
      if (!found || answer.errors) return new Set();
      for (const node of found.nodes ?? []) {
        if (Number.isInteger(node?.number) && handedInComments(node.comments?.nodes ?? [])) numbers.add(node.number);
      }
      if (!found.pageInfo?.hasNextPage) break;
      after = found.pageInfo.endCursor;
    }
  } catch (error) {
    if (/call budget/.test(error.message)) throw error;
    return new Set();
  }
  return numbers;
}

// The issues handed to a maintainer, so their comments cost no reads: those an
// older sweep filed a hand-off issue for (only a title the bot wrote counts),
// and those whose own state comment hands them off (handedInSweepComments).
// The caller skips them only while they carry needs-triage.
async function handedOff(call, repo) {
  const filed = await search(call, `repo:${repo} is:issue author:app/github-actions in:title "Intake triage left"`, (item) =>
    item.user?.login === BOT ? Number(FILED_TITLE.exec(String(item.title ?? ""))?.[1] ?? 0) : 0,
  );
  return new Set([...filed, ...(await handedInSweepComments(call, repo))]);
}

// One pass. `call` returns null for a GET that 404s.
export async function runSweep({ call, remaining = () => Infinity, repo, serverUrl, now, authorIds, appId = null }) {
  const repoUrl = `${serverUrl}/${repo}`;
  const issues = [];
  for (let page = 1; page <= MAX_ISSUE_PAGES; page += 1) {
    const batch = await call("GET", `/repos/${repo}/issues?state=open&per_page=100&page=${page}`);
    issues.push(...batch);
    if (batch.length < 100) break;
  }
  const result = { candidates: 0, dispatched: [], handed: [], handedOff: [], waiting: [], failed: [], truncated: null };
  const selected = selectCandidates({ issues, now, authorIds });
  const filed = selected.length > 0 ? await handedOff(call, repo) : new Set();
  const candidates = selected.filter((i) => !(filed.has(i.number) && names(i).includes(FLOOR)));
  result.candidates = candidates.length;
  const handOff = (number) => call("POST", `/repos/${repo}/issues/${number}/labels`, { labels: [FLOOR] });
  // Issues the sweep already handed off cost their reads and do not count
  // toward MAX_CHECKED, so they cannot starve the issues behind them.
  let checked = 0;
  for (const { number, labels } of candidates) {
    if (checked >= MAX_CHECKED) break;
    if (result.dispatched.length >= MAX_DISPATCHES && result.handed.length >= MAX_HANDED) break;
    try {
      const comments = [];
      let full = false;
      for (let page = 1; page <= COMMENT_PAGES; page += 1) {
        const batch = (await call("GET", `/repos/${repo}/issues/${number}/comments?per_page=100&page=${page}`)) ?? [];
        comments.push(...batch);
        full = batch.length === 100;
        if (!full) break;
      }
      // Past the pages read, the state comment may be hidden: a person
      // decides, so the label goes on once.
      if (full) {
        if ((labels ?? []).some((l) => l.name === FLOOR)) continue;
        checked += 1;
        await handOff(number);
        result.handedOff.push(number);
        continue;
      }
      const state = readState(comments, appId);
      // Handed to a maintainer already: the needs-triage label is on it.
      if (state.filed) continue;
      checked += 1;
      const latest = state.runs.length > 0 ? await call("GET", `/repos/${repo}/actions/runs/${state.runs.at(-1)}`) : null;
      // A run the API no longer has counts as finished.
      let action = decide({ state, latest: state.runs.length > 0 && latest === null ? { status: "completed" } : latest });
      if (action === "wait") result.waiting.push(number);
      if (action === "dispatch" && result.dispatched.length >= MAX_DISPATCHES) action = "stop";
      if (action === "hand" && result.handed.length >= MAX_HANDED) action = "stop";
      // Never start a run the budget left cannot record, or a hand-off it cannot finish.
      if ((action === "dispatch" && remaining() < 2) || (action === "hand" && remaining() < state.runs.length + 1)) {
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
      if (action === "hand") {
        const runs = [];
        for (const id of state.runs) {
          const run = id === state.runs.at(-1) ? latest : await call("GET", `/repos/${repo}/actions/runs/${id}`);
          runs.push({ id, conclusion: run?.conclusion ?? null });
        }
        // The label first, then the record that stops later passes: a failed
        // record leaves the issue for the next pass, which labels it again.
        await handOff(number);
        await writeState(call, repo, number, state, { runs: state.runs, filed: HANDED, repoUrl, details: runs });
        result.handed.push(number);
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
    const response = await fetch(`${env.GITHUB_API_URL}${path}`, {
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
    appId: /^[1-9][0-9]*$/.test(env.LANES_APP_ID ?? "") ? env.LANES_APP_ID : null,
  });
  const numbers = (xs) => xs.map((n) => `#${n}`).join(", ") || "none";
  const lines = [
    "### Triage sweep",
    "",
    `Candidates: ${result.candidates}. Dispatched: ${numbers(result.dispatched)}. Handed to a maintainer after ${ATTEMPTS} dispatches: ${numbers(result.handed)}. Handed off for too many comments: ${numbers(result.handedOff)}. Waiting on a run: ${numbers(result.waiting)}. Calls: ${budget.used}.`,
    "",
    ...(result.truncated ? [`- ${result.truncated}`] : []),
    ...result.failed.map((f) => `- failed #${f.number}: ${f.error}`),
  ];
  appendFileSync(env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
  console.log(
    `triage-sweep: candidates ${result.candidates}, dispatched ${result.dispatched.length}, handed ${result.handed.length}, waiting ${result.waiting.length}, failed ${result.failed.length}, calls ${budget.used}`,
  );
  if (result.failed.length > 0) {
    console.log(`::error::${result.failed.length} triage sweep issue(s) failed; see the step summary`);
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
