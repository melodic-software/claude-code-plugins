// handoff-evidence.sh's job-listing reads, on a stub gh that gives each call
// the next answer in turn: a read after the first sends each page it already
// got with that page's ETag, a 304 gives back that page's stored body, each
// page keeps its own ETag, and a page with no ETag or a failed one is read
// again unconditionally. Then the waits between reads, and what a read that
// never settles ends in.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";

const SCRIPT = fileURLToPath(new URL("./handoff-evidence.sh", import.meta.url));
const FIRST = "repos/o/r/actions/runs/7/jobs?filter=latest&per_page=100";
const SECOND = "https://api.github.com/repositories/9/actions/runs/7/jobs?filter=latest&per_page=100&page=2";

// gh api -i output: the status line, the headers, a blank line, then the body.
const answer = (status, headers = {}, body) =>
  [`HTTP/2.0 ${status}`, ...Object.entries(headers).map(([name, value]) => `${name}: ${value}`), "", body === undefined ? "" : JSON.stringify(body)].join("\r\n");
const listing = (...jobs) => ({ total_count: jobs.length, jobs });

const BROKER = { name: "fix-docs / broker-check", conclusion: "success", steps: [] };
// A report job the listing shows before its steps, then with them.
const UNLISTED = { name: "fix-docs / report", conclusion: "success", steps: [] };
const POSTED = { name: "fix-docs / report", conclusion: "success", steps: [{ name: "Post the check run", conclusion: "success" }] };

