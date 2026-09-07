#!/usr/bin/env bash
# Black-box contract test for compose-statusline-wiring.sh.
#
# Cases 1-8 are the eight eval cases the two statusline guard setup skills used
# to check by having the model hand-execute the peel and wrap arithmetic. Each
# carries the eval-case name it replaces, so a reader can move between the two
# in either direction:
#
#   1  composes-without-double-wrapping
#   2  rerun-does-not-compound-the-sh-c-wrap
#   3  genuine-sh-c-renderer-is-not-peeled
#   4  multiple-generated-layers-collapse-in-one-run
#   5  adapter-hiding-a-sibling-shim-is-peeled
#   6  bare-builtin-renderer-gets-a-shell
#   7  shell-syntax-sealed-inside-quotes-is-not-a-trigger
#   8  bare-quoting-is-not-a-wrap-trigger
#
# Cases 9 onward cover the contract the eval cases never reached: the refusal
# branches, the JSON input and output shapes, the legacy tee prefix, and the
# idempotency invariant over every composed value in the table.
#
# Every expected value is written as a LITERAL. Nothing here recomputes the
# escape the script performs, so a bug in that escape cannot be reproduced by
# the assertion and pass. Inside double quotes a backslash before a single
# quote stays literal, which is why the `'\''` sequences below read as they do.
#
# Command words are chosen from host-stable classes only: `ulimit` (a builtin
# on every POSIX shell and never a file on PATH), `sh` (always an executable),
# and `my-statusline` / `my-renderer` (names no host has). `echo`, `printf`,
# and `test` are deliberately avoided; each is both a builtin and a file on
# PATH, so the not-an-executable trigger would resolve differently per host.
#
# Self-contained: defines its own assertion helpers. Installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="$SCRIPT_DIR/compose-statusline-wiring.sh"

PASS=0
FAIL=0

ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

bad() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

assert_eq() { # <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    ok "$1"
  else
    bad "$1
  expected: $2
  actual:   $3"
  fi
}

assert_status() { # <label> <expected-status> <actual-status>
  if [[ "$2" == "$3" ]]; then
    ok "$1"
  else
    bad "$1 (expected exit $2, got exit $3)"
  fi
}

assert_contains() { # <label> <needle> <haystack>
  if [[ "$3" == *"$2"* ]]; then
    ok "$1"
  else
    bad "$1
  missing: $2
  in:      $3"
  fi
}

count_occurrences() { # <needle> <haystack>
  local needle="$1" rest="$2" n=0
  while [[ "$rest" == *"$needle"* ]]; do
    rest="${rest#*"$needle"}"
    n=$((n + 1))
  done
  printf '%s' "$n"
}

