#!/usr/bin/env bash
# SessionStart probe for goimports. Does not wait for a .go edit. Never installs.
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=hook-utils.sh
source "$SCRIPT_DIR/hook-utils.sh"

INPUT="$(cat || true)"

if command -v goimports >/dev/null 2>&1; then
  exit 0
fi
if hook::notice_once "go-format-goimports" "$INPUT" prerequisite; then
  hook::emit_skip_notice SessionStart \
    "go-format: no goimports binary was found on PATH. Go format will skip until it is installed. Run /go-format:check. It does not install. Install: go install golang.org/x/tools/cmd/goimports@latest"
fi
exit 0
