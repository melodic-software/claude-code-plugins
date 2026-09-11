#!/usr/bin/env bash
# Self-test for scripts/lib/fixture-tree.sh.
#
# The properties under test are the ones the hand-rolled per-suite copies
# disagreed on, so each is asserted against the BUILT TREE rather than against
# the builder's source text: the root is outside the checkout, a copied script
# resolves its own SCRIPT_DIR to the fixture's scripts/, a sibling lib that
# script sources resolves there too, a --git repo carries all four identity
# settings, the inherited git environment is cleared for all seven variables,
# the cleanup trap removes the tree on every exit path, and it composes with a
# trap the suite had already installed.
#
# This suite installs no EXIT trap of its own: the builder's trap is what
# removes the roots it makes, and a trap set here would replace it.
#
# fixture-isolation-scope: exports GIT_DIR, GIT_WORK_TREE and GIT_CONFIG into a
# child on purpose, to prove the builder clears what it inherits.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SELF_DIR/fixture-tree.sh"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd -P)"

# shellcheck source=test-harness.sh
. "$SELF_DIR/test-harness.sh"
# shellcheck source=fixture-tree.sh
. "$LIB"

# A child suite that sources the builder and reports on the tree it got. Run in
# its own process so an EXIT trap can be observed firing.
run_child() {
  local body="$1"
  shift
  local out rc
  out="$(env "$@" bash -c "$body" 2>&1)" && rc=0 || rc=$?
  printf '%s\n' "$out"
  return "$rc"
}

# The root a child printed, recovered from its output.
child_value() { # <output> <key>
  local v="${1#*"$2"=}"
  printf '%s' "${v%%$'\n'*}"
}

# fixture_tree::build assigns through a nameref, which shellcheck cannot follow;
# declaring each out-var here is what tells it (SC2154) the name is written.
root_outside="" root_plugins="" probe_home="" root_sut="" root_nolib=""
root_git="" poison_root=""

# --- sourced-only ----------------------------------------------------------

if bash "$LIB" >/dev/null 2>&1; then
  fail "executing the library exited 0"
else
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    ok "executing the library exits 2"
  else
    fail "executing the library exited $rc, expected 2"
  fi
fi

# --- the root is outside the checkout --------------------------------------

