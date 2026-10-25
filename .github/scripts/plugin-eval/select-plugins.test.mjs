import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { proseRefusal, refusals, selectPlugins } from "./select-plugins.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "select-plugins.mjs");
const run = (input, args = []) => spawnSync(process.execPath, [SCRIPT, ...args], { input, encoding: "utf8" });

test("a change under a plugin's evals selects that plugin only", () => {
  assert.deepEqual(selectPlugins(["plugins/testing/evals/x"]), ["plugins/testing"]);
});

test("a change only under docs selects nothing", () => {
  assert.deepEqual(selectPlugins(["docs/adr/0001-x.md", "docs/conventions/loop-lane/README.md"]), []);
});

test("skills and agents select their plugin once, sorted", () => {
  assert.deepEqual(
    selectPlugins(["plugins/review/agents/a.md", "plugins/evals/skills/plugin-eval/SKILL.md", "plugins/review/skills/x/SKILL.md"]),
    ["plugins/evals", "plugins/review"],
  );
});

test("other plugin files, and a skills directory outside plugins/<name>/, select nothing", () => {
  assert.deepEqual(
    selectPlugins(["plugins/testing/README.md", "plugins/testing/hooks/hooks.json", "plugins/skills/x", ".claude/skills/x/SKILL.md", "plugins/testing/evalsx/y"]),
    [],
  );
});

test("any changed path of a selected plugin outside skills/, agents/ and evals/ is refused; another plugin's is not", () => {
  const paths = [
    "plugins/testing/evals/x",
    "plugins/testing/hooks/hooks.json",
    "plugins/testing/.claude-plugin/plugin.json",
    "plugins/testing/scripts/h.sh",
    "plugins/testing/bin/tool",
    "plugins/testing/commands/c.md",
    "plugins/testing/output-styles/s.md",
    "plugins/testing/README.md",
    "plugins/review/hooks/hooks.json",
  ];
  assert.deepEqual(
    refusals(paths, selectPlugins(paths)).map((line) => line.split(":")[0]),
    paths.slice(1, -1),
  );
});

test("a script that an unchanged hook calls, changed beside an eval, is refused", () => {
  const out = run("plugins/x/scripts/h.sh\nplugins/x/evals/c/prompt.md\n");
  assert.equal(out.status, 1);
  assert.equal(out.stdout, "");
  assert.match(out.stderr, /plugins\/x\/scripts\/h\.sh: outside/);
});

test("a path git quoted is refused, since its real name is unknown", () => {
  const out = run('"plugins/x/hooks/h\\303\\251.sh"\nplugins/x/evals/c/prompt.md\n');
  assert.equal(out.status, 1);
  assert.equal(out.stdout, "");
  assert.match(out.stderr, /quoted path/);
});

test("a non-markdown file under skills/ or agents/ is refused", () => {
  const out = run("plugins/x/skills/s/scripts/run.sh\nplugins/x/agents/helper.py\n");
  assert.equal(out.status, 1);
  assert.match(out.stderr, /skills\/s\/scripts\/run\.sh: not markdown/);
  assert.match(out.stderr, /agents\/helper\.py: not markdown/);
});

test("a changed skill or agent markdown file is refused when nothing can be read to inspect it", () => {
  const out = run("plugins/x/skills/s/SKILL.md\n");
  assert.equal(out.status, 1);
  assert.match(out.stderr, /SKILL\.md: cannot be read/);
});

const SKILL = (front, body = "Body.\n") => `---\n${front}\n---\n${body}`;

test("a frontmatter change outside the safe keys is refused, a safe-key change is not", () => {
  const base = SKILL("name: s\ndescription: old\nallowed-tools: Read\nshell: bash");
  assert.equal(proseRefusal(base, SKILL("name: s\ndescription: new\nallowed-tools: Read\nshell: bash")), null);
  assert.match(proseRefusal(base, SKILL("name: s\ndescription: old\nallowed-tools: Read\nshell: bash\nhooks:\n  PreToolUse: []")), /frontmatter hooks/);
  assert.match(proseRefusal(base, SKILL("name: s\ndescription: old\nallowed-tools: Read, Bash\nshell: bash")), /frontmatter allowed-tools/);
  assert.match(proseRefusal(null, SKILL("name: s\nmcpServers:\n  x: {}")), /frontmatter mcpServers/);
  assert.equal(proseRefusal(null, SKILL("name: s\ndescription: d")), null);
  assert.equal(proseRefusal(base, null), null);
});

