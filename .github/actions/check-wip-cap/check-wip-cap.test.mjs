// Expected values come from the WIP cap rule: the issue lane's cap is the
// lanes App's merged pull requests per hour over the rolling window times the
// target lead time (pr-pipeline.yaml `wip`), rounded up and at least 1, with
// limits.wip-cap when the merged count cannot be read. Only open lane PRs that
// are not held count against it; a held one (needs-human, do-not-merge, or a
// body line exactly "Hold: a human merges this") counts against the held
// cap and its age alarm. Lane PRs opened in the window may be at most
// admission-factor times those merged in it. Over a cap the check alerts; it
// pauses the lane only on or after wip.pause-from. A read that fails never
// caps.
import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
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
function searchApi({ open = [], merged = 0, admitted = 0 } = {}) {
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
      return { total_count: answer.length, items: answer.slice((page - 1) * size, page * size) };
    }
    return answer === null ? {} : { total_count: answer, items: [] };
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
  assert.equal(status(await read({ merged: 10, admitted: 9 }), { "admission-factor": 1 }).admission_over, false);
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

test("over a cap the lane pauses only on or after pause-from: unset never, future not yet, past yes", async () => {
  const overWip = await read({ open: [pr(), pr(), pr()], merged: 24 });
  const overHeld = await read({ open: Array.from({ length: 60 }, () => pr({ labels: ["needs-human"] })), merged: 100 });
  for (const reads of [overWip, overHeld]) {
    assert.equal(status(reads).alert, true);
    assert.equal(status(reads).paused, false);
    assert.equal(status(reads, { "pause-from": "2026-10-19" }).paused, false);
    assert.equal(status(reads, { "pause-from": "2026-10-18" }).paused, true);
    assert.equal(status(reads, { "pause-from": "2026-10-01T00:00:00Z" }).paused, true);
  }
  const under = await read({ open: [pr()], merged: 24 });
  assert.equal(status(under, { "pause-from": "2026-10-01" }).paused, false);
});

test("reads that fail never cap or pause", async () => {
  const failed = new Error("GET /search/issues failed with status 502");
  const result = status(await read({ open: failed, merged: failed, admitted: failed }), { "pause-from": "2026-10-01" });
  assert.equal(result.countable_lane_prs, null);
  assert.equal(result.held_lane_prs, null);
  assert.equal(result.wip_over, false);
  assert.equal(result.held_over, false);
  assert.equal(result.paused, false);
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
  // The base config's past pause-from: over the cap it pauses, under it it runs.
  const repoConfig = readFileSync(new URL(`../../../${CONFIG}`, import.meta.url), "utf8");
  const config = repoConfig.replace(/^( +pause-from: ).*$/m, '$1"2026-10-01"');
  assert.notEqual(config, repoConfig.replace(/^( +pause-from: ).*$/m, '$1""'));
  const paused = await runMain({ open: [pr(), pr(), pr(), pr()], merged: 24 }, {}, config);
  assert.equal(paused.wip.pause_from, "2026-10-01");
  assert.equal(paused.capped, "true");
  assert.ok(paused.logs.some((line) => line.includes("4 countable lane PRs are at or over the WIP cap of 2")));
  assert.equal((await runMain({ open: [pr()], merged: 24 }, {}, config)).capped, "false");
});
