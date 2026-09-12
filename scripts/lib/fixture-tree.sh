# shellcheck shell=bash
# Shared fixture-tree builder for scripts/*.test.sh. Sourced, never executed.
#
# A check script's suite drives it through its CLI against a throwaway tree, and
# building that tree is the same six steps every time: an mktemp root outside
# the checkout, `mkdir -p "$root/scripts"`, a copy of the script under test, a
# copy of scripts/lib/ so that script's own `. "$SCRIPT_DIR/lib/read-list.sh"`
# resolves inside the fixture, an optional plugins/ tree, an optional throwaway
# git repo, and a cleanup trap. Written once per suite, the copies disagreed on
# the parts that decide whether the fixture is isolated at all: a hand-rolled
# repo set user.email and user.name but not commit.gpgsign or core.autocrlf, so
# a signing-enabled machine failed the commit; an inline `unset GIT_DIR
# GIT_WORK_TREE GIT_CONFIG` named three of the seven variables this file clears.
#
# One builder holds those by construction, so a suite states only what its
# fixture must CONTAIN and never how the world around it is made safe.
#
#   fixture_tree::build <out-var> [--sut <script>]... [--git] [--plugins]
#                       [--lib | --no-lib] [--label <name>]
#
#     <out-var>   name of a caller variable; receives the absolute root path.
#     --sut       copy a script under test into <root>/scripts/ and mark it
#                 executable. A bare basename resolves against this repo's
#                 scripts/; a path with a slash is used as given. Repeatable.
#     --git       initialize a throwaway repo at the root with the FULL
#                 identity git_init_test_repo writes.
#     --plugins   create <root>/plugins/.
#     --lib       copy scripts/lib/ (minus its own *.test.sh) into
#                 <root>/scripts/lib/. On by default once any --sut is copied,
#                 because a copied gate that sources a sibling lib dies without
#                 it; --no-lib is for a suite whose SUT walks the fixture's own
#                 scripts/ tree and would count the copies.
#     --label     mktemp prefix, for a readable path while debugging.
#
# WHY THIS IS NOT IN scripts/lib/test-harness.sh. That file owns the assertion
# counters and the exit contract, and 33 suites source it for those alone --
# including suites that build no fixture at all. Folding a git-repo builder into
# it would put `. scripts/test-git-helpers.sh` on the path of every one of them.
# The two files answer different questions ("did this assertion pass?" versus
# "what world does the script under test run in?") and stay separate.
#
# WHY THIS IS NOT IN scripts/test-git-helpers.sh. That file is the git-isolation
# layer: it clears the inherited git environment and wraps `git` with a
# throwaway identity, and it is sourced from outside scripts/ too (plugin suites
# and .claude/hooks suites). A tree builder that knows about scripts/lib/ and
# about scripts under test is repo-tooling knowledge those callers do not want.
# This file DEPENDS on that one instead: git_init_test_repo is the only identity
# spelling, here as everywhere else.
#
# WHY THE CLEAR IS REPEATED HERE. scripts/check-fixture-git-isolation.sh credits
# a suite that sources an isolating harness, resolving harnesses ONE level deep
# by basename. A file that grants that credit to its sourcers must therefore
# perform the clear itself; inheriting it through test-git-helpers.sh would
# leave every sourcer of this file uncredited and re-open the incident the gate
# exists to stop. The list below is the full seven, not the three-variable
# spelling that was drifting through the suites.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/fixture-tree.sh is sourced-only\n' >&2
  exit 2
fi

_fixture_tree_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_TREE_REPO_ROOT="$(cd "$_fixture_tree_lib_dir/../.." && pwd)"
unset _fixture_tree_lib_dir

# shellcheck source=../test-git-helpers.sh
. "$FIXTURE_TREE_REPO_ROOT/scripts/test-git-helpers.sh"

# A second source must not drop the roots already registered for cleanup: that
# would strand a fixture tree in $TMPDIR on every run. The functions stay.
if [[ -n "${FIXTURE_TREE_SOURCED:-}" ]]; then
  return 0
fi
FIXTURE_TREE_SOURCED=1

_fixture_tree_roots=()
_fixture_tree_prior_trap=""
_fixture_tree_trap_installed=0

# Runs the EXIT trap the suite had installed BEFORE the first build, then
# removes every root. That order is deliberate: a suite's own trap may still
# want to read out of its fixture, and it cannot once the tree is gone.
#
# `trap -p EXIT` prints `trap -- <shell-quoted command> EXIT`; the command is
# recovered by stripping those two fixed ends and letting the shell unquote what
# the shell itself quoted.
fixture_tree::_cleanup() {
  if [[ -n "$_fixture_tree_prior_trap" ]]; then
    local _ft_body _ft_prior_cmd
    _ft_body="${_fixture_tree_prior_trap#trap -- }"
    _ft_body="${_ft_body% EXIT}"
    eval "_ft_prior_cmd=$_ft_body"
    eval "$_ft_prior_cmd"
  fi
  local _ft_root
  for _ft_root in ${_fixture_tree_roots[@]+"${_fixture_tree_roots[@]}"}; do
    if [[ -n "$_ft_root" && "$_ft_root" != "/" ]]; then
      rm -rf "$_ft_root"
    fi
  done
  _fixture_tree_roots=()
}

