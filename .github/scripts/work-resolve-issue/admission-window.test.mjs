// Expected values come from the owner's admission rule (Q17/Q22,
// 2026-10-19): hourly = lane merges in the last 24 h / 24, release point =
// admission-factor x hourly x admission-window-hours (0.8 and 24 here unless a
// test sets them), admissions open while the agent-ready backlog is under the
// release point; exit 0 open, 1 held, 2 on error.
import assert from "node:assert/strict";
import { test } from "node:test";

import { main } from "./admission-window.mjs";

const REPO = "melodic-software/claude-code-plugins";
const NOW = Date.parse("2026-10-19T12:00:00.000Z");

// A gh stub answering each search by whether its query is the merged-PR one;
// it records every argument list.
function stubGh({ merged, admitted, repoView = REPO }) {
  const calls = [];
  const run = (args) => {
    calls.push(args);
    if (args[0] === "repo") {
      return repoView;
    }
    const q = args.find((a) => a.startsWith("q=")) ?? "";
    const answer = q.includes("is:merged") ? merged : admitted;
    if (answer instanceof Error) {
      throw answer;
    }
    return String(answer);
  };
  return { run, calls };
}

async function report({ merged, admitted, windowHours = 24, factor = 0.8, argv = ["--repo", REPO], repoView }) {
  const { run, calls } = stubGh({ merged, admitted, repoView });
  const lines = [];
  const errors = [];
  const code = await main({ argv, run, loadLimits: async () => ({ windowHours, factor }), now: NOW, out: (l) => lines.push(l), err: (l) => errors.push(l) });
  return { code, lines, errors, calls };
}

test("under the release point admissions are open and exit 0", async () => {
  // 36 merges: 1.5/h; release point 0.8 x 1.5 x 24 = 28.8; 20 admitted is under it.
  const { code, lines } = await report({ merged: 36, admitted: 20 });
  assert.equal(code, 0);
  assert.deepEqual(lines, ["merged24h=36 hourly=1.5 admitted=20 release_point=28.8 admissions=open allowed_per_hour=1.2"]);
});

test("at or over the release point admissions are held and exit 1", async () => {
  // 30 merges: 1.25/h; release point 0.8 x 1.25 x 24 = 24.
  assert.equal((await report({ merged: 30, admitted: 24 })).code, 1);
  const { code, lines } = await report({ merged: 30, admitted: 25 });
  assert.equal(code, 1);
  assert.deepEqual(lines, ["merged24h=30 hourly=1.25 admitted=25 release_point=24 admissions=held allowed_per_hour=1"]);
});

test("a release point that is whole by hand holds at that count", async () => {
  // 25 merges: 0.8 x 25/24 x 24 = 20, which a naive float product makes 20.000000000000004.
  const { code, lines } = await report({ merged: 25, admitted: 20 });
  assert.equal(code, 1);
  assert.deepEqual(lines, ["merged24h=25 hourly=1.04 admitted=20 release_point=20 admissions=held allowed_per_hour=0.83"]);
});

test("the window scales the release point", async () => {
  // 36 merges, window 12: 0.8 x 1.5 x 12 = 14.4; 15 admitted holds, 14 opens.
  assert.equal((await report({ merged: 36, admitted: 15, windowHours: 12 })).code, 1);
  assert.equal((await report({ merged: 36, admitted: 14, windowHours: 12 })).code, 0);
});

test("the factor scales the release point and the allowed rate", async () => {
  // 36 merges, factor 0.5: 0.5 x 1.5 x 24 = 18; 18 admitted holds, 17 opens.
  const held = await report({ merged: 36, admitted: 18, factor: 0.5 });
  assert.equal(held.code, 1);
  assert.deepEqual(held.lines, ["merged24h=36 hourly=1.5 admitted=18 release_point=18 admissions=held allowed_per_hour=0.75"]);
  assert.equal((await report({ merged: 36, admitted: 17, factor: 0.5 })).code, 0);
});

test("no merges in 24 h holds admissions even with an empty backlog", async () => {
  const { code, lines } = await report({ merged: 0, admitted: 0 });
  assert.equal(code, 1);
  assert.match(lines[0], / release_point=0 admissions=held allowed_per_hour=0$/);
});

test("the searches count the lanes App's PRs merged since now-24h and the open agent-ready issues", async () => {
  const { calls } = await report({ merged: 1, admitted: 0 });
  const queries = calls.map((args) => args.find((a) => a.startsWith("q=")));
  assert.deepEqual(queries, [
    `q=repo:${REPO} is:pr is:merged author:app/melodic-automation-lanes merged:>=2026-10-18T12:00:00Z`,
    `q=repo:${REPO} is:issue is:open label:agent-ready`,
  ]);
});

test("without --repo the repository comes from gh repo view", async () => {
  const { code, calls } = await report({ merged: 36, admitted: 0, argv: [] });
  assert.equal(code, 0);
  assert.equal(calls[0][0], "repo");
});

test("a failed gh call, an answer that is no count, or no repository exits 2 with no report line", async () => {
  for (const options of [
    { merged: new Error("HTTP 403: rate limit"), admitted: 0 },
    { merged: 36, admitted: "null" },
    { merged: "", admitted: 0 },
    { merged: 36, admitted: 0, argv: [], repoView: "" },
  ]) {
    const { code, lines, errors } = await report(options);
    assert.equal(code, 2);
    assert.deepEqual(lines, []);
    assert.equal(errors.length, 1);
  }
});

test("limits that cannot be read exit 2", async () => {
  const { run } = stubGh({ merged: 36, admitted: 0 });
  const errors = [];
  const code = await main({ argv: ["--repo", REPO], run, loadLimits: async () => { throw new Error("invalid-config"); }, now: NOW, out: () => {}, err: (l) => errors.push(l) });
  assert.equal(code, 2);
  assert.match(errors[0], /invalid-config/);
});
