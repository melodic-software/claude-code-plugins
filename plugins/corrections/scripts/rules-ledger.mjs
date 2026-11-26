#!/usr/bin/env node
import { readFileSync } from "node:fs";

const CHECKING_RUNGS = [
  "shared-helper",
  "compiler-setting",
  "formatter",
  "editorconfig-severity",
  "analyzer-pack-rule",
  "custom-analyzer",
  "syntax-pattern-rule",
  "architecture-test",
  "behavior-test",
  "harness-setting",
  "action-guard",
  "scaffold",
  "runtime-verification",
  "formal-verification",
];
const ALIASES = { "semgrep-rule": "syntax-pattern-rule" };
const DISPOSITIONS = ["check", "prose", "delete", "held"];
const STYLES = ["formatter", "lint"];
const WINDOW = 10;
const SOURCE = /^(.+):([1-9][0-9]*)$/;

const say = (text) => process.stderr.write(`rules-ledger: ${text}\n`);
const usage = (why) => {
  if (why) say(why);
  say("usage: rules-ledger.mjs <ledger.json> | --list-rungs");
  process.exit(2);
};
const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;
const collapse = (text) => text.replace(/\s+/g, " ").trim();
const filled = (value) => typeof value === "string" && value.trim() !== "";

const args = process.argv.slice(2);
if (args.length === 1 && args[0] === "--list-rungs") {
  process.stdout.write(`${CHECKING_RUNGS.join("\n")}\n`);
  process.exit(0);
}
if (args.length !== 1) usage(args.length ? "one ledger file" : "no ledger file");

let ledger;
try {
  ledger = JSON.parse(readFileSync(args[0], "utf8"));
} catch (error) {
  usage(`cannot read ${args[0]}: ${error.message}`);
}
if (!ledger || !Array.isArray(ledger.inputs) || !Array.isArray(ledger.rows)) {
  usage("the ledger needs an `inputs` array and a `rows` array");
}

const problems = [];
const files = new Map();
for (const input of ledger.inputs) {
  if (!filled(input?.file)) {
    problems.push("an input has no file");
    continue;
  }
  if (!Number.isInteger(input.rules) || input.rules < 0) {
    problems.push(`${input.file}: no rule count`);
  } else if (input.rules === 0 && !filled(input.reason)) {
    problems.push(`${input.file}: declares 0 rules with no reason`);
  }
  files.set(input.file, { declared: input.rules, tally: Object.fromEntries(DISPOSITIONS.map((d) => [d, 0])), rows: 0 });
}

const texts = new Map();
const lines = (file) => {
  if (!texts.has(file)) {
    try {
      texts.set(file, readFileSync(file, "utf8").split(/\r?\n/));
    } catch {
      texts.set(file, null);
    }
  }
  return texts.get(file);
};

const seen = new Set();
for (const row of ledger.rows) {
  const source = String(row?.source ?? "");
  const match = SOURCE.exec(source);
  if (!match) {
    problems.push(`${source || "(no source)"}: source is not <file>:<line>`);
    continue;
  }
  const [, file, lineText] = match;
  const at = Number(lineText);
  const entry = files.get(file);
  if (!entry) {
    problems.push(`${source}: not one of the input files`);
    continue;
  }
  entry.rows += 1;

  const body = lines(file);
  if (!body) {
    problems.push(`${source}: cannot read ${file}`);
  } else if (!filled(row.rule)) {
    problems.push(`${source}: row has no rule text`);
  } else {
    const first = at <= body.length ? collapse(body[at - 1]) : "";
    const start = collapse(body.slice(at - 1, at - 1 + WINDOW).join(" ")).indexOf(collapse(row.rule));
    if (start < 0 || start >= first.length) {
      problems.push(`${source}: rule text not found at that line`);
    } else {
      const occurrence = `${file}\u0000${at}\u0000${start}`;
      if (seen.has(occurrence)) problems.push(`${source}: listed twice`);
      seen.add(occurrence);
    }
  }

  const disposition = row.disposition;
  if (!DISPOSITIONS.includes(disposition)) {
    problems.push(
      disposition === undefined
        ? `${source}: disposition missing`
        : `${source}: disposition ${JSON.stringify(disposition)} is not check, prose, delete or held`,
    );
    continue;
  }
  entry.tally[disposition] += 1;
  if (row.style !== undefined && !STYLES.includes(row.style)) {
    problems.push(`${source}: style ${JSON.stringify(row.style)} is not formatter or lint`);
  }
  if (disposition !== "check") {
    if (!filled(row.reason)) problems.push(`${source}: ${disposition} row has no reason`);
    continue;
  }
  if (!filled(row.rung)) {
    problems.push(`${source}: check row has no rung`);
  } else if (ALIASES[row.rung]) {
    problems.push(`${source}: rung "${row.rung}" is an old id: write "${ALIASES[row.rung]}"`);
  } else if (!CHECKING_RUNGS.includes(row.rung)) {
    problems.push(`${source}: rung "${row.rung}" is not a checking rung: a rule no check holds stays prose`);
  }
  if (row.rung === "formatter" && row.style !== "formatter") {
    problems.push(`${source}: formatter rung row needs style "formatter"`);
  } else if (row.style === "formatter" && row.rung !== "formatter") {
    problems.push(`${source}: style "formatter" needs the formatter rung`);
  }
  if (!filled(row.check)) problems.push(`${source}: check row has no check command`);
  if (filled(row.old_ref) && filled(row.plant)) {
    problems.push(`${source}: check row has both old_ref and plant: one proof per check`);
  } else if (!filled(row.old_ref) && !filled(row.plant)) {
    problems.push(`${source}: check row has no old_ref or plant: an unproven check is held`);
  } else if (row.proof_exit !== 0) {
    problems.push(`${source}: proof exit ${row.proof_exit ?? "missing"}, not 0: an unproven check is held`);
  }
  if (!Array.isArray(row.covers) || !row.covers.some(filled)) {
    problems.push(`${source}: check row lists no known cases it covers`);
  }
  if (row.prose !== "flag-delete") problems.push(`${source}: check row does not flag its prose for deletion`);
}

for (const [file, entry] of files) {
  if (Number.isInteger(entry.declared) && entry.declared !== entry.rows) {
    problems.push(`${file}: declares ${plural(entry.declared, "rule")}, ledger has ${plural(entry.rows, "row")}`);
  }
}

for (const [file, { rows, tally }] of files) {
  process.stdout.write(
    `${file}: ${plural(rows, "rule")}: ${tally.check} check, ${tally.prose} prose, ${tally.delete} delete, ${tally.held} held\n`,
  );
}
if (problems.length) {
  for (const problem of problems) say(problem);
  say(`${plural(problems.length, "problem")}: the ledger does not account for every rule`);
  process.exit(1);
}
const total = [...files.values()].reduce((sum, entry) => sum + entry.rows, 0);
process.stdout.write(`ledger complete: ${plural(total, "rule")} from ${plural(files.size, "file")} accounted for\n`);
