#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, join, relative, sep } from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

const SKIP_DIRS = new Set(["results", "mocks", "graders", "node_modules", "__pycache__"]);
const PAID = /\btype["']?\s*:\s*["']?(?:llm|baseline)\b/i;
const NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const USAGE = "usage: deterministic-suite.mjs <plugin-dir> <out-name> [--cases <names>] [--keep-judged]";
const VALIDATOR = fileURLToPath(new URL("../../../plugins/evals/skills/validate/scripts/validate-cases.py", import.meta.url));
const PARSE = `
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("validate_cases", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(json.dumps([module.parse_yaml(text) for text in json.load(sys.stdin)]))
`;

export function evalDirOf(pluginDir) {
  try {
    const manifest = JSON.parse(readFileSync(join(pluginDir, ".claude-plugin", "plugin.json"), "utf8"));
    const named = manifest?.experimental?.evals;
    if (typeof named === "string" && NAME.test(named)) {
      return named;
    }
  } catch {
  }
  return "evals";
}

export function findCases(evalDir) {
  const cases = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      if (!entry.isDirectory() || SKIP_DIRS.has(entry.name) || entry.name.startsWith(".")) {
        continue;
      }
      const path = join(dir, entry.name);
      if (existsSync(join(path, "prompt.md")) || existsSync(join(path, "case.yaml"))) {
        cases.push(path);
      } else {
        walk(path);
      }
    }
  };
  walk(evalDir);
  return cases;
}

function parseYaml(texts) {
  const run = spawnSync("python3", ["-I", "-c", PARSE, VALIDATOR], { input: JSON.stringify(texts), encoding: "utf8" });
  if (run.error || run.status !== 0) {
    throw new Error(run.error?.message ?? (run.stderr.trim().split("\n").at(-1) || `python3 exit ${run.status}`));
  }
  return JSON.parse(run.stdout);
}

