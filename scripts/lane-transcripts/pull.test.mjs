import assert from "node:assert/strict";
import { existsSync, readFileSync, statSync, utimesSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { gunzipSync, gzipSync } from "node:zlib";

import { generate } from "../../.github/actions/open-lane-output/keygen.mjs";
import { parsePublicKey, sealRecord } from "../../.github/actions/seal-lane-output/seal.mjs";
import { tempDir } from "../../lib/test-tmp.mjs";
import { ENTRY, main, PAYLOAD } from "./pull.mjs";
import { CAP_BYTES, parseArtifactName, paths, prune, query, readRows, transcriptMetrics, writeRows } from "./store.mjs";

const MARKER = "plaintext-marker-5d21";
const NOW = Date.parse("2026-11-02T12:00:00Z");
const REPO_ID = 1277265216;
const MESSAGES = [
  { type: "system", subtype: "init", model: "claude-opus-5-5", session_id: "s" },
  { type: "assistant", message: { content: [{ type: "text", text: MARKER }] } },
  { type: "result", subtype: "success", is_error: false, num_turns: 7, duration_ms: 1200, usage: { input_tokens: 10, output_tokens: 20 }, modelUsage: { "claude-opus-5-5": {}, "claude-sonnet-5-5": {} } },
];
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, "Z");

// A fake artifact zip: the fake unzip reads this JSON back as its entries.
const zipOf = (entries) => Buffer.from(JSON.stringify(Object.fromEntries(Object.entries(entries).map(([k, v]) => [k, Buffer.from(v).toString("base64")]))));

function artifact(id, { jobId = "verify", attempt = 1, runId = 42, createdAt = NOW - 60_000, fork = false, entries, record }) {
  return { id, name: `lane-transcript-${jobId}-${attempt}`, size_in_bytes: 100, expired: false, created_at: iso(createdAt), workflow_run: { id: runId, repository_id: REPO_ID, head_repository_id: fork ? 1 : REPO_ID }, zip: zipOf(entries ?? { [ENTRY]: record }) };
}

function sealed(publicLine, { runId = 42, jobId = "verify", messages = MESSAGES } = {}) {
  return sealRecord(parsePublicKey(publicLine), PAYLOAD, gzipSync(Buffer.from(JSON.stringify(messages))), String(runId), jobId);
}

// `failures` maps a gh URL's suffix to how many calls to it fail before one succeeds.
function fakeDeps(pages, { now = NOW, runs = {}, failures = {} } = {}) {
  const calls = [];
  const sleeps = [];
  const byId = new Map(pages.flat().map((a) => [a.id, a]));
  const left = { ...failures };
  return {
    calls,
    sleeps,
    now: () => now,
    sleep: (ms) => sleeps.push(ms),
    gh(args) {
      calls.push(args.join(" "));
      const url = args[1];
      const failing = Object.keys(left).find((suffix) => url.endsWith(suffix));
      if (failing && left[failing]-- > 0) throw Object.assign(new Error(`HTTP 502 ${MARKER}`), { status: 1 });
      let m = /actions\/artifacts\?per_page=100&page=(\d+)$/.exec(url);
      if (m) return Buffer.from(JSON.stringify({ artifacts: (pages[Number(m[1]) - 1] ?? []).map(({ zip, ...a }) => a) }));
      m = /actions\/artifacts\/(\d+)\/zip$/.exec(url);
      if (m) return byId.get(Number(m[1])).zip;
      m = /actions\/runs\/(\d+)$/.exec(url);
      if (m) return Buffer.from(JSON.stringify(runs[m[1]] ?? { path: ".github/workflows/pr-verify.yml", name: "pr-verify", event: "pull_request", head_branch: "feat/x", conclusion: "success" }));
      throw Object.assign(new Error("unexpected gh call"), { status: 9 });
    },
    unzip(args) {
      const entries = JSON.parse(readFileSync(args[1], "utf8"));
      if (args[0] === "-Z1") return Buffer.from(Object.keys(entries).join("\n"));
      return Buffer.from(entries[args[2]], "base64");
    },
  };
}

function run(argv, { env = {}, deps } = {}) {
  let out = "";
  let err = "";
  const code = main(argv, env, deps, { out: (s) => (out += s), err: (s) => (err += s) });
  return { code, out, err };
}

