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

export function lockedVersion(lockText, name = PACKAGE) {
  const version = parse(lockText)?.packages?.[`node_modules/${name}`]?.version;
  return typeof version === "string" ? version : null;
}

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

function editScript(a, b) {
  const width = b.length + 1;
  const common = new Uint32Array((a.length + 1) * width);
  for (let i = a.length - 1; i >= 0; i -= 1) {
    for (let j = b.length - 1; j >= 0; j -= 1) {
      common[i * width + j] = a[i] === b[j] ? common[(i + 1) * width + j + 1] + 1 : Math.max(common[(i + 1) * width + j], common[i * width + j + 1]);
    }
  }
  const ops = [];
  let i = 0;
  let j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] === b[j]) {
      ops.push([" ", a[i]]);
      i += 1;
      j += 1;
    } else if (i < a.length && (j === b.length || common[(i + 1) * width + j] >= common[i * width + j + 1])) {
      ops.push(["-", a[i]]);
      i += 1;
    } else {
      ops.push(["+", b[j]]);
      j += 1;
    }
  }
  return ops;
}

export function unifiedDiff(path, before, after) {
  if (!before.endsWith("\n") || !after.endsWith("\n")) throw new Error(`${path} does not end with a newline`);
  const ops = editScript(before.slice(0, -1).split("\n"), after.slice(0, -1).split("\n"));
  const changed = ops.flatMap(([kind], i) => (kind === " " ? [] : [i]));
  if (changed.length === 0) return "";
  const at = [];
  let old = 1;
  let now = 1;
  for (const [kind] of ops) {
    at.push([old, now]);
    if (kind !== "+") old += 1;
    if (kind !== "-") now += 1;
  }
  const lines = [`diff --git a/${path} b/${path}`, `--- a/${path}`, `+++ b/${path}`];
  let i = 0;
  while (i < changed.length) {
    const start = Math.max(0, changed[i] - 3);
    let end = Math.min(ops.length, changed[i] + 4);
    let j = i + 1;
    while (j < changed.length && changed[j] - 3 <= end) {
      end = Math.min(ops.length, changed[j] + 4);
      j += 1;
    }
    const hunk = ops.slice(start, end);
    const oldCount = hunk.filter(([kind]) => kind !== "+").length;
    const newCount = hunk.filter(([kind]) => kind !== "-").length;
    lines.push(`@@ -${at[start][0] - (oldCount ? 0 : 1)},${oldCount} +${at[start][1] - (newCount ? 0 : 1)},${newCount} @@`);
    for (const [kind, line] of hunk) lines.push(`${kind}${line}`);
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
