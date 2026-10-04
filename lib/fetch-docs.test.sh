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
# A caller's cache settings must never receive this suite's fixture bytes.
unset DOCS_CACHE_DIR DOCS_CACHE_NOW

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

# The curl stand-in serves $CURL_SHIM_SRC/<last URL segment> and logs every
# request with its headers. A sidecar <name>.status, <name>.ctype or
# <name>.effective overrides the HTTP status, the content type or the final URL
# for that file. <name>.etag and <name>.lastmod are sent as ETag and
# Last-Modified (Date is <name>.date, else a fixed time), and a request whose
# If-None-Match or If-Modified-Since matches them gets an empty 304. A request
# with Accept: text/markdown gets <name>.accept-md, when present, as
# text/markdown. A file that is not served exits 22 with no output, and a
# <name>.partial file is written and then fails with curl's short-transfer
# code, like a body cut off mid-download.
SHIM="$TEST_TMPDIR/shim"
mkdir -p "$SHIM"
cat >"$SHIM/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_SHIM_LOG"
out="" url="" wfmt="" hdr="" accept="" inm="" ims=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -o | -w | -D | -H | --connect-timeout | --max-time | --proto | --proto-redir | --max-redirs)
    [[ "$1" == "-o" ]] && out="$2"
    [[ "$1" == "-w" ]] && wfmt="$2"
    [[ "$1" == "-D" ]] && hdr="$2"
    if [[ "$1" == "-H" ]]; then
      case "$2" in
      "Accept: "*) accept="${2#Accept: }" ;;
      "If-None-Match: "*) inm="${2#If-None-Match: }" ;;
      "If-Modified-Since: "*) ims="${2#If-Modified-Since: }" ;;
      esac
    fi
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
status=200
ctype="text/markdown; charset=utf-8"
[[ "$name" == llms.txt ]] && ctype="text/plain; charset=utf-8"
[[ -f "$src.ctype" ]] && ctype="$(cat "$src.ctype")"
body="$src"
if [[ "$accept" == text/markdown && -f "$src.accept-md" ]]; then
  body="$src.accept-md"
  ctype="text/markdown; charset=utf-8"
fi
[[ -f "$src.status" ]] && status="$(cat "$src.status")"
etag="" lastmod="" date="Mon, 01 Jan 2001 00:00:00 GMT"
[[ -f "$src.etag" ]] && etag="$(cat "$src.etag")"
[[ -f "$src.lastmod" ]] && lastmod="$(cat "$src.lastmod")"
[[ -f "$src.date" ]] && date="$(cat "$src.date")"
if [[ (-n "$etag" && "$inm" == "$etag") || (-n "$lastmod" && "$ims" == "$lastmod") ]]; then
  status=304
  body=""
fi
if [[ -n "$body" ]]; then cp "$body" "$out"; fi
if [[ -n "$hdr" ]]; then
  {
    printf 'HTTP/1.1 %s X\r\nDate: %s\r\n' "$status" "$date"
    [[ -z "$etag" ]] || printf 'ETag: %s\r\n' "$etag"
    [[ -z "$lastmod" ]] || printf 'Last-Modified: %s\r\n' "$lastmod"
    printf '\r\n'
  } >"$hdr"
fi
[[ "$status" != 304 ]] || ctype=""
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
strip='del(.index.retrieved, .index.validated, (.pages[] | .retrieved, .validated, .file)) | del(.index.file)'
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

