#!/usr/bin/env bash
# Contract test for block-hook-bypass.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained — no
# host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-hook-bypass.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# run <label> <command> <expected-exit> [extra-env NAME=VAL ...]
run() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc
  env "$@" bash "$HOOK" <<<"$(command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

# --- Core bypass forms ------------------------------------------------------
run "cat > file (blocked)" "cat > foo.txt" 2
run "cat>file no space (blocked)" "cat>foo.txt" 2
run "cat >> file append (blocked)" "cat >> foo.txt" 2
run "echo > file (blocked)" "echo hello > foo.txt" 2
# No-space redirect forms (echo>file / echo>>file) still write a file.
run "echo>file no space (blocked)" "echo hi>foo.txt" 2
run "echo>>file no space append (blocked)" "echo hi>>foo.txt" 2
run "echo>/dev/null no space (allowed)" "echo hi>/dev/null" 0
run "python3 -c open write (blocked)" \
  "python3 -c \"open('x','w').write('a')\"" 2
run "git status (allowed)" "git status" 0
run "cat file (allowed)" "cat README.md" 0
run "python3 -c json parse (allowed)" \
  "python3 -c \"import json; print(json.loads('{}'))\"" 0

# --- Redirect false-positive regression -------------------------------------
# stderr/fd redirects + /dev/null discards are NOT file-write bypasses, even
# when an `echo` appears in the same compound command.
run "echo + 2>/dev/null (allowed)" \
  "echo done; grep -i pat file 2>/dev/null" 0
run "echo + 2>&1 (allowed)" "echo hi; ls foo 2>&1 | cat" 0
run "echo stdout to /dev/null (allowed)" "echo noise >/dev/null" 0
run "echo + find 2>/dev/null pipe (allowed)" \
  "echo scan; find . -name x 2>/dev/null | head" 0
# Real writes still blocked, including alongside a stderr suppressor (no hole).
run "echo append > file still blocked" "echo line >> real.txt" 2
run "echo > file with 2>/dev/null still blocked" \
  "echo data > real.txt 2>/dev/null" 2

# --- Producer-scoped redirect (false-fire regression) ------------------------
# The guard must flag ONLY when the echo/printf is itself the producer whose
# stdout is redirected into a file — not any compound command that merely
# CO-MENTIONS an `echo` token and a `>` token. The three cases below are the
# false positives observed during PR babysitting (a script's stdout captured
# to a scratchpad data file, with an unrelated `echo` status line in the same
# call), which must now be ALLOWED.
# 1. Script stdout captured to a JSON sink + a trailing echo status line.
run "script stdout capture + echo status (allowed)" \
  'bash fetch-all-pr-comments.sh 526 > pr526.json && echo "EXIT: $?"' 0
run "script stdout capture; echo status semicolon (allowed)" \
  'bash fetch.sh 526 > pr526.json; echo "EXIT: $?"' 0
# 2. Same capture inside a bounded poll loop whose body also echoes a summary.
# shellcheck disable=SC2016  # literal loop is the command under test, not for expansion
run "poll-loop redirect + echo summary (allowed)" \
  'for i in 1 2 3; do bash fetch.sh 526 > poll.json; echo "poll $i"; done' 0
# 3. echo/`>` tokens appearing ONLY inside a quoted --body argument (the
#    `gh issue create` for the bug report itself). Single-line and multi-line
#    quoted payloads both stay inert — the multi-line body is the exact form that
#    forced the reporter to fall back to `--body-file`.
run "gh issue create --body mentioning echo > file, single line (allowed)" \
  'gh issue create --title t --body "echo > file write bypasses"' 0
GH_MULTILINE_BODY=$(printf 'gh issue create --title t --body "The guard blocks:\necho > file write bypasses\nremove the echo statements"')
run "gh issue create --body mentioning echo > file, multi-line (allowed)" \
  "$GH_MULTILINE_BODY" 0

