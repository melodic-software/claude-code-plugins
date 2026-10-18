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
// added again by the App, which starts the lane. At most RESTARTS_PER_RUN
// issues per run, longest-waiting first.
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
// When that label's run opened a pull request instead, the newest one the
// lanes App opened from the issue's lane branch in this repository decides:
//   merged with `Refs:`   the issue stays open with nothing to run, so the App
//                         adds needs-triage and removes agent-ready;
//   closed unmerged       re-fired the same way, once per close, under the
//                         same marker bound;
//   open                  when the newest successful pr-merge run's gate
//                         refused it at its current head for having no linked
//                         issue (the LINKED_NONE reason, read from that run's
//                         log), the lane never merges it, so the App adds
//                         needs-human to the issue.
// Each of these also counts against RESTARTS_PER_RUN.
//
// Environment:
//   GH_TOKEN               the lane App token (issues: write)
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
//                          work-resolve-issue runs and read pr-merge's gate
//                          log; unset skips the re-fire after a failed run
//                          and the needs-human hand-off
//   LANES_BOT_LOGIN        the lanes App bot login, the only author of a marker
//                          and actor of a restart this trusts (default
//                          melodic-automation-lanes[bot])
//   GITHUB_API_URL
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { clampReset, isLaneBranch, parseOutcomeMarker } from "../work-resolve-issue/report-outcome.mjs";

const LABEL = "agent-ready";
const HUMAN_LABEL = "needs-human";
const TRIAGE_LABEL = "needs-triage";
// pr-merge's refusal of a lane PR whose body links its issue with `Refs:`.
const LINKED_NONE = "ineligible:linked-issues:0";
// The eligibility check's own reason, which stays put when an earlier refusal
// (`in-flight:`, `rung-off:`) is the gate's first.
const LINKED_ELIGIBILITY = "linked-issues:0";
// The lane's caller and the write runner: the broker refuses a run whose copy
// of either differs from main's.
const LANE_WORKFLOWS = [".github/workflows/pr-run-activity-write.yml", ".github/workflows/work-resolve-issue.yml"];
const FAILED = new Set(["failure", "timed_out", "startup_failure"]);
// A label event's run is created within seconds; this window finds it.
const RUN_WINDOW_MS = 10 * 60_000;
const BLOB = /^[0-9a-f]{40}$/;
// The key is main's two lane workflow blob SHAs, or `pr-<number>-<closed at,
// epoch ms>` for a lane PR closed unmerged.
const REFIRED = /^<!-- work-unblock refired ([0-9a-f]{40}-[0-9a-f]{40}|pr-[1-9][0-9]{0,9}-[0-9]{1,15}) -->/;
const handedMarker = (kind, pr) => `<!-- work-unblock handed ${kind} #${pr} -->`;
const DEFAULT_BOT = "melodic-automation-lanes[bot]";
// Hard-coded until pr-pipeline.yaml has a limits.restarts-per-run leaf:
// https://github.com/melodic-software/claude-code-plugins/issues/7764
export const RESTARTS_PER_RUN = 5;
// Limit stops since a person last added agent-ready before the issue goes to
// a person instead of another restart (judgment).
export const MAX_LIMIT_STOPS = 3;
// A person decides these; the lane never starts on them.
const HOLDS = new Set(["needs-owner-decision", "status: needs-decision", "needs-human"]);
const NUMBER = /^[1-9][0-9]{0,9}$/;
// Run and job ids are past ten digits.
const RUN_ID = /^[1-9][0-9]{0,15}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
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

