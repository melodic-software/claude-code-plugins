#!/usr/bin/env bash
# Gate: the rate-limit-guard "operable floor" block must stay identical across
# every surface that inlines it.
#
#   scripts/check-loop-lane-floor-drift.sh            report drift, exit 1 if any
#   scripts/check-loop-lane-floor-drift.sh --check    same (explicit form, matches sibling gates)
#   scripts/check-loop-lane-floor-drift.sh --list     list the source and every registered consumer
#
# Exit: 0 every consumer matches the source, 1 drift or a stale registration,
# 2 usage or a prerequisite this gate cannot verify around.
#
# WHY. docs/conventions/loop-lane/README.md section 6 orders every consuming
# lane body to INLINE the floor, because an installed plugin cannot read a
# sibling plugin's files at runtime: the values have to be in the lane body or
# the lane cannot apply them. Inlining is therefore the design, not a defect,
# and deduplicating into lib/ with a sync script would break exactly the
# installed-plugin isolation the inlining exists to preserve. What the design
# needs instead is a CHECK, and until this script there was none: the section
# claimed "fleet audits check conformance per consumer" and nothing did.
#
# The claim's cost was already paid. Two uncoordinated de-slop shards, #3107
# (work-items) and #3108 (source-control), rewrote two em dashes inside the
# staleness bullet of all three lane bodies and touched neither the reader
# contract that owns the block nor the two other copies. The three lanes stayed
# byte-identical to EACH OTHER, which is the half a reviewer notices, while all
# three drifted from their source, which is the half nobody did.
#
# WHY NOT check-cross-plugin-source-drift.sh. That gate is blind here twice
# over, and neither blindness is a bug in it. It skips SKILL.md by basename
# (a per-plugin skill body is not a shared-source copy), and it clusters on
# identical path-within-plugin, whereas these copies sit at six unrelated
# paths in five directories. Path-shaped clustering structurally cannot find
# this set, so the consumer list below is explicit and hand-maintained.
#
# TWO CONFORMANCE MODES, declared per consumer, because the copies are not all
# free to be byte-identical:
#
#   exact   the extracted block must equal the source block byte for byte.
#           Every prose consumer is in this mode.
#   values  the block must match after normalization (blockquote markers,
#           backticks and emphasis stripped, whitespace runs flattened). This
#           is for the launch-prompt templates under prompts/loops/, which
#           carry the floor inside a blockquote re-wrapped to a narrower
#           column. Their VALUES are still asserted; only the wrapping is free.
#
# A consumer is never silently downgraded to `values`: the mode is written next
# to the path, so widening one is a reviewable edit rather than a lucky match.
#
# LIVENESS IS ASSERTED, NOT ASSUMED. The extractor keys on a marker line, and a
# marker that stops matching would make every block empty and every comparison
# trivially equal — a gate that passes forever over surfaces it no longer
# reads. So the source block is checked against the five bullet labels the
# floor is made of before any consumer is compared, an empty extraction fails,
# and a marker occurring more than once in a file fails as ambiguous rather
# than resolving to the first hit.
#
# Test injection, defaulting to this repository:
#   LOOP_LANE_FLOOR_ROOT   repository root to read
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
ROOT="${LOOP_LANE_FLOOR_ROOT:-$SCRIPT_DIR/..}"
cd "$ROOT" || {
  echo "check-loop-lane-floor-drift: cannot enter root: $ROOT" >&2
  exit 2
}

# The one file that OWNS the floor. Everything below is a copy of this.
SOURCE="plugins/rate-limit-guard/reference/reader-contract.md"

# The explicit consumer registry: "<mode> <path>".
#
# Three lane bodies (the convention's own consumer table), one skill context
# file that inlines the same floor for the orchestrated extract-ssot mode, and
# two launch-prompt templates. Adding a copy of the floor anywhere means adding
# a line here in the same change; the block is small enough that a copy nobody
# registered is a copy nobody will update.
CONSUMERS=(
  "exact plugins/work-items/skills/work-loop/SKILL.md"
  "exact plugins/work-items/skills/attend-queue/SKILL.md"
  "exact plugins/source-control/skills/babysit-loop/SKILL.md"
  "exact plugins/docs-hygiene/skills/extract-ssot/context/orchestrated-mode.md"
  "values prompts/loops/loop-lane-prompts.md"
  "values prompts/loops/loop-lane-profile-claude-code-plugins.md"
)

# The bullet labels the floor is made of. Present in the source block or this
# gate is reading the wrong thing and says so instead of passing.
BULLETS=(
  "**Tee file (fixed path):**"
  "**Pause threshold (fixed):**"
  "**Pause end:**"
  "**Staleness rule:**"
  "**Drain-then-pause:**"
)

# The first line of the floor block, in both plain and blockquoted form.
MARKER='- **Tee file (fixed path):**'

MODE=check
case "${1-}" in
"" | --check) ;;
--list) MODE=list ;;
*)
  echo "usage: check-loop-lane-floor-drift.sh [--check|--list]" >&2
  exit 2
  ;;
esac

# Print the floor block of $1, blockquote markers removed. The block runs from
# the marker line to the first blank line after it (the floor is one bullet
# list with no internal blank line, in every copy and in the source).
extract_block() {
  awk '
    index($0, marker) == 1 || index($0, "> " marker) == 1 { inblock = 1 }
    inblock {
      line = $0
      sub(/^>[[:blank:]]?/, "", line)
      if (line ~ /^[[:blank:]]*$/) { exit }
      print line
    }
  ' marker="$MARKER" "$1"
}

