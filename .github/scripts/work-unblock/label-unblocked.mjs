#!/usr/bin/env node
// label-unblocked.mjs: when an issue closes, labels `agent-ready` each issue
// it blocked that is now ready for the resolve-issue lane (the label starts
// that lane once resolve-issue accepts App-added labels, a follow-up by
// Automation Lanes): open, every blocker closed as completed by a listed
// human or a merge (a pull request blocker: merged), no hold label,
// not already agent-ready, ratified by the owner's admission marker, and
// admitted by resolve-issue's own admission rule (no work class outside its
// classes). Every fact is read from the API now, never from the event
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
// stop), no hold label, ratified and admitted, gets agent-ready removed and
// added again by the App, which starts the lane. At most RESTARTS_PER_RUN
// issues per run, longest-waiting first.
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
//   BASE_PATH              the default branch checkout (default `.base`), whose
//                          pr-pipeline.yaml holds resolve-issue's admission
//   LANES_BOT_LOGIN        the lanes App bot login, the only author of a marker
//                          and actor of a restart this trusts (default
//                          melodic-automation-lanes[bot])
//   GITHUB_API_URL
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { admits } from "../../actions/resolve-config/predicate.mjs";
import { findRatification } from "../../actions/resolve-config/ratification.mjs";
import { clampReset, parseOutcomeMarker } from "../work-resolve-issue/report-outcome.mjs";

const LABEL = "agent-ready";
const HUMAN_LABEL = "needs-human";
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

// The lanes App's outcome markers on an issue, oldest first, each with when it
// was posted.
const appMarkers = (comments, bot) =>
  comments
    .filter((comment) => comment.user?.login === bot)
    .map((comment) => ({ ...parseOutcomeMarker(comment.body), at: Date.parse(comment.created_at) }))
    .filter((marker) => marker.outcome !== undefined && Number.isFinite(marker.at));

// A removal of agent-ready is a restart, not a stop, only when the App made
// it, the App's newest marker before it is `limited`, and the next agent-ready
// event after it is the App adding the label back. Any other removal stops the
// lane, a pushback after a restart included.
function isRestart(events, index, markers, bot) {
  const removal = events[index];
  const at = Date.parse(removal.created_at);
  if (removal.actor?.login !== bot || markers.filter((marker) => marker.at <= at).at(-1)?.outcome !== "limited") {
    return false;
  }
  const next = events.slice(index + 1).find((event) => isLabel(event, "labeled") || isLabel(event, "unlabeled"));
  return next !== undefined && isLabel(next, "labeled") && next.actor?.login === bot;
}

