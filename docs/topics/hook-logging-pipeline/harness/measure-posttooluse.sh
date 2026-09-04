#!/usr/bin/env bash
# Reproduces the PostToolUse hook measurements recorded in ../FINDINGS.md.
#
# Throwaway diagnostic, not a fleet component: it is committed so the numbers in
# FINDINGS.md can be reproduced rather than cited, and it is expected to be
# pruned with the rest of the topic slice before merge.
#
# Usage:  bash measure-posttooluse.sh [N]        (N = samples per row, default 15)
#
# METHOD RULES, both learned by getting them wrong first. Read before trusting
# any number this or any successor harness prints.
#
#   RULE 1 - PUT THE REAL FILE TEXT IN THE PAYLOAD. A PostToolUse hook reads
#   tool_input.content from the payload, not the file on disk. A synthetic
#   payload carrying content "x" makes a content-scanning hook short-circuit, so
#   the harness measures a no-op and reports it as the hook's cost. This is not
#   specific to one hook: skill-reference-verify measured 33.9 ms with a stub
#   payload and 622.1 ms with the real text, an 18x error, because its plugin
#   index build is gated on references found in that content.
#
#   RULE 2 - SPAWN-EQUIVALENTS ONLY SURVIVE A HOST CHANGE FOR SPAWN-DOMINATED
#   HOOKS. Dividing by the spawn floor S is sound for a hook whose cost is
#   process creation. It is NOT sound for a work-dominated hook: markdown-format
#   is mostly Node startup plus a markdownlint scan, near-constant in absolute
#   ms, so its S-ratio inflates as the measuring host gets faster and any
#   conversion to a slower reference host overstates it. Report both numbers and
#   say which class each hook is in.
#
#   The spawn floor is re-measured for every row rather than once per run, so a
#   ratio is never taken against a floor sampled under different load.

set -uo pipefail

N=${1:-15}
REPO=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "not inside a git checkout" >&2
  exit 2
}
P="$REPO/plugins"
SAMPLES="$REPO/.hook-measure-samples"

command -v jq >/dev/null 2>&1 || {
  echo "jq is required" >&2
  exit 2
}

cleanup() { rm -rf "$SAMPLES"; }
trap cleanup EXIT

# Build the sample tree INSIDE the repo: hooks resolve the project root and
# early-exit on a path outside it, so an out-of-repo sample measures an exit.
mkdir -p "$SAMPLES"
printf '# Sample\n\nA short paragraph used only to measure hook latency.\n\n- one\n- two\n' \
  >"$SAMPLES/sample.md"
printf 'A plain text file used only to measure hook latency.\n' >"$SAMPLES/sample.txt"
printf 'def main() -> None:\n    print("sample")\n' >"$SAMPLES/sample.py"
printf '#!/usr/bin/env bash\nset -euo pipefail\n\necho "sample"\n' >"$SAMPLES/sample.sh"
printf 'export function sample(): string {\n  return "sample";\n}\n' >"$SAMPLES/sample.ts"
# Carries /plugin:skill references, which is what triggers the expensive path in
# skill-reference-verify. Without them that hook measures a different thing.
# shellcheck disable=SC2016 # backticks are literal Markdown in the sample text, expansion would break the fixture
printf '# Reference sample\n\nRun `/planning:interview`, then `/planning:plan`.\nSee `/session-flow:handoff`.\n' \
  >"$SAMPLES/ref.md"

# One PostToolUse payload, shaped as Claude Code sends it. RULE 1 lives here:
# content is the real file text, never a stub.
payload() { # $1 = tool, $2 = absolute file path
  jq -nc --arg f "$2" --arg c "$(cat "$2")" --arg cwd "$REPO" --arg t "$1" '{
    session_id: "measure", transcript_path: "/tmp/measure.jsonl", cwd: $cwd,
    hook_event_name: "PostToolUse", tool_name: $t,
    tool_input: { file_path: $f, content: $c },
    tool_response: { filePath: $f, success: true },
    tool_use_id: "toolu_measure", permission_mode: "default", prompt_id: "measure"
  }'
}

floor() {
  local t0 t1 i
  t0=$EPOCHREALTIME
  for ((i = 0; i < N; i++)); do bash -c :; done
  t1=$EPOCHREALTIME
  echo "($t1 - $t0) * 1000 / $N" | bc -l
}

