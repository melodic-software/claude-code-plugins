#!/usr/bin/env node
// flag.mjs: flags an issue or pull request when someone outside the
// organization writes on it. The author of the event's content (the comment,
// the review, the pull request or the issue, in that order) is trusted when
// GitHub reports them as OWNER or MEMBER, or when their numeric id is on the
// default branch's trusted-actor list (our bots and Apps, and listed humans
// whose membership is private). Anyone else is an outside actor: the issue or
// pull request gets `security: outside-actor` and `needs-human`, and one
// comment per outside actor names their login and the event kind and says a
// person reviews it. Their text is never read, quoted or passed on.
//
// An unreadable or malformed trusted-actor list flags the author: the check
// fails closed. Labels are re-added on every untrusted event, so a person who
// cleared `needs-human` hears of new outside activity; an event whose payload
// already shows both labels skips that write. The comment is written
// once per actor, found again by its marker, which counts only on a comment
// github-actions[bot] wrote.
//
// Environment:
//   GITHUB_TOKEN          the job's token: issues write, pull-requests write
//   GITHUB_REPOSITORY     owner/repo
//   GITHUB_EVENT_NAME     the triggering event
//   GITHUB_EVENT_PATH     the event payload, read here and never by a shell
//   TRUSTED_ACTORS_PATH   the default branch's trusted-actor list
//   GITHUB_API_URL
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, paginate, REPOSITORY } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const LABEL = "security: outside-actor";
export const NEEDS_HUMAN = "needs-human";
export const MARKER = "<!-- security-outside-actor";
// github-actions[bot], the author of every comment this job's token writes.
export const ACTIONS_BOT_ID = 41898282;
const TRUSTED_ASSOCIATIONS = new Set(["OWNER", "MEMBER"]);
const LOGIN = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})(?:\[bot\])?$/;

const KINDS = {
  issues: "issue",
  issue_comment: "comment",
  pull_request_review: "pull request review",
  pull_request_review_comment: "pull request review comment",
  pull_request_target: "pull request",
};
const ACTION = /^[a-z_]{1,32}$/;
// Actions the sender takes on content another may have written: an edit, a
// push to a pull request, a reopen.
const SENDER_ACTIONS = new Set(["edited", "synchronize", "reopened"]);

// The content's author and where it lives, from the event payload. Returns
// null when the payload names no issue or pull request number.
export function readEvent(eventName, payload) {
  const content = payload.comment ?? payload.review ?? payload.pull_request ?? payload.issue ?? {};
  const number = payload.issue?.number ?? payload.pull_request?.number;
  if (!Number.isInteger(number) || number < 1 || !Object.hasOwn(KINDS, eventName)) {
    return null;
  }
  // An edit, push or reopen by someone other than the author (a person
  // retitling an outsider's issue, or a collaborator who is not a member
  // editing a member's comment or pushing to a member's pull request) is the
  // sender's act, so the sender is judged, by id alone.
  const sender = payload.sender ?? {};
  const bySender = SENDER_ACTIONS.has(payload.action) && Number.isInteger(sender.id) && sender.id !== content.user?.id;
  const user = (bySender ? sender : content.user) ?? {};
  const labels = (payload.issue ?? payload.pull_request)?.labels;
  const names = new Set(Array.isArray(labels) ? labels.map((item) => item?.name) : []);
  return {
    number,
    kind: ACTION.test(payload.action ?? "") ? `${KINDS[eventName]} ${payload.action}` : KINDS[eventName],
    association: bySender ? undefined : content.author_association,
    id: Number.isInteger(user.id) ? user.id : null,
    login: typeof user.login === "string" && LOGIN.test(user.login) ? user.login : null,
    labeled: names.has(LABEL) && names.has(NEEDS_HUMAN),
  };
}

// Whether the author is inside the organization. `ids` is null when the
// trusted-actor list could not be read: only the association can then trust.
export function isTrusted(author, ids) {
  if (TRUSTED_ASSOCIATIONS.has(author.association)) {
    return true;
  }
  return ids !== null && author.id !== null && ids.has(author.id);
}

export const markerFor = (author) => `${MARKER} actor=${author.id ?? "unknown"} -->`;

export function commentBody(author) {
  const who = author.login ? `\`${author.login}\`` : "an account whose login could not be read";
  return [
    markerFor(author),
    `**Outside actor.** ${who} (id ${author.id ?? "unknown"}) wrote here (event: ${author.kind}) and is neither an organization member nor on the trusted-actor list.`,
    "",
    "A person reviews this before any lane acts on it. Their text is not quoted here.",
  ].join("\n");
}

// A marker counts only on a comment github-actions[bot] wrote, so an outside
// actor cannot post the marker to suppress their own flag.
export const isOwnMarker = (comment, marker) =>
  comment?.user?.id === ACTIONS_BOT_ID && comment?.user?.type === "Bot" && String(comment.body ?? "").startsWith(marker);

// Labels and comment are written independently, so one failing still leaves
// the other; any failure is thrown after both were tried.
export async function flag({ github, repository, author }) {
  const base = `/repos/${repository}/issues/${author.number}`;
  const marker = markerFor(author);
  const [labeled, commented] = await Promise.allSettled([
    author.labeled ? null : github("POST", `${base}/labels`, { labels: [LABEL, NEEDS_HUMAN] }),
    paginate(github, `${base}/comments`).then(async (comments) => {
      if (comments.some((comment) => isOwnMarker(comment, marker))) {
        return author.labeled ? "unchanged" : "labeled";
      }
      await github("POST", `${base}/comments`, { body: commentBody(author) });
      return "commented";
    }),
  ]);
  const failed = [labeled, commented].filter((result) => result.status === "rejected");
  if (failed.length > 0) {
    throw new Error(`flagging #${author.number} failed: ${failed.map((result) => result.reason?.message ?? result.reason).join("; ")}`);
  }
  return commented.value;
}

export async function main({ env = process.env, github, log = console.log } = {}) {
  try {
    if (!REPOSITORY.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is malformed");
    }
    const author = readEvent(env.GITHUB_EVENT_NAME, JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, "utf8")));
    if (!author) {
      throw new Error("the event names no issue or pull request this workflow handles");
    }
    let ids = null;
    try {
      ({ ids } = loadTrustedList(env.TRUSTED_ACTORS_PATH));
    } catch (error) {
      log(`::warning::security-outside-actor: the trusted-actor list is unreadable (${error.message}); flagging the author`);
    }
    if (isTrusted(author, ids)) {
      log(`security-outside-actor: #${author.number} author id ${author.id} is trusted; nothing changed`);
      return 0;
    }
    const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const outcome = await flag({ github: client, repository: env.GITHUB_REPOSITORY, author });
    log(`::warning::security-outside-actor: #${author.number} outside actor id ${author.id ?? "unknown"} ${outcome}`);
    return 0;
  } catch (error) {
    log(`::error::security-outside-actor: ${error.message}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
