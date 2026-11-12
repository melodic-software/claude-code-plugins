import assert from "node:assert/strict";
import { execFile, execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { promisify } from "node:util";

import {
  alreadyProcessed,
  branchFor,
  changesHoldPath,
  checkRawLog,
  commitNetTree,
  fetchSynthetic,
  fileReleaseHandoffs,
  handoffMarker,
  holdPathBranch,
  KEY,
  loadHoldPaths,
  marksDone,
  netRawDiff,
  newestRelease,
  publishText,
  readNetChanges,
  readHoldPaths,
  readPlan,
  readSynthetic,
  refuseBinary,
  releaseIssue,
  releaseMarker,
  releasesFromStatus,
  renderItems,
  scheduledCandidates,
  STARTED_ARTIFACT,
  startedInWindow,
  stoppedPlanText,
  SYNTHETIC_MESSAGE,
  syntheticBundle,
  validatePlan,
} from "./upstream-apply-changelog.mjs";

const BASE = "a".repeat(40);
const HEAD = "b".repeat(40);
const plan = (over = {}) => ({
  schema: "changelog-ci-plan/1",
  status: "planned",
  range: "2.1.300..2.1.300",
  base_sha: BASE,
  branches: [
    {
      plugin: "hooks-kit",
      branch: "changelog/hooks-kit/v2.1.300",
      base_sha: BASE,
      head_sha: HEAD,
      pr: { title: "chore(hooks-kit): address Claude Code v2.1.300 changelog", body: "Refs: #7407" },
    },
  ],
  handoffs: [{ key: "changelog:2.1.300..2.1.300:adopt:plugins/x/a.sh", title: "t", body: "b" }],
  ...over,
});
const ctx = { release: "2.1.300", baseSha: BASE };
const execFileAsync = promisify(execFile);

test("the newest release is the highest version, skipping drafts, prereleases and other tags", () => {
  const releases = [
    { tag_name: "v2.1.99" },
    { tag_name: "v2.1.300" },
    { tag_name: "v2.1.301", prerelease: true },
    { tag_name: "v9.9.9", draft: true },
    { tag_name: "nightly" },
  ];
  assert.equal(newestRelease(releases), "2.1.300");
  assert.equal(newestRelease([]), "");
});

test("the per-day cap counts only start records from the last 24 hours", () => {
  const now = Date.parse("2026-11-02T12:00:00Z");
  const artifacts = [
    { name: "upstream-apply-changelog-started", created_at: "2026-11-02T01:00:00Z" },
    { name: "upstream-apply-changelog-started", created_at: "2026-11-01T11:00:00Z" },
    { name: "upstream-apply-changelog-done-2.1.300", created_at: "2026-11-02T02:00:00Z" },
  ];
  assert.equal(startedInWindow(artifacts, now), 1);
});

test("a valid plan passes and a stopped plan keeps its handoffs and publishes no branch", () => {
  assert.equal(validatePlan(plan(), ctx).branches.length, 1);
  // ci-mode.md: cap exceeded is status stopped with one docs-conformance handoff.
  const conformance = { key: "changelog:2.1.300..2.1.300:docs-conformance:plugins/harness-ops/skills/changelog/SKILL.md", title: "t", body: "b" };
  assert.deepEqual(validatePlan(plan({ status: "stopped", stop_reason: "cap-exceeded", handoffs: [conformance] }), ctx), {
    status: "stopped",
    stop_reason: "cap-exceeded",
    branches: [],
    handoffs: [conformance],
  });
  assert.equal(validatePlan(plan({ status: "stopped", stop_reason: "range-not-computed", handoffs: [] }), ctx).stop_reason, "range-not-computed");
  assert.equal(validatePlan(plan(), ctx).stop_reason, null);
  assert.throws(
    () => validatePlan(plan({ status: "stopped", stop_reason: "cap-exceeded", handoffs: [{ ...conformance, key: "changelog:2.1.1..2.1.1:docs-conformance:x" }] }), ctx),
    /handoffs\[0\]\.key/,
  );
  assert.throws(() => validatePlan(plan({ status: "stopped", stop_reason: "cap-exceeded", range: "2.1.299..2.1.299" }), ctx), /range/);
});

test("a stopped plan without a known stop_reason is refused, naming the field and not the value", () => {
  const SECRET = "zzPLANTEDzz";
  for (const stop_reason of [undefined, null, "", SECRET]) {
    assert.throws(
      () => validatePlan(plan({ status: "stopped", stop_reason }), ctx),
      (e) => /stop_reason/.test(e.message) && !e.message.includes(SECRET),
    );
  }
});

test("a plan for another release, base or branch name is refused", () => {
  assert.throws(() => validatePlan(plan({ range: "2.1.299..2.1.299" }), ctx), /range/);
  assert.throws(() => validatePlan(plan({ base_sha: HEAD }), ctx), /base_sha/);
  const renamed = plan();
  renamed.branches[0].branch = "main";
  assert.throws(() => validatePlan(renamed, ctx), /branches\[0\]\.branch is not changelog\/<plugin>\/v<release>/);
  const titled = plan();
  titled.branches[0].pr.title = "feat(other): x";
  assert.throws(() => validatePlan(titled, ctx), /branches\[0\]\.pr\.title/);
  assert.throws(() => validatePlan(plan({ handoffs: [{ key: "changelog:2.1.1..2.1.1:adopt:x", title: "t", body: "b" }] }), ctx), /handoffs\[0\]\.key/);
  const empty = plan();
  empty.branches[0].head_sha = BASE;
  assert.throws(() => validatePlan(empty, ctx), /branches\[0\]\.head_sha/);
  assert.equal(branchFor("hooks-kit", "2.1.300"), "changelog/hooks-kit/v2.1.300");
});

test("a refusal names the field and index, never the plan's value", () => {
  const SECRET = "zzPLANTEDzz";
  const cases = [];
  const renamed = plan();
  renamed.branches[0].branch = SECRET;
  cases.push([renamed, /branches\[0\]\.branch/]);
  const twice = plan();
  twice.branches.push({ ...twice.branches[0], branch: SECRET });
  cases.push([twice, /branches\[1\]\.plugin/]);
  const titled = plan();
  titled.branches[0].pr.title = `chore(hooks-kit): ${SECRET}\n`;
  cases.push([titled, /branches\[0\]\.pr\.title/]);
  const keyed = plan({ handoffs: [{ key: `changelog:2.1.300..2.1.300:adopt:${SECRET}`, title: "t", body: "b" }, { key: `changelog:2.1.300..2.1.300:adopt:${SECRET}`, title: "t", body: "b" }] });
  cases.push([keyed, /handoffs\[1\]\.key/]);
  const handTitled = plan({ handoffs: [{ key: "changelog:2.1.300..2.1.300:adopt:x", title: `${SECRET}\n`, body: "b" }] });
  cases.push([handTitled, /handoffs\[0\]\.title/]);
  for (const [p, want] of cases) {
    assert.throws(
      () => validatePlan(p, ctx),
      (e) => want.test(e.message) && !e.message.includes(SECRET),
    );
  }
  assert.throws(() => readPlan(`{"schema": ${SECRET}}`, ctx), (e) => /not valid JSON/.test(e.message) && !e.message.includes(SECRET));
  assert.equal(readPlan(JSON.stringify(plan()), ctx).branches.length, 1);
  assert.throws(
    () => checkRawLog(`:100644 100644 1 2 M\tplugins/hooks-kit/a\n:100644 100644 1 2 M\t${SECRET}`, "hooks-kit", 3),
    (e) => /branches\[3\] raw line 2/.test(e.message) && !e.message.includes(SECRET),
  );
});

test("a malformed key or plugin names the part that failed and none of its text", () => {
  const LEAK = "sk-ant-test\n::set-output name=a::b";
  const refuse = (key) => () => validatePlan(plan({ handoffs: [{ key, title: "t", body: "b" }] }), ctx);
  const cases = [
    [`changelog:2.1.299..2.1.299:adopt:${LEAK}`, "does not start with changelog:2.1.300..2.1.300:"],
    [`changelog:2.1.300..2.1.300:Adopt-${LEAK}:x`, "has a lens that is empty or has characters outside [a-z-]"],
    ["changelog:2.1.300..2.1.300::x", "has a lens that is empty or has characters outside [a-z-]"],
    ["changelog:2.1.300..2.1.300:adopt:", "has an empty surface"],
    ["changelog:2.1.300..2.1.300:adopt", "has an empty surface"],
    [`changelog:2.1.300..2.1.300:adopt:${"s".repeat(201)}`, "has a surface over 200 characters"],
    [`changelog:2.1.300..2.1.300:adopt:${LEAK}`, "has a surface with characters outside [A-Za-z0-9_./-]"],
  ];
  for (const [key, part] of cases) {
    assert.throws(refuse(key), { message: `ci-plan.json: handoffs[0].key ${part} (${key.length} characters)` }, part);
  }
  assert.throws(refuse(undefined), { message: "ci-plan.json: handoffs[0].key is not a string" });
  const plugins = [
    [`Hooks ${LEAK}`, "does not start with [a-z0-9]"],
    [`hooks-${LEAK}`, "has characters outside [a-z0-9-]"],
    ["h".repeat(65), "is over 64 characters"],
  ];
  for (const [name, part] of plugins) {
    const p = plan();
    p.branches[0].plugin = name;
    assert.throws(() => validatePlan(p, ctx), { message: `ci-plan.json: branches[0].plugin ${part} (${name.length} characters)` }, part);
  }
  const blank = plan();
  blank.branches[0].plugin = "";
  assert.throws(() => validatePlan(blank, ctx), { message: "ci-plan.json: branches[0].plugin is empty" });
});

test("the scan job's error line names the failed key part and prints no model text", () => {
  const dir = mkdtempSync(join(tmpdir(), "upstream-apply-changelog-key-"));
  try {
    const key = "changelog:2.1.300..2.1.300:adopt:sk-ant-test\n::set-output name=a::b%0A";
    writeFileSync(join(dir, "plan.json"), JSON.stringify(plan({ handoffs: [{ key, title: "t", body: "b" }] })));
    const run = () =>
      execFileSync(process.execPath, [new URL("./upstream-apply-changelog.mjs", import.meta.url).pathname, "scan"], {
        env: { PATH: process.env.PATH, IN: dir, RELEASE: "2.1.300", BASE_SHA: BASE, REPO_DIR: dir },
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      });
    assert.throws(run, (e) => {
      assert.equal(e.stdout, `::error::ci-plan.json: handoffs[0].key has a surface with characters outside [A-Za-z0-9_./-] (${key.length} characters)\n`);
      assert.ok(!e.stdout.includes("sk-ant-test") && !e.stdout.includes("::set-output") && !e.stderr.includes("sk-ant-test"), "no key text reaches the log");
      return true;
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("ci-mode.md states the key grammar the validator enforces, with a valid example", () => {
  const doc = readFileSync(new URL("../../../plugins/harness-ops/skills/changelog/context/ci-mode.md", import.meta.url), "utf8").replace(/\s+/g, " ");
  const stated = [...doc.matchAll(/`(\^changelog:[^`]*)`/g)].map((m) => m[1]);
  assert.deepEqual(stated, [KEY.source], "ci-mode.md states the key grammar once, equal to KEY");
  assert.match(doc, /both sides of `\.\.` are the release being applied/, "ci-mode.md says the release fills both sides of ..");
  const example = /for example `(changelog:[^`]+)`/.exec(doc)?.[1] ?? "";
  const release = /^changelog:([0-9.]+)\.\./.exec(example)?.[1];
  assert.equal(validatePlan(plan({ range: `${release}..${release}`, branches: [], handoffs: [{ key: example, title: "t", body: "b" }] }), { release, baseSha: BASE }).handoffs[0].key, example, "the example key passes the validator");
});

test("ci-mode.md keys native drift per item: its example passes, and two items on one surface keep distinct keys", () => {
  const doc = readFileSync(new URL("../../../plugins/harness-ops/skills/changelog/context/ci-mode.md", import.meta.url), "utf8").replace(/\s+/g, " ");
  const [, drift, example] = /drift key `(native-drift:[^`]+)` gives `(changelog:[^`]+)`/.exec(doc) ?? [];
  assert.equal(drift, "native-drift:recheck:code-review:review:code-reviewer@agent", "ci-mode.md gives a native-drift example");
  assert.equal(example, "changelog:2.1.319..2.1.319:native-drift:recheck/code-review/review-code-reviewer-agent");
  // The stated rule: <kind>/<surface>/<component>, each character outside [A-Za-z0-9_./-] made `-`.
  const planKey = (kind, surface, component) => `changelog:2.1.300..2.1.300:native-drift:${`${kind}/${surface}/${component}`.replace(/[^A-Za-z0-9_./-]/g, "-")}`;
  const keys = [planKey("candidate", "code-review", "review:code-reviewer@agent"), planKey("candidate", "code-review", "code-tidying:simplify")];
  assert.deepEqual(keys, [
    "changelog:2.1.300..2.1.300:native-drift:candidate/code-review/review-code-reviewer-agent",
    "changelog:2.1.300..2.1.300:native-drift:candidate/code-review/code-tidying-simplify",
  ]);
  const handoffs = keys.map((key) => ({ key, kind: "native-drift", title: "t", body: "b" }));
  assert.equal(validatePlan(plan({ handoffs }), ctx).handoffs.length, 2, "both keys pass and neither repeats the other");
});

test("the publish text holds every pull request and issue string publish can post, decoded", async () => {
  const p = plan({
    handoffs: [
      { key: "changelog:2.1.300..2.1.300:adopt:a", kind: "adopt", title: "first \"quoted\"", body: "line one\nline two" },
      { key: "changelog:2.1.300..2.1.300:adopt:b", kind: "adopt", title: "second", body: "z".repeat(50000) },
      { key: "changelog:2.1.300..2.1.300:adopt:c", kind: "adopt", title: "third", body: "y".repeat(50000) },
    ],
  });
  p.branches[0].pr.body = "Refs: #7407\nwith \"quotes\" and a tab\t.";
  const v = validatePlan(p, ctx);
  const text = publishText(v, "2.1.300");
  assert.ok(text.includes(v.branches[0].pr.title));
  assert.ok(text.includes("with \"quotes\" and a tab\t."));
  const f = issueApi();
  await fileReleaseHandoffs({ repo: REPO, release: "2.1.300", handoffs: v.handoffs, api: f.api });
  const posted = f.writes()[0].body;
  assert.deepEqual(posted, releaseIssue("2.1.300", v.handoffs));
  assert.equal(posted.type, "Task");
  assert.ok(text.includes(posted.title) && text.includes(posted.body));
  assert.ok(posted.body.includes("truncated proportionally"));
  assert.ok(text.includes(renderItems(v.handoffs, Number.POSITIVE_INFINITY)));
  assert.equal(publishText(validatePlan(plan({ handoffs: [] }), ctx), "2.1.300").includes(releaseMarker("2.1.300")), false);
});

test("a stopped plan's publish text holds the issue it posts, stop line included, even with no handoffs", async () => {
  const v = validatePlan(plan({ status: "stopped", stop_reason: "cap-exceeded", handoffs: [] }), ctx);
  const f = issueApi();
  await fileReleaseHandoffs({ repo: REPO, release: "2.1.300", handoffs: v.handoffs, stop: v.stop_reason, api: f.api });
  const posted = f.writes()[0].body;
  const text = publishText(v, "2.1.300");
  assert.ok(text.includes(posted.title) && text.includes(posted.body));
  assert.ok(posted.body.includes("stop_reason `cap-exceeded`"));
});

test("only a deterministic stop marks the release done; range-not-computed is retried and posts nothing", () => {
  assert.equal(marksDone(null), true);
  assert.equal(marksDone("cap-exceeded"), true);
  assert.equal(marksDone("range-not-computed"), false);
  const v = validatePlan(plan({ status: "stopped", stop_reason: "range-not-computed", handoffs: [] }), ctx);
  assert.equal(publishText(v, "2.1.300"), "\n");
});

test("the done marker uploads only when publish says the release is done", () => {
  const wf = readFileSync(new URL("../../workflows/upstream-apply-changelog.yml", import.meta.url), "utf8");
  const step = wf.split(/\n(?= {6}- name: )/).filter((s) => s.includes("name: upstream-apply-changelog-done-"));
  assert.equal(step.length, 1);
  assert.match(step[0], /\n {8}if: steps\.publish\.outcome == 'success' && steps\.publish\.outputs\.done == 'true'\n/);
});

// ci-workflows select-model-credential's start call (check-key-credit's
// gate.cjs at the pinned SHA): next-leg is `subscription` only while the
// newest marker named by its `marker` output,
// `key-credit-stop-<workflow file>-<key-job>`, is inside the window; the
// model job uploads that name after a credit-stop handoff.
// credential-legs.test.mjs holds every leg's start and credential to the
// expressions before the action.
const WORKFLOW = readFileSync(new URL("../../workflows/upstream-apply-changelog.yml", import.meta.url), "utf8");
const jobOf = (id) => {
  const match = new RegExp(`^ {2}${id}:\\n[\\s\\S]*?(?=^ {2}\\S|(?![\\s\\S]))`, "m").exec(WORKFLOW);
  assert.ok(match, id);
  return match[0];
};
const stepsOf = (id) => jobOf(id).split(/\n(?= {6}- name: )/).slice(1);
const stepIn = (id, name) => {
  const found = stepsOf(id).filter((s) => s.startsWith(`      - name: ${name}\n`));
  assert.equal(found.length, 1, name);
  return found[0];
};
const indexIn = (id, name) => stepsOf(id).findIndex((s) => s.startsWith(`      - name: ${name}\n`));
const ifOf = (text) => /^ {8}if: (.*)$/m.exec(text)?.[1];
const MARKER = "key-credit-stop-upstream-apply-changelog.yml-model";

// The scrub probe (#12836): capture-probe.mjs on run-claude-cli, on the release.
const PROBE_JOB = "scrub-probe";
const PROBE_STEP = "Probe what a Bash child can reach";
const CHECK_STEP = "Check the probe";

test("the scrub probe runs once per release the gate takes, on a read-only token, and nothing waits on it", () => {
  const job = jobOf(PROBE_JOB);
  assert.match(job, /^ {4}needs: gate$/m);
  assert.match(job, /^ {4}if: needs\.gate\.outputs\.proceed == 'true' && needs\.gate\.outputs\.next-leg != 'subscription' && github\.run_attempt == '1'$/m);
  assert.match(job, /^ {4}cache-mode: read$/m);
  assert.deepEqual(/^ {4}permissions:\n((?: {6}.*\n)+)/m.exec(job)[1].trim().split("\n").map((line) => line.trim().split(" #")[0]), ["contents: read"]);
  // Only the later probe legs wait on a probe; no publishing job does.
  const needers = [...WORKFLOW.matchAll(/^ {2}([a-z0-9-]+):\n(?: {4}name: .*\n)? {4}needs: (.*)$/gm)].filter(([, , list]) => list.includes(PROBE_JOB)).map(([, id]) => id);
  assert.deepEqual(needers, ["scrub-probe-subscription", "scrub-probe-fallback"]);
  for (const id of ["scan", "push-branches", "publish"]) assert.doesNotMatch(jobOf(id), /needs\.scrub-probe/, id);
});

test("the scrub probe runs on each credential a model leg may use, after the same handoffs", () => {
  const probe = (job) => stepIn(job, PROBE_STEP);
  assert.match(probe("scrub-probe"), /^ {10}api-key: \$\{\{ secrets\.ISSUE_LANE_CLAUDE_API_KEY \}\}$/m);
  assert.match(probe("scrub-probe-subscription"), /^ {10}subscription-token: \$\{\{ secrets\.ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN \}\}\n {10}fallback-ready: \$\{\{ steps\.credential\.outputs\.fallback-ready \}\}$/m);
  assert.match(probe("scrub-probe-fallback"), /^ {10}fallback-token: \$\{\{ secrets\.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN \}\}$/m);
  // Each leg's probe looks for its own credential's name.
  for (const [job, name] of [["scrub-probe", "ISSUE_LANE_CLAUDE_API_KEY"], ["scrub-probe-subscription", "ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN"], ["scrub-probe-fallback", "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN"]]) {
    assert.match(probe(job), new RegExp(`^ {10}CAPTURE_PROBE_EXTRA_NAMES: ${name}$`, "m"), job);
    assert.match(stepIn(job, CHECK_STEP), new RegExp(`^ {10}KEY_NAME: ${name}$`, "m"), job);
    assert.equal(ifOf(stepIn(job, CHECK_STEP)), "always() && steps.probe.outcome != 'skipped' && steps.probe.outputs.handoff != 'true'", job);
  }
  const folded = (job) => (/^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(jobOf(job))?.[1] ?? "").replace(/\s+/g, " ").trim();
  assert.match(folded("scrub-probe-subscription"), /\(needs\.scrub-probe\.outputs\.next-leg == 'subscription' \|\| needs\.gate\.outputs\.next-leg == 'subscription'\)/);
  assert.match(folded("scrub-probe-fallback"), /needs\.scrub-probe-subscription\.outputs\.next-leg == 'fallback'/);
});

test("the key reaches the probe's run-claude-cli step alone, and that step runs the release's CLI after isolation", () => {
  const job = jobOf(PROBE_JOB);
  // The probe's input, and the presence check that reads whether it is set.
  assert.deepEqual(job.match(/secrets\.[^\n]*/g), ["secrets.ISSUE_LANE_CLAUDE_API_KEY != '' }}", "secrets.ISSUE_LANE_CLAUDE_API_KEY }}"]);
  const probe = stepIn(PROBE_JOB, PROBE_STEP);
  assert.match(probe, /^ {8}uses: melodic-software\/ci-workflows\/\.github\/actions\/run-claude-cli@[0-9a-f]{40} /m);
  assert.match(probe, /^ {10}api-key: \$\{\{ secrets\.ISSUE_LANE_CLAUDE_API_KEY \}\}$/m);
  assert.match(probe, /^ {10}cli-version: \$\{\{ needs\.gate\.outputs\.release \}\}$/m);
  assert.match(probe, /^ {10}CAPTURE_PROBE_EXTRA_NAMES: ISSUE_LANE_CLAUDE_API_KEY$/m);
  assert.match(probe, /^ {10}permission-mode: dontAsk$/m);
  // A handoff ends the job green; the check carries every other failure.
  assert.match(probe, /^ {8}continue-on-error: true$/m);
  assert.deepEqual(/^ {10}allowed-tools: \|\n((?: {12}.*\n)+)/m.exec(probe)[1].trim().split("\n").map((line) => line.trim()), ["Bash(node .base/.github/scripts/pr-verify/capture-probe.mjs)"]);
  for (const rule of ["Read(//proc/**)", "Read(/${{ runner.temp }}/**)", "Edit", "Write", "Agent"]) {
    assert.ok(probe.includes(`            ${rule}\n`), rule);
  }
  const isolate = stepIn(PROBE_JOB, "Isolate the runner");
  assert.match(isolate, /^ {10}install-subprocess-isolation: "true"$/m);
  const at = ["Check the kill switch", "Apply the Claude managed settings", "Isolate the runner", PROBE_STEP, CHECK_STEP].map((name) => indexIn(PROBE_JOB, name));
  assert.deepEqual([...at].sort((a, b) => a - b), at);
  assert.match(stepIn(PROBE_JOB, "Check out the default branch tip"), /^ {10}persist-credentials: false$/m);
  // Every step after the kill switch waits on it, through the resolver.
  assert.equal(ifOf(stepIn(PROBE_JOB, "Resolve the model")), "steps.kill.outputs.proceed == 'true'");
  for (const name of ["Apply the Claude managed settings", "Isolate the runner", "Write the probe prompt"]) {
    assert.equal(ifOf(stepIn(PROBE_JOB, name)), "steps.models.outcome == 'success' && steps.models.outputs.applies == 'true'", name);
  }
  assert.equal(ifOf(stepIn(PROBE_JOB, PROBE_STEP)), "steps.models.outcome == 'success' && steps.models.outputs.applies == 'true' && steps.credential.outputs.present == 'true'");
  // A leg the kill switch skipped or that handed off has nothing to check; a failed one does.
  assert.equal(ifOf(stepIn(PROBE_JOB, CHECK_STEP)), "always() && steps.probe.outcome != 'skipped' && steps.probe.outputs.handoff != 'true'");
});

test("the check names the release and hit names on every failure, never a value, and a pass records the release", (t) => {
  const run = stepIn(PROBE_JOB, CHECK_STEP).split(/^ {8}run: \|\n/m)[1].replace(/^ {10}/gm, "");
  const dir = mkdtempSync(join(tmpdir(), "scrub-probe-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  // Where the step runs: the real script at .base, as the job's checkout has it.
  const scripts = join(dir, ".base/.github/scripts/pr-verify");
  mkdirSync(scripts, { recursive: true });
  writeFileSync(join(scripts, "capture-probe.mjs"), readFileSync(new URL("../pr-verify/capture-probe.mjs", import.meta.url)));
  const RESULT = join(dir, "capture-probe.json");
  const EXECUTION_FILE = join(dir, "execution.json");
  const GITHUB_STEP_SUMMARY = join(dir, "summary");
  const PROMPT_FILE = "/runner/_temp/probe.md";
  const SECRET = `${"sk-ant-"}api03-${"Q".repeat(40)}`;
  const leg = (result) => {
    const use = (id, file) => ({ type: "assistant", message: { content: [{ type: "tool_use", id, name: "Read", input: { file_path: file } }] } });
    const out = (id) => ({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: id, is_error: result === "refused", content: result === "refused" ? "denied" : SECRET }] } });
    writeFileSync(EXECUTION_FILE, JSON.stringify([use("a", "/proc/self/environ"), out("a"), use("b", PROMPT_FILE), out("b")]));
  };
  const check = ({ result, env = {} }) => {
    rmSync(RESULT, { force: true });
    if (result !== undefined) writeFileSync(RESULT, JSON.stringify(result));
    writeFileSync(GITHUB_STEP_SUMMARY, "");
    try {
      const stdout = execFileSync("bash", ["-e", "-c", run], {
        cwd: dir,
        encoding: "utf8",
        env: { PATH: process.env.PATH, KEY_NAME: "ISSUE_LANE_CLAUDE_API_KEY", RELEASE: "2.1.320", LEG_OUTCOME: "success", LEG_CLASS: "", CLI_VERSION: "2.1.320", RESULT, EXECUTION_FILE, PROMPT_FILE, GITHUB_STEP_SUMMARY, ...env },
      });
      return { status: 0, stdout };
    } catch (error) {
      return { status: error.status, stdout: error.stdout };
    }
  };
  const clean = { clean: true, canary: true, hits: [], names: ["GITHUB_TOKEN", "ISSUE_LANE_CLAUDE_API_KEY"] };
  const fails = (outcome, why) => {
    assert.equal(outcome.status, 1, why);
    assert.match(outcome.stdout, /^::error::Claude Code 2\.1\.320: /m, why);
    assert.doesNotMatch(outcome.stdout, /::notice::/, why);
    assert.doesNotMatch(outcome.stdout, /sk-ant-/, why);
    assert.equal(readFileSync(GITHUB_STEP_SUMMARY, "utf8"), "", why);
  };

  leg("refused");
  const pass = check({ result: clean });
  assert.equal(pass.status, 0, pass.stdout);
  assert.match(pass.stdout, /^::notice::Claude Code 2\.1\.320: the subprocess scrub probe passed$/m);
  assert.match(readFileSync(GITHUB_STEP_SUMMARY, "utf8"), /Claude Code 2\.1\.320: the subprocess scrub probe passed/);

  const hit = check({ result: { clean: false, canary: true, names: clean.names, hits: [{ where: "process 7", name: "ISSUE_LANE_CLAUDE_API_KEY" }, { where: "process 8", name: "ISSUE_LANE_CLAUDE_API_KEY" }, { where: "own environment", name: "GITHUB_TOKEN" }] } });
  fails(hit, "a hit");
  assert.match(hit.stdout, /\(GITHUB_TOKEN, ISSUE_LANE_CLAUDE_API_KEY\)/);
  assert.doesNotMatch(hit.stdout, /process 7/);

  fails(check({ result: { ...clean, clean: false, canary: false } }), "a missed canary");
  fails(check({ result: { ...clean, names: ["GITHUB_TOKEN"] } }), "the added name never arrived");
  fails(check({}), "no result");
  assert.match(check({ result: clean, env: { LEG_OUTCOME: "failure", LEG_CLASS: "install-failed" } }).stdout, /install-failed/);
  fails(check({ result: clean, env: { LEG_OUTCOME: "failure", LEG_CLASS: "install-failed" } }), "a failed leg, even with a clean result on disk");
  fails(check({ result: clean, env: { CLI_VERSION: "2.1.319" } }), "another CLI");
  leg("read");
  const read = check({ result: clean });
  fails(read, "a Read that came back");
  assert.match(read.stdout, /file tools were not refused/);
  writeFileSync(EXECUTION_FILE, "[]");
  const untried = check({ result: clean });
  fails(untried, "a leg that made no Read call");
  assert.match(untried.stdout, /^::error::Claude Code 2\.1\.320: the subprocess scrub probe failed: the leg made no Read call on \/proc or the runner's temp directory, so its file-tool fence was not tested$/m);
});

const SELECT = /^ {8}uses: melodic-software\/ci-workflows\/\.github\/actions\/select-model-credential@[0-9a-f]{40} # \S/m;

test("the gate reads the key's credit history through select-model-credential's start call once a release is picked", () => {
  assert.doesNotMatch(WORKFLOW, /check-key-credit@/);
  const gate = stepIn("gate", "Read the key's credit history");
  assert.match(gate, /^ {8}id: credit$/m);
  assert.equal(ifOf(gate), "steps.gate.outputs.proceed == 'true'");
  assert.match(gate, /^ {8}continue-on-error: true$/m);
  assert.match(gate, SELECT);
  assert.doesNotMatch(gate, /secrets\./);
  assert.match(gate, /^ {10}leg: start$/m);
  assert.match(gate, /^ {10}key-job: model$/m);
  // The window's default lives only in the action: an empty variable is its 1 hour.
  assert.match(gate, /^ {10}window-hours: \$\{\{ vars\.KEY_CREDIT_WINDOW_HOURS \}\}$/m);
  assert.match(gate, /^ {10}reset-at: \$\{\{ vars\.KEY_CREDIT_RESET_AT \}\}$/m);
  assert.match(gate, /^ {10}probe-minutes: "0"$/m);
  assert.ok(indexIn("gate", "Pick the release") < indexIn("gate", "Read the key's credit history"));
  assert.ok(indexIn("gate", "Report the credit skip") > indexIn("gate", "Read the key's credit history"));
  assert.match(jobOf("gate"), /^ {6}actions: read\b/m);
  // Every credential call is the same pinned action.
  const uses = [...WORKFLOW.matchAll(/^ {8}uses: (melodic-software\/ci-workflows\/\.github\/actions\/select-model-credential@.*)$/gm)].map((m) => m[1]);
  assert.equal(new Set(uses).size, 1, uses.join("\n"));
});

test("a skipped key runs no key leg, records no start in the gate, and names the run whose credit stop holds it off", (t) => {
  assert.ok(!jobOf("gate").includes("upstream-apply-changelog-started"));
  assert.match(jobOf("gate"), /^ {6}next-leg: \$\{\{ steps\.credit\.outputs\.next-leg \}\}$/m);
  assert.match(jobOf("gate"), /^ {6}credit-marker: \$\{\{ steps\.credit\.outputs\.marker \}\}$/m);
  assert.match(jobOf("model"), /^ {4}if: needs\.gate\.outputs\.proceed == 'true' && needs\.gate\.outputs\.next-leg != 'subscription' && github\.run_attempt == '1'$/m);
  const report = stepIn("gate", "Report the credit skip");
  assert.equal(ifOf(report), "steps.credit.outputs.next-leg == 'subscription'");
  assert.equal(ifOf(stepIn("gate", "Report the skipped key leg")), "steps.credit.outputs.next-leg == 'subscription'");
  assert.match(report, /ORIGIN_RUN: \$\{\{ steps\.credit\.outputs\.origin-run \}\}/);
  const run = report.split(/^ {8}run: \|\n/m)[1].replace(/^ {10}/gm, "");
  const dir = mkdtempSync(join(tmpdir(), "credit-skip-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const summary = join(dir, "summary.md");
  const out = execFileSync("bash", ["-e", "-c", run], {
    encoding: "utf8",
    env: { PATH: process.env.PATH, ORIGIN_RUN: "41760968895", RELEASE: "2.1.318", GITHUB_SERVER_URL: "https://github.com", GITHUB_REPOSITORY: "o/r", GITHUB_STEP_SUMMARY: summary },
  });
  assert.match(out, /^::notice::ISSUE_LANE_CLAUDE_API_KEY hit a credit stop in run https:\/\/github\.com\/o\/r\/actions\/runs\/41760968895; release 2\.1\.318 runs on the subscription token/m);
  assert.equal(readFileSync(summary, "utf8"), out.replace(/^::notice::/, ""));
});

test("the model job uploads the gate's marker only after the leg's credit-stop handoff, scanned, for one day", () => {
  const write = stepIn("model", "Write the key's credit-stop marker");
  assert.match(write, /^ {8}id: credit-marker$/m);
  assert.equal(ifOf(write), `always() && needs.gate.outputs.credit-marker == '${MARKER}' && steps.run.outputs.handoff-reason == 'credit-stop'`);
  assert.match(write, /echo "\$GITHUB_RUN_ID" >"\$RUNNER_TEMP\/key-credit-stop\/run-id"/);
  assert.ok(indexIn("model", "Run the changelog apply") < indexIn("model", "Write the key's credit-stop marker"));
  assert.ok(indexIn("model", "Check out the base for the sealer") < indexIn("model", "Write the key's credit-stop marker"));
  const scan = stepIn("model", "Scan the key's credit-stop marker for credentials");
  assert.match(scan, /^ {8}id: credit-marker-scan$/m);
  assert.equal(ifOf(scan), "always() && steps.credit-marker.outcome == 'success'");
  assert.match(scan, /^ {8}uses: \.\/\.lane-trusted\/\.github\/actions\/scan-upload /m);
  assert.match(scan, /^ {10}path: \$\{\{ runner\.temp \}\}\/key-credit-stop\/run-id$/m);
  const upload = stepIn("model", "Upload the key's credit-stop marker");
  assert.equal(ifOf(upload), "(always() && steps.credit-marker.outcome == 'success') && steps.credit-marker-scan.outputs.clean == 'true'");
  assert.match(upload, new RegExp(`^ {10}name: ${MARKER.replace(/\./g, "\\.")}$`, "m"));
  assert.match(upload, /^ {10}path: \$\{\{ runner\.temp \}\}\/key-credit-stop\/run-id$/m);
  assert.match(upload, /^ {10}retention-days: 1$/m);
  const row = JSON.parse(readFileSync(new URL("../../artifact-retention.json", import.meta.url), "utf8")).families[MARKER];
  assert.equal(row["retention-days"], 1);
  assert.equal(row.scan, "upload");
});

// A step condition of the shapes this workflow uses (string compares joined
// by && and ||, parentheses, always()), evaluated over `values`; an unset
// context reads as "", as GitHub reads a missing output or a step not run.
const evalIf = (expr, values) =>
  Function(
    `"use strict"; return (${expr
      .replace(/'([^']*)'/g, (_, s) => JSON.stringify(s))
      .replace(/always\(\)/g, "true")
      .replace(/\b(?:steps|needs)\.[\w.-]+/g, (ref) => JSON.stringify(values[ref] ?? ""))
      .replace(/([!=])=/g, "$1==")});`,
  )();
// The steps that write the start record, one per leg: the cap counts one
// record per such write, and only one leg of a run writes it.
const LEGS = ["model", "model-subscription", "model-fallback"];
const startWrite = (job) => ifOf(stepIn(job, "Record the start"));
test("only the three model legs write a start record", () => {
  const found = WORKFLOW.split(/\n(?= {6}- name: )/).filter((s) => /\/started\b/.test(s) && /printf '%s\\n' "\$RELEASE" >"[^"]*\/release\.txt"$/m.test(s));
  assert.equal(found.length, LEGS.length);
  for (const job of LEGS) assert.match(stepIn(job, "Record the start"), /printf '%s\\n' "\$RELEASE"/, job);
});
const leg = (over) => ({
  "steps.gate.outputs.proceed": "true",
  "steps.models.outcome": "success",
  "steps.credential.outputs.present": "true",
  "steps.run.outcome": "failure",
  ...over,
});

test("a leg that hands off writes no start record, so only the leg that runs the release counts toward the cap", () => {
  for (const job of ["model", "model-subscription"]) {
    for (const reason of ["credit-stop", "auth", "limit-stop"]) {
      assert.equal(evalIf(startWrite(job), leg({ "steps.run.outputs.handoff": "true", "steps.run.outputs.handoff-reason": reason })), false, `${job} ${reason}`);
    }
    // An empty credential hands the release on too.
    assert.equal(evalIf(startWrite(job), leg({ "steps.credential.outputs.present": "false", "steps.run.outcome": "skipped" })), false, `${job} empty credential`);
  }
  // The last leg never hands off, so a set token always counts.
  assert.equal(evalIf(startWrite("model-fallback"), leg({ "steps.run.outputs.handoff": "true" })), true);
  assert.equal(evalIf(startWrite("model-fallback"), leg({ "steps.credential.outputs.present": "false", "steps.run.outcome": "skipped" })), false);
});

test("a leg that ran writes a start record on success and on any failure it does not hand off", () => {
  for (const job of LEGS) {
    const write = startWrite(job);
    assert.equal(evalIf(write, leg({ "steps.run.outcome": "success", "steps.run.outputs.handoff": "false" })), true, `${job} success`);
    for (const cls of ["other", "timeout", "max-turns", "auth"]) {
      assert.equal(evalIf(write, leg({ "steps.run.outputs.lane-class": cls, "steps.run.outputs.handoff": "false" })), true, `${job} ${cls}`);
    }
  }
});

test("a setup failure before the leg still writes a start record, so the cap bounds a persistent setup fault", () => {
  for (const job of LEGS) {
    const write = startWrite(job);
    const noLeg = { "steps.run.outcome": "skipped", "steps.credential.outputs.present": "" };
    for (const models of ["success", "failure"]) {
      assert.equal(evalIf(write, leg({ ...noLeg, "steps.models.outcome": models })), true, `${job} resolve ${models}, no leg`);
    }
    // The kill switch skips Resolve the model: that run is not counted.
    assert.equal(evalIf(write, leg({ ...noLeg, "steps.models.outcome": "skipped" })), false, `${job} kill switch`);
    // The scan the record needs comes from the trusted checkout, which runs on the same condition.
    for (const step of ["Clear the trusted checkout path", "Check out the base for the sealer"]) {
      assert.equal(ifOf(stepIn(job, step)), "always() && steps.models.outcome != 'skipped'", `${job} ${step}`);
    }
  }
});

test("each leg's model step times out before the job does, so a timed-out leg still writes its start record", () => {
  const minutes = (text, indent) => Number(new RegExp(`^ {${indent}}timeout-minutes: (\\d+)$`, "m").exec(text)?.[1]);
  for (const job of LEGS) {
    const jobMinutes = minutes(jobOf(job).split(/\n {4}steps:\n/)[0], 4);
    const run = stepIn(job, "Run the changelog apply");
    const step = minutes(run, 8);
    const legMinutes = Number(/^ {10}leg-timeout-minutes: "(\d+)"$/m.exec(run)?.[1]);
    assert.ok(legMinutes < step && step <= jobMinutes - 5, `${job}: leg ${legMinutes}, step ${step}, job ${jobMinutes}`);
    assert.match(run, /^ {8}continue-on-error: true$/m);
    assert.equal(evalIf(startWrite(job), leg({ "steps.run.outcome": "failure", "steps.run.outputs.lane-class": "timeout" })), true, job);
  }
});

test("each leg writes, scans and uploads the start record after the leg", () => {
  for (const job of LEGS) {
    const record = stepIn(job, "Record the start");
    assert.match(record, /^ {8}id: start$/m);
    assert.match(record, /rm -rf "\$\{RUNNER_TEMP:\?\}\/started"/);
    assert.match(record, /^ {10}RELEASE: \$\{\{ needs\.gate\.outputs\.release \}\}$/m);
    const scan = stepIn(job, "Scan the start record for credentials");
    assert.equal(ifOf(scan), "always() && steps.start.outcome == 'success'");
    assert.match(scan, /^ {8}uses: \.\/\.lane-trusted\/\.github\/actions\/scan-upload /m);
    const upload = stepIn(job, "Upload the start record");
    assert.equal(ifOf(upload), "(always() && steps.start.outcome == 'success') && steps.start-scan.outputs.clean == 'true'");
    assert.match(upload, /^ {10}name: upstream-apply-changelog-started$/m);
    assert.doesNotMatch(upload, /continue-on-error/);
    for (const before of ["Run the changelog apply", "Check out the base for the sealer"]) {
      assert.ok(indexIn(job, before) < indexIn(job, "Record the start"), `${job} ${before}`);
    }
    assert.ok(indexIn(job, "Record the start") < indexIn(job, "Scan the start record for credentials"));
    assert.ok(indexIn(job, "Scan the start record for credentials") < indexIn(job, "Upload the start record"));
  }
  assert.ok(indexIn("model", "Upload the key's credit-stop marker") < indexIn("model", "Record the start"));
  const row = JSON.parse(readFileSync(new URL("../../artifact-retention.json", import.meta.url), "utf8")).families[STARTED_ARTIFACT];
  assert.equal(row.scan, "upload");
});

test("a key handoff writes a job summary line naming the subscription leg that takes the release", (t) => {
  const step = stepIn("model", "Report the key's handoff");
  assert.equal(ifOf(step), "always() && steps.run.outputs.handoff == 'true'");
  const run = step.split(/^ {8}run: \|\n/m)[1].replace(/^ {10}/gm, "");
  const dir = mkdtempSync(join(tmpdir(), "credit-stop-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const summary = join(dir, "summary.md");
  const report = (laneClass) => {
    rmSync(summary, { force: true });
    const out = execFileSync("bash", ["-e", "-c", run], {
      encoding: "utf8",
      env: { PATH: process.env.PATH, RELEASE: "2.1.318", LANE_CLASS: laneClass, GITHUB_STEP_SUMMARY: summary },
    });
    assert.equal(readFileSync(summary, "utf8"), out.replace(/^::warning::/, ""));
    return out;
  };
  assert.match(report("credit-stop"), /^::warning::ISSUE_LANE_CLAUDE_API_KEY hit a credit stop \(class credit-stop\); model-subscription runs release 2\.1\.318 on the subscription token$/m);
  assert.match(report("auth"), /^::warning::the API refused ISSUE_LANE_CLAUDE_API_KEY \(class auth\);.*model-subscription runs release 2\.1\.318/m);
});

test("the subscription leg runs after a key handoff, an empty key or a credit-gate skip, and the fallback leg after a subscription handoff", () => {
  const folded = (job) => (/^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(jobOf(job))?.[1] ?? "").replace(/\s+/g, " ").trim().replace(/^\$\{\{ (.*) \}\}$/, "$1");
  // Each leg starts on the leg the one before it names (credential-legs.test.mjs
  // drives these through every state).
  assert.equal(folded("model-subscription"), "!cancelled() && needs.gate.outputs.proceed == 'true' && github.run_attempt == '1' && (needs.model.outputs.next-leg == 'subscription' || needs.gate.outputs.next-leg == 'subscription')");
  assert.equal(folded("model-fallback"), "!cancelled() && needs.gate.outputs.proceed == 'true' && github.run_attempt == '1' && needs.model-subscription.outputs.next-leg == 'fallback'");
  // The empty-token run counts toward the cap once, on the fallback leg.
  assert.equal(evalIf(startWrite("model-subscription"), leg({ "steps.credential.outputs.present": "false", "steps.run.outcome": "skipped" })), false);
  assert.equal(evalIf(startWrite("model-fallback"), leg({ "steps.run.outcome": "success" })), true);
  assert.match(jobOf("model-subscription"), /^ {4}needs: \[gate, model\]$/m);
  assert.match(jobOf("model-fallback"), /^ {4}needs: \[gate, model-subscription\]$/m);
  // One credential per leg, each passed to run-claude-cli alone.
  const run = (job) => stepIn(job, "Run the changelog apply");
  assert.match(run("model"), /^ {10}api-key: \$\{\{ secrets\.ISSUE_LANE_CLAUDE_API_KEY \}\}$/m);
  assert.match(run("model-subscription"), /^ {10}subscription-token: \$\{\{ secrets\.ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN \}\}\n {10}fallback-ready: \$\{\{ steps\.credential\.outputs\.fallback-ready \}\}$/m);
  assert.match(run("model-fallback"), /^ {10}fallback-token: \$\{\{ secrets\.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN \}\}$/m);
  // Each leg seals under its own job id, and the scan opens the leg that ran.
  for (const job of LEGS) assert.match(stepIn(job, "Seal the plan and the branches"), new RegExp(`^ {10}JOB_ID: ${job}$`, "m"), job);
  assert.match(stepIn("scan", "Open the model job's sealed payloads"), /job-id: \$\{\{ needs\.model-fallback\.result != 'skipped' && 'model-fallback' \|\| needs\.model-subscription\.result != 'skipped' && 'model-subscription' \|\| 'model' \}\}/);
  // Only the key leg writes the credit gate's marker.
  for (const job of ["model-subscription", "model-fallback"]) assert.doesNotMatch(jobOf(job), /key-credit-stop/, job);
});

// The legs are the key leg's steps but for the credential, the marker, the
// handoff report, the leg record's fallback reason, the seal's job id and the
// next-leg call the fallback leg, the last, does not make.
test("the subscription and fallback legs repeat the key leg's steps", () => {
  const shape = (job) =>
    stepsOf(job)
      .filter((s) => !/^ {6}- name: (?:Write the key's credit-stop marker|Scan the key's credit-stop marker for credentials|Upload the key's credit-stop marker|Report the key's handoff|Report the subscription's handoff|Check the credential|Pick the next leg)\n/.test(s))
      .map((s) =>
        s
          .replace(/^ *#.*(?:\n|$)/gm, "")
          .trimEnd()
          .replace(/^ {10}(?:api-key|subscription-token|fallback-token|fallback-ready|fallback-reason|JOB_ID): .*(?:\n|$)/gm, "")
          .replace(/ && steps\.run\.outputs\.handoff != 'true'/, ""),
      );
  assert.deepEqual(shape("model-subscription"), shape("model"));
  assert.deepEqual(shape("model-fallback"), shape("model"));
});

test("the gate stops a fourth real run inside 24 hours and lets a third through", async (t) => {
  const now = Date.now();
  let starts = 0;
  const server = createServer((req, res) => {
    const name = new URL(req.url, "http://x").searchParams.get("name");
    const artifacts = name === STARTED_ARTIFACT
      ? Array.from({ length: starts }, (_, i) => ({ name, created_at: new Date(now - (i + 1) * 3600_000).toISOString() }))
      : [];
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ total_count: artifacts.length, artifacts }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => server.close());
  const dir = mkdtempSync(join(tmpdir(), "cap-gate-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const gate = async (count) => {
    starts = count;
    const out = join(dir, `out-${count}`);
    await execFileAsync(process.execPath, [new URL("./upstream-apply-changelog.mjs", import.meta.url).pathname, "gate"], {
      env: {
        PATH: process.env.PATH,
        GITHUB_API_URL: `http://127.0.0.1:${server.address().port}`,
        GITHUB_REPOSITORY: "o/r",
        GITHUB_OUTPUT: out,
        GH_TOKEN: "t",
        EVENT_NAME: "workflow_dispatch",
        RELEASE_INPUT: "2.1.318",
        DAILY_CAP: "3",
      },
    });
    return /^proceed=(\w+)$/m.exec(readFileSync(out, "utf8"))?.[1];
  };
  assert.equal(await gate(2), "true");
  assert.equal(await gate(3), "false");
});

test("a commit outside its plugin, or writing a link or submodule, is refused", () => {
  const ok = ":000000 100644 0000 1111 A\tplugins/hooks-kit/SKILL.md\n:000000 100644 0000 2222 A\t.changes/hooks-kit/x.md";
  assert.doesNotThrow(() => checkRawLog(ok, "hooks-kit"));
  assert.throws(() => checkRawLog(":100644 100644 1 2 M\tplugins/other/SKILL.md", "hooks-kit"), /outside/);
  assert.throws(() => checkRawLog(":100644 100644 1 2 M\t.github/workflows/x.yml", "hooks-kit"), /outside/);
  assert.throws(() => checkRawLog(":000000 120000 0 2 A\tplugins/hooks-kit/link", "hooks-kit"), /mode other than a regular file/);
  assert.throws(() => checkRawLog(":000000 160000 0 2 A\tplugins/hooks-kit/sub", "hooks-kit"), /mode other than a regular file/);
});

const SECURITY_SKILL = "plugins/review/skills/security-review/SKILL.md";
const RISK_SCORER = "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py";

test("the hold paths come from the security review's generated hold-paths block, and a missing or empty block throws", () => {
  const globs = loadHoldPaths();
  assert.ok(globs.includes("plugins/review/skills/security-review/**"));
  assert.ok(globs.includes(RISK_SCORER));
  assert.throws(() => readHoldPaths("jobs: {}\n"), /hold-paths block was not found/);
  assert.throws(() => readHoldPaths("  # BEGIN hold-floor hold-paths: x\n  hold-paths: |\n  # END hold-floor hold-paths\n"), /lists no path/);
});

test("a diff touching the security review skill or the risk scorer changes a hold path; an ordinary plugin path does not", () => {
  const raw = (path) => `:100644 100644 1 2 M\t${path}`;
  assert.equal(changesHoldPath(raw(SECURITY_SKILL)), true);
  assert.equal(changesHoldPath(raw(RISK_SCORER)), true);
  assert.equal(changesHoldPath(raw("plugins/Review/Skills/Security-Review/skill.md")), true);
  // Either side of a rename counts.
  assert.equal(changesHoldPath(`:100644 100644 1 2 R100\t${SECURITY_SKILL}\tplugins/review/skills/x.md`), true);
  assert.equal(changesHoldPath(raw("plugins/discovery/skills/explore/SKILL.md")), false);
  assert.equal(changesHoldPath(raw("plugins/review/skills/code-review/SKILL.md")), false);
});

test("the scan stops a release whose planned branch changes a hold path, naming no path, and passes an ordinary one", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "uac-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const env = { PATH: process.env.PATH, HOME: dir, GIT_CONFIG_NOSYSTEM: "1", GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@t", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@t" };
  const git = (...args) => execFileSync("git", ["-C", dir, ...args], { env, encoding: "utf8" }).trim();
  const commitFile = (path, from) => {
    git("checkout", "-q", "--detach", from);
    mkdirSync(join(dir, dirname(path)), { recursive: true });
    writeFileSync(join(dir, path), "edit");
    git("add", ".");
    git("commit", "-qm", path);
    return git("rev-parse", "HEAD");
  };
  git("init", "-q", "-b", "main");
  writeFileSync(join(dir, "keep.md"), "k");
  git("add", ".");
  git("commit", "-qm", "base");
  const base = git("rev-parse", "HEAD");
  const branch = (plugin, head) => ({ plugin, head_sha: head });
  const ordinary = commitFile("plugins/discovery/skills/explore/SKILL.md", base);
  assert.equal(holdPathBranch(dir, base, [branch("discovery", ordinary)]), -1);
  const skill = commitFile(SECURITY_SKILL, base);
  const risk = commitFile(RISK_SCORER, base);
  assert.equal(holdPathBranch(dir, base, [branch("discovery", ordinary), branch("review", skill)]), 1);
  assert.equal(holdPathBranch(dir, base, [branch("source-control", risk)]), 0);
  // A branch outside its plugin still throws before any hold path is read.
  assert.throws(() => holdPathBranch(dir, base, [branch("discovery", skill)]), (e) => /branches\[0\] raw line 1 changes a path outside/.test(e.message) && !e.message.includes("security-review"));

  // The scan subcommand rewrites the scan job's inputs to the stopped plan.
  const scanIn = join(dir, ".scan-in");
  mkdirSync(scanIn);
  const planned = plan({ base_sha: base });
  planned.branches[0] = { plugin: "review", branch: "changelog/review/v2.1.300", base_sha: base, head_sha: skill, pr: { title: "chore(review): x", body: "b" } };
  writeFileSync(join(scanIn, "plan.json"), JSON.stringify(planned));
  writeFileSync(join(scanIn, "heads.txt"), `${skill}\n`);
  const runScan = () =>
    execFileSync(process.execPath, [new URL("./upstream-apply-changelog.mjs", import.meta.url).pathname, "scan"], {
      env: { PATH: process.env.PATH, HOME: dir, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", IN: scanIn, RELEASE: "2.1.300", BASE_SHA: base, REPO_DIR: dir },
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  const out = runScan();
  assert.match(out, /::warning::branches\[0\] changes a hold path/);
  assert.equal(out.includes("security-review"), false);
  const rewritten = readPlan(readFileSync(join(scanIn, "plan.json"), "utf8"), { release: "2.1.300", baseSha: base });
  assert.deepEqual([rewritten.stop_reason, rewritten.branches.length], ["hold-path", 0]);
  assert.equal(readFileSync(join(scanIn, "heads.txt"), "utf8"), "");
  assert.ok(readFileSync(join(scanIn, "publish.txt"), "utf8").includes("stop_reason `hold-path`"));
  // A plan that claims hold-path itself is refused: only the scan sets it.
  assert.throws(runScan, (e) => /stop_reason hold-path is set by the scan job/.test(String(e.stdout)));

  // The stopped plan keeps its handoffs, publishes no branch and marks done.
  const stopped = readPlan(stoppedPlanText(JSON.stringify(plan())), ctx);
  assert.deepEqual([stopped.status, stopped.stop_reason, stopped.branches], ["stopped", "hold-path", []]);
  assert.equal(stopped.handoffs.length, 1);
  assert.equal(marksDone(stopped.stop_reason), true);
  const issue = releaseIssue("2.1.300", stopped.handoffs, stopped.stop_reason);
  assert.ok(issue.body.includes("stop_reason `hold-path`): a planned branch changed a hold path"));
  assert.ok(publishText(stopped, "2.1.300").includes(issue.body));
});

test("only the done marker skips a release, so a run after a failed publish finishes the work", () => {
  assert.equal(alreadyProcessed({ total_count: 1, artifacts: [{ name: "upstream-apply-changelog-done-2.1.300" }] }), true);
  assert.equal(alreadyProcessed({ total_count: 0, artifacts: [] }), false);
  assert.equal(alreadyProcessed(null), false);
});

test("the status file gives the unread releases, none when up to date, and stops on anything else", () => {
  assert.deepEqual(releasesFromStatus("range: 2.1.299..2.1.300 (2 releases, 5 core items)\nreleases: 2.1.299 2.1.300\ncap: within budget (2 releases / 5 items)\n"), ["2.1.299", "2.1.300"]);
  assert.deepEqual(releasesFromStatus("range: up to date\n"), []);
  assert.throws(() => releasesFromStatus("range: 2.1.1..2.1.90 (90 releases, 400 core items)\ncap: exceeded (90 releases / 400 items)\n"), /cap: exceeded/);
  assert.throws(() => releasesFromStatus("range: a..b\ncap: within budget\nreleases: v2\n"), /malformed/);
});

test("a scheduled gate checks only the newest unread releases, newest first", () => {
  const versions = Array.from({ length: 14 }, (_, i) => `2.1.${300 + i}`);
  const status = `range: 2.1.300..2.1.313 (14 releases, 90 core items)\nreleases: ${versions.join(" ")}\ncap: within budget (1000 releases / 1000000 items)\n`;
  assert.deepEqual(scheduledCandidates(status), ["2.1.313", "2.1.312", "2.1.311", "2.1.310", "2.1.309", "2.1.308", "2.1.307", "2.1.306", "2.1.305", "2.1.304"]);
  assert.deepEqual(scheduledCandidates("range: up to date\n"), []);
});

// A fake Git Data API: each object's sha is its index in the calls made.
function fakeApi() {
  const calls = [];
  const sha = (kind) => {
    calls.push(kind);
    return `${kind}-${calls.length}`;
  };
  return {
    calls,
    createBlob: async (content) => sha(`blob:${content}`),
    createTree: async (base, entries) => sha(`tree:${base}:${entries.map((e) => `${e.path}=${e.sha}`).join(",")}`),
    createCommit: async (message, tree, parents) => sha(`commit:${message.trim()}:${tree}:${parents.join(",")}`),
  };
}

test("a branch becomes one App commit on the base, titled with its pull request title, deleting a removed file", async () => {
  const api = fakeApi();
  const changes = [
    { path: "plugins/p/a.md", mode: "100644", content: Buffer.from("a") },
    { path: "plugins/p/old.md", mode: "100644", content: null },
  ];
  const tree = "tree:t0:plugins/p/a.md=blob:YQ==-1,plugins/p/old.md=null-2";
  const head = await commitNetTree(changes, { message: "chore(p): title", baseSha: BASE, baseTree: "t0", headTree: tree, api });
  assert.equal(api.calls.length, 3);
  assert.equal(api.calls[2], `commit:chore(p): title:${tree}:${BASE}`);
  assert.equal(head, `${api.calls[2]}-3`);
});

test("a built tree that is not the planned head's, or an empty change, makes no commit", async () => {
  const changes = [{ path: "plugins/p/a.md", mode: "100644", content: Buffer.from("a") }];
  const api = fakeApi();
  await assert.rejects(commitNetTree(changes, { message: "m", baseSha: BASE, baseTree: "t0", headTree: "other", api }), /not the planned head's/);
  assert.ok(!api.calls.some((c) => c.startsWith("commit:")));
  await assert.rejects(commitNetTree([], { message: "m", baseSha: BASE, baseTree: "t0", headTree: "t0", api: fakeApi() }), /changes nothing/);
});

test("the net change reads each file once at its head content, whatever the commits in between", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "uac-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const env = { PATH: process.env.PATH, HOME: dir, GIT_CONFIG_NOSYSTEM: "1", GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@t", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@t" };
  const git = (...args) => execFileSync("git", ["-C", dir, ...args], { env, encoding: "utf8" }).trim();
  git("init", "-q", "-b", "main");
  writeFileSync(join(dir, "keep.md"), "k");
  git("add", ".");
  git("commit", "-qm", "base");
  const base = git("rev-parse", "HEAD");
  writeFileSync(join(dir, "new.md"), "n1");
  git("add", ".");
  git("commit", "-qm", "add new");
  writeFileSync(join(dir, "new.md"), "n2");
  git("add", ".");
  git("commit", "-qm", "edit new");
  git("rm", "-q", "keep.md");
  git("commit", "-qm", "drop keep");
  const changes = readNetChanges(dir, base, git("rev-parse", "HEAD"));
  assert.deepEqual(
    changes.map((e) => [e.path, e.mode, e.content === null ? null : String(e.content)]),
    [["keep.md", "100644", null], ["new.md", "100644", "n2"]],
  );
  writeFileSync(join(dir, "img.bin"), Buffer.from([0, 1, 2, 0, 255]));
  git("add", ".");
  git("commit", "-qm", "binary");
  const numstat = git("diff", "--numstat", base, "HEAD");
  assert.throws(() => refuseBinary(numstat, 2), (e) => /branches\[2\] changes a binary file/.test(e.message) && !e.message.includes("img.bin"));
  assert.doesNotThrow(() => refuseBinary(git("diff", "--numstat", base, "HEAD~1"), 2));
  // A merge commit's change shows in the net diff, so the path check sees it.
  git("checkout", "-qb", "side", base);
  git("checkout", "-q", "main", "--", "new.md");
  git("commit", "-qm", "side");
  git("merge", "-q", "--no-edit", "main");
  assert.match(netRawDiff(dir, base, git("rev-parse", "HEAD")), /\tnew\.md$/m);
});

test("the scanned bundle holds one fixed commit per head with its tree, and no blob a merge added then removed", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "uac-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const env = { PATH: process.env.PATH, HOME: dir, GIT_CONFIG_NOSYSTEM: "1", GIT_AUTHOR_NAME: "model", GIT_AUTHOR_EMAIL: "m@m", GIT_COMMITTER_NAME: "model", GIT_COMMITTER_EMAIL: "m@m" };
  const repo = join(dir, "repo");
  const fresh = join(dir, "fresh");
  const git = (cwd, ...args) => execFileSync("git", ["-C", cwd, ...args], { env, encoding: "utf8" }).trim();
  git(dir, "init", "-q", "-b", "main", repo);
  writeFileSync(join(repo, "keep.md"), "k");
  git(repo, "add", ".");
  git(repo, "commit", "-qm", "base");
  const base = git(repo, "rev-parse", "HEAD");
  git(repo, "tag", "base");
  git(repo, "checkout", "-qb", "side");
  writeFileSync(join(repo, "secret.md"), "SECRET-VALUE-0123456789");
  git(repo, "add", ".");
  git(repo, "commit", "-qm", "add secret");
  const secret = git(repo, "rev-parse", "side:secret.md");
  git(repo, "checkout", "-qb", "head", base);
  writeFileSync(join(repo, "plugin.md"), "p");
  git(repo, "add", ".");
  git(repo, "commit", "-qm", "plugin change");
  git(repo, "merge", "-q", "--no-edit", "side");
  git(repo, "rm", "-q", "secret.md");
  git(repo, "commit", "-qm", "drop secret");
  const head = git(repo, "rev-parse", "HEAD");
  assert.equal(git(repo, "cat-file", "-t", secret), "blob");

  const bundle = join(dir, "branches.bundle");
  const [made] = syntheticBundle(repo, base, [head], bundle);
  assert.equal(made.tree, git(repo, "rev-parse", `${head}^{tree}`));
  assert.deepEqual(syntheticBundle(repo, base, [head], join(dir, "again.bundle")), [made]);
  assert.equal(git(repo, "log", "-1", "--format=%P|%an|%ae|%aI|%cn|%ce|%cI|%B", made.commit),
    `${base}|upstream-apply-changelog|upstream-apply-changelog@users.noreply.github.com|1970-01-01T00:00:00Z|upstream-apply-changelog|upstream-apply-changelog@users.noreply.github.com|1970-01-01T00:00:00Z|${SYNTHETIC_MESSAGE}`);

  git(dir, "init", "-q", "-b", "main", fresh);
  git(fresh, "fetch", "-q", "--no-tags", repo, "refs/tags/base:refs/base");
  assert.equal(fetchSynthetic(fresh, bundle, base, made, "refs/scanned", 0), made.commit);
  const has = (sha) => {
    try {
      git(fresh, "cat-file", "-e", sha);
      return true;
    } catch {
      return false;
    }
  };
  assert.equal(has(made.commit), true);
  assert.equal(has(secret), false);
  assert.equal(has(head), false);
  assert.deepEqual(readNetChanges(fresh, base, made.commit).map((e) => e.path), ["plugin.md"]);
  assert.throws(() => fetchSynthetic(fresh, bundle, base, { ...made, tree: base }, "refs/other", 3), /branches\[3\] does not hold the scanned tree/);
});

test("the scan job's synthetic list must name one commit and tree per planned branch", () => {
  const one = [{ commit: HEAD, tree: BASE }];
  assert.deepEqual(readSynthetic(JSON.stringify(one), 1), one);
  assert.deepEqual(readSynthetic("", 0), []);
  assert.throws(() => readSynthetic(JSON.stringify(one), 2), /do not match/);
  assert.throws(() => readSynthetic(JSON.stringify([{ commit: "x", tree: BASE }]), 1), /do not match/);
  assert.throws(() => readSynthetic("{", 1), /not JSON/);
});

const REPO = "o/r";
const REL = "2.1.300";
const APP = { login: "melodic-automation-lanes[bot]", type: "Bot" };
const OUTSIDER = { login: "someone", type: "User" };
const handoff = (n, over = {}) => ({ key: `changelog:${REL}..${REL}:adopt:plugins/x/${n}.sh`, kind: "adopt", title: `adopt ${n}`, body: `body ${n}\nline two`, ...over });
// A fake API: answers the search with `items`, a comment read with the page of
// `comments` it asks for (or `comments` itself when not a list), and records every call.
const issueApi = (items = [], comments = []) => {
  const calls = [];
  const api = async (path, opts = {}) => {
    const method = opts.method ?? "GET";
    calls.push({ path, method, body: opts.body });
    if (path.startsWith("/search/issues")) return { items };
    if (method === "GET" && path.includes("/comments?")) {
      if (!Array.isArray(comments)) return comments;
      const page = Number(path.match(/page=(\d+)$/)[1]);
      return comments.slice((page - 1) * 100, page * 100);
    }
    return {};
  };
  return { api, calls, writes: () => calls.filter((c) => c.method !== "GET") };
};

test("no handoffs files nothing and makes no call", async () => {
  const f = issueApi();
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [], api: f.api });
  assert.equal(f.calls.length, 0);
});

test("one handoff files one release issue with the release marker and its keyed checklist item", async () => {
  const f = issueApi();
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1)], api: f.api });
  const [w] = f.writes();
  assert.equal(f.writes().length, 1);
  assert.equal(w.path, `/repos/${REPO}/issues`);
  assert.equal(w.method, "POST");
  assert.equal(w.body.title, `Claude Code v${REL} changelog: 1 handoff`);
  assert.ok(w.body.body.startsWith(`${releaseMarker(REL)}\n`));
  assert.ok(w.body.body.includes("- [ ] adopt: adopt 1\n\n  body 1\n  line two\n\n  "));
  assert.ok(w.body.body.includes(handoffMarker(handoff(1).key)));
});

test("several handoffs go into one issue, one checklist item each, in plan order", async () => {
  const f = issueApi();
  const hs = [handoff(1), handoff(2, { kind: "security" }), handoff(3)];
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: hs, api: f.api });
  assert.equal(f.writes().length, 1);
  const { title, body } = f.writes()[0].body;
  assert.equal(title, `Claude Code v${REL} changelog: 3 handoffs`);
  assert.equal(body.match(/^- \[ \] /gm).length, 3);
  assert.ok(body.includes("- [ ] security: adopt 2"));
  const at = hs.map((h) => body.indexOf(handoffMarker(h.key)));
  assert.ok(at.every((i) => i > 0) && at[0] < at[1] && at[1] < at[2]);
});

test("bodies over the issue limit are cut in proportion, every key kept, and a line says so", async () => {
  const f = issueApi();
  const hs = [handoff(1, { body: "a".repeat(50000) }), handoff(2, { body: "b".repeat(25000) })];
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: hs, api: f.api });
  const { body } = f.writes()[0].body;
  assert.ok(body.length <= 65536);
  assert.match(body, /truncated proportionally/);
  for (const h of hs) assert.ok(body.includes(handoffMarker(h.key)));
  const a = body.match(/a+/g).reduce((m, s) => Math.max(m, s.length), 0);
  const b = body.match(/b{100,}/g)[0].length;
  assert.ok(Math.abs(a / b - 2) < 0.01);
  assert.equal(renderItems(hs.slice(0, 1).map((h) => ({ ...h, body: "x" })), 1000).includes("truncated"), false);
});

test("a release issue holding every key gets no write", async () => {
  const hs = [handoff(1), handoff(2)];
  const body = `${releaseMarker(REL)}\n\n${renderItems(hs, 65536)}`;
  const f = issueApi([{ user: APP, number: 7, state:"open", body }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: hs, api: f.api });
  assert.equal(f.writes().length, 0);
});

test("an open release issue missing a key gets the missing item appended in one update", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const f = issueApi([{ user: APP, number: 7, state:"open", body }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1), handoff(2)], api: f.api });
  const writes = f.writes();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].path, `/repos/${REPO}/issues/7`);
  assert.equal(writes[0].method, "PATCH");
  assert.equal(writes[0].body.title, `Claude Code v${REL} changelog: 2 handoffs`);
  assert.ok(writes[0].body.body.startsWith(body.trimEnd()));
  assert.equal(writes[0].body.body.split(handoffMarker(handoff(1).key)).length, 2);
  assert.ok(writes[0].body.body.includes(handoffMarker(handoff(2).key)));
});

test("a closed release issue gets no write, even when it lacks a key", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const f = issueApi([{ user: APP, number: 7, state:"closed", body }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1), handoff(2)], api: f.api });
  assert.equal(f.writes().length, 0);
});

