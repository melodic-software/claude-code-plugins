#!/usr/bin/env node
// label-unblocked.mjs: when an issue closes, labels `agent-ready` each issue
// it blocked that is now ready for the resolve-issue lane, which the label
// starts: open, every blocker closed, for any reason, by a listed human or a
// merge in this repository (a pull request blocker: merged here; another
// repository's blocker: closed there by a listed human), no hold label, and
// not already agent-ready. Issues it would label are taken oldest
// opened first (owner Q95). Every fact is read from the API now, never from the event
// payload. No model.
//
// Each new agent-ready is paced: at or over the issue lane's queued cap, or
// with the lane paused over its WIP or held cap (check-wip-cap.mjs, on or
// after wip.pause-from, or whenever a search answers incomplete_results:
// true) a ready issue gets `admission-deferred` instead, and with room for k
// admissions only the first k ready issues are labeled. Every sweep revisits
// the open deferred issues oldest first, before the closed ones: one still
// ready is labeled agent-ready within the room and loses admission-deferred,
// a held one, or one an open pull request in this repository names (intake
// defers those), stays deferred, and any other loses admission-deferred. Restarts, re-fires and relabels below
// re-run admitted issues and are never paced.
//
// A listed human adding admission-deferred to an issue with `status: ready`
// is the mark of a decided issue (owner decision Q75): the sweep reads its
// Size, Complexity and Uncertainty fields (a value counts only when a listed
// human or the App set it, as `status: ready` must be added; no default
// stands in) and runs intake's admission
// rules on it (admit.mjs decide). It is admitted within the room only on an
// admit verdict. A refusal gets admit.mjs's comment, `status: needs-decision`
// for `status: ready`, and loses admission-deferred; a wait on an open pull
// request stays deferred, and one on a blocker loses admission-deferred, so
// its blocker's close admits it. One the rules leave alone loses
// admission-deferred with a comment saying why.
//
// An agent-ready issue left with nothing running is stranded: no hold, no open
// lane pull request or open pull request of a listed human's for it, no
// outcome marker since its newest agent-ready, and no work-resolve-issue run
// for that label, or only one that ended with no report, over STRANDED_HOURS
// ago. It is re-fired with the re-fire record below once per version of the
// lane workflow files, and after that on a backoff (STRANDED_HOURS doubling
// with each re-fire, at most BACKOFF_CAP_HOURS), recorded in one comment
// edited in place; it never gets needs-human. All share
// limits.restarts-per-run.
//
// The lane skips an issue a blocker still blocks and keeps agent-ready on
// (check-blockers.mjs), so the close path above, which leaves an agent-ready
// issue alone, never re-runs it. The sweep does: an agent-ready issue a
// blocker still blocks is never re-fired, stranded or handed to a person, and
// a run the blocker gate skipped is re-fired like a run that did no work once
// none blocks. A run the gate stopped on untrusted provenance, or an issue
// whose untrusted-provenance label someone unlisted removed, is never
// re-fired and gets no needs-human: admission's refusal reaches a person.
//
// On `schedule` it sweeps instead: every issue closed since the last
// successful scheduled run that ran its labeling step began (less
// SWEEP_MARGIN_MIN, at most LOOKBACK_HOURS back; the full window when that
// cannot be shown) goes through the same rules, so an issue a bot closed (a
// pull request merge), which starts no close run, is still picked up. A
// swept close counts only when a listed human or a merge made it. Overlapping
// windows are harmless: an issue already labeled is left alone, and one whose
// label was removed (by a person, or by a lane's pushback) is not labeled
// again until the lanes App or a listed human adds `status: ready` after the
// newest removal (admit.mjs removalStands). A removal by the lanes App that
// follows the App's own limited marker is a restart, not a stop, and does
// not count.
//
// The sweep also restarts issues the usage limit stopped: an open agent-ready
// issue whose newest lanes-App outcome marker is `limited`, past its reset,
// with no agent-ready label added since (so no lane run started after the
// stop), and no hold label gets agent-ready removed and
// added again by the App, which starts the lane. An issue whose newest marker
// is `turn-cap` (report-outcome kept agent-ready, so a restart is left) is
// restarted the same way at once, while its turn-cap markers since a person
// last added agent-ready are within limits.turn-cap-restarts. At most
// limits.restarts-per-run issues per run, longest-waiting first.
//
// It re-fires the same way an open agent-ready issue whose newest
// work-resolve-issue run (the one its newest agent-ready label started, by a
// listed human or the App) did no work and left no lanes-App outcome marker since: a
// crash before the report, a rerun the token broker refused as
// workflow-modified, a run cancelled after admit passed and before any
// resolve-issue job started (pick-slot's timeout, a slot queue past GitHub's limit),
// or a run that ended green at the read runner's `Stop on stale workflow files`
// step (it waited in its slot past a lane workflow change, so no model ran).
// A run a newer agent-ready run replaced while it waited is never re-fired:
// admit never ran in it. A rerun keeps its first event's workflow files, so only a
// fresh label event runs on main's. Each issue is re-fired once per version
// of the two lane workflow files on main with a marker comment posted before
// the label moves, and after that on the stranded backoff, so a run that
// keeps failing is retried less often but never handed to a person.
//
// A run that minted no lane token did no work and ran no model: the WIP cap
// skipped its resolve-issue job, or its `Request the lane token` step failed
// (GitHub's rate limit past the retry budget among the reasons). Such a run is
// re-fired with the same record: a failed mint up to limits.limit-stops-per-issue
// times per version of the lane workflow files and then on the stranded
// backoff, a WIP cap skip without a per-issue bound. It waits limits.reset-clamp-min hours after the run ended, past any reset
// the broker passes on (its Retry-After is at most an hour), and only while
// the issue lane's WIP cap check (check-wip-cap.mjs) does not pause it. It is no
// limit stop, so it never counts toward handing the issue to a person.
//
// A run the token broker refused for the lanes kill switch, at broker-check's
// `Ask the broker whether the lane may run` or at a `Request the lane token`
// step, is a breaker trip, not a fault in the issue or the lanes; only the
// refused job's log names the reason (the jobs listing reads the same for a
// workflow-modified refusal). So is a run whose broker-check `Check the kill
// switch` step saw a kill switch on and skipped the broker ask: that run ends
// green, and the jobs listing alone shows it. It is re-fired limits.reset-clamp-min hours after
// the run ended with a breaker record of its own, and after
// limits.limit-stops-per-issue trips since a listed human last added
// agent-ready or a run last reported, on the stranded backoff. A breaker
// record never spends the once-per-version re-fire, never counts toward the
// failed-mint bound and never raises another cause's backoff. Each run's log
// is read once, from its one refused job and at most LOG_CAP_BYTES, and only
// its failed step's last line counts: a refusal for another reason, or a log
// that cannot be read, keeps the class it had before.
//
// When that label's run opened a pull request instead, the newest one the
// lanes App opened from the issue's lane branch in this repository decides.
// Merged with `Refs:` (the issue stays open with nothing to run) or closed
// unmerged, the App removes `status: ready` and agent-ready, so the triage
// sweep (maintenance-audit-lane-runs triage-sweep.mjs) dispatches intake,
// which decides what is left and whose fresh `status: ready` re-admits it. Open, it waits: report-outcome put needs-human on the
// issue of a Refs PR, and this lifts that hold once that PR merges or closes
// unmerged, only while its refs-hold marker and the App's needs-human label
// are the newest. Each hand-off also counts against limits.restarts-per-run.
//
// It relabels a red-main fix issue post-merge-demotion-alert.yml reopened on
// a repeat failure: the reopen keeps agent-ready but ran on that workflow's
// GITHUB_TOKEN, which starts no run. An open agent-ready issue filed by
// github-actions[bot] with a `<!-- post-merge-fix check=... -->` first line
// and a newest github-actions[bot] recurrence comment, with no agent-ready
// added since that comment, its newest agent-ready added by a listed human
// or the App, no hold, no open lane PR and no lane run in
// flight, gets a record naming that comment and agent-ready removed and added
// by the App. Relabels share limits.restarts-per-run, and the count is logged
// before any of them.
//
// When a sub-issue of a size split (intake's refine.mjs, owner Q93) closes,
// by a listed human or, on the sweep, a merge, and every sub-issue of its
// open parent is closed that way, the App comments on the parent and closes
// it as completed. Only a split parent counts (admit.mjs isSplitParent): one
// whose split record the App posted, or one split by hand whose every
// sub-issue the App or a listed human linked, not `recurring`, with no open
// task-list item in its body.
//
// Environment:
//   GH_TOKEN              the lane App token (issues: write)
//   GITHUB_REPOSITORY      owner/repo
//   GITHUB_EVENT_NAME      `issues` (a close) or `schedule` (the sweep)
//   GITHUB_EVENT_PATH      the event payload; on `issues` only its action,
//                          issue number and sender are read; on `schedule`
//                          it is not read
//   KILL_SWITCH            `proceed` from the kill-switch step; anything else stops
//   TRUSTED_ACTORS_PATH    trusted-actors.json from the default branch tip
//   ACTOR_ID               who closed the issue; must be a listed human
//                          (`issues` only)
//   ACTIONS_TOKEN          the job's GITHUB_TOKEN (actions: read), to read
//                          this run's record (`issues`), list
//                          work-resolve-issue runs, read a refused job's log,
//                          and find the last sweep and its jobs; on
//                          `schedule`, unset skips the re-fire and uses the
//                          full window
//   GITHUB_RUN_ID          this run, read for who started this attempt (a
//                          re-runner may differ; it must be a listed human,
//                          `issues` only) and skipped when reading the last
//                          sweep
//   GITHUB_RUN_ATTEMPT     this run's attempt, checked against its record
//   LANES_BOT_LOGIN        the lanes App bot login, the only author of a marker
//                          and actor of a restart this trusts (default
//                          melodic-automation-lanes[bot])
//   GITHUB_API_URL
//   RESOLVED_CONFIG        resolve-config's output (default
//                          $RUNNER_TEMP/resolved-config.json), for the limits
//   BASE_PATH              the default branch checkout (default .base), for
//                          the admission rules and models.issue-dimensions
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, isTrustedClose as closedByHumanOrMerge, loadTrustedList, paginate, readRerunner } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { admissionLine, checkWip, searchRateLimit } from "../../actions/check-wip-cap/check-wip-cap.mjs";
import { clampReset, isLaneBranch, parseOutcomeMarker, refsHoldMarker } from "../work-resolve-issue/report-outcome.mjs";
import { readLimits, readWip } from "../work-resolve-issue/limits.mjs";
import { admissionFacts, blockersOf, decide, loadRules, NEEDS_DECISION, openPullsFor, READY, refusalText, removalStands, sayWhy, stillBlocking, UNTRUSTED, untrustedHold } from "../intake-triage/admit.mjs";
import { isSplitParent, splitParentClosed } from "../intake-triage/admit.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { createJobLogReader } from "./job-log.mjs";

