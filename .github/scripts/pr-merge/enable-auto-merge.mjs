#!/usr/bin/env node
// enable-auto-merge.mjs: turns on GitHub's native auto-merge for the lanes
// App's open pull requests into main, and turns it off on one that now carries
// a hold. No model. pr-merge.yml's enable-auto-merge job runs it when a listed
// human edits, unlabels or readies a pull request, and on the schedule, which
// arms.
//
// A pull request is armed only when all of these hold:
// - The lanes App opened it (merge.agent-identity), into main, from a branch
//   of this repository, and it is not a draft.
// - It carries no hold: no `do-not-merge` and no human-gated label (the
//   tracker's role label, `needs-human` by default), and no body hold: the
//   lane's own hold line (merge-holds.mjs LANE_HOLD), or hold text a person
//   wrote (BODY_HOLD and personWrote). Labels past the listing's 100 are
//   read whole.
// - No member vetoes it (merge-holds.mjs), its discussion read whole page by
//   page (wholeDiscussion). ci-status fails on both holds too, so one added
//   after arming stops the merge queue rather than waiting for this job's
//   next run.
// - Its head changes no hold path: the merge lane's denied paths
//   (report-outcome.readHoldPaths) or the path floor (merge-holds.mjs
//   HOLD_PATH_FLOOR, this base copy's constant), read against the files,
//   renamed-from paths included, that the head changes now, since a push after report-outcome
//   wrote its Hold: line can add one. The rule is merge-holds.pathHold, which
//   ci-status also runs on every lanes App pull request event and merge
//   group, so a push after arming is held without waiting for this job. A
//   config that does not read arms nothing and labels nothing; the next run
//   reads it again.
// - Its head changes no cost path, unless its body links the owner's cost
//   decision: merge-holds.costHold and costDecision, which ci-status runs too.
// - No person turned its auto-merge off: the newest auto-merge-disabled event
//   by a user account keeps it off until a person turns it on again.
// - pr-merge's gate would take its issue link and its verifier verdict at the
//   head just read: babysit_verify_evidence.py `evidence --lane-link` refuses
//   nothing (verifyHold). The link is the gate's own rule
//   (babysit_merge_policy._linked_issue): one closing issue in this
//   repository, or, with none, the one issue its plain `Refs: #<issue>` lines
//   name, and that issue clears the trust hold
//   (babysit_merge_policy.trust_refusal): its labels read whole, none naming
//   untrusted work in any spelling and none ever removed by a non-human, so
//   one added after admission refuses for a person
//   (`untrusted-provenance`). Then a pr-verify PASS or PASS-NOTES stands at that head, no FAIL is
//   at it, no earlier FAIL is uncleared, FAILs sit at fewer than
//   merge.max-verify-fails heads, and the spec is unchanged and trusted. A
//   read that fails, or a line without the link's answer, refuses. Only the
//   scheduled run and
//   a hand-started one read them (READER_EVENTS), last, for a pull request
//   every other rule would arm or keep armed, sharing one artifact listing,
//   read once for the run, and run cache. An event run (a person's edit,
//   unlabel or ready) never arms and reads no verdict: it only disarms on a
//   hold, so a pull request waits up to one scheduled interval to be armed.
//   ci-status disarms an armed lanes App pull request on each push to its
//   head, so a new head is armed only after the reader judges it, and in the
//   merge queue it checks the pass again at the head it merges
//   (merge-holds.mjs verdictHold) and runs this reader again there on a
//   listing of its own (merge-holds.mjs evidenceHold), which holds a FAIL
//   uploaded after the run's one listing.
// - pr-merge's gate would let its lane merge one more now: babysit_verify_evidence.py
//   `lane-room` (babysit_merge_policy.lane_room) reads, once per reader run,
//   the run-level refusals the gate applies to every lane candidate. While
//   the gate holds the lane off (a demotion record, merge.rung, the loop
//   setting or the rung cap off, a post-merge failure, another authority)
//   nothing is armed and every armed lanes App pull request is disarmed.
//   Below merge.max-in-flight, counting the merge queue's lane entries, the
//   lane's unverified merges and the armed pull requests not yet queued, it
//   arms; at the cap it arms nothing more. A room that cannot be read (no
//   post-merge report, a failed read) holds as a refusal does: nothing is
//   armed and every armed lanes App pull request is disarmed. A report the
//   gate would not reuse, for any reason, is checked again as the gate does;
//   one past its reuse age only for a lane merge still unverified is first
//   kept while nothing it was read from has moved, and one refused only for
//   a demotion record filed or changed since is first kept when the
//   demotion records alone read as they were. A held room raises one warning annotation and step-summary line
//   naming why and each lane pull request left unarmed or, report-only,
//   that a disarm would have turned off, and one error and summary line
//   naming each one still armed because its disarm failed.
// - pr-merge's gate would not hold it on its risk score: `evidence
//   --lane-reviews --rung <the room's rung>` runs the gate's scorer
//   (babysit_risk.score, holding) over the inputs the gate builds, the
//   review lanes' evidence bound to the head included. So an open CRITICAL
//   security finding or a review not bound to the head (whether or not the
//   lane applied its hold label), a symlink, submodule or other non-regular
//   mode, a high path, the manifest review, the trust gate and the cost
//   review hold. Read only after the verdict allows.
// - pr-merge's gate would enqueue its head again: `evidence --lane-queue`
//   reads the gate's count of failed-check merge-queue removals since the
//   head changed against merge.max-queue-ejections (ejectionHold). At the cap
//   it is left unarmed with the gate's own marked comment and no label (a
//   push resets the count); an unread count leaves it unarmed. GitHub drops
//   the arm on an ejection, so an armed one is not disarmed on this.
// A reader run that leaves a lanes App pull request unarmed, or disarms it,
// on the lane's hold line, a hold path, a cost hold, the gate's verdict or
// its risk score says why on the pull request, since under merge.lane-prs
// native the gate never lists it: a `<!-- babysit-merge-risk -->` comment,
// edited in place while it is a lane's, posted anew when it becomes a
// person's, and left alone while the reason and head are unchanged
// (refusalWrites). The
// comment is the record; only a cause a person must clear (owner rule
// 2026-10-26: an intent or design change or a CRITICAL security issue, with
// cost and trust holds and a hold no lane can clear kept: untrusted
// provenance or an untrusted spec, the repeated-FAIL cap, a pull request too
// old to verify, a security finding, a high path, a trusted-actor widening,
// a real charge or a listing too long to check, see verifyClears; a hold path, a configured denied path
// or the floor, which only a trusted approval lifts; and the lane's own hold
// line, owner decision Q-HOLDLINE) also gets the human-gated label, put back
// while the comment stands unless a person removed it since. Every other
// refusal, a listing read that failed included, is a lane's: the next
// scheduled runs judge it again, and once a lane's refusal has stood at the
// head for merge.risk-escalation-minutes (timed from the first one there,
// LANE_SINCE) the run hands a
// failing `pr-merge/unarmed` status for the head to the unarmed-status job
// (unarmedStatus, post-unarmed-status.mjs), and a passing one when it arms
// or the refusal becomes a person's.
// clear-escalations takes the label off at the latest once the head moves,
// and this run labels the new head again only if its cause still holds.
// Holds a person already set (labels, their own body hold, a veto), the room
// and a discussion that did not read write nothing.
// Arming passes the head just read as expectedHeadOid, so a push in between
// fails the arm rather than arming a head nobody read. Before it arms, the run
// posts the gate's pin comment for that head (pinBody) unless the lanes App's
// newest pin already names it unedited, and a pin that fails to post leaves
// the pull request unarmed: an arm GitHub enqueues at once records no
// auto-merge event, so the post-merge check reads that head back against the
// pin. An armed pull request
// that fails any rule is disarmed. Each request opens its own connection, and
// a read or write that fails on the network is sent up to twice more
// (withRetry). One whose arm or disarm still fails is left as it was, named
// with its cause, and the run goes on to the rest, then exits 1. While
// merge.report-only is true it reports
// each decision and writes nothing.
//
// Environment:
//   GH_TOKEN             the lane App token (contents and pull-requests write)
//   GITHUB_REPOSITORY    owner/repo
//   KILL_SWITCH          `proceed` from the kill-switch step; anything else stops
//   REPORT_ONLY          `false` writes; anything else reports only
//   LANES_BOT_LOGIN      merge.agent-identity, an App bot login
//   TRACKER_CONFIG       the base .work-item-tracker.json, for the human-gated
//                        label (default .base/.work-item-tracker.json)
//   RESOLVED_CONFIG      the resolve-config output, for the hold paths
//   TRUSTED_ACTORS       the base trusted-actors.json, for the owner of a cost
//                        decision (default .base/.github/standards/trusted-actors/trusted-actors.json)
//   EVENT_NAME           the run's event; only READER_EVENTS read verdicts and arm
//   POSTMERGE_RESULT     this run's babysit_postmerge.py report, for lane-room
//   RUNG_CAP             vars.CLAUDE_LANES_MERGE_RUNG_CAP (empty is no cap;
//                        unset holds the lane off, as the gate reads it)
//   RISK_ESCALATION_MINUTES  merge.risk-escalation-minutes (empty is
//                        RISK_ESCALATION_MINUTES)
//   GITHUB_OUTPUT        receives UNARMED_OUTPUT for the unarmed-status job
//   BABYSIT_VERIFY_*, BABYSIT_RUN_CACHE  the reader's Actions token (the
//                        job's GITHUB_TOKEN), saved listing, head-ref map and
//                        run cache, as the gate's
//   VERIFY_ANSWERS_IN, VERIFY_ANSWERS_OUT  the verifier answers the last run
//                        kept (verify-answers.mjs) and the file this run keeps
//   VERIFY_CACHE         merge.verify-cache: `serve` serves a kept refusal to
//                        an unarmed pull request; anything else is `shadow`,
//                        which reads in full and logs how a kept answer
//                        compares (VERIFY_CACHE_PREFIX)
//   GITHUB_API_URL
import { spawnSync } from "node:child_process";
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, errorLabel, GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { humanGatedLabelFrom } from "../pr-unblock/address-feedback.mjs";
import { readHoldPaths } from "../work-resolve-issue/report-outcome.mjs";
import { BODY_HOLD, costDecision, costHold, humansOf, LANE_HOLD, pathHoldKind, personWrote, vetoers } from "./merge-holds.mjs";

