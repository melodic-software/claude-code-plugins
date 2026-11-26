import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, lstatSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { ACTIONS_BOT_ID } from "../lib/lane-vocabulary.mjs";
import { runAsScript } from "../lib/run-main.mjs";
import { bindingOf, FOOTER as LANE_FOOTER, laneChecker, laneFooter, withoutBinding, withoutLaneFooters } from "../lib/lane-binding.mjs";
import { commentItems, FAILING, gateSource, laneHold, latestRuns, listLabelEvents, prHold, ROUND_MARKER } from "./gate-source.mjs";
import { retryFetch } from "../lib/retry-fetch.mjs";
import { loadTrustedList, readRawTrustedActors, trustedListPath } from "../lib/trusted-actors.mjs";
import { BODY_HOLD, LANE_HOLD, refsIssue, trackerBindingText } from "../pr-merge/merge-holds.mjs";
import { copyPathsOf, isProtectedPath, namedInScope, prPathsOf, sharedCopyPairs } from "./thread-scope.mjs";
import { retryRung, ROUTES, stopSkip } from "./escalation-routes.mjs";

export const DEFAULT_MAX_ROUNDS = 2;
export const FRESH_FIXER_ROUNDS = 1;
export const FRESH_ROUND_BRIEF =
  "The lane's capped review rounds left these findings open, and this run is their one fresh fixer round before the lane stops. " +
  "Fix each finding in the code it names. Never weaken, skip or delete a test, assertion or check to close a finding. " +
  "A security finding rated CRITICAL that this round leaves open goes to a person.";
export const roundLine = (round, max) => `round ${round} of max ${max}`;
export { ROUND_MARKER };
const ACTIVITY = "address-feedback";
export const MARKER_AUTHOR_ID = ACTIONS_BOT_ID;
export const UNSUMMONED_REVIEWER_IDS = Object.freeze([62310815]);
const REVIEWED_HEAD =
  /^<!-- claude-lane-reviewed-head lane=(claude-review|claude-security-review) sha=([0-9a-f]{40}) -->$/;
export const SHA = /^[0-9a-f]{40}$/;
export const VERIFY_NOTE_MARKER = "<!-- pr-verify:fail-note -->";
const THREAD_COMMENT_CAP = 100;
const FILES_CAP = 3000;

const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../..");
export const CHECK_RUN_PAGES = 20;

export const copyPathsFor = (files, root = ROOT) =>
  copyPathsOf(files, sharedCopyPairs(readFileSync(join(root, "scripts/shared-copies.txt"), "utf8")));

export function planLanes(paths, root = ROOT) {
  const out = execFileSync("bash", [join(root, "scripts/plan-test-lanes.sh"), "--", ...paths], {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
    maxBuffer: 16 * 1024 * 1024,
  });
  return Object.fromEntries(
    out
      .split("\n")
      .filter((line) => line.includes("="))
      .map((line) => [line.slice(0, line.indexOf("=")), line.slice(line.indexOf("=") + 1)]),
  );
}

const legs = (value) => {
  const list = JSON.parse(value || "[0]");
  if (!Array.isArray(list) || list.length === 0 || !list.every((leg) => Number.isSafeInteger(leg) && leg >= 0)) {
    throw new Error("a lane's legs are not a list of leg numbers");
  }
  return list;
};
export function coveringLanes(plan) {
  const matrix = ["bash", "python", "node"].filter((lane) => plan[lane] === "true").flatMap((lane) => legs(plan[`${lane}_legs`]).map((leg) => `test-${lane} (${leg})`));
  const windows = JSON.parse(plan.windows_jobs || "[]");
  return [...matrix, ...(Array.isArray(windows) ? windows.filter((job) => typeof job === "string") : [])];
}

const TEST_LANE = /^(?:Test(?: [A-Z0-9][a-z0-9]*)+|test-[a-z0-9]+(?:-[a-z0-9]+)*)(?: \(\d+\))?$/;
const laneName = (name) => name.replace(/^\S+/, (id) => id.split("-").map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join(" "));
const failed = (run) => run.status === "completed" && FAILING.has(run.conclusion);
const byName = (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);

export async function ciSnapshot({ api, headSha, files, plan = planLanes }) {
  try {
    const lanes = coveringLanes(plan([...new Set(files.flatMap((file) => [file?.filename, file?.previous_filename]).filter((path) => typeof path === "string" && path !== ""))].sort())).map(laneName);
    const listed = await api.listCommitCheckRuns(headSha);
    const byLane = new Map();
    for (const run of latestRuns(listed.filter((run) => run?.app?.slug === "github-actions")).values()) {
      const name = String(run.name);
      if (TEST_LANE.test(name) && (!byLane.has(laneName(name)) || name === laneName(name))) {
        byLane.set(laneName(name), run);
      }
    }
    const tests = [...byLane.values()];
    const red = tests.filter(failed).sort(byName);
    if (red.length > 0) {
      return { state: "red", runs: red.map((run) => ({ name: run.name, url: run.html_url })) };
    }
    const planned = (run) => lanes.includes(laneName(String(run.name)));
    const runs = tests.filter(planned).sort(byName);
    const unplanned = tests.some((run) => !planned(run) && run.conclusion !== "skipped");
    const passed =
      lanes.length > 0 &&
      listed.complete !== false &&
      !unplanned &&
      lanes.every((lane) => byLane.has(lane)) &&
      runs.every((run) => run.status === "completed" && run.conclusion === "success");
    return { state: passed ? "green" : "unsettled", runs: runs.map((run) => ({ name: run.name, url: run.html_url })) };
  } catch {
    return { state: "unsettled", runs: [] };
  }
}

const BODY_MAX = 60000;

export const WRAP = 100;
const FOLD_LINES = 20;

export function wrapLine(line, width = WRAP) {
  const out = [];
  let lead = "";
  let rest = line;
  while (lead.length + rest.length > width) {
    const room = width - lead.length;
    let cut = rest.lastIndexOf(" ", room);
    if (cut <= 0) cut = rest.indexOf(" ", room);
    if (cut <= 0) break;
    out.push(lead + rest.slice(0, cut).trimEnd());
    rest = rest.slice(cut + 1).trimStart();
    lead = "  ";
  }
  out.push(lead + rest);
  return out;
}

export function quote(lines, summary = (count) => `What it wrote (${count} lines)`) {
  // biome-ignore lint/suspicious/noControlCharactersInRegex: control characters are what it removes
  const text = lines.join("\n").replace(/\r\n/g, "\n").replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "?").replaceAll("```", "'''");
  const wrapped = (text.length > BODY_MAX ? `${text.slice(0, BODY_MAX)} [cut]` : text).split("\n").flatMap((line) => wrapLine(line));
  const fence = ["```text", ...wrapped, "```"].join("\n");
  return wrapped.length > FOLD_LINES ? [`<details><summary>${summary(wrapped.length)}</summary>`, "", fence, "", "</details>"].join("\n") : fence;
}

export function staleVerifyNotes(threads, head, { supersededHead } = {}) {
  return threads
    .filter((thread) => {
      const root = thread.root?.nodes?.[0];
      const commit = root?.originalCommit?.oid ?? "";
      return thread.isResolved === false && root?.author?.databaseId === MARKER_AUTHOR_ID && firstLine(root.body) === VERIFY_NOTE_MARKER && SHA.test(commit) && (commit !== head || supersededHead === head);
    })
    .map((thread) => thread.id);
}

const lastLine = (body) =>
  String(body ?? "")
    .split("\n")
    .map((line) => line.trim())
    .findLast((line) => line !== "") ?? "";
export const laneOf = (body) => LANE_FOOTER.exec(lastLine(body))?.[1] ?? null;
export const isLaneComment = (comment) => comment.authorId === MARKER_AUTHOR_ID && laneOf(comment.body) !== null;

export const withoutLaneFooter = withoutLaneFooters;

export const restFields = (row) => ({ authorId: row.user?.id, id: row.id, createdAt: row.created_at, updatedAt: row.updated_at, lastEditedAt: undefined });
export const nodeFields = (node) => ({ authorId: node.author?.databaseId, id: node.databaseId, createdAt: node.createdAt, lastEditedAt: node.lastEditedAt });

export async function bindLaneRows(rows, { kind, check, fields = restFields }) {
  const bound = [];
  for (const row of rows) {
    const { authorId, id, createdAt, updatedAt, lastEditedAt } = fields(row);
    if (authorId !== MARKER_AUTHOR_ID || laneFooter(row.body) === null) {
      bound.push(row);
      continue;
    }
    const lane = await check({ kind, id, body: row.body, createdAt, updatedAt, lastEditedAt });
    const boundHead = lane ? bindingOf(row.body)?.sha : undefined;
    bound.push({ ...row, body: lane ? withoutBinding(row.body) : withoutLaneFooter(row.body), ...(boundHead && { boundHead }) });
  }
  return bound;
}

export async function bindTimeline(timeline, check) {
  const comments = await bindLaneRows(timeline.filter((item) => item.event === "commented"), { kind: "issue_comment", check });
  let next = 0;
  return timeline.map((item) => (item.event === "commented" ? comments[next++] : item));
}

