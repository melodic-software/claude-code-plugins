// The burn-rate pacer's rules (pace.mjs): a timer-driven run is paced when
// the GITHUB_TOKEN pool's remaining at its reset, projected at the burn rate
// the window has shown so far, falls under `pace` of the header's limit, the
// share the breaker is also stated in (pr-pipeline.schema.json api-pool).
// Expected values are worked by hand from limit, remaining and reset.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { main, paceDecision } from "./pace.mjs";
import { apiLimits } from "./rate-guard.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const NOW = 1_800_000_000;

test("the pace share is a config value: rate-limits.json's github-token default, under limits.api", () => {
  assert.equal(apiLimits({ resolvedPath: "" })["github-token"].pace, 0.2);
  const dir = tempDir("pace-config-");
  const resolved = join(dir, "resolved.json");
  writeFileSync(resolved, JSON.stringify({ limits: { api: { "github-token": { pace: 0.35 } } } }));
  assert.equal(apiLimits({ resolvedPath: resolved })["github-token"].pace, 0.35);
  // The schema lets limits.api set it, in the same range as the breaker.
  const schema = JSON.parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json", import.meta.url), "utf8"));
  assert.deepEqual(
    { ...schema.$defs["api-pool"].properties.pace, description: undefined },
    { ...schema.$defs["api-pool"].properties.breaker, description: undefined },
  );
});

test("a run is paced when the projected remaining at reset falls under the share", () => {
  // 30 minutes in: 2,000 of 5,000 used, so 2,000 more by the reset leaves 1,000, 20%.
  const half = { limit: 5000, remaining: 3000, reset: NOW + 1800 };
  assert.deepEqual(paceDecision(half, 0.2, NOW), { paced: false, projected: 0.2 });
  // 2,100 used: 2,100 more leaves 800, 16%.
  assert.deepEqual(paceDecision({ ...half, remaining: 2900 }, 0.2, NOW), { paced: true, projected: 0.16 });
  // The evidence window's reading: used 4,289, remaining 711, about 4 minutes to reset.
  assert.equal(paceDecision({ limit: 5000, remaining: 711, reset: NOW + 252 }, 0.2, NOW).paced, true);
  // A slow burn early in the window: 100 used in 10 minutes projects 500 more, 4,400 left.
  assert.deepEqual(paceDecision({ limit: 5000, remaining: 4900, reset: NOW + 3000 }, 0.2, NOW), { paced: false, projected: 0.88 });
  // A projection under zero is clamped to it.
  assert.deepEqual(paceDecision({ limit: 1000, remaining: 100, reset: NOW + 1800 }, 0.2, NOW), { paced: true, projected: 0 });
});

test("the first minute projects nothing, so only the remaining itself can pace it", () => {
  assert.deepEqual(paceDecision({ limit: 5000, remaining: 4000, reset: NOW + 3590 }, 0.2, NOW), { paced: false, projected: 0.8 });
  assert.deepEqual(paceDecision({ limit: 5000, remaining: 900, reset: NOW + 3590 }, 0.2, NOW), { paced: true, projected: 0.18 });
});

test("a reading that cannot project, or a share of 0, never paces", () => {
  for (const reading of [{}, { limit: 0, remaining: 0, reset: NOW + 60 }, { limit: 5000, remaining: "na", reset: NOW + 60 }, { limit: 5000, remaining: 100, reset: NOW - 10 }, { limit: 5000, remaining: 6000, reset: NOW + 60 }]) {
    assert.equal(paceDecision(reading, 0.2, NOW).paced, false, JSON.stringify(reading));
  }
  assert.equal(paceDecision({ limit: 5000, remaining: 10, reset: NOW + 1800 }, 0, NOW).paced, false);
});

// main's one read: a 200 answer's x-ratelimit headers.
const answer = (headers, status = 200) => async () => new Response("{}", { status, headers });
const run = async (env, fetchImpl) => {
  const dir = tempDir("pace-");
  const output = join(dir, "output");
  writeFileSync(output, "");
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    await main({ GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: output, RUNNER_TEMP: dir, EVENT_NAME: "schedule", RUN_NUMBER: "42", ...env }, { fetchImpl, now: () => NOW });
  } finally {
    console.log = log;
  }
  return { output: readFileSync(output, "utf8"), lines };
};

