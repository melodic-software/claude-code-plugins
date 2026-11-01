// eval-browser-dispatch.yml's pull request path keeps the eval credential out
// of what a pull request's prompts can read or publish: a root-owned managed
// policy denies reads of process and runner state before sudo is removed,
// the summary is redacted, and no results artifact is uploaded.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/eval-browser-dispatch.yml", import.meta.url), "utf8");
const step = (name) => {
  const start = text.indexOf(`- name: ${name}\n`);
  assert.ok(start > 0, `step ${name}`);
  return text.slice(start).split("\n      - name:")[0];
};

test("a pull request run denies reads of /proc and runner state before sudo is removed", () => {
  const deny = step("Deny the eval's reads of process and runner state");
  assert.match(deny, /if: steps\.stage\.outputs\.go == 'true' && github\.event_name == 'pull_request'\n/);
  for (const rule of ["Read(//proc/**)", "Read(//sys/**)", "Read(//home/runner/runners/**)", "Read(//home/runner/actions-runner/**)"]) {
    assert.ok(deny.includes(`"${rule}"`), rule);
  }
  // The runner's own directory comes from the Runner.Worker process, and _temp and _actions sit beside the workspace.
  assert.match(deny, /case "\$exe" in \*\/bin\/Runner\.Worker\) runner_root=/);
  assert.match(deny, /--arg runner "Read\(\/\$runner_root\/\*\*\)" --arg temp "Read\(\/\$work\/_temp\/\*\*\)" --arg actions "Read\(\/\$work\/_actions\/\*\*\)"/);
  assert.match(deny, /if \[ -z "\$runner_root" \]; then\n\s+echo "::error::[^"]+"\n\s+exit 1/);
  assert.match(deny, /sudo install -D -m 0644 -o root -g root "\$policy" \/etc\/claude-code\/managed-settings\.json/);
  assert.match(deny, /jq -e '\.permissions\.deny \| index\("Read\(\/\/proc\/\*\*\)"\)'/);
  assert.ok(text.indexOf("- name: Deny the eval's reads") < text.indexOf("- name: Isolate the runner"));
  assert.ok(text.indexOf("- name: Deny the eval's reads") < text.indexOf("- name: Run the plugin eval"));
});

test("a pull request run proves the policy denies the reads before any case runs", () => {
  const probe = step("Probe that the policy denies those reads");
  assert.match(probe, /if: steps\.stage\.outputs\.go == 'true' && github\.event_name == 'pull_request'\n/);
  assert.match(probe, /RUNNER_ROOT: \$\{\{ steps\.deny\.outputs\.runner-root \}\}/);
  assert.match(probe, /--allowedTools Read Grep Glob /);
  assert.match(probe, /any\(\.permission_denials\[\]\?; \.tool_name == \$t and/);
  for (const call of ["Read /proc/self/environ", 'Read "$RUNNER_ROOT/.runner"', "Grep /proc/self", "Glob /proc/self"]) {
    assert.ok(probe.includes(`\n          denied ${call}\n`), `the probe checks a denied ${call}`);
  }
  assert.match(probe, /if grep -qF "\$CLAUDE_CODE_OAUTH_TOKEN" "\$out"; then\n[^\n]*\n {12}exit 1/);
  assert.match(probe, /trap 'rm -f "\$out"' EXIT/);
  assert.doesNotMatch(probe, /cat "\$out"|jq [^\n]*"\$out"[^\n]*\| *tee/);
  assert.ok(text.indexOf("- name: Install the locked root toolchain") < text.indexOf("- name: Probe that the policy"));
  assert.ok(text.indexOf("- name: Probe that the policy") < text.indexOf("- name: Run the plugin eval"));
});

test("each summary also reaches the job log and the results folder, with workflow commands off", () => {
  const summarize = step("Summarize the results");
  assert.match(summarize, /summarize\.mjs "\$results" [^\n]*>"\$summary" \|\| failed=1\n/);
  assert.match(summarize, /summary="\$OUT\/\$name\/summary\.md"\n/);
  assert.match(summarize, /cat "\$summary" >>"\$GITHUB_STEP_SUMMARY"\n/);
  assert.match(summarize, /echo "::stop-commands::\$token"\n\s+cat "\$summary"\n\s+echo "::\$token::"\n/);
});

test("a pull request run redacts its summary and uploads no results", () => {
  assert.match(step("Summarize the results"), /REDACT: \$\{\{ github\.event_name == 'pull_request' && '--redact' \|\| '' \}\}/);
  assert.match(step("Summarize the results"), /summarize\.mjs "\$results" --plugin "\$name" "\$\{redact\[@\]\}"/);
  // Only a dispatched run scans and uploads, and the upload needs the scan's clean output.
  const scan = step("Scan the upload for credentials");
  assert.match(scan, /if: >-\n {10}always\(\) && steps\.stage\.outputs\.go == 'true' && github\.event_name == 'workflow_dispatch'\n/);
  assert.match(scan, /\n {8}id: scan-upload\n/);
  assert.match(scan, /\n {10}path: \$\{\{ runner\.temp \}\}\/eval-results\/\n/);
  assert.match(
    step("Upload the eval results"),
    /if: >-\n {10}\(always\(\) && steps\.stage\.outputs\.go == 'true' && github\.event_name == 'workflow_dispatch'\) && steps\.scan-upload\.outputs\.clean == 'true'\n/,
  );
  assert.ok(text.indexOf("- name: Scan the upload for credentials") < text.indexOf("- name: Upload the eval results"));
});
