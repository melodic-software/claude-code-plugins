// The expected arguments come from babysit_verify_evidence.py's `evidence`
// command line (main: --repo, --base-sha, number, head) and its report line
// (Evidence.report: refusal, head, detail).
import assert from "node:assert/strict";
import { test } from "node:test";

import { VERIFY_SCRIPT, verifyCapReader } from "./verify-cap.mjs";

const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
const REPO = "melodic-software/claude-code-plugins";
const CAPPED = `fails at 3 heads (${"1".repeat(40)}, ${"2".repeat(40)}, ${"3".repeat(40)}), the cap is 3`;

function reader(done) {
  const calls = [];
  const lines = [];
  const spawn = (command, args, options) => {
    calls.push({ command, args, timeout: options.timeout });
    return done;
  };
  const read = verifyCapReader({ GITHUB_REPOSITORY: REPO }, { spawn, log: (line) => lines.push(line) });
  return { read, calls, lines };
}

const answer = (report) => ({ status: 0, stdout: `noise\n${JSON.stringify({ head: HEAD, detail: null, ...report })}\n`, stderr: "" });

test("a pull request the reader refuses verify:repeated-fail at the head is capped, with the FAILed heads", () => {
  const { read, calls } = reader(answer({ refusal: "verify:repeated-fail", detail: CAPPED }));
  assert.equal(read({ number: 42, head: HEAD, base: BASE }), `verify:repeated-fail: ${CAPPED}`);
  assert.deepEqual(
    calls.map(({ command, args }) => [command, args]),
    [["python3", [VERIFY_SCRIPT, "evidence", "--repo", REPO, "--base-sha", BASE, "42", HEAD]]],
  );
  assert.ok(calls[0].timeout > 0);
});

test("any other answer, an allow included, is not the cap", () => {
  for (const refusal of [null, "verify:fail", "verify:earlier-fail", "verify:too-old", "verify:unreadable"]) {
    const { read } = reader(answer({ refusal }));
    assert.equal(read({ number: 42, head: HEAD, base: BASE }), null, String(refusal));
  }
});

test("a read that fails, does not parse or answers for another head runs the round as before, with a warning", () => {
  for (const done of [
    { status: 1, stdout: "", stderr: "gh: rate limited" },
    { status: null, stdout: "", stderr: "", error: new Error("spawnSync python3 ETIMEDOUT") },
    { status: 0, stdout: "not json\n", stderr: "" },
    answer({ refusal: "verify:repeated-fail", head: "c".repeat(40) }),
  ]) {
    const { read, lines } = reader(done);
    assert.equal(read({ number: 42, head: HEAD, base: BASE }), null);
    assert.match(lines.join("\n"), /^::warning::#42: /m);
  }
});

test("without a base commit the reader takes its own cap default", () => {
  const { read, calls } = reader(answer({ refusal: "verify:repeated-fail" }));
  assert.equal(read({ number: 42, head: HEAD, base: undefined }), "verify:repeated-fail");
  assert.deepEqual(calls[0].args, [VERIFY_SCRIPT, "evidence", "--repo", REPO, "42", HEAD]);
});
