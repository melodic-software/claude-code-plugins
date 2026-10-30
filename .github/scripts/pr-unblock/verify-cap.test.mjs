// The expected arguments come from babysit_verify_evidence.py's `evidence`
// command line (main: --repo, --base-sha, number, head) and its report line
// (Evidence.report: refusal, head, detail).
import assert from "node:assert/strict";
import { test } from "node:test";

import { spawn as spawnChild } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { final, SIBLING_UNREADABLE, spawnAsync, VERIFY_SCRIPT, verifyCapReader } from "./verify-cap.mjs";

const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
const REPO = "melodic-software/claude-code-plugins";
const CAPPED = `fails at 3 heads (${"1".repeat(40)}, ${"2".repeat(40)}, ${"3".repeat(40)}), the cap is 3`;

function reader(done) {
  const calls = [];
  const lines = [];
  const spawn = (command, args, options) => {
    calls.push({ command, args, timeout: options.timeout });
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

test("any other answer, an allow included, is not the cap", async () => {
  for (const refusal of [null, "verify:fail", "verify:earlier-fail", "verify:too-old", "verify:unreadable"]) {
    const { read } = reader(answer({ refusal }));
    assert.equal(await read({ number: 42, head: HEAD, base: BASE }), null, String(refusal));
  }
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

// Both dispatchers' FAIL-cap reads take the listing pr-merge carried
// (listing-carry.mjs) as the first read's base, and share one saved listing
// across every pull request of the job, as pr-merge.yml's gate does; without
// them each read lists every artifact of the repository.
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
  test(`${workflow}: every FAIL-cap read starts from pr-merge's carried listing and shares one saved listing`, async () => {
    const steps = dispatchSteps(workflow);
    const names = steps.map((s) => s.name);
    const carry = steps.find((s) => s.block.includes("node .base/.github/scripts/pr-merge/listing-carry.mjs"));
    assert.ok(carry, "a step restores pr-merge's listing through listing-carry.mjs");
    const dispatch = steps.find((s) => s.name === dispatchName);
    assert.ok(dispatch, dispatchName);
    assert.ok(names.indexOf(carry.name) < names.indexOf(dispatch.name), "the carry is restored before the dispatch reads");
    assert.match(carry.block, /\n {8}continue-on-error: true\n/, "a failed restore never stops the dispatch");
    const carryEnv = stepEnv(carry.block);
    assert.equal(carryEnv.ACTIONS_TOKEN, "${{ github.token }}");

    const LISTING = readerEnv("LISTING_ENV");
    const CARRY = readerEnv("LISTING_CARRY_ENV");
    const env = stepEnv(dispatch.block);
    assert.ok(env.VERIFY_EVIDENCE_SCRIPT, "the dispatch builds its FAIL-cap reader");
    // The reader the dispatch builds hands both files to every spawn.
    const seen = [];
    const read = verifyCapReader(env, {
      spawn: (command, args, options) => {
        seen.push(options.env);
        return answer({ refusal: null });
      },
      log: () => {},
    });
    await read({ number: 1, head: HEAD, base: BASE });
    await read({ number: 2, head: HEAD, base: BASE });
    assert.equal(seen.length, 2);
    const NO_WAITS = readerEnv("NO_INCREMENTAL_WAITS_ENV");
    for (const spawned of seen) {
      // A carried listing's waits and a whole listing outlast VERIFY_CAP_TIMEOUT_MS.
      assert.equal(spawned[NO_WAITS], "1", "a miss on the carried listing lists every page at once");
      assert.equal(spawned[CARRY], carryEnv.BABYSIT_VERIFY_LISTING_CARRY, "the reader takes the file listing-carry.mjs wrote");
      assert.equal(spawned[LISTING], "/runner/temp/verify-listing.json", "one saved listing for the job's pull requests");
      assert.notEqual(spawned[LISTING], spawned[CARRY]);
    }
  });
}

test("the sibling detail is the reader's SIBLING_UNREADABLE", async () => {
  const source = readFileSync(new URL("../../../plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py", import.meta.url), "utf8");
  assert.ok(source.includes(`SIBLING_UNREADABLE = "${SIBLING_UNREADABLE}"`));
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
