#!/usr/bin/env node
// hill-climb-edit.mjs: apply and check the one skill edit maintenance-measure-skill-edit.yml's
// model proposes.
//
//   hill-climb-edit.mjs apply --root <repo> --plugin <p> --skill <s> --proposal <file>
//   hill-climb-edit.mjs check --plugin <p> --skill <s>      (changed paths on stdin)
//
// apply reads the model's structured output, {file, old_string, new_string},
// where file is relative to plugins/<p>/skills/<s>/, and replaces the one
// occurrence of old_string in that markdown file under --root. It prints the
// changed path. check reads changed paths, one per line, and refuses each one
// outside plugins/<p>/skills/<s>/, under an evals/ directory, git-quoted (a
// leading `"`) or holding a `.` or `..` segment; no path at all is refused as
// no edit. select-plugins.mjs then judges the same paths for what a suite may
// run with the credential.
//
// Refusals go to stderr as `<path>: <reason>`. Exit 0 applied or clean, 1
// refused, 2 usage.
import { lstatSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

const NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

// Why one changed path may not reach the edit's eval pass, or null.
export function pathRefusal(path, plugin, skill) {
  if (path.startsWith('"')) {
    return "a git-quoted path, whose real name is unknown";
  }
  const parts = path.split("/");
  if (parts.some((part) => part === "" || part === "." || part === "..")) {
    return "an empty, . or .. segment";
  }
  const prefix = ["plugins", plugin, "skills", skill];
  if (parts.length <= prefix.length || prefix.some((part, index) => parts[index] !== part)) {
    return `outside plugins/${plugin}/skills/${skill}/`;
  }
  if (parts.includes("evals")) {
    return "under an evals/ directory";
  }
  return null;
}

export function check(paths, plugin, skill) {
  if (paths.length === 0) {
    return ["(none): no edit"];
  }
  return paths.flatMap((path) => {
    const reason = pathRefusal(path, plugin, skill);
    return reason ? [`${path}: ${reason}`] : [];
  });
}

// The repository path the proposal changed; throws with the reason it cannot apply.
export function applyProposal(root, plugin, skill, proposal) {
  const { file, old_string: before, new_string: after } = proposal ?? {};
  if (![file, before, after].every((value) => typeof value === "string") || before === "" || before === after) {
    throw new Error("the proposal needs a file, a non-empty old_string and a different new_string");
  }
  const path = `plugins/${plugin}/skills/${skill}/${file}`;
  const reason = pathRefusal(path, plugin, skill) ?? (path.endsWith(".md") ? null : "not a markdown file");
  if (reason) {
    throw new Error(`${path}: ${reason}`);
  }
  const target = join(root, path);
  if (!lstatSync(target, { throwIfNoEntry: false })?.isFile()) {
    throw new Error(`${path}: not a regular file`);
  }
  const text = readFileSync(target, "utf8");
  const count = text.split(before).length - 1;
  if (count !== 1) {
    throw new Error(`${path}: old_string occurs ${count} times, not once`);
  }
  writeFileSync(target, text.replace(before, () => after));
  return path;
}

export function main(argv = process.argv.slice(2)) {
  const [command, ...rest] = argv;
  let values;
  try {
    ({ values } = parseArgs({
      args: rest,
      options: { root: { type: "string" }, plugin: { type: "string" }, skill: { type: "string" }, proposal: { type: "string" } },
    }));
  } catch {
    values = {};
  }
  const named = NAME.test(values.plugin ?? "") && NAME.test(values.skill ?? "");
  if (!named || !["apply", "check"].includes(command) || (command === "apply" && !(values.root && values.proposal))) {
    console.error("usage: hill-climb-edit.mjs apply --root <repo> --plugin <p> --skill <s> --proposal <file>\n       hill-climb-edit.mjs check --plugin <p> --skill <s>");
    return 2;
  }
  if (command === "check") {
    const refused = check(readFileSync(0, "utf8").split("\n").filter(Boolean), values.plugin, values.skill);
    for (const line of refused) {
      console.error(line);
    }
    return refused.length ? 1 : 0;
  }
  try {
    const proposal = JSON.parse(readFileSync(values.proposal, "utf8"));
    console.log(applyProposal(values.root, values.plugin, values.skill, proposal));
    return 0;
  } catch (error) {
    console.error(`hill-climb-edit: ${error.message}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = main();
}
