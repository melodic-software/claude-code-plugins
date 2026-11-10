import assert from "node:assert/strict";
import { test } from "node:test";
import { datedEvents, hourlyReadings, parseSlots, replay, scaled } from "./lane-level-replay.mjs";

const epoch = (iso) => Date.parse(iso) / 1000;

test("events.log times are dated back from the last line's date, one day per midnight wrap", () => {
  const text = ["23:50Z BREAKER-TRIP kill switch ON: 12% left refused=0 reset=00:10Z", "gh: Server Error (HTTP 502)", "00:05Z BREAKER-CLEAR kill switch OFF: 74% left", "00:04Z FLOW x", "09:30Z FLOW y"].join("\n");
  const events = datedEvents(text, "2026-11-10");
  assert.deepEqual(
    events.map((e) => [new Date(e.at * 1000).toISOString(), e.kind]),
    [
      ["2026-11-09T23:50:00.000Z", "BREAKER-TRIP"],
      ["2026-11-10T00:05:00.000Z", "BREAKER-CLEAR"],
      ["2026-11-10T00:04:00.000Z", "FLOW"],
      ["2026-11-10T09:30:00.000Z", "FLOW"],
    ],
    "a one-minute step back stays on the same day; the untimed gh: line is skipped",
  );
});

test("an hour's readings with breaker trips counted: lowest App remaining over duplicate rows, highest token share, a trip's reset past midnight, slot demand", () => {
  const byHour = hourlyReadings({
    appLimit: 5200,
    breaker: true,
    app: [
      { hour: "2026-11-09T23:00:00Z", min_remaining: 3000, deny_by_reason: {} },
      { hour: "2026-11-09T23:00:00Z", min_remaining: 1200, deny_by_reason: { "github-rate-limited": 2 } },
    ],
    windows: [
      { sampled_at: "2026-11-09T23:10:00Z", used: 3010, limit: 5000 },
      { sampled_at: "2026-11-09T23:12:00Z", used: 0, limit: 5000 },
    ],
    events: datedEvents("23:50Z BREAKER-TRIP kill switch ON: 12% left refused=0 reset=00:10Z\n00:05Z FLOW x", "2026-11-10"),
    slots: parseSlots("2026-11-09T23:05:00Z running=3 waiting=11\n2026-11-09T23:40:00Z runs_in_progress=2 runs_waiting=14\n"),
  });
  assert.deepEqual(byHour.get(epoch("2026-11-09T23:00:00Z")), {
    readings: {
      at: epoch("2026-11-10T00:00:00Z"),
      pools: { "lanes-app": { used: 4000, limit: 5200 }, "github-token": { used: 3010, limit: 5000 } },
      signals: ["breaker-trip", "app-rate-limited"],
      reset: epoch("2026-11-10T00:10:00Z"),
    },
    demand: { waiting: 14, running: 3 },
    source: "slots",
  });
});

test("by default a breaker trip is not a signal: the App's own deny is the hour's only one", () => {
  const hour = hourlyReadings({
    appLimit: 5200,
    app: [{ hour: "2026-11-09T23:00:00Z", min_remaining: 1200, deny_by_reason: { "github-rate-limited": 2 } }],
    events: datedEvents("23:50Z BREAKER-TRIP kill switch ON: 12% left refused=0 reset=00:10Z", "2026-11-10"),
  }).get(epoch("2026-11-09T23:00:00Z"));
  assert.deepEqual([hour.readings.signals, hour.readings.reset], [["app-rate-limited"], undefined]);
});

test("an hour with no slot sample takes the concurrency proxy, labeled; partial rows are skipped", () => {
  const repos = (queued, inProgress, partial = false) => ({ "melodic-software/claude-code-plugins": { queued_runs: queued, waiting_runs: 0, in_progress_runs: inProgress, partial } });
  const byHour = hourlyReadings({
    appLimit: 5200,
    concurrency: [
      { ts: "2026-11-10T05:10:00Z", repos: repos(2, 7) },
      { ts: "2026-11-10T05:20:00Z", repos: repos(9, 30, true) },
    ],
  });
  const hour = byHour.get(epoch("2026-11-10T05:00:00Z"));
  assert.deepEqual([hour.demand, hour.source], [{ waiting: 2, running: 7 }, "proxy"]);
});

test("scaling an App reading from level 3 to 6 doubles its spend, and spend past the limit is a signal", () => {
  const readings = { at: 1, pools: { "lanes-app": { used: 1300, limit: 5200 } }, signals: [] };
  assert.deepEqual(scaled(readings, 6, 3).pools["lanes-app"], { used: 2600, limit: 5200 });
  assert.deepEqual(scaled(readings, 3, 0), readings, "actual 0 replays as recorded");
  const hot = scaled({ ...readings, pools: { "lanes-app": { used: 3000, limit: 5200 } } }, 6, 3);
  assert.deepEqual([hot.pools["lanes-app"].used, hot.signals], [5200, ["modeled-app-exhausted"]]);
});

test("a replay of two quiet busy hours steps 3 up to 4, and an unrecorded hour holds", () => {
  const config = { "lane-level": { floor: 2, ceiling: 6, default: 3, "clean-windows": 2, pools: ["lanes-app"] }, api: { "lanes-app": { plan: 0.7, "writer-pause": 0.4 } } };
  const start = epoch("2026-11-10T00:00:00Z");
  const quiet = (hour) => [hour, { readings: { at: hour + 3600, pools: { "lanes-app": { used: 500, limit: 5200 } }, signals: [] }, demand: { waiting: 2, running: 3 }, source: "slots" }];
  const rows = replay(new Map([quiet(start), quiet(start + 3600)]), { start, end: start + 3 * 3600, config, actual: 3 });
  assert.deepEqual(
    rows.map((r) => [r.level, r.reason]),
    [
      [3, "streak"],
      [4, "step-up"],
      [4, "missing-data"],
    ],
  );
});
