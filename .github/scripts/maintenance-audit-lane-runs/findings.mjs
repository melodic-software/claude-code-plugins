import { createHash } from "node:crypto";
import { lstatSync, readFileSync } from "node:fs";
import { join, normalize } from "node:path";

export const SLICES = new Set(["A", "C", "D"]);
const MARKER = /^<!-- lane-sweep:fp=([0-9a-f]{16}) -->$/;
const TEXT_FIELDS = ["title", "problem", "root_cause", "proposed_fix", "workflow", "job", "signature"];

const squash = (text) => String(text).replace(/\s+/g, " ").trim();

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

const fenced = (text) => {
  const body = String(text).replace(/<!--/g, "<\u200b!--");
  const longest = Math.max(0, ...(body.match(/`+/g) ?? []).map((run) => run.length));
  const fence = "`".repeat(Math.max(3, longest + 1));
  return `${fence}text\n${body}\n${fence}`;
};

export const inertTitle = (text) =>
  squash(text)
    .replace(/</g, "&lt;")
    .replace(/[[\]]/g, (c) => `\\${c}`)
    .replace(/:\/\//g, "\u200b://")
    .replace(/www\./gi, (w) => `${w.slice(0, 3)}\u200b.`)
    .replace(/@(?=[A-Za-z0-9])/g, "@\u200b")
    .replace(/#(?=\d)/g, "#\u200b");

const claimsOf = (finding) => finding.evidence.map((c) => `${c.path}:${c.line}: ${c.quote}`).join("\n");

export const DIGEST_MARKER = "<!-- lane-sweep-digest -->";
export const DIGEST_TITLE = "Review the open findings from the lane sweep";
const ENTRY = /^<!-- lane-sweep-entry fp=([0-9a-f]{16})(?: tracked=([1-9][0-9]*))?(?: slice=([ACD]))?(?: wf=(\S+))? -->$/;
const WORKFLOW_PATH = /^\.github\/workflows\/[A-Za-z0-9_.-]+\.ya?ml$/;
const workflowPath = (path) => (typeof path === "string" && WORKFLOW_PATH.test(path) ? path : null);
const entryMarker = ({ fingerprint: fp, tracked, slice, workflow }) =>
  `<!-- lane-sweep-entry fp=${fp}${tracked ? ` tracked=${tracked}` : ""}${SLICES.has(slice) ? ` slice=${slice}` : ""}${workflowPath(workflow) ? ` wf=${workflow}` : ""} -->`;
const END = "<!-- lane-sweep-end -->";
export const MAX_FIELD = 2000;
export const BODY_LIMIT = 60000;
const MUTED = new Set(["not_planned", "duplicate"]);

export const isDigest = (body) => String(body ?? "").split("\n", 1)[0] === DIGEST_MARKER;

const clip = (text) => {
  const chars = Array.from(String(text));
  return chars.length > MAX_FIELD ? `${chars.slice(0, MAX_FIELD).join("")} [cut at ${MAX_FIELD} characters]` : String(text);
};

export function renderEntry({ fingerprint: fp, finding, tracked = null }) {
  const marker = entryMarker({ fingerprint: fp, tracked, slice: finding.slice, workflow: finding.workflow });
  const head = [marker, `### ${inertTitle(finding.title)}`, ""];
  if (tracked) return [...head, `Slice ${finding.slice}, fingerprint \`${fp}\`. Tracked in #${tracked}.`].join("\n");
  return [
    ...head,
    `Slice ${finding.slice}, fingerprint \`${fp}\`.`,
    "",
    "**Problem**",
    "",
    fenced(clip(finding.problem)),
    "",
    "**Root cause**",
    "",
    fenced(clip(finding.root_cause)),
    "",
    fenced(clip(claimsOf(finding))),
    "",
    "**Proposed fix**",
    "",
    fenced(clip(finding.proposed_fix)),
    "",
    "**Where**",
    "",
    fenced(clip(`workflow ${finding.workflow}\njob ${finding.job}`)),
  ].join("\n");
}

const shortEntry = (entry) =>
  `${entry.text.split("\n", 2).join("\n")}\n\nFingerprint \`${entry.fingerprint}\`; details left out to fit the issue body limit.`;

const entryKey = (e) => `${e.fingerprint}:${e.tracked ?? ""}`;
export const digestFingerprint = (entries) =>
  createHash("sha256")
    .update(JSON.stringify(entries.map(entryKey).sort()))
    .digest("hex")
    .slice(0, 16);

export function renderDigest(entries, runUrl) {
  const head = [
    DIGEST_MARKER,
    `The lane sweep's open findings, as of [this run](${runUrl}). A sweep whose findings differ from this list, or whose findings' tracking issues opened or closed, replaces this body and adds a comment: a finding it no longer sees drops off. An entry keeps the details of the sweep that last rewrote the body. A model wrote the fenced text from CI data, which can carry text written to steer it; every cited line was checked against main in the run that found it. A rewrite takes \`agent-ready\` off. Closing this issue as not planned or duplicate mutes the digest; closing it otherwise lets the next change reopen it.`,
    "",
    entries.length === 0 ? "No open finding." : `${entries.length} open finding${entries.length === 1 ? "" : "s"}.`,
  ].join("\n");
  const tail = `\n\n${END}\n<!-- lane-sweep:fp=${digestFingerprint(entries)} -->`;
  const short = entries.map((e) => `\n\n${shortEntry(e)}`);
  let rest = short.reduce((n, s) => n + s.length, 0);
  let body = head;
  entries.forEach((entry, i) => {
    rest -= short[i].length;
    const full = `\n\n${entry.text}`;
    body += body.length + full.length + rest + tail.length <= BODY_LIMIT ? full : short[i];
  });
  return `${body}${tail}`;
}

const FENCE = /^(`{3,})text$/;
const SLICE_LINE = /^Slice ([ACD]), fingerprint `[0-9a-f]{16}`/;

function entryWhere(lines) {
  const slice = SLICE_LINE.exec(lines[3] ?? "")?.[1] ?? null;
  let fence = null;
  let armed = false;
  let workflow = null;
  for (const line of lines) {
    if (fence) {
      if (line === fence.close) fence = null;
      else if (fence.where && fence.first) workflow = /^workflow (.+)$/.exec(line)?.[1] ?? null;
      if (fence) fence.first = false;
      continue;
    }
    const open = FENCE.exec(line);
    if (open) {
      fence = { close: open[1], where: armed, first: true };
      armed = false;
      continue;
    }
    if (line === "**Where**") armed = true;
  }
  return { slice, workflow };
}

export function readEntries(body) {
  const entries = [];
  let current = null;
  let fence = null;
  for (const line of String(body ?? "").split("\n")) {
    if (fence) {
      if (line === fence) fence = null;
      current?.lines.push(line);
      continue;
    }
    const m = ENTRY.exec(line);
    if (!m && line !== END) {
      fence = FENCE.exec(line)?.[1] ?? null;
      current?.lines.push(line);
      continue;
    }
    if (current) entries.push(current);
    if (!m) {
      current = null;
      break;
    }
    current = { fingerprint: m[1], tracked: m[2] ? Number(m[2]) : null, slice: m[3] ?? null, wf: m[4] ?? null, lines: [line] };
  }
  if (current) entries.push(current);
  return entries.map(({ fingerprint: fp, tracked, slice, wf, lines }) => {
    const where = entryWhere(lines);
    return {
      fingerprint: fp,
      tracked,
      title: (lines[1] ?? "").replace(/^### /, ""),
      text: lines.join("\n").trimEnd(),
      slice: slice ?? where.slice,
      workflow: wf !== null ? workflowPath(wf) : workflowPath(where.workflow),
    };
  });
}

export function renderDigestComment({ added, dropped, retracked = [] }, runUrl) {
  const list = (entries) => entries.map((e) => `- ${e.title} (\`${e.fingerprint}\`)`);
  const where = (e) => (e.tracked ? `tracked in #${e.tracked}` : "tracked here");
  return [
    `Changed in [this run](${runUrl}).`,
    ...(added.length > 0 ? ["", "New:", "", ...list(added)] : []),
    ...(dropped.length > 0 ? ["", "No longer seen:", "", ...list(dropped)] : []),
    ...(retracked.length > 0
      ? ["", "Tracking changed:", "", ...retracked.map((e) => `- ${e.title} (\`${e.fingerprint}\`): now ${where(e)}`)]
      : []),
  ].join("\n");
}

const lastLineFp = (body) => MARKER.exec(String(body ?? "").trimEnd().split("\n").at(-1))?.[1] ?? null;

export const readFingerprint = (body) => (isDigest(body) ? null : lastLineFp(body));

export function planDigest({ items, existing, openNumbers, complete = true, carry = () => "unread" }) {
  const byFp = new Map();
  let digest = null;
  for (const issue of existing) {
    if (isDigest(issue.body)) {
      if (!digest || issue.number > digest.number) digest = issue;
      continue;
    }
    const fp = readFingerprint(issue.body);
    if (fp && (!byFp.has(fp) || issue.state === "open")) byFp.set(fp, issue);
  }
  const skip = [];
  const entries = [];
  const seen = new Set();
  for (const { fingerprint: fp, finding } of items) {
    if (seen.has(fp)) {
      skip.push({ fingerprint: fp, reason: "duplicate-in-run" });
      continue;
    }
    seen.add(fp);
    const match = byFp.get(fp);
    if (match?.state === "closed" && MUTED.has(match.state_reason)) {
      skip.push({ fingerprint: fp, reason: "muted" });
      continue;
    }
    if (finding.covered_by !== null && finding.covered_by !== digest?.number && openNumbers.has(finding.covered_by)) {
      skip.push({ fingerprint: fp, reason: "covered" });
      continue;
    }
    const tracked = match?.state === "open" ? match.number : null;
    entries.push({ fingerprint: fp, tracked, title: inertTitle(finding.title), text: renderEntry({ fingerprint: fp, finding, tracked }) });
  }
  const before = digest ? readEntries(digest.body) : [];
  const carried = [];
  if (!complete) {
    for (const entry of before.filter((e) => !seen.has(e.fingerprint))) {
      const reason = carry(entry);
      if (!reason) continue;
      const [, ...rest] = entry.text.split("\n");
      entries.push({ ...entry, text: [entryMarker(entry), ...rest].join("\n") });
      seen.add(entry.fingerprint);
      carried.push({ fingerprint: entry.fingerprint, reason });
    }
  }
  const was = new Map(before.map((e) => [e.fingerprint, e]));
  const plan = {
    action: null,
    number: digest?.number ?? null,
    entries,
    added: entries.filter((e) => !was.has(e.fingerprint)),
    dropped: before.filter((e) => !seen.has(e.fingerprint)),
    retracked: entries.filter((e) => was.has(e.fingerprint) && was.get(e.fingerprint).tracked !== e.tracked),
    carried,
    skip,
  };
  const unchanged = digest !== null && lastLineFp(digest.body) === digestFingerprint(entries);
  if (!digest) plan.action = entries.length > 0 ? "file" : null;
  else if (digest.state === "open") plan.action = unchanged ? null : "update";
  else if (!MUTED.has(digest.state_reason) && entries.length > 0 && !unchanged) plan.action = "reopen";
  return plan;
}
