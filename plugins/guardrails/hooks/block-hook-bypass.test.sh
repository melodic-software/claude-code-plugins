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

# --- python-write false-positive regression ---------------------------------
# read-only os.path.*path( helpers end in `path(` and must NOT trip the write
# indicator; the boundary-anchored `path(` clears them while a real
# pathlib.Path().write_text still blocks below.
run "python3 -c os.path.normpath (allowed)" \
  "python3 -c \"import os; print(os.path.normpath('a/b'))\"" 0
run "python3 -c os.path.abspath (allowed)" \
  "python3 -c \"import os; print(os.path.abspath('a'))\"" 0
run "python3 -c os.path.realpath+relpath (allowed)" \
  "python3 -c \"import os,sys; print(os.path.realpath(sys.argv[1]), os.path.relpath(sys.argv[1]))\"" 0
run "python3 -c os.path.commonpath (allowed)" \
  "python3 -c \"import os; print(os.path.commonpath(['a/b','a/c']))\"" 0
run "python3 -c os.path.join producer (allowed)" \
  "python3 -c \"import os; print(os.path.join('a','b'))\"" 0
run "python3 -c pathlib write_text (blocked)" \
  "python3 -c \"import pathlib; pathlib.Path('x').write_text('a')\"" 2
# Path-qualified interpreter: an absolute/relative path to python3 is the same
# write, so the command-word anchor admits a leading path (and a `.exe` suffix).
run "abs-path python3 -c open write (blocked)" \
  "/usr/bin/python3 -c \"open('x','w').write('a')\"" 2
run "path-qualified python3.exe -c open write (blocked)" \
  "/c/Python313/python3.exe -c \"open('x','w').write('a')\"" 2
# The basename anchor must NOT match a longer name that merely ends in python3.
run "notpython3 -c open (allowed)" \
  "notpython3 -c \"open('x','w').write('a')\"" 0

# --- open() write-mode discrimination ---------------------------------------
# `open(` alone is direction-agnostic (`open(f,'w')` writes, `open(f)` reads),
# so it is a write indicator ONLY alongside an argument-position write-mode
# literal — a quoted mode token carrying w / a / x / +. Read modes carry none.
# The reproduced consumer false positive, verbatim in shape: a read-mode open
# feeding json.load.
run "python3 -c read-only open() feeding json.load (allowed)" \
  "python3 -c \"import json; d=json.load(open('x.json'))\"" 0
run "python3 -c bare open(f) (allowed)" "python3 -c \"open(f).read()\"" 0
run "python3 -c open mode 'r' (allowed)" "python3 -c \"open('x','r').read()\"" 0
run "python3 -c open mode 'rb' (allowed)" "python3 -c \"open('x','rb').read()\"" 0
# A dict SUBSCRIPT that looks like a mode token is preceded by `[`, not by a
# comma, so the argument-position anchor keeps this common read shape clear.
run "python3 -c open() + dict subscript ['a'] (allowed)" \
  "python3 -c \"import json;print(json.load(open('p'))['a'])\"" 0
# Write modes still block, in every spelling.
run "python3 -c open mode 'a' append (blocked)" "python3 -c \"open('x','a')\"" 2
run "python3 -c open mode 'r+' update (blocked)" "python3 -c \"open('x','r+')\"" 2
run "python3 -c open mode='w' keyword (blocked)" "python3 -c \"open('x', mode='w')\"" 2
# REGRESSION FLOOR — must not be reintroduced: the check is co-occurrence, not
# positional, precisely so a nested call between `open(` and the mode argument
# cannot fail it open (a positional `open\([^)]*'w'` stops at the first `)`).
run "python3 -c open(nested-call, 'w') (blocked)" \
  "python3 -c \"open(os.path.join(a,b),'w')\"" 2
# ACCEPTED RESIDUAL, fail-CLOSED direction: a read-only open() in a command that
# separately carries an argument-position mode-shaped literal still blocks.
run "python3 -c read open + unrelated ', \\\"a\\\"' literal (accepted over-block)" \
  "python3 -c \"print(open('f').read(), 'a')\"" 2

# --- cat > /dev/null is a discard, not a write -------------------------------
# The exemption the echo/printf lane already grants now applies to `cat >` too,
# in every spelling the strip can produce.
run "cat > /dev/null discard (allowed)" "cat > /dev/null" 0
run "cat>/dev/null no space (allowed)" "cat>/dev/null" 0
run "cat >> /dev/null append discard (allowed)" "cat >> /dev/null" 0
run "cat >/dev/null 2>&1 (allowed)" "cat >/dev/null 2>&1" 0
run "cat >> /dev/null 2>&1 append + fd dup (allowed)" "cat >> /dev/null 2>&1" 0
run "cat > /dev/null; trailing separator (allowed)" "cat > /dev/null; echo done" 0
# A real append target with the same trailing fd dup is still a write.
run "cat >> real.txt 2>&1 still blocked" "cat >> real.txt 2>&1" 2
run "cat > fully-quoted /dev/null (allowed)" 'cat > "/dev/null"' 0
run "cat > partially-quoted /dev/null (allowed)" 'cat > /dev/"null"' 0
# REGRESSION FLOOR — must not be reintroduced: the exemption is SEGMENT-scoped.
# A command-scoped exemption would let the real write in the second segment pass.
run "cat > /dev/null && cat > real.txt still blocked" \
  "cat > /dev/null && cat > real.txt" 2
run "cat > real.txt; cat > /dev/null still blocked" \
  "cat > real.txt; cat > /dev/null" 2

# REGRESSION FLOOR — must not be reintroduced: bash applies redirects LEFT TO
# RIGHT, so the LAST stdout target wins. Exempting a segment merely because a
# /dev/null redirect appears in it is a one-token bypass of the whole guard:
# write the discard first, the real file second, within a single segment.
run "cat > /dev/null > real.txt still blocked" \
  "cat > /dev/null > real.txt" 2
run "cat >/dev/null 1>real.txt still blocked" \
  "cat >/dev/null 1>real.txt" 2
run "cat > /dev/null >> real.txt still blocked" \
  "cat > /dev/null >> real.txt" 2
# The inverse order is a genuine discard — real.txt is opened but stdout ends at
# /dev/null, so the last-target rule must still ALLOW it.
run "cat > real.txt > /dev/null is a discard (allowed)" \
  "cat > real.txt > /dev/null" 0
# Same rule on the echo/printf lane, which had the identical order-blind test.
run "echo x > /dev/null > real.txt still blocked" \
  "echo x > /dev/null > real.txt" 2
run "printf x > /dev/null > real.txt still blocked" \
  "printf x > /dev/null > real.txt" 2
# A trailing stderr redirect is not a stdout target and must not displace the
# /dev/null verdict — the fd-qualified form is excluded from the scan.
run "cat > /dev/null 2> err.log (allowed)" \
  "cat > /dev/null 2> err.log" 0

# REGRESSION FLOOR — the EXPLICIT stdout spelling is a write. `1>file` is stdout
# exactly as `>file` is, so a bare `1>` was a complete bypass of both lanes: the
# detection patterns only ever admitted the bare `>`.
run "cat 1>real.txt blocked" "cat 1>real.txt" 2
run "cat 1>>real.txt append blocked" "cat 1>>real.txt" 2
run "cat 1> real.txt spaced blocked" "cat 1> real.txt" 2
run "echo x 1>real.txt blocked" "echo x 1>real.txt" 2
run "printf x 1>real.txt blocked" "printf x 1>real.txt" 2
# …and the fd-1 discard is still a discard, on both lanes.
run "cat 1>/dev/null (allowed)" "cat 1>/dev/null" 0
run "echo x 1>/dev/null (allowed)" "echo x 1>/dev/null" 0
# Other fds must NOT be swept in by the widened operator.
run "cat 2>err.log (allowed)" "cat 2>err.log" 0
run "cat 21>err.log (allowed)" "cat 21>err.log" 0
# An fd DUPLICATION or close has no file operand and is not a write. A literal `&`
# reaches the scan (normalize_segments restores its sentinel before storing the
# segments), so the `&` exclusion in the target class is what leaves the target
# empty and the emptiness skip in cat_redirect_bypass is what passes it. The
# sentinel is excluded from that class too, so these stay allowed even if the
# restore regresses — which it silently had on bash >= 5.2.
run "cat 1>&2 fd dup (allowed)" "cat 1>&2" 0
run "cat 1>&- fd close (allowed)" "cat 1>&-" 0
run "cat >&2 bare fd dup (allowed)" "cat >&2" 0
# The fd digit needs a COMMAND BOUNDARY: `cat1` / `echo1` are unrelated binaries
# with an ordinary redirect, not `cat`/`echo` plus an fd marker.
run "cat1>file is a different binary (allowed)" "cat1>file" 0
run "echo1>file is a different binary (allowed)" "echo1>file" 0
# The zero-space `cat>file` spelling still blocks — no digit to disambiguate.
run "cat>real.txt no space blocked" "cat>real.txt" 2

# --- Redirect false-positive regression -------------------------------------
# stderr/fd redirects + /dev/null discards are NOT file-write bypasses, even
# when an `echo` appears in the same compound command.
run "echo + 2>/dev/null (allowed)" \
  "echo done; grep -i pat file 2>/dev/null" 0
run "echo + 2>&1 (allowed)" "echo hi; ls foo 2>&1 | cat" 0
run "echo stdout to /dev/null (allowed)" "echo noise >/dev/null" 0
run "echo + find 2>/dev/null pipe (allowed)" \
  "echo scan; find . -name x 2>/dev/null | head" 0
# A producer writing to a DUPLICATED fd is not a file write. These were live
# false positives on bash >= 5.2 until normalize_segments stopped restoring its
# `>&` sentinel to itself (see the `\&` note there): the surviving `\x01` matched
# _echo_file_out's target class, and the producer lane has no emptiness skip, so
# an empty effective target fell straight through to a block.
run "echo x >&2 to stderr (allowed)" "echo x >&2" 0
run "printf x >&2 to stderr (allowed)" "printf x >&2" 0
run "echo x 1>&2 explicit fd dup (allowed)" "echo x 1>&2" 0
run "echo x >&- close stdout (allowed)" "echo x >&-" 0
# …but a dup followed by a REAL file redirect still blocks: bash applies
# redirections left to right, so the file is the effective stdout target.
run "echo x >&2 then > file still blocked" "echo x >&2 > real.txt" 2
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

# --- Options of command-name modifiers before the producer (bypass regression)
# The peeled modifiers that take options — `command [-pVv]` and `exec [-cl]
# [-a name]` (bash built-in help) — leave those options between the modifier and
# the producer. They must be peeled too, else `-p`/`-a name` masks the echo/printf
# and the redirect writes a real file unblocked.
run "command -p before echo > file (blocked)" \
  'command -p echo x > real.txt' 2
run "exec -a name before echo > file (blocked)" \
  'exec -a visible echo x > real.txt' 2
run "exec -cl flags before printf > file (blocked)" \
  'exec -cl printf x > real.txt' 2
run "exec -- end-of-options before echo > file (blocked)" \
  'exec -- echo x > real.txt' 2
run "command -- end-of-options before printf > file (blocked)" \
  'command -- printf x > real.txt' 2
# No new false positive: the arg-taking `-a name` consumes its NAME word, so a
# NON-producer command after it is still allowed; a modifier-lookup with no
# redirect writes nothing.
run "exec -a name before non-producer > file (allowed)" \
  'exec -a visible ls > out.txt' 0
run "command -v lookup, no redirect (allowed)" 'command -v echo' 0
# `command -v`/`-V` DESCRIBE the argument (lookup) rather than run it, so the
# redirect captures the builtin's lookup output, not echo/printf content — the
# producer-scoped guard must NOT block these, even with a `>` redirect.
run "command -v echo describe-lookup > file (allowed)" \
  'command -v echo > out.txt' 0
run "command -V echo describe-lookup > file (allowed)" \
  'command -V echo > out.txt' 0
run "command -pv cluster with describe flag > file (allowed)" \
  'command -pv echo > out.txt' 0
run "command -v printf describe-lookup >> file append (allowed)" \
  'command -v printf >> out.txt' 0
# The describe-skip drops ONLY the lookup segment: a real producer bypass in a
# LATER segment of the same command must still block.
run "command -v describe then real echo > file in next segment (blocked)" \
  'command -v echo > a.txt; echo x > b.txt' 2
# The describe-skip fires even when the modifier sits behind an env-assignment
# prefix (`prev_mod` must survive the assignment peel into `command`).
run "env-assignment before command -v describe > file (allowed)" \
  'FOO=bar command -v echo > f' 0
# exec's `-a` consumes its NAME word even when NAME is the letter `v`; the
# describe-skip is command-only, so exec's echo producer still blocks.
run "exec -a v name then echo > file (blocked)" \
  'exec -a v echo x > f' 2
# Option peeling is scoped to command/exec: `env` keeps its bare-only floor, so an
# optioned `env` before a producer stays an accepted-floor miss (documented), not a
# partial/inconsistent catch.
run "env -i optioned before echo > file (accepted floor — allowed)" \
  'env -i echo x > real.txt' 0

