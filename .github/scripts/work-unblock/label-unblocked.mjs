#!/usr/bin/env node
// label-unblocked.mjs: when an issue closes, labels `agent-ready` each issue
// it blocked that is now ready for the resolve-issue lane, which the label
// starts: open, every blocker closed as completed by a listed human or a
// merge (a pull request blocker: merged), no hold label, and not already
// agent-ready. Every fact is read from the API now, never from the event
// payload. No model.
//
// On `schedule` it sweeps instead: every issue closed in the last
// LOOKBACK_HOURS goes through the same rules, so an issue a bot closed (a
// pull request merge), which starts no close run, is still picked up. A
// swept close counts only when a listed human or a merge made it. Overlapping
// windows are harmless: an issue already labeled is left alone, and one whose
// label was ever removed (by a person, or by a lane's pushback) is never
// labeled again. A removal by the lanes App that follows the App's own
// limited marker is a restart, not a stop, and does not count.
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
// listed human or the App) failed with no lanes-App outcome marker since: a
// crash before the report, or a rerun the token broker refused as
// workflow-modified. A rerun keeps its first event's workflow files, so only a
// fresh label event runs on main's. Each issue is re-fired at most once per
// version of the two lane workflow files on main, recorded in a marker comment
// posted before the label moves, so a run that keeps failing stops until a
// workflow change lands.
//
// A run that minted no lane token did no work and ran no model: the WIP cap
// skipped its resolve-issue job, or its `Request the lane token` step failed
// (GitHub's rate limit past the retry budget among the reasons). Such a run is
// re-fired with the same record: a failed mint up to limits.limit-stops-per-issue
// times per version of the lane workflow files, a WIP cap skip without a
// per-issue bound. It waits limits.reset-clamp-min hours after the run ended, past any reset
// the broker passes on (its Retry-After is at most an hour), and only while
// the issue lane's WIP cap check (check-wip-cap.mjs) does not pause it. It is no
// limit stop, so it never counts toward handing the issue to a person.
//
// When that label's run opened a pull request instead, the newest one the
// lanes App opened from the issue's lane branch in this repository decides.
// Merged with `Refs:` (the issue stays open with nothing to run) or closed
// unmerged, the App adds needs-triage and removes
// agent-ready, so triage decides what is left; a person adding agent-ready
// again re-runs it. Open, it waits: report-outcome put needs-human on the
// issue of a Refs PR, and this lifts that hold only when that PR merges,
// only while its refs-hold marker and the App's needs-human label are the
// newest. Each hand-off also counts against limits.restarts-per-run.
//
// It relabels a red-main fix issue post-merge-demotion-alert.yml reopened on
// a repeat failure: the reopen keeps agent-ready but ran on that workflow's
// GITHUB_TOKEN, which starts no run. An open agent-ready issue filed by
// github-actions[bot] with a `<!-- post-merge-fix check=... -->` first line
// and a newest github-actions[bot] recurrence comment, with no agent-ready
// added since that comment, no hold, no open lane PR and no lane run in
// flight, gets a record naming that comment and agent-ready removed and added
// by the App. Relabels share limits.restarts-per-run, and the count is logged
// before any of them.
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
//   TRIGGERING_ACTOR       who started this run (a re-runner may differ);
//                          must be a listed human (`issues` only)
//   ACTIONS_TOKEN          the job's GITHUB_TOKEN (actions: read), to list
//                          work-resolve-issue runs; unset skips the re-fire
//   LANES_BOT_LOGIN        the lanes App bot login, the only author of a marker
//                          and actor of a restart this trusts (default
//                          melodic-automation-lanes[bot])
//   GITHUB_API_URL
//   RESOLVED_CONFIG        resolve-config's output (default
//                          $RUNNER_TEMP/resolved-config.json), for the limits
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { checkWip, searchRateLimit } from "../../actions/check-wip-cap/check-wip-cap.mjs";
import { clampReset, isLaneBranch, parseOutcomeMarker, refsHoldMarker } from "../work-resolve-issue/report-outcome.mjs";
import { readLimits, readWip } from "../work-resolve-issue/limits.mjs";

