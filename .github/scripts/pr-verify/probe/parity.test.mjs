// The replay must judge the way pr-verify.yml does. These tests read the
// workflow and fail when its judge step, prompt step or model route drift
// from replay.mjs's JUDGE, or when the ci-workflows pin moves: cliArgs,
// LEG_ENV, CLI_VERSION and MANAGED_SETTINGS were read from run-claude-cli and
// apply-claude-managed-settings at RUN_CLAUDE_CLI_PIN, so a new pin means
// reading them again.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { test } from "node:test";

import { CLI_VERSION, cliArgs, JUDGE, LEG_ENV, legEnv, MANAGED_SETTINGS, promptText, RUN_CLAUDE_CLI_PIN } from "./replay.mjs";

const text = readFileSync(new URL("../../../workflows/pr-verify.yml", import.meta.url), "utf8");
const JOBS = ["check-intent", "check-intent-subscription"];
const jobText = (id) => {
  const found = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(text);
  assert.ok(found, `a job ${id}`);
  return found[1];
};
const step = (job, name) => {
  const found = jobText(job)
    .split(/\n(?=      - name: )/)
    .find((block) => block.startsWith(`      - name: ${name}\n`));
  assert.ok(found, `a step named ${name} in ${job}`);
  return found;
};
// A `with:` input's one-line value, a `|` list's lines, or a `>-` scalar folded.
const input = (block, key) => new RegExp(`^ {10}${key}: (.*)$`, "m").exec(block)?.[1];
const block10 = (block, key, style) =>
  (new RegExp(`^ {10}${key}: ${style}\\n((?: {12}.*\\n?)+)`, "m").exec(block)?.[1] ?? "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
const withKeys = (block) => [...block.split(/\n {8}with:\n/)[1].matchAll(/^ {10}([a-z-]+):/gm)].map((m) => m[1]);
const envOf = (block) => {
  const body = /\n {8}env:\n((?: {10}.*\n)+)/.exec(block)?.[1] ?? "";
  return Object.fromEntries(
    [...body.matchAll(/^ {10}([A-Z_]+): (.*)$/gm)].map(([, key, value]) => [key, value.replace(/^"(.*)"$/, "$1")]),
  );
};

for (const job of JOBS) {
  test(`${job}: the judge step's inputs are the replay's`, () => {
    const judge = step(job, "Judge the pull request");
    const credential = job === "check-intent" ? "api-key" : "subscription-token";
    // Any input added or removed changes the argv run-claude-cli builds.
    assert.deepEqual(withKeys(judge).sort(), [
      "allowed-tools",
      credential,
      "disallowed-tools",
      "effort",
      "json-schema-file",
      "lane",
      "leg-timeout-minutes",
      "max-turns",
      "model",
      "permission-mode",
      "preamble",
      "prompt-file",
      "role",
      "tools",
    ].sort());
    assert.equal(input(judge, "permission-mode"), JUDGE.permissionMode);
    assert.deepEqual(input(judge, "tools").split(","), JUDGE.tools);
    assert.deepEqual([input(judge, "allowed-tools")], JUDGE.allowedTools);
    assert.deepEqual(block10(judge, "disallowed-tools", "\\|"), JUDGE.disallowedTools);
    assert.equal(block10(judge, "preamble", ">-").join(" "), JUDGE.preamble);
    assert.equal(input(judge, "leg-timeout-minutes"), `"${JUDGE.legTimeoutMinutes}"`);
    assert.equal(input(judge, "model"), "${{ steps.models.outputs.model }}");
    assert.equal(input(judge, "effort"), "${{ steps.models.outputs.effort }}");
    assert.equal(input(judge, "max-turns"), "${{ steps.models.outputs.max-turns }}");
    assert.deepEqual(envOf(judge), JUDGE.stepEnv);
  });

  test(`${job}: the prompt, schema and data directory are the replay's`, () => {
    const prompt = step(job, "Write the prompt and schema");
    assert.match(prompt, /prompt=\$\(<\.base\/\.github\/scripts\/pr-verify\/prompt\.md\)/);
    assert.equal(envOf(prompt).DATA, `\${{ github.workspace }}/${JUDGE.dataDir}`);
    const substitutions = [...prompt.matchAll(/prompt=\$\{prompt\/\/([A-Z_]+)\/\$DATA\/([\w.-]+)\}/g)].map(([, token, file]) => [token, file]);
    assert.deepEqual(substitutions, JUDGE.promptSubstitutions);
    assert.match(prompt, /printf '%s\\n' "\$prompt" >"\$PROMPT_FILE"/);
    const schema = /printf '%s\\n' '(\{.*\})' >"\$SCHEMA_FILE"/.exec(prompt)?.[1];
    assert.deepEqual(JSON.parse(schema), JUDGE.schema);
    assert.equal(input(step(job, "Resolve the verifier's model"), "model-route"), JUDGE.modelRoute);
  });

  test(`${job}: run-claude-cli and the managed settings are at the replay's pin`, () => {
    for (const [name, action] of [
      ["Judge the pull request", "run-claude-cli"],
      ["Apply the Claude managed settings", "apply-claude-managed-settings"],
    ]) {
      const uses = /^ {8}uses: (.*)$/m.exec(step(job, name))?.[1];
      assert.match(uses, new RegExp(`^melodic-software/ci-workflows/\\.github/actions/${action}@${RUN_CLAUDE_CLI_PIN} # v`));
      // No `settings` input: the action's default JSON, which MANAGED_SETTINGS holds.
      if (action === "apply-claude-managed-settings") {
        assert.doesNotMatch(step(job, name), /\n {8}with:/);
      }
    }
  });
}

// Pin tests: the expected values are run-claude-cli's lane.cjs cliArgs and
// legEnv and the action's input defaults at RUN_CLAUDE_CLI_PIN, plus the one
// replay-only flag, --settings.
test("cliArgs is lane.cjs's argv for this lane, plus --settings", () => {
  assert.deepEqual(cliArgs({ model: "opus", effort: "", maxTurns: 60, settingsFile: "/c/managed-settings.json" }), [
    "-p",
    "--output-format",
    "stream-json",
    "--verbose",
    "--model",
    "opus",
    "--max-turns",
    "60",
    "--permission-mode",
    "dontAsk",
    "--permission-prompts",
    "none",
    "--restricted",
    "--strict-mcp-config",
    "--no-session-persistence",
    "--settings",
    "/c/managed-settings.json",
    "--tools",
    "Read",
    "--json-schema",
    '{"type":"object","properties":{"verdict":{"enum":["pass","pass-notes","fail"]},"summary":{"type":"string"},"notes":{"type":"array","items":{"type":"string"}}},"required":["verdict","summary","notes"],"additionalProperties":false}',
    "--disallowedTools",
    "Read(./.base/**)",
    "Glob",
    "Grep",
    "Bash",
    "Edit",
    "Write",
    "NotebookEdit",
    "WebFetch",
    "WebSearch",
    "Agent",
    "mcp__*",
    "--allowedTools",
    "Read(./pr-verify-data/**)",
  ]);
  assert.deepEqual(cliArgs({ model: "sonnet", effort: "high", maxTurns: 5, settingsFile: "/s" }).slice(4, 10), [
    "--model",
    "sonnet",
    "--effort",
    "high",
    "--max-turns",
    "5",
  ]);
});

test("the runner's CLI version, environment additions and managed settings", () => {
  assert.equal(CLI_VERSION, "2.1.304");
  assert.deepEqual(LEG_ENV, {
    CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1",
    CLAUDE_CODE_RETRY_WATCHDOG: "1",
    CLAUDE_CODE_RETRY_WATCHDOG_MAX_WAIT_MS: "1800000",
  });
  assert.deepEqual(MANAGED_SETTINGS, {
    apiKeyHelper: "",
    allowManagedHooksOnly: true,
    env: { ANTHROPIC_BASE_URL: "https://api.anthropic.com" },
    permissions: { disableBypassPermissionsMode: "disable" },
  });
});

test("legEnv passes only the allowlist, the runner's additions and the one credential", () => {
  const env = legEnv({
    base: {
      PATH: "/operator/tools:/usr/bin",
      LANG: "C.UTF-8",
      ANTHROPIC_API_KEY: "operator-key",
      ANTHROPIC_BASE_URL: "https://proxy.invalid",
      NODE_OPTIONS: "--require x",
      GITHUB_OUTPUT: "/tmp/out",
      CLAUDE_CONFIG_DIR: "/operator/.claude",
    },
    home: "/r/home",
    configDir: "/r/config",
    token: "subscription-token",
  });
  assert.deepEqual(env, {
    PATH: `${path.dirname(process.execPath)}:/usr/local/bin:/usr/bin:/bin`,
    LANG: "C.UTF-8",
    HOME: "/r/home",
    CLAUDE_CONFIG_DIR: "/r/config",
    CI: "true",
    GITHUB_ACTIONS: "true",
    CLAUDE_CODE_DISABLE_BACKGROUND_TASKS: "1",
    CLAUDE_CODE_OAUTH_TOKEN: "subscription-token",
    CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1",
    CLAUDE_CODE_RETRY_WATCHDOG: "1",
    CLAUDE_CODE_RETRY_WATCHDOG_MAX_WAIT_MS: "1800000",
  });
});

test("promptText writes the prompt as the bash step does, after the preamble", () => {
  // $(<file) drops trailing newlines, each ${prompt//TOKEN/...} replaces every
  // occurrence, printf '%s\n' adds one newline, and lane.cjs puts the trimmed
  // preamble and a blank line in front.
  const source = "Read DIFF_FILE, SPEC_TEXT_FILE and SPEC_FILE; DIFF_FILE again.\n\n\n";
  assert.equal(
    promptText(source, "/w/pr-verify-data"),
    "You run unattended; return only the verdict the schema asks for; nothing you write is posted.\n\n" +
      "Read /w/pr-verify-data/diff.patch, /w/pr-verify-data/spec-text.json and /w/pr-verify-data/spec.json; /w/pr-verify-data/diff.patch again.\n",
  );
});
