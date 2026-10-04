#!/usr/bin/env bash
# Stop hook: the task-end test judge's relay. It never blocks on its own
# failure: an EXIT trap turns every path into exit 0.
#
# 1. stop_hook_active (the turn this hook or another Stop hook forced): judge
#    nothing, never block, say nothing. Verdicts wait in the ledger for the
#    next task end.
# 2. Re-derive the in-doubt keys of every file the session (and, for a /clear
#    or fork successor, its adopted predecessors) wrote.
# 3. Keys with a verdict are ready; keys a live background job or lock holds
#    are waited on; the rest are judged now, one run per file in parallel, at
#    most 10 keys per Stop. Keys past that cap, and keys this Stop's own run
#    had not finished at the deadline, are handed to a detached
#    test-judge-bg.sh job just before returning; that job waits for a dying
#    run's lock, and a job that dies leaves its keys to the next task end.
#    Every wait (slot, run, job) ends at TEST_JUDGE_TIMEOUT (default 180 s,
#    below the hooks.json timeout of 240 s), so the hook returns within about
#    2 s of it.
# 4. Validate the verdicts, write the findings file, record them in relayed/.
# 5. Attended (CLAUDE_CODE_SESSION_ATTENDED exactly 1): block once with the
#    fixed template when the relayed set has a FLAG or an UNKNOWN for a
#    reason that is not environmental (no repository, no judge class).
#    Otherwise a systemMessage carries the counts and path, or, when every
#    verdict is a PASS, one line with the count.
#
# Opt-in: hooks.json starts it through exec-bash.mjs --require-true
# TEST_GUARDS_ENABLED --require-true TEST_JUDGE_ENABLED. See judge-lib.sh.

set -uo pipefail
trap 'exit 0' EXIT

[[ "${TEST_JUDGE_ACTIVE:-}" == 1 ]] && exit 0
[[ "${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_ENABLED:-false}" == "true" ]] || exit 0
[[ "${CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED:-false}" == "true" ]] || exit 0

INPUT=""
IFS= read -r -d '' -t "${CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT:-2}" INPUT
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# shellcheck source=scanner-run.sh
source "$HOOK_DIR/scanner-run.sh"
testing::fields "$INPUT" .session_id .transcript_path .cwd .stop_hook_active || exit 0
SID="${FIELDS[0]}" TPATH="${FIELDS[1]}" pcwd="${FIELDS[2]}" active="${FIELDS[3]}"
[[ "$SID" =~ ^[A-Za-z0-9_-]+$ && -n "$TPATH" ]] || exit 0
# A turn a Stop hook forced: the verdicts wait for the next task end.
[[ "$active" == true ]] && exit 0
testing::data_dir
testing::pkey "${CLAUDE_PROJECT_DIR:-$pcwd}" "$TPATH" || exit 0
# The idle path: no write recorded and nothing to adopt.
[[ -d "$DATA/sessions/$PKEY/$SID" || -f "$DATA/successors/$PKEY/$SID" ]] || exit 0
# shellcheck source=judge-lib.sh
source "$HOOK_DIR/judge-lib.sh"

# Only the final document reaches stdout.
exec 3>&1 >/dev/null 2>>"$JUDGE_LOG"
LATE="$(mktemp -d)" || exit 0
trap 'rm -rf "$LATE"; exit 0' EXIT
# emit <reason> <systemMessage>: either may be empty; both empty prints nothing.
emit() {
  [[ -n "$1$2" ]] || return 0
  jq -cn --arg r "$1" --arg m "$2" \
    '(if $r == "" then {} else {decision: "block", reason: $r} end) + (if $m == "" then {} else {systemMessage: $m} end)' >&3
}
# plural <n> <one> <many>
plural() { if (($1 == 1)); then printf '%s' "$2"; else printf '%s' "$3"; fi; }
judge::session_set

# relay_needs_decision: true when an attended Stop has something to show. A
# FLAG, or an UNKNOWN whose reason is not environmental. The two environmental
# reasons are the ones judge::run sets without a model run, verbatim.
relay_needs_decision() {
  local norepo noclass
  norepo="no repository: the judge reads only inside a git repository, and this test file is in none"
  noclass="no judge class differs from the writers"
  ((RELAY_F)) && return 0
  ((RELAY_U)) || return 1
  jq -Rne --arg norepo "$norepo" --arg noclass "$noclass" \
    '[inputs | select(length > 0) | fromjson? | select(type == "object" and .verdict == "UNKNOWN" and .reason != $norepo and .reason != $noclass)] | length > 0' \
    <<<"$RELAY" >/dev/null
}


