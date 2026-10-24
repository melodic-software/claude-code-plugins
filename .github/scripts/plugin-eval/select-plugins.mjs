#!/usr/bin/env node
// select-plugins.mjs: the plugins whose eval suite a pull request's changes
// call for. Reads changed paths, one per line, on stdin and prints each
// plugin directory (`plugins/<name>`) that has a changed file under its
// skills/, agents/ or evals/, sorted, one per line. Prints nothing when none
// does.
//
// A selected plugin's suite runs with the pull request's own plugin loaded
// under --trust-plugin, so a change to what runs when the plugin loads, its
// hooks, manifest or server config, would run with the eval's credential.
// When a selected plugin has such a change, the paths go to stderr and the
// exit is 1. Exit 0 otherwise.
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

const SUITE_PATH = /^plugins\/([A-Za-z0-9._-]+)\/(?:skills|agents|evals)\//;
const LOAD_TIME_PATH = /^plugins\/([A-Za-z0-9._-]+)\/(?:hooks\/|\.claude-plugin\/|\.mcp\.json$|\.lsp\.json$|settings\.json$|monitors\/)/;

export const selectPlugins = (paths) =>
  [...new Set(paths.map((path) => SUITE_PATH.exec(path.trim())?.[1]).filter((name) => name && !name.startsWith(".")))]
    .sort()
    .map((name) => `plugins/${name}`);

export const loadTimeChanges = (paths, plugins) =>
  paths.map((path) => path.trim()).filter((path) => plugins.includes(`plugins/${LOAD_TIME_PATH.exec(path)?.[1]}`));

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const paths = readFileSync(0, "utf8").split("\n").filter((path) => path.trim());
  const selected = selectPlugins(paths);
  const refused = loadTimeChanges(paths, selected);
  if (refused.length) {
    console.error(`a selected plugin changes what runs when it loads: ${refused.join(", ")}`);
    process.exitCode = 1;
  } else if (selected.length) {
    console.log(selected.join("\n"));
  }
}
