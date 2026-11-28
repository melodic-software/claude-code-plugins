// test-scope: .github/workflows/*.yml
// test-scope: scripts/lane-transcripts/* .github/actions/open-lane-output/* .github/actions/seal-lane-output/*
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { gunzipSync, gzipSync } from "node:zlib";

import { generate } from "../../.github/actions/open-lane-output/keygen.mjs";
import { parsePublicKey, sealRecord } from "../../.github/actions/seal-lane-output/seal.mjs";
import { tempDir } from "../../lib/test-tmp.mjs";
import { ENTRY, LANE_WORKFLOWS, PAYLOAD, REPO, RUN_WORKFLOWS, TELEMETRY_ENTRY, TELEMETRY_PAYLOAD, TRANSCRIPT_JOB_IDS } from "./pull.mjs";
import { artifact, fakeDeps, FOREVER, iso, MARKER, MESSAGES, NOW, REPO_ID, run, sealed, seedState, sinkDir, stateOf, workflowLines } from "./pull-fixtures.mjs";
import { CAP_BYTES, parseArtifactName, paths, prune, query, readOutcomes, readRows, telemetrySpans, traceIdOf, transcriptMetrics, writeRows } from "./store.mjs";
process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

test("a pull opens each sealed transcript into the sink, gzipped, with a metrics row and no plaintext on stdout or stderr", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const env = { LANE_TRANSCRIPT_PRIVATE_KEY: privateText };
  const deps = fakeDeps([artifact(7, { record: sealed(publicLine) })]);
  const result = run(["pull", "--sink", sink], { env, deps });
  assert.equal(result.code, 0, result.err);
  assert.equal(env.LANE_TRANSCRIPT_PRIVATE_KEY, undefined, "the key leaves the environment");
  for (const text of [result.out, result.err]) assert.ok(!text.includes(MARKER) && !text.includes(privateText));
  const [row] = readRows(sink);
  assert.deepEqual(
    { lane: row.lane, job: row.job_id, run: row.run_id, model: row.model, models: row.models, outcome: row.outcome, turns: row.num_turns, date: row.date },
    { lane: "pr-verify", job: "check-intent", run: 42, model: "claude-opus-5-5", models: ["claude-opus-5-5", "claude-sonnet-5-5"], outcome: "success", turns: 7, date: "2026-11-02" },
  );
  assert.ok(!JSON.stringify(row).includes(MARKER), "the metrics row holds no transcript text");
  const file = path.join(sink, row.transcript);
  assert.deepEqual(JSON.parse(gunzipSync(readFileSync(file)).toString("utf8")), MESSAGES);
  assert.equal(statSync(file).mode & 0o777, 0o600);
  assert.equal(statSync(sink).mode & 0o777, 0o700);
});

test("a pulled row carries the contract's provider-neutral fields beside the GitHub ones", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const deps = fakeDeps([artifact(7, { attempt: 2, record: sealed(publicLine) })]);
  assert.equal(run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps }).code, 0);
  const [row] = readRows(sink);
  assert.deepEqual(
    { provider: row.provider, run_ref: row.run_ref, run_url: row.run_url, leg_key: row.leg_key },
    { provider: "github", run_ref: "42", run_url: `https://github.com/${REPO}/actions/runs/42/attempts/2`, leg_key: "check-intent" },
  );
});

test("a pull skips fork runs, records bound to another run, a wrong key, odd zips and artifacts it already holds", () => {
  const { publicLine, privateText } = generate();
  const other = generate();
  const sink = sinkDir();
  const page = [
    artifact(10, { record: sealed(publicLine), fork: true }),
    artifact(11, { record: sealed(publicLine, { runId: 99 }) }),
    artifact(12, { record: sealed(other.publicLine) }),
    artifact(13, { entries: { [ENTRY]: "x", "extra.txt": "y" } }),
    artifact(14, { jobId: "rate-merge-risk", record: sealed(publicLine, { jobId: "rate-merge-risk" }) }),
  ];
  let deps = fakeDeps(page);
  const first = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(first.code, 0, first.err);
  assert.match(first.out, /"pulled":1,"known":0,"fork":1,.*"bad_zip":1,"sealed_mismatch":2/);
  assert.ok(!deps.calls.some((c) => c.includes("artifacts/10/zip")), "a fork artifact is never downloaded");
  deps = fakeDeps(page);
  const second = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.match(second.out, /"pulled":0,"known":1/);
  assert.ok(!deps.calls.some((c) => c.includes("artifacts/14/zip")), "a held artifact is not downloaded again");
  assert.equal(readRows(sink).length, 1);
});


const backlogState = (resumeAgeHours) => ({ last_success_at: iso(NOW - 3600_000), last_error: null, budget_exhausted: true, resume_cutoff_at: iso(NOW - resumeAgeHours * 3600_000) });

test("status alerts when a budget-stopped backlog's cutoff is more than 5 days old, though the last success is fresh", () => {
  const sink = sinkDir();
  seedState(sink, backlogState(6 * 24));
  const result = run(["status", "--sink", sink], { deps: fakeDeps([]) });
  assert.equal(result.code, 1);
  assert.equal(JSON.parse(result.out).stale, true);
  assert.match(result.err, /^ALERT: /m);
});

test("status stays quiet while a budget-stopped backlog's cutoff is 1 day old", () => {
  const sink = sinkDir();
  seedState(sink, backlogState(24));
  const result = run(["status", "--sink", sink], { deps: fakeDeps([]) });
  assert.equal(result.code, 0, result.err);
  assert.equal(JSON.parse(result.out).stale, false);
  assert.equal(result.err, "");
});

test("the backlog alert turns on at 5 days, before the 7-day listing floor passes the kept cutoff, and a budget-stopped pull exits with it", () => {
  const stale = (hours) => {
    const sink = sinkDir();
    seedState(sink, backlogState(hours));
    return JSON.parse(run(["status", "--sink", sink], { deps: fakeDeps([]) }).out).stale;
  };
  assert.deepEqual([stale(5 * 24 - 1), stale(5 * 24 + 1), stale(7 * 24 - 1)], [false, true, true]);
  const { privateText } = generate();
  const sink = sinkDir();
  seedState(sink, backlogState(6 * 24));
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: { ...fakeDeps([]), ghCallBudget: 1 } });
  assert.equal(result.code, 1);
  assert.match(result.err, /^ALERT: /m);
});

test("status alerts when pull-outcomes has not succeeded in 5 days or its backlog has not drained, and stays quiet on a sink that never ran it", () => {
  const fresh = iso(NOW - 86400_000);
  const old = iso(NOW - 6 * 86400_000);
  const statusOf = (state) => {
    const sink = sinkDir();
    seedState(sink, { last_success_at: fresh, ...state });
    return run(["status", "--sink", sink], { deps: fakeDeps([]) });
  };
  const failing = statusOf({ outcomes: { last_success_at: old } });
  assert.equal(failing.code, 1);
  assert.match(failing.err, /^ALERT: no pull-outcomes pass has succeeded/m);
  assert.doesNotMatch(failing.err, /lane transcript pull/);
  const stalled = statusOf({ outcomes: { last_success_at: fresh, resume_cutoff_at: old } });
  assert.equal(stalled.code, 1);
  assert.match(stalled.err, /^ALERT: budget-stopped pull-outcomes passes/m);
  assert.equal(statusOf({ outcomes: { last_success_at: fresh } }).code, 0);
  assert.equal(statusOf({}).code, 0);
});

test("a fresh pull exits 0 while pull-outcomes is stale, so a timer that chains them still reaches pull-outcomes, and it prints the alert", () => {
  const { privateText } = generate();
  const sink = sinkDir();
  seedState(sink, { last_success_at: iso(NOW - 86400_000), outcomes: { last_success_at: iso(NOW - 6 * 86400_000) } });
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: fakeDeps([]) });
  assert.equal(result.code, 0, result.err);
  assert.match(result.err, /^ALERT: no pull-outcomes pass has succeeded/m);
});