export { BODY_HOLD, HUMAN_VETO } from "./merge-holds.mjs";

const REPO = /^([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)$/;
const SHA = /^[0-9a-f]{40}$/;
const BOT_LOGIN = /^([a-z0-9][a-z0-9-]*)\[bot\]$/;
// babysit_merge_policy.MERGE_HOLD_LABELS, plus the human-gated label.
const HOLD_LABELS = Object.freeze(["do-not-merge"]);
// 100 pull requests a page; more than this many open is a listing the run
// stops on rather than one it reads only part of.
const MAX_PAGES = 10;
// Changed files read per pull request, 100 a page; more is a head the run
// does not arm on.
const MAX_FILE_PAGES = 3;
const VERIFY_SCRIPT = ".base/plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py";

// Into main, by name: the gate reads the default branch live
// (babysit_merge_policy._base_refusal), while this assumes it is main.
export const PULLS_QUERY = `query($owner: String!, $name: String!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(states: OPEN, baseRefName: "main", first: 100, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id number isDraft isCrossRepository headRefOid baseRefOid body
        author { __typename login }
        userContentEdits(first: 100) { totalCount nodes { editor { __typename } } }
        labels(first: 100) { totalCount nodes { name } }
        autoMergeRequest { enabledAt }
      }
    }
  }
}`;
// One candidate's discussion: the newest 100 of each, and wholeDiscussion
// reads the rest of any list that has more.
const COMMENT_FIELDS = "databaseId author { __typename login } body createdAt updatedAt lastEditedAt authorAssociation";
const REVIEW_FIELDS = "author { __typename login } body submittedAt authorAssociation";
const THREAD_COMMENT_FIELDS = "author { __typename login } body createdAt authorAssociation";
const THREAD_FIELDS = `id comments(last: 100) { totalCount nodes { ${THREAD_COMMENT_FIELDS} } }`;
export const DETAIL_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      comments(last: 100) { totalCount nodes { ${COMMENT_FIELDS} } }
      reviews(last: 100) { totalCount nodes { ${REVIEW_FIELDS} } }
      reviewThreads(last: 100) { totalCount nodes { ${THREAD_FIELDS} } }
      timelineItems(itemTypes: [AUTO_MERGE_DISABLED_EVENT], last: 1) { nodes { ... on AutoMergeDisabledEvent { actor { __typename login } } } }
    }
  }
}`;
const pageOf = (field, fields) => `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { ${field}(first: 100, after: $after) { totalCount pageInfo { hasNextPage endCursor } nodes { ${fields} } } }
  }
}`;
// One page of a discussion list, oldest first.
export const DISCUSSION_PAGE_QUERIES = Object.freeze({
  comments: pageOf("comments", COMMENT_FIELDS),
  reviews: pageOf("reviews", REVIEW_FIELDS),
  reviewThreads: pageOf("reviewThreads", THREAD_FIELDS),
});
export const THREAD_PAGE_QUERY = `query($id: ID!, $after: String) {
  node(id: $id) { ... on PullRequestReviewThread { comments(first: 100, after: $after) { totalCount pageInfo { hasNextPage endCursor } nodes { ${THREAD_COMMENT_FIELDS} } } } }
}`;
// Pages read of one discussion list before the run stops on it.
const MAX_DISCUSSION_PAGES = 30;
export const ARM_MUTATION = `mutation($id: ID!, $head: GitObjectID!) {
  enablePullRequestAutoMerge(input: { pullRequestId: $id, mergeMethod: SQUASH, expectedHeadOid: $head }) {
    pullRequest { autoMergeRequest { enabledAt } }
  }
}`;
export const DISARM_MUTATION = `mutation($id: ID!) {
  disablePullRequestAutoMerge(input: { pullRequestId: $id }) { clientMutationId }
}`;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// A network failure, with no answer from GitHub: undici's "fetch failed"
// TypeError, which every failure of Node's fetch is whatever its cause, or any
// error whose cause has one of these codes or undici's "other side closed".
// An HTTP answer (a 4xx included) and a GraphQL error are GitHubErrors with
// no cause, never this.
const TRANSIENT_CODES = new Set(["ECONNRESET", "ETIMEDOUT", "UND_ERR_SOCKET", "UND_ERR_CONNECT_TIMEOUT"]);
export const transient = (error) =>
  (error?.name === "TypeError" && error.message === "fetch failed") ||
  TRANSIENT_CODES.has(error?.cause?.code) ||
  error?.cause?.message === "other side closed";
// At most three attempts. Before each resend, a full-jitter wait: a random
// share of 4 s, then of 8 s, so the waits sum to at most 12 s.
export const RETRY_CAPS_MS = Object.freeze([4000, 8000]);
// An error's message with its cause's code and message, any token scrubbed:
// undici puts a whole header value in some messages.
export function describe(error) {
  const cause = error?.cause;
  const text = cause ? `${error?.message ?? error} (cause: ${[cause.code, cause.message].filter(Boolean).join(" ")})` : String(error?.message ?? error);
  return escapeCommand(text.replaceAll(/Bearer\s+\S+|gh[pousr]_\w+|github_pat_\w+/g, "***"));
}
// `github` with every request on a connection of its own, and a GraphQL
// POST that fails on the network sent again (RETRY_CAPS_MS). `Connection: close` closes
// each socket after its answer, so no request goes out on a pooled one that
// sat idle through a verifier read and that GitHub has since closed. A GET is
// left to createGitHub's own retry (retryServerErrors), which resends only
// GETs and GraphQL queries, so a query can go out up to three times four. This
// retry's waits, and the first send of each resend, fall outside that helper's
// 60 s budget; the step's 18-minute timeout (pr-merge.yml) is the outer cap.
// A REST write such as the refusal comment is never resent, since a
// lost answer would post it twice. A resent arm is pinned to the same expectedHeadOid, so it can arm
// only the head the run read. When the lost answer was a success, the resend
// may arm or disarm a pull request already in that state; should GitHub
// answer that with an error, the run reports it (a warning for an arm, an
// error and exit 1 for a disarm) with the state right, and the next run reads
// it as it is.
export function withRetry(github, { sleep, random = Math.random }) {
  return async (method, path, body, headers = {}, options) => {
    for (let attempt = 0; ; attempt += 1) {
      try {
        return await github(method, path, body, { Connection: "close", ...headers }, options);
      } catch (error) {
        const cap = RETRY_CAPS_MS[attempt];
        if (path !== "/graphql" || cap === undefined || !transient(error)) {
          // How many sends it took: after a resend, an earlier one may have landed.
          if (error !== null && typeof error === "object") {
            error.attempts = attempt + 1;
          }
          throw error;
        }
        const wait = Math.round(random() * cap);
        const what = body?.query === ARM_MUTATION ? " (arm)" : body?.query === DISARM_MUTATION ? " (disarm)" : "";
        const pull = body?.variables?.number ?? body?.variables?.id;
        console.log(`::warning::enable-auto-merge: ${method} ${path}${what}${pull === undefined ? "" : ` for ${pull}`} failed (${errorLabel(error)}); sending it again in ${wait} ms (retry ${attempt + 1} of ${RETRY_CAPS_MS.length})`);
        await sleep(wait);
      }
    }
  };
}

// GraphQL error types that a token, permission or rate limit answers for every
// pull request alike, never a refusal of one.
const RUN_WIDE_TYPES = new Set(["RATE_LIMITED", "FORBIDDEN", "INSUFFICIENT_SCOPES"]);
// GitHub refusing to arm this one pull request: a GraphQL error, or a 4xx
// other than 401, 403 and 429. `runWide` is an answer that is rate-limited or
// carries a RUN_WIDE_TYPES error, which is never a refusal.
export const refused = (error, runWide = false) =>
  error instanceof GitHubError && !runWide && (error.status === 200 || (error.status >= 400 && error.status < 500 && ![401, 403, 429].includes(error.status)));
// An error answer's messages, whether its GraphQL error types are run-wide,
// and whether any error names a type at all.
async function answerBody(text) {
  try {
    const json = JSON.parse(await text);
    const errors = Array.isArray(json?.errors) ? json.errors : [json];
    return {
      said: errors.map((error) => error?.message).filter(Boolean).join("; "),
      runWide: errors.some((error) => RUN_WIDE_TYPES.has(error?.type)),
      typed: errors.some((error) => typeof error?.type === "string"),
    };
  } catch {
    return { said: "", runWide: false, typed: false };
  }
}

// The hold reason for report-outcome's own hold line (merge-holds.mjs
// LANE_HOLD), a cause a person must clear (owner decision Q-HOLDLINE).
export const LANE_HOLD_REASON = "its body carries the lane's own 'Hold: a human merges this' line: a person merges it by hand, or removes that line";

// Why `pull` must not be armed, or null when it may be.
export function holdReason(pull, humanGated) {
  const labels = pull.labels?.nodes ?? [];
  if (!(pull.labels?.totalCount <= labels.length)) {
    return "its labels could not all be read";
  }
  const names = new Set(labels.map((label) => String(label?.name).toLowerCase()));
  const label = [...HOLD_LABELS, humanGated].find((name) => names.has(name.toLowerCase()));
  if (label !== undefined) {
    return `it carries ${label}`;
  }
  const body = String(pull.body ?? "");
  if (LANE_HOLD.test(body)) {
    return LANE_HOLD_REASON;
  }
  return BODY_HOLD.test(body) && personWrote(pull) ? "its body holds it" : null;
}

const whole = (connection) => Array.isArray(connection?.nodes) && connection.totalCount <= connection.nodes.length;

// Every label of pull request `number`, 100 a page, when the listing cut them.
const MAX_LABEL_PAGES = 10;
export async function allLabels(github, repo, number) {
  const names = [];
  for (let page = 1; page <= MAX_LABEL_PAGES; page += 1) {
    const rows = await github("GET", `/repos/${repo}/issues/${number}/labels?per_page=100&page=${page}`);
    if (!Array.isArray(rows)) {
      throw new Error("its labels did not read");
    }
    names.push(...rows.map((row) => ({ name: String(row?.name) })));
    if (rows.length < 100) {
      return { totalCount: names.length, nodes: names };
    }
  }
  throw new Error(`more than ${MAX_LABEL_PAGES * 100} labels`);
}

// Every node of one discussion list, page by page from the start; `pick`
// finds the list in an answer.
async function every(github, query, variables, pick) {
  const nodes = [];
  let after = null;
  for (let page = 0; page < MAX_DISCUSSION_PAGES; page += 1) {
    const found = pick((await github("POST", "/graphql", { query, variables: { ...variables, after } }))?.data);
    if (!Array.isArray(found?.nodes)) {
      throw new Error("a discussion page did not read");
    }
    nodes.push(...found.nodes);
    if (!found.pageInfo?.hasNextPage) {
      return { totalCount: nodes.length, nodes };
    }
    after = found.pageInfo.endCursor;
  }
  throw new Error(`a discussion list longer than ${MAX_DISCUSSION_PAGES * 100}`);
}

// `detail` (DETAIL_QUERY's pullRequest) with each list it cut read whole:
// its comments, reviews, review threads and each thread's comments.
export async function wholeDiscussion(github, variables, detail) {
  const read = { ...detail };
  for (const [key, query] of Object.entries(DISCUSSION_PAGE_QUERIES)) {
    if (!whole(read[key])) {
      read[key] = await every(github, query, variables, (data) => data?.repository?.pullRequest?.[key]);
    }
  }
  const threads = [];
  for (const thread of read.reviewThreads.nodes) {
    threads.push(whole(thread?.comments) ? thread : { ...thread, comments: await every(github, THREAD_PAGE_QUERY, { id: String(thread?.id) }, (data) => data?.node?.comments) });
  }
  return { ...read, reviewThreads: { ...read.reviewThreads, nodes: threads } };
}

// Why the discussion `detail` (DETAIL_QUERY's pullRequest) holds it, or null.
export function discussionHold(detail) {
  const threads = detail?.reviewThreads;
  if (![detail?.comments, detail?.reviews, threads].every(whole) || !threads.nodes.every((thread) => whole(thread?.comments))) {
    return "its comments could not all be read";
  }
  const items = [...detail.comments.nodes, ...detail.reviews.nodes, ...threads.nodes.flatMap((thread) => thread.comments.nodes)].map((item) => ({
    login: item?.author?.login,
    isUser: item?.author?.__typename === "User",
    association: item?.authorAssociation,
    at: String(item?.submittedAt ?? item?.createdAt ?? ""),
    body: String(item?.body ?? ""),
  }));
  const vetoes = vetoers(items);
  return vetoes.length ? `${vetoes.join(", ")} asked not to merge it` : null;
}

// The trusted-actor list's people; an unreadable list names none, so no cost
// decision clears.
function trustedHumans(env) {
  try {
    const { actors } = JSON.parse(readFileSync(env.TRUSTED_ACTORS || ".base/.github/standards/trusted-actors/trusted-actors.json", "utf8"));
    return humansOf(actors);
  } catch {
    return new Set();
  }
}

// The head's changed paths, null when a page did not read, and `capped`
// when the listing has a page past MAX_FILE_PAGES, which no later read
// completes. Exactly MAX_FILE_PAGES full pages read one page more to tell.
async function changedFiles(github, slug, number) {
  const paths = [];
  for (let page = 1; page <= MAX_FILE_PAGES + 1; page += 1) {
    const rows = await github("GET", `/repos/${slug}/pulls/${number}/files?per_page=100&page=${page}`);
    if (!Array.isArray(rows)) {
      return { paths: null, capped: false };
    }
    if (page > MAX_FILE_PAGES) {
      return rows.length === 0 ? { paths, capped: false } : { paths: null, capped: true };
    }
    for (const row of rows) {
      paths.push(String(row?.filename), ...(row?.previous_filename ? [String(row.previous_filename)] : []));
    }
    if (rows.length < 100) {
      return { paths, capped: false };
    }
  }
  return { paths: null, capped: true };
}

// A listing past MAX_FILE_PAGES: no lane can ever judge its hold and cost
// paths, so a person clears it.
export const FILES_CAPPED_REASON = `it changes more than ${MAX_FILE_PAGES * 100} files, so its hold and cost paths cannot all be checked`;

// How verifyHold opens the reason for each answer that refuses: the issue
// link, the verifier verdict and the risk score.
export const READER_HOLDS = Object.freeze({
  link: "pr-merge's lane does not take its issue link (",
  verdict: "pr-merge's gate refuses its verifier verdict (",
  risk: "pr-merge's gate holds it on its risk score (",
});

// Why the gate's `evidence --lane-link` (babysit_verify_evidence.py's report)
// keeps a pull request at `head` from merging, or null when it allows it.
export function verifyHold(evidence, head) {
  if (evidence === null || typeof evidence !== "object" || !("refusal" in evidence)) {
    return "its verifier verdict could not be read";
  }
  if (evidence.head !== head) {
    return "its verifier verdict was read at another head";
  }
  if (typeof evidence.ineligible === "string") {
    return `${READER_HOLDS.link}${escapeCommand(evidence.ineligible)})`;
  }
  if (evidence.refusal !== null) {
    return `${READER_HOLDS.verdict}${escapeCommand(evidence.refusal)})`;
  }
  // A line without the link's or the reviews' answer read neither: it allows nothing.
  if (evidence.ineligible !== null) {
    return "its issue link could not be read";
  }
  if (typeof evidence.reviews === "string") {
    return `${READER_HOLDS.risk}${escapeCommand(evidence.reviews)})`;
  }
  return evidence.reviews === null ? null : "its risk score could not be read";
}

// The trust hold's reasons (babysit_merge_policy.trust_refusal), each a
// person's: an issue label naming untrusted work, and labels that cannot be
// read whole, more than the 100 the read lists, which no later read changes.
export const TRUST_REFUSALS = Object.freeze(["untrusted-provenance", "untrusted-provenance-removed-by-non-human", "issue-labels-unreadable"]);

// Who clears the refusal verifyHold reads in `evidence` at `head` (owner rule
// 2026-10-26: a person only for an intent or design change, or a CRITICAL
// security issue; cost and trust holds and a hold no lane can clear stay a
// person's): `person`
// for an issue link the trust hold refuses (TRUST_REFUSALS), a verifier
// refusal the gate marks `needsHuman` (babysit_verify_evidence NEEDS_HUMAN)
// or a risk hold it marks `reviewsPerson` (babysit_risk.person_reasons),
// `lane` for every other refusal, which gets the comment and no label, and
// null for an unread answer, which the next run reads again. An answer
// without its flag is a person's, as any doubt holds.
export function verifyClears(evidence, head) {
  if (evidence === null || typeof evidence !== "object" || evidence.head !== head) {
    return null;
  }
  if (typeof evidence.ineligible === "string") {
    return TRUST_REFUSALS.includes(evidence.ineligible) ? "person" : "lane";
  }
  if (typeof evidence.refusal === "string") {
    return evidence.needsHuman === false ? "lane" : "person";
  }
  if (evidence.ineligible === null && typeof evidence.reviews === "string") {
    return evidence.reviewsPerson === false ? "lane" : "person";
  }
  return null;
}

// Why the gate would not enqueue the head again (`evidence --lane-queue`,
// babysit_merge.queue_ejection_refusal: merge.max-queue-ejections failed-check
// removals since the head changed), with the gate's marked comment when the
// count was read, or null under the cap. An answer not of that shape holds.
export function ejectionHold(evidence) {
  const queue = evidence?.queue;
  if (queue === null || typeof queue !== "object" || !(queue.refusal === null || typeof queue.refusal === "string")) {
    return { reason: "its merge-queue ejections could not be read", comment: null };
  }
  return queue.refusal === null
    ? null
    : { reason: `pr-merge's gate would not enqueue it again (${escapeCommand(queue.refusal)})`, comment: typeof queue.comment === "string" ? queue.comment : null };
}

