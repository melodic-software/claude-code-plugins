import assert from "node:assert/strict";
import { test } from "node:test";

import {
  ARTIFACT_PREFIX,
  InvalidRating,
  RATING_WORKFLOW_PATH,
  REASONS,
  artifactName,
  markerAction,
  markerBody,
  checkRating,
  checkResult,
  modelsOf,
  ratedLine,
  readRating,
  recordMergeRisk,
  unratedLine,
} from "./merge-risk-line.mjs";

const HEAD = "a".repeat(40);
const OTHER = "b".repeat(40);
const REPO = "melodic-software/claude-code-plugins";
const row = (level, extra = {}) => ({ area: "Impact", level, why: "touches one script", check: "agreed", checker_level: "", checker: "", ...extra });
const rating = (extra = {}) => ({
  pr: 7,
  head: HEAD,
  risks: [row("LOW"), row("MEDIUM", { area: "Verification" })],
  max: "MEDIUM",
  demote: false,
  rubric: "8.0.0",
  rater: "claude-opus-5-5",
  checker: "claude-opus-5-5",
  ...extra,
});

test("the rated line carries every field in order", () => {
  assert.equal(
    ratedLine(rating()),
    `Merge-Risk: max=MEDIUM demote=false head=${HEAD} rubric=8.0.0 rater=claude-opus-5-5 checker=claude-opus-5-5`,
  );
});

test("the unrated line names its reason, and only a reason from the closed set", () => {
  for (const reason of REASONS) {
    assert.equal(unratedLine(reason), `Merge-Risk: unrated reason=${reason}`);
  }
  assert.throws(() => unratedLine("do not merge"), InvalidRating);
});

test("no line or marker comment the builder writes trips a hold or a committer row", async () => {
  const { BODY_HOLD, HUMAN_VETO, LANE_HOLD } = await import("./merge-holds.mjs");
  const lines = [ratedLine(rating({ max: "CRITICAL", demote: true })), ...REASONS.map(unratedLine)];
  for (const line of [...lines, ...lines.map((text) => markerBody(HEAD, text))]) {
    assert.equal(BODY_HOLD.test(line), false, line);
    assert.equal(HUMAN_VETO.test(line), false, line);
    assert.equal(LANE_HOLD.test(line), false, line);
    assert.equal(/(^|\s)committer /.test(line), false, line);
  }
});

test("checkResult recomputes max and demote from the rows, never trusting the model's", () => {
  const checked = checkResult({ pr: 7, head: HEAD, risks: [row("LOW"), row("MEDIUM", { check: "disputed", checker_level: "HIGH", checker: "data loss" })], demote: false }, { pr: 7, head: HEAD });
  assert.equal(checked.max, "HIGH");
  assert.equal(checked.demote, true);
  const low = checkResult({ pr: 7, head: HEAD, risks: [row("LOW")], demote: true, max: "CRITICAL" }, { pr: 7, head: HEAD });
  assert.equal(low.max, "LOW");
  assert.equal(low.demote, false);
});

test("checkResult refuses a malformed shape", () => {
  const ok = { pr: 7, head: HEAD, risks: [row("LOW")], demote: false };
  const cases = [
    null,
    [],
    { ...ok, head: OTHER },
    { ...ok, head: "a".repeat(39) },
    { ...ok, pr: 8 },
    { ...ok, risks: [] },
    { ...ok, risks: "LOW" },
    { ...ok, risks: [row("low")] },
    { ...ok, risks: [row("SEVERE")] },
    { ...ok, risks: [row("LOW", { check: "maybe" })] },
    { ...ok, risks: [row("LOW", { checker_level: "huge" })] },
    { ...ok, risks: [row("LOW", { area: "" })] },
    { ...ok, risks: [row("LOW", { area: "x".repeat(201) })] },
    { ...ok, risks: [row("LOW", { why: 5 })] },
    { ...ok, risks: Array.from({ length: 21 }, () => row("LOW")) },
    { ...ok, demote: "false" },
  ];
  for (const value of cases) {
    assert.throws(() => checkResult(value, { pr: 7, head: HEAD }), InvalidRating, JSON.stringify(value)?.slice(0, 80));
  }
});