const LABEL = "agent-ready";
const HUMAN_LABEL = "needs-human";
const TRIAGE_LABEL = "needs-triage";
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
const REFIRED = /^<!-- work-unblock refired ([0-9a-f]{40}-[0-9a-f]{40}) -->/;
const handedMarker = (pr) => `<!-- work-unblock handed triage #${pr} -->`;
const DEFAULT_BOT = "melodic-automation-lanes[bot]";
// A person decides these; the lane never starts on them.
const HOLDS = new Set(["needs-owner-decision", "status: needs-decision", "needs-human"]);
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
// The sweep's window: three hourly runs overlap, so a missed run loses nothing.
export const LOOKBACK_HOURS = 3;

// Whether the account that closed the issue (ACTOR_ID, by id) and the one
// that started this run (TRIGGERING_ACTOR, by login; a re-runner may be
// another account) are each a listed human. The broker mints only then.
export function checkCloser(env) {
  if (!NUMBER.test(env.ACTOR_ID ?? "")) {
    return false;
  }
  const { humans, logins } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
  const rerunner = logins.get(String(env.TRIGGERING_ACTOR ?? "").toLowerCase());
  return humans.has(Number(env.ACTOR_ID)) && rerunner !== undefined && humans.has(rerunner);
}

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const reportError = (number, error) =>
  console.log(`::error title=label-unblocked::#${number}: ${escapeCommand(error?.message ?? error)}`);

const isLabel = (event, kind) => event.event === kind && String(event.label?.name).toLowerCase() === LABEL;

// A re-fire marker reads as outcome `refired` with its workflow key.
const parseMarker = (body) => {
  const refire = REFIRED.exec(String(body ?? ""));
  return refire ? { outcome: "refired", key: refire[1] } : parseOutcomeMarker(body);
};

// The lanes App's outcome and re-fire markers on an issue, oldest first, each
// with when it was posted.
const appMarkers = (comments, bot) =>
  comments
    .filter((comment) => comment.user?.login === bot)
    .map((comment) => ({ ...parseMarker(comment.body), at: Date.parse(comment.created_at) }))
    .filter((marker) => marker.outcome !== undefined && Number.isFinite(marker.at));

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

