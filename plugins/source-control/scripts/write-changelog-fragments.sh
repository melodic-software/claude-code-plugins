#!/usr/bin/env bash
set -uo pipefail

self="${0##*/}"
usage() {
  echo "usage: $self [--base <ref>] [--level major|minor|patch|none] < message" >&2
  exit 2
}

base="" level=""
while (($#)); do
  case "$1" in
  --base)
    (($# >= 2)) || usage
    base="$2"
    shift 2
    ;;
  --level)
    (($# >= 2)) && [[ "$2" =~ ^(major|minor|patch|none)$ ]] || usage
    level="$2"
    shift 2
    ;;
  *) usage ;;
  esac
done

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "$self: not inside a git work tree." >&2
  exit 2
}
cd "$root" || exit 2
list=scripts/fragment-plugins.txt creator=scripts/new-changelog-fragment.sh
[[ -f "$list" ]] || exit 0
if [[ ! -f "$creator" ]]; then
  echo "$self: $list exists but $creator does not; cannot create fragments." >&2
  exit 2
fi

message="$(tr -d '\r')"

if [[ -n "$base" ]]; then
  paths="$(git diff --name-only "$base...HEAD")" || {
    echo "$self: git diff $base...HEAD failed." >&2
    exit 2
  }
else
  paths="$(git diff --cached --name-only)" || exit 2
fi

declare -A listed=()
while IFS= read -r name; do
  name="${name%%#*}"
  name="${name//[[:space:]]/}"
  [[ -z "$name" ]] || listed["$name"]=1
done < <(tr -d '\r' <"$list")

declare -A seen=()
plugins=()
while IFS= read -r path; do
  case "$path" in
  plugins/*/*)
    name="${path#plugins/}" name="${name%%/*}"
    [[ -f "plugins/$name/.claude-plugin/plugin.json" ]] || continue
    ;;
  docs/contracts/*/* | docs/conventions/*/*)
    name="${path#docs/*/}" name="${name%%/*}" home="${path%%/"$name"/*}"
    [[ ! -f "plugins/$name/.claude-plugin/plugin.json" && -f "$home/$name/CHANGELOG.md" ]] || continue
    ;;
  *) continue ;;
  esac
  [[ -n "${listed[$name]:-}" && -z "${seen[$name]:-}" ]] || continue
  seen["$name"]=1
  plugins+=("$name")
done <<<"$paths"
((${#plugins[@]})) || exit 0

subject="$(sed -n '/[^[:space:]]/{p;q;}' <<<"$message")"
type="" desc="$subject" derived_breaking=""
cc='^([a-z]+)(\([^)]*\))?(!)?:[[:space:]]+(.+)$'
if [[ "$subject" =~ $cc ]]; then
  type="${BASH_REMATCH[1]}" desc="${BASH_REMATCH[4]}"
  breaking="${BASH_REMATCH[3]}"
  grep -Eq '^BREAKING[ -]CHANGE:' <<<"$message" && breaking="!"
  if [[ -z "$level" && -n "$breaking" ]]; then
    level=major derived_breaking=1
  elif [[ -z "$level" ]]; then
    case "$type" in
    feat) level="minor" ;;
    fix | perf) level="patch" ;;
    build | chore | ci | docs | refactor | style | test) level="none" ;;
    *) ;;
    esac
  fi
fi
if [[ -z "$level" ]]; then
  echo "$self: cannot tell the bump level from \"$subject\"; pass --level major|minor|patch|none." >&2
  exit 2
fi
[[ -n "$desc" ]] || {
  echo "$self: the message is empty." >&2
  exit 2
}
case "$type" in
feat) section=Added ;;
fix) section=Fixed ;;
*) section=Changed ;;
esac

body="$(awk '
  !started { if ($0 ~ /[^[:space:]]/) started = 1; next }
  { line[++n] = $0 }
  END {
    while (n > 0 && line[n] !~ /[^[:space:]]/) n--
    last = n
    while (last > 0 && line[last] ~ /[^[:space:]]/) last--
    trailers = (last < n)
    for (i = last + 1; i <= n; i++)
      if (line[i] !~ /^([A-Za-z][A-Za-z0-9-]*|BREAKING CHANGE): /) trailers = 0
    if (trailers) {
      for (i = last + 1; i <= n; i++)
        if (sub(/^BREAKING[ -]CHANGE:[ \t]*/, "", line[i])) brk[++nb] = line[i]
      n = last
    }
    while (n > 0 && line[n] !~ /[^[:space:]]/) n--
    s = 1
    while (s <= n && line[s] !~ /[^[:space:]]/) s++
    for (i = s; i <= n; i++) print (line[i] ~ /[^[:space:]]/ ? "  " line[i] : "")
    for (i = 1; i <= nb; i++) print ((n >= s || i > 1) ? "\n" : "") "  **Breaking:** " brk[i]
  }' <<<"$message")"

