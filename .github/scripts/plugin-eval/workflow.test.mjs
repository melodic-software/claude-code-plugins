// pr-run-plugin-evals.yml's pull request path keeps the eval credential out
// of what a pull request's prompts can read or publish: a root-owned managed
// policy denies reads of process and runner state before sudo is removed,
// the summary is redacted, and no results artifact is uploaded.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { evaluate } from "../lib/gate-expression.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const text = readFileSync(new URL("../../workflows/pr-run-plugin-evals.yml", import.meta.url), "utf8");
const step = (name) => {
  const start = text.indexOf(`- name: ${name}\n`);
  assert.ok(start > 0, `step ${name}`);
  return text.slice(start).split("\n      - name:")[0];
};

test("a pull request run denies reads of /proc and runner state before sudo is removed", () => {
  const deny = step("Deny the eval's reads of process and runner state");
  assert.match(deny, /if: steps\.stage\.outputs\.go == 'true' && github\.event_name == 'workflow_run'\n/);
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
  assert.match(probe, /if: steps\.stage\.outputs\.go == 'true' && github\.event_name == 'workflow_run'\n/);
  assert.match(probe, /RUNNER_ROOT: \$\{\{ steps\.deny\.outputs\.runner-root \}\}/);
  assert.match(probe, /--allowedTools Read Grep Glob /);
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
  assert.match(summarize, /\(, unknown \[0-9\]\+\)\?\)\(, absent tool \[0-9\]\+\)\?' \|\| true\)\n/);
  assert.match(summarize, /verdict=\$\(printf '%s\\n' "\$validity" \| tail -n 1\)\n/);
  assert.match(summarize, /printf '%s\\n' \$\{bash_ran:\+"\$bash_ran"\} "\$verdict" >"\$OUT\/\$name\/validity\.txt"\n/);
  assert.match(summarize, /printf '\\nValidity: %s\\n' "\$verdict" >>"\$summary"\n/);
  assert.match(summarize, /if \[ -n "\$bash_ran" \]; then printf '\\n%s\\n' "\$bash_ran" >>"\$summary"; fi\n/);
  assert.match(summarize, /noise-report\.py "\$results" >"\$OUT\/\$name\/noise\.txt"/);
  assert.doesNotMatch(summarize, /\$validity"? >/);
});

test("both legs of a dispatched suite run keep each run's final reply beside its results.json for the upload", () => {
  const capture =
    /if \[ "\$DISPATCHED" = true \]; then\n(?: +[^\n]*\n){5}\s+node \.base\/\.github\/scripts\/plugin-eval\/last-messages\.mjs "\$results" "\$OUT\/\$name\/last-messages\.jsonl" \|\|\n\s+echo "::warning::[^"\n]+"\n/g;
  assert.equal(text.match(capture)?.length, 2);
  const job = (name) => text.slice(text.indexOf(`\n  ${name}:\n`)).split("\n    steps:\n")[0];
  assert.match(job("check-key-credit"), /inputs\.mode != 'compare'/);
  assert.match(job("run-eval"), /needs: check-key-credit\n[\s\S]*needs\.check-key-credit\.result == 'success'/);
  assert.match(job("run-eval-subscription"), /inputs\.mode != 'compare'/);
});

