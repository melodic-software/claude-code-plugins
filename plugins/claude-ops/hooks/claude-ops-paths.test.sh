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
  *)
    bad "unknown path test case: $case_name"
    continue
    ;;
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

# --- Scope-selected skill-usage destination ---------------------------------
FAKE_HOME="$TEST_TMPDIR/home"
mkdir -p "$FAKE_HOME"
assert_eq "repo scope resolves under project" "$PROJECT/.claude/observability" \
  "$(claude_ops::resolve_skill_usage_dir repo "$PROJECT" '.claude/observability')"
assert_eq "user scope resolves under HOME" "$FAKE_HOME/.claude/observability" \
  "$(HOME="$FAKE_HOME" claude_ops::resolve_skill_usage_dir user "$PROJECT" '.claude/observability')"
if HOME="$FAKE_HOME" claude_ops::resolve_skill_usage_dir user "$PROJECT" '../outside' >/dev/null; then
  bad "user scope traversal rejected"
else
  ok "user scope traversal rejected"
fi

DATA_DIR="$TEST_TMPDIR/plugin-data"
mkdir -p "$DATA_DIR"
slug=$(claude_ops::repo_slug "$PROJECT")
case "$slug" in
*[!A-Za-z0-9._-]*) bad "repo_slug emits only safe bytes" ;;
'') bad "repo_slug non-empty" ;;
*) ok "repo_slug emits only safe bytes" ;;
esac
mkdir -p "$TEST_TMPDIR/a-b" "$TEST_TMPDIR/a/b"
if [[ "$(claude_ops::repo_slug "$TEST_TMPDIR/a-b")" != "$(claude_ops::repo_slug "$TEST_TMPDIR/a/b")" ]]; then
  ok "repo_slug distinguishes fold-colliding paths"
else
  bad "repo_slug distinguishes fold-colliding paths"
fi
assert_eq "repo_slug is stable across calls" "$slug" "$(claude_ops::repo_slug "$PROJECT")"

assert_eq "normalize_rel_segments drops ./ and //" ".claude/observability" \
  "$(claude_ops::normalize_rel_segments './.claude//observability/')"
assert_eq "normalize_rel_segments folds backslashes" "telemetry/skills" \
  "$(claude_ops::normalize_rel_segments 'telemetry\skills')"

assert_eq "gitignore_escape escapes glob metachars" 'telemetry\*/a\?b/\[x]' \
  "$(claude_ops::gitignore_escape 'telemetry*/a?b/[x]')"
assert_eq "gitignore_escape leaves ordinary paths intact" '.claude/observability' \
  "$(claude_ops::gitignore_escape '.claude/observability')"
assert_eq "data-dir scope keys by repo slug" "$DATA_DIR/skill-usage/$slug" \
  "$(CLAUDE_PLUGIN_DATA="$DATA_DIR" claude_ops::resolve_skill_usage_dir data-dir "$PROJECT" '.claude/observability')"
if CLAUDE_PLUGIN_DATA="" claude_ops::resolve_skill_usage_dir data-dir "$PROJECT" '.claude/observability' >/dev/null; then
  bad "data-dir scope without CLAUDE_PLUGIN_DATA fails"
else
  ok "data-dir scope without CLAUDE_PLUGIN_DATA fails"
fi

# --- Machine-local git exclude hygiene --------------------------------------
REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"
if git -C "$REPO" init -q 2>/dev/null; then
  claude_ops::ensure_git_exclude "$REPO" '.claude/observability'
  EXCL="$REPO/.git/info/exclude"
  if grep -qxF -- '/.claude/observability/' "$EXCL" 2>/dev/null; then
    ok "exclude line added to .git/info/exclude"
  else
    bad "exclude line added to .git/info/exclude"
  fi
  before=$(grep -cxF -- '/.claude/observability/' "$EXCL")
  claude_ops::ensure_git_exclude "$REPO" '.claude/observability'
  assert_eq "exclude append is idempotent" "$before" \
    "$(grep -cxF -- '/.claude/observability/' "$EXCL")"
  mkdir -p "$REPO/.claude/observability"
  : >"$REPO/.claude/observability/skill-usage.jsonl"
  if [[ -z "$(git -C "$REPO" status --porcelain -- .claude/observability 2>/dev/null)" ]]; then
    ok "store dir invisible to git status"
  else
    bad "store dir invisible to git status"
  fi
  REPO3="$TEST_TMPDIR/repo3"
  mkdir -p "$REPO3"
  git -C "$REPO3" init -q 2>/dev/null
  claude_ops::ensure_git_exclude "$REPO3" './.claude//observability/'
  if grep -qxF -- '/.claude/observability/' "$REPO3/.git/info/exclude" 2>/dev/null; then
    ok "denormalized configured dir yields canonical exclude line"
  else
    bad "denormalized configured dir yields canonical exclude line"
  fi
  mkdir -p "$REPO3/.claude/observability"
  : >"$REPO3/.claude/observability/skill-usage.jsonl"
  if [[ -z "$(git -C "$REPO3" status --porcelain 2>/dev/null)" ]]; then
    ok "status clean under denormalized configured dir"
  else
    bad "status clean under denormalized configured dir"
  fi
  REPO2="$TEST_TMPDIR/repo2"
  mkdir -p "$REPO2"
  git -C "$REPO2" init -q 2>/dev/null
  CLAUDE_PLUGIN_OPTION_SKILL_USAGE_GIT_EXCLUDE=false \
    claude_ops::ensure_git_exclude "$REPO2" '.claude/observability'
  if grep -qxF -- '/.claude/observability/' "$REPO2/.git/info/exclude" 2>/dev/null; then
    bad "skill_usage_git_exclude=false suppresses the exclude write"
  else
    ok "skill_usage_git_exclude=false suppresses the exclude write"
  fi
  # Glob-metachar configured dir writes a LITERAL exclude pattern (no dir
  # created — * is illegal in a filename on Windows; the string path is the
  # subject here).
  REPO4="$TEST_TMPDIR/repo4"
  mkdir -p "$REPO4"
  git -C "$REPO4" init -q 2>/dev/null
  claude_ops::ensure_git_exclude "$REPO4" 'telemetry*'
  if grep -qxF -- '/telemetry\*/' "$REPO4/.git/info/exclude" 2>/dev/null; then
    ok "glob-metachar configured dir written as literal exclude pattern"
  else
    bad "glob-metachar configured dir written as literal exclude pattern"
  fi
fi
NONREPO="$TEST_TMPDIR/nonrepo"
mkdir -p "$NONREPO"
claude_ops::ensure_git_exclude "$NONREPO" '.claude/observability'
ok "non-repo project is a silent no-op for exclude hygiene"

report
