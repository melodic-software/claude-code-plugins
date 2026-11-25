#!/usr/bin/env node
// write-rating.mjs: turns /review:merge-risk's result into rating.json for
// pr-rate-merge-risk.yml to upload as pr-merge-risk-<pr>-<head>, which
// enable-auto-merge.mjs reads before it arms (merge-risk-line.mjs).
//
// The result is untrusted: it is derived from the pull request's own text.
// Its shape is checked against a closed schema (merge-risk-line.mjs
// checkResult), max and demote are recomputed from its rows, and the rater
// and checker are the model ids the execution file shows ran, never ids the
// model wrote. A run with any permission denial reached past its data and
// leaves no rating. Exit 1 with nothing written on any refusal.
//
// Environment:
//   OUTPUT_FILE      run-claude-cli's structured-output-file (credential-scanned)
//   EXECUTION_FILE   run-claude-cli's execution-file, for denials and model ids
//   PLUGIN_MANIFEST  the base review plugin's .claude-plugin/plugin.json
//   PR_NUMBER, HEAD_SHA  the pull request and head the run rated
//   CLI_VERSION      run-claude-cli's cli-version output
//   STARTED_AT       the rating step's start, in epoch seconds
//   OUT_DIR          where rating.json is written

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { checkResult, modelsOf, RATING_FILE } from "../pr-merge/merge-risk-line.mjs";

const VERSION = /^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$/;

const iso = (seconds) => new Date(Number(seconds) * 1000).toISOString();

// Tools the blind checker's agent file declares (review:brief-reviewer) that
// the cage withholds: a denial of one reached nothing. A denial of any other
// tool, a Read outside the data directory above all, refuses the rating.
export const WITHHELD = Object.freeze(["Bash", "Glob", "Grep"]);

const contentOf = (message) => (Array.isArray(message?.message?.content) ? message.message.content : []);

export function unreadParts(messages, parts) {
  const list = Array.isArray(messages) ? messages : [];
  const thread = (message) => message?.parent_tool_use_id ?? "";
  const succeeded = new Set(
    list
      .filter((message) => message?.type === "user")
      .flatMap((message) => contentOf(message).filter((block) => block?.type === "tool_result" && block.is_error !== true).map((block) => `${thread(message)}\0${block.tool_use_id}`)),
  );
  const ranges = new Map();
  for (const message of list) {
    if (message?.type !== "assistant") continue;
    for (const block of contentOf(message)) {
      if (block?.type !== "tool_use" || block.name !== "Read" || typeof block.input?.file_path !== "string" || !succeeded.has(`${thread(message)}\0${block.id}`)) continue;
      const start = Math.max(1, Number(block.input.offset ?? 1) || 1);
      const end = block.input.limit === undefined ? Infinity : start + (Number(block.input.limit) || 0) - 1;
      const path = resolve(block.input.file_path);
      ranges.set(path, [...(ranges.get(path) ?? []), [start, end]]);
    }
  }
  const reach = (path) => {
    let next = 1;
    for (const [start, end] of (ranges.get(path) ?? []).sort((a, b) => a[0] - b[0])) {
      if (start > next) break;
      next = Math.max(next, end + 1);
    }
    return next - 1;
  };
  return parts.filter((part) => reach(resolve(part.path)) < Math.max(1, part.lines));
}

export function coverageRow(messages, coverage) {
  if (coverage === undefined) return undefined;
  const parts = Array.isArray(coverage?.parts) ? coverage.parts : [];
  const leftOut = Number(coverage?.left_out?.chunks ?? 0);
  const unread = unreadParts(messages, parts);
  if (unread.length === 0 && leftOut === 0) return undefined;
  const why = [
    unread.length > 0 ? `${unread.length} of ${parts.length} diff parts were never read whole by any agent` : "",
    leftOut > 0 ? `${leftOut} chunk(s) of the diff (${Number(coverage.left_out.bytes)} bytes) were past the most a rating reads and left out` : "",
  ]
    .filter(Boolean)
    .join("; ");
  return { area: "Diff coverage", level: "HIGH", why: `${why}, so this rating does not cover the whole diff.`, check: "unchecked", checker_level: "", checker: "" };
}

export function buildRating({ output, messages, pr, head, rubric, cliVersion, startedAt, endedAt, coverage }) {
  const result = Array.isArray(messages) ? messages.findLast((message) => message?.type === "result") : undefined;
  const denials = (Array.isArray(result?.permission_denials) ? result.permission_denials : []).filter((denial) => !WITHHELD.includes(denial?.tool_name));
  if (denials.length > 0) {
    throw new Error(`the run hit ${denials.length} permission denial(s) past its data, so its rating does not stand`);
  }
  if (!VERSION.test(String(rubric ?? ""))) {
    throw new Error("the review plugin's version is not a rubric version");
  }
  if (!VERSION.test(String(cliVersion ?? ""))) {
    throw new Error("the CLI version is malformed");
  }
  const gap = coverageRow(messages, coverage);
  const checked = checkResult(gap && Array.isArray(output?.risks) ? { ...output, risks: [...output.risks, gap] } : output, { pr, head });
  return { ...checked, rubric, ...modelsOf(messages), cli_version: cliVersion, started_at: iso(startedAt), ended_at: iso(endedAt) };
}

export function main(env = process.env, clock = Date.now) {
  try {
    const pr = Number(env.PR_NUMBER);
    if (!Number.isSafeInteger(pr) || pr < 1 || !/^[0-9]{1,12}$/.test(String(env.STARTED_AT ?? ""))) {
      throw new Error("PR_NUMBER or STARTED_AT is malformed");
    }
    if (!env.COVERAGE_FILE) throw new Error("COVERAGE_FILE is not set");
    const rating = buildRating({
      output: JSON.parse(readFileSync(env.OUTPUT_FILE, "utf8")),
      messages: JSON.parse(readFileSync(env.EXECUTION_FILE, "utf8")),
      pr,
      head: env.HEAD_SHA,
      rubric: JSON.parse(readFileSync(env.PLUGIN_MANIFEST, "utf8"))?.version,
      cliVersion: env.CLI_VERSION,
      startedAt: env.STARTED_AT,
      endedAt: Math.floor(clock() / 1000),
      coverage: JSON.parse(readFileSync(env.COVERAGE_FILE, "utf8")),
    });
    mkdirSync(env.OUT_DIR, { recursive: true });
    writeFileSync(join(env.OUT_DIR, RATING_FILE), `${JSON.stringify(rating, null, 2)}\n`);
    console.log(`write-rating: pr=${pr} head=${rating.head} max=${rating.max} demote=${rating.demote} rater=${rating.rater} checker=${rating.checker}`);
    return 0;
  } catch (error) {
    console.log(`::warning title=merge-risk::no rating for this head: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main();
}