assert_count() { # <label> <expected-count> <needle> <haystack>
  local actual
  actual="$(count_occurrences "$3" "$4")"
  if [[ "$2" == "$actual" ]]; then
    ok "$1"
  else
    bad "$1 (expected $2 occurrences of '$3', got $actual in: $4)"
  fi
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

CG="bash ~/.claude/context-guard/bin/statusline-shim.sh"
RLG="bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh"

OUT=""
ERR=""
STATUS=0

# compose_cmd <command-string> <wrap...> : run with --command-only, capturing
# stdout in OUT, stderr in ERR, and the exit code in STATUS.
compose_cmd() {
  local cmd="$1"
  shift
  local args=(--command "$cmd" --command-only)
  local w
  for w in "$@"; do
    args+=(--wrap "$w")
  done
  ERR="$(bash "$COMPOSE" "${args[@]}" 2>&1 >"$WORK/out")"
  STATUS=$?
  OUT="$(cat "$WORK/out")"
  # The script's documented codes are 0-4. Anything above that is the process
  # failing to run at all, so say so rather than letting an empty OUT surface as
  # an ordinary value mismatch.
  if [[ $STATUS -gt 4 ]]; then
    bad "harness: the script process exited $STATUS, outside its documented 0-4 range (stderr: $ERR)"
  fi
}

# --- 1. composes-without-double-wrapping -------------------------------------
# The sibling shim already wraps the operator's renderer. The peel recovers the
# renderer, and the composed wiring names each shim exactly once.

compose_cmd "bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh ~/.claude/statusline/render.sh" "$CG" "$RLG"
assert_status "1 composes-without-double-wrapping: exits 0" 0 "$STATUS"
assert_eq "1 composes-without-double-wrapping: each shim once, renderer unwrapped" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh ~/.claude/statusline/render.sh" \
  "$OUT"
assert_count "1 composes-without-double-wrapping: sibling shim appears exactly once" \
  1 "rate-limit-guard/bin/statusline-shim.sh" "$OUT"

# --- 2. rerun-does-not-compound-the-sh-c-wrap --------------------------------
# Wiring this script already produced, fed back in, comes out byte-identical:
# one shim invocation and exactly one sh -c layer.

compose_cmd "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'THEME=dark my-statusline --flag'" "$CG"
assert_status "2 rerun-does-not-compound-the-sh-c-wrap: exits 0" 0 "$STATUS"
assert_eq "2 rerun-does-not-compound-the-sh-c-wrap: output is byte-identical to the input" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'THEME=dark my-statusline --flag'" \
  "$OUT"
assert_count "2 rerun-does-not-compound-the-sh-c-wrap: exactly one sh -c layer" \
  1 "sh -c " "$OUT"

# --- 3. genuine-sh-c-renderer-is-not-peeled ----------------------------------
# The carried string has no unquoted top-level syntax and is not itself an
# adapter or a shim prefix, so the sh -c is the operator's own and survives.
# Peeling it would leave the shim exec-ing a builtin with no shell (exit 127).

compose_cmd "sh -c 'ulimit -n'" "$CG"
assert_status "3 genuine-sh-c-renderer-is-not-peeled: exits 0" 0 "$STATUS"
assert_eq "3 genuine-sh-c-renderer-is-not-peeled: the operator's sh -c is preserved verbatim" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'ulimit -n'" \
  "$OUT"
assert_count "3 genuine-sh-c-renderer-is-not-peeled: exactly one sh -c layer" \
  1 "sh -c " "$OUT"

# --- 4. multiple-generated-layers-collapse-in-one-run ------------------------
# Three layers (shim, nested adapter, syntax-carrying adapter) come off in ONE
# invocation. Stopping after a single peel would leave a layer behind.

compose_cmd "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'sh -c '\''THEME=dark my-statusline'\'''" "$CG"
assert_status "4 multiple-generated-layers-collapse-in-one-run: exits 0" 0 "$STATUS"
assert_eq "4 multiple-generated-layers-collapse-in-one-run: one shim, one sh -c layer" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'THEME=dark my-statusline'" \
  "$OUT"

ERR="$(bash "$COMPOSE" --command "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'sh -c '\''THEME=dark my-statusline'\'''" \
  --command-only --explain --wrap "$CG" 2>&1 >/dev/null)"
assert_contains "4 multiple-generated-layers-collapse-in-one-run: all three layers peeled in one pass" \
  "layers-peeled: 3" "$ERR"
assert_contains "4 multiple-generated-layers-collapse-in-one-run: renderer recovered byte-for-byte" \
  "renderer: THEME=dark my-statusline" "$ERR"

# --- 5. adapter-hiding-a-sibling-shim-is-peeled ------------------------------
# The carried string has no unquoted top-level syntax, but it BEGINS with a
# shim prefix, which is a shape no setup skill emits inside an adapter. Peeling
# exposes that shim to rule 1, so it is named once rather than twice.

compose_cmd "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh my-renderer --format '\''a b'\'''" "$CG" "$RLG"
assert_status "5 adapter-hiding-a-sibling-shim-is-peeled: exits 0" 0 "$STATUS"
assert_eq "5 adapter-hiding-a-sibling-shim-is-peeled: sealed shim exposed and composed once" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh my-renderer --format 'a b'" \
  "$OUT"
assert_count "5 adapter-hiding-a-sibling-shim-is-peeled: sibling shim appears exactly once" \
  1 "rate-limit-guard/bin/statusline-shim.sh" "$OUT"
assert_count "5 adapter-hiding-a-sibling-shim-is-peeled: no sh -c layer survives" \
  0 "sh -c " "$OUT"

# --- 6. bare-builtin-renderer-gets-a-shell -----------------------------------
# No shell syntax at all, but the command word resolves as a builtin, so the
# plain wrapped form would reach `exec ulimit` and die with 127 every refresh.

compose_cmd "ulimit '-n'" "$CG"
assert_status "6 bare-builtin-renderer-gets-a-shell: exits 0" 0 "$STATUS"
assert_eq "6 bare-builtin-renderer-gets-a-shell: shell-wrapped variant with the quotes escaped" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'ulimit '\''-n'\'''" \
  "$OUT"

ERR="$(bash "$COMPOSE" --command "ulimit '-n'" --command-only --explain --wrap "$CG" 2>&1 >/dev/null)"
assert_contains "6 bare-builtin-renderer-gets-a-shell: fires on the not-an-executable trigger" \
  "wrap: shell (command word is a builtin, not an executable)" "$ERR"

# --- 7. shell-syntax-sealed-inside-quotes-is-not-a-trigger -------------------
# --- 8. bare-quoting-is-not-a-wrap-trigger -----------------------------------
# One input, two eval-case names: the pipe is sealed inside a quoted argument,
# so it is one ordinary ARGV word and the quoting alone is never a trigger.

compose_cmd "my-statusline --format 'a | b'" "$CG"
assert_status "7 shell-syntax-sealed-inside-quotes-is-not-a-trigger: exits 0" 0 "$STATUS"
assert_eq "7 shell-syntax-sealed-inside-quotes-is-not-a-trigger: plain wrapped form, no adapter" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh my-statusline --format 'a | b'" \
  "$OUT"

ERR="$(bash "$COMPOSE" --command "my-statusline --format 'a | b'" --command-only --explain --wrap "$CG" 2>&1 >/dev/null)"
assert_contains "8 bare-quoting-is-not-a-wrap-trigger: the wrap decision is plain, with its reason" \
  "wrap: plain (command word resolves as an executable)" "$ERR"
assert_contains "8 bare-quoting-is-not-a-wrap-trigger: the idempotency check is reported" \
  "idempotent: yes" "$ERR"
assert_contains "8 bare-quoting-is-not-a-wrap-trigger: nothing was peeled" \
  "layers-peeled: 0" "$ERR"
assert_count "8 bare-quoting-is-not-a-wrap-trigger: no sh -c layer" 0 "sh -c " "$OUT"

# --- 9. an unquoted top-level control operator does need an adapter ----------
# The complement of cases 7 and 8: the same pipe, unquoted, cannot be an ARGV
# word, so the adapter is mandatory.

compose_cmd "my-statusline | my-filter" "$CG"
assert_status "9 unquoted pipe: exits 0" 0 "$STATUS"
assert_eq "9 unquoted pipe: shell-wrapped variant" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'my-statusline | my-filter'" \
  "$OUT"

compose_cmd "(printf hi)" "$CG"
assert_status "9 grouped command: exits 0" 0 "$STATUS"
assert_eq "9 grouped command: shell-wrapped variant" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c '(printf hi)'" \
  "$OUT"

compose_cmd "! false" "$CG"
assert_status "9 keyword bang: exits 0" 0 "$STATUS"
assert_eq "9 keyword bang: shell-wrapped variant" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c '! false'" \
  "$OUT"

compose_cmd "[[ -f file ]]" "$CG"
assert_status "9 keyword [[: exits 0" 0 "$STATUS"
assert_eq "9 keyword [[: shell-wrapped variant" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c '[[ -f file ]]'" \
  "$OUT"

# --- 10. no statusLine configured composes the standalone wiring -------------

compose_cmd "" "$CG"
assert_status "10 empty command: exits 0" 0 "$STATUS"
assert_eq "10 empty command: standalone wiring is the shim and nothing else" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh" "$OUT"

compose_cmd "bash ~/.claude/context-guard/bin/statusline-shim.sh" "$CG"
assert_eq "10 shim-only wiring re-composes to itself" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh" "$OUT"

# --- 11. the legacy version-pinned tee prefix is peeled, never re-composed ---

compose_cmd "bash \"~/.claude/plugins/cache/melodic-software/context-guard/0.1.0/scripts/statusline-tee.sh\" ~/.claude/statusline/render.sh" "$CG"
assert_status "11 legacy tee prefix: exits 0" 0 "$STATUS"
assert_eq "11 legacy tee prefix: peeled and replaced by the durable shim path" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh ~/.claude/statusline/render.sh" \
  "$OUT"
assert_count "11 legacy tee prefix: the tee is not carried into the composed wiring" \
  0 "statusline-tee.sh" "$OUT"

# --- 12. a renderer carrying substitution syntax never reaches a shell -------
# The escape and its round-trip check are pure string work, so `$(...)` in the
# operator's own renderer survives verbatim instead of being expanded.

compose_cmd "THEME=\$(date +%H) my-statusline" "$CG"
assert_status "12 substitution syntax: exits 0" 0 "$STATUS"
assert_eq "12 substitution syntax: carried verbatim into the adapter, never expanded" \
  "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'THEME=\$(date +%H) my-statusline'" \
  "$OUT"

# --- 13. refusal: no --wrap prefix -------------------------------------------

ERR="$(bash "$COMPOSE" --command "my-statusline" --command-only 2>&1 >"$WORK/out")"
STATUS=$?
assert_status "13 refusal: missing --wrap exits 2" 2 "$STATUS"
assert_contains "13 refusal: missing --wrap names the missing argument" "--wrap" "$ERR"
assert_eq "13 refusal: missing --wrap prints nothing on stdout" "" "$(cat "$WORK/out")"

# --- 14. refusal: a --wrap prefix the peel would not recognize ---------------
# An unrecognized prefix would survive the peel on the next run and stack a
# fresh layer, which is the compounding the peel rules exist to prevent.

ERR="$(bash "$COMPOSE" --command "my-statusline" --command-only --wrap "my-wrapper" 2>&1 >/dev/null)"
STATUS=$?
assert_status "14 refusal: a non-shim --wrap prefix exits 2" 2 "$STATUS"
assert_contains "14 refusal: a non-shim --wrap prefix says what the prefix must be" \
  "statusline-shim.sh" "$ERR"

ERR="$(bash "$COMPOSE" --command "my-statusline" --command-only \
  --wrap "bash ~/.claude/context-guard/bin/statusline-tee.sh" 2>&1 >/dev/null)"
STATUS=$?
assert_status "14 refusal: a legacy tee --wrap prefix exits 2" 2 "$STATUS"

ERR="$(bash "$COMPOSE" --command "my-statusline" --command-only --wrap "sh -c 'x'" 2>&1 >/dev/null)"
STATUS=$?
assert_status "14 refusal: a three-word --wrap prefix exits 2" 2 "$STATUS"

# --- 15. refusal: unbalanced quoting in the current command ------------------

ERR="$(bash "$COMPOSE" --command "my-statusline --format 'a" --command-only --wrap "$CG" 2>&1 >/dev/null)"
STATUS=$?
assert_status "15 refusal: unbalanced quoting exits 3" 3 "$STATUS"
assert_contains "15 refusal: unbalanced quoting names the reason on one line" \
  "unbalanced quoting" "$ERR"

# --- 16. refusal: unknown argument -------------------------------------------

ERR="$(bash "$COMPOSE" --command "my-statusline" --command-only --wrap "$CG" --nope 2>&1 >/dev/null)"
STATUS=$?
assert_status "16 refusal: an unknown argument exits 2" 2 "$STATUS"
assert_contains "16 refusal: an unknown argument is named" "--nope" "$ERR"

# --- 17. JSON input and output shapes ----------------------------------------

if command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"type":"command","command":"my-statusline --format '"'"'a | b'"'"'","padding":0}' >"$WORK/statusline.json"

  OUT="$(bash "$COMPOSE" --input "$WORK/statusline.json" --wrap "$CG" 2>"$WORK/err")"
  STATUS=$?
  assert_status "17 JSON object input: exits 0" 0 "$STATUS"
  assert_eq "17 JSON object input: the composed command is the plain wrapped form" \
    "bash ~/.claude/context-guard/bin/statusline-shim.sh my-statusline --format 'a | b'" \
    "$(printf '%s' "$OUT" | jq -r '.command')"
  assert_eq "17 JSON object input: unrecognized keys are preserved" \
    "0" "$(printf '%s' "$OUT" | jq -r '.padding')"
  assert_eq "17 JSON object input: type stays command" \
    "command" "$(printf '%s' "$OUT" | jq -r '.type')"

  OUT="$(printf '%s' '"my-statusline"' | bash "$COMPOSE" --wrap "$CG" 2>/dev/null)"
  assert_eq "17 JSON string input on stdin: composed" \
    "bash ~/.claude/context-guard/bin/statusline-shim.sh my-statusline" \
    "$(printf '%s' "$OUT" | jq -r '.command')"

  OUT="$(printf '%s' 'null' | bash "$COMPOSE" --wrap "$CG" --block 2>/dev/null)"
  assert_eq "17 JSON null input with --block: standalone wiring in a settings fragment" \
    "bash ~/.claude/context-guard/bin/statusline-shim.sh" \
    "$(printf '%s' "$OUT" | jq -r '.statusLine.command')"

  OUT="$(printf '%s' '' | bash "$COMPOSE" --wrap "$CG" 2>/dev/null)"
  assert_eq "17 empty stdin reads as no statusline configured" \
    "bash ~/.claude/context-guard/bin/statusline-shim.sh" \
    "$(printf '%s' "$OUT" | jq -r '.command')"

  ERR="$(printf '%s' '{not json' | bash "$COMPOSE" --wrap "$CG" 2>&1 >/dev/null)"
  STATUS=$?
  assert_status "17 refusal: invalid JSON exits 3" 3 "$STATUS"
  assert_contains "17 refusal: invalid JSON names the reason" "not valid JSON" "$ERR"

  ERR="$(printf '%s' '[1,2]' | bash "$COMPOSE" --wrap "$CG" 2>&1 >/dev/null)"
  STATUS=$?
  assert_status "17 refusal: a JSON array is not a statusLine value" 3 "$STATUS"

  ERR="$(printf '%s' '{"command":5}' | bash "$COMPOSE" --wrap "$CG" 2>&1 >/dev/null)"
  STATUS=$?
  assert_status "17 refusal: a non-string .command exits 3" 3 "$STATUS"
