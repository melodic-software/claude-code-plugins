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
import { escalationActivity, escalationRoute, ROUTES } from "../pr-unblock/escalation-routes.mjs";

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
// `headChecks` is the head's check runs, as the job token lists them, or an
// Error its read throws.
// The head's pr-require-checks runs are suites 500 and 501.
const REQUIRED_SUITES = [500, 501];
const check = (name, conclusion, { id = 1, slug = "github-actions", suite = 500 } = {}) => ({ id, name, status: "completed", conclusion, app: { slug }, check_suite: { id: suite } });
const RED = [check("test-node", "failure")];
// `evidence` is what the gate's reader (enable-auto-merge pythonVerify) answers.
function world({ timeline, mainFiles = [{ filename: "README.md" }], mergeable = false, pullFiles = [], reviewComments = [], reviews = [], threadsFail = false, author, headChecks = [], evidence = () => null, numbers = [7] }) {
  const calls = [];
  const checks = async (method, path) => {
    calls.push({ method, path, token: "checks" });
    if (headChecks instanceof Error) {
      throw headChecks;
    }
    if (path === `/repos/${REPO}/actions/workflows/pr-require-checks.yml/runs?head_sha=${HEAD}&per_page=100`) {
      return { workflow_runs: REQUIRED_SUITES.map((id) => ({ id: id * 10, check_suite_id: id })) };
    }
    assert.equal(path, `/repos/${REPO}/commits/${HEAD}/check-runs?filter=all&per_page=100&page=1`);
    return { check_runs: headChecks };
  };
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
      return path.endsWith("page=1") ? numbers.map((number) => ({ number, pull_request: {}, labels: [{ name: "needs-human" }] })) : [];
    }
    const [, kind, number] = /^\/repos\/[^/]+\/[^/]+\/(issues|pulls)\/(\d+)(?:\/timeline)?$/.exec(route) ?? [];
    if (method === "GET" && kind === "issues" && route.endsWith("/timeline") && numbers.includes(Number(number))) {
      return path.endsWith("page=1") ? timeline : [];
    }
    if (method === "GET" && kind === "pulls" && numbers.includes(Number(number))) {
      return { number: Number(number), state: "open", user: author, base: { ref: "main", sha: MAIN }, head: { sha: HEAD }, labels: [{ name: "needs-human" }], mergeable };
    }
    if (method === "GET" && route === `/repos/${REPO}/compare/${HEAD}...${MAIN}`) {
      return { files: mainFiles };
    }
    if (method === "GET" && route === `/repos/${REPO}/pulls/7/files`) {
      return path.endsWith("page=1") ? pullFiles : [];
    }
    const [, thread, kindOf] = /^\/repos\/[^/]+\/[^/]+\/pulls\/(\d+)\/(comments|reviews)(?:\?since=[^&]*)?$/.exec(route) ?? [];
    if (method === "GET" && numbers.includes(Number(thread))) {
      if (threadsFail === kindOf) {
        throw new Error(`GET ${path}: 502`);
      }
      const page = Number(/page=(\d+)$/.exec(path)[1]);
      return (kindOf === "comments" ? reviewComments : reviews).slice((page - 1) * 100, page * 100);
    }
    if (method === "POST" || method === "DELETE") {
      return null;
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { github, checks, verify, reads, calls, writes: () => calls.filter((call) => call.method !== "GET") };
}

