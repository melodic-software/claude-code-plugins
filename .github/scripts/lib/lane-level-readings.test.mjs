import assert from "node:assert/strict";
import { test } from "node:test";

import { readingLine } from "../../actions/log-api-budget/rate-guard.mjs";
import { decide } from "./lane-level.mjs";
import { readingsOf } from "./lane-level-readings.mjs";

const AT = 1794351600;
// rate-guard.mjs readingLine: <status> <limit> <remaining> <used> <reset> <resource> <route>
const line = (status, limit, remaining, used, reset, resource = "core", route = "repos/{repo}/issues/{n}") =>
  `${status} ${limit} ${remaining} ${used} ${reset} ${resource} ${route}`;

test("the peak used of the job's core and graphql readings, with their limits", () => {
  const text = [
    line(200, 5000, 4800, 200, AT + 900),
    line(200, 5000, 4100, 900, AT + 900),
    line(200, 5000, 4300, 700, AT + 900),
    line(200, 5000, 4950, 50, AT + 900, "graphql", "graphql"),
  ].join("\n");
  assert.deepEqual(readingsOf(text, { at: AT }), {
    at: AT,
    pools: { "lanes-app": { used: 900, limit: 5000 }, graphql: { used: 50, limit: 5000 } },
    signals: [],
  });
});

test("a GET /rate_limit reading is left out, as are lines with no reading", () => {
  const text = [line(200, 5000, 4000, 1000, AT + 900), line(200, 15000, 10, 14990, AT + 900, "core", "rate_limit"), "304 na na na na na other", ""].join("\n");
  assert.deepEqual(readingsOf(text, { at: AT }).pools, { "lanes-app": { used: 1000, limit: 5000 } });
});

test("a 429, or a 403 with nothing remaining, is a limit signal with its reset; a 403 with requests left is not", () => {
  const text = [line(200, 5000, 100, 4900, AT + 300), line(403, 5000, 0, 5000, AT + 300), line(429, 5000, 0, 5000, AT + 600), line(403, 5000, 90, 4910, AT + 300)].join("\n");
  const readings = readingsOf(text, { at: AT });
  assert.deepEqual(readings.signals, ["403", "429"]);
  assert.equal(readings.reset, AT + 600);
});

test("a 429 whose response carried no rate-limit headers is still a limit signal, and decide() steps down on it", () => {
  const text = [line(200, 5000, 4900, 100, AT + 900), readingLine(429, new Headers(), "repos/{repo}/issues/{n}").trim()].join("\n");
  const readings = readingsOf(text, { at: AT });
  assert.deepEqual(readings, { at: AT, pools: { "lanes-app": { used: 100, limit: 5000 } }, signals: ["429"] });
  assert.deepEqual(decide({ level: 4, streak: 1, holdUntil: 0 }, readings, { waiting: 2, running: 4 }, {}), { level: 2, streak: 0, holdUntil: 0, reason: "step-down" });
  assert.deepEqual(readingsOf(readingLine(429, new Headers(), "other"), { at: AT }).signals, ["429"], "a lone refusal is not missing data");
});

test("no reading at all is null, so decide() holds on missing data", () => {
  assert.equal(readingsOf("", { at: AT }), null);
  assert.equal(readingsOf(line(200, 15000, 10, 14990, AT, "core", "rate_limit"), { at: AT }), null);
});