# --- Case 21: --cache serves a fresh entry and says so -------------------------
T1=1000000000
T1_ISO='2001-09-09T01:46:40Z'
T2=1000000100
T3=1000086500
T3_ISO='2001-09-10T01:48:20Z'
src="$(new_served served21)"
C="$TEST_TMPDIR/cache21"
cache_run() {
  local now="$1" out="$2"
  shift 2
  DOCS_CACHE_NOW="$now" shim_run "$src" "$TEST_TMPDIR/$out" --cache --cache-dir "$C" "$@"
}
want_key="$(printf '%s\n%s' 'https://docs.test/docs/en/skills.md' markdown | sha256sum | cut -d' ' -f1)"
cache_run $T1 out21a --max-age 86400 skills
m="$TEST_TMPDIR/out21a/manifest.json"
assert_eq "case 21: a first --cache read is a fetch" "read fetch" "$(page "$m" skills '"\(.state) \(.source)"')"
assert_eq "case 21: a fetch is retrieved and validated now, age 0" "$T1_ISO $T1_ISO 0" "$(page "$m" skills '"\(.retrieved) \(.validated) \(.age_seconds)"')"
assert_eq "case 21: cache_key is the key of the url and format" "$want_key" "$(page "$m" skills .cache_key)"
requests="$(wc -l <"$src.log" | tr -d ' ')"
cache_run $T2 out21b --max-age 86400 skills
m="$TEST_TMPDIR/out21b/manifest.json"
assert_eq "case 21: a second read inside max-age is a cache hit" "read cache" "$(page "$m" skills '"\(.state) \(.source)"')"
assert_eq "case 21: the index is served from the cache too" "read cache" "$(jq -r '.index | "\(.state) \(.source)"' "$m")"
assert_eq "case 21: a hit makes no request" "$requests" "$(wc -l <"$src.log" | tr -d ' ')"
assert_eq "case 21: a hit keeps retrieved and validated and reports its age" "$T1_ISO $T1_ISO 100" "$(page "$m" skills '"\(.retrieved) \(.validated) \(.age_seconds)"')"
assert_eq "case 21: a hit has no HTTP status and the stored content type" "null text/markdown; charset=utf-8" "$(page "$m" skills '"\(.status) \(.content_type)"')"
assert_eq "case 21: a hit writes the page file" "" "$(cmp "$src/skills.md" "$TEST_TMPDIR/out21b/skills.md" 2>&1)"
assert_eq "case 21: a hit's hash is of those bytes" "$(sha256sum <"$src/skills.md" | cut -d' ' -f1)" "$(page "$m" skills .sha256)"
cache_run $T3 out21c --max-age 86400 skills
m="$TEST_TMPDIR/out21c/manifest.json"
assert_eq "edge: TTL expiry refetches; unchanged bytes keep retrieved and move validated" "fetch $T1_ISO $T3_ISO 0" "$(page "$m" skills '"\(.source) \(.retrieved) \(.validated) \(.age_seconds)"')"
rm -f "$src/skills.md"
cache_run $T3 out21d --max-age 0 skills
m="$TEST_TMPDIR/out21d/manifest.json"
assert_eq "edge: --max-age 0 with a failed fetch is unread, never the cached bytes" "unread fetch-failed fetch" "$(page "$m" skills '"\(.state) \(.reason) \(.source)"')"
assert_no_file "edge: --max-age 0 with a failed fetch leaves no page file" "$TEST_TMPDIR/out21d/skills.md"
cache_run $((T3 + 86401)) out21e --max-age 86400 skills
assert_eq "edge: offline: an expired entry with a failed fetch and --max-age above 0 is served stale, flagged, with its age" \
  "read cache true 86401 fetch-failed" \
  "$(page "$TEST_TMPDIR/out21e/manifest.json" skills '"\(.state) \(.source) \(.stale) \(.age_seconds) \(.reason)"')"
assert_eq "edge: offline: the stale page file is the cached bytes" "" \
  "$(printf '%s\n' '# Skills' 'body of skills' | cmp - "$TEST_TMPDIR/out21e/skills.md" 2>&1)"
assert_eq "edge: offline: a fresh read is not stale" false "$(page "$TEST_TMPDIR/out21b/manifest.json" skills .stale)"

# --- Case 22: the cache flags and their guards ----------------------------------
src="$(new_served served22)"
shim_run "$src" "$TEST_TMPDIR/out22" skills
m="$TEST_TMPDIR/out22/manifest.json"
assert_eq "case 22: without --cache a read is validated when retrieved, age 0, no key" "true 0 null" \
  "$(page "$m" skills '"\(.validated == .retrieved and .validated != null) \(.age_seconds) \(.cache_key)"')"
assert_eq "case 22: an unread page has no validated or age" "null null" \
  "$(page "$TEST_TMPDIR/out5/manifest.json" skills '"\(.validated) \(.age_seconds)"')"
fx="$TEST_TMPDIR/fx22"
mkdir -p "$fx"
mk_index "$fx"
printf '%s\n' '# Skills' >"$fx/skills.md"
rc=0
err="$(FETCH_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --index-url "$INDEX" --out "$TEST_TMPDIR/out22f" --cache skills 2>&1 >/dev/null)" || rc=$?
assert_eq "case 22: --cache in fixture mode with no cache directory is fatal" 2 "$rc"
assert_eq "case 22: the error names the seam" "ERROR: --cache with FETCH_DOCS_FIXTURE_DIR needs --cache-dir or DOCS_CACHE_DIR" "$err"
DOCS_CACHE_DIR="$TEST_TMPDIR/cache22" fixture_run "$fx" "$TEST_TMPDIR/out22g" --cache skills
assert_eq "case 22: DOCS_CACHE_DIR is the cache directory; a fixture read is stored" "fixture 1" \
  "$(page "$TEST_TMPDIR/out22g/manifest.json" skills '"\(.source) \(.cache_key | length / 64)"')"
DOCS_CACHE_DIR="$TEST_TMPDIR/cache22" fixture_run "$fx" "$TEST_TMPDIR/out22h" --cache skills
assert_eq "case 22: --max-age defaults above 0, so the next read is a hit" cache "$(page "$TEST_TMPDIR/out22h/manifest.json" skills .source)"
rc=0
bash "$SCRIPT" --out "$TEST_TMPDIR/out22i" --cache --max-age soon skills >/dev/null 2>&1 || rc=$?
assert_eq "case 22: a non-numeric --max-age is fatal" 2 "$rc"
printf '3\n' >"$TEST_TMPDIR/cache22/store_version"
DOCS_CACHE_DIR="$TEST_TMPDIR/cache22" fixture_run "$fx" "$TEST_TMPDIR/out22j" --cache skills 2>/dev/null
assert_eq "case 22: a root at another version is never read; the page is read and stored beside it" "read fixture true 3" \
  "$(page "$TEST_TMPDIR/out22j/manifest.json" skills '"\(.state) \(.source) \(.cache_key != null)"') $(cat "$TEST_TMPDIR/cache22/store_version")"
