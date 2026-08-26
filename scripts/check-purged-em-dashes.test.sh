#!/usr/bin/env bash
# Black-box contract test for check-purged-em-dashes.sh.
#
# Hermetic and cwd-independent: builds a throwaway git repository containing its
# own markdown, its own allowlist and its own detector config, points the SUT at
# it through the four EM_DASH_* injection variables, and asserts on exit code
# plus output. The one thing it does NOT stub is the detector. The fixture
# drives the real plugins/ai-slop/skills/audit/scripts/detect.sh, because the
# behaviour most worth pinning here is precisely that this gate and that
# detector agree on what counts as prose. A stubbed detector would let the two
# drift and still report green.
#
# The seeded violation is the point of the suite. A gate whose failing path is
# never exercised is a gate nobody has evidence works; every "clean" assertion
# below would also pass against a script that unconditionally exits 0. So the
# fixture plants a real em dash in prose and requires exit 1 and the offending
# file named, and separately plants em dashes in the places that legitimately
# carry them, a fenced code block and an ignore-marked line, and requires
# those NOT to fire.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-purged-em-dashes.sh"
DETECT="$SCRIPT_DIR/../plugins/ai-slop/skills/audit/scripts/detect.sh"
DETECT="$(cd "$(dirname "$DETECT")" && pwd)/$(basename "$DETECT")"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# Clears the inherited git environment for the whole suite; see
# scripts/check-fixture-git-isolation.sh for why -C alone does not isolate.
# shellcheck source=test-git-helpers.sh
. "$SCRIPT_DIR/test-git-helpers.sh"

EM="$(printf '\xe2\x80\x94')"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_cfg <detector-config> <fixture-root> <allowlist-relative-path> [args...]:
# sets OUT and RC. The config is a parameter because three of the cases below
# turn on what the SUT derives from a DIFFERENT tracked config than the default
# one; every other case goes through run(), which pins the default.
# Deliberately not wrapped in a command substitution of its own: that forks a
# subshell and the exit status never reaches the caller.
run_cfg() {
  local cfg="$1" root="$2" list="$3"
  shift 3
  OUT="$(
    EM_DASH_PURGED_ROOT="$root" \
      EM_DASH_PURGED_PATHS="$list" \
      EM_DASH_SLOP_CONFIG="$cfg" \
      EM_DASH_DETECT="$DETECT" \
      bash "$SUT" "$@" 2>&1
  )"
  RC=$?
}

run() { run_cfg ".claude/ai-slop.json" "$@"; }

# --- Fixture ----------------------------------------------------------------
# One repository, several allowlists pointed at different subsets of it, so each
# case selects the surface it means to assert on rather than rebuilding a repo.

REPO="$TMP/repo"
mkdir -p "$REPO/.claude" "$REPO/surface" "$REPO/other"
git_init_test_repo "$REPO"

write() { printf '%s\n' "$2" >"$REPO/$1"; }

# The tracked detector config, shaped like this repository's: rule-em-dash
# disabled here, so a passing run PROVES the SUT's throwaway layer re-enabled it
# rather than inheriting an already-permissive config.
write ".claude/ai-slop.json" '{"excluded_paths":[],"disabled_rules":["rule-em-dash","rule-emoji-formatting"]}'

write "surface/clean.md" 'A purged surface. It uses periods, and commas, instead.'

write "surface/dirty.md" "A surface with a regression ${EM} right here in prose."

# Em dashes that are DATA, not prose: one inside a fenced code block, one on a
# line the detector's own ignore marker declines. Both must stay silent, or the
# gate would push contributors to corrupt quoted material to satisfy a style
# rule.
printf '%s\n' \
  'Prose with no em dash.' \
  '' \
  '```text' \
  "code ${EM} fence" \
  '```' \
  '' \
  "ignored ${EM} line <!-- ai-slop-ignore:quoted source -->" \
  >"$REPO/surface/data.md"

write "other/unlisted.md" "Not on the allowlist ${EM} so not this gate's business."

# A file the detector opens and then declines on an in-file marker. The detector
# counts such a file BOTH as scanned and as declined, so a gate that adds those
# two totals sees one file too many and reports a coverage mismatch on a file the
# allowlist legitimately names. The marker is documented as an exemption, so it
# has to be usable from an allowlisted path.
printf '%s\n' \
  '<!-- ai-slop-ignore-file -->' \
  '' \
  "Wholly declined text ${EM} not this gate's business either." \
  >"$REPO/surface/marked.md"

