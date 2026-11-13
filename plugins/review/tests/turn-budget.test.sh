#!/usr/bin/env bash
# Offline test of the turn budget and checkpoint contract of the reviewer
# agents that write a findings file: derives that set from the agent
# definitions, checks each one's stated cap, stop turn and sentinel, and checks
# that every caller of the contract names the same sentinel. Reads files only.
# test-scope: plugins/review/agents/*.md plugins/review/reference/reviewer-handback.md plugins/review/skills/quality-gate/context/*.md plugins/review/workflows/fanout-sweep.js
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS="$PLUGIN_DIR/agents"
SENTINEL='Coverage: in progress'
# Turns kept back for the final write and the reply.
RESERVE=6

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_contains() {
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "expected to contain: $3" ;; esac
}

# One pass per agent file. Prints key=value facts:
#   tools, cap            frontmatter tools and maxTurns
#   handback              1 when the Handback section names a `Findings path:` line
#   budget                1 when a `## Turn budget` section exists
#   budget_cap            the integer after `maxTurns:` in that section
#   stop                  N from `Stop gathering by turn N`
#   sentinel              1 when the body names the checkpoint sentinel
#   out_criteria/out_coverage  1 when Output format names `Criteria read:` / `Coverage:`
#   never                 1 when a Handback line naming the sentinel also names `No findings.`
facts() {
  awk -v s="$SENTINEL" '
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm && /^---[[:space:]]*$/ { fm = 0; next }
    fm && /^tools:/ { v = $0; sub(/^tools:[[:space:]]*/, "", v); gsub(/"/, "", v); print "tools=" v; next }
    fm && /^maxTurns:/ { print "cap=" $2 + 0; next }
    fm { next }
    /^## / { sec = substr($0, 4); if (sec == "Turn budget") print "budget=1"; next }
    index($0, s) { print "sentinel=1" }
    sec == "Turn budget" && match($0, /maxTurns: [0-9]+/) { print "budget_cap=" substr($0, RSTART + 10, RLENGTH - 10) + 0 }
    sec == "Turn budget" && match($0, /Stop gathering by turn [0-9]+/) { print "stop=" substr($0, RSTART + 23, RLENGTH - 23) + 0 }
    sec == "Output format" && index($0, "Criteria read:") { print "out_criteria=1" }
    sec == "Output format" && index($0, "Coverage:") { print "out_coverage=1" }
    sec == "Handback" && index($0, "Findings path:") { print "handback=1" }
    sec == "Handback" && index($0, s) && index($0, "No findings.") { print "never=1" }
  ' "$1"
}

# get <facts> <key>: the value of key, empty when absent.
get() { [[ $1 =~ (^|$'\n')$2=([^$'\n']*) ]] && printf '%s' "${BASH_REMATCH[2]}"; }
# flag <facts> <key> <name>: passes when key=1.
flag() { if [[ "$(get "$1" "$2")" == 1 ]]; then pass "$3"; else fail "$3" "not found"; fi; }

# The handback set: agents that hold Write and name a `Findings path:` in Handback.
declare -A FACTS=()
for file in "$AGENTS"/*.md; do
  f="$(facts "$file")"
  [[ "$(get "$f" handback)" == 1 && ", $(get "$f" tools)," == *", Write,"* ]] || continue
  a="${file##*/}"
  FACTS[${a%.md}]="$f"
done

names=" ${!FACTS[*]} "
for want in code-reviewer security-reviewer; do
  assert_contains "handback set holds $want" "$names" " $want "
done

for a in "${!FACTS[@]}"; do
  f="${FACTS[$a]}"
  cap="$(get "$f" cap)"
  if [[ "$(get "$f" budget)" == 1 ]]; then pass "$a has a Turn budget section"; else fail "$a has a Turn budget section" "no '## Turn budget' heading"; fi
  bcap="$(get "$f" budget_cap)"
  if [[ -n $cap && $bcap == "$cap" ]]; then
    pass "$a Turn budget states the frontmatter cap ($cap)"
  else
    fail "$a Turn budget states the frontmatter cap" "frontmatter maxTurns '$cap', Turn budget 'maxTurns: ${bcap:-none}'"
  fi
  stop="$(get "$f" stop)"
  if [[ -n $cap && -n $stop ]] && ((stop <= cap - RESERVE)); then
    pass "$a stops gathering at least $RESERVE turns below its cap ($stop of $cap)"
  else
    fail "$a stops gathering at least $RESERVE turns below its cap" "stop turn '${stop:-none}', cap '$cap'"
  fi
  flag "$f" sentinel "$a names the checkpoint sentinel '$SENTINEL'"
  flag "$f" out_criteria "$a Output format names the 'Criteria read:' line"
  flag "$f" out_coverage "$a Output format names the 'Coverage:' line"
  flag "$f" never "$a Handback keeps 'No findings.' out of the checkpoint on the sentinel's line"
done

# Every consumer of the findings file names the same sentinel.
for rel in reference/reviewer-handback.md skills/quality-gate/context/security.md workflows/fanout-sweep.js; do
  assert_contains "$rel names the checkpoint sentinel" "$(<"$PLUGIN_DIR/$rel")" "$SENTINEL"
done

# reviewer-handback.md "After the reply" gives the resume recovery and the partial result.
after="$(awk '/^## / { on = ($0 == "## After the reply"); next } on' "$PLUGIN_DIR/reference/reviewer-handback.md")"
assert_contains "reviewer-handback.md After the reply names SendMessage" "$after" "SendMessage"
assert_contains "reviewer-handback.md After the reply names a partial result" "$after" "partial"

if ((FAILED)); then
  printf '%d assertion(s) failed\n' "$FAILED" >&2
  exit 1
fi
echo "All turn-budget assertions passed"
