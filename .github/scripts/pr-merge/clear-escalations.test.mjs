// Expected values come from the needs-human recheck acceptance criteria and report-escalation.sh's
// comment format: an App-set needs-human on a PR escalated as workflow-staged
// comes off within one sweep once main stages no .github/workflows/ change into
// the head, with one comment naming the reason and the head; a label a person
// set, a reason that still holds, a label a person added back, a marker a
// person wrote, and a person speaking after the escalation all keep it. Per the
// owner decision on #8387, a bot account speaking after the label (AI review,
// another lane) does not keep it.
import assert from "node:assert/strict";
import { after, test } from "node:test";

import { main, NATIVE_READS_PER_RUN, SESSION_CHECKS_PER_RUN } from "./clear-escalations.mjs";
import { refusalBody } from "./enable-auto-merge.mjs";
import { escalationActivity, escalationRoute, ROUTES } from "../pr-unblock/escalation-routes.mjs";
import { CREDENTIAL_HOLD, SIGNED_COMMITS_HOLD } from "../pr-unblock/gate-source.mjs";

const REPO = "melodic-software/claude-code-plugins";
const BOT = { login: "melodic-automation-lanes[bot]", type: "Bot" };
const OWNER = { login: "kyle-sexton", id: 153232337, type: "User" };
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
// `reviewThreads` is the GraphQL reviewThreads page answered for a cursor.
const threadPage = (nodes, hasNextPage = false) => ({ nodes, pageInfo: { hasNextPage, endCursor: hasNextPage ? "next" : null } });
function world({ timeline, mainFiles = [{ filename: "README.md" }], mergeable = false, pullFiles = [], reviewComments = [], reviews = [], threadsFail = false, reviewThreads = () => threadPage([]), author, headChecks = [], evidence = () => null, numbers = [7], headRepo = REPO, reader, listed = ["needs-human"], labels = ["needs-human"], sessionNumbers = [], statuses = [], keyStatuses = [] }) {
  const calls = [];
  const known = (number) => numbers.includes(number) || sessionNumbers.includes(number);
  const checks = async (method, path) => {
    calls.push({ method, path, token: "checks" });
    // `statuses` is the HEAD's REST statuses, newest first, or an Error;
    // `keyStatuses` the KEY's, an older head a lane stopped on.
    const statusHead = new RegExp(`^/repos/${REPO}/commits/([0-9a-f]{40})/statuses\\?`).exec(path)?.[1];
    if (statusHead === HEAD || statusHead === KEY) {
      const rows = statusHead === HEAD ? statuses : keyStatuses;
      if (rows instanceof Error) {
        throw rows;
      }
      return path.endsWith("page=1") ? rows : [];
    }
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
      return path.endsWith("page=1") ? numbers.map((number) => ({ number, pull_request: {}, labels: listed.map((name) => ({ name })) })) : [];
    }
    if (method === "GET" && route === `/repos/${REPO}/issues?state=open&labels=needs-session`) {
      return path.endsWith("page=1") ? sessionNumbers.map((number) => ({ number, pull_request: {}, labels: [{ name: "needs-session" }] })) : [];
    }
    const [, kind, number] = /^\/repos\/[^/]+\/[^/]+\/(issues|pulls)\/(\d+)(?:\/timeline)?$/.exec(route) ?? [];
    if (method === "GET" && kind === "issues" && route.endsWith("/timeline") && known(Number(number))) {
      return path.endsWith("page=1") ? timeline : [];
    }
    if (method === "GET" && kind === "pulls" && known(Number(number))) {
      return { number: Number(number), state: "open", user: author, base: { ref: "main", sha: MAIN }, head: { sha: HEAD, ref: "feat/x", repo: { full_name: headRepo } }, labels: labels.map((name) => ({ name })), mergeable };
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
    if (method === "POST" && path === "/graphql") {
      assert.deepEqual({ ...body.variables, after: undefined }, { owner: "melodic-software", name: "claude-code-plugins", number: 7, after: undefined });
      return { data: { repository: { pullRequest: { reviewThreads: reviewThreads(body.variables.after) } } } };
    }
    if (method === "POST" || method === "DELETE") {
      return null;
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { github, checks, verify, reader, reads, calls, writes: () => calls.filter((call) => call.method !== "GET" && call.path !== "/graphql") };
}

const run = async (w, env = {}) => {
  const logs = [];
  const original = console.log;
  console.log = (line) => logs.push(line);
  try {
    return { code: await main({ env: { ...ENV, ...env }, github: w.github, checks: w.checks, verify: w.verify, reader: w.reader }), logs };
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

test("an App-set needs-human on an item flagged security: outside-actor is never removed", async () => {
  const flagged = ["needs-human", "security: outside-actor"];
  for (const [listed, labels] of [
    [flagged, flagged],
    [["needs-human"], flagged],
  ]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated()], listed, labels });
    const { code, logs } = await run(w);
    assert.equal(code, 0);
    assert.deepEqual(w.writes(), []);
    assert.ok(logs.some((line) => /#7 kept: .*security: outside-actor/.test(line)), logs.join("\n"));
  }
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
// unresolved-conflict, workflow-staged, protected-path-conflict,
// feedback-protected-path and feedback-not-landed keep their own check.
test("a label for a reason now routed to a failing status: fix-ci comes off on a red head, others stay after the head moves", async () => {
  for (const reason of ["ci-fix-escalated", "ci-fix-round-cap"]) {
    const atHead = commented(BOT, escalationBody(reason).replaceAll(KEY, HEAD), "2026-10-18T10:00:05Z");
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), atHead], headChecks: RED });
    await run(w);
    assert.equal(w.writes().at(-1)?.method, "DELETE", reason);
    assert.match(w.writes()[0].body.body, new RegExp(`\`${reason}\``));
  }
  const others = Object.keys(ROUTES).filter(
    (reason) =>
      escalationRoute(reason) === "fail" &&
      escalationActivity(reason) !== "fix-ci" &&
      !["unresolved-conflict", "workflow-staged", "protected-path-conflict", "feedback-protected-path", "feedback-not-landed"].includes(reason),
  );
  assert.ok(others.includes("feedback-untaken-threads") && others.includes("unexpected-path-staged"));
  assert.deepEqual(
    others.filter((reason) => escalationActivity(reason) === "review-dependency"),
    ["dependency-round-cap", "dependency-invalid", "dependency-fix-not-landed", "dependency-config-unreadable", "dependency-files-truncated", "dependency-control-uncited", "dependency-workflow-unpinned"],
    "only dependency-security-close, dependency-escalate and dependency-fix-refused hold for a person",
  );
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

// Per the owner decision of 2026-10-25, feedback-not-landed needs no person
// once the head moved off its resume key and no review thread the lane
// replied to is left unresolved, and, per the owner's later direction on the
// security finding, a trusted push moved it or both review lanes read the new
// head clean: a lanes App push alone never clears it (tests below the trusted
// move). GraphQL names the lanes App bot without the `[bot]` REST adds.
const LANE_AUTHOR = { __typename: "Bot", login: "melodic-automation-lanes" };
const PERSON_AUTHOR = { __typename: "User", login: "kyle-sexton" };
const reviewThread = (isResolved, authors, totalCount = authors.length) => ({ isResolved, comments: { totalCount, nodes: authors.map((author) => ({ author })) } });
const notLanded = (head = KEY) => commented(BOT, escalationBody("feedback-not-landed").replaceAll(KEY, head), "2026-10-18T10:00:05Z");

test("feedback-not-landed stays on the head the lane's fix did not reach", async () => {
  // Any feedback-not-landed key on the head keeps it, beside one that moved.
  const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), notLanded(), notLanded(HEAD)] });
  const { logs } = await run(w);
  assert.deepEqual(w.writes(), []);
  assert.ok(logs.some((line) => line.includes("feedback-not-landed still holds") && line.includes("did not reach")), logs.join("\n"));
  assert.ok(!w.calls.some((call) => call.path === "/graphql"));
});

