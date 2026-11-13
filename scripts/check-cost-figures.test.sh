#!/usr/bin/env bash
# Black-box contract test for check-cost-figures.sh.
#
# Self-contained and cwd-independent: builds a throwaway tree with fixture
# skill, doc and upstream files plus a baseline and an exempt list, runs the
# checker against it, and asserts on exit code and output. Mutates only its own
# mktemp dir.
# shellcheck disable=SC2016  # every $<digit> here is literal fixture text
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-cost-figures.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

SKILL=plugins/alpha/skills/audit
BL=scripts/cost-figures-baseline.txt
EX=scripts/cost-figures-exempt.txt
BODY=$SKILL/reference/body.md
FIXED='FIX: delete the figure and link the page that owns it, https://code.claude.com/docs/en/costs#track-your-costs'

# mk_tree <out-var>: one baselined offender, one exempt file, and a clean file
# holding each passing shape.
mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --label cost-figures || return 1
  dir="${!1}"
  mkdir -p "$dir/$SKILL/reference" "$dir/docs/upstream" "$dir/prompts"
  printf 'Intro.\n\nA run costs about $0.30.\n' >"$dir/$SKILL/reference/old.md"
  printf 'Write $1.00 or $1, never both.\n' >"$dir/$SKILL/reference/format.md"
  cat >"$dir/$SKILL/SKILL.md" <<'EOF'
# Audit

Each turn resends the conversation; rates are on the [Pricing](https://platform.claude.com/docs/en/about-claude/pricing) page.

Pass at 80% coverage, a score of 0.9, 90% cache hits, and a 2x speedup.

The wrapper carries roughly 88% of the cost of the run, and missing comments cost 10x the cost.

Read the field with `awk '{print $1}'` or `$0`.

```text
A fence may say $4 input per million tokens.
```

## Cost anchors

List-price estimates measured on this skill's suite, 2026-10-02, Claude Code 2.1.287:

| Pass | Cost |
|---|---|
| 24 runs | 1.67 USD |

Recheck when a release note touches the runner.
EOF
  printf '| Price (vendor-reported): $4 input per million tokens | NOT ADOPTED |\n' >"$dir/docs/upstream/post.md"
  printf '# none\n%s/reference/old.md 1  # pending: fix\n' "$SKILL" >"$dir/$BL"
  printf '%s/reference/format.md  # a formatting example\n' "$SKILL" >"$dir/$EX"
}

# run_case <label> <expected-rc> <setup> [<must-name>...]
run_case() {
  local label="$1" expected="$2" setup="$3"
  shift 3
  local tree out rc s
  mk_tree tree || {
    fail "$label: fixture build failed"
    return
  }
  (cd "$tree" && eval "$setup") || {
    fail "$label: setup failed"
    return
  }
  out="$(bash "$tree/scripts/check-cost-figures.sh" --check 2>&1)"
  rc=$?
  if [[ $rc -ne $expected ]]; then
    fail "$label: expected rc=$expected, got rc=$rc: $out"
    return
  fi
  for s in "$@"; do
    if ! grep -qF -- "$s" <<<"$out"; then
      fail "$label: '$s' not named in output: $out"
      return
    fi
  done
  ok "$label"
}

# add <text> [<file>]: a new last paragraph in a skill file (default a fresh
# reference file, outside SKILL.md's list-price section).
add() { printf "printf '\\\\n%%s\\\\n' %q >>%s" "$1" "${2:-$SKILL/reference/body.md}"; }

run_case "every passing shape, a baselined offender and an exempt file pass" 0 ":" \
  "1 baselined and 1 exempt file(s)"

run_case "a price fails and names the page to link" 1 "$(add 'Opus costs $5 per million input tokens.')" \
  "$BODY:2: FIX:" "$FIXED" "https://platform.claude.com/docs/en/about-claude/pricing"
run_case "a rate written \$<n>/M fails" 1 "$(add 'Priced at $10/M in.')" "$BODY:2: FIX:"
run_case "a per-task cost in USD fails" 1 "$(add 'A task runs about 0.4 USD.')" "$BODY:2: FIX:"
run_case "a per-session cost in cents fails" 1 "$(add 'A session is 30 cents.')" "$BODY:2: FIX:"
run_case "a percentage saving fails" 1 "$(add 'Caching cuts cost by about 90%.')" "$BODY:2: FIX:"
run_case "a percent-cheaper claim fails" 1 "$(add 'The new model is 40% cheaper.')" "$BODY:2: FIX:"
run_case "a costs-less claim fails" 1 "$(add 'It costs 31% less to run.')" "$BODY:2: FIX:"
run_case "a times-cheaper claim fails" 1 "$(add 'Fast mode is 3x cheaper.')" "$BODY:2: FIX:"
run_case "a rate multiple fails" 1 "$(add 'Fast mode runs at 2x the standard price.')" "$BODY:2: FIX:"
run_case "a pound price fails" 1 "$(add 'It is £3 a month.')" "$BODY:2: FIX:"

run_case "the corrected sentence, a link and no figure, passes" 0 \
  "$(add 'Rates: [Pricing](https://platform.claude.com/docs/en/about-claude/pricing).')"

run_case "an agent file is read" 1 \
  "mkdir -p plugins/alpha/agents && printf 'Each run costs \$0.25.\n' >plugins/alpha/agents/a.md" \
  "plugins/alpha/agents/a.md:1: FIX:"
run_case "a doc file is read" 1 "printf 'Cost: \$3.50 a session.\n' >docs/guide.md" "docs/guide.md:1: FIX:"
run_case "a prompt file is read" 1 "printf 'Budget 2 USD per run.\n' >prompts/p.md" "prompts/p.md:1: FIX:"
run_case "fixtures are not read" 0 \
  "mkdir -p $SKILL/scripts/fixtures && printf 'costs \$4\n' >$SKILL/scripts/fixtures/f.md"

