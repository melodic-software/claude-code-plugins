#!/usr/bin/env node

// Operator-side publisher for the promotion-evidence events file
// (promotion_evidence_source in reference/promotion-evidence-bootstrap.md) and the C3
// promotion-evidence report. It reads GitHub only, through `gh api` GET calls and one read-only
// GraphQL query, and never runs inside the lane: the lane must not be able to write its output.
//
// Usage: node publish-promotion-evidence.mjs --repo <owner/name> --since <ISO> --lane-login <login> [--lane-login ...]
//          --gate-check <check or context name> [--gate-check ...] [--through <ISO>] [--ai-reviewer <login> ...] [--missed-blocking-label <name>] [--out <dir>]
// Exit 0 = report printed (and published with --out); 1 = publish refused; 2 = usage or GitHub read error.
//
// Report mode (no --out) prints {repo, since, through, events, unresolvedReverts, gateFailures, unclassedAutonomous, cells} to
// stdout and writes nothing. --through defaults to, and is clamped to, now. With --out it also
// writes <dir>/evidence.json (the events array) and <dir>/evidence.meta.json ({generated_at,
// through, sha256, prev_sha256}). Both temp files are written before either rename, the events
// file renamed first. It refuses when an existing evidence.json is not a JSON array, has no
// sidecar or does not match the sidecar's sha256, or holds an event the new array lacks.
//
// Cost: every run pages the repository's whole closed-PR history (one REST page per 100 closed
// PRs, created ascending, so no merge is skipped while paging), then reads, per merged PR in the
// window, one GraphQL query and the issue events of the PR and each linked issue, and per
// autonomous merge its check runs and statuses.
//
// Autonomy follows babysit_merge_policy.py derive_auto_merge: the latest AddedToMergeQueueEvent's
// actor and enqueuer, or merged_by when the merge bypassed the queue; a merge is autonomous when
// any of them is null or not human (a User outside --lane-login, not `github-actions`, not a
// `[bot]` login; derive_auto_merge's write-permission read is not made), or merged_by is a
// --lane-login. Logins compare case-insensitively and exactly in REST spelling: a GraphQL `Bot`
// actor gains `[bot]`, so a User owning an App's bare slug is never that App. GitHub records the
// enqueuer as merged_by (probed 2026-10-12 on a queue-merged pull: merged_by.login matched the
// AddedToMergeQueueEvent enqueuer), so --lane-login names any lane identity that runs as a User
// (a machine user); an App lane is a Bot and counts without it. Recheck if merged_by stops
// matching the enqueuer. For an App lane pass --lane-login as `name[bot]`, or its dispatch runs
// and pins are not found.
//
// Deletion (#7518) refuses the publish rather than erasing a contrary event, inside --since..
// --through (EvidenceGone, failClosedReason): a run_number gap between two runs of
// FULL_RUN_WORKFLOW or CANARY_WORKFLOW created in the window ("run-deleted:"), and an issue or
// pull number missing between two created in the window that reads 410 Gone ("issue-deleted:")
// or names another repository ("issue-missing:"). The newest run or issue in the window, deleted
// before a later one exists, leaves no gap. Each babysit-merge-demotion record a filer
// (github-actions[bot] or a --lane-login) opened, with the marker in its body or any revision, or
// an edit history that cannot be read whole, is a gate-failure on every cell at its creation and
// at each repeat-failure comment inside the window: records only ever add events.
//
// Anything a lane can write into a PR or commit degrades to a listing or to unclassed-autonomous,
// never to a refused publish. What refuses is GitHub itself being unreadable: a failed read, an
// unparsable date, a compare that is neither ahead, identical nor behind.
//
// What counts (judgment where the contract names no GitHub source):
// - A merged PR's work class is the highest `work-class:` label (the label set
//   babysit-prs/scripts/babysit_merge_policy.py WORK_CLASS_LABELS maps) on the issues it linked
//   at merge and on the PR, each label set rebuilt as of merged_at by undoing later
//   labeled/unlabeled events, so relabeling after the merge changes nothing. The linked set is
//   closingIssuesReferences with later ConnectedEvent/DisconnectedEvent undone; when the PR body
//   was edited after the merge, its closing-keyword links at merge are unknown and the class is
//   none. A label, linked-issue or timeline list that is unreadable or has another page leaves
//   the merge unclassed and counts it as autonomous.
// - A C2/C3 merge is counted. An autonomous merge with no class is listed in
//   unclassedAutonomous, never counted toward a positive term, and each of its contrary events
//   is emitted against every promotable cell.
// - reverted-merge: an autonomous C2/C3 merge named by a merged PR body or a default-branch
//   commit as `Reverts <owner/repo>#<n>` (GitHub's revert button) or `This reverts commit
//   <sha>` (git revert); one event per reverted merge, at the earliest revert seen. A merged PR
//   titled revert... with neither form is listed in unresolvedReverts for a human to read, as is
//   a named target that is not a merged pull request or a SHA no commit has, so a bad reference
//   cannot stop a publish. Every revert counts, whoever merged or enqueued the revert PR (a
//   human, a bot or the lane) and whoever pushed a revert commit straight to the default branch
//   (its git author can be forged anyway). The trade-off: a bot able to merge reverts can hold a
//   cell down, which fails safe (it can only demote).
// - gate-failure: only the post-merge gate counts: check runs and commit-status contexts on an
//   autonomous merge's merge commit whose name is a --gate-check (required; none named is a
//   usage error, never an empty gate). In this repository babysit-prs/scripts/babysit_postmerge.py
//   reads the post-merge gate as the silent-revert canary (post-merge-detect-silent-revert.yml,
//   check run `Silent-revert canary` on the merge commit) and the full pr-require-checks.yml run
//   (aggregate job `ci-status`), scheduled or dispatched on a later SHA containing the merge. This
//   script reads those workflow runs the same way (postMergeRuns) and, on the merge commit itself,
//   the --gate-check check runs and contexts. Among the latter, every check run (filter=all, so a run later
//   re-run green still counts) concluding failure, timed_out or startup_failure, and every
//   status in state failure or error, whenever it completed. A run concluding cancelled,
//   action_required, stale or anything else not green also counts, unless a later run of the
//   same check name on that commit succeeded. The gate-pass term also fails while a run is in
//   progress or a context's latest status is not success.
// - verification-divergence: a human (a User actor outside --lane-login) applied
//   --missed-blocking-label to a merged C3 PR (cell C3-ai-review-blocking) or an autonomous C2
//   PR (cell C2-auto-merge), read from the label timeline, so removing the label later does not
//   undo it.
// - A cell's window runs from its first counted merge to its last.
//
// Event shape and vocabulary: plugins/autonomy/skills/setup/scripts/check-security-binding.mjs,
// CONTRARY_EVIDENCE_EVENTS and resolveEffectivePromotion; restated here, not imported, because
// no plugin reads another plugin's files. Predicate terms and suggested default thresholds:
// plugins/autonomy/reference/guardrails/work-classes.md "Suggested default predicates".

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const CLASS_LABELS = {
  "work-class: read-only": "C1",
  "work-class: mechanical": "C2",
  "work-class: scoped": "C3",
  "work-class: structural": "C4",
  "work-class: untrusted-provenance": "C5",
};
const GATE_FAILED = new Set(["failure", "timed_out", "startup_failure"]);
const GATE_OK = new Set(["success", "neutral", "skipped"]);
const STATUS_FAILED = new Set(["failure", "error"]);
const PAGE = 100;
const MISSED_BLOCKING_LABEL = "ai-review: missed-blocking";
const DAY_MS = 86_400_000;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;

