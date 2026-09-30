#!/usr/bin/env bash
# Self-contained tests for lib/fetch-docs.sh (no external test lib; the copies ship with the plugins).
#
# No case touches the network: the fixture cases set the docs fixture seam, and
# the fetch cases put a curl stand-in first on PATH that serves local files and
# logs every request.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fetch-docs.sh"
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
assert_no_file() {
  if [[ ! -e "$2" ]]; then pass "$1"; else fail "$1" "file exists: $2"; fi
}

CLAUDE_STUB="$TEST_TMPDIR/claude"
printf '#!/usr/bin/env bash\necho "9.8.7 (Claude Code)"\n' >"$CLAUDE_STUB"
chmod +x "$CLAUDE_STUB"

# The curl stand-in serves $CURL_SHIM_SRC/<last URL segment>. A sidecar
# <name>.status, <name>.ctype or <name>.effective overrides the HTTP status,
# the content type or the final URL for that file. A file that is not served
# exits 22 with no output, and a <name>.partial file is written and then fails
# with curl's short-transfer code, like a body cut off mid-download.
SHIM="$TEST_TMPDIR/shim"
mkdir -p "$SHIM"
cat >"$SHIM/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_SHIM_LOG"
out="" url="" wfmt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -o | -w | --connect-timeout | --max-time | --proto | --proto-redir | --max-redirs)
    [[ "$1" == "-o" ]] && out="$2"
    [[ "$1" == "-w" ]] && wfmt="$2"
    shift 2
    ;;
  -*) shift ;;
  *)
    url="$1"
    shift
    ;;
  esac
done
name="${url##*/}"
src="$CURL_SHIM_SRC/$name"
if [[ -f "$src.partial" ]]; then
  cp "$src.partial" "$out"
  exit 18
fi
[[ -f "$src" ]] || exit 22
cp "$src" "$out"
status=200
[[ -f "$src.status" ]] && status="$(cat "$src.status")"
ctype="text/markdown; charset=utf-8"
[[ "$name" == llms.txt ]] && ctype="text/plain; charset=utf-8"
[[ -f "$src.ctype" ]] && ctype="$(cat "$src.ctype")"
effective="$url"
[[ -f "$src.effective" ]] && effective="$(cat "$src.effective")"
wfmt="${wfmt//%\{http_code\}/$status}"
wfmt="${wfmt//%\{url_effective\}/$effective}"
wfmt="${wfmt//%\{content_type\}/$ctype}"
printf '%s' "$wfmt"
exit 0
EOF
chmod +x "$SHIM/curl"

INDEX='https://docs.test/docs/llms.txt'
mk_index() {
  printf '%s\n' '# Docs' \
    '- [Skills](https://docs.test/docs/en/skills.md): skills' \
    '- [Settings](https://docs.test/docs/en/settings-reference.md): keys' \
    '- [Vars](https://other.test/docs/en/env-vars.md): vars' >"$1/llms.txt"
}

# fixture_run <fixture dir> <out dir> <args...>: no network by construction.
fixture_run() {
  local fx="$1" out="$2"
  shift 2
  FETCH_DOCS_FIXTURE_DIR="$fx" FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" \
    bash "$SCRIPT" --index-url "$INDEX" --out "$out" "$@"
}

# shim_run <served dir> <out dir> <args...>: the curl stand-in on PATH, seam unset.
shim_run() {
  local src="$1" out="$2"
  shift 2
  env -u FETCH_DOCS_FIXTURE_DIR PATH="$SHIM:$PATH" CURL_SHIM_LOG="$src.log" CURL_SHIM_SRC="$src" \
    FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" bash "$SCRIPT" --index-url "$INDEX" --out "$out" "$@"
}

# page <manifest> <slug> <jq path>: one field of one page record.
page() {
  jq -r --arg s "$2" ".pages[] | select(.slug == \$s) | $3" "$1"
}

