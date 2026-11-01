// Starts pr-unblock's address-feedback activity on a lanes App PR, or an
// adopted owner PR once idle (ownerAuthored, ownerSkip), once both
// review lanes have reviewed its current head and left an unresolved thread.
// Run by .github/workflows/pr-feedback-dispatch.yml on workflow_run, after the
// kill switch. From the event file it takes only the upstream run's id, path,
// event, repositories and head SHA, which a re-run does not change, so reading
// them back from the API would spend a call for the same values; and its
// status and start time, snapshots from when the event fired, used only to
// skip, never to admit. Nothing user-written in the payload (branch name,
// title) is read, and nothing reaches a shell. Every PR fact, including whether
// that head is still the PR's current head, is read fresh from the API.
//
// It dispatches pr-unblock.yml on main, with activity address-feedback, only
// when all of these hold, and otherwise logs why not and dispatches nothing:
// - the upstream run is a completed pull_request run of a review workflow,
//   by exact path, in this repository and on a head of this repository;
// - exactly one open, non-draft PR into main has that run's head SHA as its
//   current head, and the lanes App opened it, or a person on the base's
//   trusted-actors list did under an `adoption` section, with no `Hold:` body
//   line and the PR and its head commit idle-hours old; on such an owner PR
//   only a thread the select job keeps dispatches;
// - it carries no do-not-merge label;
// - both review lanes' newest reviewed-head markers, written by
//   github-actions[bot], name that head;
// - an unresolved review thread exists that address-feedback would work:
//   every comment is the reviewer bot's or a listed review bot's
//   (REVIEWER_IDS, pr-pipeline.yaml review-threads.reviewer-ids; a listed
//   bot's only behind a trusted person's `@codex` request, requestSkip), a trusted
//   person with write access
//   asked the lane to fix it (isFixRequest), in a bot's thread or one a
//   trusted person opened, or a trusted person answered the
//   lane's escalation (address-feedback.mjs threadAuthors); on a PR carrying
//   the human-gated label, the same when a lane escalation put the label on
//   and no review lane holds the PR (gate-source.mjs gateSource), on an owner
//   PR only as it lets fix-ci work there (prHold),
//   otherwise only a thread where a trusted person with write access asked
//   the lane to fix it (isFixRequest);
// - that head has no pr-unblock / address-feedback check run yet (one the
//   usage limit stopped stops counting once its limit resets, and one that
//   started before the head's newest pr-unblock / publish-feedback check run
//   when that run skipped no-model-turn, finding-stands, lane-stopped or
//   kill-switch: that round left the head for another round; a kill-switch
//   stop of the address-feedback run itself does not count either), and no
//   pr-unblock.yml address-feedback run for the PR is still queued or going;
// - the base config's pr-unblock lane is enabled, holds enabled
//   address-feedback and publish-feedback slots, and address-feedback applies
//   to that PR at that head, resolved by resolve-config for that one slot.
// The gate and the broker re-check the upstream run and the head; this script
// only decides whether to spend a run.
//
// A completed pr-verify run starts the file too, once its post-verify-notes
// job has posted a fail verdict's notes on the PR (verify-notes.mjs). For
// that run, which ran on main, main() takes the head the notes name
// (VERIFY_HEAD_SHA) and decides as above with the newest completed review
// run at that head as the upstream (reviewRunAt); with none, the review run
// that completes later dispatches. The dispatched-run record names that review
// run, so the gate and the broker check one kind of upstream. The notes are
// new work at a head an earlier round may have handled, so that dispatch
// counts only check runs started after the pr-verify run was created
// (notesSince, read back from the API) and skips the head's handled record.
// A pr-verify pass whose post-verify-notes job found an open fail-note
// thread from an earlier head names its head in VERIFY_PASS_HEAD_SHA instead.
// That dispatch is a pass-only round (input verify-pass-head): it runs no
// model and posts no address-feedback check, its reply job resolves those
// threads as the lanes App, so neither the review markers, a workable thread,
// the human gate (a needs-human PR dispatches here whoever applied the label)
// nor the head's check runs decide it; the hold labels still skip it. It only
// resolves notes a later pr-verify pass superseded, and the needs-human label
// it leaves on still blocks the merge. A pass-only round goes only to lanes
// App PRs: on a PR a person opened, verify-notes.mjs holds a fail with a label
// it removes itself on the next pass, so there is no thread to resolve.
//
// A round whose reply job skipped no-model-turn, finding-stands (an
// adjudicator let a disputed finding stand and the head did not move, so no
// review run follows), or kill-switch (the lanes kill switch stopped it, and
// the switch lifting starts no review run), releases its head only for the
// next review or pr-verify completion there, which may never come. So a
// completed scheduled pr-unblock-dispatch.yml run, the half-hourly tick, which
// the kill switch also stops, starts
// the file, and main() sweeps (sweepReleased): each open lanes App PR into
// main whose head's newest reply check took one of those skips, fewer than
// SWEEP_HEAD_CAP times at that head, is decided as above with the
// newest completed review run at that head as the upstream (reviewRunAt),
// which the record names. With no such head, and no stale stop, it sends the
// first idle adopted owner PR whose reviewed head has no round yet, or whose
// round's stop no thread holds any more (sweepIdleOwner), since that PR's own
// review completion found it active.
//
// Before those, the tick takes a fix request nothing else would start: no
// review run follows a reply on a head, and an earlier round's check run holds
// the head. sweepFixRequest sends each open lanes App PR into main with an
// unresolved thread the reviewer bot opened, whose newest fix request by a
// trusted person with write access came after the head's newest
// address-feedback check run, with that request's time as requestSince: as
// notesSince does for a pr-verify note, it stops the check runs started by
// then counting, but a limit stop keeps its reset hold, and the round is not
// sent for a pr-verify FAIL. A head with SWEEP_HEAD_CAP rounds or releases, or
// a run of the activity created since the request, is left alone.
//
// A sweep dispatches at most once, since the
// dispatched-run record names one upstream and one run, and keeps no record.
//
// A run of this file an outage lost, or whose dispatch job failed, dispatched
// nothing the lanes trust when re-run: check-trusted-trigger's dispatcher
// check accepts a dispatcher at attempt 1 or re-run by a listed human, so
// re-runs stay person-only. When the sweep dispatched nothing, the tick
// recovers it instead (recoverLost): one listing of this workflow's runs
// created within the reconciler's LOOKBACK_HOURS finds a run that ended in
// the reconciler's LOST set, or failed within FAILED_RUN_WINDOW_HOURS, with
// its dispatch job lost or failed after it started (a run replaced in its
// concurrency group never started one), and then each open lanes App PR into
// main short of SWEEP_HEAD_CAP, with no finished run of the activity created
// since that run, is decided as above with its head's newest completed review
// run as the upstream. The
// dispatch is this tick's own attempt-1 run, which the gate already trusts,
// and dispatchFeedback's check-run and queued-run skips keep a head the lost
// run dispatched from a second dispatch.
//
// A head the human gate skipped at its review completion has no other
// trigger once the label comes off: no round ran, so the sweep never finds a
// releasing reply there. A person's or clear-escalations' unlabel (a user or
// lanes App token, so the event starts runs) starts pr-merge.yml on
// pull_request_target, and that run's completion starts this file: main()
// takes only its head SHA and decides as above with the newest completed
// review run at that head as the upstream (reviewRunAt). The run does not say
// which label came off, so a head still gated skips at the gate as before.
// pr-merge runs on every pull_request_target event, so a head whose releasing
// skips reached SWEEP_HEAD_CAP is skipped there as the sweep skips it.
//
// Both review lanes, and any re-run, finish on one head, so a run leaves a
// record for the next run at that head (dispatch-record.mjs, carried in the
// Actions cache): a head whose check runs handle it for good, once a reply
// check started after its newest address-feedback check, is skipped before
// any read, and a head whose dispatched run for this PR is still queued or
// going is skipped after the PR read, with one read of that run in place of
// the comment, thread and run listings. Each shortcut stands for a skip the
// full path would also reach.

import { appendFileSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { commitPulls, detailSuffix, errorLabel, responseDetail } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { countRequests } from "../../actions/log-api-budget/rate-guard.mjs";
import { LOOKBACK_HOURS, LOST } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { anyListed, fixRequesters, HOLD_LINE, humanGatedLabelFrom, isFixRequest, NO_ADOPTION, onReviewedHead, ownerAdoption, ownerAuthored, readTriggers, REQUEST_HISTORY_QUERY, requestHistoryOf, requestSkip, requestSkipLine, restMentions, reviewedHeads, reviewerIdsFrom, threadAuthors, trustedHumansFrom } from "./address-feedback.mjs";

// fix-ci-dispatch.mjs imports HOLD_LINE from here.
export { HOLD_LINE, NO_ADOPTION, ownerAdoption, ownerAuthored };
import { commentItems, gateSource, listLabelEvents, prHold, reviewReader } from "./gate-source.mjs";
import { emptyRecord, isHandled, markHandled, readRecord, writeRecord } from "./dispatch-record.mjs";
import { anyHandles, KILL_SWITCH_STOP, LANE_STOP, laneStop, limitResetsAt, permanentlyHandles } from "./limit-stop.mjs";
import { budgetedFetch } from "./request-budget.mjs";
import { FAIL as VERIFY_FAIL, final as capFinal, deadlineWarning, verifyCapReader } from "./verify-cap.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  lane: "pr-unblock",
  activity: "address-feedback",
  replyActivity: "publish-feedback",
  checkName: "pr-unblock / address-feedback",
  // The reply job's check: its no-model-turn or finding-stands skip
  // releases the round's address-feedback check runs.
  replyCheckName: "pr-unblock / publish-feedback",
  reviewWorkflows: Object.freeze([
    ".github/workflows/pr-review-hosted.yml",
    ".github/workflows/pr-review-security-hosted.yml",
  ]),
  // The lanes each review workflow names in its reviewed-head marker
  // (melodic-software/ci-workflows pr-review-cli.yml).
  markerLanes: Object.freeze(["claude-review", "claude-security-review"]),
  holdLabels: Object.freeze(["do-not-merge"]),
  // claude[bot], which posted reviews before both lanes moved to pr-review-cli
  // (.github/standards/trusted-actors/trusted-actors.json). pr-review-cli posts
  // as github-actions[bot]; threadAuthors accepts those comments only when the
  // lane footer is their last line.
  reviewerId: 209825114,
  // github-actions[bot], which writes the reviewed-head markers.
  markerAuthorId: 41898282,
  // The GitHub Actions app: only a check run it created counts.
  appId: 15368,
});

const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,14}$/;

// Why an owner PR is not adopted for a round now, or "": as fix-ci adopts one
// (fix-ci-dispatch.mjs skipReason), no body line starting `Hold:` (the select
// job checks it again, as the round starts), and both
// the PR's last update and its head commit at least idle-hours old, so the
// lane does not push onto a branch a session is still working on. An
// unreadable date is not idle.
export async function ownerSkip({ api, pull, adoption, now }) {
  if (HOLD_LINE.test(String(pull.body ?? ""))) {
    return "held by a Hold: line";
  }
  const since = now - adoption.idleHours * 3_600_000;
  if (!(Date.parse(pull.updated_at ?? "") <= since) || !(Date.parse(await api.headCommittedAt(pull.head.sha)) <= since)) {
    return `owner PR or its head commit active in the last ${adoption.idleHours} hour(s)`;
  }
  return "";
}

// The tick whose completion starts the sweep.
export const SWEEP_WORKFLOW = ".github/workflows/pr-unblock-dispatch.yml";
// Releasing rounds at one head, or rounds for a fix request (sweepFixRequest),
// after which the sweep stops sending it (judgment: a third round with no model
// turn points at a cause a retry does not clear; the select job's round cap,
// address-feedback.mjs DEFAULT_MAX_ROUNDS, may end it sooner).
export const SWEEP_HEAD_CAP = 3;

const startOf = (run) => Date.parse(run.started_at ?? "");
// The reply check skips that leave the head for another round: a lane stop
// (a stop escalation-routes.json routes to a failing status) is retried on
// the same head, a fresh model session, under SWEEP_HEAD_CAP with the rest,
// and so is a kill-switch stop, which posted no reply.
const RELEASES = new Set(["Skipped: no-model-turn", "Skipped: finding-stands", LANE_STOP, KILL_SWITCH_STOP]);
const releases = (run) => run?.status === "completed" && run.conclusion === "neutral" && RELEASES.has(run.output?.title);
// A pass-only round's reply check (publish-feedback.mjs PASS_ONLY_SKIP)
// answers no thread, so it neither releases a head nor ends a release.
const roundReplies = (runs) => runs.filter((run) => run.output?.title !== "Skipped: pass-only");

// The SHA the newest marker of `lane` written by the marker author names, or "".
export function markedHead(comments, lane, markerAuthorId = DEFAULTS.markerAuthorId) {
  const prefix = `<!-- claude-lane-reviewed-head lane=${lane} sha=`;
  const marker = comments
    .filter((comment) => comment.user?.id === markerAuthorId && comment.body?.startsWith(prefix))
    .at(-1);
  const sha = marker?.body.slice(prefix.length, prefix.length + 40) ?? "";
  return SHA.test(sha) ? sha : "";
}

// threadAuthors' answer for an unresolved thread, read in full, that the select
// job keeps: it accepts the thread and its review is on a marker-confirmed
// head (onReviewedHead), unless requestSkip finds no trusted `@codex` request
// behind a listed bot's review in `mentions` and `reviews` (its reason goes to
// `log`). `heads` is reviewedHeads of the PR's issue comments.
function keptAuthors(thread, { reviewerId, reviewerIds = [], appId, trustedHumans, heads, requesters = null, fixers = requesters ?? new Set(), mentions = [], reviews = [], triggers = null, log = () => {} }) {
  if (thread.isResolved !== false || thread.comments.pageInfo?.hasNextPage === true) {
    return null;
  }
  const nodes = thread.comments.nodes;
  const authors = threadAuthors(
    nodes.map((node) => ({
      authorId: node.author?.databaseId,
      createdAt: node.createdAt,
      body: node.body,
      lastEditedAt: node.lastEditedAt,
      editorId: node.editor?.databaseId,
    })),
    { reviewerId, reviewerIds, appId, trustedHumans, requesters, fixers },
  );
  const review = nodes[0]?.pullRequestReview;
  const kept =
    authors !== null &&
    onReviewedHead({
      authors,
      firstAuthorId: nodes[0].author?.databaseId,
      review: review && { user: { id: review.author?.databaseId }, commit_id: review.commit?.oid },
      heads,
    });
  if (!kept) {
    return null;
  }
  const skip = requestSkip({
    authors,
    comments: nodes.map((node) => ({
      authorId: node.author?.databaseId,
      review: node.pullRequestReview && { authorId: node.pullRequestReview.author?.databaseId, submittedAt: node.pullRequestReview.submittedAt },
    })),
    reviews,
    mentions,
    triggers,
    reviewerIds,
    trustedHumans,
    appId,
  });
  if (skip) {
    log(requestSkipLine(thread.id, skip));
    return null;
  }
  return authors;
}

// The `@codex` request candidates and review times requestSkip reads, from
// the PR's issue comments (REST), its threads (THREADS_QUERY) and, only when
// an unresolved thread holds a listed bot's comment, one read of its reviews.
async function requestEvidence({ api, number, pull, comments, threads, reviewerIds }) {
  const listed = threads.some((thread) => thread.isResolved === false && anyListed(thread.comments.nodes.map((node) => node.author?.databaseId), reviewerIds));
  if (!listed) {
    return { mentions: [], reviews: [], triggers: null };
  }
  const [reviews, triggers] = await Promise.all([api.listReviews(number), readTriggers({ api, pr: number, pull })]);
  return {
    triggers,
    mentions: [
      ...restMentions({ issueComments: comments, reviews }),
      ...threads.flatMap((thread) => thread.comments.nodes.map((node) => ({ authorId: node.author?.databaseId, createdAt: node.createdAt, editedAt: node.lastEditedAt, body: node.body }))),
    ],
    reviews: reviews.map((review) => ({ authorId: review.user?.id, submittedAt: review.submitted_at })),
  };
}

export const hasWorkableThread = (threads, options) => threads.some((thread) => keptAuthors(thread, options) !== null);

// When the newest fix request by one of `fixers` was posted in a thread the
// select job keeps and the reviewer bot opened, in ms, or null. Direction may
// sit on any head (onReviewedHead), so no reviewed head is needed.
function newestFixRequest(threads, { fixers, ...options }) {
  const times = threads.flatMap((thread) => {
    const authors = keptAuthors(thread, { ...options, fixers, heads: new Set() });
    if (authors?.[0].author !== "reviewer") {
      return [];
    }
    return thread.comments.nodes
      .filter((node, i) => authors[i].direction === true && fixers.has(node.author?.databaseId) && isFixRequest(node.body))
      .map((node) => Date.parse(node.createdAt ?? ""));
  });
  const readable = times.filter(Number.isFinite);
  return readable.length > 0 ? Math.max(...readable) : null;
}

