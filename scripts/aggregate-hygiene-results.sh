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
# cannot be captured, so its annotation quotes the `::error` annotations the
# job's check run holds (CHECK_RUN_ID in GITHUB_REPOSITORY, read with gh api,
# GH_TOKEN needing checks: read), less the runner's exit-code lines, this
# script's own and any a captured gate printed. The check run does not say
# which step wrote an annotation, so when several such gates failed each
# quotes the same set and names them all. With no check run id, an API
# failure or nothing left to quote, it points at the step log instead. A
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

# tail_of <file>: the last N non-empty lines, color codes stripped and each
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

# gate_annotations: the job's failure annotations a composite gate may have
# written, one `<path>:<line>: <message>` line each (the path alone at line 0,
# the message alone with no file), first HYGIENE_TAIL_LINES of them. Returns 1
# when there is no check run to read or the read fails.
gate_annotations() {
  [[ -n "${CHECK_RUN_ID:-}" && -n "${GITHUB_REPOSITORY:-}" ]] || return 1
  local json dir n path line message
  json=$(gh api --paginate "repos/$GITHUB_REPOSITORY/check-runs/$CHECK_RUN_ID/annotations?per_page=50") || return 1
  dir=$(output_dir)
  n=${HYGIENE_TAIL_LINES:-10}
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || n=10
  jq -r '.[] | select(.annotation_level == "failure")
    | [.path // "", (.start_line // 0 | tostring), (.message // "" | split("\n")[0])] | @tsv' <<<"$json" |
    while IFS=$'\t' read -r path line message; do
      [[ -n "$message" && ! "$message" =~ ^Process\ completed\ with\ exit\ code\ [0-9]+\.$ && "$message" != 'Hygiene check '* ]] || continue
      [[ -n "$dir" && -d "$dir" ]] && grep -rqF -- "$message" "$dir" && continue
      if [[ "$path" == .github || -z "$path" ]]; then
        printf '%s\n' "$message"
      elif [[ "$line" == 0 ]]; then
        printf '%s: %s\n' "$path" "$message"
      else
        printf '%s:%s: %s\n' "$path" "$line" "$message"
      fi
    done | head -n "$n" | cut -c1-500
  [[ "${PIPESTATUS[0]}" -eq 0 ]]
}

# describe_failure <check> <result> [<failed composite gates>]: prints the
# first line (the reason headline), then the captured tail or quoted
# annotations, if any.
describe_failure() {
  local check=$1 result=$2 composites=${3:-$1}
  local dir file
  dir=$(output_dir)
  file="$dir/$check.log"
  local headline="Hygiene check $check finished with outcome: $result"
  if is_step_log_check "$check"; then
    # GATE_ANNOTATIONS: read once by aggregate_results, since this runs in a
    # subshell per gate.
    local quoted=${GATE_ANNOTATIONS:-}
    if [[ -z "$quoted" ]]; then
      printf '%s. This gate runs as a composite action, so its output is not captured here; see the step log.\n' "$headline"
    elif [[ "$composites" == "$check" ]]; then
      printf '%s. This gate runs as a composite action; its own annotations:\n%s\n' "$headline" "$quoted"
    else
      printf '%s. This gate runs as a composite action; annotations of the failed composite gates (%s), which the check run does not tell apart:\n%s\n' \
        "$headline" "$composites" "$quoted"
    fi
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
  local composites=''
  local GATE_ANNOTATIONS
  unset GATE_ANNOTATIONS

  # The failed composite gates, so each one's text can name the others.
  while IFS='=' read -r check result; do
    [[ -n "$check" && "$result" != success ]] && is_step_log_check "$check" && composites+="${composites:+ }$check"
  done <<< "$input"

  while IFS='=' read -r check result; do
    # YAML block scalars and Bash here-strings can each contribute a trailing
    # newline. Ignore only a fully blank record; a named empty outcome fails.
    if [[ -z "$check" && -z "$result" ]]; then
      continue
    fi

    if [[ "$result" != success ]]; then
      if [[ "$annotate" == true ]]; then
        if [[ -z "${GATE_ANNOTATIONS+set}" ]] && is_step_log_check "$check"; then
          GATE_ANNOTATIONS=$(gate_annotations) || GATE_ANNOTATIONS=''
        fi
        description=$(describe_failure "$check" "$result" "$composites")
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
  local failed=0 self=${BASH_SOURCE[0]}
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
  [[ "$out" == '::error title=plugin-options-docs failed::Hygiene check plugin-options-docs finished with outcome: failure. Last lines of its output:%0A'* ]] ||
    fail "a captured failure must open with the outcome headline, got: $out"
  [[ "$out" == *'%0ARun: python scripts/sync-plugin-options-docs.py' ]] ||
    fail "a captured failure must end with the gate's last non-empty line, got: $out"
  [[ "$out" == *'%0ASTALE options docs: 100%25 of harness-ops%0A'* ]] ||
    fail "a captured failure must escape percent signs and strip color codes, got: $out"
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
  [[ "$out" == '::error title=adr-numbers failed::Hygiene check adr-numbers finished with outcome: failure (no captured output).' ]] ||
    fail "a failure with no output file must fall back, got: $out"

  # A failed gate whose captured output is empty says so.
  out=$(HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY='' STEP_LOG_CHECKS='' \
    aggregate_results $'silent=failure\n')
  [[ "$out" == '::error title=silent failed::Hygiene check silent finished with outcome: failure (the gate printed nothing).' ]] ||
    fail "a failure with empty captured output must say so, got: $out"

  # A composite gate points at the step log, even if a stray file exists.
  : >"$summary"
  out=$(HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY=$summary STEP_LOG_CHECKS=' typos  markdown ' \
    aggregate_results $'markdown=failure\n')
  [[ "$out" == '::error title=markdown failed::Hygiene check markdown finished with outcome: failure. This gate runs as a composite action, so its output is not captured here; see the step log.' ]] ||
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

  # A composite gate quotes its own ::error annotations from the job's check
  # run. The fixture holds the annotation shapes a failed lint-repo job
  # returns: the runner's "Process completed" line, a notice, this script's
  # own annotation, a run: gate's annotation (also in its captured log), and
  # the gates' own file annotations, markdownlint's with a line and
  # check-exec-bit's with line 0.
  mkdir -p "$tmp/bin"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >>"$GH_CALLS"' \
    '[[ "${GH_EXIT:-0}" -eq 0 ]] || { echo "HTTP 403" >&2; exit "$GH_EXIT"; }' 'cat "$GH_FIXTURE"' >"$tmp/bin/gh"
  chmod +x "$tmp/bin/gh"
  cat >"$tmp/annotations.json" <<'JSON'
[{"path":".github","start_line":73,"annotation_level":"failure","title":"","message":"Process completed with exit code 1."},
 {"path":".github","start_line":20,"annotation_level":"notice","title":"","message":"Declined: only the release pull request and the merge queue release plugins."},
 {"path":".github","start_line":49,"annotation_level":"failure","title":"markdown failed","message":"Hygiene check finished with outcome: failure. This gate runs as a composite action, so its output is not captured here; see the step log."},
 {"path":"docs/adr/0001-x.md","start_line":1,"annotation_level":"failure","title":"","message":"ADR number 0001 is used twice"}]
[{"path":"plugins/knowledge/skills/docpage-digest/SKILL.md","start_line":172,"annotation_level":"failure","title":"","message":"Lists should be surrounded by blank lines [Context: \"- **Pointer**: <https://code.c...\"]"},
 {"path":"plugins/ai-briefing/skills/generate/scripts/source-bookmarks.sh","start_line":0,"annotation_level":"failure","title":"","message":"plugins/ai-briefing/skills/generate/scripts/source-bookmarks.sh has a shebang but git index mode is 100644"}]
JSON
  printf '::error file=docs/adr/0001-x.md,line=1::ADR number 0001 is used twice\n' >"$tmp/out/adr-numbers.log"
  local -a api=("GH_CALLS=$tmp/gh-calls" "GH_FIXTURE=$tmp/annotations.json" "PATH=$tmp/bin:$PATH")
  : >"$tmp/gh-calls"
  : >"$summary"
  out=$(env "${api[@]}" "HYGIENE_OUTPUT_DIR=$tmp/out" "GITHUB_STEP_SUMMARY=$summary" STEP_LOG_CHECKS='markdown typos' \
    GITHUB_REPOSITORY=o/r CHECK_RUN_ID=117510416627 GH_TOKEN=t CHECK_RESULTS=$'markdown=failure\ntypos=success\n' bash "$self")
  [[ "$out" == '::error title=markdown failed::Hygiene check markdown finished with outcome: failure. This gate runs as a composite action; its own annotations:%0A'* ]] ||
    fail "a composite gate must quote its annotations under its name, got: $out"
  [[ "$out" == *'%0Aplugins/knowledge/skills/docpage-digest/SKILL.md:172: Lists should be surrounded by blank lines [Context: "- **Pointer**: <https://code.c..."]%0A'* ]] ||
    fail "a composite gate must quote an annotation with its path and line, got: $out"
  [[ "$out" == *'%0Aplugins/ai-briefing/skills/generate/scripts/source-bookmarks.sh: plugins/ai-briefing/skills/generate/scripts/source-bookmarks.sh has a shebang but git index mode is 100644' ]] ||
    fail "an annotation at line 0 must carry its path alone, got: $out"
  [[ "$out" != *'Process completed'* && "$out" != *Declined* && "$out" != *'ADR number'* && "$out" != *'see the step log'* ]] ||
    fail "a composite gate must quote neither runner, notice, run-gate nor aggregate annotations, got: $out"
  [[ "$(cat "$tmp/gh-calls")" == *'repos/o/r/check-runs/117510416627/annotations'* ]] ||
    fail "the annotations must come from this job's check run, got: $(cat "$tmp/gh-calls")"
  grep -qxF 'plugins/knowledge/skills/docpage-digest/SKILL.md:172: Lists should be surrounded by blank lines [Context: "- **Pointer**: <https://code.c..."]' "$summary" ||
    fail "the job summary must list a composite gate's annotations, got: $(cat "$summary")"

  # Two failed composite gates share the one set: the API does not say which
  # step wrote an annotation, so the text names both.
  out=$(env "${api[@]}" "HYGIENE_OUTPUT_DIR=$tmp/out" GITHUB_STEP_SUMMARY='' STEP_LOG_CHECKS='markdown exec-bit' \
    GITHUB_REPOSITORY=o/r CHECK_RUN_ID=1 GH_TOKEN=t CHECK_RESULTS=$'exec-bit=failure\nmarkdown=failure\n' bash "$self")
  [[ "$out" == *'::error title=exec-bit failed::Hygiene check exec-bit finished with outcome: failure. This gate runs as a composite action; annotations of the failed composite gates (exec-bit markdown), which the check run does not tell apart:%0A'* ]] ||
    fail "two failed composite gates must name both, got: $out"
  [[ "$(grep -c 'source-bookmarks.sh has a shebang' <<<"$out")" -eq 2 ]] ||
    fail "each failed composite gate must quote the shared annotations, got: $out"

  # Fail-safe: an API failure, no matching annotation, or no check run id
  # gives today's step-log pointer.
  local pointer='Hygiene check markdown finished with outcome: failure. This gate runs as a composite action, so its output is not captured here; see the step log.'
  out=$(env "${api[@]}" GH_EXIT=1 STEP_LOG_CHECKS=markdown GITHUB_REPOSITORY=o/r CHECK_RUN_ID=1 GH_TOKEN=t \
    CHECK_RESULTS=$'markdown=failure\n' bash "$self" 2>/dev/null)
  [[ "$out" == "::error title=markdown failed::$pointer" ]] || fail "an API failure must fall back to the step log, got: $out"
  printf '[{"path":".github","start_line":3,"annotation_level":"failure","title":"","message":"Process completed with exit code 1."}]\n' >"$tmp/runner-only.json"
  out=$(env "${api[@]}" "GH_FIXTURE=$tmp/runner-only.json" STEP_LOG_CHECKS=markdown GITHUB_REPOSITORY=o/r CHECK_RUN_ID=1 GH_TOKEN=t \
    CHECK_RESULTS=$'markdown=failure\n' bash "$self")
  [[ "$out" == "::error title=markdown failed::$pointer" ]] || fail "no gate annotation must fall back to the step log, got: $out"
  : >"$tmp/gh-calls"
  out=$(env "${api[@]}" STEP_LOG_CHECKS=markdown GITHUB_REPOSITORY=o/r CHECK_RUN_ID='' GH_TOKEN=t \
    CHECK_RESULTS=$'markdown=failure\n' bash "$self")
  [[ "$out" == "::error title=markdown failed::$pointer" && ! -s "$tmp/gh-calls" ]] ||
    fail "no check run id must fall back without calling the API, got: $out"

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