const LABEL = "agent-ready";
const HUMAN_LABEL = "needs-human";
const DEFERRED_LABEL = "admission-deferred";
// The lane's caller and the write runner: the broker refuses a run whose copy
// of either differs from main's.
const LANE_WORKFLOWS = [".github/workflows/pr-run-activity-write.yml", ".github/workflows/work-resolve-issue.yml"];
const FAILED = new Set(["failure", "timed_out", "startup_failure"]);
// A label event's run is created within seconds; this window finds it.
const RUN_WINDOW_MS = 10 * 60_000;
const BLOB = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,14}$/;
const HOUR_MS = 3_600_000;
// The write runner's step that mints the lane token, which every model run follows.
const MINT_STEP = "Request the lane token";
// The read runner's step a run stops at, green, when its lane workflow files
// differ from main's: no model ran and no outcome marker follows.
const STALE_STEP = "Stop on stale workflow files";
// The admit job's step that skips a run while the issue has an open blocker,
// or its blockers cannot be read (check-blockers.mjs); pick-slot then skips.
const BLOCKER_STEP = "Wait for open blockers";
// The admit job's step a run stops at for good on untrusted provenance.
const UNTRUSTED_STEP = "Stop on untrusted provenance";
// broker-check's step, which asks the broker before any resolve-issue run job.
const BROKER_STEP = "Ask the broker whether the lane may run";
// broker-check's step before BROKER_STEP, which skips it while a kill switch is on.
const KILL_STEP = "Check the kill switch";
// request-lane-token's last line when the broker refuses it, in check mode
// (BROKER_STEP) or token mode (MINT_STEP), and the runner's line that follows
// it when the step fails. Only the reason word is read.
const DENIAL = {
  check: /^\d{4}-\d\d-\d\dT[\d:.]+Z ##\[error\]lane-check-denied: the broker answered 403 with reason ([a-z]+(?:-[a-z]+)*)(?::|$)/,
  token: /^\d{4}-\d\d-\d\dT[\d:.]+Z ##\[error\]lane-token-denied: the broker answered 403 with reason ([a-z]+(?:-[a-z]+)*)(?::|$)/,
};
const STEP_FAILED = /^\d{4}-\d\d-\d\dT[\d:.]+Z ##\[error\]Process completed with exit code [0-9]+\.$/;
const BREAKER = "kill-switch";
// The refused jobs' logs on 2026-10-24 were 45 KB (broker-check) and 94 KB
// (apply-issue-patch); a longer one is left unread.
const LOG_CAP_BYTES = 1_048_576;
// work-unblock.yml's job and its step that runs this script. The kill switch
// and a lane the config turns off skip the step and leave the run green, so
// only this step's success shows a sweep ran.
const SWEEP_JOB = "label-unblocked";
const SWEEP_STEP = "Label the unblocked issues";
const REFIRED = /^<!-- work-unblock refired ([0-9a-f]{40}-[0-9a-f]{40})( breaker)? -->/;
const handedMarker = (pr) => `<!-- work-unblock handed triage #${pr} -->`;
const DEFAULT_BOT = "melodic-automation-lanes[bot]";
// A person decides these; the lane never starts on them.
const HOLDS = new Set(["needs-owner-decision", "status: needs-decision", "status: needs-info", "needs-human", "work-class: untrusted-provenance"]);
const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
// post-merge-demotion-alert.yml's fix issue and the comment it posts when it
// reopens one, both under that workflow's GITHUB_TOKEN.
const ALERT_BOT = "github-actions[bot]";
const FIX_ISSUE = /^<!-- post-merge-fix check=[^\r\n]+ -->/;
export const RECURRENCE_PREFIX = "This check failed on main again at `";
const RELABELED = /^<!-- work-unblock recurrence ([1-9][0-9]{0,15}) -->/;
// A work-resolve-issue run in any of these has not finished.
const IN_FLIGHT = ["queued", "in_progress", "waiting", "pending", "requested"];
// The sweep's widest window, used when the last good sweep is unknown or
// older: a missed run loses nothing up to this far back.
export const LOOKBACK_HOURS = 3;
// The sweep reads from this long before the last good sweep started.
export const SWEEP_MARGIN_MIN = 15;
// How long an agent-ready issue may sit with no run working on it.
export const STRANDED_HOURS = 3;
// The one comment per issue that says it keeps being re-fired on a backoff,
// edited in place on each re-fire; it reads as a re-fire record timed by its
// last edit.
const INFRA = /^<!-- work-unblock infrastructure ([0-9a-f]{40}-[0-9a-f]{40}) -->/;
// The longest wait between backoff re-fires.
export const BACKOFF_CAP_HOURS = 24;
const backoffDue = (since, refires) => since + Math.min(STRANDED_HOURS * 2 ** refires, BACKOFF_CAP_HOURS) * HOUR_MS;
// The REST version that documents issue-field-values.
const FIELD_API = { "X-GitHub-Api-Version": "2026-03-10" };
const DIMENSIONS = ["size", "complexity", "uncertainty"];

// Whether the account that closed the issue (ACTOR_ID) and the one that
// started this run attempt (a re-runner may be another account) are each a
// listed human, by id. The re-runner's id is read from this run's own record
// with `actions` (default: the job token), since a login can pass to another
// account; a failed or malformed read answers false. The broker mints only
// when this holds.
export async function checkCloser(env, actions) {
  if (!NUMBER.test(env.ACTOR_ID ?? "")) {
    return false;
  }
  const { humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
  if (!humans.has(Number(env.ACTOR_ID))) {
    return false;
  }
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    return humans.has(await readRerunner(actions, env.GITHUB_REPOSITORY, String(env.GITHUB_RUN_ID ?? ""), String(env.GITHUB_RUN_ATTEMPT ?? "")));
  } catch (error) {
    console.log(`::warning title=label-unblocked::this run's record names no re-runner it could read (${escapeCommand(error?.message ?? error)}); treated as unlisted`);
    return false;
  }
}

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const reportError = (number, error) =>
  console.log(`::error title=label-unblocked::#${number}: ${escapeCommand(error?.message ?? error)}`);

const isLabel = (event, kind) => event.event === kind && String(event.label?.name).toLowerCase() === LABEL;

// A re-fire marker reads as outcome `refired` with its workflow key, and
// `breaker` when a kill-switch refusal caused it.
const parseMarker = (body) => {
  const refire = REFIRED.exec(String(body ?? "")) ?? INFRA.exec(String(body ?? ""));
  return refire ? { outcome: "refired", key: refire[1], breaker: refire[2] !== undefined } : parseOutcomeMarker(body);
};

// The lanes App's outcome and re-fire markers on an issue, oldest first, each
// with when it was posted (the backoff comment: last edited).
const appMarkers = (comments, bot) =>
  comments
    .filter((comment) => comment.user?.login === bot)
    .map((comment) => ({
      ...parseMarker(comment.body),
      at: Date.parse(INFRA.test(String(comment.body ?? "")) ? (comment.updated_at ?? comment.created_at) : comment.created_at),
    }))
    .filter((marker) => marker.outcome !== undefined && Number.isFinite(marker.at))
    .sort((a, b) => a.at - b.at);

// The App's markers after which its removal of agent-ready is a restart.
const RESTARTS = new Set(["limited", "refired", "turn-cap", "funding"]);

// A removal of agent-ready is a restart, not a stop, only when the App made
// it, the App's newest marker before it is `limited`, `turn-cap` or a re-fire, and the next agent-ready
// event after it is the App adding the label back. Any other removal stops the
// lane, a pushback after a restart included.
function isRestart(events, index, markers, bot) {
  const removal = events[index];
  const at = Date.parse(removal.created_at);
  const newest = markers.filter((marker) => marker.at <= at).at(-1)?.outcome;
  if (removal.actor?.login !== bot || !RESTARTS.has(newest)) {
    return false;
  }
  const next = events.slice(index + 1).find((event) => isLabel(event, "labeled") || isLabel(event, "unlabeled"));
  return next !== undefined && isLabel(next, "labeled") && next.actor?.login === bot;
}

// Whether a label event's actor is the lanes App (by its login) or a listed
// human (by id): the labelers whose labels the lane acts on.
const trustedLabeler = (event, { bot, humans }) => event?.actor?.login === bot || humans.has(event?.actor?.id);

// The newest `labeled` event for label `name` among an issue's events.
const newestAdd = (events, name) =>
  events.filter((event) => event.event === "labeled" && String(event.label?.name).toLowerCase() === name.toLowerCase()).at(-1);

// Why `number` is not promoted (`reason`, null when it is ready), whether a
// hold label is the reason, and whether it carries admission-deferred.
async function refusal(args) {
  const base = `/repos/${args.repo}/issues/${args.number}`;
  const current = await args.github("GET", base);
  const lower = (current.labels ?? []).map((label) => String(typeof label === "string" ? label : label.name).toLowerCase());
  const held = lower.find((label) => HOLDS.has(label));
  const reason = current.state !== "open" ? "not open" : held ? `held by ${held}` : await readiness({ ...args, base, lower });
  return { reason, held: current.state === "open" && Boolean(held), deferred: lower.includes(DEFERRED_LABEL), current };
}