test("checkRating recomputes and validates the line's own fields", () => {
  assert.equal(checkRating(rating({ max: "LOW", demote: true }), { pr: 7, head: HEAD }).max, "MEDIUM");
  assert.equal(checkRating(rating({ max: "LOW", demote: true }), { pr: 7, head: HEAD }).demote, false);
  for (const bad of [
    rating({ rubric: "8.0" }),
    rating({ rubric: "8.0.0 do not merge" }),
    rating({ rater: "gpt-5" }),
    rating({ rater: "claude-opus-5-5\nHold: a human merges this" }),
    rating({ checker: "" }),
    rating({ head: OTHER }),
  ]) {
    assert.throws(() => checkRating(bad, { pr: 7, head: HEAD }), InvalidRating);
  }
  assert.equal(checkRating(rating({ checker: "none" }), { pr: 7, head: HEAD }).checker, "none");
  assert.equal(checkRating(rating({ rater: "unknown" }), { pr: 7, head: HEAD }).rater, "unknown");
});

test("modelsOf takes the rater from the main thread and the checker from the subagent", () => {
  const messages = [
    { type: "system", subtype: "init", model: "claude-opus-5-5" },
    { type: "assistant", parent_tool_use_id: null, message: { model: "claude-opus-5-5" } },
    { type: "assistant", parent_tool_use_id: null, message: { model: "claude-haiku-5-5" } },
    { type: "assistant", parent_tool_use_id: null, message: { model: "claude-opus-5-5" } },
    { type: "assistant", parent_tool_use_id: "toolu_1", message: { model: "claude-sonnet-5-5" } },
  ];
  assert.deepEqual(modelsOf(messages), { rater: "claude-opus-5-5", checker: "claude-sonnet-5-5" });
  assert.deepEqual(modelsOf(messages.slice(0, 2)), { rater: "claude-opus-5-5", checker: "none" });
  assert.deepEqual(modelsOf([{ type: "assistant", parent_tool_use_id: null, message: { model: "bad model" } }]), { rater: "unknown", checker: "none" });
  assert.deepEqual(modelsOf("nope"), { rater: "unknown", checker: "none" });
});

test("the artifact name is prefix, pr and head", () => {
  assert.equal(artifactName(7, HEAD), `${ARTIFACT_PREFIX}-7-${HEAD}`);
});

// A fake GitHub for the reader: routes by path.
const runOf = (id, extra = {}) => ({
  id,
  path: RATING_WORKFLOW_PATH,
  event: "workflow_run",
  head_branch: "main",
  status: "completed",
  conclusion: "success",
  repository: { full_name: REPO },
  head_repository: { full_name: REPO },
  head_sha: "c".repeat(40),
  display_title: `merge-risk #7 ${HEAD}`,
  created_at: "2026-11-06T01:00:00Z",
  ...extra,
});

function fake({ artifacts = [], runs = {}, listing = [], fail = new Set() } = {}) {
  const calls = [];
  const actions = async (method, path) => {
    calls.push(`${method} ${path}`);
    for (const key of fail) {
      if (path.includes(key)) throw new Error(`refused ${key}`);
    }
    if (path.includes("/actions/artifacts?name=")) return { artifacts };
    const run = /\/actions\/runs\/(\d+)$/.exec(path);
    if (run) return runs[run[1]];
    if (path.includes("/actions/workflows/")) return { workflow_runs: listing };
    throw new Error(`unexpected ${path}`);
  };
  return { actions, calls };
}

test("readRating: a counted run's artifact gives the rated line", async () => {
  const { actions, calls } = fake({ artifacts: [{ id: 11, name: artifactName(7, HEAD), expired: false, workflow_run: { id: 5 } }], runs: { 5: runOf(5) } });
  const result = await readRating({ actions, download: () => JSON.stringify(rating()), repository: REPO, pr: 7, head: HEAD });
  assert.equal(result.line, ratedLine(rating()));
  assert.equal(result.token, "rated");
  assert.equal(calls.length, 2);
});

