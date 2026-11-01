// The expected arguments come from babysit_verify_evidence.py's `evidence`
// command line (main: --repo, --base-sha, number, head) and its report line
// (Evidence.report: refusal, head, detail).
import assert from "node:assert/strict";
import { test } from "node:test";

import { spawn as spawnChild } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { carrySteps, DEADLINE_UNREADABLE, FAIL, final, LISTING_MISS_PREFIX, NO_INCREMENTAL_WAITS, SIBLING_UNREADABLE, SUPERSEDED_AT_HEAD, spawnAsync, VERIFY_CAP_TIMEOUT_MS, VERIFY_SCRIPT, verifyCapReader, verifyReader } from "./verify-cap.mjs";

const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
const REPO = "melodic-software/claude-code-plugins";
const CAPPED = `fails at 3 heads (${"1".repeat(40)}, ${"2".repeat(40)}, ${"3".repeat(40)}), the cap is 3`;

function reader(done) {
  const calls = [];
  const lines = [];
  const spawn = (command, args, options) => {
    calls.push({ command, args, timeout: options.timeout, env: options.env });
    return done;
  };
  const read = verifyCapReader({ GITHUB_REPOSITORY: REPO }, { spawn, log: (line) => lines.push(line) });
  return { read, calls, lines };
}

const answer = (report) => ({ status: 0, stdout: `noise\n${JSON.stringify({ head: HEAD, detail: null, ...report })}\n`, stderr: "" });

test("a pull request the reader refuses verify:repeated-fail at the head is capped, with the FAILed heads", async () => {
  const { read, calls } = reader(answer({ refusal: "verify:repeated-fail", detail: CAPPED }));
  assert.equal(await read({ number: 42, head: HEAD, base: BASE }), `verify:repeated-fail: ${CAPPED}`);
  assert.deepEqual(
    calls.map(({ command, args }) => [command, args]),
    [["python3", [VERIFY_SCRIPT, "evidence", "--repo", REPO, "--base-sha", BASE, "42", HEAD]]],
  );
  assert.ok(calls[0].timeout > 0);
});

test("an allow is not the cap, and says nothing", async () => {
  const { read, lines } = reader(answer({ refusal: null }));
  assert.equal(await read({ number: 42, head: HEAD, base: BASE }), null);
  assert.deepEqual(lines, []);
});