// fixRequesters over a PR's threads, as listReviewThreads reads them.
const threadFixers = ({ threads, trustedHumans, permission }) =>
  fixRequesters({
    comments: threads.flatMap((thread) =>
      thread.comments.nodes.map((node) => ({ authorId: node.author?.databaseId, login: node.author?.login, body: node.body })),
    ),
    trustedHumans,
    permission,
  });

export const VERIFY_WORKFLOW = ".github/workflows/pr-verify.yml";
// Its pull_request_target run follows a label coming off a PR (see main).
export const MERGE_WORKFLOW = ".github/workflows/pr-merge.yml";

// The newest completed review run of this repository's head at `head` that
// reviewed something (not skipped or cancelled), or null. A fork PR at the
// same SHA lists its runs too; one must not stand in for this repository's.
export async function reviewRunAt({ api, head, repository, settings = DEFAULTS }) {
  const runs = (await Promise.all(settings.reviewWorkflows.map((path) => api.listCompletedRuns(path, head))))
    .flat()
    .filter(
      (run) =>
        run.head_sha === head &&
        run.event === "pull_request" &&
        run.head_repository?.full_name === repository &&
        !["skipped", "cancelled"].includes(run.conclusion),
    );
  runs.sort((a, b) => Date.parse(b.created_at ?? "") - Date.parse(a.created_at ?? ""));
  return runs[0] ?? null;
}

// pr-unblock.yml's run-name, which names the activity and the PR.
export const runTitle = (activity, number) => `pr-unblock ${activity} #${number}`;

// Each workflow's run listing is read at most once a run, when a pass first
// asks; a failed read is shared too, so a rate-limited endpoint is not asked
// again.
export function shareWorkflowRuns(base) {
  const seen = new Map();
  const listWorkflowRuns = (workflow) => {
    if (!seen.has(workflow)) {
      seen.set(workflow, base.listWorkflowRuns(workflow));
    }
    return seen.get(workflow);
  };
  return { ...base, listWorkflowRuns };
}