async function readiness({ github, repo, humans, closes, bot = DEFAULT_BOT, base, lower }) {
  if (lower.includes(LABEL)) {
    return `already ${LABEL}`;
  }
  // admit.mjs blockerDone: a blocker counts once closed, for any reason, by a
  // listed human or a merge in this repository; a pull request counts only
  // once merged here. Anyone can close their own issue, so a blocking issue
  // needs a trusted close (trustedClose), read fresh from the issue in its own
  // repository. Another repository's blocker counts only by a listed human's
  // close there, and a read that fails there leaves it blocking: people the
  // trusted list does not cover merge in other repositories.
  const pending = await stillBlocking(
    await blockersOf(github, base),
    repo,
    (number) => trustedClose({ github, repo, number, humans, closes, bot }),
    closedElsewhere({ github, repo, humans, closes }),
  );
  if (pending.length > 0) {
    return `${pending.length} blocker(s) not closed by a listed human or a merge`;
  }
  // Removing the label by hand stops the lane until a person adds it back,
  // or the App or a listed human marks the issue `status: ready` again.
  const comments = await paginate(github, `${base}/comments`);
  const markers = appMarkers(comments, bot);
  const events = await paginate(github, `${base}/events`);
  const stopped = (event, index) => isLabel(event, "unlabeled") && !isRestart(events, index, markers, bot);
  if (removalStands(events, stopped, (event) => trustedLabeler(event, { bot, humans }))) {
    return `${LABEL} was removed and ${READY} not added since`;
  }
  return null;
}

// Where the sweep's window starts and why: SWEEP_MARGIN_MIN before the last
// successful scheduled run of this workflow (not the current one), no further
// back than LOOKBACK_HOURS, and only when that run's SWEEP_STEP succeeded.
// Anything else (an unreadable listing, no steps, a skipped step) gives the
// full window, so a failed read re-processes and never skips.
async function sweepSince({ actions, repo, now, runId }) {
  const widest = now - LOOKBACK_HOURS * HOUR_MS;
  if (!actions) {
    return { since: widest, why: "no Actions token to read the last sweep" };
  }
  try {
    const path = `/repos/${repo}/actions/workflows/work-unblock.yml/runs?event=schedule&status=success&per_page=2`;
    const runs = (await actions("GET", path))?.workflow_runs;
    if (!Array.isArray(runs)) {
      throw new Error("the workflow run listing has an unexpected shape");
    }
    const last = runs.find((run) => String(run.id) !== String(runId ?? ""));
    const started = Date.parse(last?.run_started_at ?? last?.created_at);
    if (!Number.isFinite(started) || started > now) {
      return { since: widest, why: "no earlier successful sweep was found" };
    }
    const at = new Date(started).toISOString();
    const from = started - SWEEP_MARGIN_MIN * 60_000;
    if (from <= widest) {
      return { since: widest, why: `the last successful run started ${at}, past the widest window` };
    }
    if (!RUN_ID.test(String(last.id))) {
      throw new Error("the last successful run has no usable id");
    }
    const jobs = await jobLister(actions, repo)(last);
    const swept = namedJobs(jobs, SWEEP_JOB).some((job) =>
      (job?.steps ?? []).some((step) => step?.name === SWEEP_STEP && step.conclusion === "success"),
    );
    return swept
      ? { since: from, why: `the last sweep started ${at}` }
      : { since: widest, why: `the last successful run, started ${at}, shows no completed \`${SWEEP_STEP}\` step` };
  } catch (error) {
    return { since: widest, why: `the last sweep could not be read (${escapeCommand(error?.message ?? error)})` };
  }
}

// The issues closed at or after `since`. The listing's `since` filters on the
// last update, so the close time is checked here; pull requests, which the
// listing also returns, are left out.
async function closedSince(github, repo, since) {
  const path = `/repos/${repo}/issues?state=closed&since=${encodeURIComponent(since.toISOString())}&sort=updated&direction=desc`;
  return (await paginate(github, path))
    .filter((item) => !item.pull_request && NUMBER.test(String(item.number)) && Date.parse(item.closed_at) >= since.getTime())
    .map((item) => Number(item.number));
}

// One answer per issue per run: a swept close is also its dependents'
// blocker, and a blocker can block several dependents. `where` is the
// blocker's repository: outside `repo`, only a listed human's close counts.
function trustedClose({ github, repo, where = repo, number, humans, closes, bot = DEFAULT_BOT }) {
  const key = `${where.toLowerCase()}#${number}`;
  if (!closes.has(key)) {
    closes.set(
      key,
      (async () => {
        const closed = await github("GET", `/repos/${where}/issues/${number}`);
        return where.toLowerCase() === repo.toLowerCase() ? isTrustedClose(github, repo, closed, humans, bot) : humans.has(closed?.closed_by?.id);
      })(),
    );
  }
  return closes.get(key);
}

// stillBlocking's reader for another repository's blocker: trustedClose
// there, and a read that fails leaves it blocking.
const closedElsewhere = (args) => (blocker) => {
  const where = /\/repos\/([\w.-]+\/[\w.-]+)$/.exec(String(blocker.repository_url ?? ""))?.[1];
  return where ? trustedClose({ ...args, where, number: Number(blocker.number) }).catch(() => false) : false;
};


// The admission pace for one run: `take()` answers whether one more issue may
// get agent-ready now, reading the issue lane's status the first time it is
// asked and counting each admission against its room. A lane paused over its
// WIP or held cap admits nothing, as intake's admission does.
function admissionGate(status) {
  let room;
  let reason;
  let pause;
  return {
    // Why take() last answered false.
    why: () =>
      pause
        ? `the issue lane is paused (${pause})`
        : reason === "search-incomplete"
          ? "GitHub search answered incomplete results"
          : "queued work is at the queued cap",
    take: async () => {
      if (room === undefined) {
        const s = await status();
        pause = s.paused ? s.pause_reason : null;
        room = pause ? 0 : (s.admission_room ?? Number.POSITIVE_INFINITY);
        reason = s.admission_reason;
        if (!s.admission_open) {
          console.log(`::notice title=admission paused::${escapeCommand(admissionLine(s))}`);
        }
      }
      if (room <= 0) {
        return false;
      }
      room -= 1;
      return true;
    },
  };
}

// Adds agent-ready to a ready issue within the gate's room, else defers it.
async function admit({ github, repo, number, gate, deferred }) {
  const base = `/repos/${repo}/issues/${number}`;
  if (!(await gate.take())) {
    if (!deferred) {
      await github("POST", `${base}/labels`, { labels: [DEFERRED_LABEL] });
    }
    console.log(`label-unblocked: #${number} admission deferred: ${gate.why()}`);
    return;
  }
  await github("POST", `${base}/labels`, { labels: [LABEL] });
  if (deferred) {
    await github("DELETE", `${base}/labels/${DEFERRED_LABEL}`);
  }
  console.log(`label-unblocked: #${number} labeled ${LABEL}`);
}

// Revisits the open admission-deferred issues, oldest first. Returns how many
// reads or writes failed.
async function admitDeferred({ github, repo, humans, bot, gate, appId, admission }) {
  let waiting;
  try {
    waiting = (await paginate(github, `/repos/${repo}/issues?state=open&labels=${DEFERRED_LABEL}&sort=created&direction=asc`)).filter(
      (item) => !item.pull_request && NUMBER.test(String(item.number)),
    );
  } catch (error) {
    reportError("deferred", error);
    return 1;
  }
  const closes = new Map();
  let failed = 0;
  for (const item of waiting) {
    const number = Number(item.number);
    try {
      // Anyone who can label could add admission-deferred, and re-admitting
      // it adds the App's agent-ready, which starts a credentialed run: only
      // the App's or a listed human's newest add of it counts.
      const events = await paginate(github, `/repos/${repo}/issues/${number}/events`);
      const mark = newestAdd(events, DEFERRED_LABEL);
      if (!trustedLabeler(mark, { bot, humans })) {
        console.log(`::warning title=label-unblocked::#${number}: ${DEFERRED_LABEL} was added by neither the lanes App nor a listed human, so it is left as is and not re-admitted`);
        continue;
      }
      const { reason, held, deferred, current } = await refusal({ github, repo, number, humans, closes, bot });
      if (humans.has(mark.actor?.id) && labelNames(current).includes(READY) && !held && current.state === "open") {
        await admitMarked({ github, repo, number, issue: current, events, humans, bot, appId, closes, gate, admission });
        continue;
      }
      // Intake defers an issue an open pull request is for; it waits here
      // until no such pull request is open.
      const pulls = reason === null ? await openPullsFor(github, repo, number) : [];
      if (pulls.length > 0) {
        console.log(`label-unblocked: #${number} stays deferred: open pull request #${pulls[0]} is for it`);
      } else if (reason === null) {
        await admit({ github, repo, number, gate, deferred });
      } else if (held) {
        console.log(`label-unblocked: #${number} stays deferred: ${reason}`);
      } else {
        await github("DELETE", `/repos/${repo}/issues/${number}/labels/${DEFERRED_LABEL}`);
        console.log(`label-unblocked: #${number} deferral dropped: ${reason}`);
      }
    } catch (error) {
      failed += 1;
      reportError(number, error);
    }
  }
  return failed;
}

const labelNames = (issue) => (issue?.labels ?? []).map((label) => String(typeof label === "string" ? label : label?.name));

// The verdict intake's admission reads, from the issue itself: each of Size,
// Complexity and Uncertainty as the config's key for the option a listed
// human or the App set, else `unset`. The work class gates nothing (owner
// Q85, #9668); decide reads the untrusted-provenance hold from the labels.
// The work lanes' reader (resolve-config dimensions.mjs) reads an unset field
// as a default; admission never does. A read of an unexpected shape throws.
async function issueVerdict({ github, repo, number, humans, appId, dimensionsConfig, fieldSetters }) {
  const rows = await github("GET", `/repos/${repo}/issues/${number}/issue-field-values`, undefined, FIELD_API);
  if (!Array.isArray(rows)) {
    throw new Error("the issue's field values have an unexpected shape");
  }
  const setters = await fieldSetters(github, repo, number);
  const dimensions = {};
  for (const name of DIMENSIONS) {
    const { "field-id": fieldId, options } = dimensionsConfig.fields[name];
    const row = rows.find((item) => item?.issue_field_id === fieldId);
    const setter = setters[String(fieldId)];
    const option = String(row?.single_select_option?.id);
    const counts = row !== undefined && (humans.has(setter) || (appId !== undefined && setter === appId));
    dimensions[name] = counts && Object.hasOwn(options, option) ? options[option] : "unset";
  }
  return { workClass: null, dimensions };
}

