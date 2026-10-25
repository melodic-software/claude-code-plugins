#!/usr/bin/env node
// select-plugins.mjs: the plugins whose eval suite a pull request's changes
// call for.
//
//   select-plugins.mjs [--repo <dir> --base <ref> --head <ref>]
//
// Reads changed paths, one per line, on stdin and prints each plugin
// directory (`plugins/<name>`) that has a changed file under its skills/,
// agents/ or evals/, sorted, one per line. Prints nothing when none does.
//
// A selected plugin's suite runs with the pull request's own plugin loaded
// under --trust-plugin and the eval's credential in the environment, so only
// changes known not to add code that runs are let through, an allowlist:
//
// - every changed path of a selected plugin sits under skills/, agents/ or
//   evals/;
// - every changed path under skills/ or agents/ is markdown, since a script
//   there can be called by an unchanged hook, server or skill;
// - a changed markdown file under skills/ or agents/ keeps, between --base
//   and --head in the git repository --repo, every frontmatter key outside
//   SAFE_KEYS (hooks, allowed-tools, shell and the rest), in a frontmatter
//   shape frontmatter() can read and with no YAML alias in those keys, and
//   adds or changes no `!` shell-preprocessing line. Without --repo it cannot be read, so it
//   is refused;
// - no path is one git quoted (a leading `"`), whose real name is unknown.
//
// When a path breaks a rule, `<path>: <reason>` lines go to stderr
// and the exit is 1. Exit 0 otherwise.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import process from "node:process";
import { parseArgs } from "node:util";
import { pathToFileURL } from "node:url";

const SUITE_PATH = /^plugins\/([A-Za-z0-9._-]+)\/(?:skills|agents|evals)\//;
const PLUGIN_PATH = /^plugins\/([A-Za-z0-9._-]+)\/(.*)$/;
const PROSE_PATH = /^(?:skills|agents)\//;

// Frontmatter keys that only describe or route a skill or agent. A change to
// any other key is refused.
export const SAFE_KEYS = new Set([
  "argument-hint",
  "color",
  "description",
  "disable-model-invocation",
  "effort",
  "maxTurns",
  "metadata",
  "model",
  "name",
  "user-invocable",
  "when_to_use",
]);

// A line that runs a shell command when the skill loads: inline !`cmd`, or a
// ```! fenced block.
const PREPROCESS = /!`|^\s*```!/;

export const selectPlugins = (paths) =>
  [...new Set(paths.map((path) => SUITE_PATH.exec(path)?.[1]).filter((name) => name && !name.startsWith(".")))]
    .sort()
    .map((name) => `plugins/${name}`);

