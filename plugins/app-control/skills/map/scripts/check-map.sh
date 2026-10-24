#!/usr/bin/env bash
# Structural check of one control skill against plugins/app-control/reference/control-skill.md.
# Prints one finding per line as `<rule> | <path> | <detail>`, paths relative to the control
# skill directory. Never edits. Exits 0 with or without findings; 2 on a usage error.
#
# Rules:
#   index-dead         an index line names a feature file that does not exist
#   index-duplicate    two index lines name the same feature file
#   index-missing      a feature file on disk has no index line
#   index-entry-count  an index line's `entry points: <n>` differs from the file's entry lines
#   index-glob         an index source glob matches no file under the repository root
#   section-missing    a feature README lacks one of the six sections
#   section-extra      a feature README has an H2 section outside the six
#   section-order      a feature README's sections are out of the contract's order
#   entry-marker       an entry point line ends with neither `driven` nor `not driven: <reason>`
#   entry-reason       an entry point line ends `not driven` with no reason
#   link               a relative Markdown link in any .md file resolves to nothing
#   shared-use         a `shared/<item>` is named by fewer than two feature files
#   shared-why         a `shared/<item>` README has no `Why shared: <reason>` line
#
# A legacy `features/<f>.md` gets the index and link rules only: the contract keeps it working as
# written. What a shared item is, what counts as a use and where its why line goes: the contract's
# "Shared items" section.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check-map.sh <control-skill-dir> [--root <repository-root>]

Checks a control skill's structure and prints `<rule> | <path> | <detail>` per finding.
--root   where index source globs resolve (default: the git top level, else <dir>/../../..)
EOF
}

dir="" root=""
while (($#)); do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    [[ $# -ge 2 ]] || {
      echo "check-map.sh: --root needs a value" >&2
      exit 2
    }
    root="$2"
    shift 2
    ;;
  -*)
    echo "check-map.sh: unknown argument: $1" >&2
    exit 2
    ;;
  *)
    [[ -z "$dir" ]] || {
      echo "check-map.sh: one control skill directory only" >&2
      exit 2
    }
    dir="$1"
    shift
    ;;
  esac
done

[[ -n "$dir" ]] || {
  usage >&2
  exit 2
}
[[ -d "$dir" ]] || {
  echo "check-map.sh: not a directory: $dir" >&2
  exit 2
}
[[ -f "$dir/SKILL.md" ]] || {
  echo "check-map.sh: no SKILL.md in $dir" >&2
  exit 2
}
dir="$(cd "$dir" && pwd)"
if [[ -z "$root" ]] && ! root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"; then
  root="$(cd "$dir/../../.." && pwd)"
fi
[[ -d "$root" ]] || {
  echo "check-map.sh: not a directory: $root" >&2
  exit 2
}

SECTIONS=("Parts" "Sub-features" "Entry points" "Reset" "Drive" "Gotchas")

finding() { printf '%s | %s | %s\n' "$1" "$2" "$3"; }
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}
# Lines of a Markdown file outside fenced code blocks.
unfenced() { awk '/^[[:space:]]*(```|~~~)/ { fence = !fence; next } !fence' "$1"; }
# H2 headings of a file, in order.
h2s() { unfenced "$1" | sed -n 's/^## \(.*[^[:space:]]\)[[:space:]]*$/\1/p'; }
# Non-blank lines under `## Entry points`.
entry_lines() {
  unfenced "$1" | awk '/^## / { inside = ($0 ~ /^## Entry points[[:space:]]*$/); next } inside && NF'
}

declare -A features=() indexed=()
while IFS= read -r f; do features["$f"]=readme; done < <(cd "$dir" && find features -mindepth 2 -type f -name README.md 2>/dev/null | LC_ALL=C sort)
while IFS= read -r f; do features["$f"]=legacy; done < <(cd "$dir" && find features -mindepth 1 -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)

# Index lines, in hub order.
while IFS= read -r line; do
  IFS='|' read -r -a fields <<<"$line"
  path="$(trim "${fields[1]:-}")"
  if [[ -n "${indexed[$path]:-}" ]]; then
    finding index-duplicate SKILL.md "$path is indexed more than once"
    continue
  fi
  indexed["$path"]=1
  if [[ ! -f "$dir/$path" ]]; then
    finding index-dead SKILL.md "$path does not exist"
  elif [[ "${features[$path]:-}" == readme ]]; then
    count="$(trim "${fields[2]:-}")"
    count="${count#entry points:}"
    count="$(trim "$count")"
    actual="$(entry_lines "$dir/$path" | wc -l | tr -d ' ')"
    [[ "$count" == "$actual" ]] || finding index-entry-count SKILL.md "$path: index says $count, the file has $actual"
  fi
  sources="$(trim "${fields[3]:-}")"
  sources="${sources#sources:}"
  IFS=',' read -r -a globs <<<"$sources"
  for glob in "${globs[@]}"; do
    glob="$(trim "$glob")"
    [[ -n "$glob" ]] || continue
    hits="$(
      cd "$root"
      shopt -s globstar nullglob
      IFS=''
      # shellcheck disable=SC2206 # the glob is meant to expand; IFS='' stops word splitting
      matches=($glob)
      # A pattern with no glob characters comes back as itself, so count only what exists.
      n=0
      for m in "${matches[@]}"; do [[ -e "$m" ]] && n=$((n + 1)); done
      printf '%s' "$n"
    )"
    [[ "$hits" != 0 ]] || finding index-glob SKILL.md "$path: $glob matches no file"
  done
