#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fetch-docs.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
while IFS= read -r v; do unset "$v"; done < <(compgen -e DOCS_CACHE_)
export HOME="$TEST_TMPDIR/suite-home" XDG_CONFIG_HOME="$TEST_TMPDIR/suite-config"

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
# text/markdown, or as the type in <name>.accept-md.ctype. A file that is not served exits 22 with no output, and a
# <name>.partial file is written and then fails with curl's short-transfer
# code, like a body cut off mid-download. A body over --max-filesize exits 63
# with no output, as curl does for a declared Content-Length, unless a
# <name>.nocap sidecar makes it ignore the limit, as an older curl does for a
# body sent without one.
SHIM="$TEST_TMPDIR/shim"
mkdir -p "$SHIM"
cat >"$SHIM/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_SHIM_LOG"
out="" url="" wfmt="" hdr="" accept="" inm="" ims="" maxfs=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -o | -w | -D | -H | --connect-timeout | --max-time | --proto | --proto-redir | --max-redirs | --max-filesize)
    [[ "$1" == "-o" ]] && out="$2"
    [[ "$1" == "-w" ]] && wfmt="$2"
    [[ "$1" == "-D" ]] && hdr="$2"
    [[ "$1" == "--max-filesize" ]] && maxfs="$2"
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
  [[ -f "$src.accept-md.ctype" ]] && ctype="$(cat "$src.accept-md.ctype")"
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
if [[ -n "$body" && -n "$maxfs" && ! -f "$src.nocap" && $(wc -c <"$body") -gt $maxfs ]]; then exit 63; fi
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

fixture_run() {
  local fx="$1" out="$2"
  shift 2
  FETCH_DOCS_FIXTURE_DIR="$fx" FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" \
    bash "$SCRIPT" --index-url "$INDEX" --out "$out" "$@"
}

shim_run() {
  local src="$1" out="$2"
  shift 2
  env -u FETCH_DOCS_FIXTURE_DIR PATH="$SHIM:$PATH" CURL_SHIM_LOG="$src.log" CURL_SHIM_SRC="$src" \
    FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" bash "$SCRIPT" --index-url "$INDEX" --out "$out" "$@"
}

page() {
  jq -r --arg s "$2" ".pages[] | select(.slug == \$s) | $3" "$1"
}

new_served() {
  local d="$TEST_TMPDIR/$1"
  mkdir -p "$d"
  mk_index "$d"
  printf '%s\n' '# Skills' 'body of skills' >"$d/skills.md"
  printf '%s\n' '# Settings' 'body of settings' >"$d/settings-reference.md"
  printf '%s' "$d"
}

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

fx="$TEST_TMPDIR/fx3"
mkdir -p "$fx"
mk_index "$fx"
fixture_run "$fx" "$TEST_TMPDIR/out3" skills
assert_eq "case 3: fixture-missing" "unread fixture-missing" "$(page "$TEST_TMPDIR/out3/manifest.json" skills '"\(.state) \(.reason)"')"

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

src="$(new_served served5)"
printf '%s\n' 'not found' >"$src/skills.md"
printf '%s' 404 >"$src/skills.md.status"
shim_run "$src" "$TEST_TMPDIR/out5" skills
m="$TEST_TMPDIR/out5/manifest.json"
assert_eq "case 5: 404 is unread" "unread http-404" "$(page "$m" skills '"\(.state) \(.reason)"')"
assert_eq "case 5: the status is recorded" 404 "$(page "$m" skills .status)"
assert_no_file "case 5: no page file" "$TEST_TMPDIR/out5/skills.md"

src="$(new_served served6)"
printf '%s' 'text/html; charset=utf-8' >"$src/skills.md.ctype"
shim_run "$src" "$TEST_TMPDIR/out6" skills
m="$TEST_TMPDIR/out6/manifest.json"
assert_eq "case 6: html is unread" "unread unexpected-content-type" "$(page "$m" skills '"\(.state) \(.reason)"')"
assert_eq "case 6: the content type is recorded" "text/html; charset=utf-8" "$(page "$m" skills .content_type)"
assert_no_file "case 6: no page file" "$TEST_TMPDIR/out6/skills.md"

src="$(new_served served7)"
: >"$src/skills.md"
mkdir -p "$TEST_TMPDIR/out7"
printf 'stale' >"$TEST_TMPDIR/out7/skills.md"
shim_run "$src" "$TEST_TMPDIR/out7" skills
assert_eq "case 7: empty body is unread" "unread empty-body" "$(page "$TEST_TMPDIR/out7/manifest.json" skills '"\(.state) \(.reason)"')"
assert_no_file "case 7: no file, stale or partial" "$TEST_TMPDIR/out7/skills.md"
assert_no_file "case 7: no partial file left" "$TEST_TMPDIR/out7/skills.md.part"

src="$(new_served served8)"
printf 'half of a pa' >"$src/skills.md.partial"
shim_run "$src" "$TEST_TMPDIR/out8" skills
assert_eq "case 8: truncated body is unread" "unread fetch-failed" "$(page "$TEST_TMPDIR/out8/manifest.json" skills '"\(.state) \(.reason)"')"
assert_no_file "case 8: no file, no partial" "$TEST_TMPDIR/out8/skills.md"
assert_no_file "case 8: no .part left" "$TEST_TMPDIR/out8/skills.md.part"

src="$(new_served served9)"
printf '%s' 'https://elsewhere.example/docs/en/skills.md' >"$src/skills.md.effective"
shim_run "$src" "$TEST_TMPDIR/out9" skills
assert_eq "case 9: off-origin landing is unread" "unread redirected-off-origin" "$(page "$TEST_TMPDIR/out9/manifest.json" skills '"\(.state) \(.reason)"')"
assert_no_file "case 9: no page file" "$TEST_TMPDIR/out9/skills.md"

src="$(new_served served10)"
printf '%s\n' '# Vars' >"$src/env-vars.md"
shim_run "$src" "$TEST_TMPDIR/out10" env-vars
assert_eq "case 10: off-origin link is unread" "unread off-origin" "$(page "$TEST_TMPDIR/out10/manifest.json" env-vars '"\(.state) \(.reason)"')"
assert_eq "case 10: no page request" 0 "$(grep -c 'env-vars' "$src.log")"

src="$(new_served served11)"
shim_run "$src" "$TEST_TMPDIR/out11" skills settings-reference
total="$(wc -l <"$src.log" | tr -d ' ')"
assert_eq "case 11: three requests, the index and two pages" 3 "$total"
assert_eq "case 11: every request is HTTPS only, redirects included and capped" "$total" "$(grep -c -- '--proto =https --proto-redir =https --max-redirs 5 ' "$src.log")"
assert_eq "case 11: every request carries a connect timeout and a max time" "$total" "$(grep -c -- '--connect-timeout [0-9]* --max-time [0-9]' "$src.log")"
assert_eq "case 11: every request opens with -q, so no curlrc is read" "$total" "$(grep -c '^-q ' "$src.log")"
assert_eq "case 11: without --public-only no request is pinned" 0 "$(grep -c -- '--connect-to' "$src.log")"
assert_eq "case 11: a fetched page records its status and content type" "200 text/markdown; charset=utf-8" "$(page "$TEST_TMPDIR/out11/manifest.json" skills '"\(.status) \(.content_type)"')"

src="$(new_served served12)"
printf 'a\001b\r\nc\033[0md\177\n' >"$src/skills.md"
shim_run "$src" "$TEST_TMPDIR/out12" skills
m="$TEST_TMPDIR/out12/manifest.json"
assert_eq "case 12: sha256 is of the raw bytes" "$(sha256sum <"$src/skills.md" | cut -d' ' -f1)" "$(page "$m" skills .sha256)"
assert_eq "case 12: bytes are the raw count" "$(wc -c <"$src/skills.md" | tr -d ' ')" "$(page "$m" skills .bytes)"
assert_eq "case 12: the file on disk is byte-identical" "" "$(cmp "$src/skills.md" "$TEST_TMPDIR/out12/skills.md" 2>&1)"

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

