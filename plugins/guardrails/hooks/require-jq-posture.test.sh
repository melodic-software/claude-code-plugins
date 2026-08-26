#!/usr/bin/env bash
# Contract + behavioural test for the jq-gate POSTURE split (#2146).
#
# Two things are proven here, and the second is the one that matters:
#
#   1. MEMBERSHIP (static). A guardrails hook belongs to the fail-CLOSED class
#      iff it already fails closed on another "I cannot parse this input"
#      condition — today, a MAX_COMMAND_LEN ceiling. That criterion is applied
#      mechanically to every hook in this directory, so the class cannot drift:
#      a hook that grows a ceiling and keeps the fail-open gate fails here, and
#      so does a hook that adopts the blocking gate without one.
#
#   2. BEHAVIOUR (four cells, with controls). Running the guards with jq
#      genuinely unreachable, and asserting the ALLOW/DENY grid #2146 measured.
#      Two cells cannot distinguish "the guard was skipped" from "the harness
#      returns ALLOW for everything", so the jq-PRESENT column is the
#      discrimination control and an advisory hook is the posture control.
#
# HOW jq IS HIDDEN, AND WHY NOT BY TOUCHING PATH. A BASH_ENV file defines a
# `command` shell function that reports `jq` as absent and forwards every other
# lookup to the real builtin, plus a `jq` function that fails the way a missing
# binary does. BASH_ENV is sourced by every non-interactive bash spawned below,
# including the hook's own children, so the override covers the whole process
# tree. Every jq probe in hook-utils.sh is a `command -v jq`, so the override
# reaches all of them. PATH IS LEFT COMPLETELY INTACT, and that is not
# fastidiousness: stripping PATH directories also removes `git`, which these
# guards invoke, and a guard that cannot find git produces the SAME answer for
# an entirely unrelated reason. Three separate attempts at this measurement were
# invalid for exactly that, and each produced the answer the tester was hoping
# for. So the precondition block below asserts, INSIDE the hidden environment:
#
#     jq=hidden  git=visible  bash=visible  path-to-jq=intact
#
# and refuses to read a single verdict until all four hold. `path-to-jq=intact`
# is `builtin command -v jq` still resolving — proof that the LOOKUP was hidden
# and the tool itself was not removed.
#
# lib/hook-utils.test.sh and require-jq-notice-isolation.test.sh both record
# that real jq-removal "is not portably simulable" via an isolated bin dir
# (which cannot host bash + coreutils across Git Bash and Linux). That is true
# of the bin-dir approach, and is exactly why this one overrides the lookup.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# guardrails-test-helpers.sh has no equality primitive (it is built around
# assert_exit / assert_contains / assert_absent). A local wrapper over ok/bad
# rather than a change to the shared, cross-plugin-duplicated helper file for
# one suite's convenience.
assert_eq() {
  if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1: expected '$2', got '$3'"; fi
}

# ============================================================================
# Part 1 — membership, derived not hand-listed
# ============================================================================

FAIL_CLOSED=()
FAIL_OPEN=()
for f in "$HOOK_DIR"/*.sh; do
  base="${f##*/}"
  case "$base" in
  hook-utils.sh | guardrails-test-helpers.sh | resolve-convention-pattern.sh | *.test.sh) continue ;;
  *) ;;
  esac
  grep -q 'hook::require_jq' "$f" 2>/dev/null || continue
  if grep -qE '^MAX_COMMAND_LEN=' "$f"; then
    FAIL_CLOSED+=("$base")
  else
    FAIL_OPEN+=("$base")
  fi
done