test("an issue for another release does not count as this release's issue", async () => {
  const f = issueApi([{ user: APP, number: 7, state:"open", body: `${releaseMarker("2.1.30")}\n` }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1)], api: f.api });
  assert.equal(f.writes()[0].method, "POST");
});

test("missing items that would push the body past the limit go in one comment instead", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1, { body: "a".repeat(60000) })], 65536)}`;
  const f = issueApi([{ user: APP, number: 7, state:"open", body }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1), handoff(2, { body: "b".repeat(10000) })], api: f.api });
  const writes = f.writes();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].path, `/repos/${REPO}/issues/7/comments`);
  assert.equal(writes[0].method, "POST");
  assert.ok(writes[0].body.body.includes(handoffMarker(handoff(2).key)));
  assert.ok(!writes[0].body.body.includes(handoffMarker(handoff(1).key)));
  assert.ok(writes[0].body.body.length <= 65536);
});

test("a key already in a comment, past the first page, is not added again", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const comments = [...Array.from({ length: 100 }, () => ({ body: "noise" })), { user: APP, body: renderItems([handoff(2)], 65536) }];
  const f = issueApi([{ user: APP, number: 7, state:"open", body }], comments);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1), handoff(2), handoff(3)], api: f.api });
  const writes = f.writes();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].method, "PATCH");
  assert.ok(writes[0].body.body.includes(handoffMarker(handoff(3).key)));
  assert.ok(!writes[0].body.body.includes(handoffMarker(handoff(2).key)));
  assert.equal(f.calls.filter((c) => c.path.includes("/comments?")).length, 2);
});

test("a comment read that fails, or runs past the page cap, files nothing", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const hs = [handoff(1), handoff(2)];
  const bad = issueApi([{ user: APP, number: 7, state:"open", body }], { message: "Server Error" });
  await assert.rejects(fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: hs, api: bad.api }), /not come back as a list/);
  assert.equal(bad.writes().length, 0);
  const many = issueApi([{ user: APP, number: 7, state:"open", body }], Array.from({ length: 1000 }, () => ({ body: "" })));
  await assert.rejects(fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: hs, api: many.api }), /more comments/);
  assert.equal(many.writes().length, 0);
});

test("the search asks for issues the lanes App opened", async () => {
  const f = issueApi();
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1)], api: f.api });
  const q = decodeURIComponent(f.calls[0].path.match(/q=([^&]+)/)[1]);
  assert.match(q, /(^| )author:app\/melodic-automation-lanes( |$)/);
});

test("an outsider's issue carrying the release marker is ignored and a new issue is filed", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const f = issueApi([{ user: OUTSIDER, number: 7, state: "open", body }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1)], api: f.api });
  const writes = f.writes();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].path, `/repos/${REPO}/issues`);
  assert.equal(writes[0].method, "POST");
});

test("a stopped plan with no handoffs still files one issue that names its stop_reason", async () => {
  const f = issueApi();
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [], stop: "cap-exceeded", api: f.api });
  const writes = f.writes();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].path, `/repos/${REPO}/issues`);
  assert.equal(writes[0].body.title, `Claude Code v${REL} changelog: 0 handoffs`);
  assert.ok(writes[0].body.body.startsWith(`${releaseMarker(REL)}\n\n`));
  assert.ok(writes[0].body.body.includes(`Claude Code v${REL} stopped (stop_reason \`cap-exceeded\`)`));
});

