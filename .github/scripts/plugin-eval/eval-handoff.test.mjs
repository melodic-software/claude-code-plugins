// eval-handoff.mjs hands an eval leg to the next credential on exactly the
// stops run-claude-cli's action.yml names: a key leg's credit stop or 401/402,
// a subscription leg's credit stop, 401/402 or limit stop when a fallback leg
// follows, and never from the fallback leg. The rule cases take their expected
// values from that description (ci-workflows .github/actions/run-claude-cli/
// action.yml at b8bdd7f, the `handoff` output). The stream cases run the real
// lane.cjs and classify.cjs, fetched at the pin the eval workflows check out;
// their messages are the observed shapes ci-workflows' classify.test.cjs
// records (CLI 2.1.302).
import assert from "node:assert/strict";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { CLASSIFIER_FILES, erroredTraces, handoffReason, judgeLegStreams, loadLauncher, withPartials } from "./eval-handoff.mjs";

test("a key leg hands off on a credit stop or a 401 or 402, never a 403 or a limit stop", () => {
  assert.equal(handoffReason("api-key", "credit-stop", 400), "credit-stop");
  assert.equal(handoffReason("api-key", "auth", 401), "auth");
  assert.equal(handoffReason("api-key", "auth", 402), "auth");
  assert.equal(handoffReason("api-key", "auth", 403), "", "a 403 stops the run");
  assert.equal(handoffReason("api-key", "auth", null), "", "auth with no status");
  assert.equal(handoffReason("api-key", "rate-limit", 429, { limitStop: true }), "");
  assert.equal(handoffReason("api-key", "", null), "");
});

test("a subscription leg hands off only when a fallback leg follows", () => {
  const ready = { fallbackReady: true };
  assert.equal(handoffReason("subscription", "rate-limit", null, { ...ready, limitStop: true }), "limit-stop");
  assert.equal(handoffReason("subscription", "rate-limit", 429, { ...ready, limitStop: false }), "", "a 429 with no rejected window");
  assert.equal(handoffReason("subscription", "other", 400, { ...ready, creditStop: true }), "credit-stop");
  assert.equal(handoffReason("subscription", "auth", 401, ready), "auth");
  assert.equal(handoffReason("subscription", "auth", 403, ready), "");
  assert.equal(handoffReason("subscription", "rate-limit", null, { fallbackReady: false, limitStop: true }), "", "no fallback leg");
  assert.equal(handoffReason("fallback", "rate-limit", null, { ...ready, limitStop: true }), "", "the fallback leg is the last");
});

test("only runs that ended with an error are judged, their traces resolved against the result file", () => {
  const result = {
    cases: [
      { arms: { with: [{ error: null, tracePath: "/k/ok.jsonl" }, { error: "API error", tracePath: "run/2.jsonl" }], without: [{ error: "timed out after 300s", tracePath: "/k/3.jsonl" }] } },
      { arms: { with: [{ error: "no trace kept" }] } },
    ],
  };
  assert.deepEqual(erroredTraces(result, "/out"), ["/out/run/2.jsonl", "/k/3.jsonl"]);
  assert.deepEqual(erroredTraces(null, "/out"), []);
});

test("the first stream that hands off decides, else the first stop class is kept", () => {
  const verdicts = { a: ["", ""], b: ["rate-limit", ""], c: ["auth", "auth"], d: ["credit-stop", "credit-stop"] };
  const launcher = {
    linesToMessages: (text) => [{ text }],
    judgeLeg: ({ executionFile }) => ({ failureClass: verdicts[JSON.parse(readFileSync(executionFile, "utf8"))[0].text][0], resets: null, messages: [{}] }),
    isCreditStop: () => false,
  };
  const key = { leg: "api-key", fallbackReady: false };
  const streams = (...names) => names.map((text) => ({ text, exitCode: 1 }));
  assert.deepEqual(judgeLegStreams(streams("a", "b"), key, launcher), { handoff: false, reason: "", laneClass: "rate-limit" });
  assert.deepEqual(judgeLegStreams(streams("a", "d", "b"), key, launcher), { handoff: true, reason: "credit-stop", laneClass: "credit-stop" });
  assert.deepEqual(judgeLegStreams(streams("a"), key, launcher), { handoff: false, reason: "", laneClass: "" });
  assert.deepEqual(judgeLegStreams([], key, launcher), { handoff: false, reason: "", laneClass: "" });
});