// Why `number` is not promoted, or null when it is ready.
async function refusal({ github, repo, number, humans, closes, bot = DEFAULT_BOT }) {
  const base = `/repos/${repo}/issues/${number}`;
  const current = await github("GET", base);
  if (current.state !== "open") {
    return "not open";
  }
  const labels = (current.labels ?? []).map((label) => (typeof label === "string" ? label : label.name));
  const lower = labels.map((label) => String(label).toLowerCase());
  const held = lower.find((label) => HOLDS.has(label));
  if (held) {
    return `held by ${held}`;
  }
  if (lower.includes(LABEL)) {
    return `already ${LABEL}`;
  }
  // A blocker closed as not planned or duplicate never did the work, so only
  // a completed close counts; a pull request counts only once merged. Any
  // issue author can close their own issue as completed, so a blocking issue
  // also needs a trusted close (trustedClose), read fresh from the issue
  // itself. A blocker in another repository cannot be read with this
  // repository's token, so it never counts.
  const blockers = await paginate(github, `${base}/dependencies/blocked_by`);
  const closedHere = (blocker) =>
    blocker.state === "closed" && String(blocker.repository_url ?? "").toLowerCase().endsWith(`/repos/${repo}`.toLowerCase());
  const issues = [];
  let pending = 0;
  for (const blocker of blockers) {
    if (!closedHere(blocker)) {
      pending += 1;
    } else if (blocker.pull_request) {
      pending += blocker.pull_request.merged_at ? 0 : 1;
    } else if (blocker.state_reason !== "completed" || !NUMBER.test(String(blocker.number))) {
      pending += 1;
    } else {
      issues.push(Number(blocker.number));
    }
  }
  for (const blocker of pending === 0 ? issues : []) {
    if (!(await trustedClose({ github, repo, number: blocker, humans, closes }))) {
      pending += 1;
    }
  }
  if (pending > 0) {
    return `${pending} blocker(s) not closed as completed by a listed human or a merge`;
  }
  // Removing the label by hand stops the lane; a person adds it to restart.
  const comments = await paginate(github, `${base}/comments`);
  const markers = appMarkers(comments, bot);
  const events = await paginate(github, `${base}/events`);
  if (events.some((event, index) => isLabel(event, "unlabeled") && !isRestart(events, index, markers, bot))) {
    return `${LABEL} was removed before`;
  }
  return null;
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

// Whether a close counts: (a) a listed human made it, matched by id; or (b) a
// merge in this repository closed it: the `closer` GraphQL gives the issue's
// last ClosedEvent is a merged pull request or a commit here, whoever merged
// it. The REST close event carries no link to the pull request, so GraphQL
// is the read. Any
// other close, such as a workflow's GITHUB_TOKEN or an outside author closing
// their own issue, counts for nothing.
const CLOSER_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      timelineItems(itemTypes: CLOSED_EVENT, last: 1) {
        nodes { ... on ClosedEvent { closer {
          __typename
          ... on PullRequest { merged repository { nameWithOwner } }
          ... on Commit { repository { nameWithOwner } }
        } } }
      }
    }
  }
}`;
// One answer per issue per run: a swept close is also its dependents'
// blocker, and a blocker can block several dependents.
function trustedClose({ github, repo, number, humans, closes }) {
  if (!closes.has(number)) {
    closes.set(number, (async () => isTrustedClose(github, repo, await github("GET", `/repos/${repo}/issues/${number}`), humans))());
  }
  return closes.get(number);
}

async function isTrustedClose(github, repo, closedIssue, humans) {
  const closer = closedIssue?.closed_by;
  if (humans.has(closer?.id)) {
    return true;
  }
  if (closedIssue?.state !== "closed" || !NUMBER.test(String(closedIssue.number))) {
    return false;
  }
  const [owner, name] = repo.split("/");
  const answer = await github("POST", "/graphql", {
    query: CLOSER_QUERY,
    variables: { owner, name, number: Number(closedIssue.number) },
  });
  const by = answer?.data?.repository?.issue?.timelineItems?.nodes?.at(-1)?.closer;
  const here = String(by?.repository?.nameWithOwner ?? "").toLowerCase() === repo.toLowerCase();
  return here && (by.__typename === "Commit" || (by.__typename === "PullRequest" && by.merged === true));
}

// Labels each issue `closed` blocked that is ready, each at most once per run.
// Returns how many reads or writes failed.
async function labelUnblocked({ github, repo, closed, sweep, humans, bot }) {
  const seen = new Set();
  const closes = new Map();
  let failed = 0;
  for (const source of closed) {
    let blocked;
    try {
      if (sweep && !(await trustedClose({ github, repo, number: source, humans, closes }))) {
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
      if (seen.has(number)) {
        continue;
      }
      seen.add(number);
      try {
        const reason = await refusal({ github, repo, number, humans,closes, bot });
        if (reason !== null) {
          console.log(`label-unblocked: #${number} not labeled: ${reason}`);
          continue;
        }
        await github("POST", `/repos/${repo}/issues/${number}/labels`, { labels: [LABEL] });
        console.log(`label-unblocked: #${number} labeled ${LABEL}`);
      } catch (error) {
        failed += 1;
        reportError(number, error);
      }
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
export const refireComment = (key) =>
  `<!-- work-unblock refired ${key} -->\nThe work-resolve-issue run that \`${LABEL}\` started failed before it reported, or the token broker refused it because its workflow files differ from main's. work-unblock removed and added \`${LABEL}\` back to start a fresh run on main's workflow files. It does this once per version of those files, so if this run fails the same way, a person looks at it.`;

