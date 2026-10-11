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

check "re-cache size just under a million rounds to M, not 1000k" \
  '{"prompt_cache":{"warm":false,"recache_tokens_if_cold":999600}}' \
  'cache ○ cold · next message re-caches ~1M'

check "re-cache size under a thousand prints the count" \
  '{"prompt_cache":{"warm":false,"recache_tokens_if_cold":640}}' \
  'cache ○ cold · next message re-caches ~640'

check "an array prompt_cache prints nothing" \
  '{"prompt_cache":[]}' \
  ''

check "a prompt_cache without warm prints nothing" \
  '{"prompt_cache":{"hit_ratio":0.5}}' \
  ''

check "control characters in payload strings are stripped" \
  '{"prompt_cache":{"warm":true,"ttl":"1h\u001b]52;c;eA==\u0007","expires_at":1767227520,"misses":1,"last_miss_cause":{"causes":["tools\u001b[2J_changed"]}}}' \
  'cache ● warm until 00:32 (1h]52;c;eA==) · misses 1 (last: tools[2J_changed)'

out="$(printf '%s' '{"prompt_cache":{"warm":true,"ttl":"1h","expires_at":1767227520}}' | TZ=UTC node "$SUT")"
if [[ "$out" == *$'\e[32m●\e[0m'* ]]; then
  pass "color is on unless NO_COLOR is set"
else
  fail "color default: [$out]"
fi

out="$(printf '%s' '{"prompt_cache":{"warm":true,"ttl":"1h","expires_at":1767227520}}' | TZ=UTC NO_COLOR="" node "$SUT")"
if [[ "$out" == *$'\e[32m●\e[0m'* ]]; then
  pass "an empty NO_COLOR leaves color on"
else
  fail "empty NO_COLOR: [$out]"
fi

# --after runs the existing command on the same stdin, then prints the segment.
payload='{"model":{"display_name":"Opus"},"prompt_cache":{"warm":false,"recache_tokens_if_cold":82340}}'
want=$'model Opus\ncache ○ cold · next message re-caches ~82k'
# shellcheck disable=SC2016 # the command is expanded by the shell --after starts
out="$(printf '%s' "$payload" | TZ=UTC NO_COLOR=1 node "$SUT" --after 'printf "model %s" "$(node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>process.stdout.write(JSON.parse(s).model.display_name))")"')"
if [[ "$out" == "$want" ]]; then
  pass "--after keeps the existing command's output and adds the segment on its own line"
else
  fail "--after: got [$out] want [$want]"
fi

# shellcheck disable=SC2016 # the command is expanded by the shell --after starts
out="$(printf '%s' '{}' | NO_COLOR=1 node "$SUT" --after 'a=(x y); [[ ${#a[@]} -eq 2 ]] && echo bash-syntax')"
if [[ "$out" == "bash-syntax" ]]; then
  pass "--after runs the existing command under bash"
else
  fail "--after bash syntax: [$out]"
fi

out="$(printf 'not json' | NO_COLOR=1 node "$SUT" --after 'echo kept')"
if [[ "$out" == "kept" ]]; then
  pass "--after still prints the existing output when the payload is not JSON"
else
  fail "--after bad payload: [$out]"
fi

# --wire prints the statusLine object, quoting the existing command as one shell word.
wire() { printf '%s' "$1" | node "$SUT" --wire 2>/dev/null; }

out="$(wire '{}')"
if [[ "$(jq -r '.statusLine.command' <<<"$out")" == 'node ~/.claude/context-guard/cache-line.mjs' &&
"$(jq -r '.statusLine.type' <<<"$out")" == 'command' ]]; then
  pass "--wire with no statusLine prints the bare segment command"
else
  fail "--wire bare: $out"
fi

tricky=$'bash -c \'echo "it\'\\\'\'s $(date) (x)"\''
settings="$(jq -n --arg c "$tricky" '{statusLine:{type:"command",command:$c,padding:2,refreshInterval:5}}')"
out="$(wire "$settings")"
cmd="$(jq -r '.statusLine.command' <<<"$out")"
inner="$(sh -c "set -- ${cmd#node ~/.claude/context-guard/cache-line.mjs --after }; printf '%s' \"\$1\"")"
if [[ "$inner" == "$tricky" &&
  "$(jq -r '.statusLine.padding' <<<"$out")" == "2" &&
  "$(jq -r '.statusLine.refreshInterval' <<<"$out")" == "5" ]]; then
  pass "--wire wraps a command with quotes, \$() and parentheses as one word and keeps other keys"
else
  fail "--wire tricky: cmd=[$cmd] inner=[$inner] want=[$tricky]"
fi

out="$(printf '%s' '{"statusLine":{"type":"command","command":"node ~/.claude/context-guard/cache-line.mjs --after x"}}' | node "$SUT" --wire 2>&1 >/dev/null)"
if [[ "$out" == *"already wired"* ]]; then
  pass "--wire on an already-wired statusLine says so"
else
  fail "--wire idempotent: [$out]"
fi

if ! printf 'nope' | node "$SUT" --wire >/dev/null 2>&1; then
  pass "--wire refuses settings that are not JSON"
else
  fail "--wire accepted invalid JSON"
fi

if [[ $fails -gt 0 ]]; then
  echo "$fails failure(s)" >&2
  exit 1
fi