test("readRating: an artifact from a run of another origin never counts", async () => {
  for (const bad of [{ path: ".github/workflows/evil.yml" }, { event: "pull_request" }, { head_branch: "feat/x" }, { repository: { full_name: "other/repo" } }, { head_sha: "abc" }]) {
    const { actions } = fake({ artifacts: [{ id: 11, name: artifactName(7, HEAD), expired: false, workflow_run: { id: 5 } }], runs: { 5: runOf(5, bad) }, listing: [] });
    const result = await readRating({ actions, download: () => JSON.stringify(rating()), repository: REPO, pr: 7, head: HEAD });
    assert.equal(result.token, "unrated:no-run", JSON.stringify(bad));
  }
});

test("readRating: no artifact reads the runs for pending, no-rating or no-run", async () => {
  const pending = fake({ listing: [runOf(5, { status: "in_progress", conclusion: null })] });
  assert.equal((await readRating({ actions: pending.actions, download: () => "", repository: REPO, pr: 7, head: HEAD })).token, "unrated:pending");
  const done = fake({ listing: [runOf(5)] });
  assert.equal((await readRating({ actions: done.actions, download: () => "", repository: REPO, pr: 7, head: HEAD })).token, "unrated:no-rating");
  const other = fake({ listing: [runOf(5, { display_title: `merge-risk #7 ${OTHER}` })] });
  assert.equal((await readRating({ actions: other.actions, download: () => "", repository: REPO, pr: 7, head: HEAD })).token, "unrated:no-run");
});

test("readRating: a bad artifact is invalid, an unreadable one unreadable", async () => {
  const setup = { artifacts: [{ id: 11, name: artifactName(7, HEAD), expired: false, workflow_run: { id: 5 } }], runs: { 5: runOf(5) } };
  assert.equal((await readRating({ ...fake(setup), download: () => "{", repository: REPO, pr: 7, head: HEAD })).token, "unrated:invalid");
  assert.equal((await readRating({ ...fake(setup), download: () => JSON.stringify(rating({ head: OTHER })), repository: REPO, pr: 7, head: HEAD })).token, "unrated:invalid");
  const thrown = await readRating({
    ...fake(setup),
    download: () => {
      throw new Error("unzip failed");
    },
    repository: REPO,
    pr: 7,
    head: HEAD,
  });
  assert.equal(thrown.token, "unrated:unreadable");
});

// recordMergeRisk: the arm-side step. It never throws, never touches the
// pull request body, and lists no comments: it reads only those it is given.
const BOT = "melodic-automation-lanes";
const APP = { __typename: "Bot", login: BOT };
const pull = { number: 7, headRefOid: HEAD };
const PENDING_COMMENT = `<!-- merge-risk-line head=${HEAD} -->\nMerge-Risk: unrated reason=pending`;
const appSaid = (databaseId, body, createdAt = "2026-11-12T01:00:00Z", author = APP) => ({ databaseId, author, body, createdAt, lastEditedAt: null });
function writer({ fail = false, hang = false } = {}) {
  const sent = [];
  const github = async (method, path, payload) => {
    sent.push({ method, path, payload });
    if (method === "GET") throw new Error(`a read the arm already made: GET ${path}`);
    if (path.includes("/pulls/")) throw new Error(`a pull request body write: ${method} ${path}`);
    if (fail) throw new Error(`${method} refused`);
    if (hang) return new Promise(() => {});
    return {};
  };
  return { github, sent };
}
const pendingReads = () => fake({ listing: [runOf(5, { status: "queued", conclusion: null })] });

test("markerBody puts the head marker above the line", () => {
  assert.equal(markerBody(HEAD, unratedLine("pending")), PENDING_COMMENT);
});