rc=0
DOCS_CACHE_PATH_MAX=10 DOCS_CACHE_DIR="$TEST_TMPDIR/cache22p" fixture_run "$fx" "$TEST_TMPDIR/out22k" --cache skills 2>"$TEST_TMPDIR/err22k" || rc=$?
assert_eq "case 22: a refused cache write names its reason in the manifest and the warning" "read null 1 1" \
  "$(page "$TEST_TMPDIR/out22k/manifest.json" skills '"\(.state) \(.cache_key)"') $(page "$TEST_TMPDIR/out22k/manifest.json" skills .cache_error | grep -c 'path too long') $(grep -c 'skills.md was read but not cached in .*: path too long' "$TEST_TMPDIR/err22k")"
assert_eq "case 22: a stored page has no cache_error" null "$(page "$TEST_TMPDIR/out22h/manifest.json" skills .cache_error)"

# --- Case 23: clock skew, a server error, removal and notes ---------------------
src="$(new_served served23)"
C="$TEST_TMPDIR/cache23"
SKEW_DATE='Tue, 11 Sep 2001 01:46:40 GMT'
printf '%s' "$SKEW_DATE" >"$src/skills.md.date"
cache_run $T1 out23a --max-age 86400 skills
assert_eq "edge: clock skew: the server Date is recorded on a fetch" "$SKEW_DATE 0" \
  "$(page "$TEST_TMPDIR/out23a/manifest.json" skills '"\(.server_date) \(.age_seconds)"')"
cache_run $T2 out23b --max-age 86400 skills
assert_eq "edge: clock skew: a server Date two days ahead leaves the age to the local validated epoch" \
  "cache 100 $SKEW_DATE" "$(page "$TEST_TMPDIR/out23b/manifest.json" skills '"\(.source) \(.age_seconds) \(.server_date)"')"
printf '503' >"$src/skills.md.status"
cache_run $T3 out23c --max-age 86400 skills
assert_eq "edge: offline: a 5xx answer is a failed fetch, served stale" "read true http-503" \
  "$(page "$TEST_TMPDIR/out23c/manifest.json" skills '"\(.state) \(.stale) \(.reason)"')"
cache_run $T3 out23d --max-age 0 skills
assert_eq "edge: offline: --max-age 0 with a 5xx is unread" "unread http-503" \
  "$(page "$TEST_TMPDIR/out23d/manifest.json" skills '"\(.state) \(.reason)"')"
rm -f "$src/skills.md.status"

DC() { bash "$SCRIPT_DIR/docs-cache.sh" --cache-dir "$C" "$@"; }
skills_key="$(DC key https://docs.test/docs/en/skills.md markdown)"
printf 'Skills holds "body of skills".\n' |
  DOCS_CACHE_NOW=$T3 DC note put "$skills_key" --model m --session s --question q --sections 1 >/dev/null
cache_run $T3 out23e --max-age 0 skills
assert_eq "edge: --max-age 0 output carries no note text" "read 0" \
  "$(page "$TEST_TMPDIR/out23e/manifest.json" skills .state) $(grep -rc 'Skills holds' "$TEST_TMPDIR/out23e" | awk -F: '{ n += $NF } END { print n + 0 }')"
printf '404' >"$src/skills.md.status"
cache_run $T3 out23f --max-age 0 skills
assert_eq "edge: page removed: a 404 is unread and quarantines the key" "unread http-404 http-404" \
  "$(page "$TEST_TMPDIR/out23f/manifest.json" skills '"\(.state) \(.reason)"') $(DC info "$skills_key" | jq -r .quarantine.reason)"
assert_eq "edge: page removed: its note is never served" "" "$(DC note get "$skills_key" 2>/dev/null)"
cache_run $((T3 + 86401)) out23g --max-age 86400 skills
assert_eq "edge: page removed: a 404 is not a failed fetch, so nothing is served stale" "unread false" \
  "$(page "$TEST_TMPDIR/out23g/manifest.json" skills '"\(.state) \(.stale)"')"
settings_key="$(DC key https://docs.test/docs/en/settings-reference.md markdown)"
cache_run $T3 out23h --max-age 0 settings-reference
printf '%s\n' '# Docs' '- [Skills](https://docs.test/docs/en/skills.md): skills' >"$src/llms.txt"
cache_run $T3 out23i --max-age 0 settings-reference
assert_eq "edge: page removed from the index: not-in-index quarantines the key" "unread not-in-index not-in-index" \
  "$(page "$TEST_TMPDIR/out23i/manifest.json" settings-reference '"\(.state) \(.reason)"') $(DC info "$settings_key" | jq -r .quarantine.reason)"

