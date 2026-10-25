import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { readingLine, recordReading } from "./api-budget.mjs";
import { apiLimits, createRateLimitLatch, poolOf } from "./rate-guard.mjs";

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
  return { stdout: result.stdout, stderr: result.stderr, status: result.status, signal: result.signal };
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

// A stop the wrapper cannot record would leave every later call, in this
// shell or a $(...) subshell, free to reach the exhausted pool: the step ends
// after the one refused call, whichever shell made it. Its two errors reach
// the step's stderr once each, also when the caller holds the subshell's
// stderr in a file it reads only after the call, as gh_read does. That case
// writes the step's stderr to a file: Node gives a child a socket, which
// /proc/$$/fd/2 cannot open, where the runner gives it a pipe.
test("gh guard: a stop it cannot record ends the step after one call, naming the pool", () =>
  withDir((dir) => {
    const main = "gh api repos/o/r >/dev/null || true\ngh api repos/o/r/pulls >/dev/null || true\ngh api graphql -f query=x >/dev/null || true\necho reached";
    const sub = "x=$(gh api repos/o/r) || true\ny=$(gh api repos/o/r/pulls) || true\ngh api graphql -f query=x >/dev/null || true\necho reached";
    const held = 'exec 2>"$RUNNER_TEMP/step-stderr"\nerr=$(mktemp)\nx=$(gh api repos/o/r 2>"$err") || true\ncat "$err" >&2\ngh api repos/o/r/pulls >/dev/null || true\necho reached';
    const unwritable = {
      "an api-budget file where the directory goes": () => writeFileSync(join(dir, "api-budget"), ""),
      "a stop directory where the file goes": () => mkdirSync(join(dir, "api-budget", "stop"), { recursive: true }),
    };
    for (const [how, make] of Object.entries(unwritable)) {
      for (const [shell, script] of Object.entries({ main, sub, "held-stderr": held })) {
        rmSync(join(dir, "api-budget"), { recursive: true, force: true });
        make();
        const out = guarded(dir, ['403 0 - {"message":"API rate limit exceeded"}', "200 4000 - {}", "200 4000 - {}"], script);
        const label = `${how}, ${shell} shell`;
        const stderr = shell === "held-stderr" ? readFileSync(join(dir, "step-stderr"), "utf8") : out.stderr;
        assert.equal(out.calls.length, 1, label);
        assert.notEqual(out.status, 0, label);
        assert.doesNotMatch(out.stdout, /reached/, label);
        assert.match(stderr, /::error::'gh api repos\/o\/r' hit GitHub's core API rate limit[^\n]*\n(?:.*\n)*::error::GitHub's core API stop could not be recorded/, label);
        assert.equal(stderr.match(/::error::/g)?.length, 2, `${label}: ${stderr}`);
      }
    }
  }));

// The stop file is read alike by every port: each stop_files vector, and the
// stops each writer leaves, give the same stop per pool to the shell and the
// Node reader.
const POOL_URLS = {
  core: "https://api.github.com/repos/o/r",
  graphql: "https://api.github.com/graphql",
  search: "https://api.github.com/search/issues?q=x",
  code_search: "https://api.github.com/search/code?q=x",
};

function readBoth(dir, now) {
  const script = `date() { echo ${now}; }\nfor p in ${Object.keys(POOL_URLS).join(" ")}; do echo "$p $(api_budget_stop_until "$p")"; done`;
  const shell = Object.fromEntries(
    bash(dir, script)
      .stdout.trim()
      .split("\n")
      .map((line) => line.split(" "))
      .map(([pool, at]) => [pool, at ? Number(at) : null]),
  );
  const latch = createRateLimitLatch({ now: () => now * 1000, log: () => {}, fail: () => {}, limits: () => ({}), stopFile: join(dir, "api-budget", "stop") });
  const node = Object.fromEntries(Object.entries(POOL_URLS).map(([pool, url]) => [pool, latch.until(url)]));
  return { shell, node };
}

test("the stop file reads the same in the shell and in Node: every stop_files vector", () => {
  const vectors = JSON.parse(readFileSync(new URL("./rate-guard.vectors.json", import.meta.url), "utf8"));
  for (const vector of vectors.stop_files) {
    withDir((dir) => {
      mkdirSync(join(dir, "api-budget"));
      writeFileSync(join(dir, "api-budget", "stop"), vector.text);
      const { shell, node } = readBoth(dir, vectors.vector_now);
      assert.deepEqual(shell, vector.until, `shell: ${vector.name}`);
      assert.deepEqual(node, vector.until, `node: ${vector.name}`);
    });
  }
});