export function graderItems(lines) {
  const header = lines.findIndex((line) => /^graders[ \t]*:[ \t]*(?:#.*)?\r?$/.test(line));
  const body = (line) => line.trim() !== "" && !line.trim().startsWith("#");
  const indent = (line) => line.length - line.trimStart().length;
  const first = lines.findIndex((line, index) => index > header && body(line));
  if (header === -1 || first === -1 || !lines[first].trimStart().startsWith("-")) {
    return null;
  }
  const dash = indent(lines[first]);
  const items = [];
  for (let index = first; index < lines.length; index++) {
    const line = lines[index];
    if (!body(line)) {
      continue;
    }
    if (indent(line) < dash || (indent(line) === dash && !line.slice(dash).startsWith("-"))) {
      break;
    }
    if (indent(line) === dash) {
      items.push([index, index + 1]);
    } else {
      items.at(-1)[1] = index + 1;
    }
  }
  return { header, items };
}

export function stripCaseYaml(text) {
  const lines = text.split("\n");
  const shape = graderItems(lines);
  const paid = shape ? shape.items.map(([start, end]) => PAID.test(lines.slice(start, end).join("\n"))) : [];
  if (!paid.includes(true)) {
    if (PAID.test(text)) {
      throw new Error("a paid grader outside a block graders list");
    }
    return { text, names: [], left: shape?.items.length ?? null };
  }
  const cuts = paid.includes(false) ? shape.items.filter((_, index) => paid[index]) : [[shape.header, shape.items.at(-1)[1]]];
  const stripped = lines.filter((_, index) => !cuts.some(([start, end]) => index >= start && index < end)).join("\n");
  if (PAID.test(stripped)) {
    throw new Error("a paid line is left after the cut");
  }
  const [before, after] = parseYaml([text, stripped]);
  const graders = before?.graders;
  if (!Array.isArray(graders) || graders.length !== shape.items.length) {
    throw new Error("the graders list does not match its lines");
  }
  const expected = { ...before, graders: graders.filter((_, index) => !paid[index]) };
  if (expected.graders.length === 0) {
    delete expected.graders;
  }
  if (!isDeepStrictEqual(after, expected)) {
    throw new Error("the cut changed more than the paid graders");
  }
  const names = graders.filter((_, index) => paid[index]).map((grader) => String(grader?.name));
  const bad = names.find((name) => !NAME.test(name));
  if (bad !== undefined) {
    throw new Error(`the paid grader name ${JSON.stringify(bad)} is not a plain file name`);
  }
  return { text: stripped, names, left: expected.graders?.length ?? 0 };
}

export function planCase(caseDir) {
  const graderDir = join(caseDir, "graders");
  const files = existsSync(graderDir) ? readdirSync(graderDir).filter((name) => name.endsWith(".md")).sort() : [];
  const paidFiles = files.filter((name) => PAID.test(readFileSync(join(graderDir, name), "utf8")));
  const yamlPath = join(caseDir, "case.yaml");
  const original = existsSync(yamlPath) ? readFileSync(yamlPath, "utf8") : null;
  if (paidFiles.length === 0 && (original === null || !PAID.test(original))) {
    return { yaml: null, files: [], names: [] };
  }
  const yaml = original === null ? { text: null, names: [], left: 0 } : stripCaseYaml(original);
  if (yaml.left === null) {
    yaml.left = parseYaml([original])[0]?.graders?.length ?? 0;
  }
  if (yaml.left + files.length - paidFiles.length === 0) {
    return null;
  }
  return {
    yaml: yaml.text === original ? null : yaml.text,
    files: paidFiles,
    names: [...paidFiles.map((name) => name.slice(0, -3)), ...yaml.names],
  };
}

function caseNames(caseDirs) {
  const withYaml = caseDirs.filter((dir) => existsSync(join(dir, "case.yaml")));
  const texts = withYaml.map((dir) => readFileSync(join(dir, "case.yaml"), "utf8").trimStart());
  const docs = texts.length ? parseYaml(texts.map((text) => (text.startsWith("---") ? text.slice(3) : text))) : [];
  const named = new Map(withYaml.map((dir, i) => [dir, docs[i]?.name]));
  return caseDirs.map((dir) => {
    const name = named.get(dir);
    return typeof name === "string" && name !== "" ? name : basename(dir);
  });
}

function parseCaseList(raw) {
  const items = [...new Set(String(raw ?? "").trim().split(/\s+/).filter(Boolean))];
  const bad = items.find((item) => !NAME.test(item));
  if (bad !== undefined) {
    throw new Error(`case name ${JSON.stringify(bad)} is not a valid name`);
  }
  return items.length ? items : null;
}

export function deterministicSuite(pluginDir, outName, warnOrOptions = {}) {
  const options = typeof warnOrOptions === "function" ? { warn: warnOrOptions } : warnOrOptions;
  const warn = options.warn ?? ((line) => console.error(line));
  const keepJudged = Boolean(options.keepJudged);
  const selected = parseCaseList(options.cases);
  const name = evalDirOf(pluginDir);
  const evalDir = join(pluginDir, name);
  const out = join(pluginDir, outName);
  const allCases = findCases(evalDir);
  const excluded = [];
  let chosenCases = allCases;
  if (selected !== null) {
    const wanted = new Set(selected);
    const matched = new Set();
    const names = caseNames(allCases);
    chosenCases = [];
    for (let i = 0; i < allCases.length; i++) {
      if (wanted.has(names[i])) {
        matched.add(names[i]);
        chosenCases.push(allCases[i]);
      } else {
        excluded.push(allCases[i]);
      }
    }
    const missing = selected.filter((item) => !matched.has(item));
    if (missing.length > 0) {
      throw new Error(`unknown case${missing.length === 1 ? "" : "s"}: ${missing.join(", ")}`);
    }
  }
  const kept = [];
  const dropped = [];
  const stripped = {};
  const plans = new Map();
  for (const caseDir of chosenCases) {
    const path = relative(evalDir, caseDir).split(sep).join("/");
    if (keepJudged) {
      kept.push(path);
      continue;
    }
    let plan = null;
    try {
      plan = planCase(caseDir);
    } catch (error) {
      warn(`deterministic-suite: ${path} dropped: ${error.message}`);
    }
    if (plan === null) {
      dropped.push(path);
      continue;
    }
    kept.push(path);
    if (plan.names.length > 0) {
      stripped[path] = plan.names;
      plans.set(path, plan);
    }
  }
  const skip = new Set([join(evalDir, "results"), ...excluded, ...dropped.map((path) => join(evalDir, path))]);
  rmSync(out, { recursive: true, force: true });
  cpSync(evalDir, out, { recursive: true, filter: (source) => !skip.has(source) });
  for (const [path, plan] of plans) {
    const copy = join(out, path);
    if (plan.yaml !== null) {
      writeFileSync(join(copy, "case.yaml"), plan.yaml);
    }
    for (const file of plan.files) {
      rmSync(join(copy, "graders", file));
    }
    for (const grader of plan.names) {
      rmSync(join(copy, "samples", `${grader}.json`), { force: true });
    }
  }
  const result = { evalDir: name, kept, dropped, stripped };
  if (selected !== null) {
    result.selected = selected;
  }
  return result;
}

export function main(argv = process.argv.slice(2)) {
  const positional = [];
  let cases = null;
  let keepJudged = false;
  let seenCases = false;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--cases") {
      if (seenCases || i + 1 >= argv.length) {
        console.error(USAGE);
        return 2;
      }
      seenCases = true;
      cases = argv[++i];
    } else if (arg === "--keep-judged") {
      keepJudged = true;
    } else if (arg.startsWith("-")) {
      console.error(USAGE);
      return 2;
    } else {
      positional.push(arg);
    }
  }
  const [pluginDir, outName] = positional;
  if (positional.length !== 2 || !NAME.test(outName ?? "")) {
    console.error(USAGE);
    return 2;
  }
  const name = evalDirOf(pluginDir);
  const evalDir = join(pluginDir, name);
  if (!existsSync(evalDir) || !statSync(evalDir).isDirectory()) {
    console.error(`deterministic-suite: ${evalDir} is not a directory`);
    return 2;
  }
  if (name === outName) {
    console.error("deterministic-suite: the output would replace the eval dir");
    return 2;
  }
  try {
    console.log(JSON.stringify(deterministicSuite(pluginDir, outName, { cases, keepJudged })));
  } catch (error) {
    console.error(`deterministic-suite: ${error.message}`);
    return 2;
  }
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  process.exitCode = main();
}
