// The expected arguments come from babysit_verify_evidence.py's `evidence`
// command line (main: --repo, --base-sha, number, head) and its report line
// (Evidence.report: refusal, head, detail).
import assert from "node:assert/strict";
import { test } from "node:test";

import { readFileSync } from "node:fs";

import { DEADLINE_UNREADABLE, final, SIBLING_UNREADABLE, VERIFY_CAP_TIMEOUT_MS, VERIFY_SCRIPT, verifyCapReader } from "./verify-cap.mjs";

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

test("a pull request the reader refuses verify:repeated-fail at the head is capped, with the FAILed heads", () => {
  const { read, calls } = reader(answer({ refusal: "verify:repeated-fail", detail: CAPPED }));
  assert.equal(read({ number: 42, head: HEAD, base: BASE }), `verify:repeated-fail: ${CAPPED}`);
  assert.deepEqual(
    calls.map(({ command, args }) => [command, args]),
    [["python3", [VERIFY_SCRIPT, "evidence", "--repo", REPO, "--base-sha", BASE, "42", HEAD]]],
  );
  assert.ok(calls[0].timeout > 0);
});

test("an allow is not the cap, and says nothing", () => {
  const { read, lines } = reader(answer({ refusal: null }));
  assert.equal(read({ number: 42, head: HEAD, base: BASE }), null);
  assert.deepEqual(lines, []);
});

test("any other refusal is not the cap: the round runs, with a warning naming the reader's detail", () => {
  for (const [refusal, detail] of [
    ["verify:fail", `a FAIL at ${HEAD}`],
    ["verify:earlier-fail", "an earlier head FAILed"],
    ["verify:too-old", "opened 81 days ago"],
    ["verify:unreadable", "run of pr-verify-42-x-fail: gh: Bad credentials (HTTP 401)"],
  ]) {
    const { read, lines } = reader(answer({ refusal, detail }));
    assert.equal(read({ number: 42, head: HEAD, base: BASE }), null, refusal);
    assert.equal(lines.length, 1, refusal);
    assert.match(lines[0], /^::warning::#42: /, refusal);
    assert.ok(lines[0].includes(refusal) && lines[0].includes(detail), lines[0]);
  }
});

test("a read that fails, does not parse or answers for another head runs the round as before, with a warning", () => {
  for (const done of [
    { status: 1, stdout: "", stderr: "gh: rate limited" },
    { status: null, stdout: "", stderr: "", error: new Error("spawnSync python3 ETIMEDOUT") },
    { status: 0, stdout: "not json\n", stderr: "" },
    answer({ refusal: "verify:repeated-fail", head: "c".repeat(40) }),
  ]) {
    const { read, lines } = reader(done);
    assert.equal(read({ number: 42, head: HEAD, base: BASE }), null);
    assert.match(lines.join("\n"), /^::warning::#42: /m);
  }
});

test("without a base commit the reader takes its own cap default", () => {
  const { read, calls } = reader(answer({ refusal: "verify:repeated-fail" }));
  assert.equal(read({ number: 42, head: HEAD, base: undefined }), "verify:repeated-fail");
  assert.deepEqual(calls[0].args, [VERIFY_SCRIPT, "evidence", "--repo", REPO, "42", HEAD]);
});

// Gap: a cap reached only through other pull requests' FAILs is hidden when
// one of their runs cannot be read. That read skips the round, failing
// closed, but never records the head as handled.
test("a sibling FAIL run the reader cannot read skips the round, for this run only", () => {
  const { read } = reader(answer({ refusal: "verify:unreadable", detail: SIBLING_UNREADABLE }));
  const got = read({ number: 42, head: HEAD, base: BASE });
  assert.equal(got, `verify:unreadable: ${SIBLING_UNREADABLE}`);
  assert.equal(final(got), false);
  assert.equal(final(`verify:repeated-fail: ${CAPPED}`), true);
  // Another unreadable answer (the pull request's own run) is not the cap.
  const own = reader(answer({ refusal: "verify:unreadable", detail: "run of pr-verify-42-x-fail" }));
  assert.equal(own.read({ number: 42, head: HEAD, base: BASE }), null);
});

// Gap: a listing that does not fit in this caller's 120 s limit returned an
// exit-0 `verify:unreadable` the round ran past with no word. It hides the
// cap as a sibling read does, so it skips the round the same way.
test("a listing that does not fit in the caller's limit skips the round, for this run only, naming why", () => {
  const detail = `${DEADLINE_UNREADABLE}: repository artifacts: 10450 artifacts in 105 pages need 112 s`;
  const { read, lines } = reader(answer({ refusal: "verify:unreadable", detail }));
  const got = read({ number: 42, head: HEAD, base: BASE });
  assert.equal(got, `verify:unreadable: ${detail}`);
  assert.equal(final(got), false);
  assert.deepEqual(lines, []);
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
  test(`${workflow}: every FAIL-cap read starts from pr-merge's carried listing and shares one saved listing`, () => {
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
    read({ number: 1, head: HEAD, base: BASE });
    read({ number: 2, head: HEAD, base: BASE });
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

test("the sibling and caller-limit details are the reader's SIBLING_UNREADABLE and DEADLINE_UNREADABLE", () => {
  const source = readFileSync(new URL("../../../plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py", import.meta.url), "utf8");
  assert.ok(source.includes(`SIBLING_UNREADABLE = "${SIBLING_UNREADABLE}"`));
  assert.ok(source.includes(`DEADLINE_UNREADABLE = "${DEADLINE_UNREADABLE}"`));
});

// babysit_verify_evidence.py DEADLINE_ENV and CALLER_ENV: the reader sizes its
// listing to the limit this caller kills it at, and names the caller when a
// listing cannot fit, rather than being killed with no reason.
test("the reader is told the limit it is killed at, and who kills it", () => {
  const { read, calls } = reader(answer({ refusal: null }));
  read({ number: 42, head: HEAD, base: BASE });
  assert.equal(calls[0].timeout, 120_000);
  assert.equal(VERIFY_CAP_TIMEOUT_MS, 120_000);
  assert.equal(calls[0].env.BABYSIT_VERIFY_DEADLINE_SECONDS, "120");
  assert.equal(calls[0].env.BABYSIT_VERIFY_CALLER, "verify-cap.mjs");
  assert.equal(calls[0].env.GITHUB_REPOSITORY, REPO);
});
