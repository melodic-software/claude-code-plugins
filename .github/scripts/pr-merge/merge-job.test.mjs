// pr-merge.yml's merge job: the post-merge check and its re-dispatch do not
// wait on the candidate listing or the gate loop (#8299; a GraphQL 502 on the
// listing once held back every re-dispatch), the listing retries a failed
// `gh pr list` and fails with one clear error, the run logs its API cost
// through the shared action, and the run cache carries the verdict reads that
// never change to the next run.
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const text = readFileSync(join(root, ".github/workflows/pr-merge.yml"), "utf8");
const jobBlock = (id) => {
  const match = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(text);
  assert.ok(match, `job ${id}`);
  return match[1];
};
const stepsOf = (block) =>
  block
    .split(/\n(?=      - name: )/)
    .slice(1)
    .map((b) => ({ name: /^      - name: (.*)$/m.exec(b)[1], block: b }));
const job = jobBlock("merge");
const steps = stepsOf(job);
const step = (name, list = steps) => {
  const found = list.find((s) => s.name === name);
  assert.ok(found, `step ${name}`);
  return found.block;
};
const runScript = (name, list = steps) => {
  const body = /\n {8}run: \|\n([\s\S]*)$/.exec(step(name, list))[1];
  const lines = body.split("\n");
  const end = lines.findIndex((line) => line !== "" && !line.startsWith(" ".repeat(10)));
  return (end < 0 ? lines : lines.slice(0, end)).map((line) => line.slice(10)).join("\n");
};

test("the re-dispatch for earlier lane merges waits on neither the listing nor the gate", () => {
  const early = jobBlock("post-merge-dispatch");
  const header = early.slice(0, early.indexOf("\n    steps:\n"));
  assert.doesNotMatch(header, /\n    needs:/);
  const list = stepsOf(early);
  assert.deepEqual(
    list.map((s) => s.name),
    [
      "Check out the default branch tip",
      "Set up Node",
      "Check the kill switch",
      "Read report-only",
      "Read the lane records the last run kept",
      "Check earlier lane merges",
      "Keep the post-merge report for enable-auto-merge",
      "Start the full CI run on main",
      "Record the dispatched run",
      "Re-run a red lane-dispatched full run",
      "Record the re-run",
    ],
  );
  assert.doesNotMatch(early, /steps\.candidates|steps\.gate|needs\.merge/);
  assert.match(step("Check earlier lane merges", list), /\n {8}if: steps\.mode\.outputs\.live == 'true'\n/);
  assert.match(step("Check earlier lane merges", list), /babysit_postmerge\.py[\s\S]*--lane-merges-only/);
  assert.match(step("Read report-only", list), /if: steps\.kill\.outputs\.proceed == 'true'/);
});

test("the early re-dispatch keeps the trusted mechanics and skips untrusted events", () => {
  const early = jobBlock("post-merge-dispatch");
  const condition = /(?:^|\n)    if: >-\n([\s\S]*?)\n    [a-z-]+:/.exec(early)[1];
  assert.match(condition, /github\.ref == 'refs\/heads\/main'/);
  assert.match(condition, /\(github\.event_name == 'schedule' \|\| github\.event_name == 'workflow_dispatch'\)/);
  const list = stepsOf(early);
  const dispatch = step("Start the full CI run on main", list);
  assert.match(dispatch, /if: steps\.post-merge\.outputs\.needs-dispatch == 'true'/);
  assert.match(dispatch, /actions\/workflows\/pr-require-checks\.yml\/dispatches"[\s\S]*-f ref=main /);
  const upload = step("Record the dispatched run", list);
  assert.match(upload, /uses: actions\/upload-artifact@/);
  assert.match(upload, /name: pr-merge-dispatched-\$\{\{ steps\.dispatch\.outputs\.run-id \}\}\n/);
  // The merge job's Actions token stays read-only; only this job writes.
  assert.match(job, /\n {6}actions: read\n/);
  assert.match(early, /\n {6}actions: write /);
  assert.doesNotMatch(job, /dispatch: .*needs-dispatch/);
});

// Runs the listing step's script against a fake `gh` whose `gh pr list`
// fails its first `failures` calls, with `.base` pointing at this checkout,
// or, given `edit`, at a copy whose pr-pipeline.yaml is `edit(text)` and whose
// trusted-actors.json is `actors`, when given, else this checkout's.
// `env` overrides the step's environment: merge.lane-prs is `gate` unless it
// says otherwise, the mode that lists the lanes App's own pull requests.
const runListing = (failures, edit, actors, env = {}, failure = "HTTP 502: Bad Gateway") => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-listing-"));
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", [bin]);
    writeFileSync(
      join(bin, "gh"),
      `#!/usr/bin/env bash\necho "$*" >>"${dir}/args"\n` +
        `n=$(($(cat "${dir}/calls" 2>/dev/null || echo 0) + 1))\necho "$n" >"${dir}/calls"\n` +
        `if [ "$n" -le ${failures} ]; then echo "${failure}" >&2; exit 1; fi\n` +
        `echo '[{"number":7,"headRefOid":"abc","isDraft":false,"updatedAt":"2026-10-18T00:00:00Z","labels":[],"body":""}]'\n`,
    );
    writeFileSync(join(bin, "sleep"), "#!/usr/bin/env bash\n");
    chmodSync(join(bin, "gh"), 0o755);
    chmodSync(join(bin, "sleep"), 0o755);
    if (edit === undefined) {
      symlinkSync(root, join(dir, ".base"));
    } else {
      const conventions = join(dir, ".base/docs/conventions");
      const standards = join(dir, ".base/.github/standards/trusted-actors");
      mkdirSync(conventions, { recursive: true });
      mkdirSync(standards, { recursive: true });
      const config = readFileSync(join(root, "docs/conventions/pr-pipeline.yaml"), "utf8");
      writeFileSync(join(conventions, "pr-pipeline.yaml"), edit(config));
      const list = join(root, ".github/standards/trusted-actors/trusted-actors.json");
      writeFileSync(join(standards, "trusted-actors.json"), actors === undefined ? readFileSync(list, "utf8") : JSON.stringify({ version: 1, actors }));
      symlinkSync(join(root, "plugins"), join(dir, ".base/plugins"));
      // The shared rate guard the listing sources.
      symlinkSync(join(root, ".github/actions"), join(dir, ".base/.github/actions"));
      symlinkSync(join(root, ".github/scripts"), join(dir, ".base/.github/scripts"));
    }
    const output = join(dir, "output");
    const result = spawnSync("bash", ["-c", runScript("List the candidate PRs")], {
      cwd: dir,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        RUNNER_TEMP: dir,
        GITHUB_OUTPUT: output,
        REPO: "o/r",
        DEPENDABOT: "off",
        LANE_PRS: "gate",
        ...env,
      },
    });
    const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
    return {
      status: result.status,
      stdout: result.stdout,
      stderr: result.stderr,
      calls: Number(read("calls") || 0),
      args: read("args"),
      candidates: read("candidates.json"),
      drafts: read("drafts.json"),
      prefiltered: existsSync(join(dir, "prefilter.json")),
      output: existsSync(output) ? readFileSync(output, "utf8") : "",
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

const authorsOf = (args) => [...args.matchAll(/^pr list .*--author (\S+) /gm)].map((m) => m[1]);

test("the listing retries a failed gh pr list", () => {
  const run = runListing(2);
  assert.equal(run.status, 0, run.stderr);
  // Three tries for the lane's list, then one for each other author's.
  assert.equal(run.calls, new Set(authorsOf(run.args)).size + 2);
  assert.match(run.output, /^count=1$/m);
});

// Owner decision 2026-10-22: every trusted actor's PR is a candidate.
test("the listing adds each trusted actor, a person by login and an App as app/<slug>, once", () => {
  const actors = [
    { id: 1, login: "a-person", kind: "human" },
    { id: 2, login: "some-release[bot]", kind: "bot" },
    { id: 3, login: "melodic-automation-lanes[bot]", kind: "bot" },
    { id: 4, login: "dependabot[bot]", kind: "bot" },
    { id: 5, login: "bad login; rm", kind: "human" },
  ];
  const run = runListing(0, (config) => config, actors);
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(authorsOf(run.args), ["app/melodic-automation-lanes", "a-person", "app/some-release"]);
  assert.doesNotMatch(run.args, /^api /m);
});

test("without an adoption section no trusted actor is listed", () => {
  const run = runListing(0, (config) => config.replace(/^adoption:\n( {2}.*\n)*/m, ""));
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(authorsOf(run.args), ["app/melodic-automation-lanes"]);
  // Nor with a section that sets no idle-hours, which the gate adopts nothing under.
  const noIdle = runListing(0, (config) => config.replace(/^ {2}idle-hours: 24\n/m, ""));
  assert.equal(noIdle.status, 0, noIdle.stderr);
  assert.deepEqual(authorsOf(noIdle.args), ["app/melodic-automation-lanes"]);
});

// merge.lane-prs: native leaves the lanes App's pull requests to GitHub's
// auto-merge: the listing never asks for them, so the gate never reads them.
test("under lane-prs native the listing skips the lanes App and keeps every other author", () => {
  const actors = [
    { id: 1, login: "a-person", kind: "human" },
    { id: 3, login: "melodic-automation-lanes[bot]", kind: "bot" },
  ];
  const native = runListing(0, (config) => config, actors, { LANE_PRS: "native", DEPENDABOT: "enforce" });
  assert.equal(native.status, 0, native.stderr);
  assert.deepEqual(authorsOf(native.args), ["a-person", "app/dependabot"]);
  assert.match(native.output, /^count=1$/m);
  // gate lists the lanes App first, as before the setting existed.
  const gate = runListing(0, (config) => config, actors, { LANE_PRS: "gate", DEPENDABOT: "enforce" });
  assert.equal(gate.status, 0, gate.stderr);
  assert.deepEqual(authorsOf(gate.args), ["app/melodic-automation-lanes", "a-person", "app/dependabot"]);
});

test("under lane-prs native with no other author the listing calls nothing and lists no candidate", () => {
  const run = runListing(0, (config) => config.replace(/^adoption:\n( {2}.*\n)*/m, ""), undefined, { LANE_PRS: "native" });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.calls, 0);
  assert.equal(run.candidates.trim(), "[]");
  assert.equal(run.drafts.trim(), "[]");
  assert.match(run.output, /^count=0$/m);
});

