// Expected values come from the WIP cap rule: the issue lane's cap is the
// lanes App's merged pull requests per hour over the rolling window times the
// target lead time (pr-pipeline.yaml `wip`), rounded up and at least 1, with
// limits.wip-cap when the merged count cannot be read. Only open lane PRs that
// are not held count against it; a held one (needs-human, do-not-merge, or a
// body line exactly "Hold: a human merges this") counts against the held
// cap and its age alarm. Lane PRs opened in the window may be at most
// wip.opened-to-merged-ratio times those merged in it. Over a cap the check alerts; it
// pauses the lane over the WIP cap or the held cap, on or after wip.pause-from,
// and logs one `admission paused: reason=...` line (owner decision
// 2026-10-21). A read that fails keeps the last known pause, or with none
// fails open (owner decision 2026-10-21, #8804).
import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";

import { WIP_DEFAULTS } from "../../scripts/work-resolve-issue/limits.mjs";
import { isHeld, main, readLaneWip, wipStatus } from "./check-wip-cap.mjs";

const REPO = "melodic-software/claude-code-plugins";
const AUTHOR = "author:app/melodic-automation-lanes";
const NOW = Date.parse("2026-10-18T12:00:00Z");
const HOUR = 3_600_000;
const LIMITS = { "wip-cap": 12 };
const WIP = { ...WIP_DEFAULTS };

const pr = ({ labels = [], body = "", ageHours = 1 } = {}) => ({
  labels: labels.map((name) => ({ name })),
  body,
  created_at: new Date(NOW - ageHours * HOUR).toISOString(),
});

// A search API that answers by query: the open listing pages through `open`,
// the merged and opened counts answer `merged` and `admitted`; an Error
// answer throws. Each path is recorded.
function searchApi({ open = [], merged = 0, admitted = 0, incomplete = false } = {}) {
  const paths = [];
  const github = async (method, path) => {
    paths.push(`${method} ${path}`);
    const url = new URL(path, "https://api.github.com");
    const q = url.searchParams.get("q");
    const answer = q.includes("is:merged") ? merged : q.includes("created:") ? admitted : open;
    if (answer instanceof Error) {
      throw answer;
    }
    if (Array.isArray(answer)) {
      const page = Number(url.searchParams.get("page"));
      const size = Number(url.searchParams.get("per_page"));
      return { total_count: answer.length, incomplete_results: incomplete, items: answer.slice((page - 1) * size, page * size) };
    }
    return answer === null ? {} : { total_count: answer, incomplete_results: incomplete, items: [] };
  };
  return { github, paths };
}

const read = (answers, extra = {}) => readLaneWip(searchApi(answers).github, { repo: REPO, now: NOW, windowHours: 24, ...extra });
const status = (reads, wip = {}, limits = LIMITS) => wipStatus(reads, { limits, wip: { ...WIP, ...wip }, now: NOW });

test("each hold signal holds a PR: needs-human, do-not-merge, or the exact hold line in the body", () => {
  assert.equal(isHeld(pr({ labels: ["needs-human"] })), true);
  assert.equal(isHeld(pr({ labels: ["do-not-merge"] })), true);
  assert.equal(isHeld(pr({ body: "Refs: #8211\nHold: a human merges this\n\n## Summary" })), true);
  assert.equal(isHeld(pr({ body: "Refs: #8211\r\nHold: a human merges this\r\n" })), true);
});

test("near misses do not hold a PR", () => {
  assert.equal(isHeld(pr()), false);
  assert.equal(isHeld(pr({ labels: ["agent-ready", "needs-triage"] })), false);
  assert.equal(isHeld(pr({ body: "Note: Hold: a human merges this" })), false);
  assert.equal(isHeld(pr({ body: "hold: a human merges this" })), false);
  assert.equal(isHeld(pr({ body: "Hold: a human merges this." })), false);
  assert.equal(isHeld({ labels: null, body: null }), false);
});

test("the reads are three serial searches over the lanes App's PRs in this repository", async () => {
  const { github, paths } = searchApi({ open: [pr()], merged: 5, admitted: 3 });
  await readLaneWip(github, { repo: REPO, now: NOW, windowHours: 24 });
  const queries = paths.map((path) => new URL(path.slice("GET ".length), "https://api.github.com"));
  assert.ok(queries.every((url) => url.pathname === "/search/issues"));
  assert.deepEqual(
    queries.map((url) => url.searchParams.get("q")),
    [
      `repo:${REPO} is:pr is:open ${AUTHOR}`,
      `repo:${REPO} is:pr is:merged ${AUTHOR} merged:>=2026-10-17T12:00:00Z`,
      `repo:${REPO} is:pr ${AUTHOR} created:>=2026-10-17T12:00:00Z`,
    ],
  );
});