test("a failed pull still logs its gh call count", () => {
  const { privateText } = generate();
  const deps = fakeDeps([], { failures: { "lane-transcript-refine-issue-1&per_page=100&page=1": 99 } });
  const result = run(["pull", "--sink", sinkDir()], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: { ...deps, ghAttempts: 2 } });
  assert.equal(result.code, 1);
  assert.match(result.out, new RegExp(`gh calls: ${RUN_WORKFLOWS.length + 2} of `));
  assert.match(result.err, /pull failed: artifact-list: gh exited 1/);
});

function uploadJobIds() {
  const found = {};
  for (const [file, lines] of workflowLines()) {
    let inJobs = false;
    let job = null;
    lines.forEach((line, i) => {
      if (/^jobs:/.test(line)) inJobs = true;
      const key = inJobs && /^ {2}([A-Za-z0-9_-]+):\s*(#.*)?$/.exec(line);
      if (key) job = key[1];
      const action = /^\s+(- )?uses:\s*\S*\/\.github\/actions\/upload-lane-transcript\b/.test(line);
      const artifact = /^\s+(- )?uses:\s*actions\/upload-artifact@/.test(line);
      if (!action && !artifact) return;
      const rest = lines.slice(i + 1);
      const end = rest.findIndex((l) => /^\s+- /.test(l));
      const block = rest.slice(0, end === -1 ? undefined : end);
      let id;
      if (action) {
        const idLine = block.find((l) => /^\s+job-id:/.test(l));
        assert.ok(idLine, `${file}:${i + 1} passes no job-id`);
        id = idLine.replace(/^\s+job-id:\s*/, "").trim();
      } else {
        const name = block.map((l) => /^\s+name:\s*lane-transcript-(.+)-\$\{\{ github\.run_attempt \}\}\s*$/.exec(l)?.[1]).find(Boolean);
        if (!name) return;
        id = name;
      }
      (found[file] ??= []).push(id.replaceAll("${{ github.job }}", job));
    });
  }
  return found;
}

test("every workflow that uploads a lane transcript, and every job-id it passes, is in the puller's list", () => {
  const found = uploadJobIds();
  const local = Object.keys(TRANSCRIPT_JOB_IDS).filter((key) => !key.startsWith("ci-workflows/"));
  assert.deepEqual(Object.keys(found).sort(), local.sort(), "the workflows that call upload-lane-transcript");
  for (const [file, ids] of Object.entries(found)) {
    for (const id of ids) {
      const shape = new RegExp(`^${id.split(/\$\{\{[^}]*\}\}/).map((part) => part.replace(/[.*+?^$()|[\]\\]/g, "\\$&")).join(".*")}$`);
      assert.ok(TRANSCRIPT_JOB_IDS[file].some((listed) => shape.test(listed)), `${file}: job-id ${id} has no name in TRANSCRIPT_JOB_IDS`);
    }
  }
});

test("every read runner call's activity, with each leg and fix-ci's rung up, is in the puller's list", () => {
  const listed = new Set(TRANSCRIPT_JOB_IDS["pr-run-activity-read.yml"]);
  let calls = 0;
  for (const [file, lines] of workflowLines()) {
    lines.forEach((line, i) => {
      if (!/^\s+uses:\s*\.\/\.github\/workflows\/pr-run-activity-read\.yml\b/.test(line)) return;
      const rest = lines.slice(i + 1);
      const end = rest.findIndex((l) => /^ {2}\S/.test(l));
      const block = rest.slice(0, end === -1 ? undefined : end);
      const value = (key) => block.map((l) => new RegExp(`^\\s+${key}:\\s*(.+?)\\s*$`).exec(l)?.[1]).find(Boolean) ?? "";
      const activity = value("activity");
      const fallback = value("fallback");
      assert.match(activity, /^[a-z][a-z0-9-]*$/, `${file}:${i + 1}`);
      const legs = fallback === "fallback" ? ["-fallback"] : fallback === "" ? [""] : ["-subscription"];
      const rungs = value("model-rung") === "" ? [""] : ["", "-rung-up"];
      for (const leg of legs) for (const rung of rungs) assert.ok(listed.has(`${activity}${leg}${rung}`), `${file}:${i + 1}: ${activity}${leg}${rung}`);
      calls += 1;
    });
  }
  assert.equal(calls, 24, "the read runner's callers");
});

test("every ci-workflows reusable called with the transcript key, and the lane it is called with, is in the puller's list", () => {
  const callers = [];
  for (const [file, lines] of workflowLines()) {
    lines.forEach((line, i) => {
      if (!/^\s+lane-transcript-public-key:/.test(line)) return;
      const usesAt = lines.slice(0, i).findLastIndex((l) => /^\s+uses:/.test(l));
      const reusable = /ci-workflows\/\.github\/workflows\/([^@\s]+)@/.exec(lines[usesAt] ?? "")?.[1];
      assert.ok(reusable, `${file}:${i + 1} passes the transcript key to no ci-workflows reusable`);
      const key = `ci-workflows/${reusable}`;
      assert.ok(TRANSCRIPT_JOB_IDS[key], `${file}:${i + 1}: ${key} is missing from TRANSCRIPT_JOB_IDS`);
      const lane = lines.slice(usesAt, i).map((l) => /^\s+lane:\s*(\S+)/.exec(l)?.[1]).find(Boolean);
      if (lane) assert.ok(TRANSCRIPT_JOB_IDS[key].some((id) => id.startsWith(`${lane}-`)), `${file}:${i + 1}: lane ${lane} has no name under ${key}`);
      callers.push(key);
    });
  }
  assert.deepEqual([...new Set(callers)].sort(), Object.keys(TRANSCRIPT_JOB_IDS).filter((key) => key.startsWith("ci-workflows/")).sort());
});

test("a pull where every transcript fails to open for the key fails, so the stale alert can fire", () => {
  const { privateText } = generate();
  const other = generate();
  const sink = sinkDir();
  const deps = fakeDeps([artifact(21, { record: sealed(other.publicLine) }), artifact(22, { jobId: "rate-merge-risk", record: sealed(other.publicLine, { jobId: "rate-merge-risk" }) })]);
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 1);
  assert.match(result.err, /pull failed: key-mismatch: 2 transcript/);
  assert.equal(JSON.parse(readFileSync(paths(sink).state, "utf8")).last_success_at, undefined);
});

test("a metrics append cut short leaves a tail the next pull drops and replaces", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const env = () => ({ LANE_TRANSCRIPT_PRIVATE_KEY: privateText });
  assert.equal(run(["pull", "--sink", sink], { env: env(), deps: fakeDeps([artifact(31, { record: sealed(publicLine) })]) }).code, 0);
  writeFileSync(paths(sink).metrics, '{"artifact_id":32,"run_id":4', { flag: "a" });
  assert.equal(run(["status", "--sink", sink], { deps: fakeDeps([]) }).code, 0);
  assert.deepEqual(readRows(sink).map((r) => r.artifact_id), [31]);
  const page = [artifact(32, { jobId: "rate-merge-risk", record: sealed(publicLine, { jobId: "rate-merge-risk" }) }), artifact(31, { record: sealed(publicLine) })];
  const again = run(["pull", "--sink", sink], { env: env(), deps: fakeDeps(page) });
  assert.equal(again.code, 0, again.err);
  assert.deepEqual(readRows(sink).map((r) => r.artifact_id), [31, 32]);
  assert.ok(readFileSync(paths(sink).metrics, "utf8").endsWith("}\n"));
});

test("a pull with no key, or a malformed one, fails naming the kind only", () => {
  for (const key of [undefined, "", "not-a-key"]) {
    const result = run(["pull", "--sink", sinkDir()], { env: key === undefined ? {} : { LANE_TRANSCRIPT_PRIVATE_KEY: key }, deps: fakeDeps([]) });
    assert.equal(result.code, 1);
    assert.match(result.err, /^no-key/);
    if (key) assert.ok(!result.err.includes(key));
  }
});

