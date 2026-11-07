#!/usr/bin/env node
// report-outcome.mjs: the work-resolve-issue lane's report-outcome leaf. Reads
// what the resolve-issue run left and acts on the issue, with no model:
//
//   done      opens a ready PR from the run's branch: the body starts
//             `Closes #<issue>`, or `Refs: #<issue>` and a Remaining work
//             section when the run's `remaining` names the parts of the
//             issue it leaves for later work (a malformed list counts as
//             none); the merge lane reads a plain `Refs:` issue as it reads
//             a closing one. Under that line go the `Refs:` and `Siblings:`
//             lines the trusted issue's done-when asks the body to carry
//             (linkageLines). The title is the run's Conventional
//             Commits title, with any `#` or `/` a space
//             (else one built from the issue title), and the body carries
//             the hold line when a human must merge it. The PR gets no label:
//             the work class lives on the issue only. The merge gate reads no
//             work class and treats every lane PR as C2, so the hold line
//             carries the class floor. The body fills the PR body contract's
//             sections from the outcome's summary, changes, verification and
//             not_done, and its Verification section the runner's check
//             results (RUNNER_CHECKS). A done outcome whose not_done holds a
//             required check is stopped, and so is one whose runner checks
//             failed or cannot be read for the branch's current tip, whatever
//             the outcome file says.
//   Every stop below takes its route from stop-routes.json (stop-routes.mjs):
//   The issue's state is its Work status field (models.issue-status); no
//   route writes a status label. hold hands the issue to a person as pushback
//   does; host-run adds the host-run label; attended adds the attended label;
//   retry keeps Work status agent-ready, so
//   work-unblock restarts it, up to limits.stop-retries; wait keeps
//   agent-ready and names the open pull request the run waits on, so
//   work-unblock restarts it once that pull request merges or closes (a
//   pull request that is not open, or that neither the lanes App nor a
//   listed human opened, retries instead); intake moves
//   Work status from agent-ready to needs-triage, so the triage sweep sends
//   the issue back through intake; park sets Work status confirmed beside admission's comment naming the reason, as
//   admission parks a refusal no person answers; close closes the issue as
//   completed (an already-done
//   stop only once its cited commit or pull request is on the default
//   branch and its commit message closes the issue, doneEvidence, and a
//   verified-done stop only once VERIFY_CLOSE's sub-issues hold, else each
//   retries); fail moves Work status to needs-triage and adds no label. A
//   route other than hold carries no escalation marker.
//
//   pushback  a reason that opens with a hold code (security-risk,
//             cost-risk, design-change, intent-change) takes that row; else
//             cause intent or intent-change (as stop-routes.mjs causeName
//             normalizes the cause) comments why, adds
//             the human-gated Work status; else a cause
//             naming a hold code takes that row; else a reason opening with
//             a host-run or attended code takes that row, or security-risk's
//             hold when runCode reads a security risk after the code (owner
//             decision 2026-10-29); else pushback-means (stop-routes.json),
//             one intake round. A pushback-means whose words (reason, else
//             summary) or cause read as a security risk (runCode, any code
//             ending) goes to intake with no means framing and a `security`
//             marker; a spent intake round that is itself such a stop holds
//             as security-risk, so a leak the run states again reaches a
//             person.
//             When a listed human's newest comment, posted since the lane's
//             last outcome comment, does not open with DECISION_LINE, the
//             comment links it and shows the line, since the lane counts no
//             other comment as an answer.
//   redispatch a pushback, intent-change, design-change or cost-risk hold
//             whose answer, a listed human's decision comment or intake's
//             refinement, was posted after the run's admission (lateRecord),
//             which the run never read: instead of the hold it posts a
//             redispatch record naming that comment, then a fresh admission
//             record (lib/admission-record.mjs) and the App's restart of the
//             Work status field (remove, then set agent-ready), so the fresh
//             run freezes after the answer and reads it; a re-run of this run
//             finishes what did not land (redispatch).
//   stopped   comments why, takes its stop's route, and names the branch
//             that holds any partial work. A missing or
//             invalid outcome file is stopped; with a scan refusal marker
//             (SCAN_REFUSED_DIR) the comment names the refusal instead, and
//             otherwise, when lane.json's class says the issue file was never
//             written (readIssueStop), it names why.
//   limited   a run that wrote no readable outcome file and whose lane.json
//             carries class rate-limit (the run hit its credential's usage
//             limit before it could report): comments once with the
//             limited marker naming when the limit resets, keeps agent-ready
//             and adds no label, so work-unblock restarts it after the reset.
//   turn-cap  a run that wrote no readable outcome file and whose lane.json
//             carries class max-turns, or run-claude-cli's leg timeout
//             (class timeout): comments with the turn-cap marker,
//             naming the cap and the branch. While limits.turn-cap-restarts
//             allows a restart since a listed human last set Work status
//             agent-ready (humanSince), it keeps agent-ready and work-unblock restarts the issue; past
//             that it takes turn-cap-spent's route.
//   reused   the resolve-issue run skipped the work for a lane branch an
//             earlier run left with commits and no report (REUSE_BRANCH):
//             the earlier outcome counts only when this run's artifact names
//             that branch (a re-run attempt); with none readable, a held PR
//             opens from it, whatever the limit record. It carries the
//             read-only summary pass's summary when the summary names this
//             issue, the branch and its current tip; else fixed text only.
//             The runner's check results are listed and never stop it: the
//             PR always carries the hold line, so a human reads them.
//   refused  a done run whose patch apply-issue-patch refused
//             (ESCALATION_REASON patch-protected-path, patch-credential,
//             patch-invalid or patch-not-applied), or whose apply job failed
//             before giving one (patch-apply-failed), stops like stopped,
//             naming the reason; only patch-credential reaches a person, and
//             it does on any exit, ahead of any funding, limit or turn-cap
//             record.
//             patch-empty changes nothing, as the run committed nothing.
//   dimension the issue's dimensions skipped the run before any model turn
//             (DIMENSION_SKIP): takes the reason's route, naming the next
//             step, with no person: research-first and probe-first park at
//             status: confirmed, and split-required goes back through intake,
//             whose split files its sub-issues. No outcome file is read.
//   outside  the admit job stopped the run because the issue's author is
//             neither a listed human nor the lanes App (DIMENSION_SKIP
//             outside-author): comments that a listed human re-files the work
//             as a new issue (once: a re-run finds its own comment) and
//             moves Work status to needs-triage, with no label, since a
//             retry stops again. No outcome file is read.
//   stale    the read runner stopped on stale workflow files before any model
//             turn (DIMENSION_SKIP workflow-stale): re-fires the issue at once
//             on main's files (refireStale): the App's Work status restart,
//             gated on the field reading agent-ready and on an admission (the
//             App's admission record or a listed human's agent-ready set). No
//             outcome file is read.
//
// Run from the base copy. It reads only the outcome directory and the GitHub
// API, and never writes to a branch.
//
// `--find-prior` runs before the resolve-issue mint instead, with the job's
// read-only token, and writes the step outputs `proceed`, `skip-reason` and
// `reuse-branch` (see findPrior).
//
// Environment:
//   GH_TOKEN            token with pull-requests: write and issues: write
//                       (--find-prior: the job's read-only GITHUB_TOKEN)
//   GITHUB_REPOSITORY   owner/repo
//   ISSUE_NUMBER        the issue the lane worked
//   WORK_OUTCOME_DIR    holds work-outcome.json (written by the skill, so
//                       untrusted) and lane.json (written by the runner: the
//                       lane branch, the run's failure `class`, its limit
//                       `resets`, its `max-turns`, the `turns` it took and
//                       the `resume` branch a resumed run continued). Code the model started can
//                       rewrite this artifact, so check results are never
//                       read from it.
//   RUNNER_CHECKS       work-resolve-issue.yml's run-checks job output, where
//                       no model ran: each activity check run from the base
//                       copy against the lane branch. Empty when that job did
//                       not succeed.
//   REUSE_BRANCH        the lane branch --find-prior chose, or empty
//   ESCALATION_REASON   apply-issue-patch's escalation reason (a PATCH_REASONS
//                       key), or empty
//   SCAN_REFUSED_DIR    the read runner's scan-refusal markers for this run,
//                       when its scan job refused the run's output and so
//                       uploaded no outcome (see readScanRefusal)
//   DIMENSION_SKIP      split-required, research-first or probe-first when
//                       the issue dimensions skipped the run, or
//                       outside-author when the admit job stopped it on the
//                       issue's author (work-resolve-issue.yml report-skip),
//                       or workflow-stale when a resolve-issue call stopped on
//                       stale workflow files (resolve-issue-stale), else empty
//   VERIFY_CLOSE        the admit job's verify-close output: a finished
//                       parent's sub-issue numbers, comma-joined, each closed
//                       as completed by a trusted close (check-blockers.mjs),
//                       else empty. A verified-done stop closes only when the
//                       issue's sub-issues, read fresh, are all closed as
//                       completed and each is one of these (parentDone), and
//                       the run neither committed nor resumed a branch; else
//                       it retries
//   GITHUB_WORKFLOW_SHA workflow-stale: the commit the run's workflow files
//                       come from
//   REUSE_SUMMARY_DIR   on a reuse, holds the summary pass's reuse-summary.json
//                       (runner-written issue, branch and tip; model output)
//   TRACKER_CONFIG      the base tracker binding, for the human-gated label
//   RESOLVED_CONFIG     resolve-config's output for this run (default
//                       $RUNNER_TEMP/resolved-config.json), for the denied
//                       paths and the limits
//   LANES_BOT_LOGIN     the lanes App bot login, the only author of an open PR
//                       a rerun reuses (default melodic-automation-lanes[bot])
//   TRUSTED_ACTORS      trusted-actors.json from the base, whose humans may
//                       apply the merge: human hold, and whose comments a
//                       pushback reads
//   TRUSTED_ACTORS_PATH --find-prior: trusted-actors.json from the default
//                       branch tip, whose humans' closing PRs stop the lane
//   APP_SENDER_ID       the lanes App's user id, whose admission records and
//                       field restarts count (else the trusted-actor list's
//                       LANES_BOT_LOGIN entry)
//   GITHUB_OUTPUT       --find-prior: the step output file
//   GITHUB_API_URL, GITHUB_SERVER_URL, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT
//                       (the attempt whose scan-refusal markers are read)
import { appendFileSync, lstatSync, readdirSync, readFileSync } from "node:fs";
import { join, posix, resolve } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { LIMIT_DEFAULTS, clampReset, readLimits } from "./limits.mjs";
import { networkError, retryFetch } from "./retry-fetch.mjs";
import { refusalText, sayWhy } from "../lib/admission-comment.mjs";
import { doneEvidence, parentDone, RUN_WORDS, stopLine } from "../lib/done-evidence.mjs";
import { personReasonLines } from "../lib/stop-reason.mjs";
import { OUTSIDE_ACTOR_LABEL, trackerBindingText, UNTRUSTED_LABELS, visibleLines } from "../pr-merge/merge-holds.mjs";
import { ATTENDED_LABEL, causeName, HOST_RUN_LABEL, leadingCode, runCode, securityWord, STOP_ROUTES, stopFault, stopReasonCode, stopRetries, stopRoute, stopWhy } from "./stop-routes.mjs";

export { doneEvidence };

export const HOLD_LINE = "Hold: a human merges this";
// The label a held PR carries from its opening. The hold line is body text the
// lanes App can edit; ci-status fails while this label is on, and removing it
// lifts the hold.
export const HOLD_LABEL = "do-not-merge";
const EXITS = new Set(["done", "pushback", "stopped"]);
// The causes a pushback that reaches a person names: an intent question.
const PUSHBACK_CAUSES = new Set(["intent", "intent-change"]);
// A pushback's stop: the hold row its reason or its cause explicitly opens
// with (security-risk, cost-risk, design-change, intent-change); else pushback for
// cause intent; else the hold row its cause names; else, for a reason opening
// with a host-run or attended code, runCode's reading: that code, or
// security-risk when it names a security risk after the code (owner decision
// 2026-10-29); else pushback-means, so intake's own intent, security and cost
// rules judge it, with routeStop's security reading (pushbackSecurity).
const PUSHBACK_LANE_ROUTES = new Set(["host-run", "attended"]);
const pushbackStop = (outcome) => {
  const code = leadingCode(outcome.reason);
  if (code && stopRoute(code) === "hold") return code;
  const causeCode = leadingCode(outcome.cause);
  if (causeCode && stopRoute(causeCode) === "hold") return causeCode;
  const cause = causeName(outcome.cause);
  if (PUSHBACK_CAUSES.has(cause)) return "pushback";
  if (Object.hasOwn(STOP_ROUTES, cause) && STOP_ROUTES[cause].code === true && stopRoute(cause) === "hold") return cause;
  return PUSHBACK_LANE_ROUTES.has(stopRoute(code)) ? runCode(outcome.reason) : "pushback-means";
};
// A pushback-means stop any of whose words a comment can show (the reason,
// the summary, each not-done item) or whose cause reads as a security risk
// after any code, or with none. Intake judges it once with no means framing
// (stopPlan's neutral text) and its marker carries `security`; a spent
// intake round that is itself such a stop holds as security-risk (routeStop),
// so a real security risk the run names again never ends without a person.
const stopWords = (outcome) =>
  [outcome?.reason, outcome?.summary, outcome?.cause, ...(outcome?.notDone ?? []).map((item) => item?.what)].filter(
    (words) => typeof words === "string" && words,
  );
const pushbackSecurity = (stop, outcome) =>
  stop === "pushback-means" && stopWords(outcome).some((words) => runCode(words, { anyCodeEnds: true }) === "security-risk");
// The word a security-risk hold read in the run's words, for handBack; "" when
// the reason or the cause opens with or names a hold code, which holds on its own.
const heldWord = (outcome) =>
  [leadingCode(outcome?.reason), leadingCode(outcome?.cause), causeName(outcome?.cause)].some((code) => stopRoute(code) === "hold")
    ? ""
    : (stopWords(outcome).map(securityWord).find(Boolean) ?? "");
