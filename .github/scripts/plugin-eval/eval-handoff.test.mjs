// eval-handoff.mjs hands an eval leg to the next credential on exactly the
// stops run-claude-cli's action.yml names: a key leg's credit stop or 401/402,
// a subscription leg's credit stop, 401/402 or limit stop when a fallback leg
// follows, and never from the fallback leg. The rule cases take their expected
// values from that description (ci-workflows .github/actions/run-claude-cli/
// action.yml at b8bdd7f, the `handoff` output). The stream cases run the real
// lane.cjs and classify.cjs when EVAL_HANDOFF_CI_WORKFLOWS names a ci-workflows
// checkout at that pin; their messages are the observed shapes ci-workflows'
// classify.test.cjs records (CLI 2.1.302).
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { erroredTraces, handoffReason, judgeLegStreams } from "./eval-handoff.mjs";

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

const ROOT = process.env.EVAL_HANDOFF_CI_WORKFLOWS ?? "";
const real = ROOT === "" ? null : (() => {
  const require = createRequire(join(ROOT, ".github/actions/run-claude-cli/lane.cjs"));
  const { judgeLeg, linesToMessages } = require("./lane.cjs");
  const { isCreditStop } = require("../report-lane-outcome/classify.cjs");
  return { judgeLeg, linesToMessages, isCreditStop };
})();
const skip = real === null ? "set EVAL_HANDOFF_CI_WORKFLOWS to a ci-workflows checkout at the run-claude-cli pin" : false;
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

test("the real classifier: a key leg's observed spend-limit stop and 401 hand off, a 403 does not", { skip }, () => {
  const key = { leg: "api-key", fallbackReady: false };
  assert.deepEqual(judgeLegStreams([{ text: jsonl(SPEND_LIMIT), exitCode: 1 }], key, real), { handoff: true, reason: "credit-stop", laneClass: "credit-stop" });
  assert.deepEqual(judgeLegStreams([{ text: jsonl(rejected(401)), exitCode: 1 }], key, real), { handoff: true, reason: "auth", laneClass: "auth" });
  assert.deepEqual(judgeLegStreams([{ text: jsonl(rejected(403)), exitCode: 1 }], key, real), { handoff: false, reason: "", laneClass: "auth" });
  assert.deepEqual(judgeLegStreams([{ text: jsonl(CLEAN), exitCode: 0 }], key, real), { handoff: false, reason: "", laneClass: "" });
});

test("the real classifier: a subscription leg's limit stop and credit stop hand off to the fallback leg", { skip }, () => {
  const sub = { leg: "subscription", fallbackReady: true };
  assert.deepEqual(judgeLegStreams([{ text: jsonl(LIMITED), exitCode: 1 }], sub, real), { handoff: true, reason: "limit-stop", laneClass: "rate-limit" });
  assert.equal(judgeLegStreams([{ text: jsonl(SPEND_LIMIT), exitCode: 1 }], sub, real).reason, "credit-stop");
  assert.equal(judgeLegStreams([{ text: jsonl(LIMITED), exitCode: 1 }], { leg: "subscription", fallbackReady: false }, real).handoff, false);
  assert.equal(judgeLegStreams([{ text: jsonl(LIMITED), exitCode: 1 }], { leg: "fallback", fallbackReady: true }, real).handoff, false);
});

test("the CLI reads the probe and the errored runs, and writes the leg's duration for the lane record", { skip }, async () => {
  const { spawnSync } = await import("node:child_process");
  const dir = mkdtempSync(join(tmpdir(), "eval-handoff-cli-"));
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
