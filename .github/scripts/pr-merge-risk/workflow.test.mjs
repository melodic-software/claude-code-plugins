// pr-rate-merge-risk.yml's controls (#13657), pinned on the file's text:
// the run-name the arm side matches, a read-only job token, no pull request
// code, base-side scripts only, the credential in two steps alone, the
// model's tool cage, and the names the arm side reads.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { ARTIFACT_PREFIX, RATING_WORKFLOW_PATH, runTitle } from "../pr-merge/merge-risk-line.mjs";

const text = readFileSync(new URL("../../workflows/pr-rate-merge-risk.yml", import.meta.url), "utf8");
// Each step's text, by its name.
const steps = new Map(
  text
    .split(/\n(?= {6}- name: )/)
    .slice(1)
    .map((block) => [/^ {6}- name: (.+)$/m.exec(block)[1], block]),
);
const step = (name) => {
  assert.ok(steps.has(name), `no step named ${name}`);
  return steps.get(name);
};
const list = (block, key) =>
  new RegExp(`\\n {10}${key}: \\|\\n((?: {12}.+\\n)+)`)
    .exec(block)[1]
    .trim()
    .split("\n")
    .map((line) => line.trim());

test("the run-name renders as runTitle, so a run still going is found for its head", () => {
  const line = /^run-name: (.+)$/m.exec(text)[1];
  assert.equal(line, `"merge-risk #\${{ github.event.workflow_run.pull_requests[0].number || 'none' }} \${{ github.event.workflow_run.head_sha }}"`);
  const rendered = JSON.parse(line.replaceAll(/\$\{\{ github\.event\.workflow_run\.pull_requests\[0\]\.number \|\| 'none' \}\}/g, "7").replaceAll("${{ github.event.workflow_run.head_sha }}", "a".repeat(40)));
  assert.equal(rendered, runTitle(7, "a".repeat(40)));
});

