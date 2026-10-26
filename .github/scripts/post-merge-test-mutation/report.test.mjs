// report.mjs, and the hardening of the two post-merge mutation workflows:
// no pull request starts either, only the model-free report job writes, the
// model job reads contents only and runs under the subprocess env scrub, and
// the trigger's path filter equals the config's mutate globs.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { commentBody, MARKER, main, mergedPulls, parseResult, render, scores, violations } from "./report.mjs";

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

test("model text in the detail stays inside a fence it cannot close", () => {
  const text = render({ result: result([], { detail: "x ```` y" }), after: AFTER, mode: "commit", pulls: [], repository: "o/r" });
  assert.match(text, /\n`````text\nx ```` y\n`````/);
});

test("mergedPulls keeps the closed pull requests into main and falls back to GraphQL", async () => {
  const rest = [
    { number: 7, state: "closed", base: { ref: "main" } },
    { number: 8, state: "open", base: { ref: "main" } },
    { number: 9, state: "closed", base: { ref: "other" } },
  ];
  assert.deepEqual(await mergedPulls({ github: async () => rest, repository: "o/r", sha: AFTER }), [7]);
  const graphql = {
    data: {
      repository: {
        object: {
          associatedPullRequests: {
            pageInfo: { hasNextPage: false },
            nodes: [{ number: 5, state: "MERGED", isDraft: false, baseRefName: "main", labels: { nodes: [], pageInfo: { hasNextPage: false } } }],
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

function run(env, pulls = []) {
  const dir = mkdtempSync(join(tmpdir(), "mutation-report-"));
  const summary = join(dir, "summary.md");
  const comment = join(dir, "comment.md");
  const output = join(dir, "output");
  const lines = [];
  const original = console.log;
  console.log = (line) => lines.push(line);
  const read = (path) => (existsSync(path) ? readFileSync(path, "utf8") : null);
  const github = async () => {
    if (pulls instanceof Error) throw pulls;
    return pulls;
  };
  return main({ REPOSITORY: "o/r", AFTER, BEFORE, RANGE_MODE: "range", GITHUB_STEP_SUMMARY: summary, COMMENT_PATH: comment, GITHUB_OUTPUT: output, GITHUB_RUN_ID: "77", ...env }, { github })
    .then((code) => ({ code, lines, summary: read(summary), comment: read(comment), output: read(output) }))
    .finally(() => {
      console.log = original;
    });
}

const merged = (number, over = {}) => ({ number, state: "closed", base: { ref: "main" }, ...over });

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
  const unrestored = await run({ AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: JSON.stringify(result([], { outcome: "restore-failed" })) });
  assert.equal(unrestored.code, 1);
  assert.ok(unrestored.lines.some((line) => line.startsWith("::error::")));
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
  assert.match(LANE, /\n {4}workflows: \[post-merge-select-mutation-range\]\n/);
});

test("only the model-free report job writes, and the model job reads contents only under the env scrub", () => {
  const jobs = jobsOf(LANE);
  assert.deepEqual(Object.keys(jobs), ["prep", "audit", "report"]);
  for (const block of [...Object.values(jobsOf(GATE)), jobs.prep, jobs.audit]) {
    assert.ok(Object.values(permissionsOf(block)).every((value) => value === "read"), block.split("\n")[0]);
  }
  assert.deepEqual(permissionsOf(jobs.audit), { contents: "read" });
  assert.deepEqual(permissionsOf(jobs.report), { contents: "read", "pull-requests": "write" });
  assert.doesNotMatch(jobs.report, /claude-code-action|secrets\./, "the writing job runs no model and holds no secret");
  assert.equal(LANE.match(/anthropics\/claude-code-action@/g).length, 1);
  assert.match(jobs.audit, /anthropics\/claude-code-action@/);
  assert.match(jobs.audit, /\n {10}CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"\n/);
  assert.match(jobs.audit, /install-subprocess-isolation: true/);
  assert.match(jobs.audit, /--permission-mode dontAsk/);
  assert.equal(LANE.match(/secrets\./g).length, 1, "the OAuth token is the one secret");
  assert.doesNotMatch(`${GATE}${LANE}`, /id-token|request-lane-token|persist-credentials: true/);
  assert.equal(LANE.match(/actions\/checkout@/g).length, LANE.match(/persist-credentials: false/g).length);
});

test("the model's git reads stay in the checkout and its edits stay out of home dot paths", () => {
  const { audit } = jobsOf(LANE);
  const allowed = /\n {10}allowed="\$allowed,Bash\(git status \*\)[^\n]*/.exec(audit)[0];
  assert.doesNotMatch(allowed, /git log|git show/, "the audit skill runs neither");
  const denied = [...audit.matchAll(/\n {10}denied="([^\n]*)"/g)].map((m) => m[1]).join(",");
  for (const rule of [
    "Bash(git log *)",
    "Bash(git show *)",
    "Bash(git diff *--no-index*)",
    "Bash(git diff *--output*)",
    "Bash(git diff *~*)",
    "Bash(git diff * /*)",
    "Bash(git diff *../*)",
    "Edit(~/.*)",
    "Edit(~/.*/**)",
  ]) {
    assert.ok(denied.includes(rule), rule);
  }
});

test("the gate's path filter equals the config's mutate globs", () => {
  const config = readFileSync(new URL("../../../.claude/mutation-testing.md", import.meta.url), "utf8");
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

test("main writes a no-result comment too, without the violation text", async () => {
  const out = await run({ AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: "{}" }, [merged(42)]);
  assert.equal(out.code, 1);
  assert.equal(out.output, "pull=42\n");
  assert.match(out.comment, /- Outcome: no result\. The run's summary says why\./);
  assert.doesNotMatch(out.comment, /\$\.outcome/);
});

test("main writes no comment and no pull output for no, several or an unread merged pull request", async () => {
  const ok = { AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: JSON.stringify(result([])) };
  for (const [label, pulls, notice] of [
    ["a direct push", [], /0 pull requests merged the head/],
    ["several", [merged(1), merged(2)], /2 pull requests merged the head/],
    ["a failed lookup", new Error("down"), /lookup failed/],
  ]) {
    const out = await run(ok, pulls);
    assert.equal(out.comment, null, label);
    assert.equal(out.output, null, label);
    assert.ok(out.lines.some((line) => notice.test(line)), label);
  }
});

test("a key the model adds is never echoed, so it cannot reach the summary or a comment", async () => {
  const key = "@someone [x](https://example.invalid)";
  const out = await run({ AUDIT_RESULT: "success", RESTORED: "true", STRUCTURED_OUTPUT: JSON.stringify({ ...result([]), [key]: 1 }) }, [merged(42)]);
  assert.equal(out.code, 1);
  assert.ok(!out.summary.includes(key));
  assert.ok(!out.comment.includes(key));
  assert.ok(!out.comment.includes("@someone"));
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
