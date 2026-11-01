// record-result.mjs: store the Overall line /toolchain:check or /toolchain:lint printed, keyed by
// the hash of the working tree it ran on, so the turn-end result gate can read it.
//
// Usage:
//   node record-result.mjs --skill check|lint --overall "<the Overall line>" [--dir <path>]
//
// --dir is any path inside the repository (default: the current directory). The line is stored
// as given; this script does not judge it beyond checking it opens with
// `Overall: PASS|FAIL|INCOMPLETE|STOPPED`.
//
// Exit codes:
//   0  recorded
//   1  invalid argument
//   2  cannot record (not a git work tree, git failed, or the store cannot be written)

import { record, repository, treeHash } from "../lib/tree-result.mjs";

function fail(code, message) {
  process.stderr.write(`record-result: ${message}\n`);
  process.exit(code);
}

const args = process.argv.slice(2);
if (args.includes("-h") || args.includes("--help")) {
  process.stdout.write('Usage: node record-result.mjs --skill check|lint --overall "<Overall line>" [--dir <path>]\n');
  process.exit(0);
}
const values = { "--skill": null, "--overall": null, "--dir": process.cwd() };
for (let i = 0; i < args.length; i += 2) {
  if (!Object.hasOwn(values, args[i])) fail(1, `unknown argument ${JSON.stringify(args[i])}`);
  if (i + 1 >= args.length) fail(1, `${args[i]} needs a value`);
  values[args[i]] = args[i + 1];
}
if (values["--skill"] === null) fail(1, "--skill is required");
if (values["--overall"] === null) fail(1, "--overall is required");

let repo;
let tree;
try {
  repo = repository(values["--dir"]);
  tree = treeHash(repo);
} catch (error) {
  fail(2, `cannot hash the working tree at ${values["--dir"]}: ${error.message}`);
}
try {
  const line = record(repo, tree, values["--skill"], values["--overall"]);
  process.stdout.write(`recorded ${values["--skill"]} for tree ${tree}: ${line}\n`);
} catch (error) {
  fail(/^(skill must|not an Overall line)/.test(error.message) ? 1 : 2, error.message);
}
