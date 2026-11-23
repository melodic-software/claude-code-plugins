#!/usr/bin/env bash
# Validates each chosen plugin's eval suite with validate-cases.py and, on a
# deterministic run, stages its copy without judged cases. Reads LIST, ROOT and
# DETERMINISTIC; writes go and suites to GITHUB_OUTPUT.
# shellcheck disable=SC2154,SC2292 # the step's body verbatim; the step env sets LIST, ROOT, DETERMINISTIC and CASES, and the runner GITHUB_OUTPUT
set -e
staged=""
while IFS= read -r plugin; do
  [ -n "$plugin" ] || continue
  dir="$ROOT/$plugin"
  eval_dir=$(jq -r '.experimental.evals // "evals"' "$dir/.claude-plugin/plugin.json" 2>/dev/null || echo evals)
  if [ ! -d "$dir/$eval_dir" ]; then
    echo "::notice::$plugin has no eval suite; skipped."
    continue
  fi
  echo "== validate $plugin/$eval_dir"
  if ! python3 .base/plugins/evals/skills/validate/scripts/validate-cases.py "$dir/$eval_dir"; then
    echo "::error::$plugin/$eval_dir does not pass validate-cases.py, so no eval runs"
    exit 1
  fi
  if [ "$DETERMINISTIC" = true ]; then
    args=()
    if [[ "${CASES:-}" =~ [^[:space:]] ]]; then
      args=(--cases "$CASES")
    fi
    split=$(node .base/.github/scripts/plugin-eval/deterministic-suite.mjs "$dir" evals-deterministic "${args[@]}")
    echo "$split"
    if [ "$(jq '.kept | length' <<<"$split")" -eq 0 ]; then
      echo "::notice::$plugin has no case with deterministic graders only; skipped."
      continue
    fi
    eval_dir=evals-deterministic
  elif [[ "${CASES:-}" =~ [^[:space:]] ]]; then
    split=$(node .base/.github/scripts/plugin-eval/deterministic-suite.mjs "$dir" evals-selected --cases "$CASES" --keep-judged)
    echo "$split"
    eval_dir=evals-selected
  fi
  staged+="$dir"$'\t'"$eval_dir"$'\n'
done <<<"$LIST"
if [ -z "$staged" ]; then
  echo "go=false" >>"$GITHUB_OUTPUT"
  exit 0
fi
{
  echo "go=true"
  echo "suites<<EOF"
  printf '%s' "$staged"
  echo "EOF"
} >>"$GITHUB_OUTPUT"