const sinkDir = () => path.join(tempDir("lane-transcripts-"), "sink");

test("a pull opens each sealed transcript into the sink, gzipped, with a metrics row and no plaintext on stdout or stderr", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const env = { LANE_TRANSCRIPT_PRIVATE_KEY: privateText };
  const deps = fakeDeps([[artifact(7, { record: sealed(publicLine) })]]);
  const result = run(["pull", "--sink", sink], { env, deps });
  assert.equal(result.code, 0, result.err);
  assert.equal(env.LANE_TRANSCRIPT_PRIVATE_KEY, undefined, "the key leaves the environment");
  for (const text of [result.out, result.err]) assert.ok(!text.includes(MARKER) && !text.includes(privateText));
  const [row] = readRows(sink);
  assert.deepEqual(
    { lane: row.lane, job: row.job_id, run: row.run_id, model: row.model, models: row.models, outcome: row.outcome, turns: row.num_turns, date: row.date },
    { lane: "pr-verify", job: "verify", run: 42, model: "claude-opus-5-5", models: ["claude-opus-5-5", "claude-sonnet-5-5"], outcome: "success", turns: 7, date: "2026-11-02" },
  );
  assert.ok(!JSON.stringify(row).includes(MARKER), "the metrics row holds no transcript text");
  const file = path.join(sink, row.transcript);
  assert.deepEqual(JSON.parse(gunzipSync(readFileSync(file)).toString("utf8")), MESSAGES);
  assert.equal(statSync(file).mode & 0o777, 0o600);
  assert.equal(statSync(sink).mode & 0o777, 0o700);
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
    artifact(14, { jobId: "judge", record: sealed(publicLine, { jobId: "judge" }) }),
  ];
  let deps = fakeDeps([page]);
  const first = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(first.code, 0, first.err);
  assert.match(first.out, /"pulled":1,"known":0,"fork":1,.*"bad_zip":1,"sealed_mismatch":2/);
  assert.ok(!deps.calls.some((c) => c.includes("artifacts/10/zip")), "a fork artifact is never downloaded");
  deps = fakeDeps([page]);
  const second = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.match(second.out, /"pulled":0,"known":1/);
  assert.ok(!deps.calls.some((c) => c.includes("artifacts/14/zip")), "a held artifact is not downloaded again");
  assert.equal(readRows(sink).length, 1);
});

test("a pull stops paging at artifacts older than the last successful pull, less the overlap", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  mkdirSync(sink, { recursive: true });
  writeFileSync(paths(sink).state, JSON.stringify({ last_success_at: iso(NOW - 24 * 3600_000) }));
  const full = Array.from({ length: 100 }, (_, i) => ({ ...artifact(1000 - i, { record: sealed(publicLine) }), name: "other-artifact" }));
  full[99].created_at = iso(NOW - 31 * 3600_000);
  const deps = fakeDeps([full, [artifact(5, { record: sealed(publicLine) })]]);
  assert.equal(run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps }).code, 0);
  assert.ok(!deps.calls.some((c) => c.includes("page=2")), deps.calls.join("\n"));
});

test("a pull that hits the page cap before the cutoff fails and keeps the last success", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  mkdirSync(sink, { recursive: true });
  const last = iso(NOW - 3 * 86400_000);
  writeFileSync(paths(sink).state, JSON.stringify({ last_success_at: last }));
  const full = () => Array.from({ length: 100 }, (_, i) => ({ ...artifact(5000 - i, { record: sealed(publicLine) }), name: "other-artifact" }));
  const deps = { ...fakeDeps([full(), full(), full()]), maxPages: 2 };
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 1);
  assert.match(result.err, /pull failed: page-cap: 2 pages/);
  assert.equal(JSON.parse(readFileSync(paths(sink).state, "utf8")).last_success_at, last);
});

test("a pull where every transcript fails to open for the key fails, so the stale alert can fire", () => {
  const { privateText } = generate();
  const other = generate();
  const sink = sinkDir();
  const deps = fakeDeps([[artifact(21, { record: sealed(other.publicLine) }), artifact(22, { jobId: "judge", record: sealed(other.publicLine, { jobId: "judge" }) })]]);
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 1);
  assert.match(result.err, /pull failed: key-mismatch: 2 transcript/);
  assert.equal(JSON.parse(readFileSync(paths(sink).state, "utf8")).last_success_at, undefined);
});

