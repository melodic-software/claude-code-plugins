// sweep-summary.mjs: one pr-merge sweep's verdicts as data. Expected values
// come from the request that the counts aggregate across PRs
// (`in-flight:unverified-auto-merge:#8099` counts as
// `in-flight:unverified-auto-merge`, `post-merge:failure:dispatch#...` as
// `post-merge:failure`), the summary step's rules in pr-merge.yml (a missing
// reason reads `not ready`; a blocker loses CR, LF and backticks and keeps 300
// characters) and the row shapes the gate step writes; counts are by hand.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { main, normalizeReason, summarize } from "./sweep-summary.mjs";

const row = (pr, fields = {}) => ({
  pr,
  head: "a".repeat(40),
  updatedAt: "2026-10-19T10:00:00Z",
  exit: 1,
  ready: false,
  enqueued: false,
  merged: false,
  reportOnly: false,
  reason: null,
  dispatched: null,
  blockers: [],
  ...fields,
});
const held = (pr, reason) =>
  row(pr, {
    exit: 10,
    reportOnly: null,
    reason: `prefilter:${reason}`,
    blockers: [`prefilter: ${reason}, refused before the gate`],
  });
const meta = {
  runId: 123,
  event: "schedule",
  live: true,
  startedAt: "2026-10-19T10:11:00Z",
};

test("drops the PR number, run list or free text a reason ends with", () => {
  assert.equal(
    normalizeReason("in-flight:unverified-auto-merge:#8099"),
    "in-flight:unverified-auto-merge",
  );
  assert.equal(
    normalizeReason("in-flight:identity-entry-queued:#8100"),
    "in-flight:identity-entry-queued",
  );
  assert.equal(
    normalizeReason("post-merge:failure:dispatch#4411,ci#4412"),
    "post-merge:failure",
  );
  assert.equal(
    normalizeReason("post-merge:floor-unreadable: HTTP 502 from the API"),
    "post-merge:floor-unreadable",
  );
  assert.equal(
    normalizeReason("ineligible:commits-listed:3-of:5"),
    "ineligible:commits-listed",
  );
  assert.equal(
    normalizeReason("ineligible:dependabot-review:major;no verdict"),
    "ineligible:dependabot-review:major",
  );
  assert.equal(normalizeReason("RuntimeError: gh exited 1"), "RuntimeError");
});

test("keeps a reason that names no PR as it is", () => {
  assert.equal(
    normalizeReason("ineligible:class-missing"),
    "ineligible:class-missing",
  );
  assert.equal(
    normalizeReason("prefilter:do-not-merge"),
    "prefilter:do-not-merge",
  );
  assert.equal(normalizeReason("gate printed no JSON"), "gate printed no JSON");
});

test("a missing reason reads not ready, as the step summary says", () => {
  assert.equal(normalizeReason(null), "not ready");
  assert.equal(normalizeReason(undefined), "not ready");
});

test("counts refusals by normalized reason and keeps each raw reason in results", () => {
  const rows = [
    row(8101, { reason: "in-flight:unverified-auto-merge:#8099" }),
    row(8102, { reason: "in-flight:unverified-auto-merge:#8100" }),
    row(8103, { reason: "post-merge:failure:dispatch#4411" }),
    row(8104),
    row(8105, { exit: 0, ready: true, enqueued: true }),
    row(8106, { exit: 0, ready: true, merged: true, dispatched: false }),
  ];
  const out = summarize({
    ...meta,
    results: rows,
    candidates: 6,
    held: [],
    gateOutcome: "success",
    cursor: { last: 8106 },
  });
  assert.deepEqual(out.refusal_counts, {
    "in-flight:unverified-auto-merge": 2,
    "post-merge:failure": 1,
    "not ready": 1,
  });
  assert.equal(out.enqueued, 1);
  assert.equal(out.merged, 1);
  assert.equal(out.candidates, 6);
  assert.equal(out.held, 0);
  assert.equal(out.budget_stop, null);
  assert.equal(out.results[0].reason, "in-flight:unverified-auto-merge:#8099");
  assert.deepEqual(
    {
      run_id: out.run_id,
      event: out.event,
      live: out.live,
      started_at: out.started_at,
    },
    {
      run_id: 123,
      event: "schedule",
      live: true,
      started_at: "2026-10-19T10:11:00Z",
    },
  );
});

test("a ready row a report-only run left alone is no refusal", () => {
  const out = summarize({
    ...meta,
    results: [row(8601, { ready: true }), row(8602)],
    candidates: 2,
    held: [],
    gateOutcome: "success",
    cursor: null,
  });
  assert.equal(out.ready_unmerged, 1);
  assert.deepEqual(out.refusal_counts, { "not ready": 1 });
});

test("a reason named like an object property is counted as itself", () => {
  const out = summarize({
    ...meta,
    results: [
      row(8701, { reason: "constructor" }),
      row(8702, { reason: "constructor" }),
    ],
    candidates: 2,
    held: [],
    gateOutcome: "success",
    cursor: null,
  });
  assert.deepEqual(out.refusal_counts, { constructor: 2 });
});

