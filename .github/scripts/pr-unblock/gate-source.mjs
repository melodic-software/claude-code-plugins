import process from "node:process";

import { FOOTER as LANE_FOOTER } from "../lib/lane-binding.mjs";
import { readRawTrustedActors, trustedListPath } from "../lib/trusted-actors.mjs";
import { escalationActivity } from "./escalation-routes.mjs";

export const ESCALATION = "<!-- work-items:escalation lane=pr-unblock kind=escalated -->";
export const RESUME_KEY = /^<!-- pr-unblock resume-key=([0-9a-f]{40}|[0-9a-f]{64}) -->$/;
const ANY_ESCALATION = "<!-- work-items:escalation";
export const ROUND_MARKER = "<!-- pr-unblock:address-feedback-round -->";
export const MODEL_RUN = /^<!-- pr-unblock:address-feedback-model-run \S+ -->$/;
export const HOLD_REASON = /^<!-- stop-reason lane=pr-unblock reason=(?:intent|design|security|cost) -->$/;
export const CLEARED = /^<!-- pr-pipeline needs-human-cleared reason=[a-z,-]+ head=[0-9a-f]{40} -->$/;
export const LANE_STOPPED = /^<!-- pr-unblock:lane-stopped activity=[a-z]+(?:-[a-z]+)* -->$/;
const REVIEW_HOLD = "<!-- claude-lane-hold lane=";
export const HOLD_LINE = /^<!-- claude-lane-hold lane=[a-z-]+ sha=([0-9a-f]{40}) criteria=[a-z-]+(?:,[a-z-]+)* -->$/;
export const SIGNED_COMMITS_HOLD = "<!-- check-signed-commits hold -->";
export const CREDENTIAL_HOLD = "<!-- stop-reason lane=pr-verify reason=security -->";
export const PAIRED_MS = 60_000;

export const lines = (body) => String(body ?? "").split("\n").map((line) => line.replace(/\r$/, ""));
export const same = (a, b) => String(a ?? "").toLowerCase() === String(b).toLowerCase();
export const isApp = (user, bot) => user?.login === bot && user?.type === "Bot";
const writtenAt = (item) => Math.max(Date.parse(item.created_at), Date.parse(item.updated_at ?? item.created_at));
const writtenSince = (item, since) => !(writtenAt(item) < since);
const result = (source, reason) => ({ source, reason });
const isEscalation = (body) => body[0] === ESCALATION && RESUME_KEY.test(body[1] ?? "");
const lanesAppComments = (timeline, isLanesApp) => timeline.filter((item) => item.event === "commented" && isLanesApp(item.user));

export function laneHold(item) {
  const body = lines(item.body).map((line) => line.trim());
  const marker = body.find((line) => line.startsWith(REVIEW_HOLD));
  const lane =
    isApp(item.user, "claude[bot]") ||
    (isApp(item.user, "github-actions[bot]") && LANE_FOOTER.test(body.findLast((line) => line !== "") ?? ""));
  return item.event === "commented" && lane ? marker : undefined;
}

export const commentItems = (comments) => comments.map((comment) => ({ event: "commented", ...comment }));

const REVIEW_BOTS = ["claude[bot]", "github-actions[bot]"];

let trustedHumanIds;
export function trustedHumans() {
  if (trustedHumanIds === undefined) {
    try {
      const list = readRawTrustedActors(trustedListPath(process.env));
      trustedHumanIds = new Set(list.actors.filter((actor) => actor?.kind === "human" && Number.isSafeInteger(actor.id)).map((actor) => actor.id));
    } catch {
      trustedHumanIds = new Set();
    }
  }
  return trustedHumanIds;
}

const newest = (items) =>
  items.reduce((kept, item) => (kept === undefined || !(Date.parse(item.created_at) < Date.parse(kept.created_at)) ? item : kept), undefined);

export function labelHistory(timeline, label, trusted = trustedHumans()) {
  const events = timeline.filter((item) => same(item.label?.name, label));
  const labeled = newest(events.filter((item) => item.event === "labeled"));
  const since = Date.parse(labeled?.created_at ?? "");
  const lifted = Math.max(
    -Infinity,
    ...events
      .filter((item) => item.event === "unlabeled" && trusted.has(item.actor?.id) && !item.performed_via_github_app)
      .map((item) => Date.parse(item.created_at))
      .filter((time) => time <= since),
  );
  const reviewLabeled = newest(events.filter((item) => item.event === "labeled" && REVIEW_BOTS.some((bot) => isApp(item.actor, bot))));
  return { labeled, since, lifted, reviewLabeled };
}

export function openReviewHold(timeline, lifted, reviewLabeled) {
  const comment = timeline.find((item) => laneHold(item) !== undefined && writtenSince(item, lifted));
  return comment ?? (reviewLabeled !== undefined && writtenSince(reviewLabeled, lifted) ? reviewLabeled : undefined);
}

export const holdText = (item) => laneHold(item) ?? `${item.label?.name} added by ${item.actor?.login ?? "an unknown account"}`;

const openActionsHold = (timeline, lifted, marker) =>
  timeline.find(
    (item) =>
      item.event === "commented" &&
      isApp(item.user, "github-actions[bot]") &&
      lines(item.body)[0] === marker &&
      writtenSince(item, lifted),
  );

export const openSignedCommitsHold = (timeline, lifted) => openActionsHold(timeline, lifted, SIGNED_COMMITS_HOLD);

export const openCredentialHold = (timeline, lifted) => openActionsHold(timeline, lifted, CREDENTIAL_HOLD);

export function escalationsSince(appComments, since) {
  return appComments
    .map((item) => ({ body: lines(item.body), at: Date.parse(item.created_at) }))
    .filter(({ body, at }) => isEscalation(body) && at >= since);
}

export function foreignMarker(appComments, since, known) {
  return appComments
    .filter((item) => writtenSince(item, since))
    .flatMap((item) => lines(item.body).filter((line) => line.includes("<!--")))
    .find((line) => !known(line) && !CLEARED.test(line));
}

function openHold(timeline, head, lifted, reviewLabeled) {
  const holds = timeline.filter((item) => laneHold(item) !== undefined);
  const unparsable = holds.find((item) => !HOLD_LINE.test(laneHold(item)) && (writtenSince(item, lifted) || laneHold(item).includes(`sha=${head}`)));
  if (unparsable !== undefined) {
    return result("unknown", `a review-lane hold marker does not parse: ${laneHold(unparsable).slice(0, 120)}`);
  }
  if (holds.some((item) => HOLD_LINE.exec(laneHold(item))?.[1] === head)) {
    return result("review-hold", `a review lane holds head ${head}`);
  }
  const open = openReviewHold(timeline, lifted, reviewLabeled);
  if (open !== undefined) {
    return result("review-hold", `a review lane's hold is open: ${holdText(open).slice(0, 120)}`);
  }
  if (openSignedCommitsHold(timeline, lifted) !== undefined) {
    return result("signed-commits-hold", "check-signed-commits found a lane commit it could not verify");
  }
  if (openCredentialHold(timeline, lifted) !== undefined) {
    return result("credential-hold", "pr-verify withheld a fail that may hold a credential");
  }
  return undefined;
}

function labelGate({ timeline, label, head, isLanesApp, trusted }) {
  const { labeled, since, lifted, reviewLabeled } = labelHistory(timeline, label, trusted);
  const held = openHold(timeline, head, lifted, reviewLabeled);
  if (held !== undefined) {
    return { gate: held };
  }
  if (!isLanesApp(labeled?.actor) || Number.isNaN(since)) {
    return { gate: result("unknown", `${label} was last added by ${labeled?.actor?.login ?? "no one on the timeline"}, not the lanes App`) };
  }
  return { since };
}

export function gateSource(args) {
  const { gate, since } = labelGate(args);
  if (gate !== undefined) {
    return gate;
  }
  const { timeline, label, isLanesApp } = args;
  const appComments = lanesAppComments(timeline, isLanesApp);
  const escalations = escalationsSince(appComments, since);
  if (escalations.length === 0 || !(escalations[0].at - since <= PAIRED_MS)) {
    return result("unknown", `no lane escalation by the lanes App right after it added ${label}`);
  }
  const known = (line) =>
    line === ESCALATION || RESUME_KEY.test(line) || HOLD_REASON.test(line) || line === ROUND_MARKER || MODEL_RUN.test(line) || LANE_STOPPED.test(line);
  const malformed = appComments
    .filter((item) => writtenSince(item, since))
    .map((item) => lines(item.body))
    .find((body) => body.some((line) => line.startsWith(ANY_ESCALATION)) && !isEscalation(body));
  const foreign = malformed?.find((line) => line.includes("<!--")) ?? foreignMarker(appComments, since, known);
  if (foreign !== undefined) {
    return result("unknown", `a lanes App comment since ${label} went on carries a marker this does not read: ${foreign.slice(0, 120)}`);
  }
  return result("lane-escalation", `${escalations.length} lane escalation(s) by the lanes App since it added ${label}`);
}

