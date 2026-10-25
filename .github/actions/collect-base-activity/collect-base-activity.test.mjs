// Runs the action's skill-staging `run:` script against a throwaway base
// checkout and reads the outputs it appends to GITHUB_OUTPUT. Expected values
// come from the contract (pr-run-activity.md, "Skill activities" and
// "prepare: merge-base"): a writing skill gets the signed-commit tool and the
// instruction to commit; a merge-base skill runs on run-claude-cli alone.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";

import { LIMITS } from "../../scripts/pr-unblock/apply-dependency-verdict.mjs";
import { VERDICTS } from "../../scripts/pr-unblock/review-dependency.mjs";

const ACTION = new URL("./action.yml", import.meta.url);
const COMMIT_TOOL = "mcp__github_file_ops__commit_files";
const COMMIT_SENTENCE = "commit every repository file you changed";
// commit_files takes each file's mode from disk, so a skill that commits
// through it marks new scripts executable first.
const CHMOD_RULE = "Bash(chmod +x *)";
const CHMOD_SENTENCE =
  "run chmod +x on every new or changed file that starts with #! or ends in .sh, because the commit takes each file's mode from disk, then commit";

// Every write lane denies the shell commands that can print a file or the
// environment, read-only ones that need no allow rule
// (https://code.claude.com/docs/en/permissions#read-only-commands) among
// them, and Read of process files and of the checkout's git directory.
const WORKSPACE = "/home/runner/work/repo/repo";
const SHELL_DENIED = [
  "Bash(echo *)",
  "Bash(printf *)",
  "Bash(cat *)",
  "Bash(head *)",
  "Bash(tail *)",
  "Bash(grep *)",
  "Bash(find *)",
  "Bash(env *)",
  "Bash(printenv *)",
  "Bash(strings *)",
  "Bash(od *)",
  "Bash(xxd *)",
  "Bash(diff *)",
  "Bash(sed *)",
  "Bash(awk *)",
  "Bash(sort *)",
  "Bash(cut *)",
  "Bash(tr *)",
  "Bash(base64 *)",
  "Bash(nl *)",
  "Bash(tac *)",
  "Bash(rev *)",
  "Bash(uniq *)",
  "Bash(fold *)",
  "Bash(column *)",
  "Bash(jq *)",
  "Bash(xargs *)",
  "Bash(more *)",
  "Bash(less *)",
  "Bash(wc *)",
  "Read(//proc/**)",
  `Read(/${WORKSPACE}/.git/**)`,
];
// The write lanes' git deny rule: all of git.
const WRITE_GIT_DENIED = ["Bash(git *)"];
// Every write lane also denies Edit on the plugin copy the skill loads from.
const marketplaceDenied = (env) => `Edit(/${env.MARKETPLACE}/**)`;
// The deny rules other than the write lanes' shell, git and plugin-copy sets.
const ownDenied = (denied, env) =>
  denied.filter((rule) => !SHELL_DENIED.includes(rule) && !WRITE_GIT_DENIED.includes(rule) && rule !== marketplaceDenied(env));

// The Bash rules other than the commit grant's chmod rule.
const wrapperRules = (allowed) => allowed.filter((rule) => rule.startsWith("Bash") && rule !== CHMOD_RULE);

// The `run: |` block of the step with `id: skill`, dedented.
function skillScript() {
  const lines = readFileSync(ACTION, "utf8").split("\n");
  const id = lines.findIndex((line) => /^\s+id: skill$/.test(line));
  assert.notEqual(id, -1, "action.yml has the skill step");
  const start = lines.findIndex((line, i) => i > id && /^\s+run: \|$/.test(line));
  const keyIndent = lines[start].search(/\S/);
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && line.search(/\S/) <= keyIndent) break;
    body.push(line);
  }
  const indent = Math.min(...body.filter((l) => l.trim()).map((l) => l.search(/\S/)));
  return body.map((l) => l.slice(indent)).join("\n");
}

let root;
let base;
let resolved;

before(() => {
  root = mkdtempSync(path.join(tmpdir(), "collect-base-activity-"));
  base = path.join(root, "base");
  mkdirSync(path.join(base, "plugins", "source-control"), { recursive: true });
  const docsScripts = path.join(base, "plugins", "discovery", "scripts");
  mkdirSync(docsScripts, { recursive: true });
  for (const name of ["fetch-docs.sh", "docs-cache.sh", "html2md.py"]) writeFileSync(path.join(docsScripts, name), "");
  mkdirSync(path.join(base, ".claude-plugin"));
  writeFileSync(path.join(base, ".claude-plugin", "marketplace.json"), JSON.stringify({ name: "melodic-software" }));
  resolved = path.join(root, "resolved.json");
  writeFileSync(resolved, JSON.stringify({ selected: { args: "ci" } }));
});

after(() => {
  // The check copies are made read-only.
  spawnSync("chmod", ["-R", "u+w", root]);
  rmSync(root, { recursive: true, force: true });
});

function stage(overrides) {
  const runTemp = mkdtempSync(path.join(root, "temp-"));
  const output = path.join(runTemp, "github-output");
  writeFileSync(output, "");
  const envFile = path.join(runTemp, "github-env");
  writeFileSync(envFile, "");
  const env = {
    PATH: process.env.PATH,
    MARKETPLACE: path.join(runTemp, "base-marketplace"),
    DOCS_DIR: path.join(runTemp, "lane-docs"),
    BASE_PATH: base,
    RESOLVED: resolved,
    SKILL: "source-control:resolve-conflicts",
    GATING: "advisory",
    EFFECT: "mutate-branch",
    CAN_COMMIT: "true",
    PREPARE: "",
    SCRATCH: path.join(runTemp, "lane-scratch"),
    WORKSPACE,
    GITHUB_OUTPUT: output,
    GITHUB_ENV: envFile,
    ...overrides,
  };
  const result = spawnSync("bash", ["-e", "-c", skillScript()], { env, encoding: "utf8" });
  const text = readFileSync(output, "utf8");
  const args = /^claude-args=(.*)$/m.exec(text)?.[1] ?? "";
  // The --allowedTools list itself, split at the top-level commas.
  // claude-code-action reads a `\"` inside the quoted list as a literal quote.
  const allowed = (/--allowedTools "((?:[^"\\]|\\.)*)"/.exec(args)?.[1] ?? "").replaceAll('\\"', '"').split(/,(?![^(]*\))/);
  const denied = ((/--disallowedTools "((?:\\.|[^"\\])*)"/.exec(args)?.[1] ?? "").replaceAll('\\"', '"')).split(",").filter(Boolean);
  const prompt = /^prompt<<(\S+)\n([\s\S]*?)\n\1$/m.exec(text)?.[2] ?? "";
  const plugins = (/^plugins<<(\S+)\n([\s\S]*?)\n\1$/m.exec(text)?.[2] ?? "").split("\n").filter(Boolean);
  const jobEnv = readFileSync(envFile, "utf8");
  return { status: result.status, stdout: result.stdout, args, allowed, denied, prompt, plugins, jobEnv, env };
}

test("an issue lane's prompt names the issue before the activity's args", () => {
  const { status, prompt, args } = stage({ SKILL: "work-items:work", ISSUE_NUMBER: "77" });
  assert.equal(status, 0);
  assert.equal(prompt, "/work-items:work --issue 77 ci");
  assert.match(args, /on an issue/);
});

test("a malformed issue number fails red before any output", () => {
  const { status, stdout, prompt } = stage({ SKILL: "work-items:work", ISSUE_NUMBER: "7 --x" });
  assert.notEqual(status, 0);
  assert.match(stdout, /::error::the issue number is malformed/);
  assert.equal(prompt, "");
});

test("a writing skill that can commit gets the commit tool and the instruction to commit", () => {
  const { status, args, allowed } = stage({});
  assert.equal(status, 0);
  assert.ok(allowed.includes(COMMIT_TOOL), allowed.join(" | "));
  assert.ok(args.includes(COMMIT_SENTENCE), args);
  assert.ok(allowed.includes(CHMOD_RULE), allowed.join(" | "));
  assert.ok(args.includes(CHMOD_SENTENCE), args);
});

test("a writing skill gets the Grep and Glob tools, since its shell cannot grep or find", () => {
  for (const overrides of [{}, { CAN_COMMIT: "false" }]) {
    const { status, args, allowed } = stage(overrides);
    assert.equal(status, 0);
    assert.ok(allowed.includes("Grep") && allowed.includes("Glob"), allowed.join(" | "));
    assert.ok(args.includes("Bash(grep *)") && args.includes("Bash(find *)"), args);
  }
});

test("a writing skill with no workspace path fails red before any output", () => {
  for (const WORKSPACE of ["", "relative/path", "/has space"]) {
    const { status, args } = stage({ WORKSPACE });
    assert.notEqual(status, 0, WORKSPACE);
    assert.equal(args, "", WORKSPACE);
  }
});

test("a writing skill that cannot commit gets no chmod rule and no chmod instruction", () => {
  const { status, args, allowed } = stage({ CAN_COMMIT: "false" });
  assert.equal(status, 0);
  assert.ok(!allowed.includes(CHMOD_RULE), allowed.join(" | "));
  assert.ok(!args.includes("chmod"), args);
});

// prepare: merge-base runs only on run-claude-cli, in the read runner (the
// launcher tests below); the claude-code-action path fails red, with checks
// or without.
test("prepare: merge-base on claude-code-action fails red before any output", () => {
  for (const run of [() => stage({ PREPARE: "merge-base" }), () => withChecks(["scripts/check-x.sh --check"], { PREPARE: "merge-base" })]) {
    const { status, stdout, args } = run();
    assert.notEqual(status, 0);
    assert.match(stdout, /::error::merge-base: the skill runs on run-claude-cli, in the read runner/);
    assert.equal(args, "");
  }
});

// pr-run-activity.md, "Skill activities": each listed check runs from the base
// copy against the checkout, through a wrapper that takes no arguments, and
// that wrapper is the only Bash the runner grants.
function withChecks(checks, overrides = {}, selected = {}) {
  const dir = mkdtempSync(path.join(root, "checks-"));
  const workspace = path.join(dir, "workspace");
  mkdirSync(path.join(workspace, "scripts"), { recursive: true });
  mkdirSync(path.join(base, "scripts"), { recursive: true });
  const script = '#!/usr/bin/env bash\necho "from=$0 data=$CHECK_DATA_ROOT pwd=$PWD args=$*"\n';
  writeFileSync(path.join(base, "scripts", "check-x.sh"), script, { mode: 0o755 });
  writeFileSync(path.join(workspace, "scripts", "check-x.sh"), "#!/usr/bin/env bash\necho head code\n", { mode: 0o755 });
  const file = path.join(dir, "resolved.json");
  writeFileSync(file, JSON.stringify({ selected: { args: "ci", checks, ...selected } }));
  const checksDir = path.join(dir, "lane-checks");
  return { workspace, checksDir, ...stage({ RESOLVED: file, CHECKS_DIR: checksDir, WORKSPACE: workspace, ...overrides }) };
}