# New served dir holding the index and a couple of pages.
new_served() {
  local d="$TEST_TMPDIR/$1"
  mkdir -p "$d"
  mk_index "$d"
  printf '%s\n' '# Skills' 'body of skills' >"$d/skills.md"
  printf '%s\n' '# Settings' 'body of settings' >"$d/settings-reference.md"
  printf '%s' "$d"
}

# --- Case 1: a fixture page is read, with the hash, size and lines of its bytes
fx="$TEST_TMPDIR/fx1"
mkdir -p "$fx"
mk_index "$fx"
printf '%s\n%s\n%s' '# Skills' 'second line' 'last line without a newline' >"$fx/skills.md"
rc=0
fixture_run "$fx" "$TEST_TMPDIR/out1" skills || rc=$?
m="$TEST_TMPDIR/out1/manifest.json"
assert_eq "case 1: exit 0" 0 "$rc"
assert_eq "case 1: state and source" "read fixture" "$(page "$m" skills '"\(.state) \(.source)"')"
assert_eq "case 1: url is the one the index lists" "https://docs.test/docs/en/skills.md" "$(page "$m" skills .url)"
assert_eq "case 1: sha256 of the bytes" "$(sha256sum <"$fx/skills.md" | cut -d' ' -f1)" "$(page "$m" skills .sha256)"
assert_eq "case 1: bytes" "$(wc -c <"$fx/skills.md" | tr -d ' ')" "$(page "$m" skills .bytes)"
assert_eq "case 1: lines count a last line with no newline" 3 "$(page "$m" skills .lines)"
assert_eq "case 1: page on disk is the fixture" "" "$(cmp "$fx/skills.md" "$TEST_TMPDIR/out1/skills.md" 2>&1)"
assert_eq "case 1: mode defaults to full" full "$(page "$m" skills .mode)"
assert_eq "case 1: retrieved is a UTC ISO time" 1 "$(page "$m" skills '.retrieved | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") | if . then 1 else 0 end')"
assert_eq "case 1: a fixture read has no HTTP status" null "$(page "$m" skills .status)"
assert_eq "case 1: claude_version is the run's" 9.8.7 "$(jq -r .claude_version "$m")"
assert_eq "case 1: the index is a read record" "read fixture" "$(jq -r '.index | "\(.state) \(.source)"' "$m")"

# --- Case 2: a fixture directory that is set but empty means no network --------
fx="$TEST_TMPDIR/fx2"
mkdir -p "$fx"
rc=0
fixture_run "$fx" "$TEST_TMPDIR/out2" skills || rc=$?
m="$TEST_TMPDIR/out2/manifest.json"
assert_eq "case 2: exit 0" 0 "$rc"
assert_eq "case 2: index unread fixture-missing" "unread fixture-missing" "$(jq -r '.index | "\(.state) \(.reason)"' "$m")"
assert_eq "case 2: page unread index-unread" "unread index-unread" "$(page "$m" skills '"\(.state) \(.reason)"')"
assert_no_file "case 2: no page file" "$TEST_TMPDIR/out2/skills.md"
rc=0
FETCH_DOCS_FIXTURE_DIR="$TEST_TMPDIR/nowhere" FETCH_DOCS_CLAUDE_BIN="" \
  bash "$SCRIPT" --index-url "$INDEX" --out "$TEST_TMPDIR/out2b" skills || rc=$?
assert_eq "case 2: a missing fixture directory reads the same" "unread fixture-missing" "$(jq -r '.index | "\(.state) \(.reason)"' "$TEST_TMPDIR/out2b/manifest.json")"
assert_eq "case 2: an unreadable claude is an empty claude_version" "" "$(jq -r .claude_version "$TEST_TMPDIR/out2b/manifest.json")"

# --- Case 3: a page the index lists but the fixture lacks is fixture-missing ---
fx="$TEST_TMPDIR/fx3"
mkdir -p "$fx"
mk_index "$fx"
fixture_run "$fx" "$TEST_TMPDIR/out3" skills
assert_eq "case 3: fixture-missing" "unread fixture-missing" "$(page "$TEST_TMPDIR/out3/manifest.json" skills '"\(.state) \(.reason)"')"

