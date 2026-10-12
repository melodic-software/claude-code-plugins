#!/usr/bin/env bash
# Regression tests for worktree-discover.sh. Black-box: throwaway git fixtures
# (git environment and global config isolated by test-helpers.sh, a ghq stand-in,
# a temporary HOME) run from a directory outside every repository, with
# assertions on the TSV rows and exit codes. No network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVER="$SCRIPT_DIR/worktree-discover.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

T="$(native_mktemp_dir)"
UNRELATED="$(mktemp -d)"
trap 'rm -rf "$T" "$UNRELATED"' EXIT

mkrepo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main >/dev/null 2>&1
  git -C "$1" config user.email t@t.t
  git -C "$1" config user.name t
  git -C "$1" config commit.gpgsign false
  printf 'seed\n' >"$1/README"
  git -C "$1" add README
  git -C "$1" commit -q -m seed
}

# git's own spelling of a checkout path, so the 8.3 and drive forms match.
top() { git -C "$1" rev-parse --show-toplevel; }

FLEET="$T/fleet"
ROOT="$T/root"
mkdir -p "$ROOT" "$T/home" "$T/bin"
mkrepo "$FLEET/github.com/o/a"
mkrepo "$FLEET/github.com/o/b"
mkrepo "$FLEET/github.com/o/c"
A="$(top "$FLEET/github.com/o/a")"
B="$(top "$FLEET/github.com/o/b")"
C="$(top "$FLEET/github.com/o/c")"
git -C "$A" worktree add -q -b wa "$ROOT/a-wt" >/dev/null 2>&1
git -C "$B" worktree add -q -b wb "$ROOT/b-wt" >/dev/null 2>&1
mkdir "$ROOT/broken" "$ROOT/plain"
printf 'gitdir: %s\n' "$T/nowhere/.git/worktrees/broken" >"$ROOT/broken/.git"

GLOBAL="$T/gitconfig"
git config --file "$GLOBAL" worktreeroot.path "$ROOT"

GHQ="$T/bin/ghq"
printf '#!/usr/bin/env bash\n[[ "$*" == "root --all" ]] && printf "%%s\\n" "%s"\n' "$FLEET" >"$GHQ"
chmod +x "$GHQ"

RC=0
OUT=""
ERR=""
# run_disc <global config> <ghq bin> [args...]: from a non-repository cwd, with
# a HOME holding no fleet config unless a case writes one.
run_disc() {
  local global="$1" ghq="$2"
  shift 2
  OUT="$(cd "$UNRELATED" && HOME="$T/home" GIT_CONFIG_GLOBAL="$global" REPO_FLEET_GHQ_BIN="$ghq" \
    CLAUDE_PROJECT_DIR="${PROJ:-}" bash "$DISCOVER" "$@" 2>"$T/err")"
  RC=$?
  ERR="$(cat "$T/err")"
}

# rows <kind> <path>: the rows of that kind for that path.
rows() { printf '%s\n' "$OUT" | awk -F'\t' -v k="$1" -v p="$2" '$1 == k && $2 == p'; }

run_disc "$GLOBAL" "$T/bin/no-ghq" --repo-dir "$A"
assert_exit "named repository: exits 0" 0 "$RC"
assert_eq "root from worktreeroot.path" $'root\t'"$ROOT"$'\tgit-config' "$(rows root "$ROOT")"
assert_eq "named repository and its one linked worktree" $'repo\t'"$A"$'\t1' "$(rows repo "$A")"
assert_eq "a repository owning a worktree under the root is listed though not named" \
  $'repo\t'"$B"$'\t1' "$(rows repo "$B")"
assert_eq "worktree mapped to its owning repository" $'worktree\t'"$ROOT/a-wt"$'\t'"$A" \
  "$(rows worktree "$ROOT/a-wt")"
assert_eq "another repository's worktree mapped to it" $'worktree\t'"$ROOT/b-wt"$'\t'"$B" \
  "$(rows worktree "$ROOT/b-wt")"
assert_eq "a .git pointer git cannot resolve has no owner" $'worktree\t'"$ROOT/broken"$'\t-' \
  "$(rows worktree "$ROOT/broken")"
assert_eq "a directory with no .git is left to the root scan" "" "$(rows worktree "$ROOT/plain")"
assert_eq "an undiscovered repository with no worktree is absent" "" "$(rows repo "$C")"

run_disc "$GLOBAL" "$T/bin/no-ghq" --repo-dir "$ROOT/a-wt" --repo-dir "$A"
assert_eq "a linked worktree named as a repository maps to its main checkout, once" \
  $'repo\t'"$A"$'\t1' "$(rows repo "$A")"
assert_eq "no repository row for the linked worktree itself" "" "$(rows repo "$ROOT/a-wt")"

run_disc "$GLOBAL" "$GHQ"
assert_exit "ghq discovery: exits 0" 0 "$RC"
assert_eq "ghq discovery finds a repository with no worktrees" $'repo\t'"$C"$'\t0' "$(rows repo "$C")"
assert_eq "ghq discovery finds a repository with a worktree" $'repo\t'"$A"$'\t1' "$(rows repo "$A")"

ROOT2="$T/root2"
mkdir -p "$ROOT2"
git -C "$C" config worktreeroot.path "$ROOT2"
run_disc "$GLOBAL" "$GHQ"
assert_eq "a per-repository worktreeroot.path adds its root" $'root\t'"$ROOT2"$'\tgit-config' \
  "$(rows root "$ROOT2")"
assert_eq "the machine-level root is still listed" $'root\t'"$ROOT"$'\tgit-config' "$(rows root "$ROOT")"
git -C "$C" config --unset worktreeroot.path

