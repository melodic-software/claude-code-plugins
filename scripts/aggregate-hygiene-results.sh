#!/usr/bin/env bash
# shellcheck disable=SC2016 # Backticks in this file are literal Markdown, not expansions.
set -u

output_dir() {
  printf '%s\n' "${HYGIENE_OUTPUT_DIR:-${RUNNER_TEMP:+$RUNNER_TEMP/hygiene}}"
}

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

tail_lines() {
  local n=${HYGIENE_TAIL_LINES:-10}
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || n=10
  printf '%s\n' "$n"
}

tail_of() {
  sed -e $'s/\x1b\\[[0-9;]*[A-Za-z]//g' -e 's/\r$//' "$1" |
    grep -v '^[[:space:]]*$' | tail -n "$(tail_lines)" | cut -c1-500
}

is_step_log_check() {
  local check=$1 name
  for name in ${STEP_LOG_CHECKS:-}; do
    [[ "$name" == "$check" ]] && return 0
  done
  return 1
}

gate_annotations() {
  [[ -n "${CHECK_RUN_ID:-}" && -n "${GITHUB_REPOSITORY:-}" ]] || return 1
  local json dir path line message
  # shellcheck source=/dev/null
  [[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token
  json=$(gh api --paginate "repos/$GITHUB_REPOSITORY/check-runs/$CHECK_RUN_ID/annotations?per_page=50") || return 1
  dir=$(output_dir)
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
    done | head -n "$(tail_lines)" | cut -c1-500
  [[ "${PIPESTATUS[0]}" -eq 0 ]]
}

describe_failure() {
  local check=$1 result=$2 composites=${3:-$1}
  local dir file
  dir=$(output_dir)
  file="$dir/$check.log"
  local headline="Hygiene check $check finished with outcome: $result"
  if is_step_log_check "$check"; then
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
      local body=${description#*$'\n'} fence='````'
      while [[ "$body" == *"$fence"* ]]; do fence+='`'; done
      printf '%stext\n%s\n%s\n\n' "$fence" "$body" "$fence"
    fi
  } >>"$summary"
}

aggregate_results() {
  local input=$1 annotate=${2:-true} failed=0 check result description
  local summary=${GITHUB_STEP_SUMMARY:-} summary_started=false composites=''
  local GATE_ANNOTATIONS
  unset GATE_ANNOTATIONS

  while IFS='=' read -r check result; do
    [[ -n "$check" && "$result" != success ]] && is_step_log_check "$check" && composites+="${composites:+ }$check"
  done <<< "$input"

  while IFS='=' read -r check result; do
    [[ -n "$check" || -n "$result" ]] || continue

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

  out=$(HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY=$summary STEP_LOG_CHECKS='' \
    aggregate_results $'markdown=success\nplugin-options-docs=success\n')
  [[ -z "$out" && ! -s "$summary" ]] || fail 'all-success records must emit no annotation and no summary'

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

  out=$(HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY='' STEP_LOG_CHECKS='' \
    aggregate_results $'adr-numbers=failure\n')
  [[ "$out" == '::error title=adr-numbers failed::Hygiene check adr-numbers finished with outcome: failure (no captured output).' ]] ||
    fail "a failure with no output file must fall back, got: $out"

  out=$(HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY='' STEP_LOG_CHECKS='' \
    aggregate_results $'silent=failure\n')
  [[ "$out" == '::error title=silent failed::Hygiene check silent finished with outcome: failure (the gate printed nothing).' ]] ||
    fail "a failure with empty captured output must say so, got: $out"

  : >"$summary"
  out=$(HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY=$summary STEP_LOG_CHECKS=' typos  markdown ' \
    aggregate_results $'markdown=failure\n')
  [[ "$out" == '::error title=markdown failed::Hygiene check markdown finished with outcome: failure. This gate runs as a composite action, so its output is not captured here; see the step log.' ]] ||
    fail "a composite gate must point at the step log, got: $out"
  grep -qxF '### `markdown` failed (failure)' "$summary" ||
    fail 'the job summary must list a failed composite gate'

  printf 'before\n````\n[link](https://example.invalid)\n' >"$tmp/out/fenced.log"
  : >"$summary"
  HYGIENE_OUTPUT_DIR=$tmp/out GITHUB_STEP_SUMMARY=$summary STEP_LOG_CHECKS='' \
    aggregate_results $'fenced=failure\n' >/dev/null
  if ! grep -qxF '`````text' "$summary" || [[ "$(grep -cxF '`````' "$summary")" -ne 1 ]]; then
    fail "the summary fence must outgrow any backtick run in the tail, got: $(cat "$summary")"
  fi

  mkdir -p "$tmp/bin"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >>"$GH_CALLS"' \
    '[[ -z "${GH_DEBUG:-}" ]] || echo "* Request to https://api.github.com/x" >&2' \
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
  local -a api=("GH_CALLS=$tmp/gh-calls" "GH_FIXTURE=$tmp/annotations.json" "PATH=$tmp/bin:$PATH" RUNNER_TEMP=)
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

  mkdir -p "$tmp/runner"
  env "${api[@]}" "RUNNER_TEMP=$tmp/runner" "HYGIENE_OUTPUT_DIR=$tmp/out" GITHUB_STEP_SUMMARY='' STEP_LOG_CHECKS=markdown \
    GITHUB_REPOSITORY=o/r CHECK_RUN_ID=1 GH_TOKEN=t CHECK_RESULTS=$'markdown=failure\n' bash "$self" >/dev/null
  [[ "$(cat "$tmp/runner/api-budget/github-token" 2>/dev/null)" == "request {x}" ]] ||
    fail "the annotation read must count one request, got: $(cat "$tmp/runner/api-budget/github-token" 2>/dev/null)"

  out=$(env "${api[@]}" "HYGIENE_OUTPUT_DIR=$tmp/out" GITHUB_STEP_SUMMARY='' STEP_LOG_CHECKS='markdown exec-bit' \
    GITHUB_REPOSITORY=o/r CHECK_RUN_ID=1 GH_TOKEN=t CHECK_RESULTS=$'exec-bit=failure\nmarkdown=failure\n' bash "$self")
  [[ "$out" == *'::error title=exec-bit failed::Hygiene check exec-bit finished with outcome: failure. This gate runs as a composite action; annotations of the failed composite gates (exec-bit markdown), which the check run does not tell apart:%0A'* ]] ||
    fail "two failed composite gates must name both, got: $out"
  [[ "$(grep -c 'source-bookmarks.sh has a shebang' <<<"$out")" -eq 2 ]] ||
    fail "each failed composite gate must quote the shared annotations, got: $out"

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
