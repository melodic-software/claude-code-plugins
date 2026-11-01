// Checks the verifier's structured output, the last result message of each
// chunk's run-claude-cli execution file, and writes the one verdict file that
// pr-verify.yml uploads as pr-verify-<pr>-<head-sha>-<verdict>, a FAIL's name
// followed by `-i` and the issues it records (`artifactName`). Every reader
// also accepts that name followed by `-<headRefDigest of the head branch>`,
// which lets the pr-merge lane tie a FAIL to a branch without downloading it;
// this writer moves to it once the readers have run on main, in the change
// that adds the digest lookups to resolve-pr, which looks up only the names
// this writer writes. The output
// of each chunk must be exactly {verdict, summary, notes}: verdict pass, pass-notes or fail,
// summary a string, notes an array of strings. Since the verdict is uploaded,
// a pass or pass-notes with a permission denial writes none, and so does a chunk
// that left no output or read a part of its diff short (pr-review-main
// readCoverage) with no defect in its notes. A fail stands on a denial, since no
// fail can pass the head. A fail whose text matches the shared credential
// patterns (lib/publish-gate.mjs findSecret), a pass or pass-notes whose text
// holds a credential format (those patterns less WARN_ONLY, a secret assignment
// that may be a fixture), and any verdict whose step's credential scan stopped
// it become a fail with a fixed text in place of the model's, so the head is not
// sampled again and no part of it is published. Only this script records such a
// fail as `withheld: true`, which is what verify-notes.mjs reads to hold the pull
// request. A pass or pass-notes holding only an assignment writes no verdict.
// The file also records the head
// branch and the linked issues with their authors, as the resolver read them
// (number, author and last body editor login, id and type, last_edited_at;
// each nullable but the number), which the pr-merge
// lane's reader checks. Anything malformed throws, so the job fails and
// uploads nothing. Model text is cut to fixed lengths (judgment) and never
// reaches a shell. The file's evidence block (buildEvidence) is the one
// exception: it records the capture and the author's evidence-loop count, and
// a capture that is missing, blocked or malformed never fails the verdict.

import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { deeperLeak, findSecret, firstHit, SECRET_PATTERNS, WARN_ONLY } from "../../../lib/publish-gate.mjs";
import { readCoverage } from "../pr-review-main/write-verdict.mjs";

export const VERDICTS = Object.freeze(["pass", "pass-notes", "fail"]);
const SUMMARY_MAX = 4000;
const NOTE_MAX = 1000;
const NOTES_MAX = 30;
const SHA = /^[0-9a-f]{40}$/;
const NUMBER = /^[1-9][0-9]{0,9}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;
const REF = /^[A-Za-z0-9._/-]+$/;
const ISSUE_KEYS = "author_id,author_login,author_type,editor_id,editor_login,editor_type,last_edited_at,number,spec_comments";
// Each spec comment the model got: its id and update time, exactly.
const specComment = (comment) =>
  isObject(comment) &&
  Object.keys(comment).sort().join() === "id,updated_at" &&
  Number.isSafeInteger(comment.id) &&
  typeof comment.updated_at === "string";
const stringOrNull = (value) => value === null || typeof value === "string";
const idOrNull = (value) => value === null || Number.isSafeInteger(value);

const isObject = (value) => typeof value === "object" && value !== null && !Array.isArray(value);

function checkIssues(issues) {
  if (
    !Array.isArray(issues) ||
    !issues.every(
      (issue) =>
        isObject(issue) &&
        Object.keys(issue).sort().join() === ISSUE_KEYS &&
        Number.isSafeInteger(issue.number) &&
        issue.number > 0 &&
        ["author", "editor"].every(
          (role) => stringOrNull(issue[`${role}_login`]) && idOrNull(issue[`${role}_id`]) && stringOrNull(issue[`${role}_type`]),
        ) &&
        stringOrNull(issue.last_edited_at) &&
        Array.isArray(issue.spec_comments) &&
        issue.spec_comments.every(specComment),
    )
  ) {
    throw new Error("the linked issues do not match their schema");
  }
  return issues;
}

// The capture outcomes a capture summary may record (merge.verify-capture).
export const CAPTURES = Object.freeze(["ran", "skipped", "blocked", "not-applicable", "no-app"]);
const CAPTURE_KEYS = "capture,capture_count,features,reason";
const REASON_MAX = 1000;
const FEATURE_MAX = 200;
const FEATURES_MAX = 30;
const noApp = () => ({ capture: "no-app", reason: "no app check ran", capture_count: 0, features: [] });
const unreadable = () => ({
  capture: "blocked",
  reason: "the capture summary is unreadable or outside its schema",
  capture_count: 0,
  features: [],
});

