#!/usr/bin/env node
// post-merge-test-mutation.yml's mutate job: applies each mutant the generate
// leg returned and runs the file's covering tests on it, in a job that holds no
// secret, so no mutated code runs beside a Claude credential. No model runs here.
//
// The generation is untrusted model output: it is checked against
// generate.schema.json, and each mutant must name a tracked file inside the
// config's `mutate` globs whose `old_string` occurs exactly once and covers
// `line`; any other mutant is `invalid` and never applied. Per file, the
// covering tests run once on the unmutated tree (a red or timed-out baseline
// makes its mutants `not-run`, exit 2 `no-coverage`), then once per mutant under
// the larger of the config's timeout-ms and 1.5 times the baseline plus 5 s:
// exit 0 is `survived`, 1 `killed`, 2 `no-coverage`, a timeout `timeout`, any
// other exit `invalid`. After each mutant the file's original bytes go back,
// and the tracked tree must equal the starting snapshot; the first difference
// ends the run `restore-failed` with the rest `not-run`.
//
//   execute.mjs <generation.json> <out.json>
//
// Env: COVERING_TESTS (the read-only harness copy), CONFIG (the mutation
// config), ROOT (the checkout). Exits 0 with out.json written, 2 on a usage
// error or a generation that is not valid JSON.
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { violations } from "./report.mjs";

const GENERATE_SCHEMA = JSON.parse(readFileSync(new URL("./generate.schema.json", import.meta.url), "utf8"));
const BASELINE_TIMEOUT_MS = 600000;

// The `mutate` globs and timeout-ms from the config's plain YAML.
export function readConfig(text) {
  const globs = [];
  let inMutate = false;
  for (const line of text.split("\n")) {
    if (/^mutate:\s*$/.test(line)) {
      inMutate = true;
      continue;
    }
    if (inMutate) {
      const item = line.match(/^\s+-\s+"([^"]+)"\s*$/);
      if (item) globs.push(item[1]);
      else if (/^\S/.test(line)) inMutate = false;
    }
  }
  const timeout = text.match(/^timeout-ms:\s*(\d+)\s*$/m);
  return { globs, timeoutMs: timeout ? Number(timeout[1]) : 0 };
}

// A glob as an anchored regular expression, with `**` crossing every directory,
// dot directories included: path.matchesGlob skips a leading `.github/` for
// `**/*.mjs`, and the trigger's paths filter, which lists the same globs,
// matches it. `**/` is zero or more whole segments, `*` one segment's
// characters, `?` one of them.
export function globPattern(glob) {
  let source = "";
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (glob.startsWith("**/", i)) {
      source += "(?:.*/)?";
      i += 2;
    } else if (glob.startsWith("**", i)) {
      source += ".*";
      i += 1;
    } else if (c === "*") source += "[^/]*";
    else if (c === "?") source += "[^/]";
    else source += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  }
  return new RegExp(`^${source}$`);
}

export function inScope(path, globs) {
  let kept = false;
  for (const glob of globs) {
    if (glob.startsWith("!")) {
      if (globPattern(glob.slice(1)).test(path)) kept = false;
    } else if (globPattern(glob).test(path)) {
      kept = true;
    }
  }
  return kept;
}

// Why a mutant cannot be applied to `text`, or "" when it can.
export function applyProblem({ path, line, old_string: oldText }, { globs, text, tracked }) {
  if (path.split("/").some((part) => part === "." || part === "..")) return "path has a . or .. segment";
  if (!tracked) return "not a tracked file";
  if (!inScope(path, globs)) return "outside the mutate globs";
  if (text === null) return "unreadable";
  const at = text.indexOf(oldText);
  if (at < 0) return "old_string not found";
  if (text.indexOf(oldText, at + 1) >= 0) return "old_string occurs more than once";
  const first = text.slice(0, at).split("\n").length;
  const last = first + oldText.split("\n").length - 1;
  if (line < first || line > last) return "old_string does not cover line";
  return "";
}