// Why `number` is not promoted, or null when it is ready.
async function refusal({ github, repo, number, ratifiers, admission, closes, bot = DEFAULT_BOT }) {
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
    if (!(await trustedClose({ github, repo, number: blocker, ratifiers, closes }))) {
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
  const ratifying = findRatification(comments, ratifiers);
  if (ratifying === undefined) {
    return "no admission marker from a listed human";
  }
  return admits(admission, labels, { ratified: true }) ? null : "a work class resolve-issue does not admit";
}

// resolve-issue's admission, from the validated config on the default branch.
// Imported here, not at the top: the resolver's dependencies are installed by
// the resolve-config step that runs before this one.
async function loadAdmission(env) {
  const { readAdmission } = await import("../../actions/resolve-config/resolve-config.mjs");
  return readAdmission({ basePath: env.BASE_PATH || ".base", activity: "resolve-issue" });
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
function trustedClose({ github, repo, number, ratifiers, closes }) {
  if (!closes.has(number)) {
    closes.set(number, (async () => isTrustedClose(github, repo, await github("GET", `/repos/${repo}/issues/${number}`), ratifiers))());
  }
  return closes.get(number);
}

async function isTrustedClose(github, repo, closedIssue, ratifiers) {
  const closer = closedIssue?.closed_by;
  if (ratifiers.has(closer?.id)) {
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
async function labelUnblocked({ github, repo, closed, sweep, ratifiers, admission, bot }) {
  const seen = new Set();
  const closes = new Map();
  let failed = 0;
  for (const source of closed) {
    let blocked;
    try {
      if (sweep && !(await trustedClose({ github, repo, number: source, ratifiers, closes }))) {
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
        const reason = await refusal({ github, repo, number, ratifiers, admission, closes, bot });
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

// Why a limit-stopped agent-ready issue is not restarted now, or null with the
// time its limit reset. Every fact is read fresh from the API.
async function restartRefusal({ github, repo, issue, ratifiers, admission, bot, now }) {
  const base = `/repos/${repo}/issues/${issue.number}`;
  const labels = (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label.name));
  const held = labels.map((label) => String(label).toLowerCase()).find((label) => HOLDS.has(label));
  if (held) {
    return { reason: `held by ${held}` };
  }
  const comments = await paginate(github, `${base}/comments`);
  const markers = appMarkers(comments, bot);
  const marker = markers.at(-1);
  if (marker?.outcome !== "limited") {
    return { reason: "no limit stop is its newest lane outcome" };
  }
  const events = await paginate(github, `${base}/events`);
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
  // A lane run starts on agent-ready being added, and its outcome marker ends
  // it, so a label added after the newest marker is a run since the stop:
  // still going, or one that left no marker (a PR opened, or the reporter
  // failed). Either way this pass leaves it.
  if (events.some((event) => isLabel(event, "labeled") && Date.parse(event.created_at) > marker.at)) {
    return { reason: `${LABEL} was added after the limit stop` };
  }
  if (findRatification(comments, ratifiers) === undefined) {
    return { reason: "no admission marker from a listed human" };
  }
  if (!admits(admission, labels, { ratified: true })) {
    return { reason: "a work class resolve-issue does not admit" };
  }
  return { reason: null, resets };
}

// Restarts up to `cap` limit-stopped issues, longest-waiting first. Returns
// how many reads or writes failed.
async function restartLimited({ github, repo, ratifiers, admission, bot, now, cap = RESTARTS_PER_RUN }) {
  let failed = 0;
  const ready = [];
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
      const { reason, resets, escalate, explained } = await restartRefusal({ github, repo, issue, ratifiers, admission, bot, now });
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
      ready.push({ number: Number(issue.number), resets });
    } catch (error) {
      failed += 1;
      reportError(issue.number, error);
    }
  }
  ready.sort((a, b) => a.resets - b.resets || a.number - b.number);
  for (const { number } of ready.slice(cap)) {
    console.log(`label-unblocked: #${number} restart deferred: ${cap} restarts this run`);
  }
  for (const { number } of ready.slice(0, cap)) {
    try {
      await github("DELETE", `/repos/${repo}/issues/${number}/labels/${LABEL}`);
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
      console.log(`label-unblocked: #${number} restarted after its limit stop`);
    } catch (error) {
      failed += 1;
      reportError(number, new Error(`${LABEL} was removed for a restart but not added back: ${error?.message ?? error}`));
    }
  }
  return failed;
}

export async function main({ env = process.env, github, admission, now = Date.now() } = {}) {
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
    const ratifiers = loadTrustedList(env.TRUSTED_ACTORS_PATH).humans;
    admission ??= await loadAdmission(env);
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const closed = sweep
      ? await closedSince(github, repo, new Date(now - LOOKBACK_HOURS * 3_600_000))
      : [Number(event.issue.number)];
    if (sweep) {
      console.log(`label-unblocked: ${closed.length} issue(s) closed in the last ${LOOKBACK_HOURS} hours`);
    }
    const bot = env.LANES_BOT_LOGIN || DEFAULT_BOT;
    let failed = await labelUnblocked({ github, repo, closed, sweep, ratifiers, admission, bot });
    if (sweep) {
      failed += await restartLimited({ github, repo, ratifiers, admission, bot, now });
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
