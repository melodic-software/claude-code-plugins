#!/usr/bin/env bash
# Self-contained tests for check-doc-citations.sh (no external test lib; ships with the plugin).
#
# Fixture rows carry backticked spans that must reach the file unexpanded, so
# single quotes are the correct spelling.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-doc-citations.sh"
MANIFEST="$SCRIPT_DIR/../reference/doc-citations.tsv"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# No DOCS_CACHE_* setting and no machine config file of the caller's is ever read.
# A case that serves its own content for a slug another case also serves runs
# with its own DOCS_CACHE_DIR, so no cached title or quarantine carries over.
while IFS= read -r v; do unset "$v"; done < <(compgen -e DOCS_CACHE_)
export DOCS_CACHE_DIR="$TEST_TMPDIR/cache" XDG_CONFIG_HOME="$TEST_TMPDIR/config"

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
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected $2, got $3"; fi
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}

# index_of <dir>: write <dir>/llms.txt linking every page under <dir>, as the docs index does.
index_of() {
  local d="$1" p
  {
    printf '# Docs\n'
    while IFS= read -r p; do
      p="${p#"$d"/}"
      printf -- '- [%s](https://code.claude.com/docs/en/%s): page\n' "${p%.md}" "$p"
    done < <(find "$d" -name '*.md' | sort)
  } >"$d/llms.txt"
}

# A curl stand-in serving local files by docs path. It logs every request to
# $CURL_SHIM_LOG, serves $CURL_SHIM_SRC, answers 404 for a file it lacks, and
# reports an off-origin final URL for the page named in $CURL_SHIM_REDIRECT_PAGE.
SHIM="$TEST_TMPDIR/shim"
mkdir -p "$SHIM"
cat >"$SHIM/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_SHIM_LOG"
out="" url="" wfmt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -o | -w | -D | -H | --connect-timeout | --max-time | --max-filesize | --proto | --proto-redir | --max-redirs)
    [[ "$1" == "-o" ]] && out="$2"
    [[ "$1" == "-w" ]] && wfmt="$2"
    shift 2
    ;;
  -*) shift ;;
  *) url="$1"; shift ;;
  esac
done
rel="${url#https://code.claude.com/docs/}"
rel="${rel#en/}"
status=200
if [[ -f "$CURL_SHIM_SRC/$rel" ]]; then cp "$CURL_SHIM_SRC/$rel" "$out"; else : >"$out"; status=404; fi
ctype="text/markdown; charset=utf-8"
[[ "$rel" == llms.txt ]] && ctype="text/plain; charset=utf-8"
effective="$url"
[[ -n "${CURL_SHIM_REDIRECT_PAGE:-}" && "$url" == *"/$CURL_SHIM_REDIRECT_PAGE.md" ]] && effective="https://elsewhere.example/docs/en/$CURL_SHIM_REDIRECT_PAGE.md"
wfmt="${wfmt//%\{http_code\}/$status}"
wfmt="${wfmt//%\{url_effective\}/$effective}"
wfmt="${wfmt//%\{content_type\}/$ctype}"
printf '%s' "$wfmt"
EOF
chmod +x "$SHIM/curl"

# shim_run <served dir> <log> <script args...>: run the script through the stand-in with no fixture seam,
# and a docs cache of its own beside the log.
shim_run() {
  local src="$1" log="$2"
  shift 2
  PATH="$SHIM:$PATH" CURL_SHIM_SRC="$src" CURL_SHIM_LOG="$log" SETTINGS_AUDIT_DOCS_FIXTURE_DIR="" DOCS_CACHE_DIR="$log.cache" \
    FETCH_DOCS_FIXTURE_DIR="" bash "$SCRIPT" "$@" 2>&1
}

# --- Case 1: every span present on fixture pages passes --------------------
fx="$TEST_TMPDIR/present"
mkdir -p "$fx"
man="$TEST_TMPDIR/manifest-present.tsv"
printf '%s\n' '# comment' 'alpha	### `keyOne`' 'alpha	a sentence with `code`' 'beta	The space before a trailing `*` is part of the rule' >"$man"
printf '%s\n' '# alpha' '### `keyOne`' 'prose, a sentence with `code` inside' >"$fx/alpha.md"
printf '%s\n' '* **The space before a trailing `*` is part of the rule.** more' >"$fx/beta.md"
index_of "$fx"
rc=0
out=$(DOCS_CACHE_DIR="$fx.cache" SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --manifest "$man" 2>&1) || rc=$?
assert_exit "case 1: all present exits 0" 0 "$rc"
assert_contains "case 1: OK rows" "$out" "OK    alpha: ### \`keyOne\`"
assert_contains "case 1: summary counts" "$out" "Checked 3 citation(s), 0 missing, 0 skipped"

