#!/usr/bin/env node
// publish-feedback.mjs: the reply job of the pr-unblock lane's address-feedback
// round, a script activity with no model. The model job recorded its replies
// in an artifact; this posts exactly what it wrote, or nothing, and adds no
// judgment of its own.
//
//   1. Validates the whole artifact strictly: the select job's run.json (the
//      head it read and the kept threads) and the model's replies.jsonl,
//      one object per kept thread at most, each with exactly the template's
//      fields, within the limits below. Any failure posts no reply.
//   2. For VALID replies, which name no commit (the model job commits
//      nothing), finds the one commit apply-feedback-patch pushed: the lanes
//      App's, after the select job's head, carrying the review-threads
//      row's Lane-Activity trailer (fixCommitOf). Confirms it changes each
//      VALID thread's path and that the branch changed no path outside the
//      kept threads' scope (thread-scope.mjs) and none under
//      .github/workflows/. A
//      push that was superseded, refused, escalated or held left no such
//      commit, so the round ends feedback-not-landed.
//   3. Re-reads each thread and skips one that is resolved, moved, or has a
//      comment the model job did not see; posts the templated reply on its
//      root comment and resolves it only when it is VALID. The PR head is
//      re-read before each post and each resolve: once it is not the head
//      this job gated, nothing more is posted or resolved.
//   4. Posts the round marker, as the lanes App, once per model run: a
//      re-run of this job finds the marker naming that run and posts none.
//   5. With no replies.jsonl, no scanned patch, no scan refusal, no upload
//      the scan named and the selected head still current (no model turn)
//      posts nothing and skips no-model-turn, escalating nothing; with a
//      moved head it escalates feedback-not-landed, and beside a patch, a
//      refusal or a named upload feedback-invalid. Otherwise escalates
//      feedback-invalid, feedback-incomplete (a kept thread has no
//      disposition), feedback-not-landed, feedback-partial (posting stopped
//      after a reply), feedback-uncertain (an UNCERTAIN or VALID-defer reply)
//      or feedback-disputed (an INCORRECT reply, left open for a person).
//
// Environment:
//   GH_TOKEN              the lane token (pull-requests: write, contents: read)
//   GITHUB_REPOSITORY     owner/repo
//   PR_NUMBER, HEAD_SHA   the gated pull request and its current head
//   HEAD_REF              the PR branch, re-read for HEAD_SHA before each post
//   GITHUB_RUN_ID, MODEL_RUN_ATTEMPT  the model run the round marker names
//   APP_SENDER_ID         the lanes App bot's user id, the round marker author
//   TRUSTED_ACTORS        the base's trusted-actors.json, for the reviewer bot
//                         and the people whose replies are direction
//   FEEDBACK_REPLIES_DIR  the downloaded artifacts: the select job's run.json
//                         and the model run's scanned replies.jsonl
//   RUN_SHA256            run.json's SHA-256, from the select job
//   REPLIES_SHA256        replies.jsonl's SHA-256, from the scan job
//   REVIEW_PATCH_STATE    the scan job's patch-state for the same model call
//   SCAN_REFUSED_DIR, SCAN_REFUSED_READ  the scan-refusal job's markers for
//                         the model call and their download's outcome
//                         (address-feedback.mjs scanRefusal)
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
  isRoundMarker,
  DEFAULT_MAX_ROUNDS,
  maxRoundsFrom,
  need,
  positive,
  reviewerIdFrom,
  ROUND_MARKER,
  scanRefusal,
  SHA,
  trustedHumansFrom,
} from "./address-feedback.mjs";
import { inThreadScope } from "./thread-scope.mjs";

