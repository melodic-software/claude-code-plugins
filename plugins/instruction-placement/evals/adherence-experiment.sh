#!/usr/bin/env bash
# adherence-experiment.sh — does path-scoping actually improve adherence?
#
# THE CLAIM UNDER TEST. This plugin's justification is not only token savings.
# It also asserts that a convention delivered at the moment a matching file is
# read is followed more reliably than the same convention buried in a large
# always-loaded file. That is a claim about behavior, and it was asserted before
# it was measured. This script measures it.
#
# It is designed to be able to FAIL. A null or negative result is a real
# outcome, and the README's adherence claim has to change if it comes back that
# way. Nothing here is tuned to make the treatment win.
#
# DESIGN
#   Arm A (control)   the convention is one section of a ~250-line AGENTS.md
#                     that loads in full at session start.
#   Arm B (treatment) the identical convention text lives in a path-scoped rule
#                     covering **/*.cs; AGENTS.md carries everything else.
#
#   Both arms get an identical task that EDITS AN EXISTING .cs FILE, so the
#   read that triggers a path-scoped rule actually happens. (A create-only task
#   would test the documented write-trigger gap instead, which is a different
#   question and one the rubric already answers by refusing that destination.)
#
#   Compliance is defined BEFORE any run: the produced file declares the class
#   `sealed`, and names the private field with a leading underscore. Both are
#   stated only in the convention, and neither is the model's default.
#
# HONESTY BOUNDS
#   * Small N. This detects a large effect and nothing subtler. Raw counts are
#     reported; no p-value is computed, because one would imply power this does
#     not have.
#   * One model, one convention, one repository shape. Not a general result.
#   * Order is interleaved so drift in service conditions hits both arms alike.
#
# Usage:
#   adherence-experiment.sh [--trials N] [--filler N] [--claude <path>] [--keep]
#
# Exit: 0 the experiment ran; 2 usage error; 3 could not measure.

set -uo pipefail

TRIALS=6
CLAUDE_BIN=""
KEEP=0
# Filler sections per half of the control file. 24 gives a ~250-line AGENTS.md,
# just past the 200-line guidance; raise it to test whether an adherence effect
# appears only at much greater bloat.
FILLER_SECTIONS=24

