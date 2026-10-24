// Expected values come from report-escalation.sh (its label, then its comment
// with a Reason line) and its reason-to-activity map.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { main } from "./lane-hold.mjs";

const APP = { login: "melodic-automation-lanes[bot]", id: 337595936, type: "Bot" };
const PERSON = { login: "kyle-sexton", id: 153232337, type: "User" };
const HEAD = "a".repeat(40);

function fakeApi({ labels = ["needs-human"], actor = APP, reason = "feedback-disputed" } = {}) {
  return {
    getPull: async () => ({ head: { sha: HEAD }, labels: labels.map((name) => ({ name })) }),
    listIssueComments: async () => [
      {
        user: APP,
        created_at: "2026-10-22T10:00:05Z",
        body: `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${"b".repeat(40)} -->\nStopped.\n\n- Reason: \`${reason}\``,
      },
    ],
    listLabelEvents: async () => [{ event: "labeled", actor, label: { name: "needs-human" }, created_at: "2026-10-22T10:00:00Z" }],
  };
}

async function outputs(activity, options) {
  const dir = mkdtempSync(join(tmpdir(), "lane-hold-"));
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

test("no human-gated label is no hold; do-not-merge is left to the activity's applies-when", async () => {
  assert.equal(await outputs("resolve-conflicts", { labels: [] }), "held=false\nlane-escalated=false\n");
  assert.equal(await outputs("resolve-conflicts", { labels: ["do-not-merge"] }), "held=false\nlane-escalated=false\n");
});
