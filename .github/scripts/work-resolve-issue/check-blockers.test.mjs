import assert from "node:assert/strict";
import { test } from "node:test";

import { main } from "./check-blockers.mjs";

const ENV = { GITHUB_REPOSITORY: "o/r", ISSUE_NUMBER: "42" };
const issue = (number, state, repo = "o/r") => ({ number, state, repository_url: `https://api.github.com/repos/${repo}` });

async function run(answer, env = ENV) {
  const calls = [];
  const lines = [];
  const outputs = {};
  const github = async (method, path) => {
    calls.push(`${method} ${path}`);
    return answer(path);
  };
  const code = await main({ env, github, log: (line) => lines.push(line), write: (values) => Object.assign(outputs, values) });
  return { code, calls, lines, outputs };
}

test("an open blocker skips the run with a notice naming it, and writes nothing", async () => {
  const { code, calls, lines, outputs } = await run(() => [issue(7, "open"), issue(8, "closed"), issue(9, "open", "o/other")]);
  assert.equal(code, 0);
  assert.deepEqual(outputs, { proceed: "false" });
  assert.ok(calls.every((call) => call.startsWith("GET /repos/o/r/issues/42/dependencies/blocked_by")));
  const notice = lines.find((line) => line.startsWith("::notice"));
  assert.match(notice, /#7/);
  assert.match(notice, /o\/other#9/);
  assert.doesNotMatch(notice, /#8\b/);
});

test("every blocker closed, or none, runs", async () => {
  assert.deepEqual((await run(() => [issue(8, "closed")])).outputs, { proceed: "true" });
  assert.deepEqual((await run(() => [])).outputs, { proceed: "true" });
});

test("a blocker list it cannot read skips the run with a warning and exits 0", async () => {
  const { code, lines, outputs } = await run(() => {
    throw new Error("GET failed: 502");
  });
  assert.equal(code, 0);
  assert.deepEqual(outputs, { proceed: "false" });
  assert.ok(lines.some((line) => line.startsWith("::warning")));
});

test("an issue number that is not one skips the run with a warning and reads nothing", async () => {
  const { code, calls, lines, outputs } = await run(() => [], { ...ENV, ISSUE_NUMBER: "1; rm" });
  assert.equal(code, 0);
  assert.deepEqual(calls, []);
  assert.deepEqual(outputs, { proceed: "false" });
  assert.ok(lines.some((line) => line.startsWith("::warning")));
});
