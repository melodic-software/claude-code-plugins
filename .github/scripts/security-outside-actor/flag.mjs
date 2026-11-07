#!/usr/bin/env node
// flag.mjs: flags an issue or pull request when someone outside the
// organization writes on it. The author of the event's content (the comment,
// the review, the pull request or the issue, in that order) is trusted when
// GitHub reports them as OWNER or MEMBER, or when their numeric id is on the
// default branch's trusted-actor list (our bots and Apps, and listed humans
// whose membership is private). Anyone else is an outside actor: the issue or
// pull request gets `security: outside-actor` and needs-human (an issue's Work
// status field, write-status.mjs; a pull request's label), and one comment per
// outside actor names their login and the event kind and says a person
// reviews it. Their text is never read, quoted or passed on.
//
// An unreadable or malformed trusted-actor list flags the author: the check
// fails closed. The label and needs-human are written on every untrusted
// event, so a person who cleared needs-human hears of new outside activity;
// the payload may be stale, so the write never skips (adding a present label
// or setting the state the field holds is a no-op).
// The comment is written
// once per actor, found again by its marker, which counts only on a comment
// github-actions[bot] wrote.
//
// Only a person on the trusted-actor list (kind human, matched by id, never a
// Bot) removes `security: outside-actor`. Any other removal, a member's not on
// the list included, puts it and needs-human back and posts one comment per remover
// naming their login without a mention; an unreadable list puts them back too.
//
// Environment:
//   GITHUB_TOKEN          the job's token: issues write, pull-requests write
//   GITHUB_REPOSITORY     owner/repo
//   GITHUB_EVENT_NAME     the triggering event
//   GITHUB_EVENT_PATH     the event payload, read here and never by a shell
//   TRUSTED_ACTORS_PATH   the default branch's trusted-actor list
//   BASE_PATH             the default branch's checkout (default `.base`),
//                         whose models.issue-status the field write reads
//   GITHUB_API_URL
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, paginate, REPOSITORY } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { statusWriter } from "../../actions/resolve-config/write-status.mjs";
import { OUTSIDE_ACTOR_LABEL } from "../pr-merge/merge-holds.mjs";

export const LABEL = OUTSIDE_ACTOR_LABEL;
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

// Whether the payload's item is a pull request, which an issue_comment on one
// names under `issue`.
const isPull = (payload) => Boolean(payload.pull_request ?? payload.issue?.pull_request);