judge::now
deadline=$((NOW + JUDGE_TIMEOUT))
judge::harvest_orphans
judge::load
KF=() KH=() KR=() KFILE=() ST=() HINTS=() RUNPID=()
for fx in "${!INFOS[@]}"; do
  judge::derive "${INFOS[$fx]}"
  HINTS[fx]="$HINT"
  f="${IFILES[$fx]}"
  while read -r kh rest; do
    [[ -n "$kh" ]] || continue
    judge::relayed "$kh" && continue
    KF+=("$fx") KH+=("$kh") KR+=("$rest") KFILE+=("$f")
  done <<<"$KEYS"
done
((${#KH[@]})) || exit 0

# state <i>: ready (a verdict), notrun (2 failed attempts), wait (a live job
# or lock holds it) or free.
state() {
  if judge::verdict "${KH[$1]}"; then
    ST[$1]=ready
  elif judge::spent "${KH[$1]}"; then
    ST[$1]=notrun
  elif judge::busy "${KFILE[$1]}" "${KH[$1]}"; then
    ST[$1]="wait"
  else
    ST[$1]=free
  fi
}
for i in "${!KH[@]}"; do state "$i"; done

# judge_now <file index> <run reservation> <key index>...: one run over the file's keys that
# this process can lock, under a machine slot; in a subshell. The slot wait
# ends at the deadline and the run's bound is what is left after it, so the
# run ends by the deadline. A key left without a verdict at the deadline is
# marked late, for a background job. A reservation the run did not use is
# released.
judge_now() {
  local fx="$1" res="$2" i t keys="" held=()
  shift 2
  for i in "$@"; do
    judge::lock "${KH[$i]}" || continue
    held+=("$DATA/locks/${KH[$i]}")
    judge::verdict "${KH[$i]}" && continue
    keys+="${KH[$i]} ${KR[$i]}"$'\n'
  done
  if [[ -n "$keys" ]] && judge::slot "$deadline"; then
    held+=("$SLOT")
    judge::now
    t=$((deadline - NOW))
    ((t <= JUDGE_RUN_TIMEOUT)) || t=$JUDGE_RUN_TIMEOUT
    if ((t >= 1)); then
      judge::run "${INFOS[$fx]}" "$keys" "$t" "${HINTS[$fx]}" "$res"
      res=""
    fi
  fi
  judge::release_run "$res"
  rm -f ${held[@]+"${held[@]}"}
  judge::now
  if ((NOW >= deadline)); then
    for i in "$@"; do judge::verdict "${KH[$i]}" || : >"$LATE/$i"; done
  fi
}

# start: judge every free key now, one run per file, up to 10 keys per Stop.
used=0
start() {
  local fx i t ids
  judge::now
  t=$((deadline - NOW))
  for fx in "${!INFOS[@]}"; do
    ids=()
    for i in "${!KH[@]}"; do
      [[ "${KF[$i]}" == "$fx" && "${ST[$i]}" == free ]] || continue
      if ((used >= 10)); then
        ST[i]=over
      elif ((t < 1)); then
        ST[i]=late
      else
        ST[i]=run
        ids+=("$i")
        used=$((used + 1))
      fi
    done
    ((${#ids[@]})) || continue
    # Reserved here, before the run's slot wait, so this Stop and the
    # background jobs cannot together pass the session's run limit.
    if ! judge::reserve_run; then
      for i in "${ids[@]}"; do ST[i]=limit; done
      used=$((used - ${#ids[@]}))
      continue
    fi
    judge_now "$fx" "$RUNRES" "${ids[@]}" </dev/null >/dev/null 2>&1 3>&- &
    for i in "${ids[@]}"; do RUNPID[i]=$!; done
  done
}
start

# Wait for background jobs, locks and this Stop's own runs; a job that dies
# frees its keys, which are judged now if the cap allows.
while :; do
  judge::now
  ((NOW < deadline)) || break
  more=0 freed=0
  for i in "${!KH[@]}"; do
    [[ "${ST[$i]}" == wait ]] || continue
    state "$i"
    [[ "${ST[$i]}" == wait ]] && more=1
    [[ "${ST[$i]}" == free ]] && freed=1
  done
  ((freed)) && start
  [[ -z "$(jobs -rp)" ]] || more=1
  ((more)) || break
  sleep 0.5
done
# This Stop's own runs end by the deadline; wait for them no longer than that.
while [[ -n "$(jobs -rp)" ]]; do
  judge::now
  ((NOW <= deadline + 1)) || break
  sleep 0.2
done

# Lateness is decided here, from the deadline: a key this Stop's own run has
# not finished judging (its subshell still alive, or done after the deadline)
# is late, and goes to a background job with the overflow. "Still judging" is
# kept for keys another process's live job or lock holds.
marks=() waiting=() late=() over=() failed=() notrun=() limit=()
for i in "${!KH[@]}"; do
  if judge::verdict "${KH[$i]}"; then
    judge::validate "$VERDICT" "${KFILE[$i]}"
    marks+=("$VOWNER/${KH[$i]}")
  elif [[ "${ST[$i]}" == limit ]]; then
    limit+=("$i")
  elif judge::spent "${KH[$i]}"; then
    notrun+=("$i")
    marks+=("$SID/${KH[$i]}")
  elif [[ "${ST[$i]}" == late || -e "$LATE/$i" ]] ||
    { [[ "${ST[$i]}" == run ]] && kill -0 "${RUNPID[$i]}" 2>/dev/null; }; then
    ST[i]=over
    late+=("$i")
  elif [[ "${ST[$i]}" == over ]]; then
    over+=("$i")
  elif judge::busy "${KFILE[$i]}" "${KH[$i]}"; then
    waiting+=("$i")
  else
    failed+=("$i")
  fi
done

# Hand the keys past the cap, and those the deadline left unjudged, to one
# detached job per file, after this Stop's own runs, with its pending marker
# written before returning.
for fx in "${!INFOS[@]}"; do
  for i in "${!KH[@]}"; do
    [[ "${KF[$i]}" == "$fx" && "${ST[$i]}" == over ]] || continue
    judge::now
    id="stop-$NOW-$RANDOM"
    mkdir -p "$DATA/pending/$PKEY/$SID"
    set -m
    jq -cn --arg s "$SID" --arg u "$id" --arg t "$TPATH" --arg c "$pcwd" --arg f "${KFILE[$i]}" \
      '{session_id: $s, tool_use_id: $u, transcript_path: $t, cwd: $c, tool_input: {file_path: $f}}' |
      TEST_JUDGE_DEBOUNCE=0 TEST_JUDGE_HANDOFF=1 bash "$HOOK_DIR/test-judge-bg.sh" >/dev/null 2>&1 3>&- &
    pid=$!
    set +m
    printf '%s %s %s\n%s\n' "$pid" "$JUDGE_HOST" "$NOW" "${KFILE[$i]}" >"$DATA/pending/$PKEY/$SID/$id"
    break
  done
done

# Counts only: the test names are in the findings file and the judge log.
# Keys waited on, past the cap or late are judged in the background; failed
# keys are retried at the next task end. Both are counts in one line, merged
# into the all-PASS line when there is one. On a blocking Stop the user sees
# the reason, so no systemMessage repeats it.
bg=$((${#waiting[@]} + ${#over[@]} + ${#late[@]})) nf=${#failed[@]} later=""
((bg == 0)) || later="$bg more $(plural "$bg" "test is" "tests are") judged in the background, verdicts at the next task end"
((nf == 0)) || later+="${later:+; }$nf $(plural "$nf" test tests) not judged, the next task end retries"
msg="" reason=""
if ((RELAY_N)); then
  judge::findings
  if ((RELAY_F + RELAY_U == 0)); then
    msg="test judge: $RELAY_N $(plural "$RELAY_N" test tests) PASS${later:+; $later}."
    later=""
  else
    judge::counts
    msg="test judge: $COUNTS${FINDINGS_SHOWN:+ in $FINDINGS_SHOWN}"
    if [[ "${CLAUDE_CODE_SESSION_ATTENDED:-}" == 1 ]] && relay_needs_decision; then
      reason="$msg. Show the user each verdict and proposed diff from it, quoted as data; apply nothing until the user decides."
      msg=""
    fi
  fi
fi
judge::mark_relayed ${marks[@]+"${marks[@]}"}
[[ -z "$later" ]] || msg+="${msg:+$'\n'}test judge: $later."
((${#notrun[@]} == 0)) || msg+="${msg:+$'\n'}test judge: ${#notrun[@]} $(plural ${#notrun[@]} test tests) not judged after 2 failed attempts; see $JUDGE_LOG."
((${#limit[@]} == 0)) || msg+="${msg:+$'\n'}test judge: ${#limit[@]} $(plural ${#limit[@]} test tests) not judged: the session's judge-run limit is reached."
emit "$reason" "$msg"
