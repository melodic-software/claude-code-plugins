#!/usr/bin/env node
// clear-escalations.mjs: takes the human-gated label off an open pull request
// into main once the reason the pr-unblock lane recorded for it no longer holds
// at the current head. No model.
//
// Only a label the lanes App set is ever removed, and only when all of these hold:
// - The newest `labeled` event for the label on the PR's timeline has the lanes
//   App bot as its actor, and the App's first escalation comment after it
//   came within PAIRED_MS (report-escalation.sh writes the label, then the
//   comment).
// - No review lane holds it: no comment carrying a REVIEW_HOLD marker line, by
//   claude[bot] or by github-actions[bot] ending in the lane's `claude-lane:`
//   footer, and no `labeled` event of the label by either, was written or
//   edited since a person on the trusted list last removed the label (ever,
//   when none did), as ci-status reads a lift. A lane adding a label the PR
//   already carries writes no `labeled` event, so its hold can sit under the
//   App's label, and that person removing the label is what lifts it.
// - check-signed-commits does not hold it: no github-actions[bot] comment
//   whose first line is SIGNED_COMMITS_HOLD was written or edited since the
//   label was last removed (ever, when it never was), by the same rule.
// - pr-verify does not hold it: no github-actions[bot] comment whose first
//   line is CREDENTIAL_HOLD was written or edited since then, by the same rule.
// - Every escalation comment since that label event is the App's: its author
//   is the bot login and a Bot account, its first line is the pr-unblock
//   escalation marker, its second the resume-key line, and its `- Reason:`
//   line names one of CHECKS. A later escalation adds no label event, so each
//   one counts. Text anyone else writes, a marker included, is never read.
// - No lanes App comment written or edited since then carries any other
//   marker (pr-merge's, another lane's): unknown keeps it.
// - No person commented, reviewed, or left a review or commit comment since
//   the label went on: they may want the lane to wait. Bot accounts (AI
//   review, other lanes) are not someone speaking; an App marker is judged
//   by the rule above instead.
// - Every recorded reason no longer holds at the current head:
//     workflow-staged          (a label set before escalation-routes.json
//                              routed it `fail`) main changed nothing under
//                              .github/workflows/ since its merge base with
//                              the head, so merging main into the head stages
//                              no workflow change; or a trusted move (below)
//                              and the head contains main as it was at the
//                              escalation
//     unresolved-conflict,     GitHub reports the PR mergeable: no conflict
//     protected-path-conflict  is left to resolve
//     feedback-protected-path  the PR changes nothing under .github/workflows/
//     feedback-not-landed      the head is none of its resume keys, no
//                              unresolved review thread carries a lanes App
//                              comment (owner decision 2026-10-25), and
//                              either a trusted move (below) or, when every
//                              escalation recorded against the label since
//                              it was last removed is on LANE_ONLY, clean
//                              review lanes at the head (reviewLanesClean):
//                              a lanes App push alone never clears it
//     ci-fix-* but             a trusted move, and at the new head no check
//     ci-fix-protected-path    but ci-status (the label fails it) fails, runs
//                              or was cancelled, each latest run ended
//                              success, neutral or skipped, and one passed
//     a fix-ci reason escalation-routes.json routes `fail` (a lane run before
//     that route set the label): once a lane check of a pr-require-checks run
//     on the current head reads failed (fix-ci-context's failingChecks;
//     ci-status itself fails on the label, so it proves nothing, and an
//     advisory lane's failure leaves ci-status green), so the head stays red
//     without the label. Another fail-routed reason but feedback-not-landed
//     is a person's (below): a lane posts a pr-unblock/* status on a head
//     only when it stops there or clears its own failure, so a moved head
//     carries nothing that shows the cause gone or fails that head in the
//     label's place
//   A trusted move: the head is this repository's and none of the recorded
//   resume keys, and every activity on its branch since the label (the
//   activity API, read with the job token) is by an id trusted-actors.json
//   lists as a `human`, never the lanes App, the newest landing the head.
//   Comment text never counts. Removing the label approves nothing: ci-status
//   fails a review-lane hold an App lifted, unless the App lifted it as
//   stale-review-hold (below), and a hold path needs a trusted person's
//   approving review.
//   A listing that may be cut short, or a mergeable state not yet computed,
//   counts as the reason still holding.
// - No person wrote or edited a review comment, or submitted a review, since
//   the label went on. GitHub's timeline shows no event for a reply inside an
//   existing review thread, so a lift the rules above allow reads
//   pulls/<n>/comments (since the label) and pulls/<n>/reviews too, and
//   feedback-not-landed and a native refusal read them before their slow
//   reads; every path reads them again right before the removal, where a
//   review thread opened while the PR's reads ran keeps the label too; a
//   failed read keeps the label. Known limits: a review body edited after the label
//   is not seen (a REST review carries no update time), and any account
//   GitHub does not mark Bot, an outsider included, keeps the label, which
//   costs throughput only.
// Any other reason is decided by a person and is never cleared here: a
// security, intent or decision stop, or one with no cause-gone evidence.
//
// With no pr-unblock escalation since the label, a pr-merge escalation clears
// as `head-moved` instead, but only when the marked lanes App comment written
// last before the label is pr-merge's and came within PAIRED_MS of it, or
// carries pr-merge's escalation line (enable-auto-merge puts the label back
// under a standing one), so a label added for another reason is never read
// as pr-merge's. Then the newest lanes App comment carrying each of
// pr-merge's own markers (PR_MERGE_MARKERS) names, in its `at head `<sha>``,
// a head that is not the PR's current one. pr-merge then judges the new head
// and escalates again if its refusal still holds: under `merge.lane-prs:
// native` enable-auto-merge does, labeling it again only for a cause a person
// must clear. A marker whose head does not parse as 40-hex keeps the label,
// and so does any other marker, as above.
//
// When a review lane (github-actions[bot] or claude[bot]) added the label
// last, it clears as `stale-review-hold` when staleHoldEvidence (below) finds every
// hold since the label was last removed no longer standing at the current head
// (a trusted move off the held head, both lanes' whole reviews passing there
// with no CRITICAL finding), check-signed-commits does not hold it, no
// lanes App marker but an address-feedback round's was written since the
// label, and no person spoke since. Just before the delete, the head and the
// hold comments are read again: a moved head or a new hold keeps the label.
// ci-status runs the base commit's copy of this module's recheckStaleHold
// before it counts the App's removal. A lane that still finds the cause holds the new
// head again with its own comment and label.
//
// Before the label comes off, the App posts one comment naming the cleared
// reason and the head; a sweep that finds that comment for this escalation
// and head only retries the removal. At most CLEARS_PER_RUN a run.
//
// Under `merge.lane-prs: native`, enable-auto-merge's own person refusal
// comment (refusalBody, unedited) on a lanes App pull request, the only
// pr-merge escalation there, naming the current head, is judged again at that
// head only when its recorded cause is the lanes' (owner decision Q-CLEAR B):
// a verifier or risk reason whose every code is on LANE_CAUSES, a label set
// before its cause became a lane's. Then the gate's reader (`evidence`, as
// enable-auto-merge reads it, the room's rung cap passed as C3 so the scorer
// answers at the config's rung) runs, and the label comes off as
// `refusal-cleared` when nothing refuses, or when every code refusing now is
// on LANE_CAUSES too and the reader got at least as far as the recorded
// cause: the link, then the verdict, then the risk score, each read only once
// the one before passes. A person's recorded cause (an issue link, any code
// off that list, an unknown one included) is never read and never lifted at
// that head: a person removes the label, or a push clears it as head-moved
// above and enable-auto-merge labels the new head again if the cause holds.
// An unread answer and a failed read keep it; so does a hold or cost path,
// which no reader answer clears. At most NATIVE_READS_PER_RUN reads a run,
// starting at an offset that moves with the run number (rotated), so labels
// past the cap are read on a later run.
//
// The session-builder queue label (needs-session, each `label` that
// escalation-routes.json names) comes off with no comment when the lanes App
// added it last and each lane stop routed to it since then is mended: a
// same-head retry landed and report-escalation.sh `clear` posted success after
// that stop, or the head moved off every such stop's head and the new head
// carries no failing status for their activities and passes its checks
// (sessionVerdict).
// At most SESSION_CHECKS_PER_RUN pull requests are read a run, kept or cleared,
// from the same rotating offset.
//
// Environment:
//   GH_TOKEN             the lane App token (pull-requests and issues write)
//   CHECKS_TOKEN         the job's own token (checks: read, actions: read), for
//                        the head's pr-require-checks runs and check runs,
//                        and the statuses of a lane stop's head and the
//                        current head, which the lane token cannot read
//   GITHUB_REPOSITORY    owner/repo
//   KILL_SWITCH          `proceed` from the kill-switch step; anything else stops
//   TRACKER_CONFIG       the base .work-item-tracker.json, for the human-gated
//                        label (default .base/.work-item-tracker.json)
//   LANE_PRS             merge.lane-prs as resolve-config resolved it; only
//                        `native` re-judges enable-auto-merge's refusal
//   LANES_BOT_LOGIN      the lanes App bot login (default
//                        melodic-automation-lanes[bot])
//   TRUSTED_ACTORS_PATH  the base trusted-actors.json (default
//                        .base/.github/standards/trusted-actors/trusted-actors.json)
//   GITHUB_API_URL
//   GITHUB_RUN_NUMBER    where the sweep starts (rotated)
//   BABYSIT_VERIFY_GH_TOKEN, BABYSIT_VERIFY_LISTING, BABYSIT_VERIFY_HEAD_REFS,
//   BABYSIT_VERIFY_LISTING_CARRY,
//   BABYSIT_RUN_CACHE    the gate reader's Actions token and the run's shared
//                        reads, as enable-auto-merge passes them; the job
//                        token also reads branch activity, check runs and
//                        main's history for a trusted move, and the review
//                        lanes' runs, jobs and annotations
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { humanGatedLabelFrom } from "../pr-unblock/address-feedback.mjs";
import {
  CLEARED,
  ESCALATION,
  escalationsSince,
  escalationActivity,
  escalationRoute,
  failingChecks,
  foreignMarker,
  holdText,
  HOLD_LINE,
  isApp,
  labelHistory,
  LANE_STOPPED,
  laneHold,
  lines,
  MODEL_RUN,
  openCredentialHold,
  openReviewHold,
  openSignedCommitsHold,
  PAIRED_MS,
  personSince,
  RESUME_KEY,
  reviewEntries,
  ROUND_MARKER,
  ROUTES,
  same,
  sinceParam,
  spoken,
} from "../pr-unblock/gate-source.mjs";
import { isProtectedPath } from "../pr-unblock/thread-scope.mjs";
import { branchActivity, LANES_APP_LOGIN as DEFAULT_BOT, laneChange, OUTSIDE_ACTOR_LABEL as OUTSIDE_ACTOR, readStatuses, REVIEW_LANES } from "./merge-holds.mjs";
import { pythonVerify, READER_HOLDS, REFUSAL_MARKER, refusalReasons, rotated, verifyHold } from "./enable-auto-merge.mjs";