// The refusal comment on a lanes App pull request the run leaves unarmed:
// pr-merge's reasons-comment marker and shape (babysit_merge.py
// risk_comment_body), its second line naming the head, and for a person's
// refusal the interactive queue's escalation marker first (work-items
// escalation-marker.md), as the gate's Dependabot escalation carries it. A
// function of the class, the reason and the head only, so an unchanged
// refusal renders the same body.
export const REFUSAL_MARKER = "<!-- babysit-merge-risk -->";
export const ATTEND_QUEUE_MARKER = "<!-- work-items:escalation lane=pr-merge kind=escalated -->";
// The lane comment's last line: when a lane's refusal was first noted at
// `head`, kept while the head is unchanged so a reason whose detail moves
// every run does not restart unarmedStatus's timer.
export const LANE_SINCE = /^<!-- pr-merge-unarmed-since head=([0-9a-f]{40}) at=([0-9TZ:.-]+) -->$/;
const laneSince = (head, at) => `<!-- pr-merge-unarmed-since head=${head} at=${at} -->`;
// When the lane comment `body` says its refusal at `head` began; else
// undefined.
function sinceAt(body, head) {
  const match = LANE_SINCE.exec(String(body ?? "").split("\n").at(-1).replace(/\r$/, ""));
  return match && match[1] === head ? match[2] : undefined;
}