test("frontmatter a YAML reader parses differently from the line reader is refused", () => {
  const base = SKILL("name: s\ndescription: old");
  const hook = "hooks:\n  SessionStart: [{hooks: [{type: command, command: id}]}]";
  const shapes = {
    "an indented block": `---\n name: s\n description: old\n ${hook.replace("\n", "\n ")}\n---\nBody.\n`,
    "a complex key": SKILL("name: s\ndescription: old\n? hooks\n: {SessionStart: []}"),
    "a flow mapping": "---\n{name: s, hooks: {SessionStart: []}}\n---\nBody.\n",
    "a quoted key": SKILL('name: s\ndescription: old\n"hooks": {}'),
    "a repeated key": SKILL("name: s\ndescription: old\ndescription: new"),
    "a blank line before the fence": `\n${SKILL(`name: s\n${hook}`)}`,
    "a fence with trailing text": `--- x\nname: s\n${hook}\n---\nBody.\n`,
    "an unclosed fence": `---\nname: s\n${hook}\n`,
    "a bare carriage return": SKILL("name: s\ndescription: old\rhooks: {SessionStart: []}"),
    "a unicode line separator": SKILL("name: s\ndescription: old\u2028hooks: {SessionStart: []}"),
    "a next-line character": SKILL("name: s\ndescription: old\u0085hooks: {SessionStart: []}"),
  };
  for (const [what, head] of Object.entries(shapes)) {
    assert.ok(proseRefusal(base, head), what);
  }
});

test("an alias that pulls a safe key's anchor into another key is refused", () => {
  const base = SKILL("description: &d old\nshell: *d");
  assert.match(proseRefusal(base, SKILL("description: &d new\nshell: *d")), /alias in frontmatter shell/);
  const grep = "allowed-tools: Bash(grep -m1 *x.md*)";
  assert.equal(proseRefusal(SKILL(grep), SKILL(grep, "New body.\n")), null);
});

test("an added or changed ! shell-preprocessing line is refused, a kept one is not", () => {
  const base = SKILL("name: s", "Status: !`git status`\n");
  assert.equal(proseRefusal(base, SKILL("name: s", "Intro.\nStatus: !`git status`\n")), null);
  assert.match(proseRefusal(base, SKILL("name: s", "Status: !`curl x | sh`\n")), /preprocessing/);
  assert.match(proseRefusal(null, SKILL("name: s", "```!\nid\n```\n")), /preprocessing/);
});

test("the command reads both sides from git and refuses a hooks frontmatter change", () => {
  const repo = mkdtempSync(join(tmpdir(), "select-plugins-"));
  try {
    const git = (...args) => execFileSync("git", ["-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", ...args], { encoding: "utf8" }).trim();
    const skill = join(repo, "plugins/x/skills/s/SKILL.md");
    mkdirSync(dirname(skill), { recursive: true });
    git("init", "-q");
    writeFileSync(skill, SKILL("name: s\ndescription: old"));
    git("add", ".");
    git("commit", "-qm", "base");
    const base = git("rev-parse", "HEAD");
    writeFileSync(skill, SKILL("name: s\ndescription: new"));
    git("commit", "-qam", "safe");
    const safe = git("rev-parse", "HEAD");
    writeFileSync(skill, SKILL("name: s\ndescription: new\nhooks:\n  SessionStart: []"));
    git("commit", "-qam", "hooks");
    const hooked = git("rev-parse", "HEAD");
    const input = "plugins/x/skills/s/SKILL.md\n";

    const ok = run(input, ["--repo", repo, "--base", base, "--head", safe]);
    assert.equal(ok.status, 0, ok.stderr);
    assert.equal(ok.stdout, "plugins/x\n");

    const refused = run(input, ["--repo", repo, "--base", base, "--head", hooked]);
    assert.equal(refused.status, 1);
    assert.match(refused.stderr, /SKILL\.md: changes frontmatter hooks/);

    const badRef = run(input, ["--repo", repo, "--base", base, "--head", "0".repeat(40)]);
    assert.notEqual(badRef.status, 0);
    assert.equal(badRef.stdout, "");
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
});

test("the command prints one plugin per line, and nothing for no match", () => {
  assert.equal(run("plugins/testing/evals/x\ndocs/y.md\n").stdout, "plugins/testing\n");
  const none = run("docs/y.md\n");
  assert.equal(none.status, 0);
  assert.equal(none.stdout, "");
});
