// Expected values come from report-escalation.sh (its label, then its comment)
// and the review lanes' hold marker (docs/conventions/pr-pipeline/README.md,
// "Review-lane holds"): the races between the select job's read and the write
// runner's push.
import assert from "node:assert/strict";
import { readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { createGitHubApi } from "./address-feedback.mjs";
import { main } from "./gate-recheck.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const APP = { login: "melodic-automation-lanes[bot]", id: 337595936, type: "Bot" };
const ACTIONS = { login: "github-actions[bot]", id: 41898282, type: "Bot" };
const PERSON = { login: "kyle-sexton", id: 153232337, type: "User" };
const HEAD = "a".repeat(40);

const labeled = (actor, at) => ({ event: "labeled", actor, label: { name: "needs-human" }, created_at: at });
const unlabeled = (actor, at) => ({ event: "unlabeled", actor, label: { name: "needs-human" }, created_at: at });
const escalation = {
  event: "commented",
  user: APP,
  created_at: "2026-10-22T10:00:05Z",
  updated_at: "2026-10-22T10:00:05Z",
  body: `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${"b".repeat(40)} -->\nStopped.\n\n- Reason: \`ci-fix-escalated\``,
};
const ESCALATED = [labeled(APP, "2026-10-22T10:00:00Z"), escalation];

const NOT_ADOPTED = { ownerIds: new Set(), idleHours: undefined };
const ADOPTED = { ownerIds: new Set([PERSON.id]), idleHours: 24 };

// A fake client answering the reads each select path makes from `timeline`:
// the REST issue timeline, or its comments and label events apart.
async function recheck(timeline, env = {}, { reviewComments = [], reviews = [], author = PERSON, adoption = NOT_ADOPTED } = {}) {
  const dir = tempDir("gate-recheck-");
  try {
    const out = join(dir, "out");
    const asked = [];
    const logs = [];
    const read = (name, value) => {
      asked.push(name);
      return value;
    };
    const api = {
      getPull: async (pr) => read(`pull ${pr}`, { user: author }),
      listTimeline: async (pr) => read(`timeline ${pr}`, timeline),
      listIssueComments: async (pr) => read(`comments ${pr}`, timeline.filter((item) => item.event === "commented").map(({ event, ...comment }) => comment)),
      listLabelEvents: async (pr) => read(`labels ${pr}`, timeline.filter((item) => item.event === "labeled" || item.event === "unlabeled")),
      listReviewComments: async (pr) => read(`review-comments ${pr}`, reviewComments),
      listReviews: async (pr) => read(`reviews ${pr}`, reviews),
    };
    const vars = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: out, PR_NUMBER: "7", HEAD_SHA: HEAD, APP_SENDER_ID: String(APP.id), LABEL: "needs-human", ACTIVITY: "fix-docs", ...env };
    await main(vars, { api, adoption, log: (line) => logs.push(line) });
    return { out: readFileSync(out, "utf8"), asked, logs };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("a lane escalation still on the timeline is read again as one", async () => {
  const { out, asked, logs } = await recheck(ESCALATED);
  assert.equal(out, "lane-escalation=true\n");
  assert.deepEqual(asked.sort(), ["review-comments 7", "reviews 7", "timeline 7"]);
  assert.equal(logs[0], "#7 needs-human for fix-docs: lane-escalation");
});

test("a review-lane hold posted on the head since the select job read it is not a lane escalation", async () => {
  const hold = {
    event: "commented",
    user: ACTIONS,
    created_at: "2026-10-22T10:20:00Z",
    updated_at: "2026-10-22T10:20:00Z",
    body: `<!-- claude-lane-hold lane=claude-review sha=${HEAD} criteria=cost -->\nHeld.\n\nclaude-lane: claude-review`,
  };
  const { out, logs } = await recheck([...ESCALATED, hold]);
  assert.equal(out, "lane-escalation=false\n");
  assert.match(logs[0], /^#7 needs-human for fix-docs: held by needs-human: needs-human is not a lane escalation \(review-hold\)/);
});

test("a person removing and adding the label back is not a lane escalation", async () => {
  const { out } = await recheck([...ESCALATED, unlabeled(PERSON, "2026-10-22T10:10:00Z"), labeled(PERSON, "2026-10-22T10:11:00Z")]);
  assert.equal(out, "lane-escalation=false\n");
});

test("the label to read and the lanes App come from the environment", async () => {
  assert.equal((await recheck(ESCALATED, { LABEL: "hold-for-human" })).out, "lane-escalation=false\n");
  assert.equal((await recheck(ESCALATED, { APP_SENDER_ID: "12345" })).out, "lane-escalation=false\n");
});

test("a malformed head, PR number or missing variable throws before any read", async () => {
  await assert.rejects(recheck(ESCALATED, { HEAD_SHA: "main" }), /HEAD_SHA/);
  await assert.rejects(recheck(ESCALATED, { PR_NUMBER: "x" }), /PR_NUMBER/);
  await assert.rejects(recheck(ESCALATED, { LABEL: "" }), /LABEL/);
  await assert.rejects(recheck(ESCALATED, { ACTIVITY: "" }), /ACTIVITY/);
  await assert.rejects(recheck(ESCALATED, { ACTIVITY: "Fix CI" }), /ACTIVITY/);
});

// laneEscalationAllows (gate-source.mjs), which every select but
// address-feedback's on a PR no owner opened runs through prHold.
const personComment = { event: "commented", user: PERSON, created_at: "2026-10-22T10:30:00Z", updated_at: "2026-10-22T10:30:00Z", body: "wait" };

test("a person commenting since the label went on keeps the hold", async () => {
  assert.equal((await recheck([...ESCALATED, personComment])).out, "lane-escalation=false\n");
});

test("a person replying in a review thread since the label went on keeps the hold", async () => {
  const reply = { user: PERSON, created_at: "2026-10-22T10:30:00Z", updated_at: "2026-10-22T10:30:00Z" };
  assert.equal((await recheck(ESCALATED, {}, { reviewComments: [reply] })).out, "lane-escalation=false\n");
});

test("the activity's own escalation keeps the hold for it, not for another activity", async () => {
  assert.equal((await recheck(ESCALATED, { ACTIVITY: "fix-ci" })).out, "lane-escalation=false\n");
  assert.equal((await recheck(ESCALATED, { ACTIVITY: "resolve-conflicts" })).out, "lane-escalation=true\n");
});

test("an escalation since the label naming a reason the routing table does not list keeps the hold", async () => {
  const unlisted = { ...escalation, created_at: "2026-10-22T10:20:00Z", updated_at: "2026-10-22T10:20:00Z", body: escalation.body.replace("ci-fix-escalated", "not-a-reason") };
  assert.equal((await recheck([...ESCALATED, unlisted])).out, "lane-escalation=false\n");
});

test("address-feedback on a PR no owner opened re-reads as its select does: gateSource over comments and label events", async () => {
  const { out, asked } = await recheck([...ESCALATED, personComment], { ACTIVITY: "address-feedback" }, { author: APP });
  assert.equal(out, "lane-escalation=true\n");
  assert.deepEqual(asked.sort(), ["comments 7", "labels 7", "pull 7"]);
});

test("address-feedback on an owner PR re-reads as prHold, on comments and label events", async () => {
  const { out, asked } = await recheck([...ESCALATED, personComment], { ACTIVITY: "address-feedback" }, { adoption: ADOPTED });
  assert.equal(out, "lane-escalation=false\n");
  assert.ok(asked.includes("comments 7") && asked.includes("labels 7") && !asked.includes("timeline 7"));
  assert.equal((await recheck(ESCALATED, { ACTIVITY: "address-feedback" }, { adoption: ADOPTED })).out, "lane-escalation=true\n");
});

// The real client from address-feedback.mjs, on a stubbed fetch: the requests
// each path makes, which the write job's contents: read and pull-requests:
// read token may make (the same reads lane-hold.mjs and address-feedback.mjs
// select make from jobs with those permissions).
async function realRequests(activity) {
  const dir = tempDir("gate-recheck-real-");
  const seen = [];
  const answer = (body) => new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
  const fetch = async (url, init = {}) => {
    seen.push(`${init.method ?? "GET"} ${String(url).replace(/[?&]per_page=100/, "")}`);
    if (String(url).endsWith("/graphql")) {
      return answer({ data: { repository: { pullRequest: { timelineItems: { nodes: [], pageInfo: { hasNextPage: false } } } } } });
    }
    return answer(String(url).includes("/pulls/7") && !/pulls\/7\//.test(String(url)) ? { user: APP } : []);
  };
  const api = createGitHubApi({ token: "t", repository: "o/r", apiUrl: "https://api.test", graphqlUrl: "https://api.test/graphql", fetch });
  try {
    const out = join(dir, "out");
    const vars = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: out, PR_NUMBER: "7", HEAD_SHA: HEAD, APP_SENDER_ID: String(APP.id), LABEL: "needs-human", ACTIVITY: activity };
    await main(vars, { api, adoption: NOT_ADOPTED, log: () => {} });
    return { out: readFileSync(out, "utf8"), seen };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("the real client makes the reads each select path makes", async () => {
  const docs = await realRequests("fix-docs");
  assert.deepEqual(docs.seen, ["GET https://api.test/repos/o/r/issues/7/timeline"]);
  assert.equal(docs.out, "lane-escalation=false\n");
  const feedback = await realRequests("address-feedback");
  assert.deepEqual(feedback.seen, ["GET https://api.test/repos/o/r/pulls/7", "GET https://api.test/repos/o/r/issues/7/comments", "POST https://api.test/graphql"]);
  assert.equal(feedback.out, "lane-escalation=false\n");
});
