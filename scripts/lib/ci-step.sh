# shellcheck shell=bash

ci_step::read() {
  local step
  step="$(awk -v name="      - name: $2" '$0 == name { on = 1; print; next }
    on && /^      - / { exit }
    on { print }' "$1")"
  awk '/^        run: \|$/ { on = 1; next }
    on && /^          / { print substr($0, 11); next }
    on && /^[[:blank:]]*$/ { print ""; next }
    on { exit }' <<<"$step" >"$3"
  printf '%s\n' "$step"
  [[ -s "$3" ]]
}

ci_step::abort() {
  fail "no '$2' step with a run: | body in $1"
  test_harness::report
  exit 1
}