# A generic page redirected off its path quarantines both of its format keys' entries.
src="$TEST_TMPDIR/gs23"
mkdir -p "$src"
printf '%s\n' '# Page' 'body' >"$src/page"
C="$TEST_TMPDIR/gc23"
env -u FETCH_DOCS_FIXTURE_DIR PATH="$SHIM:$PATH" CURL_SHIM_LOG="$src.log" CURL_SHIM_SRC="$src" FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" \
  DOCS_CACHE_NOW=$T1 bash "$SCRIPT" --profile generic --out "$TEST_TMPDIR/out23j" --cache --cache-dir "$C" https://docs.test/guide/page
printf '%s' 'https://docs.test/elsewhere/page' >"$src/page.effective"
env -u FETCH_DOCS_FIXTURE_DIR PATH="$SHIM:$PATH" CURL_SHIM_LOG="$src.log" CURL_SHIM_SRC="$src" FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" \
  DOCS_CACHE_NOW=$T2 bash "$SCRIPT" --profile generic --out "$TEST_TMPDIR/out23k" --cache --cache-dir "$C" --max-age 0 https://docs.test/guide/page
assert_eq "edge: page redirected: a generic page landing off its path is unread and quarantined" "redirected-off-path redirected-off-path" \
  "$(jq -r '.pages[0].reason' "$TEST_TMPDIR/out23k/manifest.json") $(DC info "$(DC key https://docs.test/guide/page markdown)" | jq -r .quarantine.reason)"

# --- Case 24: a pointer switched between choosing and serving an entry -----------
# A jq stand-in runs the real jq and, after the first meta.json read (the cache
# lookup that picks the entry), points the key at an older entry, as a racing
# writer could. The served record must keep the chosen entry's validated time.
src="$TEST_TMPDIR/gs24"
mkdir -p "$src"
C="$TEST_TMPDIR/gc24"
RACE_URL='https://docs.test/guide/race'
printf '%s\n' '# Race' 'one' >"$TEST_TMPDIR/race1.md"
printf '%s\n' '# Race' 'two' >"$TEST_TMPDIR/race2.md"
race_key="$(printf '%s\n%s' "$RACE_URL" markdown | sha256sum | cut -d' ' -f1)"
DOCS_CACHE_NOW=$T1 DC put "$RACE_URL" markdown "$TEST_TMPDIR/race1.md" text/markdown >/dev/null
DOCS_CACHE_NOW=$T2 DC put "$RACE_URL" markdown "$TEST_TMPDIR/race2.md" text/markdown >/dev/null
JQBIN="$TEST_TMPDIR/jqbin"
mkdir -p "$JQBIN"
cat >"$JQBIN/jq" <<EOF
#!/usr/bin/env bash
if [[ ! -e "$TEST_TMPDIR/race.flag" ]]; then
  for a in "\$@"; do
    if [[ "\$a" == */meta.json ]]; then
      : >"$TEST_TMPDIR/race.flag"
      "$(command -v jq)" "\$@"
      rc=\$?
      printf '%s-%s\t%s\t%s\n' "$race_key" "$(sha256sum <"$TEST_TMPDIR/race1.md" | cut -d' ' -f1)" "$((T1 + 50))" x >"$C/keys/${race_key:0:16}"
      exit \$rc
    fi
  done
fi
exec "$(command -v jq)" "\$@"
EOF
chmod +x "$JQBIN/jq"
env -u FETCH_DOCS_FIXTURE_DIR PATH="$JQBIN:$SHIM:$PATH" CURL_SHIM_LOG="$src.log" CURL_SHIM_SRC="$src" FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" \
  DOCS_CACHE_NOW=$((T2 + 100)) bash "$SCRIPT" --profile generic --out "$TEST_TMPDIR/out24" --cache --cache-dir "$C" "$RACE_URL"
assert_eq "race: a pointer switched after the lookup still serves the chosen entry with its own validated time and age" \
  "cache $(sha256sum <"$TEST_TMPDIR/race2.md" | cut -d' ' -f1) 2001-09-09T01:48:20Z 100" \
  "$(jq -r '.pages[0] | "\(.source) \(.sha256) \(.validated) \(.age_seconds)"' "$TEST_TMPDIR/out24/manifest.json")"

# --- Case: publisher profiles ---------------------------------------------------
fx="$TEST_TMPDIR/fxp"
mkdir -p "$fx"
printf '%s\n' '# Docs' '- [Skills](https://code.claude.com/docs/en/skills.md): skills' >"$fx/llms.txt"
printf '%s\n' '# Skills' >"$fx/skills.md"
FETCH_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --out "$TEST_TMPDIR/outp-default" skills >/dev/null
FETCH_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --profile anthropic --out "$TEST_TMPDIR/outp-named" skills >/dev/null
assert_eq "profile: the default profile is anthropic" \
  "$(jq -S 'del(.pages[].retrieved, .index.retrieved, .pages[].validated, .index.validated) | del(.pages[].file, .index.file)' "$TEST_TMPDIR/outp-named/manifest.json")" \
  "$(jq -S 'del(.pages[].retrieved, .index.retrieved, .pages[].validated, .index.validated) | del(.pages[].file, .index.file)' "$TEST_TMPDIR/outp-default/manifest.json")"
assert_eq "profile: anthropic index and page resolve" "read read https://code.claude.com/docs/llms.txt https://code.claude.com/docs/en/skills.md" \
  "$(jq -r '"\(.index.state) \(.pages[0].state) \(.index.url) \(.pages[0].url)"' "$TEST_TMPDIR/outp-default/manifest.json")"
rc=0
err="$(FETCH_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --profile nope --out "$TEST_TMPDIR/outp-bad" skills 2>&1 >/dev/null)" || rc=$?
assert_eq "profile: an unknown profile is fatal" 2 "$rc"
assert_eq "profile: the error names the profile" "ERROR: unknown profile: nope (known: anthropic, platform, generic)" "$err"
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

# --- platform profile -------------------------------------------------------------
fx="$TEST_TMPDIR/fxplat"
mkdir -p "$fx/build-with-claude"
printf '%s\n' '# Docs' '- [Overview](https://platform.claude.com/docs/en/build-with-claude/overview.md): o' >"$fx/llms.txt"
printf '%s\n' '# Overview' >"$fx/build-with-claude/overview.md"
FETCH_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --profile platform --out "$TEST_TMPDIR/outplat" build-with-claude/overview >/dev/null
assert_eq "platform: index at the platform root, pages under /docs/" \
  "https://platform.claude.com/llms.txt read https://platform.claude.com/docs/en/build-with-claude/overview.md markdown" \
  "$(jq -r '"\(.index.url) \(.pages[0].state) \(.pages[0].url) \(.pages[0].format)"' "$TEST_TMPDIR/outplat/manifest.json")"
# Over the curl stand-in: the index lives at the origin root, outside /docs/.
src="$TEST_TMPDIR/served-plat"
mkdir -p "$src"
printf '%s\n' '# Docs' '- [Overview](https://platform.claude.com/docs/en/build-with-claude/overview.md): o' >"$src/llms.txt"
printf '%s\n' '# Overview' 'body' >"$src/overview.md"
plat_run() {
  env -u FETCH_DOCS_FIXTURE_DIR PATH="$SHIM:$PATH" CURL_SHIM_LOG="$src.log" CURL_SHIM_SRC="$src" \
    FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" bash "$SCRIPT" --profile platform --out "$TEST_TMPDIR/$1" build-with-claude/overview
}
plat_run outplat2
assert_eq "platform: a fetched index at the origin root is read, and so is its page" "read read markdown" \
  "$(jq -r '"\(.index.state) \(.pages[0].state) \(.pages[0].format)"' "$TEST_TMPDIR/outplat2/manifest.json")"
printf '%s' 'https://platform.claude.com/elsewhere/llms.txt' >"$src/llms.txt.effective"
plat_run outplat3
assert_eq "platform: an index request landing anywhere but the index URL is still unread" "unread redirected-off-origin index-unread" \
  "$(jq -r '"\(.index.state) \(.index.reason) \(.pages[0].reason)"' "$TEST_TMPDIR/outplat3/manifest.json")"

# --- generic profile: negotiation, validators, identity, conversion --------------
G1=1000000000
G1_ISO='2001-09-09T01:46:40Z'
G2=1000000100
G2_ISO='2001-09-09T01:48:20Z'
PAGE_URL='https://docs.test/guide/page'
PY_LOG="$TEST_TMPDIR/py.log"
export PY_LOG
CONV="$TEST_TMPDIR/conv.sh"
cat >"$CONV" <<'EOF'
#!/usr/bin/env bash
printf 'PYTHONUTF8=%s\n' "${PYTHONUTF8:-}" >>"$PY_LOG"
sed -e 's|<h1>\(.*\)</h1>|# \1|' -e 's/<[^>]*>//g' "$1" | grep -v '^[[:space:]]*$'
EOF
# mk_py <dir> <name> <probe output>: a python stand-in whose probe prints the
# given output and which runs the converter with bash otherwise.
mk_py() {
  mkdir -p "$1"
  cat >"$1/$2" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == -c ]]; then printf '$2 probed\n' >>"\$PY_LOG"; printf '%s' '$3'; exit 0; fi