test("feedback-not-landed stays while a review thread the lane replied to is unresolved", async () => {
  const w = world({
    timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), notLanded()],
    reviewThreads: (after) => (after === null ? threadPage([reviewThread(true, [LANE_AUTHOR])], true) : threadPage([reviewThread(false, [PERSON_AUTHOR, LANE_AUTHOR])])),
  });
  const { logs } = await run(w);
  assert.deepEqual(w.writes(), []);
  assert.ok(logs.some((line) => line.includes("1 unresolved review thread(s) carry a lanes App comment")), logs.join("\n"));
});

test("feedback-not-landed stays when its review thread listing may be cut short", async () => {
  for (const [label, reviewThreads] of [
    ["more pages than are read", () => threadPage([], true)],
    ["an open thread with more comments than listed", () => threadPage([reviewThread(false, [PERSON_AUTHOR], 101)])],
    ["a thread whose state did not read", () => threadPage([reviewThread(null, [PERSON_AUTHOR])])],
    ["no thread connection", () => null],
  ]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), notLanded()], reviewThreads });
    const { logs } = await run(w);
    assert.deepEqual(w.writes(), [], label);
    assert.ok(logs.some((line) => line.includes("may be cut short")), label);
  }
});

test("feedback-not-landed stays when a person spoke after the label, on the timeline or in a review thread", async () => {
  for (const [label, extra] of [
    ["timeline comment", { timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), notLanded(), commented(OWNER, "Leave this for me.", "2026-10-18T12:00:00Z")] }],
    ["thread reply", { timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), notLanded()], reviewComments: [BOT_THREAD, reply(OWNER, "2026-10-18T12:00:00Z")] }],
  ]) {
    const w = world(extra);
    const { logs } = await run(w);
    assert.deepEqual(w.writes(), [], label);
    assert.ok(logs.includes("clear-escalations: #7 kept: kyle-sexton commented or reviewed after needs-human went on"), label);
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
    ["only pr-test-platforms red", [check("test-windows", "failure", { suite: 900 }), check("test-node", "success", { id: 2 })], false],
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

// publish-feedback.mjs posts the round record and the model-run line after
// each address-feedback round on an escalated PR (gate-source.mjs knows both).
test("address-feedback's round record since the label is pr-unblock's own, not another marker", async () => {
  const round = commented(BOT, "<!-- pr-unblock:address-feedback-round -->\n<!-- pr-unblock:address-feedback-model-run 5000-1 -->\nRound 1.", "2026-10-18T10:30:00Z");
  const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), round] });
  await run(w);
  assert.equal(w.writes().at(-1)?.method, "DELETE");
  const odd = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), commented(BOT, "<!-- pr-unblock:address-feedback-model-run -->", "2026-10-18T10:30:00Z")] });
  await run(odd);
  assert.deepEqual(odd.writes(), [], "a model-run line with no run id");
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
  await run(w, { TRUSTED_ACTORS_PATH: TRUSTED });
  assert.equal(w.writes().at(-1)?.method, "DELETE");
});

// ci-status (pr-require-checks.yml, "Fail a review-lane hold an untrusted
// account lifted") accepts a lift only from a `human` of trusted-actors.json,
// and counts a review lane's own `labeled` event as a hold.
test("a review-lane hold an account off the trusted list unlabeled, or that the list does not read, keeps a later escalation", async () => {
  const timeline = [laneHold(ACTIONS_BOT, "2026-10-18T08:00:00Z"), unlabeled(STRANGER, "2026-10-18T09:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z"), escalated()];
  const w = world({ timeline });
  const { logs } = await run(w, { TRUSTED_ACTORS_PATH: TRUSTED });
  assert.deepEqual(w.writes(), []);
  assert.ok(logs.some((line) => line.includes("a review lane holds it: <!-- claude-lane-hold")), logs.join("\n"));
  const unread = world({ timeline: timeline.map((item) => (item.event === "unlabeled" ? unlabeled(OWNER, item.created_at) : item)) });
  await run(unread, { TRUSTED_ACTORS_PATH: "/nonexistent/trusted-actors.json" });
  assert.deepEqual(unread.writes(), [], "no trusted list");
});

test("a review lane's labeled event is a hold until a trusted person unlabels it", async () => {
  const held = world({ timeline: [labeled(ACTIONS_BOT, "2026-10-18T08:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z"), escalated()] });
  const { logs } = await run(held, { TRUSTED_ACTORS_PATH: TRUSTED });
  assert.deepEqual(held.writes(), []);
  assert.ok(logs.some((line) => line.includes("a review lane holds it: needs-human added by github-actions[bot]")), logs.join("\n"));
  const lifted = world({ timeline: [labeled(ACTIONS_BOT, "2026-10-18T08:00:00Z"), unlabeled(OWNER, "2026-10-18T09:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z"), escalated()] });
  await run(lifted, { TRUSTED_ACTORS_PATH: TRUSTED });
  assert.equal(lifted.writes().at(-1)?.method, "DELETE");
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

// check-signed-commits' escalation comment, as its report job posts it with
// GITHUB_TOKEN: SIGNED_COMMITS_HOLD on the first line. Its label write adds no
// `labeled` event when a lane escalation already put the label on.
const signedHold = (user, at, updatedAt = at) =>
  commented(user, `${SIGNED_COMMITS_HOLD}\nLane commit check: these commits are not GitHub-verified, so no lane continues on this pull request until a human reviews them.\n\n- \`${KEY}\``, at, updatedAt);

test("check-signed-commits' marked comment keeps the label a clearing pr-unblock escalation would take off", async () => {
  const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), signedHold(ACTIONS_BOT, "2026-10-18T11:00:00Z")] });
  const { logs } = await run(w);
  assert.deepEqual(w.writes(), []);
  assert.ok(logs.includes("clear-escalations: #7 kept: check-signed-commits holds it: a lane commit could not be verified"), logs.join("\n"));
});