# Installed once, on the first build. A suite that installs its OWN EXIT trap
# AFTER building replaces this one and owns cleanup from then on; build first.
fixture_tree::_install_trap() {
  if ((_fixture_tree_trap_installed == 1)); then
    return 0
  fi
  _fixture_tree_prior_trap="$(trap -p EXIT)"
  trap 'fixture_tree::_cleanup' EXIT
  _fixture_tree_trap_installed=1
}

# EVERY local below carries the `_ft_` prefix, and that is a correctness
# requirement rather than a naming style: a nameref resolves its target in the
# scope where it is USED, so a local sharing the caller's chosen out-var name
# would shadow that caller's variable and hand back an empty root. The same
# reason is recorded at length in scripts/lib/changed-files.sh.
#
# fixture_tree::build <out-var> [--sut <script>]... [--git] [--plugins]
#                     [--lib | --no-lib] [--label <name>]
fixture_tree::build() {
  if (($# < 1)); then
    printf 'fixture-tree: build needs an out-var name\n' >&2
    return 2
  fi
  local -n _ft_root_out="$1"
  shift

  local -a _ft_suts=()
  local _ft_git=0 _ft_plugins=0 _ft_lib=auto _ft_label=fixture
  while (($# > 0)); do
    case "$1" in
    --sut)
      if (($# < 2)); then
        printf 'fixture-tree: --sut needs a script\n' >&2
        return 2
      fi
      _ft_suts+=("$2")
      shift 2
      ;;
    --label)
      if (($# < 2)); then
        printf 'fixture-tree: --label needs a name\n' >&2
        return 2
      fi
      _ft_label="$2"
      shift 2
      ;;
    --git)
      _ft_git=1
      shift
      ;;
    --plugins)
      _ft_plugins=1
      shift
      ;;
    --lib)
      _ft_lib=1
      shift
      ;;
    --no-lib)
      _ft_lib=0
      shift
      ;;
    *)
      printf 'fixture-tree: unknown option %s\n' "$1" >&2
      return 2
      ;;
    esac
  done

  local _ft_root
  _ft_root="$(mktemp -d "${TMPDIR:-/tmp}/$_ft_label.XXXXXX")" || {
    printf 'fixture-tree: mktemp -d failed\n' >&2
    return 1
  }
  # Resolved so the inside-the-checkout test below compares real paths: on macOS
  # $TMPDIR is a symlink into /private, and an unresolved prefix test there
  # would answer about the link rather than about the tree.
  _ft_root="$(cd "$_ft_root" && pwd -P)" || return 1

  # A fixture inside the checkout is the failure this builder must not be able
  # to produce: `git init` there would attach to the real repository, and a
  # stray tree under scripts/ is picked up by every tracked-file gate. mktemp
  # normally lands in $TMPDIR, but $TMPDIR is a caller-settable variable.
  local _ft_repo_root
  _ft_repo_root="$(cd "$FIXTURE_TREE_REPO_ROOT" && pwd -P)" || return 1
  case "$_ft_root" in
  "$_ft_repo_root" | "$_ft_repo_root"/*)
    printf 'fixture-tree: refusing a root inside the checkout: %s\n' "$_ft_root" >&2
    rm -rf "$_ft_root"
    return 1
    ;;
  *) ;;
  esac

  mkdir -p "$_ft_root/scripts" || {
    rm -rf "$_ft_root"
    return 1
  }
  if ((_ft_plugins == 1)); then
    mkdir -p "$_ft_root/plugins" || {
      rm -rf "$_ft_root"
      return 1
    }
  fi

  local _ft_sut _ft_src
  for _ft_sut in ${_ft_suts[@]+"${_ft_suts[@]}"}; do
    if [[ "$_ft_sut" == */* ]]; then
      _ft_src="$_ft_sut"
    else
      _ft_src="$FIXTURE_TREE_REPO_ROOT/scripts/$_ft_sut"
    fi
    if [[ ! -f "$_ft_src" ]]; then
      printf 'fixture-tree: no such script under test: %s\n' "$_ft_src" >&2
      rm -rf "$_ft_root"
      return 1
    fi
    cp "$_ft_src" "$_ft_root/scripts/${_ft_src##*/}" || {
      rm -rf "$_ft_root"
      return 1
    }
    chmod +x "$_ft_root/scripts/${_ft_src##*/}"
  done

  if [[ "$_ft_lib" == auto ]]; then
    if ((${#_ft_suts[@]} > 0)); then
      _ft_lib=1
    else
      _ft_lib=0
    fi
  fi
  if ((_ft_lib == 1)); then
    mkdir -p "$_ft_root/scripts/lib" || {
      rm -rf "$_ft_root"
      return 1
    }
    local _ft_libfile
    for _ft_libfile in "$FIXTURE_TREE_REPO_ROOT"/scripts/lib/*; do
      [[ -f "$_ft_libfile" ]] || continue
      # A lib's own suite is not part of the world a copied gate runs in, and
      # copying it would put a second *.test.sh under the fixture where a
      # suite-counting gate would find it.
      case "$_ft_libfile" in
      *.test.sh) continue ;;
      *) ;;
      esac
      cp "$_ft_libfile" "$_ft_root/scripts/lib/" || {
        rm -rf "$_ft_root"
        return 1
      }
    done
  fi

  if ((_ft_git == 1)); then
    git_init_test_repo "$_ft_root" || {
      rm -rf "$_ft_root"
      return 1
    }
  fi

  _fixture_tree_roots+=("$_ft_root")
  fixture_tree::_install_trap
  _ft_root_out="$_ft_root"
  return 0
}