// A removal of agent-ready is a restart, not a stop, only when the App made
// it, the App's newest marker before it is `limited` or a re-fire, and the next agent-ready
// event after it is the App adding the label back. Any other removal stops the
// lane, a pushback after a restart included.
function isRestart(events, index, markers, bot) {
  const removal = events[index];
  const at = Date.parse(removal.created_at);
  const newest = markers.filter((marker) => marker.at <= at).at(-1)?.outcome;
  if (removal.actor?.login !== bot || (newest !== "limited" && newest !== "refired")) {
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

// The hand-off to a person after MAX_LIMIT_STOPS limit stops. Its marker lets
// a later sweep see the comment was posted.
const ESCALATED = "<!-- work-unblock escalated -->";
export const escalationComment = (stops) =>
  `${ESCALATED}\nThe usage limit stopped the work-resolve-issue lane on this issue ${stops} times since a person last added \`${LABEL}\`, so work-unblock no longer restarts it. To try again, remove \`${HUMAN_LABEL}\`, then remove \`${LABEL}\` and add it back: adding it starts a new run and starts the count again. Removing \`${LABEL}\` by hand also means work-unblock never adds it to this issue again when its blockers close; from then on a person adds it.`;

// The re-fire's record, posted before the label moves: one per issue per
// version of the lane workflow files.
export const refireComment = (key) =>
  `<!-- work-unblock refired ${key} -->\nThe work-resolve-issue run that \`${LABEL}\` started failed before it reported, or the token broker refused it because its workflow files differ from main's. work-unblock removed and added \`${LABEL}\` back to start a fresh run on main's workflow files. It does this once per version of those files, so if this run fails the same way, a person looks at it.`;

// The re-fire's record when the lane PR was closed without merging: one per close.
export const closedRefireComment = (key, pr) =>
  `<!-- work-unblock refired ${key} -->\nThe lanes App's pull request #${pr} for this issue was closed without merging, and \`${LABEL}\` stayed on. work-unblock removed and added \`${LABEL}\` back to start a fresh run. It does this once per close. To stop the lane on this issue instead, remove \`${LABEL}\`.`;

// The hand-offs when the lane PR links the issue with `Refs:`, each posted
// once per pull request before its labels move.
export const refsMergedComment = (pr) =>
  `${handedMarker("triage", pr)}\nThe lanes App's pull request #${pr} merged with \`Refs:\`, so this issue stays open and nothing starts the lane on it again. work-unblock added \`${TRIAGE_LABEL}\` and removed \`${LABEL}\`, so triage decides what work is left.`;
export const refsRefusedComment = (pr) =>
  `${handedMarker("human", pr)}\nThe pr-merge lane refuses the lanes App's pull request #${pr} as \`${LINKED_NONE}\`: its body links this issue with \`Refs:\`, not \`Closes\`, so the lane never merges it. work-unblock added \`${HUMAN_LABEL}\` so a person merges or closes it.`;

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

// The re-fire bound: a record counts once the App added the label back at or
// after it; one whose label write failed is finished by the next sweep, not
// posted again. Null reason with the key to record, else why not.
function refireBound({ markers, events, bot, key, resets, comment, note, what }) {
  const recorded = markers.filter((marker) => marker.outcome === "refired" && marker.key === key);
  const relabeled = (marker) =>
    events.some((event) => isLabel(event, "labeled") && event.actor?.login === bot && Date.parse(event.created_at) >= marker.at);
  if (recorded.some(relabeled)) {
    return { reason: `already re-fired for ${what}` };
  }
  return { reason: null, resets, refire: key, comment, note, recorded: recorded.length > 0 };
}

const sameRepo = (side, repo) => String(side?.repo?.full_name ?? "").toLowerCase() === repo.toLowerCase();

// The newest pull request the lanes App opened for issue `number` at or after
// `addedAt`: cross-referenced on the issue, from the issue's lane branch, with
// head and base in this repository. Null when there is none.
async function lastLanePull({ github, repo, number, addedAt, bot }) {
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
  let last = null;
  for (const pr of numbers) {
    const pull = await github("GET", `/repos/${repo}/pulls/${pr}`);
    const created = Date.parse(pull?.created_at);
    if (
      pull?.user?.login === bot &&
      sameRepo(pull.head, repo) &&
      sameRepo(pull.base, repo) &&
      isLaneBranch(pull.head?.ref, number) &&
      created >= addedAt &&
      (last === null || created > Date.parse(last.created_at))
    ) {
      last = pull;
    }
  }
  return last;
}

// What the lane PR the newest agent-ready label's run opened asks for: a
// hand-off to triage (merged with `Refs:`), a re-fire (closed unmerged), a
// hand-off to a person (open, refused by pr-merge as LINKED_NONE at its
// head), or nothing, with why.
async function pullRefusal({ pull, number, markers, comments, events, bot, gate }) {
  const handed = (kind) =>
    comments.some((comment) => comment.user?.login === bot && String(comment.body ?? "").startsWith(handedMarker(kind, pull.number)));
  const refsThis = String(pull.body ?? "").split(/\r?\n/, 1)[0].trim() === `Refs: #${number}`;
  if (pull.state === "open") {
    if (!gate) {
      return { reason: `its lane PR #${pull.number} is open; no Actions token to read pr-merge's refusal` };
    }
    const refused = (await gate()).get(pull.number);
    if (refused?.eligibility === LINKED_ELIGIBILITY && refused.head === pull.head?.sha && refsThis) {
      return { reason: null, handOff: "human", pr: pull.number, resets: Date.parse(pull.created_at), explained: handed("human") };
    }
    return { reason: `its lane PR #${pull.number} is open` };
  }
  if (pull.merged_at) {
    if (refsThis) {
      return { reason: null, handOff: "triage", pr: pull.number, resets: Date.parse(pull.merged_at), explained: handed("triage") };
    }
    return { reason: `its lane PR #${pull.number} merged` };
  }
  const closed = Date.parse(pull.closed_at);
  if (!Number.isFinite(closed)) {
    throw new Error(`lane PR #${pull.number} is closed with no readable close time`);
  }
  const key = `pr-${pull.number}-${closed}`;
  return refireBound({
    markers,
    events,
    bot,
    key,
    resets: closed,
    comment: closedRefireComment(key, pull.number),
    note: `re-fired after its lane PR #${pull.number} closed unmerged`,
    what: `the close of lane PR #${pull.number}`,
  });
}

// Why an agent-ready issue whose newest label has no marker after it is not
// re-fired or handed off now, or null with what to do.
async function refireRefusal({ github, actions, repo, number, lastAdd, addedAt, markers, comments, events, humans, bot, workflowKey, gate }) {
  if (lastAdd.actor?.login !== bot && !humans.has(lastAdd.actor?.id)) {
    return { reason: `${LABEL} was added by neither a listed human nor the lanes App` };
  }
  const pull = await lastLanePull({ github, repo, number, addedAt, bot });
  if (pull !== null) {
    return pullRefusal({ pull, number, markers, comments, events, bot, gate });
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
  if (!runs.some((run) => FAILED.has(run.conclusion))) {
    return { reason: "its lane run did not fail" };
  }
  const key = await workflowKey();
  return refireBound({
    markers,
    events,
    bot,
    key,
    resets: addedAt,
    comment: refireComment(key),
    note: "re-fired after its failed run",
    what: `workflow files ${key}`,
  });
}

// pr-merge's gate prints each candidate's verdict as a JSON object inside a
// `PR #<n> at <head>: exit <code>` log group. Each PR's refusal reason
// (`unattended.reason`) with the head it was checked at; a group that is not
// one JSON object is skipped.
const GATE_GROUP = /^##\[group\]PR #([1-9][0-9]{0,9}) at ([0-9a-f]{40}): exit [0-9]+$/;
const LOG_STAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z ?/;
export function gateRefusals(log) {
  const refusals = new Map();
  let group = null;
  for (const raw of String(log).split("\n")) {
    const line = raw.replace(/\r$/, "").replace(LOG_STAMP, "");
    if (group === null) {
      const match = GATE_GROUP.exec(line);
      group = match ? { pr: Number(match[1]), head: match[2], lines: [] } : null;
    } else if (line === "##[endgroup]") {
      let verdict;
      try {
        verdict = JSON.parse(group.lines.join("\n"));
      } catch {
        verdict = null;
      }
      const reason = verdict?.unattended?.reason;
      const eligibility = verdict?.unattended?.eligibility?.reason;
      if (typeof reason === "string") {
        refusals.set(group.pr, { head: group.head, reason, eligibility: typeof eligibility === "string" ? eligibility : null });
      }
      group = null;
    } else {
      group.lines.push(line);
    }
  }
  return refusals;
}

// The gate refusals in the newest successful scheduled pr-merge run on main
// (a fork pull_request_target run skips its job and logs no gate), from its
// `merge` job's log; empty when there is no such run or job.
async function readGateRefusals({ actions, logs, repo }) {
  const runs = (await actions("GET", `/repos/${repo}/actions/workflows/pr-merge.yml/runs?branch=main&event=schedule&status=success&per_page=1`))
    ?.workflow_runs;
  if (!Array.isArray(runs)) {
    throw new Error("the pr-merge run listing has an unexpected shape");
  }
  if (runs.length === 0 || !RUN_ID.test(String(runs[0].id))) {
    return new Map();
  }
  const jobs = (await actions("GET", `/repos/${repo}/actions/runs/${runs[0].id}/jobs?filter=latest&per_page=100`))?.jobs;
  if (!Array.isArray(jobs)) {
    throw new Error("the pr-merge job listing has an unexpected shape");
  }
  const job = jobs.find((item) => item.name === "merge" && item.conclusion === "success" && RUN_ID.test(String(item.id)));
  return job ? gateRefusals(await logs(repo, job.id)) : new Map();
}

// Reads a job's log as text with `token` (actions: read).
const jobLogs = ({ token, apiUrl = "https://api.github.com" }) =>
  async function logs(repo, jobId) {
    const response = await fetch(`${apiUrl}/repos/${repo}/actions/jobs/${jobId}/logs`, {
      headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28" },
    });
    if (!response.ok) {
      throw new Error(`GET the log of job ${jobId} answered ${response.status}`);
    }
    return response.text();
  };

// Why an agent-ready issue is not restarted now (after a limit stop) or
// re-fired (after a failed run), or null with the time it has waited since.
// Every fact is read fresh from the API.
async function restartRefusal({ github, actions, repo, issue, bot, humans, now, workflowKey, gate }) {
  const base = `/repos/${repo}/issues/${issue.number}`;
  const labels = (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label.name));
  const held = labels.map((label) => String(label).toLowerCase()).find((label) => HOLDS.has(label));
  if (held) {
    return { reason: `held by ${held}` };
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
      gate,
    });
  }
  if (marker?.outcome !== "limited") {
    return { reason: "no limit stop is its newest lane outcome" };
  }
  // A limit that keeps stopping the lane goes to a person: count the limit
  // stops since a person last added agent-ready.
  const since = events
    .filter((event) => isLabel(event, "labeled") && event.actor?.login !== bot)
    .reduce((latest, event) => Math.max(latest, Date.parse(event.created_at)), Number.NEGATIVE_INFINITY);
  const stops = markers.filter((item) => item.outcome === "limited" && item.at > since).length;
  if (stops >= MAX_LIMIT_STOPS) {
    const explained = comments.some(
      (comment) =>
        comment.user?.login === bot && String(comment.body ?? "").startsWith(ESCALATED) && Date.parse(comment.created_at) > since,
    );
    return { reason: `${stops} limit stops since a person last added ${LABEL}`, escalate: stops, explained };
  }
  const resets = clampReset(marker.resets, marker.at);
  if (now < resets) {
    return { reason: `waiting for the limit to reset at ${new Date(resets).toISOString()}` };
  }
  return { reason: null, resets };
}

