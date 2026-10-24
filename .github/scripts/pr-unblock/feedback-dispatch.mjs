// Starts pr-unblock's address-feedback activity on a lanes App PR, or a session
// PR (a trusted person's), once both review lanes have reviewed its current
// head and left an unresolved thread.
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
//   current head, and the lanes App opened it, or a trusted person did (a
//   session PR) while the base config sets adoption.feedback-idle-minutes;
// - it carries no do-not-merge label;
// - a session PR carries no owner `Hold:` body line, and its head was pushed
//   at least feedback-idle-minutes ago (the earliest completed review run
//   at the head), unless a trusted person's labeled event put lanes-may-fix
//   on it (sessionHold). Its author's reply on a thread, unless a fix
//   request, still keeps that thread from the lane (threadAuthors), and a
//   push while the lane works stops the round's push and reply jobs at the
//   trigger gate, behind which apply-patch.mjs skip-moved-head and its
//   fast-forward-only write never overwrite it;
// - both review lanes' newest reviewed-head markers, written by
//   github-actions[bot], name that head;
// - an unresolved review thread exists that address-feedback would work:
//   every comment is the reviewer bot's, a trusted person with write access
//   asked the lane to fix it (isFixRequest), or a trusted person answered the
//   lane's escalation (address-feedback.mjs threadAuthors); on a PR carrying
//   the human-gated label, the same when a lane escalation put the label on
//   and no review lane holds the PR (gate-source.mjs gateSource), and
//   otherwise only a thread where a trusted person with write access asked
//   the lane to fix it (isFixRequest);
// - that head has no pr-unblock / address-feedback check run yet (one the
//   usage limit stopped stops counting once its limit resets, and one that
//   started before the head's newest pr-unblock / publish-feedback check run
//   when that run skipped no-model-turn or finding-stands: that round left
//   the head for another round), and no
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
//
// A round whose reply job skipped no-model-turn, or finding-stands (an
// adjudicator let a disputed finding stand and the head did not move, so no
// review run follows), releases its head only for the next review or
// pr-verify completion there, which may never come. So a completed
// scheduled pr-unblock-dispatch.yml run, the half-hourly tick, also starts
// the file, and main() sweeps (sweepReleased): each open lanes App or
// session PR into main whose head's newest reply check took one of those
// skips, fewer than SWEEP_HEAD_CAP times at that head, and each session PR
// whose head has no address-feedback check run, is decided as above with the
// newest completed review run at that head as the upstream (reviewRunAt),
// which the record names. A session PR's review completion starts no
// dispatch job, so the sweep is its path. A sweep dispatches at most once,
// since the dispatched-run record names one upstream and one run, and keeps
// no record.
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

import { commitPulls } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { fixRequesters, humanGatedLabelFrom, threadAuthors, trustedHumansFrom } from "./address-feedback.mjs";
import { BODY_HOLD, commentItems, gateSource, labelHistory, listLabelEvents } from "./gate-source.mjs";
import { emptyRecord, isHandled, markHandled, readRecord, writeRecord } from "./dispatch-record.mjs";
import { anyHandles, limitResetsAt, permanentlyHandles } from "./limit-stop.mjs";
import { budgetedFetch } from "./request-budget.mjs";

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

// The tick whose completion starts the sweep.
export const SWEEP_WORKFLOW = ".github/workflows/pr-unblock-dispatch.yml";
// Releasing rounds at one head after which the sweep stops sending it
// (judgment: a third round with no model turn points at a cause a retry does
// not clear; the select job's round cap, address-feedback.mjs
// DEFAULT_MAX_ROUNDS, may end it sooner).
export const SWEEP_HEAD_CAP = 3;

// The label a trusted person puts on a session PR to let address-feedback
// work it without waiting for the authoring session to go idle.
export const MAY_FIX_LABEL = "lanes-may-fix";

const startOf = (run) => Date.parse(run.started_at ?? "");
// The reply check skips that leave the head for another round.
const RELEASES = new Set(["Skipped: no-model-turn", "Skipped: finding-stands"]);
const releases = (run) => run?.status === "completed" && run.conclusion === "neutral" && RELEASES.has(run.output?.title);

