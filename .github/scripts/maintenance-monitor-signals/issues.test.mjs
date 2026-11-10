// The incident rules: a signal holds at most one open issue, found by its
// marker, filed past its open threshold and closed past its close threshold;
// a signal that flaps inside its thresholds files and comments nothing; a
// closed-as-not-planned or duplicate incident mutes the signal; platform
// incidents are logged, never filed; the old rolling issues are retired.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { FILING, LOG_ONLY, SIGNALS, familyOf, incidentRules, partlyReadSignals, planIssues, readMarker, renderBody, renderRetire, stateFingerprint, unreadSignals } from "./issues.mjs";
import { detect } from "./signals.mjs";

const now = new Date("2026-10-19T16:41:00Z");
const windowStart = new Date("2026-10-19T15:36:00Z");
const runUrl = "https://github.com/o/r/actions/runs/900";
const denied = (id) => ({
  id,
  url: `https://github.com/o/r/actions/runs/${id}`,
  name: "pr-merge",
  event: "schedule",
  annotations: [{ level: "failure", message: "lane-token-denied: the broker answered 500 with reason unknown" }],
});
const findingFor = (runs) => detect({ now, windowStart, failedRuns: runs.map(denied) })[0];
const THROTTLING = "3 throttling";
const family = (findings) => ({ signal: THROTTLING, findings });
const RULES = Object.fromEntries(SIGNALS.map((signal) => [signal, { open: 0, close: 0 }]));
const THRESHOLDS = { ...RULES, [THROTTLING]: { open: 4, close: 3 } };
const hoursAgo = (hours, from = now) => new Date(from.getTime() - hours * 3600_000).toISOString();
const plan = (args) => planIssues({ rules: RULES, now, ...args });

const issueFrom = (findings, number, extra = {}) => ({
  number,
  state: "open",
  state_reason: null,
  body: renderBody(family(findings), runUrl),
  ...extra,
});
const oldIssue = (key, number, extra = {}) => ({
  number,
  state: "open",
  state_reason: null,
  body: `<!-- factory-monitor key=${key} fp=0123456789abcdef -->\n**Signal:** old`,
  ...extra,
});

test("the marker names the incident on the body's first line", () => {
  const body = renderBody(family([findingFor([1])]), runUrl);
  assert.equal(readMarker(body).key, "incident:throttling");
  assert.equal(readMarker(`text\n${body}`), null);
  assert.equal(readMarker("<!-- factory-monitor key=x fp=zz -->"), null);
  assert.equal(familyOf("4 merge-queue ejections"), "merge-queue-ejections");
  assert.equal(familyOf("5 held PRs"), "held-prs");
});

