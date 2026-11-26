import assert from "node:assert/strict";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";

import { budgetPolicy } from "./budget-policy.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const NOW = 1_800_000_000;
const SHIPPED = JSON.parse(readFileSync(new URL("../log-api-budget/rate-limits.json", import.meta.url), "utf8"));

function files({ defaults = SHIPPED, override = null } = {}) {
  const dir = tempDir("budget-policy-");
  const defaultsPath = path.join(dir, "rate-limits.json");
  const resolvedPath = path.join(dir, "resolved.json");
  if (defaults !== null) writeFileSync(defaultsPath, typeof defaults === "string" ? defaults : JSON.stringify(defaults));
  writeFileSync(resolvedPath, JSON.stringify({ limits: { api: { "github-token": override ?? {} } } }));
  return { dir, defaultsPath, resolvedPath };
}

function policyOf(paths) {
  const lines = [];
  return { lines, policy: budgetPolicy({ ...paths, log: (line) => lines.push(line) }) };
}

test("start stops under its share and builds the decision line from the reading", async () => {
  const { dir, ...paths } = files({ defaults: { "github-token": { "start-gate": 0.1 } } });
  try {
    const { policy } = policyOf(paths);
    assert.equal(await policy.ready("start", {}), true);
    const reading = { limit: 5000, remaining: 400, reset: NOW + 600, source: "headers", header: { limit: "5000" }, core: null };
    const low = policy.decide("start", reading, NOW);
    assert.deepEqual({ ...low, line: undefined }, { stop: true, reset: NOW + 600, projected: null, why: null, line: undefined });
    assert.equal(low.line, `::notice title=start-gate::github-token start-gate=0.1 decided from headers: limit=5000 remaining=400 reset=${NOW + 600} stop=true; body core absent; headers limit=5000`);
    assert.equal(policy.decide("start", { ...reading, remaining: 600 }, NOW).stop, false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("start reads the defaults file alone, so an override of a file-only field never reaches it", async () => {
  const { dir, ...paths } = files({ override: { "start-gate": 0.9, "start-project": 0.9, "start-run-minutes": 1 } });
  try {
    const { policy } = policyOf(paths);
    assert.equal(await policy.ready("start", { project: true }), true);
    const reading = { limit: 5000, remaining: 4000, reset: NOW + 3000, source: "headers" };
    const decision = policy.decide("start", reading, NOW);
    assert.match(decision.line, new RegExp(`start-gate=${SHIPPED["github-token"]["start-gate"]} `));
    assert.match(decision.line, new RegExp(`start-run-minutes=${SHIPPED["github-token"]["start-run-minutes"]}\\)`));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("start is not ready on a missing defaults file and warns once", async () => {
  const { dir, ...paths } = files({ defaults: null });
  try {
    const { policy, lines } = policyOf(paths);
    assert.equal(await policy.ready("start", {}), false);
    assert.equal(await policy.ready("start", {}), false);
    assert.deepEqual(lines, ["::warning title=start-gate::rate-limits.json gave no start-gate share (ENOENT); the lane proceeds without a budget read"]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("defer is not ready on an unreadable defaults file, and stops on the projection when it is", async () => {
  const broken = files({ defaults: "{" });
  try {
    const { policy, lines } = policyOf(broken);
    assert.equal(await policy.ready("defer", { job: "", minutes: "" }), false);
    assert.match(lines.join("\n"), /^::warning title=defer-gate::the defer gate could not be set up \(/);
  } finally {
    rmSync(broken.dir, { recursive: true, force: true });
  }
  const { dir, ...paths } = files();
  try {
    const { policy } = policyOf(paths);
    assert.equal(await policy.ready("defer", { job: "", minutes: "" }), true);
    const hot = policy.decide("defer", { limit: 5000, remaining: 200, reset: NOW + 1800, source: "headers" }, NOW);
    assert.equal(hot.stop, true);
    assert.match(hot.line, /^::notice title=defer-gate::github-token defer decided from headers: /);
    assert.match(hot.why, /defer-project=/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("pace takes the workflow's own share from the defaults file, never from an override, and returns no line", async () => {
  const { dir, ...paths } = files({ override: { pace: 0.25, "pace-pr-merge": 0.9 } });
  try {
    const { policy } = policyOf(paths);
    assert.equal(await policy.ready("pace"), true);
    const reading = { limit: 5000, remaining: 3125, reset: NOW + 1800 };
    const merge = policy.decide("pace", reading, NOW, { workflow: "pr-merge.yml" });
    assert.deepEqual(merge, { stop: true, reset: NOW + 1800, projected: 0.25, why: null, line: null, share: SHIPPED["github-token"]["pace-pr-merge"] });
    assert.equal(policy.decide("pace", reading, NOW, { workflow: "work-unblock.yml" }).share, 0.25);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("pace falls back to the built-in limits on an unreadable defaults file and warns before any read", async () => {
  const { dir, ...paths } = files({ defaults: null });
  try {
    const { policy, lines } = policyOf(paths);
    assert.equal(await policy.ready("pace"), true);
    assert.equal(lines.length, 1);
    assert.match(lines[0], /^::warning::rate-limits\.json could not be read \(ENOENT\); planning to the built-in defaults/);
    assert.equal(policy.decide("pace", { limit: 5000, remaining: 3125, reset: NOW + 1800 }, NOW, { workflow: "pr-merge.yml" }).share, 0.3);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
