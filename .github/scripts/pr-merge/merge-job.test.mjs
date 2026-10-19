// pr-merge.yml's merge job: the post-merge check and its re-dispatch do not
// wait on the candidate listing or the gate loop (#8299; a GraphQL 502 on the
// listing once held back every re-dispatch), the listing retries a failed
// `gh pr list` and fails with one clear error, the run logs its API cost
// through the shared action, and the run cache carries the verdict reads that
// never change to the next run.
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
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
      "Check earlier lane merges",
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

// Runs the listing step's script against a fake `gh` that fails its first
// `failures` calls, with `.base` pointing at this checkout.
const runListing = (failures) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-listing-"));
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", [bin]);
    writeFileSync(
      join(bin, "gh"),
      `#!/usr/bin/env bash\nn=$(($(cat "${dir}/calls" 2>/dev/null || echo 0) + 1))\necho "$n" >"${dir}/calls"\n` +
        `if [ "$n" -le ${failures} ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi\n` +
        `echo '[{"number":7,"headRefOid":"abc","isDraft":false,"updatedAt":"2026-10-18T00:00:00Z","labels":[],"body":""}]'\n`,
    );
    writeFileSync(join(bin, "sleep"), "#!/usr/bin/env bash\n");
    chmodSync(join(bin, "gh"), 0o755);
    chmodSync(join(bin, "sleep"), 0o755);
    symlinkSync(root, join(dir, ".base"));
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
      },
    });
    return {
      status: result.status,
      stdout: result.stdout,
      stderr: result.stderr,
      calls: Number(readFileSync(join(dir, "calls"), "utf8")),
      prefiltered: existsSync(join(dir, "prefilter.json")),
      output: existsSync(output) ? readFileSync(output, "utf8") : "",
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

test("the listing retries a failed gh pr list", () => {
  const run = runListing(2);
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.calls, 3);
  assert.match(run.output, /^count=1$/m);
});

test("the listing fails with one clear error after three failed tries", () => {
  const run = runListing(3);
  assert.equal(run.status, 1);
  assert.equal(run.calls, 3);
  assert.match(run.stdout, /^::error::gh pr list --author app\/[a-z0-9-]+ failed 3 times/m);
  assert.equal(run.prefiltered, false);
  assert.doesNotMatch(run.stderr, /jq: error|Traceback/);
});

test("the API budget is logged through the shared action at mint and at job end, for both tokens", () => {
  for (const [name, phase, condition] of [
    ["Log the API budget at mint", "start", "steps.lane-token.outputs.token != ''"],
    ["Log the API budget at job end", "end", "always() && steps.lane-token.outputs.token != ''"],
  ]) {
    const block = step(name);
    assert.match(block, /\n {8}uses: \.\/\.base\/\.github\/actions\/log-api-budget /);
    assert.match(block, new RegExp(`\\n {8}if: ${condition.replace(/[().|$]/g, "\\$&")}\\n`));
    assert.match(block, /\n {8}continue-on-error: true\n/);
    assert.match(block, new RegExp(`\\n {10}phase: ${phase}\\n`));
    assert.match(block, /\n {12}lane \$\{\{ steps\.lane-token\.outputs\.token \}\}\n {12}github-token \$\{\{ github\.token \}\}\n/);
  }
  assert.doesNotMatch(job, /gh api rate_limit/);
  const names = steps.map((s) => s.name);
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
  const run = runSweepCost("lane-cost=312 github-token-cost=41", 3, 2);
  assert.equal(run.status, 0);
  const line = "sweep-cost=312 github-token-cost=41 candidates=5 reached=3 skipped=2\n";
  assert.equal(run.stdout, line);
  assert.equal(run.stepSummary, line);
  // A rolled window, or no end reading, reads unknown.
  assert.equal(runSweepCost("lane-cost=unknown", 0).stdout, "sweep-cost=unknown github-token-cost=unknown candidates=5 reached=0 skipped=0\n");
  const block = step("Write the sweep cost");
  assert.match(block, /\n {8}if: always\(\) && steps\.gate\.outcome != 'skipped'\n/);
  assert.match(block, /COSTS: \$\{\{ steps\.budget-end\.outputs\.costs \}\}/);
  const names = steps.map((s) => s.name);
  assert.ok(names.indexOf("Log the API budget at job end") < names.indexOf("Write the sweep cost"));
});

