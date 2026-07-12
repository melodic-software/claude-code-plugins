#!/usr/bin/env bash
# Aggregate the hygiene step outcomes without treating trailing blank records
# as checks. This remains a script so its parser contract can be regression
# tested independently of GitHub expression evaluation.
set -u

aggregate_results() {
  local input=$1
  local annotate=${2:-true}
  local failed=0
  local check
  local result

  while IFS='=' read -r check result; do
    # YAML block scalars and Bash here-strings can each contribute a trailing
    # newline. Ignore only a fully blank record; a named empty outcome fails.
    if [[ -z "$check" && -z "$result" ]]; then
      continue
    fi

    if [[ "$result" != success ]]; then
      if [[ "$annotate" == true ]]; then
        printf '::error title=%s failed::Hygiene check finished with outcome: %s\n' \
          "$check" "$result"
      fi
      failed=1
    fi
  done <<< "$input"

  return "$failed"
}

self_test() {
  local failed=0

  if ! aggregate_results $'markdown=success\ncomment-hygiene=success\n' false; then
    echo 'all-success records with a trailing newline must pass' >&2
    failed=1
  fi
  if aggregate_results $'markdown=\n' false; then
    echo 'a named empty outcome must fail' >&2
    failed=1
  fi
  if aggregate_results $'markdown=failure\n' false; then
    echo 'a named non-success outcome must fail' >&2
    failed=1
  fi

  if [[ "$failed" -eq 0 ]]; then
    echo 'Hygiene result aggregation contract passed.'
  fi
  return "$failed"
}

case "${1:-}" in
  '') aggregate_results "${CHECK_RESULTS:-}" ;;
  --self-test) self_test ;;
  *) echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac
