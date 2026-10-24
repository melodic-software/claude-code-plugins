// gate-source.mjs: where a pull request's human-gated label came from, read
// from its timeline. clear-escalations.mjs (pr-merge) uses the pieces to decide
// whether the label may come off; feedback-dispatch.mjs and address-feedback.mjs
// (pr-unblock) use gateSource to decide whether address-feedback works the PR
// while the label stays on.
//
// Two writers put the label on:
// - a lane escalation: the lanes App's report-escalation.sh (pr-unblock,
//   fix-ci) adds the label, then posts a comment whose first line is
//   ESCALATION and whose second is the resume-key line;
// - a review-lane hold: a review lane's status job adds the label and posts a
//   `<!-- claude-lane-hold lane=<lane> sha=<head> criteria=<list> -->` comment,
//   as claude[bot], or as github-actions[bot] ending in the lane's footer.
//
// Timeline items take the REST timeline shape: `event` ("commented",
// "labeled", "unlabeled"), `user` or `actor` ({ login, id, type }), `body`,
// `label`, `created_at`, `updated_at`. Text written by anyone but those
// authors is never read.

export const ESCALATION = "<!-- work-items:escalation lane=pr-unblock kind=escalated -->";
export const RESUME_KEY = /^<!-- pr-unblock resume-key=([0-9a-f]{40}|[0-9a-f]{64}) -->$/;
// Any escalation marker, of any lane: one that is not a whole ESCALATION
// comment is unparsable here.
const ANY_ESCALATION = "<!-- work-items:escalation";
// address-feedback's round record (publish-feedback.mjs), posted by the lanes
// App after each round it works on an escalated PR.
export const ROUND_MARKER = "<!-- pr-unblock:address-feedback-round -->";
const MODEL_RUN = /^<!-- pr-unblock:address-feedback-model-run \S+ -->$/;
export const CLEARED = /^<!-- pr-pipeline needs-human-cleared reason=[a-z,-]+ head=[0-9a-f]{40} -->$/;
// A review lane's hold comment opens a line with this marker.
const REVIEW_HOLD = "<!-- claude-lane-hold lane=";
const HOLD_LINE = /^<!-- claude-lane-hold lane=[a-z-]+ sha=([0-9a-f]{40}) criteria=[a-z-]+(?:,[a-z-]+)* -->$/;
const LANE_FOOTER = /^`?claude-lane: (?:claude-review|claude-security-review)`?$/;
// report-escalation.sh writes the label, then the comment, retrying the
// comment for up to 15 seconds; a minute covers that (judgment).
export const PAIRED_MS = 60_000;

export const lines = (body) => String(body ?? "").split("\n").map((line) => line.replace(/\r$/, ""));
export const same = (a, b) => String(a ?? "").toLowerCase() === String(b).toLowerCase();
export const isApp = (user, bot) => user?.login === bot && user?.type === "Bot";
// Written or edited at or after `since`; an unparsable time counts as since.
const writtenSince = (item, since) =>
  !(Date.parse(item.created_at) < since) || !(Date.parse(item.updated_at ?? item.created_at) < since);

// The REVIEW_HOLD marker line of a review lane's hold comment, or undefined.
export function laneHold(item) {
  const body = lines(item.body).map((line) => line.trim());
  const marker = body.find((line) => line.startsWith(REVIEW_HOLD));
  const lane =
    isApp(item.user, "claude[bot]") ||
    (isApp(item.user, "github-actions[bot]") && LANE_FOOTER.test(body.findLast((line) => line !== "") ?? ""));
  return item.event === "commented" && lane ? marker : undefined;
}

// Issue comments (REST) as timeline items.
export const commentItems = (comments) => comments.map((comment) => ({ event: "commented", ...comment }));

// The newest `labeled` event for `label`, when it was, and when the label was
// last removed at or before it (-Infinity when never).
export function labelHistory(timeline, label) {
  const labeled = timeline.filter((item) => item.event === "labeled" && same(item.label?.name, label)).at(-1);
  const since = Date.parse(labeled?.created_at ?? "");
  const lifted = Math.max(
    -Infinity,
    ...timeline
      .filter((item) => item.event === "unlabeled" && same(item.label?.name, label))
      .map((item) => Date.parse(item.created_at))
      .filter((time) => time <= since),
  );
  return { labeled, since, lifted };
}

// A review lane's hold comment written or edited since the label was last
// removed (ever, when it never was): a person removing the label lifts it.
export function openReviewHold(timeline, lifted) {
  return timeline.find(
    (item) => laneHold(item) !== undefined && !(Math.max(Date.parse(item.created_at), Date.parse(item.updated_at ?? item.created_at)) < lifted),
  );
}

// The lanes App's escalation comments written at or after `since`.
export function escalationsSince(appComments, since) {
  return appComments
    .map((item) => ({ body: lines(item.body), at: Date.parse(item.created_at) }))
    .filter(({ body, at }) => body[0] === ESCALATION && RESUME_KEY.test(body[1] ?? "") && at >= since);
}

// The first marker line on a lanes App comment written or edited at or after
// `since` that `known` does not accept and is not clear-escalations' own.
export function foreignMarker(appComments, since, known) {
  return appComments
    .filter((item) => writtenSince(item, since))
    .flatMap((item) => lines(item.body).filter((line) => line.includes("<!--")))
    .find((line) => !known(line) && !CLEARED.test(line));
}

