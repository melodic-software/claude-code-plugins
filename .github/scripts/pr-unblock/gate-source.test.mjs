// Expected values come from report-escalation.sh's comment format and the
// review lanes' hold marker (docs/conventions/pr-pipeline/README.md, "Review-lane
// holds"), and from GitHub's GraphQL LabeledEvent and UnlabeledEvent shapes.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { escalationActivity, escalationRoute, gateSource, laneEscalationAllows, listLabelEvents, prHold, reviewReader, ROUTES, CREDENTIAL_HOLD, SIGNED_COMMITS_HOLD } from "./gate-source.mjs";
import { stopSkip } from "./escalation-routes.mjs";

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

test("report-escalation.sh's lane-stopped comment, posted or edited since the label, leaves a lane escalation workable", () => {
  const timeline = [
    label("labeled", APP, "2026-10-18T10:00:00Z"),
    escalation(),
    { ...commented(APP, "<!-- pr-unblock:lane-stopped activity=fix-ci -->\nStopped.", "2026-10-18T09:00:00Z"), updated_at: "2026-10-18T10:30:00Z" },
  ];
  assert.equal(source(timeline), "lane-escalation");
  // Only that marker's exact shape is known.
  const odd = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalation(), commented(APP, "<!-- pr-unblock:lane-stopped activity=Fix_CI -->", "2026-10-18T10:30:00Z")];
  assert.equal(source(odd), "unknown");
});

