#!/usr/bin/env node
// report-outcome.mjs: the work-resolve-issue lane's report-outcome leaf. Reads
// what the resolve-issue run left and acts on the issue, with no model:
//
//   done      opens a ready PR from the run's branch: the body starts
//             `Closes #<issue>`, or `Refs: #<issue>` and a Remaining work
//             section when the run's `remaining` names the parts of the
//             issue it leaves for later work (a malformed list counts as
//             none); the merge lane reads a plain `Refs:` issue as it reads
//             a closing one. The title is the run's Conventional
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
//   hold hands the issue to a person as pushback does; host-run adds the
//   host-run label and removes agent-ready; attended adds the attended label
//   and removes agent-ready; retry keeps agent-ready, so
//   work-unblock restarts it, up to limits.stop-retries; wait keeps
//   agent-ready and names the open pull request the run waits on, so
//   work-unblock restarts it once that pull request merges or closes (a
//   pull request that is not open, or that neither the lanes App nor a
//   listed human opened, retries instead); intake removes
//   agent-ready and status: ready, so the triage sweep sends the issue back
//   through intake; park removes them too and parks the issue at
//   status: confirmed beside admission's comment naming the reason, as
//   admission parks a refusal no person answers; close closes the issue as
//   completed (an already-done
//   stop only once its cited commit or pull request is on the default
//   branch and its commit message closes the issue, doneEvidence, else it
//   retries); fail removes agent-ready and adds no label. A
//   route other than hold carries no escalation marker.
//
//   pushback  a reason that opens with a hold code (security-risk,
//             cost-risk, design-change, intent-change) takes that row; else
//             cause intent or intent-change (as stop-routes.mjs causeName
//             normalizes the cause) comments why, adds
//             the human-gated label, removes agent-ready; else a cause
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
//             allows a restart since a person last added agent-ready, it
//             keeps agent-ready and work-unblock restarts the issue; past
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
//             removes agent-ready, with no label, since a
//             retry stops again. No outcome file is read.
//   stale    the read runner stopped on stale workflow files before any model
//             turn (DIMENSION_SKIP workflow-stale): re-fires the issue at once
//             on main's files (refireStale). No outcome file is read.
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
//   GITHUB_WORKFLOW_SHA workflow-stale: the commit the run's workflow files
//                       come from
//   REUSE_SUMMARY_DIR   on a reuse, holds the summary pass's reuse-summary.json
//                       (runner-written issue, branch and tip; model output)
//   TRACKER_CONFIG      base .work-item-tracker.json, for the human-gated label
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
//   GITHUB_OUTPUT       --find-prior: the step output file
//   GITHUB_API_URL, GITHUB_SERVER_URL, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT
//                       (the attempt whose scan-refusal markers are read)
import { appendFileSync, lstatSync, readdirSync, readFileSync } from "node:fs";
import { join, posix } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { LIMIT_DEFAULTS, clampReset, readLimits } from "./limits.mjs";
import { networkError, retryFetch } from "./retry-fetch.mjs";
import { refusalText, sayWhy } from "../lib/admission-comment.mjs";
import { doneEvidence, RUN_WORDS, stopLine } from "../lib/done-evidence.mjs";
import { personReasonLines } from "../lib/stop-reason.mjs";
import { OUTSIDE_ACTOR_LABEL } from "../pr-merge/merge-holds.mjs";
import { ATTENDED_LABEL, causeName, HOST_RUN_LABEL, leadingCode, runCode, securityWord, STOP_ROUTES, stopReasonCode, stopRetries, stopRoute, stopWhy } from "./stop-routes.mjs";

export { doneEvidence };

export const HOLD_LINE = "Hold: a human merges this";
// The work class of an issue that asks for a report and no change.
const READ_ONLY_CLASS = "work-class: read-only";
// The label a held PR carries from its opening. The hold line is body text the
// lanes App can edit; ci-status fails while this label is on and unless a
// listed person's own removal took it off (merge-holds.mjs HUMAN_MERGE_HOLD).
export const HUMAN_MERGE_HOLD = "human-merge-hold";
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
// Work a human merges: an issue labeled untrusted-provenance, a trust hold
// and the one label read here, and any diff that touches a path the merge
// lane refuses (merge.diff-check.denied-paths in the base pr-pipeline.yaml),
// so the two lists cannot drift apart. No other work class holds.
const UNTRUSTED_PROVENANCE = "work-class: untrusted-provenance";
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
const MARKER = /^(?:<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\r?\n)?<!-- work-resolve-issue outcome=([a-z]+(?:-[a-z]+)*)(?: (security))?(?: resets=(\S+))?(?: cap=(\d+))?(?: pr=(\d+))?(?: run=(\d+))?(?: branch=(resumed))? -->/;