derived_level="$level"
set_change() {
  local lead=""
  level="$derived_level"
  if [[ -n "$derived_breaking" && "$(version_of "$1")" == 0.* ]]; then
    level=minor lead="**Breaking:** "
  fi
  entry="- $lead$desc"
  [[ -z "$body" ]] || entry+=$'\n\n'"$body"
  if [[ "$level" == none ]]; then
    block="No release needed (${type:-no type}): $desc"
  else
    block="### $section"$'\n\n'"$entry"
  fi
}
version_of() {
  local f="plugins/$1/.claude-plugin/plugin.json"
  if [[ -f "$f" ]]; then
    awk 'match($0, /"version"[ \t]*:[ \t]*"[^"]*"/) { v = substr($0, RSTART, RLENGTH); sub(/^"version"[ \t]*:[ \t]*"/, "", v); sub(/"$/, "", v); print v; exit }' "$f"
    return
  fi
  for f in "docs/contracts/$1/CHANGELOG.md" "docs/conventions/$1/CHANGELOG.md"; do
    [[ -f "$f" ]] || continue
    awk 'match($0, /^##[ \t]+\[?[0-9]+\.[0-9]+\.[0-9]+/) { v = substr($0, RSTART, RLENGTH); sub(/^##[ \t]+\[?/, "", v); print v; exit }' "$f"
    return
  done
}

ref="$base"
if [[ -z "$ref" ]]; then
  ref="$(git symbolic-ref -q --short refs/remotes/origin/HEAD)" || ref=""
  for candidate in origin/main main; do
    [[ -z "$ref" ]] || break
    git rev-parse -q --verify "$candidate" >/dev/null && ref="$candidate"
  done
fi
added="$(
  [[ -z "$ref" ]] || git diff --name-only --diff-filter=A "$ref...HEAD" -- .changes/
  git diff --cached --name-only --diff-filter=A -- .changes/
  git ls-files --others --exclude-standard -- .changes/
)"

rank() { case "$1" in major) echo 3 ;; minor) echo 2 ;; patch) echo 1 ;; *) echo 0 ;; esac }
bump_of() { awk '{ sub(/\r$/, "") } NR > 1 && $0 == "---" { exit } sub(/^bump:[ \t]*/, "") { sub(/[ \t]+$/, ""); print; exit }' "$1"; }
set_bump() {
  awk -v b="$2" '!done && /^bump:/ { print "bump: " b; done = 1; next } 1' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}
add_entry() {
  ENTRY="$entry" awk -v head="### $2" '
    { sub(/\r$/, ""); line[++n] = $0 }
    END {
      h = 0
      for (i = 1; i <= n; i++) if (line[i] == head) { h = i; break }
      if (!h) {
        while (n > 0 && line[n] !~ /[^[:space:]]/) n--
        for (i = 1; i <= n; i++) print line[i]
        print ""; print head; print ""; print ENVIRON["ENTRY"]
        exit
      }
      e = n + 1
      for (i = h + 1; i <= n; i++) if (line[i] ~ /^#+[ \t]/) { e = i; break }
      last = e - 1
      while (last > h && line[last] !~ /[^[:space:]]/) last--
      for (i = 1; i <= last; i++) print line[i]
      print ""; print ENVIRON["ENTRY"]
      if (e <= n) { print ""; for (i = e; i <= n; i++) print line[i] }
    }' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

has_entry() {
  local sec
  sec="$(awk -v head="### $2" '{ sub(/\r$/, "") } $0 == head { on = 1; next } on && /^#+[ \t]/ { on = 0 } on' "$1")"
  [[ $'\n'"$sec"$'\n' == *$'\n'"$entry"$'\n'* ]]
}

[[ ! -e "$(git rev-parse --git-path MERGE_HEAD)" ]] || exit 0

for plugin in "${plugins[@]}"; do
  set_change "$plugin"
  own="$(grep -m1 -E "^\.changes/$plugin/[^/]+\.md$" <<<"$added")"
  [[ -z "$own" || -f "$own" ]] || own=""
  if [[ -z "$own" ]]; then
    path="$(bash "$creator" "$plugin" "$level")" || exit 2
    printf '%s\n' "$block" >>"$path" || exit 2
    echo "$path"
    continue
  fi
  [[ -z "$base" && "$level" != none ]] || continue
  ! has_entry "$own" "$section" || {
    echo "$own"
    continue
  }
  old="$(bump_of "$own")"
  if [[ "$old" == none ]]; then
    printf -- '---\nbump: %s\n---\n\n%s\n' "$level" "$block" >"$own" || exit 2
  else
    (($(rank "$level") > $(rank "$old"))) && { set_bump "$own" "$level" || exit 2; }
    add_entry "$own" "$section" || exit 2
  fi
  echo "$own"
done
