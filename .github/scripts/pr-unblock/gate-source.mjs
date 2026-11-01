// gate-source.mjs: where a pull request's human-gated label came from, read
// from its timeline. clear-escalations.mjs (pr-merge) uses the pieces to decide
// whether the label may come off; feedback-dispatch.mjs and address-feedback.mjs
// (pr-unblock) use gateSource to decide whether address-feedback works the PR
// while the label stays on, and prHold, which also reads the PR's review
// comments and reviews, whether resolve-conflicts, fix-ci and fix-docs do.
//
// Three writers put the label on:
// - a lane escalation: the lanes App's report-escalation.sh (pr-unblock,
//   fix-ci) adds the label, then posts a comment whose first line is
//   ESCALATION and whose second is the resume-key line;
// - a review-lane hold: a review lane's status job adds the label and posts a
//   `<!-- claude-lane-hold lane=<lane> sha=<head> criteria=<list> -->` comment,
//   as claude[bot], or as github-actions[bot] ending in the lane's footer;
// - a signed-commits hold: check-signed-commits adds the label and posts a
//   comment whose first line is SIGNED_COMMITS_HOLD, as github-actions[bot].
//   The label may already be on, so it adds no `labeled` event then.
//
// Timeline items take the REST timeline shape: `event` ("commented",
// "labeled", "unlabeled"), `user` or `actor` ({ login, id, type }), `body`,
// `label`, `created_at`, `updated_at`. Text written by anyone but those
// authors is never read.

import { readFileSync } from "node:fs";

import { escalationActivity } from "./escalation-routes.mjs";

export const ESCALATION = "<!-- work-items:escalation lane=pr-unblock kind=escalated -->";
export const RESUME_KEY = /^<!-- pr-unblock resume-key=([0-9a-f]{40}|[0-9a-f]{64}) -->$/;
// Any escalation marker, of any lane: one that is not a whole ESCALATION
// comment is unparsable here.
const ANY_ESCALATION = "<!-- work-items:escalation";
// address-feedback's round record (publish-feedback.mjs), posted by the lanes
// App after each round it works on an escalated PR.
export const ROUND_MARKER = "<!-- pr-unblock:address-feedback-round -->";
export const MODEL_RUN = /^<!-- pr-unblock:address-feedback-model-run \S+ -->$/;
export const CLEARED = /^<!-- pr-pipeline needs-human-cleared reason=[a-z,-]+ head=[0-9a-f]{40} -->$/;
// report-escalation.sh's comment for a fail-routed stop, one per activity,
// edited in place; it adds no label.
export const LANE_STOPPED = /^<!-- pr-unblock:lane-stopped activity=[a-z]+(?:-[a-z]+)* -->$/;
// A review lane's hold comment opens a line with this marker.
const REVIEW_HOLD = "<!-- claude-lane-hold lane=";
export const HOLD_LINE = /^<!-- claude-lane-hold lane=[a-z-]+ sha=([0-9a-f]{40}) criteria=[a-z-]+(?:,[a-z-]+)* -->$/;
const LANE_FOOTER = /^`?claude-lane: (?:claude-review|claude-security-review)`?$/;
// check-signed-commits' escalation comment opens with this line; its report
// job posts it with GITHUB_TOKEN, as github-actions[bot].
export const SIGNED_COMMITS_HOLD = "<!-- check-signed-commits hold -->";
// The first line of pr-verify's stop on a withheld fail (verify-notes.mjs
// holdForCredential, stop-reason.mjs reasonMarker).
export const CREDENTIAL_HOLD = "<!-- stop-reason lane=pr-verify reason=security -->";
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

// The review lanes' accounts: their `labeled` event of the human-gated label
// is a hold, as ci-status reads one (pr-require-checks.yml, "Fail a review-lane
// hold an untrusted account lifted").
const REVIEW_BOTS = ["claude[bot]", "github-actions[bot]"];

// The `human` ids of the base's trusted-actor list, read once. An unreadable
// list is empty, so no removal lifts a hold.
let trustedHumanIds;
export function trustedHumans() {
  if (trustedHumanIds === undefined) {
    try {
      const list = JSON.parse(readFileSync(new URL("../../standards/trusted-actors/trusted-actors.json", import.meta.url), "utf8"));
      trustedHumanIds = new Set(list.actors.filter((actor) => actor?.kind === "human" && Number.isSafeInteger(actor.id)).map((actor) => actor.id));
    } catch {
      trustedHumanIds = new Set();
    }
  }
  return trustedHumanIds;
}