test("markerAction posts with no marker, leaves an exact one, patches a changed line and posts for a new head", () => {
  const line = unratedLine("pending");
  assert.deepEqual(markerAction([], { bot: BOT, head: HEAD, line }), { action: "post" });
  assert.deepEqual(markerAction(undefined, { bot: BOT, head: HEAD, line }), { action: "post" });
  assert.deepEqual(markerAction([appSaid(41, PENDING_COMMENT)], { bot: BOT, head: HEAD, line }), { action: "none" });
  assert.deepEqual(markerAction([appSaid(41, `<!-- merge-risk-line head=${HEAD} -->\nMerge-Risk: unrated reason=no-run`)], { bot: BOT, head: HEAD, line }), { action: "patch", id: 41 });
  assert.deepEqual(markerAction([appSaid(41, `<!-- merge-risk-line head=${OTHER} -->\nMerge-Risk: unrated reason=pending`)], { bot: BOT, head: HEAD, line }), { action: "post" });
});

test("markerAction reads only the lanes App's newest marker comment", () => {
  const line = unratedLine("pending");
  const older = appSaid(40, PENDING_COMMENT, "2026-11-12T01:00:00Z");
  const newer = appSaid(41, `<!-- merge-risk-line head=${OTHER} -->\nMerge-Risk: unrated reason=pending`, "2026-11-12T02:00:00Z");
  assert.deepEqual(markerAction([newer, older], { bot: BOT, head: HEAD, line }), { action: "post" });
  // A person's or another app's look-alike is not the App's record.
  const person = appSaid(50, PENDING_COMMENT, "2026-11-12T03:00:00Z", { __typename: "User", login: BOT });
  const otherApp = appSaid(51, PENDING_COMMENT, "2026-11-12T03:00:00Z", { __typename: "Bot", login: "other-app" });
  assert.deepEqual(markerAction([person, otherApp], { bot: BOT, head: HEAD, line }), { action: "post" });
  // The marker must be the first line; quoting it lower down is not a record.
  assert.deepEqual(markerAction([appSaid(52, `quoted:\n${PENDING_COMMENT}`)], { bot: BOT, head: HEAD, line }), { action: "post" });
  // A same-head record with no id to patch is posted again.
  assert.deepEqual(markerAction([{ ...appSaid(53, `<!-- merge-risk-line head=${HEAD} -->\nMerge-Risk: unrated reason=no-run`), databaseId: undefined }], { bot: BOT, head: HEAD, line }), { action: "post" });
});

test("markerAction never replaces a rated record with an unrated line, and still moves a rated record to another rating", () => {
  const rated = appSaid(60, markerBody(HEAD, ratedLine(rating())));
  for (const reason of REASONS) {
    assert.deepEqual(markerAction([rated], { bot: BOT, head: HEAD, line: unratedLine(reason) }), { action: "none" }, reason);
  }
  const higher = ratedLine({ ...rating(), max: "HIGH", demote: true });
  assert.deepEqual(markerAction([rated], { bot: BOT, head: HEAD, line: higher }), { action: "patch", id: 60 });
  assert.deepEqual(markerAction([appSaid(61, PENDING_COMMENT)], { bot: BOT, head: HEAD, line: ratedLine(rating()) }), { action: "patch", id: 61 });
});

test("markerAction posts a fresh record when the App's newest marker comment was edited", () => {
  const edited = (body) => ({ ...appSaid(70, body), lastEditedAt: "2026-11-12T02:00:00Z" });
  assert.deepEqual(markerAction([edited(PENDING_COMMENT)], { bot: BOT, head: HEAD, line: unratedLine("pending") }), { action: "post" });
  assert.deepEqual(markerAction([edited(PENDING_COMMENT)], { bot: BOT, head: HEAD, line: ratedLine(rating()) }), { action: "post" });
  assert.deepEqual(markerAction([edited(markerBody(HEAD, ratedLine(rating())))], { bot: BOT, head: HEAD, line: unratedLine("no-run") }), { action: "post" });
});

