# shellcheck shell=bash
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/fixture-tree.sh is sourced-only\n' >&2
  exit 2
fi

_fixture_tree_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_TREE_REPO_ROOT="$(cd "$_fixture_tree_lib_dir/../.." && pwd)"
unset _fixture_tree_lib_dir

# shellcheck source=../test-git-helpers.sh
. "$FIXTURE_TREE_REPO_ROOT/scripts/test-git-helpers.sh"

if [[ -n "${FIXTURE_TREE_SOURCED:-}" ]]; then
  return 0
fi
FIXTURE_TREE_SOURCED=1

_fixture_tree_roots=()
_fixture_tree_prior_trap=""
_fixture_tree_trap_installed=0

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

fixture_tree::_install_trap() {
  if ((_fixture_tree_trap_installed == 1)); then
    return 0
  fi
  _fixture_tree_prior_trap="$(trap -p EXIT)"
  trap 'fixture_tree::_cleanup' EXIT
  _fixture_tree_trap_installed=1
}

fixture_tree::_lib_closure() {
  local _ft_cl_names=""
  while (($# > 0)) && [[ "$1" != -- ]]; do
    _ft_cl_names+="$1 "
    shift
  done
  shift
  awk -v dir="$FIXTURE_TREE_REPO_ROOT/scripts/lib/" -v names="$_ft_cl_names" '
    BEGIN {
      n = split(names, nm, " ")
      for (i = 1; i <= n; i++) lib[nm[i]] = 1
      for (i = 1; i < ARGC; i++) q[++nq] = ARGV[i]
      ARGC = 1
      for (h = 1; h <= nq; h++) {
        while ((getline line < q[h]) > 0) {
          m = split(line, tok, /[^A-Za-z0-9_.-]+/)
          for (j = 1; j <= m; j++)
            if ((tok[j] in lib) && !(tok[j] in seen)) { seen[tok[j]] = 1; print tok[j]; q[++nq] = dir tok[j] }
        }
        close(q[h])
      }
    }' "$@"
}

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
      _ft_lib=all
      shift
      ;;
    --no-lib)
      _ft_lib=none
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
  _ft_root="$(cd "$_ft_root" && pwd -P)" || return 1

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
  local -a _ft_srcs=()
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
    _ft_srcs+=("$_ft_src")
  done

  if [[ "$_ft_lib" == auto && ${#_ft_suts[@]} -eq 0 ]]; then
    _ft_lib=none
  fi
  if [[ "$_ft_lib" != none ]]; then
    mkdir -p "$_ft_root/scripts/lib" || {
      rm -rf "$_ft_root"
      return 1
    }
    local -a _ft_libnames=()
    local _ft_libfile
    for _ft_libfile in "$FIXTURE_TREE_REPO_ROOT"/scripts/lib/*; do
      [[ -f "$_ft_libfile" && "$_ft_libfile" != *.test.sh ]] && _ft_libnames+=("${_ft_libfile##*/}")
    done
    if [[ "$_ft_lib" == auto ]]; then
      mapfile -t _ft_libnames < <(fixture_tree::_lib_closure "${_ft_libnames[@]}" -- "${_ft_srcs[@]}")
    fi
    for _ft_libfile in ${_ft_libnames[@]+"${_ft_libnames[@]}"}; do
      cp "$FIXTURE_TREE_REPO_ROOT/scripts/lib/$_ft_libfile" "$_ft_root/scripts/lib/" || {
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