test("a listed check gets a no-argument wrapper that runs the base copy against the checkout", () => {
  const { status, allowed, args, workspace, checksDir } = withChecks(["scripts/check-x.sh --check"]);
  assert.equal(status, 0);
  const wrapper = path.join(checksDir, "bin", "check-x");
  assert.deepEqual(
    wrapperRules(allowed),
    [`Bash(${wrapper})`],
  );
  assert.ok(args.includes(wrapper), "the system prompt names the check");
  const denied = ((/--disallowedTools "((?:\\.|[^"\\])*)"/.exec(args)?.[1] ?? "").replaceAll('\\"', '"')).split(",");
  assert.ok(denied.includes(`Edit(/${checksDir}/**)`) && denied.includes(`Write(/${checksDir}/**)`), denied.join(" | "));
  const write = spawnSync("bash", ["-c", 'echo x >>"$1"', "_", wrapper], { encoding: "utf8" });
  assert.notEqual(write.status, 0, "the wrapper is read-only");
  const run = spawnSync(wrapper, [], { cwd: root, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(
    run.stdout.trim(),
    `from=${path.join(checksDir, "scripts", "check-x.sh")} data=${workspace} pwd=${workspace} args=--check`,
  );
});

// #8310: self-checks are the skill's own advisory checks; the skill runs
// them through the same wrapper as checks, and the runner does not rerun them.
test("a self-check gets the same no-argument wrapper as a check", () => {
  const { status, allowed, args, workspace, checksDir } = withChecks(undefined, {}, {
    "self-checks": ["scripts/check-x.sh --check"],
  });
  assert.equal(status, 0);
  const wrapper = path.join(checksDir, "bin", "check-x");
  assert.deepEqual(wrapperRules(allowed), [`Bash(${wrapper})`]);
  assert.ok(args.includes(wrapper), "the system prompt names the self-check");
  const run = spawnSync(wrapper, [], { cwd: root, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(
    run.stdout.trim(),
    `from=${path.join(checksDir, "scripts", "check-x.sh")} data=${workspace} pwd=${workspace} args=--check`,
  );
});

// #9096: apply-issue-patch makes each new or changed script executable (the
// issue row's script-exec-bit), so only an issue lane's patch run tells the
// checks to judge the tree with that bit set; a run that commits sets it itself.
const SCRIPT_EXEC_BIT = "export CHECK_AFFECTED_SCRIPT_EXEC_BIT=1";
test("only an issue lane's patch run gets a wrapper that sets the script exec bit", () => {
  const issuePatch = withChecks(["scripts/check-x.sh --check"], { EFFECT: "read", CAN_COMMIT: "false", ISSUE_NUMBER: "7" }, { "applied-by": { patch: "apply-issue-patch" } });
  assert.equal(issuePatch.status, 0, issuePatch.stdout);
  assert.ok(readFileSync(path.join(issuePatch.checksDir, "bin", "check-x"), "utf8").includes(SCRIPT_EXEC_BIT));
  for (const [what, overrides, selected] of [
    ["an issue lane that commits", { ISSUE_NUMBER: "7" }, {}],
    ["a pull request lane that commits", {}, {}],
  ]) {
    const run = withChecks(["scripts/check-x.sh --check"], overrides, selected);
    assert.equal(run.status, 0, what);
    assert.ok(!readFileSync(path.join(run.checksDir, "bin", "check-x"), "utf8").includes(SCRIPT_EXEC_BIT), what);
  }
});

test("checks and self-checks each get a wrapper, and a script in both fails red", () => {
  writeFileSync(path.join(base, "scripts", "check-y.sh"), "#!/usr/bin/env bash\nexit 0\n", { mode: 0o755 });
  try {
    const both = withChecks(["scripts/check-x.sh --check"], {}, { "self-checks": ["scripts/check-y.sh"] });
    assert.equal(both.status, 0);
    assert.deepEqual(wrapperRules(both.allowed), [
      `Bash(${path.join(both.checksDir, "bin", "check-x")})`,
      `Bash(${path.join(both.checksDir, "bin", "check-y")})`,
    ]);
    const dup = withChecks(["scripts/check-x.sh --check"], {}, { "self-checks": ["scripts/check-x.sh"] });
    assert.notEqual(dup.status, 0);
    assert.match(dup.stdout, /::error::two checks run the same script/);
  } finally {
    rmSync(path.join(base, "scripts", "check-y.sh"));
  }
});

// #8310: check-affected.sh passes shellcheck and markdownlint the configs beside
// its copy, and run-ruff.sh reads its pin from .github/requirements-ci.txt there;
// without them the lane's shellcheck reports what CI's does not and ruff skips.
test("a listed check's copy carries the base's shellcheck, markdownlint and ruff-pin files", () => {
  mkdirSync(path.join(base, ".github"), { recursive: true });
  writeFileSync(path.join(base, ".shellcheckrc"), "external-sources=true\n");
  writeFileSync(path.join(base, ".markdownlint-cli2.jsonc"), '{ "config": { "MD013": false } }\n');
  writeFileSync(path.join(base, ".github", "requirements-ci.txt"), "ruff==0.0.1\n");
  try {
    const { status, checksDir } = withChecks(["scripts/check-x.sh --check"]);
    assert.equal(status, 0);
    assert.equal(readFileSync(path.join(checksDir, ".shellcheckrc"), "utf8"), "external-sources=true\n");
    assert.equal(
      readFileSync(path.join(checksDir, ".markdownlint-cli2.jsonc"), "utf8"),
      '{ "config": { "MD013": false } }\n',
    );
    assert.equal(readFileSync(path.join(checksDir, ".github", "requirements-ci.txt"), "utf8"), "ruff==0.0.1\n");
  } finally {
    rmSync(path.join(base, ".shellcheckrc"));
    rmSync(path.join(base, ".markdownlint-cli2.jsonc"));
    rmSync(path.join(base, ".github"), { recursive: true });
  }
});

// A skill that commits runs its checks, fixes and re-runs them before it
// commits, since the checks read the working tree (#8319 review).
test("a committing skill with checks is told to commit after the checks and their fixes", () => {
  const { status, args, allowed } = withChecks(["scripts/check-x.sh --check"]);
  assert.equal(status, 0);
  assert.ok(allowed.includes(COMMIT_TOOL), allowed.join(" | "));
  const systemPrompt = /--append-system-prompt "([^"]*)"/.exec(args)?.[1] ?? "";
  assert.match(systemPrompt, /Run the checks before you commit: run them, fix, run them again, then commit/);
});

// #8319 review: a check's wrapper gets the verify-script wrapper's
// environment, so the check and what it runs never hold the GitHub token or
// load system, global, hook or fsmonitor git config.
test("a listed check's wrapper drops the GitHub token and pins git config", () => {
  const script =
    '#!/usr/bin/env bash\necho "gh=${GH_TOKEN-unset} github=${GITHUB_TOKEN-unset} global=$GIT_CONFIG_GLOBAL system=$GIT_CONFIG_NOSYSTEM hooks=$(git config core.hooksPath) fsmonitor=$(git config core.fsmonitor)"\n';
  mkdirSync(path.join(base, "scripts"), { recursive: true });
  writeFileSync(path.join(base, "scripts", "check-env.sh"), script, { mode: 0o755 });
  try {
    const { status, checksDir } = withChecks(["scripts/check-env.sh"]);
    assert.equal(status, 0);
    const run = spawnSync(path.join(checksDir, "bin", "check-env"), [], {
      cwd: root,
      encoding: "utf8",
      env: { ...process.env, GH_TOKEN: "secret-gh", GITHUB_TOKEN: "secret-github" },
    });
    assert.equal(run.status, 0, run.stderr);
    assert.equal(
      run.stdout.trim(),
      "gh=unset github=unset global=/dev/null system=1 hooks=/dev/null fsmonitor=false",
    );
  } finally {
    rmSync(path.join(base, "scripts", "check-env.sh"));
  }
});

for (const check of ["scripts/check-x.sh; rm -rf /", "../scripts/check-x.sh", "scripts/check-x.sh --x=$(id)", "plugins/a.sh"]) {
  test(`a check outside the allowed shape fails red: ${check}`, () => {
    const { status, stdout, args } = withChecks([check]);
    assert.notEqual(status, 0);
    assert.match(stdout, /::error::a check must be a scripts\/ script with fixed flags/);
    assert.equal(args, "");
  });
}

// pr-run-activity.md, "Skill activities": each listed verify-script runs with
// any arguments from a read-only base copy of its plugin, so a file it reads
// beside itself (here ../../../scripts/lib.sh) comes along, through a wrapper
// that starts in the checkout, refuses paths outside it and pins git config.
const VERIFY = "plugins/vtest/skills/audit/scripts/scan.sh";
function withVerify(list, overrides = {}) {
  const dir = mkdtempSync(path.join(root, "verify-"));
  const workspace = path.join(dir, "workspace");
  mkdirSync(path.join(workspace, "tests"), { recursive: true });
  writeFileSync(path.join(workspace, "tests", "a.test.js"), "");
  writeFileSync(path.join(dir, "secret.txt"), "");
  spawnSync("ln", ["-s", path.join(dir, "secret.txt"), path.join(workspace, "link.txt")]);
  const scripts = path.join(base, "plugins", "vtest", "skills", "audit", "scripts");
  mkdirSync(scripts, { recursive: true });
  mkdirSync(path.join(base, "plugins", "vtest", "scripts"), { recursive: true });
  writeFileSync(
    path.join(scripts, "scan.sh"),
    'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nsource "$here/../../../scripts/lib.sh"\n' +
      'echo "from=$0 lib=$LIB pwd=$PWD git=$GIT_CONFIG_NOSYSTEM,$GIT_CONFIG_GLOBAL,$GIT_CONFIG_KEY_0=$GIT_CONFIG_VALUE_0,$GIT_CONFIG_KEY_1=$GIT_CONFIG_VALUE_1 args=$*"\n',
  );
  writeFileSync(path.join(scripts, "unlisted.sh"), "echo unlisted\n");
  writeFileSync(path.join(base, "plugins", "vtest", "scripts", "lib.sh"), "LIB=base\n");
  const file = path.join(dir, "resolved.json");
  writeFileSync(file, JSON.stringify({ selected: { args: "--ci", "verify-scripts": list } }));
  const verifyDir = path.join(dir, "lane-verify");
  const staged = stage({ SKILL: "work-items:work", RESOLVED: file, VERIFY_DIR: verifyDir, WORKSPACE: workspace, ...overrides });
  return { dir, workspace, verifyDir, wrapper: path.join(verifyDir, "bin", "scan"), ...staged };
}

test("a listed verify-script gets one wrapper rule on a read-only copy that runs in the checkout with any arguments", () => {
  const { status, allowed, denied, args, verifyDir, workspace, wrapper } = withVerify([VERIFY]);
  assert.equal(status, 0);
  const copy = path.join(verifyDir, VERIFY);
  assert.deepEqual(
    wrapperRules(allowed),
    [`Bash(${wrapper} *)`],
  );
  assert.ok(denied.includes(`Edit(/${verifyDir}/**)`) && denied.includes(`Write(/${verifyDir}/**)`), denied.join(" | "));
  assert.ok(args.includes(`${wrapper} <arguments>`), "the system prompt names the command");
  for (const file of [wrapper, copy, path.join(verifyDir, "plugins", "vtest", "scripts", "lib.sh")]) {
    const write = spawnSync("bash", ["-c", 'echo x >>"$1"', "_", file]);
    assert.notEqual(write.status, 0, `${file} is read-only`);
  }
  const run = spawnSync(wrapper, ["--check", "--file", "tests/a.test.js", "a b"], { cwd: root, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(
    run.stdout.trim(),
    `from=${copy} lib=base pwd=${workspace} git=1,/dev/null,core.fsmonitor=false,core.hooksPath=/dev/null args=--check --file tests/a.test.js a b`,
  );
});

// A chained `; echo "$?"` needs approval the dontAsk lane cannot give, so the
// wrapper reports the script's exit status itself and the prompt says so. The
// same sentence steers the run off the compound commands, pipes and
// interpreter one-liners the lane denied in runs 39092789214 and 39092790956.
const RUN_ALONE =
  "Bash runs only the wrappers named in these instructions, each as its own command (a verification wrapper prints the script's exit status): use Read, Grep and Glob to inspect files and Edit or Write to change them, never cd, ;, &&, a pipe or an interpreter one-liner.";
test("the verify-script wrapper prints the script's exit status and exits with it", () => {
  writeFileSync(path.join(base, "plugins", "vtest", "scripts", "fails.sh"), "echo failing\nexit 3\n");
  const { status, args, verifyDir } = withVerify([VERIFY, "plugins/vtest/scripts/fails.sh"]);
  assert.equal(status, 0);
  assert.ok(args.includes(RUN_ALONE), args);
  const run = spawnSync(path.join(verifyDir, "bin", "fails"), ["--check"], { cwd: root, encoding: "utf8" });
  assert.equal(run.status, 3);
  assert.equal(run.stdout, "failing\n");
  assert.equal(run.stderr, "exit status: 3\n");
});

// check-skill.sh runs each skill's scripts/*.test.sh, and the runner's
// /home/runner/.claude is read-only (#8027), so its wrapper alone gives the
// script a fresh, writable HOME and CLAUDE_CONFIG_DIR; another verify-script
// keeps the caller's HOME.
test("only the check-skill.sh wrapper runs with a fresh, writable HOME and CLAUDE_CONFIG_DIR", () => {
  const skillQuality = path.join(base, "plugins", "skill-quality", "scripts");
  mkdirSync(skillQuality, { recursive: true });
  writeFileSync(
    path.join(skillQuality, "check-skill.sh"),
    'ls -A "$HOME" "$CLAUDE_CONFIG_DIR" && touch "$CLAUDE_CONFIG_DIR/w" "$HOME/w" && echo "home=$HOME config=$CLAUDE_CONFIG_DIR"\n',
  );
  mkdirSync(path.join(base, "plugins", "vtest", "scripts"), { recursive: true });
  writeFileSync(path.join(base, "plugins", "vtest", "scripts", "home.sh"), 'echo "home=$HOME config=$CLAUDE_CONFIG_DIR"\n');
  const { status, verifyDir } = withVerify([
    VERIFY,
    "plugins/vtest/scripts/home.sh",
    "plugins/skill-quality/scripts/check-skill.sh",
  ]);
  assert.equal(status, 0);
  const callerHome = path.join(root, "caller-home");
  mkdirSync(callerHome, { recursive: true });
  const env = { ...process.env, HOME: callerHome, CLAUDE_CONFIG_DIR: path.join(callerHome, ".claude") };
  const runs = [1, 2].map(() => spawnSync(path.join(verifyDir, "bin", "check-skill"), [], { cwd: root, env, encoding: "utf8" }));
  const homes = runs.map((run) => {
    assert.equal(run.status, 0, run.stderr);
    const [, home, config] = /home=(\S+) config=(\S+)\n$/.exec(run.stdout) ?? [];
    assert.ok(home && !home.startsWith(callerHome) && !home.startsWith(root), run.stdout);
    assert.equal(config, path.join(home, ".claude"));
    // ls -A printed only the .claude entry of a HOME that held nothing else.
    assert.equal(run.stdout, `${home}:\n.claude\n\n${config}:\nhome=${home} config=${config}\n`);
    return home;
  });
  assert.notEqual(homes[0], homes[1], "each run gets its own directory");
  const other = spawnSync(path.join(verifyDir, "bin", "home"), [], { cwd: root, env, encoding: "utf8" });
  assert.equal(other.status, 0, other.stderr);
  assert.equal(other.stdout, `home=${callerHome} config=${path.join(callerHome, ".claude")}\n`);
});

test("the verify-script wrapper refuses a path outside the checkout", () => {
  const { status, dir, wrapper } = withVerify([VERIFY]);
  assert.equal(status, 0);
  for (const arg of [path.join(dir, "secret.txt"), "../secret.txt", `--file=${path.join(dir, "secret.txt")}`, "link.txt", "/"]) {
    const run = spawnSync(wrapper, ["--file", arg], { cwd: root, encoding: "utf8" });
    assert.notEqual(run.status, 0, arg);
    assert.equal(run.stdout, "", `${arg} ran the script`);
    assert.match(run.stderr, /refused: .* is outside the checkout/, arg);
  }
});

// The wrapper unsets the GitHub token in the script's own environment. This
// does not hide it from an ancestor's /proc/<pid>/environ.
test("the verify-script wrapper runs the script without GH_TOKEN or GITHUB_TOKEN and keeps the rest of the environment", () => {
  mkdirSync(path.join(base, "plugins", "vtest", "scripts"), { recursive: true });
  writeFileSync(
    path.join(base, "plugins", "vtest", "scripts", "env.sh"),
    'echo "GH_TOKEN=${GH_TOKEN-unset} GITHUB_TOKEN=${GITHUB_TOKEN-unset} KEPT=${KEPT-unset}"\n',
  );
  const { status, verifyDir } = withVerify([VERIFY, "plugins/vtest/scripts/env.sh"]);
  assert.equal(status, 0);
  const run = spawnSync(path.join(verifyDir, "bin", "env"), [], {
    cwd: root,
    encoding: "utf8",
    env: { ...process.env, GH_TOKEN: "fake-gh", GITHUB_TOKEN: "fake-github", KEPT: "yes" },
  });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.stdout, "GH_TOKEN=unset GITHUB_TOKEN=unset KEPT=yes\n");
});

// pr-run-activity.md, "Skill activities": the issue lane lists the repository's
// test runner and git-mv-rm.sh as verify-scripts, so the same generator wraps
// them. These stage the real scripts (and the lib they source) into the base.
const REPO = new URL("../../../", import.meta.url);
const LANE_TOOLS = ["scripts/run-test-file.sh", "scripts/git-mv-rm.sh"];
function withLaneTools() {
  for (const file of [...LANE_TOOLS, "scripts/lib/checkout-path.sh"]) {
    mkdirSync(path.join(base, path.dirname(file)), { recursive: true });
    writeFileSync(path.join(base, file), readFileSync(new URL(file, REPO)));
  }
  const staged = withVerify(LANE_TOOLS);
  const { workspace, dir } = staged;
  const git = (...args) => spawnSync("git", ["-C", workspace, ...args], { encoding: "utf8" });
  git("init", "-q");
  writeFileSync(path.join(workspace, "tests", "pass.test.sh"), 'echo "token=${GH_TOKEN:-unset}"\n');
  writeFileSync(path.join(workspace, "tests", "fail.test.sh"), "echo broken\nexit 3\n");
  writeFileSync(path.join(workspace, "tests", "a.test.mjs"), 'import { test } from "node:test";\ntest("a", () => {});\n');
  writeFileSync(path.join(workspace, "tests", "test_a.py"), "");
  writeFileSync(path.join(workspace, "tests", "notes.txt"), "");
  writeFileSync(path.join(dir, "outside.test.sh"), "echo outside\n");
  spawnSync("ln", ["-s", path.join(dir, "outside.test.sh"), path.join(workspace, "tests", "link.test.sh")]);
  spawnSync("ln", ["-s", dir, path.join(workspace, "out")]);
  // Without NODE_TEST_CONTEXT, which turns a nested node --test's report off.
  const { NODE_TEST_CONTEXT, ...parentEnv } = process.env;
  const run = (name, args, env = {}) =>
    spawnSync(path.join(staged.verifyDir, "bin", name), args, {
      cwd: root,
      encoding: "utf8",
      env: { ...parentEnv, GH_TOKEN: "fake-lane-token", ...env },
    });
  return { ...staged, git, run };
}

test("the lane tools get wrapper rules, and the commit grant gains delete_files", () => {
  const { status, allowed, verifyDir } = withLaneTools();
  assert.equal(status, 0);
  assert.deepEqual(
    wrapperRules(allowed),
    [`Bash(${path.join(verifyDir, "bin", "run-test-file")} *)`, `Bash(${path.join(verifyDir, "bin", "git-mv-rm")} *)`],
  );
  assert.ok(allowed.includes("mcp__github_file_ops__delete_files"), allowed.join(" | "));
  assert.ok(!allowed.some((rule) => /^Bash\((python3|bash|node|git)[ )]/.test(rule)), allowed.join(" | "));
});

// The issue lane lists skill-quality's two checks (#7840). check-skill.sh runs
// each skill's scripts/*.test.sh from the checkout, so a fixture skill whose
// test prints the tokens and fails shows what that test saw.
const SKILL_TOOLS = ["plugins/skill-quality/scripts/check-skill.sh", "plugins/skill-quality/scripts/check-evals-quality.sh"];
test("skill-quality's checks get wrapper rules, and check-skill runs a skill's test scripts without the GitHub token", () => {
  spawnSync("cp", ["-R", new URL("plugins/skill-quality", REPO).pathname, path.join(base, "plugins")]);
  const { status, allowed, verifyDir, workspace } = withVerify(SKILL_TOOLS);
  assert.equal(status, 0);
  const bin = (name) => path.join(verifyDir, "bin", name);
  assert.deepEqual(
    wrapperRules(allowed),
    [`Bash(${bin("check-skill")} *)`, `Bash(${bin("check-evals-quality")} *)`],
  );
  const skill = path.join(workspace, "skills", "demo");
  mkdirSync(path.join(skill, "scripts"), { recursive: true });
  writeFileSync(path.join(skill, "SKILL.md"), "---\ndescription: Demo skill. Use when 'demo'.\n---\n\n# Demo\n");
  writeFileSync(path.join(skill, "scripts", "token.test.sh"), 'echo "seen=${GH_TOKEN-unset},${GITHUB_TOKEN-unset}"\nexit 1\n');
  // Like a lane run: the workspace is a checkout, and the test the lane wrote
  // is not committed yet, beside a skills root that holds a tracked file. A
  // failing fixture call fails here, never reads as a skipped test.
  const git = (...args) => {
    const result = spawnSync(
      "git",
      ["-C", workspace, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", ...args],
      { encoding: "utf8" },
    );
    assert.equal(result.status, 0, `git ${args.join(" ")}: ${result.stderr}`);
  };
  git("init", "-q");
  git("config", "user.name", "test");
  git("config", "user.email", "test@example.com");
  git("add", "skills/demo/SKILL.md");
  git("commit", "-qm", "fixture");
  const run = spawnSync(bin("check-skill"), ["skills"], {
    cwd: root,
    encoding: "utf8",
    env: { ...process.env, GH_TOKEN: "fake-gh", GITHUB_TOKEN: "fake-github" },
  });
  assert.match(run.stdout + run.stderr, /script test failed: scripts\/token\.test\.sh/);
  assert.match(run.stdout + run.stderr, /seen=unset,unset/);
});

test("the prompt names run-test-file as the way to run a test and says compound cd commands are refused", () => {
  const { status, args, verifyDir } = withLaneTools();
  assert.equal(status, 0);
  assert.ok(
    args.includes(`Run a test file only through ${path.join(verifyDir, "bin", "run-test-file")} <test file>`),
    args,
  );
  assert.match(args, /a compound command such as cd <dir>; <command> is refused/);
});

test("without run-test-file in the list the prompt names no test entry", () => {
  const { status, args } = withVerify([VERIFY]);
  assert.equal(status, 0);
  assert.ok(!args.includes("Run a test file"), args);
});

test("the prompt names git-mv-rm as the way to rename or delete a file, only when it is listed", () => {
  const lane = withLaneTools();
  assert.equal(lane.status, 0);
  assert.ok(lane.args.includes(`Rename or delete a file with ${path.join(lane.verifyDir, "bin", "git-mv-rm")}.`), lane.args);
  const bare = withVerify([VERIFY]);
  assert.equal(bare.status, 0);
  assert.ok(!bare.args.includes("Rename or delete"), bare.args);
});

// The issue lane lists new-changelog-fragment.sh: from the read-only copy of
// scripts/, it must write the fragment into the checkout it runs in.
test("new-changelog-fragment writes a fragment into the checkout from the read-only copy", () => {
  const files = ["scripts/new-changelog-fragment.sh", "scripts/lib/changelog-fragments.sh", "scripts/lib/read-list.sh"];
  for (const file of files) {
    mkdirSync(path.join(base, path.dirname(file)), { recursive: true });
    writeFileSync(path.join(base, file), readFileSync(new URL(file, REPO)));
  }
  const { status, verifyDir, workspace } = withVerify([files[0]]);
  assert.equal(status, 0);
  spawnSync("git", ["-C", workspace, "init", "-q"]);
  spawnSync("git", ["-C", workspace, "symbolic-ref", "HEAD", "refs/heads/fix/x"]);
  mkdirSync(path.join(workspace, "plugins", "alpha", ".claude-plugin"), { recursive: true });
  writeFileSync(path.join(workspace, "plugins", "alpha", ".claude-plugin", "plugin.json"), '{"name":"alpha"}\n');
  mkdirSync(path.join(workspace, "scripts"), { recursive: true });
  writeFileSync(path.join(workspace, "scripts", "fragment-plugins.txt"), "alpha\n");
  const run = spawnSync(path.join(verifyDir, "bin", "new-changelog-fragment"), ["alpha", "patch"], { cwd: root, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  assert.match(run.stdout, /^\.changes\/alpha\/fix-x-[0-9a-f]{8}\.md\n$/);
  assert.equal(readFileSync(path.join(workspace, run.stdout.trim()), "utf8"), "---\nbump: patch\n---\n\n");
});

test("run-test-file runs an in-checkout test file by its runner and prints the exit status", () => {
  const { status, run, dir } = withLaneTools();
  assert.equal(status, 0);
  const pass = run("run-test-file", ["tests/pass.test.sh"]);
  assert.equal(pass.status, 0, pass.stderr);
  assert.equal(pass.stdout, "token=unset\n", "the test gets no GitHub token");
  assert.equal(pass.stderr, "exit status: 0\n");
  const fail = run("run-test-file", ["tests/fail.test.sh"]);
  assert.equal(fail.status, 3);
  assert.equal(fail.stdout, "broken\n");
  assert.equal(fail.stderr, "exit status: 3\n");
  const node = run("run-test-file", ["tests/a.test.mjs"]);
  assert.equal(node.status, 0, node.stderr);
  assert.match(node.stdout, /pass 1/);
  assert.match(node.stderr, /exit status: 0\n$/);
  // pytest for test_*.py, through whichever python3 is on PATH.
  const shim = path.join(dir, "shim");
  mkdirSync(shim);
  writeFileSync(path.join(shim, "python3"), '#!/usr/bin/env bash\necho "python3 $*"\nexit 5\n', { mode: 0o755 });
  const py = run("run-test-file", ["tests/test_a.py"], { PATH: `${shim}:${process.env.PATH}` });
  assert.equal(py.status, 5);
  assert.match(py.stdout, /^python3 -m pytest .*tests\/test_a\.py\n$/);
  assert.equal(py.stderr, "exit status: 5\n");
});

test("run-test-file refuses a path outside the checkout, a .. path, a non-test file and an option", () => {
  const { status, run, dir } = withLaneTools();
  assert.equal(status, 0);
  for (const args of [
    [path.join(dir, "outside.test.sh")],
    ["../outside.test.sh"],
    ["tests/../tests/pass.test.sh"],
    ["tests/link.test.sh"],
    ["out/outside.test.sh"],
    ["tests/notes.txt"],
    ["tests/missing.test.sh"],
    ["-x"],
    ["tests/pass.test.sh", "tests/fail.test.sh"],
    [],
  ]) {
    const result = run("run-test-file", args);
    assert.equal(result.status, 2, JSON.stringify(args));
    assert.equal(result.stdout, "", `${JSON.stringify(args)} ran a test`);
    assert.match(result.stderr, /refused|usage/, JSON.stringify(args));
  }
});

test("git-mv-rm renames and removes tracked and new files inside the checkout", () => {
  const { status, run, git, workspace } = withLaneTools();
  assert.equal(status, 0);
  git("add", "tests/notes.txt");
  git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base");
  writeFileSync(path.join(workspace, "new.md"), "new\n");
  for (const args of [
    ["mv", "tests/notes.txt", "tests/renamed.txt"],
    ["mv", "new.md", "tests/new.md"],
    ["rm", "tests/new.md", "tests/fail.test.sh"],
  ]) {
    const result = run("git-mv-rm", args);
    assert.equal(result.status, 0, `${args.join(" ")}: ${result.stderr}`);
    assert.match(result.stderr, /exit status: 0\n$/);
  }
  assert.equal(git("status", "--porcelain", "--", "tests/renamed.txt", "tests/notes.txt").stdout, "R  tests/notes.txt -> tests/renamed.txt\n");
  for (const gone of ["new.md", "tests/new.md", "tests/fail.test.sh"]) {
    assert.throws(() => statSync(path.join(workspace, gone)), gone);
  }
});

test("git-mv-rm refuses an absolute path, a .. segment, a path through a link out, an option and the checkout itself", () => {
  const { status, run, dir, workspace } = withLaneTools();
  assert.equal(status, 0);
  for (const args of [
    ["mv", "tests/notes.txt", path.join(dir, "taken.txt")],
    ["mv", "tests/notes.txt", "../taken.txt"],
    ["mv", "tests/notes.txt", "tests/../../taken.txt"],
    ["mv", "tests/notes.txt", "out/taken.txt"],
    ["rm", path.join(dir, "secret.txt")],
    ["rm", "out/secret.txt"],
    ["rm", "--pathspec-from-file=tests/notes.txt"],
    ["rm", "."],
    ["mv", "tests/notes.txt"],
    ["cp", "tests/notes.txt", "tests/x.txt"],
  ]) {
    const result = run("git-mv-rm", args);
    assert.equal(result.status, 2, args.join(" "));
    assert.match(result.stderr, /refused|usage/, args.join(" "));
  }
  statSync(path.join(workspace, "tests", "notes.txt"));
  statSync(path.join(dir, "secret.txt"));
  assert.throws(() => statSync(path.join(dir, "taken.txt")));
});

// git reads a path argument as a pathspec, so a glob or a `:(...)` magic
// prefix would reach files the path check never saw.
test("git-mv-rm treats every path literally: a glob removes nothing else and magic is refused", () => {
  const { status, run, git, workspace } = withLaneTools();
  assert.equal(status, 0);
  writeFileSync(path.join(workspace, "tests", "a*b"), "");
  writeFileSync(path.join(workspace, "tests", "aXb"), "");
  git("add", "tests");
  git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base");
  const star = run("git-mv-rm", ["rm", "tests/*"]);
  assert.notEqual(star.status, 0, "no file is literally named *");
  const magic = run("git-mv-rm", ["rm", ":(glob)**"]);
  assert.equal(magic.status, 2);
  assert.match(magic.stderr, /refused/);
  const literal = run("git-mv-rm", ["rm", "tests/a*b"]);
  assert.equal(literal.status, 0, literal.stderr);
  for (const kept of ["aXb", "pass.test.sh", "notes.txt"]) statSync(path.join(workspace, "tests", kept));
  assert.throws(() => statSync(path.join(workspace, "tests", "a*b")));
});

test("git-mv-rm renames a new file literally named a*b and leaves aXb untracked", () => {
  const { status, run, git, workspace } = withLaneTools();
  assert.equal(status, 0);
  writeFileSync(path.join(workspace, "a*b"), "");
  writeFileSync(path.join(workspace, "aXb"), "");
  const result = run("git-mv-rm", ["mv", "a*b", "renamed.txt"]);
  assert.equal(result.status, 0, result.stderr);
  statSync(path.join(workspace, "renamed.txt"));
  assert.equal(git("status", "--porcelain", "--", ":(literal)aXb").stdout, "?? aXb\n");
});

test("run-test-file refuses a pytest node id or a name a runner could read as more than a file", () => {
  const { status, run, dir, workspace } = withLaneTools();
  assert.equal(status, 0);
  writeFileSync(path.join(workspace, "tests", "test_a.py::test_x"), "");
  writeFileSync(path.join(workspace, "tests", "test_b[1].py"), "");
  const shim = path.join(dir, "shim");
  mkdirSync(shim);
  writeFileSync(path.join(shim, "python3"), '#!/usr/bin/env bash\necho "python3 $*"\n', { mode: 0o755 });
  for (const file of ["tests/test_a.py::test_x", "tests/test_b[1].py"]) {
    const result = run("run-test-file", [file], { PATH: `${shim}:${process.env.PATH}` });
    assert.equal(result.status, 2, file);
    assert.equal(result.stdout, "", `${file} ran`);
  }
});

// A *.test.js or *.test.ts file that imports vitest runs with its package's
// locked vitest (`npx --no-install vitest run` from the nearest package.json).
// The stand-in installed there prints where it ran and fails a file that says
// BROKEN, so a pass, a failure and the directory are the stand-in's, not the
// script's.
function withVitestPackage(staged) {
  const pkg = path.join(staged.workspace, "plugin");
  const vitest = path.join(pkg, "node_modules", "vitest");
  mkdirSync(path.join(pkg, "src"), { recursive: true });
  mkdirSync(vitest, { recursive: true });
  mkdirSync(path.join(pkg, "node_modules", ".bin"));
  writeFileSync(path.join(pkg, "package.json"), JSON.stringify({ name: "p", devDependencies: { vitest: "1.0.0" } }));
  writeFileSync(path.join(vitest, "package.json"), JSON.stringify({ name: "vitest", version: "1.0.0", bin: { vitest: "vitest.mjs" } }));
  writeFileSync(
    path.join(vitest, "vitest.mjs"),
    '#!/usr/bin/env node\nimport { readFileSync } from "node:fs";\n' +
      'console.log(`vitest cwd=${process.cwd()} args=${process.argv.slice(2).join(" ")}`);\n' +
      'process.exit(readFileSync(process.argv.at(-1), "utf8").includes("BROKEN") ? 1 : 0);\n',
    { mode: 0o755 },
  );
  spawnSync("ln", ["-s", "../vitest/vitest.mjs", path.join(pkg, "node_modules", ".bin", "vitest")]);
  const imports = 'import { test } from "vitest";\n';
  writeFileSync(path.join(pkg, "src", "pass.test.ts"), `${imports}test("a", () => {});\n`);
  writeFileSync(path.join(pkg, "src", "broken.test.js"), `${imports}// BROKEN\n`);
  writeFileSync(path.join(pkg, "src", "plain.test.js"), 'import { test } from "node:test";\n');
  writeFileSync(path.join(staged.workspace, "tests", "orphan.test.ts"), imports);
  writeFileSync(path.join(staged.dir, "outside.test.ts"), imports);
  return pkg;
}

test("run-test-file runs a vitest file with its package's vitest from the package directory", () => {
  const staged = withLaneTools();
  assert.equal(staged.status, 0);
  const pkg = withVitestPackage(staged);
  const pass = staged.run("run-test-file", ["plugin/src/pass.test.ts"]);
  assert.equal(pass.status, 0, pass.stderr);
  assert.equal(pass.stdout, `vitest cwd=${pkg} args=run ${path.join(pkg, "src", "pass.test.ts")}\n`);
  assert.match(pass.stderr, /exit status: 0\n$/);
  const broken = staged.run("run-test-file", ["plugin/src/broken.test.js"]);
  assert.equal(broken.status, 1);
  assert.match(broken.stderr, /exit status: 1\n$/);
});

// A lane checkout has no node_modules in a plugin package, so run-test-file
// installs the package's lockfile (npm ci --ignore-scripts) once, first. The
// stand-in vitest is a local file: dependency, so the install needs no network.
test("run-test-file installs a package's locked dependencies once when node_modules is missing", () => {
  const staged = withLaneTools();
  assert.equal(staged.status, 0);
  withVitestPackage(staged);
  const pkg = path.join(staged.workspace, "fresh");
  mkdirSync(path.join(pkg, "src"), { recursive: true });
  writeFileSync(path.join(pkg, "package.json"), JSON.stringify({ name: "fresh", devDependencies: { vitest: "file:../plugin/node_modules/vitest" } }));
  const lock = spawnSync("npm", ["install", "--package-lock-only", "--ignore-scripts", "--no-audit", "--no-fund"], { cwd: pkg, encoding: "utf8" });
  assert.equal(lock.status, 0, lock.stderr);
  assert.throws(() => statSync(path.join(pkg, "node_modules")), "the fixture starts with no node_modules");
  writeFileSync(path.join(pkg, "src", "pass.test.ts"), 'import { test } from "vitest";\ntest("a", () => {});\n');
  const first = staged.run("run-test-file", ["fresh/src/pass.test.ts"]);
  assert.equal(first.status, 0, first.stderr);
  assert.equal(first.stdout, `vitest cwd=${pkg} args=run ${path.join(pkg, "src", "pass.test.ts")}\n`);
  const installed = statSync(path.join(pkg, "node_modules", ".package-lock.json")).mtimeMs;
  const second = staged.run("run-test-file", ["fresh/src/pass.test.ts"]);
  assert.equal(second.status, 0, second.stderr);
  assert.equal(statSync(path.join(pkg, "node_modules", ".package-lock.json")).mtimeMs, installed, "a present node_modules is not reinstalled");
});

test("run-test-file refuses a vitest file outside the checkout, one without a package and one that does not import vitest", () => {
  const staged = withLaneTools();
  assert.equal(staged.status, 0);
  withVitestPackage(staged);
  for (const file of [path.join(staged.dir, "outside.test.ts"), "../outside.test.ts", "tests/orphan.test.ts", "plugin/src/plain.test.js"]) {
    const result = staged.run("run-test-file", [file]);
    assert.equal(result.status, 2, file);
    assert.equal(result.stdout, "", `${file} ran`);
    assert.match(result.stderr, /refused/, file);
  }
});

test("a script the list does not name gets no rule, even beside a listed one", () => {
  const { status, allowed } = withVerify([VERIFY]);
  assert.equal(status, 0);
  assert.ok(!allowed.some((rule) => rule.includes("unlisted.sh")), allowed.join(" | "));
});

test("without verify-scripts no copy or rule is made", () => {
  const { status, allowed, verifyDir } = withVerify(undefined);
  assert.equal(status, 0);
  assert.ok(wrapperRules(allowed).length === 0, allowed.join(" | "));
  assert.throws(() => statSync(verifyDir));
});

for (const bad of [
  "plugins/vtest/skills/audit/scripts/*.sh",
  "plugins/vtest/skills/audit/scripts/scan.sh --check",
  "plugins/vtest/skills/audit/scripts/scan.sh *",
  "plugins/vtest/../vtest/skills/audit/scripts/scan.sh",
  "/plugins/vtest/scripts/lib.sh",
  "plugins/vtest/lib.sh",
  'plugins/vtest/scripts/x".sh',
]) {
  test(`a verify-script outside the allowed shape fails red: ${bad}`, () => {
    const { status, stdout, args } = withVerify([bad]);
    assert.notEqual(status, 0);
    assert.match(stdout, /::error::a verify-script must be the exact path of a scripts\/ script/);
    assert.equal(args, "");
  });
}

test("a verify-script missing from the base fails red", () => {
  const { status, stdout, args } = withVerify(["plugins/vtest/scripts/missing.sh"]);
  assert.notEqual(status, 0);
  assert.match(stdout, /::error::a verify-script is not in the base/);
  assert.equal(args, "");
});

test("a verify-script whose plugin holds a symbolic link fails red", () => {
  const scripts = path.join(base, "plugins", "vlink", "scripts");
  mkdirSync(scripts, { recursive: true });
  writeFileSync(path.join(scripts, "s.sh"), "echo s\n");
  spawnSync("ln", ["-sfn", root, path.join(scripts, "out")]);
  const { status, stdout, args } = withVerify(["plugins/vlink/scripts/s.sh"]);
  assert.notEqual(status, 0);
  assert.match(stdout, /::error::a verify-script's directory holds a symbolic link/);
  assert.equal(args, "");
});

test("a verify-scripts copy path a rule cannot carry fails red", () => {
  const { status, args } = withVerify([VERIFY], { VERIFY_DIR: path.join(root, "has space") });
  assert.notEqual(status, 0);
  assert.equal(args, "");
});

test("a read skill gets no verify-script rule", () => {
  const { status, allowed } = withVerify([VERIFY], { EFFECT: "read" });
  assert.equal(status, 0);
  assert.ok(!allowed.some((rule) => rule.startsWith("Bash")), allowed.join(" | "));
});

test("a read skill gets no check wrapper", () => {
  const { status, allowed } = withChecks(["scripts/check-x.sh --check"], { EFFECT: "read" });
  assert.equal(status, 0);
  assert.ok(!allowed.some((rule) => rule.startsWith("Bash")), allowed.join(" | "));
});

// pr-run-activity.md, "prepare: review-threads": the skill runs on the read
// runner's launcher; on claude-code-action, in the write runner, it fails red.
test("prepare: review-threads on claude-code-action fails red before any output", () => {
  const feedbackDir = mkdtempSync(path.join(root, "threads-"));
  writeFileSync(path.join(feedbackDir, "threads.json"), "{}");
  writeFileSync(path.join(feedbackDir, "run.json"), "{}");
  const { status, stdout, args } = stage({ PREPARE: "review-threads", FEEDBACK_DIR: feedbackDir });
  assert.notEqual(status, 0);
  assert.match(stdout, /::error::review-threads: the skill runs on run-claude-cli, in the read runner/);
  assert.equal(args, "");
});

// prepare: dependency-review runs only on run-claude-cli, in the read runner
// (the launcher tests below); the claude-code-action path fails red.
test("prepare: dependency-review on claude-code-action, or as a gate, fails red before any output", () => {
  for (const [overrides, message] of [
    [{ PREPARE: "dependency-review" }, /::error::dependency-review: the skill runs on run-claude-cli, in the read runner/],
    [{ PREPARE: "dependency-review", LAUNCHER: "run-claude-cli", GATING: "gate" }, /::error::dependency-review: the activity must be advisory/],
  ]) {
    const { status, stdout, args } = stage(overrides);
    assert.notEqual(status, 0, JSON.stringify(overrides));
    assert.match(stdout, message);
    assert.equal(args, "");
  }
});

// pr-run-activity.md, "prepare: ci-context": a read skill that holds no write
// token gets Bash, Edit and Write to rerun and fix the failing checks, reads
// the runner's read-only context file, and gets no commit tool.
function withCiContext({ file = true, effect = "read" } = {}) {
  const dir = mkdtempSync(path.join(root, "ci-"));
  const ciDir = path.join(dir, "lane-ci");
  mkdirSync(ciDir, { recursive: true });
  if (file) writeFileSync(path.join(ciDir, "context.json"), "{}");
  return { ciDir, ...stage({ PREPARE: "ci-context", CI_DIR: ciDir, EFFECT: effect, CAN_COMMIT: "false", SKILL: "source-control:pull-request" }) };
}

test("prepare: ci-context gives a read skill Bash, Edit and Write and the read-only context file", () => {
  const { status, args, allowed, denied, ciDir } = withCiContext();
  assert.equal(status, 0);
  for (const tool of ["Bash", "Edit", "Write", `Read(/${ciDir}/**)`]) {
    assert.ok(allowed.includes(tool), `${tool} in ${allowed.join(" | ")}`);
  }
  assert.ok(!allowed.includes(COMMIT_TOOL), allowed.join(" | "));
  assert.ok(denied.includes(`Edit(/${ciDir}/**)`) && denied.includes(`Write(/${ciDir}/**)`), denied.join(" | "));
  assert.ok(denied.includes("WebFetch") && denied.includes("WebSearch"), denied.join(" | "));
  assert.ok(args.includes(`${ciDir}/context.json`), "the system prompt names the context file");
  const write = spawnSync("bash", ["-c", 'echo x >>"$1"', "_", path.join(ciDir, "context.json")]);
  assert.notEqual(write.status, 0, "the context file is read-only");
});

test("a read skill without ci-context gets no Bash, Edit or Write", () => {
  const { status, allowed } = stage({ EFFECT: "read", CAN_COMMIT: "false" });
  assert.equal(status, 0);
  assert.ok(!allowed.some((rule) => /^(Bash|Edit|Write)/.test(rule)), allowed.join(" | "));
});

test("prepare: ci-context with no context file, or on a write effect, fails red before any output", () => {
  const missing = withCiContext({ file: false });
  assert.notEqual(missing.status, 0);
  assert.match(missing.stdout, /::error::ci-context: the runner wrote no context file/);
  assert.equal(missing.args, "");
  const write = withCiContext({ effect: "mutate-branch" });
  assert.notEqual(write.status, 0);
  assert.match(write.stdout, /::error::ci-context: the activity's effect must be read/);
});

test("an unknown prepare mode fails red before any output", () => {
  const { status, stdout, args } = stage({ PREPARE: "rebase" });
  assert.notEqual(status, 0);
  assert.match(stdout, /::error::the activity's prepare mode is not a known mode/);
  assert.equal(args, "");
});

// pr-run-activity.md, "Skill activities": a write skill gets no web tools
// unless its activity sets web-access. Rule forms from
// code.claude.com/docs/en/permissions#webfetch: `WebFetch(domain:*)` matches
// every domain and also opens the sandbox to it; `domain:<host>` one host.
function withWebAccess(webAccess, overrides = {}) {
  const dir = mkdtempSync(path.join(root, "web-"));
  const file = path.join(dir, "resolved.json");
  writeFileSync(file, JSON.stringify({ selected: { args: "--ci", "web-access": webAccess } }));
  return stage({ SKILL: "work-items:work", RESOLVED: file, ...overrides });
}

const RESEARCH_SKILLS = [
  "Skill(discovery:research)",
  "Skill(discovery:read-docs)",
  "Skill(knowledge:docpage-digest)",
  "Skill(knowledge:map-corpus)",
];

test("a write skill without web-access has no web tools and only its own plugin", () => {
  const { status, allowed, denied, plugins, env } = stage({ SKILL: "work-items:work" });
  assert.equal(status, 0);
  assert.deepEqual(ownDenied(denied, env), ["WebFetch", "WebSearch"]);
  assert.ok(!allowed.some((rule) => rule.startsWith("Web")), allowed.join(" | "));
  assert.deepEqual(plugins, ["work-items@melodic-software"]);
});

test("web-access disabled grants nothing", () => {
  const { status, allowed, denied, env } = withWebAccess({ enabled: false, domains: "any" });
  assert.equal(status, 0);
  assert.deepEqual(ownDenied(denied, env), ["WebFetch", "WebSearch"]);
  assert.ok(!allowed.some((rule) => rule.startsWith("Web") || RESEARCH_SKILLS.includes(rule)), allowed.join(" | "));
});

test("web-access with any domain allows every fetch, search and the research skills", () => {
  const { status, allowed, denied, plugins, args } = withWebAccess({ enabled: true, domains: "any" });
  assert.equal(status, 0);
  assert.ok(!denied.some((rule) => rule.startsWith("Web")), denied.join(" | "));
  for (const rule of ["WebFetch(domain:*)", "WebSearch", ...RESEARCH_SKILLS]) {
    assert.ok(allowed.includes(rule), `${rule} in ${allowed.join(" | ")}`);
  }
  assert.deepEqual(plugins, ["work-items@melodic-software", "discovery@melodic-software", "knowledge@melodic-software"]);
  assert.match(args, /\/discovery:research/);
});

// pr-run-activity.md, "Skill activities": for `any` only, the two docs
// scripts from a read-only copy, with their cache and page files in the
// scratch directory.
function readDocsRules(env) {
  return ["fetch-docs.sh", "docs-cache.sh"].flatMap((script) => [
    `Bash(bash ${env.DOCS_DIR}/${script} *)`,
    `Bash(bash "${env.DOCS_DIR}/${script}" *)`,
  ]);
}

test("web-access with any domain allows the read-docs scripts and points their files at the scratch directory", () => {
  const { status, allowed, denied, args, jobEnv, env } = withWebAccess({ enabled: true, domains: "any" });
  assert.equal(status, 0);
  // Both the bare and the double-quoted path, since a rule matches the path as written.
  assert.deepEqual(wrapperRules(allowed), readDocsRules(env));
  // The skill's bare Edit and Write must not reach the scripts its rules run.
  assert.deepEqual(ownDenied(denied, env), [`Edit(/${env.DOCS_DIR}/**)`, `Write(/${env.DOCS_DIR}/**)`]);
  for (const name of ["fetch-docs.sh", "docs-cache.sh", "html2md.py"]) {
    assert.equal(statSync(path.join(env.DOCS_DIR, name)).mode & 0o222, 0, name);
  }
  // The cache directory travels in the prompt, never through $GITHUB_ENV.
  assert.equal(jobEnv, "");
  const cache = `--cache-dir ${env.SCRATCH}/docs-cache`;
  assert.ok(args.includes(`bash ${env.DOCS_DIR}/fetch-docs.sh --cache ${cache} --out ${env.SCRATCH}/docs-`), args);
  assert.ok(args.includes(`bash ${env.DOCS_DIR}/docs-cache.sh ${cache} `), args);
});

for (const [name, webAccess, overrides] of [
  ["without web-access", undefined, {}],
  ["with web-access disabled", { enabled: false, domains: "any" }, {}],
  ["with a domain list", { enabled: true, domains: ["code.claude.com"] }, {}],
  ["for a read skill", { enabled: true, domains: "any" }, { EFFECT: "read" }],
]) {
  test(`no read-docs script grant ${name}`, () => {
    const { status, allowed, jobEnv } = webAccess
      ? withWebAccess(webAccess, overrides)
      : stage({ SKILL: "work-items:work" });
    assert.equal(status, 0);
    assert.ok(wrapperRules(allowed).length === 0, allowed.join(" | "));
    assert.equal(jobEnv, "");
  });
}

test("a docs script copy path a rule cannot carry fails the stage", () => {
  const { status, allowed } = withWebAccess({ enabled: true, domains: "any" }, { DOCS_DIR: path.join(root, "has space") });
  assert.notEqual(status, 0);
  assert.ok(wrapperRules(allowed).length === 0, allowed.join(" | "));
});

// With a domain list the docs scripts stay denied, so the prompt names
// WebFetch on the listed hosts as the way to read a page, not read-docs.
test("web-access with a domain list tells the run to read the listed hosts with WebFetch", () => {
  const { status, args } = withWebAccess({ enabled: true, domains: ["code.claude.com", "docs.github.com"] });
  assert.equal(status, 0);
  assert.ok(args.includes("read pages only on these hosts: code.claude.com docs.github.com."), args);
  assert.ok(args.includes("read a page on one of those hosts with WebFetch"), args);
  assert.ok(!args.includes("read each external source through /discovery:read-docs"), args);
});

test("web-access with any domain points the run at the research skills", () => {
  const { status, args } = withWebAccess({ enabled: true, domains: "any" });
  assert.equal(status, 0);
  assert.ok(args.includes("read each external source through /discovery:read-docs"), args);
  assert.ok(!args.includes("read pages only on these hosts"), args);
});

test("web-access with a domain list allows a fetch to those domains only", () => {
  const { status, allowed, denied, env } = withWebAccess({ enabled: true, domains: ["code.claude.com", "*.github.com"] });
  assert.equal(status, 0);
  assert.deepEqual(ownDenied(denied, env), []);
  const web = allowed.filter((rule) => rule.startsWith("WebFetch"));
  assert.deepEqual(web, ["WebFetch(domain:code.claude.com)", "WebFetch(domain:*.github.com)"]);
  assert.ok(allowed.includes("WebSearch"), allowed.join(" | "));
});

for (const domains of [["code.claude.com,WebFetch"], ["evil.com)"], ["*"], ["any"], ["=any"], [""], ["a b.com"], [], "all"]) {
  test(`web-access with malformed domains fails red: ${JSON.stringify(domains)}`, () => {
    const { status, stdout, args } = withWebAccess({ enabled: true, domains });
    assert.notEqual(status, 0);
    assert.match(stdout, /::error::web-access/);
    assert.equal(args, "");
  });
}

test("a read skill gets no web tools even with web-access", () => {
  const { status, allowed, plugins } = withWebAccess({ enabled: true, domains: "any" }, { EFFECT: "read" });
  assert.equal(status, 0);
  assert.ok(!allowed.some((rule) => rule.startsWith("Web")), allowed.join(" | "));
  assert.deepEqual(plugins, ["work-items@melodic-software"]);
});

// A read skill whose applied-by sets patch hands its change on as a patch
// (pr-run-activity.md, Skill activities): the write tool set, no commit tool,
// and the instruction to leave the change uncommitted.
const UNCOMMITTED_SENTENCE = "Leave every change uncommitted in the working tree";

function withAppliedBy(appliedBy, overrides = {}) {
  const dir = mkdtempSync(path.join(root, "applied-by-"));
  const file = path.join(dir, "resolved.json");
  writeFileSync(file, JSON.stringify({ selected: { args: "--ci", "applied-by": appliedBy } }));
  return stage({ EFFECT: "read", CAN_COMMIT: "false", RESOLVED: file, ...overrides });
}

test("a read skill that hands on a patch gets Edit, Write and Agent, no commit tool, and is told to leave its change uncommitted", () => {
  const { status, args, allowed } = withAppliedBy({ patch: "apply-patch" });
  assert.equal(status, 0);
  for (const tool of ["Edit", "Write", "Agent"]) {
    assert.ok(allowed.includes(tool), `${tool} in ${allowed.join(" | ")}`);
  }
  assert.ok(!allowed.some((rule) => rule.startsWith("mcp__github_file_ops__")), allowed.join(" | "));
  assert.ok(!allowed.includes(CHMOD_RULE), allowed.join(" | "));
  assert.ok(args.includes(UNCOMMITTED_SENTENCE), args);
  assert.ok(!args.includes(COMMIT_SENTENCE), args);
});

test("a read skill whose applied-by names no patch keeps the read tool set", () => {
  const { status, args, allowed } = withAppliedBy({ "feedback-replies": "publish-feedback" });
  assert.equal(status, 0);
  assert.ok(!allowed.some((rule) => /^(Bash|Edit|Write)/.test(rule)), allowed.join(" | "));
  assert.ok(!args.includes(UNCOMMITTED_SENTENCE), args);
});

test("a read skill that hands on a patch gets its checks' wrappers and the web tools its web-access sets", () => {
  const { status, allowed } = withChecks(
    ["scripts/check-x.sh"],
    { EFFECT: "read", CAN_COMMIT: "false" },
    { "applied-by": { patch: "apply-patch" }, "web-access": { enabled: true, domains: ["code.claude.com"] } },
  );
  assert.equal(status, 0);
  assert.equal(wrapperRules(allowed).length, 1, allowed.join(" | "));
  assert.ok(allowed.includes("WebFetch(domain:code.claude.com)"), allowed.join(" | "));
});

test("prepare: ci-context with applied-by.patch keeps the ci-context tool set", () => {
  const ciDir = mkdtempSync(path.join(root, "ci-ab-"));
  writeFileSync(path.join(ciDir, "context.json"), "{}");
  const { status, args, allowed } = withAppliedBy({ patch: "apply-patch" }, { PREPARE: "ci-context", CI_DIR: ciDir });
  assert.equal(status, 0);
  assert.ok(allowed.includes("Bash"), allowed.join(" | "));
  assert.ok(args.includes(`${ciDir}/context.json`), args);
  assert.ok(!args.includes(UNCOMMITTED_SENTENCE), args);
});

// Every write lane, in every mode the runner builds, carries the whole shell
// deny set and the plugin copy's Edit deny: a mode that resets or rebuilds the
// deny list must not drop them.
for (const [name, run] of [
  ["mutate-branch", () => stage({})],
  ["mutate-tracker", () => stage({ EFFECT: "mutate-tracker" })],
  ["publish-artifact", () => stage({ EFFECT: "publish-artifact" })],
  ["merge", () => stage({ EFFECT: "merge" })],
  ["a lane that cannot commit", () => stage({ CAN_COMMIT: "false" })],
  ["verify-scripts", () => withVerify([VERIFY])],
  ["checks", () => withChecks(["scripts/check-x.sh --check"])],
  ["web-access any", () => withWebAccess({ enabled: true, domains: "any" })],
  ["web-access with a domain list", () => withWebAccess({ enabled: true, domains: ["code.claude.com"] })],
  ["a read skill that hands on a patch", () => withAppliedBy({ patch: "apply-patch" })],
]) {
  test(`a write lane denies every shell read command and Read of /proc and .git: ${name}`, () => {
    const { status, denied, workspace = WORKSPACE } = run();
    assert.equal(status, 0);
    for (const rule of SHELL_DENIED) {
      const expected = rule.replace(WORKSPACE, workspace);
      assert.ok(denied.includes(expected), `${expected} in ${denied.join(" | ")}`);
    }
  });
  test(`a write lane denies all of git: ${name}`, () => {
    const { status, denied } = run();
    assert.equal(status, 0);
    for (const rule of WRITE_GIT_DENIED) {
      assert.ok(denied.includes(rule), `${rule} in ${denied.join(" | ")}`);
    }
  });
  test(`a write lane denies Edit of the plugin copy: ${name}`, () => {
    const { status, denied, env } = run();
    assert.equal(status, 0);
    assert.ok(denied.includes(marketplaceDenied(env)), `${marketplaceDenied(env)} in ${denied.join(" | ")}`);
  });
}

// The plugin loads in place from the marketplace copy, so the copy is
// read-only to every process the skill starts, whatever the activity's effect.
for (const effect of ["read", "mutate-branch"]) {
  test(`the marketplace copy is read-only for a ${effect} skill`, () => {
    const { status, env } = stage({ EFFECT: effect, CAN_COMMIT: "false" });
    assert.equal(status, 0);
    const manifest = path.join(env.MARKETPLACE, ".claude-plugin", "marketplace.json");
    assert.equal(JSON.parse(readFileSync(manifest, "utf8")).name, "melodic-software");
    const write = spawnSync("bash", ["-c", 'echo x >>"$1"', "_", manifest]);
    assert.notEqual(write.status, 0, "the manifest is read-only");
    const create = spawnSync("bash", ["-c", ': >"$1"', "_", path.join(env.MARKETPLACE, "plugins", "source-control", "new")]);
    assert.notEqual(create.status, 0, "no file can be added to a plugin");
  });
}

// --- launcher: run-claude-cli, which reads only inside the checkout ---

const outputOf = (text, name) => (new RegExp(`^${name}<<(\\S+)\\n([\\s\\S]*?)\\n\\1$`, "m").exec(text)?.[2] ?? "").split("\n").filter(Boolean);

// Runs the skill step for run-claude-cli and reads its launcher outputs and
// the stage it left.
function launch(overrides = {}) {
  const stageDir = path.join(mkdtempSync(path.join(root, "stage-")), "lane-stage");
  const run = stage({ LAUNCHER: "run-claude-cli", STAGE: stageDir, WORKSPACE, EFFECT: "read", CAN_COMMIT: "false", ...overrides });
  const text = readFileSync(run.env.GITHUB_OUTPUT, "utf8");
  return {
    ...run,
    stageDir,
    tools: outputOf(text, "tools"),
    allowedTools: outputOf(text, "allowed-tools"),
    deniedTools: outputOf(text, "disallowed-tools"),
    pluginDirs: outputOf(text, "plugin-dirs").join("\n"),
    preamble: /^preamble=(.*)$/m.exec(text)?.[1] ?? "",
    promptFile: (() => {
      try {
        return readFileSync(path.join(stageDir, "prompt.md"), "utf8");
      } catch {
        return "";
      }
    })(),
  };
}

// The file tools never reach the checkout's .git, on every launcher arm.
const GIT_DENIED = ["Read(./.git/**)", "Edit(./.git/**)", "Write(./.git/**)"];

test("run-claude-cli: a ci-context skill gets Bash, Edit and Write, the staged context and plugin under .lane/, and no claude_args", () => {
  const ciDir = mkdtempSync(path.join(root, "ci-launch-"));
  writeFileSync(path.join(ciDir, "context.json"), '{"head_sha":"x"}');
  const run = launch({ PREPARE: "ci-context", CI_DIR: ciDir, SKILL: "source-control:pull-request" });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.tools.toSorted(), ["Agent", "Bash", "Edit", "Glob", "Grep", "Read", "Skill", "Write"]);
  for (const rule of ["Skill(source-control:pull-request)", "Bash", "Edit", "Write", "Agent", "Grep", "Glob"]) {
    assert.ok(run.allowedTools.includes(rule), `${rule} in ${run.allowedTools.join(" | ")}`);
  }
  for (const rule of ["WebFetch", "WebSearch", "Edit(./.lane/ci/**)", "Write(./.lane/ci/**)", "Edit(./.lane/plugins/**)", "Write(./.lane/plugins/**)", "Edit(./.lane/trusted-context.json)", "Write(./.lane/trusted-context.json)", "Read(//proc/**)", ...GIT_DENIED]) {
    assert.ok(run.deniedTools.includes(rule), `${rule} in ${run.deniedTools.join(" | ")}`);
  }
  assert.equal(run.pluginDirs, ".lane/plugins/source-control");
  assert.equal(readFileSync(path.join(run.stageDir, "ci", "context.json"), "utf8"), '{"head_sha":"x"}');
  assert.ok(statSync(path.join(run.stageDir, "plugins", "source-control")).isDirectory());
  assert.ok(statSync(path.join(run.stageDir, "scratch")).isDirectory());
  assert.equal(run.promptFile, "Call the Skill tool with skill source-control:pull-request and args ci, then follow the skill instructions to the end.\n");
  assert.ok(run.preamble.includes(`The context file is ${WORKSPACE}/.lane/ci/context.json.`), run.preamble);
  assert.ok(run.preamble.includes(`Your scratchpad directory is ${WORKSPACE}/.lane/scratch:`), run.preamble);
  assert.match(run.preamble, /Leave every fix uncommitted in the working tree/);
  assert.equal(run.args, "", "no claude_args for the launcher");
  assert.deepEqual(run.plugins, []);
});

test("run-claude-cli: a read skill without ci-context gets no Bash, Edit or Write", () => {
  const run = launch({ SKILL: "source-control:pull-request" });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.tools.toSorted(), ["Glob", "Grep", "Read", "Skill"]);
  assert.ok(!run.allowedTools.some((rule) => /^(Bash|Edit|Write)/.test(rule)), run.allowedTools.join(" | "));
  for (const rule of ["Read(//proc/**)", ...GIT_DENIED]) assert.ok(run.deniedTools.includes(rule), `${rule} in ${run.deniedTools.join(" | ")}`);
  assert.doesNotMatch(run.preamble, /context file/);
});

// A resolved file for the launcher tests: the activity's args plus `extra`.
function launchResolved(extra) {
  const file = path.join(mkdtempSync(path.join(root, "launch-ab-")), "resolved.json");
  writeFileSync(file, JSON.stringify({ selected: { args: "fix", ...extra } }));
  return file;
}
const PATCH = { "applied-by": { patch: "apply-patch" } };

test("run-claude-cli refuses a writing skill, a patch-producing skill with a prepare mode, a gate and a check outside a no-prepare patch skill before any output", () => {
  const onlyPatch = /checks, self-checks and verify-scripts run only in a skill that hands on a patch with no prepare mode/;
  for (const [overrides, message] of [
    [{ EFFECT: "mutate-branch", CAN_COMMIT: "true" }, /only a read skill/],
    [{ PREPARE: "review-threads" }, /only a read skill/],
    [{ PREPARE: "merge-base" }, /only a read skill/],
    [{ PREPARE: "dependency-review" }, /only a read skill/],
    [{ GATING: "gate" }, /a gate skill's verdict is not read from the launcher/],
    [{ RESOLVED: launchResolved({ checks: ["scripts/check-x.sh --check"] }) }, onlyPatch],
    [{ RESOLVED: launchResolved({ "self-checks": ["scripts/check-x.sh"] }) }, onlyPatch],
    [{ RESOLVED: launchResolved({ "verify-scripts": [VERIFY] }) }, onlyPatch],
    [{ RESOLVED: launchResolved({ ...PATCH, checks: ["scripts/check-x.sh --check"] }), PREPARE: "merge-base" }, onlyPatch],
  ]) {
    const run = launch(overrides);
    assert.notEqual(run.status, 0, JSON.stringify(overrides));
    assert.match(run.stdout, message);
    assert.deepEqual(run.tools, []);
    assert.equal(run.promptFile, "");
  }
});

// pr-run-activity.md, "Issue mode": the issue lane runs on the launcher, so its
// check and verify-script wrappers are staged for .lane/checks and
// .lane/verify (--restricted reads nothing outside the checkout), named there
// in the rules and the preamble, and denied to the file tools; the prompt
// passes the issue before the activity's args.
test("run-claude-cli: an issue lane's patch skill stages its check and verify-script wrappers for .lane/, denied to the file tools", () => {
  mkdirSync(path.join(base, "scripts"), { recursive: true });
  writeFileSync(path.join(base, "scripts", "check-x.sh"), "#!/usr/bin/env bash\necho check\n", { mode: 0o755 });
  mkdirSync(path.join(base, "plugins", "vtest", "skills", "audit", "scripts"), { recursive: true });
  writeFileSync(path.join(base, VERIFY), "echo scan\n");
  const run = launch({
    ISSUE_NUMBER: "7",
    SKILL: "source-control:pull-request",
    RESOLVED: launchResolved({ ...PATCH, checks: ["scripts/check-x.sh --check"], "verify-scripts": [VERIFY] }),
  });
  assert.equal(run.status, 0, run.stdout);
  const lane = `${WORKSPACE}/.lane`;
  for (const rule of [`Bash(${lane}/checks/bin/check-x)`, `Bash(${lane}/verify/bin/scan *)`]) {
    assert.ok(run.allowedTools.includes(rule), `${rule} in ${run.allowedTools.join(" | ")}`);
  }
  for (const dir of ["checks", "verify"]) {
    for (const tool of ["Edit", "Write", "NotebookEdit"]) {
      const rule = `${tool}(./.lane/${dir}/**)`;
      assert.ok(run.deniedTools.includes(rule), `${rule} in ${run.deniedTools.join(" | ")}`);
    }
  }
  const check = readFileSync(path.join(run.stageDir, "checks", "bin", "check-x"), "utf8");
  assert.ok(check.endsWith(`CHECK_DATA_ROOT=${WORKSPACE} exec ${lane}/checks/scripts/check-x.sh --check\n`), check);
  assert.ok(check.includes("export CHECK_AFFECTED_SCRIPT_EXEC_BIT=1\n"), check);
  assert.equal(readFileSync(path.join(run.stageDir, "checks", "scripts", "check-x.sh"), "utf8"), "#!/usr/bin/env bash\necho check\n");
  assert.ok(readFileSync(path.join(run.stageDir, "verify", "bin", "scan"), "utf8").includes(`copy=${lane}/verify/${VERIFY}\n`));
  assert.equal(readFileSync(path.join(run.stageDir, "verify", VERIFY), "utf8"), "echo scan\n");
  assert.ok(run.preamble.includes(`run each of these repository checks as written, with no arguments: ${lane}/checks/bin/check-x.`), run.preamble);
  assert.ok(run.preamble.includes(`with the script's own arguments and paths inside the checkout: ${lane}/verify/bin/scan <arguments>.`), run.preamble);
  assert.ok(run.preamble.startsWith("You run unattended as a CI lane activity on an issue,"), run.preamble);
  assert.equal(run.promptFile, "Call the Skill tool with skill source-control:pull-request and args --issue 7 fix, then follow the skill instructions to the end.\n");
  // The skill's Bash: the check, verify-script and git-read wrappers,
  // nothing else; every other command matches no allow rule under dontAsk,
  // and all of git stays denied, so git runs only through git-read.
  assert.deepEqual(run.allowedTools.filter((rule) => rule.startsWith("Bash")).toSorted(), [
    `Bash(${lane}/checks/bin/check-x)`,
    `Bash(${lane}/git/git-read *)`,
    `Bash(${lane}/verify/bin/scan *)`,
  ]);
  assert.ok(run.deniedTools.includes("Bash(git *)"));
  for (const tool of ["Edit", "Write", "NotebookEdit"]) assert.ok(run.deniedTools.includes(`${tool}(./.lane/git/**)`), tool);
  assert.ok(run.preamble.includes(`only with ${lane}/git/git-read status, diff, log or show`), run.preamble);
  // A PR lane's patch skill keeps all of git denied.
  const pr = launch({ SKILL: "source-control:pull-request", RESOLVED: launchResolved(PATCH) });
  assert.ok(pr.deniedTools.includes("Bash(git *)") && !pr.allowedTools.some((rule) => rule.includes("git")));
});

// git-read, run against a real checkout: the four read commands run with
// fsmonitor, hooks and external diff programs off, and every option that
// writes a file or reads one outside the checkout is refused before git runs.
test("run-claude-cli: an issue lane's git-read runs only git's read commands, and refuses --output, --no-index and outside paths", () => {
  const dir = mkdtempSync(path.join(root, "git-read-"));
  const workspace = path.join(dir, "workspace");
  mkdirSync(workspace);
  const git = (...args) => spawnSync("git", ["-C", workspace, ...args], { encoding: "utf8" });
  git("init", "-q");
  writeFileSync(path.join(workspace, "a.txt"), "one\n");
  git("add", "a.txt");
  git("-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", "commit", "-qm", "c");
  writeFileSync(path.join(workspace, "a.txt"), "two\n");
  // A planted fsmonitor and external diff in the checkout's own config.
  const marker = path.join(dir, "ran");
  git("config", "core.fsmonitor", `touch ${marker}; false`);
  git("config", "diff.external", `touch ${marker}`);
  git("config", "diff.planted.textconv", `touch ${marker}; cat`);
  writeFileSync(path.join(workspace, ".gitattributes"), "a.txt diff=planted\n");
  writeFileSync(path.join(dir, "outside.txt"), "secret\n");
  const run = launch({ ISSUE_NUMBER: "7", SKILL: "source-control:pull-request", RESOLVED: launchResolved(PATCH), WORKSPACE: workspace });
  assert.equal(run.status, 0, run.stdout);
  const wrapper = path.join(run.stageDir, "git", "git-read");
  const read = (...args) => spawnSync(wrapper, args, { cwd: dir, encoding: "utf8", env: { PATH: process.env.PATH } });
  for (const args of [["status", "--short"], ["diff"], ["log", "--oneline", "-1"], ["show", "--stat", "HEAD"], ["show", "HEAD:a.txt"]]) {
    const result = read(...args);
    assert.equal(result.status, 0, `${args.join(" ")}: ${result.stderr}`);
  }
  assert.match(read("diff").stdout, /-one\n\+two/);
  assert.equal(existsSync(marker), false, "no planted fsmonitor, external diff or textconv ran");
  for (const args of [
    ["log", "--output=x"],
    ["log", "--outp=x"],
    ["show", "--output", "x"],
    ["diff", "--no-index", "a.txt", path.join(dir, "outside.txt")],
    ["diff", path.join(dir, "outside.txt"), "a.txt"],
    ["diff", "-Ofile"],
    ["diff", `-RO${path.join(dir, "outside.txt")}`],
    ["diff", "-pO/nonexistent"],
    ["diff", "--orderf=a.txt"],
    ["status", "-v"],
    ["status", "-sv"],
    ["status", "--verbose"],
    ["status", "--verb"],
    ["diff", "--ext-diff"],
    ["log", "--textconv"],
    ["commit", "-m", "x"],
    ["push"],
    ["-c", "core.pager=sh", "log"],
    [],
  ]) {
    const result = read(...args);
    assert.equal(result.status, 2, `${JSON.stringify(args)} is refused`);
    assert.match(result.stderr, /^refused: /, JSON.stringify(args));
  }
  assert.equal(existsSync(path.join(workspace, "x")), false, "nothing was written");
  assert.equal(existsSync(marker), false, "no refused call ran a planted program");
});

test("run-claude-cli: a staged plugin with no .mcp.json gets an empty server list, and one that ships its own keeps it", () => {
  const run = launch({ SKILL: "source-control:pull-request" });
  assert.equal(run.status, 0, run.stdout);
  assert.equal(readFileSync(path.join(run.stageDir, "plugins", "source-control", ".mcp.json"), "utf8"), '{"mcpServers":{}}\n');
  const own = mkdtempSync(path.join(root, "base-mcp-"));
  mkdirSync(path.join(own, "plugins", "source-control"), { recursive: true });
  mkdirSync(path.join(own, ".claude-plugin"));
  writeFileSync(path.join(own, ".claude-plugin", "marketplace.json"), JSON.stringify({ name: "melodic-software" }));
  const shipped = Buffer.from('{ "mcpServers": { "x": { "command": "y" } } }\r\nÿ');
  writeFileSync(path.join(own, "plugins", "source-control", ".mcp.json"), shipped);
  const kept = launch({ BASE_PATH: own, SKILL: "source-control:pull-request" });
  assert.equal(kept.status, 0, kept.stdout);
  assert.deepEqual(readFileSync(path.join(kept.stageDir, "plugins", "source-control", ".mcp.json")), shipped);
});

test("run-claude-cli: a skill plugin holding a symbolic link fails red", () => {
  const linked = mkdtempSync(path.join(root, "base-link-"));
  mkdirSync(path.join(linked, "plugins", "source-control"), { recursive: true });
  mkdirSync(path.join(linked, ".claude-plugin"));
  writeFileSync(path.join(linked, ".claude-plugin", "marketplace.json"), JSON.stringify({ name: "melodic-software" }));
  spawnSync("ln", ["-s", "/etc/passwd", path.join(linked, "plugins", "source-control", "link")]);
  const run = launch({ BASE_PATH: linked, SKILL: "source-control:pull-request" });
  assert.notEqual(run.status, 0);
  assert.match(run.stdout, /the skill's plugin holds a symbolic link/);
  assert.deepEqual(run.tools, []);
});

// A read skill with no prepare mode that hands on a patch gets Bash with no
// script rule unless its skill has one, Edit, Write and Agent, the git
// directory denied, and the instruction to leave its change uncommitted.
test("run-claude-cli: a patch-producing skill with no prepare mode gets Bash, Edit, Write and Agent, no Bash rule, and .git denied", () => {
  const run = launch({ RESOLVED: launchResolved(PATCH), SKILL: "source-control:pull-request" });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.tools.toSorted(), ["Agent", "Bash", "Edit", "Glob", "Grep", "Read", "Skill", "Write"]);
  assert.deepEqual(run.allowedTools.toSorted(), ["Agent", "Edit", "Edit(./.lane/scratch/**)", "Glob", "Grep", "Skill(source-control:pull-request)", "Write"]);
  for (const rule of ["WebFetch", "WebSearch", "Read(./.git/**)", "Read(//proc/**)", "Edit(./.lane/plugins/**)", "Write(./.lane/plugins/**)", "NotebookEdit(./.lane/plugins/**)", "Edit(./.lane/trusted-context.json)", "Write(./.lane/trusted-context.json)", "Bash(git *)"]) {
    assert.ok(run.deniedTools.includes(rule), `${rule} in ${run.deniedTools.join(" | ")}`);
  }
  assert.equal(run.pluginDirs, ".lane/plugins/source-control");
  assert.ok(statSync(path.join(run.stageDir, "plugins", "source-control")).isDirectory());
  assert.ok(statSync(path.join(run.stageDir, "scratch")).isDirectory());
  assert.ok(run.preamble.includes(`Your scratchpad directory is ${WORKSPACE}/.lane/scratch:`), run.preamble);
  assert.ok(run.preamble.includes(UNCOMMITTED_SENTENCE), run.preamble);
  assert.doesNotMatch(run.preamble, /context file/);
  assert.equal(run.promptFile, "Call the Skill tool with skill source-control:pull-request and args fix, then follow the skill instructions to the end.\n");
  assert.equal(run.args, "", "no claude_args for the launcher");
  assert.deepEqual(run.plugins, []);
});

// address-feedback on the launcher: the patch tool set, the review-thread
// tool's wrapper as its one Bash rule (bare and quoted), the thread files
// staged read-only and denied to the file tools, and state/ left writable for
// the replies file. pr-run-activity.md, "prepare: review-threads".
function launchThreads({ runFile = true } = {}) {
  const feedbackDir = mkdtempSync(path.join(root, "launch-feedback-"));
  writeFileSync(path.join(feedbackDir, "threads.json"), '{"threads":[]}\n');
  if (runFile) writeFileSync(path.join(feedbackDir, "run.json"), '{"version":1}\n');
  const scripts = path.join(base, "plugins", "source-control", "skills", "pull-request", "scripts");
  mkdirSync(scripts, { recursive: true });
  writeFileSync(path.join(scripts, "feedback-thread.sh"), "#!/usr/bin/env bash\n");
  return launch({ RESOLVED: launchResolved({ "applied-by": { patch: "apply-feedback-patch", "feedback-replies": "publish-feedback" } }), PREPARE: "review-threads", FEEDBACK_DIR: feedbackDir, SKILL: "source-control:pull-request" });
}

const FEEDBACK_TOOL = `${WORKSPACE}/.lane/feedback/bin/feedback-thread`;
const FEEDBACK_FILE_DENIED = ["threads.json", "run.json", "feedback-thread.sh", "bin/**", "state/**"].flatMap((file) =>
  ["Edit", "Write", "NotebookEdit"].map((tool) => `${tool}(./.lane/feedback/${file})`),
);

test("run-claude-cli: review-threads gets the patch tool set and the review-thread wrapper as its one Bash rule", () => {
  const run = launchThreads();
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.tools.toSorted(), ["Agent", "Bash", "Edit", "Glob", "Grep", "Read", "Skill", "Write"]);
  assert.deepEqual(run.allowedTools.toSorted(), [
    "Agent",
    `Bash("${FEEDBACK_TOOL}" *)`,
    `Bash(${FEEDBACK_TOOL} *)`,
    "Edit",
    "Edit(./.lane/scratch/**)",
    "Glob",
    "Grep",
    "Skill(source-control:pull-request)",
    "Write",
  ]);
  for (const rule of [...FEEDBACK_FILE_DENIED, "Bash(git *)", "Bash(wc *)", "Bash(cat *)", "Read(./.git/**)", "Read(//proc/**)", "NotebookEdit(./.lane/plugins/**)", "WebFetch", "WebSearch"]) {
    assert.ok(run.deniedTools.includes(rule), `${rule} in ${run.deniedTools.join(" | ")}`);
  }
  // A deny rule beats an allow rule: none names the wrapper. state/ is the
  // wrapper's to write, through Bash; the file tools are denied it, exactly.
  assert.ok(!run.deniedTools.some((rule) => rule.includes("feedback-thread *") || rule.includes("bin/feedback-thread")), run.deniedTools.join(" | "));
  assert.deepEqual(
    run.deniedTools.filter((rule) => rule.includes("feedback/state")),
    ["Edit(./.lane/feedback/state/**)", "Write(./.lane/feedback/state/**)", "NotebookEdit(./.lane/feedback/state/**)"],
  );
  assert.equal(run.args, "", "no claude_args for the launcher");
});

test("run-claude-cli: the preamble names the review-thread tool's path and subcommands, byte for byte the allow rule's path", () => {
  const run = launchThreads();
  assert.equal(run.status, 0, run.stdout);
  const sentence =
    `The review-thread tool is ${FEEDBACK_TOOL}: run it by exactly this path as ${FEEDBACK_TOOL} list, ` +
    `${FEEDBACK_TOOL} check-paths <path>... and ${FEEDBACK_TOOL} record <thread-id> <file>, with each disposition file in ${WORKSPACE}/.lane/scratch. ` +
    "The tool posts and commits nothing: a later job pushes your uncommitted fix and posts what you record.";
  assert.ok(run.preamble.endsWith(sentence), run.preamble);
  assert.ok(run.preamble.includes(UNCOMMITTED_SENTENCE), run.preamble);
  const named = /The review-thread tool is (\S+):/.exec(run.preamble)[1];
  assert.ok(run.allowedTools.includes(`Bash(${named} *)`), `the allow rule names ${named}`);
});

test("run-claude-cli: review-threads stages the thread file, run.json, the tool copy, its wrapper and an empty state/ for .lane/", () => {
  const run = launchThreads();
  assert.equal(run.status, 0, run.stdout);
  const feedback = path.join(run.stageDir, "feedback");
  assert.deepEqual(readdirSync(feedback).toSorted(), ["bin", "feedback-thread.sh", "run.json", "state", "threads.json"]);
  assert.equal(readFileSync(path.join(feedback, "threads.json"), "utf8"), '{"threads":[]}\n');
  assert.equal(readFileSync(path.join(feedback, "run.json"), "utf8"), '{"version":1}\n');
  assert.deepEqual(readdirSync(path.join(feedback, "state")), []);
  const lane = `${WORKSPACE}/.lane`;
  assert.equal(
    readFileSync(path.join(feedback, "bin", "feedback-thread"), "utf8"),
    "#!/usr/bin/env bash\n" +
      `export FEEDBACK_THREADS=${lane}/feedback/threads.json FEEDBACK_LOG=${lane}/feedback/state/replies.jsonl FEEDBACK_SCRATCH=${lane}/scratch FEEDBACK_WORKSPACE=${WORKSPACE}\n` +
      `exec bash ${lane}/feedback/feedback-thread.sh "$@"\n`,
  );
});

test("run-claude-cli: review-threads without the thread file or run.json fails red before any output", () => {
  const run = launchThreads({ runFile: false });
  assert.notEqual(run.status, 0);
  assert.match(run.stdout, /::error::review-threads: the runner wrote no thread file/);
  assert.deepEqual(run.tools, []);
  assert.equal(run.promptFile, "");
});

test("run-claude-cli: fix-ci and fix-docs get no review-thread wrapper and stage no feedback directory", () => {
  const ciDir = mkdtempSync(path.join(root, "ci-no-feedback-"));
  writeFileSync(path.join(ciDir, "context.json"), "{}");
  for (const run of [
    launch({ RESOLVED: launchResolved(PATCH), PREPARE: "ci-context", CI_DIR: ciDir, SKILL: "source-control:pull-request" }),
    launch({ RESOLVED: launchResolved(PATCH), SKILL: "source-control:pull-request" }),
  ]) {
    assert.equal(run.status, 0, run.stdout);
    assert.ok(!run.allowedTools.some((rule) => rule.includes("feedback-thread")), run.allowedTools.join(" | "));
    assert.doesNotMatch(run.preamble, /review-thread tool/);
    assert.ok(!readdirSync(run.stageDir).includes("feedback"));
  }
});

// fix-docs runs ai-slop:audit under dontAsk: Bash runs exactly the skill's
// own scripts by absolute path, bare and quoted (its `!` line runs
// "<dir>/detect.sh" --show-config), and the fix flow's digest commands,
// with git, the user-scope script and the read-only print commands denied.
const SLOP = `${WORKSPACE}/.lane/plugins/ai-slop/skills/audit/scripts`;
test("run-claude-cli: fix-docs gets exactly the ai-slop scripts' rules and the shell deny set", () => {
  const slopBase = mkdtempSync(path.join(root, "base-slop-"));
  mkdirSync(path.join(slopBase, "plugins", "ai-slop", "skills", "audit", "scripts"), { recursive: true });
  mkdirSync(path.join(slopBase, ".claude-plugin"));
  writeFileSync(path.join(slopBase, ".claude-plugin", "marketplace.json"), JSON.stringify({ name: "melodic-software" }));
  const run = launch({ BASE_PATH: slopBase, RESOLVED: launchResolved(PATCH), SKILL: "ai-slop:audit" });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(
    run.allowedTools.filter((rule) => rule.startsWith("Bash")).toSorted(),
    [
      `Bash("${SLOP}/cross-check.sh" *)`,
      `Bash("${SLOP}/detect.sh" *)`,
      `Bash("${SLOP}/emit-findings.sh" *)`,
      `Bash("${SLOP}/emit-fix-record.sh" *)`,
      `Bash("${SLOP}/rubric-fanout.sh" *)`,
      `Bash(${SLOP}/cross-check.sh *)`,
      `Bash(${SLOP}/detect.sh *)`,
      `Bash(${SLOP}/emit-findings.sh *)`,
      `Bash(${SLOP}/emit-fix-record.sh *)`,
      `Bash(${SLOP}/rubric-fanout.sh *)`,
      `Bash(mkdir -p ${WORKSPACE}/.lane/scratch/*)`,
      "Bash(sha256sum *)",
    ].toSorted(),
  );
  for (const rule of [
    ...SHELL_DENIED.filter((rule) => rule.startsWith("Bash")),
    "Read(//proc/**)",
    "Bash(git *)",
    `Bash(${SLOP}/user-scope.sh *)`,
    `Bash("${SLOP}/user-scope.sh" *)`,
    "NotebookEdit(./.lane/plugins/**)",
    "Edit(./.lane/plugins/**)",
    "Write(./.lane/plugins/**)",
  ]) {
    assert.ok(run.deniedTools.includes(rule), `${rule} in ${run.deniedTools.join(" | ")}`);
  }
  assert.match(run.preamble, /one plain command per call/);
  assert.ok(run.preamble.includes(`redirect output only into ${WORKSPACE}/.lane/scratch.`), run.preamble);
});

test("run-claude-cli: a ci-context skill that hands on a patch keeps the ci-context tool set and preamble", () => {
  const ciDir = mkdtempSync(path.join(root, "ci-launch-ab-"));
  writeFileSync(path.join(ciDir, "context.json"), "{}");
  const run = launch({ RESOLVED: launchResolved(PATCH), PREPARE: "ci-context", CI_DIR: ciDir, SKILL: "source-control:pull-request" });
  assert.equal(run.status, 0, run.stdout);
  assert.ok(run.allowedTools.includes("Bash"), "ci-context keeps its own tool set");
  assert.ok(!run.preamble.includes(UNCOMMITTED_SENTENCE), run.preamble);
});

// web-access on the launcher: `any` only, with the research plugins staged
// under .lane/ beside the skill's own and the web tools neither stripped by
// --restricted nor denied.
function webBase() {
  const dir = mkdtempSync(path.join(root, "base-web-"));
  for (const plugin of ["source-control", "discovery", "knowledge"]) mkdirSync(path.join(dir, "plugins", plugin), { recursive: true });
  mkdirSync(path.join(dir, ".claude-plugin"));
  writeFileSync(path.join(dir, ".claude-plugin", "marketplace.json"), JSON.stringify({ name: "melodic-software" }));
  return dir;
}
const RESEARCH = ["Skill(discovery:read-docs)", "Skill(discovery:research)", "Skill(knowledge:docpage-digest)", "Skill(knowledge:map-corpus)"];

test("run-claude-cli: web-access any gives a patch skill WebFetch and WebSearch, the research skills and their plugins under .lane/", () => {
  const run = launch({
    BASE_PATH: webBase(),
    RESOLVED: launchResolved({ ...PATCH, "web-access": { enabled: true, domains: "any" } }),
    SKILL: "source-control:pull-request",
  });
  assert.equal(run.status, 0, run.stdout);
  assert.ok(run.tools.includes("WebFetch") && run.tools.includes("WebSearch"), run.tools.join(" | "));
  for (const rule of ["WebFetch(domain:*)", "WebSearch", ...RESEARCH]) {
    assert.ok(run.allowedTools.includes(rule), `${rule} in ${run.allowedTools.join(" | ")}`);
  }
  assert.ok(!run.deniedTools.includes("WebFetch") && !run.deniedTools.includes("WebSearch"), run.deniedTools.join(" | "));
  for (const rule of ["Read(./.git/**)", "Read(//proc/**)", "Edit(./.lane/plugins/**)", "Write(./.lane/plugins/**)"]) {
    assert.ok(run.deniedTools.includes(rule), `${rule} in ${run.deniedTools.join(" | ")}`);
  }
  assert.equal(run.pluginDirs, ".lane/plugins/source-control\n.lane/plugins/discovery\n.lane/plugins/knowledge");
  for (const plugin of ["discovery", "knowledge"]) {
    assert.ok(statSync(path.join(run.stageDir, "plugins", plugin)).isDirectory(), plugin);
    assert.equal(readFileSync(path.join(run.stageDir, "plugins", plugin, ".mcp.json"), "utf8"), '{"mcpServers":{}}\n', plugin);
  }
  assert.match(run.preamble, /cite each page you read/);
  assert.ok(!run.allowedTools.some((rule) => rule.startsWith("Bash")), "no docs-script rule");
});

test("run-claude-cli: a patch skill without web-access gets no web tools and only its own plugin", () => {
  const run = launch({ BASE_PATH: webBase(), RESOLVED: launchResolved(PATCH), SKILL: "source-control:pull-request" });
  assert.equal(run.status, 0, run.stdout);
  assert.ok(!run.tools.includes("WebFetch") && !run.tools.includes("WebSearch"), run.tools.join(" | "));
  assert.ok(run.deniedTools.includes("WebFetch") && run.deniedTools.includes("WebSearch"), run.deniedTools.join(" | "));
  assert.equal(run.pluginDirs, ".lane/plugins/source-control");
  assert.doesNotMatch(run.preamble, /WebFetch/);
});

test("run-claude-cli: web-access with a host list gives one WebFetch rule per host and WebSearch, and stages no research plugin", () => {
  const run = launch({
    BASE_PATH: webBase(),
    RESOLVED: launchResolved({ ...PATCH, "web-access": { enabled: true, domains: ["github.com", "pypi.org"] } }),
    SKILL: "source-control:pull-request",
  });
  assert.equal(run.status, 0, run.stdout);
  assert.ok(run.tools.includes("WebFetch") && run.tools.includes("WebSearch"), run.tools.join(" | "));
  assert.deepEqual(
    run.allowedTools.filter((rule) => rule.startsWith("Web") || rule.startsWith("Skill(")),
    ["Skill(source-control:pull-request)", "WebFetch(domain:github.com)", "WebFetch(domain:pypi.org)", "WebSearch"],
  );
  assert.ok(!run.allowedTools.includes("WebFetch(domain:*)"), run.allowedTools.join(" | "));
  assert.ok(!run.deniedTools.includes("WebFetch") && !run.deniedTools.includes("WebSearch"), run.deniedTools.join(" | "));
  assert.equal(run.pluginDirs, ".lane/plugins/source-control");
  assert.match(run.preamble, /read pages only on these hosts: github\.com pypi\.org\. Read each page with WebFetch/);
});

test("run-claude-cli: web-access with a malformed host, or a research plugin missing from the base, fails red before any output", () => {
  const noKnowledge = webBase();
  rmSync(path.join(noKnowledge, "plugins", "knowledge"), { recursive: true });
  for (const [overrides, message] of [
    [{ BASE_PATH: webBase(), RESOLVED: launchResolved({ ...PATCH, "web-access": { enabled: true, domains: ["code.claude.com/x"] } }) }, /web-access: a domain is not a host name/],
    [{ BASE_PATH: webBase(), RESOLVED: launchResolved({ ...PATCH, "web-access": { enabled: true, domains: [] } }) }, /web-access: domains must be any or a list of host names/],
    [{ BASE_PATH: noKnowledge, RESOLVED: launchResolved({ ...PATCH, "web-access": { enabled: true, domains: "any" } }) }, /the knowledge plugin is not in the base/],
  ]) {
    const run = launch({ SKILL: "source-control:pull-request", ...overrides });
    assert.notEqual(run.status, 0, JSON.stringify(overrides));
    assert.match(run.stdout, message);
    assert.deepEqual(run.tools, []);
  }
});

// review-dependency on the launcher: Edit, Write and Agent with no Bash, the
// context file staged read-only under .lane/dependency/ and denied to the file
// tools, git and the shell read commands denied though no Bash is granted,
// one WebFetch rule per configured host, and the verdict schema written for
// the launcher's json-schema-file.
const DEPENDENCY_APPLIED_BY = { "applied-by": { patch: "apply-dependency-patch", "dependency-verdict": "apply-dependency-verdict" } };
const DEPENDENCY_HOSTS = ["github.com", "raw.githubusercontent.com", "www.npmjs.com", "registry.npmjs.org", "pypi.org"];
function launchDependency({ file = true, web = true } = {}) {
  const dir = mkdtempSync(path.join(root, "dependency-launch-"));
  const dependencyDir = path.join(dir, "lane-dependency");
  const schemaDir = path.join(dir, "lane-dependency-schema");
  mkdirSync(dependencyDir, { recursive: true });
  if (file) writeFileSync(path.join(dependencyDir, "dependency.json"), '{"pr":7}');
  const extra = web ? { "web-access": { enabled: true, domains: DEPENDENCY_HOSTS } } : {};
  return {
    schemaDir,
    ...launch({
      BASE_PATH: webBase(),
      RESOLVED: launchResolved({ ...DEPENDENCY_APPLIED_BY, ...extra }),
      PREPARE: "dependency-review",
      DEPENDENCY_DIR: dependencyDir,
      SCHEMA_DIR: schemaDir,
      SKILL: "source-control:pull-request",
    }),
  };
}
const DEPENDENCY_FILE_DENIED = ["Edit(./.lane/dependency/**)", "Write(./.lane/dependency/**)", "NotebookEdit(./.lane/dependency/**)"];

test("run-claude-cli: a dependency-review skill gets Edit, Write and Agent with no Bash, the staged context, and per-host web rules", () => {
  const run = launchDependency();
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.tools.toSorted(), ["Agent", "Edit", "Glob", "Grep", "Read", "Skill", "WebFetch", "WebSearch", "Write"]);
  assert.deepEqual(
    run.allowedTools.toSorted(),
    ["Agent", "Edit", "Edit(./.lane/scratch/**)", "Glob", "Grep", "Skill(source-control:pull-request)", ...DEPENDENCY_HOSTS.map((host) => `WebFetch(domain:${host})`), "WebSearch", "Write"].toSorted(),
  );
  for (const rule of [
    "Bash(git *)",
    ...SHELL_DENIED.filter((rule) => rule.startsWith("Bash(") || rule === "Read(//proc/**)"),
    "NotebookEdit(./.lane/plugins/**)",
    "Edit(./.lane/plugins/**)",
    "Write(./.lane/plugins/**)",
    ...DEPENDENCY_FILE_DENIED,
    ...GIT_DENIED,
  ]) {
    assert.ok(run.deniedTools.includes(rule), `${rule} in ${run.deniedTools.join(" | ")}`);
  }
  // A deny rule beats an allow rule: nothing the skill may write reaches the context copy.
  assert.ok(!run.deniedTools.includes("WebFetch") && !run.deniedTools.includes("WebSearch"), run.deniedTools.join(" | "));
  assert.equal(readFileSync(path.join(run.stageDir, "dependency", "dependency.json"), "utf8"), '{"pr":7}');
  assert.equal(run.pluginDirs, ".lane/plugins/source-control", "no research plugin under a host list");
  assert.ok(run.preamble.includes(`The dependency context file is ${WORKSPACE}/.lane/dependency/dependency.json.`), run.preamble);
  assert.match(run.preamble, /Your verdict is your structured output; a later job acts on it, and you post nothing\./);
  assert.match(run.preamble, /pushes only on a fix verdict/);
  assert.doesNotMatch(run.preamble, /shell command/, "no Bash, so no shell instruction");
  assert.equal(run.promptFile, "Call the Skill tool with skill source-control:pull-request and args fix, then follow the skill instructions to the end.\n");
  assert.equal(run.args, "", "no claude_args for the launcher");
});

// The schema the launcher holds the verdict to is the shape the verdict job
// validates: the verdicts review-dependency.mjs names and the limits
// apply-dependency-verdict.mjs enforces.
test("run-claude-cli: the dependency verdict schema matches the verdict job's verdicts and limits", () => {
  const run = launchDependency({ web: false });
  assert.equal(run.status, 0, run.stdout);
  const schema = JSON.parse(readFileSync(path.join(run.schemaDir, "verdict.schema.json"), "utf8"));
  assert.deepEqual(schema.properties.verdict.enum, [...VERDICTS]);
  assert.deepEqual(schema.required, ["verdict", "reasons", "evidence"]);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(
    [schema.properties.reasons.minItems, schema.properties.reasons.maxItems, schema.properties.reasons.items.maxLength],
    [1, LIMITS.reasons, LIMITS.reason],
  );
  assert.deepEqual([schema.properties.evidence.maxItems, schema.properties.evidence.items.maxLength], [LIMITS.evidence, LIMITS.evidenceItem]);
  // With no web access the web tools stay denied.
  assert.ok(run.deniedTools.includes("WebFetch") && run.deniedTools.includes("WebSearch"), run.deniedTools.join(" | "));
});

test("run-claude-cli: a dependency-review skill with no context file fails red before any output", () => {
  const run = launchDependency({ file: false });
  assert.notEqual(run.status, 0);
  assert.match(run.stdout, /::error::dependency-review: the runner wrote no context file/);
  assert.deepEqual(run.tools, []);
  assert.equal(run.promptFile, "");
});

// resolve-conflicts on the launcher: Edit, Write and Agent with no Bash, git
// and the shell read commands denied though no Bash is granted, and the merge
// context the runner writes after the stage under .lane/merge/ denied to the
// file tools.
const MERGE_FILE_DENIED = ["Edit(./.lane/merge/**)", "Write(./.lane/merge/**)", "NotebookEdit(./.lane/merge/**)"];

test("run-claude-cli: a merge-base skill gets Edit, Write and Agent with no Bash, and the merge context denied to the file tools", () => {
  const run = launch({ RESOLVED: launchResolved({ "applied-by": { patch: "apply-conflict-patch" }, args: "ci" }), PREPARE: "merge-base", SKILL: "source-control:resolve-conflicts" });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.tools.toSorted(), ["Agent", "Edit", "Glob", "Grep", "Read", "Skill", "Write"]);
  assert.deepEqual(run.allowedTools.toSorted(), ["Agent", "Edit", "Edit(./.lane/scratch/**)", "Glob", "Grep", "Skill(source-control:resolve-conflicts)", "Write"].toSorted());
  for (const rule of [
    "Bash(git *)",
    ...SHELL_DENIED.filter((rule) => rule.startsWith("Bash(") || rule === "Read(//proc/**)"),
    "NotebookEdit(./.lane/plugins/**)",
    "Edit(./.lane/plugins/**)",
    "Write(./.lane/plugins/**)",
    "WebFetch",
    "WebSearch",
    ...MERGE_FILE_DENIED,
    ...GIT_DENIED,
  ]) {
    assert.ok(run.deniedTools.includes(rule), `${rule} in ${run.deniedTools.join(" | ")}`);
  }
  // A deny rule beats an allow rule: no allowed tool reaches the merge context or .git.
  assert.ok(!run.allowedTools.some((rule) => rule.startsWith("Bash")), run.allowedTools.join(" | "));
  assert.ok(run.preamble.includes(`the merge context is ${WORKSPACE}/.lane/merge/conflicts.json`), run.preamble);
  assert.match(run.preamble, /leave a path you cannot resolve with its conflict markers, and edit no other file/);
  assert.match(run.preamble, /You run no command and post nothing\./);
  assert.doesNotMatch(run.preamble, /shell command|commit tool|commit your/i, "no Bash and no commit tool, so no such instruction");
  assert.equal(run.promptFile, "Call the Skill tool with skill source-control:resolve-conflicts and args ci, then follow the skill instructions to the end.\n");
  assert.equal(run.args, "", "no claude_args for the launcher");
});

test("run-claude-cli: a merge-base skill that hands on no patch fails red before any output", () => {
  const run = launch({ PREPARE: "merge-base", SKILL: "source-control:resolve-conflicts" });
  assert.notEqual(run.status, 0);
  assert.match(run.stdout, /only a read skill/);
  assert.deepEqual(run.tools, []);
});
