#!/usr/bin/env bash
# Aggregate the hygiene step outcomes without treating trailing blank records
# as checks. This remains a script so its parser contract can be regression
# tested independently of GitHub expression evaluation.
#
# Each failed gate gets one `::error` annotation that says why it failed: the
# last HYGIENE_TAIL_LINES (default 10) non-empty lines of the output its step
# captured through scripts/run-hygiene-gate.sh, read from
# <HYGIENE_OUTPUT_DIR, else $RUNNER_TEMP/hygiene>/<check>.log. A gate named in
# STEP_LOG_CHECKS (whitespace-separated) runs as a `uses:` action whose output
# cannot be captured, so its annotation points at the step log instead. A
# failed gate with no output file falls back to the outcome plus "no captured
# output". Every failed gate is also listed, with its tail, in
# $GITHUB_STEP_SUMMARY when that is set. Pass/fail is decided by the outcomes
# alone.

# shellcheck disable=SC2016 # Backticks in this file are literal Markdown, not expansions.
set -u

output_dir() {
  printf '%s\n' "${HYGIENE_OUTPUT_DIR:-${RUNNER_TEMP:+$RUNNER_TEMP/hygiene}}"
}

# Workflow-command escaping: the message keeps its newlines and percent signs,
# and a property value (the title) cannot end the property list early.
escape_data() {
  local s=$1
  s=${s//'%'/'%25'}
  s=${s//$'\r'/'%0D'}
  s=${s//$'\n'/'%0A'}
  printf '%s' "$s"
}

escape_property() {
  local s
  s=$(escape_data "$1")
  s=${s//':'/'%3A'}
  s=${s//','/'%2C'}
  printf '%s' "$s"
}

# tail_of <file>: the last N non-empty lines, colour codes stripped and each
# line cut at 500 characters so one minified line cannot swamp the annotation.
tail_of() {
  local n=${HYGIENE_TAIL_LINES:-10}
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || n=10
  sed -e $'s/\x1b\\[[0-9;]*[A-Za-z]//g' -e 's/\r$//' "$1" |
    grep -v '^[[:space:]]*$' | tail -n "$n" | cut -c1-500
}

is_step_log_check() {
  local check=$1 name
  for name in ${STEP_LOG_CHECKS:-}; do
    [[ "$name" == "$check" ]] && return 0
  done
  return 1
}

# describe_failure <check> <result>: prints the first line (the reason
# headline), then the captured tail, if any.
describe_failure() {
  local check=$1 result=$2
  local dir file
  dir=$(output_dir)
  file="$dir/$check.log"
  local headline="Hygiene check finished with outcome: $result"
  if is_step_log_check "$check"; then
    printf '%s. This gate runs as a composite action, so its output is not captured here; see the step log.\n' "$headline"
  elif [[ -z "$dir" || ! -f "$file" ]]; then
    printf '%s (no captured output).\n' "$headline"
  else
    local tail
    tail=$(tail_of "$file")
    if [[ -z "$tail" ]]; then
      printf '%s (the gate printed nothing).\n' "$headline"
    else
      printf '%s. Last lines of its output:\n%s\n' "$headline" "$tail"
    fi
  fi
}

write_summary() {
  local summary=$1 check=$2 result=$3 description=$4
  {
    printf '### `%s` failed (%s)\n\n' "$check" "$result"
    printf '%s\n\n' "${description%%$'\n'*}"
    if [[ "$description" == *$'\n'* ]]; then
      # The fence outgrows any backtick run in the tail, so no captured line
      # can close it early.
      local body=${description#*$'\n'} fence='````'
      while [[ "$body" == *"$fence"* ]]; do fence+='`'; done
      printf '%stext\n%s\n%s\n\n' "$fence" "$body" "$fence"
    fi
  } >>"$summary"
}

aggregate_results() {
  local input=$1
  local annotate=${2:-true}
  local failed=0
  local check
  local result
  local description
  local summary=${GITHUB_STEP_SUMMARY:-}
  local summary_started=false

  while IFS='=' read -r check result; do
    # YAML block scalars and Bash here-strings can each contribute a trailing
    # newline. Ignore only a fully blank record; a named empty outcome fails.
    if [[ -z "$check" && -z "$result" ]]; then
      continue
    fi

    if [[ "$result" != success ]]; then
      if [[ "$annotate" == true ]]; then
        description=$(describe_failure "$check" "$result")
        printf '::error title=%s::%s\n' \
          "$(escape_property "$check failed")" "$(escape_data "$description")"
        if [[ -n "$summary" ]]; then
          if [[ "$summary_started" == false ]]; then
            printf '## Failed hygiene gates\n\n' >>"$summary"
            summary_started=true
          fi
          write_summary "$summary" "$check" "$result" "$description"
        fi
      fi
      failed=1
    fi
  done <<< "$input"

  return "$failed"
}

self_test() {
  local failed=0
  local tmp out summary
  tmp=$(mktemp -d) || return 1
  # shellcheck disable=SC2064 # expand $tmp now: it is local to this function.
  trap "rm -rf '$tmp'" RETURN

  fail() {
    echo "$1" >&2
    failed=1
  }

  if ! aggregate_results $'markdown=success\ncomment-hygiene=success\n' false; then
    fail 'all-success records with a trailing newline must pass'
  fi
  if aggregate_results $'markdown=\n' false; then
    fail 'a named empty outcome must fail'
  fi
  if aggregate_results $'markdown=failure\n' false; then
    fail 'a named non-success outcome must fail'
  fi

  mkdir -p "$tmp/out"
  summary=$tmp/summary.md
  : >"$summary"
  {
    printf 'preamble line that falls outside the tail\n'
    for i in 1 2 3 4 5 6 7 8 9; do printf 'detail %s\n' "$i"; done
    printf '\n   \n'
    printf '\033[31mSTALE options docs: 100%% of harness-ops\033[0m\n'
    printf 'Run: python scripts/sync-plugin-options-docs.py\n\n'
  } >"$tmp/out/plugin-options-docs.log"
  : >"$tmp/out/silent.log"

  # All success: no annotation, no summary.
  out=$(HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY=$summary STEP_LOG_CHECKS='' \
    aggregate_results $'markdown=success\nplugin-options-docs=success\n')
  [[ -z "$out" && ! -s "$summary" ]] || fail 'all-success records must emit no annotation and no summary'

  # A failed gate with captured output: its last non-empty lines, escaped.
  out=$(HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY=$summary STEP_LOG_CHECKS='markdown' \
    aggregate_results $'plugin-options-docs=failure\n')
  [[ "$out" == '::error title=plugin-options-docs failed::Hygiene check finished with outcome: failure. Last lines of its output:%0A'* ]] ||
    fail "a captured failure must open with the outcome headline, got: $out"
  [[ "$out" == *'%0ARun: python scripts/sync-plugin-options-docs.py' ]] ||
    fail "a captured failure must end with the gate's last non-empty line, got: $out"
  [[ "$out" == *'%0ASTALE options docs: 100%25 of harness-ops%0A'* ]] ||
    fail "a captured failure must escape percent signs and strip colour codes, got: $out"
  [[ "$out" != *preamble* && "$out" == *'%0Adetail 2%0A'* && "$out" != *'detail 1%0A'* ]] ||
    fail "a captured failure must carry exactly the last 10 non-empty lines, got: $out"
  [[ "$(printf '%s' "$out" | wc -l)" -eq 0 ]] ||
    fail 'a captured failure must be a single workflow-command line'
  if ! grep -qxF '### `plugin-options-docs` failed (failure)' "$summary" ||
    ! grep -qxF 'Run: python scripts/sync-plugin-options-docs.py' "$summary"; then
    fail 'the job summary must list a failed gate with its output tail'
  fi

  # A failed gate with no output file: today's text plus the fallback.
  out=$(HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY='' STEP_LOG_CHECKS='' \
    aggregate_results $'adr-numbers=failure\n')
  [[ "$out" == '::error title=adr-numbers failed::Hygiene check finished with outcome: failure (no captured output).' ]] ||
    fail "a failure with no output file must fall back, got: $out"

  # A failed gate whose captured output is empty says so.
  out=$(HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY='' STEP_LOG_CHECKS='' \
    aggregate_results $'silent=failure\n')
  [[ "$out" == '::error title=silent failed::Hygiene check finished with outcome: failure (the gate printed nothing).' ]] ||
    fail "a failure with empty captured output must say so, got: $out"

  # A composite gate points at the step log, even if a stray file exists.
  : >"$summary"
  out=$(HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY=$summary STEP_LOG_CHECKS=' typos  markdown ' \
    aggregate_results $'markdown=failure\n')
  [[ "$out" == '::error title=markdown failed::Hygiene check finished with outcome: failure. This gate runs as a composite action, so its output is not captured here; see the step log.' ]] ||
    fail "a composite gate must point at the step log, got: $out"
  grep -qxF '### `markdown` failed (failure)' "$summary" ||
    fail 'the job summary must list a failed composite gate'

  # A captured line of backticks cannot close the summary's fence.
  printf 'before\n````\n[link](https://example.invalid)\n' >"$tmp/out/fenced.log"
  : >"$summary"
  HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY=$summary STEP_LOG_CHECKS='' \
    aggregate_results $'fenced=failure\n' >/dev/null
  if ! grep -qxF '`````text' "$summary" || [[ "$(grep -cxF '`````' "$summary")" -ne 1 ]]; then
    fail "the summary fence must outgrow any backtick run in the tail, got: $(cat "$summary")"
  fi

  # With no output directory configured there is no capture to read.
  out=$(HYGIENE_OUTPUT_DIR='' RUNNER_TEMP='' GITHUB_STEP_SUMMARY='' STEP_LOG_CHECKS='' \
    aggregate_results $'adr-numbers=failure\n')
  [[ "$out" == *'(no captured output).' ]] ||
    fail "no configured output directory must fall back, got: $out"

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
