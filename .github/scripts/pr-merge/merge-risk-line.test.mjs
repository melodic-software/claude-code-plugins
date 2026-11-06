import assert from "node:assert/strict";
import { test } from "node:test";

import {
  ARTIFACT_PREFIX,
  InvalidRating,
  RATING_WORKFLOW_PATH,
  REASONS,
  appOnlyBody,
  artifactName,
  checkRating,
  checkResult,
  modelsOf,
  ratedLine,
  readRating,
  recordMergeRisk,
  unratedLine,
  withMergeRiskLine,
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

test("no line the builder writes trips a body hold or a squash committer row", async () => {
  const { BODY_HOLD, HUMAN_VETO, LANE_HOLD } = await import("./merge-holds.mjs");
  for (const line of [ratedLine(rating({ max: "CRITICAL", demote: true })), ...REASONS.map(unratedLine)]) {
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

test("withMergeRiskLine sets the line last and replaces only the trailing line it wrote", () => {
  const line = unratedLine("pending");
  assert.equal(withMergeRiskLine("Closes #1\n\nbody", line), `Closes #1\n\nbody\n\n${line}`);
  assert.equal(withMergeRiskLine(`Closes #1\n\nbody\n\n${unratedLine("no-run")}\n`, line), `Closes #1\n\nbody\n\n${line}`);
  assert.equal(withMergeRiskLine(withMergeRiskLine("body", line), line), `body\n\n${line}`);
  assert.equal(withMergeRiskLine(null, line), line);
  // A Merge-Risk line mid-body is the author's text, not this function's.
  assert.equal(withMergeRiskLine("a\r\nMerge-Risk: max=LOW\r\nb", line), `a\r\nMerge-Risk: max=LOW\r\nb\n\n${line}`);
});

test("withMergeRiskLine keeps a fenced example of the format, as this pull request's own body has", () => {
  const line = unratedLine("pending");
  const example = ["## Summary", "", "```text", "Merge-Risk: max=<level> demote=<bool>", "Merge-Risk: unrated reason=<reason>", "```", "", "## Fix"].join("\n");
  assert.equal(withMergeRiskLine(example, line), `${example}\n\n${line}`);
  // A body that ends inside an open fence keeps its fenced lines too.
  const open = ["text", "```text", "Merge-Risk: max=LOW"].join("\n");
  assert.equal(withMergeRiskLine(open, line), `${open}\n\n${line}`);
  // After a closed fence, the trailing written line is still replaced.
  assert.equal(withMergeRiskLine(`${example}\n\n${unratedLine("no-run")}`, line), `${example}\n\n${line}`);
});

test("appOnlyBody holds only for a body the lanes App alone wrote, its edit list read whole", () => {
  const app = { __typename: "Bot", login: "lanes" };
  const edits = (...editors) => ({ totalCount: editors.length, nodes: editors.map((editor) => ({ editor })) });
  assert.equal(appOnlyBody({ author: app, userContentEdits: edits() }, "lanes"), true);
  assert.equal(appOnlyBody({ author: app, userContentEdits: edits(app, app) }, "lanes"), true);
  assert.equal(appOnlyBody({ author: app, userContentEdits: edits({ __typename: "User", login: "someone" }) }, "lanes"), false);
  assert.equal(appOnlyBody({ author: app, userContentEdits: edits({ __typename: "Bot", login: "other-app" }) }, "lanes"), false);
  assert.equal(appOnlyBody({ author: app, userContentEdits: edits(null) }, "lanes"), false);
  assert.equal(appOnlyBody({ author: app, userContentEdits: { totalCount: 101, nodes: [] } }, "lanes"), false);
  assert.equal(appOnlyBody({ author: app }, "lanes"), false);
  assert.equal(appOnlyBody({ author: { __typename: "User", login: "lanes" }, userContentEdits: edits() }, "lanes"), false);
  assert.equal(appOnlyBody({ author: app, userContentEdits: edits() }, undefined), false);
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

// recordMergeRisk: the arm-side step. It never throws.
const BOT = "melodic-automation-lanes";
const APP = { __typename: "Bot", login: BOT };
const pull = { number: 7, headRefOid: HEAD, body: "Closes #1\n\nbody", author: APP, userContentEdits: { totalCount: 0, nodes: [] } };
function writer({ body = pull.body, failGet = false, failPatch = false } = {}) {
  const sent = [];
  const github = async (method, path, payload) => {
    sent.push({ method, path, payload });
    if (method === "GET" && failGet) throw new Error("GET refused");
    if (method === "PATCH" && failPatch) throw new Error("PATCH refused");
    if (method === "GET") return { body };
    return {};
  };
  return { github, sent };
}

test("recordMergeRisk writes the rated line as the body's last line", async () => {
  const { actions } = fake({ artifacts: [{ id: 11, name: artifactName(7, HEAD), expired: false, workflow_run: { id: 5 } }], runs: { 5: runOf(5) } });
  const { github, sent } = writer();
  const result = await recordMergeRisk({ bot: BOT, pull, repository: REPO, actions, github, download: () => JSON.stringify(rating()) });
  assert.equal(result.token, "rated");
  assert.equal(result.wrote, true);
  const patch = sent.find((call) => call.method === "PATCH");
  assert.equal(patch.path, `/repos/${REPO}/pulls/7`);
  assert.equal(patch.payload.body, `Closes #1\n\nbody\n\n${ratedLine(rating())}`);
});

test("recordMergeRisk writes nothing when the line is already exact", async () => {
  const { actions } = fake({ listing: [runOf(5, { status: "queued", conclusion: null })] });
  const { github, sent } = writer({ body: `x\n\n${unratedLine("pending")}` });
  const result = await recordMergeRisk({ bot: BOT, pull: { ...pull, body: `x\n\n${unratedLine("pending")}` }, repository: REPO, actions, github, download: () => "" });
  assert.equal(result.wrote, false);
  assert.equal(sent.some((call) => call.method === "PATCH"), false);
});

test("recordMergeRisk neither reads nor writes a body another account edited", async () => {
  const { actions, calls } = fake({ listing: [] });
  const { github, sent } = writer();
  const edited = { ...pull, userContentEdits: { totalCount: 1, nodes: [{ editor: { __typename: "User", login: "outsider" } }] } };
  const result = await recordMergeRisk({ bot: BOT, pull: edited, repository: REPO, actions, github, download: () => "" });
  assert.deepEqual([result.token, result.wrote, result.skipped], ["skipped", false, "untrusted-body"]);
  assert.deepEqual(calls, []);
  assert.deepEqual(sent, []);
});

test("recordMergeRisk skips the write when the body changed since the listing", async () => {
  const { actions } = fake({ listing: [] });
  const { github, sent } = writer({ body: "Closes #1\n\nbody\n\ndo not merge" });
  const result = await recordMergeRisk({ bot: BOT, pull, repository: REPO, actions, github, download: () => "" });
  assert.equal(result.wrote, false);
  assert.equal(result.skipped, "body-changed");
  assert.equal(sent.some((call) => call.method === "PATCH"), false);
});

test("recordMergeRisk records unrated when every read throws, and still writes", async () => {
  const { actions } = fake({ fail: new Set(["/actions/"]) });
  const { github, sent } = writer();
  const result = await recordMergeRisk({ bot: BOT, pull, repository: REPO, actions, github, download: () => "" });
  assert.equal(result.token, "unrated:unreadable");
  assert.equal(sent.find((call) => call.method === "PATCH").payload.body.endsWith(unratedLine("unreadable")), true);
});

test("recordMergeRisk records over-budget when a read hangs past the deadline", async () => {
  const actions = () => new Promise(() => {});
  const { github, sent } = writer();
  const started = Date.now();
  const result = await recordMergeRisk({ bot: BOT, pull, repository: REPO, actions, github, download: () => "", readMs: 50, writeMs: 200 });
  assert.equal(result.token, "unrated:over-budget");
  assert.ok(Date.now() - started < 2000);
  assert.equal(sent.find((call) => call.method === "PATCH").payload.body.endsWith(unratedLine("over-budget")), true);
});

test("recordMergeRisk never throws when the GET or the PATCH fails or hangs", async () => {
  const { actions } = fake({ listing: [] });
  for (const options of [{ failGet: true }, { failPatch: true }]) {
    const { github } = writer(options);
    const result = await recordMergeRisk({ bot: BOT, pull, repository: REPO, actions, github, download: () => "" });
    assert.equal(result.wrote, false);
    assert.equal(result.skipped, "write-failed");
  }
  const hang = async (method) => (method === "GET" ? { body: pull.body } : new Promise(() => {}));
  const result = await recordMergeRisk({ bot: BOT, pull, repository: REPO, actions, github: hang, download: () => "", writeMs: 50 });
  assert.equal(result.wrote, false);
  assert.equal(result.skipped, "write-failed");
});

test("recordMergeRisk survives a throwing download and a malformed pull", async () => {
  const { actions } = fake({ artifacts: [{ id: 11, name: artifactName(7, HEAD), expired: false, workflow_run: { id: 5 } }], runs: { 5: runOf(5) } });
  const { github } = writer();
  const result = await recordMergeRisk({
    bot: BOT,
    pull,
    repository: REPO,
    actions,
    github,
    download: () => {
      throw new Error("boom");
    },
  });
  assert.equal(result.token, "unrated:unreadable");
  const bad = await recordMergeRisk({ bot: BOT, pull: { number: "x", headRefOid: "no" }, repository: REPO, actions, github, download: () => "" });
  assert.equal(bad.wrote, false);
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
