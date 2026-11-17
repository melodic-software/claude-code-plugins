#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { lstatSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import { basename, dirname, isAbsolute, join, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { escapes, fileState } from "../lib/config-cascade.mjs";
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
const GIT_ENV = { ...process.env, GIT_NO_LAZY_FETCH: "1" };

const git = (dir, args) => {
  const r = spawnSync("git", ["-C", dir, "-c", "core.quotepath=off", ...args], { encoding: "utf8", maxBuffer: 1 << 28, env: GIT_ENV });
  return { ok: r.status === 0, out: r.stdout ?? "" };
};
const q = (s) => JSON.stringify(s);
const lines = (text) => text.split("\0").filter(Boolean);
const kind = (p) => {
  try {
    const st = lstatSync(p);
    return st.isSymbolicLink() ? "link" : st.isDirectory() ? "dir" : st.isFile() ? "file" : "other";
  } catch {
    return null;
  }
};
const isMapping = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const text = (v) => typeof v === "string" && v.trim() !== "";

const tokens = (pattern) => {
  const out = [];
  for (let i = 0; i < pattern.length; i++) {
    const c = pattern[i];
    if (c !== "*") {
      out.push(c === "?" ? { t: "one" } : { t: "lit", c });
      continue;
    }
    let n = 1;
    while (pattern[i + 1] === "*") {
      n++;
      i++;
    }
    if (n === 1) out.push({ t: "seg" });
    else if (pattern[i + 1] === "/") {
      i++;
      out.push({ t: "dirs" });
    } else out.push({ t: "all" });
  }
  return out;
};

