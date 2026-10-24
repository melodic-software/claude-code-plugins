// The pr-unblock lane's address-feedback thread selection, shared by the model
// job's runner step and the reply job's script (publish-feedback.mjs). It runs
// no PR head code and hands the model no decision.
//
//   select  run by .github/workflows/pr-unblock.yml's address-feedback-select
//           job, which runs only base code, before the model job and any
//           model turn, with the job's read-only token: keeps the unresolved
//           review threads the reviewer bot opened in a review on a head a
//           review lane's marker confirms, when every comment is the bot's,
//           a trusted person with write access asked the lane to fix it, or
//           a trusted person answered the lane's escalation, then decides
//           skip (no such thread), escalate (the PR changes .github/workflows/**, or
//           the configured number of rounds already ran and no write-access
//           fix request came after the newest one) or proceed, writing the thread file
//           the skill's review-thread tool reads, with the same-plugin files
//           a write-access fix request names (namedPaths) and the files the
//           PR already changes (pr_paths, prPathsOf), and run.json, the
//           record the reply job checks the replies against (runRecord). On a PR carrying the
//           human-gated label it keeps only threads a trusted person with
//           write access asked it to fix (isFixRequest), and skips
//           awaiting-human when there are none, unless a lane escalation put
//           the label on and no review lane holds the PR (gate-source.mjs).
//
// Every comment body is copied into the thread file and never logged or
// interpolated into a command. Only a trusted person's reply to the lane's
// escalation, or with no escalation a trusted person's comment from the first
// write-access fix request on, is marked as direction; every other body is
// data.