usage() {
  cat <<'EOF'
adherence-experiment.sh — measure whether path-scoping improves adherence.

Usage:
  adherence-experiment.sh [--trials N] [--filler N] [--claude <path>] [--keep]

  --trials N     runs per arm (default 6; 2 model calls per trial pair)
  --filler N     filler sections per half of the control file (default 24,
                 giving a ~250-line AGENTS.md); raise it to test for an
                 adherence effect that appears only at much greater bloat
  --claude PATH  Claude Code CLI to drive
  --keep         leave the fixture and transcripts on disk for inspection

Arm A puts the convention in a ~250-line always-loaded AGENTS.md.
Arm B puts the identical text in a path-scoped rule for **/*.cs.
Both arms edit an existing .cs file, so the read-trigger fires.

Reports raw compliance counts per arm. Small N: directional only.

Exit: 0 ran; 2 usage error; 3 could not measure.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --trials)
    [[ $# -lt 2 ]] && {
      printf 'ERROR: --trials needs a number\n' >&2
      exit 2
    }
    [[ "$2" =~ ^[0-9]+$ ]] || {
      printf 'ERROR: --trials must be an integer\n' >&2
      exit 2
    }
    TRIALS="$2"
    shift 2
    ;;
  --claude)
    [[ $# -lt 2 ]] && {
      printf 'ERROR: --claude needs a path\n' >&2
      exit 2
    }
    CLAUDE_BIN="$2"
    shift 2
    ;;
  --filler)
    [[ $# -lt 2 ]] && {
      printf 'ERROR: --filler needs a number\n' >&2
      exit 2
    }
    [[ "$2" =~ ^[0-9]+$ ]] || {
      printf 'ERROR: --filler must be an integer\n' >&2
      exit 2
    }
    FILLER_SECTIONS="$2"
    shift 2
    ;;
  --keep)
    KEEP=1
    shift
    ;;
  *)
    printf 'ERROR: unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
  esac
done

if [[ -z "$CLAUDE_BIN" ]]; then
  for c in "$(dirname "${BASH_SOURCE[0]}")/../../../node_modules/.bin/claude" \
    "$(command -v claude 2>/dev/null || true)"; do
    [[ -n "$c" && -x "$c" ]] && {
      CLAUDE_BIN="$c"
      break
    }
  done
fi
[[ -n "$CLAUDE_BIN" && -x "$CLAUDE_BIN" ]] || {
  printf 'VERDICT\tUNKNOWN\tno Claude Code CLI available\n'
  exit 3
}
# Each trial runs inside the arm's directory, so a relative CLI path would
# resolve against the wrong root and every trial would fail identically.
CLAUDE_BIN="$(cd "$(dirname "$CLAUDE_BIN")" && pwd)/$(basename "$CLAUDE_BIN")"

WORK="$(mktemp -d)"
[[ $KEEP -eq 1 ]] || trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# The convention under test, written once and used verbatim by both arms.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # markdown code spans; the backticks are literal
CONVENTION='## C# class conventions

Every public class in this repository is declared `sealed` unless it is
explicitly designed for inheritance. Private fields are named with a leading
underscore, in `_camelCase`.'

# Filler that makes the control arm a realistically large always-loaded file.
# Deliberately plausible and non-conflicting: it must add length, not confusion.
write_filler() {
  local out="$1" i
  for i in $(seq 1 "$FILLER_SECTIONS"); do
    cat >>"$out" <<EOF

## Repository practice $i

Keep changes scoped to the task at hand. Prefer small, reviewable commits with a
descriptive subject line. When touching shared code, check for existing callers
before changing a signature. Document any non-obvious decision in the pull
request body rather than in a code comment. Run the relevant test suite before
pushing, and do not disable a failing test to make a build pass.
EOF
  done
}

build_arm() {
  local arm="$1"
  local dir="$WORK/$arm"
  mkdir -p "$dir/src" "$dir/.claude/rules"

  cat >"$dir/src/Billing.cs" <<'EOF'
namespace Acme.Billing;

public sealed class InvoiceLine
{
    private readonly decimal _unitPrice;

    public InvoiceLine(decimal unitPrice) => _unitPrice = unitPrice;

    public decimal UnitPrice => _unitPrice;
}
EOF

  printf '@AGENTS.md\n' >"$dir/CLAUDE.md"
  printf '# Engineering handbook\n' >"$dir/AGENTS.md"

  if [[ "$arm" == "control" ]]; then
    # Convention buried mid-file, with filler on both sides.
    write_filler "$dir/AGENTS.md"
    printf '\n%s\n' "$CONVENTION" >>"$dir/AGENTS.md"
    write_filler "$dir/AGENTS.md"
  else
    # Identical filler, identical total practice content, but the convention
    # moves to a path-scoped rule. Only the DELIVERY differs between arms.
    write_filler "$dir/AGENTS.md"
    write_filler "$dir/AGENTS.md"
    {
      printf -- '---\n'
      printf 'description: "C# class conventions"\n'
      printf 'paths:\n  - "**/*.cs"\n'
      printf -- '---\n\n'
      printf '%s\n' "$CONVENTION"
    } >"$dir/.claude/rules/csharp.md"
  fi

  git -C "$dir" init -q .
  git -C "$dir" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1
}

TASK='Add a public class named InvoiceTotal to src/Billing.cs. It needs a private field holding a running total as a decimal, a constructor, and a public method Add(decimal amount) that adds to the running total and a public property Total that exposes it. Edit the existing file. Reply with DONE when finished.'