// Runs `handoff-evidence.sh` with no waits, `posted` unless facts says; each
// answer is [gh -i output, gh exit status]. A call past the last answer gets
// nothing and exits 1. With `draw` set, shuf answers min(draw, the range's top)
// and records the range, and sleep only records its argument; delays null leaves
// the default.
function run(answers, delays = "0 0 0", { calls = "fix-docs", draw, runnerTemp, env = {}, facts = ["posted"], marker = false } = {}) {
  const dir = tempDir("handoff-evidence-");
  try {
    const bin = join(dir, "bin");
    mkdirSync(bin);
    answers.forEach(([text, code], index) => {
      writeFileSync(join(dir, `answer-${index + 1}`), text);
      writeFileSync(join(dir, `status-${index + 1}`), String(code));
    });
    writeFileSync(
      join(bin, "gh"),
      "#!/usr/bin/env bash\n" +
        `n=$(($(cat "${dir}/calls" 2>/dev/null || echo 0) + 1))\necho "$n" >"${dir}/calls"\n` +
        `printf '%s\\n' "$*" >>"${dir}/args"\ncat "${dir}/answer-$n" 2>/dev/null\n` +
        `exit "$(cat "${dir}/status-$n" 2>/dev/null || echo 1)"\n`,
    );
    chmodSync(join(bin, "gh"), 0o755);
    if (draw !== undefined) {
      writeFileSync(
        join(bin, "shuf"),
        `#!/usr/bin/env bash\nprintf '%s\\n' "$2" >>"${dir}/ranges"\ntop=\${2#*-}\necho "$((top < ${draw} ? top : ${draw}))"\n`,
      );
      writeFileSync(join(bin, "sleep"), `#!/usr/bin/env bash\nprintf '%s\\n' "$1" >>"${dir}/sleeps"\n`);
      chmodSync(join(bin, "shuf"), 0o755);
      chmodSync(join(bin, "sleep"), 0o755);
    }
    const output = join(dir, "output");
    writeFileSync(output, "");
    const result = spawnSync("bash", [SCRIPT, ...facts], {
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        RUNNER_TEMP: runnerTemp === true ? dir : "",
        GH_TOKEN: "t",
        GITHUB_REPOSITORY: "o/r",
        GITHUB_RUN_ID: "7",
        GITHUB_OUTPUT: output,
        CALLS: calls,
        ...(delays === null ? { HANDOFF_EVIDENCE_DELAYS: undefined } : { HANDOFF_EVIDENCE_DELAYS: delays }),
        ...(marker ? { LANE_HOLD_MARKER: join(dir, "lane-hold", "pr-refine") } : {}),
        ...env,
      },
    });
    const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
    const lines = (name) => read(name).split("\n").filter(Boolean);
    return { status: result.status, stdout: result.stdout, stderr: result.stderr, output: read("output"), args: lines("args"), ranges: lines("ranges"), sleeps: lines("sleeps").map(Number), marker: read("lane-hold/pr-refine") };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("a repeated read sends the page's ETag, and a 304 gives back the body that ETag came with", () => {
  const out = run([
    [answer("200 OK", { Etag: '"e1"' }, listing(UNLISTED)), 0],
    [answer("304 Not Modified", { Etag: '"e1"' }), 1],
    [answer("200 OK", { Etag: '"e2"' }, listing(POSTED)), 0],
  ]);
  assert.equal(out.status, 0, out.stdout + out.stderr);
  assert.deepEqual(out.args, [`api -i ${FIRST}`, `api -i ${FIRST} -H If-None-Match: "e1"`, `api -i ${FIRST} -H If-None-Match: "e1"`]);
  assert.match(out.stdout, /^Read 1: missing: fix-docs \/ report has no steps listed; reading again in 0s$/m);
  assert.match(out.stdout, /^Read 2: missing: fix-docs \/ report has no steps listed; reading again in 0s$/m, "the 304 kept the stored body");
  assert.match(out.stdout, /^handoff evidence: posted=true \(3 reads\)$/m);
  assert.equal(out.output, "posted=true\n");
});

// The 304 for page 1 carries no Link header: the next page is the one its 200 named.
test("each page of the listing is read through its Link and keeps its own ETag", () => {
  const next = `<${SECOND}>; rel="next", <${SECOND}>; rel="last"`;
  const prev = `<https://api.github.com/repositories/9/actions/runs/7/jobs?filter=latest&per_page=100&page=1>; rel="prev"`;
  const out = run([
    [answer("200 OK", { Etag: '"p1"', Link: next }, listing(BROKER)), 0],
    [answer("200 OK", { Etag: '"p2"', Link: prev }, listing(UNLISTED)), 0],
    [answer("304 Not Modified", { Etag: '"p1"' }), 1],
    [answer("200 OK", { Etag: '"p3"', Link: prev }, listing(POSTED)), 0],
  ]);
  assert.equal(out.status, 0, out.stdout + out.stderr);
  assert.deepEqual(out.args, [`api -i ${FIRST}`, `api -i ${SECOND}`, `api -i ${FIRST} -H If-None-Match: "p1"`, `api -i ${SECOND} -H If-None-Match: "p2"`]);
  assert.equal(out.output, "posted=true\n");
});

test("a page that came with no ETag is read again unconditionally, and one answered other than 200 or 304 is a failed read", () => {
  const out = run([
    [answer("200 OK", {}, listing(UNLISTED)), 0],
    [answer("502 Bad Gateway", {}, { message: "Server Error" }), 1],
    [answer("200 OK", { Etag: '"e1"' }, listing(POSTED)), 0],
  ]);
  assert.equal(out.status, 0, out.stdout + out.stderr);
  assert.deepEqual(out.args, [`api -i ${FIRST}`, `api -i ${FIRST}`, `api -i ${FIRST}`]);
  assert.match(out.stdout, /^Read 2: the jobs read failed; reading again in 0s$/m);
  assert.equal(out.output, "posted=true\n");
});

// gh prints a 200's headers before its body, so a stream cut off after them
// leaves a 200 status line, no body and gh's exit 1.
test("a 200 whose body was cut off or is empty is a failed read, not a listing of no jobs, and its ETag is not kept", () => {
  const out = run([
    [answer("200 OK", { Etag: '"e1"' }), 1],
    [answer("200 OK", { Etag: '"e2"' }), 0],
    [answer("200 OK", { Etag: '"e3"' }, listing(POSTED)), 0],
  ]);
  assert.equal(out.status, 0, out.stdout + out.stderr);
  assert.deepEqual(out.args, [`api -i ${FIRST}`, `api -i ${FIRST}`, `api -i ${FIRST}`]);
  assert.match(out.stdout, /^Read 1: the jobs read failed; reading again in 0s$/m);
  assert.match(out.stdout, /^Read 2: the jobs read failed; reading again in 0s$/m);
  assert.equal(out.output, "posted=true\n");
});

test("a listing still unread after the last delay fails with no output, outside pr-refine's fix-docs calls", () => {
  const failed = answer("502 Bad Gateway", {}, { message: "Server Error" });
  const out = run([[failed, 1], [failed, 1]], "0", { calls: "fix-ci" });
  assert.equal(out.status, 1);
  assert.equal(out.args.length, 2);
  assert.match(out.stdout, /^::error::handoff evidence for fix-ci still missing after 2 reads: the jobs read failed$/m);
  assert.equal(out.output, "");
});

// Outage posture element 1: each wait is drawn from 0 to a cap, never the cap
// itself. The caps are the script's documented 15 30 60 90 120 s, 315 s in all,
// the window a listing measured lagging for five minutes needs. Worked by hand:
// a draw of 40 waits 15+30+40+40+40 = 165 s over the list, then 40 s four more
// times to reach 325 s; a draw of 0 reaches no window, so the read ceiling ends it.
const UNSETTLED = Array.from({ length: 20 }, () => [answer("200 OK", {}, listing(UNLISTED)), 0]);

test("each wait is a random draw from 0 to its cap, and reads go on at the last cap until the waits fill the window", () => {
  const top = run(UNSETTLED, null, { draw: 1000 });
  assert.deepEqual(top.ranges, ["0-15", "0-30", "0-60", "0-90", "0-120"]);
  assert.deepEqual(top.sleeps, [15, 30, 60, 90, 120], "the draw is what is slept");
  assert.equal(top.args.length, 6, "the caps' sum is reached: one read and five more");
  const mid = run(UNSETTLED, null, { draw: 40 });
  assert.deepEqual(mid.sleeps, [15, 30, 40, 40, 40, 40, 40, 40, 40]);
  assert.deepEqual(mid.ranges.slice(5), ["0-120", "0-120", "0-120", "0-120"]);
  assert.equal(mid.args.length, 10);
});

test("draws that never fill the window stop at twelve reads", () => {
  const out = run(UNSETTLED, null, { draw: 0 });
  assert.equal(out.args.length, 12);
  assert.deepEqual(out.sleeps, Array(11).fill(0));
});

// Outage posture element 2: unknown holds green with a notice and no output,
// which pr-refine.yml reads as no fallback. Element 1: at most 3 attempts on a
// failed read. Only pr-refine's two calls that read it: every other caller goes
// on failing closed (the fallback token step behind a red read hands nothing on).
const BROKEN = [answer("502 Bad Gateway", {}, { message: "Server Error" }), 1];

test("pr-refine's fix-docs calls hold green with a notice after three failed reads, and write no output", () => {
  for (const calls of ["fix-docs", "fix-docs-subscription"]) {
    const out = run([BROKEN, BROKEN, BROKEN, BROKEN, BROKEN], "0 0 0 0 0", { calls });
    assert.equal(out.status, 0, calls);
    assert.equal(out.args.length, 3, calls);
    assert.match(out.stdout, new RegExp(`^::notice title=Handoff evidence hold::handoff evidence for ${calls} still missing after 3 reads: the jobs read failed; no fallback starts, and the next dispatcher tick sends the PR again$`, "m"));
    assert.doesNotMatch(out.stdout, /::error::/);
    assert.equal(out.output, "");
  }
});

test("a hold job's held read writes its lane-hold marker; a read that settles or fails closed writes none", () => {
  const held = run([BROKEN, BROKEN, BROKEN], "0 0 0", { marker: true });
  assert.equal(held.status, 0);
  assert.equal(held.marker, "pr-refine 7\n", "the marker names the lane and the run");
  const settled = run([[answer("200 OK", {}, listing(POSTED)), 0]], "0", { marker: true });
  assert.equal(settled.output, "posted=true\n");
  assert.equal(settled.marker, "", "a settled read holds nothing");
  const closed = run([BROKEN, BROKEN], "0", { calls: "fix-ci", marker: true });
  assert.equal(closed.status, 1);
  assert.equal(closed.marker, "", "a red read is no hold");
});

test("a listing that stays unsettled is no failed read: fix-docs reads on through every wait, and the opt-in ends it as the lag notice", () => {
  const out = run(UNSETTLED.slice(0, 6), "0 0 0 0 0", { env: { HANDOFF_EVIDENCE_LAG: "notice" } });
  assert.equal(out.status, 0);
  assert.equal(out.args.length, 6);
  assert.match(out.stdout, /^::notice::.*after 6 reads: missing: fix-docs \/ report has no steps listed; the outputs stay empty$/m);
  assert.equal(out.output, "");
});

// HANDOFF_EVIDENCE_LAG decides a last read that got the listing, the CALLS scope
// one that did not, and the failed-read count runs across the reads between.
test("a fix-docs call whose lag and failed reads mix ends on what its last read found", () => {
  const LAG = UNSETTLED[0];
  const env = { HANDOFF_EVIDENCE_LAG: "notice" };
  const lagLast = run([LAG, BROKEN, LAG], "0 0", { env });
  assert.equal(lagLast.status, 0);
  assert.match(lagLast.stdout, /^::notice::.*after 3 reads: missing: .*; the outputs stay empty$/m);
  assert.doesNotMatch(lagLast.stdout, /Handoff evidence hold/);
  const failLast = run([LAG, BROKEN, LAG, BROKEN], "0 0 0", { env });
  assert.equal(failLast.status, 0);
  assert.match(failLast.stdout, /^::notice title=Handoff evidence hold::.*after 4 reads: the jobs read failed;/m);
  const counted = run([BROKEN, LAG, BROKEN, LAG, BROKEN, LAG], "0 0 0 0 0 0", { env });
  assert.equal(counted.args.length, 5, "the third failed read ends it, with lag reads between");
  assert.match(counted.stdout, /^::notice title=Handoff evidence hold::.*after 5 reads: the jobs read failed;/m);
  for (const out of [lagLast, failLast, counted]) {
    assert.doesNotMatch(out.stdout, /::error::/);
    assert.equal(out.output, "");
  }
  const noOptIn = run([BROKEN, LAG], "0");
  assert.equal(noOptIn.status, 1, "a last read that got the listing needs the opt-in");
  assert.match(noOptIn.stdout, /^::error::.*after 2 reads: missing: /m);
  const settled = run([LAG, BROKEN, [answer("200 OK", {}, listing(POSTED)), 0]], "0 0", { env });
  assert.equal(settled.output, "posted=true\n");
});

test("every other caller still fails closed after six failed reads, a list of calls holding fix-docs included", () => {
  for (const calls of ["fix-ci", "resolve-issue", "fix-docs fix-ci", "fix-docs-rung-up"]) {
    const out = run(Array(8).fill(BROKEN), "0 0 0 0 0 0 0", { calls });
    assert.equal(out.status, 1, calls);
    assert.equal(out.args.length, 6, calls);
    assert.match(out.stdout, /^::error::handoff evidence for /m);
    assert.doesNotMatch(out.stdout, /::notice/);
  }
});

// A rate limit is refused the same way for every caller, so the budget stays
// protected; on a fix-docs call its annotation is a notice (API_BUDGET_HOLD).
test("a rate limit holds fix-docs under the gh wrapper: one request, a notice and no error; another call still gets the error", () => {
  const reset = Math.floor(Date.now() / 1000) + 900;
  const limited = [answer("403 Forbidden", { "X-Ratelimit-Limit": 1000, "X-Ratelimit-Remaining": 0, "X-Ratelimit-Reset": reset, "X-Ratelimit-Resource": "core" }, { message: "API rate limit exceeded for installation ID 1." }), 1];
  const held = run([limited], "0 0 0 0 0", { runnerTemp: true });
  assert.equal(held.status, 0, held.stdout + held.stderr);
  assert.equal(held.args.length, 1, "the stop refuses every later read");
  assert.match(held.stderr, /^::notice::.*hit GitHub's core API rate limit/m);
  assert.doesNotMatch(held.stdout + held.stderr, /::error::/);
  const other = run([limited], "0 0 0 0 0", { calls: "fix-ci", runnerTemp: true });
  assert.equal(other.status, 1);
  assert.equal(other.args.length, 1);
  assert.match(other.stderr, /^::error::.*hit GitHub's core API rate limit/m);
});

const lagged = () => [
  [answer("200 OK", {}, listing(UNLISTED)), 0],
  [answer("200 OK", {}, listing(UNLISTED)), 0],
];
// The job-level setting a pr-refine.yml job passes the script, read from the
// job's block in the workflow file; this suite runs with no yaml dependency.
function refineJobEnv(name) {
  const blocks = readFileSync(new URL("../../workflows/pr-refine.yml", import.meta.url), "utf8").split(/^(?=  [\w-]+:$)/m);
  const value = /^ {6}HANDOFF_EVIDENCE_LAG: (\S+)$/m.exec(blocks.find((block) => block.startsWith(`  ${name}:`)))?.[1];
  return value ? { HANDOFF_EVIDENCE_LAG: value } : {};
}

// An empty output starts a second leg in pr-unblock.yml, so the opt-in stays on
// the two jobs whose empty facts start nothing.
// Beside pr-refine.yml's two fix-docs handoff jobs, the key-credit-markers
// jobs name it: their empty outputs start nothing, so a read that cannot
// settle ends with a notice and uploads no marker.
test("only the fix-docs handoff jobs and the key-credit-markers jobs name HANDOFF_EVIDENCE_LAG", () => {
  const dir = new URL("../../workflows/", import.meta.url);
  const text = (file) => readFileSync(new URL(file, dir), "utf8");
  const files = readdirSync(dir).filter((file) => /\.ya?ml$/.test(file) && text(file).includes("HANDOFF_EVIDENCE_LAG"));
  assert.deepEqual(files, ["pr-refine.yml", "pr-unblock.yml", "work-resolve-issue.yml"]);
  const jobsNaming = (file) =>
    text(file).split(/^(?=  [\w-]+:$)/m).filter((block) => block.includes("HANDOFF_EVIDENCE_LAG")).map((block) => /^ {2}([\w-]+):$/m.exec(block)?.[1]);
  assert.deepEqual(jobsNaming("pr-refine.yml"), ["fix-docs-handoff", "key-credit-markers", "fix-docs-subscription-handoff"]);
  assert.deepEqual(jobsNaming("pr-unblock.yml"), ["key-credit-markers"]);
  assert.deepEqual(jobsNaming("work-resolve-issue.yml"), ["key-credit-markers"]);
});

test("a fact still unsettled in a listing that was read fails with no output by default", () => {
  const out = run(lagged(), "0");
  assert.equal(out.status, 1);
  assert.match(out.stdout, /^::error::handoff evidence for fix-docs still missing after 2 reads: missing: fix-docs \/ report has no steps listed$/m);
  assert.equal(out.output, "");
});

for (const name of ["fix-docs-handoff", "fix-docs-subscription-handoff"]) {
  test(`${name}: a listing that lags past the last read ends as a notice with no output`, () => {
    const out = run(lagged(), "0", { env: refineJobEnv(name) });
    assert.equal(out.status, 0, out.stdout + out.stderr);
    assert.match(out.stdout, /^::notice::handoff evidence for fix-docs still missing after 2 reads: missing: fix-docs \/ report has no steps listed; the outputs stay empty$/m);
    assert.doesNotMatch(out.stdout, /::error::/);
    assert.equal(out.output, "", "an empty output starts no later leg");
  });

  // The opt-in names lag alone: a failed read holds through the CALLS scope, and
  // the opt-in does not green one for any other call.
  test(`${name}: a read that failed fails under the opt-in outside the fix-docs calls and holds on them; a fact the script does not know still fails`, () => {
    const env = refineJobEnv(name);
    const failed = answer("403 Forbidden", {}, { message: "Resource not accessible by integration" });
    const unread = run([[failed, 1], [failed, 1]], "0", { env, calls: "fix-ci" });
    assert.equal(unread.status, 1);
    assert.match(unread.stdout, /^::error::handoff evidence for fix-ci still missing after 2 reads: the jobs read failed$/m);
    assert.equal(unread.output, "");
    const notJson = [answer("200 OK", {}).replace(/\r\n$/, "\r\n[1]"), 0];
    const unparsed = run([notJson, notJson], "0", { env, calls: "fix-ci" });
    assert.equal(unparsed.status, 1);
    assert.equal(unparsed.output, "");
    for (const answers of [[[failed, 1], [failed, 1]], [notJson, notJson]]) {
      const held = run(answers, "0", { env });
      assert.equal(held.status, 0);
      assert.match(held.stdout, /^::notice title=Handoff evidence hold::handoff evidence for fix-docs still missing after 2 reads: the jobs read failed;/m);
      assert.equal(held.output, "");
    }
    const usage = run([], "0", { env, facts: ["nonsense"] });
    assert.equal(usage.status, 2);
    assert.match(usage.stdout, /^::error::unknown handoff fact: nonsense$/m);
  });
}