import { appendFileSync, lstatSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { commentItems, gateSource, listLabelEvents, ROUND_MARKER } from "./gate-source.mjs";
import { isProtectedPath, namedInScope, prPathsOf } from "./thread-scope.mjs";

// The round cap is the config's `loop.review-rounds`, passed in as
// REVIEW_ROUNDS; the resolver's default is the fallback.
export const DEFAULT_MAX_ROUNDS = 2;
export { ROUND_MARKER };
// github-actions[bot], the author of the review lanes' reviewed-head markers.
export const MARKER_AUTHOR_ID = 41898282;
const REVIEWED_HEAD =
  /^<!-- claude-lane-reviewed-head lane=(claude-review|claude-security-review) sha=([0-9a-f]{40}) -->$/;
export const SHA = /^[0-9a-f]{40}$/;
// The first line of each review comment verify-notes.mjs posts, as
// github-actions[bot] (MARKER_AUTHOR_ID), with a pr-verify FAIL's notes. Such
// a comment opens a thread this lane works like the reviewer bot's.
export const VERIFY_NOTE_MARKER = "<!-- pr-verify:fail-note -->";
const THREAD_COMMENT_CAP = 100;
// The most files the pulls files listing returns
// (docs.github.com/en/rest/pulls/pulls#list-pull-requests-files, as of
// 2026-10-15; recheck when that section changes its limit).
const FILES_CAP = 3000;

const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");

// A review lane's own comment as the pr-review-cli reusable posts it: by
// github-actions[bot] (MARKER_AUTHOR_ID), its last non-blank line the lane's
// `claude-lane: <lane>` footer. Any other github-actions[bot] comment is not a
// finding.
const LANE_FOOTER = /^`?claude-lane: (claude-review|claude-security-review)`?$/;
// The lane a comment body's footer names, or null.
export const laneOf = (body) =>
  LANE_FOOTER.exec(
    String(body ?? "")
      .split("\n")
      .map((line) => line.trim())
      .findLast((line) => line !== "") ?? "",
  )?.[1] ?? null;
export const isLaneComment = (comment) => comment.authorId === MARKER_AUTHOR_ID && laneOf(comment.body) !== null;

// Round markers the lanes App posted; any other author's copy is ignored.
export const isRoundMarker = (comment, appId) => comment.user?.id === appId && firstLine(comment.body) === ROUND_MARKER;

export function countRounds(issueComments, appId) {
  return issueComments.filter((comment) => isRoundMarker(comment, appId)).length;
}

// The model job's check run, posted by its report job with the job token on
// the head it gated. A round that took a model turn ends success or failure;
// skips end neutral. It counts rounds the reply job could not record (a gate
// or broker refusal after the push moved the head); a forged one only stops
// the lane sooner.
export const MODEL_CHECK = "pr-unblock / address-feedback";
const isModelRun = (run, conclusions) =>
  run.name === MODEL_CHECK && run.app?.slug === "github-actions" && conclusions.includes(run.conclusion);
export function countCheckRounds(checkRunsByCommit) {
  return checkRunsByCommit.filter((runs) => runs.some((run) => isModelRun(run, ["success", "failure"]))).length;
}

// When the newest round ended: the latest of the round markers' creation and
// the model check runs' completion, a cancelled or timed-out one included so
// one fix request cannot start a round again after such a run. NaN when any of
// them has no readable time, so no fix request counts as newer.
export function lastRoundAt(issueComments, appId, checkRunsByCommit) {
  const ended = ["success", "failure", "cancelled", "timed_out"];
  const times = [
    ...issueComments.filter((comment) => isRoundMarker(comment, appId)).map((comment) => comment.created_at),
    ...checkRunsByCommit.flat().filter((run) => isModelRun(run, ended)).map((run) => run.completed_at),
  ].map((time) => Date.parse(time ?? ""));
  return times.some(Number.isNaN) ? Number.NaN : Math.max(...times);
}

export function reviewedHeads(issueComments) {
  const heads = new Set();
  for (const comment of issueComments) {
    if (comment.user?.id !== MARKER_AUTHOR_ID) {
      continue;
    }
    const match = REVIEWED_HEAD.exec(firstLine(comment.body));
    if (match) {
      heads.add(match[2]);
    }
  }
  return heads;
}

// The first line of the reply publish-feedback.mjs posts on a thread it
// leaves open for a person: every disposition but VALID.
const ESCALATION_REPLY =
  /^\*\*pr-unblock \/ address-feedback: (INCORRECT, left open|UNCERTAIN, left open for a person|VALID \(defer\), left open for a person)\*\*$/;
// The first line of the reply publish-feedback.mjs posts when an adjudicator
// finds a disputed finding stands (adjudicate-feedback.mjs): the next round
// works that thread again and accepts no second INCORRECT on it.
export const FINDING_STANDS = "<!-- pr-unblock adjudicate-feedback: finding-stands -->";
export const isEscalationReply = (comment, appId) => comment?.user?.id === appId && ESCALATION_REPLY.test(firstLine(comment.body));

// On a PR carrying the human-gated label, a thread is worked only when a
// trusted person with write access asks for it: a line of their reply that
// starts with this phrase, in any case, outside a fenced code block. A quoted
// line starts with `>`, so it never matches.
export const FIX_REQUEST = /^pr-fix lane: please fix this finding(?=[\s.:;,!]|$)/i;
export function isFixRequest(body) {
  let fenced = false;
  for (const line of String(body ?? "").split("\n")) {
    if (/^ {0,3}(```|~~~)/.test(line)) {
      fenced = !fenced;
    } else if (!fenced && FIX_REQUEST.test(line.replace(/\r$/, ""))) {
      return true;
    }
  }
  return false;
}

// The file-shaped words of a fix request's body outside fenced code blocks and
// quoted lines: each word with wrapping backticks, quotes, brackets or
// emphasis, trailing punctuation and a trailing :line or :line-line removed,
// kept when its last segment has an extension. A _ is a legal first or last
// character of a name, so it is emphasis only as a matched pair.
const WRAP_START = /^[`'"([{<*]+/;
const WRAP_END = /[`'")\]}>*.,;:!?]+$/;
const UNDERSCORE_PAIR = /^(_+)(.+)\1$/;
export function pathTokens(body) {
  const tokens = new Set();
  let fenced = false;
  for (const raw of String(body ?? "").split("\n")) {
    const line = raw.replace(/\r$/, "");
    if (/^ {0,3}(```|~~~)/.test(line)) {
      fenced = !fenced;
      continue;
    }
    if (fenced || /^ {0,3}>/.test(line)) {
      continue;
    }
    for (const word of line.split(/\s+/)) {
      const token = word
        .replace(WRAP_START, "")
        .replace(WRAP_END, "")
        .replace(UNDERSCORE_PAIR, "$2")
        .replace(/:[1-9][0-9]*(-[1-9][0-9]*)?$/, "");
      if (/\.[A-Za-z0-9]+$/.test(token.slice(token.lastIndexOf("/") + 1))) {
        tokens.add(token);
      }
    }
  }
  return [...tokens];
}

// The most named paths one thread adds, counted after the existence check.
export const NAMED_CAP = 10;
// The most distinct directories one thread's existence check reads.
export const TREE_READ_CAP = 2 * NAMED_CAP;
// A regular or executable file's git mode, as GraphQL's TreeEntry.mode gives
// it (100644 and 100755 in decimal): a symbolic link (120000) and a gitlink
// (160000) are never named in.
const FILE_MODES = new Set([0o100644, 0o100755]);

// The paths a kept thread's fix requests name that may join its scope: each
// path token of a comment by one of `fixers` that is a fix request
// (isFixRequest), read as repository-relative when it holds a / and as a
// file in the thread path's directory when it does not, allowed by
// namedInScope for the thread, and a regular file at `headSha`
// (`listTree(sha, dir)` answers the directory's GraphQL tree entries).
export async function namedPaths({ thread, reviewComments, fixers, headSha, listTree }) {
  const rows = new Map(reviewComments.map((row) => [row.id, row]));
  const dir = thread.path.slice(0, thread.path.lastIndexOf("/") + 1);
  const candidates = new Set();
  for (const comment of thread.comments) {
    const row = rows.get(comment.id);
    if (comment.author !== "trusted-human" || !fixers.has(row?.user?.id) || !isFixRequest(row.body)) {
      continue;
    }
    for (const token of pathTokens(row.body)) {
      const path = token.includes("/") ? token : `${dir}${token}`;
      if (path !== thread.path && namedInScope(path, thread.path)) {
        candidates.add(path);
      }
    }
  }
  const trees = new Map();
  const named = [];
  for (const path of candidates) {
    if (named.length === NAMED_CAP) {
      break;
    }
    const parent = path.slice(0, path.lastIndexOf("/"));
    if (!trees.has(parent)) {
      if (trees.size === TREE_READ_CAP) {
        continue;
      }
      trees.set(parent, await listTree(headSha, parent));
    }
    const entry = trees.get(parent).find((e) => e.name === path.slice(parent.length + 1));
    if (entry?.type === "blob" && FILE_MODES.has(entry.mode)) {
      named.push(path);
    }
  }
  return named;
}

// The ids of the trusted people who wrote a fix request in `comments` (each
// { authorId, login, body }) and hold write or admin permission on the
// repository now (`permission(login)` answers GitHub's permission field).
export async function fixRequesters({ comments, trustedHumans, permission }) {
  const logins = new Map();
  for (const comment of comments) {
    if (trustedHumans.has(comment.authorId) && comment.login && isFixRequest(comment.body)) {
      logins.set(comment.authorId, comment.login);
    }
  }
  const writers = new Set();
  for (const [id, login] of logins) {
    if (["admin", "write"].includes(await permission(login))) {
      writers.add(id);
    }
  }
  return writers;
}

// fixRequesters over a PR's review comments (the REST rows).
export const reviewFixers = ({ reviewComments, trustedHumans = new Set(), permission }) =>
  fixRequesters({
    comments: reviewComments.map((row) => ({ authorId: row.user?.id, login: row.user?.login, body: row.body })),
    trustedHumans,
    permission,
  });

// The base's human-gated role label: config.role_labels["human-gated"] of
// .work-item-tracker.json, needs-human when the file or entry is absent.
export function humanGatedLabelFrom(path) {
  let config;
  try {
    config = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") {
      return "needs-human";
    }
    throw new Error(`cannot read ${path}`);
  }
  const roles = config?.config?.role_labels ?? {};
  if (!Object.hasOwn(roles, "human-gated")) {
    return "needs-human";
  }
  const label = roles["human-gated"];
  if (typeof label !== "string" || label === "") {
    throw new Error("the human-gated role label is not a non-empty string");
  }
  return label;
}

// Who wrote each comment of a thread, or null when it is not one to work.
// `comments` are oldest first, each { authorId, createdAt, body, lastEditedAt,
// editorId }. The first is the reviewer bot's, a lane comment (isLaneComment,
// which counts as the reviewer bot's throughout), or a verifier note
// (github-actions[bot]'s, its first line VERIFY_NOTE_MARKER), and one of these
// holds:
// - every comment is the reviewer bot's, but a verifier note's own;
// - the lanes App never commented, every later comment is the reviewer bot's
//   or a trusted person's, and one is a fix request (isFixRequest) by one of
//   `fixers` (the trusted people with write access who wrote a fix request,
//   fixRequesters); the trusted people's comments from the first such
//   request on are direction;
// - the lanes App's last comment escalated the thread and every comment after
//   it is a trusted person's reply, which is direction;
// - the lanes App's last comment is an adjudication that let the finding
//   stand (FINDING_STANDS), and every comment after it, if any, is a trusted
//   person's reply, which is direction.
// A comment by anyone else, a trusted person's comment last edited by anyone
// but a trusted person, or a reply not after the escalation leaves the thread
// alone. The select step and the reply job (keepThreads) and the dispatcher
// (feedback-dispatch.mjs) all judge a thread with this. With `requesters` (a
// set of ids, given on a PR carrying the human-gated label), a thread is
// worked only when a reply is a fix request by one of them, after the
// escalation when there is one.
export function threadAuthors(comments, { reviewerId, appId, trustedHumans = new Set(), requesters = null, fixers = requesters ?? new Set() }) {
  const verifier = comments.length > 0 && comments[0].authorId === MARKER_AUTHOR_ID && firstLine(comments[0].body) === VERIFY_NOTE_MARKER;
  const reviewer = (comment) => comment.authorId === reviewerId || isLaneComment(comment);
  if (comments.length === 0 || (!reviewer(comments[0]) && !verifier)) {
    return null;
  }
  const finder = (comment, i) => (i === 0 && verifier ? { author: "verifier" } : reviewer(comment) ? { author: "reviewer" } : null);
  if (comments.every((comment, i) => finder(comment, i) !== null)) {
    return requesters ? null : comments.map(finder);
  }
  const isHuman = (comment) =>
    trustedHumans.has(comment.authorId) && (comment.lastEditedAt == null || trustedHumans.has(comment.editorId));
  const asks = (ids, comment) => ids.has(comment.authorId) && isFixRequest(comment.body);
  const last = comments.findLastIndex((comment) => comment.authorId === appId);
  if (last === -1) {
    const humanAsks = (ids) => comments.some((comment) => isHuman(comment) && asks(ids, comment));
    if (!humanAsks(fixers) || (requesters && !humanAsks(requesters))) {
      return null;
    }
    const asked = comments.findIndex((comment) => isHuman(comment) && asks(fixers, comment));
    const authors = [];
    for (const [i, comment] of comments.entries()) {
      if (finder(comment, i)) {
        authors.push(finder(comment, i));
      } else if (isHuman(comment)) {
        authors.push(i >= asked ? { author: "trusted-human", direction: true } : { author: "trusted-human" });
      } else {
        return null;
      }
    }
    return authors;
  }
  // An adjudication that let the finding stand (adjudicate-feedback.mjs)
  // hands the thread back to the lane with no reply needed.
  const stands = last >= 1 && firstLine(comments[last].body) === FINDING_STANDS;
  if (last < 1 || !(stands || ESCALATION_REPLY.test(firstLine(comments[last].body))) || (last === comments.length - 1 && !stands)) {
    return null;
  }
  if (requesters && !comments.slice(last + 1).some((comment) => asks(requesters, comment))) {
    return null;
  }
  const escalatedAt = Date.parse(comments[last].createdAt ?? "");
  const authors = [];
  for (const [i, comment] of comments.entries()) {
    const id = comment.authorId;
    const human = isHuman(comment);
    if (i > last) {
      // NaN compares false, so an unparsable time leaves the thread alone.
      if (!human || !(Date.parse(comment.createdAt ?? "") > escalatedAt)) {
        return null;
      }
      authors.push({ author: "trusted-human", direction: true });
    } else if (finder(comment, i) || id === appId || human) {
      authors.push(finder(comment, i) ?? { author: id === appId ? "lane" : "trusted-human" });
    } else {
      return null;
    }
  }
  return authors;
}

// A thread is kept when it is unresolved, its first comment belongs to a
// review its author (the reviewer bot, or github-actions[bot] for a verifier
// note) submitted on a marker-confirmed head (any head for a thread carrying
// a trusted person's direction), and threadAuthors accepts its comments.
// A thread with more comments than one page reads is left alone.
export function keepThreads({ threads, reviewComments, reviews, heads, reviewerId, appId, trustedHumans = new Set(), requesters = null, fixers = requesters ?? new Set() }) {
  const comments = new Map(reviewComments.map((comment) => [comment.id, comment]));
  const reviewsById = new Map(reviews.map((review) => [review.id, review]));
  const kept = [];
  for (const thread of threads) {
    if (thread.isResolved || thread.comments.totalCount > THREAD_COMMENT_CAP) {
      continue;
    }
    const nodes = thread.comments.nodes;
    const rows = nodes.map((node) => comments.get(node.databaseId));
    if (rows.length === 0 || rows.some((row) => row === undefined)) {
      continue;
    }
    const authors = threadAuthors(
      rows.map((row, i) => ({
        authorId: row.user?.id,
        createdAt: row.created_at,
        body: row.body,
        lastEditedAt: nodes[i].lastEditedAt,
        editorId: nodes[i].editor?.databaseId,
      })),
      { reviewerId, appId, trustedHumans, requesters, fixers },
    );
    if (authors === null) {
      continue;
    }
    // A trusted person's direction (a fix request, or a reply to the lane's
    // escalation) asks for the thread, so its review may be on an earlier head.
    const directed = authors.some((a) => a.direction === true);
    const review = reviewsById.get(rows[0].pull_request_review_id);
    // A verifier note's or a lane comment's review is github-actions[bot]'s.
    const reviewAuthor = authors[0].author === "verifier" || rows[0].user?.id === MARKER_AUTHOR_ID ? MARKER_AUTHOR_ID : reviewerId;
    if (review?.user?.id !== reviewAuthor || (!directed && !heads.has(review.commit_id))) {
      continue;
    }
    kept.push({
      id: thread.id,
      path: rows[0].path,
      line: rows[0].line ?? rows[0].original_line ?? null,
      review_commit: review.commit_id,
      root_comment_id: rows[0].id,
      comments: rows.map((row, i) => ({ id: row.id, ...authors[i], body: row.body ?? "" })),
    });
  }
  return kept;
}

export async function select({
  api,
  pr,
  headSha,
  repository,
  appId,
  reviewerId,
  trustedHumans,
  humanGatedLabel = "needs-human",
  maxRounds = DEFAULT_MAX_ROUNDS,
}) {
  const [pull, files, issueComments, reviews, reviewComments, threads] = await Promise.all([
    api.getPull(pr),
    api.listPullFiles(pr),
    api.listIssueComments(pr),
    api.listReviews(pr),
    api.listReviewComments(pr),
    api.listThreads(pr),
  ]);
  // The human-gated label holds the PR except for threads a trusted person
  // with write access asked the lane to fix, unless a lane escalation put it
  // on and no review lane holds the PR (gate-source.mjs). The label stays on.
  const labeled = (pull.labels ?? []).some((label) => label.name === humanGatedLabel);
  const escalated =
    labeled &&
    gateSource({
      timeline: [...commentItems(issueComments), ...(await api.listLabelEvents(pr))],
      label: humanGatedLabel,
      head: headSha,
      isLanesApp: (user) => user?.id === appId && user?.type === "Bot",
    }).source === "lane-escalation";
  const gated = labeled && !escalated;
  const fixers = await reviewFixers({ reviewComments, trustedHumans, permission: api.getPermission });
  const kept = keepThreads({
    threads,
    reviewComments,
    reviews,
    heads: reviewedHeads(issueComments),
    reviewerId,
    appId,
    trustedHumans,
    requesters: gated ? fixers : null,
    fixers,
  });
  if (kept.length === 0) {
    return { decision: "skip", skipReason: gated ? "awaiting-human" : "not-applicable", threads: kept };
  }
  // The files listing stops at FILES_CAP, so a longer diff could hide a
  // .github/workflows/ path and is treated as touching one.
  if (
    files.length >= FILES_CAP ||
    files.some((file) => isProtectedPath(file.filename) || isProtectedPath(file.previous_filename ?? ""))
  ) {
    return { decision: "escalate", escalationReason: "feedback-protected-path", threads: kept };
  }
  const commits = await api.listPullCommits(pr);
  const checkRuns = await Promise.all(commits.map((commit) => api.listCheckRuns(commit.sha, MODEL_CHECK)));
  const rounds = Math.max(countRounds(issueComments, appId), countCheckRounds(checkRuns));
  let worked = kept;
  if (rounds >= maxRounds) {
    // Past the cap, a trusted person with write access who asked for a fix
    // after the newest round grants one more round, for the threads they
    // asked about only.
    const since = lastRoundAt(issueComments, appId, checkRuns);
    const rows = new Map(reviewComments.map((row) => [row.id, row]));
    worked = kept.filter((thread) =>
      thread.comments.some((comment) => {
        const row = rows.get(comment.id);
        return (
          comment.author === "trusted-human" &&
          fixers.has(row.user?.id) &&
          isFixRequest(comment.body) &&
          Date.parse(row.created_at ?? "") > since
        );
      }),
    );
    if (worked.length === 0) {
      return { decision: "escalate", escalationReason: "feedback-round-cap", rounds, threads: kept };
    }
  }
  for (const thread of worked) {
    const named = await namedPaths({ thread, reviewComments, fixers, headSha, listTree: api.listTree });
    if (named.length > 0) {
      thread.named_paths = named;
    }
  }
  return {
    decision: "proceed",
    rounds,
    // True drops the human-gated label from the write runner's holds: every
    // kept thread carries a write-access fix request, or a lane escalation
    // put the label on.
    fixRequested: labeled,
    threads: worked,
    file: { version: 1, repository, pr, head_sha: headSha, pr_paths: prPathsOf(files), threads: worked },
  };
}

// run.json, as its bytes: the gated head and the kept threads with the comment
// ids the model is shown, a pure function of the thread file. publish-feedback.mjs
// checks the model's replies against it.
export function runRecord(file) {
  const run = {
    version: 1,
    head_sha: file.head_sha,
    pr_paths: file.pr_paths,
    threads: file.threads.map((t) => ({
      id: t.id,
      path: t.path,
      comment_ids: t.comments.map((c) => c.id),
      ...(t.named_paths ? { named_paths: t.named_paths } : {}),
    })),
  };
  return `${JSON.stringify(run)}\n`;
}

// The kept threads of a PR as they are now: the reply job's re-read.
export async function currentThreads({ api, pr, reviewerId, appId, trustedHumans }) {
  const [issueComments, reviews, reviewComments, threads] = await Promise.all([
    api.listIssueComments(pr),
    api.listReviews(pr),
    api.listReviewComments(pr),
    api.listThreads(pr),
  ]);
  const fixers = await reviewFixers({ reviewComments, trustedHumans, permission: api.getPermission });
  return {
    issueComments,
    reviewComments,
    kept: keepThreads({ threads, reviewComments, reviews, heads: reviewedHeads(issueComments), reviewerId, appId, trustedHumans, fixers }),
  };
}

const THREAD_QUERY = `query($id: ID!) {
  node(id: $id) {
    ... on PullRequestReviewThread {
      isResolved pullRequest { number } comments(first: 100) { totalCount nodes { databaseId } }
    }
  }
}`;

const TREE_QUERY = `query($owner: String!, $name: String!, $expression: String!) {
  repository(owner: $owner, name: $name) {
    object(expression: $expression) { ... on Tree { entries { name type mode } } }
  }
}`;

const RESOLVE_MUTATION = `mutation($id: ID!) {
  resolveReviewThread(input: { threadId: $id }) { thread { isResolved } }
}`;

const THREADS_QUERY = `query($owner: String!, $name: String!, $pr: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          id isResolved
          comments(first: 100) {
            totalCount
            nodes { databaseId lastEditedAt editor { ... on User { databaseId } ... on Bot { databaseId } } }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

export function createGitHubApi({ token, repository, apiUrl, graphqlUrl, fetch = globalThis.fetch }) {
  const [owner, name] = repository.split("/");
  const headers = {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "X-GitHub-Api-Version": "2022-11-28",
  };
  async function request(url, method = "GET", body) {
    const response = await fetch(url, {
      method,
      headers: body === undefined ? headers : { ...headers, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      throw Object.assign(new Error(`${method} ${url} returned ${response.status}`), { status: response.status });
    }
    return { data: await response.json(), link: response.headers.get("link") ?? "" };
  }
  async function paginate(path) {
    const rows = [];
    let url = `${apiUrl}/repos/${owner}/${name}/${path}${path.includes("?") ? "&" : "?"}per_page=100`;
    while (url) {
      const { data, link } = await request(url);
      rows.push(...data);
      url = /<([^>]+)>;\s*rel="next"/.exec(link)?.[1] ?? "";
    }
    return rows;
  }
  async function graphql(query, variables) {
    const { data } = await request(graphqlUrl, "POST", { query, variables });
    if (data.errors?.length) {
      throw new Error(`GraphQL: ${data.errors.map((error) => error.message).join("; ")}`);
    }
    return data.data;
  }
  const repo = `${apiUrl}/repos/${owner}/${name}`;
  return {
    getPull: async (pr) => (await request(`${repo}/pulls/${pr}`)).data,
    listLabelEvents: (pr) => listLabelEvents({ graphql, repository, number: pr }),
    // Metadata read, which every token holds. A 404 (not a collaborator) is none.
    async getPermission(login) {
      const url = `${repo}/collaborators/${encodeURIComponent(login)}/permission`;
      const response = await fetch(url, { headers });
      if (response.status === 404) {
        return "none";
      }
      if (!response.ok) {
        throw new Error(`GET ${url} returned ${response.status}`);
      }
      return (await response.json()).permission;
    },
    closePull: async (pr) => (await request(`${repo}/pulls/${pr}`, "PATCH", { state: "closed" })).data,
    createIssue: async (fields) => (await request(`${repo}/issues`, "POST", fields)).data,
    listIssues: (query) => paginate(`issues?${query}`),
    listPullFiles: (pr) => paginate(`pulls/${pr}/files`),
    listIssueComments: (pr) => paginate(`issues/${pr}/comments`),
    // The REST issue timeline, as gate-source.mjs prHold reads it.
    listTimeline: (pr) => paginate(`issues/${pr}/timeline`),
    listReviews: (pr) => paginate(`pulls/${pr}/reviews`),
    listReviewComments: (pr) => paginate(`pulls/${pr}/comments`),
    listPullCommits: (pr) => paginate(`pulls/${pr}/commits`),
    async listCheckRuns(sha, name) {
      const url = `${repo}/commits/${sha}/check-runs?check_name=${encodeURIComponent(name)}&filter=all&per_page=100`;
      return (await request(url)).data.check_runs ?? [];
    },
    // Every check run on a commit, up to 300 (fix-ci-context.mjs).
    async listCommitCheckRuns(sha) {
      const runs = [];
      for (let page = 1; page <= 3; page += 1) {
        const { data } = await request(`${repo}/commits/${sha}/check-runs?filter=latest&per_page=100&page=${page}`);
        runs.push(...(data.check_runs ?? []));
        if ((data.check_runs ?? []).length < 100) {
          break;
        }
      }
      return runs;
    },
    listAnnotations: async (id) => (await request(`${repo}/check-runs/${id}/annotations?per_page=50`)).data,
    getJob: async (id) => (await request(`${repo}/actions/jobs/${id}`)).data,
    // The job log redirects to a short-lived download URL; fetch follows it.
    async getJobLog(id) {
      const response = await fetch(`${repo}/actions/jobs/${id}/logs`, { headers });
      if (!response.ok) {
        throw Object.assign(new Error(`GET job ${id} logs returned ${response.status}`), { status: response.status });
      }
      return response.text();
    },
    async getCommit(sha) {
      return (await request(`${repo}/commits/${sha}`)).data;
    },
    // A file's text at `ref` through the raw media type, which serves files
    // over 1 MB (docs.github.com/en/rest/repos/contents#get-repository-content,
    // as of 2026-10-21; recheck when that section changes its size limits);
    // null when the path is absent.
    async getText(path, ref) {
      const url = `${repo}/contents/${path.split("/").map(encodeURIComponent).join("/")}?ref=${encodeURIComponent(ref)}`;
      const response = await fetch(url, { headers: { ...headers, Accept: "application/vnd.github.raw+json" } });
      if (response.status === 404) {
        return null;
      }
      if (!response.ok) {
        throw new Error(`GET ${url} returned ${response.status}`);
      }
      return response.text();
    },
    async listThreads(pr) {
      const nodes = [];
      let after = null;
      for (;;) {
        const page = (await graphql(THREADS_QUERY, { owner, name, pr, after })).repository.pullRequest.reviewThreads;
        nodes.push(...page.nodes);
        if (!page.pageInfo.hasNextPage) {
          return nodes;
        }
        after = page.pageInfo.endCursor;
      }
    },
    // The entries of the tree at `${sha}:${dir}`, none when it is no tree.
    async listTree(sha, dir) {
      const object = (await graphql(TREE_QUERY, { owner, name, expression: `${sha}:${dir}` })).repository.object;
      return object?.entries ?? [];
    },
    async readThread(id) {
      const node = (await graphql(THREAD_QUERY, { id })).node;
      return {
        isResolved: node?.isResolved,
        pr: node?.pullRequest?.number,
        commentCount: node?.comments?.totalCount,
        commentIds: (node?.comments?.nodes ?? []).map((comment) => comment.databaseId),
      };
    },
    // From git/ref, which GET /pulls can lag behind after a push.
    async readBranch(ref) {
      return (await request(`${repo}/git/ref/heads/${ref.split("/").map(encodeURIComponent).join("/")}`)).data.object.sha;
    },
    async compare(base, head) {
      return (await request(`${repo}/compare/${base}...${head}`)).data;
    },
    async getRun(id) {
      return (await request(`${repo}/actions/runs/${id}`)).data;
    },
    async createReviewComment(pr, fields) {
      return (await request(`${repo}/pulls/${pr}/comments`, "POST", fields)).data;
    },
    async replyToComment(pr, commentId, body) {
      return (await request(`${repo}/pulls/${pr}/comments/${commentId}/replies`, "POST", { body })).data;
    },
    async resolveThread(id) {
      return (await graphql(RESOLVE_MUTATION, { id })).resolveReviewThread.thread.isResolved;
    },
    async createIssueComment(pr, body) {
      await request(`${repo}/issues/${pr}/comments`, "POST", { body });
    },
    // One page: a pull request with more labels than one page holds is refused.
    async listLabels(pr) {
      const { data, link } = await request(`${repo}/issues/${pr}/labels?per_page=100`);
      if (/rel="next"/.test(link)) {
        throw new Error("the pull request has more labels than one page holds");
      }
      return data;
    },
    // The Git Data API: GitHub signs a commit made with no author or
    // committer as the App.
    createBlob: async (content) => (await request(`${repo}/git/blobs`, "POST", { content, encoding: "base64" })).data.sha,
    createTree: async (baseTree, tree) => (await request(`${repo}/git/trees`, "POST", { base_tree: baseTree, tree })).data.sha,
    createCommit: async (message, tree, parents) => (await request(`${repo}/git/commits`, "POST", { message, tree, parents })).data.sha,
    async updateRef(ref, sha, force) {
      await request(`${repo}/git/refs/${ref.split("/").map(encodeURIComponent).join("/")}`, "PATCH", { sha, force });
    },
  };
}

const MARKER_FILE = /^scan-refused-[1-9][0-9]{0,4}(-rung-up)?\.txt$/;

// The model call's scan refusal for a reply or verdict script: '' none,
// `patch` an oversize patch, `output` any other. It comes from the markers the
// read runner's scan-refusal job uploads, never from a job output: a failed
// job's outputs are not documented to reach a workflow_call caller. `dir` is
// where the write runner downloaded every attempt's marker for the model
// call's activity (SCAN_REFUSED_DIR), `read` that download's outcome
// (SCAN_REFUSED_READ). A download that failed cannot rule a refusal out, so
// it reads `output`; any marker reads `patch` only when one names it. A
// forged marker only hands the round to a person.
export function scanRefusal({ dir = "", read = "" } = {}) {
  if (read === "failure") {
    return "output";
  }
  if (dir === "") {
    return "";
  }
  let names;
  try {
    names = readdirSync(dir);
  } catch (error) {
    if (error.code === "ENOENT") {
      return "";
    }
    throw error;
  }
  const kinds = names
    .filter((name) => MARKER_FILE.test(name) && lstatSync(join(dir, name)).isFile())
    .map((name) => readFileSync(join(dir, name), "utf8").trim());
  if (kinds.length === 0) {
    return "";
  }
  return kinds.includes("patch") ? "patch" : "output";
}

export function need(env, keys) {
  for (const key of keys) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
}

export function positive(value, name) {
  if (!/^[1-9][0-9]{0,14}$/.test(String(value))) {
    throw new Error(`${name} is not a positive integer`);
  }
  return Number(value);
}

export function maxRoundsFrom(value) {
  return value === undefined || value === "" ? DEFAULT_MAX_ROUNDS : positive(value, "REVIEW_ROUNDS");
}

const readActors = (path) => JSON.parse(readFileSync(path, "utf8")).actors ?? [];

// The ids of the people on the base's trusted-actors list.
export function trustedHumansFrom(trustedActorsPath) {
  return new Set(
    readActors(trustedActorsPath)
      .filter((row) => row.kind === "human")
      .map((row) => positive(row.id, `a human id in ${trustedActorsPath}`)),
  );
}

// The reviewer bot's id comes from the base's trusted-actors list, by login.
export function reviewerIdFrom(trustedActorsPath, login = "claude[bot]") {
  const actor = readActors(trustedActorsPath).find((row) => row.login === login && row.kind === "bot");
  return positive(actor?.id, `the ${login} id in ${trustedActorsPath}`);
}

export async function main(argv, env, { api, log = (line) => console.log(line) } = {}) {
  const command = argv[0];
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "HEAD_SHA", "APP_SENDER_ID"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!SHA.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit id");
  }
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
    });
  const output = (key, value) => appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
  if (command === "select") {
    need(env, ["THREAD_FILE", "RUN_FILE", "TRUSTED_ACTORS"]);
    const result = await select({
      api: client,
      pr,
      headSha: env.HEAD_SHA,
      repository: env.GITHUB_REPOSITORY,
      appId,
      reviewerId: reviewerIdFrom(env.TRUSTED_ACTORS),
      trustedHumans: trustedHumansFrom(env.TRUSTED_ACTORS),
      humanGatedLabel: humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/.work-item-tracker.json"),
      maxRounds: maxRoundsFrom(env.REVIEW_ROUNDS),
    });
    if (result.file) {
      writeFileSync(env.THREAD_FILE, `${JSON.stringify(result.file, null, 2)}\n`);
      writeFileSync(env.RUN_FILE, runRecord(result.file));
    }
    output("proceed", String(result.decision === "proceed"));
    // The write runner drops the human-gated label from the hold list only
    // when this is true: every kept thread carries a write-access fix request,
    // or a lane escalation put the label on.
    output("fix-requested", String(result.fixRequested === true));
    output("skip-reason", result.decision === "skip" ? result.skipReason : result.decision === "escalate" ? "awaiting-human" : "");
    output("escalation-reason", result.escalationReason ?? "");
    log(`${result.decision}: ${result.threads.length} kept thread(s), ${result.rounds ?? 0} earlier round(s)${result.escalationReason ? `, ${result.escalationReason}` : ""}`);
    return 0;
  }
  throw new Error("usage: address-feedback.mjs select");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::address-feedback failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