// `branch=resumed` marks a resumed run that kept no branch of its own, so its
// work is still on the branch it resumed (see findPrior).
const resumedTag = (yes) => (yes ? " branch=resumed" : "");

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

// {outcome, resets, run, onResumed, pr?, security?} from a comment body that opens with the lane's
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
    ...(match[5] && { pr: match[5] }),
    ...(match[2] && { security: true }),
  };
}

const stopped = (reason) => ({ exit: "stopped", reason, title: "", summary: "", changes: [], verification: [], notDone: [], steps: [] });
const text = (value) => (typeof value === "string" ? value.slice(0, MAX_TEXT) : "");
const list = (value) =>
  Array.isArray(value) ? value.filter((item) => typeof item === "string").slice(0, MAX_ITEMS).map((item) => item.slice(0, MAX_ITEM)) : [];
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
    .map(({ what, required }) => ({ what: what.slice(0, MAX_ITEM), required }));

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
// each with text left in the bullet it renders as. Anything else is empty, so
// the PR closes the issue.
function remainingList(value) {
  const items = Array.isArray(value) && value.length <= MAX_ITEMS && value.every((item) => typeof item === "string") ? value.map((item) => item.slice(0, MAX_ITEM)) : [];
  return items.every((item) => bullets([item]).slice(2)) ? items : [];
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
// The cap applies after escaping. A file path keeps its comments, escaped,
// so the whole name shows.
const neutral = (value, cap, { path = false } = {}) =>
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
    .replaceAll(/\bwww\./gi, "www .")
    .slice(0, cap)
    .replace(/&[a-z]*$|\\$/, "");

// Every line prefixed `> `, so no line of it can start a heading or leave the
// quote, and the text wraps when rendered.
const quoted = (value) =>
  neutral(value || "(none)", MAX_TEXT)
    .trim()
    .split("\n")
    .map((line) => (line.trim() ? `> ${line.trimEnd()}` : ">"))
    .join("\n");

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
      ? `To retry, answer the question in a comment whose first line is \`${DECISION_LINE}\`, then remove \`${humanLabel}\` and add \`agent-ready\` again.`
      : `To retry, remove \`${humanLabel}\` and add \`agent-ready\` again.`,
  );
  return {
    action: "hand-back",
    exit: outcome.exit,
    issueNumber,
    comment: lines.join("\n"),
    addLabels: [humanLabel],
    removeLabels: ["agent-ready"],
  };
}

