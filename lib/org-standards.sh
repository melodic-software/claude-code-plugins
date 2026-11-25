#!/usr/bin/env bash
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
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
REPO_RE='^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$'

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
    if git -C "$cache" fetch --quiet --depth=1 origin main 2>/dev/null \
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
  if ! git clone --quiet --depth=1 --branch main "$url" "$tmp/c" 2>/dev/null; then
    rm -rf "${tmp:?}"
    printf 'org-standards: cannot clone %s; no org layer this run\n' "$url" >&2
    return 4
  fi
  printf '%s\n' "$now" >"$tmp/c/.git/org-standards-fetched"
  [[ -e "$cache" ]] || mv "$tmp/c" "$cache" 2>/dev/null || true
  rm -rf "${tmp:?}"
  printf '%s\n' "$cache"
}

index_of() {
  local dir index
  dir=$(yaml_value "$1/.claude/standards.yaml" standards_dir)
  index="$1/${dir:-docs/standards}"; index="${index%/}/README.md"
  [[ -f "$index" ]] && awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { exit 1 } /^standards-contract:/ { found = 1; exit } END { exit !found }' "$index" \
    && printf '%s\n' "$index"
}

first_line() { awk 'NF { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$1"; }

TABLE_SEP='^[|][ :|-]+$'

surfaces() {
  awk -v sepre="$TABLE_SEP" -F'|' '
    sep && /^\|/ { id = $2; f = $4; gsub(/^[ \t]+|[ \t]+$/, "", id); gsub(/^[ \t]+|[ \t]+$/, "", f); if (id != "") print id "\t" f; next }
    $0 ~ sepre { sep = 1 }' "$1" | sort -u
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
  local repo=$1 sha=$2 verify=$3 dest tmp leaf
  dest="$CACHE/$repo@$sha"
  [[ -d "$dest/.git" ]] && { printf '%s\n' "$dest"; return 0; }
  mkdir -p "$(dirname "$dest")"
  tmp=$(mktemp -d "$(dirname "$dest")/.build.XXXXXX")
  leaf=$(basename "$tmp")
  if ! { git init -q "$tmp" && git -C "$tmp" remote add origin "${ORG_STANDARDS_GIT_BASE:-https://github.com}/$repo.git"; }; then
    rm -rf "${tmp:?}"; return 4
  fi
  if [[ "$verify" -eq 1 ]]; then
    if ! git -C "$tmp" fetch --quiet --filter=blob:none --no-tags origin \
      '+refs/heads/*:refs/remotes/origin/*' '+refs/tags/*:refs/tags/*' 2>/dev/null; then
      rm -rf "${tmp:?}"; return 4
    fi
    if ! git -C "$tmp" cat-file -e "$sha^{commit}" 2>/dev/null \
      || [[ -z "$(git -C "$tmp" for-each-ref --count=1 --contains "$sha" 2>/dev/null)" ]]; then
      rm -rf "${tmp:?}"; return 6
    fi
  elif ! git -C "$tmp" fetch --quiet --depth=1 origin "$sha" 2>/dev/null; then
    rm -rf "${tmp:?}"; return 4
  fi
  if ! git -C "$tmp" -c core.symlinks=false -c advice.detachedHead=false checkout --quiet --detach "$sha" 2>/dev/null; then
    rm -rf "${tmp:?}"; return 4
  fi
  if [[ -e "$dest" ]]; then
    rm -rf "${tmp:?}"
  else
    mv "$tmp" "$dest" 2>/dev/null || rm -rf "${tmp:?}"
    [[ ! -e "$dest/$leaf" ]] || rm -rf "${dest:?}/$leaf"
  fi
  [[ -d "$dest/.git" ]] && printf '%s\n' "$dest"
}

write_atomic() {
  local tmpf
  tmpf=$(mktemp "$(dirname "$1")/.tmp.XXXXXX")
  cat >"$tmpf" && mv -f "$tmpf" "$1"
}

live_sha() {
  local repo=$1 stamp sha now at=0
  stamp="$CACHE/$repo@main"
  now=$(date +%s)
  if [[ -f "$stamp" ]]; then read -r sha at <"$stamp" || true; fi
  if [[ -n "${sha:-}" ]] && [[ $((now - at)) -lt "${ORG_STANDARDS_TTL:-3600}" ]] && [[ -d "$CACHE/$repo@$sha/.git" ]]; then
    printf '%s\n' "$sha"; return 0
  fi
  local fresh
  fresh=$(git ls-remote "${ORG_STANDARDS_GIT_BASE:-https://github.com}/$repo.git" refs/heads/main 2>/dev/null | awk 'NR == 1 { print $1 }') || fresh=""
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
  # shellcheck disable=SC2310  # layer_checkout's and live_sha's return codes are the answer, not a failure
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
    0) ;;
    6) note "$at: $sha is not reachable from a branch or tag of $repo; subscription refused"; return 0 ;;
    *) note "$at: cannot read $repo@${sha:0:12}; layer skipped this run"; return 0 ;;
  esac
  # shellcheck disable=SC2310  # index_of failing means no index, reported here
  index=$(index_of "$dir") || { note "$at: $repo@${sha:0:12} has no standards index; layer skipped"; return 0; }
  laststate="$CACHE/$repo.last"
  last=""
  [[ -f "$laststate" ]] && read -r last <"$laststate" || true
  if [[ -n "$last" ]] && [[ "$last" != "$sha" ]]; then
    local old
    # shellcheck disable=SC2310  # a last read whose checkout is gone has nothing to diff against
    old=$(index_of "$CACHE/$repo@$last" 2>/dev/null) || old=""
    if [[ -n "$old" ]]; then
      if [[ -n "$ref" ]]; then
        note "$at: ref of $repo changed from ${last:0:12} to ${sha:0:12}; review the index diff below"
        diff -u --label "$repo@${last:0:12}" --label "$repo@${sha:0:12}" "$old" "$index" >&2 || true
      fi
      while IFS= read -r change; do
        [[ -z "$change" ]] || note "$repo: index drift since ${last:0:12}: $change"
      done < <(drift "$old" "$index")
    fi
  fi
  [[ "$last" == "$sha" ]] || printf '%s\n' "$sha" | write_atomic "$laststate"
  if [[ -n "$topics" ]]; then
    local t ids filtered
    ids=$(surfaces "$index" | cut -f1)
    for t in $topics; do
      grep -qxF -- "$t" <<<"$ids" || note "$at: topic $t is not a Surface id in the index of $repo@${sha:0:12}"
    done
    filtered="$(dirname "$index")/.README.$(tr ' ' '\n' <<<"$topics" | sort -u | paste -sd+ -).md"
    awk -v sepre="$TABLE_SEP" -v topics="$topics" '
      BEGIN { n = split(topics, T, " "); for (i = 1; i <= n; i++) keep[T[i]] = 1 }
      sep && /^\|/ { id = $0; sub(/^\|[ \t]*/, "", id); sub(/[ \t]*\|.*$/, "", id); if (id in keep) print; next }
      $0 ~ sepre { sep = 1 }
      { print }' "$index" | write_atomic "$filtered"
    index=$filtered
  fi
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
  # shellcheck disable=SC2310  # version_lt's return code is the answer
  if version_lt "$version" "$SUBSCRIPTIONS_SINCE"; then
    note "$file declares standards-contract $version; standards_repositories needs $SUBSCRIPTIONS_SINCE: update its frontmatter"
  fi
  export GIT_TERMINAL_PROMPT=0
  local org cur line repo ref topics only except prob
  org=$(lower "$(yaml_value "$root/docs/conventions/source-control.yaml" standards_repository)")
  cur=$(origin_repo)
  while IFS="$US" read -r line repo ref topics only except prob; do
    if [[ -z "$prob" ]]; then
      if [[ -z "$repo" ]]; then prob="no repo key"
      elif ! [[ "$repo" =~ $REPO_RE ]]; then prob="repo $repo is not <owner>/<repo>"
      elif [[ -n "$ref" ]] && ! [[ "$ref" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then prob="ref is not a full commit SHA"
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
    # shellcheck disable=SC2310  # org_dir's return code is the answer, not a failure
    org=$(org_dir) || exit $?
    # shellcheck disable=SC2310  # index_of failing means no index, reported below
    index_of "$org" || { printf 'org-standards: %s has no standards index\n' "$org" >&2; exit 5; } ;;
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
    # shellcheck disable=SC2310  # org_dir's return code is the answer, not a failure
    org=$(org_dir) || status=$?
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 3 ]] || [[ "$status" -eq 4 ]] || exit "$status"
    if [[ "$status" -eq 0 ]] && [[ -f "$org/REVIEW.md" ]]; then
      cat "$org/REVIEW.md"
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