export const SHARED_COPY_ACTIVITY = "sync-shared-copies";
export const SHARED_COPY_MARKER = "<!-- babysit-merge-shared-copy-escalation -->";
const SHARED_COPY_REFUSAL = /^Refusal: `shared-copy-sources-changed:/;

export function sharedCopyGate(args) {
  const { gate, since } = labelGate(args);
  if (gate !== undefined) {
    return gate;
  }
  const { timeline, label, head, isLanesApp } = args;
  const marked = lanesAppComments(timeline, isLanesApp).filter((item) => lines(item.body).some((line) => line.includes("<!--")));
  const before = newest(marked.filter((item) => writtenAt(item) <= since));
  const body = lines(before?.body).map((line) => line.trim());
  const paired =
    before !== undefined &&
    since - writtenAt(before) <= PAIRED_MS &&
    body[0] === SHARED_COPY_MARKER &&
    body.filter((line) => line.includes("<!--")).length === 1 &&
    body.some((line) => line.includes(`at head \`${head}\``)) &&
    body.some((line) => SHARED_COPY_REFUSAL.test(line));
  if (!paired) {
    return result("unknown", `no shared-copy refusal at ${head} by the lanes App right before it added ${label}`);
  }
  const foreign = foreignMarker(marked.filter((item) => item !== before), since, (line) => LANE_STOPPED.test(line));
  if (foreign !== undefined) {
    return result("unknown", `a lanes App comment since ${label} went on carries a marker this does not read: ${foreign.slice(0, 120)}`);
  }
  return result("shared-copy-refusal", `pr-merge refused head ${head} as shared-copy-sources-changed`);
}

const REASON_LINE = /^- (?:Lane code|Reason): `([a-z][a-z-]*)`$/;

export { escalationActivity, escalationRoute, ROUTES } from "./escalation-routes.mjs";

export const FAILING = new Set(["failure", "timed_out", "startup_failure"]);
const AGGREGATE_JOBS = new Set(["CI Status", "ci-status"]);
const SILENT = new Set(["skipped", "neutral"]);
const silent = (run) => run.status === "completed" && SILENT.has(run.conclusion);

export function latestRuns(checkRuns) {
  const latest = new Map();
  for (const run of checkRuns) {
    const kept = latest.get(run.name);
    if (!kept || (silent(kept) && !silent(run)) || (silent(kept) === silent(run) && run.id > kept.id)) {
      latest.set(run.name, run);
    }
  }
  return latest;
}

export function failingChecks(checkRuns) {
  return [...latestRuns(checkRuns).values()]
    .filter((run) => !AGGREGATE_JOBS.has(run.name) && run.status === "completed" && (FAILING.has(run.conclusion) || run.conclusion === "cancelled"))
    .sort((a, b) => a.id - b.id);
}

const lastWrite = (item) => Math.max(Date.parse(item.created_at), Date.parse(item.updated_at));

export function spoken(item) {
  if (item.event === "commented") {
    return [{ user: item.user ?? item.actor, at: lastWrite(item) }];
  }
  if (item.event === "reviewed") {
    return [{ user: item.user, at: Date.parse(item.submitted_at) }];
  }
  if (item.event === "line-commented" || item.event === "commit-commented") {
    return (item.comments ?? []).map((comment) => ({ user: comment.user, at: lastWrite(comment) }));
  }
  return [];
}

export const personSince = (entries, since) => entries.find(({ user, at }) => !(at < since) && user?.type !== "Bot");

export const reviewEntries = ({ comments, reviews }) => [
  ...comments.map((comment) => ({ user: comment.user, at: lastWrite(comment) })),
  ...reviews.map((review) => ({ user: review.user, at: Date.parse(review.submitted_at) })),
];

export const sinceParam = (since) => new Date(since).toISOString().replace(/\.\d{3}Z$/, "Z");