test("a failed pull with no success in 5 days alerts, and status exits 1 until a pull succeeds", () => {
  const { privateText } = generate();
  const sink = sinkDir();
  const failing = { ...fakeDeps([]), gh: () => { throw Object.assign(new Error("boom"), { status: 4 }); } };
  const failed = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: failing });
  assert.equal(failed.code, 1);
  assert.match(failed.err, /pull failed: artifact-list: gh exited 4/);
  assert.match(failed.err, /^ALERT: no lane transcript pull has succeeded in the last 5 days \(last: never\)$/m);
  assert.equal(run(["status", "--sink", sink], { deps: fakeDeps([]) }).code, 1);
  assert.equal(run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: fakeDeps([]) }).code, 0);
  assert.equal(run(["status", "--sink", sink], { deps: fakeDeps([], { now: NOW + 4 * 86400_000 }) }).code, 0);
  const late = run(["status", "--sink", sink], { deps: fakeDeps([], { now: NOW + 6 * 86400_000 }) });
  assert.equal(late.code, 1);
  assert.match(late.err, /^ALERT: /m);
});

const zipCalls = (deps, id) => deps.calls.filter((c) => c.endsWith(`artifacts/${id}/zip`)).length;

test("a gh call that fails is retried with a growing delay, and the pull then succeeds", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const deps = fakeDeps([artifact(41, { record: sealed(publicLine) })], { failures: { "artifacts/41/zip": 2, "actions/runs/42": 1, "page=1": 1 } });
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 0, result.err);
  assert.equal(readRows(sink).length, 1);
  assert.equal(zipCalls(deps, 41), 3);
  assert.deepEqual(deps.sleeps, [2000, 2000, 4000, 2000], "page, zip twice, run");
  assert.equal(stateOf(sink).last_success_at, new Date(NOW).toISOString());
});

test("the retry count and delay are injectable", () => {
  const { publicLine, privateText } = generate();
  const deps = { ...fakeDeps([artifact(42, { record: sealed(publicLine) })], { failures: { "artifacts/42/zip": FOREVER } }), ghAttempts: 2, ghDelayMs: 5 };
  assert.equal(run(["pull", "--sink", sinkDir()], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps }).code, 1);
  assert.equal(zipCalls(deps, 42), 2);
  assert.deepEqual(deps.sleeps, [5]);
});

test("a zip fetch keeps the short schedule: five tries, about 30 s, while a listing page gets the long one", () => {
  const { publicLine, privateText } = generate();
  const deps = fakeDeps([artifact(42, { record: sealed(publicLine) })], { failures: { "artifacts/42/zip": FOREVER } });
  run(["pull", "--sink", sinkDir()], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(zipCalls(deps, 42), 5);
  assert.deepEqual(deps.sleeps, [2000, 4000, 8000, 16000]);
});

for (const [kind, failures] of [["artifact-zip", { "artifacts/51/zip": FOREVER }], ["run-read", { "actions/runs/51": FOREVER }]]) {
  test(`a fetch failure (${kind}) past its retries is counted, the pull goes on, and the next pull fetches the artifact though it is behind the failed pull's overlap`, () => {
    const { publicLine, privateText } = generate();
    const sink = sinkDir();
    const previous = iso(NOW - 24 * 3600_000);
    const cursor = iso(NOW - 12 * 3600_000);
    seedState(sink, { last_success_at: previous, cursors: { "lane-transcript-check-intent-1": cursor } });
    const env = () => ({ LANE_TRANSCRIPT_PRIVATE_KEY: privateText });
    const failing = artifact(51, { runId: 51, createdAt: NOW - 10 * 3600_000, record: sealed(publicLine, { runId: 51 }) });
    const healthy = artifact(52, { jobId: "rate-merge-risk", runId: 52, record: sealed(publicLine, { runId: 52, jobId: "rate-merge-risk" }) });

    const partial = run(["pull", "--sink", sink], { env: env(), deps: fakeDeps([failing, healthy], { failures }) });
    assert.equal(partial.code, 0, partial.err);
    assert.match(partial.out, /"fetch_failed":1/);
    assert.deepEqual(readRows(sink).map((r) => r.artifact_id), [52], "the artifact listed after the failure is still pulled");
    const state = stateOf(sink);
    assert.equal(state.last_success_at, previous, "a pull that missed an artifact does not move the cutoff");
    assert.equal(state.last_error, `fetch-failed: 1 transcript(s) (${kind})`);
    assert.equal(state.last_tally.fetch_failed, 1);
    assert.equal(state.last_attempt_at, new Date(NOW).toISOString());
    assert.equal(state.cursors["lane-transcript-check-intent-1"], cursor, "the failed artifact's name keeps its cursor");
    assert.equal(state.cursors["lane-transcript-rate-merge-risk-1"], new Date(NOW).toISOString(), "a name listed through moves its cursor");
    for (const text of [partial.out, partial.err, JSON.stringify(state)]) assert.ok(!text.includes(MARKER), "no call's error text is stored or printed");

    const later = NOW + 3600_000;
    const clean = run(["pull", "--sink", sink], { env: env(), deps: fakeDeps([failing, healthy], { now: later }) });
    assert.equal(clean.code, 0, clean.err);
    assert.deepEqual(readRows(sink).map((r) => r.artifact_id).sort(), [51, 52]);
    assert.equal(stateOf(sink).last_success_at, new Date(later).toISOString());
    assert.equal(stateOf(sink).last_error, null);
  });
}

test("a zip that unzip cannot read is a fetch failure, not an aborted pull or a permanent skip", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const fake = fakeDeps([artifact(53, { record: sealed(publicLine) })]);
  const unreadable = { ...fake, unzip: () => { throw Object.assign(new Error("bad zip"), { status: 9 }); } };
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: unreadable });
  assert.equal(stateOf(sink).last_error, "fetch-failed: 1 transcript(s) (artifact-unzip)");
  assert.equal(result.code, 1, "never succeeded, so the stale rule applies");
  assert.match(result.out, /"bad_zip":0.*"fetch_failed":1/);
});

test("a rate limit on an artifact's call stops the pull at once, with no retry and no further call", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const last = iso(NOW - 86400_000);
  seedState(sink, { last_success_at: last });
  const fake = fakeDeps([artifact(54, { record: sealed(publicLine) }), artifact(55, { jobId: "rate-merge-risk", record: sealed(publicLine, { jobId: "rate-merge-risk" }) })]);
  const gh = (args) => {
    if (!args[1].endsWith("/zip")) return fake.gh(args);
    fake.calls.push(args.join(" "));
    throw Object.assign(new Error("gh failed"), { status: 1, stderr: Buffer.from("gh: API rate limit exceeded for user (HTTP 403)") });
  };
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: { ...fake, gh } });
  assert.equal(result.code, 1);
  assert.match(result.err, /pull failed: rate-limited/);
  assert.ok(!result.err.includes("for user"), "the kind only");
  assert.equal(fake.calls.filter((c) => c.endsWith("/zip")).length, 1);
  assert.deepEqual(fake.sleeps, []);
  assert.equal(stateOf(sink).last_success_at, last);
});

test("a listing page that fails past its retries fails the pull and keeps the last success", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const last = iso(NOW - 3 * 86400_000);
  seedState(sink, { last_success_at: last });
  const full = Array.from({ length: 100 }, (_, i) => artifact(6000 - i, { fork: true, record: sealed(publicLine) }));
  const second = "name=lane-transcript-check-intent-1&per_page=100&page=2";
  const deps = fakeDeps(full, { failures: { [second]: FOREVER } });
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 1);
  assert.match(result.err, /pull failed: artifact-list: gh exited 1/);
  assert.ok(!result.err.includes(MARKER));
  assert.equal(deps.calls.filter((c) => c.endsWith(second)).length, 10);
  assert.deepEqual(deps.sleeps, [2000, 4000, 8000, 16000, 32000, 64000, 128000, 256000, 300000], "the wait doubles to a 5 min cap, about 13.5 min before giving up");
  assert.equal(stateOf(sink).last_success_at, last);
});

