// Expected values come from the needs-human recheck acceptance criteria and report-escalation.sh's
// comment format: an App-set needs-human on a PR escalated as workflow-staged
// comes off within one sweep once main stages no .github/workflows/ change into
// the head, with one comment naming the reason and the head; a label a person
// set, a reason that still holds, a label a person added back, a marker a
// person wrote, and a person speaking after the escalation all keep it. Per the
// owner decision on #8387, a bot account speaking after the label (AI review,
// another lane) does not keep it.
import assert from "node:assert/strict";
import { test } from "node:test";

import { main } from "./clear-escalations.mjs";

const REPO = "melodic-software/claude-code-plugins";
const BOT = { login: "melodic-automation-lanes[bot]", type: "Bot" };
const OWNER = { login: "kyle-sexton", type: "User" };
const CLAUDE_BOT = { login: "claude[bot]", type: "Bot" };
const CODEX_BOT = { login: "chatgpt-codex-connector[bot]", type: "Bot" };
const ACTIONS_BOT = { login: "github-actions[bot]", type: "Bot" };
const MAIN = "a".repeat(40);
const HEAD = "b".repeat(40);
const KEY = "c".repeat(40);
const ENV = { GITHUB_REPOSITORY: REPO, KILL_SWITCH: "proceed", TRACKER_CONFIG: "/nonexistent/.work-item-tracker.json" };

const escalationBody = (reason) =>
  `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${KEY} -->\nThe pr-unblock lane stopped on this pull request and needs a person: why.\n\n- Reason: \`${reason}\`\n- Resume key: \`${KEY}\` (the head the lane stopped on)\n`;
const labeled = (actor, at) => ({ event: "labeled", actor, label: { name: "needs-human" }, created_at: at });
const commented = (user, body, at, updatedAt = at) => ({ event: "commented", user, actor: user, body, created_at: at, updated_at: updatedAt });
const escalated = (reason = "workflow-staged", { user = BOT, at = "2026-10-18T10:00:05Z" } = {}) => commented(user, escalationBody(reason), at);

// One open pull request (number 7) labeled needs-human; `timeline` is its timeline and
// `mainFiles` the files main changed since its merge base with the head.
function world({ timeline, mainFiles = [{ filename: "README.md" }], mergeable = false, pullFiles = [] }) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    const route = path.replace(/[?&]per_page=100&page=\d+$/, "");
    if (method === "GET" && route === `/repos/${REPO}/git/ref/heads/main`) {
      return { ref: "refs/heads/main", object: { sha: MAIN } };
    }
    if (method === "GET" && route === `/repos/${REPO}/issues?state=open&labels=needs-human`) {
      return path.endsWith("page=1") ? [{ number: 7, pull_request: {}, labels: [{ name: "needs-human" }] }] : [];
    }
    if (method === "GET" && route === `/repos/${REPO}/issues/7/timeline`) {
      return path.endsWith("page=1") ? timeline : [];
    }
    if (method === "GET" && route === `/repos/${REPO}/pulls/7`) {
      return { number: 7, state: "open", base: { ref: "main" }, head: { sha: HEAD }, labels: [{ name: "needs-human" }], mergeable };
    }
    if (method === "GET" && route === `/repos/${REPO}/compare/${HEAD}...${MAIN}`) {
      return { files: mainFiles };
    }
    if (method === "GET" && route === `/repos/${REPO}/pulls/7/files`) {
      return path.endsWith("page=1") ? pullFiles : [];
    }
    if (method === "POST" || method === "DELETE") {
      return null;
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { github, calls, writes: () => calls.filter((call) => call.method !== "GET") };
}

const run = async (w) => {
  const logs = [];
  const original = console.log;
  console.log = (line) => logs.push(line);
  try {
    return { code: await main({ env: ENV, github: w.github }), logs };
  } finally {
    console.log = original;
  }
};

test("an App-set needs-human whose workflow-staged reason cleared comes off with one comment", async () => {
  const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated()] });
  const { code } = await run(w);
  assert.equal(code, 0);
  const [comment, removal] = w.writes();
  assert.equal(w.writes().length, 2);
  assert.equal(comment.method, "POST");
  assert.equal(comment.path, `/repos/${REPO}/issues/7/comments`);
  assert.equal(comment.body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=workflow-staged head=${HEAD} -->`);
  assert.match(comment.body.body, /`workflow-staged`/);
  assert.match(comment.body.body, new RegExp(`\`${HEAD}\``));
  assert.deepEqual(removal, { method: "DELETE", path: `/repos/${REPO}/issues/7/labels/needs-human`, body: undefined });
});