const run = async (w, env = {}) => {
  const logs = [];
  const original = console.log;
  console.log = (line) => logs.push(line);
  try {
    return { code: await main({ env: { ...ENV, ...env }, github: w.github, checks: w.checks, verify: w.verify }), logs };
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

// GitHub's timeline carries no event for a reply inside an existing review
// thread: on #10526 and #10533 every reply-only review a person submitted is
// absent from issues/<n>/timeline (no `reviewed`, no `line-commented`), while
// pulls/<n>/comments lists the reply and pulls/<n>/reviews its review.
const BOT_THREAD = { id: 101, user: ACTIONS_BOT, body: "Finding.", pull_request_review_id: 201, created_at: "2026-10-18T09:00:00Z", updated_at: "2026-10-18T09:00:00Z" };
const reply = (user, at, updatedAt = at) => ({ id: 102, user, body: "Wait on this.", pull_request_review_id: 202, in_reply_to_id: 101, created_at: at, updated_at: updatedAt });
const BOT_REVIEW = { id: 201, user: ACTIONS_BOT, state: "COMMENTED", body: "**claude-review**: 1 inline finding(s)", submitted_at: "2026-10-18T09:00:00Z" };
const replyReview = (user, at) => ({ id: 202, user, state: "COMMENTED", body: "", submitted_at: at });

test("a person's reply inside a bot's review thread after the label keeps it, though the timeline shows none", async () => {
  const w = world({
    timeline: [reviewed(ACTIONS_BOT, "2026-10-18T09:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z"), escalated()],
    reviewComments: [BOT_THREAD, reply(OWNER, "2026-10-18T12:00:00Z")],
    reviews: [BOT_REVIEW, replyReview(OWNER, "2026-10-18T12:00:00Z")],
  });
  const { logs } = await run(w);
  assert.deepEqual(w.writes(), []);
  assert.ok(logs.includes("clear-escalations: #7 kept: kyle-sexton commented or reviewed after needs-human went on"), logs.join("\n"));
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

// escalation-routes.json now ends these in a failing status, not a person.
// A fix-ci label an older lane run set comes off while the head's own CI
// checks read failed. Any other stays on for a person, on the head the lane
// stopped on and on a new one alike: a lane posts a pr-unblock/* status on a
// head only when it stops there or clears its own failure, so a new head
// carries nothing that proves the cause gone or fails it in the label's place.
test("a label for a reason now routed to a failing status: fix-ci comes off on a red head, others stay after the head moves", async () => {
  for (const reason of ["ci-fix-escalated", "ci-fix-round-cap"]) {
    const atHead = commented(BOT, escalationBody(reason).replaceAll(KEY, HEAD), "2026-10-18T10:00:05Z");
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), atHead], headChecks: RED });
    await run(w);
    assert.equal(w.writes().at(-1)?.method, "DELETE", reason);
    assert.match(w.writes()[0].body.body, new RegExp(`\`${reason}\``));
  }
  const others = Object.keys(ROUTES).filter((reason) => escalationRoute(reason) === "fail" && escalationActivity(reason) !== "fix-ci" && reason !== "unresolved-conflict");
  assert.ok(others.includes("feedback-not-landed") && others.includes("unexpected-path-staged"));
  assert.ok(!others.some((reason) => escalationActivity(reason) === "review-dependency"), "every review-dependency stop holds for a person");
  for (const reason of others) {
    const atHead = commented(BOT, escalationBody(reason).replaceAll(KEY, HEAD), "2026-10-18T10:00:05Z");
    const same = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), atHead], headChecks: RED });
    await run(same);
    assert.deepEqual(same.writes(), [], `${reason} on the head it stopped on`);
    const moved = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(reason)], headChecks: RED });
    const { logs } = await run(moved);
    assert.deepEqual(moved.writes(), [], `${reason} after the head moved`);
    assert.ok(logs.some((line) => line.includes("one a person decides")), reason);
  }
});

// The security finding on #10252: a fix-ci label came off with no CI result
// read. Only a failed GitHub Actions check on the current head other than
// ci-status clears it; ci-status itself fails on the label, so it is skipped.
test("a fix-ci label comes off only while the head's own checks read failed", async () => {
  const timeline = [labeled(BOT, "2026-10-18T10:00:00Z"), escalated("ci-fix-escalated")];
  for (const [label, headChecks, cleared] of [
    ["red", RED, true],
    ["timed out", [check("test-bash (1/4)", "timed_out")], true],
    // ci-status reads a cancelled lane job as red, so it stays red without the label.
    ["cancelled", [check("test-node", "cancelled")], true],
    ["green", [check("test-node", "success"), check("lint", "success", { id: 2 })], false],
    ["only ci-status red", [check("ci-status", "failure"), check("test-node", "success", { id: 2 })], false],
    ["a skip", [check("test-node", "skipped")], false],
    ["no checks", [], false],
    ["another app's failure", [check("test-node", "failure", { slug: "someone-else" })], false],
    ["read fails", new Error("HTTP 502"), false],
    // An advisory lane is no pr-require-checks lane: ci-status would go green.
    ["only pr-test-windows red", [check("test-windows", "failure", { suite: 900 }), check("test-node", "success", { id: 2 })], false],
    // A contract-only run's later skip does not hide the real run's failure.
    ["a failed lane with a newer skipped duplicate", [check("test-node", "failure"), check("test-node", "skipped", { id: 2, suite: 501 })], true],
  ]) {
    const w = world({ timeline, headChecks });
    const { code } = await run(w);
    assert.equal(code, 0, label);
    assert.equal(w.writes().at(-1)?.method === "DELETE", cleared, label);
    assert.ok(w.calls.filter((call) => call.token === "checks").length <= 2, label);
  }
});