test("a pull request run redacts its summary and uploads no results", () => {
  assert.match(step("Summarize the results"), /REDACT: \$\{\{ github\.event_name == 'workflow_run' && '--redact' \|\| '' \}\}/);
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

test("each suite leg takes its cost ceiling from the checked max-cost-usd input, default 5, at most 12", () => {
  assert.equal(text.match(/--max-cost-usd "\$MAX_COST"/g).length, 2, "the key leg and the subscription leg");
  assert.doesNotMatch(text, /--max-cost-usd \d/);
  assert.equal(text.match(/MAX_COST: \$\{\{ inputs\.max-cost-usd \|\| 5 \}\}/g).length, 2);
  const guards = text.match(/if ! \[\[ \$MAX_COST .*?\n\s+fi\n/gs);
  assert.equal(guards.length, 2);
  assert.equal(guards[1], guards[0]);
  const passes = (value) => spawnSync("bash", ["-c", guards[0]], { env: { MAX_COST: value } }).status === 0;
  for (const value of ["1", "5", "12"]) {
    assert.ok(passes(value), value);
  }
  for (const value of ["", "0", "13", "2.5", "1;true", "-1"]) {
    assert.ok(!passes(value), value);
  }
});

const compare = text.slice(text.indexOf("\n  compare-prepare:\n"));
const { job } = workflowText(text);
const armsScript = readFileSync(new URL("./compare-arms.sh", import.meta.url), "utf8");

test("compare mode reads the pull request's commits only as git objects for the arm patches", () => {
  assert.equal(text.match(/ref: \$\{\{ inputs\.head-sha \}\}/g).length, 1);
  assert.match(job("compare-prepare"), /ref: \$\{\{ inputs\.head-sha \}\}\n {10}path: \.head\n {10}fetch-depth: 0\n {10}persist-credentials: false\n/);
  assert.deepEqual(compare.match(/[^\n]*\.head(?![\w-])[^\n]*/g).map((line) => line.trim()), ["path: .head", "REPO: .head"]);
  assert.doesNotMatch(compare, /working-directory|\.\/\.head|\.head\//);
  const uses = armsScript.match(/[^\n]*\$REPO[^\n]*/g);
  for (const line of uses) {
    assert.match(line, /git -C "\$REPO" (?:merge-base|diff|ls-tree|read-tree|update-index|write-tree|rev-parse)(?: |$)|--repo "\$REPO"/, line);
  }
  assert.doesNotMatch(armsScript, /\b(?:source|\.)\s+"?\$REPO|bash "?\$REPO|node "?\$REPO|checkout|worktree|apply/);
});

test("compare mode hands each arm the evals key, and the token only for a trusted human's pull request, and stops without a cost cap", () => {
  for (const name of ["compare-before", "compare-after"]) {
    const arm = job(name);
    const secrets = /\n {4}secrets:\n((?: {6}.*\n?)+)/.exec(arm)[1];
    const passed = Object.fromEntries([...secrets.matchAll(/^ {6}([\w-]+): (.*)$/gm)].map((m) => [m[1], m[2]]));
    assert.deepEqual(Object.keys(passed), ["EVALS_CLAUDE_API_KEY", "EVALS_CLAUDE_CODE_OAUTH_TOKEN"], name);
    const allow = /\n {6}allow-subscription: (.*)\n/.exec(arm)[1];
    for (const subscription of ["true", "false", ""]) {
      const ctx = { "needs.compare-prepare.outputs.subscription": subscription, "secrets.EVALS_CLAUDE_API_KEY": "key", "secrets.EVALS_CLAUDE_CODE_OAUTH_TOKEN": "token" };
      assert.equal(evaluate(passed.EVALS_CLAUDE_API_KEY, ctx), "key", `${name} subscription=${subscription}`);
      assert.equal(evaluate(passed.EVALS_CLAUDE_CODE_OAUTH_TOKEN, ctx), subscription === "true" ? "token" : "", `${name} subscription=${subscription}`);
      assert.equal(evaluate(allow, ctx), subscription === "true", `${name} subscription=${subscription}`);
    }
    assert.match(arm, /max-cost-usd: \$\{\{ fromJSON\(inputs\.cost-cap-usd\) \}\}/, name);
    assert.match(arm, /\n {6}cases: \$\{\{ inputs\.cases \}\}\n/, name);
    assert.match(arm, /\n {6}ablation: none\n/, name);
    assert.match(job(name), /\n {4}needs: compare-prepare\n {4}if: >-\n {6}needs\.compare-prepare\.result == 'success'\n/, `${name} runs only after compare-prepare passed`);
  }
  assert.doesNotMatch(compare, /FALLBACK_CLAUDE_CODE_OAUTH_TOKEN|secrets: inherit/);
  assert.doesNotMatch(text, /\n {6}credential:\n|inputs\.credential/, "no input chooses the credential: the key runs first");
  assert.match(text, /cost-cap-usd:\n(?: {8}[^\n]*\n)*? {8}default: ""\n/);
  const guard = /if ! \[\[ \$COST_CAP .*?\n\s+fi\n/s.exec(job("compare-prepare"))[0];
  const passes = (value) => spawnSync("bash", ["-c", guard], { env: { COST_CAP: value } }).status === 0;
  assert.ok(passes("1") && passes("12"));
  for (const value of ["", "0", "13", "2.5"]) assert.ok(!passes(value), value);
  const filter = /read -ra tags <<<"\$TAGS"\n.*?\n\s+done\n/s.exec(job("compare-prepare"))[0];
  const selects = (env) => spawnSync("bash", ["-c", filter], { env }).status === 0;
  assert.ok(!selects({ CASE: "", CASES: "", TAGS: "" }), "no case, cases, or tag runs nothing");
  assert.ok(selects({ CASE: "p1-*", CASES: "", TAGS: "" }));
  assert.ok(selects({ CASE: "", CASES: "", TAGS: "interview" }));
  assert.ok(selects({ CASE: "", CASES: "c1 c2", TAGS: "" }));
  assert.ok(!selects({ CASE: "p1-*", CASES: "c1", TAGS: "" }), "case and cases cannot both be set");
  assert.ok(!selects({ CASE: "", CASES: "-bad", TAGS: "" }), "cases name must not start with -");
  assert.ok(!selects({ CASE: "", CASES: "ok -bad", TAGS: "" }), "later cases name must not start with -");
  assert.match(job("compare-record"), /if \[ "\$GITHUB_RUN_ATTEMPT" != 1 \]; then/);
});

test("only the compare record job writes, after the verdict and a fresh head check", () => {
  assert.deepEqual(compare.match(/[a-z-]+: write/g), ["pull-requests: write"]);
  const record = job("compare-record");
  assert.match(record, /\n {6}pull-requests: write\n/, "a comment on a pull request needs pull-requests: write, issues: write gets a 403");
  assert.match(record, /needs: \[compare-prepare, compare-verdict\]\n/);
  assert.ok(record.indexOf("compare-head.sh") > 0 && record.indexOf("compare-head.sh") < record.indexOf("- name: Post the record"));
  assert.doesNotMatch(record, /inputs\.head-sha \}\}\n {10}path/);
  assert.match(job("compare-verdict"), /needs: \[compare-prepare, compare-before, compare-after\]\n/);
  assert.doesNotMatch(job("compare-verdict"), /\n {4}if:/);
  assert.doesNotMatch(record, /\n {4}if:/);
});

test("the record job's name is the one the release requires to have succeeded", async () => {
  const { RECORD_JOB } = await import("../pr-merge/release-eval-hold.mjs");
  assert.match(job("compare-record"), new RegExp(`^ {2}compare-record:\\n {4}name: ${RECORD_JOB}\\n`));
});

test("the verdict job's name is the one whose failure keeps a cannot-start release back", async () => {
  const { VERDICT_JOB } = await import("../pr-merge/release-eval-hold.mjs");
  assert.match(job("compare-verdict"), new RegExp(`^ {2}compare-verdict:\\n {4}name: ${VERDICT_JOB}\\n`));
});

test("compare mode leaves the suite legs out, and its run name is the one the release reads back", async () => {
  assert.match(text, /name: Check Key Credit\n(?: {4}#[^\n]*\n)* {4}if: >-\n {6}vars\.CLAUDE_EVALS_DISABLED == 'false' && \(\(github\.event_name == 'workflow_dispatch' && inputs\.mode != 'compare'\n/);
  assert.match(job("compare-prepare"), /if: >-\n {6}vars\.CLAUDE_EVALS_DISABLED == 'false'\n {6}&& github\.event_name == 'workflow_dispatch' && inputs\.mode == 'compare'\n/);
  assert.match(text, /format\('eval-compare pr=\{0\} head=\{1\}', inputs\.pr, inputs\.head-sha\)/);
  const { runVouches } = await import("../pr-merge/release-eval-hold.mjs");
  const head = "d".repeat(40);
  const run = {
    path: ".github/workflows/pr-run-plugin-evals.yml",
    event: "workflow_dispatch",
    head_branch: "main",
    status: "completed",
    conclusion: "success",
    run_attempt: 1,
    head_sha: "f".repeat(40),
    display_title: `eval-compare pr=12 head=${head}`,
    repository: { full_name: "o/r" },
    head_repository: { full_name: "o/r" },
  };
  assert.deepEqual(runVouches(run, "o/r", "main"), { pr: 12, head });
});

test("a compare run records that compare mode refuses the pull request, after its dispatcher, input and head checks, and runs no arm", async () => {
  const { stepNamed, steps, outputs, jobIf } = workflowText(text);
  const names = steps("compare-prepare").map((s) => s.name);
  const at = (name) => names.indexOf(name);
  for (const check of ["Check the dispatcher is a trusted human", "Check the compare inputs", "Check the pull request head", "Stop on a pull request a bot wrote"]) {
    assert.ok(at(check) >= 0 && at(check) < at("Build the arm patches"), check);
  }
  assert.ok(!names.includes("Check the evals switch"), "compare-prepare stays behind the switch and records no evals-disabled cause");
  const script = (s) => /\n {8}run: \|\n((?: {10}.*\n|\n)+)/.exec(s.text)[1].replace(/^ {10}/gm, "");
  const work = mkdtempSync(join(tmpdir(), "cannot-start-"));
  try {
    const runIn = (body, env) => {
      const output = join(work, `out-${Math.random().toString(36).slice(2)}`);
      writeFileSync(output, "");
      const result = spawnSync("bash", ["-e", "-c", body], { cwd: work, env: { PATH: process.env.PATH, GITHUB_OUTPUT: output, ...env }, encoding: "utf8" });
      return { status: result.status, output: readFileSync(output, "utf8") };
    };
    const arms = stepNamed("compare-prepare", "Build the arm patches");
    mkdirSync(join(work, ".base/.github/scripts/plugin-eval"), { recursive: true });
    for (const [body, status, output] of [
      ["exit 0", 0, ""],
      ['echo refused=true >>"$GITHUB_OUTPUT"; exit 3', 0, "refused=true\ncannot-start=compare-refused\n"],
      ["exit 3", 3, ""],
      ["exit 1", 1, ""],
      ["exit 2", 2, ""],
    ]) {
      writeFileSync(join(work, ".base/.github/scripts/plugin-eval/compare-arms.sh"), `${body}\n`);
      assert.deepEqual(runIn(script(arms), {}), { status, output }, `compare-arms.sh: ${body}`);
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
  assert.equal(outputs("compare-prepare")["cannot-start"], "${{ steps.arms.outputs.cannot-start }}");
  for (const name of ["compare-before", "compare-after"]) {
    const ctx = (cause) => ({
      "needs.compare-prepare.result": "success",
      "needs.compare-prepare.outputs.cannot-start": cause,
      "github.event_name": "workflow_dispatch",
    });
    assert.equal(evaluate(jobIf(name), ctx("")), true, name);
    assert.equal(evaluate(jobIf(name), ctx("compare-refused")), false, name);
  }
  const { CANNOT_START_JOB, CANNOT_START_CAUSES } = await import("../pr-merge/release-eval-hold.mjs");
  assert.deepEqual(CANNOT_START_CAUSES, ["compare-refused"]);
  assert.match(job("compare-cannot-start"), new RegExp(`^ {2}compare-cannot-start:\\n {4}name: "${CANNOT_START_JOB}: \\$\\{\\{ needs\\.compare-prepare\\.outputs\\.cannot-start \\}\\}"\\n {4}needs: compare-prepare\\n`));
  assert.match(job("compare-cannot-start"), /\n {4}permissions: \{\}\n/);
  for (const cause of [...CANNOT_START_CAUSES, "evals-disabled", "", "other"]) {
    const ctx = { "needs.compare-prepare.result": "success", "needs.compare-prepare.outputs.cannot-start": cause };
    assert.equal(evaluate(jobIf("compare-cannot-start"), ctx), CANNOT_START_CAUSES.includes(cause), JSON.stringify(cause));
  }
  assert.equal(evaluate(jobIf("compare-cannot-start"), { "needs.compare-prepare.result": "failure", "needs.compare-prepare.outputs.cannot-start": "compare-refused" }), false);
});

test("cases input reaches stage-suites and run-eval through env, and rejects case+cases together", () => {
  assert.match(text, /\n {6}cases:\n {8}description: Exact case names, space-separated; stages a suite copy with only these cases\. Not with case\.\n {8}required: false\n {8}type: string\n {8}default: ""\n/);
  assert.match(step("Validate and stage the suites"), /CASES: \$\{\{ inputs\.cases \}\}\n/);
  const runStep = step("Run the plugin eval");
  assert.match(runStep, /CASES: \$\{\{ inputs\.cases \}\}\n/);
  const runGuard = /read -ra cases <<< "\$CASES"\n\s+if \[ -n "\$CASE" \].*?\n\s+fi\n/s.exec(runStep)[0];
  const allows = (env) => spawnSync("bash", ["-c", runGuard], { env, encoding: "utf8" });
  const both = allows({ CASE: "a*", CASES: "b" });
  assert.equal(both.status, 1);
  assert.match(both.stdout, /::error::/);
  assert.equal(allows({ CASE: "a*", CASES: "" }).status, 0);
  assert.equal(allows({ CASE: "", CASES: "b c" }).status, 0);
  for (const runBlock of text.matchAll(/\n {8}run: \|\n((?: {10}.*|\n)+)/g)) {
    assert.doesNotMatch(runBlock[1], /\$\{\{\s*inputs\./);
  }
});

test("stage-suites.sh stages evals-selected when CASES is set on a non-deterministic run and passes --cases on a deterministic run", () => {
  const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
  const stageScript = fileURLToPath(new URL("./stage-suites.sh", import.meta.url));
  const work = mkdtempSync(join(tmpdir(), "stage-suites-"));
  try {
    symlinkSync(repoRoot, join(work, ".base"));
    const plugin = join(work, "root/plugins/demo");
    const write = (rel, body) => {
      const full = join(plugin, rel);
      mkdirSync(join(full, ".."), { recursive: true });
      writeFileSync(full, body);
    };
    write(".claude-plugin/plugin.json", JSON.stringify({ name: "demo" }));
    write("evals/det/prompt.md", "Say hi.\n");
    write("evals/det/graders/says-hi.md", "---\ntype: regex\npattern: hi\n---\n");
    write("evals/judged/prompt.md", "Explain.\n");
    write("evals/judged/graders/clear.md", "---\ntype: llm\n---\nThe answer is clear.\n");

    const runStage = (env) => {
      const out = join(work, `gh-out-${Math.random().toString(36).slice(2)}`);
      writeFileSync(out, "");
      const res = spawnSync("bash", [stageScript], {
        cwd: work,
        env: { PATH: process.env.PATH, LIST: "plugins/demo", ROOT: "root", GITHUB_OUTPUT: out, ...env },
        encoding: "utf8",
      });
      return { res, output: readFileSync(out, "utf8") };
    };

    const plain = runStage({ DETERMINISTIC: "false", CASES: "" });
    assert.equal(plain.res.status, 0, plain.res.stderr);
    assert.match(plain.output, /root\/plugins\/demo\tevals\n/);
    assert.ok(!existsSync(join(plugin, "evals-selected")));

    const selected = runStage({ DETERMINISTIC: "false", CASES: "judged" });
    assert.equal(selected.res.status, 0, selected.res.stderr);
    assert.match(selected.output, /root\/plugins\/demo\tevals-selected\n/);
    assert.ok(existsSync(join(plugin, "evals-selected/judged/graders/clear.md")));
    assert.ok(!existsSync(join(plugin, "evals-selected/det")));

    const detSelected = runStage({ DETERMINISTIC: "true", CASES: "det" });
    assert.equal(detSelected.res.status, 0, detSelected.res.stderr);
    assert.match(detSelected.output, /root\/plugins\/demo\tevals-deterministic\n/);
    assert.ok(existsSync(join(plugin, "evals-deterministic/det/graders/says-hi.md")));
    assert.ok(!existsSync(join(plugin, "evals-deterministic/judged")));
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});

test("a compare moves to the subscription token only when its pull request's author is a trusted actor and a listed human", async () => {
  const { step, steps, outputs } = workflowText(text);
  const gate = step("compare-prepare", "author");
  const human = step("compare-prepare", "human");
  assert.match(gate.text, /uses: \.\/\.base\/\.github\/actions\/check-trusted-trigger /);
  assert.equal(gate.if, "", "the author check runs on every compare");
  assert.equal(gate.inputs["pr-number"], "${{ inputs.pr }}");
  assert.equal(gate.inputs["standards-path"], "${{ steps.standards.outputs.path }}");
  const names = steps("compare-prepare").map((s) => s.name);
  assert.ok(names.indexOf("Check a listed human wrote the pull request") < names.indexOf("Build the arm patches"), "the author is settled before any arm is built");
  assert.match(job("compare-prepare"), /\n {6}actions: read\n/, "check-trusted-trigger reads this run's re-runner");
  const subscription = outputs("compare-prepare").subscription;
  for (const [proceed, humanOutcome, moves] of [
    ["true", "success", true],
    ["true", "failure", false],
    ["false", "skipped", false],
    ["", "skipped", false],
  ]) {
    const ctx = { "steps.author.outputs.proceed": proceed, "steps.human.outcome": humanOutcome };
    assert.equal(evaluate(human.if, ctx), proceed === "true", `proceed=${proceed}: the human check runs`);
    assert.equal(evaluate(subscription, ctx), moves, `proceed=${proceed} human=${humanOutcome}`);
  }

  const { evaluateTrigger, loadTrustedList } = await import("../../actions/check-trusted-trigger/check-trusted-trigger.mjs");
  const list = loadTrustedList(fileURLToPath(new URL("../../standards/trusted-actors/trusted-actors.json", import.meta.url)));
  const owner = 153232337;
  const repository = "melodic-software/claude-code-plugins";
  const head = "a".repeat(40);
  const verdict = async (authorId) => {
    const pull = { number: 7, user: { id: authorId }, head: { ref: "feat/x", sha: head, repo: { full_name: repository } }, base: { ref: "main", sha: "b".repeat(40) } };
    const routes = {
      [`GET /repos/${repository}/pulls/7`]: pull,
      [`GET /repos/${repository}/git/ref/heads/feat/x`]: { object: { sha: head } },
      [`GET /repos/${repository}/actions/runs/99`]: { id: 99, run_attempt: 1, triggering_actor: { id: owner } },
    };
    const github = async (method, path) => {
      assert.ok(Object.hasOwn(routes, `${method} ${path}`), `${method} ${path}`);
      return routes[`${method} ${path}`];
    };
    try {
      return await evaluateTrigger({ eventName: "workflow_dispatch", event: { sender: { id: owner }, repository: { default_branch: "main" } }, repository, list, prNumber: "7", runId: "99", runAttempt: "1", github, sleep: async () => {} });
    } catch (error) {
      return { proceed: "false", reason: error.reason };
    }
  };
  assert.equal((await verdict(owner)).proceed, "true", "our own login's pull request");
  assert.equal((await verdict(337595936)).proceed, "true", "our lanes bot's pull request");
  assert.deepEqual(await verdict(12345), { proceed: "false", reason: "untrusted-author" }, "anyone else's pull request");
});

test("a compare on a pull request a bot wrote stays on the key", () => {
  const { stepNamed, steps } = workflowText(text);
  const stop = stepNamed("compare-prepare", "Check a listed human wrote the pull request");
  assert.match(stop.text, /\n {8}continue-on-error: true\n/, "a bot's pull request still compares on the key");
  const names = steps("compare-prepare").map((s) => s.name);
  assert.ok(names.indexOf("Check the pull request author") < names.indexOf("Check a listed human wrote the pull request"));

  const script = /\n {8}run: \|\n((?: {10}.*\n|\n)+)/.exec(stop.text)[1].replace(/^ {10}/gm, "");
  const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
  const work = mkdtempSync(join(tmpdir(), "bot-author-"));
  try {
    symlinkSync(repoRoot, join(work, ".base"));
    mkdirSync(join(work, "bin"));
    const run = (reply) => {
      writeFileSync(join(work, "bin/gh"), `#!/usr/bin/env bash\n${reply}\n`, { mode: 0o755 });
      return spawnSync("bash", ["-c", script], {
        cwd: work,
        env: { PATH: `${join(work, "bin")}:${process.env.PATH}`, PR: "7", GITHUB_REPOSITORY: "o/r", LIST: ".base/.github/standards/trusted-actors/trusted-actors.json" },
        encoding: "utf8",
      });
    };
    assert.equal(run("echo 153232337").status, 0, "our own login's pull request");
    const bot = run("echo 337595936");
    assert.equal(bot.status, 1, "our lanes bot's pull request");
    assert.match(bot.stdout, /::notice::bot-author:/);
    const unread = run("exit 1");
    assert.equal(unread.status, 1, "an unread author");
    assert.match(unread.stdout, /::notice::read-fault:/);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});