test("a pull with a fetch failure exits 0 until the held last success is over 5 days old, then alerts", () => {
  const { publicLine, privateText } = generate();
  const attempt = (ageDays) => {
    const sink = sinkDir();
    seedState(sink, { last_success_at: iso(NOW - ageDays * 86400_000) });
    const deps = fakeDeps([artifact(61, { record: sealed(publicLine) })], { failures: { "artifacts/61/zip": FOREVER } });
    return run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  };
  const fresh = attempt(4);
  assert.equal(fresh.code, 0, fresh.err);
  assert.equal(fresh.err, "");
  const stale = attempt(6);
  assert.equal(stale.code, 1);
  assert.match(stale.err, /^ALERT: no lane transcript pull has succeeded in the last 5 days/m);
  assert.match(stale.out, /"fetch_failed":1/);
});

test("a fetch failure beside transcripts that do not open for the key still fails the pull as a key mismatch", () => {
  const { privateText } = generate();
  const other = generate();
  const sink = sinkDir();
  const page = [artifact(71, { record: sealed(other.publicLine) }), artifact(72, { jobId: "rate-merge-risk", record: sealed(other.publicLine, { jobId: "rate-merge-risk" }) })];
  const deps = fakeDeps(page, { failures: { "artifacts/72/zip": FOREVER } });
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 1);
  assert.match(result.err, /pull failed: key-mismatch: 1 transcript/);
  assert.equal(stateOf(sink).last_success_at, undefined);
});

test("a result with is_error true is stored as outcome error, with its subtype and API status and no transcript text", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const failedLeg = [MESSAGES[0], { type: "result", subtype: "success", is_error: true, api_error_status: 400, result: `Credit balance is too low ${MARKER}`, num_turns: 1, duration_ms: 5, usage: {}, modelUsage: {} }];
  const page = [
    artifact(81, { runId: 81, record: sealed(publicLine, { runId: 81, messages: failedLeg }) }),
    artifact(82, { runId: 82, record: sealed(publicLine, { runId: 82 }) }),
    artifact(83, { runId: 83, record: sealed(publicLine, { runId: 83, messages: [MESSAGES[0]] }) }),
  ];
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: fakeDeps(page) });
  assert.equal(result.code, 0, result.err);
  const shape = ({ outcome, subtype, is_error: isError, api_error_status: status }) => ({ outcome, subtype, isError, status });
  const rows = readRows(sink);
  assert.deepEqual(shape(rows[0]), { outcome: "error", subtype: "success", isError: true, status: 400 });
  assert.deepEqual(shape(rows[1]), { outcome: "success", subtype: "success", isError: false, status: null });
  assert.deepEqual(shape(rows[2]), { outcome: "no-result", subtype: null, isError: null, status: null });
  assert.ok(!JSON.stringify(rows).includes(MARKER) && !JSON.stringify(rows).includes("Credit balance"));
  const success = run(["query", "--sink", sink, "--outcome", "success"], { deps: fakeDeps([]) });
  assert.deepEqual(success.out.trim().split("\n").map((line) => JSON.parse(line).artifact_id), [82]);
});

test("an api_error_status that is not an integer is not stored", () => {
  const rows = transcriptMetrics([{ type: "result", subtype: "success", is_error: true, api_error_status: "Credit balance is too low" }]);
  assert.equal(rows.api_error_status, null);
});

test("a writer's one-message marker is an omitted row naming its reason and size; the same message inside a transcript is not", () => {
  const marker = (reason) => ({ type: "system", subtype: "transcript_omitted", reason, bytes: 300000, cap: 286720 });
  const shape = ({ outcome, omitted_reason: reason, omitted_bytes: bytes, num_turns: turns }) => ({ outcome, reason, bytes, turns });
  assert.deepEqual(shape(transcriptMetrics([marker("too-large")])), { outcome: "omitted", reason: "too-large", bytes: 300000, turns: null });
  assert.deepEqual(shape(transcriptMetrics([marker("credential")])), { outcome: "omitted", reason: "credential", bytes: 300000, turns: null });
  assert.deepEqual(shape(transcriptMetrics([marker("anything else")])), { outcome: "omitted", reason: "unknown", bytes: 300000, turns: null });
  assert.deepEqual(shape(transcriptMetrics([...MESSAGES, marker("too-large")])), { outcome: "success", reason: undefined, bytes: undefined, turns: 7 });
});

test("query --outcome reads is_error, so a row stored before the field existed queries correctly", () => {
  const rows = [
    { job_id: "old-failed", outcome: "success", is_error: true },
    { job_id: "old-ok", outcome: "success", is_error: false },
    { job_id: "old-turns", outcome: "error_max_turns", is_error: true },
    { job_id: "new-turns", outcome: "error", subtype: "error_max_turns", is_error: true },
    { job_id: "new-failed", outcome: "error", subtype: "success", is_error: true },
    { job_id: "no-flag", outcome: "error_during_execution", is_error: false },
    { job_id: "none", outcome: "no-result", is_error: null },
  ];
  const jobs = (outcome) => query(rows, { outcome }).map((r) => r.job_id);
  assert.deepEqual(jobs("success"), ["old-ok"]);
  assert.deepEqual(jobs("error"), ["old-failed", "old-turns", "new-turns", "new-failed"]);
  assert.deepEqual(jobs("error_max_turns"), ["old-turns", "new-turns"]);
  assert.deepEqual(jobs("error_during_execution"), ["no-flag"]);
  assert.deepEqual(jobs("no-result"), ["none"]);
});

function seedStore(sink, ages) {
  mkdirSync(sink, { recursive: true });
  const rows = ages.map((days, i) => {
    const createdAt = iso(NOW - days * 86400_000);
    const transcript = path.join("transcripts", createdAt.slice(0, 10), "pr-verify", `${i + 1}-1-verify.json.gz`);
    mkdirSync(path.dirname(path.join(sink, transcript)), { recursive: true });
    writeFileSync(path.join(sink, transcript), Buffer.alloc(1000));
    return { artifact_id: i + 1, run_id: i + 1, job_id: "verify", lane: "pr-verify", created_at: createdAt, date: createdAt.slice(0, 10), transcript };
  });
  writeRows(sink, rows);
  return rows;
}

test("prune drops transcripts over 30 days, metrics rows over a year, then the oldest transcripts over the cap", () => {
  const sink = sinkDir();
  const rows = seedStore(sink, [1, 2, 3, 31, 366]);
  const kept = readRows(sink);
  assert.equal(kept.length, 5);
  const result = prune(sink, NOW, { capBytes: 3500 });
  const after = readRows(sink);
  assert.deepEqual(after.map((r) => r.artifact_id), [1, 2, 3, 4], "the 366-day row is dropped");
  assert.deepEqual(after.map((r) => r.pruned ?? null), [null, null, "cap", "age"]);
  assert.ok(!existsSync(path.join(sink, rows[3].transcript)) && !existsSync(path.join(sink, rows[2].transcript)));
  assert.ok(existsSync(path.join(sink, rows[0].transcript)) && existsSync(path.join(sink, rows[1].transcript)));
  assert.equal(result.age, 2);
  assert.equal(result.cap, 1);
  assert.ok(result.bytes <= 3500, String(result.bytes));
  assert.equal(CAP_BYTES, 5_000_000_000);
});

test("prune ages a transcript no row names by its modification time", () => {
  const sink = sinkDir();
  seedStore(sink, []);
  const stray = path.join(sink, "transcripts", "2026-01-01", "x", "stray.json.gz");
  mkdirSync(path.dirname(stray), { recursive: true });
  writeFileSync(stray, "x");
  utimesSync(stray, new Date(NOW - 40 * 86400_000), new Date(NOW - 40 * 86400_000));
  prune(sink, NOW);
  assert.ok(!existsSync(stray));
  assert.ok(!existsSync(path.join(sink, "transcripts", "2026-01-01")), "emptied directories go too");
});