test("the mode step outputs merge.lane-prs as resolve-config resolved it, and the listing reads it", () => {
  for (const mode of ["native", "gate"]) {
    const dir = mkdtempSync(join(tmpdir(), "pr-merge-mode-"));
    try {
      symlinkSync(root, join(dir, ".base"));
      writeFileSync(join(dir, "resolved-config.json"), JSON.stringify({ merge: { "lane-prs": mode } }));
      const result = spawnSync("bash", ["-c", runScript("Read report-only")], {
        cwd: dir,
        encoding: "utf8",
        env: { ...process.env, RUNNER_TEMP: dir, GITHUB_OUTPUT: join(dir, "output") },
      });
      assert.equal(result.status, 0, result.stderr);
      assert.match(readFileSync(join(dir, "output"), "utf8"), new RegExp(`^lane-prs=${mode}$`, "m"));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }
  assert.match(step("List the candidate PRs"), /\n {10}LANE_PRS: \$\{\{ steps\.mode\.outputs\.lane-prs \}\}\n/);
});

// A rate limit is never retried, gh's bare 429 message included.
test("a rate-limited listing stops red after one call, a bare HTTP 429 included", () => {
  for (const failure of ["gh: Too Many Requests (HTTP 429)", "API rate limit exceeded for installation ID 1. (HTTP 403)"]) {
    const run = runListing(3, undefined, undefined, {}, failure);
    assert.equal(run.status, 1, failure);
    assert.equal(run.calls, 1, failure);
    assert.match(run.stdout, /^::error title=GitHub rate limit::gh pr list --author app\/[a-z0-9-]+ was rate limited \(every pool until /m, failure);
    assert.equal(run.prefiltered, false);
  }
});

test("the listing fails with one clear error after three failed tries", () => {
  const run = runListing(3);
  assert.equal(run.status, 1);
  assert.equal(run.calls, 3);
  assert.match(run.stdout, /^::error::gh pr list --author app\/[a-z0-9-]+ failed 3 times/m);
  assert.equal(run.prefiltered, false);
  assert.doesNotMatch(run.stderr, /jq: error|Traceback/);
});

test("the job end logs both tokens' readings from the job's own responses, and reads no /rate_limit", () => {
  const block = step("Log the API budget at job end");
  assert.match(block, /\n {8}uses: \.\/\.base\/\.github\/actions\/log-api-budget /);
  assert.match(block, /\n {8}if: always\(\) && steps\.lane-token\.outputs\.token != ''\n/);
  assert.match(block, /\n {8}continue-on-error: true\n/);
  assert.match(block, /\n {10}tokens: lanes-app github-token\n/);
  assert.doesNotMatch(job, /gh api rate_limit|phase: start|\$\{\{ [^}]*token[^}]* \}\}\n {10}tokens:/);
  // The gate's babysit calls read into both names: the lane token by default,
  // the job token for the verdict reads that carry it.
  const gate = step("Run the merge gate on each candidate");
  assert.match(gate, /\n {10}API_BUDGET_TOKEN: lanes-app\n/);
  assert.match(gate, /\n {10}API_BUDGET_OVERRIDE_TOKEN: github-token\n/);
  const names = steps.map((s) => s.name);
  assert.ok(names.indexOf("Run the merge gate on each candidate") < names.indexOf("Log the API budget at job end"));
  assert.ok(names.indexOf("Log the API budget at job end") < names.indexOf("Revoke the lane token"));
});

