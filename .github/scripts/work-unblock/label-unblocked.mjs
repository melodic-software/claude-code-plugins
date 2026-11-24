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
// The close path also strips the closed issue's own queue labels
// (agent-ready, `status: ready`, admission-deferred; stripClosed), only those
// present, unless it is open again or is a post-merge fix issue. A bot's close
// runs no close path: where the lanes App closes an issue itself (a split
// parent here, report-outcome's close route) it strips them before the close,
// and the sweep strips each issue in its window a listed human or a merge
// closed (a merge the App ran among them).
//
// Every status this writes goes to the issue's Work status field
// (models.issue-status, write-status.mjs statusWriter), and every status it
// reads, a hold included, comes from that field first (read-status.mjs): the
// labels below name the states, and a legacy status label is only ever taken
// off. agent-ready stays a label beside its field state.
//
// Each new agent-ready is paced: at or over the issue lane's queued cap, or
// with the lane paused over its WIP or held cap (check-wip-cap.mjs, on or
// after wip.pause-from, or whenever a search answers incomplete_results:
// true) a ready issue is set deferred instead, and with room for k
// admissions only the first k ready issues are labeled. Every sweep revisits
// the open deferred issues oldest first, before the closed ones: one still
// ready is labeled agent-ready within the room, a held one, or one an open
// pull request in this repository names (intake defers those), stays
// deferred, and any other goes back to ready, or to needs-triage when no
// listed human or the App set its status: ready (dropDeferral). A
// deferred issue not yet agent-ready counts as ready only while it keeps
// `status: ready`, carries neither do-not-merge nor needs-human, has no
// untrusted-provenance hold, and neither gained `area: security` nor had its
// body edited since its newest admission-deferred add (admit.mjs
// deferralLapsed). One of those holds keeps it deferred, and one that lost
// `status: ready` loses admission-deferred. One that gained the security area
// or a body edit since gets admit.mjs's comment and loses `status: ready` and
// admission-deferred, parked at `needs-owner-decision` for the security
// area, else at `status: confirmed`. A hold's comment names its owner reason
// as the stop-reason marker and line (heldText). A person's mark below is judged by
// decide, which refuses on the same changes. Restarts, re-fires and relabels below
// re-run admitted issues and are never paced. Each admission also lifts a
// parked `status: confirmed` beside `status: ready`, as admit.mjs does.
// Before any new agent-ready, an issue a merged `Refs:` pull request may have
// done (admit.mjs mergedRefsAfter) is parked at `status: confirmed`, losing
// `status: ready` and admission-deferred, with admit.mjs's comment naming the
// pull request; each pass reads its issues in one GraphQL call
// (mergedRefsReader), and a failed read admits as before.
//
// An issue it blocked that is otherwise ready but carries `status: confirmed`
// without `status: ready` is never labeled: `status: ready` is what admission
// passed. When admission parked it (admit.mjs admissionParked), a blocker closed
// after it parked, intake admits its author, no refuse label holds it, and its
// milestone is not in admission-rules.json's `cordoned-milestones`, the App
// hands it back to intake (handBackParked): a comment opening with
// UNPARKED_MARKER, which the hourly triage sweep reads to send it to intake,
// then its Work status set to needs-triage. The close check makes this once per
// close: a sweep's window overlaps the close run, and an issue intake parked
// again after the close stays parked. Until a trusted `status: ready` follows
// that hand-back, the issue is not labeled. Only issues a closed blocker
// blocked are read, so the bound is that blocker list, and the count is logged
// before any write.
//
// A listed human adding admission-deferred to an issue with `status: ready`
// is the mark of a decided issue (owner decision Q75): the sweep reads its
// Size, Complexity and Uncertainty fields (a value counts only when a listed
// human or the App set it, as `status: ready` must be added; no default
// stands in) and runs intake's admission
// rules on it (admit.mjs decide). It is admitted within the room only on an
// admit verdict. A refusal gets admit.mjs's comment, `needs-owner-decision`
// for `status: ready` when it holds for a person, needs-triage when its one
// reason is done-when items a lane run cannot perform beside items it can
// (decide's `triage`: the triage sweep sends it to intake, whose refine step
// splits them), else `status: confirmed`, as
// intake's admit parks it; a wait on an open pull request stays deferred, and
// one on a blocker goes back to ready, so its blocker's close admits it. One
// the rules leave alone loses its deferral (dropDeferral) with a comment
// saying why.
//
// After the closed ones, the sweep runs those rules on the open `status:
// ready` issues in no queue (neither agent-ready nor admission-deferred, no
// hold or refuse label, no open blocker or sub-issue), at most
// limits.readmit-per-run of them, oldest updated first (readmitReady), and
// writes as intake's admission does. One with an open blocker or sub-issue
// goes to the rules too, once a day, while no admission comment is newer than
// its newest `status: ready` (admissionUndecided). A born-triaged issue (check-born-triaged
// notBornTriaged: the marker as its body's last line, a listed human or the
// App its author) that the rules refuse only for a Size or Uncertainty no one
// set yet waits with no write: its filer sets them after filing, and if no one
// does, the triage sweep dispatches intake for it.
//
// An agent-ready issue left with nothing running is stranded: no hold, no open
// lane pull request or open pull request of a listed human's for it, no
// outcome marker since its newest agent-ready, and no work-resolve-issue run
// for that label, or only one that ended with no report, over its cause's
// limits.stranded-backoff-hours ago. It is re-fired with the re-fire record
// below once per version of the lane workflow files, and after that on a
// backoff (those hours doubling with each re-fire, at most
// BACKOFF_CAP_HOURS), recorded in one comment
// edited in place; it never gets needs-human. All share
// limits.restarts-per-run. An issue a merged pull request names on a `Refs:`
// line after its newest decision or refinement comment (admit.mjs
// mergedRefsAfter, as admission reads it) is never re-fired: it is handed to
// triage as a lane PR merged with `Refs:` is.
//
// The lane skips an issue a blocker still blocks and keeps agent-ready on
// (check-blockers.mjs), so the close path above, which leaves an agent-ready
// issue alone, never re-runs it. The sweep does: an agent-ready issue a
// blocker still blocks is never re-fired, stranded or handed to a person, and
// a run the blocker gate skipped, at check-admission or at the read runner's in-slot
// re-check, is re-fired like a run that did no work once none blocks. An umbrella, an issue with an open sub-issue, is skipped and
// waits the same way until none is open; the listing's sub_issues_summary
// answers for one with none open at no extra call. A run the gate stopped on
// an outside author or untrusted provenance, or an issue whose
// untrusted-provenance label someone unlisted removed, is never re-fired and
// gets no needs-human: on an outside author the lane's report-skip removes
// agent-ready and asks a listed human to re-file the work, and on the rest
// admission's refusal reaches a person.
//
// On `schedule`, and on `workflow_run` after a work-resolve-issue run
// finishes, it sweeps instead: every issue closed since the last
// successful scheduled run that ran its labeling step and read its closed
// listing began (less SWEEP_MARGIN_MIN, at most LOOKBACK_HOURS back; the full
// window when that cannot be shown) goes through the same rules, so an issue a
// bot closed (a pull request merge), which starts no close run, is still picked
// up. A swept close counts only when a listed human or a merge made it. A
// listing the sweep cannot read holds: a notice and a green exit, no read or
// write after a failed closed listing, and the next sweep's window stays back,
// so it reads the closes this one missed. A read for one issue that meets a
// GitHub fault holds that issue the same way: a notice, the rest of the sweep
// goes on, and the window stays back. A write that fails, or a read that fails
// for another reason, ends the run red, which keeps the window back too.
// Overlapping windows are harmless: an issue already labeled is left alone, and one whose
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
// is `turn-cap` or `retry` (report-outcome kept agent-ready, so a restart is
// left) is restarted the same way at once, while its markers of that outcome
// since a person last added agent-ready are within limits.turn-cap-restarts
// or limits.stop-retries. One whose newest marker is `wait` names the pull
// request it waits on (`pr=`): it waits while that pull request is open and
// is then restarted like a retry, its waits counted against
// limits.stop-retries apart from its retries. A funding stop (the lane's Claude capacity: a spend
// limit, no credit or a disabled key) is restarted like a limit stop, after
// its regain date or, with none, limits.fallback-reset hours after the stop.
// At most
// limits.restarts-per-run issues per run, longest-waiting first.
//
// Limit and funding stops past limits.limit-stops-per-issue since a person
// last added agent-ready spend that cap, a safety limit, so the issue takes
// the `fail` route of the issue lane's stop routes: the App posts
// an outcome=failed marker naming the stopped run, which maintenance-monitor
// signal 9 reports, and removes agent-ready, adding no label. It never gets
// needs-human. A newest failed marker with agent-ready still on (a removal
// that did not land) gets agent-ready removed.
//
// It re-fires the same way an open agent-ready issue whose newest
// work-resolve-issue run (the one its newest agent-ready label started, by a
// listed human or the App) did no work and left no lanes-App outcome marker since: a
// crash before the report, a run cancelled after check-admission passed and before any
// resolve-issue job started (pick-slot's timeout, a slot queue past GitHub's limit),
// or a run that stopped at the read runner's `Stop on stale workflow files`
// step in any of its calls (it waited in its slot past a lane workflow change, so no model ran)
// and whose report-outcome did not re-fire it at once (report-outcome.mjs
// refireStale: its mint refused, or limits.limit-stops-per-issue re-fires already).
// A run a newer agent-ready run replaced while it waited is never re-fired:
// check-admission never ran in it. A rerun keeps its first event's workflow files, so only a
// fresh label event runs on main's. Each issue is re-fired once per version
// of the two lane workflow files on main with a marker comment posted before
// the label moves, and after that on the stranded backoff, so a run that
// keeps failing is retried less often but never handed to a person.
//
// A run that minted no lane token did no work and ran no model: the WIP cap
// skipped its resolve-issue job, or its `Request the lane token` step failed
// (GitHub's rate limit past the retry budget among the reasons), or
// check-broker's `Ask the broker whether the lane may run` failed for any
// reason but the kill switch (a broker 5xx, a workflow-modified refusal of a
// rerun, a log that names no reason): the read runner resolve-issue calls has
// no `Request the lane token` step, so that is its failed mint, and a fresh
// label event runs on main's workflow files. Such a run is
// re-fired with the same record: a failed mint up to limits.limit-stops-per-issue
// times per version of the lane workflow files and then on the stranded
// backoff, a WIP cap skip without a per-issue bound. It waits limits.reset-clamp-min hours after the run ended, past any reset
// the broker passes on (its Retry-After is at most an hour), and only while
// the issue lane's WIP cap check (check-wip-cap.mjs) does not pause it. It is no
// limit stop, so it never counts toward failing the issue.
//
// So is a run whose check-admission, pick-slot, or a call's check-broker or run job
// failed on a GitHub API rate-limit stop, in a run where no model step ran
// (the read runner's `Run the skill on` legs and its reused-branch summary
// pass): the failed step's last line is rate-guard's or api-budget.bash's
// stop, a call that hit a pool's rate limit, left it at or under its
// stop-floor share, or got a server error with a Retry-After (a server error
// hold, its record named so), naming the reset. It is re-fired as a failed mint, under
// the same bound and backoff, once both that reset and limits.reset-clamp-min
// hours after the run ended have passed. A log that cannot be read leaves the
// run as before. Where a model step ran and every failed job ended on a rate
// limit, the run is a floor stop: a fresh start only from the reset R a job
// names to FLOOR_SPAN_MIN minutes after, and from each hour after R, a primary
// rate limit's window being an hour:
// https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
// With no R named, it re-fires from an hour after the run ended. It re-fires
// once per R, at most the lane's SLOTS per rolling hour, and takes the
// failed-again backoff after limits.limit-stops-per-issue of them. A job log
// that could not be read holds the run for the next sweep until an hour after
// the run ended; a log over LOG_CAP_BYTES never can be, so it does not hold.
//
// A run the token broker refused for the lanes kill switch, at check-broker's
// `Ask the broker whether the lane may run` or at a `Request the lane token`
// step, is a breaker trip, not a fault in the issue or the lanes; only the
// refused job's log names the reason (the jobs listing reads the same for a
// workflow-modified refusal). So is a run whose check-broker `Check the kill
// switch` step saw a kill switch on and skipped the broker ask, or whose check-admission
// or pick-slot job's own `Check the kill switch` did and the job ended green
// with its gated steps skipped (check-admission's `Install resolve-config's packages`
// and `Check the trigger`, pick-slot's `Check the WIP cap`; a failed install
// is a failed run, not the switch): that run ends green, and
// the jobs listing alone shows it; both count as trips at check-broker. A
// trip at check-broker ran no model, and the sweep runs only with the kill
// switch off, so the first sweep after the switch clears re-fires it; a trip at a mint ran the model and is
// re-fired limits.reset-clamp-min hours after the run ended. A run whose
// report-outcome mint alone stopped, after another mint took its token, is a
// trip at a mint too. Each gets a breaker record of its own, and after
// limits.limit-stops-per-issue trips since a listed human last added
// agent-ready or a run last reported, waits the kill-switch
// limits.stranded-backoff-hours after the run ended, flat, never doubled,
// with no cap on trips and no fail route. A run whose start gate stopped it
// on the GITHUB_TOKEN budget (BUDGET_STEP green in a call's check-broker,
// from the jobs listing) is a breaker trip at check-broker whose record
// carries BUDGET_TAG: it never counts toward that bound or that wait, and
// re-fires only from the window reset its step names to FLOOR_SPAN_MIN minutes
// after, and from each hour after that reset:
// https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
// A sweep re-fires breaker trips,
// oldest run end first, only while the work-resolve-issue runs not yet
// finished (five status listings, read once a sweep that has one) are under
// limits.refire-queue-per-slot times the lane's SLOTS, within
// limits.restarts-per-run, so after a clear the lane stays full with a short
// queue that each finished run's sweep tops up. A budget stop's re-fire also
// waits until those runs are under limits.refire-budget-per-slot times SLOTS:
// a run queued behind a second one per slot started past the window and the
// start gate stopped it again. A run still `queued`
// limits.stale-queued-minutes after it was created is not counted: its first
// job never got a runner, so it is a run GitHub lost and will never start,
// and counting it would hold the room at 0 for good. For the same reason a
// reopened fix issue's in-flight check does not count such a run among the
// runs that name no issue, though one that names the issue still holds it. A breaker
// record never spends the once-per-version re-fire, never counts toward the
// failed-mint bound and never raises another cause's backoff. Each run's log
// is read once, from its one refused job (or its one failed job before any
// model turn) and at most LOG_CAP_BYTES, and only its failed step's last line
// counts: a refusal for another reason, or a log that cannot be read, is a
// failed mint.
//
// A run check-admission's upstream-status stop skipped (check-upstream-status: Actions
// or npm installs listed an outage) ran no model either. Once the status pages
// read clear the sweep re-fires it with no wait, paced with the breaker trips
// by limits.refire-queue-per-slot; while they list an outage or cannot be
// read, it waits limits.reset-clamp-min hours after the run ended, as a run
// the blocker gate skipped does, and that wait is not carried to the next
// sweep. The pages are read once a sweep, and only when such a run is decided.
//
// When that label's run opened a pull request instead, the newest one the
// lanes App opened from the issue's lane branch in this repository decides.
// Merged with `Refs:` (the issue stays open with nothing to run) or closed
// unmerged, the App removes `status: ready` and agent-ready, so the triage
// sweep (maintenance-audit-lane-runs triage-sweep.mjs) dispatches intake,
// which decides what is left and whose fresh `status: ready` re-admits it;
// after a merge, admission parks it for a done-check instead (admit.mjs
// mergedRefsAfter) until a decision comment says what is left. Open, it waits: report-outcome put needs-human on the
// issue of a Refs PR, and this lifts that hold once that PR merges or closes
// unmerged, only while its refs-hold marker and the App's needs-human label
// are the newest. Each hand-off also counts against limits.restarts-per-run.
// A lane PR the pr-merge lane closed at the verify cap, which its
// capped-close record on the issue names with an attempt, is no hand-off:
// that lane already restarted the issue for a fresh attempt or parked it.
// The issues this path reads carry agent-ready.
//
// It relabels a red-main fix issue post-merge-file-demotion-issues.yml reopened on
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
// open parent closed that way as completed with its done-when covered
// (admit.mjs splitLeftOpen), the App comments on the parent and closes it as
// completed. Only a split parent counts (admit.mjs isSplitParent): one whose
// split record the App posted, or one split by hand whose every sub-issue the
// App or a listed human linked, not `recurring`, each open task-list item in
// its body being one of those sub-issues: its `#N` alone or with that
// sub-issue's title. A parent that stays open gets no comment here: admission
// says why, in its one comment (readmitReady). One that admission parked on
// SIZE_SPLIT_DONE, every sub-issue now closed as completed by a trusted close,
// loses status: confirmed instead, so intake admits it for the issue lane's
// one verified-done run (reenterFinished, #12456 class A).
//
// The App's admission comment on an open parent in no queue that waits on its
// sub-issues alone (no blocker) is rewritten when it says only that the split
// is pending or that sub-issues are open and its open sub-issues now differ
// (refreshSplitWait): on each sub-issue close above, and on the sweep for the
// open-sub-issue parents whose number is the UTC hour modulo 24.
//
// The sweep also rescans open parents whose sub_issues_summary shows every
// sub-issue completed and whose number is the UTC hour modulo 24, at most
// limits.parent-rescan-per-run of them, oldest updated first
// (rescanSplitParents), with the same rules: a parent whose last sub-issue
// closed outside the sweep window still closes, and one that stays open logs
// why.
//
// Every pass leaves out a map issue and each of its items: an issue whose own
// labels hold the tracker binding's container label or a label starting with
// its wayfind prefix (check-born-triaged.mjs routingLabel, read from BASE_PATH's
// docs/conventions/work-items.yaml). The skill that filed it routes it, so no
// pass reads, judges, admits, re-fires or comments on it past the listing or
// parent lookup that named it, and the queued cap does not count it
// (check-wip-cap.mjs). One notice per run names each one left out; one that
// loses the label is decided on the next pass.
//
// Environment:
//   GH_TOKEN              the lane App token (issues: write)
//   GITHUB_REPOSITORY      owner/repo
//   GITHUB_EVENT_NAME      `issues` (a close), or `schedule`,
//                          `workflow_dispatch` or `workflow_run` (a finished
//                          work-resolve-issue run) for the sweep
//   GITHUB_EVENT_PATH      the event payload; on `issues` only its action,
//                          sender and issue number are read; on a sweep
//                          event it is not read
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
//   VERDICTS_IN            a sweep's carried job listings and log verdicts
//                          (verdict-carry.mjs read); missing carries nothing
//   VERDICTS_OUT           where a sweep keeps them for the next one, and
//                          sets the `verdicts=true` output; unset keeps
//                          and carries nothing
//   LANES_BOT_LOGIN        the lanes App bot login, the only author of a marker
//                          and actor of a restart this trusts (default
//                          melodic-automation-lanes[bot])
//   GITHUB_API_URL
//   RESOLVED_CONFIG        resolve-config's output (default
//                          $RUNNER_TEMP/resolved-config.json), for the limits
//   BASE_PATH              the default branch checkout (default .base), for
//                          the admission rules, models.issue-dimensions and
//                          the tracker binding's routing labels
import { appendFileSync, readFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { notBornTriaged, readRouting, ROUTED_BY, routingLabel } from "../../actions/check-born-triaged/check-born-triaged.mjs";
import { checkUpstreamStatus } from "../../actions/check-upstream-status/check-upstream-status.mjs";
import { createGitHub, graphqlQuery, isFault, paginate } from "../lib/github-client.mjs";
import { isTrustedClose as closedByHumanOrMerge, loadTrustedList, readRerunner } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { admissionLine, checkWip, listedStatusOf, searchRateLimit } from "../../actions/check-wip-cap/check-wip-cap.mjs";
import { clampReset, isLaneBranch, LANE_HOLDS, LANE_WORKFLOWS, parseOutcomeMarker, REFIRED, refireComment as refireRecord, refsHoldMarker, stripStateLabels } from "../work-resolve-issue/report-outcome.mjs";
import { readLimits, readWip, resolveStrandedBackoff, STRANDED_BACKOFF_MAX } from "../work-resolve-issue/limits.mjs";
import { ADMIT_MARKER, admissionFacts, admissionParked, admissionSettled, ATTENDED, authorTrust, attendedHold, BODY_EDITED, blockerDone, blockersOf, bodyVersion, clearedPastReport, CONFIRMED, confirmedOnly, decide, deferralLapsed, doneReason, humanPullsFor, judgedSince, loadRules, mergedRefsReader, NEEDS_DECISION, openPullsFor, openSubIssues, READY, refusalText, removalStands, retriageNote, sayWhy, SECURITY_AREA, SIZE_SPLIT_DONE, SPLIT_PENDING, specOf, stillBlocking, subIssueWait, UNTRUSTED, untrustedHold } from "../intake-triage/admit.mjs";
import { splitLeftOpen, splitParentClosed } from "../intake-triage/size-split.mjs";
import { LANES_APP_LOGIN as DEFAULT_BOT } from "../lib/lane-vocabulary.mjs";
import { parseReason, personReasonLines } from "../lib/stop-reason.mjs";
import { markLaneHold } from "../lib/lane-hold-marker.mjs";
import { describeLevel, laneLevelFromEnv, resolvedLaneLevel } from "../lib/lane-level-value.mjs";
import { subIssueLeftOpen } from "../lib/done-evidence.mjs";
import { budgetLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { createJobLogReader } from "./job-log.mjs";
import { loadCarry, markSaved } from "./verdict-carry.mjs";
import { FIELD_API, statusWriter } from "../../actions/resolve-config/write-status.mjs";
import { writeAdmissionRecord } from "../lib/admission-record.mjs";
import { isStatusLabel, HOLD_STATES, loadTrustedActors, readyWhileDeferred, StatusReadError, statusLabels, statusReader } from "../../actions/resolve-config/read-status.mjs";

const LABEL = "agent-ready";
const HUMAN_LABEL = "needs-human";
const DEFERRED_LABEL = "admission-deferred";
const FAILED = new Set(["failure", "timed_out", "startup_failure"]);
// A label event's run is created within seconds; this window finds it.
const RUN_WINDOW_MS = 10 * 60_000;
const BLOB = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,14}$/;
const HOUR_MS = 3_600_000;
const MINT_STEP = "Request the lane token";
const STALE_STEP = "Stop on stale workflow files";
const RESOLVE_CALLS = ["resolve-issue", "resolve-issue-subscription", "resolve-issue-fallback"];
const ADMIT = ["admit", "check-admission"];
const BLOCKER_STEP = "Wait for open blockers";
const UPSTREAM_STEP = "Check upstream status";
const RECHECK_STOP_STEP = "Stop on an open blocker";
const UNTRUSTED_STEP = "Stop on untrusted provenance";
const BROKER_STEP = "Ask the broker whether the lane may run";
const KILL_STEP = "Check the kill switch";
// check-broker's step that runs exactly when KILL_STEP stopped on the
// GITHUB_TOKEN budget (cause budget). Its name carries the window's reset,
// in epoch seconds, from the gate's reset output.
const BUDGET_STEP = /^Stop on a low GITHUB_TOKEN budget(?: until (.*))?$/;
// The second line of a breaker record whose stop was a budget stop.
const BUDGET_TAG = "<!-- work-unblock cause=budget -->";
// The budget record's last line: when each of its earlier edits was made, so
// every budget re-fire keeps its date once the record is edited again.
const BUDGET_EARLIER = /^<!-- work-unblock earlier ([^>]*) -->$/m;
const budgetEarlier = (body) => (BUDGET_EARLIER.exec(String(body ?? ""))?.[1] ?? "").split(" ").filter(Boolean);
const floorTag = (reset) => `<!-- work-unblock cause=floor reset=${isoSecond(reset)} -->`;
const FLOOR_TAG = /^<!-- work-unblock cause=floor reset=(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) -->$/;
const FLOOR_SPAN_MIN = 20;
const FLOOR_SPAN_MS = FLOOR_SPAN_MIN * 60_000;
const INSTALL_STEP = "Install resolve-config's packages";
const TRIGGER_STEP = "Check the trigger";
const WIP_STEP = "Check the WIP cap";
const MODEL_STEP = /^(?:Run the skill on|Summarize the reused branch on) /;
// A raw job log line, its timestamp first, whose rest matches the pattern `rest`.
const stamped = (rest) => new RegExp(String.raw`^\d{4}-\d\d-\d\dT[\d:.]+Z ` + rest);
// request-lane-token's last line when the broker refuses it, in check mode
// (BROKER_STEP) or token mode (MINT_STEP), and the runner's line that follows
// it when the step fails. Only the reason word is read.
const denial = (mode) => stamped(String.raw`##\[error\]lane-${mode}-denied: the broker answered 403 with reason ([a-z]+(?:-[a-z]+)*)(?::|$)`);
const DENIAL = { check: denial("check"), token: denial("token") };
const STEP_FAILED = stamped(String.raw`##\[error\]Process completed with exit code [0-9]+\.$`);
// rate-guard's (and api-budget.bash's) stop line, as the failed step's last
// line: a call that hit a pool's rate limit, left it at or under its
// stop-floor share, or got a server error with a Retry-After (rate-guard's
// serverErrorHold, held the same way, its 5xx in `status`), and the `reset` it
// names. A raw job log shows a titled annotation as `##[error]<message>`,
// the title dropped, as it shows an untitled one.
export const RATE_LIMITED = stamped(
  String.raw`##\[error\].* (?:hit GitHub's .+ rate limit|left GitHub's .+ requests, at or under its stop-floor share \S+|got a GitHub server error, HTTP (?<status>5\d\d) with a Retry-After)(?: \(status \d+\))?: no call to it before (?<reset>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) \(`,
);
const ERROR_LINE = stamped(String.raw`##\[error\]`);
const STEP_EDGE = stamped(String.raw`##\[(?:group\]Run |start-action |end-action )`);
export const HELD_UNTIL = stamped(
  String.raw`##\[error\].* was not sent: GitHub(?:'s .+ rate limit holds until| answered HTTP (?<status>5\d\d) with a Retry-After; no call to it before) (?<reset>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)(?: \(.*\))?$`,
);
const RAW_LIMIT = stamped(String.raw`##\[error\]Unhandled error: HttpError: API rate limit exceeded\b`);
const LIMIT_COMPANION = stamped(
  String.raw`##\[error\](?:\S+ \S+ failed with status 403$|handoff evidence for \S+ still missing after [0-9]+ reads: the jobs read failed(?:: GitHub.*)?$|leak-scan: no finished scan \(HttpError\);)`,
);
const FLOOR_JOB_ENDS = new Set(["success", "skipped", "failure"]);
const NO_RESET = "rate-limited";
const LOG_UNREAD = "unread";
const OVER_CAP = /answered a body over \d+ bytes$/;
const STAGE_STEP = "Stage the activity from the base";
// request-lane-token's notice when kill-switch-ok ends a kill-switch refusal
// green with no token, at a mint or at check-broker's check.
const STOPPED = stamped(
  String.raw`##\[notice\]lane-(?:token-stopped: the broker refused the token|check-stopped: the broker refused the check) because a lanes kill switch is on(?:,|$)`,
);
const LEASE_STEP = "Claim the issue with a lane lease";
// The runner's markers around request-lane-token's one composite step, its
// `Request the lane token` with id `request`; a STOPPED line counts only
// between the job's first start marker and its end marker.
const MINT_START = stamped(String.raw`##\[start-action display=Request the lane token;id=([\w-]+\.request)\]$`);
const mintEnd = (id) => stamped(String.raw`##\[end-action id=${id.replace(".", "\\.")};`);
const BREAKER = "kill-switch";
// The refused jobs' logs on 2026-10-24 were 45 KB (check-broker) and 94 KB
// (apply-issue-patch); a longer one is left unread.
const LOG_CAP_BYTES = 1_048_576;
// The line a sweep prints once it has read the closed-issue listing, and that
// line in a raw job log, stamp first. A held sweep ends as green as a full one,
// so this line alone lets the next sweep's window start from it.
const LISTED_LINE = "label-unblocked: read the closed-issue listing";
const LISTED = stamped(`${LISTED_LINE}$`);
// The line a run prints when it held an issue on a faulted read (failedFor),
// and that line in a raw job log. The next sweep's window stays back past it.
const HELD_LINE = "label-unblocked: held an issue on a failed read";
const HELD = stamped(`${HELD_LINE}$`);
// work-unblock.yml's job and its step that runs this script. The kill switch
// and a lane the config turns off skip the step and leave the run green, so
// only this step's success shows a sweep ran.
const SWEEP_JOB = "label-unblocked";
const SWEEP_STEP = "Label the unblocked issues";
const handedMarker = (pr) => `<!-- work-unblock handed triage #${pr} -->`;
// The pr-merge lane's capped-close record on the issue
// (babysit_verify_evidence.py CAPPED_CLOSE_RE) naming an attempt: it closed
// the lane PR it names at the verify cap and restarted or parked the issue
// itself. One with no attempt started nothing.
const CAPPED_CLOSE = /^<!-- verify-capped-close pr=([1-9][0-9]{0,9}) heads=[0-9a-f,]* attempt=[0-9]+ of=[0-9]+(?: parked)? -->/;
const HOLDS = LANE_HOLDS;
const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
// post-merge-file-demotion-issues.yml's fix issue and the comment it posts when it
// reopens one, both under that workflow's GITHUB_TOKEN.
const ALERT_BOT = "github-actions[bot]";
const FIX_ISSUE = /^<!-- post-merge-fix check=[^\r\n]+ -->/;
export const RECURRENCE_PREFIX = "This check failed on main again at `";
const RELABELED = /^<!-- work-unblock recurrence ([1-9][0-9]{0,15}) -->/;
// A work-resolve-issue run in any of these has not finished.
export const IN_FLIGHT = Object.freeze(["queued", "in_progress", "waiting", "pending", "requested"]);
// The sweep's widest window, used when the last good sweep is unknown or
// older: a missed run loses nothing up to this far back.
export const LOOKBACK_HOURS = 3;
// The sweep reads from this long before the last good sweep started.
export const SWEEP_MARGIN_MIN = 15;
// work-unblock.yml's step a scheduled run the burn-rate pacer paced runs
// (log-api-budget/pace.mjs), and how far back the sweep after it may read:
// it starts from the sweep before the paced run, which a dropped or late
// tick can push past LOOKBACK_HOURS.
export const PACED_STEP = "Mark this tick paced";
export const PACED_LOOKBACK_HOURS = 2 * LOOKBACK_HOURS;
// Minutes from the script's start after which a sweep decides no further
// agent-ready issue, when SWEEP_BUDGET_MINUTES (work-unblock.yml) names none.
export const SWEEP_BUDGET_MIN = 6;
const sweepBudgetMs = (env) => {
  const minutes = Number(env.SWEEP_BUDGET_MINUTES);
  return (Number.isFinite(minutes) && minutes > 0 ? minutes : SWEEP_BUDGET_MIN) * 60_000;
};
const INFRA = /^<!-- work-unblock infrastructure ([0-9a-f]{40}-[0-9a-f]{40}) -->/;
// The longest wait between backoff re-fires.
export const BACKOFF_CAP_HOURS = STRANDED_BACKOFF_MAX;
const backoffDue = (since, refires, hours) => since + Math.min(hours * 2 ** refires, BACKOFF_CAP_HOURS) * HOUR_MS;
const spanOpens = (reset, now) => {
  if (now < reset) {
    return reset;
  }
  const opened = reset + Math.floor((now - reset) / HOUR_MS) * HOUR_MS;
  return now < opened + FLOOR_SPAN_MS ? opened : opened + HOUR_MS;
};
const isoSecond = (at) => new Date(at).toISOString().replace(/\.\d{3}Z$/, "Z");
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
const reportHold = (what, error) => {
  console.log(`::notice title=label-unblocked::the ${what} listing failed (${escapeCommand(error?.message ?? error)}); holding, and the next sweep reads it again`);
  markLaneHold();
};
const READ_FAULT = Symbol("a read met a GitHub fault");
function markReads(client) {
  const marked = async (method, apiPath, body, ...rest) => {
    try {
      return await client(method, apiPath, body, ...rest);
    } catch (error) {
      const read = method === "GET" || (method === "POST" && graphqlQuery(apiPath, { body: JSON.stringify(body) }));
      if (read && isFault(error)) {
        error[READ_FAULT] = true;
      }
      throw error;
    }
  };
  marked.held = 0;
  return marked;
}
function failedFor(github, number, error) {
  if (error instanceof StatusReadError) {
    console.log(`::warning title=label-unblocked::#${number}: ${escapeCommand(error.message)}; not admitted or lifted this run`);
    github.held += 1;
    return 0;
  }
  if (error?.[READ_FAULT]) {
    console.log(`::notice title=label-unblocked::#${number}: ${escapeCommand(error.message)}; holding, and the next sweep reads it again`);
    markLaneHold();
    github.held += 1;
    return 0;
  }
  reportError(number, error);
  return 1;
}

const isLabel = (event, kind) => event.event === kind && String(event.label?.name).toLowerCase() === LABEL;

const parseMarker = (body) => {
  const refire = REFIRED.exec(String(body ?? "")) ?? INFRA.exec(String(body ?? ""));
  if (!refire) {
    return parseOutcomeMarker(body);
  }
  const breaker = refire[2] !== undefined;
  const tag = breaker ? String(body).split("\n")[1] : undefined;
  const floor = FLOOR_TAG.exec(tag ?? "")?.[1];
  return { outcome: "refired", key: refire[1], breaker, budget: tag === BUDGET_TAG, ...(floor && { floor: Date.parse(floor) }) };
};

const appMarkers = (comments, bot) =>
  comments
    .filter((comment) => comment.user?.login === bot)
    .flatMap((comment) => {
      const marker = parseMarker(comment.body);
      const edited = marker?.budget || INFRA.test(String(comment.body ?? ""));
      const at = Date.parse(edited ? (comment.updated_at ?? comment.created_at) : comment.created_at);
      return [...(marker?.budget ? budgetEarlier(comment.body) : []).map(Date.parse), at].map((when) => ({ ...marker, at: when }));
    })
    .filter((marker) => marker.outcome !== undefined && Number.isFinite(marker.at))
    .sort((a, b) => a.at - b.at);

const RESTARTS = new Set(["limited", "refired", "turn-cap", "funding", "retry", "wait"]);

const CAPPED_RESTARTS = { "turn-cap": "turn-cap-restarts", retry: "stop-retries", wait: "stop-retries" };

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

const trustedLabeler = (event, { bot, humans }) => event?.actor?.login === bot || humans.has(event?.actor?.id);

const newestAdd = (events, name) =>
  events.filter((event) => event.event === "labeled" && String(event.label?.name).toLowerCase() === name.toLowerCase()).at(-1);

const untrustedReady = (events, { bot, humans }) =>
  trustedLabeler(newestAdd(events, READY), { bot, humans }) ? null : `${READY} was added by neither a listed human nor the lanes App`;

const parkedBesideReady = (lower) => lower.includes(CONFIRMED) && lower.includes(READY);

async function fieldFirst(statusOf, number, own) {
  const lower = statusOf ? (await statusOf(number, own)).map((name) => String(name).toLowerCase()) : own;
  return readyWhileDeferred(lower, own, async () => (await statusOf?.state?.(number)) === "deferred");
}

function deferralMark(events, { bot, humans }) {
  const changes = events.filter((event) => ["labeled", "unlabeled"].includes(event.event) && String(event.label?.name).toLowerCase() === DEFERRED_LABEL);
  const newest = changes.at(-1);
  const before = changes.at(-2);
  const echo = newest?.event === "labeled" && newest.id === null && newest.actor?.login === bot && before?.event === "labeled" && before.id !== null && humans.has(before.actor?.id);
  return echo ? before : newestAdd(events, DEFERRED_LABEL);
}

const eventsOf = (github, repo, statusOf, number) =>
  statusOf?.events ? statusOf.events(number) : paginate(github, `/repos/${repo}/issues/${number}/events`);

// The Work status field's moves onto and off agent-ready (resolve-config.mjs
// fieldEvents rows for field `field`) as `labeled` and `unlabeled` agent-ready
// events, so the restart rules read a field restart as they read a label one.
// Only the lanes App's (`bot`) and a listed human's (`humans`, a User's id)
// count. Pure.
export function agentReadyEvents(rows, { field, bot, humans }) {
  return rows.flatMap((row) => {
    const app = row.actorType === "Bot" && `${row.actorLogin}[bot]` === bot;
    const person = row.actorType === "User" && humans.has(row.actorId);
    const on = row.to === LABEL;
    if (String(row.field) !== String(field) || (!app && !person) || on === (row.from === LABEL)) {
      return [];
    }
    const actor = { id: row.actorId, login: app ? bot : row.actorLogin, type: row.actorType };
    return [{ id: null, event: on ? "labeled" : "unlabeled", label: { name: LABEL }, actor, created_at: row.at }];
  });
}

const mergeByTime = (events, extra) =>
  [...events.map((event) => [0, event]), ...extra.map((event) => [1, event])]
    .sort(([a, x], [b, y]) => Date.parse(x.created_at) - Date.parse(y.created_at) || a - b)
    .map(([, event]) => event);

async function refusal(args) {
  const base = `/repos/${args.repo}/issues/${args.number}`;
  const current = await args.github("GET", base);
  const own = labelNames(current).map((name) => name.toLowerCase());
  const lower = await fieldFirst(args.statusOf, args.number, own);
  const open = current.state === "open";
  const held = lower.find((label) => HOLDS.has(label));
  const lapsed =
    open && !held && lower.includes(DEFERRED_LABEL) && !lower.includes(LABEL)
      ? deferralLapsed({
          labels: lower,
          events: args.events ?? (await eventsOf(args.github, args.repo, args.statusOf, args.number)),
          editedAt: (await specOf(args.github, args.repo, args.number)).lastEditedAt,
          humans: args.humans,
          appId: args.appId,
        })
      : [];
  const kept = lapsed.some(({ kind }) => kind === "held");
  const notReady = lapsed.some(({ kind }) => kind === "not-ready");
  const reason = !open ? "not open" : held ? `held by ${held}` : lapsed.length > 0 ? lapsed.map((item) => item.reason).join("; ") : await readiness({ ...args, base, lower, current });
  const stale = kept || notReady ? [] : lapsed;
  return { reason, held: open && Boolean(held), kept, stale, notReady, deferred: lower.includes(DEFERRED_LABEL), confirmed: parkedBesideReady(lower), current, lower };
}

async function readiness({ github, repo, number, humans, closes, bot = DEFAULT_BOT, base, lower, current, statusOf }) {
  if (lower.includes(LABEL)) {
    return `already ${LABEL}`;
  }
  const events = await eventsOf(github, repo, statusOf, number);
  const unset = lower.includes(READY) ? untrustedReady(events, { bot, humans }) : null;
  if (unset) {
    return unset;
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
    clearedHere({ github, repo, humans, closes, bot, events }),
    closedElsewhere({ github, repo, humans, closes }),
  );
  if (pending.length > 0) {
    return `${pending.length} blocker(s) not closed by a listed human or a merge`;
  }
  const subs = await openSubIssues(github, base, current);
  if (subs.length > 0) {
    return `an umbrella waiting on open ${subs.map((sub) => `sub-issue #${sub.number}`).join(", ")}`;
  }
  const comments = await paginate(github, `${base}/comments`);
  const markers = appMarkers(comments, bot);
  const stopped = (event, index) => isLabel(event, "unlabeled") && !isRestart(events, index, markers, bot);
  if (removalStands(events, stopped, (event) => trustedLabeler(event, { bot, humans }))) {
    return `${LABEL} was removed and ${READY} not added since`;
  }
  const unparked = (event) => event.event === "unlabeled" && String(event.label?.name).toLowerCase() === CONFIRMED && event.actor?.login === bot;
  const reMark = (event) => event?.event === "labeled" && [READY, CONFIRMED].includes(String(event.label?.name).toLowerCase());
  if (!lower.includes(READY) && removalStands(events, unparked, (event) => trustedLabeler(event, { bot, humans }), reMark)) {
    return `${CONFIRMED} was removed for intake and ${READY} not added since`;
  }
  return null;
}

async function sweepSince({ actions, jobLog, repo, now, runId }) {
  let widest = now - LOOKBACK_HOURS * HOUR_MS;
  const fullest = now - PACED_LOOKBACK_HOURS * HOUR_MS;
  if (!actions) {
    return { since: widest, why: "no Actions token to read the last sweep" };
  }
  let after = "";
  try {
    const path = `/repos/${repo}/actions/workflows/work-unblock.yml/runs?event=schedule&status=success&per_page=3`;
    const runs = (await actions("GET", path))?.workflow_runs;
    if (!Array.isArray(runs)) {
      throw new Error("the workflow run listing has an unexpected shape");
    }
    // Newest first by id, which grows with each run; created_at can be
    // stamped out of order (rotation.mjs runOrder).
    const order = (run) => (RUN_ID.test(String(run?.id)) ? Number(run.id) : -1);
    const older = runs.filter((run) => String(run?.id) !== String(runId ?? "")).sort((a, b) => order(b) - order(a));
    const listJobs = jobLister(actions, repo);
    let last = older[0];
    if (last && RUN_ID.test(String(last.id)) && !(Date.parse(last.run_started_at ?? last.created_at) <= now - PACED_LOOKBACK_HOURS * HOUR_MS)) {
      const paced = namedJobs(await listJobs(last), SWEEP_JOB).some((job) => (job?.steps ?? []).some((step) => step?.name === PACED_STEP && step.conclusion === "success"));
      if (paced) {
        widest = now - PACED_LOOKBACK_HOURS * HOUR_MS;
        after = ` (run ${last.id} was paced)`;
        last = older[1];
      }
    }
    const started = Date.parse(last?.run_started_at ?? last?.created_at);
    if (!Number.isFinite(started) || started > now) {
      return { since: widest, why: `no earlier successful sweep was found${after}` };
    }
    const at = new Date(started).toISOString();
    const from = started - SWEEP_MARGIN_MIN * 60_000;
    if (from <= widest) {
      return { since: widest, why: `the last successful run started ${at}, past the widest window${after}` };
    }
    if (!RUN_ID.test(String(last.id))) {
      throw new Error("the last successful run has no usable id");
    }
    const jobs = await listJobs(last);
    const swept = namedJobs(jobs, SWEEP_JOB).find((job) =>
      (job?.steps ?? []).some((step) => step?.name === SWEEP_STEP && step.conclusion === "success"),
    );
    if (!swept) {
      return { since: fullest, why: `the last successful run, started ${at}, shows no completed \`${SWEEP_STEP}\` step${after}` };
    }
    if (!RUN_ID.test(String(swept.id))) {
      throw new Error("the last sweep's job has no usable id");
    }
    const log = await jobLog(repo, swept.id, { maxBytes: LOG_CAP_BYTES });
    const lines = String(log ?? "").split("\n");
    return lines.some((line) => LISTED.test(line)) && !lines.some((line) => HELD.test(line))
      ? { since: from, why: `the last sweep started ${at}${after}` }
      : { since: fullest, why: `the last sweep, started ${at}, held or shows no read of its listing${after}` };
  } catch (error) {
    return { since: fullest, why: `the last sweep could not be read (${escapeCommand(error?.message ?? error)})${after}` };
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

function trustedClose(args) {
  return readClose(args).then(({ trusted }) => trusted);
}

function readClose({ github, repo, where = repo, number, humans, closes, bot = DEFAULT_BOT }) {
  const key = `${where.toLowerCase()}#${number}`;
  if (!closes.has(key)) {
    closes.set(
      key,
      (async () => {
        const issue = await github("GET", `/repos/${where}/issues/${number}`);
        const trusted = await (where.toLowerCase() === repo.toLowerCase() ? isTrustedClose(github, repo, issue, humans, bot) : humans.has(issue?.closed_by?.id));
        return { issue, trusted };
      })(),
    );
  }
  return closes.get(key);
}

const byBot = (bot) => (actor) => actor?.login === bot;

const clearedHere = ({ github, repo, humans, closes, bot = DEFAULT_BOT, events }) =>
  clearedPastReport({
    github,
    repository: repo,
    isApp: byBot(bot),
    trusted: (number) => trustedClose({ github, repo, number, humans, closes, bot }),
    after: judgedSince(events, (actor) => trustedLabeler({ actor }, { bot, humans })),
  });

const closedElsewhere = (args) => (blocker) => {
  const where = /\/repos\/([\w.-]+\/[\w.-]+)$/.exec(String(blocker.repository_url ?? ""))?.[1];
  return where ? trustedClose({ ...args, where, number: Number(blocker.number) }).catch(() => false) : false;
};

function admissionGate(status) {
  let room;
  let reason;
  let pause;
  return {
    why: () =>
      pause
        ? `the issue lane is paused (${pause})`
        : reason === "search-incomplete"
          ? "GitHub search answered incomplete results"
          : reason === "fail-open"
            ? "the issue lane's queued count could not be read"
            : "queued work is at the queued cap",
    take: async () => {
      if (room === undefined) {
        const s = await status();
        pause = s.paused ? s.pause_reason : null;
        const unread = s.admission_basis === "fail-open";
        room = pause || unread ? 0 : (s.admission_room ?? Number.POSITIVE_INFINITY);
        reason = unread ? "fail-open" : s.admission_reason;
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

async function admit({ github, repo, number, gate, deferred, appId, writer = NO_WRITER }) {
  if (!(await gate.take())) {
    if (!deferred && (await heldOnSet(writer, number, "deferred"))) {
      return;
    }
    console.log(`label-unblocked: #${number} admission deferred: ${gate.why()}`);
    return;
  }
  const issue = await github("GET", `/repos/${repo}/issues/${number}`);
  await writeAdmissionRecord(github, repo, number, { actorId: appId, title: issue?.title, body: issue?.body ?? "" });
  if ((await writer.set(number, "agent-ready", { keepHold: true }))?.outcome === "held") {
    console.log(`label-unblocked: #${number} held by a person, not admitted`);
    return;
  }
  console.log(`label-unblocked: #${number} set to ${LABEL}`);
}

async function parkDone({ github, repo, number, pulls, writer = NO_WRITER }) {
  const base = `/repos/${repo}/issues/${number}`;
  await sayWhy(github, repo, base, await paginate(github, `${base}/comments`), refusalText(doneReason(pulls)));
  if (await heldOnSet(writer, number, "confirmed")) {
    return;
  }
  console.log(`label-unblocked: #${number} parked for a done-check: merged Refs pull request ${pulls.map((n) => `#${n}`).join(", ")}`);
}

async function staysParked({ github, repo, issue, lower, humans, appId, admission, statusOf }) {
  const base = `/repos/${repo}/issues/${issue.number}`;
  const { rules } = await admission();
  if (rules["cordoned-milestones"].includes(issue.milestone?.title)) {
    return { why: `its milestone ${issue.milestone.title} is cordoned` };
  }
  if ((await authorTrust(github, repo, issue, humans, appId)) === null) {
    return { why: "intake does not admit its author" };
  }
  const refused = rules["refuse-labels"].find((label) => lower.includes(label.toLowerCase()));
  if (refused) {
    return { why: `${refused} refuses it` };
  }
  const comments = await paginate(github, `${base}/comments`);
  if (!admissionParked(lower, comments, appId)) {
    return { why: "admission did not park it" };
  }
  const parkedAt = Date.parse(newestAdd(await eventsOf(github, repo, statusOf, issue.number), CONFIRMED)?.created_at);
  const closedAt = Math.max(...(await blockersOf(github, base)).map((blocker) => Date.parse(blocker.closed_at)).filter(Number.isFinite));
  return parkedAt < closedAt ? { why: null, parkedAt, comments } : { why: "no blocker closed since it parked" };
}

// The lanes App's hand-back to intake of a parked issue, its comment's first
// line, which the hourly triage sweep (triage-sweep.mjs HAND_BACK) reads to
// send it to intake.
export const UNPARKED_MARKER = "<!-- work-unblock unparked triage -->";

async function handBackParked({ github, repo, number, comments, parkedAt, isApp, writer, why }) {
  const base = `/repos/${repo}/issues/${number}`;
  const marked = comments.some(
    (comment) => isApp(comment.user) && String(comment.body ?? "").startsWith(UNPARKED_MARKER) && Number.isFinite(parkedAt) && Date.parse(comment.created_at) > parkedAt,
  );
  if (!marked) {
    await github("POST", `${base}/comments`, { body: `${UNPARKED_MARKER}\n${why} so work-unblock set its Work status to needs-triage, and the hourly triage sweep sends it back to intake triage.` });
  }
  return heldOnSet(writer, number, "needs-triage");
}

// The hand-back a refusal decide marks `triage` posts before its needs-triage
// write, apart from the admission comment refine's splitOf matches: the
// UNPARKED_MARKER line, so the triage sweep starts a new dispatch cycle for
// it, then the body's version (admit.mjs bodyVersion, the key refine's own
// once-per-body guard reads), so the same body is handed back once. Pure.
export const splitHandBack = (body) =>
  `${UNPARKED_MARKER}\n${bodyVersion(body)}\nAdmission refused this issue only for done-when items a lane run cannot perform beside items it can, which intake's refine step splits off only in an intake run, so work-unblock set its Work status to needs-triage, and the hourly triage sweep sends it back to intake triage.`;

async function handBackSplit({ github, repo, issue, comments, appId }) {
  const text = splitHandBack(issue.body ?? "");
  if (!comments.some((comment) => appId !== undefined && comment.user?.id === appId && String(comment.body ?? "") === text)) {
    await github("POST", `/repos/${repo}/issues/${issue.number}/comments`, { body: text });
  }
}

async function unpark({ github, repo, parked, humans, appId, admission, writer = NO_WRITER, statusOf }) {
  const going = [];
  let failed = 0;
  for (const { issue, lower } of parked) {
    try {
      const { why, parkedAt, comments } = await staysParked({ github, repo, issue, lower, humans, appId, admission, statusOf });
      if (why) {
        console.log(`label-unblocked: #${issue.number} stays at ${CONFIRMED}: ${why}`);
      } else {
        going.push({ issue, parkedAt, comments });
      }
    } catch (error) {
      failed += failedFor(github, issue.number, error);
    }
  }
  console.log(`label-unblocked: ${going.length} of ${parked.length} parked issue(s) go back to intake`);
  for (const { issue, parkedAt, comments } of going) {
    const number = Number(issue.number);
    try {
      if (!(await handBackParked({ github, repo, number, comments, parkedAt, isApp: (user) => user?.id === appId, writer, why: `A blocker of this issue closed after admission parked it at \`${CONFIRMED}\`,` }))) {
        console.log(`label-unblocked: #${number} set to needs-triage; the triage sweep sends it to intake`);
      }
    } catch (error) {
      failed += failedFor(github, number, error);
    }
  }
  return failed;
}

const namesIssue = (body, number) => new RegExp(String.raw`(?:^|[^\w/#])#${number}(?!\d)`).test(String(body ?? ""));

const mergedPulls = (blockers, repo, after = Number.NEGATIVE_INFINITY) =>
  blockers.filter((blocker) => blocker.pull_request && blockerDone(blocker, repo, () => true) && Date.parse(blocker.pull_request.merged_at) > after);

async function stopCleared({ github, repo, number, blockers, events, comments, humans, closes, bot }) {
  const human = events.filter((event) => ["labeled", "unlabeled"].includes(event.event) && String(event.label?.name).toLowerCase() === HUMAN_LABEL).at(-1);
  if (!(human?.event === "labeled" && human.actor?.login === bot)) {
    return { why: `${HUMAN_LABEL} was not last set by the lanes App` };
  }
  const stop = comments.filter((comment) => comment.user?.login === bot && parseReason(comment.body) !== null).at(-1);
  const marker = parseOutcomeMarker(stop?.body);
  if (!marker || parseReason(stop.body).lane !== "work-resolve-issue") {
    return { why: "its newest stop-reason comment is not a work-resolve-issue stop" };
  }
  if (marker.outcome === "pushback") {
    return { why: "the lane pushed back on it, which waits for a person's decision" };
  }
  const stoppedAt = Date.parse(human.created_at);
  const merged = mergedPulls(blockers, repo, stoppedAt);
  if (merged.length === 0) {
    return { why: "no pull request recorded as its blocker merged here since the stop" };
  }
  const security = marker.security || parseReason(stop.body).reason === "security";
  const linked = security ? merged.filter((pull) => namesIssue(pull.body, number)) : merged;
  if (linked.length === 0) {
    return { why: `its stop's reason is security, and no merged blocker's body names #${number}` };
  }
  const pending = await stillBlocking(blockers, repo, clearedHere({ github, repo, humans, closes, bot, events }), closedElsewhere({ github, repo, humans, closes }));
  if (pending.length > 0) {
    return { why: `${pending.length} blocker(s) not closed by a listed human or a merge` };
  }
  return { why: null, pr: Number(linked[0].number), stoppedAt };
}

async function reenterStopped({ github, repo, listed, names, humans, bot, writer = NO_WRITER, statusOf, maps = NO_MAPS }) {
  const stopped = listed.filter((item) => {
    const lower = [...names(item), ...labelNames(item)].map((name) => String(name).toLowerCase());
    const holds = new Set(names(item).map((name) => String(name).toLowerCase()).filter((name) => HOLDS.has(name)));
    return holds.size === 1 && holds.has(HUMAN_LABEL) && !lower.includes(LABEL) && item.issue_dependencies_summary?.total_blocked_by > 0 && !maps.skip(item);
  });
  const closes = new Map();
  const going = [];
  let failed = 0;
  for (const item of stopped) {
    const number = Number(item.number);
    try {
      const blockers = await blockersOf(github, `/repos/${repo}/issues/${number}`);
      if (mergedPulls(blockers, repo).length === 0) {
        console.log(`label-unblocked: #${number} stays at ${HUMAN_LABEL}: no pull request recorded as its blocker merged here`);
        continue;
      }
      const events = await eventsOf(github, repo, statusOf, number);
      const comments = await paginate(github, `/repos/${repo}/issues/${number}/comments`);
      const { why, pr, stoppedAt } = await stopCleared({ github, repo, number, blockers, events, comments, humans, closes, bot });
      if (why) {
        console.log(`label-unblocked: #${number} stays at ${HUMAN_LABEL}: ${why}`);
      } else {
        going.push({ number, pr, stoppedAt, comments });
      }
    } catch (error) {
      failed += failedFor(github, number, error);
    }
  }
  console.log(`label-unblocked: ${going.length} of ${stopped.length} stopped issue(s) with a recorded blocker go back to intake`);
  for (const { number, pr, stoppedAt, comments } of going) {
    try {
      const why = `Pull request #${pr}, recorded as a blocker of this issue, merged after the work-resolve-issue lane stopped it at \`${HUMAN_LABEL}\`,`;
      if (!(await handBackParked({ github, repo, number, comments, parkedAt: stoppedAt, isApp: byBot(bot), writer, why }))) {
        console.log(`label-unblocked: #${number} set to needs-triage; the triage sweep sends it to intake`);
      }
    } catch (error) {
      failed += failedFor(github, number, error);
    }
  }
  return failed;
}

async function deferredIssues(github, repo, byStatus) {
  const listed = byStatus ? await byStatus(["deferred"]) : null;
  if (listed) {
    return listed.filter((item) => NUMBER.test(String(item.number))).sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at) || a.number - b.number);
  }
  return (await paginate(github, `/repos/${repo}/issues?state=open&labels=${DEFERRED_LABEL}&sort=created&direction=asc`)).filter(
    (item) => !item.pull_request && NUMBER.test(String(item.number)),
  );
}

async function admitDeferred({ github, repo, humans, bot, gate, appId, admission, writer = NO_WRITER, statusOf, byStatus, maps = NO_MAPS }) {
  let waiting;
  try {
    waiting = (await deferredIssues(github, repo, byStatus)).filter((item) => !maps.skip(item));
  } catch (error) {
    reportHold(DEFERRED_LABEL, error);
    return 0;
  }
  const closes = new Map();
  const doneBy = mergedRefsReader({ github, repository: repo, numbers: waiting.map((item) => Number(item.number)), humans, appId });
  let failed = 0;
  for (const item of waiting) {
    const number = Number(item.number);
    try {
      const events = await eventsOf(github, repo, statusOf, number);
      const mark = deferralMark(events, { bot, humans });
      if (!trustedLabeler(mark, { bot, humans })) {
        console.log(`::warning title=label-unblocked::#${number}: ${DEFERRED_LABEL} was added by neither the lanes App nor a listed human, so it is left as is and not re-admitted`);
        continue;
      }
      if (attendedHold(events, humans)) {
        console.log(`label-unblocked: #${number} stays deferred: the newest removal of ${ATTENDED} was not a listed human's`);
        continue;
      }
      const { reason, held, kept, stale, notReady, deferred, current, lower } = await refusal({ github, repo, number, humans, closes, bot, appId, events, statusOf });
      if (humans.has(mark.actor?.id) && lower.includes(READY) && !held && current.state === "open") {
        await admitMarked({ github, repo, number, issue: current, names: lower, events, humans, bot, appId, closes, gate, admission, doneBy, writer });
        continue;
      }
      const pulls = reason === null ? await openPullsFor(github, repo, number) : [];
      if (pulls.length > 0) {
        console.log(`label-unblocked: #${number} stays deferred: open pull request #${pulls[0]} is for it`);
      } else if (reason === null) {
        const done = await doneBy(number);
        await (done.length > 0 ? parkDone({ github, repo, number, pulls: done, writer }) : admit({ github, repo, number, gate, deferred, appId, writer }));
      } else if (held || kept) {
        console.log(`label-unblocked: #${number} stays deferred: ${reason}`);
      } else if (stale.length > 0 && stale.every((item) => item.reason === BODY_EDITED)) {
        const comments = await paginate(github, `/repos/${repo}/issues/${number}/comments`);
        if (!(await sendToTriage({ github, repo, number, base: `/repos/${repo}/issues/${number}`, comments, decision: { retriage: [] }, reasons: reason, writer }))) {
          console.log(`label-unblocked: #${number} sent back to intake: ${reason}`);
        }
      } else if (stale.length > 0) {
        const code = lapsedReason(stale);
        if (!(await refuseDeferred({ github, repo, number, comments: await paginate(github, `/repos/${repo}/issues/${number}/comments`), reasons: reason, labels: [parkingStatus(code)], code, writer }))) {
          console.log(`label-unblocked: #${number} refused: ${reason}`);
        }
      } else if (!(await dropDeferral({ number, events, bot, humans, notReady, writer }))) {
        console.log(`label-unblocked: #${number} deferral dropped: ${reason}`);
      }
    } catch (error) {
      failed += failedFor(github, number, error);
    }
  }
  return failed;
}

async function dropDeferral({ number, events, bot, humans, notReady = false, writer }) {
  const trusted = !notReady && trustedLabeler(newestAdd(events, READY), { bot, humans });
  return heldOnSet(writer, number, trusted ? "ready" : "needs-triage");
}

const labelNames = (issue) => (issue?.labels ?? []).map((label) => String(typeof label === "string" ? label : label?.name));

function mapSkipper(routing) {
  const skipped = new Map();
  return {
    skip(item) {
      const label = routingLabel(labelNames(item), routing);
      if (label !== null && !skipped.has(Number(item.number))) {
        skipped.set(Number(item.number), label);
      }
      return label !== null;
    },
    notice() {
      const named = [...skipped].map(([number, label]) => `#${number} ('${escapeCommand(label)}')`);
      return named.length === 0
        ? null
        : `::notice title=label-unblocked::left out ${named.length} map issue(s), each carrying ${ROUTED_BY}: ${named.join(", ")}`;
    },
  };
}
const NO_MAPS = { skip: () => false };

const NO_WRITER = { set: async () => {}, leaveAgentReady: async () => {}, restart: async () => {} };

async function heldOnSet(writer, number, state) {
  const moved = await writer.set(number, state, HOLD_STATES.includes(state) ? undefined : { keepHold: true });
  if (moved?.outcome !== "held") {
    return false;
  }
  console.log(`label-unblocked: #${number} left as is: a person's Work status ${moved.state} holds it`);
  return true;
}

const unstatused = (issue) => labelNames(issue).filter((name) => !isStatusLabel(name));

async function stripClosed({ github, repo, number, read, writer = NO_WRITER }) {
  const base = `/repos/${repo}/issues/${number}`;
  try {
    const issue = read ?? (await github("GET", base));
    if (issue?.state !== "closed") {
      console.log(`label-unblocked: #${number} is open again; its queue labels stay`);
      return 0;
    }
    if (issue.user?.login === ALERT_BOT && FIX_ISSUE.test(String(issue.body ?? ""))) {
      console.log(`label-unblocked: #${number} is a post-merge fix issue; its queue labels stay`);
      return 0;
    }
    const removed = await stripStateLabels(github, base, unstatused(issue));
    console.log(`label-unblocked: #${number} closed; removed ${removed.length} state label(s)${removed.length > 0 ? `: ${removed.join(", ")}` : ""}`);
    await writer.leaveAgentReady(Number(number), "needs-triage");
    return 0;
  } catch (error) {
    return failedFor(github, number, error);
  }
}

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
  return { dimensions };
}

export const skipText = (reason) => `Left out of admission: ${reason}, so work-unblock removed \`${DEFERRED_LABEL}\`.`;

async function admissionDecision({ github, repo, number, issue, names, events, humans, bot, appId, closes, admission, doneBy }) {
  const { rules, dimensionsConfig, webHosts, fieldSetters } = await admission();
  const verdict = await issueVerdict({ github, repo, number, humans, appId, dimensionsConfig, fieldSetters });
  const facts = await admissionFacts({
    github,
    repository: repo,
    number,
    issue: { ...issue, labels: names.map((name) => ({ name })) },
    rules,
    humans,
    appId,
    isTrusted: (blocker) => trustedClose({ github, repo, number: blocker, humans, closes, bot }),
    doneBy,
  });
  const unset = untrustedReady(events, { bot, humans });
  const decision = unset === null ? decide({ ...facts, verdict, rules, humans, appId, repository: repo, webHosts }) : { verdict: "skip", reasons: [unset] };
  const trusted = (id) => humans.has(id) || (appId !== undefined && id === appId);
  if (decision.unsetOnly && notBornTriaged(issue, trusted) === null) {
    return { decision: { verdict: "wait", reasons: [`born triaged, ${decision.unsetOnly.join(" and ")} not set yet`], pulls: [], fields: true }, facts };
  }
  return { decision, facts };
}

async function sendToTriage({ github, repo, number, base, comments, decision, reasons, writer }) {
  if (await heldOnSet(writer, number, "needs-triage")) {
    return true;
  }
  await sayWhy(github, repo, base, comments, retriageNote(reasons, decision.retriage));
  return false;
}

const NEEDS_TRIAGE = "needs-triage";

const refusedState = (status) => (status === NEEDS_DECISION ? "needs-owner-decision" : status === NEEDS_TRIAGE ? NEEDS_TRIAGE : "confirmed");

const UNBLOCK_LANE = "work-unblock";

// The admission comment's text for a refusal: one that holds for a person
// (`code`, its owner reason) adds the visible reason line and the stop-reason
// marker after it, as intake's admit.mjs heldRefusalText does, so every reader
// of the refusal's opening line reads it unchanged; a park (`code` null)
// hands nothing to a person and carries neither.
export function heldText(reasons, code) {
  if (code === null) {
    return refusalText(reasons);
  }
  const [marker, line] = personReasonLines(UNBLOCK_LANE, code);
  return `${refusalText(reasons)}\n\n${line}\n${marker}`;
}

// The owner reason a deferral's lapsed holds (admit.mjs deferralLapsed) stop
// for, as intake's decide names it: `security` for the untrusted-provenance
// hold or a gained security area, `intent` for any other hold, or null when
// none holds.
export function lapsedReason(lapsed) {
  const holds = lapsed.filter((item) => item.hold);
  if (holds.length === 0) {
    return null;
  }
  return holds.some(({ reason }) => reason.startsWith(UNTRUSTED) || reason.startsWith(SECURITY_AREA)) ? "security" : "intent";
}

const decisionReason = (decision) => (decision.hold ? (decision.reason ?? "intent") : null);

const parkingStatus = (code, triage = false) => (code !== null ? NEEDS_DECISION : triage ? NEEDS_TRIAGE : CONFIRMED);

async function refuseDeferred({ github, repo, number, comments, reasons, labels, code = null, writer = NO_WRITER }) {
  const base = `/repos/${repo}/issues/${number}`;
  await sayWhy(github, repo, base, comments, heldText(reasons, code));
  if (await heldOnSet(writer, number, refusedState(labels[0]))) {
    return true;
  }
  if (labels.includes(ATTENDED)) {
    await github("POST", `${base}/labels`, { labels: [ATTENDED] });
  }
  return false;
}

async function admitMarked({ github, repo, number, issue, names, events, humans, bot, appId, closes, gate, admission, doneBy, writer = NO_WRITER }) {
  const base = `/repos/${repo}/issues/${number}`;
  const { decision, facts } = await admissionDecision({ github, repo, number, issue, names, events, humans, bot, appId, closes, admission, doneBy });
  const reasons = decision.reasons.join("; ");
  if (decision.verdict === "admit") {
    console.log(`label-unblocked: #${number}, marked by a person, passes the admission rules`);
    await admit({ github, repo, number, gate, deferred: true, appId, writer });
  } else if (decision.verdict === "refuse") {
    const code = decisionReason(decision);
    const status = parkingStatus(code, decision.triage);
    if (decision.triage) {
      await handBackSplit({ github, repo, issue, comments: facts.comments, appId });
    }
    if (!(await refuseDeferred({ github, repo, number, comments: facts.comments, reasons, labels: decision.attended ? [status, ATTENDED] : [status], code, writer }))) {
      console.log(`label-unblocked: #${number}, marked by a person, refused: ${reasons}`);
    }
  } else if (decision.retriage) {
    if (!(await sendToTriage({ github, repo, number, base, comments: facts.comments, decision, reasons, writer }))) {
      console.log(`label-unblocked: #${number}, marked by a person, sent back to intake: ${reasons}`);
    }
  } else if (decision.verdict === "wait") {
    await sayWhy(github, repo, base, facts.comments, `Not admitted to the issue lane yet: ${reasons}.`);
    const held = decision.pulls.length === 0 && (await dropDeferral({ number, events, bot, humans, writer }));
    if (!held) {
      console.log(`label-unblocked: #${number}, marked by a person, waits: ${reasons}`);
    }
  } else {
    await sayWhy(github, repo, base, facts.comments, skipText(reasons));
    if (!(await dropDeferral({ number, events, bot, humans, writer }))) {
      console.log(`label-unblocked: #${number} deferral dropped: ${reasons}`);
    }
  }
}

// Whether no admission comment (ADMIT_MARKER, by `bot`) among `comments` was
// written at or after the newest `status: ready` add in the issue's events,
// read through `events()` only when that comment exists: no admission decided
// the ready status the issue holds now, as when intake's admission skipped or
// failed on it.
export async function admissionUndecided({ comments, events, bot }) {
  const own = comments.find((comment) => comment.user?.login === bot && String(comment.body ?? "").startsWith(ADMIT_MARKER));
  if (!own) {
    return true;
  }
  const decided = Date.parse(own.updated_at);
  return (await events()).some((event) => event?.event === "labeled" && String(event.label?.name).toLowerCase() === READY && Date.parse(event.created_at) > decided);
}

async function readmitReady({ github, repo, listed: open, names = labelNames, humans, bot, gate, appId, admission, cap, now, writer = NO_WRITER, statusOf, maps = NO_MAPS }) {
  const lower = (item) => names(item).map((name) => name.toLowerCase());
  const listed = open.filter((item) => lower(item).includes(READY) && !maps.skip(item));
  const queued = (labels) => labels.includes(LABEL) || labels.includes(DEFERRED_LABEL) || labels.some((label) => HOLDS.has(label));
  const waiting = (item) => item.issue_dependencies_summary?.blocked_by > 0 || (item.sub_issues_summary?.total ?? 0) > (item.sub_issues_summary?.completed ?? 0);
  let failed = 0;
  const hour = new Date(now).getUTCHours();
  const rotated = (entry) => Number(entry.number) % 24 === hour && entry.issue_dependencies_summary?.blocked_by === 0 && lower(entry).includes(READY) && !queued(lower(entry));
  const drained = new Set();
  const read = new Map();
  for (const item of listed.filter((entry) => rotated(entry) && waiting(entry))) {
    const base = `/repos/${repo}/issues/${item.number}`;
    try {
      const open = async () => {
        const left = (await paginate(github, `${base}/sub_issues`)).filter((child) => child?.state !== "closed");
        if (left.length === 0) {
          drained.add(item.number);
        }
        return left;
      };
      const comments = await paginate(github, `${base}/comments`);
      const rewrote = await refreshSplitWait({ github, repo, parent: item, names: lower(item), comments, open, bot });
      read.set(item.number, rewrote ? null : comments);
      if (rewrote) {
        console.log(`label-unblocked: #${item.number} admission comment now names its open sub-issues`);
      }
    } catch (error) {
      failed += failedFor(github, item.number, error);
    }
  }
  const undecided = new Set();
  for (const item of listed.filter((entry) => Number(entry.number) % 24 === hour && waiting(entry) && !drained.has(entry.number) && !queued(lower(entry)) && read.get(entry.number) !== null)) {
    const number = Number(item.number);
    try {
      const comments = read.get(item.number) ?? (await paginate(github, `/repos/${repo}/issues/${number}/comments`));
      if (await admissionUndecided({ comments, events: () => eventsOf(github, repo, statusOf, number), bot })) {
        undecided.add(item.number);
      }
    } catch (error) {
      failed += failedFor(github, number, error);
    }
  }
  let candidates = listed.filter((item) => !queued(lower(item)) && (!waiting(item) || drained.has(item.number) || undecided.has(item.number)));
  if (candidates.length === 0) {
    return failed;
  }
  let refuseLabels;
  try {
    refuseLabels = new Set((await admission()).rules["refuse-labels"].map((label) => label.toLowerCase()));
  } catch (error) {
    reportError("ready", error);
    return failed + 1;
  }
  candidates = candidates.filter((item) => !lower(item).some((label) => refuseLabels.has(label)));
  console.log(`label-unblocked: ${candidates.length} ${READY} issue(s) in no queue; deciding up to ${cap} (limits.readmit-per-run)`);
  const isMark = (event) => humans.has(event.actor?.id) || (appId !== undefined && event.actor?.id === appId);
  const closes = new Map();
  const doneBy = mergedRefsReader({ github, repository: repo, numbers: candidates.map((item) => Number(item.number)), humans, appId });
  let decided = 0;
  for (const item of candidates) {
    if (decided >= cap) {
      break;
    }
    const number = Number(item.number);
    const base = `/repos/${repo}/issues/${number}`;
    try {
      const issue = await github("GET", base);
      const labels = await fieldFirst(statusOf, number, labelNames(issue).map((name) => name.toLowerCase()));
      const events = await eventsOf(github, repo, statusOf, number);
      const settled =
        issue.state !== "open"
          ? "not open"
          : queued(labels)
            ? "queued or held since the listing"
            : (untrustedReady(events, { bot, humans }) ?? admissionSettled(labels, events, isMark, statusOf?.state ? await statusOf.state(number) : undefined));
      if (settled) {
        console.log(`label-unblocked: #${number} left as is: ${settled}`);
        continue;
      }
      const { decision, facts } = await admissionDecision({ github, repo, number, issue, names: labels, events, humans, bot, appId, closes, admission, doneBy });
      const reasons = decision.reasons.join("; ");
      if (decision.verdict === "admit" || decision.verdict === "refuse" || (decision.verdict === "wait" && decision.pulls.length > 0)) {
        decided += 1;
      }
      if (decision.verdict === "admit") {
        await admit({ github, repo, number, gate, deferred: false, appId, writer });
      } else if (decision.verdict === "refuse") {
        const code = decisionReason(decision);
        if (decision.triage) {
          await handBackSplit({ github, repo, issue, comments: facts.comments, appId });
        }
        if (await heldOnSet(writer, number, refusedState(parkingStatus(code, decision.triage)))) {
          continue;
        }
        if (decision.attended) {
          await github("POST", `${base}/labels`, { labels: [ATTENDED] });
        }
        await sayWhy(github, repo, base, facts.comments, heldText(reasons, code));
        console.log(`label-unblocked: #${number} refused: ${reasons}`);
      } else if (decision.fields) {
        console.log(`label-unblocked: #${number} waits: ${reasons}`);
      } else if (decision.retriage) {
        if (!(await sendToTriage({ github, repo, number, base, comments: facts.comments, decision, reasons, writer }))) {
          console.log(`label-unblocked: #${number} sent back to intake: ${reasons}`);
        }
      } else if (decision.verdict === "wait") {
        if (decision.pulls.length > 0 && (await heldOnSet(writer, number, "deferred"))) {
          continue;
        }
        await sayWhy(github, repo, base, facts.comments, `Not admitted to the issue lane yet: ${reasons}.`);
        console.log(`label-unblocked: #${number} waits: ${reasons}`);
      } else {
        console.log(`label-unblocked: #${number} left as is: ${reasons}`);
      }
    } catch (error) {
      failed += failedFor(github, number, error);
    }
  }
  return failed;
}

async function labelUnblocked({ github, repo, closed, sweep, humans, bot, gate, appId, admission, writer = NO_WRITER, closes = new Map(), statusOf, maps = NO_MAPS }) {
  const seen = new Map();
  let failed = 0;
  for (const source of closed) {
    let blocked;
    try {
      if (sweep) {
        const { issue, trusted } = await readClose({ github, repo, number: source, humans, closes, bot });
        if (!trusted) {
          console.log(`label-unblocked: #${source} was closed by neither a listed human nor a merge; skipped`);
          continue;
        }
        failed += await stripClosed({ github, repo, number: source, read: issue, writer });
      }
      blocked = await paginate(github, `/repos/${repo}/issues/${source}/dependencies/blocking`);
    } catch (error) {
      failed += failedFor(github, source, error);
      continue;
    }
    for (const item of blocked) {
      const number = Number(item.number);
      if (!String(item.repository_url ?? "").toLowerCase().endsWith(`/repos/${repo}`.toLowerCase()) || item.pull_request) {
        console.log(`label-unblocked: skipped a blocked item outside this repository's issues`);
        continue;
      }
      if (maps.skip(item)) {
        continue;
      }
      if (!seen.has(number)) {
        seen.set(number, Date.parse(item.created_at));
      }
    }
  }
  const opened = (number) => (Number.isFinite(seen.get(number)) ? seen.get(number) : Number.POSITIVE_INFINITY);
  const order = [...seen.keys()].sort((a, b) => opened(a) - opened(b) || a - b);
  const doneBy = mergedRefsReader({ github, repository: repo, numbers: order, humans, appId });
  const parked = [];
  for (const number of order) {
    try {
      const { reason, deferred, confirmed, current, lower } = await refusal({ github, repo, number, humans, closes, bot, appId, statusOf });
      if (reason !== null) {
        console.log(`label-unblocked: #${number} not labeled: ${reason}`);
        continue;
      }
      const done = await doneBy(number);
      if (done.length > 0) {
        await parkDone({ github, repo, number, had: labelNames(current), pulls: done, writer });
        continue;
      }
      if (!confirmed && lower.includes(CONFIRMED)) {
        parked.push({ issue: current, lower });
        continue;
      }
      await admit({ github, repo, number, gate, deferred, had: labelNames(current), appId, writer });
    } catch (error) {
      failed += failedFor(github, number, error);
    }
  }
  return failed + (parked.length > 0 ? await unpark({ github, repo, parked, humans, appId, admission, writer, statusOf }) : 0);
}

// The fail route's comment after limits.limit-stops-per-issue limit and
// funding stops. It opens with the issue lane's outcome marker, so signal 9
// reports it and findPrior resumes the stopped run's branch (`run`, and
// `branch=resumed` when that run kept no branch of its own) on the next run.
export const failedComment = ({ stops, run = "", onResumed = false }) =>
  `<!-- work-resolve-issue outcome=failed${run ? ` run=${run}` : ""}${onResumed ? " branch=resumed" : ""} -->\nThe usage limit or the lane's funding stopped the work-resolve-issue lane on this issue ${stops} times since a person last added \`${LABEL}\` (limits.limit-stops-per-issue), so work-unblock stopped restarting it: it removed \`${LABEL}\` and added no label. This is a capacity stop, not a decision for a person. To run it again, add \`${LABEL}\`; the next run continues the stopped run's branch while it is not behind the default branch.`;

// The re-fire's record, posted before the label moves: one per issue per
// version of the lane workflow files.
const FAILED_CAUSE = `The work-resolve-issue run that \`${LABEL}\` started failed or was cancelled before it reported, or it stopped or the token broker refused it because its workflow files differ from main's.`;
export const refireComment = (key, cause = FAILED_CAUSE) => refireRecord(key, cause);

const hoursText = (hours) => `${hours} hour${hours === 1 ? "" : "s"}`;
const strandedCause = {
  "no-run": (hours) => `No work-resolve-issue run started in the ${hoursText(hours)} since \`${LABEL}\` was last added.`,
  "no-report": (hours) => `The work-resolve-issue run that \`${LABEL}\` started ended over ${hoursText(hours)} ago with no report and no pull request.`,
  "failed-again": (hours) => `The work-resolve-issue run that \`${LABEL}\` started failed or was cancelled before it reported, over ${hoursText(hours)} ago.`,
};

const MINT_CAUSE = `The work-resolve-issue run that \`${LABEL}\` started could not get its lane token, or the token broker's leave to run.`;
const rateLimitCause = (reset, server = null) => {
  const at = new Date(reset).toISOString().replace(/\.\d{3}Z$/, "Z");
  return server
    ? `The work-resolve-issue run that \`${LABEL}\` started stopped on a GitHub server error hold (HTTP ${server} with a Retry-After) before any model turn; the hold passed at ${at}.`
    : `The work-resolve-issue run that \`${LABEL}\` started stopped on GitHub's API rate limit before any model turn; the limit reset at ${at}.`;
};

// The record of a re-fire after a kill-switch refusal, posted before the
// label moves, once per re-fire. It names the refused run and when it ended,
// since the re-fire can come hours after the refusal.
export const breakerComment = (key, { repo, run, ended, budget = false, earlier = [] }) =>
  budget
    ? `<!-- work-unblock refired ${key} breaker -->\n${BUDGET_TAG}\nThis records a re-fire of an earlier stop, not a new one. The start gate stopped [run ${run}](https://github.com/${repo}/actions/runs/${run}), the work-resolve-issue run that \`${LABEL}\` started, before any model turn, because the GITHUB_TOKEN budget was under its start-gate share, or the window was projected to have under its start-project share of the header's limit left by the run's expected end (github-token start-gate, start-project and start-run-minutes in rate-limits.json; the run's start-gate notice names which); that run ended at ${new Date(ended).toISOString().replace(/\.\d{3}Z$/, "Z")}. work-unblock has now removed and added \`${LABEL}\` back to start a fresh run. A budget stop is the lanes' load, not a fault in this issue: it never counts toward limits.limit-stops-per-issue or the \`kill-switch\` wait.${earlier.length > 0 ? `\n<!-- work-unblock earlier ${earlier.join(" ")} -->` : ""}`
    : `<!-- work-unblock refired ${key} breaker -->\nThis records a re-fire of an earlier refusal, not a new refusal. The lanes kill switch stopped [run ${run}](https://github.com/${repo}/actions/runs/${run}), the work-resolve-issue run that \`${LABEL}\` started, before it finished; that run ended at ${new Date(ended).toISOString().replace(/\.\d{3}Z$/, "Z")}. work-unblock has now removed and added \`${LABEL}\` back to start a fresh run. A kill-switch refusal is no fault in this issue or the lanes, so it never counts against later re-fires; after limits.limit-stops-per-issue of them since a person last added \`${LABEL}\` or a run last reported, work-unblock waits the same limits.stranded-backoff-hours \`kill-switch\` hours after each refused run before re-firing it, never longer.`;

const floorComment = (key, { repo, run, reset, named, server }) => {
  const stopper = server ? `A GitHub server error hold (HTTP ${server} with a Retry-After)` : named ? "A GitHub API pool's stop floor" : "GitHub's API rate limit";
  return `<!-- work-unblock refired ${key} breaker -->\n${floorTag(reset)}\nThis records a re-fire of an earlier stop, not a new one. ${stopper} stopped [run ${run}](https://github.com/${repo}/actions/runs/${run}), the work-resolve-issue run that \`${LABEL}\` started, after its model ran${named ? `, until ${isoSecond(reset)}` : ""}. work-unblock has now removed and added \`${LABEL}\` back to start a fresh run${named ? " early in a window" : ""}. ${server ? "A GitHub server error is" : "A floor stop is the lanes' load,"} not a fault in this issue. After limits.limit-stops-per-issue of these since a person last added \`${LABEL}\` or a run last reported, work-unblock waits the limits.stranded-backoff-hours \`failed-again\` backoff instead.`;
};

// The backoff record of an issue whose re-fires on these workflow files keep
// ending the same way: one comment per issue, edited on each re-fire.
export const infraComment = (key, cause, refires) =>
  `<!-- work-unblock infrastructure ${key} -->\n${cause} work-unblock has re-fired it ${refires} time(s) on lane workflow files ${key} and keeps re-firing it, waiting longer each time, up to ${BACKOFF_CAP_HOURS} hours, until a run reports. This is a fault in the lanes, not in the issue; this comment is updated on each re-fire.`;

// The relabel's record, posted before the label moves: one per recurrence
// comment.
export const recurrenceComment = (id) =>
  `<!-- work-unblock recurrence ${id} -->\nThis check failed on main again, and post-merge-file-demotion-issues reopened this issue, which starts no work-resolve-issue run. work-unblock removed and added \`${LABEL}\` back to start one. It does this once per reopen.`;

// The hand-offs to triage once the lane PR ended, each posted once per pull
// request before its labels move.
export const refsMergedComment = (pr) =>
  `${handedMarker(pr)}\nPull request #${pr} merged with \`Refs:\`, so this issue stays open and nothing starts the lane on it again. work-unblock removed \`${READY}\` and \`${LABEL}\`, so the hourly triage sweep sends it back to intake triage. Admission then parks it at \`${CONFIRMED}\` for a check of what that pull request left, until a \`**Decision recorded.**\` comment says what is left or someone closes it.`;
export const refsClosedComment = (pr) =>
  `${handedMarker(pr)}\nThe lanes App's pull request #${pr} for this issue was closed without merging. work-unblock removed \`${READY}\` and \`${LABEL}\`, so the hourly triage sweep sends it back to intake triage, which decides what work is left and admits it again.`;

// A work-resolve-issue run title that names an issue ends with ` #<number>`.
const NAMES_ISSUE = / #[1-9][0-9]*$/;

// A label window as the `created=a..b` listing filter reads it: both ends cut
// to the second, and both inclusive, as GitHub's `n..n` range is.
const runWindow = (addedAt) => [Math.floor(addedAt / 1000) * 1000, Math.floor((addedAt + RUN_WINDOW_MS) / 1000) * 1000];
const laneRunsPath = (repo, [from, to]) => {
  const iso = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
  return `/repos/${repo}/actions/workflows/work-resolve-issue.yml/runs?event=issues&created=${encodeURIComponent(`${iso(from)}..${iso(to)}`)}`;
};
const runTitle = (run) => String(run.display_title ?? "");

// The work-resolve-issue runs for issue `number` created within RUN_WINDOW_MS
// of the label event at `addedAt`, as `mine`. The run title ends with
// ` #<number>`; `untitled` counts the runs in the window whose title names no
// issue (titles from before that run name), which may include this issue's.
export async function laneRuns(actions, repo, number, addedAt) {
  const path = laneRunsPath(repo, runWindow(addedAt));
  const runs = [];
  for (let page = 1; page <= 10; page += 1) {
    const batch = (await actions("GET", `${path}&per_page=100&page=${page}`))?.workflow_runs;
    if (!Array.isArray(batch)) {
      throw new Error("the workflow run listing has an unexpected shape");
    }
    runs.push(...batch);
    if (batch.length < 100) {
      return {
        mine: runs.filter((run) => runTitle(run).endsWith(` #${number}`)),
        untitled: runs.filter((run) => !NAMES_ISSUE.test(runTitle(run))).length,
      };
    }
  }
  throw new Error("the workflow run listing has more than 10 pages");
}

// Label windows starting in the same span of this length share one listing.
// At about 75 lane runs an hour, a span's listing is about one page, the call
// one issue's own listing costs.
const BUCKET_MS = 60 * 60_000;
// The listing filtered by `created` answers at most 1,000 runs.
const LISTING_CAP = 1000;

// The runs of one span's listing, or null when it holds more than the listing
// answers, so each of its issues is listed on its own.
async function spanRuns(actions, repo, span) {
  const path = laneRunsPath(repo, span);
  const runs = [];
  for (let page = 1; page <= LISTING_CAP / 100; page += 1) {
    const answer = await actions("GET", `${path}&per_page=100&page=${page}`);
    const batch = answer?.workflow_runs;
    if (!Array.isArray(batch)) {
      throw new Error("the workflow run listing has an unexpected shape");
    }
    if (Number(answer.total_count) > LISTING_CAP) {
      return null;
    }
    runs.push(...batch);
    if (batch.length < 100) {
      return runs;
    }
  }
  return null;
}

// laneRuns as `(number, addedAt)`, from one listing per BUCKET_MS span that a
// label window starts in, read when an issue of that span first asks, so no
// issue's history is read ahead of its own turn. Each span's listing reaches
// RUN_WINDOW_MS past its end, so it holds the whole window of every label in
// it. A listing is never reused by another sweep, so status and updated_at
// are this sweep's; a span too big to list has each issue listed on its own.
export function sharedLaneRuns(actions, repo) {
  const spans = new Map();
  return async (number, addedAt) => {
    const [from, to] = runWindow(addedAt);
    const start = Math.floor(from / BUCKET_MS) * BUCKET_MS;
    if (!spans.has(start)) {
      spans.set(
        start,
        spanRuns(actions, repo, [start, start + BUCKET_MS + RUN_WINDOW_MS]).catch((error) => {
          spans.delete(start);
          throw error;
        }),
      );
    }
    const runs = await spans.get(start);
    if (!runs) {
      return laneRuns(actions, repo, number, addedAt);
    }
    const inWindow = runs.filter((run) => {
      const at = Date.parse(run.created_at);
      return at >= from && at <= to;
    });
    return {
      mine: inWindow.filter((run) => runTitle(run).endsWith(` #${number}`)),
      untitled: inWindow.filter((run) => !NAMES_ISSUE.test(runTitle(run))).length,
    };
  };
}

async function didNoWork(jobsOf, refusalOf, runs) {
  const rank = { outage: 0.5, capped: 1, blocked: 1, breaker: 2, "mint-failed": 3 };
  let stalled = null;
  let tripped = null;
  let stage = null;
  let switched = false;
  let resetAt = null;
  let reset = 0;
  let server = null;
  let limitSeen = false;
  const atLeast = (kind, run, at, budget = false) => {
    switched ||= kind === "breaker" && !budget;
    if (rank[kind] > (rank[stalled] ?? 0)) {
      stalled = kind;
      tripped = run;
      stage = at;
    }
  };
  for (const run of runs) {
    if (!RUN_ID.test(String(run.id))) {
      return null;
    }
    const jobs = await jobsOf(run);
    const failedAt = (job, name) => endedAt(job, name, "failure");
    if (jobs.some((job) => endedAt(job, MINT_STEP, "success") && !stoppedAt(job))) {
      const report = namedJobs(jobs, "report-outcome").find(stoppedAt);
      if (!report || (await refusalOf(report, "stop")) !== BREAKER) {
        return null;
      }
      console.log(`::notice title=label-unblocked::run ${run.id} minted, then the kill switch stopped its report-outcome mint: a breaker trip`);
      atLeast("breaker", run, "token");
      continue;
    }
    const named = (name) => namedJobs(jobs, name);
    const calls = RESOLVE_CALLS.flatMap(named);
    const budgetSteps = calls.flatMap((job) => (job?.steps ?? []).filter((step) => step?.conclusion === "success" && BUDGET_STEP.test(String(step?.name))));
    const budget = budgetSteps.length > 0;
    for (const step of budgetSteps) {
      const until = BUDGET_STEP.exec(step.name)[1] ?? "";
      const seconds = /^[0-9]{1,12}$/.test(until) ? Number(until) : 0;
      if (seconds > 0) {
        resetAt = Math.max(resetAt ?? 0, seconds * 1000);
      }
    }
    const killedBefore = (step) => (job) => endedAt(job, KILL_STEP, "success") && endedAt(job, step, "skipped");
    // check-admission's first gated step is INSTALL_STEP: a failed install also skips
    // TRIGGER_STEP, and that job fails, so only a green job with both skipped
    // is the switch. pick-slot's gated WIP_STEP follows only continue-on-error
    // steps, so a green job with it skipped is the switch too.
    const switchedOff = (...steps) => (job) => job.conclusion === "success" && steps.every((step) => killedBefore(step)(job));
    const killed =
      budget ||
      calls.some(killedBefore(BROKER_STEP)) || ADMIT.flatMap(named).some(switchedOff(INSTALL_STEP, TRIGGER_STEP)) || named("pick-slot").some(switchedOff(WIP_STEP));
    const preModel = [...ADMIT.flatMap(named), ...named("pick-slot"), ...calls.filter((job) => / \/ (?:broker-check|Broker Check|check-broker|Check Broker|run|Run)$/.test(String(job.name)))];
    const limited = modelRan(jobs) ? undefined : preModel.find((job) => job.conclusion === "failure");
    const checked = calls.find((job) => failedAt(job, BROKER_STEP));
    const checkStopped = calls.find((job) => job.conclusion === "success" && endedAt(job, BROKER_STEP, "success") && endedAt(job, LEASE_STEP, "skipped"));
    const minting = jobs.find((job) => failedAt(job, MINT_STEP));
    const stopped = jobs.find(stoppedAt);
    const capped =
      named("pick-slot").some((job) => job.conclusion === "success") &&
      named("resolve-issue").length > 0 &&
      calls.every((job) => job.conclusion === "skipped");
    const blocked =
      (ADMIT.flatMap(named).some((job) => endedAt(job, BLOCKER_STEP, "success")) && named("pick-slot").every((job) => job.conclusion === "skipped")) ||
      calls.some((job) => endedAt(job, RECHECK_STOP_STEP, "success"));
    const outage =
      ADMIT.flatMap(named).some((job) => job.conclusion === "success" && endedAt(job, UPSTREAM_STEP, "success")) &&
      named("pick-slot").length > 0 &&
      named("pick-slot").every((job) => job.conclusion === "skipped");
    const refused = await (killed
      ? null
      : checked
        ? refusalOf(checked, "check")
        : checkStopped
          ? refusalOf(checkStopped, "stop")
          : minting
            ? refusalOf(minting, "token")
            : stopped
              ? refusalOf(stopped, "stop")
              : limited
                ? refusalOf(limited, "limit")
                : null);
    if (killed || refused === BREAKER) {
      atLeast("breaker", run, killed || checked || checkStopped ? "check" : "token", budget);
    } else if (minting || checked || checkStopped || stopped) {
      atLeast("mint-failed");
    } else if (limited && refused) {
      atLeast("mint-failed");
      const [at, held] = refused.split(" ");
      reset = Math.max(reset, Date.parse(at));
      if (held) {
        server ??= Number(held.slice("server-".length));
      } else {
        limitSeen = true;
      }
    } else if (capped) {
      atLeast("capped");
    } else if (blocked) {
      atLeast(outage ? "outage" : "blocked");
    }
  }
  const budget = stalled === "breaker" && !switched;
  const limit = stalled === "mint-failed" && reset > 0;
  return stalled && { stalled, run: tripped, stage, budget, resetAt: budget ? resetAt : null, reset: stalled === "mint-failed" ? reset : 0, server: limit && !limitSeen ? server : null };
}

const modelRan = (jobs) => jobs.some((job) => (job.steps ?? []).some((step) => MODEL_STEP.test(String(step?.name)) && step.conclusion && step.conclusion !== "skipped"));

async function floorStop(jobsOf, refusalOf, runs) {
  let stop = null;
  let limitSeen = false;
  for (const run of runs.filter((item) => FAILED.has(item.conclusion))) {
    const jobs = await jobsOf(run);
    const stopped = jobs.filter((job) => job.conclusion === "failure");
    const failedSteps = stopped.map((job) => (job.steps ?? []).filter((step) => step?.conclusion === "failure"));
    if (stopped.length === 0 || !modelRan(jobs) || jobs.some((job) => !FLOOR_JOB_ENDS.has(job.conclusion)) || failedSteps.some((steps) => steps.length === 0 || steps.some((step) => MODEL_STEP.test(String(step.name))))) {
      return null;
    }
    for (const job of stopped) {
      const found = await refusalOf(job, "floor");
      if (found === LOG_UNREAD) {
        return { unread: true };
      }
      if (found === null) {
        return null;
      }
      const [at, hold] = found.split(" ");
      const reset = Date.parse(at);
      limitSeen ||= !hold;
      if (!stop || reset > (stop.reset ?? 0)) {
        stop = { run, reset: Number.isFinite(reset) ? reset : null, server: hold?.replace("server-", "") ?? null };
      }
    }
  }
  return stop && limitSeen ? { ...stop, server: null } : stop;
}

// The reason the broker refused `job`, from its log: the failed step's last
// line before the runner's first `Process completed`, in `mode` (check or
// token; in `limit` mode the reset a RATE_LIMITED line names), or BREAKER
// for a `stop` mode log with a STOPPED line inside the mint step's MINT_START
// section. Null when there is no such line or the log
// cannot be read within LOG_CAP_BYTES, or no log reader was given; the log is
// data: check and token modes read only that one line, and a STOPPED line
// outside the section never counts. A job's log never changes once it ends,
// so the answer from a log that was read is kept in `carry`
// (verdict-carry.mjs) and the next sweep reads it from there.
function refusalReader(jobLog, repo, carry) {
  return async (job, mode) => {
    if (!jobLog || !RUN_ID.test(String(job?.id))) {
      return null;
    }
    const carried = carry?.refusal(job.id, mode);
    if (carried) {
      return carried.value;
    }
    let log;
    try {
      log = await jobLog(repo, job.id, { maxBytes: LOG_CAP_BYTES });
    } catch (error) {
      console.log(`::warning title=label-unblocked::job ${job.id}'s log was not read: ${escapeCommand(error?.message ?? error)}`);
      return mode === "floor" && !OVER_CAP.test(String(error?.message)) ? LOG_UNREAD : null;
    }
    const value = refusalIn(String(log ?? "").split("\n"), mode);
    carry?.keepRefusal(job.id, mode, value);
    return value;
  };
}

const stopNamed = ({ reset, status } = {}) => (reset && Number.isFinite(Date.parse(reset)) ? `${reset}${status ? ` server-${status}` : ""}` : null);
const stopNamedIn = (line) => stopNamed(RATE_LIMITED.exec(line)?.groups);

function floorIn(lines) {
  let found = null;
  let limited = false;
  let unexplained = true;
  for (const line of lines.filter((item) => ERROR_LINE.test(item) || STEP_EDGE.test(item))) {
    const named = stopNamedIn(line) ?? stopNamed(HELD_UNTIL.exec(line)?.groups);
    if (STEP_EDGE.test(line)) {
      unexplained = true;
    } else if (named) {
      found = !found || found === NO_RESET || Date.parse(named.split(" ")[0]) > Date.parse(found.split(" ")[0]) ? named : found;
      limited ||= !named.includes(" ");
      unexplained = false;
    } else if (RAW_LIMIT.test(line)) {
      found ??= NO_RESET;
      limited = true;
      unexplained = false;
    } else if (STEP_FAILED.test(line)) {
      if (unexplained) {
        return null;
      }
      unexplained = true;
    } else if (!LIMIT_COMPANION.test(line)) {
      return null;
    }
  }
  return found && limited ? found.split(" ")[0] : found;
}

function refusalIn(lines, mode) {
  if (mode === "floor") {
    return floorIn(lines);
  }
  if (mode === "stop") {
    const start = lines.findIndex((line) => MINT_START.test(line));
    if (start < 0) {
      return null;
    }
    const end = mintEnd(MINT_START.exec(lines[start])[1]);
    const stop = lines.findIndex((line, at) => at > start && end.test(line));
    return stop > 0 && lines.slice(start, stop).some((line) => STOPPED.test(line)) ? BREAKER : null;
  }
  const end = lines.findIndex((line) => STEP_FAILED.test(line));
  if (end <= 0) {
    return null;
  }
  if (mode === "limit") {
    // `<reset>` for a rate limit, `<reset> server-<5xx>` for a server error
    // hold; verdict-carry's REASON carries both.
    return stopNamedIn(lines[end - 1]);
  }
  return DENIAL[mode].exec(lines[end - 1])?.[1] ?? null;
}

function jobLister(actions, repo, carry) {
  const listed = new Map();
  return (run) => {
    if (!listed.has(run.id)) {
      listed.set(
        run.id,
        (async () => {
          const carried = carry?.jobsOf(run);
          if (carried) {
            return carried;
          }
          const jobs = (await actions("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`))?.jobs;
          if (!Array.isArray(jobs)) {
            throw new Error(`run ${run.id}'s job listing has an unexpected shape`);
          }
          carry?.keepJobs(run, jobs);
          return jobs;
        })(),
      );
    }
    return listed.get(run.id);
  };
}

const endedAt = (job, name, conclusion) => (job?.steps ?? []).some((step) => step?.name === name && step.conclusion === conclusion);
const stoppedAt = (job) => endedAt(job, MINT_STEP, "success") && endedAt(job, STAGE_STEP, "skipped");

async function someRunJobs(jobsOf, runs, test) {
  for (const run of runs.filter((item) => RUN_ID.test(String(item.id)))) {
    if (test(await jobsOf(run))) {
      return true;
    }
  }
  return false;
}

const stoppedMint = (jobsOf, runs) => someRunJobs(jobsOf, runs, (jobs) => jobs.some(stoppedAt));

// The display name of each job this script reads, by job id. The jobs API
// names a job by its display name, or by its id on a run started before the
// rename; a called job's name goes on ` / <job>`.
const JOB_NAMES = {
  admit: "Admit",
  "check-admission": "Check Admission",
  "pick-slot": "Pick Slot",
  "report-outcome": "Report Outcome",
  "resolve-issue": "Resolve Issue",
  "resolve-issue-subscription": "Resolve Issue Subscription",
  "resolve-issue-fallback": "Resolve Issue Fallback",
  "label-unblocked": "Label Unblocked",
};
const namedJobs = (jobs, id) =>
  jobs.filter((job) => [JOB_NAMES[id], id].some((name) => job?.name === name || String(job?.name).startsWith(`${name} /`)));

const stoppedUntrusted = (jobsOf, runs) => someRunJobs(jobsOf, runs, (jobs) => ADMIT.flatMap((id) => namedJobs(jobs, id)).some((job) => endedAt(job, UNTRUSTED_STEP, "success")));

const stoppedStale = (jobsOf, runs) =>
  someRunJobs(jobsOf, runs, (jobs) => RESOLVE_CALLS.flatMap((name) => namedJobs(jobs, name)).some((job) => endedAt(job, STALE_STEP, "success")));

// A job that never ran on a runner: skipped, or no step ran and no runner took
// it. A job listing with no steps for a job a runner took is not one.
const neverStarted = (job) =>
  job?.conclusion === "skipped" || ((job?.steps ?? []).every((step) => step?.conclusion === "skipped") && (!job?.runner_id || !job?.started_at));

// Whether one of `runs` was cancelled after check-admission passed and before any
// resolve-issue job (pr-run-activity-read.yml's check-broker and run) started:
// pick-slot cancelled (its timeout, or a person), or resolve-issue cancelled
// while it waited for its slot (GitHub cancels a slot queue past its limit).
// A run a newer agent-ready run replaced in the workflow's concurrency group
// was cancelled while it waited, before check-admission ran, so it never counts.
const cancelledBeforeWork = (jobsOf, runs) =>
  someRunJobs(
    jobsOf,
    runs.filter((item) => item.conclusion === "cancelled"),
    (jobs) => {
      const named = (name) => namedJobs(jobs, name);
      const resolve = named("resolve-issue");
      return (
        ADMIT.flatMap(named).some((job) => job.conclusion === "success") &&
        resolve.every(neverStarted) &&
        [...named("pick-slot"), ...resolve].some((job) => job.conclusion === "cancelled")
      );
    },
  );

const sameRepo = (side, repo) => String(side?.repo?.full_name ?? "").toLowerCase() === repo.toLowerCase();

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

async function humanPull({ github, repo, number, humans }) {
  return (await humanPullsFor(github, repo, number, humans))[0] ?? null;
}

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

// The issue lane's slot count: the effective lane level, which pick-slot in
// work-resolve-issue.yml reads the same way (lane-level-value.mjs).
export function laneSlots({ laneLevel = {}, env = process.env, now = Date.now(), log = console.log } = {}) {
  const read = laneLevelFromEnv(laneLevel, env, now);
  log(`label-unblocked: ${describeLevel(read)}`);
  return read.level;
}

async function runsInFlight(actions, repo) {
  const runs = [];
  for (const status of IN_FLIGHT) {
    const batch = (await actions("GET", `/repos/${repo}/actions/workflows/work-resolve-issue.yml/runs?status=${status}&per_page=100`))
      ?.workflow_runs;
    if (!Array.isArray(batch) || batch.length >= 100) {
      throw new Error(`the ${status} work-resolve-issue run listing has an unexpected shape or 100 runs`);
    }
    runs.push(...batch.map((run) => ({ title: String(run.display_title ?? ""), status, created: Date.parse(run.created_at) })));
  }
  return runs;
}

// Whether `run` has sat `queued` for `minutes` or more at `now`. The lane's
// check-admission job runs on a GitHub-hosted runner and the slot wait is a job-level
// concurrency group after it (work-resolve-issue.yml), so a run that is still
// queued this long never got a runner: GitHub lost it and it will never start.
// An unreadable creation time is never stale, so the run still counts.
const staleQueued = (run, now, minutes) => run.status === "queued" && now - run.created >= minutes * 60_000;

const fieldNamesOf = (statusOf, issue) => fieldFirst(statusOf, issue.number, labelNames(issue).map((name) => name.toLowerCase()));

async function recurrenceRefusal({ github, repo, issue, bot, humans, inFlight, read, statusOf, now, limits }) {
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
  const lastAdd = events.filter((event) => isLabel(event, "labeled")).at(-1);
  if (lastAdd === undefined || !trustedLabeler(lastAdd, { bot, humans })) {
    return { reason: `${LABEL} was added by neither a listed human nor the lanes App` };
  }
  const held = (await fieldNamesOf(statusOf, issue)).find((label) => HOLDS.has(label));
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
  const runs = await inFlight();
  if (runs === null) {
    return { reason: "no Actions token to read its lane runs" };
  }
  if (runs.some((run) => run.title.endsWith(` #${issue.number}`))) {
    return { reason: "a lane run for it is in flight" };
  }
  const untitled = runs.filter((run) => !NAMES_ISSUE.test(run.title) && !staleQueued(run, now, limits["stale-queued-minutes"])).length;
  if (untitled > 0) {
    return { reason: `cannot tell whether a lane run for it is in flight: ${untitled} unfinished run(s) name no issue in their title` };
  }
  const recorded = comments.some((comment) => comment.user?.login === bot && RELABELED.exec(String(comment.body ?? ""))?.[1] === String(recurrence.id));
  return { reason: null, resets: at, recurrence: recurrence.id, recorded };
}

const appPosted = (comments, bot, marker) => comments.some((comment) => comment.user?.login === bot && String(comment.body ?? "").startsWith(marker));

function pullRefusal({ pull, number, comments, events, bot, held }) {
  const byApp = (marker) => appPosted(comments, bot, marker);
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
  if (!merged && comments.some((comment) => comment.user?.login === bot && Number(CAPPED_CLOSE.exec(String(comment.body ?? ""))?.[1]) === pull.number)) {
    return { reason: `its lane PR #${pull.number} closed at the verify cap, and pr-merge restarted or parked the issue` };
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

async function refireRefusal({ github, actions, jobLog, carry, repo, number, issue, lastAdd, addedAt, markers, comments, events, humans, bot, workflowKey, held, limits, now, wipCapped, runsOf, upstreamClear }) {
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
  if (untrustedHold({ labels: [], events, humans, isApp: byBot(bot) })) {
    return { reason: `${UNTRUSTED} was last removed by neither a listed human nor the lanes App` };
  }
  const base = `/repos/${repo}/issues/${number}`;
  const closes = new Map();
  const pending = await stillBlocking(
    await blockersOf(github, base),
    repo,
    clearedHere({ github, repo, humans, closes, bot, events }),
    closedElsewhere({ github, repo, humans, closes }),
  );
  if (pending.length > 0) {
    return { reason: `waiting on ${pending.length} blocker(s) not closed by a listed human or a merge` };
  }
  const subs = await openSubIssues(github, base, issue);
  if (subs.length > 0) {
    return { reason: `an umbrella waiting on open ${subs.map((sub) => `sub-issue #${sub.number}`).join(", ")}` };
  }
  if (!actions) {
    return { reason: "no Actions token to read its lane run" };
  }
  const firedOn = (key) => markers.filter((marker) => marker.outcome === "refired" && !marker.breaker && marker.key === key);
  const relabeled = (marker) =>
    events.some((event) => isLabel(event, "labeled") && event.actor?.login === bot && Date.parse(event.created_at) >= marker.at);
  const hoursFor = resolveStrandedBackoff(limits["stranded-backoff-hours"]);
  const backoff = (key, since, cause, hours) => {
    const first = Math.min(...firedOn(key).map((marker) => marker.at));
    const adds = events.filter((event) => isLabel(event, "labeled") && event.actor?.login === bot);
    const trips = new Set(markers.filter((marker) => marker.breaker).map((marker) => adds.find((event) => Date.parse(event.created_at) >= marker.at)));
    const refires = adds.filter((event) => Date.parse(event.created_at) >= first && !trips.has(event)).length;
    const due = backoffDue(since, refires, hours);
    if (now < due) {
      return { reason: `re-fired ${refires} time(s) on workflow files ${key}; it is re-fired again after ${new Date(due).toISOString()}`, due };
    }
    const own = comments.filter((comment) => comment.user?.login === bot && INFRA.test(String(comment.body ?? ""))).at(-1);
    return { reason: null, resets: due, refire: key, recorded: true, infra: { id: own?.id, body: infraComment(key, cause, refires + 1) } };
  };
  const stranded = async (since, why, cause) => {
    const hours = hoursFor[cause];
    if (now - since < hours * HOUR_MS) {
      return { reason: why, due: since + hours * HOUR_MS };
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
    const fired = firedOn(key);
    if (fired.some(relabeled)) {
      return backoff(key, since, strandedCause[cause](hours), hours);
    }
    return { reason: null, resets: since, refire: key, recorded: fired.length > 0, cause: strandedCause[cause](hours) };
  };
  const { mine: runs, untitled } = await runsOf(number, addedAt);
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
  const ended = Math.max(...runs.map((run) => Date.parse(run.updated_at)).filter(Number.isFinite), addedAt);
  const jobsOf = jobLister(actions, repo, carry);
  if (await stoppedUntrusted(jobsOf, runs)) {
    return { reason: "its lane run stopped on an outside author or untrusted provenance, which a person decides" };
  }
  const stale = await stoppedStale(jobsOf, runs);
  const refusalOf = refusalReader(jobLog, repo, carry);
  const { stalled, run: refused, stage, budget, resetAt, reset, server } = (!stale && (await didNoWork(jobsOf, refusalOf, runs))) || {};
  const from = Math.max(
    Number.NEGATIVE_INFINITY,
    ...events.filter((event) => isLabel(event, "labeled") && humans.has(event.actor?.id)).map((event) => Date.parse(event.created_at)),
    ...markers.filter((marker) => marker.outcome !== "refired").map((marker) => marker.at),
  );
  if (stalled) {
    // Breaker trips since a listed human last added agent-ready or a run last
    // reported; past limits.limit-stops-per-issue of them, a flat wait of the
    // kill-switch hours that never doubles: a trip is the lanes' load, not the
    // issue's fault (owner decision Q109). A stop on the GITHUB_TOKEN budget is
    // no trip: it never counts, and re-fires only early in a window after the
    // reset its step names (with none, from an hour after the run ended), a
    // primary window's length:
    // https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
    const trips = stalled === "breaker" && !budget ? markers.filter((marker) => marker.breaker && !marker.budget && marker.floor === undefined && marker.at > from).length : 0;
    const over = budget ? -1 : trips - limits["limit-stops-per-issue"];
    const outage = stalled === "outage";
    const clamp = (stalled === "breaker" && stage === "check") || (outage && (await upstreamClear())) ? 0 : limits["reset-clamp-min"];
    // A budget stop waits for a span early in a window after the reset it names:
    // https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
    // A rate-limit stop waits past the reset it names.
    const due = budget ? (resetAt === null ? ended + HOUR_MS : spanOpens(resetAt, now)) : Math.max(ended + (over >= 0 ? hoursFor["kill-switch"] : clamp) * HOUR_MS, reset);
    if (now < due) {
      const why = budget
        ? "the start gate stopped its lane run on a low GITHUB_TOKEN budget"
        : stalled === "breaker"
          ? `the broker refused its lane run for the lanes kill switch (trip ${trips + 1})`
          : outage
            ? "the upstream-status stop skipped its lane run, and the status page does not read clear"
            : reset
              ? (server ? `its lane run stopped on a GitHub server error hold (HTTP ${server} with a Retry-After) before any model turn` : "its lane run stopped on GitHub's API rate limit before any model turn")
              : "its lane run did no work";
      return { reason: `${why}; it is re-fired after ${new Date(due).toISOString()}`, ...(!outage && { due }) };
    }
    if (await wipCapped()) {
      return { reason: "its lane run did no work, and the issue lane is paused over its WIP cap" };
    }
    const key = await workflowKey();
    const recorded = markers.some((marker) => marker.outcome === "refired" && marker.at >= addedAt);
    const fired = firedOn(key).length;
    if (stalled === "mint-failed" && !recorded && fired >= limits["limit-stops-per-issue"]) {
      return backoff(key, ended, reset ? rateLimitCause(reset, server) : MINT_CAUSE, hoursFor["failed-mint"]);
    }
    const budgetRecord = budget
      ? comments.filter((comment) => comment.user?.login === bot && parseMarker(comment.body)?.budget && RUN_ID.test(String(comment.id))).at(-1)
      : undefined;
    const earlier = budgetRecord ? [...budgetEarlier(budgetRecord.body), budgetRecord.updated_at ?? budgetRecord.created_at] : [];
    const trip = stalled === "breaker" ? { run: refused.id, ended: Date.parse(refused.updated_at) || ended, budget, record: budgetRecord?.id, earlier } : undefined;
    return { reason: null, resets: trip ? ended : due, refire: key, recorded, stall: stalled, trip, ...(reset && { cause: rateLimitCause(reset, server) }), ...(budget && resetAt !== null && { closes: due + FLOOR_SPAN_MS }) };
  }
  const floored = stale ? null : await floorStop(jobsOf, refusalOf, runs);
  if (floored?.unread && now < ended + HOUR_MS) {
    return { reason: "a failed job's log was not read, so the next sweep decides whether a floor stop ended its lane run" };
  }
  if (floored && !floored.unread) {
    const reset = floored.reset ?? ended + HOUR_MS;
    const named = markers.filter((marker) => marker.floor === reset);
    if (named.some(relabeled)) {
      return stranded(ended, `already re-fired after its floor stop until ${isoSecond(reset)}`, "failed-again");
    }
    const attempts = named.filter((marker) => marker.at > from).length;
    if (attempts >= limits["limit-stops-per-issue"]) {
      return stranded(ended, `${attempts} floor re-fire attempts for the reset ${isoSecond(reset)} did not restart it`, "failed-again");
    }
    const spent = new Set(markers.filter((marker) => marker.floor !== undefined && marker.at > from).map((marker) => marker.floor)).size;
    if (named.length === 0 && spent >= limits["limit-stops-per-issue"]) {
      return stranded(ended, `${spent} floor re-fires since a person last added ${LABEL} or a run last reported`, "failed-again");
    }
    const opens = floored.reset === null ? reset : spanOpens(reset, now);
    if (now < opens) {
      return { reason: `a floor stop ended its lane run after the model ran; it is re-fired from ${isoSecond(opens)}`, due: opens };
    }
    if (await wipCapped()) {
      return { reason: "a floor stop ended its lane run, and the issue lane is paused over its WIP cap" };
    }
    return {
      reason: null,
      resets: ended,
      refire: await workflowKey(),
      recorded: false,
      floor: { run: floored.run.id, reset, named: floored.reset !== null, server: floored.server },
      ...(floored.reset !== null && { closes: opens + FLOOR_SPAN_MS }),
    };
  }
  if (!stale && !runs.some((run) => FAILED.has(run.conclusion)) && !(await stoppedMint(jobsOf, runs)) && !(await cancelledBeforeWork(jobsOf, runs))) {
    return stranded(ended, "its lane run did not fail", "no-report");
  }
  const key = await workflowKey();
  const recorded = firedOn(key);
  if (recorded.some(relabeled)) {
    return stranded(ended, `already re-fired for workflow files ${key}`, "failed-again");
  }
  return { reason: null, resets: addedAt, refire: key, recorded: recorded.length > 0 };
}

async function restartRefusal({ github, actions, jobLog, carry, repo, issue, bot, humans, now, workflowKey, limits, wipCapped, read, statusOf, runsOf, upstreamClear }) {
  const holds = (await fieldNamesOf(statusOf, issue)).filter((label) => HOLDS.has(label));
  const held = holds.length > 0;
  if (held && (holds.length > 1 || holds[0] !== HUMAN_LABEL)) {
    return { reason: `held by ${holds.find((label) => label !== HUMAN_LABEL)}` };
  }
  const comments = await read("comments");
  const markers = appMarkers(comments, bot);
  const marker = markers.filter((item) => item.outcome !== "refired").at(-1);
  const events = await read("events");
  const labelEvents = events.filter((event) => isLabel(event, "labeled") || isLabel(event, "unlabeled"));
  const newestLabel = labelEvents.at(-1);
  if (newestLabel !== undefined && isLabel(newestLabel, "unlabeled") && !isRestart(events, events.lastIndexOf(newestLabel), markers, bot)) {
    return { reason: `${LABEL} was removed` };
  }
  const lastAdd = events.filter((event) => isLabel(event, "labeled")).at(-1);
  const addedAt = Date.parse(lastAdd?.created_at);
  if (Number.isFinite(addedAt) && (marker === undefined || addedAt > marker.at)) {
    return refireRefusal({ github, actions, jobLog, carry, repo, number: issue.number, issue, lastAdd, addedAt, markers, comments, events, humans, bot, workflowKey, held, limits, now, wipCapped, runsOf, upstreamClear });
  }
  if (held) {
    return { reason: `held by ${HUMAN_LABEL}` };
  }
  if (marker?.outcome === "failed") {
    return { reason: `a failed stop left ${LABEL} on`, fail: { finish: true } };
  }
  const addedSince = (by) =>
    events.filter((event) => isLabel(event, "labeled") && by(event)).reduce((latest, event) => Math.max(latest, Date.parse(event.created_at)), Number.NEGATIVE_INFINITY);
  const since = addedSince((event) => event.actor?.login !== bot);
  if (marker?.outcome === "wait" && marker.pr) {
    const pull = await github("GET", `/repos/${repo}/pulls/${marker.pr}`);
    if (pull?.state === "open") {
      return { reason: `waiting on pull request #${marker.pr}` };
    }
  }
  const bound = CAPPED_RESTARTS[marker?.outcome];
  if (bound) {
    const humanSince = addedSince((event) => humans.has(event.actor?.id));
    const caps = markers.filter((item) => item.outcome === marker.outcome && item.at > humanSince).length;
    return caps > limits[bound]
      ? { reason: `${caps} ${marker.outcome} stops since a person last added ${LABEL}` }
      : { reason: null, resets: marker.at };
  }
  const funding = marker?.outcome === "funding";
  if (!funding && marker?.outcome !== "limited") {
    return { reason: "no limit stop is its newest lane outcome" };
  }
  // A limit or funding stop (ci-workflows#781) that keeps stopping the lane
  // spends the per-issue cap and takes the fail route: count both since a
  // person last added agent-ready.
  const stops = markers.filter((item) => (item.outcome === "limited" || item.outcome === "funding") && item.at > since).length;
  if (stops >= limits["limit-stops-per-issue"]) {
    return { reason: `${stops} limit stops since a person last added ${LABEL}`, fail: { stops, run: marker.run, onResumed: marker.onResumed } };
  }
  const resets = clampReset(marker.resets, marker.at, limits);
  if (now < resets) {
    return { reason: `waiting for the limit to reset at ${new Date(resets).toISOString()}`, due: resets };
  }
  return { reason: null, resets };
}

async function restartLimited({ github, actions, jobLog, carry, repo, bot, humans, appId, now, limits, status, cap = limits["restarts-per-run"], writer = NO_WRITER, statusOf, openIssues, byStatus, field, fieldRows, slots = laneSlots, clock = Date.now, deadline = Number.POSITIVE_INFINITY, upstream = checkUpstreamStatus, maps = NO_MAPS }) {
  let failed = 0;
  const ready = [];
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
  const wipCapped = () => status().then((s) => s.paused);
  let upstreamRead;
  const upstreamClear = () =>
    (upstreamRead ??= (async () => {
      try {
        const { degraded, reason } = await upstream();
        console.log(`label-unblocked: upstream status for runs its stop skipped: degraded=${degraded} reason=${escapeCommand(reason)}`);
        return degraded === "false" && reason === "ok";
      } catch (error) {
        console.log(`::warning title=label-unblocked::the upstream status was not read, so a run its stop skipped waits: ${escapeCommand(error?.message ?? error)}`);
        return false;
      }
    })());
  let flight;
  const inFlight = () => (flight ??= actions ? runsInFlight(actions, repo) : Promise.resolve(null));
  let open;
  try {
    const found = byStatus ? await byStatus([LABEL]) : null;
    if (found && !openIssues) {
      throw new Error("the open-issue listing was not read");
    }
    const labelOnly = (found ?? []).filter((item) => item.state === null);
    if (labelOnly.length > 0) {
      console.log(`label-unblocked: not restarted, agent-ready label with no Work status: ${labelOnly.map((item) => `#${item.number}`).join(", ")}`);
    }
    const numbers = found && new Set(found.filter((item) => item.state !== null).map((item) => Number(item.number)));
    open = (found ? openIssues.filter((item) => numbers.has(Number(item.number))) : await paginate(github, `/repos/${repo}/issues?state=open&labels=${LABEL}`)).filter(
      (item) => !item.pull_request && NUMBER.test(String(item.number)) && !maps.skip(item),
    );
  } catch (error) {
    reportHold(LABEL, error);
    return 0;
  }
  const doneBy = mergedRefsReader({ github, repository: repo, numbers: open.map((item) => Number(item.number)), humans, appId });
  const listings = new Map();
  const readsOf = (issue) => {
    if (!listings.has(issue.number)) {
      const listed = {};
      const rowsOf = statusOf?.fieldRows ?? fieldRows;
      const history = async () => {
        const events = await eventsOf(github, repo, statusOf, issue.number);
        return fieldRows ? mergeByTime(events, agentReadyEvents(await rowsOf(issue.number), { field, bot, humans })) : events;
      };
      const read = (kind) => (listed[kind] ??= kind === "events" ? history() : paginate(github, `/repos/${repo}/issues/${issue.number}/${kind}`));
      listings.set(issue.number, read);
    }
    return listings.get(issue.number);
  };
  const runsOf = sharedLaneRuns(actions, repo);
  const decidedAt = (issue) => carry?.decidedAt(Number(issue.number)) ?? Number.NEGATIVE_INFINITY;
  const sorted = open.map((issue, at) => ({ issue, at, decided: decidedAt(issue) })).sort((a, b) => a.decided - b.decided || a.at - b.at);
  const carriedOf = (issue) => carry?.carriedWait(Number(issue.number));
  const current = sorted.some(({ issue }) => carriedOf(issue)) ? await workflowKey().catch(() => null) : null;
  const stands = (issue) => {
    const wait = carriedOf(issue);
    return Boolean(wait && current && wait.key === current && wait.updated === issue.updated_at && now < wait.due);
  };
  const order = [];
  for (const { issue } of sorted) {
    if (stands(issue)) {
      carry.keepDecided(Number(issue.number), carriedOf(issue));
      console.log(`label-unblocked: #${issue.number} not restarted: ${carriedOf(issue).reason} (carried: unchanged since it was decided)`);
    } else {
      order.push(issue);
    }
  }
  console.log(`::notice title=label-unblocked::${order.length} agent-ready issue(s) to decide, ${sorted.length - order.length} carried waiting from an earlier sweep`);
  const keepWait = async (issue, verdict) => {
    const number = Number(issue.number);
    const due = verdict?.reason ? verdict.due : undefined;
    const key = Number.isFinite(due) && typeof issue.updated_at === "string" ? await workflowKey().catch(() => null) : null;
    carry?.keepDecided(number, key ? { reason: verdict.reason, due, updated: issue.updated_at, key } : undefined);
  };
  for (const [index, issue] of order.entries()) {
    if (clock() >= deadline) {
      console.log(`::notice title=label-unblocked::the sweep's time budget ran out: ${order.length - index} of ${order.length} agent-ready issue(s) left for the next sweep, which decides them first`);
      break;
    }
    carry?.keepDecided(Number(issue.number));
    const read = readsOf(issue);
    try {
      const verdict =
        (await recurrenceRefusal({ github, repo, issue, bot, humans, inFlight, read, statusOf, now, limits })) ??
        (await restartRefusal({ github, actions, jobLog, carry, repo, issue, bot, humans, now, workflowKey, limits, wipCapped, read, statusOf, runsOf, upstreamClear }));
      const { reason, fail } = verdict;
      if (carry && reason !== null && !fail) {
        await keepWait(issue, verdict);
      }
      if (fail) {
        const base = `/repos/${repo}/issues/${issue.number}`;
        if (!fail.finish) {
          await github("POST", `${base}/comments`, { body: failedComment(fail) });
        }
        await writer.leaveAgentReady(Number(issue.number), "confirmed");
        console.log(`label-unblocked: #${issue.number} failed: ${reason}`);
        continue;
      }
      if (reason !== null) {
        console.log(`label-unblocked: #${issue.number} not restarted: ${reason}`);
        continue;
      }
      const done = verdict.refire ? await doneBy(issue.number) : [];
      if (done.length > 0) {
        const pr = done.at(-1);
        const explained = appPosted(await read("comments"), bot, handedMarker(pr));
        console.log(`label-unblocked: #${issue.number} not re-fired: ${doneReason(done)}`);
        ready.push({ number: Number(issue.number), had: labelNames(issue), resets: verdict.resets, handOff: "merged", pr, explained });
        continue;
      }
      ready.push({ ...verdict, number: Number(issue.number), had: labelNames(issue) });
    } catch (error) {
      failed += failedFor(github, issue.number, error);
    }
  }
  ready.sort((a, b) => Number(Boolean(b.floor)) - Number(Boolean(a.floor)) || a.resets - b.resets || a.number - b.number);
  console.log(`label-unblocked: ${ready.filter((item) => item.recurrence).length} reopened fix issue(s) to relabel`);
  const newFloor = (item) => item.floor && !item.recorded;
  let floorRoom = 0;
  if (ready.some(newFloor)) {
    try {
      const since = now - HOUR_MS;
      const recent = await paginate(github, `/repos/${repo}/issues/comments?since=${encodeURIComponent(new Date(since).toISOString())}`);
      const spent = recent.filter((comment) => comment.user?.login === bot && parseMarker(comment.body)?.floor !== undefined && Date.parse(comment.created_at) >= since).length;
      floorRoom = Math.max(0, slots() - spent);
      console.log(`label-unblocked: ${spent} floor re-fire(s) in the last hour, room for ${floorRoom}`);
    } catch (error) {
      reportHold("floor re-fire record", error);
    }
  }
  const paced = (item) => item.stall === "breaker" || item.stall === "outage";
  const budgeted = (item) => item.stall === "breaker" && item.trip?.budget;
  let room = 0;
  let budgetRoom = 0;
  if (ready.some(paced)) {
    try {
      const target = limits["refire-queue-per-slot"] * slots();
      const budgetTarget = limits["refire-budget-per-slot"] * slots();
      const unfinished = await inFlight();
      const minutes = limits["stale-queued-minutes"];
      const stale = unfinished.filter((run) => staleQueued(run, now, minutes)).length;
      if (stale > 0) {
        console.log(`::notice title=label-unblocked::${stale} work-resolve-issue run(s) queued ${minutes}+ minutes not counted toward the kill-switch re-fire room: GitHub lost them and never starts them (limits.stale-queued-minutes)`);
      }
      const queued = unfinished.length - stale;
      room = Math.max(0, target - queued);
      console.log(`label-unblocked: ${queued} work-resolve-issue run(s) unfinished, kill-switch re-fire room ${room} of ${target}`);
      if (ready.some(budgeted)) {
        budgetRoom = Math.max(0, budgetTarget - queued);
        console.log(`label-unblocked: budget-stop re-fire room ${budgetRoom} of ${budgetTarget}`);
      }
    } catch (error) {
      reportHold("kill-switch re-fire queue", error);
    }
  }
  const go = ready.filter((item) => {
    if (newFloor(item) && floorRoom-- <= 0) {
      console.log(`label-unblocked: #${item.number} floor re-fire deferred: the last hour's batch is spent`);
      return false;
    }
    if (budgeted(item) && room > 0 && budgetRoom-- <= 0) {
      console.log(`label-unblocked: #${item.number} budget-stop re-fire deferred: the issue lane's queue is at its budget-stop re-fire target`);
      return false;
    }
    if (!paced(item)) {
      return true;
    }
    if (room-- > 0) {
      if (!budgeted(item)) {
        budgetRoom--;
      }
      return true;
    }
    console.log(`label-unblocked: #${item.number} re-fire deferred: the issue lane's queue is at its kill-switch re-fire target`);
    return false;
  });
  for (const { number } of go.slice(cap)) {
    console.log(`label-unblocked: #${number} restart deferred: ${cap} restarts this run`);
  }
  for (const { number, refire, cause, stall, trip, floor, closes, recurrence, recorded, handOff, pr, explained, release, infra, had } of go.slice(0, cap)) {
    const base = `/repos/${repo}/issues/${number}`;
    if (closes !== undefined && clock() >= closes) {
      console.log(`label-unblocked: #${number} re-fire left for the next window: its span closed at ${isoSecond(closes)}`);
      continue;
    }
    if (handOff) {
      try {
        if (!explained) {
          await github("POST", `${base}/comments`, { body: handOff === "merged" ? refsMergedComment(pr) : refsClosedComment(pr) });
        }
        if (await heldOnSet(writer, number, "needs-triage")) {
          continue;
        }
        console.log(`label-unblocked: #${number} handed to triage: PR #${pr} ${handOff === "merged" ? "merged with Refs:" : "closed unmerged"}`);
      } catch (error) {
        failed += failedFor(github, number, error);
      }
      continue;
    }
    try {
      if (refire && !recorded) {
        const body = floor ? floorComment(refire, { repo, ...floor }) : stall === "breaker" ? breakerComment(refire, { repo, ...trip }) : refireComment(refire, cause);
        await (trip?.record === undefined
          ? github("POST", `${base}/comments`, { body })
          : github("PATCH", `/repos/${repo}/issues/comments/${trip.record}`, { body }));
      }
      if (infra) {
        await (infra.id === undefined
          ? github("POST", `${base}/comments`, { body: infra.body })
          : github("PATCH", `/repos/${repo}/issues/comments/${infra.id}`, { body: infra.body }));
      }
      if (recurrence && !recorded) {
        await github("POST", `${base}/comments`, { body: recurrenceComment(recurrence) }).catch((error) =>
          console.log(`::warning title=label-unblocked::#${number}: the relabel record was not posted: ${escapeCommand(error?.message ?? error)}`),
        );
      }
    } catch (error) {
      failed += failedFor(github, number, error);
      continue;
    }
    try {
      const restarted = await writer
        .restart(number, { from: [LABEL] })
        .catch(() => writer.restart(number, { from: [LABEL, null] }));
      if (restarted?.outcome === "held" || restarted?.outcome === "moved") {
        console.log(`label-unblocked: #${number} left as is: its Work status is now ${restarted.state ?? "unset"}`);
        continue;
      }
      const why = infra ? "re-fired on a backoff" : floor ? "re-fired early in a window after its floor stop" : stall === "breaker" ? (trip?.budget ? "re-fired after a start-gate budget stop" : "re-fired after a kill-switch refusal") : stall === "outage" ? "re-fired after its upstream-status skip" : refire ? "re-fired after its failed run" : recurrence ? "relabeled after its reopen on a repeat failure" : "restarted after its limit stop";
      console.log(`label-unblocked: #${number} ${why}`);
    } catch (error) {
      failed += 1;
      reportError(number, new Error(`the restart did not set the Work status to ${LABEL}: ${error?.message ?? error}`));
    }
  }
  return failed;
}

const SPLIT_CLOSED = "<!-- work-unblock split parent closed -->";

async function isTrustedClose(github, repo, issue, humans, bot) {
  const trusted = async (number) => isTrustedClose(github, repo, await github("GET", `/repos/${repo}/issues/${number}`), humans, bot);
  const isApp = byBot(bot);
  return (await closedByHumanOrMerge(github, repo, issue, humans, isApp)) || splitParentClosed({ github, repository: repo, issue, isApp, humans, trusted });
}

async function closeSplitParents({ github, repo, closed, sweep, humans, bot, closes = new Map(), writer = NO_WRITER, statusOf, maps = NO_MAPS }) {
  let failed = 0;
  for (const number of closed) {
    try {
      await closeSplitParent({ github, repo, number, humans, closes, bot, sweep, writer, statusOf, maps });
    } catch (error) {
      failed += failedFor(github, number, error);
    }
  }
  return failed;
}

async function closeSplitParent({ github, repo, number, humans, closes, bot, sweep, writer, statusOf, maps }) {
  const { issue, trusted } = sweep ? await readClose({ github, repo, number, humans, closes, bot }) : { issue: await github("GET", `/repos/${repo}/issues/${number}`), trusted: true };
  if (!issue?.parent_issue_url || !trusted) {
    return;
  }
  const parent = await github("GET", `/repos/${repo}/issues/${number}/parent`);
  if (!maps.skip(parent)) {
    await closeDoneParent({ github, repo, parent, humans, closes, bot, writer, statusOf });
  }
}

async function rescanSplitParents({ github, repo, listed, humans, bot, cap, now, writer = NO_WRITER, statusOf, maps = NO_MAPS }) {
  const hour = new Date(now).getUTCHours();
  const done = (item) => (item.sub_issues_summary?.total ?? 0) > 0 && item.sub_issues_summary.completed === item.sub_issues_summary.total;
  const due = listed.filter((item) => done(item) && Number(item.number) % 24 === hour && !maps.skip(item));
  if (due.length === 0) {
    return 0;
  }
  console.log(`label-unblocked: ${due.length} open issue(s) with every sub-issue completed in this hour's rotation; checking up to ${cap} (limits.parent-rescan-per-run)`);
  const closes = new Map();
  let failed = 0;
  for (const item of due.slice(0, cap)) {
    try {
      await closeDoneParent({ github, repo, parent: await github("GET", `/repos/${repo}/issues/${item.number}`), humans, closes, bot, writer, statusOf });
    } catch (error) {
      failed += failedFor(github, item.number, error);
    }
  }
  return failed;
}

async function closeDoneParent({ github, repo, parent, humans, closes, bot, writer = NO_WRITER, statusOf }) {
  if (parent?.state !== "open" || !NUMBER.test(String(parent.number)) || !String(parent.repository_url ?? "").toLowerCase().endsWith(`/repos/${repo}`.toLowerCase())) {
    return;
  }
  const base = `/repos/${repo}/issues/${parent.number}`;
  const comments = await paginate(github, `${base}/comments`);
  const children = await paginate(github, `${base}/sub_issues`);
  let names;
  const namesOf = async () => (names ??= fieldNamesOf(statusOf, parent));
  try {
    if (await refreshSplitWait({ github, repo, parent, names: await namesOf(), comments, open: async () => children.filter((child) => child?.state !== "closed"), bot })) {
      console.log(`label-unblocked: #${parent.number} admission comment now names its open sub-issues`);
    }
  } catch (error) {
    console.log(`::warning::label-unblocked: #${parent.number} admission comment not refreshed: ${escapeCommand(error?.message ?? error)}`);
  }
  const trusted = async (child) => NUMBER.test(String(child)) && trustedClose({ github, repo, number: Number(child), humans, closes, bot });
  const leftOpen = await splitLeftOpen({ github, repository: repo, issue: parent, comments, children, isApp: byBot(bot), humans, trusted });
  if (leftOpen) {
    console.log(`label-unblocked: #${parent.number} stays open: ${leftOpen}`);
    await reenterFinished({ github, repo, parent, names: await namesOf(), comments, children, trusted, bot, writer, statusOf });
    return;
  }
  if (!appPosted(comments, bot, SPLIT_CLOSED)) {
    await github("POST", `${base}/comments`, {
      body: `${SPLIT_CLOSED}\nEvery sub-issue of this split is closed as completed by a listed human or a merge (${children.map((child) => `#${child.number}`).join(", ")}), so the lanes App closes it as completed.`,
    });
  }
  await github("PATCH", base, { state: "closed", state_reason: "completed" });
  const states = await stripStateLabels(github, base, unstatused(parent));
  console.log(`label-unblocked: split parent #${parent.number} closed as completed; removed ${states.length} state label(s)`);
  await writer.leaveAgentReady(Number(parent.number), "needs-triage");
}

async function reenterFinished({ github, repo, parent, names, comments, children, trusted, bot, writer, statusOf }) {
  const parkedDone = comments.some((comment) => comment.user?.login === bot && String(comment.body ?? "").startsWith(ADMIT_MARKER) && String(comment.body).includes(SIZE_SPLIT_DONE));
  if (!parkedDone || !confirmedOnly(names) || children.length === 0 || (await subIssueLeftOpen(children, trusted, repo)) !== null) {
    return false;
  }
  const parkedAt = Date.parse(newestAdd(await eventsOf(github, repo, statusOf, parent.number), CONFIRMED)?.created_at);
  if (!(await handBackParked({ github, repo, number: parent.number, had: labelNames(parent), comments, parkedAt, isApp: byBot(bot), writer, why: "Every sub-issue of this split closed as completed," }))) {
    console.log(`label-unblocked: #${parent.number} set to needs-triage: every sub-issue closed as completed, so the triage sweep sends it to intake for one verified-done run`);
  }
  return true;
}

const WAIT_PREFIX = "Not admitted to the issue lane yet: ";

async function refreshSplitWait({ github, repo, parent, names: labels, comments, open, bot }) {
  if (!labels.includes(READY) || labels.includes(LABEL) || labels.includes(DEFERRED_LABEL) || labels.some((label) => HOLDS.has(label)) || parent.issue_dependencies_summary?.blocked_by !== 0) {
    return false;
  }
  const own = comments.find((comment) => comment.user?.login === bot && String(comment.body ?? "").startsWith(`${ADMIT_MARKER}\n${WAIT_PREFIX}`));
  const reasons = String(own?.body ?? "")
    .slice(`${ADMIT_MARKER}\n${WAIT_PREFIX}`.length)
    .replace(/\.$/, "")
    .split("; ");
  if (!own || !reasons.every((reason) => SPLIT_PENDING.has(reason) || /^sub-issue #\d+ is open$/.test(reason))) {
    return false;
  }
  const children = await open();
  const body = `${ADMIT_MARKER}\n${WAIT_PREFIX}${children.map((child) => subIssueWait(child.number)).join("; ")}.`;
  if (children.length === 0 || own.body === body) {
    return false;
  }
  await github("PATCH", `/repos/${repo}/issues/comments/${own.id}`, { body });
  return true;
}

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

const fieldListing = (env, github, repo) => {
  let loaded;
  let listing;
  let sharedFailed = false;
  return async (states) => {
    loaded ??= (async () => {
      const { issueStatusFromBase, issuesByStatus } = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
      const config = issueStatusFromBase(env);
      return config ? { config, trustedActors: loadTrustedActors(env), issuesByStatus } : null;
    })();
    const setup = await loaded;
    if (!setup) {
      return null;
    }
    const { config, trustedActors, issuesByStatus } = setup;
    const own = () => issuesByStatus(github, repo, states ?? Object.keys(config.labels), { config, trustedActors });
    let found;
    if (sharedFailed) {
      found = await own();
    } else {
      listing ??= issuesByStatus(github, repo, Object.keys(config.labels), { config, trustedActors });
      try {
        found = await listing;
      } catch (error) {
        sharedFailed = true;
        listing = undefined;
        console.log(`::warning title=label-unblocked::the shared Work status listing failed (${error?.message ?? error}); each pass lists its own states`);
        found = await own();
      }
    }
    const wanted = states && new Set(states.flatMap((state) => config.labels[state] ?? []).map((label) => label.toLowerCase()));
    const kept = wanted ? found.filter((item) => (item.state === null ? item.labels.some((label) => wanted.has(label.toLowerCase())) : states.includes(item.state))) : found;
    return Object.defineProperty(
      kept.map((item) => ({ ...item, labels: statusLabels(item.state, item.labels, config) })),
      "held",
      { value: found.held ?? [] },
    );
  };
};

async function workStatusField(env, github, repo) {
  try {
    const { fieldEvents, issueStatusFromBase } = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
    const field = issueStatusFromBase(env)?.["field-id"];
    return field === undefined ? {} : { field, fieldRows: (number) => fieldEvents(github, repo, number) };
  } catch (error) {
    console.log(`::warning title=label-unblocked::the Work status config could not be read, so no restart is written: ${escapeCommand(error?.message ?? error)}`);
    return {};
  }
}

async function listedNames(byStatus) {
  const found = byStatus ? await byStatus() : null;
  if (!found) {
    return labelNames;
  }
  const names = new Map(found.map((item) => [Number(item.number), item.labels]));
  for (const { number } of found.held ?? []) {
    names.set(Number(number), []);
  }
  return (item) => names.get(Number(item.number)) ?? labelNames(item);
}

export { budgetLatch, failedFor, fieldListing, markReads };

export async function main({ env = process.env, github, actions, jobLog, now = Date.now(), rate = searchRateLimit(), admission = baseAdmission(env), writer, statusOf, byStatus, statusField, slots, clock = Date.now, upstream } = {}) {
  const deadline = clock() + sweepBudgetMs(env);
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const sweep = ["schedule", "workflow_dispatch", "workflow_run"].includes(env.GITHUB_EVENT_NAME);
    const event = sweep ? {} : JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, "utf8"));
    if (!sweep && (env.GITHUB_EVENT_NAME !== "issues" || event.action !== "closed" || !NUMBER.test(String(event.issue?.number)))) {
      throw new Error("this runs only on an issue closing, on the schedule, by hand or after a work-resolve-issue run");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("label-unblocked: the lanes kill switch stops this run; nothing read or labeled");
      return 0;
    }
    if (!sweep) {
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
    const routing = readRouting(join(env.BASE_PATH || ".base", "docs/conventions/work-items.yaml"), { who: "label-unblocked" });
    const maps = mapSkipper(routing);
    const own = Boolean(github);
    github = markReads(github ?? createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, onResponse: rate.onResponse }));
    const writeTo = writer ?? (own ? NO_WRITER : await statusWriter({ env, github, repository: repo }));
    const statusTo = statusOf ?? (own ? undefined : statusReader({ env, github, repository: repo }));
    const queuedStatus = statusOf ?? (own ? undefined : listedStatusOf({ env, github, repository: repo }));
    const listing = byStatus ?? (own ? undefined : fieldListing(env, github, repo));
    if (sweep) {
      const latch = budgetLatch("github-token");
      actions ??= env.ACTIONS_TOKEN ? createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, latch }) : null;
      jobLog ??= env.ACTIONS_TOKEN ? createJobLogReader({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, latch }) : null;
      actions = actions && markReads(actions);
    }
    const carry = sweep && env.VERDICTS_OUT ? loadCarry(env.VERDICTS_IN, now) : null;
    const window = sweep ? await sweepSince({ actions, jobLog, repo, now, runId: env.GITHUB_RUN_ID }) : null;
    let closed = sweep ? [] : [Number(event.issue.number)];
    if (sweep) {
      try {
        closed = await closedSince(github, repo, new Date(window.since));
      } catch (error) {
        reportHold("closed-issue", error);
        return 0;
      }
      console.log(LISTED_LINE);
      const minutes = Math.round((now - window.since) / 60_000);
      console.log(`label-unblocked: ${closed.length} issue(s) closed in the last ${minutes} minutes (${window.why})`);
    }
    const bot = env.LANES_BOT_LOGIN || DEFAULT_BOT;
    const appId = logins.get(bot);
    const resolved = env.RESOLVED_CONFIG || `${env.RUNNER_TEMP ?? ""}/resolved-config.json`;
    const limits = readLimits(resolved);
    const wip = readWip(resolved);
    let read;
    const status = () => (read ??= checkWip(github, { repo, bot, now, limits, wip, remaining: rate.remaining, statusOf: queuedStatus, routing }));
    const gate = admissionGate(status);
    let failed = sweep ? await admitDeferred({ github, repo, humans, bot, gate, appId, admission, writer: writeTo, statusOf: statusTo, byStatus: listing, maps }) : 0;
    const closes = new Map();
    failed += await labelUnblocked({ github, repo, closed, sweep, humans, bot, gate, appId, admission, writer: writeTo, closes, statusOf: statusTo, maps });
    failed += await closeSplitParents({ github, repo, closed, sweep, humans, bot, closes, writer: writeTo, statusOf: statusTo, maps });
    if (!sweep) {
      failed += await stripClosed({ github, repo, number: Number(event.issue.number), writer: writeTo });
    } else {
      let listed;
      try {
        listed = (await paginate(github, `/repos/${repo}/issues?state=open&sort=updated&direction=asc`)).filter((item) => !item.pull_request && NUMBER.test(String(item.number)));
      } catch (error) {
        reportHold("open", error);
      }
      if (listed) {
        failed += await rescanSplitParents({ github, repo, listed, humans, bot, cap: limits["parent-rescan-per-run"], now, writer: writeTo, statusOf: statusTo, maps });
        let names;
        try {
          names = await listedNames(listing);
        } catch (error) {
          reportHold("Work status", error);
        }
        if (names) {
          failed += await readmitReady({ github, repo, listed, names, humans, bot, gate, appId, admission, cap: limits["readmit-per-run"], now, writer: writeTo, statusOf: statusTo, maps });
          failed += await reenterStopped({ github, repo, listed, names, humans, bot, writer: writeTo, statusOf: statusTo, maps });
        }
      }
      failed += await restartLimited({ github, actions, jobLog, carry, repo, bot, humans, appId, now, limits, status, slots: slots ?? (() => laneSlots({ laneLevel: resolvedLaneLevel(resolved), env })), writer: writeTo, statusOf: statusTo, openIssues: listed, byStatus: listing, clock, deadline, upstream, maps, ...(statusField ?? (own ? {} : await workStatusField(env, github, repo))) });
      if (carry) {
        const { jobsHit, jobsRead, refusalsHit, refusalsRead } = carry.counts;
        console.log(`::notice title=label-unblocked::carried verdicts: ${jobsHit} job listing(s) and ${refusalsHit} log verdict(s) reused, ${jobsRead} and ${refusalsRead} read`);
        if (carry.save(env.VERDICTS_OUT)) {
          markSaved(env);
        }
      }
    }
    const left = maps.notice();
    if (left) {
      console.log(left);
    }
    if (github.held > 0) {
      console.log(HELD_LINE);
    }
    if (sweep && failed === 0 && !(github.held > 0) && env.GITHUB_OUTPUT) {
      appendFileSync(env.GITHUB_OUTPUT, "clean-sweep=true\n");
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
