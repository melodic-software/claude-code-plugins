# shellcheck shell=bash
# shellcheck disable=SC2154 # check-open-questions.sh sets fence_awk, ledger, seen_ids and trimmed

check_sweep() {
  local text lno sweep_ran sweep_matches sweep_line facts_matches facts="" body
  local s_lo=0 s_hi=0 sweep_keys=$'\n' sweep_rows=0 sweep_none=0 row seps key
  local sweep_marks=$'\n' sweep_no high_water
  local category class src disposition hedged user_owned owned_kind qnum qid fid basis found gaps src_rest src_max
  local quote_re='"[^"]+"' loc_re='(https?://[^[:space:]]+|[^[:space:]:]+:[0-9]+)'

  while IFS=$'\t' read -r lno text; do
    [[ -n "$lno" ]] && proc_problem "line $lno: Step-exit checkbox is unchecked: $text (tick it when the step is done; a skipped step is ticked with 'SKIPPED: <reason>')"
  done <<<"$(awk "$fence_awk"'
    fence_line($0) { next }
    fenced { next }
    {
      l = tolower($0)
      if (l ~ /^[[:space:]]*[-*+][[:space:]]+\[ \][[:space:]]+step[[:space:]]+[0-9.]+[[:space:]]+exit/) {
        match(l, /step[[:space:]]+[0-9.]+[[:space:]]+exit/)
        print NR "\t" substr($0, RSTART, RLENGTH)
      }
    }
  ' "$ledger")"

  sweep_ran="$(awk "$fence_awk"'
    fence_line($0) { next }
    fenced { next }
    {
      l = tolower($0)
      if (l ~ /^[[:space:]]*[-*+][[:space:]]+\[x\][[:space:]]+step[[:space:]]+2[[:space:]]+exit/ && l !~ /skipped:/) { print NR; exit }
    }
  ' "$ledger")"

  sweep_matches="$(heading_matches '^#+[[:space:]]+assumption sweep[[:space:]]*$' "$ledger")"
  if [[ -z "$sweep_matches" ]]; then
    [[ -z "$sweep_ran" ]] ||
      proc_problem "line $sweep_ran: Step 2 exit is ticked but the ledger has no '## Assumption sweep' section; record each sweep item there with its disposition, or '- none'"
  elif [[ "$(match_count "$sweep_matches")" -gt 1 ]]; then
    proc_problem "$(match_count "$sweep_matches") headings match 'assumption sweep' (lines $(match_lines "$sweep_matches")); keep one section"
    return
  else
    sweep_line="${sweep_matches%%$'\t'*}"
    facts_matches="$(heading_matches '^#+[[:space:]]+self-answered facts[[:space:]]*$' "$ledger")"
    if [[ -n "$facts_matches" && "$(match_count "$facts_matches")" -eq 1 ]]; then
      while IFS= read -r text; do
        [[ "${text%%$'\t'*}" == "." ]] || continue
        text="${text#*$'\t'}"
        [[ "$text" =~ ^[[:space:]]*-[[:space:]]+[Ff]([1-9][0-9]*)[[:space:]]*\| ]] || continue
        facts="${facts}F${BASH_REMATCH[1]}"$'\t'"${text##*|}"$'\n'
      done <<<"$(extract_section "${facts_matches%%$'\t'*}" "$ledger")"
    fi

    body="$(extract_section "$sweep_line" "$ledger")"
    s_lo=$((sweep_line + 1))
    lno="$sweep_line"
    while IFS= read -r text; do
      lno=$((lno + 1))
      [[ "${text%%$'\t'*}" == "." ]] || continue
      text="${text#*$'\t'}"
      if [[ "$text" =~ ^[[:space:]]*-[[:space:]]+[Nn][Oo][Nn][Ee][[:space:]]*$ ]]; then
        sweep_none=1
        continue
      fi
      if [[ "$text" =~ ^[[:space:]]*-[[:space:]]+[Ss]weep[[:space:]]+([1-9][0-9]*)[[:space:]]*\|[[:space:]]*(register|Register)[[:space:]]+through[[:space:]]+[Qq]([1-9][0-9]*)[[:space:]]*$ ]]; then
        sweep_no="${BASH_REMATCH[1]}"
        qnum="${BASH_REMATCH[3]}"
        case "$seen_ids" in
        *" Q$qnum "*) ;;
        *) proc_problem "line $lno: sweep $sweep_no's high-water line names Q$qnum, which has no register row" ;;
        esac
        case "$sweep_marks" in
        *$'\n'"$sweep_no "*) proc_problem "line $lno: duplicate high-water line for sweep $sweep_no" ;;
        *) sweep_marks="$sweep_marks$sweep_no $qnum"$'\n' ;;
        esac
        continue
      fi
      [[ "$text" =~ ^[[:space:]]*-[[:space:]]+[Ss][0-9]+([^0-9]|$) ]] || continue
      sweep_rows=$((sweep_rows + 1))
      row="${text#*-}"
      seps="${row//[!|]/}"
      if ! [[ "$row" =~ ^[[:space:]]*[Ss]([1-9][0-9]*)[[:space:]]*\|[[:space:]]*[Ss]weep[[:space:]]+([1-9][0-9]*)[[:space:]]*\| ]] || [[ "${#seps}" -lt 5 ]]; then
        proc_problem "line $lno: malformed sweep row (needs 'S<N> | sweep <M> | category | class | source | disposition'): $text"
        continue
      fi
      sweep_no="${BASH_REMATCH[2]}"
      key="sweep $sweep_no S${BASH_REMATCH[1]}"
      case "$sweep_keys" in
      *$'\n'"$key"$'\n'*)
        proc_problem "line $lno: duplicate sweep row: $key"
        continue
        ;;
      *) ;;
      esac
      sweep_keys="$sweep_keys$key"$'\n'
      row="${row#*|}"
      row="${row#*|}"
      trim_into "${row%%|*}"
      category="$trimmed"
      row="${row#*|}"
      trim_into "${row%%|*}"
      class="$trimmed"
      row="${row#*|}"
      src="${row%|*}"
      trim_into "${row##*|}"
      disposition="$trimmed"

      shopt -s nocasematch
      case "$category" in
      undecided | hidden-default | contradiction | inherited | hedged | coined-term | unstated-value) ;;
      *) proc_problem "line $lno: $key has unknown category '$category'" ;;
      esac
      case "$class" in
      decision | fact | tenant | person) ;;
      *) proc_problem "line $lno: $key has unknown class '$class'" ;;
      esac
      hedged=0
      [[ "$category" != hedged ]] || hedged=1
      user_owned=0
      [[ "$class" != decision && "$class" != person && "$category" != unstated-value ]] || user_owned=1
      owned_kind="$class"
      [[ "$category" != unstated-value ]] || owned_kind="$category"
      shopt -u nocasematch

      if [[ "$disposition" =~ ^[Qq]([1-9][0-9]*)$ ]]; then
        qnum="${BASH_REMATCH[1]}"
        qid="Q$qnum"
        case "$seen_ids" in
        *" $qid "*) ;;
        *) proc_problem "line $lno: $key names $qid, which has no register row" ;;
        esac
        if [[ "$hedged" -eq 0 ]]; then
          if [[ "$src" =~ (^|[^A-Za-z0-9])[Qq]$qnum([^0-9]|$) ]]; then
            proc_problem "line $lno: $key names $qid, the row it was found in; a sweep item becomes a new register row at the next Q<N>, asked with a recommendation"
          else
            src_rest="$src"
            src_max=0
            while [[ "$src_rest" =~ (^|[^A-Za-z0-9])[Qq]([1-9][0-9]*)([^0-9].*)?$ ]]; do
              [[ "${BASH_REMATCH[2]}" -le "$src_max" ]] || src_max="${BASH_REMATCH[2]}"
              src_rest="x${BASH_REMATCH[3]}"
            done
            high_water="${sweep_marks#*$'\n'"$sweep_no "}"
            if [[ "$high_water" == "$sweep_marks" ]]; then
              proc_problem "line $lno: $key has a Q<N> disposition but sweep $sweep_no has no '- sweep $sweep_no | register through Q<N>' line above it; write that line, with the register's last row, before the sweep runs"
            else
              high_water="${high_water%%$'\n'*}"
              if [[ "$src_max" -gt "$high_water" ]]; then
                proc_problem "line $lno: $key's source names Q$src_max, above Q$high_water, sweep $sweep_no's high-water line; that line names the register's last row when the sweep ran"
              elif [[ "$qnum" -le "$high_water" ]]; then
                proc_problem "line $lno: $key names $qid, which is not above Q$high_water, the last row before sweep $sweep_no; a sweep item becomes a new register row at the next Q<N>, asked with a recommendation"
              fi
            fi
          fi
        fi
      elif [[ "$disposition" =~ ^[Ff]([1-9][0-9]*)$ ]]; then
        fid="F${BASH_REMATCH[1]}"
        if [[ "$user_owned" -eq 1 ]]; then
          proc_problem "line $lno: $key is a $owned_kind item settled by $fid; a $owned_kind item becomes an open register row asked with a recommendation, never a fact"
          continue
        fi
        found=0
        basis=""
        while IFS=$'\t' read -r text basis; do
          if [[ "$text" == "$fid" ]]; then
            found=1
            break
          fi
        done <<<"$facts"
        if [[ "$found" -eq 0 ]]; then
          proc_problem "line $lno: $key names $fid, which has no line in '## Self-answered facts'"
        elif ! [[ "$basis" =~ $quote_re && "$basis" =~ $loc_re ]]; then
          proc_problem "line $lno: $key is settled by $fid, whose basis does not quote its source (\"...\") with a file:line or a URL: '$basis'"
        fi
      elif [[ "$disposition" =~ ^[Dd]eferred:[[:space:]]*[^[:space:]] ]]; then
        [[ "$user_owned" -eq 0 || "$hedged" -eq 1 ]] ||
          proc_problem "line $lno: $key is a $owned_kind item deferred outside the register; it becomes a register row (deferred there with arbiter /planning:design when it sits below the interview's level or a quoted owner ruling routed it, blocked when it cannot be asked)"
      else
        proc_problem "line $lno: $key has no disposition (Q<N>, F<N> or 'deferred: <where>'): '$disposition'"
      fi
    done <<<"$body"
    s_hi="$lno"

    if [[ "$sweep_rows" -eq 0 && "$sweep_none" -eq 0 ]]; then
      proc_problem "the '## Assumption sweep' section at line $sweep_line records no item; write '- none' when the sweep returned nothing"
    fi
    gaps="$(printf '%s' "$sweep_keys" | awk '
      NF < 3 { next }
      {
        m = $2 + 0; n = substr($3, 2) + 0; seen[m " " n] = 1
        if (!(m in lo) || n < lo[m]) lo[m] = n
        if (n > hi[m]) hi[m] = n
        if (m > top) top = m
      }
      END {
        prev = 0
        for (m = 1; m <= top; m++) {
          if (!(m in lo)) continue
          if (lo[m] != 1 && lo[m] != prev + 1) print "sweep " m " starts at S" lo[m] ", not S1" (prev ? " or S" prev + 1 : "")
          for (n = lo[m]; n <= hi[m]; n++) if (!((m " " n) in seen)) print "sweep " m " has no row for S" n
          prev = hi[m]
        }
      }
    ')"
    while IFS= read -r text; do
      [[ -n "$text" ]] && proc_problem "$text (S ids run contiguously within a sweep, from S1 or on from the last sweep's highest S id)"
    done <<<"$gaps"
  fi

  while IFS= read -r lno; do
    [[ -n "$lno" ]] && proc_problem "line $lno: sweep row outside the '## Assumption sweep' section; move it into the section, above its next heading"
  done <<<"$(awk -v lo="$s_lo" -v hi="$s_hi" "$fence_awk"'
    fence_line($0) { next }
    fenced { next }
    NR >= lo && NR <= hi { next }
    /^[[:space:]]*-[[:space:]]+[Ss][0-9]+[[:space:]]*[|]/ { print NR }
  ' "$ledger")"
}
