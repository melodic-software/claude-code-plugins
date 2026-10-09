#!/usr/bin/env bash
# Tests for pointer-line.sh, the helper that keeps the developer-experience
# pointer line inside the shared plugin-conventions block of a consumer's
# AGENTS.md. Every expected file below is written out by hand from the block
# contract (marker text, line text, ownership prefix), never captured from a run.
#
# Each case builds its own fixture repository under one mktemp directory that
# the EXIT trap removes. Cases that need a symlink or a chmod the host does not
# honor (Git Bash without symlink rights, NTFS modes) print SKIP and move on.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PROJECT_DIR POINTER_LINE_RESOLVER

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/pointer-line.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASES=0

BEGIN='<!-- BEGIN GENERATED: plugin-conventions -->'
END='<!-- END GENERATED: plugin-conventions -->'
DEF='docs/conventions/developer-experience.md'
BOM=$'\xef\xbb\xbf'
# shellcheck disable=SC2016 # backticks are Markdown, not command substitution
OTHER='- Before editing hooks, read `docs/conventions/hooks.md` and use /hooks:check.'
CITER='- Run /developer-experience:build-cli before adding a release script (release plugin).'

# The DX-owned line for a conventions path, spelled out from the contract.
dx() {
  printf '%s' '- Before creating, changing or cleaning up CLIs, scripts or other developer tools, read `'
  printf '%s' "$1"
  printf '%s' '` and use /developer-experience:build-cli or /developer-experience:audit-tools.'
}

