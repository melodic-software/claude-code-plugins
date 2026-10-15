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
    MODEL: "",
    MAX_TURNS: "75",
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

test("a read skill gets no check wrapper", () => {
  const { status, allowed } = withChecks(["scripts/check-x.sh --check"], { EFFECT: "read" });
  assert.equal(status, 0);
  assert.ok(!allowed.some((rule) => rule.startsWith("Bash")), allowed.join(" | "));
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
