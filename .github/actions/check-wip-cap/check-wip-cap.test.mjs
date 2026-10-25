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
import { BLOCKER_READS, isHeld, main, readLaneWip, wipStatus } from "./check-wip-cap.mjs";

const REPO = "melodic-software/claude-code-plugins";
const AUTHOR = "author:app/melodic-automation-lanes";
const NOW = Date.parse("2026-10-18T12:00:00Z");
const HOUR = 3_600_000;
const LIMITS = { "wip-cap": 12 };
const WIP = { ...WIP_DEFAULTS };

const pr = ({ labels = [], body = "", ageHours = 1, number } = {}) => ({
  ...(number === undefined ? {} : { number }),
  labels: labels.map((name) => ({ name })),
  body,
  created_at: new Date(NOW - ageHours * HOUR).toISOString(),
});

// A search API that answers by query: the open listing pages through `open`,
// the queued issue listing through `queued` (issues as { number }), the
// merged and opened counts answer `merged` and `admitted`; an Error
// answer throws. A pull request read answers `heads[number]` as its head
// ref. Each path is recorded.
function searchApi({ open = [], merged = 0, admitted = 0, queued = [], incomplete = false, heads = {}, blockedBy = {} } = {}) {
  const paths = [];
  const github = async (method, path) => {
    paths.push(`${method} ${path}`);
    const url = new URL(path, "https://api.github.com");
    const deps = /^\/repos\/[^/]+\/[^/]+\/issues\/([0-9]+)\/dependencies\/blocked_by$/.exec(url.pathname);
    if (deps) {
      const answer = blockedBy[deps[1]] ?? [];
      if (answer instanceof Error) {
        throw answer;
      }
      return answer;
    }
    const pull = /^\/repos\/[^/]+\/[^/]+\/pulls\/([0-9]+)$/.exec(url.pathname);
    if (pull) {
      const head = heads[pull[1]];
      if (head instanceof Error) {
        throw head;
      }
      return { number: Number(pull[1]), head: { ref: head } };
    }
    const q = url.searchParams.get("q");
    const answer = q.includes("is:issue") ? queued : q.includes("is:merged") ? merged : q.includes("created:") ? admitted : open;
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

test("the reads are four serial searches: the lanes App's PRs, then the open agent-ready issues not held", async () => {
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
      `repo:${REPO} is:issue is:open label:agent-ready -label:needs-human -label:needs-owner-decision -label:"status: needs-decision" -label:"status: needs-info"`,
    ],
  );
});

test("the open listing pages until a short page", async () => {
  const open = Array.from({ length: 150 }, () => pr());
  const { github, paths } = searchApi({ open });
  const reads = await readLaneWip(github, { repo: REPO, now: NOW, windowHours: 24 });
  assert.equal(reads.open.length, 150);
  assert.equal(paths.filter((path) => path.includes("is%3Apr%20is%3Aopen")).length, 2);
});

test("a search that answers incomplete results is an unknown read", async () => {
  const reads = await read({ open: [pr()], merged: 0, admitted: 3, incomplete: true });
  assert.deepEqual(reads, { open: null, merged: null, admitted: null, queued: null, queuedUnlisted: null, blocked: [], searchIncomplete: true });
});

// During a GitHub search incident the API answered total_count 0 with
// incomplete_results true for a repository with about 600 open issues
// (2026-10-22). A failed read keeps admissions open; an incomplete one is
// evidence the search itself is degraded, so it closes them whatever
// pause-from says (owner decision 2026-10-22); the queued cap stays as configured.
test("an incomplete search answer closes new admissions with pause-from unset, future or past", async () => {
  const reads = await read({ open: [], merged: 0, admitted: 0, queued: [], incomplete: true });
  for (const pauseFrom of ["", "2026-10-19", "2026-10-01"]) {
    const closed = status(reads, { "pause-from": pauseFrom });
    assert.equal(closed.admission_open, false, pauseFrom);
    assert.equal(closed.admission_room, 0, pauseFrom);
    assert.equal(closed.admission_reason, "search-incomplete", pauseFrom);
    assert.equal(closed.admission_basis, "search-incomplete", pauseFrom);
    assert.equal(closed.paused, false, pauseFrom);
  }
});