export class PublishError extends Error {}

// Contrary evidence GitHub no longer lists: failClosedReason carries the stable reason prefix.
export class EvidenceGone extends PublishError {
  constructor(reason) {
    super(`refusing to publish: ${reason}`);
    this.failClosedReason = reason;
  }
}

function instant(value, name) {
  const ms = typeof value === "string" && ISO.test(value) ? Date.parse(value) : Number.NaN;
  if (Number.isNaN(ms)) throw new PublishError(`${name}: not an ISO 8601 instant with an offset: ${JSON.stringify(value)}`);
  return ms;
}

// A REST path is read with GET; "graphql" runs a query (read-only: PULL_QUERY is the only one).
function realGh(path, graphql) {
  const args = graphql
    ? ["api", "graphql", "-f", `query=${graphql.query}`, ...Object.entries(graphql.variables).flatMap(([key, value]) => ["-F", `${key}=${value}`])]
    : ["api", "--method", "GET", path];
  const run = spawnSync("gh", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (run.status !== 0) return ghFailure(path, graphql, run.stdout, run.stderr || run.error?.message || "");
  return JSON.parse(run.stdout);
}

// A reference a lane can write (a PR number, a commit SHA) that names nothing: listed, never fatal.
export class UnresolvableError extends PublishError {}
// A page that is unreadable or has another page: the merge's class is unknown.
class IncompleteError extends PublishError {}

// A failed `gh api` call. Only two answers are not read failures: GraphQL NOT_FOUND on the pull
// request or discussion itself (data.repository.<key> null, every error path ending in that key),
// which is returned as the answer, and REST 422 "No commit found for SHA", which is unresolvable. Any
// other failure, a repository NOT_FOUND included, fails the publish.
export function ghFailure(path, graphql, stdout, stderr) {
  let body = null;
  try {
    body = JSON.parse(stdout);
  } catch {}
  const errors = body?.errors;
  for (const key of ["pullRequest", "discussion"]) {
    if (
      graphql &&
      body?.data?.repository?.[key] === null &&
      Array.isArray(errors) &&
      errors.length > 0 &&
      errors.every((e) => e?.type === "NOT_FOUND" && Array.isArray(e.path) && e.path.at(-1) === key)
    ) {
      return body;
    }
  }
  if (!graphql && String(body?.status) === "422" && /^No commit found for SHA/.test(body?.message ?? "")) throw new UnresolvableError(body.message);
  throw new PublishError(`gh api ${path} failed: ${String(stderr).trim()}`);
}

// A date GitHub returned; one that does not parse refuses the publish.
function ms(value, what) {
  const parsed = typeof value === "string" ? Date.parse(value) : Number.NaN;
  if (Number.isNaN(parsed)) throw new PublishError(`refusing to publish: ${what} has an unreadable date ${JSON.stringify(value)}`);
  return parsed;
}

const PULL_QUERY =
  "query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){" +
  "number headRefOid mergedAt lastEditedAt mergeCommit{oid} mergedBy{__typename login} labels(first:100){pageInfo{hasNextPage} nodes{name}} " +
  "closingIssuesReferences(first:50){pageInfo{hasNextPage} nodes{number labels(first:100){pageInfo{hasNextPage} nodes{name}}}} " +
  "timelineItems(first:100,itemTypes:[CONNECTED_EVENT,DISCONNECTED_EVENT,ADDED_TO_MERGE_QUEUE_EVENT]){pageInfo{hasNextPage} nodes{__typename " +
  "... on ConnectedEvent{createdAt subject{__typename ... on Issue{number}}} ... on DisconnectedEvent{createdAt subject{__typename ... on Issue{number}}} " +
  "... on AddedToMergeQueueEvent{createdAt actor{__typename login} enqueuer{__typename login}}}}}}}";
const CELLS = ["C2-auto-merge", "C3-ai-review-blocking", "C3-auto-merge"];

// A REST login (`app[bot]` for an App), compared exactly and case-insensitively.
function loginKey(login) {
  return String(login ?? "")
    .trim()
    .toLowerCase();
}

// A GraphQL actor in REST spelling, as babysit_merge_policy.py actor_key: a `Bot` gains the
// `[bot]` GraphQL omits, so a User who owns the bare slug `app` is never the App `app[bot]`.
function actorKey(actor) {
  const login = loginKey(actor?.login);
  return actor?.__typename === "Bot" && login && !login.endsWith("[bot]") ? `${login}[bot]` : login;
}

function onePage(connection, what) {
  if (!Array.isArray(connection?.nodes) || connection.pageInfo?.hasNextPage !== false) {
    throw new IncompleteError(`gh api graphql: ${what} unreadable or hasNextPage`);
  }
  return connection.nodes;
}

function pages(gh, path, key) {
  const out = [];
  for (let page = 1; ; page += 1) {
    const body = gh(`${path}${path.includes("?") ? "&" : "?"}per_page=${PAGE}&page=${page}`);
    const items = key ? body?.[key] : body;
    if (!Array.isArray(items)) throw new PublishError(`gh api ${path}: expected an array${key ? ` at .${key}` : ""}`);
    out.push(...items);
    if (items.length < PAGE) return out;
  }
}

function workClass(names) {
  return names.map((name) => CLASS_LABELS[name]).filter(Boolean).sort().at(-1) ?? null;
}

// The label set as of `atMs`: the current set with every later labeled/unlabeled event undone.
function labelsAsOf(current, events, atMs) {
  const set = new Set(current);
  const later = events
    .filter((e) => (e.event === "labeled" || e.event === "unlabeled") && ms(e.created_at, "a label event") > atMs)
    .sort((a, b) => ms(b.created_at, "a label event") - ms(a.created_at, "a label event"));
  for (const e of later) e.event === "labeled" ? set.delete(e.label?.name) : set.add(e.label?.name);
  return [...set];
}

function eventKey(event) {
  return JSON.stringify([event.cell, event.event, event.at]);
}

// The post-merge gate's workflow runs, read as babysit-prs/scripts/babysit_postmerge.py check()
// and _judge() read them (same plugin, mirrored rather than imported across languages):
// FULL_RUN_WORKFLOW runs from `schedule` and `workflow_dispatch`, and CANARY_WORKFLOW runs from
// `push`, on the default branch, created at or after a merge (no upper bound), on a SHA that
// contains it: compare <merge>...<run SHA>, as _Context.contains does. Attempt 1 decides; a red
// full run is a flake only when a lane identity's attempt 2 passed. A merge is verified at the
// later of its first green lane dispatch run and first green canary run, and runs created after
// that are not its evidence; a compare that is behind means not contained. Only a verified merge
// with nothing red or pending passes the gate, and only a lane dispatch created within
// DISPATCH_DEADLINE of the merge verifies it, so a merge with no timely lane dispatch run
// (check()'s 6-hour failure) is not passed. Departures, all toward a failure: a compare that is
// diverged or unknown refuses the publish (check() reads it as not containing); a red full run
// whose re-run has not come counts as red once DISPATCH_DEADLINE has passed since it completed
// (check() waits on it); a red run covering several merges is a failure of each.
//
// Where check() files a Failure, this emits a gate-failure, so demotion counts match: a red full
// or canary run (at the run's update time); no dispatch run by a lane identity created within
// DISPATCH_DEADLINE of the merge, once that deadline has passed (at the deadline); and, for a
// merge a lane identity enqueued, the pin read-back (read_pin): no unedited lane pin once the
// deadline has passed (at the deadline), or a pinned SHA that is not headRefOid (at the merge).
const FULL_RUN_WORKFLOW = "pr-require-checks.yml";
const CANARY_WORKFLOW = "post-merge-detect-silent-revert.yml";
const DISPATCH_DEADLINE_MS = 6 * 3_600_000;

function isoSeconds(msValue) {
  return new Date(msValue).toISOString().replace(/\.000Z$/, "Z");
}

// babysit_postmerge.py read_pin: the newest comment by the identity whose first line is the pin
// marker, read through at most PIN_PAGE_LIMIT pages; none, an edited one, or a longer thread is
// no pin.
const PIN_RE = /^<!-- babysit-merge-pin sha=([0-9a-f]{40}) -->$/;
const PIN_QUERY =
  "query($owner:String!,$name:String!,$number:Int!,$c:String){repository(owner:$owner,name:$name){pullRequest(number:$number){" +
  "comments(first:100,after:$c){pageInfo{hasNextPage endCursor} nodes{author{__typename login} body lastEditedAt}}}}}";
const PIN_PAGE_LIMIT = 30;

function readPin(gh, owner, name, number, lane) {
  const firstLine = (text) => String(text ?? "").trimStart().split("\n", 1)[0].trim();
  const pins = [];
  let cursor = null;
  for (let page = 0; page < PIN_PAGE_LIMIT; page += 1) {
    const variables = { owner, name, number, ...(cursor ? { c: cursor } : {}) };
    const comments = gh("graphql", { query: PIN_QUERY, variables })?.data?.repository?.pullRequest?.comments;
    if (!Array.isArray(comments?.nodes) || typeof comments.pageInfo?.hasNextPage !== "boolean") throw new PublishError(`#${number} pin: no comment page`);
    pins.push(...comments.nodes.filter((c) => lane.has(actorKey(c?.author)) && PIN_RE.test(firstLine(c?.body))));
    if (!comments.pageInfo.hasNextPage) {
      const last = pins.at(-1);
      return last && !last.lastEditedAt ? PIN_RE.exec(firstLine(last.body))[1] : null;
    }
    cursor = comments.pageInfo.endCursor;
    if (typeof cursor !== "string" || !cursor) throw new PublishError(`#${number} pin: a next page with no cursor`);
  }
  return null;
}

function postMergeRuns(gh, repo, branch, merges, { lane, throughMs }) {
  if (merges.length === 0) return () => ({ failures: [], unsettled: false, verified: false });
  const floor = Math.min(...merges.map((m) => ms(m.mergedAt, `#${m.number} mergedAt`)));
  const created = encodeURIComponent(`>=${new Date(floor).toISOString().replace(/\.\d{3}Z$/, "Z")}`);
  const byCreated = (a, b) => a.createdMs - b.createdMs;
  const list = (workflow, event) =>
    pages(gh, `repos/${repo}/actions/workflows/${workflow}/runs?event=${event}&branch=${encodeURIComponent(branch)}&created=${created}`, "workflow_runs")
      .map((run) => ({ ...run, createdMs: ms(run.created_at, `run ${run.id}`), check: `${workflow} ${event}` }))
      .filter((run) => run.head_branch === branch && run.createdMs >= floor);
  const fullRuns = [...list(FULL_RUN_WORKFLOW, "schedule"), ...list(FULL_RUN_WORKFLOW, "workflow_dispatch")].sort(byCreated);
  const canaryRuns = list(CANARY_WORKFLOW, "push").sort(byCreated);

  const compares = new Map();
  const contains = (sha, runSha) => {
    const key = `${sha}...${runSha}`;
    if (!compares.has(key)) {
      const status = gh(`repos/${repo}/compare/${key}?per_page=1&page=1`)?.status;
      // behind: the run's SHA is an ancestor of the merge, so it does not contain it (as check()).
      if (status !== "ahead" && status !== "identical" && status !== "behind") {
        throw new PublishError(`refusing to publish: compare ${key} is ${JSON.stringify(status)}, so whether that post-merge run contains the merge is unknown`);
      }
      compares.set(key, status !== "behind");
    }
    return compares.get(key);
  };

  const outcomes = new Map();
  const outcome = (run, attributable) => {
    const key = `${run.id}:${attributable}`;
    if (!outcomes.has(key)) {
      const attempt = (n) => (run.run_attempt === n ? run : gh(`repos/${repo}/actions/runs/${run.id}/attempts/${n}`));
      const first = attempt(1);
      let state;
      if (!first?.status) throw new PublishError(`run ${run.id}: attempt 1 is missing`);
      if (first.status !== "completed") state = "pending";
      else if (first.conclusion === "success") state = "green";
      else if (!attributable) state = "red";
      else {
        const second = run.run_attempt >= 2 ? attempt(2) : null;
        if (!second) state = throughMs - ms(first.updated_at, `run ${run.id} attempt 1`) > DISPATCH_DEADLINE_MS ? "red" : "pending";
        else if (!lane.has(loginKey(second.triggering_actor?.login))) state = "red";
        else if (second.status !== "completed") state = "pending";
        else state = second.conclusion === "success" ? "flake" : "red";
      }
      outcomes.set(key, { state, conclusion: first.conclusion });
    }
    return outcomes.get(key);
  };

  // Compares run only where the answer can change the verdict: a red or pending run, a green lane
  // dispatch run, and a green canary run once a lane dispatch has verified half the merge.
  return (merge) => {
    const mergedMs = ms(merge.mergedAt, `#${merge.number} mergedAt`);
    const after = (runs) => runs.filter((run) => run.createdMs >= mergedMs);
    const relevant = (run) => contains(merge.sha, run.head_sha);
    const fulls = after(fullRuns);
    const canaries = after(canaryRuns);
    const dispatch = fulls.find(
      (run) =>
        run.event === "workflow_dispatch" &&
        run.createdMs <= mergedMs + DISPATCH_DEADLINE_MS &&
        lane.has(loginKey(run.actor?.login)) &&
        ["green", "flake"].includes(outcome(run, true).state) &&
        relevant(run),
    );
    const canary = dispatch && canaries.find((run) => outcome(run, false).state === "green" && relevant(run));
    const verifiedAt = canary ? Math.max(dispatch.createdMs, canary.createdMs) : Number.POSITIVE_INFINITY;
    const deadline = mergedMs + DISPATCH_DEADLINE_MS;
    const timely = fulls.some((run) => run.event === "workflow_dispatch" && run.createdMs <= deadline && lane.has(loginKey(run.actor?.login)) && relevant(run));
    const result = { failures: [], unsettled: false, verified: Boolean(canary) };
    if (!timely && throughMs > deadline) {
      result.failures.push({ check: "dispatch deadline", conclusion: "no dispatch run by a lane identity within 6 h", at: isoSeconds(deadline) });
    }
    for (const [runs, attributable] of [
      [fulls, true],
      [canaries, false],
    ]) {
      for (const run of runs.filter((r) => r.createdMs <= verifiedAt)) {
        const { state, conclusion } = outcome(run, attributable);
        if (state === "red" && relevant(run)) result.failures.push({ check: run.check, conclusion, at: run.updated_at });
        else if (state === "pending" && relevant(run)) result.unsettled = true;
      }
    }
    return result;
  };
}

// run_number starts at 1 per workflow, rises with each new run, and a re-run keeps it (pointer:
// https://docs.github.com/en/actions/reference/workflows-and-actions/contexts, github.run_number;
// as of 2026-10-15; recheck if that definition changes). So the runs created in [loMs, hiMs],
// every event and branch, number consecutively unless one between them was deleted. A list
// filtered by `created` returns at most RUN_RESULT_LIMIT results (pointer: REST "List workflow
// runs for a workflow"; measured 2026-10-15, past them a page is empty and total_count reads 0,
// and total_count stops at 2,500), so a range holding more is read in halves. The list is newest
// first, but runs created in one second are not in run_number order (measured 2026-10-15), so a
// range's newest number is the highest on its first page and its oldest the lowest on its last
// page and the page before. A count that changes between those reads shifts the pages and could
// hide one deletion, so it refuses, as does any answer that does not fit.
const RUN_RESULT_LIMIT = 1000;
function checkRunNumbers(gh, repo, workflow, loMs, hiMs) {
  const read = (lo, hi, page) => {
    const range = encodeURIComponent(`${isoSeconds(lo)}..${isoSeconds(hi)}`);
    const body = gh(`repos/${repo}/actions/workflows/${workflow}/runs?created=${range}&per_page=${PAGE}&page=${page}`);
    if (!Number.isInteger(body?.total_count) || !Array.isArray(body.workflow_runs)) throw new PublishError(`gh api ${workflow} runs: no total_count or workflow_runs`);
    const numbers = body.workflow_runs.map((run) => {
      if (!Number.isInteger(run?.run_number) || run.run_number < 1) throw new PublishError(`refusing to publish: a ${workflow} run created in the window has no run_number`);
      return run.run_number;
    });
    return { total: body.total_count, numbers };
  };
  const joined = (a, b) => {
    if (!a || !b) return a ?? b;
    if (b.oldest !== a.newest + 1) throw new EvidenceGone(`run-deleted: ${workflow} runs ${a.newest + 1}..${b.oldest - 1} are missing between runs created in the window`);
    return { oldest: a.oldest, newest: b.newest };
  };
  const span = (lo, hi) => {
    const { total, numbers: newer } = read(lo, hi, 1);
    if (total === 0) return null;
    if (total > RUN_RESULT_LIMIT) {
      if (hi <= lo) throw new PublishError(`refusing to publish: over ${RUN_RESULT_LIMIT} ${workflow} runs created at ${isoSeconds(lo)}`);
      const mid = lo + Math.floor((hi - lo) / 2000) * 1000;
      return joined(span(lo, mid), span(mid + 1000, hi));
    }
    const last = Math.ceil(total / PAGE);
    const tail = (page) => {
      const later = read(lo, hi, page);
      if (later.total !== total) throw new PublishError(`refusing to publish: ${workflow} run count changed from ${total} to ${later.total} while reading runs created ${isoSeconds(lo)}..${isoSeconds(hi)}`);
      return later.numbers;
    };
    const older = last === 1 ? newer : [...(last > 2 ? tail(last - 1) : newer), ...tail(last)];
    if (newer.length === 0 || older.length === 0) throw new PublishError(`refusing to publish: ${workflow} lists ${total} runs created ${isoSeconds(lo)}..${isoSeconds(hi)} but returns none`);
    const [newest, oldest] = [Math.max(...newer), Math.min(...older)];
    if (newest - oldest + 1 > total) throw new EvidenceGone(`run-deleted: ${workflow} lists ${total} runs created ${isoSeconds(lo)}..${isoSeconds(hi)} numbered ${oldest}..${newest}`);
    if (newest - oldest + 1 < total) throw new PublishError(`refusing to publish: ${workflow} lists ${total} runs created ${isoSeconds(lo)}..${isoSeconds(hi)} numbered only ${oldest}..${newest}`);
    return { oldest, newest };
  };
  span(Math.ceil(loMs / 1000) * 1000, Math.floor(hiMs / 1000) * 1000);
}

// Issues, pulls and discussions share one number sequence, so a number missing between two created
// in the window was deleted (410 Gone, pointer: REST "Get an issue"; as of 2026-10-15), moved, or
// is a discussion, which reads 404 there (measured 2026-10-15). Anyone can open a discussion, so
// one is no gap unless a filer wrote it, which no filer should: converting an issue keeps it under
// its number and numbers the discussion anew, so the check only fails closed. The listing is
// newest first and stops at the first page reaching before the window.
const DISCUSSION_QUERY = "query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){discussion(number:$number){author{__typename login}}}}";
function checkIssueNumbers(gh, repo, sinceMs, throughMs, filers) {
  const [owner, name] = repo.split("/");
  const numbers = new Set();
  for (let page = 1; ; page += 1) {
    const items = gh(`repos/${repo}/issues?state=all&sort=created&direction=desc&per_page=${PAGE}&page=${page}`);
    if (!Array.isArray(items)) throw new PublishError(`gh api repos/${repo}/issues: expected an array`);
    let before = false;
    for (const item of items) {
      if (!Number.isInteger(item?.number)) throw new PublishError(`gh api repos/${repo}/issues: an item without a number`);
      const created = ms(item.created_at, `issue #${item.number}`);
      if (created < sinceMs) before = true;
      else if (created <= throughMs) numbers.add(item.number);
    }
    if (before || items.length < PAGE) break;
  }
  const sorted = [...numbers].sort((a, b) => a - b);
  for (let n = sorted[0] + 1; n < sorted.at(-1); n += 1) {
    if (numbers.has(n)) continue;
    let issue;
    try {
      issue = gh(`repos/${repo}/issues/${n}`);
    } catch (error) {
      if (/\(HTTP 410\)/.test(error?.message)) throw new EvidenceGone(`issue-deleted: #${n} reads 410 Gone between issues created in the window`);
      if (!/\(HTTP 404\)/.test(error?.message)) throw error;
      const discussion = gh("graphql", { query: DISCUSSION_QUERY, variables: { owner, name, number: n } })?.data?.repository?.discussion;
      if (discussion && !filers.includes(actorKey(discussion.author))) continue;
    }
    if (issue?.number !== n || !String(issue.repository_url ?? "").toLowerCase().endsWith(`/repos/${repo.toLowerCase()}`)) {
      throw new EvidenceGone(`issue-missing: #${n} is not listed between issues created in the window and does not read back as this repository's`);
    }
  }
}

// The demotion records post-merge-demotion-alert.yml files (and babysit_postmerge.py files under
// the lane identity), read as babysit_merge_policy.py read_demotion finds candidates: issues a
// filer opened, updated inside the window, whose body or any revision carries the marker, or
// whose edit history is not whole. Each yields its creation and every repeat-failure comment a
// filer posted; anyone can comment on a public record, and the alert workflow reads only its own.
const DEMOTION_MARKER = "<!-- babysit-merge-demotion";
const DEMOTION_FILER = "github-actions[bot]";
const DEMOTION_AGAIN = "The post-merge check found this failure again: ";
const DEMOTION_QUERY =
  "query($owner:String!,$name:String!,$author:String!,$since:DateTime!,$c:String){repository(owner:$owner,name:$name){" +
  "issues(first:50,after:$c,filterBy:{createdBy:$author,since:$since}){pageInfo{hasNextPage endCursor} nodes{number createdAt updatedAt body " +
  "userContentEdits(first:100){totalCount nodes{diff deletedAt}}}}}}";
const DEMOTION_PAGE_LIMIT = 30;

function demotionRecords(gh, owner, name, filers, since) {
  const out = [];
  for (const author of filers) {
    let cursor = null;
    for (let page = 0; ; page += 1) {
      if (page === DEMOTION_PAGE_LIMIT) throw new PublishError(`refusing to publish: issues by ${author} run past ${DEMOTION_PAGE_LIMIT} pages`);
      const variables = { owner, name, author, since, ...(cursor ? { c: cursor } : {}) };
      const issues = gh("graphql", { query: DEMOTION_QUERY, variables })?.data?.repository?.issues;
      if (!Array.isArray(issues?.nodes) || typeof issues.pageInfo?.hasNextPage !== "boolean") throw new PublishError(`issues by ${author}: no issue page`);
      for (const issue of issues.nodes) {
        const edits = issue?.userContentEdits;
        const whole = Array.isArray(edits?.nodes) && edits.totalCount === edits.nodes.length && edits.nodes.every((e) => typeof e?.diff === "string" && !e.deletedAt);
        if (whole && ![issue?.body, ...edits.nodes.map((e) => e.diff)].some((text) => String(text ?? "").includes(DEMOTION_MARKER))) continue;
        const at = [{ at: issue.createdAt, conclusion: "demotion record filed" }];
        for (const c of pages(gh, `repos/${owner}/${name}/issues/${issue.number}/comments`)) {
          if (filers.includes(loginKey(c?.user?.login)) && String(c?.body ?? "").startsWith(DEMOTION_AGAIN)) at.push({ at: c.created_at, conclusion: "repeat failure" });
        }
        for (const sighting of at) out.push({ issue: issue.number, ...sighting });
      }
      if (!issues.pageInfo.hasNextPage) break;
      cursor = issues.pageInfo.endCursor;
      if (typeof cursor !== "string" || !cursor) throw new PublishError(`issues by ${author}: a next page with no cursor`);
    }
  }
  return out;
}

export function collect({ repo, since, through, laneLogins, gateChecks, aiReviewers = [], missedBlockingLabel = MISSED_BLOCKING_LABEL, gh = realGh }) {
  const gate = new Set(gateChecks ?? []);
  if (gate.size === 0) throw new PublishError("at least one --gate-check naming the post-merge gate is required");
  const sinceMs = instant(since, "--since");
  const throughMs = Math.min(instant(through, "--through"), Date.now());
  const lane = new Set(laneLogins.map(loginKey));
  // babysit_merge_policy.py is_human, without its permission read: a User that is not a lane
  // login, `github-actions` or a `[bot]` login. A null actor is not human.
  const human = (actor) =>
    actor?.__typename === "User" && !lane.has(actorKey(actor)) && loginKey(actor.login) !== "github-actions" && !/\[bot\]$/i.test(actor.login ?? "");
  const inWindow = (at) => typeof at === "string" && Date.parse(at) >= sinceMs && Date.parse(at) <= throughMs;
  const events = new Map();
  const addEvent = (cell, event, at) => {
    ms(at, `a ${event} event`);
    const record = { cell, event, at };
    events.set(eventKey(record), record);
  };

  const branch = gh(`repos/${repo}`)?.default_branch;
  if (!branch) throw new PublishError(`gh api repos/${repo}: no default_branch`);
  for (const workflow of [FULL_RUN_WORKFLOW, CANARY_WORKFLOW]) checkRunNumbers(gh, repo, workflow, sinceMs, throughMs);
  const filers = [...new Set([DEMOTION_FILER, ...laneLogins].map(loginKey))];
  checkIssueNumbers(gh, repo, sinceMs, throughMs, filers);
  // Merges into the default branch only (babysit_postmerge.py _merged_since). Created-ascending
  // order is stable while paging: an update moves no PR between pages.
  const seen = new Set();
  const merged = pages(gh, `repos/${repo}/pulls?state=closed&base=${encodeURIComponent(branch)}&sort=created&direction=asc`).filter(
    (pr) => inWindow(pr.merged_at) && !seen.has(pr.number) && seen.add(pr.number),
  );

  const issueEvents = new Map();
  const eventsOf = (number) => {
    if (!issueEvents.has(number)) issueEvents.set(number, pages(gh, `repos/${repo}/issues/${number}/events`));
    return issueEvents.get(number);
  };
  const [owner, name] = repo.split("/");

  // The class at merge: labels of the PR and of the issues linked at merge, each rebuilt as of
  // mergedAt. Links: the current set with later Connected/Disconnected events undone; a body
  // edited after the merge leaves the closing-keyword links unknown, so the class is too.
  const classAtMerge = (g, timeline) => {
    const atMs = ms(g.mergedAt, `#${g.number} mergedAt`);
    if (g.lastEditedAt && ms(g.lastEditedAt, `#${g.number} lastEditedAt`) > atMs) return { cls: null, reason: "PR body edited after the merge: closing-keyword links unknown" };
    const linked = new Map();
    for (const issue of onePage(g.closingIssuesReferences, `closingIssuesReferences of #${g.number}`)) {
      linked.set(issue.number, onePage(issue.labels, `labels of issue #${issue.number}`).map((label) => label?.name));
    }
    // A ConnectedEvent on a PR timeline names the issue as `subject` (recorded from cli/cli #14616);
    // any other shape after the merge leaves the links unknown.
    const laterLinks = timeline
      .filter((e) => ["ConnectedEvent", "DisconnectedEvent"].includes(e.__typename) && ms(e.createdAt, "a link event") > atMs)
      .sort((a, b) => ms(b.createdAt, "a link event") - ms(a.createdAt, "a link event"));
    if (laterLinks.some((e) => e.subject?.__typename !== "Issue" || !Number.isInteger(e.subject.number))) {
      return { cls: null, reason: "a link event after the merge has an unrecognized shape: links unknown" };
    }
    for (const e of laterLinks) {
      if (e.__typename === "ConnectedEvent") linked.delete(e.subject.number);
      else if (!linked.has(e.subject.number)) {
        const labels = gh(`repos/${repo}/issues/${e.subject.number}`)?.labels;
        if (!Array.isArray(labels)) throw new IncompleteError(`labels of issue #${e.subject.number} unreadable`);
        linked.set(e.subject.number, labels.map((label) => label?.name));
      }
    }
    const names = labelsAsOf(onePage(g.labels, `labels of #${g.number}`).map((label) => label?.name), eventsOf(g.number), atMs);
    for (const [issue, labels] of linked) names.push(...labelsAsOf(labels, eventsOf(issue), atMs));
    const cls = workClass(names);
    return { cls, reason: cls ? null : "no work-class label at merge" };
  };

  // Autonomy as babysit_merge_policy.py derive_auto_merge reads it: the latest
  // AddedToMergeQueueEvent's actor and enqueuer, or merged_by when the merge bypassed the
  // queue; any of them null or not human makes the merge autonomous.
  const autonomousOf = (g, timeline) => {
    const queued = timeline.filter((e) => e.__typename === "AddedToMergeQueueEvent").sort((a, b) => ms(a.createdAt, "a merge-queue event") - ms(b.createdAt, "a merge-queue event"));
    const actors = queued.length > 0 ? [queued.at(-1).actor, queued.at(-1).enqueuer] : [g.mergedBy];
    const byIdentity = actors.some((actor) => actor && lane.has(actorKey(actor)));
    return { autonomous: actors.some((actor) => !human(actor)) || lane.has(actorKey(g.mergedBy)), byIdentity };
  };

  const details = new Map();
  const record = (number) => {
    if (!details.has(number)) {
      const g = gh("graphql", { query: PULL_QUERY, variables: { owner, name, number } })?.data?.repository?.pullRequest;
      if (!g?.mergedAt) throw new UnresolvableError(`#${number} is not a merged pull request`);
      ms(g.mergedAt, `#${number} mergedAt`);
      const base = { number, mergedAt: g.mergedAt, sha: g.mergeCommit?.oid, head: g.headRefOid, reverted: false };
      // A page a lane can make incomplete or unreadable leaves the merge unclassed-autonomous.
      try {
        const timeline = onePage(g.timelineItems, `timeline of #${number}`);
        details.set(number, { ...base, ...classAtMerge(g, timeline), ...autonomousOf(g, timeline) });
      } catch (error) {
        if (!(error instanceof IncompleteError)) throw error;
        // Who enqueued it is unknown too, so it also owes a pin.
        details.set(number, { ...base, cls: null, reason: "a linked-issue, label or timeline page is unreadable or incomplete: class unknown", autonomous: true, byIdentity: true });
      }
    }
    return details.get(number);
  };
  // Tracked: C2/C3 merges, and autonomous merges with no class, which are never counted toward
  // a positive term but whose contrary events go against every cell.
  const tracked = merged.map((pr) => record(pr.number)).filter((r) => ["C2", "C3"].includes(r.cls) || (r.autonomous && r.cls === null));
  const cellsOf = (r) => (r.cls ? [`${r.cls}-auto-merge`] : CELLS);
  const bySha = new Map(tracked.map((r) => [r.sha, r]));

  // Reverts, from merged PR bodies and default-branch commit messages; earliest per target.
  const own = repo.toLowerCase();
  const revertsOf = (text) => {
    const targets = [];
    for (const m of (text ?? "").matchAll(/\bReverts\s+(?:([\w.-]+\/[\w.-]+))?#(\d+)/g)) {
      // A GraphQL Int is at most 2^31 - 1; a longer digit string is never parsed into a Number.
      if (!m[1] || m[1].toLowerCase() === own) {
        const valid = /^[1-9]\d{0,9}$/.test(m[2]) && BigInt(m[2]) <= 2147483647n;
        targets.push(valid ? { number: Number(m[2]) } : { invalid: m[2] });
      }
    }
    for (const m of (text ?? "").matchAll(/This reverts commit ([0-9a-f]{40})/g)) targets.push({ sha: m[1] });
    return targets;
  };
  const reverts = [];
  const unresolvedReverts = [];
  const gateFailures = [];
  // Every revert counts, whoever merged or enqueued it (owner decision, #4588).
  for (const pr of merged) {
    const targets = revertsOf(pr.body);
    for (const target of targets) reverts.push({ ...target, at: pr.merged_at });
    if (targets.length === 0 && /^revert\b/i.test(pr.title ?? "")) unresolvedReverts.push({ number: pr.number, title: pr.title });
  }
  const commits = pages(gh, `repos/${repo}/commits?since=${new Date(sinceMs).toISOString()}&until=${new Date(throughMs).toISOString()}`);
  for (const commit of commits) {
    for (const target of revertsOf(commit.commit?.message)) reverts.push({ ...target, at: commit.commit?.committer?.date });
  }
  const firstRevert = new Map();
  for (const revert of reverts) {
    if (!inWindow(revert.at)) continue;
    if (revert.invalid !== undefined) {
      unresolvedReverts.push({ target: revert.invalid, reason: "not a pull request number (a positive GraphQL Int)" });
      continue;
    }
    let number = revert.number;
    if (number === undefined) {
      const known = bySha.get(revert.sha);
      try {
        number = known ? known.number : gh(`repos/${repo}/commits/${revert.sha}/pulls`).find((pr) => pr.merged_at)?.number;
      } catch (error) {
        if (!(error instanceof UnresolvableError)) throw error;
        unresolvedReverts.push({ target: revert.sha, reason: "no commit found for this SHA" });
        continue;
      }
      if (number === undefined) {
        unresolvedReverts.push({ target: revert.sha, reason: "no merged pull request for this commit" });
        continue;
      }
    }
    if (!firstRevert.has(number) || Date.parse(revert.at) < Date.parse(firstRevert.get(number))) firstRevert.set(number, revert.at);
  }
  for (const [number, at] of firstRevert) {
    let target;
    try {
      target = record(number);
    } catch (error) {
      if (!(error instanceof UnresolvableError)) throw error;
      unresolvedReverts.push({ target: number, reason: "not a merged pull request" });
      continue;
    }
    if (target.autonomous && (["C2", "C3"].includes(target.cls) || target.cls === null)) {
      target.reverted = true;
      for (const cell of cellsOf(target)) addEvent(cell, "reverted-merge", at);
    }
  }

  const judgeWorkflows = postMergeRuns(gh, repo, branch, tracked.filter((c) => c.autonomous), { lane, throughMs });

  // check()'s read-back for a merge a lane identity enqueued.
  const readBack = (r) => {
    const deadline = ms(r.mergedAt, `#${r.number} mergedAt`) + DISPATCH_DEADLINE_MS;
    const pinned = readPin(gh, owner, name, r.number, lane);
    if (pinned === null) {
      return throughMs > deadline
        ? { failure: { check: "pin read-back", conclusion: "no unedited pin comment by a lane identity", at: isoSeconds(deadline) } }
        : { pending: true };
    }
    return pinned === r.head ? {} : { failure: { check: "pin read-back", conclusion: `headRefOid ${r.head} is not the pinned ${pinned}`, at: r.mergedAt } };
  };

  // Post-merge gate on each autonomous merge commit: the --gate-check runs and status contexts.
  // A run that did not finish green or red (cancelled, action_required, stale) fails the gate
  // unless a later run of the same check succeeded, so cancelling a red run cannot erase it.
  // Then the post-merge workflow runs on later SHAs containing the merge (postMergeRuns).
  for (const r of tracked.filter((c) => c.autonomous)) {
    const wf = judgeWorkflows(r);
    const pin = r.byIdentity ? readBack(r) : {};
    if (pin.failure) wf.failures.push(pin.failure);
    if (pin.pending) wf.unsettled = true;
    for (const failure of wf.failures) {
      for (const cell of cellsOf(r)) addEvent(cell, "gate-failure", failure.at);
      gateFailures.push({ number: r.number, ...failure });
    }
    const runs = pages(gh, `repos/${repo}/commits/${r.sha}/check-runs?filter=all`, "check_runs").filter((run) => gate.has(run.name));
    const statuses = pages(gh, `repos/${repo}/commits/${r.sha}/statuses`).filter((status) => gate.has(status.context));
    const outcome = (run) => {
      if (run.status !== "completed") return "unsettled";
      if (GATE_FAILED.has(run.conclusion)) return "failed";
      if (GATE_OK.has(run.conclusion)) return "ok";
      const rerunGreen = runs.some(
        (o) => o !== run && o.name === run.name && o.status === "completed" && o.conclusion === "success" && Date.parse(o.completed_at) > Date.parse(run.completed_at ?? 0),
      );
      return rerunGreen ? "ok" : "failed";
    };
    const failedRuns = runs.filter((run) => outcome(run) === "failed");
    const failedStatuses = statuses.filter((status) => STATUS_FAILED.has(status.state));
    for (const cell of cellsOf(r)) {
      for (const run of failedRuns) addEvent(cell, "gate-failure", run.completed_at ?? r.mergedAt);
      for (const status of failedStatuses) addEvent(cell, "gate-failure", status.created_at);
    }
    for (const run of failedRuns) gateFailures.push({ number: r.number, check: run.name, conclusion: run.conclusion, at: run.completed_at ?? r.mergedAt });
    for (const status of failedStatuses) gateFailures.push({ number: r.number, check: status.context, conclusion: status.state, at: status.created_at });
    const latest = new Map();
    for (const status of [...statuses].sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))) {
      if (!latest.has(status.context)) latest.set(status.context, status.state);
    }
    // Passed only where check() would call the merge verified, with nothing pending.
    const settled =
      wf.verified &&
      !wf.unsettled &&
      runs.every((run) => outcome(run) === "ok") &&
      [...latest.values()].every((state) => state === "success");
    r.gate = failedRuns.length + failedStatuses.length + wf.failures.length > 0 ? "failed" : settled ? "passed" : "unsettled";
  }

  // Human-confirmed missed-blocking AI-review findings, from the label timeline.
  for (const r of tracked.filter((c) => c.cls === "C3" || c.autonomous)) {
    const confirmed = eventsOf(r.number).filter(
      (e) => e.event === "labeled" && e.label?.name === missedBlockingLabel && e.actor?.type === "User" && !lane.has(loginKey(e.actor.login)) && inWindow(e.created_at),
    );
    r.missedBlocking = confirmed.length > 0 ? 1 : 0;
    const cells = r.cls === "C3" ? ["C3-ai-review-blocking"] : r.cls === "C2" ? ["C2-auto-merge"] : CELLS;
    for (const e of confirmed) for (const cell of cells) addEvent(cell, "verification-divergence", e.created_at);
  }
  const reviewers = new Set(aiReviewers);
  if (reviewers.size > 0) {
    for (const r of tracked.filter((c) => c.cls === "C3")) {
      r.aiReviewed = pages(gh, `repos/${repo}/pulls/${r.number}/reviews`).some((review) => reviewers.has(review.user?.login));
    }
  }

  // Which merges a record's SHA contains is not read: it is contrary for every cell.
  for (const record of demotionRecords(gh, owner, name, filers, new Date(sinceMs).toISOString())) {
    if (!inWindow(record.at)) continue;
    for (const cell of CELLS) addEvent(cell, "gate-failure", record.at);
    gateFailures.push({ issue: record.issue, check: "babysit-merge-demotion", conclusion: record.conclusion, at: record.at });
  }

  const sorted = [...events.values()].sort((a, b) => Date.parse(a.at) - Date.parse(b.at) || eventKey(a).localeCompare(eventKey(b)));
  return {
    repo,
    since,
    through: new Date(throughMs).toISOString(),
    events: sorted,
    unresolvedReverts,
    gateFailures,
    unclassedAutonomous: [...details.values()]
      .filter((r) => r.autonomous && r.cls === null && (tracked.includes(r) || r.reverted))
      .map((r) => ({ number: r.number, reason: r.reason })),
    cells: report(tracked, sorted, reviewers.size > 0),
  };
}

