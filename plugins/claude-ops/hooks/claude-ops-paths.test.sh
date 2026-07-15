#!/usr/bin/env bash
# Contract tests for project-relative userConfig path containment.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=claude-ops-paths.sh
source "$HOOK_DIR/claude-ops-paths.sh"
# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"

PROJECT="$TEST_TMPDIR/project"
mkdir -p "$PROJECT"

assert_eq "valid nested path resolves under project" "$PROJECT/telemetry/skills" \
  "$(claude_ops::resolve_project_relative_dir "$PROJECT" 'telemetry/skills')"

for case_name in posix_absolute windows_drive windows_drive_relative unc traversal backslash_traversal; do
  case "$case_name" in
  posix_absolute) value="/tmp/skills" ;;
  windows_drive) value='C:\\temp\\skills' ;;
  windows_drive_relative) value='C:skills' ;;
  unc) value='\\\\server\\share\\skills' ;;
  traversal) value='../outside' ;;
  backslash_traversal) value='..\\outside' ;;
  *) bad "unknown path test case: $case_name"; continue ;;
  esac
  if claude_ops::resolve_project_relative_dir "$PROJECT" "$value" >/dev/null; then
    bad "$case_name path rejected"
  else
    ok "$case_name path rejected"
  fi
done

OUTSIDE="$TEST_TMPDIR/outside"
mkdir -p "$OUTSIDE"
if ln -s "$OUTSIDE" "$PROJECT/escape" 2>/dev/null && [[ -L "$PROJECT/escape" ]]; then
  if claude_ops::resolve_project_relative_dir "$PROJECT" 'escape/skills' >/dev/null; then
    bad "escaping symlink ancestor rejected"
  else
    ok "escaping symlink ancestor rejected"
  fi
fi

report