test("recordMergeRisk posts one marker comment when the head has none", async () => {
  const { actions } = fake({ artifacts: [{ id: 11, name: artifactName(7, HEAD), expired: false, workflow_run: { id: 5 } }], runs: { 5: runOf(5) } });
  const { github, sent } = writer();
  const result = await recordMergeRisk({ bot: BOT, pull, comments: [], repository: REPO, actions, github, download: () => JSON.stringify(rating()) });
  assert.deepEqual([result.token, result.wrote, result.skipped], ["rated", true, undefined]);
  assert.deepEqual(sent, [
    {
      method: "POST",
      path: `/repos/${REPO}/issues/7/comments`,
      payload: { body: `<!-- merge-risk-line head=${HEAD} -->\nMerge-Risk: max=MEDIUM demote=false head=${HEAD} rubric=8.0.0 rater=claude-opus-5-5 checker=claude-opus-5-5` },
    },
  ]);
});

test("recordMergeRisk patches the head's marker comment when its line changed", async () => {
  const { actions } = fake({ artifacts: [{ id: 11, name: artifactName(7, HEAD), expired: false, workflow_run: { id: 5 } }], runs: { 5: runOf(5) } });
  const { github, sent } = writer();
  const result = await recordMergeRisk({ bot: BOT, pull, comments: [appSaid(41, PENDING_COMMENT)], repository: REPO, actions, github, download: () => JSON.stringify(rating()) });
  assert.deepEqual([result.token, result.wrote], ["rated", true]);
  assert.deepEqual(sent, [
    {
      method: "PATCH",
      path: `/repos/${REPO}/issues/comments/41`,
      payload: { body: `<!-- merge-risk-line head=${HEAD} -->\nMerge-Risk: max=MEDIUM demote=false head=${HEAD} rubric=8.0.0 rater=claude-opus-5-5 checker=claude-opus-5-5` },
    },
  ]);
});

test("recordMergeRisk writes nothing when the head's marker comment already holds the line", async () => {
  const { actions } = pendingReads();
  const { github, sent } = writer();
  const result = await recordMergeRisk({ bot: BOT, pull, comments: [appSaid(41, PENDING_COMMENT)], repository: REPO, actions, github, download: () => "" });
  assert.deepEqual([result.token, result.wrote, result.skipped], ["unrated:pending", false, "exact"]);
  assert.deepEqual(sent, []);
});

test("recordMergeRisk posts a new marker comment for a new head", async () => {
  const { actions } = pendingReads();
  const { github, sent } = writer();
  const old = appSaid(41, `<!-- merge-risk-line head=${OTHER} -->\nMerge-Risk: unrated reason=pending`);
  await recordMergeRisk({ bot: BOT, pull, comments: [old], repository: REPO, actions, github, download: () => "" });
  assert.deepEqual(sent, [{ method: "POST", path: `/repos/${REPO}/issues/7/comments`, payload: { body: PENDING_COMMENT } }]);
});

test("recordMergeRisk records a pull request a person wrote or edited too: the comment is the App's own text", async () => {
  const { actions } = pendingReads();
  const { github, sent } = writer();
  const edited = { ...pull, body: "Closes #1", author: { __typename: "User", login: "someone" }, userContentEdits: { totalCount: 1, nodes: [{ editor: { __typename: "User", login: "outsider" } }] } };
  const result = await recordMergeRisk({ bot: BOT, pull: edited, comments: [], repository: REPO, actions, github, download: () => "" });
  assert.equal(result.wrote, true);
  assert.deepEqual(sent, [{ method: "POST", path: `/repos/${REPO}/issues/7/comments`, payload: { body: PENDING_COMMENT } }]);
});

test("recordMergeRisk records unrated when every read throws, and still writes", async () => {
  const { actions } = fake({ fail: new Set(["/actions/"]) });
  const { github, sent } = writer();
  const result = await recordMergeRisk({ bot: BOT, pull, comments: [], repository: REPO, actions, github, download: () => "" });
  assert.equal(result.token, "unrated:unreadable");
  assert.deepEqual(sent.map((call) => call.payload.body), [`<!-- merge-risk-line head=${HEAD} -->\nMerge-Risk: unrated reason=unreadable`]);
});