// The item with the newest created_at, whatever the list order; a later item
// wins a tie, and one whose time does not parse wins over the one kept.
const newest = (items) =>
  items.reduce((kept, item) => (kept === undefined || !(Date.parse(item.created_at) < Date.parse(kept.created_at)) ? item : kept), undefined);

// For `label`: the newest `labeled` event and when it was; when a person on the
// trusted list (`trusted`, a set of ids) last removed it at or before then
// (-Infinity when never), directly and not through an App, as ci-status
// accepts a lift; and the newest `labeled` event by a review lane's account,
// which ci-status counts as a hold.
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

// When a timeline item was last written: created, or edited later.
const writtenAt = (item) => Math.max(Date.parse(item.created_at), Date.parse(item.updated_at ?? item.created_at));

// A review lane's hold written or edited since the label was last lifted
// (ever, when it never was): its hold comment, or else `reviewLabeled`
// (labelHistory's) when given. A trusted person removing the label lifts it.
export function openReviewHold(timeline, lifted, reviewLabeled) {
  const comment = timeline.find((item) => laneHold(item) !== undefined && !(writtenAt(item) < lifted));
  return comment ?? (reviewLabeled !== undefined && !(writtenAt(reviewLabeled) < lifted) ? reviewLabeled : undefined);
}

// What an openReviewHold result shows: the hold comment's marker, or who
// added the label.
export const holdText = (item) => laneHold(item) ?? `${item.label?.name} added by ${item.actor?.login ?? "an unknown account"}`;

// A github-actions[bot] comment written or edited since the label was last
// removed (ever, when it never was) whose first line is `marker`. The marker in
// anyone else's comment is never read; a trusted person removing the label
// lifts it.
const openActionsHold = (timeline, lifted, marker) =>
  timeline.find(
    (item) =>
      item.event === "commented" &&
      isApp(item.user, "github-actions[bot]") &&
      lines(item.body)[0] === marker &&
      !(Math.max(Date.parse(item.created_at), Date.parse(item.updated_at ?? item.created_at)) < lifted),
  );

// check-signed-commits' escalation comment, as openActionsHold reads it.
export const openSignedCommitsHold = (timeline, lifted) => openActionsHold(timeline, lifted, SIGNED_COMMITS_HOLD);

// pr-verify's stop on a withheld fail, as openActionsHold reads it: a clean
// head rotates nothing, so only a person's removal clears the label.
export const openCredentialHold = (timeline, lifted) => openActionsHold(timeline, lifted, CREDENTIAL_HOLD);

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

