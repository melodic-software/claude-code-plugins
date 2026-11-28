#!/usr/bin/env bash
# shellcheck disable=SC2310  # every function here answers through its return code; callers branch on it
set -euo pipefail
export LC_ALL=C

REPLACE_MARKER='<!-- review-base: replace -->'
SUBSCRIPTIONS_SINCE=1.3.0
CONCERN=docs/conventions/standards.yaml
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
US=$'\037'

die() { printf 'org-standards: %s\n' "$(printable "$1")" >&2; exit "${2:-2}"; }
note() { printf 'org-standards: %s\n' "$(printable "$1")" >&2; }

GIT_ISOLATE=(-c core.hooksPath=/dev/null -c core.fsmonitor=false -c http.followRedirects=false)

# shellcheck disable=SC2016  # an awk program; awk expands its own $ fields
ESCAPE='
function esc(s, tab,    out) {
  if (!ORDS) { for (ORDS = 1; ORDS < 256; ORDS++) ORD[sprintf("%c", ORDS)] = ORDS }
  out = ""
  while (match(s, /[^ -~]/)) {
    out = out substr(s, 1, RSTART - 1); s = substr(s, RSTART)
    if (tab && substr(s, 1, 1) == "\t") { out = out "\t"; s = substr(s, 2) }
    else if (match(s, /^(\302[\240-\277]|[\303-\337][\200-\277]|\340[\240-\277][\200-\277]|[\341-\354\356\357][\200-\277][\200-\277]|\355[\200-\237][\200-\277]|\360[\220-\277][\200-\277][\200-\277]|[\361-\363][\200-\277][\200-\277][\200-\277]|\364[\200-\217][\200-\277][\200-\277])/)) {
      out = out substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1)
    }
    else if (match(s, /^\302[\200-\237]/)) { out = out sprintf("\\x%02x", ORD[substr(s, 2, 1)]); s = substr(s, 3) }
    else { out = out sprintf("\\x%02x", ORD[substr(s, 1, 1)]); s = substr(s, 2) }
  }
  return out s
}'
printable() { ESCAPE_IN=$1 awk "$ESCAPE"' BEGIN { printf "%s", esc(ENVIRON["ESCAPE_IN"], 0) }'; }
as_is() { [[ "$(printable "$1")" == "$1" ]]; }

cmd=${1:-}; shift || true
root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 ]] || die "--root needs a directory"; root=$2; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
case "$cmd" in dir|index|guidance|review|citations|subscriptions) ;; *) die "usage: org-standards.sh dir|index|guidance|review|citations|subscriptions [--root DIR]" ;; esac
if [[ -z "$root" ]]; then
  root=$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null command git "${GIT_ISOLATE[@]}" rev-parse --show-toplevel 2>/dev/null || pwd)
fi

