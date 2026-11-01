// pr-verify.yml's ordering rules, from its concurrency comment and the
// README's "Verifier verdict" section: GitHub cancels an older pending run in the same concurrency group, so a cancelled
// run must leave no verdict. The upload is therefore each job's only artifact
// step, it runs after the verdict file is written, and only when writing it
// succeeded; the group is per PR and head, never cancelling a running judgment.
// The key job judges first; the subscription job repeats it on the other
// credential only when the key job hands the judgment on, and the fallback
// job repeats it on the central fallback token only when the subscription job
// hands it on, so one job per run writes a verdict.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";

const text = readFileSync(new URL("../../workflows/pr-verify.yml", import.meta.url), "utf8");
const KEY = "check-intent";
const SUB = "check-intent-subscription";
const FB = "check-intent-fallback";
const JOBS = [KEY, SUB, FB];
const jobText = (id) => {
  const found = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(text);
  assert.ok(found, `a job ${id}`);
  return found[1];
};
// Each step starts at a `      - name:` line of its job.
const stepsOf = (id) =>
  jobText(id)
    .split(/\n(?=      - name: )/)
    .slice(1)
    .map((block) => ({ name: /^      - name: (.*)$/m.exec(block)[1], block }));
const STEPS = Object.fromEntries(JOBS.map((id) => [id, stepsOf(id)]));
const index = (name, job = KEY) => STEPS[job].findIndex((step) => step.name === name);
const step = (name, job = KEY) => {
  const found = STEPS[job].find((s) => s.name === name);
  assert.ok(found, `a step named ${name} in ${job}`);
  return found.block;
};
const input = (block, key) => new RegExp(`^ {10}${key}: (.*)$`, "m").exec(block)?.[1];
const list = (block, key) => {
  const body = new RegExp(`^ {10}${key}: \\|\\n((?: {12}.*\\n?)+)`, "m").exec(block)?.[1] ?? "";
  return body.split("\n").map((line) => line.trim()).filter(Boolean);
};
// The most chunks a head is judged in: chunk-diff.sh's one MAX_CHUNKS, and
// each job holds a judge step for every one (the slot tests below).
const chunkScript = readFileSync(new URL("./chunk-diff.sh", import.meta.url), "utf8");
const CEILING = Number(/^MAX_CHUNKS=\$\{MAX_CHUNKS:-([1-9][0-9]*)\}$/m.exec(chunkScript)?.[1]);
const SLOTS = Array.from({ length: CEILING }, (_, i) => i + 1);
const PIN = /^melodic-software\/ci-workflows\/\.github\/actions\/([a-z-]+)@[0-9a-f]{40} # \S/;
// The subscription job's one lane record names why the key did not judge,
// in report-lane-outcome's fallback-reason (ci-workflows intake-triage.yml).
const FALLBACK_REASON =
  "${{ needs.check-intent.outputs.lane-class == 'credit-stop' && 'credit-stop' || needs.check-intent.outputs.lane-class == 'auth' && 'auth' || needs.check-intent.outputs.credential-present == 'false' && 'no-key' || '' }}";
// The fallback job's record names why the subscription did not judge, from
// its handoff-reason (ci-workflows intake-triage.yml, the fallback job).
const FB_REASON =
  "${{ needs.check-intent-subscription.outputs.handoff-reason == 'limit-stop' && 'limit-stop' || needs.check-intent-subscription.outputs.handoff-reason == 'credit-stop' && 'credit-stop' || needs.check-intent-subscription.outputs.handoff-reason == 'auth' && 'auth' || '' }}";
const FALLBACK = "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN";
// Whether the fallback leg can run, never the token (ci-workflows
// intake-triage.yml and pr-review-cli.yml, "Check the credential").
const FALLBACK_PRESENT = `          FALLBACK_PRESENT: \${{ secrets.${FALLBACK} != '' }}`;
const FALLBACK_READY = [
  '          if [ "$FALLBACK_PRESENT" = true ]; then',
  '            echo "fallback-ready=true" >>"$GITHUB_OUTPUT"',
  "          else",
  '            echo "fallback-ready=false" >>"$GITHUB_OUTPUT"',
  "          fi",
].join("\n");
// check-intent's reads, which the subscription job's resolver takes through
// env only (resolve-pr.mjs takeReads).
const CARRIED = "          CARRIED: ${{ needs.check-intent.outputs.reads }}";
const CARRY_ENV = ["          CONTEXT_FILE: ${{ github.workspace }}/pr-verify-data/context.json", CARRIED];
const NOT_CARRIED = " && steps.pr.outputs.carried != 'true'";
const KEY_CLASS = "${{ steps.judge.outputs.lane-class == 'credit-stop' && 'rate-limit' || steps.judge.outputs.lane-class }}";
const KEY_REPORT_IF =
  "(steps.judge.outcome == 'success' || steps.judge.outcome == 'failure') && (steps.judge.outputs.handoff != 'true' || steps.key-leg.outcome == 'failure')";
const SUB_REPORT_IF =
  "(steps.judge.outcome == 'success' || steps.judge.outcome == 'failure') && (steps.judge.outputs.handoff != 'true' || steps.sub-leg.outcome == 'failure')";
const CREDENTIAL = {
  [KEY]: ["api-key", "PR_VERIFY_CLAUDE_API_KEY"],
  [SUB]: ["subscription-token", "PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN"],
  [FB]: ["fallback-token", FALLBACK],
};
const others = (job) => JOBS.filter((id) => id !== job).map((id) => CREDENTIAL[id]);
const keyGate = () => /^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(jobText(KEY))?.[1].replace(/\s+/g, " ").trim();
// Evaluates a gate of `a == b` terms joined by && and parenthesized || groups
// on one run's context; an evaluated term of any other shape fails the test.
const admits = (gate, context) => {
  const value = (term) => (/^'.*'$/.test(term) ? term.slice(1, -1) : term.split(".").reduce((at, key) => at?.[key], context));
  const equal = (term) => {
    assert.match(term, /^\S+ == \S+$/);
    const [left, right] = term.split(" == ");
    return value(left) === value(right);
  };
  return gate.split(" && ").every((clause) => clause.replace(/^\(|\)$/g, "").split(" || ").some(equal));
};
// A branch filter pattern per GitHub's filter pattern cheat sheet: `*` stops
// at `/`, `**` matches any character including `/`. Every other character is
// taken literally, so a pattern using `?`, `+`, `[]` or `!` needs more here.
const glob = (pattern) => {
  const literal = pattern.replace(/[.+?^$()|[\]{}\\]/g, "\\$&");
  return new RegExp("^" + literal.replace(/\*\*|\*/g, (star) => (star === "**" ? ".*" : "[^/]*")) + "$");
};
const REPO = "melodic-software/claude-code-plugins";
// A job output read from each chunk's step, chunk 1's id being `first`.
const chainOf = (build, first) => [first, ...SLOTS.slice(1).map((k) => `${first}-${k}`), `${first}-spec`].map(build).join(" || ");
// Every leg check of a job left no clean handoff: "&& steps.<leg>-k.outcome != 'success'" for each slot and the spec.
const legsClear = (first) => chainOf((id) => `steps\\.${id}\\.outcome != 'success'`, first).replaceAll(" || ", " && ");
const upstreamRun = (overrides = {}) => ({
  github: {
    ref: "refs/heads/main",
    repository: REPO,
    event: {
      workflow_run: { event: "pull_request", conclusion: "success", head_repository: { full_name: REPO }, ...overrides },
    },
  },
});