test("query filters rows by lane, lane/job, model, outcome and date", () => {
  const rows = [
    { lane: "pr-verify", job_id: "verify", model: "claude-opus-5-5", models: ["claude-opus-5-5"], outcome: "success", date: "2026-10-30" },
    { lane: "pr-verify", job_id: "judge", model: "claude-sonnet-5-5", models: [], outcome: "error_max_turns", date: "2026-11-01" },
    { lane: "intake-triage", job_id: "refine", model: null, models: ["claude-sonnet-5-5"], outcome: "success", date: "2026-11-02" },
  ];
  const jobs = (filters) => query(rows, filters).map((r) => r.job_id);
  assert.deepEqual(jobs({ lane: "pr-verify" }), ["verify", "judge"]);
  assert.deepEqual(jobs({ lane: "pr-verify/judge" }), ["judge"]);
  assert.deepEqual(jobs({ model: "sonnet" }), ["judge", "refine"]);
  assert.deepEqual(jobs({ outcome: "success", since: "2026-11-01" }), ["refine"]);
  assert.deepEqual(jobs({ until: "2026-10-31" }), ["verify"]);
  assert.throws(() => query(rows, { since: "yesterday" }), /YYYY-MM-DD/);
});

test("the query command prints matching rows with absolute transcript paths", () => {
  const sink = sinkDir();
  seedStore(sink, [1]);
  const result = run(["query", "--sink", sink, "--lane", "pr-verify"], { deps: fakeDeps([]) });
  assert.equal(result.code, 0);
  assert.equal(JSON.parse(result.out).transcript, path.join(sink, "transcripts", iso(NOW - 86400_000).slice(0, 10), "pr-verify", "1-1-verify.json.gz"));
});

test("artifact names parse to a job id and attempt; anything else does not", () => {
  assert.deepEqual(parseArtifactName("lane-transcript-refine-issue-2"), { jobId: "refine-issue", attempt: 2 });
  assert.deepEqual(parseArtifactName("lane-transcript-audit_x-1"), { jobId: "audit_x", attempt: 1 });
  for (const bad of ["lane-transcript-verify", "lane-transcript--1", "lane-transcript-../x-1", "lane-transcript-verify-0", "other-verify-1"]) {
    assert.equal(parseArtifactName(bad), null, bad);
  }
});

test("usage errors and a relative sink exit 2", () => {
  assert.equal(run([]).code, 2);
  assert.equal(run(["pull", "--bogus", "x"]).code, 2);
  assert.equal(run(["status", "--sink", "relative/dir"]).code, 2);
});

test("the sink defaults under XDG_DATA_HOME, and LANE_TRANSCRIPT_SINK replaces it", () => {
  const base = tempDir("lane-transcripts-xdg-");
  const fromXdg = JSON.parse(run(["status"], { env: { XDG_DATA_HOME: base }, deps: fakeDeps([]) }).out);
  assert.equal(fromXdg.sink, path.join(base, "lane-transcripts"));
  const fromEnv = JSON.parse(run(["status"], { env: { XDG_DATA_HOME: base, LANE_TRANSCRIPT_SINK: path.join(base, "elsewhere") }, deps: fakeDeps([]) }).out);
  assert.equal(fromEnv.sink, path.join(base, "elsewhere"));
});

test("a result's cache tokens, cost estimate and per-model usage are stored; a run with no result stores null for each", () => {
  const result = {
    type: "result",
    subtype: "success",
    is_error: false,
    total_cost_usd: 0.25,
    usage: { input_tokens: 10, output_tokens: 20, cache_read_input_tokens: 300, cache_creation_input_tokens: 40 },
    modelUsage: {
      "claude-sonnet-5-5": { inputTokens: 3, outputTokens: 4, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, costUSD: 0.05, webSearchRequests: 2 },
      "claude-opus-5-5": { inputTokens: 10, outputTokens: 20, cacheReadInputTokens: 300, cacheCreationInputTokens: 40, costUSD: 0.2, contextWindow: 200000 },
    },
  };
  const pick = ({ cache_read_input_tokens: read, cache_creation_input_tokens: created, total_cost_usd: cost, model_usage: perModel }) => ({ read, created, cost, perModel });
  assert.deepEqual(pick(transcriptMetrics([MESSAGES[0], result])), {
    read: 300,
    created: 40,
    cost: 0.25,
    perModel: {
      "claude-opus-5-5": { input_tokens: 10, output_tokens: 20, cache_read_input_tokens: 300, cache_creation_input_tokens: 40, cost_usd: 0.2 },
      "claude-sonnet-5-5": { input_tokens: 3, output_tokens: 4, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, cost_usd: 0.05 },
    },
  });
  assert.deepEqual(pick(transcriptMetrics([MESSAGES[0]])), { read: null, created: null, cost: null, perModel: null });
  assert.deepEqual(pick(transcriptMetrics([{ type: "result", total_cost_usd: -1, usage: { cache_read_input_tokens: 1.5 }, modelUsage: { m: { costUSD: "0.1" } } }])), {
    read: null,
    created: null,
    cost: null,
    perModel: { m: { input_tokens: null, output_tokens: null, cache_read_input_tokens: null, cache_creation_input_tokens: null, cost_usd: null } },
  });
});

test("the trace id is the first 32 hex of SHA-256 over lane-outcome:<run id>:<attempt>, as ci-workflows computes it", () => {
  assert.equal(traceIdOf(42, 1), "33284f6935ab289df17507682acc6c66", "printf lane-outcome:42:1 | sha256sum");
  assert.equal(traceIdOf(18234567890, 2), "6231b3dd4912b8d706768f07c9843b10", "printf lane-outcome:18234567890:2 | sha256sum");
  for (const [run, attempt] of [[null, 1], [42, 0], ["42", 1], [42, 1.5]]) assert.equal(traceIdOf(run, attempt), null, `${run}:${attempt}`);
});

test("a zip holding a second sealed file beside the transcript is pulled; a third entry, or a second that is not sealed, is a bad zip", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const record = sealed(publicLine);
  const page = [
    artifact(91, { entries: { [ENTRY]: record, "otel.jsonl.gz.sealed": "z" } }),
    artifact(92, { entries: { [ENTRY]: record, "otel.jsonl.gz.sealed": "z", "more.sealed": "z" } }),
    artifact(93, { entries: { [ENTRY]: record, "otel.jsonl.gz": "z" } }),
    artifact(94, { entries: { "a.sealed": "z", "b.sealed": "z" } }),
  ];
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: fakeDeps(page) });
  assert.equal(result.code, 0, result.err);
  assert.match(result.out, /"pulled":1,.*"bad_zip":3/);
  assert.deepEqual(readRows(sink).map((r) => r.artifact_id), [91]);
  assert.deepEqual(pickTelemetry(readRows(sink)[0]), { telemetry: null, telemetry_bytes: null, telemetry_spans: null, telemetry_joined_spans: null, telemetry_outcome: "sealed_mismatch" }, "telemetry that does not open keeps the transcript");
});

const pickTelemetry = ({ telemetry, telemetry_bytes, telemetry_spans, telemetry_joined_spans, telemetry_outcome }) => ({ telemetry, telemetry_bytes, telemetry_spans, telemetry_joined_spans, telemetry_outcome });

function telemetryLines(traceIds) {
  const spans = traceIds.map((traceId, i) => ({ traceId, spanId: `${i}`.padStart(16, "0"), name: MARKER }));
  return `${JSON.stringify({ resourceSpans: [{ scopeSpans: [{ spans }] }] })}\n${JSON.stringify({ resourceLogs: [{ scopeLogs: [{ logRecords: [{ body: { stringValue: MARKER } }] }] }] })}\n`;
}

const sealedTelemetry = (publicLine, text, { runId = 42, jobId = "check-intent", payload = TELEMETRY_PAYLOAD } = {}) => sealRecord(parsePublicKey(publicLine), payload, gzipSync(Buffer.from(text)), String(runId), jobId);

test("a pull opens the sealed telemetry beside the transcript into the sink and counts the spans that join the row's trace id", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const trace = traceIdOf(42, 1);
  const text = telemetryLines([trace, trace.toUpperCase(), "0".repeat(32)]);
  const deps = fakeDeps([artifact(95, { entries: { [ENTRY]: sealed(publicLine), [TELEMETRY_ENTRY]: sealedTelemetry(publicLine, text) } })]);
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 0, result.err);
  for (const out of [result.out, result.err]) assert.ok(!out.includes(MARKER));
  const [row] = readRows(sink);
  assert.equal(row.trace_id, trace);
  const { telemetry, telemetry_bytes: bytes, ...counts } = pickTelemetry(row);
  assert.deepEqual(counts, { telemetry_spans: 3, telemetry_joined_spans: 2, telemetry_outcome: "stored" });
  assert.equal(telemetry, row.transcript.replace(/\.json\.gz$/, ".otel.jsonl.gz"));
  const file = path.join(sink, telemetry);
  assert.equal(gunzipSync(readFileSync(file)).toString("utf8"), text);
  assert.equal(bytes, statSync(file).size);
  assert.equal(statSync(file).mode & 0o777, 0o600);
  assert.ok(!JSON.stringify(row).includes(MARKER), "the metrics row holds no telemetry text");
});

