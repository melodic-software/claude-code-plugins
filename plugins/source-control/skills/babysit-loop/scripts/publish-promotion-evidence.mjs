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
// Report mode (no --out) prints {repo, since, through, events, unresolvedReverts, gateFailures, noRungAutonomous, cells} to
// stdout and writes nothing. --through defaults to, and is clamped to, now. With --out it also
// writes <dir>/evidence.json (the events array) and <dir>/evidence.meta.json ({generated_at,
// through, sha256, prev_sha256}). Both temp files are written before either rename, the events
// file renamed first. It refuses when an existing evidence.json is not a JSON array, has no
// sidecar or does not match the sidecar's sha256, holds a contrary event the new array lacks, or
// holds an event whose `discovered` the new array changes, except a contrary event published
// without one gaining the previous generated_at; a re-earned event the new array lacks is carried
// forward instead. It refuses a new contrary event whose `discovered` is missing or does not parse.
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
// Anything a lane can write into a PR or commit degrades to a listing or to no-rung-autonomous,
// never to a refused publish. What refuses is GitHub itself being unreadable: a failed read, an
// unparsable date, a compare that is neither ahead, identical nor behind.
//
// What counts (judgment where the contract names no GitHub source):
// - An autonomous merge's rung is the one its lane pin names (`rung=C2|C3`, babysit_postmerge.py
//   pin_comment, or enable-auto-merge.mjs pinBody for the pr-merge lane's native arm): the
//   effective rung the gate enqueued or armed it under. No work-class label is read. A native
//   auto-merge owes no pin but is credited by one the same way. A merge counts toward its rung's
//   cells: C2 merges toward the C2 terms, C3 merges toward the C3 terms. An autonomous merge with
//   no rung (no unedited lane pin at its head, a pin of the older shape naming none, another
//   bot's merge, or an unreadable timeline page) is
//   listed in noRungAutonomous, never counted toward a positive term, and each of its contrary
//   events is emitted against every promotable cell. A human merge has no rung.
// - C3-ai-review-blocking's positive evidence (its advisory-review count and its window) comes
//   from autonomous rung-C3 merges only; its missed-blocking term counts confirmed misses on those
//   and on human merges, so a human merge can only count against it. Autonomous C2 and no-rung
//   merges are in neither. C3-auto-merge and the C2 terms count only autonomous merges of their
//   rung.
// - reverted-merge: an autonomous merge named by a merged PR body or a default-branch
//   commit as `Reverts <owner/repo>#<n>` (GitHub's revert button) or `This reverts commit
//   <sha>` (git revert); one event at each date a revert of the merge is seen, so a revert found
//   later with an earlier date adds an event rather than moving a published one. A merged PR
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
//   check run `Silent-Revert Canary`, `Silent-revert canary` on a commit tested before the
//   rename, on the merge commit; pass both as --gate-check) and the full pr-require-checks.yml run
//   (aggregate job `CI Status`), scheduled or dispatched on a later SHA containing the merge. This
//   script reads those workflow runs the same way (postMergeRuns) and, on the merge commit itself,
//   the --gate-check check runs and contexts. Among the latter, every check run (filter=all, so a run later
//   re-run green still counts) concluding failure, timed_out or startup_failure, and every
//   status in state failure or error, whenever it completed. A run concluding cancelled,
//   action_required, stale or anything else not green also counts, unless a later run of the
//   same check name on that commit succeeded. The gate-pass term also fails while a run is in
//   progress or a context's latest status is not success.
// - verification-divergence: a human (a User actor outside --lane-login) applied
//   --missed-blocking-label to a merged PR, read from the label timeline, so removing the label
//   later does not undo it: against C2-auto-merge for a C2 merge, every cell for an autonomous
//   merge with no rung, and C3-ai-review-blocking otherwise (a C3 merge or a human merge).
// - A cell's window runs from its first counted merge to its last.
// - re-earned: {cell, event: "re-earned", at, since}, emitted when the cell's report() predicate
//   passes over only the merges after `since`, the latest `at` or `discovered` of any contrary
//   event against the cell or a prerequisite (reEarned). It lets a demoted cell re-promote with no
//   binding update.
// - discovered: with `prior` (the published events, which main reads for --out), each contrary
//   event carries {cell, event, at, discovered}: the run's `now` rounded up to a whole second the
//   first time its key is published, else the value the prior file holds. An event that file
//   holds without one (published before the field existed) is stamped once with that file's
//   generated_at, rounded up to a whole second. Report mode passes no prior and sets none.
//
// Event shape and vocabulary: the autonomy plugin's check-security-binding.mjs (/autonomy:setup),
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
// A page that is unreadable or has another page: the merge's autonomy and rung are unknown.
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
  "number headRefOid mergedAt mergeCommit{oid} mergedBy{__typename login} author{__typename login} isCrossRepository " +
  "timelineItems(first:100,itemTypes:[ADDED_TO_MERGE_QUEUE_EVENT]){pageInfo{hasNextPage} nodes{__typename " +
  "... on AddedToMergeQueueEvent{createdAt actor{__typename login} enqueuer{__typename login}}}} " +
  "autoMerge:timelineItems(itemTypes:[AUTO_MERGE_ENABLED_EVENT,AUTO_MERGE_DISABLED_EVENT],last:1){nodes{__typename " +
  "... on AutoMergeEnabledEvent{createdAt actor{__typename login}} ... on AutoMergeDisabledEvent{createdAt actor{__typename login}}}}}}}";
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

