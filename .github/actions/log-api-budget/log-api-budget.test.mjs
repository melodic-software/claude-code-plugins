import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { readingLine, recordReading } from "./api-budget.mjs";
import { apiLimits, poolOf } from "./rate-guard.mjs";

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
// api_budget_read takes a file, as the gh wrapper gives it one.
const READ = 'f=$(mktemp -p "$RUNNER_TEMP"); cat >"$f"; api_budget_read';

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
const readEach = (dir, token, ...blocks) => blocks.forEach((input) => bash(dir, `${READ} ${token} "$f" >/dev/null`, { input }));

test("api_budget_read reads only the leading header block and passes the body through unchanged", () =>
  withDir((dir) => {
    // A body line shaped like a status line is body, never a second block.
    const body = "keep1\nHTTP/1.1 200 x\nflagged()\n\nafter\n";
    const out = bash(dir, `${READ} github-token "$f"`, { input: head({ used: 120 }) + body });
    assert.equal(out.stdout, body);
    assert.equal(state(dir, "github-token"), "200 5000 4880 120 1792748042 core\n");
    // Output with no header block is passed on and read as nothing.
    assert.equal(bash(dir, `${READ} lanes-app "$f"`, { input: "[1]\n" }).stdout, "[1]\n");
    assert.equal(existsSync(join(dir, "api-budget", "lanes-app")), false);
    // A body with no final newline keeps none.
    assert.equal(bash(dir, `${READ} x "$f"`, { input: `${head({ used: 1 })}{"a":1}` }).stdout, '{"a":1}');
  }));