// The classifier the legs check out, fetched at the pin the workflows name, so
// a pin bump that reshapes judgeLeg's return (failureClass, resets, the last
// message's api_error_status) or isCreditStop fails here. The three paths are
// the legs' sparse checkout.
const workflowPins = ["maintenance-measure-skill-edit-pass.yml", "pr-run-plugin-evals.yml"].flatMap((name) => [
  ...readFileSync(new URL(`../../workflows/${name}`, import.meta.url), "utf8").matchAll(/repository: melodic-software\/ci-workflows\n\s+ref: ([0-9a-f]{40})/g),
].map((m) => m[1]));
const PIN = workflowPins[0];
const ROOT = tempDir("eval-handoff-ci-workflows-");
for (const path of CLASSIFIER_FILES) {
  const url = `https://raw.githubusercontent.com/melodic-software/ci-workflows/${PIN}/${path}`;
  const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
  assert.ok(response.ok, `${url} answered ${response.status}`);
  mkdirSync(join(ROOT, path, ".."), { recursive: true });
  writeFileSync(join(ROOT, path), await response.text());
}
const real = loadLauncher(ROOT);

test("the files eval-handoff loads are the eval legs' sparse checkout", () => {
  for (const name of ["maintenance-measure-skill-edit-pass.yml", "pr-run-plugin-evals.yml"]) {
    const sparse = [...readFileSync(new URL(`../../workflows/${name}`, import.meta.url), "utf8").matchAll(/sparse-checkout: \|\n((?: {12}\S+\n)+)/g)]
      .filter(([block]) => block.includes("run-claude-cli/lane.cjs"))
      .map(([, block]) => block.trim().split(/\s+/));
    assert.equal(sparse.length, 3, name);
    for (const paths of sparse) assert.deepEqual(paths, CLASSIFIER_FILES, name);
  }
});

// Run 42138674762: the classifier required in place climbed to the workspace
// root's package.json, which did not parse, and the leg failed before judging.
test("the classifier loads under a workspace whose root package.json does not parse", async () => {
  const { spawnSync } = await import("node:child_process");
  const ws = tempDir("eval-handoff-ws-");
  writeFileSync(join(ws, "package.json"), "not json {");
  for (const path of CLASSIFIER_FILES) {
    mkdirSync(join(ws, ".ci-workflows", path, ".."), { recursive: true });
    writeFileSync(join(ws, ".ci-workflows", path), readFileSync(join(ROOT, path)));
  }
  writeFileSync(join(ws, "probe.jsonl"), jsonl(SPEND_LIMIT));
  const r = spawnSync(process.execPath, [new URL("./eval-handoff.mjs", import.meta.url).pathname], {
    cwd: ws,
    encoding: "utf8",
    env: { PATH: process.env.PATH, LEG: "key", CI_WORKFLOWS: join(ws, ".ci-workflows"), PROBE: join(ws, "probe.jsonl"), PROBE_EXIT: "1", RESULTS: "" },
  });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, "handoff=true\nhandoff-reason=credit-stop\nlane-class=credit-stop\noutcome=failure\n");
});

// A classifier that cannot load fails the run with exit 2 and no verdict, so
// the workflow step stops the leg red rather than guessing a handoff.
test("a classifier that cannot load prints no verdict and exits 2", async () => {
  const { spawnSync } = await import("node:child_process");
  const r = spawnSync(process.execPath, [new URL("./eval-handoff.mjs", import.meta.url).pathname], {
    encoding: "utf8",
    env: { PATH: process.env.PATH, LEG: "key", CI_WORKFLOWS: tempDir("eval-handoff-empty-"), RESULTS: "" },
  });
  assert.equal(r.status, 2);
  assert.equal(r.stdout, "");
  assert.match(r.stderr, /^eval-handoff: /);
});

test("every eval leg checks out the classifier at one pin", () => {
  assert.equal(workflowPins.length, 6, "three legs in each eval workflow");
  assert.deepEqual([...new Set(workflowPins)], [PIN]);
});

test("the pinned judgeLeg returns the fields eval-handoff reads", () => {
  const dir = tempDir("eval-handoff-shape-");
  const executionFile = join(dir, "execution.json");
  writeFileSync(executionFile, JSON.stringify(real.linesToMessages(jsonl(LIMITED))));
  const judged = real.judgeLeg({ leg: { leg: "subscription" }, executionFile, exitCode: 1, timedOut: false, maxTurns: "" });
  assert.equal(judged.failureClass, "rate-limit");
  assert.equal(judged.resets, "2100-01-01T00:00:00Z");
  assert.equal(judged.messages.at(-1).api_error_status, 429);
  assert.equal(real.isCreditStop(SPEND_LIMIT, { exitCode: 1 }), true);
});
const jsonl = (messages) => messages.map((m) => JSON.stringify(m)).join("\n");

