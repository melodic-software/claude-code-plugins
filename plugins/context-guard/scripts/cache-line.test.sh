#!/usr/bin/env bash
# cache-line.mjs prints one status-line segment from statusline prompt_cache.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$ROOT/scripts/cache-line.mjs"
fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not on PATH"
  exit 0
fi

run() {
  printf '%s' "$1" | TZ=UTC NO_COLOR=1 node "$SUT"
}

check() {
  local name="$1" payload="$2" want="$3" out rc
  out="$(run "$payload")"
  rc=$?
  if [[ $rc -eq 0 && "$out" == "$want" ]]; then
    pass "$name"
  else
    fail "$name (rc=$rc): got [$out] want [$want]"
  fi
}

# 1767225600 is 2026-01-01T00:00:00Z; +1920 s is 00:32 UTC.
check "warm shows the expiry clock time, ttl and hit ratio" \
  '{"prompt_cache":{"warm":true,"ttl":"1h","expires_at":1767227520,"hit_ratio":0.912,"misses":0}}' \
  'cache ● warm until 00:32 (1h) · hit 91%'

check "cold shows the re-cache size rounded to k" \
  '{"prompt_cache":{"warm":false,"expires_at":null,"recache_tokens_if_cold":82340,"hit_ratio":0.5,"misses":0}}' \
  'cache ○ cold · next message re-caches ~82k · hit 50%'

check "a miss with a cause names it" \
  '{"prompt_cache":{"warm":true,"ttl":"5m","expires_at":1767225900,"hit_ratio":0.8,"misses":2,"last_miss_cause":{"causes":["tools_changed","system_prompt_changed"],"tools_added":1}}}' \
  'cache ● warm until 00:05 (5m) · hit 80% · misses 2 (last: tools_changed, system_prompt_changed)'

check "a null cause prints the count alone" \
  '{"prompt_cache":{"warm":true,"ttl":"1h","expires_at":1767227520,"misses":1,"last_miss_cause":null}}' \
  'cache ● warm until 00:32 (1h) · misses 1'

check "cold right after a compaction omits the re-cache size" \
  '{"prompt_cache":{"warm":false,"recache_tokens_if_cold":null,"hit_ratio":null}}' \
  'cache ○ cold'

check "re-cache size past a million uses M" \
  '{"prompt_cache":{"warm":false,"recache_tokens_if_cold":1250000}}' \
  'cache ○ cold · next message re-caches ~1.3M'

check "caching not observed says so" \
  '{"prompt_cache":{"caching_observed":false,"warm":false}}' \
  'cache not reported'

check "a payload without prompt_cache prints nothing" \
  '{"context_window":{"used_percentage":8}}' \
  ''

check "invalid JSON prints nothing" \
  'not json' \
  ''

check "a non-object prompt_cache prints nothing" \
  '{"prompt_cache":"warm"}' \
  ''

out="$(printf '%s' '{"prompt_cache":{"warm":true,"ttl":"1h","expires_at":1767227520}}' | TZ=UTC node "$SUT")"
if [[ "$out" == *$'\e[32m●\e[0m'* ]]; then
  pass "color is on unless NO_COLOR is set"
else
  fail "color default: [$out]"
fi

if [[ $fails -gt 0 ]]; then
  echo "$fails failure(s)" >&2
  exit 1
fi
