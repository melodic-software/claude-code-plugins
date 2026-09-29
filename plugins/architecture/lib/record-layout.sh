#!/usr/bin/env bash
# The layout a landscape record must have for line-based readers to read it.
#
# Source this file. record_layout_problem FILE prints the first problem, or
# nothing when FILE has the layout.
#
# landscape-record.sh and render-landscape.sh recover the record's arrays by
# line, so a record that is valid JSON in another layout (compacted, or one key
# per line) would recover nothing and read as empty. In the layout, each of
# `repositories` and `edges` is either empty on its key's line, or opens alone
# on that line and holds one object of the expected shape per line until its
# closing bracket.
#
# Executing this file prints usage and exits 2.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'record-layout.sh: source this file; it is not a command\n' >&2
  exit 2
fi

read -r -d '' _RECORD_LAYOUT_AWK <<'AWK' || true
BEGIN {
  shape["repositories"] = "^[[:space:]]*[{]\"name\":"
  shape["edges"] = "^[[:space:]]*[{]\"from\":"
}
function open_array(key,   rest) {
  if (!match($0, "\"" key "\"[[:space:]]*:[[:space:]]*\\[")) return
  rest = substr($0, RSTART + RLENGTH)
  if (rest ~ /^[[:space:]]*\]/) { seen[key] = 1; return }
  if (substr($0, 1, RSTART - 1) ~ /^[[:space:]]*$/ && rest ~ /^[[:space:]]*$/) { open = key; return }
  problem = "the " key " array does not start on a line of its own"
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

record_layout_problem() {
  awk "$_RECORD_LAYOUT_AWK" "$1"
}