# --- Case 2: a span the page lost is a MISS and exit 1 ------------------------
man="$TEST_TMPDIR/manifest-missing.tsv"
printf '%s\n' 'alpha	### `keyOne`' 'alpha	### `keyGone`' >"$man"
rc=0
out=$(DOCS_CACHE_DIR="$fx.cache" SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --manifest "$man" 2>&1) || rc=$?
assert_exit "case 2: missing span exits 1" 1 "$rc"
assert_contains "case 2: MISS row names the span" "$out" "MISS  alpha: ### \`keyGone\`"
assert_contains "case 2: summary counts the miss" "$out" "1 missing"

# --- Case 3: an unreadable page is a SKIP, never a pass or a failure -----------
man="$TEST_TMPDIR/manifest-skip.tsv"
printf '%s\n' 'alpha	### `keyOne`' 'gamma	anything' 'gamma	anything else' >"$man"
rc=0
out=$(DOCS_CACHE_DIR="$fx.cache" SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --manifest "$man" 2>&1) || rc=$?
assert_exit "case 3: skip does not fail" 0 "$rc"
assert_contains "case 3: SKIP line printed once per page" "$out" "SKIP  gamma: page could not be read"
assert_contains "case 3: SKIP line carries the reason" "$out" "not-in-index"
assert_contains "case 3: summary counts skips" "$out" "2 skipped"
assert_not_contains "case 3: no OK claimed for the skipped page" "$out" "OK    gamma"

# --- Case 4: --docs-dir pages are read before any fetch -------------------------
# The stand-in serves an index listing both pages but only one page file, so the
# run proves both that a page on disk is never requested and that a page the
# fetch cannot read is a SKIP.
served="$TEST_TMPDIR/served4"
mkdir -p "$served"
printf '%s\n' '# Docs' '- [a](https://code.claude.com/docs/en/alpha.md): a' '- [d](https://code.claude.com/docs/en/delta.md): d' >"$served/llms.txt"
man="$TEST_TMPDIR/manifest-docs.tsv"
printf '%s\n' 'alpha	### `keyOne`' 'delta	never fetched span' >"$man"
rc=0
out=$(shim_run "$served" "$TEST_TMPDIR/curl-4.log" --manifest "$man" --docs-dir "$fx") || rc=$?
assert_exit "case 4: docs-dir page satisfies the row, failed fetch is a skip" 0 "$rc"
assert_contains "case 4: OK from the docs dir" "$out" "OK    alpha"
assert_contains "case 4: the unfetchable page is skipped with its reason" "$out" "SKIP  delta: page could not be read this run (http-404)"
calls="$(cat "$TEST_TMPDIR/curl-4.log" 2>/dev/null || true)"
assert_not_contains "case 4: the on-disk page was never fetched" "$calls" "alpha.md"
assert_contains "case 4: the absent page was fetched once" "$calls" "delta.md"

# --- Case 5: fatal cases ---------------------------------------------------------
rc=0
bash "$SCRIPT" --manifest "$TEST_TMPDIR/absent.tsv" >/dev/null 2>&1 || rc=$?
assert_exit "case 5: missing manifest exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" --nope >/dev/null 2>&1 || rc=$?
assert_exit "case 5: unknown argument exits 2" 2 "$rc"
rc=0
out=$(CLAUDE_PLUGIN_ROOT="$TEST_TMPDIR/no-plugin" SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --manifest "$man" 2>&1) || rc=$?
assert_exit "case 5: a missing shared fetcher exits 2" 2 "$rc"
assert_contains "case 5: the missing fetcher is named" "$out" "shared fetcher not found"