else
  echo "skip: jq not on PATH, JSON input and output cases not run" >&2
fi

# --- 18. idempotency over the whole table ------------------------------------
# Feeding any composed value back through the script has to reproduce it byte
# for byte. This is the property the script's own second pass asserts; running
# it from outside proves the assertion is not vacuous.

idempotent_case() { # <label> <command> <wrap...>
  local label="$1" cmd="$2"
  shift 2
  compose_cmd "$cmd" "$@"
  if [[ $STATUS -ne 0 ]]; then
    bad "18 idempotency ($label): first compose exited $STATUS"
    return
  fi
  local once="$OUT"
  compose_cmd "$once" "$@"
  if [[ $STATUS -ne 0 ]]; then
    bad "18 idempotency ($label): second compose exited $STATUS"
    return
  fi
  assert_eq "18 idempotency ($label): re-composing is byte-identical" "$once" "$OUT"
}

idempotent_case "sibling shim" "bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh ~/.claude/statusline/render.sh" "$CG" "$RLG"
idempotent_case "generated adapter" "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'THEME=dark my-statusline --flag'" "$CG"
idempotent_case "operator sh -c" "sh -c 'ulimit -n'" "$CG"
idempotent_case "stacked layers" "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'sh -c '\''THEME=dark my-statusline'\'''" "$CG"
idempotent_case "sealed sibling shim" "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c 'bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh my-renderer --format '\''a b'\'''" "$CG" "$RLG"
idempotent_case "builtin renderer" "ulimit '-n'" "$CG"
idempotent_case "quoted pipe" "my-statusline --format 'a | b'" "$CG"
idempotent_case "unquoted pipe" "my-statusline | my-filter" "$CG"
idempotent_case "grouped command" "(printf hi)" "$CG"
idempotent_case "keyword bang" "! false" "$CG"
idempotent_case "keyword conditional" "[[ -f file ]]" "$CG"
idempotent_case "no statusline" "" "$CG"
idempotent_case "legacy tee" "bash \"~/.claude/plugins/cache/melodic-software/context-guard/0.1.0/scripts/statusline-tee.sh\" ~/.claude/statusline/render.sh" "$CG"

# --- 19. --help prints the contract and exits 0 ------------------------------

OUT="$(bash "$COMPOSE" --help 2>/dev/null)"
STATUS=$?
assert_status "19 --help exits 0" 0 "$STATUS"
assert_contains "19 --help documents the exit codes" "EXIT CODES" "$OUT"
assert_contains "19 --help documents the arguments" "--wrap <prefix>" "$OUT"

# --- summary -----------------------------------------------------------------

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]
