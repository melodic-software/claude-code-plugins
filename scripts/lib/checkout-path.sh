# shellcheck shell=bash
# Path argument check for the issue lane's path-taking tools, run-test-file.sh
# and git-mv-rm.sh. Sourced, never executed. The verify-scripts wrapper that
# runs them already refuses an existing path outside the checkout; this adds
# what a tool that runs or moves files also needs: a path that does not exist
# yet (a rename's destination) is held to the checkout too, and the argument
# can only be a plain relative path.
#
#   checkout_path::require <path>
#
# Exits 2 with `refused: ...` on stderr unless <path> is relative, has no `..`
# segment, does not start with `-`, and, with links followed, names something
# inside the current directory (the checkout) other than the directory itself.

checkout_path::refuse() {
  echo "refused: $1" >&2
  exit 2
}

checkout_path::require() {
  local path=$1 here real
  case /$path/ in
    // | //*) checkout_path::refuse "'$path' is absolute or empty" ;;
    */../*) checkout_path::refuse "'$path' has a .. segment" ;;
    *) ;;
  esac
  [[ $path != -* ]] || checkout_path::refuse "'$path' starts with -"
  here=$(pwd -P)
  real=$(realpath -m -- "$path") || checkout_path::refuse "'$path' does not resolve"
  [[ $real == "$here"/* ]] || checkout_path::refuse "'$path' is not inside the checkout"
}