if ((${#FAIL_CLOSED[@]} < 2)); then
  bad "expected at least 2 hooks in the fail-closed class (a MAX_COMMAND_LEN ceiling), found ${#FAIL_CLOSED[@]}"
else
  ok "the #2146 membership criterion selects ${#FAIL_CLOSED[@]} fail-closed hook(s): ${FAIL_CLOSED[*]}"
fi
if ((${#FAIL_OPEN[@]} < 2)); then
  bad "expected at least 2 fail-open hooks to contrast against, found ${#FAIL_OPEN[@]}"
else
  ok "and leaves ${#FAIL_OPEN[@]} hook(s) fail-open: ${FAIL_OPEN[*]}"
fi

for base in "${FAIL_CLOSED[@]}"; do
  f="$HOOK_DIR/$base"
  if grep -qE 'hook::require_jq_blocking[[:space:]]' "$f"; then
    ok "$base (already fails closed on command length) uses hook::require_jq_blocking"
  else
    bad "$base defines MAX_COMMAND_LEN but does not call hook::require_jq_blocking — two opposite postures toward an unparsable input in one script is the defect #2146 reports"
  fi
  if grep -qE 'hook::require_jq[[:space:]]' "$f"; then
    bad "$base also calls the fail-OPEN hook::require_jq; the blocking gate must be the only jq gate in a fail-closed guard"
  else
    ok "$base does not also carry the fail-open gate"
  fi
done

for base in "${FAIL_OPEN[@]}"; do
  f="$HOOK_DIR/$base"
  if grep -qE 'hook::require_jq_blocking[[:space:]]' "$f"; then
    bad "$base adopted the fail-CLOSED jq gate without a MAX_COMMAND_LEN ceiling — it is not in the class the #2146 criterion defines; widen the criterion at hook::require_jq_blocking first"
  fi
done
ok "no advisory hook adopted the fail-closed gate (${#FAIL_OPEN[@]} checked)"

# The reasoning must live AT THE HELPER, not only at the call sites (#2146).
UTILS_SRC="$(cat "$HOOK_DIR/hook-utils.sh")"
for needle in "TWO POSTURES" "hook::require_jq_blocking" "MAX_COMMAND_LEN"; do
  assert_contains "hook-utils.sh's posture block mentions '$needle'" "$UTILS_SRC" "$needle"
done

# ============================================================================
# Part 2 — the jq-hidden environment, and its preconditions
# ============================================================================

HIDE_JQ="$TEST_TMPDIR/hide-jq.sh"
cat >"$HIDE_JQ" <<'HIDEEOF'
# Sourced via BASH_ENV by every non-interactive bash below. Hides the LOOKUP of
# jq without touching PATH: `command -v jq` reports absence, a direct `jq` call
# fails the way a missing binary does, and every other lookup — git, bash, grep
# — forwards to the real builtin untouched.
command() {
  local a
  for a in "$@"; do
    if [[ "$a" == "jq" ]]; then
      return 1
    fi
  done
  builtin command "$@"
}
jq() {
  echo "bash: jq: command not found" >&2
  return 127
}
HIDEEOF

PRECHECK="$TEST_TMPDIR/precheck.sh"
cat >"$PRECHECK" <<'PREEOF'
jq_state=visible
command -v jq >/dev/null 2>&1 || jq_state=hidden
git_state=missing
command -v git >/dev/null 2>&1 && git_state=visible
bash_state=missing
command -v bash >/dev/null 2>&1 && bash_state=visible
path_state=broken
builtin command -v jq >/dev/null 2>&1 && path_state=intact
printf 'jq=%s git=%s bash=%s path-to-jq=%s\n' "$jq_state" "$git_state" "$bash_state" "$path_state"
PREEOF

PRECOND="$(BASH_ENV="$HIDE_JQ" bash "$PRECHECK" 2>/dev/null)"
echo
echo "PRECONDITION (measured inside the jq-hidden environment): $PRECOND"
echo

JQ_HIDING_WORKS=1
if [[ "$PRECOND" != "jq=hidden git=visible bash=visible path-to-jq=intact" ]]; then
  JQ_HIDING_WORKS=0
  bad "jq-hidden environment did not establish its preconditions ($PRECOND) — every behavioural cell below would be unreadable, so none is reported"
else
  ok "precondition: jq=hidden git=visible bash=visible path-to-jq=intact (PATH untouched; the LOOKUP is what was hidden)"
fi

# A second, independent proof that the hiding reaches the code under test: run
# the gate's OWN predicate, sourced from the real hook-utils.sh, inside the
# hidden environment. If jq leaked through, this is where it shows.
if ((JQ_HIDING_WORKS)); then
  PREDICATE="$TEST_TMPDIR/predicate.sh"
  {
    printf 'source "%s/hook-utils.sh"\n' "$HOOK_DIR"
    printf 'if command -v jq >/dev/null 2>&1; then echo GATE-SEES-JQ; else echo GATE-SEES-NO-JQ; fi\n'
  } >"$PREDICATE"
  gate_view="$(BASH_ENV="$HIDE_JQ" bash "$PREDICATE" 2>/dev/null)"
  assert_eq "the jq gate's own predicate reports jq absent inside the hidden environment" \
    "GATE-SEES-NO-JQ" "$gate_view"
  # ...and reports it PRESENT without the override, so the predicate itself is
  # not simply always-false.
  gate_view_plain="$(bash "$PREDICATE" 2>/dev/null)"
  assert_eq "control — the same predicate reports jq PRESENT without the override" \
    "GATE-SEES-JQ" "$gate_view_plain"
fi

# ============================================================================
# Part 3 — the four cells (plus controls)
# ============================================================================
#
# The hook is a pure decision function: a payload on stdin, a verdict as an exit
# code. Nothing is executed, so every cell is read-only by construction.
# EXIT CODES: 2 = DENY (PreToolUse blocks the tool call), 0 = ALLOW.

WORKDIR="$TEST_TMPDIR/work"
mkdir -p "$WORKDIR"
git init -q "$WORKDIR" 2>/dev/null || bad "fixture: could not create the working repository"

# payload <command> — a PreToolUse Bash payload, hand-built rather than composed
# with the helpers' jq builders, because jq is exactly what half these cells
# do not have.
payload() {
  local cmd="${1//\\/\\\\}"
  cmd="${cmd//\"/\\\"}"
  printf '{"session_id":"jq-posture-test","tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' \
    "$cmd" "$WORKDIR"
}

# verdict <hook> <command> <show|hide> [stderr-file] -> prints DENY or ALLOW
verdict() {
  local hook="$1" cmd="$2" hide="$3" errfile="${4:-/dev/null}" rc
  if [[ "$hide" == "hide" ]]; then
    (cd "$WORKDIR" && BASH_ENV="$HIDE_JQ" CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-$RANDOM" \
      bash "$HOOK_DIR/$hook" <<<"$(payload "$cmd")" >/dev/null 2>"$errfile")
  else
    (cd "$WORKDIR" && CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-$RANDOM" \
      bash "$HOOK_DIR/$hook" <<<"$(payload "$cmd")" >/dev/null 2>"$errfile")
  fi
  rc=$?
  if ((rc == 2)); then printf 'DENY'; else printf 'ALLOW'; fi
}

DANGEROUS="git push --force origin main"
SAFE="git status --short"
BYPASS="git commit --no-verify -m x"

if ((JQ_HIDING_WORKS)); then
  echo "--- four cells: block-dangerous-git.sh ---"
  c_dang_present="$(verdict block-dangerous-git.sh "$DANGEROUS" show)"
  c_safe_present="$(verdict block-dangerous-git.sh "$SAFE" show)"
  ERR_HIDDEN="$TEST_TMPDIR/dang-hidden.err"
  c_dang_hidden="$(verdict block-dangerous-git.sh "$DANGEROUS" hide "$ERR_HIDDEN")"
  c_safe_hidden="$(verdict block-dangerous-git.sh "$SAFE" hide)"
  printf '                       jq PRESENT   jq HIDDEN\n'
  printf '    dangerous push     %-12s %s\n' "$c_dang_present" "$c_dang_hidden"
  printf '    safe command       %-12s %s\n' "$c_safe_present" "$c_safe_hidden"
  echo

  # The discrimination control FIRST: without it a uniformly-DENY harness would
  # read as a working guard.
  assert_eq "control — jq PRESENT, safe command: ALLOW (the harness discriminates)" \
    "ALLOW" "$c_safe_present"
  assert_eq "jq PRESENT, dangerous push: DENY" \
    "DENY" "$c_dang_present"
  assert_eq "jq HIDDEN, dangerous push: DENY (was ALLOW before #2146 — the reported defect)" \
    "DENY" "$c_dang_hidden"
  assert_eq "jq HIDDEN, safe command: DENY (the disclosed cost — a guard that cannot read the command cannot exempt it)" \
    "DENY" "$c_safe_hidden"

  # PROOF THE DENY CAME FROM THE NEW PATH, not from some unrelated failure.
  hidden_err="$(cat "$ERR_HIDDEN" 2>/dev/null)"
  assert_contains "the jq-hidden denial names jq as the missing prerequisite" \
    "$hidden_err" "jq"
  assert_contains "the jq-hidden denial points at the documented install route" \
    "$hidden_err" "https://jqlang.org/download/"
  assert_contains "the jq-hidden denial names the kill switch that bypasses it" \
    "$hidden_err" "block_dangerous_git_enabled"
  assert_absent "the jq-hidden denial is NOT the fail-open skip notice" \
    "$hidden_err" "hook skipped for this session"

  echo "--- four cells: block-no-verify.sh ---"
  n_bypass_present="$(verdict block-no-verify.sh "$BYPASS" show)"
  n_safe_present="$(verdict block-no-verify.sh "$SAFE" show)"
  ERR_NV="$TEST_TMPDIR/nv-hidden.err"
  n_bypass_hidden="$(verdict block-no-verify.sh "$BYPASS" hide "$ERR_NV")"
  n_safe_hidden="$(verdict block-no-verify.sh "$SAFE" hide)"
  printf '                       jq PRESENT   jq HIDDEN\n'
  printf '    commit --no-verify %-12s %s\n' "$n_bypass_present" "$n_bypass_hidden"
  printf '    safe command       %-12s %s\n' "$n_safe_present" "$n_safe_hidden"
  echo

  assert_eq "control — jq PRESENT, safe command: ALLOW (the harness discriminates)" \
    "ALLOW" "$n_safe_present"
  assert_eq "jq PRESENT, commit --no-verify: DENY" \
    "DENY" "$n_bypass_present"
  assert_eq "jq HIDDEN, commit --no-verify: DENY (was ALLOW before #2146)" \
    "DENY" "$n_bypass_hidden"
  assert_eq "jq HIDDEN, safe command: DENY (the disclosed cost)" \
    "DENY" "$n_safe_hidden"
  assert_contains "block-no-verify's jq-hidden denial names its own kill switch" \
    "$(cat "$ERR_NV" 2>/dev/null)" "block_no_verify_enabled"

  # --- POSTURE CONTROL: an advisory guard must be UNCHANGED ------------------
  # The cell that proves the change is SCOPED, and the harness's second control:
  # if hiding jq had broken the environment generally, these would deny too.
  echo "--- posture control: the advisory hooks still fail OPEN ---"
  checked_advisory=0
  for advisory in "${FAIL_OPEN[@]}"; do
    case "$advisory" in
    block-hook-bypass.sh | block-noncanonical-commit.sh | block-convention-violation.sh) ;;
    *) continue ;;
    esac
    checked_advisory=$((checked_advisory + 1))
    a_present="$(verdict "$advisory" "$SAFE" show)"
    ERR_ADV="$TEST_TMPDIR/adv-$advisory.err"
    a_hidden="$(verdict "$advisory" "$SAFE" hide "$ERR_ADV")"
    printf '    %-32s jq PRESENT=%-6s jq HIDDEN=%s\n' "$advisory" "$a_present" "$a_hidden"
    assert_eq "control — $advisory allows a safe command with jq present" "ALLOW" "$a_present"
    assert_eq "control — $advisory still fails OPEN with jq hidden (posture unchanged)" \
      "ALLOW" "$a_hidden"
    assert_absent "control — $advisory does not emit the fail-closed denial" \
      "$(cat "$ERR_ADV" 2>/dev/null)" "This guard blocks irreversible operations"
  done
  if ((checked_advisory == 0)); then
    bad "no advisory hook was exercised as a posture control — the scoping claim is unmeasured"
  fi

  # --- The kill switch still wins on a jq-less machine ------------------------
  # Fail-closed must not mean unbypassable: hook::check_enabled runs before the
  # gate, so a consumer who deliberately turns the guard off is not trapped.
  ks_rc=0
  (cd "$WORKDIR" && BASH_ENV="$HIDE_JQ" CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ENABLED=false \
    CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-ks" \
    bash "$HOOK_DIR/block-dangerous-git.sh" <<<"$(payload "$DANGEROUS")" >/dev/null 2>&1) || ks_rc=$?
  assert_exit "the kill switch still bypasses the guard with jq hidden (fail-closed is not a trap)" \
    0 "$ks_rc"
fi

report
