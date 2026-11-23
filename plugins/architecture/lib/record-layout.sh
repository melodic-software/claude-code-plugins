#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'record-layout.sh: source this file; it is not a command\n' >&2
  exit 2
fi

read -r -d '' RECORD_OPEN_ARRAY_AWK <<'AWK' || true
function open_array(key,   rest) {
  if (!match($0, "\"" key "\"[[:space:]]*:[[:space:]]*\\[")) return
  rest = substr($0, RSTART + RLENGTH)
  if (rest ~ /^[[:space:]]*\]/) { seen[key] = 1; return }
  if (substr($0, 1, RSTART - 1) ~ /^[[:space:]]*$/ && rest ~ /^[[:space:]]*$/) { open = key; return }
  problem = "the " key " array does not start on a line of its own"
}
AWK
RECORD_OPEN_ARRAY_AWK+=$'\n'

read -r -d '' _RECORD_LAYOUT_AWK <<'AWK' || true
BEGIN {
  shape["repositories"] = "^[[:space:]]*[{]\"name\":"
  shape["edges"] = "^[[:space:]]*[{]\"from\":"
}
open != "" {
  if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) { seen[open] = 1; open = ""; next }
  if ($0 !~ shape[open]) { problem = "line " NR " is not one " open " object"; exit }
  next
}
{
  open_array("repositories")
  if (problem == "" && open == "") open_array("edges")
  if (problem != "") exit
}
END {
  if (problem == "" && open != "") problem = "the " open " array never closes"
  if (problem == "" && !("repositories" in seen)) problem = "no repositories array was found"
  if (problem == "" && !("edges" in seen)) problem = "no edges array was found"
  print problem
}
AWK
_RECORD_LAYOUT_AWK="$RECORD_OPEN_ARRAY_AWK$_RECORD_LAYOUT_AWK"

record_layout_problem() {
  awk "$_RECORD_LAYOUT_AWK" "$1"
}