fx="$TEST_TMPDIR/fx14"
mkdir -p "$fx"
mk_index "$fx"
printf 'x\n' >"$fx/skills.md"
printf 'y\n' >"$fx/settings-reference.md"
fixture_run "$fx" "$TEST_TMPDIR/out14" skills --mode search settings-reference
m="$TEST_TMPDIR/out14/manifest.json"
assert_eq "case 14: modes per page" "full search" "$(page "$m" skills .mode) $(page "$m" settings-reference .mode)"

src="$(new_served served15)"
shim_run "$src" "$TEST_TMPDIR/out15" --discover
m="$TEST_TMPDIR/out15/manifest.json"
assert_eq "case 15: the two origin pages, not the off-origin link" "settings-reference skills" "$(jq -r '[.pages[].slug] | sort | join(" ")' "$m")"
assert_eq "case 15: both read" "read read" "$(jq -r '[.pages[].state] | join(" ")' "$m")"

src="$(new_served served16)"
rm -f "$src/llms.txt"
shim_run "$src" "$TEST_TMPDIR/out16" skills
m="$TEST_TMPDIR/out16/manifest.json"
assert_eq "case 16: index unread" "unread fetch-failed" "$(jq -r '.index | "\(.state) \(.reason)"' "$m")"
assert_eq "case 16: page unread index-unread" "unread index-unread" "$(page "$m" skills '"\(.state) \(.reason)"')"
assert_eq "case 16: only the index was requested" 1 "$(wc -l <"$src.log" | tr -d ' ')"

fx="$TEST_TMPDIR/fx17"
mkdir -p "$fx"
mk_index "$fx"
fixture_run "$fx" "$TEST_TMPDIR/out17" '../escape'
assert_eq "case 17: invalid slug" "unread invalid-slug" "$(jq -r '.pages[0] | "\(.state) \(.reason)"' "$TEST_TMPDIR/out17/manifest.json")"

rc=0
bash "$SCRIPT" --out "$TEST_TMPDIR/out18" >/dev/null 2>&1 || rc=$?
assert_eq "case 18: no page and no --discover" 2 "$rc"
rc=0
bash "$SCRIPT" skills >/dev/null 2>&1 || rc=$?
assert_eq "case 18: no --out" 2 "$rc"
rc=0
bash "$SCRIPT" --out "$TEST_TMPDIR/out18" --index-url http://docs.test/docs/llms.txt skills >/dev/null 2>&1 || rc=$?
assert_eq "case 18: a non-https index URL" 2 "$rc"

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

src="$TEST_TMPDIR/served20"
mkdir -p "$src"
printf '%s\n' '# Docs' '- [X](http://other.test/docs/en/x.md): x' >"$src/llms.txt"
shim_run "$src" "$TEST_TMPDIR/out20" x
assert_eq "case 20: non-https link is off-origin" "unread off-origin" "$(page "$TEST_TMPDIR/out20/manifest.json" x '"\(.state) \(.reason)"')"
printf '%s\n' '# Docs' '- [X](//other.test/docs/en/x.md): x' >"$src/llms.txt"
shim_run "$src" "$TEST_TMPDIR/out20r" x
assert_eq "case 20: protocol-relative link is off-origin" "unread off-origin" "$(page "$TEST_TMPDIR/out20r/manifest.json" x '"\(.state) \(.reason)"')"

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

CFGX="$TEST_TMPDIR/cfg22/claude-docs-cache"
mkdir -p "$CFGX"
cfg_run() {
  local out="$TEST_TMPDIR/$1"
  shift
  local envs=()
  while [[ "$1" != -- ]]; do
    envs+=("$1")
    shift
  done
  shift
  env XDG_CONFIG_HOME="$TEST_TMPDIR/cfg22" ${envs[@]+"${envs[@]}"} FETCH_DOCS_FIXTURE_DIR="$fx" FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" \
    bash "$SCRIPT" --index-url "$INDEX" --out "$out" "$@"
}
printf '%s\n' '{"ttl_seconds": 0}' >"$CFGX/config.json"
cfg_run out22c1 DOCS_CACHE_DIR="$TEST_TMPDIR/cache22c" -- --cache skills
cfg_run out22c2 DOCS_CACHE_DIR="$TEST_TMPDIR/cache22c" -- --cache skills
assert_eq "case 22c: ttl_seconds 0 in the file is the default --max-age: a stored page is not served" "fixture 1" \
  "$(page "$TEST_TMPDIR/out22c2/manifest.json" skills '"\(.source) \(.cache_key | length / 64)"')"
cfg_run out22c3 DOCS_CACHE_DIR="$TEST_TMPDIR/cache22c" -- --cache --max-age 86400 skills
assert_eq "case 22c: an explicit --max-age wins over ttl_seconds" cache "$(page "$TEST_TMPDIR/out22c3/manifest.json" skills .source)"
cfg_run out22c4 DOCS_CACHE_DIR="$TEST_TMPDIR/cache22c" DOCS_CACHE_TTL_SECONDS=86400 -- --cache skills
assert_eq "case 22c: DOCS_CACHE_TTL_SECONDS wins over the file" cache "$(page "$TEST_TMPDIR/out22c4/manifest.json" skills .source)"
assert_eq "case 22c: with the cache on, the manifest says nothing is disabled" null "$(jq -r .cache_disabled "$TEST_TMPDIR/out22c4/manifest.json")"
assert_eq "case 22c: without --cache nothing is disabled either" null "$(jq -r .cache_disabled "$TEST_TMPDIR/out22/manifest.json")"

printf '%s\n' '{"cache_enabled": false}' >"$CFGX/config.json"
cfg_run out22d1 DOCS_CACHE_DIR="$TEST_TMPDIR/cache22d" -- --cache skills
assert_eq "case 22c: cache_enabled false in the file: --cache reads as without it and the manifest names the layer" "read fixture null file" \
  "$(page "$TEST_TMPDIR/out22d1/manifest.json" skills '"\(.state) \(.source) \(.cache_key)"') $(jq -r .cache_disabled "$TEST_TMPDIR/out22d1/manifest.json")"
assert_no_file "case 22c: cache_enabled false writes no cache" "$TEST_TMPDIR/cache22d"
cfg_run out22d2 DOCS_CACHE_DIR="$TEST_TMPDIR/cache22d" DOCS_CACHE_ENABLED=true -- --cache skills
assert_eq "case 22c: DOCS_CACHE_ENABLED=true wins over the file" "1 null" \
  "$(page "$TEST_TMPDIR/out22d2/manifest.json" skills '.cache_key | length / 64') $(jq -r .cache_disabled "$TEST_TMPDIR/out22d2/manifest.json")"
rm -f "$CFGX/config.json"
rc=0
cfg_run out22d3 DOCS_CACHE_ENABLED=false -- --cache skills || rc=$?
assert_eq "case 22c: disabled by DOCS_CACHE_ENABLED, fixture mode needs no cache directory" "0 read env" \
  "$rc $(page "$TEST_TMPDIR/out22d3/manifest.json" skills .state) $(jq -r .cache_disabled "$TEST_TMPDIR/out22d3/manifest.json")"

printf '{"cache_dir": "%s"}\n' "$TEST_TMPDIR/cache22e" >"$CFGX/config.json"
rc=0
cfg_run out22e -- --cache skills 2>/dev/null || rc=$?
assert_eq "case 22c: in fixture mode a cache_dir from the machine file is not enough: fatal, nothing written" "2 0" \
  "$rc $([[ -e "$TEST_TMPDIR/cache22e" ]] && echo 1 || echo 0)"
src="$(new_served served22e)"
XDG_CONFIG_HOME="$TEST_TMPDIR/cfg22" shim_run "$src" "$TEST_TMPDIR/out22e2" --cache skills
assert_eq "case 22c: a fetch stores in the machine file's cache_dir" "1 1" \
  "$(page "$TEST_TMPDIR/out22e2/manifest.json" skills '.cache_key | length / 64') $([[ -f "$TEST_TMPDIR/cache22e/store_version" ]] && echo 1 || echo 0)"
