#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { appendFileSync, mkdirSync, readdirSync, readFileSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { devNull } from "node:os";
import { dirname, join } from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

const SHA = /^[0-9a-f]{40}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const CHUNKING = fileURLToPath(new URL("../diff-chunking/diff_chunking.py", import.meta.url));
const SPLIT_UNBOUNDED = "1000000";
// https://code.claude.com/docs/en/sub-agents#concurrent-subagent-limit
const DEFAULT_SUBAGENTS = 20;

export function changedFiles(diff) {
  return [...new Set(Array.from(String(diff).matchAll(/^diff --git a\/.+? b\/(.+)$/gm), (match) => match[1]))];
}

export function factsOf({ context, repository, pr, head, base, files }) {
  return {
    number: pr,
    url: `https://github.com/${repository}/pull/${pr}`,
    title: String(context?.pr?.title ?? ""),
    body: String(context?.pr?.body ?? ""),
    headRefOid: head,
    baseRefOid: base,
    files: files.map((path) => ({ path })),
  };
}

export function issueText(specText) {
  if (!Array.isArray(specText) || specText.length === 0) {
    return "No closing issue was read for this pull request.\n";
  }
  return specText
    .map((issue) => {
      const comments = (Array.isArray(issue?.comments) ? issue.comments : []).map((comment, index) => `### Comment ${index + 1}\n\n${String(comment)}\n`);
      const body = typeof issue?.body === "string" ? issue.body : "(no trusted body)";
      return [`## Issue #${Number(issue?.number)} (${issue?.spec_kind === "refs" ? "refs" : "closes"})\n\n${body}\n`, ...comments].join("\n");
    })
    .join("\n");
}

const chunkNumber = (name) => Number(/^chunk-(\d+)\.patch$/.exec(name)?.[1] ?? 0);

function chunking(args) {
  const run = spawnSync("python3", ["-I", CHUNKING, ...args], { encoding: "utf8" });
  if (run.status !== 0) {
    throw new Error(`the diff did not cut into chunks (exit ${run.status ?? run.signal}): ${String(run.stderr).trim()}`);
  }
}

export function cutDiff({ diffFile, data, chunkBytes, maxChunks, partBytes, partLines }) {
  const dir = join(data, "diff");
  mkdirSync(dir, { recursive: true });
  chunking(["split", diffFile, dir, String(chunkBytes), SPLIT_UNBOUNDED, devNull, "0", "--cut-lines"]);
  const names = readdirSync(dir)
    .filter((name) => chunkNumber(name) > 0)
    .sort((a, b) => chunkNumber(a) - chunkNumber(b));
  if (names.length === 0) {
    writeFileSync(join(dir, "chunk-1.patch"), "");
    names.push("chunk-1.patch");
  }
  const leftOut = { chunks: 0, bytes: 0, files: 0 };
  for (const name of names.slice(maxChunks)) {
    const text = readFileSync(join(dir, name), "utf8");
    leftOut.chunks += 1;
    leftOut.bytes += Buffer.byteLength(text);
    leftOut.files += (text.match(/^diff --git /gm) ?? []).length;
    unlinkSync(join(dir, name));
  }
  chunking(["parts", dir, String(partBytes), String(partLines)]);
  const chunks = names.slice(0, maxChunks).map((name) => {
    const k = chunkNumber(name);
    const parts = readdirSync(join(dir, `chunk-${k}`))
      .sort()
      .map((part) => {
        const path = `diff/chunk-${k}/${part}`;
        const text = readFileSync(join(data, path), "utf8");
        return { path, lines: (text.match(/\n/g) ?? []).length };
      });
    return { chunk: k, parts };
  });
  return { chunks, leftOut };
}

const positive = (value, name) => {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 1) throw new Error(`${name} is not a positive whole number`);
  return number;
};

export function main(env = process.env) {
  try {
    const pr = Number(env.PR_NUMBER);
    if (!Number.isSafeInteger(pr) || pr < 1 || !SHA.test(env.HEAD_SHA ?? "") || !SHA.test(env.BASE_SHA ?? "") || !REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("PR_NUMBER, HEAD_SHA, BASE_SHA or GITHUB_REPOSITORY is malformed");
    }
    const cut = {
      chunkBytes: positive(env.CHUNK_BYTES, "CHUNK_BYTES"),
      maxChunks: positive(env.MAX_CHUNKS, "MAX_CHUNKS"),
      partBytes: positive(env.PART_BYTES, "PART_BYTES"),
      partLines: positive(env.PART_LINES, "PART_LINES"),
    };
    if (!env.COVERAGE_FILE) throw new Error("COVERAGE_FILE is not set");
    const size = statSync(env.DIFF_FILE).size;
    const diff = readFileSync(env.DIFF_FILE, "utf8");
    const facts = factsOf({
      context: JSON.parse(readFileSync(env.CONTEXT_FILE, "utf8")),
      repository: env.GITHUB_REPOSITORY,
      pr,
      head: env.HEAD_SHA,
      base: env.BASE_SHA,
      files: changedFiles(diff),
    });
    const issue = issueText(JSON.parse(readFileSync(env.SPEC_TEXT_FILE, "utf8")));
    mkdirSync(env.DATA, { recursive: true });
    const { chunks, leftOut } = cutDiff({ diffFile: env.DIFF_FILE, data: env.DATA, ...cut });
    writeFileSync(join(env.DATA, "facts.json"), `${JSON.stringify(facts, null, 2)}\n`);
    writeFileSync(join(env.DATA, "issue.md"), issue);
    const listed = { chunks: chunks.map(({ chunk, parts }) => ({ chunk, parts: parts.map((part) => part.path) })), left_out: leftOut };
    writeFileSync(join(env.DATA, "chunks.json"), `${JSON.stringify(listed, null, 2)}\n`);
    const coverage = { parts: chunks.flatMap(({ parts }) => parts.map((part) => ({ path: join(env.DATA, part.path), lines: part.lines }))), left_out: leftOut };
    mkdirSync(dirname(env.COVERAGE_FILE), { recursive: true });
    writeFileSync(env.COVERAGE_FILE, `${JSON.stringify(coverage)}\n`);
    const agents = Math.max(DEFAULT_SUBAGENTS, 2 * chunks.length);
    if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, `agents=${agents}\nchunks=${chunks.length}\n`);
    console.log(
      `merge-risk input: pr=${pr} head=${env.HEAD_SHA} files=${facts.files.length} diff-bytes=${size} chunks=${chunks.length} parts=${coverage.parts.length} left-out-chunks=${leftOut.chunks}`,
    );
    if (leftOut.chunks > 0) {
      console.log(`::warning title=merge-risk::${leftOut.chunks} chunk(s) past the ${cut.maxChunks} a rating reads are left out (${leftOut.bytes} bytes, ${leftOut.files} file diffs); the rating carries a HIGH coverage row`);
    }
    return 0;
  } catch (error) {
    console.log(`::warning title=merge-risk::no rating for this head: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main();
}
