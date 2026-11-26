#!/usr/bin/env node
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { readRouting, ROUTED_BY, routingLabel } from "../../actions/check-born-triaged/check-born-triaged.mjs";
import { createGitHub, GitHubError } from "../lib/github-client.mjs";
import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { authorAdmitted, confirmedOnly } from "../intake-triage/admit.mjs";
import { isDecisionComment, selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";
import { carried, DECISION_LABELS, HOLD_STATES, INFO_LABELS, isStatusLabel, statusReader } from "../../actions/resolve-config/read-status.mjs";
import { statusWriter } from "../../actions/resolve-config/write-status.mjs";
import { ACTIONS_BOT_ID, AGENT_READY, NEEDS_DECISION, NEEDS_HUMAN } from "../lib/lane-vocabulary.mjs";
import { ownComment } from "../lib/upsert-comment.mjs";

export { NEEDS_DECISION, NEEDS_HUMAN };
export const NEEDS_INFO = "needs-reporter-info";
export const CONFIRMED = "status: confirmed";
export const NEEDS_TRIAGE = "needs-triage";
const DEFERRED = "admission-deferred";
const WORKFLOW = "intake-triage.yml";
const FIELD_ACTIONS = new Set(["field_added", "field_removed"]);
const INFO_HOLDS = new Set([NEEDS_HUMAN, NEEDS_DECISION, "needs-spec"]);
const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPOSITORY = /^[A-Za-z0-9-]+\/(?!\.\.?$)[A-Za-z0-9_.-]+$/;

export const HOLD_MARKER = "<!-- intake-reenter:needs-human-decision -->";
export const FORM_MARKER = "<!-- intake-reenter:decision-form -->";
const HOW_FIELD = "a listed human changes the issue's Work status field from needs-human to needs-triage, or clears it";
const HOW_FIELD_REPOST = "a listed human clears the issue's Work status field and then posts the decision again, since a field release re-enters no issue that also carries a status label";
const HOW_LABEL = `a listed human clears the issue's Work status field if it also reads needs-human, then removes the \`${NEEDS_HUMAN}\` label`;
const HOW_LABEL_CONFIRMED = `${HOW_LABEL} and then posts the decision again, since a label removal re-enters no issue at \`${CONFIRMED}\``;
const holdReply = (how) =>
  `${HOLD_MARKER}\n\`${NEEDS_HUMAN}\` holds this issue, so a recorded decision does not send it back to intake triage. The hold stays until ${how}. The issue then goes back to intake triage, which reads the decision.`;
const FORM_REPLY = `${FORM_MARKER}\nThis comment did not send the issue back to intake triage: only a comment by a listed human whose first line is exactly \`**Decision recorded.**\` does. Post the decision again with that first line.`;
const firstLine = (body) => (body ?? "").trimStart().split("\n", 1)[0].trimEnd();
const LOOSE_DECISION = /^[^\p{L}\p{N}]*decision recorded/iu;

const labelNames = (issue) => (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));
const openIssue = (issue) => !issue.pull_request && issue.state === "open";
const positiveId = (value) => (/^[1-9][0-9]*$/.test(value ?? "") ? Number(value) : null);
const notFound = (error) => error instanceof GitHubError && error.status === 404;

export async function answerLabels(issue, statusOf) {
  const own = labelNames(issue);
  return statusOf ? statusOf(Number(issue.number), own) : own;
}

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
  while (i > 0 && events[i].from === null && sender(events[i - 1])) {
    i -= 1;
  }
  return HOLD_STATES.includes(events[i].from) ? { from: events[i].from, to: now, event: events[i] } : null;
}

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

async function replyOnce({ client, repository, base, issue, marker, body, log, what }) {
  if (await ownComment({ github: client, repository, pull: issue.number, marker })) {
    log(`intake-reenter: ${what}; the reply is already on the issue, so nothing changed`);
    return 0;
  }
  await client("POST", `${base}/comments`, { body });
  log(`intake-reenter: ${what}; posted the reply, changed nothing else`);
  return 0;
}

const holdHow = (own) => {
  if (own.includes(NEEDS_HUMAN)) {
    return own.includes(CONFIRMED) ? HOW_LABEL_CONFIRMED : HOW_LABEL;
  }
  return own.some((name) => isStatusLabel(name)) ? HOW_FIELD_REPOST : HOW_FIELD;
};

const movesElsewhere = (labels) =>
  labels.some((name) => [AGENT_READY, NEEDS_TRIAGE, DEFERRED].includes(name) || (isStatusLabel(name) && name !== CONFIRMED && !DECISION_LABELS.includes(name)));

const replyHeld = ({ own, ...rest }) =>
  replyOnce({ ...rest, marker: HOLD_MARKER, body: holdReply(holdHow(own)), what: `${NEEDS_HUMAN} holds the issue, so a decision re-enters nothing` });

async function replyUnanswered({ client, repository, base, issue, comment, humans, ids, labels, own, log }) {
  const user = comment.user ?? {};
  if (openIssue(issue) && user.type === "User" && humans.has(user.id) && comment.performed_via_github_app == null) {
    const exact = isDecisionComment({ comment, lastEditedAt: null, lastEditorId: null }, humans);
    if (!exact && LOOSE_DECISION.test(firstLine(comment.body))) {
      return replyOnce({ client, repository, base, issue, log, marker: FORM_MARKER, body: FORM_REPLY, what: "a decision whose first line is not exactly **Decision recorded.** re-enters nothing" });
    }
    if (exact && labels.includes(NEEDS_HUMAN) && !movesElsewhere(labels)) {
      const { kept } = await selectTrustedIssueComments({ github: client, repository, issueNumber: issue.number, ids });
      const item = kept.find((one) => one.comment.id === comment.id);
      if (item && isDecisionComment(item, humans)) {
        return replyHeld({ client, repository, base, issue, own, log });
      }
    }
  }
  log("intake-reenter: not an answer to a parked issue; nothing changed");
  return 0;
}

const dispatch = (client, repository, issue) =>
  client("POST", `/repos/${repository}/actions/workflows/${WORKFLOW}/dispatches`, {
    ref: "main",
    inputs: { "issue-number": String(issue.number) },
  });

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

const ANSWERED = {
  decision: [DECISION_LABELS, "needs-owner-decision"],
  parked: [[CONFIRMED], "confirmed"],
  info: [INFO_LABELS, "needs-reporter-info"],
  statusless: [[], null],
};

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
      log(`intake-reenter: the issue carries '${routed}', ${ROUTED_BY}; nothing changed`);
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
        return await replyUnanswered({ client, repository, base, issue, comment, humans, ids, labels, own, log });
      }
      const held = kind === "info" && labels.find((name) => INFO_HOLDS.has(name) && !own.includes(name));
      if (held) {
        log(`intake-reenter: ${held} holds the issue, so a reply changes nothing`);
        return 0;
      }
      if (kind !== "info" && labels.includes(NEEDS_HUMAN)) {
        if (movesElsewhere(labels)) {
          log(`intake-reenter: ${NEEDS_HUMAN} holds the issue and it is not parked for a decision; nothing changed`);
          return 0;
        }
        return await replyHeld({ client, repository, base, issue, own, log });
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
    try {
      const moved = await set(number, NEEDS_TRIAGE, { keepHold: true, releases: prior });
      if (moved?.outcome === "held") {
        await restore({ set, client, base, number, state: null, label: took ? status : null, log, next: "" });
        log(`intake-reenter: a person's Work status ${moved.state} holds the issue, so the answer changes nothing; nothing dispatched`);
        return 0;
      }
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
