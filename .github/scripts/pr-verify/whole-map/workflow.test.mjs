/**
 * maintenance-verify-whole-map.yml: a whole-map pass on a listed human's
 * dispatch, in pr-verify-capture.yml's sandbox, launch broker and key proxy.
 * The steps both workflows run are held identical to the capture's under
 * SUBSTITUTIONS, so the capture stays their one source and its credential
 * separation carries over unchanged.
 */
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "../../../../lib/test-tmp.mjs";

const REPO = fileURLToPath(new URL("../../../../", import.meta.url));
const MAP = readFileSync(path.join(REPO, ".github/workflows/maintenance-verify-whole-map.yml"), "utf8");
const CAPTURE = readFileSync(path.join(REPO, ".github/workflows/pr-verify-capture.yml"), "utf8");
const JOB = "verify-map";

const jobIn = (source, id) => {
  const found = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(source);
  assert.ok(found, `a job ${id}`);
  return found[1];
};
const jobIds = (source) => [.../\njobs:\n([\s\S]*)$/.exec(source)[1].matchAll(/^ {2}([a-z][a-z0-9-]*):$/gm)].map((m) => m[1]);
const stepsIn = (source, id) =>
  jobIn(source, id)
    .split(/\n(?=      - name: )/)
    .slice(1)
    .map((block) => ({ name: /^      - name: (.*)$/m.exec(block)[1], block }));
