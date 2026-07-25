#!/usr/bin/env bash
# Contract test for skill-reference-verify.sh (guardrails plugin).
#
# Black-box subprocess invocation. Builds a synthetic marketplace working tree so
# the plugins-root and plugin-scope gates have both a hit and a miss to
# distinguish, then feeds a PostToolUse Write|Edit payload on stdin.

# shellcheck disable=SC2016
# Every fixture below is markdown fed to the hook as literal data, and backticks
# are the code-span delimiters the hook scans for — single quotes are required so
# nothing expands. Disabled file-wide rather than on ~20 individual lines.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/skill-reference-verify.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

unset CLAUDE_PROJECT_DIR
RC=0

# hook::buffer_stdin bounds its fd0 read at CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT
# seconds, default 2, and a timeout makes an advisory hook exit 0 silently. A
# single invocation costs 10-20 s of wall time on a loaded Windows/Git Bash box, so
# the default bound produces empty output and a false FAIL that looks like a logic
# defect. Raised here because these cases test detection, not the read bound.
export CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=30

# --- Synthetic marketplace ---------------------------------------------------
# Two plugins. `alpha`'s manifest name matches its directory. `beta`'s manifest
# name deliberately DIVERGES from its directory (`beta-dir`), which is what
# proves resolution goes through the manifest rather than the directory listing.
REPO="$TEST_TMPDIR/market"
mkdir -p "$REPO"
git -C "$REPO" init -q

mk_plugin() {
  local dir="$1" name="$2"
  mkdir -p "$REPO/plugins/$dir/.claude-plugin"
  MSYS_NO_PATHCONV=1 jq -n --arg n "$name" '{name:$n,version:"0.1.0"}' \
    >"$REPO/plugins/$dir/.claude-plugin/plugin.json"
}
# mk_skill <plugin-dir> <skill-dir> [frontmatter-name]
mk_skill() {
  local pdir="$1" sdir="$2" fname="${3:-}"
  mkdir -p "$REPO/plugins/$pdir/skills/$sdir"
  local f="$REPO/plugins/$pdir/skills/$sdir/SKILL.md"
  if [[ -n "$fname" ]]; then
    {
      printf -- '---\n'
      printf 'name: %s\n' "$fname"
      printf 'description: x\n'
      printf -- '---\n'
    } >"$f"
  else
    : >"$f"
  fi
}

mk_plugin alpha alpha
mk_skill alpha setup
mk_skill alpha audit
# Command name comes from frontmatter, not the directory.
mk_skill alpha legacy-dir renamed-command
# Quoted frontmatter name must resolve identically.
mk_skill alpha quoted-dir '"quoted-name"'

mk_plugin beta-dir beta
mk_skill beta-dir check

TARGET="$REPO/notes.md"
: >"$TARGET"

run() {
  local out
  out=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$TARGET" "$1")" 2>&1)
  RC=$?
  printf '%s' "$out"
}
run_edit() {
  local out
  out=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$TARGET" "$1")" 2>&1)
  RC=$?
  printf '%s' "$out"
}

# ============================ MUST FIRE =====================================

OUT=$(run 'Run `/alpha:nonexistent` next.')
assert_exit "unresolved skill → exit 0 (advisory)" 0 "$RC"
assert_contains "unresolved skill → named" "$OUT" "UNRESOLVED_SKILL: /alpha:nonexistent"
assert_contains "unresolved skill → names the searched plugin dir" "$OUT" "plugins/alpha/skills/"

OUT=$(run 'Both `/alpha:ghost` and `/beta:missing` are gone.')
assert_contains "two unresolved → count" "$OUT" "2 skill reference(s) do not resolve"
assert_contains "two unresolved → manifest-named plugin resolves to its real dir" "$OUT" \
  "plugins/beta-dir/skills/"

OUT=$(run_edit 'Now cites `/alpha:vanished`.')
assert_contains "Edit hunk scanned via new_string" "$OUT" "UNRESOLVED_SKILL: /alpha:vanished"

