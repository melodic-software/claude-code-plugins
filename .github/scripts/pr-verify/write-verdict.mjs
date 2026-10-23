// Checks the verifier's structured output, the last result message of
// run-claude-cli's execution file, and writes the verdict file that
// pr-verify.yml uploads as pr-verify-<pr>-<head-sha>-<verdict>, a FAIL's name
// followed by `-i` and the issues it records (`artifactName`). Every reader
// also accepts that name followed by `-<headRefDigest of the head branch>`,
// which lets the pr-merge lane tie a FAIL to a branch without downloading it;
// this writer moves to it once the readers have run on main. The output
// must be exactly {verdict, summary, notes}: verdict pass, pass-notes or fail,
// summary a string, notes an array of strings, none matching the shared
// credential patterns (lib/publish-gate.mjs findSecret), since the verdict is
// uploaded; a run with any permission
// denial writes none. The file also records the head
// branch and the linked issues with their authors, as the resolver read them
// (number, author and last body editor login, id and type, last_edited_at;
// each nullable but the number), which the pr-merge
// lane's reader checks. Anything malformed throws, so the job fails and
// uploads nothing. Model text is cut to fixed lengths (judgment) and never
// reaches a shell.

import { createHash } from "node:crypto";
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { findSecret } from "../../../lib/publish-gate.mjs";

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

export function buildVerdict({ output, pr, headSha, baseSha, runId, headRef, linkedIssues, specText = [] }) {
  if (
    !NUMBER.test(String(pr)) ||
    !SHA.test(headSha ?? "") ||
    !SHA.test(baseSha ?? "") ||
    !RUN_ID.test(String(runId)) ||
    !REF.test(headRef ?? "")
  ) {
    throw new Error("the PR number, a SHA, the run id or the head branch is malformed");
  }
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
  const own = Array.isArray(specText) ? specText.find((entry) => entry?.source === "pull-request") : undefined;
  return {
    pr: Number(pr),
    head_sha: headSha,
    base_sha: baseSha,
    head_ref: headRef,
    linked_issues: checkIssues(linkedIssues),
    // What the spec was: the pull request's own title and body
    // (babysit_verify_evidence.INTENT_PULL_REQUEST), else its closing issues.
    intent: own ? "pull-request" : "issues",
    // The title and body it judged, which the gate compares live
    // (babysit_verify_evidence): an edit since refuses the pass.
    ...(own ? { intent_sha256: createHash("sha256").update(String(own.body)).digest("hex") } : {}),
    verdict: parsed.verdict,
    summary: parsed.summary.slice(0, SUMMARY_MAX),
    notes: parsed.notes.slice(0, NOTES_MAX).map((note) => note.slice(0, NOTE_MAX)),
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

// After the key leg hands off, the subscription job judges on a new VM
// that cannot read this leg's log, so the key job records here whether the
// leg was free of denials; the subscription job runs only on clean=true.
export function checkKeyLeg(env = process.env) {
  for (const key of ["LOG_FILE", "GITHUB_OUTPUT"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  let logText;
  try {
    logText = readFileSync(env.LOG_FILE, "utf8");
  } catch {
    throw new Error("the run log is unreadable");
  }
  earlierDenials(logText);
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
export function artifactName(verdict) {
  const name = `pr-verify-${verdict.pr}-${verdict.head_sha}-${verdict.verdict}`;
  const issues = [...new Set((verdict.linked_issues ?? []).map((issue) => issue.number))].sort((a, b) => a - b);
  if (verdict.verdict !== "fail" || issues.length === 0) {
    return name;
  }
  if (issues.length > NAMED_ISSUES_MAX) {
    throw new Error(`the verdict records ${issues.length} issues, more than a name carries`);
  }
  return `${name}-i${issues.join(".")}`;
}

export function main(env = process.env) {
  for (const key of [
    "EXECUTION_FILE",
    "LOG_FILE",
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
  let messages;
  try {
    messages = JSON.parse(readFileSync(env.EXECUTION_FILE, "utf8"));
  } catch {
    throw new Error("the execution file is unreadable");
  }
  const output = structuredOutput(messages);
  let logText;
  try {
    logText = readFileSync(env.LOG_FILE, "utf8");
  } catch {
    throw new Error("the run log is unreadable");
  }
  earlierDenials(logText);
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
  const verdict = buildVerdict({
    output,
    pr: env.PR_NUMBER,
    headSha: env.HEAD_SHA,
    baseSha: env.BASE_SHA,
    runId: env.GITHUB_RUN_ID,
    headRef: env.HEAD_REF,
    linkedIssues,
    specText,
  });
  mkdirSync(env.VERDICT_DIR, { recursive: true });
  writeFileSync(path.join(env.VERDICT_DIR, "verdict.json"), `${JSON.stringify(verdict, null, 2)}\n`);
  appendFileSync(env.GITHUB_OUTPUT, `name=${artifactName(verdict)}\nverdict=${verdict.verdict}\n`);
  console.log(`write-verdict: ${artifactName(verdict)}`);
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