printf '$2 ran\n' >>"\$PY_LOG"
exec bash "\$@"
EOF
  chmod +x "$1/$2"
}
PYOK="$TEST_TMPDIR/pyok"
mk_py "$PYOK" python3 $'3\r\n'
mk_py "$PYOK" python 3
PYSKIP="$TEST_TMPDIR/pyskip"
mk_py "$PYSKIP" python3 ''
mk_py "$PYSKIP" python 3
PYNONE="$TEST_TMPDIR/pynone"
mk_py "$PYNONE" python3 ''
mk_py "$PYNONE" python 2

# gen_run <served dir> <out> <python dir> <now> <args...>: the generic profile
# through the curl stand-in, with the stand-in converter and cache.
gen_run() {
  local src="$1" out="$2" py="$3" now="$4"
  shift 4
  env -u FETCH_DOCS_FIXTURE_DIR PATH="$py:$SHIM:$PATH" CURL_SHIM_LOG="$src.log" CURL_SHIM_SRC="$src" \
    FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" FETCH_DOCS_HTML2MD="${GEN_CONV:-$CONV}" DOCS_CACHE_NOW="$now" \
    bash "$SCRIPT" --profile generic --out "$TEST_TMPDIR/$out" "$@"
}
gpage() { jq -r ".pages[0] | $2" "$TEST_TMPDIR/$1/manifest.json"; }
key_of() { printf '%s\n%s' "$1" "$2" | sha256sum | cut -d' ' -f1; }
entry_dirs() { find "$1/entries" -mindepth 1 -maxdepth 1 -type d ! -name '.tmp-*' | wc -l | tr -d ' '; }
html_page() { printf '<html><head><title>%s</title></head><body>\n<h1>%s</h1>\n<p>%s</p>\n</body></html>\n' "$2" "$2" "$3" >"$1"; }