# --- fd-duplication redirect before stdout redirect (bypass regression) ------
# An fd-dup redirect (`2>&1`, `>&2`) before the real stdout redirect must not let
# the `&` split cut the producer away from its `> file`. The whole simple command
# stays one segment so the trailing stdout-to-file redirect is still the echo's.
run "echo 2>&1 then > file (blocked)" 'echo x 2>&1 > real.txt' 2
run "echo >&2 then > file (blocked)" 'echo x >&2 > real.txt' 2
# The dup redirects themselves, with no stdout-to-file target, are NOT writes.
run "echo piped with 2>&1 dup (allowed)" 'echo hi 2>&1 | cat' 0
run "ls to stderr via >&2 dup (allowed)" 'ls foo >&2' 0

# --- Compound-command headers / negation before a producer (bypass regression)
# `if`/`elif`/`while`/`until` headers and `!` negation can precede the command
# word just like `do`/`then`/`else`; the producer inside them must still be seen.
run "echo > file after ! negation (blocked)" '! echo x > real.txt' 2
run "echo > file in if header (blocked)" \
  'if echo x > real.txt; then :; fi' 2
run "echo > file in while header (blocked)" \
  'while echo x > real.txt; do :; done' 2
run "echo > file in until header (blocked)" \
  'until echo x > real.txt; do :; done' 2
# No new false positive: a non-producer command word after the header is allowed.
run "non-producer in if header > file (allowed)" \
  'if grep -q x file; then ls; fi' 0

# --- Leading redirect before the producer word (bypass regression) -----------
# Bash permits redirections before the command word, so a producer can hide
# behind one. The leading redirect is peeled to expose echo/printf, while the
# redirect itself still counts as the write signal.
run "leading redirect before echo (blocked)" '> real.txt echo x' 2
run "leading redirect before printf (blocked)" '> real.txt printf x' 2
run "leading redirect glued to target before echo (blocked)" '>real.txt echo x' 2
run "leading redirect + env-assignment before echo (blocked)" \
  '> real.txt FOO=bar echo x' 2
# No new false positive: a leading INPUT redirect writes nothing, a leading
# stdout /dev/null discard is not a bypass, and a non-producer command word after
# a leading redirect is allowed.
run "leading input redirect before echo (allowed)" '< input.txt echo x' 0
run "leading /dev/null redirect before echo (allowed)" '> /dev/null echo x' 0
run "leading redirect before non-producer (allowed)" '> out.txt ls -la' 0

# --- coproc header before the producer (bypass regression) -------------------
# A bare `coproc` header can precede the producer of a simple command; it is
# peeled like the other command headers so the producer inside is still seen.
run "coproc before echo > file (blocked)" 'coproc echo x > real.txt' 2
run "coproc before printf > file (blocked)" 'coproc printf x > real.txt' 2
# No new false positive: a non-producer command word after coproc is allowed.
run "coproc before non-producer > file (allowed)" 'coproc make > log.txt' 0

# --- Escaped separators between producer and redirect (bypass regression) ----
# A backslash-escaped separator is NOT a command boundary — bash keeps `\;` `\|`
# `\&` as literal arguments and removes a `\<newline>` line continuation, all
# within the SAME simple command. The segment split must not cut the producer
# from its `> file` at an escaped separator, or the write slips through.
run "escaped semicolon then echo > file (blocked)" \
  'echo x \; > real.txt' 2
run "escaped pipe then echo > file (blocked)" \
  'echo x \| > real.txt' 2
run "escaped ampersand then echo > file (blocked)" \
  'echo x \& > real.txt' 2
ESCAPED_NEWLINE=$(printf 'echo x \\\n> real.txt')
run "escaped-newline continuation then echo > file (blocked)" \
  "$ESCAPED_NEWLINE" 2
# No new false positive: an UNescaped separator still splits, so a captured
# subprocess stdout with an unrelated trailing echo stays allowed.
run "unescaped separator, capture + echo status (allowed)" \
  'bash fetch.sh > out.json; echo done' 0

# --- Comment quote-state leak (bypass regression) ----------------------------
# strip_literals carries an open quote across physical lines. An unmatched quote
# inside a `#` comment must NOT leak a quote span onto the next line — otherwise
# the next line's real producer gets stripped away and the write slips through.
COMMENT_QUOTE_LEAK=$(printf 'true # "\necho x > real.txt')
run "unmatched quote in comment, next-line bypass (blocked)" \
  "$COMMENT_QUOTE_LEAK" 2
# Same leak reachable via an operator-preceded comment (`;#`), a word boundary too.
COMMENT_QUOTE_LEAK_SEMI=$(printf 'true;# "\necho x > real.txt')
run "unmatched quote in operator-preceded comment, next-line bypass (blocked)" \
  "$COMMENT_QUOTE_LEAK_SEMI" 2
# Discriminating: a `#` mid-word is literal, not a comment introducer, so a real
# `echo a#b > file` write must STILL block (the comment strip must not over-reach).
run "mid-word # is literal, real write still blocked" 'echo a#b > real.txt' 2
# A parameter expansion `${v#x}` carries a `#` that is not a comment either — the
# producer + redirect after it must still block.
# shellcheck disable=SC2016  # literal ${v#x} is the command under test, not for expansion
run "parameter-expansion # then echo > file (blocked)" \
  'echo "${v#x}" > real.txt' 2
# A genuine trailing comment on an allowed command stays allowed and does not
# swallow a following unrelated line via a leaked quote.
COMMENT_BENIGN=$(printf 'ls -la # list files\ngit status')
run "benign trailing comment, no leak (allowed)" "$COMMENT_BENIGN" 0

# --- Quoted redirect operands (bypass regression) ----------------------------
# strip_literals drops quoted spans so their tokens stay inert, but a quoted
# redirect TARGET is not inert prose — it is the write's destination. Dropping it
# left the segment as `echo x > ` with no surviving operand, so _echo_file_out
# (which needs a non-space target) did not match and the write slipped through.
# A quoted operand word is now kept as literal content (quote marks dropped) so
# the write signal survives; a quoted span anywhere else still drops.
# shellcheck disable=SC2016  # literal $out path is the command under test, not for expansion
run "echo > double-quoted var target (blocked)" 'echo x > "$out"' 2
run "echo > single-quoted literal target (blocked)" "echo x > 'out.txt'" 2
run "echo > double-quoted literal target (blocked)" 'echo x > "out.txt"' 2
run "echo>quoted target no space (blocked)" 'echo hi>"foo.txt"' 2
# shellcheck disable=SC2016  # literal $out path is the command under test, not for expansion
run "printf > quoted var target (blocked)" 'printf y > "$out"' 2
# shellcheck disable=SC2016  # literal $out path is the command under test, not for expansion
run "echo >> quoted target append (blocked)" 'echo x >> "$out"' 2
# Partial quoting is the common real form — a quoted segment inside an otherwise
# unquoted operand word must still count as the target.
# shellcheck disable=SC2016  # literal $dir path is the command under test, not for expansion
run "echo > partially-quoted target (blocked)" 'echo x > "$dir"/out.txt' 2
# The dropped quote marks must NOT strand the /dev/null exemption: a quoted (or
# partially-quoted) /dev/null discard is not a Write/Edit bypass and stays allowed.
run "echo > fully-quoted /dev/null (allowed)" 'echo x > "/dev/null"' 0
run "echo > partially-quoted /dev/null (allowed)" 'echo x > /dev/"null"' 0
# No new false positive: a NON-producer whose stdout is captured to a quoted data
# sink is the original false-positive report's form and must stay allowed — the
# producer is the script, not an echo.
run "script stdout to quoted sink (allowed)" \
  'bash fetch.sh 526 > "pr526.json"' 0
# A quoted span that is NOT a redirect operand (a quoted echo ARGUMENT) still
# drops — only the following real `> file` write drives the block, not the arg.
run "echo quoted arg then > quoted file (blocked)" 'echo "done" > "log.txt"' 2

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
TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
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

