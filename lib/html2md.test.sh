#!/usr/bin/env bash
# Self-contained tests for lib/html2md.py (no external test lib; the copies ship with the plugins).
#
# Converts the committed fixture lib/html2md-fixture/page.html and a few inline
# pages, and checks the markdown against values written by hand from those inputs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/html2md.py"
FIXTURE="$SCRIPT_DIR/html2md-fixture/page.html"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
assert_contains() {
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "missing [$2]"; fi
}
assert_absent() {
  if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1" "unexpected [$2]"; fi
}

# Python 3 the way lib/session-bridge/view-bridge.sh finds it: python3, then python,
# each accepted only when it runs and reports major version 3 (the Windows Store
# alias stub fails this probe).
PY=""
for name in python3 python; do
  candidate=$(command -v "$name" 2>/dev/null) || continue
  if [[ "$("$candidate" -c 'import sys; print(sys.version_info[0])' 2>/dev/null)" == 3 ]]; then
    PY="$candidate"
    break
  fi
done
if [[ -z "$PY" ]]; then
  echo "SKIP: html2md.py tests (no python3 or python on PATH runs Python 3)"
  exit 0
fi

conv() { PYTHONUTF8=1 "$PY" "$SCRIPT" "$@"; }

# --- Case: the fixture page ---
out_file="$TEST_TMPDIR/page.md"
conv "$FIXTURE" >"$out_file"
assert_eq "fixture: converter exits 0" 0 "$?"
md="$(cat "$out_file")"

assert_eq "fixture: H1 outside <main> leads the output" "# Widget configuration" "$(head -n 1 "$out_file")"
assert_eq "fixture: exactly one H1" 1 "$(grep -c '^# ' "$out_file")"
assert_contains "fixture: H2 survives a permalink block inside the heading" $'\n## Install\n' "$md"
assert_contains "fixture: second H2" $'\n## Options\n' "$md"
assert_contains "fixture: H3" $'\n### Environment variables\n' "$md"

assert_contains "fixture: fenced code keeps language and lines" \
  $'```bash\nnpm install widget\nwidget --init --dir ./config\n```' "$md"

assert_contains "fixture: table header row" "| Name | Default | Description |" "$md"
assert_contains "fixture: table separator row" "| --- | --- | --- |" "$md"
assert_contains "fixture: table body row with inline code" \
  "| \`timeout\` | 30 | Seconds before a request is abandoned. |" "$md"
assert_contains "fixture: pipe inside a cell is escaped" 'Either strict \| lenient.' "$md"

assert_contains "fixture: absolute link keeps its URL" \
  "[settings file](https://example.com/docs/settings-file)" "$md"
assert_contains "fixture: relative link keeps its URL" "[CLI reference](/docs/cli#flags)" "$md"
assert_contains "fixture: list item with inline code" "- \`WIDGET_HOME\` overrides the settings directory." "$md"

assert_absent "fixture: footer dropped" "Copyright" "$md"
assert_absent "fixture: script dropped" "analytics" "$md"
assert_absent "fixture: nav dropped" "[Home]" "$md"
assert_absent "fixture: page title suffix not emitted when an H1 exists" "Example Docs" "$md"

assert_eq "fixture: no carriage return in output" 0 "$(tr -cd '\r' <"$out_file" | wc -c | tr -d ' ')"
last_two="$(tail -c 2 "$out_file" | od -An -tx1 | tr -d ' \n')"
if [[ "$last_two" == *0a && "$last_two" != 0a0a ]]; then
  pass "fixture: output ends with exactly one newline"
else
  fail "fixture: output ends with exactly one newline" "last bytes [$last_two]"
fi

# --- Case: stdin gives the same bytes as a file argument ---
assert_eq "cli: stdin and file argument agree" "$(cksum <"$out_file")" "$(conv <"$FIXTURE" | cksum)"

# --- Case: CRLF input still yields LF-only output ---
sed 's/$/\r/' "$FIXTURE" >"$TEST_TMPDIR/crlf.html"
conv "$TEST_TMPDIR/crlf.html" >"$TEST_TMPDIR/crlf.md"
assert_eq "cli: CRLF input converts to the same bytes" "$(cksum <"$out_file")" "$(cksum <"$TEST_TMPDIR/crlf.md")"

# --- Case: no H1 anywhere, so <title> becomes the H1 ---
title_md="$(printf '%s' '<html><head><title>Release notes</title></head><body><main><h2>Fixes</h2><p>Body text.</p></main></body></html>' | conv)"
assert_eq "title: <title> is the H1 when the page has none" "# Release notes" "$(head -n 1 <<<"$title_md")"
assert_contains "title: body still follows" $'## Fixes\n\nBody text.' "$title_md"

