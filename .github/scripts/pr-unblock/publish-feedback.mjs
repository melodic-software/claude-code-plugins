#!/usr/bin/env node
// publish-feedback.mjs: the reply job of the pr-unblock lane's address-feedback
// round, a script activity with no model. The model job recorded its replies
// in an artifact; this posts exactly what it wrote, or nothing, and adds no
// judgment of its own.
//
//   1. Validates the whole artifact strictly: the runner's run.json (the
//      model job's gated head and kept threads) and the model's replies.jsonl,
//      one object per kept thread at most, each with exactly the template's
//      fields, within the limits below. Any failure posts no reply.
//   2. For VALID replies, confirms every fix commit reached the PR branch
//      after the model job's gated head and that the branch changed no path
//      but the kept threads' and none under .github/.
//   3. Re-reads each thread and skips one that is resolved, moved, or has a
//      comment the model job did not see; posts the templated reply on its
//      root comment and resolves it only when it is VALID.
//   4. Always posts the round marker, as the lanes App.
//   5. Escalates feedback-invalid, feedback-not-landed or, for an UNCERTAIN or
//      VALID-defer reply, feedback-uncertain.
//
// Environment:
//   GH_TOKEN              the lane token (pull-requests: write, contents: read)
//   GITHUB_REPOSITORY     owner/repo
//   PR_NUMBER, HEAD_SHA   the gated pull request and its current head
//   APP_SENDER_ID         the lanes App bot's user id, the round marker author
//   TRUSTED_ACTORS        the base's trusted-actors.json, for the reviewer bot
//   FEEDBACK_REPLIES_DIR  the downloaded artifact: run.json and replies.jsonl
//   RUN_SHA256            run.json's SHA-256, from the model job's runner step
//   GITHUB_WORKSPACE      the PR head checkout evidence paths are checked in
//   SKIP_REASON_FILE, ESCALATION_REASON_FILE  where the runner reads them

import { createHash } from "node:crypto";
import { existsSync, lstatSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import {
  countRounds,
  createGitHubApi,
  currentThreads,
  isProtectedPath,
  MAX_ROUNDS,
  need,
  positive,
  reviewerIdFrom,
  ROUND_MARKER,
  SHA,
} from "./address-feedback.mjs";

export const LIMITS = { bytes: 262144, note: 2000, evidence: 10, files: 300 };
const THREAD_ID = /^PRRT_[A-Za-z0-9_-]{1,100}$/;
const PATH_LINE = /^[A-Za-z0-9_@+.-]+(\/[A-Za-z0-9_@+.-]+)*:[1-9][0-9]{0,6}$/;
const DOT_SEGMENT = /(^|\/)\.\.?(\/|:)/;
// Tab and newline only, and no direction, zero-width or byte-order mark.
const BAD_CHARS = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f​-‏‪-‮⁠-⁩﻿]/u;
// HTML comments carry markers; token shapes from
// docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github#githubs-token-formats
// (as of 2026-10-15; recheck when that section adds a prefix).
const FORBIDDEN = /<!--|-->|gh[opsur]_[A-Za-z0-9]{20}|github_pat_/;
const DISPOSITIONS = ["VALID", "INCORRECT", "UNCERTAIN", "VALID-defer"];
const KEYS = ["disposition", "evidence", "fix_sha", "note", "thread"];
const LABELS = {
  VALID: "VALID, fixed",
  INCORRECT: "INCORRECT, left open",
  UNCERTAIN: "UNCERTAIN, left open for a person",
  "VALID-defer": "VALID (defer), left open for a person",
};

class Invalid extends Error {}

function check(condition, why) {
  if (!condition) {
    throw new Invalid(why);
  }
}

const sameIds = (a, b) => a.length === b.length && a.every((id, i) => id === b[i]);

// run.json is the runner's: the model job's gated head and the threads its
// select step kept, with the comment ids the model was shown.
export function parseRun(text) {
  let run;
  try {
    run = JSON.parse(text);
  } catch {
    throw new Invalid("run.json does not parse");
  }
  check(run?.version === 1 && SHA.test(run.head_sha ?? "") && Array.isArray(run.threads), "run.json is malformed");
  for (const thread of run.threads) {
    check(
      THREAD_ID.test(thread?.id ?? "") &&
        typeof thread.path === "string" &&
        Array.isArray(thread.comment_ids) &&
        thread.comment_ids.length > 0 &&
        thread.comment_ids.every((id) => Number.isSafeInteger(id) && id > 0),
      "run.json holds a malformed thread",
    );
  }
  return run;
}

