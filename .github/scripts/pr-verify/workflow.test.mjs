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
import { readFileSync } from "node:fs";
import { test } from "node:test";

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
const PIN = /^melodic-software\/ci-workflows\/\.github\/actions\/([a-z-]+)@[0-9a-f]{40} # v\d+\.\d+\.\d+$/;
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

test("the upload is each job's only artifact step and follows the written verdict", () => {
  for (const job of JOBS) {
    const uploads = STEPS[job].filter((s) => /uses: actions\/upload-artifact@/.test(s.block));
    assert.deepEqual(
      uploads.map((s) => s.name),
      ["Upload the verdict"],
      job,
    );
    assert.ok(index("Judge the pull request", job) >= 0 && index("Write the verdict", job) > index("Judge the pull request", job), job);
    assert.ok(index("Upload the verdict", job) > index("Write the verdict", job), job);
    assert.match(uploads[0].block, /if: steps\.verdict\.outcome == 'success'/, job);
    // A verdict needs a judge step that succeeded, which run-claude-cli never
    // reports with a lane-class, so a credit stop writes none.
    assert.match(step("Write the verdict", job), /^ {8}if: steps\.judge\.outcome == 'success'$/m, job);
  }
  assert.doesNotMatch(text, /actions\/upload-artifact\/merge|gh api .*artifacts.* -X (POST|PUT)|actions\/download-artifact|actions\/cache/);
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
    assert.equal(input(judge, "leg-timeout-minutes"), '"10"', job);
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

test("the subscription job runs only on a clean handoff or an empty key, on a fixed runner", () => {
  const job = jobText(SUB);
  assert.match(job, /^ {4}needs: check-intent$/m);
  const gate = /^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(job)?.[1].replace(/\s+/g, " ").trim();
  assert.equal(
    gate,
    [
      "github.ref == 'refs/heads/main'",
      "&& github.event.workflow_run.event == 'pull_request'",
      "&& github.event.workflow_run.conclusion == 'success'",
      "&& github.event.workflow_run.head_repository.full_name == github.repository",
      "&& ((needs.check-intent.outputs.handoff == 'true'",
      "&& needs.check-intent.outputs.key-leg-clean == 'true')",
      "|| needs.check-intent.outputs.credential-present == 'false')",
    ].join(" "),
  );
  // No status function, so GitHub adds success(): a failed key job skips it.
  assert.doesNotMatch(gate, /always\(\)|failure\(\)|cancelled\(\)|success\(\)/);
  assert.match(job, /^ {4}runs-on: ubuntu-24\.04$/m);
  // The key job's outputs reach only that if and the record's fallback
  // reason, which they pick between three literals; never a run: script.
  const steps = job.slice(job.indexOf("\n    steps:\n"));
  assert.deepEqual(
    steps.split("\n").filter((line) => line.includes("needs.")),
    [`          fallback-reason: ${FALLBACK_REASON}`],
  );
  const key = jobText(KEY);
  const outputs = /^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(key)?.[1];
  assert.equal(
    outputs,
    [
      "      lane-class: ${{ steps.judge.outputs.lane-class }}",
      "      handoff: ${{ steps.judge.outputs.handoff }}",
      "      credential-present: ${{ steps.credential.outputs.present }}",
      "      key-leg-clean: ${{ steps.key-leg.outputs.clean }}",
      "",
    ].join("\n"),
  );
  // The fallback job reads these: each a launcher output set after the step
  // files are restored, or the denial check's.
  assert.equal(
    /^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(job)?.[1],
    [
      "      handoff: ${{ steps.judge.outputs.handoff }}",
      "      handoff-reason: ${{ steps.judge.outputs.handoff-reason }}",
      "      leg-clean: ${{ steps.sub-leg.outputs.clean }}",
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
      "&& github.event.workflow_run.conclusion == 'success'",
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
    [`          fallback-reason: ${FB_REASON}`],
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
  assert.match(leg, /^ {10}LOG_FILE: \$\{\{ steps\.judge\.outputs\.log-file \}\}$/m);
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
  assert.match(leg, /^ {10}LOG_FILE: \$\{\{ steps\.judge\.outputs\.log-file \}\}$/m);
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
      .filter((s) => s.name !== "Check the key leg" && s.name !== "Check the subscription leg")
      .map((s) =>
        lines(s.block)
          .replace(`\n${FALLBACK_PRESENT}`, "")
          .replace(`\n${FALLBACK_READY}`, "")
          .replace("\n          fallback-ready: ${{ steps.credential.outputs.fallback-ready }}", "")
          .replace(/PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN/g, "PR_VERIFY_CLAUDE_API_KEY")
          .replace(/^( {10})subscription-token: /m, "$1api-key: ")
          .replace(`if: ${KEY_REPORT_IF}`, PLAIN_REPORT_IF)
          .replace(`if: ${SUB_REPORT_IF}`, PLAIN_REPORT_IF)
          .replace(`known-failure-class: ${KEY_CLASS}`, "known-failure-class: ${{ steps.judge.outputs.lane-class }}")
          .replace(`\n          fallback-reason: ${FALLBACK_REASON}`, "")
          .replace(/ && steps\.credential\.outputs\.present != 'false' && steps\.key-leg\.outcome != 'success'$/m, "")
          .replace(/ && steps\.sub-leg\.outcome != 'success'$/m, ""),
      );
  assert.deepEqual(normalize(STEPS[SUB]), normalize(STEPS[KEY]));
  // The fallback job's credential step reads the fallback token where the
  // subscription job's reads the role's.
  const fallback = STEPS[FB].map((s) => ({
    ...s,
    block: s.block
      .replace(`PRESENT: \${{ secrets.${FALLBACK} != '' }}\n          SECRET_NAME: ${FALLBACK}`, "PRESENT: ${{ secrets.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN != '' }}\n          SECRET_NAME: PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN")
      .replace(`fallback-token: \${{ secrets.${FALLBACK} }}`, "subscription-token: ${{ secrets.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN }}")
      .replace(`\n          fallback-reason: ${FB_REASON}`, `\n          fallback-reason: ${FALLBACK_REASON}`),
  }));
  assert.deepEqual(normalize(fallback), normalize(STEPS[SUB]));
});

test("the model reads only the data directory, with Read alone, and is told nothing is posted", () => {
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
    assert.match(preamble ?? "", /nothing you write is posted/, job);
  }
});

test("every data path the model reads sits under the working directory", () => {
  assert.doesNotMatch(text, /runner\.temp \}\}\/pr-verify-data/);
  for (const job of JOBS) {
    for (const name of ["Resolve the pull request", "Select the trusted PR text", "Write the diff", "Write the prompt and schema", "Write the verdict"]) {
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
    assert.match(step("Write the verdict", job), /^ {10}EXECUTION_FILE: \$\{\{ steps\.judge\.outputs\.execution-file \}\}$/m, job);
    assert.match(step("Write the verdict", job), /^ {10}LOG_FILE: \$\{\{ steps\.judge\.outputs\.log-file \}\}$/m, job);
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
    /^ {8}if: always\(\) && steps\.agree\.outcome == 'success' && steps\.verdict\.outcome != 'success' && steps\.credential\.outputs\.present != 'false' && steps\.key-leg\.outcome != 'success'$/m,
  );
  assert.match(
    STEPS[SUB].at(-1).block,
    /^ {8}if: always\(\) && steps\.agree\.outcome == 'success' && steps\.verdict\.outcome != 'success' && steps\.sub-leg\.outcome != 'success'$/m,
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

test("every ci-workflows action is pinned to one release", () => {
  const refs = [...text.matchAll(/uses: melodic-software\/ci-workflows\/[^@\s]+@([0-9a-f]{40}) # (v\d+\.\d+\.\d+)$/gm)].map((m) => `${m[1]} ${m[2]}`);
  assert.equal(refs.length, (text.match(/melodic-software\/ci-workflows\//g) ?? []).length, "every ref is a SHA pin with its tag");
  assert.ok(refs.length >= 6);
  assert.equal(new Set(refs).size, 1, `one pin: ${[...new Set(refs)].join(", ")}`);
});

test("the resolver reads the trusted-actor list from main in both jobs", () => {
  for (const job of JOBS) {
    const block = step("Resolve the pull request", job);
    assert.match(block, /TRUSTED_ACTORS_PATH: \.base\/\.github\/standards\/trusted-actors\/trusted-actors\.json\n/, job);
    assert.match(block, /SPEC_FROM_BODY_APPS=\$\(yq '\.adoption\."spec-from-body-apps" \/\/ \[\] \| \.\[\]' \.base\/docs\/conventions\/pr-pipeline\.yaml\)\n/, job);
    assert.match(block, /export VERIFY_AUTHORS LANE_IDENTITY SPEC_FROM_BODY_APPS\n/, job);
    assert.match(step("Write the verdict", job), /SPEC_TEXT_FILE: \$\{\{ github\.workspace \}\}\/pr-verify-data\/spec-text\.json\n/, job);
    // Every verdict records the digest of the title and body this job's resolver read.
    assert.match(step("Write the verdict", job), /BODY_SHA256: \$\{\{ steps\.pr\.outputs\.body-sha256 \}\}\n/, job);
  }
});