// Where the human-gated `label` on a PR at `head` came from:
// - "review-hold" when a review lane's hold names `head`, or one is open;
// - "lane-escalation" when the lanes App (`isLanesApp`) added the label last,
//   its pr-unblock escalation comment followed within PAIRED_MS, and every
//   marker on its comments since is that escalation's or an address-feedback
//   round's;
// - "unknown" for anything else, an unparsable hold or escalation marker
//   included. Only "lane-escalation" lets a caller work the PR.
export function gateSource({ timeline, label, head, isLanesApp }) {
  const result = (source, reason) => ({ source, reason });
  const holds = timeline.filter((item) => laneHold(item) !== undefined);
  const unparsable = holds.find((item) => !HOLD_LINE.test(laneHold(item)));
  if (unparsable !== undefined) {
    return result("unknown", `a review-lane hold marker does not parse: ${laneHold(unparsable).slice(0, 120)}`);
  }
  const atHead = holds.find((item) => HOLD_LINE.exec(laneHold(item))[1] === head);
  if (atHead !== undefined) {
    return result("review-hold", `a review lane holds head ${head}`);
  }
  const { labeled, since, lifted } = labelHistory(timeline, label);
  const open = openReviewHold(timeline, lifted);
  if (open !== undefined) {
    return result("review-hold", `a review lane's hold is open: ${laneHold(open).slice(0, 120)}`);
  }
  if (!isLanesApp(labeled?.actor) || Number.isNaN(since)) {
    return result("unknown", `${label} was last added by ${labeled?.actor?.login ?? "no one on the timeline"}, not the lanes App`);
  }
  const appComments = timeline.filter((item) => item.event === "commented" && isLanesApp(item.user));
  const escalations = escalationsSince(appComments, since);
  if (escalations.length === 0 || !(escalations[0].at - since <= PAIRED_MS)) {
    return result("unknown", `no lane escalation by the lanes App right after it added ${label}`);
  }
  // A whole escalation's two marker lines and address-feedback's own round
  // record are known; any other marker, another lane's escalation or an
  // escalation line out of place included, is not.
  const known = (line) => line === ESCALATION || RESUME_KEY.test(line) || line === ROUND_MARKER || MODEL_RUN.test(line);
  const malformed = appComments
    .filter((item) => writtenSince(item, since))
    .map((item) => lines(item.body))
    .find((body) => body.some((line) => line.startsWith(ANY_ESCALATION)) && !(body[0] === ESCALATION && RESUME_KEY.test(body[1] ?? "")));
  const foreign = malformed?.find((line) => line.includes("<!--")) ?? foreignMarker(appComments, since, known);
  if (foreign !== undefined) {
    return result("unknown", `a lanes App comment since ${label} went on carries a marker this does not read: ${foreign.slice(0, 120)}`);
  }
  return result("lane-escalation", `${escalations.length} lane escalation(s) by the lanes App since it added ${label}`);
}

// The Reason line report-escalation.sh writes into its escalation comment.
const REASON_LINE = /^- Reason: `([a-z][a-z-]*)`$/;

// The activity a reason resumes, as report-escalation.sh maps it.
export const escalationActivity = (reason) =>
  reason.startsWith("feedback-")
    ? "address-feedback"
    : reason.startsWith("dependency-")
      ? "review-dependency"
      : reason.startsWith("ci-fix-")
        ? "fix-ci"
        : "resolve-conflicts";

// Whether `activity` may work a PR while its human-gated `label` stays on: only
// when gateSource reads a lane escalation, no person has commented since the
// label went on, and no escalation since then is `activity`'s own, so one
// lane's escalation does not stop the others. `why` is a fixed phrase, safe to
// log.
export function laneEscalationAllows({ timeline, label, head, isLanesApp, activity }) {
  const gate = gateSource({ timeline, label, head, isLanesApp });
  if (gate.source !== "lane-escalation") {
    return { allowed: false, why: `${label} is not a lane escalation (${gate.source})` };
  }
  const { since } = labelHistory(timeline, label);
  // As clear-escalations.mjs keeps the label: a person who commented since it
  // went on may want the lanes to wait.
  if (timeline.some((item) => item.event === "commented" && item.user?.type !== "Bot" && writtenSince(item, since))) {
    return { allowed: false, why: `a person commented since ${label} went on` };
  }
  const appComments = timeline.filter((item) => item.event === "commented" && isLanesApp(item.user));
  const reasons = escalationsSince(appComments, since).map(({ body }) => body.map((line) => REASON_LINE.exec(line.trim())?.[1]).find(Boolean));
  if (reasons.some((reason) => reason === undefined)) {
    return { allowed: false, why: `a lane escalation since ${label} went on names no reason` };
  }
  if (reasons.some((reason) => escalationActivity(reason) === activity)) {
    return { allowed: false, why: `${activity} escalated it` };
  }
  return { allowed: true, why: "" };
}

// Whether a PR carrying `labels` is held for `activity`: any of `holdLabels`
// but the human-gated `gateLabel` holds it; `gateLabel` holds it unless
// laneEscalationAllows reads `readTimeline()` (called only then) as another
// lane's escalation. A null gateLabel (unreadable) or no lanes App id holds.
// laneEscalated is true when the label is on and this activity works past it.
export async function prHold({ labels, holdLabels, gateLabel, head, activity, appId, readTimeline }) {
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
  const { allowed, why } = laneEscalationAllows({ timeline: await readTimeline(), label: gateLabel, head, isLanesApp, activity });
  return allowed ? { held: false, laneEscalated: true, why: "" } : { held: true, laneEscalated: false, why: `held by ${gateLabel}: ${why}` };
}

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

// A PR's label events as REST timeline items, read with `graphql(query,
// variables)`, which a pull-requests: read token may do.
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
        actor: { login: node.actor?.login, id: node.actor?.databaseId, type: node.actor?.__typename },
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
