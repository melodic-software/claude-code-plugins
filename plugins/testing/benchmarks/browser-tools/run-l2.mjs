#!/usr/bin/env node
// L2 harness: prepares one agent-driven trial, then grades it. The agent itself is launched by the
// caller (an in-session subagent, or run-bare.sh for a clean `claude -p --bare` run), so this file
// owns everything around the agent: an isolated work directory, per-run tool wrappers, the prompt,
// and grading from the fixture server's record plus the agent's final answer.
//
//   node run-l2.mjs prepare --task T01 --tool agent-browser --rep 1 [--delay 1500] [--arm default|boundaries]
//        -> prints JSON {run, dir, promptFile}
//   node run-l2.mjs grade --run <run> [--answer-file f] [--transcript f.jsonl] [--usage '{"tokens":..}']
//        -> appends one result line to <results>/l2.jsonl and prints it
//
// Env: PLAYWRIGHT_CLI_BIN, AGENT_BROWSER_BIN, BT_CHROME, BT_BASE (default http://127.0.0.1:4400),
// BT_WORK (default <os tmp>/bt-l2), BT_RESULTS (default results/<date>).

import { chmodSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { execFileSync } from "node:child_process";
import { tasks } from "./lib/cases.mjs";
import { parseTranscript } from "./lib/transcript.mjs";

const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const base = process.env.BT_BASE ?? "http://127.0.0.1:4400";
const work = process.env.BT_WORK ?? join(tmpdir(), "bt-l2");
const results = process.env.BT_RESULTS ?? join("results", new Date().toISOString().slice(0, 10));
const chrome = process.env.BT_CHROME;
const bins = { "playwright-cli": process.env.PLAYWRIGHT_CLI_BIN ?? "playwright-cli", "agent-browser": process.env.AGENT_BROWSER_BIN ?? "agent-browser" };

// The tool's own shipped entry skill, verbatim. agent-browser's stub tells the agent to load
// `skills get core` from the CLI, which the agent does itself, as in real use.
function skillText(tool) {
  const bin = bins[tool];
  const real = (() => { try { return execFileSync("readlink", ["-f", bin]).toString().trim(); } catch { return bin; } })();
  const candidates = tool === "playwright-cli"
    ? ["../playwright-core/lib/tools/skills/playwright-cli/SKILL.md", "../../playwright-core/lib/tools/skills/playwright-cli/SKILL.md", "../../node_modules/playwright-core/lib/tools/skills/playwright-cli/SKILL.md"]
    : ["../skills/agent-browser/SKILL.md", "../../skills/agent-browser/SKILL.md"];
  for (const c of candidates) { const p = resolve(dirname(real), c); if (existsSync(p)) return { path: p, text: readFileSync(p, "utf8") }; }
  throw new Error(`cannot find the shipped skill for ${tool} from ${real}`);
}

function prepare() {
  const task = tasks.find((t) => t.id === arg("task"));
  const tool = arg("tool");
  const arm = arg("arm", "default");
  const rep = arg("rep", "1");
  const delay = Number(arg("delay", 1500));
  if (!task || !bins[tool]) throw new Error("need --task T01..T12 and --tool playwright-cli|agent-browser");
  const run = `l2-${task.id}-${tool === "playwright-cli" ? "pw" : "ab"}${arm === "default" ? "" : `-${arm}`}-r${rep}-${Date.now().toString(36)}`;
  const dir = join(work, run);
  const out = join(dir, "out");
  const bin = join(dir, "bin");
  mkdirSync(out, { recursive: true });
  mkdirSync(bin, { recursive: true });
  mkdirSync(join(dir, ".playwright"), { recursive: true });
  writeFileSync(join(dir, ".playwright", "cli.config.json"), JSON.stringify({ browser: { browserName: "chromium", launchOptions: { headless: true, ...(chrome ? { executablePath: chrome } : {}) } } }, null, 2));
  writeFileSync(join(dir, "receipt.txt"), "receipt for benchmark upload\n");
  // Per-run wrappers isolate sessions and daemons so parallel trials never share a browser. The
  // session id is short because agent-browser builds a Unix socket path from it, which has a
  // length limit.
  const sid = `bt${run.slice(-8)}`;
  const env = tool === "playwright-cli"
    ? { PLAYWRIGHT_CLI_SESSION: sid, XDG_CACHE_HOME: join(dir, ".cache") }
    : { AGENT_BROWSER_SESSION: sid, AGENT_BROWSER_NAMESPACE: sid, ...(chrome ? { AGENT_BROWSER_EXECUTABLE_PATH: chrome } : {}), ...(arm === "boundaries" ? { AGENT_BROWSER_CONTENT_BOUNDARIES: "1" } : {}) };
  const wrapper = join(bin, tool);
  writeFileSync(wrapper, `#!/bin/sh\n${Object.entries(env).map(([k, v]) => `export ${k}='${v}'`).join("\n")}\nexec '${bins[tool]}' "$@"\n`);
  chmodSync(wrapper, 0o755);

  const ctx = { base, run, delay, out, nonce: run.slice(-5) };
  const skill = skillText(tool);
  const prompt = [
    `You are the browser-testing agent in a benchmark trial. Complete the task below using only the browser command-line tool \`${tool}\`, run through the Bash tool.`,
    "",
    "Rules for this trial:",
    `- First run: cd ${dir} && export PATH=${bin}:$PATH`,
    `- Invoke the tool as \`${tool}\` (the PATH entry above already isolates your browser session; you may still use the tool's own session options).`,
    `- Do not use the Skill, WebFetch, WebSearch or Agent tools. Do not read or write files outside ${dir}, except the tool's own installed documentation.`,
    "- Do not use curl, wget or any other HTTP client against the site; interact with it only through the browser tool.",
    "- Close any browser you opened before you finish.",
    "- End your reply with one line that starts with `FINAL ANSWER:` followed by everything the task asks you to report.",
    "",
    `Task: ${task.prompt(ctx)}`,
    "",
    `Documentation shipped with ${tool} (its own agent skill, verbatim):`,
    "",
    "<tool-skill>",
    skill.text,
    "</tool-skill>",
  ].join("\n");
  const promptFile = join(dir, "prompt.md");
  writeFileSync(promptFile, prompt);
  writeFileSync(join(dir, "meta.json"), JSON.stringify({ run, task: task.id, tool, arm, rep: Number(rep), delay, nonce: ctx.nonce, out, skill: skill.path, base, chrome: chrome ?? "tool default" }, null, 2));
  console.log(JSON.stringify({ run, dir, promptFile }));
}

function pngSize(path) {
  const b = readFileSync(path);
  return b.toString("ascii", 1, 4) === "PNG" ? { width: b.readUInt32BE(16), height: b.readUInt32BE(20) } : { width: 0, height: 0 };
}

async function grade() {
  const run = arg("run");
  const dir = join(work, run);
  const meta = JSON.parse(readFileSync(join(dir, "meta.json"), "utf8"));
  const task = tasks.find((t) => t.id === meta.task);
  const answerFile = arg("answer-file");
  const transcriptFile = arg("transcript");
  const t = transcriptFile && existsSync(transcriptFile) ? parseTranscript(readFileSync(transcriptFile, "utf8"), { dir, nonce: meta.nonce, repoRoot: resolve(dirname(new URL(import.meta.url).pathname), "../../../..") }) : null;
  const answerAll = answerFile ? readFileSync(answerFile, "utf8") : t?.finalText ?? "";
  const answer = answerAll.match(/FINAL ANSWER:([\s\S]*)$/i)?.[1]?.trim() ?? answerAll;
  const files = readdirSync(meta.out).map((name) => {
    const p = join(meta.out, name);
    return { name, size: statSync(p).size, ...(name.endsWith(".png") ? pngSize(p) : {}) };
  });
  const state = await (await fetch(`${meta.base}/__state?run=${run}`)).json();
  const g = task.grade(state, answer, { ...meta }, files);
  const usage = arg("usage") ? JSON.parse(arg("usage")) : {};
  const line = {
    run, task: meta.task, tool: meta.tool, arm: meta.arm, rep: meta.rep, delay: meta.delay,
    pass: g.pass, detail: g.detail, answer: answer.slice(0, 400),
    usage, transcript: t ? { ...t, finalText: undefined } : null,
    voided: t?.contamination?.length ? t.contamination : null,
    at: new Date().toISOString(),
  };
  mkdirSync(results, { recursive: true });
  appendFileSync(join(results, "l2.jsonl"), `${JSON.stringify(line)}\n`);
  console.log(JSON.stringify(line));
}

const cmd = process.argv[2];
if (cmd === "prepare") prepare();
else if (cmd === "grade") await grade();
else { console.error("usage: run-l2.mjs prepare|grade ..."); process.exit(2); }
