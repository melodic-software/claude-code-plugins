#!/usr/bin/env bash
# Tests for lib/read-verification.sh. Expected outputs follow
# docs/contracts/verification-level/README.md: a skill entry beats the plugin
# value, the team file is read at origin's default branch only, a layer with no
# value to read resolves light, and an invalid value or unparsable file resolves
# standard, each with its reason.
# Run directly: bash lib/read-verification.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/read-verification.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
}

g() { git -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false "$@"; }

# fixture <name> <default-branch file text, or - for none>: a clone of a local
# bare origin whose default branch commits that text as
# docs/conventions/verification.yaml. Prints the clone's path.
fixture() {
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir/work/docs/conventions"
  g init -q -b main "$dir/work"
  if [[ "$2" == - ]]; then
    : >"$dir/work/README"
  else
    printf '%s' "$2" >"$dir/work/docs/conventions/verification.yaml"
  fi
  g -C "$dir/work" add -A
  g -C "$dir/work" commit -q -m fixture
  g init -q --bare -b main "$dir/origin.git"
  g -C "$dir/work" remote add origin "$dir/origin.git"
  g -C "$dir/work" push -q origin main
  printf '%s\n' "$dir/work"
}

run() { CLAUDE_PROJECT_DIR="$1" bash "$SCRIPT" --plugin verification --skill confirm; }
at() { printf 'at origin/main, commit %s' "$(git -C "$1" rev-parse HEAD)"; }
F=docs/conventions/verification.yaml

repo=$(fixture absent -)
assert_eq "an absent file resolves light" \
  "verification: light (default; $F sets no level $(at "$repo"))" "$(run "$repo")"

repo=$(fixture plugin $'verification: light\n')
assert_eq "the plugin value applies" \
  "verification: light ($F verification $(at "$repo"))" "$(run "$repo")"

repo=$(fixture explicit-standard $'verification: standard\n')
assert_eq "an explicit standard raises the level above the light default" \
  "verification: standard ($F verification $(at "$repo"))" "$(run "$repo")"

repo=$(fixture home-pointer $'verification: off\n')
mkdir -p "$repo/team/conv"
printf 'verification: strict\n' >"$repo/team/conv/verification.yaml"
# shellcheck disable=SC2016 # the backticks are the pointer line's literal markup.
printf '<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in `team/conv`.\n<!-- END GENERATED: convention-home -->\n' >"$repo/AGENTS.md"
g -C "$repo" add -A
g -C "$repo" commit -q -m home
g -C "$repo" push -q origin main
assert_eq "a non-default convention home is read from its pointer line" \
  "verification: strict (team/conv/verification.yaml verification $(at "$repo"))" "$(run "$repo")"

assert_eq "--file reads the fixed path and ignores the convention home" \
  "verification: off ($F verification $(at "$repo"))" \
  "$(CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" --plugin verification --skill confirm --file "$F")"

assert_eq "--file outside the repository is refused" \
  "verification: light (default; --file '../x.yaml' is not a repository-relative .yaml path)" \
  "$(CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" --plugin verification --skill confirm --file ../x.yaml)"

repo=$(fixture skill $'verification: light\nverification_skills:\n  confirm: strict\n  measure: off\n')
assert_eq "a skill entry beats the plugin value" \
  "verification: strict ($F verification_skills.confirm $(at "$repo"))" "$(run "$repo")"

repo=$(fixture other-skill $'verification: light\nverification_skills:\n  measure: off\n')
assert_eq "another skill's entry leaves the plugin value" \
  "verification: light ($F verification $(at "$repo"))" "$(run "$repo")"

repo=$(fixture invalid $'verification: Strict\n')
assert_eq "an invalid value is named and keeps the standard floor" \
  "verification: standard (default; $F verification=Strict is not off, light, standard or strict $(at "$repo"))" "$(run "$repo")"

repo=$(fixture invalid-skill $'verification: strict\nverification_skills:\n  confirm: lite\n')
assert_eq "an invalid skill entry keeps the standard floor, not the plugin value" \
  "verification: standard (default; $F verification_skills.confirm=lite is not off, light, standard or strict $(at "$repo"))" "$(run "$repo")"

repo=$(fixture unparsable $'verification: |\n  strict\n')
assert_eq "a file that does not parse is named and keeps the standard floor" \
  "verification: standard (default; $F does not parse or repeats a key $(at "$repo"))" "$(run "$repo")"

repo=$(fixture no-key $'proof_level: live\n')
assert_eq "a file that sets no level resolves light" \
  "verification: light (default; $F sets no level $(at "$repo"))" "$(run "$repo")"

repo=$(fixture repeated $'verification: strict\nverification: off\n')
assert_eq "a repeated key is named and keeps the standard floor" \
  "verification: standard (default; $F does not parse or repeats a key $(at "$repo"))" "$(run "$repo")"

repo=$(fixture slash $'verification: off/\n')
assert_eq "a value with a trailing slash is named, never read as off" \
  "verification: standard (default; $F verification=off/ is not off, light, standard or strict $(at "$repo"))" "$(run "$repo")"