# --- Case 4: a slug the index does not list is not requested -------------------
src="$(new_served served4)"
cp "$src/skills.md" "$src/slash-commands.md"
rc=0
mkdir -p "$TEST_TMPDIR/out4"
printf stale >"$TEST_TMPDIR/out4/slash-commands.md"
shim_run "$src" "$TEST_TMPDIR/out4" slash-commands skills || rc=$?
m="$TEST_TMPDIR/out4/manifest.json"
assert_eq "case 4: exit 0" 0 "$rc"
assert_eq "case 4: not-in-index" "unread not-in-index" "$(page "$m" slash-commands '"\(.state) \(.reason)"')"
assert_eq "case 4: no page request for it" 0 "$(grep -c 'slash-commands' "$src.log")"
assert_no_file "case 4: no file for it, a stale one included" "$TEST_TMPDIR/out4/slash-commands.md"
assert_eq "case 4: the listed slug is read" read "$(page "$m" skills .state)"
assert_eq "case 4: a URL the index lacks is not-in-index too" "unread not-in-index" "$(
  shim_run "$src" "$TEST_TMPDIR/out4b" https://docs.test/docs/en/slash-commands.md
  page "$TEST_TMPDIR/out4b/manifest.json" slash-commands '"\(.state) \(.reason)"'
)"

# --- Case 5: a 404 records its status and is unread ----------------------------
src="$(new_served served5)"
printf '%s\n' 'not found' >"$src/skills.md"
printf '%s' 404 >"$src/skills.md.status"
shim_run "$src" "$TEST_TMPDIR/out5" skills
m="$TEST_TMPDIR/out5/manifest.json"
assert_eq "case 5: 404 is unread" "unread http-404" "$(page "$m" skills '"\(.state) \(.reason)"')"
assert_eq "case 5: the status is recorded" 404 "$(page "$m" skills .status)"
assert_no_file "case 5: no page file" "$TEST_TMPDIR/out5/skills.md"

# --- Case 6: a text/html body is unread ----------------------------------------
src="$(new_served served6)"
printf '%s' 'text/html; charset=utf-8' >"$src/skills.md.ctype"
shim_run "$src" "$TEST_TMPDIR/out6" skills
m="$TEST_TMPDIR/out6/manifest.json"
assert_eq "case 6: html is unread" "unread unexpected-content-type" "$(page "$m" skills '"\(.state) \(.reason)"')"
assert_eq "case 6: the content type is recorded" "text/html; charset=utf-8" "$(page "$m" skills .content_type)"
assert_no_file "case 6: no page file" "$TEST_TMPDIR/out6/skills.md"

# --- Case 7: an empty body leaves no file, even over an earlier run's file -----
src="$(new_served served7)"
: >"$src/skills.md"
mkdir -p "$TEST_TMPDIR/out7"
printf 'stale' >"$TEST_TMPDIR/out7/skills.md"
shim_run "$src" "$TEST_TMPDIR/out7" skills
assert_eq "case 7: empty body is unread" "unread empty-body" "$(page "$TEST_TMPDIR/out7/manifest.json" skills '"\(.state) \(.reason)"')"
assert_no_file "case 7: no file, stale or partial" "$TEST_TMPDIR/out7/skills.md"
assert_no_file "case 7: no partial file left" "$TEST_TMPDIR/out7/skills.md.part"

# --- Case 8: a body cut off mid-download is unread -----------------------------
src="$(new_served served8)"
printf 'half of a pa' >"$src/skills.md.partial"
shim_run "$src" "$TEST_TMPDIR/out8" skills
assert_eq "case 8: truncated body is unread" "unread fetch-failed" "$(page "$TEST_TMPDIR/out8/manifest.json" skills '"\(.state) \(.reason)"')"
assert_no_file "case 8: no file, no partial" "$TEST_TMPDIR/out8/skills.md"
assert_no_file "case 8: no .part left" "$TEST_TMPDIR/out8/skills.md.part"

