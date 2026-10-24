// Expected values come from report-escalation.sh's comment format and the
// review lanes' hold marker (docs/conventions/pr-pipeline/README.md, "Review-lane
// holds"), and from GitHub's GraphQL LabeledEvent and UnlabeledEvent shapes.
import assert from "node:assert/strict";
import { test } from "node:test";

import { gateSource, laneEscalationAllows, listLabelEvents, prHold } from "./gate-source.mjs";

const APP = { login: "melodic-automation-lanes[bot]", id: 337595936, type: "Bot" };
const ACTIONS = { login: "github-actions[bot]", id: 41898282, type: "Bot" };
const OWNER = { login: "kyle-sexton", id: 153232337, type: "User" };
const HEAD = "a".repeat(40);
const OLD = "b".repeat(40);
const isLanesApp = (user) => user?.id === APP.id && user?.type === "Bot";

const commented = (user, body, at) => ({ event: "commented", user, body, created_at: at, updated_at: at });
const label = (event, actor, at) => ({ event, actor, label: { name: "needs-human" }, created_at: at });
const escalation = (at = "2026-10-18T10:00:05Z") =>
  commented(APP, `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${OLD} -->\nStopped.`, at);
const hold = (sha, at) =>
  commented(ACTIONS, `<!-- claude-lane-hold lane=claude-review sha=${sha} criteria=cost,trust-gate -->\nHeld.\n\nclaude-lane: claude-review`, at);
const source = (timeline) => gateSource({ timeline, label: "needs-human", head: HEAD, isLanesApp }).source;

test("a hold on an older head a person lifted by unlabeling leaves a later lane escalation workable", () => {
  const timeline = [
    hold(OLD, "2026-10-18T08:00:00Z"),
    label("unlabeled", OWNER, "2026-10-18T09:00:00Z"),
    label("labeled", APP, "2026-10-18T10:00:00Z"),
    escalation(),
  ];
  assert.equal(source(timeline), "lane-escalation");
});

test("a hold on the current head holds even after a person unlabeled it", () => {
  const timeline = [
    hold(HEAD, "2026-10-18T08:00:00Z"),
    label("unlabeled", OWNER, "2026-10-18T09:00:00Z"),
    label("labeled", APP, "2026-10-18T10:00:00Z"),
    escalation(),
  ];
  assert.equal(source(timeline), "review-hold");
});

test("a hold marker text a person wrote is not read", () => {
  const timeline = [commented(OWNER, `<!-- claude-lane-hold lane=claude-review sha=${HEAD} criteria=cost -->`, "2026-10-18T10:01:00Z"), label("labeled", APP, "2026-10-18T10:00:00Z"), escalation()];
  assert.equal(source(timeline), "lane-escalation");
});

test("another lane's marker on a lanes App comment since the label is unknown", () => {
  const timeline = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalation(), commented(APP, "<!-- babysit-merge-risk -->\nRisk.", "2026-10-18T10:02:00Z")];
  assert.equal(source(timeline), "unknown");
});

test("address-feedback's own round records since the escalation leave it workable", () => {
  const timeline = [
    label("labeled", APP, "2026-10-18T10:00:00Z"),
    escalation(),
    commented(APP, "<!-- pr-unblock:address-feedback-round -->\n<!-- pr-unblock:address-feedback-model-run 5000-1 -->\nRound 1.", "2026-10-18T10:30:00Z"),
    commented(APP, "<!-- pr-unblock:address-feedback-round -->\nRound 2.", "2026-10-18T11:30:00Z"),
  ];
  assert.equal(source(timeline), "lane-escalation");
});

test("an escalation more than a minute after the label is unknown", () => {
  assert.equal(source([label("labeled", APP, "2026-10-18T10:00:00Z"), escalation("2026-10-18T10:05:00Z")]), "unknown");
});

// An escalation comment as report-escalation.sh writes it, with its Reason line.
const escalated = (reason, at = "2026-10-18T10:00:05Z") =>
  commented(APP, `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${OLD} -->\nThe pr-unblock lane stopped.\n\n- Reason: \`${reason}\`\n- Resume key: \`${OLD}\``, at);
const allows = (timeline, activity) => laneEscalationAllows({ timeline, label: "needs-human", head: HEAD, isLanesApp, activity }).allowed;

// report-escalation.sh maps each reason to the activity that resumes it:
// feedback-* address-feedback, dependency-* review-dependency, ci-fix-* fix-ci,
// any other resolve-conflicts.
test("a lane escalation holds only the activity it belongs to", () => {
  const by = (reason) => [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated(reason)];
  for (const activity of ["fix-ci", "resolve-conflicts", "fix-docs"]) {
    assert.equal(allows(by("feedback-disputed"), activity), true, activity);
  }
  assert.equal(allows(by("ci-fix-escalated"), "fix-ci"), false);
  assert.equal(allows(by("ci-fix-escalated"), "resolve-conflicts"), true);
  assert.equal(allows(by("unresolved-conflict"), "resolve-conflicts"), false);
  assert.equal(allows(by("conflict-patch-invalid"), "resolve-conflicts"), false);
  assert.equal(allows(by("unresolved-conflict"), "fix-ci"), true);
});

