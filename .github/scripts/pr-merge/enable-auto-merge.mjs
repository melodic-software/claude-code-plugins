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
//   trusted person's approving review of the head, or of an earlier head
//   carried over base merges, lifts it, as ci-status lifts it
//   (merge-holds.pathLifters and liftersOf); it lifts no listing or check
//   that could not run. A config that does not read arms nothing and labels
//   nothing; the next run reads it again.
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
//   read once for the run, and run cache. An event run (a person's
//   unlabel) never arms and reads no verdict: it only disarms on a
//   hold, so a pull request waits up to one scheduled interval to be armed.
//   An arm survives a push to its head (disarming needs contents: write, which
//   the arming lanes App token holds and ci-status's GITHUB_TOKEN lacks), so
//   in the merge queue ci-status checks the pass again at the head it merges
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
// (refusalWrites). A hold path or cost hold is never the only reason named:
// an unarmed one is read by the verifier too, and every reason a person
// clears goes in the one comment, one per line and sorted, so one lift
// answers them all; a run whose verifier read did not come never narrows a
// person's comment that already names its reasons. The
// comment is the record; only a cause a person must clear
// (docs/contracts/loop-lane/README.md#when-work-stops-for-the-owner,
// with cost and trust holds kept: untrusted
// provenance or an untrusted spec, a security finding, a trusted-actor
// widening, a real charge or a listing too long to check, see
// verifyClears; a hold path, a configured denied path
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
// A lane's risk hold that only a clean whole review of the head clears
// (`evidence`'s wholeReviewWanted, babysit_whole_review.wanted, such as a
// `review-path:` hold whose security findings the lanes App resolved) gets
// the request pr-merge's gate makes for its own candidates: under
// merge.lane-prs native the gate never lists a lanes App pull request.
// babysit_whole_review.py `request` applies the gate's caps (once per head,
// MAX_TOGGLES per pull request, one per run through
// BABYSIT_WHOLE_REVIEW_SPENT, the running-jobs and rate-limit floors) and
// answers a record line, which the lane's comment carries from then on; once
// the comment is written, `toggle` drafts the pull request and marks it
// ready again, and the security lane reviews the whole head on
// ready_for_review. The toggle restarts every lane that runs on
// ready_for_review, not only the security review (both review lanes, and any
// other workflow on that event). Just before its first write, `toggle` reads
// the pull request again and refuses one already a draft (a person's draft,
// which a mark-ready would undo), one with a merge-hold label or a body hold,
// and one whose state did not read. A draft such a toggle left, carrying no
// hold (holdReason), is marked ready on the next reader run (`recover`).
// Arming passes the head just read as expectedHeadOid, so a push in between
// fails the arm rather than arming a head nobody read. Before it arms, the run
// posts the gate's pin comment for that head (pinBody) unless the lanes App's
// newest pin already names it unedited, and a pin that fails to post leaves
// the pull request unarmed: an arm GitHub enqueues at once records no
// auto-merge event, so the post-merge check reads that head back against the
// pin. An armed pull request
// that fails any rule is disarmed. Each request opens its own connection, and
// a read or write that fails on the network is sent up to twice more
// (withRetry). A resent arm or disarm that errors is read back once, and
// counts as done when the pull request already holds the target state. One
// whose arm or disarm still fails is left as it was, named with its cause,
// and the run goes on to the rest, then exits 1. While
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
//                        decision and the approvers who lift a hold path (default .base/.github/standards/trusted-actors/trusted-actors.json)
//   EVENT_NAME           the run's event; only READER_EVENTS read verdicts and arm
//   EVENT_PR             a pull_request_target run's pull request number, the only one it handles
//   EAM_SKIP_IN, EAM_SKIP_OUT  the skip records the last reader run kept, and
//                        the file this one keeps (SKIPPABLE); no OUT, no skip
//   SKIP_MAX_MINUTES, SKIP_MAX_SKIPS  merge.skip-unchanged's limits; 0 in either: no skip
//   POSTMERGE_RESULT     this run's babysit_postmerge.py report, for lane-room
//   POSTMERGE_CODE_SHA   the commit whose code ran that report's check (empty
//                        when unknown: lane-room reads the report again)
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
//   BABYSIT_WHOLE_REVIEW_SPENT  the file whose creation claims the run's one
//                        whole-review request (babysit_whole_review.limits)
//   VERIFY_CACHE         merge.verify-cache: `serve` serves a kept refusal to
//                        an unarmed pull request; anything else is `shadow`,
//                        which reads in full and logs how a kept answer
//                        compares (VERIFY_CACHE_PREFIX)
//   GITHUB_API_URL
//
// A reader run takes the human-gated label off a pull request whose newest
// refusal at its head names only hold paths once a trusted person approved
// that head (approvalLift), which re-runs ci-status there, but only while the
// label stands for that refusal alone (liftBlocker): never a label a person
// set or one another escalation or hold stands behind. Every other person's
// refusal keeps waiting for a person to remove the label.

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, errorLabel, GitHubError, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { humanGatedLabelFrom, quote } from "../pr-unblock/address-feedback.mjs";
import {
  lines as bodyLines,
  foreignMarker,
  HOLD_LINE,
  isApp,
  labelHistory,
  laneHold,
  openReviewHold,
  openCredentialHold,
  openSignedCommitsHold,
  PAIRED_MS,
  personSince,
  reviewEntries,
  sinceParam,
  spoken,
} from "../pr-unblock/gate-source.mjs";
import { readHoldPaths } from "../work-resolve-issue/report-outcome.mjs";
import {
  BODY_HOLD,
  costDecision,
  costHold,
  HUMAN_MERGE_HOLD,
  humansOf,
  LANE_HOLD,
  liftersOf,
  OUTSIDE_ACTOR_LABEL,
  pathHoldKind,
  pathLifters,
  personWrote,
  readPathHolds,
  readStatuses,
  unblockStops,
  vetoers,
} from "./merge-holds.mjs";

export { BODY_HOLD, HUMAN_VETO } from "./merge-holds.mjs";

