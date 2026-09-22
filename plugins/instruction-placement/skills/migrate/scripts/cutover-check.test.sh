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

# A helper this suite never defined used to print "command not found" to stderr
# and move on, so the run reported every other check passing while silently
# skipping that one. An unknown command is a failed check.
#
# The count goes through a FILE, not the FAILED variable: bash runs this
# handler wherever the unknown command was, which is often a subshell, and a
# subshell's increment dies with it. The summary adds the file's lines back in.
UNKNOWN_COMMANDS="$(mktemp)"
# shellcheck disable=SC2329 # bash invokes this by name when a command is not found
command_not_found_handle() {
  printf '%s\n' "$1" >>"$UNKNOWN_COMMANDS"
  printf 'FAIL: unknown command in the suite: %s\n' "$1"
  printf '      a helper is missing or misspelled; the check it belonged to did not run\n'
  return 127
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; rm -f "${UNKNOWN_COMMANDS:-}"' EXIT
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

### First session after an install or upgrade
EOF

ENVVARS_DELISTED="$TMP/env-vars-delisted.md"
cat >"$ENVVARS_DELISTED" <<'EOF'
# Environment variables

## Features that need feature-flag fetching

- Some other flag-gated feature.

## Something else

### First session after an install or upgrade
EOF

# The heading arrived, the bullet had not yet. Without a completeness check
# this reads exactly like a page that dropped the bullet, which is [MET].
ENVVARS_TRUNCATED="$TMP/env-vars-truncated.md"
cat >"$ENVVARS_TRUNCATED" <<'EOF'
# Environment variables

## Features that need feature-flag fetching

- Some other flag-gated feature.
EOF

ENVVARS_NOHEADING="$TMP/env-vars-noheading.md"
cat >"$ENVVARS_NOHEADING" <<'EOF'
# Environment variables

## A page that was restructured

- Nothing here names the feature-flag list.

### First session after an install or upgrade
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
ERR=$(bash "$SCRIPT" --repo "$CLEAN" --repo "$CLEAN" --skip-canary 2>&1 >/dev/null) || rc=$?
assert_eq "the same --repo twice exits 2" 2 "$rc"
assert_contains "and says which two are the same repository" "$ERR" "are the same repository"

# Two spellings of one tree are one repository, not two: the plan climbs to
# the toplevel, so a trailing slash or a subdirectory would grade it twice.
rc=0
ERR=$(bash "$SCRIPT" --repo "$CLEAN" --repo "$CLEAN/" --skip-canary 2>&1 >/dev/null) || rc=$?
assert_eq "a trailing slash is the same repository" 2 "$rc"
rc=0
ERR=$(bash "$SCRIPT" --repo "$CLEAN" --repo "$CLEAN/.github" --skip-canary 2>&1 >/dev/null) || rc=$?
assert_eq "a subdirectory of the same tree is the same repository" 2 "$rc"

rc=0
bash "$SCRIPT" --repo "$CLEAN" --sources "$TMP/nope.md" >/dev/null 2>&1 || rc=$?
assert_eq "a missing records file exits 2" 2 "$rc"

# A named site the check cannot see is a usage error, not a clean result: an
# unplannable repository yields no ACTION and no PATHDET rows, and both
# conditions that read them would otherwise pass on the silence.
mkdir -p "$TMP/norepo"
rc=0
ERR=$(GIT_CEILING_DIRECTORIES="$TMP" bash "$SCRIPT" --repo "$TMP/norepo" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary 2>&1) || rc=$?
assert_eq "a repository that cannot be planned exits 2" 2 "$rc"
assert_contains "and names the repository it could not plan" "$ERR" "cannot plan"
assert_not_contains "and grades nothing on the silence" "$ERR" "[MET]"

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

# A page cut off after the heading but before the bullet is UNREACH, never
# MET: "the bullet is gone" and "the download stopped early" are the same
# observation until the body is known to have arrived whole.
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-false" --env-vars-file "$ENVVARS_TRUNCATED" --skip-canary)
assert_contains "a truncated page is reported as truncated" "$OUT" "it is truncated or restructured"
assert_not_contains "and is never read as the bullet being gone" "$OUT" \
  "no longer carries the AGENTS.md bullet"
assert_contains "so condition 1 is UNREACH" "$OUT" "[UNREACH] neither probe could answer"

# A bullet that MOVED to another heading reads, from inside one section,
# exactly like a bullet that was deleted. Both are UNREACH.
ENVVARS_MOVED="$TMP/env-vars-moved.md"
cat >"$ENVVARS_MOVED" <<'EOF'
# Environment variables

## Features that need feature-flag fetching

- Some other flag-gated feature.

## Features behind a different flag mechanism

- Have Claude Code read `AGENTS.md` files as project instructions; this one is flag-gated too.

### First session after an install or upgrade
EOF
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-false" --env-vars-file "$ENVVARS_MOVED" --skip-canary)
assert_contains "a bullet that moved elsewhere is not a bullet that left" "$OUT" \
  "still ties AGENTS.md to a flag elsewhere"
assert_not_contains "and is never MET" "$OUT" "ties AGENTS.md to no flag anywhere"

# A bundle with no readable window is UNREACH too, not a default of true.
printf 'tengu_agents_md_mod appears with no export beside it\n' >"$TMP/bundle-opaque"
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-opaque" --env-vars-file "$ENVVARS_NOHEADING" --skip-canary)
assert_contains "an unreadable bundle reports UNREACH" "$OUT" "no window ties"

# The identifier comes from the registration, not from the first isOnByDefault
# in the window: a window holding two plugins would otherwise resolve this
# flag's default from a neighbor's variable.
{
  printf 'Cs(A,{isOnByDefault:()=>Q});var Q=!0;'
  printf 'Cs(ne,{isOnByDefault:()=>W});var W=!1;var B=()=>Gl("tengu_agents_md_mod",W);'
} >"$TMP/bundle-neighbour"
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-neighbour" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "the default is read from the registered identifier" "$OUT" "var W=!1"
assert_contains "and the neighboring plugin's true default is not borrowed" "$OUT" \
  "[UNMET]   code default false"

# A registration with no export tying to the same identifier answers nothing.
printf 'var B=()=>Gl("tengu_agents_md_mod",W);var W=!1;' >"$TMP/bundle-untied"
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-untied" --env-vars-file "$ENVVARS_NOHEADING" --skip-canary)
assert_contains "an untied registration is UNREACH" "$OUT" "no isOnByDefault export ties to it"

# The same declaration is reachable from more than one offset on some builds.
# Two occurrences that AGREE are one answer, not a disagreement.
{
  printf 'Gl("tengu_agents_md_mod",W) mentioned once here; '
  printf 'Cs(ne,{isOnByDefault:()=>W});var W=!0;var B=()=>Gl("tengu_agents_md_mod",W);'
} >"$TMP/bundle-twice"
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-twice" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "two agreeing occurrences are one answer" "$OUT" "code default for tengu_agents_md_mod is true"

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

# A ref the script cannot parse must not prefix-match the release map's first
# row and borrow its CLI version.
BADREF="$TMP/badref"
make_repo "$BADREF"
mkdir -p "$BADREF/.github/workflows"
printf '# Shared\n' >"$BADREF/AGENTS.md"
# shellcheck disable=SC2016 # the fixture line is literal YAML; the ${{ }} must not expand here
printf 'jobs:\n  a:\n    steps:\n      - uses: anthropics/claude-code-action@${{ env.PIN }}\n' \
  >"$BADREF/.github/workflows/claude.yml"
commit_all "$BADREF"
rc=0
OUT=$(bash "$SCRIPT" --repo "$BADREF" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary) || rc=$?
assert_contains "an unparsable pin ref is UNREACH" "$OUT" "could not parse a ref out of the pin"
assert_not_contains "and never borrows the first release-map row" "$OUT" "installs CLI 2.1.258"

# A scan that failed and a scan that found nothing are the same empty output.
# The plan says which it was, and a plan that says neither is UNREACH.
ERRPLAN="$TMP/errplan"
make_repo "$ERRPLAN"
printf '# Shared\n' >"$ERRPLAN/AGENTS.md"
commit_all "$ERRPLAN"
STUB_DIR="$TMP/stub-plan"
mkdir -p "$STUB_DIR"
printf '#!/usr/bin/env bash\nprintf "DIR\\t.\\tshim\\t11\\t9\\n"\n' >"$STUB_DIR/plan-migration.sh"
printf '#!/usr/bin/env bash\nprintf "ACTION\\tERROR\\tgrep exited 2\\nPATHDET\\tERROR\\tgit grep exited 2\\n"\n' \
  >"$STUB_DIR/plan-migration-error.sh"
chmod +x "$STUB_DIR/plan-migration.sh" "$STUB_DIR/plan-migration-error.sh"

silent_plan_check() { # <stub name>
  local stub="$TMP/silent-$1"
  mkdir -p "$stub/scripts" "$stub/reference"
  cp "$SCRIPT" "$stub/scripts/cutover-check.sh"
  cp "$STUB_DIR/$2" "$stub/scripts/plan-migration.sh"
  cp "$REAL_SOURCES" "$stub/reference/sources.md"
  bash "$stub/scripts/cutover-check.sh" --repo "$ERRPLAN" \
    --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary
}

rc=0
OUT=$(silent_plan_check quiet plan-migration.sh) || rc=$?
assert_contains "a plan with no ACTION row is UNREACH, not zero pins" "$OUT" \
  "the plan carries no ACTION row"
assert_contains "a plan with no PATHDET row is UNREACH, not a clean tree" "$OUT" \
  "the plan carries no PATHDET row"
assert_not_contains "and neither condition is graded on the silence" "$OUT" "[MET]     0 pin"

rc=0
OUT=$(silent_plan_check errored plan-migration-error.sh) || rc=$?
assert_contains "an errored pin scan is UNREACH" "$OUT" "the pin scan failed"
assert_contains "an errored detection scan is UNREACH" "$OUT" "the detection scan failed"

# Two repositories whose paths differ only by punctuation must not share a plan
# file: the second would overwrite the first, grading one tree twice and the
# other not at all.
COLLIDE_A="$TMP/repo-x"
COLLIDE_B="$TMP/repo_x"
make_repo "$COLLIDE_A"
make_repo "$COLLIDE_B"
printf '# Shared\n' >"$COLLIDE_A/AGENTS.md"
mkdir -p "$COLLIDE_B/.github/workflows"
printf '# Shared\n' >"$COLLIDE_B/AGENTS.md"
printf 'jobs:\n  a:\n    steps:\n      - uses: anthropics/claude-code-action@56cf60fde42f7b19c3abfd5c9c48b69a1288461f # v1.0.222\n' \
  >"$COLLIDE_B/.github/workflows/claude.yml"
commit_all "$COLLIDE_A"
commit_all "$COLLIDE_B"

OUT=$(bash "$SCRIPT" --repo "$COLLIDE_A" --repo "$COLLIDE_B" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "the punctuation-only sibling keeps its own plan" "$OUT" "BELOW 2.1.277"
assert_contains "and the other is still reported as pinless" "$OUT" "$COLLIDE_A: no claude-code-action pin"

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

# The canary writes an AGENTS.md, so its scratch root must not be a working
# tree: a repository handed here would get an instruction file it never asked
# for, and would lose it again when the leg cleaned up.
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" \
  --claude-bin "$TMP/bin/claude-met" --canary-home-root "$CLEAN/scratch" \
  --canary-alt-root "$TMP/canary-alt")
assert_contains "a canary root inside a git repository is refused" "$OUT" \
  "is inside a git repository"
assert_eq "and that repository is untouched" "" "$(cd "$CLEAN" && git status --porcelain)"

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

# The reason IS the review. A row with a path and a copy of the line but no
# reason acknowledges nothing.
# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf 'tools/find-root.sh\tif [[ -f "$root/CLAUDE.md" || -f "$root/other" ]]; then echo found; fi\t\n' \
  >"$DIRTY/.claude/cutover-pathdet-ack.txt"
commit_all "$DIRTY" "ack row with no reason"
OUT=$(bash "$SCRIPT" --repo "$DIRTY" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "an acknowledgement with no reason acknowledges nothing" "$OUT" \
  "UNACKNOWLEDGED tools/find-root.sh"

# A repository with no detection at all needs no file.
OUT=$(bash "$SCRIPT" --repo "$CLEAN" --sources "$REAL_SOURCES" \
  --bundle "$TMP/bundle-true" --env-vars-file "$ENVVARS_LISTED" --skip-canary)
assert_contains "no rows and no file is MET" "$OUT" "no path detection"

# --- Case 8: nothing is written -------------------------------------------

assert_eq "the checked repository is untouched" "" "$(cd "$CLEAN" && git status --porcelain)"

[[ -s "$UNKNOWN_COMMANDS" ]] && FAILED=$((FAILED + $(wc -l <"$UNKNOWN_COMMANDS")))

echo
if ((FAILED == 0)); then
  echo "All $CASE_NUM checks passed"
  exit 0
fi
echo "$FAILED/$CASE_NUM checks failed"
exit 1
