#!/usr/bin/env bash
# Regression tests for cutover-check.sh (self-contained — ships with the plugin).
#
# Every case runs from a neutral temporary directory against fixture inputs: a
# fixture bundle, a fixture env-vars page, fixture repositories, and a fake
# `claude` that answers the canary without a metered turn. No case reads the
# real fleet and no case spends a real turn.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/cutover-check.sh"
REAL_SOURCES="$SCRIPT_DIR/../reference/sources.md"

CASE_NUM=0
FAILED=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1"
  printf '      %s\n' "$2"
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "expected NOT to contain: $3" ;;
  *) pass "$1" ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1

make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "t@example.com" &&
    git config user.name "t" && git config core.autocrlf false &&
    git commit -q --allow-empty -m init)
}

commit_all() { (cd "$1" && git add -A && git commit -q -m "${2:-fixture}"); }

# --- fixtures -------------------------------------------------------------

# A bundle is binary; what the parser needs from it is the flag string, the
# export and the declaration inside one window, surrounded by bytes that are
# not text. `!0` is true, `!1` is false.
make_bundle() { # <path> <!0|!1>
  {
    printf 'noise\001\002\003'
    printf 'var ne={};Cs(ne,{isOnByDefault:()=>W,registerPlugin:()=>ze});'
    printf 'var W=%s;var B=()=>oX()&&Gl("tengu_agents_md_mod",W);' "$2"
    printf '\004\005trailing'
  } >"$1"
}

ENVVARS_LISTED="$TMP/env-vars-listed.md"
cat >"$ENVVARS_LISTED" <<'EOF'
# Environment variables

## Features that need feature-flag fetching

