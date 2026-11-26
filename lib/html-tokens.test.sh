#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 environment (node missing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "html-tokens: node not found on PATH" >&2
  exit 2
fi

node --input-type=module - "$REPO_ROOT" <<'NODE'
import { readFileSync } from "node:fs";

const root = process.argv[2];
const read = (path) => readFileSync(`${root}/${path}`, "utf8").replace(/\r\n?/g, "\n");
const tokens = read("lib/html-tokens.css");
const chrome = read("lib/html-chrome.html");

let failed = 0;
const check = (name, cond, detail) => {
  if (cond) {
    console.log(`ok: ${name}`);
  } else {
    console.error(`FAIL: ${name}${detail === undefined ? "" : ` - ${detail}`}`);
    failed += 1;
  }
};
const flat = (text) => text.replace(/^[ \t]+/gm, "");

const rules = tokens.replace(/^\/\*.*?\*\/\n/s, "");
check("the token file opens with one header comment and then holds rules", rules !== tokens && !rules.includes("/*"));

const style = /<style>\n(.*?)<\/style>/s.exec(chrome)?.[1];
check("the chrome has one style element", style !== undefined && (chrome.match(/<style>/g) ?? []).length === 1);
check(
  "the chrome's style element opens with the token rules, leading whitespace aside",
  style !== undefined && flat(style).startsWith(flat(rules)),
  "copy lib/html-tokens.css's rules into lib/html-chrome.html, then rerun scripts/sync-shared-copies.sh",
);

const block = (re) => re.exec(rules)?.[1];
const schemes = {
  light: block(/^:root \{([^}]*)\}/m),
  "system dark": block(/@media \(prefers-color-scheme: dark\) \{[ \t\n]*:root:not\(\[data-theme=light\]\) \{([^}]*)\}/),
  "pinned dark": block(/^:root\[data-theme=dark\] \{([^}]*)\}/m),
};
const hex = /^#[0-9A-Fa-f]{6}$/;
const defined = (body, name) => new RegExp(`(?:^|\\n)[ \\t]*--${name}:[ \\t]*([^;]+);`).exec(body ?? "")?.[1];
const resolve = (name) => {
  let value = defined(schemes.light, name);
  for (let hops = 0; value?.startsWith("var(--") && hops < 5; hops += 1) {
    value = defined(schemes.light, value.slice(6, -1));
  }
  return value;
};
for (const [scheme, body] of Object.entries(schemes)) {
  check(`the ${scheme} block exists`, body !== undefined);
  check(
    `the ${scheme} block sets color-scheme`,
    new RegExp(`color-scheme:[ \\t]*${scheme === "light" ? "light" : "dark"};`).test(body ?? ""),
  );
  for (const role of ["bg", "fg", "panel", "muted", "accent", "link", "focus"]) {
    const value = defined(body, role);
    const shipped = value?.startsWith("var(--") ? resolve(value.slice(6, -1)) : value;
    check(`the ${scheme} block gives --${role} a six-digit hex value`, hex.test(shipped ?? ""), value);
  }
}
for (const stack of ["serif", "sans", "mono"]) {
  check(`the light block defines the --${stack} stack`, /[^ \t]/.test(defined(schemes.light, stack) ?? ""));
}

if (failed) {
  console.error(`${failed} check(s) failed`);
  process.exit(1);
}
console.log("all html-tokens checks passed");
NODE
