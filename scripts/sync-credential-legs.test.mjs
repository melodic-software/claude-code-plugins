// test-scope: .github/lane-funding.json scripts/credential-legs/*
import assert from "node:assert/strict";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { tempDir } from "../lib/test-tmp.mjs";
import { readRunnerCalls } from "./credential-legs/read-runner-calls.mjs";
import { checkFunding, jobSpan, main, render } from "./sync-credential-legs.mjs";

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const FUNDING = JSON.parse(readFileSync(path.join(REPO, ".github/lane-funding.json"), "utf8"));

const KEY_JOB = `  judge:
    name: Judge
    if: vars.KEY_OFF != 'true'
    steps:
      # Read first.
      - name: Read
        run: echo read

      # Only the key holds a credit gate.
      - name: Gate the key
        run: echo gate

      - name: Pick the model
        run: echo model
      # The key's credential.
      - name: Check the credential
        with:
          leg: key
      - name: Judge it
        with:
          # The model's credential.
          api-key: \${{ secrets.X_CLAUDE_API_KEY }}
          log: \${{ steps.judge.outputs.log }}
          log-2: \${{ steps.judge-2.outputs.log }}`;

const LEG = {
  job: "judge-subscription",
  drop: ["Gate the key"],
  move: { "Check the credential": "Pick the model" },
  comments: { Read: true, "Check the credential": "The subscription's credential,\nnever its value." },
  replace: [
    ["  judge:\n    name: Judge\n", "  judge-subscription:\n    name: Judge Subscription\n    needs: judge\n", 1],
    ["leg: key", "leg: subscription", 1],
    [/^( {10})api-key: \$\{\{ secrets\.X_CLAUDE_API_KEY \}\}$/gm, "$1subscription-token: ${{ secrets.X_CLAUDE_CODE_OAUTH_TOKEN }}", 1],
    [/steps\.judge(-\d)?\.outputs\.log/g, "steps.judge$1.outputs.transcript", 2],
  ],
};

test("a derived job drops and moves the declared steps, keeps only the declared step comments, then applies each replacement", () => {
  assert.equal(
    render(KEY_JOB.split("\n"), LEG),
    `  judge-subscription:
    name: Judge Subscription
    needs: judge
    if: vars.KEY_OFF != 'true'
    steps:
      # Read first.
      - name: Read
        run: echo read

      - name: Pick the model
        run: echo model
      # The subscription's credential,
      # never its value.
      - name: Check the credential
        with:
          leg: subscription
      - name: Judge it
        with:
          # The model's credential.
          subscription-token: \${{ secrets.X_CLAUDE_CODE_OAUTH_TOKEN }}
          log: \${{ steps.judge.outputs.transcript }}
          log-2: \${{ steps.judge-2.outputs.transcript }}`,
  );
});

test("a replacement that matches other than its declared count stops the render", () => {
  const leg = { ...LEG, replace: [["steps.judge", "steps.verdict", 1]] };
  assert.throws(() => render(KEY_JOB.split("\n"), leg), /judge-subscription expects 1 of steps\.judge, found 2/);
});

test("a declaration naming a step the key job lacks stops the render", () => {
  for (const leg of [
    { ...LEG, drop: ["Gate the keys"] },
    { ...LEG, move: { "Check the credential": "Pick a model" } },
    { ...LEG, comments: { Reed: true } },
  ]) {
    assert.throws(() => render(KEY_JOB.split("\n"), leg), /names a step the key job lacks/, JSON.stringify(leg));
  }
  assert.throws(() => render(KEY_JOB.split("\n"), { ...LEG, move: { "Check the credential": "Gate the key" } }), /moves Check the credential after a dropped step/);
});