const REASON = /^- Reason: `([a-z-]+)`$/m;
// An outside actor's hold is a person's to lift: an item carrying the
// security-outside-actor label keeps its needs-human whatever else cleared.
const outsideActorHeld = (labels) => (labels ?? []).some((item) => same(item?.name, OUTSIDE_ACTOR));
const OUTSIDE_ACTOR_KEPT = `it carries ${OUTSIDE_ACTOR}, which a person lifts`;
const CREDENTIAL_KEPT = "pr-verify holds it for a credential, which a person lifts";
const clearedMarker = (reason, head) => `<!-- pr-pipeline needs-human-cleared reason=${reason} head=${head} -->`;
// babysit_merge.py's verifier-refusal escalation, reasons comment, shared-copy
// escalation and Dependabot-major escalation: the marker on the first or
// second line, the next line naming `at head `<sha>``.
const PR_MERGE_MARKERS = Object.freeze([
  "<!-- babysit-merge-verify-escalation -->",
  "<!-- babysit-merge-risk -->",
  "<!-- babysit-merge-shared-copy-escalation -->",
  "<!-- babysit-merge-dependabot-major -->",
]);
// The work-items escalation line pr-merge writes above a marker: pr-merge's
// own, so it neither unpairs the comment nor counts as another lane's marker.
const PR_MERGE_ESCALATION = "<!-- work-items:escalation lane=pr-merge kind=escalated -->";
const prMergeLine = (line) => PR_MERGE_MARKERS.includes(line) || line === PR_MERGE_ESCALATION;
const AT_HEAD = / at head `([^`]*)`/g;
const HEAD_MOVED = "head-moved";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
// report-escalation.sh's fix-ci stops, each judged by ciPasses. Not
// ci-fix-protected-path or ci-fix-weaken-required: a session builder makes
// their fix (needs-session), so an older human-gated label on them clears only
// once the head's checks read failed, the lane's failing status holding it.
const CI_FIX = Object.freeze(["ci-fix-round-cap", "ci-fix-empty", "ci-fix-invalid", "ci-fix-not-applied", "ci-fix-escalated"]);
// The only conclusions a check's latest run at the head may have for a ci-fix
// stop to clear; action_required, stale, null and any other keep it.
const PASSING = new Set(["success", "neutral", "skipped"]);
// fix-ci's aggregate check, which the human-gated label itself fails.
const AGGREGATE = "ci-status";
// Check-run pages read at a head; a head with more stays unread.
const CHECK_PAGES = 3;
const SHA = /^[0-9a-f]{40}$/;
// The compare API lists at most 300 files, the PR files API at most 3000.
const COMPARE_CAP = 300;
const FILES_CAP = 3000;
// Each clear lets the lanes run on the PR again (judgment).
export const CLEARS_PER_RUN = 5;
// Each reader run takes up to enable-auto-merge's VERIFY_TIMEOUT_MS; the
// step's timeout-minutes (pr-merge.yml) allows this many (judgment).
export const NATIVE_READS_PER_RUN = 3;
// A kept label is read again every run, so reads are capped, not just clears
// (judgment: the same five; rotated reaches the rest on later runs).
export const SESSION_CHECKS_PER_RUN = 5;
const REFUSAL_CLEARED = "refusal-cleared";
// The causes the lanes clear, by READER_HOLDS kind: the only recorded ones
// this script lifts at the same head, and the only ones a lift tolerates
// refusing now. Every other code, an unknown one included, is a person's. The
// list is explicit, so it fails closed; lane-causes-person-codes.test.mjs pins
// it against babysit_risk.PERSON_CODES and PERSON_PREFIXES (#10249) and
// babysit_verify_evidence.NEEDS_HUMAN.
// - risk (an entry ending in ":" is a prefix): babysit_risk.py's holding MED
//   codes files-incomplete (:938) and evidence-unbound:<lane> (:978-998), and
//   the manifest review (:598). Not the reader's `unreadable: …` score.
//   files-incomplete and the manifest review join their items with "; ", so
//   a reason with two or more items reads as unknown codes and stays.
// - verdict: every babysit_verify_evidence.py refusal off NEEDS_HUMAN that
//   answers: FAIL, EARLIER_FAIL and SPEC_CHANGED, which a push or a new
//   judgment clears, and REPEATED_FAIL and TOO_OLD, which never clear but hold
//   for the lanes with no label (owner rule 2026-10-27). Not untrusted-spec (a
//   person's), missing or unreadable (no answer), or ineligible (always
//   paired with a link answer, which verifyHold reads first).
// - link: none; an issue link is a person's.
export const LANE_CAUSES = Object.freeze({
  link: Object.freeze([]),
  verdict: Object.freeze(["verify:fail", "verify:earlier-fail", "verify:spec-changed", "verify:repeated-fail", "verify:too-old"]),
  risk: Object.freeze(["files-incomplete", "evidence-unbound:", "manifest-review-required"]),
});

// Whether the `kind` reason (verifyHold's) names only causes the lanes clear:
// each "; "-separated code on LANE_CAUSES[kind].
function laneCause(kind, reason) {
  const codes = reason.slice(READER_HOLDS[kind].length, -1).split("; ").map((part) => part.split(": ")[0]);
  return codes.every((code) => LANE_CAUSES[kind].some((entry) => (entry.endsWith(":") ? code.startsWith(entry) : code === entry)));
}


// The workflow whose lanes ci-status aggregates. An advisory lane's failure
// (pr-test-platforms) leaves ci-status green once the label is off, so only
// this workflow's checks count.
const REQUIRED_WORKFLOW = "pr-require-checks.yml";

// Whether a lane check of a pr-require-checks run on the head (not ci-status)
// failed. Every such run counts: a contract-only run posts its lanes skipped,
// and failingChecks prefers a lane's real result over that skip. One read per
// PR; a listing that fails, or may be cut short, reads as not failing.
async function headFailing({ checks, repo, pull }) {
  try {
    const required = (await checks("GET", `/repos/${repo}/actions/workflows/${REQUIRED_WORKFLOW}/runs?head_sha=${pull.head.sha}&per_page=100`))?.workflow_runs;
    if (!Array.isArray(required) || required.length >= 100) {
      return false;
    }
    const suites = new Set(required.map((run) => run.check_suite_id));
    const runs = [];
    for (let page = 1; ; page += 1) {
      const listed = (await checks("GET", `/repos/${repo}/commits/${pull.head.sha}/check-runs?filter=all&per_page=100&page=${page}`))?.check_runs;
      if (!Array.isArray(listed)) {
        return false;
      }
      runs.push(...listed);
      if (listed.length < 100) {
        break;
      }
      if (page === CHECK_PAGES) {
        return false;
      }
    }
    return failingChecks(runs.filter((run) => run.app?.slug === "github-actions" && suites.has(run.check_suite?.id))).length > 0;
  } catch {
    return false;
  }
}

const reasonOf = ({ body }) => REASON.exec(body.join("\n"))?.[1];
const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const reportError = (number, error) =>
  console.log(`::error title=clear-escalations::#${number}: ${escapeCommand(error?.message ?? error)}`);

// The only escalations a lanes App push may lift with clean review lanes
// (reviewLanesClean) in a person's place: the lane's own stops. Any other
// escalation recorded against the label (a person-held path, a security
// finding, a merge-risk hold, an owner reason, an unknown one) keeps it for a
// person or a trusted push (owner direction on the security finding).
export const LANE_ONLY = Object.freeze(["feedback-not-landed"]);
// Any lane's escalation line.
const ANY_ESCALATION = "<!-- work-items:escalation";

// The first escalation recorded against the label since it was last removed
// (ever, when it never was) that is not on LANE_ONLY, or undefined: a
// pr-unblock escalation's reason, or a pr-merge marker or another lane's
// escalation line on a lanes App comment written or edited since then. A
// reason that does not parse, or a time that does not parse, counts.
function personEscalation({ appComments, lifted }) {
  return appComments
    .filter((item) => !(Math.max(Date.parse(item.created_at), Date.parse(item.updated_at ?? item.created_at)) < lifted))
    .flatMap((item) => {
      const body = lines(item.body);
      const unblock = body[0] === ESCALATION ? [reasonOf({ body }) ?? "an escalation whose reason does not parse"] : [];
      return [...unblock, ...body.filter((line) => PR_MERGE_MARKERS.includes(line) || (line.startsWith(ANY_ESCALATION) && line !== ESCALATION))];
    })
    .find((reason) => !LANE_ONLY.includes(reason));
}

// Why each reason no longer holds at `pull`'s head, or { held } saying why it
// still does. `moved` and `mainMerged` read with the job token (`reader`) and
// answer null on any doubt, an unreadable read included.
const CHECKS = Object.freeze({
  "workflow-staged": async (context) => {
    const { github, repo, pull, mainSha } = context;
    const files = (await github("GET", `/repos/${repo}/compare/${pull.head.sha}...${mainSha}`))?.files;
    const workflow = (path) => /^\.github\/workflows\//.test(String(path ?? ""));
    const listed = Array.isArray(files) && files.length < COMPARE_CAP;
    const changed = listed ? files.flatMap((file) => [file.filename, file.previous_filename]).find(workflow) : undefined;
    if (listed && changed === undefined) {
      return `main changes nothing under .github/workflows/ since its merge base with ${pull.head.sha}`;
    }
    // The merge the lane would not push is in place: a trusted push moved the
    // head, and the head contains main as it was when the lane escalated.
    const moved = await context.moved();
    const merged = moved === null ? null : await context.mainMerged("workflow-staged");
    if (merged !== null) {
      return `${moved}, and it contains main as of the escalation (${merged})`;
    }
    return { held: listed ? `main ${mainSha} changes ${changed}` : `main ${mainSha}'s file listing against it may be cut short` };
  },
  "unresolved-conflict": async ({ pull }) => mergeable(pull),
  "protected-path-conflict": async ({ pull }) => mergeable(pull),
  ...Object.fromEntries(CI_FIX.map((reason) => [reason, ciPasses])),
  "feedback-protected-path": async ({ github, repo, pull }) => {
    const files = await paginate(github, `/repos/${repo}/pulls/${pull.number}/files`);
    return files.length >= FILES_CAP || files.some((file) => isProtectedPath(file.filename) || isProtectedPath(file.previous_filename ?? ""))
      ? { held: "the pull request changes a protected path, or its file listing may be cut short" }
      : "the pull request changes nothing under .github/workflows/";
  },
  // address-feedback's fix did not reach its resume key. Gone once the head
  // is none of those keys, no review thread the lane replied to is open, and
  // a trusted push moved the head or, when every escalation recorded against
  // the label is on LANE_ONLY, both review lanes read it clean: a lanes App
  // push alone must not clear its own stop.
  "feedback-not-landed": async (context) => {
    const head = context.pull.head.sha;
    if (context.keysOf("feedback-not-landed").includes(head)) {
      return { held: "the head is still the one the lane's fix did not reach" };
    }
    const open = await openLaneThreads(context);
    if (open === null) {
      return { held: "its review thread listing may be cut short" };
    }
    if (open > 0) {
      return { held: `${open} unresolved review thread(s) carry a lanes App comment` };
    }
    // The review threads before the job token's reads: a person's reply
    // there keeps the label whatever the trusted move or the lanes answer.
    const speaker = await context.speaker();
    if (speaker !== undefined) {
      return { spoke: speaker };
    }
    const moved = await context.moved();
    if (moved !== null) {
      return `${moved}, and no review thread the lane replied to is unresolved`;
    }
    const recorded = personEscalation(context);
    if (recorded !== undefined) {
      return { held: `a push no trusted person made moved the head, and ${recorded} is recorded against the label: clean review lanes lift only ${LANE_ONLY.join(", ")}` };
    }
    const clean = await reviewLanesClean(context);
    return clean === null
      ? { held: `a push no trusted person made moved the head; waiting for clean review lanes at ${head}` }
      : `the head moved off the resume key to ${head}, no review thread the lane replied to is unresolved, and ${clean}`;
  },
  // A fix-ci reason escalation-routes.json now routes to a failing status
  // rather than a person, on a label an older lane run set: once the head's
  // checks read failed, so it stays red without the label. Otherwise a ci-fix
  // stop still clears as ciPasses decides (a trusted push fixed it). Every
  // other fail-routed reason but feedback-not-landed is a person's here: a
  // lane posts a pr-unblock/* status on a head only when it stops there or
  // clears its own failure (report-escalation.sh), so nothing on a new head
  // proves its cause gone or fails that head in the label's place.
  ...Object.fromEntries(
    Object.keys(ROUTES)
      .filter((reason) => escalationRoute(reason) === "fail" && escalationActivity(reason) === "fix-ci")
      .map((reason) => [
        reason,
        async (context) => {
          if (await context.failing()) {
            return "the lane now ends it in a failing status, not a person, and the head's own checks read failed";
          }
          return CI_FIX.includes(reason) ? ciPasses(context) : { held: "the head's own checks do not read failed" };
        },
      ]),
  ),
});