mkdir -p "$T/home/.claude"
git config --file "$T/home/.claude/repo-fleet-hygiene.conf" fleet.repo "$C"
run_disc "$GLOBAL" "$T/bin/no-ghq"
assert_eq "user-global fleet config names a repository" $'repo\t'"$C"$'\t0' "$(rows repo "$C")"
run_disc "$GLOBAL" "$T/bin/no-ghq" --repo-dir "$A"
assert_eq "named repositories replace the configured scope" "" "$(rows repo "$C")"

# The project-scoped config outranks the user-global one, as in the fleet audit.
mkrepo "$FLEET/github.com/o/e"
E="$(top "$FLEET/github.com/o/e")"
mkdir -p "$T/proj/.claude"
git config --file "$T/proj/.claude/repo-fleet-hygiene.conf" fleet.repo "$E"
PROJ="$T/proj"
run_disc "$GLOBAL" "$T/bin/no-ghq"
assert_eq "project fleet config names a repository" $'repo\t'"$E"$'\t0' "$(rows repo "$E")"
assert_eq "project fleet config shadows the user-global one" "" "$(rows repo "$C")"
# shellcheck disable=SC2016
PROJ='${CLAUDE_PROJECT_DIR}'
run_disc "$GLOBAL" "$T/bin/no-ghq"
assert_eq "an unexpanded project directory falls to the user-global config" \
  $'repo\t'"$C"$'\t0' "$(rows repo "$C")"
PROJ=""
rm -f "$T/home/.claude/repo-fleet-hygiene.conf"

# A repository found only by the root scan has its own root resolved and scanned.
mkrepo "$FLEET/github.com/o/d"
D="$(top "$FLEET/github.com/o/d")"
ROOT3="$T/root3"
mkdir -p "$ROOT3"
git -C "$D" worktree add -q -b wd "$ROOT/d-wt" >/dev/null 2>&1
git -C "$D" worktree add -q -b wd3 "$ROOT3/d-wt3" >/dev/null 2>&1
git -C "$D" config worktreeroot.path "$ROOT3"
run_disc "$GLOBAL" "$T/bin/no-ghq" --repo-dir "$A"
assert_eq "an owner found by the scan contributes its root" $'root\t'"$ROOT3"$'\tgit-config' \
  "$(rows root "$ROOT3")"
assert_eq "that root is scanned" $'worktree\t'"$ROOT3/d-wt3"$'\t'"$D" "$(rows worktree "$ROOT3/d-wt3")"
git -C "$D" worktree remove --force "$ROOT/d-wt" >/dev/null 2>&1

# A path holding a tab cannot be a TSV field: skipped, with a warning.
TABBED="$ROOT/tab"$'\t'"wt"
if git -C "$A" worktree add -q -b wtab "$TABBED" >/dev/null 2>&1; then
  run_disc "$GLOBAL" "$T/bin/no-ghq" --repo-dir "$A"
  assert_eq "every row keeps three fields" "" \
    "$(printf '%s\n' "$OUT" | awk -F'\t' 'NF != 3')"
  assert_contains "the skipped path is named on stderr" "$ERR" "tab or newline"
  git -C "$A" worktree remove --force "$TABBED" >/dev/null 2>&1
else
  skip_case "a directory name holding a tab is not creatable on this host"
fi

# Rungs below the git key: the plugin option, then the plugin data directory.
printf '%s' "$T/opt-root" >"$T/fallback"
# shellcheck disable=SC2016
printf '%s' '${user_config.worktree_root}' >"$T/fallback-unset"
printf '%s' "$T/data" >"$T/data-root"
run_disc /dev/null "$T/bin/no-ghq" --repo-dir "$B" --fallback-root-file "$T/fallback" \
  --data-root-file "$T/data-root"
assert_eq "plugin option when no git key is set" $'root\t'"$T/opt-root"$'\tplugin-option' "$(rows root "$T/opt-root")"
run_disc /dev/null "$T/bin/no-ghq" --repo-dir "$B" --fallback-root-file "$T/fallback-unset" \
  --data-root-file "$T/data-root"
assert_eq "an unexpanded plugin option falls to the data directory" \
  $'root\t'"$T/data/worktrees"$'\tplugin-data' "$(rows root "$T/data/worktrees")"

run_disc /dev/null "$T/bin/no-ghq" --repo-dir "$B"
assert_exit "no rung resolves: exits 3" 3 "$RC"
assert_contains "no rung resolves: says so" "$ERR" "no worktree root resolved"
assert_eq "no rung resolves: repositories are still listed" $'repo\t'"$B"$'\t1' "$(rows repo "$B")"

# Read-only: a retired alias is read, never rewritten or dropped.
git -C "$A" config melodic.worktreeroot "$ROOT"
run_disc /dev/null "$T/bin/no-ghq" --repo-dir "$A"
assert_eq "retired alias still answers" $'root\t'"$ROOT"$'\tgit-config' "$(rows root "$ROOT")"
assert_eq "retired alias left in place" "$ROOT" "$(git -C "$A" config --get melodic.worktreeroot)"
assert_eq "current key not written" "" "$(git -C "$A" config --local --get worktreeroot.path)"

run_disc /dev/null "$T/bin/no-ghq" --bogus
assert_exit "unknown argument is a usage error" 2 "$RC"
run_disc /dev/null "$T/bin/no-ghq" --repo-dir
assert_exit "--repo-dir without a value is a usage error" 2 "$RC"
run_disc /dev/null "$T/bin/no-ghq" --data-root-file "$T/missing"
assert_exit "a missing root file is a usage error" 2 "$RC"

[[ $FAILED -eq 0 ]] || exit 1
