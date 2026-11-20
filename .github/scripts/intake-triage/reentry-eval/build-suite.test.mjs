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
  composeScript,
  lineScalar,
  OUTPUT_LINE,
  schema,
  verdictModule,
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
  'core.setOutput("allowed", JSON.stringify(labels.map((l) => l.name)));',
  'core.setOutput("type-names", JSON.stringify(["Bug"]));',
  'core.setOutput("prompt-file", path.join(dir, "p.md"));',
];
// The schema step stub: like verdict.cjs, a non-empty verdict-schema adds its
// fields to the schema and appends a verdict-fields block to the prompt file.
// https://github.com/melodic-software/ci-workflows/blob/main/.github/actions/check-intake-triage-verdict/verdict.cjs
const VERDICT = [
  'const fs = require("node:fs");',
  'const path = require("node:path");',
  "function main(env) {",
  '  if (env.INPUT_MODE !== "schema") throw new Error("not the schema step");',
  '  const file = path.join(path.dirname(env.INPUT_PROMPT_FILE), "schema.json");',
  "  const fields = env.INPUT_VERDICT_SCHEMA === '' ? null : Object.keys(JSON.parse(env.INPUT_VERDICT_SCHEMA).properties);",
  "  if (fields) fs.appendFileSync(env.INPUT_PROMPT_FILE, '\\nVERDICT FIELDS: ' + fields.join(', ') + '\\n');",
  "  fs.writeFileSync(file, JSON.stringify({ ...(fields ? { fields } : {}), allowed: JSON.parse(env.INPUT_ALLOWED), types: JSON.parse(env.INPUT_TYPE_NAMES) }));",
  '  return { outputs: { "schema-file": file }, lines: [] };',
  "}",
  "module.exports = { main };",
].join("\n");
const step = (lines) =>
  [
    "      - name: Compose",
    "        id: compose",
    "        with:",
    "          script: |",
    ...lines.map((l) => `            ${l}`),
    "",
  ].join("\n");
const reusable = (...steps) =>
  ["jobs:", "  triage:", "    steps:", ...steps].join("\n");
const CALLER = [
  "jobs:",
  "  intake-triage:",
  "    uses: melodic-software/ci-workflows/.github/workflows/intake-triage.yml@abc123",
  "    with:",
  "      allowed-labels: |",
  "        priority: low",
  "        needs-human",
  "      instructions: |",
  "        RULE ONE.",
  "",
  "          indented line",
  "    secrets: {}",
  "",
].join("\n");
// The same caller with a verdict-schema, single-quoted as intake-triage.yml
// writes it; `''` is YAML's escaped quote.
// https://yaml.org/spec/1.2.2/
const VERDICT_SCHEMA =
  '{"properties":{"size":{"type":"string"},"it\'s":{"type":"string"}},"required":["size"]}';
const CALLER_WITH_SCHEMA = CALLER.replace(
  "    with:\n",
  `    with:\n      verdict-schema: '${VERDICT_SCHEMA.replaceAll("'", "''")}'\n`,
);

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

test("callerInputs reads the pin and dedents the block scalars as YAML does", () => {
  assert.deepEqual(callerInputs(CALLER), {
    ref: "abc123",
    allowedLabels: "priority: low\nneeds-human\n",
    instructions: "RULE ONE.\n\n  indented line\n",
    verdictSchema: "",
  });
  assert.equal(callerInputs(CALLER_WITH_SCHEMA).verdictSchema, VERDICT_SCHEMA);
});

test("lineScalar reads plain and single-quoted values and fails closed on any other style", () => {
  assert.equal(lineScalar("  k: plain"), "plain");
  assert.equal(lineScalar("  k: 'a''b'"), "a'b");
  assert.throws(() => lineScalar("  k: 'open"), /unterminated/u);
  assert.throws(() => lineScalar('  k: "x"'), /unsupported scalar style/u);
  assert.throws(
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a workflow expression, not a template
    () => lineScalar("  k: ${{ vars.X }}"),
    /workflow expression/u,
  );
});

test("build passes the caller's verdict-schema and the emptied build is an exact prefix of it", async () => {
  const promptOf = (out, name) =>
    JSON.parse(
      readFileSync(join(out, "evals", name, "case.yaml"), "utf8").match(
        /^ {2}prompt: (.*)$/mu,
      )[1],
    );
  const run = async (verdictSchema) => {
    const out = tempDir("reentry-build-");
    const { cases } = await build({
      reusable: reusable(step(SCRIPT)),
      verdictSource: VERDICT,
      sha: "0".repeat(40),
      out,
      verdictSchema,
      callerText: CALLER_WITH_SCHEMA,
    });
    return { out, cases };
  };
  const withSchema = await run(true);
  const baseline = await run(false);
  for (const name of withSchema.cases) {
    const full = promptOf(withSchema.out, name);
    const base = promptOf(baseline.out, name);
    const composed = full.split(`\n${OUTPUT_LINE}\n`)[0];
    const baseComposed = base.split(`\n${OUTPUT_LINE}\n`)[0];
    assert.ok(composed.startsWith(baseComposed), name);
    assert.equal(
      composed.slice(baseComposed.length),
      "\nVERDICT FIELDS: size, it's\n",
      "the only addition is the verdict-fields block the schema step appends",
    );
    assert.ok(full.includes('"fields":["size","it\'s"]'), name);
    assert.ok(!base.includes('"fields"'), name);
  }
});

test("build fills every case with the composed prompt and writes the issue files the prompt names", async () => {
  for (const instructions of [true, false]) {
    const out = tempDir("reentry-build-");
    const { cases } = await build({
      reusable: reusable(step(SCRIPT)),
      verdictSource: VERDICT,
      sha: "0".repeat(40),
      out,
      instructions,
      callerText: CALLER,
    });
    assert.equal(cases.length, 9);
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
        prompt.trimEnd().endsWith('"types":["Bug"]}'),
        "the schema the schema step wrote from the compose outputs ends the prompt",
      );
      assert.ok(prompt.includes('"allowed":["priority: low"'), name);
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
    reusable: reusable(step(SCRIPT)),
    verdictSource: VERDICT,
    sha: "0".repeat(40),
    out,
    callerText: CALLER,
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

test("build fails closed when the schema step writes no schema file", async () => {
  const run = (verdictSource) =>
    build({
      reusable: reusable(step(SCRIPT)),
      verdictSource,
      sha: "0".repeat(40),
      out: tempDir("reentry-build-"),
      callerText: CALLER,
    });
  await assert.rejects(
    run("module.exports = { main: () => ({ outputs: {}, lines: [] }) };"),
    /schema step set no schema-file output/u,
  );
  await assert.rejects(run("module.exports = {};"), /exports no main/u);
});

test("schema fails closed when compose sets no output the schema step reads", () => {
  const verdict = verdictModule(VERDICT);
  for (const name of ["allowed", "type-names", "prompt-file"]) {
    const outputs = {
      allowed: "[]",
      "type-names": "[]",
      "prompt-file": join(tempDir("reentry-schema-"), "p.md"),
    };
    delete outputs[name];
    assert.throws(
      () => schema(verdict, outputs),
      new RegExp(`compose set no ${name} output`, "u"),
    );
  }
});
