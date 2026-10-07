#!/usr/bin/env bash
# Clean L2 runs on a local machine: each trial is a fresh `claude -p --bare` process started in the
# trial's own directory, so no repository instructions, plugins or skill listing reach the agent.
# Needs: node 22+, claude on PATH (signed in), both tools installed, the fixture server running
# (node fixtures/server.mjs), and BT_CHROME pointing at a Chromium both tools can drive.
#
#   ./run-bare.sh [runs-per-case=5] [model] [effort]
#
# Results append to $BT_RESULTS/l2.jsonl (default results/<date>/l2.jsonl).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
runs="${1:-5}"
model="${2:-}"
effort="${3:-}"
extra=()
[[ -n "$model" ]] && extra+=(--model "$model")
[[ -n "$effort" ]] && extra+=(--effort "$effort")

trial() { # task tool rep [arm]
  local info dir prompt run
  info="$(node "$here/run-l2.mjs" prepare --task "$1" --tool "$2" --rep "$3" --arm "${4:-default}")"
  run="$(node -e 'console.log(JSON.parse(process.argv[1]).run)' "$info")"
  dir="$(node -e 'console.log(JSON.parse(process.argv[1]).dir)' "$info")"
  prompt="$(node -e 'console.log(JSON.parse(process.argv[1]).promptFile)' "$info")"
  local start end
  start="$(date +%s%3N)"
  local args=(-p --bare --output-format stream-json --verbose
    --permission-mode acceptEdits --allowedTools "Bash" "${extra[@]}")
  (cd "$dir" && claude "${args[@]}" <"$prompt" >"$dir/transcript.jsonl") || true # prereq-ok: maintainer benchmark harness, not run by the plugin on a user's machine
  end="$(date +%s%3N)"
  node "$here/run-l2.mjs" grade --run "$run" --transcript "$dir/transcript.jsonl" \
    --usage "{\"wallMs\":$((end - start)),\"driver\":\"claude -p --bare\"}"
}

for rep in $(seq 1 "$runs"); do
  for task in T01 T02 T03 T04 T05 T06 T07 T08 T09 T10 T11 T12; do
    for tool in playwright-cli agent-browser; do trial "$task" "$tool" "$rep"; done
  done
  trial T09 agent-browser "$rep" boundaries
done