test("the open listing pages until a short page", async () => {
  const open = Array.from({ length: 150 }, () => pr());
  const { github, paths } = searchApi({ open });
  const reads = await readLaneWip(github, { repo: REPO, now: NOW, windowHours: 24 });
  assert.equal(reads.open.length, 150);
  assert.equal(paths.filter((path) => path.includes("is%3Aopen")).length, 2);
});

test("a search that answers incomplete results is an unknown read", async () => {
  const reads = await read({ open: [pr()], merged: 0, admitted: 3, incomplete: true });
  assert.deepEqual(reads, { open: null, merged: null, admitted: null });
});

test("no read is made once the rate limit has nothing left; those reads are unknown", async () => {
  const { github, paths } = searchApi({ open: [pr()], merged: 5, admitted: 3 });
  let left = 1;
  const reads = await readLaneWip(github, { repo: REPO, now: NOW, windowHours: 24, remaining: () => left-- });
  assert.equal(paths.length, 1);
  assert.equal(reads.open.length, 1);
  assert.equal(reads.merged, null);
  assert.equal(reads.admitted, null);
});

test("countable PRs are the open ones not held; held ones are counted apart", async () => {
  const open = [pr(), pr(), pr({ labels: ["needs-human"] }), pr({ labels: ["do-not-merge"] }), pr({ body: "Hold: a human merges this" })];
  const result = status(await read({ open, merged: 24 }));
  assert.equal(result.countable_lane_prs, 2);
  assert.equal(result.held_lane_prs, 3);
});

test("the cap is compared against countable PRs only", async () => {
  // 24 merged in 24 h at a 2-hour target: a cap of 2.
  const held = Array.from({ length: 10 }, () => pr({ labels: ["needs-human"] }));
  const under = status(await read({ open: [pr(), ...held], merged: 24 }));
  assert.equal(under.wip_cap, 2);
  assert.equal(under.wip_over, false);
  const at = status(await read({ open: [pr(), pr(), ...held], merged: 24 }));
  assert.equal(at.wip_over, true);
});

test("the cap is the merge rate times the target lead time, rounded up and at least 1", async () => {
  const cases = [
    [{ merged: 36 }, {}, 3],
    [{ merged: 30 }, {}, 3],
    [{ merged: 36 }, { "target-lead-time-hours": 8 }, 12],
    [{ merged: 36 }, { "merge-rate-window-hours": 12 }, 6],
    [{ merged: 0 }, {}, 1],
  ];
  for (const [answers, wip, cap] of cases) {
    const result = status(await read(answers, { windowHours: wip["merge-rate-window-hours"] ?? 24 }), wip);
    assert.equal(result.wip_cap, cap, JSON.stringify([answers, wip]));
    assert.equal(result.wip_cap_source, "computed");
  }
  assert.equal(status(await read({ merged: 36 })).merge_rate_per_hour, 1.5);
});

test("the cap never falls below wip.min-cap, so a quiet day cannot stall the lane", async () => {
  const floor = { "min-cap": 12, "pause-from": "2026-10-01" };
  for (const merged of [0, 1]) {
    const result = status(await read({ open: [pr()], merged }), floor);
    assert.equal(result.wip_cap, 12, `merged=${merged}`);
    assert.equal(result.wip_min_cap, 12);
    assert.equal(result.wip_cap_source, "computed");
    assert.equal(result.wip_over, false, `merged=${merged}`);
    assert.equal(result.paused, false, `merged=${merged}`);
  }
  assert.equal(status(await read({ merged: 300 }), floor).wip_cap, 25);
  assert.equal(status(await read({ merged: 0 })).wip_min_cap, 1);
});

test("with no merged count the cap is limits.wip-cap from config", async () => {
  for (const merged of [new Error("GET /search/issues failed with status 403"), null]) {
    const result = status(await read({ merged }));
    assert.equal(result.wip_cap, 12);
    assert.equal(result.wip_cap_source, "config");
  }
});