export function withLaneBinding(api, actions, store) {
  const checkers = new Map();
  const checkerFor = (pr) => {
    if (!checkers.has(Number(pr))) {
      checkers.set(Number(pr), laneChecker({ pr: Number(pr), ...actions, store }));
    }
    return checkers.get(Number(pr));
  };
  const bindNodes = (nodes, pr) => bindLaneRows(nodes ?? [], { kind: "review_comment", check: checkerFor(pr), fields: nodeFields });
  const wrap = (name, kind) =>
    api[name] && { [name]: async (pr, ...rest) => bindLaneRows(await api[name](pr, ...rest), { kind, check: checkerFor(pr) }) };
  return {
    ...api,
    ...wrap("listIssueComments", "issue_comment"),
    ...(api.listTimeline && { listTimeline: async (pr, ...rest) => bindTimeline(await api.listTimeline(pr, ...rest), checkerFor(pr)) }),
    ...wrap("listReviewComments", "review_comment"),
    ...(api.listReviewThreads && {
      async listReviewThreads(pr, ...rest) {
        const threads = [];
        for (const thread of await api.listReviewThreads(pr, ...rest)) {
          threads.push({ ...thread, comments: { ...thread.comments, nodes: await bindNodes(thread.comments?.nodes, pr) } });
        }
        return threads;
      },
    }),
    ...(api.readThread && {
      async readThread(id) {
        const thread = await api.readThread(id);
        return { ...thread, nodes: await bindNodes(thread.nodes, thread.pr) };
      },
    }),
  };
}

export function laneReader(env, { fetch } = {}) {
  if (!env.ARTIFACT_READ_TOKEN) {
    const refuse = async () => {
      throw new Error("ARTIFACT_READ_TOKEN is not set, so a lane comment's binding cannot be checked");
    };
    return { getPull: refuse, getRun: refuse, listArtifacts: refuse, download: refuse };
  }
  const reads = createGitHubApi({ token: env.ARTIFACT_READ_TOKEN, repository: env.GITHUB_REPOSITORY, apiUrl: env.GITHUB_API_URL ?? "https://api.github.com", graphqlUrl: "", fetch });
  return { getPull: reads.getPull, getRun: reads.getRun, listArtifacts: reads.listArtifacts, download: reads.downloadArtifact };
}

export const SECURITY_SEVERITIES = Object.freeze(["SUGGESTION", "IMPORTANT", "CRITICAL"]);
export const SECURITY_PERSON_SEVERITY = "CRITICAL";
export const SEVERITY_SHAPED = /^[ \t>*_`#+\-\d.]*severity[*_`]*[ \t]*(?::|[-–—][ \t])/i;
const SECURITY_LANE_NAMED = /\blane:\s*[^\n]*claude-security-review/i;
const SEVERITY_LINE = /^severity:[ \t]*([A-Za-z]+)[ \t]*$/i;
const FENCE = /^[ \t]*(```|~~~)/;
export function severityOf(body) {
  let fence = null;
  const content = String(body ?? "")
    .split("\n")
    .map((raw) => {
      const line = raw.replace(/\r$/, "");
      const open = FENCE.exec(line)?.[1];
      const fenced = fence !== null || open !== undefined;
      if (fence === null) {
        fence = open ?? null;
      } else if (open === fence) {
        fence = null;
      }
      return { line, fenced };
    });
  const shaped = content.filter(({ line }) => SEVERITY_SHAPED.test(line));
  if (shaped.length !== 1 || shaped[0].fenced) {
    return null;
  }
  const nonBlank = content.filter(({ line }) => line.trim() !== "");
  const footer = nonBlank.length > 0 && laneOf(nonBlank.at(-1).line) !== null;
  const positions = [nonBlank[0], footer ? nonBlank.at(-2) : undefined];
  const match = positions.includes(shaped[0]) ? SEVERITY_LINE.exec(shaped[0].line) : null;
  const rating = match?.[1].toUpperCase();
  return SECURITY_SEVERITIES.includes(rating) ? rating : null;
}
export const securityNeedsPerson = (body, floor = SECURITY_PERSON_SEVERITY) => {
  const severity = severityOf(body);
  return severity === null || SECURITY_SEVERITIES.indexOf(severity) >= SECURITY_SEVERITIES.indexOf(floor);
};
export const claimsSecurity = (body, floor = SECURITY_PERSON_SEVERITY) => {
  const text = String(body ?? "");
  const claims = SECURITY_LANE_NAMED.test(text) || text.split("\n").some((line) => SEVERITY_SHAPED.test(line));
  return claims && securityNeedsPerson(text, floor);
};

const isVerifierNote = (thread) => thread.comments[0]?.author === "verifier";
const isDirected = (thread) => thread.comments.some((comment) => comment.direction === true);

export const needsPerson = (thread, rootAuthorId, floor = SECURITY_PERSON_SEVERITY) => {
  if (isVerifierNote(thread)) {
    return isDirected(thread);
  }
  const root = thread.comments[0];
  if (root?.author !== "reviewer") {
    return true;
  }
  if (root.listed === true) {
    return root.security === "held" || isDirected(thread);
  }
  if (rootAuthorId !== MARKER_AUTHOR_ID) {
    return claimsSecurity(root.body, floor);
  }
  const lane = laneOf(root.body);
  return lane === "claude-security-review" ? securityNeedsPerson(root.body, floor) : lane !== "claude-review";
};

export const securityThread = (thread, rootAuthorId, floor = SECURITY_PERSON_SEVERITY) => {
  const root = thread.comments[0];
  if (isVerifierNote(thread) || root?.author !== "reviewer") {
    return false;
  }
  return root.listed === true ? root.security === "held" : needsPerson(thread, rootAuthorId, floor);
};

export const isRoundMarker = (comment, appId) => comment.user?.id === appId && firstLine(comment.body) === ROUND_MARKER;

export function countRounds(issueComments, appId) {
  return issueComments.filter((comment) => isRoundMarker(comment, appId)).length;
}

export const MODEL_CHECK = "pr-unblock / address-feedback";
export const REPLY_CHECK = "pr-unblock / publish-feedback";
const isModelRun = (run, conclusions) =>
  run.name === MODEL_CHECK && run.app?.slug === "github-actions" && conclusions.includes(run.conclusion);
export function countCheckRounds(checkRunsByCommit) {
  return checkRunsByCommit.filter((runs) => runs.some((run) => isModelRun(run, ["success", "failure"]))).length;
}

export function lastRoundAt(issueComments, appId, checkRunsByCommit) {
  const ended = ["success", "failure", "cancelled", "timed_out"];
  const times = [
    ...issueComments.filter((comment) => isRoundMarker(comment, appId)).map((comment) => comment.created_at),
    ...checkRunsByCommit.flat().filter((run) => isModelRun(run, ended)).map((run) => run.completed_at),
  ].map((time) => Date.parse(time ?? ""));
  return times.some(Number.isNaN) ? Number.NaN : Math.max(...times);
}

const SECURITY_HOLD = /^<!-- claude-lane-hold lane=claude-security-review sha=([0-9a-f]{40}) criteria=([a-z,-]+) -->$/;
const reviewedHeadMarker = (comment) => (comment.user?.id === MARKER_AUTHOR_ID ? REVIEWED_HEAD.exec(firstLine(comment.body)) : null);
export function securitySignals(issueComments) {
  const reviewed = new Set();
  const holds = [];
  for (const comment of issueComments) {
    const marker = reviewedHeadMarker(comment);
    if (marker?.[1] === "claude-security-review") {
      reviewed.add(marker[2]);
    }
    const hold = SECURITY_HOLD.exec(laneHold({ event: "commented", ...comment }) ?? "");
    if (hold?.[2].split(",").includes("critical-security")) {
      holds.push({ sha: hold[1], at: Date.parse(comment.created_at ?? "") });
    }
  }
  return { reviewed, holds };
}

export function securityState({ reviewed, holds }, review) {
  const since = Date.parse(review.submitted_at ?? "");
  if (holds.some((hold) => hold.sha === review.commit_id || hold.at >= since)) {
    return "held";
  }
  return reviewed.has(review.commit_id) ? "clear" : "pending";
}

export function reviewedHeads(issueComments) {
  return new Set(issueComments.map((comment) => reviewedHeadMarker(comment)?.[2]).filter(Boolean));
}

const ESCALATION_REPLY =
  /^\*\*pr-unblock \/ address-feedback: (INCORRECT, left open|UNCERTAIN, left open(?: for a person)?|VALID \(defer\), left open(?: for a person)?)\*\*$/;
export const FINDING_STANDS = "<!-- pr-unblock adjudicate-feedback: finding-stands -->";
export const isEscalationReply = (comment, appId) => comment?.user?.id === appId && ESCALATION_REPLY.test(firstLine(comment.body));

export const FIX_REQUEST = /^pr-fix lane: please fix this finding(?=[\s.:;,!]|$)/i;
function leadsLine(body, lead) {
  let fenced = false;
  for (const line of String(body ?? "").split("\n")) {
    if (/^ {0,3}(```|~~~)/.test(line)) {
      fenced = !fenced;
    } else if (!fenced && lead.test(line.replace(/\r$/, ""))) {
      return true;
    }
  }
  return false;
}
export const isFixRequest = (body) => leadsLine(body, FIX_REQUEST);

export const LANE_ASK = /^pr-fix lane:/i;
export const ASKED_CAP = 10;
export const COMMENT_ITEM_ID = /^PRC_[1-9][0-9]{0,19}$/;
export const commentItemId = (commentId) => `PRC_${commentId}`;
export const answeredLine = (commentId) => `<!-- pr-unblock:answered-comment ${commentId} -->`;
const ANSWERED_LINE = /^<!-- pr-unblock:answered-comment ([1-9][0-9]{0,19}) -->$/;
export const answeredIds = (issueComments, appId) =>
  new Set(issueComments.filter((comment) => comment.user?.id === appId).map((comment) => ANSWERED_LINE.exec(firstLine(comment.body))?.[1]).filter(Boolean));