export const skipText = (reason) => `Left out of admission: ${reason}, so work-unblock removed \`${DEFERRED_LABEL}\`.`;

// Runs intake's admission rules on an issue a listed human marked, and admits
// it within the gate's room only on an admit verdict. `status: ready` counts
// only when its newest add, in `events`, is a listed human's or the App's, as
// the mark's own add must be.
async function admitMarked({ github, repo, number, issue, events, humans, bot, appId, closes, gate, admission }) {
  const base = `/repos/${repo}/issues/${number}`;
  const trusted = (name) => trustedLabeler(newestAdd(events, name), { bot, humans });
  const { rules, dimensionsConfig, webHosts, fieldSetters } = await admission();
  const verdict = await issueVerdict({ github, repo, number, humans, appId, dimensionsConfig, fieldSetters });
  const facts = await admissionFacts({
    github,
    repository: repo,
    number,
    issue,
    rules,
    humans,
    appId,
    isTrusted: (blocker) => trustedClose({ github, repo, number: blocker, humans, closes, bot }),
  });
  const decision = trusted(READY)
    ? decide({ ...facts, verdict, rules, humans, appId, repository: repo, webHosts })
    : { verdict: "skip", reasons: [`${READY} was added by neither a listed human nor the lanes App`] };
  const reasons = decision.reasons.join("; ");
  if (decision.verdict === "admit") {
    console.log(`label-unblocked: #${number}, marked by a person, passes the admission rules`);
    await admit({ github, repo, number, gate, deferred: true });
  } else if (decision.verdict === "refuse") {
    // The comment first, then the needs-decision hold before status: ready
    // comes off, and admission-deferred last: a failed write leaves the issue
    // either still marked, for the next sweep, or held, which no sweep admits.
    await sayWhy(github, repo, base, facts.comments, refusalText(reasons));
    await github("POST", `${base}/labels`, { labels: [NEEDS_DECISION] });
    await github("DELETE", `${base}/labels/${encodeURIComponent(READY)}`);
    await github("DELETE", `${base}/labels/${DEFERRED_LABEL}`);
    console.log(`label-unblocked: #${number}, marked by a person, refused: ${reasons}`);
  } else if (decision.verdict === "wait") {
    await sayWhy(github, repo, base, facts.comments, `Not admitted to the issue lane yet: ${reasons}.`);
    if (decision.pulls.length === 0) {
      await github("DELETE", `${base}/labels/${DEFERRED_LABEL}`);
    }
    console.log(`label-unblocked: #${number}, marked by a person, waits: ${reasons}`);
  } else {
    // A skip drops the person's mark, so the comment tells them why.
    await sayWhy(github, repo, base, facts.comments, skipText(reasons));
    await github("DELETE", `${base}/labels/${DEFERRED_LABEL}`);
    console.log(`label-unblocked: #${number} deferral dropped: ${reasons}`);
  }
}

// Labels each issue `closed` blocked that is ready, each at most once per run,
// within the gate's room, oldest opened first (owner Q95). Returns how many
// reads or writes failed.
async function labelUnblocked({ github, repo, closed, sweep, humans, bot, gate }) {
  const seen = new Map();
  const closes = new Map();
  let failed = 0;
  for (const source of closed) {
    let blocked;
    try {
      if (sweep && !(await trustedClose({ github, repo, number: source, humans, closes, bot }))) {
        console.log(`label-unblocked: #${source} was closed by neither a listed human nor a merge; skipped`);
        continue;
      }
      blocked = await paginate(github, `/repos/${repo}/issues/${source}/dependencies/blocking`);
    } catch (error) {
      failed += 1;
      reportError(source, error);
      continue;
    }
    for (const item of blocked) {
      const number = Number(item.number);
      // A label write here can land only in this repository.
      if (!String(item.repository_url ?? "").toLowerCase().endsWith(`/repos/${repo}`.toLowerCase()) || item.pull_request) {
        console.log(`label-unblocked: skipped a blocked item outside this repository's issues`);
        continue;
      }
      if (!seen.has(number)) {
        seen.set(number, Date.parse(item.created_at));
      }
    }
  }
  // An unreadable open time sorts last.
  const opened = (number) => (Number.isFinite(seen.get(number)) ? seen.get(number) : Number.POSITIVE_INFINITY);
  for (const number of [...seen.keys()].sort((a, b) => opened(a) - opened(b) || a - b)) {
    try {
      const { reason, deferred } = await refusal({ github, repo, number, humans, closes, bot });
      if (reason !== null) {
        console.log(`label-unblocked: #${number} not labeled: ${reason}`);
        continue;
      }
      await admit({ github, repo, number, gate, deferred });
    } catch (error) {
      failed += 1;
      reportError(number, error);
    }
  }
  return failed;
}

// The hand-off to a person after limits.limit-stops-per-issue limit stops. Its marker lets
// a later sweep see the comment was posted.
const ESCALATED = "<!-- work-unblock escalated -->";
export const escalationComment = (stops) =>
  `${ESCALATED}\nThe usage limit stopped the work-resolve-issue lane on this issue ${stops} times since a person last added \`${LABEL}\`, so work-unblock no longer restarts it. To try again, remove \`${HUMAN_LABEL}\`, then remove \`${LABEL}\` and add it back: adding it starts a new run and starts the count again. Removing \`${LABEL}\` by hand also means work-unblock never adds it to this issue again when its blockers close; from then on a person adds it.`;

// The re-fire's record, posted before the label moves: one per issue per
// version of the lane workflow files.
const FAILED_CAUSE = `The work-resolve-issue run that \`${LABEL}\` started failed or was cancelled before it reported, or it stopped or the token broker refused it because its workflow files differ from main's.`;
export const refireComment = (key, cause = FAILED_CAUSE) =>
  `<!-- work-unblock refired ${key} -->\n${cause} work-unblock removed and added \`${LABEL}\` back to start a fresh run on main's workflow files. If this run ends the same way, it re-fires the issue again, waiting longer each time.`;

// Why a stranded issue has nothing running, as the comments say it.
const strandedCause = {
  "no-run": `No work-resolve-issue run started in the ${STRANDED_HOURS} hours since \`${LABEL}\` was last added.`,
  "no-report": `The work-resolve-issue run that \`${LABEL}\` started ended over ${STRANDED_HOURS} hours ago with no report and no pull request.`,
  "failed-again": `The work-resolve-issue run that \`${LABEL}\` started failed or was cancelled before it reported, over ${STRANDED_HOURS} hours ago.`,
};

const MINT_CAUSE = `The work-resolve-issue run that \`${LABEL}\` started could not get its lane token.`;

// The record of a re-fire after a kill-switch refusal, posted before the
// label moves, once per re-fire.
export const breakerComment = (key) =>
  `<!-- work-unblock refired ${key} breaker -->\nThe token broker refused the work-resolve-issue run that \`${LABEL}\` started because the lanes kill switch was on, so it did no work. work-unblock removed and added \`${LABEL}\` back to start a fresh run. A kill-switch refusal is no fault in this issue or the lanes, so it never counts against later re-fires; after limits.limit-stops-per-issue of them since a person last added \`${LABEL}\` or a run last reported, work-unblock waits longer before each one, up to ${BACKOFF_CAP_HOURS} hours.`;

// The backoff record of an issue whose re-fires on these workflow files keep
// ending the same way: one comment per issue, edited on each re-fire.
export const infraComment = (key, cause, refires) =>
  `<!-- work-unblock infrastructure ${key} -->\n${cause} work-unblock has re-fired it ${refires} time(s) on lane workflow files ${key} and keeps re-firing it, waiting longer each time, up to ${BACKOFF_CAP_HOURS} hours, until a run reports. This is a fault in the lanes, not in the issue; this comment is updated on each re-fire.`;

// The relabel's record, posted before the label moves: one per recurrence
// comment.
export const recurrenceComment = (id) =>
  `<!-- work-unblock recurrence ${id} -->\nThis check failed on main again, and post-merge-demotion-alert reopened this issue, which starts no work-resolve-issue run. work-unblock removed and added \`${LABEL}\` back to start one. It does this once per reopen.`;

// The hand-offs to triage once the lane PR ended, each posted once per pull
// request before its labels move.
export const refsMergedComment = (pr) =>
  `${handedMarker(pr)}\nThe lanes App's pull request #${pr} merged with \`Refs:\`, so this issue stays open and nothing starts the lane on it again. work-unblock removed \`${READY}\` and \`${LABEL}\`, so the hourly triage sweep sends it back to intake triage, which decides what work is left and admits it again.`;
export const refsClosedComment = (pr) =>
  `${handedMarker(pr)}\nThe lanes App's pull request #${pr} for this issue was closed without merging. work-unblock removed \`${READY}\` and \`${LABEL}\`, so the hourly triage sweep sends it back to intake triage, which decides what work is left and admits it again.`;