test("check-signed-commits' marked comment keeps a pr-merge head-moved escalation too", async () => {
  const w = world({ timeline: [...mergeEscalated(verifyBody(OLD)), signedHold(ACTIONS_BOT, "2026-10-18T11:00:00Z")] });
  await run(w);
  assert.deepEqual(w.writes(), []);
});

test("an unmarked bot comment, or the marker from another account, does not keep the label", async () => {
  for (const spoke of [
    commented(ACTIONS_BOT, "Lane commit check: these commits are not GitHub-verified.", "2026-10-18T11:00:00Z"),
    signedHold(CODEX_BOT, "2026-10-18T11:00:00Z"),
  ]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), spoke] });
    await run(w);
    assert.equal(w.writes().at(-1)?.method, "DELETE", spoke.user.login);
  }
});

test("check-signed-commits' hold a person lifted by unlabeling no longer keeps a later escalation", async () => {
  const lifted = [signedHold(ACTIONS_BOT, "2026-10-18T08:00:00Z"), unlabeled(OWNER, "2026-10-18T09:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z"), escalated()];
  const w = world({ timeline: lifted });
  await run(w, { TRUSTED_ACTORS_PATH: TRUSTED });
  assert.equal(w.writes().at(-1)?.method, "DELETE");
  const edited = world({ timeline: [signedHold(ACTIONS_BOT, "2026-10-18T08:00:00Z", "2026-10-18T09:30:00Z"), ...lifted.slice(1)] });
  await run(edited);
  assert.deepEqual(edited.writes(), [], "edited after the unlabel");
});

// pr-verify's stop on a withheld fail, as verify-notes.mjs posts it with
// GITHUB_TOKEN under a label already on, which adds no `labeled` event.
const credentialHold = (user, at, updatedAt) => commented(user, `${CREDENTIAL_HOLD}\nReason: \`security\`\n\npr-verify withheld its fail at head \`${"a".repeat(40)}\`.`, at, updatedAt);

test("pr-verify's credential stop keeps the label a clearing escalation would take off, until a person lifts it", async () => {
  const held = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), credentialHold(ACTIONS_BOT, "2026-10-18T11:00:00Z")] });
  const { logs } = await run(held);
  assert.deepEqual(held.writes(), []);
  assert.ok(logs.includes("clear-escalations: #7 kept: pr-verify holds it for a credential, which a person lifts"), logs.join("\n"));
  const lifted = [credentialHold(ACTIONS_BOT, "2026-10-18T08:00:00Z"), unlabeled(OWNER, "2026-10-18T09:00:00Z"), labeled(BOT, "2026-10-18T10:00:00Z"), escalated()];
  const clear = world({ timeline: lifted });
  await run(clear, { TRUSTED_ACTORS_PATH: TRUSTED });
  assert.equal(clear.writes().at(-1)?.method, "DELETE", "a person lifted it");
  const forged = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(), credentialHold(OWNER, "2026-10-18T11:00:00Z")] });
  const { logs: forgedLogs } = await run(forged, { TRUSTED_ACTORS_PATH: TRUSTED });
  assert.ok(!forgedLogs.some((line) => line.includes("for a credential")), "the marker from a person is not the hold");
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

// The person refusal written out by hand, its reason lines as given: one line
// per reason before reasons wrapped, or a reason wrapped at 100 columns with
// two-space continuations. LONG_UNBOUND's ";" is its 99th column (the risk
// prefix is 44, then 17 + 37 + 1), so the wrap cuts right after "; " and the
// lane code after it is on the next line.
const handRefusal = (reasonLines, head = HEAD) =>
  [
    "<!-- work-items:escalation lane=pr-merge kind=escalated -->",
    "<!-- babysit-merge-risk -->",
    `Unattended merge: native auto-merge leaves this pull request unarmed at head \`${head}\`. A person must clear this reason, so the pr-merge lane added the \`needs-human\` label: fix the reason, then remove the label, and the next scheduled run judges it again.`,
    "",
    "```text",
    ...reasonLines,
    "```",
  ].join("\n");
const LONG_UNBOUND = `pr-merge's gate holds it on its risk score (evidence-unbound:${"a".repeat(37)}; files-incomplete)`;
const LONG_SECURITY = `pr-merge's gate holds it on its risk score (evidence-unbound:${"a".repeat(37)}; security-finding: 1 open CRITICAL finding)`;
const wrapAfterSemicolon = (reason) => [reason.slice(0, 99), `  ${reason.slice(100)}`];