export function askedComments(issueComments, { trustedHumans = new Set(), appId }) {
  const answered = answeredIds(issueComments, appId);
  return issueComments.filter(
    (comment) => comment.user?.type === "User" && trustedHumans.has(comment.user.id) && !answered.has(String(comment.id)) && leadsLine(comment.body, LANE_ASK),
  );
}

export const askedItems = (comments) =>
  comments.slice(0, ASKED_CAP).map((comment) => ({
    id: commentItemId(comment.id),
    comment_id: comment.id,
    author: comment.user.login,
    created_at: comment.created_at,
    updated_at: comment.updated_at,
    body: comment.body,
  }));

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

export const NAMED_CAP = 10;
export const TREE_READ_CAP = 2 * NAMED_CAP;
const FILE_MODES = new Set([0o100644, 0o100755]);

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

export const reviewFixers = ({ reviewComments, trustedHumans = new Set(), permission }) =>
  fixRequesters({
    comments: reviewComments.map((row) => ({ authorId: row.user?.id, login: row.user?.login, body: row.body })),
    trustedHumans,
    permission,
  });

export function humanGatedLabelFrom(path) {
  let config;
  try {
    config = JSON.parse(trackerBindingText(path));
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

export const isReviewerComment = (comment, { reviewerId, reviewerIds = [] }) =>
  comment.authorId === reviewerId || reviewerIds.includes(comment.authorId) || isLaneComment(comment);
export const isVerifierRoot = (comment) => comment?.authorId === MARKER_AUTHOR_ID && firstLine(comment.body) === VERIFY_NOTE_MARKER;
export function threadAuthors(comments, { reviewerId, reviewerIds = [], appId, trustedHumans = new Set(), requesters = null, fixers = requesters ?? new Set() }) {
  const verifier = comments.length > 0 && isVerifierRoot(comments[0]);
  const reviewer = (comment) => isReviewerComment(comment, { reviewerId, reviewerIds });
  const isHuman = (comment) =>
    trustedHumans.has(comment.authorId) && (comment.lastEditedAt == null || trustedHumans.has(comment.editorId));
  if (comments.length === 0 || (!reviewer(comments[0]) && !verifier && !isHuman(comments[0]))) {
    return null;
  }
  const finder = (comment, i) => (i === 0 && verifier ? { author: "verifier" } : reviewer(comment) ? { author: "reviewer" } : null);
  if (comments.every((comment, i) => finder(comment, i) !== null)) {
    return requesters ? null : comments.map(finder);
  }
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

export const CODEX_MENTION = /(?:^|[^\w@/.-])@codex(?![\w-])/i;
const ANY_CODEX_MENTION = /@codex(?![\w-])/i;

export function codexRequest({ authorId, submittedAt, reviews, mentions, triggers = null, reviewerIds = [], trustedHumans = new Set(), appId }) {
  const ourBot = (id) => id === appId || id === MARKER_AUTHOR_ID;
  const at = Date.parse(submittedAt ?? "");
  if (Number.isNaN(at) || triggers === null) {
    return { reason: "codex-request-not-found" };
  }
  const since = Math.max(...reviews.filter((review) => review.authorId === authorId).map((review) => Date.parse(review.submittedAt ?? "")).filter((time) => time < at));
  const within = (time) => time > since && time <= at;
  const untrusted = (requester, via) => ({ reason: "codex-request-untrusted", requester, via });
  let trusted = false;
  for (const mention of mentions) {
    if (reviewerIds.includes(mention.authorId)) {
      continue;
    }
    const body = String(mention.body ?? "");
    const created = Date.parse(mention.createdAt ?? "");
    const edited = Date.parse((mention.reviewId === undefined ? mention.editedAt : triggers.reviewEdits?.[mention.reviewId]) ?? "");
    if (trustedHumans.has(mention.authorId)) {
      trusted ||= CODEX_MENTION.test(body) && within(created);
    } else if (ANY_CODEX_MENTION.test(body) && (Number.isNaN(created) || within(created) || within(edited))) {
      return untrusted(mention.authorId, "@codex request");
    } else if (!ourBot(mention.authorId) && created <= at && edited > created && edited > since) {
      return untrusted(mention.authorId, "edited comment");
    }
  }
  for (const deletion of triggers.deletions ?? []) {
    const id = deletion.authorId;
    if (!(Date.parse(deletion.at ?? "") <= since) && !trustedHumans.has(id) && !ourBot(id) && !reviewerIds.includes(id)) {
      return untrusted(id, "deleted comment");
    }
  }
  const events = [{ via: "opening of the pull request", ...triggers.opened }, ...triggers.ready.map((event) => ({ via: "ready-for-review event", ...event }))];
  for (const event of events) {
    if (!within(Date.parse(event.at ?? ""))) {
      continue;
    }
    if (!trustedHumans.has(event.actorId) && event.actorId !== appId) {
      return untrusted(event.actorId, event.via);
    }
    trusted = true;
  }
  return trusted ? null : { reason: "codex-request-not-found" };
}

export async function readTriggers({ api, pr, pull }) {
  try {
    const read = pull ?? (await api.getPull(pr));
    const timeline = await api.listTimeline(pr);
    const history = await api.listRequestHistory(pr);
    return {
      opened: { actorId: read?.user?.id, at: read?.created_at },
      ready: timeline.filter((event) => event?.event === "ready_for_review").map((event) => ({ actorId: event.actor?.id, at: event.created_at })),
      deletions: history.deletions,
      reviewEdits: history.reviewEdits,
    };
  } catch {
    return null;
  }
}

export const REQUEST_HISTORY_QUERY = `query($owner: String!, $name: String!, $pr: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      timelineItems(itemTypes: [COMMENT_DELETED_EVENT], first: 100) {
        pageInfo { hasNextPage }
        nodes { ... on CommentDeletedEvent { createdAt deletedCommentAuthor { ... on User { databaseId } ... on Bot { databaseId } } } }
      }
      reviews(first: 100) { pageInfo { hasNextPage } nodes { databaseId lastEditedAt } }
    }
  }
}`;
export function requestHistoryOf(data) {
  const pull = data?.repository?.pullRequest;
  if (!pull || pull.timelineItems.pageInfo.hasNextPage || pull.reviews.pageInfo.hasNextPage) {
    throw new Error("the pull request's comment deletions or reviews run past one page");
  }
  return {
    deletions: pull.timelineItems.nodes.map((node) => ({ authorId: node.deletedCommentAuthor?.databaseId, at: node.createdAt })),
    reviewEdits: Object.fromEntries(pull.reviews.nodes.filter((node) => node.lastEditedAt).map((node) => [node.databaseId, node.lastEditedAt])),
  };
}

export const anyListed = (authorIds, reviewerIds = []) => reviewerIds.length > 0 && authorIds.some((id) => reviewerIds.includes(id));

export function requestSkip({ authors, comments, reviews, mentions, triggers = null, reviewerIds = [], trustedHumans, appId }) {
  if (authors.some((author) => author.direction === true)) {
    return null;
  }
  for (const comment of comments) {
    if (reviewerIds.includes(comment.authorId) && UNSUMMONED_REVIEWER_IDS.includes(comment.authorId)) {
      if (triggers === null) {
        return { reason: "codex-request-not-found" };
      }
      const opener = triggers.opened?.actorId;
      if (!trustedHumans.has(opener) && opener !== appId) {
        return { reason: "codex-request-untrusted", requester: opener, via: "opening of the pull request" };
      }
    } else if (reviewerIds.includes(comment.authorId)) {
      const submittedAt = comment.review?.authorId === comment.authorId ? comment.review.submittedAt : undefined;
      const skip = codexRequest({ authorId: comment.authorId, submittedAt, reviews, mentions, triggers, reviewerIds, trustedHumans, appId });
      if (skip) {
        return skip;
      }
    }
  }
  return null;
}

export const requestSkipLine = (id, skip) =>
  `skip thread ${id}: ${skip.reason} (${
    skip.reason === "codex-request-untrusted"
      ? `the ${skip.via} behind the bot's review came from account ${skip.requester}, not on the trusted-actor list`
      : "no trusted @codex request, and no readable opening or ready-for-review event, since the bot's previous review"
  })`;

export const restMentions = ({ issueComments = [], reviewComments = [], reviews = [] }) => [
  ...[...issueComments, ...reviewComments].map((row) => ({ authorId: row.user?.id, createdAt: row.created_at, editedAt: row.updated_at, body: row.body })),
  ...reviews.map((review) => ({ authorId: review.user?.id, createdAt: review.submitted_at, reviewId: review.id, body: review.body })),
];

export function onReviewedHead({ authors, firstAuthorId, review, heads, rootBoundHead }) {
  const directed = authors.some((a) => a.direction === true);
  const laneVerifiedHead = rootBoundHead !== undefined && review?.commit_id === rootBoundHead;
  return firstAuthorId !== undefined && review?.user?.id === firstAuthorId && (directed || heads.has(review.commit_id) || laneVerifiedHead);
}

export function keepThreads({ threads, reviewComments, reviews, heads, security = { reviewed: new Set(), holds: [] }, reviewerId, reviewerIds = [], appId, trustedHumans = new Set(), requesters = null, fixers = requesters ?? new Set(), issueComments = [], triggers = null, log = () => {} }) {
  const comments = new Map(reviewComments.map((comment) => [comment.id, comment]));
  const reviewsById = new Map(reviews.map((review) => [review.id, review]));
  const mentions = restMentions({ issueComments, reviewComments, reviews });
  const reviewTimes = reviews.map((review) => ({ authorId: review.user?.id, submittedAt: review.submitted_at }));
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
      { reviewerId, reviewerIds, appId, trustedHumans, requesters, fixers },
    );
    if (authors === null) {
      continue;
    }
    const review = reviewsById.get(rows[0].pull_request_review_id);
    if (!onReviewedHead({ authors, firstAuthorId: rows[0].user?.id, review, heads, rootBoundHead: rows[0].boundHead })) {
      continue;
    }
    const skip = requestSkip({
      authors,
      comments: rows.map((row) => {
        const own = reviewsById.get(row.pull_request_review_id);
        return { authorId: row.user?.id, review: own && { authorId: own.user?.id, submittedAt: own.submitted_at } };
      }),
      reviews: reviewTimes,
      mentions,
      triggers,
      reviewerIds,
      trustedHumans,
      appId,
    });
    if (skip) {
      log(requestSkipLine(thread.id, skip));
      continue;
    }
    kept.push({
      id: thread.id,
      path: rows[0].path,
      line: rows[0].line ?? rows[0].original_line ?? null,
      review_commit: review.commit_id,
      is_outdated: thread.isOutdated === true,
      root_comment_id: rows[0].id,
      comments: rows.map((row, i) => {
        const lane = isLaneComment({ authorId: row.user?.id, body: row.body }) ? laneOf(row.body) : null;
        const listed = authors[i].author === "reviewer" && reviewerIds.includes(row.user?.id);
        const state = listed && i === 0 ? { security: securityState(security, review) } : {};
        return { id: row.id, ...authors[i], ...(lane ? { lane } : {}), ...(listed ? { listed } : {}), ...state, body: row.body ?? "" };
      }),
    });
  }
  return kept;
}

const LANE_STOPPED = `<!-- pr-unblock:lane-stopped activity=${ACTIVITY} -->`;
export function sessionQueued({ labels = [], issueComments, headSha, isLanesApp }) {
  const names = new Set(labels.map((label) => label.name));
  return issueComments.some((comment) => {
    const body = String(comment.body ?? "").replaceAll("\r\n", "\n");
    if (!isLanesApp(comment.user) || firstLine(body) !== LANE_STOPPED) {
      return false;
    }
    const reason = /^- Reason: `([^`]*)`$/m.exec(body)?.[1] ?? "";
    const label = Object.hasOwn(ROUTES, reason) ? ROUTES[reason].label : undefined;
    return /^- Head: `([0-9a-f]{40})`$/m.exec(body)?.[1] === headSha && typeof label === "string" && names.has(label);
  });
}

