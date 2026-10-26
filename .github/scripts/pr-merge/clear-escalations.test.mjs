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

import { main, NATIVE_READS_PER_RUN } from "./clear-escalations.mjs";
import { refusalBody } from "./enable-auto-merge.mjs";

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
// `evidence` is what the gate's reader (enable-auto-merge pythonVerify) answers.
function world({ timeline, mainFiles = [{ filename: "README.md" }], mergeable = false, pullFiles = [], author, evidence = () => null }) {
  const calls = [];
  const reads = [];
  const verify = async (pull, rung) => {
    reads.push({ pull, rung });
    return evidence(pull);
  };
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
      return { number: 7, state: "open", user: author, base: { ref: "main", sha: MAIN }, head: { sha: HEAD }, labels: [{ name: "needs-human" }], mergeable };
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
  return { github, verify, reads, calls, writes: () => calls.filter((call) => call.method !== "GET") };
}

const run = async (w, env = {}) => {
  const logs = [];
  const original = console.log;
  console.log = (line) => logs.push(line);
  try {
    return { code: await main({ env: { ...ENV, ...env }, github: w.github, verify: w.verify }), logs };
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
const commitCommented = (user, at) => ({ event: "commit-commented", comments: [{ user, body: "On this commit.", created_at: at }] });

test("a person's comment, review, or review comment after the label keeps it", async () => {
  for (const spoke of [
    commented(OWNER, "Leave this for a person.", "2026-10-18T12:00:00Z"),
    reviewed(OWNER, "2026-10-18T12:00:00Z"),
    lineCommented(OWNER, "2026-10-18T12:00:00Z"),
    commitCommented(OWNER, "2026-10-18T12:00:00Z"),
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
    commitCommented(CLAUDE_BOT, "2026-10-18T12:00:00Z"),
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

// pr-merge's own escalations, in babysit_merge.py's verify_escalation_body and
// risk_comment_body formats: the marker line, then a line naming `at head `<sha>``.
const OLD = "d".repeat(40);
const verifyBody = (head) =>
  `<!-- babysit-merge-verify-escalation -->\nUnattended merge: the verifier verdict refuses \`verify:fail\` at head \`${head}\`. That refusal needs a human, who merges in person; the pr-merge lane will not merge this pull request.`;
const riskBody = (head) =>
  `<!-- babysit-merge-risk -->\nUnattended merge: risk **HIGH** at head \`${head}\`. Only LOW merges without a human. This pull request waits for one.\n\n\`\`\`text\nHIGH workflow-change: .github/workflows/ci.yml\n\`\`\``;
// pr-merge writes its comment, then the label.
const mergeEscalated = (body) => [commented(BOT, body, "2026-10-18T09:59:58Z"), labeled(BOT, "2026-10-18T10:00:00Z")];

test("a pr-merge verify escalation at an old head comes off as head-moved, naming both heads", async () => {
  const w = world({ timeline: mergeEscalated(verifyBody(OLD)) });
  const { code } = await run(w);
  assert.equal(code, 0);
  const [comment, removal] = w.writes();
  assert.equal(w.writes().length, 2);
  assert.equal(comment.body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=head-moved head=${HEAD} -->`);
  assert.match(comment.body.body, /`head-moved`/);
  assert.match(comment.body.body, new RegExp(`\`${OLD}\``));
  assert.match(comment.body.body, new RegExp(`\`${HEAD}\``));
  assert.deepEqual(removal, { method: "DELETE", path: `/repos/${REPO}/issues/7/labels/needs-human`, body: undefined });
});

test("a pr-merge risk comment at an old head comes off as head-moved", async () => {
  const w = world({ timeline: mergeEscalated(riskBody(OLD)) });
  await run(w);
  assert.equal(w.writes().length, 2);
  assert.equal(w.writes()[0].body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=head-moved head=${HEAD} -->`);
});

// Under merge.lane-prs native pr-merge never lists a lanes App PR, so nothing
// would judge its new head and escalate again: the label stays.
test("a pr-merge escalation at an old head on a lanes App PR is kept under lane-prs native, cleared under gate", async () => {
  const native = world({ timeline: mergeEscalated(riskBody(OLD)), author: BOT });
  const { logs } = await run(native, { LANE_PRS: "native" });
  assert.equal(native.writes().length, 0);
  assert.ok(logs.some((line) => /#7 kept: under merge\.lane-prs native/.test(line)), logs.join("\n"));
  const gate = world({ timeline: mergeEscalated(riskBody(OLD)), author: BOT });
  await run(gate, { LANE_PRS: "gate" });
  assert.equal(gate.writes().length, 2);
  // An adopted owner PR is still gated under native, so it clears.
  const owner = world({ timeline: mergeEscalated(riskBody(OLD)), author: OWNER });
  await run(owner, { LANE_PRS: "native" });
  assert.equal(owner.writes().length, 2);
});

const sharedCopyBody = (head) =>
  `<!-- babysit-merge-shared-copy-escalation -->\nUnattended merge: the shared-library canonical \`lib/a.sh\` changed on \`main\` since merge base \`${OLD}\`, so the copies this pull request carries are stale at head \`${head}\`.`;

test("a pr-merge shared-copy escalation at an old head comes off as head-moved", async () => {
  const w = world({ timeline: mergeEscalated(sharedCopyBody(OLD)) });
  await run(w);
  assert.equal(w.writes().length, 2);
  assert.equal(w.writes()[0].body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=head-moved head=${HEAD} -->`);
  assert.deepEqual(w.writes()[1], { method: "DELETE", path: `/repos/${REPO}/issues/7/labels/needs-human`, body: undefined });
});

test("a pr-merge shared-copy escalation at the current head is kept", async () => {
  const w = world({ timeline: mergeEscalated(sharedCopyBody(HEAD)) });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

const dependabotMajorBody = (head) =>
  `<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-dependabot-major -->\nUnattended merge: \`x(unreadable)\` is a major version update, one whose version cannot be read (\`(unreadable)\`), or one whose title and commit metadata disagree (\`(disagree)\`), at head \`${head}\`.`;

test("a pr-merge Dependabot-major escalation at an old head comes off as head-moved", async () => {
  const w = world({ timeline: mergeEscalated(dependabotMajorBody(OLD)) });
  await run(w);
  assert.equal(w.writes().length, 2);
  assert.equal(w.writes()[0].body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=head-moved head=${HEAD} -->`);
});

test("a pr-merge Dependabot-major escalation at the current head is kept", async () => {
  const w = world({ timeline: mergeEscalated(dependabotMajorBody(HEAD)) });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a pr-merge escalation naming the current head is kept", async () => {
  for (const timeline of [
    mergeEscalated(verifyBody(HEAD)),
    mergeEscalated(riskBody(HEAD)),
    // Rewritten in place at the new head after the label.
    [commented(BOT, verifyBody(HEAD), "2026-10-18T09:59:58Z", "2026-10-18T12:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z")],
    // Either marker at the current head holds it.
    [...mergeEscalated(verifyBody(OLD)), commented(BOT, riskBody(HEAD), "2026-10-18T12:00:00Z")],
  ]) {
    const w = world({ timeline });
    await run(w);
    assert.deepEqual(w.writes(), []);
  }
});

test("a comment after a pr-merge escalation's label keeps it", async () => {
  const w = world({ timeline: [...mergeEscalated(verifyBody(OLD)), commented(OWNER, "Leave this for a person.", "2026-10-18T12:00:00Z")] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("another lane's marker beside a pr-merge escalation at an old head keeps it", async () => {
  for (const marker of [
    "<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-dependabot-major -->",
    "<!-- work-items:escalation lane=work-loop kind=escalated -->",
  ]) {
    const w = world({ timeline: [...mergeEscalated(verifyBody(OLD)), commented(BOT, `${marker}\nheld`, "2026-10-18T10:00:05Z")] });
    await run(w);
    assert.deepEqual(w.writes(), [], marker);
  }
});

test("a pr-merge escalation whose head does not parse as 40-hex is kept", async () => {
  for (const head of ["d".repeat(39), "D".repeat(40), `${OLD}0`, ""]) {
    const w = world({ timeline: mergeEscalated(verifyBody(head)) });
    await run(w);
    assert.deepEqual(w.writes(), [], head);
  }
  const none = world({ timeline: mergeEscalated("<!-- babysit-merge-verify-escalation -->\nUnattended merge: held.") });
  await run(none);
  assert.deepEqual(none.writes(), []);
});

test("a pr-merge comment rewritten just before the label pairs with it", async () => {
  const w = world({ timeline: [commented(BOT, verifyBody(OLD), "2026-10-17T08:00:00Z", "2026-10-18T09:59:58Z"), labeled(BOT, "2026-10-18T10:00:00Z")] });
  await run(w);
  assert.equal(w.writes().at(-1)?.method, "DELETE");
});

test("a pr-merge risk comment created long ago and rewritten to escalate just before the label pairs with it", async () => {
  // babysit_merge.py appends its persisted-refusal line, then adds the label.
  const escalatedRisk = `${riskBody(OLD)}\n\nThis refusal has stood unchanged at this head, so a person is needed: the pr-merge lane added the human-gated label.`;
  const w = world({ timeline: [commented(BOT, escalatedRisk, "2026-10-18T08:30:00Z", "2026-10-18T09:59:59Z"), labeled(BOT, "2026-10-18T10:00:00Z")] });
  await run(w);
  assert.equal(w.writes().length, 2);
  assert.equal(w.writes()[0].body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=head-moved head=${HEAD} -->`);
  assert.deepEqual(w.writes()[1], { method: "DELETE", path: `/repos/${REPO}/issues/7/labels/needs-human`, body: undefined });
});

test("a pr-merge escalation posted as a new comment beside an older reasons comment pairs with the label", async () => {
  // babysit_merge.py posts the escalation new, then adds the label; the
  // earlier reasons comment it extends stays as it was.
  const line = "This refusal has stood unchanged at this head, so a person is needed: the pr-merge lane added the human-gated label.";
  const timeline = (head) => [
    commented(BOT, riskBody(head), "2026-10-18T08:30:00Z"),
    commented(BOT, `${riskBody(head)}\n\n${line}`, "2026-10-18T09:59:59Z"),
    labeled(BOT, "2026-10-18T10:00:00Z"),
  ];
  const moved = world({ timeline: timeline(OLD) });
  await run(moved);
  assert.equal(moved.writes().length, 2);
  assert.equal(moved.writes()[0].body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=head-moved head=${HEAD} -->`);
  const current = world({ timeline: timeline(HEAD) });
  await run(current);
  assert.deepEqual(current.writes(), []);
});

test("an old pr-merge comment with nothing written beside a later label is kept", async () => {
  // The label came on for another reason whose comment write failed.
  const w = world({ timeline: [commented(BOT, riskBody(OLD), "2026-10-17T08:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z")] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a Dependabot-major escalation at an old head beside an older pr-merge comment comes off as head-moved", async () => {
  // babysit_merge.py's major_escalation_body, posted before the label it adds.
  // Under `merge.dependabot.majors: review` pr-merge judges the new head
  // afresh, so a moved head clears it like its other escalations.
  const major = `<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-dependabot-major -->\nUnattended merge: \`actions/checkout 5.0.0\` is a major version update at head \`${OLD}\`.`;
  for (const prior of [riskBody(OLD), verifyBody(OLD)]) {
    const w = world({
      timeline: [commented(BOT, prior, "2026-10-17T08:00:00Z"), commented(BOT, major, "2026-10-18T09:59:58Z"), labeled(BOT, "2026-10-18T10:00:00Z")],
    });
    await run(w);
    assert.equal(w.writes().length, 2, prior.split("\n")[0]);
  }
});

test("another lane's escalation just before the label keeps it beside an older pr-merge comment", async () => {
  const other = `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${KEY} -->\nThe pr-unblock lane stopped on this pull request and needs a person: why.`;
  const w = world({
    timeline: [commented(BOT, riskBody(OLD), "2026-10-17T08:00:00Z"), commented(BOT, other, "2026-10-18T09:59:58Z"), labeled(BOT, "2026-10-18T10:00:00Z")],
  });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a needs-human a person added beside a pr-merge escalation at an old head is kept", async () => {
  const w = world({ timeline: [commented(BOT, verifyBody(OLD), "2026-10-18T09:59:58Z"), labeled(OWNER, "2026-10-18T10:00:00Z")] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a feedback-protected-path label comes off once the PR changes nothing under .github/workflows/, whatever else it changes under .github/", async () => {
  for (const [pullFiles, clears] of [
    [[{ filename: ".github/scripts/x.mjs" }, { filename: ".github/CODEOWNERS" }], true],
    [[{ filename: "README.md" }, { filename: ".github/workflows/ci.yml" }], false],
  ]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated("feedback-protected-path")], pullFiles });
    await run(w);
    assert.equal(w.writes().at(-1)?.method === "DELETE", clears, pullFiles[0].filename);
  }
});

// A review lane's hold: its marker comment, by claude[bot], or by
// github-actions[bot] when the comment ends in the lane's footer (the
// pr-review-cli shape). Adding a label the PR already carries writes no
// `labeled` event, so the hold may sit under the App's own label.
const HOLD = "<!-- claude-lane-hold lane=claude-security-review sha=" + HEAD + " criteria=trust-gate -->";
const laneHold = (user, at, { footer = true, updatedAt = at } = {}) =>
  commented(user, `${HOLD}\nChanges a trust gate.${footer ? "\n\n`claude-lane: claude-security-review`\n" : ""}`, at, updatedAt);
const unlabeled = (actor, at) => ({ event: "unlabeled", actor, label: { name: "needs-human" }, created_at: at });

test("a review-lane hold keeps the label a clearing pr-unblock escalation would take off", async () => {
  for (const hold of [laneHold(ACTIONS_BOT, "2026-10-18T11:00:00Z"), laneHold(CLAUDE_BOT, "2026-10-18T11:00:00Z")]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), hold] });
    const { logs } = await run(w);
    assert.deepEqual(w.writes(), [], hold.user.login);
    assert.match(logs.join("\n"), /#7 kept: a review lane holds it/, hold.user.login);
  }
});

test("a review-lane hold written before the App's label, with no unlabel since, keeps it", async () => {
  const w = world({ timeline: [laneHold(ACTIONS_BOT, "2026-10-18T09:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z"), escalated()] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a review-lane hold keeps a pr-merge head-moved escalation too", async () => {
  const w = world({ timeline: [...mergeEscalated(verifyBody(OLD)), laneHold(ACTIONS_BOT, "2026-10-18T11:00:00Z")] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a review-lane hold a person approved by unlabeling no longer keeps a later escalation", async () => {
  const w = world({
    timeline: [
      laneHold(ACTIONS_BOT, "2026-10-18T08:00:00Z"),
      unlabeled(OWNER, "2026-10-18T09:00:00Z"),
      labeled(BOT, "2026-10-18T10:00:00Z"),
      escalated(),
    ],
  });
  await run(w);
  assert.equal(w.writes().at(-1)?.method, "DELETE");
});

test("a review-lane hold edited after the unlabel keeps it", async () => {
  const w = world({
    timeline: [
      laneHold(ACTIONS_BOT, "2026-10-18T08:00:00Z", { updatedAt: "2026-10-18T09:30:00Z" }),
      unlabeled(OWNER, "2026-10-18T09:00:00Z"),
      labeled(BOT, "2026-10-18T10:00:00Z"),
      escalated(),
    ],
  });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a hold marker from github-actions[bot] with no lane footer, or from another bot, is not a review-lane hold", async () => {
  for (const hold of [laneHold(ACTIONS_BOT, "2026-10-18T11:00:00Z", { footer: false }), laneHold(CODEX_BOT, "2026-10-18T11:00:00Z")]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), hold] });
    await run(w);
    assert.equal(w.writes().at(-1)?.method, "DELETE", hold.user.login);
  }
});

// enable-auto-merge's own person refusal comment (refusalBody), then its
// label: under merge.lane-prs native the only writer of a lanes App PR's
// pr-merge label. #10090's shape: a risk hold on unbound reviews at the head
// the PR still has.
const UNBOUND = "pr-merge's gate holds it on its risk score (evidence-unbound:claude-review: not bound: rerun-not-allowed)";
const nativeEscalated = (reason, head = HEAD) => mergeEscalated(refusalBody(true, reason, head, "needs-human"));
const clean = (pull) => ({ head: pull.headRefOid, refusal: null, ineligible: null, reviews: null });

test("enable-auto-merge's label at the current head comes off once the gate's reader no longer refuses there", async () => {
  const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence: clean });
  const { code, logs } = await run(w, { LANE_PRS: "native" });
  assert.equal(code, 0, logs.join("\n"));
  assert.deepEqual(w.reads, [{ pull: { number: 7, headRefOid: HEAD, baseRefOid: MAIN }, rung: "C3" }]);
  const [comment, removal] = w.writes();
  assert.equal(w.writes().length, 2);
  assert.equal(comment.body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=refusal-cleared head=${HEAD} -->`);
  assert.match(comment.body.body, new RegExp(`\`${HEAD}\``));
  assert.deepEqual(removal, { method: "DELETE", path: `/repos/${REPO}/issues/7/labels/needs-human`, body: undefined });
});

test("enable-auto-merge's label comes off when the refusal is now one the lanes clear", async () => {
  const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence: (pull) => ({ ...clean(pull), refusal: "verify:no-pass", needsHuman: false }) });
  await run(w, { LANE_PRS: "native" });
  assert.equal(w.writes().at(-1)?.method, "DELETE");
});

test("enable-auto-merge's label stays while its cause, or another a person must clear, holds at the head", async () => {
  for (const evidence of [
    // A security finding or a trusted-actor widening stays a person's.
    (pull) => ({ ...clean(pull), reviews: "security-finding: 1 open CRITICAL finding" }),
    (pull) => ({ ...clean(pull), reviews: "trust-gate:trusted-actors: widens the trusted actors" }),
    // A verifier refusal the gate marks needsHuman, an issue link the lane does not take.
    (pull) => ({ ...clean(pull), refusal: "verify:untrusted-spec", needsHuman: true }),
    (pull) => ({ ...clean(pull), ineligible: "untrusted-provenance" }),
    // Unread, read at another head, or a read that fails.
    () => null,
    () => ({ ...clean({ headRefOid: OLD }) }),
    () => {
      throw new Error("babysit_verify_evidence.py exited 1");
    },
  ]) {
    const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence });
    await run(w, { LANE_PRS: "native" });
    assert.deepEqual(w.writes(), [], String(evidence));
  }
});

test("enable-auto-merge's hold-path or cost-path label is never judged on the reader's answer", async () => {
  for (const reason of ["it changes .github/workflows/ci.yml, a hold path", "it changes infra/main.ts, a cost path"]) {
    const w = world({ timeline: nativeEscalated(reason), author: BOT, evidence: clean });
    await run(w, { LANE_PRS: "native" });
    assert.deepEqual(w.writes(), [], reason);
    assert.deepEqual(w.reads, [], reason);
  }
});

test("a label a person added, or added back, beside enable-auto-merge's comment is kept unread", async () => {
  for (const timeline of [
    [commented(BOT, refusalBody(true, UNBOUND, HEAD, "needs-human"), "2026-10-18T09:59:58Z"), labeled(OWNER, "2026-10-18T10:00:00Z")],
    [...nativeEscalated(UNBOUND), unlabeled(OWNER, "2026-10-18T11:00:00Z"), labeled(OWNER, "2026-10-18T11:00:10Z")],
  ]) {
    const w = world({ timeline, author: BOT, evidence: clean });
    await run(w, { LANE_PRS: "native" });
    assert.deepEqual(w.writes(), []);
    assert.deepEqual(w.reads, []);
  }
});

test("a pr-merge person comment not in enable-auto-merge's exact shape is not re-judged", async () => {
  const edited = `${refusalBody(true, UNBOUND, HEAD, "needs-human")}\nedited`;
  const w = world({ timeline: mergeEscalated(edited), author: BOT, evidence: clean });
  await run(w, { LANE_PRS: "native" });
  assert.deepEqual(w.writes(), []);
  assert.deepEqual(w.reads, []);
});

test("enable-auto-merge's refusal at an old head is judged at the current one", async () => {
  const still = world({ timeline: nativeEscalated(UNBOUND, OLD), author: BOT, evidence: (pull) => ({ ...clean(pull), reviews: "security-finding: 1 open CRITICAL finding" }) });
  await run(still, { LANE_PRS: "native" });
  assert.deepEqual(still.writes(), []);
  const gone = world({ timeline: nativeEscalated(UNBOUND, OLD), author: BOT, evidence: clean });
  await run(gone, { LANE_PRS: "native" });
  assert.equal(gone.writes()[0].body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=refusal-cleared head=${HEAD} -->`);
});

test("at most NATIVE_READS_PER_RUN reader runs a run", async () => {
  const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence: () => null });
  const held = Array.from({ length: NATIVE_READS_PER_RUN + 2 }, (_, i) => ({ number: 7, pull_request: {}, i }));
  const github = async (method, path, body) => (method === "GET" && path.includes("issues?state=open") ? (path.endsWith("page=1") ? held : []) : w.github(method, path, body));
  const { logs } = await run({ ...w, github });
  assert.equal(w.reads.length, NATIVE_READS_PER_RUN);
  assert.equal(logs.filter((line) => /reader runs this run/.test(line)).length, 2);
});