test("the upload is each job's only artifact step and follows the written verdict", () => {
  for (const job of JOBS) {
    const uploads = STEPS[job].filter((s) => /uses: actions\/upload-artifact@/.test(s.block));
    assert.deepEqual(
      uploads.map((s) => s.name),
      ["Upload the verdict"],
      job,
    );
    assert.ok(index("Judge the pull request", job) >= 0 && index("Write the verdict", job) > index("Judge the pull request", job), job);
    // The written verdict is scanned just before it uploads, and uploads only on the scan's clean output.
    assert.ok(index("Scan the upload for credentials", job) > index("Write the verdict", job), job);
    assert.equal(index("Upload the verdict", job), index("Scan the upload for credentials", job) + 1, job);
    const scan = step("Scan the upload for credentials", job);
    assert.match(scan, /^ {8}id: scan-upload\n {8}if: >-\n {10}\$\{\{ !cancelled\(\) && steps\.verdict\.outcome == 'success' \}\}$/m, job);
    assert.match(scan, /^ {10}path: \$\{\{ runner\.temp \}\}\/pr-verify-verdict\/verdict\.json$/m, job);
    assert.match(
      uploads[0].block,
      /^ {8}if: >-\n {10}\(!cancelled\(\) && steps\.verdict\.outcome == 'success'\) && steps\.scan-upload\.outputs\.clean == 'true'$/m,
      job,
    );
    // The verdict step names the retention (write-verdict.mjs retentionDays).
    assert.equal(input(uploads[0].block, "retention-days"), "${{ steps.verdict.outputs.retention-days }}", job);
    // A pass's retention follows this job's resolver (resolve-pr.mjs relinkedSince).
    assert.match(step("Write the verdict", job), /^ {10}RELINK_SINCE_HEAD: \$\{\{ steps\.pr\.outputs\.relink-since-head \}\}$/m, job);
    // A verdict needs a judge step that succeeded, which run-claude-cli never
    // reports with a lane-class, so a credit stop writes none.
    assert.match(step("Write the verdict", job), /^ {8}if: \$\{\{ !cancelled\(\) && \(/m, job);
  }
  assert.doesNotMatch(text, /actions\/upload-artifact\/merge|gh api .*artifacts.* -X (POST|PUT)|actions\/download-artifact|actions\/cache/);
});

// The resolver reads only, and skips on its own reads a run whose head is
// judged, moved past, a draft, red for anything a person's approval does not
// lift, or not the lanes App's; so it runs before the trigger gate, whose
// reads then go only to a run the resolver would judge. The agree step runs
// only after the gate proceeds, so a gate refusal ends the run without a
// judgment and without a mismatch error.
test("the resolver runs before the trigger gate, and the agree step only after the gate proceeds", () => {
  for (const job of JOBS) {
    assert.ok(index("Resolve the pull request", job) < index("Check the trigger", job), job);
    assert.ok(index("Check the trigger", job) < index("Assert the gate and the resolver agree", job), job);
    assert.match(step("Resolve the pull request", job), /^ {8}if: steps\.kill\.outputs\.proceed == 'true'$/m, job);
    assert.match(step("Check the trigger", job), /^ {8}if: steps\.pr\.outputs\.proceed == 'true'$/m, job);
    assert.match(step("Assert the gate and the resolver agree", job), /^ {8}if: steps\.gate\.outputs\.proceed == 'true'$/m, job);
    // Every judging step hangs off agree, and so does the missing-verdict failure.
    assert.match(step("Fail without a verdict", job), /steps\.agree\.outcome == 'success'/, job);
  }
});

test("pr-merge.yml gives the gate an Actions token for the verdict reads only", () => {
  // babysit_verify_evidence.py reads BABYSIT_VERIFY_GH_TOKEN; the lane token
  // the gate runs gh with holds no Actions permission.
  const merge = readFileSync(new URL("../../workflows/pr-merge.yml", import.meta.url), "utf8");
  const job = /\n  merge:\n([\s\S]*?)\n  [a-z-]+:\n/.exec(merge)[1];
  assert.match(job, /\n {6}actions: read\n/);
  const gate = /- name: Run the merge gate on each candidate\n([\s\S]*?)\n {6}- name: /.exec(job)[1];
  assert.match(gate, /\n {10}GH_TOKEN: \$\{\{ steps\.lane-token\.outputs\.token \}\}\n/);
  assert.match(gate, /\n {10}BABYSIT_VERIFY_GH_TOKEN: \$\{\{ github\.token \}\}\n/);
});

test("the concurrency group is per PR and head and never cancels a running judgment", () => {
  const group = /^concurrency:\n  group: (.*)\n  cancel-in-progress: (.*)$/m.exec(text);
  assert.ok(group, "a top-level concurrency block");
  assert.match(group[1], /workflow_run\.pull_requests\[0\]\.number/);
  assert.match(group[1], /workflow_run\.head_sha/);
  assert.equal(group[2], "false");
});

// The judgment on ci-workflows' run-claude-cli (docs/conventions/pr-pipeline/README.md,
// Funding: pr-verify takes the pr-verify role), under the launcher's input
// contract (its action.yml: managed settings while sudo works, then runner
// isolation) and the deny rules that keep the model on its data files.
test("each job judges on run-claude-cli as the pr-verify role with its one secret", () => {
  const pins = new Set();
  for (const job of JOBS) {
    const judge = step("Judge the pull request", job);
    const uses = /^ {8}uses: (.*)$/m.exec(judge)[1];
    assert.equal(PIN.exec(uses)?.[1], "run-claude-cli", job);
    pins.add(uses);
    assert.equal(input(judge, "lane"), "pr-verify", job);
    assert.equal(input(judge, "role"), "pr-verify", job);
    const [own, secret] = CREDENTIAL[job];
    assert.equal(input(judge, own), `\${{ secrets.${secret} }}`, job);
    for (const [other] of others(job)) assert.equal(input(judge, other), undefined, job);
    assert.match(judge, /^ {8}if: steps\.credential\.outputs\.present == 'true'$/m, job);
    for (const key of ["model", "effort", "max-turns"]) {
      assert.equal(input(judge, key), `\${{ steps.models.outputs.${key} }}`, key);
    }
    assert.equal(input(judge, "permission-mode"), "dontAsk", job);
    assert.equal(input(judge, "leg-timeout-minutes"), '"15"', job);
    assert.match(judge, /^ {8}continue-on-error: true$/m, job);
    assert.match(judge, /^ {8}timeout-minutes: 22$/m, job);
    assert.match(judge, /^ {10}CLAUDE_CODE_DISABLE_BACKGROUND_TASKS: "1"$/m, job);
    assert.match(input(judge, "prompt-file"), /^\$\{\{ runner\.temp \}\}\//, job);
    assert.match(input(judge, "json-schema-file"), /^\$\{\{ runner\.temp \}\}\//, job);
  }
  assert.equal(pins.size, 1, "every job pins the same run-claude-cli");
  assert.doesNotMatch(text, /anthropics\/claude-code-action/);
});

test("each secret appears only in its own job", () => {
  // The subscription job may ask only whether the fallback token is set.
  const seen = (job) => (job === SUB ? jobText(job).replaceAll(`secrets.${FALLBACK} != ''`, "") : jobText(job));
  for (const job of JOBS) {
    const [, own] = CREDENTIAL[job];
    assert.ok(jobText(job).includes(`secrets.${own}`), job);
    for (const [, other] of others(job)) assert.ok(!seen(job).includes(`secrets.${other}`), `${job} reads ${other}`);
  }
  assert.ok(jobText(SUB).includes(`secrets.${FALLBACK} != ''`));
  assert.doesNotMatch(text, /secrets\.(?!PR_VERIFY_CLAUDE_API_KEY\b|PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN\b|FALLBACK_CLAUDE_CODE_OAUTH_TOKEN\b)/);
  assert.doesNotMatch(text, /secrets: inherit|toJSON\(secrets\)/);
});

// A failed upstream run reaches resolve-pr, which judges it only when it
// failed on nothing but holds an approving review of the head lifts, the
// `do-not-merge` label, or both (heldOnly).
test("the key job runs on main for a same-repository pull_request run that passed or failed", () => {
  assert.equal(
    keyGate(),
    [
      "github.ref == 'refs/heads/main'",
      "&& github.event.workflow_run.event == 'pull_request'",
      "&& (github.event.workflow_run.conclusion == 'success' || github.event.workflow_run.conclusion == 'failure')",
      "&& github.event.workflow_run.head_repository.full_name == github.repository",
    ].join(" "),
  );
});

// The trigger's branch filter matches the branch the pr-require-checks run ran
// on (GitHub's events docs, workflow_run). A merge-queue run's branch is
// gh-readonly-queue/main/... and a schedule or dispatch run's is main, so
// neither starts a run that would only skip; every pull request branch still
// reaches the gate.
test("a same-repository pull_request run on a feature branch passes the trigger and the key job's gate", () => {
  const on = /^on:\n([\s\S]*?)\n(?=\S)/m.exec(text)?.[1] ?? "";
  assert.match(on, /^ {4}workflows: \[pr-require-checks\]$/m);
  assert.match(on, /^ {4}types: \[completed\]$/m);
  assert.doesNotMatch(on, /^ {4}branches:/m);
  const ignored =
    /^ {4}branches-ignore: \[(.*)\]$/m
      .exec(on)?.[1]
      .split(",")
      .map((pattern) => pattern.trim().replace(/^'|'$/g, "")) ?? [];
  assert.deepEqual(ignored, ["main", "gh-readonly-queue/**"]);
  const triggers = (branch) => !ignored.some((pattern) => glob(pattern).test(branch));
  for (const branch of ["feat/8695-skip-only-runs", "fix/a", "dependabot/npm_and_yarn/a/b", "main-follow-up", "mainline"]) {
    assert.ok(triggers(branch), branch);
    assert.ok(admits(keyGate(), upstreamRun({ head_branch: branch })), branch);
    assert.ok(admits(keyGate(), upstreamRun({ head_branch: branch, conclusion: "failure" })), branch);
  }
  for (const branch of ["main", "gh-readonly-queue/main/pr-123-0123456789abcdef0123456789abcdef01234567"]) {
    assert.ok(!triggers(branch), branch);
  }
  // What the trigger still admits but pr-verify does not judge, the gate skips.
  assert.ok(!admits(keyGate(), upstreamRun({ conclusion: "cancelled" })));
  assert.ok(!admits(keyGate(), upstreamRun({ event: "push" })));
  assert.ok(!admits(keyGate(), upstreamRun({ head_repository: { full_name: "someone/fork" } })));
});

test("the subscription job runs only on a clean handoff or an empty key, on a fixed runner", () => {
  const job = jobText(SUB);
  assert.match(job, /^ {4}needs: check-intent$/m);
  const gate = /^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(job)?.[1].replace(/\s+/g, " ").trim();
  assert.equal(
    gate,
    [
      "github.ref == 'refs/heads/main'",
      "&& github.event.workflow_run.event == 'pull_request'",
      "&& (github.event.workflow_run.conclusion == 'success' || github.event.workflow_run.conclusion == 'failure')",
      "&& github.event.workflow_run.head_repository.full_name == github.repository",
      "&& ((needs.check-intent.outputs.handoff == 'true'",
      "&& needs.check-intent.outputs.key-leg-clean == 'true')",
      "|| needs.check-intent.outputs.credential-present == 'false')",
    ].join(" "),
  );
  // No status function, so GitHub adds success(): a failed key job skips it.
  assert.doesNotMatch(gate, /always\(\)|failure\(\)|cancelled\(\)|success\(\)/);
  assert.match(job, /^ {4}runs-on: ubuntu-24\.04$/m);
  // The key job's outputs reach only that if, the resolver's env and the
  // record's fallback reason, which they pick between three literals; never a
  // run: script.
  const steps = job.slice(job.indexOf("\n    steps:\n"));
  assert.deepEqual(
    steps.split("\n").filter((line) => line.includes("needs.")),
    [CARRIED, ...Array(SLOTS.length + 1).fill(`          fallback-reason: ${FALLBACK_REASON}`)],
  );
  const key = jobText(KEY);
  const outputs = /^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(key)?.[1];
  assert.equal(
    outputs,
    [
      `      lane-class: \${{ ${chainOf((id) => `steps.${id}.outputs.lane-class`, "judge")} }}`,
      `      handoff: \${{ ${chainOf((id) => `steps.${id}.outputs.handoff == 'true'`, "judge")} }}`,
      "      credential-present: ${{ steps.credential.outputs.present }}",
      `      key-leg-clean: \${{ ${chainOf((id) => `steps.${id}.outputs.clean`, "key-leg")} }}`,
      "      reads: ${{ steps.carry.outputs.reads }}",
      "",
    ].join("\n"),
  );
  // The fallback job reads these: each a launcher output set after the step
  // files are restored, or the denial check's.
  assert.equal(
    /^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(job)?.[1],
    [
      `      handoff: \${{ ${chainOf((id) => `steps.${id}.outputs.handoff == 'true'`, "judge")} }}`,
      `      handoff-reason: \${{ ${chainOf((id) => `steps.${id}.outputs.handoff-reason`, "judge")} }}`,
      `      leg-clean: \${{ ${chainOf((id) => `steps.${id}.outputs.clean`, "sub-leg")} }}`,
      "",
    ].join("\n"),
  );
  assert.doesNotMatch(jobText(FB), /^ {4}outputs:/m);
  for (const id of JOBS) {
    assert.match(jobText(id), /^ {4}permissions:\n {6}contents: read #.*\n {6}pull-requests: read #.*\n {6}actions: read #.*\n {4}[a-z]/m, id);
  }
});

test("the fallback job runs only on the subscription job's clean handoff, on a fixed runner", () => {
  const job = jobText(FB);
  assert.match(job, /^ {4}needs: check-intent-subscription$/m);
  const gate = /^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(job)?.[1].replace(/\s+/g, " ").trim();
  // One hop: an empty subscription token is the subscription job's red,
  // never a reason to run the fallback (the reusables gate on handoff alone).
  assert.equal(
    gate,
    [
      "github.ref == 'refs/heads/main'",
      "&& github.event.workflow_run.event == 'pull_request'",
      "&& (github.event.workflow_run.conclusion == 'success' || github.event.workflow_run.conclusion == 'failure')",
      "&& github.event.workflow_run.head_repository.full_name == github.repository",
      "&& needs.check-intent-subscription.outputs.handoff == 'true'",
      "&& needs.check-intent-subscription.outputs.leg-clean == 'true'",
    ].join(" "),
  );
  assert.doesNotMatch(gate, /always\(\)|failure\(\)|cancelled\(\)|success\(\)/);
  assert.match(job, /^ {4}runs-on: ubuntu-24\.04$/m);
  const steps = job.slice(job.indexOf("\n    steps:\n"));
  assert.deepEqual(
    steps.split("\n").filter((line) => line.includes("needs.")),
    Array(SLOTS.length + 1).fill(`          fallback-reason: ${FB_REASON}`),
  );
});

test("the subscription job hands the judgment on only after a clean handoff, and only with the fallback token set", () => {
  const credential = step("Check the credential", SUB);
  assert.ok(credential.split("\n").includes(FALLBACK_PRESENT));
  assert.ok(credential.includes(FALLBACK_READY));
  assert.equal(input(step("Judge the pull request", SUB), "fallback-ready"), "${{ steps.credential.outputs.fallback-ready }}");
  assert.equal(input(step("Judge the pull request", KEY), "fallback-ready"), undefined);
  const leg = step("Check the subscription leg", SUB);
  assert.match(leg, /^ {8}id: sub-leg$/m);
  assert.match(leg, /^ {8}if: steps\.judge\.outputs\.handoff == 'true'$/m);
  assert.match(leg, /^ {8}continue-on-error: true$/m);
  assert.match(leg, /^ {12}\$\{\{ steps\.judge\.outputs\.log-file \}\}$/m);
  assert.match(leg, /write-verdict\.mjs check-key-leg\n/);
  const run = /^ {8}run: \|\n((?: {10}.*\n?)+)/m.exec(leg)[1];
  assert.doesNotMatch(run, /\$\{\{/);
  assert.ok(index("Check the subscription leg", SUB) === index("Judge the pull request", SUB) + 1);
  assert.ok(index("Report the judgment's outcome", SUB) === index("Check the subscription leg", SUB) + 1);
  assert.equal(index("Check the subscription leg", KEY), -1);
  assert.equal(index("Check the subscription leg", FB), -1);
});

test("the key job hands the judgment on only after a clean handoff or with no key", () => {
  const leg = step("Check the key leg");
  // run-claude-cli's handoff: a credit stop, or auth with API status 401 or
  // 402; a 403 is auth too but hands nothing off, so it fails the key job.
  assert.match(leg, /^ {8}if: steps\.judge\.outputs\.handoff == 'true'$/m);
  assert.match(leg, /^ {12}\$\{\{ steps\.judge\.outputs\.log-file \}\}$/m);
  assert.match(leg, /^ {10}LANE_CLASS: \$\{\{ steps\.judge\.outputs\.lane-class \}\}$/m);
  assert.match(leg, /write-verdict\.mjs check-key-leg\n/);
  // It runs before the report, which reads its outcome, and its failure
  // leaves the red to "Fail without a verdict" after the report.
  assert.match(leg, /^ {8}continue-on-error: true$/m);
  assert.ok(index("Check the key leg") === index("Judge the pull request") + 1);
  assert.ok(index("Report the judgment's outcome") === index("Check the key leg") + 1);
  // The owner's signal to replace the key (auth) or rotate one in (a credit
  // stop), printed before the denial check can stop the step. The class
  // reaches the script through env, never interpolated.
  const run = /^ {8}run: \|\n((?: {10}.*\n?)+)/m.exec(leg)[1];
  assert.equal(run.split("\n")[0], '          case "$LANE_CLASS" in');
  assert.match(run, /^ {12}auth\) echo "::warning::the API refused the pr-verify role's API key \(PR_VERIFY_CLAUDE_API_KEY\), class auth; the owner must replace the secret" ;;$/m);
  assert.match(run, /^ {12}\*\) echo "::warning::the pr-verify role's API key \(PR_VERIFY_CLAUDE_API_KEY\) hit a credit stop; rotate a spare key in" ;;$/m);
  assert.doesNotMatch(run, /\$\{\{/);
  assert.ok(run.lastIndexOf("::warning::") < run.indexOf("check-key-leg"));
  assert.equal(index("Check the key leg", SUB), -1);
  assert.equal(index("Check the key leg", FB), -1);
  for (const job of JOBS) {
    const credential = step("Check the credential", job);
    assert.match(credential, /^ {8}if: steps\.agree\.outcome == 'success'$/m, job);
    assert.match(credential, new RegExp(`^ {10}PRESENT: \\$\\{\\{ secrets\\.${CREDENTIAL[job][1]} != '' \\}\\}$`, "m"), job);
    assert.ok(index("Check the credential", job) < index("Judge the pull request", job), job);
  }
});

test("the subscription job repeats the key job's steps but for the credential", () => {
  // Each difference the two-job pattern needs, normalized away on the key
  // job's side; everything else, the gates and hardening included, matches.
  const PLAIN_REPORT_IF = "if: steps.judge.outcome == 'success' || steps.judge.outcome == 'failure'";
  const lines = (block) =>
    block
      .split("\n")
      .filter((line) => line.trim() !== "" && !line.trim().startsWith("#"))
      .join("\n");
  const normalize = (blocks) =>
    blocks
      .filter((s) => !s.name.startsWith("Check the key leg") && !s.name.startsWith("Check the subscription leg") && s.name !== "Hand the reads on")
      .map((s) =>
        lines(s.block)
          .replace(`\n${CARRY_ENV.join("\n")}`, "")
          .replace(`if: steps.agree.outcome == 'success'${NOT_CARRIED}`, "if: steps.agree.outcome == 'success'")
          .replace(`\n${FALLBACK_PRESENT}`, "")
          .replace(`\n${FALLBACK_READY}`, "")
          .replace("\n          fallback-ready: ${{ steps.credential.outputs.fallback-ready }}", "")
          .replace(/PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN/g, "PR_VERIFY_CLAUDE_API_KEY")
          .replace(/^( {10})subscription-token: /m, "$1api-key: ")
          .replace(/if: \(steps\.(judge(?:-\d+|-spec)?)\.outcome == 'success' \|\| steps\.\1\.outcome == 'failure'\) && \(steps\.\1\.outputs\.handoff != 'true' \|\| steps\.(?:key|sub)-leg(?:-\d+|-spec)?\.outcome == 'failure'\)/, "if: steps.$1.outcome == 'success' || steps.$1.outcome == 'failure'")
          .replace(/known-failure-class: \$\{\{ steps\.(judge(?:-\d+|-spec)?)\.outputs\.lane-class == 'credit-stop' && 'rate-limit' \|\| steps\.\1\.outputs\.lane-class \}\}/, "known-failure-class: ${{ steps.$1.outputs.lane-class }}")
          .replace(`\n          fallback-reason: ${FALLBACK_REASON}`, "")
          .replace(/ && steps\.credential\.outputs\.present != 'false'/, "")
          .replace(/(?: && steps\.(?:key|sub)-leg(?:-\d+|-spec)?\.outcome != 'success')+$/m, ""),
      );
  assert.deepEqual(normalize(STEPS[SUB]), normalize(STEPS[KEY]));
  // The fallback job reads everything again, as the key job does; its
  // credential step reads the fallback token where the subscription job's
  // reads the role's.
  const fallback = STEPS[FB].map((s) => ({
    ...s,
    block: s.block
      .replace(`PRESENT: \${{ secrets.${FALLBACK} != '' }}\n          SECRET_NAME: ${FALLBACK}`, "PRESENT: ${{ secrets.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN != '' }}\n          SECRET_NAME: PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN")
      .replace(`fallback-token: \${{ secrets.${FALLBACK} }}`, "subscription-token: ${{ secrets.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN }}")
      .replace(`\n          fallback-reason: ${FB_REASON}`, `\n          fallback-reason: ${FALLBACK_REASON}`),
  }));
  assert.deepEqual(normalize(fallback), normalize(STEPS[KEY]));
});

// check-intent hands its reads on only from steps that finish before the
// model runs, and the subscription job takes them only through env, then
// still runs the trigger gate, whose head the agree step compares.
test("the subscription job takes check-intent's pre-judge reads and still runs the trigger gate", () => {
  const carry = step("Hand the reads on");
  assert.ok(index("Hand the reads on") > index("Select the trusted PR text"), "after the trusted text");
  assert.ok(index("Hand the reads on") > index("Assert the gate and the resolver agree"));
  assert.ok(index("Hand the reads on") < index("Judge the pull request"), "before the model");
  assert.match(carry, /^ {8}if: steps\.agree\.outcome == 'success'$/m);
  assert.match(carry, /^ {8}continue-on-error: true$/m);
  assert.match(carry, /^ {8}run: node \.base\/\.github\/scripts\/pr-verify\/resolve-pr\.mjs carry$/m);
  for (const expression of carry.match(/\$\{\{[^}]*\}\}/g)) {
    assert.match(expression, /^\$\{\{ (steps\.pr\.outputs\.[a-z-]+|github\.workspace) \}\}$/, expression);
  }
  // Every key job output comes from a step before the judge or from the
  // launcher's and the key-leg check's own outputs.
  const outputs = /^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(jobText(KEY))[1];
  assert.match(outputs, /^ {6}reads: \$\{\{ steps\.carry\.outputs\.reads \}\}$/m);
  const resolve = step("Resolve the pull request", SUB);
  for (const line of CARRY_ENV) assert.ok(resolve.split("\n").includes(line), line);
  assert.doesNotMatch(/^ {8}run: \|\n((?: {10}.*\n?)+)/m.exec(resolve)[1], /\$\{\{/);
  assert.equal(/^ {8}if: (.*)$/m.exec(step("Select the trusted PR text", SUB))[1], `steps.agree.outcome == 'success'${NOT_CARRIED}`);
  for (const name of ["Check the trigger", "Assert the gate and the resolver agree", "Write the diff"]) {
    assert.doesNotMatch(step(name, SUB), /carried/, name);
  }
  for (const job of [KEY, FB]) {
    assert.doesNotMatch(jobText(job), /CARRIED|outputs\.carried/, job);
  }
  assert.equal(index("Hand the reads on", SUB), -1);
  assert.equal(index("Hand the reads on", FB), -1);
});

test("the model reads only the data directory, with Read alone, and is told never to quote a credential", () => {
  for (const job of JOBS) {
    const judge = step("Judge the pull request", job);
    assert.equal(input(judge, "tools"), "Read", job);
    assert.equal(input(judge, "allowed-tools"), "Read(./pr-verify-data/**)", job);
    const denied = list(judge, "disallowed-tools");
    for (const rule of ["Read(./.base/**)", "Glob", "Grep", "Bash", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch", "Agent", "mcp__*"]) {
      assert.ok(denied.includes(rule), `${job}: disallowed-tools holds ${rule}`);
    }
    const preamble = /^ {10}preamble: >-\n((?: {12}.*\n)+)/m.exec(judge)?.[1].replace(/\s+/g, " ").trim();
    assert.match(preamble ?? "", /unattended/, job);
    assert.match(preamble ?? "", /never quote a credential/, job);
  }
});

// The README's "Verifier verdict" section: each judging job lists the jobs of
// the pr-require-checks run it was started by in pr-verify-data, read with the
// job's own token after the gate, and the prompt names that file; the model
// still reads that directory alone.
test("each job writes the upstream run's jobs into the data directory the prompt names", () => {
  for (const job of JOBS) {
    const listing = step("List the upstream run's jobs", job);
    assert.equal(/^ {8}if: (.*)$/m.exec(listing)[1], "steps.agree.outcome == 'success'", job);
    assert.ok(index("List the upstream run's jobs", job) > index("Assert the gate and the resolver agree", job), job);
    assert.ok(index("List the upstream run's jobs", job) < index("Write the prompt and schema", job), job);
    assert.equal(input(listing, "GITHUB_TOKEN"), "${{ github.token }}", job);
    assert.equal(input(listing, "UPSTREAM_RUN_ID"), "${{ github.event.workflow_run.id }}", job);
    assert.equal(input(listing, "JOBS_FILE"), "${{ github.workspace }}/pr-verify-data/upstream-jobs.json", job);
    // The head's tree, written by the diff step from its blobless fetch, outside the data directory.
    const diff = step("Write the diff", job);
    assert.equal(input(listing, "HEAD_PATHS_FILE"), "${{ runner.temp }}/pr-verify-head-paths", job);
    assert.equal(input(diff, "HEAD_PATHS_FILE"), input(listing, "HEAD_PATHS_FILE"), job);
    assert.ok(diff.includes('git -C "$SRC" ls-tree -r -z --name-only "$HEAD_SHA" >"$HEAD_PATHS_FILE"\n'), job);
    assert.ok(index("Write the diff", job) < index("List the upstream run's jobs", job), job);
    assert.match(listing, /^ {8}run: node \.base\/\.github\/scripts\/pr-verify\/upstream-jobs\.mjs$/m, job);
    assert.ok(step("Write the prompt and schema", job).includes("            prompt=${prompt//JOBS_FILE/$DATA/upstream-jobs.json}\n"), job);
    assert.equal(input(step("Judge the pull request", job), "allowed-tools"), "Read(./pr-verify-data/**)", job);
  }
  assert.ok(readFileSync(new URL("./prompt.md", import.meta.url), "utf8").includes("- `JOBS_FILE`: "));
});

test("every data path the model reads sits under the working directory", () => {
  assert.doesNotMatch(text, /runner\.temp \}\}\/pr-verify-data/);
  for (const job of JOBS) {
    for (const name of ["Resolve the pull request", "Select the trusted PR text", "Write the diff", "List the upstream run's jobs", "Write the prompt and schema", "Write the verdict"]) {
      assert.match(step(name, job), /\$\{\{ github\.workspace \}\}\/pr-verify-data/, `${job}: ${name}`);
    }
  }
});

test("each job checks out main fresh and writes the managed settings before isolating the runner", () => {
  for (const job of JOBS) {
    assert.equal(STEPS[job][0].name, "Check out the default branch tip", job);
    assert.match(STEPS[job][0].block, /^ {10}ref: refs\/heads\/main$/m, job);
    assert.match(STEPS[job][0].block, /^ {10}persist-credentials: false$/m, job);
    const settings = step("Apply the Claude managed settings", job);
    assert.equal(PIN.exec(/^ {8}uses: (.*)$/m.exec(settings)[1])?.[1], "apply-claude-managed-settings", job);
    assert.match(settings, /^ {8}if: steps\.agree\.outcome == 'success'$/m, job);
    assert.ok(index("Apply the Claude managed settings", job) < index("Isolate the runner", job), job);
    assert.ok(index("Isolate the runner", job) < index("Judge the pull request", job), job);
  }
});

test("the outcome is reported whenever a judge ran to a final class, and a missing verdict fails the job last", () => {
  for (const job of JOBS) {
    const report = step("Report the judgment's outcome", job);
    assert.equal(PIN.exec(/^ {8}uses: (.*)$/m.exec(report)[1])?.[1], "report-lane-outcome", job);
    assert.ok(index("Report the judgment's outcome", job) === index("Judge the pull request", job) + (job === FB ? 1 : 2), job);
    assert.equal(input(report, "credential"), "${{ steps.judge.outputs.credential }}", job);

    assert.equal(input(report, "step-timeout-minutes"), "22", job);
    // The start time is taken right before the judge, so a timeout is told from other failures.
    assert.equal(input(report, "step-started-at"), "${{ steps.prompt.outputs.started-at }}", job);
    assert.ok(index("Write the prompt and schema", job) === index("Judge the pull request", job) - 1, job);
    assert.equal(STEPS[job].at(-1).name, "Fail without a verdict", job);
    assert.match(STEPS[job].at(-1).block, /exit 1/, job);
  }
  assert.equal(/^ {8}if: (.*)$/m.exec(step("Report the judgment's outcome", SUB))[1], SUB_REPORT_IF);
  assert.match(step("Report the judgment's outcome", FB), /^ {8}if: steps\.judge\.outcome == 'success' \|\| steps\.judge\.outcome == 'failure'$/m);
  for (const job of [SUB, FB]) {
    assert.equal(input(step("Report the judgment's outcome", job), "known-failure-class"), "${{ steps.judge.outputs.lane-class }}", job);
    assert.equal(input(step("Report the judgment's outcome", job), "lane"), "pr-verify", job);
  }
  assert.equal(input(step("Report the judgment's outcome", SUB), "fallback-reason"), FALLBACK_REASON);
  assert.equal(input(step("Report the judgment's outcome", FB), "fallback-reason"), FB_REASON);
  // Only a hand-off spares the key job its red; an empty token fails the subscription job.
  assert.match(
    STEPS[KEY].at(-1).block,
    new RegExp(`^ {8}if: always\\(\\) && steps\\.agree\\.outcome == 'success' && steps\\.verdict\\.outcome != 'success' && steps\\.credential\\.outputs\\.present != 'false' && ${legsClear("key-leg")}$`, "m"),
  );
  assert.match(
    STEPS[SUB].at(-1).block,
    new RegExp(`^ {8}if: always\\(\\) && steps\\.agree\\.outcome == 'success' && steps\\.verdict\\.outcome != 'success' && ${legsClear("sub-leg")}$`, "m"),
  );
  assert.match(STEPS[FB].at(-1).block, /^ {8}if: always\(\) && steps\.agree\.outcome == 'success' && steps\.verdict\.outcome != 'success'$/m);
});

test("a handoff leaves exactly one lane record, from the job that saw its end", () => {
  const report = step("Report the judgment's outcome", KEY);
  assert.equal(/^ {8}if: (.*)$/m.exec(report)[1], KEY_REPORT_IF);
  assert.equal(input(report, "lane"), "pr-verify");
  assert.equal(input(report, "fallback-reason"), undefined);
  // A key leg that is not clean hands nothing on, so the key job records the
  // stop itself: a credit stop as rate-limit, the class report-lane-outcome
  // knows for it, and auth as auth.
  assert.equal(input(report, "known-failure-class"), KEY_CLASS);
  // A clean handoff skips this report; the subscription job, which runs
  // exactly when key-leg-clean is true, records the run with a plain lane
  // name and says why in fallback-reason, one of report-lane-outcome's
  // credit-stop, auth or no-key.
  assert.match(jobText(SUB), /needs\.check-intent\.outputs\.key-leg-clean == 'true'/);
  assert.deepEqual([...FALLBACK_REASON.matchAll(/&& '([a-z-]+)'/g)].map((m) => m[1]), ["credit-stop", "auth", "no-key"]);
  assert.match(FALLBACK_REASON, /lane-class == 'auth' && 'auth'/);
  // A clean subscription handoff skips the subscription job's report the
  // same way; the fallback job, which runs exactly when leg-clean is true,
  // records the run with report-lane-outcome's limit-stop, credit-stop or auth.
  assert.match(jobText(FB), /needs\.check-intent-subscription\.outputs\.leg-clean == 'true'/);
  assert.deepEqual([...FB_REASON.matchAll(/&& '([a-z-]+)'/g)].map((m) => m[1]), ["limit-stop", "credit-stop", "auth"]);
  // No gate keys the subscription leg on the credit-stop class any more:
  // run-claude-cli's handoff output is the one signal.
  for (const line of text.split("\n").filter((l) => /^\s+(- )?if: /.test(l) || /^\s+&& /.test(l))) {
    assert.doesNotMatch(line, /lane-class [!=]= 'credit-stop'/, line);
  }
});

test("every ci-workflows action is pinned to one commit, report-lane-outcome to its own", () => {
  const all = [...text.matchAll(/uses: melodic-software\/ci-workflows\/([^@\s]+)@([0-9a-f]{40}) # \S.*$/gm)].map((m) => ({ action: m[1], sha: m[2] }));
  assert.equal(all.length, (text.match(/melodic-software\/ci-workflows\//g) ?? []).length, "every ref is a SHA pin with a comment");
  const isReport = (r) => r.action.endsWith("/report-lane-outcome");
  const refs = all.filter((r) => !isReport(r)).map((r) => r.sha);
  const reportRefs = all.filter(isReport).map((r) => r.sha);
  assert.ok(refs.length >= 6);
  assert.equal(new Set(refs).size, 1, `one pin: ${[...new Set(refs)].join(", ")}`);
  assert.equal(new Set(reportRefs).size, 1, `one report-lane-outcome pin: ${[...new Set(reportRefs)].join(", ")}`);
});

test("the resolver reads the trusted-actor list from main in both jobs", () => {
  for (const job of JOBS) {
    const block = step("Resolve the pull request", job);
    assert.match(block, /TRUSTED_ACTORS_PATH: \.base\/\.github\/standards\/trusted-actors\/trusted-actors\.json\n/, job);
    assert.match(block, /SPEC_FROM_BODY_APPS=\$\(yq '\.adoption\."spec-from-body-apps" \/\/ \[\] \| \.\[\]' \.base\/docs\/conventions\/pr-pipeline\.yaml\)\n/, job);
    // The issue lane's web hosts, as admission reads them, so a split record holds under the same hosts.
    assert.match(block, /ISSUE_LANE_WEB_HOSTS=\$\(yq -o=json -I=0 '\(\.activities\."resolve-issue"\."web-access" \| select\(\.enabled == true\) \| \.domains\) \/\/ \[\]' \.base\/docs\/conventions\/pr-pipeline\.yaml\)\n/, job);
    assert.match(block, /export VERIFY_AUTHORS LANE_IDENTITY SPEC_FROM_BODY_APPS ISSUE_LANE_WEB_HOSTS\n/, job);
    assert.match(step("Write the verdict", job), /SPEC_TEXT_FILE: \$\{\{ github\.workspace \}\}\/pr-verify-data\/spec-text\.json\n/, job);
  }
});

const judgeSpec = (job) => step("Judge the whole spec", job);
const SPEC_IF = "fromJSON(steps.diff.outputs.chunks || '0') > 1 && steps.chunk-results.outcome == 'success'";
const judgeId = (k) => (k === 1 ? "judge" : `judge-${k}`);
const suffix = (k) => (k === 1 ? "" : `-${k}`);
const judgeName = (k) => (k === 1 ? "Judge the pull request" : `Judge chunk ${k}`);
const legName = { [KEY]: "Check the key leg", [SUB]: "Check the subscription leg" };
const legId = { [KEY]: "key-leg", [SUB]: "sub-leg" };
const chain = (build) => [...SLOTS.map(build), build("spec")].join(" || ");

test("the chunk ceiling is set once, in chunk-diff.sh, and a 3 MB diff fits under it", () => {
  assert.ok(Number.isInteger(CEILING), "chunk-diff.sh sets MAX_CHUNKS");
  assert.doesNotMatch(text, /MAX_CHUNKS: /, "no step sets its own");
  // 3 MB of whole files in chunks of MAX_DIFF_BYTES (chunk-diff.test.mjs splits one).
  const chunkBytes = Number(input(step("Write the diff"), "MAX_DIFF_BYTES").replaceAll('"', ""));
  assert.ok(CEILING * chunkBytes >= 3000000, `${CEILING} chunks of ${chunkBytes} bytes`);
});

test("every job has one judge step per chunk, each repeating the first but for its chunk", () => {
  for (const job of JOBS) {
    const first = step("Judge the pull request", job);
    assert.equal(STEPS[job].filter((s) => /^ {8}uses: melodic-software\/ci-workflows\/\.github\/actions\/run-claude-cli@/m.test(s.block)).length, SLOTS.length + 1, job);
    // The ceiling is chunk-diff.sh's; no step sets its own.
    assert.equal(input(step("Write the diff", job), "MAX_CHUNKS"), undefined, job);
    assert.equal(input(first, "prompt-file"), "${{ runner.temp }}/pr-verify-prompt-1.md", job);
    const bare = (block) => block.split("\n").filter((line) => !line.trim().startsWith("#")).filter((line) => !/^ +(- )?(name|id|if): /.test(line)).join("\n").trim();
    for (const k of SLOTS.slice(1)) {
      const judge = step(judgeName(k), job);
      assert.equal(/^ {8}id: (.*)$/m.exec(judge)[1], judgeId(k), job);
      assert.equal(bare(judge), bare(first).replace("pr-verify-prompt-1.md", `pr-verify-prompt-${k}.md`), `${job} chunk ${k}`);
      const previous = judgeId(k - 1);
      assert.equal(
        /^ {8}if: (.*)$/m.exec(judge)[1],
        `steps.credential.outputs.present == 'true' && fromJSON(steps.diff.outputs.chunks || '0') >= ${k} && steps.${previous}.outcome == 'success' && steps.${previous}.outputs.handoff != 'true' && steps.chunk-fail${suffix(k - 1)}.outputs.fail != 'true'`,
        `${job} chunk ${k}`,
      );
      const report = step(`Report chunk ${k}'s outcome`, job);
      assert.equal(input(report, "outcome"), `\${{ steps.${judgeId(k)}.outcome }}`, job);
      assert.equal(input(report, "step-started-at"), `\${{ steps.time-${k}.outputs.started-at }}`, job);
      assert.equal(input(step(`Upload chunk ${k}'s sealed transcript`, job), "job-id"), `\${{ github.job }}-${k}`, job);
    }
    // 22 minutes a judge step and 15 for the rest of the job.
    const judges = [...jobText(job).matchAll(/^ {8}timeout-minutes: 22$/gm)].length;
    assert.equal(judges, SLOTS.length + 1, job);
    assert.equal(Number(/^ {4}timeout-minutes: (\d+)$/m.exec(jobText(job))[1]), judges * 22 + 15, job);
  }
});

// A step run-claude-cli failed with no lane class, having left an execution
// file, stopped on its credential scan, so its fail is still a judgment;
// write-verdict counts nothing else of it. A step that timed out or never
// started the CLI leaves that file empty and skips the verdict for a re-run.
const judged = (id) => `(steps.${id}.outcome == 'success' || (steps.${id}.outcome == 'failure' && steps.${id}.outputs.lane-class == '' && steps.${id}.outputs.execution-file != ''))`;

test("the verdict needs every chunk the diff has, and reads each chunk's files", () => {
  for (const job of JOBS) {
    const verdict = step("Write the verdict", job);
    assert.equal(
      /^ {8}if: (.*)$/m.exec(verdict)[1],
      `\${{ !cancelled() && (${SLOTS.map((k) => `steps.chunk-fail${suffix(k)}.outputs.fail == 'true'`).join(" || ")} || steps.chunk-results.outcome == 'failure' || (${["steps.judge.outcome == 'success'", ...SLOTS.slice(1).map((k) => `(fromJSON(steps.diff.outputs.chunks || '0') < ${k} || steps.${judgeId(k)}.outcome == 'success')`), `(fromJSON(steps.diff.outputs.chunks || '0') < 2 || ${judged("judge-spec")})`].join(" && ")})) }}`,
      job,
    );
    for (const k of SLOTS) {
      assert.ok(verdict.includes(`            \${{ steps.${judgeId(k)}.outputs.execution-file }}\n`), `${job} execution ${k}`);
      assert.ok(verdict.includes(`            \${{ steps.${judgeId(k)}.outputs.log-file }}\n`), `${job} log ${k}`);
    }
    assert.equal(input(verdict, "CHUNKS"), "${{ steps.diff.outputs.chunks }}", job);
    assert.equal(input(verdict, "DIFF_DIR"), "${{ github.workspace }}/pr-verify-data/diff", job);
    assert.match(step("Write the diff", job), /^ {8}id: diff$/m, job);
    assert.match(step("Write the diff", job), /bash \.base\/\.github\/scripts\/pr-verify\/chunk-diff\.sh\n/, job);
  }
});

test("a handoff from any chunk hands the whole judgment on, and a denial in any chunk stops it", () => {
  for (const job of [KEY, SUB]) {
    for (const k of SLOTS) {
      const name = k === 1 ? legName[job] : `${legName[job]}, chunk ${k}`;
      const leg = step(name, job);
      assert.match(leg, new RegExp(`^ {8}id: ${legId[job]}${k === 1 ? "" : `-${k}`}$`, "m"), job);
      assert.match(leg, new RegExp(`^ {8}if: steps\\.${judgeId(k)}\\.outputs\\.handoff == 'true'$`, "m"), job);
      for (const earlier of SLOTS.slice(0, k)) {
        assert.ok(leg.includes(`            \${{ steps.${judgeId(earlier)}.outputs.log-file }}\n`), `${job} chunk ${k} reads chunk ${earlier}'s log`);
      }
    }
  }
  const outputs = (job) => /^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(jobText(job))[1];
  const id = (k) => (k === "spec" ? "judge-spec" : judgeId(k));
  const leg = (k) => (k === "spec" ? "-spec" : suffix(k));
  const handoff = `      handoff: \${{ ${chain((k) => `steps.${id(k)}.outputs.handoff == 'true'`)} }}\n`;
  assert.ok(outputs(KEY).includes(handoff));
  assert.ok(outputs(SUB).includes(handoff));
  assert.ok(outputs(KEY).includes(`      lane-class: \${{ ${chain((k) => `steps.${id(k)}.outputs.lane-class`)} }}\n`));
  assert.ok(outputs(KEY).includes(`      key-leg-clean: \${{ ${chain((k) => `steps.key-leg${leg(k)}.outputs.clean`)} }}\n`));
  assert.ok(outputs(SUB).includes(`      handoff-reason: \${{ ${chain((k) => `steps.${id(k)}.outputs.handoff-reason`)} }}\n`));
  assert.ok(outputs(SUB).includes(`      leg-clean: \${{ ${chain((k) => `steps.sub-leg${leg(k)}.outputs.clean`)} }}\n`));
});

test("the prompt step gives each chunk its own parts, and a lone chunk no note", () => {
  const run = /^ {8}run: \|\n((?: {10}.*\n?| *\n)+)/m.exec(step("Write the prompt and schema"))[1].replace(/^ {10}/gm, "");
  const write = (chunks, parts) => {
    const cwd = tempDir("pr-verify-prompt-");
    const scripts = path.join(cwd, ".base/.github/scripts/pr-verify");
    mkdirSync(scripts, { recursive: true });
    for (const name of ["prompt.md", "chunk-note.md"]) cpSync(new URL(`../pr-verify/${name}`, import.meta.url), path.join(scripts, name));
    for (const [k, count] of parts.entries()) {
      mkdirSync(path.join(cwd, `data/diff/chunk-${k + 1}`), { recursive: true });
      for (let n = 1; n <= count; n += 1) writeFileSync(path.join(cwd, `data/diff/chunk-${k + 1}/part-00${n}.patch`), "x\n");
    }
    if (chunks > 1) {
      mkdirSync(path.join(cwd, "data/manifest"));
      for (const name of ["part-001.txt", "part-002.txt"]) writeFileSync(path.join(cwd, "data/manifest", name), "x\n");
    }
    const result = spawnSync("bash", ["-euo", "pipefail", "-c", run], {
      cwd,
      encoding: "utf8",
      env: { PATH: process.env.PATH, DATA: path.join(cwd, "data"), MODEL: "opus", CHUNKS: String(chunks), PROMPT_STEM: path.join(cwd, "prompt"), SCHEMA_FILE: path.join(cwd, "schema"), GITHUB_OUTPUT: path.join(cwd, "output") },
    });
    assert.equal(result.status, 0, result.stderr);
    return { cwd, prompt: (k) => readFileSync(path.join(cwd, `prompt-${k}.md`), "utf8") };
  };
  const { cwd, prompt } = write(2, [2, 1]);
  assert.ok(prompt(1).includes(`  - \`${cwd}/data/diff/chunk-1/part-001.patch\`\n  - \`${cwd}/data/diff/chunk-1/part-002.patch\`\n- `));
  assert.ok(prompt(1).includes(`  - \`${cwd}/data/manifest/part-001.txt\`\n  - \`${cwd}/data/manifest/part-002.txt\``));
  assert.ok(!prompt(1).includes("chunk-2/part"));
  assert.match(prompt(1), /chunk 1 of 2/);
  assert.match(prompt(2), /chunk 2 of 2/);
  assert.ok(prompt(2).includes(`chunk-2/part-001.patch`));
  // Past nine chunks, each chunk still gets its own prompt and parts.
  const many = write(12, Array.from({ length: 12 }, () => 1));
  assert.match(many.prompt(12), /chunk 12 of 12/);
  assert.ok(many.prompt(12).includes(`  - \`${many.cwd}/data/diff/chunk-12/part-001.patch\`\n`));
  assert.ok(!many.prompt(12).includes("chunk-1/part"));
  assert.ok(many.prompt(10).includes(`chunk-10/part-001.patch`));
  const one = write(1, [1]);
  assert.ok(!one.prompt(1).includes("data/manifest"));
  assert.ok(prompt(1).includes(`${cwd}/data/diff/chunk-N`) || prompt(1).includes(`relative to \`${cwd}/data\``));
  for (const text of [prompt(1), prompt(2), one.prompt(1)]) {
    assert.doesNotMatch(text, /DIFF_PARTS|CHUNK_NOTE|CHUNK_INDEX|CHUNK_COUNT|DATA_DIR|MANIFEST_PARTS|SPEC_FILE|SPEC_TEXT_FILE|PR_FILE|CONTEXT_FILE|JOBS_FILE/);
  }
});

test("the whole-spec step runs only on a chunked head, after every chunk, and cannot read the diff", () => {
  for (const job of JOBS) {
    const results = step("Write the chunk results", job);
    assert.equal(
      /^ {8}if: (.*)$/m.exec(results)[1],
      ["steps.credential.outputs.present == 'true' && fromJSON(steps.diff.outputs.chunks || '0') > 1 && steps.judge.outcome == 'success'", ...SLOTS.slice(1).map((k) => `(fromJSON(steps.diff.outputs.chunks || '0') < ${k} || steps.${judgeId(k)}.outcome == 'success')`), ...SLOTS.map((k) => `steps.chunk-fail${suffix(k)}.outputs.fail != 'true'`)].join(" && "),
      job,
    );
    assert.match(results, /write-verdict\.mjs chunk-results$/m, job);
    assert.doesNotMatch(results, /continue-on-error/, job);
    assert.equal(input(results, "PROMPT_FILE"), "${{ runner.temp }}/pr-verify-prompt-spec.md", job);
    assert.equal(input(results, "PROMPT_TEMPLATE"), ".base/.github/scripts/pr-verify/spec-prompt.md", job);
    assert.equal(input(results, "SCHEMA_FILE"), "${{ runner.temp }}/pr-verify-spec-schema.json", job);
    assert.equal(input(judgeSpec(job), "json-schema-file"), "${{ runner.temp }}/pr-verify-spec-schema.json", job);
    const judge = step("Judge the whole spec", job);
    assert.equal(/^ {8}id: (.*)$/m.exec(judge)[1], "judge-spec", job);
    assert.equal(/^ {8}if: (.*)$/m.exec(judge)[1], SPEC_IF, job);
    assert.equal(/^ {8}if: (.*)$/m.exec(step("Time the spec judgment", job))[1], SPEC_IF, job);
    assert.equal(input(judge, "prompt-file"), "${{ runner.temp }}/pr-verify-prompt-spec.md", job);
    assert.equal(input(judge, "tools"), "Read", job);
    assert.equal(input(judge, "allowed-tools"), "Read(./pr-verify-data/**)", job);
    const denied = list(judge, "disallowed-tools");
    assert.ok(denied.includes("Read(./pr-verify-data/diff/**)"), job);
    assert.deepEqual(denied.filter((rule) => rule !== "Read(./pr-verify-data/diff/**)"), list(step("Judge the pull request", job), "disallowed-tools"), job);
    assert.ok(index("Write the chunk results", job) > index(`Upload chunk ${SLOTS.length}'s sealed transcript`, job), job);
    assert.ok(index("Upload the spec judgment's sealed transcript", job) < index("Write the verdict", job), job);
    assert.equal(input(step("Report the spec judgment's outcome", job), "step-started-at"), "${{ steps.time-spec.outputs.started-at }}", job);
    assert.equal(input(step("Upload the spec judgment's sealed transcript", job), "job-id"), "${{ github.job }}-spec", job);
    const verdict = step("Write the verdict", job);
    assert.equal(input(verdict, "FINAL_EXECUTION_FILE"), "${{ steps.judge-spec.outputs.execution-file }}", job);
    assert.equal(input(verdict, "FINAL_LOG_FILE"), "${{ steps.judge-spec.outputs.log-file }}", job);
    assert.equal(input(verdict, "RESULTS_DIR"), "${{ github.workspace }}/pr-verify-data/chunk-results", job);
    assert.equal(input(verdict, "MANIFEST_DIR"), "${{ github.workspace }}/pr-verify-data/manifest", job);
    assert.equal(input(verdict, "CONTEXT_FILE"), undefined, job);
    assert.equal(input(verdict, "FINAL_OUTCOME"), "${{ steps.judge-spec.outcome }}", job);
    // Each chunk's step outcome, so a failed step's text is never written.
    for (const block of [verdict, results]) assert.deepEqual(list(block, "JUDGE_OUTCOMES"), SLOTS.map((k) => `\${{ steps.${judgeId(k)}.outcome }}`), job);
    // One budget: the results are cut to the size the diff's parts are.
    assert.equal(input(results, "PART_BYTES"), input(step("Write the diff", job), "PART_BYTES"), job);
  }
  for (const [job, name] of [[KEY, "Check the key leg, whole spec"], [SUB, "Check the subscription leg, whole spec"]]) {
    const leg = step(name, job);
    assert.match(leg, /^ {8}if: steps\.judge-spec\.outputs\.handoff == 'true'$/m, job);
    assert.equal(input(leg, "CHUNKS"), "${{ steps.diff.outputs.chunks }}", job);
    for (const id of [...SLOTS.map(judgeId), "judge-spec"]) assert.ok(leg.includes(`            \${{ steps.${id}.outputs.log-file }}\n`), `${job} ${id}`);
  }
});

test("after each judge a counted fail stops the slots and reaches the verdict step", () => {
  for (const job of JOBS) {
    for (const k of SLOTS) {
      const check = step(`Read chunk ${k}'s verdict`, job);
      assert.match(check, new RegExp(`^ {8}id: chunk-fail${suffix(k)}$`, "m"), job);
      assert.equal(/^ {8}if: (.*)$/m.exec(check)[1], `\${{ !cancelled() && ${judged(judgeId(k))} }}`, job);
      assert.match(check, /^ {8}continue-on-error: true$/m, job);
      assert.equal(input(check, "EXECUTION_FILE"), `\${{ steps.${judgeId(k)}.outputs.execution-file }}`, job);
      assert.equal(input(check, "JUDGE_OUTCOME"), `\${{ steps.${judgeId(k)}.outcome }}`, job);
      assert.equal(input(check, "LOG_FILE"), `\${{ steps.${judgeId(k)}.outputs.log-file }}`, job);
      assert.equal(input(check, "CHUNK"), `"${k}"`, job);
      assert.equal(input(check, "CHUNKS"), "${{ steps.diff.outputs.chunks }}", job);
      assert.equal(input(check, "DIFF_DIR"), "${{ github.workspace }}/pr-verify-data/diff", job);
      assert.equal(input(check, "MANIFEST_DIR"), "${{ github.workspace }}/pr-verify-data/manifest", job);
      assert.match(check, /write-verdict\.mjs chunk-fail$/m, job);
      const name = k === 1 ? "Judge the pull request" : `Judge chunk ${k}`;
      assert.ok(index(`Read chunk ${k}'s verdict`, job) > index(name, job), job);
      if (k < SLOTS.length) assert.ok(index(`Read chunk ${k}'s verdict`, job) < index(`Time chunk ${k + 1}`, job), job);
    }
    assert.match(step("Summarize the verdict", job), /^ {8}if: \$\{\{ !cancelled\(\) && steps\.verdict\.outcome == 'success' \}\}$/m, job);
  }
});

test("the diff is folded at the line length the review reads whole", async () => {
  const { LONG_LINE_BYTES } = await import("../pr-review-main/write-verdict.mjs");
  for (const job of JOBS) assert.equal(input(step("Write the diff", job), "LONG_LINE_BYTES"), `"${LONG_LINE_BYTES}"`, job);
});

test("the report steps only record, so a broken one cannot stop the judgment", () => {
  for (const job of JOBS) {
    const reports = STEPS[job].filter((s) => /actions\/report-lane-outcome@/.test(s.block));
    assert.equal(reports.length, SLOTS.length + 1, job);
    for (const report of reports) {
      assert.match(report.block, /^ {8}continue-on-error: true$/m, `${job} ${report.name}`);
      assert.doesNotMatch(report.block, /^ {8}id: /m, `${job} ${report.name}`);
    }
  }
  assert.doesNotMatch(text, /steps\.report/);
});