export function stateOf({ status, timedOut }) {
  if (timedOut) return "timeout";
  if (status === 0) return "survived";
  if (status === 1) return "killed";
  if (status === 2) return "no-coverage";
  return "invalid";
}

// One run of the covering tests on `path`, bounded by `ms`; coreutils timeout
// also ends what the tests started.
function cover(harness, path, ms, root) {
  const started = Date.now();
  const r = spawnSync("timeout", ["--kill-after=10", String(Math.ceil(ms / 1000)), "bash", harness, path], {
    cwd: root,
    stdio: "ignore",
  });
  return { status: r.status, timedOut: r.status === 124 || r.status === 137, ms: Date.now() - started };
}

const git = (root, ...args) => spawnSync("git", ["-C", root, ...args], { encoding: "utf8" });

const readText = (file) => {
  try {
    return readFileSync(file, "utf8");
  } catch {
    return null;
  }
};

export function execute(generation, { root, harness, config, run = cover }) {
  const shape = violations(generation, GENERATE_SCHEMA);
  if (shape.length) return { outcome: "refused", detail: `the generation does not match its schema (${shape[0]})`, mutants: [] };
  if (generation.outcome !== "generated") return { outcome: generation.outcome, detail: generation.detail, mutants: [] };
  const { globs, timeoutMs } = readConfig(config);
  const snapshot = git(root, "status", "--porcelain").stdout;
  const out = generation.mutants.map((m) => ({ ...m, state: "not-run" }));
  const baselines = new Map();
  let invalid = 0;
  for (const [index, mutant] of out.entries()) {
    const file = join(root, mutant.path);
    const tracked = git(root, "ls-files", "--error-unmatch", "--", mutant.path).status === 0;
    const text = tracked ? readText(file) : null;
    if (applyProblem(mutant, { globs, text, tracked })) {
      mutant.state = "invalid";
      invalid++;
      continue;
    }
    if (!baselines.has(mutant.path)) baselines.set(mutant.path, run(harness, mutant.path, BASELINE_TIMEOUT_MS, root));
    const baseline = baselines.get(mutant.path);
    if (baseline.timedOut || (baseline.status !== 0 && baseline.status !== 2)) continue;
    if (baseline.status === 2) {
      mutant.state = "no-coverage";
      continue;
    }
    const original = readFileSync(file);
    writeFileSync(file, text.replace(mutant.old_string, () => mutant.new_string));
    try {
      mutant.state = stateOf(run(harness, mutant.path, Math.max(timeoutMs, 1.5 * baseline.ms + 5000), root));
    } finally {
      writeFileSync(file, original);
    }
    const clean = git(root, "diff", "--quiet", "--", mutant.path).status === 0 && git(root, "status", "--porcelain").stdout === snapshot;
    if (!clean) {
      return {
        outcome: "restore-failed",
        detail: `the tracked tree differed from its starting state after mutant ${index + 1}; later mutants did not run`,
        mutants: out,
      };
    }
  }
  const files = new Set(out.map((m) => m.path)).size;
  return {
    outcome: "reported",
    detail: `${out.length} mutants over ${files} files, ${invalid} invalid. ${generation.detail}`.slice(0, 500),
    mutants: out,
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [input, output] = process.argv.slice(2);
  let generation;
  try {
    generation = JSON.parse(readFileSync(input, "utf8"));
  } catch (error) {
    console.error(`execute: cannot read ${input}: ${error.message}`);
    process.exit(2);
  }
  const result = execute(generation, {
    root: process.env.ROOT ?? process.cwd(),
    harness: process.env.COVERING_TESTS,
    config: readFileSync(process.env.CONFIG, "utf8"),
  });
  writeFileSync(output, `${JSON.stringify(result)}\n`);
  const counts = {};
  for (const m of result.mutants) counts[m.state] = (counts[m.state] ?? 0) + 1;
  console.log(`execute: ${result.outcome}; ${JSON.stringify(counts)}`);
}
