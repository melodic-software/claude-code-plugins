import assert from "node:assert/strict";
import { existsSync, readFileSync, statSync, utimesSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { gunzipSync, gzipSync } from "node:zlib";

import { generate } from "../../.github/actions/open-lane-output/keygen.mjs";
import { parsePublicKey, sealRecord } from "../../.github/actions/seal-lane-output/seal.mjs";
import { tempDir } from "../../lib/test-tmp.mjs";
import { ENTRY, main, PAYLOAD } from "./pull.mjs";
import { CAP_BYTES, parseArtifactName, paths, prune, query, readRows, writeRows } from "./store.mjs";

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

function fakeDeps(pages, { now = NOW, runs = {} } = {}) {
  const calls = [];
  const byId = new Map(pages.flat().map((a) => [a.id, a]));
  return {
    calls,
    now: () => now,
    gh(args) {
      calls.push(args.join(" "));
      const url = args[1];
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
  assert.match(failed.err, /pull failed: a gh or unzip call exited 4/);
  assert.match(failed.err, /^ALERT: no lane transcript pull has succeeded in the last 5 days \(last: never\)$/m);
  assert.equal(run(["status", "--sink", sink], { deps: fakeDeps([]) }).code, 1);
  assert.equal(run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: fakeDeps([[]]) }).code, 0);
  assert.equal(run(["status", "--sink", sink], { deps: fakeDeps([], { now: NOW + 4 * 86400_000 }) }).code, 0);
  const late = run(["status", "--sink", sink], { deps: fakeDeps([], { now: NOW + 6 * 86400_000 }) });
  assert.equal(late.code, 1);
  assert.match(late.err, /^ALERT: /m);
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