# The advisory must state its tier — the issue this guard ships under requires
# the third guard never read as deterministic.
OUT=$(run 'Run `/alpha:nonexistent`.')
assert_contains "advisory states detect-then-judge tier" "$OUT" "Detect-then-judge"

# Repro-first regressions for review findings on #1284.

# A bare directory under skills/ is NOT a skill. Without a SKILL.md there is no
# command, so the advisory must still fire — the old directory-only test
# suppressed it.
mkdir -p "$REPO/plugins/alpha/skills/ghost"
OUT=$(run 'Run `/alpha:ghost`.')
assert_contains "skills/ dir without SKILL.md → still unresolved" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost"

# A frontmatter name carrying a trailing YAML comment is a valid rename and must
# resolve; the old end-of-line-anchored parser extracted nothing.
mk_skill alpha commented-dir 'commented-name # public command'
OUT=$(run 'Run `/alpha:commented-name`.')
assert_silent "frontmatter name with trailing YAML comment → resolves" "$OUT"

# The DIRECTORY name of a renamed skill is not an alias. `skills/legacy-dir/`
# declaring `name: renamed-command` answers to /alpha:renamed-command only — the
# stale pre-rename spelling must still fire, since suppressing it defeats the
# guard's whole purpose.
OUT=$(run 'Stale ref `/alpha:legacy-dir`.')
assert_contains "renamed skill's directory name is NOT an alias → fires" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:legacy-dir"
OUT=$(run 'Current ref `/alpha:renamed-command`.')
assert_silent "the declared frontmatter name still resolves" "$OUT"

# A skill declaring no frontmatter name answers to its directory name.
OUT=$(run 'Run `/alpha:setup`.')
assert_silent "no frontmatter name → directory name is the command" "$OUT"

# An invocation carrying arguments is the common form in this repo. The reference
# is the leading token of the span, not the whole span.
OUT=$(run 'Run `/alpha:ghost-arg --apply` now.')
assert_contains "argument-bearing invocation → leading token extracted" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-arg"
OUT=$(run 'Run `/alpha:audit --dry-run <target>`.')
assert_silent "argument-bearing invocation of a real skill → silent" "$OUT"

# ============================ MUST STAY QUIET ===============================

OUT=$(run 'Run `/alpha:setup` and `/alpha:audit` first.')
assert_exit "resolving skills → exit 0" 0 "$RC"
assert_silent "resolving skills → silent" "$OUT"

# Manifest name diverges from directory name; the reference uses the manifest name.
OUT=$(run 'Run `/beta:check`.')
assert_silent "plugin resolved via manifest name, not directory name → silent" "$OUT"

# Frontmatter name diverges from the skill directory name.
OUT=$(run 'Run `/alpha:renamed-command`.')
assert_silent "skill resolved via frontmatter name → silent" "$OUT"

OUT=$(run 'Run `/alpha:quoted-name`.')
assert_silent "skill resolved via quoted frontmatter name → silent" "$OUT"

# PLUGIN-SCOPE GATE: this repo does not own the plugin, so it has no authority.
OUT=$(run 'Install `/some-other-market:thing` from elsewhere.')
assert_silent "unowned plugin → not adjudicated" "$OUT"

# A reference to a directory that exists but carries no manifest is not a plugin.
mkdir -p "$REPO/plugins/not-a-plugin/skills/x"
OUT=$(run 'Run `/not-a-plugin:x`.')
assert_silent "directory without a manifest → not a plugin, silent" "$OUT"

OUT=$(run 'Unbackticked /alpha:nonexistent in prose is not a command.')
assert_silent "unbackticked reference → not scanned" "$OUT"

OUT=$(run 'A URL fragment `https://x.test/a:b` and a time `12:30` are not references.')
assert_silent "URL fragment and time → silent" "$OUT"

OUT=$(run 'Uppercase `/Alpha:Setup` does not match the command grammar.')
assert_silent "uppercase reference → silent (not command-shaped)" "$OUT"