test("admissions may reach the admission factor times the merges, no more", async () => {
  const at = status(await read({ merged: 10, admitted: 8 }));
  assert.equal(at.admission_cap, 8);
  assert.equal(at.admission_over, false);
  assert.equal(at.alert, false);
  const over = status(await read({ merged: 10, admitted: 9 }));
  assert.equal(over.admission_over, true);
  assert.equal(over.alert, true);
  assert.equal(status(await read({ merged: 10, admitted: 9 }), { "opened-to-merged-ratio": 1 }).admission_over, false);
});

test("the held buffer has its own cap from config", async () => {
  const held = (n) => Array.from({ length: n }, () => pr({ labels: ["do-not-merge"] }));
  assert.equal(status(await read({ open: held(59), merged: 100 })).held_over, false);
  const at = status(await read({ open: held(60), merged: 100 }));
  assert.equal(at.held_cap, 60);
  assert.equal(at.held_over, true);
  assert.equal(at.alert, true);
  assert.equal(status(await read({ open: held(30), merged: 100 }), { "held-cap": 30 }).held_over, true);
});

test("a held PR older than the alarm age raises the alarm; the oldest age is reported", async () => {
  const young = status(await read({ open: [pr({ labels: ["needs-human"], ageHours: 23.5 })], merged: 100 }));
  assert.equal(young.held_over_alarm_count, 0);
  assert.equal(young.held_alarm, false);
  assert.equal(young.held_oldest_age_hours, 23.5);
  const old = status(await read({ open: [pr({ labels: ["needs-human"], ageHours: 30 }), pr({ body: "Hold: a human merges this", ageHours: 25 }), pr({ ageHours: 99 })], merged: 100 }));
  assert.equal(old.held_over_alarm_count, 2);
  assert.equal(old.held_oldest_age_hours, 30);
  assert.equal(old.held_alarm, true);
  assert.equal(old.alert, true);
  assert.equal(status(await read({ open: [pr({ labels: ["needs-human"], ageHours: 30 })], merged: 100 }), { "held-alarm-hours": 48 }).held_alarm, false);
  assert.equal(status(await read({ merged: 100 })).held_oldest_age_hours, null);
});

test("over the WIP cap the lane pauses only on or after pause-from: unset never, future not yet, past yes", async () => {
  const overWip = await read({ open: [pr(), pr(), pr()], merged: 24 });
  assert.equal(status(overWip).alert, true);
  assert.equal(status(overWip).paused, false);
  assert.equal(status(overWip, { "pause-from": "2026-10-19" }).paused, false);
  assert.equal(status(overWip, { "pause-from": "2026-10-18" }).paused, true);
  assert.equal(status(overWip, { "pause-from": "2026-10-01T00:00:00Z" }).paused, true);
  const under = await read({ open: [pr()], merged: 24 });
  assert.equal(status(under, { "pause-from": "2026-10-01" }).paused, false);
});

test("over the held cap alone the lane pauses only on or after pause-from, for reason held-cap", async () => {
  const overHeld = await read({ open: Array.from({ length: 10 }, () => pr({ labels: ["needs-human"] })), merged: 100 });
  for (const [pauseFrom, paused] of [["", false], ["2026-10-19", false], ["2026-10-18", true], ["2026-10-01T00:00:00Z", true]]) {
    const result = status(overHeld, { "held-cap": 10, "pause-from": pauseFrom });
    assert.equal(result.held_over, true, pauseFrom);
    assert.equal(result.wip_over, false, pauseFrom);
    assert.equal(result.alert, true, pauseFrom);
    assert.equal(result.paused, paused, pauseFrom);
    assert.equal(result.pause_reason, paused ? "held-cap" : null, pauseFrom);
  }
  const under = await read({ open: Array.from({ length: 9 }, () => pr({ labels: ["needs-human"] })), merged: 100 });
  assert.equal(status(under, { "held-cap": 10, "pause-from": "2026-10-01" }).paused, false);
});

test("over both caps the lane pauses for both reasons", async () => {
  const both = await read({ open: [pr(), pr(), pr(), ...Array.from({ length: 60 }, () => pr({ labels: ["needs-human"] }))], merged: 24 });
  const result = status(both, { "pause-from": "2026-10-01" });
  assert.equal(result.held_over, true);
  assert.equal(result.wip_over, true);
  assert.equal(result.paused, true);
  assert.equal(result.pause_reason, "wip,held-cap");
});