export async function dispatchFeedback({
  api,
  repository,
  runId,
  upstream,
  appSenderId,
  resolveSlot,
  log,
  settings = DEFAULTS,
  trustedHumans = new Set(),
  reviewerIds = [],
  humanGatedLabel = "needs-human",
  now = Date.now(),
  record = emptyRecord(),
  notesSince = null,
  requestSince = null,
  passOnly = false,
  adoption = NO_ADOPTION,
  // verify-cap.mjs verifyCapReader: the cap refusal, or null.
  verifyCapped = () => null,
}) {
  const skip = (why) => {
    log(`skip: ${why}`);
    return null;
  };
  const upstreamRunId = upstream?.id;
  if (!RUN_ID.test(String(upstreamRunId)) || !RUN_ID.test(String(runId))) {
    throw new Error("the upstream or own run id is not a run id");
  }
  if (!Number.isSafeInteger(appSenderId) || appSenderId < 1) {
    throw new Error("the lanes App sender id is not a positive integer");
  }
  if (
    !settings.reviewWorkflows.includes(upstream.path) ||
    upstream.event !== "pull_request" ||
    upstream.status !== "completed" ||
    upstream.repository?.full_name !== repository ||
    upstream.head_repository?.full_name !== repository ||
    !SHA.test(upstream.head_sha ?? "")
  ) {
    return skip(`run ${upstreamRunId} is not a completed same-repository review run`);
  }
  const head = upstream.head_sha;
  const cutoff = notesSince ?? requestSince;
  if (cutoff === null && isHandled(record, settings.checkName, head)) {
    return skip(`head ${head} already has a ${settings.checkName} check run (recorded)`);
  }
  const title = (number) => runTitle(settings.activity, number);
  const reviewStarted = Date.parse(upstream.run_started_at ?? "");
  // A run of this activity for the PR, created after this review started and
  // not done, holds the dispatch (see below).
  const holds = (run, number) =>
    run.status !== "completed" && run.display_title === title(number) && !(Date.parse(run.created_at ?? "") < reviewStarted);
  const pulls = (await api.pullsForCommit(head)).filter(
    (pull) =>
      pull.state === "open" &&
      pull.head?.sha === head &&
      pull.head?.repo?.full_name === repository &&
      pull.base?.ref === settings.base,
  );
  if (pulls.length !== 1) {
    return skip(`head ${head} is the current head of ${pulls.length} open PRs into ${settings.base}`);
  }
  const [pull] = pulls;
  const number = pull.number;
  if (pull.draft !== false) {
    return skip(`#${number} is a draft`);
  }
  // A lanes App PR, or an adopted owner PR once idle. A pass-only round
  // resolves threads as the lanes App, which only its own PRs allow.
  const owner = pull.user?.id !== appSenderId;
  if (owner && (passOnly || !ownerAuthored(pull, adoption))) {
    return skip(`#${number} was not opened by the lanes App${passOnly ? "" : " or an adopted owner"}`);
  }
  if (owner) {
    const why = await ownerSkip({ api, pull, adoption, now });
    if (why) {
      return skip(`#${number}: ${why}`);
    }
  }
  const sent = record.dispatched.get(head);
  if (sent?.number === number) {
    let run = null;
    try {
      run = await api.getWorkflowRun(sent.runId);
    } catch (error) {
      log(`::warning::#${number}: could not read recorded run ${sent.runId}: ${error.message}`);
    }
    if (run && holds(run, number)) {
      return skip(`#${number}: ${settings.workflow} run ${run.id} for ${settings.activity} is not done yet (recorded)`);
    }
  }
  const held = (pull.labels ?? []).map((label) => label.name).filter((name) => settings.holdLabels.includes(name));
  if (held.length > 0) {
    return skip(`#${number} is labeled ${held.join(", ")}`);
  }
  // A pass-only round reads its own threads and runs no model, so neither the
  // review markers, a workable thread nor the human gate below decide it.
  if (!passOnly) {
    const comments = await api.listIssueComments(number);
    const unreviewed = settings.markerLanes.filter((lane) => markedHead(comments, lane, settings.markerAuthorId) !== head);
    if (unreviewed.length > 0) {
      return skip(`#${number}: ${unreviewed.join(", ")} has not marked head ${head} reviewed`);
    }
    const threads = await api.listReviewThreads(number);
    // A human-gated PR dispatches only for a thread a trusted person with
    // write access asked the lane to fix, unless a lane escalation put the
    // label on and no review lane holds the PR; on an owner PR only as that
    // escalation lets fix-ci work it (gate-source.mjs prHold). The label
    // stays on either way: clear-escalations.mjs owns taking it off.
    const labeled = (pull.labels ?? []).some((label) => label.name === humanGatedLabel);
    const timeline = async () => [...commentItems(comments), ...(await api.listLabelEvents(number))];
    let gated = false;
    let why = "";
    if (labeled && owner) {
      ({ held: gated, why } = await prHold({
        labels: pull.labels.map((label) => label.name),
        holdLabels: [],
        gateLabel: humanGatedLabel,
        head,
        activity: settings.activity,
        appId: appSenderId,
        readTimeline: timeline,
        readReviews: reviewReader(api, number),
      }));
    } else if (labeled) {
      const gate = gateSource({ timeline: await timeline(), label: humanGatedLabel, head, isLanesApp: (user) => user?.id === appSenderId && user?.type === "Bot" });
      gated = gate.source !== "lane-escalation";
      why = `${gate.source}: ${gate.reason}`;
    }
    const fixers = await threadFixers({ threads, trustedHumans, permission: api.getPermission });
    const requesters = gated ? fixers : null;
    // On an ungated head, any unresolved thread dispatches, even one the select
    // job will not keep (a reviewer the lane does not act on, a review of an
    // older head): select then escalates feedback-untaken-threads, and its
    // lane-stopped check handles the head, so the stall gets a stop once.
    const evidence = await requestEvidence({ api, number, pull, comments, threads, reviewerIds });
    const workable = hasWorkableThread(threads, { reviewerId: settings.reviewerId, reviewerIds, appId: appSenderId, trustedHumans, heads: reviewedHeads(comments), requesters, fixers, ...evidence, log });
    if (gated && !workable) {
      return skip(`#${number} is labeled ${humanGatedLabel} (${why}) and has no thread a trusted person with write access asked the lane to fix`);
    }
    if (!workable && !threads.some((thread) => thread.isResolved === false)) {
      return skip(`#${number} has no unresolved review thread`);
    }
    // On an owner PR an unresolved thread the lane does not take (one the
    // person wrote or answered) stays the person's, so it starts no round.
    if (owner && !workable) {
      return skip(`#${number} has no thread the lane works`);
    }
  }
  // Both review lanes finish on one head, and their dispatchers queue in one
  // concurrency group. The first one's run posts no check until it ends, so
  // the second skips while a run of this activity for this PR, created after
  // this review started, is not done. An older run (the round whose push made
  // this head) does not hold the dispatch, or the next round would never start.
  let runs;
  try {
    runs = await api.listWorkflowRuns(settings.workflow);
  } catch (error) {
    if (!error.rateLimited) {
      throw error;
    }
    log(`::warning::${settings.workflow} run listing is rate limited (${error.message}); #${number} not dispatched; re-run this job once the limit resets`);
    return null;
  }
  const active = runs.filter((run) => holds(run, number));
  if (active.length > 0) {
    return skip(`#${number}: ${settings.workflow} run ${active[0].id} for ${settings.activity} is not done yet`);
  }
  const resolved = await resolveSlot({ number, head });
  const enabled = (name) => resolved?.lane.slots.some((slot) => slot.name === name && slot.enabled === true);
  if (resolved?.lane.enabled !== true || !enabled(settings.activity) || !enabled(settings.replyActivity)) {
    return skip(`the ${settings.lane} lane has no enabled ${settings.activity} and ${settings.replyActivity} slots`);
  }
  if (resolved.selected?.applies !== true) {
    return skip(`#${number}: ${settings.activity} does not apply (${resolved.selected?.["skip-reason"] ?? "unknown"})`);
  }
  if (!passOnly) {
    // NaN compares false, so a run with no readable start still counts.
    const sinceNotes = (run) => cutoff === null || !(Date.parse(run.started_at ?? "") <= cutoff);
    // A fix request does not lift a limit stop's reset hold.
    const counts = (run) => sinceNotes(run) || (requestSince !== null && limitResetsAt(run, resolved.limits) !== null);
    let existing = (await api.listCheckRuns({ sha: head, checkName: settings.checkName, appId: settings.appId })).filter(counts);
    // A round whose reply job skipped no-model-turn (decided from the scan
    // job's outputs and the select job's head) handled nothing, and one that
    // skipped finding-stands left a thread for the next round at this head:
    // the address-feedback check runs that started before that reply job
    // stop counting, so the next trigger dispatches the head again. Each such
    // round posted its round marker, so the select job's round cap ends it. A
    // limit stop is never released: limit-stop.mjs still holds the head until
    // its reset and counts it toward limits.limit-stops-per-head.
    let replies = [];
    // A select job's own stop (lane-stopped on this check) ends the head; only
    // a reply job's skip releases it.
    const selectStopped = existing.some(laneStop);
    if (anyHandles(existing, { now, limits: resolved.limits })) {
      replies = roundReplies(await api.listCheckRuns({ sha: head, checkName: settings.replyCheckName, appId: settings.appId })).filter(sinceNotes);
      const newest = replies.reduce((a, b) => (startOf(b) > startOf(a) ? b : a), replies[0]);
      if (releases(newest) && !selectStopped) {
        const cut = startOf(newest);
        existing = existing.filter((run) => limitResetsAt(run, resolved.limits) !== null || !(startOf(run) < cut));
      }
    }
    // The round's reply job posts its check after the round's address-feedback
    // check, so until a reply check started after the newest address-feedback
    // check, a releasing skip may still release the head: it is not
    // recorded as handled yet (#9362). An unreadable start records nothing.
    const newestCheck = Math.max(...existing.map(startOf));
    if (permanentlyHandles(existing, { limits: resolved.limits }) && replies.some((run) => startOf(run) > newestCheck)) {
      markHandled(record, settings.checkName, head);
    }
    if (anyHandles(existing, { now, limits: resolved.limits })) {
      return skip(`#${number}: head ${head} already has a ${settings.checkName} check run`);
    }
  }
  // Last, as it costs a full verifier read, and on a pass-only dispatch too: a
  // later pass clears no cap, and a push past it could never merge, so
  // pr-merge closes the pull request for a fresh attempt. It closes only the
  // lanes App's: an adopted owner's is never skipped. A pass-only round skips
  // only on a cap the reader found: it only resolves notes a pass superseded,
  // and nothing sends it again, so a cap that could not be read (#11354)
  // does not hold it.
  // A round sent for pr-verify's FAIL at this head (notesSince) expects the
  // reader's FAIL refusal there.
  const expected = !passOnly && notesSince !== null ? [VERIFY_FAIL] : [];
  const capped = owner ? null : await verifyCapped({ number, head, base: pull.base?.sha, expected });
  if (capped) {
    // The cap never clears for the head: later runs skip it before any
    // read. A sibling read that failed is read again next run.
    if (capFinal(capped)) {
      markHandled(record, settings.checkName, head);
    }
    const warning = deadlineWarning(number, capped);
    if (warning) {
      log(warning);
    }
    if (passOnly && !capFinal(capped)) {
      log(`#${number}: pr-verify's FAIL cap could not be read (${capped}); the pass-only round runs anyway`);
    } else {
      return skip(`#${number}: pr-verify's FAILs are at the cap or cannot all be read (${capped}); pr-merge closes it for a fresh attempt, so no ${settings.activity} round`);
    }
  }
  const request = {
    workflow: settings.workflow,
    ref: `refs/heads/${settings.base}`,
    inputs: {
      "pr-number": String(number),
      activity: settings.activity,
      "dispatcher-run-id": String(runId),
      ...(passOnly ? { "verify-pass-head": head } : {}),
    },
  };
  let workflowRunId;
  try {
    ({ workflowRunId } = await api.dispatchWorkflow(request));
  } catch (error) {
    if (!connectionLost(error)) {
      throw error;
    }
    // The connection broke before any answer, so GitHub may still have taken
    // the POST: a run it started for this PR holds the second send, as the
    // listing above would. This run never sends an HTTP error answer again;
    // the run fails, and recoverLost may send it within
    // FAILED_RUN_WINDOW_HOURS.
    const since = new Date(now - 60_000).toISOString().replace(/\.\d{3}Z$/, "Z");
    const started = (await api.listRecentRuns(settings.workflow, since)).find((run) => holds(run, number));
    log(`::warning::#${number}: the ${settings.workflow} dispatch got no answer (${errorLabel(error)}); ${started ? `run ${started.id} for it is listed, so it is not sent again` : "sending it once more"}`);
    ({ workflowRunId } = started ? { workflowRunId: started.id } : await api.dispatchWorkflow(request));
  }
  const id = String(workflowRunId);
  if (!RUN_ID.test(id)) {
    throw new Error(`#${number}: dispatch returned no valid workflow_run_id`);
  }
  record.dispatched.set(head, { number, runId: id });
  log(`dispatched #${number} head ${head} upstream run ${upstreamRunId} workflow_run_id=${id}`);
  return { number, workflowRunId: id };
}

// A request whose connection broke before any answer (undici's `fetch failed`
// with a reset or closed socket); an HTTP answer is never one.
const LOST_CONNECTION = new Set(["ECONNRESET", "UND_ERR_SOCKET"]);
const connectionLost = (error) => error?.name === "TypeError" && error.message === "fetch failed" && LOST_CONNECTION.has(error.cause?.code);

// The sweep: the first open lanes App PR into main with a fix request newer
// than its head's last round (sweepFixRequest), else the first whose head's
// newest reply check took a releasing skip, under SWEEP_HEAD_CAP such checks,
// that dispatchFeedback dispatches for the head's newest completed review run.
// Returns dispatchFeedback's result with that run's id, or null.
export async function sweepReleased({ api, repository, appSenderId, log, settings = DEFAULTS, ...rest }) {
  const context = { api, repository, appSenderId, log, settings, rest };
  const listed = await openPulls(context);
  const pulls = listed.filter((pull) => pull.user?.id === appSenderId);
  const requested = await sweepPulls(context, (pull) => sweepFixRequest({ ...context, pull }), pulls);
  if (requested !== null) {
    return requested;
  }
  log("sweep: no head with a fix request newer than its last round");
  const dispatched = await sweepPulls(context, (pull) => sweepOne({ ...context, pull }), pulls);
  if (dispatched !== null) {
    return dispatched;
  }
  log("sweep: no head whose last round left it for another round to dispatch");
  const stale = await sweepPulls(context, (pull) => sweepStale({ ...context, pull }), pulls);
  if (stale !== null) {
    return stale;
  }
  log("sweep: no head with a failing address-feedback stop and nothing left to fix");
  const owners = listed.filter((pull) => pull.user?.id !== appSenderId);
  const idle = owners.length === 0 ? null : await sweepPulls(context, (pull) => sweepIdleOwner({ ...context, pull }), owners);
  if (idle === null) {
    log("sweep: no idle owner PR whose reviewed head the lane has not answered");
  }
  return idle;
}

