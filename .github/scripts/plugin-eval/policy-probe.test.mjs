// policy-probe.mjs proves the managed policy denied the probe's four reads,
// and a session that never makes them is unproven, never a policy failure:
// the workflow step stops the leg on both, so no case runs on a policy nobody
// proved. The stream shapes are stream-json's: tool_use blocks in assistant
// messages and the result's permission_denials (code.claude.com/docs/en/
// agent-sdk/typescript, "SDKResultMessage"). The step itself runs end to end
// in callers.test.mjs.
import assert from "node:assert/strict";
import { test } from "node:test";
import { judgeProbe } from "./policy-probe.mjs";

const ROOT = "/home/runner/actions-runner";
const CALLS = [
  ["Read", { file_path: "/proc/self/environ" }],
  ["Read", { file_path: `${ROOT}/.runner` }],
  ["Grep", { pattern: "policy-probe", path: "/proc/self/environ" }],
  ["Glob", { pattern: "environ", path: "/proc/self" }],
];
const stream = ({ calls = CALLS, denied = calls, subtype = "success" } = {}) =>
  [
    { type: "system", subtype: "init" },
    ...calls.map(([name, input]) => ({ type: "assistant", message: { content: [{ type: "tool_use", name, input }] } })),
    { type: "assistant", message: { content: [{ type: "text", text: "done" }] } },
    { type: "result", subtype, is_error: subtype !== "success", num_turns: 2, permission_denials: denied.map(([tool_name, tool_input]) => ({ tool_name, tool_input })) },
  ]
    .map((m) => JSON.stringify(m))
    .join("\n");

test("all four calls denied proves the policy", () => {
  const { code, line } = judgeProbe(stream(), ROOT);
  assert.equal(code, 0);
  assert.match(line, /^the managed policy denied the probe's Read, Grep and Glob calls \(probe: .* tool_calls=Read,Read,Grep,Glob denials=4 /);
});

test("a session with no tool call is unproven and runs again, never a policy failure", () => {
  const { code, line } = judgeProbe(stream({ calls: [] }), ROOT);
  assert.equal(code, 3);
  assert.match(line, /^the probe's session made no tool call, so it proved nothing about the policy \(probe: .*tool_calls=none denials=0/);
  assert.doesNotMatch(line, /did not record/);
});

test("a session that skips a call is unproven, naming the call", () => {
  const { code, line } = judgeProbe(stream({ calls: CALLS.slice(0, 3) }), ROOT);
  assert.equal(code, 3);
  assert.match(line, /^the probe's session never made its Glob of \/proc\/self, so it proved nothing/);
});

test("a call made and not denied is a policy failure", () => {
  const { code, line } = judgeProbe(stream({ denied: [CALLS[0], CALLS[1], CALLS[3]] }), ROOT);
  assert.equal(code, 1);
  assert.match(line, /^the managed policy did not record a denied Grep of \/proc\/self \(probe: /);
});

test("a session that errored before its calls is its own error, not a policy failure", () => {
  for (const text of [stream({ calls: [], subtype: "error_max_turns" }), "", "not json\n"]) {
    const { code, line } = judgeProbe(text, ROOT);
    assert.equal(code, 1);
    assert.match(line, /^the probe's session ended in error before its Read of \/proc\/self\/environ, so it proved nothing/);
  }
});

test("the facts carry no text from the stream", () => {
  const leak = JSON.stringify({ type: "result", subtype: "SECRET value", terminal_reason: "x".repeat(50), api_error_status: "sk-1", num_turns: "lots" });
  const { line } = judgeProbe(`${leak}\n[1]\n`, ROOT);
  assert.match(line, /subtype=other terminal_reason=other is_error=none api_error_status=other num_turns=other tool_calls=none denials=0 unparsable_lines=1\)$/);
});

test("a line that is not JSON cannot hide the denials", () => {
  const { code, line } = judgeProbe(`not json\n${stream()}\n`, ROOT);
  assert.equal(code, 0);
  assert.match(line, /unparsable_lines=1\)$/);
});