# Markdown by Accept, with an ETag: the revalidation is a 304.
src="$TEST_TMPDIR/gs-etag"
mkdir -p "$src"
printf '%s\n' '# Page' 'body' >"$src/page"
printf '%s' '"v1"' >"$src/page.etag"
C="$TEST_TMPDIR/gc-etag"
gen_run "$src" go-e1 "$PYOK" $G1 --cache --cache-dir "$C" "$PAGE_URL"
assert_eq "generic: Accept: text/markdown is the first channel; slug is host/path" \
  "read markdown docs-test/guide/page 200" "$(gpage go-e1 '"\(.state) \(.format) \(.slug) \(.status)"')"
assert_eq "generic: the first request asks for markdown" 1 "$(grep -c -- '-H Accept: text/markdown' "$src.log")"
assert_eq "generic: the index record is null" null "$(jq -c .index "$TEST_TMPDIR/go-e1/manifest.json")"
gen_run "$src" go-e2 "$PYOK" $G2 --cache --cache-dir "$C" --max-age 0 "$PAGE_URL"
assert_eq "validators: the revalidation carries If-None-Match" 1 "$(grep -c -- '-H If-None-Match: "v1"' "$src.log")"
assert_eq "validators: an ETag 304 serves the entry, moves validated, keeps retrieved" \
  "read cache 304 $G1_ISO $G2_ISO 0 markdown" \
  "$(gpage go-e2 '"\(.state) \(.source) \(.status) \(.retrieved) \(.validated) \(.age_seconds) \(.format)"')"
assert_eq "validators: a 304 writes the page file from the entry" "" "$(cmp "$src/page" "$TEST_TMPDIR/go-e2/docs-test/guide/page.md" 2>&1)"
assert_eq "validators: a 304 adds no entry" 1 "$(entry_dirs "$C")"

# Last-Modified then 304; Last-Modified equal to Date is absent.
src="$TEST_TMPDIR/gs-lm"
mkdir -p "$src"
printf '%s\n' '# Page' 'body' >"$src/page"
printf '%s' 'Sat, 08 Sep 2001 00:00:00 GMT' >"$src/page.lastmod"
C="$TEST_TMPDIR/gc-lm"
gen_run "$src" go-l1 "$PYOK" $G1 --cache --cache-dir "$C" "$PAGE_URL"
gen_run "$src" go-l2 "$PYOK" $G2 --cache --cache-dir "$C" --max-age 0 "$PAGE_URL"
assert_eq "validators: the revalidation carries If-Modified-Since" 1 "$(grep -c -- '-H If-Modified-Since: Sat, 08 Sep 2001 00:00:00 GMT' "$src.log")"
assert_eq "validators: a Last-Modified 304 moves validated and keeps retrieved" "cache 304 $G1_ISO $G2_ISO" \
  "$(gpage go-l2 '"\(.source) \(.status) \(.retrieved) \(.validated)"')"
src="$TEST_TMPDIR/gs-lmdate"
mkdir -p "$src"
printf '%s\n' '# Page' 'body' >"$src/page"
printf '%s' 'Mon, 01 Jan 2001 00:00:00 GMT' >"$src/page.lastmod"
C="$TEST_TMPDIR/gc-lmdate"
gen_run "$src" go-d1 "$PYOK" $G1 --cache --cache-dir "$C" "$PAGE_URL"
gen_run "$src" go-d2 "$PYOK" $G2 --cache --cache-dir "$C" --max-age 0 "$PAGE_URL"
assert_eq "edge: Last-Modified equal to Date is not a validator" 0 "$(grep -c -- 'If-Modified-Since' "$src.log")"
assert_eq "edge: so the revalidation is a refetch, same sha, validated moved" "fetch 200 $G1_ISO $G2_ISO" \
  "$(gpage go-d2 '"\(.source) \(.status) \(.retrieved) \(.validated)"')"