printf '{' >"$CFGX/config.json"
rc=0
err="$(cfg_run out22e3 DOCS_CACHE_DIR="$TEST_TMPDIR/cache22e3" -- --cache skills 2>&1 >/dev/null)" || rc=$?
assert_eq "case 22c: a malformed machine file warns and the run goes on" "0 read 1" \
  "$rc $(page "$TEST_TMPDIR/out22e3/manifest.json" skills .state) $(grep -c '^WARNING: docs-cache config: .*config.json is not one JSON object' <<<"$err")"
rm -f "$CFGX/config.json"

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
rm -f "$src/skills.md.status"
cache_run $((T3 + 86401)) out23g2 --max-age 0 skills
assert_eq "edge: page back: a 200 under the title the 404 recorded lifts the quarantine, and the note is served again" "read false 1" \
  "$(page "$TEST_TMPDIR/out23g2/manifest.json" skills '"\(.state) \(.quarantined)"') $(DC note get "$skills_key" 2>/dev/null | grep -c 'Skills holds')"
settings_key="$(DC key https://docs.test/docs/en/settings-reference.md markdown)"
cache_run $T3 out23h --max-age 0 settings-reference
printf '%s\n' '# Docs' '- [Skills](https://docs.test/docs/en/skills.md): skills' >"$src/llms.txt"
cache_run $T3 out23i --max-age 0 settings-reference
assert_eq "edge: page removed from the index: not-in-index quarantines the key" "unread not-in-index not-in-index" \
  "$(page "$TEST_TMPDIR/out23i/manifest.json" settings-reference '"\(.state) \(.reason)"') $(DC info "$settings_key" | jq -r .quarantine.reason)"

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

mkdir -p "$TEST_TMPDIR/tbin"
# shellcheck disable=SC2016 # the stub script expands its own arguments
printf '#!/usr/bin/env bash\necho "$1" >"%s"\nshift\nexec "$@"\n' "$TEST_TMPDIR/timeout.log" >"$TEST_TMPDIR/tbin/timeout"
chmod +x "$TEST_TMPDIR/tbin/timeout"
PATH="$TEST_TMPDIR/tbin:$PATH" FETCH_DOCS_FIXTURE_DIR="$TEST_TMPDIR/nowhere" FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" \
  bash "$SCRIPT" --index-url "$INDEX" --out "$TEST_TMPDIR/out-to" skills || true
assert_eq "timeout: probe bounded to 30 s" 30 "$(cat "$TEST_TMPDIR/timeout.log" 2>/dev/null)"
assert_eq "timeout: version still read" 9.8.7 "$(jq -r .claude_version "$TEST_TMPDIR/out-to/manifest.json")"

