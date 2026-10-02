#!/usr/bin/env bash
# list-targets.sh [--root <dir>]: read-only. Prints the drift-audit workflow's
# repo-mode args.targets as one JSON array of {area, files[]}: the tracked
# markdown files in <dir> (default: the current repository) that state a
# model, effort, workflow or subagent claim. Out of scope: docs/upstream/
# snapshots, changelogs, vendored trees and eval fixtures. An area is
# plugins/<name> or the first path segment ("(root)" for top-level files),
# split into chunks of at most 10 files.
set -uo pipefail

ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --root)
    [[ $# -gt 1 ]] || {
      echo "list-targets: --root needs a directory" >&2
      exit 2
    }
    ROOT="$2"
    shift 2
    ;;
  *)
    echo "list-targets: unknown argument '$1'" >&2
    exit 2
    ;;
  esac
done
[[ -n "$ROOT" ]] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "list-targets: not inside a git repository; pass --root" >&2
  exit 2
}
cd "$ROOT" || exit 2

CLAIMS='\b(opus|sonnet|haiku|fable)\b|\beffort\b.{0,30}\b(low|medium|high|xhigh|max)\b|^model:|CLAUDE_CODE_(SUBAGENT_MODEL|DISABLE_WORKFLOWS)|\bWorkflow (tool|script)|dynamic workflow|subagents?.{0,20}(model|depth|concurren)'
EXCLUDE='(^|/)(docs/upstream|vendor|node_modules|fixtures?|evals?)/|(^|/)CHANGELOG[^/]*$'

git ls-files -z -- '*.md' |
  tr '\0' '\n' |
  grep -vE "$EXCLUDE" |
  while IFS= read -r f; do
    [[ -f "$f" && ! -L "$f" ]] && grep -qEi -- "$CLAIMS" "$f" && printf '%s\n' "$f"
  done |
  awk '
    function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    {
      if ($0 ~ /^plugins\/[^\/]+\//) { split($0, p, "/"); area = "plugins/" p[2] }
      else if (index($0, "/")) area = substr($0, 1, index($0, "/") - 1)
      else area = "(root)"
      if (!(area in count)) order[++areas] = area
      k = int(count[area]++ / 10)
      chunk[area, k] = chunk[area, k] (chunk[area, k] == "" ? "" : ",") "\"" esc($0) "\""
      chunks[area] = k + 1
    }
    END {
      printf "["
      for (i = 1; i <= areas; i++) {
        a = order[i]
        for (k = 0; k < chunks[a]; k++) {
          name = chunks[a] > 1 ? a " (" k + 1 "/" chunks[a] ")" : a
          printf "%s{\"area\":\"%s\",\"files\":[%s]}", (n++ ? ",\n " : ""), esc(name), chunk[a, k]
        }
      }
      print "]"
    }'