# No validator: same bytes move validated only; changed bytes are a new entry.
src="$TEST_TMPDIR/gs-none"
mkdir -p "$src"
printf '%s\n' '# Page' 'one' >"$src/page"
C="$TEST_TMPDIR/gc-none"
gen_run "$src" go-n1 "$PYOK" $G1 --cache --cache-dir "$C" "$PAGE_URL"
gen_run "$src" go-n2 "$PYOK" $G2 --cache --cache-dir "$C" --max-age 0 "$PAGE_URL"
assert_eq "validators: none and the same bytes: no conditional header, validated moves, retrieved stays" \
  "0 fetch $G1_ISO $G2_ISO 1" \
  "$(grep -c -- 'If-' "$src.log") $(gpage go-n2 '"\(.source) \(.retrieved) \(.validated)"') $(entry_dirs "$C")"
printf '%s\n' '# Page' 'two' >"$src/page"
gen_run "$src" go-n3 "$PYOK" $G2 --cache --cache-dir "$C" --max-age 0 "$PAGE_URL"
assert_eq "validators: none and changed bytes: a new entry with a new retrieved" "$G2_ISO $G2_ISO 2 false" \
  "$(gpage go-n3 '"\(.retrieved) \(.validated)"') $(entry_dirs "$C") $(gpage go-n3 .quarantined)"

# One URL negotiating to markdown, then to HTML: two keys.
src="$TEST_TMPDIR/gs-neg"
mkdir -p "$src"
html_page "$src/page" Page 'html body'
printf '%s' 'text/html; charset=utf-8' >"$src/page.ctype"
printf '%s\n' '# Page' 'md body' >"$src/page.accept-md"
C="$TEST_TMPDIR/gc-neg"
gen_run "$src" go-g1 "$PYOK" $G1 --cache --cache-dir "$C" "$PAGE_URL"
rm -f "$src/page.accept-md"
: >"$PY_LOG"
gen_run "$src" go-g2 "$PYOK" $G2 --cache --cache-dir "$C" --max-age 0 "$PAGE_URL"
assert_eq "edge: same URL negotiated to markdown then HTML is two cache keys" \
  "markdown $(key_of "$PAGE_URL" markdown) html-converted $(key_of "$PAGE_URL" html-converted)" \
  "$(gpage go-g1 '"\(.format) \(.cache_key)"') $(gpage go-g2 '"\(.format) \(.cache_key)"')"
assert_eq "html: the converted page is the converter's output" "$(printf '%s\n' 'Page' '# Page' 'html body')" \
  "$(cat "$TEST_TMPDIR/go-g2/docs-test/guide/page.md")"
assert_eq "html: the converter runs under PYTHONUTF8=1 with the first passing python" "$(printf '%s\n' 'python3 probed' 'python3 ran' 'PYTHONUTF8=1')" "$(cat "$PY_LOG")"
assert_eq "html: the title is recorded and the HTML content type kept" "Page text/html; charset=utf-8" \
  "$(gpage go-g2 '"\(.title) \(.content_type)"')"
assert_eq "html: the .md suffix and llms.txt were tried before converting" "1 1" \
  "$(grep -cF 'https://docs.test/guide/page.md' "$src.log") $(grep -cF 'https://docs.test/llms.txt' "$src.log")"

# .md suffix and the llms.txt bundle as markdown channels.
src="$TEST_TMPDIR/gs-sfx"
mkdir -p "$src"
html_page "$src/page" Page body
printf '%s' 'text/html' >"$src/page.ctype"
printf '%s\n' '# Page' 'from suffix' >"$src/page.md"
gen_run "$src" go-s1 "$PYNONE" $G1 "$PAGE_URL"
assert_eq "generic: an HTML answer falls through to the .md suffix" "read markdown from suffix" \
  "$(gpage go-s1 '"\(.state) \(.format)"') $(sed -n 2p "$TEST_TMPDIR/go-s1/docs-test/guide/page.md")"
src="$TEST_TMPDIR/gs-bundle"
mkdir -p "$src"
html_page "$src/page" Page body
printf '%s' 'text/html' >"$src/page.ctype"
printf '%s\n' '# Site' '- [Page](/guide/page.txt): the page' '- [Other](https://elsewhere.test/guide/page.txt): no' >"$src/llms.txt"
printf '%s\n' '# Page' 'from bundle' >"$src/page.txt"
printf '%s' 'text/plain' >"$src/page.txt.ctype"
gen_run "$src" go-b1 "$PYNONE" $G1 "$PAGE_URL"
assert_eq "generic: a same-origin llms.txt link for the path is the third channel" "read markdown from bundle" \
  "$(gpage go-b1 '"\(.state) \(.format)"') $(sed -n 2p "$TEST_TMPDIR/go-b1/docs-test/guide/page.md")"

