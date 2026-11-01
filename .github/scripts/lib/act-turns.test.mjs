// Expected values come from the turn-evidence criterion: act-turns.json counts
// the execution file's assistant messages with a null parent_tool_use_id
// (main loop) and with one set (subagents), within the 32768-byte cap, and
// says when the file holds main-loop messages only.
import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { actTurns, CAP, MAIN_LOOP_ONLY, runStep, turnCounts } from "./act-turns.mjs";

const assistant = (id, parent, ...content) => ({ type: "assistant", parent_tool_use_id: parent, message: { id, content } });
const tool = { type: "tool_use", name: "Bash" };
const text = { type: "text", text: "x" };
const result = (extra = {}) => ({ type: "result", subtype: "success", is_error: false, num_turns: 140, modelUsage: { m: {} }, ...extra });

// Three main-loop messages over two model turns (m1 streamed as two
// messages), three subagent messages over two turns, and a user message.
const BOTH = [
  assistant("m1", null, text),
  assistant("m1", null, tool),
  assistant("m2", null, text),
  assistant("s1", "toolu_1", tool),
  assistant("s2", "toolu_1", text),
  assistant("s2", "toolu_1", tool),
  { type: "user", parent_tool_use_id: null, message: { content: [] } },
  result(),
];

test("a fixture with main-loop and subagent messages counts each kind", () => {
  assert.deepEqual(turnCounts(BOTH), { main_loop: 3, subagent: 3, main_loop_turns: 2, subagent_turns: 2 });
});

test("an execution file with no subagent message says it holds main-loop messages only", () => {
  const counts = turnCounts([assistant("m1", null, tool), assistant("m2", null, text), result()]);
  assert.deepEqual(counts, { main_loop: 2, subagent: 0, main_loop_turns: 2, subagent_turns: 0, note: MAIN_LOOP_ONLY });
  // A missing parent_tool_use_id is the main loop, as null is.
  assert.equal(turnCounts([{ type: "assistant", message: { id: "a" } }]).main_loop, 1);
});

test("the step writes both counts into act-turns.json and sets the turns output", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "act-turns-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, "execution.json"), JSON.stringify(BOTH));
  const outputs = {};
  const failed = [];
  const core = { info: () => {}, setOutput: (k, v) => (outputs[k] = v), setFailed: (m) => failed.push(m) };
  await runStep({ core, executionFile: join(dir, "execution.json"), replyDir: join(dir, "reply") });
  assert.deepEqual(failed, []);
  assert.equal(outputs.turns, "140");
  const recorded = JSON.parse(readFileSync(join(dir, "reply", "act-turns.json"), "utf8"));
  assert.equal(recorded.num_turns, 140);
  assert.equal(recorded.turn_counts.main_loop, 3);
  assert.equal(recorded.turn_counts.subagent, 3);
});

test("the counts survive the 32768-byte cap on a worst-case file", () => {
  const esc = (n) => "\x1b".repeat(n);
  const denials = Array.from({ length: 100 }, () => ({ tool_name: esc(1000), tool_input: { command: esc(1000) } }));
  const stderr = { type: "user", message: { content: `<local-command-stderr>${esc(5000)}` } };
  const { diag, text: written } = actTurns([...BOTH.slice(0, 6), ...Array(6).fill(stderr), result({ permission_denials: denials })]);
  assert.ok(Buffer.byteLength(written, "utf8") <= CAP, String(Buffer.byteLength(written, "utf8")));
  assert.deepEqual(JSON.parse(written).turn_counts, diag.turn_counts);
  assert.equal(diag.turn_counts.subagent, 3);
});

test("redact applies to the recorded stderr and denial inputs", () => {
  const { diag } = actTurns(
    [{ type: "user", message: { content: "<local-command-stderr>tok-123</local-command-stderr>" } }, result({ permission_denials: [{ tool_name: "Bash", tool_input: { command: "echo tok-123" } }] })],
    { redact: (s) => s.split("tok-123").join("[REDACTED]") },
  );
  assert.equal(diag.local_command_stderr[0], "<local-command-stderr>[REDACTED]</local-command-stderr>");
  assert.equal(diag.denied[0].input, "echo [REDACTED]");
});