# True positives must still block: the echo/printf IS the redirected producer,
# including inside compound-command bodies (loops, conditionals, brace groups)
# where the issue's false positives all lived.
run "echo content > file still blocked" 'echo "some content" > file.txt' 2
run "printf content > file (blocked)" 'printf "%s" "content" > file.txt' 2
run "echo > file after an unrelated command (blocked)" \
  'ls foo 2>/dev/null; echo "x" > real.txt' 2
# shellcheck disable=SC2016  # literal loop is the command under test, not for expansion
run "echo > file in for-loop body (blocked)" \
  'for f in a b; do echo "$f" > out.txt; done' 2
run "echo > file in if-then body (blocked)" \
  'if true; then echo x > real.txt; fi' 2
run "echo > file in brace group (blocked)" '{ echo x > real.txt; }' 2
# Group-level redirect (`{ echo x; } > file`) is NOT caught — the closing `}`
# and `)` are seps, so the redirect is a separate segment from the echo inside.
# Accepted as the floor: this form is structurally unusual for LLM output.
run "echo in brace group with group-level redirect (accepted floor — allowed)" \
  '{ echo x; } > real.txt' 0

# --- Command-prefix producers (bypass regression) ----------------------------
# A producer preceded by a valid shell prefix — an env assignment or a
# command-name modifier (`command`/`builtin`/`exec`/`env`) — must still be caught:
# its stdout is redirected into a real file exactly like a bare `echo > file`.
# The head-only producer match would otherwise skip these, making the Write/Edit
# bypass trivial via `command echo` or `FOO=bar echo`.
run "env-assignment prefix before echo > file (blocked)" \
  'FOO=bar echo content > real.txt' 2
run "command modifier before echo > file (blocked)" \
  'command echo content > real.txt' 2
run "builtin modifier before printf > file (blocked)" \
  'builtin printf x > real.txt' 2
run "exec modifier before echo > file (blocked)" 'exec echo x > real.txt' 2
run "env modifier before echo > file (blocked)" 'env echo content > real.txt' 2
# No new false positive: peeling a prefix only reveals the command word; a
# NON-producer command word after the prefix is still allowed.
run "command modifier before non-producer > file (allowed)" \
  'command ls > out.txt' 0
run "env-assignment before non-producer > file (allowed)" \
  'FOO=bar make > log.txt' 0
# Floor: external command-runner utilities (own options + a command arg) are NOT
# peeled — each needs per-utility argument parsing. Accepted as the floor; these
# forms are structurally unusual for LLM output.
run "nohup wrapper before echo > file (accepted floor — allowed)" \
  'nohup echo x > real.txt' 0

# --- Executable-token vs quoted-argument detection --------------------------
# Prose or a commit message merely MENTIONING a bypass in a quoted span is
# documentation, not a Write/Edit bypass. The python write-indicator scan stays
# on the raw command, so a real `python3 -c "open(...)"` still blocks.
run "echo prose mentioning python3 -c open (allowed)" \
  "echo 'use python3 -c open() to write a file'" 0
run "commit msg mentioning python3 -c open (allowed)" \
  "git commit -m 'doc: do not use python3 -c open() writes'" 0
run "python3 -c single-quoted open write (blocked)" \
  "python3 -c 'open(\"x\",\"w\").write(\"a\")'" 2

# --- Case-insensitive command-token detection (matters on Windows) ----------
run "uppercase CAT > file (blocked)" "CAT > foo.txt" 2
run "uppercase ECHO > file (blocked)" "ECHO hello > foo.txt" 2

# --- Accepted string-matching floor -----------------------------------------
# A write inside a command substitution in double quotes is NOT caught — the
# strip treats the quoted span as inert, and catching it would re-block inert
# prose sharing the span. A genuine regression vs raw-match, accepted as the floor.
# shellcheck disable=SC2016  # literal $(...) is the command under test, not for expansion
run "write in command substitution (accepted floor — allowed)" \
  'echo "$(python3 -c '\''import pathlib'\'')"' 0