// bytes: replies.jsonl's cap, the read runner's carry, seal and scan cap too;
// runBytes: run.json's, the 1 MiB the read runner accepts for it.
export const LIMITS = { bytes: 49152, runBytes: 1048576, note: 2000, evidence: 10, files: 300 };
// GitHub's web-flow user, the committer of a commit made through the API.
const WEB_FLOW_ID = 19864447;
// The trailer apply-patch.mjs writes from patch-rules.json's review-threads row.
export const FIX_TRAILER = "Lane-Activity: pr-unblock/address-feedback";
const THREAD_ID = /^PRRT_[A-Za-z0-9_-]{1,100}$/;
const PATH_LINE = /^[A-Za-z0-9_@+.-]+(\/[A-Za-z0-9_@+.-]+)*:[1-9][0-9]{0,6}$/;
const DOT_SEGMENT = /(^|\/)\.\.?(\/|:)/;
// Tab and newline only, and no direction, zero-width or byte-order mark.
const BAD_CHARS = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f​-‏‪-‮⁠-⁩﻿]/u;
// HTML comments carry markers; token shapes from
// docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github#githubs-token-formats
// and the stateless installation token (ghs_ then a JWT) from
// https://github.blog/changelog/2026-05-15-github-app-installation-tokens-per-request-override-header/
// whose header gh[opsur]_[A-Za-z0-9]{20} matches; this prefix check is not GitHub's recommended regex
// (as of 2026-10-21; recheck when GitHub changes a token format or its recommended regex).
const FORBIDDEN = /<!--|-->|gh[opsur]_[A-Za-z0-9]{20}|ghs_[0-9]+_|github_pat_/;
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