test("a reason still held for a person keeps the label beside a fail-routed one", async () => {
  for (const reason of ["feedback-uncertain", "feedback-question-security", "dependency-escalate", "dependency-security-close", "ci-fix-protected-path"]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(reason), escalated("ci-fix-escalated", { at: "2026-10-18T10:05:00Z" })] });
    await run(w);
    assert.deepEqual(w.writes(), [], reason);
  }
});

test("report-escalation.sh's lane-stopped comment since the label is the lane's own, not another marker", async () => {
  const w = world({
    timeline: [
      labeled(BOT, "2026-10-18T10:00:00Z"),
      escalated(),
      commented(BOT, "<!-- pr-unblock:lane-stopped activity=fix-ci -->\nStopped.", "2026-10-18T09:00:00Z", "2026-10-18T10:30:00Z"),
    ],
  });
  await run(w);
  assert.equal(w.writes().at(-1)?.method, "DELETE");
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

// Under merge.lane-prs native, enable-auto-merge judges the new head
// once the label is off and labels it again only for a cause a person must
// clear, so the label comes off under native as under gate.
test("a pr-merge escalation at an old head comes off under lane-prs native and gate alike", async () => {
  for (const [lanePrs, author] of [["native", BOT], ["gate", BOT], ["native", OWNER]]) {
    const w = world({ timeline: mergeEscalated(riskBody(OLD)), author });
    await run(w, { LANE_PRS: lanePrs });
    assert.equal(w.writes().length, 2, lanePrs);
    assert.equal(w.writes()[1].method, "DELETE", lanePrs);
  }
  // At the current head it stays.
  const current = world({ timeline: mergeEscalated(riskBody(HEAD)), author: BOT });
  await run(current, { LANE_PRS: "native" });
  assert.deepEqual(current.writes(), []);
});

// enable-auto-merge puts a missing label back under its standing escalation
// comment with no new comment: that label is still pr-merge's.
test("a label put back under pr-merge's standing escalation comment is pr-merge's", async () => {
  const escalation = `<!-- work-items:escalation lane=pr-merge kind=escalated -->\n${riskBody(OLD)}`;
  const relabeled = [commented(BOT, escalation, "2026-10-18T08:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z")];
  const w = world({ timeline: relabeled, author: BOT });
  await run(w, { LANE_PRS: "native" });
  assert.equal(w.writes().length, 2);
  // Without the escalation line, an old comment pairs with no label.
  const unpaired = world({ timeline: [commented(BOT, riskBody(OLD), "2026-10-18T08:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z")], author: BOT });
  await run(unpaired, { LANE_PRS: "native" });
  assert.deepEqual(unpaired.writes(), []);
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
// the PR still has. Reader answers use babysit_verify_evidence.py's own
// constants (FAIL, MISSING, UNREADABLE, the `unreadable:` reviews answer).
const UNBOUND = "pr-merge's gate holds it on its risk score (evidence-unbound:claude-review: not bound: rerun-not-allowed)";
const SECURITY = "pr-merge's gate holds it on its risk score (security-finding: 1 open CRITICAL finding)";
const REPEATED = "pr-merge's gate refuses its verifier verdict (verify:repeated-fail)";
const TOO_OLD = "pr-merge's gate refuses its verifier verdict (verify:too-old)";
const UNTRUSTED = "pr-merge's lane does not take its issue link (untrusted-provenance)";
const UNTRUSTED_SPEC = "pr-merge's gate refuses its verifier verdict (verify:untrusted-spec)";
const COST = "pr-merge's gate holds it on its risk score (cost-review-required: infra/main.tf)";
// Labels enable-auto-merge set before #9826 made these lane causes.
const SPEC_CHANGED = "pr-merge's gate refuses its verifier verdict (verify:spec-changed)";
const NATIVE = { LANE_PRS: "native" };
const nativeEscalated = (reason, head = HEAD) => mergeEscalated(refusalBody(true, reason, head, "needs-human"));
const clean = (pull) => ({ head: pull.headRefOid, refusal: null, ineligible: null, reviews: null });
const refusing = (refusal) => (pull) => ({ head: pull.headRefOid, refusal, ineligible: null });
const risk = (codes) => `pr-merge's gate holds it on its risk score (${codes})`;
const reviewsNow = (reviews) => (pull) => ({ ...clean(pull), reviews });
// The reader's early answer for a link it does not take: no verdict, no risk score.
const ineligible = (why) => (pull) => ({ head: pull.headRefOid, refusal: "verify:ineligible", ineligible: why });
const DELETE = { method: "DELETE", path: `/repos/${REPO}/issues/7/labels/needs-human`, body: undefined };

test("enable-auto-merge's label at the current head comes off once the gate's reader no longer refuses there", async () => {
  const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence: clean });
  const { code, logs } = await run(w, NATIVE);
  assert.equal(code, 0, logs.join("\n"));
  assert.deepEqual(w.reads, [{ pull: { number: 7, headRefOid: HEAD, baseRefOid: MAIN }, rung: "C3" }]);
  const [comment, removal] = w.writes();
  assert.equal(w.writes().length, 2);
  assert.equal(comment.body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=refusal-cleared head=${HEAD} -->`);
  assert.match(comment.body.body, new RegExp(`\`${HEAD}\``));
  assert.deepEqual(removal, DELETE);
});

test("enable-auto-merge's label comes off when the reader now reads a refusal the lanes clear for the same cause", async () => {
  for (const [reason, evidence] of [
    // A lane-class verifier label: any verdict the lanes clear, read whole.
    [SPEC_CHANGED, refusing("verify:fail")],
    [SPEC_CHANGED, refusing("verify:earlier-fail")],
    // A risk label: a risk score read whole, now naming only lane causes.
    [UNBOUND, (pull) => ({ ...clean(pull), reviews: "evidence-unbound:claude-review: not bound: rerun-allowed" })],
    // A lane verdict now passes, and the risk score it hid names only lane causes.
    [SPEC_CHANGED, reviewsNow("evidence-unbound:claude-review: not bound: rerun-allowed")],
    // Owner rule 2026-10-27: the repeated-FAIL cap and an old pull request
    // hold for the lanes, so their labels come off at the head where the
    // reader still refuses them (#10134's shape).
    [REPEATED, refusing("verify:repeated-fail")],
    [TOO_OLD, refusing("verify:too-old")],
  ]) {
    const w = world({ timeline: nativeEscalated(reason), author: BOT, evidence });
    await run(w, NATIVE);
    assert.deepEqual(w.writes().at(-1), DELETE, `${reason} ${evidence}`);
  }
});

// Owner decision Q-CLEAR B: a label whose recorded cause is a person's is
// never lifted at the head it was raised at, whatever the reader answers; a
// person removes it, or a push clears it as head-moved. It is not read.
const PERSON_CLASS = [
  SECURITY,
  risk("trust-gate:trusted-actors: widens the trusted actors"),
  COST,
  risk("high-path:**: a symlink"),
  risk("high-path:.github/workflows/**: .github/workflows/ci.yml"),
  UNTRUSTED_SPEC,
  UNTRUSTED,
  // A link reason, the reader's own unread link included.
  "pr-merge's lane does not take its issue link (unreadable: timed out)",
  // Off the lane list: one the reader always pairs with a link answer.
  "pr-merge's gate refuses its verifier verdict (verify:ineligible)",
  // A code not known to be a lane's, matched whole, or a person's beside a lane's.
  risk("a-new-code: x"),
  risk("files-incomplete-x: d"),
  "pr-merge's gate refuses its verifier verdict (verify:fail-x)",
  risk("evidence-unbound:claude-review: not bound: x; security-finding: 1 open"),
];

test("a person-class label is never removed at its head, even when nothing refuses", async () => {
  for (const reason of PERSON_CLASS) {
    for (const evidence of [clean, reviewsNow("evidence-unbound:claude-review: not bound: rerun-allowed"), refusing("verify:fail")]) {
      const w = world({ timeline: nativeEscalated(reason), author: BOT, evidence });
      const { code, logs } = await run(w, NATIVE);
      assert.equal(code, 0, `${reason}\n${logs.join("\n")}`);
      assert.deepEqual(w.reads, [], reason);
      assert.deepEqual(w.writes(), [], reason);
      assert.match(logs.join("\n"), /one a person clears/, reason);
    }
  }
});

test("a lane-class label comes off at its head once nothing refuses", async () => {
  for (const reason of [
    SPEC_CHANGED,
    "pr-merge's gate refuses its verifier verdict (verify:fail)",
    "pr-merge's gate refuses its verifier verdict (verify:earlier-fail)",
    UNBOUND,
    risk("files-incomplete: the changed-file listing did not read whole"),
    risk("manifest-review-required: plugins/x/.claude-plugin/plugin.json"),
  ]) {
    const w = world({ timeline: nativeEscalated(reason), author: BOT, evidence: clean });
    const { code, logs } = await run(w, NATIVE);
    assert.equal(code, 0, logs.join("\n"));
    assert.equal(w.reads.length, 1, reason);
    assert.equal(w.writes()[0].body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=refusal-cleared head=${HEAD} -->`, reason);
    assert.deepEqual(w.writes()[1], DELETE, reason);
  }
});

// A risk score is read only when the verdict passes (babysit_verify_evidence.py
// `evidence`), so a refusal or an unread answer hides a lane's recorded cause:
// the label stays.
test("a lane-class label stays when the reader's answer no longer shows its cause", async () => {
  for (const [reason, evidence] of [
    [SPEC_CHANGED, refusing("verify:unreadable")],
    [SPEC_CHANGED, refusing("verify:missing")],
    [UNBOUND, reviewsNow("unreadable: no agent identity")],
    [SPEC_CHANGED, reviewsNow("unreadable: no agent identity")],
    [UNBOUND, refusing("verify:fail")],
    [SPEC_CHANGED, ineligible("not-agent-ready")],
    // A lane cause recorded never lifts a person's now.
    [risk("files-incomplete: the listing did not read whole"), reviewsNow("high-path:infra/**: infra/main.tf")],
    [UNBOUND, reviewsNow("security-finding: 1 open CRITICAL finding")],
    [SPEC_CHANGED, refusing("verify:untrusted-spec")],
  ]) {
    const w = world({ timeline: nativeEscalated(reason), author: BOT, evidence });
    await run(w, NATIVE);
    assert.equal(w.reads.length, 1, `${reason} ${evidence}`);
    assert.deepEqual(w.writes(), [], `${reason} ${evidence}`);
  }
});

test("enable-auto-merge's label stays while its cause, or another a person must clear, holds at the head", async () => {
  for (const evidence of [
    // A security finding or a trusted-actor widening stays a person's.
    (pull) => ({ ...clean(pull), reviews: "security-finding: 1 open CRITICAL finding" }),
    (pull) => ({ ...clean(pull), reviews: "trust-gate:trusted-actors: widens the trusted actors" }),
    // A verifier refusal a person must clear, an issue link the trust hold refuses.
    refusing("verify:untrusted-spec"),
    ineligible("untrusted-provenance"),
    // Unread, read at another head, or a read that fails.
    () => null,
    () => ({ ...clean({ headRefOid: OLD }) }),
    () => {
      throw new Error("babysit_verify_evidence.py exited 1");
    },
  ]) {
    const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence });
    const { code, logs } = await run(w, NATIVE);
    // Kept as a verdict, never a per-PR error: a null answer included.
    assert.equal(code, 0, `${evidence}\n${logs.join("\n")}`);
    assert.deepEqual(w.writes(), [], String(evidence));
  }
});

test("enable-auto-merge's hold-path or cost-path label is never judged on the reader's answer", async () => {
  for (const reason of ["it changes .github/workflows/ci.yml, a hold path", "it changes infra/main.ts, a cost path"]) {
    const w = world({ timeline: nativeEscalated(reason), author: BOT, evidence: clean });
    await run(w, NATIVE);
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
    await run(w, NATIVE);
    assert.deepEqual(w.writes(), []);
    assert.deepEqual(w.reads, []);
  }
});

test("a pr-merge person comment not in enable-auto-merge's exact shape, or edited since, is not re-judged", async () => {
  const body = refusalBody(true, UNBOUND, HEAD, "needs-human");
  for (const timeline of [
    mergeEscalated(`${body}\nedited`),
    [commented(BOT, body, "2026-10-18T09:00:00Z", "2026-10-18T09:59:58Z"), labeled(BOT, "2026-10-18T10:00:00Z")],
  ]) {
    const w = world({ timeline, author: BOT, evidence: clean });
    await run(w, NATIVE);
    assert.deepEqual(w.writes(), []);
    assert.deepEqual(w.reads, []);
  }
});

// Main's head-moved rule (#9826): no read; enable-auto-merge judges the new
// head and labels it again only for a cause a person must clear.
test("enable-auto-merge's refusal at an old head comes off as head-moved without a read", async () => {
  const w = world({ timeline: nativeEscalated(SECURITY, OLD), author: BOT, evidence: clean });
  await run(w, NATIVE);
  assert.deepEqual(w.reads, []);
  assert.equal(w.writes()[0].body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=head-moved head=${HEAD} -->`);
  assert.deepEqual(w.writes()[1], DELETE);
});

test("enable-auto-merge's comment on a pull request a person opened is not read", async () => {
  const w = world({ timeline: nativeEscalated(UNBOUND), author: OWNER, evidence: clean });
  await run(w, NATIVE);
  assert.deepEqual(w.reads, []);
  assert.deepEqual(w.writes(), []);
});

test("enable-auto-merge's comment beside another pr-merge escalation is not read", async () => {
  for (const other of [verifyBody(HEAD), sharedCopyBody(HEAD)]) {
    const timeline = [commented(BOT, other, "2026-10-18T09:59:50Z"), ...nativeEscalated(UNBOUND)];
    const w = world({ timeline, author: BOT, evidence: clean });
    await run(w, NATIVE);
    assert.deepEqual(w.reads, [], other);
    assert.deepEqual(w.writes(), [], other);
  }
});

test("another pr-merge escalation alone at the head is not read as enable-auto-merge's", async () => {
  for (const other of [verifyBody(HEAD), sharedCopyBody(HEAD)]) {
    const w = world({ timeline: mergeEscalated(other), author: BOT, evidence: clean });
    const { code, logs } = await run(w, NATIVE);
    assert.equal(code, 0, logs.join("\n"));
    assert.deepEqual(w.reads, [], other);
    assert.deepEqual(w.writes(), [], other);
  }
});

test("enable-auto-merge's comment is not read under merge.lane-prs gate", async () => {
  for (const env of [{ LANE_PRS: "gate" }, {}]) {
    const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence: clean });
    await run(w, env);
    assert.deepEqual(w.reads, [], JSON.stringify(env));
    assert.deepEqual(w.writes(), [], JSON.stringify(env));
  }
});