// replies.jsonl is model output: every line is checked before anything posts.
export function parseReplies(text, run, fileExists) {
  check(Buffer.byteLength(text) <= LIMITS.bytes, "the replies are over the size limit");
  const kept = new Map(run.threads.map((thread) => [thread.id, thread]));
  const seen = new Set();
  const replies = [];
  for (const line of text.split("\n").filter((row) => row !== "")) {
    let reply;
    try {
      reply = JSON.parse(line);
    } catch {
      throw new Invalid("a reply line does not parse");
    }
    check(reply !== null && typeof reply === "object" && !Array.isArray(reply), "a reply is not an object");
    check(Object.keys(reply).sort().join() === KEYS.join(), "a reply's fields are not the template's");
    const { thread, disposition, evidence, fix_sha: fixSha, note } = reply;
    check(typeof thread === "string" && kept.has(thread), "a reply names a thread the runner did not keep");
    check(!seen.has(thread), "two replies name one thread");
    seen.add(thread);
    check(DISPOSITIONS.includes(disposition), "a reply's disposition is not one of the four");
    check(
      Array.isArray(evidence) &&
        evidence.length <= LIMITS.evidence &&
        evidence.every((ev) => typeof ev === "string" && PATH_LINE.test(ev) && !DOT_SEGMENT.test(ev)),
      "a reply's evidence is not a list of path:line",
    );
    check(!["VALID", "INCORRECT"].includes(disposition) || evidence.length > 0, "a VALID or INCORRECT reply cites no evidence");
    check(
      evidence.every((ev) => fileExists(ev.slice(0, ev.lastIndexOf(":")))),
      "a reply's evidence names a file not in the checkout",
    );
    check(disposition === "VALID" ? SHA.test(fixSha) : fixSha === "", "a reply's fix_sha does not match its disposition");
    check(
      typeof note === "string" && note.length > 0 && note.length <= LIMITS.note && !BAD_CHARS.test(note) && !FORBIDDEN.test(note),
      "a reply's note is empty, too long, or holds a control character, an HTML comment or a token",
    );
    replies.push({ thread, disposition, evidence, fixSha, note });
  }
  return replies;
}