// A ci-fix stop: the lane could not fix CI at its resume key. Gone once a
// trusted push moved the head and checksHeld finds the new head's checks pass.
async function ciPasses(context) {
  const moved = await context.moved();
  if (moved === null) {
    return { held: "no trusted push alone moved the head off the resume key" };
  }
  const held = await checksHeld(context.read, context.repo, context.pull.head.sha);
  return held === null ? `${moved}, and no check other than ${AGGREGATE} fails, runs or was cancelled at it` : { held };
}

// Why `head`'s checks do not pass, or null when they do: no check fails, runs
// or was cancelled (fix-ci's failingChecks over every run, so a later skip
// hides no failure), each check's latest run ended in PASSING, and one passed.
// ci-status is left out: the label fails it. `read` runs a read with a token
// that holds checks: read and answers null when the read fails.
async function checksHeld(read, repo, head) {
  const runs = await read(async (reader) => {
    const all = [];
    for (let page = 1; page <= CHECK_PAGES; page += 1) {
      const batch = (await reader("GET", `/repos/${repo}/commits/${head}/check-runs?filter=all&per_page=100&page=${page}`))?.check_runs;
      if (!Array.isArray(batch)) {
        return null;
      }
      all.push(...batch);
      if (batch.length < 100) {
        return all;
      }
    }
    return null;
  });
  const others = (runs ?? []).filter((run) => run?.name !== AGGREGATE);
  const latest = new Map();
  for (const run of others) {
    if (!(latest.get(run.name)?.id > run.id)) {
      latest.set(run.name, run);
    }
  }
  if (
    runs === null ||
    failingChecks(others).length > 0 ||
    others.some((run) => run.status !== "completed") ||
    [...latest.values()].some((run) => !PASSING.has(run.conclusion)) ||
    !others.some((run) => run.conclusion === "success")
  ) {
    return `a check other than ${AGGREGATE} fails, runs, was cancelled or did not pass at ${head}, or its runs did not read`;
  }
  return null;
}

// The review lanes reviewLanesClean reads, as pr-require-checks.yml's
// `Require both review lanes on this head` step names them: the workflow, the
// lane its completion record names, its status job, and whether only a whole
// review counts.
const LANE_RECORDS = Object.freeze([
  { file: "pr-review-hosted.yml", lane: "claude-review", job: "pr-review / claude-review-status", whole: false },
  { file: "pr-review-security-hosted.yml", lane: "claude-security-review", job: "pr-review-security / security-review", whole: true },
]);
const RECORD_TITLE = "claude-lane-review-complete";
// A review's completion record (babysit_review_evidence.py RECORD_RE); a skip
// record matches none of it, so it reviewed nothing here.
const REVIEW_RECORD =
  /^claude-lane-review-complete lane=([\w-]+) sha=([0-9a-f]{40}) findings=\d{1,6} inline=\d{1,6} scope=(whole|incremental since=[0-9a-f]{40})(?: account=fallback)?$/;
// The security lane's reviewed-head marker, the first line of the comment
// that carries its summary, and the summary's and each inline comment's
// severity lines (babysit_review_evidence.py MARKER_RE, SUMMARY_CRITICAL_RE,
// SEVERITY_RE).
const SECURITY_REVIEWED_HEAD = /^<!-- claude-lane-reviewed-head lane=claude-security-review sha=([0-9a-f]{40}) -->$/;
const MARKER_AUTHOR = "github-actions[bot]";
const CRITICAL_FINDINGS = /^\s*`?critical-findings: (\d{1,6})`?\s*$/gm;
const newestById = (items) => items.reduce((newest, item) => (newest === undefined || item.id > newest.id ? item : newest), undefined);