// enable-auto-merge puts the label back under its standing comment after
// this script took it off; the put-back is judged again like the first.
test("a label enable-auto-merge put back after this script cleared it is judged again", async () => {
  const timeline = [
    ...nativeEscalated(UNBOUND),
    commented(BOT, `<!-- pr-pipeline needs-human-cleared reason=refusal-cleared head=${HEAD} -->\ncleared`, "2026-10-18T11:00:00Z"),
    unlabeled(BOT, "2026-10-18T11:00:01Z"),
    labeled(BOT, "2026-10-18T12:00:00Z"),
  ];
  const kept = world({ timeline, author: BOT, evidence: (pull) => ({ ...clean(pull), reviews: "security-finding: 1 open CRITICAL finding" }) });
  await run(kept, NATIVE);
  assert.equal(kept.reads.length, 1);
  assert.deepEqual(kept.writes(), []);
  const gone = world({ timeline, author: BOT, evidence: clean });
  await run(gone, NATIVE);
  assert.equal(gone.writes().length, 2);
  assert.deepEqual(gone.writes()[1], DELETE);
});

test("at most NATIVE_READS_PER_RUN reader runs a run", async () => {
  const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence: () => null });
  const held = Array.from({ length: NATIVE_READS_PER_RUN + 2 }, (_, i) => ({ number: 7, pull_request: {}, i }));
  const github = async (method, path, body) => (method === "GET" && path.includes("issues?state=open") ? (path.endsWith("page=1") ? held : []) : w.github(method, path, body));
  const { logs } = await run({ ...w, github }, NATIVE);
  assert.equal(w.reads.length, NATIVE_READS_PER_RUN);
  assert.equal(logs.filter((line) => /reader runs this run/.test(line)).length, 2);
});