// Hours after an owner PR turns idle during which the tick still sends a head
// with no round (judgment: four of pr-unblock-dispatch.yml's half-hourly ticks,
// so a late or dropped tick, or a transient skip, does not lose the PR).
export const IDLE_OWNER_WINDOW_HOURS = 2;

// An owner PR's review completes while the person's session is still on it,
// so its review-run dispatch skips the idle test; once idle, the tick sends
// it. A PR still active by the listing's last update spends no read; an idle
// one spends one check-run read. A head with no round is decided by
// dispatchFeedback (both markers on the head, a thread the lane works, about
// six reads) only within IDLE_OWNER_WINDOW_HOURS of turning idle, so each
// update buys at most that window's ticks of those reads; a new thread, marker
// or fix request moves the update time and opens the window again. A head
// with a round spends a reply check-run read, and a status read unless that
// round's reply released it (sweepOne, as for a lanes App PR); a failing stop
// with no thread left is then cleared as sweepStale clears one on a lanes App
// PR, with no window, since resolving a thread may not move the update time.
async function sweepIdleOwner(context) {
  const { api, pull, rest, settings } = context;
  const since = (rest.now ?? Date.now()) - (rest.adoption?.idleHours ?? 0) * 3_600_000;
  const updated = Date.parse(pull.updated_at ?? "");
  if (!(updated <= since)) {
    return null;
  }
  const rounds = await api.listCheckRuns({ sha: pull.head.sha, checkName: settings.checkName, appId: settings.appId });
  if (rounds.length > 0) {
    return (await sweepOne(context)) ?? sweepStale(context);
  }
  return updated > since - IDLE_OWNER_WINDOW_HOURS * 3_600_000 ? dispatchAtHead(context) : null;
}

// Each open lanes App PR into the base, and each adopted owner PR
// (dispatchFeedback applies its idle test); only the idle pass takes the
// owner PRs.
// One listing per client: a tick's sweeps and recoveries share it.
const listed = new WeakMap();
async function openPulls({ api, repository, appSenderId, settings, rest }) {
  if (!listed.has(api)) {
    listed.set(api, api.listOpenPulls(settings.base));
  }
  return (await listed.get(api)).filter(
    (pull) =>
      (pull.user?.id === appSenderId || ownerAuthored(pull, rest?.adoption)) &&
      pull.draft === false &&
      pull.head?.repo?.full_name === repository &&
      SHA.test(pull.head?.sha ?? ""),
  );
}

// Each of `pulls` (default: the open lanes App PRs), decided by `decide` in
// listing order until one dispatches.
async function sweepPulls(context, decide, pulls = null) {
  const { log } = context;
  for (const pull of pulls ?? (await openPulls(context)).filter((row) => row.user?.id === context.appSenderId)) {
    let dispatched = null;
    try {
      dispatched = await decide(pull);
    } catch (error) {
      // One PR's failed read leaves the PRs after it to the sweep.
      log(`::warning::#${pull.number}: the sweep could not decide head ${pull.head.sha}: ${error.message}`);
    }
    if (dispatched !== null) {
      return dispatched;
    }
  }
  return null;
}

// The newest status of `context` on a head by github-actions[bot], read
// across every page newest first, as ci-status and report-escalation.sh clear
// read it; null when there is none.
export function newestStatus(statuses, context) {
  return statuses.find((row) => row?.context === context && row?.creator?.login === "github-actions[bot]") ?? null;
}

// A head whose newest pr-unblock/address-feedback status fails although no
// review thread is left unresolved: a person resolved the threads after the
// lane stopped, and nothing else dispatches the lane on that head. A run of
// the activity then finds nothing to fix (address-feedback.mjs `resolved`),
// and report-stop-status clears the status. Once per stop: a pr-unblock run
// for the PR created after the failing status holds the head. The upstream is
// the head's newest completed review run, as for any other dispatch. An
// adopted owner PR (sweepIdleOwner) keeps its Hold: line and idle gates.
async function sweepStale({ api, pull, repository, appSenderId, log, settings, rest }) {
  const head = pull.head.sha;
  const number = pull.number;
  const status = newestStatus(await api.listStatuses(head), `pr-unblock/${settings.activity}`);
  if (status?.state !== "failure" && status?.state !== "error") {
    return null;
  }
  if (pull.user?.id !== appSenderId) {
    const why = await ownerSkip({ api, pull, adoption: rest.adoption, now: rest.now ?? Date.now() });
    if (why) {
      log(`skip: #${number}: ${why}`);
      return null;
    }
  }
  const held = (pull.labels ?? []).map((label) => label.name).filter((name) => settings.holdLabels.includes(name));
  if (held.length > 0) {
    log(`skip: #${number} is labeled ${held.join(", ")}`);
    return null;
  }
  if ((await api.listReviewThreads(number)).some((thread) => thread.isResolved === false)) {
    return null;
  }
  const stoppedAt = Date.parse(status.created_at ?? "");
  const since = (await api.listWorkflowRuns(settings.workflow)).find(
    (run) => run.display_title === runTitle(settings.activity, number) && !(Date.parse(run.created_at ?? "") < stoppedAt),
  );
  if (since) {
    log(`skip: #${number}: ${settings.workflow} run ${since.id} for ${settings.activity} started after the stop on head ${head}`);
    return null;
  }
  const resolved = await rest.resolveSlot({ number, head });
  const enabled = (name) => resolved?.lane.slots.some((slot) => slot.name === name && slot.enabled === true);
  if (resolved?.lane.enabled !== true || !enabled(settings.activity) || resolved.selected?.applies !== true) {
    log(`skip: #${number}: ${settings.activity} is not enabled or does not apply`);
    return null;
  }
  const upstream = await reviewRunAt({ api, head, repository, settings });
  if (upstream === null) {
    log(`skip: #${number}: head ${head} has no completed review run`);
    return null;
  }
  const { workflowRunId } = await api.dispatchWorkflow({
    workflow: settings.workflow,
    ref: `refs/heads/${settings.base}`,
    inputs: { "pr-number": String(number), activity: settings.activity, "dispatcher-run-id": String(rest.runId) },
  });
  const id = String(workflowRunId);
  if (!RUN_ID.test(id)) {
    throw new Error(`#${number}: dispatch returned no valid workflow_run_id`);
  }
  log(`dispatched #${number} head ${head} to clear a stop with no thread left, upstream run ${upstream.id} workflow_run_id=${id}`);
  return { number, workflowRunId: id, upstreamRunId: upstream.id };
}

// Whether the head's newest reply check released it, and whether releasing
// skips reached SWEEP_HEAD_CAP there (logged).
async function releaseState({ api, pull, log, settings }) {
  const head = pull.head.sha;
  const replies = roundReplies(await api.listCheckRuns({ sha: head, checkName: settings.replyCheckName, appId: settings.appId }));
  const newest = replies.reduce((a, b) => (startOf(b) > startOf(a) ? b : a), replies[0]);
  const skips = replies.filter(releases).length;
  const capped = releases(newest) && skips >= SWEEP_HEAD_CAP;
  if (capped) {
    log(`skip: #${pull.number}: head ${head} was released ${skips} times, the sweep's cap`);
  }
  return { released: releases(newest), capped };
}

async function sweepOne(context) {
  const { released, capped } = await releaseState(context);
  return released && !capped ? dispatchAtHead(context) : null;
}