export function refusalBody(person, reason, head, label, since = null) {
  const who = person
    ? `A person must clear this reason, so the pr-merge lane added the \`${label}\` label: fix the reason, then remove the label, and the next scheduled run judges it again.`
    : "The lanes clear this reason on their own; the next scheduled run judges it again.";
  return [
    ...(person ? [ATTEND_QUEUE_MARKER] : []),
    REFUSAL_MARKER,
    `Unattended merge: native auto-merge leaves this pull request unarmed at head \`${head}\`. ${who}`,
    "",
    "```text",
    String(reason).replaceAll(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "?").replaceAll("```", "'''"),
    "```",
    ...(person || since === null ? [] : [laneSince(head, since)]),
  ].join("\n");
}

// The pin the post-merge read-back checks the merged head against
// (babysit_postmerge.pin_comment and PIN_RE): arming a pull request that is
// already mergeable enqueues it at once with no auto-merge event, which the
// read-back judges as an identity enqueue, so the head is pinned first.
export const PIN_RE = /^<!-- babysit-merge-pin sha=([0-9a-f]{40}) -->$/;
export const pinBody = (sha) => `<!-- babysit-merge-pin sha=${sha} -->\nThe unattended merge path armed native auto-merge at head \`${sha}\`.`;

// Whether the read-back would already read `head` from `comments`
// (DETAIL_QUERY's): the lanes App's newest pin names it and is unedited.
export function pinned(comments, bot, head) {
  const pin = (comments ?? [])
    .filter((c) => c?.author?.__typename === "Bot" && c.author.login === bot && PIN_RE.test(String(c.body ?? "").split("\n", 1)[0].replace(/\r$/, "")))
    .sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)))
    .at(-1);
  return pin !== undefined && !pin.lastEditedAt && PIN_RE.exec(String(pin.body).split("\n", 1)[0].replace(/\r$/, ""))[1] === head;
}

// The lanes App's newest comment in `comments` (DETAIL_QUERY's) whose first
// or second line is `marker`, the refusal comment's by default.
function priorRefusal(comments, bot, marker = REFUSAL_MARKER) {
  return (comments ?? [])
    .filter((c) => c?.author?.__typename === "Bot" && c.author.login === bot && String(c.body ?? "").split("\n", 2).map((line) => line.replace(/\r$/, "")).includes(marker))
    .sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)))
    .at(-1);
}

// The comment and label write for a refusal `clears` (verifyClears, or
// `person` for a hold path or a cost hold) with `reason` at `pull`'s head:
// the comment first, so a label never stands unexplained, and the label only
// when this write made the comment a person's, so a label a person removed
// stays off until the reason or the head changes. Returns what it wrote, or
// null when the comment already says this.
export function refusalWrites(pull, comments, { clears, reason, comment }, { bot, label, now = Date.now() }) {
  // The gate's own marked comment (the queue-ejection one): edited in place,
  // with no label, as babysit_merge.upsert_marker_comment writes it.
  if (typeof comment === "string") {
    const marked = priorRefusal(comments, bot, comment.split("\n", 1)[0]);
    return marked?.body === comment ? null : { body: comment, commentId: marked?.databaseId ?? null, label: null };
  }
  const prior = priorRefusal(comments, bot);
  const since = sinceAt(prior?.body, pull.headRefOid) ?? new Date(now).toISOString();
  const lane = refusalBody(false, reason, pull.headRefOid, label, since);
  const person = refusalBody(true, reason, pull.headRefOid, label);
  const body = clears === "person" ? person : lane;
  // A person's comment already standing while the label is off (a pull
  // request carrying it never gets here: holdReason holds it): the label
  // goes back on unless a person removed it after the comment last changed,
  // which the caller reads from the timeline (`liftedSince`).
  if (prior?.body === body) {
    return body === person ? { body: null, commentId: prior.databaseId ?? null, label, liftedSince: String(prior.updatedAt ?? prior.createdAt) } : null;
  }
  // An escalation to a person posts a new comment: an edit notifies no one
  // and keeps the old date, so the label would stand unexplained.
  return body === person ? { body, commentId: null, label } : { body, commentId: prior?.databaseId ?? null, label: null };
}

// The commit status context the status job posts (pr-merge.yml
// unarmed-status), and the step output enable-auto-merge hands it.
export const UNARMED_CONTEXT = "pr-merge/unarmed";
export const UNARMED_OUTPUT = "unarmed-statuses";
// GitHub's limit on a status description.
const STATUS_DESCRIPTION_CHARS = 140;
// merge.risk-escalation-minutes' default (babysit_merge_policy.RISK_ESCALATION_MINUTES).
export const RISK_ESCALATION_MINUTES = 60;

// The failing `pr-merge/unarmed` status for a refusal the lanes clear
// (`clears` lane) whose comment has stood unchanged at the head for
// `minutes`: the next scheduled runs judge it again until then, and past it
// the hold shows as a failing status on the head, never a label (owner rule
// 2026-10-26). Null while it has stood less, and for any other refusal.
export function unarmedStatus(pull, comments, { clears, reason, comment }, { bot, now, minutes }) {
  if (clears !== "lane") {
    return null;
  }
  // The gate's own marked comment is timed from its last change; the lane
  // comment from the first lane refusal at the head (LANE_SINCE).
  const marked = typeof comment === "string" ? priorRefusal(comments, bot, comment.split("\n", 1)[0]) : null;
  const began =
    typeof comment === "string" ? (marked?.body === comment ? (marked.updatedAt ?? marked.createdAt) : undefined) : sinceAt(priorRefusal(comments, bot)?.body, pull.headRefOid);
  if (!(now - Date.parse(String(began)) >= minutes * 60_000)) {
    return null;
  }
  return { sha: pull.headRefOid, state: "failure", description: Array.from(String(reason).replaceAll(/\s+/g, " ")).slice(0, STATUS_DESCRIPTION_CHARS).join("") };
}

