# shellcheck shell=bash

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
  [[ $path != [-:]* ]] || checkout_path::refuse "'$path' starts with - or :"
  here=$(pwd -P)
  real=$(realpath -m -- "$path") || checkout_path::refuse "'$path' does not resolve"
  [[ $real == "$here"/* ]] || checkout_path::refuse "'$path' is not inside the checkout"
}
