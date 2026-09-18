# shellcheck shell=bash
# Shared trust boundary for manifest-pointed hook config paths. Sourced, never
# executed.
#
# check-hook-exec-form.sh and check-hook-userconfig-argv.sh both follow a plugin
# manifest's `hooks` string/array value to another file, and a manifest is input
# the gate does not control. A value that leaves the plugin directory -- an
# absolute path, a Windows drive letter, or any `..` segment -- is refused
# rather than followed, so a crafted manifest cannot point a gate at files
# outside the tree it claims to scan.
#
# The refusal is a VISIBLE skip (scripts/check-silent-skips.sh), and both gates'
# suites assert the wording of that line, so it is a CI contract: only the
# leading script name differs between the two.
#
# The test is a portable string check on purpose: no realpath, no `readlink -f`,
# nothing that would need the BSD fallback ladder.
#
# Usage:
#
#   manifest_path_guard::resolve_to <out-var> <gate> <manifest> <plugin> <rel>
#
# Writes `<plugin>/<rel>` (a leading `./` removed) into <out-var> when <rel>
# stays inside the plugin, and the empty string when it does not, or when <rel>
# is empty. <gate> leads the skip line. It always returns 0 so a caller under
# errexit tests the out-var rather than running the call in a condition context,
# which would disable errexit for the whole callee.
#
# Every local carries the `_mpg_` prefix: a bash nameref resolves in the scope
# where it is USED, so an unprefixed local sharing the caller's out-var name
# would shadow that caller's variable (scripts/lib/read-list.sh records the
# measurement).

# manifest_path_guard::resolve_to <out-var> <gate> <manifest> <plugin> <rel>
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