// The newest label removals on a pull request, for refusalWrites' lift check.
export const UNLABELED_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      timelineItems(itemTypes: [UNLABELED_EVENT], last: 100) { totalCount nodes { ... on UnlabeledEvent { createdAt actor { __typename login } label { name } } } }
    }
  }
}`;

// Whether a person removed `label` at or after `since`, from UNLABELED_QUERY's
// timeline; a timeline not read whole counts as removed, so an unknown never
// puts back a label a person may have taken off.
export function liftedByPerson(timeline, label, since) {
  if (!Array.isArray(timeline?.nodes) || !(timeline.totalCount <= timeline.nodes.length)) {
    return true;
  }
  return timeline.nodes.some(
    (event) =>
      event?.actor?.__typename === "User" &&
      String(event?.label?.name).toLowerCase() === String(label).toLowerCase() &&
      Date.parse(String(event?.createdAt)) >= Date.parse(since),
  );
}

// A reader child's exit when babysit_gh's rate guard stopped it
// (RATE_LIMIT_EXIT). Its stop is in the job's stop file, which this process's
// latch read before the child wrote it and takes in again (reload) on this exit.
export const READER_RATE_LIMIT_EXIT = 75;
const GUARD_ERROR = "::error title=GitHub rate limit::";

// A reader stopped on a rate limit; `line` is its guard's ::error.
export class ReaderRateLimited extends Error {
  constructor(what, stderr) {
    const line = String(stderr ?? "")
      .split("\n")
      .find((text) => text.startsWith(GUARD_ERROR));
    super(`${what} stopped on a GitHub rate limit: ${line ? line.slice(GUARD_ERROR.length) : `it exited ${READER_RATE_LIMIT_EXIT}`}`);
    this.name = "ReaderRateLimited";
  }
}

// The `babysit-gh-calls` line a babysit script prints on stderr at exit
// (babysit_gh.py gh_call_summary): its gh invocations in all, those under
// the Actions token (`override`, the job's GITHUB_TOKEN), and those paginated,
// each of which made one request per page. Null when there is no such line.
export const GH_CALLS_PREFIX = "babysit-gh-calls ";
export function ghCalls(stderr) {
  const line = String(stderr ?? "")
    .split("\n")
    .map((text) => text.replace(/\r$/, ""))
    .findLast((text) => text.startsWith(GH_CALLS_PREFIX));
  if (line === undefined) {
    return null;
  }
  let payload;
  try {
    payload = JSON.parse(line.slice(GH_CALLS_PREFIX.length));
  } catch {
    return null;
  }
  const calls = payload?.calls;
  if (!Number.isSafeInteger(payload?.total) || calls === null || typeof calls !== "object") {
    return null;
  }
  const sum = (match) => Object.entries(calls).reduce((n, [kind, count]) => n + (match(kind) && Number.isSafeInteger(count) ? count : 0), 0);
  return { total: payload.total, githubToken: sum((kind) => kind.startsWith("override ")), paginated: sum((kind) => kind.endsWith("+paginate")) };
}

// One pull request's reader cost, as logged and summarized; `cached` (a
// read with answers files) is whether a kept answer served it.
export const costLine = ({ number, calls, ms, cached }) =>
  `#${number} ${calls === null ? "calls=unknown" : `calls=${calls.total} github-token=${calls.githubToken} paginated=${calls.paginated}`} ms=${ms}${cached === undefined ? "" : ` cached=${cached ? 1 : 0}`}`;

// The reader's `cache` object as one greppable line: whether the key matched
// a kept refusal, what was kept and read, and whether the two decide alike
// (`agree` is n/a on a miss). Null for an answer without one.
export const VERIFY_CACHE_PREFIX = "verify-cache ";
export function cacheLine(number, cache) {
  const word = (value) => (typeof value === "string" && /^[a-z:-]+$/.test(value) ? value : "?");
  if (cache === null || typeof cache !== "object") {
    return null;
  }
  return `${VERIFY_CACHE_PREFIX}${word(cache.mode)}: #${number} key=${word(cache.key)} stored=${word(cache.stored)} fresh=${word(cache.fresh)} agree=${cache.agree === "n/a" ? "n/a" : word(cache.agree)}`;
}

// merge.verify-cache as the run applies it: `serve` only when it says so.
export const cacheMode = (env) => (env.VERIFY_CACHE === "serve" ? "serve" : "shadow");

// The gate's own reader, one process per pull request; the run shares its
// artifact listing, head-ref map and run cache through the BABYSIT_* files.
// `--shared-listing`: the first read's listing serves the whole run, an allow
// on it included, since ci-status's merge-queue step runs this reader again
// at the head it merges (merge-holds.mjs evidenceHold).
// Each read's cost goes to the log and to `verify.costs`.
// With VERIFY_ANSWERS_OUT set, each read also keeps its answer for the next
// run and compares it with the one the last run kept (VERIFY_ANSWERS_IN): a
// kept refusal is served (`serve`) only to a pull request not armed, which is
// always read in full, and never on `fresh`; `cacheOnly` reads only a kept
// one, returning no `refusal` on a miss.
export function pythonVerify(env, { spawn = spawnSync, clock = Date.now } = {}) {
  // `rung`: the lane room's effective rung, which the gate scores at.
  const verify = async ({ number, headRefOid: head, baseRefOid: base, autoMergeRequest }, rung, { fresh = false, cacheOnly = false } = {}) => {
    if (!SHA.test(String(base))) {
      throw new Error("its base commit is not a commit SHA");
    }
    // --base-sha: the gate's FAIL cap, the lower of the base's and main's.
    const args = [env.VERIFY_EVIDENCE_SCRIPT || VERIFY_SCRIPT, "evidence", "--lane-link", "--lane-reviews", "--lane-queue", "--shared-listing", "--repo", env.GITHUB_REPOSITORY, "--base-sha", base];
    if (typeof rung === "string") {
      args.push("--rung", rung);
    }
    const answers = Boolean(env.VERIFY_ANSWERS_OUT);
    if (answers) {
      const serve = cacheMode(env) === "serve" && autoMergeRequest == null && !fresh;
      args.push("--answers-out", env.VERIFY_ANSWERS_OUT, "--answers-mode", serve ? "serve" : "shadow");
      if (env.VERIFY_ANSWERS_IN) {
        args.push("--answers-in", env.VERIFY_ANSWERS_IN);
      }
      if (cacheOnly && serve) {
        args.push("--answers-only");
      }
    }
    const started = clock();
    const timeout = args.includes("--answers-only") ? CACHE_ONLY_TIMEOUT_MS : VERIFY_TIMEOUT_MS;
    const done = spawn("python3", [...args, String(number), head], { encoding: "utf8", env, timeout });
    const cost = { number, calls: ghCalls(done.stderr), ms: clock() - started };
    let evidence;
    if (done.status === 0) {
      try {
        evidence = JSON.parse(String(done.stdout).trim().split("\n").at(-1));
      } catch (error) {
        evidence = error;
      }
    }
    if (answers) {
      cost.cached = evidence?.cached === true;
    }
    verify.costs.push(cost);
    console.log(`enable-auto-merge: ${costLine(cost)}`);
    const line = cacheLine(number, evidence?.cache);
    if (line !== null) {
      console.log(`enable-auto-merge: ${line}`);
    }
    if (done.status === READER_RATE_LIMIT_EXIT) {
      throw new ReaderRateLimited(`#${number}'s verifier read`, done.stderr);
    }
    if (done.status !== 0) {
      const said = String(done.stderr ?? "")
        .trim()
        .split("\n")
        .filter((text) => !text.startsWith(GH_CALLS_PREFIX))
        .at(-1);
      throw new Error(`babysit_verify_evidence.py exited ${done.status ?? done.signal}: ${said ?? ""}`);
    }
    if (evidence instanceof Error) {
      throw evidence;
    }
    return evidence;
  };
  verify.costs = [];
  return verify;
}

// The gate's run-level answer for its lane (babysit_verify_evidence.py
// `lane-room`), read with the reader's Actions token when it has one, as the
// merge job reads the post-merge check, so the reads stay off the lane App's
// quota.
export function pythonRoom(env, spawn = spawnSync) {
  return async () => {
    const args = [env.VERIFY_EVIDENCE_SCRIPT || VERIFY_SCRIPT, "lane-room", "--repo", env.GITHUB_REPOSITORY, "--postmerge-result", env.POSTMERGE_RESULT ?? ""];
    if (env.RUNG_CAP !== undefined) {
      args.push("--rung-cap", env.RUNG_CAP);
    }
    const token = env.BABYSIT_VERIFY_GH_TOKEN;
    const roomEnv = token ? { ...env, GH_TOKEN: token, API_BUDGET_TOKEN: "github-token" } : env;
    const done = spawn("python3", args, { encoding: "utf8", env: roomEnv, timeout: LANE_ROOM_TIMEOUT_MS });
    if (done.status === READER_RATE_LIMIT_EXIT) {
      throw new ReaderRateLimited("the lane-room read", done.stderr);
    }
    if (done.status !== 0) {
      throw new Error(`babysit_verify_evidence.py lane-room exited ${done.status ?? done.signal}: ${String(done.stderr ?? "").trim().split("\n").at(-1)}`);
    }
    return JSON.parse(String(done.stdout).trim().split("\n").at(-1));
  };
}

