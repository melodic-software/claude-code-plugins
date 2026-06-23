#!/usr/bin/env bash
# PostToolUse hook: auto-format and lint Markdown via markdownlint-cli2.
# Triggered on Write|Edit of *.md and *.mdc (Cursor MDC = markdown + frontmatter).
#
# ADVISORY: always exits 0. markdownlint-cli2 --fix auto-format always applies;
# unfixable markdownlint violations surface via additionalContext but never
# block the edit. Uses the consuming repo's own markdownlint config — ships none.

set -uo pipefail

# Read inherited fd0 directly (bare jq) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT → silent no-op). hook::read_file_path reads bare fd0.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "MARKDOWN_FORMAT"

FILE=$(hook::read_file_path) || exit 0
case "$FILE" in
  *.md | *.mdc) ;;
  *) exit 0 ;;
esac

MDLINT=()
if command -v markdownlint-cli2 >/dev/null 2>&1; then
  MDLINT=(markdownlint-cli2)
elif command -v npx >/dev/null 2>&1; then
  MDLINT=(npx markdownlint-cli2)
else
  exit 0
fi

# Run markdownlint-cli2 from the linted file's repo root. Its config
# auto-discovery is CWD-anchored, and the hook's CWD is not guaranteed to be
# the file's repo root, so a drifted CWD would silently lose the repo's
# markdownlint config cascade and fall back to tool defaults. Running from the
# repo root applies the consumer's own rules. repo_root is file-anchored.
REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"

if FIX_OUTPUT=$(cd "$REPO_ROOT" && "${MDLINT[@]}" --fix "$FILE" 2>&1); then
  exit 0
fi

hook::ctx_reset
hook::ctx_append "markdown-format: $(basename "$FILE") has markdownlint findings:"
while IFS= read -r line; do
  hook::ctx_append "  $line"
done <<<"$FIX_OUTPUT"
hook::ctx_flush PostToolUse
exit 0
