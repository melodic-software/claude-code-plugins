#!/usr/bin/env node
// deterministic-suite.mjs: copy a plugin's eval suite without the cases that
// need a paid judge, so a run spends nothing on grading.
//
//   deterministic-suite.mjs <plugin-dir> <out-name>
//
// Reads the plugin's eval dir (the manifest's experimental.evals, else
// evals/) and writes <plugin-dir>/<out-name>/ holding every file of it except
// results/ and the cases with an llm or baseline grader. `claude plugin eval
// --eval-dir <out-name>` then runs only the deterministic cases. Prints
// {"evalDir", "kept", "dropped"} as JSON, case paths relative to the eval dir.
//
// A case is a directory holding prompt.md or case.yaml, found the way
// /evals:validate's validate-cases.py finds one. It is dropped when its
// case.yaml or any graders/*.md names type llm or baseline anywhere, quoted
// or not: run after that validator passes, every grader has one of the six
// types, so a case with no such line has deterministic graders only, and a
// stray match only drops a case, never keeps a paid one.
//
// Exit 0 written; 2 a usage error, or the eval dir or output cannot be used.
import { cpSync, existsSync, readFileSync, readdirSync, rmSync, statSync } from "node:fs";
import { join, relative, sep } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const SKIP_DIRS = new Set(["results", "mocks", "graders", "node_modules", "__pycache__"]);
const PAID = /\btype["']?\s*:\s*["']?(?:llm|baseline)\b/i;
const NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

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

export function needsJudge(caseDir) {
  const files = [join(caseDir, "case.yaml")];
  const graders = join(caseDir, "graders");
  if (existsSync(graders)) {
    files.push(...readdirSync(graders).filter((name) => name.endsWith(".md")).map((name) => join(graders, name)));
  }
  return files.some((file) => existsSync(file) && PAID.test(readFileSync(file, "utf8")));
}

export function deterministicSuite(pluginDir, outName) {
  const name = evalDirOf(pluginDir);
  const evalDir = join(pluginDir, name);
  const out = join(pluginDir, outName);
  const kept = [];
  const dropped = [];
  for (const caseDir of findCases(evalDir)) {
    (needsJudge(caseDir) ? dropped : kept).push(relative(evalDir, caseDir).split(sep).join("/"));
  }
  const skip = new Set([join(evalDir, "results"), ...dropped.map((path) => join(evalDir, path))]);
  rmSync(out, { recursive: true, force: true });
  cpSync(evalDir, out, { recursive: true, filter: (source) => !skip.has(source) });
  return { evalDir: name, kept, dropped };
}

export function main(argv = process.argv.slice(2)) {
  const [pluginDir, outName] = argv;
  if (argv.length !== 2 || !NAME.test(outName ?? "")) {
    console.error("usage: deterministic-suite.mjs <plugin-dir> <out-name>");
    return 2;
  }
  const evalDir = join(pluginDir, evalDirOf(pluginDir));
  if (!existsSync(evalDir) || !statSync(evalDir).isDirectory()) {
    console.error(`deterministic-suite: ${evalDir} is not a directory`);
    return 2;
  }
  if (evalDirOf(pluginDir) === outName) {
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