# --- PowerShell tool coverage ------------------------------------------------
# The guard is matched on Bash|PowerShell. PowerShell file-write forms that
# bypass the Write/Edit gate are blocked; content-producer scoping is preserved
# (a tool's own output redirect is allowed, matching the Bash producer scope).
run_pwsh() {
  local label="$1" command="$2" expected="$3" rc
  bash "$HOOK" <<<"$(pwsh_command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}
run_pwsh "PS: Set-Content (blocked)" "Set-Content -Path f.txt -Value 'x'" 2
run_pwsh "PS: Add-Content (blocked)" "Add-Content f.txt 'x'" 2
run_pwsh "PS: Out-File (blocked)" "'secret' | Out-File creds.txt" 2
run_pwsh "PS: Tee-Object (blocked)" "'x' | Tee-Object f.txt" 2
run_pwsh "PS: string > file (blocked)" "'content' > file.txt" 2
run_pwsh "PS: echo > file (blocked)" "echo hi > out.txt" 2
run_pwsh "PS: tool output > file (allowed — producer is the tool)" "git diff > out.txt" 0
run_pwsh "PS: redirect to \$null (allowed — discard)" "git log > \$null" 0
run_pwsh "PS: Set-Content mentioned in quoted arg (allowed)" "echo 'run Set-Content later'" 0
run_pwsh "PS: plain git status (allowed)" "git status" 0
# Alias + backtick-obfuscation regressions (independent security review).
bt='`'
run_pwsh "PS: ac alias (Add-Content, blocked)" "ac -Path f.txt -Value x" 2
run_pwsh "PS: tee alias (Tee-Object, blocked)" "x | tee -FilePath out.txt" 2
run_pwsh "PS: backtick-escaped Set\`-Content (blocked)" "Set${bt}-Content f.txt x" 2
# `sc` is sc.exe in PowerShell 7 (service controller), NOT Set-Content — allowed.
run_pwsh "PS: sc is sc.exe not Set-Content (allowed)" "sc query" 0
# Expanded write surface (independent security review, round 2).
run_pwsh "PS: iex opaque run (blocked)" "iex 'Set-Content f.txt x'" 2
run_pwsh "PS: New-Item -Value (blocked)" "New-Item -Path f -ItemType File -Value 'data'" 2
run_pwsh "PS: New-Item -ItemType Directory, no -Value (allowed)" "New-Item -Path d -ItemType Directory" 0
run_pwsh "PS: Export-Csv (blocked)" "\$d | Export-Csv f.csv" 2
run_pwsh "PS: Export-Clixml (blocked)" "\$d | Export-Clixml f.xml" 2
run_pwsh "PS: [IO.File]::WriteAllText (blocked)" "[IO.File]::WriteAllText('f','x')" 2
run_pwsh "PS: StreamWriter (blocked)" "(New-Object IO.StreamWriter 'f').Write('x')" 2
run_pwsh "PS: variable redirected to file (blocked)" "\$x > f.txt" 2
# Write-cmdlet alias parity (round 3 review): ni (New-Item), epcsv (Export-Csv).
run_pwsh "PS: ni -Value alias (blocked)" "ni -Path f -ItemType File -Value 'data'" 2
run_pwsh "PS: epcsv alias (Export-Csv, blocked)" "\$d | epcsv f.csv" 2
# `sc` is Set-Content in Windows PowerShell 5.1; matched only in its Set-Content
# form (a -Value/-Path parameter). sc.exe (PS 7) service calls stay allowed.
run_pwsh "PS: sc -Path -Value (5.1 Set-Content form, blocked)" "sc -Path f.txt -Value 'x'" 2
run_pwsh "PS: sc query (sc.exe service, allowed)" "sc query" 0
run_pwsh "PS: sc start service (sc.exe, allowed)" "sc start W32Time" 0
# Review round 4: producer-alias, module-qualified, grouped-producer, and
# quoted-writer-call parity.
run_pwsh "PS: write alias (Write-Output) > file (blocked)" "write secret > creds.txt" 2
run_pwsh "PS: module-qualified Set-Content (blocked)" \
  "Microsoft.PowerShell.Management\\Set-Content -Path f.txt -Value x" 2 # portability-ok: PowerShell module-qualified command string in a test fixture, not a regex/sed construct
run_pwsh "PS: parenthesized literal > file (blocked)" "('secret') > creds.txt" 2
run_pwsh "PS: parenthesized Write-Output > file (blocked)" "(Write-Output secret) > creds.txt" 2
run_pwsh "PS: parenthesized tool output > file (allowed — producer is the tool)" \
  "(git diff) > out.txt" 0
run_pwsh "PS: & 'Set-Content' quoted writer call (blocked)" \
  "& 'Set-Content' -Path f.txt -Value x" 2
run_pwsh "PS: & 'Invoke-Expression' quoted (blocked)" \
  "& 'Invoke-Expression' 'Set-Content f x'" 2
run_pwsh "PS: & quoted non-writer program path (allowed)" \
  "& 'C:\\tools\\build.exe' arg" 0 # portability-ok: Windows path string in a test fixture, not a regex/sed construct
# Review round 5: expression-valued producers and computed call targets.
run_pwsh "PS: numeric expression > file (blocked)" "36 > out.txt" 2
run_pwsh "PS: cast expression > file (blocked)" "[char]65 > out.txt" 2
run_pwsh "PS: & computed writer name (fail-closed block)" \
  "& ('Set-'+'Content') -Path f.txt -Value x" 2
# #2722: a bare computed call/dot-source with NO write indicator is not a write.
# The shape alone must not enter the fail-closed sink — same residual the git
# lane documents for `& $tool …` in has_dynamic_invocation.
run_pwsh "PS: . \$PROFILE reload (allowed — no write indicator)" \
  ". \$PROFILE" 0
run_pwsh "PS: & \$py script.py (allowed — no write indicator)" \
  "& \$py script.py" 0
run_pwsh "PS: & \$tool --version (allowed — no write indicator)" \
  "& \$tool --version" 0
run_pwsh "PS: . \$env:MY_PROFILE (allowed — no write indicator)" \
  ". \$env:MY_PROFILE" 0
run_pwsh "PS: & \$python -m unittest discover (allowed — no write indicator)" \
  "& \$python -m unittest discover" 0
# Still fail-closed when a write signal accompanies the computed variable target.
run_pwsh "PS: & \$w -Value computed writer (blocked)" \
  "& \$w -Path f.txt -Value x" 2
run_pwsh "PS: & \$w > file computed call redirect (blocked)" \
  "& \$w > f.txt" 2
# Positional Path+Value / pipeline Out-File shapes lack -Value and `>` but still write.
run_pwsh "PS: & \$w positional Path+Value (blocked)" \
  "& \$w f.txt x" 2
run_pwsh "PS: pipeline into & \$w path (blocked)" \
  "\$data | & \$w out.txt" 2

# --- #2848: grouping is not a write signal --------------------------------------
# The computed-target branch above used to gate on a blanket
# ps::has_special_constructs, so ANY grouping construct anywhere in the command
# counted as a write signal — and ordinary PowerShell that resolves an interpreter
# into a variable and then loops was reported as a "file-write cmdlet bypass" for
# a command that writes no file. Grouping is out; the shapes that gate actually
# needed to carry are named directly and pinned individually below.
# shellcheck disable=SC2016
run_pwsh "PS: grouping + bare-computed target via Get-Command (allowed — #2848)" \
  '$py = "C:/tools/python.exe"; if (-not (Test-Path $py)) { $py = (Get-Command python).Source }; & $py C:/s/run.py --flag' 0
# The previously unpinned single-factor allowance: grouping with a LITERAL target.
# shellcheck disable=SC2016
run_pwsh "PS: grouping + literal call target (allowed — single-factor pin, #2848)" \
  "foreach (\$id in @('a','b')) { & \"C:/tools/python.exe\" C:/s/run.py \$id }" 0
# Fail-OPEN guard rails: every write signal must still fire with the same grouping
# present. These four are the #2722 block-side pins re-run inside a `foreach`.
# shellcheck disable=SC2016
run_pwsh "PS: grouping + & \$w -Value (still blocked — #2848)" \
  "foreach (\$x in @('a')) { & \$w -Path f.txt -Value \$x }" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + & \$w > file (still blocked — #2848)" \
  "foreach (\$x in @('a')) { & \$w > f.txt }" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + & \$w positional Path+Value (still blocked — #2848)" \
  "foreach (\$x in @('a')) { & \$w f.txt \$x }" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + pipeline into & \$w path (still blocked — #2848)" \
  "foreach (\$x in @('a')) { \$x | & \$w out.txt }" 2
# shellcheck disable=SC2016
run_pwsh "PS: grouping + subexpression writer target (still blocked — #2848)" \
  "foreach (\$x in @('a')) { & ('Set-'+'Content') f.txt \$x }" 2
# ISOLATING pin for the subexpression arm: ONE positional, no grouping, no
# redirect, no -Value, and the writer name is split across two quoted fragments
# so the quote-blanked cmdlet scan below cannot see it either. Every other probe
# in this branch is therefore silent, and only ps::call_target_is_bare_subexpression
# can carry this row. Without it the row above passes on the positional signal and
# the new arm would be untested.
# shellcheck disable=SC2016
run_pwsh "PS: subexpression writer target, single positional (blocked — isolates the arm, #2848)" \
  "& ('Set-'+'Content') f.txt" 2
# A NESTED computed call inside a script block. The outer target's first token is
# a flag, so the outer site contributes zero positionals; only measuring EVERY
# `& \$var` site in the command reaches the inner write (#2848). While the gate
# was a blanket ps::has_special_constructs the script block alone carried this,
# which is why the first-site-only measurement was invisible.
# shellcheck disable=SC2016
run_pwsh "PS: nested computed write inside a script block (blocked — #2848)" \
  "& \$ic -ScriptBlock { & \$w f.txt \$x }" 2
# The three shapes that replaced the blanket grouping test, each pinned on its own
# so a later pass cannot drop one silently. The SPLAT rows matter most: `& $w @p`
# supplies -Path/-Value from a hashtable none of the probes above can see. Before
# #2848 it was caught only by accident, and only when the hashtable literal sat in
# the same command; naming it closes the pre-built-`$p` form too, so replacing the
# grouping test is not a net loosening of this branch.
# shellcheck disable=SC2016
run_pwsh "PS: splat into a computed writer, hashtable literal inline (blocked)" \
  "\$p = @{Path='f.txt';Value='x'}; & \$w @p" 2
# shellcheck disable=SC2016
run_pwsh "PS: splat into a computed writer, hashtable built earlier (blocked — #2848)" \
  "& \$w @p" 2
# The splat is scoped to its OWN call's operands, not matched anywhere in the
# command (#2848 review). A whole-command `@name` scan made an unrelated splat
# the write signal for a call it has nothing to do with — the same
# signal-detected-anywhere over-block this issue closes, one shape narrower.
# Both rows are the reviewers' verbatim reproductions; the second is the control
# they paired it with, allowed before and after, which is what makes the first
# row's block attributable to the splat scope rather than to the call itself.
# shellcheck disable=SC2016
run_pwsh "PS: unrelated splat in an earlier statement (allowed — #2848 review)" \
  'Write-Output @args; & $py script.py' 0
# shellcheck disable=SC2016
run_pwsh "PS: same command without the splat (allowed — control for the row above)" \
  'Write-Output; & $py script.py' 0
# shellcheck disable=SC2016
run_pwsh "PS: unrelated Copy-Item splat beside a computed call (allowed — #2848 review)" \
  'Copy-Item @copyParams; & $tool status' 0
# The scoped probe deliberately does NOT stop at the first dash-flag the way its
# positional sibling does: a splat supplies parameters wherever it sits, so this
# row is the same write hypothesis as `& $w @p` and must keep blocking. It is the
# one place the two probes diverge, so it is pinned on its own.
# shellcheck disable=SC2016
run_pwsh "PS: splat after a flag on the same computed call (blocked — #2848 review)" \
  "& \$w -Encoding utf8 @p" 2
# A splat reached only by measuring EVERY call site: the outer target's operands
# hold no splat, the nested one's do.
# shellcheck disable=SC2016
run_pwsh "PS: splat on a nested computed call inside a script block (blocked — #2848 review)" \
  "& \$ic -ScriptBlock { & \$w @p }" 2
# ...and the converse: a splat inside a script block operand is NOT claimed by the
# enclosing call. Only the nested call site owns it, and there is no nested call
# here, so nothing writes. This is what keeps the per-call-site scoping honest in
# both directions rather than trading one over-block for another.
# shellcheck disable=SC2016
run_pwsh "PS: splat inside a script block with no nested computed call (allowed — #2848 review)" \
  "& \$tool -ScriptBlock { Write-Output @args }" 0
# BRACED CALL TARGETS. `${env:w}` and `$env:w` are the SAME reference
# (about_Variables; `${env:t} -eq $env:t` is True), and the gate predicate
# ps::call_target_is_bare_computed admits both because it only looks for the `$`.
# When only the bare spelling was recognized by the measuring probes, a braced
# target entered the computed-target gate and then matched no call site at all —
# every arm stayed silent and the command fell through ALLOWED, while the
# identical bare spelling blocked. Each row is paired with its bare twin so the
# two spellings are pinned to the same verdict and cannot drift apart again.
# shellcheck disable=SC2016
run_pwsh "PS: braced call target, positional Path+Value (blocked — #2848 verifier)" \
  '& ${env:writer} f.txt x' 2
# shellcheck disable=SC2016
run_pwsh "PS: bare twin of the row above (blocked — same reference)" \
  "& \$env:writer f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: braced call target, splat (blocked — #2848 verifier)" \
  '& ${env:writer} @p' 2
# shellcheck disable=SC2016
run_pwsh "PS: braced dot-source target, splat (blocked — #2848 verifier)" \
  '. ${env:w} @p' 2
# shellcheck disable=SC2016
run_pwsh "PS: braced script-scope call target (blocked — #2848 verifier)" \
  '& ${script:w} f.txt x' 2
# A braced name containing a SPACE — legal PowerShell, and the shape a bare-name
# character class can never reach, so it isolates the braced alternative.
# shellcheck disable=SC2016
run_pwsh "PS: braced call target whose name contains a space (blocked — #2848 verifier)" \
  '& ${my writer} f.txt x' 2
# The braced target must not become a write signal on its own: an ordinary
# interpreter call spelled with braces stays allowed, exactly like its bare twin.
# shellcheck disable=SC2016
run_pwsh "PS: braced call target, single positional (allowed — #2848 verifier)" \
  '& ${env:py} script.py' 0
# ESCAPED CLOSERS inside a braced name. `${my`}writer}` names the variable
# `my}writer` (about_Variables). The library deletes backticks to recover an
# obfuscated cmdlet name, which turned that text into `${my}writer}` — genuinely
# indistinguishable from `${my}` followed by a literal `writer}`, so the braced
# scanner's `[^}]*` stopped at the injected brace, the whitespace boundary failed,
# and the call site vanished: both measuring probes returned false and the gate
# fell through ALLOWED. The escape is now consumed BEFORE the deletion
# (ps::fold_escaped_brace_closers), and the target token may carry non-space text
# glued after its closing brace. Blocked pre-0.28.33; these pin the recovery.
# shellcheck disable=SC2016
run_pwsh "PS: escaped closer in a braced call target, positional Path+Value (blocked — #2908 review)" \
  '& ${my`}writer} f.txt x' 2
# shellcheck disable=SC2016
run_pwsh "PS: escaped closer in a braced call target, splat (blocked — #2908 review)" \
  '& ${my`}writer} @p' 2
# shellcheck disable=SC2016
run_pwsh "PS: escaped closer in a braced dot-source target, splat (blocked — #2908 review)" \
  '. ${my`}writer} @p' 2
# TWO escaped closers in one name — a single-pass scanner that stops after the
# first escape would lose the second and re-open the same hole.
# shellcheck disable=SC2016
run_pwsh "PS: two escaped closers in one braced name (blocked — #2908 review)" \
  '& ${my`}w`}x} f.txt x' 2
# An escaped BACKTICK followed by a REAL closer: the name is `my``, the brace
# terminates it, and `writer}` is glued to the target token. The escaped backtick
# must not lend its second backtick to the brace, and the glued text must not make
# the call site unmatchable.
# shellcheck disable=SC2016
run_pwsh "PS: escaped backtick then a real closer, glued operand text (blocked — #2908 review)" \
  '& ${my``}writer} f.txt x' 2
# The same glue with no escape at all — `& ${env:w}riter` concatenates.
# shellcheck disable=SC2016
run_pwsh "PS: braced call target with glued trailing text (blocked — #2908 review)" \
  '& ${env:w}riter f.txt x' 2
# An escaped OPENING brace needs no special handling: deleting its backtick leaves
# `${my{writer}`, which `[^}]*` matches and the real closer still terminates.
# shellcheck disable=SC2016
run_pwsh "PS: escaped opening brace in a braced call target (blocked — #2908 review)" \
  '& ${my`{writer} f.txt x' 2
# The allowed side of the escaped-closer shape: consuming the escape must not turn
# an ordinary one-positional interpreter call into a write signal.
# shellcheck disable=SC2016
run_pwsh "PS: escaped closer in a braced call target, single positional (allowed — #2908 review)" \
  '& ${my`}py} script.py' 0
# DOLLAR-SPELLED SUBEXPRESSION CALL TARGETS. `$( … )` and `( … )` are the same
# construct — each evaluates an expression into the command name — so they must
# reach the same verdict. Recognizing only the paren spelling let `& $( … )`
# ENTER the computed-target gate (ps::call_target_is_bare_computed matches
# `[.&][[:space:]]*[$(]`, so the `$` admits it) and then match no call site in
# any measuring probe: both the positional and the splat probe require a `$name`
# or `${name}` target, and `$(` is neither. Every arm stayed silent and the
# command fell through ALLOWED, so `& $($w) f.txt x` — a working
# Set-Content Path+Value — was waved past while `& ($w) f.txt x` blocked
# (#2924). Same "gate admits, probes cannot see" mechanism as the braced
# spelling above. Each row is PAIRED with its paren twin so the two spellings
# are pinned to one verdict and cannot drift apart again.
# shellcheck disable=SC2016
run_pwsh "PS: \$() call target, positional Path+Value (blocked — #2924)" \
  "& \$(\$w) f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: paren twin of the row above (blocked — same construct)" \
  "& (\$w) f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: \$() call target, splat (blocked — #2924)" \
  "& \$(\$w) @p" 2
# shellcheck disable=SC2016
run_pwsh "PS: paren twin of the splat row above (blocked — same construct)" \
  "& (\$w) @p" 2
# shellcheck disable=SC2016
run_pwsh "PS: \$() dot-source target (blocked — #2924)" \
  ". \$(\$w) f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: paren twin of the dot-source row above (blocked — same construct)" \
  ". (\$w) f.txt x" 2
# No space between the call operator and the subexpression, and extra space —
# the operator prefix already allows both, so these pin that widening the target
# token did not disturb it.
# shellcheck disable=SC2016
run_pwsh "PS: \$() call target glued to the call operator (blocked — #2924)" \
  "&\$(\$w) f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: \$() call target after extra whitespace (blocked — #2924)" \
  "&   \$(\$w) f.txt x" 2
# Nested and member-access spellings of the same computed target.
# shellcheck disable=SC2016
run_pwsh "PS: nested \$(\$()) call target (blocked — #2924)" \
  "& \$(\$(\$w)) f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: \$() call target wrapping a call operator (blocked — #2924)" \
  "& \$(& \$w) f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: \$().Member call target (blocked — #2924)" \
  "& \$(Get-Command x).Source f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: paren twin of the member row above (blocked — same construct)" \
  "& (Get-Command x).Source f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: \$() call target holding a braced reference (blocked — #2924)" \
  "& \$(\${env:w}) f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: \$() call target with a scoped variable (blocked — #2924)" \
  "& \$(\$script:w) f.txt x" 2
# A SUBEXPRESSION target is refused BY SHAPE — regardless of its operands — so a
# single-positional interpreter call spelled this way blocks too. That is not the
# grouping-as-write-signal over-block #2848 removed: #2848 dropped grouping
# ANYWHERE ELSE in the command as a signal and deliberately KEPT the
# target-is-subexpression arm, which is why the paren twin below has always
# blocked and still does. The two spellings agreeing is the invariant; allowing
# the dollar one would be a new instance of the same defect one construct over.
# shellcheck disable=SC2016
run_pwsh "PS: \$() call target, single positional (blocked by shape — #2924)" \
  "& \$(\$py) script.py" 2
# shellcheck disable=SC2016
run_pwsh "PS: paren twin of the row above (blocked by shape, unchanged)" \
  "& (\$py) script.py" 2
# The literal-assembly shape the subexpression arm exists for, in both spellings.
# It is also the tripwire for the escaped `\$` in the predicate: an unescaped
# `\$?` would expand to the last exit status and silently stop matching the paren
# spelling, a fail-OPEN on exactly this row.
# shellcheck disable=SC2016
run_pwsh "PS: assembled writer name in parens (blocked — pre-existing)" \
  "& ('Set-'+'Content') f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: assembled writer name in a \$() subexpression (blocked — #2924)" \
  "& \$('Set-'+'Content') f.txt x" 2
# DECOY BRACES. Scoping a call's operands by truncating at the first `}` assumed
# no `}` can appear inside the call's OWN operands before a token of interest —
# false for `${scope:name}`, a `{…}` script block, and a `@{…}` hashtable literal.
# Each row below is a working write whose real splat sits AFTER such an operand;
# under a first-`}` truncation the splat was cut away and the command was allowed,
# a full bypass of this hook. The operand region is bracket-depth aware instead.
# shellcheck disable=SC2016
run_pwsh "PS: \${scope:name} operand before a splat (blocked — #2848 review)" \
  "& \$w \${script:Path} @Body" 2
# shellcheck disable=SC2016
run_pwsh "PS: empty script block before a splat (blocked — #2848 review)" \
  "& \$w {} @Body" 2
# shellcheck disable=SC2016
run_pwsh "PS: hashtable literal before a splat (blocked — #2848 review)" \
  "& \$w @{a=1} @Body" 2
# The same decoy blinded the POSITIONAL probe, which shares the operand region:
# `${script:Path}` is one computed operand, `f.txt` and `x` are the Path+Value pair.
# shellcheck disable=SC2016
run_pwsh "PS: \${scope:name} operand before positional Path+Value (blocked — #2848 review)" \
  "& \$w \${script:Path} f.txt x" 2
# A bracket pair INSIDE a single token (an index) is balanced, so the token stays
# one operand and is still a visible literal — the Path+Value shape holds.
# shellcheck disable=SC2016
run_pwsh "PS: indexed literal path beside a positional (blocked — #2848 review)" \
  "& \$w logs[0].txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: stop-parsing token after a computed target (blocked)" \
  "& \$w --% f.txt x" 2
# The positional signal CLASSIFIES operands rather than merely counting them
# (#2848): a parenthesized subexpression is one operand however many words it
# spans, and the two-positional arm fires only when at least one operand is a
# visible literal. `& $py $script (Join-Path …)` — every operand computed — is
# the ordinary interpreter-over-computed-paths call the issue de-blocks, with or
# without the enclosing foreach; `& $py $script out.jsonl` still blocks, because
# a visible literal beside another positional is exactly the Path+Value shape
# (`& $w f.txt x`) the #2722 signal exists for. The pins sit together so the
# next reader can see the line is drawn at a visible-literal operand, not at
# grouping.
# shellcheck disable=SC2016
run_pwsh "PS: bare-computed target, literal beside a positional (blocked — #2722 signal)" \
  "& \$py \$script out.jsonl" 2
# shellcheck disable=SC2016
run_pwsh "PS: bare-computed target, all operands computed (allowed — #2848)" \
  "& \$py \$script (Join-Path \$dir \"\$id.jsonl\")" 0
# shellcheck disable=SC2016
run_pwsh "PS: grouping + bare-computed target inside foreach (allowed — #2848)" \
  "\$ids = @('a','b'); foreach (\$id in \$ids) { & \$py \$script (Join-Path \$dir \"\$id.jsonl\") }" 0
# The concession the visible-literal line makes, pinned so it is deliberate: a
# writer name, path, AND value all staged into variables inside one command
# string is a deliberately evasive shape of the same class as the `node -e`
# writes this hook's scope note already excludes — while a pipeline into the
# call keeps failing closed on ANY operand, computed or not, because the content
# demonstrably arrives via `|`.
# shellcheck disable=SC2016
run_pwsh "PS: all-variable staged positional call (allowed — outside scope, #2848)" \
  "& \$w \$path \$value" 0
# shellcheck disable=SC2016
run_pwsh "PS: pipeline into & \$w computed operand (still blocked — #2848)" \
  "\$data | & \$w \$out" 2

# Quoted `>` / `-value` text must not trip the write-signal probes.
run_pwsh "PS: & \$tool quoted greater-than message (allowed)" \
  "& \$tool -Message \"CPU > 90%\"" 0
run_pwsh "PS: & \$tool quoted -value substring (allowed)" \
  "& \$tool -Message \"please -value this\"" 0
# fd-dup merge is plumbing, not a file write — must not trip the redirect gate.
run_pwsh "PS: & \$tool 2>&1 stream merge (allowed — no file write)" \
  "& \$tool 2>&1" 0
run_pwsh "PS: spaced numeric is a value write, tool redirect still allowed" \
  "git diff 2> err.txt" 0
# Review round 6: non-success stream producers and separator-adjacent calls.
run_pwsh "PS: Write-Error 2> file (blocked)" "Write-Error secret 2> creds.txt" 2
run_pwsh "PS: Write-Warning 3> file (blocked)" "Write-Warning secret 3> creds.txt" 2
run_pwsh "PS: semicolon-adjacent & 'Set-Content' (blocked)" \
  "Write-Host ok;& 'Set-Content' -Path f.txt -Value x" 2
run_pwsh "PS: quoted '@' not a here-string opener (write line not swallowed)" \
  "$(printf "Write-Output '@'\nSet-Content -Path f.txt -Value x\n'@'")" 2

# Review round 7: fd-dup merge redirects are plumbing, not producers; invoked
# script blocks are unwrapped like parenthesized producers.
run_pwsh "PS: tool capture with 2>&1 > file (allowed)" "git status 2>&1 > out.txt" 0
run_pwsh "PS: Get-ChildItem 2>&1 > file (allowed)" "Get-ChildItem 2>&1 > out.txt" 0
run_pwsh "PS: echo with 2>&1 > file (still a producer, blocked)" "echo x 2>&1 > f.txt" 2
run_pwsh "PS: & { Write-Output secret } > file (blocked)" \
  "& { Write-Output secret } > creds.txt" 2
run_pwsh "PS: & { git diff } > file (tool producer, allowed)" \
  "& { git diff } > out.txt" 0

# --- fd-dup merge must not hide a computed writer's operands (#2927) ---------
# The `&` inside `2>&1` sits at bracket depth ZERO, and ps::call_site_operand_region
# ends a call's operand region at a depth-zero `;` `|` `&`. So the region of
# `& $w 2>&1 f.txt x` was truncated to `" 2>"`, both measuring probes went silent,
# and a working `Set-Content <path> <value>` — verified as a real write under
# pwsh — fell through ALLOWED. The strip that already existed for the redirect
# probe now runs before EVERY probe in the branch, so the remaining `&`
# characters really are separators. Each row is a shape the truncation hid.
# shellcheck disable=SC2016
run_pwsh "PS: fd-dup before positional Path+Value (blocked — #2927)" \
  "& \$w 2>&1 f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: fd-dup before a splat (blocked — #2927)" \
  "& \$w 2>&1 @p" 2
# shellcheck disable=SC2016
run_pwsh "PS: fd-dup with an env: target (blocked — #2927)" \
  "& \$env:w 2>&1 f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: fd-dup on a piped computed call (blocked — #2927)" \
  "'x' | & \$w 2>&1 f.txt" 2
# The walk measures EVERY call site, so the fd-dup on a NON-leftmost one is
# reached too — an earlier bare `& $w` must not consume the scan.
# shellcheck disable=SC2016
run_pwsh "PS: fd-dup on a non-leftmost call site (blocked — #2927)" \
  "& \$w; & \$w2 2>&1 f.txt x" 2
# The deliberately ACCEPTED behavior change: once the merge is stripped, one
# literal positional before it and one after it read as the Path+Value pair. That
# is consistent with `& $py script.py arg`, which already blocked, so the class is
# narrow — it needs BOTH sides of the merge to carry a positional.
# shellcheck disable=SC2016
run_pwsh "PS: positional on each side of an fd-dup (blocked — accepted #2927 change)" \
  "& \$py a.py 2>&1 b.txt" 2
# The protective half of the strip, which the fix must not undo: a merge with no
# operands after it is plumbing, and a tool's own capture-and-redirect is a tool
# producer, not a content author.
# shellcheck disable=SC2016
run_pwsh "PS: computed call with a bare fd-dup (still allowed — #2927)" \
  "& \$tool 2>&1" 0
# shellcheck disable=SC2016
run_pwsh "PS: computed call, flag-first, trailing fd-dup (still allowed — #2927)" \
  "& \$py -m pip install x 2>&1" 0

# --- call-site boundaries PowerShell's tokenizer honors (#2928) -------------
# The separator classes were derived from bash character classes rather than from
# PowerShell's tokenizer, so any spelling PowerShell separates and bash does not
# made the call site vanish from every measuring probe — a fail-OPEN. Two members
# were proven with real writes under pwsh; both are pinned here.
#
# The Unicode separators are built from BYTE ESCAPES, never pasted as literal
# characters. A raw U+00A0 in this file is one formatter or `.gitattributes` rule
# away from becoming a plain space, at which point the row degrades to
# `& $w f.txt x` — which blocks anyway, so the case would pass while pinning
# nothing.
# U+00A0 NO-BREAK SPACE and U+2003 EM SPACE.
PS_NBSP=$'\xc2\xa0'
PS_EMSP=$'\xe2\x80\x83'
# Gap 1: `=` was absent from the separator class, so an assignment with no space
# before the call operator never entered the gate — while the spaced form did.
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment before a computed writer call (blocked — #2928)" \
  "\$a=& \$w f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment, spaced contrast (blocked — pre-existing)" \
  "\$a = & \$w f.txt x" 2
# The `=` widening has to reach the QUOTED-writer and SUBEXPRESSION-target
# predicates too, not just the bare-variable one: entry and measurement moving
# apart is what produced #2922 and #2924.
run_pwsh "PS: unspaced assignment before a quoted writer name (blocked — #2928)" \
  "\$a=& 'Set-Content' f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment before a subexpression target (blocked — #2928)" \
  "\$a=& (\$w) f.txt x" 2
# Gap 2: PowerShell's tokenizer treats U+00A0 as token-separating whitespace and
# bash's `[[:space:]]` does not, so the whole call site disappeared. Normalized at
# intake instead of widened into the classes — under a single-byte locale the two
# bytes of U+00A0 inside a bracket expression become independent members, and
# `\xa0` is the second byte of `à`, which would over-block ordinary accented
# paths.
# shellcheck disable=SC2016
run_pwsh "PS: U+00A0 between a computed target and its positionals (blocked — #2928)" \
  "& \$w${PS_NBSP}f.txt x" 2
# shellcheck disable=SC2016
run_pwsh "PS: U+00A0 before a splat (blocked — #2928)" \
  "& \$w${PS_NBSP}@p" 2
# U+2003 is the same defect, not a separate one: the whole measured set of
# PowerShell-separating Unicode spaces is normalized, so a second member proves
# the class moved rather than one character.
# shellcheck disable=SC2016
run_pwsh "PS: U+2003 between a computed target and its positionals (blocked — #2928)" \
  "& \$w${PS_EMSP}f.txt x" 2
# Both gaps at once.
# shellcheck disable=SC2016
run_pwsh "PS: unspaced assignment plus U+00A0 (blocked — #2928)" \
  "\$a=& \$w${PS_NBSP}f.txt x" 2
# THE OVER-BLOCK GUARD ON THE NORMALIZATION. If the U+00A0 bytes had gone into a
# character class, `\xa0` would match on its own under a single-byte locale and
# split an accented literal into two operands — reopening #2848 one shape
# narrower. These stay allowed.
# shellcheck disable=SC2016
run_pwsh "PS: accented single positional after a computed target (allowed — #2928 guard)" \
  "& \$py café.py" 0
# shellcheck disable=SC2016
run_pwsh "PS: accented flag operand after a computed target (allowed — #2928 guard)" \
  "& \$py -m café" 0
# shellcheck disable=SC2016
run_pwsh "PS: accented single positional, writer-shaped target (allowed — #2928 guard)" \
  "& \$w café.txt" 0
# U+200B and U+FEFF are deliberately NOT normalized. They measured as ZERO-width
# under `[System.Management.Automation.Language.Parser]::ParseInput` — the token
# does not split, so the call target never resolves and there is no write to hide.
# shellcheck disable=SC2016
run_pwsh "PS: U+200B does not separate tokens (allowed — #2928 scope)" \
  "& \$w"$'\xe2\x80\x8b'"f.txt x" 0

# Interpreter-producer writes under the PowerShell tool: PowerShell is not
# faithfully bash-tokenizable, so this lane follows the SINK DOCTRINE — block on
# the mangle-resistant co-occurrence of a raw write indicator (_py_write) AND a
# python3 token + `-c` inline-code flag (ps::might_write_via_python3), rather than a
# precise `python3 -c` scan that review rounds defeated. `-c` is REQUIRED so script
# and module runs stay allowed; MENTIONS over-block (the accepted fail-closed cost).
run_pwsh "PS: python3 -c open write (blocked)" \
  "python3 -c \"open('x','w').write('a')\"" 2
run_pwsh "PS: python3 -c pathlib write_text (blocked)" \
  "python3 -c \"import pathlib; pathlib.Path('x').write_text('a')\"" 2
# No write indicator (read-only os.path.normpath) — allowed even with python3 -c.
run_pwsh "PS: python3 -c read-only os.path.normpath (allowed)" \
  "python3 -c \"import os; print(os.path.normpath('a/b'))\"" 0
# `-c` REQUIRED: a script run / module run that merely touches an `open(`-like path
# is NOT an inline-code write — stays allowed (spares legitimate python3 invocations).
run_pwsh "PS: python3 script run, open( in an arg, no -c (allowed)" \
  "python3 build.py --path \"open('x','w')\"" 0
run_pwsh "PS: python3 -m module run, open( in an arg, no -c (allowed)" \
  "python3 -m mytool \"open('x','w')\"" 0
# here-string mention stays inert (blanked before the probe, like the git lane).
# Spelled with a WRITE MODE so the here-string blanking is what makes this
# allowed — a bare `open(` would now be allowed for the unrelated reason that it
# is no longer a write indicator.
run_pwsh "PS: here-string mentions python3 -c open write (allowed)" \
  "$(printf '@%s\npython3 -c open(f,"w")\n%s@\nWrite-Output ok' "'" "'")" 0
# ACCEPTED OVER-BLOCK (fail-closed): a MENTION of python3 … -c + a write indicator in
# prose, a line comment, or a quoted string now blocks — the guard cannot prove a
# non-tokenizable PowerShell command is a mere mention. The mentioned write is
# spelled with a WRITE MODE, because a bare `open(` is no longer a write
# indicator in either lane (see the open() write-mode discrimination above).
run_pwsh "PS: prose mention of python3 -c open write now over-blocks (blocked)" \
  "Write-Output 'run python3 -c open(f,\"w\") later'" 2
run_pwsh "PS: line-comment mention of python3 -c open write now over-blocks (blocked)" \
  "Write-Output ok # python3 -c open(f,'w')" 2
run_pwsh "PS: quoted &{python3 -c open( write string now over-blocks (blocked)" \
  "Write-Output '&{python3 -c open(f,\"w\")}'" 2
# The same three MENTION shapes carrying only a read-mode open are no longer
# write indicators at all, so they stay allowed — this is the fix, not a hole.
run_pwsh "PS: prose mention of a read-only python3 -c open (allowed)" \
  "Write-Output 'run python3 -c open(f) later'" 0
# Quoted / path-qualified / brace-glued / backtick-obfuscated python3 with -c: all
# caught by the token+`-c` probe (quote-intact, backtick-recovered).
run_pwsh "PS: & 'python3' -c open write (blocked)" \
  "& 'python3' -c \"open('x','w').write('a')\"" 2
run_pwsh "PS: & \"python3\" -c open write (blocked)" \
  "& \"python3\" -c \"open('x','w').write('a')\"" 2
run_pwsh "PS: backtick-continuation python3 -c open (blocked)" \
  "$(printf 'python3 `\n-c "open('"'"'x'"'"','"'"'w'"'"').write('"'"'a'"'"')"')" 2
run_pwsh "PS: & 'C:\\...\\python3.exe' -c open write (blocked)" \
  "& 'C:\\Python313\\python3.exe' -c \"open('x','w').write('a')\"" 2
run_pwsh "PS: bare C:\\...\\python3.exe -c open write (blocked)" \
  "C:\\Python313\\python3.exe -c \"open('x','w').write('a')\"" 2
run_pwsh "PS: compact &{python3 -c} open write (blocked)" \
  "&{python3 -c \"open('x','w').write('a')\"}" 2
run_pwsh "PS: spaced & {python3 -c} open write (blocked)" \
  "& {python3 -c \"open('x','w').write('a')\"}" 2
run_pwsh "PS: &{'python3' -c} quoted-in-block open write (blocked)" \
  "&{'python3' -c \"open('x','w').write('a')\"}" 2
# Block comment as decoy + real invocation after it: token+`-c` still fires.
run_pwsh "PS: block-comment decoy then python3 -c open write (blocked)" \
  "$(printf '<# note #> python3 -c "open('"'"'x'"'"','"'"'w'"'"').write('"'"'a'"'"')"')" 2
# Arg-splitting: `-c` hidden in -ArgumentList is still a `-c` token (quote-bounded).
run_pwsh "PS: Start-Process python3 -ArgumentList '-c',open (blocked)" \
  "Start-Process python3 -ArgumentList '-c','open(\"x\",\"w\").write(\"a\")'" 2
# Computed `-c`: PowerShell evaluates expression-valued arguments before launching,
# so `('-'+'c')` builds the flag with no literal `-c` token. A python3 write whose
# args carry a non-tokenizable subexpression construct (`(…)`, via
# ps::has_special_constructs on the quote-blanked text) cannot be ruled out — fail
# closed (sink doctrine), the same construct class the git lane refuses to parse.
run_pwsh "PS: python3 ('-'+'c') computed flag open write (blocked)" \
  "python3 ('-'+'c') \"open('x','w').write('a')\"" 2
run_pwsh "PS: Start-Process -ArgumentList ('-'+'c') computed (blocked)" \
  "Start-Process python3 -ArgumentList ('-'+'c'),'open(\"x\",\"w\").write(\"a\")'" 2
# Computed launcher TARGET: `Start-Process -FilePath ('py'+'thon3')` hides the
# interpreter name itself, so the literal python3-token test cannot see it. A
# launcher with a computed program arg could be python3 — fail closed (mirrors
# might_invoke_git). A LITERAL non-python launcher target stays allowed.
run_pwsh "PS: Start-Process -FilePath ('py'+'thon3') computed target (blocked)" \
  "Start-Process -FilePath ('py'+'thon3') -ArgumentList '-c','open(\"x\",\"w\").write(\"a\")'" 2
# Colon-bound parameter binding (`-FilePath:$p`) is the same computed target as the
# whitespace-separated form — both must fail closed.
run_pwsh "PS: Start-Process -FilePath:\$p colon-bound computed target (blocked)" \
  "\$p = 'py'+'thon3'; Start-Process -FilePath:\$p -ArgumentList '-c','open(\"x\",\"w\").write(\"a\")'" 2
# Options before the computed target: any launcher + an unquoted computed construct
# fails closed regardless of how many options precede -FilePath.
run_pwsh "PS: Start-Process -NoNewWindow -FilePath \$exe computed target (blocked)" \
  "\$exe = 'py'+'thon3'; Start-Process -NoNewWindow -FilePath \$exe -ArgumentList '-c','open(\"x\",\"w\").write(\"a\")'" 2
run_pwsh "PS: Start-Process notepad (literal non-python launcher, allowed)" \
  "Start-Process notepad -ArgumentList '-c','open(\"x\",\"w\")'" 0
# `-c` concatenated with a variable/subexpression: PowerShell joins the adjacent
# expansion into one `-c<source>` arg, so `python3 -c$code` has no whitespace/quote
# after `-c`. Fail closed. A longer literal flag (`-config`) is NOT `-c` + code.
run_pwsh "PS: python3 -c\$code concatenated computed flag (blocked)" \
  "\$code = 'import pathlib; pathlib.Path(\"x\").write_text(\"a\")'; python3 -c\$code" 2
run_pwsh "PS: python3 -config longer flag, pathlib in arg (allowed)" \
  "python3 -config \"pathlib.Path\"" 0
# A non-python quoted program with a write indicator stays ALLOWED — no python3
# token, so the co-occurrence probe does not fire (write_bypass allows quoted progs).
run_pwsh "PS: & 'C:\\...\\app.exe' with open mention (allowed)" \
  "& 'C:\\Program Files\\app.exe' -c \"print open(\"" 0
# Call operator with a DOUBLE-QUOTED interpolated target resolves a computed
# interpreter — fail closed. A SINGLE-quoted target does not interpolate (literal
# name), so it stays allowed via write_bypass's arbitrary-quoted-program residual.
run_pwsh "PS: & \"\$env:PYTHON_BIN\" -c interpolated target (blocked)" \
  "& \"\$env:PYTHON_BIN\" -c \"open('x','w').write('a')\"" 2
run_pwsh "PS: & '\$x' single-quoted literal target (allowed)" \
  "& '\$x' -c \"print open(\"" 0

# Review round 8: module-qualified producer heads.
run_pwsh "PS: module-qualified Write-Output > file (blocked)" \
  "Microsoft.PowerShell.Utility\\Write-Output secret > f.txt" 2 # portability-ok: PowerShell module-qualified command string in a test fixture, not a regex/sed construct
run_pwsh "PS: module-qualified Write-Error 2> file (blocked)" \
  "Microsoft.PowerShell.Utility\\Write-Error secret 2> f.txt" 2 # portability-ok: PowerShell module-qualified command string in a test fixture, not a regex/sed construct

# The block message is shell-agnostic (no 'Bash' assumption).
psout=$(bash "$HOOK" <<<"$(pwsh_command_json "Set-Content f.txt 'x'")" 2>&1)
assert_contains "PS write block names Write/Edit" "$psout" "Write or Edit tool"
assert_absent "PS write block message is shell-agnostic" "$psout" "Bash file-write"
assert_contains "PS write block names kill switch" "$psout" "block_hook_bypass_enabled"
assert_contains "PS write block names isolated Write/Edit refusal" "$psout" "main checkout"
assert_contains "PS write block marks kill switch operator-only" "$psout" "not actionable by the blocked agent"
assert_contains "PS write block warns kill switch is user-scoped" "$psout" "user-scoped"
assert_contains "PS write block warns kill switch persists across repositories" "$psout" "every repository"
assert_contains "PS write block tells operator to re-enable kill switch" "$psout" "re-enable it"

# --- Enforcement-scope disclosure -------------------------------------------
# The message asserted "use Write or Edit instead" with no scope, so it read as
# "shell file writes are blocked" when the guard is deliberately producer-scoped
# over one command string. Both lanes must carry the scope, and the behaviour
# the scope describes is pinned below it so message and reality move together.
scopeout=$(bash "$HOOK" <<<"$(command_json "printf 'x' > out.log")" 2>&1)
assert_contains "bash block names kill switch" "$scopeout" "block_hook_bypass_enabled"
assert_contains "bash block names isolated Write/Edit refusal" "$scopeout" "main checkout"
assert_contains "bash block marks kill switch operator-only" "$scopeout" \
  "not actionable by the blocked agent"
assert_contains "bash block warns kill switch is user-scoped" "$scopeout" "user-scoped"
assert_contains "bash block warns kill switch persists across repositories" "$scopeout" \
  "every repository"
assert_contains "bash block tells operator to re-enable kill switch" "$scopeout" "re-enable it"
assert_contains "bash block states its scope" "$scopeout" \
  "only this command string is inspected"
assert_contains "bash block names the invoked-script gap" "$scopeout" \
  "inside an invoked script file"
# The note states the ENFORCED surface, so it is pinned at the shipped width, not
# at a remembered one. #2217 widened the python lane past the literal `python3 -c`
# and this assertion went on pinning the obsolete claim — the assertion is what
# should have caught the drift, so it now names both the family and the stdin form.
assert_contains "bash block names the interpreter family it covers" "$scopeout" \
  "python/python3/py/pypy with -c"
assert_contains "bash block names the stdin form it covers" "$scopeout" \
  "python3 - <<PY"
assert_contains "bash block names the no-dash stdin residual" "$scopeout" \
  "python3 <<PY"
assert_contains "bash block still limits interpreter coverage" "$scopeout" "only"
assert_contains "bash block names the tee gap" "$scopeout" "POSIX tee"
assert_contains "bash block names other-interpreter gap" "$scopeout" "node -e"
psscope=$(bash "$HOOK" <<<"$(pwsh_command_json "Set-Content f.txt 'x'")" 2>&1)
assert_contains "powershell block states its scope" "$psscope" \
  "only this command string is inspected"
assert_contains "powershell block names Tee-Object coverage" "$psscope" "Tee-Object"
assert_contains "powershell block names the interpreter family it covers" "$psscope" \
  "python/python3/py/pypy with -c"

# The behaviour the scope note describes. A write inside an invoked script is
# not inspected, and a redirect whose producer is another program is allowed by
# the producer-scoped design — so the note must not promise either is blocked.
run "invoked script is not inspected (allowed)" "bash execute.sh" 0
run "invoked script with its own redirect (allowed)" "bash execute.sh >> run.log" 0
run "non-producer redirect (allowed)" "sort data.txt > out.txt" 0
run "cat with input files is not a heredoc write (allowed)" "cat a.txt b.txt > c.txt" 0
# tee and other inline-interpreter writes are outside the modeled surface.
run "tee pipe write (accepted floor — allowed)" 'echo "*" | tee .gitignore' 0
run "tee -a append (accepted floor — allowed)" 'echo "*" | tee -a .gitignore' 0
run "node -e write (accepted floor — allowed)" \
  "node -e \"require('fs').writeFileSync('f.txt','a')\"" 0
run "sed -i in-place write (accepted floor — allowed)" \
  "sed -i 's/a/b/' f.txt" 0 # portability-ok: test fixture command string containing sed -i, not an unsuffixed sed -i invocation
run "dd of= write (accepted floor — allowed)" "dd of=f.txt <<< x" 0

# --- Scratch-root exemption (block_hook_bypass_scratch_roots) ----------------
# The guard's first TARGET-scoped axis. The last exemption of this shape
# (`/dev/null`) shipped a one-token bypass of the whole guard, so the assertions
# that matter here are the ones proving the BYPASS SHAPES STILL BLOCK — a target
# that merely contains the exempt string, a `..` escape out of an exempt root,
# and a discard-then-real-file redirect ordering. The happy path is one line;
# everything below it is the adversarial floor.
SCRATCH_ENV=CLAUDE_PLUGIN_OPTION_BLOCK_HOOK_BYPASS_SCRATCH_ROOTS

# Shipped default is unchanged: with no roots configured, a temp write blocks
# exactly as it did before this option existed.
run "scratch: temp write blocks with option unset (blocked)" \
  "echo hello > /tmp/scratch/data.json" 2
run "scratch: temp write blocks with option empty (blocked)" \
  "echo hello > /tmp/scratch/data.json" 2 "$SCRATCH_ENV="

# Happy path: a write strictly under a configured root is exempt, in both lanes.
run "scratch: echo under configured root (allowed)" \
  "echo hello > /tmp/scratch/data.json" 0 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: cat under configured root (allowed)" \
  "cat > /tmp/scratch/data.json" 0 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: append under configured root (allowed)" \
  "echo hello >> /tmp/scratch/log" 0 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: second root in the comma list (allowed)" \
  "echo hello > /var/jobtmp/f" 0 "$SCRATCH_ENV=/tmp/scratch, /var/jobtmp"
run "scratch: nested below the root (allowed)" \
  "echo hello > /tmp/scratch/a/b/c.json" 0 "$SCRATCH_ENV=/tmp/scratch"

# THE BYPASS SHAPE. A sibling whose name merely STARTS WITH the root's last
# component is a different directory; a string-prefix compare would exempt it.
run "scratch: sibling sharing the root's prefix (blocked)" \
  "echo hello > /tmp/scratchevil/data.json" 2 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: root name as a substring mid-path (blocked)" \
  "echo hello > /opt/tmp/scratch-not/f" 2 "$SCRATCH_ENV=/tmp/scratch"
# The root itself is not a file the exemption covers — containment is strict.
run "scratch: the root path itself (blocked)" \
  "echo hello > /tmp/scratch" 2 "$SCRATCH_ENV=/tmp/scratch"
# `..` escapes are resolved BEFORE the compare, so the effective target governs.
run "scratch: dot-dot escape out of the root (blocked)" \
  "echo hello > /tmp/scratch/../../etc/passwd" 2 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: dot-dot escape to a prefix sibling (blocked)" \
  "echo hello > /tmp/scratch/../scratchevil/f" 2 "$SCRATCH_ENV=/tmp/scratch"
# `..` INSIDE the root still resolves under it and stays exempt.
run "scratch: dot-dot resolving back inside the root (allowed)" \
  "echo hello > /tmp/scratch/a/../b" 0 "$SCRATCH_ENV=/tmp/scratch"
# Left-to-right redirect ordering: the same trap the /dev/null exemption already
# survived. The EFFECTIVE target is the real file, so it blocks.
run "scratch: exempt target then real file (blocked)" \
  "echo hello > /tmp/scratch/f > real.txt" 2 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: exempt target then explicit 1> real file (blocked)" \
  "echo hello > /tmp/scratch/f 1>real.txt" 2 "$SCRATCH_ENV=/tmp/scratch"
# ...and the reverse ordering is exempt, because the effective target is exempt.
run "scratch: real file then exempt target (allowed)" \
  "echo hello > real.txt > /tmp/scratch/f" 0 "$SCRATCH_ENV=/tmp/scratch"
# A compound command cannot leak one segment's exemption onto the next.
run "scratch: exemption does not leak across segments (blocked)" \
  "echo a > /tmp/scratch/f && echo b > real.txt" 2 "$SCRATCH_ENV=/tmp/scratch"

# FAIL CLOSED on every target whose written text is not dependably the path that
# gets written.
run "scratch: relative target (blocked)" \
  "echo hello > scratch/data.json" 2 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: unexpanded variable in target (blocked)" \
  "echo hello > \$TMPDIR/data.json" 2 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: tilde target (blocked)" \
  "echo hello > ~/scratch/data.json" 2 "$SCRATCH_ENV=/tmp/scratch,~"
run "scratch: glob target (blocked)" \
  "echo hello > /tmp/scratch/*.json" 2 "$SCRATCH_ENV=/tmp/scratch"
# A root that fails the same normalization is skipped, not honoured loosely.
run "scratch: relative configured root exempts nothing (blocked)" \
  "echo hello > /tmp/scratch/f" 2 "$SCRATCH_ENV=scratch"
run "scratch: root of / exempts nothing (blocked)" \
  "echo hello > /tmp/scratch/f" 2 "$SCRATCH_ENV=/"

# Windows spellings normalize to the Git Bash form, so a CONFIGURED ROOT written
# `D:\jobtmp\scratch` and a target written `/d/jobtmp/scratch/f` compare equal.
# The root is configuration, not command text, so the escaped-operand fail-close
# does not apply to it.
run "scratch: /d target under a D:\\ root (allowed)" \
  "echo hello > /d/jobtmp/scratch/f" 0 "$SCRATCH_ENV=D:\\jobtmp\\scratch" # portability-ok: a backslash-separated Windows path in a test fixture, not a regex/sed construct
run "scratch: Windows sibling sharing the prefix (blocked)" \
  "echo hello > /d/jobtmp/scratchevil/f" 2 "$SCRATCH_ENV=/d/jobtmp/scratch"
# A backslash-spelled TARGET is never exempt, by the same fail-close as a quoted
# operand: in bash a backslash is an escape, so `D:\jobtmp\scratch\f` is not the
# path it looks like, and what reaches the compare is not what gets written.
# Windows targets belong in the `/d/...` spelling.
run "scratch: backslash-spelled target is not exempted (blocked)" \
  "echo hello > D:\\jobtmp\\scratch\\f" 2 "$SCRATCH_ENV=/d/jobtmp/scratch" # portability-ok: a backslash-separated Windows path in a test fixture, not a regex/sed construct

# Documented residual, pinned so it moves only deliberately: the segment scan
# runs over the lowercased command, so the compare is case-insensitive.
run "scratch: case-insensitive compare (documented residual, allowed)" \
  "echo hello > /tmp/SCRATCH/f" 0 "$SCRATCH_ENV=/tmp/scratch"

# TRUNCATED-OPERAND FAIL-CLOSED. strip_literals keeps a quoted write target but
# drops its quotes, and before 0.27.0 normalize_segments then resolved a `;`,
# `|`, `&`, newline or space inside that operand as SYNTAX — so a quoted pathname
# reached the compare as a safe-looking prefix of itself. bash treats the whole
# quoted word as one pathname, so exempting the prefix would be a one-token
# bypass. The operand now carries an OPAQUE mark over each such character and
# survives as one token (#2226); this axis refuses any operand that is opaque,
# and — its shipped floor, unchanged — any operand that was quoted at all.
run "scratch: quoted operand with ; is not exempted (blocked)" \
  "echo x > \"/tmp/scratch/a;/../../etc/passwd\"" 2 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: quoted operand with | is not exempted (blocked)" \
  "echo x > \"/tmp/scratch/a|/../../etc/passwd\"" 2 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: quoted operand with & is not exempted (blocked)" \
  "echo x > \"/tmp/scratch/a&/../../etc/passwd\"" 2 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: quoted operand with whitespace is not exempted (blocked)" \
  "echo x > \"/tmp/scratch/a ../../etc/pw\"" 2 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: escaped operand is not exempted (blocked)" \
  "echo x > /tmp/scratch/a\\ ../../etc/pw" 2 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: even a benign quoted target is not exempted (blocked)" \
  "echo x > \"/tmp/scratch/f\"" 2 "$SCRATCH_ENV=/tmp/scratch"
# Quotes BEFORE the redirect are the ordinary case and must not cost the
# exemption — as long as the quoted content holds no `>`; see the pair below.
run "scratch: quoted content, unquoted target (allowed)" \
  "echo \"hello world\" > /tmp/scratch/f" 0 "$SCRATCH_ENV=/tmp/scratch"
# THE BREADTH THAT WAS, still pinned on both sides — but the verdicts moved in
# 0.27.0 and these four cases are where that is visible. 0.25.x could not tell
# operand quotes from content quotes, so it read `${COMMAND#*>}` and refused the
# exemption on ANY quote or backslash after the first `>` CHARACTER anywhere in
# the command (#2236). The operand marks supply that association, so the test is
# keyed on the target word instead and both shapes below are exempt again.
# FOUR of the five assertions here are GRANTS — blocked at 0.25.3, allowed now —
# and they are the ENTIRE grant surface of the #2226 fix. Each lands only on a
# target the marks prove was bare: no quote mark, no opaque mark, no backslash.
# The fifth (the unquoted compound) was already allowed and is the control.
#
# (1) Segment-scoped now: a quote in an unrelated LATER segment is that segment's
#     business. Segment 1's target is a plain path strictly under the root.
run "scratch: quote in an unrelated later segment keeps it (allowed)" \
  "echo x > /tmp/scratch/f && grep foo \"notes.txt\"" 0 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: the same compound with no quotes keeps it (allowed)" \
  "echo x > /tmp/scratch/f && grep foo notes.txt" 0 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: quote in a later ;-segment keeps it (allowed)" \
  "echo x > /tmp/scratch/f; cat \"notes.txt\"" 0 "$SCRATCH_ENV=/tmp/scratch"
# (2) Keyed on the redirect OPERAND now: a `>` inside quoted CONTENT is content,
#     and that content's quotes are the content's own. strip_literals drops the
#     whole span — the same quote tracking every other lane of this guard already
#     relies on to keep quoted prose inert.
run "scratch: > inside double-quoted content keeps it (allowed)" \
  "echo \"a > b\" > /tmp/scratch/f" 0 "$SCRATCH_ENV=/tmp/scratch"
run "scratch: > inside single-quoted content keeps it (allowed)" \
  "echo 'x > y' > /tmp/scratch/f" 0 "$SCRATCH_ENV=/tmp/scratch"
# --- Redirect-operand marking (#2226) ---------------------------------------
# THE REPORTED BYPASS AND ITS FAMILY. A quoted redirect operand is one pathname
# to bash. Until 0.27.0 the exemptions were decided on its first whitespace- or
# separator-delimited fragment, so `> "/dev/null ../../etc/pw"` was exempted on
# the word `/dev/null` while nothing named `/dev/null` was the destination. The
# operand now carries an opaque mark over every character whose literal value
# would read as syntax, and survives the strip and the segment split as ONE
# token, so no fragment of it can stand in for the whole.
#
# The DISCARD lane. Every one of these is allowed at 0.25.3 unless noted.
run "#2226: quoted /dev/null + space fragment (blocked)" \
  "echo x > \"/dev/null ../../etc/pw\"" 2
run "#2226: quoted /dev/null + ; fragment (blocked)" \
  "echo x > \"/dev/null;/../../etc/passwd\"" 2
run "#2226: quoted /dev/null + | fragment (blocked)" \
  "echo x > \"/dev/null|/../../etc/passwd\"" 2
run "#2226: quoted /dev/null + & fragment (blocked)" \
  "echo x > \"/dev/null&/../../etc/passwd\"" 2
run "#2226: quoted /dev/null + parens (blocked)" \
  "echo x > \"/dev/null(a)/../../etc/pw\"" 2
# A backslash inside a DOUBLE-quoted operand: bash keeps the backslash here, this
# strip cannot, so the pair is opaque rather than guessed at.
run "#2226: double-quoted /dev/null + backslash escape (blocked)" \
  "echo x > \"/dev/null\\ ../../etc/pw\"" 2
run "#2226: single-quoted /dev/null + space fragment (blocked)" \
  "echo x > '/dev/null ../../etc/pw'" 2
run "#2226: partially-quoted /dev/null + space fragment (blocked)" \
  "echo x > /dev/\"null ../../etc/pw\"" 2
# The same truncation via an UNQUOTED escape. `\;` reached normalize_segments'
# escaped-separator sentinel and was restored to a space, cutting the operand.
run "#2226: unquoted escaped ; in a /dev/null operand (blocked)" \
  "echo x > /dev/null\\;/../../etc/passwd" 2
run "#2226: unquoted escaped space in a /dev/null operand (blocked)" \
  "echo x > /dev/null\\ ../../etc/pw" 2
# fd-numbered stdout spelling, the cat lane, and redirect ordering all reach the
# same decision, so all three carry the shape.
run "#2226: 1> fd-numbered quoted operand (blocked)" \
  "echo x 1>\"/dev/null ../../etc/pw\"" 2
run "#2226: cat lane, quoted operand (blocked)" \
  "cat > \"/dev/null ../../etc/pw\"" 2
run "#2226: quoted operand then real file (blocked)" \
  "echo x > \"/dev/null ../x\" > real.txt" 2
run "#2226: real file then quoted operand (blocked)" \
  "echo x > real.txt > \"/dev/null ../x\"" 2
# A quoted operand spanning physical lines, and an operand continued by a
# backslash-newline: bash keeps both as one word, so the mark must too.
DEVNULL_MULTILINE=$(printf 'echo x > "/dev/null\n../../etc/pw"')
run "#2226: multi-line quoted operand (blocked)" "$DEVNULL_MULTILINE" 2
DEVNULL_CONTINUED=$(printf 'echo x > /dev/null\\\n../../etc/pw')
run "#2226: operand continued by backslash-newline (blocked)" "$DEVNULL_CONTINUED" 2
# A raw sentinel byte in the command text must never pass for a mark this strip
# emitted — the quote mark is stripped before the discard compare, so a forged
# one would otherwise make `/dev/<EOT>null` compare equal to `/dev/null`.
DEVNULL_FORGED=$(printf 'echo x > /dev/\x04null')
run "#2226: forged quote-mark byte in the target (blocked)" "$DEVNULL_FORGED" 2
DEVNULL_FORGED_OPAQUE=$(printf 'echo x > /dev/\x03null')
run "#2226: forged opaque-mark byte in the target (blocked)" "$DEVNULL_FORGED_OPAQUE" 2
# An empty quoted operand is not a discard and is not a path; it blocks.
run "#2226: empty quoted target (blocked)" "echo x > \"\"" 2
# THE FRICTION FLOOR. An unambiguous quoted or partially-quoted discard is still
# a discard — the quote mark is transparent to this compare, deliberately, so
# the fix costs no ordinary /dev/null usage. (Also pinned above, kept adjacent
# here because it is the boundary the marking must not cross.)
run "#2226: unambiguous quoted /dev/null stays a discard (allowed)" \
  "echo x > \"/dev/null\"" 0
run "#2226: unambiguous partially-quoted /dev/null stays a discard (allowed)" \
  "cat > /dev/\"null\"" 0
# The stderr/fd lanes never resolved a stdout target and must not start now.
run "#2226: 2> quoted operand is not a stdout write (allowed)" \
  "echo x 2>\"/dev/null a\"" 0

# THE SCRATCH LANE, same shapes. These already blocked at 0.25.3 via the
# whole-command fail-close; they must keep blocking on the operand-keyed rule
# that replaced it, otherwise the narrowing below traded a bypass for a fix.
run "#2226: scratch, quoted operand with > inside (blocked)" \
  "echo x > \"/tmp/scratch/a>real.txt\"" 2 "$SCRATCH_ENV=/tmp/scratch"
run "#2226: scratch, unquoted escaped ; in the operand (blocked)" \
  "echo x > /tmp/scratch/a\\;/../../etc/passwd" 2 "$SCRATCH_ENV=/tmp/scratch"
SCRATCH_CONTINUED=$(printf 'echo x > /tmp/scratch/a\\\n../../etc/passwd')
run "#2226: scratch, operand continued by backslash-newline (blocked)" \
  "$SCRATCH_CONTINUED" 2 "$SCRATCH_ENV=/tmp/scratch"

# The exemption is target-scoped only — it must not relax the producer axis.
run "scratch: python3 -c write into an exempt root still blocks" \
  "python3 -c \"open('/tmp/scratch/x','w').write('a')\"" 2 "$SCRATCH_ENV=/tmp/scratch"

# --- #2217: three inline-write forms that reached a real file ----------------
# All three were rc=0 (allowed) before this change. Every assertion below that
# moves anything moves allowed -> blocked; the floors interleaved with them are
# what pin that NO assertion moved blocked -> allowed.

# (1) THE INTERPRETER SPELLING FLOOR. The detector required the literal
# `python3`, so the same inline write spelled with any other name in the family
# ran unseen. The guard's own scope note advertised `python -c` as its example.
run "#2217: python -c open write (blocked)" \
  "python -c \"open('x','w').write('a')\"" 2
run "#2217: py -c open write (blocked)" \
  "py -c \"open('x','w').write('a')\"" 2
run "#2217: py3 -c open write (blocked)" \
  "py3 -c \"open('x','w').write('a')\"" 2
run "#2217: python2 -c open write (blocked)" \
  "python2 -c \"open('x','w').write('a')\"" 2
run "#2217: python3.11 -c open write (blocked)" \
  "python3.11 -c \"open('x','w').write('a')\"" 2
run "#2217: pypy3 -c open write (blocked)" \
  "pypy3 -c \"open('x','w').write('a')\"" 2
# The Windows launcher's version selector is admitted because a `-<digits>`
# token cannot be a script path. No other gap between interpreter and flag is.
run "#2217: py -3 -c open write (blocked)" \
  "py -3 -c \"open('x','w').write('a')\"" 2
run "#2217: path-qualified python.exe -c open write (blocked)" \
  "/c/Python313/python.exe -c \"open('x','w').write('a')\"" 2

# THE NAME-ANCHOR FLOOR. Widening the name must not widen the boundary: every
# one of these merely CONTAINS a family spelling and stays inert.
run "#2217: mypy -c open write (allowed)" \
  "mypy -c \"open('x','w').write('a')\"" 0
run "#2217: happy -c open write (allowed)" \
  "happy -c \"open('x','w').write('a')\"" 0
run "#2217: spy -c open write (allowed)" \
  "spy -c \"open('x','w').write('a')\"" 0
run "#2217: pytest -c open write (allowed)" \
  "pytest -c \"open('x','w').write('a')\"" 0
run "#2217: mypython3 -c open write (allowed)" \
  "mypython3 -c \"open('x','w').write('a')\"" 0
# THE OVER-BLOCK FLOOR (#1601 / #2148 are open against this arm in the OPPOSITE
# direction). Widening the name multiplies whatever false-positive rate the arm
# has, so the read-only and script-run shapes are pinned for the new spellings
# too — not just for `python3`.
run "#2217: python -c read-only open (allowed)" \
  "python -c \"print(open('f').read())\"" 0
run "#2217: py -c print only (allowed)" \
  "py -c \"print(1+1)\"" 0
run "#2217: python3.11 -c os.path.normpath (allowed)" \
  "python3.11 -c \"import os; print(os.path.normpath('a/b'))\"" 0
run "#2217: python -m module run (allowed)" "python -m mytool --out f" 0
run "#2217: python build.py script run (allowed)" "python build.py" 0
run "#2217: python --version (allowed)" "python --version" 0
run "#2217: py --list (allowed)" "py --list" 0

# (2) A PRODUCER SPLIT FROM ITS OWN REDIRECT BY A PHYSICAL NEWLINE. A newline
# reached with a quote span still OPEN is not a separator — bash is inside a
# quoted word — but strip_literals re-emitted it, so normalize_segments split
# the producer from the redirect it owned. The `\n`-escaped spelling of the same
# command always blocked; only the physical newline slipped.
PY_NL_SQ=$(printf 'printf \x27a\nb\n\x27 > notes.md')
run "#2217: printf, physical newline in a single-quoted arg (blocked)" "$PY_NL_SQ" 2
PY_NL_DQ=$(printf 'echo "a\nb" > notes.md')
run "#2217: echo, physical newline in a double-quoted arg (blocked)" "$PY_NL_DQ" 2
run "#2217: control — the same write with an escaped newline (blocked)" \
  "printf \"a\\nb\\n\" > notes.md" 2
# THE DISCRIMINATOR between joining the two sides with NOTHING and joining them
# with a space. `ec"<newline>"ho` is ONE bash word and bash runs it as `echo`;
# only an empty join reconstructs it. A space join leaves `ec ho` and this
# assertion fails — which is why the shipped fix does not use one.
PY_NL_SPLICE=$(printf 'ec"\n"ho x > f')
run "#2217: quote span splicing a command word (blocked)" "$PY_NL_SPLICE" 2
# Non-empty dropped spans inside a command word must not splice into a false
# producer name (`ec"xy"ho` runs as `ecxyho`, not `echo`).
run "#2385: ec\"xy\"ho splice false positive (allowed)" 'ec"xy"ho hello > out.txt' 0
PY_XY_NL=$(printf 'ec"x\ny"ho hello > out.txt')
run "#2385: ec\"x<NL>y\"ho multiline splice (allowed)" "$PY_XY_NL" 0
run "#2385: ec\"\"ho empty span splice still blocks" 'ec""ho x > f' 2
run "#2385: ec\"<NL>\"ho empty multiline span still blocks" "$(printf 'ec"\n"ho x > f')" 2

# THE MULTI-LINE PROSE FLOOR. The whole point of carrying an open quote across
# lines is that a `--body`/`-m` payload merely MENTIONING a write stays inert.
# Dropping the join newline must not change that — the span's content is dropped
# either way — so these stay allowed.
PY_NL_BODY=$(printf 'gh pr create --body "line one\necho x > f\nline three"')
run "#2217: multi-line PR body mentioning a write (allowed)" "$PY_NL_BODY" 0
PY_NL_MSG=$(printf 'git commit -m "subject\n\ncat > notes.md is a bypass\n"')
run "#2217: multi-line commit message mentioning a write (allowed)" "$PY_NL_MSG" 0
PY_NL_GREP=$(printf 'grep "foo\nbar" file | wc -l')
run "#2217: multi-line grep pattern piped, no redirect (allowed)" "$PY_NL_GREP" 0
PY_NL_DEVNULL=$(printf 'echo "a\nb" > /dev/null')
run "#2217: multi-line span discarded to /dev/null (allowed)" "$PY_NL_DEVNULL" 0
PY_NL_PIPE=$(printf 'printf \x27a\nb\x27 | wc -c')
run "#2217: multi-line span piped, no redirect (allowed)" "$PY_NL_PIPE" 0
PY_NL_DANGLE=$(printf 'git status ; echo "dangling')
run "#2217: unterminated quote at end of command (allowed)" "$PY_NL_DANGLE" 0
# Already blocked before the change; the segment split it relies on is a real
# separator on the closing line, so it must keep blocking.
PY_NL_THEN=$(printf 'grep "a\nb" f ; echo x > out.txt')
run "#2217: multi-line span then a real producer+redirect (blocked)" "$PY_NL_THEN" 2

# THE ONE ROW THAT MOVES THE OTHER WAY, pinned deliberately. Fusing the two
# sides of the span back into one segment can also put a NON-producer at the
# segment start, and that is the correct reading: in `foo "a<newline>" echo x > f`
# bash's command word is `foo` and `echo` is one of its ARGUMENTS, so the
# redirect's producer is another program and this guard is producer-scoped by
# design. Before the change the newline split it into a bogus `echo x > f`
# segment and it blocked — a false positive. The single-line spelling of the
# same command is the control: it has always been allowed on `main`, so this
# makes the multi-line form agree with the shipped single-line behavior rather
# than inventing a new exemption. Both are asserted so the agreement is pinned.
PY_NL_ARGECHO=$(printf 'foo "a\n" echo x > f')
run "#2217: producer is foo, echo is its argument (allowed)" "$PY_NL_ARGECHO" 0
run "#2217: control — same command on one line (allowed)" "foo \"a\" echo x > f" 0
# The mirror image, and the reason the row above is not a hole: when the command
# word really IS the producer, fusing the segment is what reveals the write.
PY_NL_REALECHO=$(printf 'echo "a\n" x > f')
run "#2217: producer is echo, span is its argument (blocked)" "$PY_NL_REALECHO" 2
run "#2217: control — same command on one line (blocked)" "echo \"a\" x > f" 2
# Same fusion on the cat lane, with its own single-line control.
PY_NL_CAT=$(printf 'cat "a\n" > f')
run "#2217: cat with a multi-line quoted arg then a redirect (blocked)" "$PY_NL_CAT" 2
run "#2217: control — same command on one line (blocked)" "cat \"a\" > f" 2
# A span that closes and re-opens across lines fuses at both joins.
PY_NL_TWO=$(printf 'echo "a\nb" "c\nd" > f')
run "#2217: two multi-line spans, one producer+redirect (blocked)" "$PY_NL_TWO" 2
# THE BOUNDARY OF THE ROW ABOVE, and the reason it is one row and not a class.
# Fusion puts whatever preceded the span at the segment start, so the question is
# whether a LEGITIMATE command prefix in front of a multi-line span can hide a
# real producer from `_producer_head`'s `^` anchor. It cannot: `_cmd_prefix`,
# `_modifier_opt_arg` and `_leading_redir` peel exactly these, and the peel runs
# on the fused segment. Each is paired with the single-line control that already
# blocked on `main`, so a regression in the peel shows up as a pair splitting.
PY_NL_ENVASSIGN=$(printf 'FOO="a\nb" echo x > f')
run "#2217: env-assignment prefix before a multi-line span (blocked)" "$PY_NL_ENVASSIGN" 2
run "#2217: control — same command on one line (blocked)" "FOO=\"ab\" echo x > f" 2
PY_NL_ENV=$(printf 'env FOO="a\nb" echo x > f')
run "#2217: env modifier before a multi-line span (blocked)" "$PY_NL_ENV" 2
run "#2217: control — same command on one line (blocked)" "env FOO=\"ab\" echo x > f" 2
PY_NL_IF=$(printf 'if true ; then echo "a\nb" > f ; fi')
run "#2217: compound-command header before a multi-line span (blocked)" "$PY_NL_IF" 2
PY_NL_NEG=$(printf '! echo "a\nb" > f')
run "#2217: pipeline negation before a multi-line span (blocked)" "$PY_NL_NEG" 2
PY_NL_EXECA=$(printf 'exec -a n echo "a\nb" > f')
run "#2217: exec -a NAME before a multi-line span (blocked)" "$PY_NL_EXECA" 2
PY_NL_LEADREDIR=$(printf '> f echo "a\nb"')
run "#2217: leading redirect before a multi-line span (blocked)" "$PY_NL_LEADREDIR" 2
run "#2217: control — same command on one line (blocked)" "> f echo \"ab\"" 2
PY_NL_PRINTF=$(printf 'FOO=1 printf "a\nb" > f')
run "#2217: env-assignment prefix, printf producer (blocked)" "$PY_NL_PRINTF" 2
# The cat lane keeps its own shape: `cat FILE x > f` is a copy, not a stdin
# consume, and `_cat_redir` needs `cat` immediately before the redirect. Fusion
# leaves the argument words in place, so this stays allowed — before and after.
PY_NL_CATARG=$(printf 'cat "a\nb" x > f')
run "#2217: cat with args between it and the redirect (allowed)" "$PY_NL_CATARG" 0

# (3) THE REOPENED ACCEPTED RESIDUAL. `python3 - <<PY … PY` (no `-c`) was
# documented as uncovered and accepted in the PowerShell lane's comment. Reopened
# on new reachability evidence: this repo's own session record shows an agent
# reaching for that exact form to patch a file
# (.work/handoffs/20260809T082720Z-handoff-post-2008-followups.md:211). The `-`
# is what makes it INLINE — the code is in the command string the hook reads,
# not in an opaque script file.
PY_HEREDOC=$(printf 'python3 - <<\x27PY\x27\nopen("f","w").write("x")\nPY')
run "#2217: python3 - <<PY heredoc write (blocked)" "$PY_HEREDOC" 2
PY_HEREDOC2=$(printf 'python - <<\x27PY\x27\nimport pathlib; pathlib.Path("f").write_text("x")\nPY')
run "#2217: python - <<PY heredoc write, family spelling (blocked)" "$PY_HEREDOC2" 2
# THE STDIN FLOOR. `-` alone says nothing about direction; the raw write
# indicator still has to be there, and an opaque script piped in stays unseen.
PY_HEREDOC_RO=$(printf 'python3 - <<\x27PY\x27\nprint(open("f").read())\nPY')
run "#2217: python3 - <<PY read-only heredoc (allowed)" "$PY_HEREDOC_RO" 0
run "#2217: cat script.py | python3 - (allowed)" "cat script.py | python3 -" 0
run "#2217: python3 - </dev/null (allowed)" "python3 - </dev/null" 0
# ACCEPTED RESIDUAL, restated at its NARROWED width: `python3 <<PY` with no `-`
# argument stays uncovered. Matching a bare trailing interpreter token would
# flip the two allowed cases below, so that exemption costs this one spelling.
PY_HEREDOC_NODASH=$(printf 'python3 <<\x27PY\x27\nopen("f","w").write("x")\nPY')
run "#2217: accepted floor — python3 <<PY with no dash (allowed)" "$PY_HEREDOC_NODASH" 0
# Same discipline as the `-c` arm: no gap between interpreter and `-`, so an
# interpreter option in between is uncovered. Admitting an arbitrary
# option-shaped token is what would let a SCRIPT path through as one.
PY_HEREDOC_OPT=$(printf 'python3 -O - <<\x27PY\x27\nopen("f","w").write("x")\nPY')
run "#2217: accepted floor — an option between python3 and - (allowed)" "$PY_HEREDOC_OPT" 0
# The heredoc operator glued to the `-` is the same invocation and IS covered.
PY_HEREDOC_GLUED=$(printf 'python3 -<<\x27PY\x27\nopen("f","w").write("x")\nPY')
run "#2217: python3 -<<PY with no space (blocked)" "$PY_HEREDOC_GLUED" 2
run "#2217: floor that costs it — echo pathlib | python3 (allowed)" \
  "echo \"pathlib\" | python3" 0
run "#2217: floor that costs it — cat script.py | python3 (allowed)" \
  "cat script.py | python3" 0
# A prose mention of the heredoc form is still a mention: the Bash lane decides
# the INVOCATION on the literal-stripped form, so a quoted one never matches.
run "#2217: commit message quoting a heredoc write (allowed)" \
  "git commit -m \"use python3 - <<PY open('f','w').write(x) PY\"" 0

# The PowerShell lane carried the same interpreter spelling floor.
run_pwsh "#2217: PS python -c open write (blocked)" \
  "python -c \"open('x','w').write('a')\"" 2
run_pwsh "#2217: PS py -c open write (blocked)" \
  "py -c \"open('x','w').write('a')\"" 2
run_pwsh "#2217: PS python3.11 -c open write (blocked)" \
  "python3.11 -c \"open('x','w').write('a')\"" 2
run_pwsh "#2217: PS mypy -c open write (allowed)" \
  "mypy -c \"open('x','w').write('a')\"" 0
run_pwsh "#2217: PS pytest -c open write (allowed)" \
  "pytest -c \"open('x','w').write('a')\"" 0
run_pwsh "#2217: PS python -c read-only os.path.normpath (allowed)" \
  "python -c \"import os; print(os.path.normpath('a/b'))\"" 0
run_pwsh "#2217: PS python script run, open( in an arg, no -c (allowed)" \
  "python build.py --path \"open('x','w')\"" 0

# --- #2663: PowerShell classifier is sourced only on the PowerShell lane -------
# The ~41 KB ps-command.sh must not be parsed on every Bash PreToolUse. Trace the
# Bash lane and assert the source is absent; then pin that the PowerShell lane
# still loads it and still blocks a write with no unbound-ps:: error on stderr.
bash_trace=$(bash -x "$HOOK" <<<"$(command_json 'git status')" 2>&1 >/dev/null) || true
assert_absent "#2663: Bash lane does not source ps-command.sh" \
  "$bash_trace" "ps-command.sh"
assert_absent "#2663: Bash lane never defines a ps:: symbol via source" \
  "$bash_trace" "lib/powershell"
pwsh_trace_err=$(bash -x "$HOOK" <<<"$(pwsh_command_json 'Set-Content -Path f.txt -Value x')" 2>&1 >/dev/null) || true
assert_contains "#2663: PowerShell lane sources ps-command.sh" \
  "$pwsh_trace_err" "ps-command.sh"
assert_absent "#2663: PowerShell lane has no unbound ps:: on stderr" \
  "$pwsh_trace_err" "command not found"
run_pwsh "#2663: PowerShell write still blocked after lazy source" \
  "Set-Content -Path f.txt -Value x" 2

# --- #2731: same-command staged-write mv|cp detector --------------------------
# Unmodeled producer redirects into a path that a later mv|cp reuses as SOURCE.
# Path-identity keeps ordinary renames unblocked; scratch-root dest stays staging.
run "#2731: jq > tmp && mv tmp repo-file (blocked)" \
  "jq . f > /tmp/x && mv /tmp/x plugins/guardrails/.claude-plugin/plugin.json" 2
run "#2731: curl > tmp && cp tmp dest (blocked)" \
  "curl -s https://example.com > /tmp/page && cp /tmp/page out.html" 2
run "#2731: sort > tmp && mv -f tmp dest (blocked)" \
  "sort f > /tmp/sorted && mv -f /tmp/sorted out.txt" 2
run "#2731: mv -t dest form (blocked)" \
  "jq . f > /tmp/x && mv -t plugins/x.json /tmp/x" 2
run "#2731: ordinary rename, no prior redirect (allowed)" \
  "mv old.txt new.txt" 0
run "#2731: data-pipeline mv of a path never redirected here (allowed)" \
  "jq . f > /tmp/other && mv /tmp/unrelated dest.txt" 0
run "#2731: redirect alone, no later move (allowed — producer residual)" \
  "jq . f > plugins/guardrails/.claude-plugin/plugin.json" 0
run "#2731: staged move into configured scratch (allowed)" \
  "jq . f > /tmp/scratch/x && mv /tmp/scratch/x /tmp/scratch/y" 0 \
  "$SCRATCH_ENV=/tmp/scratch"
run "#2731: staged move from scratch path to repo (blocked)" \
  "jq . f > /tmp/scratch/x && mv /tmp/scratch/x out.json" 2 \
  "$SCRATCH_ENV=/tmp/scratch"
run "#2731: install mover residual (allowed — not mv|cp)" \
  "jq . f > /tmp/x && install /tmp/x dest.txt" 0
run "#2731: multi-source cp keeps sources distinct (blocked)" \
  "jq . f > /tmp/x && cp /tmp/x /tmp/other destdir/" 2
# Scope note names the new lane and the residuals it still cannot see.
scopeout=$(bash "$HOOK" <<<"$(command_json 'jq . f > /tmp/x && mv /tmp/x dest')" 2>&1 >/dev/null) || true
assert_contains "#2731: block names staged-write-move form" "$scopeout" "staged write"
assert_contains "#2731: scope names same-command staged move" "$scopeout" "same-command staged"
assert_contains "#2731: scope names cross-tool-call residual" "$scopeout" "cross-tool-call"
assert_contains "#2731: scope names other movers residual" "$scopeout" "install, rsync, dd"

# --- NUL in payload must fail closed (#2136) ----------------------------------
nul_rc=0
bash "$HOOK" <<<"$(jq -n '{tool_name:"Bash",tool_input:{command:("git status" + ([0]|implode))}}')" >/dev/null 2>&1 || nul_rc=$?
assert_exit "NUL in command (blocked)" 2 "$nul_rc"

report
