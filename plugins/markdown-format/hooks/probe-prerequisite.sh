#!/usr/bin/env bash
# SessionStart probe for markdownlint-cli2. Runs in the main session, before
# any Markdown edit, so a missing formatter is not visible only to a subagent
# that happened to edit a file. Never installs.
set -uo pipefail

have_markdownlint() {
  command -v markdownlint-cli2 >/dev/null 2>&1 && return 0
  local dir="$PWD"
  local i
  for ((i = 0; i < 8; i++)); do
    [[ -x "$dir/node_modules/.bin/markdownlint-cli2" ]] && return 0
    [[ "$dir" == "/" ]] && break
    dir="$(dirname "$dir")"
  done
  return 1
}

if have_markdownlint; then
  exit 0
fi

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=hook-utils.sh
source "$SCRIPT_DIR/hook-utils.sh"

INPUT="$(cat || true)"

if hook::notice_once "markdown-format-markdownlint" "$INPUT" prerequisite; then
  hook::emit_skip_notice SessionStart \
    "markdown-format: markdownlint-cli2 was not found on PATH or as node_modules/.bin/markdownlint-cli2. Markdown lint will skip until it is installed. Run /markdown-format:check. It does not install. A repo-local install (npm i -D markdownlint-cli2) is the reliable route."
fi
exit 0