fx="$TEST_TMPDIR/fxplat"
mkdir -p "$fx/build-with-claude"
printf '%s\n' '# Docs' '- [Overview](https://platform.claude.com/docs/en/build-with-claude/overview.md): o' >"$fx/llms.txt"
printf '%s\n' '# Overview' >"$fx/build-with-claude/overview.md"
FETCH_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --profile platform --out "$TEST_TMPDIR/outplat" build-with-claude/overview >/dev/null
assert_eq "platform: index at the platform root, pages under /docs/" \
  "https://platform.claude.com/llms.txt read https://platform.claude.com/docs/en/build-with-claude/overview.md markdown" \
  "$(jq -r '"\(.index.url) \(.pages[0].state) \(.pages[0].url) \(.pages[0].format)"' "$TEST_TMPDIR/outplat/manifest.json")"
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
mk_py() {
  mkdir -p "$1"
  cat >"$1/$2" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2" == "-I -c" ]]; then printf '$2 probed\n' >>"\$PY_LOG"; printf '%s' '$3'; exit 0; fi
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

src="$TEST_TMPDIR/gs-plainmd"
mkdir -p "$src"
printf '%s\n' '# Page' 'plain md' >"$src/page.md"
printf '%s' 'text/plain; charset=utf-8' >"$src/page.md.ctype"
gen_run "$src" go-pm1 "$PYNONE" $G1 "$PAGE_URL.md"
assert_eq "generic: a text/plain 2xx for a .md path is read as markdown on the first request" \
  "read markdown text/plain; charset=utf-8 1" \
  "$(gpage go-pm1 '"\(.state) \(.format) \(.content_type)"') $(wc -l <"$src.log" | tr -d ' ')"
assert_eq "generic: the .md page file is the body" "$(cat "$src/page.md")" "$(cat "$TEST_TMPDIR/go-pm1/docs-test/guide/page.md")"
src="$TEST_TMPDIR/gs-plainhtml"
mkdir -p "$src"
printf '%s\n' 'plain text, not markdown' >"$src/page"
printf '%s' 'text/plain' >"$src/page.ctype"
gen_run "$src" go-pm2 "$PYOK" $G1 "$PAGE_URL"
assert_eq "generic: text/plain for a non-.md path is refused" "unread unexpected-content-type" \
  "$(gpage go-pm2 '"\(.state) \(.reason)"')"

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

# X's logged-out shell: a 200 text/html body with Log in and Sign up links and no
# article text. The pass-through converter keeps the links the stand-in strips.
X_URL='https://x.com/someone/status/2117512471930167377'
X_FILE='x-com/someone/status/2117512471930167377.md'
X_LOGIN='redirect_after_login=%2Fsomeone%2Fstatus%2F2117512471930167377'
PASSTHRU="$TEST_TMPDIR/passthru.sh"
cat >"$PASSTHRU" <<'EOF'
#!/usr/bin/env bash
cat "$1"
EOF
x_shell() {
  printf '%s\n' '# Someone on X: "A post about agents" / X' '' "[Log in](https://x.com/i/flow/login?$X_LOGIN)" \
    "[Sign up](https://x.com/i/flow/signup?$X_LOGIN)" '' "Don't miss what's happening" \
    'People on X are the first to know.' '' '## Post' '' '[Someone](https://x.com/someone)' '' '[@someone](https://x.com/someone)' \
    '' '[Article](https://x.com/someone/article/2117512471930167377)' '' '12.3K' '' 'Views' '' \
    '## New to X?' '' 'Sign up now to get your own personalized timeline!'
}
src="$TEST_TMPDIR/gs-xwall"
mkdir -p "$src"
x_shell >"$src/2117512471930167377"
printf '%s' 'text/html; charset=utf-8' >"$src/2117512471930167377.ctype"
C="$TEST_TMPDIR/gc-xwall"
GEN_CONV="$PASSTHRU" gen_run "$src" go-w1 "$PYOK" $G1 --cache --cache-dir "$C" "$X_URL"
assert_eq "login-wall: X's converted logged-out shell is unread login-wall" "unread login-wall 200" \
  "$(gpage go-w1 '"\(.state) \(.reason) \(.status)"')"
assert_no_file "login-wall: the shell leaves no page file" "$TEST_TMPDIR/go-w1/$X_FILE"
assert_eq "login-wall: the shell is never cached" 0 "$(entry_dirs "$C" 2>/dev/null)"
{
  x_shell
  printf 'article text line %s of the post body.\n' {1..60}
} >"$src/2117512471930167377"
GEN_CONV="$PASSTHRU" gen_run "$src" go-w2 "$PYOK" $G1 "$X_URL"
assert_eq "login-wall: a full X article page with the same links is read" "read html-converted" \
  "$(gpage go-w2 '"\(.state) \(.format)"')"
assert_eq "login-wall: the article text is in the page file" 1 \
  "$(grep -c 'article text line 60 of' "$TEST_TMPDIR/go-w2/$X_FILE")"
x_shell >"$src/page"
printf '%s' 'text/html' >"$src/page.ctype"
GEN_CONV="$PASSTHRU" gen_run "$src" go-w3 "$PYOK" $G1 "$PAGE_URL"
assert_eq "login-wall: a non-X page with the same login links reads as before" "read html-converted" \
  "$(gpage go-w3 '"\(.state) \(.format)"')"
x_shell >"$TEST_TMPDIR/x-shell.md"
C="$TEST_TMPDIR/gc-xstored"
DOCS_CACHE_NOW=$G1 bash "$SCRIPT_DIR/docs-cache.sh" --cache-dir "$C" put "$X_URL" html-converted "$TEST_TMPDIR/x-shell.md" text/html >/dev/null
GEN_CONV="$PASSTHRU" gen_run "$src" go-w4 "$PYOK" $G1 --cache --cache-dir "$C" --max-age 86400 "$X_URL"
assert_eq "login-wall: a shell stored in the cache is served as unread login-wall" "unread login-wall cache null false" \
  "$(gpage go-w4 '"\(.state) \(.reason) \(.source) \(.cache_key) \(.stale)"')"
assert_no_file "login-wall: the cached shell leaves no page file" "$TEST_TMPDIR/go-w4/$X_FILE"
fx="$TEST_TMPDIR/fx-xwall"
mkdir -p "$fx/x-com/someone/status"
x_shell >"$fx/$X_FILE"
FETCH_DOCS_FIXTURE_DIR="$fx" FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" \
  bash "$SCRIPT" --profile generic --out "$TEST_TMPDIR/go-w5" "$X_URL"
assert_eq "login-wall: a fixture-served shell is unread login-wall" "unread login-wall fixture" \
  "$(gpage go-w5 '"\(.state) \(.reason) \(.source)"')"
assert_no_file "login-wall: the fixture shell leaves no page file" "$TEST_TMPDIR/go-w5/$X_FILE"

gen_run "$src" go-x "$PYOK" $G1 skills 'http://docs.test/a' >/dev/null
assert_eq "generic: a slug or a non-https URL is unread invalid-url" "invalid-url invalid-url" \
  "$(jq -r '[.pages[].reason] | join(" ")' "$TEST_TMPDIR/go-x/manifest.json")"
rc=0
gen_run "$src" go-y "$PYOK" $G1 --discover >/dev/null 2>&1 || rc=$?
assert_eq "generic: --discover is fatal" 2 "$rc"

pub_run() {
  : >"$1.log"
  env -u FETCH_DOCS_FIXTURE_DIR PATH="${4:+$4:}$SHIM:$PATH" CURL_SHIM_LOG="$1.log" CURL_SHIM_SRC="$1" \
    FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" FETCH_DOCS_ADDRESSES="$3" \
    bash "$SCRIPT" --profile generic --public-only --out "$TEST_TMPDIR/$2" "$PAGE_URL"
}
src="$TEST_TMPDIR/gs-pub"
mkdir -p "$src"
printf '%s\n' '# Page' >"$src/page"
pub_run "$src" pub1 'docs.test=93.184.216.34'
assert_eq "public-only: a host with only global addresses is read" "read" "$(gpage pub1 .state)"
assert_eq "public-only: every request connects only to the checked address, with no proxy" \
  "$(wc -l <"$src.log" | tr -d ' ')" "$(grep -c -- '^-q .*--noproxy \* --connect-to ::93\.184\.216\.34: ' "$src.log")"
pub_run "$src" pub2 'docs.test=2606:4700::1111'
assert_eq "public-only: a global IPv6 address is pinned in brackets" 1 "$(grep -c -- '--connect-to ::\[2606:4700::1111\]: ' "$src.log")"
for answer in 10.0.0.5 127.0.0.1 169.254.169.254 100.64.0.1 '93.184.216.34,192.168.1.1' ::1 fd00::1 fe80::1 ::ffff:127.0.0.1; do
  pub_run "$src" pub3 "docs.test=$answer"
  assert_eq "public-only: a DNS answer of $answer is unread private-address with no request" \
    "unread private-address 0" "$(gpage pub3 '"\(.state) \(.reason)"') $(wc -l <"$src.log" | tr -d ' ')"
done
pub_run "$src" pub4 'other.test=93.184.216.34'
assert_eq "public-only: a host that does not resolve is unread fetch-failed" "unread fetch-failed" "$(gpage pub4 '"\(.state) \(.reason)"')"
pub_run "$src" pub5 'docs.test=93.184.216.34' "$PYNONE"
assert_eq "public-only: no Python 3 to check with is unread address-unchecked" "unread address-unchecked 0" \
  "$(gpage pub5 '"\(.state) \(.reason)"') $(wc -l <"$src.log" | tr -d ' ')"
plant="$TEST_TMPDIR/planted-cwd"
mkdir -p "$plant"
printf 'open(%s, "w").write("ran")\n' "'$TEST_TMPDIR/planted-ran'" >"$plant/ipaddress.py"
(cd "$plant" && pub_run "$src" pub7 'docs.test=93.184.216.34' >/dev/null 2>&1)
assert_no_file "public-only: an ipaddress.py in the cwd is not imported" "$TEST_TMPDIR/planted-ran"
assert_eq "public-only: the address check still passes beside a planted module" "read" "$(gpage pub7 .state)"
printf '%s' 'https://intranet.corp/guide/page' >"$src/page.effective"
pub_run "$src" pub6 'docs.test=93.184.216.34 intranet.corp=10.0.0.5'
assert_eq "public-only: a redirect to an internal host is unread" "unread redirected-off-origin" "$(gpage pub6 '"\(.state) \(.reason)"')"
assert_eq "public-only: the redirected request was pinned to the checked address" 1 "$(grep -c -- '--connect-to ::93\.184\.216\.34: ' "$src.log")"
src="$TEST_TMPDIR/gs-pub-nobundle"
mkdir -p "$src" "$TEST_TMPDIR/pub-cwd"
printf '%s' '{}' >"$src/page"
printf '%s' 'application/json' >"$src/page.ctype"
printf '%s\n' '# Page' 'from a stray file' >"$src/page.txt"
printf '%s' 'text/plain' >"$src/page.txt.ctype"
printf '%s\n' '- [Page](/guide/page.txt)' >"$TEST_TMPDIR/pub-cwd/93.184.216.34"
(cd "$TEST_TMPDIR/pub-cwd" && pub_run "$src" pub7 'docs.test=93.184.216.34')
assert_eq "public-only: an origin with no llms.txt has no bundle channel" "unread 0" \
  "$(gpage pub7 .state) $(grep -c 'page\.txt' "$src.log")"

src="$(new_served served-idx-etag)"
printf '%s' '"s1"' >"$src/skills.md.etag"
C="$TEST_TMPDIR/gc-idx"
DOCS_CACHE_NOW=$G1 shim_run "$src" "$TEST_TMPDIR/out-ie1" --cache --cache-dir "$C" skills
DOCS_CACHE_NOW=$G2 shim_run "$src" "$TEST_TMPDIR/out-ie2" --cache --cache-dir "$C" --max-age 0 skills
assert_eq "validators: an indexed page revalidates with If-None-Match and a 304" "cache 304 $G1_ISO $G2_ISO" \
  "$(page "$TEST_TMPDIR/out-ie2/manifest.json" skills '"\(.source) \(.status) \(.retrieved) \(.validated)"')"
assert_eq "validators: the conditional request named the stored ETag" 1 "$(grep -c -- 'If-None-Match: "s1"' "$src.log")"

src="$(new_served served25)"
head -c 2000 /dev/zero | tr '\0' x >>"$src/skills.md"
C="$TEST_TMPDIR/cache25"
DOCS_CACHE_MAX_PAGE_BYTES=1000 shim_run "$src" "$TEST_TMPDIR/out25a" --cache --cache-dir "$C" skills settings-reference
m="$TEST_TMPDIR/out25a/manifest.json"
assert_eq "case 25: a body over the cap is unread too-large with no cache key" "unread too-large null" \
  "$(page "$m" skills '"\(.state) \(.reason) \(.cache_key)"')"
assert_no_file "case 25: too-large leaves no page file" "$TEST_TMPDIR/out25a/skills.md"
rc=0
DC info "$(key_of https://docs.test/docs/en/skills.md markdown)" >/dev/null 2>&1 || rc=$?
assert_eq "case 25: too-large stores nothing" 1 "$rc"
assert_eq "case 25: a body under the cap is read" read "$(page "$m" settings-reference .state)"
assert_eq "case 25: every request asks curl to stop at the cap" "$(wc -l <"$src.log" | tr -d ' ')" "$(grep -c -- '--max-filesize 1000' "$src.log")"
touch "$src/skills.md.nocap"
DOCS_CACHE_MAX_PAGE_BYTES=1000 shim_run "$src" "$TEST_TMPDIR/out25b" skills
assert_eq "case 25: a curl that ignores the cap is caught by the size check, without --cache too" "unread too-large" \
  "$(page "$TEST_TMPDIR/out25b/manifest.json" skills '"\(.state) \(.reason)"')"
assert_no_file "case 25: the size check leaves no page file" "$TEST_TMPDIR/out25b/skills.md"
DOCS_CACHE_MAX_PAGE_BYTES=1000 shim_run "$src" "$TEST_TMPDIR/out25c" --max-page-bytes 100000 skills
assert_eq "case 25: --max-page-bytes wins over DOCS_CACHE_MAX_PAGE_BYTES" read "$(page "$TEST_TMPDIR/out25c/manifest.json" skills .state)"
rc=0
err="$(shim_run "$src" "$TEST_TMPDIR/out25d" --max-page-bytes big skills 2>&1)" || rc=$?
assert_eq "case 25: --max-page-bytes needs a positive integer" "2 ERROR: --max-page-bytes needs a positive integer" "$rc $err"
for bad in 0 010 09; do
  rc=0
  err="$(shim_run "$src" "$TEST_TMPDIR/out25d" --max-page-bytes "$bad" skills 2>&1)" || rc=$?
  assert_eq "case 25: --max-page-bytes $bad is refused" "2 ERROR: --max-page-bytes needs a positive integer" "$rc $err"
done
rc=0
err="$(shim_run "$src" "$TEST_TMPDIR/out25d" --max-age 010 skills 2>&1)" || rc=$?
assert_eq "case 25: --max-age with a leading zero is refused" "2 ERROR: --max-age needs a non-negative integer" "$rc $err"
DOCS_CACHE_MAX_PAGE_BYTES=010 shim_run "$src" "$TEST_TMPDIR/out25e" skills settings-reference 2>"$TEST_TMPDIR/err25e"
assert_eq "case 25: DOCS_CACHE_MAX_PAGE_BYTES=010 is warned and the 10 MiB default applies" "1 read read" \
  "$(grep -c '^WARNING: docs-cache config: DOCS_CACHE_MAX_PAGE_BYTES=010 ' "$TEST_TMPDIR/err25e") $(page "$TEST_TMPDIR/out25e/manifest.json" skills .state) $(page "$TEST_TMPDIR/out25e/manifest.json" settings-reference .state)"

src="$(new_served served25x)"
head -c 1000 /dev/zero | tr '\0' x >"$src/skills.md"
head -c 1001 /dev/zero | tr '\0' x >"$src/settings-reference.md"
touch "$src/skills.md.nocap" "$src/settings-reference.md.nocap"
DOCS_CACHE_MAX_PAGE_BYTES=1000 shim_run "$src" "$TEST_TMPDIR/out25x" skills settings-reference
m="$TEST_TMPDIR/out25x/manifest.json"
assert_eq "case 25: a body of exactly max_page_bytes is read, all of it" "read 1000" "$(page "$m" skills '"\(.state) \(.bytes)"')"
assert_eq "case 25: a body one byte over max_page_bytes is unread too-large" "unread too-large" \
  "$(page "$m" settings-reference '"\(.state) \(.reason)"')"
src="$TEST_TMPDIR/gs-big"
mkdir -p "$src"
html_page "$src/page" Page "$(head -c 2000 /dev/zero | tr '\0' x)"
printf '%s' 'text/html' >"$src/page.ctype"
: >"$PY_LOG"
DOCS_CACHE_MAX_PAGE_BYTES=1000 gen_run "$src" go-big "$PYOK" $G1 "$PAGE_URL"
assert_eq "case 25: a generic HTML page over the cap is unread too-large and never converted" "unread too-large 0" \
  "$(gpage go-big '"\(.state) \(.reason)"') $(grep -c ran "$PY_LOG")"
printf '%s\n' 'not markdown' >"$src/page.accept-md"
printf '%s' 'text/plain' >"$src/page.accept-md.ctype"
: >"$PY_LOG"
: >"$src.log"
DOCS_CACHE_MAX_PAGE_BYTES=1000 gen_run "$src" go-big2 "$PYOK" $G1 "$PAGE_URL"
assert_eq "case 25: HTML over the cap on the plain GET after the markdown request is unread too-large, never converted" \
  "unread too-large 0 1" \
  "$(gpage go-big2 '"\(.state) \(.reason)"') $(grep -c ran "$PY_LOG") $(grep -v -- '-H Accept' "$src.log" | awk -v u="$PAGE_URL" '$NF == u' | wc -l | tr -d ' ')"
src="$TEST_TMPDIR/gs-bigsfx"
mkdir -p "$src"
html_page "$src/page" Page 'html body'
printf '%s' 'text/html' >"$src/page.ctype"
head -c 2000 /dev/zero | tr '\0' x >"$src/page.md"
printf '%s\n' '- [Page](https://docs.test/guide/page.txt)' >"$src/llms.txt"
printf '%s\n' '# Page' 'bundle body' >"$src/page.txt"
touch "$src/page.md.nocap" "$src/page.txt.nocap"
DOCS_CACHE_MAX_PAGE_BYTES=1000 gen_run "$src" go-bigsfx "$PYOK" $G1 "$PAGE_URL"
assert_eq "case 25: a .md suffix over the cap is skipped; the llms.txt link is read" "read markdown 1 0" \
  "$(gpage go-bigsfx '"\(.state) \(.format)"') $(grep -cF 'https://docs.test/guide/page.md' "$src.log") $(find "$TEST_TMPDIR/go-bigsfx" -name '*.part' | wc -l | tr -d ' ')"
assert_eq "case 25: the page is the llms.txt link's body" "$(cat "$src/page.txt")" "$(cat "$TEST_TMPDIR/go-bigsfx/docs-test/guide/page.md")"
rm -f "$src/page.md"
head -c 2000 /dev/zero | tr '\0' x >"$src/page.txt"
: >"$PY_LOG"
DOCS_CACHE_MAX_PAGE_BYTES=1000 gen_run "$src" go-bigbundle "$PYOK" $G1 "$PAGE_URL"
assert_eq "case 25: an llms.txt link over the cap is skipped; the HTML is converted" "read html-converted 1 0" \
  "$(gpage go-bigbundle '"\(.state) \(.format)"') $(grep -c ran "$PY_LOG") $(find "$TEST_TMPDIR/go-bigbundle" -name '*.part' | wc -l | tr -d ' ')"
head -c 2000 /dev/zero | tr '\0' x >"$src/page.md"
printf '%s' 'text/plain' >"$src/page.ctype"
DOCS_CACHE_MAX_PAGE_BYTES=1000 gen_run "$src" go-bignone "$PYOK" $G1 "$PAGE_URL"
assert_eq "case 25: over-cap fallbacks with nothing read after them leave no .part file" "unread 0" \
  "$(gpage go-bignone .state) $(find "$TEST_TMPDIR/go-bignone" -name '*.part' | wc -l | tr -d ' ')"

src="$(new_served served26)"
C="$TEST_TMPDIR/cache26"
skills_key="$(DC key https://docs.test/docs/en/skills.md markdown)"
cache_run $T1 out26a --max-age 0 skills
for form in https://docs.test/docs/en/skills 'https://docs.test/docs/en/skills#frontmatter' 'https://docs.test/docs/en/skills.md#frontmatter' \
  'https://docs.test/docs/en/skills?utm_source=x' https://docs.test/docs/en/skills/; do
  cache_run $T1 out26b --max-age 0 "$form"
  assert_eq "case 26: $form reads the page the index lists" "read https://docs.test/docs/en/skills.md" \
    "$(page "$TEST_TMPDIR/out26b/manifest.json" skills '"\(.state) \(.url)"')"
done
assert_eq "case 26: no browser form quarantines the listed page's key" null "$(DC info "$skills_key" | jq -c .quarantine)"
cache_run $T1 out26c --max-age 0 https://evil.test/docs/en/skills
assert_eq "case 26: an off-origin browser form is unread and never fetched" "unread 0" \
  "$(page "$TEST_TMPDIR/out26c/manifest.json" https://evil.test/docs/en/skills .state) $(grep -c 'evil\.test' "$src.log")"

src="$(new_served served27)"
C="$TEST_TMPDIR/cache27"
skills_key="$(DC key https://docs.test/docs/en/skills.md markdown)"
cache_run $T1 out27a --max-age 86400 skills
printf '404' >"$src/skills.md.status"
cache_run $((T1 + 10)) out27b --max-age 0 skills
cache_run $((T1 + 20)) out27c --max-age 86400 skills
assert_eq "case 27: inside max-age a removed page asks the server and stays unread" "unread http-404 fetch" \
  "$(page "$TEST_TMPDIR/out27c/manifest.json" skills '"\(.state) \(.reason) \(.source)"')"
mv "$src/skills.md" "$src/skills.md.away"
rm -f "$src/skills.md.status"
cache_run $((T1 + 25)) out27g --max-age 86400 skills
assert_eq "case 27: a removed page whose next fetch fails is unread, never served stale" "unread fetch-failed false" \
  "$(page "$TEST_TMPDIR/out27g/manifest.json" skills '"\(.state) \(.reason) \(.stale)"')"
mv "$src/skills.md.away" "$src/skills.md"
cache_run $((T1 + 30)) out27d --max-age 86400 skills
assert_eq "case 27: the page back lifts the quarantine through a fetch" "read fetch false null" \
  "$(page "$TEST_TMPDIR/out27d/manifest.json" skills '"\(.state) \(.source) \(.quarantined)"') $(DC info "$skills_key" | jq -c .quarantine)"
printf '%s\n' '# Renamed' 'body of skills' >"$src/skills.md"
cache_run $((T1 + 40)) out27e --max-age 0 skills
cache_run $((T1 + 50)) out27f --max-age 86400 skills
assert_eq "case 27: a retitled key is still served fresh from the cache" "read cache true" \
  "$(page "$TEST_TMPDIR/out27f/manifest.json" skills '"\(.state) \(.source) \(.quarantined)"')"

procedure="$SCRIPT_DIR/docs-lookup-procedure.md"
# shellcheck disable=SC2016 # the patterns are literal procedure text
assert_eq "case 28: the procedure makes --out with mktemp" 1 "$(grep -c '^out="$(mktemp -d)"$' "$procedure")"
# shellcheck disable=SC2016 # the pattern is literal procedure text
assert_eq "case 28: the procedure removes --out by its literal path" 1 "$(grep -c '`rm -rf <out>`' "$procedure")"

FC_SHIM="$TEST_TMPDIR/fc-shim"
mkdir -p "$FC_SHIM"
cat >"$FC_SHIM/firecrawl" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "$PWD" "$*" >>"$FC_SHIM_LOG"
mkdir -p .firecrawl
printf 'cached\n' >.firecrawl/cache
[[ "${1:-}" == scrape ]] || exit 2
shift
url="" fmt="" out="" json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -f | --format | --formats) fmt="$2"; shift 2 ;;
  -o | --output) out="$2"; shift 2 ;;
  -u | --url) url="$2"; shift 2 ;;
  --json) json=1; shift ;;
  -*) shift ;;
  *) url="$1"; shift ;;
  esac
