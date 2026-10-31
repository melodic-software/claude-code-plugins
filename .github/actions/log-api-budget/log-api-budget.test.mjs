import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { readingLine, recordReading, routeOf } from "./api-budget.mjs";
import { apiLimits, createRateLimitLatch, PLACEHOLDERS, poolOf, REST_PATH_WORDS, routeOk } from "./rate-guard.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

// Root reads and writes past any file mode, so the permission cases skip.
const ROOT = process.getuid?.() === 0;
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
  const dir = tempDir("api-budget-");
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
    env: { PATH: path, RUNNER_TEMP: dir, TMPDIR: dir, ...RUNNER, ...env },
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
    assert.equal(state(dir, "github-token"), "200 5000 4880 120 1792748042 core other\n");
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
    assert.equal(state(dir, "github-token"), "403 5000 0 5000 1792748042 core {x}\n");
    rmSync(join(dir, "api-budget", "stop"), { force: true });
    // A call that is not `gh api`, or already asks for headers, is passed on as it is.
    for (const args of ["pr view 1", "api route --paginate --jq .", "api --silent route"]) {
      const plain = bash(dir, `api_budget_wrap_gh github-token\ngh ${args}`, { path: `${dir}:${process.env.PATH}` });
      assert.equal(plain.stderr, `args: ${args}\n`);
      assert.equal(plain.status, 9);
    }
  }));

test("api_budget_emit writes the hub line for each reset's last reading, cost since the first with the same reset", () =>
  withDir((dir) => {
    readEach(dir, "github-token", head({ used: 13 }), head({ used: 100, reset: 1792748100 }), head({ used: 328, reset: 1792748100 }));
    assert.equal(
      bash(dir, "api_budget_emit github-token").stdout,
      `${NOTICE}token=github-token ${WHERE} limit=5000 remaining=4987 used=13 reset=1792748042 resource=core cost=na\n` +
        `${NOTICE}token=github-token ${WHERE} limit=5000 remaining=4672 used=328 reset=1792748100 resource=core cost=228\n`,
    );
  }));

test("api_budget_emit writes cost=na for a reset with one reading", () =>
  withDir((dir) => {
    readEach(dir, "lanes-app", head({ used: 900 }), head({ used: 3, reset: 1792751642 }));
    assert.equal(
      bash(dir, "api_budget_emit lanes-app").stdout,
      `${NOTICE}token=lanes-app ${WHERE} limit=5000 remaining=4100 used=900 reset=1792748042 resource=core cost=na\n` +
        `${NOTICE}token=lanes-app ${WHERE} limit=5000 remaining=4997 used=3 reset=1792751642 resource=core cost=na\n`,
    );
  }));

test("api_budget_emit shows both core counters of one token, the job's latest core reading last", () =>
  withDir((dir) => {
    const [A, B] = [1792748042, 1792748500];
    readEach(
      dir,
      "github-token",
      head({ used: 3800, reset: B }),
      head({ used: 1200, reset: A }),
      head({ used: 7, reset: A, resource: "graphql" }),
      head({ used: 3805, reset: B }),
      head({ used: 1210, reset: A }),
    );
    const out = bash(dir, `lines=$(api_budget_emit github-token); printf "%s\\n" "$lines"; echo "last cost \${lines##*cost=}"`).stdout;
    assert.deepEqual(
      out
        .split("\n")
        .filter(Boolean)
        .map((line) => (line.startsWith(NOTICE) ? line.slice(line.indexOf(" used=")) : line)),
      [
        ` used=7 reset=${A} resource=graphql cost=na`,
        ` used=3805 reset=${B} resource=core cost=5`,
        ` used=1210 reset=${A} resource=core cost=10`,
        "last cost 10",
      ],
    );
  }));