export function laneEscalationAllows({ timeline, reviewComments, reviews, label, head, isLanesApp, activity }) {
  const shared = activity === SHARED_COPY_ACTIVITY;
  const gate = shared ? sharedCopyGate({ timeline, label, head, isLanesApp }) : gateSource({ timeline, label, head, isLanesApp });
  if (gate.source !== (shared ? "shared-copy-refusal" : "lane-escalation")) {
    return { allowed: false, why: `${label} is not a lane escalation (${gate.source})` };
  }
  if (!Array.isArray(reviewComments) || !Array.isArray(reviews)) {
    return { allowed: false, why: "its review comments or reviews were not read" };
  }
  const { since } = labelHistory(timeline, label);
  const entries = [...timeline.flatMap(spoken), ...reviewEntries({ comments: reviewComments, reviews })];
  if (personSince(entries, since) !== undefined) {
    return { allowed: false, why: `a person commented or reviewed since ${label} went on` };
  }
  const reasons = escalationsSince(lanesAppComments(timeline, isLanesApp), since).map(({ body }) => body.map((line) => REASON_LINE.exec(line.trim())?.[1]).find(Boolean));
  if (reasons.some((reason) => reason === undefined || escalationActivity(reason) === null)) {
    return { allowed: false, why: `a lane escalation since ${label} went on names no reason report-escalation.sh lists` };
  }
  if (reasons.some((reason) => escalationActivity(reason) === activity)) {
    return { allowed: false, why: `${activity} escalated it` };
  }
  return { allowed: true, why: "" };
}

export async function prHold({ labels, holdLabels, gateLabel, head, activity, appId, readTimeline, readReviews }) {
  const hard = labels.find((name) => holdLabels.includes(name) && name !== gateLabel);
  if (hard !== undefined) {
    return { held: true, laneEscalated: false, why: `held by ${hard}` };
  }
  if (gateLabel === null || !labels.includes(gateLabel)) {
    return { held: false, laneEscalated: false, why: "" };
  }
  if (!Number.isSafeInteger(appId) || appId < 1) {
    return { held: true, laneEscalated: false, why: `held by ${gateLabel}` };
  }
  const isLanesApp = (user) => user?.id === appId && user?.type === "Bot";
  const timeline = await readTimeline();
  const allows = (reviewComments, reviews) => laneEscalationAllows({ timeline, reviewComments, reviews, label: gateLabel, head, isLanesApp, activity });
  let { allowed, why } = allows([], []);
  if (allowed) {
    let read;
    try {
      read = await readReviews(sinceParam(labelHistory(timeline, gateLabel).since - 1000));
    } catch {
      read = undefined;
    }
    ({ allowed, why } = allows(read?.comments, read?.reviews));
  }
  return allowed ? { held: false, laneEscalated: true, why: "" } : { held: true, laneEscalated: false, why: `held by ${gateLabel}: ${why}` };
}

export const reviewReader = (api, number) => async (since) => {
  const comments = await api.listReviewComments(number, since);
  const reviews = await api.listReviews(number);
  return { comments, reviews };
};

const LABEL_EVENTS_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      timelineItems(itemTypes: [LABELED_EVENT, UNLABELED_EVENT], first: 100, after: $after) {
        nodes {
          __typename
          ... on LabeledEvent { createdAt label { name } actor { __typename login ... on Bot { databaseId } ... on User { databaseId } } }
          ... on UnlabeledEvent { createdAt label { name } actor { __typename login ... on Bot { databaseId } ... on User { databaseId } } }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;
const LABEL_EVENT_PAGES = 20;

const restLogin = (actor) => (actor?.__typename === "Bot" && actor.login && !actor.login.endsWith("[bot]") ? `${actor.login}[bot]` : actor?.login);

export async function listLabelEvents({ graphql, repository, number }) {
  const [owner, name] = repository.split("/");
  const events = [];
  let after = null;
  for (let page = 0; page < LABEL_EVENT_PAGES; page += 1) {
    const items = (await graphql(LABEL_EVENTS_QUERY, { owner, name, number, after })).repository.pullRequest.timelineItems;
    events.push(
      ...items.nodes.map((node) => ({
        event: node.__typename === "LabeledEvent" ? "labeled" : "unlabeled",
        label: { name: node.label?.name },
        actor: { login: restLogin(node.actor), id: node.actor?.databaseId, type: node.actor?.__typename },
        created_at: node.createdAt,
      })),
    );
    if (!items.pageInfo.hasNextPage) {
      return events;
    }
    after = items.pageInfo.endCursor;
  }
  throw new Error(`#${number} has more than ${LABEL_EVENT_PAGES * 100} label events`);
}