const touchesProtected = (files) => files.length >= FILES_CAP || files.some((file) => isProtectedPath(file.filename) || isProtectedPath(file.previous_filename ?? ""));

async function roundsSoFar(api, pr, issueComments, appId) {
  const checkRuns = await api.listModelRounds(pr, MODEL_CHECK);
  return { rounds: Math.max(countRounds(issueComments, appId), countCheckRounds(checkRuns)), checkRuns };
}

async function earlierFailRound({ api, pr, headSha, repository, appId, files, issueComments, heads, labeled, maxRounds, earlierFailHeads, readFailNotes, ci, log }) {
  if (touchesProtected(files)) {
    return { decision: "escalate", escalationReason: "feedback-protected-path", threads: [] };
  }
  let notes;
  try {
    notes = await readFailNotes({ heads: earlierFailHeads, files: files.map((file) => file.filename) });
  } catch (error) {
    log(`::warning::#${pr}: the notes of pr-verify's FAIL at ${earlierFailHeads.join(", ")} could not be read from its verdict artifact (${String(error?.message ?? error).slice(0, 300)})`);
    return { decision: "escalate", escalationReason: "feedback-verdict-unreadable", threads: [] };
  }
  const { rounds } = await roundsSoFar(api, pr, issueComments, appId);
  const bound = maxRounds + FRESH_FIXER_ROUNDS;
  if (rounds >= bound) {
    return { decision: "escalate", escalationReason: "feedback-verifier-open", rounds, maxRounds: bound, threads: [] };
  }
  log(`earlier-fail: ${notes.length} note item(s) from pr-verify's FAIL at ${earlierFailHeads.join(", ")}`);
  return {
    decision: "proceed",
    modelRung: retryRung(await api.listCheckRuns(headSha, REPLY_CHECK)),
    rounds,
    maxRounds: bound,
    humanGate: labeled ? "lane-escalation" : "",
    threads: [],
    file: { version: 1, repository, pr, head_sha: headSha, pr_paths: prPathsOf(files), copy_paths: copyPathsFor(files), threads: [], verify_notes: notes },
    reviewedHeads: [...heads].sort(),
    ci: await ci({ headSha, files }),
  };
}

const ADVISORY = /^\*\*Advisory\b/;
export const advisoryFinding = (thread) =>
  thread.comments.length === 1 && thread.comments[0].author === "reviewer" && thread.comments[0].lane === "claude-review" && ADVISORY.test(firstLine(thread.comments[0].body));

export function contractIssues(specText, repository) {
  return (Array.isArray(specText) ? specText : [])
    .filter((issue) => Number.isSafeInteger(issue?.number) && issue.number > 0)
    .map((issue) => ({
      number: issue.number,
      url: `https://github.com/${repository}/issues/${issue.number}`,
      body: typeof issue.body === "string" ? issue.body : null,
      comments: (Array.isArray(issue.comments) ? issue.comments : []).filter((comment) => typeof comment === "string"),
    }));
}

export async function linkedSpec(env, log) {
  if (!/^[1-9][0-9]*$/.test(env.PR_NUMBER ?? "")) {
    return [];
  }
  try {
    const { linkedIssues } = await import("../pr-verify/resolve-pr.mjs");
    const { createGitHub } = await import("../lib/github-client.mjs");
    const { loadRules } = await import("../intake-triage/admit.mjs");
    const trusted = loadTrustedList(trustedListPath(env, env.TRUSTED_ACTORS_PATH));
    const api = (keepGraphQLErrors) => createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL, keepGraphQLErrors });
    const identity = String(env.LANE_IDENTITY ?? "").trim().toLowerCase().replace(/\[bot\]$/, "");
    const taskList = loadRules(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url).pathname)["task-list"];
    const { specText } = await linkedIssues(api(false), api(true), env.GITHUB_REPOSITORY, Number(env.PR_NUMBER), trusted.humans, identity ? trusted.logins.get(`${identity}[bot]`) : undefined, taskList);
    return specText;
  } catch (error) {
    log(`::warning::cannot read the linked issues' spec text (${String(error?.message ?? error).slice(0, 300)}); this round reads none`);
    return [];
  }
}