// Runs the sweep-cost step with the end reading's costs and a summary of
// `reached` gate verdicts and `skipped` carried ones beside one held candidate.
const runSweepCost = (costs, reached, skipped = 0) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-cost-"));
  try {
    writeFileSync(join(dir, "held.json"), '[{"number": 9}]');
    const rows = [
      { pr: 9 },
      ...Array.from({ length: reached }, (_, i) => ({ pr: i + 1 })),
      ...Array.from({ length: skipped }, (_, i) => ({ pr: i + 20, carried: { skips: 1 } })),
    ];
    writeFileSync(join(dir, "pr-merge-summary.json"), JSON.stringify(rows));
    const result = spawnSync("bash", ["-eo", "pipefail", "-c", runScript("Write the sweep cost")], {
      encoding: "utf8",
      env: { ...process.env, RUNNER_TEMP: dir, GITHUB_STEP_SUMMARY: join(dir, "step-summary"), COSTS: costs, CANDIDATES: "5" },
    });
    return { status: result.status, stdout: result.stdout, stepSummary: readFileSync(join(dir, "step-summary"), "utf8") };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

test("the sweep cost names both tokens' spend, the candidates, those reached and those skipped, in the log and the summary", () => {
  const run = runSweepCost("lanes-app-cost=312 github-token-cost=41", 3, 2);
  assert.equal(run.status, 0);
  const line = "sweep-cost=312 github-token-cost=41 candidates=5 reached=3 skipped=2\n";
  assert.equal(run.stdout, line);
  assert.equal(run.stepSummary, line);
  // A rolled window, or no end reading, reads unknown.
  assert.equal(runSweepCost("lanes-app-cost=unknown", 0).stdout, "sweep-cost=unknown github-token-cost=unknown candidates=5 reached=0 skipped=0\n");
  const block = step("Write the sweep cost");
  assert.match(block, /\n {8}if: always\(\) && steps\.gate\.outcome != 'skipped'\n/);
  assert.match(block, /COSTS: \$\{\{ steps\.budget-end\.outputs\.costs \}\}/);
  const names = steps.map((s) => s.name);
  assert.ok(names.indexOf("Log the API budget at job end") < names.indexOf("Write the sweep cost"));
});

// The run cache's carried reads (carry-run-cache.mjs) reach both token-holding
// jobs as the head-ref map does (#9416): read from the last trusted run's
// pr-merge-run-cache artifact, and uploaded by scheduled and hand-started
// merge jobs only, the runs a later read accepts. Neither job restores an
// Actions cache, which any job in main's cache scope can write (#9455).
test("both token-holding jobs read the carried reads from the last trusted run's artifact, never a cache", () => {
  const carried = "${{ runner.temp }}/pr-merge-carried.json";
  const runCache = "${{ runner.temp }}/babysit-run-cache.json";
  const read = "Read the verdict reads the last run kept";
  for (const list of [steps, stepsOf(jobBlock("enable-auto-merge"))]) {
    const names = list.map((s) => s.name);
    assert.ok(names.indexOf(read) >= 0 && names.indexOf(read) < names.indexOf("Start the run cache from them"));
    const block = step(read, list);
    assert.match(block, /run: node \.base\/\.github\/scripts\/pr-merge\/carry-run-cache\.mjs read\n/);
    assert.ok(block.includes(`CARRY_TO: ${carried}\n`) && block.includes("ACTIONS_TOKEN: ${{ github.token }}\n"));
    assert.match(block, /\n {8}timeout-minutes: 2\n/);
    const start = step("Start the run cache from them", list);
    assert.ok(start.includes(`CARRY_FROM: ${carried}\n`) && start.includes(`CARRY_TO: ${runCache}\n`));
    assert.match(start, /run: node \.base\/\.github\/scripts\/pr-merge\/carry-run-cache\.mjs\n/);
    for (const name of [read, "Start the run cache from them"]) {
      assert.match(step(name, list), /\n {8}continue-on-error: true\n/, name);
    }
    for (const s of list) assert.doesNotMatch(s.block, /uses: actions\/cache[@/]/, s.name);
  }
  const names = steps.map((s) => s.name);
  const order = [
    read,
    "Skip refusals whose inputs have not changed",
    "Run the merge gate on each candidate",
    "Keep the verdict reads that never change",
    "Keep the refusals the next run may skip",
    "Upload the verdict reads for the next run",
  ].map((name) => names.indexOf(name));
  assert.ok(order.every((i, n) => i >= 0 && (n === 0 || i > order[n - 1])), String(order));
  assert.ok(step("Run the merge gate on each candidate").includes(`BABYSIT_RUN_CACHE: ${runCache}\n`));
  const keep = step("Keep the verdict reads that never change");
  assert.ok(keep.includes(`CARRY_FROM: ${runCache}\n`) && keep.includes(`CARRY_TO: ${carried}\n`));
  assert.ok(
    keep.includes(
      "always() && steps.gate.outcome != 'skipped'\n          && (github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')\n",
    ),
  );
  const upload = step("Upload the verdict reads for the next run");
  assert.match(upload, /uses: actions\/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 /);
  assert.ok(upload.includes("name: pr-merge-run-cache\n") && upload.includes(`path: ${carried}\n`));
  assert.ok(upload.includes("retention-days: 1\n"));
  assert.match(upload, /\n {8}if: always\(\) && steps\.carry\.outputs\.carried == 'true'\n/);
  for (const name of ["Keep the verdict reads that never change", "Upload the verdict reads for the next run"]) {
    assert.match(step(name), /\n {8}continue-on-error: true\n/, name);
  }
});

// The merge gate reads no lane verdict, so enable-auto-merge's reader is the
// only one that fills run-record: a scheduled or hand-started run keeps its
// reads as the merge job does and uploads them under a name of their own, and
// only when it kept one, so an empty file never hides an older one.
test("enable-auto-merge uploads its verifier reads for the next run", () => {
  const list = stepsOf(jobBlock("enable-auto-merge"));
  const carried = "${{ runner.temp }}/pr-merge-carried.json";
  const names = list.map((s) => s.name);
  const order = ["Arm and disarm auto-merge", "Keep the verdict reads that never change", "Upload the verdict reads for the next run"].map(
    (name) => names.indexOf(name),
  );
  assert.ok(order.every((i, n) => i >= 0 && (n === 0 || i > order[n - 1])), String(order));
  const keep = step("Keep the verdict reads that never change", list);
  assert.match(keep, /\n {8}id: carry\n/);
  assert.ok(keep.includes(`CARRY_FROM: \${{ runner.temp }}/babysit-run-cache.json\n`) && keep.includes(`CARRY_TO: ${carried}\n`));
  assert.ok(
    keep.includes(
      "always() && steps.arm.outcome != 'skipped'\n          && (github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')\n",
    ),
  );
  assert.match(keep, /run: node \.base\/\.github\/scripts\/pr-merge\/carry-run-cache\.mjs\n/);
  const upload = step("Upload the verdict reads for the next run", list);
  assert.match(upload, /uses: actions\/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 /);
  assert.ok(upload.includes("name: pr-merge-verify-run-cache\n") && upload.includes(`path: ${carried}\n`));
  assert.ok(upload.includes("retention-days: 1\n"));
  assert.match(upload, /\n {8}if: always\(\) && steps\.carry\.outputs\.kept == 'true'\n/);
  for (const block of [keep, upload]) assert.match(block, /\n {8}continue-on-error: true\n/);
});

// The head-ref map (head-ref-map.mjs): read before the gate from the last
// trusted run's artifact, written after it from the gate's own files, and
// uploaded as this run's artifact by scheduled and hand-started runs only,
// the runs a later read accepts. It never goes through actions/cache.
test("the gate reads the head-ref map the last run uploaded and uploads the next", () => {
  const names = steps.map((s) => s.name);
  const order = [
    "Read the head refs the last run kept",
    "Run the merge gate on each candidate",
    "Keep the head refs the gate read",
    "Upload them for the next run",
  ].map((name) => names.indexOf(name));
  assert.ok(order.every((i, n) => i >= 0 && (n === 0 || i > order[n - 1])), String(order));
  const mapIn = "${{ runner.temp }}/head-refs-in.json";
  const mapOut = "${{ runner.temp }}/head-refs/head-refs.json";
  const read = step("Read the head refs the last run kept");
  assert.match(read, /run: node \.base\/\.github\/scripts\/pr-merge\/head-ref-map\.mjs read\n/);
  assert.ok(read.includes(`HEAD_REFS_PATH: ${mapIn}\n`) && read.includes("ACTIONS_TOKEN: ${{ github.token }}\n"));
  const gate = step("Run the merge gate on each candidate");
  assert.ok(gate.includes(`BABYSIT_VERIFY_HEAD_REFS: ${mapIn}\n`));
  const keep = step("Keep the head refs the gate read");
  assert.match(keep, /head-ref-map\.mjs write\n/);
  for (const line of [
    `HEAD_REFS_PATH: ${mapIn}`,
    "BABYSIT_RUN_CACHE: ${{ runner.temp }}/babysit-run-cache.json",
    "BABYSIT_VERIFY_LISTING: ${{ runner.temp }}/verify-listing.json",
    `HEAD_REFS_OUT: ${mapOut}`,
  ]) {
    assert.ok(keep.includes(`${line}\n`), line);
    if (!line.startsWith("HEAD_REFS")) assert.ok(gate.includes(`${line}\n`), line);
  }
  assert.ok(
    keep.includes(
      "always() && steps.gate.outcome != 'skipped'\n          && (github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')\n",
    ),
  );
  const upload = step("Upload them for the next run");
  assert.match(upload, /uses: actions\/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 /);
  assert.ok(upload.includes("name: pr-merge-head-refs\n") && upload.includes(`path: ${mapOut}\n`));
  assert.match(upload, /\n {8}if: always\(\) && steps\.head-refs\.outcome == 'success'\n/);
  for (const name of ["Read the head refs the last run kept", "Keep the head refs the gate read", "Upload them for the next run"]) {
    assert.match(step(name), /\n {8}continue-on-error: true\n/, name);
  }
  for (const s of steps.filter((s) => s.block.includes("actions/cache/"))) {
    assert.ok(!s.block.includes("head-refs"), s.name);
  }
});

// The lane records (lane-records.mjs): read before every post-merge check,
// the gate's included, from the last trusted run's artifact; written after
// the gate and uploaded by scheduled and hand-started runs of the merge job
// only, the runs a later read accepts; never through actions/cache.
test("every post-merge check reads the lane records, and only the merge job uploads them", () => {
  const file = "${{ runner.temp }}/lane-records.json";
  const out = "${{ runner.temp }}/lane-records/lane-records.json";
  const early = stepsOf(jobBlock("post-merge-dispatch"));
  for (const list of [steps, early]) {
    const names = list.map((s) => s.name);
    const read = step("Read the lane records the last run kept", list);
    assert.ok(names.indexOf("Read the lane records the last run kept") < names.indexOf("Check earlier lane merges"));
    assert.match(read, /run: node \.base\/\.github\/scripts\/pr-merge\/lane-records\.mjs read\n/);
    assert.ok(read.includes(`LANE_RECORDS_PATH: ${file}\n`) && read.includes("ACTIONS_TOKEN: ${{ github.token }}\n"));
    assert.match(read, /\n {8}continue-on-error: true\n/);
    assert.ok(step("Check earlier lane merges", list).includes(`BABYSIT_POSTMERGE_LANE_RECORDS: ${file}\n`));
  }
  for (const name of ["Record a failed lane merge", "Run the merge gate on each candidate"]) {
    assert.ok(step(name).includes(`BABYSIT_POSTMERGE_LANE_RECORDS: ${file}\n`), name);
  }
  const names = steps.map((s) => s.name);
  const keep = step("Keep the lane records the checks proved");
  assert.ok(names.indexOf("Run the merge gate on each candidate") < names.indexOf("Keep the lane records the checks proved"));
  assert.match(keep, /lane-records\.mjs write\n/);
  for (const line of [`LANE_RECORDS_PATH: ${file}`, "BABYSIT_VERIFY_LISTING: ${{ runner.temp }}/verify-listing.json", `LANE_RECORDS_OUT: ${out}`]) {
    assert.ok(keep.includes(`${line}\n`), line);
  }
  assert.ok(
    keep.includes(
      "always() && steps.post-merge.outcome != 'skipped'\n          && (github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')\n",
    ),
  );
  const upload = step("Upload the lane records for the next run");
  assert.match(upload, /uses: actions\/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 /);
  assert.ok(upload.includes("name: pr-merge-lane-records\n") && upload.includes(`path: ${out}\n`));
  assert.match(upload, /\n {8}if: always\(\) && steps\.lane-records\.outcome == 'success'\n/);
  assert.doesNotMatch(jobBlock("post-merge-dispatch"), /name: pr-merge-lane-records|lane-records\.mjs write/);
  for (const s of steps.filter((s) => s.block.includes("actions/cache/"))) {
    assert.ok(!s.block.includes("lane-records"), s.name);
  }
});

// Runs the early job's check against a fake python3 that prints a report and
// exits `code`.
const runEarlyCheck = (code, needsDispatch = false, stops) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-early-"));
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", [bin]);
    if (stops !== undefined) {
      mkdirSync(join(dir, "api-budget"));
      writeFileSync(join(dir, "api-budget", "stop"), stops);
    }
    writeFileSync(join(bin, "python3"), `#!/usr/bin/env bash\necho '{"needsDispatch": ${needsDispatch}}'\nexit ${code}\n`);
    chmodSync(join(bin, "python3"), 0o755);
    symlinkSync(root, join(dir, ".base"));
    const output = join(dir, "output");
    const script = runScript("Check earlier lane merges", stepsOf(jobBlock("post-merge-dispatch")));
    const result = spawnSync("bash", ["-c", script], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, GITHUB_OUTPUT: output, REPO: "o/r" },
    });
    const keptCode = join(dir, "post-merge-report", "post-merge-code");
    return {
      status: result.status,
      stdout: result.stdout,
      output: readFileSync(output, "utf8"),
      keptCode: existsSync(keptCode) ? readFileSync(keptCode, "utf8").trim() : null,
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

// The owner's rule: a rate-limit stop (babysit_gh.py exits 75) turns the job
// red, and nothing after it calls the stopped pool. The outputs and the kept
// report are written first, so the dispatch reads needs-dispatch=false.
test("the early check fails red on a rate-limit stop, after its outputs and report", () => {
  const run = runEarlyCheck(75, true);
  assert.notEqual(run.status, 0, run.stdout);
  assert.match(run.stdout, /^::error::the post-merge check stopped on a GitHub rate limit/m);
  assert.match(run.output, /^needs-dispatch=false$/m);
  assert.match(run.output, /^code=75$/m);
  assert.equal(run.keptCode, "75");
});

// The stop the check recorded in the job's stop file (babysit_gh.py
// _record_stop) goes to the next jobs as the rate-limited output, naming the
// pool and its reset, every line folded by the readers' rule:
// 4102444800 is 2100-01-01T00:00:00Z, 4102448400 an hour later.
test("the early check names the stopped pool and its reset in its rate-limited output", () => {
  // The later of two pools' stops, whatever the line order.
  const core = runEarlyCheck(75, false, "core 4102448400\ngraphql 4102444800\ncore 4102444800\n");
  assert.match(core.output, /^rate-limited=the core pool until 2100-01-01T01:00:00Z$/m);
  // A * stop wins the name, and the time is the latest stop's.
  assert.match(runEarlyCheck(75, false, "core 4102448400\n* 4102444800\n").output, /^rate-limited=every pool until 2100-01-01T01:00:00Z$/m);
  // A CRLF line, a torn last line and a past stop count for nothing.
  const torn = runEarlyCheck(75, false, "graphql 4102448400\r\ncore 1\nsearch 4102444800\ncore 41024");
  assert.match(torn.output, /^rate-limited=the search pool until 2100-01-01T00:00:00Z$/m);
  // No readable stop still stops the next jobs.
  assert.match(runEarlyCheck(75).output, /^rate-limited=an unrecorded pool until its reset$/m);
  for (const code of [0, 1, 3]) {
    assert.doesNotMatch(runEarlyCheck(code, false, "core 4102444800\n").output, /rate-limited=/);
  }
});

// The label's time is the latest stop api-budget.bash reads for any pool,
// pinned to every stop_files vector the shell and Node readers share.
test("the rate-stop label's time is the latest stop of every stop_files vector", () => {
  const vectors = JSON.parse(readFileSync(join(root, ".github/actions/log-api-budget/rate-guard.vectors.json"), "utf8"));
  for (const vector of vectors.stop_files) {
    const dir = mkdtempSync(join(tmpdir(), "pr-merge-stop-label-"));
    try {
      mkdirSync(join(dir, "api-budget"));
      writeFileSync(join(dir, "api-budget", "stop"), vector.text);
      const script =
        `. ${join(root, ".github/actions/log-api-budget/api-budget.bash")}\n. ${join(root, ".github/scripts/pr-merge/rate-stop.bash")}\n` +
        `date() { echo ${vectors.vector_now}; }\nrate_stop_label\n`;
      const result = spawnSync("bash", ["-c", script], { encoding: "utf8", env: { ...process.env, RUNNER_TEMP: dir } });
      const times = Object.values(vector.until).filter((t) => t !== null);
      const want = times.length ? new Date(Math.max(...times) * 1000).toISOString().replace(".000Z", "Z") : "";
      assert.equal(result.stdout.trim().replace(/^.* until /, ""), want, vector.name);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

// Owner rule: stop calling a pool once rate-limited until reset. The merge
// and enable-auto-merge jobs read on the same GITHUB_TOKEN, so a stop in
// post-merge-dispatch ends each before its first step that could call GitHub,
// red, naming the pool.
for (const id of ["merge", "enable-auto-merge"]) {
  test(`${id} sends nothing and ends red when post-merge-dispatch stopped on a rate limit`, () => {
    const list = stepsOf(jobBlock(id));
    const first = list[0];
    assert.equal(first.name, "Stop on post-merge-dispatch's rate limit");
    assert.match(first.block, /\n {8}if: needs\.post-merge-dispatch\.outputs\.rate-limited != ''\n/);
    assert.match(first.block, /\n {10}STOP: \$\{\{ needs\.post-merge-dispatch\.outputs\.rate-limited \}\}\n/);
    const result = spawnSync("bash", ["-c", runScript(first.name, list)], {
      encoding: "utf8",
      env: { ...process.env, STOP: "the core pool until 2026-10-24T19:00:00Z" },
    });
    assert.equal(result.status, 1);
    assert.match(result.stdout, /^::error title=GitHub rate limit::post-merge-dispatch stopped on a GitHub rate limit \(the core pool until 2026-10-24T19:00:00Z\); this job sends nothing to GitHub$/m);
    // With the stop step failed, every later step is skipped: each one's
    // `if:` is evaluated with the earlier steps skipped and their outputs
    // empty, for every event the job runs on.
    for (const event of ["schedule", "workflow_dispatch", "pull_request_target", "workflow_run", "issues"]) {
      const context = (path) => {
        if (path === "github.event_name") return event;
        if (path === "github.ref") return "refs/heads/main";
        if (path === "needs.post-merge-dispatch.result") return "failure";
        if (path === "needs.post-merge-dispatch.outputs.rate-limited") return "the core pool until 2100-01-01T00:00:00Z";
        if (/^steps\.[^.]+\.(outcome|conclusion)$/.test(path)) return "skipped";
        return "";
      };
      assert.equal(stepRuns(first.block, context, "success"), true, `${id} ${event}: the stop step runs`);
      for (const { name, block } of list.slice(1)) {
        assert.equal(stepRuns(block, context, "failure"), false, `${id} ${event}: ${name} runs after the stop`);
      }
    }
  });
}

// Whether a step runs: its `if:` (no status function means `success() &&`)
// over GitHub's expression grammar as these jobs use it, with the job's
// status so far. Context paths resolve through `context`.
// https://docs.github.com/en/actions/reference/workflows-and-actions/expressions
function stepRuns(block, context, status) {
  const match = /\n {8}if: (?:>-\n((?: {10}.*\n)+)|(.*)\n)/.exec(block);
  const text = match ? (match[1] ?? match[2]).replace(/\s+/g, " ").trim().replace(/^\$\{\{(.*)\}\}$/, "$1") : "";
  const value = text ? evaluate(text, context, status) : true;
  return /\b(always|success|failure|cancelled)\(\)/.test(text) ? truthy(value) : status === "success" && truthy(value);
}
const truthy = (v) => v !== false && v !== "" && v !== null && v !== 0 && v !== undefined;
function evaluate(text, context, status) {
  const tokens = text.match(/'(?:[^']|'')*'|==|!=|&&|\|\||[!(),]|[A-Za-z_][\w.-]*|\d+/g);
  let at = 0;
  const peek = () => tokens[at];
  const take = (t) => {
    if (t !== undefined && tokens[at] !== t) throw new Error(`expected ${t} at ${tokens[at]} in ${text}`);
    return tokens[at++];
  };
  const eq = (a, b) => (typeof a === "string" && typeof b === "string" ? a.toLowerCase() === b.toLowerCase() : a === b || String(a ?? "") === String(b ?? ""));
  const fns = {
    always: () => true,
    success: () => status === "success",
    failure: () => status === "failure",
    cancelled: () => false,
    contains: (a, b) => (Array.isArray(a) ? a.some((x) => eq(x, b)) : String(a).toLowerCase().includes(String(b).toLowerCase())),
    fromJSON: (s) => JSON.parse(s),
    format: (f, ...args) => f.replace(/\{(\d+)\}/g, (_, i) => String(args[i] ?? "")),
    startsWith: (a, b) => String(a).toLowerCase().startsWith(String(b).toLowerCase()),
  };
  const primary = () => {
    const t = take();
    if (t === "!") return !truthy(primary());
    if (t === "(") {
      const v = or();
      take(")");
      return v;
    }
    if (t.startsWith("'")) return t.slice(1, -1).replace(/''/g, "'");
    if (/^\d+$/.test(t)) return Number(t);
    if (t === "true" || t === "false") return t === "true";
    if (peek() === "(") {
      take("(");
      const args = [];
      while (peek() !== ")") {
        args.push(or());
        if (peek() === ",") take(",");
      }
      take(")");
      assert.ok(fns[t], `function ${t}`);
      return fns[t](...args);
    }
    return context(t);
  };
  const compare = () => {
    let v = primary();
    while (peek() === "==" || peek() === "!=") {
      const op = take();
      const r = primary();
      v = op === "==" ? eq(v, r) : !eq(v, r);
    }
    return v;
  };
  const and = () => {
    let v = compare();
    while (peek() === "&&") {
      take();
      const r = compare();
      v = truthy(v) ? r : v;
    }
    return v;
  };
  const or = () => {
    let v = and();
    while (peek() === "||") {
      take();
      const r = and();
      v = truthy(v) ? v : r;
    }
    return v;
  };
  const v = or();
  assert.equal(at, tokens.length, `parsed all of ${text}`);
  return v;
}

test("the step-condition evaluator fails a later step that runs on empty outputs", () => {
  const context = (path) => (/\.(outcome|conclusion)$/.test(path) ? "skipped" : "");
  // The shape the old check let through: always() with a step reference that
  // is true when that step was skipped.
  assert.equal(stepRuns("\n        if: always() && steps.x.outputs.y == ''\n", context, "failure"), true);
  assert.equal(stepRuns("\n        if: always() && steps.gate.outcome != 'skipped'\n", context, "failure"), false);
  assert.equal(stepRuns("\n        if: steps.kill.outputs.proceed == 'true'\n", context, "failure"), false);
  assert.equal(stepRuns("\n        name: x\n", context, "failure"), false);
  assert.equal(stepRuns("\n        if: >-\n          !cancelled()\n          && steps.dispatch.outputs.rate-limited != 'true'\n", context, "failure"), true);
});

test("the early check warns when it cannot judge, and stays quiet on a verdict", () => {
  for (const code of [2, 3, 4]) {
    const run = runEarlyCheck(code);
    assert.equal(run.status, 0);
    assert.match(run.stdout, new RegExp(`^::warning::the post-merge check exited ${code} `, "m"));
    assert.match(run.output, /^needs-dispatch=false$/m);
  }
  for (const code of [0, 1, 5]) {
    assert.doesNotMatch(runEarlyCheck(code).stdout, /::warning::/);
  }
});

test("the early job can read the demotion records its floor depends on", () => {
  assert.match(jobBlock("post-merge-dispatch"), /\n {6}issues: read /);
});

test("the summary does not call a full run unneeded when only the gate's dispatch is read", () => {
  const summary = step("Write the summary");
  assert.match(summary, /WANTS_DISPATCH: \$\{\{ steps\.gate\.outputs\.dispatch == 'true' \}\}/);
  assert.doesNotMatch(summary, /not needed/);
  assert.match(summary, /earlier lane merges are the post-merge-dispatch job's/);
});

// Runs the gate step with a fake gate whose second candidate kills the loop,
// as a cancelled run would stop it mid-sweep.
const runCancelledGate = () => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-gate-"));
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", ["-p", bin, join(dir, ".base")]);
    writeFileSync(join(bin, "gh"), `#!/usr/bin/env bash\necho "5000/5000 reset=1"\n`);
    writeFileSync(
      join(dir, ".base", "gate"),
      `#!/usr/bin/env bash\ncase "\${@: -1}" in *#2) kill -9 $PPID ;; esac\n` +
        `echo '{"ready": false, "blockers": ["x"], "unattended": {"reason": "verify:missing"}}'\nexit 10\n`,
    );
    chmodSync(join(bin, "gh"), 0o755);
    chmodSync(join(dir, ".base", "gate"), 0o755);
    writeFileSync(join(dir, "resolved-config.json"), '{"selected": {"args": ""}}');
    writeFileSync(join(dir, "held.json"), '[{"number": 9, "head": "c", "updatedAt": "u", "reason": "label"}]');
    writeFileSync(
      join(dir, "candidates.json"),
      '[{"number": 1, "head": "a", "updatedAt": "u"}, {"number": 2, "head": "b", "updatedAt": "u"}]',
    );
    spawnSync("bash", ["-c", runScript("Run the merge gate on each candidate")], {
      cwd: dir,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        RUNNER_TEMP: dir,
        GITHUB_OUTPUT: join(dir, "output"),
        GITHUB_STEP_SUMMARY: join(dir, "step-summary"),
        SCRIPT: "gate",
        BABYSIT_VERIFY_GH_TOKEN: "t",
        KILL_SWITCH: "proceed",
        RUNG_CAP: "",
        REPO: "o/r",
        OWNER: "o",
      },
    });
    const summary = join(dir, "pr-merge-summary.json");
    return existsSync(summary) ? JSON.parse(readFileSync(summary, "utf8")) : null;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

test("a sweep stopped mid-loop keeps the verdicts it reached in the summary", () => {
  const summary = runCancelledGate();
  assert.ok(summary, "pr-merge-summary.json written before the loop ended");
  assert.deepEqual(
    summary.map((row) => [row.pr, row.reason]),
    [
      [9, "prefilter:label"],
      [1, "verify:missing"],
    ],
  );
});

// A failed lane merge holds the gate until a human closes its demotion
// record, and only a `--remediate` run under the lanes App files one (pr-merge
// run 39201629405 refused every candidate on a failure with no record).
test("a failed lane merge reruns the check with --remediate under the lane token", () => {
  const names = steps.map((s) => s.name);
  const check = names.indexOf("Check earlier lane merges");
  const record = names.indexOf("Record a failed lane merge");
  assert.ok(check >= 0 && record === check + 1, "the record step follows the check");
  assert.ok(record < names.indexOf("Run the merge gate on each candidate"));
  const block = step("Record a failed lane merge");
  assert.match(block, /\n {8}if: steps\.mode\.outputs\.live == 'true' && steps\.post-merge\.outputs\.code == '1'\n/);
  assert.match(block, /\n {10}GH_TOKEN: \$\{\{ steps\.lane-token\.outputs\.token \}\}\n/);
  assert.match(runScript("Check earlier lane merges"), /^echo "code=\$code" >>"\$GITHUB_OUTPUT"$/m);
});

// Only --remediate writes, so it alone takes the lane token. The read-only
// check and the gate's evidence reads spend the job's own token, which this
// job grants no write.
test("the read-only post-merge check and the gate's reads use the job's read-only token", () => {
  assert.match(step("Check earlier lane merges"), /\n {10}GH_TOKEN: \$\{\{ github\.token \}\}\n/);
  assert.doesNotMatch(runScript("Check earlier lane merges"), /--remediate/);
  assert.match(step("Record a failed lane merge"), /\n {10}GH_TOKEN: \$\{\{ steps\.lane-token\.outputs\.token \}\}\n/);
  const gate = step("Run the merge gate on each candidate");
  assert.match(gate, /\n {10}GH_TOKEN: \$\{\{ steps\.lane-token\.outputs\.token \}\}\n/);
  assert.match(gate, /\n {10}BABYSIT_VERIFY_GH_TOKEN: \$\{\{ github\.token \}\}\n/);
  const permissions = /\n    permissions:\n([\s\S]*?)\n    [a-z-]+:/.exec(job)[1];
  const grants = [...permissions.matchAll(/^ {6}([a-z-]+): ([a-z]+)/gm)].map((m) => `${m[1]}: ${m[2]}`);
  assert.deepEqual(grants.filter((g) => g.endsWith(": write")), ["id-token: write"]);
  assert.ok(grants.includes("issues: read"), grants.join(", "));
});

// Runs the record step against a fake python3 that saves its arguments,
// prints `report` and exits `code`.
const runRecord = (code, report = { remediation: { errors: [] } }) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-record-"));
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", [bin]);
    writeFileSync(join(bin, "python3"), `#!/usr/bin/env bash\nprintf '%s\\n' "$@" >"${dir}/args"\ncat <<'EOF'\n${JSON.stringify(report)}\nEOF\nexit ${code}\n`);
    chmodSync(join(bin, "python3"), 0o755);
    symlinkSync(root, join(dir, ".base"));
    const result = spawnSync("bash", ["-c", runScript("Record a failed lane merge")], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, REPO: "o/r" },
    });
    return { status: result.status, stdout: result.stdout, args: readFileSync(join(dir, "args"), "utf8").split("\n") };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

test("the record step passes --remediate and is quiet when the record was filed", () => {
  const run = runRecord(1);
  assert.equal(run.status, 0);
  assert.ok(run.args.includes("--remediate"), run.args.join(" "));
  assert.ok(run.args.includes("--lane-merges-only"));
  assert.equal(run.args[run.args.indexOf("--agent-identity") + 1], "melodic-automation-lanes[bot]");
  assert.doesNotMatch(run.stdout, /::(warning|error)::/);
});

// Exit 4 covers both the expected re-run and dispatch refusals and a failed
// filing, so only the report's errors tell them apart.
test("the record step warns on refused re-runs and errors when the record was not filed", () => {
  const refused = runRecord(4, { remediation: { errors: ["re-run: HTTP 403", "dispatch: HTTP 403"] } });
  assert.equal(refused.status, 0);
  assert.match(refused.stdout, /^::warning::the post-merge remediation exited 4 /m);
  assert.doesNotMatch(refused.stdout, /::error::/);
  for (const error of ["demotion issue: HTTP 403", "dequeue: HTTP 502", "disarm: HTTP 502"]) {
    const failed = runRecord(4, { remediation: { errors: ["re-run: HTTP 403", error] } });
    assert.equal(failed.status, 0);
    assert.match(failed.stdout, /^::error::the post-merge remediation could not file the demotion record/m);
  }
  for (const code of [1, 2, 3]) {
    const crashed = runRecord(code, { reason: "unreadable" });
    assert.equal(crashed.status, 0);
    assert.match(crashed.stdout, new RegExp(`^::error::the post-merge remediation exited ${code} with no remediation report`, "m"));
  }
});

// Runs the gate step over three candidates with a fake clock: `date +%s`
// answers each value of `clock` in turn (the first is the loop's start), and
// `skipped` as the skip step's file when given. `gate` replaces the fake
// gate's body, and `candidateMinutes` is merge.gate-candidate-minutes.
const REFUSING_GATE = `echo '{"ready": false, "blockers": ["x"], "unattended": {"reason": "verify:missing"}}'\nexit 10\n`;
const runBudgetedGate = (
  budget,
  clock,
  skipped,
  {
    gate = REFUSING_GATE,
    candidateMinutes = "",
    deferredMinutes = "",
    candidates = [7, 3, 5].map((number) => ({ number, head: `h${number}`, updatedAt: "u" })),
  } = {},
) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-budget-"));
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", ["-p", bin, join(dir, ".base")]);
    writeFileSync(join(bin, "gh"), `#!/usr/bin/env bash\necho "5000/5000 reset=1"\n`);
    writeFileSync(
      join(bin, "date"),
      `#!/usr/bin/env bash\nn=$(($(cat "${dir}/ticks" 2>/dev/null || echo 0) + 1))\necho "$n" >"${dir}/ticks"\n` +
        `t=(${clock.join(" ")})\necho "\${t[$((n - 1))]:-\${t[-1]}}"\n`,
    );
    writeFileSync(
      join(dir, ".base", "gate"),
      `#!/usr/bin/env bash\necho "\${@: -1}" >>"${dir}/gated"\necho "$*" >>"${dir}/argv"\n` + gate,
    );
    for (const file of [join(bin, "gh"), join(bin, "date"), join(dir, ".base", "gate")]) chmodSync(file, 0o755);
    writeFileSync(join(dir, "resolved-config.json"), '{"selected": {"args": ""}}');
    writeFileSync(join(dir, "held.json"), "[]");
    writeFileSync(join(dir, "candidates.json"), JSON.stringify(candidates));
    if (skipped !== undefined) writeFileSync(join(dir, "skipped.json"), skipped);
    const result = spawnSync("bash", ["-c", runScript("Run the merge gate on each candidate")], {
      cwd: dir,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        RUNNER_TEMP: dir,
        GITHUB_OUTPUT: join(dir, "output"),
        GITHUB_STEP_SUMMARY: join(dir, "step-summary"),
        SCRIPT: "gate",
        BABYSIT_VERIFY_GH_TOKEN: "t",
        KILL_SWITCH: "proceed",
        RUNG_CAP: "",
        REPO: "o/r",
        OWNER: "o",
        BUDGET_MINUTES: budget,
        CANDIDATE_MINUTES: candidateMinutes,
        DEFERRED_MINUTES: deferredMinutes,
      },
    });
    const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
    return {
      status: result.status,
      stdout: result.stdout,
      stderr: result.stderr,
      gated: read("gated").split("\n").filter(Boolean),
      argv: read("argv").split("\n").filter(Boolean),
      cursor: read("gate-cursor/cursor.json"),
      stepSummary: read("step-summary"),
      summary: JSON.parse(read("pr-merge-summary.json") || "null"),
      output: read("output"),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

test("the gate starts no candidate once the budget is used and records where it stopped", () => {
  // Start at 0; the second candidate starts at 30 s, the third would at 60 s.
  const run = runBudgetedGate("1", [0, 0, 30, 60]);
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(run.gated, ["o/r#7", "o/r#3"]);
  assert.deepEqual(JSON.parse(run.cursor), { last: 3 });
  assert.deepEqual(
    run.summary.map((row) => row.pr),
    [7, 3],
  );
  assert.match(run.stdout, /^::notice::the 1-minute gate budget is used after 2 of 3 candidates; the next run starts after #3$/m);
  assert.match(run.stepSummary, /^budget-stop: /m);
});

test("with no budget, or an unreadable one, the gate checks every candidate", () => {
  for (const budget of ["", "ten"]) {
    const run = runBudgetedGate(budget, [0, 0, 9999, 99999]);
    assert.equal(run.status, 0, run.stderr);
    assert.deepEqual(run.gated, ["o/r#7", "o/r#3", "o/r#5"]);
    assert.deepEqual(JSON.parse(run.cursor), { last: 5 });
    assert.doesNotMatch(run.stepSummary, /budget-stop/);
    assert.equal(/::warning::merge\.gate-budget-minutes/.test(run.stdout), budget === "ten");
  }
});

test("a candidate stopped at its read limit is reported unknown, never ready, and the next candidate is gated", () => {
  // The first candidate's gate stops at its limit as babysit_merge.py does.
  const gate =
    `if [[ $* == *'#7' ]]; then echo '{"pr": "o/r#7", "error": "unknown:candidate-deadline; stopped"}'; exit 11; fi\n` + REFUSING_GATE;
  const run = runBudgetedGate("10", [0, 0, 1, 2], undefined, { gate, candidateMinutes: "4" });
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(run.gated, ["o/r#7", "o/r#3", "o/r#5"]);
  assert.ok(run.argv.every((line) => line.includes("--candidate-deadline-seconds 240 ")), run.argv.join("\n"));
  assert.deepEqual(
    run.summary.map((row) => [row.pr, row.exit, row.ready, row.enqueued, row.reason]),
    [
      [7, 11, false, false, "unknown:candidate-deadline; stopped"],
      [3, 10, false, false, "verify:missing"],
      [5, 10, false, false, "verify:missing"],
    ],
  );
  assert.deepEqual(JSON.parse(run.cursor), { last: 5, deferred: 7 });
});

// Owner rule: stop calling a pool once rate-limited until reset. After the
// gate stops on one (exit 75), no later step of the job calls GitHub, nor the
// gate-check job, whose own stop file would not hold the stop.
test("after the gate's rate-limit stop, no later merge-job step calls GitHub", () => {
  const gate = `if [[ $* == *'#7' ]]; then echo '{"error": "rate limited"}'; exit 75; fi\n` + REFUSING_GATE;
  const run = runBudgetedGate("", [0, 0, 1, 2], undefined, { gate });
  assert.equal(run.status, 1, run.stderr);
  assert.deepEqual(run.gated, ["o/r#7"]);
  assert.match(run.output, /^rate-limited=true$/m);
  for (const limited of ["true", ""]) {
    const context = (path) => {
      if (path === "github.event_name") return "schedule";
      if (path === "steps.gate.outcome") return "failure";
      if (path === "steps.gate.outputs.rate-limited") return limited;
      if (path === "steps.lane-token.outputs.token") return "t";
      if (path === "steps.mode.outputs.report-only") return "false";
      return "";
    };
    for (const name of ["Hand the gate's rows to the check writer", "Re-fire lane runs refused as workflow-modified", "Clear escalations whose reason no longer holds"]) {
      assert.equal(stepRuns(step(name), context, "failure"), limited !== "true", `${name} with rate-limited=${limited}`);
    }
  }
  // The refusal count still writes its summary, with no read of the run.
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-count-"));
  try {
    const bin = join(dir, "bin");
    mkdirSync(bin);
    writeFileSync(join(bin, "gh"), `#!/usr/bin/env bash\necho "$*" >>"${dir}/gh"\necho 2026-10-26T00:00:00Z\n`);
    writeFileSync(join(bin, "node"), `#!/usr/bin/env bash\necho "RUN_STARTED_AT=$RUN_STARTED_AT" >"${dir}/node"\n`);
    for (const file of ["gh", "node"]) chmodSync(join(bin, file), 0o755);
    const sweep = join(dir, "sweep.json");
    writeFileSync(sweep, '{"refusal_counts": {}}');
    for (const limited of ["true", ""]) {
      rmSync(join(dir, "gh"), { force: true });
      const result = spawnSync("bash", ["-c", runScript("Count the sweep's refusals")], {
        cwd: dir,
        encoding: "utf8",
        env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, LIMITED: limited, REPO: "o/r", GITHUB_RUN_ID: "1", SWEEP_SUMMARY_TO: sweep },
      });
      assert.equal(result.status, 0, result.stderr);
      assert.equal(existsSync(join(dir, "gh")), limited !== "true", `gh with LIMITED=${limited}`);
      assert.equal(readFileSync(join(dir, "node"), "utf8").trim(), `RUN_STARTED_AT=${limited === "true" ? "" : "2026-10-26T00:00:00Z"}`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// The candidates the next run's rotation.mjs orders from a cursor.
const rotateFrom = async (cursor) => {
  const { main: rotation } = await import("./rotation.mjs");
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-rotation-"));
  try {
    const path = join(dir, "candidates.json");
    writeFileSync(path, JSON.stringify([3, 5, 7].map((number) => ({ number, head: `h${number}`, updatedAt: "u" }))));
    const actions = async (_method, url) =>
      url.includes("/artifacts")
        ? { artifacts: [{ expired: false }] }
        : { workflow_runs: [{ id: 1, event: "schedule", head_branch: "main", path: ".github/workflows/pr-merge.yml" }] };
    const log = console.log;
    console.log = () => {};
    try {
      await rotation({ env: { GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "2", CANDIDATES_PATH: path }, actions, download: () => cursor });
    } finally {
      console.log = log;
    }
    return JSON.parse(readFileSync(path, "utf8"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

// #7's gate always runs past the 4-minute limit, and past the 20-minute
// ceiling too when `pastCeiling`.
const slowGate = (pastCeiling) =>
  `if [[ $* == *'--candidate-deadline-seconds 240 '*'#7' ${pastCeiling ? "|| $* == *'--candidate-deadline-seconds 1200 '*'#7' " : ""}]]; then ` +
  `echo '{"error": "unknown:candidate-deadline; stopped"}'; exit 11; fi\n` +
  REFUSING_GATE;
const limits = { candidateMinutes: "4", deferredMinutes: "20" };

test("a candidate that always passes its read limit is gated first the next run under the deferred ceiling", async () => {
  const gate = slowGate(false);
  const first = runBudgetedGate("", [0, 0, 1, 2], undefined, { gate, ...limits });
  assert.equal(first.status, 0, first.stderr);
  assert.deepEqual(JSON.parse(first.cursor), { last: 5, deferred: 7 });
  assert.deepEqual(first.summary.map((row) => [row.pr, row.exit]), [[7, 11], [3, 10], [5, 10]]);
  const second = runBudgetedGate("", [0, 0, 1, 2], undefined, { gate, ...limits, candidates: await rotateFrom(first.cursor) });
  assert.equal(second.status, 0, second.stderr);
  assert.deepEqual(second.gated, ["o/r#7", "o/r#3", "o/r#5"]);
  assert.match(second.argv[0], /--candidate-deadline-seconds 1200 /);
  assert.ok(second.argv.slice(1).every((line) => line.includes("--candidate-deadline-seconds 240 ")));
  assert.deepEqual(second.summary.map((row) => [row.pr, row.exit, row.reason]), [[7, 10, "verify:missing"], [3, 10, "verify:missing"], [5, 10, "verify:missing"]]);
  assert.deepEqual(JSON.parse(second.cursor), { last: 5 });
  assert.doesNotMatch(second.stdout, /merge\.gate-deferred-minutes/);
});

test("a deferred candidate stopped at its ceiling is warned about and not deferred again", async () => {
  const gate = slowGate(true);
  const first = runBudgetedGate("", [0, 0, 1, 2], undefined, { gate, ...limits });
  const second = runBudgetedGate("", [0, 0, 1, 2], undefined, { gate, ...limits, candidates: await rotateFrom(first.cursor) });
  assert.equal(second.status, 0, second.stderr);
  assert.deepEqual(second.summary.map((row) => [row.pr, row.exit]), [[7, 11], [3, 10], [5, 10]]);
  assert.match(second.stdout, /^::warning::PR #7's gate ran past merge\.gate-deferred-minutes \(20\) after a deferral; it goes back to the capped rotation$/m);
  assert.deepEqual(JSON.parse(second.cursor), { last: 5 });
  // The run after that rotates on from #5 with #7 capped like the rest.
  const third = await rotateFrom(second.cursor);
  assert.deepEqual(third.map((c) => [c.number, c.deferred === true]), [[7, false], [3, false], [5, false]]);
});

test("with no read limit, or an unreadable one, the gate passes none", () => {
  for (const candidateMinutes of ["", "four", "0"]) {
    const run = runBudgetedGate("", [0, 0, 1, 2], undefined, { candidateMinutes });
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.argv.length, 3);
    assert.ok(run.argv.every((line) => !line.includes("--candidate-deadline-seconds")));
    assert.equal(/::warning::merge\.gate-candidate-minutes/.test(run.stdout), candidateMinutes !== "");
  }
});

test("a skipped candidate's carried refusal is reported once, and one still listed is gated", () => {
  const carried = (pr) => ({ pr, head: `h${pr}`, updatedAt: "u", exit: 10, reason: "risk:MED", carried: { skips: 1 } });
  const run = runBudgetedGate("", [0, 0, 1, 2], JSON.stringify([carried(4), carried(7)]));
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(run.gated, ["o/r#7", "o/r#3", "o/r#5"]);
  assert.deepEqual(
    run.summary.map((row) => [row.pr, row.reason, "carried" in row]),
    [
      [4, "risk:MED", true],
      [7, "verify:missing", false],
      [3, "verify:missing", false],
      [5, "verify:missing", false],
    ],
  );
});

test("a missing or malformed skip file adds no row and the gate still runs", () => {
  for (const skipped of [undefined, "not json"]) {
    const run = runBudgetedGate("", [0, 0, 1, 2], skipped);
    assert.equal(run.status, 0, run.stderr);
    assert.deepEqual(run.gated, ["o/r#7", "o/r#3", "o/r#5"]);
    assert.deepEqual(run.summary.map((row) => row.pr), [7, 3, 5]);
  }
});

test("the skip step runs just before the gate and its record between the carry and the upload, neither able to fail the job", () => {
  const names = steps.map((s) => s.name);
  const at = (name) => names.indexOf(name);
  assert.equal(at("Skip refusals whose inputs have not changed"), at("Run the merge gate on each candidate") - 1);
  assert.ok(at("Record a failed lane merge") < at("Skip refusals whose inputs have not changed"));
  assert.equal(at("Keep the refusals the next run may skip"), at("Keep the verdict reads that never change") + 1);
  assert.equal(at("Upload the verdict reads for the next run"), at("Keep the refusals the next run may skip") + 1);
  const filter = step("Skip refusals whose inputs have not changed");
  assert.match(filter, /\n {8}continue-on-error: true\n/);
  assert.match(filter, /\n {8}if: steps\.candidates\.outcome == 'success'\n/);
  assert.match(filter, /GH_TOKEN: \$\{\{ steps\.lane-token\.outputs\.token \}\}/);
  assert.match(filter, /BABYSIT_VERIFY_GH_TOKEN: \$\{\{ github\.token \}\}/);
  // The listing it reads is saved where the gate's first candidate looks.
  const listing = "BABYSIT_VERIFY_LISTING: ${{ runner.temp }}/verify-listing.json\n";
  assert.ok(filter.includes(listing) && step("Run the merge gate on each candidate").includes(listing));
  assert.match(filter, /babysit_merge_skip\.py filter /);
  assert.match(filter, /--store "\$RUNNER_TEMP\/pr-merge-carried\.json"/);
  assert.match(filter, /MAX_MINUTES: \$\{\{ steps\.mode\.outputs\.skip-max-minutes \}\}/);
  assert.match(filter, /MAX_SKIPS: \$\{\{ steps\.mode\.outputs\.skip-max-skips \}\}/);
  assert.match(step("Read report-only"), /echo "skip-max-minutes=\$\(yq '\.merge\."skip-unchanged"\."max-minutes" \/\/ ""' "\$config"\)"/);
  assert.match(step("Read report-only"), /echo "skip-max-skips=\$\(yq '\.merge\."skip-unchanged"\."max-skips" \/\/ ""' "\$config"\)"/);
  const record = step("Keep the refusals the next run may skip");
  assert.match(record, /\n {8}if: always\(\) && steps\.carry\.outputs\.carried == 'true'\n/);
  assert.match(record, /\n {8}continue-on-error: true\n/);
  assert.match(record, /babysit_merge_skip\.py record /);
  assert.match(record, /--store "\$RUNNER_TEMP\/pr-merge-carried\.json"/);
});

test("the budget comes from the pipeline config, rotation runs before the gate, and the upload step runs under always()", () => {
  assert.match(step("Read report-only"), /echo "gate-budget-minutes=\$\(yq '\.merge\."gate-budget-minutes" \/\/ ""' "\$config"\)"/);
  assert.match(step("Run the merge gate on each candidate"), /BUDGET_MINUTES: \$\{\{ steps\.mode\.outputs\.gate-budget-minutes \}\}/);
  assert.match(step("Read report-only"), /echo "gate-candidate-minutes=\$\(yq '\.merge\."gate-candidate-minutes" \/\/ ""' "\$config"\)"/);
  assert.match(step("Run the merge gate on each candidate"), /CANDIDATE_MINUTES: \$\{\{ steps\.mode\.outputs\.gate-candidate-minutes \}\}/);
  assert.match(step("Read report-only"), /echo "gate-deferred-minutes=\$\(yq '\.merge\."gate-deferred-minutes" \/\/ ""' "\$config"\)"/);
  assert.match(step("Run the merge gate on each candidate"), /DEFERRED_MINUTES: \$\{\{ steps\.mode\.outputs\.gate-deferred-minutes \}\}/);
  const names = steps.map((s) => s.name);
  const rotation = names.indexOf("Start after the candidate the last run reached");
  const gate = names.indexOf("Run the merge gate on each candidate");
  const record = names.indexOf("Record where the gate stopped");
  assert.ok(names.indexOf("List the candidate PRs") < rotation && rotation < gate && gate < record);
  assert.match(step("Start after the candidate the last run reached"), /\n {8}continue-on-error: true\n/);
  const upload = step("Record where the gate stopped");
  assert.match(upload, /\n {8}if: always\(\) && steps\.gate\.outcome != 'skipped'\n/);
  assert.match(upload, /uses: actions\/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 /);
  assert.match(upload, /\n {10}name: pr-merge-gate-cursor\n/);
});

// The main ruleset requires `ci-status` from the GitHub Actions app, the app
// every GITHUB_TOKEN posts as, so a token with checks: write could pass it.
// Only a job of its own, running nothing but the check writer, holds it.
test("each candidate's check run is written by its own job, the only one holding checks: write", () => {
  assert.match(job, /\n {6}checks: read\n/);
  assert.equal(text.match(/\n {6}checks: write\n/g)?.length, 1);
  const upload = step("Hand the gate's rows to the check writer");
  assert.ok(steps.findIndex((s) => s.name === "Run the merge gate on each candidate") < steps.findIndex((s) => s.name === "Hand the gate's rows to the check writer"));
  assert.match(upload, /\n {8}if: >-\n {10}always\(\) && steps\.gate\.outcome != 'skipped' && steps\.mode\.outputs\.report-only == 'false'\n {10}&& steps\.gate\.outputs\.rate-limited != 'true'\n/);
  assert.match(upload, /\n {10}name: pr-merge-gate-rows\n {10}path: \$\{\{ runner\.temp \}\}\/pr-merge-summary\.json\n/);
  assert.match(job, /\n {6}gate-rows: \$\{\{ steps\.rows\.outcome == 'success' \}\}\n/);

  const writer = jobBlock("gate-check");
  assert.match(writer, /^ {4}needs: \[merge\]\n/);
  assert.match(writer, /\n {4}if: always\(\) && needs\.merge\.outputs\.gate-rows == 'true'\n/);
  assert.match(writer, /\n {4}permissions:\n {6}contents: read[^\n]*\n(?: {6}#[^\n]*\n)* {6}checks: write\n {6}pull-requests: read[^\n]*\n {4}[a-z]/);
  // Runs wait in line like the merge job's: never two writers at once, and a
  // cancelled job would sit on PR heads as a CANCELLED check.
  assert.match(writer, /\n {4}concurrency:\n {6}group: pr-merge-gate-check\n {6}queue: max\n/);
  const writerSteps = stepsOf(writer);
  assert.deepEqual(
    writerSteps.map((s) => s.name),
    ["Check out the default branch tip", "Set up Node", "Read the gate's rows", "Show each candidate's refusal as a check run"],
  );
  assert.match(writerSteps[0].block, /\n {10}ref: refs\/heads\/main\n {10}path: \.base\n {10}persist-credentials: false\n/);
  for (const { name, block } of writerSteps.slice(2)) {
    assert.match(block, /\n {8}continue-on-error: true\n/, name);
  }
  const show = writerSteps[3].block;
  assert.match(show, /\n {10}GH_TOKEN: \$\{\{ github\.token \}\}\n/);
  assert.match(show, /\n {10}SUMMARY_PATH: \$\{\{ runner\.temp \}\}\/rows\/pr-merge-summary\.json\n/);
  assert.match(show, /\n {8}run: node \.base\/\.github\/scripts\/pr-merge\/gate-check\.mjs\n/);
  assert.equal(steps.find((s) => s.name === "Show each candidate's refusal as a check run"), undefined);
});

// #8399 (option B): a red attempt 1 of a full run the lane dispatched gets its
// one re-run from the early job, under its own token, and a record the
// post-merge check requires before it credits that github-actions[bot] attempt.
const earlySteps = () => stepsOf(jobBlock("post-merge-dispatch"));

// Runs the early job's check against a fake python3 that prints `report`.
const runEarlyReport = (report) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-early-report-"));
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", [bin]);
    writeFileSync(join(bin, "python3"), `#!/usr/bin/env bash\ncat <<'EOF'\n${JSON.stringify(report)}\nEOF\nexit 5\n`);
    chmodSync(join(bin, "python3"), 0o755);
    symlinkSync(root, join(dir, ".base"));
    const output = join(dir, "output");
    spawnSync("bash", ["-c", runScript("Check earlier lane merges", earlySteps())], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, GITHUB_OUTPUT: output, REPO: "o/r" },
    });
    return readFileSync(output, "utf8");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

test("the early check names only a lane-dispatched run awaiting its re-run", () => {
  const reruns = [
    { runId: 31, signal: "schedule", laneDispatched: false },
    { runId: 11, signal: "dispatch", laneDispatched: true },
  ];
  assert.match(runEarlyReport({ reruns }), /^lane-rerun=11$/m);
  assert.match(runEarlyReport({ reruns: [reruns[0]] }), /^lane-rerun=$/m);
  assert.match(runEarlyReport({ reason: "unreadable" }), /^lane-rerun=$/m);
  // The fake check exits 5; the re-run step's gate reads it.
  assert.match(runEarlyReport({ reruns }), /^code=5$/m);
});

// Runs the re-run step against a fake gh that answers `attempts` in turn for
// the run read, failing a read whose entry is "x" (a 502) and rate-limiting
// one whose entry is "limited" (a 403 with the core pool spent until
// 2100-01-01). `post` answers the re-run POST, or each POST in turn when a
// list: "ok", "refuse" (a 403 that is no rate limit), "limited" (a 429 with a
// retry-after) or "unsent" (a TLS handshake timeout, before the request left).
// The "limited" read's stderr is RATE_LIMITED_STDERR. Like gh, with -i it
// prints the status and headers before the body, the guard's shape.
// gh's stderr for a call GitHub refused for a rate limit, as run 39906176584
// logged it (pr-merge.yml, dispatch-full-run, "Start the full CI run on main",
// 2026-10-23T05:30:57Z).
const RATE_LIMITED_STDERR =
  "gh: API rate limit exceeded for installation. If you reach out to GitHub Support for help, please include the request ID 8000:1DF2D:1EE39F:657D15:6ADAF110 and timestamp 2026-10-23 05:30:57 UTC. For more on scraping GitHub and how it may affect your rights, please review our Terms of Service (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) (HTTP 403)";
const LIMITED_403 ='HTTP/2.0 403 Forbidden\\r\\nX-Ratelimit-Remaining: 0\\r\\nX-Ratelimit-Reset: 4102444800\\r\\nX-Ratelimit-Resource: core\\r\\n\\r\\n{"message": "API rate limit exceeded for installation ID 1."}\\n';
const runRerun = (attempts, { refuse = false, post = refuse ? "refuse" : "ok", runId = "11" } = {}) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-rerun-"));
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", [bin]);
    writeFileSync(
      join(bin, "gh"),
      `#!/usr/bin/env bash\ninc=; if [ "$2" = -i ]; then inc=1; set -- "$1" "\${@:3}"; fi\n` +
        `echo "$*" >>"${dir}/calls"\n` +
        `say() { if [ -n "$inc" ]; then printf "$1"; else printf "$1" | sed '1,/^\\r\\?$/d'; fi; }\n` +
        `if [ "$3" = POST ]; then p=(${[post].flat().join(" ")}); s=$(($(cat "${dir}/posts" 2>/dev/null || echo 0) + 1)); echo "$s" >"${dir}/posts"\n` +
        `case "\${p[$((s - 1))]:-\${p[-1]}}" in\n` +
        `  ok) say 'HTTP/2.0 204 No Content\\r\\n\\r\\n'; exit 0 ;;\n` +
        `  unsent) echo 'Post "https://api.github.com/repos/o/r/actions/runs/11/rerun-failed-jobs": net/http: TLS handshake timeout' >&2; exit 1 ;;\n` +
        `  refuse) say 'HTTP/2.0 403 Forbidden\\r\\n\\r\\n{"message": "Resource not accessible by integration"}\\n'; echo "HTTP 403" >&2; exit 1 ;;\n` +
        `  limited) say 'HTTP/2.0 429 Too Many Requests\\r\\nRetry-After: 60\\r\\n\\r\\n{"message": "Too many requests"}\\n'; echo "HTTP 429" >&2; exit 1 ;;\n` +
        `esac; fi\n` +
        `n=$(($(cat "${dir}/reads" 2>/dev/null || echo 0) + 1))\necho "$n" >"${dir}/reads"\n` +
        `a=(${attempts.join(" ")})\nv="\${a[$((n - 1))]:-\${a[-1]}}"\n` +
        `if [ "$v" = x ]; then say 'HTTP/2.0 502 Bad Gateway\\r\\n\\r\\n{}\\n'; echo "HTTP 502" >&2; exit 1; fi\n` +
        `if [ "$v" = limited ]; then say '${LIMITED_403}'; echo '${RATE_LIMITED_STDERR}' >&2; exit 1; fi\n` +
        `if [ "$v" = bare429 ]; then echo "gh: Too Many Requests (HTTP 429)" >&2; exit 1; fi\n` +
        `say "HTTP/2.0 200 OK\\r\\n\\r\\n$v\\n"\n`,
    );
    writeFileSync(join(bin, "sleep"), `#!/usr/bin/env bash\necho "$1" >>"${dir}/slept"\n`);
    chmodSync(join(bin, "gh"), 0o755);
    chmodSync(join(bin, "sleep"), 0o755);
    symlinkSync(root, join(dir, ".base"));
    const output = join(dir, "output");
    const result = spawnSync("bash", ["-c", runScript("Re-run a red lane-dispatched full run", earlySteps())], {
      cwd: dir,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        RUNNER_TEMP: dir,
        GITHUB_OUTPUT: output,
        GITHUB_RUN_ID: "700",
        REPO: "o/r",
        RUN_ID: runId,
      },
    });
    const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
    return {
      status: result.status,
      stdout: result.stdout,
      calls: read("calls").split("\n").filter(Boolean),
      output: read("output"),
      record: read("rerun.json"),
      slept: read("slept").split("\n").filter(Boolean).map(Number),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

const POST = "api -X POST repos/o/r/actions/runs/11/rerun-failed-jobs";

test("the re-run step re-runs attempt 1 once and records attempt 2", () => {
  const run = runRerun([1, 1, 2]);
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(
    run.calls.filter((c) => c.includes("POST")),
    [POST],
  );
  assert.deepEqual(JSON.parse(run.record), { rerunner_run_id: 700, run_id: 11, attempt: 2 });
  assert.match(run.output, /^recorded=true$/m);
});

test("the re-run step neither re-runs nor records a run past attempt 1", () => {
  const run = runRerun([2]);
  assert.equal(run.status, 0);
  assert.deepEqual(
    run.calls.filter((c) => c.includes("POST")),
    [],
  );
  assert.equal(run.record, "");
  assert.doesNotMatch(run.output, /recorded=true/);
});

test("the re-run step records nothing when the re-run is refused or lands past attempt 2", () => {
  for (const [attempts, options] of [
    [[1], { refuse: true }],
    [[1, 3], {}],
  ]) {
    const run = runRerun(attempts, options);
    assert.equal(run.status, 0);
    assert.equal(run.record, "");
    assert.doesNotMatch(run.output, /recorded=true/);
    assert.match(run.stdout, /^::warning::/m);
  }
});

// The owner outage rule (Q677: at most three attempts, a capped full-jitter
// backoff), as the dispatch: a POST that never left is sent again; a refusal
// GitHub answered is not, since the re-run may have started.
test("a re-run POST that never left is sent again after a jittered wait, at most three times", () => {
  const run = runRerun([1, 2], { post: ["unsent", "unsent", "ok"] });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.calls.filter((c) => c.includes("POST")), [POST, POST, POST]);
  assert.ok(run.slept[0] >= 1 && run.slept[0] <= 10, `${run.slept[0]}`);
  assert.ok(run.slept[1] >= 1 && run.slept[1] <= 20, `${run.slept[1]}`);
  assert.match(run.output, /^recorded=true$/m);
  const spent = runRerun([1], { post: ["unsent"] });
  assert.equal(spent.status, 0, spent.stdout);
  assert.equal(spent.calls.filter((c) => c.includes("POST")).length, 3);
  assert.equal(spent.record, "");
  assert.match(spent.stdout, /::warning::the re-run of run 11 was refused after 3 attempt\(s\)/);
  const refused = runRerun([1], { post: ["refuse", "ok"] });
  assert.deepEqual(refused.calls.filter((c) => c.includes("POST")), [POST]);
  assert.deepEqual(refused.slept, []);
});

test("a rate limit after a re-run POST that never left still stops red, with no further send", () => {
  const run = runRerun([1], { post: ["unsent", "limited", "ok"] });
  assert.equal(run.status, 1, run.stdout);
  assert.deepEqual(run.calls.filter((c) => c.includes("POST")), [POST, POST]);
  assert.equal(run.record, "");
  assert.match(run.output, /^rate-limited=true$/m);
});

test("the re-run step rides out failed reads after the re-run and records attempt 2", () => {
  const run = runRerun([1, "x", "x", "x", 2]);
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(
    run.calls.filter((c) => c.includes("POST")),
    [POST],
  );
  assert.deepEqual(JSON.parse(run.record), { rerunner_run_id: 700, run_id: 11, attempt: 2 });
  assert.match(run.output, /^recorded=true$/m);
});

test("the re-run step fails visibly when it cannot confirm attempt 2 after the re-run", () => {
  for (const [attempts, reason] of [
    [[1, "x"], /could not read/],
    [[1, 1], /still reads attempt 1/],
  ]) {
    const run = runRerun(attempts);
    assert.equal(run.status, 1, run.stdout);
    assert.equal(run.record, "");
    assert.doesNotMatch(run.output, /recorded=true/);
    assert.match(run.stdout, /^::error::.*/m);
    assert.match(run.stdout, reason);
    // The POST is not repeated, and the reads stop after a bounded number of tries.
    assert.deepEqual(
      run.calls.filter((c) => c.includes("POST")),
      [POST],
    );
    assert.equal(run.calls.filter((c) => !c.includes("POST")).length, 1 + 7);
  }
});

test("a rate-limited read-back stops the re-run step red after one read", () => {
  const run = runRerun([1, "limited", 2]);
  assert.equal(run.status, 1, run.stdout);
  assert.equal(run.record, "");
  assert.match(run.stdout, /::error title=GitHub rate limit::the read-back of run 11's re-run was rate limited/);
  assert.equal(run.calls.filter((c) => !c.includes("POST")).length, 2);
  assert.match(run.output, /^rate-limited=true$/m);
  assert.match(run.output, /^stop=the core pool until 2100-01-01T00:00:00Z$/m);
});

// Owner rule: a rate limit is never sent again, the step ends red, and the
// stop goes to the merge and enable-auto-merge jobs (post-merge-dispatch's
// rate-limited output). The re-run's 429 and the first read's 403 are caught
// by the shared rate guard (api-budget.bash), as every gh call is.
test("a rate-limited re-run POST stops the step red, sends it once, and names the stop", () => {
  const run = runRerun([1], { post: "limited" });
  assert.equal(run.status, 1, run.stdout);
  assert.deepEqual(run.calls.filter((c) => c.includes("POST")), [POST]);
  assert.equal(run.calls.filter((c) => !c.includes("POST")).length, 1);
  assert.equal(run.record, "");
  assert.match(run.stdout, /::error title=GitHub rate limit::the re-run of run 11 was rate limited \(every pool until \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\)/);
  assert.match(run.output, /^rate-limited=true$/m);
  assert.match(run.output, /^stop=every pool until \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/m);
});

// gh's bare 429 message, with no header block or message naming a rate
// limit, is a rate limit too: never read again.
test("a bare HTTP 429 on the read-back stops the re-run step red after one read", () => {
  const run = runRerun([1, "bare429", 2]);
  assert.equal(run.status, 1, run.stdout);
  assert.equal(run.record, "");
  assert.equal(run.calls.filter((c) => !c.includes("POST")).length, 2);
  assert.match(run.stdout, /::error title=GitHub rate limit::the read-back of run 11's re-run was rate limited \(every pool until /);
  assert.match(run.output, /^stop=every pool until \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/m);
});

test("a rate-limited first read stops the step red before the re-run, naming the stop", () => {
  const run = runRerun(["limited"]);
  assert.equal(run.status, 1, run.stdout);
  assert.deepEqual(run.calls.filter((c) => c.includes("POST")), []);
  assert.match(run.stdout, /::error title=GitHub rate limit::the read of run 11 was rate limited \(the core pool until 2100-01-01T00:00:00Z\)/);
  assert.match(run.output, /^stop=the core pool until 2100-01-01T00:00:00Z$/m);
});

test("post-merge-dispatch's rate-limited output also carries the re-run step's stop", () => {
  const header = `${jobBlock("post-merge-dispatch").split("\n    steps:\n")[0]}\n`;
  assert.match(header, /\n {6}rate-limited: \$\{\{ steps\.post-merge\.outputs\.rate-limited \|\| steps\.dispatch\.outputs\.stop \|\| steps\.rerun\.outputs\.stop \}\}\n/);
});

test("the re-run step refuses a run id that is not a number", () => {
  const run = runRerun([1], { runId: "11; rm -rf /" });
  assert.equal(run.status, 1);
  assert.deepEqual(run.calls, []);
});

test("the re-run record is named by run and attempt, uploaded only after a recorded re-run", () => {
  const list = earlySteps();
  const rerun = step("Re-run a red lane-dispatched full run", list);
  // Only a check that could judge (exit 0, 1 or 5) names a run to re-run,
  // and nothing is sent after the dispatch stopped on a rate limit.
  assert.match(
    rerun,
    /\n {8}if: >-\n {10}!cancelled\(\)\n {10}&& steps\.dispatch\.outputs\.rate-limited != 'true'\n {10}&& contains\(fromJSON\('\["0","1","5"\]'\), steps\.post-merge\.outputs\.code\)\n {10}&& steps\.post-merge\.outputs\.lane-rerun != ''\n/,
  );
  assert.match(rerun, /\n {10}GH_TOKEN: \$\{\{ github\.token \}\}\n/);
  const upload = step("Record the re-run", list);
  assert.match(upload, /\n {8}if: "!cancelled\(\) && steps\.rerun\.outputs\.recorded == 'true'"\n/);
  assert.match(upload, /uses: actions\/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 /);
  assert.match(upload, /\n {10}name: pr-merge-rerun-\$\{\{ steps\.post-merge\.outputs\.lane-rerun \}\}-attempt-2\n/);
});

// The merge job's check, run with this run's post-merge-dispatch report kept
// in post-merge-kept (or none) and a fake python3 that marks it ran. The rule
// (pr-merge.yml): reuse a report whose check judged (exit 0, 1 or 5) main at
// this job's commit under REUSE_MINUTES ago; otherwise run the check.
const MAIN = execFileSync("git", ["-C", root, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
const runMergeCheck = ({ kept, code = "0", records, exit = 3, report = { ran: true } } = {}) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-reuse-"));
  try {
    const bin = join(dir, "bin");
    mkdirSync(bin);
    writeFileSync(join(bin, "python3"), `#!/usr/bin/env bash\ntouch "${dir}/ran"\necho '${JSON.stringify(report)}'\nexit ${exit}\n`);
    chmodSync(join(bin, "python3"), 0o755);
    symlinkSync(root, join(dir, ".base"));
    writeFileSync(join(dir, "lane-records.json"), "read in");
    if (kept !== undefined) {
      mkdirSync(join(dir, "post-merge-kept"));
      writeFileSync(join(dir, "post-merge-kept/post-merge.json"), JSON.stringify(kept));
      writeFileSync(join(dir, "post-merge-kept/post-merge-code"), `${code}\n`);
      if (records !== undefined) writeFileSync(join(dir, "post-merge-kept/lane-records.json"), records);
    }
    const output = join(dir, "output");
    const result = spawnSync("bash", ["-c", runScript("Check earlier lane merges")], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, GITHUB_OUTPUT: output, REPO: "o/r", REUSE_MINUTES: /\n {10}REUSE_MINUTES: (\d+)\n/.exec(step("Check earlier lane merges"))[1] },
    });
    return {
      status: result.status,
      stdout: result.stdout,
      ran: existsSync(join(dir, "ran")),
      output: readFileSync(output, "utf8"),
      report: JSON.parse(readFileSync(join(dir, "post-merge.json"), "utf8")),
      records: readFileSync(join(dir, "lane-records.json"), "utf8"),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};
const keptReport = ({ main = MAIN, minutesAgo = 3 } = {}) => ({
  readable: true,
  needsDispatch: true,
  shared: { mainSha: main, computedAt: new Date(Date.now() - minutesAgo * 60_000).toISOString().replace("Z", "+00:00") },
});

test("the merge job reuses this run's post-merge report for main at its commit, with its code and lane records", () => {
  for (const code of ["0", "1", "5"]) {
    const run = runMergeCheck({ kept: keptReport(), code, records: "proved" });
    assert.equal(run.status, 0, run.stdout);
    assert.equal(run.ran, false, code);
    assert.match(run.output, new RegExp(`^code=${code}$`, "m"));
    assert.match(run.output, /^needs-dispatch=true$/m);
    assert.equal(run.report.shared.mainSha, MAIN);
    assert.equal(run.records, "proved");
    assert.match(run.stdout, /::notice::post-merge-dispatch's check judged main at [0-9a-f]{40} \d+s ago/);
  }
  // A report kept with no lane records leaves the ones read in.
  assert.equal(runMergeCheck({ kept: keptReport() }).records, "read in");
});

test("the merge job runs the check itself for no report, another main, an old report or a check that could not judge", () => {
  for (const [why, options] of [
    ["none", {}],
    ["another main", { kept: keptReport({ main: "f".repeat(40) }) }],
    ["7 minutes old", { kept: keptReport({ minutesAgo: 7 }) }],
    ["from the future", { kept: keptReport({ minutesAgo: -5 }) }],
    ["no time", { kept: { ...keptReport(), shared: { mainSha: MAIN } } }],
    ["exit 3", { kept: keptReport(), code: "3" }],
  ]) {
    const run = runMergeCheck({ ...options, records: "proved" });
    assert.equal(run.ran, true, why);
    assert.match(run.output, /^code=3$/m, why);
    assert.deepEqual(run.report, { ran: true }, why);
    assert.equal(run.records, "read in", why);
  }
});

// The gate and every later step would call GitHub again while limited, so
// the merge job's own check fails red on a rate-limit stop too.
test("the merge job's check fails red on a rate-limit stop, after its outputs", () => {
  const run = runMergeCheck({ exit: 75, report: { ran: true, needsDispatch: true } });
  assert.equal(run.ran, true);
  assert.notEqual(run.status, 0, run.stdout);
  assert.match(run.stdout, /^::error::the post-merge check stopped on a GitHub rate limit/m);
  assert.match(run.output, /^needs-dispatch=false$/m);
  assert.match(run.output, /^code=75$/m);
});

test("the merge job reads this run's report only when post-merge-dispatch keeps one", () => {
  const read = step("Read this run's post-merge report");
  assert.match(read, /uses: actions\/download-artifact@[0-9a-f]{40} /);
  // A pattern that matches nothing yet (post-merge-dispatch still checking)
  // downloads nothing rather than failing the step.
  assert.match(read, /\n {10}pattern: pr-merge-post-merge-report\n {10}merge-multiple: true\n {10}path: \$\{\{ runner\.temp \}\}\/post-merge-kept\n/);
  assert.match(read, /\n {8}continue-on-error: true\n/);
  assert.match(read, /steps\.mode\.outputs\.live == 'true'\n {10}&& needs\.post-merge-dispatch\.result != 'skipped'\n/);
  assert.doesNotMatch(read, /run-id|github-token|repository:/);
  const names = steps.map((s) => s.name);
  assert.equal(names.indexOf("Read this run's post-merge report") + 1, names.indexOf("Check earlier lane merges"));
});

// The merge job reads the report only after post-merge-dispatch has kept it.
// !cancelled() keeps the job on pull_request_target, where that job is
// skipped, and when it fails.
test("the merge job waits for post-merge-dispatch and still runs when it is skipped or fails", () => {
  const header = job.slice(0, job.indexOf("\n    steps:\n"));
  assert.match(header, /\n {4}needs: \[post-merge-dispatch\]\n/);
  assert.match(header, /\n {4}if: >-\n {6}!cancelled\(\)\n {6}&& github\.ref == 'refs\/heads\/main'/);
  assert.doesNotMatch(header, /needs\.post-merge-dispatch\.result == 'success'/);
});

test("the lane token request passes the resolved grant's actions, so an actions read grant is compared too", () => {
  const block = step("Request the lane token");
  for (const scope of ["contents", "pull-requests", "issues", "actions"]) {
    assert.match(block, new RegExp(`\\n {10}${scope}: \\$\\{\\{ steps\\.config\\.outputs\\.${scope} \\}\\}\\n`));
  }
});