test("telemetry bound to another job or payload name is not stored, and a transcript alone records none", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const text = telemetryLines([traceIdOf(42, 1)]);
  const page = [
    artifact(96, { entries: { [ENTRY]: sealed(publicLine), [TELEMETRY_ENTRY]: sealedTelemetry(publicLine, text, { jobId: "other" }) } }),
    artifact(97, { attempt: 2, entries: { [ENTRY]: sealed(publicLine), [TELEMETRY_ENTRY]: sealedTelemetry(publicLine, text, { payload: PAYLOAD }) } }),
    artifact(98, { attempt: 3, record: sealed(publicLine) }),
  ];
  assert.equal(run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: fakeDeps(page) }).code, 0);
  const byId = Object.fromEntries(readRows(sink).map((r) => [r.artifact_id, r.telemetry_outcome]));
  assert.deepEqual(byId, { 96: "sealed_mismatch", 97: "sealed_mismatch", 98: "none" });
  assert.ok(readRows(sink).every((r) => r.telemetry === null && r.transcript));
});

test("telemetry that cannot be extracted or is over its size cap is unreadable, and the transcript is kept", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const page = [
    artifact(81, { entries: { [ENTRY]: sealed(publicLine), [TELEMETRY_ENTRY]: sealedTelemetry(publicLine, "\n".repeat(64 * 1024 * 1024 + 1)) } }),
    artifact(82, { attempt: 2, entries: { [ENTRY]: sealed(publicLine), [TELEMETRY_ENTRY]: "z" } }),
  ];
  const deps = fakeDeps(page);
  const unzip = deps.unzip;
  deps.unzip = (args) => {
    if (args[2] === TELEMETRY_ENTRY && JSON.parse(readFileSync(args[1], "utf8"))[TELEMETRY_ENTRY] === Buffer.from("z").toString("base64")) throw Object.assign(new Error("maxBuffer"), { status: 9 });
    return unzip(args);
  };
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 0, result.err);
  const byId = Object.fromEntries(readRows(sink).map((r) => [r.artifact_id, [r.telemetry_outcome, r.telemetry, Boolean(r.transcript)]]));
  assert.deepEqual(byId, { 81: ["unreadable", null, true], 82: ["unreadable", null, true] });
});

test("telemetrySpans counts spans across lines and skips a line that is not JSON", () => {
  const trace = "a".repeat(32);
  assert.deepEqual(telemetrySpans(`not json\n${telemetryLines([trace, "b".repeat(32)])}`, trace), { telemetry_spans: 2, telemetry_joined_spans: 1 });
  assert.deepEqual(telemetrySpans("", trace), { telemetry_spans: 0, telemetry_joined_spans: 0 });
});

test("prune drops a row's telemetry with its transcript, and a telemetry file gone missing clears its path", () => {
  const sink = sinkDir();
  const rows = seedStore(sink, [1, 31]);
  for (const row of rows) {
    row.telemetry = row.transcript.replace(/\.json\.gz$/, ".otel.jsonl.gz");
    writeFileSync(path.join(sink, row.telemetry), "t");
  }
  writeRows(sink, rows);
  rmSync(path.join(sink, rows[0].telemetry));
  prune(sink, NOW);
  const after = readRows(sink);
  assert.deepEqual(after.map((r) => [r.telemetry, r.pruned ?? null]), [[null, null], [null, "age"]]);
  assert.ok(existsSync(path.join(sink, after[0].transcript)), "the fresh transcript stays");
  assert.ok(!existsSync(path.join(sink, rows[1].telemetry)), "the aged telemetry goes with its transcript");
});

test("a pulled row carries its run attempt's trace id, and no failure class while no lane-outcome record is held", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  assert.equal(run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: fakeDeps([artifact(7, { record: sealed(publicLine) })]) }).code, 0);
  const [row] = readRows(sink);
  assert.deepEqual({ trace: row.trace_id, cls: row.failure_class, source: row.failure_class_source }, { trace: "33284f6935ab289df17507682acc6c66", cls: null, source: "none" });
});

const annotation = (record) => ({ annotation_level: "notice", message: `Lane stopped. lane-outcome ${JSON.stringify(record)} Last SDK result: ${MARKER}` });
const laneRecord = (fields) => ({ v: 1, lane: "pr-verify", outcome: "failure", class: "max-turns", credential: { secret: "CLAUDE_CODE_OAUTH_TOKEN", kind: "oauth-token" }, ...fields });
const laneRun = (id, { attempt = 1, fork = false, path: workflowPath = ".github/workflows/pr-verify.yml" } = {}) => ({ id, run_attempt: attempt, name: "pr-verify", path: workflowPath, repository: { id: REPO_ID }, head_repository: { id: fork ? 1 : REPO_ID }, created_at: iso(NOW - 3600_000) });
const laneJob = (id, { attempt = 1, conclusion = "failure", name = "check-intent" } = {}) => ({ id, run_attempt: attempt, name, conclusion, completed_at: iso(NOW - 3600_000) });

function outcomeDeps({ runs = {}, jobs = {}, annotations = {} } = {}) {
  const calls = [];
  return {
    calls,
    now: () => NOW,
    sleep: () => {},
    gh(args) {
      calls.push(args[1]);
      let m = /actions\/workflows\/([^/]+)\/runs\?created=[^&]+&status=completed&per_page=100&page=(\d+)$/.exec(args[1]);
      if (m) return Buffer.from(JSON.stringify({ workflow_runs: m[2] === "1" ? (runs[m[1]] ?? []) : [] }));
      m = /actions\/runs\/(\d+)\/jobs\?filter=all&per_page=100&page=(\d+)$/.exec(args[1]);
      if (m) return Buffer.from(JSON.stringify({ jobs: m[2] === "1" ? (jobs[m[1]] ?? []) : [] }));
      m = /check-runs\/(\d+)\/annotations\?per_page=100&page=(\d+)$/.exec(args[1]);
      if (m) return Buffer.from(JSON.stringify(m[2] === "1" ? (annotations[m[1]] ?? []) : []));
      throw Object.assign(new Error("unexpected gh call"), { status: 9 });
    },
    unzip() {
      throw new Error("pull-outcomes opens no zip");
    },
  };
}

