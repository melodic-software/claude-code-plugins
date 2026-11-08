// report.mjs, and the hardening of the two post-merge mutation workflows:
// no pull request starts either, only the model-free report job writes, the
// model jobs read contents only and run no test, the mutants run in a job that
// holds no secret, and the trigger's path filter equals the config's mutate globs.
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import process from "node:process";
import { test } from "node:test";

import { commentBody, MARKER, main, mergedPulls, parseResult, rangePulls, render, scores, violations } from "./report.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const AFTER = "a".repeat(40);
const BEFORE = "b".repeat(40);
const mutant = (over = {}) => ({ path: "scripts/x.sh", line: 3, operator: "SBR", state: "killed", disposition: "none", cause: "none", ...over });
const result = (mutants, over = {}) => ({ outcome: "reported", detail: "", mutants, ...over });

test("a result in the schema's shape has no violations", () => {
  assert.deepEqual(violations(result([mutant(), mutant({ state: "survived", disposition: "productive", cause: "input-gap" })])), []);
});

test("each kind of schema violation is named by its path", () => {
  assert.deepEqual(violations(result([mutant({ state: "dead" })])), ["$.mutants[0].state: not one of killed, survived, no-coverage, timeout, invalid, not-run"]);
  assert.deepEqual(violations({ ...result([]), extra: 1 }), ["$: has a property the schema does not list"]);
  assert.deepEqual(violations({ outcome: "reported", mutants: [] }), ["$.detail: missing"]);
  assert.match(violations(result([mutant({ path: "a|b" })]))[0], /^\$\.mutants\[0\]\.path: does not match/);
  assert.match(parseResult(JSON.stringify(result([mutant({ path: "a/../x" })]))).error, /mutants\[0\]\.path: has a \. or \.\. segment/);
  assert.deepEqual(violations(result([mutant({ line: 0 })])), ["$.mutants[0].line: not an integer of at least 1"]);
  assert.deepEqual(violations(result(Array.from({ length: 51 }, () => mutant()))), ["$.mutants: more than 50 items"]);
  assert.deepEqual(violations(result([], { detail: "x".repeat(501) })), ["$.detail: longer than 500"]);
  assert.deepEqual(violations([]), ["$: not an object"]);
});

test("parseResult refuses text that is not JSON", () => {
  assert.deepEqual(parseResult("not json"), { error: "the audit returned no JSON result" });
  assert.deepEqual(parseResult(undefined), { error: "the audit returned no JSON result" });
  assert.match(parseResult('{"outcome":"x"}').error, /does not match result\.schema\.json/);
});

test("scores follow Stryker's aggregates: timeouts are detected, no coverage only in the plain score", () => {
  const s = scores([
    mutant(),
    mutant({ state: "timeout" }),
    mutant({ state: "survived" }),
    mutant({ state: "no-coverage" }),
    mutant({ state: "invalid" }),
  ]);
  assert.equal(s.coveredScore, "67%");
  assert.equal(s.mutationScore, "50%");
  assert.equal(scores([]).coveredScore, "n/a");
});

