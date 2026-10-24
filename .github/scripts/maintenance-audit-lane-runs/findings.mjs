// The lane sweep's finding rules, shared by the judge's writer and the filer:
// shape checks, the claim check against main, the dedup fingerprint, the
// issue body, and the filing plan. No model, no network.
import { createHash } from "node:crypto";
import { lstatSync, readFileSync } from "node:fs";
import { join, normalize } from "node:path";

import { BORN_TRIAGED_MARKER } from "../../actions/check-born-triaged/check-born-triaged.mjs";

export const SLICES = new Set(["A", "C", "D"]);
export const MAX_NEW_ISSUES = 5;
const MARKER = /^<!-- lane-sweep:fp=([0-9a-f]{16}) -->$/;
const TEXT_FIELDS = ["title", "problem", "root_cause", "proposed_fix", "workflow", "job", "signature"];

const squash = (text) => String(text).replace(/\s+/g, " ").trim();

// Field names that fail, empty when the finding is well formed.
export function validateFinding(finding) {
  const bad = [];
  if (!SLICES.has(finding?.slice)) bad.push("slice");
  for (const field of TEXT_FIELDS) {
    if (typeof finding?.[field] !== "string" || squash(finding[field]) === "") bad.push(field);
  }
  if (typeof finding?.title === "string" && finding.title.length > 120) bad.push("title");
  const evidence = finding?.evidence;
  const claimOk = (c) => typeof c?.path === "string" && Number.isInteger(c?.line) && typeof c?.quote === "string";
  if (!Array.isArray(evidence) || evidence.length < 1 || evidence.length > 5 || !evidence.every(claimOk)) {
    bad.push("evidence");
  }
  if (!(finding?.covered_by === null || (Number.isInteger(finding?.covered_by) && finding.covered_by > 0))) {
    bad.push("covered_by");
  }
  return [...new Set(bad)];
}

// A claim holds when its path is a regular file under base (no symlink, no
// escape) and its quote, whitespace squashed, is on that 1-based line.
export function checkClaim(base, { path, line, quote }) {
  if (
    !/^[A-Za-z0-9._@+-][A-Za-z0-9._@+/-]*$/.test(path) ||
    normalize(path) !== path ||
    path.split("/").includes("..")
  ) {
    return { ok: false, reason: "bad-path" };
  }
  if (squash(quote) === "") return { ok: false, reason: "empty-quote" };
  const full = join(base, path);
  let stat;
  try {
    stat = lstatSync(full);
  } catch {
    return { ok: false, reason: "not-a-file" };
  }
  if (!stat.isFile()) return { ok: false, reason: "not-a-file" };
  const lines = readFileSync(full, "utf8").split("\n");
  if (lines.at(-1) === "") lines.pop();
  if (line < 1 || line > lines.length) return { ok: false, reason: "line-out-of-range" };
  return squash(lines[line - 1]).includes(squash(quote)) ? { ok: true } : { ok: false, reason: "quote-not-on-line" };
}

export function normalizeSignature(text) {
  return squash(text)
    .replace(/\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\b/g, "<time>")
    .replace(/\b(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}\b/g, "<sha>")
    .replace(/\b\d+\b/g, "<n>");
}

export const fingerprint = ({ slice, workflow, job, signature }) =>
  createHash("sha256")
    .update(JSON.stringify([slice, workflow, job, normalizeSignature(signature)]))
    .digest("hex")
    .slice(0, 16);

// Model text is data. Every free-text field renders inside a fence longer
// than any backtick run it holds, so no link, image, mention or reference
// works; an HTML comment cannot open even there.
const fenced = (text) => {
  const body = String(text).replace(/<!--/g, "<\u200b!--");
  const longest = Math.max(0, ...(body.match(/`+/g) ?? []).map((run) => run.length));
  const fence = "`".repeat(Math.max(3, longest + 1));
  return `${fence}text\n${body}\n${fence}`;
};

// The issue title, which renders outside any fence: no mention, link,
// reference or HTML.
export const inertTitle = (text) =>
  String(text)
    .replace(/</g, "&lt;")
    .replace(/[[\]]/g, (c) => `\\${c}`)
    .replace(/:\/\//g, "\u200b://")
    .replace(/@(?=[A-Za-z0-9])/g, "@\u200b")
    .replace(/#(?=\d)/g, "#\u200b");

const claimsOf = (finding) => finding.evidence.map((c) => `${c.path}:${c.line}: ${c.quote}`).join("\n");

export function renderBody(finding, fp, runUrl) {
  return [
    `Filed by the lane sweep ([run](${runUrl})) from slice ${finding.slice}. A model wrote the fenced text below from CI data, which can carry text written to steer it; every cited line was checked against main when filed. Rewrite the issue in your own words before marking it agent-ready.`,
    "",
    "## Problem",
    "",
    fenced(finding.problem),
    "",
    "## Root cause",
    "",
    fenced(finding.root_cause),
    "",
    fenced(claimsOf(finding)),
    "",
    "## Proposed fix",
    "",
    fenced(finding.proposed_fix),
    "",
    "## Where",
    "",
    fenced(`workflow ${finding.workflow}\njob ${finding.job}`),
    "",
    `<!-- lane-sweep:fp=${fp} -->`,
    BORN_TRIAGED_MARKER,
  ].join("\n");
}

// The comment that reopens a closed issue: the run and the recheck claims.
export const renderReopenComment = (finding, runUrl) =>
  [
    `Seen again by the lane sweep in [this run](${runUrl}) after this issue was closed, so it is reopened. Every cited line below was checked against main in that run.`,
    "",
    fenced(claimsOf(finding)),
  ].join("\n");

// The fingerprint from the body's last line, or the line above a closing
// born-triaged marker.
export function readFingerprint(body) {
  const lines = String(body ?? "")
    .trimEnd()
    .split("\n");
  if (lines.at(-1) === BORN_TRIAGED_MARKER) lines.pop();
  return MARKER.exec(lines.at(-1) ?? "")?.[1] ?? null;
}

// items: [{fingerprint, finding}]; existing: sweep issues of any state, with
// no time window, with body; openNumbers: open issue and PR numbers.
export function planFiling({ items, existing, openNumbers, maxNew = MAX_NEW_ISSUES }) {
  const byFp = new Map();
  for (const issue of existing) {
    const fp = readFingerprint(issue.body);
    if (fp && !byFp.has(fp)) byFp.set(fp, issue);
    if (fp && issue.state === "open") byFp.set(fp, issue);
  }
  const plan = { file: [], comment: [], reopen: [], skip: [] };
  const seen = new Set();
  for (const { fingerprint: fp, finding } of items) {
    const skip = (reason) => plan.skip.push({ fingerprint: fp, reason });
    if (seen.has(fp)) {
      skip("duplicate-in-run");
      continue;
    }
    seen.add(fp);
    const match = byFp.get(fp);
    if (match?.state === "open") {
      plan.comment.push({ number: match.number, fingerprint: fp });
      continue;
    }
    if (match?.state_reason === "not_planned") {
      skip("not-planned");
      continue;
    }
    if (match?.state_reason === "duplicate") {
      skip("closed-duplicate");
      continue;
    }
    if (finding.covered_by !== null && openNumbers.has(finding.covered_by)) {
      skip("covered");
      continue;
    }
    if (match) {
      plan.reopen.push({ number: match.number, fingerprint: fp, finding });
      continue;
    }
    if (plan.file.length >= maxNew) {
      skip("cap");
      continue;
    }
    plan.file.push({ fingerprint: fp, finding });
  }
  return plan;
}
