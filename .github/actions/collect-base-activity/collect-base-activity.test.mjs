// Runs the action's skill-staging `run:` script against a throwaway base
// checkout and reads the outputs it appends to GITHUB_OUTPUT. Expected values
// come from the contract (pr-run-activity.md, "Skill activities" and
// "prepare: merge-base"): a writing skill gets the signed-commit tool and the
// instruction to commit, except in merge-base mode, where the runner commits.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";

const ACTION = new URL("./action.yml", import.meta.url);
const COMMIT_TOOL = "mcp__github_file_ops__commit_files";
const COMMIT_SENTENCE = "commit every repository file you changed";

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
  const denied = (/--disallowedTools "([^"]*)"/.exec(args)?.[1] ?? "").split(",").filter(Boolean);
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
});

test("prepare: merge-base leaves out the commit tool and the instruction to commit", () => {
  const { status, args, allowed } = stage({ PREPARE: "merge-base" });
  assert.equal(status, 0);
  assert.ok(!allowed.includes(COMMIT_TOOL), allowed.join(" | "));
  assert.ok(!args.includes(COMMIT_TOOL), args);
  assert.ok(!args.includes(COMMIT_SENTENCE), args);
  // Still a writing skill: it edits and stages its resolution.
  assert.match(args, /--allowedTools "Skill\(source-control:resolve-conflicts\),Read\([^)]*\),Edit,Write,Agent,Edit\(/);
  assert.ok(args.includes("--disallowedTools \"WebFetch,WebSearch\""), args);
});

// pr-run-activity.md, "Skill activities": each listed check runs from the base
// copy against the checkout, through a wrapper that takes no arguments, and
// that wrapper is the only Bash the runner grants.
function withChecks(checks, overrides = {}) {
  const dir = mkdtempSync(path.join(root, "checks-"));
  const workspace = path.join(dir, "workspace");
  mkdirSync(path.join(workspace, "scripts"), { recursive: true });
  mkdirSync(path.join(base, "scripts"), { recursive: true });
  const script = '#!/usr/bin/env bash\necho "from=$0 data=$CHECK_DATA_ROOT pwd=$PWD args=$*"\n';
  writeFileSync(path.join(base, "scripts", "check-x.sh"), script, { mode: 0o755 });
  writeFileSync(path.join(workspace, "scripts", "check-x.sh"), "#!/usr/bin/env bash\necho head code\n", { mode: 0o755 });
  const file = path.join(dir, "resolved.json");
  writeFileSync(file, JSON.stringify({ selected: { args: "ci", checks } }));
  const checksDir = path.join(dir, "lane-checks");
  return { workspace, checksDir, ...stage({ RESOLVED: file, CHECKS_DIR: checksDir, WORKSPACE: workspace, ...overrides }) };
}

test("a listed check gets a no-argument wrapper that runs the base copy against the checkout", () => {
  const { status, allowed, args, workspace, checksDir } = withChecks(["scripts/check-x.sh --check"]);
  assert.equal(status, 0);
  const wrapper = path.join(checksDir, "bin", "check-x");
  assert.deepEqual(
    allowed.filter((rule) => rule.startsWith("Bash")),
    [`Bash(${wrapper})`],
  );
  assert.ok(args.includes(wrapper), "the system prompt names the check");
  const denied = (/--disallowedTools "([^"]*)"/.exec(args)?.[1] ?? "").split(",");
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
    allowed.filter((rule) => rule.startsWith("Bash")),
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
// wrapper reports the script's exit status itself and the prompt says so.
const RUN_ALONE = "Run each verification wrapper as its own command, not chained to another; it prints the script's exit status.";
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

// A listed script may run checkout code (check-skill.sh runs each skill's
// test scripts), so the wrapper runs every script without the GitHub token.
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
    allowed.filter((rule) => rule.startsWith("Bash")),
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
    allowed.filter((rule) => rule.startsWith("Bash")),
    [`Bash(${bin("check-skill")} *)`, `Bash(${bin("check-evals-quality")} *)`],
  );
  const skill = path.join(workspace, "skills", "demo");
  mkdirSync(path.join(skill, "scripts"), { recursive: true });
  writeFileSync(path.join(skill, "SKILL.md"), "---\ndescription: Demo skill. Use when 'demo'.\n---\n\n# Demo\n");
  writeFileSync(path.join(skill, "scripts", "token.test.sh"), 'echo "seen=${GH_TOKEN-unset},${GITHUB_TOKEN-unset}"\nexit 1\n');
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
  assert.ok(!allowed.some((rule) => rule.startsWith("Bash")), allowed.join(" | "));
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

// pr-run-activity.md, "prepare: review-threads": the skill keeps the commit
// tool and gets one more Bash rule, the review-thread wrapper, which runs a
// read-only base copy with the thread file, log, scratch and checkout fixed.
function withThreads(threads = true) {
  const dir = mkdtempSync(path.join(root, "threads-"));
  const workspace = path.join(dir, "workspace");
  const feedbackDir = path.join(dir, "lane-feedback");
  const feedbackState = path.join(dir, "lane-feedback-state");
  mkdirSync(workspace, { recursive: true });
  mkdirSync(feedbackDir, { recursive: true });
  if (threads) writeFileSync(path.join(feedbackDir, "threads.json"), "{}");
  const scripts = path.join(base, "plugins", "source-control", "skills", "pull-request", "scripts");
  mkdirSync(scripts, { recursive: true });
  writeFileSync(
    path.join(scripts, "feedback-thread.sh"),
    'echo "threads=$FEEDBACK_THREADS log=$FEEDBACK_LOG scratch=$FEEDBACK_SCRATCH ws=$FEEDBACK_WORKSPACE args=$*"\n',
  );
  const staged = stage({ PREPARE: "review-threads", FEEDBACK_DIR: feedbackDir, FEEDBACK_STATE: feedbackState, WORKSPACE: workspace });
  return { workspace, feedbackDir, feedbackState, ...staged };
}

test("prepare: review-threads keeps the commit tool and adds only the review-thread wrapper", () => {
  const { status, args, allowed, denied, workspace, feedbackDir, feedbackState, env } = withThreads();
  assert.equal(status, 0);
  assert.ok(allowed.includes(COMMIT_TOOL), allowed.join(" | "));
  assert.ok(args.includes(COMMIT_SENTENCE), args);
  const tool = path.join(feedbackDir, "bin", "feedback-thread");
  assert.deepEqual(
    allowed.filter((rule) => rule.startsWith("Bash")),
    [`Bash(${tool} *)`],
  );
  for (const dir of [feedbackDir, feedbackState]) {
    assert.ok(denied.includes(`Edit(/${dir}/**)`) && denied.includes(`Write(/${dir}/**)`), denied.join(" | "));
  }
  assert.ok(args.includes(`${tool} record <thread-id> <file>`), "the system prompt names the tool");
  const write = spawnSync("bash", ["-c", 'echo x >>"$1"', "_", path.join(feedbackDir, "feedback-thread.sh")]);
  assert.notEqual(write.status, 0, "the tool's copy is read-only");
  const run = spawnSync(tool, ["list", "x y"], { cwd: root, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(
    run.stdout.trim(),
    `threads=${path.join(feedbackDir, "threads.json")} log=${path.join(feedbackState, "replies.jsonl")} scratch=${env.SCRATCH} ws=${workspace} args=list x y`,
  );
});

test("prepare: review-threads with no thread file fails red before any output", () => {
  const { status, stdout, args } = withThreads(false);
  assert.notEqual(status, 0);
  assert.match(stdout, /::error::review-threads: the runner wrote no thread file/);
  assert.equal(args, "");
});

// pr-run-activity.md, "prepare: dependency-review": the skill keeps the commit
// tool, reads the runner's read-only context file, gets no Bash rule, and
// must return the verdict schema's structured output.
function withDependency({ file = true, gating = "advisory" } = {}) {
  const dir = mkdtempSync(path.join(root, "dependency-"));
  const dependencyDir = path.join(dir, "lane-dependency");
  mkdirSync(dependencyDir, { recursive: true });
  if (file) writeFileSync(path.join(dependencyDir, "dependency.json"), "{}");
  return { dependencyDir, ...stage({ PREPARE: "dependency-review", DEPENDENCY_DIR: dependencyDir, GATING: gating }) };
}

test("prepare: dependency-review reads the context file and returns the verdict schema", () => {
  const { status, args, allowed, denied, dependencyDir } = withDependency();
  assert.equal(status, 0);
  assert.ok(allowed.includes(COMMIT_TOOL), allowed.join(" | "));
  assert.ok(allowed.includes(`Read(/${dependencyDir}/**)`), allowed.join(" | "));
  assert.ok(!allowed.some((rule) => rule.startsWith("Bash")), allowed.join(" | "));
  assert.ok(denied.includes(`Edit(/${dependencyDir}/**)`) && denied.includes(`Write(/${dependencyDir}/**)`), denied.join(" | "));
  const schema = JSON.parse(/--json-schema '([^']+)'/.exec(args)[1]);
  assert.deepEqual(schema.properties.verdict.enum, ["merge", "fix", "close", "escalate"]);
  assert.deepEqual(schema.required, ["verdict", "reasons", "evidence"]);
  const write = spawnSync("bash", ["-c", 'echo x >>"$1"', "_", path.join(dependencyDir, "dependency.json")]);
  assert.notEqual(write.status, 0, "the context file is read-only");
});

test("prepare: dependency-review with no context file, or as a gate, fails red before any output", () => {
  const missing = withDependency({ file: false });
  assert.notEqual(missing.status, 0);
  assert.match(missing.stdout, /::error::dependency-review: the runner wrote no context file/);
  assert.equal(missing.args, "");
  const gate = withDependency({ gating: "gate" });
  assert.notEqual(gate.status, 0);
  assert.match(gate.stdout, /::error::dependency-review: the activity must be advisory/);
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
  const { status, allowed, denied, plugins } = stage({ SKILL: "work-items:work" });
  assert.equal(status, 0);
  assert.deepEqual(denied, ["WebFetch", "WebSearch"]);
  assert.ok(!allowed.some((rule) => rule.startsWith("Web")), allowed.join(" | "));
  assert.deepEqual(plugins, ["work-items@melodic-software"]);
});

test("web-access disabled grants nothing", () => {
  const { status, allowed, denied } = withWebAccess({ enabled: false, domains: "any" });
  assert.equal(status, 0);
  assert.deepEqual(denied, ["WebFetch", "WebSearch"]);
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
  assert.deepEqual(allowed.filter((rule) => rule.startsWith("Bash(")), readDocsRules(env));
  // The skill's bare Edit and Write must not reach the scripts its rules run.
  assert.deepEqual(denied, [`Edit(/${env.DOCS_DIR}/**)`, `Write(/${env.DOCS_DIR}/**)`]);
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
    assert.ok(!allowed.some((rule) => rule.startsWith("Bash(")), allowed.join(" | "));
    assert.equal(jobEnv, "");
  });
}

test("a docs script copy path a rule cannot carry fails the stage", () => {
  const { status, allowed } = withWebAccess({ enabled: true, domains: "any" }, { DOCS_DIR: path.join(root, "has space") });
  assert.notEqual(status, 0);
  assert.ok(!allowed.some((rule) => rule.startsWith("Bash(")), allowed.join(" | "));
});

test("web-access with a domain list allows a fetch to those domains only", () => {
  const { status, allowed, denied } = withWebAccess({ enabled: true, domains: ["code.claude.com", "*.github.com"] });
  assert.equal(status, 0);
  assert.deepEqual(denied, []);
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