# --- Case 6: the shipped manifest is well-formed --------------------------------
rc=0
bad=$(grep -vE '^(#|$)' "$MANIFEST" | grep -vcE $'^[a-z-]+(/[a-z-]+)*\t.+$' || true)
if [[ "$bad" == "0" ]]; then pass "case 6: every manifest row is slug<TAB>span"; else fail "case 6: every manifest row is slug<TAB>span" "$bad malformed row(s)"; fi

# --- Case 7: a manifest with no trailing newline still checks its last row ------
fx7="$TEST_TMPDIR/lastrow"
mkdir -p "$fx7"
man="$TEST_TMPDIR/manifest-lastrow.tsv"
printf 'alpha\t### `keyOne`\nalpha\t### `keyGone`' >"$man"
printf '%s\n' '### `keyOne`' >"$fx7/alpha.md"
index_of "$fx7"
rc=0
out=$(DOCS_CACHE_DIR="$fx7.cache" SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx7" bash "$SCRIPT" --manifest "$man" 2>&1) || rc=$?
assert_exit "case 7: the unterminated last row is checked and fails" 1 "$rc"
assert_contains "case 7: MISS names the last row" "$out" "MISS  alpha: ### \`keyGone\`"
assert_contains "case 7: both rows counted" "$out" "Checked 2 citation(s), 1 missing"

# --- Case 8: a nested slug is fetched into its own subdirectory -----------------
served="$TEST_TMPDIR/served8"
mkdir -p "$served/plugins"
printf 'a nested span\n' >"$served/plugins/install.md"
index_of "$served"
man="$TEST_TMPDIR/manifest-nested.tsv"
printf 'plugins/install\ta nested span\n' >"$man"
rc=0
out=$(shim_run "$served" "$TEST_TMPDIR/curl-8.log" --manifest "$man") || rc=$?
assert_exit "case 8: the nested page is fetched and checked" 0 "$rc"
assert_contains "case 8: OK for the nested slug" "$out" "OK    plugins/install: a nested span"

# --- Case 9: a slug that could leave the page directory is refused --------------
# A page sits beside the fixture directory, so a slug that climbed out of it
# would read that page and pass.
fx9="$TEST_TMPDIR/slugs/pages"
mkdir -p "$fx9"
printf '%s\n' 'an escaped span' >"$TEST_TMPDIR/slugs/escape.md"
printf '%s\n' 'an escaped span' >"$fx9/alpha.md"
index_of "$fx9"
for bad in '../escape' '/escape' 'alpha/../../escape' 'Alpha'; do
  man="$TEST_TMPDIR/manifest-badslug.tsv"
  printf 'alpha\tan escaped span\n%s\tan escaped span\n' "$bad" >"$man"
  rc=0
  out=$(DOCS_CACHE_DIR="$fx9.cache" SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx9" bash "$SCRIPT" --manifest "$man" 2>&1) || rc=$?
  assert_exit "case 9: slug '$bad' exits 2" 2 "$rc"
  assert_contains "case 9: slug '$bad' is named with its row" "$out" "ERROR: manifest row 2 has an invalid page slug: $bad"
  assert_not_contains "case 9: slug '$bad' checks no row" "$out" "OK "
done

# --- Case 10: a slug the index does not list is skipped, never fetched -----------
# The index lists skills but not slash-commands. slash-commands.md sits in the
# fixture and on the served side byte-identical to skills.md, the shape of a
# retired slug that answers with another page's body: a span skills carries
# must not pass as slash-commands' own.
fx10="$TEST_TMPDIR/retired"
mkdir -p "$fx10"
printf '%s\n' '# Skills' 'a span the skills page carries' >"$fx10/skills.md"
cp "$fx10/skills.md" "$fx10/slash-commands.md"
printf '%s\n' '# Docs' '- [Skills](https://code.claude.com/docs/en/skills.md): skills' >"$fx10/llms.txt"
man="$TEST_TMPDIR/manifest-retired.tsv"
printf '%s\n' 'slash-commands	a span the skills page carries' >"$man"
rc=0
out=$(DOCS_CACHE_DIR="$fx10.cache" SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx10" bash "$SCRIPT" --manifest "$man" 2>&1) || rc=$?
assert_exit "case 10: fixture, the unindexed page does not fail" 0 "$rc"
assert_contains "case 10: fixture, SKIP names the page and the reason" "$out" "SKIP  slash-commands: page could not be read this run (not-in-index)"
assert_not_contains "case 10: fixture, no OK for the unindexed page" "$out" "OK "
assert_contains "case 10: fixture, the row counts as skipped" "$out" "Checked 0 citation(s), 0 missing, 1 skipped"
printf '%s\n' 'skills	a span the skills page carries' 'slash-commands	a span the skills page carries' >"$man"
rc=0
out=$(shim_run "$fx10" "$TEST_TMPDIR/curl-10.log" --manifest "$man") || rc=$?
assert_exit "case 10: fetch route, the unindexed page does not fail" 0 "$rc"
assert_contains "case 10: fetch route, the indexed page is read" "$out" "OK    skills: a span the skills page carries"
assert_contains "case 10: fetch route, the unindexed page is a SKIP" "$out" "SKIP  slash-commands: page could not be read this run (not-in-index)"
assert_not_contains "case 10: fetch route, no OK for the unindexed page" "$out" "OK    slash-commands"
calls="$(cat "$TEST_TMPDIR/curl-10.log" 2>/dev/null || true)"
assert_contains "case 10: fetch route, the indexed page was requested" "$calls" "skills.md"
assert_not_contains "case 10: fetch route, no request for slash-commands.md" "$calls" "slash-commands.md"

# --- Case 11: every request is HTTPS only and stays on the docs origin -----------
served="$TEST_TMPDIR/served11"
mkdir -p "$served"
printf '%s\n' 'alpha span' >"$served/alpha.md"
printf '%s\n' 'beta span' >"$served/beta.md"
index_of "$served"
man="$TEST_TMPDIR/manifest-origin.tsv"
printf '%s\n' 'alpha	alpha span' 'beta	beta span' >"$man"
rc=0
out=$(CURL_SHIM_REDIRECT_PAGE=beta shim_run "$served" "$TEST_TMPDIR/curl-11.log" --manifest "$man") || rc=$?
assert_exit "case 11: an off-origin redirect does not fail the run" 0 "$rc"
assert_contains "case 11: the on-origin page is read" "$out" "OK    alpha: alpha span"
assert_contains "case 11: the redirected page is a SKIP with the reason" "$out" "SKIP  beta: page could not be read this run (redirected-off-origin)"
assert_not_contains "case 11: no OK for the redirected page" "$out" "OK    beta"
calls="$(cat "$TEST_TMPDIR/curl-11.log")"
total="$(grep -c . "$TEST_TMPDIR/curl-11.log")"
assert_eq "case 11: the index and both pages were requested" 3 "$total"
https_only="$(grep -c -- '--proto =https --proto-redir =https --max-redirs 5 ' "$TEST_TMPDIR/curl-11.log")"
assert_eq "case 11: every request is HTTPS only, redirects included and capped" "$total" "$https_only"
timed="$(grep -c -- '--connect-timeout .* --max-time ' "$TEST_TMPDIR/curl-11.log")"
assert_eq "case 11: every request carries a connect timeout and a max time" "$total" "$timed"
assert_not_contains "case 11: no plain-http request" "$calls" "http://"

# --- Case 12: a jq that ends each @tsv line with CR (Windows) leaves no CR in the reason ---
crjq="$TEST_TMPDIR/crjq"
mkdir -p "$crjq"
real_jq="$(command -v jq)"
cat >"$crjq/jq" <<EOF
#!/usr/bin/env bash
case "\$*" in
*@tsv*) "$real_jq" "\$@" | sed 's/\$/\r/' ;;
*) exec "$real_jq" "\$@" ;;
esac
EOF
chmod +x "$crjq/jq"
man="$TEST_TMPDIR/manifest-crlf.tsv"
printf '%s\n' 'gamma	anything' >"$man"
rc=0
out=$(PATH="$crjq:$PATH" DOCS_CACHE_DIR="$fx.crlf-cache" SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --manifest "$man" 2>&1) || rc=$?
assert_exit "case 12: CR-terminated reason still skips" 0 "$rc"
assert_contains "case 12: SKIP reason closes without a CR" "$out" "SKIP  gamma: page could not be read this run (not-in-index)"
assert_not_contains "case 12: no CR reaches the output" "$out" $'\r'

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