// `lane-room`'s answer as the run applies it, or an unreadable one when it is
// not of that shape: { refusal, unreadable, count, cap, queued }.
export function readRoom(answer) {
  const text = (value) => value === null || typeof value === "string";
  const whole = (value, least) => Number.isSafeInteger(value) && value >= least;
  if (
    answer === null ||
    typeof answer !== "object" ||
    !text(answer.refusal) ||
    !text(answer.unreadable) ||
    !whole(answer.count, 0) ||
    !whole(answer.cap, 1) ||
    !Array.isArray(answer.queued) ||
    !answer.queued.every((number) => whole(number, 1)) ||
    typeof answer.rung !== "string"
  ) {
    return { refusal: null, unreadable: "its answer is not lane-room's", count: 0, cap: 1, queued: [], rung: "off" };
  }
  return answer;
}

// The runs that read the verifier verdict and so may arm: the schedule, and a
// hand-started run, which a person starts to retry a pull request that looks
// stuck.
export const READER_EVENTS = Object.freeze(["schedule", "workflow_dispatch"]);
// The reader's per pull request limit, and when the run stops starting one:
// the room read (at most LANE_ROOM_TIMEOUT_MS) comes first, then a read
// started at the budget ends by VERIFY_BUDGET_MS + VERIFY_TIMEOUT_MS, 17
// minutes in all, inside the step's 18 (pr-merge.yml), so no read is cut off
// and the rest of the pull requests are left for the next run (rotated).
export const VERIFY_TIMEOUT_MS = 4 * 60_000;
// Longer than a verifier read: the room may run a full post-merge check. A
// timeout still reads as unreadable, which holds the lane.
export const LANE_ROOM_TIMEOUT_MS = 8 * 60_000;
export const VERIFY_BUDGET_MS = 5 * 60_000;
// Under merge.verify-cache serve, how long past VERIFY_BUDGET_MS a read that
// only looks up a kept refusal may start, and its own limit: the last ends
// well before the last full read's VERIFY_TIMEOUT_MS would.
export const CACHE_ONLY_WINDOW_MS = 60_000;
export const CACHE_ONLY_TIMEOUT_MS = 30_000;

// `pulls` started at an offset that moves with the run number, so a run
// that reaches VERIFY_BUDGET_MS leaves different pull requests for the next
// one rather than always the same.
export function rotated(pulls, runNumber) {
  const start = Number.isSafeInteger(runNumber) && pulls.length > 0 ? ((runNumber % pulls.length) + pulls.length) % pulls.length : 0;
  return [...pulls.slice(start), ...pulls.slice(0, start)];
}

// What to do with one listed pull request: { action: arm | disarm | none, reason }.
// `detail` is its discussion; undefined means not read yet, and an arm or a
// keep then waits on it (action `read`). Its `verify` is the gate's verifier
// evidence; absent, an arm or a keep waits on it (action `verify`).
export function decide(pull, { bot, humanGated, holdPaths = null }, detail) {
  if (pull.author?.__typename !== "Bot" || pull.author.login !== bot) {
    return { action: "none", reason: "not the lanes App's" };
  }
  const armed = pull.autoMergeRequest != null;
  const held =
    pull.isDraft !== false
      ? "it is a draft"
      : pull.isCrossRepository !== false
        ? "it is from another repository"
        : !SHA.test(String(pull.headRefOid))
          ? "its head is not a commit SHA"
          : holdReason(pull, humanGated);
  // The lane's hold line gets the comment and label once a reader run has
  // read the discussion, so the note finds the comment it wrote before; an
  // armed one is disarmed at once and noted on the next reader run.
  if (held === LANE_HOLD_REASON && !armed && detail !== null) {
    return detail === undefined ? { action: "read", reason: "its discussion is not read yet" } : { action: "none", reason: held, clears: "person" };
  }
  if (held !== null) {
    return { action: armed ? "disarm" : "none", reason: held };
  }
  if (detail === undefined) {
    return { action: "read", reason: "its discussion is not read yet" };
  }
  if (detail === null) {
    return { action: "none", reason: "its discussion did not read" };
  }
  // An unread config labels nothing: the next run reads it again.
  if (holdPaths === null) {
    return { action: armed ? "disarm" : "none", reason: "the hold paths could not be read" };
  }
  if (detail.filesCapped === true) {
    return { action: armed ? "disarm" : "none", reason: FILES_CAPPED_REASON, clears: "person" };
  }
  // A hold path a person clears; a listing or check that could not run is
  // a lane's, which the next run reads again.
  const pathHeld = pathHoldKind(detail.files, holdPaths);
  if (pathHeld !== null) {
    return { action: armed ? "disarm" : "none", reason: pathHeld.reason, clears: pathHeld.kind === "hold-path" ? "person" : "lane" };
  }
  const costHeld = costHold(detail.files, detail.costDecision);
  if (costHeld !== null) {
    return { action: armed ? "disarm" : "none", reason: costHeld, clears: "person" };
  }
  // A hold a person set, read whole: `withdraw` marks a decided outcome,
  // whose run may withdraw a lane's failing status.
  const vetoed = discussionHold(detail);
  if (vetoed !== null) {
    return { action: armed ? "disarm" : "none", reason: vetoed, withdraw: true };
  }
  if (!armed && detail.timelineItems?.nodes?.at(-1)?.actor?.__typename === "User") {
    return { action: "none", reason: "a person turned its auto-merge off", withdraw: true };
  }
  if (!("verify" in detail)) {
    return { action: "verify", reason: "its verifier verdict is not read yet" };
  }
  const unverified = verifyHold(detail.verify, pull.headRefOid);
  if (unverified !== null) {
    const clears = verifyClears(detail.verify, pull.headRefOid);
    return { action: armed ? "disarm" : "none", reason: unverified, ...(clears ? { clears } : {}) };
  }
  // GitHub drops the arm on an ejection, so only the lane's own arm is refused.
  const ejected = armed ? null : ejectionHold(detail.verify);
  if (ejected !== null) {
    // A push resets the count: the lanes clear it, with the gate's comment.
    return { action: "none", reason: ejected.reason, ...(ejected.comment ? { clears: "lane", comment: ejected.comment } : {}) };
  }
  // A kept answer stands only for a refusal (babysit_verify_evidence.py
  // answer_cacheable): one that holds nothing arms and keeps nothing, and is
  // read again in full.
  if (detail.verify?.cached === true) {
    return { action: "verify", reason: "its kept verifier answer holds nothing, so it is read in full" };
  }
  return armed ? { action: "none", reason: "already armed" } : { action: "arm", reason: "no hold" };
}

async function listPulls(github, owner, name) {
  const pulls = [];
  let after = null;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const data = (await github("POST", "/graphql", { query: PULLS_QUERY, variables: { owner, name, after } }))?.data;
    const connection = data?.repository?.pullRequests;
    if (!Array.isArray(connection?.nodes)) {
      throw new Error("the open pull request listing did not read");
    }
    pulls.push(...connection.nodes);
    if (!connection.pageInfo?.hasNextPage) {
      return pulls;
    }
    after = connection.pageInfo.endCursor;
  }
  throw new Error(`more than ${MAX_PAGES * 100} open pull requests into main`);
}

