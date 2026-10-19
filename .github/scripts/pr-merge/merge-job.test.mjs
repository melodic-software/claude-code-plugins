// pr-merge.yml's merge job: the post-merge check and its re-dispatch do not
// wait on the candidate listing or the gate loop (#8299; a GraphQL 502 on the
// listing once held back every re-dispatch), the listing retries a failed
// `gh pr list` and fails with one clear error, and the gate logs its API cost.
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

test("the gate logs both tokens' core rate limit around the loop and the sweep cost", () => {
  const gate = step("Run the merge gate on each candidate");
  assert.match(gate, /gh api rate_limit --jq '\.resources\.core \| "\\\(\.remaining\)\/\\\(\.limit\) reset=\\\(\.reset\)"'/);
  const before = gate.indexOf('echo "rate before the gate: lane $lane_before github.token $verify_before"');
  const loop = gate.indexOf("while read -r number head updated; do");
  const after = gate.indexOf('echo "rate after the gate: lane $lane_after github.token $verify_after"');
  assert.ok(before >= 0 && loop > before && after > loop);
  assert.match(gate, /verify_before=\$\(GH_TOKEN=\$BABYSIT_VERIFY_GH_TOKEN rate\)/);
  assert.match(gate, /echo "sweep-cost=.* candidates=.*" >>"\$GITHUB_STEP_SUMMARY"/);
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

// Runs the gate step over three candidates with a fake clock: `date +%s`
// answers each value of `clock` in turn (the first is the loop's start).
const runBudgetedGate = (budget, clock) => {
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
  assert.match(run.stepSummary, / reached=2$/m);
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
