#!/usr/bin/env node

// Operator-side publisher for the promotion-evidence events file
// (promotion_evidence_source in reference/promotion-evidence-bootstrap.md) and the C3
// promotion-evidence report. It reads GitHub only, through `gh api` GET calls and one read-only
// GraphQL query, and never runs inside the lane: the lane must not be able to write its output.
//
// Usage: node publish-promotion-evidence.mjs --repo <owner/name> --since <ISO> --lane-login <login> [--lane-login ...]
//          [--through <ISO>] [--ai-reviewer <login> ...] [--missed-blocking-label <name>] [--out <dir>]
// Exit 0 = report printed (and published with --out); 1 = publish refused; 2 = usage or GitHub read error.
//
// Report mode (no --out) prints {repo, since, through, events, unresolvedReverts, unclassedAutonomous, cells} to
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
// --lane-login. Logins compare case-insensitively with `[bot]` dropped. GitHub records the
// enqueuer as merged_by (probed 2026-10-12 on PR #7352: merged_by.login matched the
// AddedToMergeQueueEvent enqueuer), so --lane-login names any lane identity that runs as a User
// (a machine user); an App lane is a Bot and counts without it. Recheck if merged_by stops
// matching the enqueuer.
//
// What counts (judgment where the contract names no GitHub source):
// - A merged PR's work class is the highest `work-class:` label (the label set
//   babysit-prs/scripts/babysit_merge_policy.py WORK_CLASS_LABELS maps) on the issues it linked
//   at merge and on the PR, each label set rebuilt as of merged_at by undoing later
//   labeled/unlabeled events, so relabeling after the merge changes nothing. The linked set is
//   closingIssuesReferences with later ConnectedEvent/DisconnectedEvent undone; when the PR body
//   was edited after the merge, its closing-keyword links at merge are unknown and the class is
//   none. A list with another page fails closed.
// - A C2/C3 merge is counted. An autonomous merge with no class is listed in
//   unclassedAutonomous, never counted toward a positive term, and each of its contrary events
//   is emitted against every promotable cell.
// - reverted-merge: an autonomous C2/C3 merge named by a merged PR body or a default-branch
//   commit as `Reverts <owner/repo>#<n>` (GitHub's revert button) or `This reverts commit
//   <sha>` (git revert); one event per reverted merge, at the earliest revert seen. A merged PR
//   titled revert... with neither form is listed in unresolvedReverts for a human to read.
// - gate-failure: every check run on an autonomous merge's merge commit (filter=all, so a run
//   later re-run green still counts) concluding failure, timed_out or startup_failure, and every
//   commit status in state failure or error, whenever it completed. A run concluding cancelled,
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
const DAY_MS = 86_400_000;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;

export class PublishError extends Error {}

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
  if (run.status !== 0) throw new PublishError(`gh api ${path} failed: ${(run.stderr || run.error?.message || "").trim()}`);
  return JSON.parse(run.stdout);
}

const PULL_QUERY =
  "query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){" +
  "number mergedAt lastEditedAt mergeCommit{oid} mergedBy{__typename login} labels(first:100){pageInfo{hasNextPage} nodes{name}} " +
  "closingIssuesReferences(first:50){pageInfo{hasNextPage} nodes{number labels(first:100){pageInfo{hasNextPage} nodes{name}}}} " +
  "timelineItems(first:100,itemTypes:[CONNECTED_EVENT,DISCONNECTED_EVENT,ADDED_TO_MERGE_QUEUE_EVENT]){pageInfo{hasNextPage} nodes{__typename " +
  "... on ConnectedEvent{createdAt subject{__typename ... on Issue{number}}} ... on DisconnectedEvent{createdAt subject{__typename ... on Issue{number}}} " +
  "... on AddedToMergeQueueEvent{createdAt actor{__typename login} enqueuer{__typename login}}}}}}}";
const CELLS = ["C2-auto-merge", "C3-ai-review-blocking", "C3-auto-merge"];

