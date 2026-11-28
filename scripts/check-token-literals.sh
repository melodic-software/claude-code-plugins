#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr.
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check-token-literals.sh [--help]

Fails a page source under plugins/ that defines a palette role or a type stack
with its own value instead of taking it from the token layer, lib/html-tokens.css
(ADR 0133, Decision 7). The roles are the properties the token layer's pinned-dark
block sets with var(); the stacks are its light-block properties ending in a CSS
generic font family. A definition passes only as var(--name) of a property the
token layer defines.

Page sources: tracked and untracked .html .htm .css .js .mjs .cjs .jsx .ts .tsx
.svg files under plugins/, skipping evals, tests, fixtures, probes and the
token-layer copies registered in scripts/shared-copies.txt (copies of
lib/html-tokens.css and lib/html-chrome.html).

Pages not yet migrated are listed in scripts/token-literals-allowlist.txt; an
entry whose file is gone or no longer has a finding fails, so the list shrinks.
EOF
}

case "${1-}" in
  "") ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "check-token-literals: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "${CHECK_DATA_ROOT:-${SCRIPT_DIR}/..}" && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "check-token-literals: node not found on PATH" >&2
  exit 2
fi
if ! git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "check-token-literals: ${REPO_ROOT} is not a git work tree; the scan lists files with git" >&2
  exit 2
fi
if ! files="$(git -C "${REPO_ROOT}" ls-files -z --cached --others --exclude-standard -- plugins | tr '\0' '\n')"; then
  echo "check-token-literals: git ls-files failed under ${REPO_ROOT}" >&2
  exit 2
fi

node --input-type=module - "${REPO_ROOT}" <<<"${files}" 3<&0 <<'NODE'
import { existsSync, readFileSync } from "node:fs";

const root = process.argv[2];
const die = (message) => {
  console.error(`check-token-literals: ${message}`);
  process.exit(2);
};
process.on("uncaughtException", (error) => die(error.stack ?? String(error)));
const read = (path) => readFileSync(`${root}/${path}`, "utf8").replace(/\r\n?/g, "\n");

const TOKENS = "lib/html-tokens.css";
const COPIES = "scripts/shared-copies.txt";
const ALLOWLIST = "scripts/token-literals-allowlist.txt";
if (!existsSync(`${root}/${TOKENS}`)) die(`token layer ${TOKENS} not found`);
if (!existsSync(`${root}/${COPIES}`)) die(`${COPIES} not found`);

const tokens = read(TOKENS).replace(/\/\*.*?\*\//gs, "");
const declarations = (body) =>
  [...(body ?? "").matchAll(/--([A-Za-z0-9_-]+)[ \t]*:[ \t]*([^;]*);/g)].map(([, name, value]) => [name, value.trim()]);
const lightBody = /(?:^|\n):root[ \t]*\{([^}]*)\}/.exec(tokens)?.[1];
const darkBody = /:root\[data-theme=dark\][ \t]*\{([^}]*)\}/.exec(tokens)?.[1];
const GENERIC =
  /(?:^|,)[ \t]*(?:serif|sans-serif|monospace|cursive|fantasy|system-ui|ui-serif|ui-sans-serif|ui-monospace|ui-rounded|math|emoji|fangsong)[ \t]*$/;
const roles = declarations(darkBody).filter(([, v]) => /^var\(--[A-Za-z0-9_-]+\)$/.test(v)).map(([n]) => n);
const stacks = declarations(lightBody).filter(([, v]) => GENERIC.test(v)).map(([n]) => n);
if (roles.length === 0) die(`${TOKENS} names no palette role (no var() property in its :root[data-theme=dark] block)`);
if (stacks.length === 0) die(`${TOKENS} names no type stack (no light :root property ending in a generic font family)`);
const defined = new Set(declarations(tokens).map(([n]) => n));

const exempt = new Set(
  read(COPIES)
    .split("\n")
    .map((line) => line.replace(/#.*/, "").trim().split(/[ \t]+/))
    .filter(([canonical, copy]) => copy && (canonical === TOKENS || canonical === "lib/html-chrome.html"))
    .map(([, copy]) => copy),
);
const allowed = existsSync(`${root}/${ALLOWLIST}`)
  ? read(ALLOWLIST)
      .split("\n")
      .map((line) => line.replace(/#.*/, "").trim())
      .filter(Boolean)
  : [];

const PAGE = /\.(?:html?|css|[cm]?js|jsx|tsx?|svg)$/;
const NOT_PAGE = /(?:^|\/)(?:evals|tests?|__tests__|fixtures|probes)\/|\.(?:test|spec)\.[^/]+$/;
const sources = readFileSync(3, "utf8")
  .split("\n")
  .filter((p) => p && PAGE.test(p) && !NOT_PAGE.test(p) && !exempt.has(p) && existsSync(`${root}/${p}`));

const definition = new RegExp(`(?<![A-Za-z0-9_-])--(${[...roles, ...stacks].join("|")})['"]?[ \\t]*:[ \\t]*([^;}\\n]*)`, "g");
const tokenRef = /^var\([ \t]*--([A-Za-z0-9_-]+)[ \t]*\)$/;

const findings = new Map();
for (const path of sources) {
  read(path)
    .split("\n")
    .forEach((line, index) => {
      for (const [, name, raw] of line.matchAll(definition)) {
        const value = raw.trim().replace(/^['"]|['"],?$/g, "").trim();
        if (defined.has(tokenRef.exec(value)?.[1])) continue;
        const list = findings.get(path) ?? [];
        list.push(`TOKEN LITERAL: ${path}:${index + 1}: --${name}: ${value}`);
        findings.set(path, list);
      }
    });
}

let failed = false;
for (const [path, lines] of findings) {
  if (allowed.includes(path)) continue;
  for (const line of lines) console.error(line);
  failed = true;
}
if (failed) {
  console.error(
    `Take each palette role and type stack from the token layer: drop the definition, or set it to var(--name) of a property ${TOKENS} defines. Consumer branding (ADR 0133) only reaches pages that do.`,
  );
}
for (const path of allowed) {
  if (findings.has(path)) continue;
  console.error(`STALE ALLOWLIST: ${path} has no literal palette or type token left, or is gone; delete its line from ${ALLOWLIST}`);
  failed = true;
}
if (failed) process.exit(1);
console.log(
  `No literal palette role or type stack in ${sources.length} page source(s); ${allowed.length} allowlisted page(s) still to migrate.`,
);
NODE