// The content's author and where it lives, from the event payload. Returns
// null when the payload names no issue or pull request number.
export function readEvent(eventName, payload) {
  const content = payload.comment ?? payload.review ?? payload.pull_request ?? payload.issue ?? {};
  const number = payload.issue?.number ?? payload.pull_request?.number;
  if (!Number.isInteger(number) || number < 1 || !Object.hasOwn(KINDS, eventName)) {
    return null;
  }
  // An edit, push or reopen by someone other than the author (retitling an
  // outsider's issue, editing another's comment, pushing to another's pull
  // request) is the sender's act, so the sender is judged by id alone: the
  // payload carries no association for them, so anyone not on the trusted
  // list, an organization member included, is flagged.
  const sender = payload.sender ?? {};
  const bySender = SENDER_ACTIONS.has(payload.action) && Number.isInteger(sender.id) && sender.id !== content.user?.id;
  const user = (bySender ? sender : content.user) ?? {};
  return {
    number,
    pull: isPull(payload),
    kind: ACTION.test(payload.action ?? "") ? `${KINDS[eventName]} ${payload.action}` : KINDS[eventName],
    association: bySender ? undefined : content.author_association,
    id: Number.isInteger(user.id) ? user.id : null,
    login: typeof user.login === "string" && LOGIN.test(user.login) ? user.login : null,
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

// The label and the comment, then an issue's Work status hold, set through
// `setStatus(number, state)` (write-status.mjs statusWriter's set); a pull
// request's hold is the label. The field write needs resolve-config's
// packages, so it comes last: when it fails, the label and comment are
// already written. Each write is tried whatever the others did; any failure
// is thrown after all were tried. Returns `comment`'s outcome.
async function writeFlag({ github, base, item, setStatus, comment, what }) {
  const results = await Promise.allSettled([comment(), github("POST", `${base}/labels`, { labels: item.pull ? [LABEL, NEEDS_HUMAN] : [LABEL] })]);
  if (!item.pull) {
    results.push(...(await Promise.allSettled([setStatus(item.number, NEEDS_HUMAN)])));
  }
  const failed = results.filter((result) => result.status === "rejected");
  if (failed.length > 0) {
    throw new Error(`${what} failed: ${failed.map((result) => result.reason?.message ?? result.reason).join("; ")}`);
  }
  return results[0].value;
}

// The comment is written once per marker: a marker github-actions[bot]
// already posted answers `seen` instead.
const commentOnce = (github, base, marker, body, seen, posted) => async () => {
  const comments = await paginate(github, `${base}/comments`);
  if (comments.some((comment) => isOwnMarker(comment, marker))) {
    return seen;
  }
  await github("POST", `${base}/comments`, { body });
  return posted;
};

export async function flag({ github, repository, author, setStatus }) {
  const base = `/repos/${repository}/issues/${author.number}`;
  const comment = commentOnce(github, base, markerFor(author), commentBody(author), "labeled", "commented");
  return writeFlag({ github, base, item: author, setStatus, comment, what: `flagging #${author.number}` });
}

// Who removed which label, from an `unlabeled` event's payload.
export function readRemoval(payload) {
  const number = payload.issue?.number ?? payload.pull_request?.number;
  if (!Number.isInteger(number) || number < 1) {
    return null;
  }
  const sender = payload.sender ?? {};
  return {
    number,
    pull: isPull(payload),
    label: payload.label?.name,
    id: Number.isInteger(sender.id) ? sender.id : null,
    login: typeof sender.login === "string" && LOGIN.test(sender.login) ? sender.login : null,
    bot: sender.type !== "User",
  };
}

// `humans` is null when the trusted-actor list could not be read.
export const mayRemove = (remover, humans) => !remover.bot && humans !== null && remover.id !== null && humans.has(remover.id);

export const removalMarkerFor = (remover) => `${MARKER} removed-by=${remover.id ?? "unknown"} -->`;

export function removalBody(remover) {
  const who = remover.login ? `\`${remover.login}\`` : "an account whose login could not be read";
  return [
    removalMarkerFor(remover),
    `**Outside-actor label restored.** ${who} (id ${remover.id ?? "unknown"}) removed \`${LABEL}\` and is not a person on the trusted-actor list, so it and \`${NEEDS_HUMAN}\` are back.`,
    "",
    "Only a person on the trusted-actor list removes it.",
  ].join("\n");
}

export async function restore({ github, repository, remover, setStatus }) {
  const base = `/repos/${repository}/issues/${remover.number}`;
  const comment = commentOnce(github, base, removalMarkerFor(remover), removalBody(remover), "restored", "restored and commented");
  return writeFlag({ github, base, item: remover, setStatus, comment, what: `restoring ${LABEL} on #${remover.number}` });
}

// The job token's Work status write, over the base checkout's config.
const fieldSetter = (env, github) => async (number, state) =>
  (await statusWriter({ env, github, repository: env.GITHUB_REPOSITORY })).set(number, state);

async function handleRemoval({ env, github, log, payload }) {
  const remover = readRemoval(payload);
  if (!remover) {
    throw new Error("the event names no issue or pull request this workflow handles");
  }
  if (remover.label?.toLowerCase() !== LABEL.toLowerCase()) {
    log(`security-outside-actor: #${remover.number} a label other than ${LABEL} was removed; nothing changed`);
    return 0;
  }
  let humans = null;
  try {
    ({ humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH));
  } catch (error) {
    log(`::warning::security-outside-actor: the trusted-actor list is unreadable (${error.message}); restoring the label`);
  }
  if (mayRemove(remover, humans)) {
    log(`security-outside-actor: #${remover.number} listed person id ${remover.id} removed ${LABEL}; nothing changed`);
    return 0;
  }
  const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
  const outcome = await restore({ github: client, repository: env.GITHUB_REPOSITORY, remover, setStatus: fieldSetter(env, client) });
  log(`::warning::security-outside-actor: #${remover.number} id ${remover.id ?? "unknown"} is not a listed person; ${LABEL} ${outcome}`);
  return 0;
}

export async function main({ env = process.env, github, log = console.log } = {}) {
  try {
    if (!REPOSITORY.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is malformed");
    }
    const payload = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, "utf8"));
    if (payload.action === "unlabeled") {
      return await handleRemoval({ env, github, log, payload });
    }
    const author = readEvent(env.GITHUB_EVENT_NAME, payload);
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
    const outcome = await flag({ github: client, repository: env.GITHUB_REPOSITORY, author, setStatus: fieldSetter(env, client) });
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