# Compliance, defined before any run.
#   sealed:     the produced class is declared sealed
#   underscore: the new private field uses a leading-underscore name
#
# The underscore check is SCOPED to the InvoiceTotal body. The seeded file
# already declares `private readonly decimal _unitPrice`, so a whole-file search
# scores 1 before the model has written anything: the criterion becomes a
# constant, and a run reports a number that is not a measurement.
#
# The scanner below biases toward UNDER-crediting. Every way of failing to
# delimit the body ends at the declaration line alone, scoring 0, rather than
# running on into a later class and crediting a field that is not the one the
# task asked for. For an instrument whose numbers get published, a false 1 is
# the unrecoverable error and a false 0 is a visible one.
#
# Three shapes a model can plausibly produce, and what happens to each:
#   `class InvoiceTotal(decimal x);`  a body-less primary constructor. No brace
#                                    body opens before the next declaration, so
#                                    the region stops at the declaration line.
#   `"unbalanced { brace"`           a brace inside a string, char literal or
#                                    line comment. Stripped before counting, so
#                                    the depth counter stays in sync.
#   anything else that desyncs       a block comment holding a lone brace, say.
#                                    Depth never returns to zero, the body is
#                                    treated as undelimited, and the region
#                                    stops at the declaration line.
score_trial() {
  local file="$1" sealed=0 underscore=0 body
  grep -qE 'sealed[[:space:]]+class[[:space:]]+InvoiceTotal' "$file" 2>/dev/null && sealed=1
  # The new class, from its declaration to its matching closing brace.
  body="$(awk '
    # Brace characters that are data, not structure.
    function scrub(s,   q) {
      q = sprintf("%c", 39)
      gsub(/"[^"]*"/, "", s)
      gsub(q "[^" q "]*" q, "", s)
      sub(/\/\/.*/, "", s)
      return s
    }
    # A line that declares some class. Rejects comment lines, which cannot.
    function declares_class(s) {
      return (s ~ /^[[:space:]]*[A-Za-z]/ &&
              s ~ /(^|[[:space:]])class[[:space:]]+[A-Za-z_]/)
    }
    !seen && /class[[:space:]]+InvoiceTotal/ { seen = 1; decl = NR }
    seen && !finished {
      # A second declaration before any brace opened means InvoiceTotal has no
      # brace body of its own, and the lines that follow belong to that class.
      if (!entered && NR > decl && declares_class($0)) { finished = 1; next }
      buf[++n] = $0
      code = scrub($0)
      opens = gsub(/\{/, "{", code)
      closes = gsub(/\}/, "}", code)
      depth += opens - closes
      if (opens > 0) entered = 1
      if (entered && depth <= 0) { finished = 1; closed = 1 }
    }
    END {
      if (!seen) exit
      if (!closed) n = 1
      for (i = 1; i <= n; i++) print buf[i]
    }
  ' "$file" 2>/dev/null)"
  # A private field declaration in the new class whose name starts with `_`.
  printf '%s\n' "$body" | grep -qE 'private[^;]*[[:space:]]_[A-Za-z][A-Za-z0-9]*' && underscore=1
  printf '%d\t%d' "$sealed" "$underscore"
}

run_trial() {
  local arm="$1" n="$2"
  local dir="$WORK/$arm"
  git -C "$dir" checkout -q -- . 2>/dev/null
  timeout 300 "$CLAUDE_BIN" -p "$TASK" \
    --allowedTools Read Edit Write >"$WORK/${arm}-${n}.out" 2>"$WORK/${arm}-${n}.err" &&
    return 0
  return 1
}

build_arm control
build_arm treatment

printf 'CONTROL AGENTS.md is %s lines; treatment AGENTS.md is %s lines.\n\n' \
  "$(wc -l <"$WORK/control/AGENTS.md" | tr -d ' ')" \
  "$(wc -l <"$WORK/treatment/AGENTS.md" | tr -d ' ')"
printf 'ARM\tTRIAL\tSEALED\tUNDERSCORE\tBOTH\n'

c_sealed=0 c_under=0 c_both=0 c_ok=0
t_sealed=0 t_under=0 t_both=0 t_ok=0

for ((n = 1; n <= TRIALS; n++)); do
  # Interleaved, so any drift in service conditions hits both arms alike.
  for arm in control treatment; do
    dir="$WORK/$arm"
    (cd "$dir" && run_trial "$arm" "$n") >/dev/null 2>&1
    rc=$?
    if ((rc != 0)); then
      printf '%s\t%d\t-\t-\tERROR\n' "$arm" "$n"
      continue
    fi
    read -r s u <<<"$(score_trial "$dir/src/Billing.cs")"
    both=0
    ((s == 1 && u == 1)) && both=1
    printf '%s\t%d\t%d\t%d\t%d\n' "$arm" "$n" "$s" "$u" "$both"
    if [[ "$arm" == "control" ]]; then
      c_ok=$((c_ok + 1))
      c_sealed=$((c_sealed + s))
      c_under=$((c_under + u))
      c_both=$((c_both + both))
    else
      t_ok=$((t_ok + 1))
      t_sealed=$((t_sealed + s))
      t_under=$((t_under + u))
      t_both=$((t_both + both))
    fi
  done
done

printf '\nRESULT\tarm\tn\tsealed\tunderscore\tboth\n'
printf 'RESULT\tcontrol\t%d\t%d\t%d\t%d\n' "$c_ok" "$c_sealed" "$c_under" "$c_both"
printf 'RESULT\ttreatment\t%d\t%d\t%d\t%d\n' "$t_ok" "$t_sealed" "$t_under" "$t_both"

printf '\nRaw counts only. N is small by design and no p-value is computed:\n'
printf 'this detects a large effect and nothing subtler. One model, one\n'
printf 'convention, one repository shape — not a general result.\n'
[[ $KEEP -eq 1 ]] && printf '\nFixture kept at: %s\n' "$WORK"
exit 0