test("pull-outcomes copies each validated record from a lane run's job annotations, skipping forks, skipped jobs and records naming another run, and sets the row's failure class", () => {
  const sink = sinkDir();
  mkdirSync(sink, { recursive: true });
  writeRows(sink, [{ artifact_id: 1, run_id: 501, run_attempt: 1, job_id: "check-intent", created_at: iso(NOW - 3600_000), date: "2026-11-02", transcript: null }]);
  const deps = outcomeDeps({
    runs: { "pr-verify.yml": [laneRun(501), laneRun(502, { fork: true })] },
    jobs: { 501: [laneJob(9001), laneJob(9002, { conclusion: "skipped" }), laneJob(9003, { conclusion: "success", name: "report" })] },
    annotations: {
      9001: [annotation(laneRecord({ runId: 501, runAttempt: 1 })), { message: "Node 20 is deprecated" }],
      9003: [annotation(laneRecord({ runId: 777 })), annotation({ v: 2, lane: "x" })],
    },
  });
  const result = run(["pull-outcomes", "--sink", sink], { deps });
  assert.equal(result.code, 0, result.err);
  assert.ok(!deps.calls.some((c) => c.includes("runs/502/")), "a fork run is not read");
  assert.ok(!deps.calls.some((c) => c.includes("check-runs/9002/")), "a skipped job is not read");
  const outcomes = readOutcomes(sink);
  assert.equal(outcomes.length, 1);
  assert.deepEqual(
    { run: outcomes[0].run_id, attempt: outcomes[0].run_attempt, trace: outcomes[0].trace_id, check: outcomes[0].check_run_id, lane: outcomes[0].lane, cls: outcomes[0].record.class },
    { run: 501, attempt: 1, trace: traceIdOf(501, 1), check: 9001, lane: "pr-verify", cls: "max-turns" },
  );
  assert.ok(!readFileSync(paths(sink).outcomes, "utf8").includes(MARKER), "no annotation free text is stored");
  assert.match(result.out, /"mismatched":1/);
  const [row] = readRows(sink);
  assert.deepEqual({ cls: row.failure_class, source: row.failure_class_source, trace: row.trace_id }, { cls: "max-turns", source: "lane-outcome", trace: traceIdOf(501, 1) });
  assert.deepEqual(query(readRows(sink), { class: "max-turns" }).map((r) => r.artifact_id), [1]);
  assert.deepEqual(query(readRows(sink), { trace: traceIdOf(501, 1) }).map((r) => r.artifact_id), [1]);

  const again = outcomeDeps({ runs: { "pr-verify.yml": [laneRun(501)] }, jobs: { 501: [laneJob(9001)] }, annotations: {} });
  assert.equal(run(["pull-outcomes", "--sink", sink], { deps: again }).code, 0);
  assert.ok(!again.calls.some((c) => c.includes("check-runs/9001/")), "a job already held is not read again");
  assert.equal(readOutcomes(sink).length, 1);
});

test("the puller starts from an export of only its own directory and the two lane-output actions", () => {
  const root = tempDir("lane-transcripts-export-");
  const repoRoot = path.join(import.meta.dirname, "..", "..");
  for (const dir of ["scripts/lane-transcripts", ".github/actions/open-lane-output", ".github/actions/seal-lane-output"]) {
    cpSync(path.join(repoRoot, dir), path.join(root, dir), { recursive: true });
  }
  const out = execFileSync(process.execPath, [path.join(root, "scripts/lane-transcripts/pull.mjs"), "query", "--sink", path.join(root, "sink")], { encoding: "utf8" });
  assert.equal(out, "");
});

test("a job an interrupted pull left half written is read again whole, so its records can still disagree", () => {
  const sink = sinkDir();
  mkdirSync(sink, { recursive: true });
  writeRows(sink, [{ artifact_id: 1, run_id: 501, run_attempt: 1, job_id: "check-intent", created_at: iso(NOW - 3600_000), date: "2026-11-02", transcript: null }]);
  const first = laneRecord({ class: "rate-limit" });
  const half = { run_id: 501, run_attempt: 1, trace_id: traceIdOf(501, 1), check_run_id: 9001, job_name: "check-intent", lane: "pr-verify", workflow: "pr-verify", created_at: iso(NOW - 3600_000), date: "2026-11-02", record: first, job_records: 2 };
  writeFileSync(paths(sink).outcomes, `${JSON.stringify(half)}\n`);
  const deps = outcomeDeps({
    runs: { "pr-verify.yml": [laneRun(501)] },
    jobs: { 501: [laneJob(9001)] },
    annotations: { 9001: [annotation(first), annotation(laneRecord({ class: "overloaded" }))] },
  });
  assert.equal(run(["pull-outcomes", "--sink", sink], { deps }).code, 0);
  assert.deepEqual(readOutcomes(sink).map((o) => [o.record.class, o.job_records]), [["rate-limit", 2], ["overloaded", 2]]);
  const [row] = readRows(sink);
  assert.deepEqual([row.failure_class, row.failure_class_source], [null, "disagree"]);
});

test("a row's failure class stays null when its run attempt's records disagree, and differs per attempt", () => {
  const sink = sinkDir();
  mkdirSync(sink, { recursive: true });
  writeRows(sink, [1, 2].map((attempt) => ({ artifact_id: attempt, run_id: 601, run_attempt: attempt, job_id: "review", created_at: iso(NOW - 3600_000), date: "2026-11-02", transcript: null })));
  const deps = outcomeDeps({
    runs: { "pr-review-hosted.yml": [laneRun(601, { attempt: 2 })] },
    jobs: { 601: [laneJob(1, { attempt: 1 }), laneJob(2, { attempt: 1, name: "review-2" }), laneJob(3, { attempt: 2 })] },
    annotations: {
      1: [annotation(laneRecord({ class: "rate-limit", handoff: true }))],
      2: [annotation(laneRecord({ outcome: "success", class: undefined }))],
      3: [annotation(laneRecord({ class: "overloaded" }))],
    },
  });
  assert.equal(run(["pull-outcomes", "--sink", sink], { deps }).code, 0);
  assert.deepEqual(readRows(sink).map((r) => [r.failure_class, r.failure_class_source]), [[null, "disagree"], ["overloaded", "lane-outcome"]]);
});

const twoLegRows = (sink, jobIds) => writeRows(sink, jobIds.map((jobId, i) => ({ artifact_id: i + 1, run_id: 801, run_attempt: 1, job_id: jobId, created_at: iso(NOW - 3600_000), date: "2026-11-02", transcript: null })));
const pullTwoLegs = (sink, records) => {
  const deps = outcomeDeps({
    runs: { "pr-verify.yml": [laneRun(801)] },
    jobs: { 801: records.map((_, i) => laneJob(i + 1, { name: `leg-${i + 1}` })) },
    annotations: Object.fromEntries(records.map((record, i) => [i + 1, [annotation(laneRecord(record))]])),
  });
  assert.equal(run(["pull-outcomes", "--sink", sink], { deps }).code, 0);
  return readRows(sink).map((r) => [r.job_id, r.failure_class, r.failure_class_source]);
};

test("in an attempt with one failed and one successful job, each row takes its own job's record by jobId", () => {
  const sink = sinkDir();
  mkdirSync(sink, { recursive: true });
  twoLegRows(sink, ["check-intent", "judge"]);
  const rows = pullTwoLegs(sink, [{ jobId: "check-intent", class: "rate-limit" }, { jobId: "judge", outcome: "success", class: undefined }]);
  assert.deepEqual(rows, [
    ["check-intent", "rate-limit", "lane-outcome"],
    ["judge", null, "lane-outcome"],
  ]);
});

test("two jobs failing with different classes each keep their own class by jobId", () => {
  const sink = sinkDir();
  mkdirSync(sink, { recursive: true });
  twoLegRows(sink, ["check-intent", "judge"]);
  const rows = pullTwoLegs(sink, [{ jobId: "check-intent", class: "rate-limit" }, { jobId: "judge", class: "overloaded" }]);
  assert.deepEqual(rows, [
    ["check-intent", "rate-limit", "lane-outcome"],
    ["judge", "overloaded", "lane-outcome"],
  ]);
});

test("records with no jobId set every row of the attempt as before, and a row no jobId matches falls back to them alone", () => {
  const old = sinkDir();
  mkdirSync(old, { recursive: true });
  twoLegRows(old, ["check-intent", "judge"]);
  assert.deepEqual(pullTwoLegs(old, [{ class: "rate-limit" }, { outcome: "success", class: undefined }]), [
    ["check-intent", null, "disagree"],
    ["judge", null, "disagree"],
  ]);
  const agreeing = sinkDir();
  mkdirSync(agreeing, { recursive: true });
  twoLegRows(agreeing, ["check-intent", "judge"]);
  assert.deepEqual(pullTwoLegs(agreeing, [{ class: "rate-limit" }, { class: "rate-limit" }]), [
    ["check-intent", "rate-limit", "lane-outcome"],
    ["judge", "rate-limit", "lane-outcome"],
  ]);
  const mixed = sinkDir();
  mkdirSync(mixed, { recursive: true });
  twoLegRows(mixed, ["check-intent", "judge", "report"]);
  assert.deepEqual(pullTwoLegs(mixed, [{ jobId: "check-intent", class: "rate-limit" }, { jobId: "elsewhere", class: "auth" }, { class: "overloaded" }]), [
    ["check-intent", "rate-limit", "lane-outcome"],
    ["judge", "overloaded", "lane-outcome"],
    ["report", "overloaded", "lane-outcome"],
  ]);
  const unmatched = sinkDir();
  mkdirSync(unmatched, { recursive: true });
  twoLegRows(unmatched, ["check-intent", "report"]);
  assert.deepEqual(pullTwoLegs(unmatched, [{ jobId: "check-intent", class: "rate-limit" }]), [
    ["check-intent", "rate-limit", "lane-outcome"],
    ["report", null, "none"],
  ]);
});