# Three more tracked configs, each carrying one switch that can quiet
# rule-em-dash on an allowlisted file. The SUT strips the first two when it
# derives its throwaway layer and fails the run on the third, so each of these
# is pointed at the SEEDED VIOLATION: a config that could suppress the finding
# is the only fixture in which stripping is observable.
write ".claude/cfg-em-dash-allowed.json" '{"excluded_paths":[],"em_dash_allowed_paths":["surface/dirty.md"],"disabled_rules":["rule-em-dash"]}'
write ".claude/cfg-rule-allowed.json" '{"excluded_paths":[],"rule_allowed_paths":{"rule-em-dash":["surface/dirty.md"]},"disabled_rules":["rule-em-dash"]}'
write ".claude/cfg-excluded.json" '{"excluded_paths":["surface/dirty.md"],"disabled_rules":["rule-em-dash"]}'

list() {
  local name="$1"
  shift
  printf '%s\n' "$@" >"$REPO/$name.txt"
}

list "only-clean" 'surface/clean.md'
list "marked" 'surface/clean.md' 'surface/marked.md'
list "clean-and-data" 'surface/clean.md' 'surface/data.md'
list "with-dirty" 'surface/clean.md' 'surface/dirty.md'
list "globbed" 'surface/*.md'
list "stale" 'surface/clean.md' 'surface/gone.md'
list "empty" '# only a comment' ''
list "commented" 'surface/clean.md   # the surface purged in this fixture'

git_test_config "$REPO" add -A
git_test_config "$REPO" commit -qm fixture

# --- Cases ------------------------------------------------------------------

# Each `run` forks the detector, which is the expensive part of this suite, so
# every allowlist is run ONCE and all of its assertions read the captured
# result. Re-running the same fixture to ask a second question about it is what
# made this suite minutes long instead of seconds.

run "$REPO" "only-clean.txt"
clean_rc=$RC clean_out="$OUT"
if ((clean_rc == 0)); then
  ok "clean surface passes"
else
  fail "clean surface passes (rc=$clean_rc): $clean_out"
fi
# An unlisted file is unenforced: that is the allowlist's defining property, and
# asserting it here is what stops a later "just scan everything" edit from
# passing this suite. Asserting the file is merely ABSENT from the output does
# not pin that, because a clean run prints one summary line and names nothing;
# the scanned count is what distinguishes "one file was checked" from "the whole
# fixture was checked and happened to be clean apart from the listed one".
if [[ "$clean_out" != *"unlisted.md"* ]] &&
  [[ "$clean_out" == *"1 declared paths, 1 files scanned"* ]]; then
  ok "a file outside the allowlist is not scanned"
else
  fail "a file outside the allowlist is not scanned: $clean_out"
fi

# THE SEEDED VIOLATION.
run "$REPO" "with-dirty.txt"
if ((RC == 1)); then
  ok "seeded em dash fails the gate"
else
  fail "seeded em dash fails the gate (rc=$RC, want 1): $OUT"
fi
if [[ "$OUT" == *"surface/dirty.md"* ]]; then
  ok "the failure names the offending file"
else
  fail "the failure names the offending file: $OUT"
fi
if [[ "$OUT" != *"surface/clean.md:"* ]]; then
  ok "the failure does not implicate the clean file"
else
  fail "the failure does not implicate the clean file: $OUT"
fi
# If the SUT ever stopped re-enabling rule-em-dash, the fixture's tracked config
# would leave the rule off and this same case would report a clean run. The
# liveness guard must therefore not be what fired here.
if [[ "$OUT" != *"config layer did not take effect"* ]]; then
  ok "the derived config layer takes effect"
else
  fail "the derived config layer takes effect: $OUT"
fi

run "$REPO" "clean-and-data.txt"
if ((RC == 0)); then
  ok "em dashes in a code fence and an ignore-marked line do not fire"
else
  fail "em dashes in a code fence and an ignore-marked line do not fire (rc=$RC): $OUT"
fi

# A whole-file ignore marker is one of the exemptions this gate documents, so an
# allowlisted path is allowed to carry one. The detector counts such a file both
# as scanned and as declined, and a gate that reads those two totals as disjoint
# concludes it was handed one file too many and refuses the run at exit 2 —
# green surfaces reported broken because of an exemption they were promised.
run "$REPO" "marked.txt"
if ((RC == 0)); then
  ok "a whole-file ignore marker does not break the coverage assertion"
else
  fail "a whole-file ignore marker does not break the coverage assertion (rc=$RC): $OUT"
fi

run "$REPO" "globbed.txt"
if ((RC == 1)) && [[ "$OUT" == *"surface/dirty.md"* ]]; then
  ok "a glob entry expands to every matching tracked file"
else
  fail "a glob entry expands to every matching tracked file (rc=$RC): $OUT"
fi

run "$REPO" "stale.txt"
if ((RC == 1)) && [[ "$OUT" == *"stale allowlist entry"* ]] && [[ "$OUT" == *"surface/gone.md"* ]]; then
  ok "an entry matching no tracked file fails as stale"
else
  fail "an entry matching no tracked file fails as stale (rc=$RC): $OUT"
fi