// The capture summary as recorded: undefined (no summary) is no-app, and
// anything outside the schema, credential-shaped text included, is blocked.
function captureEvidence(summary) {
  if (summary === undefined) {
    return noApp();
  }
  if (
    !isObject(summary) ||
    Object.keys(summary).sort().join() !== CAPTURE_KEYS ||
    !CAPTURES.includes(summary.capture) ||
    !stringOrNull(summary.reason) ||
    !Number.isSafeInteger(summary.capture_count) ||
    summary.capture_count < 0 ||
    !Array.isArray(summary.features) ||
    !summary.features.every((feature) => typeof feature === "string") ||
    [summary.reason ?? "", ...summary.features].some((text) => findSecret(text))
  ) {
    return unreadable();
  }
  return {
    capture: summary.capture,
    reason: summary.reason === null ? null : summary.reason.slice(0, REASON_MAX),
    capture_count: summary.capture_count,
    features: summary.features.slice(0, FEATURES_MAX).map((feature) => feature.slice(0, FEATURE_MAX)),
  };
}

// The author's own count from the trusted PR body's `Evidence loop: k/3`
// line, read as data: null when the body is withheld or holds no such line.
export function localLoop(body) {
  const match = typeof body === "string" ? /^Evidence loop: ([0-3])\/3[ \t\r]*$/m.exec(body) : null;
  return match ? Number(match[1]) : null;
}

export function buildEvidence({ capture, prBody } = {}) {
  return { ...captureEvidence(capture), local_loop: localLoop(prBody) };
}

// run-claude-cli's own scan, which fails its step on a shorter Anthropic key
// than findSecret's shape, so this script holds text to the same line.
const KEY_SHAPE = /\bsk-ant-[A-Za-z0-9_-]{8,}/;
// chunk-diff.sh's fold, which a quoted line carries through the middle of a
// token, with the white space a quote leaves before it, on the line or across a
// line end. The lookbehind starts a match only at the head of a white space run,
// so a long run is not read again from each of its characters; folds in a
// row, an empty one included, go as one.
const FOLD = /(?<!\s)(?:\s*\\ continued: ?)+/g;
// The credential formats, which scanLeak blocks on. findSecret alone would name
// an assignment first and hide a format later on its line or after it.
const FORMATS = SECRET_PATTERNS.filter(([label]) => label !== WARN_ONLY);
const formatIn = (text) => firstHit(FORMATS, text)?.[0] ?? (KEY_SHAPE.test(text) ? "Anthropic key" : deeperLeak(text));
// The texts in order, so a credential split between two of them still reads.
// The raw text keeps the word boundaries a whole token needs; the second pass
// joins a token split over a fold or over two quoted diff lines. With no format,
// any hit left is WARN_ONLY.
const credentialIn = (texts) => {
  const text = texts.join("\n");
  const joined = text.replace(FOLD, "").replace(/\n[-+ ]/g, "\n");
  return formatIn(text) ?? formatIn(joined) ?? (findSecret(text) ?? findSecret(joined))?.[0] ?? null;
};

// A pass or pass-notes holding only an assignment: no verdict, and no security
// stop, unless its step's scan stopped it (readJudgment), which `parsed` is for.
class AssignmentOnly extends Error {
  constructor(parsed) {
    super(`the structured output holds text shaped like a credential (${WARN_ONLY})`);
    this.parsed = parsed;
  }
}

// What a withheld fail says. Its text decides nothing: a genuine fail may quote it.
export const WITHHELD_SUMMARY = "The verifier returned fail, and its text is withheld: the text was shaped like a credential, or its step stopped on the credential scan.";

// Marks a checked output as withheld. Outputs pass through parseOutput more than
// once, and a symbol key survives a spread, stays out of its exact-key check, and
// is one no model's JSON can carry. buildVerdict writes it as `withheld: true`.
const WITHHELD = Symbol("withheld");

// A fail with none of the model's text, whatever verdict it replaces: no mask
// finds where a credential ends. Empty notes stay empty. The annotation names
// the kind alone, so the run shows a credential to rotate.
const withheld = ({ notes }, kind) => {
  console.log(`::warning title=pr-verify credential::kind=${kind}`);
  return {
    verdict: "fail",
    summary: WITHHELD_SUMMARY,
    notes: notes.length > 0 ? ["The verifier's notes are withheld with its summary. Check the diff for a committed credential, and rotate any that is real."] : [],
    [WITHHELD]: true,
  };
};