// The SHA the newest marker of `lane` written by the marker author names, or "".
export function markedHead(comments, lane, markerAuthorId = DEFAULTS.markerAuthorId) {
  const prefix = `<!-- claude-lane-reviewed-head lane=${lane} sha=`;
  const marker = comments
    .filter((comment) => comment.user?.id === markerAuthorId && comment.body?.startsWith(prefix))
    .at(-1);
  const sha = marker?.body.slice(prefix.length, prefix.length + 40) ?? "";
  return SHA.test(sha) ? sha : "";
}

// An unresolved thread, read in full, that threadAuthors accepts.
export function hasWorkableThread(threads, { reviewerId, appId, trustedHumans, requesters = null, fixers = requesters ?? new Set() }) {
  return threads.some(
    (thread) =>
      thread.isResolved === false &&
      thread.comments.pageInfo?.hasNextPage !== true &&
      threadAuthors(
        thread.comments.nodes.map((node) => ({
          authorId: node.author?.databaseId,
          createdAt: node.createdAt,
          body: node.body,
          lastEditedAt: node.lastEditedAt,
          editorId: node.editor?.databaseId,
        })),
        { reviewerId, appId, trustedHumans, requesters, fixers },
      ) !== null,
  );
}

export const VERIFY_WORKFLOW = ".github/workflows/pr-verify.yml";

// The completed pull_request review runs at `head`, any conclusion.
export async function reviewRunsAt({ api, head, settings = DEFAULTS }) {
  return (await Promise.all(settings.reviewWorkflows.map((path) => api.listCompletedRuns(path, head))))
    .flat()
    .filter((run) => run.head_sha === head && run.event === "pull_request");
}

// The newest completed review run at `head` that reviewed something (not
// skipped or cancelled), or null.
export async function reviewRunAt({ api, head, settings = DEFAULTS, runs = null }) {
  const reviewed = (runs ?? (await reviewRunsAt({ api, head, settings }))).filter((run) => !["skipped", "cancelled"].includes(run.conclusion));
  reviewed.sort((a, b) => Date.parse(b.created_at ?? "") - Date.parse(a.created_at ?? ""));
  return reviewed[0] ?? null;
}

// adoption.feedback-idle-minutes from the base config, or null when unset.
async function idleMinutesOf(loadAdoption) {
  const minutes = (await loadAdoption())?.["feedback-idle-minutes"];
  return Number.isSafeInteger(minutes) && minutes > 0 ? minutes : null;
}