function eventKey(event) {
  return JSON.stringify(event.since === undefined ? [event.cell, event.event, event.at] : [event.cell, event.event, event.at, event.since]);
}

const byInstant = (a, b) => Date.parse(a.at) - Date.parse(b.at) || eventKey(a).localeCompare(eventKey(b));

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
// merge a lane identity enqueued, other than its own native auto-merge, the pin read-back
// (read_pin): no unedited lane pin once the deadline has passed (at the deadline), or a pinned
// SHA that is not headRefOid (at the merge).
const FULL_RUN_WORKFLOW = "pr-require-checks.yml";
const CANARY_WORKFLOW = "post-merge-detect-silent-revert.yml";
const DISPATCH_DEADLINE_MS = 6 * 3_600_000;

function isoSeconds(msValue) {
  return new Date(msValue).toISOString().replace(/\.000Z$/, "Z");
}

const ceilSecond = (msValue) => Math.ceil(msValue / 1000) * 1000;
// The one `discovered` an event published without one may gain: its file's generated_at.
const legacyDiscovered = (generatedMs) => isoSeconds(ceilSecond(generatedMs));

// babysit_postmerge.py read_pin: the newest comment by the identity whose first line is the pin
// marker, read through at most PIN_PAGE_LIMIT pages; none, an edited one, or a longer thread is
// no pin. A pin is {sha, rung}: the rung the gate enqueued under, null in the older shape.
const PIN_RE = /^<!-- babysit-merge-pin sha=([0-9a-f]{40})(?: rung=(C2|C3))? -->$/;
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
      if (!last || last.lastEditedAt) return null;
      const [, sha, rung = null] = PIN_RE.exec(firstLine(last.body));
      return { sha, rung };
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
  // check()'s _Context.on_branch: a run's head_branch is only a name, which a run on a tag named
  // like the branch carries too, so a run counts only when its commit is on refs/heads/<branch>.
  // Residual: the tip is read here, before the run listings, where check() reads it after them,
  // so a run on a commit that lands between the two reads is off the branch here alone.
  const ref = gh(`repos/${repo}/git/ref/heads/${branch.split("/").map(encodeURIComponent).join("/")}`);
  const tip = ref?.object?.sha;
  if (!/^[0-9a-f]{40}$/.test(tip ?? "")) throw new PublishError(`refusing to publish: branch ${branch} has no tip commit`);
  const onBranches = new Map();
  const onBranch = (sha) => {
    if (!/^[0-9a-f]{40}$/.test(sha ?? "")) return false;
    if (!onBranches.has(sha)) {
      const status = sha === tip ? "identical" : gh(`repos/${repo}/compare/${sha}...${tip}?per_page=1&page=1`)?.status;
      if (!["ahead", "identical", "behind", "diverged"].includes(status)) {
        throw new PublishError(`refusing to publish: compare ${sha}...${tip} is ${JSON.stringify(status)}, so whether that run is on ${branch} is unknown`);
      }
      onBranches.set(sha, status === "ahead" || status === "identical");
    }
    return onBranches.get(sha);
  };
  const list = (workflow, event) =>
    pages(gh, `repos/${repo}/actions/workflows/${workflow}/runs?event=${event}&branch=${encodeURIComponent(branch)}&created=${created}`, "workflow_runs")
      .map((run) => ({ ...run, createdMs: ms(run.created_at, `run ${run.id}`), check: `${workflow} ${event}` }))
      .filter((run) => run.head_branch === branch && run.createdMs >= floor && onBranch(run.head_sha));
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
  span(ceilSecond(loMs), Math.floor(hiMs / 1000) * 1000);
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