const SPEND_LIMIT_TEXT = "API Error: 400 You have reached your specified workspace API usage limits. You will regain access on 2026-11-01 at 00:00 UTC.";
const SPEND_LIMIT = [
  { type: "assistant", error: "unknown", is_api_error_message: true, api_error_status: 400, message: { model: "<synthetic>", content: [{ type: "text", text: SPEND_LIMIT_TEXT }], usage: { input_tokens: 0, output_tokens: 0 } } },
  { type: "result", subtype: "success", is_error: true, num_turns: 1, total_cost_usd: 0, api_error_status: 400, terminal_reason: "api_error", result: SPEND_LIMIT_TEXT, usage: { input_tokens: 0, output_tokens: 0 } },
];
const REJECTED_TEXT = "Invalid API key · Fix external API key";
const rejected = (status) => [
  { type: "assistant", error: "authentication_failed", is_api_error_message: true, api_error_status: status, message: { model: "<synthetic>", content: [{ type: "text", text: REJECTED_TEXT }], usage: { input_tokens: 0, output_tokens: 0 } } },
  { type: "result", subtype: "success", is_error: true, num_turns: 1, total_cost_usd: 0, api_error_status: status, terminal_reason: "api_error", result: REJECTED_TEXT, usage: { input_tokens: 0, output_tokens: 0 } },
];
// A subscription run held by a rejected five-hour window, its reset in the future.
const LIMITED = [
  { type: "system", subtype: "init" },
  { type: "rate_limit_event", rate_limit_info: { status: "rejected", resetsAt: 4102444800, rateLimitType: "five_hour" } },
  { type: "result", subtype: "success", is_error: true, num_turns: 1, api_error_status: 429, result: "limit", usage: { input_tokens: 0, output_tokens: 0 } },
];
const CLEAN = [{ type: "system", subtype: "init" }, { type: "result", subtype: "success", is_error: false, num_turns: 3 }];

test("the real classifier: a key leg's observed spend-limit stop and 401 hand off, a 403 does not", () => {
  const key = { leg: "api-key", fallbackReady: false };
  assert.deepEqual(judgeLegStreams([{ text: jsonl(SPEND_LIMIT), exitCode: 1 }], key, real), { handoff: true, reason: "credit-stop", laneClass: "credit-stop" });
  assert.deepEqual(judgeLegStreams([{ text: jsonl(rejected(401)), exitCode: 1 }], key, real), { handoff: true, reason: "auth", laneClass: "auth" });
  assert.deepEqual(judgeLegStreams([{ text: jsonl(rejected(403)), exitCode: 1 }], key, real), { handoff: false, reason: "", laneClass: "auth" });
  assert.deepEqual(judgeLegStreams([{ text: jsonl(CLEAN), exitCode: 0 }], key, real), { handoff: false, reason: "", laneClass: "" });
});

test("the real classifier: a subscription leg's limit stop and credit stop hand off to the fallback leg", () => {
  const sub = { leg: "subscription", fallbackReady: true };
  assert.deepEqual(judgeLegStreams([{ text: jsonl(LIMITED), exitCode: 1 }], sub, real), { handoff: true, reason: "limit-stop", laneClass: "rate-limit" });
  assert.equal(judgeLegStreams([{ text: jsonl(SPEND_LIMIT), exitCode: 1 }], sub, real).reason, "credit-stop");
  assert.equal(judgeLegStreams([{ text: jsonl(LIMITED), exitCode: 1 }], { leg: "subscription", fallbackReady: false }, real).handoff, false);
  assert.equal(judgeLegStreams([{ text: jsonl(LIMITED), exitCode: 1 }], { leg: "fallback", fallbackReady: true }, real).handoff, false);
});

// The partial reasons plugin-evals' results.json table lists: cost_ceiling,
// interrupted and auth_failed. Only auth_failed is the credential's stop.
const partial = (partialReason) => ({ partial: true, partialReason, cases: [{ arms: { with: [{ error: "exit 1: Not logged in · Please run /login", tracePath: "/absent/trace.jsonl" }] } }] });
const none = { handoff: false, reason: "", laneClass: "" };

