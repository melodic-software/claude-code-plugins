import { appendFileSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { findSecret } from "../../../lib/publish-gate.mjs";

export const SCHEMA = 1;
export const LANES = Object.freeze(["claude-review", "claude-security-review"]);
export const SEVERITIES = Object.freeze(["CRITICAL", "IMPORTANT", "SUGGESTION"]);
export const LONG_LINE_BYTES = 1800;
const FINDINGS_MAX = 200;
const TEXT_MAX = 2000;
const SUMMARY_MAX = 4000;
export const MERGED_SUMMARY_MAX = 4 * SUMMARY_MAX;
const SHA = /^[0-9a-f]{40}$/;
const NUMBER = /^[1-9][0-9]{0,9}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;
const FINDING_KEYS = "body,line,path,severity,title";
const FOLD = /(?<!\s)(?:\s*\\ continued: ?)+/g;

const isObject = (value) => typeof value === "object" && value !== null && !Array.isArray(value);

export function artifactName(lane, pr, tree) {
  return `pr-review-main-${lane}-${pr}-${tree}`;
}

export function structuredOutput(messages) {
  const result = Array.isArray(messages) ? messages.findLast((message) => message?.type === "result") : undefined;
  if (result?.structured_output === undefined) {
    throw new Error("the run left no result with a structured output");
  }
  const denials = Array.isArray(result.permission_denials) ? result.permission_denials : [];
  if (denials.length > 0) {
    throw new Error(`the run hit ${denials.length} permission denial(s)`);
  }
  return result.structured_output;
}

export function readCoverage(messages, parts) {
  if (!Array.isArray(messages) || !Array.isArray(parts) || parts.length === 0) {
    throw new Error("the diff parts or the run's messages are unreadable");
  }
  const content = (type) =>
    messages.filter((m) => m?.type === type).flatMap((m) => (Array.isArray(m?.message?.content) ? m.message.content : []));
  const failed = new Set(content("user").filter((c) => c?.type === "tool_result" && c.is_error).map((c) => c.tool_use_id));
  const whole = new Set(
    content("assistant")
      .filter(
        (c) =>
          c?.type === "tool_use" &&
          c.name === "Read" &&
          typeof c.input?.file_path === "string" &&
          c.input.offset === undefined &&
          c.input.limit === undefined &&
          !failed.has(c.id),
      )
      .map((c) => path.resolve(c.input.file_path)),
  );
  const missed = parts.filter((part) => !whole.has(path.resolve(part)));
  if (missed.length > 0) {
    throw new Error(`the run did not read ${missed.length} of ${parts.length} diff part(s) whole`);
  }
}

export function longestLine(texts) {
  let longest = 0;
  for (const text of texts) {
    for (const line of text.split("\n")) {
      longest = Math.max(longest, Buffer.byteLength(line, "utf8") - 1);
    }
  }
  if (longest > LONG_LINE_BYTES) {
    throw new Error(`a diff line is ${longest} bytes, over the ${LONG_LINE_BYTES} the review reads whole`);
  }
  return longest;
}

export function buildVerdict({ output, lane, pr, headSha, baseSha, tree, standardsSha, runId, maxLineBytes }) {
  if (!LANES.includes(lane)) {
    throw new Error("unknown lane");
  }
  if (!Number.isSafeInteger(maxLineBytes) || maxLineBytes < 0 || maxLineBytes > LONG_LINE_BYTES) {
    throw new Error("the longest diff line is not measured within the cap");
  }
  if (!NUMBER.test(String(pr)) || !RUN_ID.test(String(runId))) {
    throw new Error("the pull request number or run id is malformed");
  }
  for (const sha of [headSha, baseSha, tree, standardsSha]) {
    if (!SHA.test(String(sha))) {
      throw new Error("a head, base, tree or standards SHA is malformed");
    }
  }
  if (!isObject(output) || Object.keys(output).sort().join() !== "findings,summary") {
    throw new Error("the output is not exactly {findings, summary}");
  }
  if (typeof output.summary !== "string" || !Array.isArray(output.findings) || output.findings.length > FINDINGS_MAX) {
    throw new Error("the summary is not a string or the findings are not a bounded list");
  }
  const findings = output.findings.map((finding) => {
    if (
      !isObject(finding) ||
      Object.keys(finding).sort().join() !== FINDING_KEYS ||
      !SEVERITIES.includes(finding.severity) ||
      typeof finding.path !== "string" ||
      !Number.isSafeInteger(finding.line) ||
      finding.line < 0 ||
      typeof finding.title !== "string" ||
      typeof finding.body !== "string"
    ) {
      throw new Error("a finding is not {severity, path, line, title, body}");
    }
    return {
      severity: finding.severity,
      path: finding.path.slice(0, 400),
      line: finding.line,
      title: finding.title.slice(0, 300),
      body: finding.body.slice(0, TEXT_MAX),
    };
  });
  const summary = output.summary.slice(0, SUMMARY_MAX);
  for (const text of [summary, ...findings.flatMap((f) => [f.path, f.title, f.body])]) {
    if (findSecret(text) || findSecret(text.replace(FOLD, ""))) {
      throw new Error("the review's text matches a credential pattern; nothing is uploaded");
    }
  }
  return {
    schema: SCHEMA,
    lane,
    pr: Number(pr),
    head_sha: headSha,
    base_sha: baseSha,
    tree,
    standards_sha: standardsSha,
    run_id: Number(runId),
    findings: findings.length,
    critical: findings.filter((f) => f.severity === "CRITICAL").length,
    max_line_bytes: maxLineBytes,
    summary,
    items: findings,
  };
}

export function buildChunkedVerdict({ outputs, ...rest }) {
  if (!Array.isArray(outputs) || outputs.length === 0) {
    throw new Error("there is no chunk output");
  }
  const chunks = outputs.map((output, i) => {
    try {
      return buildVerdict({ ...rest, output });
    } catch (error) {
      throw new Error(`chunk ${i + 1} of ${outputs.length}: ${error.message}`);
    }
  });
  if (chunks.length === 1) {
    return chunks[0];
  }
  const room = Math.min(SUMMARY_MAX, Math.floor(MERGED_SUMMARY_MAX / chunks.length));
  return {
    ...chunks[0],
    findings: chunks.reduce((sum, c) => sum + c.findings, 0),
    critical: Math.max(...chunks.map((c) => c.critical)),
    summary: chunks.map((c, i) => `Chunk ${i + 1} of ${chunks.length}: ${c.summary.slice(0, room)}`).join("\n\n"),
    items: chunks.flatMap((c, i) => c.items.map((item) => ({ ...item, chunk: i + 1 }))),
  };
}

export function executionFiles(env, count) {
  return Array.from({ length: count }, (_, i) => (i === 0 ? env.EXECUTION_FILE : env.CHUNKS_DIR && path.join(env.CHUNKS_DIR, `chunk-${i + 1}`, "execution.json")));
}

export function main(env = process.env) {
  for (const key of ["EXECUTION_FILE", "CHUNKS", "LANE", "PR_NUMBER", "HEAD_SHA", "BASE_SHA", "TREE_SHA", "STANDARDS_SHA", "GITHUB_RUN_ID", "VERDICT_DIR", "DIFF_DIR", "GITHUB_OUTPUT"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  if (!/^[1-9][0-9]?$/.test(env.CHUNKS)) {
    throw new Error("the chunk count is malformed");
  }
  const count = Number(env.CHUNKS);
  let dirs;
  try {
    dirs = readdirSync(env.DIFF_DIR).filter((name) => /^chunk-\d+$/.test(name));
  } catch {
    throw new Error("the diff chunks are unreadable");
  }
  const want = Array.from({ length: count }, (_, i) => `chunk-${i + 1}`);
  if (dirs.length !== count || !want.every((name) => dirs.includes(name))) {
    throw new Error(`the diff holds ${dirs.length} chunk directories, not the ${count} the diff step wrote`);
  }
  const files = executionFiles(env, count);
  const chunks = want.map((name, i) => {
    const label = `chunk ${i + 1} of ${count}`;
    let parts;
    try {
      parts = readdirSync(path.join(env.DIFF_DIR, name))
        .filter((part) => /^part-\d{3}\.patch$/.test(part))
        .map((part) => path.join(env.DIFF_DIR, name, part));
    } catch {
      throw new Error(`${label}: the diff parts are unreadable`);
    }
    try {
      if (!files[i]) {
        throw new Error("no review ran");
      }
      let messages;
      try {
        messages = JSON.parse(readFileSync(files[i], "utf8"));
      } catch {
        throw new Error("the execution file is unreadable");
      }
      readCoverage(messages, parts);
      const texts = parts.map((part) => readFileSync(part, "utf8"));
      return { texts, output: structuredOutput(messages), bytes: texts.reduce((sum, t) => sum + Buffer.byteLength(t, "utf8"), 0) };
    } catch (error) {
      throw new Error(`${label}: ${error.message}`);
    }
  });
  const verdict = buildChunkedVerdict({
    outputs: chunks.map((c) => c.output),
    maxLineBytes: longestLine(chunks.flatMap((c) => c.texts)),
    lane: env.LANE,
    pr: env.PR_NUMBER,
    headSha: env.HEAD_SHA,
    baseSha: env.BASE_SHA,
    tree: env.TREE_SHA,
    standardsSha: env.STANDARDS_SHA,
    runId: env.GITHUB_RUN_ID,
  });
  mkdirSync(env.VERDICT_DIR, { recursive: true });
  writeFileSync(path.join(env.VERDICT_DIR, "verdict.json"), `${JSON.stringify(verdict, null, 2)}\n`);
  const name = artifactName(verdict.lane, verdict.pr, verdict.tree);
  appendFileSync(env.GITHUB_OUTPUT, `name=${name}\nfindings=${verdict.findings}\ncritical=${verdict.critical}\n`);
  chunks.forEach((c, i) => {
    const critical = c.output.findings.filter((f) => f.severity === "CRITICAL").length;
    console.log(`::notice title=pr-review-main chunk::lane=${verdict.lane} chunk=${i + 1}/${count} bytes=${c.bytes} findings=${c.output.findings.length} critical=${critical}`);
  });
  console.log(`write-verdict: ${name} findings=${verdict.findings} critical=${verdict.critical}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.log(`::error::${String(error.message).replaceAll(/[\r\n]/g, " ")}`);
    process.exit(1);
  }
}
