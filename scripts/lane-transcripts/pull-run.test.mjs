import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { gzipSync } from "node:zlib";

import { generate } from "../../.github/actions/open-lane-output/keygen.mjs";
import { parsePublicKey, sealRecord } from "../../.github/actions/seal-lane-output/seal.mjs";
import { ENTRY, TELEMETRY_ENTRY, TELEMETRY_PAYLOAD } from "./pull.mjs";
import { artifact, fakeDeps, iso, MARKER, NOW, run, sealed, seedState, sinkDir } from "./pull-fixtures.mjs";
import { paths, readRows, traceIdOf } from "./store.mjs";
process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const telemetry = (publicLine, runId, jobId) => {
  const spans = [traceIdOf(runId, 1), "0".repeat(32)].map((traceId, i) => ({ traceId, spanId: `${i}`.padStart(16, "0"), name: MARKER }));
  return sealRecord(parsePublicKey(publicLine), TELEMETRY_PAYLOAD, gzipSync(Buffer.from(`${JSON.stringify({ resourceSpans: [{ scopeSpans: [{ spans }] }] })}\n`)), String(runId), jobId);
};

function runArtifacts(publicLine) {
  const withTelemetry = (id, runId, jobId) => artifact(id, { runId, jobId, entries: { [ENTRY]: sealed(publicLine, { runId, jobId }), [TELEMETRY_ENTRY]: telemetry(publicLine, runId, jobId) } });
  return [
    withTelemetry(1, 77, "assess-units-a1"),
    withTelemetry(2, 77, "assess-units-a1"),
    { ...artifact(3, { runId: 77, record: "x" }), name: "unit-findings-a1" },
    withTelemetry(4, 78, "assess-units-a1"),
  ];
}

const keyEnv = (privateText) => ({ LANE_TRANSCRIPT_PRIVATE_KEY: privateText });

test("pull --run stores only that run's transcripts and telemetry, listing only its artifacts, with the rows a pull writes", () => {
  const { publicLine, privateText } = generate();
  const artifacts = runArtifacts(publicLine);
  const sink = sinkDir();
  const deps = fakeDeps(artifacts);
  const result = run(["pull", "--run", "77", "--sink", sink], { env: keyEnv(privateText), deps });
  assert.equal(result.code, 0, result.err);
  for (const text of [result.out, result.err]) assert.ok(!text.includes(MARKER) && !text.includes(privateText));
  assert.match(result.out, /pulled 2 transcript\(s\) from run 77; skipped \{"pulled":2,"known":0,"fork":0,"expired":0,"unnamed":0,/);
  assert.match(result.out, /gh calls: 4 of 1000/);
  assert.ok(deps.calls.every((c) => !c.includes("actions/artifacts?") && !c.includes("/workflows/")), "no name listing and no workflow run listing");
  assert.ok(!deps.calls.some((c) => c.includes("artifacts/3/zip") || c.includes("artifacts/4/zip")), "another artifact of the run, and another run's, are not downloaded");
  const rows = readRows(sink);
  assert.deepEqual(rows.map((r) => [r.artifact_id, r.run_id, r.telemetry_outcome, r.telemetry_joined_spans]), [[1, 77, "stored", 1], [2, 77, "stored", 1]]);

  const full = sinkDir();
  const fullDeps = fakeDeps(artifacts.filter((a) => a.workflow_run.id === 77 && a.id !== 3));
  assert.equal(run(["pull", "--sink", full], { env: keyEnv(privateText), deps: fullDeps }).code, 0);
  assert.deepEqual(rows, readRows(full).sort((a, b) => a.artifact_id - b.artifact_id));
});

test("pull --run leaves the pull's state byte for byte, and a second run skips what it holds", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  seedState(sink, { last_success_at: iso(NOW - 3600_000), resume_cutoff_at: iso(NOW - 2 * 86400_000), resume_name: "lane-transcript-assess-units-a1-1", budget_exhausted: true, cursors: { "lane-transcript-assess-units-a1-1": iso(NOW - 7200_000) } });
  const before = readFileSync(paths(sink).state, "utf8");
  assert.equal(run(["pull", "--run", "77", "--sink", sink], { env: keyEnv(privateText), deps: fakeDeps(runArtifacts(publicLine)) }).code, 0);
  assert.equal(readFileSync(paths(sink).state, "utf8"), before);
  const deps = fakeDeps(runArtifacts(publicLine));
  const again = run(["pull", "--run", "77", "--sink", sink], { env: keyEnv(privateText), deps });
  assert.equal(again.code, 0, again.err);
  assert.match(again.out, /"pulled":0,"known":2/);
  assert.ok(!deps.calls.some((c) => c.includes("/zip")), "a held artifact is not downloaded again");
  assert.equal(readRows(sink).length, 2);
});

test("pull --run skips a fork's artifact and fails when every transcript is sealed to another key", () => {
  const { publicLine, privateText } = generate();
  const fork = run(["pull", "--run", "42", "--sink", sinkDir()], { env: keyEnv(privateText), deps: fakeDeps([artifact(5, { record: sealed(publicLine), fork: true })]) });
  assert.equal(fork.code, 0, fork.err);
  assert.match(fork.out, /"pulled":0,"known":0,"fork":1/);
  const other = generate();
  const mismatch = run(["pull", "--run", "42", "--sink", sinkDir()], { env: keyEnv(privateText), deps: fakeDeps([artifact(6, { record: sealed(other.publicLine) })]) });
  assert.equal(mismatch.code, 1);
  assert.match(mismatch.err, /pull failed: key-mismatch: 1 transcript/);
});

test("pull --run exits 1 on a missed artifact or a failed listing, naming the kind only and writing no state", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const missed = run(["pull", "--run", "42", "--sink", sink], { env: keyEnv(privateText), deps: { ...fakeDeps([artifact(7, { record: sealed(publicLine) })], { failures: { "artifacts/7/zip": 5 } }), ghDelayMs: 0 } });
  assert.equal(missed.code, 1);
  assert.match(missed.out, /"fetch_failed":1/);
  const listing = run(["pull", "--run", "42", "--sink", sink], { env: keyEnv(privateText), deps: { ...fakeDeps([], { failures: { "artifacts?per_page=100&page=1": 10 } }), ghDelayMs: 0 } });
  assert.equal(listing.code, 1);
  assert.match(listing.err, /^pull failed: run-artifact-list: gh exited 1\n$/);
  assert.ok(!listing.err.includes(MARKER));
  assert.throws(() => readFileSync(paths(sink).state), { code: "ENOENT" });
});

test("--run takes a run id, and only on pull", () => {
  for (const argv of [["pull", "--run", "abc"], ["pull", "--run", "0"], ["pull", "--run", "-1"], ["status", "--run", "77"], ["query", "--run", "77"], ["pull", "--run", "1", "--run", "2"]]) {
    assert.equal(run(argv, { deps: fakeDeps([]) }).code, 2, argv.join(" "));
  }
});
