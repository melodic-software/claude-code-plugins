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

# --- Enforcement-scope disclosure -------------------------------------------
# The message asserted "use Write or Edit instead" with no scope, so it read as
# "shell file writes are blocked" when the guard is deliberately producer-scoped
# over one command string. Both lanes must carry the scope, and the behaviour
# the scope describes is pinned below it so message and reality move together.
scopeout=$(bash "$HOOK" <<<"$(command_json "printf 'x' > out.log")" 2>&1)
assert_contains "bash block states its scope" "$scopeout" \
  "only this command string is inspected"
assert_contains "bash block names the invoked-script gap" "$scopeout" \
  "inside an invoked script file"
assert_contains "bash block exempts inspected inline code from the gap" "$scopeout" \
  "recognized inline interpreter code"
psscope=$(bash "$HOOK" <<<"$(pwsh_command_json "Set-Content f.txt 'x'")" 2>&1)
assert_contains "powershell block states its scope" "$psscope" \
  "only this command string is inspected"

# The behaviour the scope note describes. A write inside an invoked script is
# not inspected, and a redirect whose producer is another program is allowed by
# the producer-scoped design — so the note must not promise either is blocked.
run "invoked script is not inspected (allowed)" "bash execute.sh" 0
run "invoked script with its own redirect (allowed)" "bash execute.sh >> run.log" 0
run "non-producer redirect (allowed)" "sort data.txt > out.txt" 0
run "cat with input files is not a heredoc write (allowed)" "cat a.txt b.txt > c.txt" 0

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

# Windows spellings normalize to the Git Bash form, so a root and a target
# written in different spellings of the same directory compare equal.
run "scratch: backslash target under a /c root (allowed)" \
  "echo hello > C:\\\\Users\\\\me\\\\scratch\\\\f" 0 "$SCRATCH_ENV=/c/Users/me/scratch" # portability-ok: a backslash-separated Windows path in a test fixture, not a regex/sed construct
run "scratch: /c target under a C:\\ root (allowed)" \
  "echo hello > /c/Users/me/scratch/f" 0 "$SCRATCH_ENV=C:\\Users\\me\\scratch" # portability-ok: a backslash-separated Windows path in a test fixture, not a regex/sed construct
run "scratch: Windows sibling sharing the prefix (blocked)" \
  "echo hello > /c/Users/me/scratchevil/f" 2 "$SCRATCH_ENV=/c/Users/me/scratch"

# Documented residual, pinned so it moves only deliberately: the segment scan
# runs over the lowercased command, so the compare is case-insensitive.
run "scratch: case-insensitive compare (documented residual, allowed)" \
  "echo hello > /tmp/SCRATCH/f" 0 "$SCRATCH_ENV=/tmp/scratch"

# The exemption is target-scoped only — it must not relax the producer axis.
run "scratch: python3 -c write into an exempt root still blocks" \
  "python3 -c \"open('/tmp/scratch/x','w').write('a')\"" 2 "$SCRATCH_ENV=/tmp/scratch"

report
