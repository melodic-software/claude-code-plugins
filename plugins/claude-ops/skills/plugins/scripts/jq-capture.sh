# shellcheck shell=bash
# Shared jq capture and JSON string encoder for this skill's scripts. Sourced
# (not executed) by cache-content-check.sh, fleet-state.sh and sync-run.sh, the
# way fleet-state.sh sources the plugin's hooks/hook-utils.sh: a fixed sibling
# resolved from the sourcing script's own location, never from a caller-supplied
# env var.
#
# CALLING CONVENTION: both helpers are spelled `<name>_to <var> [args…]` and
# write into the caller's variable instead of printing, so no caller pays a
# command-substitution fork per call. Call them directly rather than wrapping
# them in `$( )`. This is the same convention, for the same reason, that
# lib/hook-utils.sh states for its own `hook::<name>_to` family.

# --- jq capture ---------------------------------------------------------------
# Some native-Windows jq builds CRLF-terminate every line, including single-line
# compact output. `$(...)` strips only the trailing LF, so a stray CR survives at
# the end of a captured value and corrupts it once re-parsed as JSON, and every
# id but the last in a line-oriented output arrives as `<name>@<marketplace>\r`.
# Every jq call goes through this helper, which strips ALL carriage returns in
# the shell (no `tr` process) and stores the result in the named variable.
# Callers never pipe jq to anything: the pipeline would fork a second process for
# the consumer, and a `while read` over a here-string of the captured value costs
# nothing. See context/gotchas.md.
jq_to() {
  local __jq_var="$1"
  shift
  local __jq_out __jq_rc=0
  __jq_out=$(command jq "$@") || __jq_rc=$?
  printf -v "$__jq_var" '%s' "${__jq_out//$'\r'/}"
  return "$__jq_rc"
}

# --- JSON string literal, built with builtins ----------------------------------
# Blocks that the shell assembles around jq's own compact output (the --all
# envelope and the per-marketplace error blocks in fleet-state.sh, the per-install
# records in cache-content-check.sh) still contain strings the shell itself has to
# encode: marketplace names, lastUpdated stamps, paths, ids, verdicts. They get
# the same escaping jq's encoder applies: `\"`, `\\`, the five short control
# escapes, `\u00XX` for every other C0 byte, everything else (including non-ASCII
# and DEL) verbatim.
json_string_to() {
  local __js_s="$2" __js_i __js_c __js_hex __js_out=""
  __js_s="${__js_s//\\/\\\\}"
  __js_s="${__js_s//\"/\\\"}"
  __js_s="${__js_s//$'\n'/\\n}"
  __js_s="${__js_s//$'\r'/\\r}"
  __js_s="${__js_s//$'\t'/\\t}"
  __js_s="${__js_s//$'\b'/\\b}" # portability-ok: JSON short escape for U+0008 in a parameter expansion, not a regex word boundary
  __js_s="${__js_s//$'\f'/\\f}"
  if [[ "$__js_s" == *[$'\x01'-$'\x1f']* ]]; then
    for ((__js_i = 0; __js_i < ${#__js_s}; __js_i++)); do
      __js_c="${__js_s:__js_i:1}"
      if [[ "$__js_c" == [$'\x01'-$'\x1f'] ]]; then
        printf -v __js_hex '\\u%04x' "'$__js_c"
        __js_out+="$__js_hex"
      else
        __js_out+="$__js_c"
      fi
    done
    __js_s="$__js_out"
  fi
  printf -v "$1" '"%s"' "$__js_s"
}
