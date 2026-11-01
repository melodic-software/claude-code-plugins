// pr-merge.yml's merge job: the post-merge check and its re-dispatch do not
// wait on the gate loop (#8299), the listing retries a failed `gh pr list`, an
// unknown listing holds the job green and every later acting step, the
// post-merge check included, waits on that hold, the run logs its API cost
// through the shared action, and the run cache carries the verdict reads that
// never change to the next run.
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";

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
      "Read the post-merge report the last run kept",
      "Check earlier lane merges",
      "Scan the upload for credentials",
      "Keep the post-merge report for enable-auto-merge",
      "Read main's full-run cover",
      "Find lane merges no full run covers",
      "Start the full CI run on main",
      "Scan the upload for credentials",
      "Record the dispatched run",
      "Re-run a red lane-dispatched full run",
      "Scan the upload for credentials",
      "Record the re-run",
      "Send a red full run to the demotion alert",
      "Scan the upload for credentials",
      "Record the alert sent",
      "Log the API budget at the end",
    ],
  );
  // Each upload waits on the credential scan just before it. The report is
  // best-effort, so its scan cannot fail the job; a run record the
  // post-merge check needs fails the job when its scan does (a missing
  // scanner included), as a failed upload of it does.
  assert.match(
    assertScanned("Keep the post-merge report for enable-auto-merge", "steps.post-merge.conclusion == 'success'", list),
    /\n {8}continue-on-error: true\n/,
  );
  for (const [name, predicate] of [
    ["Record the dispatched run", "steps.dispatch.outputs.run-id != ''"],
    ["Record the re-run", "!cancelled() && steps.rerun.outputs.recorded == 'true'"],
    ["Record the alert sent", "!cancelled() && steps.alert.outputs.run-id != ''"],
  ]) {
    assert.doesNotMatch(assertScanned(name, predicate, list), /continue-on-error/, name);
    assert.doesNotMatch(step(name, list), /continue-on-error/, name);
  }
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
  assert.match(dispatch, /steps\.post-merge\.outputs\.needs-dispatch == 'true'/);
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
// fails its first `failures` calls and then answers `prs` (by default one pull
// request of the lanes App's) and whose open-count read answers `total` (by
// default as many as `prs`; null fails it), with `.base` pointing at this checkout,
// or, given `edit`, at a copy whose pr-pipeline.yaml is `edit(text)` and whose
// trusted-actors.json is `actors`, when given, else this checkout's.
// `env` overrides the step's environment: merge.lane-prs is `gate` unless it
// says otherwise, the mode that lists the lanes App's own pull requests.
// `attempts` scripts each `gh pr list` in turn: `502` fails that one.
const listed = (number, login, isDraft = false) => ({ id: `PR_${number}`, number, headRefOid: "abc", isDraft, updatedAt: "2026-10-18T00:00:00Z", labels: [], body: "", author: { login } });
const LANES_PR = [listed(7, "app/melodic-automation-lanes")];
const runListing = (failures, edit, actors, env = {}, failure = "HTTP 502: Bad Gateway", prs = LANES_PR, total = prs.length, attempts = []) => {
  const dir = tempDir("pr-merge-listing-");
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", [bin]);
    writeFileSync(join(dir, "prs.json"), JSON.stringify(prs));
    writeFileSync(
      join(bin, "gh"),
      `#!/usr/bin/env bash\n` +
        `if [ "$1" = api ]; then\n` +
        `  [[ "$*" == *.totalCount* && "$*" == *'pullRequests(states: OPEN, baseRefName: "main")'* ]] || { echo "unexpected query: $*" >&2; exit 1; }\n` +
        `  ${total === null ? 'echo "HTTP 502: Bad Gateway" >&2; exit 1' : `echo ${total}; exit 0`}\n` +
        `fi\n` +
        `echo "$*" >>"${dir}/args"\n` +
        `n=$(($(cat "${dir}/calls" 2>/dev/null || echo 0) + 1))\necho "$n" >"${dir}/calls"\n` +
        `attempts=(${attempts.join(" ")})\n` +
        `if [ "$n" -le ${failures} ] || [ "\${attempts[$((n - 1))]:-}" = 502 ]; then echo "${failure}" >&2; exit 1; fi\n` +
        `cat "${dir}/prs.json"\n`,
    );
    writeFileSync(join(bin, "sleep"), `#!/usr/bin/env bash\necho "$1" >>"${dir}/sleeps"\n`);
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
        EVENT_PR: "",
        ...env,
      },
    });
    const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
    const numbers = (name) => (read(name).trim() ? JSON.parse(read(name)).map((item) => item.number) : []);
    return {
      status: result.status,
      stdout: result.stdout,
      stderr: result.stderr,
      calls: Number(read("calls") || 0),
      sleeps: read("sleeps").split("\n").filter(Boolean).map(Number),
      args: read("args"),
      candidates: read("candidates.json"),
      listed: numbers("candidates.json"),
      draftsListed: numbers("drafts.json"),
      drafts: read("drafts.json"),
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
  // Three tries of the one list.
  assert.equal(run.calls, 3);
  assert.match(run.output, /^count=1$/m);
  assert.match(run.output, /^listed=true$/m);
  assert.doesNotMatch(run.output, /held/);
  // Two capped waits with full jitter.
  assert.equal(run.sleeps.length, 2);
  assert.ok(run.sleeps[0] <= 15 && run.sleeps[1] <= 30, String(run.sleeps));
});

// Unknown holds the job: green, a notice, and no count or candidate for any
// later step (each hold below; the steps' gates are the next test's).
const assertHeld = (run) => {
  assert.equal(run.status, 0, run.stderr);
  assert.match(run.stdout, /^::notice title=Merge lane hold::/m);
  assert.doesNotMatch(run.stdout, /^::error title=GitHub rate limit::gh pr list/m);
  assert.match(run.output, /^held=true$/m);
  assert.doesNotMatch(run.output, /^(count|listed)=/m);
  assert.equal(run.prefiltered, false);
  assert.equal(run.candidates, "");
};

test("a listing with pull requests missing from a 200 holds the job, and the next complete read clears it", () => {
  const degraded = runListing(0, undefined, undefined, {}, undefined, LANES_PR, 2);
  assertHeld(degraded);
  // A count that moved between the two reads gets the retries before it holds.
  assert.equal(degraded.calls, 3);
  assert.match(degraded.stderr, /gh pr list holds 1 of 2 open pull requests/);
  assert.match(degraded.output, /^held-reason=failed 3 times \(count mismatch\)$/m);
  const next = runListing(0, undefined, undefined, {}, undefined, LANES_PR, 1);
  assert.equal(next.status, 0, next.stderr);
  assert.doesNotMatch(next.stdout, /::notice title=Merge lane hold::/);
  assert.doesNotMatch(next.output, /held/);
  assert.match(next.output, /^count=1$/m);
  assert.deepEqual(next.listed, [7]);
});

test("the hold names only the last try's fault", () => {
  const cleared = runListing(0, undefined, undefined, {}, undefined, LANES_PR, 2, ["ok", "502", "502"]);
  assertHeld(cleared);
  assert.equal(cleared.calls, 3);
  assert.match(cleared.output, /^held-reason=failed 3 times$/m);
  const last = runListing(0, undefined, undefined, {}, undefined, LANES_PR, 2, ["502", "502", "ok"]);
  assertHeld(last);
  assert.match(last.output, /^held-reason=failed 3 times \(count mismatch\)$/m);
});

test("a repeated pull request does not stand in for a missing one", () => {
  assertHeld(runListing(0, undefined, undefined, {}, undefined, [listed(7, "app/melodic-automation-lanes"), listed(7, "app/melodic-automation-lanes")], 2));
});

test("a listing whose open count cannot be read holds the job", () => {
  assertHeld(runListing(0, undefined, undefined, {}, undefined, LANES_PR, null));
});

// A step's `if:` as GitHub evaluates it on the schedule, with `steps` and
// `needs` as given. No `if:` runs it. Takes a step block, since the credential
// scans share one name.
const blockRunsOn = (block, context, needs = {}) => {
  const found = /\n {8}if: (>-\n(?: {10}.*\n)+|.*\n)/.exec(`${block}\n`);
  if (!found) return true;
  const script = `return (${found[1].replace(">-\n", "").replace(/\.([a-z]+(?:-[a-z0-9]+)+)/g, '["$1"]')});`;
  return new Function("steps", "needs", "github", "always", script)(context, needs, { event_name: "schedule" }, () => true);
};
const runsOn = (name, context, needs = {}) => blockRunsOn(step(name), context, needs);
const SCAN = "Scan the upload for credentials";
const isScanId = (id) => /^scan-upload(-\d+)?$/.test(id);
// The merge job's steps at the listing's end: any step not named here has not
// run, as on the schedule with a live lane. Every credential scan reads as
// clean, so an upload runs or not on its own condition.
const atListing = (candidates) =>
  new Proxy(
    { "lane-token": { outputs: { token: "t" } }, mode: { outputs: { live: "true", "report-only": "false" } }, kill: { outputs: { proceed: "true" } }, candidates },
    { get: (known, id) => known[id] ?? (isScanId(id) ? { outcome: "success", outputs: { clean: "true" } } : { outcome: "skipped", outputs: {} }) },
  );
