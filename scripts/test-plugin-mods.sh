#!/usr/bin/env bash
# Run `claude plugin test` on every plugin that ships a mod: a hooks/hooks.json
# whose "modules" array is non-empty (ADR 0052 adopts mods). Exits 0 with a
# skip line when no plugin ships a mod, when
# `claude` is not on PATH, or when the CLI predates `claude plugin test` (mods
# need 2.1.287). Exits 1 when any mod's tests fail, and 2 when node, which
# reads hooks.json, is not on PATH.
# Basis: https://code.claude.com/docs/en/plugins/mods/test.md
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

mods=()
for hooks in plugins/*/hooks/hooks.json; do
  [[ -f "$hooks" ]] || continue
  if node -e 'const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).modules;
process.exit(Array.isArray(m) && m.length > 0 ? 0 : 1)' "$hooks" 2>/dev/null; then
    mods+=("${hooks%/hooks/hooks.json}")
  fi
done

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

failed=0
for dir in "${mods[@]}"; do
  echo "=== claude plugin test $dir ==="
  claude plugin test "$dir" || failed=1
done
if [[ $failed -ne 0 ]]; then
  echo "Mod tests failed." >&2
  exit 1
fi
echo "All mod tests passed."