// Whether both review lanes read `pull`'s head clean: a description, or null
// on any doubt, an unreadable or full page included. Read with the job token:
// each lane's newest pull_request run on the head from this repository
// completed success, and so did its status job, whose one completion record
// names the lane and the head as a review, never a skip; the security lane's
// is a whole review. The security lane's newest reviewed-head marker names
// the head, is unedited (an edit's author is not read), and carries one
// `critical-findings: 0` line. Every unresolved review thread opens with one
// readable `severity:` line below CRITICAL: a CRITICAL or unreadable one, as
// on a person's thread, keeps it (only a CRITICAL finding holds, owner
// decision on #11020). For a clear that a push no
// trusted person made may lift.
async function reviewLanesClean(context) {
  const { read, repo, pull, timeline } = context;
  const head = pull.head.sha;
  for (const { file, lane, job, whole } of LANE_RECORDS) {
    const scope = await read(async (reader) => {
      const runs = (await reader("GET", `/repos/${repo}/actions/workflows/${file}/runs?head_sha=${head}&event=pull_request&per_page=100`))?.workflow_runs;
      if (!Array.isArray(runs) || runs.length >= 100) {
        return null;
      }
      const run = newestById(
        runs.filter((item) => item?.path === `.github/workflows/${file}` && item.head_sha === head && item.event === "pull_request" && item.head_repository?.full_name === repo),
      );
      if (run?.status !== "completed" || run.conclusion !== "success") {
        return null;
      }
      const jobs = (await reader("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`))?.jobs;
      if (!Array.isArray(jobs) || jobs.length >= 100) {
        return null;
      }
      const status = newestById(jobs.filter((item) => item?.name === job));
      if (status?.status !== "completed" || status.conclusion !== "success") {
        return null;
      }
      const notes = await reader("GET", `/repos/${repo}/check-runs/${status.id}/annotations?per_page=100`);
      if (!Array.isArray(notes) || notes.length >= 100) {
        return null;
      }
      const records = notes.filter((note) => note?.title === RECORD_TITLE);
      const record = records.length === 1 && records[0].annotation_level === "notice" ? REVIEW_RECORD.exec(String(records[0].message ?? "")) : null;
      return record !== null && record[1] === lane && record[2] === head ? record[3] : null;
    });
    if (scope === null || (whole && scope !== "whole")) {
      return null;
    }
  }
  const marker = timeline
    .filter((item) => item.event === "commented" && isApp(item.user, MARKER_AUTHOR) && SECURITY_REVIEWED_HEAD.test(lines(item.body)[0]))
    .at(-1);
  if (
    marker === undefined ||
    SECURITY_REVIEWED_HEAD.exec(lines(marker.body)[0])[1] !== head ||
    !(Date.parse(marker.updated_at ?? marker.created_at) <= Date.parse(marker.created_at))
  ) {
    return null;
  }
  const counts = [...String(marker.body).matchAll(CRITICAL_FINDINGS)];
  if (counts.length !== 1 || Number(counts[0][1]) !== 0) {
    return null;
  }
  const open = await context.threads();
  const severe = (thread) => {
    const found = [...String(thread?.opening?.nodes?.[0]?.body ?? "").matchAll(SEVERITY)];
    return found.length !== 1 || found[0][1] === "CRITICAL";
  };
  if (open === null || open.some(severe)) {
    return null;
  }
  return "both review lanes completed a review of it, the security review whole with critical-findings: 0, and no unresolved review thread carries a CRITICAL or unreadable severity";
}

// main's tip when the newest `reason` escalation was written, when the head
// contains it (the compare from it to the head is behind by none), or null.
async function mainMergedAt({ read, repo, pull, escalations }, reason) {
  const times = escalations.filter((item) => reasonOf(item) === reason).map((item) => item.at);
  if (times.length === 0 || !times.every(Number.isFinite)) {
    return null;
  }
  const until = new Date(Math.max(...times)).toISOString();
  return read(async (reader) => {
    const then = (await reader("GET", `/repos/${repo}/commits?sha=main&until=${encodeURIComponent(until)}&per_page=1`))?.[0]?.sha;
    if (!SHA.test(String(then))) {
      return null;
    }
    const compare = await reader("GET", `/repos/${repo}/compare/${then}...${pull.head.sha}`);
    return compare?.behind_by === 0 && ["ahead", "identical"].includes(compare?.status) ? then : null;
  });
}

function mergeable(pull) {
  return pull.mergeable === true && pull.mergeable_state !== "dirty"
    ? "GitHub reports no conflict with main"
    : { held: `GitHub reports mergeable ${pull.mergeable ?? "unknown"} (${pull.mergeable_state ?? "unknown"})` };
}

// Review-thread pages read for feedback-not-landed; a PR with more stays unread.
const THREAD_PAGES = 10;
const LANE_THREADS_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          isResolved
          opening: comments(first: 1) { nodes { body } }
          comments(first: 100) { totalCount nodes { author { __typename login } } }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

// How many unresolved review threads on `pull` carry a comment by the lanes
// App `bot`, or null when a listing may be cut short. GraphQL names a Bot
// without the `[bot]` REST adds.
async function openLaneThreads({ threads, bot }) {
  const open = await threads();
  const lane = (author) => author?.__typename === "Bot" && (author.login === bot || `${author.login}[bot]` === bot);
  return open === null ? null : open.filter((thread) => thread.comments.nodes.some((comment) => lane(comment?.author))).length;
}

// The unresolved review threads on `pull`, or null when a listing may be cut
// short.
async function unresolvedThreads({ github, repo, pull }) {
  const [owner, name] = repo.split("/");
  const open = [];
  let after = null;
  for (let page = 0; page < THREAD_PAGES; page += 1) {
    const variables = { owner, name, number: pull.number, after };
    const threads = (await github("POST", "/graphql", { query: LANE_THREADS_QUERY, variables }))?.data?.repository?.pullRequest?.reviewThreads;
    if (!Array.isArray(threads?.nodes)) {
      return null;
    }
    for (const thread of threads.nodes) {
      if (thread?.isResolved === true) {
        continue;
      }
      const comments = thread?.comments;
      if (thread?.isResolved !== false || !Array.isArray(comments?.nodes) || !(comments.totalCount <= comments.nodes.length)) {
        return null;
      }
      open.push(thread);
    }
    if (!threads.pageInfo?.hasNextPage) {
      return open;
    }
    after = threads.pageInfo.endCursor;
  }
  return null;
}

const keepNote = (label) => `To keep a person on it, add \`${label}\` back: a label a person adds is never removed.`;

export const clearedComment = (reason, head, why, label) =>
  reason === STALE_HOLD
    ? `${clearedMarker(reason, head)}\nA review lane held this pull request at an earlier head, and that hold no longer stands at \`${head}\` (\`${STALE_HOLD}\`): ${why}. pr-merge removed \`${label}\`; a review lane that still finds the cause holds the head again. ${keepNote(label)}`
    : reason === REFUSAL_CLEARED
    ? `${clearedMarker(reason, head)}\nThe pr-merge lane left this pull request for a person, and at \`${head}\` that no longer holds (\`${REFUSAL_CLEARED}\`): ${why}. pr-merge removed \`${label}\`, so the next scheduled run judges it again. ${keepNote(label)}`
    : reason === HEAD_MOVED
    ? `${clearedMarker(reason, head)}\nThe pr-merge lane escalated this pull request, and its head has moved (\`${HEAD_MOVED}\`): ${why}. pr-merge removed \`${label}\` so it judges \`${head}\` afresh, and escalates again if its refusal still holds. ${keepNote(label)}`
    : `${clearedMarker(reason, head)}\nThe pr-unblock lane escalated this pull request as \`${reason.replaceAll(",", "`, `")}\`, and that no longer holds at \`${head}\`: ${why}. pr-merge removed \`${label}\`, so the lanes run on it again. ${keepNote(label)}`;

// The newest lanes App comment carrying each pr-merge marker, with the head it
// names: null when that line names none, or more than one, as 40-hex.
function prMergeEscalations(appComments) {
  return PR_MERGE_MARKERS.flatMap((marker) => {
    const newest = appComments.filter((item) => lines(item.body).slice(0, 2).includes(marker)).at(-1);
    if (newest === undefined) {
      return [];
    }
    const body = lines(newest.body);
    const named = [...String(body[body.indexOf(marker) + 1] ?? "").matchAll(AT_HEAD)].map((match) => match[1]);
    return [{ marker, head: named.length === 1 && SHA.test(named[0]) ? named[0] : null }];
  });
}

// enable-auto-merge's person refusal comment, when it is the only pr-merge
// escalation in `merged`, names `head`, verifyHold wrote its reason, and
// nothing edited it since (enable-auto-merge posts a person's anew):
// { kind, reason }, kind a READER_HOLDS key.
function nativeRefusal(appComments, merged, label, head) {
  if (merged.length !== 1 || merged[0].marker !== REFUSAL_MARKER || merged[0].head !== head) {
    return null;
  }
  const newest = appComments.filter((item) => lines(item.body).slice(0, 2).includes(REFUSAL_MARKER)).at(-1);
  if (!(Date.parse(newest.updated_at) <= Date.parse(newest.created_at))) {
    return null;
  }
  const reason = refusalReasons(newest.body, true, head, label)?.join("\n");
  const kind = reason === undefined ? undefined : Object.keys(READER_HOLDS).find((key) => reason.startsWith(READER_HOLDS[key]));
  return kind !== undefined ? { kind, reason } : null;
}

// Whether the reader's `evidence` at `head` lifts the `kind` refusal, whose
// recorded cause the caller has found the lanes' (laneCause): nothing
// refuses, or what refuses now is the lanes' too and the reader got at least
// as far as the recorded cause. It reads the link, then the verdict, then the
// risk score (READER_HOLDS order), each only once the one before passes, so a
// refusal that stops earlier hides the recorded cause.
function liftsRefusal(kind, evidence, head) {
  const held = verifyHold(evidence, head);
  if (held === null) {
    return true;
  }
  const order = Object.keys(READER_HOLDS);
  const now = order.find((key) => held.startsWith(READER_HOLDS[key]));
  return order.indexOf(now) >= order.indexOf(kind) && laneCause(now, held);
}

// Whether the lanes App comment written last at or before `since` that carries
// any marker other than this script's own is pr-merge's alone, and was written
// within PAIRED_MS of it (pr-merge writes its comment, then the label) or
// carries pr-merge's escalation line, under which enable-auto-merge puts a
// missing label back with no new comment. A comment's writes are its
// creation and its last edit; a tie fails closed.
function pairedWithPrMerge(appComments, since) {
  let newest = -Infinity;
  let ours = false;
  let escalated = false;
  for (const item of appComments) {
    const markers = lines(item.body).filter((line) => line.includes("<!--") && !CLEARED.test(line) && !LANE_STOPPED.test(line));
    const at = Math.max(...[item.created_at, item.updated_at].map(Date.parse).filter((time) => time <= since));
    if (markers.length === 0 || at < newest) {
      continue;
    }
    const mine = markers.some((line) => PR_MERGE_MARKERS.includes(line)) && markers.every(prMergeLine);
    ours = at > newest ? mine : ours && mine;
    escalated = at > newest ? markers.includes(PR_MERGE_ESCALATION) : escalated && markers.includes(PR_MERGE_ESCALATION);
    newest = at;
  }
  return ours && (since - newest <= PAIRED_MS || escalated);
}

// A STALE HOLD (staleHoldEvidence, which clear-escalations runs before the
// App removes the label and ci-status runs again through recheckStaleHold).
// The holds since the label was last removed no longer stand only when every
// hold comment names a head (`sha=`), none names the current one, and at the
// judged head (the current one; for ci-status, the head the App cleared):
// - a trusted move took the branch off the newest held head: every push since
//   the one that landed it is by a `human` of trusted-actors.json, never the
//   lanes App;
// - a push since each held head is not a merge, so an `Update branch` alone
//   lifts nothing, and a critical-security hold's lane left at least one
//   CRITICAL inline finding at its held head, each in a file a pushed commit
//   changed and on lines changed since: a finding only the summary carried,
//   or one whose lines no push touched, stays for a person;
// - the head changes neither review caller (merge-holds laneChange), which a
//   pull_request run takes from the head and so could forge its notices;
// - both review lanes passed: each caller's newest pull_request run on the
//   head, from this repository, has its status job succeeded, recording one
//   review-complete notice for the lane and the head and no hold notice;
// - every lane's review was whole, so a finding at an older head was looked
//   at again, and none leaves a CRITICAL finding: the security lane's summary
//   reads `critical-findings: 0`; a strict lane (the security lane, or one a
//   hold names) counted every finding inline; and no unresolved thread a lane
//   opened is at CRITICAL, or, for a strict lane, has no one readable
//   `severity:` line. An IMPORTANT or SUGGESTION finding is reported and
//   keeps nothing (docs/conventions/pr-pipeline/README.md).
// A read that fails, or a listing that may be cut short, keeps the hold.

export const STALE_HOLD = "stale-review-hold";
// Each review caller's lane id, as its notices and comments name it.
const LANE_OF = Object.freeze({ "pr-review-hosted.yml": "claude-review", "pr-review-security-hosted.yml": "claude-security-review" });
const SECURITY_LANE = "claude-security-review";
// The security lane's per-finding and summary severity lines
// (/review:security-review "Reporting"; babysit_review_evidence's SEVERITY_RE
// and SUMMARY_CRITICAL_RE).
const SEVERITY = /^\s*`?severity: (CRITICAL|IMPORTANT|SUGGESTION)`?\s*$/gm;
const CRITICAL_COUNT = /^\s*`?critical-findings: (\d{1,6})`?\s*$/gm;
const HOLD_LANE = /^<!-- claude-lane-hold lane=([a-z-]+) /;
const HOLD_CRITERIA = / criteria=([a-z,-]+) -->$/;
// The most files GitHub lists for a commit; a listing that long may be cut short.
const COMPARE_FILES = 300;
// The most fix commits whose files a critical-security clear reads (judgment).
const FIX_COMMITS = 20;
const LANE_TAG = /^\s*`?claude-lane: ([\w-]+)`?\s*$/m;
const REVIEW_THREAD_PAGES = 10;
const REVIEW_THREADS_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        nodes { isResolved path comments(first: 1) { nodes { author { __typename login } body originalCommit { oid } originalLine originalStartLine } } }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

// The review lane a review comment (GraphQL author) is from: a Claude App
// comment's tag, ANY_LANE when it has none, or a github-actions comment's last
// non-blank line as its footer (babysit_review_evidence._lane_comment); null
// for any other comment.
const ANY_LANE = "*";
function commentLane(author, body) {
  if (author?.__typename !== "Bot") {
    return null;
  }
  const text = String(body ?? "");
  if (["claude", "claude[bot]"].includes(author.login)) {
    return LANE_TAG.exec(text)?.[1] ?? ANY_LANE;
  }
  const last = lines(text).filter((line) => line.trim() !== "").at(-1) ?? "";
  return ["github-actions", "github-actions[bot]"].includes(author.login) ? (LANE_TAG.exec(last)?.[1] ?? null) : null;
}

// Each review thread a review lane opened, as { lane, severity, resolved,
// path, commit, lines } (its root comment's `severity:` values, the commit it
// was made on and the [first, last] lines it names there, or null); null when the listing does not read or may be cut short.
async function laneThreads({ github, repo, number }) {
  const [owner, name] = repo.split("/");
  const open = [];
  let after = null;
  for (let page = 0; page < REVIEW_THREAD_PAGES; page += 1) {
    const threads = (await github("POST", "/graphql", { query: REVIEW_THREADS_QUERY, variables: { owner, name, number, after } }))?.data?.repository?.pullRequest
      ?.reviewThreads;
    if (!Array.isArray(threads?.nodes)) {
      return null;
    }
    for (const thread of threads.nodes) {
      const root = thread?.comments?.nodes?.[0];
      if (thread?.isResolved === true && root === undefined) {
        continue;
      }
      if (typeof thread?.isResolved !== "boolean" || root === undefined) {
        return null;
      }
      const lane = commentLane(root.author, root.body);
      if (lane !== null) {
        open.push({
          lane,
          severity: [...String(root.body ?? "").matchAll(SEVERITY)].map((match) => match[1]),
          resolved: thread.isResolved,
          path: thread.path ?? null,
          commit: root.originalCommit?.oid ?? null,
          lines: Number.isInteger(root.originalLine) ? [root.originalStartLine ?? root.originalLine, root.originalLine] : null,
        });
      }
    }
    if (!threads.pageInfo?.hasNextPage) {
      return open;
    }
    after = threads.pageInfo.endCursor;
  }
  return null;
}

// One review caller's verdict at `head`, read with the job token: { findings,
// inline, whole } from its review-complete notice, or { held } saying why it
// has not passed there.
async function laneReview({ checks, repo, head }, [file, check]) {
  const lane = LANE_OF[file];
  try {
    const runs = (await checks("GET", `/repos/${repo}/actions/workflows/${file}/runs?event=pull_request&head_sha=${head}&per_page=100`))?.workflow_runs;
    if (!Array.isArray(runs) || runs.length >= 100) {
      return { held: `${lane}'s runs on ${head} did not read whole` };
    }
    const run = runs.filter((item) => item?.head_sha === head && item.head_repository?.full_name === repo).sort((a, b) => b.id - a.id)[0];
    if (run === undefined) {
      return { held: `${lane} has not run on ${head}` };
    }
    const jobs = (await checks("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`))?.jobs;
    const job = (Array.isArray(jobs) ? jobs : []).filter((item) => item?.name === check).sort((a, b) => b.id - a.id)[0];
    if (job?.status !== "completed" || job.conclusion !== "success") {
      return { held: `${lane} has not passed on ${head}` };
    }
    const notes = await checks("GET", `/repos/${repo}/check-runs/${job.id}/annotations?per_page=100`);
    if (!Array.isArray(notes) || notes.length >= 100) {
      return { held: `${lane}'s notices on ${head} did not read whole` };
    }
    const messages = notes.filter((note) => note?.annotation_level === "notice").map((note) => String(note.message ?? ""));
    if (messages.some((message) => message.startsWith("claude-lane-hold ") && message.includes(` sha=${head} `))) {
      return { held: `${lane} holds ${head}` };
    }
    const done = new RegExp(
      `^claude-lane-review-complete lane=${lane} sha=${head} findings=(\\d{1,6}) inline=(\\d{1,6}) scope=(whole|incremental since=[0-9a-f]{40})(?: account=fallback)?$`,
    );
    const reviewed = messages.map((message) => done.exec(message)).filter((match) => match !== null);
    if (reviewed.length !== 1) {
      return { held: `${lane} recorded no one review of ${head}` };
    }
    return { lane, findings: Number(reviewed[0][1]), inline: Number(reviewed[0][2]), whole: reviewed[0][3] === "whole" };
  } catch (error) {
    return { held: `${lane}'s run on ${head} did not read: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}` };
  }
}

// Why a lane's review of `head` may leave a CRITICAL finding, or null when
// none does. Every lane's review must be whole, so a finding at an older head
// was looked at again. A lane is strict when it is the security lane or a hold
// names it: every finding it counted must be inline, and an open thread of it
// with no one readable `severity:` line counts as CRITICAL. Any lane's open
// thread at CRITICAL counts.
function findingsHeld({ head, timeline, threads }, reviews, heldLanes) {
  for (const review of reviews) {
    if (!review.whole) {
      return `${review.lane} reviewed only part of ${head}`;
    }
    if ((review.lane === SECURITY_LANE || heldLanes.has(review.lane)) && review.findings > review.inline) {
      return `${review.lane} reported ${review.findings - review.inline} finding(s) at ${head} with no inline severity`;
    }
  }
  const marker = `<!-- claude-lane-reviewed-head lane=${SECURITY_LANE} sha=${head} -->`;
  const summary = timeline.filter((item) => item.event === "commented" && isApp(item.user, "github-actions[bot]") && lines(item.body)[0] === marker);
  const counts = summary.length === 1 ? [...String(summary[0].body).matchAll(CRITICAL_COUNT)].map((match) => match[1]) : [];
  if (counts.length !== 1 || counts[0] !== "0") {
    return `the security lane's summary of ${head} does not read critical-findings: 0`;
  }
  const open = threads.filter((thread) => !thread.resolved);
  for (const { lane } of reviews) {
    const strict = lane === SECURITY_LANE || heldLanes.has(lane);
    const blocking = open.filter(
      (thread) =>
        (thread.lane === lane || thread.lane === ANY_LANE) &&
        (thread.severity.length === 1 ? thread.severity[0] === "CRITICAL" : strict || thread.severity.includes("CRITICAL")),
    ).length;
    if (blocking > 0) {
      return `${blocking} unresolved ${lane} finding(s) at CRITICAL or with no one readable severity`;
    }
  }
  return null;
}

// Whether trusted pushes alone moved `pull`'s head off every resume key since
// the label went on: the head is this repository's (the activity API shows no
// fork push), its newest push since `since` landed the head, and every push
// or other activity on the branch since then is by an id `trusted` holds (a
// `human` of trusted-actors.json; never the lanes App, whose own push would
// lift its own stop). The branch's activity, read by cursor to its end
// (branchActivity), must reach back past `since`, or the move stays unread. A
// description, or null.
export async function trustedMove({ read, repo, pull, keys, since, trusted }) {
  const head = pull.head.sha;
  const ref = String(pull.head?.ref ?? "");
  if (trusted === null || keys.includes(head) || pull.head?.repo?.full_name !== repo || ref === "") {
    return null;
  }
  const activity = await read((reader) => branchActivity(reader, repo, ref));
  if (!Array.isArray(activity)) {
    return null;
  }
  const at = (item) => Date.parse(String(item?.timestamp));
  const recent = activity.filter((item) => !(at(item) <= since)).sort((a, b) => at(b) - at(a));
  if (recent.length === 0 || recent.length === activity.length || recent[0].after !== head) {
    return null;
  }
  if (recent.some((item) => !trusted.has(item?.actor?.id))) {
    return null;
  }
  const by = [...new Set(recent.map((item) => item.actor.login))].join(", ");
  return `${by} moved the head from the resume key to ${head}`;
}

// The review-lane hold comments written or edited since `lifted`, the label's
// last removal before it went on: { shas, lanes, critical }, a sha undefined
// when its marker names no head, and `critical` the { sha, lane } of each
// hold whose criteria include critical-security.
export function holdsSince(timeline, lifted) {
  const holds = timeline
    .filter((item) => laneHold(item) !== undefined && !(Math.max(Date.parse(item.created_at), Date.parse(item.updated_at ?? item.created_at)) < lifted))
    .map((item) => {
      const marker = laneHold(item);
      return { sha: HOLD_LINE.exec(marker)?.[1], lane: HOLD_LANE.exec(marker)?.[1], criteria: (HOLD_CRITERIA.exec(marker)?.[1] ?? "").split(",") };
    });
  return {
    shas: holds.map((hold) => hold.sha),
    lanes: new Set(holds.map((hold) => hold.lane)),
    critical: holds.filter((hold) => hold.criteria.includes("critical-security")).map(({ sha, lane }) => ({ sha, lane })),
  };
}

// A compare as { commits, files }, or null when its commits do not read whole.
async function compareCommits(github, repo, from, to) {
  const compare = await github("GET", `/repos/${repo}/compare/${from}...${to}`);
  const commits = compare?.commits;
  return Array.isArray(commits) && commits.length === compare.total_commits && commits.every((commit) => SHA.test(String(commit?.sha)))
    ? { commits, files: Array.isArray(compare.files) ? compare.files : [] }
    : null;
}

// Whether a unified-diff `patch` removes, or inserts beside, an old-side line
// in [first, last].
export function patchTouches(patch, [first, last]) {
  let old = 0;
  for (const line of String(patch).split("\n")) {
    const hunk = /^@@ -(\d+)/.exec(line);
    if (hunk !== null) {
      old = Number(hunk[1]);
    } else if (line.startsWith("-")) {
      if (old >= first && old <= last) {
        return true;
      }
      old += 1;
    } else if (line.startsWith("+")) {
      if (old >= first && old - 1 <= last) {
        return true;
      }
    } else if (!line.startsWith("\\")) {
      old += 1;
    }
  }
  return false;
}

// Why the pushes from held head `held` to `head` fix nothing a hold could
// name, or null. Only the pull request's own commits since `held` count (not
// reachable from the base branch, so an `Update branch` brings in none), and
// one of them must not be a merge. A critical-security hold's lane must have
// left a CRITICAL inline finding at `held`, each in a file one of those
// commits changed, on lines the diff from `held` changed. A listing that does not read whole keeps the hold.
async function heldCauseUnchanged({ github, repo, base, head, threads }, held, critical) {
  const since = await compareCommits(github, repo, held, head);
  const own = await compareCommits(github, repo, base, head);
  if (since === null || own === null) {
    return `the commits from ${held} or ${base} to ${head} did not read whole`;
  }
  const mine = new Set(own.commits.map((commit) => commit.sha));
  const fixes = since.commits.filter((commit) => mine.has(commit.sha) && Array.isArray(commit.parents) && commit.parents.length === 1);
  if (fixes.length === 0) {
    return `no commit of the pull request's own but merges moved the head off ${held}`;
  }
  const holds = critical.filter((hold) => hold.sha === held);
  if (holds.length === 0) {
    return null;
  }
  if (fixes.length > FIX_COMMITS) {
    return `more than ${FIX_COMMITS} commits moved the head off ${held}`;
  }
  const changed = new Set();
  for (const { sha } of fixes) {
    const files = (await github("GET", `/repos/${repo}/commits/${sha}`))?.files;
    if (!Array.isArray(files) || files.length >= COMPARE_FILES) {
      return `the files of ${sha} did not read whole`;
    }
    for (const file of files) {
      changed.add(file?.filename);
    }
  }
  for (const { lane } of holds) {
    const findings = threads.filter((thread) => thread.lane === lane && thread.commit === held && thread.severity.includes("CRITICAL"));
    if (findings.length === 0) {
      return `the critical-security hold at ${held} has no CRITICAL inline ${lane} finding there`;
    }
    const unchanged = findings.find((thread) => !changed.has(thread.path));
    if (unchanged !== undefined) {
      return `${unchanged.path}, which holds a CRITICAL finding at ${held}, is unchanged since then`;
    }
    const untouched = findings.find((thread) => {
      const patch = since.files.find((file) => file?.filename === thread.path)?.patch;
      return thread.lines === null || typeof patch !== "string" || !patchTouches(patch, thread.lines);
    });
    if (untouched !== undefined) {
      return `the lines of ${untouched.path} that hold a CRITICAL finding at ${held} are unchanged since then`;
    }
  }
  return null;
}

// Whether the holds since `lifted` no longer stand at `head` (`pull`'s head
// unless named): { held, holds, moved } (the held heads, how many hold
// comments, who moved the head), or { reason } saying why they stand. Only
// pushes up to `until` count, and the newest of them must land `head`, so
// ci-status judges the head the App cleared as it was at the removal.
// `reader` reads the branch activity and `checks` the lanes' runs; null
// `reader` or `trusted` keeps them.
export async function staleHoldEvidence({ github, checks, reader, repo, number, pull, timeline, lifted, trusted, head = pull.head.sha, until = Infinity }) {
  const { shas, lanes, critical } = holdsSince(timeline, lifted);
  if (shas.length === 0) {
    return { reason: "no review-lane hold comment stands since the label went on" };
  }
  if (shas.includes(undefined)) {
    return { reason: "a review-lane hold names no head this can read" };
  }
  for (const sha of new Set([head, pull.head.sha])) {
    if (shas.includes(sha)) {
      return { reason: `a review lane holds the current head ${sha}` };
    }
  }
  const changed = laneChange(await github("GET", `/repos/${repo}/compare/${pull.base.sha}...${head}`));
  if (changed !== null) {
    return { reason: `the head's lane runs prove nothing: it changes ${changed}` };
  }
  // The push that landed the newest held head anchors the trusted move.
  const ref = String(pull.head?.ref ?? "");
  let activity = null;
  if (reader !== null && ref !== "") {
    try {
      activity = await branchActivity(reader, repo, ref);
    } catch {
      activity = null;
    }
  }
  activity = Array.isArray(activity) ? activity.filter((item) => !(Date.parse(String(item?.timestamp)) > until)) : null;
  const landed = (activity ?? []).filter((item) => shas.includes(item?.after)).map((item) => Date.parse(String(item.timestamp)));
  if (landed.length === 0 || !landed.every(Number.isFinite)) {
    return { reason: "the push that landed the held head is not in the branch's activity" };
  }
  const judged = { ...pull, head: { ...pull.head, sha: head } };
  const moved = await trustedMove({ read: async () => activity, repo, pull: judged, keys: shas, since: Math.max(...landed), trusted });
  if (moved === null) {
    return { reason: "no trusted push alone moved the head off the held head" };
  }
  const reviews = [];
  for (const lane of REVIEW_LANES) {
    const review = await laneReview({ checks, repo, head }, lane);
    if (review.held !== undefined) {
      return { reason: review.held };
    }
    reviews.push(review);
  }
  const threads = await laneThreads({ github, repo, number });
  if (threads === null) {
    return { reason: "the review thread listing may be cut short" };
  }
  const findings = findingsHeld({ head, timeline, threads }, reviews, lanes);
  if (findings !== null) {
    return { reason: findings };
  }
  for (const held of new Set(shas)) {
    const unchanged = await heldCauseUnchanged({ github, repo, base: pull.base.ref, head, threads }, held, critical);
    if (unchanged !== null) {
      return { reason: unchanged };
    }
  }
  return { held: [...new Set(shas)], holds: shas.length, moved };
}

// ci-status's recheck (pr-require-checks.yml, the hold-lift step, running the
// base commit's copy of this module with its own token): after the lanes App
// removed a review-lane hold as STALE_HOLD, 0 when the hold no longer stands
// at CLEARED_SHA, the head the App's marker names, judged as it was when the
// App removed the label (its newest push then landed that head), 1 when it
// stands or anything did not read. A later head is judged by its own lanes,
// as after a person's lift, so a clean push stays green before they run.
// Environment: GH_TOKEN, GITHUB_REPOSITORY, PR_NUMBER, HEAD_SHA (the event's
// head, still the pull request's), CLEARED_SHA, HUMAN_GATED (the label),
// TRUSTED_ACTORS_PATH, GITHUB_API_URL.
export async function recheckStaleHold({ env = process.env, github } = {}) {
  try {
    const repo = env.GITHUB_REPOSITORY ?? "";
    const number = Number(env.PR_NUMBER);
    const label = env.HUMAN_GATED ?? "";
    const cleared = env.CLEARED_SHA ?? "";
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo) || !Number.isSafeInteger(number) || number < 1 || !SHA.test(env.HEAD_SHA ?? "") || !SHA.test(cleared) || label === "") {
      throw new Error("GITHUB_REPOSITORY, PR_NUMBER, HEAD_SHA, CLEARED_SHA or HUMAN_GATED is not set");
    }
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const trusted = new Set(loadTrustedList(env.TRUSTED_ACTORS_PATH).humans);
    const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
    if (pull?.head?.sha !== env.HEAD_SHA || pull.head?.repo?.full_name !== repo) {
      console.log(`stale-review-hold: #${number}'s head is no longer ${env.HEAD_SHA}`);
      return 1;
    }
    const timeline = await paginate(github, `/repos/${repo}/issues/${number}/timeline`);
    const { since, lifted } = labelHistory(timeline, label);
    const removed = timeline
      .filter((item) => item.event === "unlabeled" && same(item.label?.name, label))
      .map((item) => Date.parse(item.created_at))
      .filter((time) => time >= since);
    if (removed.length === 0) {
      console.log(`stale-review-hold: no removal of ${label} since it went on is recorded`);
      return 1;
    }
    // Judged as the App saw it: the timeline, review comments and reviews
    // written up to the removal (an edit after it still counts), whose actor
    // ci-status checked is the lanes App.
    const until = Math.min(...removed);
    const removal = timeline.find((item) => item.event === "unlabeled" && same(item.label?.name, label) && Date.parse(item.created_at) === until);
    const written = (item) => !(Date.parse(item?.created_at ?? item?.submitted_at ?? "") > until);
    const seen = timeline.filter(written);
    const stop =
      standingStop({ timeline: seen, lifted, since, bot: removal?.actor?.login ?? "", label }) ??
      ((speaker) => (speaker === undefined ? null : spokeReason(speaker, label)))(
        personSince(
          reviewEntries({
            comments: (await paginate(github, `/repos/${repo}/pulls/${number}/comments?since=${sinceParam(since - 1000)}`)).filter(written),
            reviews: (await paginate(github, `/repos/${repo}/pulls/${number}/reviews`)).filter(written),
          }),
          since,
        ),
      );
    if (stop !== null) {
      console.log(`stale-review-hold: the hold stands at ${cleared}: ${stop}`);
      return 1;
    }
    const evidence = await staleHoldEvidence({ github, checks: github, reader: github, repo, number, pull, timeline: seen, lifted, trusted, head: cleared, until });
    if (evidence.reason !== undefined) {
      console.log(`stale-review-hold: the hold stands at ${cleared}: ${evidence.reason}`);
      return 1;
    }
    console.log(`stale-review-hold: the hold at ${evidence.held.join(", ")} no longer stands at ${cleared}: ${evidence.moved}`);
    return 0;
  } catch (error) {
    console.log(`stale-review-hold: did not read: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

// The accounts a review lane's hold step adds the label as.
const LANE_LABELERS = Object.freeze(["github-actions[bot]", "claude[bot]"]);
// A label a review lane added: what to clear as STALE_HOLD, or { reason }
// saying why nothing is.
// Why something besides the review-lane holds keeps the label, from the
// timeline, or null: check-signed-commits' hold, pr-verify's credential hold, a
// lanes App (`bot`) marker
// other than an address-feedback round's or a clear's since the label went
// on, or a person who spoke since. clear-escalations and ci-status's recheck
// both run it.
function standingStop({ timeline, lifted, since, bot, label }) {
  if (openSignedCommitsHold(timeline, lifted) !== undefined) {
    return "check-signed-commits holds it: a lane commit could not be verified";
  }
  if (openCredentialHold(timeline, lifted) !== undefined) {
    return CREDENTIAL_KEPT;
  }
  const appComments = timeline.filter((item) => item.event === "commented" && isApp(item.user, bot));
  const foreign = foreignMarker(appComments, since, (line) => line === ROUND_MARKER);
  if (foreign !== undefined) {
    return `a lanes App comment since ${label} went on carries a marker: ${foreign.slice(0, 120)}`;
  }
  const speaker = personSince(timeline.flatMap(spoken), since);
  return speaker === undefined ? null : spokeReason(speaker, label);
}

async function staleReviewHold({ github, checks, repo, number, label, bot, timeline, since, lifted, reader, trusted }) {
  const stop = standingStop({ timeline, lifted, since, bot, label });
  if (stop !== null) {
    return { reason: stop };
  }
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  if (pull?.state !== "open" || pull.base?.ref !== "main" || !SHA.test(String(pull.head?.sha))) {
    return { reason: "not an open pull request into main" };
  }
  if (!(pull.labels ?? []).some((item) => same(item.name, label))) {
    return { reason: `${label} is no longer on it` };
  }
  if (outsideActorHeld(pull.labels)) {
    return { reason: OUTSIDE_ACTOR_KEPT };
  }
  const evidence = await staleHoldEvidence({ github, checks, reader, repo, number, pull, timeline, lifted, trusted });
  if (evidence.reason !== undefined) {
    return evidence;
  }
  const head = pull.head.sha;
  return {
    ...cleared(timeline, bot, since, [STALE_HOLD], head, [
    `it held \`${evidence.held.join("`, `")}\``,
    evidence.moved,
    "both review lanes passed on it with a whole review and no open CRITICAL finding",
  ]),
    holds: evidence.holds,
  };
}

// Why a stale-review-hold clear no longer stands at a fresh read of the head
// and the timeline, or null: the head moved, or the hold comments since the
// label was last removed are not the ones judged.
async function staleHoldMoved({ github, repo, number, label, result }) {
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  if (pull?.head?.sha !== result.head) {
    return `its head moved to ${pull?.head?.sha ?? "an unread head"} since it was judged`;
  }
  const timeline = await paginate(github, `/repos/${repo}/issues/${number}/timeline`);
  const { lifted } = labelHistory(timeline, label);
  if (openCredentialHold(timeline, lifted) !== undefined) {
    return CREDENTIAL_KEPT;
  }
  const holds = holdsSince(timeline, lifted).shas;
  return holds.length !== result.holds || holds.some((sha) => sha === undefined || sha === result.head) ? "a review lane wrote a hold since it was judged" : null;
}

// What to clear on `number`, or { reason } saying why nothing is.
async function verdict({ github, checks, repo, number, label, bot, mainSha, lanePrs, verify, reads, reader, trusted }) {
  const timeline = await paginate(github, `/repos/${repo}/issues/${number}/timeline`);
  // A removal lifts a review lane's hold only when a person on the trusted
  // list made it, as ci-status reads a lift; without that list none does.
  const { labeled, since, lifted, reviewLabeled } = labelHistory(timeline, label, trusted ?? new Set());
  if (LANE_LABELERS.some((login) => isApp(labeled?.actor, login))) {
    return staleReviewHold({ github, checks, repo, number, label, bot, timeline, since, lifted, reader, trusted });
  }
  if (!isApp(labeled?.actor, bot)) {
    return { reason: `${label} was last added by ${labeled?.actor?.login ?? "no one on the timeline"}, not the lanes App` };
  }
  // A comment's writes are its creation and its last edit; a tie, or a time
  // that does not parse, keeps the label.
  const held = openReviewHold(timeline, lifted, reviewLabeled);
  if (held !== undefined) {
    return { reason: `a review lane holds it: ${holdText(held).slice(0, 120)}` };
  }
  if (openSignedCommitsHold(timeline, lifted) !== undefined) {
    return { reason: "check-signed-commits holds it: a lane commit could not be verified" };
  }
  if (openCredentialHold(timeline, lifted) !== undefined) {
    return { reason: CREDENTIAL_KEPT };
  }
  // Every escalation since the label went on: a later one posts no new label
  // event, so each reason it recorded must have cleared.
  const appComments = timeline.filter((item) => item.event === "commented" && isApp(item.user, bot));
  const escalations = escalationsSince(appComments, since);
  const merged = escalations.length === 0 && pairedWithPrMerge(appComments, since) ? prMergeEscalations(appComments) : [];
  let reasons = [];
  if (merged.length === 0) {
    if (escalations.length === 0 || !(escalations[0].at - since <= PAIRED_MS)) {
      return { reason: `no pr-unblock escalation by the lanes App right after it added ${label}` };
    }
    reasons = [...new Set(escalations.map(reasonOf))];
    const decided = reasons.find((reason) => !Object.hasOwn(CHECKS, reason ?? ""));
    if (reasons.length === 0 || decided !== undefined || reasons.includes(undefined)) {
      return { reason: `an escalation reason since the label (${decided ?? "none"}) is one a person decides` };
    }
  }
  // The App also escalates for other lanes (a work-items:escalation from
  // another lane, a pr-merge marker this script does not judge) without adding
  // the label again. Any marker on an App comment written or edited since the
  // label that is not the escalation being judged or this script's own keeps
  // it, so a marker this script does not know fails closed.
  // address-feedback's round record and model-run line, which it posts after
  // a round it works on the escalated PR, are pr-unblock's own too.
  const known =
    merged.length > 0
      ? prMergeLine
      : (line) => line === ESCALATION || RESUME_KEY.test(line) || LANE_STOPPED.test(line) || line === ROUND_MARKER || MODEL_RUN.test(line);
  const foreign = foreignMarker(appComments, since, known);
  if (foreign !== undefined) {
    return { reason: `a lanes App comment since ${label} went on carries another marker: ${foreign.slice(0, 120)}` };
  }
  // Only a person speaking keeps the label; an account GitHub marks Bot does
  // not. An unknown author counts as a person.
  const speaker = personSince(timeline.flatMap(spoken), since);
  if (speaker !== undefined) {
    return { reason: spokeReason(speaker, label) };
  }
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  if (pull?.state !== "open" || pull.base?.ref !== "main" || !SHA.test(String(pull.head?.sha))) {
    return { reason: "not an open pull request into main" };
  }
  if (!(pull.labels ?? []).some((item) => same(item.name, label))) {
    return { reason: `${label} is no longer on it` };
  }
  if (outsideActorHeld(pull.labels)) {
    return { reason: OUTSIDE_ACTOR_KEPT };
  }
  const why = [];
  if (merged.length > 0) {
    const unread = merged.find(({ head }) => head === null);
    if (unread !== undefined) {
      return { reason: `the pr-merge comment carrying ${unread.marker} names no head this script can read` };
    }
    // A refusal at an old head takes the head-moved path below.
    const native = lanePrs === "native" && isApp(pull.user, bot) ? nativeRefusal(appComments, merged, label, pull.head.sha) : null;
    // A person's recorded cause stays until a person removes the label or the
    // head moves (owner decision Q-CLEAR B): no reader answer lifts it.
    if (native !== null && !laneCause(native.kind, native.reason)) {
      return { reason: `enable-auto-merge's refusal at ${pull.head.sha} is one a person clears (${native.reason})` };
    }
    if (native !== null) {
      // The review threads first: a person's reply there keeps the label
      // whatever the reader answers, so it spends none of the run's reads.
      const speaker = await threadSpeaker(github, repo, number, since);
      if (speaker !== undefined) {
        return { reason: spokeReason(speaker, label) };
      }
      if (reads.left <= 0) {
        return { reason: `enable-auto-merge's refusal waits: ${NATIVE_READS_PER_RUN} reader runs this run` };
      }
      reads.left -= 1;
      let evidence;
      try {
        evidence = await verify({ number, headRefOid: pull.head.sha, baseRefOid: pull.base?.sha }, "C3");
      } catch (error) {
        return { reason: `the gate's reader did not answer: ${escapeCommand(error?.message ?? error)}` };
      }
      const held = verifyHold(evidence, pull.head.sha);
      if (!liftsRefusal(native.kind, evidence, pull.head.sha)) {
        return { reason: `enable-auto-merge's refusal still needs a person at ${pull.head.sha}: ${held}` };
      }
      return cleared(timeline, bot, since, [REFUSAL_CLEARED], pull.head.sha, [
        `it refused this head (${native.reason})`,
        held === null ? "the gate now takes its issue link, verifier verdict and risk score" : `what refuses now is one the lanes clear: ${held}`,
      ]);
    }
    if (merged.some(({ head }) => head === pull.head.sha)) {
      return { reason: `a pr-merge escalation names the current head ${pull.head.sha}` };
    }
    reasons = [HEAD_MOVED];
    why.push(`its escalation names head \`${[...new Set(merged.map(({ head }) => head))].join("`, `")}\`, and the head is now \`${pull.head.sha}\``);
  } else {
    let red;
    const failing = () => (red ??= headFailing({ checks, repo, pull }));
    // A job-token read that fails keeps the label and leaves the run green:
    // it is retried on the next schedule.
    const read = async (fn) => {
      if (reader === null) {
        return null;
      }
      try {
        return await fn(reader);
      } catch (error) {
        console.log(`::warning title=clear-escalations::#${number}: ${escapeCommand(error?.message ?? error)}`);
        return null;
      }
    };
    const keys = escalations.map(({ body }) => RESUME_KEY.exec(body[1])?.[1]);
    let movedOnce;
    let threadsOnce;
    let speakerOnce;
    const context = { github, repo, pull, mainSha, read, escalations, bot, timeline, appComments, lifted };
    context.keysOf = (reason) => keys.filter((_, i) => reasonOf(escalations[i]) === reason);
    context.moved = () => (movedOnce ??= trustedMove({ read, repo, pull, keys, since, trusted }));
    context.threads = () => (threadsOnce ??= unresolvedThreads(context));
    context.mainMerged = (reason) => mainMergedAt(context, reason);
    context.failing = failing;
    context.speaker = () => (speakerOnce ??= threadSpeaker(github, repo, number, since));
    for (const reason of reasons) {
      const cleared = await CHECKS[reason](context);
      if (cleared?.spoke !== undefined) {
        return { reason: spokeReason(cleared.spoke, label) };
      }
      if (typeof cleared !== "string") {
        return { reason: `${reason} still holds at ${pull.head.sha}: ${cleared?.held ?? "unknown"}` };
      }
      why.push(cleared);
    }
  }
  return cleared(timeline, bot, since, reasons, pull.head.sha, why);
}

// The clear of `reasons` at `head`, and whether its comment is already posted.
function cleared(timeline, bot, since, reasons, head, why) {
  const recorded = reasons.join(",");
  const marker = clearedMarker(recorded, head);
  const explained = timeline.some(
    (item) => item.event === "commented" && isApp(item.user, bot) && Date.parse(item.created_at) >= since && lines(item.body)[0] === marker,
  );
  return { reason: null, recorded, head, why: why.join("; "), explained, since };
}

const spokeReason = (speaker, label) => `${speaker.user?.login ?? "an account"} commented or reviewed after ${label} went on`;

// `number`'s review comments written or edited after `since` and its reviews.
// A failed read throws, which keeps the label.
async function reviewActivity(github, repo, number, since) {
  const comments = await paginate(github, `/repos/${repo}/pulls/${number}/comments?since=${sinceParam(since - 1000)}`);
  const reviews = await paginate(github, `/repos/${repo}/pulls/${number}/reviews`);
  return { comments, reviews };
}

// Who spoke on `number`'s review threads or reviews after `since`, which the
// timeline misses for a reply inside an existing thread: the first person, or
// undefined. A comment counts at its last write (the `since` filter is on
// update time), so an edit after the label counts too. A failed read throws,
// which keeps the label.
async function threadSpeaker(github, repo, number, since) {
  return personSince(reviewEntries(await reviewActivity(github, repo, number, since)), since);
}

// The review threads and their speakers read again right before the label
// comes off, on every path: the reads a check makes after its own thread read
// (the gate's reader, the job token's) leave time for a person's reply inside
// an existing thread, which the timeline misses, or for a new thread. Why the
// label stays, or undefined: a person spoke after `since`, or a review thread
// was opened, by anyone, at or after `readAt` (this PR's reads began; a
// second earlier, as GitHub stamps to the second). A time that does not parse
// counts as since; a failed read throws, which keeps the label.
async function threadsSettled(github, repo, number, since, readAt, label) {
  const activity = await reviewActivity(github, repo, number, since);
  const speaker = personSince(reviewEntries(activity), since);
  if (speaker !== undefined) {
    return spokeReason(speaker, label);
  }
  const opened = activity.comments.find((comment) => comment?.in_reply_to_id == null && !(Date.parse(comment?.created_at) < readAt - 1000));
  return opened === undefined ? undefined : `a review thread was opened by ${opened.user?.login ?? "an account"} while its reads ran`;
}

// THE SESSION-BUILDER QUEUE LABEL. A fail-routed stop whose escalation-routes.json
// entry names a `label` (needs-session) puts it on before its lane-stopped
// comment, and report-escalation.sh `clear` posts success over the stop's
// failing status when a same-head retry lands, which leaves the label on.
// Every label the table names is a session label.
export const SESSION_LABELS = Object.freeze([...new Set(Object.values(ROUTES).map((entry) => entry?.label).filter((label) => typeof label === "string"))]);
const STOP_ACTIVITY = /^<!-- pr-unblock:lane-stopped activity=([a-z]+(?:-[a-z]+)*) -->$/;
const STOP_HEAD = /^- Head: `([0-9a-f]{40})`$/m;
// report-escalation.sh's status context for an activity.
const stopContext = (activity) => (activity === "resolve-conflicts" ? "pr-unblock/conflict" : `pr-unblock/${activity}`);

// A stop the new-head lift leaves on: the route marks a workflow or action
// change beyond a full-SHA pin swap, which green checks do not judge, so only
// its lane's own clear on the stop's head removes the label.
const SAME_HEAD_ONLY = Object.freeze(["dependency-workflow-unpinned"]);
// The newest status for `context` by github-actions[bot] in `statuses`
// (newest first), or undefined.
const laneStatus = (statuses, context) => statuses.find((status) => status?.context === context && status?.creator?.login === "github-actions[bot]");

// Whether the session label `label` on `number` comes off, or { reason }
// saying why it stays. It comes off only when the lanes App added it last,
// and every lanes App lane-stopped comment (one per activity, edited in
// place) written or edited since then whose reason routes to `label` is
// mended, on its own head or on a new one.
// - Same head: the newest status at the stop's head for that activity's
//   context, by github-actions[bot], is `success` and newer than the stop
//   (report-escalation.sh `clear`, after a same-head retry landed).
//   report-stop-status posts a stop's failure in a job of its own, so a
//   success older than the comment belongs to an earlier stop and proves
//   nothing.
// - New head: when the PR's head is none of those stops' heads, a stop not
//   so cleared is mended once its route is off SAME_HEAD_ONLY, the newest
//   github-actions[bot] status for its context at the current head, if any,
//   is `success`, and the current head's checks pass (checksHeld). The PR
//   and the current head are read only when some stop is not cleared on its
//   own head.
//   A lane posts a status only on a head it gates, so nothing else marks a
//   new head mended; a cause that still holds stops the lane again on the
//   new head, and that stop puts the label back.
// A stop since the label whose reason or head does not parse, none at all,
// or a read that fails keeps it. `checks` (the job token) reads the statuses
// and check runs; the lanes App token holds no statuses permission.
async function sessionVerdict({ github, checks, repo, number, label, bot }) {
  const timeline = await paginate(github, `/repos/${repo}/issues/${number}/timeline`);
  const { labeled, since } = labelHistory(timeline, label, new Set());
  if (!isApp(labeled?.actor, bot)) {
    return { reason: `${label} was last added by ${labeled?.actor?.login ?? "no one on the timeline"}, not the lanes App` };
  }
  const stops = new Map();
  for (const item of timeline) {
    const activity = item.event === "commented" && isApp(item.user, bot) ? STOP_ACTIVITY.exec(lines(item.body)[0])?.[1] : undefined;
    if (activity !== undefined) {
      stops.set(activity, item);
    }
  }
  const routed = [];
  for (const [activity, item] of stops) {
    const stoppedAt = Math.max(Date.parse(item.created_at), Date.parse(item.updated_at ?? item.created_at));
    if (stoppedAt < since) {
      continue;
    }
    const body = String(item.body);
    const reason = REASON.exec(body)?.[1];
    const head = STOP_HEAD.exec(body)?.[1];
    if (reason === undefined || head === undefined || escalationActivity(reason) !== activity) {
      return { reason: `the ${activity} stop since ${label} went on names no reason, head or activity this script can read` };
    }
    if (ROUTES[reason].label === label) {
      routed.push({ activity, reason, head, stoppedAt });
    }
  }
  if (routed.length === 0) {
    return { reason: `no lane stop routed to ${label} since it went on` };
  }
  // A read that fails keeps the label and leaves the run green.
  const guarded = async (fn) => {
    try {
      return await fn();
    } catch (error) {
      console.log(`::warning title=clear-escalations::#${number}: ${escapeCommand(error?.message ?? error)}`);
      return null;
    }
  };
  const why = [];
  const open = [];
  for (const stop of routed) {
    const context = stopContext(stop.activity);
    const statuses = await guarded(() => readStatuses(checks, repo, stop.head));
    if (statuses === null) {
      return { reason: `the statuses of ${stop.head} did not read` };
    }
    const own = laneStatus(statuses, context);
    if (own?.state === "success" && Date.parse(own.created_at) > stop.stoppedAt) {
      why.push(`${stop.reason} no longer fails ${context} at ${stop.head}`);
    } else {
      open.push({ ...stop, context, own });
    }
  }
  if (open.length === 0) {
    return { reason: null, why: why.join("; ") };
  }
  const current = (await guarded(() => github("GET", `/repos/${repo}/pulls/${number}`)))?.head?.sha;
  if (!SHA.test(String(current))) {
    return { reason: "the pull request's head did not read" };
  }
  if (routed.some(({ head }) => head === current)) {
    const { reason, context, head, own } = open[0];
    const state = own?.state === "success" ? "no success since the stop" : (own?.state ?? "no status");
    return { reason: `${reason} still fails ${context} at ${head} (${state})` };
  }
  const now = await guarded(() => readStatuses(checks, repo, current));
  if (now === null) {
    return { reason: `the statuses of ${current} did not read` };
  }
  for (const { reason, context, head } of open) {
    if (SAME_HEAD_ONLY.includes(reason)) {
      return { reason: `${reason} stopped at ${head}, and only its lane's clear on that head lifts ${label}: green checks do not judge its workflow change` };
    }
    const newest = laneStatus(now, context);
    if (newest !== undefined && newest.state !== "success") {
      return { reason: `${reason}'s ${context} reads ${newest.state} at the new head ${current}` };
    }
    why.push(`${reason} stopped at ${head}, and no ${context} status fails at the new head ${current}`);
  }
  const held = await checksHeld((fn) => guarded(() => fn(checks)), repo, current);
  if (held !== null) {
    return { reason: `${label} stays at the new head: ${held}` };
  }
  why.push(`no check other than ${AGGREGATE} fails, runs or was cancelled at ${current}`);
  return { reason: null, why: why.join("; ") };
}

// Takes each session label off where sessionVerdict finds its stop cleared,
// reading at most SESSION_CHECKS_PER_RUN pull requests a label a run. No
// comment: the label queues a session and holds nothing a person must see
// lifted. The failures counted.
async function clearSessionLabels({ github, checks, repo, bot, runNumber }) {
  let failed = 0;
  for (const label of SESSION_LABELS) {
    const held = (await paginate(github, `/repos/${repo}/issues?state=open&labels=${encodeURIComponent(label)}`)).filter(
      (item) => item.pull_request && Number.isSafeInteger(item.number) && item.number > 0,
    );
    for (const [index, { number }] of rotated(held, runNumber).entries()) {
      if (index >= SESSION_CHECKS_PER_RUN) {
        console.log(`clear-escalations: #${number} ${label} not checked: ${SESSION_CHECKS_PER_RUN} read this run`);
        continue;
      }
      try {
        const result = await sessionVerdict({ github, checks, repo, number, label, bot });
        if (result.reason !== null) {
          console.log(`clear-escalations: #${number} ${label} kept: ${result.reason}`);
          continue;
        }
        await github("DELETE", `/repos/${repo}/issues/${number}/labels/${encodeURIComponent(label)}`);
        console.log(`clear-escalations: #${number} ${label} cleared: ${result.why}`);
      } catch (error) {
        failed += 1;
        reportError(number, error);
      }
    }
  }
  return failed;
}

// The ids whose push is a trusted move: every `human` of trusted-actors.json,
// matched by id. Not the lanes App: every lane that sets check-trusted-trigger's
// denied-actor-ids denies its sender id, and its own push must not clear its
// own stop.
// Null when the list does not read.
function trustedIds(path) {
  try {
    return new Set(loadTrustedList(path).humans);
  } catch (error) {
    console.log(`clear-escalations: no stop clears on a trusted move: ${escapeCommand(error?.message ?? error)}`);
    return null;
  }
}

export async function main({ env = process.env, github, checks, verify, reader } = {}) {
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("clear-escalations: the lanes kill switch stops this run; nothing read or removed");
      return 0;
    }
    const repo = env.GITHUB_REPOSITORY;
    const bot = env.LANES_BOT_LOGIN || DEFAULT_BOT;
    const label = humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/.work-item-tracker.json");
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    checks ??= createGitHub({ token: env.CHECKS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    verify ??= pythonVerify(env);
    const reads = { left: NATIVE_READS_PER_RUN };
    // The job's own token reads branch activity, check runs and main's
    // history; without it, or without the trusted list, no stop clears on a
    // trusted move.
    reader = env.BABYSIT_VERIFY_GH_TOKEN ? (reader ?? createGitHub({ token: env.BABYSIT_VERIFY_GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined })) : null;
    const trusted = trustedIds(env.TRUSTED_ACTORS_PATH || ".base/.github/standards/trusted-actors/trusted-actors.json");
    const tip = await github("GET", `/repos/${repo}/git/ref/heads/main`);
    const mainSha = tip?.ref === "refs/heads/main" ? tip.object?.sha : undefined;
    if (!SHA.test(String(mainSha))) {
      throw new Error("main's tip has no commit SHA");
    }
    const held = (await paginate(github, `/repos/${repo}/issues?state=open&labels=${encodeURIComponent(label)}`)).filter(
      (item) => item.pull_request && Number.isSafeInteger(item.number) && item.number > 0,
    );
    let failed = 0;
    let cleared = 0;
    for (const { number, labels } of rotated(held, Number(env.GITHUB_RUN_NUMBER))) {
      if (outsideActorHeld(labels)) {
        console.log(`clear-escalations: #${number} kept: ${OUTSIDE_ACTOR_KEPT}`);
        continue;
      }
      if (cleared >= CLEARS_PER_RUN) {
        console.log(`clear-escalations: #${number} not checked: ${CLEARS_PER_RUN} cleared this run`);
        continue;
      }
      try {
        const readAt = Date.now();
        const result = await verdict({ github, checks, repo, number, label, bot, mainSha, lanePrs: env.LANE_PRS, verify, reads, reader, trusted });
        if (result.reason !== null) {
          console.log(`clear-escalations: #${number} kept: ${result.reason}`);
          continue;
        }
        // The review threads again right before the removal, on every path,
        // even when a check read them earlier (threadsSettled).
        const unsettled = await threadsSettled(github, repo, number, result.since, readAt, label);
        if (unsettled !== undefined) {
          console.log(`clear-escalations: #${number} kept: ${unsettled}`);
          continue;
        }
        // A stale hold is judged again before the comment and again before
        // the delete: a hold a lane wrote since (the label already on, so no
        // labeled event) or a moved head keeps it, with no comment saying
        // the label came off.
        const recheck = async () => (result.recorded === STALE_HOLD ? await staleHoldMoved({ github, repo, number, label, result }) : null);
        let moved = await recheck();
        // The comment first: a failed removal is retried by the next sweep,
        // which finds the comment and posts no second one.
        const base = `/repos/${repo}/issues/${number}`;
        if (moved === null && !result.explained) {
          await github("POST", `${base}/comments`, { body: clearedComment(result.recorded, result.head, result.why, label) });
          moved = await recheck();
        }
        if (moved !== null) {
          console.log(`clear-escalations: #${number} kept: ${moved}`);
          continue;
        }
        await github("DELETE", `${base}/labels/${encodeURIComponent(label)}`);
        cleared += 1;
        console.log(`clear-escalations: #${number} cleared: ${result.recorded} no longer holds at ${result.head}`);
      } catch (error) {
        failed += 1;
        reportError(number, error);
      }
    }
    failed += await clearSessionLabels({ github, checks, repo, bot, runNumber: Number(env.GITHUB_RUN_NUMBER) });
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=clear-escalations::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