// One run's structured output, parsed and checked against the verdict schema.
function parseOutput(output) {
  let parsed = output;
  if (typeof output === "string") {
    try {
      parsed = JSON.parse(output);
    } catch {
      throw new Error("the structured output is not JSON");
    }
  }
  if (
    !isObject(parsed) ||
    Object.keys(parsed).sort().join() !== "notes,summary,verdict" ||
    !VERDICTS.includes(parsed.verdict) ||
    typeof parsed.summary !== "string" ||
    !Array.isArray(parsed.notes) ||
    !parsed.notes.every((note) => typeof note === "string")
  ) {
    throw new Error("the structured output does not match the verdict schema");
  }
  const kind = credentialIn([parsed.summary, ...parsed.notes]);
  if (kind === WARN_ONLY && parsed.verdict !== "fail") {
    throw new AssignmentOnly(parsed);
  }
  return kind ? withheld(parsed, kind) : parsed;
}

// One output from each chunk's and the whole-spec judgment's: the worst
// verdict, each summary, and the notes, unprefixed since each starts with its
// path (verify-notes.mjs noteComments). The worst come first, so the cuts in
// buildVerdict never drop a fail's notes for a pass-notes chunk's. A single
// chunk is its own output; two or more never stand without `final`, so no
// chunk's pass or pass-notes becomes the head's alone.
export function mergeChunks(outputs, final) {
  if (!Array.isArray(outputs) || outputs.length === 0) {
    throw new Error("no chunk left an output");
  }
  const chunks = outputs.map(parseOutput);
  if (chunks.length === 1) {
    return chunks[0];
  }
  if (final === undefined || final === null) {
    throw new Error("the whole-spec judgment left no output");
  }
  return mergeEntries([...chunks.map((chunk, i) => ({ ...chunk, label: `Chunk ${i + 1} of ${chunks.length}` })), { ...parseOutput(final), label: "Whole spec" }]);
}

function mergeEntries(entries) {
  const worst = [...entries].sort((a, b) => VERDICTS.indexOf(b.verdict) - VERDICTS.indexOf(a.verdict));
  const room = Math.floor(SUMMARY_MAX / worst.length) - 1;
  return {
    verdict: worst[0].verdict,
    summary: worst.map(({ label, verdict, summary }) => `${label}, ${verdict}: ${summary}`.slice(0, room)).join("\n"),
    notes: worst.flatMap((entry) => entry.notes),
    ...(entries.some((entry) => entry[WITHHELD]) ? { [WITHHELD]: true } : {}),
  };
}

// The whole-spec judgment's schema: the verdict's, and each done-when item with
// the chunks that together deliver it, none when no chunk does.
export const FINAL_SCHEMA = Object.freeze({
  type: "object",
  properties: {
    verdict: { enum: VERDICTS },
    summary: { type: "string" },
    notes: { type: "array", items: { type: "string" } },
    items: {
      type: "array",
      items: {
        type: "object",
        properties: { item: { type: "string" }, chunks: { type: "array", items: { type: "integer", minimum: 1 } } },
        required: ["item", "chunks"],
        additionalProperties: false,
      },
    },
  },
  required: ["verdict", "summary", "notes", "items"],
  additionalProperties: false,
});

// The whole-spec judgment's output as a verdict output. The script holds it to
// its own mapping: an item it maps to no chunk fails the head whatever verdict
// it gave, and a pass or pass-notes that maps no item, or names a chunk that
// does not exist, counts for nothing. The script cannot tell whether a named
// chunk holds the item: that stays the judgment's.
export function parseFinal(output, count) {
  if (!isObject(output) || !Array.isArray(output.items)) {
    throw new Error("the structured output does not match the verdict schema");
  }
  const { items, ...rest } = output;
  if (!items.every((entry) => isObject(entry) && typeof entry.item === "string" && Array.isArray(entry.chunks) && entry.chunks.every(Number.isInteger))) {
    throw new Error("the structured output does not match the verdict schema");
  }
  const parsed = parseOutput(rest);
  if (parsed.verdict === "fail") {
    return parsed;
  }
  const nowhere = items.filter(({ chunks }) => chunks.length === 0);
  if (nowhere.length > 0) {
    return parseOutput({
      verdict: "fail",
      summary: `${nowhere.length} done-when item(s) delivered by no chunk. ${parsed.summary}`,
      notes: [...nowhere.map(({ item }) => `${item}: delivered by no chunk`), ...parsed.notes],
    });
  }
  if (items.length === 0 || items.some(({ chunks }) => chunks.some((chunk) => chunk < 1 || chunk > count))) {
    throw new Error("the whole-spec judgment mapped no item, or an item to no such chunk");
  }
  return parsed;
}