// A head whose newest fix request came after its newest address-feedback check
// run, or which has none, under SWEEP_HEAD_CAP rounds and releases, with no run
// of the activity for the PR created since the request. That last holds a
// round that ended before posting its check, so a request is sent once. A PR
// with no such thread costs one read.
async function sweepFixRequest(context) {
  const { api, pull, appSenderId, log, settings, rest } = context;
  const number = pull.number;
  const head = pull.head.sha;
  const trustedHumans = rest.trustedHumans ?? new Set();
  const threads = await api.listReviewThreads(number);
  const fixers = await threadFixers({ threads, trustedHumans, permission: api.getPermission });
  const requestSince = newestFixRequest(threads, { reviewerId: settings.reviewerId, reviewerIds: rest.reviewerIds, appId: appSenderId, trustedHumans, fixers });
  if (requestSince === null) {
    return null;
  }
  const rounds = await api.listCheckRuns({ sha: head, checkName: settings.checkName, appId: settings.appId });
  // NaN compares false, so a run with no readable start still counts.
  if (rounds.some((run) => !(startOf(run) <= requestSince))) {
    log(`skip: #${number}: head ${head} has a ${settings.checkName} check run since its newest fix request`);
    return null;
  }
  if (rounds.length >= SWEEP_HEAD_CAP || (await releaseState(context)).capped) {
    log(`skip: #${number}: head ${head} reached the sweep's cap, so its fix request waits for a push`);
    return null;
  }
  const sent = (await api.listWorkflowRuns(settings.workflow)).find(
    (run) => run.display_title === runTitle(settings.activity, number) && !(Date.parse(run.created_at ?? "") < requestSince),
  );
  if (sent) {
    log(`skip: #${number}: ${settings.workflow} run ${sent.id} for ${settings.activity} started after its newest fix request`);
    return null;
  }
  return dispatchAtHead(context, { requestSince });
}

// dispatchFeedback for a PR's head with the head's newest completed review run
// as the upstream, with that run's id; null when it has none or nothing is sent.
async function dispatchAtHead({ api, pull, repository, appSenderId, log, settings, rest }, options = {}) {
  const head = pull.head.sha;
  const upstream = await reviewRunAt({ api, head, repository, settings });
  if (upstream === null) {
    log(`skip: #${pull.number}: head ${head} has no completed review run`);
    return null;
  }
  const dispatched = await dispatchFeedback({ ...rest, ...options, api, repository, appSenderId, log, settings, upstream });
  return dispatched === null ? null : { ...dispatched, upstreamRunId: upstream.id };
}

// This file's workflow, whose lost runs the tick recovers.
export const DISPATCH_WORKFLOW = ".github/workflows/pr-feedback-dispatch.yml";

// The workflow's job that dispatches; a loss of its other jobs leaves no head
// undispatched.
const DISPATCH_JOB = "dispatch";
// A job that ran a step, as reconcile.mjs holdReason reads one.
const jobStarted = (job) => (Array.isArray(job?.steps) ? job.steps : []).some((step) => step?.conclusion != null && step.conclusion !== "skipped");
// A failed dispatch job sent nothing either (#11344: its POST threw), and
// nothing else sends it again, so it is recovered as a lost one is. LOST stays
// the reconciler's set: it re-runs what it holds.
const RECOVERABLE = new Set([...LOST, "failure"]);
// Hours after a failed run during which the tick retries it (judgment: four
// half-hourly ticks, as IDLE_OWNER_WINDOW_HOURS, so a dropped tick does not
// lose it). A POST the API rejects starts no round to hold the PR, and the
// tick logs it and ends green (sweepPulls), so this age is the only bound.
export const FAILED_RUN_WINDOW_HOURS = 2;
const dispatchLost = (job) => job?.name === DISPATCH_JOB && RECOVERABLE.has(job.conclusion) && jobStarted(job);

// The newest run of DISPATCH_WORKFLOW other than this one, created within
// LOOKBACK_HOURS (FAILED_RUN_WINDOW_HOURS for a failed one), that ended in
// RECOVERABLE with its dispatch job lost or failed after it started; null when
// none, or when the listing cannot be
// read. One listing call when none ended in RECOVERABLE; then one jobs read per such run, newest
// first, until one matches.
export async function lostDispatchRun({ api, runId, log, now = Date.now() }) {
  const since = now - LOOKBACK_HOURS * 3_600_000;
  const failedSince = now - FAILED_RUN_WINDOW_HOURS * 3_600_000;
  let runs;
  try {
    runs = await api.listRecentRuns(DISPATCH_WORKFLOW, new Date(since).toISOString().replace(/\.\d{3}Z$/, "Z"));
  } catch (error) {
    log(`::warning::${DISPATCH_WORKFLOW} run listing failed (${error.message}); no lost run is recovered this tick`);
    return null;
  }
  const lost = runs
    .filter((run) => String(run.id) !== String(runId) && run.status === "completed" && RECOVERABLE.has(run.conclusion) && Date.parse(run.created_at ?? "") >= (run.conclusion === "failure" ? failedSince : since))
    .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
  for (const run of lost) {
    try {
      if ((await api.listRunJobs(run.id)).some(dispatchLost)) {
        return run;
      }
    } catch (error) {
      log(`::warning::run ${run.id}'s jobs could not be read (${error.message}); the next tick reads them again`);
    }
  }
  return null;
}

// The recovery: when a lost run of this workflow is in the window
// (lostDispatchRun), the first open lanes App PR into main, short of the
// sweep's cap, that dispatchFeedback dispatches for its head's newest
// completed review run. Returns dispatchFeedback's result with that run's id,
// or null.
export async function recoverLost({ api, repository, appSenderId, log, settings = DEFAULTS, now, ...rest }) {
  const deferred = await recoverDeferred({ ...rest, api, repository, appSenderId, log, settings, now });
  if (deferred !== null) {
    return deferred;
  }
  const lost = await lostDispatchRun({ api, runId: rest.runId, log, now });
  if (lost === null) {
    return null;
  }
  log(`recover: ${DISPATCH_WORKFLOW} run ${lost.id} ended ${lost.conclusion} after its ${DISPATCH_JOB} job started`);
  const context = { api, repository, appSenderId, log, settings, rest };
  // A round that ended before posting its check does not handle the head, and
  // the lost run stays in the window for a day, so each lost run sends at most
  // one round per PR: a finished run of the activity for the PR created after
  // it holds the PR. A run still going is dispatchFeedback's to skip. One
  // listing a tick, read when the first PR asks.
  let finished;
  const sentSince = async (number) => {
    finished ??= api.listFinishedRunsSince(settings.workflow, lost.created_at);
    return (await finished).find((run) => run.display_title === runTitle(settings.activity, number));
  };
  const dispatched = await sweepPulls(context, async (pull) => {
    const sent = await sentSince(pull.number);
    if (sent) {
      log(`skip: #${pull.number}: ${settings.workflow} run ${sent.id} for ${settings.activity} started after lost run ${lost.id}`);
      return null;
    }
    return (await releaseState({ ...context, pull })).capped ? null : dispatchAtHead({ ...context, pull });
  });
  if (dispatched === null) {
    log("recover: no head left to dispatch");
  }
  return dispatched;
}

// The record post-verify-notes uploads when the lost-run reconciler re-ran it
// to apply a verdict the kill switch deferred (reconcile.mjs, the Verdict
// kind), named for the head and the verdict. The re-run sends no round
// itself, since check-trusted-trigger trusts a dispatcher only at attempt 1
// or re-run by a listed human; this tick, an attempt-1 run, sends it.
export const DEFERRED_RECORD = /^pr-feedback-deferred-([0-9a-f]{40})-(fail|pass)$/;
const ACTIONS_BOT = "github-actions[bot]";

// Whether `run`, the run that uploaded a deferred record, is a
// github-actions[bot] re-run of this workflow on main: any workflow can
// upload that name to its own run.
const deferringRun = (run, repository) =>
  run?.path === DISPATCH_WORKFLOW &&
  run.event === "workflow_run" &&
  run.head_branch === "main" &&
  run.repository?.full_name === repository &&
  run.run_attempt > 1 &&
  run.triggering_actor?.login === ACTIONS_BOT;