test("the run cache starts from the last run's kept reads and saves this run's under a new key", () => {
  const names = steps.map((s) => s.name);
  const order = [
    "Restore the verdict reads the last run kept",
    "Start the run cache from them",
    "Run the merge gate on each candidate",
    "Keep the verdict reads that never change",
    "Save them for the next run",
  ].map((name) => names.indexOf(name));
  assert.ok(order.every((i, n) => i >= 0 && (n === 0 || i > order[n - 1])), String(order));
  const key = "pr-merge-run-cache-${{ github.run_id }}-${{ github.run_attempt }}";
  const carried = "${{ runner.temp }}/pr-merge-carried.json";
  const runCache = "${{ runner.temp }}/babysit-run-cache.json";
  const restore = step("Restore the verdict reads the last run kept");
  assert.match(restore, /uses: actions\/cache\/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 /);
  assert.ok(restore.includes(`key: ${key}\n`) && restore.includes("restore-keys: pr-merge-run-cache-\n"));
  assert.ok(restore.includes(`path: ${carried}\n`));
  const start = step("Start the run cache from them");
  assert.ok(start.includes(`CARRY_FROM: ${carried}\n`) && start.includes(`CARRY_TO: ${runCache}\n`));
  assert.ok(step("Run the merge gate on each candidate").includes(`BABYSIT_RUN_CACHE: ${runCache}\n`));
  const keep = step("Keep the verdict reads that never change");
  assert.ok(keep.includes(`CARRY_FROM: ${runCache}\n`) && keep.includes(`CARRY_TO: ${carried}\n`));
  assert.match(keep, /\n {8}if: always\(\) && steps\.gate\.outcome != 'skipped'\n/);
  const save = step("Save them for the next run");
  assert.match(save, /uses: actions\/cache\/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 /);
  assert.ok(save.includes(`key: ${key}\n`) && save.includes(`path: ${carried}\n`));
  assert.match(save, /\n {8}if: always\(\) && steps\.carry\.outputs\.carried == 'true'\n/);
  for (const name of ["Restore the verdict reads the last run kept", "Start the run cache from them", "Keep the verdict reads that never change", "Save them for the next run"]) {
    assert.match(step(name), /\n {8}continue-on-error: true\n/, name);
  }
});