// The subject allows no `#`, `/` or `GH-<digit>`, so the squash commit title
// cannot name an issue to close.
const PREFIX = /^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z0-9._-]+\))?!?: /;
const SUBJECT = /^(?!.*\bGH-\d)[A-Za-z0-9][A-Za-z0-9 ,.:;()'"`!?+=_-]{0,98}$/i;
const SUBJECT_MAX = 99;

// A subject with every character SUBJECT refuses made a space, `GH-<digit>`
// split, starting at a letter or digit, and cut at a word to SUBJECT_MAX;
// empty when nothing is left.
function subjectFrom(text) {
  let subject = text
    .replaceAll(/[^A-Za-z0-9 ,.:;()'"`!?+=_-]+/g, " ")
    .replaceAll(/\b(GH)-(?=\d)/gi, "$1 ")
    .replaceAll(/\s+/g, " ")
    .replace(/^[^A-Za-z0-9]+/, "")
    .trimEnd();
  if (subject.length > SUBJECT_MAX) {
    const cut = subject.slice(0, SUBJECT_MAX + 1);
    subject = cut.slice(0, cut.lastIndexOf(" ") > 0 ? cut.lastIndexOf(" ") : SUBJECT_MAX);
  }
  return subject.replace(/[ ,:;-]+$/, "");
}

// A Conventional Commits title from `text`: its own type and scope when it
// opens with them, else `fix:`; empty when no subject is left.
function conventionalFrom(text) {
  const prefix = PREFIX.exec(text)?.[0] ?? "";
  const subject = subjectFrom(text.slice(prefix.length));
  return subject ? `${prefix || "fix: "}${subject}` : "";
}

// The PR title: the run's when valid; else the run's with the refused
// characters made spaces, when it opens with a type; else one from the issue
// title; else one from the issue number.
function prTitle(runTitle, issueTitle, issueNumber) {
  const match = PREFIX.exec(runTitle);
  if (match && SUBJECT.test(runTitle.slice(match[0].length))) {
    return runTitle;
  }
  return (match && conventionalFrom(runTitle)) || conventionalFrom(issueTitle) || `fix: resolve issue ${issueNumber}`;
}
// Work a human merges: an issue carrying one of UNTRUSTED_LABELS, a trust
// hold and the one label read here, and any diff that touches a path the merge
// lane refuses (merge.diff-check.denied-paths in the base pr-pipeline.yaml),
// so the two lists cannot drift apart. No other work class holds.
// An owner decision that a person merges the issue's PR. It holds only when the
// lane's labeler check passes: the newest `labeled` event is a listed human's
// (by id) or the lanes App's, so no one else can add the hold or stand in for it.
export const HUMAN_MERGE_LABEL = "merge: human";
export function trustedLabeler(events, label, { bot, humans }) {
  const last = events.filter((event) => event?.event === "labeled" && event.label?.name === label).at(-1);
  return last !== undefined && (last.actor?.login === bot || humans.has(last.actor?.id));
}
const MAX_TEXT = 3000;
const MAX_ITEMS = 20;
const MAX_ITEM = 300;
// GET /compare lists at most this many files, so a listing this long may
// hide a denied path.
const COMPARE_FILES_CAP = 300;

// A limit stop with no reset time is taken to reset `limits.fallback-reset`
// hours after the run: the shortest plan limit is a five-hour session window
// (https://support.claude.com/en/articles/11145838). work-unblock takes
// clampReset from here.
export { clampReset };
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?Z$/;
// The attended queue's escalation marker (work-items reference
// escalation-marker.md): the first line of every comment that hands the issue
// to a person, so /work-items:attend-queue lists it as escalated. The outcome
// marker follows on the next line.
export const ESCALATION_MARKER = "<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->";
const escalated = (lines) => [ESCALATION_MARKER, ...lines];
// The lane name its stop-reason markers carry.
const LANE = "work-resolve-issue";
const MARKER = /^(?:<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\r?\n)?<!-- work-resolve-issue outcome=([a-z]+(?:-[a-z]+)*)(?: (security))?(?: resets=(\S+))?(?: cap=(\d+))?(?: pr=(\d+))?(?: run=(\d+))?(?: branch=(resumed))?(?: credential=(ISSUE_LANE_CLAUDE_API_KEY|ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN|FALLBACK_CLAUDE_CODE_OAUTH_TOKEN))?(?: fallback=(credit-stop|no-key))? -->/;

// `branch=resumed` marks a resumed run that kept no branch of its own, so its
// work is still on the branch it resumed (see findPrior).
const resumedTag = (yes) => (yes ? " branch=resumed" : "");

// The secret NAME a run's leg used and why it fell back, from lane.json, which
// the run could rewrite. Only the names run-claude-cli records for role
// issue-lane and the reasons the collect step writes pass, so a rewritten
// lane.json cannot carry any other value (an encoded token) into the marker.
const CREDENTIALS = new Set(["ISSUE_LANE_CLAUDE_API_KEY", "ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN", "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN"]);
const FALLBACKS = new Set(["credit-stop", "no-key"]);
export function readLaneCredential(dir) {
  let lane;
  try {
    lane = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"));
  } catch {
    return {};
  }
  return {
    ...(CREDENTIALS.has(lane?.credential) && { credential: lane.credential }),
    ...(FALLBACKS.has(lane?.fallback) && { fallback: lane.fallback }),
  };
}

// The plan with ` credential=<NAME> fallback=<reason>` (each when valid)
// closing its outcome marker line; a line already tagged is left as it is.
export function withCredential(plan, { credential, fallback } = {}) {
  const tag = `${CREDENTIALS.has(credential) ? ` credential=${credential}` : ""}${FALLBACKS.has(fallback) ? ` fallback=${fallback}` : ""}`;
  if (!tag || typeof plan?.comment !== "string") {
    return plan;
  }
  return { ...plan, comment: plan.comment.replace(/^(<!-- work-resolve-issue outcome=(?:(?! credential=| fallback=)[^\n])*?) -->/m, `$1${tag} -->`) };
}

// The marker a limited run leaves on its issue; work-unblock reads it back.
export const limitedMarker = ({ resets, runId, onResumed = false }) =>
  `<!-- work-resolve-issue outcome=limited resets=${resets} run=${runId || 0}${resumedTag(onResumed)} -->`;

// The marker a run that reached its turn cap leaves, restarted or handed back.
export const turnCapMarker = ({ cap, runId, onResumed = false }) =>
  `<!-- work-resolve-issue outcome=turn-cap${cap ? ` cap=${cap}` : ""}${runId ? ` run=${runId}` : ""}${resumedTag(onResumed)} -->`;

// The marker of a refs-hold comment: the App's needs-human hold on the issue
// of a Refs PR, which work-unblock lifts once that PR merges. report-outcome
// sets none, since the merge lane merges a plain `Refs:` PR as a closing one.
export const refsHoldMarker = (pr) => `<!-- work-resolve-issue refs-hold #${pr} -->`;

// {outcome, resets, run, onResumed, pr?, security?, credential?, fallback?} from a comment body that opens with the lane's
// marker, alone or after ESCALATION_MARKER, or null. resets is epoch milliseconds, or null when absent or
// unreadable; onResumed is true for `branch=resumed`; security is true on an
// intake marker a pushbackSecurity stop left.
export function parseOutcomeMarker(body) {
  const match = MARKER.exec(String(body ?? ""));
  if (!match) {
    return null;
  }
  const resets = ISO.test(match[3] ?? "") ? Date.parse(match[3]) : Number.NaN;
  return {
    outcome: match[1],
    resets: Number.isFinite(resets) ? resets : null,
    run: match[6] ?? "",
    onResumed: match[7] === "resumed",
    ...(match[8] && { credential: match[8] }),
    ...(match[9] && { fallback: match[9] }),
    ...(match[5] && { pr: match[5] }),
    ...(match[2] && { security: true }),
  };
}

// `value` cut to `cap` UTF-16 units at its last whitespace, `tidy` applied,
// and CUT added; a single token longer than the cap is cut hard, never inside
// a surrogate pair. Text within the cap is only tidied; a cut that keeps only
// whitespace is empty.
const CUT = "…";
const clip = (value, cap, tidy = (kept) => kept) => {
  if (value.length <= cap) {
    return tidy(value);
  }
  const head = value.slice(0, cap - CUT.length + 1);
  const words = head.slice(0, head.search(/\s\S*$/) + 1).trimEnd();
  const kept = tidy(words || head.slice(0, -1).replace(/[\uD800-\uDBFF]$/, "")).trimEnd();
  return kept && `${kept}${CUT}`;
};

const stopped = (reason) => ({ exit: "stopped", reason, title: "", summary: "", changes: [], verification: [], notDone: [], steps: [] });
const text = (value) => (typeof value === "string" ? clip(value, MAX_TEXT) : "");
const list = (value) =>
  Array.isArray(value) ? value.filter((item) => typeof item === "string").slice(0, MAX_ITEMS).map((item) => clip(item, MAX_ITEM)) : [];
// A not_done entry is a string or {what, required}; required marks a check the
// run had to pass and did not, and counts whatever `what` holds.
const notDoneList = (value) =>
  (Array.isArray(value) ? value : [])
    .map((item) =>
      typeof item === "string"
        ? { what: item, required: false }
        : item?.required === true
          ? { what: typeof item.what === "string" ? item.what : "A required check the run did not name.", required: true }
          : typeof item?.what === "string"
            ? { what: item.what, required: false }
            : null,
    )
    .filter(Boolean)
    .slice(0, MAX_ITEMS)
    .map(({ what, required }) => ({ what: clip(what, MAX_ITEM), required }));

// The prep steps the run reports, each {activity, result}, both strings;
// post-statuses.mjs decides which of them it posts.
const stepList = (value) =>
  (Array.isArray(value) ? value : [])
    .filter((item) => typeof item?.activity === "string" && typeof item?.result === "string")
    .slice(0, MAX_ITEMS)
    .map(({ activity, result }) => ({ activity: activity.slice(0, 40), result: result.slice(0, 20) }));

// The merge lane's denied-path globs from the resolved config; an empty list
// denies no path. Null, which holds every PR, when the file cannot be read or
// parsed, or the value is missing, not a list, or holds a non-string.
export function readHoldPaths(path) {
  try {
    const paths = JSON.parse(readFileSync(path, "utf8"))?.merge?.["diff-check"]?.["denied-paths"];
    return Array.isArray(paths) && paths.every((glob) => typeof glob === "string") ? paths : null;
  } catch {
    return null;
  }
}

// The denied paths a PR holds on: readHoldPaths while
// merge.diff-check.path-holds is on, none while it is absent or false (owner
// decisions Q15 and Q16; merge-holds.mjs pathHoldsOf reads it alike). An
// unreadable config still holds.
export function heldPaths(path) {
  const paths = readHoldPaths(path);
  try {
    const on = JSON.parse(readFileSync(path, "utf8"))?.merge?.["diff-check"]?.["path-holds"];
    return paths !== null && [undefined, null, false, "false"].includes(on) ? [] : paths;
  } catch {
    return paths;
  }
}

// The read runner's scan refusal markers, the ones address-feedback.mjs
// scanRefusal reads; the runner copies only this script's directory, so it
// cannot import that one. `patch` when every marker names a patch over its
// cap, `fault` when they name only that or a mix of it and `patch` (the scan
// faulted, finding no credential), `output` when any names another (it may be
// a credential shape), so a mixed set fails closed; '' for none or an
// unreadable directory: a failed
// download claims no refusal here, since the hand-back would name a false cause. Only
// the current attempt's markers count (the download pattern spans every
// attempt's), and with no readable attempt none does. A
// marker's text only picks one of the fixed sentences below, so a forged one
// puts nothing of its own in the comment.
const ATTEMPT = /^[1-9][0-9]{0,4}$/;
export function readScanRefusal(dir, attempt) {
  if (!ATTEMPT.test(attempt ?? "")) return "";
  const markerFile = new RegExp(`^scan-refused-${attempt}(-rung-up)?\\.txt$`);
  let kinds;
  try {
    kinds = readdirSync(dir)
      .filter((name) => markerFile.test(name) && lstatSync(join(dir, name)).isFile())
      .map((name) => readFileSync(join(dir, name), "utf8").trim());
  } catch {
    return "";
  }
  if (kinds.length === 0) return "";
  if (kinds.every((kind) => kind === "patch")) return "patch";
  return kinds.every((kind) => kind === "patch" || kind === "fault") ? "fault" : "output";
}

// The scan job's refusals, as its decode step names them.
export const SCAN_REFUSALS = {
  patch: "The scan job refused the run's output, so nothing was published: too-large: the patch was over its 262144-byte cap. The run's log names its size.",
  output: "The scan job refused the run's output, so nothing was published. The run's log names why.",
  fault: "The scan job could not finish, or the patch did not apply to the head it scans, so nothing was published. The run's log names which; neither says anything about a credential.",
};

// The scan job's collect-refused output, as collect-patch.sh's exit 3 sets it.
export const COLLECT_REFUSED =
  "The run left content, a link or a directory at a name the patch collector only accepts as an empty stub (such as `.npmrc`, `.env` or a lockfile), so no patch was collected and nothing was published. The run's log names the file.";

// The skill's outcome file, checked as data. Anything unreadable is stopped.
export function readOutcome(path) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return { ...stopped("The run wrote no readable outcome file, so it stopped before it finished."), unread: true, stop: "outcome-unread" };
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed) || !EXITS.has(parsed.exit)) {
    return { ...stopped("The run's outcome file names no known exit (done, pushback or stopped)."), unread: true, stop: "outcome-invalid" };
  }
  return {
    exit: parsed.exit,
    reason: text(parsed.reason),
    cause: text(parsed.cause),
    title: text(parsed.title),
    summary: text(parsed.summary),
    changes: list(parsed.changes),
    verification: list(parsed.verification),
    notDone: notDoneList(parsed.not_done),
    steps: stepList(parsed.steps),
    remaining: remainingList(parsed.remaining),
  };
}

// The parts of the issue the PR leaves for later work: 1 to MAX_ITEMS strings,
// each with text other than CUT left in the bullet it renders as. Anything
// else is empty, so the PR closes the issue.
function remainingList(value) {
  const items = Array.isArray(value) && value.length <= MAX_ITEMS && value.every((item) => typeof item === "string") ? value.map((item) => clip(item, MAX_ITEM)) : [];
  return items.every((item) => bullets([item]).slice(2).replace(CUT, "")) ? items : [];
}