# --- Case 9: a redirect that lands off-origin is unread ------------------------
src="$(new_served served9)"
printf '%s' 'https://elsewhere.example/docs/en/skills.md' >"$src/skills.md.effective"
shim_run "$src" "$TEST_TMPDIR/out9" skills
assert_eq "case 9: off-origin landing is unread" "unread redirected-off-origin" "$(page "$TEST_TMPDIR/out9/manifest.json" skills '"\(.state) \(.reason)"')"
assert_no_file "case 9: no page file" "$TEST_TMPDIR/out9/skills.md"

# --- Case 10: an index link off the docs origin is not fetched -----------------
src="$(new_served served10)"
printf '%s\n' '# Vars' >"$src/env-vars.md"
shim_run "$src" "$TEST_TMPDIR/out10" env-vars
assert_eq "case 10: off-origin link is unread" "unread off-origin" "$(page "$TEST_TMPDIR/out10/manifest.json" env-vars '"\(.state) \(.reason)"')"
assert_eq "case 10: no page request" 0 "$(grep -c 'env-vars' "$src.log")"

# --- Case 11: every request is HTTPS only, capped and timed --------------------
src="$(new_served served11)"
shim_run "$src" "$TEST_TMPDIR/out11" skills settings-reference
total="$(wc -l <"$src.log" | tr -d ' ')"
assert_eq "case 11: three requests, the index and two pages" 3 "$total"
assert_eq "case 11: every request is HTTPS only, redirects included and capped" "$total" "$(grep -c -- '--proto =https --proto-redir =https --max-redirs 5 ' "$src.log")"
assert_eq "case 11: every request carries a connect timeout and a max time" "$total" "$(grep -c -- '--connect-timeout [0-9]* --max-time [0-9]' "$src.log")"
assert_eq "case 11: a fetched page records its status and content type" "200 text/markdown; charset=utf-8" "$(page "$TEST_TMPDIR/out11/manifest.json" skills '"\(.status) \(.content_type)"')"

# --- Case 12: the hash is over raw bytes, control characters included ----------
src="$(new_served served12)"
printf 'a\001b\r\nc\033[0md\177\n' >"$src/skills.md"
shim_run "$src" "$TEST_TMPDIR/out12" skills
m="$TEST_TMPDIR/out12/manifest.json"
assert_eq "case 12: sha256 is of the raw bytes" "$(sha256sum <"$src/skills.md" | cut -d' ' -f1)" "$(page "$m" skills .sha256)"
assert_eq "case 12: bytes are the raw count" "$(wc -c <"$src/skills.md" | tr -d ' ')" "$(page "$m" skills .bytes)"
assert_eq "case 12: the file on disk is byte-identical" "" "$(cmp "$src/skills.md" "$TEST_TMPDIR/out12/skills.md" 2>&1)"

# --- Case 13: --follow is accepted and changes nothing -------------------------
src="$(new_served served13)"
rc=0
shim_run "$src" "$TEST_TMPDIR/out13a" skills || rc=$?
shim_run "$src" "$TEST_TMPDIR/out13b" --follow 1 skills || rc=$((rc + $?))
strip='del(.index.retrieved, (.pages[] | .retrieved, .file)) | del(.index.file)'
assert_eq "case 13: exit 0 both times" 0 "$rc"
assert_eq "case 13: the manifests match" "$(jq -S "$strip" "$TEST_TMPDIR/out13a/manifest.json")" "$(jq -S "$strip" "$TEST_TMPDIR/out13b/manifest.json")"
assert_eq "case 13: the same requests" 4 "$(wc -l <"$src.log" | tr -d ' ')"
rc=0
shim_run "$src" "$TEST_TMPDIR/out13c" --follow deep skills 2>/dev/null || rc=$?
assert_eq "case 13: a non-numeric depth is fatal" 2 "$rc"

