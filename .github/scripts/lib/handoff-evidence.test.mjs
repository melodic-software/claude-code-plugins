// handoff-evidence.sh's job-listing reads, on a stub gh that gives each call
// the next answer in turn: a read after the first sends each page it already
// got with that page's ETag, a 304 gives back that page's stored body, each
// page keeps its own ETag, and a page with no ETag or a failed one is read
// again unconditionally.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

// Runs `handoff-evidence.sh posted` for CALLS=fix-docs with no waits; each
// answer is [gh -i output, gh exit status]. A call past the last answer gets
// nothing and exits 1.
function run(answers, delays = "0 0 0") {
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
    const output = join(dir, "output");
    writeFileSync(output, "");
    const result = spawnSync("bash", [SCRIPT, "posted"], {
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        RUNNER_TEMP: "",
        GH_TOKEN: "t",
        GITHUB_REPOSITORY: "o/r",
        GITHUB_RUN_ID: "7",
        GITHUB_OUTPUT: output,
        CALLS: "fix-docs",
        HANDOFF_EVIDENCE_DELAYS: delays,
      },
    });
    const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
    return { status: result.status, stdout: result.stdout, stderr: result.stderr, output: read("output"), args: read("args").split("\n").filter(Boolean) };
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

test("a listing still unread after the last delay fails with no output", () => {
  const failed = answer("502 Bad Gateway", {}, { message: "Server Error" });
  const out = run([[failed, 1], [failed, 1]], "0");
  assert.equal(out.status, 1);
  assert.equal(out.args.length, 2);
  assert.match(out.stdout, /^::error::handoff evidence for fix-docs still missing after 2 reads: the jobs read failed$/m);
  assert.equal(out.output, "");
});