// Read may cut a long line short, so each line for the whole-spec judgment is
// wrapped at WRAP_CHARS characters (pr-review-main.yml LONG_LINE_BYTES).
const WRAP_CHARS = 1500;

function wrapped(text) {
  const out = [];
  for (const line of text.split("\n")) {
    let rest = line;
    for (; rest.length > WRAP_CHARS; rest = rest.slice(WRAP_CHARS)) {
      out.push(rest.slice(0, WRAP_CHARS));
    }
    out.push(rest);
  }
  return out.join("\n");
}

// Text in parts of at most partBytes, the most one Read returns whole
// (pr-verify.yml PART_BYTES), cut between lines.
function readParts(text, partBytes) {
  const parts = [""];
  for (const line of wrapped(text).split("\n")) {
    if (Buffer.byteLength(parts.at(-1)) + Buffer.byteLength(line) + 1 > partBytes) {
      parts.push("");
    }
    parts[parts.length - 1] += `${line}\n`;
  }
  return parts;
}

export function buildVerdict({ output, pr, headSha, baseSha, runId, headRef, linkedIssues, specText = [], capture, prBody }) {
  if (
    !NUMBER.test(String(pr)) ||
    !SHA.test(headSha ?? "") ||
    !SHA.test(baseSha ?? "") ||
    !RUN_ID.test(String(runId)) ||
    !REF.test(headRef ?? "")
  ) {
    throw new Error("the PR number, a SHA, the run id or the head branch is malformed");
  }
  const parsed = parseOutput(output);
  const own = Array.isArray(specText) ? specText.find((entry) => entry?.source === "pull-request") : undefined;
  const issues = checkIssues(linkedIssues);
  const refs = Array.isArray(specText) && specText.some((entry) => entry?.spec_kind === "refs");
  return {
    pr: Number(pr),
    head_sha: headSha,
    base_sha: baseSha,
    head_ref: headRef,
    linked_issues: issues,
    // How the linked issues were linked (resolve-pr's specKind): a `refs`
    // issue was judged as a partial slice, so the gate refuses the pass once
    // the pull request closes it instead (babysit_verify_evidence).
    spec_kind: own ? "pull-request" : issues.length === 0 ? "none" : refs ? "refs" : "closes",
    // What the spec was: the pull request's own title and body
    // (babysit_verify_evidence.INTENT_PULL_REQUEST), else its closing issues.
    intent: own ? "pull-request" : "issues",
    // The title and body it judged, which the gate compares live
    // (babysit_verify_evidence): an edit since refuses the pass.
    ...(own ? { intent_sha256: createHash("sha256").update(String(own.body)).digest("hex") } : {}),
    verdict: parsed.verdict,
    summary: parsed.summary.slice(0, SUMMARY_MAX),
    notes: parsed.notes.slice(0, NOTES_MAX).map((note) => note.slice(0, NOTE_MAX)),
    ...(parsed[WITHHELD] ? { withheld: true } : {}),
    evidence: buildEvidence({ capture, prBody }),
    run_id: Number(runId),
  };
}

// The last result message in the CLI's messages, with a structured output.
function lastResult(messages) {
  const result = Array.isArray(messages) ? messages.findLast((message) => message?.type === "result") : undefined;
  if (result?.structured_output === undefined) {
    throw new Error("the run left no result with a structured output");
  }
  return result;
}

const resultDenials = (result) => (Array.isArray(result.permission_denials) ? result.permission_denials : []);

// The structured output of the last result message in the CLI's messages. A
// denied call means the model reached past its data files: no pass stands on
// it. Only tool names are printed, never a call's input.
export function structuredOutput(messages) {
  const result = lastResult(messages);
  const denials = resultDenials(result);
  if (denials.length > 0) {
    const names = [...new Set(denials.map((d) => (/^[A-Za-z0-9_*-]{1,64}$/.test(d?.tool_name ?? "") ? d.tool_name : "unnamed")))];
    throw new Error(`the run hit ${denials.length} permission denial(s): ${names.join(", ")}`);
  }
  return result.structured_output;
}

// run-claude-cli's log, one object per leg, counts every leg's denials.
const logDenials = (logText) =>
  logText
    .split("\n")
    .filter((line) => line.trim() !== "")
    .reduce((sum, line) => {
      try {
        return sum + (JSON.parse(line)?.denials?.count ?? 0);
      } catch {
        throw new Error("the run log is unreadable");
      }
    }, 0);

export function earlierDenials(logText) {
  const total = logDenials(logText);
  if (total > 0) {
    throw new Error(`the run's legs hit ${total} permission denial(s)`);
  }
}

// A newline-separated list from a workflow's env, by position; a step that
// did not run renders as a blank line.
const positions = (value) =>
  String(value ?? "")
    .split("\n")
    .map((line) => line.trim());