# --- Heredoc terminator with a regex-metachar delimiter ---------------------
# The heredoc body is stripped; the terminator must be matched LITERALLY. A
# delimiter like EOF+ would break a `=~ "$delim"` compare (the `+` quantifies),
# leaving the stripper stuck in-heredoc and silently swallowing the trailing
# `cat > real.txt` bypass. Regression for that: the bypass after the heredoc
# must still block.
HEREDOC_METACHAR=$(printf 'cat <<%sEOF+%s\ncontent line\nEOF+\ncat > real.txt' "'" "'")
run "heredoc metachar delim, trailing cat > bypass (blocked)" "$HEREDOC_METACHAR" 2

# Backslash-quoted heredoc delimiter (<<\EOF) terminates on bare EOF — the strip
# must strip the leading backslash so the terminator matches, else it stays
# in-heredoc and swallows the trailing bypass.
HEREDOC_BACKSLASH=$(printf 'cat <<\\EOF\ncontent line\nEOF\ncat > real.txt')
run "heredoc backslash delim, trailing cat > bypass (blocked)" "$HEREDOC_BACKSLASH" 2

# A stdout redirect ON the heredoc opener line (`cat <<EOF > file`) is a real
# file-write bypass. The strip must drop only the heredoc operator + delimiter,
# keeping the trailing `> file` so the redirect scan still fires — truncating
# everything after `<<` would leak this form (exit 0).
HEREDOC_OPENER_REDIR=$(printf 'cat <<EOF > real.txt\ncontent line\nEOF')
run "heredoc opener stdout redirect (blocked)" "$HEREDOC_OPENER_REDIR" 2
# A plain heredoc with NO redirect on the opener stays allowed.
HEREDOC_NO_REDIR=$(printf 'cat <<EOF | cat\ncontent line\nEOF')
run "heredoc opener, no redirect (allowed)" "$HEREDOC_NO_REDIR" 0
# Redirect GLUED to the delimiter (no space): bash ends the delimiter word at
# `>`, so `cat <<EOF>real.txt` is a real stdout redirect. The delimiter capture
# must stop at `>` (not greedily swallow `EOF>real.txt`) so the `>` survives.
HEREDOC_GLUED_REDIR=$(printf 'cat <<EOF>real.txt\ncontent line\nEOF')
run "heredoc opener redirect glued to delimiter (blocked)" "$HEREDOC_GLUED_REDIR" 2
# Tab-stripping opener form (`<<-EOF`): the `<<-?` regex + fix cover it.
HEREDOC_TAB_STRIP=$(printf 'cat <<-EOF > real.txt\ncontent line\nEOF')
run "heredoc tab-strip opener redirect (blocked)" "$HEREDOC_TAB_STRIP" 2
# Quoted delimiter (`<<'EOF'`): BASH_REMATCH[0] is `<<'EOF'`; the suffix scan
# still preserves the trailing redirect.
HEREDOC_QUOTED_DELIM=$(printf "cat <<'EOF' > real.txt\ncontent line\nEOF")
run "heredoc quoted-delimiter opener redirect (blocked)" "$HEREDOC_QUOTED_DELIM" 2

# A here-string (<<<) has no terminator — it must NOT be mistaken for a heredoc,
# which would strand the stripper and swallow the trailing bypass.
HERESTRING=$(printf 'read x <<< %sok%s\ncat > real.txt' '"' '"')
run "here-string then trailing cat > bypass (blocked)" "$HERESTRING" 2
# And a plain here-string with no bypass stays allowed.
run "here-string alone (allowed)" "grep foo <<< \"haystack\"" 0

# --- Kill switch — disabled path is a clean no-op even on a bypass ----------
run "kill switch off → no-op despite cat > file" "cat > foo.txt" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_ENABLED=false

# --- Telemetry: block emits a `blocked` envelope ----------------------------
TEL="$(mktemp -p "$TEST_TMPDIR")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(command_json 'cat > foo.txt')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "block-hook-bypass"
  assert_contains "telemetry: status blocked" "$(jq -r '.status' "$TEL")" "blocked"
  assert_contains "telemetry: subject Bash:cat" "$(jq -r '.data.subject' "$TEL")" "Bash:cat"
  assert_contains "telemetry: form cat-redirect" "$(jq -r '.data.form' "$TEL")" "cat-redirect"
else
  bad "telemetry: no envelope written on block"
fi

report