// The write runner's escalation enum (pr-run-activity-write.yml, its first
// step) is the list of reasons a run may hand report-escalation.sh; the
// routing table must route each one, and route nothing else.
test("escalation-routes.json routes every reason the write runner accepts, each to one activity and one route", () => {
  const workflow = readFileSync(new URL("../../workflows/pr-run-activity-write.yml", import.meta.url), "utf8");
  const block = workflow.slice(workflow.indexOf("case $ESCALATION_REASON in"), workflow.indexOf("patch-empty | patch-invalid"));
  const accepted = [...block.matchAll(/(?<=^|[\s|])([a-z]+(?:-[a-z]+)+)(?=\s*(?:\||\)))/gm)].map((match) => match[1]);
  assert.ok(accepted.length > 30, `read ${accepted.length} reasons from the enum`);
  assert.deepEqual([...new Set(accepted)].sort(), Object.keys(ROUTES).sort());
  for (const [reason, entry] of Object.entries(ROUTES)) {
    assert.ok(["resolve-conflicts", "address-feedback", "review-dependency", "fix-ci", "sync-shared-copies"].includes(entry.activity), reason);
    assert.ok(["hold", "fail"].includes(entry.route), reason);
    // Only a fail route names a label, the session-builder queue's.
    assert.ok(!Object.hasOwn(entry, "label") || (entry.route === "fail" && entry.label === "needs-session"), reason);
    assert.equal(escalationActivity(reason), entry.activity);
    assert.equal(escalationRoute(reason), entry.route);
    assert.equal(stopSkip(reason), entry.route === "fail" ? "lane-stopped" : "awaiting-human", reason);
  }
  assert.equal(escalationActivity("bogus"), null);
  assert.equal(escalationRoute("constructor"), null);
  // Fail-safe: a reason the table does not list waits for a person.
  assert.equal(stopSkip("bogus"), "awaiting-human");
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

// ci-status (pr-require-checks.yml, "Fail a review-lane hold an untrusted
// account lifted") lifts a review-lane hold only on a removal by a `human` of
// trusted-actors.json, not through an App, and counts github-actions[bot]'s or
// claude[bot]'s `labeled` event as a hold. OWNER is that list's one human.
const STRANGER = { login: "drive-by", id: 99, type: "User" };
const CLAUDE = { login: "claude[bot]", id: 209825114, type: "Bot" };
const afterLift = (remover) => [hold(OLD, "2026-10-18T08:00:00Z"), label("unlabeled", remover, "2026-10-18T09:00:00Z"), label("labeled", APP, "2026-10-18T10:00:00Z"), escalation()];

test("only a trusted person's unlabel lifts a review-lane hold", () => {
  assert.equal(source(afterLift(OWNER)), "lane-escalation");
  assert.equal(source(afterLift(STRANGER)), "review-hold");
  assert.equal(source(afterLift(APP)), "review-hold");
  const viaApp = afterLift(OWNER).map((item) => (item.event === "unlabeled" ? { ...item, performed_via_github_app: { slug: "some-app" } } : item));
  assert.equal(source(viaApp), "review-hold");
  // `trusted` replaces the base's list.
  assert.equal(gateSource({ timeline: afterLift(STRANGER), label: "needs-human", head: HEAD, isLanesApp, trusted: new Set([STRANGER.id]) }).source, "lane-escalation");
  assert.equal(gateSource({ timeline: afterLift(OWNER), label: "needs-human", head: HEAD, isLanesApp, trusted: new Set() }).source, "review-hold");
});

test("a review lane's labeled event is a hold until a trusted person unlabels it", () => {
  for (const bot of [ACTIONS, CLAUDE]) {
    const held = [label("labeled", bot, "2026-10-18T08:00:00Z"), label("labeled", APP, "2026-10-18T10:00:00Z"), escalation()];
    const gate = gateSource({ timeline: held, label: "needs-human", head: HEAD, isLanesApp });
    assert.deepEqual(gate, { source: "review-hold", reason: `a review lane's hold is open: needs-human added by ${bot.login}` });
    const lifted = [held[0], label("unlabeled", OWNER, "2026-10-18T09:00:00Z"), ...held.slice(1)];
    assert.equal(source(lifted), "lane-escalation", bot.login);
    const stranger = [held[0], label("unlabeled", STRANGER, "2026-10-18T09:00:00Z"), ...held.slice(1)];
    assert.equal(source(stranger), "review-hold", bot.login);
  }
  // Another bot's labeled event is no hold.
  assert.equal(source([label("labeled", { login: "dependabot[bot]", id: 49699333, type: "Bot" }, "2026-10-18T08:00:00Z"), label("labeled", APP, "2026-10-18T10:00:00Z"), escalation()]), "lane-escalation");
});

const badHold = (sha, at) => commented(ACTIONS, `<!-- claude-lane-hold lane=claude-review sha=${sha} criteria=Cost_Gate -->\nHeld.\n\nclaude-lane: claude-review`, at);

test("a malformed hold a trusted person lifted on an older head leaves a later lane escalation workable", () => {
  const timeline = [badHold(OLD, "2026-10-18T08:00:00Z"), label("unlabeled", OWNER, "2026-10-18T09:00:00Z"), label("labeled", APP, "2026-10-18T10:00:00Z"), escalation()];
  assert.equal(source(timeline), "lane-escalation");
});

test("a malformed hold that is open, or names the current head, is unknown", () => {
  const open = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalation(), badHold(OLD, "2026-10-18T10:30:00Z")];
  assert.equal(source(open), "unknown");
  const atHead = [badHold(HEAD, "2026-10-18T08:00:00Z"), label("unlabeled", OWNER, "2026-10-18T09:00:00Z"), label("labeled", APP, "2026-10-18T10:00:00Z"), escalation()];
  assert.equal(source(atHead), "unknown");
  const unlifted = [badHold(OLD, "2026-10-18T08:00:00Z"), label("unlabeled", STRANGER, "2026-10-18T09:00:00Z"), label("labeled", APP, "2026-10-18T10:00:00Z"), escalation()];
  assert.equal(source(unlifted), "unknown");
});

test("the newest labeled event is read by its time, not its place in the list", () => {
  // A person's later label, listed first, is the one that went on last.
  const timeline = [label("labeled", OWNER, "2026-10-18T11:00:00Z"), label("labeled", APP, "2026-10-18T10:00:00Z"), escalation()];
  assert.deepEqual(gateSource({ timeline, label: "needs-human", head: HEAD, isLanesApp }), {
    source: "unknown",
    reason: "needs-human was last added by kyle-sexton, not the lanes App",
  });
  // The lanes App's later label, listed first, pairs with its escalation.
  const reordered = [label("labeled", APP, "2026-10-18T10:00:00Z"), label("labeled", OWNER, "2026-10-18T09:00:00Z"), escalation()];
  assert.equal(source(reordered), "lane-escalation");
});