pass() {
  CASES=$((CASES + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASES=$((CASES + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}

skip() { printf 'SKIP: %s (%s)\n' "$1" "$2"; }

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "contains: $3" "$2" ;;
  esac
}

assert_absent() {
  case "$2" in
    *"$3"*) fail "$1" "does NOT contain: $3" "$2" ;;
    *) pass "$1" ;;
  esac
}

# assert_file <name> <actual-file> <expected-file> : byte-for-byte equality.
assert_file() {
  if cmp -s "$2" "$3"; then
    pass "$1"
  else
    fail "$1" "$(od -c "$3" | head -20)" "$(od -c "$2" | head -20)"
  fi
}

fixture() { mktemp -d "$TEST_TMPDIR/repo.XXXXXX"; }

# run <args...> : run the helper with no TTY on stdin; sets OUT, ERR, RC.
run() {
  OUT="$(bash "$SUT" "$@" 2>"$TEST_TMPDIR/stderr" </dev/null)"
  RC=$?
  ERR="$(cat "$TEST_TMPDIR/stderr")"
}

# ls is the portable way to read an inode and a mode string (stat differs on BSD).
# shellcheck disable=SC2012
inode() { ls -i "$1" | awk '{print $1}'; }
# shellcheck disable=SC2012
perms() { ls -l "$1" | cut -c1-10; }

kind() {
  if [[ -L "$1" ]]; then echo symlink; elif [[ -e "$1" ]]; then echo file; else echo absent; fi
}

test_absent_block_appends_block() {
  local r
  r="$(fixture)"
  printf '# Repo\n\nTeam text.\n' >"$r/AGENTS.md"
  printf '# Repo\n\nTeam text.\n\n%s\n%s\n%s\n' "$BEGIN" "$(dx "$DEF")" "$END" >"$r/want"
  run check --root "$r" --path "$DEF"
  assert_eq "absent block: check exits 1" 1 "$RC"
  assert_contains "absent block: check reports no-block" "$OUT" "state: no-block"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "absent block: apply exits 0" 0 "$RC"
  assert_file "absent block: block and line appended" "$r/AGENTS.md" "$r/want"
}

test_block_without_line_inserts() {
  local r
  r="$(fixture)"
  printf '%s\n%s\n%s\n' "$BEGIN" "$OTHER" "$END" >"$r/AGENTS.md"
  printf '%s\n%s\n%s\n%s\n' "$BEGIN" "$OTHER" "$(dx "$DEF")" "$END" >"$r/want"
  run check --root "$r" --path "$DEF"
  assert_contains "no line: check reports no-line" "$OUT" "state: no-line"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "no line: apply exits 0" 0 "$RC"
  assert_file "no line: line inserted before the end marker" "$r/AGENTS.md" "$r/want"
}

test_stale_path_replaced() {
  local r
  r="$(fixture)"
  printf '%s\n%s\n%s\n%s\n' "$BEGIN" "$(dx old/place.md)" "$OTHER" "$END" >"$r/AGENTS.md"
  printf '%s\n%s\n%s\n%s\n' "$BEGIN" "$(dx "$DEF")" "$OTHER" "$END" >"$r/want"
  run check --root "$r" --path "$DEF"
  assert_contains "stale: check reports stale" "$OUT" "state: stale"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "stale: apply exits 0" 0 "$RC"
  assert_file "stale: only the DX line replaced, in place" "$r/AGENTS.md" "$r/want"
}

test_identical_line_no_write() {
  local r before
  r="$(fixture)"
  printf '%s\n%s\n%s\n' "$BEGIN" "$(dx "$DEF")" "$END" >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  before="$(inode "$r/AGENTS.md")"
  run check --root "$r" --path "$DEF"
  assert_eq "identical: check exits 0" 0 "$RC"
  assert_contains "identical: check reports current" "$OUT" "state: current"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "identical: apply exits 0" 0 "$RC"
  assert_contains "identical: apply reports unchanged" "$OUT" "result: unchanged"
  assert_file "identical: bytes unchanged" "$r/AGENTS.md" "$r/want"
  assert_eq "identical: file not rewritten (same inode)" "$before" "$(inode "$r/AGENTS.md")"
}

test_two_dx_lines_fail() {
  local r
  r="$(fixture)"
  printf '%s\n%s\n%s\n%s\n' "$BEGIN" "$(dx a.md)" "$(dx b.md)" "$END" >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  run check --root "$r" --path "$DEF"
  assert_eq "two lines: check exits 3" 3 "$RC"
  assert_contains "two lines: check reports duplicate-line" "$OUT" "state: duplicate-line"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "two lines: apply exits 3" 3 "$RC"
  assert_file "two lines: nothing written" "$r/AGENTS.md" "$r/want"
}

test_unbalanced_begin_only_fails() {
  local r
  r="$(fixture)"
  printf 'Intro\n%s\n%s\n' "$BEGIN" "$OTHER" >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "begin only: apply exits 3" 3 "$RC"
  assert_contains "begin only: reports unbalanced markers" "$OUT" "state: unbalanced-markers"
  assert_file "begin only: nothing written" "$r/AGENTS.md" "$r/want"
}

test_unbalanced_end_only_fails() {
  local r
  r="$(fixture)"
  printf 'Intro\n%s\n%s\n' "$OTHER" "$END" >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "end only: apply exits 3" 3 "$RC"
  assert_file "end only: nothing written" "$r/AGENTS.md" "$r/want"
}

test_outside_text_and_other_lines_identical() {
  local r
  r="$(fixture)"
  # shellcheck disable=SC2016 # backticks and $ are fixture text
  printf '# Rules\n\n  indented `code` & $vars\n\n%s\n%s\n%s\n%s\n%s\nTrailing *user* text.\n\n' \
    "$BEGIN" "$OTHER" "$(dx old.md)" "$CITER" "$END" >"$r/AGENTS.md"
  # shellcheck disable=SC2016 # backticks and $ are fixture text
  printf '# Rules\n\n  indented `code` & $vars\n\n%s\n%s\n%s\n%s\n%s\nTrailing *user* text.\n\n' \
    "$BEGIN" "$OTHER" "$(dx "$DEF")" "$CITER" "$END" >"$r/want"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "outside text: apply exits 0" 0 "$RC"
  assert_file "outside text: every other byte identical" "$r/AGENTS.md" "$r/want"
}

test_no_trailing_newline_kept() {
  local r
  r="$(fixture)"
  printf '%s\n%s\n%s\nlast line' "$BEGIN" "$(dx old.md)" "$END" >"$r/AGENTS.md"
  printf '%s\n%s\n%s\nlast line' "$BEGIN" "$(dx "$DEF")" "$END" >"$r/want"
  run apply --root "$r" --path "$DEF" --yes
  assert_file "no final newline: still none after replace" "$r/AGENTS.md" "$r/want"
}

test_crlf_preserved() {
  local r
  r="$(fixture)"
  printf '# Repo\r\n%s\r\n%s\r\n%s\r\nAfter\r\n' "$BEGIN" "$OTHER" "$END" >"$r/AGENTS.md"
  printf '# Repo\r\n%s\r\n%s\r\n%s\r\n%s\r\nAfter\r\n' "$BEGIN" "$OTHER" "$(dx "$DEF")" "$END" >"$r/want"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "crlf: apply exits 0" 0 "$RC"
  assert_file "crlf: inserted line uses CRLF, rest untouched" "$r/AGENTS.md" "$r/want"
}

test_crlf_identical_recognized() {
  local r
  r="$(fixture)"
  printf '%s\r\n%s\r\n%s\r\n' "$BEGIN" "$(dx "$DEF")" "$END" >"$r/AGENTS.md"
  run check --root "$r" --path "$DEF"
  assert_contains "crlf: current line recognized" "$OUT" "state: current"
}

test_path_with_space_rejected() {
  local r
  r="$(fixture)"
  printf 'Team text.\n' >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  run apply --root "$r" --path 'docs/my conventions.md' --yes
  assert_eq "space in path: exits 2" 2 "$RC"
  assert_contains "space in path: names the problem" "$ERR" "invalid conventions path"
  assert_file "space in path: nothing written" "$r/AGENTS.md" "$r/want"
}

test_path_with_backslash_rejected() {
  local r
  r="$(fixture)"
  printf 'Team text.\n' >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  run apply --root "$r" --path 'docs\conventions.md' --yes
  assert_eq "backslash in path: exits 2" 2 "$RC"
  assert_file "backslash in path: nothing written" "$r/AGENTS.md" "$r/want"
}

test_path_with_dotdot_rejected() {
  local r
  r="$(fixture)"
  run check --root "$r" --path '../outside.md'
  assert_eq "dotdot path: exits 2" 2 "$RC"
  run check --root "$r" --path '/etc/conventions.md'
  assert_eq "absolute path: exits 2" 2 "$RC"
}

test_path_under_dot_claude_rejected() {
  local r
  r="$(fixture)"
  printf 'Team text.\n' >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  run apply --root "$r" --path '.claude/developer-experience.md' --yes
  assert_eq ".claude path: exits 2" 2 "$RC"
  assert_contains ".claude path: names the problem" "$ERR" "never under .claude/"
  assert_file ".claude path: nothing written" "$r/AGENTS.md" "$r/want"
  run check --root "$r" --path '.claude/rules/dx.md'
  assert_eq ".claude nested path: check exits 2" 2 "$RC"
  run check --root "$r" --path 'docs/.claude/dx.md'
  assert_eq ".claude as a later segment: not a usage error" 1 "$RC"
}

test_bom_kept_and_line_found() {
  local r
  r="$(fixture)"
  printf '%s%s\n%s\n%s\n' "$BOM" "$BEGIN" "$(dx "$DEF")" "$END" >"$r/AGENTS.md"
  run check --root "$r" --path "$DEF"
  assert_contains "bom: marker and line found" "$OUT" "state: current"
  printf '%s%s\n%s\n%s\n' "$BOM" "$BEGIN" "$(dx old.md)" "$END" >"$r/AGENTS.md"
  printf '%s%s\n%s\n%s\n' "$BOM" "$BEGIN" "$(dx "$DEF")" "$END" >"$r/want"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "bom: apply exits 0" 0 "$RC"
  assert_file "bom: kept on write" "$r/AGENTS.md" "$r/want"
}

test_missing_agents_check_reports() {
  local r
  r="$(fixture)"
  run check --root "$r" --path "$DEF"
  assert_eq "missing file: check exits 1" 1 "$RC"
  assert_contains "missing file: check reports it" "$OUT" "state: missing-file"
  assert_eq "missing file: check created nothing" absent "$(kind "$r/AGENTS.md")"
}

test_missing_agents_apply_without_yes_writes_nothing() {
  local r
  r="$(fixture)"
  run apply --root "$r" --path "$DEF"
  assert_eq "missing file, no --yes: exits 1" 1 "$RC"
  assert_eq "missing file, no --yes: nothing created" absent "$(kind "$r/AGENTS.md")"
}

test_missing_agents_apply_yes_creates_and_warns() {
  local r
  r="$(fixture)"
  printf '# Claude rules\n' >"$r/CLAUDE.md"
  cp "$r/CLAUDE.md" "$r/claude.want"
  printf '%s\n%s\n%s\n' "$BEGIN" "$(dx "$DEF")" "$END" >"$r/want"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "missing file, --yes: exits 0" 0 "$RC"
  assert_file "missing file, --yes: created with the block" "$r/AGENTS.md" "$r/want"
  assert_contains "missing file, --yes: says no effect" "$OUT$ERR" "no effect until CLAUDE.md imports @AGENTS.md"
  assert_file "missing file, --yes: CLAUDE.md untouched" "$r/CLAUDE.md" "$r/claude.want"
}

test_symlinked_agents_refused() {
  local r
  r="$(fixture)"
  mkdir "$r/shared"
  printf 'Shared text.\n' >"$r/shared/TEAM.md"
  cp "$r/shared/TEAM.md" "$r/want"
  if ! ln -s shared/TEAM.md "$r/AGENTS.md" 2>/dev/null || [[ ! -L "$r/AGENTS.md" ]]; then
    skip "symlinked AGENTS.md" "host cannot create symlinks"
    return
  fi
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "symlink: apply exits 4" 4 "$RC"
  assert_contains "symlink: message names the target" "$ERR" "shared/TEAM.md"
  assert_eq "symlink: link kept" symlink "$(kind "$r/AGENTS.md")"
  assert_file "symlink: target unchanged" "$r/shared/TEAM.md" "$r/want"
}

test_file_mode_kept() {
  local r
  r="$(fixture)"
  printf 'Team text.\n' >"$r/AGENTS.md"
  chmod 0640 "$r/AGENTS.md"
  if [[ "$(perms "$r/AGENTS.md")" != "-rw-r-----" ]]; then
    skip "file mode kept" "host does not honor chmod 0640"
    return
  fi
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "mode: apply exits 0" 0 "$RC"
  assert_eq "mode: 0640 kept" "-rw-r-----" "$(perms "$r/AGENTS.md")"
}

test_other_plugin_citing_dx_skill_untouched() {
  local r
  r="$(fixture)"
  printf '%s\n%s\n%s\n' "$BEGIN" "$CITER" "$END" >"$r/AGENTS.md"
  printf '%s\n%s\n%s\n%s\n' "$BEGIN" "$CITER" "$(dx "$DEF")" "$END" >"$r/want"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "ownership: apply exits 0" 0 "$RC"
  assert_file "ownership: citing line kept, DX line added" "$r/AGENTS.md" "$r/want"
}

test_draft_marker_reported_for_migration() {
  local r
  r="$(fixture)"
  printf '<!-- BEGIN plugin-conventions -->\n%s\n<!-- END plugin-conventions -->\n' "$OTHER" >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  run check --root "$r" --path "$DEF"
  assert_contains "draft marker: check reports it" "$OUT" "state: draft-marker"
  assert_contains "draft marker: names the GENERATED form" "$ERR" "$BEGIN"
  run apply --root "$r" --path "$DEF" --yes
  assert_eq "draft marker: apply exits 3" 3 "$RC"
  assert_file "draft marker: nothing written" "$r/AGENTS.md" "$r/want"
}

# current_agents <root> : an AGENTS.md whose block already holds the current line.
current_agents() { printf '%s\n%s\n%s\n' "$BEGIN" "$(dx "$DEF")" "$END" >"$1/AGENTS.md"; }

test_load_claude_md_without_import() {
  local r
  r="$(fixture)"
  current_agents "$r"
  printf '# Claude only\n' >"$r/CLAUDE.md"
  cp "$r/CLAUDE.md" "$r/claude.want"
  run check --root "$r" --path "$DEF"
  assert_eq "load CLAUDE.md: check exits 1" 1 "$RC"
  assert_contains "load CLAUDE.md: missing import reported" "$OUT" "load: missing-import CLAUDE.md"
  assert_contains "load CLAUDE.md: line to add printed" "$OUT" "add: CLAUDE.md: @AGENTS.md"
  printf '%s\n%s\n%s\n' "$BEGIN" "$(dx old.md)" "$END" >"$r/AGENTS.md"
  run apply --root "$r" --path "$DEF" --yes
  assert_contains "load CLAUDE.md: apply reports it too" "$OUT" "load: missing-import CLAUDE.md"
  assert_file "load CLAUDE.md: apply leaves CLAUDE.md alone" "$r/CLAUDE.md" "$r/claude.want"
}

test_load_claude_md_with_import_ok() {
  local r
  r="$(fixture)"
  current_agents "$r"
  printf '@AGENTS.md\n\nClaude extras.\n' >"$r/CLAUDE.md"
  run check --root "$r" --path "$DEF"
  assert_eq "load import: check exits 0" 0 "$RC"
  assert_absent "load import: no load finding" "$OUT" "load:"
}

# shellcheck disable=SC2016 # backticks are Markdown fences, not command substitution
test_load_import_inside_fenced_block_ignored() {
  local r
  r="$(fixture)"
  current_agents "$r"
  printf '# Claude only\n\n```\n@AGENTS.md\n```\n\n~~~md\n@AGENTS.md\n~~~\n' >"$r/CLAUDE.md"
  run check --root "$r" --path "$DEF"
  assert_eq "fenced import: check exits 1" 1 "$RC"
  assert_contains "fenced import: missing import reported" "$OUT" "load: missing-import CLAUDE.md"
  mkdir "$r/.claude"
  printf '```bash\n@../AGENTS.md\n```\n' >"$r/.claude/CLAUDE.md"
  run check --root "$r" --path "$DEF"
  assert_contains "fenced import: .claude/CLAUDE.md reported" "$OUT" "load: missing-import .claude/CLAUDE.md"
  rm "$r/.claude/CLAUDE.md"
  printf '```\nexample\n```\n@AGENTS.md\n' >"$r/CLAUDE.md"
  run check --root "$r" --path "$DEF"
  assert_eq "import after a closed fence: check exits 0" 0 "$RC"
  assert_absent "import after a closed fence: no load finding" "$OUT" "load:"
}

test_load_dot_claude_md_without_import() {
  local r
  r="$(fixture)"
  current_agents "$r"
  mkdir "$r/.claude"
  printf '# Claude only\n' >"$r/.claude/CLAUDE.md"
  cp "$r/.claude/CLAUDE.md" "$r/claude.want"
  run check --root "$r" --path "$DEF"
  assert_contains "load .claude/CLAUDE.md: missing import reported" "$OUT" "load: missing-import .claude/CLAUDE.md"
  assert_contains "load .claude/CLAUDE.md: relative import printed" "$OUT" "add: .claude/CLAUDE.md: @../AGENTS.md"
  run apply --root "$r" --path "$DEF" --yes
  assert_file "load .claude/CLAUDE.md: apply leaves it alone" "$r/.claude/CLAUDE.md" "$r/claude.want"
}

test_load_claude_local_md_may_not_load() {
  local r
  r="$(fixture)"
  current_agents "$r"
  printf 'my sandbox\n' >"$r/CLAUDE.local.md"
  cp "$r/CLAUDE.local.md" "$r/local.want"
  run check --root "$r" --path "$DEF"
  assert_contains "load CLAUDE.local.md: may not load" "$OUT" "load: may-not-load CLAUDE.local.md"
  assert_contains "load CLAUDE.local.md: line to add printed" "$OUT" "add: CLAUDE.md: @AGENTS.md"
  run apply --root "$r" --path "$DEF" --yes
  assert_file "load CLAUDE.local.md: apply leaves it alone" "$r/CLAUDE.local.md" "$r/local.want"
}

test_load_parent_claude_md_may_not_load() {
  local p r
  p="$(fixture)"
  r="$p/repo"
  mkdir "$r"
  current_agents "$r"
  printf '# Parent rules\n' >"$p/CLAUDE.md"
  cp "$p/CLAUDE.md" "$p/claude.want"
  run check --root "$r" --path "$DEF"
  assert_contains "load parent CLAUDE.md: may not load" "$OUT" "load: may-not-load $p/CLAUDE.md"
  assert_contains "load parent CLAUDE.md: line to add printed" "$OUT" "add: CLAUDE.md: @AGENTS.md"
  run apply --root "$r" --path "$DEF" --yes
  assert_file "load parent CLAUDE.md: apply leaves it alone" "$p/CLAUDE.md" "$p/claude.want"
}

test_load_claude_md_symlink_counts_as_loading() {
  local r
  r="$(fixture)"
  current_agents "$r"
  if ! ln -s AGENTS.md "$r/CLAUDE.md" 2>/dev/null || [[ ! -L "$r/CLAUDE.md" ]]; then
    skip "CLAUDE.md symlinked to AGENTS.md" "host cannot create symlinks"
    return
  fi
  run check --root "$r" --path "$DEF"
  assert_eq "load symlink: check exits 0" 0 "$RC"
  assert_absent "load symlink: no load finding" "$OUT" "load:"
}

# stub <exit> <stdout> <stderr> : a resolver stand-in; prints its path.
stub() {
  local s
  s="$(mktemp "$TEST_TMPDIR/resolver.XXXXXX")"
  printf '#!/usr/bin/env bash\nprintf %%s %q\nprintf %%s %q >&2\nexit %s\n' "$2" "$3" "$1" >"$s"
  printf '%s' "$s"
}

test_resolver_bound_home_used() {
  local r
  r="$(fixture)"
  printf '%s\n%s\n%s\n' "$BEGIN" "$(dx old.md)" "$END" >"$r/AGENTS.md"
  printf '%s\n%s\n%s\n' "$BEGIN" "$(dx team/conv/developer-experience.md)" "$END" >"$r/want"
  POINTER_LINE_RESOLVER="$(stub 0 $'team/conv\n' '')"
  export POINTER_LINE_RESOLVER
  run apply --root "$r" --yes
  unset POINTER_LINE_RESOLVER
  assert_eq "resolver 0: apply exits 0" 0 "$RC"
  assert_contains "resolver 0: source bound" "$OUT" "source: bound"
  assert_file "resolver 0: bound home used" "$r/AGENTS.md" "$r/want"
}

test_resolver_unbound_uses_default() {
  local r
  r="$(fixture)"
  printf '%s\n%s\n%s\n' "$BEGIN" "$(dx old.md)" "$END" >"$r/AGENTS.md"
  printf '%s\n%s\n%s\n' "$BEGIN" "$(dx "$DEF")" "$END" >"$r/want"
  POINTER_LINE_RESOLVER="$(stub 1 '' '')"
  export POINTER_LINE_RESOLVER
  run apply --root "$r" --yes
  unset POINTER_LINE_RESOLVER
  assert_eq "resolver 1: apply exits 0" 0 "$RC"
  assert_contains "resolver 1: source default" "$OUT" "source: default"
  assert_file "resolver 1: default path used" "$r/AGENTS.md" "$r/want"
}

test_resolver_fail_stops_without_fallback() {
  local r
  r="$(fixture)"
  printf '%s\n%s\n%s\n' "$BEGIN" "$(dx old.md)" "$END" >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  POINTER_LINE_RESOLVER="$(stub 3 '' 'FAIL: two pointer lines in one region')"
  export POINTER_LINE_RESOLVER
  run apply --root "$r" --yes
  unset POINTER_LINE_RESOLVER
  assert_eq "resolver 3: apply exits 5" 5 "$RC"
  assert_contains "resolver 3: resolver stderr relayed" "$ERR" "FAIL: two pointer lines in one region"
  assert_absent "resolver 3: no default fallback" "$OUT" "$DEF"
  assert_file "resolver 3: nothing written" "$r/AGENTS.md" "$r/want"
}

test_resolver_internal_error_stops() {
  local r
  r="$(fixture)"
  printf '%s\n%s\n%s\n' "$BEGIN" "$(dx old.md)" "$END" >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  POINTER_LINE_RESOLVER="$(stub 2 '' 'ERROR: unusable --root')"
  export POINTER_LINE_RESOLVER
  run apply --root "$r" --yes
  unset POINTER_LINE_RESOLVER
  assert_eq "resolver 2: apply exits 6" 6 "$RC"
  assert_contains "resolver 2: reports internal error" "$ERR" "internal error"
  assert_file "resolver 2: nothing written" "$r/AGENTS.md" "$r/want"
}

test_dry_run_shows_diff_writes_nothing() {
  local r
  r="$(fixture)"
  printf 'Team text.\n' >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  run apply --root "$r" --path "$DEF" --dry-run
  assert_eq "dry run: exits 0" 0 "$RC"
  assert_contains "dry run: diff shows the added line" "$OUT" "+$(dx "$DEF")"
  assert_contains "dry run: reports would-write" "$OUT" "result: would-write"
  assert_file "dry run: nothing written" "$r/AGENTS.md" "$r/want"
}

test_apply_without_yes_and_no_tty_declines() {
  local r
  r="$(fixture)"
  printf 'Team text.\n' >"$r/AGENTS.md"
  cp "$r/AGENTS.md" "$r/want"
  run apply --root "$r" --path "$DEF"
  assert_eq "no tty, no --yes: exits 1" 1 "$RC"
  assert_contains "no tty, no --yes: says how to confirm" "$ERR" "--yes"
  assert_file "no tty, no --yes: nothing written" "$r/AGENTS.md" "$r/want"
}

test_help_and_usage_errors() {
  run --help
  assert_eq "help: exits 0" 0 "$RC"
  assert_contains "help: prints usage on stdout" "$OUT" "Usage:"
  run frobnicate
  assert_eq "unknown command: exits 2" 2 "$RC"
  run check --bogus
  assert_eq "unknown flag: exits 2" 2 "$RC"
}

test_absent_block_appends_block
test_block_without_line_inserts
test_stale_path_replaced
test_identical_line_no_write
test_two_dx_lines_fail
test_unbalanced_begin_only_fails
test_unbalanced_end_only_fails
test_outside_text_and_other_lines_identical
test_no_trailing_newline_kept
test_crlf_preserved
test_crlf_identical_recognized
test_path_with_space_rejected
test_path_with_backslash_rejected
test_path_with_dotdot_rejected
test_path_under_dot_claude_rejected
test_bom_kept_and_line_found
test_missing_agents_check_reports
test_missing_agents_apply_without_yes_writes_nothing
test_missing_agents_apply_yes_creates_and_warns
test_symlinked_agents_refused
test_file_mode_kept
test_other_plugin_citing_dx_skill_untouched
test_draft_marker_reported_for_migration
test_load_claude_md_without_import
test_load_claude_md_with_import_ok
test_load_import_inside_fenced_block_ignored
test_load_dot_claude_md_without_import
test_load_claude_local_md_may_not_load
test_load_parent_claude_md_may_not_load
test_load_claude_md_symlink_counts_as_loading
test_resolver_bound_home_used
test_resolver_unbound_uses_default
test_resolver_fail_stops_without_fallback
test_resolver_internal_error_stops
test_dry_run_shows_diff_writes_nothing
test_apply_without_yes_and_no_tty_declines
test_help_and_usage_errors

printf '\n%d checks, %d failed\n' "$CASES" "$FAILED"
[[ "$FAILED" -eq 0 ]]
