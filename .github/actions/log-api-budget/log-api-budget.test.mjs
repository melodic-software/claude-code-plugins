import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { readingLine, recordReading } from "./api-budget.mjs";

const LIB = new URL("./api-budget.bash", import.meta.url).pathname;
const ACTION = readFileSync(new URL("./action.yml", import.meta.url), "utf8");
const CI = readFileSync(new URL("../../workflows/pr-require-checks.yml", import.meta.url), "utf8");

const RUNNER = {
  GITHUB_WORKFLOW_REF: "melodic-software/claude-code-plugins/.github/workflows/pr-require-checks.yml@refs/pull/9/merge",
  GITHUB_JOB: "ci-status",
  GITHUB_RUN_ID: "39931677333",
  GITHUB_RUN_ATTEMPT: "2",
};
const WHERE = "workflow=.github/workflows/pr-require-checks.yml job=ci-status run=39931677333 attempt=2";
const NOTICE = "::notice title=api-budget::";

// A `gh api -i` header block, CRLF header lines as gh prints them.
const head = ({ status = 200, used, reset = 1792748042, resource = "core" }) =>
  `HTTP/2.0 ${status} OK\nContent-Type: application/json\r\nX-Ratelimit-Limit: 5000\r\n` +
  `X-Ratelimit-Remaining: ${5000 - used}\r\nX-Ratelimit-Reset: ${reset}\r\nX-Ratelimit-Resource: ${resource}\r\n` +
  `X-Ratelimit-Used: ${used}\r\n\r\n`;