test("the stop file reads the same in the shell and in Node: the stops each writer leaves", async () => {
  const now = JSON.parse(readFileSync(new URL("./rate-guard.vectors.json", import.meta.url), "utf8")).vector_now;
  const until = { core: now + 3600, graphql: now + 60, search: now + 60, code_search: now + 60 };
  withDir((dir) => {
    bash(dir, `api_budget_stop core ${now + 3600} x-ratelimit-reset one || :\napi_budget_stop '*' ${now + 60} retry-after two || :`);
    assert.deepEqual(readBoth(dir, now), { shell: until, node: until });
  });
  const dir = mkdtempSync(join(tmpdir(), "api-budget-"));
  try {
    const answers = [
      new Response("{}", { status: 403, headers: { "x-ratelimit-remaining": "0", "x-ratelimit-reset": String(now + 3600), "x-ratelimit-resource": "core" } }),
      new Response('{"message":"You have exceeded a secondary rate limit."}', { status: 403, headers: { "retry-after": "60" } }),
    ];
    const options = { now: () => now * 1000, log: () => {}, fail: () => {}, limits: () => ({}), stopFile: join(dir, "api-budget", "stop") };
    await createRateLimitLatch(options).observe(POOL_URLS.core, answers[0]);
    await createRateLimitLatch(options).observe(POOL_URLS.graphql, answers[1]);
    assert.deepEqual(readBoth(dir, now), { shell: until, node: until });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

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

// pr-feedback-dispatch.yml's post-verify-notes and rerun-ci-status jobs post
// no other notice, so without these lines their calls go unattributed.
// post-verify-notes' notice covers only its artifact listing, the one call
// that leaves a reading: `gh run download` goes through the gh wrapper but is
// not `gh api`, so it leaves none, and verify-notes.mjs calls through
// address-feedback's createGitHubApi, a plain fetch that keeps no reading.
// That notice understates the job's spend.
const FEEDBACK = new URL("../../workflows/pr-feedback-dispatch.yml", import.meta.url);

// The job's steps, from `  <job>:` to the next job.
function jobText(job) {
  const lines = readFileSync(FEEDBACK, "utf8").split("\n");
  const start = lines.indexOf(`  ${job}:`);
  assert.notEqual(start, -1, job);
  const end = lines.findIndex((line, i) => i > start && /^ {2}[a-z][\w-]*:$/.test(line));
  return lines.slice(start + 1, end === -1 ? undefined : end).join("\n");
}

test("pr-feedback-dispatch.yml: each job that calls the API ends by logging its github-token readings", () => {
  for (const job of ["post-verify-notes", "dispatch", "rerun-ci-status"]) {
    const steps = jobText(job).split("\n      - name: ");
    assert.equal(
      steps.at(-1).split("\n").filter((line, i) => i === 0 || line.startsWith("        ")).join("\n"),
      "Log the API budget at the end\n        if: always()\n        continue-on-error: true\n        timeout-minutes: 1\n" +
        "        uses: ./.base/.github/actions/log-api-budget # zizmor: ignore[self-repository]\n        with:\n          tokens: github-token",
      job,
    );
  }
});

test("pr-feedback-dispatch.yml: post-verify-notes keeps the reading of its artifact listing and decides as before", () =>
  withDir((dir) => {
    const step = jobText("post-verify-notes").split("\n      - name: ").find((text) => text.startsWith("Download the fail verdict"));
    const body = /\n {8}run: \|\n((?: {10}[^\n]*\n|\n)+)/.exec(`${step}\n`)[1].replace(/^ {10}/gm, "");
    for (const sub of [".base/.github/actions/log-api-budget", "bin", "rt"]) {
      mkdirSync(join(dir, sub), { recursive: true });
    }
    copyFileSync(LIB, join(dir, ".base/.github/actions/log-api-budget/api-budget.bash"));
    // A gh that answers `api -i <artifacts route> --jq <filter>` with a header block and no FAIL name.
    writeFileSync(
      join(dir, "bin/gh"),
      `#!/usr/bin/env bash\n[[ $1 == api && $2 == -i && $3 == repos/o/r/actions/runs/77/artifacts* && $4 == --jq ]] || { echo "args: $*" >&2; exit 9; }\n` +
        `printf '${head({ used: 41 }).replace(/\r/g, "\\r").replace(/\n/g, "\\n")}'\n`,
    );
    chmodSync(join(dir, "bin/gh"), 0o755);
    const result = spawnSync("bash", ["-e", "-c", body], {
      cwd: dir,
      encoding: "utf8",
      env: { PATH: `${join(dir, "bin")}:${process.env.PATH}`, RUNNER_TEMP: join(dir, "rt"), RUN_ID: "77", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: join(dir, "out") },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, "::notice::run 77 uploaded no fail verdict; nothing to post\n");
    assert.equal(state(join(dir, "rt"), "github-token"), "200 5000 4959 41 1792748042 core\n");
  }));
