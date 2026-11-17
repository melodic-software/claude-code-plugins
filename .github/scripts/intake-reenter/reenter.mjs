#!/usr/bin/env node
// reenter.mjs: sends an answered issue back to intake triage. The issue's
// status is its label names as the Work status field decides them
// (read-status.mjs statusReader; a hold label still holds on top). On a new
// comment on an open issue (never a pull request):
//
// - `needs-owner-decision` and a decision comment (select-trusted-text's
//   isDecisionComment, the rule write-issue.mjs marks `decision: true` by);
// - `status: confirmed` as the only status, with no `agent-ready` (where
//   admission parks a refusal no person must answer, or a person confirmed
//   the issue before any admission), and a decision comment;
// - `needs-reporter-info` and a comment by the issue's author or a listed
//   human, not posted through an App;
// - no `status:`, `agent-ready`, `needs-human`, `needs-triage` or
//   `admission-deferred`, and a listed human's decision comment;
// - EVENT_NAME `issues` (no comment) with REMOVED_LABEL `needs-human` (the
//   default; any other removed label changes nothing): a listed human removed
//   it, and the issue carries no status label but `needs-owner-decision`, and no
//   `agent-ready`, `needs-human` or `needs-triage`. The newest `needs-human`
//   removal in the issue's history (read-status.mjs statusEvents, so a
//   person's change of the field away from needs-human counts) must be that
//   person's;
// - EVENT_NAME `issues` with EVENT_ACTION `field_added` or `field_removed`: a
//   listed human (SENDER_ID) changed the Work status field. Past this lane's
//   own needs-triage writes, the issue's newest Work status field events must
//   be that person's, from a hold state (read-status.mjs HOLD_STATES) to none
//   or needs-triage; the issue must carry no status label but `needs-triage`
//   and intake must admit its author. The claim is a marked comment keyed to
//   the event that left the hold, posted first, since the field may already
//   read needs-triage before the run: a re-run of that release finds it and
//   dispatches nothing. A release that left the field empty then sets it to
//   needs-triage, and intake is dispatched;
//
// A decision on an issue that carries `needs-human` changes nothing: only a
// listed human releases that hold (docs/contracts/loop-lane/README.md, the
// label table), and their release re-enters an issue at
// `needs-owner-decision` (owner decision on #10735). At `status: confirmed`
// it re-enters nothing, so the decision is posted again after it. Nor does
// anything on an issue whose own labels hold a routing label
// (check-born-triaged.mjs routingLabel): intake skips it;
//
// then, on a comment or a needs-human removal, it sets the Work status field
// to needs-triage and dispatches intake-triage.yml once, only for an issue
// whose author intake admits (a listed human or the lanes App). Anything
// else changes nothing. It never adds `agent-ready`. The answered status's
// label, when the issue still carries it, is taken off first: when GitHub
// answers 404 another run already took it, and nothing is dispatched. The
// field at needs-triage is the claim otherwise: the runs wait in line per
// issue, and a second one reads it and stops. When a later call fails, the
// run sets the field back to the answered status, puts back a label it took,
// and fails, so a re-run can claim again; with no status answered (a
// statusless decision, a lift from no status) the field stays at
// needs-triage, which the triage sweep dispatches. Every fact is read from
// the API; the event supplies only the issue and comment numbers and, on
// `issues`, the removed label or the field change's action and sender. A
// Work status read or write that fails fails the run.
//
// Environment:
//   GITHUB_TOKEN          the job's token: issues write, actions write
//   GITHUB_REPOSITORY     owner/repo
//   ISSUE_NUMBER, COMMENT_ID (not read when EVENT_NAME is `issues`)
//   EVENT_NAME            `issues` for a label removal or a field change,
//                         else a comment
//   EVENT_ACTION          on `issues`, `field_added` or `field_removed` for a
//                         field change; anything else is a label removal
//   SENDER_ID             on a field change, the account that made it
//   REMOVED_LABEL         on a label removal, the label removed (default
//                         `needs-human`)
//   BASE_PATH             the default branch checkout (default `.base`), whose
//                         models.issue-status the Work status is read and
//                         written by
//   TRUSTED_ACTORS_PATH   the default branch's trusted-actor list
//   LANES_APP_ID          the lanes App bot's user id, or empty
//   KILL_SWITCH           `proceed`, or the run stops before any API call
//   GITHUB_API_URL
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { readRouting, routingLabel } from "../../actions/check-born-triaged/check-born-triaged.mjs";
import { createGitHub, GitHubError, loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { authorAdmitted, confirmedOnly } from "../intake-triage/admit.mjs";
import { isDecisionComment, selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { carried, DECISION_LABELS, HOLD_STATES, INFO_LABELS, isStatusLabel, statusReader } from "../../actions/resolve-config/read-status.mjs";
import { statusWriter } from "../../actions/resolve-config/write-status.mjs";
import { ownComment } from "../lib/upsert-comment.mjs";

export const NEEDS_DECISION = "needs-owner-decision";
export const NEEDS_INFO = "needs-reporter-info";
// Where admission parks a refusal no person must answer (admit.mjs CONFIRMED),
// or a person confirmed the issue before any admission.
export const CONFIRMED = "status: confirmed";
export const NEEDS_HUMAN = "needs-human";
export const NEEDS_TRIAGE = "needs-triage";
const AGENT_READY = "agent-ready";
const DEFERRED = "admission-deferred";
const WORKFLOW = "intake-triage.yml";
// The issues actions a Work status field change starts this run with.
const FIELD_ACTIONS = new Set(["field_added", "field_removed"]);
// The holds other than needs-info, as the field-first names carry them.
const INFO_HOLDS = new Set([NEEDS_HUMAN, NEEDS_DECISION, "needs-spec"]);
const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPOSITORY = /^[A-Za-z0-9-]+\/(?!\.\.?$)[A-Za-z0-9_.-]+$/;

const labelNames = (issue) => (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));
const openIssue = (issue) => !issue.pull_request && issue.state === "open";
const positiveId = (value) => (/^[1-9][0-9]*$/.test(value ?? "") ? Number(value) : null);
const notFound = (error) => error instanceof GitHubError && error.status === 404;

// The issue's label names as its Work status field decides them:
// `statusOf(number, names)` (read-status.mjs statusReader). With no
// `statusOf`, its own.
export async function answerLabels(issue, statusOf) {
  const own = labelNames(issue);
  return statusOf ? statusOf(Number(issue.number), own) : own;
}

// Which answer the comment is, or null: `decision`, `parked` (a decision on a
// status: confirmed issue no admission took), `info`, or `statusless` (a
// decision on an issue with no status). `labels` are the issue's label
// names, by default its own (answerLabels).
export async function classify({ github, repository, issue, comment, humans, ids, lanesAppId, labels = labelNames(issue) }) {
  if (!openIssue(issue)) {
    return null;
  }
  const user = comment.user ?? {};
  if (user.type !== "User" || user.id === lanesAppId || comment.performed_via_github_app != null) {
    return null;
  }
  const kept = async () => {
    const { kept: list } = await selectTrustedIssueComments({ github, repository, issueNumber: issue.number, ids });
    return list.find((item) => item.comment.id === comment.id) ?? null;
  };
  // With no status on the issue, only a listed human's decision answers, and
  // only where nothing else holds or moves the issue.
  if (!labels.some((name) => isStatusLabel(name))) {
    if (!humans.has(user.id) || [NEEDS_HUMAN, NEEDS_TRIAGE, AGENT_READY, DEFERRED].some((name) => labels.includes(name))) {
      return null;
    }
    const item = await kept();
    return item && isDecisionComment(item, humans) ? "statusless" : null;
  }
  if (carried(labels, DECISION_LABELS) && humans.has(user.id)) {
    const item = await kept();
    if (item && isDecisionComment(item, humans)) {
      return "decision";
    }
  }
  // A listed human's decision re-enters a status: confirmed issue whether
  // admission parked it there or a person confirmed it before any admission.
  if (humans.has(user.id) && confirmedOnly(labels)) {
    const item = await kept();
    if (item && isDecisionComment(item, humans)) {
      return "parked";
    }
  }
  if (carried(labels, INFO_LABELS)) {
    if (user.id === issue.user?.id) {
      return "info";
    }
    if (humans.has(user.id) && (await kept())) {
      return "info";
    }
  }
  return null;
}

async function removeLabel(github, base, name) {
  try {
    await github("DELETE", `${base}/labels/${encodeURIComponent(name)}`);
    return true;
  } catch (error) {
    if (notFound(error)) {
      return false;
    }
    throw error;
  }
}

// A listed human lifted `needs-human` and left the issue parked nowhere or at
// `needs-owner-decision`: true when intake should take it again. `labels`
// are the issue's names as the field decides them; `events()` its
// statusEvents, whose newest `needs-human` removal names who lifted it.
async function liftReenters({ issue, humans, lanesAppId, labels, events }) {
  if (!openIssue(issue)) {
    return false;
  }
  const parked = labels.some((name) => isStatusLabel(name) && !DECISION_LABELS.includes(name));
  if (parked || [NEEDS_HUMAN, NEEDS_TRIAGE, AGENT_READY].some((name) => labels.includes(name))) {
    return false;
  }
  if (!authorAdmitted(issue, humans, lanesAppId)) {
    return false;
  }
  const actor = (await events()).filter((event) => event?.event === "unlabeled" && event.label?.name === NEEDS_HUMAN).at(-1)?.actor;
  return actor?.type === "User" && humans.has(actor.id);
}

// The job token's bot, whose needs-triage write is this lane's own.
const ACTIONS_BOT_ID = 41898282;

// A listed human released a hold the Work status field held, on an issue no
// status label holds or moves. Walking back from the newest Work status event,
// past this lane's own needs-triage writes (the job token's or the lanes
// App's), the sender's run of newest events (a listed human's, as a User)
// must start from a hold state and end at none or the floor, so a removal and
// then a needs-triage add release too, and a re-run that sees its own write
// still finds the release. Every value an event names must be an option the
// config maps, so a renamed option fails the run instead of hiding a release.
// Returns {from, to, event}, `to` the field's state now and `event` the one
// that left the hold, or null when intake should not take the issue.
async function fieldReleases({ github, repository, issue, humans, lanesAppId, senderId, config, fieldEvents }) {
  const states = new Set(Object.values(config.options));
  const unknown = HOLD_STATES.find((state) => !states.has(state));
  if (unknown !== undefined) {
    throw new Error(`models.issue-status maps no option to the hold \`${unknown}\``);
  }
  if (!openIssue(issue) || !humans.has(senderId) || !authorAdmitted(issue, humans, lanesAppId)) {
    return null;
  }
  const own = new Set(labelNames(issue).map((name) => String(name).toLowerCase()));
  const statusLabels = Object.entries(config.labels).flatMap(([state, names]) => (state === NEEDS_TRIAGE ? [] : names));
  if (statusLabels.some((name) => own.has(name.toLowerCase()))) {
    return null;
  }
  const field = String(config["field-id"]);
  const events = (await fieldEvents(github, repository, Number(issue.number))).filter((event) => event.field === field);
  for (const event of events) {
    for (const name of [event.from, event.to]) {
      if (name !== null && !states.has(name)) {
        throw new Error(`the Work status field names option \`${name}\`, which models.issue-status does not map`);
      }
    }
  }
  const now = events.at(-1)?.to ?? null;
  if (now !== null && now !== NEEDS_TRIAGE) {
    return null;
  }
  const ownWrite = (event) => event.to === NEEDS_TRIAGE && event.actorType === "Bot" && (event.actorId === ACTIONS_BOT_ID || event.actorId === lanesAppId);
  let i = events.length - 1;
  while (i >= 0 && ownWrite(events[i])) {
    i -= 1;
  }
  const sender = (event) => event.actorType === "User" && event.actorId === senderId;
  if (i < 0 || !sender(events[i])) {
    return null;
  }
  // A removal followed by an add names no earlier value on the add; read the
  // sender's removal before it. Stop there, so a hold the sender set earlier
  // never hides the release.
  while (i > 0 && events[i].from === null && sender(events[i - 1])) {
    i -= 1;
  }
  return HOLD_STATES.includes(events[i].from) ? { from: events[i].from, to: now, event: events[i] } : null;
}

// The record of one release: a job token comment opening with a marker keyed
// to the event that left the hold, so a re-run of that release finds it and a
// later release, a new event, does not. The body is fixed text: the triage
// run reads the job token's comments as trusted.
const releaseMarker = (event) => {
  if (!event.actorId || !event.at) {
    throw new Error("the release's Work status event names no actor or time");
  }
  return `<!-- intake-reenter:release ${event.actorId} ${event.at} -->`;
};

async function dropRecord(client, repository, id) {
  try {
    await client("DELETE", `/repos/${repository}/issues/comments/${id}`);
  } catch (error) {
    if (!notFound(error)) {
      throw error;
    }
  }
}

// The Work status field path: a listed human's release (fieldReleases) posts
// its record (releaseMarker), sets the field to needs-triage when the release
// left it empty, and dispatches intake once; it writes no label. Runs for one
// issue wait in line, so only a re-run can see the same release again, and it
// finds the record and dispatches nothing. A hold a person set since then
// keeps the field and takes the record back. A failed field write or
// dispatch takes the record back, leaves the field as written and fails the
// run, so a re-run, which walks past the field write, can claim again.
async function releaseField({ client, repository, base, issue, humans, lanesAppId, env, log }) {
  const senderId = positiveId(env.SENDER_ID);
  const { fieldEvents, issueStatusFromBase } = await import("../../actions/resolve-config/resolve-config.mjs");
  const config = issueStatusFromBase(env);
  if (!config) {
    throw new Error("models.issue-status is not set, so a Work status field change cannot be read");
  }
  const release = await fieldReleases({ github: client, repository, issue, humans, lanesAppId, senderId, config, fieldEvents });
  if (release === null) {
    log("intake-reenter: not a listed human's release of a Work status hold that sends an issue to intake; nothing changed");
    return 0;
  }
  const marker = releaseMarker(release.event);
  if (await ownComment({ github: client, repository, pull: issue.number, marker })) {
    log("intake-reenter: this release's record is already on the issue; nothing dispatched");
    return 0;
  }
  const record = await client("POST", `${base}/comments`, {
    body: `${marker}\nA listed human released the issue's Work status hold, so it goes back to intake triage.`,
  });
  try {
    if (release.to === null) {
      const moved = await (await statusWriter({ env, github: client, repository })).set(Number(issue.number), NEEDS_TRIAGE, { keepHold: true });
      if (moved?.outcome === "held") {
        await dropRecord(client, repository, record.id);
        log(`intake-reenter: a person's Work status ${moved.state} holds the issue, so the release changes nothing; nothing dispatched`);
        return 0;
      }
    }
    await dispatch(client, repository, issue);
  } catch (error) {
    await dropRecord(client, repository, record.id).catch(() => log("::error title=intake-reenter::could not take back this release's record; delete it by hand so a re-run can claim again"));
    throw error;
  }
  log(`intake-reenter: Work status ${release.from} released, posted its record${release.to === null ? `, set Work status to ${NEEDS_TRIAGE}` : ""}, dispatched ${WORKFLOW}`);
  return 0;
}

const dispatch = (client, repository, issue) =>
  client("POST", `/repos/${repository}/actions/workflows/${WORKFLOW}/dispatches`, {
    ref: "main",
    inputs: { "issue-number": String(issue.number) },
  });

// Puts back `label` when the run took it off, and sets the Work status back
// to `state`, when given, unless a person's hold landed since (keepHold).
async function restore({ set, client, base, number, state, label, log, next = "; re-run the job to send the issue back to triage" }) {
  const back = async (what, write) => {
    try {
      const result = await write();
      log(result?.outcome === "held" ? `intake-reenter: left ${what} unrestored, since a person's Work status ${result.state} holds the issue` : `intake-reenter: restored ${what}${next}`);
    } catch {
      log(`::error title=intake-reenter::could not restore ${what}; restore it by hand`);
    }
  };
  if (label) {
    await back(label, () => client("POST", `${base}/labels`, { labels: [label] }));
  }
  if (state) {
    await back(`Work status ${state}`, () => set(number, state, { keepHold: true, releases: state }));
  }
}

// Each answer's status: the label it takes off when the issue carries it, and
// the Work status state a failed run sets back. A statusless answer has neither.
const ANSWERED = {
  decision: [DECISION_LABELS, "needs-owner-decision"],
  parked: [[CONFIRMED], "confirmed"],
  info: [INFO_LABELS, "needs-reporter-info"],
  statusless: [[], null],
};

// `routing` overrides the binding's routing labels, read by default from
// BASE_PATH's work-items.yaml (check-born-triaged.mjs readRouting).
export async function main({ env = process.env, github, log = console.log, statusOf, routing } = {}) {
  try {
    if (env.KILL_SWITCH !== "proceed") {
      log("intake-reenter: the kill switch stops this run; nothing read or labeled");
      return 0;
    }
    const lift = env.EVENT_NAME === "issues";
    const field = lift && FIELD_ACTIONS.has(env.EVENT_ACTION);
    if (!NUMBER.test(env.ISSUE_NUMBER ?? "") || !(lift || /^[1-9][0-9]{0,15}$/.test(env.COMMENT_ID ?? "")) || !REPOSITORY.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("ISSUE_NUMBER, COMMENT_ID or GITHUB_REPOSITORY is malformed");
    }
    const lanesAppId = positiveId(env.LANES_APP_ID);
    const { ids, humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const repository = env.GITHUB_REPOSITORY;
    const base = `/repos/${repository}/issues/${env.ISSUE_NUMBER}`;
    const issue = await client("GET", base);
    const routed = routingLabel(labelNames(issue).filter(Boolean), routing ?? readRouting(join(env.BASE_PATH || ".base", "docs/conventions/work-items.yaml"), { who: "intake-reenter", log }));
    if (routed) {
      log(`intake-reenter: the issue carries '${routed}', a container or wayfind label, so the skill that filed it routes it; nothing changed`);
      return 0;
    }
    if (field) {
      return await releaseField({ client, repository, base, issue, humans, lanesAppId, env, log });
    }
    if (lift && (env.REMOVED_LABEL || NEEDS_HUMAN) !== NEEDS_HUMAN) {
      log(`intake-reenter: a removal of ${env.REMOVED_LABEL} sends no issue to intake; nothing changed`);
      return 0;
    }
    const number = Number(issue.number);
    const own = labelNames(issue);
    const reader = statusOf ?? statusReader({ env, github: client, repository, log });
    const labels = await answerLabels(issue, reader);
    let kind;
    if (lift) {
      if (!(await liftReenters({ issue, humans, lanesAppId, labels, events: () => reader.events(number) }))) {
        log(`intake-reenter: not a removal of ${NEEDS_HUMAN} that sends an issue to intake; nothing changed`);
        return 0;
      }
      kind = carried(labels, DECISION_LABELS) ? "decision" : "statusless";
    } else {
      const comment = await client("GET", `/repos/${repository}/issues/comments/${env.COMMENT_ID}`);
      if (comment.issue_url !== undefined && !String(comment.issue_url).endsWith(base)) {
        throw new Error("the comment is not on the issue");
      }
      kind = await classify({ github: client, repository, issue, comment, humans, ids, lanesAppId, labels });
      if (!kind) {
        log("intake-reenter: not an answer to a parked issue; nothing changed");
        return 0;
      }
      // A reply sets needs-triage, so it must not overwrite a hold only the
      // field holds beside the needs-info it answers; a hold label stays on.
      const held = kind === "info" && labels.find((name) => INFO_HOLDS.has(name) && !own.includes(name));
      if (held) {
        log(`intake-reenter: ${held} holds the issue, so a reply changes nothing`);
        return 0;
      }
      if (kind !== "info" && labels.includes(NEEDS_HUMAN)) {
        const next =
          kind === "decision"
            ? `a listed human's removal of ${NEEDS_HUMAN} sends it back to triage`
            : `a listed human removes ${NEEDS_HUMAN} and posts the decision again, since a removal re-enters no issue at ${CONFIRMED}`;
        log(`intake-reenter: ${NEEDS_HUMAN} holds the issue, so a decision changes nothing; ${next}`);
        return 0;
      }
    }
    const [names, prior] = ANSWERED[kind];
    const status = carried(own, names) ?? names[0] ?? null;
    const took = status !== null && own.includes(status);
    if (took && !(await removeLabel(client, base, status))) {
      log(`intake-reenter: ${status} is already gone; nothing dispatched`);
      return 0;
    }
    const removed = took ? `removed ${status}, ` : "";
    const { set } = await statusWriter({ env, github: client, repository });
    // Past the claim, a failed call sets the answered status back, so a re-run
    // of the job finds the issue parked and the answer is not lost.
    try {
      // A hold a person set since the read stands (write-status.mjs
      // keepHold), except the hold this answer releases.
      const moved = await set(number, NEEDS_TRIAGE, { keepHold: true, releases: prior });
      if (moved?.outcome === "held") {
        await restore({ set, client, base, number, state: null, label: took ? status : null, log, next: "" });
        log(`intake-reenter: a person's Work status ${moved.state} holds the issue, so the answer changes nothing; nothing dispatched`);
        return 0;
      }
      // Intake admits an issue only from a listed human or the lanes App; any
      // other issue waits in needs-triage for a person, so its author cannot
      // start a model run with each reply.
      if (!authorAdmitted(issue, humans, lanesAppId)) {
        log(`intake-reenter: ${removed}set Work status to ${NEEDS_TRIAGE}; the author is not one intake admits, so nothing dispatched`);
        return 0;
      }
      await dispatch(client, repository, issue);
    } catch (error) {
      if (prior) {
        await restore({ set, client, base, number, state: prior, label: took ? status : null, log });
      }
      throw error;
    }
    log(`intake-reenter: ${lift ? `${NEEDS_HUMAN} lifted, ` : ""}${removed}set Work status to ${NEEDS_TRIAGE}, dispatched ${WORKFLOW}`);
    return 0;
  } catch (error) {
    const detail = error?.name === "GitHubError" ? error.message : (error?.message ?? "error");
    log(`::error title=intake-reenter::${String(detail).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