export function collect({ repo, since, through, laneLogins, gateChecks, aiReviewers = [], missedBlockingLabel = MISSED_BLOCKING_LABEL, gh = realGh, prior = null, priorGeneratedAt = null, now = new Date() }) {
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

  // Each lane pin read once: the read-back and the rung share it.
  const pins = new Map();
  const pinOf = (number) => {
    if (!pins.has(number)) pins.set(number, readPin(gh, owner, name, number, lane));
    return pins.get(number);
  };

  // The rung an autonomous merge ran under, from the lane pin at its head; a human merge has none.
  // A native auto-merge owes no pin, but the pr-merge lane posts one when it arms, read the same way.
  const rungOf = (g, { autonomous, byIdentity }) => {
    if (!autonomous) return { rung: null, reason: null };
    if (!byIdentity) return { rung: null, reason: "not enqueued by a lane identity: no pin" };
    const pin = pinOf(g.number);
    if (pin === null) return { rung: null, reason: "no unedited lane pin" };
    if (pin.sha !== g.headRefOid) return { rung: null, reason: "the pin names another head" };
    return pin.rung ? { rung: pin.rung, reason: null } : { rung: null, reason: "the pin names no rung" };
  };

  // Autonomy as babysit_merge_policy.py derive_auto_merge reads it: the latest
  // AddedToMergeQueueEvent's actor and enqueuer, or merged_by when the merge bypassed the
  // queue; any of them null or not human makes the merge autonomous.
  const autonomousOf = (g, timeline) => {
    const queued = timeline.filter((e) => e.__typename === "AddedToMergeQueueEvent").sort((a, b) => ms(a.createdAt, "a merge-queue event") - ms(b.createdAt, "a merge-queue event"));
    const actors = queued.length > 0 ? [queued.at(-1).actor, queued.at(-1).enqueuer] : [g.mergedBy];
    const byIdentity = actors.some((actor) => actor && lane.has(actorKey(actor)));
    // babysit_postmerge.py native_auto_merge: a lane identity's own native auto-merge posts no
    // pin. One lane identity opened it from this repository, enqueued it, and made its newest
    // auto-merge enable or disable, an enable no later than the enqueue. When that identity
    // opened it from this repository, unreadable auto-merge events refuse the publish, as the
    // check reads them unreadable.
    const who = actorKey(g.author);
    const owned = byIdentity && lane.has(who) && actors.some((actor) => actor && actorKey(actor) === who) && g.isCrossRepository === false;
    if (owned && !Array.isArray(g.autoMerge?.nodes)) throw new PublishError(`refusing to publish: #${g.number} has no auto-merge events`);
    const armed = owned ? g.autoMerge.nodes.at(-1) : undefined;
    const native =
      armed?.__typename === "AutoMergeEnabledEvent" &&
      actorKey(armed.actor) === who &&
      (queued.length === 0 || ms(armed.createdAt, "an auto-merge event") <= ms(queued.at(-1).createdAt, "a merge-queue event"));
    return { autonomous: actors.some((actor) => !human(actor)) || lane.has(actorKey(g.mergedBy)), byIdentity, native };
  };

  const details = new Map();
  const record = (number) => {
    if (!details.has(number)) {
      const g = gh("graphql", { query: PULL_QUERY, variables: { owner, name, number } })?.data?.repository?.pullRequest;
      if (!g?.mergedAt) throw new UnresolvableError(`#${number} is not a merged pull request`);
      ms(g.mergedAt, `#${number} mergedAt`);
      const base = { number, mergedAt: g.mergedAt, sha: g.mergeCommit?.oid, head: g.headRefOid, reverted: false };
      // A page a lane can make incomplete or unreadable leaves the merge autonomous with no rung.
      let timeline;
      try {
        timeline = onePage(g.timelineItems, `timeline of #${number}`);
      } catch (error) {
        if (!(error instanceof IncompleteError)) throw error;
        // Who enqueued it is unknown too, so it also owes a pin.
        details.set(number, { ...base, rung: null, reason: "the timeline page is unreadable or incomplete: rung unknown", autonomous: true, byIdentity: true });
      }
      if (timeline) {
        const autonomy = autonomousOf(g, timeline);
        details.set(number, { ...base, ...autonomy, ...rungOf(g, autonomy) });
      }
    }
    return details.get(number);
  };
  const all = merged.map((pr) => record(pr.number));
  // Tracked: autonomous merges. One with no rung is never counted toward a positive term, and its
  // contrary events go against every cell.
  const tracked = all.filter((r) => r.autonomous);
  const cellsOf = (r) => (r.rung ? [`${r.rung}-auto-merge`] : CELLS);
  const bySha = new Map(tracked.map((r) => [r.sha, r]));

  // Reverts, from merged PR bodies and default-branch commit messages; every date per target.
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
  const revertDates = new Map();
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
    if (!revertDates.has(number)) revertDates.set(number, []);
    revertDates.get(number).push(revert.at);
  }
  for (const [number, dates] of revertDates) {
    let target;
    try {
      target = record(number);
    } catch (error) {
      if (!(error instanceof UnresolvableError)) throw error;
      unresolvedReverts.push({ target: number, reason: "not a merged pull request" });
      continue;
    }
    if (target.autonomous) {
      target.reverted = true;
      for (const at of dates) for (const cell of cellsOf(target)) addEvent(cell, "reverted-merge", at);
    }
  }

  const judgeWorkflows = postMergeRuns(gh, repo, branch, tracked, { lane, throughMs });

  // check()'s read-back for a merge a lane identity enqueued.
  const readBack = (r) => {
    const deadline = ms(r.mergedAt, `#${r.number} mergedAt`) + DISPATCH_DEADLINE_MS;
    const pinned = pinOf(r.number);
    if (pinned === null) {
      return throughMs > deadline
        ? { failure: { check: "pin read-back", conclusion: "no unedited pin comment by a lane identity", at: isoSeconds(deadline) } }
        : { pending: true };
    }
    return pinned.sha === r.head ? {} : { failure: { check: "pin read-back", conclusion: `headRefOid ${r.head} is not the pinned ${pinned.sha}`, at: r.mergedAt } };
  };

  // Post-merge gate on each autonomous merge commit: the --gate-check runs and status contexts.
  // A run that did not finish green or red (cancelled, action_required, stale) fails the gate
  // unless a later run of the same check succeeded, so cancelling a red run cannot erase it.
  // Then the post-merge workflow runs on later SHAs containing the merge (postMergeRuns).
  for (const r of tracked) {
    const wf = judgeWorkflows(r);
    const pin = r.byIdentity && !r.native ? readBack(r) : {};
    if (pin.failure) wf.failures.push(pin.failure);
    if (pin.pending) wf.unsettled = true;
    const addFailures = (found) => {
      for (const failure of found) {
        for (const cell of cellsOf(r)) addEvent(cell, "gate-failure", failure.at);
        gateFailures.push({ number: r.number, ...failure });
      }
    };
    addFailures(wf.failures);
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
    const failures = [
      ...runs.filter((run) => outcome(run) === "failed").map((run) => ({ check: run.name, conclusion: run.conclusion, at: run.completed_at ?? r.mergedAt })),
      ...statuses.filter((status) => STATUS_FAILED.has(status.state)).map((status) => ({ check: status.context, conclusion: status.state, at: status.created_at })),
    ];
    addFailures(failures);
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
    r.gate = failures.length + wf.failures.length > 0 ? "failed" : settled ? "passed" : "unsettled";
  }

  // Human-confirmed missed-blocking AI-review findings, from the label timeline.
  // On every merge in the window: a human merge ran under no rung, so its finding is the AI
  // review's alone.
  for (const r of all) {
    const confirmed = eventsOf(r.number).filter(
      (e) => e.event === "labeled" && e.label?.name === missedBlockingLabel && e.actor?.type === "User" && !lane.has(loginKey(e.actor.login)) && inWindow(e.created_at),
    );
    r.missedBlocking = confirmed.length > 0 ? 1 : 0;
    const cells = r.rung === "C2" ? ["C2-auto-merge"] : r.autonomous && !r.rung ? CELLS : ["C3-ai-review-blocking"];
    for (const e of confirmed) for (const cell of cells) addEvent(cell, "verification-divergence", e.created_at);
  }
  const reviewers = new Set(aiReviewers);
  if (reviewers.size > 0) {
    for (const r of all.filter(aiReviewCredited)) {
      r.aiReviewed = pages(gh, `repos/${repo}/pulls/${r.number}/reviews`).some((review) => reviewers.has(review.user?.login));
    }
  }

  // Which merges a record's SHA contains is not read: it is contrary for every cell.
  for (const record of demotionRecords(gh, owner, name, filers, new Date(sinceMs).toISOString())) {
    if (!inWindow(record.at)) continue;
    for (const cell of CELLS) addEvent(cell, "gate-failure", record.at);
    gateFailures.push({ issue: record.issue, check: "babysit-merge-demotion", conclusion: record.conclusion, at: record.at });
  }

  const sorted = [...events.values()].sort(byInstant);
  // The previous publish's generated_at: a stamp is never at or before one the prior file holds,
  // even when this run's clock is behind (publish() then refuses).
  const priorGeneratedMs = priorGeneratedAt === null ? Number.NaN : instant(priorGeneratedAt, "the previous generated_at");
  if (Array.isArray(prior)) {
    const floor = Number.isNaN(priorGeneratedMs) ? -Infinity : ceilSecond(priorGeneratedMs) + 1000;
    const found = isoSeconds(Math.max(ceilSecond(now.getTime()), floor));
    const published = new Map(prior.filter((e) => e && typeof e === "object").map((e) => [eventKey(e), e]));
    for (const e of sorted) {
      const before = published.get(eventKey(e));
      if (!before) e.discovered = found;
      else if (before.discovered !== undefined) e.discovered = before.discovered;
      // An event a file from before `discovered` holds was first published no later than that
      // file's generated_at: stamped with it once, which publish() allows only on that upgrade.
      else if (!Number.isNaN(priorGeneratedMs)) e.discovered = legacyDiscovered(priorGeneratedMs);
    }
  }
  return {
    repo,
    since,
    through: new Date(throughMs).toISOString(),
    events: [...sorted, ...reEarned(all, sorted, reviewers.size > 0)].sort(byInstant),
    unresolvedReverts,
    gateFailures,
    noRungAutonomous: [...details.values()]
      .filter((r) => r.autonomous && r.rung === null && (tracked.includes(r) || r.reverted))
      .map((r) => ({ number: r.number, reason: r.reason })),
    cells: report(all, sorted, reviewers.size > 0),
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

// C3-ai-review-blocking's populations: its positive evidence (reviews, window) comes from
// autonomous rung-C3 merges only; a confirmed miss counts against it from those and from human
// merges. Autonomous C2 and no-rung merges are in neither.
const aiReviewCredited = (r) => r.autonomous && r.rung === "C3";
const aiReviewMissCounted = (r) => !r.autonomous || r.rung === "C3";

// Thresholds are work-classes.md's suggested defaults; "C2" and "C3" name the rung a merge ran
// under (its pin), not a work class. `merges` is every merge in the window.
function report(merges, events, reviewsMeasured) {
  const c2 = merges.filter((r) => r.rung === "C2" && r.autonomous);
  const c3 = merges.filter(aiReviewCredited);
  const missCounted = merges.filter(aiReviewMissCounted);
  const c2Window = windowOf(c2);
  const reverted = (records) => records.filter((r) => r.reverted).length;
  const missed = (records) => records.reduce((sum, r) => sum + (r.missedBlocking ?? 0), 0);
  const c2Demotions = events.filter((e) => e.cell === "C2-auto-merge").length;
  const reviewed = c3.filter((r) => r.aiReviewed);
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
    "C3-ai-review-blocking": cell(windowOf(c3), [
      reviewsMeasured
        ? term("advisory AI reviews on C3", reviewed.length, ">= 30", reviewed.length >= 30)
        : term("advisory AI reviews on C3", null, ">= 30", false, { unmeasured: "no --ai-reviewer given" }),
      term("human-confirmed missed-blocking findings", missed(missCounted), "0", missed(missCounted) === 0),
    ]),
  };
}

