#!/usr/bin/env node
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { RULES_PATH } from "./apply-patch.mjs";
import { PATH_RULES, segments } from "./protected-paths.mjs";

export const PATTERNS = {
  "github-workflows": () => ["/.github/workflows/**"],
  codeowners: () => ["/CODEOWNERS", "/.github/CODEOWNERS", "/docs/CODEOWNERS"],
  gitmodules: () => [".gitmodules"],
  settings: (dirs) =>
    ["", ...dirs].filter((dir) => PATH_RULES.settings(segments(`${dir}/settings.json`))).map((dir) => (dir ? `/${dir}/**/settings*.json` : "/settings*.json")),
  "lane-grants": () => ["/.github/actions/resolve-config/lane-grants.json", "/.github/standards/trusted-actors/trusted-actors.json"],
  "claude-protected": () => [],
};

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
