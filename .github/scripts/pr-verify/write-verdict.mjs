// Checks the verifier's structured output, the last result message of
// run-claude-cli's execution file, and writes the verdict file that
// pr-verify.yml uploads as pr-verify-<pr>-<head-sha>-<verdict>. The output
// must be exactly {verdict, summary, notes}: verdict pass, pass-notes or fail,
// summary a string, notes an array of strings, none shaped like an Anthropic
// key or OAuth token, since the verdict is uploaded. The file also records the head
// branch and the linked issues with their authors, as the resolver read them
// (number, author and last body editor login, id and type, last_edited_at;
// each nullable but the number), which the pr-merge
// lane's reader checks. Anything malformed throws, so the job fails and
// uploads nothing. Model text is cut to fixed lengths (judgment) and never
// reaches a shell.

import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { SECRET_PATTERNS } from "../../../lib/publish-gate.mjs";

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

// Both credential kinds start sk-ant-.
const ANTHROPIC_KEY = SECRET_PATTERNS.find(([label]) => label === "Anthropic key")[1];

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

export function buildVerdict({ output, pr, headSha, baseSha, runId, headRef, linkedIssues }) {
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
  if ([parsed.summary, ...parsed.notes].some((text) => ANTHROPIC_KEY.test(text))) {
    throw new Error("the structured output holds text shaped like an Anthropic credential");
  }
  return {
    pr: Number(pr),
    head_sha: headSha,
    base_sha: baseSha,
    head_ref: headRef,
    linked_issues: checkIssues(linkedIssues),
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
  return result.structured_output;
}

export const artifactName = (verdict) => `pr-verify-${verdict.pr}-${verdict.head_sha}-${verdict.verdict}`;

export function main(env = process.env) {
  for (const key of [
    "EXECUTION_FILE",
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
  let linkedIssues;
  try {
    linkedIssues = JSON.parse(readFileSync(env.SPEC_FILE, "utf8"));
  } catch {
    throw new Error("the linked issues file is unreadable");
  }
  const verdict = buildVerdict({
    output,
    pr: env.PR_NUMBER,
    headSha: env.HEAD_SHA,
    baseSha: env.BASE_SHA,
    runId: env.GITHUB_RUN_ID,
    headRef: env.HEAD_REF,
    linkedIssues,
  });
  mkdirSync(env.VERDICT_DIR, { recursive: true });
  writeFileSync(path.join(env.VERDICT_DIR, "verdict.json"), `${JSON.stringify(verdict, null, 2)}\n`);
  appendFileSync(env.GITHUB_OUTPUT, `name=${artifactName(verdict)}\nverdict=${verdict.verdict}\n`);
  console.log(`write-verdict: ${artifactName(verdict)}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.log(`::error::no verdict: ${error.message}`);
    process.exitCode = 1;
  }
}