test("a metrics append cut short leaves a tail the next pull drops and replaces", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const env = () => ({ LANE_TRANSCRIPT_PRIVATE_KEY: privateText });
  assert.equal(run(["pull", "--sink", sink], { env: env(), deps: fakeDeps([[artifact(31, { record: sealed(publicLine) })]]) }).code, 0);
  writeFileSync(paths(sink).metrics, '{"artifact_id":32,"run_id":4', { flag: "a" });
  assert.equal(run(["status", "--sink", sink], { deps: fakeDeps([]) }).code, 0);
  assert.deepEqual(readRows(sink).map((r) => r.artifact_id), [31]);
  const page = [artifact(32, { jobId: "judge", record: sealed(publicLine, { jobId: "judge" }) }), artifact(31, { record: sealed(publicLine) })];
  const again = run(["pull", "--sink", sink], { env: env(), deps: fakeDeps([page]) });
  assert.equal(again.code, 0, again.err);
  assert.deepEqual(readRows(sink).map((r) => r.artifact_id), [31, 32]);
  assert.ok(readFileSync(paths(sink).metrics, "utf8").endsWith("}\n"));
});

test("a pull with no key, or a malformed one, fails naming the kind only", () => {
  for (const key of [undefined, "", "not-a-key"]) {
    const result = run(["pull", "--sink", sinkDir()], { env: key === undefined ? {} : { LANE_TRANSCRIPT_PRIVATE_KEY: key }, deps: fakeDeps([[]]) });
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
  assert.equal(run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: fakeDeps([[]]) }).code, 0);
  assert.equal(run(["status", "--sink", sink], { deps: fakeDeps([], { now: NOW + 4 * 86400_000 }) }).code, 0);
  const late = run(["status", "--sink", sink], { deps: fakeDeps([], { now: NOW + 6 * 86400_000 }) });
  assert.equal(late.code, 1);
  assert.match(late.err, /^ALERT: /m);
});

const FOREVER = Number.MAX_SAFE_INTEGER;
const stateOf = (sink) => JSON.parse(readFileSync(paths(sink).state, "utf8"));
const seedState = (sink, state) => {
  mkdirSync(sink, { recursive: true });
  writeFileSync(paths(sink).state, JSON.stringify(state));
};
const zipCalls = (deps, id) => deps.calls.filter((c) => c.endsWith(`artifacts/${id}/zip`)).length;

test("a gh call that fails is retried with a growing delay, and the pull then succeeds", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const deps = fakeDeps([[artifact(41, { record: sealed(publicLine) })]], { failures: { "artifacts/41/zip": 2, "actions/runs/42": 1, "page=1": 1 } });
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 0, result.err);
  assert.equal(readRows(sink).length, 1);
  assert.equal(zipCalls(deps, 41), 3);
  assert.deepEqual(deps.sleeps, [2000, 2000, 4000, 2000], "page, zip twice, run");
  assert.equal(stateOf(sink).last_success_at, new Date(NOW).toISOString());
});

test("the retry count and delay are injectable", () => {
  const { publicLine, privateText } = generate();
  const deps = { ...fakeDeps([[artifact(42, { record: sealed(publicLine) })]], { failures: { "artifacts/42/zip": FOREVER } }), ghAttempts: 2, ghDelayMs: 5 };
  assert.equal(run(["pull", "--sink", sinkDir()], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps }).code, 1);
  assert.equal(zipCalls(deps, 42), 2);
  assert.deepEqual(deps.sleeps, [5]);
});