test("enable-auto-merge's long refusal comes off in the old one-line format and the wrapped one", async () => {
  for (const body of [handRefusal([LONG_UNBOUND]), handRefusal(wrapAfterSemicolon(LONG_UNBOUND))]) {
    const w = world({ timeline: mergeEscalated(body), author: BOT, evidence: clean });
    const { logs } = await run(w, NATIVE);
    assert.deepEqual(w.writes().at(-1), DELETE, `${body}\n${logs.join("\n")}`);
  }
  // A person's code on the wrapped line still keeps the label.
  for (const body of [handRefusal([LONG_SECURITY]), handRefusal(wrapAfterSemicolon(LONG_SECURITY))]) {
    const w = world({ timeline: mergeEscalated(body), author: BOT, evidence: clean });
    await run(w, NATIVE);
    assert.deepEqual(w.writes(), [], body);
  }
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

// A trusted move: the head left every resume key through pushes the base
// trusted-actors.json lists as a `human` (never the lanes App's own entry),
// read with the job token (`reader`). Expected values come from the owner rule
// of 2026-10-26: a person is needed only for intent, design or a HIGH/CRITICAL
// security finding, so a mechanical stop comes off once trusted evidence shows
// its cause gone.
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PERSON_ID = 153232337;
const APP_ID = 337595936;
const STRANGER = { login: "drive-by", id: 99, type: "User" };
const PERSON = { login: "kyle-sexton", id: PERSON_ID, type: "User" };
const APP_ACTOR = { login: BOT.login, id: APP_ID, type: "Bot" };
const MAIN_THEN = "d".repeat(40);
const TRUSTED_DIR = mkdtempSync(join(tmpdir(), "clear-escalations-"));
after(() => rmSync(TRUSTED_DIR, { recursive: true, force: true }));
const TRUSTED = join(TRUSTED_DIR, "trusted-actors.json");
writeFileSync(
  TRUSTED,
  JSON.stringify({
    version: 1,
    actors: [
      { id: PERSON_ID, login: "kyle-sexton", kind: "human" },
      { id: APP_ID, login: BOT.login, kind: "bot" },
      { id: 209825114, login: "claude[bot]", kind: "bot" },
    ],
  }),
);
const TRUST_ENV = { TRUSTED_ACTORS_PATH: TRUSTED, BABYSIT_VERIFY_GH_TOKEN: "job-token" };

// The branch's activity, newest first: created before the label, then `pushes`
// ({ actor, after, at }) after it.
const activityOf = (pushes) => [
  ...pushes.map(({ actor, after, at }) => ({ activity_type: "push", actor, after, before: KEY, timestamp: at })).reverse(),
  { activity_type: "branch_creation", actor: PERSON, after: KEY, before: "0".repeat(40), timestamp: "2026-10-17T09:00:00Z" },
];
const pushedBy = (actor, after = HEAD, at = "2026-10-18T11:00:00Z") => ({ actor, after, at });
const run_ = (name, conclusion, id, status = "completed") => ({ id, name, status, conclusion, app: { slug: "github-actions" } });
const GREEN = [run_("ci-status", "failure", 1), run_("test-node", "success", 2), run_("lint-repo", "skipped", 3)];

const ACTIVITY = `/repos/${REPO}/activity?ref=${encodeURIComponent("refs/heads/feat/x")}&direction=desc&per_page=100`;

// The job-token reads: branch activity, main's tip when the lane escalated,
// whether the head contains it, and the head's check runs.
function readerFor({ pushes = [pushedBy(PERSON)], contains = true, checkRuns = GREEN, calls = [] } = {}) {
  return async (method, path) => {
    calls.push(path);
    if (method !== "GET") {
      throw new Error(`the reader writes nothing: ${method} ${path}`);
    }
    if (path === ACTIVITY) {
      return activityOf(pushes);
    }
    if (path === `/repos/${REPO}/commits?sha=main&until=${encodeURIComponent("2026-10-18T10:00:05.000Z")}&per_page=1`) {
      return [{ sha: MAIN_THEN }];
    }
    if (path === `/repos/${REPO}/compare/${MAIN_THEN}...${HEAD}`) {
      return contains ? { status: "ahead", behind_by: 0 } : { status: "diverged", behind_by: 3 };
    }
    if (path.startsWith(`/repos/${REPO}/commits/${HEAD}/check-runs?filter=all&per_page=100&page=`)) {
      return { check_runs: path.endsWith("page=1") ? checkRuns : [] };
    }
    throw new Error(`unexpected reader ${method} ${path}`);
  };
}

const WORKFLOW_MAIN = [{ filename: ".github/workflows/pr-merge.yml" }];
const stagedTimeline = () => [labeled(BOT, "2026-10-18T10:00:00Z"), escalated("workflow-staged")];

test("workflow-staged comes off once a trusted person moved the head past the resume key with main merged in, though main still changes workflows", async () => {
  const w = world({ timeline: stagedTimeline(), mainFiles: WORKFLOW_MAIN, reader: readerFor() });
  await run(w, TRUST_ENV);
  const [comment, removal] = w.writes();
  assert.equal(w.writes().length, 2);
  assert.equal(comment.body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=workflow-staged head=${HEAD} -->`);
  assert.match(comment.body.body, /kyle-sexton/);
  assert.match(comment.body.body, new RegExp(MAIN_THEN));
  assert.equal(removal.method, "DELETE");
});

test("a lanes App push is not a trusted move: the App never lifts its own stop with its own push", async () => {
  for (const pushes of [[pushedBy(APP_ACTOR)], [pushedBy(PERSON, "e".repeat(40), "2026-10-18T10:30:00Z"), pushedBy(APP_ACTOR)]]) {
    for (const reason of ["workflow-staged", "ci-fix-escalated"]) {
      const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(reason)], mainFiles: WORKFLOW_MAIN, reader: readerFor({ pushes }) });
      await run(w, TRUST_ENV);
      assert.deepEqual(w.writes(), [], `${reason} ${JSON.stringify(pushes)}`);
    }
  }
});

// feedback-not-landed after a push no trusted person made: the review lanes'
// runs, status jobs and completion records at the head, read with the job
// token (`scopes` names each lane's record scope; a lane left out has no run),
// and the security lane's reviewed-head marker carrying its summary.
const REVIEW_FILES = { "claude-review": ["pr-review-hosted.yml", "pr-review / claude-review-status"], "claude-security-review": ["pr-review-security-hosted.yml", "pr-review-security / security-review"] };
function laneReader({ pushes = [pushedBy(APP_ACTOR)], scopes = { "claude-review": "incremental since=" + KEY, "claude-security-review": "whole" }, runStatus = "completed" } = {}) {
  const fallback = readerFor({ pushes });
  return async (method, path) => {
    for (const [index, [lane, [file, job]]] of Object.entries(REVIEW_FILES).entries()) {
      const runId = 800 + index;
      const jobId = 900 + index;
      if (path === `/repos/${REPO}/actions/workflows/${file}/runs?head_sha=${HEAD}&event=pull_request&per_page=100`) {
        const runs = lane in scopes ? [{ id: runId, path: `.github/workflows/${file}`, head_sha: HEAD, event: "pull_request", head_repository: { full_name: REPO }, status: runStatus, conclusion: runStatus === "completed" ? "success" : null }] : [];
        return { workflow_runs: runs };
      }
      if (path === `/repos/${REPO}/actions/runs/${runId}/jobs?filter=latest&per_page=100`) {
        return { jobs: [{ id: jobId, name: job, status: "completed", conclusion: "success" }] };
      }
      if (path === `/repos/${REPO}/check-runs/${jobId}/annotations?per_page=100`) {
        return [{ title: "claude-lane-review-complete", annotation_level: "notice", message: `claude-lane-review-complete lane=${lane} sha=${HEAD} findings=1 inline=1 scope=${scopes[lane]}` }];
      }
    }
    return fallback(method, path);
  };
}
const securitySummary = (critical = 0, head = HEAD) =>
  commented(ACTIONS_BOT, `<!-- claude-lane-reviewed-head lane=claude-security-review sha=${head} -->\nSummary.\n\ncritical-findings: ${critical}\n\nclaude-lane: claude-security-review`, "2026-10-18T11:30:00Z");
const notLandedTimeline = (summary = securitySummary()) => [labeled(BOT, "2026-10-18T10:00:00Z"), notLanded(), summary];
const REVIEWER_AUTHOR = { __typename: "Bot", login: "github-actions" };
const severityThread = (severity) => ({ ...reviewThread(false, [REVIEWER_AUTHOR]), opening: { nodes: [{ body: `Finding.\n\n${severity}\n\nclaude-lane: claude-security-review` }] } });
const WAITING = `a push no trusted person made moved the head; waiting for clean review lanes at ${HEAD}`;

// An open SUGGESTION or IMPORTANT finding is reported, not held: only a
// CRITICAL one holds (owner decision on #11020).
test("feedback-not-landed comes off after a lanes App push once both review lanes read the new head clean, an open SUGGESTION or IMPORTANT thread included", async () => {
  for (const severity of ["severity: SUGGESTION", "severity: IMPORTANT"]) {
    const w = world({ timeline: notLandedTimeline(), reader: laneReader(), reviewThreads: () => threadPage([reviewThread(true, [LANE_AUTHOR]), severityThread(severity)]) });
    const { code } = await run(w, TRUST_ENV);
    assert.equal(code, 0, severity);
    const [comment, removal] = w.writes();
    assert.equal(comment.body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=feedback-not-landed head=${HEAD} -->`, severity);
    assert.match(comment.body.body, /both review lanes completed a review of it/);
    assert.deepEqual(removal, { method: "DELETE", path: `/repos/${REPO}/issues/7/labels/needs-human`, body: undefined }, severity);
  }
});

test("feedback-not-landed stays after a lanes App push while the review lanes have not reviewed the new head", async () => {
  for (const [label, reader, timeline] of [
    ["no lane run", laneReader({ scopes: {} }), notLandedTimeline()],
    ["only one lane ran", laneReader({ scopes: { "claude-security-review": "whole" } }), notLandedTimeline()],
    ["runs still in progress", laneReader({ runStatus: "in_progress" }), notLandedTimeline()],
    ["an incremental security review", laneReader({ scopes: { "claude-review": "whole", "claude-security-review": `incremental since=${KEY}` } }), notLandedTimeline()],
    ["no security summary", laneReader(), notLandedTimeline(commented(ACTIONS_BOT, "CI summary.", "2026-10-18T11:30:00Z"))],
    ["a summary of an earlier head", laneReader(), notLandedTimeline(securitySummary(0, KEY))],
    ["no job token", undefined, notLandedTimeline()],
  ]) {
    const w = world({ timeline, reader });
    const { logs } = await run(w, reader === undefined ? { TRUSTED_ACTORS_PATH: TRUSTED } : TRUST_ENV);
    assert.deepEqual(w.writes(), [], label);
    assert.ok(logs.some((line) => line.includes(WAITING)), `${label}: ${logs.join("\n")}`);
  }
});

test("feedback-not-landed stays after a lanes App push while an unresolved review thread carries a CRITICAL or unreadable severity", async () => {
  for (const severity of ["severity: CRITICAL", "", "severity: SUGGESTION\nseverity: IMPORTANT"]) {
    const w = world({ timeline: notLandedTimeline(), reader: laneReader(), reviewThreads: () => threadPage([severityThread(severity)]) });
    const { logs } = await run(w, TRUST_ENV);
    assert.deepEqual(w.writes(), [], severity);
    assert.ok(logs.some((line) => line.includes(WAITING)), severity);
  }
});

test("feedback-not-landed stays after a lanes App push when the security review reports a CRITICAL finding", async () => {
  for (const timeline of [notLandedTimeline(securitySummary(1)), notLandedTimeline({ ...securitySummary(0), updated_at: "2026-10-18T12:00:00Z" })]) {
    const w = world({ timeline, reader: laneReader() });
    const { logs } = await run(w, TRUST_ENV);
    assert.deepEqual(w.writes(), []);
    assert.ok(logs.some((line) => line.includes(WAITING)), logs.join("\n"));
  }
});

test("feedback-not-landed comes off after a trusted person's push, as before, with no review lane read", async () => {
  const calls = [];
  const w = world({
    timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), notLanded()],
    reader: readerFor({ calls }),
    reviewThreads: () => threadPage([reviewThread(true, [PERSON_AUTHOR, LANE_AUTHOR]), reviewThread(false, [PERSON_AUTHOR])]),
  });
  const { code } = await run(w, TRUST_ENV);
  assert.equal(code, 0);
  const [comment, removal] = w.writes();
  assert.equal(comment.body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=feedback-not-landed head=${HEAD} -->`);
  assert.match(comment.body.body, /kyle-sexton moved the head/);
  assert.match(comment.body.body, /no review thread the lane replied to is unresolved/);
  assert.equal(removal.method, "DELETE");
  assert.ok(!calls.some((path) => path.includes("/actions/")), calls.join("\n"));
});

// Per the owner's direction on the security finding: clean review lanes stand
// in for a person only when every escalation recorded against the label since
// it was last removed is a lane-only one.
test("feedback-not-landed stays after a lanes App push when another escalation is recorded against the label", async () => {
  for (const [label, earlier, named] of [
    ["a pr-merge risk hold", commented(BOT, riskBody(OLD), "2026-10-18T09:00:00Z"), "<!-- babysit-merge-risk -->"],
    ["a security escalation", escalated("feedback-question-security", { at: "2026-10-18T09:00:00Z" }), "feedback-question-security"],
    ["an unknown reason", escalated("some-future-reason", { at: "2026-10-18T09:00:00Z" }), "some-future-reason"],
  ]) {
    const w = world({ timeline: [earlier, ...notLandedTimeline()], reader: laneReader() });
    const { logs } = await run(w, TRUST_ENV);
    assert.deepEqual(w.writes(), [], label);
    assert.ok(logs.some((line) => line.includes("feedback-not-landed still holds") && line.includes(`${named} is recorded against the label`)), `${label}: ${logs.join("\n")}`);
  }
});

test("feedback-not-landed comes off after a lanes App push when another escalation came before a person removed the label", async () => {
  const lifted = [commented(BOT, riskBody(OLD), "2026-10-18T08:00:00Z"), { event: "unlabeled", actor: OWNER, label: { name: "needs-human" }, created_at: "2026-10-18T09:00:00Z" }];
  const w = world({ timeline: [...lifted, ...notLandedTimeline()], reader: laneReader() });
  await run(w, TRUST_ENV);
  assert.deepEqual(w.writes().at(-1), { method: "DELETE", path: `/repos/${REPO}/issues/7/labels/needs-human`, body: undefined });
});

test("workflow-staged stays when any push since the label is by an account off the trusted list", async () => {
  for (const pushes of [
    [pushedBy(STRANGER)],
    [pushedBy(STRANGER, "e".repeat(40), "2026-10-18T10:30:00Z"), pushedBy(PERSON)],
    [pushedBy({ login: "claude[bot]", id: 209825114, type: "Bot" })],
    [pushedBy({ login: BOT.login, id: 1, type: "Bot" })],
  ]) {
    const w = world({ timeline: stagedTimeline(), mainFiles: WORKFLOW_MAIN, reader: readerFor({ pushes }) });
    await run(w, TRUST_ENV);
    assert.deepEqual(w.writes(), [], JSON.stringify(pushes));
  }
});

test("workflow-staged stays when the head does not contain main as it was at the escalation", async () => {
  const w = world({ timeline: stagedTimeline(), mainFiles: WORKFLOW_MAIN, reader: readerFor({ contains: false }) });
  await run(w, TRUST_ENV);
  assert.deepEqual(w.writes(), []);
});

test("workflow-staged stays when the newest push is not the head, or no push since the label is read", async () => {
  for (const pushes of [[pushedBy(PERSON, "e".repeat(40))], []]) {
    const w = world({ timeline: stagedTimeline(), mainFiles: WORKFLOW_MAIN, reader: readerFor({ pushes }) });
    await run(w, TRUST_ENV);
    assert.deepEqual(w.writes(), []);
  }
});

test("workflow-staged stays when the activity page does not reach back to the label", async () => {
  const pushes = Array.from({ length: 100 }, (_, index) => pushedBy(PERSON, index === 99 ? HEAD : "e".repeat(40), new Date(Date.parse("2026-10-18T11:00:00Z") + index * 60_000).toISOString()));
  const reader = async (method, path) =>
    path.includes("/activity?") ? pushes.map(({ actor, after, at }) => ({ activity_type: "push", actor, after, timestamp: at })) : readerFor()(method, path);
  const w = world({ timeline: stagedTimeline(), mainFiles: WORKFLOW_MAIN, reader });
  await run(w, TRUST_ENV);
  assert.deepEqual(w.writes(), []);
});

// The activity API ignores `page`: each next page is the Link rel="next"
// cursor (merge-holds.mjs branchActivity). `rows` split into pages of 100;
// `link` decides whether page n names page n + 1.
const pagedReader = (rows, link = (n, pages) => n + 1 < pages.length) => {
  const pages = Array.from({ length: Math.max(1, Math.ceil(rows.length / 100)) }, (_, n) => rows.slice(n * 100, n * 100 + 100));
  return async (method, path) => {
    if (!path.startsWith(ACTIVITY)) {
      return readerFor()(method, path);
    }
    const n = Number(/&after=c(\d+)$/.exec(path)?.[1] ?? 0);
    const page = [...(pages[n] ?? [])];
    return Object.defineProperty(page, Symbol.for("github.link"), { value: link(n, pages) ? `<https://api.github.com/repositories/1/activity?after=c${n + 1}>; rel="next"` : null });
  };
};
// `count` trusted pushes since the label, the newest landing the head, then the branch's creation.
const longHistory = (count) => activityOf(Array.from({ length: count }, (_, i) => pushedBy(PERSON, i === count - 1 ? HEAD : "e".repeat(40), new Date(Date.parse("2026-10-18T11:00:00Z") + i * 1000).toISOString())));