// The note sits in a fence longer than any backtick run in it.
export function renderReply({ disposition, evidence, fixSha, note }) {
  const fence = "`".repeat(Math.max(3, ...[...note.matchAll(/`+/g)].map((run) => run[0].length + 1)));
  return [
    `**pr-unblock / address-feedback: ${LABELS[disposition]}**`,
    "",
    evidence.length > 0 ? `Evidence: ${evidence.map((ev) => `\`${ev}\``).join(", ")}` : "Evidence: none in the checkout",
    ...(fixSha ? [`Fix: ${fixSha}`] : []),
    "",
    `${fence}text`,
    note,
    fence,
  ].join("\n");
}

// Whenever the PR branch moved since the model job's gated head, or a reply is
// VALID, that range may change only the kept threads' paths (run.json, whose
// SHA-256 the model job's runner recorded), and nothing under .github/. Every VALID
// fix must be a commit in that range that changes its own thread's path.
async function fixesLanded({ api, run, headSha, replies }) {
  const valid = replies.filter((reply) => reply.disposition === "VALID");
  if (valid.length === 0 && run.head_sha === headSha) {
    return true;
  }
  const comparison = await api.compare(run.head_sha, headSha);
  const commits = new Set((comparison.commits ?? []).map((commit) => commit.sha));
  const threadPath = new Map(run.threads.map((thread) => [thread.id, thread.path]));
  const paths = new Set(threadPath.values());
  const files = comparison.files ?? [];
  const inRange =
    ["ahead", "identical"].includes(comparison.status) &&
    valid.every((reply) => commits.has(reply.fixSha)) &&
    files.length < LIMITS.files &&
    files.every((file) =>
      [file.filename, file.previous_filename].every(
        (path) => path === undefined || (paths.has(path) && !isProtectedPath(path)),
      ),
    );
  if (!inRange) {
    return false;
  }
  for (const reply of valid) {
    const changed = ((await api.getCommit(reply.fixSha)).files ?? []).map((file) => file.filename);
    if (!changed.includes(threadPath.get(reply.thread))) {
      return false;
    }
  }
  return true;
}

// Resolves a VALID thread only while it holds exactly the model's view plus
// this reply, so a comment posted meanwhile is not resolved unread. One retry
// covers a transient read or resolve failure; false means it changed.
async function resolveAfterReply(api, id, expected) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      const after = await api.readThread(id);
      if (after.isResolved !== false || !sameIds(after.commentIds, expected)) {
        return false;
      }
      if ((await api.resolveThread(id)) !== true) {
        throw new Error(`replied on ${id} but it does not read resolved`);
      }
      return true;
    } catch (error) {
      if (attempt >= 2) {
        throw error;
      }
    }
  }
}

export async function publish({ api, pr, headSha, appId, reviewerId, readArtifact, fileExists, log = () => {} }) {
  let escalationReason = "";
  try {
    let run;
    let replies;
    try {
      const { runText, repliesText } = readArtifact();
      run = parseRun(runText);
      replies = parseReplies(repliesText, run, fileExists);
    } catch (error) {
      if (!(error instanceof Invalid) && error.code !== "ENOENT") {
        throw error;
      }
      log(`no reply is posted: ${error instanceof Invalid ? error.message : "the artifact is missing"}`);
      escalationReason = "feedback-invalid";
      return { escalationReason, posted: [] };
    }
    const { kept } = await currentThreads({ api, pr, reviewerId });
    const now = new Map(kept.map((thread) => [thread.id, thread]));
    if (!(await fixesLanded({ api, run, headSha, replies }))) {
      log("no reply is posted: a VALID fix did not reach the PR branch, or the branch changed another path");
      escalationReason = "feedback-not-landed";
      return { escalationReason, posted: [] };
    }
    if (replies.some((reply) => reply.disposition === "UNCERTAIN" || reply.disposition === "VALID-defer")) {
      escalationReason = "feedback-uncertain";
    }
    const shown = new Map(run.threads.map((thread) => [thread.id, thread]));
    const posted = [];
    for (const reply of replies) {
      const ids = shown.get(reply.thread).comment_ids;
      const fresh = now.get(reply.thread);
      const reread = fresh && (await api.readThread(reply.thread));
      if (
        !fresh ||
        !sameIds(fresh.comments.map((comment) => comment.id), ids) ||
        reread.isResolved !== false ||
        reread.pr !== pr ||
        reread.commentCount !== ids.length ||
        !sameIds(reread.commentIds, ids)
      ) {
        log(`skipped ${reply.thread}: it changed since the model job read it`);
        continue;
      }
      // Once a reply posts, the thread is no longer the reviewer bot's alone,
      // so no later round selects it again: a failure from here on, or a VALID
      // thread left open, hands the PR to a person instead of stranding it.
      try {
        const answer = await api.replyToComment(pr, ids[0], renderReply(reply));
        if (answer?.in_reply_to_id !== ids[0]) {
          throw new Error(`the reply on ${reply.thread} did not land on its thread`);
        }
        posted.push({ thread: reply.thread, disposition: reply.disposition });
        if (reply.disposition === "VALID" && !(await resolveAfterReply(api, reply.thread, [...ids, answer.id]))) {
          log(`replied on ${reply.thread} but left it open: it changed while the reply was posted`);
          escalationReason = "feedback-partial";
          continue;
        }
      } catch (error) {
        log(`stopped at ${reply.thread}: ${String(error?.message ?? error).slice(0, 300)}`);
        escalationReason = "feedback-partial";
        break;
      }
      log(`replied on ${reply.thread} (${reply.disposition})${reply.disposition === "VALID" ? "; resolved" : ""}`);
    }
    return { escalationReason, posted };
  } finally {
    // The round counts whatever happened above, so the cap holds.
    const rounds = countRounds(await api.listIssueComments(pr), appId) + 1;
    await api.createIssueComment(
      pr,
      [ROUND_MARKER, `pr-unblock / address-feedback finished round ${rounds} of ${MAX_ROUNDS} on ${headSha}.`].join("\n"),
    );
    log(`recorded round ${rounds}${escalationReason ? `; escalating ${escalationReason}` : ""}`);
  }
}

export async function main(env, { api, log = (line) => console.log(line) } = {}) {
  need(env, [
    "GH_TOKEN",
    "GITHUB_REPOSITORY",
    "PR_NUMBER",
    "HEAD_SHA",
    "APP_SENDER_ID",
    "TRUSTED_ACTORS",
    "FEEDBACK_REPLIES_DIR",
    "GITHUB_WORKSPACE",
    "SKIP_REASON_FILE",
    "ESCALATION_REASON_FILE",
  ]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!SHA.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit id");
  }
  const dir = env.FEEDBACK_REPLIES_DIR;
  const read = (name) => {
    const path = join(dir, name);
    const stat = lstatSync(path);
    if (!stat.isFile()) {
      throw new Invalid(`${name} is not a regular file`);
    }
    if (stat.size > LIMITS.bytes + 1) {
      throw new Invalid(`${name} is over the size limit`);
    }
    return readFileSync(path, "utf8");
  };
  // run.json must be the bytes the model job's runner step wrote, whose
  // SHA-256 that job passed out as a runner-computed output.
  const readRun = () => {
    const text = read("run.json");
    if (!/^[0-9a-f]{64}$/.test(env.RUN_SHA256 ?? "") || createHash("sha256").update(text).digest("hex") !== env.RUN_SHA256) {
      throw new Invalid("run.json does not match the SHA-256 the model job recorded");
    }
    return text;
  };
  const { escalationReason } = await publish({
    api:
      api ??
      createGitHubApi({
        token: env.GH_TOKEN,
        repository: env.GITHUB_REPOSITORY,
        apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
        graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      }),
    pr,
    headSha: env.HEAD_SHA,
    appId,
    reviewerId: reviewerIdFrom(env.TRUSTED_ACTORS),
    readArtifact: () => ({ runText: readRun(), repliesText: read("replies.jsonl") }),
    fileExists: (path) => existsSync(join(env.GITHUB_WORKSPACE, path)),
    log,
  });
  if (escalationReason) {
    writeFileSync(env.ESCALATION_REASON_FILE, `${escalationReason}\n`);
    writeFileSync(env.SKIP_REASON_FILE, "awaiting-human\n");
  }
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::publish-feedback failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
