#!/usr/bin/env bash
# biome-format pre-commit check: rewrite the staged JavaScript, TypeScript and
# JSON files, then report what Biome still finds on the lines this commit adds.
#
#   biome-check.sh               the staged changes (git runs it as pre-commit)
#   biome-check.sh --worktree    the uncommitted changes against HEAD, untracked
#                                files included, reported without rewriting
#                                (the opt-in end-of-turn Stop row)
#
# Pre-commit: a partly staged file is refused before anything is rewritten
# (re-staging a rewrite would stage its unstaged hunks too). Then `biome check
# --write` (safe fixes, formatting, import sorting) runs over the staged .ts,
# .tsx, .js, .jsx, .mjs, .cjs, .mts, .cts, .json and .jsonc files, the rewritten
# paths print on stdout and are re-staged, and the findings that remain print as
# "<path>:<line>: <message>" on stderr, exit 1, only for lines the commit adds.
#
# Only a file a Biome configuration governs is touched: a biome.json or
# biome.jsonc in the file's directory or above it, up to the repository root. The
# topmost one wins, since Biome reads a root config and the nested ones beneath
# it from there. Biome runs from that directory, so its own ignores hold for
# these explicit paths. Files under .githooks/ are installed copies and are
# skipped. Biome comes from node_modules/.bin (the governing config's directory,
# else the repository root), else PATH. Missing biome follows the check-placement
# contract in every mode: checks.skipmissing, else fail for an agent and a notice
# for a person.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1

checks_init pre-commit "$@" || exit 0

# biome_config_dir <repo-relative path>: sets CONFIG_DIR to the topmost directory
# that holds a Biome config on the way up to the repository root ("." for the
# root itself); returns 1 when none does.
CONFIG_DIR=""
biome_config_dir() {
  local dir="${1%/*}"
  [[ "$dir" == "$1" ]] && dir=.
  CONFIG_DIR=""
  while :; do
    if [[ -f "$dir/biome.json" || -f "$dir/biome.jsonc" ]]; then
      CONFIG_DIR="$dir"
    fi
    [[ "$dir" == . ]] && break
    case "$dir" in
    */*) dir="${dir%/*}" ;;
    *) dir=. ;;
    esac
  done
  [[ -n "$CONFIG_DIR" ]]
}

files=()
dirs=()
while IFS= read -r -d '' f; do
  case "$f" in
  .githooks/*) continue ;;
  *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.mts | *.cts | *.json | *.jsonc) ;;
  *) continue ;;
  esac
  [[ -f "$f" && ! -L "$f" ]] || continue
  biome_config_dir "$f" || continue
  files+=("$f")
  dirs+=("$CONFIG_DIR")
done < <(checks_files)
((${#files[@]})) || exit 0

# The local install comes first on PATH so the missing-tool rule sees it.
[[ -x node_modules/.bin/biome ]] && PATH="$PWD/node_modules/.bin:$PATH"
for d in "${dirs[@]}"; do
  [[ -x "$d/node_modules/.bin/biome" ]] && PATH="$PWD/$d/node_modules/.bin:$PATH"
done
checks_require_tool biome "npm i -D @biomejs/biome, or another method at https://biomejs.dev/guides/getting-started/"

# Each distinct config directory is one Biome run, from that directory, over its
# files named relative to it. Sets GROUP_DIR, GROUP_BIN and GROUP (the paths).
done_dirs=$'\n'
group_dirs=()
for d in "${dirs[@]}"; do
  [[ "$done_dirs" != *$'\n'"$d"$'\n'* ]] || continue
  done_dirs+="$d"$'\n'
  group_dirs+=("$d")
done

load_group() { # <config dir>
  local i f
  GROUP_DIR="$1"
  GROUP=()
  for i in "${!files[@]}"; do
    [[ "${dirs[i]}" == "$GROUP_DIR" ]] || continue
    f="${files[i]}"
    if [[ "$GROUP_DIR" == . ]]; then GROUP+=("$f"); else GROUP+=("${f#"$GROUP_DIR"/}"); fi
  done
  GROUP_BIN=biome
  if [[ -x "$GROUP_DIR/node_modules/.bin/biome" ]]; then
    GROUP_BIN="$PWD/$GROUP_DIR/node_modules/.bin/biome"
  elif [[ -x node_modules/.bin/biome ]]; then
    GROUP_BIN="$PWD/node_modules/.bin/biome"
  fi
}

# run_biome <output file> [biome check options...]: BIOME_CONFIG_PATH is unset so
# a stray export cannot swap the discovered config for another one.
run_biome() {
  local out="$1"
  shift
  (cd "$GROUP_DIR" && env -u BIOME_CONFIG_PATH "$GROUP_BIN" check "$@" --no-errors-on-unmatched -- "${GROUP[@]}") >"$out" 2>&1
}

if [[ "$CHECKS_MODE" == pre-commit ]]; then
  # Only the Biome files are refused, not every staged path, which is what
  # checks_refuse_partly_staged would walk.
  refused=0
  for f in "${files[@]}"; do
    if checks_partly_staged "$f"; then
      printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
      refused=1
    fi
  done
  ((refused)) && exit 1

  for d in "${group_dirs[@]}"; do
    load_group "$d"
    run_biome "$CHECKS_TMP/write" --write || :
  done

  rewritten=()
  while IFS= read -r -d '' f; do
    rewritten+=("$f")
  done < <(git diff --name-only -z -- "${files[@]}")
  if ((${#rewritten[@]})); then
    printf '%s\n' "${rewritten[@]}"
    git add -- "${rewritten[@]}"
  fi
fi

checks_changed_lines

# Biome's concise format is "<mark> <path>:<line>:<col>: <rule>: <message>"; the
# contract line drops the mark and the column, puts the path relative to the
# repository root in git's forward-slash spelling, and leaves out the assist
# actions (import sorting), which the rewrite pass applies. A diagnostic with no
# line, such as a would-be format change, has no changed line to match.
to_contract() { # <config dir>
  awk -v prefix="$1" '
    /^[^ ]+ [^:]+:[0-9]+:[0-9]+: / {
      sub(/^[^ ]+ /, "")
      match($0, /:[0-9]+:[0-9]+: /)
      path = substr($0, 1, RSTART - 1)
      rest = substr($0, RSTART + 1)
      split(rest, p, ":")
      msg = substr(rest, length(p[1]) + length(p[2]) + 4)
      if (msg ~ /^assist\//) next
      gsub(/\\/, "/", path)
      if (prefix != ".") path = prefix "/" path
      print path ":" p[1] ": " msg
    }'
}

# A diagnostic line, whatever its position; its absence from a failing run means
# Biome broke (a config it could not read) rather than judged the files.
has_diagnostic() {
  grep -qE '^[^[:space:]]+ [^:]+(:[0-9]+:[0-9]+)?: ([a-z]+/)*[A-Za-z]+: ' "$1"
}

: >"$CHECKS_TMP/contract"
for d in "${group_dirs[@]}"; do
  load_group "$d"
  out="$CHECKS_TMP/report"
  run_biome "$out" --error-on-warnings --reporter=concise
  rc=$?
  if ((rc != 0)) && ! has_diagnostic "$out"; then
    printf 'biome-format: biome failed:\n' >&2
    cat "$out" >&2
    exit 1
  fi
  to_contract "$GROUP_DIR" <"$out" >>"$CHECKS_TMP/contract"
done

checks_filter_findings <"$CHECKS_TMP/contract" >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
printf 'biome-format: fix the findings above, or adjust the repository Biome config.\n' >&2
exit 1
