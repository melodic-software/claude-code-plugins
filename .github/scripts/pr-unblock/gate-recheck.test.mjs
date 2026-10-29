// Expected values come from report-escalation.sh (its label, then its comment)
// and the review lanes' hold marker (docs/conventions/pr-pipeline/README.md,
// "Review-lane holds"): the races between the select job's read and the write
// runner's push.
import assert from "node:assert/strict";
import { readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

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

async function recheck(timeline, env = {}) {
  const dir = tempDir("gate-recheck-");
  try {
    const out = join(dir, "out");
    const asked = [];
    const logs = [];
    const api = {
      listTimeline: async (pr) => {
        asked.push(pr);
        return timeline;
      },
    };
    const vars = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: out, PR_NUMBER: "7", HEAD_SHA: HEAD, APP_SENDER_ID: String(APP.id), LABEL: "needs-human", ...env };
    await main(vars, { api, log: (line) => logs.push(line) });
    return { out: readFileSync(out, "utf8"), asked, logs };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("a lane escalation still on the timeline is read again as one", async () => {
  const { out, asked, logs } = await recheck(ESCALATED);
  assert.equal(out, "lane-escalation=true\n");
  assert.deepEqual(asked, [7]);
  assert.match(logs[0], /^#7 needs-human: lane-escalation \(/);
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
  assert.match(logs[0], /^#7 needs-human: review-hold \(/);
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
});