test("reads that fail never cap or pause on their own", async () => {
  const failed = new Error("GET /search/issues failed with status 502");
  const result = status(await read({ open: failed, merged: failed, admitted: failed }), { "pause-from": "2026-10-01" });
  assert.equal(result.countable_lane_prs, null);
  assert.equal(result.held_lane_prs, null);
  assert.equal(result.wip_over, false);
  assert.equal(result.held_over, false);
  assert.equal(result.paused, false);
  assert.equal(result.pause_reason, null);
});

// main against a base checkout; with no `config` it holds no schema, so the
// defaults apply. With `config` it holds this repository's files the resolver
// reads, with that pr-pipeline.yaml text.
const CONFIG = "docs/conventions/pr-pipeline.yaml";
const BASE_FILES = [
  "docs/conventions/pr-pipeline/pr-pipeline.schema.json",
  ".github/standards/github-actions-conventions/vocabulary.json",
  ".github/CODEOWNERS",
];
async function runMain(answers, extraEnv = {}, config) {
  const dir = mkdtempSync(join(tmpdir(), "check-wip-cap-"));
  const base = join(dir, "base");
  mkdirSync(base);
  if (config !== undefined) {
    for (const file of BASE_FILES) {
      mkdirSync(dirname(join(base, file)), { recursive: true });
      copyFileSync(new URL(`../../../${file}`, import.meta.url), join(base, file));
    }
    writeFileSync(join(base, CONFIG), config);
  }
  const output = join(dir, "output");
  const summary = join(dir, "summary");
  writeFileSync(output, "");
  writeFileSync(summary, "");
  const logs = [];
  const { github } = searchApi(answers);
  await main({ env: { GITHUB_REPOSITORY: REPO, BASE_PATH: base, GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: summary, ...extraEnv }, github, now: NOW, log: (line) => logs.push(line) });
  const text = readFileSync(output, "utf8");
  const value = (name) => new RegExp(`${name}<<(\\S+)\\n([\\s\\S]*?)\\n\\1`).exec(text)?.[2];
  return { capped: value("capped"), wip: JSON.parse(value("wip")), summary: readFileSync(summary, "utf8"), logs };
}

test("main publishes the status as one flat JSON object in the output, the step summary and the log", async (t) => {
  const { capped, wip, summary, logs } = await runMain({ open: [pr(), pr({ labels: ["needs-human"], ageHours: 30 })], merged: 36, admitted: 2 });
  assert.equal(capped, "false");
  for (const [key, value] of Object.entries({
    countable_lane_prs: 1,
    held_lane_prs: 1,
    held_oldest_age_hours: 30,
    held_over_alarm_count: 1,
    wip_cap: 3,
    wip_cap_source: "computed",
    held_cap: 60,
    held_alarm: true,
    alert: true,
    paused: false,
  })) {
    assert.deepEqual(wip[key], value, key);
  }
  assert.ok(Object.values(wip).every((value) => value === null || typeof value !== "object"));
  assert.ok(summary.includes(JSON.stringify(wip)));
  assert.ok(logs.some((line) => line.includes(JSON.stringify(wip))));
  assert.ok(logs.some((line) => line.startsWith("::warning title=check-wip-cap::") && line.includes("held lane PRs are older than 24 h")));
});

test("main writes capped=true only when paused", async () => {
  // With the default config pause-from is empty: over the cap it alerts, never caps.
  const over = await runMain({ open: [pr(), pr(), pr(), pr()], merged: 24 });
  assert.equal(over.wip.wip_over, true);
  assert.equal(over.capped, "false");
  assert.equal((await runMain({ open: [pr()], merged: 24 })).capped, "false");
  // The base config's past pause-from: over the cap (its min-cap floor of 12
  // here, since 24 merged would compute 2) it pauses, under it it runs.
  const repoConfig = readFileSync(new URL(`../../../${CONFIG}`, import.meta.url), "utf8");
  const config = repoConfig.replace(/^( +pause-from: ).*$/m, '$1"2026-10-01"');
  assert.notEqual(config, repoConfig.replace(/^( +pause-from: ).*$/m, '$1""'));
  const paused = await runMain({ open: Array.from({ length: 13 }, () => pr()), merged: 24 }, {}, config);
  assert.equal(paused.wip.pause_from, "2026-10-01");
  assert.equal(paused.wip.wip_min_cap, 12);
  assert.equal(paused.capped, "true");
  assert.ok(paused.logs.some((line) => line.includes("13 countable lane PRs are at or over the WIP cap of 12")));
  const line = "admission paused: reason=wip countable=13 wip_cap=12 held=0 held_cap=10";
  assert.ok(paused.logs.includes(`::notice title=admission paused::${line}`), paused.logs.join("\n"));
  assert.ok(paused.summary.includes(`\n${line}\n`));
  const running = await runMain({ open: [pr()], merged: 24 }, {}, config);
  assert.equal(running.capped, "false");
  assert.ok(!running.logs.some((l) => l.includes("admission paused")));
  assert.ok(!running.summary.includes("admission paused"));
});