test("api_budget_emit keeps a refused reading that is not its counter's last, and does not repeat one that is", () =>
  withDir((dir) => {
    const [A, B] = [1792748042, 1792748500];
    readEach(
      dir,
      "github-token",
      head({ status: 403, used: 5000, reset: A }),
      head({ used: 3900, reset: B }),
      head({ status: 403, used: 3950, reset: B }),
      head({ used: 3960, reset: B }),
    );
    assert.deepEqual(
      bash(dir, "api_budget_emit github-token")
        .stdout.split("\n")
        .filter(Boolean)
        .map((line) => line.slice(line.indexOf(" used="))),
      [` used=3950 reset=${B} resource=core cost=50`, ` used=5000 reset=${A} resource=core cost=na`, ` used=3960 reset=${B} resource=core cost=60`],
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
    assert.equal(readingLine(304, headers), "304 5000 na 12 na na other\n");
    recordReading({ token: "github-token", dir, status: 200, headers });
    recordReading({ token: "", dir, status: 200, headers });
    assert.equal(state(dir, "github-token"), "200 5000 na 12 na na other\n");
    assert.equal(existsSync(join(dir, "api-budget", "lanes-app")), false);
  }));

// [URL or gh api path, route, the names in the input no route may carry].
// A token-shaped segment, built so no secret scanner reads it as one.
const PAT = ["ghp", "abcdefghijklmnopqrstuvwxyz0123456789"].join("_");
const ROUTES = [
  ["https://api.github.com/repos/melodic-software/claude-code-plugins/issues/42/comments?per_page=100&page=2", "repos/{repo}/issues/{n}/comments", ["melodic", "claude-code-plugins", "per_page", "page=2"]],
  ["repos/{owner}/{repo}/pulls/7/files", "repos/{repo}/pulls/{n}/files", ["{owner}"]],
  ["/repos/o/r/commits/0123456789abcdef0123456789abcdef01234567/check-runs", "repos/{repo}/commits/{sha}/check-runs", ["0123456789abcdef"]],
  ["repos/o/r/actions/runs/39931677333/attempts/2/jobs", "repos/{repo}/actions/runs/{n}/attempts/{n}/jobs", ["39931677333"]],
  ["https://api.github.com/graphql", "graphql", []],
  ["https://ghe.example/api/graphql", "graphql", ["ghe.example"]],
  ["https://ghe.example/api/v3/repos/o/r/labels/needs-human", "repos/{repo}/labels/{x}", ["ghe.example", "needs-human"]],
  [`search/issues?q=repo:o/r+is:open&access_token=${PAT}`, "search/issues", [PAT, "access_token", "is:open"]],
  [`repos/o/r/contents/.github/${PAT}`, "repos/{repo}/contents/{x}/{x}", [PAT, ".github"]],
  [`user/${PAT}`, "user/{x}", [PAT]],
  ["user/github_pat_abc", "user/{x}", ["github_pat_abc"]],
  ["repos/o/r/git/ref/heads/feature/fix-it", "repos/{repo}/git/ref/{x}/{x}/{x}", ["feature", "fix-it"]],
  ["repos/o/r/branches/main/protection", "repos/{repo}/branches/{x}/protection", ["main"]],
  ["users/SomeLogin/repos", "users/{x}/repos", ["SomeLogin"]],
  ["repos/o/r/actions/workflows/pr-verify.yml/runs", "repos/{repo}/actions/workflows/{x}/runs", ["pr-verify"]],
  ["repos/o/r/issues/1/comments#frag", "repos/{repo}/issues/{n}/comments", ["frag"]],
  ["repos/o/r/hello world", "repos/{repo}/{x}", ["hello"]],
  ["/repos/o/r/rules/branches/stale-feature-name", "repos/{repo}/rules/branches/{x}", ["stale-feature-name"]],
  ["repos/o/r/branches/feat/secret-topic/protection", "repos/{repo}/branches/{x}/{x}/protection", ["feat", "secret-topic"]],
  ["repos/o/r/commits/release-candidate/status", "repos/{repo}/commits/{x}/status", ["release-candidate"]],
  ["repos/o/r/git/trees/main?recursive=1", "repos/{repo}/git/trees/{x}", ["main", "recursive"]],
  ["repos/o/r/labels/area/ci", "repos/{repo}/labels/{x}/{x}", ["area", "ci"]],
  ["repos/o/r/actions/runners/build-box-seven", "repos/{repo}/actions/{x}/{x}", ["runners", "build-box-seven"]],
  ["repos/someowner", "repos/{x}", ["someowner"]],
  ["applications/Iv1abcdef/token", "{x}/{x}/{x}", ["applications", "Iv1abcdef", "token"]],
  ["https://github.com/someowner/somerepo/pull/5", "other", ["someowner", "somerepo", "github.com"]],
  ["https://uploads.github.com/repos/o/r/releases/9/assets?name=secret-asset.zip", "repos/{repo}/releases/{n}/{x}", ["secret-asset", "assets"]],
  ["rate_limit", "rate_limit", []],
  ["", "other", []],
  ["https://api.github.com/", "other", []],
  [`repos/o/r/${"issues/".repeat(12)}comments`, "other", []],
];

test("routeOf and the shell's api_route template each request path alike, leaking nothing", () =>
  withDir((dir) => {
    const shell = bash(dir, `while IFS= read -r u; do api_budget_route api "$u"; done`, { input: `${ROUTES.map(([url]) => url).join("\n")}\n` });
    const fromShell = shell.stdout.split("\n").slice(0, -1);
    const fromNode = ROUTES.map(([url]) => routeOf(url));
    assert.deepEqual(fromShell, ROUTES.map(([, route]) => route), shell.stderr);
    assert.deepEqual(fromNode, ROUTES.map(([, route]) => route));
    // Every name the input carried is absent from what each templater wrote,
    // and every segment written is a REST path word or a placeholder.
    ROUTES.forEach(([url, , names], i) => {
      for (const out of [fromShell[i], fromNode[i]]) {
        for (const name of names) assert.ok(!out.includes(name), `${url} -> ${out} carries ${name}`);
        assert.ok(routeOk(out), `${url} -> ${out}`);
      }
    });
    // The gh args around the path change nothing.
    assert.equal(bash(dir, "api_budget_route api -X PATCH -H 'Accept: x' --jq .id repos/o/r/issues/3 -f body=hi").stdout, "repos/{repo}/issues/{n}\n");
    assert.equal(bash(dir, "api_budget_route api --method=POST -fquery='query { viewer { login } }' graphql").stdout, "graphql\n");
    assert.equal(bash(dir, "api_budget_route pr view 1").stdout, "other\n");
  }));

test("api-budget.bash's route word list is rate-guard.mjs's REST_PATH_WORDS", () =>
  withDir((dir) => {
    // Every key api_words loads, whatever line adds it, against the JS words
    // and placeholders.
    const keys = bash(dir, `awk "$API_BUDGET_ROUTE"' BEGIN { api_words(); for (k in API_WORD) print k }'`);
    assert.deepEqual(keys.stdout.split("\n").filter(Boolean).sort(), [...REST_PATH_WORDS, ...PLACEHOLDERS].sort(), keys.stderr);
    const placeholders = bash(dir, `awk "$API_BUDGET_ROUTE"' BEGIN { api_words(); for (k in API_WORD) if (k ~ /^[{]/) print k }'`);
    assert.deepEqual(placeholders.stdout.split("\n").filter(Boolean).sort(), [...PLACEHOLDERS].sort());
  }));

test("both writers append the route last, and every reader keeps its fields", () =>
  withDir((dir) => {
    const headers = new Headers({ "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4990", "x-ratelimit-used": "10", "x-ratelimit-reset": "1792748042", "x-ratelimit-resource": "core" });
    assert.equal(readingLine(200, headers, "repos/{repo}/pulls/{n}"), "200 5000 4990 10 1792748042 core repos/{repo}/pulls/{n}\n");
    // A route not in the templater's shape is never written.
    assert.equal(readingLine(200, headers, "repos/o/r?token=x"), "200 5000 4990 10 1792748042 core other\n");
    recordReading({ token: "github-token", dir, status: 200, headers, route: routeOf("https://api.github.com/repos/o/r/pulls/9") });
    bash(dir, `${READ} github-token "$f" 'repos/{repo}/issues/{n}/comments' >/dev/null`, { input: head({ used: 11 }) });
    bash(dir, `${READ} github-token "$f" 'repos/o/r?x=1' >/dev/null`, { input: head({ used: 12 }) });
    assert.equal(
      state(dir, "github-token"),
      "200 5000 4990 10 1792748042 core repos/{repo}/pulls/{n}\n" +
        "200 5000 4989 11 1792748042 core repos/{repo}/issues/{n}/comments\n" +
        "200 5000 4988 12 1792748042 core other\n",
    );
    // api_budget_emit still reads seven-field lines.
    assert.match(bash(dir, "api_budget_emit github-token").stdout, /used=12 reset=1792748042 resource=core cost=2\n$/);
  }));

// [count, route] lines in a token's file, in the order given.
const routeLines = (dir, rows) => {
  mkdirSync(join(dir, "api-budget"), { recursive: true });
  writeFileSync(join(dir, "api-budget", "github-token"), rows.flatMap(([n, line]) => Array(n).fill(`${line}\n`)).join(""));
};

test("api_budget_emit_routes counts N by route, most first, 304s left out, a line with no route as other", () =>
  withDir((dir) => {
    routeLines(dir, [
      [3, "200 5000 1 2 3 core repos/{repo}/issues/{n}/comments"],
      [2, "304 5000 1 2 3 core repos/{repo}/issues/{n}/comments"],
      [2, "request graphql"],
      [2, "request repos/{repo}/pulls/{n}"],
      [1, "200 5000 1 2 3 core"],
      [1, "request"],
      [1, "200 5000 1 2 3 core repos/{repo}/x?y=ghp_1"],
    ]);
    assert.equal(
      bash(dir, "api_budget_emit_routes github-token").stdout,
      "::notice title=api-routes::github-token other=3 repos/{repo}/issues/{n}/comments=3 graphql=2 repos/{repo}/pulls/{n}=2 rest=0\n",
    );
    // The routes sum to api-calls' N.
    assert.equal(bash(dir, "api_budget_emit_calls github-token").stdout, "::notice title=api-calls::github-token=10 not-modified=2 graphql=2\n");
    assert.equal(bash(dir, "api_budget_emit_routes lanes-app").stdout, "::notice title=api-routes::lanes-app rest=0\n");
  }));

test("api_budget_emit_routes names at most 15 routes in at most 1000 bytes and sums the rest", () =>
  withDir((dir) => {
    const words = [...REST_PATH_WORDS].filter((w) => w.length <= 9 && !["api", "v3", "graphql"].includes(w)).slice(0, 20).sort();
    routeLines(dir, words.map((w, i) => [30 - i, `request repos/{repo}/${w}`]));
    const line = bash(dir, "api_budget_emit_routes github-token").stdout;
    const shown = words.slice(0, 15).map((w, i) => `repos/{repo}/${w}=${30 - i}`);
    assert.equal(line, `::notice title=api-routes::github-token ${shown.join(" ")} rest=${15 + 14 + 13 + 12 + 11}\n`);
    // Long routes stop at the byte cap before 15, and the rest holds the others.
    const long = (w) => `repos/{repo}/pending_deployments/requested_reviewers/rerun-failed-jobs/${w}`;
    routeLines(dir, words.map((w, i) => [30 - i, `request ${long(w)}`]));
    const capped = bash(dir, "api_budget_emit_routes github-token").stdout;
    assert.ok(Buffer.byteLength(capped) <= 1001, `${Buffer.byteLength(capped)} bytes`);
    const named = [...capped.matchAll(/ (\S+)=(\d+)/g)].filter(([, route]) => route !== "rest");
    assert.ok(named.length < 15 && named.length > 0);
    assert.deepEqual(named.map(([, route]) => route), words.slice(0, named.length).map(long));
    const total = words.reduce((sum, _, i) => sum + 30 - i, 0);
    assert.equal(named.reduce((sum, [, , n]) => sum + Number(n), 0) + Number(/ rest=(\d+)\n$/.exec(capped)[1]), total);
  }));

test("the action emits each named token, the call count as an api-calls notice the hub reads (0 with no reading), the summary and the calls and costs outputs, and reads no /rate_limit", () =>
  withDir((dir) => {
    // Two calls GitHub counted, then a conditional GET answered 304.
    readEach(dir, "github-token", head({ used: 13 }), head({ used: 41 }), head({ status: 304, used: 41 }));
    const run = /\n {6}run: \|\n([\s\S]*)$/.exec(ACTION)[1].replace(/^ {8}/gm, "");
    writeFileSync(join(dir, "summary"), "");
    writeFileSync(join(dir, "output"), "");
    const out = execFileSync("bash", ["-c", run], {
      encoding: "utf8",
      env: {
        PATH: process.env.PATH,
        ...RUNNER,
        RUNNER_TEMP: dir,
        TMPDIR: dir,
        GITHUB_ACTION_PATH: new URL(".", import.meta.url).pathname,
        GITHUB_STEP_SUMMARY: join(dir, "summary"),
        GITHUB_OUTPUT: join(dir, "output"),
        TOKENS: "lanes-app\ngithub-token",
      },
    });
    assert.equal(
      out,
      "::notice title=api-calls::lanes-app=0 not-modified=0 graphql=0\n" +
        `${NOTICE}token=github-token ${WHERE} limit=5000 remaining=4959 used=41 reset=1792748042 resource=core cost=28\n` +
        "::notice title=api-calls::github-token=2 not-modified=1 graphql=0\n" +
        "::notice title=api-routes::lanes-app rest=0\n::notice title=api-routes::github-token other=2 rest=0\n",
    );
    assert.equal(
      readFileSync(join(dir, "summary"), "utf8"),
      "api-calls lanes-app=0 not-modified=0 graphql=0\n" +
        `api-budget: token=github-token ${WHERE} limit=5000 remaining=4959 used=41 reset=1792748042 resource=core cost=28\n` +
        "api-calls github-token=2 not-modified=1 graphql=0\n" +
        "api-routes lanes-app rest=0\napi-routes github-token other=2 rest=0\ngithub-token-cost=28\n",
    );
    // calls: each token's own requests (2 counted plus a 304 is 2), not the counter's rise (28).
    assert.equal(readFileSync(join(dir, "output"), "utf8"), "calls=lanes-app-calls=0 github-token-calls=2\ncosts=github-token-cost=28\n");
    // With no RUNNER_TEMP there is no api-calls line to read: unknown, never an empty count.
    writeFileSync(join(dir, "output"), "");
    execFileSync("bash", ["-c", run], {
      encoding: "utf8",
      env: { PATH: process.env.PATH, ...RUNNER, RUNNER_TEMP: "", TMPDIR: dir, GITHUB_ACTION_PATH: new URL(".", import.meta.url).pathname, GITHUB_STEP_SUMMARY: join(dir, "summary"), GITHUB_OUTPUT: join(dir, "output"), TOKENS: "github-token" },
    });
    assert.equal(readFileSync(join(dir, "output"), "utf8"), "calls=github-token-calls=unknown\n");
    assert.doesNotMatch(ACTION + readFileSync(LIB, "utf8"), /gh api[^\n]*rate_limit/);
  }));

test("ci-status ends with the same api-budget and api-calls notices the action writes", () =>
  withDir((dir) => {
    readEach(dir, "github-token", head({ used: 13 }), head({ used: 41 }), head({ status: 304, used: 41 }));
    const block = /\n {10}(\[ -z "\$\{API_BUDGET_SH:-\}" \] \|\| \{[^\n]*api_budget_emit github-token;[^\n]*\}\n)/.exec(CI);
    assert.ok(block, "ci-status emits its notices in one block");
    const out = execFileSync("bash", ["-c", block[1]], {
      encoding: "utf8",
      env: { PATH: process.env.PATH, ...RUNNER, RUNNER_TEMP: dir, TMPDIR: dir, API_BUDGET_SH: readFileSync(LIB, "utf8") },
    });
    assert.equal(
      out,
      `${NOTICE}token=github-token ${WHERE} limit=5000 remaining=4959 used=41 reset=1792748042 resource=core cost=28\n` +
        "::notice title=api-calls::github-token=2 not-modified=1 graphql=0\n" +
        "::notice title=api-routes::github-token other=2 rest=0\n",
    );
    // With no reading, no api-budget line and an api-calls count of 0, as the action writes.
    rmSync(join(dir, "api-budget"), { recursive: true });
    assert.equal(
      execFileSync("bash", ["-c", block[1]], { encoding: "utf8", env: { PATH: process.env.PATH, RUNNER_TEMP: dir, TMPDIR: dir, API_BUDGET_SH: readFileSync(LIB, "utf8") } }),
      "::notice title=api-calls::github-token=0 not-modified=0 graphql=0\n::notice title=api-routes::github-token rest=0\n",
    );
  }));

// The shell port of the rate guard decides every shared vector as
// rate-guard.mjs does.
test("api_budget_classify decides every rate-guard vector", () => {
  const vectors = JSON.parse(readFileSync(new URL("./rate-guard.vectors.json", import.meta.url), "utf8"));
  const floor = apiLimits({ resolvedPath: "" })["github-token"]["read-floor"];
  for (const vector of vectors.vectors) {
    const input = { ...vector.input, now: vectors.vector_now * 1000, pool: poolOf(vector.input.url), floor, cap: vector.limit_cap ?? null };
    const out = withDir((dir) => bash(dir, 'jq -c "$API_BUDGET_CLASSIFY"', { input: JSON.stringify(input) }));
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

// A caller that reads the headers itself (-i) is still counted, and a
// conditional GET answered 304 counts as not-modified, which GitHub does not
// charge.
test("gh guard: a -i call is counted in api-calls, and a 304 as not-modified", () =>
  withDir((dir) => {
    const out = guarded(
      dir,
      ["200 4000 - {}", "304 4000 - "],
      'gh api -i repos/o/r >/dev/null\ngh api -i -H "If-None-Match: x" repos/o/r >/dev/null || true\napi_budget_emit_calls github-token',
    );
    assert.equal(out.calls.length, 2);
    assert.equal(out.stdout, "::notice title=api-calls::github-token=1 not-modified=1 graphql=0\n");
  }));

// A gh that plays $RUNNER_TEMP/script, one `<where> <text>` line each: `o`
// stdout, `e` stderr, `n` stderr with no newline, `d` stderr only under
// GH_DEBUG=1, `x` its exit status. The `d` lines are gh 2.103.3's GH_DEBUG=1
// output, recorded from `gh api --paginate repos/<this repo>/labels?per_page=20`
// (three pages), `gh run list --limit 1` (two git lines, two requests) and a
// refused proxy connect.
function scriptedGh(dir, lines) {
  writeFileSync(
    join(dir, "gh"),
    `#!/usr/bin/env bash
echo "$*" >>"$RUNNER_TEMP/calls"
rc=0
while IFS= read -r line; do
  text=\${line:2}
  case \${line:0:1} in
    o) printf '%s\\n' "$text" ;;
    e) printf '%s\\n' "$text" >&2 ;;
    n) printf '%s' "$text" >&2 ;;
    d) [[ \${GH_DEBUG:-} != 1 ]] || printf '%s\\n' "$text" >&2 ;;
    x) rc=$text ;;
  esac
done <"$RUNNER_TEMP/script"
exit "$rc"
`,
  );
  chmodSync(join(dir, "gh"), 0o755);
  writeFileSync(join(dir, "script"), lines.map((line) => `${line}\n`).join(""));
  writeFileSync(join(dir, "calls"), "");
}

const request = (url) => [
  "d * Request at 2026-10-28 17:14:16.342958108 +0000 UTC m=+0.118696845",
  `d * Request to ${url}`,
  "d * Request took 353.479902ms",
];
const LABELS = "https://api.github.com/repositories/1277265216/labels?per_page=20";

// stdout, stderr and status from the same scripted gh, wrapped and bare.
function wrappedAndBare(dir, lines, args) {
  scriptedGh(dir, lines);
  const path = `${dir}:${process.env.PATH}`;
  const wrapped = bash(dir, `api_budget_wrap_gh github-token\ngh ${args}\necho "rc=$?"\napi_budget_emit_calls github-token`, { path });
  rmSync(join(dir, "api-budget"), { recursive: true, force: true });
  const bare = bash(dir, `command gh ${args}\necho "rc=$?"`, { path });
  return { wrapped, bare };
}

test("gh guard: a paginated call of three pages counts three requests, with stdout and stderr as gh wrote them", () =>
  withDir((dir) => {
    const { wrapped, bare } = wrappedAndBare(
      dir,
      [...request("https://api.github.com/repos/o/r/labels?per_page=20"), "o 20", ...request(`${LABELS}&page=2`), "o 20", ...request(`${LABELS}&page=3`), "o 9"],
      "api --paginate repos/o/r/labels --jq length",
    );
    assert.equal(wrapped.stdout, "20\n20\n9\nrc=0\n::notice title=api-calls::github-token=3 not-modified=0 graphql=0\n");
    assert.equal(bare.stdout, "20\n20\n9\nrc=0\n");
    assert.equal(wrapped.stderr, "");
    // A page line is a request, never a reading: no api-budget notice.
    assert.equal(bash(dir, "api_budget_emit github-token").stdout, "");
  }));

test("gh guard: a call that is not gh api counts its requests and drops the git lines debug adds", () =>
  withDir((dir) => {
    const { wrapped, bare } = wrappedAndBare(
      dir,
      [
        "d [git remote -v]",
        "d [git config --get-regexp ^remote\\..*\\.gh-resolved$]",
        ...request("https://api.github.com/repos/o/r/actions/runs?exclude_pull_requests=true&per_page=1"),
        ...request("https://api.github.com/repos/o/r/actions/workflows?page=1&per_page=100"),
        "o []",
      ],
      "run list --limit 1 --json databaseId",
    );
    assert.equal(wrapped.stdout, "[]\nrc=0\n::notice title=api-calls::github-token=2 not-modified=0 graphql=0\n");
    assert.equal(wrapped.stderr, bare.stderr);
  }));

test("gh guard: a failing call keeps gh's stderr byte for byte and its status", () =>
  withDir((dir) => {
    const { wrapped, bare } = wrappedAndBare(
      dir,
      [
        "d * Request at 2026-10-28 17:23:22.386063392 +0000 UTC m=+0.074866727",
        "d * Request to https://api.github.com/rate_limit",
        "d * proxyconnect tcp: dial tcp 127.0.0.1:9: connect: connection refused",
        "d * Request took 293.912µs",
        'e Get "https://api.github.com/rate_limit": proxyconnect tcp: dial tcp 127.0.0.1:9: connect: connection refused',
        "e error connecting to api.github.com",
        "d lookup api.github.com: no such host",
        "e check your internet connection or https://githubstatus.com",
        "e * a line of gh's own, outside any request",
        "e ",
        "n gh: Not Found (HTTP 404)",
        "x 1",
      ],
      "pr view 7",
    );
    assert.equal(bare.stderr.endsWith("gh: Not Found (HTTP 404)"), true);
    assert.equal(wrapped.stderr, bare.stderr);
    assert.equal(wrapped.stdout, "rc=1\n::notice title=api-calls::github-token=1 not-modified=0 graphql=0\n");
  }));

test("gh guard: a header-read call counts each request once, a 304 still as not-modified, and a download host not at all", () =>
  withDir((dir) => {
    const head304 = "o HTTP/2.0 304 Not Modified";
    // One request, read from its header block: one call, not two.
    let out = wrappedAndBare(dir, [...request("https://api.github.com/repos/o/r"), head304, "o ", "x 1"], 'api -i -H "If-None-Match: x" repos/o/r').wrapped;
    assert.equal(out.stdout.split("\n").at(-2), "::notice title=api-calls::github-token=0 not-modified=1 graphql=0");
    // A redirect the header block does not show is a second request.
    out = wrappedAndBare(dir, [...request("https://api.github.com/repos/o/old"), ...request("https://api.github.com/repositories/1"), "o HTTP/2.0 200 OK", "o ", "o {}"], "api repos/o/old").wrapped;
    assert.equal(out.stdout, "{}\nrc=0\n::notice title=api-calls::github-token=2 not-modified=0 graphql=0\n");
    // A download redirect leaves GitHub's API, so it spends nothing there.
    out = wrappedAndBare(
      dir,
      [...request("https://api.github.com/repos/o/r/actions/runs/1/logs"), ...request("https://results-receiver.actions.githubusercontent.com/x")],
      "run view 1 --log",
    ).wrapped;
    assert.equal(out.stdout, "rc=0\n::notice title=api-calls::github-token=1 not-modified=0 graphql=0\n");
  }));

test("gh guard: a GraphQL request is counted among the requests and again as graphql, from a request line or a reading", () =>
  withDir((dir) => {
    // gh pr view: one GraphQL request, one REST request.
    let out = wrappedAndBare(dir, [...request("https://api.github.com/graphql"), ...request("https://api.github.com/repos/o/r/pulls/7"), "o {}"], "pr view 7 --json number").wrapped;
    assert.equal(out.stdout, "{}\nrc=0\n::notice title=api-calls::github-token=2 not-modified=0 graphql=1\n");
    // gh api graphql, read from its header block: one reading whose resource is graphql.
    out = wrappedAndBare(
      dir,
      [...request("https://api.github.com/graphql"), "o HTTP/2.0 200 OK", "o X-Ratelimit-Resource: graphql", "o ", "o {}"],
      "api graphql -f query=x",
    ).wrapped;
    assert.equal(out.stdout, "{}\nrc=0\n::notice title=api-calls::github-token=1 not-modified=0 graphql=1\n");
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
// after the one refused call, whichever shell made it, and no call follows
// from a retry loop in a capture around it. Its two errors reach the step's
// stderr once each, also when the caller holds the subshell's stderr in a
// file it reads only after the call, as gh_read does. Node gives the step a
// socket for stderr, which /proc/$$/fd/2 cannot open.
test("gh guard: a stop it cannot record ends the step after one call, naming the pool", { skip: ROOT && "root writes past any file mode" }, () =>
  withDir((dir) => {
    const main = "gh api repos/o/r >/dev/null || true\ngh api repos/o/r/pulls >/dev/null || true\ngh api graphql -f query=x >/dev/null || true\necho reached";
    const sub = "x=$(gh api repos/o/r) || true\ny=$(gh api repos/o/r/pulls) || true\ngh api graphql -f query=x >/dev/null || true\necho reached";
    const retry = "sleep() { :; }\nx=$(for a in 1 2 3; do y=$(gh api repos/o/r) && break; sleep 5; done) || true\necho reached";
    const held = 'err=$(mktemp)\nx=$(gh api repos/o/r 2>"$err") || true\ncat "$err" >&2\ngh api repos/o/r/pulls >/dev/null || true\necho reached';
    // Readable but not writable: a stop file that cannot be read stops every
    // pool before any call (stop_file_errors).
    const unwritable = {
      "a read-only api-budget directory": () => {
        mkdirSync(join(dir, "api-budget"));
        chmodSync(join(dir, "api-budget"), 0o555);
      },
      "a read-only stop file": () => {
        mkdirSync(join(dir, "api-budget"));
        writeFileSync(join(dir, "api-budget", "stop"), "");
        chmodSync(join(dir, "api-budget", "stop"), 0o444);
      },
    };
    for (const [how, make] of Object.entries(unwritable)) {
      for (const [shell, script] of Object.entries({ main, sub, retry, "held-stderr": held })) {
        unlock(dir);
        make();
        const out = guarded(dir, ['403 0 - {"message":"API rate limit exceeded"}', "200 4000 - {}", "200 4000 - {}"], script);
        const label = `${how}, ${shell} shell`;
        const { stderr } = out;
        assert.equal(out.calls.length, 1, label);
        assert.notEqual(out.status, 0, label);
        assert.doesNotMatch(out.stdout, /reached/, label);
        assert.match(stderr, /::error::'gh api repos\/o\/r' hit GitHub's core API rate limit[^\n]*\n(?:.*\n)*::error::GitHub's core API stop could not be recorded/, label);
        assert.equal(stderr.match(/::error::/g)?.length, 2, `${label}: ${stderr}`);
      }
    }
    unlock(dir);
  }));

// Removes $RUNNER_TEMP/api-budget, read-only or not.
function unlock(dir) {
  const budget = join(dir, "api-budget");
  if (existsSync(budget)) {
    chmodSync(budget, 0o755);
  }
  rmSync(budget, { recursive: true, force: true });
}

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

// stop_file_errors: a stop file that exists but cannot be read holds every
// pool in both readers, with an error naming it; a missing one holds nothing.
test("the stop file reads the same in the shell and in Node: every stop_file_errors vector", () => {
  const vectors = JSON.parse(readFileSync(new URL("./rate-guard.vectors.json", import.meta.url), "utf8"));
  for (const vector of vectors.stop_file_errors) {
    if (vector.error === "EACCES" && ROOT) {
      continue;
    }
    withDir((dir) => {
      const budget = join(dir, "api-budget");
      const stop = join(budget, "stop");
      if (vector.layout === "api-budget-is-file") {
        writeFileSync(budget, "");
      } else {
        mkdirSync(budget);
      }
      if (vector.layout === "stop-unreadable") {
        writeFileSync(stop, "core 1792751600\n");
        chmodSync(stop, 0o000);
      } else if (vector.layout === "stop-is-directory") {
        mkdirSync(stop);
      } else if (vector.layout === "api-budget-unsearchable") {
        writeFileSync(stop, "core 1792751600\n");
        chmodSync(budget, 0o600);
      }
      const lines = [];
      const latch = createRateLimitLatch({ now: () => vectors.vector_now * 1000, log: (line) => lines.push(line), fail: () => {}, limits: () => ({}), stopFile: stop });
      const node = Object.fromEntries(Object.entries(POOL_URLS).map(([pool, url]) => [pool, latch.until(url)]));
      const out = bash(dir, `date() { echo ${vectors.vector_now}; }\nfor p in ${Object.keys(POOL_URLS).join(" ")}; do echo "$p $(api_budget_stop_until "$p")"; done`);
      const shell = Object.fromEntries(
        out.stdout
          .trim()
          .split("\n")
          .map((line) => line.split(" "))
          .map(([pool, at]) => [pool, at ? Number(at) : null]),
      );
      assert.deepEqual(shell, vector.until, `shell: ${vector.name}`);
      assert.deepEqual(node, vector.until, `node: ${vector.name}`);
      const named = `the rate guard's stop file ${stop} cannot be read`;
      const shellErrors = out.stderr.split("\n").filter((line) => line.startsWith("::error::"));
      const nodeErrors = lines.filter((line) => line.startsWith("::error::"));
      if (vector.error === "ENOENT") {
        assert.deepEqual([shellErrors, nodeErrors], [[], []], vector.name);
      } else {
        assert.ok(shellErrors.length === 4 && shellErrors.every((line) => line.includes(named)), `shell: ${vector.name}: ${out.stderr}`);
        assert.ok(nodeErrors.length === 1 && nodeErrors[0].includes(named), `node: ${vector.name}: ${lines}`);
      }
      if (vector.layout === "api-budget-unsearchable") {
        chmodSync(budget, 0o755);
      }
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
  const dir = tempDir("api-budget-");
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
    'api -H "Accept: x" repos/o/r/issues/7/comments -f body=x',
    "api --hostname h repos/o/r/issues/7/comments -f body=x",
    "api -p x repos/o/r/issues/7/comments -f body=x",
    "api -X=POST repos/o/r/issues/7/comments",
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
  const judge = (args) => withDir((dir) => bash(dir, `api_budget_is_content ${args}`)).status === 0;
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
        TMPDIR: dir,
        GITHUB_ACTION_PATH: new URL(".", import.meta.url).pathname,
        GITHUB_STEP_SUMMARY: join(dir, "summary"),
        GITHUB_OUTPUT: join(dir, "output"),
        TOKENS: "github-token",
      },
    });
    assert.equal(out, `::notice title=api-calls::github-token=0 not-modified=0 graphql=0\n${NOTICE}content-creation ${WHERE} count=1 max-per-minute=1\n::notice title=api-routes::github-token rest=0\n`);
    assert.equal(
      readFileSync(join(dir, "summary"), "utf8"),
      `api-calls github-token=0 not-modified=0 graphql=0\napi-budget: content-creation ${WHERE} count=1 max-per-minute=1\napi-routes github-token rest=0\n`,
    );
  }));

// Every lane job that calls GitHub through the rate guard names its token and
// ends by logging the budget, so the hub reads each job's spend and its
// content-creating writes.
test("each heavy lane job names its API_BUDGET_TOKEN and ends with the log-api-budget step", () => {
  const jobs = {
    // apply-verdict's resolve-config reads with the job token, recorded under github-token.
    "intake-triage.yml": { "born-triaged": "github-token", "apply-verdict": ["lanes-app", "lanes-app github-token"], "refine-select": "github-token", "apply-refinement": "lanes-app" },
    "work-resolve-issue.yml": { admit: "github-token", "pick-slot": "github-token", "report-statuses": "github-token" },
    "pr-verify.yml": { "check-intent": "github-token", "check-intent-subscription": "github-token", "check-intent-fallback": "github-token" },
    // label-unblocked's ACTIONS_TOKEN client records under github-token, so
    // that job logs both: [API_BUDGET_TOKEN, the tokens it logs].
    "work-unblock.yml": { "wip-state": "github-token", "label-unblocked": ["lanes-app", "lanes-app github-token"] },
    "pr-merge.yml": { "post-merge-dispatch": "github-token" },
    "intake-reenter.yml": { reenter: "github-token" },
    "security-outside-actor.yml": { flag: "github-token" },
    "pr-feedback-dispatch.yml": { "post-verify-notes": "github-token", dispatch: "github-token", "rerun-ci-status": "github-token" },
    "post-merge-test-mutation.yml": { report: "github-token" },
    "pr-refine.yml": { "fix-docs-head": "github-token" },
    "post-merge-demotion-alert.yml": { alert: "github-token", "report-red-main": "github-token" },
    // Every step job but the handoff jobs, whose shape callers.test.mjs pins.
    "pr-unblock.yml": Object.fromEntries(
      ["resolve-conflicts-not-run", "conflict-scan-refusal", "address-feedback-not-run", "review-dependency-not-run", "fix-ci-not-run", "fix-ci-unreported", "report-stop-status"].map((job) => [job, "github-token"]),
    ),
    "pr-review-hosted.yml": { "resolve-model": "github-token", "kill-switch": "github-token" },
    "pr-review-security-hosted.yml": { "resolve-model": "github-token", "kill-switch": "github-token" },
    // Not run (head code) or scan (a key, and no other action from a checkout).
    "pr-run-activity-read.yml": { "broker-check": "github-token", "issue-fields": "github-token", summary: "github-token", report: "github-token" },
    "pr-run-activity-write.yml": { report: "github-token" },
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
      assert.match(last, /^Log the API budget[^\n]*\n {8}if: always\(\)\n/, `${file} ${job} ends with the log step`);
      assert.match(last, /uses: \.\/\.base\/\.github\/actions\/log-api-budget /);
      assert.match(last, new RegExp(`\\n {10}tokens: ${logged}\\n?\\s*$`), `${file} ${job} logs ${logged}`);
    }
  }
});

// A job's shell steps call gh through api-budget.bash's wrapper, so the
// job-end step has their readings to count; a step that sends gh before it
// wraps would leave those calls out.
test("each shell step in the demotion alert job that calls gh wraps it first", () => {
  const text = readFileSync(new URL("../../workflows/post-merge-demotion-alert.yml", import.meta.url), "utf8");
  const block = /\n  alert:\n([\s\S]*?)(?=\n  [a-z0-9-]+:\n|$)/.exec(text)?.[1] ?? "";
  const wrap = "{ . .base/.github/actions/log-api-budget/api-budget.bash 2>/dev/null && api_budget_wrap_gh github-token; } || true";
  const calling = block.split(/\n {6}- name: /).filter((step) => /^ {10}[^#\n]*\bgh api\b/m.test(step));
  assert.ok(calling.length >= 2, "the alert job's gh-calling steps are found");
  for (const step of calling) {
    const run = step.indexOf("        run: |\n");
    assert.ok(run > 0, `${step.split("\n")[0]} is a run step`);
    const at = step.indexOf(wrap);
    assert.ok(at > run && at < step.search(/^ {10}[^#\n]*\bgh api\b/m), `${step.split("\n")[0]} wraps gh before its first call`);
  }
});

// pr-review-main's record job has no checkout of the action, and its only
// calls are one check-run POST per verdict file, so it counts them itself and
// ends with the notice in api_budget_emit_calls' shape.
test("pr-review-main's record job ends with its own api-calls notice in the emitter's shape", () =>
  withDir((dir) => {
    const text = readFileSync(new URL("../../workflows/pr-review-main.yml", import.meta.url), "utf8");
    const block = /\n  record:\n([\s\S]*?)(?=\n  [a-z0-9-]+:\n|$)/.exec(text)?.[1] ?? "";
    const last = block.split(/\n {6}- name: /).at(-1);
    assert.match(last, /^Log the API calls at the end\n {8}if: always\(\)\n/);
    const run = /\n {8}run: \|\n((?: {10}[^\n]*\n?)+)/.exec(last)?.[1].replace(/^ {10}/gm, "");
    assert.ok(run, "the step has a run block");
    const lib = new URL("api-budget.bash", import.meta.url).pathname;
    const emitted = (count) => {
      if (count !== undefined) writeFileSync(join(dir, "pr-review-main-calls"), `${count}\n`);
      // As Actions runs `shell: bash`: -e ends the step on any failing command.
      return execFileSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", "-c", run], { encoding: "utf8", env: { PATH: process.env.PATH, RUNNER_TEMP: dir, TMPDIR: dir } });
    };
    const shape = execFileSync("bash", ["-c", `. "${lib}"; api_budget_emit_calls github-token`], { encoding: "utf8", env: { PATH: process.env.PATH, RUNNER_TEMP: dir, TMPDIR: dir } });
    assert.equal(emitted(), shape, "no count file is 0, as the emitter writes with no reading");
    assert.equal(emitted(2), shape.replace("github-token=0", "github-token=2"));
    assert.equal(emitted("2; rm"), shape, "anything but a count is 0");
  }));

// Jobs that hold the job token but call GitHub only through actions the
// counter cannot see still end by logging it, so each run carries its
// api-calls line, 0 when no step of the job's own called GitHub.
test("each job that holds the job token and calls no guarded client ends with the log-api-budget step", () => {
  const windows = ["select-tests-windows", ...["rename-1", "rename-2", "secrets", "guards", "hooks", "lib", "worktree"].map((s) => `test-windows-${s}`), "test-macos-planning-shared"];
  const jobs = {
    "pr-test-platforms.yml": Object.fromEntries(windows.map((job) => [job, "./"])),
    "post-merge-detect-silent-revert.yml": { "detect-silent-revert": "./" },
    "release-publish-plugins.yml": { merge: "./", build: "./" },
    "dependabot-fragments.yml": { write: "./" },
    "pr-require-checks.yml": { "lint-repo": "./", "lint-shell": "./", "check-plugins": "./", "check-skills": "./" },
  };
  for (const [file, byJob] of Object.entries(jobs)) {
    const text = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
    for (const [job, root] of Object.entries(byJob)) {
      const block = new RegExp(`\\n  ${job}:\\n([\\s\\S]*?)(?=\\n  [a-z0-9-]+:\\n|$)`).exec(text)?.[1] ?? "";
      const last = block.split(/\n {6}- name: /).at(-1).replace(/(\n *(#[^\n]*)?)+$/, "");
      assert.equal(
        last,
        // check-lane-coverage reads a continue-on-error step in this workflow as a gate.
        `Log the API budget at the end\n        if: always()\n${file === "pr-require-checks.yml" ? "" : "        continue-on-error: true\n"}        timeout-minutes: 1\n` +
          `        uses: ${root}.github/actions/log-api-budget # zizmor: ignore[self-repository]\n        with:\n          tokens: github-token`,
        `${file} ${job}`,
      );
    }
  }
});

// 950 used of a header limit of 5000 leaves 50 of a planned 1000, under a
// floor of 100; without the cap the same reading is far over its floor.
test("gh guard: API_BUDGET_LIMIT_CAP plans the floor to the cap, and only the header's remaining stops", () =>
  withDir((dir) => {
    const capped = guarded(dir, ["200 4050 - {}", "200 4050 - {}"], "gh api repos/o/r >/dev/null; gh api repos/o/r >/dev/null", { API_BUDGET_READ_FLOOR: "0.1", API_BUDGET_LIMIT_CAP: "1000" });
    assert.equal(capped.calls.length, 2);
    assert.equal(capped.stderr.match(/::warning::/g)?.length, 1);
    assert.equal(capped.status, 0);
  }));

test("gh guard: with no API_BUDGET_LIMIT_CAP the floor is a share of the header limit", () =>
  withDir((dir) => {
    const out = guarded(dir, ["200 4050 - {}"], "gh api repos/o/r >/dev/null", { API_BUDGET_READ_FLOOR: "0.1" });
    assert.equal(out.stderr, "");
  }));

// ci-status runs on GITHUB_TOKEN, so its cap is github-token's limit-cap
// default, pinned here as the floor is below.
test("ci-status sets the shell limit cap to github-token's limit-cap default", () => {
  const cap = /\n {6}API_BUDGET_LIMIT_CAP: "?([0-9]+)"?\n/.exec(CI);
  assert.ok(cap, "ci-status sets API_BUDGET_LIMIT_CAP");
  assert.equal(Number(cap[1]), apiLimits({ resolvedPath: "" })["github-token"]["limit-cap"]);
});

// ci-status has no checkout of rate-limits.json, so its wrapper's floor is set in
// the job env, pinned here to the rate-limits.json default the Node guard reads.
test("ci-status sets the shell read floor to the read-floor default", () => {
  const floor = /\n {6}API_BUDGET_READ_FLOOR: "?([0-9.]+)"?\n/.exec(CI);
  assert.ok(floor, "ci-status sets API_BUDGET_READ_FLOOR");
  assert.equal(Number(floor[1]), apiLimits({ resolvedPath: "" })["github-token"]["read-floor"]);
});

test("ci-status and mark-lanes carry api-budget.bash verbatim in their API_BUDGET_SH env", () => {
  const blocks = [...CI.matchAll(/\n( +)API_BUDGET_SH: \|\n((?:\1 {2}[^\n]*\n|\n)+)/g)];
  assert.deepEqual(
    blocks.map(([, pad]) => pad.length),
    [10, 6],
    "the mark-lanes step, then the ci-status job, set API_BUDGET_SH as a block scalar",
  );
  for (const [, pad, body] of blocks) {
    const carried = body.replace(new RegExp(`^${pad} {2}`, "gm"), "").replace(/\n+$/, "\n");
    assert.equal(carried, readFileSync(LIB, "utf8"));
  }
});

// The mark-lanes step as shipped, against a gh that answers `api -i`, failing
// its first `fails` calls. RUNNER_TEMP holds the fake and the readings.
function markLanes(dir, fails) {
  const job = CI.slice(CI.indexOf("\n  mark-lanes:\n"), CI.indexOf("\n  select-tests:\n"));
  const body = /\n {8}run: \|\n((?: {10}[^\n]*\n)+)/.exec(job)[1].replace(/^ {10}/gm, "").replace(/sleep \$\(\(attempt \* 5\)\)/, ":");
  const answer = head({ used: 12 }).replace(/\r/g, "\\r").replace(/\n/g, "\\n");
  writeFileSync(
    join(dir, "gh"),
    `#!/usr/bin/env bash\nn=$(($(cat "${dir}/n" 2>/dev/null || echo 0) + 1)); echo "$n" >"${dir}/n"\n` +
      `[[ $1 == api && $2 == -i ]] || exit 9\n[ -z "\${GH_DEBUG:-}" ] || echo "* Request to https://api.github.com/x" >&2\n` +
      `printf '${answer}{}'\n((n > ${fails}))\n`,
  );
  chmodSync(join(dir, "gh"), 0o755);
  return spawnSync("bash", ["-e", "-c", body], {
    encoding: "utf8",
    env: { PATH: `${dir}:${process.env.PATH}`, ...RUNNER, RUNNER_TEMP: dir, TMPDIR: dir, API_BUDGET_SH: readFileSync(LIB, "utf8"), HEAD_SHA: "a", GITHUB_REPOSITORY: "o/r", GITHUB_SERVER_URL: "s", GH_TOKEN: "t" },
  });
}

test("mark-lanes counts its status write, and each retry of it", () =>
  withDir((dir) => {
    const once = markLanes(dir, 0);
    assert.equal(once.status, 0, once.stderr);
    assert.match(once.stdout, /^Marked ci-lanes pending on a\.$/m);
    assert.match(once.stdout, /used=12 reset=1792748042 resource=core cost=na\n/);
    assert.match(once.stdout, /^::notice title=api-calls::github-token=1 not-modified=0 graphql=0$/m);
    rmSync(join(dir, "api-budget"), { recursive: true });
    rmSync(join(dir, "n"));
    const retried = markLanes(dir, 1);
    assert.equal(retried.status, 0, retried.stderr);
    assert.match(retried.stdout, /^::notice title=api-calls::github-token=2 not-modified=0 graphql=0$/m);
  }));

test("mark-lanes still fails, and still reports its calls, when every attempt fails", () =>
  withDir((dir) => {
    const out = markLanes(dir, 3);
    assert.equal(out.status, 1);
    assert.match(out.stdout, /^::error::could not mark ci-lanes pending on a;/m);
    assert.match(out.stdout, /^::notice title=api-calls::github-token=3 not-modified=0 graphql=0$/m);
  }));

test("ci-status emits the api-calls notice beside its api-budget notice", () => {
  assert.match(CI, /api_budget_emit github-token; api_budget_emit_calls github-token; /);
});

// pr-feedback-dispatch.yml's post-verify-notes and rerun-ci-status jobs post
// no other notice, so without these lines their calls go unattributed.
// post-verify-notes' notice covers its artifact listing and verify-notes.mjs's
// calls, which go through the rate guard; `gh run download` goes through the
// gh wrapper but is not `gh api`, so it leaves none.
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

// The wrapper keeps a copy of the stderr it is set up under, so a setup line
// that sends its own stderr to /dev/null would swallow the unrecorded-stop errors.
test("pr-feedback-dispatch.yml: the wrapper setup keeps the step's stderr for an unrecorded stop's errors", { skip: ROOT && "root writes past any file mode" }, () =>
  withDir((dir) => {
    const setups = readFileSync(FEEDBACK, "utf8")
      .split("\n")
      .filter((line) => line.includes("api_budget_wrap_gh github-token"))
      .map((line) => line.trim());
    assert.ok(setups.length > 0);
    mkdirSync(join(dir, ".base/.github/actions/log-api-budget"), { recursive: true });
    copyFileSync(LIB, join(dir, ".base/.github/actions/log-api-budget/api-budget.bash"));
    stubGh(dir);
    for (const setup of new Set(setups)) {
      writeFileSync(join(dir, "answers"), '403 0 - {"message":"API rate limit exceeded"}\n200 4000 - {}\n');
      writeFileSync(join(dir, "calls"), "");
      unlock(dir);
      mkdirSync(join(dir, "api-budget"));
      chmodSync(join(dir, "api-budget"), 0o555);
      const result = spawnSync("bash", ["-c", `${setup}\nx=$(gh api repos/o/r) || true\ngh api repos/o/r >/dev/null || true\necho reached`], {
        cwd: dir,
        encoding: "utf8",
        env: { PATH: `${dir}:${process.env.PATH}`, RUNNER_TEMP: dir, TMPDIR: dir },
      });
      assert.equal(readFileSync(join(dir, "calls"), "utf8").split("\n").filter(Boolean).length, 1, setup);
      assert.doesNotMatch(result.stdout, /reached/, setup);
      assert.match(result.stderr, /::error::'gh api repos\/o\/r' hit GitHub's core API rate limit[^\n]*\n(?:.*\n)*::error::GitHub's core API stop could not be recorded/, setup);
    }
    unlock(dir);
  }));

test("pr-feedback-dispatch.yml: post-verify-notes keeps the reading of its artifact listing and decides as before", () =>
  withDir((dir) => {
    const step = jobText("post-verify-notes").split("\n      - name: ").find((text) => text.startsWith("Download the verdict"));
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
      env: { PATH: `${join(dir, "bin")}:${process.env.PATH}`, RUNNER_TEMP: join(dir, "rt"), TMPDIR: dir, RUN_ID: "77", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: join(dir, "out") },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, "::notice::run 77 uploaded no verdict; nothing to post\n");
    assert.equal(state(join(dir, "rt"), "github-token"), "200 5000 4959 41 1792748042 core repos/{repo}/actions/runs/{n}/artifacts\n");
  }));

test("the gh wrapper routes each traced request by its URL", () =>
  withDir((dir) => {
    scriptedGh(dir, [
      ...request("https://api.github.com/repos/o/r/pulls?per_page=100&page=1"),
      ...request("https://api.github.com/repos/o/r/pulls?per_page=100&page=2"),
      ...request("https://api.github.com/graphql"),
    ]);
    const path = `${dir}:${process.env.PATH}`;
    bash(dir, "api_budget_wrap_gh github-token\ngh api --paginate 'repos/o/r/pulls?per_page=100' >/dev/null", { path });
    assert.equal(state(dir, "github-token"), "request repos/{repo}/pulls\nrequest repos/{repo}/pulls\nrequest graphql\n");
    const calls = bash(dir, "api_budget_emit_calls github-token").stdout;
    assert.equal(calls, "::notice title=api-calls::github-token=3 not-modified=0 graphql=1\n");
  }));
