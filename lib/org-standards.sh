#!/usr/bin/env bash
# shellcheck disable=SC2310  # every function here answers through its return code; callers branch on it
set -euo pipefail

REPLACE_MARKER='<!-- review-base: replace -->'
SUBSCRIPTIONS_SINCE=1.3.0
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
US=$'\037'

die() { printf 'org-standards: %s\n' "$1" >&2; exit "${2:-2}"; }
note() { printf 'org-standards: %s\n' "$1" >&2; }

cmd=${1:-}; shift || true
root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 ]] || die "--root needs a directory"; root=$2; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
case "$cmd" in dir|index|review|subscriptions) ;; *) die "usage: org-standards.sh dir|index|review|subscriptions [--root DIR]" ;; esac
if [[ -z "$root" ]]; then
  root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

yaml_value() {
  [[ -f "$1" ]] || return 0
  sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n 1 | sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' \
    -e "s/^\"\(.*\)\"$/\1/" -e "s/^'\(.*\)'$/\1/"
}

CACHE="${ORG_STANDARDS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-plugins/org-standards}"
STATE="$CACHE/.state"
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

GIT_TIMEOUT=${ORG_STANDARDS_GIT_TIMEOUT:-60}
[[ "$GIT_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || GIT_TIMEOUT=60
net_git() {
  local limit=()
  command -v timeout >/dev/null 2>&1 && limit=(timeout "$GIT_TIMEOUT")
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS='' GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" \
    ${limit[@]+"${limit[@]}"} git -c credential.helper= "$@"
}
REPO_RE='^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*$'
SHA_RE='^[0-9a-f]{40}([0-9a-f]{24})?$'

org_dir() {
  if [[ -n "${STANDARDS_DIR:-}" ]]; then
    [[ -d "$STANDARDS_DIR" ]] || { printf 'org-standards: STANDARDS_DIR %s is not a directory\n' "$STANDARDS_DIR" >&2; return 4; }
    printf '%s\n' "$STANDARDS_DIR"; return 0
  fi
  local repo
  repo=$(yaml_value "$root/docs/conventions/source-control.yaml" standards_repository)
  [[ -n "$repo" ]] || return 3
  if ! [[ "$repo" =~ $REPO_RE ]]; then
    printf 'org-standards: standards_repository %s is not <owner>/<repo>; no org layer\n' "$repo" >&2
    return 3
  fi
  local cache
  cache="$CACHE/$repo"
  local stamp="$cache/.git/org-standards-fetched" ttl="${ORG_STANDARDS_TTL:-3600}" now
  local url="${ORG_STANDARDS_GIT_BASE:-https://github.com}/$repo.git"
  now=$(date +%s)
  if [[ -d "$cache/.git" ]]; then
    if [[ -f "$stamp" ]] && [[ $((now - $(cat "$stamp"))) -lt "$ttl" ]]; then
      printf '%s\n' "$cache"; return 0
    fi
    if net_git -C "$cache" fetch --quiet --depth=1 origin main 2>/dev/null \
      && git -C "$cache" checkout --quiet --force --detach FETCH_HEAD 2>/dev/null; then
      printf '%s\n' "$now" >"$stamp"
    else
      printf 'org-standards: refreshing %s failed; using the copy cached at %s\n' "$repo" "$cache" >&2
    fi
    printf '%s\n' "$cache"; return 0
  fi
  mkdir -p "$(dirname "$cache")"
  local tmp
  tmp=$(mktemp -d "$(dirname "$cache")/.clone.XXXXXX")
  if ! net_git clone --quiet --depth=1 --branch main "$url" "$tmp/c" 2>/dev/null; then
    rm -rf "${tmp:?}"
    printf 'org-standards: cannot clone %s; no org layer this run\n' "$url" >&2
    return 4
  fi
  printf '%s\n' "$now" >"$tmp/c/.git/org-standards-fetched"
  [[ -e "$cache" ]] || mv "$tmp/c" "$cache" 2>/dev/null || true
  rm -rf "${tmp:?}"
  printf '%s\n' "$cache"
}

printable() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'; }

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

path_problem() {
  case "$1" in
    /*) printf 'is absolute' ;;
    ..|../*|*/..|*/../*) printf "has a '..' segment" ;;
    *) [[ "$1" =~ ^[A-Za-z0-9._@+/\ -]*$ ]] && return 1; printf 'is not a relative forward-slash path' ;;
  esac
}

within() {
  local p=$2
  while [[ ! -e "$p" && ! -L "$p" ]]; do p=$(dirname "$p"); done
  inside "$1" "$p"
}

index_of() {
  local conf="$1/.claude/standards.yaml" dir index why
  if [[ -e "$conf" || -L "$conf" ]] && ! inside "$1" "$conf"; then
    note "$conf resolves outside its checkout; no usable index"; return 1
  fi
  dir=$(yaml_value "$conf" standards_dir)
  if why=$(path_problem "$dir"); then
    note "$conf: standards_dir $(printable "$dir") $why; no usable index"; return 1
  fi
  index="$1/${dir:-docs/standards}"; index="${index%/}/README.md"
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
{ f = C[4]; if (f ~ /^`[^`]+`$/) f = substr(f, 2, length(f) - 2); print NR "\037row\037" C[2] "\037" f }'
# shellcheck disable=SC2016  # an awk program; awk expands its own $ fields
EMIT="$TABLE_CELLS"'
BEGIN { m = split(ENVIRON["KEEP"], K, "\n"); for (i = 1; i <= m; i++) if (K[i] != "") { t = index(K[i], "\t"); keep[substr(K[i], 1, t - 1)] = substr(K[i], t + 1) } }
index($0, "|") == 0 { print; next }
!(FNR in keep) { next }
keep[FNR] == "" { print; next }
{ cells($0); print "| " C[2] " | " C[3] " | " keep[FNR] " |" }'
BAD_CELL='[[:cntrl:]|`]'

locate() {
  local root=$1 sdir=$2 f=$3 why cand
  [[ -n "$f" ]] || { printf 'is empty'; return 1; }
  if why=$(path_problem "$f"); then printf '%s' "$why"; return 1; fi
  cand="$sdir/$f"
  if ! [[ -e "$cand" || -L "$cand" ]] && [[ -e "$root/$f" || -L "$root/$f" ]]; then cand="$root/$f"; fi
  within "$root" "$cand" || { printf 'resolves outside its checkout'; return 1; }
  [[ ! -e "$cand" ]] || cand=$(phys "$cand") || { printf 'resolves outside its checkout'; return 1; }
  [[ ! "$cand" =~ $BAD_CELL ]] || { printf 'resolves to a path a table cell cannot hold'; return 1; }
  printf '%s' "$cand"
}

confine() {
  local root=$1 index=$2 topics=$3 sdir line kind id f path keep="" key out
  sdir=$(dirname "$index")
  while IFS="$US" read -r line kind id f; do
    case "$kind" in
      head) keep+="$line"$'\t\n' ;;
      row)
        if ! path=$(locate "$root" "$sdir" "$f"); then
          note "$index:$line: File $(printable "$f") $path; row dropped"
        elif [[ -z "$topics" || " $topics " == *" $id "* ]]; then
          keep+="$line"$'\t'"$path"$'\n'
        fi ;;
      *) note "$index:$line: not a row of the index table; line dropped" ;;
    esac
  done < <(awk "$CLASSIFY" "$index")
  key=$(tr ' ' '\n' <<<"$topics" | sort -u | paste -sd+ -)
  out="$STATE/confined/$(printf '%s' "$index" | git hash-object --stdin).${key:-@all}.md"
  KEEP=$keep awk "$EMIT" "$index" | write_atomic "$out" || return 1
  printf '%s\n' "$out"
}

surfaces() {
  awk "$CLASSIFY" "$1" | awk -F"$US" '$2 == "row" { print $3 "\t" $4 }' | sort -u
}

# Prints a REVIEW.md, dropping each line whose `<path>.md#<heading>` citation leaves the checkout.
# shellcheck disable=SC2016  # an awk program; awk expands its own $ fields
CITATIONS='
{
  line = $0
  while (match(line, /`[^`]*`/)) {
    s = substr(line, RSTART + 1, RLENGTH - 2)
    if (index(s, ".md#")) print NR "\037" s
    line = substr(line, 1, RSTART - 1) " " substr(line, RSTART + RLENGTH)
  }
  n = split(line, W, /[ \t()<>"\047\[\]]+/)
  for (i = 1; i <= n; i++) if (index(W[i], ".md#")) print NR "\037" W[i]
}'
confine_review() {
  local root=$1 file=$2 line cite path why drop=""
  while IFS="$US" read -r line cite; do
    path=${cite%#*}
    if why=$(path_problem "$path"); then :
    elif ! within "$root" "$root/$path"; then why="resolves outside the org checkout"
    else continue
    fi
    note "$file:$line: citation $(printable "$cite") $why; line dropped"
    drop="$drop $line"
  done < <(awk "$CITATIONS" "$file")
  awk -v drop="$drop" 'BEGIN { n = split(drop, D, " "); for (i = 1; i <= n; i++) gone[D[i]] = 1 } !(FNR in gone)' "$file"
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
  awk 'NR == 1 { if ($0 != "---") exit; print ""; next } $0 == "---" { exit } { print }' "$1"
}

list_ranges() {
  awk '
    /^standards_repositories:/ {
      v = $0; sub(/^standards_repositories:[ \t]*/, "", v)
      if (v != "" && v !~ /^#/) { print "flow", NR; exit }
      inlist = 1; next
    }
    inlist {
      if ($0 ~ /^[ \t]*(#.*)?$/) next
      match($0, /^ */); ind = RLENGTH; rest = substr($0, ind + 1)
      if (ind == 0 && rest !~ /^-( |$)/) { inlist = 0; if (start) print start, last; start = 0; next }
      if (rest ~ /^-( |$)/ && (iind == "" || ind == iind)) { if (iind == "") iind = ind; if (start) print start, last; start = NR }
      last = NR
    }
    END { if (start) print start, last }'
}

to_records() {
  awk -F'\t' -v starts="$1" '
    BEGIN { n = split(starts, S, " ") }
    $1 == "standards-contract" { print "version\t" $2; next }
    $1 ~ /^trusted_owners(\.[0-9]+)?$/ { print "trusted\t" $2; next }
    $1 ~ /^standards_repositories\./ {
      rest = substr($1, 24); k = rest; sub(/\..*/, "", k); field = substr(rest, length(k) + 2)
      seen[k] = 1
      if (field == "") { prob[k] = "an entry is a mapping with a repo key"; next }
      key = field; sub(/\..*/, "", key); islist = (field != key)
      if (key == "repo" || key == "ref") { if (islist) prob[k] = key " is a single value"; else v[k, key] = $2; next }
      if (key == "topics" || key == "only_in" || key == "except_in") {
        if (!islist) prob[k] = key " is a list"
        else v[k, key] = (v[k, key] == "" ? "" : v[k, key] " ") $2
        next
      }
      prob[k] = "unknown key " key
    }
    END {
      for (k = 0; k < n; k++) if (k in seen)
        printf "%s%c%s%c%s%c%s%c%s%c%s%c%s\n", S[k + 1], 31, v[k, "repo"], 31, v[k, "ref"], 31, v[k, "topics"], 31, v[k, "only_in"], 31, v[k, "except_in"], 31, prob[k]
    }'
}

origin_repo() {
  local url
  url=$(git -C "$root" remote get-url origin 2>/dev/null) || return 0
  lower "$(printf '%s' "$url" | sed -e 's#/*$##' -e 's#\.git$##' -e 's#:#/#g' | awk -F/ 'NF >= 2 { print $(NF - 1) "/" $NF }')"
}

glob_hit() {
  local cur=$1 g globs
  read -ra globs <<<"$2"
  for g in "${globs[@]}"; do
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
  local repo=$1 sha=$2 verify=$3 dest tmp leaf peeled="$STATE/$1@$2.commit" commit=""
  [[ -f "$peeled" ]] && read -r commit <"$peeled" || true
  [[ "$commit" =~ $SHA_RE ]] && sha=$commit
  dest="$CACHE/$repo@$sha"
  [[ -d "$dest/.git" ]] && { printf '%s\n' "$dest"; return 0; }
  mkdir -p "$(dirname "$dest")"
  tmp=$(mktemp -d "$(dirname "$dest")/.build.XXXXXX")
  leaf=$(basename "$tmp")
  if ! { git init -q "$tmp" && git -C "$tmp" remote add origin "${ORG_STANDARDS_GIT_BASE:-https://github.com}/$repo.git"; }; then
    rm -rf "${tmp:?}"; return 4
  fi
  if [[ "$verify" -eq 1 ]]; then
    if ! net_git -C "$tmp" fetch --quiet --filter=blob:none --no-tags origin \
      '+refs/heads/*:refs/remotes/origin/*' '+refs/tags/*:refs/tags/*' 2>/dev/null; then
      rm -rf "${tmp:?}"; return 4
    fi
    if ! commit=$(GIT_NO_LAZY_FETCH=1 git -C "$tmp" rev-parse --verify --quiet "$sha^{commit}" 2>/dev/null) \
      || [[ -z "$(GIT_NO_LAZY_FETCH=1 git -C "$tmp" for-each-ref --count=1 --contains "$commit" 2>/dev/null)" ]]; then
      rm -rf "${tmp:?}"; return 6
    fi
    if [[ "$commit" != "$sha" ]]; then
      mkdir -p "$(dirname "$peeled")" && printf '%s\n' "$commit" | write_atomic "$peeled"
      sha=$commit; dest="$CACHE/$repo@$sha"
      [[ ! -d "$dest/.git" ]] || { rm -rf "${tmp:?}"; printf '%s\n' "$dest"; return 0; }
    fi
  elif ! net_git -C "$tmp" fetch --quiet --depth=1 origin "$sha" 2>/dev/null; then
    rm -rf "${tmp:?}"; return 4
  fi
  if ! net_git -C "$tmp" -c core.symlinks=false -c advice.detachedHead=false checkout --quiet --detach "$sha" >/dev/null 2>&1; then
    rm -rf "${tmp:?}"; return 4
  fi
  mv "$tmp" "$dest" 2>/dev/null || rm -rf "${tmp:?}"
  [[ ! -e "$dest/$leaf" ]] || rm -rf "${dest:?}/$leaf"
  [[ -d "$dest/.git" ]] && printf '%s\n' "$dest"
}

write_atomic() {
  local dir p tmpf
  dir=$(dirname "$1")
  [[ "$1" == "$STATE"/* ]] || { note "$1 is outside the reader's state; not written"; return 1; }
  mkdir -p "$dir" 2>/dev/null || true
  p=$1
  while [[ "$p" != "$CACHE" && "$p" != / && "$p" != . ]]; do
    [[ ! -L "$p" ]] || { note "$p is a symbolic link; not written"; return 1; }
    p=$(dirname "$p")
  done
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
  fresh=$(net_git ls-remote "${ORG_STANDARDS_GIT_BASE:-https://github.com}/$repo.git" refs/heads/main 2>/dev/null | awk 'NR == 1 { print $1 }') || fresh=""
  [[ "$fresh" =~ $SHA_RE ]] || fresh=""
  if [[ -z "$fresh" ]]; then
    [[ -n "${sha:-}" ]] && [[ -d "$CACHE/$repo@$sha/.git" ]] || return 4
    note "refreshing $repo failed; using its main as cached at ${sha:0:12}"
    printf '%s\n' "$sha"; return 0
  fi
  mkdir -p "$(dirname "$stamp")"
  printf '%s %s\n' "$fresh" "$now" | write_atomic "$stamp"
  printf '%s\n' "$fresh"
}

subscription() {
  local file=$1 line=$2 repo=$3 ref=$4 topics=$5 only=$6 except=$7 org=$8 cur=$9 trusted=${10}
  local at="$file:$line" owner repo_l only_hit except_hit sha dir status=0 index last laststate
  owner=$(lower "${repo%%/*}")
  repo_l=$(lower "$repo")
  only_hit=$(glob_hit "$cur" "$only")
  except_hit=$(glob_hit "$cur" "$except")
  if [[ -n "$only" && "$only_hit" == 0 ]] || [[ "$except_hit" == 1 ]]; then return 0; fi
  if [[ -n "$org" ]] && [[ "$repo_l" == "$org" ]]; then
    note "$at: $repo is also this repository's org layer; it is read once there, at the org layer's commit and team strength${ref:+ (pin ${ref:0:12} skipped)}"
    return 0
  fi
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
  index=$(index_of "$dir") || { note "$at: $repo@${sha:0:12} has no standards index; layer skipped"; return 0; }
  laststate="$STATE/$repo.last"
  last=""
  [[ -f "$laststate" ]] && read -r last <"$laststate" || true
  [[ "$last" =~ $SHA_RE ]] || last=""
  if [[ -n "$last" ]] && [[ "$last" != "$sha" ]]; then
    local old
    old=$(index_of "$CACHE/$repo@$last" 2>/dev/null) || old=""
    if [[ -n "$old" ]]; then
      if [[ -n "$ref" ]]; then
        note "$at: ref of $repo changed from ${last:0:12} to ${sha:0:12}; review the index diff below"
        diff -u --label "$repo@${last:0:12}" --label "$repo@${sha:0:12}" "$old" "$index" \
          | LC_ALL=C tr -d '\000-\010\013-\037\177' >&2 || true
      fi
      while IFS= read -r change; do
        [[ -z "$change" ]] || note "$repo: index drift since ${last:0:12}: $(printable "$change")"
      done < <(drift "$old" "$index")
    fi
  fi
  [[ "$last" == "$sha" ]] || { mkdir -p "$(dirname "$laststate")" && printf '%s\n' "$sha" | write_atomic "$laststate"; }
  if [[ -n "$topics" ]]; then
    local t ids
    ids=$(surfaces "$index" | cut -f1)
    for t in $topics; do
      grep -qxF -- "$t" <<<"$ids" || note "$at: topic $t is not a Surface id in the index of $repo@${sha:0:12}"
    done
  fi
  index=$(confine "$dir" "$index" "$topics") || { note "$at: $repo@${sha:0:12} has no usable index; layer skipped"; return 0; }
  printf '%s@%s\t%s\t%s\n' "$repo" "$sha" "$dir" "$index"
}

subscriptions() {
  if [[ "${STANDARDS_SUBSCRIPTIONS_DISABLED:-}" == "true" ]]; then
    note "personal subscriptions skipped this session (STANDARDS_SUBSCRIPTIONS_DISABLED=true)"
    return 0
  fi
  local file="$HOME/.claude/standards/README.md"
  [[ -e "$file" ]] || return 0
  if ! [[ -f "$file" && -r "$file" ]]; then note "subscriptions not read: user index unreadable ($file)"; return 0; fi
  local awkf
  if [[ -f "$HERE/yaml-subset.awk" ]]; then awkf="$HERE/yaml-subset.awk"
  elif [[ -f "$HERE/../lib/yaml-subset.awk" ]]; then awkf="$HERE/../lib/yaml-subset.awk"
  else note "subscriptions not read: yaml-subset.awk is missing beside $0"; return 0
  fi
  local text ranges parsed errline msg range
  text=$(frontmatter "$file")
  ranges=$(printf '%s\n' "$text" | list_ranges)
  if [[ "$ranges" == flow* ]]; then
    note "subscriptions not read: $file:${ranges#flow }: standards_repositories is not a block list; write each entry as a block mapping"
    return 0
  fi
  while ! parsed=$(printf '%s\n' "$text" | awk -f "$awkf"); do
    errline=$(printf '%s\n' "$parsed" | awk -F'\t' '$1 == "error" { print $2; exit }')
    msg=$(printf '%s\n' "$parsed" | awk -F'\t' '$1 == "error" { print $3; exit }')
    range=$(printf '%s\n' "$ranges" | awk -v l="$errline" '$1 <= l + 0 && l + 0 <= $2 { print; exit }')
    if [[ -z "$range" ]]; then
      note "subscriptions not read: $file:$errline: $msg"; return 0
    fi
    note "$file:${range% *}: malformed subscription ($msg at line $errline); entry skipped"
    text=$(printf '%s\n' "$text" | awk -v a="${range% *}" -v b="${range#* }" 'NR >= a && NR <= b { print ""; next } { print }')
    ranges=$(printf '%s\n' "$ranges" | grep -vxF -- "$range" || true)
  done
  local records version="" trusted="" starts
  starts=$(printf '%s\n' "$ranges" | awk 'NF { printf "%s%s", sep, $1; sep = " " }')
  records=$(printf '%s\n' "$parsed" | to_records "$starts")
  [[ -n "$records" ]] || return 0
  while IFS=$'\t' read -r kind value; do
    case "$kind" in
      version) version=$value ;;
      trusted) trusted="$trusted $(lower "$value")" ;;
      *) ;;
    esac
  done < <(printf '%s\n' "$records" | grep -E $'^(version|trusted)\t' || true)
  if [[ -z "$version" ]]; then
    note "subscriptions not read: $file has no standards-contract frontmatter key, so it is not an index"; return 0
  fi
  local entries
  entries=$(printf '%s\n' "$records" | grep -vE $'^(version|trusted)\t' || true)
  [[ -n "$entries" ]] || return 0
  if version_lt "$version" "$SUBSCRIPTIONS_SINCE"; then
    note "$file declares standards-contract $version; standards_repositories needs $SUBSCRIPTIONS_SINCE: update its frontmatter"
  fi
  local org cur line repo ref topics only except prob layerfile at
  for layerfile in "$root/docs/conventions/source-control.yaml" "$(index_of "$root" 2>/dev/null || true)"; do
    [[ -f "$layerfile" ]] || continue
    at=$(if [[ "$layerfile" == *.md ]]; then frontmatter "$layerfile"; else cat "$layerfile"; fi | grep -n -m1 '^trusted_owners:' | cut -d: -f1 || true)
    [[ -z "$at" ]] || note "$layerfile:$at: trusted_owners is read from the user-global index only; ignored here"
  done
  org=$(lower "$(yaml_value "$root/docs/conventions/source-control.yaml" standards_repository)")
  cur=$(origin_repo)
  while IFS="$US" read -r line repo ref topics only except prob; do
    if [[ -z "$prob" ]]; then
      if [[ -z "$repo" ]]; then prob="no repo key"
      elif ! [[ "$repo" =~ $REPO_RE ]]; then prob="repo $repo is not <owner>/<repo>"
      elif [[ -n "$ref" ]] && ! [[ "$ref" =~ $SHA_RE ]]; then prob="ref is not a full commit SHA"
      elif [[ -n "$topics" ]] && ! [[ "$topics" =~ ^[A-Za-z0-9._\ -]+$ ]]; then prob="a topic is not a Surface id"
      fi
    fi
    if [[ -n "$prob" ]]; then note "$file:$line: malformed subscription ($prob); entry skipped"; continue; fi
    subscription "$file" "$line" "$repo" "$ref" "$topics" "$only" "$except" "$org" "$cur" "$trusted"
  done <<<"$entries"
}

case "$cmd" in
  dir)
    org_dir ;;
  index)
    org=$(org_dir) || exit $?
    idx=$(index_of "$org") || { printf 'org-standards: %s has no standards index\n' "$org" >&2; exit 5; }
    confine "$org" "$idx" "" || { printf 'org-standards: %s has no usable index\n' "$org" >&2; exit 5; } ;;
  subscriptions)
    subscriptions ;;
  review)
    local_file="$root/REVIEW.md"
    first=""
    [[ -f "$local_file" ]] && first=$(first_line "$local_file")
    if [[ "$first" = "$REPLACE_MARKER" ]]; then
      cat "$local_file"; exit 0
    fi
    status=0
    org=$(org_dir) || status=$?
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 3 ]] || [[ "$status" -eq 4 ]] || exit "$status"
    if [[ "$status" -eq 0 ]] && [[ -f "$org/REVIEW.md" ]] && ! inside "$org" "$org/REVIEW.md"; then
      note "$org/REVIEW.md resolves outside its checkout; not read"
      status=3
    fi
    if [[ "$status" -eq 0 ]] && [[ -f "$org/REVIEW.md" ]]; then
      confine_review "$org" "$org/REVIEW.md"
      if [[ -f "$local_file" ]] && ! cmp -s "$org/REVIEW.md" "$local_file"; then
        printf '\n<!-- The repository REVIEW.md follows: its criteria add to the organization criteria above. -->\n\n'
        cat "$local_file"
      fi
    elif [[ -f "$local_file" ]]; then
      cat "$local_file"
    else
      exit 3
    fi ;;
  *)
    die "unknown command: $cmd" ;;
esac
