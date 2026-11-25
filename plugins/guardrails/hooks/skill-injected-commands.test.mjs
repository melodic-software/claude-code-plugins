// test-scope: plugins/*/SKILL.md .claude/skills/*/SKILL.md plugins/*/commands/*.md
// test-scope: plugins/guardrails/hooks/hooks.json plugins/guardrails/hooks/*.sh
// test-scope: plugins/guardrails/hooks/*.mjs plugins/guardrails/lib/*
// test-scope: plugins/guardrails/hooks/fixtures/pre-skill-shell-command-payload.json
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

const HOOK_DIR = import.meta.dirname;
const PLUGIN_DIR = path.dirname(HOOK_DIR);
const ROOT = path.resolve(PLUGIN_DIR, "../..");

const ALLOWED = [
  {
    file: "plugins/knowledge/skills/video-digest/SKILL.md",
    command:
      'node "${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction/preflight.mjs" --data-dir "${CLAUDE_PLUGIN_DATA}" --asr-python "${user_config.asr_python}"',
    reason: "unset asr_python leaves a literal ${user_config.*} token shfmt cannot parse; PR #19104 quotes it",
  },
];

export function extractInjected(text) {
  const lines = text.split(/\r?\n/);
  let start = 0;
  if (lines[0] === "---") {
    const end = lines.indexOf("---", 1);
    if (end > 0) start = end + 1;
  }
  const found = [];
  let block = null;
  for (let i = start; i < lines.length; i++) {
    const line = lines[i];
    if (block) {
      const close = /^\s*(`{3,})\s*$/.exec(line);
      if (close && close[1].length >= block.ticks) {
        found.push({ line: block.line, form: "block", command: block.body.join("\n") });
        block = null;
      } else {
        block.body.push(line);
      }
      continue;
    }
    const open = /^\s*(`{3,})!/.exec(line);
    if (open) {
      block = { ticks: open[1].length, line: i + 2, body: [] };
      continue;
    }
    for (const m of line.matchAll(/(?:^|\s)!`([^`]+)`/g)) {
      found.push({ line: i + 1, form: "inline", command: m[1] });
    }
  }
  if (block) found.push({ line: block.line, form: "block", command: block.body.join("\n") });
  return found;
}

function shellOf(text) {
  const fm = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(text);
  const m = fm && /^shell:\s*["']?(\w+)/m.exec(fm[1]);
  return m?.[1].toLowerCase() === "powershell" ? "PowerShell" : "Bash";
}

test("extraction follows https://code.claude.com/docs/en/skills#inject-dynamic-context", () => {
  const text = [
    "---",
    "description: !`not-run-in-frontmatter`",
    "---",
    "!`at-line-start` and !`after-space`",
    "KEY=!`after-other-char` stays literal",
    "````!",
    "first line",
    "```",
    "second line",
    "````",
    "```bash",
    "!`inside-a-plain-fence`",
    "```",
  ].join("\n");
  assert.deepEqual(extractInjected(text), [
    { line: 4, form: "inline", command: "at-line-start" },
    { line: 4, form: "inline", command: "after-space" },
    { line: 7, form: "block", command: "first line\n```\nsecond line" },
    { line: 12, form: "inline", command: "inside-a-plain-fence" },
  ]);
});

const gitEnv = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };

function skillFiles() {
  const out = execFileSync(
    "git",
    [
      "-C",
      ROOT,
      "ls-files",
      "--",
      ":(glob)plugins/*/skills/**/SKILL.md",
      ":(glob).claude/skills/**/SKILL.md",
      ":(glob)plugins/*/commands/**/*.md",
      ":(glob).claude/commands/**/*.md",
    ],
    { encoding: "utf8", env: gitEnv },
  );
  return out.split("\n").filter((f) => f && !/(^|\/)(fixtures|tests?|evals|testdata)\//.test(f));
}

const row = JSON.parse(readFileSync(path.join(HOOK_DIR, "hooks.json"), "utf8")).hooks.PreSkillShellCommand[0]
  .hooks[0];
const rowArgs = row.args.map((a) => a.replaceAll("${CLAUDE_PLUGIN_ROOT}", PLUGIN_DIR));
const guards = rowArgs.filter((a) => /^[a-z-]+\.sh$/.test(a) && !a.includes("/"));
const fixture = JSON.parse(readFileSync(path.join(HOOK_DIR, "fixtures/pre-skill-shell-command-payload.json"), "utf8"));

const work = mkdtempSync(path.join(tmpdir(), "skill-injected-"));
process.on("exit", () => rmSync(work, { recursive: true, force: true }));
const env = Object.fromEntries(
  Object.entries(gitEnv).filter(([k]) => !k.startsWith("CLAUDE_PLUGIN_OPTION_") && k !== "HOOK_TELEMETRY_SINK"),
);
Object.assign(env, {
  CLAUDE_PLUGIN_ROOT: PLUGIN_DIR,
  CLAUDE_PROJECT_DIR: work,
  CLAUDE_PLUGIN_DATA: work,
  CLAUDE_CODE_SESSION_ATTENDED: "0",
  GIT_CEILING_DIRECTORIES: path.dirname(work),
});

function substitute(command, file) {
  const plugin = /^plugins\/([^/]+)\//.exec(file);
  let out = command
    .replaceAll("${CLAUDE_SKILL_DIR}", path.join(ROOT, path.dirname(file)))
    .replaceAll("${CLAUDE_PROJECT_DIR}", work)
    .replaceAll("${CLAUDE_SESSION_ID}", fixture.session_id)
    .replaceAll("${CLAUDE_EFFORT}", "medium");
  if (plugin) {
    out = out
      .replaceAll("${CLAUDE_PLUGIN_ROOT}", path.join(ROOT, "plugins", plugin[1]))
      .replaceAll("${CLAUDE_PLUGIN_DATA}", work);
  }
  return out;
}

function runRow(args, payload) {
  return new Promise((resolve) => {
    const child = spawn("node", args, { cwd: work, env });
    let out = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.resume();
    child.on("close", (code) => resolve({ code: code ?? 128, out }));
    child.stdin.end(payload);
  });
}

function refused({ code, out }) {
  if (code !== 0) return true;
  return out
    .split("\n")
    .filter((l) => l.startsWith("{"))
    .some((l) => {
      const d = JSON.parse(l).hookSpecificOutput?.permissionDecision;
      return d !== undefined && d !== "allow";
    });
}

test("every injected command passes the PreSkillShellCommand guards, or is allowed", async () => {
  const items = [];
  const files = skillFiles();
  for (const file of files) {
    const text = readFileSync(path.join(ROOT, file), "utf8");
    const tool = shellOf(text);
    for (const f of extractInjected(text)) items.push({ file, tool, ...f });
  }
  assert.ok(items.length > 0, "found no injected commands; the file list or parser is broken");

  const payloadOf = (item) =>
    JSON.stringify({
      ...fixture,
      cwd: work,
      tool_name: item.tool,
      tool_input: { command: substitute(item.command, item.file) },
    });
  const queue = [...items];
  await Promise.all(
    Array.from({ length: 4 }, async () => {
      for (let item = queue.shift(); item; item = queue.shift()) {
        const payload = payloadOf(item);
        if (!refused(await runRow(rowArgs, payload))) continue;
        item.by = [];
        for (const g of guards) {
          const one = rowArgs.filter((a) => !guards.includes(a)).concat(g);
          if (refused(await runRow(one, payload))) item.by.push(g.replace(/\.sh$/, ""));
        }
      }
    }),
  );

  const isAllowed = (i) => ALLOWED.some((a) => a.file === i.file && a.command === i.command);
  const bad = items.filter((i) => i.by);
  const report = bad.map(
    (i) => `${i.file}:${i.line} (${i.form}, ${i.tool}) refused by ${i.by.join(", ") || "the dispatcher"}: ${i.command}`,
  );
  console.log(
    `scanned ${files.length} files, ${items.length} injected commands ` +
      `(${items.filter((i) => i.form === "inline").length} inline, ${items.filter((i) => i.form === "block").length} block), ` +
      `${bad.length} refused, ${bad.filter(isAllowed).length} of them allowed`,
  );
  for (const line of report) console.log(`  ${line}`);
  assert.deepEqual(
    bad.filter((i) => !isAllowed(i)).map((i) => `${i.file}:${i.line}`),
    [],
    "a guard refuses an injected command; fix the command or add it to ALLOWED with a reason",
  );
  const stale = ALLOWED.filter((a) => !bad.some((i) => i.file === a.file && i.command === a.command));
  assert.deepEqual(stale, [], "an ALLOWED entry matches no refused command; remove it");
});