// An upload gated by the credential scan just before it: the scan runs on the
// upload's own condition and scans the same path, and the upload's folded
// `if:` is that condition and the scan's clean output. Returns the scan.
const pathOf = (block) => /\n {10}path: (\|\n(?: {12}.*\n)+|.*\n)/.exec(`${block}\n`)?.[1];
const assertScanned = (name, predicate, list = steps) => {
  const at = list.findIndex((s) => s.name === name);
  assert.ok(at > 0, `step ${name}`);
  const scan = list[at - 1];
  assert.equal(scan.name, SCAN, `the step before ${name}`);
  const id = /\n {8}id: (scan-upload(?:-\d+)?)\n/.exec(scan.block)?.[1];
  assert.ok(id, `the scan before ${name} has an id`);
  assert.ok(scan.block.includes(`\n        if: >-\n          ${predicate}\n`), `the scan before ${name} runs on its condition`);
  assert.ok(scan.block.includes("\n        uses: ./.base/.github/actions/scan-upload # zizmor: ignore[self-repository]\n"), `the scan before ${name}`);
  const upload = list[at].block;
  assert.ok(upload.includes(`\n        if: >-\n          (${predicate}) && steps.${id}.outputs.clean == 'true'\n`), `${name} waits on ${id}`);
  assert.ok(pathOf(upload), `${name} has a path`);
  assert.equal(pathOf(scan.block), pathOf(upload), `the scan before ${name} scans its path`);
  return scan.block;
};
const dispatched = (code) => ({ "post-merge-dispatch": { result: "success", outputs: { "post-merge-code": code, "rate-limited": "" } } });

// Everything after the listing that reads, writes or files waits on `listed`;
// a hold runs only the cleanup and the summary, and files no failed lane merge.
test("no step after the listing acts on a held listing", () => {
  const after = steps.slice(steps.findIndex((s) => s.name === "List the candidate PRs") + 1);
  assert.ok(after.length > 20);
  const running = (candidates, code) => after.filter(({ block }) => blockRunsOn(block, atListing(candidates), dispatched(code))).map((s) => s.name);
  const held = { outcome: "success", outputs: { held: "true" } };
  const always = ["Count the sweep's refusals", SCAN, "Upload the sweep's verdicts", "Log the API budget at job end", "Write the sweep cost", "Revoke the lane token"];
  assert.deepEqual(running(held, "0"), always);
  assert.deepEqual(running(held, "1"), always);
  // The same steps that a hold stops do run once the listing is whole.
  const whole = running({ outcome: "success", outputs: { listed: "true" } }, "0");
  for (const name of ["Run the merge gate on each candidate", "Re-fire lane runs refused as workflow-modified", "Clear escalations whose reason no longer holds"]) {
    assert.ok(whole.includes(name), name);
    assert.ok(!running(held, "1").includes(name), name);
  }
});

// GitHub Support's audit item 7: one listing of every open pull request into
// main, filtered by author, in place of one `gh pr list --author` (a search
// call) per author.
const AUTHORED = [
  listed(1, "app/melodic-automation-lanes"),
  listed(2, "a-person"),
  listed(3, "app/some-release"),
  listed(4, "app/dependabot"),
  listed(5, "a-stranger"),
  listed(6, "app/melodic-automation-lanes", true),
];

// Owner decision 2026-10-22: every trusted actor's PR is a candidate.
test("the listing keeps each trusted actor's pull requests, a person by login and an App as app/<slug>, from one list", () => {
  const actors = [
    { id: 1, login: "a-person", kind: "human" },
    { id: 2, login: "some-release[bot]", kind: "bot" },
    { id: 3, login: "melodic-automation-lanes[bot]", kind: "bot" },
    { id: 4, login: "dependabot[bot]", kind: "bot" },
    { id: 5, login: "bad login; rm", kind: "human" },
  ];
  const run = runListing(0, (config) => config, actors, {}, undefined, AUTHORED);
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.calls, 1);
  assert.doesNotMatch(run.args, /--author/);
  assert.deepEqual(run.listed, [1, 2, 3]);
  assert.deepEqual(run.draftsListed, [6]);
  assert.doesNotMatch(run.args, /^api /m);
});

test("without an adoption section no trusted actor is listed", () => {
  const run = runListing(0, (config) => config.replace(/^adoption:\n( {2}.*\n)*/m, ""), undefined, {}, undefined, AUTHORED);
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(run.listed, [1]);
  // Nor with a section that sets no idle-hours, which the gate adopts nothing under.
  const noIdle = runListing(0, (config) => config.replace(/^ {2}idle-hours: 2\n/m, ""), undefined, {}, undefined, AUTHORED);
  assert.equal(noIdle.status, 0, noIdle.stderr);
  assert.deepEqual(noIdle.listed, [1]);
});

// merge.lane-prs: native leaves the lanes App's pull requests to GitHub's
// auto-merge: the listing drops them, so the gate never reads them.
test("under lane-prs native the listing skips the lanes App and keeps every other author", () => {
  const actors = [
    { id: 1, login: "a-person", kind: "human" },
    { id: 3, login: "melodic-automation-lanes[bot]", kind: "bot" },
  ];
  const native = runListing(0, (config) => config, actors, { LANE_PRS: "native", DEPENDABOT: "enforce" }, undefined, AUTHORED);
  assert.equal(native.status, 0, native.stderr);
  assert.deepEqual(native.listed, [2, 4]);
  assert.match(native.output, /^count=2$/m);
  const gate = runListing(0, (config) => config, actors, { LANE_PRS: "gate", DEPENDABOT: "enforce" }, undefined, AUTHORED);
  assert.equal(gate.status, 0, gate.stderr);
  assert.deepEqual(gate.listed, [1, 2, 4]);
});

test("under lane-prs native with no other author the listing calls nothing and lists no candidate", () => {
  const run = runListing(0, (config) => config.replace(/^adoption:\n( {2}.*\n)*/m, ""), undefined, { LANE_PRS: "native" });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.calls, 0);
  assert.equal(run.candidates.trim(), "[]");
  assert.equal(run.drafts.trim(), "[]");
  assert.match(run.output, /^count=0$/m);
});

// GitHub Support's audit item 5: a pull_request_target run gates only the
// pull request its event names, from the listing (never the payload); the
// scheduled run keeps the whole sweep.
test("an event run lists only its own pull request", () => {
  const actors = [{ id: 1, login: "a-person", kind: "human" }];
  const run = runListing(0, (config) => config, actors, { EVENT_PR: "2" }, undefined, AUTHORED);
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(run.listed, [2]);
  assert.deepEqual(run.draftsListed, []);
  assert.match(run.output, /^count=1$/m);
  // A pull request the listing does not hold lists nothing.
  const absent = runListing(0, (config) => config, actors, { EVENT_PR: "5" }, undefined, AUTHORED);
  assert.deepEqual(absent.listed, []);
  assert.match(step("List the candidate PRs"), /\n {10}EVENT_PR: \$\{\{ github\.event\.pull_request\.number \}\}\n/);
});

test("a listing that reaches the limit ends red at once: a lasting fault, not a hold", () => {
  const many = Array.from({ length: 1000 }, (_, i) => listed(i + 1, "app/melodic-automation-lanes"));
  for (const total of [1000, 1500]) {
    const run = runListing(0, undefined, undefined, {}, undefined, many, total);
    assert.equal(run.status, 1, run.stderr);
    assert.equal(run.calls, 1);
    assert.deepEqual(run.sleeps, []);
    assert.match(run.stdout, /^::error::gh pr list returned 1000 pull requests, so the listing may be cut short/m);
    assert.doesNotMatch(run.stdout, /Merge lane hold/);
    assert.doesNotMatch(run.output, /held|listed/);
  }
});

test("a held listing files no failed lane merge; a run that listed goes by its own check", () => {
  const record = (held, own, dispatch) =>
    runsOn(
      "Record a failed lane merge",
      { "lane-token": { outputs: { token: "t" } }, mode: { outputs: { live: "true" } }, candidates: { outputs: { held } }, "post-merge": { outputs: { code: own } } },
      { "post-merge-dispatch": { outputs: { "post-merge-code": dispatch } } },
    );
  for (const dispatch of ["1", "0", "3", ""]) assert.equal(record("true", undefined, dispatch), false, dispatch);
  assert.equal(record(undefined, "1", "0"), true);
  assert.equal(record(undefined, "0", "1"), false);
});

