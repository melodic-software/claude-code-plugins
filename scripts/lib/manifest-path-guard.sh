# shellcheck shell=bash

manifest_path_guard::resolve_to() {
  local -n _mpg_out="$1"
  local _mpg_gate="$2" _mpg_manifest="$3" _mpg_plugin="$4" _mpg_rel="$5"
  _mpg_out=""
  [[ -n "$_mpg_rel" ]] || return 0
  if [[ "$_mpg_rel" == /* || "$_mpg_rel" =~ ^[A-Za-z]: || "/$_mpg_rel/" == *"/../"* ]]; then
    echo "$_mpg_gate: skipping out-of-tree hooks path in $_mpg_manifest: $_mpg_rel" >&2
    return 0
  fi
  _mpg_out="$_mpg_plugin/${_mpg_rel#./}"
}
