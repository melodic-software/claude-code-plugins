// /review:explain-change: the digest policy (each trigger, each policy, the
// cascade layers), the builder (template plus escaped JSON, never markup from
// data), and the read-only boundary (no post, no check status).
import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const SKILL = join(PLUGIN, "skills/explain-change");
const POLICY = join(SKILL, "scripts/digest-policy.mjs");
const BUILDER = join(SKILL, "scripts/build-digest.mjs");
const REPO = join(PLUGIN, "../..");

const { DEFAULTS, configBlock, decide, globRegExp } = await import(POLICY);
const { buildDigest, shapeDigest } = await import(BUILDER);
const { validateView } = await import(join(PLUGIN, "lib/view-builder.mjs"));

const scratch = mkdtempSync(join(tmpdir(), "explain-change-test-"));
after(() => rmSync(scratch, { recursive: true, force: true }));

const config = (over = {}) =>
  Object.fromEntries(Object.entries({ ...DEFAULTS, ...over }).map(([k, value]) => [k, { value }]));
const opts = (over = {}) => ({ policy: "offer", event: "review", blastRadius: "", requested: false, ...over });
const files = (n, dir = "src") => Array.from({ length: n }, (_, i) => ({ path: `${dir}/f${i}.js` }));
const quiet = { files: files(1), additions: 1, deletions: 1, labels: [] };