test("a search answer with no incomplete_results field is a failed read, not an incomplete one", async () => {
  const reads = await read({ open: [pr()], merged: 48, queued: null });
  assert.equal(reads.searchIncomplete, false);
  const result = status(reads, { "pause-from": "2026-10-01" });
  assert.equal(result.admission_open, true);
  assert.equal(result.admission_basis, "fail-open");
});

test("no read is made once the rate limit has nothing left; those reads are unknown", async () => {
  const { github, paths } = searchApi({ open: [pr()], merged: 5, admitted: 3 });
  let left = 1;
  const reads = await readLaneWip(github, { repo: REPO, now: NOW, windowHours: 24, remaining: () => left-- });
  assert.equal(paths.length, 1);
  assert.equal(reads.open.length, 1);
  assert.equal(reads.merged, null);
  assert.equal(reads.admitted, null);
  assert.equal(reads.queued, null);
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

// Queued work (owner decision 2026-10-21, #8794): open agent-ready issues no
// open lane PR names on its first body line (`Closes #n` or `Refs: #n`, as
// report-outcome writes it) or, failing that, by its lane branch (#8965), plus
// held lane PRs. The queued cap is
// max(limits.admission-factor x lane merges per hour, limits.admission-min-per-hour)
// x wip.merge-rate-window-hours. Over it, on or after pause-from, new
// admissions pause; runs never pause on it.
const issues = (...numbers) => numbers.map((number) => ({ number }));

// A blocker as GET .../dependencies/blocked_by lists it.
const blocker = (number, { state = "open", reason = null, repo = REPO, pull } = {}) => ({
  number,
  state,
  state_reason: reason,
  repository_url: `https://api.github.com/repos/${repo}`,
  ...(pull === undefined ? {} : { pull_request: { merged_at: pull ? "2026-10-01T00:00:00Z" : null } }),
});

test("an agent-ready issue a blocker still blocks is not queued work; one whose blockers are all done is", async () => {
  const blockedBy = {
    1: [blocker(11)],
    2: [blocker(12, { state: "closed", pull: false })],
    3: [blocker(13, { state: "closed", reason: "not_planned" })],
    4: [blocker(14, { state: "closed", reason: "completed" }), blocker(15, { state: "closed", pull: true })],
    5: [],
  };
  const reads = await read({ merged: 24, queued: issues(1, 2, 3, 4, 5), blockedBy });
  // #3's blocker closed as not planned counts as done (admission's rule).
  assert.deepEqual(reads.blocked, [1, 2]);
  assert.equal(status(reads).queued_issues, 3);
});

test("blocker reads skip issues a lane PR names, stop at BLOCKER_READS, and a failed one leaves the issue queued", async () => {
  const many = Array.from({ length: BLOCKER_READS + 5 }, (_, i) => i + 1);
  const blockedBy = Object.fromEntries(many.map((n) => [n, [blocker(1000 + n)]]));
  blockedBy[2] = new Error("GET failed with status 502");
  const { github, paths } = searchApi({ open: [pr({ body: "Closes #1" })], merged: 24, queued: issues(...many), blockedBy });
  const reads = await readLaneWip(github, { repo: REPO, now: NOW, windowHours: 24 });
  const depReads = paths.filter((path) => path.includes("/dependencies/blocked_by"));
  assert.equal(depReads.length, BLOCKER_READS);
  assert.ok(!depReads.some((path) => path.includes("/issues/1/")), "a named issue costs no read");
  assert.ok(!reads.blocked.includes(2));
  // Read and blocked: 3..31; unread past the bound, and #2, stay queued.
  assert.equal(reads.blocked.length, BLOCKER_READS - 1);
  assert.equal(status(reads).queued_issues, many.length - 1 - (BLOCKER_READS - 1));
});

test("queued work is the agent-ready issues no open lane PR names first, plus the held lane PRs", async () => {
  const open = [
    pr({ body: "Closes #1\n\n## Summary" }),
    pr({ body: "Refs: #2\r\nHold: a human merges this" }),
    pr({ body: "Closes #99" }),
    pr({ body: "## Summary\nCloses #3" }),
    pr({ labels: ["needs-human"], body: "Closes #4x" }),
  ];
  const result = status(await read({ open, merged: 24, queued: issues(1, 2, 3, 4) }));
  assert.equal(result.queued_issues, 2);
  assert.equal(result.held_lane_prs, 2);
  assert.equal(result.queued_total, 4);
});

// #8965: a lane PR's head branch (work-resolve-issue/issue-<n>-<run>-<attempt>,
// as apply-issue-patch names it) names its issue too, so a person editing the
// body's first line does not leave the issue queued. Only a PR whose first
// line names no issue costs a pull request read.
test("a lane PR whose edited body names no issue still takes its issue out of the queue by its head branch", async () => {
  const open = [pr({ number: 50, body: "Closes #1" }), pr({ number: 51, body: "Edited by a person.\n\nCloses #3" })];
  const { github, paths } = searchApi({ open, merged: 24, queued: issues(1, 2, 3), heads: { 51: "work-resolve-issue/issue-3-123-1" } });
  const result = status(await readLaneWip(github, { repo: REPO, now: NOW, windowHours: 24 }));
  assert.equal(result.queued_issues, 1);
  assert.deepEqual(
    paths.filter((path) => path.includes("/pulls/")),
    [`GET /repos/${REPO}/pulls/51`],
  );
});

test("a held lane PR with an edited body counts once, as held, not again as a queued issue", async () => {
  const open = [pr({ number: 52, labels: ["needs-human"], body: "Rewritten summary" })];
  const result = status(await read({ open, merged: 24, queued: issues(7), heads: { 52: "work-resolve-issue/issue-7-9-2" } }));
  assert.equal(result.held_lane_prs, 1);
  assert.equal(result.queued_issues, 0);
  assert.equal(result.queued_total, 1);
});

test("a head branch outside the lane's shape names no issue, and a failed pull request read keeps the listing", async () => {
  const open = [pr({ number: 53, body: "x" }), pr({ number: 54, body: "y" }), pr({ number: 55, body: "z" })];
  const heads = { 53: "work-resolve-issue/issue-1-abc-1", 54: "feat/issue-2", 55: new Error("GET failed with status 502") };
  const reads = await read({ open, merged: 24, queued: issues(1, 2, 3), heads });
  assert.equal(reads.open.length, 3);
  assert.equal(status(reads).queued_issues, 3);
  assert.equal(status(reads).countable_lane_prs, 3);
});

test("the queued cap is max(factor x merges per hour, the floor) x the merge-rate window", async () => {
  const cases = [
    // 48 merged in 24 h: 2/h x 0.8 = 1.6/h over the floor of 1; x 24 h.
    [{ merged: 48 }, {}, {}, 38.4],
    // No merges: the floor of 1/h x 24 h.
    [{ merged: 0 }, {}, {}, 24],
    [{ merged: 48 }, { "admission-factor": 1, "admission-min-per-hour": 0 }, {}, 48],
    // The target lead time does not size it.
    [{ merged: 48 }, {}, { "target-lead-time-hours": 8 }, 38.4],
    // 48 merged in 12 h: 4/h x 0.5 = 2/h; x 12 h.
    [{ merged: 48 }, { "admission-factor": 0.5 }, { "merge-rate-window-hours": 12 }, 24],
    // No merged count: the floor alone.
    [{ merged: null }, { "admission-factor": 1 }, {}, 24],
  ];
  for (const [answers, limits, wip, cap] of cases) {
    const result = status(await read(answers, { windowHours: wip["merge-rate-window-hours"] ?? 24 }), wip, { ...LIMITS, ...limits });
    assert.equal(result.queued_cap, cap, JSON.stringify([answers, limits, wip]));
  }
});

test("over the queued cap new admissions pause only on or after pause-from, and runs do not", async () => {
  // No merges over a 3-hour window: the floor of 1/h x 3 h, a queued cap of 3.
  const short = { "merge-rate-window-hours": 3 };
  const over = await read({ open: [pr({ labels: ["needs-human"] })], merged: 0, queued: issues(1, 2) }, { windowHours: 3 });
  for (const [pauseFrom, open] of [["", true], ["2026-10-19", true], ["2026-10-18", false]]) {
    const result = status(over, { ...short, "pause-from": pauseFrom });
    assert.equal(result.queued_cap, 3, pauseFrom);
    assert.equal(result.queued_total, 3, pauseFrom);
    assert.equal(result.queued_over, true, pauseFrom);
    assert.equal(result.alert, true, pauseFrom);
    assert.equal(result.admission_open, open, pauseFrom);
    assert.equal(result.admission_reason, open ? null : "queued", pauseFrom);
    assert.equal(result.admission_room, open ? null : 0, pauseFrom);
    assert.equal(result.paused, false, pauseFrom);
  }
  const under = status(await read({ merged: 0, queued: issues(1, 2) }, { windowHours: 3 }), { ...short, "pause-from": "2026-10-01" });
  assert.equal(under.queued_over, false);
  assert.equal(under.admission_open, true);
  // 2 queued under 3: room for one more.
  assert.equal(under.admission_room, 1);
  // 48 merged in 24 h: a cap of 38.4, so 3 queued leave room for 36.
  assert.equal(status(await read({ merged: 48, queued: issues(1, 2, 3) }), { "pause-from": "2026-10-01" }).admission_room, 36);
});

test("past the search's 1,000-result listing, unlisted queued issues still count and admissions pause", async () => {
  // 1,050 queued issues: the search lists 1,000 (10 pages of 100) and answers
  // total_count 1,050; the 50 unlisted ones count as queued, no lane PR names
  // them. A cap above that (100/h x 24 h = 2,400) still pauses: a count the
  // listing cut short never admits.
  const queued = issues(...Array.from({ length: 1050 }, (_, i) => i + 1));
  const reads = await read({ open: [pr({ body: "Closes #1" })], merged: 0, queued });
  assert.equal(reads.queued.length, 1000);
  assert.equal(reads.queuedUnlisted, 50);
  const result = status(reads, { "pause-from": "2026-10-01" }, { ...LIMITS, "admission-min-per-hour": 100 });
  assert.equal(result.queued_cap, 2400);
  assert.equal(result.queued_issues, 1049);
  assert.equal(result.queued_truncated, true);
  assert.equal(result.queued_over, true);
  assert.equal(result.admission_open, false);
  assert.equal(result.admission_room, 0);
  const listed = status(await read({ merged: 0, queued: issues(1, 2) }), { "pause-from": "2026-10-01" });
  assert.equal(listed.queued_truncated, false);
});

test("a queued read that fails leaves admissions open and touches no run pause", async () => {
  const failed = new Error("GET /search/issues failed with status 502");
  for (const answers of [{ queued: failed }, { open: failed }]) {
    const result = status(await read({ merged: 48, ...answers }), { "pause-from": "2026-10-01" });
    assert.equal(result.queued_total, null);
    assert.equal(result.admission_open, true);
    assert.equal(result.admission_room, null);
    assert.equal(result.admission_basis, "fail-open");
  }
  assert.equal(status(await read({ merged: 48 })).admission_basis, "read");
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
  return { capped: value("capped"), admissionOpen: value("admission-open"), wip: JSON.parse(value("wip")), summary: readFileSync(summary, "utf8"), logs };
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
const unsetConfig = () =>
  readFileSync(new URL(`../../../${CONFIG}`, import.meta.url), "utf8").replace(/^( +pause-from: ).*$/m, '$1""');
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
  // Its own job: a restored cache must never reach a job that can mint
  // through the token broker (id-token) or holds a secret.
  assert.deepEqual(savers.map(({ file, name }) => `${file}:${name}`), ["work-unblock.yml:wip-state"]);
  const saver = yamlAt(".github/workflows/work-unblock.yml").jobs["wip-state"];
  assert.match(saver.if, /github\.event_name == 'schedule'/);
  assert.deepEqual(saver.permissions, { contents: "read", "pull-requests": "read", issues: "read" });
  assert.ok(!JSON.stringify(saver).includes("secrets."));
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

test("main pauses new admissions over this repository's queued cap past pause-from, and not the run", async () => {
  // This repository's limits (factor 0.8, floor 1/h) and 24-hour window: 24
  // merged is 0.8/h under the floor, so the cap is 24. Twenty-three queued
  // issues and one held PR make 24.
  const open = [pr({ labels: ["needs-human"], body: "Closes #9" })];
  const queued = issues(...Array.from({ length: 23 }, (_, i) => 100 + i));
  const over = await runMain({ open, merged: 24, queued }, {}, pastConfig());
  assert.equal(over.capped, "false");
  assert.equal(over.admissionOpen, "false");
  assert.equal(over.wip.queued_cap, 24);
  const line = "admission paused: reason=queued queued=23 held=1 cap=24";
  assert.ok(over.logs.includes(`::notice title=admission paused::${line}`), over.logs.join("\n"));
  assert.ok(over.summary.includes(`\n${line}\n`));
  const under = await runMain({ open, merged: 24, queued: [] }, {}, pastConfig());
  assert.equal(under.admissionOpen, "true");
  assert.ok(!under.logs.some((l) => l.includes("admission paused")));
});

test("main closes new admissions and warns when the search answers incomplete results, under this repository's own pause-from", async () => {
  const repoConfig = readFileSync(new URL(`../../../${CONFIG}`, import.meta.url), "utf8");
  for (const config of [repoConfig, pastConfig()]) {
    const result = await runMain({ open: [], merged: 0, admitted: 0, queued: [], incomplete: true }, {}, config);
    assert.equal(result.admissionOpen, "false");
    assert.equal(result.wip.admission_basis, "search-incomplete");
    const warning = result.logs.find((line) => line.includes("search-incomplete"));
    assert.ok(warning?.startsWith("::warning title=check-wip-cap::"), result.logs.join("\n"));
    assert.ok(warning.includes("no new admissions are made this run"), warning);
    assert.ok(result.logs.includes("::notice title=admission paused::admission paused: reason=search-incomplete queued=null held=null cap=24"), result.logs.join("\n"));
  }
});

test("over a cap with an unreadable base config the warning names the config, not pause-from", async () => {
  const held = await runMain({ open: Array.from({ length: 60 }, () => pr({ labels: ["needs-human"] })), merged: 24 });
  const warning = held.logs.find((line) => line.startsWith("::warning title=check-wip-cap::60 held"));
  assert.ok(warning?.includes("the lane keeps running (the base config could not be read, so the defaults apply)"), held.logs.join("\n"));
  const unset = await runMain(
    { open: Array.from({ length: 60 }, () => pr({ labels: ["needs-human"] })), merged: 24 },
    {},
    unsetConfig(),
  );
  const unsetWarning = unset.logs.find((line) => line.startsWith("::warning title=check-wip-cap::"));
  assert.ok(unsetWarning?.includes("the lane keeps running (pause-from is not set)"), unset.logs.join("\n"));
});

test("a queued read that fails keeps the run's read basis and leaves admissions open", async () => {
  const failed = new Error("GET /search/issues failed with status 502");
  const result = await runMain({ open: [pr()], merged: 24, queued: failed }, { WIP_STATE: stateFile() }, pastConfig());
  assert.equal(result.wip.pause_basis, "read");
  assert.equal(result.admissionOpen, "true");
  assert.equal(result.wip.admission_basis, "fail-open");
});