done
[[ -n "$url" && "$fmt" == markdown && $json -eq 1 && -n "$out" ]] || exit 2
name="${url##*/}"
src="$FC_SHIM_SRC/$name"
[[ ! -f "$src.fail" ]] || exit 1
[[ -f "$src.md" ]] || exit 1
r_url="$url"
[[ ! -f "$src.url" ]] || r_url="$(cat "$src.url")"
status=200
[[ ! -f "$src.status" ]] || status="$(cat "$src.status")"
title=""
[[ ! -f "$src.title" ]] || title="$(cat "$src.title")"
use_source_only=0
[[ ! -f "$src.sourceurl" ]] || use_source_only=1
no_url=0
[[ ! -f "$src.nourl" ]] || no_url=1
wrapped=0
[[ ! -f "$src.wrapped" ]] || wrapped=1
jq -n --rawfile md "$src.md" --arg url "$r_url" --argjson st "$status" --arg title "$title" \
  --argjson so "$use_source_only" --argjson nu "$no_url" --argjson wr "$wrapped" '
  ({statusCode: $st}
   + (if $title != "" then {title: $title} else {} end)
   + (if $nu == 1 then {}
      elif $so == 1 then {sourceURL: $url}
      else {url: $url, sourceURL: $url} end)) as $meta
  | {markdown: $md, metadata: $meta}
  | if $wr == 1 then {success: true, data: .} else . end