// Runs the early job's check against a fake python3 that prints a report and
// exits `code`.
const runEarlyCheck = (code) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-early-"));
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", [bin]);
    writeFileSync(join(bin, "python3"), `#!/usr/bin/env bash\necho '{"needsDispatch": false}'\nexit ${code}\n`);
    chmodSync(join(bin, "python3"), 0o755);
    symlinkSync(root, join(dir, ".base"));
    const output = join(dir, "output");
    const script = runScript("Check earlier lane merges", stepsOf(jobBlock("post-merge-dispatch")));
    const result = spawnSync("bash", ["-c", script], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, GITHUB_OUTPUT: output, REPO: "o/r" },
    });
    return { status: result.status, stdout: result.stdout, output: readFileSync(output, "utf8") };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

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
  for (const error of ["demotion issue: HTTP 403", "dequeue: HTTP 502"]) {
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
// `skipped` as the skip step's file when given.
const runBudgetedGate = (budget, clock, skipped) => {
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
      `#!/usr/bin/env bash\necho "\${@: -1}" >>"${dir}/gated"\n` +
        `echo '{"ready": false, "blockers": ["x"], "unattended": {"reason": "verify:missing"}}'\nexit 10\n`,
    );
    for (const file of [join(bin, "gh"), join(bin, "date"), join(dir, ".base", "gate")]) chmodSync(file, 0o755);
    writeFileSync(join(dir, "resolved-config.json"), '{"selected": {"args": ""}}');
    writeFileSync(join(dir, "held.json"), "[]");
    writeFileSync(
      join(dir, "candidates.json"),
      JSON.stringify([7, 3, 5].map((number) => ({ number, head: `h${number}`, updatedAt: "u" }))),
    );
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
      },
    });
    const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
    return {
      status: result.status,
      stdout: result.stdout,
      stderr: result.stderr,
      gated: read("gated").split("\n").filter(Boolean),
      cursor: read("gate-cursor/cursor.json"),
      stepSummary: read("step-summary"),
      summary: JSON.parse(read("pr-merge-summary.json") || "null"),
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

test("the skip step runs just before the gate and its record between the carry and the save, neither able to fail the job", () => {
  const names = steps.map((s) => s.name);
  const at = (name) => names.indexOf(name);
  assert.equal(at("Skip refusals whose inputs have not changed"), at("Run the merge gate on each candidate") - 1);
  assert.ok(at("Record a failed lane merge") < at("Skip refusals whose inputs have not changed"));
  assert.equal(at("Keep the refusals the next run may skip"), at("Keep the verdict reads that never change") + 1);
  assert.equal(at("Save them for the next run"), at("Keep the refusals the next run may skip") + 1);
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
// the run read, failing a read whose entry is "x", and fails the re-run POST
// when `refuse`.
const runRerun = (attempts, { refuse = false, runId = "11" } = {}) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-rerun-"));
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", [bin]);
    writeFileSync(
      join(bin, "gh"),
      `#!/usr/bin/env bash\necho "$*" >>"${dir}/calls"\n` +
        `if [ "$3" = POST ]; then ${refuse ? 'echo "HTTP 403" >&2; exit 1' : "exit 0"}; fi\n` +
        `n=$(($(cat "${dir}/reads" 2>/dev/null || echo 0) + 1))\necho "$n" >"${dir}/reads"\n` +
        `a=(${attempts.join(" ")})\nv="\${a[$((n - 1))]:-\${a[-1]}}"\n` +
        `if [ "$v" = x ]; then echo "HTTP 502" >&2; exit 1; fi\necho "$v"\n`,
    );
    writeFileSync(join(bin, "sleep"), "#!/usr/bin/env bash\n");
    chmodSync(join(bin, "gh"), 0o755);
    chmodSync(join(bin, "sleep"), 0o755);
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

test("the re-run step refuses a run id that is not a number", () => {
  const run = runRerun([1], { runId: "11; rm -rf /" });
  assert.equal(run.status, 1);
  assert.deepEqual(run.calls, []);
});

test("the re-run record is named by run and attempt, uploaded only after a recorded re-run", () => {
  const list = earlySteps();
  const rerun = step("Re-run a red lane-dispatched full run", list);
  // Only a check that could judge (exit 0, 1 or 5) names a run to re-run.
  assert.match(
    rerun,
    /\n {8}if: >-\n {10}!cancelled\(\)\n {10}&& contains\(fromJSON\('\["0","1","5"\]'\), steps\.post-merge\.outputs\.code\)\n {10}&& steps\.post-merge\.outputs\.lane-rerun != ''\n/,
  );
  assert.match(rerun, /\n {10}GH_TOKEN: \$\{\{ github\.token \}\}\n/);
  const upload = step("Record the re-run", list);
  assert.match(upload, /\n {8}if: "!cancelled\(\) && steps\.rerun\.outputs\.recorded == 'true'"\n/);
  assert.match(upload, /uses: actions\/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 /);
  assert.match(upload, /\n {10}name: pr-merge-rerun-\$\{\{ steps\.post-merge\.outputs\.lane-rerun \}\}-attempt-2\n/);
});