export async function select({
  api,
  pr,
  headSha,
  repository,
  appId,
  reviewerId,
  reviewerIds = [],
  trustedHumans,
  humanGatedLabel = "needs-human",
  maxRounds = DEFAULT_MAX_ROUNDS,
  adoption = NO_ADOPTION,
  ci = async () => undefined,
  earlierFailHeads = [],
  readFailNotes = async () => {
    throw new Error("no reader of the FAILs' verdict artifacts");
  },
  pull: given,
  readSpec = async () => [],
  log = () => {},
}) {
  const pull = given ?? (await api.getPull(pr));
  const files = await api.listPullFiles(pr);
  const issueComments = await api.listIssueComments(pr);
  const reviews = await api.listReviews(pr);
  const reviewComments = await api.listReviewComments(pr);
  const threads = await api.listThreads(pr);
  const owner = ownerAuthored(pull, adoption);
  if (owner && HOLD_LINE.test(String(pull.body ?? ""))) {
    return { decision: "skip", skipReason: "awaiting-human", threads: [] };
  }
  const labeled = (pull.labels ?? []).some((label) => label.name === humanGatedLabel);
  const timeline = async () => [...commentItems(issueComments), ...(await api.listLabelEvents(pr))];
  const isLanesApp = (user) => user?.id === appId && user?.type === "Bot";
  const gated =
    labeled &&
    (owner
      ? (
          await prHold({
            labels: pull.labels.map((label) => label.name),
            holdLabels: [],
            gateLabel: humanGatedLabel,
            head: headSha,
            activity: ACTIVITY,
            appId,
            readTimeline: timeline,
            readReviews: async () => ({ comments: reviewComments, reviews }),
          })
        ).held
      : gateSource({ timeline: await timeline(), label: humanGatedLabel, head: headSha, isLanesApp }).source !== "lane-escalation");
  const fixers = await reviewFixers({ reviewComments, trustedHumans, permission: api.getPermission });
  const heads = reviewedHeads(issueComments);
  const asked = gated || pull.user?.id !== appId || touchesProtected(files) ? [] : askedItems(askedComments(issueComments, { trustedHumans, appId }));
  const kept = keepThreads({
    threads,
    reviewComments,
    reviews,
    heads,
    security: securitySignals(issueComments),
    reviewerId,
    reviewerIds,
    appId,
    trustedHumans,
    requesters: gated ? fixers : null,
    fixers,
    issueComments,
    triggers: anyListed(reviewComments.map((row) => row.user?.id), reviewerIds) ? await readTriggers({ api, pr, pull }) : null,
    log,
  });
  if (kept.length === 0) {
    if (gated) {
      return { decision: "skip", skipReason: "awaiting-human", threads: kept };
    }
    const stale = new Set(staleVerifyNotes(threads, headSha));
    const untaken = threads.some((thread) => thread.isResolved === false && !stale.has(thread.id));
    if (untaken && owner) {
      return { decision: "skip", skipReason: "not-applicable", threads: kept };
    }
    if (untaken && sessionQueued({ labels: pull.labels, issueComments, headSha, isLanesApp })) {
      return { decision: "skip", skipReason: "awaiting-session", threads: kept };
    }
    if (untaken) {
      return { decision: "escalate", escalationReason: "feedback-untaken-threads", threads: kept };
    }
    if (earlierFailHeads.length > 0 && sessionQueued({ labels: pull.labels, issueComments, headSha, isLanesApp })) {
      return { decision: "skip", skipReason: "awaiting-session", threads: kept };
    }
    if (earlierFailHeads.length > 0) {
      return { ...(await earlierFailRound({ api, pr, headSha, repository, appId, files, issueComments, heads, labeled, maxRounds, earlierFailHeads, readFailNotes, ci, log })), body: pull.body };
    }
    if (asked.length > 0) {
      return {
        decision: "proceed",
        modelRung: retryRung(await api.listCheckRuns(headSha, REPLY_CHECK)),
        humanGate: labeled ? "lane-escalation" : "",
        threads: kept,
        file: { version: 1, repository, pr, head_sha: headSha, pr_paths: prPathsOf(files), copy_paths: copyPathsFor(files), threads: kept, pr_comments: asked },
        reviewedHeads: [...heads].sort(),
        ci: await ci({ headSha, files }),
        body: pull.body,
      };
    }
    return { decision: "skip", skipReason: "stop-resolved", resolved: true, threads: kept };
  }
  if (touchesProtected(files)) {
    return { decision: "escalate", escalationReason: "feedback-protected-path", threads: kept };
  }
  const { rounds, checkRuns } = await roundsSoFar(api, pr, issueComments, appId);
  const bound = maxRounds + FRESH_FIXER_ROUNDS;
  let worked = kept;
  let retry;
  if (rounds >= maxRounds) {
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
      const rootOf = (thread) => rows.get(thread.root_comment_id);
      const spent = rounds >= bound;
      const holds = (thread) => needsPerson(thread, rootOf(thread)?.user?.id);
      if (gated || kept.some(holds)) {
        const security = kept.some((thread) => securityThread(thread, rootOf(thread)?.user?.id));
        return { decision: "escalate", escalationReason: security ? "feedback-round-cap-security" : "feedback-round-cap", rounds, maxRounds: bound, threads: kept };
      }
      if (spent) {
        const escalationReason = kept.every(isVerifierNote) ? "feedback-verifier-open" : "feedback-not-converging";
        return { decision: "escalate", escalationReason, rounds, maxRounds: bound, threads: kept };
      }
      worked = kept;
      retry = { brief: FRESH_ROUND_BRIEF };
    }
  }
  for (const thread of worked) {
    const named = await namedPaths({ thread, reviewComments, fixers, headSha, listTree: api.listTree });
    if (named.length > 0) {
      thread.named_paths = named;
    }
  }
  const advisory = worked.filter(advisoryFinding);
  const closing = advisory.length > 0 ? contractIssues(await readSpec(), repository).filter((issue) => issue.body !== null || issue.comments.length > 0) : [];
  if (closing.length > 0) {
    for (const thread of advisory) {
      thread.may_follow_up = true;
    }
  }
  return {
    decision: "proceed",
    modelRung: retryRung(await api.listCheckRuns(headSha, REPLY_CHECK)),
    rounds,
    maxRounds: bound,
    humanGate: labeled ? (gated ? "fix-request" : "lane-escalation") : "",
    threads: worked,
    file: {
      version: 1,
      repository,
      pr,
      head_sha: headSha,
      pr_paths: prPathsOf(files),
      copy_paths: copyPathsFor(files),
      threads: worked,
      ...(asked.length > 0 ? { pr_comments: asked } : {}),
      ...(closing.length > 0 ? { closing_issues: closing } : {}),
      ...(retry ? { retry } : {}),
    },
    reviewedHeads: [...heads].sort(),
    ci: await ci({ headSha, files }),
    body: pull.body,
  };
}

export function runRecord(file, reviewedHeads, ci) {
  const run = {
    version: 1,
    head_sha: file.head_sha,
    pr_paths: file.pr_paths,
    copy_paths: file.copy_paths,
    threads: file.threads.map((t) => ({
      id: t.id,
      path: t.path,
      comment_ids: t.comments.map((c) => c.id),
      ...(t.named_paths ? { named_paths: t.named_paths } : {}),
      ...(t.may_follow_up ? { may_follow_up: true } : {}),
    })),
    ...(file.stale_notes ? { stale_notes: file.stale_notes } : {}),
    ...(file.superseded_head ? { superseded_head: file.superseded_head } : {}),
    ...(file.verify_notes ? { verify_notes: file.verify_notes.map(({ id, head, path }) => ({ id, head, path })) } : {}),
    ...(file.pr_comments ? { pr_comments: file.pr_comments.map(({ id, comment_id, updated_at }) => ({ id, comment_id, updated_at })) } : {}),
    ...(reviewedHeads ? { reviewed_heads: reviewedHeads } : {}),
    ...(ci ? { ci } : {}),
    ...(file.body_sections ? { body_sections: file.body_sections.map(({ heading, text }) => ({ heading, sha256: sha256(text) })) } : {}),
  };
  return `${JSON.stringify(run)}\n`;
}

const sha256 = (text) => createHash("sha256").update(text).digest("hex");

export const BAD_CHARS = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f​-‏‪-‮⁠-⁩﻿]/u;
export const FORBIDDEN = /<!--|-->|gh[opsur]_[A-Za-z0-9]{20}|ghs_[0-9]+_|github_pat_/;

export const BODY_LIMITS = { text: 4000, sections: 8, record: 16384 };

const asciiLower = (text) => text.replace(/[A-Z]/g, (c) => c.toLowerCase());
const GATE_LEAD = /^[ \t>]*(?:(?:hold|draft|siblings|merge-risk|refs|relates[ \t]+to):|no[ \t]+(?:linked|related)[ \t]+issue)/;
const HOLD_WORDING = /do(?:n[^ \t\n\v\f\r]{0,3}t|[ \t\n\v\f\r]+not)[ \t\n\v\f\r]+merge/g;
const GATE_ANYWHERE = [
  new RegExp(HOLD_WORDING.source),
  /(?:close[sd]?|fix(?:es|ed)?|resolve[sd]?)[ \t]*:?[ \t]*(?:[a-z0-9_.-]+\/[a-z0-9_.-]+)?#[0-9]+/,
  /(?:close[sd]?|fix(?:es|ed)?|resolve[sd]?):?[ \t]*https?:\/\/github\.com\/[a-z0-9_.-]+\/[a-z0-9_.-]+\/issues\/[0-9]+/,
];

export function gateLines(body) {
  const found = [];
  let followUps = false;
  for (const raw of String(body ?? "").split("\n")) {
    const line = raw.replace(/\r$/, "");
    const lower = asciiLower(line);
    if (/^##[ \t]+follow-ups[ \t]*$/.test(lower)) {
      followUps = true;
    } else if (/^#{1,2}[ \t]/.test(lower)) {
      followUps = false;
    }
    if (followUps ? /[^ \t]/.test(line) : GATE_LEAD.test(lower) || GATE_ANYWHERE.some((re) => re.test(lower))) {
      found.push(line);
    }
  }
  for (const [match] of asciiLower(String(body ?? "").replace(/\r/g, "")).matchAll(HOLD_WORDING)) {
    if (match.includes("\n")) {
      found.push(`hold wording across lines: ${match.replace(/[ \t\n\v\f\r]+/g, " ")}`);
    }
  }
  return found.sort();
}

const SECTION_REFUSALS = [
  [/^[ \t>]*#{1,2}(?:[ \t]|$)/m, "a heading line"],
  [/^[ \t>]*(?:`{3,}|~{3,})/m, "a code fence"],
  [/\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b:?\s*https?:\/\/github\.com\/[^\s/]+\/[^\s/]+\/(?:issues|pull)\/\d/i, "a line a gate reads"],
  [/pre-existing \(advisory\):/i, "the follow-up sweep's marker"],
  [/\bcommitter\b/i, "the word committer"],
  [/(?<![A-Za-z0-9_.`/-])@[A-Za-z0-9]/, "an @-mention"],
];

export function sectionRefusal(text) {
  const value = String(text ?? "");
  if (value.trim() === "") {
    return "empty text";
  }
  if ([...value].length > BODY_LIMITS.text) {
    return "text over the size cap";
  }
  if (BAD_CHARS.test(value) || FORBIDDEN.test(value)) {
    return "a control character, an HTML comment or a token";
  }
  if (gateLines(value).length > 0 || BODY_HOLD.test(value) || LANE_HOLD.test(value) || refsIssue(value) !== null) {
    return "a line a gate reads";
  }
  return SECTION_REFUSALS.find(([shape]) => shape.test(value))?.[1] ?? null;
}

