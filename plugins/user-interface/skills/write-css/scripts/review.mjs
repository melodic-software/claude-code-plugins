#!/usr/bin/env node
/* Runs the vendored good-css linter over CSS and HTML files and prints its
   violations with a rule id, moving those the resolved config disables to
   their own section.

     node review.mjs [--config FILE|JSON] <path|glob> [<path|glob> …]

   --config takes the resolved config values ({"css":{"rules":{"disable":[…]}}})
   or the whole resolver output ({"values":{…}}), as a JSON string or a file.
   Exit: 0 no findings (suppressed ones do not count), 1 findings, 2 usage
   error or crash. */
import { existsSync, globSync, readFileSync } from "node:fs";
import { check, checkFile } from "../vendor/check-css.mjs";

const USAGE = "Usage: node review.mjs [--config FILE|JSON] <path|glob> [<path|glob> …]";

const JUDGMENT = [
  "Everything pressable has an `:active` state.",
  "Sizes that scale with the viewport sit in one `clamp()` token.",
  "An `overflow: hidden` is not on something a script scrolls.",
  "The rest of the good-css rules and the project's own conventions need a read.",
];

class UsageError extends Error {}

function parseArgs(argv) {
  let config = "{}";
  const patterns = [];
  for (let index = 0; index < argv.length; index++) {
    if (argv[index] === "--config") {
      if (index + 1 >= argv.length) throw new UsageError("--config needs a file or a JSON string.");
      config = argv[++index];
    } else patterns.push(argv[index]);
  }
  if (!patterns.length) throw new UsageError("No path given.");
  return { config, patterns };
}

function disabledRules(arg) {
  let parsed;
  try {
    parsed = JSON.parse(arg.trimStart().startsWith("{") ? arg : readFileSync(arg, "utf8"));
  } catch (error) {
    throw new UsageError(`--config is neither JSON nor a readable JSON file: ${error.message}`);
  }
  const disable = (parsed?.values ?? parsed)?.css?.rules?.disable ?? [];
  if (!Array.isArray(disable)) throw new UsageError("--config css.rules.disable must be a list.");
  return new Set(disable);
}

function expand(patterns) {
  return patterns.flatMap((pattern) => {
    if (!/[*?[{]/.test(pattern)) {
      if (!existsSync(pattern)) throw new UsageError(`No such file: ${pattern}`);
      return [pattern];
    }
    const matches = globSync(pattern).sort();
    if (!matches.length) throw new UsageError(`No file matches: ${pattern}`);
    return matches;
  });
}

/* Upstream reads only a lowercase `.css` suffix as CSS, so the suffix test is
   made here and the HTML path is left to checkFile. */
const lint = (path) => (/\.css$/i.test(path) ? check(readFileSync(path, "utf8")) : checkFile(path));

function main(argv) {
  const { config, patterns } = parseArgs(argv);
  const disabled = disabledRules(config);
  const findings = [];
  const suppressed = [];
  const unchecked = [];

  for (const path of expand(patterns)) {
    const violations = lint(path);
    if (!violations) {
      unchecked.push(path);
      continue;
    }
    for (const { line, rule, message } of violations) {
      const entry = `${path}:${line} [${rule}] ${message}`;
      if (disabled.has(rule)) suppressed.push(`${entry} — reason (config: rules.disable)`);
      else findings.push(entry);
    }
  }

  const judgment = [...unchecked.map((path) => `${path}: not checked, it has no <style> block; read it by hand.`), ...JUDGMENT];
  const section = (title, lines) => `## ${title}\n\n${lines.length ? lines.join("\n") : "(none)"}\n`;
  console.log([section("Findings", findings), section("Suppressed", suppressed), section("Judgment", judgment)].join("\n"));
  return findings.length ? 1 : 0;
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (error) {
  console.error(error instanceof UsageError ? `${error.message}\n${USAGE}` : `review.mjs failed: ${error.stack ?? error}`);
  process.exitCode = 2;
}
