// pr-merge.yml's main-verification trigger. Expected values come from the
// owner decision of 2026-10-18 (every merge to main gets a full run, whoever
// merged), the efficiency plan of 2026-10-26 (items 5 and 7(b): at most one
// full run of main per 30 minutes, and no wait on the run), GitHub's
// concurrency rules (a group holds one running and one pending job, and a
// newer pending job replaces the older one unless `queue: max` is set), and
// the rule babysit_postmerge.py and post-merge-demotion-alert.yml share: a
// cancelled full run counts as red, unless it never started, so no running
// pr-require-checks run may be cancelled by concurrency.
import assert from "node:assert/strict";
import { execFileSync, spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { CACHE_ONLY_TIMEOUT_MS, CACHE_ONLY_WINDOW_MS, LANE_ROOM_TIMEOUT_MS, VERIFY_BUDGET_MS, VERIFY_TIMEOUT_MS } from "./enable-auto-merge.mjs";
import { classify, resetLabel } from "../../actions/log-api-budget/rate-guard.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const read = (name) => readFileSync(new URL(`../../workflows/${name}`, import.meta.url), "utf8");
const merge = read("pr-merge.yml");
const jobs = merge.slice(merge.indexOf("\njobs:\n"));
const job = (id) => {
  const match = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(jobs);
  assert.ok(match, `job ${id}`);
  return match[1];
};

test("every push to main reaches the dispatch job, with no author filter", () => {
  assert.match(merge, /\n {2}push:\n {4}branches: \[main\]\n/);
  const dispatch = job("dispatch-full-run");
  const condition = /\n {4}if: >-\n([\s\S]*?)\n {4}[a-z-]+:/.exec(dispatch)[1];
  assert.match(condition, /\(github\.event_name == 'push' && github\.ref == 'refs\/heads\/main'\)/);
  assert.doesNotMatch(dispatch, /head_commit|AUTOMATION_LANES_APP_SENDER_ID|needs\.lane-merge-landed/);
  assert.doesNotMatch(jobs, /\n {2}lane-merge-landed:\n/);
});

test("push dispatches share one group that queues one and cancels nothing", () => {
  const dispatch = job("dispatch-full-run");
  const block = /\n {4}concurrency:\n {6}group: (.*)\n {6}cancel-in-progress: (.*)\n/.exec(dispatch);
  assert.ok(block, "a job-level concurrency block");
  assert.match(block[1], /github\.event_name == 'push' && '[a-z-]+'/);
  assert.match(block[1], /github\.run_id/);
  assert.equal(block[2], "false");
  assert.doesNotMatch(dispatch, /\n {6}queue:/);
});

// The job ends once it dispatches (efficiency plan item 7(b), owner
// decision): post-merge-dispatch sends a red run to the alert on the next
// scheduled run, so no step polls the run or sleeps on a held runner.
test("dispatch-full-run ends once it dispatches: no wait on the run it started", () => {
  const dispatch = job("dispatch-full-run");
  assert.deepEqual(
    [...dispatch.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]),
    [
      "Check out the api-budget library",
      "Read main's full-run cover",
      "Start the full CI run on main",
      "Scan the upload for credentials",
      "Record the dispatched run",
      "Log the API budget at the end",
    ],
  );
  assert.doesNotMatch(dispatch, /sleep 180|actions\/runs\/\$RUN_ID|post-merge-demotion-alert\.yml\/dispatches/);
  const timeout = Number(/\n {4}timeout-minutes: (\d+)\n/.exec(dispatch)[1]);
  assert.ok(timeout <= 10, `timeout-minutes ${timeout}`);
});

const HEAD = "0123456789abcdef0123456789abcdef01234567";
// gh's stderr for a POST GitHub refused for a rate limit, as run 39906176584
// logged it (pr-merge.yml, dispatch-full-run, "Start the full CI run on main",
// 2026-10-23T05:30:57Z).
const RATE_LIMITED_STDERR =
  "gh: API rate limit exceeded for installation. If you reach out to GitHub Support for help, please include the request ID 8000:1DF2D:1EE39F:657D15:6ADAF110 and timestamp 2026-10-23 05:30:57 UTC. For more on scraping GitHub and how it may affect your rights, please review our Terms of Service (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) (HTTP 403)";

// The cover step's body, run under bash against a stub gh that applies the
// step's --jq filter to a canned listing of pr-require-checks.yml dispatches
// on main, newest first, as the runs API lists them. `runs` entries are
// {minutesAgo, sha, actor, conclusion}. The cap (owner decision, efficiency
// plan item 5) is one full run of main per 30 minutes.
const coverBody = (id) => {
  const block = job(id).split("\n      - name: Read main's full-run cover\n")[1].split("\n      - name: ")[0];
  return { block, body: runBody(block) };
};
function runCover(runs, { jobId = "dispatch-full-run", fails = false, limited = false, tip = HEAD } = {}) {
  const dir = tempDir("pr-merge-cover-");
  mkdirSync(join(dir, "bin"));
  const now = Date.now();
  const listing = {
    workflow_runs: runs.map((r, i) => ({
      id: 100 - i,
      head_sha: r.sha ?? HEAD,
      head_branch: "main",
      created_at: new Date(now - r.minutesAgo * 60_000).toISOString().replace(/\.\d{3}Z$/, "Z"),
      actor: { login: r.actor ?? "github-actions[bot]" },
      status: r.conclusion ? "completed" : "in_progress",
      conclusion: r.conclusion ?? null,
    })),
  };
  writeFileSync(join(dir, "listing.json"), JSON.stringify(listing));
  writeFileSync(
    join(dir, "bin", "gh"),
    `#!/usr/bin/env bash
printf '%s\\n' "$*" >>"${dir}/log"
${fails ? `echo 'gh: Server Error (HTTP 502)' >&2; exit 1` : ""}
${limited ? `echo '${RATE_LIMITED_STDERR}' >&2; exit 1` : ""}
while [ $# -gt 0 ]; do if [ "$1" = --jq ]; then exec jq -c "$2" "${dir}/listing.json"; fi; shift; done
exit 1
`,
    { mode: 0o755 },
  );
  writeFileSync(join(dir, "body.sh"), coverBody(jobId).body);
  writeFileSync(join(dir, "output"), "");
  const result = spawnSync("bash", ["-e", join(dir, "body.sh")], {
    env: {
      ...process.env,
      PATH: `${join(dir, "bin")}:${process.env.PATH}`,
      GH_TOKEN: "x",
      REPO: "o/r",
      TIP: tip,
      CAP_MINUTES: /\n {10}CAP_MINUTES: (\d+)\n/.exec(coverBody(jobId).block)[1],
      GITHUB_OUTPUT: join(dir, "output"),
      RUNNER_TEMP: dir,
    },
    encoding: "utf8",
  });
  const output = readFileSync(join(dir, "output"), "utf8");
  const log = existsSync(join(dir, "log")) ? readFileSync(join(dir, "log"), "utf8") : "";
  rmSync(dir, { recursive: true, force: true });
  return {
    status: result.status,
    out: result.stdout + result.stderr,
    capped: /^capped=true$/m.test(output),
    uncovered: /^uncovered=true$/m.test(output),
    limited: /^rate-limited=true$/m.test(output),
    writes: log.split("\n").filter((l) => l.includes("-X")),
  };
}
const OLDER = "89abcdef0123456789abcdef0123456789abcdef";