done < <(unfenced "$dir/SKILL.md" | { grep -E '^- .*\|[[:space:]]*features/' || true; })

mapfile -t feature_list < <(printf '%s\n' "${!features[@]}" | LC_ALL=C sort)
for f in "${feature_list[@]}"; do
  [[ -n "$f" ]] || continue
  [[ -n "${indexed[$f]:-}" ]] || finding index-missing "$f" "no index line names this feature file"
  [[ "${features[$f]}" == readme ]] || continue

  mapfile -t have < <(h2s "$dir/$f")
  declare -A seen=()
  present=()
  for h in "${have[@]}"; do
    seen["$h"]=1
    is_known=0
    for s in "${SECTIONS[@]}"; do [[ "$h" == "$s" ]] && is_known=1; done
    if ((is_known)); then present+=("$h"); else finding section-extra "$f" "## $h"; fi
  done
  want=()
  for s in "${SECTIONS[@]}"; do
    if [[ -n "${seen[$s]:-}" ]]; then want+=("$s"); else finding section-missing "$f" "## $s"; fi
  done
  [[ "${present[*]}" == "${want[*]}" ]] || finding section-order "$f" "$(
    IFS=,
    printf '%s' "${present[*]}"
  )"
  unset seen

  while IFS= read -r entry; do
    e="$(trim "$entry")"
    if [[ "$e" =~ not\ driven:[[:space:]]*[^[:space:]] ]]; then
      :
    elif [[ "$e" =~ not\ driven:?$ ]]; then
      finding entry-reason "$f" "$e"
    elif [[ "$e" =~ (^|[^[:alnum:]_-])driven$ ]]; then
      :
    else
      finding entry-marker "$f" "$e"
    fi
  done < <(entry_lines "$dir/$f")
done

# Relative links in every Markdown file of the control skill.
# shellcheck disable=SC2016 # the backticks are the Markdown code-span delimiter, not a substitution
link_targets() { unfenced "$1" | sed 's/`[^`]*`//g' | { grep -oE '\]\([^)]+\)' || true; } | sed 's/^](//; s/)$//'; }
while IFS= read -r md; do
  base="$(dirname "$dir/$md")"
  while IFS= read -r target; do
    target="${target%% *}"
    target="${target#<}"
    target="${target%>}"
    target="${target%%#*}"
    [[ -n "$target" ]] || continue
    [[ "$target" =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]] && continue
    [[ -e "$base/$target" ]] || finding link "$md" "$target does not resolve"
  done < <(link_targets "$dir/$md")
done < <(cd "$dir" && find . -type f -name '*.md' | sed 's|^\./||' | LC_ALL=C sort)

# shared/ items.
if [[ -d "$dir/shared" ]]; then
  while IFS= read -r item; do
    name="${item#shared/}"
    # shellcheck disable=SC2016 # $ is a regex character to escape, not an expansion
    escaped="$(printf '%s' "$name" | sed 's/[][\.*^$()+?{}|]/\\&/g')"
    users=0
    for f in "${feature_list[@]}"; do
      [[ -n "$f" ]] || continue
      if grep -qE "shared/$escaped([^A-Za-z0-9._-]|\$)" "$dir/$f"; then users=$((users + 1)); fi
    done
    ((users >= 2)) || finding shared-use "$item" "named by $users feature file(s); shared/ holds only what two or more use"
    readme="$dir/$item"
    [[ -d "$readme" ]] && readme="$readme/README.md"
    if [[ ! -f "$readme" ]]; then
      finding shared-why "$item" "no README.md"
    elif ! grep -qiE '^[[:space:]]*why shared:[[:space:]]*[^[:space:]]' "$readme"; then
      finding shared-why "$item" "no 'Why shared: <reason>' line"
    fi
  done < <(cd "$dir" && find shared -mindepth 1 -maxdepth 1 | LC_ALL=C sort)
fi

exit 0
