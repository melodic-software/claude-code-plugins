#!/usr/bin/env bash
# Tests for scripts/check-pipefail-grep-q.sh: one fixture file per shape, fed
# as a file argument, so each verdict is on that shape alone. Every fixture is
# written from a quoted heredoc, which is what keeps this suite's own source
# clean under the gate it tests.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-pipefail-grep-q.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

WORK="$(mktemp -d)" || exit 2
trap 'rm -rf "$WORK"' EXIT

RC=0
OUT=""
ERR=""
n=0

# run_gate <args...>: run the gate with stdout and stderr kept apart.
run_gate() {
  RC=0
  bash "$SCRIPT" "$@" >"$WORK/out" 2>"$WORK/err" || RC=$?
  OUT="$(cat "$WORK/out")"
  ERR="$(cat "$WORK/err")"
}

# new_case: write stdin to a fresh fixture file and name it in CASE_FILE.
new_case() {
  n=$((n + 1))
  CASE_FILE="$WORK/case-$n.sh"
  cat >"$CASE_FILE"
}

# expect_flag <label> <line> < fixture: exit 1 with a finding at <line>.
expect_flag() {
  local label="$1" line="$2"
  new_case
  run_gate "$CASE_FILE"
  if ((RC == 1)) && [[ "$ERR" == *"PIPED EARLY-EXIT GREP: $CASE_FILE:$line:"* && "$OUT" != *"PIPED"* ]]; then
    ok "flags $label"
  else
    fail "expected $label flagged at line $line (rc=$RC, stdout='$OUT', stderr='$ERR')"
  fi
}

# expect_clean <label> < fixture: exit 0 with a clean statement and no finding.
expect_clean() {
  local label="$1"
  new_case
  run_gate "$CASE_FILE"
  if ((RC == 0)) && [[ -n "$OUT" && "$ERR" != *"PIPED"* ]]; then
    ok "does not flag $label"
  else
    fail "expected $label clean (rc=$RC, stdout='$OUT', stderr='$ERR')"
  fi
}

# --- early-exit options, each in its own spelling ----------------------------
expect_flag "-q" 1 <<'EOF'
printf '%s\n' "$x" | grep -q foo
EOF
expect_flag "-Fxq" 1 <<'EOF'
echo "$x" | grep -Fxq foo
EOF
expect_flag "-qv" 1 <<'EOF'
echo "$x" | grep -qv foo
EOF
expect_flag "-vq" 1 <<'EOF'
echo "$x" | grep -vq foo
EOF
expect_flag "--quiet" 1 <<'EOF'
echo "$x" | grep --quiet foo
EOF
expect_flag "--silent" 1 <<'EOF'
echo "$x" | grep --silent foo
EOF
expect_flag "-l" 1 <<'EOF'
cat list | grep -l foo
EOF
expect_flag "-L" 1 <<'EOF'
cat list | grep -L foo
EOF
expect_flag "-m1" 1 <<'EOF'
echo "$x" | grep -m1 foo
EOF
expect_flag "-m 1" 1 <<'EOF'
echo "$x" | grep -m 1 foo
EOF
expect_flag "--max-count=1" 1 <<'EOF'
echo "$x" | grep --max-count=1 foo
EOF
expect_flag "an option after the pattern" 1 <<'EOF'
echo "$x" | grep foo -q
EOF

# --- the grep word and the pipe in their other spellings ---------------------
expect_flag "egrep" 1 <<'EOF'
echo "$x" | egrep -q 'a|b'
EOF
expect_flag "fgrep" 1 <<'EOF'
echo "$x" | fgrep -q foo
EOF
expect_flag "a command-prefixed grep" 1 <<'EOF'
echo "$x" | command grep -q foo
EOF
expect_flag "a backslash-escaped grep" 1 <<'EOF'
echo "$x" | \grep -q foo
EOF
expect_flag "a grep named by path" 1 <<'EOF'
echo "$x" | /usr/bin/grep -q foo
EOF
expect_flag "an env-prefixed grep" 1 <<'EOF'
echo "$x" | env LC_ALL=C grep -q foo
EOF
expect_flag "a grep in a brace group" 1 <<'EOF'
echo "$x" | { grep -q foo; }
EOF
expect_flag "a grep in a subshell" 1 <<'EOF'
echo "$x" | ( grep -q foo )
EOF
expect_flag "a grep in a nested subshell" 1 <<'EOF'
echo "$x" | ( (grep -q foo) )
EOF
expect_flag "-q after --color" 1 <<'EOF'
echo "$x" | grep --color -q foo
EOF
expect_flag "a pipe of both streams (|&)" 1 <<'EOF'
make 2>&1 |& grep -q error
EOF
expect_flag "a three-stage pipe" 1 <<'EOF'
echo "$x" | sort | grep -q foo
EOF
expect_flag "a negated pipeline" 1 <<'EOF'
if ! echo "$x" | grep -q foo; then :; fi
EOF

