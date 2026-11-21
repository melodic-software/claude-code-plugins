// The builder against a synthetic reusable and caller: it must run the compose
// script it finds, fail closed when it cannot, and fill each case with that
// script's prompt. No assertion reads the real reusable's prompt text.
import assert from "node:assert/strict";
import { existsSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../../lib/test-tmp.mjs";
import {
  build,
  callerInputs,
  checkSchemaSteps,
  composeScript,
} from "./build-suite.mjs";

const SCRIPT = [
  'const fs = require("node:fs");',
  'const path = require("node:path");',
  "const env = process.env;",
  'github.hook.after("request", () => {});',
  'github.hook.error("request", (error) => { throw error; });',
  "const labels = await github.paginate(github.rest.issues.listLabelsForRepo, {});",
  'const dir = fs.mkdtempSync(path.join(env.RUNNER_TEMP, "t-"));',
  // biome-ignore lint/suspicious/noTemplateCurlyInString: the stub script's own template literal
  'fs.writeFileSync(path.join(dir, "p.md"), `ISSUE ${env.ISSUE_NUMBER} AT ${env.ISSUE_FILE} OF ${context.repo.repo} (${labels.length})\\n${env.INSTRUCTIONS}`);',
  'core.setOutput("prompt-file", path.join(dir, "p.md"));',
  'core.setOutput("allowed", JSON.stringify(["priority: low"]));',
  'core.setOutput("type-names", JSON.stringify(["Bug"]));',
];
const VERDICT = [
  'const fs = require("node:fs");',
  'const path = require("node:path");',
  "exports.main = (env) => {",
  '  if (env.INPUT_MODE !== "schema") throw new Error(env.INPUT_MODE);',
  '  const file = path.join(path.dirname(env.INPUT_PROMPT_FILE), "schema.json");',
  "  fs.writeFileSync(file, JSON.stringify({ allowed: JSON.parse(env.INPUT_ALLOWED), types: JSON.parse(env.INPUT_TYPE_NAMES), verdict: env.INPUT_VERDICT_SCHEMA }));",
  '  fs.appendFileSync(env.INPUT_PROMPT_FILE, "\\nVERDICT FIELDS\\n");',
  '  return { outputs: { "schema-file": file } };',
  "};",
].join("\n");
const SCHEMA = `{"allowed":["priority: low"],"types":["Bug"],"verdict":"{\\"note\\":\\"it's\\"}"}`;
const step = (lines) =>
  [
    "      - name: Compose",
    "        id: compose",
    "        with:",
    "          script: |",
    ...lines.map((l) => `            ${l}`),
    "",
  ].join("\n");
// biome-ignore lint/suspicious/noTemplateCurlyInString: a workflow expression, not a template
const VERDICT_INPUT = "verdict-schema: ${{ inputs.verdict-schema }}";
const schemaStep = (withLines = ["mode: schema", VERDICT_INPUT]) =>
  [
    "      - name: Compose the output schema",
    "        id: schema",
    "        uses: ./.github/actions/check-intake-triage-verdict",
    "        with:",
    ...withLines.map((l) => `          ${l}`),
    "",
  ].join("\n");
const reusable = (...steps) =>
  ["jobs:", "  triage:", "    steps:", ...steps].join("\n");
const leg = () => [step(SCRIPT), schemaStep()];
const CALLER = [
  "jobs:",
  "  intake-triage:",
  "    uses: melodic-software/ci-workflows/.github/workflows/intake-triage.yml@abc123",
  "    with:",
  `      verdict-schema: '{"note":"it''s"}'`,
  "      allowed-labels: |",
  "        priority: low",
  "        needs-human",
  // biome-ignore lint/suspicious/noTemplateCurlyInString: a workflow expression, not a template
  "      instructions: ${{ needs.check-born-triaged.outputs.instructions }}",
  "    secrets: {}",
  "",
].join("\n");

test("composeScript returns the one script every compose step carries", () => {
  assert.match(
    composeScript(reusable(step(SCRIPT), step(SCRIPT))),
    /^const fs = require/u,
  );
});

test("composeScript fails closed on no step, differing legs or a workflow expression", () => {
  assert.throws(() => composeScript(reusable()), /no compose step/u);
  assert.throws(
    () => composeScript(reusable(step(SCRIPT), step([...SCRIPT, "// other"]))),
    /2 compose scripts differ/u,
  );
  assert.throws(
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a workflow expression, not a template
    () => composeScript(reusable(step(['const x = "${{ inputs.y }}";']))),
    /workflow expression/u,
  );
});

test("checkSchemaSteps passes when every compose step has its schema step", () => {
  assert.doesNotThrow(() => checkSchemaSteps(reusable(...leg(), ...leg())));
});

test("checkSchemaSteps fails closed on a missing schema step or one not fed verdict-schema", () => {
  assert.throws(
    () => checkSchemaSteps(reusable(...leg(), step(SCRIPT))),
    /2 compose steps but 1 schema steps/u,
  );
  assert.throws(
    () =>
      checkSchemaSteps(reusable(step(SCRIPT), schemaStep(["mode: schema"]))),
    /does not run schema mode on the caller's verdict-schema/u,
  );
  assert.throws(
    () =>
      checkSchemaSteps(
        reusable(step(SCRIPT), schemaStep(["mode: check", VERDICT_INPUT])),
      ),
    /does not run schema mode/u,
  );
});

const RUBRIC = "RULE ONE.\n\n  indented line\n";

test("callerInputs reads the pin, unquotes verdict-schema and dedents the allowed-labels block scalar as YAML does", () => {
  assert.deepEqual(callerInputs(CALLER), {
    ref: "abc123",
    allowedLabels: "priority: low\nneeds-human\n",
    verdictSchema: '{"note":"it\'s"}',
  });
});

test("callerInputs gives an empty verdict-schema when the caller sets none, and refuses a form it cannot read", () => {
  const without = CALLER.split("\n")
    .filter((line) => !line.includes("verdict-schema"))
    .join("\n");
  assert.equal(callerInputs(without).verdictSchema, "");
  assert.throws(
    () =>
      callerInputs(
        CALLER.replace(/verdict-schema: '.*'/u, 'verdict-schema: "{}"'),
      ),
    /not one single-quoted line/u,
  );
});

test("build fails when the schema step writes no schema file", async () => {
  await assert.rejects(
    build({
      reusable: reusable(...leg()),
      verdict: "exports.main = () => ({ outputs: {} });",
      sha: "0".repeat(40),
      out: tempDir("reentry-build-"),
      callerText: CALLER,
      rubricText: RUBRIC,
    }),
    /the schema step wrote no schema file/u,
  );
});

test("build fills every case with the composed prompt and writes the issue files the prompt names", async () => {
  for (const instructions of [true, false]) {
    const out = tempDir("reentry-build-");
    const { cases } = await build({
      reusable: reusable(...leg()),
      verdict: VERDICT,
      sha: "0".repeat(40),
      out,
      instructions,
      callerText: CALLER,
      rubricText: RUBRIC,
    });
    assert.equal(cases.length, 10);
    for (const name of cases) {
      const dir = join(out, "evals", name);
      const prompt = JSON.parse(
        readFileSync(join(dir, "case.yaml"), "utf8").match(
          /^ {2}prompt: (.*)$/mu,
        )[1],
      );
      const issue = JSON.parse(
        readFileSync(
          join(dir, "workspace", ".intake-triage-eval", "issue.json"),
          "utf8",
        ),
      );
      assert.ok(
        prompt.startsWith(
          `ISSUE ${issue.number} AT .intake-triage-eval/issue.json OF claude-code-plugins (`,
        ),
        name,
      );
      assert.equal(prompt.includes("RULE ONE."), instructions, name);
      assert.ok(
        prompt.endsWith(`\n\n${SCHEMA}\n`),
        "the schema the schema step wrote, from the compose outputs and the caller's verdict-schema, ends the prompt",
      );
      assert.match(
        prompt,
        /\nVERDICT FIELDS\n\nReply with only/u,
        "the prompt is read after the schema step appends to it",
      );
      for (const file of [issue.body, ...issue.comments.map((c) => c.body)])
        assert.ok(existsSync(join(dir, "workspace", file)), file);
      for (const comment of issue.comments)
        assert.match(comment.url, /#issuecomment-\d+$/u, name);
      assert.ok(existsSync(join(dir, "workspace", "AGENTS.md")));
      assert.ok(
        existsSync(
          join(dir, "workspace", ".intake-triage-eval", "merged-pulls.json"),
        ),
        "the merged pull requests file the prompt names",
      );
      assert.ok(
        statSync(join(dir, "scaffold.sh")).mode & 0o100,
        "scaffold is executable",
      );
    }
  }
});

test("build gives a case its own body.md and the rest the shared one", async () => {
  const out = tempDir("reentry-build-");
  await build({
    reusable: reusable(...leg()),
    verdict: VERDICT,
    sha: "0".repeat(40),
    out,
    callerText: CALLER,
    rubricText: RUBRIC,
  });
  const body = (name) =>
    readFileSync(
      join(out, "evals", name, "workspace", ".intake-triage-eval", "body.md"),
      "utf8",
    );
  assert.match(
    body("outside-spec-flags-untrusted"),
    /pull request opened from a fork by an\s+account outside this organization/u,
  );
  assert.match(body("settled-confirms"), /## Open questions/u);
});