test("a zip fetch keeps the short schedule: five tries, about 30 s, while a listing page gets the long one", () => {
  const { publicLine, privateText } = generate();
  const deps = fakeDeps([[artifact(42, { record: sealed(publicLine) })]], { failures: { "artifacts/42/zip": FOREVER } });
  run(["pull", "--sink", sinkDir()], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(zipCalls(deps, 42), 5);
  assert.deepEqual(deps.sleeps, [2000, 4000, 8000, 16000]);
});

for (const [kind, failures] of [["artifact-zip", { "artifacts/51/zip": FOREVER }], ["run-read", { "actions/runs/51": FOREVER }]]) {
  test(`a fetch failure (${kind}) past its retries is counted, the pull goes on, and the next pull fetches the artifact though it is behind the failed pull's overlap`, () => {
    const { publicLine, privateText } = generate();
    const sink = sinkDir();
    const previous = iso(NOW - 24 * 3600_000);
    seedState(sink, { last_success_at: previous });
    const env = () => ({ LANE_TRANSCRIPT_PRIVATE_KEY: privateText });
    // Older than OVERLAP (6 hours) at the failed pull, so a cutoff taken from that pull would miss it.
    const failing = artifact(51, { runId: 51, createdAt: NOW - 10 * 3600_000, record: sealed(publicLine, { runId: 51 }) });
    const healthy = artifact(52, { jobId: "judge", runId: 52, record: sealed(publicLine, { runId: 52, jobId: "judge" }) });

    const partial = run(["pull", "--sink", sink], { env: env(), deps: fakeDeps([[failing, healthy]], { failures }) });
    assert.equal(partial.code, 0, partial.err);
    assert.match(partial.out, /"fetch_failed":1/);
    assert.deepEqual(readRows(sink).map((r) => r.artifact_id), [52], "the artifact listed after the failure is still pulled");
    const state = stateOf(sink);
    assert.equal(state.last_success_at, previous, "a pull that missed an artifact does not move the cutoff");
    assert.equal(state.last_error, `fetch-failed: 1 transcript(s) (${kind})`);
    assert.equal(state.last_tally.fetch_failed, 1);
    assert.equal(state.last_attempt_at, new Date(NOW).toISOString());
    for (const text of [partial.out, partial.err, JSON.stringify(state)]) assert.ok(!text.includes(MARKER), "no call's error text is stored or printed");

    const later = NOW + 3600_000;
    const clean = run(["pull", "--sink", sink], { env: env(), deps: fakeDeps([[failing, healthy]], { now: later }) });
    assert.equal(clean.code, 0, clean.err);
    assert.deepEqual(readRows(sink).map((r) => r.artifact_id).sort(), [51, 52]);
    assert.equal(stateOf(sink).last_success_at, new Date(later).toISOString());
    assert.equal(stateOf(sink).last_error, null);
  });
}

test("a zip that unzip cannot read is a fetch failure, not an aborted pull or a permanent skip", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  const fake = fakeDeps([[artifact(53, { record: sealed(publicLine) })]]);
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
  const fake = fakeDeps([[artifact(54, { record: sealed(publicLine) }), artifact(55, { jobId: "judge", record: sealed(publicLine, { jobId: "judge" }) })]]);
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
  const full = Array.from({ length: 100 }, (_, i) => ({ ...artifact(6000 - i, { record: sealed(publicLine) }), name: "other-artifact" }));
  const deps = fakeDeps([full, []], { failures: { "page=2": FOREVER } });
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 1);
  assert.match(result.err, /pull failed: artifact-list: gh exited 1/);
  assert.ok(!result.err.includes(MARKER));
  assert.equal(deps.calls.filter((c) => c.endsWith("page=2")).length, 10);
  assert.deepEqual(deps.sleeps, [2000, 4000, 8000, 16000, 32000, 64000, 128000, 256000, 300000], "the wait doubles to a 5 min cap, about 13.5 min before giving up");
  assert.equal(stateOf(sink).last_success_at, last);
});

test("a pull with a fetch failure exits 0 until the held last success is over 5 days old, then alerts", () => {
  const { publicLine, privateText } = generate();
  const attempt = (ageDays) => {
    const sink = sinkDir();
    seedState(sink, { last_success_at: iso(NOW - ageDays * 86400_000) });
    const deps = fakeDeps([[artifact(61, { record: sealed(publicLine) })]], { failures: { "artifacts/61/zip": FOREVER } });
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
  const page = [artifact(71, { record: sealed(other.publicLine) }), artifact(72, { jobId: "judge", record: sealed(other.publicLine, { jobId: "judge" }) })];
  const deps = fakeDeps([page], { failures: { "artifacts/72/zip": FOREVER } });
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
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: fakeDeps([page]) });
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