function withDir(fn) {
  const dir = mkdtempSync(join(tmpdir(), "api-budget-"));
  try {
    return fn(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// Runs `script` in bash with the library sourced; returns stdout and status.
function bash(dir, script, { input = "", env = {}, path = process.env.PATH } = {}) {
  const result = spawnSync("bash", ["-c", `. "${LIB}"\n${script}`], {
    input,
    encoding: "utf8",
    env: { PATH: path, RUNNER_TEMP: dir, ...RUNNER, ...env },
  });
  return { stdout: result.stdout, stderr: result.stderr, status: result.status };
}

const state = (dir, token) => readFileSync(join(dir, "api-budget", token), "utf8");

// One response per api_budget_read, as each gh api call makes.
const readEach = (dir, token, ...blocks) => blocks.forEach((input) => bash(dir, `api_budget_read ${token} >/dev/null`, { input }));

test("api_budget_read reads only the leading header block and passes the body through unchanged", () =>
  withDir((dir) => {
    // A body line shaped like a status line is body, never a second block.
    const body = "keep1\nHTTP/1.1 200 x\nflagged()\n\nafter\n";
    const out = bash(dir, "api_budget_read github-token", { input: head({ used: 120 }) + body });
    assert.equal(out.stdout, body);
    assert.equal(state(dir, "github-token"), "200 5000 4880 120 1792748042 core\n");
    // Output with no header block is passed on and read as nothing.
    assert.equal(bash(dir, "api_budget_read lanes-app", { input: "[1]\n" }).stdout, "[1]\n");
    assert.equal(existsSync(join(dir, "api-budget", "lanes-app")), false);
  }));

test("the gh wrapper keeps stdout, stderr and the exit status, and reads the headers", () =>
  withDir((dir) => {
    // A gh that answers `api -i <route> ...` with a header block, a body, an error and exit 1.
    writeFileSync(
      join(dir, "gh"),
      `#!/usr/bin/env bash\n[[ $1 == api && $2 == -i && $3 == route ]] || { echo "args: $*" >&2; exit 9; }\n` +
        `printf '${head({ status: 403, used: 5000 }).replace(/\r/g, "\\r").replace(/\n/g, "\\n")}{"message":"rate limit"}'\n` +
        `echo 'gh: rate limit (HTTP 403)' >&2\nexit 1\n`,
    );
    chmodSync(join(dir, "gh"), 0o755);
    const out = bash(dir, 'api_budget_wrap_gh github-token\nbody=$(gh api route --jq .) || echo "exit=$?"\necho "$body"', {
      path: `${dir}:${process.env.PATH}`,
    });
    assert.equal(out.stdout, 'exit=1\n{"message":"rate limit"}\n');
    assert.equal(out.stderr, "gh: rate limit (HTTP 403)\n");
    assert.equal(state(dir, "github-token"), "403 5000 0 5000 1792748042 core\n");
    // A call that is not `gh api`, or already asks for headers, is passed on as it is.
    for (const args of ["pr view 1", "api route --paginate --jq .", "api --silent route"]) {
      const plain = bash(dir, `api_budget_wrap_gh github-token\ngh ${args}`, { path: `${dir}:${process.env.PATH}` });
      assert.equal(plain.stderr, `args: ${args}\n`);
      assert.equal(plain.status, 9);
    }
  }));

test("api_budget_emit writes the hub line for the last reading, cost since the first with the same reset", () =>
  withDir((dir) => {
    readEach(dir, "github-token", head({ used: 13 }), head({ used: 100, reset: 1792748100 }), head({ used: 328, reset: 1792748100 }));
    assert.equal(
      bash(dir, "api_budget_emit github-token").stdout,
      `${NOTICE}token=github-token ${WHERE} limit=5000 remaining=4672 used=328 reset=1792748100 resource=core cost=228\n`,
    );
  }));

test("api_budget_emit writes cost=na when the last reading has no earlier one in its window", () =>
  withDir((dir) => {
    readEach(dir, "lanes-app", head({ used: 900 }), head({ used: 3, reset: 1792751642 }));
    assert.equal(
      bash(dir, "api_budget_emit lanes-app").stdout,
      `${NOTICE}token=lanes-app ${WHERE} limit=5000 remaining=4997 used=3 reset=1792751642 resource=core cost=na\n`,
    );
  }));

test("api_budget_emit writes a line for each refused reading and then the last", () =>
  withDir((dir) => {
    readEach(dir, "github-token", head({ used: 1000 }), head({ status: 403, used: 1066 }), head({ status: 429, used: 1066 }), head({ used: 1070 }));
    const lines = bash(dir, "api_budget_emit github-token").stdout.split("\n").filter(Boolean);
    assert.deepEqual(
      lines.map((line) => line.slice(line.indexOf(" used="))),
      [
        " used=1066 reset=1792748042 resource=core cost=66",
        " used=1066 reset=1792748042 resource=core cost=66",
        " used=1070 reset=1792748042 resource=core cost=70",
      ],
    );
  }));

test("api_budget_emit names unset runner fields na and skips a token with no reading", () =>
  withDir((dir) => {
    readEach(dir, "github-token", head({ used: 7 }));
    const env = { GITHUB_WORKFLOW_REF: "", GITHUB_JOB: "", GITHUB_RUN_ID: "", GITHUB_RUN_ATTEMPT: "" };
    assert.equal(
      bash(dir, "api_budget_emit lanes-app github-token", { env }).stdout,
      `${NOTICE}token=github-token workflow=na job=na run=na attempt=na limit=5000 remaining=4993 used=7 reset=1792748042 resource=core cost=na\n`,
    );
  }));

test("recordReading appends the same line shape, na for a missing or malformed value, and needs a token name", () =>
  withDir((dir) => {
    const headers = new Headers({ "x-ratelimit-limit": "5000", "x-ratelimit-used": "12", "x-ratelimit-resource": "Core!" });
    assert.equal(readingLine(304, headers), "304 5000 na 12 na na\n");
    recordReading({ token: "github-token", dir, status: 200, headers });
    recordReading({ token: "", dir, status: 200, headers });
    assert.equal(state(dir, "github-token"), "200 5000 na 12 na na\n");
    assert.equal(existsSync(join(dir, "api-budget", "lanes-app")), false);
  }));

test("the action emits each named token, writes the summary and the costs output, and reads no /rate_limit", () =>
  withDir((dir) => {
    readEach(dir, "github-token", head({ used: 13 }), head({ used: 41 }));
    const run = /\n {6}run: \|\n([\s\S]*)$/.exec(ACTION)[1].replace(/^ {8}/gm, "");
    writeFileSync(join(dir, "summary"), "");
    writeFileSync(join(dir, "output"), "");
    const out = execFileSync("bash", ["-c", run], {
      encoding: "utf8",
      env: {
        PATH: process.env.PATH,
        ...RUNNER,
        RUNNER_TEMP: dir,
        GITHUB_ACTION_PATH: new URL(".", import.meta.url).pathname,
        GITHUB_STEP_SUMMARY: join(dir, "summary"),
        GITHUB_OUTPUT: join(dir, "output"),
        TOKENS: "lanes-app\ngithub-token",
      },
    });
    assert.equal(out, `${NOTICE}token=github-token ${WHERE} limit=5000 remaining=4959 used=41 reset=1792748042 resource=core cost=28\n`);
    assert.equal(
      readFileSync(join(dir, "summary"), "utf8"),
      `api-budget: token=github-token ${WHERE} limit=5000 remaining=4959 used=41 reset=1792748042 resource=core cost=28\ngithub-token-cost=28\n`,
    );
    assert.equal(readFileSync(join(dir, "output"), "utf8"), "costs=github-token-cost=28\n");
    assert.doesNotMatch(ACTION + readFileSync(LIB, "utf8"), /gh api[^\n]*rate_limit/);
  }));

test("ci-status carries api-budget.bash verbatim in its API_BUDGET_SH env", () => {
  const block = /\n {6}API_BUDGET_SH: \|\n((?: {8}[^\n]*\n|\n)+)/.exec(CI);
  assert.ok(block, "ci-status sets API_BUDGET_SH as a block scalar");
  const carried = block[1].replace(/^ {8}/gm, "").replace(/\n+$/, "\n");
  assert.equal(carried, readFileSync(LIB, "utf8"));
});