' >"$out"
exit 0
EOF
chmod +x "$FC_SHIM/firecrawl"

render_run() {
  local src="$1" fcsrc="$2" out="$3" now="$4"
  shift 4
  env -u FETCH_DOCS_FIXTURE_DIR PATH="$FC_SHIM:$PYOK:$SHIM:$PATH" \
    CURL_SHIM_LOG="$src.log" CURL_SHIM_SRC="$src" \
    FC_SHIM_LOG="$fcsrc.log" FC_SHIM_SRC="$fcsrc" \
    FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" FETCH_DOCS_HTML2MD="$CONV" DOCS_CACHE_NOW="$now" \
    bash "$SCRIPT" --profile generic --out "$TEST_TMPDIR/$out" "$@"
}

src="$TEST_TMPDIR/rs-403"
fcsrc="$TEST_TMPDIR/rf-403"
mkdir -p "$src" "$fcsrc"
printf 'blocked\n' >"$src/page"
printf '403' >"$src/page.status"
printf '%s' 'text/html' >"$src/page.ctype"
printf '%s\n' '# Rendered Page' 'rendered content marker' >"$fcsrc/page.md"
: >"$fcsrc.log"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-noflag $G1 "$PAGE_URL"
assert_eq "render: without --render-fallback a 403 stays unread and never calls firecrawl" "unread http-403 0" \
  "$(gpage ro-noflag '"\(.state) \(.reason)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"
assert_no_file "render: without --render-fallback no page file" "$TEST_TMPDIR/ro-noflag/docs-test/guide/page.md"

: >"$fcsrc.log"
render_run "$src" "$fcsrc" ro-rnone $G1 --render-fallback "$PAGE_URL"
assert_eq "render: with default renderer none, --render-fallback leaves a 403 unread" "unread http-403 0" \
  "$(gpage ro-rnone '"\(.state) \(.reason)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"

C="$TEST_TMPDIR/rc-403"
caller_cwd="$TEST_TMPDIR/rc-caller-cwd"
mkdir -p "$caller_cwd"
: >"$src.log"
: >"$fcsrc.log"
(cd "$caller_cwd" && DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-403a $G1 --cache --cache-dir "$C" --max-age 86400 --render-fallback "$PAGE_URL")
assert_eq "render: --render-fallback with firecrawl renders a 403" \
  "read fetch rendered text/markdown 200 $(key_of "$PAGE_URL" rendered)" \
  "$(gpage ro-403a '"\(.state) \(.source) \(.format) \(.content_type) \(.status) \(.cache_key)"')"
assert_eq "render: page file holds the rendered markdown" "" \
  "$(cmp "$fcsrc/page.md" "$TEST_TMPDIR/ro-403a/docs-test/guide/page.md" 2>&1)"
assert_eq "render: firecrawl ran once" 1 "$(wc -l <"$fcsrc.log" | tr -d ' ')"
used_cwd="$(cut -f1 "$fcsrc.log")"
assert_eq "render: firecrawl ran in a temp working directory, not caller cwd" 1 \
  "$([[ -n "$used_cwd" && "$used_cwd" != "$caller_cwd" ]] && echo 1 || echo 0)"