test("the report names the range, the merged pull request, the counts and each survivor", () => {
  const text = render({
    result: result([mutant(), mutant({ path: "lib/y.mjs", line: 9, state: "survived", disposition: "productive", cause: "no-assertion" })]),
    before: BEFORE,
    after: AFTER,
    mode: "range",
    pulls: [42],
    repository: "o/r",
  });
  assert.match(text, /- Range: bbbbbbbbbbbb\.\.aaaaaaaaaaaa\n/);
  assert.match(text, /- Merged pull request: \[#42\]\(https:\/\/github\.com\/o\/r\/pull\/42\)\n/);
  assert.match(text, /Killed 1, survived 1, timeout 0, no coverage 0, invalid 0, not run 0\./);
  assert.match(text, /\| `lib\/y\.mjs` \| 0 \| 1 \|/);
  assert.match(text, /\| `lib\/y\.mjs:9` \| SBR \| productive \| no-assertion \|/);
});

test("the report says when there was no previous head, no pull request, or no lookup", () => {
  const base = { result: result([]), after: AFTER, repository: "o/r" };
  assert.match(render({ ...base, mode: "commit", pulls: [] }), /Range: aaaaaaaaaaaa only .*\n- Merged pull request: none \(a direct push\)/);
  assert.match(render({ ...base, mode: "range", before: BEFORE, pulls: null }), /Merged pull request: unknown \(the lookup failed\)/);
});

test("an audit that stopped before choosing a mode reports the pushed range, not a missing previous head", () => {
  const text = render({ result: null, error: "the audit job failed", before: BEFORE, after: AFTER, mode: "", pulls: [], repository: "o/r" });
  assert.match(text, /- Range: bbbbbbbbbbbb\.\.aaaaaaaaaaaa pushed; the audit chose no diff mode\n/);
  assert.doesNotMatch(text, /no usable previous head/);
});

test("model text in the detail stays inside a fence it cannot close", () => {
  const text = render({ result: result([], { detail: "x ```` y" }), after: AFTER, mode: "commit", pulls: [], repository: "o/r" });
  assert.match(text, /\n`````text\nx ```` y\n`````/);
});

// A pull request opened on main's tip and closed unmerged lists the commit
// too; only the merged one counts, on the REST read and the GraphQL fallback.
test("mergedPulls keeps the merged pull requests into main and falls back to GraphQL", async () => {
  const rest = [
    { number: 7, state: "closed", merged_at: "2026-10-26T10:00:00Z", base: { ref: "main" } },
    { number: 6, state: "closed", merged_at: null, base: { ref: "main" } },
    { number: 8, state: "open", merged_at: null, base: { ref: "main" } },
    { number: 9, state: "closed", merged_at: "2026-10-26T10:00:00Z", base: { ref: "other" } },
  ];
  assert.deepEqual(await mergedPulls({ github: async () => rest, repository: "o/r", sha: AFTER }), [7]);
  assert.deepEqual(await mergedPulls({ github: async () => [rest[1]], repository: "o/r", sha: AFTER }), []);
  const node = (number, state, mergedAt) => ({ number, state, mergedAt, isDraft: false, baseRefName: "main", labels: { nodes: [], pageInfo: { hasNextPage: false } } });
  const graphql = {
    data: {
      repository: {
        object: {
          associatedPullRequests: {
            pageInfo: { hasNextPage: false },
            nodes: [node(5, "MERGED", "2026-10-26T10:00:00Z"), node(4, "CLOSED", null)],
          },
        },
      },
    },
  };
  const fallback = async (method) => {
    if (method === "GET") throw Object.assign(new Error("boom"), { status: 502 });
    return graphql;
  };
  const logged = [];
  const original = console.log;
  console.log = (line) => logged.push(line);
  try {
    assert.deepEqual(await mergedPulls({ github: fallback, repository: "o/r", sha: AFTER }), [5]);
    assert.equal(await mergedPulls({ github: async () => { throw new Error("down"); }, repository: "o/r", sha: AFTER }), null);
  } finally {
    console.log = original;
  }
});

// `pulls` answers each commit's pull request read: a list for every commit, or
// a map from commit SHA to its list. The compare read lists `commits`.
function run(env, pulls = [], commits = [AFTER]) {
  const dir = tempDir("mutation-report-");
  const summary = join(dir, "summary.md");
  const comment = join(dir, "comment.md");
  const output = join(dir, "output");
  const lines = [];
  const original = console.log;
  console.log = (line) => lines.push(line);
  const read = (path) => (existsSync(path) ? readFileSync(path, "utf8") : null);
  const github = async (method, path) => {
    if (path.includes("/compare/")) return { total_commits: commits.length, commits: commits.map((sha) => ({ sha })) };
    if (pulls instanceof Error) throw pulls;
    return Array.isArray(pulls) ? pulls : pulls[path.split("/").at(-2)];
  };
  return main({ REPOSITORY: "o/r", AFTER, BEFORE, RANGE_MODE: "range", GITHUB_STEP_SUMMARY: summary, COMMENT_PATH: comment, GITHUB_OUTPUT: output, GITHUB_RUN_ID: "77", ...env }, { github })
    .then((code) => ({ code, lines, summary: read(summary), comment: read(comment), output: read(output) }))
    .finally(() => {
      console.log = original;
    });
}

const merged = (number, over = {}) => ({ number, state: "closed", merged_at: "2026-10-26T10:00:00Z", base: { ref: "main" }, ...over });

test("main passes a report with survivors, since no score gates the lane", async () => {
  const out = await run({ AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: JSON.stringify(result([mutant({ state: "survived", disposition: "unclassified", cause: "unclassified" })])) });
  assert.equal(out.code, 0);
  assert.match(out.summary, /survived 1/);
});

test("main fails a run that left no valid result or an edited checkout", async () => {
  const failed = await run({ AUDIT_RESULT: "failure", RESTORED: "true" });
  assert.equal(failed.code, 1);
  assert.match(failed.summary, /Outcome: no result\. the audit job ended failure/);
  const edited = await run({ AUDIT_RESULT: "failure", RESTORED: "false" });
  assert.equal(edited.code, 1);
  assert.match(edited.summary, /differs from the pushed head/);
  const invalid = await run({ AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: "{}" });
  assert.equal(invalid.code, 1);
});

// The workflow's check of the tree decides a restore; the model's restore-failed
// outcome alone does not fail the run.
test("a restore-failed result fails the run only when the workflow's check did not find the tree restored", async () => {
  const output = JSON.stringify(result([mutant(), mutant({ line: 4, state: "not-run" })], { outcome: "restore-failed" }));
  const restored = await run({ AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: output });
  assert.equal(restored.code, 0);
  assert.ok(restored.lines.some((line) => line.startsWith("::warning::")));
  assert.match(restored.summary, /Outcome: restore-failed/);
  assert.match(restored.summary, /Killed 1, survived 0, timeout 0, no coverage 0, invalid 0, not run 1\./);
  for (const RESTORED of ["false", ""]) {
    const out = await run({ AUDIT_RESULT: "success", RESTORED, STRUCTURED_OUTPUT: output });
    assert.equal(out.code, 1, `RESTORED=${JSON.stringify(RESTORED)}`);
    assert.ok(out.lines.some((line) => line.startsWith("::error::")));
  }
});

test("a usage or capacity limit stop passes with a notice, and any other class still fails", async () => {
  for (const STOP_CLASS of ["rate-limit", "overloaded"]) {
    const out = await run({ AUDIT_RESULT: "success", RESTORED: "true", STOP_CLASS, STRUCTURED_OUTPUT: "" }, [merged(42)]);
    assert.equal(out.code, 0, STOP_CLASS);
    assert.ok(out.lines.some((line) => line.startsWith("::notice::") && line.includes(STOP_CLASS)));
    assert.match(out.summary, new RegExp(`Outcome: stopped on class ${STOP_CLASS}`));
    assert.equal(out.comment, null, "a stop posts no comment");
  }
  for (const STOP_CLASS of ["max-turns", "other", "auth"]) {
    const out = await run({ AUDIT_RESULT: "success", RESTORED: "true", STOP_CLASS, STRUCTURED_OUTPUT: "" });
    assert.equal(out.code, 1, STOP_CLASS);
  }
  const edited = await run({ AUDIT_RESULT: "success", RESTORED: "false", STOP_CLASS: "rate-limit", STRUCTURED_OUTPUT: "" });
  assert.equal(edited.code, 1, "a limit stop never covers an edited checkout");
});

// The two workflows, read as text: each job is the block under its two-space id.
const workflowText = (name) => readFileSync(new URL(`../../workflows/${name}`, import.meta.url), "utf8");
const jobsOf = (text) =>
  Object.fromEntries(
    `\n${text.split("\njobs:\n")[1]}`
      .split(/\n(?= {2}[a-z][a-z-]*:\n)/)
      .slice(1)
      .map((block) => [/^ {2}([a-z-]+):/.exec(block)[1], block]),
  );
const permissionsOf = (block) => {
  const match = /\n {4}permissions:(?: \{\}\n|\n((?: {6}[a-z-]+: [a-z]+.*\n)+))/.exec(block);
  assert.ok(match, "the job names its permissions");
  return Object.fromEntries([...(match[1] ?? "").matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => [m[1], m[2]]));
};
const GATE = workflowText("post-merge-select-mutation-range.yml");
const LANE = workflowText("post-merge-test-mutation.yml");

test("only a push to main starts the gate, and only the gate's run starts the lane", () => {
  for (const text of [GATE, LANE]) {
    assert.doesNotMatch(text, /pull_request/);
    assert.match(text, /\npermissions: \{\}\n/);
  }
  assert.deepEqual([...GATE.split("\non:\n")[1].split("\npermissions:")[0].matchAll(/^ {2}([a-z_]+):/gm)].map((m) => m[1]), ["push"]);
  assert.deepEqual([...LANE.split("\non:\n")[1].split("\npermissions:")[0].matchAll(/^ {2}([a-z_]+):/gm)].map((m) => m[1]), ["workflow_run"]);
  assert.match(LANE, /\n {4}workflows: \[Post Merge Select Mutation Range\]\n/);
});

const MODEL_JOBS = ["generate", "generate-subscription", "generate-fallback", "triage", "triage-subscription", "triage-fallback"];
// One step of a job block, by its id or its name.
const stepOf = (block, key) => {
  const step = block.split(/\n(?= {6}- name: )/).find((s) => s.includes(`\n        id: ${key}\n`) || s.includes(`- name: ${key}\n`));
  assert.ok(step, key);
  return step;
};
// A literal block (`key: |`) of a step, one entry per line.
const literal = (step, key) => {
  const lines = step.split(`\n          ${key}: |\n`)[1].split("\n");
  const end = lines.findIndex((line) => !line.startsWith("            "));
  return lines.slice(0, end < 0 ? lines.length : end).map((line) => line.trim());
};
// A run step's script, as the runner runs it.
const script = (step) => step.split("\n        run: |\n")[1].split("\n").map((line) => line.replace(/^ {10}/, "")).join("\n");
const field = (step, key) => new RegExp(`\\n {8,10}${key}: (.*)\\n`).exec(step)?.[1];

test("only the model-free report job writes, the model jobs read contents only, and the mutants run in a job with no secret", () => {
  const jobs = jobsOf(LANE);
  assert.deepEqual(Object.keys(jobs), ["prep", "key-credit", ...MODEL_JOBS.slice(0, 3), "mutate", ...MODEL_JOBS.slice(3), "report"]);
  for (const block of [...Object.values(jobsOf(GATE)), jobs.prep, jobs["key-credit"], jobs.mutate, ...MODEL_JOBS.map((id) => jobs[id])]) {
    assert.ok(Object.values(permissionsOf(block)).every((value) => value === "read"), block.split("\n")[0]);
  }
  for (const id of MODEL_JOBS) {
    assert.deepEqual(permissionsOf(jobs[id]), { contents: "read" }, id);
    assert.match(jobs[id], /run-claude-cli@[0-9a-f]{40} /, id);
    assert.match(jobs[id], /\n {10}permission-mode: dontAsk\n/, id);
    assert.doesNotMatch(jobs[id].replace(/^\s*#.*$/gm, ""), /run-covering-tests|execute\.mjs|setup-env\.sh/, `${id} runs no test and no head install`);
  }
  assert.deepEqual(permissionsOf(jobs.mutate), { contents: "read" });
  assert.doesNotMatch(jobs.mutate, /secrets\.|github\.token|run-claude-cli/, "the mutate job holds no secret and runs no model");
  assert.match(jobs.mutate, /post-merge-test-mutation\/execute\.mjs "\$GENERATION"/);
  assert.match(jobs.mutate, /\n {10}install-subprocess-isolation: true\n/);
  assert.deepEqual(permissionsOf(jobs.report), { contents: "read", "pull-requests": "write" });
  assert.doesNotMatch(jobs.report, /claude-code-action|run-claude-cli|secrets\./, "the writing job runs no model and holds no secret");
  assert.doesNotMatch(LANE, /anthropics\/claude-code-action@/);
  assert.equal(LANE.match(/\/run-claude-cli@/g).length, 6);
  assert.doesNotMatch(`${GATE}${LANE}`, /id-token|request-lane-token|persist-credentials: true/);
  assert.equal(LANE.match(/actions\/checkout@/g).length, LANE.match(/persist-credentials: false/g).length);
});

// Each model leg's Bash runs read-only git and the plugin's suppression lint,
// which Phase 1 step 3 runs in generate and Phase 4 in triage; no leg edits a file.
test("the model's Bash allows git reads only and its git reads stay in the checkout", () => {
  const jobs = jobsOf(LANE);
  for (const id of MODEL_JOBS) {
    const run = stepOf(jobs[id], "run");
    const allowed = literal(run, "allowed-tools");
    const git = allowed.flatMap((rule) => [.../^Bash\(git ([a-z-]+)/.exec(rule) ?? []].slice(1));
    assert.ok(git.length > 0, id);
    assert.deepEqual(git.filter((verb) => !["status", "diff", "branch", "rev-parse"].includes(verb)), [], id);
    assert.deepEqual(allowed.filter((rule) => rule.startsWith("Bash(") && !rule.startsWith("Bash(git ")), ["Bash(bash ${{ steps.prompt.outputs.lint }} *)"], id);
    const denied = literal(run, "disallowed-tools");
    for (const rule of ["Edit", "Write", "NotebookEdit", "Bash(git log *)", "Bash(git show *)", "Bash(git diff *--no-index*)", "Bash(git diff *--output*)", "Bash(git diff *~*)", "Bash(git diff * /*)", "Bash(git diff *../*)", "Bash(git diff *$*)"]) {
      assert.ok(denied.includes(rule), `${id} ${rule}`);
    }
  }
});

// A model leg's stop step, run as the runner runs it.
function stopStep(failureClass) {
  const step = stepOf(jobsOf(LANE).generate, "stop");
  const dir = tempDir("mutation-stop-");
  const output = join(dir, "output");
  const res = spawnSync("bash", ["-e", "-c", script(step)], { env: { PATH: process.env.PATH, FAILURE_CLASS: failureClass, GITHUB_OUTPUT: output }, encoding: "utf8" });
  return { code: res.status, output: existsSync(output) ? readFileSync(output, "utf8") : "" };
}

test("the stop step passes a usage or capacity limit and fails every other class", () => {
  for (const failureClass of ["rate-limit", "overloaded"]) {
    assert.deepEqual(stopStep(failureClass), { code: 0, output: `class=${failureClass}\n` });
  }
  for (const failureClass of ["auth", "max-turns", "timeout", "no-execution", "other", ""]) {
    assert.deepEqual(stopStep(failureClass), { code: 1, output: "" }, failureClass);
  }
  // A handoff is no failure: the step runs only on a failed leg that handed nothing on.
  for (const id of MODEL_JOBS) {
    assert.equal(field(stepOf(jobsOf(LANE)[id], "stop"), "if"), "always() && steps.run.outcome == 'failure' && steps.run.outputs.handoff != 'true'", id);
  }
});

test("the mutate job applies mutants under the config's mutate globs and checks the tree it leaves", () => {
  const jobs = jobsOf(LANE);
  const execute = stepOf(jobs.mutate, "execute");
  assert.match(execute, /CONFIG=docs\/conventions\/mutation-testing\.yaml/);
  assert.match(execute, /cp -R scripts "\$HARNESS\/"\n\s*chmod -R a-w "\$HARNESS"/, "a mutant of the harness cannot break the harness");
  assert.match(stepOf(jobs.mutate, "restored"), /git diff --quiet HEAD/);
  // Each handoff between jobs is one artifact pinned by the SHA-256 its job recorded.
  assert.match(field(stepOf(jobs.mutate, "mutants"), "WANT"), /needs\.generate-fallback\.outputs\.sha256/);
  for (const id of ["triage", "triage-subscription", "triage-fallback"]) {
    assert.equal(field(stepOf(jobs[id], "Check the executed mutants"), "WANT"), "${{ needs.mutate.outputs.sha256 }}", id);
  }
  assert.match(stepOf(jobs.report, "report"), /pinned "\$EXECUTED" "\$EXECUTED_SUM"/);
});

test("the gate's path filter equals the config's mutate globs", () => {
  const config = readFileSync(new URL("../../../docs/conventions/mutation-testing.yaml", import.meta.url), "utf8");
  const mutate = [...config.split("\nmutate:\n")[1].split("\n\n")[0].matchAll(/^ {2}- "([^"]+)"$/gm)].map((m) => m[1]);
  const paths = [...GATE.split("\n    paths:\n")[1].split("\n\n")[0].matchAll(/^ {6}- "([^"]+)"$/gm)].map((m) => m[1]);
  assert.ok(mutate.length > 0);
  assert.deepEqual(paths, mutate);
});

test("the comment step runs only on report.mjs's pull output, after a failed report too, and takes its body from the file", () => {
  const { report } = jobsOf(LANE);
  const steps = report.split(/\n(?= {6}- name: )/);
  const write = steps.find((step) => step.includes("name: Write the report"));
  const comment = steps.find((step) => step.includes("name: Comment the report on the merged pull request"));
  assert.ok(steps.indexOf(write) < steps.indexOf(comment));
  assert.match(write, /\n {8}id: report\n/);
  assert.match(comment, /\n {8}if: \$\{\{ !cancelled\(\) && steps\.report\.outputs\.pull != '' \}\}\n/);
  assert.match(comment, /\n {10}PULL: \$\{\{ steps\.report\.outputs\.pull \}\}\n/);
  assert.match(comment, /\n {8}run: node \.base\/\.github\/scripts\/post-merge-test-mutation\/comment\.mjs\n/);
  assert.equal(comment.match(/COMMENT_PATH: (.*)/)[1], write.match(/COMMENT_PATH: (.*)/)[1]);
  // No model output reaches the comment step, by env or expression.
  assert.doesNotMatch(comment, /needs\.audit|STRUCTURED_OUTPUT/);
});

test("main writes the comment body and the pull output for exactly one merged pull request", async () => {
  const out = await run({ AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: JSON.stringify(result([mutant({ state: "survived" })], { detail: "free text" })) }, [merged(42)]);
  assert.equal(out.code, 0);
  assert.equal(out.output, "pull=42\n");
  assert.ok(out.comment.startsWith(`${MARKER}\n## Post-merge mutation testing\n`));
  assert.match(out.comment, /\[The run's summary\]\(https:\/\/github\.com\/o\/r\/actions\/runs\/77\)/);
  assert.doesNotMatch(out.comment, /free text/);
  assert.match(out.summary, /free text/);
});

test("main comments on the merged pull request when another closed unmerged on the head", async () => {
  const out = await run({ AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: JSON.stringify(result([mutant({ state: "survived" })])) }, [merged(42), merged(43, { merged_at: null })]);
  assert.equal(out.output, "pull=42\n");
  assert.notEqual(out.comment, null);
});

// Each outcome class, on one merged pull request: comment only for a survivor or an uncovered mutant.
const OUTCOMES = [
  ["a survivor", result([mutant({ state: "survived" })]), true, null],
  ["an uncovered mutant", result([mutant({ state: "no-coverage" })]), true, null],
  ["a survivor beside a refusal", result([mutant({ state: "survived" })], { outcome: "refused" }), true, /refused/],
  ["all killed", result([mutant(), mutant({ line: 4, state: "timeout" })]), false, null],
  ["a scope-empty result", result([], { outcome: "scope-empty" }), false, null],
  ["a refusal", result([mutant({ state: "not-run" })], { outcome: "refused" }), false, /refused/],
  ["a reported result with every mutant not run", result([mutant({ state: "not-run" })]), false, /every mutant is not-run/],
  ["a reported result with some killed, some not run", result([mutant(), mutant({ line: 4, state: "not-run" })]), false, null],
];
for (const [label, output, comments, warning] of OUTCOMES) {
  test(`main ${comments ? "comments" : "stays quiet"} for ${label}${warning ? " and warns" : ""}`, async () => {
    const out = await run({ AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: JSON.stringify(output) }, [merged(42)]);
    assert.equal(out.code, 0);
    assert.ok(out.summary.includes("Post-merge mutation testing"), "the summary is written for every outcome");
    assert.equal(out.comment !== null, comments);
    assert.equal(out.output, comments ? "pull=42\n" : null);
    const warned = out.lines.filter((line) => line.startsWith("::warning::"));
    if (warning) assert.ok(warned.some((line) => warning.test(line)), `warning ${warning}`);
    else assert.equal(warned.length, 0);
  });
}

test("main writes no comment for a run with no valid result, and fails it", async () => {
  const out = await run({ AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: "{}" }, [merged(42)]);
  assert.equal(out.code, 1);
  assert.equal(out.comment, null);
  assert.equal(out.output, null);
  assert.match(out.summary, /Outcome: no result/);
});

test("main writes no comment and no pull output for no, several or an unread merged pull request", async () => {
  const ok = { AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: JSON.stringify(result([mutant({ state: "survived" })])) };
  for (const [label, pulls, notice] of [
    ["a direct push", [], /0 pull requests merged the range/],
    ["a direct push with a pull request closed unmerged on the head", [merged(3, { merged_at: null })], /0 pull requests merged the range/],
    ["several", [merged(1), merged(2)], /2 pull requests merged the range/],
    ["a failed lookup", new Error("down"), /lookup failed/],
  ]) {
    const out = await run(ok, pulls);
    assert.equal(out.comment, null, label);
    assert.equal(out.output, null, label);
    assert.ok(out.lines.some((line) => notice.test(line)), label);
  }
});

// A merge queue pushed two squash merges at once (#13675 then #13669): the
// survivor is in the first one's file, so the head's pull request alone must
// not get the comment.
test("main names every pull request of a batched push and comments on none of them", async () => {
  const first = "c".repeat(40);
  const ok = { AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: JSON.stringify(result([mutant({ state: "survived" })])) };
  const out = await run(ok, { [first]: [merged(13675)], [AFTER]: [merged(13669)] }, [first, AFTER]);
  assert.equal(out.comment, null);
  assert.equal(out.output, null);
  assert.match(out.summary, /Merged pull request: \[#13669\]\([^)]*\), \[#13675\]/);
  assert.ok(out.lines.some((line) => /2 pull requests merged the range/.test(line)));
});

test("main reads only the head's pull requests when the push had no usable previous head", async () => {
  const ok = { AUDIT_RESULT: "success", RESTORED: "true", RANGE_MODE: "commit", STRUCTURED_OUTPUT: JSON.stringify(result([mutant({ state: "survived" })])) };
  const out = await run(ok, { [AFTER]: [merged(42)] }, []);
  assert.equal(out.output, "pull=42\n");
});

test("a range the compare read does not list in full names no pull request", async () => {
  const github = async (method, path) => (path.includes("/compare/") ? { total_commits: 300, commits: [{ sha: AFTER }] } : [merged(1)]);
  assert.equal(await rangePulls({ github, repository: "o/r", before: BEFORE, after: AFTER }), null);
  const down = async () => {
    throw new Error("down");
  };
  assert.equal(await rangePulls({ github: down, repository: "o/r", before: BEFORE, after: AFTER }), null);
});

test("a key the model adds is never echoed, so it cannot reach the summary or a comment", async () => {
  const key = "@someone [x](https://example.invalid)";
  const out = await run({ AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: JSON.stringify({ ...result([]), [key]: 1 }) }, [merged(42)]);
  assert.equal(out.code, 1);
  assert.ok(!out.summary.includes(key));
  assert.equal(out.comment, null);
});

test("the comment body carries only validated fields: enums, integers, pattern-checked paths and SHAs", () => {
  const body = commentBody({
    result: result([mutant({ path: "lib/@scope/y.mjs", line: 9, state: "survived", disposition: "productive", cause: "no-assertion" })], { detail: "@someone ```` [x](https://example.invalid)" }),
    before: BEFORE,
    after: AFTER,
    mode: "range",
    pulls: [42],
    repository: "o/r",
    runId: "not-a-number",
  });
  assert.ok(body.startsWith(`${MARKER}\n`));
  assert.doesNotMatch(body, /example\.invalid|````/);
  // An @ in a path sits inside inline code, where it notifies no one.
  assert.match(body, /\| `lib\/@scope\/y\.mjs:9` \| SBR \| productive \| no-assertion \|/);
  assert.match(body, /\nThe run's summary has the full report\.\n$/);
});