// run.json is the select job's: the gated head and the threads it kept, with
// the comment ids the model was shown.
export function parseRun(text) {
  let run;
  try {
    run = JSON.parse(text);
  } catch {
    throw new Invalid("run.json does not parse");
  }
  check(
    run?.version === 1 &&
      SHA.test(run.head_sha ?? "") &&
      Array.isArray(run.threads) &&
      (run.pr_paths === undefined || (Array.isArray(run.pr_paths) && run.pr_paths.every((path) => typeof path === "string"))),
    "run.json is malformed",
  );
  for (const thread of run.threads) {
    check(
      THREAD_ID.test(thread?.id ?? "") &&
        typeof thread.path === "string" &&
        Array.isArray(thread.comment_ids) &&
        thread.comment_ids.length > 0 &&
        thread.comment_ids.every((id) => Number.isSafeInteger(id) && id > 0) &&
        (thread.named_paths === undefined ||
          (Array.isArray(thread.named_paths) && thread.named_paths.every((path) => typeof path === "string"))),
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
    // The model job commits nothing: this job finds the fix commit itself.
    check(fixSha === "", "a reply's fix_sha is not empty");
    check(
      // Code points, as jq's length counts them in the review-thread tool.
      typeof note === "string" && note.length > 0 && [...note].length <= LIMITS.note && !BAD_CHARS.test(note) && !FORBIDDEN.test(note),
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

const SKILL_FILE = /^((?:.*\/)?skills\/[^/]+\/)SKILL\.md$/;

// Whether a fix commit's changed files touch a thread's path: the path itself,
// a file the pull request already changes (`prPaths`), so a finding on one
// file fixed in another of the PR's files lands, or for a skill's SKILL.md any
// file under that skill's directory.
function touchesThread(changed, threadPath, prPaths) {
  if (changed.some((file) => prPaths.has(file))) {
    return true;
  }
  const skillDir = SKILL_FILE.exec(threadPath)?.[1];
  return skillDir === undefined ? changed.includes(threadPath) : changed.some((file) => file.startsWith(skillDir));
}

// The one commit in a range that the lanes App authored through the API (the
// web-flow committer, with a valid signature, as upstreamHeadHolds in
// check-trusted-trigger.mjs requires) with the fix trailer on a line of its
// own; null for none or more than one.
export function fixCommitOf(commits, appId) {
  const fixes = commits.filter(
    (commit) =>
      commit.author?.id === appId &&
      commit.committer?.id === WEB_FLOW_ID &&
      commit.commit?.verification?.verified === true &&
      commit.commit.verification.reason === "valid" &&
      String(commit.commit?.message ?? "")
        .split("\n")
        .some((line) => line.replace(/\r$/, "") === FIX_TRAILER),
  );
  return fixes.length === 1 ? fixes[0].sha : null;
}

// Whenever the PR branch moved since the select job's head, or a reply is
// VALID, that range may change only what inThreadScope allows around the kept
// threads' paths and the PR's own files (run.json, whose SHA-256 the select
// job recorded), adding none of those files, and nothing under
// .github/workflows/. With a VALID reply the range must hold
// exactly one fix commit (fixCommitOf), and it must change every VALID thread's path, a
// file the PR already changes, or for a thread on a skill's SKILL.md any file
// in that skill's directory (touchesThread). Returns the fix commit, "" when no reply is VALID, or null.
async function fixesLanded({ api, run, headSha, replies, appId }) {
  const valid = replies.filter((reply) => reply.disposition === "VALID");
  if (valid.length === 0 && run.head_sha === headSha) {
    return "";
  }
  const comparison = await api.compare(run.head_sha, headSha);
  const fixSha = valid.length === 0 ? "" : fixCommitOf(comparison.commits ?? [], appId);
  const threadPath = new Map(run.threads.map((thread) => [thread.id, thread.path]));
  const paths = new Set(threadPath.values());
  const prPaths = new Set(run.pr_paths ?? []);
  const files = comparison.files ?? [];
  const inRange =
    ["ahead", "identical"].includes(comparison.status) &&
    fixSha !== null &&
    files.length < LIMITS.files &&
    files.every((file) =>
      [file.filename, file.previous_filename].every(
        (path) =>
          path === undefined ||
          inThreadScope(path, paths, run.threads, {
            prPaths,
            added: path === file.filename && ["added", "renamed", "copied"].includes(file.status),
          }),
      ),
    );
  if (!inRange) {
    return null;
  }
  if (fixSha) {
    const changed = ((await api.getCommit(fixSha)).files ?? []).map((file) => file.filename);
    if (!valid.every((reply) => touchesThread(changed, threadPath.get(reply.thread), prPaths))) {
      return null;
    }
  }
  return fixSha;
}

// Resolves a VALID thread only while it holds exactly the model's view plus
// this reply, so a comment posted meanwhile is not resolved unread, and only
// while the PR head is still the gated one. One retry covers a transient read
// or resolve failure; false means the thread or the head changed.
async function resolveAfterReply(api, id, expected, headMoved) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      const after = await api.readThread(id);
      if (!sameIds(after.commentIds, expected) || (await headMoved())) {
        return false;
      }
      // A resolve that took effect before its answer was lost.
      if (after.isResolved === true && attempt > 1) {
        return true;
      }
      if (after.isResolved !== false) {
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

// The line after the round marker naming the model run whose replies this job
// posts; a re-run of this job alone reuses that run's artifact.
export const modelRunLine = (modelRun) => `<!-- pr-unblock:address-feedback-model-run ${modelRun} -->`;

export async function publish(args) {
  const { api, pr, headSha, appId, modelRun, maxRounds = DEFAULT_MAX_ROUNDS, log = () => {} } = args;
  let result = null;
  let failure = null;
  try {
    result = await postReplies({ ...args, log });
  } catch (error) {
    failure = error;
  }
  // The round counts whatever happened above, so the cap holds. A marker
  // that cannot be posted still leaves the replies' outcome to a person.
  try {
    const comments = await api.listIssueComments(pr);
    // With no model run named, the marker is always posted: counting a round
    // twice hands the PR to a person sooner; skipping one would not.
    const runLine = modelRun ? modelRunLine(modelRun) : null;
    if (runLine && comments.some((comment) => isRoundMarker(comment, appId) && String(comment.body).split("\n").includes(runLine))) {
      log(`the round of model run ${modelRun} is already recorded`);
    } else {
      const rounds = countRounds(comments, appId) + 1;
      await api.createIssueComment(
        pr,
        [ROUND_MARKER, ...(runLine ? [runLine] : []), `pr-unblock / address-feedback finished round ${rounds} of ${maxRounds} on ${headSha}.`].join("\n"),
      );
      log(`recorded round ${rounds}${result?.escalationReason ? `; escalating ${result.escalationReason}` : ""}`);
    }
  } catch (error) {
    log(`could not record the round: ${String(error?.message ?? error).slice(0, 300)}`);
    if (result !== null && result.escalationReason === "") {
      result = { ...result, escalationReason: "feedback-partial" };
    }
  }
  if (failure !== null) {
    throw failure;
  }
  return result;
}

async function postReplies({ api, pr, headSha, headRef, appId, patchState = "", scanRefused = "", repliesExpected = false, reviewerId, trustedHumans, readArtifact, fileExists, log }) {
  let escalationReason = "";
  // fixesLanded judged the range up to headSha; a push after it is unjudged.
  const headMoved = async () => (await api.readBranch(headRef)) !== headSha;
  {
    let run;
    let replies;
    try {
      const { runText, repliesText } = readArtifact();
      run = parseRun(runText);
      // No replies.jsonl. The run job decides that, so it is a skip only
      // when the scan refused nothing, named no upload, handed on no patch,
      // and the PR head is still the one the select job read: the model call
      // never ran. The round still counts. A refused scan uploads nothing
      // whatever the model did; named replies that did not arrive are a
      // failed download; a moved head is a push nothing replied to; a patch
      // with no replies is an artifact the model job left half-written.
      if (repliesText === null) {
        if (scanRefused !== "" || repliesExpected) {
          log(`no reply is posted: ${scanRefused ? `the scan refused the model call's ${scanRefused}` : "the replies the scan uploaded did not arrive"}`);
          return { escalationReason: "feedback-invalid", posted: [] };
        }
        if (headSha !== run.head_sha) {
          log("no reply is posted: no replies, and the PR head moved since the select job read it");
          return { escalationReason: "feedback-not-landed", posted: [] };
        }
        if (patchState !== "") {
          log(`no reply is posted: no replies beside a ${patchState} patch`);
          return { escalationReason: "feedback-invalid", posted: [] };
        }
        log("no reply is posted: no model turn uploaded replies");
        return { escalationReason: "", skipReason: "no-model-turn", posted: [] };
      }
      replies = parseReplies(repliesText, run, fileExists);
    } catch (error) {
      if (!(error instanceof Invalid) && error.code !== "ENOENT") {
        throw error;
      }
      log(`no reply is posted: ${error instanceof Invalid ? error.message : "the artifact is missing"}`);
      escalationReason = "feedback-invalid";
      return { escalationReason, posted: [] };
    }
    // Every kept thread needs its disposition: one left out would stay open
    // with no reply, and the head's check run stops another dispatch.
    if (replies.length !== run.threads.length) {
      log(`no reply is posted: ${replies.length} of ${run.threads.length} kept threads have a disposition`);
      escalationReason = "feedback-incomplete";
      return { escalationReason, posted: [] };
    }
    const { kept } = await currentThreads({ api, pr, reviewerId, appId, trustedHumans });
    const now = new Map(kept.map((thread) => [thread.id, thread]));
    const fixSha = await fixesLanded({ api, run, headSha, replies, appId });
    if (fixSha === null) {
      log("no reply is posted: no one fix commit for the VALID replies reached the PR branch, or the branch changed another path");
      escalationReason = "feedback-not-landed";
      return { escalationReason, posted: [] };
    }
    replies = replies.map((reply) => (reply.disposition === "VALID" ? { ...reply, fixSha } : reply));
    if (replies.some((reply) => reply.disposition === "UNCERTAIN" || reply.disposition === "VALID-defer")) {
      escalationReason = "feedback-uncertain";
    }
    const shown = new Map(run.threads.map((thread) => [thread.id, thread]));
    const posted = [];
    for (const reply of replies) {
      const ids = shown.get(reply.thread).comment_ids;
      const fresh = now.get(reply.thread);
      // Once a reply posts, no later round selects the thread again until a
      // trusted person answers a reply that left it open: any failure in this
      // loop stops the posting, and it or a VALID thread left open hands the
      // PR to a person instead of stranding a thread.
      try {
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
        if (await headMoved()) {
          log(`stopped at ${reply.thread}: the PR head is no longer ${headSha}`);
          escalationReason = posted.length === 0 ? "feedback-not-landed" : "feedback-partial";
          break;
        }
        const answer = await api.replyToComment(pr, ids[0], renderReply(reply));
        if (answer?.in_reply_to_id !== ids[0]) {
          throw new Error(`the reply on ${reply.thread} did not land on its thread`);
        }
        posted.push({ thread: reply.thread, disposition: reply.disposition });
        if (reply.disposition === "VALID" && !(await resolveAfterReply(api, reply.thread, [...ids, answer.id], headMoved))) {
          log(`replied on ${reply.thread} but left it open: it or the PR head changed while the reply was posted`);
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
    // An INCORRECT thread stays open for a person to decide (owner decision):
    // its evidence reply is posted, and the PR goes to a person, since no
    // later round selects it until that person replies in the thread.
    if (escalationReason === "" && posted.some((entry) => entry.disposition === "INCORRECT")) {
      escalationReason = "feedback-disputed";
    }
    return { escalationReason, posted };
  }
}

export async function main(env, { api, log = (line) => console.log(line) } = {}) {
  need(env, [
    "GH_TOKEN",
    "GITHUB_REPOSITORY",
    "PR_NUMBER",
    "HEAD_SHA",
    "HEAD_REF",
    "GITHUB_RUN_ID",
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
  // An empty attempt is a model run that uploaded no replies: it names no
  // run, so its marker is always posted.
  const attempt = env.MODEL_RUN_ATTEMPT ?? "";
  if (attempt !== "" && !/^[1-9][0-9]{0,4}$/.test(attempt)) {
    throw new Error("MODEL_RUN_ATTEMPT is not a run attempt");
  }
  const patchState = env.REVIEW_PATCH_STATE ?? "";
  if (!["", "written", "empty"].includes(patchState)) {
    throw new Error("REVIEW_PATCH_STATE is not a patch state");
  }
  const scanRefused = scanRefusal({ dir: env.SCAN_REFUSED_DIR ?? "", read: env.SCAN_REFUSED_READ ?? "" });
  const runId = positive(env.GITHUB_RUN_ID, "GITHUB_RUN_ID");
  const modelRun = attempt ? `${runId}-${attempt}` : null;
  const dir = env.FEEDBACK_REPLIES_DIR;
  const read = (name, limit = LIMITS.bytes + 1) => {
    const path = join(dir, name);
    const stat = lstatSync(path);
    if (!stat.isFile()) {
      throw new Invalid(`${name} is not a regular file`);
    }
    if (stat.size > limit) {
      throw new Invalid(`${name} is over the size limit`);
    }
    return readFileSync(path, "utf8");
  };
  // run.json must be the bytes the select job wrote, whose SHA-256 that job
  // passed out.
  const readRun = () => {
    const text = read("run.json", LIMITS.runBytes);
    if (!/^[0-9a-f]{64}$/.test(env.RUN_SHA256 ?? "") || createHash("sha256").update(text).digest("hex") !== env.RUN_SHA256) {
      throw new Invalid("run.json does not match the SHA-256 the select job recorded");
    }
    return text;
  };
  // A missing replies.jsonl is judged in postReplies; one present must be
  // the bytes the scan job uploaded, whose SHA-256 it passed out.
  const readReplies = () => {
    let text;
    try {
      text = read("replies.jsonl");
    } catch (error) {
      if (error.code === "ENOENT") {
        return null;
      }
      throw error;
    }
    if (!/^[0-9a-f]{64}$/.test(env.REPLIES_SHA256 ?? "") || createHash("sha256").update(text).digest("hex") !== env.REPLIES_SHA256) {
      throw new Invalid("replies.jsonl does not match the SHA-256 the scan job recorded");
    }
    return text;
  };
  const { escalationReason, skipReason } = await publish({
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
    headRef: env.HEAD_REF,
    appId,
    modelRun,
    patchState,
    scanRefused,
    repliesExpected: attempt !== "" || (env.REPLIES_SHA256 ?? "") !== "",
    maxRounds: maxRoundsFrom(env.REVIEW_ROUNDS),
    reviewerId: reviewerIdFrom(env.TRUSTED_ACTORS),
    trustedHumans: trustedHumansFrom(env.TRUSTED_ACTORS),
    readArtifact: () => ({ runText: readRun(), repliesText: readReplies() }),
    fileExists: (path) => existsSync(join(env.GITHUB_WORKSPACE, path)),
    log,
  });
  if (escalationReason) {
    writeFileSync(env.ESCALATION_REASON_FILE, `${escalationReason}\n`);
    writeFileSync(env.SKIP_REASON_FILE, "awaiting-human\n");
  } else if (skipReason) {
    writeFileSync(env.SKIP_REASON_FILE, `${skipReason}\n`);
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
