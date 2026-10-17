// Checks the verifier's structured output and writes the verdict file that
// pr-verify.yml uploads as pr-verify-<pr>-<head-sha>-<verdict>. The output
// must be exactly {verdict, summary, notes}: verdict pass, pass-notes or fail,
// summary a string, notes an array of strings. Anything else, or a malformed
// PR number, SHA or run id, throws, so the job fails and uploads nothing.
// Model text is cut to fixed lengths (judgment) and never reaches a shell.

import { mkdirSync, appendFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

export const VERDICTS = Object.freeze(["pass", "pass-notes", "fail"]);
const SUMMARY_MAX = 4000;
const NOTE_MAX = 1000;
const NOTES_MAX = 30;
const SHA = /^[0-9a-f]{40}$/;
const NUMBER = /^[1-9][0-9]{0,9}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;

const isObject = (value) => typeof value === "object" && value !== null && !Array.isArray(value);

export function buildVerdict({ output, pr, headSha, baseSha, runId }) {
  if (!NUMBER.test(String(pr)) || !SHA.test(headSha ?? "") || !SHA.test(baseSha ?? "") || !RUN_ID.test(String(runId))) {
    throw new Error("the PR number, a SHA or the run id is malformed");
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
  return {
    pr: Number(pr),
    head_sha: headSha,
    base_sha: baseSha,
    verdict: parsed.verdict,
    summary: parsed.summary.slice(0, SUMMARY_MAX),
    notes: parsed.notes.slice(0, NOTES_MAX).map((note) => note.slice(0, NOTE_MAX)),
    run_id: Number(runId),
  };
}

export const artifactName = (verdict) => `pr-verify-${verdict.pr}-${verdict.head_sha}-${verdict.verdict}`;

export function main(env = process.env) {
  for (const key of ["STRUCTURED_OUTPUT", "PR_NUMBER", "HEAD_SHA", "BASE_SHA", "GITHUB_RUN_ID", "VERDICT_DIR", "GITHUB_OUTPUT"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const verdict = buildVerdict({
    output: env.STRUCTURED_OUTPUT,
    pr: env.PR_NUMBER,
    headSha: env.HEAD_SHA,
    baseSha: env.BASE_SHA,
    runId: env.GITHUB_RUN_ID,
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