# --- Case: a '# ' comment line inside fenced code is not mistaken for an H1 ---
comment_md="$(printf '%s' '<html><head><title>Setup guide</title></head><body><main><pre><code class="language-bash"># install deps
npm i</code></pre></main></body></html>' | conv)"
assert_eq "title: code comment does not suppress the title H1" "# Setup guide" "$(head -n 1 <<<"$comment_md")"

# --- Case: an H1 inside <main> is not doubled by the title ---
inner_md="$(printf '%s' '<html><head><title>Guide - Site</title></head><body><main><h1>Guide</h1><p>Text.</p></main></body></html>' | conv)"
assert_eq "title: H1 inside <main> is the only H1" "# Guide" "$(grep '^# ' <<<"$inner_md")"

# --- Case: a heading's own trailing '#' is text; permalink anchors are not ---
head_md="$(printf '%s' '<html><body><main><h1>Doc</h1><h2>Using C#</h2><h2>Setup <a href="#setup">#</a></h2><h2>Usage <a class="headerlink" href="#usage">¶</a></h2><h3>Notes ¶</h3><p>End.</p></main></body></html>' | conv)"
assert_contains "heading: a trailing '#' in the heading text is kept" $'\n## Using C#\n' "$head_md"
assert_contains "heading: a '#' permalink anchor is dropped" $'\n## Setup\n' "$head_md"
assert_contains "heading: a pilcrow permalink anchor is dropped" $'\n## Usage\n' "$head_md"
assert_contains "heading: a standalone trailing pilcrow is dropped" $'\n### Notes\n' "$head_md"

# --- Case: an in-page anchor that wraps the heading text keeps it (mdBook, VuePress) ---
wrap_md="$(printf '%s' '<html><body><main><h1 id="b"><a class="header" href="#b">The Book</a></h1><h2 id="s"><a class="header" href="#s">Setup</a></h2><h2 id="u"><a class="header-anchor" href="#u"><span>Usage</span></a></h2><h2>See <a href="#i">Install</a> now</h2><p>End.</p></main></body></html>' | conv)"
assert_eq "heading: an anchor wrapping the H1 text keeps it" "# The Book" "$(head -n 1 <<<"$wrap_md")"
assert_contains "heading: an anchor wrapping the H2 text keeps it" $'\n## Setup\n' "$wrap_md"
assert_contains "heading: an anchor wrapping a span keeps its text" $'\n## Usage\n' "$wrap_md"
assert_contains "heading: an in-page link inside the heading keeps its text" $'\n## See Install now\n' "$wrap_md"

# --- Case: text hidden from sight or from screen readers inside a heading is dropped ---
hid_md="$(printf '%s' '<html><body><main><h1>Doc</h1><h2 id="x">Install<a class="anchor" href="#x"><span class="sr-only">Permalink to this heading</span></a></h2><h2>Deploy<span aria-hidden="true">#</span></h2><h2 id="y"><a href="#y">Build<span class="visually-hidden"><span>(</span>anchor)</span></a> steps</h2><h2>Run<span class="screen-reader-text"> section</span></h2><p>End.</p></main></body></html>' | conv)"
assert_contains "heading: screen-reader-only text in a permalink anchor is dropped" $'\n## Install\n' "$hid_md"
assert_contains "heading: an aria-hidden glyph span is dropped" $'\n## Deploy\n' "$hid_md"
assert_contains "heading: visually-hidden text is dropped to its own end tag, nested spans included" $'\n## Build steps\n' "$hid_md"
assert_contains "heading: screen-reader-text is dropped" $'\n## Run\n' "$hid_md"
void_md="$(printf '%s' '<html><body><main><h1>Doc</h1><h2><img aria-hidden="true" src="i.svg">Quick start</h2><p>End.</p></main></body></html>' | conv)"
assert_contains "heading: an aria-hidden void element hides none of the text after it" $'\n## Quick start\n' "$void_md"

# --- Case: a ``` line inside <pre> does not close the fence early ---
nested_file="$TEST_TMPDIR/nested.md"
printf '%s' '<html><body><main><h1>Doc</h1><pre><code class="language-markdown">```
## Fake heading
```</code></pre><h2>Real</h2></main></body></html>' | conv >"$nested_file"
assert_contains "fence: outer fence is one backtick longer than the longest inner run" \
  $'````markdown\n```\n## Fake heading\n```\n````' "$(cat "$nested_file")"
nested_map="$(bash "$SCRIPT_DIR/docs-cache.sh" map --file "$nested_file")"
assert_absent "fence: section map has no heading from inside the code block" "Fake heading" "$nested_map"
assert_contains "fence: the heading after the code block is in the map" "Doc > Real" "$nested_map"

echo
if [[ $FAILED -eq 0 ]]; then
  printf 'All %d assertions passed.\n' "$CASE_NUM"
else
  printf '%d of %d assertions failed.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