NET_KEYS='^(https?\.proxy|http\.sslcainfo|http\.sslcapath|core\.sshcommand|url\..*\.insteadof|credential\..*)$'
USER_SSH=""
cfg_count=${GIT_CONFIG_COUNT:-0}
if [[ "$cfg_count" =~ ^[0-9]+$ ]]; then cfg_count=$((10#$cfg_count)); else cfg_count=0; fi
while IFS= read -r -d '' kv; do
  [[ "$kv" == *$'\n'* ]] || continue
  key=${kv%%$'\n'*}
  if [[ "$key" == core.sshcommand ]]; then USER_SSH=${kv#*$'\n'}; continue; fi
  export "GIT_CONFIG_KEY_$cfg_count=$key" "GIT_CONFIG_VALUE_$cfg_count=${kv#*$'\n'}"
  cfg_count=$((cfg_count + 1))
done < <(
  dir=$root; [[ -d "$dir" ]] || dir=.
  for scope in system global; do command git -C "$dir" config "--$scope" --includes -z --get-regexp "$NET_KEYS" 2>/dev/null || true; done
)
[[ "$cfg_count" -eq 0 ]] || export GIT_CONFIG_COUNT=$cfg_count
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ALLOW_PROTOCOL=https:ssh:git:file
git() { command git "${GIT_ISOLATE[@]}" "$@"; }

yaml_value() {
  [[ -f "$1" ]] || return 0
  sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n 1 | sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' \
    -e "s/^\"\(.*\)\"$/\1/" -e "s/^'\(.*\)'$/\1/"
}

CACHE="${ORG_STANDARDS_CACHE:-${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}}}"
[[ -z "$CACHE" ]] || [[ -n "${ORG_STANDARDS_CACHE:-}" ]] || CACHE="$CACHE/claude-code-plugins/org-standards"
[[ -z "$CACHE" ]] || [[ "$CACHE" == /* ]] || CACHE="$PWD/$CACHE"
need_cache() {
  [[ -n "$CACHE" ]] || die "no cache directory: set HOME, XDG_CACHE_HOME or ORG_STANDARDS_CACHE"
  as_is "$CACHE" || die "the cache directory $CACHE holds a control character or invalid UTF-8"
}
STATE="$CACHE/.state"
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

GIT_TIMEOUT=${ORG_STANDARDS_GIT_TIMEOUT:-60}
[[ "$GIT_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || GIT_TIMEOUT=60
net_git() {
  local run=(command git)
  command -v timeout >/dev/null 2>&1 && run=(timeout "$GIT_TIMEOUT" git)
  { { GIT_TERMINAL_PROMPT=0 GIT_ASKPASS='' GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-${USER_SSH:-ssh}} -o BatchMode=yes" \
    GIT_CEILING_DIRECTORIES="${CACHE%/*}" "${run[@]}" "${GIT_ISOLATE[@]}" "$@" 2>&1 >&3 3>&-; } \
    | NOTE=${REDIRECT_NOTE:-} awk "$ESCAPE"' ENVIRON["NOTE"] != "" && /returned error: 30[0-9]/ && !n++ { print "org-standards: " esc(ENVIRON["NOTE"], 0) }' >&2 3>&-; } 3>&1
}
checkout_git() { local dir=$1; shift; GIT_LFS_SKIP_SMUDGE=1 net_git -C "$dir" "$@"; }
cache_git() { mkdir -p "$CACHE" && GIT_CEILING_DIRECTORIES="${CACHE%/*}" git -C "$CACHE" "$@"; }
clear_links() {
  local p=$1 chain=() link
  while [[ "$p" == "$CACHE"/* ]]; do chain=("$p" ${chain[@]+"${chain[@]}"}); p=${p%/*}; done
  for link in ${chain[@]+"${chain[@]}"}; do
    [[ -L "$link" ]] || continue
    note "$link is a symbolic link; removed, so the entry is built inside the cache"
    rm -f -- "$link" || return 1
  done
}
place() {
  local tmp=$1 dest=$2 leaf
  mv -T "$tmp" "$dest" 2>/dev/null && return 0
  leaf=$(basename "$tmp")
  if [[ ! -e "$dest" ]] && mv "$tmp" "$dest" 2>/dev/null && [[ -e "$dest/$leaf" ]]; then
    rm -rf "${dest:?}/$leaf"
  fi
  [[ ! -e "$tmp" ]] || rm -rf "${tmp:?}"
}
REPO_RE='^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*$'
SHA_RE='^[0-9a-f]{40}([0-9a-f]{24})?$'

org_dir() {
  if [[ -n "${STANDARDS_DIR:-}" ]]; then
    as_is "$STANDARDS_DIR" || { note "STANDARDS_DIR $STANDARDS_DIR holds a control character or invalid UTF-8; no org layer"; return 4; }
    [[ -d "$STANDARDS_DIR" ]] || { note "STANDARDS_DIR $STANDARDS_DIR is not a directory"; return 4; }
    printf '%s\n' "$STANDARDS_DIR"; return 0
  fi
  local repo
  repo=$(yaml_value "$root/docs/conventions/source-control.yaml" standards_repository)
  [[ -n "$repo" ]] || return 3
  if ! [[ "$repo" =~ $REPO_RE ]]; then
    note "standards_repository $repo is not <owner>/<repo>; no org layer"
    return 3
  fi
  need_cache
  local cache REDIRECT_NOTE="$repo answered with a redirect (for example, it was renamed or moved), which is not followed; set standards_repository to its new location"
  cache="$CACHE/$repo"
  clear_links "$cache" || return 4
  local stamp="$cache/.git/org-standards-fetched" ttl="${ORG_STANDARDS_TTL:-3600}" now
  local url="${ORG_STANDARDS_GIT_BASE:-https://github.com}/$repo.git"
  now=$(date +%s)
  if [[ -d "$cache/.git" ]] && { [[ -n "$(find "$cache" -path "$cache/.git" -prune -o -type l -print -quit 2>/dev/null)" ]] \
    || [[ "$(git -C "$cache" config --get core.symlinks 2>/dev/null)" != false ]]; }; then
    note "$cache holds or allows symbolic links; cloning it again"
    local old
    old=$(mktemp -d "$(dirname "$cache")/.old.XXXXXX") || return 4
    mv -- "$cache" "$old/" 2>/dev/null || true
    rm -rf "${old:?}"
  fi
  if [[ -d "$cache/.git" ]]; then
    if [[ -f "$stamp" ]] && [[ $((now - $(cat "$stamp"))) -lt "$ttl" ]]; then
      printf '%s\n' "$cache"; return 0
    fi
    if net_git -C "$cache" fetch --quiet --depth=1 origin main \
      && checkout_git "$cache" -c core.symlinks=false checkout --quiet --force --detach FETCH_HEAD 2>/dev/null; then
      printf '%s\n' "$now" >"$stamp"
    else
      note "refreshing $repo failed; using the copy cached at $cache"
    fi
    printf '%s\n' "$cache"; return 0
  fi
  mkdir -p "$(dirname "$cache")"
  local tmp
  tmp=$(mktemp -d "$(dirname "$cache")/.clone.XXXXXX")
  if ! net_git -C "$CACHE" clone --quiet --no-checkout --depth=1 --branch main --config core.symlinks=false "$url" "$tmp" \
    || ! checkout_git "$tmp" -c core.symlinks=false checkout --quiet --force main 2>/dev/null; then
    rm -rf "${tmp:?}"
    note "cannot clone $url; no org layer this run"
    return 4
  fi
  printf '%s\n' "$now" >"$tmp/.git/org-standards-fetched"
  place "$tmp" "$cache"
  printf '%s\n' "$cache"
}

phys() {
  local p=$1 n=0 target dir
  if command -v realpath >/dev/null 2>&1; then
    realpath -- "$p" 2>/dev/null && return 0
  fi
  while [[ -L "$p" && $n -lt 40 ]]; do
    target=$(readlink "$p") || return 1
    case "$target" in /*) p=$target ;; *) p="$(dirname "$p")/$target" ;; esac
    n=$((n + 1))
  done
  if [[ -d "$p" ]]; then
    (CDPATH='' cd -- "$p" && pwd -P)
  else
    dir=$(CDPATH='' cd -- "$(dirname "$p")" && pwd -P) || return 1
    printf '%s/%s\n' "$dir" "$(basename "$p")"
  fi
}

inside() {
  local base path
  base=$(phys "$1") && path=$(phys "$2") || return 1
  [[ "$path" == "$base" || "$path" == "$base"/* ]]
}

trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

path_problem() {
  local seg segs
  [[ "$(trim "$1")" != /* ]] || { printf 'is absolute'; return 0; }
  IFS=/ read -ra segs <<<"$1"
  for seg in ${segs[@]+"${segs[@]}"}; do
    [[ "$(trim "$seg")" != .. ]] || { printf "has a '..' segment"; return 0; }
  done
  [[ "$1" =~ ^[A-Za-z0-9._@+/\ -]*$ ]] && return 1
  printf 'is not a relative forward-slash path'
}

within() {
  local p=$2
  while [[ ! -e "$p" && ! -L "$p" ]]; do p=$(dirname "$p"); done
  inside "$1" "$p"
}

concern_ok() {
  local conf="$1/$CONCERN" old="$1/.claude/standards.yaml"
  if [[ -e "$conf" || -L "$conf" ]]; then
    inside "$1" "$conf" || { note "$conf resolves outside its checkout; no usable index"; return 1; }
  elif [[ -e "$old" || -L "$old" ]]; then
    note "$old: moved to $CONCERN in standards-contract 2.0.0; not read"
  fi
}

index_of() {
  local key=$2 conf="$1/$CONCERN" dir index why
  if [[ -e "$conf" || -L "$conf" ]] && ! inside "$1" "$conf"; then return 1; fi
  dir=$(yaml_value "$conf" "$key")
  if why=$(path_problem "$dir"); then
    note "$conf: $key $dir $why; no usable index"; return 1
  fi
  if [[ -z "$dir" ]]; then
    [[ "$key" == standards_dir ]] || return 1
    dir=docs/standards
  fi
  index="$1/$dir"; index="${index%/}/README.md"
  [[ -f "$index" ]] || return 1
  if ! inside "$1" "$index"; then
    note "$index: the index resolves outside its checkout; no usable index"; return 1
  fi
  awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { exit 1 } /^standards-contract:/ { found = 1; exit } END { exit !found }' "$index" \
    && printf '%s\n' "$index"
}

first_line() { awk 'NF { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$1"; }

TABLE_CELLS='
{ gsub(/\r/, "") }
function cells(s,    n, i) {
  if (s !~ /^\|.*\|[ \t]*$/ || index(s, "\\|") || index(s, "\037")) return 0
  n = split(s, C, "|")
  if (n != 5 || C[5] !~ /^[ \t]*$/) return 0
  for (i = 2; i <= 4; i++) gsub(/^[ \t]+|[ \t]+$/, "", C[i])
  return 1
}'
# shellcheck disable=SC2016  # an awk program; awk expands its own $ fields
CLASSIFY="$TABLE_CELLS"'
index($0, "|") == 0 { state = 0; next }
!cells($0) { print NR "\037junk"; next }
state == 0 {
  if (tolower(C[2]) == "surface" && tolower(C[3]) == "applies when" && tolower(C[4]) == "file") { state = 1; print NR "\037head" }
  else print NR "\037junk"
  next
}
state == 1 {
  if (C[2] ~ /^:?-+:?$/ && C[3] ~ /^:?-+:?$/ && C[4] ~ /^:?-+:?$/) { state = 2; print NR "\037head" }
  else { state = 0; print NR "\037junk" }
  next
}
{
  f = C[4]
  if (f ~ /^`[^`]+`$/) f = substr(f, 2, length(f) - 2)
  gsub(/^[ \t]+|[ \t]+$/, "", f)
  print NR "\037row\037" C[2] "\037" C[3] "\037" f
}'
BAD_CELL='[|`]'
SURFACE_RE='^[A-Za-z0-9._-]+$'

locate() {
  local root=$1 sdir=$2 f=$3 why cand
  [[ -n "$f" ]] || { printf 'is empty'; return 1; }
  if why=$(path_problem "$f"); then printf '%s' "$why"; return 1; fi
  cand="$sdir/$f"
  if ! [[ -e "$cand" || -L "$cand" ]] && [[ -e "$root/$f" || -L "$root/$f" ]]; then cand="$root/$f"; fi
  within "$root" "$cand" || { printf 'resolves outside its checkout'; return 1; }
  [[ ! -e "$cand" ]] || cand=$(phys "$cand") || { printf 'resolves outside its checkout'; return 1; }
  if [[ "$cand" =~ $BAD_CELL ]] || ! as_is "$cand"; then printf 'resolves to a path a table cell cannot hold'; return 1; fi
  printf '%s' "$cand"
}

confine() {
  local root=$1 index=$2 topics=$3 marker="" sdir line kind id when f path version text key out
  [[ -z "${4:-}" ]] || marker="kind: $4"$'\n'
  need_cache
  version=$(yaml_value "$index" standards-contract)
  if ! [[ "$version" =~ ^[0-9A-Za-z.+-]+$ ]]; then
    note "$index: standards-contract $version is not a version; no usable index"; return 1
  fi
  text=$(printf -- '---\nstandards-contract: %s\n%s---\n\n| Surface | Applies when | File |\n|---|---|---|' "$version" "$marker")
  sdir=$(dirname "$index")
  while IFS="$US" read -r line kind id when f; do
    case "$kind" in
      head) ;;
      row)
        if ! [[ "$id" =~ $SURFACE_RE ]]; then
          note "$index:$line: Surface $id is not an id; row dropped"
        elif ! path=$(locate "$root" "$sdir" "$f"); then
          note "$index:$line: File $f $path; row dropped"
        elif [[ -z "$topics" || " $topics " == *" $id "* ]]; then
          text+=$'\n'"| $id | $(printable "$when") | $path |"
        fi ;;
      *) note "$index:$line: not a row of the index table; line dropped" ;;
    esac
  done < <(awk "$CLASSIFY" "$index")
  key=$(tr ' ' '\n' <<<"$topics" | sort -u | paste -sd+ -)
  out="$STATE/confined/$(printf '%s' "$index" | cache_git hash-object --stdin).${key:-@all}${4:+.$4}.md"
  printf '%s\n' "$text" | write_atomic "$out" || return 1
  printf '%s\n' "$out"
}

surfaces() {
  awk "$CLASSIFY" "$1" | awk -F"$US" '$2 == "row" { print $3 "\t" $5 }' | sort -u
}

# shellcheck disable=SC2016  # an awk program; awk expands its own $ fields
CITATIONS='
function unescape(s,    out, v) {
  out = ""
  while (match(s, /%[0-9A-Fa-f][0-9A-Fa-f]/)) {
    v = HEX[tolower(substr(s, RSTART + 1, 2))]
    out = out substr(s, 1, RSTART - 1) (v >= 32 && v < 127 ? sprintf("%c", v) : substr(s, RSTART, 3))
    s = substr(s, RSTART + 3)
  }
  return out s
}
function check(cite, lo, hi,    n, P, i, k, p, q, l) {
  sub(/^[ \t]+/, "", cite); sub(/[ \t.,;:!?]+$/, "", cite)
  if (cite ~ /^[Hh][Tt][Tt][Pp][Ss]?:\/\//) return
  n = split(cite, P, /[#?]/)
  for (i = 1; i <= n; i++) {
    p = P[i]
    for (k = 0; k < 4 && (q = unescape(p)) != p; k++) p = q
    sub(/[ \t]+$/, "", p)
    if (tolower(p) ~ /\.(md|markdown)$/) for (l = lo; l <= hi; l++) print l "\037" cite "\037" p
  }
}
function tokens(s, lo,    n, W, i) {
  n = split(s, W, /[ \t`()<>"\047\[\]]+/)
  for (i = 1; i <= n; i++) check(W[i], lo, lo)
  gsub(/<[^<>]*>/, "", s)
  n = split(s, W, /[ \t`()<>"\047\[\]]+/)
  for (i = 1; i <= n; i++) check(W[i], lo, lo)
}
function line_of(off, S,    i) {
  for (i = nb; i > 1 && S[i] > off; i--) ;
  return N[i]
}
function spans(B, S,    J, i, j, r, RP, RL, rest, off, a, A, m, at, len) {
  J = B[1]; S[1] = 1
  for (i = 2; i <= nb; i++) { S[i] = length(J) + 2; J = J " " B[i] }
  r = 0; rest = J; off = 0
  while (match(rest, /`+/)) { RP[++r] = off + RSTART; RL[r] = RLENGTH; off += RSTART + RLENGTH - 1; rest = substr(rest, RSTART + RLENGTH) }
  for (i = 1; i < r; i++) for (j = i + 1; j <= r; j++) if (RL[j] == RL[i]) {
    a = RP[i] + RL[i]; check(substr(J, a, RP[j] - a), line_of(RP[i], S), line_of(RP[j], S)); break
  }
  rest = J; off = 0
  while (match(rest, /<[^<>]*>/)) {
    at = RSTART; len = RLENGTH; a = off + at
    m = split(substr(rest, at + 1, len - 2), A, /["\047=]/)
    for (i = 1; i <= m; i++) check(A[i], line_of(a, S), line_of(a + len - 1, S))
    off += at + len - 1; rest = substr(rest, at + len)
  }
}
function flush() { if (nb) { spans(B0, S0); spans(B1, S1) } nb = 0 }
BEGIN { for (i = 0; i < 256; i++) HEX[sprintf("%02x", i)] = i }
{
  line = $0
  gsub(/\037/, " ", line)
  gsub(/<[A-Za-z0-9_-]+>/, "x", line)
  if (line ~ /^[ \t\r]*$/) { flush(); next }
  N[++nb] = NR; B0[nb] = B1[nb] = line
  gsub(INVISIBLE, "", B0[nb]); gsub(INVISIBLE, " ", B1[nb])
  tokens(B0[nb], NR); tokens(B1[nb], NR)
}
END { flush() }'
INVISIBLE='\302[\240\255]|\330[\200-\205\234]|\333\235|\334\217|\340\242[\220\221]|\340\243\242|\341\232\200|\341\240\216|\342\200[\200-\217\250-\257]|\342\201[\237-\244\246-\257]|\343\200\200|\357\273\277|\357\277[\271-\273]|\360\221\202\275|\360\221\203\215|\360\223\220[\260-\277]|\360\233\262[\240-\243]|\360\235\205[\263-\272]|\363\240\200[\201\240-\277]|\363\240\201[\200-\277]'
review_drops() {
  local root=$1 file=$2 line cite path why drop=" "
  while IFS="$US" read -r line cite path; do
    [[ "$drop" != *" $line "* ]] || continue
    if why=$(path_problem "$path"); then :
    elif ! within "$root" "$root/$path"; then why="resolves outside the org checkout"
    else continue
    fi
    note "$file:$line: citation $cite $why; line dropped"
    drop+="$line "
  done < <(awk -v INVISIBLE="$INVISIBLE" "$CITATIONS" "$file" | sort -s -n -t "$US" -k1,1)
  printf '%s' "$drop"
}
show() { awk -v drop=" ${2:-} " "$ESCAPE"' index(drop, " " FNR " ") { next } { sub(/\r$/, ""); print esc($0, 1) }' "$1"; }

CITE_RE='^[A-Za-z0-9][A-Za-z0-9._/-]*\.md#[A-Za-z0-9][A-Za-z0-9._-]*$'
# shellcheck disable=SC2016  # an awk program; awk expands its own $ fields
SPANS='
index(drop, " " FNR " ") { next }
{
  s = $0; before = ""
  while (match(s, /`[^`]+`/)) {
    if (RSTART > 1) before = substr(s, RSTART - 1, 1)
    if (before != "`" && substr(s, RSTART + RLENGTH, 1) != "`") print substr(s, RSTART + 1, RLENGTH - 2)
    before = "`"; s = substr(s, RSTART + RLENGTH)
  }
}'
citations() {
  local c real base
  base=$(phys "$2") || return 0
  while IFS= read -r c; do
    [[ "$c" =~ $CITE_RE && "/${c%%#*}/" != */../* ]] || continue
    real=$(phys "$base/${c%%#*}" 2>/dev/null) || continue
    [[ -f "$real" && "$real" == "$base"/* && "${real#"$base"/}" =~ ^[A-Za-z0-9._/-]+$ ]] || continue
    printf '%s\t%s#%s\n' "$c" "$real" "${c#*#}"
  done < <(awk -v drop=" ${3:-} " "$SPANS" "$1")
}

drift() {
  awk -F'\t' '
    FNR == NR { old[$1] = $2; next }
    { new[$1] = $2 }
    END {
      for (i in new) if (!(i in old)) added[i] = new[i]
      for (i in old) if (!(i in new)) removed[i] = old[i]
      for (r in removed) for (a in added) if (removed[r] == added[a]) { print "renamed " r " -> " a; delete removed[r]; delete added[a]; break }
      for (a in added) print "added " a
      for (r in removed) print "removed " r
    }' <(surfaces "$1") <(surfaces "$2") | sort
}

frontmatter() {
  awk '{ sub(/\r$/, "") } NR == 1 { if ($0 != "---") exit; print ""; next } $0 == "---" { exit } { print }' "$1"
}

# shellcheck disable=SC2016  # an awk program run ahead of yaml-subset.awk: ORS appends each record's line, and END reads the parser's keyseen so a key is found under any spelling it accepts
NUMBERED='
{ ORS = "\t" NR "\n" }
END {
  ORS = "\n"
  for (k in keyseen) if (k ~ /(^|\.)(trusted_owners|standards_repositories)$/) print (index(k, ".") ? ".nested" : ".key") "\t" k "\t" keyseen[k]
}'
parse_yaml() { awk -f <(printf '%s\n' "$NUMBERED") -f "$1"; }

key_line() {
  local text=$2 parsed status at err
  while :; do
    status=0
    parsed=$(printf '%s\n' "$text" | parse_yaml "$1") || status=$?
    at=$(printf '%s\n' "$parsed" | awk -F'\t' -v k="$3" '$1 == ".key" && $2 == k { print $3 }')
    err=$(printf '%s\n' "$parsed" | awk -F'\t' '$1 == "error" { print $2; exit }')
    if [[ -n "$at" || "$status" -eq 0 || ! "$err" =~ ^[1-9][0-9]*$ ]]; then printf '%s' "$at"; return 0; fi
    text=$(printf '%s\n' "$text" | awk -v l="$err" 'NR == l { print ""; next } { print }')
  done
}
# shellcheck disable=SC2016  # an awk program; awk expands its own $ fields
VALUE_ON_KEY_LINE='function on_key_line(s) { sub(/^[^:]*:[ \t]*/, "", s); return s != "" && s !~ /^#/ }'

list_ranges() {
  awk -v at="$1" "$VALUE_ON_KEY_LINE"'
    NR < at { next }
    NR == at { if (on_key_line($0)) { print "not-block"; exit } match($0, /^[ \t]*/); kind = RLENGTH; next }
    {
      if ($0 ~ /^[ \t]*(#.*)?$/) next
      match($0, /^[ \t]*/); ind = RLENGTH; dash = substr($0, ind + 1) ~ /^-( |$)/
      if (ind < kind || (ind == kind && !dash)) exit
      if (iind == "" && !dash) { print "not-block"; exit }
      if (dash && (iind == "" || ind == iind)) { if (iind == "") iind = ind; if (start) print start, last; start = NR }
      last = NR
    }
    END { if (start) print start, last }'
}

to_records() {
  awk -F'\t' -v starts="$1" "$VALUE_ON_KEY_LINE"'
    BEGIN { n = split(starts, S, " ") }
    FNR == NR { text[FNR] = $0; next }
    $1 == ".key" { if ($2 == "trusted_owners") tl = $3; next }
    $1 == "standards-contract" { print "version\t" $2; next }
    $1 == "trusted_owners" || index($1, "trusted_owners.") == 1 {
      if ($1 ~ /^trusted_owners\.[0-9]+$/ && text[$NF] ~ /^[ \t]*- /) {
        if (NF == 3 && $2 !~ /[[:space:]]/) owners[++no] = $2; else print "spaced\t" $NF "\t" $2
      }
      else bad = 1
      next
    }
    $1 ~ /^standards_repositories\./ {
      rest = substr($1, 24); k = rest; sub(/\..*/, "", k); field = substr(rest, length(k) + 2)
      seen[k] = 1
      if (field == "") { prob[k] = "an entry is a mapping with a repo key"; next }
      key = field; sub(/\..*/, "", key); islist = (field != key)
      if (key == "repo" || key == "ref") { if (islist) prob[k] = key " is a single value"; else v[k, key] = $2; next }
      if (key == "topics") { prob[k] = "topics was renamed surfaces in standards-contract 2.0.0"; next }
      if (key == "surfaces" || key == "only_in" || key == "except_in") {
        if (!islist) prob[k] = key " is a list"
        else v[k, key] = (v[k, key] == "" ? "" : v[k, key] " ") $2
        next
      }
      prob[k] = "unknown key " key
    }
    END {
      if (bad || (no && !tl) || on_key_line(text[tl])) print "untrusted\t" (tl ? tl : "?")
      else for (i = 1; i <= no; i++) print "trusted\t" owners[i]
      for (k = 0; k < n; k++) if (k in seen)
        printf "%s%c%s%c%s%c%s%c%s%c%s%c%s\n", S[k + 1], 31, v[k, "repo"], 31, v[k, "ref"], 31, v[k, "surfaces"], 31, v[k, "only_in"], 31, v[k, "except_in"], 31, prob[k]
    }' "$2" -
}

origin_repo() {
  local url
  url=$(git -C "$root" remote get-url origin 2>/dev/null) || return 0
  lower "$(printf '%s' "$url" | sed -e 's#/*$##' -e 's#\.git$##' -e 's#:#/#g' | awk -F/ 'NF >= 2 { print $(NF - 1) "/" $NF }')"
}

glob_hit() {
  local cur=$1 g globs
  read -ra globs <<<"$2"
  for g in ${globs[@]+"${globs[@]}"}; do
    g=$(lower "$g")
    [[ "$g" == */* ]] || g="$g/*"
    # shellcheck disable=SC2254  # the glob in $g is the pattern being matched
    case "$cur" in $g) printf 1; return 0 ;; *) ;; esac
  done
  printf 0
}

version_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); split(b, y, "."); for (i = 1; i <= 3; i++) if (x[i] + 0 != y[i] + 0) exit !(x[i] + 0 < y[i] + 0); exit 1 }'
}

layer_checkout() {
  local repo=$1 sha=$2 verify=$3 dest tmp peeled="$STATE/$1@$2.commit" commit=""
  [[ -f "$peeled" ]] && read -r commit <"$peeled" || true
  [[ "$commit" =~ $SHA_RE ]] && sha=$commit
  dest="$CACHE/$repo@$sha"
  clear_links "$dest" || return 4
  [[ -d "$dest/.git" ]] && { printf '%s\n' "$dest"; return 0; }
  mkdir -p "$(dirname "$dest")"
  tmp=$(mktemp -d "$(dirname "$dest")/.build.XXXXXX")
  if ! { cache_git init -q "$tmp" && git -C "$tmp" remote add origin "${ORG_STANDARDS_GIT_BASE:-https://github.com}/$repo.git"; }; then
    rm -rf "${tmp:?}"; return 4
  fi
  if [[ "$verify" -eq 1 ]]; then
    if ! net_git -C "$tmp" fetch --quiet --filter=blob:none --no-tags origin \
      '+refs/heads/*:refs/remotes/origin/*' '+refs/tags/*:refs/tags/*'; then
      rm -rf "${tmp:?}"; return 4
    fi
    if ! commit=$(GIT_NO_LAZY_FETCH=1 git -C "$tmp" rev-parse --verify --quiet "$sha^{commit}" 2>/dev/null) \
      || [[ -z "$(GIT_NO_LAZY_FETCH=1 git -C "$tmp" for-each-ref --count=1 --contains "$commit" 2>/dev/null)" ]]; then
      rm -rf "${tmp:?}"; return 6
    fi
    if [[ "$commit" != "$sha" ]]; then
      printf '%s\n' "$commit" | write_atomic "$peeled"
      sha=$commit; dest="$CACHE/$repo@$sha"
      clear_links "$dest" || { rm -rf "${tmp:?}"; return 4; }
      [[ ! -d "$dest/.git" ]] || { rm -rf "${tmp:?}"; printf '%s\n' "$dest"; return 0; }
    fi
  elif ! net_git -C "$tmp" fetch --quiet --depth=1 origin "$sha"; then
    rm -rf "${tmp:?}"; return 4
  fi
  if ! checkout_git "$tmp" -c core.symlinks=false -c advice.detachedHead=false checkout --quiet --detach "$sha" >/dev/null 2>&1; then
    rm -rf "${tmp:?}"; return 4
  fi
  place "$tmp" "$dest"
  [[ -d "$dest/.git" ]] && printf '%s\n' "$dest"
}

no_link_below_cache() {
  local p=$1
  while [[ "$p" != "$CACHE" && "$p" != / && "$p" != . ]]; do
    [[ ! -L "$p" ]] || { note "$p is a symbolic link; not written"; return 1; }
    p=$(dirname "$p")
  done
}

write_atomic() {
  local dir tmpf
  dir=$(dirname "$1")
  [[ "$1" == "$STATE"/* ]] || { note "$1 is outside the reader's state; not written"; return 1; }
  no_link_below_cache "$1" || return 1
  mkdir -p "$dir" 2>/dev/null || true
  no_link_below_cache "$1" || return 1
  tmpf=$(mktemp "$dir/.tmp.XXXXXX") || return 1
  cat >"$tmpf" && mv -f "$tmpf" "$1" && return 0
  rm -f "$tmpf"; return 1
}

live_sha() {
  local repo=$1 stamp sha now at=0
  stamp="$STATE/$repo@main"
  now=$(date +%s)
  if [[ -f "$stamp" ]]; then read -r sha at <"$stamp" || true; fi
  [[ "${sha:-}" =~ $SHA_RE && "$at" =~ ^[0-9]+$ ]] || { sha=""; at=0; }
  if [[ -n "${sha:-}" ]] && [[ $((now - at)) -lt "${ORG_STANDARDS_TTL:-3600}" ]] && [[ -d "$CACHE/$repo@$sha/.git" ]]; then
    printf '%s\n' "$sha"; return 0
  fi
  local fresh
  mkdir -p "$CACHE"
  fresh=$(net_git -C "$CACHE" ls-remote "${ORG_STANDARDS_GIT_BASE:-https://github.com}/$repo.git" refs/heads/main | awk 'NR == 1 { print $1 }') || fresh=""
  [[ "$fresh" =~ $SHA_RE ]] || fresh=""
  if [[ -z "$fresh" ]]; then
    [[ -n "${sha:-}" ]] && [[ -d "$CACHE/$repo@$sha/.git" ]] || return 4
    note "refreshing $repo failed; using its main as cached at ${sha:0:12}"
    printf '%s\n' "$sha"; return 0
  fi
  printf '%s %s\n' "$fresh" "$now" | write_atomic "$stamp"
  printf '%s\n' "$fresh"
}

subscription() {
  local file=$1 line=$2 repo=$3 ref=$4 topics=$5 trusted=$6
  local at="$file:$line" owner sha dir status=0 last k old t ids said=""
  local REDIRECT_NOTE="$at: $repo answered with a redirect (for example, it was renamed or moved), which is not followed; set the subscription's repo to its new location"
  local keys=(standards_dir guidance_dir) kinds=("" guidance) labels=("" "guidance ") idx=("" "") out=("" "")
  owner=$(lower "${repo%%/*}")
  if [[ -n "$ref" ]]; then
    sha=$ref
    dir=$(layer_checkout "$repo" "$sha" 1) || status=$?
  elif [[ " $trusted " == *" $owner "* ]]; then
    sha=$(live_sha "$repo") || { note "$at: cannot read $repo; layer skipped this run"; return 0; }
    dir=$(layer_checkout "$repo" "$sha" 0) || status=$?
  else
    note "$at: $repo is not pinned and its owner is not in trusted_owners; subscription refused (pin it with ref: <full commit SHA>)"
    return 0
  fi
  case "$status" in
    0) sha=${dir##*@} ;;
    6) note "$at: $sha is not reachable from a branch or tag of $repo; subscription refused"; return 0 ;;
    *) note "$at: cannot read $repo@${sha:0:12}; layer skipped this run"; return 0 ;;
  esac
  concern_ok "$dir" || { note "$at: $repo@${sha:0:12} has no usable index; layer skipped"; return 0; }
  for k in 0 1; do idx[k]=$(index_of "$dir" "${keys[k]}") || idx[k]=""; done
  [[ -n "${idx[0]}${idx[1]}" ]] || { note "$at: $repo@${sha:0:12} has no standards or guidance index; layer skipped"; return 0; }
  local laststate="$STATE/$repo.last"
  last=""
  [[ -f "$laststate" ]] && read -r last <"$laststate" || true
  [[ "$last" =~ $SHA_RE ]] || last=""
  if [[ -n "$last" ]] && [[ "$last" != "$sha" ]] && clear_links "$CACHE/$repo@$last"; then
    for k in 0 1; do
      [[ -n "${idx[k]}" ]] || continue
      old=$(concern_ok "$CACHE/$repo@$last" 2>/dev/null && index_of "$CACHE/$repo@$last" "${keys[k]}" 2>/dev/null) || old=""
      [[ -n "$old" ]] || continue
      if [[ -n "$ref" ]]; then
        [[ -n "$said" ]] || note "$at: ref of $repo changed from ${last:0:12} to ${sha:0:12}; review the index diff below"
        said=1
        diff -u --label "$repo@${last:0:12} ${labels[k]}index" --label "$repo@${sha:0:12} ${labels[k]}index" "$old" "${idx[k]}" \
          | awk "$ESCAPE"'{ print esc($0, 1) }' >&2 || true
      fi
      while IFS= read -r change; do
        [[ -z "$change" ]] || note "$repo: ${labels[k]}index drift since ${last:0:12}: $change"
      done < <(drift "$old" "${idx[k]}")
    done
  fi
  [[ "$last" == "$sha" ]] || printf '%s\n' "$sha" | write_atomic "$laststate" || true
  if [[ -n "$topics" ]]; then
    ids=$(for k in 0 1; do [[ -z "${idx[k]}" ]] || surfaces "${idx[k]}" | cut -f1; done)
    for t in $topics; do
      grep -qxF -- "$t" <<<"$ids" || note "$at: surface $t is not a Surface id in any index of $repo@${sha:0:12}"
    done
  fi
  for k in 0 1; do
    [[ -z "${idx[k]}" ]] || out[k]=$(confine "$dir" "${idx[k]}" "$topics" "${kinds[k]}") || out[k]=""
  done
  [[ -n "${out[0]}${out[1]}" ]] || { note "$at: $repo@${sha:0:12} has no usable index; layer skipped"; return 0; }
  printf '%s@%s\t%s\t%s\t%s\n' "$repo" "$sha" "$dir" "${out[0]:--}" "${out[1]:--}"
}

read_list() {
  local file=$1 text=$2 ranges="" parsed status=0 list_at errline msg range starts
  parsed=$(printf '%s\n' "$text" | parse_yaml "$awkf") || status=$?
  list_at=$(printf '%s\n' "$parsed" | awk -F'\t' '$1 == ".key" && $2 == "standards_repositories" { print $3 }')
  [[ -z "$list_at" ]] || ranges=$(printf '%s\n' "$text" | list_ranges "$list_at")
  if [[ "$ranges" == not-block ]]; then
    note "subscriptions not read: $file:$list_at: standards_repositories is not a block list; write each entry as a block mapping"
    return 1
  fi
  while [[ "$status" -ne 0 ]]; do
    errline=$(printf '%s\n' "$parsed" | awk -F'\t' '$1 == "error" { print $2; exit }')
    msg=$(printf '%s\n' "$parsed" | awk -F'\t' '$1 == "error" { print $3; exit }')
    range=$(printf '%s\n' "$ranges" | awk -v l="$errline" '$1 <= l + 0 && l + 0 <= $2 { print; exit }')
    if [[ -z "$range" ]]; then
      note "subscriptions not read: $file:$errline: $msg"; return 1
    fi
    note "$file:${range% *}: malformed subscription ($msg at line $errline); entry skipped"
    text=$(printf '%s\n' "$text" | awk -v a="${range% *}" -v b="${range#* }" 'NR >= a && NR <= b { print ""; next } { print }')
    ranges=$(printf '%s\n' "$ranges" | grep -vxF -- "$range" || true)
    status=0
    parsed=$(printf '%s\n' "$text" | parse_yaml "$awkf") || status=$?
  done
  starts=$(printf '%s\n' "$ranges" | awk 'NF { printf "%s%s", sep, $1; sep = " " }')
  printf '%s\n' "$parsed" | awk -F'\t' '$1 == ".nested" { print "nested\t" $2 "\t" $3 }' | sort -t $'\t' -k3,3n
  printf '%s\n' "$parsed" | to_records "$starts" <(printf '%s\n' "$text")
}

listed_entries() {
  local l key entry="^[0-9]+$US"
  while IFS= read -r l; do
    if [[ "$l" == nested$'\t'* ]]; then
      l=${l#nested$'\t'}; key=${l%%$'\t'*}
      note "$1:${l#*$'\t'}: $key is under another key, so it is not read; write ${key##*.} at the top level of the frontmatter"
    elif [[ "$l" =~ $entry ]]; then
      printf '%s%s%s\n' "$1" "$US" "$l"
    fi
  done <<<"$2"
}

ignored_trust() {
  local at
  at=$(key_line "$awkf" "$2" trusted_owners)
  [[ -z "$at" ]] || note "$1:$at: trusted_owners is read from the user-global index only; ignored here"
}

default_ref() {
  local ref
  ref=$(git -C "$root" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || ref=refs/remotes/origin/main
  git -C "$root" rev-parse --verify --quiet "$ref^{commit}" >/dev/null 2>&1 && printf '%s\n' "${ref#refs/remotes/}"
}

subscriptions() {
  if [[ "${STANDARDS_SUBSCRIPTIONS_DISABLED:-}" == "true" ]]; then
    note "subscriptions skipped this session (STANDARDS_SUBSCRIPTIONS_DISABLED=true)"
    return 0
  fi
  [[ -n "${HOME:-}" ]] || { note "subscriptions not read: HOME is not set"; return 0; }
  local file="$HOME/.claude/standards/README.md"
  [[ -e "$file" ]] || return 0
  if ! [[ -f "$file" && -r "$file" ]]; then note "subscriptions not read: user index unreadable ($file)"; return 0; fi
  local awkf
  if [[ -f "$HERE/yaml-subset.awk" ]]; then awkf="$HERE/yaml-subset.awk"
  elif [[ -f "$HERE/../lib/yaml-subset.awk" ]]; then awkf="$HERE/../lib/yaml-subset.awk"
  else note "subscriptions not read: yaml-subset.awk is missing beside $0"; return 0
  fi
  local records version="" trusted="" untrusted_at="" spaced=() item kind value
  records=$(read_list "$file" "$(frontmatter "$file")") || return 0
  while IFS=$'\t' read -r kind value; do
    case "$kind" in
      version) version=$value ;;
      trusted) trusted="$trusted $(lower "$value")" ;;
      untrusted) untrusted_at=$value ;;
      spaced) spaced+=("$value") ;;
      *) ;;
    esac
  done < <(printf '%s\n' "$records" | grep -E $'^(version|trusted|untrusted|spaced)\t' || true)
  if [[ -z "$version" ]]; then
    note "subscriptions not read: $file has no standards-contract frontmatter key, so it is not an index"; return 0
  fi
  local personal
  personal=$(listed_entries "$file" "$records")
  [[ -n "$personal" || -n "$trusted" ]] || return 0
  need_cache
  if [[ -n "$personal" ]] && version_lt "$version" "$SUBSCRIPTIONS_SINCE"; then
    note "$file declares standards-contract $version; standards_repositories needs $SUBSCRIPTIONS_SINCE: update its frontmatter"
  fi
  [[ -z "$untrusted_at" ]] || note "$file:$untrusted_at: trusted_owners is not a block list; no owner is trusted"
  for item in ${spaced[@]+"${spaced[@]}"}; do
    note "$file:${item%%$'\t'*}: trusted_owners item \"${item#*$'\t'}\" holds a space, and an owner name has none; it trusts no owner"
  done
  local layerfile
  for layerfile in "$root/docs/conventions/source-control.yaml" "$root/$CONCERN" "$(concern_ok "$root" 2>/dev/null && index_of "$root" standards_dir 2>/dev/null || true)"; do
    [[ -f "$layerfile" ]] || continue
    ignored_trust "$layerfile" "$(if [[ "$layerfile" == *.md ]]; then frontmatter "$layerfile"; else cat "$layerfile"; fi)"
  done
  local org cur team="" here="" odir status=0 dref text
  org=$(lower "$(yaml_value "$root/docs/conventions/source-control.yaml" standards_repository)")
  cur=$(origin_repo)
  if [[ -n "$org" && " $trusted " == *" ${org%%/*} "* ]]; then
    odir=$(org_dir) || status=$?
    if [[ "$status" -eq 0 ]] && concern_ok "$odir" 2>/dev/null && [[ -f "$odir/$CONCERN" ]]; then
      text=$(cat "$odir/$CONCERN")
      ignored_trust "$odir/$CONCERN" "$text"
      team=$(read_list "$odir/$CONCERN" "$text") && team=$(listed_entries "$odir/$CONCERN" "$team") || team=""
    fi
  fi
  if [[ -n "$cur" && "$cur" != "$org" && " $trusted " == *" ${cur%%/*} "* ]] && dref=$(default_ref) \
    && text=$(GIT_NO_LAZY_FETCH=1 git -C "$root" cat-file blob "refs/remotes/$dref:$CONCERN" 2>/dev/null); then
    ignored_trust "$dref:$CONCERN" "$text"
    here=$(read_list "$dref:$CONCERN" "$text") && here=$(listed_entries "$dref:$CONCERN" "$here") || here=""
  fi
  local label line repo ref topics only except prob i j L=() N=() R=() F=() T=() RL=()
  while IFS="$US" read -r label line repo ref topics only except prob; do
    [[ -n "$label" ]] || continue
    if [[ -z "$prob" ]]; then
      if [[ -z "$repo" ]]; then prob="no repo key"
      elif ! [[ "$repo" =~ $REPO_RE ]]; then prob="repo $repo is not <owner>/<repo>"
      elif [[ -n "$ref" ]] && ! [[ "$ref" =~ $SHA_RE ]]; then prob="ref is not a full commit SHA"
      elif [[ -n "$topics" ]] && ! [[ "$topics" =~ ^[A-Za-z0-9._\ -]+$ ]]; then prob="a surface is not a Surface id"
      fi
    fi
    if [[ -n "$prob" ]]; then note "$label:$line: malformed subscription ($prob); entry skipped"; continue; fi
    if [[ -n "$only" && "$(glob_hit "$cur" "$only")" == 0 ]] || [[ "$(glob_hit "$cur" "$except")" == 1 ]]; then continue; fi
    if [[ -n "$org" ]] && [[ "$(lower "$repo")" == "$org" ]]; then
      note "$label:$line: $repo is also this repository's org layer; it is read once there, at the org layer's commit and team strength${ref:+ (pin ${ref:0:12} skipped)}"
      continue
    fi
    L+=("$label") N+=("$line") R+=("$repo") F+=("$ref") T+=("$topics") RL+=("$(lower "$repo")")
  done < <(printf '%s\n%s\n%s\n' "$team" "$here" "$personal")
  for ((i = 0; i < ${#R[@]}; i++)); do
    for ((j = i + 1; j < ${#R[@]}; j++)); do [[ "${RL[j]}" != "${RL[i]}" ]] || break; done
    if [[ "$j" -lt "${#R[@]}" ]]; then
      note "${L[i]}:${N[i]}: ${R[i]} is listed again at ${L[j]}:${N[j]}; it is read once, there"
      continue
    fi
    subscription "${L[i]}" "${N[i]}" "${R[i]}" "${F[i]}" "${T[i]}" "$trusted"
  done
}

case "$cmd" in
  dir)
    org_dir ;;
  index|guidance)
    org=$(org_dir) || exit $?
    if [[ "$cmd" == index ]]; then key=standards_dir what=standards kind=""; else key=guidance_dir what=guidance kind=guidance; fi
    if ! concern_ok "$org" || ! idx=$(index_of "$org" "$key"); then note "$org has no $what index"; exit 5; fi
    confine "$org" "$idx" "" "$kind" || { note "$org has no usable $what index"; exit 5; } ;;
  subscriptions)
    subscriptions ;;
  review|citations)
    local_file="$root/REVIEW.md"
    parts=()
    first=""
    [[ -f "$local_file" ]] && first=$(first_line "$local_file")
    if [[ "$first" != "$REPLACE_MARKER" ]]; then
      status=0
      org=$(org_dir) || status=$?
      [[ "$status" -eq 0 ]] || [[ "$status" -eq 3 ]] || [[ "$status" -eq 4 ]] || exit "$status"
      if [[ "$status" -eq 0 ]] && [[ -f "$org/REVIEW.md" ]] && ! inside "$org" "$org/REVIEW.md"; then
        note "$org/REVIEW.md resolves outside its checkout; not read"
        status=3
      fi
      if [[ "$status" -eq 0 ]] && [[ -f "$org/REVIEW.md" ]]; then
        parts=("$org/REVIEW.md" "$org" "$(review_drops "$org" "$org/REVIEW.md")")
        ! cmp -s "$org/REVIEW.md" "$local_file" || local_file=""
      fi
    fi
    [[ ! -f "$local_file" ]] || parts+=("$local_file" "$root" "")
    [[ ${#parts[@]} -gt 0 ]] || exit 3
    if [[ "$cmd" == review ]]; then
      for ((i = 0; i < ${#parts[@]}; i += 3)); do
        [[ "$i" -eq 0 ]] || printf '\n<!-- The repository REVIEW.md follows: its criteria add to the organization criteria above. -->\n\n'
        show "${parts[i]}" "${parts[i + 2]}"
      done
    else
      for ((i = 0; i < ${#parts[@]}; i += 3)); do citations "${parts[@]:i:3}"; done | awk 'NF && !seen[$0]++' | show -
    fi ;;
  *)
    die "unknown command: $cmd" ;;
esac