repo=$(fixture list-skill $'verification: strict\nverification_skills:\n  confirm: [strict]\n')
assert_eq "a list-valued skill entry is named and keeps the standard floor" \
  "verification: standard (default; $F verification_skills.confirm is a list or map, not off, light, standard or strict $(at "$repo"))" "$(run "$repo")"

# A tag and a local branch both named origin/main, on a commit that sets off,
# must not shadow the remote-tracking ref (gitrevisions resolves refs/tags first).
repo=$(fixture shadow $'verification: strict\n')
want="verification: strict ($F verification $(at "$repo"))"
printf 'verification: off\n' >"$repo/$F"
g -C "$repo" commit -q -am lower
g -C "$repo" tag origin/main
g -C "$repo" branch origin/main
g -C "$repo" reset -q --hard HEAD~1
assert_eq "a tag or local branch named origin/main does not shadow origin's default branch" "$want" "$(run "$repo")"

# A single-branch clone of another branch has no refs/remotes/origin/main until
# the reader fetches it into that ref.
repo=$(fixture single $'verification: strict\n')
g -C "$repo" push -q origin main:refs/heads/other
g clone -q --single-branch --branch other "$TEST_TMPDIR/single/origin.git" "$TEST_TMPDIR/single/clone"
assert_eq "a single-branch clone still reads the default branch" \
  "verification: strict ($F verification $(at "$repo"))" "$(run "$TEST_TMPDIR/single/clone")"

repo=$(fixture lowered $'verification: strict\n')
printf 'verification: off\n' >"$repo/$F"
assert_eq "a branch-lowered copy loses to the default-branch value, and both are named" \
  "verification: strict ($F verification $(at "$repo"))
verification: the working tree's copy gives off ($F verification); the origin/main copy (strict) applied" "$(run "$repo")"

repo=$(fixture added -)
printf 'verification: off\n' >"$repo/$F"
assert_eq "a copy only the branch adds does not apply" \
  "verification: light (default; $F sets no level $(at "$repo"))
verification: the working tree's copy gives off ($F verification); the origin/main copy (light) applied" "$(run "$repo")"

repo=$(fixture home $'verification: off\n')
assert_eq "a \$HOME root skips the layer" \
  "verification: light (default; team layer skipped: the root is \$HOME or an ancestor of it)" \
  "$(HOME="$repo" CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" --plugin verification --skill confirm)"

mkdir -p "$TEST_TMPDIR/loose"
assert_eq "a non-repo root skips the layer" \
  "verification: light (default; team layer skipped: the root is not inside a git working tree)" \
  "$(run "$TEST_TMPDIR/loose")"

repo=$(fixture bad-branch $'verification: off\n')
g -C "$repo" push -q origin 'main:refs/heads/a+b'
git --git-dir="$TEST_TMPDIR/bad-branch/origin.git" symbolic-ref HEAD 'refs/heads/a+b'
assert_eq "a bad branch name skips the layer" \
  "verification: light (default; team layer skipped: origin's default branch name 'a+b' is not a safe name)" \
  "$(run "$repo")"

mkdir -p "$TEST_TMPDIR/no-origin"
g init -q -b main "$TEST_TMPDIR/no-origin"
assert_eq "no origin skips the layer" \
  "verification: light (default; team layer skipped: no origin remote answered git ls-remote --symref origin HEAD)" \
  "$(run "$TEST_TMPDIR/no-origin")"

repo=$(fixture args $'verification: off\n')
assert_eq "a skill name holding a dot is refused, not read as a nested key" \
  "verification: light (default; --plugin and --skill take a name of lowercase letters, digits and -)" \
  "$(CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" --plugin verification --skill a.b)"
rc=0
CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "a usage error still exits 0" 0 "$rc"

# No default-branch text selects the working-tree read: a team file holding only `--worktree` beside a
# working-tree copy set to off still resolves from the team text, which does not parse.
repo=$(fixture selector $'--worktree\n')
printf 'verification: off\n' >"$repo/$F"
assert_eq "team file text cannot select the working-tree copy" \
  "verification: standard (default; $F does not parse or repeats a key $(at "$repo"))" "$(run "$repo" | head -n 1)"

# A failed fetch keeps the team's level from the last fetched copy, named as possibly stale, rather than
# dropping to the light default. Origin's main moves ahead (pushed by URL, so refs/remotes/origin/main
# stays behind) and a reference-transaction hook refuses the fetch's update.
repo=$(fixture stale $'verification: strict\n')
next="$(g -C "$repo" commit-tree "HEAD^{tree}" -p HEAD -m next)"
g -C "$repo" push -q "$TEST_TMPDIR/stale/origin.git" "$next:refs/heads/main"
mkdir -p "$TEST_TMPDIR/hooks"
printf '#!/bin/sh\nexit 1\n' >"$TEST_TMPDIR/hooks/reference-transaction"
chmod +x "$TEST_TMPDIR/hooks/reference-transaction"
g -C "$repo" config core.hooksPath "$TEST_TMPDIR/hooks"
assert_eq "a failed fetch keeps the last fetched level" \
  "verification: strict ($F verification $(at "$repo"); the fetch failed, so the last fetched copy may be stale)" \
  "$(run "$repo")"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