export const globMatch = (pattern, path) => {
  const toks = tokens(pattern);
  const m = toks.length;
  const mid = m + 1;
  const close = (set) => {
    const stack = [...set];
    while (stack.length) {
      const i = stack.pop();
      if (i < m && toks[i].t !== "lit" && toks[i].t !== "one" && !set.has(i + 1)) {
        set.add(i + 1);
        stack.push(i + 1);
      }
    }
    return set;
  };
  let states = close(new Set([0]));
  for (const c of path) {
    const next = new Set();
    for (const s of states) {
      const i = s >= mid ? s - mid : s;
      if (i === m) continue;
      const tok = toks[i];
      if (tok.t === "dirs") {
        if (c === "/") next.add(i);
        else next.add(mid + i);
      } else if (tok.t === "lit" ? tok.c === c : tok.t === "one" && c !== "/") next.add(i + 1);
      else if (tok.t === "seg" && c !== "/") next.add(i);
      else if (tok.t === "all") next.add(i);
    }
    if (next.size === 0) return false;
    states = close(next);
  }
  return states.has(m);
};
const matcher = (pattern) => {
  if (/[*?]/.test(pattern)) return (file) => globMatch(pattern, file);
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

const givesCommand = (run, command) =>
  run.split("\n").some((line) => {
    const l = line.trim().replace(/^[-*]\s+/, "");
    return l === command || l === `\`${command}\``;
  });

const repoRelative = (p) => typeof p === "string" && p.trim() !== "" && !isAbsolute(p) && !/^[A-Za-z]:/.test(p) && !p.split(/[\\/]/).includes("..");

const syncProblems = (data) => {
  const problems = [];
  if (!isMapping(data)) return ["sync.yaml: expected a mapping with a checks: list"];
  if (!Array.isArray(data.checks) || data.checks.length === 0) return ["sync.yaml: checks: must be a list of at least one check"];
  if (data.outside_model !== undefined) {
    if (!Array.isArray(data.outside_model)) problems.push("sync.yaml: outside_model: must be a list of paths");
    else for (const p of data.outside_model) if (!repoRelative(p)) problems.push(`sync.yaml: outside_model: ${q(p)} must be a repository-relative path with no .. segment`);
  }
  const ids = new Set();
  data.checks.forEach((entry, i) => {
    const at = `sync.yaml: checks[${i}]`;
    if (!isMapping(entry)) return problems.push(`${at}: expected a mapping`);
    for (const key of CHECK_KEYS) if (entry[key] === undefined || entry[key] === null) problems.push(`${at}: ${key}: missing`);
    if (entry.id !== undefined && !text(entry.id)) problems.push(`${at}: id: must be a non-empty string`);
    else if (text(entry.id)) {
      if (ids.has(entry.id)) problems.push(`${at}: id: ${q(entry.id)} is not unique`);
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

const readGuarded = (path, label, fail) => {
  const state = fileState(path);
  if (state.refused) {
    fail(`${label}: ${state.refused}`);
    return undefined;
  }
  return state.ok ? readFileSync(path, "utf8") : null;
};

const checkSkill = (projectDir, dir, ctx, report) => {
  const name = basename(dir);
  const fail = (msg) => report("FAIL", name, msg);
  const warn = (msg) => report("WARN", name, msg);
  if (kind(dir) !== "dir") return fail("folder: is a symlink or not a folder; the check reads only real folders");
  const body = readGuarded(join(dir, "SKILL.md"), "SKILL.md", fail);
  if (body === null) fail("SKILL.md: missing");
  else if (body !== undefined) {
    const fm = frontmatter(body);
    if (!fm) fail("frontmatter: missing; SKILL.md must open with a --- block");
    else {
      if (fm.name !== name) fail(`frontmatter: name must be ${q(name)}, the folder's name`);
      if (!text(fm.description)) fail("frontmatter: description: missing");
    }
    if (!name.startsWith("formal-")) fail("folder: a formal-area skill's folder is named formal-<area>");
  }
  const hasBody = typeof body === "string";
  const found = hasBody ? sections(body) : new Map();
  if (hasBody) {
    for (const s of SECTIONS) if (!found.has(s)) fail(`section: ## ${s} missing`);
    const order = [...found.keys()].filter((s) => SECTIONS.includes(s));
    const expected = SECTIONS.filter((s) => found.has(s));
    if (order.join("\n") !== expected.join("\n")) fail(`section: out of order; the contract's order is ${expected.map((s) => `## ${s}`).join(", ")}`);
  }
  const raw = readGuarded(join(dir, "sync.yaml"), "sync.yaml", fail);
  if (raw === undefined) return;
  if (raw === null) return fail("sync.yaml: missing");
  let data;
  try {
    data = parse(raw);
  } catch (error) {
    return fail(`sync.yaml: not valid: line ${error.line ?? "?"}: ${error.message}`);
  }
  const problems = syncProblems(data);
  for (const p of problems) fail(p);
  if (problems.length) return;
  const run = found.get("Run") ?? "";
  for (const entry of data.checks) {
    const at = `check ${q(entry.id)}`;
    if (hasBody && !givesCommand(run, entry.command)) fail(`${at}: no run command: ## Run does not give its command on a line of its own`);
    const known = git(projectDir, ["cat-file", "-e", `${entry.commit}^{commit}`]).ok;
    const ancestor = known && git(projectDir, ["merge-base", "--is-ancestor", entry.commit, "HEAD"]).ok;
    if (!ancestor) fail(`${at}: sync commit ${entry.commit} is not an ancestor of HEAD`);
    if (ctx.defaultRef)
      for (const [label, commit] of [["sync commit", entry.commit], ["seeded-break commit", entry.seeded_break.commit]]) {
        const onDefault = git(projectDir, ["cat-file", "-e", `${commit}^{commit}`]).ok && git(projectDir, ["merge-base", "--is-ancestor", commit, ctx.defaultRef]).ok;
        if (!onDefault) fail(`${at}: ${label} ${commit} is not on the default branch ${q(ctx.defaultLabel)}; a squash or rebase merge will discard it`);
      }
    for (const pattern of entry.covers)
      if (!ctx.headFiles.some(matcher(pattern))) fail(`${at}: covered path ${q(pattern)} is missing at HEAD`);
    if (!ancestor) continue;
    const changed = lines(git(projectDir, ["diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--name-only", "-z", entry.commit, "HEAD"]).out);
    const tests = entry.covers.map(matcher);
    const stale = changed.filter((f) => tests.some((t) => t(f))).sort();
    if (stale.length === 0) continue;
    const mode = entry.on_stale ?? ctx.onStale;
    const msg = `${at}: covered code changed since sync commit ${entry.commit.slice(0, 12)}: ${stale.map(q).join(", ")}`;
    (mode === "fail" ? fail : warn)(msg);
  }
};

export const check = (projectDir, targets = [], { home, skillsDir: skillsOption, defaultRef } = {}) => {
  const out = [];
  const report = (level, name, msg) => out.push(`${level} ${q(name)}: ${msg}`);
  const top = git(projectDir, ["rev-parse", "--show-toplevel"]);
  if (!top.ok || !git(projectDir, ["rev-parse", "--verify", "-q", "HEAD^{commit}"]).ok)
    return { code: 2, out: ["formal-verification check: not a git work tree with a HEAD commit"] };
  const settings = resolveSettings(projectDir, home);
  const skillsRel = skillsOption ?? settings.values.skills_dir;
  const skillsDir = resolvePath(projectDir, skillsRel);
  const ctx = { onStale: settings.values.check.on_stale, headFiles: [], defaultRef: null, defaultLabel: defaultRef };
  if (defaultRef !== undefined) {
    const resolved = !defaultRef.startsWith("-") && git(projectDir, ["rev-parse", "--verify", "-q", "--end-of-options", `${defaultRef}^{commit}`]);
    if (resolved && resolved.ok) ctx.defaultRef = resolved.out.trim();
    else report("WARN", "default-ref", `${q(defaultRef)} does not resolve to a commit here; the default-branch check is skipped`);
  }
  const outside = (p) => {
    let at = p;
    while (kind(at) === null && dirname(at) !== at) at = dirname(at);
    return escapes(at, projectDir);
  };
  let dirs = [];
  let entries = [];
  if (outside(skillsDir)) {
    out.push(`FAIL settings: the skills folder ${q(skillsRel)} is outside the repository`);
  } else {
    ctx.headFiles = lines(git(projectDir, ["ls-tree", "-r", "-z", "--name-only", "--full-tree", "HEAD"]).out);
    entries = kind(skillsDir) === "dir" || kind(skillsDir) === "link" ? readdirSync(skillsDir).sort() : [];
    for (const t of targets) {
      const d = resolvePath(projectDir, t);
      if (outside(d)) report("FAIL", t, "is outside the repository");
      else dirs.push(d);
    }
    if (targets.length === 0) dirs = entries.filter((e) => e.startsWith("formal-")).map((e) => join(skillsDir, e));
    for (const e of entries) {
      const d = join(skillsDir, e);
      if (e.startsWith("formal-") || kind(d) !== "dir") continue;
      if (kind(join(d, "sync.yaml")) !== null || kind(join(d, "model")) === "dir")
        report("WARN", e, "verification skill outside the contract: it holds a sync.yaml or model/ but is not named formal-<area>");
    }
    for (const d of [...dirs].sort()) checkSkill(projectDir, d, ctx, report);
  }
  for (const layer of settings.layers) for (const error of layer.errors ?? []) out.push(`WARN settings: ${q(error)}`);
  const failures = out.filter((l) => l.startsWith("FAIL ")).length;
  const warnings = out.filter((l) => l.startsWith("WARN ")).length;
  const counted = dirs.length === 0 ? `no formal-<area> skill under ${q(skillsRel)}` : `${dirs.length} formal-<area> skill(s)`;
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
    parsed = parseArgs({
      allowPositionals: true,
      options: { "project-dir": { type: "string" }, home: { type: "string" }, "skills-dir": { type: "string" }, "default-ref": { type: "string" } },
    });
  } catch (error) {
    console.error(`${error.message}\nusage: check.mjs [--project-dir DIR] [--home DIR] [--skills-dir DIR] [--default-ref REF] [SKILL_DIR...]`);
    process.exit(2);
  }
  const { code, out } = check(resolvePath(parsed.values["project-dir"] ?? process.cwd()), parsed.positionals, {
    home: parsed.values.home,
    skillsDir: parsed.values["skills-dir"],
    defaultRef: parsed.values["default-ref"],
  });
  process.stdout.write(`${out.join("\n")}\n`);
  process.exit(code);
}
