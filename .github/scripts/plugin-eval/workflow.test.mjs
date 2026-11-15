// pr-run-plugin-evals.yml's pull request path keeps the eval credential out
// of what a pull request's prompts can read or publish: a root-owned managed
// policy denies reads of process and runner state before sudo is removed,
// the summary is redacted, and no results artifact is uploaded.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/pr-run-plugin-evals.yml", import.meta.url), "utf8");
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
  // policy-probe.mjs judges the four calls; only its exit 0 lets the step pass.
  const judge = 'reason=$(env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN PROBE="$out" node .base/.github/scripts/plugin-eval/policy-probe.mjs) || judged=$?';
  assert.ok(probe.includes(judge), "the judge runs from the base checkout without the credential");
  assert.match(probe, /\n {10}case \$judged in\n {12}0\) echo "\$reason" ;;\n {12}3\) echo "::error::[^\n]*"; exit 1 ;;\n {12}\*\) echo "::error::[^\n]*"; exit 1 ;;\n {10}esac\n/);
  // The leak check looks for the leg's own credential, whichever leg runs.
  assert.match(probe, /credential=\$\{ANTHROPIC_API_KEY:-\$\{CLAUDE_CODE_OAUTH_TOKEN:-\}\}\n {10}\[ -n "\$credential" \] \|\| /);
  assert.match(probe, /if grep -qF "\$credential" "\$out"; then\n[^\n]*\n {14}exit 1/);
  assert.match(probe, /trap 'rm -f "\$out"' EXIT/);
  // A probe the credential's own stop ended hands off before the denial checks, never past them.
  assert.ok(probe.indexOf("eval-handoff.mjs") < probe.indexOf("policy-probe.mjs"));
  assert.ok(probe.indexOf('if grep -qF "$credential"') < probe.indexOf("eval-handoff.mjs"), "the leak check runs before the classifier");
  assert.match(probe, /env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN PROBE="\$out"/, "the classifier runs without the credential");
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

test("a red summary names the failed cases or the suite that did not run in one ::error", () => {
  const summarize = step("Summarize the results");
  assert.match(summarize, /summarize\.mjs "\$results" [^\n]*--annotation "\$annotation" >"\$summary"/);
  // The annotation prints after the stop-commands block ends, so the runner reads it.
  assert.ok(summarize.indexOf('echo "::$token::"') < summarize.indexOf('head -n 1 "$annotation"'));
  assert.match(summarize, /echo "::error title=Plugin eval did not run%3A \$\{name\/\/\[\$'\\r\\n%:,'\]\/_\}::No result was written/);
  // A result summarize.mjs cannot read (exit 2) writes no file, and still annotates.
  assert.match(summarize, /elif \[ ! -e "\$annotation" \]; then\n\s+echo "::error title=Plugin eval did not run%3A [^\n]*::The result could not be read\."/);
});

test("a dispatched run writes the validity bash ran and verdict lines and the noise report into its uploaded results", () => {
  const summarize = step("Summarize the results");
  assert.match(summarize, /DISPATCHED: \$\{\{ github\.event_name == 'workflow_dispatch' \}\}\n/);
  assert.match(summarize, /RUNS: \$\{\{ inputs\.runs \}\}\n/);
  assert.match(summarize, /if \[ "\$DISPATCHED" = true \]; then\n\s+validity=\$\(python3 \.base\/plugins\/evals\/skills\/plugin-eval\/scripts\/run-validity\.py "\$results" --runs "\$RUNS" --scaffolded\) \|\| true\n/);
  // Only the count-only bash ran line and the last line leave the runner:
  // run-validity's detail lines can quote a trace.
  assert.match(summarize, /bash_ran=\$\(printf '%s\\n' "\$validity" \| tail -n 2 \| head -n 1 \| grep -xE 'bash ran: \(n\/a\|\[a-z-\]\+ /);
  assert.match(summarize, /verdict=\$\(printf '%s\\n' "\$validity" \| tail -n 1\)\n/);
  assert.match(summarize, /printf '%s\\n' \$\{bash_ran:\+"\$bash_ran"\} "\$verdict" >"\$OUT\/\$name\/validity\.txt"\n/);
  assert.match(summarize, /printf '\\nValidity: %s\\n' "\$verdict" >>"\$summary"\n/);
  assert.match(summarize, /if \[ -n "\$bash_ran" \]; then printf '\\n%s\\n' "\$bash_ran" >>"\$summary"; fi\n/);
  assert.match(summarize, /noise-report\.py "\$results" >"\$OUT\/\$name\/noise\.txt"/);
  assert.doesNotMatch(summarize, /\$validity"? >/);
});

test("a pull request run redacts its summary and uploads no results", () => {
  assert.match(step("Summarize the results"), /REDACT: \$\{\{ github\.event_name == 'pull_request' && '--redact' \|\| '' \}\}/);
  assert.match(step("Summarize the results"), /summarize\.mjs "\$results" --plugin "\$name" "\$\{redact\[@\]\}"/);
  // Only a dispatched run scans and uploads, and the upload needs the scan's clean output.
  // A leg that handed off to the next credential uploads nothing.
  const scan = step("Scan the upload for credentials");
  assert.match(scan, /if: >-\n {10}always\(\) && steps\.stage\.outputs\.go == 'true' && github\.event_name == 'workflow_dispatch' && steps\.judge\.outputs\.handoff != 'true'\n/);
  assert.match(scan, /\n {8}id: scan-upload\n/);
  assert.match(scan, /\n {10}path: \$\{\{ runner\.temp \}\}\/eval-results\/\n/);
  assert.match(
    step("Upload the eval results"),
    /if: >-\n {10}\(always\(\) && steps\.stage\.outputs\.go == 'true' && github\.event_name == 'workflow_dispatch' && steps\.judge\.outputs\.handoff != 'true'\) && steps\.scan-upload\.outputs\.clean == 'true'\n/,
  );
  assert.ok(text.indexOf("- name: Scan the upload for credentials") < text.indexOf("- name: Upload the eval results"));
});

test("every eval leg takes its cost ceiling from the checked max-cost-usd input, default 5, at most 12", () => {
  assert.equal(text.match(/--max-cost-usd "\$MAX_COST"/g).length, 3);
  assert.doesNotMatch(text, /--max-cost-usd \d/);
  assert.equal(text.match(/MAX_COST: \$\{\{ inputs\.max-cost-usd \|\| 5 \}\}/g).length, 3);
  const guards = text.match(/if ! \[\[ \$MAX_COST .*?\n\s+fi\n/gs);
  assert.equal(guards.length, 3);
  const passes = (value) => spawnSync("bash", ["-c", guards[0]], { env: { MAX_COST: value } }).status === 0;
  for (const value of ["1", "5", "12"]) {
    assert.ok(passes(value), value);
  }
  for (const value of ["", "0", "13", "2.5", "1;true", "-1"]) {
    assert.ok(!passes(value), value);
  }
});