run "$REPO" "empty.txt"
if ((RC == 2)); then
  ok "an allowlist with no active entry is exit 2, not a clean run"
else
  fail "an allowlist with no active entry is exit 2 (rc=$RC): $OUT"
fi

run "$REPO" "missing.txt"
if ((RC == 2)); then
  ok "a missing allowlist is exit 2"
else
  fail "a missing allowlist is exit 2 (rc=$RC): $OUT"
fi

run "$REPO" "commented.txt"
if ((RC == 0)); then
  ok "an inline comment is stripped from an entry"
else
  fail "an inline comment is stripped from an entry (rc=$RC): $OUT"
fi

run "$REPO" "only-clean.txt" --list
if ((RC == 0)) && [[ "$OUT" == *"surface/clean.md"* ]]; then
  ok "--list reports each declared entry"
else
  fail "--list reports each declared entry (rc=$RC): $OUT"
fi
# --list is the cheap audit the allowlist header sends a reader to, so it must
# stop at the expansion. Pointed at the seeded violation it still lists rather
# than judging: no detector verdict in the output, and exit 0 for a listing that
# expanded cleanly even though a check of the same allowlist would exit 1.
run "$REPO" "with-dirty.txt" --list
if ((RC == 0)) && [[ "$OUT" != *"no em dashes"* ]] && [[ "$OUT" != *"em-dash line(s)"* ]]; then
  ok "--list expands the allowlist without running the detector"
else
  fail "--list expands the allowlist without running the detector (rc=$RC): $OUT"
fi

run "$REPO" "only-clean.txt" --bogus
if ((RC == 2)); then
  ok "an unknown argument is exit 2"
else
  fail "an unknown argument is exit 2 (rc=$RC): $OUT"
fi

OUT="$(EM_DASH_PURGED_ROOT="$REPO" EM_DASH_PURGED_PATHS="only-clean.txt" \
  EM_DASH_SLOP_CONFIG="does-not-exist.json" EM_DASH_DETECT="$DETECT" \
  bash "$SUT" 2>&1)"
RC=$?
if ((RC == 2)); then
  ok "an unreadable detector config is exit 2"
else
  fail "an unreadable detector config is exit 2 (rc=$RC): $OUT"
fi

# --- Switches that could quiet rule-em-dash on a declared path ---------------
#
# Each of the three runs below uses with-dirty.txt, whose surface/dirty.md the
# base case above proves is a real finding. So each asserts on the ONE thing
# its config changes, against a fixture where suppression would be visible.

# em_dash_allowed_paths exempts a single file from rule-em-dash alone. The
# detector still opens the file, so it counts as scanned, the coverage
# assertion still balances and the rule summary still says disabled=0: nothing
# in a passing run would have said the file was never actually judged. The SUT
# strips the key rather than trusting those counters to reveal it.
run_cfg ".claude/cfg-em-dash-allowed.json" "$REPO" "with-dirty.txt"
if ((RC == 1)) && [[ "$OUT" == *"surface/dirty.md"* ]]; then
  ok "em_dash_allowed_paths does not exempt a declared path"
else
  fail "em_dash_allowed_paths does not exempt a declared path (rc=$RC, want 1): $OUT"
fi

# rule_allowed_paths is the generalized form of the same switch, keyed by rule
# slug, and reaches the detector through a different reader. Stripping one and
# not the other would leave the identical hole under a second spelling.
run_cfg ".claude/cfg-rule-allowed.json" "$REPO" "with-dirty.txt"
if ((RC == 1)) && [[ "$OUT" == *"surface/dirty.md"* ]]; then
  ok "rule_allowed_paths[rule-em-dash] does not exempt a declared path"
else
  fail "rule_allowed_paths[rule-em-dash] does not exempt a declared path (rc=$RC, want 1): $OUT"
fi

# excluded_paths is handled the other way round: the file is never opened, so
# the SUT cannot judge it and does not pretend to. It reports the path and
# FAILS, because a declaration the detector never reads is not coverage, and a
# green exit is exactly how it would be mistaken for some.
run_cfg ".claude/cfg-excluded.json" "$REPO" "with-dirty.txt"
if ((RC == 1)) && [[ "$OUT" == *"were NOT checked"* ]] && [[ "$OUT" == *"surface/dirty.md"* ]]; then
  ok "a declared path the config excludes fails the gate and is named"
else
  fail "a declared path the config excludes fails the gate and is named (rc=$RC, want 1): $OUT"
fi
# ... and the failure is the exclusion, not the em dash that happens to be in
# that file: the detector never read it, so it can report no finding on it.
if [[ "$OUT" != *"em-dash line(s)"* ]]; then
  ok "the excluded path fails as unchecked rather than as a finding"
else
  fail "the excluded path fails as unchecked rather than as a finding: $OUT"
fi

test_harness::report
