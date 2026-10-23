import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const SCRIPT = new URL("./log-api-budget.sh", import.meta.url).pathname;

// A `gh` that answers `api -i rate_limit` with the response `gh api -i` prints
// (status line, headers, blank line, body), its used count read per call from
// a file so a test can move it between phases.
function run({ phase, tokens, used, reset = 1792378942, dir, runner = true }) {
  writeFileSync(join(dir, "used"), String(used));
  writeFileSync(
    join(dir, "gh"),
    `#!/usr/bin/env bash
[[ "$*" == "api -i rate_limit" && -n $GH_TOKEN ]] || exit 9
u=$(cat "${dir}/used")
printf 'HTTP/2.0 200 OK\\r\\nX-Ratelimit-Limit: 5000\\r\\nX-Ratelimit-Remaining: %s\\r\\nX-Ratelimit-Reset: ${reset}\\r\\nX-Ratelimit-Resource: core\\r\\nX-Ratelimit-Used: %s\\r\\n\\r\\n{"resources":{"graphql":{"remaining":4990}}}\\n' $((5000 - u)) "$u"
`,
  );
  chmodSync(join(dir, "gh"), 0o755);
  const summary = join(dir, "summary");
  const output = join(dir, "output");
  writeFileSync(summary, "", { flag: "a" });
  writeFileSync(output, "");
  const stdout = execFileSync("bash", [SCRIPT], {
    env: {
      PATH: `${dir}:${process.env.PATH}`,
      PHASE: phase,
      TOKENS: tokens,
      STATE_DIR: join(dir, "state"),
      GITHUB_STEP_SUMMARY: summary,
      GITHUB_OUTPUT: output,
      ...(runner && {
        GITHUB_WORKFLOW_REF: "melodic-software/claude-code-plugins/.github/workflows/pr-require-checks.yml@refs/pull/9/merge",
        GITHUB_JOB: "ci-status",
        GITHUB_RUN_ID: "39931677333",
        GITHUB_RUN_ATTEMPT: "2",
      }),
    },
    encoding: "utf8",
  });
  return { stdout, summary: readFileSync(summary, "utf8"), output: readFileSync(output, "utf8") };
}

const WHERE = "workflow=.github/workflows/pr-require-checks.yml job=ci-status run=39931677333 attempt=2";

test("prints the rate line at start and the hub's line at end, with the cost since start", () => {
  const dir = mkdtempSync(join(tmpdir(), "log-api-budget-"));
  try {
    const start = run({ phase: "start", tokens: "github-token t0ken", used: 120, dir });
    assert.equal(
      start.stdout,
      "::notice title=api-budget::start github-token core remaining=4880 used=120 limit=5000 reset=2026-10-19T03:02:22Z graphql remaining=4990\n",
    );
    writeFileSync(join(dir, "summary"), "");
    const end = run({ phase: "end", tokens: "github-token t0ken", used: 135, dir });
    assert.equal(
      end.stdout,
      `::notice title=api-budget::token=github-token ${WHERE} limit=5000 remaining=4865 used=135 reset=1792378942 resource=core cost=15\n`,
    );
    assert.equal(
      end.summary,
      "api-budget: end github-token core remaining=4865 used=135 limit=5000 reset=2026-10-19T03:02:22Z graphql remaining=4990 used-since-start=15\ngithub-token-cost=15\n",
    );
    writeFileSync(join(dir, "summary"), "");
    const rolled = run({ phase: "end", tokens: "github-token t0ken", used: 3, reset: 1792382542, dir });
    assert.equal(
      rolled.stdout,
      `::notice title=api-budget::token=github-token ${WHERE} limit=5000 remaining=4997 used=3 reset=1792382542 resource=core cost=na\n`,
    );
    assert.match(rolled.summary, / used-since-start=window-rolled\n/);
    assert.match(rolled.summary, /\ngithub-token-cost=unknown\n$/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// Readings from pr-merge run 39274021802's lane token: used rose 13 -> 328
// while the reset moved earlier, 16:04:04Z -> 15:58:58Z. One window; 315 spent.
const RUN_START_RESET = 1792425844;
const RUN_END_RESET = 1792425538;

function costAt({ start, end }) {
  const dir = mkdtempSync(join(tmpdir(), "log-api-budget-"));
  try {
    run({ phase: "start", tokens: "lanes-app l4ne", ...start, dir });
    return run({ phase: "end", tokens: "lanes-app l4ne", ...end, dir }).output;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("counts the cost when the reset moved earlier within one window", () => {
  assert.equal(
    costAt({ start: { used: 13, reset: RUN_START_RESET }, end: { used: 328, reset: RUN_END_RESET } }),
    "costs=lanes-app-cost=315\n",
  );
});

test("counts the plain difference when the reset is unchanged", () => {
  assert.equal(
    costAt({ start: { used: 13, reset: RUN_START_RESET }, end: { used: 328, reset: RUN_START_RESET } }),
    "costs=lanes-app-cost=315\n",
  );
});

test("reports unknown when the window rolled: reset an hour later and used lower", () => {
  assert.equal(
    costAt({ start: { used: 328, reset: RUN_START_RESET }, end: { used: 13, reset: RUN_START_RESET + 3600 } }),
    "costs=lanes-app-cost=unknown\n",
  );
});

test("reports unknown when the reset moved later by an hour even though used rose", () => {
  assert.equal(
    costAt({ start: { used: 13, reset: RUN_START_RESET }, end: { used: 328, reset: RUN_START_RESET + 3600 } }),
    "costs=lanes-app-cost=unknown\n",
  );
});

test("reports unknown when used went down at the same reset", () => {
  assert.equal(
    costAt({ start: { used: 328, reset: RUN_START_RESET }, end: { used: 13, reset: RUN_START_RESET } }),
    "costs=lanes-app-cost=unknown\n",
  );
});

test("skips an entry with no token or a bad name, and still exits 0", () => {
  const dir = mkdtempSync(join(tmpdir(), "log-api-budget-"));
  try {
    const { stdout } = run({ phase: "start", tokens: "github-token\nBad_Name t0ken", used: 1, dir });
    assert.equal(stdout, "::warning::api-budget: skipped a token entry with no usable name or token\n".repeat(2));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("sets the costs output at a later phase, for every token, and none at start", () => {
  const dir = mkdtempSync(join(tmpdir(), "log-api-budget-"));
  try {
    const tokens = "lanes-app l4ne\ngithub-token t0ken";
    assert.equal(run({ phase: "start", tokens, used: 100, dir }).output, "");
    assert.equal(run({ phase: "end", tokens, used: 142, dir }).output, "costs=lanes-app-cost=42 github-token-cost=42\n");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("an end with no start reading still prints the hub's line, cost na", () => {
  const dir = mkdtempSync(join(tmpdir(), "log-api-budget-"));
  try {
    const end = run({ phase: "end", tokens: "lanes-app l4ne", used: 7, dir });
    assert.equal(
      end.stdout,
      `::notice title=api-budget::token=lanes-app ${WHERE} limit=5000 remaining=4993 used=7 reset=1792378942 resource=core cost=na\n`,
    );
    assert.equal(end.output, "costs=lanes-app-cost=unknown\n");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a run with no runner variables names them na", () => {
  const dir = mkdtempSync(join(tmpdir(), "log-api-budget-"));
  try {
    const end = run({ phase: "end", tokens: "github-token t0ken", used: 7, dir, runner: false });
    assert.equal(
      end.stdout,
      "::notice title=api-budget::token=github-token workflow=na job=na run=na attempt=na limit=5000 remaining=4993 used=7 reset=1792378942 resource=core cost=na\n",
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
