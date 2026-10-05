#!/usr/bin/env bash
# write-changelog-fragments.sh — write the changelog fragment for each plugin a
# change touches, in a repository that releases plugins from fragments: it has
# scripts/fragment-plugins.txt and scripts/new-changelog-fragment.sh. Anywhere
# else, and for a plugin the list does not name, it writes nothing, and the
# per-pull-request version bump plus CHANGELOG entry still applies.
#
#   write-changelog-fragments.sh [--base <ref>] [--level major|minor|patch|none] < message
#
# The message on stdin is a commit message (subject, blank line, body) or a pull
# request title. Touched plugins are the plugins/<name>/ paths in the index
# (git diff --cached), or with --base the paths changed on the branch
# (git diff <ref>...HEAD).
#
# Bump level, from the Conventional Commits subject unless --level names one:
#   `!` before the colon, or a BREAKING CHANGE footer   major
#   feat                                                minor
#   fix, perf                                           patch
#   build, chore, ci, docs, refactor, style, test       none
# When a listed plugin is touched, any other subject is refused (exit 2) until
# --level names the level.
#
# Body: the subject description as one list item under `### Added` (feat),
# `### Fixed` (fix) or `### Changed` (everything else), with the message body
# indented beneath it and the trailer paragraph dropped except a BREAKING CHANGE
# footer, kept as a **Breaking:** line. A `none` fragment gets one line saying
# why no release is needed.
#
# One fragment per plugin per branch. The branch's own fragment is one this
# branch added: since the merge base with --base or the default branch, or
# staged or untracked. Without --base, a later releasing commit appends its
# entry to that fragment (once; a rerun finds it there) and raises its bump to
# the higher level; with --base, a plugin that already has a branch fragment is
# left alone, so a pull request only fills the gaps its commits left.
#
# Prints each fragment path it wrote, one per line; stage them with the commit.
# Exit: 0 done (including nothing to do); 2 usage, a refused subject, or a
# failure.
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
  [[ "$path" == plugins/*/* ]] || continue
  name="${path#plugins/}" name="${name%%/*}"
  [[ -n "${listed[$name]:-}" && -z "${seen[$name]:-}" && -f "plugins/$name/.claude-plugin/plugin.json" ]] || continue
  seen["$name"]=1
  plugins+=("$name")
done <<<"$paths"
((${#plugins[@]})) || exit 0

subject="$(sed -n '/[^[:space:]]/{p;q;}' <<<"$message")"
type="" desc="$subject"
cc='^([a-z]+)(\([^)]*\))?(!)?:[[:space:]]+(.+)$'
if [[ "$subject" =~ $cc ]]; then
  type="${BASH_REMATCH[1]}" desc="${BASH_REMATCH[4]}"
  breaking="${BASH_REMATCH[3]}"
  grep -Eq '^BREAKING[ -]CHANGE:' <<<"$message" && breaking="!"
  if [[ -z "$level" ]]; then
    if [[ -n "$breaking" ]]; then
      level=major
    else
      case "$type" in
      feat) level="minor" ;;
      fix | perf) level="patch" ;;
      build | chore | ci | docs | refactor | style | test) level="none" ;;
      *) ;;
      esac
    fi
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

# The message body after the subject, minus a final paragraph of trailers,
# indented two spaces so it continues the list item and no line of it can read
# as a heading. A BREAKING CHANGE footer is kept, as a **Breaking:** line.
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

if [[ "$level" == none ]]; then
  block="No release needed (${type:-no type}): $desc"
else
  block="### $section"$'\n\n'"- $desc"
  [[ -z "$body" ]] || block+=$'\n\n'"$body"
fi

# Fragments this branch added: committed since the merge base with --base, or
# with the default branch, plus staged and untracked ones. A fragment main
# already holds belongs to another change, even when its name carries the same
# branch slug.
ref="$base"
if [[ -z "$ref" ]]; then
  ref="$(git symbolic-ref -q --short refs/remotes/origin/HEAD)" || ref=""
  for candidate in origin/main main; do
    [[ -z "$ref" ]] || break
    ! git rev-parse -q --verify "$candidate" >/dev/null || ref="$candidate"
  done
fi
added="$(
  [[ -z "$ref" ]] || git diff --name-only --diff-filter=A "$ref...HEAD" -- .changes/
  git diff --cached --name-only --diff-filter=A -- .changes/
  git ls-files --others --exclude-standard -- .changes/
)"

rank() { case "$1" in major) echo 3 ;; minor) echo 2 ;; patch) echo 1 ;; *) echo 0 ;; esac }
bump_of() { awk '{ sub(/\r$/, "") } NR > 1 && $0 == "---" { exit } sub(/^bump:[ \t]*/, "") { sub(/[ \t]+$/, ""); print; exit }' "$1"; }
# Rewrite the bump line in place; no `sed -i`, whose syntax differs between GNU
# and BSD.
set_bump() {
  awk -v b="$2" '!done && /^bump:/ { print "bump: " b; done = 1; next } 1' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

for plugin in "${plugins[@]}"; do
  own="$(grep -m1 -E "^\.changes/$plugin/[^/]+\.md$" <<<"$added")"
  [[ -z "$own" || -f "$own" ]] || own=""
  if [[ -z "$own" ]]; then
    path="$(bash "$creator" "$plugin" "$level")" || exit 2
    printf '%s\n' "$block" >>"$path" || exit 2
    echo "$path"
    continue
  fi
  [[ -z "$base" && "$level" != none ]] || continue
  # A rerun after a failed or amended commit finds its entry already there.
  [[ "$(<"$own")" != *"$block"* ]] || {
    echo "$own"
    continue
  }
  old="$(bump_of "$own")"
  if [[ "$old" == none ]]; then
    printf -- '---\nbump: %s\n---\n\n%s\n' "$level" "$block" >"$own" || exit 2
  else
    (($(rank "$level") > $(rank "$old"))) && { set_bump "$own" "$level" || exit 2; }
    printf '\n%s\n' "$block" >>"$own" || exit 2
  fi
  echo "$own"
done