// After a demotion a cell re-promotes from run evidence (check-security-binding.mjs reads the
// event): its window restarts at the latest contrary event against it or a prerequisite, which
// takes in each demotion record's creation, rounded up to a whole second as
// babysit_merge_policy.py _window_start rounds the resolver's --window-start. `report()` runs over
// only the merges after that instant, and the first merge at which the cell's predicate passes is
// the re-earn's `at`. The same evidence gives the same event, but the prefix can change with no
// contrary event (a pull body edited after its merge, a gate going from passed to unsettled), so
// a later run may derive a different re-earn or none; publish() keeps the one already published.
// A contrary event's `at` is not always when it was found (a revert's committer date, a merge
// time), so the window starts at the later of each event's `at` and its `discovered`: a contrary
// event found after a re-earn was published starts a new window after that run, and the checker
// voids the earlier re-earn. A re-earn is not contrary.
const PROMOTION_DEPENDENCIES = { "C3-auto-merge": ["C2-auto-merge", "C3-ai-review-blocking"] };
const knownAt = (event) => Math.max(Date.parse(event.at), event.discovered !== undefined ? Date.parse(event.discovered) : -Infinity);

function reEarned(counted, contrary, reviewsMeasured) {
  const out = [];
  for (const cell of CELLS) {
    const against = [cell, ...(PROMOTION_DEPENDENCIES[cell] ?? [])];
    const times = contrary.filter((e) => against.includes(e.cell)).map(knownAt);
    if (times.length === 0) continue;
    const sinceMs = ceilSecond(Math.max(...times));
    const after = counted.filter((r) => Date.parse(r.mergedAt) > sinceMs).sort((a, b) => Date.parse(a.mergedAt) - Date.parse(b.mergedAt) || a.number - b.number);
    const later = contrary.filter((e) => Date.parse(e.at) > sinceMs);
    for (let k = 1; k <= after.length; k += 1) {
      if (!report(after.slice(0, k), later, reviewsMeasured)[cell].pass) continue;
      out.push({ cell, event: "re-earned", at: isoSeconds(Date.parse(after[k - 1].mergedAt)), since: isoSeconds(sinceMs) });
      break;
    }
  }
  return out;
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

export function publish(outDir, derived, through, now = new Date(), { rename = renameSync } = {}) {
  let events = derived;
  const unstamped = derived.filter((event) => event?.event !== "re-earned" && Number.isNaN(Date.parse(event?.discovered)));
  if (unstamped.length > 0) {
    throw new PublishError(`refusing to publish: ${unstamped.length} contrary event(s) have no parsable discovered time: ${unstamped.map(eventKey).join(", ")}`);
  }
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
    // A clock behind the previous publish could stamp a `discovered` at or before a published
    // re-earn's `since`.
    const previousAt = typeof priorMeta.generated_at === "string" ? Date.parse(priorMeta.generated_at) : Number.NaN;
    if (Number.isNaN(previousAt) || now.getTime() < previousAt) {
      throw new PublishError(`refusing to publish: this run's time ${now.toISOString()} is before the previous publish's generated_at ${JSON.stringify(priorMeta.generated_at)} in ${metaFile}, or that value does not parse`);
    }
    const byKey = new Map(events.map((event) => [eventKey(event), event]));
    const missing = prior.filter((event) => !byKey.has(eventKey(event)));
    const dropped = missing.filter((event) => event?.event !== "re-earned");
    if (dropped.length > 0) {
      throw new PublishError(`refusing to publish: the new events drop ${dropped.length} previously published event(s): ${dropped.map(eventKey).join(", ")}`);
    }
    // The one change allowed: a contrary event the previous file holds with no `discovered` gains
    // that file's generated_at, the upgrade collect() makes.
    const upgrade = (event, next) => event?.discovered === undefined && event?.event !== "re-earned" && next.discovered === legacyDiscovered(previousAt);
    const redated = prior.filter((event) => {
      const next = byKey.get(eventKey(event));
      return next !== undefined && next.discovered !== event?.discovered && !upgrade(event, next);
    });
    if (redated.length > 0) {
      throw new PublishError(`refusing to publish: the new events change the discovered time of ${redated.length} published event(s): ${redated.map(eventKey).join(", ")}`);
    }
    // A re-earn the run no longer derives (a later contrary event moved its window) is kept: the
    // checker honors one only while every in-epoch contrary event's `at` and `discovered` are at
    // or before its `since`.
    if (missing.length > 0) events = [...events, ...missing].sort(byInstant);
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

// The published events, for their discovered times: [] when there is none yet or it cannot be
// read as an array (publish() then refuses on its own checks).
function publishedEvents(outDir) {
  try {
    const events = JSON.parse(readIfPresent(join(outDir, "evidence.json")) ?? "[]");
    return Array.isArray(events) ? events : [];
  } catch {
    return [];
  }
}

// The previous sidecar's generated_at, or null when there is none to read.
function publishedGeneratedAt(outDir) {
  try {
    const at = JSON.parse(readIfPresent(join(outDir, "evidence.meta.json")) ?? "null")?.generated_at;
    return typeof at === "string" ? at : null;
  } catch {
    return null;
  }
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
    const now = new Date();
    const result = collect({
      now,
      prior: values.out ? publishedEvents(values.out) : null,
      priorGeneratedAt: values.out ? publishedGeneratedAt(values.out) : null,
      repo: values.repo,
      since: values.since,
      through: values.through ?? new Date().toISOString(),
      laneLogins: values["lane-login"],
      gateChecks: values["gate-check"],
      aiReviewers: values["ai-reviewer"] ?? [],
      missedBlockingLabel: values["missed-blocking-label"],
    });
    if (values.out) publish(values.out, result.events, result.through, now);
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } catch (error) {
    process.stderr.write(`publish-promotion-evidence: ${error.message}\n`);
    process.exit(error instanceof PublishError && error.message.startsWith("refusing") ? 1 : 2);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