- Have Claude Code [read `AGENTS.md` files](/docs/en/memory#agents-md) as project instructions.

## Something else
EOF

ENVVARS_DELISTED="$TMP/env-vars-delisted.md"
cat >"$ENVVARS_DELISTED" <<'EOF'
# Environment variables

## Features that need feature-flag fetching

- Some other flag-gated feature.

## Something else
EOF

ENVVARS_NOHEADING="$TMP/env-vars-noheading.md"
cat >"$ENVVARS_NOHEADING" <<'EOF'
# Environment variables

## A page that was restructured

- Nothing here names the feature-flag list.
EOF

make_bundle "$TMP/bundle-false" '!1'
make_bundle "$TMP/bundle-true" '!0'

# A fake CLI, so the canary legs cost nothing. `met` echoes the scratch
# directory's own AGENTS.md, which is what a loaded file looks like; `unmet`
# answers NONE; `unreach` exits non-zero.
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\ncat AGENTS.md\n' >"$TMP/bin/claude-met"
printf '#!/usr/bin/env bash\necho NONE\n' >"$TMP/bin/claude-unmet"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/bin/claude-unreach"
chmod +x "$TMP/bin/claude-met" "$TMP/bin/claude-unmet" "$TMP/bin/claude-unreach"

CANARY_ROOTS=(--canary-home-root "$TMP/canary-home" --canary-alt-root "$TMP/canary-alt")

# A repository already at the cutover shape: a pin that clears the floor and
# nothing locating a path by CLAUDE.md.
CLEAN="$TMP/clean"
make_repo "$CLEAN"
mkdir -p "$CLEAN/.github/workflows"
printf '# Shared\n' >"$CLEAN/AGENTS.md"
printf '@AGENTS.md\n' >"$CLEAN/CLAUDE.md"
printf 'jobs:\n  a:\n    steps:\n      - uses: anthropics/claude-code-action@cfc3eb22bfed5c26ef66e3223c982af27e4524de # v1.0.231\n' \
  >"$CLEAN/.github/workflows/claude.yml"
commit_all "$CLEAN"

# A repository that fails both repository-shaped conditions: an old pin and an
# unacknowledged path detector.
DIRTY="$TMP/dirty"
make_repo "$DIRTY"
mkdir -p "$DIRTY/.github/workflows" "$DIRTY/tools"
printf '# Shared\n' >"$DIRTY/AGENTS.md"
printf '@AGENTS.md\n' >"$DIRTY/CLAUDE.md"
printf 'jobs:\n  a:\n    steps:\n      - uses: anthropics/claude-code-action@56cf60fde42f7b19c3abfd5c9c48b69a1288461f # v1.0.222\n' \
  >"$DIRTY/.github/workflows/claude.yml"
# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf 'if [[ -f "$root/CLAUDE.md" ]]; then echo found; fi\n' >"$DIRTY/tools/find-root.sh"
commit_all "$DIRTY"

# --- Case 1: --help and usage errors --------------------------------------

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_eq "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"
assert_contains "--help documents --skip-canary" "$OUT" "--skip-canary"
assert_contains "--help says UNREACH is never a pass" "$OUT" "never a pass"

rc=0
bash "$SCRIPT" --skip-canary >/dev/null 2>&1 || rc=$?
assert_eq "no --repo exits 2" 2 "$rc"

rc=0
bash "$SCRIPT" --repo "$CLEAN" --bogus >/dev/null 2>&1 || rc=$?
assert_eq "an unknown argument exits 2" 2 "$rc"

rc=0
bash "$SCRIPT" --repo "$CLEAN" --sources "$TMP/nope.md" >/dev/null 2>&1 || rc=$?
assert_eq "a missing records file exits 2" 2 "$rc"

printf '# Records\n\n## The CI canary\n\nNothing parsable here.\n' >"$TMP/broken-sources.md"
rc=0
ERR=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$TMP/broken-sources.md" 2>&1 >/dev/null) || rc=$?
assert_eq "an unparsable record exits 2 rather than skipping the check" 2 "$rc"
assert_contains "and says which record it could not parse" "$ERR" "cannot parse"

# --- Case 2: every graded condition met -----------------------------------

rc=0
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" \
  --claude-bin "$TMP/bin/claude-met" "${CANARY_ROOTS[@]}") || rc=$?
assert_eq "an all-met fixture exits 0" 0 "$rc"
assert_contains "the verdict says every condition is met" "$OUT" "every graded condition MET"
assert_not_contains "and no condition is UNMET" "$OUT" "[UNMET]"
assert_not_contains "and no condition is UNREACH" "$OUT" "[UNREACH]"
assert_contains "condition 1 shows the code default it read" "$OUT" "var W=!0"
assert_contains "condition 2 shows the pin it resolved" "$OUT" "installs CLI 2.1.278"
assert_contains "condition 2 shows the CI canary run" "$OUT" "35475056935"
assert_contains "condition 3 shows both legs" "$OUT" "second-path cwd"

# A scratch directory the canary made is a directory the canary removes.
assert_eq "the home-leg scratch directory is gone" "" "$(ls "$TMP/canary-home" 2>/dev/null)"
assert_eq "the second-path scratch directory is gone" "" "$(ls "$TMP/canary-alt" 2>/dev/null)"

# --- Case 3: one condition unmet names it and exits non-zero --------------

rc=0
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" \
  --claude-bin "$TMP/bin/claude-met" "${CANARY_ROOTS[@]}") || rc=$?
assert_eq "an unmet condition exits 1" 1 "$rc"
assert_contains "the verdict names the unmet conditions" "$OUT" "Condition(s) 2, 4 are not [MET]"
assert_contains "condition 2 names the pin below the floor" "$OUT" "BELOW 2.1.277"
assert_contains "condition 4 names the unacknowledged row" "$OUT" "UNACKNOWLEDGED tools/find-root.sh"
assert_contains "the verdict says nothing was removed" "$OUT" "nothing is removed"

# --- Case 4: the flag probe ------------------------------------------------

# Code default false while the page still lists the dependency: UNMET.
rc=0
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-false" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "a false code default plus a listed bullet is UNMET" "$OUT" \
  "[UNMET]   code default false"
assert_contains "and the evidence names the identifier it resolved" "$OUT" "isOnByDefault:()=>W"

# The page dropping the bullet satisfies the condition on its own.
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-false" --env-vars-file "$ENVVARS_DELISTED" --skip-canary)
assert_contains "a delisted bullet is MET even with a false code default" "$OUT" \
  "no longer carries the AGENTS.md bullet"

# A restructured page is UNREACH, never MET: the absence of a heading cannot be
# read as the absence of the dependency.
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-false" --env-vars-file "$ENVVARS_NOHEADING" --skip-canary)
assert_contains "a missing heading reports UNREACH for condition 1" "$OUT" \
  "[UNREACH] neither probe could answer"
assert_not_contains "and never reports it MET" "$OUT" "no longer carries the AGENTS.md bullet"

# A bundle with no readable window is UNREACH too, not a default of true.
printf 'tengu_agents_md_mod appears with no export beside it\n' >"$TMP/bundle-opaque"
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-opaque" --env-vars-file "$ENVVARS_NOHEADING" --skip-canary)
assert_contains "an unreadable bundle reports UNREACH" "$OUT" "no window around"

# --- Case 5: the pin map ---------------------------------------------------

UNKNOWN="$TMP/unknownpin"
make_repo "$UNKNOWN"
mkdir -p "$UNKNOWN/.github/workflows"
printf '# Shared\n' >"$UNKNOWN/AGENTS.md"
printf 'jobs:\n  a:\n    steps:\n      - uses: anthropics/claude-code-action@0000000000000000000000000000000000000000 # v9.9.9\n' \
  >"$UNKNOWN/.github/workflows/claude.yml"
commit_all "$UNKNOWN"

rc=0
OUT=$(bash "$SCRIPT" --repo "$UNKNOWN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "a pin outside the release map is UNREACH" "$OUT" "is not in the release map"
assert_not_contains "and is never reported as clearing the floor" "$OUT" "[MET]     1 pin"

# A comment naming the action is not a pin, and an absent workflow directory is
# reported as checked rather than silently skipped.
NOPIN="$TMP/nopin"
make_repo "$NOPIN"
printf '# Shared\n' >"$NOPIN/AGENTS.md"
commit_all "$NOPIN"
OUT=$(bash "$SCRIPT" --repo "$NOPIN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "a repository with no pin says so" "$OUT" "no claude-code-action pin"

# --- Case 6: the canary ----------------------------------------------------

OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" \
  --claude-bin "$TMP/bin/claude-unmet" "${CANARY_ROOTS[@]}")
assert_contains "a clean NONE is UNMET" "$OUT" "[UNMET]   a lone AGENTS.md did not load"

OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" \
  --claude-bin "$TMP/bin/claude-unreach" "${CANARY_ROOTS[@]}")
assert_contains "a non-zero CLI exit is UNREACH" "$OUT" "[UNREACH] a leg could not measure"
assert_not_contains "and is never a pass" "$OUT" "both legs returned the canary line"

OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "--skip-canary is UNREACH, not a skip" "$OUT" "[UNREACH] --skip-canary"

# --- Case 7: the acknowledgement file --------------------------------------

mkdir -p "$DIRTY/.claude"
# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf '# a comment row\n\nnot/the/path\tif [[ -f "$root/CLAUDE.md" ]]; then echo found; fi\twrong path\n' \
  >"$DIRTY/.claude/cutover-pathdet-ack.txt"
commit_all "$DIRTY" "ack with the wrong path"
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "an acknowledgement for another path does not cover this row" "$OUT" \
  "UNACKNOWLEDGED tools/find-root.sh"

# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf 'tools/find-root.sh\tif [[ -f "$root/CLAUDE.md" ]]; then echo found; fi\tfixture, locates nothing\n' \
  >"$DIRTY/.claude/cutover-pathdet-ack.txt"
commit_all "$DIRTY" "ack matching path and text"
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "a matching acknowledgement covers the row" "$OUT" "acknowledged tools/find-root.sh"
assert_contains "and the reason is printed as evidence" "$OUT" "fixture, locates nothing"
assert_contains "so condition 4 is MET" "$OUT" "every one acknowledged with a reviewed reason"

# The match is on the source text, never the line number: moving the row keeps
# it acknowledged, changing its code does not.
# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf '# padding\n# padding\nif [[ -f "$root/CLAUDE.md" ]]; then echo found; fi\n' \
  >"$DIRTY/tools/find-root.sh"
commit_all "$DIRTY" "row moved to a new line"
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "a moved row is still acknowledged" "$OUT" "acknowledged tools/find-root.sh"

# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf '# padding\nif [[ -f "$root/CLAUDE.md" || -f "$root/other" ]]; then echo found; fi\n' \
  >"$DIRTY/tools/find-root.sh"
commit_all "$DIRTY" "row changed"
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "a changed row falls out and is re-reported" "$OUT" \
  "UNACKNOWLEDGED tools/find-root.sh"

# A repository with no detection at all needs no file.
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "no rows and no file is MET" "$OUT" "no path detection"

# --- Case 8: nothing is written -------------------------------------------

assert_eq "the checked repository is untouched" "" "$(cd "$CLEAN" && git status --porcelain)"

echo
if ((FAILED == 0)); then
  echo "All $CASE_NUM checks passed"
  exit 0
fi
echo "$FAILED/$CASE_NUM checks failed"
exit 1