export async function main({ env = process.env, github, verify, room, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)), random, latch, now = Date.now } = {}) {
  try {
    const repo = REPO.exec(env.GITHUB_REPOSITORY ?? "");
    if (!repo) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("enable-auto-merge: the lanes kill switch stops this run; nothing read or armed");
      return 0;
    }
    const slug = BOT_LOGIN.exec(env.LANES_BOT_LOGIN ?? "")?.[1];
    if (slug === undefined) {
      throw new Error("LANES_BOT_LOGIN is not an App bot login");
    }
    const write = env.REPORT_ONLY === "false";
    const minutes = /^[0-9]+$/.test(env.RISK_ESCALATION_MINUTES ?? "") ? Number(env.RISK_ESCALATION_MINUTES) : RISK_ESCALATION_MINUTES;
    // The pr-merge/unarmed statuses for the status job (UNARMED_OUTPUT).
    const statuses = [];
    const humanGated = humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/.work-item-tracker.json");
    const holdPaths = readHoldPaths(env.RESOLVED_CONFIG ?? "");
    // The newest answer's rate limit and body, for an arm GitHub refuses.
    let answer = null;
    const onResponse = (response) => {
      answer = { limited: response.headers.get("x-ratelimit-remaining") === "0" || response.headers.has("retry-after"), text: response.clone().text().catch(() => "") };
    };
    latch ??= rateLimitLatch;
    github = withRetry(github ?? createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, onResponse, latch }), { sleep, random });
    // A reader child that stops on a rate limit writes its stop to the job's
    // stop file; set from then on. Its stop holds every lanes App pull request
    // as an unread room does, so an armed one is disarmed, unless the disarm's
    // own pool (GraphQL) is stopped too: then it stays armed, named in an
    // error, and the run fails.
    let stopped = null;
    const disarmStop = () => (stopped === null ? null : latch.until(`${env.GITHUB_API_URL || "https://api.github.com"}/graphql`));
    verify ??= pythonVerify(env);
    const reads = READER_EVENTS.includes(env.EVENT_NAME);
    const serve = cacheMode(env) === "serve";
    const pulls = await listPulls(github, repo[1], repo[2]);
    const lanes = (pull) => pull.author?.__typename === "Bot" && pull.author.login === slug;
    // Only a reader run arms, so only it reads the room.
    let lane = null;
    if (reads) {
      try {
        lane = readRoom(await (room ?? pythonRoom(env))());
      } catch (error) {
        if (error instanceof ReaderRateLimited) {
          stopped = error;
          latch.reload?.();
        }
        lane = readRoom(null);
        lane.unreadable = stopped === null ? describe(error) : stopped.message;
      }
      console.log(`enable-auto-merge: lane room: ${escapeCommand(JSON.stringify(lane))}`);
    }
    // After the room read, so the verdict reads keep their whole budget.
    const deadline = now() + VERIFY_BUDGET_MS;
    // Merges in flight: the gate's count, plus each armed lanes App pull
    // request the queue has not taken yet, which GitHub enqueues on its own.
    let inFlight = lane === null ? 0 : lane.count + pulls.filter((pull) => lanes(pull) && pull.autoMergeRequest != null && !lane.queued.includes(pull.number)).length;
    // Why the room keeps `pull` from arming, with `disarm` when it also turns
    // an armed one off; null when it has room.
    // An unknown room holds as a refusal does: unknown holds.
    let laneHeld =
      lane?.refusal != null ? `pr-merge's gate holds its lane off (${lane.refusal})` : lane?.unreadable != null ? `the lane's room could not be read (${lane.unreadable})` : null;
    const roomHold = (pull) => {
      if (lane === null || !lanes(pull)) {
        return null;
      }
      if (laneHeld !== null) {
        return { disarm: true, reason: laneHeld };
      }
      if (pull.autoMergeRequest != null) {
        return null;
      }
      return inFlight >= lane.cap ? { disarm: false, reason: `merge.max-in-flight is ${lane.cap} and ${inFlight} merges are in flight` } : null;
    };
    // Each lane pull request the room's refusal or unread room holds, by
    // what became of it: unarmed (never armed, or disarmed), armed (its
    // disarm failed, so the hold is not enforced) or report-only (a disarm
    // would have run).
    const roomHeld = new Map();
    let failed = 0;
    let arms = 0;
    let networkArms = 0;
    let unexplainedArms = 0;
    const skippedArms = [];
    if (holdPaths === null) {
      console.log("::warning title=enable-auto-merge::the resolved config's hold paths did not read, so nothing is armed this run; the next run reads them again");
    }
    // A reader run's per pull request refusal (the lane's hold line, a hold
    // path or cost hold, or the gate's verdict or risk score) goes on the
    // pull request itself:
    // under merge.lane-prs native the gate never lists it, so a log line
    // would be all anyone saw.
    const note = async (pull, detail, refusal) => {
      if (!reads || stopped !== null || refusal.clears === undefined) {
        return;
      }
      const status = unarmedStatus(pull, detail?.comments?.nodes, refusal, { bot: slug, now: now(), minutes });
      if (status !== null && write) {
        statuses.push(status);
      }
      const writes = refusalWrites(pull, detail?.comments?.nodes, refusal, { bot: slug, label: humanGated, now: now() });
      // A kept answer's refusal is the one already noted: a changed reason
      // is written, an unchanged one puts back no label.
      if (refusal.cached === true && writes?.body === null) {
        return;
      }
      // A lane's failing status withdrawn once the refusal is a person's:
      // the status job writes it only over a status already there.
      if (write && writes?.label && writes.commentId === null && writes.body !== null) {
        statuses.push({ sha: pull.headRefOid, state: "success", description: `a person clears this hold: ${humanGated}` });
      }
      if (writes === null) {
        return;
      }
      if (!write) {
        console.log(`enable-auto-merge: #${pull.number} would note its refusal (report-only)${writes.label ? `, labeled ${writes.label}` : ""}`);
        return;
      }
      const base = `/repos/${repo[0]}/issues`;
      try {
        if (writes.body === null) {
          const variables = { owner: repo[1], name: repo[2], number: pull.number };
          const timeline = (await github("POST", "/graphql", { query: UNLABELED_QUERY, variables }))?.data?.repository?.pullRequest?.timelineItems;
          if (liftedByPerson(timeline, writes.label, writes.liftedSince)) {
            console.log(`enable-auto-merge: #${pull.number} left unlabeled: a person removed ${escapeCommand(writes.label)} after its refusal comment, or the timeline did not read whole`);
            return;
          }
          await github("POST", `${base}/${pull.number}/labels`, { labels: [writes.label] });
          console.log(`enable-auto-merge: #${pull.number} labeled ${writes.label} again: its refusal comment stands and no person removed the label`);
          return;
        }
        await (writes.commentId === null
          ? github("POST", `${base}/${pull.number}/comments`, { body: writes.body })
          : github("PATCH", `${base}/comments/${writes.commentId}`, { body: writes.body }));
        if (writes.label) {
          await github("POST", `${base}/${pull.number}/labels`, { labels: [writes.label] });
        }
        console.log(`enable-auto-merge: #${pull.number} refusal noted on the pull request${writes.label ? `, labeled ${writes.label}` : ""}`);
      } catch (error) {
        failed += 1;
        console.log(`::error title=enable-auto-merge::#${pull.number} refusal note: ${describe(error)}`);
      }
    };
    for (let pull of rotated(pulls, Number(env.GITHUB_RUN_NUMBER))) {
      if (stopped === null && lanes(pull) && !(pull.labels?.totalCount <= (pull.labels?.nodes?.length ?? 0))) {
        try {
          pull = { ...pull, labels: await allLabels(github, repo[0], pull.number) };
        } catch (error) {
          console.log(`enable-auto-merge: #${pull.number} labels did not read whole: ${describe(error)}`);
        }
      }
      let { action, reason } = decide(pull, { bot: slug, humanGated, holdPaths });
      let clears;
      let comment;
      let withdraw;
      let detail = null;
      let decided = false;
      // Whether the verdict decided on is a kept answer.
      let cached = false;
      // Checked before the reads, so a held lane spends none.
      const held = ["read", "verify", "arm"].includes(action) ? roomHold(pull) : null;
      if (held?.disarm) {
        roomHeld.set(pull.number, pull.autoMergeRequest != null ? "armed" : "unarmed");
      }
      if (held !== null) {
        ({ action, reason } = { action: held.disarm && pull.autoMergeRequest != null ? "disarm" : "none", reason: held.reason });
      }
      if (action === "read" && !reads && pull.autoMergeRequest == null) {
        ({ action, reason } = { action: "none", reason: "only a scheduled or hand-started run arms it, on the gate's verifier verdict" });
      }
      if (action === "read") {
        try {
          const variables = { owner: repo[1], name: repo[2], number: pull.number };
          detail = (await github("POST", "/graphql", { query: DETAIL_QUERY, variables }))?.data?.repository?.pullRequest ?? null;
          if (detail !== null) {
            detail = await wholeDiscussion(github, variables, detail);
            const { paths: files, capped } = await changedFiles(github, `${repo[1]}/${repo[2]}`, pull.number);
            const decision = costHold(files, null) ? await costDecision(github, repo[0], pull.number, pull.body, trustedHumans(env), pull.headRefOid) : null;
            detail = { ...detail, files, filesCapped: capped, costDecision: decision };
          }
        } catch (error) {
          // A read that fails decides nothing and writes nothing.
          detail = null;
          console.log(`enable-auto-merge: #${pull.number} discussion did not read: ${describe(error)}`);
        }
        ({ action, reason, clears, comment, withdraw } = decide(pull, { bot: slug, humanGated, holdPaths }, detail));
      }
      // Past the budget, under serve, an unarmed pull request is answered
      // only from a kept refusal, which reads no more than its key, for
      // CACHE_ONLY_WINDOW_MS.
      const at = now();
      const late = at > deadline;
      const cacheOnly = late && at <= deadline + CACHE_ONLY_WINDOW_MS && serve && pull.autoMergeRequest == null;
      if (action === "verify" && !reads) {
        ({ action, reason } =
          pull.autoMergeRequest != null
            ? { action: "none", reason: "already armed; the next scheduled run checks its verifier verdict" }
            : { action: "none", reason: "only a scheduled or hand-started run arms it, on the gate's verifier verdict" });
      } else if (action === "verify" && late && !cacheOnly) {
        ({ action, reason } = { action: "none", reason: "no time left in this run to read its verifier verdict" });
      } else if (action === "verify") {
        const read = async (options) => {
          try {
            return await verify(pull, lane?.rung, options);
          } catch (error) {
            // No decide and no note, whose writes would follow the stop: this
            // and every later lanes App pull request is held as an unread room.
            if (error instanceof ReaderRateLimited) {
              stopped = error;
              latch.reload?.();
              laneHeld = `the lane's room could not be read (${error.message})`;
              const armed = pull.autoMergeRequest != null;
              roomHeld.set(pull.number, armed ? "armed" : "unarmed");
              ({ action, reason, clears, comment } = { action: armed ? "disarm" : "none", reason: laneHeld, clears: undefined, comment: undefined });
              decided = true;
            } else {
              console.log(`enable-auto-merge: #${pull.number} verifier verdict did not read: ${describe(error)}`);
            }
            return null;
          }
        };
        let evidence = await read(cacheOnly ? { cacheOnly: true } : undefined);
        if (cacheOnly && !decided && evidence?.cached !== true) {
          ({ action, reason } = { action: "none", reason: "no time left in this run to read its verifier verdict" });
          decided = true;
        }
        // A read failing on every run holds every clean lane pull request: say why.
        if (typeof evidence?.queue?.readError === "string") {
          console.log(`::warning title=enable-auto-merge::#${pull.number} its merge-queue ejections could not be read: ${escapeCommand(evidence.queue.readError)}`);
        }
        if (!decided) {
          ({ action, reason, clears, comment, withdraw } = decide(pull, { bot: slug, humanGated, holdPaths }, { ...detail, verify: evidence }));
        }
        // A kept answer that holds nothing: read in full once, never armed on.
        if (!decided && action === "verify") {
          if (now() > deadline) {
            ({ action, reason } = { action: "none", reason: "no time left in this run to read its verifier verdict" });
          } else {
            evidence = await read({ fresh: true });
            if (!decided) {
              ({ action, reason, clears, comment, withdraw } = decide(pull, { bot: slug, humanGated, holdPaths }, { ...detail, verify: evidence }));
            }
          }
        }
        cached = evidence?.cached === true;
      }
      // Only an arm, a disarm or nothing goes on from here.
      if (action === "verify") {
        ({ action, reason, clears, comment, withdraw } = { action: "none", reason: "its verifier verdict is not read yet" });
      }
      // A pull request armed earlier in this run counts toward the cap.
      const full = action === "arm" ? roomHold(pull) : null;
      if (full !== null) {
        ({ action, reason } = { action: "none", reason: full.reason });
      }
      if (action === "arm") {
        inFlight += 1;
      }
      if (action === "none") {
        if (reason !== "not the lanes App's") {
          console.log(`enable-auto-merge: #${pull.number} left: ${escapeCommand(reason)}`);
        }
        // A lane's refusal noted at this head that a decided hold a person
        // set now stands in for (a veto, auto-merge turned off): its failing
        // status is withdrawn, as an arm withdraws it. An outcome that read
        // nothing (no time left, unread hold paths, a verdict that did not
        // read) leaves the status as it is.
        if (reads && write && withdraw === true && sinceAt(priorRefusal(detail?.comments?.nodes, slug)?.body, pull.headRefOid) !== undefined) {
          statuses.push({ sha: pull.headRefOid, state: "success", description: "its lanes refusal no longer stands" });
        }
        await note(pull, detail, { clears, reason, comment, cached });
        continue;
      }
      if (!write) {
        if (roomHeld.get(pull.number) === "armed") {
          roomHeld.set(pull.number, "report-only");
        }
        console.log(`enable-auto-merge: #${pull.number} would ${action} (report-only): ${escapeCommand(reason)}`);
        await note(pull, detail, { clears, reason });
        continue;
      }
      if (action === "arm" && !pinned(detail?.comments?.nodes, slug, pull.headRefOid)) {
        try {
          await github("POST", `/repos/${repo[0]}/issues/${pull.number}/comments`, { body: pinBody(pull.headRefOid) });
          console.log(`enable-auto-merge: #${pull.number} pinned at ${pull.headRefOid}`);
        } catch (error) {
          // No pin, no arm: an immediate enqueue would have no read-back.
          failed += 1;
          console.log(`::error title=enable-auto-merge::#${pull.number} pin, so not armed: ${describe(error)}`);
          continue;
        }
      }
      if (action === "disarm" && disarmStop() !== null) {
        failed += 1;
        console.log(`::error title=enable-auto-merge::#${pull.number} disarm not sent: GitHub's GraphQL rate limit is stopped until ${new Date(disarmStop() * 1000).toISOString()}, so it stays armed`);
        continue;
      }
      try {
        if (action === "arm") {
          arms += 1;
          await github("POST", "/graphql", { query: ARM_MUTATION, variables: { id: pull.id, head: pull.headRefOid } });
          console.log(`enable-auto-merge: #${pull.number} armed at ${pull.headRefOid}`);
          statuses.push({ sha: pull.headRefOid, state: "success", description: "armed for native auto-merge" });
        } else {
          await github("POST", "/graphql", { query: DISARM_MUTATION, variables: { id: pull.id } });
          if (roomHeld.has(pull.number)) {
            roomHeld.set(pull.number, "unarmed");
          }
          console.log(`enable-auto-merge: #${pull.number} disarmed: ${escapeCommand(reason)}`);
        }
      } catch (error) {
        const body = action === "arm" && answer !== null ? await answerBody(answer.text) : { said: "", runWide: false, typed: false };
        if (action === "arm" && refused(error, answer?.limited || body.runWide)) {
          // GitHub said no on the first send, so nothing is in flight. After a
          // resend an earlier send may have landed, so its slot stays counted.
          if ((error.attempts ?? 1) === 1) {
            inFlight -= 1;
          }
          // A 404, or GraphQL errors that name no type, may be the run's own
          // (a wrong API URL) rather than this pull request's.
          if (error.status === 404 || (error.status === 200 && !body.typed)) {
            unexplainedArms += 1;
          }
          skippedArms.push(`#${pull.number}`);
          console.log(`::warning title=enable-auto-merge::#${pull.number} arm refused, skipped this run: ${describe(body.said ? new Error(`${error.message}: ${body.said}`) : error)}`);
          continue;
        }
        // Its slot stays counted: a lost answer may hide an arm that landed,
        // and the next run counts it from autoMergeRequest.
        if (action === "arm" && transient(error)) {
          skippedArms.push(`#${pull.number}`);
          networkArms += 1;
          console.log(`::warning title=enable-auto-merge::#${pull.number} arm failed on the network after its resends, skipped this run: ${describe(error)}`);
          continue;
        }
        failed += 1;
        console.log(`::error title=enable-auto-merge::#${pull.number} ${action}: ${describe(error)}`);
        // Still armed: a note saying it is unarmed would be false.
        continue;
      }
      if (action === "disarm") {
        await note(pull, detail, { clears, reason });
      }
    }
    // One warning (and an error while a disarm failed) and their summary
    // lines per run, not a comment per pull request: the room is read again
    // every scheduled run.
    const held = (state) => [...roomHeld].filter(([, outcome]) => outcome === state).map(([number]) => `#${number}`).join(", ");
    const lines = [];
    const warned = [
      ["left unarmed", held("unarmed")],
      ["report-only, a disarm would have run", held("report-only")],
    ].filter(([, numbers]) => numbers);
    if (warned.length > 0) {
      lines.push(["warning", escapeCommand(`${laneHeld}; ${warned.map(([what, numbers]) => `${what}: ${numbers}`).join("; ")}`)]);
    }
    // No arm landed. Every arm failing on the network, or two or more arms all
    // failing without a reason of their own (network, 404, untyped GraphQL
    // errors), is the run's; refusals that name their reason are each pull
    // request's.
    const outage = arms > 0 && skippedArms.length === arms && (networkArms === arms || (arms > 1 && networkArms + unexplainedArms === arms));
    if (outage) {
      failed += 1;
    }
    if (arms > 0 && skippedArms.length === arms) {
      lines.push([outage ? "error" : "warning", `every arm this run failed: ${skippedArms.join(", ")}`]);
    }
    if (held("armed")) {
      lines.push(["error", escapeCommand(`${laneHeld}; still armed, its disarm failed, so the hold is not enforced: ${held("armed")}`)]);
    }
    for (const [level, text] of lines) {
      console.log(`::${level} title=enable-auto-merge::${text}`);
    }
    if (statuses.length > 0 && env.GITHUB_OUTPUT) {
      try {
        appendFileSync(env.GITHUB_OUTPUT, `${UNARMED_OUTPUT}=${JSON.stringify(statuses)}\n`);
      } catch (error) {
        failed += 1;
        console.log(`::error title=enable-auto-merge::the ${UNARMED_CONTEXT} statuses were not handed on: ${describe(error)}`);
      }
    }
    if (stopped !== null) {
      failed += 1;
      console.log(`${GUARD_ERROR}enable-auto-merge: ${escapeCommand(stopped.message)}; no pull request is read, noted or armed after it this run, and each armed lanes App pull request is disarmed`);
    }
    // Each verifier read's cost too, so a run's spend reads per pull request.
    const summary = [...lines.map(([, text]) => text), ...(verify.costs ?? []).map(costLine)];
    if (summary.length > 0 && env.GITHUB_STEP_SUMMARY) {
      try {
        appendFileSync(env.GITHUB_STEP_SUMMARY, summary.map((text) => `enable-auto-merge: ${text}\n`).join(""));
      } catch (error) {
        console.log(`enable-auto-merge: the step summary was not written: ${describe(error)}`);
      }
    }
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=enable-auto-merge::${describe(error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