# --- pipes that span lines report the grep's own line ------------------------
expect_flag "a continuation before the pipe" 2 <<'EOF'
echo "$x" \
  | grep -q foo
EOF
expect_flag "a continuation after the pipe" 2 <<'EOF'
echo "$x" | \
  grep -q foo
EOF
expect_flag "a trailing pipe with grep on the next line" 2 <<'EOF'
echo "$x" |
  grep -q foo
EOF
expect_flag "a finding below unrelated lines" 4 <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
y=$((1 << 3))
echo "$y" | grep -q 8
EOF
expect_flag "a pipe after a bare arithmetic left shift" 2 <<'EOF'
(( mask = 1 << 3 ))
echo "$mask" | grep -q 8
EOF

# --- quoting that must not hide a real pipe ----------------------------------
expect_flag "a quoted -q option" 1 <<'EOF'
echo x | grep "-q" foo
EOF
expect_flag "a single-quoted --quiet option" 1 <<'EOF'
echo x | grep '--quiet' foo
EOF
expect_flag "a case pattern ) inside \$( ) before the pipe" 1 <<'EOF'
v="$(case $y in a) echo a;; esac | grep -q x)"
EOF
expect_flag "a pipe after \$( ) holding a bare case argument" 2 <<'EOF'
v="$(echo case x)"
echo x | grep -q y
EOF
expect_flag "a pipe after \$( ) ending in a bare case argument, same line" 1 <<'EOF'
v="$(echo case )"; echo x | grep -q y
EOF
expect_flag "a pipe two lines after \$( ) holding a printf case argument" 3 <<'EOF'
v="$(printf '%s\n' case x)"
out="$(echo z)"
echo "$out" | grep -q z
EOF
expect_flag "a pipe three lines after \$( ) holding a bare case argument" 3 <<'EOF'
v="$(echo case x)"
w="$y"
echo x | grep -q y
EOF
expect_flag "a pipe inside \$( ) after a case argument" 1 <<'EOF'
v=$(echo case study | grep -q x)
EOF
expect_flag "a pipe after an esac argument inside a case in \$( )" 2 <<'EOF'
v=$(case $y in a) echo esac ;; esac)
echo x | grep -q y
EOF
expect_flag "a pipe after a case inside \$( ) closes" 2 <<'EOF'
v=$(case $y in (a) echo a;; b|c) echo b;; esac)
echo "$v" | grep -q a
EOF
expect_flag "a # inside double quotes before the pipe" 1 <<'EOF'
echo "a#b" | grep -q a
EOF
expect_flag "a # inside single quotes before the pipe" 1 <<'EOF'
echo 'x # y' | grep -q x
EOF
expect_flag "a pipe inside a command substitution inside double quotes" 1 <<'EOF'
v="$(echo "$x" | grep -q foo && echo y)"
EOF