test("a held listing writes a sweep summary with no read, and a monitor can tell it held", () => {
  const skipped = { gate: { outcome: "skipped" }, candidates: { outputs: {} }, "scan-upload-5": { outputs: { clean: "true" } } };
  for (const name of ["Count the sweep's refusals", "Upload the sweep's verdicts", "Write the sweep cost"]) {
    assert.equal(runsOn(name, { ...skipped, candidates: { outputs: { held: "true" } } }), true, name);
    assert.equal(runsOn(name, skipped), false, name);
  }
  // The verdicts' credential scan runs on the same hold, and a scan that is
  // not clean withholds the upload.
  const scan = assertScanned("Upload the sweep's verdicts", "always() && (steps.gate.outcome != 'skipped' || steps.candidates.outputs.held == 'true')");
  assert.equal(blockRunsOn(scan, { ...skipped, candidates: { outputs: { held: "true" } } }), true);
  assert.equal(blockRunsOn(scan, skipped), false);
  assert.equal(runsOn("Upload the sweep's verdicts", { ...skipped, candidates: { outputs: { held: "true" } }, "scan-upload-5": { outputs: {} } }), false);
  const dir = tempDir("pr-merge-held-summary-");
  try {
    const bin = join(dir, "bin");
    mkdirSync(bin);
    writeFileSync(join(bin, "gh"), `#!/usr/bin/env bash\necho "$*" >>"${dir}/gh-calls"\n`);
    chmodSync(join(bin, "gh"), 0o755);
    symlinkSync(root, join(dir, ".base"));
    const to = join(dir, "sweep.json");
    const result = spawnSync("bash", ["-c", runScript("Count the sweep's refusals")], {
      cwd: dir,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        // .base is a symlink here, and the script runs only as the main module.
        NODE_OPTIONS: "--preserve-symlinks-main",
        RUNNER_TEMP: dir,
        REPO: "o/r",
        GITHUB_RUN_ID: "41",
        EVENT: "schedule",
        LIVE: "true",
        GATE_OUTCOME: "skipped",
        LIMITED: "",
        LISTING_HELD: "true",
        LISTING_HELD_REASON: "failed 3 times",
        SUMMARY_PATH: join(dir, "pr-merge-summary.json"),
        HELD_PATH: join(dir, "held.json"),
        CANDIDATES_PATH: join(dir, "candidates.json"),
        CURSOR_PATH: join(dir, "cursor.json"),
        SWEEP_SUMMARY_TO: to,
      },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(existsSync(join(dir, "gh-calls")), false);
    const summary = JSON.parse(readFileSync(to, "utf8"));
    assert.equal(summary.run_id, 41);
    assert.equal(summary.listing_held, true);
    assert.equal(summary.listing_held_reason, "failed 3 times");
    assert.equal(summary.candidates, null);
    assert.deepEqual(summary.results, []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the mode step outputs merge.lane-prs as resolve-config resolved it, and the listing reads it", () => {
  for (const mode of ["native", "gate"]) {
    const dir = tempDir("pr-merge-mode-");
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

// A stop past the budget is not slept: one call, gh's bare 429 message included.
test("a rate-limited listing holds the job after one call, a bare HTTP 429 included", () => {
  for (const failure of ["gh: Too Many Requests (HTTP 429)", "API rate limit exceeded for installation ID 1. (HTTP 403)"]) {
    const run = runListing(3, undefined, undefined, {}, failure);
    assertHeld(run);
    assert.equal(run.calls, 1, failure);
    assert.deepEqual(run.sleeps, [], failure);
    assert.match(run.stdout, /^::notice title=Merge lane hold::.*every pool until /m, failure);
  }
});

test("the listing holds the job after three failed tries", () => {
  const run = runListing(3);
  assertHeld(run);
  assert.equal(run.calls, 3);
  assert.doesNotMatch(run.stderr, /jq: error|Traceback/);
});

test("the job end logs both tokens' readings from the job's own responses, and reads no /rate_limit", () => {
  const block = step("Log the API budget at job end");
  assert.match(block, /\n {8}uses: \.\/\.base\/\.github\/actions\/log-api-budget /);
  assert.match(block, /\n {8}if: always\(\) && needs\.post-merge-dispatch\.outputs\.rate-limited == ''\n/);
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

// Runs the sweep-cost step with the end step's call counts and a summary of
// `reached` gate verdicts and `skipped` carried ones beside one held candidate.
const runSweepCost = (calls, reached, skipped = 0) => {
  const dir = tempDir("pr-merge-cost-");
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
      env: { ...process.env, RUNNER_TEMP: dir, GITHUB_STEP_SUMMARY: join(dir, "step-summary"), CALLS: calls, CANDIDATES: "5" },
    });
    return { status: result.status, stdout: result.stdout, stepSummary: readFileSync(join(dir, "step-summary"), "utf8") };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

test("the sweep cost names both tokens' own request counts, the candidates, those reached and those skipped, in the log and the summary", () => {
  const run = runSweepCost("lanes-app-calls=312 github-token-calls=41", 3, 2);
  assert.equal(run.status, 0);
  const line = "sweep-calls=312 github-token-calls=41 candidates=5 reached=3 skipped=2\n";
  assert.equal(run.stdout, line);
  assert.equal(run.stepSummary, line);
  // A token the job-end step wrote no count for reads unknown; a cost is not a count.
  assert.equal(runSweepCost("lanes-app-calls=7", 0).stdout, "sweep-calls=7 github-token-calls=unknown candidates=5 reached=0 skipped=0\n");
  assert.equal(runSweepCost("lanes-app-cost=312 github-token-cost=41", 0).stdout, "sweep-calls=unknown github-token-calls=unknown candidates=5 reached=0 skipped=0\n");
  const block = step("Write the sweep cost");
  assert.match(block, /CALLS: \$\{\{ steps\.budget-end\.outputs\.calls \}\}/);
  const names = steps.map((s) => s.name);
  assert.ok(names.indexOf("Log the API budget at job end") < names.indexOf("Write the sweep cost"));
});

test("a held listing's cost line names the tokens' calls, marks the hold, and has no counts to give", () => {
  const dir = tempDir("pr-merge-cost-held-");
  try {
    const result = spawnSync("bash", ["-eo", "pipefail", "-c", runScript("Write the sweep cost")], {
      encoding: "utf8",
      env: { ...process.env, RUNNER_TEMP: dir, GITHUB_STEP_SUMMARY: join(dir, "step-summary"), CALLS: "github-token-calls=41", CANDIDATES: "", LISTING_HELD: "true" },
    });
    const line = "sweep-calls=unknown github-token-calls=41 candidates=unknown reached=unknown skipped=unknown listing-held=true\n";
    assert.equal(result.stdout, line);
    assert.equal(readFileSync(join(dir, "step-summary"), "utf8"), line);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// The run cache's carried reads (carry-run-cache.mjs) reach both token-holding
// jobs as the head-ref map does (#9416): read from the last trusted run's
// pr-merge-run-cache artifact (with enable-auto-merge's
// pr-merge-verify-run-cache added), each uploaded by scheduled and
// hand-started runs only, the runs a later read accepts. Neither job restores an
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
  const scan = assertScanned("Upload the verdict reads for the next run", "always() && steps.carry.outputs.carried == 'true'");
  for (const block of [keep, scan, upload]) assert.match(block, /\n {8}continue-on-error: true\n/);
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
  const scan = assertScanned("Upload the verdict reads for the next run", "always() && steps.carry.outputs.kept == 'true'", list);
  assert.ok(upload.includes("\n        if: >-\n          (always() && steps.carry.outputs.kept == 'true') && steps.scan-upload-2.outputs.clean == 'true'\n"));
  // Keeping, scanning and uploading the reads never fails the job.
  for (const block of [keep, scan, upload]) assert.match(block, /\n {8}continue-on-error: true\n/);
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
  const scan = assertScanned("Upload them for the next run", "always() && steps.head-refs.outcome == 'success'");
  for (const block of [read, keep, scan, upload]) assert.match(block, /\n {8}continue-on-error: true\n/);
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
  assertScanned("Upload the lane records for the next run", "always() && steps.lane-records.outcome == 'success'");
  assert.doesNotMatch(jobBlock("post-merge-dispatch"), /name: pr-merge-lane-records|lane-records\.mjs write/);
  for (const s of steps.filter((s) => s.block.includes("actions/cache/"))) {
    assert.ok(!s.block.includes("lane-records"), s.name);
  }
});

// Runs the early job's check against a fake python3 that prints a report and
// exits `code`.
const runEarlyCheck = (code, needsDispatch = false, stops) => {
  const dir = tempDir("pr-merge-early-");
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
    const keptSha = join(dir, "post-merge-report", "post-merge-code-sha");
    return {
      status: result.status,
      stdout: result.stdout,
      output: readFileSync(output, "utf8"),
      keptCode: existsSync(keptCode) ? readFileSync(keptCode, "utf8").trim() : null,
      keptSha: existsSync(keptSha) ? readFileSync(keptSha, "utf8").trim() : null,
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

// post-merge-dispatch's check, run with the last run's report in
// post-merge-last (or none) and a fake python3: `settle` answers whether the
// report stands (exit `settle`), any other call is the check, which marks that
// it ran. The rule (pr-merge.yml): an idle tick reuses a report whose check
// passed (exit 0 or 5) and that `settle --idle-tick` keeps
// (babysit_verify_evidence.py, tested in test_babysit_lane_room.py
// IdleRefusal and SettleCommand), keeping its code and commit so the reuse
// ends SHARED_MAX_AGE after the check that made it; otherwise it runs the
// check.
const LAST_SHA = "d".repeat(40);
const lastReport = () => ({ readable: true, ok: true, needsDispatch: false, shared: { mainSha: "a".repeat(40) } });
const runIdleCheck = ({ last, code = "0", settle = 0, exit = 3, attempts } = {}) => {
  const dir = tempDir("pr-merge-idle-");
  try {
    const bin = join(dir, "bin");
    mkdirSync(bin);
    writeFileSync(
      join(bin, "python3"),
      `#!/usr/bin/env bash\nif [ "$2" = settle ]; then echo "$@" >"${dir}/settled"; exit ${settle}; fi\ntouch "${dir}/ran"\necho '{"ran": true}'\nexit ${exit}\n`,
    );
    chmodSync(join(bin, "python3"), 0o755);
    symlinkSync(root, join(dir, ".base"));
    writeFileSync(join(dir, "lane-records.json"), "read in");
    if (last !== undefined) {
      mkdirSync(join(dir, "post-merge-last"));
      writeFileSync(join(dir, "post-merge-last/post-merge.json"), JSON.stringify(last));
      writeFileSync(join(dir, "post-merge-last/post-merge-code"), `${code}\n`);
      writeFileSync(join(dir, "post-merge-last/post-merge-code-sha"), `${LAST_SHA}\n`);
      writeFileSync(join(dir, "post-merge-last/lane-records.json"), "the last run's");
      if (attempts !== undefined) writeFileSync(join(dir, "post-merge-last/attempts.json"), attempts);
    }
    const output = join(dir, "output");
    const result = spawnSync("bash", ["-c", runScript("Check earlier lane merges", stepsOf(jobBlock("post-merge-dispatch")))], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, GITHUB_OUTPUT: output, REPO: "o/r" },
    });
    const kept = (file) => (existsSync(join(dir, "post-merge-report", file)) ? readFileSync(join(dir, "post-merge-report", file), "utf8").trim() : null);
    return {
      status: result.status,
      stdout: result.stdout,
      ran: existsSync(join(dir, "ran")),
      settled: existsSync(join(dir, "settled")) ? readFileSync(join(dir, "settled"), "utf8").trim() : null,
      output: existsSync(output) ? readFileSync(output, "utf8") : "",
      report: kept("post-merge.json"),
      keptCode: kept("post-merge-code"),
      keptSha: kept("post-merge-code-sha"),
      records: kept("lane-records.json"),
      attempts: kept("attempts.json"),
      handed: existsSync(join(dir, "post-merge-attempts.json")) ? readFileSync(join(dir, "post-merge-attempts.json"), "utf8") : null,
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

test("an idle tick reuses the last run's report that settle --idle-tick keeps, with its code and commit", () => {
  for (const code of ["0", "5"]) {
    const run = runIdleCheck({ last: lastReport(), code });
    assert.equal(run.status, 0, run.stdout);
    assert.equal(run.ran, false, `exit ${code}: the check ran again`);
    assert.match(run.settled, new RegExp(`babysit_verify_evidence\\.py settle --idle-tick --repo o/r --postmerge-result \\S+/post-merge-last/post-merge\\.json --code-sha ${LAST_SHA}$`));
    assert.match(run.stdout, /::notice::the last run's post-merge check \(exit \d\) still stands: nothing it reads has moved; reused, not run again/);
    assert.match(run.output, new RegExp(`^code=${code}$`, "m"));
    assert.match(run.output, /^needs-dispatch=false$/m);
    // Kept for this run's later jobs and the next tick as it was made, with
    // the lane records this run read, not the last run's.
    assert.deepEqual(JSON.parse(run.report), lastReport());
    assert.equal(run.keptCode, code);
    assert.equal(run.keptSha, LAST_SHA);
    assert.equal(run.records, "read in");
  }
});

test("a tick runs the check itself for no report, a refusal, a crash or a check that did not pass", () => {
  const head = execFileSync("git", ["-C", root, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  for (const [why, options] of [
    ["none", {}],
    ["settle refuses", { last: lastReport(), settle: 1 }],
    ["settle crashes", { last: lastReport(), settle: 2 }],
    ...["1", "2", "3", "4", "75"].map((code) => [`exit ${code}`, { last: lastReport(), code }]),
  ]) {
    const run = runIdleCheck(options);
    assert.equal(run.ran, true, why);
    assert.match(run.output, /^code=3$/m, why);
    assert.deepEqual(JSON.parse(run.report), { ran: true }, why);
    assert.equal(run.keptSha, head, why);
    if (/^exit /.test(why)) assert.equal(run.settled, null, `${why} is not offered to settle`);
  }
});

// The attempt carry (babysit_postmerge.py ATTEMPTS_ENV): the last run's
// attempts file is handed to the check at the path the step names, and kept
// for the next tick whether the check runs or an idle tick reuses the report.
test("post-merge-dispatch hands the last run's attempts to the check and keeps them", () => {
  const file = "${{ runner.temp }}/post-merge-attempts.json";
  assert.ok(step("Check earlier lane merges", stepsOf(jobBlock("post-merge-dispatch"))).includes(`BABYSIT_POSTMERGE_ATTEMPTS: ${file}\n`));
  for (const options of [{}, { settle: 1 }]) {
    const run = runIdleCheck({ last: lastReport(), attempts: "carried", ...options });
    assert.equal(run.ran, options.settle === 1);
    assert.equal(run.handed, "carried");
    assert.equal(run.attempts, "carried");
  }
  assert.equal(runIdleCheck({ last: lastReport(), settle: 1 }).attempts, null);
});

test("post-merge-dispatch reads the last run's report before its check, from a trusted run alone", () => {
  const list = stepsOf(jobBlock("post-merge-dispatch"));
  const names = list.map((s) => s.name);
  const read = step("Read the post-merge report the last run kept", list);
  assert.equal(names.indexOf("Read the post-merge report the last run kept") + 1, names.indexOf("Check earlier lane merges"));
  assert.match(read, /\n {8}if: steps\.mode\.outputs\.live == 'true'\n {8}continue-on-error: true\n/);
  assert.ok(read.includes("LAST_REPORT_DIR: ${{ runner.temp }}/post-merge-last\n"));
  assert.match(read, /\n {8}run: node \.base\/\.github\/scripts\/pr-merge\/last-report\.mjs\n/);
});

// The merge job reuses the kept report only while the check's code at its
// own commit reads as it did here: the report keeps the commit it ran.
test("the early check keeps the commit whose code ran it beside its report", () => {
  const head = execFileSync("git", ["-C", root, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  for (const code of [0, 1, 3]) {
    const run = runEarlyCheck(code);
    assert.equal(run.status, 0, run.stdout);
    assert.equal(run.keptSha, head, String(code));
  }
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
    const dir = tempDir("pr-merge-stop-label-");
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
  const dir = tempDir("pr-merge-gate-");
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
  assert.match(block, /\n {10}steps\.lane-token\.outputs\.token != '' && steps\.mode\.outputs\.live == 'true'\n {10}&& steps\.post-merge\.outputs\.code == '1'\n {8}env:/);
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
  const dir = tempDir("pr-merge-record-");
  try {
    const bin = join(dir, "bin");
    execFileSync("mkdir", [bin]);
    writeFileSync(
      join(bin, "python3"),
      `#!/usr/bin/env bash\nprintf '%s\\n' "$@" >"${dir}/args"\ncat <<'EOF'\n${JSON.stringify(report)}\nEOF\nexit ${code}\n`,
    );
    chmodSync(join(bin, "python3"), 0o755);
    symlinkSync(root, join(dir, ".base"));
    const result = spawnSync("bash", ["-c", runScript("Record a failed lane merge")], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, REPO: "o/r" },
    });
    return {
      status: result.status,
      stdout: result.stdout,
      args: readFileSync(join(dir, "args"), "utf8").split("\n"),
    };
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
  const dir = tempDir("pr-merge-budget-");
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
      if (path === "steps.candidates.outputs.listed") return "true";
      // Every credential scan reads as clean: the rows go by their own condition.
      if (/^steps\.scan-upload(-\d+)?\.outputs\.clean$/.test(path)) return "true";
      return "";
    };
    for (const name of ["Hand the gate's rows to the check writer", "Re-fire lane runs refused as workflow-modified", "Clear escalations whose reason no longer holds"]) {
      assert.equal(stepRuns(step(name), context, "failure"), limited !== "true", `${name} with rate-limited=${limited}`);
    }
    const rowsScan = steps[steps.findIndex((s) => s.name === "Hand the gate's rows to the check writer") - 1];
    assert.equal(rowsScan.name, SCAN);
    assert.equal(stepRuns(rowsScan.block, context, "failure"), limited !== "true", `the rows' scan with rate-limited=${limited}`);
  }
  // The refusal count still writes its summary, with no read of the run.
  const dir = tempDir("pr-merge-count-");
  try {
    const bin = join(dir, "bin");
    mkdirSync(bin);
    // The step reads through the wrapped gh, which asks for the headers (-i).
    symlinkSync(fileURLToPath(new URL("../../..", import.meta.url)), join(dir, ".base"));
    writeFileSync(join(bin, "gh"), `#!/usr/bin/env bash\necho "$*" >>"${dir}/gh"\nprintf 'HTTP/2.0 200 OK\\r\\n\\r\\n'\necho 2026-10-26T00:00:00Z\n`);
    writeFileSync(join(bin, "node"), `#!/usr/bin/env bash\necho "RUN_STARTED_AT=$RUN_STARTED_AT" >"${dir}/node"\n`);
    for (const file of ["gh", "node"]) chmodSync(join(bin, file), 0o755);
    const sweep = join(dir, "sweep.json");
    writeFileSync(sweep, '{"refusal_counts": {}}');
    for (const limited of ["true", ""]) {
      rmSync(join(dir, "gh"), { force: true });
      const result = spawnSync("bash", ["-c", runScript("Count the sweep's refusals")], {
        cwd: dir,
        encoding: "utf8",
        env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, LIMITED: limited, LISTING_HELD: "", REPO: "o/r", GITHUB_RUN_ID: "1", SWEEP_SUMMARY_TO: sweep, RUNNER_TEMP: dir },
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
  const dir = tempDir("pr-merge-rotation-");
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
  // The upload's credential scan sits between the record and the upload.
  assert.equal(names[at("Keep the refusals the next run may skip") + 1], SCAN);
  assert.match(steps[at("Keep the refusals the next run may skip") + 1].block, /\n {8}id: scan-upload-4\n/);
  assert.equal(at("Upload the verdict reads for the next run"), at("Keep the refusals the next run may skip") + 2);
  const filter = step("Skip refusals whose inputs have not changed");
  assert.match(filter, /\n {8}continue-on-error: true\n/);
  assert.match(filter, /\n {8}if: steps\.lane-token\.outputs\.token != '' && steps\.candidates\.outputs\.listed == 'true'\n/);
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
  assertScanned("Record where the gate stopped", "always() && steps.gate.outcome != 'skipped'");
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
  const scan = assertScanned(
    "Hand the gate's rows to the check writer",
    "always() && steps.gate.outcome != 'skipped' && steps.mode.outputs.report-only == 'false' && steps.gate.outputs.rate-limited != 'true'",
  );
  for (const block of [scan, upload]) assert.match(block, /\n {8}continue-on-error: true\n/);
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
    ["Check out the default branch tip", "Set up Node", "Read the gate's rows", "Show each candidate's refusal as a check run", "Log the API budget at the end"],
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
  const dir = tempDir("pr-merge-early-report-");
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
  const dir = tempDir("pr-merge-rerun-");
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

// babysit_postmerge.py names in `reruns` only runs no newer green run
// settles, so the step re-runs the run it is given and reads nothing else
// first: a second rule here could skip a run the check still holds pending.
test("the re-run step re-runs the named run after reading only that run", () => {
  const run = runRerun([1, 2]);
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.calls.slice(0, 2).map((c) => c.replace(/ --jq .*/, "")), ["api repos/o/r/actions/runs/11", POST]);
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

test("post-merge-dispatch's rate-limited output also carries the cover, re-run and alert steps' stops", () => {
  const header = `${jobBlock("post-merge-dispatch").split("\n    steps:\n")[0]}\n`;
  assert.match(header, /\n {6}rate-limited: \$\{\{ steps\.post-merge\.outputs\.rate-limited \|\| steps\.cover\.outputs\.stop \|\| steps\.dispatch\.outputs\.stop \|\| steps\.rerun\.outputs\.stop \|\| steps\.alert\.outputs\.stop \}\}\n/);
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
    /\n {8}if: >-\n {10}!cancelled\(\)\n {10}&& steps\.cover\.outputs\.rate-limited != 'true'\n {10}&& steps\.dispatch\.outputs\.rate-limited != 'true'\n {10}&& contains\(fromJSON\('\["0","1","5"\]'\), steps\.post-merge\.outputs\.code\)\n {10}&& steps\.post-merge\.outputs\.lane-rerun != ''\n/,
  );
  assert.match(rerun, /\n {10}GH_TOKEN: \$\{\{ github\.token \}\}\n/);
  const upload = step("Record the re-run", list);
  assertScanned("Record the re-run", "!cancelled() && steps.rerun.outputs.recorded == 'true'", list);
  assert.match(upload, /uses: actions\/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 /);
  assert.match(upload, /\n {10}name: pr-merge-rerun-\$\{\{ steps\.post-merge\.outputs\.lane-rerun \}\}-attempt-2\n/);
});

// The alert send's step, run with .base at this checkout (the rate guard)
// against a fake gh that answers, through the guard's -i form and the step's
// --jq filter, a listing of pr-require-checks.yml dispatches on main (`runs`:
// {id, attempt, status, conclusion, sha, actor}), each later attempt's
// attempt 1 (`firsts` by id), each run's attempt-1 job count (`jobs` by id,
// default 3) and its pr-merge-alerted-<id> record count (`sent` by id,
// default 0). A read whose answer is "x" fails with a 502, "limited" with
// the rate-limited 403. `post` answers each send in turn: "ok", "unsent" (a
// TLS handshake timeout, before the request left), "502" or "limited" (a
// 429). The send replaces dispatch-full-run's wait step (efficiency plan item
// 7(b)): GITHUB_TOKEN started the full run, so it raises no workflow_run
// event, and post-merge-demotion-alert.yml hears of a red one only from here.
const ALERT_SHA = "0123456789abcdef0123456789abcdef01234567";
// main's tip, and the run of pr-merge.yml's post-merge-dispatch on it that a
// trusted pr-merge-alerted-<id> record comes from (babysit_postmerge.py
// _lane_sender: this repository's pr-merge.yml, a schedule or
// workflow_dispatch run, head_branch main, head commit on main's tip).
const ALERT_TIP = "fedcba9876543210fedcba9876543210fedcba98";
const ALERT_SENDER = {
  id: 900,
  path: ".github/workflows/pr-merge.yml",
  event: "schedule",
  head_branch: "main",
  head_sha: ALERT_TIP,
  repository: { full_name: "o/r" },
  head_repository: { full_name: "o/r" },
};
const alertSend = (id, sha = ALERT_SHA) =>
  `api -X POST repos/o/r/actions/workflows/post-merge-demotion-alert.yml/dispatches -f ref=main -f inputs[run-id]=${id} -f inputs[head-sha]=${sha}`;
const runAlert = ({ runs = [], firsts = {}, jobs = {}, sent = {}, post = ["ok"], listing, python } = {}) => {
  const dir = tempDir("pr-merge-alert-");
  try {
    const bin = join(dir, "bin");
    mkdirSync(bin);
    const fixture = (name, value) => writeFileSync(join(dir, name), typeof value === "string" ? value : JSON.stringify(value));
    fixture(
      "listing",
      listing ??
        {
          workflow_runs: runs.map((r) => ({
            id: r.id,
            run_attempt: r.attempt ?? 1,
            status: r.status ?? "completed",
            conclusion: r.conclusion ?? null,
            head_sha: r.sha ?? ALERT_SHA,
            head_branch: "main",
            actor: { login: r.actor ?? "github-actions[bot]" },
          })),
        },
    );
    for (const [id, a] of Object.entries(firsts)) fixture(`first.${id}`, a === "x" || a === "limited" ? a : { status: "completed", ...a });
    for (const r of runs) {
      const n = jobs[r.id] ?? 3;
      fixture(`jobs.${r.id}`, n === "x" || n === "limited" ? n : { total_count: n, jobs: [] });
      const s = sent[r.id] ?? 0;
      const record = (sender) => ({ id: 1, name: `pr-merge-alerted-${r.id}`, workflow_run: { id: sender } });
      if (s === "x" || s === "limited") fixture(`sent.${r.id}`, s);
      else if (typeof s === "number") fixture(`sent.${r.id}`, { total_count: s, artifacts: Array.from({ length: s }, () => record(900)) });
      else {
        // One same-name record from run 901: the trusted sender with `s` over it.
        fixture(`sent.${r.id}`, { total_count: 1, artifacts: [record(901)] });
        fixture("run.901", { ...ALERT_SENDER, id: 901, ...s });
      }
    }
    fixture("run.900", ALERT_SENDER);
    fixture("tip", { object: { sha: ALERT_TIP } });
    writeFileSync(
      join(bin, "gh"),
      `#!/usr/bin/env bash
inc=; args=()
for a in "$@"; do if [ "$a" = -i ]; then inc=1; else args+=("$a"); fi; done
set -- "\${args[@]}"
echo "$*" >>"${dir}/calls"
filter=.; for ((i = 1; i <= $#; i++)); do if [ "\${!i}" = --jq ]; then j=$((i + 1)); filter="\${!j}"; fi; done
endpoint=$(printf '%s\\n' "$@" | grep -m1 '^repos/')
head() { [ -z "$inc" ] || printf "$1"; }
if [ "$2" = -X ]; then
  p=(${[post].flat().join(" ")}); s=$(($(cat "${dir}/posts" 2>/dev/null || echo 0) + 1)); echo "$s" >"${dir}/posts"
  case "\${p[$((s - 1))]:-\${p[-1]}}" in
    ok) head 'HTTP/2.0 204 No Content\\r\\n\\r\\n'; exit 0 ;;
    unsent) echo 'Post "https://api.github.com/repos/o/r/actions/workflows/post-merge-demotion-alert.yml/dispatches": net/http: TLS handshake timeout' >&2; exit 1 ;;
    502) head 'HTTP/2.0 502 Bad Gateway\\r\\n\\r\\n{}\\n'; echo "gh: Server Error (HTTP 502)" >&2; exit 1 ;;
    limited) head 'HTTP/2.0 429 Too Many Requests\\r\\nRetry-After: 60\\r\\n\\r\\n{"message": "Too many requests"}\\n'; echo "gh: Too Many Requests (HTTP 429)" >&2; exit 1 ;;
  esac
fi
case "$endpoint" in
  */workflows/pr-require-checks.yml/runs\\?*) f=listing ;;
  */attempts/1/jobs*) f=jobs.$(sed -E 's#.*/runs/([0-9]+)/.*#\\1#' <<<"$endpoint") ;;
  */attempts/1) f=first.$(sed -E 's#.*/runs/([0-9]+)/.*#\\1#' <<<"$endpoint") ;;
  */artifacts\\?name=pr-merge-alerted-*) f=sent.$(sed -E 's#.*pr-merge-alerted-([0-9]+).*#\\1#' <<<"$endpoint") ;;
  repos/o/r/actions/runs/90[01]) f=run.\${endpoint##*/} ;;
  repos/o/r/git/ref/heads/main) f=tip ;;
  *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
v=$(cat "${dir}/$f")
if [ "$v" = x ]; then head 'HTTP/2.0 502 Bad Gateway\\r\\n\\r\\n'; echo '{}'; echo "gh: Server Error (HTTP 502)" >&2; exit 1; fi
if [ "$v" = limited ]; then head '${LIMITED_403}'; echo '${RATE_LIMITED_STDERR}' >&2; exit 1; fi
head 'HTTP/2.0 200 OK\\r\\n\\r\\n'
jq -r "$filter" <<<"$v"
`,
    );
    writeFileSync(join(bin, "sleep"), `#!/usr/bin/env bash\necho "$1" >>"${dir}/slept"\n`);
    chmodSync(join(bin, "gh"), 0o755);
    chmodSync(join(bin, "sleep"), 0o755);
    // `python`: a stand-in for babysit_postmerge.py's process, as a bash body.
    if (python) writeFileSync(join(bin, "python3"), `#!/usr/bin/env bash\n${python}\n`, { mode: 0o755 });
    symlinkSync(root, join(dir, ".base"));
    const result = spawnSync("bash", ["-c", runScript("Send a red full run to the demotion alert", earlySteps())], {
      cwd: dir,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        RUNNER_TEMP: dir,
        GITHUB_OUTPUT: join(dir, "output"),
        GITHUB_RUN_ID: "700",
        REPO: "o/r",
        LOOKBACK_HOURS: /\n {10}LOOKBACK_HOURS: (\d+)\n/.exec(step("Send a red full run to the demotion alert", earlySteps()))[1],
      },
    });
    const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
    const calls = read("calls").split("\n").filter(Boolean);
    return {
      status: result.status,
      out: result.stdout + result.stderr,
      calls,
      sends: calls.filter((c) => c.includes("-X POST")),
      output: read("output"),
      record: read("alerted.json"),
      slept: read("slept").split("\n").filter(Boolean).map(Number),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

test("a red full run is sent to post-merge-demotion-alert.yml once, by its run id and head SHA, and recorded", () => {
  const run = runAlert({ runs: [{ id: 41, conclusion: "failure" }] });
  assert.equal(run.status, 0, run.out);
  assert.deepEqual(run.sends, [alertSend(41)]);
  assert.match(run.output, /^run-id=41$/m);
  assert.deepEqual(JSON.parse(run.record), { alerter_run_id: 700, run_id: 41 });
  assert.ok(run.calls[0].includes("actions/workflows/pr-require-checks.yml/runs?event=workflow_dispatch&branch=main&created=%3E%3D"), run.calls[0]);
  const upload = step("Record the alert sent", earlySteps());
  assertScanned("Record the alert sent", "!cancelled() && steps.alert.outputs.run-id != ''", earlySteps());
  assert.match(upload, /uses: actions\/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 /);
  assert.match(upload, /\n {10}name: pr-merge-alerted-\$\{\{ steps\.alert\.outputs\.run-id \}\}\n/);
});

// babysit_postmerge.py's FAILED_CONCLUSIONS, the conclusions post-merge
// demotion counts as red: a cancel once the jobs started is red too.
test("every red conclusion of a full run is sent", () => {
  for (const conclusion of ["failure", "timed_out", "cancelled", "startup_failure", "action_required"]) {
    const run = runAlert({ runs: [{ id: 41, conclusion }] });
    assert.equal(run.status, 0, `${conclusion}: ${run.out}`);
    assert.deepEqual(run.sends, [alertSend(41)], conclusion);
  }
});

test("a green, running or other actor's run, one already sent, and one the group replaced are sent nowhere", () => {
  const run = runAlert({
    runs: [
      { id: 40, conclusion: "success" },
      { id: 41, conclusion: "skipped" },
      { id: 42, status: "in_progress" },
      { id: 43, conclusion: "failure", actor: "maintainer" },
      { id: 44, conclusion: "failure" },
      { id: 45, conclusion: "cancelled" },
    ],
    sent: { 44: 1 },
    jobs: { 45: 0 },
  });
  assert.equal(run.status, 0, run.out);
  assert.deepEqual(run.sends, []);
  assert.match(run.out, /run 45 was replaced before it started: no signal/);
  assert.equal(run.record, "");
});

// The re-run step may have made attempt 2 first: attempt 1 decides.
test("a run past attempt 1 is judged on attempt 1", () => {
  const red = runAlert({ runs: [{ id: 41, attempt: 2, conclusion: "success" }], firsts: { 41: { conclusion: "failure" } } });
  assert.deepEqual(red.sends, [alertSend(41)], red.out);
  const green = runAlert({ runs: [{ id: 41, attempt: 2, conclusion: "failure" }], firsts: { 41: { conclusion: "success" } } });
  assert.deepEqual(green.sends, [], green.out);
});

// Review finding on #10491 (claude-security-review): a run sent counts only
// when pr-merge.yml's own post-merge-dispatch on main uploaded its record, by
// babysit_postmerge.py's sender rule (_lane_sender), which this step runs. A
// same-name artifact from any other run, such as a pull request run, does
// not suppress the send.
test("a same-name record from a run that is not pr-merge.yml's on main does not suppress the alert", () => {
  const trusted = runAlert({ runs: [{ id: 41, conclusion: "failure" }], sent: { 41: {} } });
  assert.equal(trusted.status, 0, trusted.out);
  assert.deepEqual(trusted.sends, [], "control: the lane's own record is a send already made");
  assert.ok(trusted.calls.includes("api repos/o/r/actions/runs/901"), trusted.calls.join("\n"));
  for (const forged of [
    { event: "pull_request" },
    { event: "pull_request_target" },
    { event: "push" },
    { path: ".github/workflows/ci.yml" },
    { head_branch: "feature" },
    { head_repository: { full_name: "outsider/r" } },
    { repository: { full_name: "outsider/r" } },
  ]) {
    const run = runAlert({ runs: [{ id: 41, conclusion: "failure" }], sent: { 41: forged } });
    assert.equal(run.status, 0, run.out);
    assert.deepEqual(run.sends, [alertSend(41)], JSON.stringify(forged));
  }
});

// Review finding on #10491 (claude-review): only --lane-alerted's "not
// recorded" code (EXIT_NOT_ALERTED, 4) sends. An uncaught exception exits 1
// with a traceback, and any code but 0, 4 and 75 leaves the run to the next
// run, so a crashing check never sends the same run again each tick.
test("a record check that crashes or answers an unknown code sends nothing", () => {
  const traceback = 'echo "Traceback (most recent call last):" >&2; echo "TypeError: unexpected" >&2; exit 1';
  for (const python of [traceback, "exit 2", "exit 3", "exit 5"]) {
    const run = runAlert({ runs: [{ id: 41, conclusion: "failure" }], python });
    assert.equal(run.status, 0, run.out);
    assert.deepEqual(run.sends, [], python);
    assert.match(run.out, /::warning::the record read of run 41 failed \(exit \d\); the next run tries again/);
    assert.equal(run.record, "");
  }
  // Control: the not-recorded code sends.
  const missing = runAlert({ runs: [{ id: 41, conclusion: "failure" }], python: "exit 4" });
  assert.deepEqual(missing.sends, [alertSend(41)], missing.out);
});

test("one run per job: the oldest red one unsent, the next on the next run", () => {
  const run = runAlert({
    runs: [
      { id: 52, conclusion: "failure", sha: "89abcdef0123456789abcdef0123456789abcdef" },
      { id: 51, conclusion: "failure" },
    ],
  });
  assert.deepEqual(run.sends, [alertSend(51)]);
});

test("a failed read of one run's jobs or record sends nothing for it and moves on", () => {
  const run = runAlert({
    runs: [
      { id: 41, conclusion: "cancelled" },
      { id: 42, conclusion: "failure" },
      { id: 43, conclusion: "failure" },
    ],
    jobs: { 41: "x" },
    sent: { 42: "x" },
  });
  assert.equal(run.status, 0, run.out);
  assert.deepEqual(run.sends, [alertSend(43)]);
  assert.match(run.out, /::warning::the jobs read of run 41 failed/);
  assert.match(run.out, /::warning::the record read of run 42 failed/);
  const listing = runAlert({ listing: "x" });
  assert.equal(listing.status, 0);
  assert.match(listing.out, /::warning::the listing of main's full runs failed/);
});

// The owner outage rule (Q677: at most three attempts, a capped full-jitter
// backoff), sent again only when the request never left, as the dispatch.
test("an alert send that never left is sent again after a jittered wait, at most three times", () => {
  const sent = runAlert({ runs: [{ id: 41, conclusion: "failure" }], post: ["unsent", "unsent", "ok"] });
  assert.equal(sent.status, 0, sent.out);
  assert.deepEqual(sent.sends, [alertSend(41), alertSend(41), alertSend(41)]);
  assert.equal(sent.slept.length, 2);
  assert.ok(sent.slept[0] >= 1 && sent.slept[0] <= 10, `${sent.slept[0]}`);
  assert.ok(sent.slept[1] >= 1 && sent.slept[1] <= 20, `${sent.slept[1]}`);
  const spent = runAlert({ runs: [{ id: 41, conclusion: "failure" }], post: ["unsent"] });
  assert.equal(spent.status, 0, spent.out);
  assert.equal(spent.sends.length, 3);
  assert.match(spent.out, /::warning::could not send run 41 to post-merge-demotion-alert\.yml after 3 attempt\(s\); the next run tries again/);
  assert.equal(spent.record, "");
  // A send that may have reached GitHub is not sent again.
  const answered = runAlert({ runs: [{ id: 41, conclusion: "failure" }], post: ["502", "ok"] });
  assert.deepEqual(answered.sends, [alertSend(41)]);
  assert.equal(answered.record, "");
});

test("a rate-limited read or send stops red with the stop as the job's output, sending nothing more", () => {
  const send = runAlert({ runs: [{ id: 41, conclusion: "failure" }, { id: 42, conclusion: "failure" }], post: ["limited"] });
  assert.equal(send.status, 1, send.out);
  assert.deepEqual(send.sends, [alertSend(41)]);
  assert.match(send.out, /::error title=GitHub rate limit::the send of run 41 to post-merge-demotion-alert\.yml was rate limited/);
  assert.match(send.output, /^rate-limited=true$/m);
  assert.match(send.output, /^stop=/m);
  const read = runAlert({ runs: [{ id: 41, conclusion: "failure" }], sent: { 41: "limited" } });
  assert.equal(read.status, 1, read.out);
  assert.deepEqual(read.sends, []);
  assert.match(read.out, /::error title=GitHub rate limit::the record read of run 41 was rate limited/);
  assert.match(jobBlock("post-merge-dispatch"), /\n {6}rate-limited: \$\{\{ [^\n]*\|\| steps\.alert\.outputs\.stop \}\}\n/);
});

// Every merge's run is sent, as dispatch-full-run starts it, whoever merged,
// after a dispatch or re-run that failed for any reason but a rate limit, and
// only while the lane is live (review decision on #10491: the kill switch and
// report-only stop everything the scheduled job spends API on).
test("the alert send runs after the re-run while the lane is live, and stops after a rate limit", () => {
  const list = earlySteps();
  const alert = step("Send a red full run to the demotion alert", list);
  assert.match(
    alert,
    /\n {8}if: >-\n {10}!cancelled\(\)\n {10}&& steps\.kill\.outputs\.proceed == 'true'\n {10}&& steps\.mode\.outputs\.live == 'true'\n {10}&& steps\.post-merge\.outputs\.code != '75'\n {10}&& steps\.cover\.outputs\.rate-limited != 'true'\n {10}&& steps\.dispatch\.outputs\.rate-limited != 'true'\n {10}&& steps\.rerun\.outputs\.rate-limited != 'true'\n/,
  );
  const names = list.map((s) => s.name);
  assert.deepEqual(names.slice(-4), [
    "Send a red full run to the demotion alert",
    SCAN,
    "Record the alert sent",
    "Log the API budget at the end",
  ]);
});

// The scheduled job's cover read, run with .base at this checkout (the rate
// guard) against a fake gh whose listing answers `answer`: "limited" with the
// rate-limited 403, "x" with a 502.
const runPostMergeCover = (answer) => {
  const dir = tempDir("pr-merge-pm-cover-");
  try {
    const bin = join(dir, "bin");
    mkdirSync(bin);
    writeFileSync(
      join(bin, "gh"),
      `#!/usr/bin/env bash
inc=; args=()
for a in "$@"; do if [ "$a" = -i ]; then inc=1; else args+=("$a"); fi; done
echo "\${args[*]}" >>"${dir}/calls"
if [ "${answer}" = limited ]; then [ -z "$inc" ] || printf '${LIMITED_403}'; echo '${RATE_LIMITED_STDERR}' >&2; exit 1; fi
[ -z "$inc" ] || printf 'HTTP/2.0 502 Bad Gateway\\r\\n\\r\\n'; echo '{}'; echo "gh: Server Error (HTTP 502)" >&2; exit 1
`,
    );
    chmodSync(join(bin, "gh"), 0o755);
    symlinkSync(root, join(dir, ".base"));
    const result = spawnSync("bash", ["-c", runScript("Read main's full-run cover", earlySteps())], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, GITHUB_OUTPUT: join(dir, "output"), REPO: "o/r", TIP: ALERT_SHA, CAP_MINUTES: "30" },
    });
    const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), "utf8") : "");
    return { status: result.status, out: result.stdout + result.stderr, output: read("output"), calls: read("calls").split("\n").filter(Boolean) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

// stop-on-limit (docs/conventions/pr-pipeline/README.md, rate-stop.bash): a
// cover read refused for a rate limit stops the step red with the stop as the
// job's rate-limited output, and no later step of the job calls GitHub.
test("a rate-limited cover read stops post-merge-dispatch red, and nothing after it calls GitHub", () => {
  const limited = runPostMergeCover("limited");
  assert.equal(limited.status, 1, limited.out);
  assert.equal(limited.calls.length, 1);
  assert.match(limited.out, /::error title=GitHub rate limit::the read of main's full runs was rate limited \(the core pool until 2100-01-01T00:00:00Z\)/);
  assert.match(limited.output, /^rate-limited=true$/m);
  assert.match(limited.output, /^stop=the core pool until 2100-01-01T00:00:00Z$/m);
  // Any other failed read is no stop: no cap applies, as before.
  const other = runPostMergeCover("x");
  assert.equal(other.status, 0, other.out);
  assert.doesNotMatch(other.output, /rate-limited|stop=/);
  assert.match(other.out, /::warning::the read of main's full runs failed; no cap applies to this run/);

  const list = earlySteps();
  const live = { "steps.kill.outputs.proceed": "true", "steps.mode.outputs.live": "true", "steps.post-merge.outputs.code": "0", "steps.post-merge.outputs.needs-dispatch": "true", "steps.post-merge.outputs.lane-rerun": "11", "steps.cover.outputs.uncovered": "true" };
  const after = ["Start the full CI run on main", "Re-run a red lane-dispatched full run", "Send a red full run to the demotion alert"];
  // Control: with the read answered, each later API step runs.
  for (const name of after) assert.equal(stepRuns(step(name, list), (p) => live[p] ?? "", "success"), true, name);
  const stopped = { ...live, "steps.cover.outputs.rate-limited": "true", "steps.cover.outputs.stop": "the core pool until 2100-01-01T00:00:00Z" };
  for (const name of after) assert.equal(stepRuns(step(name, list), (p) => stopped[p] ?? "", "failure"), false, name);
  // The merge and enable-auto-merge jobs stop on that output.
  for (const id of ["merge", "enable-auto-merge"]) {
    const first = stepsOf(jobBlock(id)).find((s) => s.name === "Stop on post-merge-dispatch's rate limit");
    assert.ok(first, id);
    assert.match(first.block, /\n {8}if: needs\.post-merge-dispatch\.outputs\.rate-limited != ''\n/);
  }
});

// Review decision on #10491: the kill switch and report-only stop everything
// post-merge-dispatch does that spends API or starts a run: the cover read,
// the pr-require-checks.yml dispatch on main and the alert dispatch.
// dispatch-full-run's push carve-out stays.
const spending = [
  "Read main's full-run cover",
  "Start the full CI run on main",
  "Record the dispatched run",
  "Re-run a red lane-dispatched full run",
  "Record the re-run",
  "Send a red full run to the demotion alert",
  "Record the alert sent",
];
test("the kill switch and report-only stop the scheduled job's cover read, dispatch and alert send", () => {
  const list = earlySteps();
  const base = { "steps.cover.outputs.uncovered": "true", "steps.post-merge.outputs.needs-dispatch": "true" };
  const reportOnly = { ...base, "steps.kill.outputs.proceed": "true" };
  for (const name of spending) assert.equal(stepRuns(step(name, list), (p) => reportOnly[p] ?? "", "success"), false, `${name} while report-only`);
  const live = { ...reportOnly, "steps.mode.outputs.live": "true" };
  for (const name of ["Read main's full-run cover", "Start the full CI run on main", "Send a red full run to the demotion alert"]) {
    assert.equal(stepRuns(step(name, list), (p) => live[p] ?? "", "success"), true, `${name} while live`);
  }
});

// The kill switch's own action, run with CLAUDE_LANES_DISABLED or
// CLAUDE_LANES_REPO_DISABLED set, then every later step of the scheduled job
// evaluated over its output: no step that starts a pr-require-checks.yml run
// or sends to the alert runs, nor the steps those switches skip.
test("with either kill switch set, the scheduled job starts no full run and sends no alert", () => {
  const list = earlySteps();
  const killAt = list.findIndex((s) => s.name === "Check the kill switch");
  assert.match(list[killAt].block, /\n {10}value: \$\{\{ vars\.CLAUDE_LANES_DISABLED \}\}\n {10}repo-value: \$\{\{ vars\.CLAUDE_LANES_REPO_DISABLED \}\}\n/);
  const killSwitch = (org, repo) => {
    const dir = tempDir("pr-merge-kill-");
    try {
      const out = join(dir, "output");
      writeFileSync(out, "");
      execFileSync("node", [join(root, ".github/actions/check-kill-switch/check-kill-switch.mjs")], {
        env: { ...process.env, KILL_SWITCH_VALUE: org, REPO_KILL_SWITCH_VALUE: repo, GITHUB_OUTPUT: out },
      });
      return /^proceed<<(\S+)\n(.*)\n\1$/m.exec(readFileSync(out, "utf8"))[2];
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };
  assert.equal(killSwitch("false", "false"), "true", "control: both off proceeds");
  for (const [org, repo] of [["true", "false"], ["false", "true"]]) {
    const proceed = killSwitch(org, repo);
    assert.equal(proceed, "false", `CLAUDE_LANES_DISABLED=${org} CLAUDE_LANES_REPO_DISABLED=${repo}`);
    const context = (p) => (p === "steps.kill.outputs.proceed" ? proceed : "");
    for (const { name, block } of list.slice(killAt + 1)) {
      if (["Check earlier lane merges", "Read the lane records the last run kept", "Read report-only", ...spending].includes(name)) {
        assert.equal(stepRuns(block, context, "success"), false, `${name} with ${org}/${repo}`);
      }
    }
  }
  assert.doesNotMatch(jobBlock("dispatch-full-run"), /steps\.(kill|mode)\./, "the push carve-out stays");
});

// The merge job's check, run with this run's post-merge-dispatch report kept
// in post-merge-kept (or none) and a fake python3: `settle` answers whether
// the report stands (exit `settle`), any other call is the check, which marks
// that it ran. The rule (pr-merge.yml): reuse a report whose check judged
// (exit 0, 1 or 5) and that `settle` keeps (babysit_verify_evidence.py, the
// lane room's rule, tested in test_babysit_lane_room.py) given the commit
// post-merge-dispatch's check ran (`codeSha`, null for no file); otherwise
// run the check. `yqFails` puts a yq that fails on the PATH.
const KEPT_SHA = "b".repeat(40);
const runMergeCheck = ({ kept, code = "0", codeSha = KEPT_SHA, records, settle = 0, exit = 3, report = { ran: true }, yqFails = false } = {}) => {
  const dir = tempDir("pr-merge-reuse-");
  try {
    const bin = join(dir, "bin");
    mkdirSync(bin);
    writeFileSync(
      join(bin, "python3"),
      `#!/usr/bin/env bash\nif [ "$2" = settle ]; then echo "$@" >"${dir}/settled"; exit ${settle}; fi\ntouch "${dir}/ran"\necho '${JSON.stringify(report)}'\nexit ${exit}\n`,
    );
    chmodSync(join(bin, "python3"), 0o755);
    if (yqFails) {
      writeFileSync(join(bin, "yq"), "#!/usr/bin/env bash\nexit 1\n");
      chmodSync(join(bin, "yq"), 0o755);
    }
    symlinkSync(root, join(dir, ".base"));
    writeFileSync(join(dir, "lane-records.json"), "read in");
    if (kept !== undefined) {
      mkdirSync(join(dir, "post-merge-kept"));
      writeFileSync(join(dir, "post-merge-kept/post-merge.json"), JSON.stringify(kept));
      writeFileSync(join(dir, "post-merge-kept/post-merge-code"), `${code}\n`);
      if (codeSha !== null) writeFileSync(join(dir, "post-merge-kept/post-merge-code-sha"), `${codeSha}\n`);
      if (records !== undefined) writeFileSync(join(dir, "post-merge-kept/lane-records.json"), records);
    }
    const output = join(dir, "output");
    const result = spawnSync("bash", ["-c", runScript("Check earlier lane merges")], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, GITHUB_OUTPUT: output, REPO: "o/r" },
    });
    return {
      status: result.status,
      stdout: result.stdout,
      ran: existsSync(join(dir, "ran")),
      settled: existsSync(join(dir, "settled")) ? readFileSync(join(dir, "settled"), "utf8").trim() : null,
      output: existsSync(output) ? readFileSync(output, "utf8") : "",
      report: existsSync(join(dir, "post-merge.json")) ? JSON.parse(readFileSync(join(dir, "post-merge.json"), "utf8")) : null,
      records: readFileSync(join(dir, "lane-records.json"), "utf8"),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};
const keptReport = () => ({ readable: true, needsDispatch: true, shared: { mainSha: "a".repeat(40) } });

test("the merge job reuses this run's post-merge report that settle keeps, with its code and lane records", () => {
  for (const code of ["0", "1", "5"]) {
    const run = runMergeCheck({ kept: keptReport(), code, records: "proved" });
    assert.equal(run.status, 0, run.stdout);
    assert.equal(run.ran, false, code);
    assert.match(run.output, new RegExp(`^code=${code}$`, "m"));
    assert.match(run.output, /^needs-dispatch=true$/m);
    assert.equal(run.report.shared.mainSha, "a".repeat(40));
    assert.equal(run.records, "proved");
    assert.match(run.stdout, /::notice::post-merge-dispatch's check \(exit \d\) still stands by the lane room's reuse rule; reused, not run again/);
  }
  // settle is given the commit whose code ran the kept check, and reads the
  // lane's identity itself.
  const run = runMergeCheck({ kept: keptReport() });
  assert.match(run.settled, new RegExp(`babysit_verify_evidence\\.py settle --repo o/r --postmerge-result \\S+/post-merge-kept/post-merge\\.json --code-sha ${KEPT_SHA}$`));
  // With no commit kept, an empty one, which settle refuses.
  assert.match(runMergeCheck({ kept: keptReport(), codeSha: null }).settled, / --code-sha$/);
  // A report kept with no lane records leaves the ones read in.
  assert.equal(run.records, "read in");
  // The identity read (yq) is the fresh check's alone: a reused report
  // needs none, so a failing yq fails only the check that needs it.
  const reused = runMergeCheck({ kept: keptReport(), yqFails: true });
  assert.equal(reused.status, 0, reused.stdout);
  assert.equal(reused.ran, false);
  const fresh = runMergeCheck({ kept: keptReport(), settle: 1, yqFails: true });
  assert.notEqual(fresh.status, 0);
  assert.equal(fresh.ran, false);
});

test("the merge job runs the check itself for no report, a report settle refuses or a check that could not judge", () => {
  for (const [why, options] of [
    ["none", {}],
    ["settle refuses", { kept: keptReport(), settle: 1 }],
    ["settle crashes", { kept: keptReport(), settle: 2 }],
    ["exit 3", { kept: keptReport(), code: "3" }],
    ["exit 75", { kept: keptReport(), code: "75" }],
  ]) {
    const run = runMergeCheck({ ...options, records: "proved" });
    assert.equal(run.ran, true, why);
    assert.match(run.output, /^code=3$/m, why);
    assert.deepEqual(run.report, { ran: true }, why);
    assert.equal(run.records, "read in", why);
  }
  // A code that could not judge is not offered to settle.
  assert.equal(runMergeCheck({ kept: keptReport(), code: "3" }).settled, null);
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