// An escalation comment as report-escalation.sh writes it, with its Reason line.
const escalated = (reason, at = "2026-10-18T10:00:05Z") =>
  commented(APP, `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${OLD} -->\nThe pr-unblock lane stopped.\n\n- Reason: \`${reason}\`\n- Resume key: \`${OLD}\``, at);
const allows = (timeline, activity, { reviewComments = [], reviews = [] } = {}) =>
  laneEscalationAllows({ timeline, reviewComments, reviews, label: "needs-human", head: HEAD, isLanesApp, activity }).allowed;

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

test("a person's comment edited after the label, or written in its own second, holds every activity", () => {
  const base = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  const edited = [{ ...commented(OWNER, "Looks fine. Edit: wait.", "2026-10-18T09:00:00Z"), updated_at: "2026-10-18T11:00:00Z" }, ...base];
  const sameSecond = [...base, commented(OWNER, "Wait.", "2026-10-18T10:00:00Z")];
  const inlineEdited = [...base, { event: "line-commented", comments: [{ user: OWNER, created_at: "2026-10-18T09:00:00Z", updated_at: "2026-10-18T11:00:00Z" }] }];
  assert.equal(allows(edited, "fix-ci"), false, "an edit after the label");
  assert.equal(allows(sameSecond, "fix-ci"), false, "the label's own second");
  assert.equal(allows(inlineEdited, "fix-ci"), false, "an inline comment edited after the label");
});

test("a person's timeline comment with no updated_at counts as written since the label", () => {
  const base = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  const comment = [{ ...commented(OWNER, "Wait.", "2026-10-18T09:00:00Z"), updated_at: undefined }, ...base];
  const inline = [...base, { event: "line-commented", comments: [{ user: OWNER, created_at: "2026-10-18T09:00:00Z" }] }];
  assert.equal(allows(comment, "fix-ci"), false, "a comment");
  assert.equal(allows(inline, "fix-ci"), false, "an inline comment");
});

// GitHub's REST pulls/<n>/comments: a reply inside an existing review thread
// carries in_reply_to_id and has no event on the issue timeline (#10526, #10533).
const reply = (user, at, extra = {}) => ({ id: 2, in_reply_to_id: 1, user, body: "Wait.", created_at: at, updated_at: at, ...extra });

test("a person's inline reply in a review thread, seen only in the review comments, holds every activity", () => {
  const timeline = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  assert.equal(allows(timeline, "fix-ci"), true, "the timeline alone shows no one");
  const inline = { reviewComments: [reply(OWNER, "2026-10-18T11:00:00Z")] };
  assert.equal(allows(timeline, "fix-ci", inline), false);
  assert.equal(allows(timeline, "resolve-conflicts", inline), false);
  const edited = { reviewComments: [reply(OWNER, "2026-10-18T09:00:00Z", { updated_at: "2026-10-18T11:00:00Z" })] };
  assert.equal(allows(timeline, "fix-ci", edited), false, "a reply edited after the label");
  const unknown = { reviewComments: [reply(undefined, "2026-10-18T11:00:00Z")] };
  assert.equal(allows(timeline, "fix-ci", unknown), false, "an unknown author counts as a person");
  const before = { reviewComments: [reply(OWNER, "2026-10-18T09:00:00Z")] };
  assert.equal(allows(timeline, "fix-ci", before), true, "a reply before the label");
  const noUpdate = { reviewComments: [reply(OWNER, "2026-10-18T09:00:00Z", { updated_at: undefined })] };
  assert.equal(allows(timeline, "fix-ci", noUpdate), false, "a reply with no updated_at counts as written since the label, as clear-escalations reads it");
  const bot = { reviewComments: [reply(APP, "2026-10-18T11:00:00Z"), reply(ACTIONS, "2026-10-18T11:05:00Z")] };
  assert.equal(allows(timeline, "fix-ci", bot), true, "a bot's inline reply is no one asking to wait");
});

test("a person's review since the label, seen only in the reviews, holds; a bot's or an earlier one does not", () => {
  const timeline = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  const review = (user, at) => ({ id: 9, user, state: "COMMENTED", submitted_at: at });
  assert.equal(allows(timeline, "fix-ci", { reviews: [review(OWNER, "2026-10-18T11:00:00Z")] }), false);
  assert.equal(allows(timeline, "fix-ci", { reviews: [review(OWNER, "2026-10-18T09:00:00Z")] }), true);
  assert.equal(allows(timeline, "fix-ci", { reviews: [review(ACTIONS, "2026-10-18T11:00:00Z")] }), true);
});