# --- shapes that are not a pipe into an early-exit grep ----------------------
expect_clean "an || list" <<'EOF'
test -f x || grep -q foo file
EOF
expect_clean "a pipe inside single quotes" <<'EOF'
echo 'a | grep -q foo'
EOF
expect_clean "a pipe inside double quotes" <<'EOF'
echo "a | grep -q foo"
EOF
expect_clean "a comment line" <<'EOF'
# echo "$x" | grep -q foo
EOF
expect_clean "a trailing comment" <<'EOF'
echo "$x" # | grep -q foo
EOF
expect_clean "a heredoc body" <<'EOF'
cat <<DOC
echo "$x" | grep -q foo
DOC
EOF
# The fixture's leading tabs come from printf's \t, so this file stays space-indented.
# shellcheck disable=SC2016  # literal fixture source; nothing here should expand
expect_clean "a quoted, tab-stripped heredoc body" < <(printf 'cat <<-%sDOC%s\n\techo "$x" | grep -q foo\n\tDOC\n' "'" "'")
expect_clean "a here-string" <<'EOF'
grep -q foo <<<"$x"
EOF
expect_clean "a process substitution" <<'EOF'
grep -q foo < <(echo "$x")
EOF
expect_clean "grep -c" <<'EOF'
echo "$x" | grep -c foo
EOF
expect_clean "grep -e q" <<'EOF'
echo "$x" | grep -e q foo
EOF
expect_clean "grep -eq (q is the -e argument)" <<'EOF'
echo "$x" | grep -eq
EOF
expect_clean "-eq in [[ ]] beside a pipe" <<'EOF'
if [[ $x -eq 1 ]]; then echo "$x" | grep -c foo; fi
EOF
expect_clean "grep -q on a file with no pipe" <<'EOF'
grep -q foo file
EOF
expect_clean "a quoted pattern that is not an option" <<'EOF'
echo "$x" | grep "a -q b" file
EOF
expect_clean "a quoted -q given as the -e argument" <<'EOF'
echo "$x" | grep -e "-q"
EOF
expect_clean "a case pattern pipe inside \$( )" <<'EOF'
v="$(case $y in a|b) grep -c x f;; esac)"
EOF
expect_clean "a quoted pipe after \$( ) holding 'in case' arguments" <<'EOF'
v="$(echo in case you)"
echo "a | grep -q b"
EOF
expect_clean "an option after --" <<'EOF'
echo "$x" | grep -- -q
EOF

# --- the interface ------------------------------------------------------------
run_gate "$WORK/does-not-exist.sh"
if ((RC == 2)) && [[ -n "$ERR" && -z "$OUT" ]]; then
  ok "a missing file argument exits 2 with a diagnostic on stderr"
else
  fail "a missing file argument: wanted exit 2 on stderr only (rc=$RC, stdout='$OUT', stderr='$ERR')"
fi

# A default run that finds no scripts/ tree could not look, so it is not clean.
mkdir -p "$WORK/noscripts/bin"
cp "$SCRIPT" "$WORK/noscripts/bin/gate.sh"
run_gate_default() {
  RC=0
  bash "$WORK/noscripts/bin/gate.sh" >"$WORK/out" 2>"$WORK/err" || RC=$?
}
run_gate_default
if ((RC == 2)) && [[ ! -s "$WORK/out" ]]; then
  ok "a default run with no scripts/ tree exits 2"
else
  fail "a default run with no scripts/ tree: wanted exit 2 (rc=$RC, stdout='$(cat "$WORK/out")')"
fi

# A bare name shaped like var=value must still be read as a file, not as an awk
# variable assignment that would silently scan nothing.
mkdir -p "$WORK/eq"
# shellcheck disable=SC2016  # literal fixture source; nothing here should expand
printf '%s\n' 'echo "$x" | grep -q foo' >"$WORK/eq/a=b.sh"
RC=0
(cd "$WORK/eq" && bash "$SCRIPT" a=b.sh >"$WORK/out" 2>"$WORK/err") || RC=$?
if ((RC == 1)) && grep -q 'a=b.sh:1:' "$WORK/err"; then
  ok "a file argument shaped like var=value is scanned"
else
  fail "a var=value file argument was not scanned (rc=$RC, stderr='$(cat "$WORK/err")')"
fi

new_case <<'EOF'
echo "$x" | grep -q foo
echo "$x" | grep -q bar
EOF
run_gate "$CASE_FILE"
if ((RC == 1)) && [[ "$ERR" == *"$CASE_FILE:1: echo \"\$x\" | grep -q foo"* && "$ERR" == *"$CASE_FILE:2:"* && "$ERR" == *"2 piped early-exit grep"* ]]; then
  ok "each finding carries the trimmed source line, and the count is reported"
else
  fail "expected two findings with source text and a count (rc=$RC, stderr='$ERR')"
fi

# --- the gate and this suite are themselves clean ----------------------------
run_gate "$SCRIPT" "$SELF_DIR/check-pipefail-grep-q.test.sh"
if ((RC == 0)) && [[ -n "$OUT" ]]; then
  ok "the gate and its suite scan clean"
else
  fail "the gate or its suite carries a finding (rc=$RC, stderr='$ERR')"
fi

test_harness::report