test("an empty sweep is all zeros, not an error", () => {
  const out = summarize({
    ...meta,
    results: [],
    candidates: 0,
    held: [],
    gateOutcome: "success",
    cursor: null,
  });
  assert.deepEqual(
    {
      candidates: out.candidates,
      enqueued: out.enqueued,
      merged: out.merged,
      held: out.held,
    },
    { candidates: 0, enqueued: 0, merged: 0, held: 0 },
  );
  assert.deepEqual(out.refusal_counts, {});
  assert.deepEqual(out.results, []);
  assert.equal(out.budget_stop, null);
});

test("held candidates count once each, under their prefilter reason", () => {
  const rows = [
    held(8201, "do-not-merge"),
    held(8202, "body-hold"),
    held(8203, "do-not-merge"),
    row(8204),
  ];
  const holds = [8201, 8202, 8203].map((number) => ({ number }));
  const out = summarize({
    ...meta,
    results: rows,
    candidates: 1,
    held: holds,
    gateOutcome: "success",
    cursor: { last: 8204 },
  });
  assert.equal(out.held, 3);
  assert.deepEqual(out.refusal_counts, {
    "prefilter:do-not-merge": 2,
    "prefilter:body-hold": 1,
    "not ready": 1,
  });
  assert.equal(out.budget_stop, null);
});

test("a gate that ended early on success is a budget stop naming where the next run starts", () => {
  const rows = [row(8301), row(8302)];
  const out = summarize({
    ...meta,
    results: rows,
    candidates: 5,
    held: [],
    gateOutcome: "success",
    cursor: { last: 8302 },
  });
  assert.deepEqual(out.budget_stop, {
    reached: 2,
    candidates: 5,
    next_after: 8302,
  });
});

test("a cancelled or failed gate is no budget stop", () => {
  const rows = [row(8301)];
  for (const gateOutcome of ["cancelled", "failure"]) {
    const out = summarize({
      ...meta,
      results: rows,
      candidates: 5,
      held: [],
      gateOutcome,
      cursor: { last: 8301 },
    });
    assert.equal(out.budget_stop, null);
  }
});

test("blockers lose CR, LF and backticks and keep 300 characters", () => {
  const long = "x".repeat(310);
  const out = summarize({
    ...meta,
    results: [row(8401, { blockers: ["a\r\nb`c", long] })],
    candidates: 1,
    held: [],
    gateOutcome: "success",
    cursor: null,
  });
  assert.deepEqual(out.results[0].blockers, ["a  b c", "x".repeat(300)]);
});

test("main reads the run's files and writes the artifact", () => {
  const dir = mkdtempSync(join(tmpdir(), "sweep-summary-"));
  try {
    const path = (name) => join(dir, name);
    writeFileSync(
      path("summary.json"),
      JSON.stringify([
        held(8501, "do-not-merge"),
        row(8502, { reason: "in-flight:unverified-auto-merge:#8499" }),
      ]),
    );
    writeFileSync(path("held.json"), JSON.stringify([{ number: 8501 }]));
    writeFileSync(path("candidates.json"), JSON.stringify([{ number: 8502 }]));
    writeFileSync(path("cursor.json"), JSON.stringify({ last: 8502 }));
    main({
      SUMMARY_PATH: path("summary.json"),
      HELD_PATH: path("held.json"),
      CANDIDATES_PATH: path("candidates.json"),
      CURSOR_PATH: path("cursor.json"),
      SWEEP_SUMMARY_TO: path("out.json"),
      GITHUB_RUN_ID: "987",
      EVENT: "workflow_dispatch",
      LIVE: "false",
      GATE_OUTCOME: "success",
      RUN_STARTED_AT: "",
    });
    const out = JSON.parse(readFileSync(path("out.json"), "utf8"));
    assert.equal(out.run_id, 987);
    assert.equal(out.event, "workflow_dispatch");
    assert.equal(out.live, false);
    assert.equal(out.started_at, null);
    assert.equal(out.candidates, 1);
    assert.equal(out.held, 1);
    assert.deepEqual(out.refusal_counts, {
      "prefilter:do-not-merge": 1,
      "in-flight:unverified-auto-merge": 1,
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("main writes an empty sweep when the gate left no summary", () => {
  const dir = mkdtempSync(join(tmpdir(), "sweep-summary-"));
  try {
    const to = join(dir, "out.json");
    main({
      SUMMARY_PATH: join(dir, "missing.json"),
      SWEEP_SUMMARY_TO: to,
      GITHUB_RUN_ID: "1",
      GATE_OUTCOME: "failure",
    });
    const out = JSON.parse(readFileSync(to, "utf8"));
    assert.deepEqual(out.results, []);
    assert.deepEqual(out.refusal_counts, {});
    assert.equal(out.candidates, null);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
