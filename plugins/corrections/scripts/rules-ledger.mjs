#!/usr/bin/env node
// Reconciles a `/corrections:codify rules` ledger: every rule read from every input file is
// accounted for, or the run fails.
//   rules-ledger.mjs <ledger.json>
//   rules-ledger.mjs --list-rungs
// Run from the repository root: each row's `source` (<file>:<line>) is read from there, and the
// row's `rule` text must appear, whitespace collapsed, within ten lines from that line.
// Each input declares how many rules it holds (`rules`; zero needs a `reason`) and must have exactly
// that many rows. A row's disposition is one of check, prose, delete, held:
//   check   rung (a checking rung id), check, old_ref, proof_exit 0, covers (non-empty),
//           prose "flag-delete"
//   prose, delete, held   reason
// Prints one tally line per file and `ledger complete: ...` on success.
// Exit: 0 complete, 1 a rule unaccounted for (one stderr line each), 2 usage or unreadable input.
import { readFileSync } from "node:fs";

const CHECKING_RUNGS = [
  "shared-helper",
  "compiler-setting",
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
  const key = `${source}\u0000${collapse(String(row.rule ?? ""))}`;
  if (seen.has(key)) problems.push(`${source}: listed twice`);
  seen.add(key);

  const body = lines(file);
  if (!body) {
    problems.push(`${source}: cannot read ${file}`);
  } else if (!filled(row.rule)) {
    problems.push(`${source}: row has no rule text`);
  } else if (at > body.length || !collapse(body.slice(at - 1, at - 1 + WINDOW).join(" ")).includes(collapse(row.rule))) {
    problems.push(`${source}: rule text not found at that line`);
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
  if (!filled(row.check)) problems.push(`${source}: check row has no check command`);
  if (!filled(row.old_ref)) {
    problems.push(`${source}: check row has no old_ref: an unproven check is held`);
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
