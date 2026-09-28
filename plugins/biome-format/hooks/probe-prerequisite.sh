#!/usr/bin/env bash
# SessionStart probe for the biome binary. Does not wait for a biome.json or
# for a JavaScript edit: a missing binary used to stay silent until both
# gates had passed. Never installs.
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=hook-utils.sh
source "$SCRIPT_DIR/hook-utils.sh"

INPUT="$(cat || true)"

have_biome() {
  command -v biome >/dev/null 2>&1 && return 0
  local dir="$PWD"
  local i
  for ((i = 0; i < 8; i++)); do
    [[ -x "$dir/node_modules/.bin/biome" ]] && return 0
    [[ "$dir" == "/" ]] && break
    dir="$(dirname "$dir")"
  done
  return 1
}

if have_biome; then
  exit 0
fi
if hook::notice_once "biome-format-biome" "$INPUT" prerequisite; then
  hook::emit_skip_notice SessionStart \
    "biome-format: no biome binary was found on PATH or as node_modules/.bin/biome. Format and lint will skip until it is installed. Run /biome-format:check. It does not install. A repo-local install (npm i -D @biomejs/biome) is the reliable route."
fi
exit 0