test("review comments or reviews not read disallow", () => {
  const timeline = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  const read = (reviewComments, reviews) => laneEscalationAllows({ timeline, reviewComments, reviews, label: "needs-human", head: HEAD, isLanesApp, activity: "fix-ci" });
  assert.deepEqual(read(undefined, []), { allowed: false, why: "its review comments or reviews were not read" });
  assert.deepEqual(read([], null), { allowed: false, why: "its review comments or reviews were not read" });
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
  let reviewReads = 0;
  const readTimeline = async () => {
    reads += 1;
    return [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  };
  const readReviews = async () => {
    reviewReads += 1;
    return { comments: [], reviews: [] };
  };
  const hold_ = (labels, extra = {}) =>
    prHold({ labels, holdLabels: ["do-not-merge", "needs-human"], gateLabel: "needs-human", head: HEAD, activity: "fix-ci", appId: APP.id, readTimeline, readReviews, ...extra });
  assert.deepEqual(await hold_([]), { held: false, laneEscalated: false, why: "" });
  assert.equal(reads, 0);
  assert.equal((await hold_(["do-not-merge", "needs-human"])).held, true);
  assert.equal(reads, 0, "a do-not-merge hold needs no timeline read");
  assert.deepEqual(await hold_(["needs-human"]), { held: false, laneEscalated: true, why: "" });
  assert.deepEqual([reads, reviewReads], [1, 1]);
  assert.equal((await hold_(["needs-human"], { activity: "address-feedback" })).held, true, "its own escalation");
  assert.equal(reviewReads, 1, "a PR the timeline alone holds needs no review read");
  assert.equal((await hold_(["needs-human"], { appId: undefined })).held, true, "with no lanes App id the label holds");
  assert.equal((await hold_(["needs-human"], { gateLabel: null })).held, true, "with no readable human-gated label it holds");
});

// check-signed-commits' escalation comment, posted with its report job's
// GITHUB_TOKEN; its label write adds no `labeled` event when the label is on.
const noReviews = async () => ({ comments: [], reviews: [] });
const signedHold = (user, at) =>
  commented(user, `${SIGNED_COMMITS_HOLD}\nLane commit check: these commits are not GitHub-verified, so no lane continues on this pull request until a human reviews them.\n\n- \`${OLD}\``, at);

test("pr-verify's credential stop holds a PR that is otherwise another lane's escalation, until a person lifts it", async () => {
  const stop = (user, at) => commented(user, `${CREDENTIAL_HOLD}\nReason: \`security\``, at);
  const timeline = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed"), stop(ACTIONS, "2026-10-18T11:00:00Z")];
  assert.equal(source(timeline), "credential-hold");
  assert.equal(allows(timeline, "fix-ci"), false);
  const held = await prHold({ labels: ["needs-human"], holdLabels: [], gateLabel: "needs-human", head: HEAD, activity: "fix-ci", appId: APP.id, readTimeline: async () => timeline, readReviews: noReviews });
  assert.deepEqual(held, { held: true, laneEscalated: false, why: "held by needs-human: needs-human is not a lane escalation (credential-hold)" });
  assert.equal(source(timeline.slice(0, 2)), "lane-escalation", "without the comment");
});

test("check-signed-commits' marked comment holds a PR that is otherwise another lane's escalation", async () => {
  const timeline = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed"), signedHold(ACTIONS, "2026-10-18T11:00:00Z")];
  assert.equal(source(timeline), "signed-commits-hold");
  assert.equal(allows(timeline, "fix-ci"), false);
  const held = await prHold({ labels: ["needs-human"], holdLabels: [], gateLabel: "needs-human", head: HEAD, activity: "fix-ci", appId: APP.id, readTimeline: async () => timeline, readReviews: noReviews });
  assert.deepEqual(held, { held: true, laneEscalated: false, why: "held by needs-human: needs-human is not a lane escalation (signed-commits-hold)" });
  assert.equal(source(timeline.slice(0, 2)), "lane-escalation", "without the marked comment");
});

test("an unmarked bot comment, or the marker from another account, does not hold", async () => {
  const base = [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  for (const comment of [
    commented(ACTIONS, "Lane commit check: these commits are not GitHub-verified.", "2026-10-18T11:00:00Z"),
    signedHold({ login: "chatgpt-codex-connector[bot]", id: 1, type: "Bot" }, "2026-10-18T11:00:00Z"),
    signedHold({ ...ACTIONS, type: "User" }, "2026-10-18T11:00:00Z"),
  ]) {
    const timeline = [...base, comment];
    assert.equal(source(timeline), "lane-escalation", comment.body);
    const held = await prHold({ labels: ["needs-human"], holdLabels: [], gateLabel: "needs-human", head: HEAD, activity: "fix-ci", appId: APP.id, readTimeline: async () => timeline, readReviews: noReviews });
    assert.equal(held.held, comment.user.type !== "Bot", comment.user.login);
  }
});

test("check-signed-commits' hold a person lifted by unlabeling leaves a later lane escalation workable", () => {
  const timeline = [signedHold(ACTIONS, "2026-10-18T08:00:00Z"), label("unlabeled", OWNER, "2026-10-18T09:00:00Z"), label("labeled", APP, "2026-10-18T10:00:00Z"), escalation()];
  assert.equal(source(timeline), "lane-escalation");
  assert.equal(source([signedHold(ACTIONS, "2026-10-18T08:00:00Z"), label("labeled", APP, "2026-10-18T10:00:00Z"), escalation()]), "signed-commits-hold", "never lifted");
});

test("prHold holds on a person's inline reply its review reader returns", async () => {
  const readTimeline = async () => [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  const api = {
    listReviewComments: async (number) => (number === 7 ? [reply(OWNER, "2026-10-18T11:00:00Z")] : []),
    listReviews: async () => [],
  };
  const held = await prHold({ labels: ["needs-human"], holdLabels: [], gateLabel: "needs-human", head: HEAD, activity: "fix-ci", appId: APP.id, readTimeline, readReviews: reviewReader(api, 7) });
  assert.deepEqual(held, { held: true, laneEscalated: false, why: "held by needs-human: a person commented or reviewed since needs-human went on" });
});

test("prHold's review reader asks for the review comments since a second before the label, and every review", async () => {
  const readTimeline = async () => [label("labeled", APP, "2026-10-18T10:00:00.250Z"), escalated("feedback-disputed")];
  const asked = [];
  const api = {
    listReviewComments: async (...args) => (asked.push(["comments", ...args]), []),
    listReviews: async (...args) => (asked.push(["reviews", ...args]), []),
  };
  const result = await prHold({ labels: ["needs-human"], holdLabels: [], gateLabel: "needs-human", head: HEAD, activity: "fix-ci", appId: APP.id, readTimeline, readReviews: reviewReader(api, 7) });
  assert.equal(result.held, false);
  assert.deepEqual(asked, [
    ["comments", 7, "2026-10-18T09:59:59Z"],
    ["reviews", 7],
  ]);
});

test("prHold holds when the review comments or the reviews read fails, or reads no array", async () => {
  const readTimeline = async () => [label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("feedback-disputed")];
  const failed = async () => {
    throw Object.assign(new Error("GET pulls/7/comments returned 502"), { status: 502 });
  };
  const empty = async () => [];
  const hold_ = (api) =>
    prHold({ labels: ["needs-human"], holdLabels: [], gateLabel: "needs-human", head: HEAD, activity: "fix-ci", appId: APP.id, readTimeline, readReviews: reviewReader(api, 7) });
  const unread = { held: true, laneEscalated: false, why: "held by needs-human: its review comments or reviews were not read" };
  assert.deepEqual(await hold_({ listReviewComments: failed, listReviews: empty }), unread, "a failed comments read");
  assert.deepEqual(await hold_({ listReviewComments: empty, listReviews: failed }), unread, "a failed reviews read");
  assert.deepEqual(await hold_({ listReviewComments: async () => ({ message: "Not Found" }), listReviews: empty }), unread, "comments not an array");
  assert.deepEqual(await hold_({ listReviewComments: empty, listReviews: async () => null }), unread, "reviews not an array");
  const none = await prHold({ labels: ["needs-human"], holdLabels: [], gateLabel: "needs-human", head: HEAD, activity: "fix-ci", appId: APP.id, readTimeline });
  assert.deepEqual(none, unread, "no review reader");
});

test("listLabelEvents maps GraphQL label events to timeline items across pages", async () => {
  const pages = [
    {
      nodes: [{ __typename: "LabeledEvent", createdAt: "2026-10-18T10:00:00Z", label: { name: "needs-human" }, actor: { __typename: "Bot", login: APP.login, databaseId: APP.id } }],
      pageInfo: { hasNextPage: true, endCursor: "c1" },
    },
    {
      nodes: [
        { __typename: "UnlabeledEvent", createdAt: "2026-10-18T11:00:00Z", label: { name: "needs-human" }, actor: { __typename: "User", login: OWNER.login, databaseId: OWNER.id } },
        // GraphQL names a Bot without the `[bot]` REST gives it.
        { __typename: "LabeledEvent", createdAt: "2026-10-18T12:00:00Z", label: { name: "needs-human" }, actor: { __typename: "Bot", login: "github-actions", databaseId: ACTIONS.id } },
      ],
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
    label("labeled", ACTIONS, "2026-10-18T12:00:00Z"),
  ]);
  assert.deepEqual(asked, [
    { owner: "o", name: "r", number: 7, after: null },
    { owner: "o", name: "r", number: 7, after: "c1" },
  ]);
});

// pr-merge's shared-copy escalation as babysit_merge.py writes it: the comment,
// then the label.
const sharedCopy = (head = HEAD, reason = "shared-copy-sources-changed:lib/x.sh changed on main since merge base c", at = "2026-10-18T09:59:58Z") =>
  commented(
    APP,
    `<!-- babysit-merge-shared-copy-escalation -->\nUnattended merge: the shared-library canonical source \`lib/x.sh\` changed on \`main\` since merge base \`c\`, so the generated copies this pull request carries are stale at head \`${head}\`.\n\nRefusal: \`${reason}\`\n\nUpdating the branch from the base cannot regenerate them.`,
    at,
  );
const refused = (comment = sharedCopy()) => [comment, label("labeled", APP, "2026-10-18T10:00:00Z")];

test("pr-merge's shared-copy refusal lets sync-shared-copies past the label, and no other activity", () => {
  assert.equal(allows(refused(), "sync-shared-copies"), true);
  for (const activity of ["resolve-conflicts", "fix-ci", "fix-docs", "address-feedback"]) {
    assert.equal(allows(refused(), activity), false, activity);
  }
});

test("sync-shared-copies stays held unless the refusal names this head, this reason, and the lanes App paired it with the label", () => {
  assert.equal(allows(refused(sharedCopy(OLD)), "sync-shared-copies"), false);
  assert.equal(allows(refused(sharedCopy(HEAD, "check-inputs-changed:x changed on main")), "sync-shared-copies"), false);
  assert.equal(allows(refused(sharedCopy(HEAD, undefined, "2026-10-18T09:50:00Z")), "sync-shared-copies"), false);
  assert.equal(allows([sharedCopy(), label("labeled", OWNER, "2026-10-18T10:00:00Z")], "sync-shared-copies"), false);
  assert.equal(allows(refused({ ...sharedCopy(), user: OWNER }), "sync-shared-copies"), false);
  // A pr-unblock escalation alone is not pr-merge's refusal.
  assert.equal(allows([label("labeled", APP, "2026-10-18T10:00:00Z"), escalated("unresolved-conflict")], "sync-shared-copies"), false);
});

test("sync-shared-copies stays held once a person spoke or another lane marked the PR since the label", () => {
  assert.equal(allows([...refused(), commented(OWNER, "wait", "2026-10-18T11:00:00Z")], "sync-shared-copies"), false);
  assert.equal(allows(refused(), "sync-shared-copies", { reviews: [{ user: OWNER, submitted_at: "2026-10-18T11:00:00Z" }] }), false);
  assert.equal(allows([...refused(), escalated("unresolved-conflict", "2026-10-18T11:00:00Z")], "sync-shared-copies"), false);
});