// Why a session PR (one a trusted person opened, whose authoring session may
// still push) is not worked now, or "" when it is: an owner `Hold:` line
// holds it; a lanes-may-fix label whose newest labeled event a trusted person
// made lets it through at once; otherwise the head must have been pushed at
// least `idleMinutes` ago. The push time is the earliest completed review
// run's creation at the head (a pull_request run starts on the push), so a
// lane's own push restarts the wait too; an unreadable time is not idle.
async function sessionHold({ api, pull, head, trustedHumans, idleMinutes, now, reviewRuns, settings }) {
  if (BODY_HOLD.test(String(pull.body ?? ""))) {
    return "carries an owner Hold: line";
  }
  if ((pull.labels ?? []).some((label) => label.name === MAY_FIX_LABEL)) {
    const { labeled } = labelHistory(await api.listLabelEvents(pull.number), MAY_FIX_LABEL);
    if (labeled?.actor?.type === "User" && trustedHumans.has(labeled.actor.id)) {
      return "";
    }
  }
  const runs = reviewRuns ?? (await reviewRunsAt({ api, head, settings }));
  const pushed = Math.min(...runs.map((run) => Date.parse(run.created_at ?? "")).map((time) => (Number.isNaN(time) ? Infinity : time)));
  const minutes = Math.floor((now - pushed) / 60_000);
  if (!(minutes >= idleMinutes)) {
    const ago = Number.isFinite(minutes) ? `${minutes} minute(s) ago` : "at an unreadable time";
    return `the authoring session pushed head ${head} ${ago}, under adoption.feedback-idle-minutes (${idleMinutes})`;
  }
  return "";
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
  humanGatedLabel = "needs-human",
  now = Date.now(),
  record = emptyRecord(),
  notesSince = null,
  loadAdoption = async () => ({}),
  reviewRuns = null,
  reviewThreads = null,
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
  if (notesSince === null && isHandled(record, settings.checkName, head)) {
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
  // A trusted person's PR is a session PR: worked only under sessionHold.
  const session = pull.user?.id !== appSenderId;
  if (session && !trustedHumans.has(pull.user?.id)) {
    return skip(`#${number} was not opened by the lanes App or a trusted person`);
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
  if (session) {
    const idleMinutes = await idleMinutesOf(loadAdoption);
    if (idleMinutes === null) {
      return skip(`#${number} is a trusted person's PR and adoption.feedback-idle-minutes is not set`);
    }
    const why = await sessionHold({ api, pull, head, trustedHumans, idleMinutes, now, reviewRuns, settings });
    if (why !== "") {
      return skip(`#${number}: ${why}`);
    }
  }
  const comments = await api.listIssueComments(number);
  const unreviewed = settings.markerLanes.filter((lane) => markedHead(comments, lane, settings.markerAuthorId) !== head);
  if (unreviewed.length > 0) {
    return skip(`#${number}: ${unreviewed.join(", ")} has not marked head ${head} reviewed`);
  }
  const threads = reviewThreads ?? (await api.listReviewThreads(number));
  // A human-gated PR dispatches only for a thread a trusted person with
  // write access asked the lane to fix, unless a lane escalation put the
  // label on and no review lane holds the PR. The label stays on either way:
  // clear-escalations.mjs owns taking it off.
  const labeled = (pull.labels ?? []).some((label) => label.name === humanGatedLabel);
  const gate = labeled
    ? gateSource({
        timeline: [...commentItems(comments), ...(await api.listLabelEvents(number))],
        label: humanGatedLabel,
        head,
        isLanesApp: (user) => user?.id === appSenderId && user?.type === "Bot",
      })
    : null;
  const gated = labeled && gate.source !== "lane-escalation";
  const fixers = await fixRequesters({
    comments: threads.flatMap((thread) =>
      thread.comments.nodes.map((node) => ({ authorId: node.author?.databaseId, login: node.author?.login, body: node.body })),
    ),
    trustedHumans,
    permission: api.getPermission,
  });
  const requesters = gated ? fixers : null;
  if (!hasWorkableThread(threads, { reviewerId: settings.reviewerId, appId: appSenderId, trustedHumans, requesters, fixers })) {
    return skip(
      gated
        ? `#${number} is labeled ${humanGatedLabel} (${gate.source}: ${gate.reason}) and has no thread a trusted person with write access asked the lane to fix`
        : `#${number} has no unresolved thread left by the reviewer bot alone, asked to be fixed, or answered by a trusted person`,
    );
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
  // NaN compares false, so a run with no readable start still counts.
  const sinceNotes = (run) => notesSince === null || !(Date.parse(run.started_at ?? "") <= notesSince);
  let existing = (await api.listCheckRuns({ sha: head, checkName: settings.checkName, appId: settings.appId })).filter(sinceNotes);
  // A round whose reply job skipped no-model-turn (decided from the scan
  // job's outputs and the select job's head) handled nothing, and one that
  // skipped finding-stands left a thread for the next round at this head:
  // the address-feedback check runs that started before that reply job
  // stop counting, so the next trigger dispatches the head again. Each such
  // round posted its round marker, so the select job's round cap ends it. A
  // limit stop is never released: limit-stop.mjs still holds the head until
  // its reset and counts it toward limits.limit-stops-per-head.
  let replies = [];
  if (anyHandles(existing, { now, limits: resolved.limits })) {
    replies = (await api.listCheckRuns({ sha: head, checkName: settings.replyCheckName, appId: settings.appId })).filter(sinceNotes);
    const newest = replies.reduce((a, b) => (startOf(b) > startOf(a) ? b : a), replies[0]);
    if (releases(newest)) {
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
  const { workflowRunId } = await api.dispatchWorkflow({
    workflow: settings.workflow,
    ref: `refs/heads/${settings.base}`,
    inputs: {
      "pr-number": String(number),
      activity: settings.activity,
      "dispatcher-run-id": String(runId),
    },
  });
  const id = String(workflowRunId);
  if (!RUN_ID.test(id)) {
    throw new Error(`#${number}: dispatch returned no valid workflow_run_id`);
  }
  record.dispatched.set(head, { number, runId: id });
  log(`dispatched #${number} head ${head} upstream run ${upstreamRunId} workflow_run_id=${id}`);
  return { number, workflowRunId: id };
}

// The sweep: the first open PR into main that dispatchFeedback dispatches
// for its head's newest completed review run, among the lanes App's PRs and
// session PRs (a trusted person's, while adoption.feedback-idle-minutes is
// set) whose head's newest reply check took a releasing skip, under
// SWEEP_HEAD_CAP such checks, and the session PRs whose head has no
// address-feedback check run yet. A review completion on a session PR's
// branch starts no dispatch job (pr-feedback-dispatch.yml), and right after
// a push the session is not idle anyway, so this is a session PR's path.
// A session PR held by a hold label or an owner Hold: line costs no read,
// and one with no unresolved review thread one read.
// Returns dispatchFeedback's result with that run's id, or null.
export async function sweepReleased({ api, repository, appSenderId, log, settings = DEFAULTS, trustedHumans = new Set(), loadAdoption = async () => ({}), ...rest }) {
  const open = (await api.listOpenPulls(settings.base)).filter(
    (pull) => pull.draft === false && pull.head?.repo?.full_name === repository && SHA.test(pull.head?.sha ?? ""),
  );
  const isSession = (pull) =>
    pull.user?.id !== appSenderId &&
    trustedHumans.has(pull.user?.id) &&
    !(pull.labels ?? []).some((label) => settings.holdLabels.includes(label.name)) &&
    !BODY_HOLD.test(String(pull.body ?? ""));
  // Read once, and only when a session PR is open.
  const sessions = open.some(isSession) && (await idleMinutesOf(loadAdoption)) !== null;
  const pulls = open.filter((pull) => pull.user?.id === appSenderId || (sessions && isSession(pull)));
  for (const pull of pulls) {
    const head = pull.head.sha;
    let dispatched = null;
    try {
      dispatched = await sweepOne({ api, pull, head, repository, appSenderId, log, settings, rest: { ...rest, trustedHumans, loadAdoption } });
    } catch (error) {
      // One PR's failed read leaves the PRs after it to the sweep.
      log(`::warning::#${pull.number}: the sweep could not decide head ${head}: ${error.message}`);
    }
    if (dispatched !== null) {
      return dispatched;
    }
  }
  log("sweep: no head whose last round left it for another round to dispatch");
  return null;
}

async function sweepOne({ api, pull, head, repository, appSenderId, log, settings, rest }) {
  // Most session PRs have no open thread: one read settles them each tick.
  const session = pull.user?.id !== appSenderId;
  const reviewThreads = session ? await api.listReviewThreads(pull.number) : null;
  if (session && !reviewThreads.some((thread) => thread.isResolved === false)) {
    return null;
  }
  const replies = await api.listCheckRuns({ sha: head, checkName: settings.replyCheckName, appId: settings.appId });
  const newest = replies.reduce((a, b) => (startOf(b) > startOf(a) ? b : a), replies[0]);
  if (releases(newest)) {
    const skips = replies.filter(releases).length;
    if (skips >= SWEEP_HEAD_CAP) {
      log(`skip: #${pull.number}: head ${head} was released ${skips} times, the sweep's cap`);
      return null;
    }
  } else if (
    pull.user?.id === appSenderId ||
    // A check dispatchFeedback would not count (the gate's untrusted-trigger
    // skip, a reset limit stop) leaves a session PR's head to the sweep,
    // its only path; dispatchFeedback decides again with the config's limits.
    anyHandles(await api.listCheckRuns({ sha: head, checkName: settings.checkName, appId: settings.appId }), { now: rest.now ?? Date.now() })
  ) {
    return null;
  }
  const reviewRuns = await reviewRunsAt({ api, head, settings });
  const upstream = await reviewRunAt({ api, head, settings, runs: reviewRuns });
  if (upstream === null) {
    log(`skip: #${pull.number}: head ${head} has no completed review run`);
    return null;
  }
  const dispatched = await dispatchFeedback({ ...rest, api, repository, appSenderId, log, settings, upstream, reviewRuns, reviewThreads });
  return dispatched === null ? null : { ...dispatched, upstreamRunId: upstream.id };
}

const THREADS_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          isResolved
          comments(first: 100) {
            nodes {
              author { login ... on Bot { databaseId } ... on User { databaseId } }
              createdAt body lastEditedAt
              editor { ... on Bot { databaseId } ... on User { databaseId } }
            }
            pageInfo { hasNextPage }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

export function createGitHubApi({ token, repository, apiUrl, graphqlUrl, fetch = globalThis.fetch, attemptTimeoutMs }) {
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
      throw Object.assign(new Error(`${method} ${url} returned ${response.status}`), { rateLimited: response.rateLimited === true });
    }
    return response.status === 204 ? {} : response.json();
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
        throw new Error(`GET ${url} returned ${response.status}`);
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
    // The newest completed pull_request runs of a workflow file at a head.
    async listCompletedRuns(path, head) {
      const query = new URLSearchParams({ head_sha: head, event: "pull_request", status: "completed", per_page: "10" });
      return (await request(`${repo}/actions/workflows/${path.split("/").at(-1)}/runs?${query}`)).workflow_runs ?? [];
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
// The base config's `adoption` section as set; a config that cannot be read
// works no session PR this run.
async function baseAdoption(env, log) {
  try {
    const { adoptionFromBase } = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
    return adoptionFromBase({ BASE_PATH: env.BASE_PATH || ".base" });
  } catch (error) {
    log(`::warning::cannot read the base config's adoption section (${error.message}); no session PR is worked this run`);
    return {};
  }
}

export async function main(env, { api, github, resolveSlot, log = (line) => console.log(line), loadAdoption, now } = {}) {
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
    // The base checkout's list, the one resolve-config reads beside it.
    trustedHumans: trustedHumansFrom(env.TRUSTED_ACTORS || `${env.BASE_PATH || ".base"}/.github/standards/trusted-actors/trusted-actors.json`),
    humanGatedLabel: humanGatedLabelFrom(env.TRACKER_CONFIG || `${env.BASE_PATH || ".base"}/.work-item-tracker.json`),
    resolveSlot: resolveSlot ?? (({ number, head }) => resolveFeedbackSlot({ number, head, env, github })),
    log,
    // Read at most once, and only for a trusted person's PR.
    loadAdoption: (() => {
      let read = null;
      return () => (read ??= (loadAdoption ?? (() => baseAdoption(env, log)))());
    })(),
    ...(now === undefined ? {} : { now }),
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
    const swept = await sweepReleased(common).finally(summary);
    if (swept !== null) {
      appendFileSync(env.GITHUB_OUTPUT, `run-id=${swept.workflowRunId}\nupstream-run-id=${swept.upstreamRunId}\n`);
    }
    return 0;
  }
  let notesSince = null;
  if (upstream?.path === VERIFY_WORKFLOW) {
    const head = env.VERIFY_HEAD_SHA ?? "";
    if (!SHA.test(head)) {
      throw new Error("a pr-verify run names no posted head in VERIFY_HEAD_SHA");
    }
    notesSince = Date.parse((await client.getWorkflowRun(upstream.id)).created_at ?? "");
    if (Number.isNaN(notesSince)) {
      throw new Error(`pr-verify run ${upstream.id} has no readable creation time`);
    }
    upstream = await reviewRunAt({ api: client, head });
    if (upstream === null) {
      log(`skip: head ${head} has no completed review run yet; the review run dispatches when it completes`);
      return 0;
    }
  }
  const dispatched = await dispatchFeedback({ ...common, record, upstream, notesSince }).finally(summary);
  if (dispatched !== null) {
    appendFileSync(env.GITHUB_OUTPUT, `run-id=${dispatched.workflowRunId}\nupstream-run-id=${upstream.id}\n`);
  }
  if (writeRecord(env.DISPATCH_RECORD, record, text)) {
    appendFileSync(env.GITHUB_OUTPUT, "record-changed=true\n");
  }
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::pr-feedback dispatch failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