function gitRepo(repo) {
  const git = (...args) => execFileSync("git", ["-C", repo, ...args], { stdio: "ignore" });
  git("init", "-q", "-b", "main");
  const commit = () =>
    git("-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "x");
  return { git, commit };
}

const runPolicy = (home, repo) => (facts, args = []) => {
  const out = spawnSync(process.execPath, [POLICY, ...args], {
    input: JSON.stringify(facts),
    encoding: "utf8",
    env: { ...process.env, HOME: home, USERPROFILE: home, CLAUDE_PROJECT_DIR: repo },
  });
  assert.equal(out.status, 0, out.stderr);
  return JSON.parse(out.stdout);
};

describe("offer fires on each trigger", () => {
  const cases = [
    ["files", { ...quiet, files: files(6) }, {}],
    ["changed-lines", { ...quiet, additions: 150, deletions: 51 }, {}],
    ["blast-radius", quiet, { blastRadius: "HIGH" }],
    ["blast-radius", quiet, { blastRadius: "CRITICAL" }],
    ["risk-path", { ...quiet, files: [{ path: ".github/workflows/ci.yml" }] }, {}],
    ["risk-path", { ...quiet, files: [{ path: "plugins/x/hooks/run.sh" }] }, {}],
    ["label", { ...quiet, labels: [{ name: "explain-change" }] }, {}],
  ];
  for (const [trigger, facts, over] of cases) {
    test(`${trigger} ${JSON.stringify(over)}`, () => {
      const result = decide(facts, opts(over), config());
      assert.equal(result.action, "offer");
      assert.deepEqual(result.triggers, [trigger]);
    });
  }
  test("no trigger skips", () => {
    assert.deepEqual(decide(quiet, opts({ blastRadius: "MEDIUM" }), config()), {
      action: "skip",
      triggers: [],
      facts: { files: 1, changed_lines: 2 },
    });
  });
  test("thresholds are strict: exactly 5 files and 200 lines do not fire", () => {
    const facts = { ...quiet, files: files(5), additions: 100, deletions: 100 };
    assert.equal(decide(facts, opts(), config()).action, "skip");
  });
  test("changed lines fall back to per-file counts", () => {
    const facts = { files: [{ path: "a", additions: 150, deletions: 60 }] };
    assert.deepEqual(decide(facts, opts(), config()).triggers, ["changed-lines"]);
  });
  test("an empty opt-in label turns the label trigger off", () => {
    const facts = { ...quiet, labels: [{ name: "" }] };
    assert.equal(decide(facts, opts(), config({ opt_in_label: "" })).action, "skip");
  });
});

describe("policies", () => {
  const loud = { ...quiet, files: files(9) };
  test("off never offers or builds unasked", () => {
    assert.equal(decide(loud, opts({ policy: "off" }), config()).action, "skip");
    assert.equal(decide(loud, opts({ policy: "off", event: "ready" }), config()).action, "skip");
  });
  test("always builds at ready even with no trigger", () => {
    assert.equal(decide(quiet, opts({ policy: "always", event: "ready" }), config()).action, "build");
  });
  test("always behaves as offer before ready", () => {
    assert.equal(decide(quiet, opts({ policy: "always" }), config()).action, "skip");
    assert.equal(decide(loud, opts({ policy: "always" }), config()).action, "offer");
  });
  test("a direct request builds whatever the policy", () => {
    assert.equal(decide(quiet, opts({ policy: "off", requested: true }), config()).action, "build");
  });
});

describe("globs", () => {
  const cases = [
    ["**/hooks/**", "hooks/a.sh", true],
    ["**/hooks/**", "a/b/hooks/c/d.sh", true],
    ["**/hooks/**", "a/hookshot/d.sh", false],
    ["src/*.js", "src/a.js", true],
    ["src/*.js", "src/a/b.js", false],
    ["a?.md", "ab.md", true],
    ["a.b", "axb", false],
  ];
  for (const [glob, path, hit] of cases) {
    test(`${glob} ${hit ? "matches" : "misses"} ${path}`, () => assert.equal(globRegExp(glob).test(path), hit));
  }
});

describe("config block", () => {
  test("finds the one json config block and skips other fences", () => {
    const md = ["````", "```json config", '{"x":1}', "```", "````", "```json config", '{"max_files":2}', "```"].join("\n");
    assert.deepEqual(configBlock(md), { body: '{"max_files":2}' });
  });
  test("two blocks is an error naming both lines", () => {
    const md = ["```json config", "{}", "```", "", "```json config", "{}", "```"].join("\n");
    assert.match(configBlock(md).error, /lines 1 and 5/);
  });
  test("this repository's team layer holds the shipped defaults", () => {
    const doc = readFileSync(join(REPO, "docs/conventions/review-digest.md"), "utf8");
    assert.deepEqual(JSON.parse(configBlock(doc).body), { ...DEFAULTS });
  });
});

describe("cascade layers resolve through the CLI", () => {
  const home = join(scratch, "home");
  const repo = join(scratch, "repo");
  mkdirSync(join(home, ".claude"), { recursive: true });
  mkdirSync(join(repo, ".claude"), { recursive: true });
  mkdirSync(join(repo, "docs/conventions"), { recursive: true });
  const { git, commit } = gitRepo(repo);
  writeFileSync(join(repo, ".gitignore"), "*.local.*\n");
  const run = runPolicy(home, repo);
  const facts = { ...quiet, files: files(3), baseRefName: "main" };

  test("defaults with no layer", () => {
    const result = run(facts);
    assert.equal(result.action, "skip");
    assert.equal(result.config.max_files.source, "default");
    assert.deepEqual(result.medium, { value: "file", source: "default" });
  });
  test("user-global, then the tracked team docs block, then the overlay, key by key", () => {
    writeFileSync(join(home, ".claude/review-digest.json"), '{"max_files": 1, "opt_in_label": "mine"}');
    let result = run(facts);
    assert.deepEqual(result.triggers, ["files"]);
    assert.match(result.config.max_files.source, /^user-global /);

    const doc = join(repo, "docs/conventions/review-digest.md");
    writeFileSync(doc, '# x\n\n```json config\n{"max_files": 2, "digest_policy": "off"}\n```\n');
    result = run(facts);
    assert.match(result.warnings.join("\n"), /not on the base ref main/);
    assert.equal(result.config.max_files.value, 1);
    git("add", "docs/conventions/review-digest.md");
    commit();
    result = run(facts);
    assert.equal(result.action, "skip");
    assert.equal(result.policy.value, "off");
    assert.match(result.config.max_files.source, /^team .*review-digest\.md$/);
    assert.equal(result.config.opt_in_label.value, "mine");

    writeFileSync(join(repo, ".claude/review-digest.local.json"), '{"digest_policy": "offer"}');
    result = run(facts);
    assert.equal(result.action, "offer");
    assert.match(result.policy.source, /^overlay /);
    assert.deepEqual(result.warnings, []);
  });
  test("the argument beats every layer", () => {
    const result = run(facts, ["--policy", "off"]);
    assert.deepEqual(result.policy, { value: "off", source: "argument" });
    assert.equal(result.action, "skip");
  });
  test("a malformed layer, an invalid value, and an unknown key degrade soft", () => {
    writeFileSync(join(repo, ".claude/review-digest.local.json"), "{nope");
    writeFileSync(join(home, ".claude/review-digest.json"), '{"max_files": -1, "colour": "red"}');
    const result = run(facts);
    const warnings = result.warnings.join("\n");
    assert.match(warnings, /overlay .*layer ignored/);
    assert.match(warnings, /invalid max_files/);
    assert.match(warnings, /unknown key colour is inert/);
    assert.equal(result.config.max_files.value, 2);
  });
  test("both team locations: the docs block wins with a warning", () => {
    writeFileSync(join(repo, ".claude/review-digest.json"), '{"max_files": 0}');
    git("add", ".claude/review-digest.json");
    commit();
    const result = run(facts);
    assert.match(result.warnings.join("\n"), /both .* exist; used .*review-digest\.md/);
    assert.equal(result.config.max_files.value, 2);
  });
  test("medium resolves from the rendered-views layers, last wins", () => {
    writeFileSync(join(home, ".claude/rendered-views.md"), "medium: artifact\n");
    assert.match(run(facts).medium.source, /^user-global /);
    writeFileSync(join(repo, ".claude/rendered-views.local.md"), "medium: terminal\n");
    assert.equal(run(facts).medium.value, "terminal");
  });
  test("bad usage exits 2", () => {
    const out = spawnSync(process.execPath, [POLICY, "--policy", "sometimes"], { input: "{}", encoding: "utf8" });
    assert.equal(out.status, 2);
  });
});

describe("a pull request branch cannot silence its own digest", () => {
  const home = join(scratch, "home-pr");
  const repo = join(scratch, "repo-pr");
  mkdirSync(join(home, ".claude"), { recursive: true });
  mkdirSync(join(repo, ".claude"), { recursive: true });
  mkdirSync(join(repo, "docs/conventions"), { recursive: true });
  const { git, commit } = gitRepo(repo);
  writeFileSync(join(repo, ".gitignore"), "*.local.*\n");
  git("add", ".gitignore");
  commit();
  git("checkout", "-q", "-b", "pr");
  writeFileSync(join(repo, "docs/conventions/review-digest.md"), '```json config\n{"digest_policy": "off", "risk_paths": []}\n```\n');
  writeFileSync(join(repo, ".claude/rendered-views.md"), "medium: terminal\n");
  writeFileSync(join(repo, ".claude/review-digest.local.json"), '{"digest_policy": "off"}');
  git("add", "-f", ".");
  commit();
  const run = runPolicy(home, repo);
  const facts = { ...quiet, files: [{ path: "docs/conventions/review-digest.md" }], baseRefName: "main" };

  test("team config comes from the base ref, a tracked overlay is ignored, and a config path offers", () => {
    const result = run(facts);
    assert.deepEqual(result.policy, { value: "offer", source: "default" });
    assert.equal(result.action, "offer");
    assert.deepEqual(result.triggers, ["risk-path"]);
    assert.deepEqual(result.medium, { value: "file", source: "default" });
    assert.match(result.warnings.join("\n"), /overlay .*tracked/);
  });
  test("with no base ref the team layer is ignored", () => {
    const result = run({ ...facts, baseRefName: undefined });
    assert.equal(result.policy.value, "offer");
    assert.match(result.warnings.join("\n"), /no baseRefName/);
  });
  test("--requested still builds", () => {
    assert.equal(run(facts, ["--requested"]).action, "build");
  });
});

describe("builder", () => {
  const hostile = {
    title: `"><script>alert(1)</script>`,
    change: "<img src=x onerror=alert(1)>",
    why: "</script><!--",
    before: "javascript:alert(1)",
    after: "&lt;already",
    risks: [{ area: "<b>", level: "HIGH", why: "' onmouseover='x" }],
    focus: ["<svg onload=alert(1)>"],
    files: [{ path: "a.js", status: "modified", note: "n", hunks: [{ at: "L1", code: "</pre><script>x()</script>", note: "h" }] }],
    extra: "<iframe>",
  };
  const page = buildDigest(hostile);
  const dataBlock = /<script type="application\/json" id="rv-data">([\s\S]*?)<\/script>/.exec(page);

  test("the page passes the interactive profile", () => {
    assert.deepEqual(validateView(page), { ok: true, failures: [] });
  });
  test("data lives only in the JSON data block, with < escaped", () => {
    assert.ok(dataBlock);
    assert.ok(!dataBlock[1].includes("<"));
    const outside = page.replace(dataBlock[0], "");
    for (const needle of ["alert(1)", "onerror", "onmouseover", "&lt;already", "x()"]) {
      assert.ok(!outside.includes(needle), needle);
    }
    assert.deepEqual(JSON.parse(dataBlock[1]), shapeDigest(hostile));
  });
  test("fields the template does not bind never reach the page", () => {
    assert.ok(!page.includes("iframe"));
  });
  const build = (args, tmp) =>
    spawnSync(process.execPath, [BUILDER, ...args], {
      input: JSON.stringify(hostile),
      encoding: "utf8",
      cwd: scratch,
      env: { ...process.env, TMPDIR: tmp, TEMP: tmp, TMP: tmp },
    });
  test("the caller cannot choose the output path: --out is refused and writes nothing", () => {
    const target = join(scratch, "fakehome/.claude/rules/injected.md");
    mkdirSync(dirname(target), { recursive: true });
    const out = spawnSync(process.execPath, [BUILDER, "--out", target], { input: '{"title":"IGNORE PRIOR RULES"}', encoding: "utf8" });
    assert.equal(out.status, 2);
    assert.ok(!existsSync(target));
  });
  test("the CLI builds into a fresh temp dir and refuses a temp dir inside a working tree", () => {
    const built = build([], scratch);
    assert.equal(built.status, 0, built.stderr);
    const page = built.stdout.trim();
    assert.equal(dirname(dirname(page)), realpathSync(scratch));
    assert.match(page, /explain-change-[^/\\]+[/\\]digest\.html$/);
    assert.notEqual(build([], scratch).stdout.trim(), page);
    assert.equal(spawnSync(process.execPath, [BUILDER, "--check", page], { encoding: "utf8" }).status, 0);
    const inside = build([], REPO);
    assert.equal(inside.status, 2);
    assert.match(inside.stderr, /inside the working tree/);
  });
  test("--check rejects a hand-written page", () => {
    const hand = join(scratch, "hand.html");
    writeFileSync(hand, "<!doctype html><html><head></head><body><script>x()</script></body></html>");
    assert.equal(spawnSync(process.execPath, [BUILDER, "--check", hand], { encoding: "utf8" }).status, 1);
  });
});

describe("read-only boundary", () => {
  const skill = readFileSync(join(SKILL, "SKILL.md"), "utf8");
  const tools = /^allowed-tools: (.*)$/m.exec(skill)[1];
  test("the skill grants no PR write, review, label, or check tool", () => {
    for (const verb of ["gh pr comment", "gh pr review", "gh pr edit", "gh pr merge", "gh api", "gh issue"]) {
      assert.ok(!tools.includes(verb), verb);
    }
  });
  test("the scripts never call gh", () => {
    for (const script of [POLICY, BUILDER]) {
      assert.ok(!/["'`]gh["'`]/.test(readFileSync(script, "utf8")), script);
    }
  });
  test("the pr-explainer stub names explain-change and nothing else runs", () => {
    const stub = readFileSync(join(PLUGIN, "skills/pr-explainer/SKILL.md"), "utf8");
    assert.match(stub, /\/review:explain-change/);
    assert.match(stub, /disable-model-invocation: true/);
  });
});