// The comment and labels of a stop whose route is not hold, which carries no
// escalation marker: retry and wait keep agent-ready (work-unblock restarts it
// and the next run resumes the branch), host-run and attended add their
// label, intake removes the status labels admission reads, park removes them
// and adds status: confirmed (finishStop writes admission's comment first),
// close and fail add none; all but retry and wait remove agent-ready.
const ROUTE_OUTCOME = { retry: "retry", wait: "wait", intake: "intake", park: "parked", close: "closed", "host-run": "host-run", attended: "attended", fail: "failed" };
const ROUTE_LABEL = { "host-run": HOST_RUN_LABEL, attended: ATTENDED_LABEL, park: "status: confirmed" };
const KEPT = new Set(["retry", "wait"]);
// The routes whose stops are counted against a cap: past it, retry-spent's.
const COUNTED = new Set([...KEPT, "intake"]);
const ADMISSION_LABELS = ["agent-ready", "status: ready", "admission-deferred"];
const ROUTE_REMOVES = { intake: ADMISSION_LABELS, park: ADMISSION_LABELS };
const ROUTE_TEXT = {
  "host-run": `It added \`${HOST_RUN_LABEL}\` and removed \`agent-ready\`: an agent run on a host builds it, and it waits on no decision from a person.`,
  attended: `It added \`${ATTENDED_LABEL}\` and removed \`agent-ready\`: the step needs the owner present, and it waits on no decision from a person.`,
  intake:
    "It removed `agent-ready` and `status: ready`, so the hourly triage sweep sends it back through intake triage, and it waits on no decision from a person.",
  "intake-security": "It removed `agent-ready` and `status: ready`, so the hourly triage sweep sends it back through intake triage.",
  park: `It removed \`agent-ready\` and \`status: ready\` and added \`status: confirmed\`, as admission parks a refusal no person answers, and it waits on no decision from a person. Once that step is done, a listed human's comment whose first line is \`${DECISION_LINE}\` sends it back through intake triage.`,
  close: "It closes the issue as completed.",
  fail: "It removed `agent-ready` and added no label.",
};
// The pull request a blocked-by-pr reason names: its first `#<n>` (or the
// full-width `＃<n>`) other than the issue itself, or "".
export const waitedPull = (reason, issueNumber) =>
  [...String(reason ?? "").matchAll(/[#＃]([1-9][0-9]{0,9})\b/g)].map((match) => match[1]).find((number) => Number(number) !== issueNumber) ?? "";
// pushbackSecurity's stop line, which leaves the question's kind to intake.
const PUSHBACK_SECURITY_WHY =
  "the run pushed back without naming cause intent, and its words may name a security risk, so intake triage judges the issue again on evidence; if the run names it again once this intake round is spent, the issue reaches a person";
function stopPlan({ route, stop, shown, retries, cap, outcome, issueNumber, branch, runUrl, runId, onResumed = false, pr = "", why = "", neutral = false }) {
  const exit = ROUTE_OUTCOME[route];
  const lines = [
    `<!-- work-resolve-issue outcome=${exit}${neutral ? " security" : ""}${pr ? ` pr=${pr}` : ""}${runId ? ` run=${runId}` : ""}${resumedTag(onResumed)} -->`,
    `${stopLine(stop)} ${neutral ? PUSHBACK_SECURITY_WHY : stopWhy(shown)}.`,
    ...(why ? [why] : []),
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
    lines.push("", `To hand it back to the lane, remove \`${HOST_RUN_LABEL}\` and add \`agent-ready\` again.`);
  } else if (route === "attended") {
    lines.push("", `Once the step is done, a listed human removes \`${ATTENDED_LABEL}\` and adds \`agent-ready\` again.`);
  } else if (route === "fail") {
    lines.push("", "To run it again, add `agent-ready`.");
  }
  return {
    action: route,
    exit,
    stop,
    issueNumber,
    runId,
    comment: lines.join("\n"),
    addLabels: Object.hasOwn(ROUTE_LABEL, route) ? [ROUTE_LABEL[route]] : [],
    removeLabels: KEPT.has(route) ? [] : (ROUTE_REMOVES[route] ?? ["agent-ready"]),
    ...(pr && { pr }),
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
  const plan =
    route === "hold"
      ? handBack({ ...args, reason: stopReasonCode(shown), spentSecurity, word: shown === "security-risk" ? heldWord(args.outcome) : "" })
      : stopPlan({ ...args, outcome: { notDone: [], ...args.outcome }, route, stop, shown, retries, cap, pr, why, neutral: security });
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
  return { action: "hand-back", exit: OUTSIDE_AUTHOR, issueNumber, comment: lines.join("\n"), addLabels: [], removeLabels: ["agent-ready"] };
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
// owner takes present; only a person removes OUTSIDE_ACTOR_LABEL.
export const LANE_HOLDS = new Set(["needs-owner-decision", "status: needs-decision", "status: needs-info", "needs-human", UNTRUSTED_PROVENANCE, ATTENDED_LABEL, OUTSIDE_ACTOR_LABEL]);
const BLOB = /^[0-9a-f]{40}$/;

// A run that stopped on stale workflow files ran no model and is no fault in
// the issue, so it is re-fired at once on main's files, the way work-unblock's
// sweep re-fires it: its re-fire record, then agent-ready removed and added
// back by the App, which starts a fresh run (admission accepts the App's
// agent-ready). Nothing is done when the run's files match main's (the
// stale claim does not hold), the issue is closed, agent-ready is off, was
// last removed, or was last added by neither a listed human nor the App, or a
// hold is on, or a person removes agent-ready before the write lands; and none
// past limits.limit-stops-per-issue re-fire records since a listed human last
// added agent-ready or a run last reported. Past that bound the hourly sweep
// still re-fires a stale stop once per new version of the two lane workflow
// files on main, so the re-fires are bounded by how often main changes them.
// Returns what it did.
export async function refireStale(github, repo, issueNumber, { workflowSha, bot, humans, limits }) {
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
  if (issue?.state !== "open" || !labels.includes("agent-ready")) {
    return "skipped: the issue is closed or agent-ready is off";
  }
  const hold = labels.find((label) => LANE_HOLDS.has(label));
  if (hold) {
    return `skipped: held by ${hold}`;
  }
  const events = (await paginate(github, `${base}/events`)).filter(
    (event) => (event?.event === "labeled" || event?.event === "unlabeled") && String(event.label?.name).toLowerCase() === "agent-ready",
  );
  if (events.at(-1)?.event !== "labeled") {
    return "skipped: agent-ready was last removed";
  }
  // The App's re-add admits on its own, so it repeats only a label admission
  // would take: a listed human's or the App's own (work-unblock's rule).
  if (!trustedLabeler(events, events.at(-1).label.name, { bot, humans })) {
    return "skipped: agent-ready was last added by neither a listed human nor the lanes App";
  }
  const comments = (await paginate(github, `${base}/comments`)).filter((comment) => comment?.user?.login === bot);
  const at = (comment) => Date.parse(comment.created_at);
  const from = Math.max(
    Number.NEGATIVE_INFINITY,
    ...events.filter((event) => event.event === "labeled" && humans.has(event.actor?.id)).map((event) => Date.parse(event.created_at)),
    ...comments.filter((comment) => parseOutcomeMarker(comment.body) !== null).map(at),
  );
  const records = comments.filter((comment) => {
    const record = REFIRED.exec(String(comment.body ?? ""));
    return record !== null && record[2] === undefined && at(comment) > from;
  });
  // A record no App agent-ready add follows is one whose label move did not
  // finish: finish it without posting another (work-unblock's `relabeled`).
  const pending = records.some(
    (comment) => !events.some((event) => event.event === "labeled" && event.actor?.login === bot && Date.parse(event.created_at) >= at(comment)),
  );
  if (!pending && records.length >= limits["limit-stops-per-issue"]) {
    return `skipped: ${records.length} re-fires since a person last added agent-ready or a run last reported (limits.limit-stops-per-issue); work-unblock's sweep takes it`;
  }
  if (!pending) {
    await github("POST", `${base}/comments`, { body: refireComment(key, STALE_CAUSE, "The run's report-outcome") });
  }
  // A 404 is a person's removal since the read: it stands, and the record no
  // App re-add follows ends nothing (work-unblock lists only agent-ready issues).
  try {
    await github("DELETE", `${base}/labels/agent-ready`);
  } catch (error) {
    if (/ answered 404$/.test(error?.message ?? "")) {
      return "skipped: agent-ready was removed before the re-fire";
    }
    throw error;
  }
  // The label is off now; one failed re-add would leave the issue out of the
  // lane, so it is tried twice and then fails the job.
  const add = () => github("POST", `${base}/labels`, { labels: ["agent-ready"] });
  await add().catch(add);
  return `re-fired on workflow files ${key}`;
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
  return { action: "limited", exit: "limited", issueNumber, resets, runId, comment: lines.join("\n"), addLabels: [], removeLabels: [] };
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
  return { action: "funding", exit: "funding", issueNumber, runId, comment: lines.join("\n"), addLabels: [], removeLabels: [] };
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
  return { action: "turn-cap", exit: "turn-cap", issueNumber, runId, comment: lines.join("\n"), addLabels: [], removeLabels: [] };
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
  const record = { tip: parsed.tip, results: results.map(({ check, exit }) => ({ check: check.slice(0, MAX_ITEM), exit })) };
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
// its own leak scan: a trusted `merge: human`, an issue labeled
// untrusted-provenance, an unreadable denied-path list or changed-file list,
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
    issueLabels.includes(UNTRUSTED_PROVENANCE) ||
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
// (unmarkedAnswer).
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
    // A delivered report closes only a read-only issue the run committed
    // nothing for; any other one retries.
    const retry = stop === "report-delivered" && !(issueLabels.includes(READ_ONLY_CLASS) && !branch);
    const why = `The issue is not \`${READ_ONLY_CLASS}\`, or the run committed to a branch, so it retries instead of closing.`;
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
// changed after the label, and issue-file when it wrote no issue file for
// another reason. Either way no model ran.
export const ISSUE_STOPS = {
  "issue-edited":
    "The run did not start: the issue's title or body changed after `agent-ready` was added, so the runner wrote no issue file for the skill and no model ran.",
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

// The turn-cap restarts since a listed human last added agent-ready: the lanes
// App's turn-cap markers after that, other than this run's own. Anyone else's
// label resets nothing, so it cannot buy restarts.
export const countTurnCapRestarts = (args) => countRestarts({ ...args, outcome: "turn-cap" });

// The lanes App's `outcome` markers since a listed human last added
// agent-ready, other than this run's own: turn-cap restarts, or stop retries.
function restartMarkers({ comments, events, bot, humans, runId, outcome }) {
  const since = events
    .filter((event) => event?.event === "labeled" && event.label?.name === "agent-ready" && humans.has(event.actor?.id))
    .reduce((latest, event) => Math.max(latest, Date.parse(event.created_at)), Number.NEGATIVE_INFINITY);
  return comments
    .map((comment) => (comment.user?.login === bot ? { ...parseOutcomeMarker(comment.body), at: Date.parse(comment.created_at) } : null))
    .filter((marker) => marker?.outcome === outcome && marker.run !== runId && marker.at > since);
}
export const countRestarts = (args) => restartMarkers(args).length;

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
      throw new Error(`${method} ${path} answered ${response.status}`);
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
// outputs. Any failed read, or an answer of the wrong shape, fails the step,
// so the mint never follows it.
export async function findPriorMain({ env = process.env, fetch = globalThis.fetch, sleep } = {}) {
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
    const keepBehind = env.FIND_PRIOR_KEEP_BEHIND === "true";
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
    console.log(`::error title=report-outcome::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

// A hand-back, host-run, attended or fail plan's edits. The label first, so a failed
// comment still leaves the issue on its route. A fail plan adds none: its
// comment's marker is the route, so it is posted before agent-ready goes, and
// a failed post leaves agent-ready for work-unblock's stranded sweep. Adding a
// label the issue has, or removing one it lacks (a 404 the catch logs), leaves
// the same labels, so both are resent; the comment is not.
// An empty plan.comment posts none: the comment is already on the issue.
async function applyHandBack(github, repo, plan) {
  const comment = async () => plan.comment && github("POST", `${repo}/issues/${plan.issueNumber}/comments`, { body: plan.comment });
  if (plan.addLabels.length) {
    await github("POST", `${repo}/issues/${plan.issueNumber}/labels`, { labels: plan.addLabels }, { safeToResend: true });
  } else {
    await comment();
  }
  for (const name of plan.removeLabels) {
    await github("DELETE", `${repo}/issues/${plan.issueNumber}/labels/${encodeURIComponent(name)}`, undefined, { safeToResend: true }).catch((error) =>
      console.log(`report-outcome: could not remove ${name}: ${error.message}`),
    );
  }
  if (plan.addLabels.length) {
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
// first counts its own outcome's markers since a listed human last added
// agent-ready: past its cap it takes retry-spent's route (security-risk's hold
// for an intake round that is a pushbackSecurity stop), so an issue intake
// keeps sending back cannot loop. An earlier round's security reading does not
// carry over: intake triage re-judged it before admitting the issue again. A
// retry or wait under the cap posts its comment once per run (a rerun of this
// report finds its own marker) and keeps agent-ready. A close comments,
// removes agent-ready, then closes the issue as completed.
async function finishStop(github, repo, plan, { bot, humans, runId, limits }) {
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
  let history = null;
  const read = async () =>
    (history ??= {
      comments: await paginate(github, `${repo}/issues/${plan.issueNumber}/comments`),
      events: await paginate(github, `${repo}/issues/${plan.issueNumber}/events`),
      bot,
      humans,
      runId,
    });
  if (COUNTED.has(plan.action)) {
    const counted = { ...(await read()), outcome: plan.exit };
    plan = capRetries(plan, countRestarts(counted), limits);
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
  await applyHandBack(github, repo, plan);
  if (plan.action === "close") {
    await github("PATCH", `${repo}/issues/${plan.issueNumber}`, { state: "closed", state_reason: "completed" }, { safeToResend: true });
    console.log(`report-outcome: closed issue #${plan.issueNumber} (${plan.stop})`);
  }
}

export async function main({ env = process.env, fetch = globalThis.fetch, now = Date.now(), sleep } = {}) {
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
        humans: readHumansOrNone(env.TRUSTED_ACTORS),
        limits: readLimits(resolved),
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
      await applyHandBack(github, repo, posted ? { ...plan, comment: "" } : plan);
      return 0;
    }
    if (dimensionSkip) {
      const humanLabel = humanLabelFrom(env.TRACKER_CONFIG ?? ".base/.work-item-tracker.json");
      const resolved = env.RESOLVED_CONFIG || join(env.RUNNER_TEMP ?? "", "resolved-config.json");
      const plan = routeStop(dimensionSkip, { outcome: stopped(""), issueNumber, branch: "", humanLabel, runUrl, runId }, { why: DIMENSION_STEPS[dimensionSkip] });
      await finishStop(github, repo, plan, { bot: env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]", humans: readHumansOrNone(env.TRUSTED_ACTORS), runId, limits: readLimits(resolved) });
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
    // A labeler that cannot be read holds the PR, like an unreadable denied-path list.
    const humanMerge =
      issueLabels.includes(HUMAN_MERGE_LABEL) &&
      (await paginate(github, `${repo}/issues/${issueNumber}/events`)
        .then((events) => trustedLabeler(events, HUMAN_MERGE_LABEL, { bot, humans: readHumans(env.TRUSTED_ACTORS ?? "") }))
        .catch(() => true));
    const listedHumans = () => readHumansOrNone(env.TRUSTED_ACTORS);
    const limits = readLimits(resolvedPath);
    // Only a turn cap with no outcome of the run's own reads the issue's history.
    const capped = !unreported && funding === null && turnCap !== null && outcome?.unread === true;
    const comments = capped ? await paginate(github, `${repo}/issues/${issueNumber}/comments`) : [];
    const turnCapRestarts = capped
      ? countTurnCapRestarts({
          comments,
          events: await paginate(github, `${repo}/issues/${issueNumber}/events`),
          bot,
          humans: listedHumans(),
          runId,
        })
      : 0;
    const humanLabel = humanLabelFrom(env.TRACKER_CONFIG ?? ".base/.work-item-tracker.json");
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
        });
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
            // it is read back first, and created once more only when absent.
            if (!networkError(error)) {
              throw error;
            }
            pull = (await findOpen()) ?? (await github("POST", `${repo}/pulls`, fields));
          }
        }
        // A held PR carries the hold label from its opening; one the label
        // cannot reach is closed rather than left held by body text alone.
        const labeled =
          !plan.hold ||
          (await github("POST", `${repo}/issues/${pull.number}/labels`, { labels: [HUMAN_MERGE_HOLD] }, { safeToResend: true }).then(
            () => true,
            (error) => {
              console.log(`::warning title=report-outcome::could not label PR #${pull.number} ${HUMAN_MERGE_HOLD}: ${String(error?.message ?? error)}`);
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
            : `report-outcome: closed PR #${pull.number}: it holds for a person and could not be labeled ${HUMAN_MERGE_HOLD}`,
        );
        plan = routeStop(moved ? "pr-head-moved" : "hold-label-failed", {
          outcome: stopped(
            moved
              ? `The PR from \`${plan.branch}\` opened at a head other than ${plan.tip}, the tip the runner checked, so it was closed.`
              : `The PR from \`${plan.branch}\` holds for a person, and the \`${HUMAN_MERGE_HOLD}\` label could not be added, so it was closed.`,
          ),
          issueNumber,
          branch: plan.branch,
          humanLabel,
          runUrl,
          runId,
        });
      }
    }
    await finishStop(github, repo, plan, { bot, humans: listedHumans(), runId, limits });
    return 0;
  } catch (error) {
    console.log(`::error title=report-outcome::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = process.argv[2] === "--find-prior" ? await findPriorMain() : await main();
}