# --- Case 14: --mode is recorded per page as declared --------------------------
fx="$TEST_TMPDIR/fx14"
mkdir -p "$fx"
mk_index "$fx"
printf 'x\n' >"$fx/skills.md"
printf 'y\n' >"$fx/settings-reference.md"
fixture_run "$fx" "$TEST_TMPDIR/out14" skills --mode search settings-reference
m="$TEST_TMPDIR/out14/manifest.json"
assert_eq "case 14: modes per page" "full search" "$(page "$m" skills .mode) $(page "$m" settings-reference .mode)"

# --- Case 15: --discover requests every docs-origin page the index links -------
src="$(new_served served15)"
shim_run "$src" "$TEST_TMPDIR/out15" --discover
m="$TEST_TMPDIR/out15/manifest.json"
assert_eq "case 15: the two origin pages, not the off-origin link" "settings-reference skills" "$(jq -r '[.pages[].slug] | sort | join(" ")' "$m")"
assert_eq "case 15: both read" "read read" "$(jq -r '[.pages[].state] | join(" ")' "$m")"

# --- Case 16: an index that fails to fetch leaves every page unread ------------
src="$(new_served served16)"
rm -f "$src/llms.txt"
shim_run "$src" "$TEST_TMPDIR/out16" skills
m="$TEST_TMPDIR/out16/manifest.json"
assert_eq "case 16: index unread" "unread fetch-failed" "$(jq -r '.index | "\(.state) \(.reason)"' "$m")"
assert_eq "case 16: page unread index-unread" "unread index-unread" "$(page "$m" skills '"\(.state) \(.reason)"')"
assert_eq "case 16: only the index was requested" 1 "$(wc -l <"$src.log" | tr -d ' ')"

# --- Case 17: a slug that is not a path segment run is refused ------------------
fx="$TEST_TMPDIR/fx17"
mkdir -p "$fx"
mk_index "$fx"
fixture_run "$fx" "$TEST_TMPDIR/out17" '../escape'
assert_eq "case 17: invalid slug" "unread invalid-slug" "$(jq -r '.pages[0] | "\(.state) \(.reason)"' "$TEST_TMPDIR/out17/manifest.json")"

# --- Case 18: bad arguments are fatal -------------------------------------------
rc=0
bash "$SCRIPT" --out "$TEST_TMPDIR/out18" >/dev/null 2>&1 || rc=$?
assert_eq "case 18: no page and no --discover" 2 "$rc"
rc=0
bash "$SCRIPT" skills >/dev/null 2>&1 || rc=$?
assert_eq "case 18: no --out" 2 "$rc"
rc=0
bash "$SCRIPT" --out "$TEST_TMPDIR/out18" --index-url http://docs.test/docs/llms.txt skills >/dev/null 2>&1 || rc=$?
assert_eq "case 18: a non-https index URL" 2 "$rc"

# --- Case 19: a nested page never shadows the top-level page of the same name --
src="$TEST_TMPDIR/served19"
mkdir -p "$src"
printf '%s\n' '# Docs' \
  '- [Nested](https://docs.test/docs/en/plugins/x.md): nested' \
  '- [Top](https://docs.test/docs/en/x.md): top' >"$src/llms.txt"
printf '%s\n' '# X' 'body of x' >"$src/x.md"
shim_run "$src" "$TEST_TMPDIR/out19" x
m="$TEST_TMPDIR/out19/manifest.json"
assert_eq "case 19: the url is the top-level page" "https://docs.test/docs/en/x.md" "$(page "$m" x .url)"
assert_eq "case 19: the page is read" read "$(page "$m" x .state)"
shim_run "$src" "$TEST_TMPDIR/out19d" --discover
m="$TEST_TMPDIR/out19d/manifest.json"
assert_eq "case 19: discover lists the top-level page with its url" "https://docs.test/docs/en/x.md" "$(page "$m" x .url)"
assert_eq "case 19: discover does not call the top-level page not-in-index" read "$(page "$m" x .state)"
assert_eq "case 19: discover still resolves the nested page" "https://docs.test/docs/en/plugins/x.md" "$(page "$m" plugins/x .url)"