test("an escalation of the activity's own, among others since the label, holds it", () => {
  const timeline = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed"), escalated("ci-fix-round-cap", "2026-10-18T12:00:00Z")];
  assert.equal(allows(timeline, "fix-ci"), false);
  assert.equal(allows(timeline, "resolve-conflicts"), true);
});

test("a person's comment since the label went on holds every activity; one before it does not", () => {
  const base = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  const after = [...base, commented(OWNER, "Please wait, I am looking at this.", "2026-10-18T11:00:00Z")];
  const before = [commented(OWNER, "Looks fine.", "2026-10-18T09:00:00Z"), ...base];
  const bot = [...base, commented(ACTIONS, "A review lane's note.", "2026-10-18T11:00:00Z")];
  assert.equal(allows(after, "fix-ci"), false);
  assert.equal(allows(after, "resolve-conflicts"), false);
  assert.equal(allows(before, "fix-ci"), true);
  assert.equal(allows(bot, "fix-ci"), true, "a bot's comment is no one asking to wait");
  // GitHub's REST timeline: a review carries submitted_at, an inline comment sits under line-commented.
  const review = [...base, { event: "reviewed", user: OWNER, submitted_at: "2026-10-18T11:00:00Z", state: "changes_requested" }];
  const inline = [...base, { event: "line-commented", comments: [{ user: OWNER, created_at: "2026-10-18T11:00:00Z" }] }];
  assert.equal(allows(review, "fix-ci"), false, "a person's review");
  assert.equal(allows(inline, "resolve-conflicts"), false, "a person's inline comment");
});

test("an escalation reason report-escalation.sh does not list holds every activity", () => {
  const timeline = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("some-new-reason")];
  assert.equal(allows(timeline, "fix-ci"), false);
  assert.equal(allows(timeline, "resolve-conflicts"), false);
});

test("a person's label, a review-lane hold or an escalation with no reason holds every activity", () => {
  const person = [label("labeled", OWNER, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  const review = [hold(HEAD, "2026-10-18T09:00:00Z"), label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  const noReason = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalation()];
  for (const timeline of [person, review, noReason]) {
    assert.equal(allows(timeline, "fix-ci"), false);
    assert.equal(allows(timeline, "resolve-conflicts"), false);
  }
});

test("prHold reads the timeline only for the human-gated label, and holds on any other hold label", async () => {
  let reads = 0;
  const readTimeline = async () => {
    reads += 1;
    return [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  };
  const hold_ = (labels, extra = {}) =>
    prHold({ labels, holdLabels: ["do-not-merge", "needs-human"], gateLabel: "needs-human", head: HEAD, activity: "fix-ci", appId: APP.id, readTimeline, ...extra });
  assert.deepEqual(await hold_([]), { held: false, laneEscalated: false, why: "" });
  assert.equal(reads, 0);
  assert.equal((await hold_(["do-not-merge", "needs-human"])).held, true);
  assert.equal(reads, 0, "a do-not-merge hold needs no timeline read");
  assert.deepEqual(await hold_(["needs-human"]), { held: false, laneEscalated: true, why: "" });
  assert.equal(reads, 1);
  assert.equal((await hold_(["needs-human"], { activity: "address-feedback" })).held, true, "its own escalation");
  assert.equal((await hold_(["needs-human"], { appId: undefined })).held, true, "with no lanes App id the label holds");
  assert.equal((await hold_(["needs-human"], { gateLabel: null })).held, true, "with no readable human-gated label it holds");
});

test("listLabelEvents maps GraphQL label events to timeline items across pages", async () => {
  const pages = [
    {
      nodes: [{ __typename: "LabeledEvent", createdAt: "2026-10-18T10:00:00Z", label: { name: "needs-human" }, actor: { __typename: "Bot", login: APP.login, databaseId: APP.id } }],
      pageInfo: { hasNextPage: true, endCursor: "c1" },
    },
    {
      nodes: [{ __typename: "UnlabeledEvent", createdAt: "2026-10-18T11:00:00Z", label: { name: "needs-human" }, actor: { __typename: "User", login: OWNER.login, databaseId: OWNER.id } }],
      pageInfo: { hasNextPage: false, endCursor: null },
    },
  ];
  const asked = [];
  const graphql = async (query, variables) => {
    asked.push(variables);
    return { repository: { pullRequest: { timelineItems: pages[asked.length - 1] } } };
  };
  const events = await listLabelEvents({ graphql, repository: "o/r", number: 7 });
  assert.deepEqual(events, [
    label("labeled", APP, "2026-10-18T10:00:00Z"),
    label("unlabeled", OWNER, "2026-10-18T11:00:00Z"),
  ]);
  assert.deepEqual(asked, [
    { owner: "o", name: "r", number: 7, after: null },
    { owner: "o", name: "r", number: 7, after: "c1" },
  ]);
});