const FENCE = /^---[ \t]*$/;
const KEY_LINE = /^([A-Za-z_][A-Za-z0-9_-]*)[ \t]*:(?:[ \t]|$)/;
// A YAML alias (*name) starting a value, list item or flow entry can pull in
// an anchor set under another key.
const ALIAS = /(?:^|[:[{,]|^[ \t]*-)[ \t]*\*[A-Za-z0-9_]/m;

// Top-level frontmatter entries as key -> text (the key line and its
// continuation lines); text with no frontmatter has none. Only a plain shape
// every YAML reader agrees on is read: `---` on the first line, a closing
// `---`, each entry a `key:` at column 0 with indented, blank or comment
// continuation lines. Anything else (an indented block, a `? key`, a flow
// mapping, a quoted or repeated key, frontmatter after a blank line) returns
// null, which refuses the file.
export function frontmatter(text) {
  const lines = String(text ?? "")
    .replace(/^﻿/, "")
    .split(/\r?\n/);
  const entries = new Map();
  const first = lines.findIndex((line) => line.trim() !== "");
  if (first === -1 || !lines[first].trimStart().startsWith("---")) {
    return entries;
  }
  if (first !== 0 || !FENCE.test(lines[0])) {
    return null;
  }
  let key = null;
  for (const line of lines.slice(1)) {
    if (FENCE.test(line)) {
      return entries;
    }
    const top = KEY_LINE.exec(line);
    if (top) {
      if (entries.has(top[1])) {
        return null;
      }
      key = top[1];
      entries.set(key, line);
    } else if (key !== null && (/^[ \t]/.test(line) || /^\s*(?:#.*)?$/.test(line))) {
      entries.set(key, `${entries.get(key)}\n${line}`);
    } else if (!/^\s*(?:#.*)?$/.test(line)) {
      return null;
    }
  }
  return null;
}

const preprocessLines = (text) =>
  new Set(
    String(text ?? "")
      .split(/\r?\n/)
      .filter((line) => PREPROCESS.test(line)),
  );

// Why a changed markdown file is refused, or null. `head` is null when the
// file is deleted; `base` is null when it is new.
export function proseRefusal(base, head) {
  if (head === null) {
    return null;
  }
  const after = frontmatter(head);
  if (after === null) {
    return "has frontmatter in a shape that cannot be checked";
  }
  const before = frontmatter(base) ?? new Map();
  const keys = [...new Set([...before.keys(), ...after.keys()])].filter((key) => !SAFE_KEYS.has(key));
  const changed = keys.filter((key) => before.get(key) !== after.get(key));
  if (changed.length) {
    return `changes frontmatter ${changed.join(", ")}`;
  }
  const aliased = keys.filter((key) => ALIAS.test(after.get(key)?.slice(key.length + 1) ?? ""));
  if (aliased.length) {
    return `uses a YAML alias in frontmatter ${aliased.join(", ")}`;
  }
  const known = preprocessLines(base);
  if ([...preprocessLines(head)].some((line) => !known.has(line))) {
    return "adds or changes a ! shell-preprocessing line";
  }
  return null;
}

// `<path>: <reason>` for each changed path of a selected plugin that breaks a
// rule. read(side, path) returns the file text at "base" or "head", null when
// absent there, or undefined when nothing can be read.
export function refusals(paths, plugins, read = () => undefined) {
  const out = [];
  for (const path of paths) {
    if (path.startsWith('"')) {
      out.push(`${path}: a quoted path cannot be checked`);
      continue;
    }
    const match = PLUGIN_PATH.exec(path);
    if (!match || !plugins.includes(`plugins/${match[1]}`)) {
      continue;
    }
    const rest = match[2];
    if (!SUITE_PATH.test(path)) {
      out.push(`${path}: outside skills/, agents/ and evals/`);
    } else if (PROSE_PATH.test(rest)) {
      if (!rest.endsWith(".md")) {
        out.push(`${path}: not markdown`);
        continue;
      }
      const head = read("head", path);
      const base = read("base", path);
      if (head === undefined || base === undefined) {
        out.push(`${path}: cannot be read to inspect`);
        continue;
      }
      const reason = proseRefusal(base, head);
      if (reason) {
        out.push(`${path}: ${reason}`);
      }
    }
  }
  return out;
}

// A ref git cannot resolve would read every file as absent, so it throws.
const gitReader = (repo, refs) => {
  for (const ref of Object.values(refs)) {
    execFileSync("git", ["-C", repo, "rev-parse", "--verify", "--quiet", `${ref}^{commit}`], { stdio: "ignore" });
  }
  return (side, path) => gitShow(repo, refs[side], path);
};

const gitShow = (repo, ref, path) => {
  try {
    return execFileSync("git", ["-C", repo, "show", `${ref}:${path}`], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch {
    return null;
  }
};

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const { values } = parseArgs({ options: { repo: { type: "string" }, base: { type: "string" }, head: { type: "string" } } });
  const read = values.repo && values.base && values.head ? gitReader(values.repo, { base: values.base, head: values.head }) : undefined;
  const paths = readFileSync(0, "utf8").split("\n").filter(Boolean);
  const selected = selectPlugins(paths);
  const refused = refusals(paths, selected, read);
  if (refused.length) {
    console.error(`a selected plugin changes more than its suite may run with the credential:\n${refused.join("\n")}`);
    process.exitCode = 1;
  } else if (selected.length) {
    console.log(selected.join("\n"));
  }
}