fixture_tree::build root_outside
case "$root_outside" in
"$REPO_ROOT" | "$REPO_ROOT"/*)
  fail "the built root is inside the checkout: $root_outside"
  ;;
*)
  if [[ -d "$root_outside/scripts" ]]; then
    ok "the built root is outside the checkout and carries scripts/"
  else
    fail "the built root has no scripts/ dir: $root_outside"
  fi
  ;;
esac

# A root that would land inside the checkout is refused rather than built. The
# child moves the repo-root marker over $TMPDIR instead of writing into the real
# checkout: the same comparison with none of the litter.
out="$(
  run_child "
    . \"$LIB\"
    FIXTURE_TREE_REPO_ROOT=\"\${TMPDIR:-/tmp}\"
    if fixture_tree::build inside; then
      echo BUILT
    else
      echo REFUSED
    fi
  "
)" && rc=0 || rc=$?
if [[ "$out" == *REFUSED* && "$out" == *"refusing a root inside the checkout"* ]]; then
  ok "a root that would land inside the checkout is refused"
else
  fail "inside-the-checkout root should be refused, got rc=$rc out='$out'"
fi

# --- --plugins and the default tree ----------------------------------------

fixture_tree::build root_plugins --plugins
if [[ -d "$root_plugins/plugins" && -d "$root_plugins/scripts" ]]; then
  ok "--plugins creates the plugins tree alongside scripts/"
else
  fail "--plugins should create plugins/ and scripts/, got: $(ls -A "$root_plugins" 2>&1)"
fi
if [[ -d "$root_plugins/scripts/lib" ]]; then
  fail "no --sut was copied, so scripts/lib should not be staged"
else
  ok "scripts/lib is not staged when there is no script under test"
fi

# --- a copied SUT resolves its own SCRIPT_DIR and its sibling lib -----------

fixture_tree::build probe_home
cat >"$probe_home/probe-gate.sh" <<'PROBE'
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2
printf 'SCRIPT_DIR=%s\n' "$SCRIPT_DIR"
entries=()
read_list::into entries "$SCRIPT_DIR/../list.txt" --comments inline || exit 2
printf 'ENTRIES=%s\n' "${entries[*]}"
PROBE
chmod +x "$probe_home/probe-gate.sh"

fixture_tree::build root_sut --sut "$probe_home/probe-gate.sh"
printf 'alpha\nbeta # why\n' >"$root_sut/list.txt"
if [[ -x "$root_sut/scripts/probe-gate.sh" ]]; then
  ok "the script under test is copied executable into the fixture's scripts/"
else
  fail "expected an executable copy at $root_sut/scripts/probe-gate.sh"
fi
probe_out="$(bash "$root_sut/scripts/probe-gate.sh" 2>&1)" && probe_rc=0 || probe_rc=$?
if [[ "$probe_out" == *"SCRIPT_DIR=$root_sut/scripts"* ]]; then
  ok "the copied script resolves its own SCRIPT_DIR to the fixture's scripts/"
else
  fail "SCRIPT_DIR should be $root_sut/scripts, got rc=$probe_rc out='$probe_out'"
fi
if [[ "$probe_rc" -eq 0 && "$probe_out" == *"ENTRIES=alpha beta"* ]]; then
  ok "a sibling lib the copied script sources resolves inside the fixture"
else
  fail "the copied script should read its list through the staged lib, got rc=$probe_rc out='$probe_out'"
fi
if [[ -e "$root_sut/scripts/lib/read-list.test.sh" ]]; then
  fail "a lib's own suite must not be staged into the fixture"
else
  ok "the staged lib carries no *.test.sh of its own"
fi

# --no-lib is the escape for a suite whose SUT walks the fixture's scripts/.
fixture_tree::build root_nolib --sut "$probe_home/probe-gate.sh" --no-lib
if [[ -d "$root_nolib/scripts/lib" ]]; then
  fail "--no-lib should leave scripts/lib unstaged"
else
  ok "--no-lib leaves scripts/lib unstaged"
fi

# A script under test that does not exist is an error, not an empty fixture.
if fixture_tree::build root_missing --sut "$probe_home/not-a-script.sh" 2>/dev/null; then
  fail "a missing script under test should fail the build"
else
  ok "a missing script under test fails the build"
fi

# An unknown option is a usage error (2), not a silently ignored flag.
fixture_tree::build root_badopt --wat 2>/dev/null && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "an unknown option exits 2"
else
  fail "unknown option should return 2, got $rc"
fi

# --- --git writes the FULL throwaway identity ------------------------------

fixture_tree::build root_git --git
identity_ok=1
for pair in "user.email=t@t.test" "user.name=test" "commit.gpgsign=false" "core.autocrlf=false"; do
  key="${pair%%=*}"
  want="${pair#*=}"
  got="$(git -C "$root_git" config --local --get "$key" 2>&1)"
  if [[ "$got" != "$want" ]]; then
    identity_ok=0
    fail "--git repo: $key is '$got', expected '$want'"
  fi
done
if ((identity_ok == 1)); then
  ok "--git writes all four identity settings git_init_test_repo owns"
fi
if git -C "$root_git" rev-parse --git-dir >/dev/null 2>&1; then
  ok "--git leaves a usable repository at the root"
else
  fail "--git should leave a repository at $root_git"
fi

# The identity lands in the FIXTURE, never in the caller's config, even when the
# caller's environment points every git variable at another repository. This is
# the incident scripts/check-fixture-git-isolation.sh exists to stop, asserted
# against the builder rather than against a grep of a suite's source.
fixture_tree::build poison_root --git
git_test_config "$poison_root" config user.email caller@example.test
out="$(
  run_child "
    . \"$LIB\"
    fixture_tree::build r --git
    printf 'FIXTURE_EMAIL=%s\n' \"\$(git -C \"\$r\" config --local --get user.email)\"
  " \
    GIT_DIR="$poison_root/.git" GIT_WORK_TREE="$poison_root" GIT_CONFIG="$poison_root/.git/config"
)" && rc=0 || rc=$?
poisoned="$(git -C "$poison_root" config --local --get user.email 2>&1)"
if [[ "$out" == *"FIXTURE_EMAIL=t@t.test"* && "$poisoned" == "caller@example.test" ]]; then
  ok "an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG does not redirect the fixture's identity write"
else
  fail "inherited git env leaked: child out='$out' rc=$rc caller user.email='$poisoned'"
fi

# --- the inherited git environment is cleared, all seven variables ---------

out="$(
  run_child "
    . \"$LIB\"
    for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG; do
      printf '%s=[%s]\n' \"\$v\" \"\${!v:-}\"
    done
  " \
    GIT_DIR=/nope GIT_WORK_TREE=/nope GIT_INDEX_FILE=/nope GIT_COMMON_DIR=/nope \
    GIT_PREFIX=/nope GIT_OBJECT_DIRECTORY=/nope GIT_CONFIG=/nope
)" && rc=0 || rc=$?
still_set=()
while IFS= read -r line; do
  case "$line" in
  *"=[]") ;;
  *"=["*"]") still_set+=("$line") ;;
  *) ;;
  esac
done <<<"$out"
if ((${#still_set[@]} == 0)); then
  ok "sourcing the builder clears all seven inherited git variables"
else
  fail "git variables survived the source: ${still_set[*]} (rc=$rc)"
fi

# --- the trap removes the tree on every exit path --------------------------

for path_case in normal explicit-exit set-e-failure; do
  case "$path_case" in
  normal) tail='exit 0' ;;
  explicit-exit) tail='exit 3' ;;
  set-e-failure) tail='set -e; false' ;;
  *) tail='exit 0' ;;
  esac
  out="$(
    run_child "
      . \"$LIB\"
      fixture_tree::build r
      printf 'ROOT=%s\n' \"\$r\"
      $tail
    "
  )" && rc=0 || rc=$?
  child_root="$(child_value "$out" ROOT)"
  if [[ -z "$child_root" ]]; then
    fail "trap ($path_case): the child printed no root: '$out'"
  elif [[ -e "$child_root" ]]; then
    fail "trap ($path_case): $child_root survived the child's exit"
    rm -rf "$child_root"
  else
    ok "the cleanup trap removes the tree on the $path_case exit path"
  fi
done

# Several roots from several builds all go, not just the last one.
out="$(
  run_child "
    . \"$LIB\"
    fixture_tree::build a
    fixture_tree::build b --plugins
    printf 'FIRST=%s\n' \"\$a\"
    printf 'SECOND=%s\n' \"\$b\"
  "
)" && rc=0 || rc=$?
ra="$(child_value "$out" FIRST)"
rb="$(child_value "$out" SECOND)"
if [[ -n "$ra" && -n "$rb" && ! -e "$ra" && ! -e "$rb" ]]; then
  ok "every root from repeated builds is removed, not only the last"
else
  fail "repeated builds left a root behind: first='$ra' second='$rb' out='$out'"
  [[ -n "$ra" ]] && rm -rf "$ra"
  [[ -n "$rb" ]] && rm -rf "$rb"
fi

# --- composing with a trap the suite already installed ---------------------
#
# The prior trap must still run, and it must run BEFORE the tree is removed so
# a suite's own cleanup can still read out of its fixture.

out="$(
  run_child "
    trap 'printf \"PRIOR_TRAP_RAN\n\"; if [[ -d \"\${r:-}\" ]]; then printf \"TREE_STILL_THERE\n\"; fi' EXIT
    . \"$LIB\"
    fixture_tree::build r
    printf 'ROOT=%s\n' \"\$r\"
  "
)" && rc=0 || rc=$?
child_root="$(child_value "$out" ROOT)"
if [[ "$out" == *PRIOR_TRAP_RAN* && "$out" == *TREE_STILL_THERE* && -n "$child_root" && ! -e "$child_root" ]]; then
  ok "a pre-existing EXIT trap runs before the tree is removed, and the tree is still removed"
else
  fail "trap composition failed: out='$out' root='$child_root' rc=$rc"
  [[ -n "$child_root" ]] && rm -rf "$child_root"
fi

# A prior trap carrying quotes and a newline survives the round trip through
# `trap -p`, which is the only reason the recovery below can be a text strip.
out="$(
  run_child "
    trap 'printf \"A B\n\"
printf \"C\n\"' EXIT
    . \"$LIB\"
    fixture_tree::build r
    printf 'ROOT=%s\n' \"\$r\"
  "
)" && rc=0 || rc=$?
child_root="$(child_value "$out" ROOT)"
if [[ "$out" == *"A B"* && "$out" == *$'\nC'* && -n "$child_root" && ! -e "$child_root" ]]; then
  ok "a multi-line quoted prior trap is composed verbatim"
else
  fail "multi-line prior trap was mangled: out='$out' root='$child_root' rc=$rc"
  [[ -n "$child_root" ]] && rm -rf "$child_root"
fi

# --- re-sourcing does not drop registered roots ----------------------------

out="$(
  run_child "
    . \"$LIB\"
    fixture_tree::build r
    . \"$LIB\"
    printf 'ROOT=%s\n' \"\$r\"
  "
)" && rc=0 || rc=$?
child_root="$(child_value "$out" ROOT)"
if [[ -n "$child_root" && ! -e "$child_root" ]]; then
  ok "re-sourcing the builder keeps the already-registered root scheduled for cleanup"
else
  fail "re-source dropped a registered root: '$child_root' out='$out'"
  [[ -n "$child_root" ]] && rm -rf "$child_root"
fi

test_harness::report