test("a stopped plan's handoff issue opens with the stop line above its checklist", async () => {
  const f = issueApi();
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1)], stop: "cap-exceeded", api: f.api });
  const { body } = f.writes()[0].body;
  const stopAt = body.indexOf("stop_reason `cap-exceeded`");
  assert.ok(stopAt > 0 && stopAt < body.indexOf("- [ ] adopt: adopt 1"));
  assert.ok(body.includes(handoffMarker(handoff(1).key)));
});

test("a stopped plan whose closed release issue lacks a key fails with no write", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const f = issueApi([{ user: APP, number: 7, state: "closed", body }]);
  await assert.rejects(
    fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1), handoff(2)], stop: "cap-exceeded", api: f.api }),
    /#7 is closed and lacks 1 handoffs/,
  );
  assert.equal(f.writes().length, 0);
});

test("a stopped plan whose release issue already holds every key succeeds with no write, open or closed", async () => {
  const hs = [handoff(1), handoff(2)];
  const body = `${releaseMarker(REL)}\n\n${renderItems(hs, 65536)}`;
  for (const state of ["open", "closed"]) {
    const f = issueApi([{ user: APP, number: 7, state, body }]);
    await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: hs, stop: "cap-exceeded", api: f.api });
    assert.equal(f.writes().length, 0);
  }
});

test("a stopped plan whose issue filing fails rejects, so publish fails and the release is retried", async () => {
  const f = issueApi();
  const failing = async (path, opts = {}) => {
    if (opts.method === "POST") throw new Error("POST /repos/o/r/issues answered 502");
    return f.api(path, opts);
  };
  await assert.rejects(fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1)], stop: "cap-exceeded", api: failing }), /answered 502/);
});

test("a key marker in an outsider's comment does not count as filed", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const f = issueApi([{ user: APP, number: 7, state: "open", body }], [{ user: OUTSIDER, body: renderItems([handoff(2)], 65536) }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1), handoff(2)], api: f.api });
  const writes = f.writes();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].method, "PATCH");
  assert.ok(writes[0].body.body.includes(handoffMarker(handoff(2).key)));
});