test("workflow-staged comes off when the trusted move reads past the first activity page, or ends on an empty one", async () => {
  for (const [label, reader] of [
    ["the branch creation on page 2", pagedReader(longHistory(100))],
    ["an empty page after a full one", pagedReader(longHistory(99), (n) => n === 0)],
  ]) {
    const w = world({ timeline: stagedTimeline(), mainFiles: WORKFLOW_MAIN, reader });
    await run(w, TRUST_ENV);
    assert.equal(w.writes().at(-1)?.method, "DELETE", label);
  }
});

test("workflow-staged stays at the activity cursor's end: a full page with no next link, or more than 20 pages", async () => {
  for (const [label, reader] of [
    ["no next link", pagedReader(longHistory(100), () => false)],
    ["past 20 pages", pagedReader(longHistory(2000))],
  ]) {
    const w = world({ timeline: stagedTimeline(), mainFiles: WORKFLOW_MAIN, reader });
    await run(w, TRUST_ENV);
    assert.deepEqual(w.writes(), [], label);
  }
});

// Page 1 alone would clear the hold (the empty-page case above), so only a
// read that stops at the failed page 2 keeps it.
test("workflow-staged stays when a later activity page fails to read or is not a list", async () => {
  const pages = pagedReader(longHistory(99), (n) => n === 0);
  for (const [label, page2] of [
    ["page 2 throws", () => Promise.reject(new Error("GET activity returned 500"))],
    ["page 2 is not a list", async () => ({ message: "Not Found" })],
  ]) {
    const reader = (method, path) => (path.startsWith(ACTIVITY) && path.endsWith("&after=c1") ? page2() : pages(method, path));
    const w = world({ timeline: stagedTimeline(), mainFiles: WORKFLOW_MAIN, reader });
    await run(w, TRUST_ENV);
    assert.deepEqual(w.writes(), [], label);
  }
});

