# shellcheck shell=bash

unset SESSION_ATTENDED_VAR SESSION_ATTENDED_VALUE SESSION_ATTENDED_ENTRYPOINT_VAR SESSION_ATTENDED_HEADLESS_ENTRYPOINTS
# shellcheck source=/dev/null
. "${BASH_SOURCE[0]%/*}/session-attended.env" 2>/dev/null || true

hook::session_attended() {
  [[ -n ${SESSION_ATTENDED_VAR-} && -n ${SESSION_ATTENDED_ENTRYPOINT_VAR-} && -n ${SESSION_ATTENDED_VALUE-} ]] || return 1
  local name
  for name in "$SESSION_ATTENDED_VAR" "$SESSION_ATTENDED_ENTRYPOINT_VAR"; do
    [[ $name != [0-9]* && $name != *[!A-Za-z0-9_]* ]] || return 1
  done
  [[ ${!SESSION_ATTENDED_VAR-} == "$SESSION_ATTENDED_VALUE" ]] || return 1
  local entrypoint=${!SESSION_ATTENDED_ENTRYPOINT_VAR-}
  [[ -z $entrypoint || " ${SESSION_ATTENDED_HEADLESS_ENTRYPOINTS-} " != *" $entrypoint "* ]]
}
