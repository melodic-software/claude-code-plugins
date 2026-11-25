#!/usr/bin/env node
import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { loadManifest } from "../lib/prerequisites.mjs";

const SELF = fileURLToPath(import.meta.url);
const BASELINE = "scripts/prerequisites-baseline.txt";
const TOOLS = "scripts/prerequisites-tools.txt";
const SHARED = "scripts/shared-copies.txt";
const CHECKER_COPIES = ["prerequisites.mjs", "prerequisites.sh", "prerequisites.ps1"];
const CODE_EXT = new Set([".sh", ".bash", ".mjs", ".js", ".cjs", ".ts", ".tsx", ".mts", ".cts", ".py", ".ps1", ".psm1"]);
const JS_LIKE = new Set([".mjs", ".js", ".cjs", ".ts", ".tsx", ".mts", ".cts"]);
const SKIP_DIRS = new Set(["tests", "test", "fixtures", "evals", "node_modules", "__pycache__", ".venv"]);
const TEST_FILE = /(\.test\.|\.spec\.|\.Tests\.ps1$|^test_.*\.py$|_test\.py$|^conftest\.py$)/;
const ESCAPE = /prereq-ok:\s*\S/;

function readList(file) {
  return readFileSync(file, "utf8")
    .split(/\r?\n/)
    .map((l) => l.replace(/#.*/, "").trim())
    .filter(Boolean);
}

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

const alternation = (tools) =>
  [...tools]
    .sort((a, b) => b.length - a.length)
    .map(escapeRe)
    .join("|");

function shellMatcher(tools) {
  const lead = String.raw`(?:^\s*\(?|[;&|{\x60]|\$\(|\b(?:then|do|else|elif|if|while|until|exec|xargs|time|env|nohup|sudo|!)\s|\bcommand(?:\s+-[vV])?\s|\btype(?:\s+-[aPpt])?\s|\bhash\s|\bwhich\s|\bGet-Command(?:\s+-Name)?\s|&\s*)`;
  const assign = String.raw`[A-Za-z_]\w*=(?:'[^']*'|"[^"]*"|[^\s'"(]\S*)?\s+`;
  const names = alternation(tools);
  const closed = String.raw`(?:\$\(\s*|\b(?:command(?:\s+-[vV])?|type(?:\s+-[aPpt])?|hash|which|Get-Command(?:\s+-Name)?)\s+)(${names})(?=\))`;
  return new RegExp(
    String.raw`${lead}\s*(?:${assign})*(${names})(?=$|[\s;&\x60'"])(?!\s*=[^=])|${closed}`,
    "g",
  );
}

const literalsBlanked = (line) => line.replace(/'[^']*'/g, "''");

const CASE_LABEL = /^\s*[\w.*"'-]+(\s*\|\s*[\w.*"'-]+)*\s*\)/;

function callMatcher(tools) {
  return new RegExp(
    String.raw`\b(?:spawn|spawnSync|execFile|execFileSync|exec|execSync|execa|which|run|call|check_call|check_output|Popen|system)\s*\(\s*\[?\s*[rbfu]?["'\x60](${alternation(tools)})(?=["'\x60\s])`,
    "g",
  );
}

function shellLines(file, text) {
  const lines = text.split(/\r?\n/);
  if (path.basename(file) !== "SKILL.md") return lines.map((line, i) => [i + 1, line]);
  const out = [];
  let fence = null;
  lines.forEach((line, i) => {
    const open = /^\s*(```+|~~~+)\s*(\w*)/.exec(line);
    if (fence) {
      if (open && open[1].startsWith(fence.mark)) fence = null;
      else if (fence.shell) out.push([i + 1, line]);
      return;
    }
    if (open) {
      fence = { mark: open[1], shell: /^(bash|sh|shell|console|zsh|powershell|pwsh|ps1)$/i.test(open[2]) };
      return;
    }
    for (const m of line.matchAll(/!`([^`]+)`/g)) out.push([i + 1, m[1]]);
  });
  return out;
}

function withoutHeredocs(lines) {
  const out = [];
  let end = null;
  for (const [n, line] of lines) {
    if (end) {
      if (line.trim() === end) end = null;
      continue;
    }
    out.push([n, line]);
    const open = /<<-?\s*(['"]?)([A-Za-z_]\w*)\1/.exec(line);
    if (open && !/<<</.test(line)) end = open[2];
  }
  return out;
}

function isComment(line, ext) {
  const t = line.trimStart();
  if (JS_LIKE.has(ext)) return t.startsWith("//") || t.startsWith("*") || t.startsWith("/*");
  return t.startsWith("#");
}

function callUses(re, ext, text) {
  const lines = text.split(/\r?\n/);
  const masked = lines.map((l) => (isComment(l, ext) ? "" : l)).join("\n");
  const seen = new Set();
  const found = [];
  for (const m of masked.matchAll(re)) {
    const line = masked.slice(0, m.index + m[0].length).split("\n").length;
    const key = `${m[1]}@${line}`;
    if (seen.has(key) || ESCAPE.test(lines[line - 1])) continue;
    seen.add(key);
    found.push({ tool: m[1], line });
  }
  return found;
}

const matcherCache = new Map();

export function usesOf(file, text, tools) {
  const ext = path.extname(file);
  const powershell = ext === ".ps1" || ext === ".psm1";
  const shellish = file.endsWith("SKILL.md") || powershell || ext === ".sh" || ext === ".bash";
  const key = `${shellish}\n${tools.join("\n")}`;
  if (!matcherCache.has(key)) matcherCache.set(key, shellish ? shellMatcher(tools) : callMatcher(tools));
  const re = matcherCache.get(key);
  if (!shellish) return callUses(re, ext, text);
  const found = [];
  let blockComment = false;
  for (const [line, raw] of withoutHeredocs(shellLines(file, text))) {
    if (powershell && (blockComment || raw.trimStart().startsWith("<#"))) {
      blockComment = !raw.includes("#>");
      continue;
    }
    if (ESCAPE.test(raw) || isComment(raw, ext) || CASE_LABEL.test(raw)) continue;
    const content = literalsBlanked(raw);
    for (const tool of new Set([...content.matchAll(re)].map((m) => m[1] ?? m[2]))) found.push({ tool, line });
  }
  return found;
}

function scannable(rel) {
  const parts = rel.split("/");
  const base = parts.at(-1);
  if (parts.some((p) => SKIP_DIRS.has(p)) || TEST_FILE.test(base)) return false;
  return base === "SKILL.md" || CODE_EXT.has(path.extname(base));
}

function walk(dir, rel = "") {
  const files = [];
  for (const ent of readdirSync(dir, { withFileTypes: true })) {
    if (ent.name === ".git") continue;
    const r = rel ? `${rel}/${ent.name}` : ent.name;
    if (ent.isDirectory()) {
      if (!SKIP_DIRS.has(ent.name)) files.push(...walk(path.join(dir, ent.name), r));
    } else if (ent.isFile() && scannable(r)) {
      files.push(r);
    }
  }
  return files;
}

function declaredTools(manifest) {
  const names = new Set();
  for (const e of manifest.requires) {
    names.add(e.id);
    for (const n of e.detect.any ?? []) names.add(n);
    if (e.detect.probe) names.add(e.detect.probe.args[0]);
  }
  return names;
}

export function collect(root) {
  const tools = readList(path.join(root, TOOLS));
  const registered = new Set(readList(path.join(root, SHARED)).map((l) => l.split(/\s+/).slice(0, 2).join(" ")));
  const gaps = new Map();
  const problems = [];
  const addGap = (key, detail) => gaps.set(key, [...(gaps.get(key) ?? []), detail]);
  const pluginsDir = path.join(root, "plugins");
  for (const name of readdirSync(pluginsDir).sort()) {
    const pluginRoot = path.join(pluginsDir, name);
    if (!statSync(pluginRoot).isDirectory()) continue;
    const { manifest, errors, absent } = loadManifest(pluginRoot);
    const valid = !absent && errors.length === 0;
    if (!absent && !valid) addGap(`${name} schema`, `plugins/${name}/prerequisites.json: ${errors.join("; ")}`);
    if (valid) {
      for (const copy of CHECKER_COPIES) {
        const line = `lib/${copy} plugins/${name}/lib/${copy}`;
        if (!registered.has(line))
          problems.push(`plugins/${name}: declares prerequisites but ${SHARED} lacks "${line}"`);
      }
    }
    const declared = valid ? declaredTools(manifest) : new Set();
    for (const rel of walk(pluginRoot)) {
      const text = readFileSync(path.join(pluginRoot, rel), "utf8");
      if (text.slice(0, 300).includes("GENERATED from ")) continue;
      for (const { tool, line } of usesOf(rel, text, tools)) {
        if (!declared.has(tool)) addGap(`${name} ${tool}`, `plugins/${name}/${rel}:${line}`);
      }
    }
  }
  return { gaps, problems };
}

function parseArgs(argv) {
  const opts = { root: path.resolve(path.dirname(SELF), ".."), write: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--root" && argv[i + 1]) opts.root = path.resolve(argv[++i]);
    else if (argv[i] === "--write-baseline") opts.write = true;
    else return null;
  }
  return opts;
}

export function main(argv, out = { log: console.log, error: console.error }) {
  const opts = parseArgs(argv);
  if (!opts) {
    out.error("usage: check-declared-prerequisites.mjs [--root <repo>] [--write-baseline]");
    return 2;
  }
  let result;
  let baseline;
  try {
    result = collect(opts.root);
    baseline = opts.write ? [] : readList(path.join(opts.root, BASELINE));
  } catch (err) {
    out.error(`check-declared-prerequisites: ${err.message}`);
    return 2;
  }
  const { gaps, problems } = result;
  if (opts.write) {
    const header = [
      "# Prerequisite gaps the gate tolerates today: `<plugin> <gap>` per line.",
      "# `schema` means the plugin's prerequisites.json is not yet in the schema's shape;",
      "# any other gap is a tool its files run that the plugin does not declare.",
      "# Generated by `node scripts/check-declared-prerequisites.mjs --write-baseline`.",
      "# Remove a row by declaring the tool; the gate fails on a row with no gap behind it.",
    ];
    writeFileSync(path.join(opts.root, BASELINE), `${[...header, ...[...gaps.keys()].sort()].join("\n")}\n`);
    out.log(`wrote ${gaps.size} gap(s) to ${BASELINE}`);
    for (const p of problems) out.error(p);
    return problems.length ? 1 : 0;
  }
  const allowed = new Set(baseline);
  const findings = [...problems];
  for (const [key, details] of [...gaps].sort()) {
    if (allowed.has(key)) continue;
    const [plugin, gap] = key.split(" ");
    if (gap === "schema") {
      findings.push(details[0]);
    } else {
      findings.push(
        `plugins/${plugin} runs ${gap} but its prerequisites.json does not declare it: ${details.slice(0, 3).join(", ")}${details.length > 3 ? ", ..." : ""}`,
      );
    }
  }
  for (const key of baseline) {
    if (!gaps.has(key)) findings.push(`${BASELINE}: "${key}" no longer matches a gap; delete the row`);
  }
  if (findings.length) {
    for (const f of findings) out.error(f);
    out.error(`${findings.length} finding(s). Declare the tool per docs/contracts/prerequisites/README.md.`);
    return 1;
  }
  out.log(
    `prerequisites: every declaration passes the schema and every tool run is declared or baselined (${gaps.size} baselined gap(s)).`,
  );
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === SELF) {
  process.exitCode = main(process.argv.slice(2));
}
