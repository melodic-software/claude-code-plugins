// Expected values come from report-escalation.sh (its label, then its comment
// with a Reason line) and its reason-to-activity map.
import assert from "node:assert/strict";
import { readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { main } from "./lane-hold.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const APP = { login: "melodic-automation-lanes[bot]", id: 337595936, type: "Bot" };
const PERSON = { login: "kyle-sexton", id: 153232337, type: "User" };
const HEAD = "a".repeat(40);

// createGitHubApi's error for a refused answer: a plain Error with the status.
const refused = (status) => Object.assign(new Error(`GET returned ${status}`), { status });

function fakeApi({ labels = ["needs-human"], actor = APP, reason = "feedback-disputed", reviewComments = [], reviews = [], pullError = null, timelineError = null } = {}) {
  return {
    getPull: async () => {
      if (pullError) {
        throw pullError;
      }
      return { head: { sha: HEAD }, labels: labels.map((name) => ({ name })) };
    },
    listReviewComments: async () => {
      if (reviewComments instanceof Error) {
        throw reviewComments;
      }
      return reviewComments;
    },
    listReviews: async () => reviews,
    listTimeline: async () => {
      if (timelineError) {
        throw timelineError;
      }
      return timeline(actor, reason);
    },
  };
}

function timeline(actor, reason) {
  return [
    {
      event: "commented",
      user: APP,
      created_at: "2026-10-22T10:00:05Z",
      body: `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${"b".repeat(40)} -->\nStopped.\n\n- Reason: \`${reason}\``,
    },
    { event: "labeled", actor, label: { name: "needs-human" }, created_at: "2026-10-22T10:00:00Z" },
  ];
}

async function outputs(activity, options) {
  const dir = tempDir("lane-hold-");
  try {
    const env = {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: "o/r",
      GITHUB_OUTPUT: join(dir, "out"),
      PR_NUMBER: "7",
      APP_SENDER_ID: String(APP.id),
      ACTIVITY: activity,
      TRACKER_CONFIG: join(dir, "absent.json"),
    };
    await main(env, { api: fakeApi(options), log: () => {} });
    return readFileSync(env.GITHUB_OUTPUT, "utf8");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("another lane's escalation leaves resolve-conflicts and fix-docs unheld and lane-escalated", async () => {
  assert.equal(await outputs("resolve-conflicts"), "held=false\nlane-escalated=true\n");
  assert.equal(await outputs("fix-docs", { reason: "ci-fix-escalated" }), "held=false\nlane-escalated=true\n");
});

test("resolve-conflicts's own escalation or a person's label holds it", async () => {
  assert.equal(await outputs("resolve-conflicts", { reason: "unresolved-conflict" }), "held=true\nlane-escalated=false\n");
  assert.equal(await outputs("resolve-conflicts", { actor: PERSON }), "held=true\nlane-escalated=false\n");
});

test("a person's inline review-thread reply since the label, or an unread review listing, holds it", async () => {
  // GitHub's timeline has no event for a reply inside an existing review thread.
  const reply = (user) => ({ id: 2, in_reply_to_id: 1, user, body: "Wait.", created_at: "2026-10-22T11:00:00Z", updated_at: "2026-10-22T11:00:00Z" });
  assert.equal(await outputs("resolve-conflicts", { reviewComments: [reply(PERSON)] }), "held=true\nlane-escalated=false\n");
  assert.equal(await outputs("resolve-conflicts", { reviewComments: [reply(APP)] }), "held=false\nlane-escalated=true\n");
  assert.equal(await outputs("resolve-conflicts", { reviewComments: new Error("GET pulls/7/comments returned 404") }), "held=true\nlane-escalated=false\n");
});

// Outage posture element 2: a fault leaves the hold unknown, so the step holds
// green with unread=true and neither held nor lane-escalated, which every
// caller reads as "run nothing, post nothing".
test("a GitHub fault on the pull, timeline or review read holds the step unread", async () => {
  const unread = "unread=true\n";
  for (const status of [502, 503, 429]) {
    assert.equal(await outputs("fix-docs", { pullError: refused(status) }), unread, `pull ${status}`);
    assert.equal(await outputs("resolve-conflicts", { timelineError: refused(status) }), unread, `timeline ${status}`);
    assert.equal(await outputs("resolve-conflicts", { reviewComments: refused(status) }), unread, `review comments ${status}`);
  }
  const network = Object.assign(new TypeError("fetch failed"), { cause: { code: "ECONNRESET" } });
  assert.equal(await outputs("fix-docs", { pullError: network }), unread, "no answer");
  const stop = Object.assign(new Error("GET pulls/7 stopped"), { name: "RateLimitStop" });
  assert.equal(await outputs("fix-docs", { timelineError: stop }), unread, "a rate-guard stop");
});

test("a refused read that is no fault still fails the step, and a non-fault review read still holds for a person", async () => {
  for (const status of [401, 403, 404, 422]) {
    await assert.rejects(outputs("fix-docs", { pullError: refused(status) }), /returned/, `pull ${status}`);
    await assert.rejects(outputs("resolve-conflicts", { timelineError: refused(status) }), /returned/, `timeline ${status}`);
    assert.equal(await outputs("resolve-conflicts", { reviewComments: refused(status) }), "held=true\nlane-escalated=false\n", `review comments ${status}`);
  }
});

test("no human-gated label is no hold; do-not-merge is left to the activity's applies-when", async () => {
  assert.equal(await outputs("resolve-conflicts", { labels: [] }), "held=false\nlane-escalated=false\n");
  assert.equal(await outputs("resolve-conflicts", { labels: ["do-not-merge"] }), "held=false\nlane-escalated=false\n");
});

// The default client goes through the rate guard, so each answer leaves its
// reading for the job-end api-budget notice (log-api-budget's action).
test("the default client keeps each answer's rate-limit reading under API_BUDGET_TOKEN", async () => {
  const dir = tempDir("lane-hold-");
  const saved = { fetch: globalThis.fetch, token: process.env.API_BUDGET_TOKEN, temp: process.env.RUNNER_TEMP };
  const headers = { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4990", "x-ratelimit-used": "10", "x-ratelimit-reset": "1800000000", "x-ratelimit-resource": "core" };
  globalThis.fetch = async (url) =>
    new Response(JSON.stringify(String(url).endsWith("/pulls/7") ? { head: { sha: HEAD }, labels: [] } : []), { status: 200, headers });
  process.env.API_BUDGET_TOKEN = "github-token";
  process.env.RUNNER_TEMP = dir;
  try {
    const env = {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: "o/r",
      GITHUB_OUTPUT: join(dir, "out"),
      PR_NUMBER: "7",
      APP_SENDER_ID: String(APP.id),
      ACTIVITY: "fix-docs",
      TRACKER_CONFIG: join(dir, "absent.json"),
    };
    await main(env, { log: () => {} });
    assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "held=false\nlane-escalated=false\n");
    assert.equal(readFileSync(join(dir, "api-budget", "github-token"), "utf8"), "200 5000 4990 10 1800000000 core repos/{repo}/pulls/{n}\n");
  } finally {
    globalThis.fetch = saved.fetch;
    for (const [key, value] of [["API_BUDGET_TOKEN", saved.token], ["RUNNER_TEMP", saved.temp]]) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
    rmSync(dir, { recursive: true, force: true });
  }
});