const FENCE_LINE = /^ {0,3}(`{3,}|~{3,})/;
const SECTION_HEADING = /^(#{1,2})[ \t]+(.*?)[ \t]*\r?$/;
const HEADING_NAME = /^[\p{L}\p{N} ,.'&()/+-]{1,80}$/u;

export function bodySections(body) {
  const rows = String(body ?? "").split("\n");
  const heads = [];
  let fence = "";
  rows.forEach((row, at) => {
    const marker = FENCE_LINE.exec(row);
    if (fence) {
      fence = marker && marker[1][0] === fence[0] && marker[1].length >= fence.length ? "" : fence;
      return;
    }
    if (marker) {
      fence = marker[1];
      return;
    }
    const head = SECTION_HEADING.exec(row);
    if (head) {
      heads.push({ at, heading: head[1] === "##" ? head[2] : "" });
    }
  });
  return {
    rows,
    sections: heads.map(({ at, heading }, k) => {
      const end = heads[k + 1]?.at ?? rows.length;
      return { heading, start: at, end, text: rows.slice(at + 1, end).join("\n") };
    }),
  };
}

export function refreshableSections(body, names = []) {
  const { rows, sections } = bodySections(body);
  const fold = (name) => asciiLower(name.trim());
  const wanted = new Set(names.map(fold).filter(Boolean));
  const seen = sections.map((section) => fold(section.heading));
  return sections
    .filter(
      (section, k) =>
        HEADING_NAME.test(section.heading) &&
        section.end < rows.length &&
        fold(section.heading) !== "follow-ups" &&
        seen.indexOf(seen[k]) === seen.lastIndexOf(seen[k]) &&
        (wanted.size === 0 || wanted.has(seen[k])) &&
        (section.text.trim() === "" || sectionRefusal(section.text.replace(/\r$/gm, "")) === null),
    )
    .slice(0, BODY_LIMITS.sections)
    .map(({ heading, text }) => ({ heading, text }));
}

const TEMPLATE_DIRS = [".github", "", "docs"];
const TEMPLATE_NAME = "pull_request_template.md";

export function templateHeadings(text) {
  return bodySections(String(text ?? "").replace(/<!--[\s\S]*?-->/g, ""))
    .sections.map((section) => section.heading.trim())
    .filter((heading) => HEADING_NAME.test(heading));
}

export function localTemplate(root) {
  for (const dir of TEMPLATE_DIRS) {
    let names;
    try {
      names = readdirSync(join(root, dir));
    } catch {
      continue;
    }
    const name = names.find((entry) => entry.toLowerCase() === TEMPLATE_NAME);
    if (name && lstatSync(join(root, dir, name)).isFile()) {
      return readFileSync(join(root, dir, name), "utf8");
    }
  }
  return null;
}

export async function orgTemplate(readPath, owner) {
  const base = `/repos/${encodeURIComponent(owner)}/.github/contents`;
  for (const dir of TEMPLATE_DIRS) {
    let entries;
    try {
      entries = await readPath(dir ? `${base}/${dir}` : base);
    } catch (error) {
      if (error.status === 404) {
        continue;
      }
      throw error;
    }
    const entry = Array.isArray(entries) ? entries.find((item) => item.type === "file" && String(item.name).toLowerCase() === TEMPLATE_NAME) : undefined;
    if (entry) {
      return Buffer.from((await readPath(`${base}/${entry.path}`)).content ?? "", "base64").toString("utf8");
    }
  }
  return null;
}

export async function bodySectionNames({ listed, root, readPath, owner, log = () => {} }) {
  const names = String(listed ?? "").split("\n").filter((name) => name.trim() !== "");
  if (names.length > 0) {
    return names;
  }
  const local = templateHeadings(localTemplate(root));
  if (local.length > 0) {
    return local;
  }
  try {
    return templateHeadings(await orgTemplate(readPath, owner));
  } catch (error) {
    log(`body refresh off: the ${owner}/.github pull request template is unreadable (${error.message})`);
    return null;
  }
}

/** The read-only body view's caps: code points per section, and sections. A PR body holds at most 65,536 characters, so the view stays far under the thread file's 1 MiB cap. */
export const BODY_VIEW_LIMITS = { text: 8000, sections: 30 };
// biome-ignore lint/suspicious/noControlCharactersInRegex: control characters are what it replaces
const VIEW_CONTROL = /[\u0000-\u0008\u000b-\u001f\u007f]/g;

/**
 * Every `##` section of the body, the ones refreshableSections leaves out
 * included, so the round can read what it may not rewrite: each heading and
 * its text cut to BODY_VIEW_LIMITS.text code points (`truncated` says so),
 * control characters but tab and newline shown as "?".
 */
export function bodyView(body) {
  const clean = (text) => text.replace(VIEW_CONTROL, "?");
  return bodySections(body)
    .sections.filter((section) => section.heading !== "")
    .slice(0, BODY_VIEW_LIMITS.sections)
    .map(({ heading, text }) => {
      const points = [...text.replace(/\r$/gm, "")];
      return { heading: clean(heading), text: clean(points.slice(0, BODY_VIEW_LIMITS.text).join("")), truncated: points.length > BODY_VIEW_LIMITS.text };
    });
}

export async function currentThreads({ api, pr, reviewerId, reviewerIds = [], appId, trustedHumans, heads, log = () => {} }) {
  const issueComments = await api.listIssueComments(pr);
  const reviews = await api.listReviews(pr);
  const reviewComments = await api.listReviewComments(pr);
  const threads = await api.listThreads(pr);
  const fixers = await reviewFixers({ reviewComments, trustedHumans, permission: api.getPermission });
  const triggers = anyListed(reviewComments.map((row) => row.user?.id), reviewerIds) ? await readTriggers({ api, pr }) : null;
  return {
    issueComments,
    reviewComments,
    kept: keepThreads({ threads, reviewComments, reviews, heads: heads ?? reviewedHeads(issueComments), security: securitySignals(issueComments), reviewerId, reviewerIds, appId, trustedHumans, fixers, issueComments, triggers, log }),
  };
}

const THREAD_QUERY = `query($id: ID!) {
  node(id: $id) {
    ... on PullRequestReviewThread {
      isResolved isOutdated pullRequest { number }
      comments(first: 100) {
        totalCount
        nodes { databaseId body createdAt lastEditedAt author { ... on User { databaseId } ... on Bot { databaseId } } editor { ... on User { databaseId } ... on Bot { databaseId } } }
      }
    }
  }
}`;

const TREE_QUERY = `query($owner: String!, $name: String!, $expression: String!) {
  repository(owner: $owner, name: $name) {
    object(expression: $expression) { ... on Tree { entries { name type mode } } }
  }
}`;

export const QUEUE_ENTRY_QUERY = `query($owner: String!, $name: String!, $pr: Int!) {
  repository(owner: $owner, name: $name) { pullRequest(number: $pr) { id mergeQueueEntry { id } } }
}`;
export const DEQUEUE_MUTATION = "mutation($id: ID!) { dequeuePullRequest(input: { id: $id }) { clientMutationId } }";

export const HOLD_DEQUEUE_TITLE = "hold-label-dequeue";
export const holdDequeueLine = (pr, label, outcome) =>
  `::notice title=${HOLD_DEQUEUE_TITLE}::pr=${String(pr).replaceAll(/[\r\n%]/g, " ")} label=${String(label).replaceAll(/[\r\n%]/g, " ")} outcome=${outcome}`;

export async function leaveQueueOnHold({ readQueueEntry, dequeuePull, pr, label, log = console.log }) {
  let outcome;
  let entry = null;
  try {
    entry = await readQueueEntry(pr);
  } catch (error) {
    outcome = "refused:read-failed";
    log(`::warning::#${pr}: its merge-queue entry did not read (${error.message}); it was not dequeued`);
  }
  if (entry !== null) {
    if (!entry.queued) {
      outcome = "not-queued";
    } else {
      try {
        await dequeuePull(entry.id);
        outcome = "dequeued";
      } catch (error) {
        outcome = "refused:dequeue-failed";
        log(`::warning::#${pr}: could not dequeue it (${error.message}); ci-status still fails its merge group on ${label}`);
      }
    }
  }
  log(holdDequeueLine(pr, label, outcome));
  return outcome;
}
const RESOLVE_MUTATION = `mutation($id: ID!) {
  resolveReviewThread(input: { threadId: $id }) { thread { isResolved } }
}`;

const GITHUB_ACTIONS_APP_ID = 15368;
const ROUNDS_QUERY = `query($owner: String!, $name: String!, $pr: Int!, $check: String!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      commits(first: 100) {
        pageInfo { hasNextPage }
        nodes {
          commit {
            oid
            checkSuites(first: 5, filterBy: { appId: ${GITHUB_ACTIONS_APP_ID}, checkName: $check }) {
              pageInfo { hasNextPage }
              nodes { checkRuns(first: 10, filterBy: { checkName: $check, checkType: ALL }) { pageInfo { hasNextPage } nodes { databaseId name conclusion completedAt } } }
            }
          }
        }
      }
    }
  }
}`;

const THREADS_QUERY = `query($owner: String!, $name: String!, $pr: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          id isResolved isOutdated
          comments(first: 100) {
            totalCount
            nodes { databaseId lastEditedAt editor { ... on User { databaseId } ... on Bot { databaseId } } }
          }
          root: comments(first: 1) {
            nodes { author { ... on User { databaseId } ... on Bot { databaseId } } body originalCommit { oid } }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

export const guardedFetch = async (fetchImpl = globalThis.fetch, latch) => {
  const guard = await import("../../actions/log-api-budget/rate-guard.mjs");
  return (latch ?? guard.rateLimitLatch).guard(fetchImpl, { floorGraceMs: guard.DISPATCH_FLOOR_GRACE_MS });
};

export function createGitHubApi({ token, repository, apiUrl, graphqlUrl, fetch: rawFetch = globalThis.fetch, sleep }) {
  const fetch = retryFetch(rawFetch, { sleep });
  const [owner, name] = repository.split("/");
  const headers = {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "X-GitHub-Api-Version": "2022-11-28",
  };
  async function request(url, method = "GET", body, safeToResend = false) {
    const response = await fetch(url, {
      method,
      safeToResend,
      headers: body === undefined ? headers : { ...headers, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      throw Object.assign(new Error(`${method} ${url} returned ${response.status}`), { status: response.status });
    }
    return { data: await response.json(), link: response.headers.get("link") ?? "" };
  }
  const requestData = async (...args) => (await request(...args)).data;
  const repo = `${apiUrl}/repos/${owner}/${name}`;
  async function paginate(path) {
    const rows = [];
    let url = `${repo}/${path}${path.includes("?") ? "&" : "?"}per_page=100`;
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
  const encodePath = (path) => path.split("/").map(encodeURIComponent).join("/");
  const checkRunsNamed = async (sha, check) =>
    (await requestData(`${repo}/commits/${sha}/check-runs?check_name=${encodeURIComponent(check)}&filter=all&per_page=100`)).check_runs ?? [];
  const eachCommit = async (shas, check) => {
    const runs = [];
    for (const sha of shas) {
      runs.push(await checkRunsNamed(sha, check));
    }
    return runs;
  };
  return {
    getPull: async (pr) => requestData(`${repo}/pulls/${pr}`),
    graphqlAnswer: (body) => requestData(graphqlUrl, "POST", body),
    listLabelEvents: (pr) => listLabelEvents({ graphql, repository, number: pr }),
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
    closePull: async (pr) => requestData(`${repo}/pulls/${pr}`, "PATCH", { state: "closed" }, true),
    updatePullBody: async (pr, body) => requestData(`${repo}/pulls/${pr}`, "PATCH", { body }, true),
    createIssue: (fields) => requestData(`${repo}/issues`, "POST", fields),
    listIssues: (query) => paginate(`issues?${query}`),
    listPullFiles: (pr) => paginate(`pulls/${pr}/files`),
    listIssueComments: (pr) => paginate(`issues/${pr}/comments`),
    listTimeline: (pr) => paginate(`issues/${pr}/timeline`),
    listReviews: (pr) => paginate(`pulls/${pr}/reviews`),
    listReviewComments: (pr, since) => paginate(`pulls/${pr}/comments${since === undefined ? "" : `?since=${encodeURIComponent(since)}`}`),
    listPullCommits: (pr) => paginate(`pulls/${pr}/commits`),
    async listModelRounds(pr, check) {
      const commits = (await graphql(ROUNDS_QUERY, { owner, name, pr, check })).repository.pullRequest.commits;
      if (commits.pageInfo.hasNextPage) {
        return eachCommit((await paginate(`pulls/${pr}/commits`)).map((commit) => commit.sha), check);
      }
      const runs = [];
      for (const { commit } of commits.nodes) {
        const suites = commit.checkSuites;
        runs.push(
          suites.pageInfo.hasNextPage || suites.nodes.some((suite) => suite.checkRuns.pageInfo.hasNextPage)
            ? await checkRunsNamed(commit.oid, check)
            : [...new Map(suites.nodes.flatMap((suite) => suite.checkRuns.nodes).map((run) => [run.databaseId, run])).values()].map((run) => ({
                id: run.databaseId,
                name: run.name,
                app: { slug: "github-actions" },
                conclusion: String(run.conclusion ?? "").toLowerCase() || null,
                completed_at: run.completedAt,
              })),
        );
      }
      return runs;
    },
    listCommitStatuses: (sha) => paginate(`commits/${sha}/statuses`),
    async listActivity(branch) {
      const { branchActivity, LINK } = await import("../pr-merge/merge-holds.mjs");
      const read = async (method, path) => {
        const { data, link } = await request(`${apiUrl}${path}`, method);
        return Array.isArray(data) ? Object.defineProperty(data, LINK, { value: link }) : data;
      };
      return branchActivity(read, `${owner}/${name}`, branch);
    },
    listCheckRuns: checkRunsNamed,
    async listCommitCheckRuns(sha) {
      const runs = [];
      let total = Infinity;
      for (let page = 1; page <= CHECK_RUN_PAGES; page += 1) {
        const data = await requestData(`${repo}/commits/${sha}/check-runs?filter=all&per_page=100&page=${page}`);
        runs.push(...(data.check_runs ?? []));
        total = data.total_count ?? Infinity;
        if ((data.check_runs ?? []).length < 100 || runs.length >= total) {
          break;
        }
      }
      return Object.assign(runs, { complete: runs.length >= total });
    },
    listAnnotations: async (id) => requestData(`${repo}/check-runs/${id}/annotations?per_page=50`),
    getJob: async (id) => requestData(`${repo}/actions/jobs/${id}`),
    async getJobLog(id) {
      const response = await fetch(`${repo}/actions/jobs/${id}/logs`, { headers });
      if (!response.ok) {
        throw Object.assign(new Error(`GET job ${id} logs returned ${response.status}`), { status: response.status });
      }
      return response.text();
    },
    getCommit: async (sha) => requestData(`${repo}/commits/${sha}`),
    readPath: async (path) => requestData(`${apiUrl}${path}`),
    async downloadArtifact(id) {
      const response = await fetch(`${repo}/actions/artifacts/${id}/zip`, { headers });
      if (!response.ok) {
        throw Object.assign(new Error(`GET artifact ${id} zip returned ${response.status}`), { status: response.status });
      }
      return Buffer.from(await response.arrayBuffer());
    },
    // The raw media type serves files of 1-100 MB; the default JSON form does not.
    // https://docs.github.com/en/rest/repos/contents#get-repository-content
    async getText(path, ref, { exactUtf8 = false } = {}) {
      const url = `${repo}/contents/${encodePath(path)}?ref=${encodeURIComponent(ref)}`;
      const response = await fetch(url, { headers: { ...headers, Accept: "application/vnd.github.raw+json" } });
      if (response.status === 404) {
        return null;
      }
      if (!response.ok) {
        throw new Error(`GET ${url} returned ${response.status}`);
      }
      return exactUtf8 ? new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(await response.arrayBuffer()) : response.text();
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
    listRequestHistory: async (pr) => requestHistoryOf(await graphql(REQUEST_HISTORY_QUERY, { owner, name, pr })),
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
        isOutdated: node?.isOutdated,
        nodes: node?.comments?.nodes ?? [],
      };
    },
    async readBranch(ref) {
      return (await requestData(`${repo}/git/ref/heads/${encodePath(ref)}`)).object.sha;
    },
    compare: async (base, head) => requestData(`${repo}/compare/${base}...${head}`),
    getRun: async (id) => requestData(`${repo}/actions/runs/${id}`),
    getPull: async (pr) => requestData(`${repo}/pulls/${pr}`),
    async listArtifacts(id) {
      const artifacts = [];
      for (let page = 1; ; page += 1) {
        const data = await requestData(`${repo}/actions/runs/${id}/artifacts?per_page=100&page=${page}`);
        const rows = data.artifacts ?? [];
        artifacts.push(...rows);
        if (rows.length === 0 || artifacts.length >= (data.total_count ?? 0)) {
          return artifacts;
        }
      }
    },
    createReviewComment: async (pr, fields) => requestData(`${repo}/pulls/${pr}/comments`, "POST", fields),
    replyToComment: async (pr, commentId, body) => requestData(`${repo}/pulls/${pr}/comments/${commentId}/replies`, "POST", { body }),
    async resolveThread(id) {
      return (await graphql(RESOLVE_MUTATION, { id })).resolveReviewThread.thread.isResolved;
    },
    async readQueueEntry(pr) {
      const pull = (await graphql(QUEUE_ENTRY_QUERY, { owner, name, pr })).repository.pullRequest;
      return { id: pull.id, queued: pull.mergeQueueEntry !== null };
    },
    async dequeuePull(id) {
      await graphql(DEQUEUE_MUTATION, { id });
    },
    async createIssueComment(pr, body) {
      await request(`${repo}/issues/${pr}/comments`, "POST", { body });
    },
    async updateIssueComment(id, body) {
      await request(`${repo}/issues/comments/${id}`, "PATCH", { body }, true);
    },
    async addLabels(pr, labels) {
      await request(`${repo}/issues/${pr}/labels`, "POST", { labels }, true);
    },
    async removeLabel(pr, label) {
      await request(`${repo}/issues/${pr}/labels/${encodeURIComponent(label)}`, "DELETE");
    },
    async listLabels(pr) {
      const { data, link } = await request(`${repo}/issues/${pr}/labels?per_page=100`);
      if (/rel="next"/.test(link)) {
        throw new Error("the pull request has more labels than one page holds");
      }
      return data;
    },
    createBlob: async (content) => (await requestData(`${repo}/git/blobs`, "POST", { content, encoding: "base64" }, true)).sha,
    createTree: async (baseTree, tree) => (await requestData(`${repo}/git/trees`, "POST", { base_tree: baseTree, tree }, true)).sha,
    createCommit: async (message, tree, parents) => (await requestData(`${repo}/git/commits`, "POST", { message, tree, parents }, true)).sha,
    async updateRef(ref, sha, force) {
      await request(`${repo}/git/refs/${encodePath(ref)}`, "PATCH", { sha, force }, true);
    },
  };
}

const MARKER_FILE = /^scan-refused-[1-9][0-9]{0,4}(-rung-up)?\.txt$/;

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
  return kinds.every((kind) => kind === "patch") ? "patch" : "output";
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

const readActors = (path) => readRawTrustedActors(path).actors ?? [];

export function trustedHumansFrom(trustedActorsPath) {
  return new Set(
    readActors(trustedActorsPath)
      .filter((row) => row.kind === "human")
      .map((row) => positive(row.id, `a human id in ${trustedActorsPath}`)),
  );
}

export const ownerPull = (pull, trustedHumans) => pull?.user?.type === "User" && trustedHumans.has(pull.user.id);

export const NO_ADOPTION = Object.freeze({ ownerIds: Object.freeze(new Set()), idleHours: undefined });

export const ownerAuthored = (pull, adoption = NO_ADOPTION) =>
  adoption.idleHours !== undefined && pull.user?.type === "User" && adoption.ownerIds.has(pull.user?.id);

export const HOLD_LINE = /(?:^|(?<=[\r\n]))[^\S\r\n]*hold:/i;

export async function ownerAdoption(env, log = () => {}) {
  try {
    const { adoptionFromBase } = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
    const idleHours = adoptionFromBase({ BASE_PATH: env.BASE_PATH || ".base", STANDARDS_DIR: env.STANDARDS_DIR })["idle-hours"];
    if (idleHours === undefined) {
      return NO_ADOPTION;
    }
    return { ownerIds: trustedHumansFrom(trustedListPath(env, env.TRUSTED_ACTORS)), idleHours };
  } catch (error) {
    log(`::warning::cannot read the base adoption section or trusted-actors list (${error.message}); no owner PR is served this run`);
    return NO_ADOPTION;
  }
}

export function reviewerIdFrom(trustedActorsPath, login = "claude[bot]") {
  const actor = readActors(trustedActorsPath).find((row) => row.login === login && row.kind === "bot");
  return positive(actor?.id, `the ${login} id in ${trustedActorsPath}`);
}

export function reviewerIdsFrom(text) {
  return String(text ?? "")
    .split(/\s+/)
    .filter(Boolean)
    .map((id) => positive(id, "an id in REVIEWER_IDS"));
}

export function earlierFailHeadsFrom(env) {
  const heads = String(env.VERIFY_EARLIER_FAIL_HEADS ?? "")
    .split(" ")
    .filter(Boolean);
  if (heads.length === 0) {
    return [];
  }
  if (heads.length > 10 || new Set(heads).size !== heads.length || !heads.every((sha) => SHA.test(sha) && sha !== env.HEAD_SHA)) {
    throw new Error("VERIFY_EARLIER_FAIL_HEADS is not a list of other heads' commit ids");
  }
  if (!env.DISPATCHER_RUN_ID || env.VERIFY_PASS_HEAD) {
    throw new Error("only a dispatcher run's model round names earlier FAILed heads");
  }
  return heads;
}

export function pullFromFile(path, pr, headSha) {
  if (!path) {
    return undefined;
  }
  try {
    const pull = JSON.parse(readFileSync(path, "utf8"));
    return pull?.number === pr && pull.head?.sha === headSha ? pull : undefined;
  } catch {
    return undefined;
  }
}

export async function main(argv, env, { api, actions, plan, readSpec: specReader, log = (line) => console.log(line) } = {}) {
  const command = argv[0];
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "HEAD_SHA", "APP_SENDER_ID"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!SHA.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit id");
  }
  const fetch = api ? undefined : await guardedFetch();
  const client = withLaneBinding(
    api ??
      createGitHubApi({
        token: env.GITHUB_TOKEN,
        repository: env.GITHUB_REPOSITORY,
        apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
        graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
        fetch,
      }),
    actions ?? laneReader(env, { fetch }),
  );
  const output = (key, value) => appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
  const earlierFailHeads = earlierFailHeadsFrom(env);
  let spec;
  const readSpec = () => (spec ??= specReader ? specReader() : linkedSpec({ ...env, TRUSTED_ACTORS_PATH: env.TRUSTED_ACTORS }, log));
  const selectThreads = async () => {
    need(env, ["TRUSTED_ACTORS"]);
    return select({
      api: client,
      pr,
      headSha: env.HEAD_SHA,
      repository: env.GITHUB_REPOSITORY,
      appId,
      reviewerId: reviewerIdFrom(env.TRUSTED_ACTORS),
      reviewerIds: reviewerIdsFrom(env.REVIEWER_IDS),
      trustedHumans: trustedHumansFrom(env.TRUSTED_ACTORS),
      humanGatedLabel: humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/docs/conventions/work-items.yaml"),
      maxRounds: maxRoundsFrom(env.REVIEW_ROUNDS),
      adoption: await ownerAdoption(env, log),
      ci: ({ headSha, files }) => ciSnapshot({ api: client, headSha, files, plan }),
      earlierFailHeads,
      readFailNotes: async ({ heads, files }) => {
        const { earlierFailNotes } = await import("./earlier-fail-notes.mjs");
        return earlierFailNotes({ actions: { read: client.readPath, download: client.downloadArtifact }, repository: env.GITHUB_REPOSITORY, pr, heads, files });
      },
      pull: pullFromFile(env.PULL_FILE, pr, env.HEAD_SHA),
      readSpec,
      log,
    });
  };
  if (command === "select" && env.VERIFY_PASS_HEAD) {
    need(env, ["THREAD_FILE", "RUN_FILE"]);
    if (!SHA.test(env.VERIFY_PASS_HEAD)) {
      throw new Error("VERIFY_PASS_HEAD is not a commit id");
    }
    if (env.VERIFY_SUPERSEDED_HEAD && !SHA.test(env.VERIFY_SUPERSEDED_HEAD)) {
      throw new Error("VERIFY_SUPERSEDED_HEAD is not a commit id");
    }
    if (!env.DISPATCHER_RUN_ID) {
      throw new Error("only a dispatcher run sends a pr-verify pass head");
    }
    if (env.VERIFY_PASS_HEAD !== env.HEAD_SHA) {
      log(`skip: the PR head ${env.HEAD_SHA} is not ${env.VERIFY_PASS_HEAD}, which pr-verify passed`);
      return 0;
    }
    const superseded = env.VERIFY_SUPERSEDED_HEAD === env.HEAD_SHA;
    const stale = staleVerifyNotes(await client.listThreads(pr), env.HEAD_SHA, { supersededHead: superseded ? env.HEAD_SHA : undefined });
    log(`pass-only: ${stale.length} open fail-note thread(s) from an earlier head${superseded ? " or this one, whose FAIL a pass superseded" : ""}`);
    if (stale.length > 0) {
      const file = { version: 1, repository: env.GITHUB_REPOSITORY, pr, head_sha: env.HEAD_SHA, pr_paths: [], threads: [], stale_notes: stale, ...(superseded ? { superseded_head: env.HEAD_SHA } : {}) };
      writeFileSync(env.THREAD_FILE, `${JSON.stringify(file, null, 2)}\n`);
      writeFileSync(env.RUN_FILE, runRecord(file));
      output("resolve-only", "true");
    } else {
      output("stop-resolved", String((await selectThreads()).resolved === true));
    }
    return 0;
  }
  if (command === "select") {
    need(env, ["THREAD_FILE", "RUN_FILE"]);
    const result = await selectThreads();
    if (result.file) {
      result.file.body_view = bodyView(result.body);
    }
    if (result.file && env.BODY_REFRESH !== "false") {
      const names = await bodySectionNames({ listed: env.BODY_SECTIONS, root: ".base", readPath: client.readPath, owner: env.GITHUB_REPOSITORY.split("/")[0], log });
      const sections = names === null ? [] : refreshableSections(result.body, names);
      if (sections.length > 0 && (await readSpec()).length === 0) {
        log("body refresh skipped: no linked issue read, so pr-verify may read the PR body as its spec");
      } else if (sections.length > 0) {
        result.file.body_sections = sections;
      }
    }
    if (result.file) {
      writeFileSync(env.THREAD_FILE, `${JSON.stringify(result.file, null, 2)}\n`);
      writeFileSync(env.RUN_FILE, runRecord(result.file, result.reviewedHeads, result.ci));
    }
    output("proceed", String(result.decision === "proceed"));
    output("human-gate", result.humanGate ?? "");
    output("model-rung", result.modelRung ?? "");
    output("skip-reason", result.decision === "skip" ? result.skipReason : result.decision === "escalate" ? stopSkip(result.escalationReason) : "");
    output("escalation-reason", result.escalationReason ?? "");
    output("not-run-detail", result.decision === "escalate" && result.maxRounds ? roundLine(result.rounds, result.maxRounds) : "");
    output("stop-resolved", String(result.resolved === true));
    const pull = pullFromFile(env.PULL_FILE, pr, env.HEAD_SHA);
    output("person-opened", String(pull !== undefined && ownerPull(pull, trustedHumansFrom(env.TRUSTED_ACTORS))));
    log(`${result.decision}: ${result.threads.length} kept thread(s), ${result.rounds ?? 0} earlier round(s)${result.escalationReason ? `, ${result.escalationReason}` : ""}`);
    return 0;
  }
  throw new Error("usage: address-feedback.mjs select");
}

runAsScript(import.meta.url, "address-feedback", () => main(process.argv.slice(2), process.env));