test("recordMergeRisk records over-budget when a read hangs past the deadline", async () => {
  const actions = () => new Promise(() => {});
  const { github, sent } = writer();
  const started = Date.now();
  const result = await recordMergeRisk({ bot: BOT, pull, comments: [], repository: REPO, actions, github, download: () => "", readMs: 50, writeMs: 200 });
  assert.equal(result.token, "unrated:over-budget");
  assert.ok(Date.now() - started < 2000);
  assert.deepEqual(sent.map((call) => call.payload.body), [`<!-- merge-risk-line head=${HEAD} -->\nMerge-Risk: unrated reason=over-budget`]);
});

test("recordMergeRisk never throws when the comment write fails or hangs", async () => {
  const { actions } = fake({ listing: [] });
  const failed = await recordMergeRisk({ bot: BOT, pull, comments: [], repository: REPO, actions, github: writer({ fail: true }).github, download: () => "" });
  assert.deepEqual([failed.wrote, failed.skipped], [false, "write-failed"]);
  const hung = await recordMergeRisk({ bot: BOT, pull, comments: [], repository: REPO, actions, github: writer({ hang: true }).github, download: () => "", writeMs: 50 });
  assert.deepEqual([hung.wrote, hung.skipped], [false, "write-failed"]);
});

test("recordMergeRisk survives a throwing download and a malformed pull", async () => {
  const { actions } = fake({ artifacts: [{ id: 11, name: artifactName(7, HEAD), expired: false, workflow_run: { id: 5 } }], runs: { 5: runOf(5) } });
  const { github, sent } = writer();
  const result = await recordMergeRisk({
    bot: BOT,
    pull,
    comments: [],
    repository: REPO,
    actions,
    github,
    download: () => {
      throw new Error("boom");
    },
  });
  assert.equal(result.token, "unrated:unreadable");
  const before = sent.length;
  const bad = await recordMergeRisk({ bot: BOT, pull: { number: "x", headRefOid: "no" }, comments: [], repository: REPO, actions, github, download: () => "" });
  assert.deepEqual([bad.wrote, bad.skipped], [false, "no-pull"]);
  assert.equal(sent.length, before);
});

// ci-status loads clear-escalations.mjs, which imports enable-auto-merge.mjs,
// from a sparse checkout of main (pr-require-checks.yml "Check out the base
// commit's hold config"). Every module that load reaches through static
// imports must be in that list, so enable-auto-merge.mjs takes
// merge-risk-line.mjs by a dynamic import inside main.
test("ci-status's sparse hold config holds every module clear-escalations.mjs loads", async () => {
  const { readFileSync } = await import("node:fs");
  const { dirname, join, relative, resolve } = await import("node:path");
  const { fileURLToPath } = await import("node:url");
  const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
  const workflow = readFileSync(join(root, ".github/workflows/pr-require-checks.yml"), "utf8");
  const block = /- name: Check out the base commit's hold config[\s\S]*?sparse-checkout: \|\n([\s\S]*?)\n {10}sparse-checkout-cone-mode/.exec(workflow);
  assert.ok(block, "the hold config checkout is in pr-require-checks.yml");
  const sparse = new Set(block[1].split("\n").map((line) => line.trim()));
  const seen = new Set();
  const visit = (file) => {
    const path = relative(root, file);
    if (seen.has(path)) return;
    seen.add(path);
    const text = readFileSync(file, "utf8");
    for (const [, spec] of text.matchAll(/^(?:import|export)\s[^;]*?\sfrom\s+"(\.[^"]+)";/gms)) {
      visit(resolve(dirname(file), spec));
    }
  };
  visit(join(root, ".github/scripts/pr-merge/clear-escalations.mjs"));
  const missing = [...seen].filter((path) => !sparse.has(`/${path}`));
  assert.deepEqual(missing, []);
  assert.ok(seen.has(".github/scripts/pr-merge/enable-auto-merge.mjs"));
  assert.ok(!seen.has(".github/scripts/pr-merge/merge-risk-line.mjs"));
});