test("main pauses at this repository's held cap of 10, past pause-from, and logs the pause line", async () => {
  const repoConfig = readFileSync(new URL(`../../../${CONFIG}`, import.meta.url), "utf8");
  const config = repoConfig.replace(/^( +pause-from: ).*$/m, '$1"2026-10-01"');
  const held = await runMain({ open: Array.from({ length: 10 }, () => pr({ labels: ["needs-human"] })), merged: 24 }, {}, config);
  assert.equal(held.wip.held_cap, 10);
  assert.equal(held.wip.held_over, true);
  assert.equal(held.wip.wip_over, false);
  assert.equal(held.capped, "true");
  const warning = held.logs.find((line) => line.startsWith("::warning title=check-wip-cap::") && line.includes("held cap of 10"));
  assert.ok(warning?.includes("this run starts no work and work-unblock re-fires it once under both caps"), warning);
  assert.ok(held.logs.includes("::notice title=admission paused::admission paused: reason=held-cap countable=0 wip_cap=12 held=10 held_cap=10"));
  const nine = await runMain({ open: Array.from({ length: 9 }, () => pr({ labels: ["needs-human"] })), merged: 24 }, {}, config);
  assert.equal(nine.capped, "false");
});

// The last known state is the previous run's published status, in the file
// WIP_STATE names (owner decision 2026-10-21, #8804).
const pastConfig = () =>
  readFileSync(new URL(`../../../${CONFIG}`, import.meta.url), "utf8").replace(/^( +pause-from: ).*$/m, '$1"2026-10-01"');
function stateFile(prior) {
  const path = join(mkdtempSync(join(tmpdir(), "check-wip-cap-state-")), "state.json");
  if (prior !== undefined) {
    writeFileSync(path, JSON.stringify(prior));
  }
  return path;
}
const failed = new Error("GET /search/issues failed with status 502");

test("a read that fails keeps a last known pause, and logs it as kept", async () => {
  const prior = { paused: true, pause_reason: "held-cap" };
  for (const [answers, config] of [
    [{ open: failed, merged: 24 }, pastConfig()],
    [{ open: [pr()], merged: 24 }, undefined],
  ]) {
    const path = stateFile(prior);
    const kept = await runMain(answers, { WIP_STATE: path }, config);
    assert.equal(kept.capped, "true");
    assert.equal(kept.wip.paused, true);
    assert.equal(kept.wip.pause_reason, "held-cap");
    assert.equal(kept.wip.pause_basis, "last-state");
    const line = "admission paused: reason=held-cap (read-error, kept last state)";
    assert.ok(kept.logs.includes(`::notice title=admission paused::${line}`), kept.logs.join("\n"));
    assert.ok(kept.summary.includes(`\n${line}\n`));
    assert.deepEqual(JSON.parse(readFileSync(path, "utf8")), prior);
  }
});

test("a kept pause ends when a readable config no longer pauses", async () => {
  const path = stateFile({ paused: true, pause_reason: "wip" });
  for (const from of ['""', '"2026-10-19"']) {
    const config = readFileSync(new URL(`../../../${CONFIG}`, import.meta.url), "utf8").replace(/^( +pause-from: ).*$/m, `$1${from}`);
    const open = await runMain({ open: failed, merged: 24 }, { WIP_STATE: path }, config);
    assert.equal(open.capped, "false");
    assert.equal(open.wip.pause_basis, "last-state");
    assert.ok(!open.summary.includes("admission paused"));
  }
});

