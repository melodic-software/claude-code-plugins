#!/usr/bin/env bash

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# shellcheck source=hook-test-sink.sh
source "$LIB_DIR/hook-test-sink.sh"
# shellcheck source=hook-utils.sh
source "$LIB_DIR/hook-utils.sh"
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

now_ms() {
  local t=$EPOCHREALTIME
  NOW_MS=$((${t%[.,]*} * 1000 + 10#${t#*[.,]} / 1000))
}

timed_wait() {
  local t0
  now_ms
  t0=$NOW_MS
  wait_for_sink "$1" "$2"
  WAIT_RC=$?
  now_ms
  WAIT_MS=$((NOW_MS - t0))
}

emit_with_sink() {
  local rc_file="$WORK/emit.rc"
  EMIT_OUT=$(
    export HOOK_TELEMETRY_SINK="$1"
    hook::emit_telemetry t-hook PostToolUse ok "$EPOCHREALTIME" '{"tool":"Write"}' "${2:-}"
    echo $? >"$rc_file"
    wait
  )
  EMIT_RC=$(<"$rc_file")
}

BOUND_MS=5000

# shellcheck disable=SC2016  # $1 expands in the child shell, not here
funcs=$(env -i "$BASH" -c 'source "$1" && declare -F' _ "$LIB_DIR/hook-test-sink.sh" 2>&1 | sed 's/^declare -f //')
if [[ "$funcs" == $'check_envelope\nmake_sink\nwait_for_sink' ]]; then
  ok "source: defines check_envelope, make_sink and wait_for_sink and prints nothing"
else
  fail "source: expected exactly check_envelope, make_sink and wait_for_sink, got: $funcs"
fi

: >"$WORK/plain-file"
errf="$WORK/guard.err"
for guard_case in "unset|-u WORK" "a file|WORK=$WORK/plain-file" "a missing path|WORK=$WORK/missing-dir"; do
  guard_label=${guard_case%%|*}
  guard_env=${guard_case#*|}
  # shellcheck disable=SC2016,SC2086  # $1 expands in the child; the env args are split on purpose
  out=$(env $guard_env "$BASH" -c 'source "$1" && make_sink :' _ "$LIB_DIR/hook-test-sink.sh" 2>"$errf")
  rc=$?
  if [[ $rc -eq 2 && -z "$out" ]] && grep -q 'WORK' "$errf"; then
    ok "make_sink: WORK $guard_label -> status 2, message on stderr, no path"
  else
    fail "make_sink: WORK $guard_label: expected status 2, a message and no path; got status $rc, out [$out], err [$(<"$errf")]"
  fi
done
unset guard_case guard_label guard_env out rc

CAP_A="$WORK/cap-a"
sink_a=$(make_sink "cat >\"$CAP_A\"")
rc=$?
if [[ $rc -eq 0 && -x "$sink_a" ]]; then
  ok "make_sink: returns 0 and an executable stub"
else
  fail "make_sink: status $rc, path [$sink_a] is not an executable file"
fi
if [[ -n "$sink_a" && "$sink_a" != *[[:space:]]* ]]; then
  ok "make_sink: the path is one word, no whitespace or arguments"
else
  fail "make_sink: the path is empty or holds whitespace: [$sink_a]"
fi
if [[ "$sink_a" == "$WORK"/sink.* ]]; then
  ok "make_sink: the stub lives under \$WORK"
else
  fail "make_sink: the stub is outside \$WORK: $sink_a"
fi
if [[ "$(head -n 1 "$sink_a")" == '#!/usr/bin/env bash' ]]; then
  ok "make_sink: the stub starts with the bash shebang"
else
  fail "make_sink: unexpected first line: $(head -n 1 "$sink_a")"
fi
sink_a2=$(make_sink ':')
if [[ -n "$sink_a2" && "$sink_a2" != "$sink_a" ]]; then
  ok "make_sink: each call returns a distinct path"
else
  fail "make_sink: a second call returned [$sink_a2] after [$sink_a]"
fi
(printf '{"probe":"a"}\n' | "$sink_a") &
if wait_for_sink "$CAP_A"; then
  ok "wait_for_sink: sees the file the stub captured stdin into"
else
  fail "wait_for_sink: the capture file never became non-empty"
fi
wait
if [[ "$(<"$CAP_A")" == '{"probe":"a"}' ]]; then
  ok "make_sink: the stub body received the stdin envelope"
else
  fail "make_sink: captured [$(<"$CAP_A")]"
fi

CAP_B="$WORK/cap-b"
sink_b=$(make_sink ':')
emit_with_sink "$sink_b"
if [[ $EMIT_RC -eq 0 && -z "$EMIT_OUT" ]]; then
  ok "never-firing sink: hook::emit_telemetry still returns 0 with nothing on stdout"
else
  fail "never-firing sink: status $EMIT_RC, stdout [$EMIT_OUT]"
fi
timed_wait "$CAP_B" 5
if [[ $WAIT_RC -ne 0 ]]; then
  ok "never-firing sink: wait_for_sink returns non-zero instead of passing"
else
  fail "never-firing sink: wait_for_sink returned 0 for a file nothing wrote"
fi
if [[ $WAIT_MS -lt $BOUND_MS ]]; then
  ok "never-firing sink: the failure arrives within the bound ($WAIT_MS ms)"
else
  fail "never-firing sink: the wait took $WAIT_MS ms, bound $BOUND_MS ms"
fi
: >"$CAP_B"
if ! wait_for_sink "$CAP_B" 5; then
  ok "wait_for_sink: an existing but empty file does not count as delivered"
else
  fail "wait_for_sink: returned 0 for an empty file"
fi

CAP_C="$WORK/cap-c"
TEE=$(command -v tee)
printf 'control\n' | "$TEE" "$CAP_C" >/dev/null
if [[ "$(<"$CAP_C")" == control ]]; then
  ok "control: the same tee command line delivers when the shell splits it"
else
  fail "control: [$TEE $CAP_C] did not deliver even when split"
fi
for args_sink in "$TEE $CAP_C" "tee $CAP_C"; do
  rm -f "$CAP_C"
  emit_with_sink "$args_sink" "$WORK"
  if [[ ! -e "$CAP_C" ]]; then
    ok "command-with-args sink [${args_sink%% *}...]: nothing is delivered"
  else
    fail "command-with-args sink [$args_sink] delivered: $(<"$CAP_C")"
  fi
  if [[ $EMIT_RC -eq 0 && -z "$EMIT_OUT" ]]; then
    ok "command-with-args sink [${args_sink%% *}...]: fail-open, status 0, silent stdout"
  else
    fail "command-with-args sink [$args_sink]: status $EMIT_RC, stdout [$EMIT_OUT]"
  fi
done
unset args_sink
rm -f "$CAP_C"
sink_c=$(make_sink "cat >\"$CAP_C\"")
emit_with_sink "$sink_c" "$WORK"
if wait_for_sink "$CAP_C"; then
  ok "single-path stub: the envelope is delivered"
else
  fail "single-path stub: nothing was delivered"
fi
if grep -q '"hook":"t-hook"' "$CAP_C" 2>/dev/null; then
  ok "single-path stub: the delivered document is the telemetry envelope"
else
  fail "single-path stub: unexpected capture: $(cat "$CAP_C" 2>/dev/null)"
fi

CAP_D="$WORK/cap-d"
timed_wait "$CAP_D" 1
if [[ $WAIT_RC -ne 0 && $WAIT_MS -lt $BOUND_MS ]]; then
  ok "wait_for_sink tries=1: returns non-zero promptly ($WAIT_MS ms)"
else
  fail "wait_for_sink tries=1: status $WAIT_RC after $WAIT_MS ms"
fi
timed_wait "$CAP_D" 5
if [[ $WAIT_RC -ne 0 && $WAIT_MS -ge 80 && $WAIT_MS -lt $BOUND_MS ]]; then
  ok "wait_for_sink tries=5: polls its five 20ms steps, then stops ($WAIT_MS ms)"
else
  fail "wait_for_sink tries=5: status $WAIT_RC after $WAIT_MS ms, expected 80 to $BOUND_MS ms"
fi
printf 'x\n' >"$CAP_D"
timed_wait "$CAP_D" 1
if [[ $WAIT_RC -eq 0 && $WAIT_MS -lt $BOUND_MS ]]; then
  ok "wait_for_sink tries=1: a file already written returns 0"
else
  fail "wait_for_sink tries=1: status $WAIT_RC after $WAIT_MS ms for a written file"
fi

SCHEMA="$LIB_DIR/../docs/contracts/hook-telemetry/envelope.schema.json"
[[ -s "$SCHEMA" ]] || SCHEMA="$LIB_DIR/../docs/conventions/hook-telemetry/envelope.schema.json"
CAP_E="$WORK/cap-e"
sink_e=$(make_sink "cat >\"$CAP_E\"")
emit_with_sink "$sink_e" "$WORK"
if ! wait_for_sink "$CAP_E"; then
  fail "check_envelope: the real hook::emit_telemetry envelope never arrived"
fi
ENV_GOOD="$WORK/env-good.json"
cp "$CAP_E" "$ENV_GOOD"

expect_envelope() {
  local want="$1" label="$2" err="$WORK/env.err" rc
  check_envelope "${@:3}" 2>"$err"
  rc=$?
  if [[ $want == pass && $rc -eq 0 && ! -s "$err" ]]; then
    ok "check_envelope: $label passes"
  elif [[ $want == fail && $rc -ne 0 && $(wc -l <"$err") -eq 1 ]]; then
    ok "check_envelope: $label fails ($(<"$err"))"
  else
    fail "check_envelope: $label: wanted $want, got status $rc, stderr [$(<"$err")]"
  fi
}

mutate() {
  jq -c "$2" "$ENV_GOOD" >"$WORK/$1.json"
  printf '%s' "$WORK/$1.json"
}

expect_envelope pass "the real hook::emit_telemetry envelope against the real schema" "$ENV_GOOD"
expect_envelope pass "an explicit schema-file argument" "$ENV_GOOD" "$SCHEMA"
HOOK_ENVELOPE_SCHEMA="$SCHEMA" expect_envelope pass "the HOOK_ENVELOPE_SCHEMA override" "$ENV_GOOD"

home_case() {
  local label="$1" repo="$WORK/home-${RANDOM}" home
  shift
  mkdir -p "$repo/lib"
  cp "$LIB_DIR/hook-test-sink.sh" "$repo/lib/"
  for home in "$@"; do
    mkdir -p "$repo/docs/$home/hook-telemetry"
    cp "$SCHEMA" "$repo/docs/$home/hook-telemetry/envelope.schema.json"
  done
  if [[ " $* " == *" contracts "* ]]; then
    mkdir -p "$repo/docs/conventions/hook-telemetry"
    # shellcheck disable=SC2016  # $ref is a JSON key, not a shell expansion
    printf '{"$ref": "../../contracts/hook-telemetry/envelope.schema.json"}\n' \
      >"$repo/docs/conventions/hook-telemetry/envelope.schema.json"
  fi
  if (
    unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
    git init -q "$repo" &&
      . "$repo/lib/hook-test-sink.sh" &&
      check_envelope "$ENV_GOOD" 2>"$WORK/home.err"
  ); then
    ok "check_envelope: the default schema resolves $label"
  else
    fail "check_envelope: the default schema should resolve $label: $(<"$WORK/home.err")"
  fi
}
home_case "under docs/conventions/ alone (before the move)" conventions
home_case "under docs/contracts/ past the stub at docs/conventions/ (after the move)" contracts

mapfile -t REQUIRED < <(jq -r '.required[]' "$SCHEMA")
if ((${#REQUIRED[@]} > 0)); then
  ok "the real schema lists ${#REQUIRED[@]} required fields"
else
  fail "the real schema lists no required fields"
fi
for field in "${REQUIRED[@]}"; do
  expect_envelope fail "missing $field" "$(mutate "no-$field" "del(.$field)")"
done
expect_envelope fail "duration_ms as a string" "$(mutate dur-str '.duration_ms = "12"')"
expect_envelope fail "duration_ms negative" "$(mutate dur-neg '.duration_ms = -1')"
expect_envelope fail "duration_ms a float" "$(mutate dur-float '.duration_ms = 1.5')"
expect_envelope pass "duration_ms a whole number written as a float" "$(mutate dur-whole '.duration_ms = 3.0')"
expect_envelope fail "status as a number" "$(mutate status-num '.status = 1')"
expect_envelope fail "data as an array" "$(mutate data-arr '.data = []')"
expect_envelope fail "an optional property with the wrong type" "$(mutate sid-num '.session_id = 5')"
expect_envelope pass "an unknown extra property" "$(mutate extra '.extra = true')"
printf 'not json\n' >"$WORK/env-text.json"
expect_envelope fail "non-JSON text" "$WORK/env-text.json"
printf '[]\n' >"$WORK/env-array.json"
expect_envelope fail "a JSON array" "$WORK/env-array.json"
: >"$WORK/env-empty.json"
expect_envelope fail "an empty envelope file" "$WORK/env-empty.json"
expect_envelope fail "a missing envelope file" "$WORK/env-absent.json"
expect_envelope fail "no envelope argument"

expect_envelope fail "a missing schema path" "$ENV_GOOD" "$WORK/no-such.schema.json"
: >"$WORK/empty.schema.json"
expect_envelope fail "an empty schema file" "$ENV_GOOD" "$WORK/empty.schema.json"
jq '.required = []' "$SCHEMA" >"$WORK/norequired.schema.json"
expect_envelope fail "a schema with an empty required list" "$ENV_GOOD" "$WORK/norequired.schema.json"
jq 'del(.required)' "$SCHEMA" >"$WORK/nokey.schema.json"
expect_envelope fail "a schema with no required list" "$ENV_GOOD" "$WORK/nokey.schema.json"

jq '.required += ["added_field"] | .properties.added_field = {type: "string"}' "$SCHEMA" >"$WORK/added.schema.json"
expect_envelope fail "the good envelope against a schema copy that requires a new field" "$ENV_GOOD" "$WORK/added.schema.json"
jq '.properties.hook.type = "integer"' "$SCHEMA" >"$WORK/retyped.schema.json"
expect_envelope fail "the good envelope against a schema copy that retypes hook" "$ENV_GOOD" "$WORK/retyped.schema.json"
jq '.properties.duration_ms.minimum = 1000000' "$SCHEMA" >"$WORK/minimum.schema.json"
expect_envelope fail "the good envelope against a schema copy that raises the duration_ms minimum" "$ENV_GOOD" "$WORK/minimum.schema.json"
jq 'del(.required[] | select(. == "data"))' "$SCHEMA" >"$WORK/relaxed.schema.json"
expect_envelope pass "an envelope without data against a schema copy that no longer requires it" "$(mutate no-data-relaxed 'del(.data)')" "$WORK/relaxed.schema.json"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
