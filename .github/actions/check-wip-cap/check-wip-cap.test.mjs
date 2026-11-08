// Expected values come from the WIP cap rule: the issue lane's cap is the
// lanes App's merged pull requests per hour over the rolling window times the
// target lead time (pr-pipeline.yaml `wip`), rounded up and at least 1, with
// limits.wip-cap when the merged count cannot be read. Only open lane PRs that
// are not held count against it; a held one (needs-human or do-not-merge in
// any case, or a body line exactly "Hold: a human merges this") counts against the held
// cap and its age alarm. Lane PRs opened in the window may be at most
// wip.opened-to-merged-ratio times those merged in it. Over a cap the check alerts; it
// pauses the lane over the WIP cap or the held cap, on or after wip.pause-from,
// and logs one `admission paused: reason=...` line (owner decision
// 2026-10-21). A read the pause depends on that fails (the open listing, the
// base config, not the merged count) makes the pause unknown, so the run holds:
// `capped` true with one notice, and no stored state decides it (outage
// posture elements 2 and 3, #12283).
import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { test } from "node:test";

import { WIP_DEFAULTS } from "../../scripts/work-resolve-issue/limits.mjs";
import { BLOCKER_READS, isHeld, listedStatusOf, main, readLaneWip, wipStatus } from "./check-wip-cap.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { HUMAN_ID, mirroredStatusOf, STATUS_CONFIG, STRANGER_ID, TRUSTED_ACTORS, withFields } from "../resolve-config/read-status.fixtures.mjs";
import { statusReader } from "../resolve-config/read-status.mjs";

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
// the merged and opened counts answer `merged` and `admitted`; an Error
// answer throws. The repository issues listing pages through `queued` (issues
// as { number, labels?, pull_request? }); null answers no list, and page
// `failQueuedPage` throws. A pull request read answers `heads[number]` as its
// head ref. Each path is recorded.
function searchApi({ open = [], merged = 0, admitted = 0, queued = [], incomplete = false, heads = {}, blockedBy = {}, failQueuedPage = null } = {}) {
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
    if (/^\/repos\/[^/]+\/[^/]+\/issues$/.test(url.pathname)) {
      const page = Number(url.searchParams.get("page"));
      if (queued instanceof Error) {
        throw queued;
      }
      if (page === failQueuedPage) {
        throw new Error(`GET ${path} failed with status 502`);
      }
      if (!Array.isArray(queued)) {
        return {};
      }
      const size = Number(url.searchParams.get("per_page"));
      return queued.slice((page - 1) * size, page * size);
    }
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

// pr-merge's holdReason matches hold labels ignoring case, so the WIP count
// does too; the body line stays exact.
test("a hold label holds a PR in any case", () => {
  assert.equal(isHeld(pr({ labels: ["Needs-Human"] })), true);
  assert.equal(isHeld(pr({ labels: ["Do-Not-Merge"] })), true);
  assert.equal(isHeld(pr({ labels: ["DO-NOT-MERGE"] })), true);
});

test("a label with a missing or non-string name is no hold and does not throw", () => {
  assert.equal(isHeld({ labels: [null, {}, { name: null }, { name: 7 }, { name: ["needs-human"] }] }), false);
});

test("near misses do not hold a PR", () => {
  assert.equal(isHeld(pr()), false);
  assert.equal(isHeld(pr({ labels: ["agent-ready", "needs-triage"] })), false);
  assert.equal(isHeld(pr({ body: "Note: Hold: a human merges this" })), false);
  assert.equal(isHeld(pr({ body: "hold: a human merges this" })), false);
  assert.equal(isHeld(pr({ body: "Hold: a human merges this." })), false);
  assert.equal(isHeld({ labels: null, body: null }), false);
});

test("the reads are three serial searches for the lanes App's PRs, then the issues listing of open agent-ready issues, oldest first", async () => {
  const { github, paths } = searchApi({ open: [pr()], merged: 5, admitted: 3 });
  await readLaneWip(github, { repo: REPO, now: NOW, windowHours: 24 });
  const queries = paths.map((path) => new URL(path.slice("GET ".length), "https://api.github.com"));
  assert.equal(queries.length, 4);
  assert.ok(queries.slice(0, 3).every((url) => url.pathname === "/search/issues"));
  assert.deepEqual(
    queries.slice(0, 3).map((url) => url.searchParams.get("q")),
    [
      `repo:${REPO} is:pr is:open ${AUTHOR}`,
      `repo:${REPO} is:pr is:merged ${AUTHOR} merged:>=2026-10-17T12:00:00Z`,
      `repo:${REPO} is:pr ${AUTHOR} created:>=2026-10-17T12:00:00Z`,
    ],
  );
  assert.equal(queries[3].pathname, `/repos/${REPO}/issues`);
  assert.deepEqual(Object.fromEntries(queries[3].searchParams), { labels: "agent-ready", state: "open", sort: "created", direction: "asc", per_page: "100", page: "1" });
});

// The search index carries no recency guarantee, and admit.mjs counts its
// racing admissions against this count, so the queued issues come from the
// repository issues listing. It lists pull requests too
// (https://docs.github.com/en/rest/issues/issues#list-repository-issues) and
// takes no label exclusion, so both are left out client-side.
test("the queued listing leaves out pull requests and hold labels in any case, in listing order", async () => {
  const queued = [
    { number: 1 },
    { number: 2, pull_request: {} },
    { number: 3, labels: [{ name: "needs-human" }] },
    { number: 4, labels: [{ name: "Status: Needs-Decision" }] },
    { number: 5, labels: [{ name: "needs-owner-decision" }] },
    { number: 6, labels: [{ name: "status: needs-info" }] },
    { number: 7, labels: [{ name: "agent-ready" }, { name: "priority: high" }, null, { name: 7 }] },
    { number: 8, labels: [{ name: "status: ready" }] },
    { number: 9, labels: [{ name: "Host-Run" }] },
    { number: 10, labels: [{ name: "attended" }] },
  ];
  const reads = await read({ merged: 24, queued });
  assert.deepEqual(reads.queued, [1, 7, 8]);
  assert.equal(reads.queuedUnlisted, 0);
  assert.equal(status(reads).queued_issues, 3);
});

// The Work status field a trusted account set (read-status.mjs): with a status
// label on the issue it only adds a hold; with none it decides; unset, the labels decide.
const fieldRead = (fields, queued) => {
  const { github } = searchApi({ merged: 24, queued });
  const fielded = withFields(github, fields);
  const statusOf = statusReader({ github: fielded, repository: REPO, config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: () => {} });
  return readLaneWip(fielded, { repo: REPO, now: NOW, windowHours: 24, statusOf });
};

test("a field that mirrors the labels changes no queued answer", async () => {
  const queued = [
    { number: 1 },
    { number: 2, pull_request: {} },
    { number: 3, labels: [{ name: "needs-human" }] },
    { number: 4, labels: [{ name: "Status: Needs-Decision" }] },
    { number: 5, labels: [{ name: "needs-owner-decision" }] },
    { number: 6, labels: [{ name: "status: needs-info" }] },
    { number: 7, labels: [{ name: "agent-ready" }, { name: "priority: high" }, null, { name: 7 }] },
    { number: 8, labels: [{ name: "status: ready" }] },
    { number: 9, labels: [{ name: "agent-ready" }, { name: "needs-spec" }] },
  ];
  const reads = await read({ merged: 24, queued }, { statusOf: mirroredStatusOf });
  // #9's labels collapse to needs-spec, a hold state, and a field at a state
  // other than agent-ready drops the agent-ready label.
  assert.deepEqual(reads.queued, [1, 7, 8]);
});

test("a hold in the Work status field the labels lack keeps an issue out of the queue", async () => {
  const queued = [
    { number: 1, labels: [{ name: "agent-ready" }] },
    { number: 2, labels: [{ name: "agent-ready" }, { name: "needs-human" }] },
    { number: 3, labels: [{ name: "agent-ready" }] },
  ];
  const reads = await fieldRead({ 1: { state: "needs-human" }, 2: { state: "agent-ready" } }, queued);
  assert.deepEqual(reads.queued, [3]);
});

// The listing names only agent-ready issues, so every listed one carries a
// status label: the field never decides alone here.
test("a queued issue whose Work status field is unset, or set by another account, is judged by its labels", async () => {
  const queued = [
    { number: 1, labels: [{ name: "agent-ready" }] },
    { number: 2, labels: [{ name: "agent-ready" }] },
  ];
  const reads = await fieldRead({ 2: { state: "needs-human", setter: STRANGER_ID } }, queued);
  assert.deepEqual(reads.queued, [1, 2]);
});

test("a queued issue whose Work status field read fails counts as queued", async () => {
  const queued = [
    { number: 1, labels: [{ name: "agent-ready" }] },
    { number: 2, labels: [{ name: "agent-ready" }] },
    { number: 3, labels: [{ name: "agent-ready" }] },
  ];
  const reads = await fieldRead({ 2: new Error("HTTP 502"), 3: { state: "needs-human" } }, queued);
  assert.deepEqual(reads.queued, [1, 2]);
  assert.equal(reads.queuedUnlisted, 0);
});

// The Work status listing (resolve-config.mjs issuesByStatus) as listedStatusOf
// reads it: `issues` as {number, createdAt, labels, field?: {state, setter?}},
// the setter defaulting to the listed human. The label listing must not be read.
const fieldListing = (issues, { fail = false } = {}) => {
  const { github, paths } = searchApi({ merged: 24, queued: new Error("the label listing was read") });
  const field = { fullDatabaseId: String(STATUS_CONFIG["field-id"]) };
  const listed = async (method, path, body) => {
    if (method === "POST" && path === "/graphql" && /issues\(states: OPEN/.test(body?.query ?? "")) {
      if (fail) throw new Error("GraphQL answered 502");
      const nodes = issues.map((i) => ({
        number: i.number,
        createdAt: i.createdAt,
        labels: { nodes: (i.labels ?? []).map((name) => ({ name })) },
        issueFieldValues: { nodes: i.field ? [{ name: i.field.state, field }] : [] },
        timelineItems: { nodes: i.field ? [{ __typename: "IssueFieldChangedEvent", newValue: i.field.state, actor: { databaseId: i.field.setter ?? HUMAN_ID }, issueField: field }] : [] },
      }));
      return { data: { repository: { issues: { pageInfo: { hasNextPage: false, endCursor: null }, nodes } } } };
    }
    return github(method, path, body);
  };
  const statusOf = listedStatusOf({ github: listed, repository: REPO, config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS });
  return { paths, reads: () => readLaneWip(listed, { repo: REPO, now: NOW, windowHours: 24, statusOf }) };
};

test("with a Work status listing, the field decides which issues are queued, oldest first, holds left out", async () => {
  const { reads, paths } = fieldListing([
    { number: 5, createdAt: "2026-10-03T00:00:00Z", field: { state: "agent-ready" } },
    { number: 1, createdAt: "2026-10-01T00:00:00Z", field: { state: "agent-ready" } },
    { number: 2, createdAt: "2026-10-02T00:00:00Z", labels: ["agent-ready"], field: { state: "confirmed" } },
    { number: 3, createdAt: "2026-10-02T00:00:00Z", labels: ["agent-ready"] },
    { number: 4, createdAt: "2026-10-04T00:00:00Z", labels: ["needs-human"], field: { state: "agent-ready" } },
    { number: 6, createdAt: "2026-10-05T00:00:00Z", labels: ["agent-ready"], field: { state: "needs-spec" } },
    { number: 7, createdAt: "2026-10-06T00:00:00Z", field: { state: "agent-ready", setter: STRANGER_ID } },
  ]);
  const result = await reads();
  assert.deepEqual(result.queued, [1, 3, 5]);
  assert.equal(result.queuedUnlisted, 0);
  assert.equal(paths.filter((path) => path.startsWith(`GET /repos/${REPO}/issues?`)).length, 0);
});

test("a Work status listing that fails leaves the queued count unread", async () => {
  const { reads } = fieldListing([{ number: 1, createdAt: "2026-10-01T00:00:00Z", field: { state: "agent-ready" } }], { fail: true });
  assert.equal((await reads()).queued, null);
});

test("the queued listing pages until a short page, counting pull requests toward the page size", async () => {
  const queued = Array.from({ length: 150 }, (_, i) => (i % 10 === 0 ? { number: i + 1, pull_request: {} } : { number: i + 1 }));
  const { github, paths } = searchApi({ merged: 24, queued });
  const reads = await readLaneWip(github, { repo: REPO, now: NOW, windowHours: 24 });
  assert.equal(paths.filter((path) => path.startsWith(`GET /repos/${REPO}/issues?`)).length, 2);
  assert.equal(reads.queued.length, 135);
  assert.deepEqual(reads.queued.slice(0, 3), [2, 3, 4]);
});

test("a failed page or an answer that is no list leaves the queued count unread, so admissions read fail-open", async () => {
  const many = Array.from({ length: 150 }, (_, i) => ({ number: i + 1 }));
  for (const answers of [{ queued: many, failQueuedPage: 2 }, { queued: many, failQueuedPage: 1 }, { queued: null }]) {
    const reads = await read({ merged: 24, ...answers });
    assert.equal(reads.queued, null, JSON.stringify(answers.failQueuedPage));
    assert.equal(reads.searchIncomplete, false);
    const result = status(reads, { "pause-from": "2026-10-01" });
    assert.equal(result.queued_issues, null);
    assert.equal(result.admission_basis, "fail-open");
  }
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
  // The queued listing is no search, so it still reads.
  assert.deepEqual(reads, { open: null, merged: null, admitted: null, queued: [], queuedUnlisted: 0, blocked: [], searchIncomplete: true });
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

// A broken dependency or config file leaves the default limits, so the caps
// are unknown: admissions close whatever pause-from says, as on an incomplete
// search, and the run pause is unchanged.
test("an unreadable base config closes new admissions with pause-from unset, future or past", async () => {
  const reads = await read({ open: [pr()], merged: 24, admitted: 0, queued: [] });
  for (const pauseFrom of ["", "2026-10-19", "2026-10-01"]) {
    const closed = wipStatus(reads, { limits: LIMITS, wip: { ...WIP, "pause-from": pauseFrom }, now: NOW, configError: true });
    assert.equal(closed.admission_open, false, pauseFrom);
    assert.equal(closed.admission_room, 0, pauseFrom);
    assert.equal(closed.admission_reason, "config-unreadable", pauseFrom);
    assert.equal(closed.admission_basis, "config-unreadable", pauseFrom);
    assert.equal(closed.paused, status(reads, { "pause-from": pauseFrom }).paused, pauseFrom);
  }
});

test("a search answer with no incomplete_results field is a failed read, not an incomplete one", async () => {
  const reads = await read({ open: null, merged: 48 });
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

test("past the listing's 10 pages, an unlisted queued issue still counts and admissions pause", async () => {
  // 1,050 queued issues: the listing stops at 1,000 (10 pages of 100) and
  // answers no count, so a full last page counts one more as queued, no lane
  // PR naming it. A cap above that (100/h x 24 h = 2,400) still pauses: a
  // count the listing cut short never admits.
  const queued = issues(...Array.from({ length: 1050 }, (_, i) => i + 1));
  const reads = await read({ open: [pr({ body: "Closes #1" })], merged: 0, queued });
  assert.equal(reads.queued.length, 1000);
  assert.equal(reads.queuedUnlisted, 1);
  const result = status(reads, { "pause-from": "2026-10-01" }, { ...LIMITS, "admission-min-per-hour": 100 });
  assert.equal(result.queued_cap, 2400);
  assert.equal(result.queued_issues, 1000);
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
  ".github/standards/trusted-actors/trusted-actors.json",
];
async function runMain(answers, extraEnv = {}, config) {
  const dir = tempDir("check-wip-cap-");
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
  const { github, paths } = searchApi(answers);
  // The one open-issues listing the Work status states and the queued issues
  // come from answers `answers.listed` (issue nodes), by default the issues of
  // `answers.queued` with the agent-ready label and no field value (an Error
  // fails it), and stays out of `paths`.
  const fromQueued = () =>
    (Array.isArray(answers.queued) ? answers.queued : [])
      .filter((item) => !item.pull_request)
      .map((item) => ({ number: item.number, createdAt: "2026-10-01T00:00:00Z", labels: { nodes: [...(item.labels ?? []), { name: "agent-ready" }] }, issueFieldValues: { nodes: [] }, timelineItems: { nodes: [] } }));
  const listed = async (method, path, body, ...rest) => {
    if (method === "POST" && path === "/graphql" && String(body?.query).includes("issues(states: OPEN")) {
      if (answers.queued instanceof Error) throw answers.queued;
      return { data: { repository: { issues: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: answers.listed ?? fromQueued() } } } };
    }
    return github(method, path, body, ...rest);
  };
  await main({ env: { GITHUB_REPOSITORY: REPO, BASE_PATH: base, GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: summary, ...extraEnv }, github: listed, now: NOW, log: (line) => logs.push(line) });
  const text = readFileSync(output, "utf8");
  const value = (name) => new RegExp(`${name}<<(\\S+)\\n([\\s\\S]*?)\\n\\1`).exec(text)?.[2];
  return { capped: value("capped"), held: value("held"), admissionOpen: value("admission-open"), wip: JSON.parse(value("wip")), output: text, summary: readFileSync(summary, "utf8"), logs, paths };
}


test("main publishes the status as one flat JSON object in the output, the step summary and the log", async (t) => {
  const { capped, wip, summary, logs } = await runMain({ open: [pr(), pr({ labels: ["needs-human"], ageHours: 30 })], merged: 36, admitted: 2 });
  // No base config here, so the pause is unknown and the run holds.
  assert.equal(capped, "true");
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
  // With pause-from empty, over the cap (its min-cap floor of 24) it alerts, never caps.
  const over = await runMain({ open: Array.from({ length: 25 }, () => pr()), merged: 24 }, {}, unsetConfig());
  assert.equal(over.wip.wip_over, true);
  assert.equal(over.capped, "false");
  assert.equal((await runMain({ open: [pr()], merged: 24 }, {}, unsetConfig())).capped, "false");
  // The base config's past pause-from: over the cap (its min-cap floor of 24
  // here, since 24 merged would compute 2) it pauses, under it it runs.
  const repoConfig = readFileSync(new URL(`../../../${CONFIG}`, import.meta.url), "utf8");
  const config = repoConfig.replace(/^( +pause-from: ).*$/m, '$1"2026-10-01"');
  assert.notEqual(config, repoConfig.replace(/^( +pause-from: ).*$/m, '$1""'));
  const paused = await runMain({ open: Array.from({ length: 25 }, () => pr()), merged: 24 }, {}, config);
  assert.equal(paused.wip.pause_from, "2026-10-01");
  assert.equal(paused.wip.wip_min_cap, 24);
  assert.equal(paused.capped, "true");
  // A pause that was read is no hold, so pick-slot still reads the dimensions.
  assert.equal(paused.held, "false");
  assert.ok(paused.logs.some((line) => line.includes("25 countable lane PRs are at or over the WIP cap of 24")));
  const line = "admission paused: reason=wip countable=25 wip_cap=24 held=0 held_cap=10";
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
  assert.ok(held.logs.includes("::notice title=admission paused::admission paused: reason=held-cap countable=0 wip_cap=24 held=10 held_cap=10"));
  const nine = await runMain({ open: Array.from({ length: 9 }, () => pr({ labels: ["needs-human"] })), merged: 24 }, {}, config);
  assert.equal(nine.capped, "false");
});

const pastConfig = () =>
  readFileSync(new URL(`../../../${CONFIG}`, import.meta.url), "utf8").replace(/^( +pause-from: ).*$/m, '$1"2026-10-01"');
const unsetConfig = () =>
  readFileSync(new URL(`../../../${CONFIG}`, import.meta.url), "utf8").replace(/^( +pause-from: ).*$/m, '$1""');
const failed = new Error("GET /search/issues failed with status 502");
const HOLD = "::notice title=WIP cap hold::";

// Outage posture element 2 (#12283): a read the pause depends on that fails,
// or a search that answers incomplete, makes the pause unknown, so the run
// holds with one notice whatever the reads that succeeded say, and the step
// still exits 0. Sixty held PRs are over the default held cap of 60, so the
// config case would pause on its own; the hold names the unread config
// instead of a pause line.
test("a read the pause depends on that fails holds the run with one notice", async () => {
  for (const [answers, config, unread] of [
    [{ open: failed, merged: 24 }, pastConfig(), "the open lane PRs could not be listed"],
    [{ open: failed, merged: failed }, unsetConfig(), "the open lane PRs could not be listed"],
    [{ open: [pr()], merged: 24, incomplete: true }, pastConfig(), "the open lane PRs could not be listed"],
    [{ open: [pr()], merged: 24 }, undefined, "the base config could not be read"],
    [{ open: Array.from({ length: 60 }, () => pr({ labels: ["needs-human"] })), merged: 24 }, undefined, "the base config could not be read"],
  ]) {
    const held = await runMain(answers, {}, config);
    assert.equal(held.capped, "true", unread);
    assert.equal(held.held, "true", unread);
    assert.equal(held.wip.pause_basis, "unknown", unread);
    const notices = held.logs.filter((line) => line.startsWith(HOLD));
    assert.equal(notices.length, 1, held.logs.join("\n"));
    assert.ok(notices[0].startsWith(`${HOLD}WIP cap hold: ${unread}, so the pause is unknown and this run starts no work`), notices[0]);
    assert.ok(held.summary.includes(`\nWIP cap hold: ${unread}, `), held.summary);
    assert.ok(!held.logs.some((line) => /admission paused: reason=(wip|held-cap|null)/.test(line)), held.logs.join("\n"));
    assert.ok(!held.logs.some((line) => line.startsWith("::error")), held.logs.join("\n"));
  }
});

// A merged count that cannot be read is no hold: the cap is this
// repository's limits.wip-cap of 24, so 24 countable PRs past pause-from
// pause and 23 run, both read.
test("a failed merged count decides the pause from limits.wip-cap, with no hold", async () => {
  for (const [count, capped] of [[24, "true"], [23, "false"]]) {
    const result = await runMain({ open: Array.from({ length: count }, () => pr()), merged: failed }, {}, pastConfig());
    assert.equal(result.capped, capped, String(count));
    assert.equal(result.wip.wip_cap, 24);
    assert.equal(result.wip.wip_cap_source, "config");
    assert.equal(result.wip.merged_lane_prs_window, null);
    assert.equal(result.wip.pause_basis, "read");
    assert.ok(!result.logs.some((line) => line.includes("WIP cap hold")), result.logs.join("\n"));
  }
});

test("reads that succeed decide the pause and name no hold", async () => {
  for (const [answers, capped] of [
    [{ open: [pr()], merged: 24 }, "false"],
    [{ open: Array.from({ length: 25 }, () => pr()), merged: 24 }, "true"],
  ]) {
    const result = await runMain(answers, {}, pastConfig());
    assert.equal(result.capped, capped);
    assert.equal(result.wip.pause_basis, "read");
    assert.ok(!result.logs.some((line) => line.includes("WIP cap hold")), result.logs.join("\n"));
  }
});

// Outage posture element 3: no earlier run's state decides the pause. A state
// file left where the action used to restore one changes nothing either way,
// and the check never writes it.
test("a stored state decides nothing and is never written", async () => {
  const path = join(tempDir("check-wip-cap-state-"), "state.json");
  for (const [prior, answers, capped] of [
    [{ paused: false, pause_reason: null }, { open: failed, merged: 24 }, "true"],
    [{ paused: true, pause_reason: "wip" }, { open: [pr()], merged: 24 }, "false"],
    [{ paused: false, pause_reason: null }, { open: Array.from({ length: 25 }, () => pr()), merged: 24 }, "true"],
  ]) {
    const text = JSON.stringify(prior);
    writeFileSync(path, text);
    const result = await runMain(answers, { WIP_STATE: path }, pastConfig());
    assert.equal(result.capped, capped, text);
    assert.equal(readFileSync(path, "utf8"), text);
    assert.doesNotMatch(result.output, /state-saved/);
  }
});

const { parse } = createRequire(new URL("../resolve-config/package.json", import.meta.url))("yaml");
const yamlAt = (path) => parse(readFileSync(new URL(`../../../${path}`, import.meta.url), "utf8"));
const usesWip = (step) => String(step?.uses ?? "").endsWith("/.github/actions/check-wip-cap");

test("no workflow restores or saves a WIP cap state, and pick-slot runs the check once", () => {
  const action = yamlAt(".github/actions/check-wip-cap/action.yml");
  assert.equal(action.inputs["save-state"], undefined);
  assert.equal(action.outputs["state-saved"], undefined);
  assert.ok(!action.runs.steps.some((step) => /^actions\/cache/.test(String(step.uses ?? ""))));
  const callers = [];
  for (const file of readdirSync(new URL("../../workflows/", import.meta.url)).filter((f) => /\.ya?ml$/.test(f))) {
    const text = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
    assert.doesNotMatch(text, /check-wip-cap-state/, file);
    for (const [name, job] of Object.entries(parse(text).jobs ?? {})) {
      for (const step of (job.steps ?? []).filter(usesWip)) {
        assert.equal(step.with?.["save-state"], undefined, `${file}:${name}`);
        callers.push(`${file}:${name}`);
      }
    }
  }
  assert.deepEqual(callers, ["work-resolve-issue.yml:pick-slot"]);
  const pickSlot = yamlAt(".github/workflows/work-resolve-issue.yml").jobs["pick-slot"];
  assert.equal(pickSlot["cache-mode"], "read");
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

test("over a cap with an unreadable base config the warning names the hold, not pause-from", async () => {
  const held = await runMain({ open: Array.from({ length: 60 }, () => pr({ labels: ["needs-human"] })), merged: 24 });
  const warning = held.logs.find((line) => line.startsWith("::warning title=check-wip-cap::60 held"));
  assert.ok(warning?.endsWith("; this run holds on the unknown pause"), held.logs.join("\n"));
  assert.equal(held.capped, "true");
  const unset = await runMain(
    { open: Array.from({ length: 60 }, () => pr({ labels: ["needs-human"] })), merged: 24 },
    {},
    unsetConfig(),
  );
  const unsetWarning = unset.logs.find((line) => line.startsWith("::warning title=check-wip-cap::"));
  assert.ok(unsetWarning?.includes("the lane keeps running (pause-from is not set)"), unset.logs.join("\n"));
});

test("main closes new admissions and warns when the base config cannot be read, and holds the run", async () => {
  const result = await runMain({ open: [pr()], merged: 24, admitted: 0, queued: [] });
  assert.equal(result.admissionOpen, "false");
  assert.equal(result.wip.admission_reason, "config-unreadable");
  assert.equal(result.wip.admission_basis, "config-unreadable");
  const warning = result.logs.find((line) => line.includes("admission_basis config-unreadable"));
  assert.ok(warning?.startsWith("::warning title=check-wip-cap::"), result.logs.join("\n"));
  assert.ok(warning.includes("no new admissions are made this run"), warning);
  assert.ok(result.logs.some((line) => line.startsWith("::notice title=admission paused::admission paused: reason=config-unreadable")), result.logs.join("\n"));
  assert.equal(result.capped, "true");
  assert.equal(result.wip.pause_basis, "unknown");
});

// The queued listing feeds admission-open alone, so its failure is no hold.
test("a queued read that fails keeps the run's read basis and leaves admissions open", async () => {
  const failed = new Error("GET /search/issues failed with status 502");
  const result = await runMain({ open: [pr()], merged: 24, queued: failed }, {}, pastConfig());
  assert.equal(result.capped, "false");
  assert.equal(result.wip.pause_basis, "read");
  assert.equal(result.admissionOpen, "true");
  assert.equal(result.wip.admission_basis, "fail-open");
});

// pick-slot reads only `capped`, which the open listing and the merged count
// decide; the admitted count, the queued listing, its pull request reads and
// its blocker reads feed admission-open alone. With WIP_READS=pause the check
// makes those two searches and nothing else, whatever the queue holds.
const queuedIssues = (n) => Array.from({ length: n }, (_, i) => ({ number: 500 + i }));

test("pause reads make exactly two searches however many issues are queued", async () => {
  const lanePrs = [pr({ number: 1, body: "edited by a person" }), pr({ number: 2, body: "Closes #500" })];
  for (const n of [0, 19, 40]) {
    const answers = { open: lanePrs, merged: 24, admitted: 9, queued: queuedIssues(n), heads: { 1: "work-resolve-issue/issue-501-1-1" } };
    const full = await runMain(answers, {}, pastConfig());
    const paused = await runMain(answers, { WIP_READS: "pause" }, pastConfig());
    assert.equal(paused.paths.length, 2, paused.paths.join("\n"));
    assert.deepEqual(
      paused.paths.map((path) => new URL(path.slice("GET ".length), "https://api.github.com").searchParams.get("q")),
      [`repo:${REPO} is:pr is:open ${AUTHOR}`, `repo:${REPO} is:pr is:merged ${AUTHOR} merged:>=2026-10-17T12:00:00Z`],
    );
    // Full reads: three searches (the Work status listing stays out of `paths`), one pull request
    // read when issues are queued, and one blocker read per queued issue no lane PR names, at most BLOCKER_READS.
    const named = n === 0 ? 0 : 2;
    assert.equal(full.paths.length, 3 + (n === 0 ? 0 : 1) + Math.min(Math.max(n - named, 0), BLOCKER_READS));
  }
});

// A listing node whose Work status a listed human (trusted-actors.json) set.
const listedNode = (number, state) => ({
  number,
  createdAt: "2026-10-01T00:00:00Z",
  labels: { nodes: [{ name: "agent-ready" }] },
  issueFieldValues: { nodes: [{ name: state, field: { fullDatabaseId: String(STATUS_CONFIG["field-id"]) } }] },
  timelineItems: {
    nodes: [{ __typename: "IssueFieldAddedEvent", createdAt: "2026-10-01T00:00:00Z", value: state, actor: { __typename: "User", login: "kyle-sexton", databaseId: 153232337 }, issueField: { fullDatabaseId: String(STATUS_CONFIG["field-id"]) } }],
  },
});

// One listing gives every queued issue its Work status, so a queue longer
// than any per-issue read limit has no tail read as unheld or as queued.
test("a field-only hold keeps each of 60 queued issues out of the count, the last as the first", async () => {
  const queued = queuedIssues(60);
  const listed = queued.map(({ number }) => listedNode(number, number % 2 === 0 ? "needs-human" : "agent-ready"));
  const result = await runMain({ open: [], merged: 24, admitted: 0, queued, listed }, {}, pastConfig());
  assert.equal(result.wip.queued_issues, 30, "every odd-numbered issue queued, every even one held, past issue 530 too");
});

test("pause reads decide capped, the pause reason and its basis as full reads do", async () => {
  const cases = [
    { open: [pr()], merged: 24 },
    { open: Array.from({ length: 25 }, () => pr()), merged: 24 },
    { open: Array.from({ length: 10 }, () => pr({ labels: ["needs-human"], ageHours: 30 })), merged: 24 },
    { open: [...Array.from({ length: 25 }, () => pr()), ...Array.from({ length: 10 }, () => pr({ body: "Hold: a human merges this" }))], merged: 24 },
    { open: Array.from({ length: 25 }, () => pr()), merged: failed },
    { open: failed, merged: 24 },
    { open: [pr()], merged: 24, incomplete: true },
  ];
  for (const [i, answers] of cases.entries()) {
    for (const config of [pastConfig(), undefined]) {
      const full = await runMain({ ...answers, admitted: 50, queued: queuedIssues(5) }, {}, config);
      const paused = await runMain({ ...answers, admitted: 50, queued: queuedIssues(5) }, { WIP_READS: "pause" }, config);
      const label = `case ${i}, ${config === undefined ? "missing" : "past"} config`;
      assert.equal(paused.capped, full.capped, label);
      for (const field of ["paused", "pause_reason", "pause_basis", "countable_lane_prs", "held_lane_prs", "wip_cap", "wip_over", "held_over", "held_alarm"]) {
        assert.deepEqual(paused.wip[field], full.wip[field], `${label}: ${field}`);
      }
    }
  }
});

test("pause reads say the admission counts were not read, and leave admissions open", async () => {
  const { admissionOpen, wip } = await runMain({ open: [pr()], merged: 24, admitted: 50, queued: queuedIssues(60) }, { WIP_READS: "pause" }, pastConfig());
  assert.equal(admissionOpen, "true");
  assert.equal(wip.admission_basis, "not-read");
  assert.equal(wip.admitted_lane_prs_window, null);
  assert.equal(wip.queued_issues, null);
  assert.equal(wip.admission_over, false);
  assert.equal(wip.queued_over, false);
});

test("pick-slot reads only what the pause needs; admitting jobs read everything", () => {
  const action = yamlAt(".github/actions/check-wip-cap/action.yml");
  assert.equal(action.inputs.reads.default, "full");
  assert.equal(action.runs.steps.find((step) => step.id === "check").env.WIP_READS, "${{ inputs.reads }}");
  const pickSlot = yamlAt(".github/workflows/work-resolve-issue.yml").jobs["pick-slot"];
  assert.equal(pickSlot.steps.find(usesWip).with?.reads, "pause");
  // Only capped leaves pick-slot; nothing downstream reads admission-open or wip from it.
  assert.deepEqual(Object.keys(pickSlot.outputs).filter((key) => /wip|admission/.test(pickSlot.outputs[key])), ["capped"]);
});