assert_no_file "render: the temp working directory is removed afterwards" "$used_cwd"
assert_no_file "render: caller cwd has no .firecrawl directory" "$caller_cwd/.firecrawl"

curl_before="$(wc -l <"$src.log" | tr -d ' ')"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-403b $G2 --cache --cache-dir "$C" --max-age 86400 --render-fallback "$PAGE_URL"
assert_eq "render: second run within window is served from cache with no new render or fetch" \
  "read cache rendered text/markdown 100 1 $curl_before" \
  "$(gpage ro-403b '"\(.state) \(.source) \(.format) \(.content_type) \(.age_seconds)"') $(wc -l <"$fcsrc.log" | tr -d ' ') $(wc -l <"$src.log" | tr -d ' ')"
assert_eq "render: cached rendered bytes match" "" \
  "$(cmp "$fcsrc/page.md" "$TEST_TMPDIR/ro-403b/docs-test/guide/page.md" 2>&1)"

rcfg="$TEST_TMPDIR/rcfg/claude-docs-cache"
mkdir -p "$rcfg"
printf '%s\n' '{"renderer": "firecrawl"}' >"$rcfg/config.json"
: >"$fcsrc.log"
XDG_CONFIG_HOME="$TEST_TMPDIR/rcfg" render_run "$src" "$fcsrc" ro-cfg $G1 --render-fallback "$PAGE_URL"
assert_eq "render: machine config renderer=firecrawl enables --render-fallback" "read rendered 1" \
  "$(gpage ro-cfg '"\(.state) \(.format)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"

src="$TEST_TMPDIR/rs-kinds"
fcsrc="$TEST_TMPDIR/rf-kinds"
mkdir -p "$src" "$fcsrc"
printf 'rate limited\n' >"$src/page"
printf '429' >"$src/page.status"
printf '%s' 'text/html' >"$src/page.ctype"
printf '%s\n' '# Page' 'from 429' >"$fcsrc/page.md"
touch "$fcsrc/page.wrapped"
: >"$fcsrc.log"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-429 $G1 --render-fallback "$PAGE_URL"
assert_eq "render: 429 is rendered (wrapped JSON)" "read rendered 1" \
  "$(gpage ro-429 '"\(.state) \(.format)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"
touch "$fcsrc/page.sourceurl"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-429s $G1 --render-fallback "$PAGE_URL"
assert_eq "render: a render reporting only sourceURL, no final url, stays unread" "unread" \
  "$(gpage ro-429s '.state')"
rm -f "$fcsrc/page.sourceurl"

rm -f "$src/page" "$src/page.status" "$src/page.ctype"
: >"$fcsrc.log"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-fail $G1 --render-fallback "$PAGE_URL"
assert_eq "render: fetch-failed is rendered" "read rendered 1" \
  "$(gpage ro-fail '"\(.state) \(.format)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"

printf '{"ok": true}\n' >"$src/page"
printf '%s' 'application/json' >"$src/page.ctype"
: >"$fcsrc.log"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-ctype $G1 --render-fallback "$PAGE_URL"
assert_eq "render: unexpected-content-type is rendered" "read rendered 1" \
  "$(gpage ro-ctype '"\(.state) \(.format)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"

src="$TEST_TMPDIR/rs-shell"
fcsrc="$TEST_TMPDIR/rf-shell"
mkdir -p "$src" "$fcsrc"
html_page "$src/page" 'App Shell' 'Loading...'
printf '%s' 'text/html; charset=utf-8' >"$src/page.ctype"
printf '%s\n' '# Leaderboard' 'Score: 99' >"$fcsrc/page.md"
C="$TEST_TMPDIR/rc-shell"
: >"$fcsrc.log"
render_run "$src" "$fcsrc" ro-shell1 $G1 --cache --cache-dir "$C" --expect 'Score:' "$PAGE_URL"
assert_eq "expect: JS shell without marker is unread no-content" "unread no-content 200 null 0" \
  "$(gpage ro-shell1 '"\(.state) \(.reason) \(.status) \(.cache_key)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"
assert_no_file "expect: no-content leaves no page file" "$TEST_TMPDIR/ro-shell1/docs-test/guide/page.md"
assert_eq "expect: no-content caches nothing" 0 "$(entry_dirs "$C" 2>/dev/null)"

render_run "$src" "$fcsrc" ro-shell-ok $G1 --expect 'Loading...' "$PAGE_URL"
assert_eq "expect: plain page containing marker is read without rendering" "read html-converted 0" \
  "$(gpage ro-shell-ok '"\(.state) \(.format)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"

: >"$fcsrc.log"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-shell2 $G1 --cache --cache-dir "$C" --max-age 86400 --expect 'Score:' --render-fallback "$PAGE_URL"
assert_eq "expect: no-content with --render-fallback renders and caches" "read fetch rendered 1" \
  "$(gpage ro-shell2 '"\(.state) \(.source) \(.format)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-shell3 $G2 --cache --cache-dir "$C" --max-age 86400 --expect 'Score:' --render-fallback "$PAGE_URL"
assert_eq "expect: second run serves rendered entry from cache with no new render" "read cache rendered 1" \
  "$(gpage ro-shell3 '"\(.state) \(.source) \(.format)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"

printf '%s\n' '# Still Empty' 'Loading...' >"$fcsrc/page.md"
: >"$fcsrc.log"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-shell4 $G1 --expect 'Score:' --render-fallback "$PAGE_URL"
assert_eq "expect: rendered body still missing marker stays unread no-content" "unread no-content 1" \
  "$(gpage ro-shell4 '"\(.state) \(.reason)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"
assert_no_file "expect: failed rendered marker check leaves no page file" "$TEST_TMPDIR/ro-shell4/docs-test/guide/page.md"

src="$TEST_TMPDIR/rs-never"
fcsrc="$TEST_TMPDIR/rf-never"
mkdir -p "$src" "$fcsrc"
printf 'not found\n' >"$src/page"
printf '%s' 'text/html' >"$src/page.ctype"
printf '%s\n' '# Should Not Render' >"$fcsrc/page.md"
for code in 404 410; do
  printf '%s' "$code" >"$src/page.status"
  : >"$fcsrc.log"
  DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" "ro-$code" $G1 --render-fallback "$PAGE_URL"
  assert_eq "render: HTTP $code is never rendered" "unread http-$code 0" \
    "$(gpage "ro-$code" '"\(.state) \(.reason)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"
done
rm -f "$src/page.status"
printf '%s' 'https://elsewhere.example/guide/page' >"$src/page.effective"
: >"$fcsrc.log"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-offorig $G1 --render-fallback "$PAGE_URL"
assert_eq "render: off-origin plain redirect is never rendered" "unread redirected-off-origin 0" \
  "$(gpage ro-offorig '"\(.state) \(.reason)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"
printf '%s' 'https://docs.test/other/page' >"$src/page.effective"
: >"$fcsrc.log"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-offpath $G1 --render-fallback "$PAGE_URL"
assert_eq "render: off-path plain redirect is never rendered" "unread redirected-off-path 0" \
  "$(gpage ro-offpath '"\(.state) \(.reason)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"

src="$TEST_TMPDIR/rs-rredir"
fcsrc="$TEST_TMPDIR/rf-rredir"
mkdir -p "$src" "$fcsrc"
printf 'blocked\n' >"$src/page"
printf '403' >"$src/page.status"
printf '%s' 'text/html' >"$src/page.ctype"
printf '%s\n' '# Off Site' 'body' >"$fcsrc/page.md"
printf '%s' 'https://elsewhere.example/guide/page' >"$fcsrc/page.url"
C="$TEST_TMPDIR/rc-rredir"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-ro1 $G1 --cache --cache-dir "$C" --render-fallback "$PAGE_URL"
assert_eq "render: off-site final URL from renderer stays unread" "unread redirected-off-origin null" \
  "$(gpage ro-ro1 '"\(.state) \(.reason) \(.cache_key)"')"
assert_no_file "render: off-site final URL leaves no page file" "$TEST_TMPDIR/ro-ro1/docs-test/guide/page.md"