test("on a schedule tick main reads the pool once and writes paced, with a notice", async () => {
  let calls = 0;
  const fetchImpl = async (...args) => {
    calls += 1;
    return answer({ "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "2900", "x-ratelimit-used": "2100", "x-ratelimit-reset": String(NOW + 1800), "x-ratelimit-resource": "core" })(...args);
  };
  const got = await run({}, fetchImpl);
  assert.equal(calls, 1);
  assert.equal(got.output, "paced=true\n");
  assert.deepEqual(got.lines, ["::notice title=api-pace::github-token projected=0.16 pace=0.2 paced=true; this tick skips its work"]);
});

// Pacing halves a lane's cadence rather than stopping it: a paced
// projection still runs the odd-numbered ticks, so the lost-run reconciler
// keeps re-running lost runs while the pool recovers.
test("a paced projection skips only the even-numbered ticks", async () => {
  const low = answer({ "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "2900", "x-ratelimit-reset": String(NOW + 1800) });
  assert.equal((await run({ RUN_NUMBER: "42" }, low)).output, "paced=true\n");
  const odd = await run({ RUN_NUMBER: "43" }, low);
  assert.equal(odd.output, "paced=false\n");
  assert.deepEqual(odd.lines, ["::notice title=api-pace::github-token projected=0.16 pace=0.2 paced=false; an odd tick runs at half cadence"]);
  // A run number that is no number runs the tick.
  for (const number of ["", "4x", "-2"]) {
    assert.equal((await run({ RUN_NUMBER: number }, low)).output, "paced=false\n", JSON.stringify(number));
  }
});

test("any other event, an unreadable answer or a failed read is never paced", async () => {
  let calls = 0;
  const counting = async () => {
    calls += 1;
    return new Response("{}", { status: 200 });
  };
  assert.equal((await run({ EVENT_NAME: "workflow_dispatch" }, counting)).output, "paced=false\n");
  assert.equal((await run({ EVENT_NAME: "push" }, counting)).output, "paced=false\n");
  assert.equal(calls, 0, "no read off a schedule tick");
  assert.equal((await run({}, counting)).output, "paced=false\n", "no headers");
  assert.equal((await run({}, answer({}, 502))).output, "paced=false\n");
  const throws = async () => {
    throw new Error("down");
  };
  const failed = await run({}, throws);
  assert.equal(failed.output, "paced=false\n");
  assert.match(failed.lines.join("\n"), /::warning::/);
});

// The timer-driven lanes that read the pacer: each reads it once on the
// event, never fails on it, and gates every step that spends the pool.
test("each paced timer lane reads the pacer before its work and gates every spending step on it", () => {
  const lanes = {
    "maintenance-reconcile-lost-runs.yml": { job: "reconcile", gated: ["Find lost runs", "Re-run lost runs"] },
    "pr-unblock-dispatch.yml": { job: "dispatch", gated: ["Install resolve-config's dependencies", "Restore the dispatch record", "Dispatch pr-unblock for conflicting, review-tier Dependabot, failing lanes App and Markdown-changing PRs"] },
  };
  for (const [file, { job, gated }] of Object.entries(lanes)) {
    const text = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
    const block = new RegExp(`\\n  ${job}:\\n([\\s\\S]*?)(?=\\n  [a-z0-9-]+:\\n|$)`).exec(text)?.[1] ?? "";
    // Less the blank and comment lines that lead into the next step.
    const steps = block.split(/\n(?= {6}- name: )/).slice(1).map((s) => ({ name: /^ {6}- name: (.*)$/m.exec(s)[1], s: s.replace(/(\n *(#[^\n]*)?)+$/, "") }));
    const at = (name) => steps.findIndex((step) => step.name === name);
    const pace = steps[at("Pace the tick on the GITHUB_TOKEN burn rate")]?.s ?? "";
    assert.match(pace, /\n {8}id: pace\n/, file);
    assert.match(pace, /\n {8}continue-on-error: true\n/, file);
    assert.match(pace, /\n {10}EVENT_NAME: \$\{\{ github\.event_name \}\}\n/, file);
    assert.match(pace, /\n {10}RUN_NUMBER: \$\{\{ github\.run_number \}\}\n/, file);
    assert.match(pace, /\n {8}run: node \.base\/\.github\/actions\/log-api-budget\/pace\.mjs\n?$/, file);
    for (const name of gated) {
      assert.ok(at(name) > at("Pace the tick on the GITHUB_TOKEN burn rate"), `${file}: ${name} follows the pacer`);
      assert.match(steps[at(name)].s, /steps\.pace\.outputs\.paced != 'true'/, `${file}: ${name}`);
    }
  }
});