test("api_budget_emit writes the last reading of each resource, core last", () =>
  withDir((dir) => {
    readEach(dir, "lanes-app", head({ used: 10 }), head({ used: 4, resource: "graphql" }), head({ used: 12 }), head({ used: 9, resource: "graphql" }));
    const lines = bash(dir, "api_budget_emit lanes-app").stdout.split("\n").filter(Boolean);
    assert.deepEqual(
      lines.map((line) => line.slice(line.indexOf(" used="))),
      [" used=9 reset=1792748042 resource=graphql cost=5", " used=12 reset=1792748042 resource=core cost=2"],
    );
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
    assert.match(out.stderr, /^gh: rate limit \(HTTP 403\)\n::error::'gh api route --jq \.' hit GitHub's core API rate limit/);
    assert.equal(state(dir, "github-token"), "403 5000 0 5000 1792748042 core\n");
    rmSync(join(dir, "api-budget", "stop"), { force: true });
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

// The shell port of the rate guard decides every shared vector as
// rate-guard.mjs does.
test("api_budget_classify decides every rate-guard vector", () => {
  const vectors = JSON.parse(readFileSync(new URL("./rate-guard.vectors.json", import.meta.url), "utf8"));
  const floor = apiLimits({ resolvedPath: "" })["github-token"]["read-floor"];
  for (const vector of vectors.vectors) {
    const input = { ...vector.input, now: vectors.vector_now * 1000, pool: poolOf(vector.input.url), floor };
    const out = bash(tmpdir(), 'jq -c "$API_BUDGET_CLASSIFY"', { input: JSON.stringify(input) });
    assert.deepEqual(JSON.parse(out.stdout), vector.expect, `${vector.name}: ${out.stderr}`);
  }
});

// A gh that logs each call and answers from STUB_ANSWERS, one line per call:
// `<status> <remaining> <retry-after or -> <body>` for `api -i`, printed as a
// header block and body (exit 1 unless 200); `fail <text>` prints text on
// stderr and exits 1; `ok <text>` prints text.
function stubGh(dir) {
  writeFileSync(
    join(dir, "gh"),
    `#!/usr/bin/env bash
echo "$*" >>"$RUNNER_TEMP/calls"
n=$(wc -l <"$RUNNER_TEMP/calls")
read -r status remaining after body <<<"$(sed -n "\${n}p" "$RUNNER_TEMP/answers")"
case $status in
  ok) echo "$remaining $after $body"; exit 0 ;;
  fail) echo "$remaining $after $body" >&2; exit 1 ;;
esac
printf 'HTTP/2.0 %s X\\r\\nX-Ratelimit-Limit: 5000\\r\\nX-Ratelimit-Remaining: %s\\r\\nX-Ratelimit-Reset: %s\\r\\nX-Ratelimit-Resource: core\\r\\n' "$status" "$remaining" $(($(date +%s) + 3600))
[[ $after == - ]] || printf 'Retry-After: %s\\r\\n' "$after"
printf '\\r\\n%s\\n' "$body"
[[ $status == 200 ]]
`,
  );
  chmodSync(join(dir, "gh"), 0o755);
}

function guarded(dir, answers, script, env = {}) {
  stubGh(dir);
  writeFileSync(join(dir, "answers"), `${answers.join("\n")}\n`);
  writeFileSync(join(dir, "calls"), "");
  const out = bash(dir, `api_budget_wrap_gh github-token\n${script}`, { path: `${dir}:${process.env.PATH}`, env });
  return { ...out, calls: readFileSync(join(dir, "calls"), "utf8").split("\n").filter(Boolean) };
}

test("gh guard: a limited response sends no second call to its pool, and the error names the reset", () =>
  withDir((dir) => {
    const out = guarded(
      dir,
      ['403 0 - {"message":"API rate limit exceeded for installation ID 1."}', "200 4000 - {}", "200 4000 - {}"],
      'gh api repos/o/r/pulls/1 >/dev/null || echo "first=$?"\n' +
        'gh api repos/o/r/pulls/2 >/dev/null || echo "second=$?"\n' +
        "gh pr view 1 || echo \"pr=$?\"\n" +
        'gh api graphql -f query=x >/dev/null && echo "graphql=sent"',
    );
    assert.equal(out.stdout, "first=1\nsecond=1\npr=1\ngraphql=sent\n");
    assert.deepEqual(out.calls, ["api -i repos/o/r/pulls/1", "api -i graphql -f query=x"]);
    const reset = new Date(Number(readFileSync(join(dir, "api-budget", "stop"), "utf8").split(" ")[1]) * 1000).toISOString().replace(".000Z", "Z");
    assert.match(out.stderr, new RegExp(`::error::'gh api repos/o/r/pulls/1' hit GitHub's core API rate limit: no call to it before ${reset}`));
    assert.match(out.stderr, new RegExp(`::error::'gh api repos/o/r/pulls/2' was not sent: GitHub's core API rate limit holds until ${reset}`));
  }));

test("gh guard: retry-after stops every pool until it ends, and an ended stop lets calls go", () =>
  withDir((dir) => {
    const out = guarded(dir, ['403 4000 120 {"message":"You have exceeded a secondary rate limit."}', "200 4000 - {}"], 'gh api repos/o/r >/dev/null; gh api graphql -f query=x || echo "refused=$?"');
    assert.equal(out.stdout, "refused=1\n");
    assert.equal(out.calls.length, 1);
    const [pool, until] = readFileSync(join(dir, "api-budget", "stop"), "utf8").trim().split(" ");
    assert.equal(pool, "*");
    assert.ok(Math.abs(Number(until) - (Math.floor(Date.now() / 1000) + 120)) <= 5);
    writeFileSync(join(dir, "api-budget", "stop"), `* ${Math.floor(Date.now() / 1000) - 1}\n`);
    assert.equal(guarded(dir, ["200 4000 - {}"], "gh api repos/o/r").calls.length, 1);
  }));

// The epoch second of the one stop a case wrote, less now.
const stopFor = (dir) => {
  const [pool, until] = readFileSync(join(dir, "api-budget", "stop"), "utf8").trim().split(" ");
  return [pool, Number(until) - Math.floor(Date.now() / 1000)];
};

test("gh guard: a paginated call that fails on a primary limit stops every pool for an hour, not a minute", () =>
  withDir((dir) => {
    const out = guarded(dir, ["fail gh: API rate limit exceeded for installation. (HTTP 403)"], 'gh api repos/o/r/pulls --paginate || true\ngh api repos/o/r || echo "refused=$?"');
    assert.equal(out.stdout, "refused=1\n");
    assert.equal(out.calls.length, 1);
    assert.match(out.stderr, /\(fallback\); the call returns 1/);
    const [pool, left] = stopFor(dir);
    assert.equal(pool, "*");
    assert.ok(left >= 3595 && left <= 3600, `stopped for ${left}s`);
    // Still stopped well past the minute: two minutes on, nothing is sent.
    const later = Math.floor(Date.now() / 1000) + 120;
    const shifted = guarded(dir, ["ok never"], `date() { echo ${later}; }\ngh api repos/o/r/pulls --paginate || echo "refused=$?"`);
    assert.equal(shifted.stdout, "refused=1\n");
    assert.equal(shifted.calls.length, 0);
  }));

test("gh guard: a paginated secondary or abuse-detection limit waits the minute; a 429 an hour", () =>
  withDir((dir) => {
    for (const [text, seconds] of [
      ["gh: You have exceeded a secondary rate limit. (HTTP 403)", 60],
      ["gh: You have triggered an abuse detection mechanism. (HTTP 403)", 60],
      ["gh: Too Many Requests (HTTP 429)", 3600],
    ]) {
      rmSync(join(dir, "api-budget"), { recursive: true, force: true });
      const out = guarded(dir, [`fail ${text}`], "gh api repos/o/r/pulls --paginate || true");
      const [pool, left] = stopFor(dir);
      assert.equal(pool, "*", text);
      assert.ok(left >= seconds - 5 && left <= seconds, `${text}: stopped for ${left}s`);
      assert.match(out.stderr, /::error::/, text);
    }
  }));

// The call got a good answer, so it keeps gh's status: a caller that read a
// failure would retry a write GitHub already accepted. The next call is
// refused.
test("gh guard: a 200 that spends the last request keeps its body and status 0, and stops the pool", () =>
  withDir((dir) => {
    const out = guarded(
      dir,
      ['200 0 - {"ok":1}', "200 4000 - {}"],
      'body=$(gh api repos/o/r) && echo "rc=0"\necho "$body"\ngh api repos/o/r/pulls >/dev/null || echo "next=$?"',
    );
    assert.equal(out.stdout, 'rc=0\n{"ok":1}\nnext=1\n');
    assert.equal(out.calls.length, 1);
    assert.match(state(dir, "github-token"), /^200 5000 0 /);
    assert.match(out.stderr, /; its answer stands, and later calls to it are refused$/m);
    assert.equal(stopFor(dir)[0], "core");
  }));

test("gh guard: a POST answered 200 with remaining 0 returns 0, so no caller resends the write", () =>
  withDir((dir) => {
    for (const flag of ["", "-i "]) {
      rmSync(join(dir, "api-budget"), { recursive: true, force: true });
      const out = guarded(dir, ['200 0 - {"id":1}'], `gh api ${flag}-X POST repos/o/r/issues/1/comments -f body=x >/dev/null && echo sent`);
      assert.equal(out.stdout, "sent\n", flag);
      assert.equal(out.calls.length, 1, flag);
    }
  }));

test("gh guard: a refused answer still returns 1 on both paths", () =>
  withDir((dir) => {
    for (const flag of ["", "-i "]) {
      rmSync(join(dir, "api-budget"), { recursive: true, force: true });
      const out = guarded(dir, ['403 0 - {"message":"API rate limit exceeded"}'], `gh api ${flag}repos/o/r >/dev/null || echo "rc=$?"`);
      assert.equal(out.stdout, "rc=1\n", flag);
      assert.match(out.stderr, /; the call returns 1$/m, flag);
    }
  }));

test("gh guard: a stop-file line whose reset is not a number stops nothing", () =>
  withDir((dir) => {
    mkdirSync(join(dir, "api-budget"), { recursive: true });
    writeFileSync(join(dir, "api-budget", "stop"), "core 99999999999x\n* abc\ncore 1e12\n");
    const out = guarded(dir, ["200 4000 - {}"], 'until=$(api_budget_stop_until core); echo "until=$until"\ngh api repos/o/r >/dev/null && echo sent');
    assert.equal(out.stdout, "until=\nsent\n");
    assert.equal(out.calls.length, 1);
  }));

test("gh guard: a 403 Resource not accessible is passed on as before, with no stop", () =>
  withDir((dir) => {
    const out = guarded(dir, ['403 4000 - {"message":"Resource not accessible by integration"}', "200 4000 - {}"], 'gh api repos/o/r >/dev/null || echo "first=$?"\ngh api repos/o/r >/dev/null && echo "second=sent"');
    assert.equal(out.stdout, "first=1\nsecond=sent\n");
    assert.equal(out.calls.length, 2);
    assert.equal(out.stderr, "");
    assert.equal(existsSync(join(dir, "api-budget", "stop")), false);
  }));

test("gh guard: under the read floor it warns once and keeps sending", () =>
  withDir((dir) => {
    const out = guarded(dir, ["200 450 - {}", "200 449 - {}"], "gh api repos/o/r >/dev/null; gh api repos/o/r >/dev/null", { API_BUDGET_READ_FLOOR: "0.1" });
    assert.equal(out.calls.length, 2);
    assert.equal(out.stderr.match(/::warning::/g)?.length, 1);
    assert.match(out.stderr, /reads continue\n/);
    assert.equal(out.status, 0);
  }));

test("api_budget_is_content judges a gh call as rate-guard.mjs's isContentWrite judges its request", () => {
  const writes = [
    "api -X POST repos/o/r/issues/7/comments -f body=x",
    "api repos/o/r/issues/7/labels -f labels[]=x",
    "api --method PATCH /repos/o/r/issues/7 -f state=closed",
    "api repos/o/r/pulls/7/comments/9/replies --input body.json",
    "api graphql -f query=mutation{x}",
    "api graphql -f 'query=mutation($id:ID!){x}' -F id=5",
    "api graphql -f 'query=mutation($id: ID!) { disablePullRequestAutoMerge(input: {pullRequestId: $id}) { clientMutationId } }' -f id=PR_x",
    "api -F id=5 graphql -f query=mutation{x}",
    "api graphql -fquery=mutation{x}",
    "api -XPATCH repos/o/r/issues/7",
    "api --method=PATCH repos/o/r/issues/7",
    "api repos/o/r/issues/7/labels --field=labels[]=x",
    "issue comment 7 --body x",
    "pr edit 7 --add-label x",
  ];
  const others = [
    "api repos/o/r/issues/7/comments",
    "api -X DELETE repos/o/r/issues/7/labels/x",
    "api -X POST repos/o/r/statuses/abc -f state=success",
    "api graphql -f query=query{viewer{login}}",
    "api graphql -f 'query=query($id:ID!){node(id:$id){id}}' -F id=5",
    "api --method=GET repos/o/r/issues/7/comments -f per_page=1",
    "pr view 7",
  ];
  const judge = (args) => bash(tmpdir(), `api_budget_is_content ${args}`).status === 0;
  for (const args of writes) {
    assert.equal(judge(args), true, args);
  }
  for (const args of others) {
    assert.equal(judge(args), false, args);
  }
});

test("the gh wrapper counts a content write, and the action emits the count and the busiest minute", () =>
  withDir((dir) => {
    guarded(dir, ["201 4000 - {}", "200 4000 - {}", "201 4000 - {}"], 'gh api -X POST repos/o/r/issues/7/comments -f body=x >/dev/null; gh api repos/o/r/issues/7 >/dev/null; gh api repos/o/r/issues/7/labels -f labels[]=y >/dev/null');
    assert.equal(readFileSync(join(dir, "api-budget", "content-creation"), "utf8").trim().split("\n").length, 2);
    writeFileSync(join(dir, "api-budget", "content-creation"), "1792748000\n1792748010\n1792748100\n");
    assert.equal(bash(dir, "api_budget_emit_content").stdout, `${NOTICE}content-creation ${WHERE} count=3 max-per-minute=2\n`);
    // Two writes a second apart across a clock-minute boundary, appended out of order, are in one 60 s window.
    writeFileSync(join(dir, "api-budget", "content-creation"), "1792748040\n1792747000\n1792748039\n");
    assert.equal(bash(dir, "api_budget_emit_content").stdout, `${NOTICE}content-creation ${WHERE} count=3 max-per-minute=2\n`);
    rmSync(join(dir, "api-budget", "content-creation"));
    assert.equal(bash(dir, "api_budget_emit_content").stdout, "");
  }));

test("the action writes the content-creation notice after the token lines", () =>
  withDir((dir) => {
    mkdirSync(join(dir, "api-budget"), { recursive: true });
    writeFileSync(join(dir, "api-budget", "content-creation"), "1792748000\n");
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
        TOKENS: "github-token",
      },
    });
    assert.equal(out, `${NOTICE}content-creation ${WHERE} count=1 max-per-minute=1\n`);
    assert.equal(readFileSync(join(dir, "summary"), "utf8"), `api-budget: content-creation ${WHERE} count=1 max-per-minute=1\n`);
  }));

// Every lane job that calls GitHub through the rate guard names its token and
// ends by logging the budget, so the hub reads each job's spend and its
// content-creating writes.
test("each heavy lane job names its API_BUDGET_TOKEN and ends with the log-api-budget step", () => {
  const jobs = {
    "intake-triage.yml": { "born-triaged": "github-token", "apply-verdict": "lanes-app", "refine-select": "github-token", "apply-refinement": "lanes-app" },
    "intake-label-needs-triage.yml": { "born-triaged": "github-token" },
    "work-resolve-issue.yml": { admit: "github-token", "pick-slot": "github-token", "report-statuses": "github-token" },
    "pr-verify.yml": { "check-intent": "github-token", "check-intent-subscription": "github-token" },
    // label-unblocked's ACTIONS_TOKEN client records under github-token, so
    // that job logs both: [API_BUDGET_TOKEN, the tokens it logs].
    "work-unblock.yml": { "wip-state": "github-token", "label-unblocked": ["lanes-app", "lanes-app github-token"] },
  };
  for (const [file, tokens] of Object.entries(jobs)) {
    const text = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
    for (const [job, names] of Object.entries(tokens)) {
      const [token, logged = token] = [names].flat();
      const block = new RegExp(`\\n  ${job}:\\n([\\s\\S]*?)(?=\\n  [a-z0-9-]+:\\n|$)`).exec(text)?.[1] ?? "";
      assert.match(block, new RegExp(`\\n {6,10}API_BUDGET_TOKEN: ${token}\\n`), `${file} ${job} names ${token}`);
      // pr-verify keeps "Fail without a verdict" as each job's last step.
      const steps = block.split(/\n {6}- name: /).filter((s) => !s.startsWith("Fail without a verdict\n"));
      // Less the blank and comment lines that lead into the next step or job.
      const last = steps.at(-1).replace(/(\n *(#[^\n]*)?)+$/, "");
      assert.match(last, /^Log the API budget at the end\n {8}if: always\(\)\n/, `${file} ${job} ends with the log step`);
      assert.match(last, /uses: \.\/\.base\/\.github\/actions\/log-api-budget /);
      assert.match(last, new RegExp(`\\n {10}tokens: ${logged}\\n?\\s*$`), `${file} ${job} logs ${logged}`);
    }
  }
});

// ci-status has no checkout of the schema, so its wrapper's floor is set in
// the job env, pinned here to the schema default the Node guard reads.
test("ci-status sets the shell read floor to the schema's read-floor default", () => {
  const floor = /\n {6}API_BUDGET_READ_FLOOR: "?([0-9.]+)"?\n/.exec(CI);
  assert.ok(floor, "ci-status sets API_BUDGET_READ_FLOOR");
  assert.equal(Number(floor[1]), apiLimits({ resolvedPath: "" })["github-token"]["read-floor"]);
});

test("ci-status carries api-budget.bash verbatim in its API_BUDGET_SH env", () => {
  const block = /\n {6}API_BUDGET_SH: \|\n((?: {8}[^\n]*\n|\n)+)/.exec(CI);
  assert.ok(block, "ci-status sets API_BUDGET_SH as a block scalar");
  const carried = block[1].replace(/^ {8}/gm, "").replace(/\n+$/, "\n");
  assert.equal(carried, readFileSync(LIB, "utf8"));
});