test("any other refusal is not the cap: the round runs, with a warning naming the reader's detail", async () => {
  for (const [refusal, detail] of [
    ["verify:fail", `a FAIL at ${HEAD}`],
    ["verify:earlier-fail", "an earlier head FAILed"],
    ["verify:too-old", "opened 81 days ago"],
    ["verify:unreadable", "run of pr-verify-42-x-fail: gh: Bad credentials (HTTP 401)"],
  ]) {
    const { read, lines } = reader(answer({ refusal, detail }));
    assert.equal(await read({ number: 42, head: HEAD, base: BASE }), null, refusal);
    assert.equal(lines.length, 1, refusal);
    assert.match(lines[0], /^::warning::#42: /, refusal);
    assert.ok(lines[0].includes(refusal) && lines[0].includes(detail), lines[0]);
  }
});

// Gap: an address-feedback round is sent for the FAIL at its head, so every
// such round warned that the reader refused verify:fail.
test("a refusal the round expects warns nothing; any other still warns, and the cap still caps", async () => {
  const quiet = reader(answer({ refusal: "verify:fail", detail: `a FAIL at ${HEAD}` }));
  assert.equal(await quiet.read({ number: 42, head: HEAD, base: BASE, expected: ["verify:fail"] }), null);
  assert.deepEqual(quiet.lines, []);
  const other = reader(answer({ refusal: "verify:earlier-fail", detail: "an earlier head FAILed" }));
  assert.equal(await other.read({ number: 42, head: HEAD, base: BASE, expected: ["verify:fail"] }), null);
  assert.equal(other.lines.length, 1);
  assert.match(other.lines[0], /^::warning::#42: .*verify:earlier-fail/);
  const capped = reader(answer({ refusal: "verify:repeated-fail", detail: CAPPED }));
  assert.equal(await capped.read({ number: 42, head: HEAD, base: BASE, expected: ["verify:fail"] }), `verify:repeated-fail: ${CAPPED}`);
});

// Gap: the reader's stderr, where its listing misses go
// (babysit_verify_evidence.py `Reader._incremental`), was dropped, so a
// round skipped for a listing that outran the limit showed no cause.
test("the reader's stderr is logged on one line, its listing misses first", async () => {
  const miss = (stage, listed) =>
    `babysit-listing-miss {"base_age_seconds": 900, "fresh": 120, "kept": 10300, "listed": ${listed}, "pages": 2, "stage": "${stage}", "total_count": 10450}`;
  const stderr = [miss("incremental", 10420), miss("top-up", 10449), 'babysit-gh-calls {"total": 107}', ""].join("\n");
  const { read, lines } = reader({ ...answer({ refusal: null }), stderr });
  assert.equal(await read({ number: 42, head: HEAD, base: BASE }), null);
  assert.equal(lines.length, 1);
  assert.ok(lines[0].startsWith("#42: the verifier reader's stderr: 3 line(s), 2 babysit-listing-miss: "), lines[0]);
  assert.ok(lines[0].includes(miss("incremental", 10420)) && lines[0].includes(miss("top-up", 10449)), lines[0]);
  assert.ok(!lines[0].includes("babysit-gh-calls"), lines[0]);

  // With no miss, the last line; a timed-out read still logs what it wrote.
  const plain = reader({ ...answer({ refusal: null }), stderr: "first\nlast line\n" });
  await plain.read({ number: 42, head: HEAD, base: BASE });
  assert.deepEqual(plain.lines, ["#42: the verifier reader's stderr: 2 line(s), 0 babysit-listing-miss: last line"]);
  const killed = reader({ status: null, stdout: "", stderr: `${miss("incremental", 10420)}\n`, error: new Error("spawnSync python3 ETIMEDOUT") });
  assert.equal(await killed.read({ number: 42, head: HEAD, base: BASE }), null);
  assert.equal(killed.lines.length, 2);
  assert.ok(killed.lines[0].includes(miss("incremental", 10420)), killed.lines[0]);
  assert.match(killed.lines[1], /^::warning::#42: .*ETIMEDOUT/);
  const silent = reader({ status: null, stdout: "", stderr: null, error: new Error("spawnSync python3 ETIMEDOUT") });
  await silent.read({ number: 42, head: HEAD, base: BASE });
  assert.equal(silent.lines.length, 1);
});

test("a read that fails, does not parse or answers for another head runs the round as before, with a warning", async () => {
  for (const done of [
    { status: 1, stdout: "", stderr: "gh: rate limited" },
    { status: null, stdout: "", stderr: "", error: new Error("spawnSync python3 ETIMEDOUT") },
    { status: 0, stdout: "not json\n", stderr: "" },
    answer({ refusal: "verify:repeated-fail", head: "c".repeat(40) }),
  ]) {
    const { read, lines } = reader(done);
    assert.equal(await read({ number: 42, head: HEAD, base: BASE }), null);
    assert.match(lines.join("\n"), /^::warning::#42: /m);
  }
});

// feedback-dispatch.mjs resolves a same-head FAIL's notes on the reader's own
// `supersededAtHead` (Evidence.report), from a read at the head only: a
// missing field (an older reader), any other value, a failed read or an
// answer for another head is not superseded.
test("the reader's supersededAtHead reaches the caller only as true from a read at the head", async () => {
  const read = (done) => verifyReader({ GITHUB_REPOSITORY: REPO }, { spawn: () => done, log: () => {} })({ number: 42, head: HEAD, base: BASE });
  assert.deepEqual(await read(answer({ refusal: null, supersededAtHead: true })), { cap: null, supersededAtHead: true });
  assert.deepEqual(await read(answer({ refusal: "verify:spec-changed", supersededAtHead: true })), { cap: null, supersededAtHead: true });
  for (const done of [
    answer({ refusal: "verify:fail", supersededAtHead: false }),
    answer({ refusal: null }),
    answer({ refusal: null, supersededAtHead: "true" }),
    answer({ refusal: null, supersededAtHead: true, head: "c".repeat(40) }),
    { status: 1, stdout: "", stderr: "gh: rate limited" },
  ]) {
    assert.deepEqual(await read(done), { cap: null, supersededAtHead: false }, JSON.stringify(done));
  }
  assert.deepEqual(await read(answer({ refusal: "verify:repeated-fail", detail: CAPPED, supersededAtHead: false })), { cap: `verify:repeated-fail: ${CAPPED}`, supersededAtHead: false });
});

test("without a base commit the reader takes its own cap default", async () => {
  const { read, calls } = reader(answer({ refusal: "verify:repeated-fail" }));
  assert.equal(await read({ number: 42, head: HEAD, base: undefined }), "verify:repeated-fail");
  assert.deepEqual(calls[0].args, [VERIFY_SCRIPT, "evidence", "--repo", REPO, "42", HEAD]);
});

// Gap: a cap reached only through other pull requests' FAILs is hidden when
// one of their runs cannot be read. That read skips the round, failing
// closed, but never records the head as handled.
test("a sibling FAIL run the reader cannot read skips the round, for this run only", async () => {
  const { read } = reader(answer({ refusal: "verify:unreadable", detail: SIBLING_UNREADABLE }));
  const got = await read({ number: 42, head: HEAD, base: BASE });
  assert.equal(got, `verify:unreadable: ${SIBLING_UNREADABLE}`);
  assert.equal(final(got), false);
  assert.equal(final(`verify:repeated-fail: ${CAPPED}`), true);
  // Another unreadable answer (the pull request's own run) is not the cap.
  const own = reader(answer({ refusal: "verify:unreadable", detail: "run of pr-verify-42-x-fail" }));
  assert.equal(await own.read({ number: 42, head: HEAD, base: BASE }), null);
});

// Gap: a listing that does not fit in this caller's 120 s limit returned an
// exit-0 `verify:unreadable` the round ran past with no word. It hides the
// cap as a sibling read does, so it skips the round the same way.
test("a listing that does not fit in the caller's limit skips the round, for this run only, naming why", async () => {
  const detail = `${DEADLINE_UNREADABLE}: repository artifacts: 10450 artifacts in 105 pages need 112 s`;
  const { read, lines } = reader(answer({ refusal: "verify:unreadable", detail }));
  const got = await read({ number: 42, head: HEAD, base: BASE });
  assert.equal(got, `verify:unreadable: ${detail}`);
  assert.equal(final(got), false);
  assert.deepEqual(lines, []);
});

// The dispatchers read one pull request after another: each read after a
// caller-limit answer must not repeat the 15 s and 30 s waits.
test("after a caller-limit answer the same reader's later reads skip the waits; before one, and in a new reader, they wait", async () => {
  const NO_WAITS = Object.keys(NO_INCREMENTAL_WAITS)[0];
  const refused = answer({ refusal: "verify:unreadable", detail: `${DEADLINE_UNREADABLE}: repository artifacts` });
  const allowed = answer({ refusal: null });
  const replies = [allowed, refused, refused, allowed];
  const waits = [];
  const spawn = (command, args, options) => {
    waits.push(options.env[NO_WAITS]);
    return replies.shift();
  };
  const read = verifyCapReader({ GITHUB_REPOSITORY: REPO }, { spawn, log: () => {} });
  for (const number of [41, 42, 43, 44]) {
    await read({ number, head: HEAD, base: BASE });
  }
  assert.deepEqual(waits, [undefined, undefined, "1", "1"]);
  const { read: fresh, calls: freshCalls } = reader(allowed);
  await fresh({ number: 45, head: HEAD, base: BASE });
  assert.equal(freshCalls[0].env[NO_WAITS], undefined);
});

test("a refusal other than the caller limit keeps the waits for later reads", async () => {
  const NO_WAITS = Object.keys(NO_INCREMENTAL_WAITS)[0];
  const { read, calls } = reader(answer({ refusal: "verify:unreadable", detail: SIBLING_UNREADABLE }));
  await read({ number: 42, head: HEAD, base: BASE });
  await read({ number: 43, head: HEAD, base: BASE });
  assert.equal(calls[1].env[NO_WAITS], undefined);
});

// Both dispatchers' FAIL-cap reads take the listing pr-merge carried
// (listing-carry.mjs) as the first read's base, and share one saved listing
// across every pull request of the job, as pr-merge.yml's gate does; without
// them each read lists every artifact of the repository. The carry costs
// listing-carry.mjs's calls (5 or 6 a run, its api-calls notices on
// 2026-10-30), so it is fetched on the job's first FAIL-cap read, not by a
// step every run pays for.
const READER = readFileSync(new URL("../../../plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py", import.meta.url), "utf8");
const readerEnv = (name) => {
  const match = new RegExp(`^${name} = "([A-Z_]+)"$`, "m").exec(READER);
  assert.ok(match, name);
  return match[1];
};
const dispatchSteps = (workflow) => {
  const text = readFileSync(new URL(`../../workflows/${workflow}`, import.meta.url), "utf8");
  const job = /\n {2}dispatch:\n([\s\S]*?)(?=\n {2}[a-z-]+:\n|$)/.exec(text);
  assert.ok(job, `${workflow} dispatch job`);
  return job[1]
    .split(/\n(?= {6}- name: )/)
    .slice(1)
    .map((block) => ({ name: /^ {6}- name: (.*)$/m.exec(block)[1], block }));
};
const stepEnv = (block) => {
  const env = {};
  const body = /\n {8}env:\n((?: {10}.*\n?)*)/.exec(block)?.[1] ?? "";
  for (const line of body.split("\n")) {
    const kv = /^ {10}([A-Z_][A-Z0-9_]*): (.*)$/.exec(line);
    if (kv) env[kv[1]] = kv[2].replaceAll("${{ runner.temp }}", "/runner/temp");
  }
  return env;
};

for (const [workflow, dispatchName] of [
  ["pr-feedback-dispatch.yml", "Dispatch address-feedback"],
  ["pr-unblock-dispatch.yml", "Dispatch pr-unblock for conflicting, review-tier Dependabot, failing lanes App and Markdown-changing PRs"],
]) {
  test(`${workflow}: the carried listing is fetched on the first FAIL-cap read only, and every read shares one saved listing`, async () => {
    const steps = dispatchSteps(workflow);
    assert.deepEqual(
      steps.filter((s) => s.block.includes("run: node .base/.github/scripts/pr-merge/listing-carry.mjs")).map((s) => s.name),
      [],
      "no step fetches the carry before the dispatch knows it reads a FAIL cap",
    );
    const dispatch = steps.find((s) => s.name === dispatchName);
    assert.ok(dispatch, dispatchName);

    const LISTING = readerEnv("LISTING_ENV");
    const CARRY = readerEnv("LISTING_CARRY_ENV");
    const env = stepEnv(dispatch.block);
    assert.ok(env.VERIFY_EVIDENCE_SCRIPT, "the dispatch builds its FAIL-cap reader");
    assert.equal(env.GITHUB_TOKEN, "${{ github.token }}", "the carry is fetched with the job's token");
    const order = [];
    const read = verifyCapReader(env, {
      spawn: (command, args, options) => {
        order.push(["read", options.env]);
        return answer({ refusal: null });
      },
      carry: (carryEnv) => order.push(["carry", carryEnv]),
      log: () => {},
    });
    assert.deepEqual(order, [], "building the reader fetches nothing");
    await read({ number: 1, head: HEAD, base: BASE });
    await read({ number: 2, head: HEAD, base: BASE });
    assert.deepEqual(
      order.map(([kind]) => kind),
      ["carry", "read", "read"],
    );
    assert.equal(order[0][1][CARRY], "/runner/temp/verify-listing-carry.json");
    for (const [, spawned] of order.slice(1)) {
      assert.equal(spawned[CARRY], "/runner/temp/verify-listing-carry.json", "the reader takes the file listing-carry.mjs wrote");
      assert.equal(spawned[LISTING], "/runner/temp/verify-listing.json", "one saved listing for the job's pull requests");
    }
  });

  test(`${workflow}: every FAIL-cap read takes the run cache and head-ref map pr-merge carried`, async () => {
    const env = stepEnv(dispatchSteps(workflow).find((s) => s.name === dispatchName).block);
    const CACHE = "BABYSIT_RUN_CACHE";
    const REFS = readerEnv("HEAD_REFS_ENV");
    const spawned = [];
    const read = verifyCapReader(env, { spawn: (command, args, options) => (spawned.push(options.env), answer({ refusal: null })), carry: () => {}, log: () => {} });
    await read({ number: 1, head: HEAD, base: BASE });
    await read({ number: 2, head: HEAD, base: BASE });
    for (const readEnv of spawned) {
      assert.equal(readEnv[CACHE], "/runner/temp/babysit-run-cache.json", "the reader skips a FAIL's run and compare reads");
      assert.equal(readEnv[REFS], "/runner/temp/head-refs-in.json", "the reader skips an untied FAIL's download");
    }
    assert.deepEqual(
      carrySteps({ ...env, RUNNER_TEMP: "/runner/temp" }).map(({ script, args }) => [script, ...args]),
      [["listing-carry.mjs"], ["carry-run-cache.mjs", "read"], ["carry-run-cache.mjs"], ["head-ref-map.mjs", "read"]],
    );
  });
}

test("the carry starts the reader's run cache from pr-merge's file, shares its GET answers, and leaves the dispatch step's outputs alone", async () => {
  const dir = tempDir("verify-cap-");
  const cache = join(dir, "babysit-run-cache.json");
  const output = join(dir, "output");
  writeFileSync(output, "");
  const key = `${REPO}|${"a".repeat(40)}...main`;
  const env = { RUNNER_TEMP: dir, BABYSIT_RUN_CACHE: cache, BABYSIT_VERIFY_HEAD_REFS: join(dir, "head-refs-in.json") };
  const steps = carrySteps(env);
  const reads = steps.filter((step) => step.args[0] === "read" || step.script === "listing-carry.mjs");
  assert.equal(new Set(reads.map((step) => step.env.PR_MERGE_READS_PATH)).size, 1);
  assert.deepEqual(reads.map((step) => step.env.API_BUDGET_SCRIPT), ["listing-carry", "carry-run-cache", "head-ref-map"]);

  const start = steps.find((step) => step.script === "carry-run-cache.mjs" && step.args.length === 0);
  writeFileSync(start.env.CARRY_FROM, JSON.stringify({ "carried-on-branch": { [key]: { at: new Date().toISOString(), value: true } } }));
  const script = fileURLToPath(new URL(`../pr-merge/${start.script}`, import.meta.url));
  const done = await spawnAsync(process.execPath, [script], { env: { PATH: process.env.PATH, GITHUB_REPOSITORY: REPO, GITHUB_OUTPUT: output, ...start.env }, timeout: 30_000 });
  assert.equal(done.status, 0, done.stderr);
  assert.equal(JSON.parse(readFileSync(cache, "utf8"))["carried-on-branch"][key].value, true);
  assert.equal(readFileSync(output, "utf8"), "");
});

test("a job that names only the listing fetches only the listing", () => {
  assert.deepEqual(carrySteps({ RUNNER_TEMP: "/t" }).map((step) => step.script), ["listing-carry.mjs"]);
});

test("a carry that fails is fetched once, warns, and the reads go on without it", async () => {
  let fetched = 0;
  const lines = [];
  const reads = [];
  const read = verifyCapReader(
    { GITHUB_REPOSITORY: REPO, BABYSIT_VERIFY_LISTING_CARRY: "/runner/temp/verify-listing-carry.json" },
    {
      spawn: (command, args) => {
        reads.push(args.at(-2));
        return answer({ refusal: "verify:repeated-fail", detail: CAPPED });
      },
      carry: () => {
        fetched += 1;
        throw new Error("HTTP 502");
      },
      log: (line) => lines.push(line),
    },
  );
  assert.equal(await read({ number: 42, head: HEAD, base: BASE }), `verify:repeated-fail: ${CAPPED}`);
  assert.equal(await read({ number: 43, head: HEAD, base: BASE }), `verify:repeated-fail: ${CAPPED}`);
  assert.equal(fetched, 1);
  assert.deepEqual(reads, ["42", "43"]);
  assert.equal(lines.length, 1);
  assert.match(lines[0], /^::warning::pr-merge's carried reads were not all fetched \(HTTP 502\)/);
});

// The default carry runs listing-carry.mjs as a bounded child, as the step
// did: here it removes a stale file at the path and stops at the repository
// name, with no request.
test("the default carry runs listing-carry.mjs with the job's environment, then the read goes on", async () => {
  const dir = tempDir("verify-cap-");
  const path = join(dir, "verify-listing-carry.json");
  writeFileSync(path, "stale");
  const reads = [];
  const read = verifyCapReader(
    { PATH: process.env.PATH, GITHUB_REPOSITORY: "not a repository", RUNNER_TEMP: dir, BABYSIT_VERIFY_LISTING_CARRY: path },
    { spawn: (command, args) => (reads.push(args.at(-2)), answer({ refusal: null })), log: () => {} },
  );
  assert.equal(await read({ number: 42, head: HEAD, base: BASE }), null);
  assert.equal(existsSync(path), false, "listing-carry.mjs removed the stale file before reading");
  assert.deepEqual(reads, ["42"]);
});

test("with no carry file named, no carry is fetched", async () => {
  let fetched = 0;
  const read = verifyCapReader({ GITHUB_REPOSITORY: REPO }, { spawn: () => answer({ refusal: null }), carry: () => (fetched += 1), log: () => {} });
  assert.equal(await read({ number: 42, head: HEAD, base: BASE }), null);
  assert.equal(fetched, 0);
});

test("the sibling and caller-limit details, the FAIL refusal, the listing-miss prefix, the no-wait switch and the superseded field are the reader's", async () => {
  const source = readFileSync(new URL("../../../plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py", import.meta.url), "utf8");
  assert.ok(source.includes(`SIBLING_UNREADABLE = "${SIBLING_UNREADABLE}"`));
  assert.ok(source.includes(`DEADLINE_UNREADABLE = "${DEADLINE_UNREADABLE}"`));
  assert.ok(source.includes(`FAIL = "${FAIL}"`));
  assert.ok(source.includes(`LISTING_MISS_PREFIX = "${LISTING_MISS_PREFIX}"`));
  assert.ok(source.includes(`NO_INCREMENTAL_WAITS_ENV = "${Object.keys(NO_INCREMENTAL_WAITS)[0]}"`));
  assert.ok(source.includes(`"${SUPERSEDED_AT_HEAD}": self.superseded_at_head,`));
});

// babysit_verify_evidence.py DEADLINE_ENV and CALLER_ENV: the reader sizes its
// listing to the limit this caller kills it at, and names the caller when a
// listing cannot fit, rather than being killed with no reason.
test("the reader is told the limit it is killed at, and who kills it", async () => {
  const { read, calls } = reader(answer({ refusal: null }));
  await read({ number: 42, head: HEAD, base: BASE });
  assert.equal(calls[0].timeout, 120_000);
  assert.equal(VERIFY_CAP_TIMEOUT_MS, 120_000);
  assert.equal(calls[0].env.BABYSIT_VERIFY_DEADLINE_SECONDS, "120");
  assert.equal(calls[0].env.BABYSIT_VERIFY_CALLER, "verify-cap.mjs");
  assert.equal(calls[0].env.GITHUB_REPOSITORY, REPO);
});

// Runs 41078771801, 41081672214, 41082104940 and 41085939386 (2026-10-30):
// after a 57-125 s read the dispatch POST failed at once with `fetch failed`.
// A server in another process resets a connection idle 200 ms; the reader
// runs past that, then the next request goes out. Under spawnSync the reset
// lay unread and the request went out on the dead socket (ECONNRESET).
test("a request after the reader's read goes out on a live connection, not on one reset while it ran", async () => {
  const server = spawnChild(
    process.execPath,
    [
      "-e",
      `const s = require("node:net").createServer((c) => {
        let idle;
        const arm = () => { clearTimeout(idle); idle = setTimeout(() => c.resetAndDestroy(), 200); };
        arm();
        c.on("data", () => { arm(); c.write("HTTP/1.1 200 OK\\r\\ncontent-type: application/json\\r\\ncontent-length: 2\\r\\n\\r\\n{}"); });
        c.on("error", () => {});
      });
      s.listen(0, "127.0.0.1", () => console.log(s.address().port));`,
    ],
    { stdio: ["ignore", "pipe", "inherit"] },
  );
  try {
    const port = await new Promise((resolve) => server.stdout.once("data", (chunk) => resolve(String(chunk).trim())));
    const url = `http://127.0.0.1:${port}/`;
    await (await fetch(url)).json();
    // Let the first response's socket go back to the pool.
    await new Promise((resolve) => setTimeout(resolve, 100));
    const script = join(tempDir("verify-cap-"), "reader.py");
    writeFileSync(script, `import json, sys, time\ntime.sleep(0.8)\nprint(json.dumps({"head": sys.argv[-1], "refusal": None, "detail": None}))\n`);
    const read = verifyCapReader({ GITHUB_REPOSITORY: REPO, VERIFY_EVIDENCE_SCRIPT: script, PATH: process.env.PATH }, { log: () => {} });
    assert.equal(await read({ number: 42, head: HEAD, base: BASE }), null);
    const response = await fetch(url, { method: "POST", body: "{}" });
    assert.equal(response.status, 200);
  } finally {
    server.kill();
  }
});

test("a reader child past its timeout is killed and answers spawnSync's ETIMEDOUT error", async () => {
  const started = Date.now();
  const done = await spawnAsync(process.execPath, ["-e", "setTimeout(() => {}, 10_000)"], { encoding: "utf8", timeout: 200 });
  assert.ok(Date.now() - started < 5_000);
  assert.equal(done.status, null);
  assert.equal(done.error?.code, "ETIMEDOUT");
  assert.match(done.error.message, /ETIMEDOUT/);
});

test("a reader child's exit status, stdout and stderr come back as spawnSync gives them", async () => {
  const done = await spawnAsync(process.execPath, ["-e", "console.log('out'); console.error('err'); process.exit(3)"], { encoding: "utf8", timeout: 5_000 });
  assert.deepEqual(done, { status: 3, stdout: "out\n", stderr: "err\n", error: undefined });
  const missing = await spawnAsync("no-such-reader-binary", [], { timeout: 5_000 });
  assert.equal(missing.status, null);
  assert.equal(missing.error?.code, "ENOENT");
});