test("a suite that ended auth_failed hands off as a refused credential, and never reads as success", () => {
  const results = [{ partial: false }, partial("auth_failed")];
  assert.deepEqual(withPartials(none, results, { leg: "api-key", fallbackReady: false }), { handoff: true, reason: "auth", laneClass: "auth" });
  assert.deepEqual(withPartials(none, results, { leg: "subscription", fallbackReady: true }), { handoff: true, reason: "auth", laneClass: "auth" });
  assert.deepEqual(withPartials(none, results, { leg: "subscription", fallbackReady: false }), { handoff: false, reason: "", laneClass: "auth" }, "no fallback leg");
  assert.deepEqual(withPartials(none, results, { leg: "fallback", fallbackReady: true }), { handoff: false, reason: "", laneClass: "auth" }, "the fallback leg is the last");
});

test("a suite stopped by its cost ceiling or an interrupt, or not partial, leaves the streams' verdict", () => {
  const key = { leg: "api-key", fallbackReady: false };
  for (const reason of ["cost_ceiling", "interrupted"]) assert.deepEqual(withPartials(none, [partial(reason)], key), none, reason);
  assert.deepEqual(withPartials(none, [{ partial: false, partialReason: null }, null], key), none);
  const limited = { handoff: false, reason: "", laneClass: "rate-limit" };
  assert.deepEqual(withPartials(limited, [partial("cost_ceiling")], key), limited);
  const credit = { handoff: true, reason: "credit-stop", laneClass: "credit-stop" };
  assert.deepEqual(withPartials(credit, [partial("auth_failed")], key), credit, "a stream's handoff stands");
});

test("the CLI hands a key leg off on an auth_failed suite whose runs kept no trace, and fails the fallback leg", async () => {
  const { spawnSync } = await import("node:child_process");
  const dir = tempDir("eval-handoff-auth-");
  writeFileSync(join(dir, "results.json"), JSON.stringify({ durationSeconds: 1, costUsd: 0, ...partial("auth_failed") }));
  writeFileSync(join(dir, "ceiling.json"), JSON.stringify({ durationSeconds: 1, costUsd: 5, ...partial("cost_ceiling") }));
  const run = (leg, file) =>
    spawnSync(process.execPath, [new URL("./eval-handoff.mjs", import.meta.url).pathname], {
      encoding: "utf8",
      env: { LEG: leg, FALLBACK_READY: "", CI_WORKFLOWS: ROOT, RESULTS: join(dir, file) },
    });
  assert.equal(run("key", "results.json").stdout, "handoff=true\nhandoff-reason=auth\nlane-class=auth\noutcome=failure\n");
  assert.equal(run("fallback", "results.json").stdout, "handoff=false\nhandoff-reason=\nlane-class=auth\noutcome=failure\n");
  assert.equal(run("key", "ceiling.json").stdout, "handoff=false\nhandoff-reason=\nlane-class=\noutcome=success\n");
});

test("the CLI reads the probe and the errored runs, and writes the leg's duration for the lane record", async () => {
  const { spawnSync } = await import("node:child_process");
  const dir = tempDir("eval-handoff-cli-");
  mkdirSync(join(dir, "t"));
  writeFileSync(join(dir, "probe.jsonl"), jsonl(CLEAN));
  writeFileSync(join(dir, "t/1.jsonl"), jsonl(LIMITED));
  writeFileSync(join(dir, "results.json"), JSON.stringify({ durationSeconds: 7.5, costUsd: 0.25, cases: [{ arms: { with: [{ error: "API error", tracePath: "t/1.jsonl" }] } }] }));
  writeFileSync(join(dir, "other.json"), JSON.stringify({ durationSeconds: 2.5, costUsd: 0.5, cases: [{ arms: { with: [{ error: null, tracePath: "t/1.jsonl" }] } }] }));
  const results = [join(dir, "other.json"), join(dir, "results.json"), join(dir, "absent.json")].join("\n");
  const run = (leg) =>
    spawnSync(process.execPath, [new URL("./eval-handoff.mjs", import.meta.url).pathname], {
      encoding: "utf8",
      env: { LEG: leg, FALLBACK_READY: "true", CI_WORKFLOWS: ROOT, RESULTS: results, PROBE: join(dir, "probe.jsonl"), PROBE_EXIT: "0", LEG_RESULT: join(dir, "leg.json") },
    });
  const sub = run("subscription");
  assert.equal(sub.status, 0, sub.stderr);
  assert.equal(sub.stdout, "handoff=true\nhandoff-reason=limit-stop\nlane-class=rate-limit\noutcome=failure\n");
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "leg.json"), "utf8")), [
    { type: "result", subtype: "error_during_execution", is_error: true, duration_ms: 10000, total_cost_usd: 0.75 },
  ]);
  assert.equal(run("fallback").stdout, "handoff=false\nhandoff-reason=\nlane-class=rate-limit\noutcome=failure\n");
  assert.equal(run("nope").status, 2);
});