test("workflow-staged stays at the resume key, on a fork head, and without the trusted list or the job token", async () => {
  const atKey = world({
    timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), commented(BOT, escalationBody("workflow-staged").replaceAll(KEY, HEAD), "2026-10-18T10:00:05Z")],
    mainFiles: WORKFLOW_MAIN,
    reader: readerFor(),
  });
  await run(atKey, TRUST_ENV);
  assert.deepEqual(atKey.writes(), []);
  const fork = world({ timeline: stagedTimeline(), mainFiles: WORKFLOW_MAIN, headRepo: "someone/fork", reader: readerFor() });
  await run(fork, TRUST_ENV);
  assert.deepEqual(fork.writes(), []);
  for (const env of [{ BABYSIT_VERIFY_GH_TOKEN: "job-token", TRUSTED_ACTORS_PATH: "/nonexistent/trusted-actors.json" }, { TRUSTED_ACTORS_PATH: TRUSTED }]) {
    const w = world({ timeline: stagedTimeline(), mainFiles: WORKFLOW_MAIN, reader: env.BABYSIT_VERIFY_GH_TOKEN ? readerFor() : undefined });
    await run(w, env);
    assert.deepEqual(w.writes(), []);
  }
});

test("an unreadable job-token read keeps the label without failing the run", async () => {
  const reader = async () => {
    throw new Error("HTTP 502");
  };
  const w = world({ timeline: stagedTimeline(), mainFiles: WORKFLOW_MAIN, reader });
  const { code } = await run(w, TRUST_ENV);
  assert.equal(code, 0);
  assert.deepEqual(w.writes(), []);
});

const CI_FIX = ["ci-fix-round-cap", "ci-fix-empty", "ci-fix-invalid", "ci-fix-not-applied", "ci-fix-escalated"];

test("a ci-fix stop comes off once a trusted push moved the head and no check but ci-status fails there", async () => {
  for (const reason of CI_FIX) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(reason)], reader: readerFor() });
    await run(w, TRUST_ENV);
    assert.equal(w.writes().length, 2, reason);
    assert.match(w.writes()[0].body.body, new RegExp(`reason=${reason} head=${HEAD}`));
    assert.match(w.writes()[0].body.body, /no check other than ci-status fails/);
  }
});