// The work-resolve-issue runs for issue `number` created within RUN_WINDOW_MS
// of the label event at `addedAt`, as `mine`. The run title ends with
// ` #<number>`; `untitled` counts the runs in the window whose title names no
// issue (titles from before that run name), which may include this issue's.
async function laneRuns(actions, repo, number, addedAt) {
  const iso = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
  const created = encodeURIComponent(`${iso(addedAt)}..${iso(addedAt + RUN_WINDOW_MS)}`);
  const path = `/repos/${repo}/actions/workflows/work-resolve-issue.yml/runs?event=issues&created=${created}`;
  const runs = [];
  for (let page = 1; page <= 10; page += 1) {
    const batch = (await actions("GET", `${path}&per_page=100&page=${page}`))?.workflow_runs;
    if (!Array.isArray(batch)) {
      throw new Error("the workflow run listing has an unexpected shape");
    }
    runs.push(...batch);
    if (batch.length < 100) {
      const title = (run) => String(run.display_title ?? "");
      return {
        mine: runs.filter((run) => title(run).endsWith(` #${number}`)),
        untitled: runs.filter((run) => !/ #[1-9][0-9]*$/.test(title(run))).length,
      };
    }
  }
  throw new Error("the workflow run listing has more than 10 pages");
}

// How every one of `runs` (completed) did no work in its latest attempt, or
// null when one did some: no job minted a lane token, and the agent-ready run
// either had its `Request the lane token` step fail (`mint-failed`, which
// wins), had the broker refuse it for the kill switch at broker-check or a
// mint, or had broker-check skip its broker ask for the kill switch
// (`breaker`), was skipped by the WIP cap (`capped`: pick-slot ran,
// resolve-issue did not), or was skipped by the admit job's blocker gate
// (`blocked`: its BLOCKER_STEP ran and pick-slot did not). A broker-check
// refusal for another reason, or one whose log gives none, is none of these.
// A run another gate stopped before its mint (an open closing PR, a reused
// branch) is none of these, so it is never re-fired here.
async function didNoWork(jobsOf, refusalOf, runs) {
  // A higher rank wins across runs; between equal ranks the first stays.
  const rank = { capped: 1, blocked: 1, breaker: 2, "mint-failed": 3 };
  let stalled = null;
  const atLeast = (kind) => {
    if (rank[kind] > (rank[stalled] ?? 0)) {
      stalled = kind;
    }
  };
  for (const run of runs) {
    if (!RUN_ID.test(String(run.id))) {
      return null;
    }
    const jobs = await jobsOf(run);
    const mints = jobs.flatMap((job) => (job?.steps ?? []).filter((step) => step?.name === MINT_STEP));
    if (mints.some((step) => step.conclusion === "success")) {
      return null;
    }
    const named = (name) => namedJobs(jobs, name);
    const endedAt = (job, name, conclusion) => (job?.steps ?? []).some((step) => step?.name === name && step.conclusion === conclusion);
    const failedAt = (job, name) => endedAt(job, name, "failure");
    const killed = named("resolve-issue").some((job) => endedAt(job, KILL_STEP, "success") && endedAt(job, BROKER_STEP, "skipped"));
    const checked = named("resolve-issue").find((job) => failedAt(job, BROKER_STEP));
    const minting = jobs.find((job) => failedAt(job, MINT_STEP));
    const capped =
      named("pick-slot").some((job) => job.conclusion === "success") &&
      named("resolve-issue").length > 0 &&
      named("resolve-issue").every((job) => job.conclusion === "skipped");
    const blocked =
      named("admit").some((job) => (job?.steps ?? []).some((step) => step?.name === BLOCKER_STEP && step.conclusion === "success")) &&
      named("pick-slot").every((job) => job.conclusion === "skipped");
    // One log per run: broker-check's when it refused, else the first failed mint's.
    const refused = killed ? null : checked ? refusalOf(checked, "check") : minting ? refusalOf(minting, "token") : null;
    if (killed || (await refused) === BREAKER) {
      atLeast("breaker");
    } else if (minting) {
      atLeast("mint-failed");
    } else if (capped) {
      atLeast("capped");
    } else if (blocked) {
      atLeast("blocked");
    }
  }
  return stalled;
}

// The reason the broker refused `job`, from its log: the failed step's last
// line before the runner's first `Process completed`, in `mode` (check or
// token). Null when that line is no such refusal or the log cannot be read
// within LOG_CAP_BYTES, or no log reader was given; the log is data, and no
// other line of it is read.
function refusalReader(jobLog, repo) {
  return async (job, mode) => {
    if (!jobLog || !RUN_ID.test(String(job?.id))) {
      return null;
    }
    let log;
    try {
      log = await jobLog(repo, job.id, { maxBytes: LOG_CAP_BYTES });
    } catch (error) {
      console.log(`::warning title=label-unblocked::job ${job.id}'s log was not read: ${escapeCommand(error?.message ?? error)}`);
      return null;
    }
    const lines = String(log ?? "").split("\n");
    const end = lines.findIndex((line) => STEP_FAILED.test(line));
    return end > 0 ? (DENIAL[mode].exec(lines[end - 1])?.[1] ?? null) : null;
  };
}

// Each run's latest-attempt job listing, read once per run id.
function jobLister(actions, repo) {
  const listed = new Map();
  return (run) => {
    if (!listed.has(run.id)) {
      listed.set(
        run.id,
        (async () => {
          const jobs = (await actions("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`))?.jobs;
          if (!Array.isArray(jobs)) {
            throw new Error(`run ${run.id}'s job listing has an unexpected shape`);
          }
          return jobs;
        })(),
      );
    }
    return listed.get(run.id);
  };
}

const namedJobs = (jobs, name) => jobs.filter((job) => job?.name === name || String(job?.name).startsWith(`${name} /`));

// Whether one of `runs` stopped at the admit job's provenance stop.
async function stoppedUntrusted(jobsOf, runs) {
  for (const run of runs.filter((item) => RUN_ID.test(String(item.id)))) {
    const admit = namedJobs(await jobsOf(run), "admit");
    if (admit.some((job) => (job?.steps ?? []).some((step) => step?.name === UNTRUSTED_STEP && step.conclusion === "success"))) {
      return true;
    }
  }
  return false;
}

// Whether one of `runs` ended green at the read runner's stale-workflow stop.
async function stoppedStale(jobsOf, runs) {
  for (const run of runs.filter((item) => item.conclusion === "success" && RUN_ID.test(String(item.id)))) {
    const resolve = namedJobs(await jobsOf(run), "resolve-issue");
    if (resolve.some((job) => (job?.steps ?? []).some((step) => step?.name === STALE_STEP && step.conclusion === "success"))) {
      return true;
    }
  }
  return false;
}

// A job that never ran on a runner: skipped, or no step ran and no runner took
// it. A job listing with no steps for a job a runner took is not one.
const neverStarted = (job) =>
  job?.conclusion === "skipped" || ((job?.steps ?? []).every((step) => step?.conclusion === "skipped") && (!job?.runner_id || !job?.started_at));

// Whether one of `runs` was cancelled after admit passed and before any
// resolve-issue job (pr-run-activity-read.yml's broker-check and run) started:
// pick-slot cancelled (its timeout, or a person), or resolve-issue cancelled
// while it waited for its slot (GitHub cancels a slot queue past its limit).
// A run a newer agent-ready run replaced in the workflow's concurrency group
// was cancelled while it waited, before admit ran, so it never counts.
async function cancelledBeforeWork(jobsOf, runs) {
  for (const run of runs.filter((item) => item.conclusion === "cancelled" && RUN_ID.test(String(item.id)))) {
    const jobs = await jobsOf(run);
    const named = (name) => namedJobs(jobs, name);
    const resolve = named("resolve-issue");
    if (
      named("admit").some((job) => job.conclusion === "success") &&
      resolve.every(neverStarted) &&
      [...named("pick-slot"), ...resolve].some((job) => job.conclusion === "cancelled")
    ) {
      return true;
    }
  }
  return false;
}

const sameRepo = (side, repo) => String(side?.repo?.full_name ?? "").toLowerCase() === repo.toLowerCase();

// The pull requests the lanes App opened for issue `number`: cross-referenced
// on the issue, from the issue's lane branch, with head and base in this
// repository.
async function lanePulls({ github, repo, number, bot }) {
  const here = `/repos/${repo}`.toLowerCase();
  const numbers = new Set(
    (await paginate(github, `/repos/${repo}/issues/${number}/timeline`))
      .map((event) => event.source?.issue)
      .filter(
        (source) =>
          source?.pull_request &&
          source.user?.login === bot &&
          NUMBER.test(String(source.number)) &&
          String(source.repository_url ?? "").toLowerCase().endsWith(here),
      )
      .map((source) => Number(source.number)),
  );
  const pulls = [];
  for (const pr of numbers) {
    const pull = await github("GET", `/repos/${repo}/pulls/${pr}`);
    if (pull?.user?.login === bot && sameRepo(pull.head, repo) && sameRepo(pull.base, repo) && isLaneBranch(pull.head?.ref, number)) {
      pulls.push(pull);
    }
  }
  return pulls;
}

// A listed human's open pull request for issue `number` (openPullsFor: one
// GitHub says closes it, or one with its `Refs:` line), or null: work running
// on the issue, as an open lane PR is.
async function humanPull({ github, repo, number, humans }) {
  for (const pr of await openPullsFor(github, repo, number)) {
    const pull = await github("GET", `/repos/${repo}/pulls/${pr}`);
    if (pull?.state === "open" && humans.has(pull.user?.id)) {
      return pull;
    }
  }
  return null;
}

// The newest of those opened at or after `addedAt`, or null.
async function lastLanePull({ github, repo, number, addedAt, bot }) {
  let last = null;
  for (const pull of await lanePulls({ github, repo, number, bot })) {
    const created = Date.parse(pull.created_at);
    if (created >= addedAt && (last === null || created > Date.parse(last.created_at))) {
      last = pull;
    }
  }
  return last;
}

// The titles of every work-resolve-issue run that has not finished.
async function runsInFlight(actions, repo) {
  const titles = [];
  for (const status of IN_FLIGHT) {
    const batch = (await actions("GET", `/repos/${repo}/actions/workflows/work-resolve-issue.yml/runs?status=${status}&per_page=100`))
      ?.workflow_runs;
    if (!Array.isArray(batch) || batch.length >= 100) {
      throw new Error(`the ${status} work-resolve-issue run listing has an unexpected shape or 100 runs`);
    }
    titles.push(...batch.map((run) => String(run.display_title ?? "")));
  }
  return titles;
}

// For a fix issue post-merge-demotion-alert reopened on a repeat failure: why
// it is not relabeled now, or null with what to do. Null for any other issue,
// and for one agent-ready was added to since the reopen, which the restart
// and re-fire rules then take.
async function recurrenceRefusal({ github, repo, issue, bot, humans, inFlight, read }) {
  if (issue.user?.login !== ALERT_BOT || !FIX_ISSUE.test(String(issue.body ?? ""))) {
    return null;
  }
  const comments = await read("comments");
  const recurrence = comments
    .filter((comment) => comment.user?.login === ALERT_BOT && String(comment.body ?? "").startsWith(RECURRENCE_PREFIX))
    .at(-1);
  if (recurrence === undefined) {
    return null;
  }
  const at = Date.parse(recurrence.created_at);
  if (!RUN_ID.test(String(recurrence.id)) || !Number.isFinite(at)) {
    throw new Error("its recurrence comment has no readable id or time");
  }
  const events = await read("events");
  if (events.some((event) => isLabel(event, "labeled") && Date.parse(event.created_at) >= at)) {
    return null;
  }
  // The App's re-add admits on its own, so it may only repeat a label that
  // admission would take: a listed human's or the App's own.
  const lastAdd = events.filter((event) => isLabel(event, "labeled")).at(-1);
  if (lastAdd === undefined || !trustedLabeler(lastAdd, { bot, humans })) {
    return { reason: `${LABEL} was added by neither a listed human nor the lanes App` };
  }
  const held = (issue.labels ?? []).map((label) => String(typeof label === "string" ? label : label.name).toLowerCase()).find((label) => HOLDS.has(label));
  if (held) {
    return { reason: `held by ${held}` };
  }
  const open = (await lanePulls({ github, repo, number: issue.number, bot })).find((pull) => pull.state === "open");
  if (open) {
    return { reason: `its lane PR #${open.number} is open` };
  }
  const person = await humanPull({ github, repo, number: issue.number, humans });
  if (person) {
    return { reason: `a listed human's PR #${person.number} for it is open` };
  }
  const titles = await inFlight();
  if (titles === null) {
    return { reason: "no Actions token to read its lane runs" };
  }
  if (titles.some((title) => title.endsWith(` #${issue.number}`))) {
    return { reason: "a lane run for it is in flight" };
  }
  const untitled = titles.filter((title) => !/ #[1-9][0-9]*$/.test(title)).length;
  if (untitled > 0) {
    return { reason: `cannot tell whether a lane run for it is in flight: ${untitled} unfinished run(s) name no issue in their title` };
  }
  const recorded = comments.some((comment) => comment.user?.login === bot && RELABELED.exec(String(comment.body ?? ""))?.[1] === String(recurrence.id));
  return { reason: null, resets: at, recurrence: recurrence.id, recorded };
}

// What the lane PR the newest agent-ready label's run opened asks for: a
// hand-off to triage once it merged with `Refs:` or closed unmerged, or
// nothing, with why. `held`: the issue's one hold is needs-human, which only
// the end (merge or unmerged close) of the Refs PR report-outcome set it for
// lifts.
function pullRefusal({ pull, number, comments, events, bot, held }) {
  const byApp = (marker) => comments.some((comment) => comment.user?.login === bot && String(comment.body ?? "").startsWith(marker));
  const refs = String(pull.body ?? "").split(/\r?\n/, 1)[0].trim() === `Refs: #${number}`;
  const merged = Boolean(pull.merged_at);
  if (held) {
    const human = events.filter((event) => ["labeled", "unlabeled"].includes(event.event) && String(event.label?.name).toLowerCase() === HUMAN_LABEL);
    const newest = human.at(-1);
    const ours = newest?.event === "labeled" && newest.actor?.login === bot && byApp(refsHoldMarker(pull.number));
    if (!(ours && refs && pull.state !== "open")) {
      return { reason: `held by ${HUMAN_LABEL}` };
    }
  }
  if (pull.state === "open") {
    return { reason: `its lane PR #${pull.number} is open` };
  }
  if (merged && !refs) {
    return { reason: `its lane PR #${pull.number} merged` };
  }
  const ended = Date.parse(merged ? pull.merged_at : pull.closed_at);
  if (!Number.isFinite(ended)) {
    throw new Error(`lane PR #${pull.number} is closed with no readable close time`);
  }
  return { reason: null, handOff: merged ? "merged" : "closed", pr: pull.number, resets: ended, explained: byApp(handedMarker(pull.number)), release: held };
}

// Why an agent-ready issue whose newest label has no marker after it is not
// re-fired or handed off now, or null with what to do.
async function refireRefusal({ github, actions, jobLog, repo, number, lastAdd, addedAt, markers, comments, events, humans, bot, workflowKey, held, limits, now, wipCapped }) {
  if (!trustedLabeler(lastAdd, { bot, humans })) {
    return { reason: `${LABEL} was added by neither a listed human nor the lanes App` };
  }
  const pull = await lastLanePull({ github, repo, number, addedAt, bot });
  if (pull !== null) {
    return pullRefusal({ pull, number, comments, events, bot, held });
  }
  if (held) {
    return { reason: `held by ${HUMAN_LABEL}` };
  }
  // The lane stops for good on an issue untrusted provenance holds
  // (check-blockers.mjs), so one is never re-fired or handed to a person here:
  // admission's refusal path takes it to a person. The label itself is a hold
  // above; this is the removal by someone unlisted.
  if (untrustedHold({ labels: [], events, humans, isApp: (actor) => actor?.login === bot })) {
    return { reason: `${UNTRUSTED} was last removed by neither a listed human nor the lanes App` };
  }
  // The lane skips an issue a blocker still blocks (check-blockers.mjs), so
  // one is never re-fired or handed to a person while one does.
  const closes = new Map();
  const pending = await stillBlocking(
    await blockersOf(github, `/repos/${repo}/issues/${number}`),
    repo,
    (blocker) => trustedClose({ github, repo, number: blocker, humans, closes, bot }),
    closedElsewhere({ github, repo, humans, closes }),
  );
  if (pending.length > 0) {
    return { reason: `waiting on ${pending.length} blocker(s) not closed by a listed human or a merge` };
  }
  if (!actions) {
    return { reason: "no Actions token to read its lane run" };
  }
  // A record counts once the App added the label back at or after it; one
  // whose label write failed is finished by the next sweep, not posted again.
  // A re-fire record on workflow files `key` other than a breaker trip's.
  const refiredOn = (marker, key) => marker.outcome === "refired" && !marker.breaker && marker.key === key;
  const relabeled = (marker) =>
    events.some((event) => isLabel(event, "labeled") && event.actor?.login === bot && Date.parse(event.created_at) >= marker.at);
  // A re-fire past the first on these workflow files waits longer each time
  // (backoffDue from `since`), and its record is the one backoff comment,
  // edited in place, never a new comment or a hold.
  const backoff = (key, since, cause) => {
    const first = Math.min(...markers.filter((marker) => refiredOn(marker, key)).map((marker) => marker.at));
    // Each breaker record's own re-add, the App's first after it (dated by
    // when it was posted), is that trip's, not this cause's; the backoff
    // comment's edits never move it.
    const adds = events.filter((event) => isLabel(event, "labeled") && event.actor?.login === bot);
    const trips = new Set(markers.filter((marker) => marker.breaker).map((marker) => adds.find((event) => Date.parse(event.created_at) >= marker.at)));
    const refires = adds.filter((event) => Date.parse(event.created_at) >= first && !trips.has(event)).length;
    const due = backoffDue(since, refires);
    if (now < due) {
      return { reason: `re-fired ${refires} time(s) on workflow files ${key}; it is re-fired again after ${new Date(due).toISOString()}` };
    }
    const own = comments.filter((comment) => comment.user?.login === bot && INFRA.test(String(comment.body ?? ""))).at(-1);
    return { reason: null, resets: due, refire: key, recorded: true, infra: { id: own?.id, body: infraComment(key, cause, refires + 1) } };
  };
  // An issue with nothing running since `since`: once STRANDED_HOURS have
  // passed with no open lane PR and no open pull request of a listed human's
  // for it, re-fired, once per version of the lane workflow files and then on
  // a backoff.
  const stranded = async (since, why, cause) => {
    if (now - since < STRANDED_HOURS * HOUR_MS) {
      return { reason: why };
    }
    const open = (await lanePulls({ github, repo, number, bot })).find((item) => item.state === "open");
    if (open) {
      return { reason: `${why}; its lane PR #${open.number} is open` };
    }
    const person = await humanPull({ github, repo, number, humans });
    if (person) {
      return { reason: `${why}; a listed human's PR #${person.number} for it is open` };
    }
    const key = await workflowKey();
    const fired = markers.filter((marker) => refiredOn(marker, key));
    if (fired.some(relabeled)) {
      return backoff(key, since, strandedCause[cause]);
    }
    return { reason: null, resets: since, refire: key, recorded: fired.length > 0, cause: strandedCause[cause] };
  };
  const { mine: runs, untitled } = await laneRuns(actions, repo, number, addedAt);
  if (runs.length === 0) {
    return untitled > 0
      ? {
          reason: `cannot tell whether a lane run started since ${LABEL} was added: ${untitled} work-resolve-issue run(s) then name no issue in their title`,
        }
      : stranded(addedAt, `no lane run since ${LABEL} was added`, "no-run");
  }
  if (runs.some((run) => run.status !== "completed")) {
    return { reason: "its lane run is still going" };
  }
  // When the newest of its runs ended: every clock below starts there.
  const ended = Math.max(...runs.map((run) => Date.parse(run.updated_at)).filter(Number.isFinite), addedAt);
  const jobsOf = jobLister(actions, repo);
  if (await stoppedUntrusted(jobsOf, runs)) {
    return { reason: "its lane run stopped on untrusted provenance, which a person decides" };
  }
  const stalled = await didNoWork(jobsOf, refusalReader(jobLog, repo), runs);
  if (stalled) {
    // Breaker trips since a listed human last added agent-ready or a run last
    // reported; past limits.limit-stops-per-issue of them, the stranded backoff.
    const from = Math.max(
      Number.NEGATIVE_INFINITY,
      ...events.filter((event) => isLabel(event, "labeled") && humans.has(event.actor?.id)).map((event) => Date.parse(event.created_at)),
      ...markers.filter((marker) => marker.outcome !== "refired").map((marker) => marker.at),
    );
    const trips = stalled === "breaker" ? markers.filter((marker) => marker.breaker && marker.at > from).length : 0;
    const over = trips - limits["limit-stops-per-issue"];
    const due = over >= 0 ? backoffDue(ended, over) : ended + limits["reset-clamp-min"] * HOUR_MS;
    if (now < due) {
      const why = stalled === "breaker" ? `the broker refused its lane run for the lanes kill switch (trip ${trips + 1})` : "its lane run did no work";
      return { reason: `${why}; it is re-fired after ${new Date(due).toISOString()}` };
    }
    if (await wipCapped()) {
      return { reason: "its lane run did no work, and the issue lane is paused over its WIP cap" };
    }
    const key = await workflowKey();
    // A record after the newest label is one whose label write failed: the
    // sweep finishes it without posting another.
    const recorded = markers.some((marker) => marker.outcome === "refired" && marker.at >= addedAt);
    // A mint that keeps failing (a broker misconfigured, an issue it refuses)
    // goes on a backoff after limits.limit-stops-per-issue re-fires on these
    // workflow files, as a crash does after one. A WIP cap skip made no mint
    // attempt, and the cap and restarts-per-run bound it.
    const fired = markers.filter((marker) => refiredOn(marker, key)).length;
    if (stalled === "mint-failed" && !recorded && fired >= limits["limit-stops-per-issue"]) {
      return backoff(key, ended, MINT_CAUSE);
    }
    return { reason: null, resets: due, refire: key, recorded, stall: stalled };
  }
  if (!runs.some((run) => FAILED.has(run.conclusion)) && !(await cancelledBeforeWork(jobsOf, runs)) && !(await stoppedStale(jobsOf, runs))) {
    return stranded(ended, "its lane run did not fail", "no-report");
  }
  const key = await workflowKey();
  const recorded = markers.filter((marker) => refiredOn(marker, key));
  if (recorded.some(relabeled)) {
    return stranded(ended, `already re-fired for workflow files ${key}`, "failed-again");
  }
  return { reason: null, resets: addedAt, refire: key, recorded: recorded.length > 0 };
}

// Why an agent-ready issue is not restarted now (after a limit stop) or
// re-fired (after a failed run), or null with the time it has waited since.
// Every fact is read from the API this sweep; `read` lists the issue's
// comments or events once, shared with the recurrence check.
async function restartRefusal({ github, actions, jobLog, repo, issue, bot, humans, now, workflowKey, limits, wipCapped, read }) {
  const labels = (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label.name));
  const holds = labels.map((label) => String(label).toLowerCase()).filter((label) => HOLDS.has(label));
  // needs-human alone may be report-outcome's hold on a Refs PR, which the
  // lane PR check below may lift; any other hold stops everything here.
  const held = holds.length > 0;
  if (held && (holds.length > 1 || holds[0] !== HUMAN_LABEL)) {
    return { reason: `held by ${holds.find((label) => label !== HUMAN_LABEL)}` };
  }
  const comments = await read("comments");
  const markers = appMarkers(comments, bot);
  // A re-fire record ends no run, so only outcome markers count here.
  const marker = markers.filter((item) => item.outcome !== "refired").at(-1);
  const events = await read("events");
  // The listing can be older than a removal: agent-ready taken off since, by
  // anyone but the App restarting the lane, ends all unblock actions here.
  const labelEvents = events.filter((event) => isLabel(event, "labeled") || isLabel(event, "unlabeled"));
  const newestLabel = labelEvents.at(-1);
  if (newestLabel !== undefined && isLabel(newestLabel, "unlabeled") && !isRestart(events, events.lastIndexOf(newestLabel), markers, bot)) {
    return { reason: `${LABEL} was removed` };
  }
  // A lane run starts on agent-ready being added, and its outcome marker ends
  // it, so a label added after the newest marker is a run since: still going,
  // one that left no marker (a PR opened, or the run failed), or none yet.
  const lastAdd = events.filter((event) => isLabel(event, "labeled")).at(-1);
  const addedAt = Date.parse(lastAdd?.created_at);
  if (Number.isFinite(addedAt) && (marker === undefined || addedAt > marker.at)) {
    return refireRefusal({
      github,
      actions,
      jobLog,
      repo,
      number: issue.number,
      lastAdd,
      addedAt,
      markers,
      comments,
      events,
      humans,
      bot,
      workflowKey,
      held,
      limits,
      now,
      wipCapped,
    });
  }
  if (held) {
    return { reason: `held by ${HUMAN_LABEL}` };
  }
  const since = events
    .filter((event) => isLabel(event, "labeled") && event.actor?.login !== bot)
    .reduce((latest, event) => Math.max(latest, Date.parse(event.created_at)), Number.NEGATIVE_INFINITY);
  // report-outcome keeps agent-ready after a turn cap only while a restart is
  // left, and hands the issue back otherwise; the count here bounds a forged
  // or stale marker the same way.
  if (marker?.outcome === "turn-cap") {
    // Only a listed human's agent-ready resets the turn-cap count, so another
    // labeler cannot buy restarts.
    const humanSince = events
      .filter((event) => isLabel(event, "labeled") && humans.has(event.actor?.id))
      .reduce((latest, event) => Math.max(latest, Date.parse(event.created_at)), Number.NEGATIVE_INFINITY);
    const caps = markers.filter((item) => item.outcome === "turn-cap" && item.at > humanSince).length;
    return caps > limits["turn-cap-restarts"]
      ? { reason: `${caps} turn-cap stops since a person last added ${LABEL}` }
      : { reason: null, resets: marker.at };
  }
  const funding = marker?.outcome === "funding";
  if (!funding && marker?.outcome !== "limited") {
    return { reason: "no limit stop is its newest lane outcome" };
  }
  // A limit or funding stop (ci-workflows#781) that keeps stopping the lane
  // goes to a person: count both since a person last added agent-ready.
  const stops = markers.filter((item) => (item.outcome === "limited" || item.outcome === "funding") && item.at > since).length;
  if (stops >= limits["limit-stops-per-issue"]) {
    const explained = comments.some(
      (comment) =>
        comment.user?.login === bot && String(comment.body ?? "").startsWith(ESCALATED) && Date.parse(comment.created_at) > since,
    );
    return { reason: `${stops} limit stops since a person last added ${LABEL}`, escalate: stops, explained };
  }
  // A funding stop with no regain date waits for a person.
  if (funding && marker.resets === null) {
    return { reason: "waiting for a person to restore the lane's funding" };
  }
  const resets = clampReset(marker.resets, marker.at, limits);
  if (now < resets) {
    return { reason: `waiting for the limit to reset at ${new Date(resets).toISOString()}` };
  }
  return { reason: null, resets };
}

// Restarts, re-fires or hands off up to `cap` issues, longest-waiting first.
// Returns how many reads or writes failed.
async function restartLimited({ github, actions, jobLog, repo, bot, humans, now, limits, status, cap = limits["restarts-per-run"] }) {
  let failed = 0;
  const ready = [];
  // Main's blob SHAs of the lane workflow files, read once per run.
  let key;
  const workflowKey = () =>
    (key ??= (async () => {
      const shas = [];
      for (const path of LANE_WORKFLOWS) {
        const sha = (await github("GET", `/repos/${repo}/contents/${path}?ref=main`))?.sha;
        if (!BLOB.test(String(sha))) {
          throw new Error(`${path} on main has no blob SHA`);
        }
        shas.push(sha);
      }
      return shas.join("-");
    })());
  // The issue lane's run pause; a read that fails never pauses.
  const wipCapped = () => status().then((s) => s.paused);
  // The unfinished lane runs, read once per run and only for a reopened fix
  // issue; null with no Actions token.
  let flight;
  const inFlight = () => (flight ??= actions ? runsInFlight(actions, repo) : Promise.resolve(null));
  let open;
  try {
    open = (await paginate(github, `/repos/${repo}/issues?state=open&labels=${LABEL}`)).filter(
      (item) => !item.pull_request && NUMBER.test(String(item.number)),
    );
  } catch (error) {
    reportError("restart", error);
    return 1;
  }
  for (const issue of open) {
    const listed = {};
    const read = (kind) => (listed[kind] ??= paginate(github, `/repos/${repo}/issues/${issue.number}/${kind}`));
    try {
      const verdict =
        (await recurrenceRefusal({ github, repo, issue, bot, humans, inFlight, read })) ??
        (await restartRefusal({
          github,
          actions,
          jobLog,
          repo,
          issue,
          bot,
          humans,
          now,
          workflowKey,
          limits,
          wipCapped,
          read,
        }));
      const { reason, escalate, explained } = verdict;
      if (escalate) {
        // The comment first and the label last: the label is a hold, so a
        // sweep after a failed comment would never come back to post it. A
        // failed label write is retried by the next sweep, which finds the
        // comment and adds only the label.
        const base = `/repos/${repo}/issues/${issue.number}`;
        if (!explained) {
          await github("POST", `${base}/comments`, { body: escalationComment(escalate) });
        }
        await github("POST", `${base}/labels`, { labels: [HUMAN_LABEL] });
        console.log(`label-unblocked: #${issue.number} handed to a person: ${reason}`);
        continue;
      }
      if (reason !== null) {
        console.log(`label-unblocked: #${issue.number} not restarted: ${reason}`);
        continue;
      }
      ready.push({ ...verdict, number: Number(issue.number) });
    } catch (error) {
      failed += 1;
      reportError(issue.number, error);
    }
  }
  ready.sort((a, b) => a.resets - b.resets || a.number - b.number);
  console.log(`label-unblocked: ${ready.filter((item) => item.recurrence).length} reopened fix issue(s) to relabel`);
  for (const { number } of ready.slice(cap)) {
    console.log(`label-unblocked: #${number} restart deferred: ${cap} restarts this run`);
  }
  for (const { number, refire, cause, stall, recurrence, recorded, handOff, pr, explained, release, infra } of ready.slice(0, cap)) {
    const base = `/repos/${repo}/issues/${number}`;
    if (handOff) {
      // The comment first, then the labels; agent-ready comes off last, so a
      // failed write leaves the issue for the next sweep, which finds the
      // comment and moves only the labels. With no `status:` label and no
      // agent-ready, the hourly triage sweep dispatches intake on it, whose
      // fresh `status: ready` re-admits it; needs-triage would keep that
      // verdict from ready, so none is added.
      try {
        if (!explained) {
          await github("POST", `${base}/comments`, { body: handOff === "merged" ? refsMergedComment(pr) : refsClosedComment(pr) });
        }
        if (release) {
          await github("DELETE", `${base}/labels/${HUMAN_LABEL}`);
        }
        await github("DELETE", `${base}/labels/${encodeURIComponent(READY)}`).catch((error) => {
          if (error?.status !== 404) {
            throw error;
          }
        });
        await github("DELETE", `${base}/labels/${LABEL}`);
        console.log(`label-unblocked: #${number} handed to triage: lane PR #${pr} ${handOff === "merged" ? "merged with Refs:" : "closed unmerged"}`);
      } catch (error) {
        failed += 1;
        reportError(number, error);
      }
      continue;
    }
    try {
      // The record first: a failed comment re-fires nothing, so the bound holds.
      if (refire && !recorded) {
        await github("POST", `${base}/comments`, { body: stall === "breaker" ? breakerComment(refire) : refireComment(refire, cause) });
      }
      if (infra) {
        await (infra.id === undefined
          ? github("POST", `${base}/comments`, { body: infra.body })
          : github("PATCH", `/repos/${repo}/issues/comments/${infra.id}`, { body: infra.body }));
      }
      // The labels, not the record, bound a relabel, so a failed record (the
      // alert locks every fix issue) is named and the relabel goes ahead.
      if (recurrence && !recorded) {
        await github("POST", `${base}/comments`, { body: recurrenceComment(recurrence) }).catch((error) =>
          console.log(`::warning title=label-unblocked::#${number}: the relabel record was not posted: ${escapeCommand(error?.message ?? error)}`),
        );
      }
      await github("DELETE", `${base}/labels/${LABEL}`);
    } catch (error) {
      failed += 1;
      reportError(number, error);
      continue;
    }
    // The label is off now; one failed re-add would leave the issue out of
    // the lane with nothing saying so, so it is tried twice and then named.
    const add = () => github("POST", `/repos/${repo}/issues/${number}/labels`, { labels: [LABEL] });
    try {
      await add().catch(add);
      const why = infra ? "re-fired on a backoff" : stall === "breaker" ? "re-fired after a kill-switch refusal" : refire ? "re-fired after its failed run" : recurrence ? "relabeled after its reopen on a repeat failure" : "restarted after its limit stop";
      console.log(`label-unblocked: #${number} ${why}`);
    } catch (error) {
      failed += 1;
      reportError(number, new Error(`${LABEL} was removed for a restart but not added back: ${error?.message ?? error}`));
    }
  }
  return failed;
}

const SPLIT_CLOSED = "<!-- work-unblock split parent closed -->";

// A close that counts as done: by a listed human or a merge, or the lanes
// App's close of a size split's parent once each sub-issue's close counts
// (admit.mjs splitParentClosed, owner Q93).
async function isTrustedClose(github, repo, issue, humans, bot) {
  const trusted = async (number) => isTrustedClose(github, repo, await github("GET", `/repos/${repo}/issues/${number}`), humans, bot);
  return (await closedByHumanOrMerge(github, repo, issue, humans)) || splitParentClosed({ github, repository: repo, issue, isApp: (actor) => actor?.login === bot, humans, trusted });
}

// For each issue in `closed` (on the sweep, only one a listed human or a
// merge closed), closes its split parent when it is done (closeSplitParent).
// Returns how many reads or writes failed.
async function closeSplitParents({ github, repo, closed, sweep, humans, bot }) {
  const closes = new Map();
  let failed = 0;
  for (const number of closed) {
    try {
      await closeSplitParent({ github, repo, number, humans, closes, bot, sweep });
    } catch (error) {
      failed += 1;
      reportError(number, error);
    }
  }
  return failed;
}

// Closes, as completed and with one comment first, the open split parent
// (admit.mjs isSplitParent) of issue `number`, once every sub-issue is
// closed by a listed human or a merge (owner Q93). Its body is never edited.
async function closeSplitParent({ github, repo, number, humans, closes, bot, sweep }) {
  if (!(await github("GET", `/repos/${repo}/issues/${number}`))?.parent_issue_url || (sweep && !(await trustedClose({ github, repo, number, humans, closes, bot })))) {
    return;
  }
  const parent = await github("GET", `/repos/${repo}/issues/${number}/parent`);
  if (parent?.state !== "open" || !NUMBER.test(String(parent.number)) || !String(parent.repository_url ?? "").toLowerCase().endsWith(`/repos/${repo}`.toLowerCase())) {
    return;
  }
  const base = `/repos/${repo}/issues/${parent.number}`;
  const comments = await paginate(github, `${base}/comments`);
  const children = await paginate(github, `${base}/sub_issues`);
  if (!(await isSplitParent({ github, repository: repo, issue: parent, comments, children, isApp: (actor) => actor?.login === bot, humans }))) {
    return;
  }
  for (const child of children) {
    if (child?.state !== "closed" || !NUMBER.test(String(child.number)) || !(await trustedClose({ github, repo, number: Number(child.number), humans, closes, bot }))) {
      console.log(`label-unblocked: split parent #${parent.number} stays open: sub-issue #${child?.number} is not closed by a listed human or a merge`);
      return;
    }
  }
  if (!comments.some((comment) => comment.user?.login === bot && String(comment.body ?? "").startsWith(SPLIT_CLOSED))) {
    await github("POST", `${base}/comments`, {
      body: `${SPLIT_CLOSED}\nEvery sub-issue of this split is closed by a listed human or a merge (${children.map((child) => `#${child.number}`).join(", ")}), so the lanes App closes it as completed.`,
    });
  }
  await github("PATCH", base, { state: "closed", state_reason: "completed" });
  console.log(`label-unblocked: split parent #${parent.number} closed as completed`);
}

// What a marked issue's admission check reads from the default branch: the
// rules, models.issue-dimensions, the issue lane's web hosts and the field
// setter reader. resolve-config needs the packages its step installed in this
// job, so it loads only when a marked issue needs it.
const baseAdmission = (env) => {
  let loaded;
  return () =>
    (loaded ??= (async () => {
      const config = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
      const dimensionsConfig = config.issueDimensionsFromBase(env);
      if (!dimensionsConfig?.fields) {
        throw new Error("the config sets no models.issue-dimensions");
      }
      return {
        rules: loadRules(`${env.BASE_PATH || ".base"}/.github/actions/resolve-config/admission-rules.json`),
        dimensionsConfig,
        webHosts: config.issueLaneWebHostsFromBase(env),
        fieldSetters: config.fieldSetters,
      };
    })());
};

// The rate guard's latch with its readings recorded under token, so a second
// client's readings never mix with the App token's.
export function budgetLatch(token, latch = rateLimitLatch) {
  return { ...latch, guard: (fetchImpl) => latch.guard(fetchImpl, { token }) };
}

export async function main({ env = process.env, github, actions, jobLog, now = Date.now(), rate = searchRateLimit(), admission = baseAdmission(env) } = {}) {
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const sweep = env.GITHUB_EVENT_NAME === "schedule";
    const event = sweep ? {} : JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, "utf8"));
    if (!sweep && (env.GITHUB_EVENT_NAME !== "issues" || event.action !== "closed" || !NUMBER.test(String(event.issue?.number)))) {
      throw new Error("this runs only on an issue closing or on the schedule");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("label-unblocked: the lanes kill switch stops this run; nothing read or labeled");
      return 0;
    }
    if (!sweep) {
      // A bot's close (the lanes App's, or a PR merge a bot ran) is skipped
      // cleanly: the broker refuses it, and the hourly sweep picks it up.
      if (event.sender?.type === "Bot") {
        console.log("label-unblocked: a bot closed this issue; nothing read or labeled");
        return 0;
      }
      if (!(await checkCloser(env, actions))) {
        console.log("label-unblocked: the closer or the re-runner is not a listed human; nothing read or labeled");
        return 0;
      }
    }
    const repo = env.GITHUB_REPOSITORY;
    const { humans, logins } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, onResponse: rate.onResponse });
    if (sweep) {
      const latch = budgetLatch("github-token");
      actions ??= env.ACTIONS_TOKEN ? createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, latch }) : null;
      jobLog ??= env.ACTIONS_TOKEN ? createJobLogReader({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, latch }) : null;
    }
    const window = sweep ? await sweepSince({ actions, repo, now, runId: env.GITHUB_RUN_ID }) : null;
    const closed = sweep ? await closedSince(github, repo, new Date(window.since)) : [Number(event.issue.number)];
    if (sweep) {
      const minutes = Math.round((now - window.since) / 60_000);
      console.log(`label-unblocked: ${closed.length} issue(s) closed in the last ${minutes} minutes (${window.why})`);
    }
    const bot = env.LANES_BOT_LOGIN || DEFAULT_BOT;
    const resolved = env.RESOLVED_CONFIG || `${env.RUNNER_TEMP ?? ""}/resolved-config.json`;
    const limits = readLimits(resolved);
    const wip = readWip(resolved);
    // The issue lane's status, read once per run and only when asked.
    let read;
    const status = () => (read ??= checkWip(github, { repo, bot, now, limits, wip, remaining: rate.remaining }));
    const gate = admissionGate(status);
    let failed = sweep ? await admitDeferred({ github, repo, humans, bot, gate, appId: logins.get(bot), admission }) : 0;
    failed += await labelUnblocked({ github, repo, closed, sweep, humans, bot, gate });
    failed += await closeSplitParents({ github, repo, closed, sweep, humans, bot });
    if (sweep) {
      failed += await restartLimited({ github, actions, jobLog, repo, bot, humans, now, limits, status });
    }
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=label-unblocked::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

// `--check-closer` writes only the closer check, as the `proceed` step
// output, so the workflow can stop before it requests a token.
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  if (process.argv[2] === "--check-closer") {
    const proceed = await checkCloser(process.env);
    writeOutputs({ proceed: String(proceed) });
    console.log(`label-unblocked: closer and re-runner ${proceed ? "are" : "are not both"} listed humans`);
  } else {
    process.exitCode = await main();
  }
}
