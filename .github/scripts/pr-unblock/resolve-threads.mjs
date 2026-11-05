#!/usr/bin/env node
// resolve-threads.mjs: the resolve job of the pr-unblock lane's
// address-feedback round, a script activity with no model and no head
// checkout (checkout: base). On a PR a trusted person opened, the lanes App is
// no writer to publish-feedback.mjs's publish-artifact token, so it replies
// and leaves each answered thread open; this job's mutate-branch token
// (contents: write) can resolve it. It reads the PR's threads from GitHub
// itself, never from another job's outputs, and resolves each one judgeThread
// rules `answered` or `outdated`:
//
//   - every comment is a review bot's (isReviewerComment) or the lanes App's,
//     and none was edited by another account: a thread a person wrote or
//     joined stays theirs;
//   - its root is a review bot's finding that no reviewer comment rates
//     CRITICAL (isCritical) and that adjudicate-feedback.mjs adjudicable
//     would let an adjudicator judge, so a security finding a person decides
//     (CRITICAL or unrated, or a listed bot's on a head the security-review
//     lane held or has not reviewed) stays open, as does a pr-verify note,
//     which publish-feedback.mjs's pass-only round owns;
//   - answered: its last comment is the lanes App's resolving answer
//     (publish-feedback.mjs isResolvingAnswer); outdated: GitHub reports it
//     outdated and no lanes App comment on it left it open (an INCORRECT,
//     UNCERTAIN or VALID-defer reply, an escalation, or a finding that stood).
//
// Each thread is re-read just before its resolve and left alone unless it
// still holds the comments it was judged on and judgeThread, run again on
// their bodies and edits as they are then, still resolves it. Only a PR whose author
// is a person on the base's trusted-actors list is served; any other skips
// not-applicable. A failed resolve is logged, the rest are tried, and the job
// then fails so a re-run tries again.
//
// Environment:
//   GH_TOKEN           the lane token (contents: write, pull-requests: read)
//   GITHUB_REPOSITORY  owner/repo
//   PR_NUMBER          the gated pull request
//   APP_SENDER_ID      the lanes App bot's user id
//   TRUSTED_ACTORS     the base's trusted-actors.json: the owners and the reviewer bot
//   REVIEWER_IDS       the listed review bots' ids, one per line
//   SKIP_REASON_FILE   where the runner reads the skip reason

import { writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import {
  createGitHubApi,
  isLaneComment,
  isReviewerComment,
  isVerifierRoot,
  laneOf,
  need,
  ownerPull,
  positive,
  reviewerIdFrom,
  reviewerIdsFrom,
  securitySignals,
  securityState,
  trustedHumansFrom,
} from "./address-feedback.mjs";
import { adjudicable, isCritical } from "./adjudicate-feedback.mjs";
import { isResolvingAnswer } from "./publish-feedback.mjs";

// The most comments one thread read holds (address-feedback.mjs THREADS_QUERY).
const THREAD_COMMENT_CAP = 100;
export const RESOLVES = Object.freeze(["answered", "outdated"]);

// One thread's verdict: `answered` or `outdated` (resolve it), else why it
// stays open. `thread` is a listThreads node, `rows` its comments' REST rows
// in thread order, `review` the root comment's review, `security` the PR's
// securitySignals.
export function judgeThread({ thread, rows, review, security, reviewerId, reviewerIds = [], appId }) {
  if (thread.isResolved !== false) {
    return "resolved";
  }
  const nodes = thread.comments?.nodes ?? [];
  if (thread.comments?.totalCount > THREAD_COMMENT_CAP || rows.length === 0 || rows.length !== nodes.length || rows.some((row) => row === undefined)) {
    return "unread";
  }
  const comments = rows.map((row) => ({ authorId: row.user?.id, body: row.body ?? "" }));
  if (isVerifierRoot(comments[0])) {
    return "verifier-note";
  }
  const bot = (comment, i) => {
    const edited = nodes[i].lastEditedAt != null && nodes[i].editor?.databaseId !== comment.authorId;
    return !edited && (comment.authorId === appId || isReviewerComment(comment, { reviewerId, reviewerIds }));
  };
  if (!comments.every(bot) || comments[0].authorId === appId) {
    return "not-bot-only";
  }
  // Tagged as keepThreads tags them for adjudicable.
  const tagged = comments.map((comment, i) => {
    const author = comment.authorId === appId ? "lane" : "reviewer";
    const lane = isLaneComment(comment) ? laneOf(comment.body) : null;
    const listed = author === "reviewer" && reviewerIds.includes(comment.authorId);
    const state = listed && i === 0 ? { security: review ? securityState(security, review) : "pending" } : {};
    return { author, ...(lane ? { lane } : {}), ...(listed ? { listed } : {}), ...state, body: comment.body };
  });
  if (tagged.some((comment) => comment.author === "reviewer" && isCritical(comment.body)) || !adjudicable(tagged)) {
    return "person-decides";
  }
  const lane = comments.filter((comment) => comment.authorId === appId);
  if (comments.at(-1).authorId === appId && isResolvingAnswer(comments.at(-1).body)) {
    return "answered";
  }
  if (lane.some((comment) => !isResolvingAnswer(comment.body))) {
    return "left-open";
  }
  return thread.isOutdated === true ? "outdated" : "current";
}

const sameIds = (a, b) => a.length === b.length && a.every((id, i) => id === b[i]);

export async function resolveThreads({ api, pr, appId, reviewerId, reviewerIds = [], trustedHumans, log = () => {} }) {
  const pull = await api.getPull(pr);
  if (!ownerPull(pull, trustedHumans)) {
    log(`#${pr} was not opened by a person on the trusted-actors list; nothing is resolved`);
    return { skipReason: "not-applicable", resolved: [] };
  }
  const [threads, reviewComments, reviews, issueComments] = [await api.listThreads(pr), await api.listReviewComments(pr), await api.listReviews(pr), await api.listIssueComments(pr)];
  const byId = new Map(reviewComments.map((row) => [row.id, row]));
  const reviewsById = new Map(reviews.map((row) => [row.id, row]));
  const security = securitySignals(issueComments);
  const resolved = [];
  const failed = [];
  for (const thread of threads) {
    const rows = (thread.comments?.nodes ?? []).map((node) => byId.get(node.databaseId));
    const judge = (t, r) => judgeThread({ thread: t, rows: r, review: reviewsById.get(rows[0]?.pull_request_review_id), security, reviewerId, reviewerIds, appId });
    const verdict = judge(thread, rows);
    if (!RESOLVES.includes(verdict)) {
      if (verdict !== "resolved") {
        log(`${thread.id}: left open (${verdict})`);
      }
      continue;
    }
    try {
      // Judged again on the re-read bodies and edits: a comment edited since
      // the first read (say, rated CRITICAL) leaves the thread open.
      const now = await api.readThread(thread.id);
      const nodes = now.nodes ?? [];
      const fresh =
        now.pr === pr && sameIds(now.commentIds, rows.map((row) => row.id)) && nodes.every((node) => typeof node.body === "string")
          ? judge({ ...thread, isResolved: now.isResolved, isOutdated: now.isOutdated, comments: { totalCount: now.commentCount, nodes } }, rows.map((row, i) => ({ ...row, body: nodes[i].body })))
          : "changed";
      if (!RESOLVES.includes(fresh)) {
        log(`${thread.id}: left open; it changed since it was read (${fresh})`);
        continue;
      }
      if ((await api.resolveThread(thread.id)) !== true) {
        throw new Error("it does not read resolved");
      }
      resolved.push(thread.id);
      log(`${thread.id}: resolved (${verdict})`);
    } catch (error) {
      failed.push(thread.id);
      log(`could not resolve ${thread.id}: ${String(error?.message ?? error).slice(0, 300)}`);
    }
  }
  log(`resolved ${resolved.length} review thread(s) on #${pr}`);
  if (failed.length > 0) {
    throw new Error(`could not resolve ${failed.join(", ")}`);
  }
  return { skipReason: "", resolved };
}

export async function main(env, { api, log = (line) => console.log(line) } = {}) {
  need(env, ["GH_TOKEN", "GITHUB_REPOSITORY", "PR_NUMBER", "APP_SENDER_ID", "TRUSTED_ACTORS", "SKIP_REASON_FILE"]);
  const { skipReason } = await resolveThreads({
    api:
      api ??
      createGitHubApi({
        token: env.GH_TOKEN,
        repository: env.GITHUB_REPOSITORY,
        apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
        graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      }),
    pr: positive(env.PR_NUMBER, "PR_NUMBER"),
    appId: positive(env.APP_SENDER_ID, "APP_SENDER_ID"),
    reviewerId: reviewerIdFrom(env.TRUSTED_ACTORS),
    reviewerIds: reviewerIdsFrom(env.REVIEWER_IDS),
    trustedHumans: trustedHumansFrom(env.TRUSTED_ACTORS),
    log,
  });
  if (skipReason) {
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
      console.log(`::error::resolve-threads failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
