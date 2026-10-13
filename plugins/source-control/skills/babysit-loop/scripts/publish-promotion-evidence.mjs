#!/usr/bin/env node

// Operator-side publisher for the promotion-evidence events file
// (promotion_evidence_source in reference/promotion-evidence-bootstrap.md) and the C3
// promotion-evidence report. It reads GitHub only, through GET `gh api` calls, and never
// runs inside the lane: the lane must not be able to write its output.
//
// Usage: node publish-promotion-evidence.mjs --repo <owner/name> --since <ISO> --lane-login <login> [--lane-login ...]
//          [--through <ISO>] [--ai-reviewer <login> ...] [--missed-blocking-label <name>] [--out <dir>]
// Exit 0 = report printed (and published with --out); 1 = publish refused; 2 = usage or GitHub read error.
//
// Report mode (no --out) prints {repo, since, through, events, unresolvedReverts, cells} to
// stdout and writes nothing. With --out it also writes <dir>/evidence.json (the events array)
// and <dir>/evidence.meta.json ({generated_at, through, sha256, prev_sha256}), each through a
// temp file and a rename, and refuses when evidence.json already holds an event the new array
// lacks or cannot be read as an array.
//
// What counts (judgment where the contract names no GitHub source):
// - A merged PR's work class is the highest `work-class:` label (the label set
//   babysit-prs/scripts/babysit_merge_policy.py WORK_CLASS_LABELS maps) on its linked issues
//   (closingIssuesReferences, one read-only GraphQL query per merged PR) and its own labels,
//   which are the fallback when no linked issue carries one. A PR with no class is not counted.
// - Autonomous means merged_by is a --lane-login identity.
// - reverted-merge: an autonomous C2/C3 merge named by a merged PR body or a default-branch
//   commit as `Reverts <owner/repo>#<n>` (GitHub's revert button) or `This reverts commit
//   <sha>` (git revert). A merged PR titled revert... with neither form is listed in
//   unresolvedReverts for a human to read.
// - gate-failure: a check run on an autonomous merge's merge commit concluding failure,
//   timed_out or startup_failure. A run still in progress, cancelled or action_required is
//   unsettled: no event, and the gate-pass term fails until it settles.
// - verification-divergence: a human (a User actor outside --lane-login) applied
//   --missed-blocking-label to a merged C3 PR (cell C3-ai-review-blocking) or an autonomous C2
//   PR (cell C2-auto-merge).
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
  "query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){closingIssuesReferences(first:20){nodes{number labels(first:50){nodes{name}}}}}}}";

function pages(gh, path, key, stop = () => false) {
  const out = [];
  for (let page = 1; ; page += 1) {
    const body = gh(`${path}${path.includes("?") ? "&" : "?"}per_page=${PAGE}&page=${page}`);
    const items = key ? body?.[key] : body;
    if (!Array.isArray(items)) throw new PublishError(`gh api ${path}: expected an array${key ? ` at .${key}` : ""}`);
    out.push(...items);
    if (items.length < PAGE || stop(items)) return out;
  }
}

function workClass(labels) {
  return (labels ?? []).map((label) => CLASS_LABELS[label?.name]).filter(Boolean).sort().at(-1) ?? null;
}

function eventKey(event) {
  return JSON.stringify([event.cell, event.event, event.at]);
}

