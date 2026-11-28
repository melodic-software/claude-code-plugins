# shellcheck shell=bash
# shellcheck disable=SC2154 # the Actions runner sets GITHUB_REPOSITORY

fix_charset='^[A-Za-z0-9][- A-Za-z0-9._:,/()]{0,99}$'
fix_name_ok() {
  [[ "$1" =~ $fix_charset && "$1" != *babysit-merge-demotion* && "$1" != *post-merge-failure* ]]
}

file_issue() {
  local type="$1" filed
  shift
  filed="$(gh api -X POST "repos/$GITHUB_REPOSITORY/issues" -f type="$type" "$@" \
    --jq '"\(.number) \(.type.name // "")"')" || return 1
  if [[ "${filed#* }" != "$type" ]]; then
    echo "::warning::#${filed%% *} came back without Issue Type $type" >&2
  fi
  printf '%s\n' "${filed%% *}"
}

post_fields() {
  local issue="$1"
  shift
  jq -n '[[48484079, 49622037, 15462270, 48625720, 48625721], $ARGS.positional] | transpose
    | map(select(.[1] != null) | {field_id: .[0], value: .[1]}) | {issue_field_values: .}' --args "$@" |
    gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$issue/issue-field-values" \
      -H 'X-GitHub-Api-Version: 2026-03-10' --input - >/dev/null
}

set_fields() {
  local issue="$1"
  shift
  post_fields "$issue" "$@" && return
  (($# > 2)) || return 1
  post_fields "$issue" "$1" "$2" "${3^}" "${4^}" "${5^}"
}

mark_undelivered() {
  if ! gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$1/comments" -f body="<!-- post-merge-undelivered $2 -->" >/dev/null; then
    echo "::error::could not mark #$1 for the hand-off retry"
    return 1
  fi
}

send_to_intake() {
  intake_missed=''
  if ! gh api -X PUT "repos/$GITHUB_REPOSITORY/issues/$1/lock" >/dev/null; then
    echo "::error::could not lock #$1: not sent to intake triage"
    intake_missed="#$1 could not be locked, so it was not sent to intake triage"
    return 1
  fi
  if ! gh api -X POST "repos/$GITHUB_REPOSITORY/actions/workflows/intake-triage.yml/dispatches" \
    -f ref=main -f "inputs[issue-number]=$1" >/dev/null; then
    echo "::error::could not dispatch intake triage for #$1"
    intake_missed="#$1 was not sent to intake triage"
    return 1
  fi
}

fix_work() {
  local check="$1" sha="$2" signal="$3" on_record="$4" merges="$5" run_link="$6" fix_marker="$7" note="$8"
  local found fix_number fix_state fix_reason fix_body job old
  fix_missed='' fix_missed_issue='' fix_open='' fix_handled=''
  job="${check%% (*}" old="${job// /-}"
  old="<!-- post-merge-fix check=${old,,}${check:${#job}} -->"
  found="$(awk -F'\t' -v m="$fix_marker" -v o="$old" '$4 == m && any == "" { any = $0 }
    $4 == m && $2 == "open" && open == "" { open = $0 }
    $4 == o && oldAny == "" { oldAny = $0 }
    $4 == o && $2 == "open" && oldOpen == "" { oldOpen = $0 }
    END { print (open != "" ? open : any != "" ? any : oldOpen != "" ? oldOpen : oldAny) }' <<<"$own_records")"
  IFS=$'\t' read -r fix_number fix_state fix_reason _ <<<"$found"
  if [[ "$fix_state" == open ]]; then
    echo "#$fix_number already tracks $check"
    fix_open="$fix_number"
  elif [[ -n "$fix_number" && "$fix_reason" =~ ^(not_planned|duplicate)$ ]]; then
    echo "#$fix_number, closed as $fix_reason, mutes $check"
  elif [[ -n "$fix_number" ]]; then
    if gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$fix_number/comments" -f body="$note" >/dev/null &&
      gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/$fix_number" -f state=open -f state_reason=reopened >/dev/null; then
      echo "reopened fix issue #$fix_number for $check"
      own_records+=$'\n'"$fix_number"$'\topen\tnone\t'"$fix_marker"
      fix_handled="$fix_number"
    else
      echo "::error::could not reopen fix issue #$fix_number for $check"
      fix_missed="#$fix_number (\`$check\`) could not be reopened"
    fi
  else
    fix_body="$fix_marker

The check \`$check\` started failing on main in a \`$signal\` run of pr-require-checks.

- Main at the failing run: \`$sha\`
- Run: $run_link
- Merge range: $merges

Fix the check on main. Closing this issue changes nothing on $on_record."
    if fix_number="$(file_issue Bug -f title="Fix $check on main, failing since ${sha:0:12}" -f body="$fix_body")" &&
      [[ "$fix_number" =~ ^[1-9][0-9]*$ ]]; then
      echo "filed fix issue #$fix_number for $check"
      set_fields "$fix_number" needs-triage critical ||
        echo "::warning::could not set the field values of #$fix_number"
      own_records+=$'\n'"$fix_number"$'\topen\tnone\t'"$fix_marker"
      if send_to_intake "$fix_number"; then
        fix_handled="$fix_number"
      else
        fix_missed="$intake_missed" fix_missed_issue="$fix_number"
      fi
    else
      echo "::error::could not file the fix issue for $check"
      fix_missed="no fix issue could be filed for \`$check\`"
    fi
  fi
}

clear_marks() {
  local id
  for id in "$@"; do
    gh api -X DELETE "repos/$GITHUB_REPOSITORY/issues/comments/$id" >/dev/null ||
      echo "::warning::could not clear marker comment $id: the next alert run acts on it again"
  done
}

retry_undelivered() {
  local listed n kind count first failing marks id mark named t row moved failed=0
  local r check sha signal on_record run_link own_records
  local -A sendable=() marked=() sent=()
  local -a checks=()
  # shellcheck disable=SC2016 # jq variables, not shell
  listed="$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues?state=open&creator=github-actions%5Bbot%5D&per_page=100" \
    --jq '.[] | select(.pull_request == null and .state == "open" and .user.login == "github-actions[bot]")
      | ((.body // "") | sub("^\\s+"; "") | split("\n")) as $lines
      | (($lines[0] // "") | sub("\\s+$"; "")) as $first
      | (if ($first | startswith("<!-- post-merge-fix check=")) then "fix"
         elif ($first | startswith("<!-- post-merge-quarantine suite=")) then "quarantine"
         elif ($first | test("^<!-- (babysit-merge-demotion|post-merge-failure) sha=")) then "record"
         else empty end) as $kind
      | [.number, $kind, (.comments // 0), $first,
         ([$lines[] | select(startswith("- Failing run: "))][0] // "none" | ltrimstr("- Failing run: ") | sub("\\s+$"; ""))]
      | @tsv')" || {
    echo "::warning::could not read the open alert issues: the next alert run retries any undelivered hand-off"
    return 0
  }
  while IFS=$'\t' read -r n kind count first failing; do
    [[ -n "$n" ]] || continue
    [[ "$kind" == record ]] || sendable[$n]=1
    ((count > 0)) || continue
    marks="$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$n/comments?per_page=100" \
      --jq '.[] | select(.user.login == "github-actions[bot]")
        | [.id, ((.body // "") | split("\n")[0] // "" | sub("\\s+$"; ""))]
        | select(.[1] | startswith("<!-- post-merge-undelivered ")) | @tsv')" || {
      echo "::warning::could not read the comments of #$n: the next alert run retries any undelivered hand-off"
      continue
    }
    while IFS=$'\t' read -r id mark; do
      [[ "$id" =~ ^[1-9][0-9]*$ ]] || continue
      if [[ "$mark" =~ ^\<!--\ post-merge-undelivered\ issue=([1-9][0-9]*)\ --\>$ ]]; then
        t="${BASH_REMATCH[1]}"
        if [[ "$kind" == record || "$t" == "$n" ]]; then
          marked[$t]+=" $id"
        fi
      elif [[ "$kind" == record && "$mark" =~ ^\<!--\ post-merge-undelivered\ check=(.+)\ --\>$ ]]; then
        check="${BASH_REMATCH[1]}"
        if fix_name_ok "$check"; then
          checks+=("$n"$'\t'"$check"$'\t'"$id"$'\t'"$first"$'\t'"$failing")
        fi
      fi
    done <<<"$marks"
  done <<<"$listed"

  for t in "${!marked[@]}"; do
    named="${marked[$t]}"
    if [[ -z "${sendable[$t]:-}" ]]; then
      echo "#$t is not listed as an open fix or quarantine issue: left its marker for a later run"
      continue
    fi
    if send_to_intake "$t"; then
      echo "re-sent #$t to intake triage"
      sent[$t]=1
    else
      failed=1
      continue
    fi
    # shellcheck disable=SC2086 # named is a list of numeric comment ids
    clear_marks $named
  done

  if ((${#checks[@]} == 0)); then
    return "$failed"
  fi
  own_records="$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues?state=all&creator=github-actions%5Bbot%5D&per_page=100" \
    --jq '.[] | select(.pull_request == null)
      | [.number, .state, (.state_reason // "none"), ((.body // "") | sub("^\\s+"; "") | split("\n")[0] // "" | sub("\\s+$"; ""))]
      | @tsv')" || {
    echo "::warning::could not read the alert's issues: the next alert run retries any undelivered fix issue"
    return "$failed"
  }
  for row in "${checks[@]}"; do
    IFS=$'\t' read -r r check id first failing <<<"$row"
    if [[ ! "$first" =~ ^\<!--\ (babysit-merge-demotion|post-merge-failure)\ sha=([0-9a-f]{40})\ signal=(schedule|dispatch)\ --\>$ ]]; then
      continue
    fi
    on_record="demotion record #$r"
    if [[ "${BASH_REMATCH[1]}" == post-merge-failure ]]; then
      on_record="failure record #$r"
    fi
    sha="${BASH_REMATCH[2]}" signal="${BASH_REMATCH[3]}"
    run_link="see $on_record"
    if [[ "$failing" =~ ^https://[A-Za-z0-9./-]+/actions/runs/[1-9][0-9]*/attempts/[1-9][0-9]*$ ]]; then
      run_link="$failing"
    fi
    fix_work "$check" "$sha" "$signal" "$on_record" "see $on_record" "$run_link" \
      "<!-- post-merge-fix check=$check -->" \
      "This check failed on main again at \`$sha\`. Merge range: see $on_record. Run: $run_link"
    if [[ -n "$fix_handled" ]]; then
      sent[$fix_handled]=1
    fi
    if [[ -n "$fix_open" && -z "${sent[$fix_open]:-}" ]]; then
      if send_to_intake "$fix_open"; then
        echo "re-sent #$fix_open to intake triage"
        sent[$fix_open]=1
      else
        fix_missed="$intake_missed" fix_missed_issue="$fix_open"
      fi
    fi
    if [[ -n "$fix_missed" ]]; then
      failed=1
      [[ -n "$fix_missed_issue" ]] || continue
      moved=''
      mark_undelivered "$fix_missed_issue" "issue=$fix_missed_issue" && moved=1
      mark_undelivered "$r" "issue=$fix_missed_issue" && moved=1
      [[ -n "$moved" ]] || continue
    fi
    clear_marks "$id"
  done
  return "$failed"
}