// The first deferred verdict at an open lanes App PR's head that
// dispatchFeedback sends for the head's newest completed review run, as
// main() would have for an on-time verdict: a FAIL with notesSince the
// record's upload, when its notes reached the PR, so a round before then
// does not hold it; a PASS as a pass-only round. A run of the activity for
// the PR created after the record holds it, so each record is sent once.
// Each head costs two exact-name artifact reads, fail then pass; a record
// whose read fails is logged and left to the next tick.
export async function recoverDeferred({ api, repository, appSenderId, log, settings = DEFAULTS, ...rest }) {
  const pulls = (await openPulls({ api, repository, appSenderId, settings, rest })).filter((pull) => pull.user?.id === appSenderId);
  for (const pull of pulls) {
    const head = pull.head.sha;
    for (const verdict of ["fail", "pass"]) {
      const name = `pr-feedback-deferred-${head}-${verdict}`;
      try {
        const [artifact] = (await api.listArtifactsNamed(name))
          .filter((row) => row?.name === name && row.expired === false)
          .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
        if (!artifact) {
          continue;
        }
        const run = await api.getWorkflowRun(artifact.workflow_run?.id);
        if (!deferringRun(run, repository)) {
          log(`skip: #${pull.number}: ${name} was uploaded by run ${run?.id}, not a github-actions[bot] re-run of ${DISPATCH_WORKFLOW} on main`);
          continue;
        }
        const recorded = Date.parse(artifact.created_at ?? "");
        const sent = (await api.listWorkflowRuns(settings.workflow)).find(
          (row) => row.display_title === runTitle(settings.activity, pull.number) && !(Date.parse(row.created_at ?? "") < recorded),
        );
        if (sent) {
          log(`skip: #${pull.number}: ${settings.workflow} run ${sent.id} started after the deferred ${verdict} at ${head}`);
          continue;
        }
        const upstream = await reviewRunAt({ api, head, repository, settings });
        if (upstream === null) {
          log(`skip: #${pull.number}: head ${head} has no completed review run`);
          continue;
        }
        const passOnly = verdict === "pass";
        const dispatched = await dispatchFeedback({ ...rest, api, repository, appSenderId, log, settings, upstream, notesSince: passOnly ? null : recorded, passOnly });
        if (dispatched !== null) {
          log(`recover: sent the ${verdict} verdict deferred at ${head} (run ${run.id})`);
          return { ...dispatched, upstreamRunId: upstream.id };
        }
      } catch (error) {
        log(`::warning::#${pull.number}: the deferred ${verdict} at ${head} could not be decided (${error.message}); the next tick reads it again`);
      }
    }
  }
  return null;
}