const STEPS = stepsIn(MAP, JOB);
const CAP_STEPS = stepsIn(CAPTURE, "capture");
const at = (name, steps = STEPS) => {
  const index = steps.findIndex((s) => s.name === name);
  assert.ok(index >= 0, `a step named ${name}`);
  return index;
};
const step = (name, steps = STEPS) => steps[at(name, steps)].block;
const input = (block, key) => new RegExp(`^ {10}${key}: (.*)$`, "m").exec(block)?.[1];
const list = (block, key) => (new RegExp(`^ {10}${key}: \\|\\n((?: {12}.*\\n?)+)`, "m").exec(block)?.[1] ?? "").split("\n").map((l) => l.trim()).filter(Boolean);
const scriptOf = (block) => /^ {8}run: \|\n((?: {10}.*\n?|\n)+)/m.exec(block)[1].replace(/^ {10}/gm, "");
/** A step without its comment lines, which hold the next step's comment too. */
const bare = (block) => block.replace(/^ *#.*\n?/gm, "").trim();
const RUN_CLAUDE_CLI = /uses: melodic-software\/ci-workflows\/\.github\/actions\/run-claude-cli@[0-9a-f]{40} /;

/** What a shared step may differ in: the lane's name, the credit markers' names (gate.cjs names them from the workflow file and the job), and the commit the driven session's clone must be at. */
const SUBSTITUTIONS = [
  ["lane: pr-verify-capture\n", "lane: maintenance-verify-whole-map\n"],
  ["lane-id: pr-verify-capture\n", "lane-id: maintenance-verify-whole-map\n"],
  ["pr-verify-capture.yml-capture", "maintenance-verify-whole-map.yml-verify-map"],
  ["key-job: capture\n", "key-job: verify-map\n"],
  ["HEAD_SHA: ${{ steps.pr.outputs.head-sha }}", "HEAD_SHA: ${{ github.sha }}"],
];
const substitute = (text) => SUBSTITUTIONS.reduce((out, [from, to]) => out.split(from).join(to), text);
const SHARED = [
  "Set up Node",
  "Report the skipped key leg",
  "Write the key's probing marker",
  "Scan the key's probing marker for credentials",
  "Upload the key's probing marker",
  "Log the API budget",
  "Create the key proxy's user and directories",
  "Install the driven Claude Code",
  "Install the screenshot font",
  "Install the driver and its engine",
  "Write the driven settings and the proxy config",
  "Apply the Claude managed settings",
  "Start the key proxy",
  "Isolate the runner",
  "Start the sentinel",
  "Start the sibling sandbox",
  "Check the sibling sandbox",
  "Write the probe prompt",
  "Check the driver legs hold no real key",
  "Probe what head code can reach",
  "Upload the probe's sealed transcript",
  "Record the probe leg",
  "Write the key's credit-stop marker",
  "Scan the key's credit-stop marker for credentials",
  "Upload the key's credit-stop marker",
  "Report the key's handoff",
  "Check the probe",
  "Pick the next leg",
  "Clone the head for the driven session",
  "Upload the capture's sealed transcript",
  "Stop the sibling sandbox",
  "Stop the key proxy",
  "Report the key proxy's usage",
  "Remove the checkouts' .git directories",
];
/** Shared but for the condition they run on, which chains on this workflow's own plan. */
const SHARED_BUT_IF = ["Read the key's credit history", "Check the credential"];

test("each shared step is the capture's, under the substitution table alone", () => {
  for (const name of SHARED) assert.equal(bare(step(name)), substitute(bare(step(name, CAP_STEPS))), name);
  const noIf = (block) => bare(block).replace(/^ {8}if: .*\n/m, "");
  for (const name of SHARED_BUT_IF) assert.equal(noIf(step(name)), substitute(noIf(step(name, CAP_STEPS))), name);
  const shared = [...SHARED, ...SHARED_BUT_IF].map((name) => step(name, CAP_STEPS)).join("\n");
  for (const [from] of SUBSTITUTIONS) assert.ok(shared.includes(from), `the substitution ${from} changes no shared step`);
});

test("the shared steps keep the capture's order", () => {
  const order = (steps) => SHARED.map((name) => at(name, steps));
  for (const steps of [STEPS, CAP_STEPS]) {
    const found = order(steps);
    assert.deepEqual([...found].sort((a, b) => a - b), found);
  }
});

test("only a dispatch on the default branch runs it, once, with read-only permissions", () => {
  const on = /\non:\n([\s\S]*?)\n\n/.exec(MAP)[1];
  assert.deepEqual([...on.matchAll(/^ {2}([a-z_]+):/gm)].map((m) => m[1]), ["workflow_dispatch"]);
  const inputs = [...on.matchAll(/^ {6}([a-z_]+):\n((?: {8}.*\n?)+)/gm)].map(([, name, body]) => [name, /default: (.*)/.exec(body)[1], /type: (.*)/.exec(body)[1]]);
  assert.deepEqual(inputs, [
    ["features", '""', "string"],
    ["max_entries", '"40"', "string"],
    ["baseline_run", '""', "string"],
  ]);
  assert.match(MAP, /^permissions: \{\}$/m);
  assert.deepEqual(jobIds(MAP), [JOB]);
  const job = jobIn(MAP, JOB);
  assert.match(job, /^ {4}if: github\.ref == format\('refs\/heads\/\{0\}', github\.event\.repository\.default_branch\) && github\.run_attempt == '1'$/m);
  const granted = /^ {4}permissions:\n((?: {6}.*\n)+)/m.exec(job)[1].trim().split("\n").map((line) => line.trim().split(" #")[0]);
  assert.deepEqual(granted, ["contents: read", "actions: read"]);
  assert.match(job, /^ {4}cache-mode: read$/m);
  assert.doesNotMatch(MAP, /^\s*[a-z-]+:\s*write\b|write-all|id-token/m);
  assert.match(MAP, /^concurrency:\n {2}group: maintenance-verify-whole-map\n {2}cancel-in-progress: false$/m);
});

test("the gates run before the inputs, the plan before every model turn, and the plan before the key", () => {
  assert.match(step("Check the kill switch"), /^ {10}budget: "true"$/m);
  assert.match(step("Check who started the run"), /^ {10}require-kind: human$/m);
  assert.match(step("Check who started the run"), /^ {10}require-pr: "false"$/m);
  assert.match(step("Check who started the run"), /^ {10}denied-actor-ids: \$\{\{ vars\.AUTOMATION_LANES_APP_SENDER_ID \}\}$/m);
  const order = ["Check the kill switch", "Check upstream status", "Check who started the run", "Check the run may spend", "Check the inputs", "Resolve the driver's model", "Plan the pass", "Read the key's credit history", "Check the credential", "Find the baseline", "Log the API budget", "Start the key proxy", "Probe what head code can reach", "Check the probe", "Check out the default branch for the pass", "Verify the map"];
  const found = order.map((name) => at(name));
  assert.deepEqual([...found].sort((a, b) => a - b), found);
  const models = STEPS.flatMap((s, i) => (RUN_CLAUDE_CLI.test(s.block) ? [i] : []));
  assert.deepEqual(models, [at("Probe what head code can reach"), at("Verify the map")]);
  assert.doesNotMatch(step("Check the run may spend"), /continue-on-error/);
  assert.match(step("Check the inputs"), /^ {8}if: steps\.kill\.outputs\.proceed == 'true'$/m);
  assert.match(step("Plan the pass"), /^ {8}if: steps\.models\.outcome == 'success'$/m);
  assert.match(step("Read the key's credit history"), /^ {8}if: steps\.plan\.outcome == 'success'$/m);
});

test("a dispatcher input reaches a script only through env", () => {
  for (const s of STEPS) {
    const run = /^ {8}run: /m.test(s.block) ? s.block.slice(s.block.search(/^ {8}run: /m)) : "";
    assert.doesNotMatch(run, /\$\{\{\s*(?:inputs|github\.event\.inputs)\./, s.name);
  }
  const readers = STEPS.filter((s) => /\$\{\{\s*inputs\./.test(s.block)).map((s) => s.name);
  assert.deepEqual(readers, ["Check the inputs"]);
});

test("the real key reaches only the key proxy's start; both legs hold the client key", () => {
  const readers = STEPS.filter((s) => /secrets\.PR_VERIFY_CLAUDE_API_KEY(?! != '')/.test(s.block)).map((s) => s.name);
  assert.deepEqual(readers, ["Start the key proxy"]);
  assert.equal([...MAP.matchAll(/secrets\./g)].length, 2, "the start and the credential's presence check");
  for (const name of ["Probe what head code can reach", "Verify the map"]) {
    assert.equal(input(step(name), "api-key"), "${{ steps.proxy.outputs.client-key }}", name);
    assert.equal(input(step(name), "loopback-base-url"), "http://127.0.0.1:47101", name);
    assert.equal(input(step(name), "role"), "pr-verify", name);
  }
});

/** Runs one step's script with bash -eo pipefail, as GitHub runs it. */
function runStep(name, env, cwd) {
  const dir = tempDir("verify-map-step-");
  const output = path.join(dir, "output");
  const summary = path.join(dir, "summary");
  writeFileSync(output, "");
  writeFileSync(summary, "");
  const result = spawnSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", "-c", scriptOf(step(name))], {
    cwd: cwd ?? dir,
    encoding: "utf8",
    env: { PATH: process.env.PATH, HOME: dir, RUNNER_TEMP: dir, GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: summary, ...env },
  });
  const outputs = Object.fromEntries(readFileSync(output, "utf8").split("\n").filter(Boolean).map((line) => line.split(/=(.*)/s).slice(0, 2)));
  return { status: result.status, stdout: result.stdout, stderr: result.stderr, outputs, summary: readFileSync(summary, "utf8") };
}

test("the inputs step takes the defaults and refuses a cap, an id list or a run id it cannot use", () => {
  const dir = tempDir("verify-map-inputs-");
  const config = path.join(dir, "pr-pipeline.yaml");
  writeFileSync(config, "merge:\n  verify-capture:\n    app: demo\n");
  const check = (FEATURES, MAX_ENTRIES, BASELINE_RUN, CONFIG = config) => runStep("Check the inputs", { FEATURES, MAX_ENTRIES, BASELINE_RUN, CONFIG });
  assert.deepEqual(check("", "40", "").outputs, { app: "demo", features: "", "max-entries": "40", "baseline-run": "" });
  for (const ok of [["actionlint/setup,bugs", "100", "12345"], ["alpha/P2", "1", ""]]) assert.equal(check(...ok).status, 0, ok.join(" "));
  for (const bad of [["", "0", ""], ["", "101", ""], ["", "4a", ""], ["a;rm", "40", ""], ["-x", "40", ""], ["a,,b", "40", ""], ["", "40", "12a"], ["x".repeat(2001), "40", ""]]) {
    assert.equal(check(...bad).status, 1, bad.join(" ").slice(0, 40));
  }
  writeFileSync(path.join(dir, "no-app.yaml"), "merge: {}\n");
  const none = check("", "40", "", path.join(dir, "no-app.yaml"));
  assert.equal(none.status, 1);
  assert.match(none.summary, /gate: inputs: merge\.verify-capture\.app is unset/);
});

/** A .base with the real scripts and a fixture hub of two features, one of two parts. */
function planBase({ fileFindings = "none" } = {}) {
  const dir = tempDir("verify-map-plan-");
  const base = path.join(dir, ".base");
  const write = (rel, text) => {
    mkdirSync(path.dirname(path.join(base, rel)), { recursive: true });
    writeFileSync(path.join(base, rel), text);
  };
  mkdirSync(path.join(base, "plugins"), { recursive: true });
  symlinkSync(path.join(REPO, "plugins/testing"), path.join(base, "plugins/testing"));
  symlinkSync(path.join(REPO, ".github"), path.join(base, ".github"));
  write("docs/conventions/testing.yaml", `map_unit: part\nmap_entry_points: first\nfile_findings: ${fileFindings}\n`);
  write("docs/conventions/pr-pipeline.yaml", "merge:\n  verify-capture:\n    proxy:\n      driven-model: m-driven\n      token-cap: 111\n      driver-token-cap: 222\n");
  write(".claude/skills/control-demo/SKILL.md", "## Features\n\n- one | features/one/README.md | entry points: 1 | sources: a/**\n- two | features/two/README.md | entry points: 2 | sources: b/**\n");
  write(".claude/skills/control-demo/features/one/README.md", "## Parts\n\n- `a`: first.\n- `b`: second.\n\n## Entry points\n\n- slash | driven\n");
  write(".claude/skills/control-demo/features/two/README.md", "## Entry points\n\n- slash | driven\n- words | driven\n");
  return dir;
}
const PLAN_ENV = { APP: "demo", FEATURES: "", MAX_ENTRIES: "1", MODEL: "opus", EFFORT: "high", MAX_TURNS: "300", CONFIG: ".base/docs/conventions/pr-pipeline.yaml" };

test("the plan prints the entry count, the cap, both token caps, the driven model and the driver's turns", () => {
  const dir = planBase();
  const plan = runStep("Plan the pass", PLAN_ENV, dir);
  assert.equal(plan.status, 0, plan.stdout + plan.stderr);
  for (const line of [
    "- app: demo; map_unit: part; map_entry_points: first",
    "- entries: 3 listed, 1 driven, 2 not checked (cap 1); 4 entry-point rows",
    "- token-cap (driven session): 111; driver-token-cap (driver legs): 222",
    "- driven model: m-driven; driver: opus, effort high, max-turns 300",
  ]) {
    assert.ok(plan.summary.includes(`${line}\n`), line);
    assert.ok(plan.stdout.includes(line), `${line} in the log`);
  }
  assert.deepEqual(plan.outputs, { rows: "4" });
  const missing = runStep("Plan the pass", { ...PLAN_ENV, FEATURES: "two,nope" }, dir);
  assert.match(missing.summary, /- entries: 1 listed, 1 driven, 0 not checked \(cap 1\); 2 entry-point rows\n- not in the map: nope\n/);
});

test("the plan refuses file_findings new and an app with no control skill", () => {
  const filing = runStep("Plan the pass", PLAN_ENV, planBase({ fileFindings: "new" }));
  assert.equal(filing.status, 1);
  assert.match(filing.summary, /gate: plan: file_findings is new/);
  const noHub = runStep("Plan the pass", { ...PLAN_ENV, APP: "other" }, planBase());
  assert.equal(noHub.status, 1);
  assert.match(noHub.summary, /gate: plan: main has no project control skill control-other/);
});

/** A stub gh that answers `gh api <route>` from a file per route, and fails any other route. */
function stubGh(routes) {
  const dir = tempDir("verify-map-gh-");
  const answers = path.join(dir, "answers");
  mkdirSync(answers);
  for (const [route, body] of Object.entries(routes)) writeFileSync(path.join(answers, route.replace(/[/?=&]/g, "_")), JSON.stringify(body));
  mkdirSync(path.join(dir, "bin"));
  writeFileSync(path.join(dir, "bin/gh"), `#!/usr/bin/env bash\nf="${answers}/$(printf %s "$2" | tr '/?=&' '____')"\n[ "$1" = api ] && [ -f "$f" ] && cat "$f"\n`, { mode: 0o755 });
  return path.join(dir, "bin");
}
const WORKFLOW = ".github/workflows/maintenance-verify-whole-map.yml";
const run = (id, over = {}) => ({ id, path: WORKFLOW, head_branch: "main", event: "workflow_dispatch", conclusion: "success", head_repository: { full_name: "o/r" }, ...over });
const artifacts = (...expired) => ({ artifacts: expired.map((e) => ({ name: "map-findings", expired: e })) });
const LIST = "repos/o/r/actions/workflows/maintenance-verify-whole-map.yml/runs?branch=main&event=workflow_dispatch&status=success&per_page=20";
function findBaseline(routes, BASELINE_RUN = "") {
  const bin = stubGh(routes);
  return runStep("Find the baseline", { PATH: `${bin}:${process.env.PATH}`, GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "999", BASELINE_RUN, WORKFLOW, BRANCH: "main", TRUSTED: "/nonexistent" });
}

test("with no run named, the baseline is the newest earlier pass with an unexpired map-findings", () => {
  const routes = {
    [LIST]: { workflow_runs: [run(999), run(40, { head_repository: { full_name: "fork/r" } }), run(30), run(20), run(10)] },
    "repos/o/r/actions/runs/40/artifacts?name=map-findings": artifacts(false),
    "repos/o/r/actions/runs/30/artifacts?name=map-findings": artifacts(),
    "repos/o/r/actions/runs/20/artifacts?name=map-findings": artifacts(true),
    "repos/o/r/actions/runs/10/artifacts?name=map-findings": artifacts(false),
  };
  const found = findBaseline(routes);
  assert.equal(found.status, 0, found.stdout);
  assert.deepEqual(found.outputs, { "run-id": "10" });
  const none = findBaseline({ ...routes, "repos/o/r/actions/runs/10/artifacts?name=map-findings": artifacts(true) });
  assert.equal(none.status, 0);
  assert.deepEqual(none.outputs, {});
  assert.match(none.stdout, /runs with no baseline/);
});

test("a named run must be a successful dispatched pass on the default branch with an unexpired map-findings", () => {
  const routes = (over, kept = [false]) => ({ "repos/o/r/actions/runs/7": run(7, over), "repos/o/r/actions/runs/7/artifacts?name=map-findings": artifacts(...kept) });
  assert.deepEqual(findBaseline(routes({}), "7").outputs, { "run-id": "7" });
  for (const [why, over, kept] of [
    ["another workflow", { path: ".github/workflows/pr-verify-capture.yml" }, [false]],
    ["another branch", { head_branch: "feature" }, [false]],
    ["a failed run", { conclusion: "failure" }, [false]],
    ["another event", { event: "workflow_run" }, [false]],
    ["a fork's run", { head_repository: { full_name: "fork/r" } }, [false]],
    ["an expired artifact", {}, [true]],
    ["no artifact", {}, []],
  ]) {
    const result = findBaseline(routes(over, kept), "7");
    assert.equal(result.status, 1, why);
    assert.deepEqual(result.outputs, {}, why);
  }
});

test("the prompt names the map arguments, with the features and the baseline only when given", () => {
  const prompt = (env) => {
    const dir = tempDir("verify-map-prompt-");
    const file = path.join(dir, "prompt.md");
    const result = runStep("Write the map prompt and schema", { APP: "demo", FEATURES: "", MAX_ENTRIES: "40", BASELINE: "skipped", WORKDIR: "success", PROMPT_FILE: file, SCHEMA_FILE: path.join(dir, "schema.json"), GITHUB_WORKSPACE: "/ws", ...env });
    assert.equal(result.status, 0);
    return readFileSync(file, "utf8");
  };
  assert.match(prompt({}), /^ {4}map --unattended app=demo trusted-root=\/ws\/\.base max_entries=40$/m);
  assert.match(prompt({ FEATURES: "a,b/c", BASELINE: "success" }), /^ {4}map --unattended app=demo trusted-root=\/ws\/\.base max_entries=40 features=a,b\/c baseline=\/ws\/map-baseline\/findings\.json$/m);
  assert.match(prompt({}), /Its run directory is\n\/ws\/capture-run: write findings\.json/);
});

test("the driver allows the map scope's commands and none of the capture's diff, match or checkout edits", () => {
  const drive = step("Verify the map");
  const allowed = list(drive, "allowed-tools");
  const ws = "${{ github.workspace }}";
  const compare = `${ws}/.base/plugins/testing/skills/run-e2e/scripts/findings-compare.sh`;
  for (const rule of [
    `Bash(bash ${ws}/.base/plugins/testing/scripts/resolve-config.sh map *)`,
    `Bash(bash ${ws}/.base/plugins/testing/skills/run-e2e/scripts/finding-id.sh *)`,
    `Bash(bash ${compare} ${ws}/capture-run/findings.json)`,
    `Bash(bash ${compare} --baseline ${ws}/map-baseline/findings.json ${ws}/capture-run/findings.json)`,
    `Bash(bash ${compare} ${ws}/map-baseline/findings.json)`,
    "Bash(date +%s)",
    `Bash(git -C ${ws}/head rev-parse HEAD)`,
    `Read(/${ws}/map-baseline/**)`,
    "Skill(testing:run-e2e *)",
    "Skill(app-control:drive *)",
  ]) {
    assert.ok(allowed.includes(rule), rule);
  }
  assert.deepEqual(allowed.filter((r) => r.includes("findings-compare.sh") && r.endsWith("*)")), [], "the compare script runs only on its exact paths");
  assert.deepEqual(allowed.filter((r) => /diff --name-only|affected_features\.py|^Bash\(bash \*|^Bash\(node \*/.test(r)), []);
  assert.deepEqual(allowed.filter((r) => r.startsWith("Edit(")), [`Edit(/${ws}/capture-run/**)`]);
  assert.ok(!allowed.includes("Bash"));
  const denied = list(drive, "disallowed-tools");
  for (const rule of [`Edit(/${ws}/head/**)`, `Edit(/${ws}/map-baseline/**)`, `Edit(/${ws}/.base/**)`, "Read(~/.claude/**)", "WebFetch", "mcp__*"]) assert.ok(denied.includes(rule), rule);
  assert.equal(input(drive, "permission-mode"), "dontAsk");
  assert.equal(input(drive, "model"), "${{ steps.models.outputs.model }}");
  assert.equal(input(drive, "max-turns"), "${{ steps.models.outputs.max-turns }}");
  assert.equal(input(step("Resolve the driver's model"), "model-route"), "verify-map");
});

test("the job, the driver step and its leg fit inside one another and under the hosted limit", () => {
  const minutes = (text, indent) => Number(new RegExp(`^ {${indent}}timeout-minutes: (\\d+)$`, "m").exec(text)[1]);
  const job = minutes(jobIn(MAP, JOB).split(/\n {4}steps:\n/)[0], 4);
  const drive = minutes(step("Verify the map"), 8);
  const leg = Number(/^ {10}leg-timeout-minutes: "(\d+)"$/m.exec(step("Verify the map"))[1]);
  assert.ok(leg < drive && drive < job && job <= 360, `${leg} < ${drive} < ${job} <= 360`);
});

test("findings.json uploads alone for 90 days and the evidence for 7, each behind its own scan", () => {
  const uploads = STEPS.filter((s) => /uses: actions\/upload-artifact@/.test(s.block) && !/key-credit-/.test(s.block));
  assert.deepEqual(
    uploads.map((s) => [input(s.block, "name"), input(s.block, "path"), input(s.block, "retention-days")]),
    [
      ["map-findings", "${{ runner.temp }}/map-findings", "90"],
      ["map-evidence", "${{ runner.temp }}/map-evidence", "7"],
    ],
  );
  for (const [upload, scan, id] of [["Upload the findings", "Scan the findings for credentials", "scan-findings"], ["Upload the evidence", "Scan the evidence for credentials", "scan-evidence"]]) {
    assert.equal(input(step(scan), "path"), input(step(upload), "path"));
    assert.match(step(upload), new RegExp(`&& steps\\.${id}\\.outputs\\.clean == 'true'$`, "m"));
    assert.ok(at(scan) < at(upload));
  }
  const collect = scriptOf(step("Collect the pass"));
  assert.match(collect, /index\("findings\.json"\) != null[\s\S]*bash \/opt\/ccd\/findings-compare\.sh "\$findings"[\s\S]*cp -P -- "\$findings" "\$FINDINGS\/findings\.json"/);
  assert.match(collect, /\.capture\.status[^\n]*= blocked \]; then\n\s*echo "reason=the map skill reported the pass blocked[^\n]*" >>"\$GITHUB_OUTPUT"/);
  assert.match(step("Report the pass"), /BLOCKED: \$\{\{ steps\.collect\.outputs\.reason \|\| steps\.blocked\.outputs\.reason \}\}[\s\S]*if \[ -n "\$BLOCKED" \]; then[\s\S]*exit 1/);
  assert.ok(at("Install the findings checker") < at("Isolate the runner"));
  assert.match(step("Install the findings checker"), /sudo install -m 0755 -o root -g root \.base\/plugins\/testing\/skills\/run-e2e\/scripts\/findings-compare\.sh \/opt\/ccd\/findings-compare\.sh/);
  assert.equal(input(step("Download the baseline"), "name"), "map-findings");
});
