#!/usr/bin/env node
// release-eval-hold.mjs: takes `do-not-merge` off an open pull request whose
// hold waits only on eval evidence of no loss, once a listed human posts the
// eval-pair record for its current head. No model. The hold convention is in
// docs/contracts/loop-lane/README.md (Cross-lane PR hold).
//
// The label comes off only when all of these hold (decide):
// - The pull request is open and carries `do-not-merge`, and its newest
//   `labeled` event for that label is read (heldAt).
// - Since heldAt, a listed human (trusted-actors.json kind human, by account
//   id, a User not posting through an App) recorded the hold's reason as a
//   line `<!-- pr-hold reason=eval -->`, and every line opening `<!-- pr-hold`
//   since then, whoever wrote it, is such a line. No reason, another reason, a
//   line of another shape or an eval line by anyone else keeps the label.
// - Since heldAt, a listed human posted the record line
//   `<!-- eval-pair verdict=no-loss validity=VALID head=<sha> -->`, and the
//   newest such comment names the pull request's current head. A comment
//   with more than one record line counts as none.
// - Both lines count only on a line of their own, outside a fenced code block
//   and a block quote.
// - No other hold stands: no body hold (merge-holds.mjs bodyHolds) and no
//   member veto (merge-holds.mjs vetoers) in its comments or reviews.
// The comments are read first, and a pull request with no listed human's eval
// hold line and record line anywhere stops there (mayRelease).
// The head and the label are read again before the comment and before the
// removal. The comment comes first, carrying RELEASED_MARKER, so a failed
// removal is retried by the next run without a second comment. At most
// RELEASES_PER_RUN a run. Each pull request logs one line,
// `release-eval-hold: #<n> released head=<sha> record=<url> wait-minutes=<m>`
// or `release-eval-hold: #<n> kept: <reason>`, and the run ends with
// `release-eval-hold: held=<h> released=<r> kept=<k> failed=<f>`.
//
// Environment:
//   GH_TOKEN             the lane token (reads, the comment, the label)
//   GITHUB_REPOSITORY    owner/repo
//   TRUSTED_ACTORS_PATH  trusted-actors.json from the default branch tip
//   KILL_SWITCH          `proceed` to run
//   LANES_BOT_LOGIN      the lanes App's login (default LANES_APP_LOGIN)
//   GITHUB_STEP_SUMMARY  receives the run line
//   GITHUB_API_URL
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { bodyHolds, fromRest, LANES_APP_LOGIN, vetoers } from "./merge-holds.mjs";