# How many times the marker opens a block in $1. More than one is ambiguous.
# awk with index() rather than grep: the marker is a literal containing `*`,
# `(` and `)`, which a regex engine would read as syntax, and -F would give up
# the line anchor this needs.
count_markers() {
  awk '
    index($0, marker) == 1 || index($0, "> " marker) == 1 { n++ }
    END { print n + 0 }
  ' marker="$MARKER" "$1"
}

# Strip emphasis and backticks, flatten every whitespace run, trim the ends.
# Same normalization idiom as plugins/plugin-quality/scripts/zones-inline-drift.test.sh.
norm() {
  tr -d '`*' | tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'
}

errors=0
report() {
  echo "$1" >&2
  errors=$((errors + 1))
}

# --- The source ------------------------------------------------------------

if [[ ! -r "$SOURCE" ]]; then
  echo "check-loop-lane-floor-drift: source not readable: $SOURCE" >&2
  exit 2
fi

src_markers="$(count_markers "$SOURCE")"
if [[ "$src_markers" != 1 ]]; then
  echo "check-loop-lane-floor-drift: source $SOURCE opens the floor block $src_markers time(s); expected exactly 1" >&2
  exit 2
fi

SRC_BLOCK="$(extract_block "$SOURCE")"
if [[ -z "$SRC_BLOCK" ]]; then
  echo "check-loop-lane-floor-drift: extracted no floor block from $SOURCE; the marker no longer matches" >&2
  exit 2
fi
for bullet in "${BULLETS[@]}"; do
  if [[ "$SRC_BLOCK" != *"$bullet"* ]]; then
    echo "check-loop-lane-floor-drift: source block from $SOURCE is missing the '$bullet' bullet; refusing to compare against a block this gate did not recognize" >&2
    exit 2
  fi
done
SRC_NORM="$(printf '%s\n' "$SRC_BLOCK" | norm)"

if [[ "$MODE" == list ]]; then
  printf 'source  %s (%s lines)\n' "$SOURCE" "$(printf '%s\n' "$SRC_BLOCK" | wc -l | tr -d ' ')"
  for entry in "${CONSUMERS[@]}"; do
    printf 'consumer %-6s %s\n' "${entry%% *}" "${entry#* }"
  done
  printf 'check-loop-lane-floor-drift: 1 source, %s registered consumer(s).\n' "${#CONSUMERS[@]}"
  exit 0
fi

# --- Every registered consumer ---------------------------------------------

checked=0
for entry in "${CONSUMERS[@]}"; do
  mode="${entry%% *}"
  path="${entry#* }"

  if [[ ! -r "$path" ]]; then
    report "STALE REGISTRATION: $path is registered as a floor consumer but is not readable. Repoint or remove the entry; a registration matching no file enforces nothing."
    continue
  fi

  markers="$(count_markers "$path")"
  if [[ "$markers" == 0 ]]; then
    report "MISSING FLOOR: $path is registered as a floor consumer but no longer inlines the block. Restore the inlined floor, or drop the registration in the same change."
    continue
  fi
  if [[ "$markers" != 1 ]]; then
    report "AMBIGUOUS FLOOR: $path opens the floor block $markers times; this gate compares exactly one block per consumer."
    continue
  fi

  block="$(extract_block "$path")"
  if [[ -z "$block" ]]; then
    report "EMPTY FLOOR: $path matched the floor marker but yielded no block."
    continue
  fi

  checked=$((checked + 1))

  if [[ "$mode" == exact ]]; then
    if [[ "$block" == "$SRC_BLOCK" ]]; then
      continue
    fi
    report "DRIFT (exact): $path does not match the floor block in $SOURCE."
    diff -u <(printf '%s\n' "$SRC_BLOCK") <(printf '%s\n' "$block") |
      sed "s|^--- .*|--- $SOURCE|; s|^+++ .*|+++ $path|" >&2 || true
    continue
  fi

  if [[ "$(printf '%s\n' "$block" | norm)" == "$SRC_NORM" ]]; then
    continue
  fi
  report "DRIFT (values): $path does not match the floor block in $SOURCE after normalization."
  diff -u <(printf '%s\n' "$SRC_NORM" | tr ' ' '\n') \
    <(printf '%s\n' "$block" | norm | tr ' ' '\n') |
    sed "s|^--- .*|--- $SOURCE (normalized)|; s|^+++ .*|+++ $path (normalized)|" >&2 || true
done

if ((errors != 0)); then
  cat >&2 <<EOF

The rate-limit guard's operable floor is inlined on purpose: an installed
plugin cannot read a sibling plugin's files at runtime, so every consumer
carries its own copy (docs/conventions/loop-lane/README.md section 6). The
values are DECIDED in one place only:

  $SOURCE

Every copy above has to move with it in the same change. Reconcile the copies
to the source, or change the source and every copy together. Do not hoist the
block into a shared file: the copies exist to survive plugin isolation.
EOF
  echo "check-loop-lane-floor-drift: $errors drifted or unresolvable consumer(s)" >&2
  exit 1
fi

printf 'check-loop-lane-floor-drift: %s consumer(s) match the operable floor in %s\n' "$checked" "$SOURCE"
exit 0
