# shellcheck shell=bash

changed_files::verify_base() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null 2>&1
}

changed_files::resolve_base() {
  local -n _cf_base_out="$1"
  local _cf_candidate
  for _cf_candidate in origin/main origin/master main master; do
    if changed_files::verify_base "$_cf_candidate"; then
      _cf_base_out="$_cf_candidate"
      return 0
    fi
  done
  return 1
}

changed_files::into() {
  local -n _cf_paths_out="$1"
  local _cf_base="$2"
  shift 2

  local -a _cf_filter=(--diff-filter=d)
  local -a _cf_renames=()
  while (($# > 0)); do
    case "$1" in
    --include-deleted) _cf_filter=() ;;
    --no-renames | --find-renames) _cf_renames=("$1") ;;
    --)
      shift
      break
      ;;
    *)
      printf 'changed-files: unknown option %s\n' "$1" >&2
      return 2
      ;;
    esac
    shift
  done

  _cf_paths_out=()

  local _cf_tmp
  _cf_tmp="$(mktemp)" || {
    printf 'changed-files: mktemp failed\n' >&2
    return 1
  }

  if ! git diff --name-only ${_cf_filter[@]+"${_cf_filter[@]}"} ${_cf_renames[@]+"${_cf_renames[@]}"} -z "$_cf_base" -- "$@" >"$_cf_tmp"; then
    rm -f "$_cf_tmp"
    printf 'changed-files: git diff against %s failed; refusing to report an empty change set\n' "$_cf_base" >&2
    return 1
  fi
  if ! sort -z -u "$_cf_tmp" -o "$_cf_tmp"; then
    rm -f "$_cf_tmp"
    printf 'changed-files: sorting the change set for %s failed\n' "$_cf_base" >&2
    return 1
  fi

  local _cf_path
  while IFS= read -r -d '' _cf_path; do
    _cf_paths_out+=("$_cf_path")
  done <"$_cf_tmp"
  rm -f "$_cf_tmp"
  return 0
}