# A retitled page quarantines its key.
src="$TEST_TMPDIR/gs-title"
mkdir -p "$src"
printf '%s\n' '# Alpha' 'body' >"$src/page"
C="$TEST_TMPDIR/gc-title"
gen_run "$src" go-t1 "$PYOK" $G1 --cache --cache-dir "$C" "$PAGE_URL"
printf '%s\n' '# Beta' 'body' >"$src/page"
gen_run "$src" go-t2 "$PYOK" $G2 --cache --cache-dir "$C" --max-age 0 "$PAGE_URL"
assert_eq "identity: a first read is not quarantined" "Alpha false" "$(gpage go-t1 '"\(.title) \(.quarantined)"')"
assert_eq "identity: a title change between fetches quarantines the key" "Beta true" "$(gpage go-t2 '"\(.title) \(.quarantined)"')"
assert_eq "identity: the cache records both titles" "Alpha Beta" \
  "$(bash "$SCRIPT_DIR/docs-cache.sh" --cache-dir "$C" info "$(key_of "$PAGE_URL" markdown)" | jq -r '.quarantine | "\(.from_title) \(.to_title)"')"

# A redirect off the requested path is unread, and no other channel is tried.
src="$TEST_TMPDIR/gs-redir"
mkdir -p "$src"
printf '%s\n' '# Other' >"$src/page"
printf '%s' 'https://docs.test/guide/other-page' >"$src/page.effective"
printf '%s\n' '# Page' >"$src/page.md"
gen_run "$src" go-r1 "$PYOK" $G1 "$PAGE_URL"
assert_eq "edge: a redirect off the requested path is unread" "unread redirected-off-path" "$(gpage go-r1 '"\(.state) \(.reason)"')"
assert_no_file "edge: a redirect off path leaves no page file" "$TEST_TMPDIR/go-r1/docs-test/guide/page.md"
assert_eq "edge: a redirect off path tries no other channel" 1 "$(wc -l <"$src.log" | tr -d ' ')"
printf '%s' 'https://elsewhere.test/guide/page' >"$src/page.effective"
gen_run "$src" go-r2 "$PYOK" $G1 "$PAGE_URL"
assert_eq "generic: a redirect off origin is unread" "unread redirected-off-origin" "$(gpage go-r2 '"\(.state) \(.reason)"')"

# Python resolution.
src="$TEST_TMPDIR/gs-py"
mkdir -p "$src"
html_page "$src/page" Page body
printf '%s' 'text/html' >"$src/page.ctype"
gen_run "$src" go-p1 "$PYNONE" $G1 "$PAGE_URL"
assert_eq "html: no python that passes the probe is unread no-python" "unread no-python" "$(gpage go-p1 '"\(.state) \(.reason)"')"
assert_no_file "html: no-python leaves no page file" "$TEST_TMPDIR/go-p1/docs-test/guide/page.md"
: >"$PY_LOG"
gen_run "$src" go-p2 "$PYSKIP" $G1 "$PAGE_URL"
assert_eq "html: a python3 that fails the probe is skipped for python" "read html-converted" "$(gpage go-p2 '"\(.state) \(.format)"')"
assert_eq "html: python3 was probed and never ran; python ran" "$(printf '%s\n' 'python3 probed' 'python probed' 'python ran' 'PYTHONUTF8=1')" "$(cat "$PY_LOG")"
GEN_CONV="$TEST_TMPDIR/absent.py" gen_run "$src" go-p3 "$PYOK" $G1 "$PAGE_URL" 2>/dev/null
assert_eq "html: a missing converter is unread converter-missing" "unread converter-missing" "$(gpage go-p3 '"\(.state) \(.reason)"')"

# Targets the generic profile refuses.
gen_run "$src" go-x "$PYOK" $G1 skills 'http://docs.test/a' >/dev/null
assert_eq "generic: a slug or a non-https URL is unread invalid-url" "invalid-url invalid-url" \
  "$(jq -r '[.pages[].reason] | join(" ")' "$TEST_TMPDIR/go-x/manifest.json")"
rc=0
gen_run "$src" go-y "$PYOK" $G1 --discover >/dev/null 2>&1 || rc=$?
assert_eq "generic: --discover is fatal" 2 "$rc"

# An indexed profile revalidates with its stored ETag too.
src="$(new_served served-idx-etag)"
printf '%s' '"s1"' >"$src/skills.md.etag"
C="$TEST_TMPDIR/gc-idx"
DOCS_CACHE_NOW=$G1 shim_run "$src" "$TEST_TMPDIR/out-ie1" --cache --cache-dir "$C" skills
DOCS_CACHE_NOW=$G2 shim_run "$src" "$TEST_TMPDIR/out-ie2" --cache --cache-dir "$C" --max-age 0 skills
assert_eq "validators: an indexed page revalidates with If-None-Match and a 304" "cache 304 $G1_ISO $G2_ISO" \
  "$(page "$TEST_TMPDIR/out-ie2/manifest.json" skills '"\(.source) \(.status) \(.retrieved) \(.validated)"')"
assert_eq "validators: the conditional request named the stored ETag" 1 "$(grep -c -- 'If-None-Match: "s1"' "$src.log")"

echo
if [[ $FAILED -eq 0 ]]; then
  printf 'All %d assertions passed.\n' "$CASE_NUM"
else
  printf '%d of %d assertions failed.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