// A login compared across REST (`app[bot]`) and GraphQL (`app`) spellings, as
// babysit_merge_policy.py _login_key does.
function loginKey(login) {
  return String(login ?? "")
    .trim()
    .toLowerCase()
    .replace(/\[bot\]$/, "");
}

function onePage(connection, what) {
  if (!Array.isArray(connection?.nodes) || connection.pageInfo?.hasNextPage !== false) {
    throw new PublishError(`gh api graphql: ${what} unreadable or hasNextPage`);
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
    .filter((e) => (e.event === "labeled" || e.event === "unlabeled") && Date.parse(e.created_at) > atMs)
    .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
  for (const e of later) e.event === "labeled" ? set.delete(e.label?.name) : set.add(e.label?.name);
  return [...set];
}

function eventKey(event) {
  return JSON.stringify([event.cell, event.event, event.at]);
}

export function collect({ repo, since, through, laneLogins, aiReviewers = [], missedBlockingLabel, gh = realGh }) {
  const sinceMs = instant(since, "--since");
  const throughMs = Math.min(instant(through, "--through"), Date.now());
  const lane = new Set(laneLogins.map(loginKey));
  // babysit_merge_policy.py is_human, without its permission read: a User that is not a lane
  // login, `github-actions` or a `[bot]` login. A null actor is not human.
  const human = (actor) =>
    actor?.__typename === "User" && !lane.has(loginKey(actor.login)) && loginKey(actor.login) !== "github-actions" && !/\[bot\]$/i.test(actor.login ?? "");
  const inWindow = (at) => typeof at === "string" && Date.parse(at) >= sinceMs && Date.parse(at) <= throughMs;
  const events = new Map();
  const addEvent = (cell, event, at) => {
    const record = { cell, event, at };
    events.set(eventKey(record), record);
  };

  // Created-ascending order is stable while paging: an update moves no PR between pages.
  const seen = new Set();
  const merged = pages(gh, `repos/${repo}/pulls?state=closed&sort=created&direction=asc`).filter(
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
    const atMs = Date.parse(g.mergedAt);
    if (g.lastEditedAt && Date.parse(g.lastEditedAt) > atMs) return { cls: null, reason: "PR body edited after the merge: closing-keyword links unknown" };
    const linked = new Map();
    for (const issue of onePage(g.closingIssuesReferences, `closingIssuesReferences of #${g.number}`)) {
      linked.set(issue.number, onePage(issue.labels, `labels of issue #${issue.number}`).map((label) => label?.name));
    }
    const laterLinks = timeline
      .filter((e) => ["ConnectedEvent", "DisconnectedEvent"].includes(e.__typename) && e.subject?.__typename === "Issue" && Date.parse(e.createdAt) > atMs)
      .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
    for (const e of laterLinks) {
      if (e.__typename === "ConnectedEvent") linked.delete(e.subject.number);
      else if (!linked.has(e.subject.number)) linked.set(e.subject.number, (gh(`repos/${repo}/issues/${e.subject.number}`).labels ?? []).map((label) => label?.name));
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
    const queued = timeline.filter((e) => e.__typename === "AddedToMergeQueueEvent").sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));
    const actors = queued.length > 0 ? [queued.at(-1).actor, queued.at(-1).enqueuer] : [g.mergedBy];
    return actors.some((actor) => !human(actor)) || lane.has(loginKey(g.mergedBy?.login));
  };

  const details = new Map();
  const record = (number) => {
    if (!details.has(number)) {
      const g = gh("graphql", { query: PULL_QUERY, variables: { owner, name, number } })?.data?.repository?.pullRequest;
      if (!g?.mergedAt) throw new PublishError(`gh api graphql: pull request #${number} unreadable or not merged`);
      const timeline = onePage(g.timelineItems, `timeline of #${number}`);
      details.set(number, { number, ...classAtMerge(g, timeline), autonomous: autonomousOf(g, timeline), mergedAt: g.mergedAt, sha: g.mergeCommit?.oid, reverted: false });
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
      if (!m[1] || m[1].toLowerCase() === own) targets.push({ number: Number(m[2]) });
    }
    for (const m of (text ?? "").matchAll(/This reverts commit ([0-9a-f]{40})/g)) targets.push({ sha: m[1] });
    return targets;
  };
  const reverts = [];
  const unresolvedReverts = [];
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
    let number = revert.number;
    if (number === undefined) {
      const known = bySha.get(revert.sha);
      number = known ? known.number : gh(`repos/${repo}/commits/${revert.sha}/pulls`).find((pr) => pr.merged_at)?.number;
      if (number === undefined) continue;
    }
    if (!firstRevert.has(number) || Date.parse(revert.at) < Date.parse(firstRevert.get(number))) firstRevert.set(number, revert.at);
  }
  for (const [number, at] of firstRevert) {
    const target = record(number);
    if (target.autonomous && (["C2", "C3"].includes(target.cls) || target.cls === null)) {
      target.reverted = true;
      for (const cell of cellsOf(target)) addEvent(cell, "reverted-merge", at);
    }
  }

  // Post-merge gate on each autonomous merge commit: every check run and every commit status.
  // A run that did not finish green or red (cancelled, action_required, stale) fails the gate
  // unless a later run of the same check succeeded, so cancelling a red run cannot erase it.
  for (const r of tracked.filter((c) => c.autonomous)) {
    const runs = pages(gh, `repos/${repo}/commits/${r.sha}/check-runs?filter=all`, "check_runs");
    const statuses = pages(gh, `repos/${repo}/commits/${r.sha}/statuses`);
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
    const latest = new Map();
    for (const status of [...statuses].sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))) {
      if (!latest.has(status.context)) latest.set(status.context, status.state);
    }
    const settled = runs.length + latest.size > 0 && runs.every((run) => outcome(run) === "ok") && [...latest.values()].every((state) => state === "success");
    r.gate = failedRuns.length + failedStatuses.length > 0 ? "failed" : settled ? "passed" : "unsettled";
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

  const sorted = [...events.values()].sort((a, b) => Date.parse(a.at) - Date.parse(b.at) || eventKey(a).localeCompare(eventKey(b)));
  return {
    repo,
    since,
    through: new Date(throughMs).toISOString(),
    events: sorted,
    unresolvedReverts,
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
      term("human-reverted merges", reverted(c2), "0", reverted(c2) === 0),
    ]),
    "C3-auto-merge": cell(windowOf([...c2, ...c3]), [
      term("autonomous C2 merges", c2.length, ">= 20", c2.length >= 20),
      term("C2 window days", c2Window.days, ">= 14", c2Window.days >= 14),
      term("C2 demotion events", c2Demotions, "0", c2Demotions === 0),
      term("autonomous C3 completions", c3.length, ">= 10", c3.length >= 10),
      gateTerm("C3 deterministic-gate pass", c3),
      term("C3 human-reverted merges", reverted(c3), "0", reverted(c3) === 0),
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

export function publish(outDir, events, through, now = new Date()) {
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
  try {
    metaTemp = writeTemp(metaFile, `${JSON.stringify(meta, null, 2)}\n`);
    renameSync(eventsTemp, file);
  } catch (error) {
    rmSync(eventsTemp, { force: true });
    if (metaTemp) rmSync(metaTemp, { force: true });
    throw error;
  }
  // A failure here leaves a pair the next run refuses on the sha256 check: fail closed.
  renameSync(metaTemp, metaFile);
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
        "ai-reviewer": { type: "string", multiple: true },
        "missed-blocking-label": { type: "string", default: "ai-review: missed-blocking" },
        out: { type: "string" },
      },
    }));
    if (!/^[\w.-]+\/[\w.-]+$/.test(values.repo ?? "") || !values.since || !values["lane-login"]?.length) {
      throw new PublishError("--repo <owner/name>, --since <ISO> and at least one --lane-login are required");
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
