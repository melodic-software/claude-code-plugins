import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { apiLimits, classify, createRateLimitLatch, entryOf, isContentWrite, poolOf, RateLimitStop } from "./rate-guard.mjs";

const VECTORS = JSON.parse(readFileSync(new URL("./rate-guard.vectors.json", import.meta.url), "utf8"));
const SCHEMA_PATH = new URL("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json", import.meta.url);
const NOW = VECTORS.vector_now * 1000;
// Root reads and writes past any file mode, so the permission cases skip.
const ROOT = process.getuid?.() === 0;
const READ_FLOOR = apiLimits({ resolvedPath: "" })["github-token"]["read-floor"];

// Runs fn in a fresh directory, removed once fn (sync or async) is done.
async function withDir(fn) {
  const dir = mkdtempSync(join(tmpdir(), "rate-guard-"));
  try {
    return await fn(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("the vectors file holds at least twelve well-formed vectors", () => {
  assert.ok(Number.isInteger(VECTORS.vector_now));
  assert.ok(VECTORS.vectors.length >= 12);
  for (const vector of VECTORS.vectors) {
    assert.deepEqual(Object.keys(vector.input).sort(), ["body", "headers", "status", "url"], vector.name);
    assert.ok(!("limit_cap" in vector) || Number.isInteger(vector.limit_cap), vector.name);
    assert.deepEqual(Object.keys(vector.expect).sort(), ["latched", "low", "pool", "reset", "reset_source"], vector.name);
    assert.ok(Object.keys(vector.input.headers).every((name) => name === name.toLowerCase()), vector.name);
  }
});

for (const vector of VECTORS.vectors) {
  test(`vector: ${vector.name}`, () => {
    assert.deepEqual(classify(vector.input, { now: NOW, readFloor: READ_FLOOR, limitCap: vector.limit_cap ?? null }), vector.expect);
  });
}

test("classify reads a Headers object as it reads a plain one", () => {
  const vector = VECTORS.vectors.find((v) => v.expect.reset_source === "retry-after");
  const headers = new Headers(vector.input.headers);
  assert.deepEqual(classify({ ...vector.input, headers }, { now: NOW, readFloor: READ_FLOOR }), vector.expect);
});

test("defaults come from the schema: a changed schema default changes the module's", () =>
  withDir((dir) => {
    const schema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
    const live = apiLimits({ resolvedPath: "", schemaPath: SCHEMA_PATH });
    schema.$defs["api-pool"].properties["read-floor"].default = 0.25;
    schema.$defs["api-content-pool"].properties["per-minute"].default = 7;
    const path = join(dir, "schema.json");
    writeFileSync(path, JSON.stringify(schema));
    const changed = apiLimits({ resolvedPath: "", schemaPath: path });
    for (const name of ["github-token", "lanes-app", "graphql", "owner-token", "content-creation"]) {
      assert.equal(changed[name]["read-floor"], 0.25, name);
      assert.notEqual(live[name]["read-floor"], 0.25, name);
    }
    assert.equal(changed["content-creation"]["per-minute"], 7);
    assert.equal(changed["github-token"]["per-minute"], undefined);
  }));

// github-token plans to a limit-cap of 1,000, the figure GitHub documents for
// GITHUB_TOKEN per repository per hour
// (https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#primary-rate-limit-for-github_token-in-github-actions).
// That is a planning cap, not this repository's live limit: its responses
// report x-ratelimit-limit 5000. The other pools plan to the limit their
// header reports.
test("limit-cap defaults to 1000 for github-token only", () => {
  const limits = apiLimits({ resolvedPath: "" });
  assert.equal(limits["github-token"]["limit-cap"], 1000);
  for (const name of ["lanes-app", "graphql", "owner-token", "content-creation"]) {
    assert.equal(limits[name]["limit-cap"], undefined, name);
  }
});

test("a resolved limit-cap caps another pool, and another github-token field keeps its cap", () =>
  withDir((dir) => {
    const path = join(dir, "resolved.json");
    writeFileSync(path, JSON.stringify({ limits: { api: { "github-token": { "read-floor": 0.2 }, "lanes-app": { "limit-cap": 4000 } } } }));
    const limits = apiLimits({ resolvedPath: path });
    assert.equal(limits["github-token"]["limit-cap"], 1000);
    assert.equal(limits["github-token"]["read-floor"], 0.2);
    assert.equal(limits["lanes-app"]["limit-cap"], 4000);
  }));

test("a resolved config's limits.api overrides the schema default for that field only", () =>
  withDir((dir) => {
    const path = join(dir, "resolved.json");
    writeFileSync(path, JSON.stringify({ limits: { api: { "lanes-app": { "read-floor": 0.3 } } } }));
    const limits = apiLimits({ resolvedPath: path });
    const defaults = apiLimits({ resolvedPath: "" });
    assert.equal(limits["lanes-app"]["read-floor"], 0.3);
    assert.equal(limits["lanes-app"].plan, defaults["lanes-app"].plan);
    assert.deepEqual(limits["github-token"], defaults["github-token"]);
  }));

test("poolOf and entryOf name the resource and its config entry", () => {
  assert.equal(poolOf("https://api.github.com/graphql"), "graphql");
  assert.equal(poolOf("https://api.github.com/search/issues?q=a"), "search");
  assert.equal(poolOf("https://api.github.com/search/code?q=a"), "code_search");
  assert.equal(poolOf("https://api.github.com/repos/o/r/pulls"), "core");
  assert.equal(entryOf("graphql", "lanes-app"), "graphql");
  assert.equal(entryOf("core", "lanes-app"), "lanes-app");
  assert.equal(entryOf("core", undefined), "github-token");
});

// A fake GitHub: answers in order, counting requests.
function fakeGitHub(answers) {
  const sent = [];
  return {
    sent,
    fetch: async (url, init = {}) => {
      sent.push(`${init.method ?? "GET"} ${url}`);
      const [status, headers = {}, body = {}] = answers.shift() ?? [200];
      return new Response(typeof body === "string" ? body : JSON.stringify(body), { status, headers });
    },
  };
}

function latchFor({ now = NOW } = {}) {
  const lines = [];
  let failed = 0;
  const clock = { now };
  const latch = createRateLimitLatch({
    now: () => clock.now,
    log: (line) => lines.push(line),
    fail: () => {
      failed += 1;
    },
    limits: () => apiLimits({ resolvedPath: "" }),
    stopFile: null,
  });
  return { latch, lines, clock, failed: () => failed };
}

const PRIMARY = [403, { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1792751600", "x-ratelimit-resource": "core" }, { message: "API rate limit exceeded for installation ID 1." }];
const URL_A = "https://api.github.com/repos/o/r/pulls/1";
const URL_B = "https://api.github.com/repos/o/r/issues/2";

test("a limited response sends no second request, and the error names the reset", async () => {
  const gh = fakeGitHub([PRIMARY, [200]]);
  const { latch, lines, failed } = latchFor();
  const fetch = latch.guard(gh.fetch);
  assert.equal((await fetch(URL_A)).status, 403);
  await assert.rejects(fetch(URL_B), (error) => error instanceof RateLimitStop && error.message.includes("2026-10-23T10:33:20Z"));
  assert.deepEqual(gh.sent, [`GET ${URL_A}`]);
  assert.ok(lines.some((line) => line.startsWith("::error::") && line.includes("2026-10-23T10:33:20Z")));
  assert.ok(failed() >= 1);
});

test("retry-after is honored: refused before it ends, sent after", async () => {
  const gh = fakeGitHub([[403, { "retry-after": "120" }, { message: "You have exceeded a secondary rate limit." }], [200]]);
  const { latch, clock } = latchFor();
  const fetch = latch.guard(gh.fetch);
  await fetch(URL_A);
  clock.now = NOW + 119_000;
  await assert.rejects(fetch(URL_B), RateLimitStop);
  assert.equal(gh.sent.length, 1);
  clock.now = NOW + 121_000;
  assert.equal((await fetch(URL_B)).status, 200);
  assert.equal(gh.sent.length, 2);
});

test("a primary limit on core leaves graphql open; a secondary one stops every pool", async () => {
  const gh = fakeGitHub([PRIMARY, [200], [403, { "retry-after": "60" }, { message: "secondary rate limit" }]]);
  const { latch } = latchFor();
  const fetch = latch.guard(gh.fetch);
  await fetch(URL_A);
  assert.equal((await fetch("https://api.github.com/graphql", { method: "POST" })).status, 200);
  await fetch("https://api.github.com/graphql", { method: "POST" });
  await assert.rejects(fetch("https://api.github.com/graphql", { method: "POST" }), RateLimitStop);
  assert.equal(gh.sent.length, 3);
});

test("under the read floor: one warning, no failure, calls still go, belowFloor reports it", async () => {
  const low = [200, { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "450", "x-ratelimit-reset": "1792751600" }];
  const gh = fakeGitHub([low, low]);
  const { latch, lines, failed } = latchFor();
  const fetch = latch.guard(gh.fetch);
  await fetch(URL_A);
  await fetch(URL_B);
  assert.equal(gh.sent.length, 2);
  assert.equal(lines.filter((line) => line.startsWith("::warning::")).length, 1);
  // The warning says what happens: nothing stops.
  assert.match(lines.find((line) => line.startsWith("::warning::")), /reads continue$/);
  assert.doesNotMatch(lines.join("\n"), /reads stop/);
  assert.equal(failed(), 0);
  assert.equal(latch.belowFloor(URL_A), true);
  assert.equal(latch.belowFloor("https://api.github.com/graphql"), false);
});

// github-token's default limit-cap of 1000 sets the floor at 100 left of the
// planned 1000: 950 used of a header limit of 5000 leaves 50.
test("the latch reads the pool's limit-cap: past the plan it warns, and a remaining above zero sends on", async () => {
  const past = [200, { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4050", "x-ratelimit-reset": "1792751600" }];
  const gh = fakeGitHub([past, past]);
  const { latch, lines, failed } = latchFor();
  const fetch = latch.guard(gh.fetch);
  await fetch(URL_A);
  await fetch(URL_B);
  assert.equal(gh.sent.length, 2);
  assert.equal(failed(), 0);
  assert.equal(latch.belowFloor(URL_A), true);
  assert.deepEqual(lines, ["::warning::GitHub's core API has under its read floor left (50 of the planned 1000; header remaining 4050 of 5000); reads continue"]);
});

test("a 403 Resource not accessible keeps its old behavior: returned, no latch, no failure", async () => {
  const refused = [403, { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4950" }, { message: "Resource not accessible by integration" }];
  const gh = fakeGitHub([refused, [200]]);
  const { latch, lines, failed } = latchFor();
  const fetch = latch.guard(gh.fetch);
  assert.equal((await fetch(URL_A)).status, 403);
  assert.equal((await fetch(URL_B)).status, 200);
  assert.equal(gh.sent.length, 2);
  assert.equal(failed(), 0);
  assert.deepEqual(lines, []);
});

test("graphql 200 with RATE_LIMITED latches graphql", async () => {
  const gh = fakeGitHub([[200, {}, { errors: [{ type: "RATE_LIMITED" }] }]]);
  const { latch } = latchFor();
  const fetch = latch.guard(gh.fetch);
  await fetch("https://api.github.com/graphql", { method: "POST" });
  await assert.rejects(fetch("https://api.github.com/graphql", { method: "POST" }), RateLimitStop);
  assert.equal(gh.sent.length, 1);
});

test("without a readable schema the latch still stops, and says the floor is unchecked", async () => {
  const lines = [];
  const latch = createRateLimitLatch({
    now: () => NOW,
    log: (line) => lines.push(line),
    fail: () => {},
    stopFile: null,
    limits: () => {
      throw new Error("ENOENT");
    },
  });
  const gh = fakeGitHub([PRIMARY]);
  const fetch = latch.guard(gh.fetch);
  await fetch(URL_A);
  await assert.rejects(fetch(URL_B), RateLimitStop);
  assert.ok(lines.some((line) => line.includes("read floor is not checked")));
});

// The process-wide stop, end to end in a child process: createGitHub trips the
// shared latch, then budgetedFetch's next call is refused without a request,
// and the process exits 1 although main set exitCode 0.
test("one limit stops every helper in the process, and the process exits red", () => {
  const script = `
    import { createGitHub } from "./.github/actions/check-trusted-trigger/check-trusted-trigger.mjs";
    import { budgetedFetch } from "./.github/scripts/pr-unblock/request-budget.mjs";
    let sent = 0;
    const fetchImpl = async () => {
      sent += 1;
      return new Response(JSON.stringify({ message: "API rate limit exceeded" }), {
        status: 403,
        headers: { "x-ratelimit-remaining": "0", "x-ratelimit-reset": String(Math.floor(Date.now() / 1000) + 3600), "x-ratelimit-limit": "5000" },
      });
    };
    const github = createGitHub({ token: "t", fetchImpl });
    await github("GET", "/repos/o/r").catch(() => {});
    const budget = budgetedFetch({ fetch: fetchImpl, log: () => {}, maxWaitMs: 0 });
    const refused = await budget.fetch("https://api.github.com/repos/o/r/pulls").then(() => "sent", (error) => error.name);
    console.log("sent=" + sent + " refused=" + refused);
    process.exitCode = 0;
  `;
  const root = new URL("../../../", import.meta.url).pathname;
  const run = spawnSync(process.execPath, ["--input-type=module", "-e", script], { cwd: root, encoding: "utf8", env: { ...process.env, RESOLVED_CONFIG: "", RUNNER_TEMP: "" } });
  assert.match(run.stdout, /sent=1 refused=RateLimitStop/);
  assert.match(run.stdout, /::error::GET \/repos\/o\/r|::error::GET https:\/\/api\.github\.com\/repos\/o\/r /);
  assert.equal(run.status, 1);
});

// The job-wide stop: a latch writes its stop to the file the gh wrapper
// shares, and a later step's latch, or the wrapper, starts from it.
test("a stop is written to the job's stop file, and a later latch refuses from it", async () =>
  withDir(async (dir) => {
    const stopFile = join(dir, "api-budget", "stop");
    const options = { now: () => NOW, log: () => {}, fail: () => {}, limits: () => ({}), stopFile };
    const gh = fakeGitHub([PRIMARY]);
    const first = createRateLimitLatch(options).guard(gh.fetch);
    await first(URL_A);
    assert.equal(readFileSync(stopFile, "utf8"), "core 1792751600\n");
    const later = createRateLimitLatch(options).guard(gh.fetch);
    await assert.rejects(later(URL_B), RateLimitStop);
    assert.equal(gh.sent.length, 1);
  }));

// A stop the job's stop file could not take is reported, and this process's
// latch still refuses the pool.
test("a stop the stop file cannot take is reported in the error line, and the latch still holds", { skip: ROOT && "root writes past any file mode" }, async () =>
  withDir(async (dir) => {
    const stopFile = join(dir, "api-budget", "stop");
    mkdirSync(dirname(stopFile));
    chmodSync(dirname(stopFile), 0o555);
    const lines = [];
    const gh = fakeGitHub([PRIMARY, [200]]);
    const latch = createRateLimitLatch({ now: () => NOW, log: (line) => lines.push(line), fail: () => {}, limits: () => ({}), stopFile });
    const fetch = latch.guard(gh.fetch);
    await fetch(URL_A);
    const error = lines.find((line) => line.startsWith("::error::"));
    assert.match(error, /core API rate limit/);
    assert.match(error, /the stop could not be recorded in the job's stop file \(EACCES\)/);
    await assert.rejects(fetch(URL_B), RateLimitStop);
    assert.equal(gh.sent.length, 1);
    chmodSync(dirname(stopFile), 0o755);
  }));

// The stop-file reader every port shares: rate-guard.vectors.json's
// stop_files, read through a latch at vector_now.
const POOL_URLS = {
  core: "https://api.github.com/repos/o/r",
  graphql: "https://api.github.com/graphql",
  search: "https://api.github.com/search/issues?q=x",
  code_search: "https://api.github.com/search/code?q=x",
};

for (const vector of VECTORS.stop_files) {
  test(`stop file: ${vector.name}`, () =>
    withDir((dir) => {
      const stopFile = join(dir, "stop");
      writeFileSync(stopFile, vector.text);
      const latch = createRateLimitLatch({ now: () => NOW, log: () => {}, fail: () => {}, limits: () => ({}), stopFile });
      assert.deepEqual(Object.fromEntries(Object.entries(POOL_URLS).map(([pool, url]) => [pool, latch.until(url)])), vector.until);
    }));
}

// A stop file that exists but cannot be read holds every pool, with an error
// naming it; a missing one holds nothing (rate-guard.vectors.json's
// stop_file_errors).
// Each vector's layout; the returned function undoes its permissions.
function makeStopFileError(dir, layout) {
  const budget = join(dir, "api-budget");
  const stop = join(budget, "stop");
  if (layout === "api-budget-is-file") {
    writeFileSync(budget, "");
    return { stop, undo: () => {} };
  }
  mkdirSync(budget);
  if (layout === "stop-unreadable") {
    writeFileSync(stop, "core 1792751600\n");
    chmodSync(stop, 0o000);
  } else if (layout === "stop-is-directory") {
    mkdirSync(stop);
  } else if (layout === "api-budget-unsearchable") {
    writeFileSync(stop, "core 1792751600\n");
    chmodSync(budget, 0o600);
  }
  return { stop, undo: () => chmodSync(budget, 0o755) };
}

for (const vector of VECTORS.stop_file_errors) {
  test(`stop file error: ${vector.name}`, { skip: vector.error === "EACCES" && ROOT && "root reads any file" }, () =>
    withDir((dir) => {
      const { stop: stopFile, undo } = makeStopFileError(dir, vector.layout);
      const lines = [];
      const latch = createRateLimitLatch({ now: () => NOW, log: (line) => lines.push(line), fail: () => {}, limits: () => ({}), stopFile });
      assert.deepEqual(Object.fromEntries(Object.entries(POOL_URLS).map(([pool, url]) => [pool, latch.until(url)])), vector.until);
      const errors = lines.filter((line) => line.startsWith("::error::"));
      if (vector.error === "ENOENT") {
        assert.deepEqual(errors, []);
      } else {
        assert.equal(errors.length, 1);
        assert.ok(errors[0].includes(`stop file ${stopFile} cannot be read (${vector.error})`), errors[0]);
      }
      undo();
    }));
}

// Every guarded answer leaves one reading for the job-end notice, under the
// bucket API_BUDGET_TOKEN names; without that name it leaves none.
test("the guard keeps a reading of each answer under API_BUDGET_TOKEN, and none without it", async () =>
  withDir(async (dir) => {
    const saved = { token: process.env.API_BUDGET_TOKEN, temp: process.env.RUNNER_TEMP };
    process.env.RUNNER_TEMP = dir;
    const ok = [200, { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4990", "x-ratelimit-used": "10", "x-ratelimit-reset": "1792751600", "x-ratelimit-resource": "core" }];
    const options = { now: () => NOW, log: () => {}, fail: () => {}, limits: () => ({}), stopFile: null };
    try {
      delete process.env.API_BUDGET_TOKEN;
      await createRateLimitLatch(options).guard(fakeGitHub([ok]).fetch)(URL_A);
      assert.equal(readdirSync(dir).length, 0);
      process.env.API_BUDGET_TOKEN = "github-token";
      const gh = fakeGitHub([ok, [404, { ...ok[1], "x-ratelimit-remaining": "4989", "x-ratelimit-used": "11" }], [500]]);
      const guarded = createRateLimitLatch(options).guard(gh.fetch);
      for (const url of [URL_A, URL_A, URL_B]) {
        await guarded(url);
      }
      assert.equal(readFileSync(join(dir, "api-budget", "github-token"), "utf8"), "200 5000 4990 10 1792751600 core\n404 5000 4989 11 1792751600 core\n500 na na na na na\n");
    } finally {
      for (const [key, value] of [["API_BUDGET_TOKEN", saved.token], ["RUNNER_TEMP", saved.temp]]) {
        if (value === undefined) delete process.env[key];
        else process.env[key] = value;
      }
    }
  }));

// No lane script calls fetch outside the guard, except the files below, each
// for its stated reason. A new raw fetch fails here until it is guarded or
// listed.
const UNGUARDED = {
  // Package registries and status pages, not the API.
  ".github/scripts/pr-unblock/dependency-classify.mjs": "package registries",
  ".github/scripts/maintenance-reconcile-lost-runs/component-status.mjs": "the status pages, not the API",
  // Their fetch is budgetedFetch's, which the guard wraps.
  ".github/scripts/pr-unblock/dispatch.mjs": "fetch injected from budgetedFetch",
  ".github/scripts/pr-unblock/feedback-dispatch.mjs": "fetch injected from budgetedFetch",
  // Script activities that run from a copy of their own directory, where the
  // guard module is not: open until the copy carries it.
  ".github/scripts/apply-patch/apply-patch.mjs": "script activity run from a directory copy",
  ".github/scripts/pr-unblock/address-feedback.mjs": "imported by script activities run from a directory copy",
  ".github/scripts/work-resolve-issue/report-outcome.mjs": "script activity run from a directory copy",
  // pr-merge's own guard is its owner's change.
  ".github/scripts/pr-merge/merge-holds.mjs": "pr-merge, guarded by its owner",
};

test("every lane script that calls fetch goes through the rate guard, or is listed with its reason", () => {
  const root = new URL("../../../", import.meta.url).pathname;
  const files = spawnSync("git", ["-C", root, "ls-files", ".github/*.mjs", ".github/*.js", ".github/*.cjs"], { encoding: "utf8" })
    .stdout.split("\n")
    .filter((file) => file && !/\.test\.[cm]?js$/.test(file) && !file.includes("/node_modules/") && !file.includes("/fixtures/") && !file.includes("/probe/"));
  const raw = files.filter((file) => {
    const text = readFileSync(join(root, file), "utf8");
    // An import of the guard counts; the path named in a string does not.
    const imports = /from\s+["'][^"']*log-api-budget\/rate-guard\.mjs["']/.test(text);
    return /(^|[^\w.])fetch\(/m.test(text) && !imports && !file.endsWith("log-api-budget/rate-guard.mjs");
  });
  assert.deepEqual(raw.filter((file) => !(file in UNGUARDED)), []);
  assert.deepEqual(Object.keys(UNGUARDED).filter((file) => !raw.includes(file)), [], "a listed file no longer needs its exception");
});

test("isContentWrite counts the issue, pull request, comment, review and label writes, and GraphQL mutations", () => {
  const repo = "https://api.github.com/repos/o/r";
  for (const [url, method] of [
    [`${repo}/issues`, "POST"],
    [`${repo}/issues/7`, "PATCH"],
    [`${repo}/issues/7/comments`, "POST"],
    [`${repo}/issues/7/labels`, "POST"],
    [`${repo}/issues/comments/9`, "PATCH"],
    [`${repo}/pulls`, "POST"],
    [`${repo}/pulls/7/reviews`, "POST"],
    [`${repo}/pulls/7/comments/9/replies`, "POST"],
  ]) {
    assert.equal(isContentWrite(url, method), true, `${method} ${url}`);
  }
  for (const [url, method] of [
    [`${repo}/issues/7/comments`, "GET"],
    [`${repo}/issues/7/labels/x`, "DELETE"],
    [`${repo}/statuses/abc`, "POST"],
    [`${repo}/actions/workflows/x.yml/dispatches`, "POST"],
  ]) {
    assert.equal(isContentWrite(url, method), false, `${method} ${url}`);
  }
  const graphql = "https://api.github.com/graphql";
  assert.equal(isContentWrite(graphql, "POST", JSON.stringify({ query: " mutation($id: ID!) { x }" })), true);
  assert.equal(isContentWrite(graphql, "POST", JSON.stringify({ query: "query { viewer { login } }" })), false);
});

test("a guarded content write is counted in the job's content-creation file, a read is not", async () =>
  withDir(async (dir) => {
    const saved = process.env.RUNNER_TEMP;
    process.env.RUNNER_TEMP = dir;
    try {
      const gh = fakeGitHub([[201], [200]]);
      const options = { now: () => NOW, log: () => {}, fail: () => {}, limits: () => ({}), stopFile: null };
      const fetch = createRateLimitLatch(options).guard(gh.fetch);
      await fetch("https://api.github.com/repos/o/r/issues/7/comments", { method: "POST", body: "{}" });
      await fetch("https://api.github.com/repos/o/r/issues/7/comments");
      assert.equal(readFileSync(join(dir, "api-budget", "content-creation"), "utf8"), `${VECTORS.vector_now}\n`);
    } finally {
      if (saved === undefined) delete process.env.RUNNER_TEMP;
      else process.env.RUNNER_TEMP = saved;
    }
  }));

test("a guard given a token records its readings under that name, and one without under API_BUDGET_TOKEN", async () =>
  withDir(async (dir) => {
    const saved = { RUNNER_TEMP: process.env.RUNNER_TEMP, API_BUDGET_TOKEN: process.env.API_BUDGET_TOKEN };
    process.env.RUNNER_TEMP = dir;
    process.env.API_BUDGET_TOKEN = "lanes-app";
    try {
      const gh = fakeGitHub([[200], [200], [200]]);
      const latch = createRateLimitLatch({ now: () => NOW, log: () => {}, fail: () => {}, limits: () => ({}), stopFile: null });
      const app = latch.guard(gh.fetch);
      const actions = latch.guard(gh.fetch, { token: "github-token" });
      await app("https://api.github.com/repos/o/r/issues/7");
      await actions("https://api.github.com/repos/o/r/actions/runs");
      await actions("https://api.github.com/repos/o/r/actions/runs");
      const lines = (name) => readFileSync(join(dir, "api-budget", name), "utf8").trim().split("\n").length;
      assert.equal(lines("lanes-app"), 1);
      assert.equal(lines("github-token"), 2);
    } finally {
      for (const [key, value] of Object.entries(saved)) {
        if (value === undefined) delete process.env[key];
        else process.env[key] = value;
      }
    }
  }));

// label-unblocked's ACTIONS_TOKEN client runs in a lanes-app step: its guard
// plans to github-token's limit-cap of 1000, not lanes-app's header limit.
test("a guard given a token plans to that token's limits.api entry, not API_BUDGET_TOKEN's", async () => {
  const saved = process.env.API_BUDGET_TOKEN;
  process.env.API_BUDGET_TOKEN = "lanes-app";
  try {
    const past = [200, { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4050", "x-ratelimit-reset": "1792751600" }];
    const limits = () => ({ "github-token": { "read-floor": 0.1, "limit-cap": 1000 }, "lanes-app": { "read-floor": 0.1 } });
    const warned = async (options) => {
      const lines = [];
      const latch = createRateLimitLatch({ now: () => NOW, log: (line) => lines.push(line), fail: () => {}, limits, stopFile: null });
      await latch.guard(fakeGitHub([past]).fetch, options)(URL_A);
      return lines.length;
    };
    assert.equal(await warned({ token: "github-token" }), 1);
    assert.equal(await warned(), 0);
  } finally {
    if (saved === undefined) delete process.env.API_BUDGET_TOKEN;
    else process.env.API_BUDGET_TOKEN = saved;
  }
});