printf '%s' 'https://docs.test/elsewhere/page' >"$fcsrc/page.url"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-ro2 $G1 --render-fallback "$PAGE_URL"
assert_eq "render: off-path final URL from renderer stays unread" "unread redirected-off-path" \
  "$(gpage ro-ro2 '"\(.state) \(.reason)"')"

rm -f "$fcsrc/page.url"
touch "$fcsrc/page.nourl"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-ro3 $G1 --render-fallback "$PAGE_URL"
assert_eq "render: missing final URL from renderer stays unread" "unread http-403" \
  "$(gpage ro-ro3 '"\(.state) \(.reason)"')"
rm -f "$fcsrc/page.nourl"

printf '404' >"$fcsrc/page.status"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-ro4 $G1 --render-fallback "$PAGE_URL"
assert_eq "render: 404 reported by renderer stays unread http-404" "unread http-404 404" \
  "$(gpage ro-ro4 '"\(.state) \(.reason) \(.status)"')"
rm -f "$fcsrc/page.status"

src="$TEST_TMPDIR/rs-rpub"
fcsrc="$TEST_TMPDIR/rf-rpub"
mkdir -p "$src" "$fcsrc"
printf 'blocked\n' >"$src/page"
printf '403' >"$src/page.status"
printf '%s' 'text/html' >"$src/page.ctype"
printf '%s\n' '# Public Page' 'body' >"$fcsrc/page.md"
rpub_run() {
  : >"$src.log"
  : >"$fcsrc.log"
  env -u FETCH_DOCS_FIXTURE_DIR PATH="$FC_SHIM:$SHIM:$PATH" \
    CURL_SHIM_LOG="$src.log" CURL_SHIM_SRC="$src" \
    FC_SHIM_LOG="$fcsrc.log" FC_SHIM_SRC="$fcsrc" \
    FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" FETCH_DOCS_ADDRESSES="$2" DOCS_CACHE_RENDERER=firecrawl \
    bash "$SCRIPT" --profile generic --public-only --render-fallback --out "$TEST_TMPDIR/$1" "$PAGE_URL"
}
rpub_run ro-rpub-priv 'docs.test=127.0.0.1'
assert_eq "render: --public-only refuses private host before rendering" "unread private-address 0 0" \
  "$(gpage ro-rpub-priv '"\(.state) \(.reason)"') $(wc -l <"$src.log" | tr -d ' ') $(wc -l <"$fcsrc.log" | tr -d ' ')"
rpub_run ro-rpub-unres 'other.test=93.184.216.34'
assert_eq "render: --public-only refuses unresolvable host before rendering" "unread fetch-failed 0 0" \
  "$(gpage ro-rpub-unres '"\(.state) \(.reason)"') $(wc -l <"$src.log" | tr -d ' ') $(wc -l <"$fcsrc.log" | tr -d ' ')"
rpub_run ro-rpub-ok 'docs.test=93.184.216.34'
assert_eq "render: --public-only renders global host after 403" "read rendered 1" \
  "$(gpage ro-rpub-ok '"\(.state) \(.format)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"

src="$TEST_TMPDIR/rs-stale"
fcsrc="$TEST_TMPDIR/rf-stale"
mkdir -p "$src" "$fcsrc"
printf 'blocked\n' >"$src/page"
printf '403' >"$src/page.status"
printf '%s' 'text/html' >"$src/page.ctype"
printf '%s\n' '# Cached Rendered' 'original body' >"$fcsrc/page.md"
C="$TEST_TMPDIR/rc-stale"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-st1 $G1 --cache --cache-dir "$C" --max-age 86400 --render-fallback "$PAGE_URL"
assert_eq "render stale: initial render cached" "read fetch rendered" "$(gpage ro-st1 '"\(.state) \(.source) \(.format)"')"
touch "$fcsrc/page.fail"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-st2 $T3 --cache --cache-dir "$C" --max-age 86400 --render-fallback "$PAGE_URL"
assert_eq "render stale: 403 serves cached copy stale with age when rendering fails" \
  "read cache true 86500 http-403 403" \
  "$(gpage ro-st2 '"\(.state) \(.source) \(.stale) \(.age_seconds) \(.reason) \(.status)"')"
assert_eq "render stale: stale page file is the cached bytes" "" \
  "$(cmp "$fcsrc/page.md" "$TEST_TMPDIR/ro-st2/docs-test/guide/page.md" 2>&1)"

printf '429' >"$src/page.status"
DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-st3 $T3 --cache --cache-dir "$C" --max-age 86400 --render-fallback "$PAGE_URL"
assert_eq "render stale: 429 serves cached copy stale with age when rendering fails" \
  "read cache true 86500 http-429 429" \
  "$(gpage ro-st3 '"\(.state) \(.source) \(.stale) \(.age_seconds) \(.reason) \(.status)"')"

DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-st3e $T3 --cache --cache-dir "$C" --max-age 86400 --render-fallback --expect 'Score:' "$PAGE_URL"
assert_eq "render stale: a stale cached copy without the --expect marker stays unread" "unread no-content" \
  "$(gpage ro-st3e '"\(.state) \(.reason)"')"

DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-st4 $T3 --cache --cache-dir "$C" --max-age 0 --render-fallback "$PAGE_URL"
assert_eq "render stale: --max-age 0 never serves stale on 429" "unread http-429 false" \
  "$(gpage ro-st4 '"\(.state) \(.reason) \(.stale)"')"

DOCS_CACHE_RENDERER=none render_run "$src" "$fcsrc" ro-st5 $T3 --cache --cache-dir "$C" --max-age 86400 --render-fallback "$PAGE_URL"
assert_eq "render stale: renderer=none leaves 429 unread without stale" "unread http-429 false" \
  "$(gpage ro-st5 '"\(.state) \(.reason) \(.stale)"')"

DOCS_CACHE_RENDERER=firecrawl render_run "$src" "$fcsrc" ro-st6 $T3 --cache --cache-dir "$C" --max-age 86400 "$PAGE_URL"
assert_eq "render stale: without --render-fallback, 429 stays unread without stale" "unread http-429 false" \
  "$(gpage ro-st6 '"\(.state) \(.reason) \(.stale)"')"

rc=0
bash "$SCRIPT" --out "$TEST_TMPDIR/ro-bad1" --render-fallback skills >/dev/null 2>&1 || rc=$?
assert_eq "render: --render-fallback on indexed profile is fatal" 2 "$rc"
rc=0
bash "$SCRIPT" --out "$TEST_TMPDIR/ro-bad2" --expect 'Marker' skills >/dev/null 2>&1 || rc=$?
assert_eq "expect: --expect on indexed profile is fatal" 2 "$rc"
rc=0
bash "$SCRIPT" --profile generic --out "$TEST_TMPDIR/ro-bad3" --expect '' "$PAGE_URL" >/dev/null 2>&1 || rc=$?
assert_eq "expect: empty --expect is fatal" 2 "$rc"
: >"$fcsrc.log"
fx="$TEST_TMPDIR/fx-render"
mkdir -p "$fx/docs-test/guide"
printf '%s\n' '# Shell' 'Loading...' >"$fx/docs-test/guide/page.md"
PATH="$FC_SHIM:$PATH" FC_SHIM_LOG="$fcsrc.log" FC_SHIM_SRC="$fcsrc" DOCS_CACHE_RENDERER=firecrawl \
  FETCH_DOCS_FIXTURE_DIR="$fx" FETCH_DOCS_CLAUDE_BIN="$CLAUDE_STUB" \
  bash "$SCRIPT" --profile generic --expect 'Score:' --render-fallback --out "$TEST_TMPDIR/ro-fx" "$PAGE_URL"
assert_eq "render: fixture mode checks --expect and never invokes firecrawl" "unread no-content 0" \
  "$(gpage ro-fx '"\(.state) \(.reason)"') $(wc -l <"$fcsrc.log" | tr -d ' ')"

echo
if [[ $FAILED -eq 0 ]]; then
  printf 'All %d assertions passed.\n' "$CASE_NUM"
else
  printf '%d of %d assertions failed.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
