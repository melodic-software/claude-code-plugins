// Moves package.json's install-script approval for @anthropic-ai/claude-code
// (`allowScripts`, one exact version) to the version package-lock.json
// installs, so a Dependabot bump of the CLI keeps its postinstall. It writes
// that version only when it is also the exact version package.json pins,
// since the push rule (dependency-classify.mjs installScriptPinRefusal, under
// patch-rules.json's install-script-pin row) checks the pin against the
// manifest's version as Dependabot set it, not the lockfile. It runs no head
// code: the manifest and lockfile are data. review-dependency.mjs select
// writes its patch, which apply-dependency-pin pushes. `check` exits 1 when
// the pin and the lockfile disagree, for pr-require-checks.yml.
//
//   node install-script-pin.mjs check [dir]

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { INSTALL_SCRIPT_PINS, installScriptPinRefusal } from "./dependency-classify.mjs";

export const PACKAGE = INSTALL_SCRIPT_PINS[0];

const parse = (text) => {
  try {
    const value = JSON.parse(String(text));
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
};

// The version package-lock.json installs at the top level, or null.
export function lockedVersion(lockText, name = PACKAGE) {
  const version = parse(lockText)?.packages?.[`node_modules/${name}`]?.version;
  return typeof version === "string" ? version : null;
}

// { text, from, to } with the pin renamed in place, so key order, indent and
// the rest of the file keep their bytes; null when there is nothing to move:
// no pin for the package, the pin already names the locked version, or no
// locked version. A pin it cannot move as exactly one key throws.
export function movePin(packageText, lockText, name = PACKAGE) {
  const manifest = parse(packageText);
  if (!manifest) throw new Error("package.json is not a JSON object");
  const scripts = manifest.allowScripts;
  const keys = scripts && typeof scripts === "object" ? Object.keys(scripts).filter((key) => key.startsWith(`${name}@`)) : [];
  if (keys.length === 0) return null;
  if (keys.length > 1) throw new Error(`allowScripts holds ${keys.length} ${name} pins`);
  const to = lockedVersion(lockText, name);
  const [from] = keys;
  if (to === null || from === `${name}@${to}`) return null;
  const literal = JSON.stringify(from);
  const at = packageText.indexOf(literal);
  if (at < 0 || packageText.indexOf(literal, at + 1) >= 0) throw new Error(`${literal} does not appear exactly once in package.json`);
  const text = `${packageText.slice(0, at)}${JSON.stringify(`${name}@${to}`)}${packageText.slice(at + literal.length)}`;
  const refusal = installScriptPinRefusal(packageText, text);
  if (refusal) throw new Error(`the moved pin is refused: ${refusal}`);
  return { text, from: from.slice(name.length + 1), to };
}

// A git unified diff of `path` from `before` to `after`, with three lines of
// context per hunk; both texts end with a newline.
export function unifiedDiff(path, before, after) {
  if (!before.endsWith("\n") || !after.endsWith("\n")) throw new Error(`${path} does not end with a newline`);
  const a = before.slice(0, -1).split("\n");
  const b = after.slice(0, -1).split("\n");
  if (a.length !== b.length) throw new Error("the edit changes the line count");
  const changed = a.flatMap((line, i) => (line === b[i] ? [] : [i]));
  if (changed.length === 0) return "";
  const lines = [`diff --git a/${path} b/${path}`, `--- a/${path}`, `+++ b/${path}`];
  let i = 0;
  while (i < changed.length) {
    const start = Math.max(0, changed[i] - 3);
    let end = Math.min(a.length, changed[i] + 4);
    let j = i + 1;
    while (j < changed.length && changed[j] - 3 <= end) {
      end = Math.min(a.length, changed[j] + 4);
      j += 1;
    }
    const count = end - start;
    lines.push(`@@ -${start + 1},${count} +${start + 1},${count} @@`);
    for (let k = start; k < end; k += 1) {
      if (a[k] === b[k]) lines.push(` ${a[k]}`);
      else lines.push(`-${a[k]}`, `+${b[k]}`);
    }
    i = j;
  }
  return `${lines.join("\n")}\n`;
}

export function main(argv, { log = (line) => console.log(line) } = {}) {
  if (argv[0] !== "check") throw new Error("usage: install-script-pin.mjs check [dir]");
  const dir = argv[1] ?? ".";
  const moved = movePin(readFileSync(join(dir, "package.json"), "utf8"), readFileSync(join(dir, "package-lock.json"), "utf8"));
  if (moved) {
    log(`::error file=package.json::allowScripts approves ${PACKAGE}@${moved.from}, but package-lock.json installs ${moved.to}; npm ci skips the CLI's install script until the pin names ${PACKAGE}@${moved.to}`);
    return 1;
  }
  log(`${PACKAGE}: the allowScripts pin matches package-lock.json`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    console.log(`::error::install-script-pin failed: ${error.message}`);
    process.exitCode = 1;
  }
}