run_case "an upstream figure without vendor-reported fails" 1 \
  "printf '| Price: \$4 input per million tokens | NOT ADOPTED |\n' >>docs/upstream/post.md" \
  "docs/upstream/post.md:2: FIX:"
run_case "vendor-reported outside docs/upstream does not exempt" 1 \
  "$(add 'Opus is $4 input (vendor-reported).')" "$BODY:2: FIX:"
run_case "a list-price section without a recheck trigger fails" 1 \
  "grep -v '^Recheck when' $SKILL/SKILL.md >s.md; mv s.md $SKILL/SKILL.md" "$SKILL/SKILL.md:21: FIX:"
run_case "a list-price section without a version fails" 1 \
  "awk '{ sub(/, Claude Code 2.1.287/, \"\") } 1' $SKILL/SKILL.md >s.md; mv s.md $SKILL/SKILL.md" \
  "$SKILL/SKILL.md:21: FIX:"
run_case "a list-price label in another section does not cover a figure" 1 \
  "$(add '## Later' "$SKILL/SKILL.md"); $(add 'A pass costs 2 USD.' "$SKILL/SKILL.md")" "$SKILL/SKILL.md:27: FIX:"
run_case "a list-price section outside a skill does not exempt" 1 \
  "cp $SKILL/SKILL.md docs/anchors.md" "docs/anchors.md:21: FIX:"
run_case "a per-million rate inside a list-price section still fails" 1 \
  "$(add 'Opus is $5 per million input tokens.' "$SKILL/SKILL.md")" "$SKILL/SKILL.md:25: FIX:"
run_case "a \$<n>/M rate inside a list-price section still fails" 1 \
  "$(add 'The judge is priced at $10/M in.' "$SKILL/SKILL.md")" "$SKILL/SKILL.md:25: FIX:"
run_case "a rate multiple inside a list-price section still fails" 1 \
  "$(add 'Fast mode runs at 2x the standard price.' "$SKILL/SKILL.md")" "$SKILL/SKILL.md:25: FIX:"
run_case "a run cost inside a list-price section still passes" 0 \
  "$(add 'A second pass cost 1.98 USD, about 0.12 USD per run.' "$SKILL/SKILL.md")"
run_case "a labeled section whose prose wraps onto a #<issue> line passes" 0 \
  "printf 'A pass cost 0.9 USD (see\n#15939). List-price estimate, 2026-10-02, Claude Code 2.1.287; recheck when the runner changes.\n' >$SKILL/reference/anchors.md"
run_case "an upstream paragraph that wraps onto a #<issue> line keeps its vendor-reported label" 0 \
  "printf 'The post prices Opus at \$4 input (see\n#12), vendor-reported.\n' >docs/upstream/wrap.md"

# The canonical source sits outside the scanned roots, so only the mapping can
# put it in the output.
run_case "a generated copy is reported at its canonical source" 1 \
  "mkdir -p shared/c && printf 'A run costs \$1.20.\n' >shared/c/README.md && cp shared/c/README.md $SKILL/reference/copy.md && printf 'shared/c/README.md %s/reference/copy.md\n' $SKILL >scripts/shared-copies.txt" \
  "shared/c/README.md:1: FIX:"

run_case "a second offender in a baselined file fails and names the counts" 1 \
  "printf '\nAnd \$0.40 more.\n' >>$SKILL/reference/old.md" \
  "$SKILL/reference/old.md:5: FIX:" "allows 1 and the file has 2"
run_case "a baselined file with fewer offenders than listed asks for the baseline to shrink" 1 \
  "printf '%s/reference/old.md 2\n' $SKILL >$BL" "lower its count in $BL to 1"
run_case "a baselined file whose figure was fixed asks for its line to go" 1 \
  "printf 'See the pricing page.\n' >$SKILL/reference/old.md" \
  "$SKILL/reference/old.md: FIX: delete its line from $BL; the file states no cost figure now"
run_case "a baseline entry naming a missing file fails as stale" 1 \
  "rm $SKILL/reference/old.md" "$SKILL/reference/old.md: FIX: delete its line from $BL; the file does not exist"
run_case "an exempt entry whose file holds no figure fails as stale" 1 \
  "printf 'Write numbers consistently.\n' >$SKILL/reference/format.md" \
  "$SKILL/reference/format.md: FIX: delete its line from $EX"

run_case "a tree with no plugins, docs or prompts passes" 0 "rm -r plugins docs prompts && : >$BL && : >$EX"
run_case "a baseline entry without a count is an environment error" 2 \
  "printf '%s/reference/old.md\n' $SKILL >$BL" "is not \"<markdown path> <count>\""
run_case "a missing baseline is an environment error" 2 "rm $BL"
run_case "a missing exempt list is an environment error" 2 "rm $EX"

# Findings on stderr only; the clean statement on stdout only.
tree=""
if mk_tree tree; then
  printf 'A run costs $2.\n' >"$tree/$SKILL/reference/new.md"
  stdout="$(bash "$tree/scripts/check-cost-figures.sh" 2>/dev/null)"
  rc=$?
  if [[ $rc -eq 1 && -z "$stdout" ]]; then
    ok "discover mode exits 1 with nothing on stdout"
  else
    fail "discover mode should exit 1 with an empty stdout (rc=$rc): $stdout"
  fi
else
  fail "discover mode: fixture build failed"
fi

bash "$SUT_SRC" --bogus >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "unknown mode exits 2"
else
  fail "unknown mode should exit 2 (rc=$rc)"
fi

test_harness::report
