#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr.
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check-token-literals.sh [--base <ref>] [--help]

Fails a page source under plugins/ that defines a palette role or a type stack
with its own value instead of taking it from the token layer, lib/html-tokens.css
(ADR 0133, Decision 7). The roles are the properties the token layer's pinned-dark
block sets with var(); the stacks are its light-block properties ending in a CSS
generic font family. A definition passes only as var(--name) of a property the
token layer defines, in a declaration (wrapped or not, in CSS, an inline style
or a JS string or object) or in a style.setProperty call.

Page sources: tracked and untracked .html .htm .css .js .mjs .cjs .jsx .ts .tsx
.svg files under plugins/, skipping evals, tests, fixtures, probes and the
token-layer copies registered in scripts/shared-copies.txt (copies of
lib/html-tokens.css and lib/html-chrome.html).

Pages not yet migrated are listed in scripts/token-literals-allowlist.txt as
'<path> <count>', the count being the page's literal definitions today. A page
over its count fails, naming every definition; a page under it fails as stale
until the count is lowered, so the list only shrinks. With --base <ref>, an
entry that is new or higher than in <ref>'s allowlist fails as growth.
EOF
}

base=""
while (($# > 0)); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --base)
      if (($# < 2)) || [[ -z "$2" ]]; then
        echo "check-token-literals: --base needs a ref" >&2
        exit 2
      fi
      base="$2"
      shift 2
      ;;
    *)
      echo "check-token-literals: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

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

base_list=""
has_base=0
if [[ -n "${base}" ]]; then
  if ! git -C "${REPO_ROOT}" rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
    echo "check-token-literals: --base ${base} names no commit" >&2
    exit 2
  fi
  if git -C "${REPO_ROOT}" cat-file -e "${base}:scripts/token-literals-allowlist.txt" 2>/dev/null; then
    base_list="$(git -C "${REPO_ROOT}" show "${base}:scripts/token-literals-allowlist.txt")" || {
      echo "check-token-literals: git show of the allowlist at ${base} failed" >&2
      exit 2
    }
    has_base=1
  else
    has_base=2
  fi
fi

node --input-type=module - "${REPO_ROOT}" "${has_base}" <<<"${files}" 3<&0 4<<<"${base_list}" <<'NODE'
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
const parseAllowlist = (text, bad) => {
  const entries = new Map();
  for (const line of text.split("\n")) {
    const entry = line.replace(/#.*/, "").trim();
    if (!entry) continue;
    const match = /^([^ \t]+)[ \t]+([1-9][0-9]*)$/.exec(entry);
    if (match) entries.set(match[1], Number(match[2]));
    else bad.push(entry);
  }
  return entries;
};
const badEntries = [];
const allowed = parseAllowlist(existsSync(`${root}/${ALLOWLIST}`) ? read(ALLOWLIST) : "", badEntries);
const baseMode = process.argv[3];
const baseAllowed = baseMode === "1" ? parseAllowlist(readFileSync(4, "utf8"), []) : undefined;

const PAGE = /\.(?:html?|css|[cm]?js|jsx|tsx?|svg)$/;
const NOT_PAGE = /(?:^|\/)(?:evals|tests?|__tests__|fixtures|probes)\/|\.(?:test|spec)\.[^/]+$/;
const sources = readFileSync(3, "utf8")
  .split("\n")
  .filter((p) => p && PAGE.test(p) && !NOT_PAGE.test(p) && !exempt.has(p) && existsSync(`${root}/${p}`));

const names = [...roles, ...stacks].join("|");
const declaration = new RegExp(`(?<![A-Za-z0-9_-])--(${names})(['"]?)[ \\t\\n]*:[ \\t\\n]*`, "g");
const setProperty = new RegExp(`setProperty\\([ \\t\\n]*(['"\`])--(${names})\\1[ \\t\\n]*,[ \\t\\n]*`, "g");
const quotedValue = /(['"`])([^'"`\n]*)\1/y;
const tokenRef = /^var\([ \t]*--([A-Za-z0-9_-]+)[ \t]*\)$/;

// A declaration inside a quoted string or attribute (an inline style, a JS
// string) ends at that quote: the quote left open earlier on its line.
const enclosingQuote = (text, index) => {
  const before = text.slice(text.lastIndexOf("\n", index) + 1, index);
  return ['"', "'", "`"].find((q) => before.split(q).length % 2 === 0) ?? "";
};
const readValue = (text, start, quoted, stops) => {
  if (quoted) {
    quotedValue.lastIndex = start;
    const got = quotedValue.exec(text);
    if (got) return got[2];
  }
  const bare = new RegExp(`[^${stops}]*`, "y");
  bare.lastIndex = start;
  return bare.exec(text)[0];
};

const findings = new Map();
for (const path of sources) {
  const text = read(path);
  const candidates = [];
  for (const match of text.matchAll(declaration)) {
    const [head, name, nameQuote] = match;
    const stops = `;}${nameQuote ? "," : ""}${enclosingQuote(text, match.index)}`;
    candidates.push([match.index, name, readValue(text, match.index + head.length, Boolean(nameQuote), stops)]);
  }
  for (const match of text.matchAll(setProperty)) {
    const [head, , name] = match;
    candidates.push([match.index, name, readValue(text, match.index + head.length, true, ")")]);
  }
  candidates.sort((x, y) => x[0] - y[0]);
  for (const [index, name, raw] of candidates) {
    const value = raw.replace(/[ \t\n]+/g, " ").trim();
    if (defined.has(tokenRef.exec(value)?.[1])) continue;
    const line = text.slice(0, index).split("\n").length;
    const list = findings.get(path) ?? [];
    list.push(`TOKEN LITERAL: ${path}:${line}: --${name}: ${value}`);
    findings.set(path, list);
  }
}

let failed = false;
for (const entry of badEntries) {
  console.error(`BAD ALLOWLIST: ${entry}: want '<path> <count>', the count being the page's literal token definitions today`);
  failed = true;
}
let fresh = false;
for (const [path, lines] of findings) {
  const recorded = allowed.get(path);
  if (recorded !== undefined && lines.length <= recorded) continue;
  for (const line of lines) console.error(line);
  if (recorded !== undefined) {
    console.error(`${path} has ${lines.length} literal token definition(s); the allowlist records ${recorded}. A migrating page may not gain one.`);
  }
  fresh = true;
}
if (fresh) {
  console.error(
    `Take each palette role and type stack from the token layer: drop the definition, or set it to var(--name) of a property ${TOKENS} defines. Consumer branding (ADR 0133) only reaches pages that do.`,
  );
  failed = true;
}
for (const [path, recorded] of allowed) {
  const count = findings.get(path)?.length ?? 0;
  if (count >= recorded) continue;
  console.error(
    `STALE ALLOWLIST: ${path} has ${count} literal token definition(s), the allowlist records ${recorded}; ${count ? `lower its count to ${count}` : "delete its line"} in ${ALLOWLIST}`,
  );
  failed = true;
}
if (baseAllowed) {
  for (const [path, recorded] of allowed) {
    const before = baseAllowed.get(path);
    if (before !== undefined && recorded <= before) continue;
    console.error(
      `ALLOWLIST GROWTH: ${path} ${recorded}: ${before === undefined ? "a new entry" : `up from ${before}`} against the base; take the page's palette and stacks from the token layer instead`,
    );
    failed = true;
  }
}
if (failed) process.exit(1);
console.log(
  `No new literal palette role or type stack in ${sources.length} page source(s); ${allowed.size} allowlisted page(s) still to migrate.${baseMode === "2" ? " No allowlist at the base revision, so growth was not compared." : ""}`,
);
NODE
