#!/usr/bin/env bash
# Run `claude plugin test` on every plugin that ships a mod: a hooks/hooks.json
# whose "modules" array is non-empty (ADR 0052 adopts mods). Exits 0 with a
# skip line when no plugin ships a mod, when
# `claude` is not on PATH, or when the CLI predates `claude plugin test` (mods
# need 2.1.287). Exits 1 when any mod's tests fail, a plugin ships a
# hooks/register.* file that its hooks.json names no modules for, or a mod
# plugin's plugin.json declares no engines["claude-code"] range or one other
# than ">=" the claude version floor in its prerequisites.json, and 2 when
# node, which reads hooks.json, is not on PATH.
# Basis: https://code.claude.com/docs/en/plugins/mods/test#write-a-test (as of
# 2026-10-30: `claude plugin test` runs the *.test.ts files and exits 1 when a test
# fails). Recheck when that section changes the command, the file pattern or the
# exit status.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not on PATH; cannot read hooks.json to find mods" >&2
  exit 2
fi

MIN_VERSION=2.1.287

# version_at_least <have> <want>: dotted numeric comparison, no sort -V.
version_at_least() {
  local -a have want
  IFS=. read -ra have <<<"$1"
  IFS=. read -ra want <<<"$2"
  local i
  for i in 0 1 2; do
    ((10#${have[i]:-0} > 10#${want[i]:-0})) && return 0
    ((10#${have[i]:-0} < 10#${want[i]:-0})) && return 1
  done
  return 0
}

engines_error() {
  node -e '
const fs = require("fs");
const read = (file) => {
  try {
    return JSON.parse(fs.readFileSync(process.argv[1] + "/" + file, "utf8"));
  } catch {
    return null;
  }
};
const range = read(".claude-plugin/plugin.json")?.engines?.["claude-code"];
if (typeof range !== "string" || !range.trim()) {
  console.log("declares no engines[\"claude-code\"] range in .claude-plugin/plugin.json");
  process.exit(0);
}
const floor = read("prerequisites.json")?.requires?.find(
  (entry) => Array.isArray(entry?.detect?.any) && entry.detect.any.includes("claude") && entry.detect.version?.min,
)?.detect.version.min;
if (floor && range !== ">=" + floor) {
  console.log("declares engines[\"claude-code\"] \"" + range + "\", not \">=" + floor + "\" from the claude version floor in prerequisites.json");
}' "$1"
}

mods=()
invalid=0
declare -A has_mod=()
hooks_files=()
for dir in plugins/*/hooks; do
  [[ -f "$dir/hooks.json" ]] && hooks_files+=("$dir/hooks.json")
done
if ((${#hooks_files[@]} > 0)); then
  while IFS= read -r mdir; do
    mdir="${mdir%$'\r'}"
    [[ -n "$mdir" ]] && has_mod["$mdir"]=1
  done < <(node -e '
    const fs = require("fs");
    for (const f of process.argv.slice(1)) {
      try {
        const m = JSON.parse(fs.readFileSync(f, "utf8")).modules;
        if (Array.isArray(m) && m.length > 0) console.log(f.slice(0, -"/hooks.json".length));
      } catch {}
    }
  ' "${hooks_files[@]}")
fi
for dir in plugins/*/hooks; do
  if [[ -n "${has_mod[$dir]:-}" ]]; then
    mods+=("${dir%/hooks}")
    why="$(engines_error "${dir%/hooks}")"
    if [[ -n "$why" ]]; then
      echo "error: ${dir%/hooks} ships a mod but $why" >&2
      invalid=1
    fi
    continue
  fi
  for register in "$dir"/register.*; do
    [[ -f "$register" ]] || continue
    echo "error: ${dir%/hooks} ships hooks/${register##*/} but hooks/hooks.json names no modules, so Claude Code never loads it" >&2
    invalid=1
  done
done
((invalid == 0)) || exit 1

if [[ ${#mods[@]} -eq 0 ]]; then
  echo "claude plugin test: skipped, no plugin ships a mod"
  exit 0
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "claude plugin test: skipped, claude CLI not on PATH (${#mods[@]} mod(s) untested)"
  exit 0
fi
version="$(claude --version 2>/dev/null)"
version="${version%% *}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || ! version_at_least "$version" "$MIN_VERSION"; then
  echo "claude plugin test: skipped, claude ${version:-unknown} predates $MIN_VERSION (${#mods[@]} mod(s) untested)"
  exit 0
fi

jobs="${MOD_TEST_JOBS:-2}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || jobs=2

buf="$(mktemp -d)" || exit 2
trap 'rm -rf "$buf"' EXIT
pids=()
failed=()
collect() {
  local i=$1 rc=0 tests="" line msg
  echo "=== claude plugin test ${mods[i]} ==="
  wait "${pids[i]}" || rc=$?
  cat "$buf/$i.out"
  ((rc == 0)) && return
  failed+=("${mods[i]}")
  while IFS= read -r line; do
    [[ $line =~ ^\(fail\)\ (.+)$ ]] || continue
    line="${BASH_REMATCH[1]}"
    [[ $line =~ ^(.+)\ \[[0-9.]+m?s\]$ ]] && line="${BASH_REMATCH[1]}"
    tests+="${tests:+; }$line"
  done <"$buf/$i.out"
  msg="${mods[i]}: ${tests:-exit $rc with no (fail) line; see the log above}"
  msg="${msg//'%'/%25}"
  echo "::error title=Mod tests failed::$msg"
}
next=0
for i in "${!mods[@]}"; do
  while ((i - next >= jobs)); do
    collect $((next++))
  done
  claude plugin test "${mods[i]}" >"$buf/$i.out" 2>&1 &
  pids[i]=$!
done
while ((next < ${#mods[@]})); do
  collect $((next++))
done
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "Mod tests failed." >&2
  echo "Failing mod plugins: ${failed[*]}" >&2
  exit 1
fi
echo "All mod tests passed."