// The hold a review lane, check-signed-commits or pr-verify keeps on a PR at
// `head`, as gateSource's { source, reason }, or undefined when none is open.
// These post while the label is already on, so who added it last never
// decides them; gateSource and sharedCopyGate read them first.
function openHold(timeline, head, lifted, reviewLabeled) {
  const result = (source, reason) => ({ source, reason });
  const holds = timeline.filter((item) => laneHold(item) !== undefined);
  // A lifted hold on an older head holds nothing, whatever its marker says.
  const unparsable = holds.find((item) => !HOLD_LINE.test(laneHold(item)) && (!(writtenAt(item) < lifted) || laneHold(item).includes(`sha=${head}`)));
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

// Where the human-gated `label` on a PR at `head` came from:
// - "review-hold" when a review lane's hold names `head`, or one is open;
// - "signed-commits-hold" when check-signed-commits' hold is open;
// - "credential-hold" when pr-verify's credential hold is open;
// - "lane-escalation" when the lanes App (`isLanesApp`) added the label last,
//   its pr-unblock escalation comment followed within PAIRED_MS, and every
//   marker on its comments since is that escalation's or an address-feedback
//   round's;
// - "unknown" for anything else, an unparsable hold marker that is open or
//   names `head`, or an unparsable escalation marker, included. Only
//   "lane-escalation" lets a caller work the PR.
// `trusted` is labelHistory's: the ids whose removal of the label lifts a hold.
export function gateSource({ timeline, label, head, isLanesApp, trusted }) {
  const result = (source, reason) => ({ source, reason });
  const { labeled, since, lifted, reviewLabeled } = labelHistory(timeline, label, trusted);
  const held = openHold(timeline, head, lifted, reviewLabeled);
  if (held !== undefined) {
    return held;
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
  const known = (line) => line === ESCALATION || RESUME_KEY.test(line) || line === ROUND_MARKER || MODEL_RUN.test(line) || LANE_STOPPED.test(line);
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

// pr-merge's refusal of a head whose generated shared-library copies are stale
// (babysit_merge.py), which only the sync-shared-copies activity works past.
export const SHARED_COPY_ACTIVITY = "sync-shared-copies";
export const SHARED_COPY_MARKER = "<!-- babysit-merge-shared-copy-escalation -->";
const SHARED_COPY_REFUSAL = /^Refusal: `shared-copy-sources-changed:/;

// Where the human-gated `label` came from, read for sync-shared-copies alone:
// "shared-copy-refusal" when the lanes App added it last, the lanes App comment
// with a marker written last at or before then carries SHARED_COPY_MARKER as
// its only marker, came within PAIRED_MS of the label, names `head` (``at head
// `<sha>` ``) and refuses with the `shared-copy-sources-changed:` prefix, and
// no lanes App comment since carries a marker but report-escalation.sh's
// lane-stopped, and no review-lane, signed-commits or credential hold is open
// (openHold's source then); "unknown" for anything else.
export function sharedCopyGate({ timeline, label, head, isLanesApp, trusted }) {
  const result = (source, reason) => ({ source, reason });
  const { labeled, since, lifted, reviewLabeled } = labelHistory(timeline, label, trusted);
  const held = openHold(timeline, head, lifted, reviewLabeled);
  if (held !== undefined) {
    return held;
  }
  if (!isLanesApp(labeled?.actor) || Number.isNaN(since)) {
    return result("unknown", `${label} was last added by ${labeled?.actor?.login ?? "no one on the timeline"}, not the lanes App`);
  }
  const marked = timeline.filter((item) => item.event === "commented" && isLanesApp(item.user) && lines(item.body).some((line) => line.includes("<!--")));
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

// The Reason line report-escalation.sh writes into its escalation comment.
const REASON_LINE = /^- Reason: `([a-z][a-z-]*)`$/;

export { escalationActivity, escalationRoute, ROUTES } from "./escalation-routes.mjs";

export const FAILING = new Set(["failure", "timed_out", "startup_failure"]);
// The aggregate of the others: fixing them fixes it. It also fails on a hold
// label, so it never stands for the head's CI.
const AGGREGATE = "ci-status";
// A contract-only run skips every lane, and ci-status then carries the last
// full run's recorded verdict forward, so a skip says nothing about a check.
const SILENT = new Set(["skipped", "neutral"]);
const silent = (run) => run.status === "completed" && SILENT.has(run.conclusion);

// The latest run of each check name, a real result over a skip: name -> run.
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

// The latest run of each check name that is not a skip, when it failed or was
// cancelled; select keeps a cancelled one only past its time limit. The fix-ci
// dispatcher reads a cancelled head through it too, so the two agree, and
// clear-escalations reads a fix-ci stop's head through it.
export function failingChecks(checkRuns) {
  return [...latestRuns(checkRuns).values()]
    .filter((run) => run.name !== AGGREGATE && run.status === "completed" && (FAILING.has(run.conclusion) || run.conclusion === "cancelled"))
    .sort((a, b) => a.id - b.id);
}


// A comment's last write: its creation or its last edit, so an old comment
// edited to say "wait" counts at the edit. A time that does not parse, a
// missing updated_at included, is NaN, which personSince counts as since.
const lastWrite = (item) => Math.max(Date.parse(item.created_at), Date.parse(item.updated_at));

// When a timeline item was written, and by whom, for a comment or a review
// (clear-escalations.mjs reads people speaking the same way).
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

// The first of `entries` ({ user, at }) a person wrote at or after `since`
// (the label's own second included, as GitHub's `since` filter reads it): an
// account GitHub marks Bot is not a person; an unknown author, or a time that
// does not parse, counts as one. The one rule for "a person spoke since the
// label", whatever source the entries come from.
export const personSince = (entries, since) => entries.find(({ user, at }) => !(at < since) && user?.type !== "Bot");

// A PR's REST review comments (pulls/<n>/comments) and reviews
// (pulls/<n>/reviews) as personSince entries: a comment at its last write,
// where a missing created_at or updated_at does not parse and so counts as
// since; a review when submitted. The timeline shows no reply inside an
// existing review thread, so laneEscalationAllows and clear-escalations.mjs
// (pr-merge) both read these through this one mapping.
export const reviewEntries = ({ comments, reviews }) => [
  ...comments.map((comment) => ({ user: comment.user, at: Math.max(Date.parse(comment.created_at), Date.parse(comment.updated_at)) })),
  ...reviews.map((review) => ({ user: review.user, at: Date.parse(review.submitted_at) })),
];

// `since` (epoch ms) as GitHub's `since` query value, to the second. GitHub
// documents `since` as "updated after" without saying whether its own second
// is included, so callers pass a second earlier and personSince filters again.
export const sinceParam = (since) => new Date(since).toISOString().replace(/\.\d{3}Z$/, "Z");

// Whether `activity` may work a PR while its human-gated `label` stays on: only
// when gateSource reads a lane escalation, no person has commented, reviewed or
// replied in a review thread since the label went on, and no escalation since
// then is `activity`'s own, so one lane's escalation does not stop the others.
// `reviewComments` and `reviews` are the PR's REST pulls/<n>/comments and
// pulls/<n>/reviews; either not an array (unread) disallows. `why` is a fixed
// phrase, safe to log.
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
  // A person who commented or reviewed since the label went on may want the
  // lanes to wait. An unknown author counts as a person. GitHub's timeline
  // shows no event for a reply inside an existing review thread, so the review
  // comments and reviews are read too, through reviewEntries. Known limit: a
  // review body edited after the label is not seen (a REST review carries no
  // update time).
  const entries = [...timeline.flatMap(spoken), ...reviewEntries({ comments: reviewComments, reviews })];
  if (personSince(entries, since) !== undefined) {
    return { allowed: false, why: `a person commented or reviewed since ${label} went on` };
  }
  const appComments = timeline.filter((item) => item.event === "commented" && isLanesApp(item.user));
  const reasons = escalationsSince(appComments, since).map(({ body }) => body.map((line) => REASON_LINE.exec(line.trim())?.[1]).find(Boolean));
  if (reasons.some((reason) => reason === undefined || escalationActivity(reason) === null)) {
    return { allowed: false, why: `a lane escalation since ${label} went on names no reason report-escalation.sh lists` };
  }
  if (reasons.some((reason) => escalationActivity(reason) === activity)) {
    return { allowed: false, why: `${activity} escalated it` };
  }
  return { allowed: true, why: "" };
}

// Whether a PR carrying `labels` is held for `activity`: any of `holdLabels`
// but the human-gated `gateLabel` holds it; `gateLabel` holds it unless
// laneEscalationAllows reads `readTimeline()` (called only then) and
// `readReviews(since)` ({ comments, reviews }: reviewReader's, called only
// when the timeline alone does not hold it, with the label's time as
// sinceParam gives it) as another lane's escalation. A
// readReviews that throws, or whose comments or reviews is not an array,
// holds with a fixed why. A null gateLabel
// (unreadable) or no lanes App id holds. laneEscalated is true when the label
// is on and this activity works past it.
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
  // More entries can only hold it, so the timeline is judged alone first and
  // the review reads are spent only on a PR it does not hold.
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

// prHold's readReviews for PR `number`: its review comments written or edited
// since `since` and every review, through `api`'s listReviewComments and
// listReviews (REST pulls/<n>/comments and pulls/<n>/reviews, which a
// pull-requests: read token may list; reviews take no since filter).
export const reviewReader = (api, number) => async (since) => {
  const [comments, reviews] = await Promise.all([api.listReviewComments(number, since), api.listReviews(number)]);
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

// GraphQL names a Bot by its login without the `[bot]` suffix REST gives it.
const restLogin = (actor) => (actor?.__typename === "Bot" && actor.login && !actor.login.endsWith("[bot]") ? `${actor.login}[bot]` : actor?.login);

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