export const LABEL = "do-not-merge";
export const RELEASES_PER_RUN = 5;
export const EVAL_REASON = "eval";
const RECORD = /^<!-- eval-pair verdict=no-loss validity=VALID head=([0-9a-f]{40}) -->$/;
const HOLD = /^<!-- pr-hold reason=([a-z0-9][a-z0-9-]{0,63}) -->$/;
const HOLD_PREFIX = "<!-- pr-hold";
const FENCE = /^ {0,3}(`{3,}|~{3,})/;
const QUOTE = /^ {0,3}>/;
const REPO = /^[A-Za-z0-9-]+\/[A-Za-z0-9_.-]+$/;

export const releasedMarker = (head, recordId) => `<!-- eval-hold-released head=${head} record=${recordId} -->`;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// The lines of `body` outside a fenced code block and a block quote, as written.
export function* ownLines(body) {
  let fence = "";
  for (const line of String(body ?? "").split(/\r\n|\r|\n/)) {
    const marker = FENCE.exec(line);
    if (fence) {
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && line.slice(marker[0].length).trim() === "") {
        fence = "";
      }
      continue;
    }
    if (marker) {
      fence = marker[1];
      continue;
    }
    if (!QUOTE.test(line)) {
      yield line;
    }
  }
}

// Every capture of `pattern` on a line of its own in `body`.
export const markers = (body, pattern) => [...ownLines(body)].map((line) => pattern.exec(line)?.[1]).filter((value) => value !== undefined);

// A comment a listed human wrote: a User account by id, not through an App.
const byHuman = (comment, humans) =>
  comment?.user?.type === "User" && Number.isSafeInteger(comment.user.id) && humans.has(comment.user.id) && comment.performed_via_github_app == null;

// The newest `labeled` event of LABEL, as its time, or null.
export function heldAt(events) {
  const times = (events ?? []).filter((event) => event?.event === "labeled" && event.label?.name === LABEL).map((event) => String(event.created_at ?? ""));
  return times.length === 0 ? null : times.sort().at(-1);
}

// Whether to release one pull request: { release: true, record, head } or
// { release: false, reason }. `pull` is GET pulls/{n}; `comments` the issue
// comments, `reviews` the reviews and `events` the issue events, each every
// page; `humans` the listed humans' ids (numbers).
export function decide({ pull, comments, reviews = [], events, humans }) {
  const keep = (reason) => ({ release: false, reason });
  if (pull?.state !== "open") {
    return keep("not-open");
  }
  if (!(pull.labels ?? []).some((label) => label?.name === LABEL)) {
    return keep("no-label");
  }
  const head = pull.head?.sha;
  if (!/^[0-9a-f]{40}$/.test(String(head))) {
    return keep("head-unread");
  }
  const since = heldAt(events);
  if (since === null) {
    return keep("no-label-event");
  }
  const recent = (comments ?? []).filter((comment) => String(comment?.created_at ?? "") >= since);
  // Every hold line since the label, whoever wrote it: only a listed human's
  // exact `reason=eval` line is an eval hold, and anything else keeps it.
  const holds = recent.flatMap((comment) => [...ownLines(comment.body)].filter((line) => line.trimStart().startsWith(HOLD_PREFIX)).map((line) => ({ comment, line })));
  if (holds.length === 0) {
    return keep("no-hold-reason");
  }
  for (const { comment, line } of holds) {
    const reason = HOLD.exec(line)?.[1];
    if (reason === undefined) {
      return keep("hold-reason-unknown");
    }
    if (reason !== EVAL_REASON) {
      return keep(`hold-reason-${reason}`);
    }
    if (!byHuman(comment, humans)) {
      return keep("hold-reason-unlisted-author");
    }
  }
  if (bodyHolds(pull.body, true)) {
    return keep("body-hold");
  }
  const vetoing = vetoers([...(comments ?? []), ...(reviews ?? [])].map(fromRest));
  if (vetoing.length > 0) {
    return keep(`member-veto-${vetoing.join(",")}`);
  }
  const records = recent
    .filter((comment) => byHuman(comment, humans))
    .map((comment) => ({ comment, heads: markers(comment.body, RECORD) }))
    .filter(({ heads }) => heads.length === 1)
    .sort((a, b) => String(a.comment.created_at).localeCompare(String(b.comment.created_at)));
  const newest = records.at(-1);
  if (newest === undefined) {
    return keep("no-record");
  }
  if (newest.heads[0] !== head) {
    return keep("record-head-mismatch");
  }
  return { release: true, record: newest.comment, head };
}

export const releasedComment = (head, record) =>
  `${releasedMarker(head, record.id)}\nThe \`${LABEL}\` hold waited only on eval evidence (\`reason=${EVAL_REASON}\`), and a listed human posted a VALID no-loss eval-pair record for \`${head}\`: ${record.html_url}. pr-merge removed \`${LABEL}\`. To hold again, add the label back with a new \`pr-hold\` reason line.`;

// Whether `comments` could release at all: a listed human's eval hold line and
// record line, at any time. Most held pull requests stop here, on one read.
export function mayRelease(comments, humans) {
  const human = (comments ?? []).filter((comment) => byHuman(comment, humans));
  if (!human.some((comment) => markers(comment.body, HOLD).includes(EVAL_REASON))) {
    return "no-eval-hold";
  }
  return human.some((comment) => markers(comment.body, RECORD).length > 0) ? null : "no-record";
}

// The comments first; the rest only for a pull request that may release.
async function readAll(github, repo, number, humans) {
  const base = `/repos/${repo}/issues/${number}`;
  const comments = await paginate(github, `${base}/comments`);
  const early = mayRelease(comments, humans);
  if (early !== null) {
    return { early };
  }
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  const events = await paginate(github, `${base}/events`);
  const reviews = await paginate(github, `/repos/${repo}/pulls/${number}/reviews`);
  return { pull, comments, events, reviews };
}

// Whether the head and the label still stand as decided.
async function stands(github, repo, number, head) {
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  return pull?.state === "open" && pull.head?.sha === head && (pull.labels ?? []).some((label) => label?.name === LABEL);
}

export async function main({ env = process.env, github, now = Date.now } = {}) {
  const summary = (line) => {
    console.log(line);
    if (env.GITHUB_STEP_SUMMARY) {
      appendFileSync(env.GITHUB_STEP_SUMMARY, `${line}\n`);
    }
  };
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("release-eval-hold: the lanes kill switch stops this run; nothing read or removed");
      return 0;
    }
    const repo = env.GITHUB_REPOSITORY;
    const bot = env.LANES_BOT_LOGIN || LANES_APP_LOGIN;
    const { humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH || ".base/.github/standards/trusted-actors/trusted-actors.json");
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const held = (await paginate(github, `/repos/${repo}/issues?state=open&labels=${LABEL}`)).filter(
      (item) => item.pull_request && Number.isSafeInteger(item.number) && item.number > 0,
    );
    const counts = { released: 0, kept: 0, failed: 0 };
    for (const { number } of held) {
      if (counts.released >= RELEASES_PER_RUN) {
        console.log(`release-eval-hold: #${number} kept: ${RELEASES_PER_RUN} released this run`);
        counts.kept += 1;
        continue;
      }
      try {
        const read = await readAll(github, repo, number, humans);
        const result = read.early === undefined ? decide({ ...read, humans }) : { release: false, reason: read.early };
        if (!result.release) {
          console.log(`release-eval-hold: #${number} kept: ${result.reason}`);
          counts.kept += 1;
          continue;
        }
        const { head, record } = result;
        const since = heldAt(read.events);
        const explained = read.comments.some(
          (comment) =>
            comment?.user?.login === bot &&
            String(comment.created_at ?? "") >= since &&
            [...ownLines(comment.body)].includes(releasedMarker(head, record.id)),
        );
        const base = `/repos/${repo}/issues/${number}`;
        if (!explained) {
          if (!(await stands(github, repo, number, head))) {
            console.log(`release-eval-hold: #${number} kept: moved-before-comment`);
            counts.kept += 1;
            continue;
          }
          await github("POST", `${base}/comments`, { body: releasedComment(head, record) });
        }
        if (!(await stands(github, repo, number, head))) {
          console.log(`release-eval-hold: #${number} kept: moved-before-removal`);
          counts.kept += 1;
          continue;
        }
        await github("DELETE", `${base}/labels/${LABEL}`);
        counts.released += 1;
        const wait = Math.round((now() - Date.parse(record.created_at)) / 60000);
        console.log(`release-eval-hold: #${number} released head=${head} record=${record.html_url} wait-minutes=${Number.isFinite(wait) ? wait : "unknown"}`);
      } catch (error) {
        counts.failed += 1;
        console.log(`::error title=release-eval-hold::#${number}: ${escapeCommand(error?.message ?? error)}`);
      }
    }
    summary(`release-eval-hold: held=${held.length} released=${counts.released} kept=${counts.kept} failed=${counts.failed}`);
    return counts.failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=release-eval-hold::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