export function collect({ repo, since, through, laneLogins, aiReviewers = [], missedBlockingLabel, gh = realGh }) {
  const sinceMs = instant(since, "--since");
  const throughMs = instant(through, "--through");
  const lane = new Set(laneLogins);
  const inWindow = (at) => typeof at === "string" && Date.parse(at) >= sinceMs && Date.parse(at) <= throughMs;
  const events = new Map();
  const addEvent = (cell, event, at) => {
    const record = { cell, event, at };
    events.set(eventKey(record), record);
  };

  const merged = pages(gh, `repos/${repo}/pulls?state=closed&sort=updated&direction=desc`, null, (items) =>
    Date.parse(items.at(-1).updated_at) < sinceMs,
  ).filter((pr) => inWindow(pr.merged_at));

  // Class labels live on the linked issues (closingIssuesReferences); a PR's own labels are the
  // fallback. The highest class across both wins, as in babysit_merge_policy.py.
  const [owner, name] = repo.split("/");
  const classes = new Map();
  const classOf = (number, prLabels) => {
    if (!classes.has(number)) {
      const nodes = gh("graphql", { query: LINKED_ISSUES, variables: { owner, name, number } })?.data?.repository?.pullRequest
        ?.closingIssuesReferences?.nodes;
      if (!Array.isArray(nodes)) throw new PublishError(`gh api graphql: no closingIssuesReferences for #${number}`);
      classes.set(number, workClass([...(prLabels ?? []), ...nodes.flatMap((issue) => issue?.labels?.nodes ?? [])]));
    }
    return classes.get(number);
  };

  const details = new Map();
  const record = (number) => {
    if (!details.has(number)) {
      const pr = gh(`repos/${repo}/pulls/${number}`);
      details.set(number, {
        number,
        cls: classOf(number, pr.labels),
        autonomous: lane.has(pr.merged_by?.login),
        mergedAt: pr.merged_at,
        sha: pr.merge_commit_sha,
        labels: (pr.labels ?? []).map((label) => label?.name),
        reverted: false,
      });
    }
    return details.get(number);
  };
  const counted = merged.filter((pr) => ["C2", "C3"].includes(classOf(pr.number, pr.labels))).map((pr) => record(pr.number));
  const bySha = new Map(counted.map((r) => [r.sha, r]));

  // Reverts, from merged PR bodies and default-branch commit messages.
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
  for (const revert of reverts) {
    if (!inWindow(revert.at)) continue;
    let number = revert.number;
    if (number === undefined) {
      const known = bySha.get(revert.sha);
      number = known ? known.number : gh(`repos/${repo}/commits/${revert.sha}/pulls`).find((pr) => pr.merged_at)?.number;
      if (number === undefined) continue;
    }
    const target = record(number);
    if (target.autonomous && ["C2", "C3"].includes(target.cls)) {
      target.reverted = true;
      addEvent(`${target.cls}-auto-merge`, "reverted-merge", revert.at);
    }
  }

  // Post-merge gate on each autonomous merge commit.
  for (const r of counted.filter((c) => c.autonomous)) {
    const runs = pages(gh, `repos/${repo}/commits/${r.sha}/check-runs`, "check_runs");
    const failed = runs.filter((run) => run.status === "completed" && GATE_FAILED.has(run.conclusion) && inWindow(run.completed_at));
    r.gate = failed.length > 0 ? "failed" : runs.length > 0 && runs.every((run) => run.status === "completed" && GATE_OK.has(run.conclusion)) ? "passed" : "unsettled";
    for (const run of failed) addEvent(`${r.cls}-auto-merge`, "gate-failure", run.completed_at);
  }

  // Human-confirmed missed-blocking AI-review findings, and advisory AI reviews on C3.
  for (const r of counted.filter((c) => c.cls === "C3" || c.autonomous)) {
    r.missedBlocking = 0;
    if (!r.labels.includes(missedBlockingLabel)) continue;
    const confirmed = pages(gh, `repos/${repo}/issues/${r.number}/events`).filter(
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
    through,
    events: sorted,
    unresolvedReverts,
    cells: report(counted, sorted, throughMs, reviewers.size > 0),
  };
}

function term(name, value, threshold, pass, detail) {
  return { term: name, value, threshold, pass, ...(detail ? { detail } : {}) };
}

function windowOf(records, throughMs) {
  if (records.length === 0) return { from: null, through: new Date(throughMs).toISOString(), days: 0 };
  const from = Math.min(...records.map((r) => Date.parse(r.mergedAt)));
  return { from: new Date(from).toISOString(), through: new Date(throughMs).toISOString(), days: Math.floor(((throughMs - from) / DAY_MS) * 100) / 100 };
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
function report(counted, events, throughMs, reviewsMeasured) {
  const c2 = counted.filter((r) => r.cls === "C2" && r.autonomous);
  const c3 = counted.filter((r) => r.cls === "C3" && r.autonomous);
  const c3All = counted.filter((r) => r.cls === "C3");
  const c2Window = windowOf(c2, throughMs);
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
    "C3-auto-merge": cell(windowOf([...c2, ...c3], throughMs), [
      term("autonomous C2 merges", c2.length, ">= 20", c2.length >= 20),
      term("C2 window days", c2Window.days, ">= 14", c2Window.days >= 14),
      term("C2 demotion events", c2Demotions, "0", c2Demotions === 0),
      term("autonomous C3 completions", c3.length, ">= 10", c3.length >= 10),
      gateTerm("C3 deterministic-gate pass", c3),
      term("C3 human-reverted merges", reverted(c3), "0", reverted(c3) === 0),
      term("C3 human-confirmed missed-blocking findings", missed(c3), "0", missed(c3) === 0),
    ]),
    "C3-ai-review-blocking": cell(windowOf(c3All, throughMs), [
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

function writeAtomic(path, text) {
  const temp = `${path}.${process.pid}.tmp`;
  // "wx" refuses a temp file that already exists rather than overwrite or remove it.
  writeFileSync(temp, text, { flag: "wx" });
  try {
    renameSync(temp, path);
  } catch (error) {
    rmSync(temp, { force: true });
    throw error;
  }
}

export function publish(outDir, events, through, now = new Date()) {
  const file = join(outDir, "evidence.json");
  let previous = null;
  try {
    previous = readFileSync(file, "utf8");
  } catch (error) {
    if (error.code !== "ENOENT") throw new PublishError(`cannot read ${file}: ${error.message}`);
  }
  if (previous !== null) {
    let prior;
    try {
      prior = JSON.parse(previous);
    } catch (error) {
      throw new PublishError(`refusing to publish: ${file} is not JSON (${error.message}), so the superset check cannot run`);
    }
    if (!Array.isArray(prior)) throw new PublishError(`refusing to publish: ${file} is not a JSON array, so the superset check cannot run`);
    const keys = new Set(events.map(eventKey));
    const dropped = prior.filter((event) => !keys.has(eventKey(event)));
    if (dropped.length > 0) {
      throw new PublishError(`refusing to publish: the new events drop ${dropped.length} previously published event(s): ${dropped.map(eventKey).join(", ")}`);
    }
  }
  const text = `${JSON.stringify(events, null, 2)}\n`;
  const meta = { generated_at: now.toISOString(), through, sha256: sha256(text), prev_sha256: previous === null ? null : sha256(previous) };
  writeAtomic(file, text);
  writeAtomic(join(outDir, "evidence.meta.json"), `${JSON.stringify(meta, null, 2)}\n`);
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
