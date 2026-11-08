#!/usr/bin/env node
// deterministic-suite.mjs: copy a plugin's eval suite without the graders
// that need a paid judge, so a run spends nothing on grading.
//
//   deterministic-suite.mjs <plugin-dir> <out-name>
//
// Reads the plugin's eval dir (the manifest's experimental.evals, else
// evals/) and writes <plugin-dir>/<out-name>/ holding every file of it except
// results/, the llm and baseline graders, and the cases left with no grader.
// `claude plugin eval --eval-dir <out-name>` then runs deterministic graders
// only. Prints {"evalDir", "kept", "dropped", "stripped"} as JSON: case paths
// relative to the eval dir, and stripped maps each kept case that lost graders
// to their names.
//
// A case is a directory holding prompt.md or case.yaml, found the way
// /evals:validate's validate-cases.py finds one. A grader is paid when its
// text names type llm or baseline, quoted or not: a graders/*.md file, or one
// item of case.yaml's block `graders:` list. Run after that validator passes,
// every grader has one of the six types, and a stray match only strips a
// grader, never keeps a paid one. Each case.yaml cut removes the item's lines
// and leaves every other byte; it is kept only when validate-cases.py's own
// parser reads the copy as the original minus those items and no paid line is
// left. Any other outcome (a flow-style list, a parse error, no python3) drops
// the case, with a note on stderr. A stripped grader's samples/<name>.json goes
// with it. The parser is loaded from this script's tree, never the plugin's.
//
// Exit 0 written; 2 a usage error, or the eval dir or output cannot be used.
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

const SKIP_DIRS = new Set(["results", "mocks", "graders", "node_modules", "__pycache__"]);
const PAID = /\btype["']?\s*:\s*["']?(?:llm|baseline)\b/i;
const NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
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
    // No readable manifest: the default eval dir.
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

// The documents validate-cases.py's parse_yaml reads from texts, or throws.
function parseYaml(texts) {
  const run = spawnSync("python3", ["-I", "-c", PARSE, VALIDATOR], { input: JSON.stringify(texts), encoding: "utf8" });
  if (run.error || run.status !== 0) {
    throw new Error(run.error?.message ?? (run.stderr.trim().split("\n").at(-1) || `python3 exit ${run.status}`));
  }
  return JSON.parse(run.stdout);
}

// Line ranges [start, end) of each item of the top-level block `graders:`
// list, each ending at its last non-blank, non-comment line; null for any
// other shape.
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

// The copy of one case.yaml without its paid items, as {text, names, left}
// (left null when its graders are not a block list), or throws when the cut
// cannot be proven against the parser.
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
  // With every item paid, the cut takes the header and the whole list.
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

// How one case is copied: null to drop it, else the case.yaml text to write
// (or null to leave it), and the graders/*.md files and names to strip.
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

export function deterministicSuite(pluginDir, outName, warn = (line) => console.error(line)) {
  const name = evalDirOf(pluginDir);
  const evalDir = join(pluginDir, name);
  const out = join(pluginDir, outName);
  const kept = [];
  const dropped = [];
  const stripped = {};
  const plans = new Map();
  for (const caseDir of findCases(evalDir)) {
    const path = relative(evalDir, caseDir).split(sep).join("/");
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
  const skip = new Set([join(evalDir, "results"), ...dropped.map((path) => join(evalDir, path))]);
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
  return { evalDir: name, kept, dropped, stripped };
}

export function main(argv = process.argv.slice(2)) {
  const [pluginDir, outName] = argv;
  if (argv.length !== 2 || !NAME.test(outName ?? "")) {
    console.error("usage: deterministic-suite.mjs <plugin-dir> <out-name>");
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
    console.log(JSON.stringify(deterministicSuite(pluginDir, outName)));
  } catch (error) {
    console.error(`deterministic-suite: ${error.message}`);
    return 2;
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = main();
}
