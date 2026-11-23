// test-scope: .github/lane-funding.json scripts/credential-legs/*
import assert from "node:assert/strict";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { tempDir } from "../lib/test-tmp.mjs";
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

test("a job's span ends at its last non-blank line, before the next job's comment", () => {
  const lines = ["jobs:", "  a:", "    steps:", "      - name: A", "", "        run: x", "", "  # b's comment", "  b:", "    steps: []", ""];
  assert.deepEqual(jobSpan(lines, "a"), [1, 6]);
  assert.deepEqual(jobSpan(lines, "b"), [8, 10]);
  assert.throws(() => jobSpan(lines, "c"), /no job c/);
});

test("an eval lane is key-only, so it gets no subscription or fallback job", () => {
  for (const job of ["run-eval-subscription", "run-eval-fallback"]) {
    assert.throws(() => checkFunding(FUNDING, ".github/workflows/pr-run-plugin-evals.yml", job, ""), /funds no .* lane in pr-run-plugin-evals\.yml/, job);
  }
  assert.throws(() => checkFunding(FUNDING, ".github/workflows/maintenance-measure-skill-edit-pass.yml", "run-eval-subscription", ""), /funds no/);
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