test("a step name two steps share stops the render, and its #id names just one", () => {
  const keyJob = `  judge:
    steps:
      - name: Scan
        id: scan-handoff
        run: echo handoff
      - name: Scan
        id: scan-upload
        run: echo upload`.split("\n");
  const leg = { job: "judge-fallback" };
  assert.throws(() => render(keyJob, { ...leg, drop: ["Scan"] }), /judge-fallback names 2 steps Scan; name one by its #id/);
  assert.equal(
    render(keyJob, { ...leg, drop: ["#scan-handoff"], comments: { "#scan-upload": "The upload's scan." } }),
    `  judge:
    steps:
      # The upload's scan.
      - name: Scan
        id: scan-upload
        run: echo upload`,
  );
  assert.throws(() => render(keyJob, { ...leg, drop: ["#scan"] }), /names a step the key job lacks: #scan/);
});

const CALLER = `  call:
    name: Call
    needs: pick
    if: >-
      needs.pick.outputs.go == 'true'
      && vars.KEY_OFF != 'true'
    # The key alone.
    uses: ./.github/workflows/runner.yml
    with:
      start-gate: true
      key-credit-job: call
      lane: l
    secrets:
      claude-api-key: \${{ secrets.X_CLAUDE_API_KEY }}
      carrier: \${{ secrets.CARRIER }}`.split("\n");

test("a key job with no steps is all header: each replacement applies to the whole job, and a step name stops the render", () => {
  const leg = { job: "call-subscription", replace: [["  call:\n    name: Call\n", "  call-subscription:\n    name: Call Subscription\n", 1], ["claude-api-key: ${{ secrets.X_CLAUDE_API_KEY }}", "claude-code-oauth-token: ${{ secrets.X_CLAUDE_CODE_OAUTH_TOKEN }}", 1]] };
  assert.equal(
    render(CALLER, leg),
    `  call-subscription:
    name: Call Subscription
    needs: pick
    if: >-
      needs.pick.outputs.go == 'true'
      && vars.KEY_OFF != 'true'
    # The key alone.
    uses: ./.github/workflows/runner.yml
    with:
      start-gate: true
      key-credit-job: call
      lane: l
    secrets:
      claude-code-oauth-token: \${{ secrets.X_CLAUDE_CODE_OAUTH_TOKEN }}
      carrier: \${{ secrets.CARRIER }}`,
  );
  assert.throws(() => render(CALLER, { ...leg, drop: ["Judge it"] }), /call-subscription names a step the key job lacks: Judge it/);
});

test("a read-runner call's subscription and fallback legs take their own header, credential and secret, and drop the key's comments", () => {
  const declaration = readRunnerCalls({
    workflow: ".github/workflows/w.yml",
    key: "call",
    role: "X",
    upstream: ["pick"],
    comments: 1,
    subscription: { if: "${{ !cancelled() && needs.call-handoff.outputs.posted != 'true' }}" },
    fallback: { replace: [["      start-gate: true\n", "", 1]] },
  });
  assert.equal(declaration.workflow, ".github/workflows/w.yml");
  assert.equal(declaration.key, "call");
  const [subscription, fallback] = declaration.legs;
  assert.equal(subscription.job, "call-subscription");
  assert.equal(
    render(CALLER, subscription),
    `  call-subscription:
    name: Call Subscription
    needs: [pick, call, call-handoff]
    if: \${{ !cancelled() && needs.call-handoff.outputs.posted != 'true' }}
    uses: ./.github/workflows/runner.yml
    with:
      start-gate: true
      fallback: handoff
      fallback-ready: \${{ needs.call-handoff.outputs.fallback-ready }}
      lane: l
    secrets:
      claude-code-oauth-token: \${{ secrets.X_CLAUDE_CODE_OAUTH_TOKEN }}
      carrier: \${{ secrets.CARRIER }}`,
  );
  assert.equal(fallback.job, "call-fallback");
  assert.equal(
    render(CALLER, fallback),
    `  call-fallback:
    name: Call Fallback
    needs: [pick, call, call-handoff, call-subscription, call-subscription-handoff]
    if: \${{ !cancelled() && needs.call-handoff.outputs.fallback-ready == 'true' && needs.call-subscription-handoff.outputs.handed-off == 'true' }}
    uses: ./.github/workflows/runner.yml
    with:
      fallback: fallback
      lane: l
    secrets:
      fallback-claude-code-oauth-token: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}
      carrier: \${{ secrets.CARRIER }}`,
  );
});

test("a read-runner call whose key job gained or lost a comment stops the render", () => {
  const legs = (comments) => readRunnerCalls({ workflow: "w.yml", key: "call", role: "X", upstream: ["pick"], comments, subscription: { if: "true" } }).legs;
  for (const comments of [0, 2]) {
    for (const leg of legs(comments)) assert.throws(() => render(CALLER, leg), new RegExp(`${leg.job} expects ${comments} of .*, found 1`), `${leg.job} ${comments}`);
  }
});

test("a job's span ends at its last non-blank line, before the next job's comment", () => {
  const lines = ["jobs:", "  a:", "    steps:", "      - name: A", "", "        run: x", "", "  # b's comment", "  b:", "    steps: []", ""];
  assert.deepEqual(jobSpan(lines, "a"), [1, 6]);
  assert.deepEqual(jobSpan(lines, "b"), [8, 10]);
  assert.throws(() => jobSpan(lines, "c"), /no job c/);
});

test("an eval lane gets no fallback job, and a subscription job only on the token alone", () => {
  for (const workflow of [".github/workflows/pr-run-plugin-evals.yml", ".github/workflows/maintenance-measure-skill-edit-pass.yml"]) {
    assert.throws(() => checkFunding(FUNDING, workflow, "run-eval-fallback", ""), /funds no/, workflow);
    assert.doesNotThrow(() => checkFunding(FUNDING, workflow, "run-eval-subscription", "${{ secrets.MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN }}"), workflow);
    assert.throws(() => checkFunding(FUNDING, workflow, "run-eval-subscription", "${{ secrets.MAINTENANCE_CLAUDE_API_KEY }}"), /reads MAINTENANCE_CLAUDE_API_KEY/, workflow);
    assert.throws(() => checkFunding(FUNDING, workflow, "run-eval-subscription", "${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}"), /reads FALLBACK_CLAUDE_CODE_OAUTH_TOKEN/, workflow);
  }
});

test("a derived job reads only the secrets lane-funding.json funds its lane with, and never the API key", () => {
  const workflow = ".github/workflows/pr-verify.yml";
  assert.doesNotThrow(() => checkFunding(FUNDING, workflow, "check-intent-subscription", "${{ secrets.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN }} ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}"));
  assert.throws(() => checkFunding(FUNDING, workflow, "check-intent-fallback", "${{ secrets.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN }}"), /reads PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN, which lane-funding\.json does not fund it with/);
  assert.throws(() => checkFunding(FUNDING, workflow, "check-intent-subscription", "${{ secrets.PR_VERIFY_CLAUDE_API_KEY }}"), /reads PR_VERIFY_CLAUDE_API_KEY/);
  assert.throws(() => checkFunding(FUNDING, workflow, "check-intent", ""), /funded by the API key/);
});

test("--check reports a hand-edited derived job, a plain run rewrites it, and the check then passes", (t) => {
  t.mock.method(process.stdout, "write", () => true);
  t.mock.method(process.stderr, "write", () => true);
  const root = tempDir("credential-legs-");
  mkdirSync(path.join(root, ".github/workflows"), { recursive: true });
  const funding = { roles: [{ keySecret: "X_CLAUDE_API_KEY", lanes: [{ id: "judge-subscription", workflow: "w.yml", currentSecrets: ["X_CLAUDE_CODE_OAUTH_TOKEN"] }] }] };
  writeFileSync(path.join(root, ".github/lane-funding.json"), JSON.stringify(funding));
  const file = path.join(root, ".github/workflows/w.yml");
  const rendered = render(KEY_JOB.split("\n"), LEG);
  const committed = `jobs:\n${KEY_JOB}\n\n${rendered.replace("leg: subscription", "leg: hand-edited")}\n`;
  writeFileSync(file, committed);
  const declarations = [{ workflow: ".github/workflows/w.yml", key: "judge", legs: [LEG] }];
  assert.equal(main(["--check"], root, declarations), 1);
  assert.match(process.stdout.write.mock.calls.map((c) => c.arguments[0]).join(""), /^-\s+leg: hand-edited\n\+\s+leg: subscription$/m);
  assert.equal(readFileSync(file, "utf8"), committed, "--check writes nothing");
  assert.equal(main([], root, declarations), 0);
  assert.equal(readFileSync(file, "utf8"), `jobs:\n${KEY_JOB}\n\n${rendered}\n`);
  assert.equal(main(["--check"], root, declarations), 0);
  assert.equal(main(["--fix"], root, declarations), 2);
});