test("a last known pause reason outside wip, held-cap and wip,held-cap is no prior state", async () => {
  for (const reason of ["wip\n::error::injected", "other", null]) {
    const path = stateFile({ paused: true, pause_reason: reason });
    const open = await runMain({ open: failed, merged: 24 }, { WIP_STATE: path }, pastConfig());
    assert.equal(open.capped, "false");
    assert.equal(open.wip.pause_basis, "fail-open");
    assert.ok(!open.summary.includes("admission paused"));
  }
  const kept = await runMain({ open: failed, merged: 24 }, { WIP_STATE: stateFile({ paused: true, pause_reason: "wip,held-cap" }) }, pastConfig());
  assert.equal(kept.capped, "true");
});

// Issue-event runs cannot save a default-branch cache (low-trust trigger), so
// only work-unblock's hourly schedule saves the state; pick-slot only reads.
const { parse } = createRequire(new URL("../resolve-config/package.json", import.meta.url))("yaml");
const yamlAt = (path) => parse(readFileSync(new URL(`../../../${path}`, import.meta.url), "utf8"));
const usesWip = (step) => String(step?.uses ?? "").endsWith("/.github/actions/check-wip-cap");

test("the state is saved only from work-unblock's schedule, and pick-slot only reads it", () => {
  const action = yamlAt(".github/actions/check-wip-cap/action.yml");
  assert.equal(action.inputs["save-state"].default, "false");
  const saves = action.runs.steps.filter((step) => String(step.uses ?? "").startsWith("actions/cache/save@"));
  assert.equal(saves.length, 1);
  assert.match(saves[0].if, /inputs\.save-state == 'true'/);
  const savers = [];
  for (const file of readdirSync(new URL("../../workflows/", import.meta.url)).filter((f) => /\.ya?ml$/.test(f))) {
    for (const [name, job] of Object.entries(yamlAt(`.github/workflows/${file}`).jobs ?? {})) {
      for (const step of (job.steps ?? []).filter(usesWip)) {
        if (String(step.with?.["save-state"] ?? "false") === "true") {
          savers.push({ file, name, step });
        }
      }
    }
  }
  assert.deepEqual(savers.map(({ file, name }) => `${file}:${name}`), ["work-unblock.yml:label-unblocked"]);
  assert.match(savers[0].step.if, /github\.event_name == 'schedule'/);
  const pickSlot = yamlAt(".github/workflows/work-resolve-issue.yml").jobs["pick-slot"];
  assert.equal(pickSlot["cache-mode"], "read");
  assert.equal(pickSlot.steps.filter(usesWip).length, 1);
});

test("a read that fails keeps a last known open lane open", async () => {
  const prior = { paused: false, pause_reason: null };
  const path = stateFile(prior);
  const kept = await runMain({ open: failed, merged: 24 }, { WIP_STATE: path }, pastConfig());
  assert.equal(kept.capped, "false");
  assert.equal(kept.wip.paused, false);
  assert.equal(kept.wip.pause_basis, "last-state");
  assert.ok(!kept.summary.includes("admission paused"));
  assert.deepEqual(JSON.parse(readFileSync(path, "utf8")), prior);
});

test("a read that fails with no last known state fails open", async () => {
  for (const prior of [undefined, { paused: "yes" }]) {
    const path = stateFile(prior);
    const open = await runMain({ open: failed, merged: 24 }, { WIP_STATE: path }, pastConfig());
    assert.equal(open.capped, "false");
    assert.equal(open.wip.pause_basis, "fail-open");
    assert.ok(!open.summary.includes("admission paused"));
  }
});

test("a read that succeeds saves its status as the last known state", async () => {
  const path = stateFile();
  const paused = await runMain({ open: Array.from({ length: 13 }, () => pr()), merged: 24 }, { WIP_STATE: path }, pastConfig());
  assert.equal(paused.capped, "true");
  assert.equal(paused.wip.pause_basis, "read");
  assert.deepEqual(JSON.parse(readFileSync(path, "utf8")), paused.wip);
});

test("main's warning before pause-from says the pause date is not reached", async () => {
  const repoConfig = readFileSync(new URL(`../../../${CONFIG}`, import.meta.url), "utf8");
  const config = repoConfig.replace(/^( +pause-from: ).*$/m, '$1"2026-10-19"');
  const held = await runMain({ open: Array.from({ length: 10 }, () => pr({ labels: ["needs-human"] })), merged: 24 }, {}, config);
  assert.equal(held.capped, "false");
  const warning = held.logs.find((line) => line.startsWith("::warning title=check-wip-cap::"));
  assert.ok(warning?.includes("the lane keeps running (pause-from not reached)"), warning);
});