// Model text is data. HTML comments go; `&` is escaped first, so no entity
// can spell `@` or `#`, then raw HTML (`<`, `>`) and link syntax (`[`, `]`,
// which could hide a reference definition). `@` is dropped so nothing
// mentions anyone, and issue references are broken: squash merge copies the
// body as plain text, so `#` becomes a full-width ＃, `GH-` and `/issues/` or
// `/pull/` gain a space, and no closing keyword in it can close an issue.
// `://` and `www.` gain a space too, so no bare URL autolinks.
// Control characters other than newline go, and so do format characters
// (bidi overrides, zero-width), which can make text read other than it is.
// The cap applies after escaping, at a word (clip), and drops a half-cut
// entity or escape. A file path keeps its comments, escaped, so the whole
// name shows.
const neutral = (value, cap, { path = false } = {}) =>
  clip(
    (path ? value : value.replaceAll(/<!--[\s\S]*?(-->|$)/g, ""))
      .replaceAll(/\p{Cf}/gu, "")
      .replaceAll("\r\n", "\n")
      .replaceAll(/[\u0000-\u0009\u000b-\u001f\u007f-\u009f]/g, " ")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("[", "\\[")
      .replaceAll("]", "\\]")
      .replaceAll("@", "")
      .replaceAll("#", "＃")
      .replaceAll(/\bGH-/gi, "GH -")
      .replaceAll(/\/(issues|pull)\//gi, "/$1 /")
      .replaceAll("://", ": //")
      .replaceAll(/\bwww\./gi, "www ."),
    cap,
    (kept) => kept.replace(/&[a-z]*$|\\$/, ""),
  );

// Every line prefixed `> `, so no line of it can start a heading or leave the
// quote, and the text wraps when rendered.
const quoted = (value) =>
  neutral(value || "(none)", MAX_TEXT)
    .trim()
    .split("\n")
    .map((line) => (line.trim() ? `> ${line.trimEnd()}` : ">"))
    .join("\n");

// The linkage lines the issue's done-when asks the PR body to carry: each
// task-list item that names the PR body and quotes, in a code span, a
// `Refs: #<n>` or `Siblings: #<a>, #<b>` line in the form pr-verify and the
// merge lane read (merge-holds.mjs refsIssue, resolve-pr.mjs siblingNumbers).
// Built from the issue's text, never the run's, so the line keeps the ASCII
// `#` that neutral() breaks in model text; main passes a body only when a
// listed human or the lanes App wrote the issue. A Refs line naming the issue
// itself is left out, since the body's first line already names it.
const TASK_ITEM = /^ {0,3}[-*+] \[[ xX]\] (.*)$/;
const PR_BODY = /\b(?:PR|pull request)(?:'s)? body\b/i;
const LINKAGE = /`(Refs:[ \t]*#[1-9][0-9]{0,8}|Siblings:[ \t]*#[1-9][0-9]{0,8}(?:[ \t]*,[ \t]*#[1-9][0-9]{0,8}){0,9})[ \t]*`/g;
export const MAX_LINKAGE = 10;
export function linkageLines(body, issueNumber) {
  const lines = new Set();
  for (const line of visibleLines(body)) {
    const item = TASK_ITEM.exec(line);
    if (!item || !PR_BODY.test(item[1])) {
      continue;
    }
    for (const [, quote] of item[1].matchAll(LINKAGE)) {
      const text = quote.replace(/:[ \t]*/, ": ").replaceAll(/[ \t]*,[ \t]*/g, ", ");
      if (text !== `Refs: #${issueNumber}`) {
        lines.add(text);
      }
    }
  }
  return [...lines].slice(0, MAX_LINKAGE);
}

// One line per item, so an item cannot open a section of its own.
const bullets = (items) =>
  items
    .slice(0, MAX_ITEMS)
    .map((item) => `- ${neutral(item.replaceAll(/\s+/g, " "), MAX_ITEM).trim()}`)
    .join("\n");

// The first line that makes a listed human's issue comment a decision the run
// builds (select-trusted-text's isDecisionComment, which write-issue.mjs
// applies). A script activity runs from a copy of its own directory, so the
// rule is restated here, not imported.
export const DECISION_LINE = "**Decision recorded.**";
const DECISION = /^\*\*Decision recorded\.\*\*(\s|$)/;
const COMMENT_URL = /^https:\/\/[A-Za-z0-9.-]+\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/issues\/[1-9][0-9]*#issuecomment-[1-9][0-9]*$/;

// The URL of a listed human's newest issue comment after the lanes App's
// (`bot`) last outcome marker, when they posted it themselves (not through an
// App) and its first line is not DECISION_LINE; else null. `comments` are
// oldest first, as GET /issues/{n}/comments lists them.
export function unmarkedAnswer(comments, humans, bot) {
  const since = comments.findLastIndex((comment) => comment?.user?.login === bot && parseOutcomeMarker(comment.body) !== null);
  const last = comments.slice(since + 1).filter((comment) => humans.has(comment?.user?.id)).at(-1);
  const first = String(last?.body ?? "").trimStart().split("\n", 1)[0].trimEnd();
  return last && last.performed_via_github_app == null && !DECISION.test(first) && COMMENT_URL.test(last.html_url ?? "") ? last.html_url : null;
}

// The marker names the run, so --find-prior never reuses a branch whose work
// this report already handed on. `unmarked` is unmarkedAnswer's URL, which a
// pushback links with the line it lacks.
// `reason` is the stop-reason code (stopReasonCode), which must be a person
// reason: the comment carries its marker and its visible line. `spentSecurity`
// marks routeStop's spent security hold, whose line says the run named the
// risk again after its intake rounds were spent. `word` is heldWord's, which a
// code span keeps inert in this public comment.
function handBack({ outcome, issueNumber, branch, humanLabel, runUrl, runId, onResumed = false, unmarked = null, reason, spentSecurity = false, word = "" }) {
  const pushback = outcome.exit === "pushback";
  const [reasonMarker, reasonLine] = personReasonLines(LANE, reason);
  const lines = escalated([
    `<!-- work-resolve-issue outcome=${outcome.exit}${runId ? ` run=${runId}` : ""}${resumedTag(onResumed)} -->`,
    reasonMarker,
    spentSecurity
      ? "The work-resolve-issue lane hands this issue to a person: this run named a possible security risk again after its intake rounds were spent, so a person checks it first."
      : reason === "security" && pushback
        ? "The work-resolve-issue lane did not start this issue: the run named a possible security risk, so a person checks it first."
        : pushback
        ? "The work-resolve-issue lane did not start this issue: it needs a person to make it clearer first."
        : "The work-resolve-issue lane stopped partway through this issue and needs a person.",
    "",
    reasonLine,
    ...(word ? ["", `Matched security word: \`${word}\`. A match holds the stop whether or not the text names a risk, so read the word in context below.`] : []),
    "",
    "Why, in the run's own words:",
    "",
    quoted(outcome.reason || outcome.summary),
  ]);
  if (outcome.notDone.length) {
    lines.push("", "What the run says it did not do:", "", bullets(outcome.notDone.map(({ what }) => what)));
  }
  if (pushback && unmarked) {
    lines.push(
      "",
      `The newest comment from a listed maintainer, ${unmarked}, does not start with \`${DECISION_LINE}\`, so the lane did not count it as an answer. If it answers the question, post the answer again in a new comment whose first line is:`,
      "",
      "```",
      `${DECISION_LINE} <answer>`,
      "```",
    );
  }
  if (branch) {
    lines.push(
      "",
      pushback
        ? `Partial work is on the branch \`${branch}\`.`
        : `Partial work is on the branch \`${branch}\`. A retry continues from it while it is not behind the default branch, and otherwise starts fresh from the default branch; delete the branch first to always start fresh.`,
    );
  }
  if (runUrl) {
    lines.push("", `Run: ${runUrl}`);
  }
  lines.push(
    "",
    pushback
      ? `To retry, answer the question in a comment whose first line is \`${DECISION_LINE}\`, then set Work status to agent-ready again (clearing the \`${humanLabel}\` hold).`
      : `To retry, set Work status to agent-ready again (clearing the \`${humanLabel}\` hold).`,
  );
  return {
    action: "hand-back",
    exit: outcome.exit,
    issueNumber,
    comment: lines.join("\n"),
    addLabels: [],
    status: humanLabel,
  };
}

// The comment and labels of a stop whose route is not hold, which carries no
// escalation marker: retry and wait keep Work status at agent-ready
// (work-unblock restarts it and the next run resumes the branch), host-run and
// attended add their label and move Work status to confirmed, so a listed
// human's agent-ready later is a change that starts a run, intake and fail
// move Work status to needs-triage,
// park to confirmed (finishStop writes admission's comment first), and close
// closes the issue. No route writes a status label: the field is the state.
const ROUTE_OUTCOME = { retry: "retry", wait: "wait", intake: "intake", park: "parked", close: "closed", "host-run": "host-run", attended: "attended", fail: "failed" };
const ROUTE_LABEL = { "host-run": HOST_RUN_LABEL, attended: ATTENDED_LABEL };
// The label whose Work status state a park writes.
const PARK_STATUS = "status: confirmed";
const KEPT = new Set(["retry", "wait"]);
// The routes whose stops are counted against a cap: past it, retry-spent's.
const COUNTED = new Set([...KEPT, "intake"]);
// Removes no label: the queue state is the Work status field. Kept for
// work-unblock (label-unblocked.mjs), which still calls it.
export async function stripQueueLabels() {
  return [];
}
// The state label a closed issue no longer needs: the host queue's. Removed
// only once the issue is closed, so a close that fails leaves an open issue in
// its state. `attended` stays: only a listed human lifts it.
export const STATE_LABELS = [HOST_RUN_LABEL];

// Removes the state labels `had` holds from the closed issue at `base`, and
// returns their names. A 404 counts as removed.
export async function stripStateLabels(github, base, had) {
  const present = new Set(had.map((name) => String(typeof name === "string" ? name : name?.name).toLowerCase()));
  const removed = STATE_LABELS.filter((name) => present.has(name));
  for (const name of removed) {
    await github("DELETE", `${base}/labels/${encodeURIComponent(name)}`).catch((error) => {
      if (error?.status !== 404) {
        throw error;
      }
    });
  }
  return removed;
}
const ROUTE_TEXT = {
  "host-run": `It added \`${HOST_RUN_LABEL}\` and set Work status to confirmed: an agent run on a host builds it, and it waits on no decision from a person.`,
  attended: `It added \`${ATTENDED_LABEL}\` and set Work status to confirmed: the step needs the owner present, and it waits on no decision from a person.`,
  intake: "It set Work status to needs-triage, so the hourly triage sweep sends it back through intake triage, and it waits on no decision from a person.",
  "intake-security": "It set Work status to needs-triage, so the hourly triage sweep sends it back through intake triage.",
  park: `It set Work status to confirmed, as admission parks a refusal no person answers, and it waits on no decision from a person. Once that step is done, a listed human's comment whose first line is \`${DECISION_LINE}\` sends it back through intake triage.`,
  close: "It closes the issue as completed.",
  fail: "It set Work status to needs-triage and added no label.",
};
// The pull request a blocked-by-pr reason names, or the issue a
// blocked-by-issue reason names: its first `#<n>` (or the full-width `＃<n>`)
// other than the issue itself, or "".
export const waitedPull = (reason, issueNumber) =>
  [...String(reason ?? "").matchAll(/[#＃]([1-9][0-9]{0,9})\b/g)].map((match) => match[1]).find((number) => Number(number) !== issueNumber) ?? "";
// pushbackSecurity's stop line, which leaves the question's kind to intake.
const PUSHBACK_SECURITY_WHY =
  "the run pushed back without naming cause intent, and its words may name a security risk, so intake triage judges the issue again on evidence; if the run names it again once this intake round is spent, the issue reaches a person";
function stopPlan({ route, stop, shown, retries, cap, outcome, issueNumber, branch, runUrl, runId, onResumed = false, pr = "", after = "", why = "", neutral = false }) {
  const exit = ROUTE_OUTCOME[route];
  const lines = [
    `<!-- work-resolve-issue outcome=${exit}${neutral ? " security" : ""}${pr ? ` pr=${pr}` : ""}${runId ? ` run=${runId}` : ""}${resumedTag(onResumed)} -->`,
    `${stopLine(stop)} ${neutral ? PUSHBACK_SECURITY_WHY : stopWhy(shown)}.`,
    ...(why ? [why] : []),
    // Outside the quoted run words, whose `#` reads full-width, so intake
    // triage reads the blocker as a plain issue reference.
    ...(after ? [`It must land after #${after}: intake triage records #${after} on its \`Blocked by:\` line, which writes the blocked-by edge.`] : []),
    route === "retry"
      ? `It keeps \`agent-ready\`, and work-unblock starts it again (retry ${retries + 1} of ${cap}).`
      : route === "wait"
        ? `It keeps \`agent-ready\`, and work-unblock starts it again once #${pr} merges or closes (wait ${retries + 1} of ${cap}).`
        : ROUTE_TEXT[neutral ? "intake-security" : route],
  ];
  const words = outcome.reason || outcome.summary;
  if (words) {
    lines.push("", RUN_WORDS, "", quoted(words));
  }
  if (outcome.exit === "pushback" && String(outcome.cause ?? "").trim()) {
    lines.push("", "The cause the run named:", "", quoted(String(outcome.cause)));
  }
  // A closed issue's result is the run's report, which its summary holds.
  if (route === "close" && outcome.reason && outcome.summary) {
    lines.push("", "The run's report:", "", quoted(outcome.summary));
  }
  if (outcome.notDone.length) {
    lines.push("", "What the run says it did not do:", "", bullets(outcome.notDone.map(({ what }) => what)));
  }
  if (branch) {
    lines.push("", `Partial work is on the branch \`${branch}\`. The next run continues from it while it is not behind the default branch, and otherwise starts fresh.`);
  }
  if (runUrl) {
    lines.push("", `Run: ${runUrl}`);
  }
  if (route === "host-run") {
    lines.push("", `To hand it back to the lane, remove \`${HOST_RUN_LABEL}\` and set Work status to agent-ready again.`);
  } else if (route === "attended") {
    lines.push("", `Once the step is done, a listed human removes \`${ATTENDED_LABEL}\` and sets Work status to agent-ready again.`);
  } else if (route === "fail") {
    lines.push("", "To run it again, set Work status to agent-ready.");
  }
  return {
    action: route,
    exit,
    stop,
    issueNumber,
    runId,
    comment: lines.join("\n"),
    addLabels: Object.hasOwn(ROUTE_LABEL, route) ? [ROUTE_LABEL[route]] : [],
    ...((route === "park" || Object.hasOwn(ROUTE_LABEL, route)) && { status: PARK_STATUS }),
    ...(pr && { pr }),
    ...(after && { after }),
    ...(route === "park" && { admission: parkReason(stop, why || stopWhy(shown)) }),
  };
}

// The reason a park's admission comment gives (refusalText), as
// admission words a refusal: lowercase, no closing period.
const parkReason = (stop, why) => {
  const said = why.replace(/\.$/, "");
  return `the work-resolve-issue lane stopped on it (\`${stop}\`); ${said.charAt(0).toLowerCase()}${said.slice(1)}`;
};

// A stop routed by stop-routes.json, or by `route` in its place; `args` are
// handBack's. A retry, wait or intake past limits.stop-retries, or the row's
// own `retries` when fewer (`retries`, counted since a listed human last added
// agent-ready), takes retry-spent's route instead; a spent intake round that
// is itself a pushbackSecurity stop takes security-risk's hold. `spentSecurity`
// marks that hold for handBack.
function routeStop(stop, args, { retries = 0, limits = LIMIT_DEFAULTS, route: given = stopRoute(stop), why = "", spentSecurity = false } = {}) {
  const cap = stopRetries(stop, limits["stop-retries"]);
  const spent = COUNTED.has(given) && retries >= cap;
  const security = given === "intake" && pushbackSecurity(stop, args.outcome);
  if (spent && security) {
    return routeStop("security-risk", args, { spentSecurity: true });
  }
  const shown = spent ? "retry-spent" : stop;
  const route = spent ? stopRoute(shown) : given;
  const pr = route === "wait" ? waitedPull(args.outcome?.reason, args.issueNumber) : "";
  const after = route === "intake" && shown === "blocked-by-issue" ? waitedPull(args.outcome?.reason, args.issueNumber) : "";
  const plan =
    route === "hold"
      ? handBack({ ...args, reason: stopReasonCode(shown), spentSecurity, word: shown === "security-risk" ? heldWord(args.outcome) : "" })
      : stopPlan({ ...args, outcome: { notDone: [], ...args.outcome }, route, stop, shown, retries, cap, pr, after, why, neutral: security });
  return { ...plan, stop, stopArgs: args, ...(why && { why }) };
}

// A retry, wait or intake plan with the earlier ones counted in: past the cap
// it becomes retry-spent's route, or security-risk's hold for an intake plan
// that is a pushbackSecurity stop. Any other plan is returned as it is.
export const capRetries = (plan, retries, limits = LIMIT_DEFAULTS) =>
  COUNTED.has(plan.action) ? routeStop(plan.stop, plan.stopArgs, { retries, limits, route: plan.action, why: plan.why }) : plan;

// apply-issue-patch's escalation reasons, each with why the patch did not land.
export const PATCH_REASONS = {
  "patch-empty": "the run wrote no change",
  "patch-protected-path": "the patch changes a path the issue lane may not push: a workflow, a CODEOWNERS file, submodule config or a settings file",
  "patch-invalid": "the run's output was not a valid patch to push: missing, too large or made on another commit",
  "patch-credential": "the patch, or a file it writes, carries a credential shape",
  "patch-not-applied": "the patch did not apply to the commit the run started from",
  "patch-apply-failed": "apply-issue-patch failed before it committed or refused the patch",
};

// The step that must come before the lane can run an issue its dimensions
// skipped, as triage's apply-outcome rule names it.
export const DIMENSION_STEPS = {
  "split-required": "Its Size is too large for one run: intake splits it into sub-issues (owner Q93).",
  "research-first": "Its Uncertainty says research comes first: plan or research the approach, then set Uncertainty to Known.",
  "probe-first": "Its Uncertainty says only an experiment answers it: run a probe or spike first, then set Uncertainty to Known.",
};

// Outcomes no run produces now that issue comments may still carry from runs
// that ran nothing, so prior() passes them over like a dimension skip.
const RETIRED_SKIPS = new Set(["not-assessed"]);

// The admit job's stop on an issue neither a listed human nor the lanes App
// wrote (check-blockers.mjs), which report-skip reports like a dimension skip.
export const OUTSIDE_AUTHOR = "outside-author";
// The stops that leave the queue for triage with no state of their own.
const TRIAGE_AGAIN = new Set(["intake", "failed", OUTSIDE_AUTHOR]);

// A run the admit job stopped on the issue's author: agent-ready comes off and
// one comment says a listed human re-files the work. No label: re-adding
// agent-ready stops again, and the issue's text is never quoted.
function outsideAuthorPlan({ issueNumber, runUrl, runId }) {
  const lines = [
    `<!-- work-resolve-issue outcome=${OUTSIDE_AUTHOR}${runId ? ` run=${runId}` : ""} -->`,
    "The work-resolve-issue lane did not start this issue (`outside-author`): its author is outside the trusted list, neither a listed human nor the lanes App, so the lane does not work from its text. A listed human re-files the work as a new issue in their own words.",
  ];
  if (runUrl) {
    lines.push("", `Run: ${runUrl}`);
  }
  return { action: "hand-back", exit: OUTSIDE_AUTHOR, issueNumber, comment: lines.join("\n"), addLabels: [] };
}

// The read runner's stop on stale workflow files (pr-run-activity-read.yml
// `Stop on stale workflow files`), which work-resolve-issue.yml's
// resolve-issue-stale job reads from the jobs listing and report-outcome
// passes on like a dimension skip.
export const WORKFLOW_STALE = "workflow-stale";

// The lane's caller and the write runner, in work-unblock's re-fire key
// order: the broker refuses a run whose copy of either differs from main's.
export const LANE_WORKFLOWS = [".github/workflows/pr-run-activity-write.yml", ".github/workflows/work-resolve-issue.yml"];
// work-unblock's re-fire record, which its sweep reads back: the key is
// main's blob SHAs of LANE_WORKFLOWS, and `breaker` marks a kill-switch trip.
export const REFIRED = /^<!-- work-unblock refired ([0-9a-f]{40}-[0-9a-f]{40})( breaker)? -->/;
export const refireComment = (key, cause, actor = "work-unblock") =>
  `<!-- work-unblock refired ${key} -->\n${cause} ${actor} removed and added \`agent-ready\` back to start a fresh run on main's workflow files. If this run ends the same way, it re-fires the issue again, waiting longer each time.`;
const STALE_CAUSE =
  "The work-resolve-issue run that `agent-ready` started waited in its slot past a change to its lane workflow files on main, so it stopped before any model turn.";
// The labels the issue lane never starts or restarts on, which work-unblock
// reads too: a person decides each but `attended`, which waits on a step the
// owner takes present, and `host-run`, which a host session builds while Work
// status stays agent-ready; only a person removes OUTSIDE_ACTOR_LABEL.
export const LANE_HOLDS = new Set(["needs-owner-decision", "status: needs-decision", "status: needs-info", "needs-human", ...UNTRUSTED_LABELS, ATTENDED_LABEL, HOST_RUN_LABEL, OUTSIDE_ACTOR_LABEL]);
const BLOB = /^[0-9a-f]{40}$/;

// The admission record's lib, loaded on use: ci-status loads this file from a
// sparse checkout that holds no lib/admission-record.mjs.
const admissionLib = () => import("../lib/admission-record.mjs");

// The times the lanes App (`appId`) set the Work status field (`fieldId`) to
// agent-ready, among resolve-config fieldEvents: its restarts.
const appSets = (fieldEvents, fieldId, appId) =>
  (fieldEvents ?? [])
    .filter((event) => event?.field === String(fieldId) && event.removed === false && event.to === "agent-ready" && event.actorId === appId)
    .map((event) => Date.parse(event.at));

// The trusted Work status state (`field.state`), or undefined with one
// warning when it cannot be read.
async function fieldState(field, issueNumber) {
  try {
    return await field.state(issueNumber);
  } catch (error) {
    console.log(`::warning title=work-status::issue #${issueNumber} is left as it is: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return undefined;
  }
}

// The Work status field as report-outcome reads and restarts it, which
// baseStatus builds: `id` the field id (null when models.issue-status is
// unset), `state(number)` its trusted state (read-status.mjs), `events(number)`
// resolve-config fieldEvents, and `restart(number, from)` the App's restart:
// while the state still reads `from`, the value is removed (unless `from` is
// null) and agent-ready set, which starts a fresh run. False when the state
// moved or the removal found no value: a person's change stands.
const NO_FIELD = { id: null, state: async () => null, events: async () => [], restart: async () => false };

// A run that stopped on stale workflow files ran no model and is no fault in
// the issue, so it is re-fired at once on main's files, the way work-unblock's
// sweep re-fires it: its re-fire record, then the App's restart of the Work
// status field (`field.restart`), which starts a fresh run. The restart writes
// no admission record, so the fresh run freezes at the admission this one did.
// Nothing is done when the run's files match main's (the stale claim does not
// hold), the issue is closed, its trusted Work status is not agent-ready or
// cannot be read, no admission (admission-record.mjs admittedAt: the App's
// record or a listed human's agent-ready set) admitted it, a hold is on, or a
// person changes the field before the write lands; and none past
// limits.limit-stops-per-issue re-fire records since the newest admission or
// a run last reported. Past that bound the hourly sweep still re-fires a stale
// stop once per new version of the two lane workflow files on main, so the
// re-fires are bounded by how often main changes them. Returns what it did.
// `statusOf(number, names)` gives the label names as the Work status field
// decides them (baseStatus); a failed read re-fires nothing.
export async function refireStale(github, repo, issueNumber, { workflowSha, bot, appId, humans, limits, statusOf = async (number, names) => names, field = NO_FIELD }) {
  if (!BLOB.test(workflowSha ?? "")) {
    return "skipped: the run names no workflow commit";
  }
  const shas = async (ref) => {
    const out = [];
    for (const path of LANE_WORKFLOWS) {
      const sha = (await github("GET", `${repo}/contents/${path}?ref=${ref}`))?.sha;
      if (!BLOB.test(String(sha))) {
        throw new Error(`${path} at ${ref} has no blob SHA`);
      }
      out.push(sha);
    }
    return out.join("-");
  };
  const key = await shas("main");
  if ((await shas(workflowSha)) === key) {
    return "skipped: the run's lane workflow files are main's";
  }
  const base = `${repo}/issues/${issueNumber}`;
  const issue = await github("GET", base);
  const labels = (issue?.labels ?? []).map((label) => String(typeof label === "string" ? label : label?.name).toLowerCase());
  if (issue?.state !== "open") {
    return "skipped: the issue is closed";
  }
  const state = await fieldState(field, issueNumber);
  if (state === undefined) {
    return "skipped: the Work status could not be read";
  }
  if (state !== "agent-ready") {
    return "skipped: the Work status is not agent-ready";
  }
  const held = await laneHold(statusOf, issueNumber, labels);
  if (held) {
    return `skipped: ${held}`;
  }
  const all = await paginate(github, `${base}/comments`);
  const fieldEvents = await field.events(issueNumber);
  const { admittedAt } = await admissionLib();
  let admission;
  try {
    admission = admittedAt({ comments: all, appId, fieldEvents, fieldId: field.id, humans });
  } catch {
    return "skipped: no admission record or listed human's agent-ready set admitted the issue";
  }
  const comments = all.filter((comment) => comment?.user?.login === bot);
  const at = (comment) => Date.parse(comment.created_at);
  const from = Math.max(admission.at, ...comments.filter((comment) => parseOutcomeMarker(comment.body) !== null).map(at));
  const records = comments.filter((comment) => {
    const record = REFIRED.exec(String(comment.body ?? ""));
    return record !== null && record[2] === undefined && at(comment) > from;
  });
  // A record no App agent-ready set follows is one whose restart did not
  // finish: finish it without posting another (work-unblock's `relabeled`).
  const sets = appSets(fieldEvents, field.id, appId);
  const pending = records.some((comment) => !sets.some((time) => time >= at(comment)));
  if (!pending && records.length >= limits["limit-stops-per-issue"]) {
    return `skipped: ${records.length} re-fires since the issue's admission or a run last reported (limits.limit-stops-per-issue); work-unblock's sweep takes it`;
  }
  if (!pending) {
    await github("POST", `${base}/comments`, { body: refireComment(key, STALE_CAUSE, "The run's report-outcome") });
  }
  // A failed set throws, failing the job: the record no App set follows is
  // finished on a re-run.
  if (!(await field.restart(issueNumber, "agent-ready"))) {
    return "skipped: the Work status changed before the re-fire";
  }
  return `re-fired on workflow files ${key}`;
}

// What holds the issue from the lane, from its lowercased label names as the
// Work status field decides them: `held by <label>`, `the Work status could
// not be read` (with one warning), or "" when nothing does.
async function laneHold(statusOf, issueNumber, labels) {
  let names;
  try {
    names = (await statusOf(issueNumber, labels)).map((name) => String(name).toLowerCase());
  } catch (error) {
    console.log(`::warning title=work-status::issue #${issueNumber} is left as it is: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return "the Work status could not be read";
  }
  const hold = names.find((label) => LANE_HOLDS.has(label));
  return hold ? `held by ${hold}` : "";
}

// intake's refinement record (admit.mjs REFINE_MARKER), restated as
// DECISION_LINE is: a script activity runs from a copy of its own directory.
export const REFINE_MARKER = "<!-- intake-triage refinement -->";
// The hold stops that wait on a person's answer on the issue. A security
// stop is never among them: a person checks it first, whatever was posted.
const ANSWERED_STOPS = new Set(["pushback", "intent-change", "design-change", "cost-risk"]);
// The record opens with an outcome marker naming the run, so findPrior counts
// the run's lane branch as reported and the fresh run starts past it instead
// of reusing it unread.
const REDISPATCHED = /^(?:<!-- work-resolve-issue outcome=redispatch[^\n]* -->\r?\n)?<!-- work-resolve-issue redispatch comment=([1-9][0-9]{0,15}) -->/;
export const redispatchComment = (comment, runId = "") =>
  `<!-- work-resolve-issue outcome=redispatch${runId ? ` run=${runId}` : ""} -->\n<!-- work-resolve-issue redispatch comment=${comment.id} -->\nA record this run did not read was posted after its admission: ${comment.html_url}. The run's report-outcome posted a fresh admission record and set the Work status field to agent-ready again, so a fresh run admits the issue as it stands now and reads it.`;

// The record a hold would leave unread, or null: a listed human's own
// decision (DECISION_LINE first, not posted through an App) or the lanes
// App's (`bot`) refinement, created or last updated at or after the newest
// admission (admission-record.mjs admittedAt: the App's admission record or a
// listed human's agent-ready set of the Work status field `fieldId`). The
// App's restarts write no record, so write-issue.mjs freezes a run at that
// admission or an earlier one, and each such record is one the run left out.
// `comments` are oldest first. Returns {comment}, or, when this run
// (`runId`) already posted a redispatch record, {comment, marker, recorded}
// naming it: a re-run finishes that redispatch rather than reading the new
// admission record it posted, `recorded` when an App admission record
// followed the marker. No admission found answers null.
export async function lateRecord({ comments, fieldEvents, fieldId, appId, bot, humans, runId }) {
  const { admissionRecords, admittedAt } = await admissionLib();
  const marker = runId
    ? comments.findLast((item) => item?.user?.login === bot && REDISPATCHED.test(String(item.body ?? "")) && parseOutcomeMarker(item.body)?.run === runId)
    : undefined;
  if (marker) {
    const named = REDISPATCHED.exec(String(marker.body))[1];
    const comment = comments.find((item) => String(item?.id) === named);
    const since = Date.parse(marker.created_at);
    return comment ? { comment, marker, recorded: admissionRecords(comments, appId).some(({ at }) => at >= since) } : null;
  }
  let from;
  try {
    from = admittedAt({ comments, appId, fieldEvents, fieldId, humans }).at;
  } catch {
    return null;
  }
  const comment = comments.find((item) => {
    const body = String(item?.body ?? "");
    if (!(Date.parse(item?.updated_at ?? item?.created_at ?? "") >= from)) {
      return false;
    }
    if (item.user?.login === bot) {
      return body.startsWith(REFINE_MARKER);
    }
    const first = body.trimStart().split("\n", 1)[0].trimEnd();
    return item.user?.type === "User" && humans.has(item.user.id) && item.performed_via_github_app == null && DECISION.test(first);
  });
  return comment ? { comment } : null;
}

// A hold whose answer landed after the run's admission starts a fresh run
// instead: a redispatch record naming the answer, then a fresh admission
// record (admission-record.mjs, the title and body of this one read of the
// issue) and the App's restart of the Work status field (`field.restart`), so
// the new run freezes at that record, after the answer. A record post that
// fails throws before any restart. A re-run of this run's own redispatch
// (`late.marker`) posts neither record again once it is on the issue, and
// restarts the field unless an App agent-ready set already followed the
// marker. Nothing moves when the issue is closed, a hold is on, or the trusted
// Work status is not agent-ready, unless the App's own removal after the
// marker left it unset, which a re-run finishes. A hold is read through
// `statusOf` (refireStale's), and a failed read holds, as does an unknown App
// id, which no record can carry. Returns whether it re-dispatched.
async function redispatch(github, repo, plan, late, { runId, statusOf, field, appId }) {
  if (!Number.isSafeInteger(appId)) {
    return false;
  }
  const base = `${repo}/issues/${plan.issueNumber}`;
  const issue = await github("GET", base);
  const labels = (issue?.labels ?? []).map((label) => String(typeof label === "string" ? label : label?.name).toLowerCase());
  const since = late.marker ? Date.parse(late.marker.created_at) : Number.POSITIVE_INFINITY;
  const events = late.marker ? await field.events(plan.issueNumber) : [];
  if (appSets(events, field.id, appId).some((time) => time >= since)) {
    return true;
  }
  if (issue?.state !== "open" || (await laneHold(statusOf, plan.issueNumber, labels))) {
    return false;
  }
  const state = await fieldState(field, plan.issueNumber);
  const newest = events.filter((event) => event?.field === String(field.id)).at(-1);
  const moving = state === null && newest?.removed === true && newest.actorId === appId && Date.parse(newest.at) >= since;
  if (state !== "agent-ready" && !moving) {
    return false;
  }
  if (!late.marker) {
    await github("POST", `${base}/comments`, { body: redispatchComment(late.comment, runId) });
  }
  if (!late.recorded) {
    const { writeAdmissionRecord } = await admissionLib();
    await writeAdmissionRecord(github, repo.slice("/repos/".length), plan.issueNumber, { actorId: appId, title: issue.title, body: issue.body ?? "" });
  }
  // A person's change since the read stands.
  await field.restart(plan.issueNumber, moving ? null : "agent-ready");
  return true;
}

// A run the usage limit stopped: one marker comment, agent-ready kept, no
// label, so work-unblock restarts the issue once the limit resets.
function limitedPlan({ issueNumber, branch, resets, runId, runUrl, onResumed }) {
  const lines = [
    limitedMarker({ resets, runId, onResumed }),
    `The work-resolve-issue lane stopped on its usage limit, not on this issue. It keeps \`agent-ready\`, and work-unblock starts it again after ${resets}.`,
  ];
  if (branch) {
    lines.push("", `Partial work is on the branch \`${branch}\`.`);
  }
  if (runUrl) {
    lines.push("", `Run: ${runUrl}`);
  }
  return { action: "limited", exit: "limited", issueNumber, resets, runId, comment: lines.join("\n"), addLabels: [] };
}

// A run the lane's funding stopped: one marker comment, agent-ready kept, no
// label. It counts toward the limit-stop bound, not the turn-cap one; work-unblock
// restarts it after the regain date, or with no date after limits.fallback-reset
// hours, as it does a limit stop with no reset.
function fundingPlan({ issueNumber, branch, regain, runId, runUrl, onResumed }) {
  const resets = regain === null ? "" : new Date(regain).toISOString().replace(/\.\d+Z$/, "Z");
  const lines = [
    `<!-- work-resolve-issue outcome=funding${resets ? ` resets=${resets}` : ""} run=${runId || 0}${resumedTag(onResumed)} -->`,
    resets
      ? `The work-resolve-issue lane stopped on its funding (\`funding\`: a spend limit or no credit), not on this issue. It keeps \`agent-ready\`, and work-unblock starts it again after ${resets}.`
      : "The work-resolve-issue lane stopped on its funding (`funding`: no credit or a disabled key), not on this issue. It keeps `agent-ready`, and work-unblock starts it again after limits.fallback-reset hours; after limits.limit-stops-per-issue limit and funding stops it removes `agent-ready` and marks the issue failed.",
  ];
  if (branch) {
    lines.push("", `Partial work is on the branch \`${branch}\`; the restart continues from it while it is not behind the default branch, and otherwise starts fresh.`);
  }
  if (runUrl) {
    lines.push("", `Run: ${runUrl}`);
  }
  return { action: "funding", exit: "funding", issueNumber, runId, comment: lines.join("\n"), addLabels: [] };
}

// A run that reached its turn cap: the marker names the cap, and the comment
// names the cause and the branch. With restarts left, agent-ready stays and
// work-unblock starts the issue again; otherwise it takes turn-cap-spent's route.
function turnCapPlan({ issueNumber, branch, cap, timeout = false, restart, humanLabel, runId, runUrl, onResumed }) {
  const reached = timeout ? "its time ran out (the launcher's leg timeout)" : cap ? `turn cap ${cap} reached` : "turn cap reached";
  if (!restart) {
    return routeStop("turn-cap-spent", {
      outcome: stopped(`The run stopped: ${reached}, and it has used its turn-cap restarts.`),
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
      onResumed,
    });
  }
  const lines = [
    turnCapMarker({ cap, runId, onResumed }),
    `The work-resolve-issue lane stopped on this issue: ${reached}. It keeps \`agent-ready\`, and work-unblock starts it again from the branch, or fresh from the default branch once the branch is behind it.`,
    "",
    branch
      ? `Partial work is on the branch \`${branch}\`; a restart or retry continues from it while it is not behind the default branch, and otherwise starts fresh. Delete the branch first to always start fresh.`
      : "The run committed nothing.",
  ];
  if (runUrl) {
    lines.push("", `Run: ${runUrl}`);
  }
  return { action: "turn-cap", exit: "turn-cap", issueNumber, runId, comment: lines.join("\n"), addLabels: [] };
}

// The summary pass's file for a reused branch, or null unless it is bound to
// this issue and branch, names the tip it read, and holds a non-empty summary.
// issue, branch and tip are runner values; output is the model's, read as data.
export function readSummary(dir, { issueNumber, branch }) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(join(dir, "reuse-summary.json"), "utf8"));
  } catch {
    return null;
  }
  const output = parsed?.output;
  if (
    parsed?.version !== 1 ||
    parsed.issue !== issueNumber ||
    parsed.branch !== branch ||
    !/^[0-9a-f]{40}$/.test(parsed.tip ?? "") ||
    output === null ||
    typeof output !== "object" ||
    Array.isArray(output)
  ) {
    return null;
  }
  const summary = text(output.summary);
  return summary.trim() ? { tip: parsed.tip, title: text(output.title), summary, changes: list(output.changes) } : null;
}

// The run-checks job's `checks` output: {tip, results: [{check, exit}]}, or
// null unless it names this branch, a tip, and at most MAX_ITEMS whole-number
// results, so no result is cut off. A check passes only on exit 0. On a reused
// branch it adds `scan`, the leak scan's word for that tip (scan-reuse.mjs);
// any word but clean holds the PR, and so does none.
export function readChecks(text, { branch }) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  const results = parsed?.results;
  const valid =
    parsed?.version === 1 &&
    typeof branch === "string" &&
    branch !== "" &&
    parsed.branch === branch &&
    /^[0-9a-f]{40}$/.test(parsed.tip ?? "") &&
    Array.isArray(results) &&
    results.length <= MAX_ITEMS &&
    results.every((result) => typeof result?.check === "string" && Number.isInteger(result.exit));
  if (!valid) {
    return null;
  }
  const record = { tip: parsed.tip, results: results.map(({ check, exit }) => ({ check: clip(check, MAX_ITEM), exit })) };
  return Object.hasOwn(parsed, "scan") ? { ...record, scan: SCAN_WORDS.has(parsed.scan) ? parsed.scan : "failed" } : record;
}
const SCAN_WORDS = new Set(["clean", "found", "failed"]);

const checkFailures = (checks) =>
  checks === null
    ? [{ what: "The runner's check results are missing, unreadable or for another tip of the branch.", required: true }]
    : checks.results.filter(({ exit }) => exit !== 0).map(({ check, exit }) => ({ what: `${check} failed (exit ${exit})`, required: true }));

// The gate a resumed branch passes before its PR opens and its statuses are
// posted: at least one check ran and none failed.
export const checksPassed = (checks) => Boolean(checks?.results.length) && !checkFailures(checks).length;

// Whether the lane's PR holds for a person. decide() and reusePlan() both ask
// here, so a reused branch holds on exactly the main path's conditions plus
// its own leak scan: a trusted `merge: human`, an issue carrying one of
// UNTRUSTED_LABELS, an unreadable denied-path list or changed-file list,
// a listing cut at the cap while some path is denied (it may hide one), a
// changed path the merge lane refuses, and on a reused branch a leak scan that
// is missing or not clean. Runner checks hold nothing, failed or unreported:
// the PR's Verification section names a failure, and ci-status reruns them on
// the head, where a red one goes to the fix lanes, not a person. The scan is
// not covered that way: lint-repo's gitleaks honors a gitleaks:allow comment
// or .gitleaksignore the branch can add, its password rule misses short or
// symbol-bearing values scanLeak flags, and it reads only the commits' patches.
export function mustHold({ issueLabels, humanMerge, holdPaths, changedFiles, checks, reused = false }) {
  return (
    humanMerge ||
    issueLabels.some((label) => UNTRUSTED_LABELS.includes(label)) ||
    holdPaths === null ||
    changedFiles === null ||
    (holdPaths.length > 0 && changedFiles.length >= COMPARE_FILES_CAP) ||
    changedFiles.some((path) => holdPaths.some((glob) => posix.matchesGlob(path, glob))) ||
    (reused && checks?.scan !== "clean")
  );
}

// The reused branch's leak scan as the PR body's Verification section shows it.
const scanLine = (checks) =>
  checks?.scan === "clean"
    ? "The runner's leak scan read everything the branch changes since its merge base with the default branch and found nothing credential-shaped."
    : checks?.scan === "found"
      ? "The runner's leak scan found a credential shape or a password or secret assignment in what the branch changes, so a person merges this."
      : "The runner's leak scan of the branch did not finish or could not be read, so a person merges this.";

// The runner's check results as the PR body's Verification section shows them.
const checkLines = (checks) =>
  checks === null
    ? "The runner's check results could not be read."
    : checks.results.length
      ? `The runner ran each check from the base copy against ${checks.tip}:\n\n${bullets(
          checks.results.map(({ check, exit }) => `${check}: ${exit === 0 ? "passed" : `failed (exit ${exit})`}`),
        )}`
      : "The runner ran no checks: the activity lists none.";

// The files a reused branch changes, from the runner's GET /compare (null
// when it failed), with each one the merge lane's denied paths cover marked
// and listed first. File names come from the branch, so they are data.
const MAX_FILES = 50;
function fileList(files, holdPaths) {
  if (!files) {
    return "The changed-file list is unavailable: the compare request failed.";
  }
  if (!files.length) {
    return "The compare listing names no changed files.";
  }
  const denied = (path) => holdPaths?.some((glob) => posix.matchesGlob(path, glob)) ?? false;
  const sorted = [...files.filter(denied), ...files.filter((path) => !denied(path))];
  return [
    holdPaths
      ? "Files the branch changes, from the compare listing; a denied path, which the merge lane refuses, is marked and listed first:"
      : "Files the branch changes, from the compare listing; the denied paths could not be read, so none is marked:",
    "",
    ...sorted
      .slice(0, MAX_FILES)
      .map((path) => `- ${neutral(path.replaceAll(/\s+/g, " "), MAX_ITEM, { path: true }).trim()}${denied(path) ? " (denied path)" : ""}`),
    ...(sorted.length > MAX_FILES ? [`- and ${sorted.length - MAX_FILES} more`] : []),
    ...(files.length >= COMPARE_FILES_CAP ? ["", `The compare listing stops at ${COMPARE_FILES_CAP} files, so this list may be incomplete.`] : []),
  ].join("\n");
}

// A lane branch an earlier run left with commits and no report, whose outcome
// this run cannot read: a PR listing the files it changes, held on mustHold's
// conditions. With the summary pass's summary it carries that text; without
// it, titled from the issue, no model text.
export function reusePlan({
  issueNumber,
  issueLabels = [],
  issueTitle = "",
  branch,
  runUrl = "",
  earlierRunUrl = "",
  summary = null,
  changedFiles = null,
  holdPaths = null,
  humanMerge = false,
  checks = null,
  linkage = [],
}) {
  const hold = mustHold({ issueLabels, humanMerge, holdPaths, changedFiles, checks, reused: true });
  const opened = `Opened by the work-resolve-issue lane from \`${branch}\`, which an earlier run left with commits and no report.`;
  const [about, fix, earlierChecks, leftOut] = summary
    ? [
        [`${opened} A summary-only model pass read the branch's diff and the issue, changed nothing, and wrote:`, "", quoted(summary.summary)],
        summary.changes.length ? bullets(summary.changes) : "The summary pass listed no changes; the diff shows them.",
        "The earlier run reported no checks here, and the summary pass ran none.",
        "every check the earlier run would have reported",
      ]
    : [
        [`${opened} The model did not run again, and the earlier run's outcome could not be read, so this body carries none of its text.`],
        "The diff shows the changes.",
        "The earlier run reported no checks here.",
        "every check",
      ];
  const body = [
    `Closes #${issueNumber}`,
    ...linkage,
    "",
    ...(hold ? [HOLD_LINE, ""] : []),
    "## Summary",
    "",
    ...about,
    "",
    "## Fix",
    "",
    fix,
    "",
    fileList(changedFiles, holdPaths),
    "",
    "## Verification",
    "",
    `${earlierChecks}\n\n${checkLines(checks)}\n\n${scanLine(checks)}`,
    "",
    earlierRunUrl ? `- The earlier lane run: ${earlierRunUrl}` : "- The earlier lane run.",
    runUrl ? `- This lane run: ${runUrl}` : "- This lane run.",
    "",
    hold
      ? `Left out: ${leftOut}; a person reviews the diff before merging.`
      : `Left out: ${leftOut}; ci-status, pr-verify and the security review lane check the head before it merges.`,
    "",
    "## Related",
    "",
    `#${issueNumber}`,
  ].join("\n");
  return { action: "open-pr", issueNumber, title: prTitle(summary?.title ?? "", issueTitle, issueNumber), body, branch, hold };
}

// What to do on the issue, from the outcome and what the run left. `limit` is
// the runner's limit record ({resets}, epoch ms or null) when the run hit its
// usage limit; a missing reset counts from `now`, the run's end. `turnCap` is
// the runner's record ({cap}) when the run reached its turn cap, and
// `turnCapRestarts` the restarts already made since a person last added
// agent-ready. `checks` is readChecks' record for the branch's current tip;
// null stops a done run. `unmarked` is the comment a pushback links
// (unmarkedAnswer). `linkage` is linkageLines' list for the issue.
export function decide({
  outcome,
  issueNumber,
  issueLabels,
  issueTitle = "",
  branch,
  changedFiles,
  holdPaths = null,
  humanMerge = false,
  humanLabel = "needs-human",
  runUrl = "",
  limit = null,
  turnCap = null,
  turnCapRestarts = 0,
  overCap = null,
  funding = null,
  issueStop = null,
  limits = LIMIT_DEFAULTS,
  now = Date.now(),
  runId = "",
  checks = null,
  resumed = "",
  escalation = "",
  unmarked = null,
  collectRefused = false,
  linkage = [],
}) {
  outcome = { changes: [], verification: [], notDone: [], remaining: [], ...outcome };
  // A run that never started left no outcome; its record names why.
  if (issueStop && outcome.unread) {
    outcome = { ...outcome, reason: issueStop, stop: Object.keys(ISSUE_STOPS).find((key) => ISSUE_STOPS[key] === issueStop) ?? outcome.stop };
  }
  const onResumed = !branch && resumed !== "";
  // The run's patch collector refused a stub name holding content: the run
  // may have planted a credential or config file. Its outcome file and
  // records are its own to forge, so this comes before all of them.
  if (collectRefused) {
    return routeStop("collect-refused", { outcome: stopped(COLLECT_REFUSED), issueNumber, branch: "", humanLabel, runUrl, runId });
  }
  // apply-issue-patch refused the run's patch: its work never landed, so no
  // PR opens, from a resumed branch either.
  const patchRefused = (lead) =>
    routeStop(escalation, {
      outcome: stopped(`${lead}, but apply-issue-patch did not commit its patch (\`${escalation}\`): ${PATCH_REASONS[escalation]}. The run's log names the path or check.`),
      issueNumber,
      branch: branch || resumed,
      humanLabel,
      runUrl,
      runId,
      onResumed,
    });
  // A refusal that holds comes before the records below for the same reason,
  // and before any exit: a run that stopped or hit its turn cap can still
  // leave a patch not proven clear of a credential.
  if (escalation && stopRoute(escalation) === "hold") {
    return patchRefused(outcome.exit === "done" ? "The run reported done" : "The run left a patch");
  }
  if (outcome.stop === "scan-refused-output") {
    return routeStop(outcome.stop, { outcome, issueNumber, branch: branch || resumed, humanLabel, runUrl, runId, onResumed });
  }
  // A funding, limit or turn-cap record counts only for a run that left no
  // outcome of its own: any code the run executed can forge the record, so it
  // must not hide a stop or pushback the skill reported from the person it
  // goes to. Funding comes first: the run ended on it, whatever the class.
  if (funding && outcome.unread) {
    return fundingPlan({ issueNumber, branch, regain: funding.regain, runId, runUrl, onResumed });
  }
  if (limit && outcome.unread) {
    const resets = new Date(clampReset(limit.resets, now, limits)).toISOString().replace(/\.\d+Z$/, "Z");
    return limitedPlan({ issueNumber, branch, resets, runId, runUrl, onResumed });
  }
  if (turnCap && outcome.unread) {
    const restart = turnCapRestarts < limits["turn-cap-restarts"];
    return turnCapPlan({ issueNumber, branch, cap: turnCap.cap, timeout: turnCap.timeout === true, restart, humanLabel, runId, runUrl, onResumed });
  }
  // patch-apply-failed is only the job's result, so a branch it did make wins.
  if (outcome.exit === "done" && escalation && escalation !== "patch-empty" && !(escalation === "patch-apply-failed" && branch)) {
    return patchRefused("The run reported done");
  }
  // A resumed run that committed nothing of its own: its work is the
  // resumed branch's. main passes checks for that branch only once run-checks
  // checked it at its current tip and every commit on it ahead of the default
  // branch is the lanes App's; then the PR opens from it when at least one
  // check ran and none failed. Otherwise a person gets it unopened.
  const resumedChecked = checksPassed(checks);
  if (outcome.exit === "done" && !branch && resumed && resumedChecked) {
    // `tip`: main opens the PR only at the tip the runner checked.
    const plan = decide({
      outcome: {
        ...outcome,
        verification: [
          `This run resumed \`${resumed}\` and made no commit of its own; the runner checked that whole branch at ${checks.tip}, and every commit on it ahead of the default branch is the lanes App's.`,
          ...outcome.verification,
        ],
      },
      issueNumber,
      issueLabels,
      issueTitle,
      branch: resumed,
      changedFiles,
      holdPaths,
      humanMerge,
      humanLabel,
      runUrl,
      overCap,
      limits,
      now,
      runId,
      checks,
      linkage,
    });
    return plan.action === "open-pr" ? { ...plan, tip: checks.tip } : plan;
  }
  if (outcome.exit === "done" && !branch && resumed) {
    return routeStop("resumed-unchecked", {
      outcome: stopped(
        `The run resumed \`${resumed}\` and reported done with no new commit. The earlier run's work is on that branch, and the runner's checks did not pass over that whole branch, so no PR was opened.`,
      ),
      issueNumber,
      branch: resumed,
      humanLabel,
      runUrl,
      runId,
      onResumed,
    });
  }
  if (outcome.exit === "done" && !branch) {
    return routeStop("done-no-commit", {
      outcome: stopped("The run reported done but committed nothing."),
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
    });
  }
  // The lane denies the paths apply-issue-patch refuses and tells a run whose
  // change needs one to stop with this reason, before it spends the run.
  // A run that stopped opens its reason with a stop-routes.json code, or with
  // none, and runCode reads a misformatted owner code as its hold row; a
  // missing or unreadable outcome carries its own stop.
  // A pushback takes pushbackStop's stop.
  const stop = outcome.exit === "pushback" ? pushbackStop(outcome) : outcome.unread ? (outcome.stop ?? "outcome-unread") : runCode(outcome.reason);
  if (outcome.exit === "stopped" && stop === "patch-protected-path") {
    return routeStop(stop, {
      outcome: {
        ...outcome,
        reason: `The run stopped early (\`patch-protected-path\`): its change needs a path the issue lane may not push, which a person changes instead. In the run's words: ${outcome.reason}`,
      },
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
      onResumed,
    });
  }
  if (outcome.exit !== "done") {
    // A delivered report or a verified-done check closes only an issue with no
    // branch: one this run committed to, or a resumed one whose earlier
    // commits are still unmerged.
    const retry = (stop === "report-delivered" || stop === "verified-done") && (branch || resumed);
    const why = "The run committed to a branch, or resumed one, so it retries instead of closing.";
    return routeStop(stop, { outcome, issueNumber, branch, humanLabel, runUrl, runId, onResumed, unmarked }, retry ? { route: "retry", why } : {});
  }
  // The outcome file is model output, so its own report never clears this.
  const failed = checkFailures(checks);
  if (failed.length) {
    return routeStop("check-failed", {
      outcome: {
        ...outcome,
        exit: "stopped",
        reason: "The run reported done, but a check the runner ran on the branch failed or could not be read, so it is not finished.",
        notDone: [...failed, ...outcome.notDone],
      },
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
    });
  }
  if (outcome.notDone.some(({ required }) => required)) {
    return routeStop("required-undone", {
      outcome: {
        ...outcome,
        exit: "stopped",
        reason: "The run reported done but left a required check undone, so it is not finished.",
      },
      issueNumber,
      branch,
      humanLabel,
      runUrl,
      runId,
    });
  }
  // A PR that names work it leaves for later links without closing.
  const refs = outcome.remaining.length > 0;
  const hold = mustHold({ issueLabels, humanMerge, holdPaths, changedFiles, checks });
  // The sections of the PR body contract (.claude/rules/pr-body-contract.md),
  // in the org PR template's order, with the run's gaps above the work.
  const gaps = outcome.notDone.map(({ what }) => what);
  const body = [
    refs ? `Refs: #${issueNumber}` : `Closes #${issueNumber}`,
    // A second Refs number would make a Refs PR name no issue (refsIssue).
    ...linkage.filter((line) => !(refs && line.startsWith("Refs:"))),
    ...(hold ? ["", HOLD_LINE] : []),
    "",
    "## Summary",
    "",
    "Opened by the work-resolve-issue lane. The run's own summary:",
    "",
    quoted(outcome.summary),
    // lane.json is rewritable, so this line only informs; it never changes the plan.
    ...(overCap ? ["", `The run went past its turn budget (turns=${overCap.turns} max-turns=${overCap.cap}): the work may be too big for one run.`] : []),
    ...(refs ? ["", "## Remaining work", "", bullets(outcome.remaining)] : []),
    ...(gaps.length ? ["", "## Not verified", "", bullets(gaps)] : []),
    "",
    "## Fix",
    "",
    outcome.changes.length ? bullets(outcome.changes) : "The run listed no changes; the diff shows them.",
    "",
    "## Verification",
    "",
    checkLines(checks),
    "",
    outcome.verification.length ? `The run reports:\n\n${bullets(outcome.verification)}` : "The run listed no checks.\n",
    runUrl ? `- The lane run: ${runUrl}` : "- The lane run.",
    "",
    gaps.length ? "Left out: the items under Not verified." : "Left out: nothing the run reported.",
    "",
    "## Related",
    "",
    `#${issueNumber}`,
  ].join("\n");
  return {
    action: "open-pr",
    issueNumber,
    title: prTitle(outcome.title, issueTitle, issueNumber),
    body,
    branch,
    hold,
  };
}

function humanLabelFrom(path) {
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
  // agent-ready starts this lane, so a pushback adding it would start the
  // next run itself.
  if (label.trim().toLowerCase() === "agent-ready") {
    throw new Error("the human-gated role label is agent-ready");
  }
  return label;
}

// The outcomes after which the next run continues the marked run's branch.
// work-unblock's `failed` names the limit or funding stop's run it ends.
export const RESUMABLE = new Set(["turn-cap", "stopped", "limited", "funding", "retry", "wait", "host-run", "attended", "failed"]);

// The issue's lane branch name, capturing its run id and attempt.
const laneBranch = (issueNumber) => new RegExp(`^work-resolve-issue/issue-${issueNumber}-([1-9][0-9]*)-([1-9][0-9]*)$`);
export const isLaneBranch = (name, issueNumber) => laneBranch(issueNumber).test(name ?? "");
// The issue a lane branch name is for, or null for any other name.
export const laneBranchIssue = (name) => {
  const issue = /^work-resolve-issue\/issue-([1-9][0-9]*)-/.exec(name ?? "")?.[1];
  return issue && isLaneBranch(name, issue) ? Number(issue) : null;
};

// A commit the lanes App made through the API: verified, authored by the App
// and committed by web-flow (a branch name proves nothing about who pushed to
// it, and anyone can sign a commit naming the App's address as author).
const laneCommit = (commit, bot) =>
  commit?.commit?.verification?.verified === true && commit.author?.login === bot && commit.committer?.login === "web-flow";
// A resume carries every commit ahead of the default branch into the next PR,
// so each of them, not only the tip, must be the lanes App's. A listing cut
// short (null) passes none.
// A GET /compare answer's commits, or null when the listing (at most 250) is
// cut short.
export const listedCommits = (comparison) =>
  Array.isArray(comparison?.commits) && comparison.commits.length === comparison.total_commits ? comparison.commits : null;
export const allLaneCommits = (commits, bot) => Array.isArray(commits) && commits.length > 0 && commits.every((commit) => laneCommit(commit, bot));

export function readBranch(dir, issueNumber, key = "branch") {
  try {
    const branch = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"))?.[key];
    return isLaneBranch(branch, issueNumber) ? branch : "";
  } catch {
    return "";
  }
}

// The first of the issue's open closing PRs (closingPulls) in this repository
// that the lanes App or a listed human opened: anyone can write `Closes #N`, so
// an outsider's PR would let anyone stop the lane.
export const trustedCloser = (closing, { repo, bot, humans }) =>
  closing.find(({ author, repository }) => String(repository?.nameWithOwner ?? "").toLowerCase() === repo.toLowerCase() && trustedAuthor(author, { bot, humans }));
// Whether a GraphQL author is the lanes App or a listed human (by id).
const trustedAuthor = (author, { bot, humans }) =>
  (author?.__typename === "Bot" && (author.login === bot || `${author.login}[bot]` === bot)) || (author?.__typename === "User" && humans.has(author.databaseId));

// Whether an earlier run already did the issue's work, from facts read before
// the resolve-issue mint:
//   stop   a lanes-App PR from a lane branch is open, or an open PR in this
//          repository closes the issue and the lanes App or a listed human
//          opened it (anyone can write `Closes #N`, so an outsider's PR
//          would let anyone stop the lane);
//   reuse  the first lane branch, newest first, with commits ahead of the default branch,
//          a tip commit GitHub verified, authored by the lanes App and
//          committed by web-flow, as the App's API commits are (a branch
//          name proves nothing about who pushed to it, and anyone can sign
//          a commit naming the App's address as author),
//          no lanes-App PR in any state (a closed one was rejected or
//          merged) and no lanes-App outcome marker for its run (that report
//          already handed the work on, so the model runs again);
//   resume the newest lanes-App outcome marker, passing over those of resumed
//          runs that kept no branch, is turn-cap, stopped, limited or funding
//          and names a run whose newest lane branch passes the same
//          tip, commit and PR checks, with every commit ahead of the default
//          branch verified, by the lanes App, committed by web-flow, and no
//          commit behind the default branch: the model runs on a new lane
//          branch made at that branch's tip (`tip`, the sha read), so it
//          continues the work instead of starting from the default branch.
//          A branch behind the default branch would carry its stale base into
//          the runner's whole-branch checks, so it starts fresh instead
//          (`stale` names it and the tip read) and is left as it is. With `keepBehind` it
//          resumes anyway: the read runner's issue-fields job re-derives a
//          claim made before the model ran, and the default branch may have
//          moved since;
//   run    otherwise.
// `branches` are {name, sha, aheadBy, behindBy, tip, tipAt, pulls, commits} (commits
// from GET /compare, null when the listing is cut short; tip from GET
// /commits/{sha}, tipAt epoch ms, pulls from
// GET /pulls?state=all&head=); `closing` the issue's open closing PRs as
// GraphQL nodes; `markers` the lanes App's parsed outcome markers, each with
// `at`. A marker naming no run, posted before markers named one, covers every
// branch whose tip is not newer than it.
export function findPrior({ issueNumber, repo, bot, humans, branches, closing, markers, keepBehind = false }) {
  const lane = laneBranches(branches, issueNumber);
  const byBot = (pull) => pull?.user?.login === bot;
  const open = lane.find(({ pulls }) => pulls.some((pull) => pull.state === "open" && byBot(pull)));
  if (open) {
    return { action: "stop", reason: `the lanes App's PR from ${open.name} is open` };
  }
  const trusted = trustedCloser(closing, { repo, bot, humans });
  if (trusted) {
    return { action: "stop", reason: `open PR #${trusted.number} closes the issue` };
  }
  const reported = reportedIn(markers);
  const laneTip = ({ tip }) => laneCommit(tip, bot);
  const usable = (branch) => branch.aheadBy > 0 && laneTip(branch) && !branch.pulls.some(byBot);
  const reuse = lane.find((branch) => usable(branch) && !reported(branch));
  if (reuse) {
    return { action: "reuse", branch: reuse.name };
  }
  const allLane = ({ commits }) => allLaneCommits(commits, bot);
  // Newest marker first. A resumable marker for a resumed run that kept no
  // branch of its own (`branch=resumed`) left the work on the run before it,
  // so it is passed over, and so is a dimension skip (a parked one included) or an outside-author stop, which ran nothing. The
  // first other marker decides: a resumable one
  // whose run's branch still passes resumes it; anything else (a pushback, a
  // marker naming no run, or a branch deleted or failing a check) starts
  // fresh, so deleting a resumed run's branch never falls back to an older one.
  const decisive = [...markers]
    .reverse()
    .find(
      (marker) =>
        !(marker.onResumed && RESUMABLE.has(marker.outcome)) &&
        !Object.hasOwn(DIMENSION_STEPS, marker.outcome) &&
        marker.outcome !== ROUTE_OUTCOME.park &&
        marker.outcome !== OUTSIDE_AUTHOR &&
        !RETIRED_SKIPS.has(marker.outcome),
    );
  const resume =
    RESUMABLE.has(decisive?.outcome) && decisive.run !== ""
      ? lane.find((branch) => branch.match[1] === decisive.run && usable(branch) && allLane(branch))
      : null;
  if (resume && resume.behindBy !== 0 && !keepBehind) {
    return { action: "run", stale: { branch: resume.name, tip: resume.sha, behindBy: resume.behindBy } };
  }
  return resume ? { action: "resume", branch: resume.name, tip: resume.sha, cause: decisive.outcome } : { action: "run" };
}

// The issue's lane branches, each with its name's match, newest run and
// attempt first.
const laneBranches = (branches, issueNumber) => {
  const shape = laneBranch(issueNumber);
  return branches
    .map((branch) => ({ ...branch, match: shape.exec(branch.name) }))
    .filter(({ match }) => match)
    .sort((a, b) => Number(b.match[1]) - Number(a.match[1]) || Number(b.match[2]) - Number(a.match[2]));
};
// Whether a lanes-App outcome marker reported a lane branch's run.
const reportedIn = (markers) => ({ match, tipAt }) =>
  markers.some((marker) => marker.run === match[1] || (marker.run === "" && !(marker.at <= tipAt)));

// At most this many branches are named to prune per run; the rest wait for
// the next run on the issue.
export const PRUNE_CAP = 20;

// The issue's lane branches a run deletes (owner decision on #7948): a stopped
// run's branch, one whose run posted an outcome marker and whose every commit
// ahead of the default branch is the lanes App's, with no pull request in any state, from the facts findPrior
// decided on, so it costs no read. Spared: the branch the run reuses, resumes
// or starts fresh past (`prior`), an unreported branch (reuse's), and every
// attempt of the run itself (`runId`). A branch someone else pushed to is kept
// for the daily branch cleanup.
export function pruneBranches({ issueNumber, bot, branches, markers, prior, runId = "" }) {
  const spared = new Set([prior?.branch, prior?.stale?.branch].filter(Boolean));
  const reported = reportedIn(markers);
  return laneBranches(branches, issueNumber)
    .filter((branch) => branch.pulls.length === 0 && laneCommit(branch.tip, bot) && allLaneCommits(branch.commits, bot) && reported(branch))
    .filter((branch) => branch.match[1] !== String(runId) && !spared.has(branch.name))
    .map(({ name }) => name)
    .slice(0, PRUNE_CAP);
}

// The listed humans' ids in trusted-actors.json; throws when it cannot be read.
export function readHumans(path) {
  const list = JSON.parse(readFileSync(path, "utf8"));
  if (list?.version !== 1 || !Array.isArray(list.actors)) {
    throw new Error("the trusted-actor list does not match its schema");
  }
  return new Set(list.actors.filter((actor) => actor?.kind === "human" && Number.isInteger(actor.id)).map((actor) => actor.id));
}

// The listed humans, or none when the list cannot be read: a count since a
// human last added agent-ready then counts every marker, so the lane
// restarts less, never more.
function readHumansOrNone(path) {
  try {
    return readHumans(path ?? "");
  } catch {
    return new Set();
  }
}

// The runner's limit record in lane.json: {resets} (epoch ms, or null when
// the run named none) when the run's class is rate-limit, else null.
export function readLimit(dir) {
  try {
    const lane = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"));
    if (lane?.class !== "rate-limit") {
      return null;
    }
    const resets = ISO.test(lane.resets ?? "") ? Date.parse(lane.resets) : Number.NaN;
    return { resets: Number.isFinite(resets) ? resets : null };
  } catch {
    return null;
  }
}

// Why the run never started, from lane.json's class, or null: the runner set
// issue-edited when write-issue refused because the issue's title or body
// changed after the label, issue-edited-trusted when only listed accounts
// changed them, and issue-file when it wrote no issue file for another
// reason. Either way no model ran.
export const ISSUE_STOPS = {
  "issue-edited":
    "The run did not start: the issue's title or body changed after `agent-ready` was added, so the runner wrote no issue file for the skill and no model ran.",
  "issue-edited-trusted":
    "The run did not start: the issue's title or body changed after `agent-ready` was added, each change by a listed account, so the runner wrote no issue file for the skill and no model ran.",
  "issue-file":
    "The run did not start: the runner could not write the issue file for the skill, so no model ran. The run job's `Write the issue for the skill` step names the reason.",
};
export function readIssueStop(dir) {
  try {
    const stop = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"))?.class;
    return Object.hasOwn(ISSUE_STOPS, stop ?? "") ? ISSUE_STOPS[stop] : null;
  } catch {
    return null;
  }
}

// The runner's funding record in lane.json: {regain} (epoch ms, or null when
// no date is readable) when the run failed on a spend limit or zero balance
// (api_error_status 400 with "regain access on <date>") or a disabled key
// (401), else null. The stop text's shape is the one ci-workflows#781 records.
const REGAIN = /regain access on ([^.\n"]{1,80})/i;
export function readFunding(dir) {
  try {
    const lane = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"));
    if (lane?.failed !== "true") {
      return null;
    }
    const text = typeof lane["error-text"] === "string" ? lane["error-text"].slice(0, 2000) : "";
    if (lane["api-error-status"] === "401") {
      return { regain: null };
    }
    const match = lane["api-error-status"] === "400" ? REGAIN.exec(text) : null;
    if (!match) {
      return null;
    }
    const regain = Date.parse(match[1].trim());
    return { regain: Number.isFinite(regain) ? regain : null };
  } catch {
    return null;
  }
}

// The runner's turn-cap record in lane.json: {cap} (the run's --max-turns, or
// null when unreadable) when the run's class is max-turns, else null. A leg
// run-claude-cli stopped at its leg timeout (class timeout) ran out of time
// the same way, so it is the same record with `timeout: true` and no cap: it
// restarts from its branch under limits.turn-cap-restarts, never stops.
export function readTurnCap(dir) {
  try {
    const lane = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"));
    if (lane?.class === "timeout") {
      return { cap: null, timeout: true };
    }
    if (lane?.class !== "max-turns") {
      return null;
    }
    return { cap: /^[1-9][0-9]{0,5}$/.test(lane["max-turns"] ?? "") ? Number(lane["max-turns"]) : null };
  } catch {
    return null;
  }
}

// The runner's over-cap record in lane.json: {turns, cap} when the run took
// more turns than its --max-turns and still ended, else null. run-claude-cli
// counts such a run a success, so its class is empty.
export function readOverCap(dir) {
  try {
    const lane = JSON.parse(readFileSync(join(dir, "lane.json"), "utf8"));
    const count = (value) => (/^[1-9][0-9]{0,5}$/.test(value ?? "") ? Number(value) : null);
    const [turns, cap] = [count(lane?.turns), count(lane?.["max-turns"])];
    return turns !== null && cap !== null && turns > cap ? { turns, cap } : null;
  } catch {
    return null;
  }
}

// When a listed human last set the Work status field (`fieldId`) to
// agent-ready, among resolve-config fieldEvents (admission-record.mjs
// personAdmissions), else -Infinity. Anyone else's set, the lanes App's
// restarts included, resets nothing, so it cannot buy restarts.
export async function humanSince(fieldEvents, fieldId, humans) {
  if (fieldId == null) {
    return Number.NEGATIVE_INFINITY;
  }
  const { personAdmissions } = await admissionLib();
  return personAdmissions(fieldEvents, { fieldId, humans }).at(-1)?.at ?? Number.NEGATIVE_INFINITY;
}

// The turn-cap restarts since `since` (humanSince): the lanes App's turn-cap
// markers after that, other than this run's own.
export const countTurnCapRestarts = (args) => countRestarts({ ...args, outcome: "turn-cap" });

// The lanes App's `outcome` markers after `since` (humanSince), other than
// this run's own: turn-cap restarts, or stop retries.
function restartMarkers({ comments, since, bot, runId, outcome }) {
  return comments
    .map((comment) => (comment.user?.login === bot ? { ...parseOutcomeMarker(comment.body), at: Date.parse(comment.created_at), fault: faultComment(comment.body) } : null))
    .filter((marker) => marker?.outcome === outcome && marker.run !== runId && marker.at > since);
}
export const countRestarts = (args) => restartMarkers(args).length;

// Whether a stop comment names a fault row, on the line after its marker
// (stopPlan). A marker with no such line counts as no fault.
const FAULT_STOPS = Object.keys(STOP_ROUTES).filter(stopFault).map(stopLine);
const faultComment = (body) => {
  const line = String(body ?? "").split(/\r?\n/, 2)[1] ?? "";
  return FAULT_STOPS.some((stop) => line.startsWith(stop));
};

// Whether a retry past its cap holds rather than taking retry-spent's route
// (docs/outage-posture-audit.md, element 4): a fault is no evidence about the
// issue, so while this stop and every counted retry were faults, the lane stops
// nothing. It posts no marker, so work-unblock's sweep restarts the issue on the
// stranded backoff, past its cap on retry markers. That needs this run to have
// made no branch of its own, which with no marker the next run would open a PR
// from (findPrior's reuse), its failed checks and all, so such a stop still
// takes the route. A cap of 0 counts no retry, so it takes the route too.
const spentOnFaults = (plan, markers, runId, limits) =>
  plan.action === "retry" &&
  stopFault(plan.stop) &&
  markers.length > 0 &&
  markers.length >= stopRetries(plan.stop, limits["stop-retries"]) &&
  markers.every((marker) => marker.fault) &&
  (!plan.stopArgs.branch || laneBranch(plan.issueNumber).exec(plan.stopArgs.branch)?.[1] !== runId);

// A read, GraphQL queries included, and a write marked safeToResend, is sent
// again after a network error or a 5xx (retry-fetch.mjs).
function api({ fetch: rawFetch, apiUrl, token, sleep }) {
  const fetch = retryFetch(rawFetch, { sleep });
  return async (method, path, body, { safeToResend = false } = {}) => {
    const response = await fetch(`${apiUrl}${path}`, {
      method,
      safeToResend,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    if (!response.ok) {
      throw Object.assign(new Error(`${method} ${path} answered ${response.status}`), { status: response.status });
    }
    return response.status === 204 ? null : response.json();
  };
}

// Every page of a list endpoint, 100 per page. A script activity runs from a
// copy of its own directory (collect-base-activity), so this is not imported.
async function paginate(github, path, maxPages = 50) {
  const items = [];
  const separator = path.includes("?") ? "&" : "?";
  for (let page = 1; page <= maxPages; page += 1) {
    const batch = await github("GET", `${path}${separator}per_page=100&page=${page}`);
    if (!Array.isArray(batch)) {
      throw new Error(`${path} answered something other than a list`);
    }
    items.push(...batch);
    if (batch.length < 100) {
      return items;
    }
  }
  throw new Error(`${path} has more than ${maxPages} pages`);
}

const CLOSING_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      closedByPullRequestsReferences(first: 100, after: $after, includeClosedPrs: false) {
        nodes { number state author { __typename login ... on User { databaseId } } repository { nameWithOwner } }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

// Every open PR that closes the issue, across pages, so no number of other
// PRs can push a trusted one out of reach. `includeClosedPrs: false` still
// lists a merged PR, so each node's state decides.
export async function closingPulls(github, { owner, name, number }, maxPages = 50) {
  const nodes = [];
  let after = null;
  for (let page = 1; page <= maxPages; page += 1) {
    const answer = await github("POST", "/graphql", { query: CLOSING_QUERY, variables: { owner, name, number, after } });
    const refs = answer?.data?.repository?.issue?.closedByPullRequestsReferences;
    if (answer?.errors?.length || !Array.isArray(refs?.nodes)) {
      throw new Error("the issue's closing pull requests could not be read");
    }
    if (!refs.nodes.every((node) => typeof node?.state === "string")) {
      throw new Error("the issue's closing pull requests answered one with no state");
    }
    nodes.push(...refs.nodes.filter((node) => node.state === "OPEN"));
    if (typeof refs.pageInfo?.hasNextPage !== "boolean") {
      throw new Error("the issue's closing pull requests answered no page information");
    }
    if (!refs.pageInfo.hasNextPage) {
      return nodes;
    }
    after = refs.pageInfo.endCursor;
    if (typeof after !== "string" || after === "") {
      throw new Error("the issue's closing pull requests answered a next page with no cursor");
    }
  }
  throw new Error(`the issue has more than ${maxPages} pages of closing pull requests`);
}

// The marker of report-outcome's comment naming a stale lane branch a fresh
// run left behind, once per branch.
export const staleMarker = (branch) => `<!-- work-resolve-issue stale-branch=${branch} -->`;
const staleNoted = (body, branch) => String(body ?? "").split(/\r?\n/, 1)[0] === staleMarker(branch);
export const staleComment = (branch) =>
  `${staleMarker(branch)}\nThis run started fresh from the default branch instead of resuming \`${branch}\`, which is behind it. That branch keeps the earlier run's commits until the next run on this issue deletes it, when no pull request uses it.`;

// --find-prior: reads the facts findPrior decides on and writes its step
// outputs. A failed read, or an answer of the wrong shape, holds
// (docs/outage-posture-audit.md, element 2): green with a notice and
// proceed=false, so no model runs and no mint follows, with no branch to reuse
// or prune. agent-ready stays and no marker goes up, so work-unblock's sweep
// starts the issue again. The re-derive fails instead: its job continues on the
// error, and that failure is what withholds the run's branch claim
// (pr-run-activity-read.yml).
export async function findPriorMain({ env = process.env, fetch = globalThis.fetch, sleep } = {}) {
  const keepBehind = env.FIND_PRIOR_KEEP_BEHIND === "true";
  let reading = false;
  try {
    if (!/^[1-9][0-9]{0,9}$/.test(env.ISSUE_NUMBER ?? "")) {
      throw new Error("ISSUE_NUMBER is not an issue number");
    }
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const issueNumber = Number(env.ISSUE_NUMBER);
    const [owner, name] = env.GITHUB_REPOSITORY.split("/");
    const repo = `/repos/${env.GITHUB_REPOSITORY}`;
    const bot = env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]";
    const humans = readHumans(env.TRUSTED_ACTORS_PATH ?? "");
    const github = api({ fetch, apiUrl: env.GITHUB_API_URL || "https://api.github.com", token: env.GH_TOKEN, sleep });
    reading = true;
    const appComments = (await paginate(github, `${repo}/issues/${issueNumber}/comments`)).filter((comment) => comment.user?.login === bot);
    const markers = appComments
      .map((comment) => ({ ...parseOutcomeMarker(comment.body), at: Date.parse(comment.created_at) }))
      .filter((marker) => marker.outcome !== undefined);
    // A marker naming no run is matched by its time, so that time must read.
    if (markers.some((marker) => marker.run === "" && !Number.isFinite(marker.at))) {
      throw new Error("a lane outcome marker that names no run has no readable time");
    }
    const closing = await closingPulls(github, { owner, name, number: issueNumber });
    const shape = laneBranch(issueNumber);
    // The trailing `-` keeps one issue's prefix from matching a longer
    // issue number that starts with the same digits.
    const matching = await github("GET", `${repo}/git/matching-refs/heads/work-resolve-issue/issue-${issueNumber}-`);
    if (!Array.isArray(matching)) {
      throw new Error("the issue's lane branches could not be read");
    }
    const refs = matching
      .map((ref) => ({ name: String(ref.ref ?? "").replace(/^refs\/heads\//, ""), sha: ref.object?.sha }))
      .filter((ref) => shape.test(ref.name));
    const base = refs.length ? (await github("GET", repo))?.default_branch : "";
    if (refs.length && (typeof base !== "string" || base === "")) {
      throw new Error("the repository's default branch could not be read");
    }
    const legacy = markers.some((marker) => marker.run === "");
    const branches = [];
    for (const ref of refs) {
      const comparison = await github("GET", `${repo}/compare/${encodeURIComponent(base)}...${encodeURIComponent(ref.name)}`);
      if (!Number.isSafeInteger(comparison?.ahead_by) || comparison.ahead_by < 0) {
        throw new Error(`the commits ${ref.name} holds ahead of ${base} could not be read`);
      }
      if (!Number.isSafeInteger(comparison.behind_by) || comparison.behind_by < 0) {
        throw new Error(`the commits ${ref.name} lacks from ${base} could not be read`);
      }
      const pulls = await paginate(github, `${repo}/pulls?state=all&head=${encodeURIComponent(`${owner}:${ref.name}`)}`);
      if (!/^[0-9a-f]{40}$/.test(ref.sha ?? "")) {
        throw new Error(`the tip of ${ref.name} could not be read`);
      }
      const tip = await github("GET", `${repo}/commits/${ref.sha}`);
      // Only a marker naming no run needs the tip's time.
      const tipAt = legacy ? Date.parse(tip?.commit?.committer?.date) : Number.NaN;
      if (legacy && !Number.isFinite(tipAt)) {
        throw new Error(`the tip commit time of ${ref.name} could not be read`);
      }
      // The compare listing holds at most 250 commits; a branch it cuts short
      // carries no commit list, so it is never resumed.
      const commits =
        Array.isArray(comparison.commits) && comparison.commits.length === comparison.total_commits ? comparison.commits : null;
      branches.push({ name: ref.name, sha: ref.sha, aheadBy: comparison.ahead_by, behindBy: comparison.behind_by, tip, tipAt, pulls, commits });
    }
    reading = false;
    const prior = findPrior({ issueNumber, repo: env.GITHUB_REPOSITORY, bot, humans, branches, closing, markers, keepBehind });
    const runs = prior.action === "run" || prior.action === "resume";
    // A stopped run's leftover branches, deleted by work-resolve-issue.yml's
    // prune job, which re-checks each; a stop names none.
    const prune =
      runs || prior.action === "reuse"
        ? pruneBranches({ issueNumber, bot, branches, markers, prior, runId: env.GITHUB_RUN_ID ?? "" })
        : [];
    const pruned = prune.length ? { "prune-branches": prune.join(" ") } : {};
    const outputs = runs
      ? {
          proceed: "true",
          "skip-reason": "",
          "reuse-branch": "",
          ...(prior.action === "resume"
            ? { "resume-branch": prior.branch, "resume-tip": prior.tip, "resume-cause": prior.cause }
            : {}),
          // A fresh start past a stale branch: write-issue gives the model its
          // commits as data, and report-outcome names it on the issue unless
          // a lanes App comment already does (stale-noted).
          ...(prior.stale
            ? {
                "stale-branch": prior.stale.branch,
                "stale-tip": prior.stale.tip,
                "stale-noted": String(appComments.some((comment) => staleNoted(comment.body, prior.stale.branch))),
              }
            : {}),
          ...pruned,
        }
      : { proceed: "false", "skip-reason": "not-applicable", "reuse-branch": prior.action === "reuse" ? prior.branch : "", ...pruned };
    appendFileSync(env.GITHUB_OUTPUT, Object.entries(outputs).map(([key, value]) => `${key}=${value}\n`).join(""));
    console.log(
      prior.stale
        ? `report-outcome: ${prior.stale.branch} is ${prior.stale.behindBy} commits behind the default branch, so the model starts issue #${issueNumber} fresh from the default branch instead of resuming it; the branch is left as it is`
        : prior.action === "run"
        ? `report-outcome: no earlier run of issue #${issueNumber} left work to report; the model runs`
        : prior.action === "resume"
          ? `report-outcome: the model resumes issue #${issueNumber} from ${prior.branch} at ${prior.tip} (${prior.cause})`
          : prior.action === "reuse"
          ? `report-outcome: ${prior.branch} holds unreported work for issue #${issueNumber}; the work is skipped, a summary pass describes it and report-outcome opens its PR`
          : `report-outcome: ${prior.reason}; the model is skipped`,
    );
    return 0;
  } catch (error) {
    const message = String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ");
    if (reading && !keepBehind) {
      appendFileSync(env.GITHUB_OUTPUT, "proceed=false\n");
      console.log(`::notice title=report-outcome::could not read this issue's earlier work (${message}); the model is skipped, and a later run reads it again`);
      return 0;
    }
    console.log(`::error title=report-outcome::${message}`);
    return 1;
  }
}

// A hand-back, host-run, attended or fail plan's edits. The state first, so a
// failed comment still leaves the issue on its route. A fail plan writes its
// comment first: the comment's marker is the route, so a failed post leaves
// the Work status at agent-ready for work-unblock's stranded sweep. Adding a
// label the issue has leaves the same labels, so it is resent; the comment is
// not. An empty plan.comment posts none: the comment is already on the issue.
// A plan's `status`, a hand-back's human label or a park's status: confirmed,
// names a Work status state by one of its labels (`stateOf`, over
// models.issue-status labels), which `setStatus(number, state)` (baseStatus)
// writes; no status label is written. An intake, fail or outside-author stop
// moves a Work status still at agent-ready to needs-triage
// (`leaveAgentReady`) after its comment.
async function applyHandBack(github, repo, plan, { setStatus = async () => {}, leaveAgentReady = async () => {}, stateOf } = {}) {
  const comment = async () => plan.comment && github("POST", `${repo}/issues/${plan.issueNumber}/comments`, { body: plan.comment });
  // A host-run or attended stop carries both: its label goes on first, so the
  // issue is held off the lane before Work status leaves agent-ready.
  if (plan.addLabels.length) {
    await github("POST", `${repo}/issues/${plan.issueNumber}/labels`, { labels: plan.addLabels }, { safeToResend: true });
  }
  if (plan.status) {
    // A park leaves a hold a person set during the run (write-status.mjs
    // keepHold): the issue stays as that person left it.
    const moved = await setStatus(plan.issueNumber, await stateOf(plan.status), plan.status === PARK_STATUS ? { keepHold: true } : undefined);
    if (moved?.outcome === "held") {
      console.log(`report-outcome: issue #${plan.issueNumber} left as is: a person's Work status ${moved.state} holds it`);
      return;
    }
  } else if (!plan.addLabels.length) {
    await comment();
  }
  if (TRIAGE_AGAIN.has(plan.exit)) {
    await leaveAgentReady(plan.issueNumber, "needs-triage");
  }
  if (plan.status || plan.addLabels.length) {
    await comment();
  }
  console.log(`report-outcome: handed issue #${plan.issueNumber} back (${plan.exit})`);
}

// `pr` read as a pull request in this repository: "open" while it is open and
// the lanes App or a listed human opened it (trustedAuthor, as closed-by-open-pr
// takes its closer: anyone can open one), "untrusted" while it is open and
// someone else opened it, else "". A read that fails is "", so the stop
// retries instead of waiting.
const openPull = (github, repo, pr, { bot, humans }) =>
  pr
    ? github("GET", `${repo}/pulls/${pr}`).then(
        (pull) =>
          pull?.state === "open" && pull.merged_at == null
            ? trustedAuthor({ __typename: pull.user?.type, login: pull.user?.login, databaseId: pull.user?.id }, { bot, humans })
              ? "open"
              : "untrusted"
            : "",
        () => "",
      )
    : Promise.resolve("");

// A stop plan's edits. A wait on a pull request that is not open or that
// neither the lanes App nor a listed human opened, and an already-done close
// that doneEvidence does not prove, retry instead. A retry, wait or intake
// first counts its own outcome's markers since a listed human last set the
// Work status to agent-ready (humanSince): past its cap it holds when every retry was a fault
// (spentOnFaults), and otherwise takes retry-spent's route (security-risk's hold
// for an intake round that is a pushbackSecurity stop), so an issue intake
// keeps sending back cannot loop. An earlier round's security reading does not
// carry over: intake triage re-judged it before admitting the issue again. A
// retry or wait under the cap posts its comment once per run (a rerun of this
// report finds its own marker) and keeps agent-ready. A close comments, closes
// the issue as completed, then removes host-run. `setStatus` is
// applyHandBack's, `statusOf` and `field` (refireStale's) redispatch's, and
// `appId` the lanes App's user id.
async function finishStop(github, repo, plan, { bot, appId, humans, runId, limits, lane = {}, verifyClose = "", setStatus, leaveAgentReady, statusOf, stateOf, field = NO_FIELD }) {
  const waited = plan.action === "wait" ? await openPull(github, repo, plan.pr, { bot, humans }) : "";
  if (plan.action === "wait" && waited !== "open") {
    const why = !plan.pr
      ? "Its reason names no pull request, so it retries instead."
      : waited === "untrusted"
        ? `#${plan.pr} was not opened by the lanes App or a listed human, so it retries instead.`
        : `#${plan.pr} is not an open pull request here, so it retries instead.`;
    plan = routeStop(plan.stop, plan.stopArgs, { limits, route: "retry", why });
  }
  if (plan.action === "close" && plan.stop === "already-done" && !(await doneEvidence(github, repo, plan.stopArgs.outcome?.reason, plan.issueNumber))) {
    const why =
      "Its reason cites no pull request merged into the default branch, or commit on it, made after the issue opened whose commit message closes this issue, so it retries instead of closing.";
    plan = routeStop(plan.stop, plan.stopArgs, { limits, route: "retry", why });
  }
  // A verified-done close: the run checked the issue's own done-when, and its
  // sub-issues, read fresh, are each closed as completed and among the
  // admit job's trusted closes (VERIFY_CLOSE).
  const trustedSubs = new Set(String(verifyClose).split(",").filter((number) => /^[1-9][0-9]{0,9}$/.test(number)).map(Number));
  if (plan.action === "close" && plan.stop === "verified-done" && !(await parentDone(github, repo, plan.issueNumber, async (number) => trustedSubs.has(Number(number))))) {
    const why =
      "Not every sub-issue of this issue is closed as completed by a listed human or a merge, as the run's admission read them, so it retries instead of closing.";
    plan = routeStop(plan.stop, plan.stopArgs, { limits, route: "retry", why });
  }
  let history = null;
  const read = async () => {
    if (history === null) {
      const comments = await paginate(github, `${repo}/issues/${plan.issueNumber}/comments`);
      const fieldEvents = await field.events(plan.issueNumber);
      history = { comments, fieldEvents, fieldId: field.id, since: await humanSince(fieldEvents, field.id, humans), appId, bot, humans, runId };
    }
    return history;
  };
  if (COUNTED.has(plan.action)) {
    const counted = { ...(await read()), outcome: plan.exit };
    if (spentOnFaults(plan, restartMarkers(counted), runId, limits)) {
      console.log(`::notice title=report-outcome::issue #${plan.issueNumber} stopped on a fault (${plan.stop}), and every retry since a person last added agent-ready was one too; it keeps agent-ready and a later run tries again`);
      return;
    }
    plan = capRetries(plan, countRestarts(counted), limits);
  }
  // Every plan above is final here, rebuilt or not, so each takes the run's tags.
  plan = withCredential(plan, lane);
  // A hold whose answer this run never read re-dispatches once instead. A
  // failed read takes the hold, as before.
  if (plan.action === "hand-back" && ANSWERED_STOPS.has(plan.stop)) {
    const late = await read().then(lateRecord, () => null);
    if (late && (await redispatch(github, repo, plan, late, { runId, statusOf, field, appId }))) {
      console.log(`report-outcome: issue #${plan.issueNumber} got a record after its admission (${late.comment.html_url}); a fresh run reads it`);
      return;
    }
  }
  if (KEPT.has(plan.action)) {
    const posted = history.comments.some((comment) => {
      const marker = comment.user?.login === bot ? parseOutcomeMarker(comment.body) : null;
      return marker?.outcome === plan.exit && runId !== "" && marker.run === runId;
    });
    if (!posted) {
      await github("POST", `${repo}/issues/${plan.issueNumber}/comments`, { body: plan.comment });
    }
    console.log(
      plan.action === "wait"
        ? `report-outcome: issue #${plan.issueNumber} waits on #${plan.pr} (${plan.stop}); it keeps agent-ready and work-unblock restarts it once #${plan.pr} merges or closes`
        : `report-outcome: issue #${plan.issueNumber} stopped (${plan.stop}); it keeps agent-ready and work-unblock retries it`,
    );
    return;
  }
  // A park writes admission's comment before its labels, as label-unblocked's
  // parkDone does: intake-reenter lifts status: confirmed only beside it.
  if (plan.action === "park") {
    const base = `${repo}/issues/${plan.issueNumber}`;
    await sayWhy(github, repo.slice("/repos/".length), base, (await read()).comments, refusalText(plan.admission), bot);
  }
  await applyHandBack(github, repo, plan, { setStatus, leaveAgentReady, stateOf });
  if (plan.action === "close") {
    const base = `${repo}/issues/${plan.issueNumber}`;
    // A label DELETE is idempotent (a 404 counts as removed), so it is resent
    // after a 5xx.
    const resend = (method, path) => github(method, path, undefined, { safeToResend: true });
    const had = (await github("GET", base))?.labels ?? [];
    await github("PATCH", base, { state: "closed", state_reason: "completed" }, { safeToResend: true });
    const states = await stripStateLabels(resend, base, had);
    console.log(`report-outcome: closed issue #${plan.issueNumber} (${plan.stop}); removed ${states.length} state label(s)`);
  }
}

// The Work status field (NO_FIELD's shape) over `github`, a createGitHub
// client, and the modules baseStatus loads. `reader` is read-status.mjs
// statusReader's and `restart(number)` write-status.mjs statusWriter's, which
// removes the value and sets agent-ready, answering {outcome: "held"} on a
// listed human's hold. The state is read again just before it, since a
// removal clears whatever value a person set since the caller's read.
export function workStatusField({ github, repository, config, reader, fieldEvents, restart }) {
  if (!config) {
    return NO_FIELD;
  }
  const state = async (number) => {
    await reader(number, []);
    return reader.state(number);
  };
  return {
    id: String(config["field-id"]),
    state,
    events: (number) => fieldEvents(github, repository, Number(number)),
    async restart(number, from) {
      if ((await state(number)) !== from) {
        return false;
      }
      const outcome = (await restart(Number(number), { from: from === null ? undefined : [from] }))?.outcome;
      return outcome !== "held" && outcome !== "moved";
    },
  };
}

// The Work status writer, reader and field (write-status.mjs statusWriter's
// set, read-status.mjs statusReader, workStatusField), loaded from the base
// checkout: this script runs from a copy of its own directory
// (collect-base-activity), where they are not beside it, and the field calls
// need createGitHub's headers, which api() does not send. When they cannot
// load, each call throws.
async function baseStatus(env) {
  try {
    const actions = resolve(env.BASE_PATH || ".base", ".github", "actions");
    const { statusWriter } = await import(pathToFileURL(join(actions, "resolve-config", "write-status.mjs")).href);
    const { statusReader } = await import(pathToFileURL(join(actions, "resolve-config", "read-status.mjs")).href);
    const { fieldEvents, issueStatusFromBase } = await import(pathToFileURL(join(actions, "resolve-config", "resolve-config.mjs")).href);
    const { createGitHub } = await import(pathToFileURL(join(actions, "check-trusted-trigger", "check-trusted-trigger.mjs")).href);
    const github = createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const repository = env.GITHUB_REPOSITORY;
    const { set, leaveAgentReady, restart } = await statusWriter({ env, github, repository });
    const statusOf = statusReader({ env, github, repository });
    const field = workStatusField({ github, repository, config: issueStatusFromBase(env), reader: statusOf, fieldEvents, restart });
    return { setStatus: set, leaveAgentReady, statusOf, field };
  } catch (error) {
    const fail = async () => {
      throw new Error(`the Work status writer and reader did not load: ${error?.message ?? error}`);
    };
    return { setStatus: fail, leaveAgentReady: fail, statusOf: fail, field: { id: null, state: fail, events: fail, restart: fail } };
  }
}

// The lanes App's user id: APP_SENDER_ID, else the trusted-actor list's bot
// entry for `bot`; NaN when neither names one, which no record or field event
// matches.
function appIdFrom(env, bot) {
  if (/^[1-9][0-9]*$/.test(env.APP_SENDER_ID ?? "")) {
    return Number(env.APP_SENDER_ID);
  }
  try {
    const actors = JSON.parse(readFileSync(env.TRUSTED_ACTORS ?? "", "utf8"))?.actors ?? [];
    const app = actors.find((actor) => actor?.kind === "bot" && actor.login === bot && Number.isSafeInteger(actor.id));
    return app ? app.id : Number.NaN;
  } catch {
    return Number.NaN;
  }
}

// The Work status state one of whose models.issue-status labels is `label`,
// read from the base checkout's config as baseStatus loads its modules; a
// label no state lists throws.
async function labelState(env, label) {
  const actions = resolve(env.BASE_PATH || ".base", ".github", "actions");
  const { issueStatusFromBase } = await import(pathToFileURL(join(actions, "resolve-config", "resolve-config.mjs")).href);
  const labels = issueStatusFromBase(env)?.labels ?? {};
  const state = Object.keys(labels).find((one) => labels[one].some((name) => name.toLowerCase() === label.toLowerCase()));
  if (state === undefined) {
    throw new Error(`models.issue-status gives no Work status state the label \`${label}\``);
  }
  return state;
}

// `setStatus(number, state)` writes the issue's Work status field,
// `statusOf(number, names)` reads its label names as the field decides them,
// and `field` reads and restarts the field (baseStatus at the command line).
export async function main({ env = process.env, fetch = globalThis.fetch, now = Date.now(), sleep, setStatus = async () => {}, leaveAgentReady = async () => {}, statusOf = async (number, names) => names, field = NO_FIELD } = {}) {
  const stateOf = (label) => labelState(env, label);
  const appId = appIdFrom(env, env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]");
  try {
    const issueNumber = Number(env.ISSUE_NUMBER);
    if (!/^[1-9][0-9]{0,9}$/.test(env.ISSUE_NUMBER ?? "")) {
      throw new Error("ISSUE_NUMBER is not an issue number");
    }
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const dimensionSkip = env.DIMENSION_SKIP ?? "";
    if (dimensionSkip && !Object.hasOwn(DIMENSION_STEPS, dimensionSkip) && dimensionSkip !== OUTSIDE_AUTHOR && dimensionSkip !== WORKFLOW_STALE) {
      throw new Error("DIMENSION_SKIP is not an issue-dimension skip reason");
    }
    const escalation = env.ESCALATION_REASON ?? "";
    if (escalation && !Object.hasOwn(PATCH_REASONS, escalation)) {
      throw new Error("ESCALATION_REASON is not an apply-issue-patch escalation reason");
    }
    const reuse = env.REUSE_BRANCH ?? "";
    const reused = laneBranch(issueNumber).exec(reuse);
    if (reuse && !reused) {
      throw new Error("REUSE_BRANCH is not this issue's lane branch");
    }
    const repo = `/repos/${env.GITHUB_REPOSITORY}`;
    const github = api({ fetch, apiUrl: env.GITHUB_API_URL || "https://api.github.com", token: env.GH_TOKEN, sleep });
    const runUrlOf = (id) => (env.GITHUB_SERVER_URL && id ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${id}` : "");
    const runUrl = runUrlOf(env.GITHUB_RUN_ID);
    const runId = /^[1-9][0-9]{0,14}$/.test(env.GITHUB_RUN_ID ?? "") ? env.GITHUB_RUN_ID : "";
    // A dimension skip, an outside-author stop or a stale stop left no outcome to read: no model ran.
    if (dimensionSkip === WORKFLOW_STALE) {
      const resolved = env.RESOLVED_CONFIG || join(env.RUNNER_TEMP ?? "", "resolved-config.json");
      const done = await refireStale(github, repo, issueNumber, {
        workflowSha: env.GITHUB_WORKFLOW_SHA,
        bot: env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]",
        appId,
        humans: readHumansOrNone(env.TRUSTED_ACTORS),
        limits: readLimits(resolved),
        statusOf,
        field,
      });
      console.log(`report-outcome: issue #${issueNumber} stopped on stale workflow files; ${done}`);
      return 0;
    }
    if (dimensionSkip === OUTSIDE_AUTHOR) {
      // A re-run finds the lanes App's own comment and posts none; the marker
      // from anyone else does not count, since the outside author can write it.
      const bot = env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]";
      const comments = await paginate(github, `${repo}/issues/${issueNumber}/comments`);
      const posted = comments.some((comment) => comment.user?.login === bot && parseOutcomeMarker(comment.body)?.outcome === OUTSIDE_AUTHOR);
      const plan = outsideAuthorPlan({ issueNumber, runUrl, runId });
      await applyHandBack(github, repo, posted ? { ...plan, comment: "" } : plan, { setStatus, leaveAgentReady, stateOf });
      return 0;
    }
    if (dimensionSkip) {
      const humanLabel = humanLabelFrom(env.TRACKER_CONFIG ?? ".base/docs/conventions/work-items.yaml");
      const resolved = env.RESOLVED_CONFIG || join(env.RUNNER_TEMP ?? "", "resolved-config.json");
      const plan = routeStop(dimensionSkip, { outcome: stopped(""), issueNumber, branch: "", humanLabel, runUrl, runId }, { why: DIMENSION_STEPS[dimensionSkip] });
      await finishStop(github, repo, plan, {
        bot: env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]",
        appId,
        humans: readHumansOrNone(env.TRUSTED_ACTORS),
        runId,
        limits: readLimits(resolved),
        setStatus,
        leaveAgentReady,
        statusOf,
        stateOf,
        field,
      });
      return 0;
    }
    const dir = env.WORK_OUTCOME_DIR ?? "";
    const ran = readBranch(dir, issueNumber);
    // The stale lane branch this run started fresh past, which issue-prior
    // found no comment naming: lane.json's `stale` (rewritable, so only a
    // name of this issue's lane-branch shape). The comment names it once so a
    // person can find and delete it; nothing deletes it. A failed post is
    // logged, and the next fresh start past it posts again.
    const stale = readBranch(dir, issueNumber, "stale");
    if (stale) {
      await github("POST", `${repo}/issues/${issueNumber}/comments`, { body: staleComment(stale) }).then(
        () => console.log(`report-outcome: named the stale lane branch ${stale} on issue #${issueNumber}`),
        (error) => console.log(`report-outcome: could not name the stale lane branch ${stale}: ${error.message}`),
      );
    }
    // On a reuse the downloaded outcome is the branch's own only when it names
    // that branch (a re-run attempt of the run that made it).
    let outcome = reuse && ran !== reuse ? null : readOutcome(join(dir, "work-outcome.json"));
    // A run whose scan refused its output left no outcome: say so.
    const refusal = !reuse && outcome?.unread && env.SCAN_REFUSED_DIR ? readScanRefusal(env.SCAN_REFUSED_DIR, env.GITHUB_RUN_ATTEMPT) : "";
    if (refusal) {
      outcome = { ...stopped(SCAN_REFUSALS[refusal]), unread: true, stop: `scan-refused-${refusal}` };
    }
    const branch = reuse || ran;
    // A resumed run that finished with no commit of its own deleted its
    // branch; decide() marks it so, and hands a done run back naming the
    // resumed branch.
    const resumed = branch ? "" : readBranch(dir, issueNumber, "resume");
    // run-checks checks the resumed branch when this run kept none of its own,
    // and only when lane.json's resume (rewritable) equals the branch
    // issue-prior chose before the mint, so results naming it vouch for it.
    const checkedBranch = branch || resumed;
    const checked = readChecks(env.RUNNER_CHECKS ?? "", { branch: checkedBranch });
    const limit = readLimit(dir);
    const turnCap = readTurnCap(dir);
    const overCap = readOverCap(dir);
    const funding = readFunding(dir);
    // A scan refusal means a model ran, so it outranks a not-started record.
    const issueStop = refusal ? null : readIssueStop(dir);
    const issue = await github("GET", `${repo}/issues/${issueNumber}`);
    const unreported = reuse && (outcome === null || outcome.unread);
    // The summary counts only while the branch is still at the tip it read; a
    // tip that cannot be read keeps the fixed text.
    let summary = unreported && env.REUSE_SUMMARY_DIR ? readSummary(env.REUSE_SUMMARY_DIR, { issueNumber, branch: reuse }) : null;
    if (summary) {
      const ref = reuse.split("/").map(encodeURIComponent).join("/");
      const tip = await github("GET", `${repo}/git/ref/heads/${ref}`).then(
        (answer) => answer?.object?.sha,
        () => "",
      );
      if (tip !== summary.tip) {
        console.log(`report-outcome: ${reuse} is not at the tip the summary read, so the PR keeps the fixed text`);
        summary = null;
      }
    }
    // The runner's check results count only while the branch is still at the
    // tip they checked; a tip that cannot be read counts as no results.
    // run-checks checks only this run's own lane branch (or the reuse branch),
    // so results for another run's branch were not written by it.
    // A resumed branch is the earlier run's, named by lane.json (rewritable),
    // so its results count only once every commit on it is the App's (below).
    const ownBranch = reuse !== "" || resumed !== "" || laneBranch(issueNumber).exec(branch)?.[1] === env.GITHUB_RUN_ID;
    let checks = checkedBranch && ownBranch && (unreported || outcome?.exit === "done") ? checked : null;
    if (checks) {
      const ref = checkedBranch.split("/").map(encodeURIComponent).join("/");
      const tip = await github("GET", `${repo}/git/ref/heads/${ref}`).then((answer) => answer?.object?.sha, () => "");
      if (tip !== checks.tip) {
        console.log(`report-outcome: ${checkedBranch} is not at the tip the runner checked, so its check results do not count`);
        checks = null;
      }
    }
    let base = "";
    let commits = null;
    const compare = async (head = branch) => {
      base = (await github("GET", repo)).default_branch;
      const comparison = await github("GET", `${repo}/compare/${encodeURIComponent(base)}...${encodeURIComponent(head)}`);
      // The listing holds at most 250 commits; one cut short lists none.
      commits = listedCommits(comparison);
      return (comparison.files ?? []).flatMap((file) =>
        file.previous_filename ? [file.filename, file.previous_filename] : [file.filename],
      );
    };
    const bot = env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]";
    let changedFiles = outcome?.exit === "done" && branch ? await compare() : [];
    if (outcome?.exit === "done" && resumed && checks) {
      // By the checked SHA: the name can move after the tip check above.
      changedFiles = await compare(checks.tip);
      if (!allLaneCommits(commits, bot)) {
        console.log(`report-outcome: ${resumed} holds a commit that is not the lanes App's, so its check results do not count`);
        checks = null;
      }
    }
    const resolvedPath = env.RESOLVED_CONFIG || join(env.RUNNER_TEMP ?? "", "resolved-config.json");
    const holdPaths = heldPaths(resolvedPath);
    // A reuse whose outcome cannot be read never takes the limit record: the
    // skipped run hit no limit, and a limited marker would loop restarts. A
    // failed compare leaves its file list unread, which holds the PR.
    const issueTitle = typeof issue.title === "string" ? issue.title : "";
    const issueLabels = (issue.labels ?? []).map((label) => label.name);
    // A labeler that cannot be read is null, which opens no PR (below). A trusted
    // list that cannot be read holds the PR, like an unreadable denied-path list.
    const humanMerge =
      issueLabels.includes(HUMAN_MERGE_LABEL) &&
      (await paginate(github, `${repo}/issues/${issueNumber}/events`)
        .then((events) => trustedLabeler(events, HUMAN_MERGE_LABEL, { bot, humans: readHumans(env.TRUSTED_ACTORS ?? "") }), () => null)
        .catch(() => true));
    const listedHumans = () => readHumansOrNone(env.TRUSTED_ACTORS);
    // Only an issue a listed human or the lanes App wrote supplies linkage
    // lines; an unreadable trusted list supplies none.
    const author = issue.user ?? {};
    const trustedIssue = (author.type === "User" && listedHumans().has(author.id)) || (author.type === "Bot" && author.login === bot);
    const linkage = trustedIssue ? linkageLines(issue.body, issueNumber) : [];
    const limits = readLimits(resolvedPath);
    // Only a turn cap with no outcome of the run's own reads the issue's history.
    const capped = !unreported && funding === null && turnCap !== null && outcome?.unread === true;
    const comments = capped ? await paginate(github, `${repo}/issues/${issueNumber}/comments`) : [];
    const turnCapRestarts = capped
      ? countTurnCapRestarts({
          comments,
          since: await humanSince(await field.events(issueNumber), field.id, listedHumans()),
          bot,
          runId,
        })
      : 0;
    const humanLabel = humanLabelFrom(env.TRACKER_CONFIG ?? ".base/docs/conventions/work-items.yaml");
    // Only a pushback reads the comments; a failed read leaves the link out.
    const unmarked =
      !unreported && outcome?.exit === "pushback"
        ? await paginate(github, `${repo}/issues/${issueNumber}/comments`)
            .then((list) => unmarkedAnswer(list, readHumans(env.TRUSTED_ACTORS ?? ""), bot))
            .catch(() => null)
        : null;
    let plan = unreported
      ? reusePlan({
          issueNumber,
          issueLabels,
          issueTitle,
          branch,
          runUrl,
          earlierRunUrl: runUrlOf(reused[1]),
          summary,
          changedFiles: await compare().catch(() => null),
          holdPaths,
          humanMerge,
          checks,
          linkage,
        })
      : decide({
          outcome,
          issueNumber,
          issueLabels,
          issueTitle,
          branch,
          resumed,
          changedFiles,
          holdPaths,
          humanMerge,
          humanLabel,
          runUrl,
          limit,
          turnCap,
          turnCapRestarts,
          overCap,
          funding,
          issueStop,
          limits,
          now,
          runId,
          checks,
          escalation,
          unmarked,
          collectRefused: env.COLLECT_REFUSED === "true",
          linkage,
        });
    const lane = readLaneCredential(dir);
    plan = withCredential(plan, lane);
    if (plan.action === "turn-cap") {
      // Once per run, like the limited marker: a rerun of this report finds
      // its own marker and posts nothing.
      const posted = comments.some((comment) => {
        const marker = comment.user?.login === bot ? parseOutcomeMarker(comment.body) : null;
        return marker?.outcome === "turn-cap" && runId !== "" && marker.run === runId;
      });
      if (!posted) {
        await github("POST", `${repo}/issues/${issueNumber}/comments`, { body: plan.comment });
      }
      console.log(`report-outcome: issue #${issueNumber} reached its turn cap; work-unblock restarts it`);
      return 0;
    }
    if (plan.action === "limited" || plan.action === "funding") {
      // Once per run: a rerun of this report, however late, finds its own
      // marker in the issue's whole comment history and posts nothing.
      const comments = await paginate(github, `${repo}/issues/${issueNumber}/comments`);
      const posted = comments.some((comment) => {
        const marker = comment.user?.login === bot ? parseOutcomeMarker(comment.body) : null;
        return marker?.outcome === plan.action && plan.runId !== "" && marker.run === plan.runId;
      });
      if (!posted) {
        await github("POST", `${repo}/issues/${issueNumber}/comments`, { body: plan.comment });
      }
      console.log(
        plan.action === "funding"
          ? `report-outcome: issue #${issueNumber} stopped on the lane's funding; it waits`
          : `report-outcome: issue #${issueNumber} stopped on the usage limit; restart after ${plan.resets}`,
      );
      return 0;
    }
    // Whether a person merges this PR is unknown, so it holds
    // (docs/outage-posture-audit.md, element 2): no PR, and no marker, so the
    // branch stays unreported, work-unblock's sweep starts the issue again, and
    // that run opens the PR from it.
    if (plan.action === "open-pr" && humanMerge === null) {
      console.log(`::notice title=report-outcome::could not read who added ${HUMAN_MERGE_LABEL} to issue #${issueNumber}; no PR opens from ${plan.branch}, and a later run reads it again`);
      return 0;
    }
    if (plan.action === "open-pr") {
      // A rerun finds the PR it already opened. Anyone can open a PR between two branches of a public repository, so
      // only one the lanes App opened is reused; otherwise the create fails.
      const owner = env.GITHUB_REPOSITORY.split("/")[0];
      const findOpen = async () =>
        (await github("GET", `${repo}/pulls?state=open&head=${encodeURIComponent(`${owner}:${plan.branch}`)}`)).find(
          (candidate) => candidate.user?.login === bot,
        );
      let pull = await findOpen();
      // A PR that closes the issue may have opened, or gained its closing
      // keyword, while the model ran, after the earlier-work check
      // (--find-prior) read none, so the closers are read again just before
      // the open. A failed read throws, like this script's other reads, and
      // opens no PR.
      const closer = pull
        ? undefined
        : trustedCloser(await closingPulls(github, { owner, name: env.GITHUB_REPOSITORY.split("/")[1], number: issueNumber }), {
            repo: env.GITHUB_REPOSITORY,
            bot,
            humans: listedHumans(),
          });
      if (closer) {
        console.log(`report-outcome: open PR #${closer.number} already closes issue #${issueNumber}, so no PR opens from ${plan.branch}`);
        plan = routeStop("closed-by-open-pr", {
          outcome: stopped(`Open PR #${closer.number} already closes this issue, so no second PR opened from \`${plan.branch}\`.`),
          issueNumber,
          branch: plan.branch,
          humanLabel,
          runUrl,
          runId,
        });
      } else {
        if (!pull) {
          const fields = { title: plan.title, body: plan.body, head: plan.branch, base: base || (await github("GET", repo)).default_branch, draft: false };
          try {
            pull = await github("POST", `${repo}/pulls`, fields);
          } catch (error) {
            // A create that failed on the network may have opened the PR, so
            // it is read back. A create is a non-idempotent write, which the
            // outage posture never sends twice (docs/outage-posture-audit.md,
            // element 1): when the read finds none, the run fails, and a
            // rerun's findOpen reuses the PR or opens it.
            if (!networkError(error)) {
              throw error;
            }
            pull = await findOpen();
            if (!pull) {
              throw new Error(`the PR create from ${plan.branch} failed on the network and no open PR from it reads back; the create is not sent again`, { cause: error });
            }
          }
        }
        // A held PR carries the hold label from its opening; one the label
        // cannot reach is closed rather than left held by body text alone.
        const labeled =
          !plan.hold ||
          (await github("POST", `${repo}/issues/${pull.number}/labels`, { labels: [HOLD_LABEL] }, { safeToResend: true }).then(
            () => true,
            (error) => {
              console.log(`::warning title=report-outcome::could not label PR #${pull.number} ${HOLD_LABEL}: ${String(error?.message ?? error)}`);
              return false;
            },
          ));
        // A plan with a tip opens only at it: a PR whose head moved off the
        // checked tip is closed, and the issue goes to a person. Closing a
        // closed PR changes nothing, so the close is resent.
        const moved = Boolean(plan.tip) && pull.head?.sha !== plan.tip;
        if (labeled && !moved) {
          console.log(`report-outcome: opened PR #${pull.number} for issue #${issueNumber}`);
          return 0;
        }
        await github("PATCH", `${repo}/pulls/${pull.number}`, { state: "closed" }, { safeToResend: true });
        console.log(
          moved
            ? `report-outcome: closed PR #${pull.number}: its head is not ${plan.tip}, the tip the runner checked`
            : `report-outcome: closed PR #${pull.number}: it holds for a person and could not be labeled ${HOLD_LABEL}`,
        );
        plan = routeStop(moved ? "pr-head-moved" : "hold-label-failed", {
          outcome: stopped(
            moved
              ? `The PR from \`${plan.branch}\` opened at a head other than ${plan.tip}, the tip the runner checked, so it was closed.`
              : `The PR from \`${plan.branch}\` holds for a person, and the \`${HOLD_LABEL}\` label could not be added, so it was closed.`,
          ),
          issueNumber,
          branch: plan.branch,
          humanLabel,
          runUrl,
          runId,
        });
      }
    }
    await finishStop(github, repo, plan, { bot, appId, humans: listedHumans(), runId, limits, lane, verifyClose: env.VERIFY_CLOSE ?? "", setStatus, leaveAgentReady, statusOf, stateOf, field });
    return 0;
  } catch (error) {
    console.log(`::error title=report-outcome::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = process.argv[2] === "--find-prior" ? await findPriorMain() : await main(await baseStatus(process.env));
}
