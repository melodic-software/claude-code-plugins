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
// Report mode (no --out) prints {repo, since, through, events, unresolvedReverts, cells} to
// stdout and writes nothing. --through defaults to, and is clamped to, now. With --out it also
// writes <dir>/evidence.json (the events array) and <dir>/evidence.meta.json ({generated_at,
// through, sha256, prev_sha256}). Both temp files are written before either rename, the events
// file renamed first. It refuses when an existing evidence.json is not a JSON array, has no
// sidecar or does not match the sidecar's sha256, or holds an event the new array lacks.
//
// --lane-login: GitHub records the merge-queue enqueuer as merged_by. Probed 2026-10-12 on PR
// #7352: merged_by.login was the login of the AddedToMergeQueueEvent enqueuer, not a queue bot.
// So pass the identity the lane enqueues or merges with (its App bot login, `<slug>[bot]`); a
// lane PR a human enqueued counts as a human merge. Recheck if merged_by stops matching the
// enqueuer.
//
// What counts (judgment where the contract names no GitHub source):
// - A merged PR's work class is the highest `work-class:` label (the label set
//   babysit-prs/scripts/babysit_merge_policy.py WORK_CLASS_LABELS maps) on its linked issues
//   (closingIssuesReferences) and on the PR, each label set rebuilt as of merged_at by undoing
//   later labeled/unlabeled events, so relabeling after the merge changes nothing. A linked-issue
//   or label list with another page fails closed. A PR with no class is not counted.
// - Autonomous means merged_by is a --lane-login identity.
// - reverted-merge: an autonomous C2/C3 merge named by a merged PR body or a default-branch
//   commit as `Reverts <owner/repo>#<n>` (GitHub's revert button) or `This reverts commit
//   <sha>` (git revert); one event per reverted merge, at the earliest revert seen. A merged PR
//   titled revert... with neither form is listed in unresolvedReverts for a human to read.
// - gate-failure: every check run on an autonomous merge's merge commit (filter=all, so a run
//   later re-run green still counts) concluding failure, timed_out or startup_failure, and every
//   commit status in state failure or error, whenever it completed. The gate-pass term also
//   fails while a run is not completed with success, neutral or skipped, or a context's latest
//   status is not success.
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

// A REST path is read with GET; "graphql" runs a query (read-only: LINKED_ISSUES is the only one).
function realGh(path, graphql) {
  const args = graphql
    ? ["api", "graphql", "-f", `query=${graphql.query}`, ...Object.entries(graphql.variables).flatMap(([key, value]) => ["-F", `${key}=${value}`])]
    : ["api", "--method", "GET", path];
  const run = spawnSync("gh", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (run.status !== 0) throw new PublishError(`gh api ${path} failed: ${(run.stderr || run.error?.message || "").trim()}`);
  return JSON.parse(run.stdout);
}

const LINKED_ISSUES =
  "query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){closingIssuesReferences(first:50){pageInfo{hasNextPage} nodes{number labels(first:100){pageInfo{hasNextPage} nodes{name}}}}}}}";

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
  const lane = new Set(laneLogins);
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
  const classes = new Map();
  const classOf = (number, prLabels, mergedAt) => {
    if (!classes.has(number)) {
      const refs = gh("graphql", { query: LINKED_ISSUES, variables: { owner, name, number } })?.data?.repository?.pullRequest?.closingIssuesReferences;
      if (!Array.isArray(refs?.nodes) || refs.pageInfo?.hasNextPage !== false) {
        throw new PublishError(`gh api graphql: closingIssuesReferences for #${number} unreadable or hasNextPage`);
      }
      const atMs = Date.parse(mergedAt);
      const names = labelsAsOf((prLabels ?? []).map((label) => label?.name), eventsOf(number), atMs);
      for (const issue of refs.nodes) {
        if (!Array.isArray(issue?.labels?.nodes) || issue.labels.pageInfo?.hasNextPage !== false) {
          throw new PublishError(`gh api graphql: labels of issue #${issue?.number} unreadable or hasNextPage`);
        }
        names.push(...labelsAsOf(issue.labels.nodes.map((label) => label?.name), eventsOf(issue.number), atMs));
      }
      classes.set(number, workClass(names));
    }
    return classes.get(number);
  };

  const details = new Map();
  const record = (number) => {
    if (!details.has(number)) {
      const pr = gh(`repos/${repo}/pulls/${number}`);
      details.set(number, {
        number,
        cls: classOf(number, pr.labels, pr.merged_at),
        autonomous: lane.has(pr.merged_by?.login),
        mergedAt: pr.merged_at,
        sha: pr.merge_commit_sha,
        reverted: false,
      });
    }
    return details.get(number);
  };
  const counted = merged.filter((pr) => ["C2", "C3"].includes(classOf(pr.number, pr.labels, pr.merged_at))).map((pr) => record(pr.number));
  const bySha = new Map(counted.map((r) => [r.sha, r]));

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
    if (target.autonomous && ["C2", "C3"].includes(target.cls)) {
      target.reverted = true;
      addEvent(`${target.cls}-auto-merge`, "reverted-merge", at);
    }
  }

  // Post-merge gate on each autonomous merge commit: every check run and every commit status.
  for (const r of counted.filter((c) => c.autonomous)) {
    const runs = pages(gh, `repos/${repo}/commits/${r.sha}/check-runs?filter=all`, "check_runs");
    const statuses = pages(gh, `repos/${repo}/commits/${r.sha}/statuses`);
    const failedRuns = runs.filter((run) => run.status === "completed" && GATE_FAILED.has(run.conclusion));
    const failedStatuses = statuses.filter((status) => STATUS_FAILED.has(status.state));
    for (const run of failedRuns) addEvent(`${r.cls}-auto-merge`, "gate-failure", run.completed_at);
    for (const status of failedStatuses) addEvent(`${r.cls}-auto-merge`, "gate-failure", status.created_at);
    const latest = new Map();
    for (const status of [...statuses].sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))) {
      if (!latest.has(status.context)) latest.set(status.context, status.state);
    }
    const settled =
      runs.length + latest.size > 0 &&
      runs.every((run) => run.status === "completed" && GATE_OK.has(run.conclusion)) &&
      [...latest.values()].every((state) => state === "success");
    r.gate = failedRuns.length + failedStatuses.length > 0 ? "failed" : settled ? "passed" : "unsettled";
  }

  // Human-confirmed missed-blocking AI-review findings, from the label timeline.
  for (const r of counted.filter((c) => c.cls === "C3" || c.autonomous)) {
    const confirmed = eventsOf(r.number).filter(
      (e) => e.event === "labeled" && e.label?.name === missedBlockingLabel && e.actor?.type === "User" && !lane.has(e.actor.login) && inWindow(e.created_at),
    );
    r.missedBlocking = confirmed.length > 0 ? 1 : 0;
    for (const e of confirmed) addEvent(r.cls === "C3" ? "C3-ai-review-blocking" : "C2-auto-merge", "verification-divergence", e.created_at);
  }
  const reviewers = new Set(aiReviewers);
  if (reviewers.size > 0) {
    for (const r of counted.filter((c) => c.cls === "C3")) {
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
    cells: report(counted, sorted, reviewers.size > 0),
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