function term(name, value, threshold, pass, detail) {
  return { term: name, value, threshold, pass, ...(detail ? { detail } : {}) };
}

function windowOf(records) {
  if (records.length === 0) return { from: null, to: null, days: 0 };
  const times = records.map((r) => Date.parse(r.mergedAt));
  const [from, to] = [Math.min(...times), Math.max(...times)];
  return { from: new Date(from).toISOString(), to: new Date(to).toISOString(), days: Math.floor(((to - from) / DAY_MS) * 100) / 100 };
}

function gateTerm(name, records) {
  const detail = { passed: 0, failed: 0, unsettled: 0, total: records.length };
  for (const r of records) detail[r.gate] += 1;
  const value = records.length === 0 ? null : Math.floor((detail.passed / records.length) * 10000) / 100;
  return term(name, value, "100%", records.length > 0 && detail.passed === records.length, detail);
}

function cell(window, terms) {
  return { window, pass: terms.every((t) => t.pass), terms };
}

// Thresholds are work-classes.md's suggested defaults.
function report(counted, events, reviewsMeasured) {
  const c2 = counted.filter((r) => r.cls === "C2" && r.autonomous);
  const c3 = counted.filter((r) => r.cls === "C3" && r.autonomous);
  const c3All = counted.filter((r) => r.cls === "C3");
  const c2Window = windowOf(c2);
  const reverted = (records) => records.filter((r) => r.reverted).length;
  const missed = (records) => records.reduce((sum, r) => sum + (r.missedBlocking ?? 0), 0);
  const c2Demotions = events.filter((e) => e.cell === "C2-auto-merge").length;
  const reviewed = c3All.filter((r) => r.aiReviewed);
  return {
    "C2-auto-merge": cell(c2Window, [
      term("autonomous C2 completions", c2.length, ">= 20", c2.length >= 20),
      term("window days", c2Window.days, ">= 14", c2Window.days >= 14),
      gateTerm("deterministic-gate pass", c2),
      term("reverted merges", reverted(c2), "0", reverted(c2) === 0),
    ]),
    "C3-auto-merge": cell(windowOf([...c2, ...c3]), [
      term("autonomous C2 merges", c2.length, ">= 20", c2.length >= 20),
      term("C2 window days", c2Window.days, ">= 14", c2Window.days >= 14),
      term("C2 demotion events", c2Demotions, "0", c2Demotions === 0),
      term("autonomous C3 completions", c3.length, ">= 10", c3.length >= 10),
      gateTerm("C3 deterministic-gate pass", c3),
      term("C3 reverted merges", reverted(c3), "0", reverted(c3) === 0),
      term("C3 human-confirmed missed-blocking findings", missed(c3), "0", missed(c3) === 0),
    ]),
    "C3-ai-review-blocking": cell(windowOf(c3All), [
      reviewsMeasured
        ? term("advisory AI reviews on C3", reviewed.length, ">= 30", reviewed.length >= 30)
        : term("advisory AI reviews on C3", null, ">= 30", false, { unmeasured: "no --ai-reviewer given" }),
      term("human-confirmed missed-blocking findings", missed(c3All), "0", missed(c3All) === 0),
    ]),
  };
}