const REPO = /^([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)$/;
const SHA = /^[0-9a-f]{40}$/;
const BOT_LOGIN = /^([a-z0-9][a-z0-9-]*)\[bot\]$/;
// babysit_merge_policy.MERGE_HOLD_LABELS, plus the human-gated label.
export const HOLD_LABELS = Object.freeze(["do-not-merge", "pr-verify-failed", HUMAN_MERGE_HOLD, OUTSIDE_ACTOR_LABEL]);
// 100 pull requests a page; more than this many open is a listing the run
// stops on rather than one it reads only part of.
const MAX_PAGES = 10;
// Changed files read per pull request, 100 a page; more is a head the run
// does not arm on.
const MAX_FILE_PAGES = 3;
const VERIFY_SCRIPT = ".base/plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py";
const WHOLE_REVIEW_SCRIPT = ".base/plugins/source-control/skills/babysit-prs/scripts/babysit_whole_review.py";

// Into main, by name: the gate reads the default branch live
// (babysit_merge_policy._base_refusal), while this assumes it is main.
export const PULLS_QUERY = `query($owner: String!, $name: String!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(states: OPEN, baseRefName: "main", first: 100, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id number isDraft isCrossRepository headRefOid baseRefOid body updatedAt
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
const REVIEW_FIELDS = "author { __typename login ... on User { databaseId } } state commit { oid } body submittedAt authorAssociation";
const THREAD_COMMENT_FIELDS = "author { __typename login } body createdAt authorAssociation";
const THREAD_FIELDS = `id comments(last: 100) { totalCount nodes { ${THREAD_COMMENT_FIELDS} } }`;
export const DETAIL_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      comments(last: 100) { totalCount nodes { ${COMMENT_FIELDS} } }
      reviews(last: 100) { totalCount nodes { ${REVIEW_FIELDS} } }
      reviewThreads(last: 100) { totalCount nodes { ${THREAD_FIELDS} } }
      timelineItems(itemTypes: [AUTO_MERGE_DISABLED_EVENT], last: 1) { nodes { ... on AutoMergeDisabledEvent { actor { __typename login } } } }
      files(first: 100) { totalCount nodes { path changeType } }
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
// A pull request's auto-merge state, read back once when a resent arm or
// disarm errors (sendSettled).
export const AUTO_MERGE_STATE_QUERY = `query($id: ID!) {
  node(id: $id) { ... on PullRequest { state headRefOid autoMergeRequest { enabledAt } } }
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
// undici puts a whole header value in some messages. With `label`, a
// causeless error's message is followed by its errorLabel, unless the message
// already is that label, and the scrub runs over both.
export function describe(error, { label = false } = {}) {
  const cause = error?.cause;
  const message = String(error?.message ?? error);
  const named = label && errorLabel(error) !== message ? `${message} (${errorLabel(error)})` : message;
  const text = cause ? `${error?.message ?? error} (cause: ${[cause.code, cause.message].filter(Boolean).join(" ")})` : named;
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
// answer that with an error, the run reads the state back once (sendSettled)
// and counts the target reached as a success.
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

// A pull request's label connection without `name` (any case).
const unlabeledAs = (connection, name) => {
  const nodes = (connection?.nodes ?? []).filter((label) => String(label?.name).toLowerCase() !== name.toLowerCase());
  return { totalCount: (connection?.totalCount ?? 0) - ((connection?.nodes?.length ?? 0) - nodes.length), nodes };
};

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

// One DETAIL_QUERY comment or review as a merge-holds item (fromRest's shape).
const itemOf = (item) => ({
  login: item?.author?.login,
  userId: item?.author?.databaseId,
  state: item?.state,
  commitId: item?.commit?.oid,
  isUser: item?.author?.__typename === "User",
  association: item?.authorAssociation,
  at: String(item?.submittedAt ?? item?.createdAt ?? ""),
  body: String(item?.body ?? ""),
});

// The trusted people (`humans`) whose newest deciding review of `head` in
// `detail` approves it, as ci-status reads them (merge-holds.pathLifters).
const headLifters = (detail, humans, head) => pathLifters((detail?.reviews?.nodes ?? []).map(itemOf), humans, head);

// Why the discussion `detail` (DETAIL_QUERY's pullRequest) holds it, or null.
export function discussionHold(detail) {
  const threads = detail?.reviewThreads;
  if (![detail?.comments, detail?.reviews, threads].every(whole) || !threads.nodes.every((thread) => whole(thread?.comments))) {
    return "its comments could not all be read";
  }
  const items = [...detail.comments.nodes, ...detail.reviews.nodes, ...threads.nodes.flatMap((thread) => thread.comments.nodes)].map(itemOf);
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

// The changed paths DETAIL_QUERY's `files` lists, or null when the REST
// listing must be read: a list cut at one page, or a rename or copy, whose
// old path only REST names (previous_filename).
export function listedFiles(files) {
  const nodes = files?.nodes;
  if (!Array.isArray(nodes) || files.totalCount !== nodes.length || nodes.length >= 100) {
    return null;
  }
  return nodes.every((node) => typeof node?.path === "string" && typeof node.changeType === "string" && !["RENAMED", "COPIED"].includes(node.changeType))
    ? nodes.map((node) => node.path)
    : null;
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

// The verifier refusals that never clear for the pull request
// (babysit_verify_evidence.py VERIFY_FINAL): the FAIL cap. decide closes
// such a pull request for a fresh attempt at its issue (pythonClose), never
// adding a person's label. An old pull request's verify:too-old waits for a
// fresh pass at its head instead.
export const VERIFY_FINAL = Object.freeze(["verify:repeated-fail"]);

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
    // A refusal that never clears names the reader's detail (the cap's FAILed
    // heads), so the close log says what closed it.
    const detail = VERIFY_FINAL.includes(evidence.refusal) && typeof evidence.detail === "string" && evidence.detail ? `: ${escapeCommand(evidence.detail)}` : "";
    return `${READER_HOLDS.verdict}${escapeCommand(evidence.refusal)}${detail})`;
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

// Who clears the refusal verifyHold reads in `evidence` at `head`
// (docs/contracts/loop-lane/README.md#when-work-stops-for-the-owner;
// cost and trust holds stay a person's): `person`
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
// refusal the attended queue's escalation marker first (work-items
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

// A person's reasons as one refusal reason: one per line, each once, sorted,
// so the same set always renders the same comment.
export const personReason = (reasons) => [...new Set(reasons.map(String))].sort().join("\n");

// A person's refusal written without the verifier's answer (decide's
// `partial`) ends with this line, so the one reader run that gets the answer
// widens it even with the label on, and none after.
const partialLine = (head) => `<!-- pr-merge-partial head=${head} -->`;
export const isPartial = (body, head) => String(body ?? "").split("\n").at(-1) === partialLine(head);

// The reason lines of a refusal comment `body` at `head` (a person's when
// `person`), each whole and as fenced renders it, when refusalBody renders it
// from them with `since`, `partial` and `records`, or rendered it before
// reasons wrapped (one fence line per reason); else null. A wrapped line's
// continuations start with two spaces, which no fenced line does.
export function refusalReasons(body, person, head, label, { since = null, partial = false, records = [] } = {}) {
  const lines = String(body ?? "").split("\n");
  const open = lines.indexOf("```text");
  const close = lines.indexOf("```", open + 1);
  if (open < 0 || close < 0) {
    return null;
  }
  const raw = lines.slice(open + 1, close);
  const reasons = raw.reduce((out, line) => (line.startsWith("  ") && out.length > 0 ? [...out.slice(0, -1), `${out.at(-1)} ${line.slice(2)}`] : [...out, line]), []);
  if (refusalBody(person, reasons.join("\n"), head, label, since, partial, records) === body) {
    return reasons;
  }
  return renderRefusal(unwrappedFence, person, raw.join("\n"), head, label, since, partial, records) === body ? fenced(raw.join("\n")).split("\n") : null;
}

// The reason lines of a person's refusal comment `body` at `head`, or null
// when it is not one.
const personReasons = (body, head, label) => refusalReasons(body, true, head, label, { partial: isPartial(body, head), records: recordLines(body) });

// A person's refusal at `head` whose every reason is a hold path
// (merge-holds.pathHoldKind's "it changes <path>, a hold path"): the one
// escalation a trusted person's approval of the head lifts, so the lane may
// take its label off. A cost, risk or verifier reason, a label a person set
// with no refusal, or a comment at another head is not one, except that with
// `pathHolds` false a risk reason whose every code is a path hold
// (babysit_risk.is_path_hold: `high-path:<glob>` but `high-path:**`, or
// `review-path:`) is one too.
const HOLD_PATH_LINE = /^it changes .+, a hold path$/;
const PATH_HOLD_CODE = /^(high-path:(?!\*\*$)|review-path:)\S/;
const pathOnlyRisk = (line) =>
  line.startsWith(READER_HOLDS.risk) &&
  line.endsWith(")") &&
  line
    .slice(READER_HOLDS.risk.length, -1)
    .split("; ")
    .every((part) => PATH_HOLD_CODE.test(part.split(": ")[0]));
export function holdPathOnly(body, head, label, pathHolds = true) {
  const reasons = personReasons(body, head, label);
  return reasons !== null && reasons.length > 0 && reasons.every((line) => HOLD_PATH_LINE.test(line) || (pathHolds === false && pathOnlyRisk(line)));
}

// Whether the lane lifts `label` off `pull`: its newest refusal at the head
// names only hold paths, the changed files still hold on nothing but a hold
// path (no cost hold, a listing read whole), and `detail.lifters` holds a
// trusted person whose approval binds the head (merge-holds pathLifters, or
// liftersOf over base merges), or `pathHolds` is false, so no hold path holds.
export function approvalLift(pull, detail, { bot, label, holdPaths, pathHolds = true }) {
  if (!holdPathOnly(priorRefusal(detail?.comments?.nodes, bot)?.body, pull.headRefOid, label, pathHolds)) {
    return false;
  }
  // Off, a risk refusal's path may be one only the gate's floor holds, so a
  // readable listing is enough.
  const listed = pathHolds === false ? Array.isArray(detail.files) : pathHoldKind(detail.files, holdPaths)?.kind === "hold-path";
  if (!Array.isArray(holdPaths) || detail.filesCapped === true || !listed) {
    return false;
  }
  return costHold(detail.files, detail.costDecision) === null && (pathHolds === false || (Array.isArray(detail.lifters) && detail.lifters.length > 0));
}

// Whether `label` stands for enable-auto-merge's refusal alone, so the lane
// may take it off: null when it does, else why it stays. The same label also
// carries holds that live only in the label, so it stays unless all hold:
// - no review lane's hold names the head `head` (or fails to parse);
// - the newest `labeled` event is the lanes App's (`login`, the REST login),
//   and the App's marked comment written last at or before it, within
//   PAIRED_MS, is a person's refusal (pr-merge's escalation and refusal
//   markers);
// - no review-lane or check-signed-commits hold comment stands since a
//   person last removed the label (gate-source's readers, as clear-escalations
//   reads them);
// - no lanes App comment written or edited since the label carries any marker
//   but the refusal's: a pr-unblock escalation adds no label event;
// - no person commented, replied on a review thread, reviewed or labeled
//   since, a trusted approval (`humans`) aside.
// A time that does not parse counts as since, which keeps the label.
const REFUSAL_LINES = (line) => line === ATTEND_QUEUE_MARKER || line === REFUSAL_MARKER || /^<!-- pr-merge-partial head=[0-9a-f]{40} -->$/.test(line);
export function liftBlocker({ timeline, reviewComments = [], reviews = [], label, login, humans, head }) {
  const { labeled, since } = labelHistory(timeline, label);
  // Only a person's removal lifts a hold (liftedByPerson's rule): a bot's
  // unlabel, which the lane then puts back, lifts nothing.
  const lifted = Math.max(
    -Infinity,
    ...timeline
      .filter((item) => item.event === "unlabeled" && item.actor?.type === "User" && String(item.label?.name).toLowerCase() === String(label).toLowerCase())
      .map((item) => Date.parse(item.created_at))
      .filter((time) => time <= since),
  );
  // A review lane's hold on this head keeps it whenever it was written, and
  // one whose marker does not parse keeps it too (gateSource's head check).
  const holdMarkers = timeline.map(laneHold).filter((marker) => marker !== undefined);
  if (holdMarkers.some((marker) => (HOLD_LINE.exec(marker)?.[1] ?? head) === head)) {
    return `a review lane holds head ${head}, or its hold does not parse`;
  }
  if (!isApp(labeled?.actor, login)) {
    return `${label} was last added by ${labeled?.actor?.login ?? "no one on the timeline"}, not the lanes App`;
  }
  const appComments = timeline.filter((item) => item.event === "commented" && isApp(item.user, login));
  const marked = (item) => bodyLines(item.body).filter((line) => line.includes("<!--"));
  const before = appComments
    .map((item) => ({ markers: marked(item), at: Math.max(...[item.created_at, item.updated_at ?? item.created_at].map(Date.parse).filter((time) => time <= since)) }))
    .filter(({ markers, at }) => markers.length > 0 && at > -Infinity)
    .sort((a, b) => a.at - b.at);
  const paired = before.at(-1);
  // The refusal comes within PAIRED_MS before the label (refusalWrites posts
  // the comment, then the label). A label put back under a standing comment
  // with no new one does not pair, so it stays for a person.
  if (paired === undefined || before.filter(({ at }) => at === paired.at).length > 1 || !paired.markers.includes(REFUSAL_MARKER) || !paired.markers.includes(ATTEND_QUEUE_MARKER) || !(since - paired.at <= PAIRED_MS)) {
    return `${label} does not pair with enable-auto-merge's refusal`;
  }
  if (openReviewHold(timeline, lifted) !== undefined) {
    return "a review lane holds it";
  }
  if (openSignedCommitsHold(timeline, lifted) !== undefined) {
    return "check-signed-commits holds it";
  }
  if (openCredentialHold(timeline, lifted) !== undefined) {
    return "pr-verify holds it for a credential";
  }
  const foreign = foreignMarker(appComments, since, REFUSAL_LINES);
  if (foreign !== undefined) {
    return `a lanes App comment since ${label} went on carries another marker: ${foreign.slice(0, 120)}`;
  }
  const approval = (user, state) => String(state).toUpperCase() === "APPROVED" && humans.has(user?.id);
  const entries = [
    ...timeline.filter((item) => !(item.event === "reviewed" && approval(item.user, item.state))).flatMap(spoken),
    ...timeline.filter((item) => item.event === "labeled" || item.event === "unlabeled").map((item) => ({ user: item.actor, at: Date.parse(item.created_at) })),
    ...reviewEntries({ comments: reviewComments, reviews: reviews.filter((review) => !approval(review.user, review.state)) }),
  ];
  const speaker = personSince(entries, since);
  return speaker === undefined ? null : `${speaker.user?.login ?? "an account"} spoke or labeled after ${label} went on`;
}

// liftBlocker over `number`'s timeline, review comments and reviews.
async function liftBlocked(github, repo, number, options) {
  const timeline = await paginate(github, `/repos/${repo}/issues/${number}/timeline`);
  const { labeled, since } = labelHistory(timeline, options.label);
  if (!isApp(labeled?.actor, options.login) || Number.isNaN(since)) {
    return liftBlocker({ timeline, ...options });
  }
  const reviewComments = await paginate(github, `/repos/${repo}/pulls/${number}/comments?since=${sinceParam(since - 1000)}`);
  const reviews = await paginate(github, `/repos/${repo}/pulls/${number}/reviews`);
  return liftBlocker({ timeline, reviewComments, reviews, ...options });
}

// A reason as the comment carried it before reasons wrapped.
const unfolded = (reason) => String(reason).replaceAll(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "?").replaceAll("```", "'''");
// A reason as the comment's fenced block carries it: each line trimmed, its
// whitespace runs one space, so a wrap at a space joins back exactly.
const fenced = (reason) =>
  unfolded(reason)
    .split("\n")
    .map((line) => line.replaceAll(/\s+/g, " ").trim())
    .join("\n");
// The fenced block: each reason line wrapped (address-feedback quote), or one
// fence line per reason as before reasons wrapped.
const wrappedFence = (reason) => quote(fenced(reason).split("\n"), (count) => `Its reasons (${count} lines)`);
const unwrappedFence = (reason) => ["```text", unfolded(reason), "```"].join("\n");

// A whole-review request's record line (babysit_whole_review.py RECORD_RE),
// kept on every rewrite of the refusal comment, a person's included, since it
// holds the once-per-head and per pull request caps.
export const WHOLE_REVIEW_RECORD = /^Whole review requested at head `[0-9a-f]{40}` at \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ: .*$/;
// Only outside the fenced reasons, which quote changed paths verbatim, so a
// path holding a newline plants no record.
export const recordLines = (body) => {
  let fenced = false;
  return String(body ?? "")
    .split("\n")
    .map((line) => line.replace(/\r$/, ""))
    .filter((line) => {
      if (line.startsWith("```")) {
        fenced = !fenced;
        return false;
      }
      return !fenced && WHOLE_REVIEW_RECORD.test(line);
    });
};

// `records`: the comment's whole-review record lines, before its last.
export const refusalBody = (person, reason, head, label, since = null, partial = false, records = []) =>
  renderRefusal(wrappedFence, person, reason, head, label, since, partial, records);

function renderRefusal(fence, person, reason, head, label, since, partial, records) {
  const who = person
    ? `A person must clear this reason, so the pr-merge lane added the \`${label}\` label: fix the reason, then remove the label, and the next scheduled run judges it again.`
    : "The lanes clear this reason on their own; the next scheduled run judges it again.";
  return [
    ...(person ? [ATTEND_QUEUE_MARKER] : []),
    REFUSAL_MARKER,
    `Unattended merge: native auto-merge leaves this pull request unarmed at head \`${head}\`. ${who}`,
    "",
    fence(reason),
    ...(records.length === 0 ? [] : ["", ...records]),
    ...(person || since === null ? [] : [laneSince(head, since)]),
    ...(person && partial ? [partialLine(head)] : []),
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
// A `partial` person's refusal (decide's, without the verifier's answer) that
// the standing person's comment at the head already covers, every reason of
// it there, is that comment: a read that did not come never narrows it.
// `answered`: the verifier's answer came, so the comment carries no partial
// mark even when the answer could not be scored. A label the pull request
// already carries is not written again. The comment keeps the prior one's
// whole-review record lines, plus `record`, a new one.
export function refusalWrites(pull, comments, { clears, reason, comment, partial = false, answered = false, record = null }, { bot, label, now = Date.now() }) {
  // The gate's own marked comment (the queue-ejection one): edited in place,
  // with no label, as babysit_merge.upsert_marker_comment writes it.
  if (typeof comment === "string") {
    const marked = priorRefusal(comments, bot, comment.split("\n", 1)[0]);
    return marked?.body === comment ? null : { body: comment, commentId: marked?.databaseId ?? null, label: null };
  }
  const prior = priorRefusal(comments, bot);
  const since = sinceAt(prior?.body, pull.headRefOid) ?? new Date(now).toISOString();
  const records = [...recordLines(prior?.body), ...(record === null ? [] : [record])];
  const lane = refusalBody(false, reason, pull.headRefOid, label, since, false, records);
  const person = refusalBody(true, reason, pull.headRefOid, label, null, partial && !answered, records);
  const body = clears === "person" ? person : lane;
  // The same comment as written before reasons wrapped, which says this too.
  const unwrapped =
    clears === "person"
      ? renderRefusal(unwrappedFence, true, reason, pull.headRefOid, label, null, partial && !answered, records)
      : renderRefusal(unwrappedFence, false, reason, pull.headRefOid, label, since, false, records);
  const carried = (pull.labels?.nodes ?? []).some((node) => String(node?.name).toLowerCase() === String(label).toLowerCase());
  // The verifier's answer adding nothing to a partial refusal at the head:
  // its mark comes off in place, notifying no one of what it already said.
  if (body === person && !isPartial(body, pull.headRefOid) && isPartial(prior?.body, pull.headRefOid) && personReasons(prior.body, pull.headRefOid, label)?.join("\n") === fenced(reason)) {
    return { body, commentId: prior.databaseId ?? null, label: null };
  }
  // A person's comment already standing while the label is off (a pull
  // request carrying it gets here only to widen a partial one): the label
  // goes back on unless a person removed it after the comment last changed,
  // which the caller reads from the timeline (`liftedSince`).
  const standing = partial && body === person ? personReasons(prior?.body, pull.headRefOid, label) : null;
  if (prior?.body === body || (prior !== undefined && prior.body === unwrapped) || (standing !== null && fenced(reason).split("\n").every((line) => standing.includes(line)))) {
    return body === person && !carried ? { body: null, commentId: prior.databaseId ?? null, label, liftedSince: String(prior.updatedAt ?? prior.createdAt) } : null;
  }
  // An escalation to a person posts a new comment: an edit notifies no one
  // and keeps the old date, so the label would stand unexplained.
  return body === person ? { body, commentId: null, label: carried ? null : label } : { body, commentId: prior?.databaseId ?? null, label: null };
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
function ghCallsPayload(stderr) {
  const line = String(stderr ?? "")
    .split("\n")
    .map((text) => text.replace(/\r$/, ""))
    .findLast((text) => text.startsWith(GH_CALLS_PREFIX));
  try {
    return line === undefined ? null : JSON.parse(line.slice(GH_CALLS_PREFIX.length));
  } catch {
    return null;
  }
}

// That line as the log carries it, as the merge job's tee does, so one grep
// sums the calls per endpoint across both jobs: re-serialized from the parsed
// JSON, so it is one line whatever the reader printed. Null without one.
export function ghCallsLine(stderr) {
  const payload = ghCallsPayload(stderr);
  return payload === null || typeof payload !== "object" ? null : `${GH_CALLS_PREFIX}${JSON.stringify(payload)}`;
}

// The `babysit-listing-miss` lines the reader prints on stderr, one per
// incremental artifact read that missed GitHub's live count
// (babysit_verify_evidence.py LISTING_MISS_PREFIX), in order: why a read fell
// back to the full listing. Empty when there are none.
export const LISTING_MISS_PREFIX = "babysit-listing-miss ";
export function listingMissLines(stderr) {
  return String(stderr ?? "")
    .split("\n")
    .map((text) => text.replace(/\r$/, ""))
    .filter((text) => text.startsWith(LISTING_MISS_PREFIX));
}

export function ghCalls(stderr) {
  const payload = ghCallsPayload(stderr);
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
// (`agree` is n/a on a miss), or `cache=error` when the cache failed and the
// read went on without it. Null for an answer without one.
export const VERIFY_CACHE_PREFIX = "verify-cache ";
export function cacheLine(number, cache) {
  const word = (value) => (typeof value === "string" && /^[a-z:-]+$/.test(value) ? value : "?");
  if (cache === null || typeof cache !== "object") {
    return null;
  }
  if (cache.error === true) {
    return `${VERIFY_CACHE_PREFIX}${word(cache.mode)}: #${number} cache=error`;
  }
  return `${VERIFY_CACHE_PREFIX}${word(cache.mode)}: #${number} key=${word(cache.key)} stored=${word(cache.stored)} fresh=${word(cache.fresh)} agree=${cache.agree === "n/a" ? "n/a" : word(cache.agree)}`;
}

// merge.verify-cache as the run applies it: `serve` only when it says so.
export const cacheMode = (env) => (env.VERIFY_CACHE === "serve" ? "serve" : "shadow");

// The reader's env with the limit it is killed at, so it sizes its listing to
// that limit and names this caller when a listing cannot fit
// (babysit_verify_evidence.py DEADLINE_ENV and CALLER_ENV).
const readerEnv = (env, timeoutMs) => ({ ...env, BABYSIT_VERIFY_DEADLINE_SECONDS: String(timeoutMs / 1000), BABYSIT_VERIFY_CALLER: "enable-auto-merge.mjs" });

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
// one, returning no `refusal` on a miss or when there is no file to read.

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
    if (cacheOnly && !args.includes("--answers-only")) {
      // Never a full read in its place: one past the budget can outrun the step.
      return { head, cached: false };
    }
    const started = clock();
    const timeout = args.includes("--answers-only") ? CACHE_ONLY_TIMEOUT_MS : VERIFY_TIMEOUT_MS;
    const done = spawn("python3", [...args, String(number), head], { encoding: "utf8", env: readerEnv(env, timeout), timeout });
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
    const calls = ghCallsLine(done.stderr);
    if (calls !== null) {
      console.log(calls);
    }
    for (const miss of listingMissLines(done.stderr)) {
      console.log(miss);
    }
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
        .filter((text) => !text.startsWith(GH_CALLS_PREFIX) && !text.startsWith(LISTING_MISS_PREFIX))
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
    const args = [
      env.VERIFY_EVIDENCE_SCRIPT || VERIFY_SCRIPT,
      "lane-room",
      "--repo",
      env.GITHUB_REPOSITORY,
      "--postmerge-result",
      env.POSTMERGE_RESULT ?? "",
      "--code-sha",
      env.POSTMERGE_CODE_SHA ?? "",
    ];
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

// The close of a pull request decide answers `close` for: the reader's
// `capped-close` (babysit_verify_evidence.py capped_close), which judges the
// head again, posts the FAIL findings on the pull request and its issue,
// closes it, and starts the issue's fresh attempt or parks it. Its writes run
// under GH_TOKEN, the lanes App token; its Actions reads under
// BABYSIT_VERIFY_GH_TOKEN, as the verify reads. `holds`: labels that keep the
// pull request open. `reason`: `verify`, or `feedback-not-converging` for a
// head decide closes on `notConverging`, which capped_close judges again from
// the same comment. Throws when it exits non-zero.
export function pythonClose(env, spawn = spawnSync) {
  return ({ number, headRefOid: head, baseRefOid: base }, holds, reason = "verify") => {
    if (!SHA.test(String(base))) {
      throw new Error("its base commit is not a commit SHA");
    }
    const args = [env.VERIFY_EVIDENCE_SCRIPT || VERIFY_SCRIPT, "capped-close", "--repo", env.GITHUB_REPOSITORY, "--base-sha", base, "--reason", reason];
    for (const label of holds) {
      args.push("--hold-label", label);
    }
    const done = spawn("python3", [...args, String(number), head], { encoding: "utf8", env: readerEnv(env, VERIFY_TIMEOUT_MS), timeout: VERIFY_TIMEOUT_MS });
    let answer = null;
    try {
      answer = JSON.parse(String(done.stdout).trim().split("\n").at(-1));
    } catch {
      answer = null;
    }
    if (done.status !== 0) {
      throw new Error(`capped-close exited ${done.status ?? done.signal}: ${answer?.error ?? String(done.stderr ?? "").trim().split("\n").at(-1)}`);
    }
    return answer;
  };
}

// The gate's whole-review request (babysit_whole_review.py), on the lane token
// for its writes and the job token for its limits, as the merge job runs it:
// `request` answers the record line for the head, the prior comment on stdin,
// or why not; `toggle` drafts the pull request and marks it ready again,
// which starts a whole review; `recover` marks ready a draft a toggle left.
// Each call's limit: `recover` and a `request` with its `toggle` run inside
// VERIFY_BUDGET_MS, a request only while the budget lasts.
export const WHOLE_REVIEW_TIMEOUT_MS = 30_000;
export function pythonWholeReview(env, spawn = spawnSync) {
  const run = (args, input) => {
    const done = spawn("python3", [env.WHOLE_REVIEW_SCRIPT || WHOLE_REVIEW_SCRIPT, ...args], { encoding: "utf8", env, input, timeout: WHOLE_REVIEW_TIMEOUT_MS });
    if (done.status === READER_RATE_LIMIT_EXIT) {
      throw new ReaderRateLimited(`babysit_whole_review.py ${args[0]}`, done.stderr);
    }
    let answer;
    try {
      answer = JSON.parse(String(done.stdout).trim().split("\n").at(-1));
    } catch {
      throw new Error(`babysit_whole_review.py ${args[0]} exited ${done.status ?? done.signal}: ${String(done.stderr ?? "").trim().split("\n").at(-1)}`);
    }
    return answer;
  };
  const repo = ["--repo", env.GITHUB_REPOSITORY, "--identity", env.LANES_BOT_LOGIN];
  return {
    request: (pull, prior) => run(["request", ...repo, "--head", pull.headRefOid, "--node-id", pull.id], prior),
    toggle: (pull, humanGated) => run(["toggle", "--node-id", pull.id, "--human-gated", humanGated]),
    recover: (drafts) => run(["recover", ...repo, "--drafts", "/dev/stdin"], JSON.stringify(drafts)),
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

// The address-feedback lane-stopped comment report-escalation.sh posts, one
// per activity, edited in place, and the reason that closes the pull request.
export const LANE_STOPPED_FEEDBACK = "<!-- pr-unblock:lane-stopped activity=address-feedback -->";
export const NOT_CONVERGING = "feedback-not-converging";

// Whether the pr-unblock lane stopped the review rounds of the head as not
// converging: a failing pr-unblock/address-feedback status stops the head
// (detail.unblockStops), and the lanes App's (`bot`) lane-stopped comment
// names NOT_CONVERGING and `head`. The reason is read from that comment, which
// only the App writes, never from a status description, which any workflow
// run can post (babysit_verify_evidence.not_converging_stop judges it again).
export function notConverging(detail, bot, head) {
  if (!Array.isArray(detail?.unblockStops) || !detail.unblockStops.some((stop) => stop?.context === "pr-unblock/address-feedback")) {
    return false;
  }
  return (detail.comments?.nodes ?? []).some((comment) => {
    if (comment?.author?.__typename !== "Bot" || comment.author.login !== bot) {
      return false;
    }
    const lines = String(comment.body ?? "")
      .split("\n")
      .map((line) => line.replace(/\r$/, ""));
    return lines[0] === LANE_STOPPED_FEEDBACK && lines.includes(`- Reason: \`${NOT_CONVERGING}\``) && lines.includes(`- Head: \`${head}\``);
  });
}

// Why a head's pr-unblock statuses hold it (merge-holds.unblockStops), or
// null: anything but a read list of stops holds it.
export function unblockHold(stops) {
  if (!Array.isArray(stops)) {
    return "its head's pr-unblock statuses could not be read";
  }
  return stops.length === 0 ? null : `a pr-unblock lane stopped its head (${stops.map(({ context, state }) => `${context} is ${state}`).join(", ")}), which ci-status fails in the merge queue`;
}

// What to do with one listed pull request: { action: arm | disarm | none, reason }.
// `detail` is its discussion; undefined means not read yet, and an arm or a
// keep then waits on it (action `read`). Its `verify` is the gate's verifier
// evidence; absent, an arm or a keep waits on it (action `verify`).
export function decide(pull, { bot, humanGated, holdPaths = null, pathHolds = true }, detail) {
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
  // ci-status's merge-queue run fails a head a pr-unblock lane stopped, so it
  // is never queued; a status list that did not read holds it too.
  const stopped = unblockHold(detail.unblockStops);
  // Review rounds the lane stopped as not converging at this head close below,
  // after the path, cost and discussion holds, as the verify cap does.
  const unconverged = stopped !== null && notConverging(detail, bot, pull.headRefOid);
  if (stopped !== null && !unconverged) {
    return { action: armed ? "disarm" : "none", reason: stopped, clears: "lane" };
  }
  // A hold path a person clears, lifted by a trusted person's approval of the
  // head or of an earlier head carried over base merges (`lifters`) as
  // ci-status lifts it; a listing or check that could not run
  // is a lane's, which the next run reads again.
  const pathHeld = pathHoldKind(detail.files, holdPaths, pathHolds);
  if (pathHeld !== null && pathHeld.kind !== "hold-path") {
    return { action: armed ? "disarm" : "none", reason: pathHeld.reason, clears: "lane" };
  }
  // A hold path and a cost hold are both a person's, and so is a verifier
  // refusal or risk hold the gate marks so (verifyClears): every one of them
  // goes in one refusal, so one lift answers them all rather than each lift
  // exposing the next. An unarmed one waits for the verifier read to add its
  // reasons (`fold`, what stands without them); an armed one is disarmed at
  // once and the next reader run reads them.
  const reasons = [...(pathHeld !== null && !(detail.lifters?.length > 0) ? [pathHeld.reason] : []), ...[costHold(detail.files, detail.costDecision)].filter(Boolean)];
  if (reasons.length > 0) {
    const read = "verify" in detail;
    const clears = read ? verifyClears(detail.verify, pull.headRefOid) : null;
    const held = { action: armed ? "disarm" : "none", reason: personReason(clears === "person" ? [...reasons, verifyHold(detail.verify, pull.headRefOid)] : reasons), clears: "person" };
    // `partial`: the risk score is not in it, since the gate scores it only
    // once the verdict and link allow (babysit_verify_evidence.py evidence).
    const scored = read && detail.verify?.head === pull.headRefOid && detail.verify.refusal === null && detail.verify.ineligible === null;
    const partial = scored && (detail.verify.reviews === null || (typeof detail.verify.reviews === "string" && !detail.verify.reviews.startsWith("unreadable"))) ? {} : { partial: true };
    return !read && !armed ? { action: "verify", reason: "its verifier verdict is not read yet", fold: { ...held, partial: true } } : { ...held, ...partial };
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
  // Closed for a fresh attempt at its issue (pythonClose), the holds above
  // having let it through; it needs no verdict.
  if (unconverged) {
    return { action: "close", reason: `${stopped}; its review rounds are not converging (${NOT_CONVERGING})` };
  }
  if (!("verify" in detail)) {
    return { action: "verify", reason: "its verifier verdict is not read yet" };
  }
  const unverified = verifyHold(detail.verify, pull.headRefOid);
  // A refusal that never clears at the head read: closed for a fresh attempt
  // at its issue, the hold labels above having let it through.
  if (unverified !== null && detail.verify?.head === pull.headRefOid && VERIFY_FINAL.includes(detail.verify?.refusal)) {
    return { action: "close", reason: unverified };
  }
  if (unverified !== null) {
    const clears = verifyClears(detail.verify, pull.headRefOid);
    // A lane's risk hold, the only one here, that a clean whole review of the
    // head clears (babysit_whole_review.wanted): the gate requests one.
    const whole = clears === "lane" && typeof detail.verify.reviews === "string" && detail.verify.wholeReviewWanted === true;
    return { action: armed ? "disarm" : "none", reason: unverified, ...(clears ? { clears } : {}), ...(whole ? { wholeReview: true } : {}) };
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

// Skip-unchanged, as babysit_merge_skip.py keys the merge gate's skip: a
// reader run keeps, for each unarmed lanes App pull request it left on a
// lane's refusal in SKIPPABLE with nothing written, the key of every input
// that refusal reads: its head, update time and labels, its head's check and
// status rollup, review decision and count, newest comments and review
// threads (none of which need move `updatedAt`), main's code and config,
// the resolved config and the rung the gate scores at. The next reader run leaves a pull request whose
// key still matches on that refusal with no read, for at most
// merge.skip-unchanged max-minutes from its judgment and max-skips runs in a
// row, and never past the time its lane comment turns into a failing status.
// A skip only repeats a refusal: it never arms. A verdict refusal is never
// kept, since a new pr-verify artifact changes nothing in the key. The
// records ride in the pr-merge-verify-answers artifact (EAM_SKIP_IN, _OUT).
export const SKIP_VERSION = 1;
export const SKIPPABLE = Object.freeze([READER_HOLDS.risk, "a pr-unblock lane stopped its head ("]);
// merge.skip-unchanged's defaults (babysit_merge_skip.py).
export const SKIP_MAX_MINUTES = 60;
export const SKIP_MAX_SKIPS = 3;
const SKIP_CHUNK = 20;
// The paths of main whose tree ids go in the key: the config this run reads
// and every script it, the verifier and the risk score run.
export const SKIP_MAIN_PATHS = Object.freeze([
  "docs/conventions/pr-pipeline.yaml",
  ".work-item-tracker.json",
  ".github/standards/trusted-actors/trusted-actors.json",
  ".github/workflows/pr-merge.yml",
  ".github/actions",
  ".github/scripts",
  "plugins/source-control",
]);
const SKIP_STATE_FIELDS =
  "number headRefOid updatedAt reviewDecision reviews { totalCount } comments(last: 50) { totalCount nodes { databaseId updatedAt } } reviewThreads(first: 100) { totalCount nodes { isResolved isOutdated } } commits(last: 1) { nodes { commit { oid statusCheckRollup { contexts(first: 100) { totalCount nodes { __typename ... on CheckRun { databaseId name status conclusion } ... on StatusContext { context state } } } } } } }";
export const SKIP_STATE_PREFIX = "query($o: String!, $r: String!) { repository(owner: $o, name: $r) {";
export const skipStateQuery = (numbers) => `${SKIP_STATE_PREFIX} ${numbers.map((n) => `p${n}: pullRequest(number: ${n}) { ...s }`).join(" ")} } } fragment s on PullRequest { ${SKIP_STATE_FIELDS} }`;
const ZONED_TIME = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z$/;

// A merge.skip-unchanged limit: empty is `fallback`, a whole number is itself,
// anything else 0 (off).
export function skipLimit(text, fallback) {
  const value = String(text ?? "").trim();
  if (value === "" || value === "null") return fallback;
  return /^[0-9]{1,6}$/.test(value) ? Number(value) : 0;
}

// main's tree ids of SKIP_MAIN_PATHS in the `.base` clone, or null.
export function mainInputsOf(base = ".base") {
  const run = spawnSync("git", ["-C", base, "ls-tree", "HEAD", "--", ...SKIP_MAIN_PATHS], { encoding: "utf8" });
  return run.status === 0 && run.stdout.trim() !== "" ? run.stdout : null;
}

// A state node as the key reads it, or null when any part is missing, cut
// or not at `head`: the head's check and status rollup (a status's time is
// left out, so the same state posted again on the next run is no change),
// the review decision and count, the newest comments' ids and edit times,
// and the review threads' resolved and outdated flags, none of which need
// move `updatedAt`, as babysit_merge_skip.pr_state keys them.
export function rollupOf(node, head) {
  const commit = node?.commits?.nodes?.[0]?.commit;
  if (commit?.oid !== head) return null;
  const whole = (list, cap) => Array.isArray(list?.nodes) && list.totalCount === list.nodes.length && list.nodes.length <= cap;
  const contexts = commit.statusCheckRollup == null ? { totalCount: 0, nodes: [] } : commit.statusCheckRollup.contexts;
  if (!whole(contexts, 100) || !whole(node.reviewThreads, 100) || !Array.isArray(node.comments?.nodes) || !Number.isSafeInteger(node.comments.totalCount) || !Number.isSafeInteger(node.reviews?.totalCount)) {
    return null;
  }
  return {
    checks: contexts.nodes.map((c) => JSON.stringify([c?.__typename ?? null, c?.databaseId ?? c?.context ?? null, c?.name ?? null, c?.status ?? c?.state ?? null, c?.conclusion ?? null])).sort(),
    reviewDecision: node.reviewDecision ?? null,
    reviews: node.reviews.totalCount,
    comments: [node.comments.totalCount, ...node.comments.nodes.map((c) => [c?.databaseId ?? null, c?.updatedAt ?? null])],
    threads: node.reviewThreads.nodes.map((t) => JSON.stringify([Boolean(t?.isResolved), Boolean(t?.isOutdated)])).sort(),
  };
}

export const skipKey = (pull, rollup, main) =>
  createHash("sha256")
    .update(
      JSON.stringify({
        v: SKIP_VERSION,
        pr: pull.number,
        head: pull.headRefOid,
        updatedAt: pull.updatedAt ?? null,
        labels: (pull.labels?.nodes ?? []).map((node) => String(node?.name).toLowerCase()).sort(),
        rollup,
        main,
      }),
    )
    .digest("hex");

// The kept records at `path` that still stand at `at`, by number; any doubt
// keeps none.
export function loadSkips(path, repo, at, { maxMinutes, maxSkips }) {
  let data;
  try {
    data = JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return {};
  }
  if (data?.v !== SKIP_VERSION || data.repo !== repo || data.entries === null || typeof data.entries !== "object") return {};
  const kept = {};
  for (const [number, entry] of Object.entries(data.entries)) {
    const judged = ZONED_TIME.test(String(entry?.at)) ? Date.parse(entry.at) : Number.NaN;
    const until = ZONED_TIME.test(String(entry?.until)) ? Date.parse(entry.until) : Number.NaN;
    if (
      /^[0-9]+$/.test(number) &&
      at - judged >= 0 &&
      at - judged < maxMinutes * 60_000 &&
      at < until &&
      Number.isSafeInteger(entry.skips) &&
      entry.skips >= 0 &&
      entry.skips < maxSkips &&
      /^[0-9a-f]{64}$/.test(String(entry.key)) &&
      SHA.test(String(entry.head)) &&
      typeof entry.reason === "string" &&
      SKIPPABLE.some((prefix) => entry.reason.startsWith(prefix))
    ) {
      kept[number] = { at: entry.at, until: entry.until, key: entry.key, head: entry.head, reason: entry.reason, skips: entry.skips };
    }
  }
  return kept;
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

export async function main({ env = process.env, github, actions, verify, room, close, whole, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)), random, latch, now = Date.now, mainInputs } = {}) {
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
    // merge.diff-check.path-holds (owner decision Q15): off, no hold path
    // holds, and a refusal naming only hold paths comes off (approvalLift).
    const pathHolds = readPathHolds(env.RESOLVED_CONFIG ?? "");
    // The newest answer's rate limit and body, for an arm GitHub refuses.
    let answer = null;
    const onResponse = (response) => {
      answer = { limited: response.headers.get("x-ratelimit-remaining") === "0" || response.headers.has("retry-after"), text: response.clone().text().catch(() => "") };
    };
    const injected = github !== undefined;
    latch ??= rateLimitLatch;
    github = withRetry(github ?? createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, onResponse, latch }), { sleep, random });
    // The lane runs, jobs and annotations a cost decision's decided head is
    // read from, and the head's pr-unblock statuses, on the job token
    // (actions: read, checks: read, statuses: read), as the verifier reads
    // take it; the lanes App token holds none of them.
    actions =
      actions ??
      (!injected && env.BABYSIT_VERIFY_GH_TOKEN
        ? withRetry(createGitHub({ token: env.BABYSIT_VERIFY_GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, latch }), { sleep, random })
        : github);
    // A reader child that stops on a rate limit writes its stop to the job's
    // stop file; set from then on. Its stop holds every lanes App pull request
    // as an unread room does, so an armed one is disarmed, unless the disarm's
    // own pool (GraphQL) is stopped too: then it stays armed, named in an
    // error, and the run fails.
    let stopped = null;
    const disarmStop = () => (stopped === null ? null : latch.until(`${env.GITHUB_API_URL || "https://api.github.com"}/graphql`));
    // Arms or disarms one pull request. When a resent send errors, the first
    // may have landed with its answer lost, so the state is read back once:
    // an open pull request armed at the head the run read, or unarmed, is the
    // target reached and returns as a success. Any other state, a failed
    // read, or a rate limit (nothing more is sent) throws the send's own
    // error, with the newest answer still the send's.
    const sendSettled = async (action, pull) => {
      const [query, variables] = action === "arm" ? [ARM_MUTATION, { id: pull.id, head: pull.headRefOid }] : [DISARM_MUTATION, { id: pull.id }];
      try {
        await github("POST", "/graphql", { query, variables });
      } catch (error) {
        if ((error?.attempts ?? 1) === 1 || answer?.limited || [401, 403, 429].includes(error?.status) || disarmStop() !== null) {
          throw error;
        }
        const sent = answer;
        let state;
        try {
          state = (await github("POST", "/graphql", { query: AUTO_MERGE_STATE_QUERY, variables: { id: pull.id } }))?.data?.node;
        } catch (readError) {
          console.log(`enable-auto-merge: #${pull.number} ${action} failed after a resend and its state was not read back: ${describe(readError)}`);
        }
        answer = sent;
        // An open pull request only: a merged one shows no auto-merge either,
        // and a disarm that missed it must still fail.
        const reached = state?.state === "OPEN" && (action === "arm" ? state.autoMergeRequest != null && state.headRefOid === pull.headRefOid : state.autoMergeRequest === null);
        if (!reached) {
          throw error;
        }
        console.log(`enable-auto-merge: #${pull.number} ${action} failed after a resend (${describe(error)}), but it is already ${action === "arm" ? `armed at ${pull.headRefOid}` : "unarmed"}, so an earlier send landed`);
      }
    };
    verify ??= pythonVerify(env);
    whole ??= pythonWholeReview(env);
    const reads = READER_EVENTS.includes(env.EVENT_NAME);
    const serve = cacheMode(env) === "serve";
    // A pull_request_target run handles only the pull request its event
    // names, as the listing holds it; a scheduled or hand-started run, every one.
    const listed = await listPulls(github, repo[1], repo[2]);
    const pulls = env.EVENT_NAME === "pull_request_target" ? listed.filter((pull) => String(pull.number) === String(env.EVENT_PR ?? "")) : listed;
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
    // A whole-review child stopped on a rate limit holds every lanes App pull
    // request after it, as a verifier read's stop does.
    const wholeStopped = (error) => {
      if (!(error instanceof ReaderRateLimited)) {
        return false;
      }
      stopped = error;
      latch.reload?.();
      laneHeld = `the lane's room could not be read (${error.message})`;
      return true;
    };
    // A lanes App draft a whole-review toggle left (the run ended between its
    // two writes) is marked ready, as the merge job recovers its candidates',
    // inside the verdict reads' budget.
    const drafts = pulls.filter((pull) => lanes(pull) && pull.isDraft === true && holdReason(pull, humanGated) === null);
    if (reads && write && stopped === null && drafts.length > 0) {
      try {
        const listed = drafts.map((pull) => ({ number: pull.number, id: pull.id, head: pull.headRefOid, updatedAt: pull.updatedAt, labels: (pull.labels?.nodes ?? []).map((node) => node?.name) }));
        for (const item of whole.recover(listed)) {
          console.log(`enable-auto-merge: #${item.pr} ${item.ready === true ? "marked ready again: a whole-review toggle left it a draft" : `left a draft by a whole-review toggle, not marked ready: ${escapeCommand(item.error ?? "mark-ready failed")}`}`);
        }
      } catch (error) {
        if (!wholeStopped(error)) {
          console.log(`::warning title=enable-auto-merge::the whole-review drafts did not recover: ${describe(error)}`);
        }
      }
    }
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
    // Each pull request a pr-unblock stop on its head kept out of the queue, for the summary.
    const unblockSkips = [];
    if (holdPaths === null) {
      console.log("::warning title=enable-auto-merge::the resolved config's hold paths did not read, so nothing is armed this run; the next run reads them again");
    }
    // A reader run's per pull request refusal (the lane's hold line, a hold
    // path or cost hold, or the gate's verdict or risk score) goes on the
    // pull request itself:
    // under merge.lane-prs native the gate never lists it, so a log line
    // would be all anyone saw.
    // Writes note sent or tried, for skip-unchanged.
    let sent = 0;
    const note = async (pull, detail, refusal) => {
      if (!reads || stopped !== null || refusal.clears === undefined) {
        return;
      }
      const status = unarmedStatus(pull, detail?.comments?.nodes, refusal, { bot: slug, now: now(), minutes });
      if (status !== null && write) {
        statuses.push(status);
      }
      // A whole review the gate would request at the head (decide's
      // `wholeReview`): its record line goes in the comment, written before
      // the toggle, so a failed write never toggles twice at a head. Past the
      // budget the next run asks.
      let record = null;
      if (write && refusal.wholeReview === true && refusal.clears === "lane" && typeof refusal.comment !== "string" && now() <= deadline) {
        sent += 1;
        try {
          const answer = whole.request(pull, priorRefusal(detail?.comments?.nodes, slug)?.body ?? "");
          if (typeof answer?.line === "string" && WHOLE_REVIEW_RECORD.test(answer.line)) {
            record = answer.line;
          } else if (answer !== null) {
            console.log(`enable-auto-merge: #${pull.number} whole review not requested: ${escapeCommand(JSON.stringify(answer))}`);
          }
        } catch (error) {
          if (wholeStopped(error)) {
            return;
          }
          console.log(`::warning title=enable-auto-merge::#${pull.number} whole-review request: ${describe(error)}`);
        }
      }
      const writes = refusalWrites(pull, detail?.comments?.nodes, { ...refusal, record }, { bot: slug, label: humanGated, now: now() });
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
      sent += 1;
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
        return;
      }
      if (record !== null) {
        try {
          const toggled = whole.toggle(pull, humanGated);
          console.log(
            toggled?.toggled === true
              ? `enable-auto-merge: #${pull.number} whole review requested at ${pull.headRefOid}: drafted and marked ready again`
              : `::warning title=enable-auto-merge::#${pull.number} whole-review toggle: ${escapeCommand(toggled?.error ?? JSON.stringify(toggled))}`,
          );
        } catch (error) {
          if (!wholeStopped(error)) {
            console.log(`::warning title=enable-auto-merge::#${pull.number} whole-review toggle: ${describe(error)}`);
          }
        }
      }
    };
    // Skip-unchanged (SKIPPABLE): a reader run that writes keeps its records
    // and reads the last run's.
    const skips = { on: reads && write && Boolean(env.EAM_SKIP_OUT), maxMinutes: skipLimit(env.SKIP_MAX_MINUTES, SKIP_MAX_MINUTES), maxSkips: skipLimit(env.SKIP_MAX_SKIPS, SKIP_MAX_SKIPS) };
    const rollups = new Map();
    const kept = {};
    let skipStore = {};
    let skipMain = null;
    let skipped = 0;
    let recorded = 0;
    let keyable = 0;
    if (skips.on && skips.maxMinutes > 0 && skips.maxSkips > 0) {
      skipMain = (mainInputs ?? (() => mainInputsOf()))();
      try {
        // The rung the gate scores the risk at (pythonVerify's `rung`).
        skipMain = skipMain === null ? null : `${skipMain}\n${readFileSync(env.RESOLVED_CONFIG ?? "", "utf8")}\n${minutes}\n${lane?.rung ?? ""}\n${env.RUNG_CAP ?? ""}`;
      } catch {
        skipMain = null;
      }
      if (skipMain !== null) {
        skipStore = loadSkips(env.EAM_SKIP_IN ?? "", repo[0], now(), skips);
        const numbers = pulls.filter((pull) => lanes(pull) && pull.autoMergeRequest == null && pull.isDraft === false && holdReason(pull, humanGated) === null).map((pull) => pull.number);
        keyable = numbers.length;
        for (let start = 0; start < numbers.length; start += SKIP_CHUNK) {
          try {
            const read = (await github("POST", "/graphql", { query: skipStateQuery(numbers.slice(start, start + SKIP_CHUNK)), variables: { o: repo[1], r: repo[2] } }))?.data?.repository;
            for (const number of numbers.slice(start, start + SKIP_CHUNK)) {
              const node = read?.[`p${number}`];
              const listed = pulls.find((pull) => pull.number === number);
              const rollup = node?.number === number && node.headRefOid === listed.headRefOid && node.updatedAt === listed.updatedAt ? rollupOf(node, listed.headRefOid) : null;
              if (rollup !== null) rollups.set(number, rollup);
            }
          } catch (error) {
            console.log(`enable-auto-merge: skip-unchanged state read failed, so those pull requests are read in full: ${describe(error)}`);
          }
        }
      }
    }
    for (let pull of rotated(pulls, Number(env.GITHUB_RUN_NUMBER))) {
      if (stopped === null && lanes(pull) && !(pull.labels?.totalCount <= (pull.labels?.nodes?.length ?? 0))) {
        try {
          pull = { ...pull, labels: await allLabels(github, repo[0], pull.number) };
        } catch (error) {
          console.log(`enable-auto-merge: #${pull.number} labels did not read whole: ${describe(error)}`);
        }
      }
      let { action, reason } = decide(pull, { bot: slug, humanGated, holdPaths, pathHolds });
      let clears;
      let comment;
      let withdraw;
      // A person's hold that waits on the verifier to add its reasons (decide's
      // `fold`), and whether the refusal lacks the verifier's answer.
      let fold = null;
      let partial;
      // Whether a clean whole review of the head would clear its lane risk hold.
      let wholeReview;
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
      // Held by the label alone, its refusal at the head written without the
      // verifier's answer (isPartial): a reader run with time left reads it
      // once, judged as if unlabeled, to widen the comment. It never arms.
      const labelHold = reason;
      let widen = reads && stopped === null && held === null && pull.autoMergeRequest == null && reason === `it carries ${humanGated}` && now() <= deadline && roomHold(pull) === null;
      // A widening read finding no partial comment reads nothing past the discussion.
      let unmarked = false;
      const judged = widen ? { ...pull, labels: unlabeledAs(pull.labels, humanGated) } : pull;
      // Whether a widening read got the verifier's answer.
      let answered = false;
      if (widen) {
        action = "read";
      }
      // This pull request's skip key, when its outcome may be kept or skipped.
      const key = skipMain !== null && action === "read" && !widen && held === null && stopped === null && pull.autoMergeRequest == null && rollups.has(pull.number) ? skipKey(pull, rollups.get(pull.number), skipMain) : null;
      const prior = key === null ? undefined : skipStore[pull.number];
      if (prior !== undefined && prior.key === key && prior.head === pull.headRefOid) {
        skipped += 1;
        kept[pull.number] = { ...prior, skips: prior.skips + 1 };
        console.log(`enable-auto-merge: #${pull.number} left, unchanged since ${prior.at} (skip ${prior.skips + 1} of ${skips.maxSkips}): ${escapeCommand(prior.reason)}`);
        continue;
      }
      if (action === "read") {
        try {
          const variables = { owner: repo[1], name: repo[2], number: pull.number };
          detail = (await github("POST", "/graphql", { query: DETAIL_QUERY, variables }))?.data?.repository?.pullRequest ?? null;
          if (detail !== null) {
            detail = await wholeDiscussion(github, variables, detail);
            const standing = priorRefusal(detail?.comments?.nodes, slug)?.body;
            // A hold-path refusal with a trusted person's approval in the
            // discussion reads on, for approvalLift below.
            const approvedBy = (detail.reviews?.nodes ?? []).map(itemOf).some((item) => item.isUser && trustedHumans(env).has(item.userId) && item.state === "APPROVED");
            unmarked = widen && !isPartial(standing, pull.headRefOid) && !((approvedBy || pathHolds === false) && holdPathOnly(standing, pull.headRefOid, humanGated, pathHolds));
          }
          if (detail !== null && !unmarked) {
            const graphed = listedFiles(detail.files);
            const { paths: files, capped } = graphed !== null ? { paths: graphed, capped: false } : await changedFiles(github, `${repo[1]}/${repo[2]}`, pull.number);
            const humans = trustedHumans(env);
            const decision = costHold(files, null) ? await costDecision(github, repo[0], pull.number, pull.body, humans, pull.headRefOid, actions) : null;
            let lifters = headLifters(detail, humans, pull.headRefOid);
            // An approval of an earlier head carried over base merges
            // (merge-holds.liftersOf) lifts the hold path as ci-status lifts
            // it, so a base merge after a person's approval does not send the
            // pull request back to them.
            const skipped = pathHolds === false ? pathHoldKind(files, holdPaths) : null;
            if (skipped?.kind === "hold-path") {
              console.log(`enable-auto-merge: #${pull.number} path holds are off (merge.diff-check.path-holds), so nothing holds it for this: ${escapeCommand(skipped.reason)}`);
            }
            if (!lifters.length && Array.isArray(holdPaths) && pathHoldKind(files, holdPaths, pathHolds)?.kind === "hold-path") {
              lifters = (await liftersOf(github, repo[0], pull.number, pull.headRefOid, humans, holdPaths)).lifters;
            }
            let stops = null;
            try {
              // On the job token (statuses: read): the lanes App holds no
              // commit-statuses permission.
              stops = unblockStops(await readStatuses(actions, `${repo[1]}/${repo[2]}`, pull.headRefOid));
            } catch (error) {
              console.log(`enable-auto-merge: #${pull.number} head statuses did not read: ${describe(error)}`);
            }
            detail = { ...detail, files, filesCapped: capped, costDecision: decision, lifters, unblockStops: stops };
            // A hold-path escalation a trusted person's approval of the head
            // lifts: the lane takes its label off, which re-runs ci-status at
            // the head (pr-require-checks.yml runs on unlabeled), and judges
            // it as unlabeled from here.
            // The label must stand for that refusal alone (liftBlocker), and
            // the head read again just before the delete must be the one
            // judged. A read that fails keeps the label.
            let lift = widen && approvalLift(pull, detail, { bot: slug, label: humanGated, holdPaths, pathHolds });
            if (lift) {
              let kept;
              try {
                kept = await liftBlocked(github, repo[0], pull.number, { label: humanGated, login: env.LANES_BOT_LOGIN, humans, head: pull.headRefOid });
                if (kept === null && write) {
                  const fresh = await github("GET", `/repos/${repo[0]}/pulls/${pull.number}`);
                  kept = fresh?.head?.sha === pull.headRefOid ? null : `its head moved to ${fresh?.head?.sha ?? "an unread head"}`;
                }
              } catch (error) {
                kept = `the label's history did not read: ${describe(error)}`;
              }
              if (kept !== null) {
                console.log(`enable-auto-merge: #${pull.number} keeps ${escapeCommand(humanGated)}: ${escapeCommand(kept)}`);
              }
              lift = kept === null;
            }
            if (lift) {
              if (write) {
                await github("DELETE", `/repos/${repo[0]}/issues/${pull.number}/labels/${encodeURIComponent(humanGated)}`);
              }
              const why = pathHolds === false ? "path holds are off (merge.diff-check.path-holds)" : `${detail.lifters.join(", ")} approved its head`;
              console.log(`enable-auto-merge: #${pull.number} ${write ? "lifted" : "would lift (report-only)"} ${escapeCommand(humanGated)}: ${why}, which lifts its hold path`);
              widen = false;
              // Off in this run's view too, so a person's reason the verifier
              // read adds puts the label back (refusalWrites).
              pull.labels = unlabeledAs(pull.labels, humanGated);
            }
          }
        } catch (error) {
          // A read that fails decides nothing and writes nothing.
          detail = null;
          console.log(`enable-auto-merge: #${pull.number} discussion did not read: ${describe(error)}`);
        }
        ({ action, reason, clears, comment, withdraw, partial, fold = null } =
          widen && (detail === null || unmarked)
            ? { action: "none", reason: labelHold, clears: undefined, comment: undefined, withdraw: undefined, partial: undefined, fold: null }
            : decide(judged, { bot: slug, humanGated, holdPaths, pathHolds }, detail));
        if (detail && reason === unblockHold(detail.unblockStops)) {
          unblockSkips.push(`#${pull.number} ${action === "disarm" ? "disarmed" : "not queued"}: ${escapeCommand(reason)}`);
        }
      }
      // Past the budget, under serve with an answers file, an unarmed pull
      // request is answered only from a kept refusal, which reads no more
      // than its key, for CACHE_ONLY_WINDOW_MS.
      const at = now();
      const late = at > deadline;
      const cacheOnly = late && at <= deadline + CACHE_ONLY_WINDOW_MS && serve && Boolean(env.VERIFY_ANSWERS_OUT) && pull.autoMergeRequest == null;
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
        answered = evidence !== null && !decided;
        if (!decided) {
          ({ action, reason, clears, comment, withdraw, partial, wholeReview } = decide(judged, { bot: slug, humanGated, holdPaths, pathHolds }, { ...detail, verify: evidence }));
        }
        // A kept answer that holds nothing: read in full once, never armed on.
        if (!decided && action === "verify") {
          if (now() > deadline) {
            ({ action, reason } = { action: "none", reason: "no time left in this run to read its verifier verdict" });
          } else {
            evidence = await read({ fresh: true });
            if (!decided) {
              ({ action, reason, clears, comment, withdraw, wholeReview } = decide(judged, { bot: slug, humanGated, holdPaths, pathHolds }, { ...detail, verify: evidence }));
            }
          }
        }
        // A path or cost hold is no kept answer's: its label goes back on as before.
        cached = fold === null && evidence?.cached === true;
      }
      // A person's hold whose verifier read did not come (no time left, not
      // a reader run, a cache-only miss) stands with the reasons it has.
      if (fold !== null && stopped === null && clears === undefined) {
        ({ action, reason, clears, partial } = fold);
      }
      // A widening read writes only a person's refusal, whole once the
      // answer came; an answer naming no person's reason (the hold lifted)
      // takes the mark off the standing reasons, so no later run reads again.
      // With no answer the marked comment waits for the next run.
      if (widen && stopped === null) {
        const standing = personReasons(priorRefusal(detail?.comments?.nodes, slug)?.body, pull.headRefOid, humanGated);
        ({ action, reason, clears, comment, withdraw, partial } =
          answered && clears === "person"
            ? { action: "none", reason, clears, comment, withdraw: undefined, partial }
            : answered && standing !== null
              ? { action: "none", reason: standing.join("\n"), clears: "person", comment: undefined, withdraw: undefined, partial: true }
              : { action: "none", reason: labelHold, clears: undefined, comment: undefined, withdraw: undefined, partial: undefined });
      }
      // A pull request the verifier refuses for good closes for a fresh
      // attempt; a failed close leaves it for the next run, which finds what
      // this one wrote.
      if (action === "close") {
        if (!write) {
          console.log(`enable-auto-merge: #${pull.number} would close for a fresh attempt (report-only): ${escapeCommand(reason)}`);
          continue;
        }
        let closed = false;
        try {
          // An armed one is disarmed first, so a close that fails leaves it unarmed.
          if (pull.autoMergeRequest != null) {
            await sendSettled("disarm", pull);
            console.log(`enable-auto-merge: #${pull.number} disarmed: ${escapeCommand(reason)}`);
          }
          close ??= pythonClose(env);
          const result = await close(pull, ["do-not-merge", humanGated], detail && notConverging(detail, slug, pull.headRefOid) ? NOT_CONVERGING : "verify");
          closed = result?.closed === true;
          console.log(
            closed
              ? `enable-auto-merge: #${pull.number} closed for a fresh attempt (${escapeCommand(reason)}); restarted ${JSON.stringify(result.restarted ?? [])}, parked ${JSON.stringify(result.parked ?? [])}`
              : `enable-auto-merge: #${pull.number} left open: ${escapeCommand(result?.reason ?? "the close answered nothing")}`,
          );
        } catch (error) {
          failed += 1;
          console.log(`::error title=enable-auto-merge::#${pull.number} capped close: ${describe(error)}`);
        }
        // Left open, it sits unarmed: the lane's refusal note and its
        // pr-merge/unarmed status, never a person's label.
        if (!closed) {
          await note(pull, detail, { clears: "lane", reason, cached, partial, answered });
        }
        continue;
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
        const sentBefore = sent;
        const failedBefore = failed;
        await note(pull, detail, { clears, reason, comment, cached, partial, answered, wholeReview });
        // Kept only when this run wrote nothing for it, so the key read
        // before it still stands.
        if (key !== null && detail != null && sent === sentBefore && failed === failedBefore && stopped === null && clears === "lane" && typeof comment !== "string" && wholeReview !== true && SKIPPABLE.some((prefix) => String(reason).startsWith(prefix))) {
          const since = sinceAt(priorRefusal(detail.comments?.nodes, slug)?.body, pull.headRefOid);
          const at = now();
          const escalated = unarmedStatus(pull, detail.comments?.nodes, { clears, reason, comment }, { bot: slug, now: at, minutes }) !== null;
          const until = Math.min(at + skips.maxMinutes * 60_000, escalated ? Number.POSITIVE_INFINITY : Date.parse(String(since)) + minutes * 60_000);
          if (since !== undefined && until > at) {
            recorded += 1;
            kept[pull.number] = { at: new Date(at).toISOString(), until: new Date(until).toISOString(), key, head: pull.headRefOid, reason: String(reason), skips: 0 };
          }
        }
        continue;
      }
      if (!write) {
        if (roomHeld.get(pull.number) === "armed") {
          roomHeld.set(pull.number, "report-only");
        }
        console.log(`enable-auto-merge: #${pull.number} would ${action} (report-only): ${escapeCommand(reason)}`);
        await note(pull, detail, { clears, reason, partial, answered });
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
          await sendSettled("arm", pull);
          console.log(`enable-auto-merge: #${pull.number} armed at ${pull.headRefOid}`);
          statuses.push({ sha: pull.headRefOid, state: "success", description: "armed for native auto-merge" });
        } else {
          await sendSettled("disarm", pull);
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
        // and the next run counts it from autoMergeRequest. A causeless error
        // (undici's bare "fetch failed") is named, since its message alone does
        // not say what threw.
        if (action === "arm" && transient(error)) {
          skippedArms.push(`#${pull.number}`);
          networkArms += 1;
          console.log(`::warning title=enable-auto-merge::#${pull.number} arm failed on the network after its resends, skipped this run: ${describe(error, { label: true })}`);
          continue;
        }
        failed += 1;
        console.log(`::error title=enable-auto-merge::#${pull.number} ${action}: ${describe(error)}`);
        // Still armed: a note saying it is unarmed would be false.
        continue;
      }
      if (action === "disarm") {
        await note(pull, detail, { clears, reason, partial, answered });
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
    if (skips.on) {
      console.log(`enable-auto-merge: skip-unchanged skipped=${skipped} recorded=${recorded} keyed=${rollups.size} of ${keyable}`);
      try {
        writeFileSync(`${env.EAM_SKIP_OUT}.tmp`, JSON.stringify({ v: SKIP_VERSION, repo: repo[0], entries: kept }));
        renameSync(`${env.EAM_SKIP_OUT}.tmp`, env.EAM_SKIP_OUT);
      } catch (error) {
        console.log(`::warning title=enable-auto-merge::the skip records were not kept, so the next run reads every pull request: ${describe(error)}`);
      }
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
    const summary = [...lines.map(([, text]) => text), ...unblockSkips, ...(verify.costs ?? []).map(costLine)];
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
