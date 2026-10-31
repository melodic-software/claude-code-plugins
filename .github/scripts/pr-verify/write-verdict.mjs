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
// summary a string, notes an array of strings, none matching the shared
// credential patterns (lib/publish-gate.mjs findSecret), since the verdict is
// uploaded; a run with any permission denial, or a chunk that left no output
// or read a part of its diff short (pr-review-main readCoverage), writes none.
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

import { findSecret } from "../../../lib/publish-gate.mjs";
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
  for (const text of [parsed.summary, ...parsed.notes]) {
    const hit = findSecret(text);
    if (hit) {
      throw new Error(`the structured output holds text shaped like a credential (${hit[0]})`);
    }
  }
  return parsed;
}

// One output from each chunk's: the worst verdict, each chunk's summary, and
// the notes, unprefixed since each starts with its path (verify-notes.mjs
// noteComments). The worst chunks come first, so the cuts in buildVerdict
// never drop a fail's notes for a pass-notes chunk's. A single chunk is its
// own output.
export function mergeChunks(outputs) {
  if (!Array.isArray(outputs) || outputs.length === 0) {
    throw new Error("no chunk left an output");
  }
  const chunks = outputs.map(parseOutput);
  if (chunks.length === 1) {
    return chunks[0];
  }
  const worst = chunks
    .map((chunk, i) => ({ ...chunk, k: i + 1 }))
    .sort((a, b) => VERDICTS.indexOf(b.verdict) - VERDICTS.indexOf(a.verdict) || a.k - b.k);
  const room = Math.floor(SUMMARY_MAX / chunks.length) - 1;
  return {
    verdict: worst[0].verdict,
    summary: worst.map(({ k, verdict, summary }) => `Chunk ${k} of ${chunks.length}, ${verdict}: ${summary}`.slice(0, room)).join("\n"),
    notes: worst.flatMap((chunk) => chunk.notes),
  };
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
    evidence: buildEvidence({ capture, prBody }),
    run_id: Number(runId),
  };
}

// The structured output of the last result message in the CLI's messages.
export function structuredOutput(messages) {
  const result = Array.isArray(messages) ? messages.findLast((message) => message?.type === "result") : undefined;
  if (result?.structured_output === undefined) {
    throw new Error("the run left no result with a structured output");
  }
  // A denied call means the model reached past its data files: no verdict.
  // Only tool names are printed, never a call's input.
  const denials = Array.isArray(result.permission_denials) ? result.permission_denials : [];
  if (denials.length > 0) {
    const names = [...new Set(denials.map((d) => (/^[A-Za-z0-9_*-]{1,64}$/.test(d?.tool_name ?? "") ? d.tool_name : "unnamed")))];
    throw new Error(`the run hit ${denials.length} permission denial(s): ${names.join(", ")}`);
  }
  return result.structured_output;
}

// run-claude-cli's log, one object per leg, counts every leg's denials.
export function earlierDenials(logText) {
  const total = logText
    .split("\n")
    .filter((line) => line.trim() !== "")
    .reduce((sum, line) => sum + (JSON.parse(line)?.denials?.count ?? 0), 0);
  if (total > 0) {
    throw new Error(`the run's legs hit ${total} permission denial(s)`);
  }
}

// A newline-separated list from a workflow's env; a step that did not run
// renders as a blank line.
const fileList = (value) =>
  String(value ?? "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

// One chunk's log, checked for a denial on any of its legs.
function checkLog(file) {
  let logText;
  try {
    logText = readFileSync(file, "utf8");
  } catch {
    throw new Error("the run log is unreadable");
  }
  earlierDenials(logText);
}

// After a leg hands off, the next job judges on a new VM that cannot read
// this leg's logs, so this job records here whether every chunk it judged was
// free of denials; the next job runs only on clean=true.
export function checkKeyLeg(env = process.env) {
  for (const key of ["LOG_FILES", "GITHUB_OUTPUT"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  // Every chunk listed here ran, so a blank line is a leg that left no log.
  const logs = env.LOG_FILES.replace(/\n$/, "").split("\n");
  if (logs.some((line) => line.trim() === "")) {
    throw new Error("the run log is unreadable");
  }
  logs.forEach((line) => checkLog(line.trim()));
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
// earlier FAIL until the pull request is TOO_OLD_DAYS (80) old
// (babysit_verify_evidence.py), and carry-run-cache.mjs RETENTION_DAYS
// matches it.
export function retentionDays(verdict, mayRelink = true) {
  return ["pass", "pass-notes"].includes(verdict) && mayRelink === false ? 7 : 90;
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
  const executions = fileList(env.EXECUTION_FILES);
  const logs = fileList(env.LOG_FILES);
  const chunkDirs = readdirSync(env.DIFF_DIR).filter((name) => /^chunk-[1-9]$/.test(name));
  const count = Number(env.CHUNKS);
  if (!/^[1-9]$/.test(env.CHUNKS) || executions.length !== count || logs.length !== count || chunkDirs.length !== count) {
    throw new Error(`the chunk count does not match ${executions.length} run(s), ${logs.length} log(s) and ${chunkDirs.length} chunk(s) of the diff`);
  }
  const outputs = executions.map((file, i) => {
    try {
      let messages;
      try {
        messages = JSON.parse(readFileSync(file, "utf8"));
      } catch {
        throw new Error("the execution file is unreadable");
      }
      const dir = path.join(env.DIFF_DIR, `chunk-${i + 1}`);
      readCoverage(
        messages,
        readdirSync(dir).map((name) => path.join(dir, name)),
      );
      const output = structuredOutput(messages);
      checkLog(logs[i]);
      return output;
    } catch (error) {
      throw new Error(`chunk ${i + 1} of ${count}: ${error.message}`);
    }
  });
  const output = mergeChunks(outputs);
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
  outputs.forEach((one, i) => console.log(`::notice title=pr-verify chunk::pr=${verdict.pr} chunk=${i + 1}/${count} verdict=${mergeChunks([one]).verdict}`));
  console.log(`write-verdict: ${name}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv[2] === "check-key-leg") {
      checkKeyLeg();
    } else {
      main();
    }
  } catch (error) {
    console.log(`::error::no verdict: ${error.message}`);
    process.exitCode = 1;
  }
}