row() { # $1 = label, $2 = hook script, $3 = payload, rest = extra argv
  local label="$1" script="$2" data="$3"
  shift 3
  local t0 t1 i ms s
  printf '%s' "$data" | bash "$script" "$@" >/dev/null 2>&1 # warm
  t0=$EPOCHREALTIME
  for ((i = 0; i < N; i++)); do printf '%s' "$data" | bash "$script" "$@" >/dev/null 2>&1; done
  t1=$EPOCHREALTIME
  ms=$(echo "($t1 - $t0) * 1000 / $N" | bc -l)
  s=$(floor)
  printf '%-42s %8.1f ms   %6.1f S\n' "$label" "$ms" "$(echo "$ms / $s" | bc -l)"
}

md=$(payload Write "$SAMPLES/sample.md")
txt=$(payload Write "$SAMPLES/sample.txt")
ref=$(payload Write "$SAMPLES/ref.md")

printf 'spawn floor S = %.2f ms   (N=%s)\n\n' "$(floor)" "$N"

echo "== formatters on a file they handle =="
row "markdown-format (.md)" "$P/markdown-format/hooks/markdown-format.sh" "$md"
row "typos-format (.md)" "$P/typos-format/hooks/typos-format.sh" "$md"
row "eol-normalizer (.md)" "$P/eol-normalizer/hooks/eol-normalizer.sh" "$md"
row "ruff-format (.py)" "$P/ruff-format/hooks/ruff-format.sh" "$(payload Write "$SAMPLES/sample.py")"
row "bash-format (.sh)" "$P/bash-format/hooks/bash-format.sh" "$(payload Write "$SAMPLES/sample.sh")"
row "biome-format (.ts)" "$P/biome-format/hooks/biome-format.sh" "$(payload Write "$SAMPLES/sample.ts")"

echo
echo "== the three ungated rows, on a .txt they have nothing to say about =="
row "typos-format (.txt)" "$P/typos-format/hooks/typos-format.sh" "$txt"
row "eol-normalizer (.txt)" "$P/eol-normalizer/hooks/eol-normalizer.sh" "$txt"
row "guardrails trio (.txt)" "$P/guardrails/hooks/run-guards.sh" "$txt" \
  cli-flag-verify.sh skill-reference-verify.sh stale-path-verify.sh

echo
echo "== RULE 1 demonstrated: same hook, same file, payload content differs =="
row "skill-reference-verify (with refs)" "$P/guardrails/hooks/skill-reference-verify.sh" "$ref"
row "skill-reference-verify (no refs)" "$P/guardrails/hooks/skill-reference-verify.sh" "$md"

echo
echo "== disabled-path cost: the switch is read AFTER the library is sourced =="
CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=false \
  row "markdown-format DISABLED" "$P/markdown-format/hooks/markdown-format.sh" "$md"
CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=false \
  row "typos-format DISABLED" "$P/typos-format/hooks/typos-format.sh" "$md"
CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED=false \
  row "eol-normalizer DISABLED" "$P/eol-normalizer/hooks/eol-normalizer.sh" "$md"

echo
echo "== reference floors =="
printf '%-42s %8.1f ms\n' "bash -c : (spawn floor)" "$(floor)"
t0=$EPOCHREALTIME
for ((i = 0; i < N; i++)); do bash -c "source '$REPO/lib/hook-utils.sh'"; done
t1=$EPOCHREALTIME
printf '%-42s %8.1f ms\n' "spawn + source lib/hook-utils.sh" "$(echo "($t1 - $t0) * 1000 / $N" | bc -l)"

echo
echo "== the skill-reference-verify index loop, isolated =="
t0=$EPOCHREALTIME
for m in "$P"/*/.claude-plugin/plugin.json; do
  jq -r '.name // empty' "$m" 2>/dev/null | tr -d '\r' >/dev/null
  jq -r '.skills // empty | if type == "array" then .[] else . end' "$m" 2>/dev/null | tr -d '\r' >/dev/null
done
t1=$EPOCHREALTIME
printf '%-42s %8.1f ms  (%s manifests, 4 procs each)\n' "per-manifest loop, as written" \
  "$(echo "($t1 - $t0) * 1000" | bc -l)" "$(find "$P" -path '*/.claude-plugin/plugin.json' | wc -l)"
t0=$EPOCHREALTIME
jq -rs '.[] | (.name // empty)' "$P"/*/.claude-plugin/plugin.json >/dev/null 2>&1
t1=$EPOCHREALTIME
printf '%-42s %8.1f ms\n' "one batched jq, same work" "$(echo "($t1 - $t0) * 1000" | bc -l)"