// The relabel's record, posted before the label moves: one per recurrence
// comment.
export const recurrenceComment = (id) =>
  `<!-- work-unblock recurrence ${id} -->\nThis check failed on main again, and post-merge-demotion-alert reopened this issue, which starts no work-resolve-issue run. work-unblock removed and added \`${LABEL}\` back to start one. It does this once per reopen.`;

// The hand-offs to triage once the lane PR ended, each posted once per pull
// request before its labels move.
export const refsMergedComment = (pr) =>
  `${handedMarker(pr)}\nThe lanes App's pull request #${pr} merged with \`Refs:\`, so this issue stays open and nothing starts the lane on it again. work-unblock added \`${TRIAGE_LABEL}\` and removed \`${LABEL}\`, so triage decides what work is left.`;
export const refsClosedComment = (pr) =>
  `${handedMarker(pr)}\nThe lanes App's pull request #${pr} for this issue was closed without merging. work-unblock added \`${TRIAGE_LABEL}\` and removed \`${LABEL}\`, so triage decides what work is left; the lane does not run again on its own. To run it again, add \`${LABEL}\`.`;

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
// wins) or was skipped by the WIP cap (`capped`: pick-slot ran, resolve-issue
// did not). A run another gate stopped before its mint (an open closing PR, a
// reused branch) is neither, so it is never re-fired here.
async function didNoWork(actions, repo, runs) {
  let stalled = null;
  for (const run of runs) {
    if (!RUN_ID.test(String(run.id))) {
      return null;
    }
    const jobs = (await actions("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`))?.jobs;
    if (!Array.isArray(jobs)) {
      throw new Error(`run ${run.id}'s job listing has an unexpected shape`);
    }
    const mints = jobs.flatMap((job) => (job?.steps ?? []).filter((step) => step?.name === MINT_STEP));
    if (mints.some((step) => step.conclusion === "success")) {
      return null;
    }
    const named = (name) => jobs.filter((job) => job?.name === name || String(job?.name).startsWith(`${name} /`));
    const capped =
      named("pick-slot").some((job) => job.conclusion === "success") &&
      named("resolve-issue").length > 0 &&
      named("resolve-issue").every((job) => job.conclusion === "skipped");
    if (mints.some((step) => step.conclusion === "failure")) {
      stalled = "mint-failed";
    } else if (capped) {
      stalled ??= "capped";
    }
  }
  return stalled;
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
async function recurrenceRefusal({ github, repo, issue, bot, inFlight }) {
  if (issue.user?.login !== ALERT_BOT || !FIX_ISSUE.test(String(issue.body ?? ""))) {
    return null;
  }
  const base = `/repos/${repo}/issues/${issue.number}`;
  const comments = await paginate(github, `${base}/comments`);
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
  const events = await paginate(github, `${base}/events`);
  if (events.some((event) => isLabel(event, "labeled") && Date.parse(event.created_at) >= at)) {
    return null;
  }
  const held = (issue.labels ?? []).map((label) => String(typeof label === "string" ? label : label.name).toLowerCase()).find((label) => HOLDS.has(label));
  if (held) {
    return { reason: `held by ${held}` };
  }
  const open = (await lanePulls({ github, repo, number: issue.number, bot })).find((pull) => pull.state === "open");
  if (open) {
    return { reason: `its lane PR #${open.number} is open` };
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
// a merge of the Refs PR report-outcome set it for lifts.
function pullRefusal({ pull, number, comments, events, bot, held }) {
  const byApp = (marker) => comments.some((comment) => comment.user?.login === bot && String(comment.body ?? "").startsWith(marker));
  const refs = String(pull.body ?? "").split(/\r?\n/, 1)[0].trim() === `Refs: #${number}`;
  const merged = Boolean(pull.merged_at);
  if (held) {
    const human = events.filter((event) => ["labeled", "unlabeled"].includes(event.event) && String(event.label?.name).toLowerCase() === HUMAN_LABEL);
    const newest = human.at(-1);
    const ours = newest?.event === "labeled" && newest.actor?.login === bot && byApp(refsHoldMarker(pull.number));
    if (!(ours && merged && refs)) {
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
async function refireRefusal({ github, actions, repo, number, lastAdd, addedAt, markers, comments, events, humans, bot, workflowKey, held, limits, now, wipCapped }) {
  if (lastAdd.actor?.login !== bot && !humans.has(lastAdd.actor?.id)) {
    return { reason: `${LABEL} was added by neither a listed human nor the lanes App` };
  }
  const pull = await lastLanePull({ github, repo, number, addedAt, bot });
  if (pull !== null) {
    return pullRefusal({ pull, number, comments, events, bot, held });
  }
  if (held) {
    return { reason: `held by ${HUMAN_LABEL}` };
  }
  if (!actions) {
    return { reason: "no Actions token to read its lane run" };
  }
  const { mine: runs, untitled } = await laneRuns(actions, repo, number, addedAt);
  if (runs.length === 0) {
    return {
      reason:
        untitled > 0
          ? `cannot tell whether a lane run started since ${LABEL} was added: ${untitled} work-resolve-issue run(s) then name no issue in their title`
          : `no lane run since ${LABEL} was added`,
    };
  }
  if (runs.some((run) => run.status !== "completed")) {
    return { reason: "its lane run is still going" };
  }
  const stalled = await didNoWork(actions, repo, runs);
  if (stalled) {
    const ended = Math.max(...runs.map((run) => Date.parse(run.updated_at)).filter(Number.isFinite), addedAt);
    const due = ended + limits["reset-clamp-min"] * HOUR_MS;
    if (now < due) {
      return { reason: `its lane run did no work; it is re-fired after ${new Date(due).toISOString()}` };
    }
    if (await wipCapped()) {
      return { reason: "its lane run did no work, and the issue lane is paused over its WIP cap" };
    }
    const key = await workflowKey();
    // A record after the newest label is one whose label write failed: the
    // sweep finishes it without posting another.
    const recorded = markers.some((marker) => marker.outcome === "refired" && marker.at >= addedAt);
    // A mint that keeps failing (a broker misconfigured, an issue it refuses)
    // stops after limits.limit-stops-per-issue re-fires on these workflow
    // files, as a crash stops after one. A WIP cap skip made no mint attempt,
    // and the cap and restarts-per-run bound it.
    const fired = markers.filter((marker) => marker.outcome === "refired" && marker.key === key).length;
    if (stalled === "mint-failed" && !recorded && fired >= limits["limit-stops-per-issue"]) {
      return { reason: `its lane token request failed after ${fired} re-fires on workflow files ${key}` };
    }
    return { reason: null, resets: due, refire: key, recorded };
  }
  if (!runs.some((run) => FAILED.has(run.conclusion))) {
    return { reason: "its lane run did not fail" };
  }
  const key = await workflowKey();
  // A record counts once the App added the label back at or after it; one
  // whose label write failed is finished by the next sweep, not posted again.
  const recorded = markers.filter((marker) => marker.outcome === "refired" && marker.key === key);
  const relabeled = (marker) =>
    events.some((event) => isLabel(event, "labeled") && event.actor?.login === bot && Date.parse(event.created_at) >= marker.at);
  if (recorded.some(relabeled)) {
    return { reason: `already re-fired for workflow files ${key}` };
  }
  return { reason: null, resets: addedAt, refire: key, recorded: recorded.length > 0 };
}

// Why an agent-ready issue is not restarted now (after a limit stop) or
// re-fired (after a failed run), or null with the time it has waited since.
// Every fact is read fresh from the API.
async function restartRefusal({ github, actions, repo, issue, bot, humans, now, workflowKey, limits, wipCapped }) {
  const base = `/repos/${repo}/issues/${issue.number}`;
  const labels = (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label.name));
  const holds = labels.map((label) => String(label).toLowerCase()).filter((label) => HOLDS.has(label));
  // needs-human alone may be report-outcome's hold on a Refs PR, which the
  // lane PR check below may lift; any other hold stops everything here.
  const held = holds.length > 0;
  if (held && (holds.length > 1 || holds[0] !== HUMAN_LABEL)) {
    return { reason: `held by ${holds.find((label) => label !== HUMAN_LABEL)}` };
  }
  const comments = await paginate(github, `${base}/comments`);
  const markers = appMarkers(comments, bot);
  // A re-fire record ends no run, so only outcome markers count here.
  const marker = markers.filter((item) => item.outcome !== "refired").at(-1);
  const events = await paginate(github, `${base}/events`);
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
async function restartLimited({ github, actions, repo, bot, humans, now, limits, wip, remaining, cap = limits["restarts-per-run"] }) {
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
  // The issue lane's pause, read once per run; a read that fails never pauses.
  let capped;
  const wipCapped = () => (capped ??= checkWip(github, { repo, bot, now, limits, wip, remaining }).then((status) => status.paused));
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
    try {
      const verdict =
        (await recurrenceRefusal({ github, repo, issue, bot, inFlight })) ??
        (await restartRefusal({
          github,
          actions,
          repo,
          issue,
          bot,
          humans,
          now,
          workflowKey,
          limits,
          wipCapped,
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
  for (const { number, refire, recurrence, recorded, handOff, pr, explained, release } of ready.slice(0, cap)) {
    const base = `/repos/${repo}/issues/${number}`;
    if (handOff) {
      // The comment first, then the labels; agent-ready comes off last, so a
      // failed write leaves the issue for the next sweep, which finds the
      // comment and moves only the labels.
      try {
        if (!explained) {
          await github("POST", `${base}/comments`, { body: handOff === "merged" ? refsMergedComment(pr) : refsClosedComment(pr) });
        }
        await github("POST", `${base}/labels`, { labels: [TRIAGE_LABEL] });
        if (release) {
          await github("DELETE", `${base}/labels/${HUMAN_LABEL}`);
        }
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
        await github("POST", `${base}/comments`, { body: refireComment(refire) });
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
      const why = refire ? "re-fired after its failed run" : recurrence ? "relabeled after its reopen on a repeat failure" : "restarted after its limit stop";
      console.log(`label-unblocked: #${number} ${why}`);
    } catch (error) {
      failed += 1;
      reportError(number, new Error(`${LABEL} was removed for a restart but not added back: ${error?.message ?? error}`));
    }
  }
  return failed;
}

export async function main({ env = process.env, github, actions, now = Date.now(), rate = searchRateLimit() } = {}) {
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
      if (!checkCloser(env)) {
        console.log("label-unblocked: the closer or the re-runner is not a listed human; nothing read or labeled");
        return 0;
      }
    }
    const repo = env.GITHUB_REPOSITORY;
    const humans = loadTrustedList(env.TRUSTED_ACTORS_PATH).humans;
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, onResponse: rate.onResponse });
    const closed = sweep
      ? await closedSince(github, repo, new Date(now - LOOKBACK_HOURS * 3_600_000))
      : [Number(event.issue.number)];
    if (sweep) {
      console.log(`label-unblocked: ${closed.length} issue(s) closed in the last ${LOOKBACK_HOURS} hours`);
    }
    const bot = env.LANES_BOT_LOGIN || DEFAULT_BOT;
    let failed = await labelUnblocked({ github, repo, closed, sweep, humans, bot });
    if (sweep) {
      actions ??= env.ACTIONS_TOKEN ? createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined }) : null;
      const resolved = env.RESOLVED_CONFIG || `${env.RUNNER_TEMP ?? ""}/resolved-config.json`;
      failed += await restartLimited({ github, actions, repo, bot, humans, now, limits: readLimits(resolved), wip: readWip(resolved), remaining: rate.remaining });
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
    const proceed = checkCloser(process.env);
    writeOutputs({ proceed: String(proceed) });
    console.log(`label-unblocked: closer and re-runner ${proceed ? "are" : "are not both"} listed humans`);
  } else {
    process.exitCode = await main();
  }
}
