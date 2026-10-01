#!/usr/bin/env bash
# Time test-scan.sh end to end and resolve-config.sh --quick alone for each
# team-layer configuration: none, .claude/testing.yaml only, the docs block
# only, and both. One sample of every arm per iteration, in interleaved order,
# after a warm-up pass; p50 and p95 in milliseconds.
#
# Usage: time-config.sh [samples]     default 50
set -uo pipefail

N="${1:-50}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../hooks/test-scan.sh"
RESOLVER="$HERE/resolve-config.sh"
FIXTURE="$HERE/../skills/audit/evals/fixtures/positive/cant-fail-js.test.js"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
export CLAUDE_PLUGIN_DATA="$W/data" CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED=true HOME="$W/home"
mkdir -p "$HOME"

# The same team config in both locations: two excludes, a rule level, an extend list.
BODY="paths:
  exclude:
    - 'vendor/**'
    - 'generated/**'
rules:
  test-weaken-block: error
extend:
  js-vitest:
    files:
      - '*.it.js'"

ARMS=(none claude docs both)
for arm in "${ARMS[@]}"; do
  r="$W/$arm"
  mkdir -p "$r/src"
  git -C "$r" init -q
  cp "$FIXTURE" "$r/src/a.test.js"
  if [[ $arm == claude || $arm == both ]]; then
    mkdir -p "$r/.claude"
    printf '%s\n' "$BODY" >"$r/.claude/testing.yaml"
  fi
  if [[ $arm == docs || $arm == both ]]; then
    mkdir -p "$r/docs/conventions"
    # shellcheck disable=SC2016 # the fence is literal text
    printf '# Testing\n\nProse rules.\n\n```yaml config\n%s\n```\n' "$BODY" >"$r/docs/conventions/testing.md"
  fi
done

payload() {
  jq -cn --arg f "$W/$1/src/a.test.js" --arg u "$2" --arg c "$W/$1" \
    '{hook_event_name:"PostToolUse",tool_name:"Write",session_id:"s",tool_use_id:$u,cwd:$c,
      tool_input:{file_path:$f},tool_response:{type:"create",structuredPatch:[]}}'
}
hook_arm() { payload "$1" "$2" | CLAUDE_PROJECT_DIR="$W/$1" bash "$HOOK" >/dev/null 2>&1; }
resolver_arm() { bash "$RESOLVER" --quick --root "$W/$1" >/dev/null 2>&1; }

# us <command...>: wall time of the command in microseconds.
us() {
  local t0=$EPOCHREALTIME
  "$@"
  local t1=$EPOCHREALTIME
  echo $((${t1/./} - ${t0/./}))
}

for arm in "${ARMS[@]}"; do
  out="$(payload "$arm" "w-$arm" | CLAUDE_PROJECT_DIR="$W/$arm" bash "$HOOK" 2>&1)"
  if [[ $out != *rule-recomputed-expectation* ]]; then
    echo "arm $arm did not emit the finding: ${out:0:300}" >&2
    exit 1
  fi
  resolver_arm "$arm"
done

for i in $(seq "$N"); do
  for arm in "${ARMS[@]}"; do
    echo "hook $arm $(us hook_arm "$arm" "u$i-$arm")"
    echo "resolver $arm $(us resolver_arm "$arm")"
  done
done >"$W/samples"

printf '%-9s %-7s %9s %9s\n' stage config p50_ms p95_ms
for stage in hook resolver; do
  for arm in "${ARMS[@]}"; do
    awk -v s="$stage" -v a="$arm" '$1 == s && $2 == a {print $3}' "$W/samples" | sort -n |
      awk -v s="$stage" -v a="$arm" '{v[NR]=$1} END {
        printf "%-9s %-7s %9.1f %9.1f\n", s, a, v[int((NR + 1) / 2)] / 1000, v[int(NR * 0.95 + 0.999999)] / 1000 }'
  done
done
printf 'samples %d per row; load %s\n' "$N" "$(cut -d' ' -f1-3 /proc/loadavg)"