const fileList = (value) => positions(value).filter(Boolean);

function readLog(file) {
  try {
    return readFileSync(file, "utf8");
  } catch {
    throw new Error("the run log is unreadable");
  }
}

// One chunk's log, checked for a denial on any of its legs.
const checkLog = (file) => earlierDenials(readLog(file));

// After a leg hands off, the next job judges on a new VM that cannot read
// this leg's logs, so this job records here whether every chunk it judged was
// free of denials; the next job runs only on clean=true.
export function checkKeyLeg(env = process.env) {
  for (const key of ["LOG_FILES", "GITHUB_OUTPUT"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  // Every chunk listed ran, so a blank line is a leg that left no log. The
  // whole-spec leg lists every slot, and CHUNKS says how many ran before it.
  const lines = env.LOG_FILES.replace(/\n$/, "").split("\n");
  const logs = fileList(env.LOG_FILES);
  if (logs.length !== (env.CHUNKS ? Number(env.CHUNKS) + 1 : lines.length)) {
    throw new Error("the run log is unreadable");
  }
  logs.forEach(checkLog);
  appendFileSync(env.GITHUB_OUTPUT, "clean=true\n");
}

// The head-ref digest in an artifact name: the first HEAD_REF_DIGEST_HEX hex
// digits of the SHA-256 of the head branch's UTF-8 bytes. Equal branches
// always give equal digests, so a collision can only tie a FAIL to a branch
// it did not judge, which holds a merge, never clears one.
// babysit_verify_evidence.head_ref_digest is its twin, and
// tests/test_verify_rules_sync.py compares them.
export const HEAD_REF_DIGEST_HEX = 16;
export const headRefDigest = (ref) =>
  createHash("sha256").update(String(ref), "utf8").digest("hex").slice(0, HEAD_REF_DIGEST_HEX);

// A FAIL's name ends with `-i` and the numbers of the issues it records,
// ascending and joined by dots, so the pr-merge gate counts it toward each
// issue's repeated-fail cap from the artifact listing alone
// (babysit_verify_evidence.NAME_RE, which takes at most NAMED_ISSUES_MAX).
export const NAMED_ISSUES_MAX = 10;
// The `-i` part for issue numbers `numbers`: empty for none, null for more
// than a name carries.
export function issuesSuffix(numbers) {
  const issues = [...new Set(numbers)].sort((a, b) => a - b);
  if (issues.length > NAMED_ISSUES_MAX) return null;
  return issues.length === 0 ? "" : `-i${issues.join(".")}`;
}
// A verdict's name (babysit_verify_evidence.NAME_RE): the head-ref digest is
// optional, and so, on a FAIL only, is `-i` with the verdict's issue numbers,
// ascending, each once, joined by dots (`isVerdictName` checks the order).
export const NAME = /^pr-verify-([1-9][0-9]{0,9})-([0-9a-f]{40})-(pass(?:-notes)?(?=(?:-[0-9a-f]{16})?$)|fail)(?:-[0-9a-f]{16})?(?:-i([1-9][0-9]{0,9}(?:\.[1-9][0-9]{0,9}){0,9}))?$/;
// The longest name NAME allows (babysit_verify_evidence.NAME_MAX).
export const NAME_MAX = 194;
export function isVerdictName(name) {
  const match = String(name).length <= NAME_MAX ? NAME.exec(String(name)) : null;
  const numbers = match?.[4]?.split(".").map(Number) ?? [];
  return match !== null && numbers.every((n, i) => i === 0 || numbers[i - 1] < n);
}

// The verdict's artifact name, checked against the readers' pattern before
// anything uploads: a name no reader takes throws, so the job fails loudly. A
// FAIL whose issues no name carries (over the cap, or a number the pattern
// refuses) keeps the plain name, which still counts per pull request and at
// the head.
export function artifactName(verdict) {
  const plain = `pr-verify-${verdict.pr}-${verdict.head_sha}-${verdict.verdict}`;
  let name = plain;
  if (verdict.verdict === "fail") {
    const suffix = issuesSuffix((verdict.linked_issues ?? []).map((issue) => issue.number));
    if (suffix === null || (suffix && !isVerdictName(plain + suffix))) {
      console.log(`::warning::the FAIL's issues fit no artifact name, so it is named ${plain}`);
    } else {
      name = plain + suffix;
    }
  }
  if (!isVerdictName(name)) {
    throw new Error(`the artifact name ${name} is one no reader takes`);
  }
  return name;
}

// How many days the verdict's artifact lasts. A PASS or PASS-NOTES judged
// after no body edit or issue connect or disconnect since the head commit
// (resolve-pr.mjs relinkedSince, RELINK_SINCE_HEAD `false`) is read only at
// the open pull request's current head, so one that expires refuses as
// verify:missing until the next pr-require-checks run (a push, edit or label)
// has pr-verify judge the head again; 7 days keeps a week of a held head.
// Any other pass may supersede a FAIL at its head after a relink
// (babysit_verify_evidence `_superseded`), which the merge gate still reads
// at a later head of the same change, so it keeps a FAIL's 90 days. A FAIL,
// or anything else, keeps 90 days, the maximum: the merge gate counts an
// earlier FAIL while its artifact lasts (babysit_verify_evidence.py), and
// carry-run-cache.mjs RETENTION_DAYS matches it.
export function retentionDays(verdict, mayRelink = true) {
  return ["pass", "pass-notes"].includes(verdict) && mayRelink === false ? 7 : 90;
}

function readExecution(file) {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    throw new Error("the execution file is unreadable");
  }
}

// One run's messages and its checked output: it left an output on the schema
// and a readable log, or this throws, and so does a denial on anything but a
// fail. A fail cannot pass the head, so it stands and records the denials. The
// workflow reads a failed step only when run-claude-cli's scan stopped it, on
// text this script may not recognize and with no log when the log held it, so
// that step's output is a withheld fail.
function readJudgment(file, logFile, outcome, parse = parseOutput) {
  const messages = readExecution(file);
  const result = lastResult(messages);
  const stopped = outcome !== "success";
  let output;
  try {
    output = parse(result.structured_output);
  } catch (error) {
    if (!stopped || !(error instanceof AssignmentOnly)) {
      throw error;
    }
    output = error.parsed;
  }
  if (stopped) {
    return { messages, output: withheld(output, "credential scan stop") };
  }
  const denied = resultDenials(result).length + logDenials(readLog(logFile));
  if (denied === 0) {
    return { messages, output };
  }
  if (output.verdict !== "fail") {
    structuredOutput(messages);
    throw new Error(`the run's legs hit ${denied} permission denial(s)`);
  }
  return { messages, output: { ...output, summary: `This judgment hit ${denied} permission denial(s). ${output.summary}` } };
}

// What a judgment's output counts as, given the files it had to read. A pass
// or pass-notes needs every one read whole. A fail stands on less, but only
// with a defect in its notes or withheld, whose hold needs no note, and it
// records how much it read.
function countedOutput({ messages, output }, files) {
  if (output.verdict !== "fail") {
    readCoverage(messages, files);
    return output;
  }
  const whole = (file) => {
    try {
      readCoverage(messages, [file]);
      return true;
    } catch {
      return false;
    }
  };
  const read = files.filter(whole).length;
  if (read === files.length) {
    return output;
  }
  if (output.notes.length === 0 && !output[WITHHELD]) {
    throw new Error(`a fail that read ${read} of ${files.length} parts names no defect`);
  }
  return { ...output, summary: `This judgment read ${read} of ${files.length} parts. ${output.summary}` };
}

const filesIn = (dir) => readdirSync(dir).map((name) => path.join(dir, name));

// The files chunk k had to read: its parts and, with more than one chunk, the
// manifest.
const chunkFiles = (env, k, count) => [...filesIn(path.join(env.DIFF_DIR, `chunk-${k}`)), ...(count > 1 ? filesIn(env.MANIFEST_DIR) : [])];

// After each judge step: whether its run left a fail the head can count, which
// stops the later chunks. Anything else, a broken run included, is no fail.
export function checkChunk(env = process.env) {
  let fail = false;
  try {
    const judgment = readJudgment(env.EXECUTION_FILE, env.LOG_FILE, env.JUDGE_OUTCOME);
    fail = countedOutput(judgment, chunkFiles(env, Number(env.CHUNK), Number(env.CHUNKS))).verdict === "fail";
  } catch {
    fail = false;
  }
  appendFileSync(env.GITHUB_OUTPUT, `fail=${fail}\n`);
}

// Each chunk by position: `output`, or `error` for a chunk that did not count.
function judgedChunks(env) {
  const chunkDirs = readdirSync(env.DIFF_DIR).filter((name) => /^chunk-[1-9][0-9]?$/.test(name));
  const count = Number(env.CHUNKS);
  if (!/^[1-9][0-9]?$/.test(env.CHUNKS) || chunkDirs.length !== count) {
    throw new Error(`the chunk count does not match ${chunkDirs.length} chunk(s) of the diff`);
  }
  const executions = positions(env.EXECUTION_FILES);
  const logs = positions(env.LOG_FILES);
  const outcomes = positions(env.JUDGE_OUTCOMES);
  const results = Array.from({ length: count }, (_, i) => {
    const k = i + 1;
    try {
      if (!executions[i]) {
        throw new Error("the chunk left no run");
      }
      return { k, output: countedOutput(readJudgment(executions[i], logs[i], outcomes[i]), chunkFiles(env, k, count)) };
    } catch (error) {
      return { k, error: error.message };
    }
  });
  return { count, results };
}

const firstError = (results, count) => {
  const broken = results.find((result) => result.error !== undefined);
  return broken ? new Error(`chunk ${broken.k} of ${count}: ${broken.error}`) : null;
};

// The whole-spec judgment's output: it ran, read every result (a `refs`
// entry's context parts among them), the spec and the manifest whole, and hit
// no denial, or this throws (countedOutput). A step that failed, which reaches
// here only from run-claude-cli's credential scan, leaves a withheld fail.
function finalOutput(env, count) {
  try {
    for (const key of ["FINAL_EXECUTION_FILE", "RESULTS_DIR", "MANIFEST_DIR"]) {
      if (!env[key]) {
        throw new Error(`${key} is not set`);
      }
    }
    const judgment = readJudgment(env.FINAL_EXECUTION_FILE, env.FINAL_LOG_FILE, env.FINAL_OUTCOME, (text) => parseFinal(text, count));
    return countedOutput(judgment, [...filesIn(env.RESULTS_DIR), env.SPEC_FILE, ...filesIn(env.MANIFEST_DIR)]);
  } catch (error) {
    throw new Error(`the whole-spec judgment: ${error.message}`);
  }
}

// The head's output. A fail any chunk left stands alone, so nothing after it
// can discard it; anything else needs every chunk and the whole-spec judgment.
function headOutput(env, count, results) {
  const counted = results.filter((result) => result.output !== undefined);
  if (counted.some(({ output }) => output.verdict === "fail")) {
    return count === 1 ? counted[0].output : mergeEntries(counted.map(({ k, output }) => ({ ...output, label: `Chunk ${k} of ${count}` })));
  }
  const error = firstError(results, count);
  if (error) {
    throw error;
  }
  return mergeChunks(
    counted.map(({ output }) => output),
    count > 1 ? finalOutput(env, count) : undefined,
  );
}

// The most chunk results the final judge reads, in bytes: the read budget one
// judgment gets (pr-verify.yml MAX_DIFF_BYTES). Past it no verdict is the
// outcome anyway, so the step stops before the model runs.
const RESULT_BYTES_MAX = 300000;

// What the whole-spec judgment reads, each file one Read, with its prompt and
// schema: written only when every chunk counts. Each chunk's output goes whole,
// in as many files as it takes: a cut here could hide what a chunk delivers,
// and the head would fail on size alone. The prompt lists the files, whose
// number only this step knows.
export function writeChunkResults(env = process.env) {
  for (const key of ["EXECUTION_FILES", "LOG_FILES", "JUDGE_OUTCOMES", "CHUNKS", "DIFF_DIR", "RESULTS_DIR", "PART_BYTES", "SPEC_TEXT_FILE", "SPEC_FILE", "CONTEXT_FILE", "PR_FILE", "MANIFEST_DIR", "PROMPT_FILE", "PROMPT_TEMPLATE", "SCHEMA_FILE"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  // Past three bytes a character, one wrapped line always fits a part.
  const partBytes = Number(env.PART_BYTES);
  if (!Number.isSafeInteger(partBytes) || partBytes <= WRAP_CHARS * 3) {
    throw new Error("PART_BYTES is not a part size");
  }
  const { count, results } = judgedChunks(env);
  const error = firstError(results, count);
  if (error) {
    throw error;
  }
  const chunkParts = results.map(({ k, output: { verdict, summary, notes } }) => [`chunk-${k}`, readParts(JSON.stringify({ chunk: k, of: count, verdict, summary, notes }), partBytes)]);
  const resultParts = chunkParts.flatMap(([, parts]) => parts).length;
  if (resultParts * partBytes > RESULT_BYTES_MAX) {
    throw new Error(`the chunk results take ${resultParts} parts, more than the final judge reads`);
  }
  const specText = readFileSync(env.SPEC_TEXT_FILE, "utf8");
  const refs = JSON.parse(specText).some?.((entry) => entry?.spec_kind === "refs");
  mkdirSync(env.RESULTS_DIR, { recursive: true });
  const writeParts = (stem, parts) =>
    parts.map((part, i) => {
      const file = path.join(env.RESULTS_DIR, `${stem}-part-${String(i + 1).padStart(3, "0")}.txt`);
      writeFileSync(file, part);
      return file;
    });
  const resultFiles = chunkParts.flatMap(([stem, parts]) => writeParts(stem, parts));
  const partFiles = writeParts("spec", readParts(specText, partBytes));
  // A `refs` entry's delivered part is read from the context, so its parts sit
  // with the results, which a pass must read whole (finalOutput).
  const contextFiles = refs ? writeParts("context", readParts(readFileSync(env.CONTEXT_FILE, "utf8"), partBytes)) : [env.CONTEXT_FILE];
  const listed = (files) => files.map((file) => `  - \`${file}\``).join("\n");
  const template = readFileSync(env.PROMPT_TEMPLATE, "utf8");
  const prompt = [
    ["RESULT_FILES", listed(resultFiles)],
    ["SPEC_PARTS", listed(partFiles)],
    ["MANIFEST_PARTS", listed(filesIn(env.MANIFEST_DIR).sort())],
    ["CONTEXT_FILE", contextFiles.join("`, `")],
    ["PR_FILE", env.PR_FILE],
    ["SPEC_FILE", env.SPEC_FILE],
  ].reduce((text, [token, value]) => text.replaceAll(token, () => value), template);
  writeFileSync(env.PROMPT_FILE, prompt);
  writeFileSync(env.SCHEMA_FILE, `${JSON.stringify(FINAL_SCHEMA)}\n`);
}

export function main(env = process.env) {
  for (const key of [
    "EXECUTION_FILES",
    "LOG_FILES",
    "CHUNKS",
    "DIFF_DIR",
    "PR_NUMBER",
    "HEAD_SHA",
    "BASE_SHA",
    "HEAD_REF",
    "SPEC_FILE",
    "GITHUB_RUN_ID",
    "VERDICT_DIR",
    "GITHUB_OUTPUT",
  ]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const { count, results } = judgedChunks(env);
  const output = headOutput(env, count, results);
  let linkedIssues;
  try {
    linkedIssues = JSON.parse(readFileSync(env.SPEC_FILE, "utf8"));
  } catch {
    throw new Error("the linked issues file is unreadable");
  }
  let specText = [];
  if (env.SPEC_TEXT_FILE) {
    try {
      specText = JSON.parse(readFileSync(env.SPEC_TEXT_FILE, "utf8"));
    } catch {
      throw new Error("the spec text file is unreadable");
    }
  }
  // The evidence inputs are optional: no capture summary file is no-app, and
  // an unreadable one is blocked (null); a trusted PR text file
  // (select-trusted-text's context) that is unreadable or for another pull
  // request leaves local_loop null.
  let capture;
  if (env.CAPTURE_FILE && existsSync(env.CAPTURE_FILE)) {
    try {
      capture = JSON.parse(readFileSync(env.CAPTURE_FILE, "utf8"));
    } catch {
      capture = null;
    }
  }
  let prBody = null;
  if (env.CONTEXT_FILE) {
    try {
      const pull = JSON.parse(readFileSync(env.CONTEXT_FILE, "utf8"))?.pr;
      prBody = String(pull?.number) === env.PR_NUMBER ? (pull.body ?? null) : null;
    } catch {
      prBody = null;
    }
  }
  const verdict = buildVerdict({
    output,
    pr: env.PR_NUMBER,
    headSha: env.HEAD_SHA,
    baseSha: env.BASE_SHA,
    runId: env.GITHUB_RUN_ID,
    headRef: env.HEAD_REF,
    linkedIssues,
    specText,
    capture,
    prBody,
  });
  mkdirSync(env.VERDICT_DIR, { recursive: true });
  writeFileSync(path.join(env.VERDICT_DIR, "verdict.json"), `${JSON.stringify(verdict, null, 2)}\n`);
  const name = artifactName(verdict);
  appendFileSync(env.GITHUB_OUTPUT, `name=${name}\nverdict=${verdict.verdict}\nretention-days=${retentionDays(verdict.verdict, env.RELINK_SINCE_HEAD !== "false")}\n`);
  results.forEach(({ k, output: one }) => console.log(`::notice title=pr-verify chunk::pr=${verdict.pr} chunk=${k}/${count} verdict=${one?.verdict ?? "none"}`));
  console.log(`write-verdict: ${name}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv[2] === "check-key-leg") {
      checkKeyLeg();
    } else if (process.argv[2] === "chunk-fail") {
      checkChunk();
    } else if (process.argv[2] === "chunk-results") {
      writeChunkResults();
    } else {
      main();
    }
  } catch (error) {
    console.log(`::error::no verdict: ${error.message}`);
    process.exitCode = 1;
  }
}