test("pull-outcomes lists each lane workflow once, stops at its own budget without touching the transcript pull's state, and resumes at the workflow it stopped on", () => {
  const sink = sinkDir();
  const transcriptState = { last_success_at: iso(NOW - 3600_000), resume_cutoff_at: null, gh_calls: 12 };
  seedState(sink, transcriptState);
  const full = outcomeDeps();
  assert.equal(run(["pull-outcomes", "--sink", sink], { deps: full }).code, 0);
  assert.deepEqual(full.calls.map((c) => /workflows\/([^/]+)\/runs/.exec(c)?.[1]), LANE_WORKFLOWS);
  const stopped = { ...outcomeDeps(), outcomeCallBudget: 3 };
  const result = run(["pull-outcomes", "--sink", sink], { deps: stopped });
  assert.equal(result.code, 0, result.err);
  assert.match(result.out, /gh calls: 3 of 3/);
  const state = stateOf(sink);
  assert.deepEqual({ last_success_at: state.last_success_at, resume_cutoff_at: state.resume_cutoff_at, gh_calls: state.gh_calls }, transcriptState);
  assert.deepEqual({ exhausted: state.outcomes.budget_exhausted, workflow: state.outcomes.resume_workflow }, { exhausted: true, workflow: LANE_WORKFLOWS[3] });
  const resumed = outcomeDeps();
  run(["pull-outcomes", "--sink", sink], { deps: resumed });
  assert.equal(/workflows\/([^/]+)\/runs/.exec(resumed.calls[0])[1], LANE_WORKFLOWS[3]);
  assert.equal(stateOf(sink).outcomes.budget_exhausted, false);
});

test("backfill fills trace_id, the cache, cost and per-model fields from a stored transcript, and a second run leaves the file byte for byte", () => {
  const sink = sinkDir();
  const transcript = path.join("transcripts", "2026-11-01", "pr-verify", "42-1-check-intent.json.gz");
  mkdirSync(path.dirname(path.join(sink, transcript)), { recursive: true });
  const messages = [MESSAGES[0], { ...MESSAGES[2], total_cost_usd: 1.5, usage: { input_tokens: 10, output_tokens: 20, cache_read_input_tokens: 7 } }];
  writeFileSync(path.join(sink, transcript), gzipSync(Buffer.from(JSON.stringify(messages))));
  writeRows(sink, [
    { artifact_id: 1, run_id: 42, run_attempt: 1, created_at: iso(NOW), date: "2026-11-02", transcript },
    { artifact_id: 2, run_id: 18234567890, run_attempt: 2, created_at: iso(NOW), date: "2026-11-02", transcript: null, pruned: "age" },
  ]);
  const first = run(["backfill", "--sink", sink], { deps: fakeDeps([]) });
  assert.equal(first.code, 0, first.err);
  const [stored, pruned] = readRows(sink);
  assert.deepEqual(
    { trace: stored.trace_id, read: stored.cache_read_input_tokens, created: stored.cache_creation_input_tokens, cost: stored.total_cost_usd, models: Object.keys(stored.model_usage), source: stored.failure_class_source },
    { trace: "33284f6935ab289df17507682acc6c66", read: 7, created: null, cost: 1.5, models: ["claude-opus-5-5", "claude-sonnet-5-5"], source: "none" },
  );
  assert.deepEqual({ trace: pruned.trace_id, cost: pruned.total_cost_usd }, { trace: "6231b3dd4912b8d706768f07c9843b10", cost: undefined });
  const bytes = readFileSync(paths(sink).metrics);
  const second = run(["backfill", "--sink", sink], { deps: fakeDeps([]) });
  assert.equal(JSON.parse(second.out).changed, 0);
  assert.ok(readFileSync(paths(sink).metrics).equals(bytes));
});

test("prune drops lane-outcome records over a year old with the metrics rows", () => {
  const sink = sinkDir();
  seedStore(sink, []);
  writeFileSync(paths(sink).outcomes, [364, 366].map((days) => `${JSON.stringify({ check_run_id: days, created_at: iso(NOW - days * 86400_000) })}\n`).join(""));
  assert.equal(prune(sink, NOW).outcomes, 1);
  assert.deepEqual(readOutcomes(sink).map((o) => o.check_run_id), [364]);
});

/**
 * The lane workflows read from the workflow text: a `uses:` line naming
 * report-lane-outcome, run-claude-cli, a ci-workflows lane reusable, or a
 * local reusable that is itself a lane workflow; a workflow_call-only file
 * has no runs of its own.
 */
test("every workflow whose runs write lane-outcome records is in LANE_WORKFLOWS, and nothing else", () => {
  const files = new Map(workflowLines());
  const direct = /^\s+(- )?uses:\s*melodic-software\/ci-workflows\/\.github\/(actions\/(report-lane-outcome|run-claude-cli)|workflows\/(pr-review-cli|intake-triage)\.yml)@/;
  const local = (lines) => lines.map((l) => /^\s+(- )?uses:\s*\.\/\.github\/workflows\/([^\s@]+\.yml)/.exec(l)?.[2]).filter(Boolean);
  const lane = new Set([...files].filter(([, lines]) => lines.some((l) => direct.test(l))).map(([file]) => file));
  for (let grew = true; grew; ) {
    grew = false;
    for (const [file, lines] of files) if (!lane.has(file) && local(lines).some((called) => lane.has(called))) grew = lane.add(file);
  }
  const callOnly = (lines) => {
    const at = lines.findIndex((l) => /^on:/.test(l));
    const triggers = lines.slice(at + 1).filter((l, i, rest) => rest.slice(0, i).every((p) => !/^\S/.test(p)) && /^ {2}[a-z_]+:/.test(l));
    return triggers.length === 1 && /workflow_call/.test(triggers[0]);
  };
  const expected = [...lane].filter((file) => !callOnly(files.get(file))).sort();
  assert.ok(expected.includes("pr-verify.yml") && !expected.includes("pr-run-activity-read.yml"), "a lane caller is in, a reusable is out");
  assert.deepEqual([...LANE_WORKFLOWS].sort(), expected);
});

test("a pull-outcomes pass after a budget stop skips each run attempt it already read, though its jobs held no record", () => {
  const sink = sinkDir();
  const backlog = { runs: { [LANE_WORKFLOWS[0]]: [laneRun(701), laneRun(702)] }, jobs: { 701: [laneJob(71, { conclusion: "success", name: "gate" })], 702: [laneJob(72)] }, annotations: { 72: [annotation(laneRecord({}))] } };
  const first = { ...outcomeDeps(backlog), outcomeCallBudget: 3 };
  assert.equal(run(["pull-outcomes", "--sink", sink], { deps: first }).code, 0);
  assert.deepEqual(first.calls.filter((c) => c.includes("/runs/7")).map((c) => /runs\/(\d+)/.exec(c)[1]), ["701"]);
  const shown = JSON.parse(run(["status", "--sink", sink], { deps: fakeDeps([]) }).out);
  assert.deepEqual({ exhausted: shown.outcomes_budget_exhausted, resume: shown.outcomes_resume_cutoff_at }, { exhausted: true, resume: new Date(NOW - 30 * 86400_000).toISOString() });
  const second = outcomeDeps(backlog);
  assert.equal(run(["pull-outcomes", "--sink", sink], { deps: second }).code, 0);
  assert.ok(!second.calls.some((c) => c.includes("runs/701/") || c.includes("check-runs/71/")), "the run read before the stop costs no call");
  assert.deepEqual(readOutcomes(sink).map((o) => o.check_run_id), [72]);
});
