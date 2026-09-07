#!/usr/bin/env bash
# Behavioral tests for the shared helpers carried by the loop-closure snippet
# reference, plugins/visualization/reference/html-loop-closure.html.
#
#   bash scripts/check-loop-closure-helpers.test.sh
#
# WHY THIS EXISTS. That asset is a SNIPPET surface: every skill that adopts a
# loop-closure or export pattern copies its helpers verbatim, so a helper that
# silently loses a case is inherited by every copy and caught by nothing. The
# html-assets gate lints the file's MARKUP; markup linting says nothing about
# whether esc still escapes the single quote or whether safeHref still refuses
# a javascript: URL. This suite is the discriminating check on the behavior.
#
# The helpers are extracted from the live asset between the two comment
# markers the file uses to bound them, so this suite tests the shipped text
# rather than a copy. Losing a marker fails the suite loudly.
#
# Exit 0 clean, 1 findings, 2 environment (node missing, markers missing).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || exit 2
ASSET="$REPO_ROOT/plugins/visualization/reference/html-loop-closure.html"

if ! command -v node >/dev/null 2>&1; then
  echo "check-loop-closure-helpers: node not found on PATH" >&2
  exit 2
fi
if [[ ! -f "$ASSET" ]]; then
  echo "check-loop-closure-helpers: asset missing at $ASSET" >&2
  exit 2
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

cat >"$work/driver.mjs" <<'NODE'
import { readFileSync } from "node:fs";

const asset = process.argv[2];
const src = readFileSync(asset, "utf8");

let pass = 0;
let fail = 0;
const ok = (label) => { pass += 1; console.log(`ok: ${label}`); };
const bad = (label) => { fail += 1; console.error(`FAIL: ${label}`); };
const check = (cond, label) => (cond ? ok(label) : bad(label));

// --- extract the helper block from the shipped asset ---------------------
const OPEN = "/* ---- the four shared helpers ---- */";
const CLOSE = "/* ---- pattern snippets, printed into their pre blocks as text ---- */";
const from = src.indexOf(OPEN);
const to = src.indexOf(CLOSE);
if (from === -1 || to === -1 || to <= from) {
  console.error("check-loop-closure-helpers: helper block markers not found in the asset");
  process.exit(2);
}
const helpers = src.slice(from + OPEN.length, to);

// esc, safeHref and safeFilename are pure; copyText and downloadText touch the
// DOM, so they are asserted at source level below rather than executed.
const factory = new Function(`${helpers}\nreturn { esc, safeHref, safeFilename, copyText, downloadText };`);
const { esc, safeHref, safeFilename, copyText, downloadText } = factory();

// --- esc: every character the convention's baseline names ----------------
const escaped = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};
for (const [raw, want] of Object.entries(escaped)) {
  check(esc(raw) === want, `esc escapes ${JSON.stringify(raw)} to ${want}`);
}
check(esc("&lt;") === "&amp;lt;", "esc replaces & first, so an entity is not double-decoded");
check(esc(null) === "null", "esc coerces a non-string rather than throwing");
// The single-quote case is the one an attribute breakout needs: a value
// dropped into a single-quoted attribute must not be able to close it.
check(
  !esc("' onclick='alert(1)").includes("'"),
  "esc leaves no raw single quote that could close a single-quoted attribute",
);
check(
  !esc('" onclick="alert(1)').includes('"'),
  "esc leaves no raw double quote that could close a double-quoted attribute",
);

// --- safeHref: scheme hazards escaping cannot reach ----------------------
const rejected = [
  "javascript:alert(1)",
  "JavaScript:alert(1)",
  "  javascript:alert(1)  ",
  "java\tscript:alert(1)",
  "data:text/html,<script>alert(1)</" + "script>",
  "vbscript:msgbox(1)",
  "file:///etc/passwd",
  "relative/page.html",
];
for (const value of rejected) {
  check(safeHref(value) === "#", `safeHref refuses ${JSON.stringify(value)}`);
}
check(safeHref("#section-2") === "#section-2", "safeHref passes a fragment through");
check(safeHref("https://example.com/x").startsWith("https://"), "safeHref allows https");
check(safeHref("mailto:a@example.com").startsWith("mailto:"), "safeHref allows mailto");
// A rejected scheme must also survive the escape pass without reappearing.
check(esc(safeHref("javascript:alert(1)")) === "#", "a refused URL stays refused after esc");

// --- safeFilename: the download attribute --------------------------------
check(!safeFilename("../../etc/passwd").includes("/"), "safeFilename drops path separators");
// The backslash is written as an escape so this file carries no GNU-only
// regex token for the shell-portability lint to trip over.
const BACKSLASH = String.fromCharCode(92);
check(!safeFilename("a" + BACKSLASH + "b.md").includes(BACKSLASH), "safeFilename drops backslashes");
check(!safeFilename('x" onfocus="y.md').includes('"'), "safeFilename drops quotes");
check(safeFilename("") === "export.txt", "safeFilename falls back when nothing survives");
check(safeFilename("...").startsWith("export"), "safeFilename refuses a leading-dot-only name");
check(safeFilename("review-notes.md") === "review-notes.md", "safeFilename keeps an ordinary name");
check(safeFilename("x".repeat(500)).length <= 100, "safeFilename caps the length");

// --- source-level assertions on the two DOM helpers ----------------------
const copySrc = copyText.toString();
check(copySrc.includes("navigator.clipboard"), "copyText uses the async clipboard write");
check(copySrc.includes("execCommand"), "copyText keeps the execCommand fallback");
check(copySrc.includes("textContent"), "copyText writes its flash with textContent");
check(!copySrc.includes("innerHTML"), "copyText never writes its flash with innerHTML");

const downloadSrc = downloadText.toString();
check(downloadSrc.includes("new Blob("), "downloadText builds a Blob");
check(downloadSrc.includes("createObjectURL"), "downloadText mints an object URL");
check(downloadSrc.includes("revokeObjectURL"), "downloadText revokes the object URL");
check(downloadSrc.includes("safeFilename("), "downloadText sanitizes the download filename");
check(!/data:/.test(downloadSrc), "downloadText builds no data: URL");

// --- self-containment of the whole asset ---------------------------------
check(!/https?:\/\//.test(src), "the asset contains no absolute http(s) URL");
// These patterns spell their character classes out rather than using the
// shorthand escapes, so this file carries no GNU-only regex token for the
// shell-portability lint to trip over.
const lower = src.toLowerCase();
check(!lower.includes("<link"), "the asset links no external stylesheet");
check(!/ src *=/i.test(src), "the asset loads no external resource via src");
check(!lower.includes("@import"), "the asset imports no external stylesheet");
// Handler attributes built from input are what the baseline forbids; the asset
// must wire every control through addEventListener instead.
check(!/ on(click|load|error|focus|input|change) *=/i.test(src), "the asset declares no inline handler attribute");

console.log(`PASS=${pass} FAIL=${fail}`);
process.exit(fail > 0 ? 1 : 0);
NODE

node "$work/driver.mjs" "$ASSET"
status=$?
if ((status != 0)); then
  exit "$status"
fi
echo "PASS: scripts/check-loop-closure-helpers.test.sh"
