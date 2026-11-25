#!/usr/bin/env node

import { mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const SHA = /^[0-9a-f]{40}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

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

export function main(env = process.env) {
  try {
    const pr = Number(env.PR_NUMBER);
    if (!Number.isSafeInteger(pr) || pr < 1 || !SHA.test(env.HEAD_SHA ?? "") || !SHA.test(env.BASE_SHA ?? "") || !REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("PR_NUMBER, HEAD_SHA, BASE_SHA or GITHUB_REPOSITORY is malformed");
    }
    const max = Number(env.MAX_DIFF_BYTES);
    const size = statSync(env.DIFF_FILE).size;
    if (!Number.isSafeInteger(max) || size > max) {
      throw new Error(`the diff is ${size} bytes, over the ${env.MAX_DIFF_BYTES} a rating reads`);
    }
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
    writeFileSync(join(env.DATA, "facts.json"), `${JSON.stringify(facts, null, 2)}\n`);
    writeFileSync(join(env.DATA, "pr.diff"), diff);
    writeFileSync(join(env.DATA, "issue.md"), issue);
    console.log(`merge-risk input: pr=${pr} head=${env.HEAD_SHA} files=${facts.files.length} diff-bytes=${size}`);
    return 0;
  } catch (error) {
    console.log(`::warning title=merge-risk::no rating for this head: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main();
}
