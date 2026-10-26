#!/usr/bin/env node
// deny-rules.mjs: the Edit deny rules that keep a lane's model off the paths
// apply-patch refuses, built from apply-patch's PATH_RULES for the refusals
// one patch-rules.json row names. collect-base-activity passes them to the
// issue lane's model, so a run whose change needs such a path is denied at
// its first write and stops, where it would otherwise finish and be refused at
// the push. apply-patch still refuses every path itself.
//
//   node deny-rules.mjs <base-dir> <row>
//
// prints one rule per line, read from <base-dir>'s patch-rules.json and its
// top-level directories.

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { PATH_RULES, RULES_PATH, segments } from "./apply-patch.mjs";

// Each path rule's Edit patterns, anchored at the checkout: a leading `/` in a
// CLI rule anchors at the primary working directory
// (https://code.claude.com/docs/en/permissions#where-a-pattern-anchors), and a
// bare name matches at any depth. A pattern matches only paths its rule
// refuses, so the model never loses an edit apply-patch would take; it may
// match fewer, which apply-patch still refuses at the push. `dirs` are the
// base's top-level directories.
export const PATTERNS = {
  "github-workflows": () => ["/.github/workflows/**"],
  codeowners: () => ["/CODEOWNERS", "/.github/CODEOWNERS", "/docs/CODEOWNERS"],
  gitmodules: () => [".gitmodules"],
  // One pattern for the root and each top-level directory the rule refuses a
  // settings file in, so the rule's own exceptions decide which.
  settings: (dirs) =>
    ["", ...dirs].filter((dir) => PATH_RULES.settings(segments(`${dir}/settings.json`))).map((dir) => (dir ? `/${dir}/**/settings*.json` : "/settings*.json")),
};

// The Edit rules for the path rules `refuse` names; its other refusals
// (symlink, backslash and the like) are not paths a rule can name.
export function denyRules(refuse, dirs) {
  return refuse
    .filter((name) => Object.hasOwn(PATH_RULES, name))
    .flatMap((name) => {
      if (!Object.hasOwn(PATTERNS, name)) {
        throw new Error(`the path rule ${name} has no deny patterns`);
      }
      return PATTERNS[name](dirs);
    })
    .map((pattern) => `Edit(${pattern})`);
}

export function main([baseDir, rowName], { log = console.log } = {}) {
  const row = JSON.parse(readFileSync(join(baseDir, RULES_PATH), "utf8"))[rowName];
  if (!Array.isArray(row?.refuse)) {
    throw new Error(`patch-rules.json has no ${rowName} row with a refuse list`);
  }
  const dirs = readdirSync(baseDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name !== ".git")
    .map((entry) => entry.name)
    .toSorted();
  const unsafe = dirs.find((dir) => !/^[A-Za-z0-9._-]+$/.test(dir));
  if (unsafe !== undefined) {
    throw new Error(`the top-level directory ${JSON.stringify(unsafe)} has a name a rule cannot carry`);
  }
  for (const rule of denyRules(row.refuse, dirs)) log(rule);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2));
}