const THREADS_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          id isResolved
          comments(first: 100) {
            nodes {
              author { login ... on Bot { databaseId } ... on User { databaseId } }
              createdAt body lastEditedAt
              editor { ... on Bot { databaseId } ... on User { databaseId } }
              pullRequestReview { author { ... on Bot { databaseId } ... on User { databaseId } } commit { oid } submittedAt }
            }
            pageInfo { hasNextPage }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

export function createGitHubApi({ token, repository, apiUrl, graphqlUrl, fetch: rawFetch = globalThis.fetch, attemptTimeoutMs }) {
  // Each request's rate-limit reading goes to the job-end api-calls notice.
  const fetch = countRequests(rawFetch);
  const [owner, name] = repository.split("/");
  const repo = `${apiUrl}/repos/${owner}/${name}`;
  const headers = {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "X-GitHub-Api-Version": "2022-11-28",
  };

  async function request(url, method = "GET", body, signal) {
    const response = await fetch(url, {
      method,
      headers: body === undefined ? headers : { ...headers, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    });
    if (!response.ok) {
      throw Object.assign(new Error(`${method} ${url} returned ${response.status}`), { rateLimited: response.rateLimited === true, detail: await responseDetail(response) });
    }
    return response.status === 204 ? {} : response.json();
  }

  // Every page of a REST listing, at most 50.
  async function pages(url) {
    const rows = [];
    for (let page = 1; page <= 50; page += 1) {
      const batch = await request(`${url}&page=${page}`);
      rows.push(...batch);
      if (batch.length < 100) {
        return rows;
      }
    }
    throw new Error(`${url} has more than 50 pages`);
  }

  async function graphql(query, variables, signal) {
    const result = await request(graphqlUrl, "POST", { query, variables }, signal);
    if (result.errors?.length) {
      throw new Error(`GraphQL: ${result.errors.map((error) => error.message).join("; ")}`);
    }
    return result.data;
  }

  return {
    pullsForCommit: (sha) =>
      commitPulls({
        repository,
        sha,
        readRest: () => request(`${repo}/commits/${sha}/pulls`),
        readGraphQL: graphql,
        timeoutMs: attemptTimeoutMs,
      }),
    // Metadata read, which every token holds. A 404 (not a collaborator) is none.
    async getPermission(login) {
      const url = `${repo}/collaborators/${encodeURIComponent(login)}/permission`;
      const response = await fetch(url, { headers });
      if (response.status === 404) {
        return "none";
      }
      if (!response.ok) {
        throw Object.assign(new Error(`GET ${url} returned ${response.status}`), { detail: await responseDetail(response) });
      }
      return (await response.json()).permission;
    },
    async listIssueComments(number) {
      const comments = [];
      for (let page = 1; page <= 50; page += 1) {
        const batch = await request(`${repo}/issues/${number}/comments?per_page=100&page=${page}`);
        comments.push(...batch);
        if (batch.length < 100) {
          return comments;
        }
      }
      throw new Error(`#${number} has more than 5000 comments`);
    },
    listLabelEvents: (number) => listLabelEvents({ graphql, repository, number }),
    // prHold's review reads (gate-source.mjs reviewReader), on an owner PR
    // carrying the human-gated label only.
    listReviewComments: (number, since) => pages(`${repo}/pulls/${number}/comments?since=${encodeURIComponent(since)}&per_page=100`),
    listReviews: (number) => pages(`${repo}/pulls/${number}/reviews?per_page=100`),
    // The REST issue timeline, for a listed bot's automatic review
    // (address-feedback.mjs readTriggers).
    listTimeline: (number) => pages(`${repo}/issues/${number}/timeline?per_page=100`),
    listRequestHistory: async (number) => requestHistoryOf(await graphql(REQUEST_HISTORY_QUERY, { owner, name, pr: number })),
    async listReviewThreads(number) {
      const threads = [];
      let after = null;
      for (;;) {
        const data = await graphql(THREADS_QUERY, { owner, name, number, after });
        const page = data.repository.pullRequest.reviewThreads;
        threads.push(...page.nodes);
        if (!page.pageInfo.hasNextPage) {
          return threads;
        }
        after = page.pageInfo.endCursor;
      }
    },
    async listCheckRuns({ sha, checkName, appId }) {
      const query = new URLSearchParams({
        check_name: checkName,
        app_id: String(appId),
        filter: "all",
        per_page: "100",
      });
      return (await request(`${repo}/commits/${sha}/check-runs?${query}`)).check_runs;
    },
    // The newest workflow_dispatch runs: a run still queued or going is
    // among them, since a dispatcher waits at most minutes behind it.
    async listWorkflowRuns(workflow) {
      return (await request(`${repo}/actions/workflows/${workflow}/runs?event=workflow_dispatch&per_page=100`)).workflow_runs ?? [];
    },
    getWorkflowRun: (id) => request(`${repo}/actions/runs/${encodeURIComponent(id)}`),
    // A commit's committer date, the time it was made.
    headCommittedAt: async (sha) => (await request(`${repo}/commits/${sha}`)).commit?.committer?.date ?? "",
    async listOpenPulls(base) {
      const pulls = [];
      for (let page = 1; page <= 10; page += 1) {
        const batch = await request(`${repo}/pulls?state=open&base=${encodeURIComponent(base)}&per_page=100&page=${page}`);
        pulls.push(...batch);
        if (batch.length < 100) {
          return pulls;
        }
      }
      throw new Error(`more than 1000 open PRs into ${base}`);
    },
    // Every status on a commit, newest first across pages.
    async listStatuses(sha) {
      const statuses = [];
      for (let page = 1; page <= 10; page += 1) {
        const batch = await request(`${repo}/commits/${sha}/statuses?per_page=100&page=${page}`);
        statuses.push(...batch);
        if (batch.length < 100) {
          return statuses;
        }
      }
      throw new Error(`commit ${sha} has more than 1000 statuses`);
    },
    // The newest completed pull_request runs of a workflow file at a head.
    async listCompletedRuns(path, head) {
      const query = new URLSearchParams({ head_sha: head, event: "pull_request", status: "completed", per_page: "10" });
      return (await request(`${repo}/actions/workflows/${path.split("/").at(-1)}/runs?${query}`)).workflow_runs ?? [];
    },
    // A workflow file's newest 100 runs created since `since`: many ticks'
    // worth, so a run the window holds is listed again by a later tick.
    async listRecentRuns(path, since) {
      const query = new URLSearchParams({ created: `>=${since}`, per_page: "100" });
      return (await request(`${repo}/actions/workflows/${path.split("/").at(-1)}/runs?${query}`)).workflow_runs ?? [];
    },
    // Every finished workflow_dispatch run of a workflow created since `since`,
    // newest first. The API returns at most 1,000 for a filtered listing
    // (https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow),
    // so a window past that is an error, not a shorter answer.
    async listFinishedRunsSince(workflow, since) {
      const query = new URLSearchParams({ event: "workflow_dispatch", status: "completed", created: `>=${since}`, per_page: "100" });
      const runs = [];
      for (let page = 1; page <= 10; page += 1) {
        const batch = (await request(`${repo}/actions/workflows/${workflow}/runs?${query}&page=${page}`)).workflow_runs ?? [];
        runs.push(...batch);
        if (batch.length < 100) {
          return runs;
        }
      }
      throw new Error(`${workflow} has more than 1000 finished runs since ${since}`);
    },
    // The repository's artifacts with exactly this name, newest first.
    async listArtifactsNamed(name) {
      const query = new URLSearchParams({ name, per_page: "10" });
      return (await request(`${repo}/actions/artifacts?${query}`)).artifacts ?? [];
    },
    // A run's latest attempt's jobs, with their steps.
    async listRunJobs(id) {
      const listing = await request(`${repo}/actions/runs/${encodeURIComponent(id)}/jobs?filter=latest&per_page=100`);
      if (!Array.isArray(listing?.jobs) || listing.total_count > 100) {
        throw new Error(`run ${id}'s job listing is not one complete page`);
      }
      return listing.jobs;
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      const result = await request(`${repo}/actions/workflows/${workflow}/dispatches`, "POST", {
        ref,
        inputs,
        return_run_details: true,
      });
      return { workflowRunId: result.workflow_run_id };
    },
  };
}

// The pr-unblock lane as the dispatched run resolves it: resolve-config from
// the base checkout, deciding only the address-feedback slot, for this PR and
// head, on a workflow_dispatch event. Naming the activity keeps another slot's
// predicate (resolve-conflicts' mergeable) from needing facts this run lacks.
// The workflow installs resolve-config's dependencies before this runs.
// A valid config whose lane has no address-feedback slot resolves to null;
// every refusal, a malformed config included, throws.
export async function resolveFeedbackSlot({ number, head, env, github, settings = DEFAULTS }) {
  const { resolveFromBase } = await import(
    new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href
  );
  return resolveFromBase({
    absentAsNull: true,
    env: {
      LANE: settings.lane,
      ACTIVITY: settings.activity,
      BASE_PATH: env.BASE_PATH || ".base",
      EVENT_NAME: "workflow_dispatch",
      PR_NUMBER: String(number),
      HEAD_SHA: head,
      // Only reading: the dispatched runners perform the prepare step and
      // hand on what the read runner's address-feedback leaves (its patch
      // and its replies), as that runner's applied-by-supported names them.
      PREPARE_SUPPORTED: "true",
      APPLIED_BY_SUPPORTED: "patch feedback-replies",
      GITHUB_TOKEN: env.GITHUB_TOKEN,
      GITHUB_API_URL: env.GITHUB_API_URL,
      REPOSITORY: env.GITHUB_REPOSITORY,
    },
    event: {},
    github,
  });
}

// Writes run-id, the dispatched run, as a step output; the workflow records
// it with the upstream run id as an artifact on this run.
export async function main(env, { api, github, resolveSlot, verifyCapped, log = (line) => console.log(line), now = Date.now() } = {}) {
  for (const key of ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_RUN_ID", "GITHUB_OUTPUT", "GITHUB_EVENT_PATH", "APP_SENDER_ID"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const budget = api ? null : budgetedFetch({ log });
  const { record, text } = readRecord(env.DISPATCH_RECORD);
  const client = shareWorkflowRuns(
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      fetch: budget.fetch,
    }),
  );
  let upstream = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, "utf8")).workflow_run;
  const common = {
    api: client,
    repository: env.GITHUB_REPOSITORY,
    runId: env.GITHUB_RUN_ID,
    appSenderId: Number(env.APP_SENDER_ID),
    reviewerIds: reviewerIdsFrom(env.REVIEWER_IDS),
    // The base checkout's list, the one resolve-config reads beside it.
    trustedHumans: trustedHumansFrom(env.TRUSTED_ACTORS || `${env.BASE_PATH || ".base"}/.github/standards/trusted-actors/trusted-actors.json`),
    humanGatedLabel: humanGatedLabelFrom(env.TRACKER_CONFIG || `${env.BASE_PATH || ".base"}/.work-item-tracker.json`),
    resolveSlot: resolveSlot ?? (({ number, head }) => resolveFeedbackSlot({ number, head, env, github })),
    adoption: await ownerAdoption(env, log),
    // The gate's reader for the FAIL-cap skip (verify-cap.mjs), when the
    // workflow names it in VERIFY_EVIDENCE_SCRIPT.
    verifyCapped: verifyCapped ?? (env.VERIFY_EVIDENCE_SCRIPT ? verifyCapReader(env, { log }) : undefined),
    now,
    log,
  };
  const summary = () => {
    if (budget) {
      log(budget.summary());
    }
  };
  if (upstream?.path === SWEEP_WORKFLOW) {
    if (upstream.event !== "schedule") {
      log(`skip: run ${upstream.id} is not a scheduled tick`);
      return 0;
    }
    // A lost run is recovered only on a tick the released heads leave idle.
    const sweep = async () => (await sweepReleased(common)) ?? recoverLost({ ...common, now });
    const swept = await sweep().finally(summary);
    if (swept !== null) {
      appendFileSync(env.GITHUB_OUTPUT, `run-id=${swept.workflowRunId}\nupstream-run-id=${swept.upstreamRunId}\n`);
    }
    return 0;
  }
  if (upstream?.path === MERGE_WORKFLOW) {
    if (upstream.event !== "pull_request_target" || !SHA.test(upstream.head_sha ?? "")) {
      log(`skip: run ${upstream.id} is not a pull_request_target run of ${MERGE_WORKFLOW}`);
      return 0;
    }
    const head = upstream.head_sha;
    const pull = { number: upstream.pull_requests?.[0]?.number ?? "?", head: { sha: head } };
    if ((await releaseState({ api: client, pull, log, settings: DEFAULTS })).capped) {
      return 0;
    }
    upstream = await reviewRunAt({ api: client, head, repository: common.repository });
    if (upstream === null) {
      log(`skip: head ${head} has no completed review run yet; the review run dispatches when it completes`);
      return 0;
    }
  }
  let notesSince = null;
  let passOnly = false;
  if (upstream?.path === VERIFY_WORKFLOW) {
    if (env.VERIFY_HEAD_SHA && env.VERIFY_PASS_HEAD_SHA) {
      throw new Error("a pr-verify run names exactly one head: VERIFY_HEAD_SHA or VERIFY_PASS_HEAD_SHA");
    }
    passOnly = Boolean(env.VERIFY_PASS_HEAD_SHA);
    const head = (passOnly ? env.VERIFY_PASS_HEAD_SHA : env.VERIFY_HEAD_SHA) ?? "";
    if (!SHA.test(head)) {
      throw new Error("a pr-verify run names no posted head in VERIFY_HEAD_SHA, nor a passing one in VERIFY_PASS_HEAD_SHA");
    }
    notesSince = Date.parse((await client.getWorkflowRun(upstream.id)).created_at ?? "");
    if (Number.isNaN(notesSince)) {
      throw new Error(`pr-verify run ${upstream.id} has no readable creation time`);
    }
    upstream = await reviewRunAt({ api: client, head, repository: common.repository });
    if (upstream === null) {
      log(`skip: head ${head} has no completed review run yet; the review run dispatches when it completes`);
      return 0;
    }
  }
  const dispatched = await dispatchFeedback({ ...common, record, upstream, notesSince, passOnly }).finally(summary);
  if (dispatched !== null) {
    appendFileSync(env.GITHUB_OUTPUT, `run-id=${dispatched.workflowRunId}\nupstream-run-id=${upstream.id}\n`);
  }
  if (writeRecord(env.DISPATCH_RECORD, record, text)) {
    appendFileSync(env.GITHUB_OUTPUT, "record-changed=true\n");
  }
  return 0;
}

// The step's error annotation for a failed run. A thrown fetch names its
// cause only in error.cause; the label carries its code, never its message,
// which can hold a header value. A refused GitHub call adds its answer's detail.
export const failureAnnotation = (error) =>
  `::error::pr-feedback dispatch failed: ${error.message}${error?.cause?.code ? ` (${errorLabel(error)})` : ""}${detailSuffix(error)}`;

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(failureAnnotation(error));
      process.exitCode = 1;
    },
  );
}
