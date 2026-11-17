#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { basename, join, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { parse } from "../lib/yaml-subset.mjs";
import { resolveSettings } from "./settings.mjs";

export const SECTIONS = [
  "Property",
  "Harm",
  "Tool and why",
  "Bounds and assumptions",
  "Not covered",
  "Run",
  "Reading a result",
  "Updating",
];
const CHECK_KEYS = ["id", "covers", "commit", "command", "seeded_break"];
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const STALE = ["warn", "fail"];

const git = (dir, args) => {
  const r = spawnSync("git", ["-C", dir, "-c", "core.quotepath=off", ...args], { encoding: "utf8", maxBuffer: 1 << 28 });
  return { ok: r.status === 0, out: r.stdout ?? "" };
};
const lines = (text) => text.split("\0").filter(Boolean);
const isDir = (p) => existsSync(p) && statSync(p).isDirectory();
const isMapping = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const text = (v) => typeof v === "string" && v.trim() !== "";

export const globRegex = (pattern) => {
  let re = "";
  for (let i = 0; i < pattern.length; i++) {
    const c = pattern[i];
    if (c === "*" && pattern[i + 1] === "*") {
      i++;
      if (pattern[i + 1] === "/") {
        i++;
        re += "(?:.*/)?";
      } else re += ".*";
    } else if (c === "*") re += "[^/]*";
    else if (c === "?") re += "[^/]";
    else re += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  }
  return new RegExp(`^${re}$`);
};
const isGlob = (p) => /[*?]/.test(p);
const matcher = (pattern) => {
  if (isGlob(pattern)) {
    const re = globRegex(pattern);
    return (file) => re.test(file);
  }
  const plain = pattern.replace(/\/+$/, "");
  return (file) => file === plain || file.startsWith(`${plain}/`);
};