test("every signal has a plain title, no prefix, and a Priority value", () => {
  assert.deepEqual(new Set(Object.keys(FILING)), new Set(SIGNALS));
  for (const [signal, { title, priority }] of Object.entries(FILING)) {
    assert.doesNotMatch(title, /^\[|^[A-Za-z]+:\s/, signal);
    assert.ok(["critical", "high", "medium", "low"].includes(priority), signal);
  }
  assert.equal(FILING["1 main red"].priority, "critical");
});

test("the state fingerprint follows the findings' keys, so new evidence for the same key changes nothing", () => {
  const a = findingFor([1]);
  assert.equal(stateFingerprint([a]), stateFingerprint([{ ...a, summary: "other text", fingerprint: "ffffffffffffffff" }]));
  assert.notEqual(stateFingerprint([a]), stateFingerprint([a, { ...a, key: "throttle:rate-limited" }]));
  assert.notEqual(stateFingerprint([a]), stateFingerprint([]));
});

test("a signal under its open threshold files nothing and keeps its timer", () => {
  const f = findingFor([1]);
  const first = planIssues({ findings: [f], existing: [], rules: THRESHOLDS, now });
  assert.deepEqual(first.file, []);
  assert.deepEqual(first.episodes[THROTTLING], { onSince: now.toISOString(), clearSince: null });
  assert.deepEqual(first.skip, [{ family: "throttling", number: null, reason: "below threshold" }]);
  const carried = { [THROTTLING]: { onSince: hoursAgo(3.9), clearSince: null } };
  assert.deepEqual(planIssues({ findings: [f], existing: [], rules: THRESHOLDS, episodes: carried, now }).file, []);
});

test("at its open threshold a signal files one incident holding every finding", () => {
  const a = findingFor([1]);
  const b = { ...findingFor([2]), key: "throttle:rate-limited" };
  const carried = { [THROTTLING]: { onSince: hoursAgo(4), clearSince: null } };
  const filed = planIssues({ findings: [a, b], existing: [], rules: THRESHOLDS, episodes: carried, now });
  assert.equal(filed.file.length, 1);
  assert.deepEqual(filed.file[0].family.findings.map((f) => f.key), [a.key, b.key].sort());
  assert.equal(filed.episodes[THROTTLING].onSince, carried[THROTTLING].onSince);
});

test("a zero open threshold files at the first run; a clear run restarts the timer", () => {
  const zero = planIssues({ findings: [findingFor([1])], existing: [], rules: { ...THRESHOLDS, [THROTTLING]: { open: 0, close: 3 } }, now });
  assert.equal(zero.file.length, 1);
  const carried = { [THROTTLING]: { onSince: hoursAgo(10), clearSince: null } };
  const clear = planIssues({ findings: [], existing: [], rules: THRESHOLDS, episodes: carried, now });
  assert.deepEqual(clear.episodes, {});
  assert.deepEqual(clear.file, []);
});

// #9866's first twelve on and off spans, in hours, as the issue's timeline
// recorded them (2026-10-24 on), replayed one run an hour.
const FLAPPING = [
  ["on", 1.01],
  ["off", 2.0],
  ["on", 1.34],
  ["off", 0.76],
  ["on", 1.93],
  ["off", 13.96],
  ["on", 1.0],
  ["off", 10.08],
  ["on", 0.95],
  ["off", 1.35],
  ["on", 3.66],
  ["off", 12.96],
];
const hourlyRuns = (spans) => spans.flatMap(([kind, hours]) => Array(Math.max(1, Math.round(hours))).fill(kind === "on"));

test("#9866's flapping inside its thresholds opens no issue and writes nothing", () => {
  let episodes = {};
  const f = findingFor([1]);
  for (const [i, on] of hourlyRuns(FLAPPING).entries()) {
    const at = new Date(now.getTime() + i * 3600_000);
    const p = planIssues({ findings: on ? [f] : [], existing: [], rules: THRESHOLDS, episodes, now: at });
    episodes = p.episodes;
    assert.deepEqual([p.file, p.update, p.close, p.retire], [[], [], [], []], `run ${i}`);
  }
});

test("an open incident is updated only when its findings' keys change, with no comment planned", () => {
  const f = findingFor([1]);
  const existing = [issueFrom([f], 41)];
  const same = plan({ findings: [findingFor([1])], existing });
  assert.deepEqual(same.update, []);
  assert.deepEqual(same.skip, [{ family: "throttling", number: 41, reason: "unchanged" }]);
  const newEvidence = plan({ findings: [{ ...f, summary: "new text" }], existing });
  assert.deepEqual(newEvidence.update, []);
  const changed = plan({ findings: [f, { ...f, key: "throttle:rate-limited" }], existing });
  assert.deepEqual(changed.update.map((u) => u.number), [41]);
  assert.deepEqual(changed.file, []);
});

test("a clear run starts the close timer, and only past close-hours does the incident close", () => {
  const existing = [issueFrom([findingFor([1])], 41)];
  const first = planIssues({ findings: [], existing, rules: THRESHOLDS, now });
  assert.deepEqual(first.close, []);
  assert.deepEqual(first.episodes[THROTTLING], { onSince: null, clearSince: now.toISOString() });
  const waiting = planIssues({ findings: [], existing, rules: THRESHOLDS, episodes: { [THROTTLING]: { onSince: null, clearSince: hoursAgo(2) } }, now });
  assert.deepEqual(waiting.close, []);
  assert.deepEqual(waiting.skip, [{ family: "throttling", number: 41, reason: "clearing" }]);
  const past = planIssues({ findings: [], existing, rules: THRESHOLDS, episodes: { [THROTTLING]: { onSince: null, clearSince: hoursAgo(3) } }, now });
  assert.deepEqual(past.close, [{ number: 41, family: family([]) }]);
});

test("an on run stops the close timer", () => {
  const f = findingFor([1]);
  const existing = [issueFrom([f], 41)];
  const p = planIssues({ findings: [f], existing, rules: THRESHOLDS, episodes: { [THROTTLING]: { onSince: null, clearSince: hoursAgo(2) } }, now });
  assert.deepEqual(p.close, []);
  assert.equal(p.episodes[THROTTLING].clearSince, null);
});

test("an unread signal keeps its timers and leaves its incident as it is", () => {
  const existing = [issueFrom([findingFor([1])], 41)];
  const carried = { [THROTTLING]: { onSince: null, clearSince: hoursAgo(5) } };
  const unread = unreadSignals(["failed runs: HTTP 502"]);
  const quiet = planIssues({ findings: [], existing, rules: THRESHOLDS, episodes: carried, unread, now });
  assert.deepEqual([quiet.close, quiet.update], [[], []]);
  assert.deepEqual(quiet.skip, [{ family: "throttling", number: 41, reason: "not read" }]);
  assert.deepEqual(quiet.episodes[THROTTLING], carried[THROTTLING]);
  const other = planIssues({ findings: [], existing, rules: THRESHOLDS, episodes: carried, unread: unreadSignals(["audits: HTTP 502"]), now });
  assert.deepEqual(other.close.map((c) => c.number), [41]);
  const firing = planIssues({ findings: [findingFor([1])], existing: [], rules: { ...THRESHOLDS, [THROTTLING]: { open: 0, close: 3 } }, unread, now });
  assert.deepEqual(firing.file, []);
});

// Signal 13 at its default threshold of 4 held runs in 24 hours: 4 held
// work-unblock runs fire it, 3 do not.
const LANE_HOLDS = "13 lane holds";
const heldRuns = (n) =>
  Array.from({ length: n }, (_, i) => ({ lane: "work-unblock", runId: 70 + i, url: `https://github.com/o/r/actions/runs/${70 + i}`, item: null, reason: "open listing failed", at: hoursAgo(i + 1) }));
const holdFindings = (n) => detect({ now, windowStart, laneHolds: heldRuns(n), holdRule: { threshold: 4, windowHours: 24 } });
const HOLD_RULES = { ...RULES, [LANE_HOLDS]: { open: 1, close: 2 } };
const PARTLY = ["lane holds partly read: over the cap of unread green runs of work-resolve-issue (cap 6); held runs read only through 2026-10-19T16:00:00Z"];
const holdIncident = () => ({ number: 52, state: "open", state_reason: null, body: renderBody({ signal: LANE_HOLDS, findings: holdFindings(4) }, runUrl) });

test("a partly read signal 13 with a lane at 4 holds opens its incident", () => {
  assert.equal(holdFindings(3).length, 0, "3 holds are under the threshold");
  const findings = holdFindings(4);
  assert.deepEqual(findings.map((f) => f.key), ["lane-hold:work-unblock"]);
  const p = planIssues({ findings, existing: [], unread: unreadSignals(PARTLY), partly: partlyReadSignals(PARTLY), rules: HOLD_RULES, episodes: { [LANE_HOLDS]: { onSince: hoursAgo(2), clearSince: null } }, now });
  assert.deepEqual(p.file.map((f) => f.family.signal), [LANE_HOLDS]);
  assert.deepEqual(p.episodes[LANE_HOLDS], { onSince: hoursAgo(2), clearSince: null });
  const fresh = planIssues({ findings, existing: [], partly: partlyReadSignals(PARTLY), rules: HOLD_RULES, now });
  assert.deepEqual(fresh.episodes[LANE_HOLDS], { onSince: now.toISOString(), clearSince: null }, "a partial read with a finding starts the open timer");
});

test("a partly read signal 13 under 4 holds leaves its open incident open and its timers as they are", () => {
  const carried = { [LANE_HOLDS]: { onSince: null, clearSince: hoursAgo(5) } };
  const p = planIssues({ findings: holdFindings(3), existing: [holdIncident()], partly: partlyReadSignals(PARTLY), rules: HOLD_RULES, episodes: carried, now });
  assert.deepEqual([p.close, p.update, p.file], [[], [], []]);
  assert.deepEqual(p.skip, [{ family: "lane-holds", number: 52, reason: "partly read" }]);
  assert.deepEqual(p.episodes[LANE_HOLDS], carried[LANE_HOLDS]);
  assert.equal(p.status.find((s) => s.signal === LANE_HOLDS).state, "partly read, #52 left as it is");
});

test("a whole read of signal 13 under 4 holds clears its incident as before", () => {
  const p = planIssues({ findings: holdFindings(3), existing: [holdIncident()], rules: HOLD_RULES, episodes: { [LANE_HOLDS]: { onSince: null, clearSince: hoursAgo(5) } }, now });
  assert.deepEqual(p.close.map((c) => c.number), [52]);
  const starting = planIssues({ findings: holdFindings(3), existing: [holdIncident()], rules: HOLD_RULES, now });
  assert.deepEqual([starting.close, starting.episodes[LANE_HOLDS]], [[], { onSince: null, clearSince: now.toISOString() }]);
});

test("a partly-read gap leaves no signal unread and marks only signal 13 partly read", () => {
  assert.equal(unreadSignals(PARTLY).size, 0);
  assert.deepEqual([...partlyReadSignals(PARTLY)], [LANE_HOLDS]);
  assert.equal(partlyReadSignals(["lane holds: the monitor.lane-holds rule was not read: yq failed", "audits: x"]).size, 0);
});

// A failed lane-hold marker list leaves the scan's reads, a floor on the whole.
const MARKERS_FAILED = ["lane hold markers: GET artifacts: HTTP 502"];

test("a failed marker list reads signal 13 partly: a lane at 4 holds still files, and under 4 an open incident stays open", () => {
  assert.equal(unreadSignals(MARKERS_FAILED).size, 0, "the marker gap leaves no signal unread");
  assert.deepEqual([...partlyReadSignals(MARKERS_FAILED)], [LANE_HOLDS]);
  const filed = planIssues({ findings: holdFindings(4), existing: [], unread: unreadSignals(MARKERS_FAILED), partly: partlyReadSignals(MARKERS_FAILED), rules: HOLD_RULES, episodes: { [LANE_HOLDS]: { onSince: hoursAgo(2), clearSince: null } }, now });
  assert.deepEqual(filed.file.map((f) => f.family.signal), [LANE_HOLDS], "the scan's 4 holds file the incident");
  const kept = planIssues({ findings: holdFindings(3), existing: [holdIncident()], unread: unreadSignals(MARKERS_FAILED), partly: partlyReadSignals(MARKERS_FAILED), rules: HOLD_RULES, episodes: { [LANE_HOLDS]: { onSince: null, clearSince: hoursAgo(5) } }, now });
  assert.deepEqual(kept.close, [], "no clear without the markers");
  assert.deepEqual(kept.skip, [{ family: "lane-holds", number: 52, reason: "partly read" }]);
});

test("each collect source maps to the signals it feeds, and an unknown gap leaves every signal unread", () => {
  const text = readFileSync(new URL("./collect.mjs", import.meta.url), "utf8");
  const sources = [...text.matchAll(/await source\("([^"]+)"/g)].map((m) => m[1]);
  assert.ok(sources.length >= 10);
  for (const name of sources) assert.notDeepEqual([...unreadSignals([`${name}: x`])], SIGNALS, name);
  assert.deepEqual([...unreadSignals(["audits: x"])], ["6 report-only audit"]);
  assert.deepEqual([...unreadSignals(["post-merge reports: x"])], ["11 post-merge unreadable"]);
  assert.deepEqual([...unreadSignals(["pr-merge sweep: x"])], ["3 throttling", "5 held PRs", "8 throughput", "12 listing held"]);
  assert.deepEqual([...unreadSignals(["pr-merge listed sweep: x"])], ["5 held PRs", "8 throughput"]);
  assert.deepEqual([...unreadSignals(["lane holds: x"])], ["13 lane holds"]);
  assert.deepEqual(new Set(unreadSignals(["new source: x"])), new Set(SIGNALS));
  assert.equal(unreadSignals([]).size, 0);
});

test("a later episode after the lane closed one files a new incident, and only one", () => {
  const closed = [issueFrom([], 30, { state: "closed", state_reason: "completed", closed_at: "2026-10-19T10:00:00Z" })];
  const carried = { [THROTTLING]: { onSince: hoursAgo(4), clearSince: null } };
  const p = planIssues({ findings: [findingFor([1])], existing: closed, rules: THRESHOLDS, episodes: carried, now });
  assert.equal(p.file.length, 1);
  assert.deepEqual(plan({ findings: [], existing: closed }).file, []);
  const openToo = [...closed, issueFrom([findingFor([1])], 31)];
  assert.deepEqual(plan({ findings: [findingFor([1])], existing: openToo }).file, []);
});

test("a person's completed close with the same keys holds until a finding is newer than the close", () => {
  const f = { ...findingFor([1]), observedAt: "2026-10-19T15:00:00Z" };
  const closed = [issueFrom([f], 30, { state: "closed", state_reason: "completed", closed_at: "2026-10-19T16:00:00Z" })];
  const episodes = { [THROTTLING]: { onSince: "2026-10-19T14:00:00Z", clearSince: null } };
  const same = plan({ findings: [f], existing: closed, episodes });
  assert.deepEqual(same.file, []);
  assert.deepEqual(same.skip, [{ family: "throttling", number: 30, reason: "closed-unchanged" }]);
  assert.equal(plan({ findings: [{ ...f, observedAt: "2026-10-19T16:30:00Z" }], existing: closed, episodes }).file.length, 1);
});

test("a person's completed close holds only for the episode it closed, when findings carry no time", () => {
  const f = findingFor([1]);
  assert.equal(f.observedAt, null);
  const closed = [issueFrom([f], 30, { state: "closed", state_reason: "completed", closed_at: hoursAgo(10) })];
  const held = plan({ findings: [f], existing: closed, episodes: { [THROTTLING]: { onSince: hoursAgo(12), clearSince: null } } });
  assert.deepEqual(held.skip, [{ family: "throttling", number: 30, reason: "closed-unchanged" }]);
  const later = plan({ findings: [f], existing: closed, episodes: { [THROTTLING]: { onSince: hoursAgo(2), clearSince: null } } });
  assert.equal(later.file.length, 1);
});

test("closing as not planned or duplicate mutes the signal, and the newest incident decides", () => {
  for (const reason of ["not_planned", "duplicate"]) {
    const muted = plan({
      findings: [findingFor([1, 2])],
      existing: [issueFrom([findingFor([1])], 10, { state: "closed", state_reason: "completed", closed_at: "2026-10-01T00:00:00Z" }), issueFrom([findingFor([1])], 20, { state: "closed", state_reason: reason, closed_at: "2026-10-02T00:00:00Z" })],
    });
    assert.deepEqual([muted.file, muted.update], [[], []]);
    assert.deepEqual(muted.skip, [{ family: "throttling", number: 20, reason: "muted" }]);
    assert.match(muted.status.find((s) => s.signal === THROTTLING).state, /muted by #20/);
  }
  const reopened = plan({ findings: [findingFor([1])], existing: [issueFrom([findingFor([2])], 20, { state: "open" })] });
  assert.deepEqual(reopened.skip, [{ family: "throttling", number: 20, reason: "unchanged" }]);
});

test("a platform incident is logged in the plan and never filed", () => {
  const findings = detect({
    now,
    windowStart,
    status: {
      components: [],
      incidents: [{ id: "x1", name: "Actions down", status: "investigating", created_at: "2026-10-19T16:00:00Z", shortlink: "s", components: ["Actions"] }],
    },
  });
  assert.ok(LOG_ONLY.has(findings[0].signal));
  const p = plan({ findings, existing: [] });
  assert.deepEqual(p.file, []);
  assert.deepEqual(p.logged, findings);
});

test("every open rolling issue and earlier per-key issue is retired, and closed ones and incidents are left alone", () => {
  const p = plan({
    findings: [],
    existing: [
      issueFrom([findingFor([1])], 90),
      oldIssue("family:throttling", 12),
      oldIssue("family:lane-holds", 11),
      oldIssue("broker-deny:500-unknown", 13),
      oldIssue("family:ceiling", 16, { state: "closed", state_reason: "completed" }),
    ],
  });
  assert.deepEqual(p.retire, [
    { number: 11, key: "family:lane-holds" },
    { number: 12, key: "family:throttling" },
    { number: 13, key: "broker-deny:500-unknown" },
  ]);
  assert.match(renderRetire(runUrl), /job summary/);
  assert.ok(renderRetire(runUrl).includes(runUrl));
});

test("a rolling issue closed as not planned does not mute the new flow", () => {
  const p = plan({ findings: [findingFor([1])], existing: [oldIssue("family:throttling", 9, { state: "closed", state_reason: "not_planned" })] });
  assert.equal(p.file.length, 1);
});

test("every detector's signal is an incident signal or logged only, and an unknown one is named in the plan", () => {
  const all = detect({
    now,
    windowStart,
    failedRuns: [denied(1)],
    mainRun: { id: 1, url: "u", sha: "a", event: "schedule", conclusion: "failure", failedJobs: [{ name: "j", annotations: [{ level: "failure", message: "m" }] }] },
    budgetReadings: [{ phase: "end", name: "lane", used: 99, limit: 100, remaining: 1 }],
    mergeGroupFailures: [1, 2, 3].map((id) => ({ id, url: "u", workflow: "w", createdAt: "t" })),
    sweep: { url: "u", live: true, startedAt: "2026-10-19T16:30:00Z", candidates: 3, results: [{ pr: 1, updatedAt: "2026-10-17T00:00:00Z" }] },
    laneMerges: { lastMergedAt: null },
    audits: [{ workflow: "w", run: { id: 1, url: "u", conclusion: "failure", createdAt: "t" } }],
    status: { components: [{ name: "Actions", status: "major_outage" }], incidents: [] },
    laneStops: [{ id: 1, outcome: "funding", issue: 3, createdAt: "t", url: "u" }],
    stalledStops: [{ pr: 5, head: "a", activity: "fix-ci", reason: "ci-fix-invalid", stoppedAt: "t", url: "u" }],
    postMergeReports: [4, 3, 2, 1].map((runId) => ({ runId, url: "u", code: "3", reason: "r", createdAt: "t" })),
    heldSweeps: [4, 3, 2, 1].map((runId) => ({ runId, url: "u", reason: "r", createdAt: "t" })),
    laneHolds: [1, 2].map((runId) => ({ lane: "work-unblock", runId, url: "u", item: null, reason: "r", at: "2026-10-19T16:00:00Z" })),
    holdRule: { threshold: 2, windowHours: 24 },
  });
  assert.deepEqual(new Set(all.map((f) => f.signal)), new Set([...SIGNALS, ...LOG_ONLY]));
  const p = plan({ findings: [{ ...findingFor([1]), signal: "10 renamed" }], existing: [] });
  assert.deepEqual(p.file, []);
  assert.deepEqual(p.skip, [{ family: "renamed", number: null, reason: "unknown signal" }]);
});

test("every signal reports one state line, with its findings as evidence", () => {
  const f = findingFor([1]);
  const p = plan({ findings: [f], existing: [] });
  assert.deepEqual(p.status.map((s) => s.signal), SIGNALS);
  const entry = p.status.find((s) => s.signal === THROTTLING);
  assert.deepEqual(entry.findings, [f]);
  assert.match(entry.state, /filing an incident/);
  assert.equal(p.status.find((s) => s.signal === "1 main red").state, "clear");
});

test("the thresholds cover every signal and refuse a missing or fractional value", () => {
  const raw = Object.fromEntries(SIGNALS.map((s) => [familyOf(s), { "open-hours": 2, "close-hours": 6 }]));
  assert.deepEqual(incidentRules(raw)[THROTTLING], { open: 2, close: 6 });
  const { throttling, ...missing } = raw;
  assert.ok(throttling);
  assert.throws(() => incidentRules(missing), /throttling open-hours/);
  assert.throws(() => incidentRules({ ...raw, throttling: { "open-hours": 1.5, "close-hours": 1 } }), /throttling open-hours/);
  assert.throws(() => incidentRules({ ...raw, throttling: { "open-hours": 1, "close-hours": -1 } }), /throttling close-hours/);
});

test("the body carries each finding's evidence inside a text fence, says how to mute, and takes no born-triaged marker", () => {
  const f = findingFor([1, 2]);
  const body = renderBody(family([f]), runUrl);
  assert.match(body, /Owning area/);
  assert.match(body, new RegExp(`### \`${f.key}\``));
  assert.match(body, /```text\n[^`]*lane-token-denied[^`]*\n```/);
  assert.match(body, /\*\*State:\*\* 1 current finding in/);
  assert.match(body, /not planned or duplicate mutes the signal/);
  assert.match(body, /## Done when\n\n- \[ \]/);
  assert.doesNotMatch(body, /born-triaged/);
  assert.match(renderBody(family([]), runUrl), /\*\*State:\*\* clear in/);
});

// The post-hoc review of #9772: a finding's summary carries run, job and URL
// text, and rendered outside a fence a mention, link or tag in it worked.
test("each finding's summary renders inside a text fence in the body", () => {
  const hostile = { ...findingFor([1]), summary: "job @someone [x](https://e.example) <img src=x> #12 failed" };
  const text = renderBody(family([hostile]), runUrl);
  assert.ok(text.includes("```text\njob @someone [x](https://e.example) <img src=x> #12 failed\n```"), text);
  assert.equal(text.split("@someone").length, 2, "only the fenced copy");
  const ticks = { ...findingFor([1]), summary: "a ``` b" };
  assert.ok(renderBody(family([ticks]), runUrl).includes("````text\na ``` b\n````"), "the fence outgrows a backtick run");
});