test("a needs-human a person added is kept", async () => {
  const w = world({ timeline: [labeled(OWNER, "2026-10-18T10:00:00Z"), escalated()] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("an App-set needs-human is kept while main still changes a workflow", async () => {
  const w = world({
    timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated()],
    mainFiles: [{ filename: "README.md" }, { filename: ".github/workflows/pr-merge.yml" }],
  });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("an App-set needs-human a person removed and added back is kept", async () => {
  const w = world({
    timeline: [
      labeled(BOT, "2026-10-18T10:00:00Z"),
      escalated(),
      { event: "unlabeled", actor: OWNER, label: { name: "needs-human" }, created_at: "2026-10-18T11:00:00Z" },
      labeled(OWNER, "2026-10-18T11:00:10Z"),
    ],
  });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("an escalation marker a person wrote is never read for a reason", async () => {
  const w = world({
    timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated("workflow-staged", { user: OWNER })],
  });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

const reviewed = (user, at) => ({ event: "reviewed", user, state: "commented", body: "Review.", submitted_at: at });
const lineCommented = (user, at) => ({ event: "line-commented", comments: [{ user, body: "Nit.", created_at: at }] });

test("a person's comment, review, or review comment after the label keeps it", async () => {
  for (const spoke of [
    commented(OWNER, "Leave this for a person.", "2026-10-18T12:00:00Z"),
    reviewed(OWNER, "2026-10-18T12:00:00Z"),
    lineCommented(OWNER, "2026-10-18T12:00:00Z"),
    commented(null, "Ghost author.", "2026-10-18T12:00:00Z"),
  ]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), spoke] });
    await run(w);
    assert.deepEqual(w.writes(), [], spoke.event);
  }
});

test("an AI review or another bot's comment after the label does not keep it", async () => {
  for (const spoke of [
    reviewed(CLAUDE_BOT, "2026-10-18T12:00:00Z"),
    lineCommented(CLAUDE_BOT, "2026-10-18T12:00:00Z"),
    commented(CODEX_BOT, "Codex review: no issues.", "2026-10-18T12:00:00Z"),
    commented(ACTIONS_BOT, "CI summary.", "2026-10-18T12:00:00Z"),
    commented(BOT, "A lane note.", "2026-10-18T12:00:00Z"),
  ]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), spoke] });
    await run(w);
    assert.equal(w.writes().at(-1)?.method, "DELETE", `${spoke.event} ${spoke.user?.login ?? spoke.comments?.[0].user.login}`);
  }
});

test("an earlier escalation a person decides keeps the label when a later one would clear", async () => {
  const w = world({
    timeline: [
      labeled(BOT, "2026-10-18T10:00:00Z"),
      escalated("feedback-disputed"),
      escalated("feedback-protected-path", { at: "2026-10-18T14:00:00Z" }),
    ],
    pullFiles: [{ filename: "README.md" }],
  });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("an App label with no escalation right after it is kept", async () => {
  const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated("workflow-staged", { at: "2026-10-18T11:00:00Z" })] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a pr-merge escalation by the App after the label keeps it", async () => {
  for (const marker of [
    "<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-verify-escalation -->",
    "<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-dependabot-major -->",
    "<!-- some-future-lane-marker -->",
  ]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), commented(BOT, `${marker}\nUnattended merge: held.`, "2026-10-18T12:00:00Z")] });
    await run(w);
    assert.deepEqual(w.writes(), [], marker);
  }
});

test("an App comment written before the label and edited after it with another marker keeps it", async () => {
  const marker = "<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-verify-escalation -->";
  const edited = commented(BOT, `${marker}\nUnattended merge: held.`, "2026-10-18T09:00:00Z", "2026-10-18T12:00:00Z");
  const w = world({ timeline: [edited, labeled(BOT, "2026-10-18T10:00:00Z"), escalated()] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a reason a person decides is never cleared", async () => {
  const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated("feedback-round-cap")] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a conflict reason clears only once GitHub reports the PR mergeable", async () => {
  const timeline = [labeled(BOT, "2026-10-18T10:00:00Z"), escalated("unresolved-conflict")];
  const unknown = world({ timeline, mergeable: null });
  await run(unknown);
  assert.deepEqual(unknown.writes(), []);
  const clean = world({ timeline, mergeable: true });
  await run(clean);
  assert.equal(clean.writes().at(-1).method, "DELETE");
});

test("a sweep that finds its own comment for this head retries only the removal", async () => {
  const done = commented(BOT, `<!-- pr-pipeline needs-human-cleared reason=workflow-staged head=${HEAD} -->\nearlier`, "2026-10-18T12:00:00Z");
  const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), done] });
  await run(w);
  assert.deepEqual(
    w.writes().map((call) => call.method),
    ["DELETE"],
  );
});