# PLUGINS-ROOT GATE: outside a marketplace repo there is no local authority.
PLAIN="$TEST_TMPDIR/plain"
mkdir -p "$PLAIN"
git -C "$PLAIN" init -q
PLAIN_TARGET="$PLAIN/notes.md"
: >"$PLAIN_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$PLAIN" bash "$HOOK" <<<"$(write_json "$PLAIN_TARGET" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "no plugins/ tree → exit 0" 0 "$RC"
assert_silent "no plugins/ tree → silent (no local authority)" "$OUT"

# A plugins/ directory with no manifests is not a marketplace either.
EMPTY="$TEST_TMPDIR/empty-market"
mkdir -p "$EMPTY/plugins/whatever"
git -C "$EMPTY" init -q
EMPTY_TARGET="$EMPTY/notes.md"
: >"$EMPTY_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$EMPTY" bash "$HOOK" <<<"$(write_json "$EMPTY_TARGET" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "plugins/ with no manifests → exit 0" 0 "$RC"
assert_silent "plugins/ with no manifests → silent" "$OUT"

# Non-markdown files are out of scope.
SCRIPT="$REPO/tool.sh"
: >"$SCRIPT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$SCRIPT" 'echo `/alpha:nonexistent`')" 2>&1)
RC=$?
assert_exit "non-markdown file → exit 0" 0 "$RC"
assert_silent "non-markdown file → not scanned" "$OUT"

OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(notebook_json "$TARGET" '`/alpha:nonexistent`')" 2>&1)
RC=$?
assert_exit "NotebookEdit payload → exit 0" 0 "$RC"
assert_silent "NotebookEdit payload → silent" "$OUT"

OUTSIDE="$TEST_TMPDIR/outside.md"
: >"$OUTSIDE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "file outside project dir → exit 0" 0 "$RC"
assert_silent "file outside project dir → silent" "$OUT"

# ============================ KILL SWITCH ===================================

OUT=$(CLAUDE_PROJECT_DIR="$REPO" CLAUDE_PLUGIN_OPTION_SKILL_REFERENCE_VERIFY_ENABLED=false \
  bash "$HOOK" <<<"$(write_json "$TARGET" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "kill switch → exit 0" 0 "$RC"
assert_silent "kill switch → silent" "$OUT"

# ============================ EMPTY STDIN ===================================

OUT=$(bash "$HOOK" </dev/null 2>&1)
RC=$?
assert_exit "empty stdin → exit 0" 0 "$RC"
assert_silent "empty stdin → no output" "$OUT"

# ============================ MISSING PREREQUISITE ==========================

# Runtime jq-removal is not portably simulable — an isolated bin dir without jq
# cannot host bash + coreutils across Git Bash and Linux, the same constraint
# secret-pattern-detection.test.sh and require-jq-notice-isolation.test.sh both
# document. Assert the fail-open guard is present via the shared helper;
# require_jq's own behavior is covered by lib/hook-utils.test.sh, and this hook's
# notice key is proven unique plugin-wide by require-jq-notice-isolation.test.sh.
HOOK_SRC=$(cat "$HOOK")
assert_contains "jq guard: uses hook::require_jq" "$HOOK_SRC" 'hook::require_jq'
assert_contains "jq guard: hook-specific notice key" "$HOOK_SRC" 'guardrails-skill-reference-verify'
assert_contains "repo root is file-anchored" "$HOOK_SRC" 'hook::repo_root "$(dirname "$FILE")"'

# ============================ TELEMETRY =====================================

TEL="$(mktemp -p "$TEST_TMPDIR")"
SINK="$(make_sink "cat >\"$TEL\"")"
CLAUDE_PROJECT_DIR="$REPO" HOOK_TELEMETRY_SINK="$SINK" \
  bash "$HOOK" <<<"$(write_json "$TARGET" 'Run `/alpha:nonexistent`.')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "skill-reference-verify"
  assert_contains "telemetry: status ok" "$(jq -r '.status' "$TEL")" "ok"
  assert_contains "telemetry: findings name the reference" "$(jq -r '.data.findings[]' "$TEL")" "/alpha:nonexistent"
  assert_absent "telemetry: file path is repo-relative, never absolute" \
    "$(jq -r '.data.file' "$TEL")" "$TEST_TMPDIR"
else
  bad "telemetry: no envelope written"
fi

report
