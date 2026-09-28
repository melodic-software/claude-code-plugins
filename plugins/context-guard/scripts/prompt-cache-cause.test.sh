#!/usr/bin/env bash
# prompt-cache-cause.py reads statusline prompt_cache.last_miss_cause.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$ROOT/scripts/prompt-cache-cause.py"
fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

run() {
  printf '%s' "$1" | python3 "$SUT"
}

out="$(run '{"prompt_cache":{"last_miss_cause":{"causes":["tools_changed","system_prompt_changed"],"tools_added":2,"tools_removed":1,"system_char_delta":40}}}')"
rc=$?
if [[ $rc -eq 0 ]] \
  && grep -qx 'causes	tools_changed,system_prompt_changed' <<<"$out" \
  && grep -qx 'tools_added	2' <<<"$out" \
  && grep -qx 'system_char_delta	40' <<<"$out"; then
  pass "cause names and counts"
else
  fail "cause names (rc=$rc): $out"
fi

out="$(run '{"prompt_cache":{"last_miss_cause":null,"misses":0}}')"
rc=$?
if [[ $rc -eq 0 && "$out" == "last_miss_cause	null" ]]; then
  pass "null cause is an undiagnosed miss"
else
  fail "null cause (rc=$rc): $out"
fi

out="$(run '{"context_window":{"used_percentage":8}}')"
rc=$?
if [[ $rc -eq 0 && "$out" == "last_miss_cause	absent" ]]; then
  pass "a payload without prompt_cache is absent, not a miss"
else
  fail "absent field (rc=$rc): $out"
fi

out="$(run '[]' 2>/dev/null)"
rc=$?
if [[ $rc -eq 2 ]]; then
  pass "a non-object exits 2"
else
  fail "non-object should exit 2 (rc=$rc): $out"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
