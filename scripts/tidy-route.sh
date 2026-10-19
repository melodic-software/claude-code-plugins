#!/usr/bin/env bash
# Routes a lane run's in-run tidy passes over the diff in the work tree it runs
# in: the tracked changes against HEAD plus the untracked files.
#
#   scripts/tidy-route.sh --max-changed-lines <n> --passes <file>
#
# <file> holds one pass per line, `<code|markdown><TAB><skill><TAB><args>`, in
# the order they run. Prints `route: run` and then one `run: /<skill> <args>
# <files>` line per pass that has files, or `route: skip <reason>` when the
# diff is empty, touches more than one area, or is over <n> added plus deleted
# lines. An area is `plugins/<name>` for a plugin's files and the first path
# segment otherwise; `.changes/` counts toward the size but is no area. A pass
# runs only on files with a name safe as a prompt word, never on an instruction
# surface (CLAUDE.md, CLAUDE.local.md, AGENTS.md, SKILL.md, or anything under a
# .claude, .claude-plugin, skills, agents, commands, hooks, output-styles or
# prompts directory) and never under .github/ or .changes/. An untracked file's
# every line is new, so its run line drops an `--added-since <base>` pair.
#
# Exit: 0 routed, 2 usage or a git failure.
set -uo pipefail
self="$(basename "$0")"

usage() {
  echo "usage: $self --max-changed-lines <n> --passes <file>" >&2
  exit 2
}

max="" passes=""
while (($#)); do
  case "$1" in
    --max-changed-lines) (($# >= 2)) || usage; max="$2"; shift 2 ;;
    --passes) (($# >= 2)) || usage; passes="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ $max =~ ^[1-9][0-9]*$ && -f $passes ]] || usage

top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "$self: not inside a git work tree" >&2; exit 2; }
cd "$top" || exit 2

declare -A untracked=()
paths=()
total=0
while IFS= read -r -d '' record; do
  IFS=$'\t' read -r added deleted path <<<"$record"
  [[ $added =~ ^[0-9]+$ ]] || added=0
  [[ $deleted =~ ^[0-9]+$ ]] || deleted=0
  total=$((total + added + deleted))
  paths+=("$path")
done < <(git diff --no-ext-diff --no-textconv --no-renames --numstat -z HEAD)
wait "$!" || { echo "$self: git diff failed" >&2; exit 2; }
while IFS= read -r -d '' path; do
  [[ -L $path ]] || total=$((total + $(wc -l <"$path")))
  untracked[$path]=1
  paths+=("$path")
done < <(git ls-files -z --others --exclude-standard)
wait "$!" || { echo "$self: git ls-files failed" >&2; exit 2; }

area() {
  case "$1" in
    .changes/*) ;;
    plugins/*/*) local rest="${1#plugins/}" && echo "plugins/${rest%%/*}" ;;
    */*) echo "${1%%/*}" ;;
    *) echo . ;;
  esac
}

eligible() {
  local path="$1" lower="${1,,}"
  [[ $path =~ ^[A-Za-z0-9_+.][A-Za-z0-9_@+.-]*(/[A-Za-z0-9_@+.][A-Za-z0-9_@+.-]*)*$ && /$path/ != */./* && /$path/ != */../* ]] || return 1
  case "$path" in
    .github/* | .changes/*) return 1 ;;
    *) ;;
  esac
  case "${lower##*/}" in
    claude.md | claude.local.md | agents.md | skill.md) return 1 ;;
    *) ;;
  esac
  case "/$lower" in
    */.claude/* | */.claude-plugin/* | */skills/* | */agents/* | */commands/* | */hooks/* | */output-styles/* | */prompts/*) return 1 ;;
    *) ;;
  esac
}

kind() {
  case "${1,,}" in
    *.md) echo markdown ;;
    *.sh | *.bash | *.mjs | *.cjs | *.js | *.jsx | *.ts | *.tsx | *.py | *.ps1 | *.psm1 | *.go | *.cs | *.rb | *.rs | *.java | *.kt) echo code ;;
    *) ;;
  esac
}

declare -A areas=()
code=() markdown=() docs_only=true
for path in "${paths[@]}"; do
  a="$(area "$path")"
  [[ -z $a ]] || areas[$a]=1
  k="$(kind "$path")"
  [[ $k == markdown || -z $a ]] || docs_only=false
  if [[ -z $k || ! -e $path ]] || ! eligible "$path"; then continue; fi
  if [[ $k == code ]]; then code+=("$path"); else markdown+=("$path"); fi
done

if ((${#paths[@]} == 0)); then
  echo "route: skip empty"
  exit 0
fi
if ((${#areas[@]} > 1)); then
  mapfile -t names < <(printf '%s\n' "${!areas[@]}" | sort)
  echo "route: skip areas ${#areas[@]}: ${names[*]}"
  exit 0
fi
if ((total > max)); then
  echo "route: skip lines $total over $max"
  exit 0
fi

lines=()
while IFS=$'\t' read -r files skill args; do
  case "$files" in
    code) targets=("${code[@]}") ;;
    markdown) targets=("${markdown[@]}") ;;
    *) echo "$self: a pass names no file kind" >&2 && exit 2 ;;
  esac
  tracked=() new=()
  for path in "${targets[@]}"; do
    if [[ -n ${untracked[$path]:-} ]]; then new+=("$path"); else tracked+=("$path"); fi
  done
  ((${#tracked[@]})) && lines+=("run: /$skill${args:+ $args} ${tracked[*]}")
  if ((${#new[@]})); then
    read -ra words <<<"$args"
    kept=()
    for ((i = 0; i < ${#words[@]}; i++)); do
      if [[ ${words[i]} == --added-since ]]; then i=$((i + 1)); else kept+=("${words[i]}"); fi
    done
    lines+=("run: /$skill${kept[*]:+ ${kept[*]}} ${new[*]}")
  fi
done <"$passes"

if ((${#lines[@]} == 0)); then
  echo "route: skip no-targets"
  exit 0
fi
scope=code
[[ $docs_only == false ]] || scope=docs-only
area_name="${!areas[*]}"
echo "route: run"
echo "scope: $scope, files ${#paths[@]}, lines $total, area ${area_name:-none}"
printf '%s\n' "${lines[@]}"