// Restarts, re-fires or hands off up to `cap` issues, longest-waiting first.
// Returns how many reads or writes failed.
async function restartLimited({ github, actions, logs, repo, bot, humans, now, cap = RESTARTS_PER_RUN }) {
  let failed = 0;
  const ready = [];
  // pr-merge's gate refusals, read once per run and only when needed.
  let refusals;
  // A failed read counts once and leaves the rest of the run with no refusals.
  const gate =
    actions && logs
      ? () =>
          (refusals ??= readGateRefusals({ actions, logs, repo }).catch((error) => {
            failed += 1;
            reportError("gate", error);
            return new Map();
          }))
      : null;
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
      const verdict = await restartRefusal({
        github,
        actions,
        repo,
        issue,
        bot,
        humans,
        now,
        workflowKey,
        gate,
      });
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
  for (const { number } of ready.slice(cap)) {
    console.log(`label-unblocked: #${number} restart deferred: ${cap} restarts this run`);
  }
  for (const { number, refire, recorded, comment, note, handOff, pr, explained } of ready.slice(0, cap)) {
    const base = `/repos/${repo}/issues/${number}`;
    if (handOff) {
      // The comment first, then the labels; agent-ready comes off last, so a
      // failed write leaves the issue for the next sweep, which finds the
      // comment and moves only the labels.
      try {
        if (!explained) {
          await github("POST", `${base}/comments`, { body: handOff === "triage" ? refsMergedComment(pr) : refsRefusedComment(pr) });
        }
        await github("POST", `${base}/labels`, { labels: [handOff === "triage" ? TRIAGE_LABEL : HUMAN_LABEL] });
        if (handOff === "triage") {
          await github("DELETE", `${base}/labels/${LABEL}`);
        }
        console.log(
          `label-unblocked: #${number} ${handOff === "triage" ? `handed to triage: lane PR #${pr} merged with Refs:` : `handed to a person: pr-merge refuses lane PR #${pr} as ${LINKED_NONE}`}`,
        );
      } catch (error) {
        failed += 1;
        reportError(number, error);
      }
      continue;
    }
    try {
      // The record first: a failed comment re-fires nothing, so the bound holds.
      if (refire && !recorded) {
        await github("POST", `${base}/comments`, { body: comment });
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
      console.log(`label-unblocked: #${number} ${refire ? note : "restarted after its limit stop"}`);
    } catch (error) {
      failed += 1;
      reportError(number, new Error(`${LABEL} was removed for a restart but not added back: ${error?.message ?? error}`));
    }
  }
  return failed;
}

export async function main({ env = process.env, github, actions, logs, now = Date.now() } = {}) {
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
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
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
      logs ??= env.ACTIONS_TOKEN ? jobLogs({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined }) : null;
      failed += await restartLimited({ github, actions, logs, repo, bot, humans, now });
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
