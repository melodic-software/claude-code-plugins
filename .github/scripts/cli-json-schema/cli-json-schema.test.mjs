// test-scope: package.json package-lock.json .github/actions/collect-base-activity/action.yml docs/conventions/pr-pipeline.yaml
// test-scope: plugins/work-items/skills/triage/schemas/ci-verdict.schema.json .github/scripts/intake-triage/refine-schema.json
// test-scope: .github/scripts/maintenance-audit-lane-runs/lane-sweep.schema.json

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";

const REPO_ROOT = path.join(import.meta.dirname, "../../..");
const read = (file) => readFileSync(path.join(REPO_ROOT, file), "utf8");

const INVALID = "is not a valid JSON Schema";
const CLI_NAME = "@anthropic-ai/claude-code";
const CLI_PACKAGE = `node_modules/${CLI_NAME}`;
const PIN = JSON.parse(read("package.json")).devDependencies[CLI_NAME];
const ACTION = read(".github/actions/collect-base-activity/action.yml");

function cli() {
  let manifest;
  try {
    manifest = JSON.parse(read(`${CLI_PACKAGE}/package.json`));
  } catch (error) {
    assert.fail(`the pinned CLI is not installed; run npm ci at the repository root (${error.message})`);
  }
  assert.equal(manifest.version, PIN, `${CLI_PACKAGE} is not the version package.json pins; run npm ci at the repository root`);
  return path.join(REPO_ROOT, CLI_PACKAGE, manifest.bin.claude);
}

function runCli(schema) {
  const home = tempDir("cli-json-schema-home-");
  const run = spawnSync(cli(), ["-p", "--json-schema", schema, "Reply with an empty object."], {
    cwd: home,
    encoding: "utf8",
    input: "",
    timeout: 120_000,
    env: {
      PATH: process.env.PATH,
      HOME: home,
      CLAUDE_CONFIG_DIR: path.join(home, ".claude"),
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
    },
  });
  assert.equal(run.error, undefined, `the CLI did not run to its exit: ${run.error}\n${run.stderr}`);
  return run;
}

function triageCopy() {
  const block = /^[ \t]*dimensions=\$\(yq [\s\S]*?>"\$VERDICT_SCHEMA_DIR\/verdict\.schema\.json"[^\n]*$/m.exec(ACTION)?.[0];
  assert.ok(block, "collect-base-activity no longer writes the triage verdict copy in the block this suite runs");
  const dir = tempDir("cli-json-schema-verdict-");
  const run = spawnSync("bash", ["-c", `fail() { echo "$*" >&2; exit 1; }\n${block}`], {
    encoding: "utf8",
    env: {
      ...process.env,
      BASE_PATH: REPO_ROOT,
      VERDICT_SCHEMA_DIR: dir,
      verdict_schema: path.join(REPO_ROOT, "plugins/work-items/skills/triage/schemas/ci-verdict.schema.json"),
    },
  });
  assert.equal(run.status, 0, run.stderr);
  return readFileSync(path.join(dir, "verdict.schema.json"), "utf8");
}

function dependencySchema() {
  const schema = /printf '%s\\n' '(\{[^']*\})' \\\n[ \t]*>"\$SCHEMA_DIR\/verdict\.schema\.json"/.exec(ACTION)?.[1];
  assert.ok(schema, "collect-base-activity no longer writes the dependency verdict schema in the line this suite reads");
  return schema;
}

const LANE_SCHEMAS = {
  "triage verdict copy collect-base-activity writes": triageCopy,
  "dependency verdict schema collect-base-activity writes": dependencySchema,
  "intake-triage refine schema": () => read(".github/scripts/intake-triage/refine-schema.json"),
  "maintenance-audit-lane-runs lane-sweep schema": () => read(".github/scripts/maintenance-audit-lane-runs/lane-sweep.schema.json"),
};

let accepted;
const acceptedRun = () => (accepted ??= runCli(JSON.stringify({ type: "object" })));

test("control: the pinned CLI refuses a 2020-12 $schema before it authenticates", () => {
  const run = runCli(JSON.stringify({ $schema: "https://json-schema.org/draft/2020-12/schema", type: "object" }));
  assert.ok(run.stderr.includes(INVALID), `stderr lacks "${INVALID}":\n${run.stderr}`);
  assert.ok(!acceptedRun().stderr.includes(INVALID), `a bare draft-07 schema is refused too:\n${acceptedRun().stderr}`);
});

for (const [name, schema] of Object.entries(LANE_SCHEMAS)) {
  test(`the pinned CLI accepts the ${name}`, () => {
    const run = runCli(JSON.stringify(JSON.parse(schema())));
    assert.ok(!run.stderr.includes(INVALID), run.stderr);
    assert.equal(run.status, acceptedRun().status, `the run ended unlike a bare draft-07 schema's:\n${run.stderr}`);
    assert.equal(run.stderr, acceptedRun().stderr, "the run's stderr differs from a bare draft-07 schema's");
  });
}
