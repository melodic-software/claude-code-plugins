import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { lastMessage } from "./last-messages.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const run = (...args) => spawnSync(process.execPath, [join(HERE, "last-messages.mjs"), ...args], { encoding: "utf8" });
const jsonl = (...lines) => lines.map((line) => JSON.stringify(line)).join("\n");
const said = (text) => ({ type: "assistant", message: { content: [{ type: "text", text }] } });

function suite(...replies) {
  const dir = tempDir("last-messages-");
  const runs = replies.map((reply, index) => {
    if (reply === null) return { score: 0 };
    writeFileSync(join(dir, `t${index}.jsonl`), jsonl(said("working"), { type: "result", result: reply }));
    return { score: 1, tracePath: `t${index}.jsonl` };
  });
  writeFileSync(join(dir, "results.json"), JSON.stringify({ cases: [{ name: "c1", arms: { with: runs, without: [{ score: 0 }] } }] }));
  return dir;
}

test("the result event's text is the reply, ahead of any assistant text", () => {
  assert.equal(lastMessage([said("first"), { type: "result", result: "final" }, said("after")]), "final");
});

test("without a result event the last assistant text is the reply, its text parts joined", () => {
  const tool = { type: "assistant", message: { content: [{ type: "tool_use", name: "Read" }] } };
  const parts = { type: "assistant", message: { content: [{ type: "text", text: "a" }, { type: "text", text: "b" }] } };
  assert.equal(lastMessage([said("early"), parts, tool]), "a\nb");
  assert.equal(lastMessage([tool]), null);
});

test("a clean result writes one line per run with the reply, and prints no reply", () => {
  const dir = suite("The test passes.", null);
  const out = join(dir, "last-messages.jsonl");
  const result = run(join(dir, "results.json"), out);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(readFileSync(out, "utf8").trim().split("\n").map((line) => JSON.parse(line)), [
    { case: "c1", arm: "with", run: 1, last_message: "The test passes." },
    { case: "c1", arm: "with", run: 2, last_message: null },
    { case: "c1", arm: "without", run: 1, last_message: null },
  ]);
  assert.doesNotMatch(result.stdout + result.stderr, /The test passes/);
});

test("a reply the leak scan blocks withholds the whole file with a warning naming only the rule", () => {
  const key = `sk-ant-${"x".repeat(30)}`;
  const dir = suite("clean reply", `here is ${key}`);
  const out = join(dir, "last-messages.jsonl");
  const result = run(join(dir, "results.json"), out);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(out), false);
  assert.match(result.stdout, /^::warning title=Eval replies withheld::The leak scan matched Anthropic key in the /m);
  assert.doesNotMatch(result.stdout + result.stderr, /sk-ant-|clean reply/);
});

test("an unreadable result or a wrong argument count exits 2 and writes nothing", () => {
  const dir = tempDir("last-messages-");
  const out = join(dir, "last-messages.jsonl");
  assert.equal(run(join(dir, "missing.json"), out).status, 2);
  assert.equal(run(join(dir, "missing.json")).status, 2);
  assert.equal(existsSync(out), false);
});