test("a ci-fix stop stays while a check fails, runs, or none has passed at the head, or the head never moved", async () => {
  for (const checkRuns of [
    [...GREEN, run_("test-bash (0)", "failure", 4)],
    [...GREEN, run_("test-bash (0)", null, 4, "in_progress")],
    [...GREEN, run_("test-python", "cancelled", 4)],
    [run_("test-node", "failure", 2), run_("test-node", "skipped", 9)],
    [run_("ci-status", "failure", 1), run_("lint-repo", "skipped", 3)],
    [...GREEN, run_("deploy", "action_required", 4)],
    [...GREEN, run_("test-go", "stale", 4)],
    [...GREEN, run_("test-go", null, 4)],
    [],
  ]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated("ci-fix-escalated")], reader: readerFor({ checkRuns }) });
    await run(w, TRUST_ENV);
    assert.deepEqual(w.writes(), [], JSON.stringify(checkRuns));
  }
  const unmoved = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated("ci-fix-escalated")], reader: readerFor({ pushes: [pushedBy(STRANGER)] }) });
  await run(unmoved, TRUST_ENV);
  assert.deepEqual(unmoved.writes(), []);
});

test("a ci-fix stop passes with a neutral check at the head", async () => {
  const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated("ci-fix-escalated")], reader: readerFor({ checkRuns: [...GREEN, run_("pr-unblock / publish-feedback", "neutral", 4)] }) });
  await run(w, TRUST_ENV);
  assert.equal(w.writes().at(-1)?.method, "DELETE");
});

test("a protected-path or own-patch stop stays, even once the PR is mergeable after a trusted move with everything green", async () => {
  for (const reason of ["ci-fix-protected-path", "unexpected-path-staged", "conflict-patch-invalid", "conflict-patch-not-applied", "conflict-patch-protected-path"]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(reason)], mergeable: true, reader: readerFor() });
    await run(w, TRUST_ENV);
    assert.deepEqual(w.writes(), [], reason);
  }
});

test("a security, intent or decision stop is never lifted, even after a trusted move with everything green", async () => {
  for (const reason of [
    "feedback-uncertain",
    "feedback-disputed",
    "feedback-unadjudicated",
    "feedback-question-intent",
    "feedback-question-design",
    "feedback-question-security",
    "feedback-round-cap",
    "dependency-security-close",
    "dependency-escalate",
    "repeat-cap",
  ]) {
    const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), escalated(reason)], mergeable: true, reader: readerFor() });
    await run(w, TRUST_ENV);
    assert.deepEqual(w.writes(), [], reason);
  }
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
    [`/repos/${REPO}/pulls/7/comments?since=2026-10-18T09:59:59Z&per_page=100&page=1`, `/repos/${REPO}/pulls/7/reviews?per_page=100&page=1`],
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

test("a refusal cleared by the reader reads the review threads again right before the removal", async () => {
  const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence: clean });
  await run(w, NATIVE);
  assert.deepEqual(w.writes().at(-1), DELETE);
  assert.equal(threadReads(w).length, 4);
});

test("a thread opened, or a person's reply, while the gate's reader runs keeps enable-auto-merge's label", async () => {
  for (const [label, landed, kept] of [
    ["a thread opened", () => ({ ...BOT_THREAD, id: 103, created_at: new Date().toISOString(), updated_at: new Date().toISOString() }), "a review thread was opened by github-actions[bot] while its reads ran"],
    ["a person's reply", () => reply(OWNER, "2026-10-18T12:00:00Z"), "kyle-sexton commented or reviewed after needs-human went on"],
  ]) {
    const reviewComments = [BOT_THREAD];
    const evidence = (pull) => {
      reviewComments.push(landed());
      return clean(pull);
    };
    const w = world({ timeline: nativeEscalated(UNBOUND), author: BOT, evidence, reviewComments });
    const { logs } = await run(w, NATIVE);
    assert.deepEqual(w.writes(), [], label);
    assert.equal(w.reads.length, 1, label);
    assert.ok(logs.includes(`clear-escalations: #7 kept: ${kept}`), `${label}: ${logs.join("\n")}`);
  }
});