test("the job token only reads, the workflow grants nothing, and one job runs", () => {
  assert.match(text, /\npermissions: \{\}\n/);
  assert.equal([...text.matchAll(/\n {2}[a-z-]+:\n {4}if:/g)].length, 1);
  assert.match(text, /\n {4}permissions:\n {6}contents: read # [^\n]+\n {6}pull-requests: read # [^\n]+\n {6}actions: read # [^\n]+\n {4}steps:/);
  assert.doesNotMatch(text, /^ +[a-z-]+: write\b/m);
  assert.doesNotMatch(text, /id-token|request-lane-token|create-github-app-token/);
});

test("no pull request code is checked out, and every script and local action is main's", () => {
  const checkouts = [...text.matchAll(/uses: actions\/checkout@/g)];
  assert.equal(checkouts.length, 1);
  assert.match(step("Check out the default branch tip"), /ref: \$\{\{ steps\.tip\.outputs\.sha \}\}\n {10}path: \.base\n {10}persist-credentials: false/);
  for (const [, uses] of text.matchAll(/uses: (\.\/[^\s]+)/g)) assert.match(uses, /^\.\/\.base\//, uses);
  for (const [, script] of text.matchAll(/node (\S+\.mjs)/g)) assert.match(script, /^\.base\//, script);
});

// The key, subscription and fallback legs, each on one credential.
const LEGS = {
  "Rate the pull request": "api-key: ${{ secrets.PR_VERIFY_CLAUDE_API_KEY }}",
  "Rate the pull request on the subscription": "subscription-token: ${{ secrets.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN }}",
  "Rate the pull request on the fallback token": "fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}",
};

test("each credential reaches only its presence check and its own leg", () => {
  const holders = [...steps].filter(([, block]) => /secrets\./.test(block)).map(([name]) => name);
  assert.deepEqual(holders, ["Check the API key", "Check the credential", ...Object.keys(LEGS)]);
  assert.match(step("Check the API key"), /KEY: \$\{\{ secrets\.PR_VERIFY_CLAUDE_API_KEY != '' \}\}/);
  assert.match(step("Check the credential"), /TOKEN: \$\{\{ secrets\.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN != '' \}\}\n {10}FALLBACK: \$\{\{ secrets\.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' \}\}\n/);
  for (const [name, credential] of Object.entries(LEGS)) {
    assert.deepEqual([...step(name).matchAll(/secrets\.[A-Z_]+/g)].map(([ref]) => ref), [credential.match(/secrets\.[A-Z_]+/)[0]], name);
    assert.ok(step(name).includes(`\n          ${credential}\n`), name);
  }
});

test("the subscription leg follows a key handoff or skip, and the fallback leg a subscription handoff or empty token", () => {
  assert.match(step("Read the key's credit history"), /key-job: rate-merge-risk\n {10}window-hours: \$\{\{ vars\.KEY_CREDIT_WINDOW_HOURS \|\| '1' \}\}\n/);
  assert.match(step("Rate the pull request"), /if: steps\.prompt\.outcome == 'success' && steps\.credential\.outputs\.key == 'true'\n/);
  assert.match(step("Rate the pull request on the subscription"), /&& \(steps\.rate\.outcome == 'skipped' \|\| steps\.rate\.outputs\.handoff == 'true'\)\n/);
  assert.match(step("Rate the pull request on the fallback token"), /&& \(steps\.rate-subscription\.outputs\.handoff == 'true'\n\s+\|\| steps\.credential\.outputs\.token != 'true' && \(steps\.rate\.outcome == 'skipped' \|\| steps\.rate\.outputs\.handoff == 'true'\)\)\n/);
  // Only the key leg's credit stop writes the marker the gate reads.
  assert.match(step("Write the key's credit-stop marker"), /'key-credit-stop-pr-rate-merge-risk\.yml-rate-merge-risk' && steps\.rate\.outputs\.handoff-reason == 'credit-stop'\n/);
  assert.match(step("Upload the key's credit-stop marker"), /name: key-credit-stop-pr-rate-merge-risk\.yml-rate-merge-risk\n/);
});

test("the rating runs under dontAsk on the data directory and the review plugin's copy alone", () => {
  // Each leg is the key leg's step but for its name, id, condition and credential.
  const shape = (name) =>
    step(name)
      .replace(/^ {6}- name: .+\n {8}id: .+\n {8}if: (?:>-\n(?: {10}.+\n)+|.+\n)/, "")
      .replace(/\n {10}(?:api-key|subscription-token|fallback-token|fallback-ready): .+(?=\n)/g, "")
      .replace(/\n+\s*(?:#.*\n\s*)*$/, "");
  for (const name of Object.keys(LEGS)) assert.equal(shape(name), shape("Rate the pull request"), name);
  const rate = step("Rate the pull request");
  assert.match(rate, /uses: melodic-software\/ci-workflows\/\.github\/actions\/run-claude-cli@[0-9a-f]{40} /);
  assert.match(rate, /permission-mode: dontAsk\n/);
  assert.match(rate, /continue-on-error: true\n/);
  assert.deepEqual(list(rate, "tools"), ["Read", "Skill", "Agent"]);
  assert.deepEqual(list(rate, "allowed-tools"), ["Read(./merge-risk-data/**)", "Read(./.lane/plugins/review/**)", "Skill(review:merge-risk *)", "Agent"]);
  // merge-risk's frontmatter allowed-tools pre-approves bare Read once the
  // skill runs, so these deny rules, not the allow list, bound what it reads.
  // None may name the workspace or the home whole: the workspace sits under it.
  assert.match(readFileSync(new URL("../../../plugins/review/skills/merge-risk/SKILL.md", import.meta.url), "utf8"), /^allowed-tools: \[[^\]]*"Read"/m);
  const denied = list(rate, "disallowed-tools");
  assert.deepEqual(denied, [
    "Read(./.base/**)",
    "Read(/${{ runner.temp }}/**)",
    "Read(~/.config/**)",
    "Read(~/.git-credentials)",
    "Read(~/.claude/**)",
    "Read(//proc/**)",
    "Read(//sys/**)",
    "Read(//etc/**)",
    "Glob",
    "Grep",
    "Bash",
    "Edit",
    "Write",
    "NotebookEdit",
    "WebFetch",
    "WebSearch",
    "mcp__*",
  ]);
  assert.ok(!denied.some((rule) => ["Read(~/**)", "Read(./**)", "Read(//**)", "Read"].includes(rule)));
  assert.match(text, /allow rules do not bound Read once the skill runs/);
  assert.deepEqual(list(rate, "plugin-dirs"), [".lane/plugins/review"]);
  assert.match(rate, /CLAUDE_CODE_SUBAGENT_MODEL_FORCE: \$\{\{ steps\.checker\.outputs\.force \}\}/);
  // The managed settings and the isolation come first.
  const order = [...steps.keys()];
  assert.ok(order.indexOf("Apply the Claude managed settings") < order.indexOf("Isolate the runner"));
  assert.ok(order.indexOf("Isolate the runner") < order.indexOf("Rate the pull request"));
  assert.match(step("Stage the review plugin"), /chmod -R a-w \.lane\/plugins\/review/);
});

test("the names the arm side reads match merge-risk-line.mjs", () => {
  const resolve = step("Resolve the pull request");
  assert.match(resolve, new RegExp(`RATED_WORKFLOW_PATH: ${RATING_WORKFLOW_PATH.replaceAll(".", "\\.")}\\n`));
  assert.match(resolve, new RegExp(`RATED_ARTIFACT_PREFIX: ${ARTIFACT_PREFIX}\\n`));
  assert.match(resolve, /VERIFY_AUTHORS: lane\n/);
  assert.match(step("Upload the rating"), new RegExp(`name: ${ARTIFACT_PREFIX}-\\$\\{\\{ steps\\.pr\\.outputs\\.pr-number \\}\\}-\\$\\{\\{ steps\\.pr\\.outputs\\.head-sha \\}\\}\\n`));
  assert.match(step("Upload the rating"), /retention-days: 7\n/);
  assert.match(step("Upload the rating"), /steps\.scan-upload\.outputs\.clean == 'true'/);
});

test("the trigger is pr-verify's, judged only for a successful same-repository pull_request run on main", () => {
  assert.match(text, /\non:\n {2}# [^\n]+\n {2}workflow_run: # zizmor: ignore\[dangerous-triggers\]\n {4}workflows: \[pr-require-checks\]\n {4}types: \[completed\]\n/);
  assert.match(text, /github\.ref == 'refs\/heads\/main'\n {6}&& github\.event\.workflow_run\.event == 'pull_request'\n {6}&& github\.event\.workflow_run\.conclusion == 'success'\n {6}&& github\.event\.workflow_run\.head_repository\.full_name == github\.repository\n/);
  assert.match(text, /cancel-in-progress: false\n/);
});
