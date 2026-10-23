// Expected values come from report-escalation.sh's comment format and the
// review lanes' hold marker (docs/conventions/pr-pipeline/README.md, "Review-lane
// holds"), and from GitHub's GraphQL LabeledEvent and UnlabeledEvent shapes.
import assert from "node:assert/strict";
import { test } from "node:test";

import { gateSource, listLabelEvents } from "./gate-source.mjs";

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

test("an escalation more than a minute after the label is unknown", () => {
  assert.equal(source([label("labeled", APP, "2026-10-18T10:00:00Z"), escalation("2026-10-18T10:05:00Z")]), "unknown");
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