test("a person's reply inside an existing thread after feedback-not-landed's own thread read keeps the label", async () => {
  // The reply lands while the check reads the trusted move with the job
  // token, after its thread read saw none.
  const reviewComments = [BOT_THREAD];
  const trusted = readerFor();
  const reader = async (method, path) => {
    if (reviewComments.length === 1) {
      reviewComments.push(reply(OWNER, "2026-10-18T12:00:00Z"));
    }
    return trusted(method, path);
  };
  const w = world({ timeline: [labeled(BOT, "2026-10-18T10:00:00Z"), notLanded()], reviewComments, reader });
  const { logs } = await run(w, TRUST_ENV);
  assert.deepEqual(w.writes(), []);
  assert.ok(logs.includes("clear-escalations: #7 kept: kyle-sexton commented or reviewed after needs-human went on"), logs.join("\n"));
  assert.equal(threadReads(w).filter((call) => call.path.includes("/comments?")).length, 2);
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

// The session-builder queue label (#11087): report-escalation.sh puts
// needs-session on before its lane-stopped comment for a fail-routed reason
// whose escalation-routes.json entry names it, and its `clear` mode posts
// success over the stop's failing status when a same-head retry lands.
const sessionLabeled = (actor, at = "2026-10-18T10:00:00Z") => ({ event: "labeled", actor, label: { name: "needs-session" }, created_at: at });
const stopBody = (reason, head = HEAD, activity = escalationActivity(reason)) =>
  `<!-- pr-unblock:lane-stopped activity=${activity} -->\nThe pr-unblock lane stopped \`${activity}\` on this pull request: why. The lane labels it \`needs-session\` for a session builder, who makes the change this lane cannot, and the run ends in a failing \`pr-unblock/${activity}\` status on the head the lane gated.\n\n- Reason: \`${reason}\`\n- Head: \`${head}\`\n- Run: https://github.com/${REPO}/actions/runs/1\n`;
const stopped = (reason = "ci-fix-escalated", head = HEAD) => commented(BOT, stopBody(reason, head), "2026-10-18T10:00:02Z");
const status = (state, creator = ACTIONS_BOT, at = "2026-10-18T11:00:00Z", context = "pr-unblock/fix-ci") => ({ context, state, creator, created_at: at });
const sessionWorld = (options) => world({ numbers: [], sessionNumbers: [8], ...options });

test("a rung-0 ci-fix-escalated stop whose same-head retry landed leaves the PR without needs-session, with no comment", async () => {
  assert.equal(ROUTES["ci-fix-escalated"].label, "needs-session");
  const w = sessionWorld({ timeline: [sessionLabeled(BOT), stopped()], statuses: [status("success"), status("failure")] });
  const { code, logs } = await run(w);
  assert.equal(code, 0);
  assert.deepEqual(w.writes(), [{ method: "DELETE", path: `/repos/${REPO}/issues/8/labels/needs-session`, body: undefined }]);
  assert.ok(logs.some((line) => /#8 needs-session cleared: ci-fix-escalated no longer fails pr-unblock\/fix-ci/.test(line)), logs.join("\n"));
});

test("a needs-session stop whose failing status still stands keeps the label", async () => {
  for (const statuses of [[status("failure")], [status("error"), status("success")], [], [status("success", OWNER), status("failure")]]) {
    const w = sessionWorld({ timeline: [sessionLabeled(BOT), stopped()], statuses });
    const { code, logs } = await run(w);
    assert.equal(code, 0);
    assert.deepEqual(w.writes(), [], JSON.stringify(statuses));
    assert.ok(logs.some((line) => /#8 needs-session kept: ci-fix-escalated still fails/.test(line)), logs.join("\n"));
  }
});

test("a success from before the stop keeps needs-session: the stop's failure posts in another job", async () => {
  const earlier = commented(BOT, stopBody("ci-fix-escalated"), "2026-10-18T10:00:02Z", "2026-10-18T12:00:00Z");
  const w = sessionWorld({ timeline: [sessionLabeled(BOT), earlier], statuses: [status("success")] });
  const { logs } = await run(w);
  assert.deepEqual(w.writes(), []);
  assert.ok(logs.some((line) => /#8 needs-session kept: .*no success since the stop/.test(line)), logs.join("\n"));
});

test("at most SESSION_CHECKS_PER_RUN pull requests are read a run, kept ones included, and the offset moves", async () => {
  const sessionNumbers = [1, 2, 3, 4, 5, 6, 7];
  const readBy = async (GITHUB_RUN_NUMBER) => {
    const w = world({ numbers: [], sessionNumbers, timeline: [sessionLabeled(BOT), stopped()], statuses: [status("failure")] });
    const { logs } = await run(w, { GITHUB_RUN_NUMBER });
    assert.deepEqual(w.writes(), []);
    assert.equal(logs.filter((line) => /needs-session not checked: 5 read this run/.test(line)).length, sessionNumbers.length - SESSION_CHECKS_PER_RUN);
    return w.calls.filter((call) => call.path.includes("/timeline")).map((call) => Number(/\/issues\/(\d+)\//.exec(call.path)[1]));
  };
  assert.deepEqual(await readBy("0"), [1, 2, 3, 4, 5]);
  assert.deepEqual(await readBy("3"), [4, 5, 6, 7, 1]);
});

test("a needs-session a person added, or one with no lane stop since it went on, is kept", async () => {
  for (const timeline of [
    [sessionLabeled(OWNER), stopped()],
    [commented(BOT, stopBody("ci-fix-escalated"), "2026-10-18T09:00:00Z"), sessionLabeled(BOT)],
    [sessionLabeled(BOT), stopped("ci-fix-round-cap")],
  ]) {
    const w = sessionWorld({ timeline, statuses: [status("success")] });
    await run(w);
    assert.deepEqual(w.writes(), [], JSON.stringify(timeline));
  }
});

// The new-head lift (#11200): a stop's status sits on the stop's head, so a
// push leaves nothing that marks the new head mended. The label comes off
// when the head is none of the stops' heads, the new head carries no failing
// status for their activities, and its checks pass; ci-status, which the
// label keeps red, is not counted.
const NEW_HEAD_GREEN = [check("test-node", "success"), check("ci-status", "failure", { id: 2 })];
const laneContext = (reason) => `pr-unblock/${escalationActivity(reason)}`;

test("a needs-session stop on an older head comes off once the new head carries no failing status and its checks pass", async () => {
  for (const reason of ["ci-fix-escalated", "dependency-round-cap"]) {
    assert.equal(ROUTES[reason].label, "needs-session");
    const keyStatuses = [status("failure", ACTIONS_BOT, "2026-10-18T10:00:01Z", laneContext(reason))];
    const w = sessionWorld({ timeline: [sessionLabeled(BOT), stopped(reason, KEY)], keyStatuses, headChecks: NEW_HEAD_GREEN });
    const { code, logs } = await run(w);
    assert.equal(code, 0);
    assert.deepEqual(w.writes(), [{ method: "DELETE", path: `/repos/${REPO}/issues/8/labels/needs-session`, body: undefined }], reason);
    const cleared = new RegExp(`#8 needs-session cleared: ${reason} stopped at ${KEY}, and no ${laneContext(reason)} status fails at the new head ${HEAD}; no check other than ci-status fails`);
    assert.ok(logs.some((line) => cleared.test(line)), logs.join("\n"));
  }
});

test("a new head keeps needs-session while the stop's status fails there or its checks do not pass", async () => {
  for (const [options, kept] of [
    [{ statuses: [status("failure")], headChecks: NEW_HEAD_GREEN }, /pr-unblock\/fix-ci reads failure at the new head/],
    [{ statuses: [status("pending"), status("success")], headChecks: NEW_HEAD_GREEN }, /pr-unblock\/fix-ci reads pending at the new head/],
    [{ headChecks: RED }, /stays at the new head: a check other than ci-status fails/],
    [{ headChecks: [check("ci-status", "failure")] }, /stays at the new head/],
    [{ headChecks: [{ ...check("test-node", "success"), status: "in_progress", conclusion: null }] }, /stays at the new head/],
    [{ headChecks: new Error("HTTP 403") }, /stays at the new head/],
  ]) {
    const w = sessionWorld({ timeline: [sessionLabeled(BOT), stopped("ci-fix-escalated", KEY)], keyStatuses: [status("failure")], ...options });
    const { code, logs } = await run(w);
    assert.equal(code, 0);
    assert.deepEqual(w.writes(), [], String(kept));
    assert.ok(logs.some((line) => /#8 needs-session kept: /.test(line) && kept.test(line)), logs.join("\n"));
  }
});

test("a dependency-workflow-unpinned stop keeps needs-session on a new head; only its same-head clear removes it", async () => {
  const reason = "dependency-workflow-unpinned";
  const context = laneContext(reason);
  const failed = status("failure", ACTIONS_BOT, "2026-10-18T10:00:01Z", context);
  const kept = sessionWorld({ timeline: [sessionLabeled(BOT), stopped(reason, KEY)], keyStatuses: [failed], headChecks: NEW_HEAD_GREEN });
  const { logs } = await run(kept);
  assert.deepEqual(kept.writes(), []);
  assert.ok(logs.some((line) => /#8 needs-session kept: dependency-workflow-unpinned stopped at .*only its lane's clear on that head/.test(line)), logs.join("\n"));
  const lifted = sessionWorld({ timeline: [sessionLabeled(BOT), stopped(reason, KEY)], keyStatuses: [status("success", ACTIONS_BOT, undefined, context), failed] });
  await run(lifted);
  assert.deepEqual(lifted.writes(), [{ method: "DELETE", path: `/repos/${REPO}/issues/8/labels/needs-session`, body: undefined }]);
});

test("a needs-session stop whose head statuses do not read keeps the label without failing the run", async () => {
  const w = sessionWorld({ timeline: [sessionLabeled(BOT), stopped()], statuses: new Error("HTTP 403") });
  const { code, logs } = await run(w);
  assert.equal(code, 0);
  assert.deepEqual(w.writes(), []);
  assert.ok(logs.some((line) => /::warning title=clear-escalations::#8: HTTP 403/.test(line)), logs.join("\n"));
});