# --- Case 20: a non-https index link to the slug is off-origin, not absent ------
src="$TEST_TMPDIR/served20"
mkdir -p "$src"
printf '%s\n' '# Docs' '- [X](http://other.test/docs/en/x.md): x' >"$src/llms.txt"
shim_run "$src" "$TEST_TMPDIR/out20" x
assert_eq "case 20: non-https link is off-origin" "unread off-origin" "$(page "$TEST_TMPDIR/out20/manifest.json" x '"\(.state) \(.reason)"')"
printf '%s\n' '# Docs' '- [X](//other.test/docs/en/x.md): x' >"$src/llms.txt"
shim_run "$src" "$TEST_TMPDIR/out20r" x
assert_eq "case 20: protocol-relative link is off-origin" "unread off-origin" "$(page "$TEST_TMPDIR/out20r/manifest.json" x '"\(.state) \(.reason)"')"

# --- Case: publisher profiles ---------------------------------------------------
fx="$TEST_TMPDIR/fxp"
mkdir -p "$fx"
printf '%s\n' '# Docs' '- [Skills](https://code.claude.com/docs/en/skills.md): skills' >"$fx/llms.txt"
printf '%s\n' '# Skills' >"$fx/skills.md"
FETCH_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --out "$TEST_TMPDIR/outp-default" skills >/dev/null
FETCH_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --profile anthropic --out "$TEST_TMPDIR/outp-named" skills >/dev/null
assert_eq "profile: the default profile is anthropic" \
  "$(jq -S 'del(.pages[].retrieved, .index.retrieved) | del(.pages[].file, .index.file)' "$TEST_TMPDIR/outp-named/manifest.json")" \
  "$(jq -S 'del(.pages[].retrieved, .index.retrieved) | del(.pages[].file, .index.file)' "$TEST_TMPDIR/outp-default/manifest.json")"
assert_eq "profile: anthropic index and page resolve" "read read https://code.claude.com/docs/llms.txt https://code.claude.com/docs/en/skills.md" \
  "$(jq -r '"\(.index.state) \(.pages[0].state) \(.index.url) \(.pages[0].url)"' "$TEST_TMPDIR/outp-default/manifest.json")"
rc=0
err="$(FETCH_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --profile nope --out "$TEST_TMPDIR/outp-bad" skills 2>&1 >/dev/null)" || rc=$?
assert_eq "profile: an unknown profile is fatal" 2 "$rc"
assert_eq "profile: the error names the profile" "ERROR: unknown profile: nope (known: anthropic)" "$err"
assert_no_file "profile: an unknown profile writes no manifest" "$TEST_TMPDIR/outp-bad/manifest.json"
rc=0
FETCH_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --profile --out "$TEST_TMPDIR/outp-bad" skills >/dev/null 2>&1 || rc=$?
assert_eq "profile: --profile takes the next word as its value" 2 "$rc"

# --- Case: the claude version probe runs under a timeout ---
mkdir -p "$TEST_TMPDIR/tbin"
# shellcheck disable=SC2016 # the stub script expands its own arguments
printf '#!/usr/bin/env bash\necho "$1" >"%s"\nshift\nexec "$@"\n' "$TEST_TMPDIR/timeout.log" >"$TEST_TMPDIR/tbin/timeout"
chmod +x "$TEST_TMPDIR/tbin/timeout"
PATH="$TEST_TMPDIR/tbin:$PATH" FETCH_DOCS_FIXTURE_DIR="$TEST_TMPDIR/nowhere" FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" \
  bash "$SCRIPT" --index-url "$INDEX" --out "$TEST_TMPDIR/out-to" skills || true
assert_eq "timeout: probe bounded to 30 s" 30 "$(cat "$TEST_TMPDIR/timeout.log" 2>/dev/null)"
assert_eq "timeout: version still read" 9.8.7 "$(jq -r .claude_version "$TEST_TMPDIR/out-to/manifest.json")"

echo
if [[ $FAILED -eq 0 ]]; then
  printf 'All %d assertions passed.\n' "$CASE_NUM"
else
  printf '%d of %d assertions failed.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