// More labels held for a person than reads a run: the start moves with the
// run number, so each one is read within as many runs as there are labels.
test("labels past the read cap are read on a later run", async () => {
  const numbers = Array.from({ length: NATIVE_READS_PER_RUN + 1 }, (_, i) => 7 + i);
  const read = new Set();
  for (let runNumber = 1; runNumber <= numbers.length; runNumber += 1) {
    const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence: reviewsNow("unreadable: no agent identity"), numbers });
    await run(w, { ...NATIVE, GITHUB_RUN_NUMBER: String(runNumber) });
    assert.equal(w.reads.length, NATIVE_READS_PER_RUN);
    for (const { pull } of w.reads) {
      read.add(pull.number);
    }
  }
  assert.deepEqual([...read].sort((a, b) => a - b), numbers);
});

const threadReads = (w) => w.calls.filter((call) => /\/pulls\/7\/(comments|reviews)/.test(call.path));
const inlineTimeline = () => [reviewed(ACTIONS_BOT, "2026-10-18T09:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z"), escalated()];

test("a person's inline reply after a pr-merge label keeps it from coming off as head-moved", async () => {
  const w = world({ timeline: mergeEscalated(verifyBody(OLD)), reviewComments: [BOT_THREAD, reply(OWNER, "2026-10-18T12:00:00Z")] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a person's review submitted after the label keeps it, with no review comment", async () => {
  const w = world({ timeline: inlineTimeline(), reviews: [BOT_REVIEW, { ...replyReview(OWNER, "2026-10-18T12:00:00Z"), body: "Wait for me." }] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("a person's review comment edited after the label keeps it; one written and left before it does not", async () => {
  const edited = world({ timeline: inlineTimeline(), reviewComments: [reply(OWNER, "2026-10-18T09:30:00Z", "2026-10-18T12:00:00Z")] });
  await run(edited);
  assert.deepEqual(edited.writes(), []);
  const before = world({ timeline: inlineTimeline(), reviewComments: [reply(OWNER, "2026-10-18T09:30:00Z")], reviews: [replyReview(OWNER, "2026-10-18T09:30:00Z")] });
  await run(before);
  assert.equal(before.writes().at(-1)?.method, "DELETE");
});

test("a bot's inline reply or review after the label does not keep it", async () => {
  const w = world({
    timeline: inlineTimeline(),
    reviewComments: [BOT_THREAD, reply(CODEX_BOT, "2026-10-18T12:00:00Z")],
    reviews: [BOT_REVIEW, replyReview(CLAUDE_BOT, "2026-10-18T12:00:00Z")],
  });
  await run(w);
  assert.equal(w.writes().at(-1)?.method, "DELETE");
});

test("an inline reply by an unknown author, or at a time that does not parse, keeps it", async () => {
  for (const spoke of [reply(null, "2026-10-18T12:00:00Z"), reply(OWNER, "not a time")]) {
    const w = world({ timeline: inlineTimeline(), reviewComments: [spoke] });
    await run(w);
    assert.deepEqual(w.writes(), [], JSON.stringify(spoke.user));
  }
});

test("a failed review comment or review read keeps the label", async () => {
  for (const kind of ["comments", "reviews"]) {
    const w = world({ timeline: inlineTimeline(), threadsFail: kind });
    const { code } = await run(w);
    assert.equal(code, 1, kind);
    assert.deepEqual(w.writes(), [], kind);
  }
});

test("the thread reads run once each, since the label, and only when the timeline alone would clear", async () => {
  const clears = world({ timeline: inlineTimeline() });
  await run(clears);
  assert.deepEqual(
    threadReads(clears).map((call) => call.path),
    [`/repos/${REPO}/pulls/7/comments?since=2026-10-18T10:00:00Z&per_page=100&page=1`, `/repos/${REPO}/pulls/7/reviews?per_page=100&page=1`],
  );
  const spoke = world({ timeline: [...inlineTimeline(), commented(OWNER, "Wait.", "2026-10-18T12:00:00Z")] });
  await run(spoke);
  assert.deepEqual(threadReads(spoke), []);
  const holds = world({ timeline: inlineTimeline(), mainFiles: [{ filename: ".github/workflows/ci.yml" }] });
  await run(holds);
  assert.deepEqual(threadReads(holds), []);
});

test("a workflow-staged keep line names main's SHA and the first workflow file it changes", async () => {
  for (const [file, named] of [
    [{ filename: ".github/workflows/pr-merge.yml" }, ".github/workflows/pr-merge.yml"],
    [{ filename: "docs/old.yml", previous_filename: ".github/workflows/old.yml" }, ".github/workflows/old.yml"],
  ]) {
    const w = world({ timeline: inlineTimeline(), mainFiles: [{ filename: "README.md" }, file, { filename: ".github/workflows/later.yml" }] });
    const { logs } = await run(w);
    assert.ok(logs.includes(`clear-escalations: #7 kept: workflow-staged still holds at ${HEAD}: main ${MAIN} changes ${named}`), logs.join("\n"));
  }
  const cut = world({ timeline: inlineTimeline(), mainFiles: Array.from({ length: 300 }, (_, i) => ({ filename: `f${i}` })) });
  const { logs } = await run(cut);
  assert.ok(logs.includes(`clear-escalations: #7 kept: workflow-staged still holds at ${HEAD}: main ${MAIN}'s file listing against it may be cut short`), logs.join("\n"));
});

test("a person's reply or review on the second page of either listing keeps it", async () => {
  const botComments = Array.from({ length: 100 }, (_, i) => ({ ...BOT_THREAD, id: 1000 + i, created_at: "2026-10-18T11:00:00Z", updated_at: "2026-10-18T11:00:00Z" }));
  const botReviews = Array.from({ length: 100 }, (_, i) => ({ ...BOT_REVIEW, id: 2000 + i, submitted_at: "2026-10-18T11:00:00Z" }));
  for (const [reviewComments, reviews, which] of [
    [[...botComments, reply(OWNER, "2026-10-18T12:00:00Z")], botReviews, "comments"],
    [botComments, [...botReviews, replyReview(OWNER, "2026-10-18T12:00:00Z")], "reviews"],
  ]) {
    const w = world({ timeline: inlineTimeline(), reviewComments, reviews });
    await run(w);
    assert.deepEqual(w.writes(), [], which);
    assert.ok(threadReads(w).some((call) => call.path.includes(`/${which}`) && call.path.endsWith("page=2")), which);
  }
});

test("a person's inline reply keeps enable-auto-merge's label without spending a reader run", async () => {
  const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence: clean, reviewComments: [BOT_THREAD, reply(OWNER, "2026-10-18T12:00:00Z")] });
  const { logs } = await run(w, NATIVE);
  assert.deepEqual(w.writes(), []);
  assert.deepEqual(w.reads, []);
  assert.ok(logs.includes("clear-escalations: #7 kept: kyle-sexton commented or reviewed after needs-human went on"), logs.join("\n"));
});

test("a refusal cleared by the reader reads the review threads once", async () => {
  const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence: clean });
  await run(w, NATIVE);
  assert.deepEqual(w.writes().at(-1), DELETE);
  assert.equal(threadReads(w).length, 2);
});

test("a person's comment written before the label and edited after it, or in the label's own second, keeps it", async () => {
  for (const spoke of [
    commented(OWNER, "Looks fine. Edit: wait for me.", "2026-10-18T09:00:00Z", "2026-10-18T12:00:00Z"),
    commented(OWNER, "Wait.", "2026-10-18T10:00:00Z"),
  ]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), spoke] });
    await run(w);
    assert.deepEqual(w.writes(), [], spoke.body);
  }
});