// The two copies differ only in how a failed read is classified:
// post-merge-dispatch sources the shared rate guard from its checkout,
// dispatch-full-run has none and matches the pattern the guard reads.
test("both jobs read main's cover with the same cap logic, a 30-minute cap and the run's own SHA as the tip", () => {
  const a = coverBody("dispatch-full-run");
  const b = coverBody("post-merge-dispatch");
  const afterRead = (body) => body.slice(body.indexOf('\n  echo "::warning::the read of main\'s full runs failed'));
  assert.equal(afterRead(a.body), afterRead(b.body));
  assert.match(a.body, /grep -qiE 'rate limit\|RATE_LIMITED\|abuse detection\|HTTP 429' "\$RUNNER_TEMP\/cover-stderr"/);
  assert.match(b.body, /\. \.base\/\.github\/scripts\/pr-merge\/rate-stop\.bash\n/);
  assert.match(b.body, /stop=\$\(rate_stop_from "\$RUNNER_TEMP\/cover-stderr" /);
  for (const body of [a.body, b.body]) assert.match(body, /echo "rate-limited=true" >>"\$GITHUB_OUTPUT"\n(?: +echo "stop=\$stop" >>"\$GITHUB_OUTPUT"\n)? +exit 1\n/);
  for (const { block } of [a, b]) {
    assert.match(block, /\n {10}CAP_MINUTES: 30\n/);
    assert.match(block, /\n {10}TIP: \$\{\{ github\.sha \}\}\n/);
    assert.match(block, /^ {8}id: cover\n/);
  }
  assert.match(a.body, /actions\/workflows\/pr-require-checks\.yml\/runs\?event=workflow_dispatch&branch=main/);
});

test("a full run of main started within 30 minutes caps the next dispatch", () => {
  const r = runCover([{ minutesAgo: 12, sha: OLDER }]);
  assert.equal(r.status, 0, r.out);
  assert.equal(r.capped, true);
  assert.equal(r.uncovered, true);
  assert.match(r.out, /::notice::a full run of main was started at .*, within 30 minutes/);
  assert.deepEqual(r.writes, []);
});

test("a full run of main older than 30 minutes caps nothing, and a run at the tip covers it", () => {
  const old = runCover([{ minutesAgo: 31, sha: OLDER }]);
  assert.equal(old.capped, false);
  assert.equal(old.uncovered, true);
  const atTip = runCover([{ minutesAgo: 45, conclusion: "success" }]);
  assert.equal(atTip.capped, false);
  assert.equal(atTip.uncovered, false);
  assert.deepEqual(runCover([]), { status: 0, out: "", capped: false, uncovered: true, limited: false, writes: [] });
});

// A cancelled run is no cover: replaced before it started, or cancelled once
// running, which reads red. Only github-actions[bot]'s dispatches count: the
// post-merge check credits no one else's for a lane merge.
test("a cancelled run or another actor's dispatch neither caps nor covers", () => {
  const r = runCover([
    { minutesAgo: 5, conclusion: "cancelled" },
    { minutesAgo: 8, actor: "maintainer" },
    { minutesAgo: 40, sha: OLDER, conclusion: "success" },
  ]);
  assert.equal(r.capped, false, r.out);
  assert.equal(r.uncovered, true);
});

test("a failed read sets neither output, so the run dispatches as with no cap", () => {
  const r = runCover([{ minutesAgo: 5 }], { fails: true });
  assert.equal(r.status, 0);
  assert.equal(r.capped, false);
  assert.equal(r.uncovered, false);
  assert.equal(r.limited, false);
  assert.match(r.out, /::warning::the read of main's full runs failed; no cap applies to this run/);
});

// stop-on-limit (docs/conventions/pr-pipeline/README.md): a read refused for a
// rate limit is no ordinary failure. The step stops red with rate-limited=true
// and the dispatch after it sends nothing.
test("a rate-limited read stops dispatch-full-run red, and the dispatch is skipped", () => {
  const r = runCover([{ minutesAgo: 5 }], { limited: true });
  assert.equal(r.status, 1, r.out);
  assert.equal(r.limited, true);
  assert.equal(r.capped, false);
  assert.match(r.out, /::error title=GitHub rate limit::the read of main's full runs was rate limited; nothing more is sent/);
  assert.doesNotMatch(r.out, /no cap applies/);
  const text = stepIf("dispatch-full-run", "Start the full CI run on main");
  assert.equal(evalStep(text, outs({ limited: "true", uncovered: "true" })), false);
});

// The dispatch steps' conditions, evaluated over the cover and post-merge
// outputs: dispatch-full-run starts nothing within the cap; post-merge-dispatch
// starts main's tip when no run covers it, for any merge, and keeps the lane's
// own request, both outside the cap.
const stepIf = (id, name) => {
  const block = job(id).split(`\n      - name: ${name}\n`)[1].split("\n      - name: ")[0];
  const text = /\n {8}if: (?:>-\n((?: {10}.*\n)+)|(.*)\n)/.exec(block);
  return (text[1] ?? text[2]).replaceAll("\n", " ");
};
const evalStep = (text, steps) =>
  new Function("steps", `return (${text.replace(/\.([a-z]+(?:-[a-z]+)+)/g, '["$1"]')});`)(steps);
const outs = ({ capped = "", uncovered = "", needs = "false", limited = "", proceed = "true", live = "true", bypass = "" } = {}) => ({
  kill: { outputs: { proceed } },
  mode: { outputs: { live } },
  cover: { outputs: { capped, uncovered, "rate-limited": limited } },
  "post-merge": { outputs: { "needs-dispatch": needs } },
  bypass: { outputs: { bypass } },
});

test("dispatch-full-run starts nothing within the cap, and anything outside it", () => {
  const text = stepIf("dispatch-full-run", "Start the full CI run on main");
  assert.equal(evalStep(text, outs({ capped: "true" })), false);
  assert.equal(evalStep(text, outs({ uncovered: "true" })), true);
  // A failed cover read sets nothing: the dispatch goes ahead.
  assert.equal(evalStep(text, outs()), true);
});

// The merge job mints its lane token, and reads its mode, only while the
// resolved merge-pr slot applies; a slot `enabled: false` or whose
// `applies-when` does not match prints the skip reason instead (#7636).
// A merge-job step's condition, with or without an `id:` line before it.
const conditionOf = (body, name) => {
  const found = /(?:^|\n) {8}if: (?:>-\n((?: {10}.*\n)+)|(.*)\n)/.exec(body);
  assert.ok(found, `${name} has a condition`);
  return (found[1] ?? found[2]).replaceAll("\n", " ");
};
const mergeIf = (name) => conditionOf(job("merge").split(`\n      - name: ${name}\n`)[1].split("\n      - name: ")[0], name);
const configured = (applies, outcome = "success") => ({ config: { outcome, outputs: { applies, "skip-reason": applies === "true" ? "" : "disabled-by-config" } } });

test("the merge job requests its lane token and reads its mode only while the merge-pr slot applies", () => {
  for (const name of ["Request the lane token", "Read report-only"]) {
    const text = mergeIf(name);
    assert.equal(evalStep(text, configured("true")), true, name);
    assert.equal(evalStep(text, configured("false")), false, name);
    assert.equal(evalStep(text, configured("")), false, name);
    assert.equal(evalStep(text, configured("true", "failure")), false, name);
  }
});

test("a merge-pr slot the config turns off prints its skip reason before the token request, and nothing after it runs", () => {
  const merge = job("merge");
  const names = [...merge.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.equal(names.indexOf("Report a lane the config turns off") + 1, names.indexOf("Request the lane token"));
  const text = mergeIf("Report a lane the config turns off");
  assert.equal(evalStep(text, configured("false")), true);
  assert.equal(evalStep(text, configured("true")), false);
  assert.equal(evalStep(text, configured("false", "failure")), false);
  const block = merge.split("\n      - name: Report a lane the config turns off\n")[1].split("\n      - name: ")[0];
  assert.match(block, /\n {10}REASON: \$\{\{ steps\.config\.outputs\.skip-reason \}\}\n/);
  assert.match(block, /::notice::merge-pr does not apply \(\$\{REASON:-no reason\}\)/);
  // Every step after the token request waits on a token, or on a step that does.
  // Each credential scan reads as clean, so an upload waits on its own
  // condition, not only on its scan. Steps go by block: the scans share a name.
  const blocks = merge.split("\n      - name: ").slice(1);
  const after = blocks.slice(names.indexOf("Request the lane token") + 1);
  for (const block of after) {
    const name = block.slice(0, block.indexOf("\n"));
    const condition = conditionOf(block, name);
    const unminted = new Proxy(
      { ...configured("false"), "lane-token": { outputs: { token: "" } }, mode: { outputs: {} }, candidates: { outcome: "skipped", outputs: {} }, gate: { outcome: "skipped" }, "head-refs": { outcome: "skipped" }, "post-merge": { outcome: "skipped", outputs: {} }, "lane-records": { outcome: "skipped" }, carry: { outputs: {} } },
      { get: (known, id) => known[id] ?? (/^scan-upload(-\d+)?$/.test(id) ? { outcome: "success", outputs: { clean: "true" } } : undefined) },
    );
    const always = () => true;
    const value = new Function("steps", "github", "needs", "always", `return (${condition.replace(/\.([a-z]+(?:-[a-z0-9]+)+)/g, '["$1"]')});`)(unminted, { event_name: "schedule" }, { "post-merge-dispatch": { result: "success", outputs: { "rate-limited": "" } } }, always);
    // It reads the job's own token, and runs on a kill switch too.
    if (name === "Log the API budget at job end") {
      continue;
    }
    assert.equal(value, false, name);
  }
});

test("post-merge-dispatch starts main's uncovered tip for any merge, outside the cap only", () => {
  const text = stepIf("post-merge-dispatch", "Start the full CI run on main");
  const expr = text;
  assert.equal(evalStep(expr, outs({ uncovered: "true" })), true, "a skipped merge of anyone's");
  assert.equal(evalStep(expr, outs({ uncovered: "true", capped: "true" })), false);
  assert.equal(evalStep(expr, outs({ needs: "true" })), true, "the lane's own request");
  assert.equal(evalStep(expr, outs({ needs: "true", capped: "true" })), false);
  assert.equal(evalStep(expr, outs()), false, "a covered tip");
  assert.equal(evalStep(expr, outs({ uncovered: "true", limited: "true" })), false, "a rate-limited cover read");
  assert.equal(evalStep(expr, outs({ uncovered: "true", proceed: "false", live: "" })), false, "the kill switch on");
  assert.equal(evalStep(expr, outs({ uncovered: "true", live: "" })), false, "report-only on");
  // merge.full-run-cap-bypass: an uncovered lane batch starts one run inside the cap.
  assert.equal(evalStep(expr, outs({ capped: "true", bypass: "true" })), true, "an uncovered lane batch inside the cap");
  assert.equal(evalStep(expr, outs({ capped: "true", bypass: "true", limited: "true" })), false, "a rate-limited cover read");
  assert.equal(evalStep(expr, outs({ capped: "true", bypass: "true", live: "" })), false, "report-only on");
});

// Review decision on #10491: the scheduled job reads the cover only while the
// lane is live (kill switch off, report-only off), as its post-merge check
// does; dispatch-full-run's push carve-out still starts a run per merge.
test("post-merge-dispatch reads the cover only while the lane is live", () => {
  const dispatch = job("post-merge-dispatch");
  const block = dispatch.split("\n      - name: Read main's full-run cover\n")[1].split("\n      - name: ")[0];
  assert.match(block, /\n {8}if: steps\.kill\.outputs\.proceed == 'true' && steps\.mode\.outputs\.live == 'true'\n/);
  const names = [...dispatch.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.equal(names.indexOf("Read main's full-run cover") + 1, names.indexOf("Find lane merges no full run covers"));
  assert.equal(names.indexOf("Find lane merges no full run covers") + 1, names.indexOf("Start the full CI run on main"));
  assert.ok(names.indexOf("Check earlier lane merges") < names.indexOf("Read main's full-run cover"));
  const cover = job("dispatch-full-run").split("\n      - name: Read main's full-run cover\n")[1].split("\n      - name: ")[0];
  assert.doesNotMatch(cover, /\n {8}if:/);
  assert.doesNotMatch(job("dispatch-full-run"), /steps\.(kill|mode)\./);
});

// contents: read only checks out the api-budget library and the upload scan
// with the rules it reads, sparse, from main.
test("the dispatch job's token is actions: write and contents: read, and nothing else", () => {
  const dispatch = job("dispatch-full-run");
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(dispatch)[1];
  assert.deepEqual(
    [...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => `${m[1]}: ${m[2]}`),
    ["actions: write", "contents: read"],
  );
  const checkout = dispatch.split("\n      - name: Check out the api-budget library\n")[1].split("\n      - name: ")[0];
  assert.match(checkout, /^ {8}continue-on-error: true\n/);
  assert.match(checkout, /\n {10}ref: refs\/heads\/main\n {10}path: \.base\n {10}persist-credentials: false\n {10}sparse-checkout: \|\n {12}\/\.github\/actions\/log-api-budget\/\n {12}\/\.github\/actions\/scan-upload\/\n {12}\/lib\/publish-gate\.mjs\n {10}sparse-checkout-cone-mode: false\n/);
});

// The cover read and each dispatch POST leave a rate-limit reading, so the
// job-end api-calls notice counts them; the POST is recorded, never guarded.
test("dispatch-full-run's cover read and dispatch POST each leave one reading", () => {
  const dir = tempDir("pr-merge-reading-");
  mkdirSync(join(dir, "bin"));
  symlinkSync(fileURLToPath(new URL("../../..", import.meta.url)), join(dir, ".base"));
  const headers = "X-Ratelimit-Limit: 5000\r\nX-Ratelimit-Remaining: 4000\r\nX-Ratelimit-Used: 1000\r\nX-Ratelimit-Reset: 9999999999\r\nX-Ratelimit-Resource: core\r\n\r\n";
  writeFileSync(
    join(dir, "bin", "gh"),
    `#!/usr/bin/env bash
if [[ " $* " == *" -X POST "* ]]; then printf 'HTTP/2.0 200 OK\\r\\n${headers.replaceAll("\r\n", "\\r\\n")}{"workflow_run_id":4242}'; exit 0; fi
printf 'HTTP/2.0 200 OK\\r\\n${headers.replaceAll("\r\n", "\\r\\n")}'
while [ $# -gt 0 ]; do if [ "$1" = --jq ]; then echo '[]' | jq -c "$2"; exit; fi; shift; done
`,
    { mode: 0o755 },
  );
  writeFileSync(join(dir, "cover.sh"), coverBody("dispatch-full-run").body);
  writeFileSync(join(dir, "dispatch.sh"), dispatchStep("dispatch-full-run").body);
  writeFileSync(join(dir, "output"), "");
  const env = { ...process.env, PATH: `${join(dir, "bin")}:${process.env.PATH}`, GH_TOKEN: "x", REPO: "o/r", TIP: HEAD, CAP_MINUTES: "30", WAIT_CAP: "180", GITHUB_EVENT_NAME: "push", GITHUB_SHA: HEAD, GITHUB_RUN_ID: "77", GITHUB_OUTPUT: join(dir, "output"), RUNNER_TEMP: dir };
  try {
    for (const body of ["cover.sh", "dispatch.sh"]) {
      const r = spawnSync("bash", ["-e", join(dir, body)], { cwd: dir, env, encoding: "utf8" });
      assert.equal(r.status, 0, r.stdout + r.stderr);
    }
    assert.match(readFileSync(join(dir, "output"), "utf8"), /^run-id=4242$/m);
    assert.equal(readFileSync(join(dir, "api-budget", "github-token"), "utf8"), "200 5000 4000 1000 9999999999 core repos/{repo}/actions/workflows/{x}/runs\n200 5000 4000 1000 9999999999 core repos/{repo}/actions/workflows/{x}/dispatches\n");
    const calls = spawnSync("bash", ["-c", ". .base/.github/actions/log-api-budget/api-budget.bash; api_budget_emit_calls github-token"], { cwd: dir, env, encoding: "utf8" });
    assert.equal(calls.stdout, "::notice title=api-calls::github-token=2 not-modified=0 graphql=0\n");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// pr-require-checks.yml's concurrency, evaluated per event. Main's dispatches
// share one group with no `queue` key: GitHub then keeps one running and one
// pending, "When a new job or workflow run is queued, any existing pending job
// or workflow run in the same group is canceled and replaced", whereas
// `queue: max` keeps up to 100 pending, which would batch nothing
// (https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).
// That group never cancels a running run, which reads red to the post-merge
// check; every other group keeps its cancel.
const checksConcurrency = () => {
  const checks = read("pr-require-checks.yml");
  const block = /\nconcurrency:\n {2}group: >-\n([\s\S]*?)\n {2}cancel-in-progress: (.*)\n(?=\S|\n)/.exec(checks);
  assert.ok(block, "a workflow-level concurrency block");
  const unwrap = (text) => text.trim().replace(/^\$\{\{\s*/, "").replace(/\s*\}\}$/, "").replaceAll("\n", " ");
  const evaluate = (text, github) =>
    new Function("github", "contains", "fromJSON", "format", `return (${unwrap(text)});`)(
      github,
      (list, item) => list.includes(item),
      JSON.parse,
      (template, ...values) => template.replace(/\{(\d+)\}/g, (_, i) => String(values[i])),
    );
  return { checks, block, group: (github) => evaluate(block[1], github), cancel: (github) => evaluate(block[2], github) };
};
const prEvent = (action, number = 5) => ({
  event_name: "pull_request",
  ref: `refs/pull/${number}/merge`,
  repository: "o/r",
  workflow: "pr-require-checks",
  run_id: 900 + number,
  event: { action, pull_request: { number, head: { repo: { full_name: "o/r" } } }, changes: {} },
});

test("pr-require-checks.yml holds main's dispatches in one group that cancels nothing", () => {
  const { checks, block, group, cancel } = checksConcurrency();
  const on = checks.slice(checks.indexOf("\non:\n"), checks.indexOf("\npermissions:\n"));
  assert.doesNotMatch(on, /\n {2}push:/);
  assert.doesNotMatch(block[0], /queue:/);
  const main = (run_id, run_attempt = 1) => ({ event_name: "workflow_dispatch", ref: "refs/heads/main", workflow: "pr-require-checks", run_id, run_attempt, event: { pull_request: { head: { repo: {} } }, changes: {} } });
  assert.equal(group(main(1)), group(main(2)));
  assert.equal(cancel(main(1)), false);
  // A re-run keeps its own group, so no newer dispatch replaces the one
  // re-run a red run waits on (babysit_postmerge.py reads it red otherwise).
  assert.equal(group(main(3, 2)), "pr-require-checks-3");
  assert.equal(cancel(main(3, 2)), true);
});

test("pr-require-checks.yml keeps every other run's group and cancel", () => {
  const { group, cancel } = checksConcurrency();
  // A missing event field reads null in an expression; this stands in for it.
  const none = { pull_request: { head: { repo: {} } }, changes: {} };
  const other = [
    { event_name: "workflow_dispatch", ref: "refs/heads/feat/x", workflow: "pr-require-checks", run_id: 7, event: none },
    { event_name: "schedule", ref: "refs/heads/main", workflow: "pr-require-checks", run_id: 8, event: none },
    { event_name: "merge_group", ref: "refs/heads/gh-readonly-queue/main/pr-1", workflow: "pr-require-checks", run_id: 9, event: none },
  ];
  for (const github of other) {
    assert.equal(group(github), `pr-require-checks-${github.run_id}`, github.event_name);
    assert.equal(cancel(github), true, github.event_name);
  }
  assert.equal(group(prEvent("synchronize")), "pr-require-checks-5");
  assert.equal(group(prEvent("labeled")), "ci-contract-5-905");
  assert.equal(cancel(prEvent("synchronize")), true);
});

// Only a scheduled or hand-started run arms (enable-auto-merge.mjs
// READER_EVENTS), and a pull request the issue lane just opened is not armed,
// so the issue lane finishing would give the job nothing to do: no
// workflow_run trigger wakes it.
test("no workflow_run trigger wakes pr-merge, and the enable-auto-merge job skips push", () => {
  const on = merge.slice(merge.indexOf("\non:\n"), merge.indexOf("\npermissions:"));
  assert.doesNotMatch(on, /\n {2}workflow_run:/);
  const condition = (body) => /\n {4}if: >-\n([\s\S]*?)\n {4}(?:[a-z-]+:|#)/.exec(body)[1];
  assert.doesNotMatch(condition(job("merge")), /workflow_run/);
  const arm = job("enable-auto-merge");
  const armIf = condition(arm);
  assert.doesNotMatch(armIf, /workflow_run/);
  // A push to main is a merge landing, never a new lane pull request.
  assert.match(armIf, /github\.event_name != 'push'/);
  assert.match(arm, /\n {4}concurrency:\n {6}group: pr-merge-enable-auto-merge\n {6}queue: max\n/);
});

// A job its condition skips never joins the group, so a pull request the job
// cannot arm (not the lanes App's) shows a skipped check, not one pending
// behind every queued run. The other events keep their conditions.
test("a pull request event wakes enable-auto-merge only for a lanes App pull request", () => {
  const armIf = /\n {4}if: >-\n([\s\S]*?)\n {4}[a-z-]+:/.exec(job("enable-auto-merge"))[1];
  assert.match(
    armIf,
    /\(github\.event_name != 'pull_request_target'\n {6}\|\| \(github\.event\.pull_request\.head\.repo\.full_name == github\.repository\n {6}&& format\('\{0\}', github\.event\.pull_request\.user\.id\) == vars\.AUTOMATION_LANES_APP_SENDER_ID\n {6}&& github\.event\.sender\.type != 'Bot'\)\)\n/,
  );
  assert.match(armIf, /^ {6}!cancelled\(\)\n/);
  assert.doesNotMatch(armIf, /schedule|workflow_dispatch/);
});

// A bot-sent pull_request_target run would wait in the queue and then stop at
// who.mjs (a bot is never a listed human), so the job's condition skips it
// first. The condition's syntax is the subset JavaScript reads the same way,
// so the test evaluates it against hand-written events.
const evalIf = (id, event) => {
  const text = /\n {4}if: >-\n([\s\S]*?)\n {4}(?:[a-z-]+:|#)/.exec(job(id))[1].replaceAll("\n", " ");
  const format = (template, value) => template.replace("{0}", value);
  return new Function("github", "vars", "cancelled", "format", `return (${text});`)(
    { ref: "refs/heads/main", repository: "o/r", ...event },
    { AUTOMATION_LANES_APP_SENDER_ID: "99" },
    () => false,
    format,
  );
};
const pullRequestEvent = (senderType) => ({
  event_name: "pull_request_target",
  event: { sender: { type: senderType }, pull_request: { head: { repo: { full_name: "o/r" } }, user: { id: 99 } } },
});

for (const id of ["merge", "enable-auto-merge"]) {
  test(`${id} skips a bot-sent pull_request_target run and runs a user-sent one`, () => {
    assert.equal(evalIf(id, pullRequestEvent("Bot")), false);
    assert.equal(evalIf(id, pullRequestEvent("User")), true);
  });

  test(`${id} does not gate schedule or workflow_dispatch on the sender type`, () => {
    for (const event_name of ["schedule", "workflow_dispatch"]) {
      for (const type of ["Bot", "User"]) {
        assert.equal(evalIf(id, { event_name, event: { sender: { type } } }), true, `${event_name} sent by ${type}`);
      }
    }
  });
}

// The merge job's skip, run for enable-auto-merge's own group before the lane
// token or any other read.
test("enable-auto-merge skips its work when a waiting run's enable-auto-merge job does it", () => {
  const arm = job("enable-auto-merge");
  const step = /- name: Check for a newer run that does this work\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)?.[1];
  assert.ok(step, "a superseded step");
  assert.match(step, /^ {8}id: superseded\n {8}if: steps\.who\.outputs\.proceed == 'true'\n {8}continue-on-error: true\n/);
  assert.match(step, /\n {10}ACTIONS_TOKEN: \$\{\{ github\.token \}\}\n {10}SUPERSEDED_JOB: enable-auto-merge\n/);
  assert.match(step, /\n {8}run: node \.base\/\.github\/scripts\/pr-merge\/superseded\.mjs\n/);
  const names = [...arm.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.equal(names.indexOf("Check for a newer run that does this work"), names.indexOf("Check who started the run") + 1);
  assert.ok(names.indexOf("Check for a newer run that does this work") < names.indexOf("Request the lane token"));
  assert.match(arm, /- name: Resolve the config\n {8}id: config\n {8}if: steps\.who\.outputs\.proceed == 'true' && steps\.superseded\.outputs\.superseded != 'true'\n/);
  // The merge job asks for its own job, by default.
  assert.doesNotMatch(job("merge"), /SUPERSEDED_JOB/);
});

// Each job's readers of the files the last run kept share one file of GET
// answers in that job's RUNNER_TEMP; the readers' tests count what it saves.
test("the merge and enable-auto-merge jobs' kept-file readers share their reads", () => {
  for (const [id, scripts] of [
    ["merge", ["rotation.mjs", "head-ref-map.mjs read", "lane-records.mjs read", "listing-carry.mjs"]],
    ["enable-auto-merge", ["head-ref-map.mjs read", "lane-records.mjs read", "verify-answers.mjs", "listing-carry.mjs"]],
    ["post-merge-dispatch", ["lane-records.mjs read", "last-report.mjs"]],
  ]) {
    for (const script of scripts) {
      const step = new RegExp(`\\n {10}PR_MERGE_READS_PATH: (.*)\\n {8}run: node \\.base/\\.github/scripts/pr-merge/${script.replace(".", "\\.")}\\n`).exec(job(id));
      assert.equal(step?.[1], "${{ runner.temp }}/pr-merge-reads.json", `${id}: ${script}`);
    }
  }
});

test("the last verifier read enable-auto-merge starts ends inside its step's timeout", () => {
  const arm = job("enable-auto-merge");
  const step = /- name: Arm and disarm auto-merge\n {8}id: arm\n {8}if: .*\n {8}timeout-minutes: ([0-9]+)\n/.exec(arm);
  assert.ok(step, "the arm step names its timeout");
  // The room read, then the verdict budget and the last read it starts.
  assert.ok(LANE_ROOM_TIMEOUT_MS + VERIFY_BUDGET_MS + VERIFY_TIMEOUT_MS < Number(step[1]) * 60_000);
  // A read of a kept refusal alone starts no later than its window past the
  // budget and ends inside the same bound.
  assert.ok(CACHE_ONLY_WINDOW_MS + CACHE_ONLY_TIMEOUT_MS <= VERIFY_TIMEOUT_MS);
});

test("enable-auto-merge logs both tokens' readings at job end, before the token is revoked", () => {
  const arm = job("enable-auto-merge");
  const block = /- name: Log the API budget at job end\n([\s\S]*?)(?=\n {6}- name: |$)/.exec(arm)?.[1];
  assert.ok(block, "a job-end budget step");
  assert.match(block, /\n {8}uses: \.\/\.base\/\.github\/actions\/log-api-budget /);
  assert.match(block, /^ {8}id: budget-end\n {8}if: always\(\) && needs\.post-merge-dispatch\.outputs\.rate-limited == ''\n/);
  assert.match(block, /\n {8}continue-on-error: true\n {8}timeout-minutes: 1\n/);
  assert.match(block, /\n {10}tokens: lanes-app github-token\n/);
  // The reader's gh calls read into both names.
  const step = /- name: Arm and disarm auto-merge\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)[1];
  assert.match(step, /\n {10}API_BUDGET_TOKEN: lanes-app\n {10}API_BUDGET_OVERRIDE_TOKEN: github-token\n/);
  const names = [...arm.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.ok(names.indexOf("Arm and disarm auto-merge") < names.indexOf("Log the API budget at job end"));
  assert.ok(names.indexOf("Log the API budget at job end") < names.indexOf("Revoke the lane token"));
});

// The hub ranks GITHUB_TOKEN spend by each job's `api-calls` notice, so a
// job that calls GitHub with the job token and logs nothing is spend no one
// sees. Every such job carries the log-api-budget step, run whatever failed
// or stopped before it, naming github-token: under `always()` alone, so a job
// that ends before it mints a lane token still logs the job token's calls. A
// token with no reading logs 0 (log-api-budget.test.mjs).
test("every job that calls GitHub with the job token logs its api-calls", () => {
  const ids = [...jobs.matchAll(/\n {2}([a-z-]+):\n/g)].map((m) => m[1]);
  const callers = ids.filter((id) => job(id).includes("${{ github.token }}"));
  for (const id of ["post-merge-dispatch", "merge", "enable-auto-merge", "unarmed-status", "dispatch-full-run", "gate-check"]) {
    assert.ok(callers.includes(id), `${id} calls GitHub with the job token`);
  }
  const unlogged = callers.filter((id) => {
    const step = `\n${/- name: Log the API budget[^\n]*\n([\s\S]*?)(?=\n {6}- name: |$)/.exec(job(id))?.[1] ?? ""}`;
    return !(
      /\n {8}if: always\(\)(?: && needs\.post-merge-dispatch\.outputs\.rate-limited == '')?\n/.test(step) &&
      /\n {8}continue-on-error: true\n/.test(step) &&
      /\n {8}uses: \.\/\.base\/\.github\/actions\/log-api-budget /.test(step) &&
      /\n {10}tokens: (?:[a-z-]+ )*github-token\b/.test(step)
    );
  });
  assert.deepEqual(unlogged, []);
});

// A node step whose only token is the job token and whose script builds a
// createGitHub client keeps each answer's reading under github-token (the
// client's rate guard writes it when API_BUDGET_TOKEN names the bucket), or
// the job-end notice counts nothing; one that also holds the lane token names
// lanes-app and the github-token override. A step whose script calls nothing
// needs no bucket, so none is asked of it.
test("every createGitHub step that calls GitHub with the job token names the bucket its calls go to", () => {
  const ids = [...jobs.matchAll(/\n {2}([a-z-]+):\n/g)].map((m) => m[1]);
  const unnamed = [];
  const needless = [];
  for (const id of ids) {
    const body = job(id);
    const jobBucket = /(?:^|\n) {4}env:\n(?: {6}.*\n)*? {6}API_BUDGET_TOKEN: ([a-z-]+)$/m.exec(body.split("\n    steps:\n")[0])?.[1];
    for (const step of body.split(/\n {6}- name: /).slice(1)) {
      const name = step.split("\n")[0];
      const script = /\n {8}run: (?:\|\n(?: {10}.*\n|\s*\n)*? {10})?(?:[A-Z_]+=\S+ )*node \.base\/(\S+\.mjs)/.exec(step)?.[1];
      if (!script || !step.includes("${{ github.token }}")) {
        continue;
      }
      const calls = readFileSync(new URL(`../../../${script}`, import.meta.url), "utf8").includes("createGitHub(");
      const bucket = /\n {10}API_BUDGET_TOKEN: ([a-z-]+)\n/.exec(step)?.[1];
      // A step that also holds the lane token as its GH_TOKEN counts that
      // token's calls under lanes-app and the job token's under the override
      // (rate-guard.mjs budgetToken).
      if (step.includes("${{ steps.lane-token.outputs.token }}")) {
        const override = /\n {10}API_BUDGET_OVERRIDE_TOKEN: ([a-z-]+)\n/.exec(step)?.[1];
        if (calls && (bucket !== "lanes-app" || override !== "github-token")) {
          unnamed.push(`${id}: ${name}`);
        }
        continue;
      }
      if (calls && (bucket ?? jobBucket) !== "github-token") {
        unnamed.push(`${id}: ${name}`);
      }
      if (!calls && bucket !== undefined) {
        needless.push(`${id}: ${name}`);
      }
    }
  }
  assert.deepEqual(unnamed, []);
  assert.deepEqual(needless, []);
});

// The sweep-count step's one read, the run's start, goes through the wrapped
// gh, so the job-end notice counts it; sweep-summary.mjs calls nothing.
test("the merge job's sweep-count read leaves one github-token reading", () => {
  const step = /- name: Count the sweep's refusals\n([\s\S]*?)(?=\n {6}- name: )/.exec(job("merge"))[1];
  const run = /\n {8}run: \|\n((?: {10}.*\n|\s*\n)+)/.exec(step)[1].replace(/^ {10}/gm, "");
  const dir = tempDir("pr-merge-sweep-count-");
  try {
    mkdirSync(join(dir, "bin"));
    symlinkSync(fileURLToPath(new URL("../../..", import.meta.url)), join(dir, ".base"));
    const headers = "X-Ratelimit-Limit: 5000\\r\\nX-Ratelimit-Remaining: 4000\\r\\nX-Ratelimit-Used: 1000\\r\\nX-Ratelimit-Reset: 9999999999\\r\\nX-Ratelimit-Resource: core\\r\\n\\r\\n";
    writeFileSync(
      join(dir, "bin", "gh"),
      `#!/usr/bin/env bash
printf 'HTTP/2.0 200 OK\\r\\n${headers}'
while [ $# -gt 0 ]; do if [ "$1" = --jq ]; then echo '{"run_started_at":"2026-10-28T00:00:00Z"}' | jq -r "$2"; exit; fi; shift; done
`,
      { mode: 0o755 },
    );
    writeFileSync(join(dir, "bin", "node"), "#!/usr/bin/env bash\necho \"$RUN_STARTED_AT\" >\"$RUNNER_TEMP/started\"\n", { mode: 0o755 });
    writeFileSync(join(dir, "sweep.json"), '{"refusal_counts":{}}');
    const r = spawnSync("bash", ["-c", run], {
      cwd: dir,
      encoding: "utf8",
      env: { PATH: `${join(dir, "bin")}:${process.env.PATH}`, GH_TOKEN: "x", REPO: "o/r", GITHUB_RUN_ID: "77", LIMITED: "", LISTING_HELD: "", RUNNER_TEMP: dir, SWEEP_SUMMARY_TO: join(dir, "sweep.json") },
    });
    assert.equal(r.status, 0, r.stdout + r.stderr);
    assert.equal(readFileSync(join(dir, "started"), "utf8"), "2026-10-28T00:00:00Z\n");
    assert.equal(readFileSync(join(dir, "api-budget", "github-token"), "utf8"), "200 5000 4000 1000 9999999999 core repos/{repo}/actions/runs/{n}\n");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// A run that stops at the superseded step, before the lane token, still
// ends with the job token's calls: who's read, the pending-run listing and
// the waiting run's jobs read, each through createGitHub.
for (const jobId of ["merge", "enable-auto-merge"]) {
  test(`${jobId}: a run that stops as superseded still logs its github-token calls`, async () => {
    const body = job(jobId);
    const stepOf = (name) => new RegExp(`- name: ${name}\\n([\\s\\S]*?)(?=\\n {6}- name: |\\n*$)`).exec(body)?.[1];
    const context = { "github.event_name": "workflow_dispatch", "github.actor_id": String(OWNER.id), "github.token": "t" };
    const envOf = (step) =>
      Object.fromEntries([...step.matchAll(/^ {10}([A-Z_]+): (.*)$/gm)].map(([, k, v]) => [k, v.replace(/\$\{\{ (\S+) \}\}/g, (_, e) => context[e] ?? "")]));
    const answers = {
      "/repos/o/r/actions/runs/4242": { id: 4242, run_attempt: 2, actor: OWNER, triggering_actor: OWNER },
      "/repos/o/r/actions/workflows/pr-merge.yml/runs": { workflow_runs: [{ id: 5000, status: "pending", event: "schedule", head_branch: "main", run_attempt: 1 }] },
      "/repos/o/r/actions/runs/5000/jobs": { jobs: [{ name: jobId, status: "waiting" }] },
    };
    const server = createServer((req, res) => {
      const answer = answers[req.url.split("?")[0]];
      res.writeHead(answer ? 200 : 404, {
        "Content-Type": "application/json",
        "X-Ratelimit-Limit": "5000",
        "X-Ratelimit-Remaining": "4000",
        "X-Ratelimit-Used": "1000",
        "X-Ratelimit-Reset": "9999999999",
        "X-Ratelimit-Resource": "core",
      });
      res.end(JSON.stringify(answer ?? { message: "Not Found" }));
    });
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    const dir = tempDir("pr-merge-superseded-budget-");
    try {
      symlinkSync(fileURLToPath(new URL("../../../", import.meta.url)), join(dir, ".base"));
      const output = join(dir, "output");
      writeFileSync(output, "");
      writeFileSync(join(dir, "summary"), "");
      const base = {
        PATH: process.env.PATH,
        RUNNER_TEMP: dir,
        GITHUB_OUTPUT: output,
        GITHUB_STEP_SUMMARY: join(dir, "summary"),
        GITHUB_REPOSITORY: "o/r",
        GITHUB_RUN_ID: "4242",
        GITHUB_RUN_ATTEMPT: "2",
        GITHUB_EVENT_NAME: "workflow_dispatch",
        GITHUB_API_URL: `http://127.0.0.1:${server.address().port}`,
        NODE_OPTIONS: "--preserve-symlinks-main",
      };
      let stdout = "";
      for (const name of ["Check who started the run", "Check for a newer run that does this work"]) {
        const step = stepOf(name);
        const run = /\n {8}run: (.*)/.exec(step)[1];
        const status = await new Promise((resolve) => {
          const child = spawn("bash", ["-ec", run], { cwd: dir, env: { ...base, ...envOf(step) }, stdio: ["ignore", "pipe", "ignore"] });
          child.stdout.on("data", (chunk) => (stdout += chunk));
          child.on("close", resolve);
        });
        assert.equal(status, 0, name);
      }
      // enable-auto-merge names each step (API_BUDGET_SCRIPT), so its job
      // total splits by step: who's one read, superseded's two. The merge job
      // names none.
      assert.deepEqual(
        stdout.match(/^::notice title=api-calls::script=.*$/gm) ?? [],
        jobId === "enable-auto-merge"
          ? [
              "::notice title=api-calls::script=who github-token=1 lanes-app=0 not-modified=0 graphql=0",
              "::notice title=api-calls::script=superseded github-token=2 lanes-app=0 not-modified=0 graphql=0",
            ]
          : [],
      );
      assert.match(readFileSync(output, "utf8"), /^proceed=true$/m);
      assert.match(readFileSync(output, "utf8"), /^superseded=true$/m);
      const log = stepOf("Log the API budget at job end");
      assert.match(log, /^ {8}id: budget-end\n {8}if: always\(\) && needs\.post-merge-dispatch\.outputs\.rate-limited == ''\n/);
      const action = readFileSync(new URL("../../actions/log-api-budget/action.yml", import.meta.url), "utf8");
      const out = spawnSync("bash", ["-c", /\n {6}run: \|\n([\s\S]*)$/.exec(action)[1].replace(/^ {8}/gm, "")], {
        cwd: dir,
        encoding: "utf8",
        env: { ...base, GITHUB_ACTION_PATH: fileURLToPath(new URL("../../actions/log-api-budget/", import.meta.url)), TOKENS: /\n {10}tokens: (.*)\n/.exec(log)[1] },
      });
      assert.match(out.stdout, /^::notice title=api-calls::github-token=3 not-modified=0 graphql=0$/m);
      assert.match(out.stdout, /^::notice title=api-calls::lanes-app=0 not-modified=0 graphql=0$/m);
    } finally {
      server.close();
      rmSync(dir, { recursive: true, force: true });
    }
  });
}

// The lane's room (lane-room) reads this run's post-merge report, which
// post-merge-dispatch keeps, rather than running the check a third time per
// scheduled run, and the rung cap as the merge job passes it: an unset cap
// holds the lane off, so a step that drops it would disarm every lane pull
// request.
test("enable-auto-merge reads the lane's room from this run's post-merge-dispatch report and the rung cap", () => {
  const dispatch = job("post-merge-dispatch");
  const keep = /- name: Keep the post-merge report for enable-auto-merge\n([\s\S]*?)(?=\n {6}- name: |\n*$)/.exec(dispatch)?.[1];
  assert.ok(keep, "post-merge-dispatch keeps its report");
  assert.match(keep, /uses: actions\/upload-artifact@[0-9a-f]{40} /);
  // The directory holds post-merge.json, so the download below finds it at
  // post-merge/post-merge.json.
  assert.match(keep, /\n {10}name: pr-merge-post-merge-report\n {10}path: \$\{\{ runner\.temp \}\}\/post-merge-report\/\n {10}retention-days: 1\n/);
  assert.match(dispatch, /\n {10}cp "\$RUNNER_TEMP\/post-merge\.json" "\$kept\/post-merge\.json"\n/);
  const arm = job("enable-auto-merge");
  assert.match(arm, /^ {4}# [\s\S]*?\n {4}needs: \[post-merge-dispatch\]\n/);
  assert.match(/\n {4}if: >-\n([\s\S]*?)\n {4}[a-z-]+:/.exec(arm)[1], /^ {6}!cancelled\(\)\n/);
  // No check of its own: the report comes from this run's job alone.
  assert.doesNotMatch(arm, /python3 [^\n]*babysit_postmerge\.py/);
  const read = /- name: Read this run's post-merge report\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)?.[1];
  assert.ok(read, "a download of the report");
  assert.match(read, /uses: actions\/download-artifact@[0-9a-f]{40} /);
  assert.match(read, /\n {10}name: pr-merge-post-merge-report\n/);
  // Not 'success': a step after the kept report can fail the job.
  assert.match(read, /needs\.post-merge-dispatch\.result != 'skipped'/);
  assert.doesNotMatch(read, /run-id|github-token|repository:/);
  const step = /- name: Arm and disarm auto-merge\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)[1];
  assert.match(step, /\n {10}POSTMERGE_RESULT: \$\{\{ runner\.temp \}\}\/post-merge\/post-merge\.json\n/);
  // The commit whose code ran it, kept beside it, for lane-room.
  assert.match(dispatch, /\n {10}git -C \.base rev-parse HEAD >"\$kept\/post-merge-code-sha" \|\| true\n/);
  assert.match(step, /\n {10}POSTMERGE_CODE_SHA=\$\(cat "\$RUNNER_TEMP\/post-merge\/post-merge-code-sha" 2>\/dev\/null \|\| true\)\n/);
  assert.match(step, /\n {10}export [^\n]*\bPOSTMERGE_CODE_SHA\n/);
  assert.match(step, /\n {10}RUNG_CAP: \$\{\{ vars\.CLAUDE_LANES_MERGE_RUNG_CAP \}\}\n/);
  const names = [...arm.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.ok(names.indexOf("Read this run's post-merge report") < names.indexOf("Arm and disarm auto-merge"));
});

// A room that checks the post-merge answer again reads the lane records the
// last run kept, as post-merge-dispatch's check does, so the check answers
// them with no artifact or run read each; without them the check can run
// past the room's LANE_ROOM_TIMEOUT_MS.
test("enable-auto-merge hands the room's post-merge check the lane records the last run kept", () => {
  const arm = job("enable-auto-merge");
  const records = /- name: Read the lane records the last run kept\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)?.[1];
  assert.ok(records, "a lane-records read");
  assert.match(records, /\n {8}continue-on-error: true\n/);
  assert.match(records, /\n {10}ACTIONS_TOKEN: \$\{\{ github\.token \}\}\n {10}LANE_RECORDS_PATH: \$\{\{ runner\.temp \}\}\/lane-records\.json\n/);
  assert.match(records, /\n {8}run: node \.base\/\.github\/scripts\/pr-merge\/lane-records\.mjs read\n/);
  const step = /- name: Arm and disarm auto-merge\n([\s\S]*?)(?=\n {6}- name: )/.exec(arm)[1];
  assert.match(step, /\n {10}BABYSIT_POSTMERGE_LANE_RECORDS: \$\{\{ runner\.temp \}\}\/lane-records\.json\n/);
  const names = [...arm.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.ok(names.indexOf("Read the lane records the last run kept") < names.indexOf("Arm and disarm auto-merge"));
  // Within the job's own permissions: the read needs actions: read alone.
  assert.match(arm, /\n {6}actions: read #/);
});

// Without history the post-merge check's containment test cannot decide, and
// every lane record falls back to a compare API call.
test("the default branch checkouts of the post-merge check, the merge and enable-auto-merge fetch full history", () => {
  for (const name of ["post-merge-dispatch", "merge", "enable-auto-merge"]) {
    const checkout = /- name: Check out the default branch tip\n([\s\S]*?)(?=\n {6}- name: |\n*$)/.exec(job(name))?.[1];
    assert.ok(checkout, `${name} checks out the default branch tip`);
    assert.match(checkout, /\n {10}fetch-depth: 0\n/, name);
  }
});

test("enable-auto-merge's step timeouts fit inside its job's", () => {
  const arm = job("enable-auto-merge");
  const total = Number(/\n {4}timeout-minutes: ([0-9]+)\n/.exec(arm)[1]);
  const steps = [...arm.matchAll(/\n {8}timeout-minutes: ([0-9]+)\n/g)].map((m) => Number(m[1]));
  assert.ok(steps.length >= 4, "the post-merge check, the run cache read, the arm step and the budget step name timeouts");
  assert.ok(steps.reduce((sum, minutes) => sum + minutes, 0) < total, `${steps.join(" + ")} inside ${total}`);
});

// pr-unblock's report-conflict-status precedent: statuses: write only on a
// job that holds no lane token and runs only main's script.
test("the pr-merge/unarmed statuses are posted by a job of their own, with statuses: write and nothing it could run from a pull request", () => {
  const arm = job("enable-auto-merge");
  assert.match(arm, /\n {4}outputs:\n {6}unarmed-statuses: \$\{\{ steps\.arm\.outputs\.unarmed-statuses \}\}\n/);
  assert.match(arm, /\n {6}- name: Arm and disarm auto-merge\n {8}id: arm\n/);
  assert.match(arm, /RISK_ESCALATION_MINUTES=\$\(yq '\.merge\."risk-escalation-minutes" \/\/ ""' "\$config"\)\n/);
  const post = job("unarmed-status");
  assert.match(post, /^ {4}needs: \[enable-auto-merge\]\n/);
  // It runs whenever enable-auto-merge handed it statuses, after a failed
  // step too, and only then.
  assert.match(post, /\n {4}if: \$\{\{ !cancelled\(\) && needs\.enable-auto-merge\.outputs\.unarmed-statuses != '' \}\}\n/);
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(post)[1];
  assert.deepEqual(
    [...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => `${m[1]}: ${m[2]}`),
    ["contents: read", "statuses: write"],
  );
  assert.doesNotMatch(post, /lane-token|request-lane-token|id-token/);
  assert.match(post, /\n {10}ref: refs\/heads\/main\n {10}path: \.base\n {10}persist-credentials: false\n/);
  // The statuses reach the script through its environment, never the shell.
  assert.match(post, /\n {10}STATUSES: \$\{\{ needs\.enable-auto-merge\.outputs\.unarmed-statuses \}\}\n {8}run: node \.base\/\.github\/scripts\/pr-merge\/post-unarmed-status\.mjs\n/);
});

// The merge job's sizing comment: about two minutes before the loop, then the
// longer of the gate budget (10) plus a candidate's read limit (4) and a
// deferred candidate's ceiling (20), plus one read's own timeout (4); the
// escalation clear's own timeout comes on top.
test("the merge job's ceiling covers the gate's sweep and the escalation clear", () => {
  const gate = job("merge");
  const total = Number(/\n {4}timeout-minutes: ([0-9]+)\n/.exec(gate)[1]);
  const clear = Number(/- name: Clear escalations whose reason no longer holds\n[\s\S]*?\n {8}timeout-minutes: ([0-9]+)\n/.exec(gate)[1]);
  assert.ok(total >= 2 + Math.max(10 + 4, 20) + 4 + clear, `${total} minutes for the gate and a ${clear}-minute clear`);
});

test("enable-auto-merge asks the broker for its own activity's merge token", () => {
  const arm = job("enable-auto-merge");
  const steps = [...arm.matchAll(/\n {10}lane: (.*)\n {10}activity: (.*)\n/g)].map((m) => `${m[1]}/${m[2]}`);
  assert.deepEqual(steps, ["pr-merge/enable-auto-merge", "pr-merge/enable-auto-merge"]);
  assert.match(arm, /node \.base\/\.github\/scripts\/pr-merge\/enable-auto-merge\.mjs/);
  // A missing merge.report-only reaches the script as `null`, which it reads
  // as report-only; the job must not turn it into `false`.
  assert.match(arm, /REPORT_ONLY=\$\(yq '\.merge\."report-only"' "\$config"\)\n/);
  assert.doesNotMatch(arm, /REPORT_ONLY=false/);
  // The hold paths come from the config the job resolved.
  assert.match(arm, /output-path: \$\{\{ runner\.temp \}\}\/resolved-config\.json\n/);
  assert.match(arm, /\n {10}RESOLVED_CONFIG: \$\{\{ runner\.temp \}\}\/resolved-config\.json\n/);
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(arm)[1];
  assert.deepEqual(
    [...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => `${m[1]}: ${m[2]}`),
    // statuses: read for the head's pr-unblock statuses: GitHub lists that
    // endpoint under the "Commit statuses" read permission, which the lanes
    // App does not hold.
    ["contents: read", "actions: read", "pull-requests: read", "checks: read", "issues: read", "statuses: read", "id-token: write"],
  );
  // The verifier evidence is read as the gate reads it: the job's
  // GITHUB_TOKEN for the Actions reads, with the run's head-ref map and
  // carried run cache.
  for (const line of [
    "EVENT_NAME: ${{ github.event_name }}",
    "BABYSIT_VERIFY_GH_TOKEN: ${{ github.token }}",
    "BABYSIT_VERIFY_HEAD_REFS: ${{ runner.temp }}/head-refs-in.json",
    "BABYSIT_RUN_CACHE: ${{ runner.temp }}/babysit-run-cache.json",
  ]) {
    assert.ok(arm.includes(`\n          ${line}\n`), line);
  }
  assert.match(arm, /node \.base\/\.github\/scripts\/pr-merge\/head-ref-map\.mjs read\n/);
  // Only the runs that read the verdict (READER_EVENTS) read the map.
  assert.match(
    arm,
    /- name: Read the head refs the last gate run kept\n {8}if: steps\.lane-token\.outputs\.token != '' && \(github\.event_name == 'schedule' \|\| github\.event_name == 'workflow_dispatch'\)\n/,
  );
  // The reader resolves the FAIL cap itself, from the base and main (--base-sha).
  assert.doesNotMatch(arm, /MAX_VERIFY_FAILS/);
});

// The dispatch POST's retry, run under bash against a stub gh that answers
// each POST in turn from `answers` ({status, headers, body}, or {stderr} for
// no response at all, with gh's error text), a stub sleep that logs its seconds and a stub date
// whose `+%s` is NOW. The expected answers come from the owner outage rule
// (at most three attempts, a capped full-jitter backoff) and the owner's
// ban rule: a rate limit is never sent again, and the step fails red naming
// the reset, the later of retry-after and x-ratelimit-reset while remaining
// is 0, else a minute on, as GitHub documents the waits
// (https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).
// Each expected reset below is `date -u -d @<seconds>` of the NOW sum.
const NOW = 1792736000;
const runBody = (block) =>
  /\n {8}run: \|\n((?: {10}.*\n|\s*\n)+)/
    .exec(block)[1]
    .split("\n")
    .map((l) => l.slice(10))
    .join("\n")
    .trimEnd();
const dispatchStep = (id) => {
  const block = job(id).split("\n      - name: Start the full CI run on main\n")[1].split("\n      - name: ")[0];
  return { body: runBody(block), cap: /\n {10}WAIT_CAP: (\d+)\n/.exec(block)[1] };
};
const ok = (id) => ({ status: "200 OK", headers: {}, body: JSON.stringify({ workflow_run_id: id }) });
const limited = (headers, message = "API rate limit exceeded for installation") => ({
  status: "403 Forbidden",
  headers,
  body: JSON.stringify({ message }),
});
function runDispatch(answers, { jobId = "dispatch-full-run", cap, event = "push" } = {}) {
  const step = dispatchStep(jobId);
  const dir = tempDir("pr-merge-dispatch-");
  mkdirSync(join(dir, "bin"));
  answers.forEach((a, i) => {
    const text =
      a.status === undefined
        ? ""
        : `HTTP/2.0 ${a.status}\n${Object.entries(a.headers)
            .map(([k, v]) => `${k}: ${v}\r\n`)
            .join("")}\r\n${a.body}`;
    writeFileSync(join(dir, `answer-${i + 1}`), text);
    writeFileSync(join(dir, `stderr-${i + 1}`), a.stderr ?? "");
    writeFileSync(join(dir, `code-${i + 1}`), a.status?.startsWith("200") ? "0" : "1");
  });
  writeFileSync(
    join(dir, "bin", "gh"),
    `#!/usr/bin/env bash
n=$(($(cat "${dir}/calls" 2>/dev/null || echo 0) + 1)); echo "$n" >"${dir}/calls"
printf '%s\\n' "$*" >>"${dir}/log"
cat "${dir}/answer-$n" 2>/dev/null
cat "${dir}/stderr-$n" >&2 2>/dev/null
exit "$(cat "${dir}/code-$n" 2>/dev/null || echo 1)"
`,
    { mode: 0o755 },
  );
  writeFileSync(join(dir, "bin", "sleep"), `#!/bin/sh\necho "$1" >>"${dir}/slept"\n`, { mode: 0o755 });
  const realDate = spawnSync("bash", ["-c", "command -v date"], { encoding: "utf8" }).stdout.trim();
  writeFileSync(join(dir, "bin", "date"), `#!/bin/sh\nif [ "$1" = +%s ]; then echo ${NOW}; else exec ${realDate} "$@"; fi\n`, { mode: 0o755 });
  writeFileSync(join(dir, "body.sh"), step.body);
  writeFileSync(join(dir, "output"), "");
  const result = spawnSync("bash", ["-e", join(dir, "body.sh")], {
    env: {
      ...process.env,
      PATH: `${join(dir, "bin")}:${process.env.PATH}`,
      GH_TOKEN: "x",
      REPO: "o/r",
      WAIT_CAP: cap ?? step.cap,
      GITHUB_EVENT_NAME: event,
      GITHUB_SHA: HEAD,
      GITHUB_RUN_ID: "77",
      GITHUB_OUTPUT: join(dir, "output"),
      RUNNER_TEMP: dir,
    },
    encoding: "utf8",
  });
  const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
  const out = {
    status: result.status,
    out: result.stdout + result.stderr,
    posts: read("log").split("\n").filter((l) => l.includes("-X POST")).length,
    slept: read("slept").split("\n").filter(Boolean).map(Number),
    output: read("output"),
    record: read("dispatched.json"),
  };
  rmSync(dir, { recursive: true, force: true });
  return out;
}

test("both jobs send the dispatch with the same retry", () => {
  assert.equal(dispatchStep("post-merge-dispatch").body, dispatchStep("dispatch-full-run").body);
});

test("a dispatch answered at once records its run and waits for nothing", () => {
  const r = runDispatch([ok(4242)]);
  assert.equal(r.status, 0, r.out);
  assert.equal(r.posts, 1);
  assert.deepEqual(r.slept, []);
  assert.match(r.output, /^run-id=4242$/m);
  assert.deepEqual(JSON.parse(r.record), { dispatcher_run_id: 77, run_id: 4242 });
});

// A rate limit stops the step red after its one POST, with no wait.
const stopped = (r) => {
  assert.equal(r.status, 1, r.out);
  assert.equal(r.posts, 1);
  assert.deepEqual(r.slept, []);
  assert.doesNotMatch(r.output, /run-id=/);
  // post-merge-dispatch's re-run step reads it and sends nothing.
  assert.match(r.output, /^rate-limited=true$/m);
  assert.equal(r.record, "");
};

test("a retry-after stops every pool until the later of it and a spent pool's reset", () => {
  const r = runDispatch([limited({ "Retry-After": "7", "X-Ratelimit-Remaining": "0", "X-Ratelimit-Reset": `${NOW + 100}` }), ok(4243)]);
  stopped(r);
  assert.match(r.out, /::error title=GitHub rate limit::every pool is exhausted \(HTTP 403: .*\); nothing more is sent before 2026-10-23T06:15:00Z/);
});

test("a primary limit with no retry-after names its pool and the reset", () => {
  const r = runDispatch([limited({ "X-Ratelimit-Remaining": "0", "X-Ratelimit-Reset": `${NOW + 30}`, "X-Ratelimit-Resource": "core" }), ok(4244)]);
  stopped(r);
  assert.match(r.out, /::error title=GitHub rate limit::the core pool is exhausted .*before 2026-10-23T06:13:50Z/);
  // The merge job reads this through post-merge-dispatch's rate-limited output.
  assert.match(r.output, /^stop=the core pool until 2026-10-23T06:13:50Z$/m);
});

test("a secondary limit named only by its message stops every pool for a minute", () => {
  const r = runDispatch(
    [limited({ "X-Ratelimit-Remaining": "812" }, "You have exceeded a secondary rate limit"), ok(4245)],
    { jobId: "post-merge-dispatch", event: "schedule" },
  );
  stopped(r);
  assert.match(r.out, /::error title=GitHub rate limit::every pool is exhausted .*before 2026-10-23T06:14:20Z/);
});

test("a 429 is stopped like a 403", () => {
  const r = runDispatch([{ ...limited({ "Retry-After": "5" }), status: "429 Too Many Requests" }, ok(1)]);
  stopped(r);
});

// Any 429 is a rate limit, and a limit no header times waits as
// rate-guard.mjs classify decides: the minute for a secondary one, else the hour.
const DISPATCH_URL = "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches";
for (const [name, status, body] of [
  ["a bare 429 with no headers or message", 429, ""],
  ["a 403 whose message names a primary rate limit, with no headers", 403, JSON.stringify({ message: "API rate limit exceeded for installation" })],
  ["a 403 whose message names a secondary rate limit, with no headers", 403, JSON.stringify({ message: "You have exceeded a secondary rate limit" })],
  ["a 403 whose message names only abuse detection, with no headers", 403, JSON.stringify({ message: "You have triggered an abuse detection mechanism" })],
]) {
  test(`${name} stops every pool until the guard's reset`, () => {
    const want = classify({ url: DISPATCH_URL, status, headers: {}, body }, { now: NOW * 1000 });
    assert.equal(want.pool, "*");
    for (const jobId of ["dispatch-full-run", "post-merge-dispatch"]) {
      const r = runDispatch([{ status: `${status} X`, headers: {}, body }, ok(1)], { jobId, event: "schedule" });
      stopped(r);
      assert.match(r.out, new RegExp(`::error title=GitHub rate limit::every pool is exhausted \\(HTTP ${status}: .*before ${resetLabel(want.reset)}`));
    }
  });
}

test("a secondary limit with a spent pool still stops every pool, as the guard does", () => {
  const headers = { "x-ratelimit-remaining": "0", "x-ratelimit-reset": `${NOW + 30}`, "x-ratelimit-resource": "core" };
  const body = JSON.stringify({ message: "You have exceeded a secondary rate limit" });
  const want = classify({ url: DISPATCH_URL, status: 403, headers, body }, { now: NOW * 1000 });
  assert.equal(want.pool, "*");
  for (const jobId of ["dispatch-full-run", "post-merge-dispatch"]) {
    const r = runDispatch([{ status: "403 X", headers, body }, ok(1)], { jobId, event: "schedule" });
    stopped(r);
    assert.match(r.out, new RegExp(`::error title=GitHub rate limit::every pool is exhausted \\(HTTP 403: .*before ${resetLabel(want.reset)}`));
    assert.match(r.output, new RegExp(`^stop=every pool until ${resetLabel(want.reset)}$`, "m"));
  }
});

const refused = () => limited({ "X-Ratelimit-Remaining": "900" }, "Resource not accessible by integration");

test("a refusal ends green with a warning naming the merge, and no run id", () => {
  const r = runDispatch([refused(), ok(1)]);
  assert.equal(r.status, 0, r.out);
  assert.match(r.out, new RegExp(`::warning::no full CI run started for merge ${HEAD} after 1 attempt\\(s\\): HTTP 403`));
  assert.doesNotMatch(r.output, /run-id=/);
});

test("a scheduled run's warning names main at the run's start, not a merge", () => {
  const r = runDispatch([refused()], { jobId: "post-merge-dispatch", event: "schedule" });
  assert.match(r.out, new RegExp(`::warning::no full CI run started for main \\(this run started at ${HEAD}\\)`));
});

test("a wait past the job's cap is not taken", () => {
  const r = runDispatch([{ stderr: 'Post "https://api.github.com/x": dial tcp: lookup api.github.com: no such host' }, ok(1)], { cap: "0" });
  assert.equal(r.status, 0, r.out);
  assert.equal(r.posts, 1);
  assert.deepEqual(r.slept, []);
  assert.match(r.out, /::warning::.*wait does not fit the 0s this job allows/);
  assert.doesNotMatch(r.output, /run-id=/);
});

test("a refusal that is no rate limit, and a 5xx, are sent once", () => {
  for (const answer of [
    limited({ "X-Ratelimit-Remaining": "900" }, "Resource not accessible by integration"),
    { status: "422 Unprocessable Entity", headers: {}, body: '{"message":"No ref found for: main"}' },
    { status: "502 Bad Gateway", headers: {}, body: "" },
  ]) {
    const r = runDispatch([answer, ok(1)]);
    assert.equal(r.status, 0, r.out);
    assert.equal(r.posts, 1, answer.status);
    assert.deepEqual(r.slept, [], answer.status);
    assert.match(r.out, /::warning::no full CI run started/, answer.status);
  }
});

// gh's errors for a request that never left (Go net/http wording, as gh
// prints it): a DNS lookup, a refused connection, a failed TLS handshake.
const unsent = [
  'Post "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches": dial tcp: lookup api.github.com on 127.0.0.53:53: no such host',
  'Post "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches": dial tcp 140.82.112.6:443: connect: connection refused',
  'Post "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches": remote error: tls: handshake failure',
].map((stderr) => ({ stderr }));

test("a request that never left is sent again after a jittered wait inside its bound", () => {
  const r = runDispatch([unsent[0], unsent[1], ok(4246)]);
  assert.equal(r.status, 0, r.out);
  assert.equal(r.posts, 3);
  assert.equal(r.slept.length, 2);
  assert.ok(r.slept[0] >= 1 && r.slept[0] <= 10, `${r.slept[0]}`);
  assert.ok(r.slept[1] >= 1 && r.slept[1] <= 20, `${r.slept[1]}`);
  assert.match(r.output, /^run-id=4246$/m);
  assert.equal(runDispatch([unsent[2], ok(4247)]).posts, 2);
});

// Go's net/http error when the TLS handshake outlasts its timeout, before any
// request byte is written, so a resend cannot start a second run.
const handshakeTimeout = { stderr: `Post "${DISPATCH_URL}": net/http: TLS handshake timeout` };

test("a TLS handshake timeout is sent again in both jobs", () => {
  for (const jobId of ["dispatch-full-run", "post-merge-dispatch"]) {
    const r = runDispatch([handshakeTimeout, ok(4248)], { jobId, event: "schedule" });
    assert.equal(r.status, 0, r.out);
    assert.equal(r.posts, 2, jobId);
    assert.equal(r.slept.length, 1, jobId);
    assert.ok(r.slept[0] >= 1 && r.slept[0] <= 10, `${r.slept[0]}`);
    assert.match(r.output, /^run-id=4248$/m, jobId);
  }
});

// The resend never reaches past a rate limit: the attempt after the timeout
// is answered with one, and nothing is sent after it.
test("a rate limit after a TLS handshake timeout still stops red, with no further send", () => {
  for (const jobId of ["dispatch-full-run", "post-merge-dispatch"]) {
    const r = runDispatch([handshakeTimeout, limited({ "X-Ratelimit-Remaining": "0", "X-Ratelimit-Reset": `${NOW + 30}`, "X-Ratelimit-Resource": "core" }), ok(1)], { jobId, event: "schedule" });
    assert.equal(r.status, 1, r.out);
    assert.equal(r.posts, 2, jobId);
    assert.equal(r.slept.length, 1, jobId);
    assert.match(r.output, /^rate-limited=true$/m, jobId);
    assert.doesNotMatch(r.output, /run-id=/, jobId);
  }
});

// post-merge-dispatch's cover starts main's tip for any merge no run covers.
test("the exhausted-retry warning names who starts the run next", () => {
  for (const jobId of ["dispatch-full-run", "post-merge-dispatch"]) {
    const r = runDispatch([refused()], { jobId, event: "schedule" });
    assert.match(r.out, /::warning::no full CI run started .*; the next scheduled pr-merge run starts one for main's tip$/m, jobId);
  }
});

// A reset or a timeout on an open connection may come after GitHub took the
// request, so the run may exist: stop as on exhaustion.
test("no response once the request may have been sent is not sent again", () => {
  for (const stderr of [
    'Post "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches": read tcp 10.1.0.4:51234->140.82.112.6:443: read: connection reset by peer',
    'Post "https://api.github.com/repos/o/r/actions/workflows/pr-require-checks.yml/dispatches": context deadline exceeded (Client.Timeout exceeded while awaiting headers)',
    "",
  ]) {
    const r = runDispatch([{ stderr }, ok(1)]);
    assert.equal(r.status, 0, r.out);
    assert.equal(r.posts, 1, stderr);
    assert.deepEqual(r.slept, [], stderr);
    assert.match(r.out, /::warning::no full CI run started .*the request may have been sent; not sent again/, stderr);
    assert.doesNotMatch(r.output, /run-id=/);
  }
});

test("a dispatch that returns no run id is not sent again and records nothing", () => {
  const r = runDispatch([{ status: "200 OK", headers: {}, body: "{}" }, ok(1)]);
  assert.equal(r.status, 0, r.out);
  assert.equal(r.posts, 1);
  assert.match(r.out, /::warning::.*the dispatch returned no run id/);
  assert.doesNotMatch(r.output, /run-id=/);
});

test("a dispatch that failed skips the record", () => {
  for (const [id, scanId] of [
    ["dispatch-full-run", "scan-upload"],
    ["post-merge-dispatch", "scan-upload-2"],
  ]) {
    const [before, record] = job(id).split("\n      - name: Record the dispatched run\n");
    assert.ok(
      record.startsWith(`        if: >-\n          (steps.dispatch.outputs.run-id != '') && steps.${scanId}.outputs.clean == 'true'\n`),
      id,
    );
    // The credential scan just before it runs on the same condition and scans
    // the file the record uploads.
    const scan = before.split("\n      - name: ").at(-1);
    assert.ok(
      scan.startsWith(
        `Scan the upload for credentials\n        id: ${scanId}\n        if: >-\n          steps.dispatch.outputs.run-id != ''\n        continue-on-error: true\n        uses: ./.base/.github/actions/scan-upload # zizmor: ignore[self-repository]\n        with:\n          path: \${{ runner.temp }}/dispatched.json\n`,
      ),
      id,
    );
    assert.ok(record.includes("\n          path: ${{ runner.temp }}/dispatched.json\n"), id);
  }
});

// Each job's "Check who started the run" step, run under bash from a directory
// whose .base is this checkout, with the step's own env (its github context
// filled from the run below) and an API that serves this run attempt's record,
// or answers 404 when record is null. Expected values come from GitHub's
// workflow run record: actor is who started the run and triggering_actor who
// started this attempt, each with a permanent account id, while a login can be
// released and registered by someone else. The listed human is
// trusted-actors.json's entry 153232337.
const OWNER = { id: 153232337, login: "kyle-sexton" };
const BOT = { id: 41898282, login: "github-actions[bot]" };
async function runWho(
  jobId,
  {
    event = "workflow_dispatch",
    attempt = "2",
    actor = OWNER,
    actorId = String(actor.id),
    rerunner = actor,
    record = { id: 4242, run_attempt: Number(attempt), actor, triggering_actor: rerunner },
    env: extra = {},
  } = {},
) {
  const step = /- name: Check who started the run\n([\s\S]*?)(?=\n {6}- name: )/.exec(job(jobId))[1];
  const context = {
    "github.event_name": event,
    "github.actor_id": actorId,
    "github.triggering_actor": rerunner.login,
    "github.token": "t",
  };
  const stepEnv = Object.fromEntries(
    [...step.matchAll(/^ {10}([A-Z_]+): (.*)$/gm)].map(([, k, v]) => [k, v.replace(/\$\{\{ (\S+) \}\}/g, (_, e) => context[e])]),
  );
  const block = /\n {8}run: \|\n((?: {10}.*\n|\s*\n)+)/.exec(step);
  const body = block ? block[1].split("\n").map((l) => l.slice(10)).join("\n") : /\n {8}run: (.*)/.exec(step)[1];
  const reads = [];
  const server = createServer((req, res) => {
    reads.push(req.url);
    const found = req.url === "/repos/o/r/actions/runs/4242" && record !== null;
    res.writeHead(found ? 200 : 404, { "Content-Type": "application/json" });
    res.end(JSON.stringify(found ? record : { message: "Not Found" }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const dir = tempDir("pr-merge-who-");
  try {
    symlinkSync(fileURLToPath(new URL("../../../", import.meta.url)), join(dir, ".base"));
    writeFileSync(join(dir, "body.sh"), body);
    const output = join(dir, "output");
    const env = {
      ...process.env,
      ...stepEnv,
      GITHUB_OUTPUT: output,
      GITHUB_REPOSITORY: "o/r",
      GITHUB_RUN_ID: "4242",
      GITHUB_RUN_ATTEMPT: attempt,
      GITHUB_EVENT_NAME: event,
      GITHUB_API_URL: `http://127.0.0.1:${server.address().port}`,
      // .base is a link here, a checkout in CI: keep the script's own path.
      NODE_OPTIONS: "--preserve-symlinks-main",
      ...extra,
    };
    let stdout = "";
    const status = await new Promise((resolve) => {
      const child = spawn("bash", ["-e", join(dir, "body.sh")], { cwd: dir, env, stdio: ["ignore", "pipe", "ignore"] });
      child.stdout.on("data", (chunk) => {
        stdout += chunk;
      });
      child.on("close", resolve);
    });
    assert.equal(status, 0);
    return { proceed: /^proceed=(.*)$/m.exec(readFileSync(output, "utf8"))?.[1], reads, stdout };
  } finally {
    server.close();
    rmSync(dir, { recursive: true, force: true });
  }
}

const RUN_READ = ["/repos/o/r/actions/runs/4242"];

for (const jobId of ["merge", "enable-auto-merge"]) {
  test(`${jobId}: a listed human's id proceeds whatever its login now reads`, async () => {
    const renamed = { id: OWNER.id, login: "kyle-renamed" };
    const { proceed, reads } = await runWho(jobId, { actor: renamed });
    assert.equal(proceed, "true");
    assert.deepEqual(reads, RUN_READ);
  });

  test(`${jobId}: a re-runner holding a listed login under another id stops, naming both ids`, async () => {
    const { proceed, stdout } = await runWho(jobId, { rerunner: { id: 999, login: OWNER.login } });
    assert.equal(proceed, "false");
    assert.match(stdout, /::notice::.*actor id 153232337, re-runner id 999\)/);
  });

  test(`${jobId}: an unreadable run record stops`, async () => {
    assert.equal((await runWho(jobId, { record: null })).proceed, "false");
  });

  test(`${jobId}: another attempt's record or a missing id stops`, async () => {
    assert.equal((await runWho(jobId, { record: { id: 4242, run_attempt: 1, actor: OWNER, triggering_actor: OWNER } })).proceed, "false");
    assert.equal((await runWho(jobId, { record: { id: 4242, run_attempt: 2, actor: OWNER, triggering_actor: { login: OWNER.login } } })).proceed, "false");
  });

  test(`${jobId}: an unlisted actor stops before any read, whoever re-ran it`, async () => {
    const { proceed, reads, stdout } = await runWho(jobId, { actor: { id: 999, login: "someone" }, rerunner: OWNER });
    assert.equal(proceed, "false");
    assert.deepEqual(reads, []);
    assert.match(stdout, /::notice::.*\(actor id 999\)/);
    const malformed = await runWho(jobId, { actorId: "abc", rerunner: OWNER });
    assert.equal(malformed.proceed, "false");
    assert.deepEqual(malformed.reads, []);
    // Number() reads this as the listed id; only the id's own shape refuses it.
    const padded = await runWho(jobId, { actorId: `0${OWNER.id}`, rerunner: OWNER });
    assert.equal(padded.proceed, "false");
    assert.deepEqual(padded.reads, []);
  });

  // GitHub names as a scheduled run's actor whoever last changed the
  // schedule, often a bot, and a re-run keeps the schedule event.
  test(`${jobId}: a scheduled run's first attempt proceeds without a read`, async () => {
    const { proceed, reads } = await runWho(jobId, { event: "schedule", attempt: "1", actor: BOT, record: null });
    assert.equal(proceed, "true");
    assert.deepEqual(reads, []);
  });

  test(`${jobId}: a re-run of a scheduled run proceeds only for a listed re-runner`, async () => {
    const listed = await runWho(jobId, { event: "schedule", actor: BOT, rerunner: OWNER });
    assert.equal(listed.proceed, "true");
    assert.deepEqual(listed.reads, RUN_READ);
    assert.equal((await runWho(jobId, { event: "schedule", actor: BOT, rerunner: { id: 999, login: "someone" } })).proceed, "false");
    assert.equal((await runWho(jobId, { event: "schedule", actor: BOT, rerunner: OWNER, record: null })).proceed, "false");
  });

  test(`${jobId}: a repository name GitHub cannot hold stops before any read`, async () => {
    const { proceed, reads } = await runWho(jobId, { env: { GITHUB_REPOSITORY: "o/.." } });
    assert.equal(proceed, "false");
    assert.deepEqual(reads, []);
  });

  test(`${jobId}: an unreadable trusted list stops with its own reason`, async () => {
    const { proceed, reads, stdout } = await runWho(jobId, { env: { TRUSTED_ACTORS_PATH: "missing.json" } });
    assert.equal(proceed, "false");
    assert.deepEqual(reads, []);
    assert.match(stdout, /::warning title=who::ENOENT/);
    assert.doesNotMatch(stdout, /record/);
  });
}

// A job holding `id-token: write` (the token broker's proof) or a lanes App
// token restores no Actions cache by a bare `restore-keys` prefix: any job in
// the default branch's cache scope can write such an entry, and the pinned
// restore extracts its archive with no entry filter, so a crafted entry could
// replace a checked-out script before it runs (#9455). In pr-merge.yml no such
// job restores a cache at all. Steps of a local composite action count as the
// job's own.
const root = new URL("../../../", import.meta.url);
const workflowsDir = new URL(".github/workflows/", root);
const stepsIn = (text) => text.split(/\n(?=\s*- (?:name|uses|id|if|run|env|with|shell|continue-on-error|timeout-minutes):)/).slice(1);
const restoresOf = (stepTexts, seen = new Set()) =>
  stepTexts.flatMap((s) => {
    const uses = /^\s*(?:- )?uses: *['"]?([^\s'"#]+)/m.exec(s)?.[1] ?? "";
    if (/^actions\/cache(?:\/restore)?@/.test(uses)) return [{ uses, prefix: /\n\s*restore-keys:/.test(s) }];
    // setup-node restores a package cache unless told not to
    // (package-manager-cache defaults to true); any setup action with a
    // `cache:` input restores one.
    const setupNode = /^actions\/setup-node@/.test(uses) && !/\n\s*package-manager-cache: false\b/.test(s);
    if (setupNode || (/^actions\/setup-[a-z]+@/.test(uses) && /\n\s*cache: *\S/.test(s))) return [{ uses, prefix: false }];
    const local = /^\.\/(?:\.base\/)?(\.github\/actions\/[^@]+)$/.exec(uses)?.[1];
    if (!local || seen.has(local)) return [];
    seen.add(local);
    const action = ["action.yml", "action.yaml"].map((f) => new URL(`${local.replace(/\/$/, "")}/${f}`, root)).find((u) => existsSync(u));
    return action ? restoresOf(stepsIn(readFileSync(action, "utf8")), seen) : [];
  });
// A grant of id-token: write, at any indentation and quoted or not, or write-all.
const grantsIdToken = (text) =>
  /^[ \t]*id-token:[ \t]*['"]?write['"]?[ \t]*(?:#.*)?$/m.test(text) || /^[ \t]*permissions:[ \t]*['"]?write-all\b/m.test(text);
function tokenJobRestores(text) {
  const at = text.search(/^jobs:[ \t]*$/m);
  const workflowGrant = grantsIdToken(text.slice(0, at));
  const body = text.slice(at).replace(/^jobs:.*\n/, "");
  // Job ids sit at the first indentation under jobs:, whatever it is.
  const indent = /^([ \t]+)[A-Za-z0-9_-]+:/m.exec(body)?.[1] ?? "  ";
  return body
    .split(new RegExp(`\\n(?=${indent}[A-Za-z0-9_-]+:)`))
    .map((block) => ({ id: new RegExp(`^${indent}([A-Za-z0-9_-]+):`, "m").exec(block)?.[1], block }))
    .filter(({ id, block }) => id && (workflowGrant || grantsIdToken(block) || /request-lane-token|create-github-app-token/.test(block)))
    .flatMap(({ id, block }) => restoresOf(stepsIn(block)).map((r) => ({ job: id, ...r })));
}

test("no job holding id-token or a lanes App token restores a cache by a bare prefix", () => {
  const found = readdirSync(workflowsDir)
    .filter((f) => /\.ya?ml$/.test(f))
    .flatMap((f) => tokenJobRestores(readFileSync(new URL(f, workflowsDir), "utf8")).map((r) => ({ file: f, ...r })))
    .filter((r) => r.prefix);
  assert.deepEqual(found, []);
});

test("no token-holding job in pr-merge.yml restores a cache", () => {
  assert.deepEqual(tokenJobRestores(merge), []);
  // The check sees a restore a token-holding job adds, directly or through a
  // local composite action, and ignores one in a job holding neither token.
  const withStep = (job, step) => merge.replace(new RegExp(`(\\n  ${job}:\\n[\\s\\S]*?\\n    steps:\\n)`), `$1${step}`);
  const exact = "      - name: Restore\n        uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0\n        with:\n          key: k\n";
  const composite = "      - name: Count\n        uses: ./.base/.github/actions/check-wip-cap # zizmor: ignore[self-repository]\n";
  const setupNode = "      - name: Node\n        uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0\n        with:\n          node-version: 24\n";
  const setupPython = "      - name: Python\n        uses: actions/setup-python@v6\n        with:\n          cache: pip\n";
  for (const job of ["merge", "enable-auto-merge"]) {
    for (const added of [exact, setupNode, setupPython]) {
      assert.deepEqual(tokenJobRestores(withStep(job, added)).map((r) => [r.job, r.prefix]), [[job, false]], job);
    }
    assert.deepEqual(tokenJobRestores(withStep(job, composite)).map((r) => [r.job, r.prefix]), [[job, true]], job);
  }
  assert.deepEqual(tokenJobRestores(withStep("gate-check", exact)), []);
});

test("a token grant is found at any indentation", () => {
  const restore = (pad) => `${pad}- name: Restore\n${pad}  uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0\n${pad}  with:\n${pad}    key: k\n${pad}    restore-keys: k-\n`;
  // Jobs at four spaces, their permissions at eight and ten.
  const wide = `on: push\njobs:\n    holder:\n        permissions:\n          id-token: write\n        steps:\n${restore("          ")}    other:\n        permissions:\n          contents: read\n        steps:\n${restore("          ")}`;
  assert.deepEqual(tokenJobRestores(wide).map((r) => [r.job, r.prefix]), [["holder", true]]);
  // Jobs at two spaces, the grant at eight, quoted.
  const deep = `on: push\njobs:\n  holder:\n    permissions:\n        id-token: 'write'\n    steps:\n${restore("      ")}`;
  assert.deepEqual(tokenJobRestores(deep).map((r) => r.job), ["holder"]);
  // A workflow-level grant, and write-all, cover every job.
  for (const grant of ["permissions:\n    id-token: write\n", "permissions: write-all\n"]) {
    const top = `on: push\n${grant}jobs:\n  plain:\n    steps:\n${restore("      ")}`;
    assert.deepEqual(tokenJobRestores(top).map((r) => r.job), ["plain"], grant);
  }
});

// The verifier answers (babysit_verify_evidence.py --answers-in/--answers-out)
// cross runs only as the artifact of a scheduled or hand-started run of
// main's pr-merge.yml, read through rotation.mjs newestTrustedRun and
// onMain, never actions/cache, which any job in main's cache scope can write.
test("enable-auto-merge reads the verifier answers only from a trusted run and uploads them under their own name, always", () => {
  const arm = job("enable-auto-merge");
  const step = (name) => new RegExp(`- name: ${name}\\n([\\s\\S]*?)(?=\\n {6}- name: |\\n*$)`).exec(arm)?.[1];
  const read = step("Read the verifier answers the last run kept");
  assert.ok(read, "an answers read");
  assert.match(read, /^ {8}if: steps\.lane-token\.outputs\.token != '' && \(github\.event_name == 'schedule' \|\| github\.event_name == 'workflow_dispatch'\)\n/);
  assert.match(read, /\n {8}continue-on-error: true\n/);
  assert.match(read, /\n {10}ACTIONS_TOKEN: \$\{\{ github\.token \}\}\n {10}VERIFY_ANSWERS_PATH: \$\{\{ runner\.temp \}\}\/verify-answers-in\.json\n/);
  const script = readFileSync(new URL("./verify-answers.mjs", import.meta.url), "utf8");
  assert.match(script, /newestTrustedRun\(\{ repo, runId, actions, name: ANSWERS_ARTIFACT, accept \}\)/);
  assert.match(script, /const accept = \(run\) => onMain\(/);
  assert.match(script, /export const ANSWERS_ARTIFACT = "pr-merge-verify-answers";/);
  const armStep = step("Arm and disarm auto-merge");
  assert.match(armStep, /\n {10}VERIFY_ANSWERS_IN: \$\{\{ runner\.temp \}\}\/verify-answers-in\.json\n {10}VERIFY_ANSWERS_OUT: \$\{\{ runner\.temp \}\}\/verify-answers\/verify-answers\.json\n/);
  assert.match(armStep, /\n {10}VERIFY_CACHE=\$\(yq '\.merge\."verify-cache" \/\/ "shadow"' "\$config"\)\n/);
  assert.match(armStep, /\n {10}export [^\n]*\bVERIFY_CACHE\b/);
  const upload = step("Upload the verifier answers for the next run");
  assert.ok(upload, "an answers upload");
  const predicate = "always() && steps.arm.outcome != 'skipped' && (github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')";
  assert.ok(upload.startsWith(`        if: >-\n          (${predicate}) && steps.scan-upload.outputs.clean == 'true'\n`), upload);
  // The credential scan just before it runs on the same condition over the
  // same two files.
  const scan = arm.split("\n      - name: Upload the verifier answers for the next run\n")[0].split("\n      - name: ").at(-1);
  assert.ok(scan.startsWith(`Scan the upload for credentials\n        id: scan-upload\n        if: >-\n          ${predicate}\n`), scan);
  assert.ok(scan.includes("\n        uses: ./.base/.github/actions/scan-upload # zizmor: ignore[self-repository]\n"), scan);
  // A best-effort upload: neither it nor its scan can fail the job.
  for (const block of [scan, upload]) assert.ok(block.includes("\n        continue-on-error: true\n"), block);
  assert.ok(
    scan.includes("\n          path: |\n            ${{ runner.temp }}/verify-answers/verify-answers.json\n            ${{ runner.temp }}/verify-answers/eam-skip.json\n"),
    scan,
  );
  assert.match(upload, /\n {8}uses: actions\/upload-artifact@[0-9a-f]{40} /);
  // Bounded, so the job's timeout stays above the sum of its steps'.
  assert.match(upload, /\n {8}timeout-minutes: [0-9]+\n/);
  assert.match(upload, /\n {10}name: pr-merge-verify-answers\n {10}path: \|\n {12}\$\{\{ runner\.temp \}\}\/verify-answers\/verify-answers\.json\n {12}\$\{\{ runner\.temp \}\}\/verify-answers\/eam-skip\.json\n {10}retention-days: 1\n {10}if-no-files-found: ignore\n/);
  const names = [...arm.matchAll(/\n {6}- name: (.*)/g)].map((m) => m[1]);
  assert.ok(names.indexOf("Read the verifier answers the last run kept") < names.indexOf("Arm and disarm auto-merge"));
  assert.ok(names.indexOf("Arm and disarm auto-merge") < names.indexOf("Upload the verifier answers for the next run"));
  // Its own name in the workflow, never downloaded by name, never cached.
  assert.equal([...merge.matchAll(/\n {10}name: pr-merge-verify-answers\n/g)].length, 1);
  assert.doesNotMatch(merge, /uses: actions\/cache[^\n]*\n(?:[^\n]*\n){0,6}[^\n]*verify-answers/);
  assert.doesNotMatch(merge, /uses: actions\/download-artifact[^\n]*\n(?:[^\n]*\n){0,3}[^\n]*verify-answers/);
});

// merge.full-run-cap-bypass (owner standing direction, relayed 2026-10-29:
// runner minutes on this repository are not a cost, and the cap now limits
// lane throughput). Inside the cap, post-merge-dispatch starts one run of
// main's tip when the post-merge report lists an unverified lane merge with no
// dispatch under way and no listed run created at or after the merge on a
// commit that contains it. The checkout is a real history: BEFORE, then the
// merge MERGED, then TIP; LATER is a commit the checkout lacks.
const LATER = "f".repeat(40);
function runBypass({ merges, runs, bypass = true, mergedAt = "2026-10-29T01:00:00Z" }) {
  const dir = tempDir("pr-merge-bypass-");
  const git = (...args) =>
    execFileSync("git", ["-C", join(dir, ".base"), ...args], {
      encoding: "utf8",
      env: { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" },
    }).trim();
  mkdirSync(join(dir, ".base/docs/conventions"), { recursive: true });
  git("init", "-q", "-b", "main");
  const commit = (message) => {
    git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", message);
    return git("rev-parse", "HEAD");
  };
  const shas = { BEFORE: commit("before"), MERGED: commit("the lane merge"), TIP: commit("tip"), LATER };
  const config = bypass === undefined ? "merge: {}\n" : `merge:\n  full-run-cap-bypass: ${bypass}\n`;
  writeFileSync(join(dir, ".base/docs/conventions/pr-pipeline.yaml"), config);
  const autoMerges = merges.map((m, i) => ({
    number: 100 + i,
    mergeCommit: shas.MERGED,
    mergedAt,
    verified: m.verified ?? false,
    pending: m.pending ?? ["dispatch-run-pending", "canary-run-pending"],
  }));
  writeFileSync(join(dir, "post-merge.json"), JSON.stringify({ ok: true, autoMerges }));
  writeFileSync(join(dir, "cover-runs.json"), JSON.stringify(runs.map((r) => ({ sha: shas[r.at], created: r.created }))));
  writeFileSync(join(dir, "output"), "");
  const block = job("post-merge-dispatch").split("\n      - name: Find lane merges no full run covers\n")[1].split("\n      - name: ")[0];
  writeFileSync(join(dir, "body.sh"), runBody(block));
  const result = spawnSync("bash", ["-e", join(dir, "body.sh")], {
    cwd: dir,
    env: { ...process.env, GITHUB_OUTPUT: join(dir, "output"), RUNNER_TEMP: dir, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" },
    encoding: "utf8",
  });
  const output = readFileSync(join(dir, "output"), "utf8");
  rmSync(dir, { recursive: true, force: true });
  return { status: result.status, out: result.stdout + result.stderr, bypass: /^bypass=true$/m.test(output) };
}
// The run that started the window: before the merge, at the commit before it.
const STARTED = { at: "BEFORE", created: "2026-10-29T00:50:00Z" };

test("inside the cap, an unverified lane merge no started run covers starts one run", () => {
  const r = runBypass({ merges: [{}, {}], runs: [STARTED] });
  assert.equal(r.status, 0, r.out);
  assert.equal(r.bypass, true);
  assert.match(r.out, /::notice::no full run covers lane merge\(s\) #100 #101; one run of main's tip starts inside the cap/);
});

test("a run created after the merge on a commit that contains it covers the batch: the cap holds", () => {
  for (const at of ["MERGED", "TIP", "LATER"]) {
    const r = runBypass({ merges: [{}], runs: [{ at, created: "2026-10-29T01:05:00Z" }, STARTED] });
    assert.equal(r.status, 0, r.out);
    assert.equal(r.bypass, false, `a run at ${at}`);
  }
});

test("a run after the merge on a commit without it, or one before the merge at the tip, covers nothing", () => {
  assert.equal(runBypass({ merges: [{}], runs: [{ at: "BEFORE", created: "2026-10-29T01:05:00Z" }, STARTED] }).bypass, true);
  assert.equal(runBypass({ merges: [{}], runs: [{ at: "TIP", created: "2026-10-29T00:59:59Z" }, STARTED] }).bypass, true);
});

test("the second tick in the window finds the run the first tick started and starts none", () => {
  // The first tick's dispatch, at main's tip, is in the next listing.
  const r = runBypass({ merges: [{}], runs: [{ at: "TIP", created: "2026-10-29T01:11:30Z" }, STARTED] });
  assert.equal(r.bypass, false, r.out);
});

test("no lane merge, a verified one, or one with a run under way keeps the cap", () => {
  assert.equal(runBypass({ merges: [], runs: [STARTED] }).bypass, false);
  assert.equal(runBypass({ merges: [{ verified: true, pending: [] }], runs: [STARTED] }).bypass, false);
  for (const pending of [["dispatch-run-pending", "dispatch-run-in-progress:77"], ["dispatch-run-pending", "attribution-pending:77"], ["canary-run-pending"]]) {
    assert.equal(runBypass({ merges: [{ pending }], runs: [STARTED] }).bypass, false, pending.join(","));
  }
});

test("merge.full-run-cap-bypass false keeps the cap; absent is true", () => {
  const off = runBypass({ merges: [{}], runs: [STARTED], bypass: false });
  assert.equal(off.bypass, false);
  assert.match(off.out, /::notice::merge\.full-run-cap-bypass is false: the cap holds/);
  assert.equal(runBypass({ merges: [{}], runs: [STARTED], bypass: undefined }).bypass, true);
});

test("a merge older than every listed run is skipped, not read as uncovered", () => {
  const r = runBypass({ merges: [{}], runs: [STARTED], mergedAt: "2026-10-29T00:40:00Z" });
  assert.equal(r.bypass, false, r.out);
});

test("the bypass step runs only inside the cap after a check that judged, and the yaml default is on", () => {
  const block = job("post-merge-dispatch").split("\n      - name: Find lane merges no full run covers\n")[1].split("\n      - name: ")[0];
  assert.match(block, /\n {8}if: >-\n {10}steps\.cover\.outputs\.capped == 'true'\n {10}&& contains\(fromJSON\('\["0","5"\]'\), steps\.post-merge\.outputs\.code\)\n/);
  const config = readFileSync(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url), "utf8");
  assert.match(config, /\n {2}full-run-cap-bypass: true\n/);
  assert.doesNotMatch(job("dispatch-full-run"), /steps\.bypass/);
});

// Every enable-auto-merge step that counts its GitHub calls (API_BUDGET_TOKEN)
// names itself (API_BUDGET_SCRIPT, rate-guard.mjs scriptCalls), each a name of
// its own, so the job-end api-calls total splits by step.
test("enable-auto-merge: every step that counts its calls names itself once", () => {
  const steps = job("enable-auto-merge").split(/\n {6}- name: /).filter((step) => /^ {10}API_BUDGET_TOKEN: /m.test(step));
  const names = steps.map((step) => /^ {10}API_BUDGET_SCRIPT: ([a-z][a-z0-9-]{0,39})$/m.exec(step)?.[1]);
  assert.ok(steps.length > 0);
  assert.ok(names.every(Boolean), names.join(" "));
  assert.equal(new Set(names).size, names.length);
});

// refire-refused.mjs reads merge.refire-skip-branches from resolve-config's
// output; with any other path it reads nothing and stops the step.
test("the re-fire step reads the skip list from the file the merge job's config step writes", () => {
  const merge = job("merge");
  const config = /- name: Resolve the config\n {8}id: config\n[\s\S]*?\n {10}output-path: (.*)\n/.exec(merge)?.[1];
  const refire = /- name: Re-fire lane runs refused as workflow-modified\n([\s\S]*?)(?=\n {6}- name: )/.exec(merge)?.[1] ?? "";
  assert.equal(config, "${{ runner.temp }}/resolved-config.json");
  assert.match(refire, /\n {10}RESOLVED_CONFIG_PATH: \$\{\{ runner\.temp \}\}\/resolved-config\.json\n/);
});
