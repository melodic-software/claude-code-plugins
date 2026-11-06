// pr-review-main.yml's trusted-text job reads the PR's trusted text once per
// run (outage posture element 6). Each leg takes that read only when it is this
// run attempt's, read at the leg's main commit for its PR and head, with the
// bytes the job's sha256 names; anything else, a missing artifact included,
// leaves the leg to read its own. The job and the edges to it never fail the
// run or skip a leg.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { admits } from "../lib/gate-expression.mjs";

const text = readFileSync(new URL("../../workflows/pr-review-main.yml", import.meta.url), "utf8");
const TAKE = new URL("./take-shared-text.sh", import.meta.url).pathname;
const LEGS = ["review", "review-subscription", "review-fallback"];
const TEXT = "trusted-text";
const jobText = (id) => {
  const found = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(text);
  assert.ok(found, `a job ${id}`);
  return found[1];
};
const stepsOf = (id) =>
  jobText(id)
    .split(/\n(?=      - name: )/)
    .slice(1)
    .map((block) => ({ name: /^      - name: (.*)$/m.exec(block)[1], block: block.replace(/\n\n {2}(?: {4})?#[\s\S]*$/, "") }));
const step = (job, name) => {
  const found = stepsOf(job).find((s) => s.name === name);
  assert.ok(found, `a step named ${name} in ${job}`);
  return found.block;
};
const ifOf = (block) => /^ {8}if: (.*)$/m.exec(block)?.[1];
const envOf = (block, key) => new RegExp(`^ {10}${key}: (.*)$`, "m").exec(block)?.[1];
const jobGate = (id) => /^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(jobText(id))?.[1].replace(/\s+/g, " ").trim();

const PR = 7;
const HEAD = "b".repeat(40);
const CONTEXT = `${JSON.stringify({ pr: { number: PR, head_sha: HEAD, base_sha: "c".repeat(40), author_id: 1, title: "t", body: "b" }, items: [], dropped: {} }, null, 2)}\n`;

// A main checkout with one commit, the shared read's context.json and its
// sha256 taken here with node's crypto, and the leg's matching values.
function harness() {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-shared-"));
  const base = path.join(dir, ".base");
  mkdirSync(base);
  const git = (...args) => spawnSync("git", ["-C", base, ...args], { encoding: "utf8", env: { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" } });
  git("init", "-q");
  git("-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "--allow-empty", "-m", "main");
  const main = git("rev-parse", "HEAD").stdout.trim();
  assert.match(main, /^[0-9a-f]{40}$/);
  const shared = path.join(dir, "shared", "context.json");
  mkdirSync(path.dirname(shared));
  writeFileSync(shared, CONTEXT);
  const context = path.join(dir, "data", "context.json");
  const out = path.join(dir, "out");
  const matching = {
    SHARED_FILE: shared,
    SHARED_SHA256: createHash("sha256").update(CONTEXT).digest("hex"),
    SHARED_ATTEMPT: "1",
    SHARED_MAIN: main,
    SHARED_PR: String(PR),
    SHARED_HEAD: HEAD,
    RUN_ATTEMPT: "1",
    PR_NUMBER: String(PR),
    HEAD_SHA: HEAD,
    BASE_DIR: base,
    CONTEXT_FILE: context,
  };
  const run = (changes = {}) => {
    writeFileSync(out, "");
    rmSync(path.dirname(context), { recursive: true, force: true });
    const result = spawnSync("bash", [TAKE], { encoding: "utf8", env: { ...process.env, GITHUB_OUTPUT: out, ...matching, ...changes } });
    return { status: result.status, stdout: result.stdout, out: readFileSync(out, "utf8"), taken: existsSync(context) ? readFileSync(context, "utf8") : null };
  };
  return { run, dir, shared, remove: () => rmSync(dir, { recursive: true, force: true }) };
}

test("a leg takes the shared read only when its hash, main commit, PR, head and run attempt match", () => {
  const h = harness();
  try {
    const good = h.run();
    assert.equal(good.status, 0, good.stdout);
    assert.equal(good.out, "shared=true\n");
    assert.equal(good.taken, CONTEXT);
    const mismatches = {
      "the hash differs": { SHARED_SHA256: createHash("sha256").update(`${CONTEXT} `).digest("hex") },
      "another main commit": { SHARED_MAIN: "d".repeat(40) },
      "another pull request": { SHARED_PR: "8" },
      "another head": { SHARED_HEAD: "e".repeat(40) },
      "another run attempt": { SHARED_ATTEMPT: "1", RUN_ATTEMPT: "2" },
      "no hash": { SHARED_SHA256: "" },
      "no artifact": { SHARED_FILE: `${h.shared}.missing` },
    };
    for (const [reason, changes] of Object.entries(mismatches)) {
      const own = h.run(changes);
      assert.equal(own.status, 0, reason);
      assert.equal(own.out, "", reason);
      assert.equal(own.taken, null, reason);
      assert.match(own.stdout, new RegExp(`^the shared trusted PR text is not used \\(${reason}\\); this leg reads its own$`, "m"), reason);
    }
    // A hash over a file naming another PR still leaves the leg its own read.
    const other = CONTEXT.replace(`"number": ${PR}`, '"number": 8');
    writeFileSync(h.shared, other);
    const named = h.run({ SHARED_SHA256: createHash("sha256").update(other).digest("hex") });
    assert.equal(named.out, "");
    assert.equal(named.taken, null);
  } finally {
    h.remove();
  }
});

test("each leg reads its own text unless the shared read was taken, from the trusted-text job's outputs", () => {
  for (const job of LEGS) {
    const names = stepsOf(job).map((s) => s.name);
    const at = names.indexOf("Select the trusted PR text");
    assert.deepEqual(names.slice(at - 2, at + 1), ["Download the shared trusted PR text", "Take the shared trusted PR text", "Select the trusted PR text"], job);
    const download = step(job, "Download the shared trusted PR text");
    assert.match(download, /^ {8}continue-on-error: true$/m, job);
    assert.match(download, /^ {8}uses: actions\/download-artifact@[0-9a-f]{40} # /m, job);
    assert.match(download, /^ {10}name: trusted-text-pr-review-main$/m, job);
    const take = step(job, "Take the shared trusted PR text");
    assert.match(take, /^ {8}id: shared$/m, job);
    assert.match(take, /^ {8}continue-on-error: true$/m, job);
    assert.match(take, /^ {8}run: bash \.base\/\.github\/scripts\/pr-review-main\/take-shared-text\.sh$/m, job);
    for (const [key, value] of Object.entries({
      SHARED_FILE: "${{ runner.temp }}/pr-review-main-shared-text/context.json",
      SHARED_SHA256: "${{ needs.trusted-text.outputs.sha256 }}",
      SHARED_ATTEMPT: "${{ needs.trusted-text.outputs.run-attempt }}",
      SHARED_MAIN: "${{ needs.trusted-text.outputs.main-sha }}",
      SHARED_PR: "${{ needs.trusted-text.outputs.pr-number }}",
      SHARED_HEAD: "${{ needs.trusted-text.outputs.head-sha }}",
      RUN_ATTEMPT: "${{ github.run_attempt }}",
      PR_NUMBER: "${{ steps.trigger.outputs.pr-number }}",
      HEAD_SHA: "${{ steps.trigger.outputs.head-sha }}",
      BASE_DIR: ".base",
      CONTEXT_FILE: "${{ github.workspace }}/pr-review-main-data/context.json",
    })) {
      assert.equal(envOf(take, key), value, `${job}: ${key}`);
    }
    // The download lands where the take step reads it.
    assert.equal(envOf(download, "path"), "${{ runner.temp }}/pr-review-main-shared-text", job);
    const reviewed = { steps: { diff: { outcome: "success", outputs: { stop: "" } } } };
    const select = ifOf(step(job, "Select the trusted PR text"));
    for (const shared of [undefined, "", "false"]) {
      const context = { steps: { ...reviewed.steps, shared: { outputs: shared === undefined ? {} : { shared } } } };
      assert.ok(admits(select, context), `${job}: own read on ${shared}`);
      assert.ok(admits(ifOf(take), context), `${job}: take runs`);
    }
    assert.ok(!admits(select, { steps: { ...reviewed.steps, shared: { outputs: { shared: "true" } } } }), `${job}: no own read once taken`);
    // A failed or missing shared read downloads nothing.
    const downloads = (outputs, attempt = "1") => admits(ifOf(download), { ...reviewed, github: { run_attempt: attempt }, needs: { [TEXT]: { outputs } } });
    assert.ok(downloads({ sha256: "f".repeat(64), "run-attempt": "1" }), job);
    assert.ok(!downloads({ sha256: "", "run-attempt": "1" }), job);
    assert.ok(!downloads({ sha256: "f".repeat(64), "run-attempt": "1" }, "2"), job);
  }
});

const upstreamRun = { ref: "refs/heads/main", repository: "o/r", run_attempt: "1", event: { workflow_run: { event: "pull_request", conclusion: "success", head_repository: { full_name: "o/r" } } } };
const triggered = { result: "success", outputs: { "run-attempt": "1", proceed: "true", review: "true", judged: "", held: "" } };

test("every leg needs the trusted-text job and still runs when it failed, was skipped or left no hash", () => {
  const needs = (job) => /^ {4}needs: \[(.*)\]$/m.exec(jobText(job))?.[1].split(", ") ?? [];
  for (const job of LEGS) assert.ok(needs(job).includes(TEXT), job);
  // Without a status function GitHub adds success(), which a failed
  // trusted-text job would fail; each leg's gate starts with its own.
  for (const job of LEGS) assert.ok(/^(?:\S+ != 'true' && )?!cancelled\(\) && /.test(jobGate(job)), `${job}: ${jobGate(job)}`);
  for (const result of ["failure", "skipped", "success"]) {
    const text = { result, outputs: {} };
    assert.ok(admits(jobGate("review"), { github: upstreamRun, needs: { trigger: triggered, "review-handoffs-credit": { result: "success", outputs: {} }, [TEXT]: text } }), `review: ${result}`);
    assert.ok(admits(jobGate("review-subscription"), { github: upstreamRun, needs: { "review-handoffs": { result: "success", outputs: {} }, [TEXT]: text } }), `subscription: ${result}`);
    assert.ok(admits(jobGate("review-fallback"), { github: upstreamRun, needs: { "subscription-handoffs": { result: "success", outputs: {} }, [TEXT]: text } }), `fallback: ${result}`);
  }
  for (const job of LEGS) assert.doesNotMatch(jobGate(job), /needs\.trusted-text/, job);
});

test("the trusted-text job never fails the run, and runs only where this attempt's trigger job starts the legs", () => {
  const job = jobText(TEXT);
  assert.match(job, /^ {4}continue-on-error: true$/m);
  assert.match(job, /^ {4}permissions:\n {6}contents: read #.*\n {6}pull-requests: read #.*\n {4}outputs:/m);
  assert.doesNotMatch(job, /secrets\.|run-claude-cli|exit 1/);
  // Each step that can fail carries its own continue-on-error, so the job ends green.
  for (const s of stepsOf(TEXT)) {
    if (s.name === "Report the kill switch") continue;
    assert.match(s.block, /^ {8}continue-on-error: true$/m, s.name);
  }
  const runs = (trigger, github = upstreamRun) => admits(jobGate(TEXT), { github, needs: { trigger } });
  assert.ok(runs(triggered));
  for (const outputs of [{ "run-attempt": "2" }, { proceed: "" }, { review: "false" }, { judged: "true" }, { held: "true" }]) {
    assert.ok(!runs({ ...triggered, outputs: { ...triggered.outputs, ...outputs } }), JSON.stringify(outputs));
  }
  assert.ok(!runs({ ...triggered, result: "failure" }));
  assert.ok(!runs(triggered, { ...upstreamRun, ref: "refs/heads/x" }));
  // The read runs only under the legs' kill switch and upstream status.
  const report = step(TEXT, "Report the kill switch");
  const script = /^ {8}run: \|\n((?: {10}.*\n)+)/m.exec(`${report}\n`)[1].replace(/^ {10}/gm, "");
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-text-switch-"));
  try {
    const out = path.join(dir, "out");
    const proceed = (env) => {
      writeFileSync(out, "");
      const result = spawnSync("bash", ["-e", "-c", script], { encoding: "utf8", env: { ...process.env, GITHUB_OUTPUT: out, ...env } });
      assert.equal(result.status, 0, JSON.stringify(env));
      return readFileSync(out, "utf8") === "proceed=true\n";
    };
    assert.ok(proceed({ PROCEED: "true", UPSTREAM_DEGRADED: "false", LANES_OFF: "false" }));
    assert.ok(!proceed({ PROCEED: "false", UPSTREAM_DEGRADED: "false", LANES_OFF: "false" }));
    assert.ok(!proceed({ PROCEED: "true", UPSTREAM_DEGRADED: "true", LANES_OFF: "false" }));
    assert.ok(!proceed({ PROCEED: "true", UPSTREAM_DEGRADED: "false", LANES_OFF: "true" }));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  assert.equal(ifOf(step(TEXT, "Select the trusted PR text")), "steps.switch.outputs.proceed == 'true'");
  // A hash leaves the job only for bytes that uploaded after a clean scan.
  assert.equal(ifOf(step(TEXT, "Upload the trusted PR text")), "(steps.select.outcome == 'success') && steps.scan.outputs.clean == 'true'");
  assert.equal(ifOf(step(TEXT, "Record what was read")), "steps.upload.outcome == 'success'");
  for (const [output, from] of [["sha256", "hash"], ["main-sha", "hash"], ["pr-number", "hash"], ["head-sha", "hash"]]) {
    assert.match(job, new RegExp(`^ {6}${output}: \\$\\{\\{ steps\\.${from}\\.outputs\\.${output} \\}\\}$`, "m"), output);
  }
  assert.match(job, /^ {6}run-attempt: \$\{\{ github\.run_attempt \}\}$/m);
});

test("the trusted-text job's record holds only fixed shapes, hashing the uploaded bytes", () => {
  const record = step(TEXT, "Record what was read");
  const script = /^ {8}run: \|\n((?: {10}.*\n)+)/m.exec(`${record}\n`)[1].replace(/^ {10}/gm, "");
  const h = harness();
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-text-record-"));
  try {
    const out = path.join(dir, "out");
    const run = (env) => {
      writeFileSync(out, "");
      const result = spawnSync("bash", ["-e", "-o", "pipefail", "-c", script], { cwd: h.dir, encoding: "utf8", env: { ...process.env, GITHUB_OUTPUT: out, FILE: h.shared, PR_NUMBER: String(PR), HEAD_SHA: HEAD, ...env } });
      assert.equal(result.status, 0, result.stderr);
      return readFileSync(out, "utf8");
    };
    const lines = Object.fromEntries(run({}).trim().split("\n").map((line) => line.split("=")));
    assert.equal(lines.sha256, createHash("sha256").update(CONTEXT).digest("hex"));
    assert.match(lines["main-sha"], /^[0-9a-f]{40}$/);
    assert.equal(lines["pr-number"], String(PR));
    assert.equal(lines["head-sha"], HEAD);
    assert.equal(run({ PR_NUMBER: "7; echo x" }), "");
    assert.equal(run({ HEAD_SHA: "main" }), "");
  } finally {
    h.remove();
    rmSync(dir, { recursive: true, force: true });
  }
});