function sha256(text) {
  return createHash("sha256").update(text).digest("hex");
}

// "wx" refuses a temp file that already exists rather than overwrite or remove it.
function writeTemp(path, text) {
  const temp = `${path}.${process.pid}.tmp`;
  writeFileSync(temp, text, { flag: "wx" });
  return temp;
}

function readIfPresent(path) {
  try {
    return readFileSync(path, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw new PublishError(`cannot read ${path}: ${error.message}`);
  }
}

export function publish(outDir, events, through, now = new Date(), { rename = renameSync } = {}) {
  const file = join(outDir, "evidence.json");
  const metaFile = join(outDir, "evidence.meta.json");
  const previous = readIfPresent(file);
  if (previous !== null) {
    let prior;
    try {
      prior = JSON.parse(previous);
    } catch (error) {
      throw new PublishError(`refusing to publish: ${file} is not JSON (${error.message}), so the superset check cannot run`);
    }
    if (!Array.isArray(prior)) throw new PublishError(`refusing to publish: ${file} is not a JSON array, so the superset check cannot run`);
    let priorMeta;
    try {
      priorMeta = JSON.parse(readIfPresent(metaFile));
    } catch {
      priorMeta = null;
    }
    if (priorMeta?.sha256 !== sha256(previous)) {
      throw new PublishError(`refusing to publish: ${file} does not match the sha256 in its sidecar ${metaFile} (missing, unreadable or different)`);
    }
    const keys = new Set(events.map(eventKey));
    const dropped = prior.filter((event) => !keys.has(eventKey(event)));
    if (dropped.length > 0) {
      throw new PublishError(`refusing to publish: the new events drop ${dropped.length} previously published event(s): ${dropped.map(eventKey).join(", ")}`);
    }
  }
  const text = `${JSON.stringify(events, null, 2)}\n`;
  const meta = { generated_at: now.toISOString(), through, sha256: sha256(text), prev_sha256: previous === null ? null : sha256(previous) };
  const eventsTemp = writeTemp(file, text);
  let metaTemp;
  let backup;
  try {
    metaTemp = writeTemp(metaFile, `${JSON.stringify(meta, null, 2)}\n`);
    if (previous !== null) backup = writeTemp(`${file}.prev`, previous);
    rename(eventsTemp, file);
  } catch (error) {
    for (const temp of [eventsTemp, metaTemp, backup]) if (temp) rmSync(temp, { force: true });
    throw error;
  }
  try {
    rename(metaTemp, metaFile);
  } catch (error) {
    // Put the pair back as it was. An interruption before this point still leaves a pair the
    // next run refuses on the sha256 check: fail closed.
    if (backup) rename(backup, file);
    else rmSync(file, { force: true });
    rmSync(metaTemp, { force: true });
    throw error;
  }
  if (backup) rmSync(backup, { force: true });
  return meta;
}

function main() {
  let values;
  try {
    ({ values } = parseArgs({
      options: {
        repo: { type: "string" },
        since: { type: "string" },
        through: { type: "string" },
        "lane-login": { type: "string", multiple: true },
        "gate-check": { type: "string", multiple: true },
        "ai-reviewer": { type: "string", multiple: true },
        "missed-blocking-label": { type: "string", default: MISSED_BLOCKING_LABEL },
        out: { type: "string" },
      },
    }));
    if (!/^[\w.-]+\/[\w.-]+$/.test(values.repo ?? "") || !values.since || !values["lane-login"]?.length || !values["gate-check"]?.length) {
      throw new PublishError("--repo <owner/name>, --since <ISO>, at least one --lane-login and at least one --gate-check are required");
    }
  } catch (error) {
    process.stderr.write(`usage: ${error.message}\n`);
    process.exit(2);
  }
  try {
    const result = collect({
      repo: values.repo,
      since: values.since,
      through: values.through ?? new Date().toISOString(),
      laneLogins: values["lane-login"],
      gateChecks: values["gate-check"],
      aiReviewers: values["ai-reviewer"] ?? [],
      missedBlockingLabel: values["missed-blocking-label"],
    });
    if (values.out) publish(values.out, result.events, result.through);
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } catch (error) {
    process.stderr.write(`publish-promotion-evidence: ${error.message}\n`);
    process.exit(error instanceof PublishError && error.message.startsWith("refusing") ? 1 : 2);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