export const frontmatter = (body) => {
  const all = body.split(/\r?\n/);
  if (all[0] !== "---") return null;
  const end = all.indexOf("---", 1);
  if (end === -1) return null;
  const keys = {};
  let current = null;
  for (const line of all.slice(1, end)) {
    const m = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (m) {
      current = m[1];
      const raw = m[2].trim();
      keys[current] = /^[|>][+-]?$/.test(raw) ? "" : raw.replace(/^(["'])(.*)\1$/, "$2");
    } else if (current && /^\s+\S/.test(line)) keys[current] = `${keys[current]} ${line.trim()}`.trim();
  }
  return keys;
};

export const sections = (body) => {
  const found = new Map();
  let fence = null;
  let current = null;
  for (const line of body.split(/\r?\n/)) {
    const f = line.match(/^\s*(`{3,}|~{3,})/);
    if (f) {
      if (!fence) fence = f[1];
      else if (line.trim().startsWith(fence)) fence = null;
    }
    const h = !fence && !f && line.match(/^## (.+?)\s*$/);
    if (h) {
      current = h[1];
      found.set(current, "");
    } else if (current) found.set(current, `${found.get(current)}${line}\n`);
  }
  return found;
};

const syncProblems = (data) => {
  const problems = [];
  if (!isMapping(data)) return ["sync.yaml: expected a mapping with a checks: list"];
  if (!Array.isArray(data.checks) || data.checks.length === 0) return ["sync.yaml: checks: must be a list of at least one check"];
  if (data.outside_model !== undefined && !(Array.isArray(data.outside_model) && data.outside_model.every(text)))
    problems.push("sync.yaml: outside_model: must be a list of paths");
  const ids = new Set();
  data.checks.forEach((entry, i) => {
    const at = `sync.yaml: checks[${i}]`;
    if (!isMapping(entry)) return problems.push(`${at}: expected a mapping`);
    for (const key of CHECK_KEYS) if (entry[key] === undefined || entry[key] === null) problems.push(`${at}: ${key}: missing`);
    if (entry.id !== undefined && !text(entry.id)) problems.push(`${at}: id: must be a non-empty string`);
    else if (text(entry.id)) {
      if (ids.has(entry.id)) problems.push(`${at}: id: ${JSON.stringify(entry.id)} is not unique`);
      ids.add(entry.id);
    }
    if (entry.covers !== undefined && !(Array.isArray(entry.covers) && entry.covers.length > 0 && entry.covers.every(text)))
      problems.push(`${at}: covers: must be a list of at least one path`);
    if (entry.commit !== undefined && !(typeof entry.commit === "string" && SHA.test(entry.commit)))
      problems.push(`${at}: commit: must be a full commit id`);
    if (entry.command !== undefined && entry.command !== null && !text(entry.command)) problems.push(`${at}: command: must be a non-empty string`);
    if (entry.on_stale !== undefined && !STALE.includes(entry.on_stale)) problems.push(`${at}: on_stale: must be warn or fail`);
    const sb = entry.seeded_break;
    if (sb !== undefined && sb !== null) {
      if (!isMapping(sb)) problems.push(`${at}: seeded_break: expected a mapping`);
      else {
        if (!text(sb.change)) problems.push(`${at}: seeded_break.change: must be a non-empty string`);
        if (typeof sb.caught !== "boolean") problems.push(`${at}: seeded_break.caught: must be true or false`);
        if (!(typeof sb.commit === "string" && SHA.test(sb.commit))) problems.push(`${at}: seeded_break.commit: must be a full commit id`);
      }
    }
  });
  return problems;
};

const checkSkill = (projectDir, dir, ctx, report) => {
  const name = basename(dir);
  const fail = (msg) => report("FAIL", name, msg);
  const warn = (msg) => report("WARN", name, msg);
  const skillFile = join(dir, "SKILL.md");
  const body = existsSync(skillFile) ? readFileSync(skillFile, "utf8") : null;
  if (body === null) fail("SKILL.md: missing");
  else {
    const fm = frontmatter(body);
    if (!fm) fail("frontmatter: missing; SKILL.md must open with a --- block");
    else {
      if (fm.name !== name) fail(`frontmatter: name must be ${JSON.stringify(name)}, the folder's name`);
      if (!text(fm.description)) fail("frontmatter: description: missing");
    }
    if (!name.startsWith("formal-")) fail("folder: a formal-area skill's folder is named formal-<area>");
  }
  const found = body === null ? new Map() : sections(body);
  if (body !== null) for (const s of SECTIONS) if (!found.has(s)) fail(`section: ## ${s} missing`);
  const syncFile = join(dir, "sync.yaml");
  if (!existsSync(syncFile)) return fail("sync.yaml: missing");
  let data;
  try {
    data = parse(readFileSync(syncFile, "utf8"));
  } catch (error) {
    return fail(`sync.yaml: not valid: line ${error.line ?? "?"}: ${error.message}`);
  }
  const problems = syncProblems(data);
  for (const p of problems) fail(p);
  if (problems.length) return;
  const run = found.get("Run") ?? "";
  for (const entry of data.checks) {
    const at = `check ${JSON.stringify(entry.id)}`;
    if (body !== null && !run.includes(entry.command)) fail(`${at}: no run command: ## Run does not give its command`);
    const known = git(projectDir, ["cat-file", "-e", `${entry.commit}^{commit}`]).ok;
    const ancestor = known && git(projectDir, ["merge-base", "--is-ancestor", entry.commit, "HEAD"]).ok;
    if (!ancestor) fail(`${at}: sync commit ${entry.commit} is not an ancestor of HEAD`);
    for (const pattern of entry.covers)
      if (!ctx.headFiles.some(matcher(pattern))) fail(`${at}: covered path ${JSON.stringify(pattern)} is missing at HEAD`);
    if (!ancestor) continue;
    const changed = lines(git(projectDir, ["diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--name-only", "-z", entry.commit, "HEAD"]).out);
    const tests = entry.covers.map(matcher);
    const stale = changed.filter((f) => tests.some((t) => t(f))).sort();
    if (stale.length === 0) continue;
    const mode = entry.on_stale ?? ctx.onStale;
    const msg = `${at}: covered code changed since sync commit ${entry.commit.slice(0, 12)}: ${stale.join(", ")}`;
    (mode === "fail" ? fail : warn)(msg);
  }
};

export const check = (projectDir, targets = [], home) => {
  const out = [];
  const report = (kind, name, msg) => out.push(`${kind} ${name}: ${msg}`);
  const top = git(projectDir, ["rev-parse", "--show-toplevel"]);
  if (!top.ok || !git(projectDir, ["rev-parse", "--verify", "-q", "HEAD^{commit}"]).ok)
    return { code: 2, out: ["formal-verification check: not a git work tree with a HEAD commit"] };
  const settings = resolveSettings(projectDir, home);
  const skillsDir = resolvePath(projectDir, settings.values.skills_dir);
  const onStale = settings.values.check.on_stale;
  const headFiles = lines(git(projectDir, ["ls-tree", "-r", "-z", "--name-only", "--full-tree", "HEAD"]).out);
  const ctx = { headFiles, onStale };
  let dirs = targets.map((t) => resolvePath(projectDir, t));
  const entries = isDir(skillsDir) ? readdirSync(skillsDir).sort() : [];
  if (dirs.length === 0) dirs = entries.filter((e) => e.startsWith("formal-")).map((e) => join(skillsDir, e)).filter(isDir);
  for (const e of entries) {
    const d = join(skillsDir, e);
    if (e.startsWith("formal-") || !isDir(d)) continue;
    if (existsSync(join(d, "sync.yaml")) || isDir(join(d, "model")))
      report("WARN", e, "verification skill outside the contract: it holds a sync.yaml or model/ but is not named formal-<area>");
  }
  for (const d of [...dirs].sort()) {
    if (!isDir(d)) report("FAIL", basename(d), "not a folder");
    else checkSkill(projectDir, d, ctx, report);
  }
  for (const layer of settings.layers) for (const error of layer.errors ?? []) out.push(`WARN settings: ${error}`);
  const failures = out.filter((l) => l.startsWith("FAIL ")).length;
  const warnings = out.filter((l) => l.startsWith("WARN ")).length;
  const counted = dirs.length === 0 ? `no formal-<area> skill under ${settings.values.skills_dir}` : `${dirs.length} formal-<area> skill(s)`;
  out.push(`formal-verification check: ${counted}, ${failures} failure(s), ${warnings} warning(s)`);
  return { code: failures ? 1 : 0, out };
};

const realPath = (p) => {
  try {
    return realpathSync(p);
  } catch {
    return resolvePath(p);
  }
};

if (process.argv[1] && realPath(process.argv[1]) === realPath(fileURLToPath(import.meta.url))) {
  let parsed;
  try {
    parsed = parseArgs({ allowPositionals: true, options: { "project-dir": { type: "string" }, home: { type: "string" } } });
  } catch (error) {
    console.error(`${error.message}\nusage: check.mjs [--project-dir DIR] [--home DIR] [SKILL_DIR...]`);
    process.exit(2);
  }
  const { code, out } = check(resolvePath(parsed.values["project-dir"] ?? process.cwd()), parsed.positionals, parsed.values.home);
  process.stdout.write(`${out.join("\n")}\n`);
  process.exit(code);
}
