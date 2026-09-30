# shellcheck shell=bash
# The task-end test judge's shared pieces, for test-judge-bg.sh (PostToolUse,
# async), test-judge.sh (Stop) and test-judge-start.sh (SessionStart). Source
# after scanner-run.sh, with HOOK_DIR, DATA, PKEY, SID (this session) and TPATH
# (its transcript) set.
#
# State under $DATA, all pruned after 7 days by test-scan.sh:
#   sessions/<pkey>/<sid>/<tool_use_id>.json  test-scan's record of each write
#   verdicts/<pkey>/<sid>/<key-hash>.json     the ledger, written by rename
#   relayed/<pkey>/<sid>/<key-hash>           shown to the user (mirrors the ledger)
#   locks/<key-hash>, slots/<n>               "pid host start", noclobber
#   pending/<pkey>/<sid>/<id>                 a background job: "pid host start", then the file
#   attempts/<key-hash>                       one line per failed attempt
#   runs/<pkey>/<sid>/<id>                    one file per judge run (the session cap)
#   successors/<pkey>/<sid>                   start time of a /clear or fork successor
#
# A key is file::name::ordinal::sha of the block's current text, re-derived by
# running the scanner's --blocks on the file as it is now, so a verdict stays
# valid when lines shift and goes stale when the text changes.
#
# Test seams: TEST_JUDGE_CMD replaces `claude`, TEST_JUDGE_RUN_TIMEOUT (seconds,
# default 150) the per-run hang guard, TEST_SCAN_SCANNER the scanner.
# shellcheck disable=SC2034,SC2154 # globals shared with the sourcing hook

JUDGE_RUN_TIMEOUT="${TEST_JUDGE_RUN_TIMEOUT:-150}"
JUDGE_STALE=$((JUDGE_RUN_TIMEOUT + 30))
JUDGE_SLOTS=3
JUDGE_HOST="${HOSTNAME:-localhost}"
JUDGE_LOG="$DATA/test-judge.log"
JUDGE_RULE=testing/judge/rule-restated-expectation
# Git Bash: a pid from another process tree cannot be probed, so markers go
# stale by age only.
case "${OSTYPE:-}" in msys* | cygwin*) JUDGE_AGE_ONLY=1 ;; *) JUDGE_AGE_ONLY=0 ;; esac
SCANNER="${TEST_SCAN_SCANNER:-$HOOK_DIR/../skills/audit/scripts/cant-fail-scan.sh}"

judge::log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$JUDGE_LOG" 2>/dev/null; }
judge::now() { NOW="${EPOCHSECONDS:-$(date +%s)}"; }
judge::sha() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

# judge::records_json <file>...: one JSON array of the state records, each with
# .sid (the session directory it sits in); a malformed file is skipped.
judge::records_json() {
  local f
  jq -cn '[inputs | objects | . + {sid: (input_filename | split("/") | .[-2])}]' "$@" 2>/dev/null && return
  for f in "$@"; do
    jq -c 'objects | . + {sid: (input_filename | split("/") | .[-2])}' "$f" 2>/dev/null
  done | jq -cs .
}

# judge::last_write <sid>: print the epoch of the session's last recorded write.
judge::last_write() {
  local d="$DATA/sessions/$PKEY/$1"
  compgen -G "$d/*.json" >/dev/null || return 1
  judge::records_json "$d"/*.json | jq -e '[.[].written_at? | strings | fromdate?] | max' 2>/dev/null
}

# judge::session_set: set SESSIONS to this session plus, for a /clear or fork
# successor, every other session under the project key whose last write falls
# within the hour before the successor started.
judge::session_set() {
  local m="$DATA/successors/$PKEY/$SID" t="" d s last
  SESSIONS=("$SID")
  [[ -f "$m" ]] && read -r t <"$m"
  [[ "$t" =~ ^[0-9]+$ ]] || return 0
  for d in "$DATA/sessions/$PKEY"/*/; do
    s="${d%/}" && s="${s##*/}"
    [[ -d "$d" && "$s" != "$SID" ]] || continue
    last="$(judge::last_write "$s")" || continue
    ((last <= t && last > t - 3600)) && SESSIONS+=("$s")
  done
}

# judge::load: set INFOS to one compact JSON object per file the session set's
# records name: the file, its repository, whether any record says "whole file"
# (blocks:null), the block names and ordinals the writes created or changed,
# the first recorded cant-fail-ok: count (0 when that write created the file), the changed lines (the hint for a
# whole-file bash harness), the writers (session and agent ids) and the last
# writer's session (the owner of its verdicts).
judge::load() {
  local s f files=()
  INFOS=()
  for s in "${SESSIONS[@]}"; do
    for f in "$DATA/sessions/$PKEY/$s"/*.json; do [[ -f "$f" ]] && files+=("$f"); done
  done
  ((${#files[@]})) || return 0
  mapfile -t INFOS < <(judge::records_json "${files[@]}" | jq -c '
    map(select(.file | type == "string")) | group_by(.file)[] | {
      file: .[0].file,
      repo: (map(.repo | strings) | .[0] // null),
      whole: any(.[]; .blocks == null),
      names: ([.[].blocks | arrays | .[] | "\(.ordinal) \(.name)"] | unique),
      base_ok: (sort_by(.written_at) | .[0] | if .create == true then 0 else .ok_markers // 0 end),
      lines: ([.[].lines | arrays | .[]] | unique),
      writers: ([.[] | {sid, agent: (.agent_id // "")}] | unique),
      owner: (sort_by(.written_at) | .[-1].sid)}' 2>/dev/null)
}

# judge::derive <info>: set KEYS to one line per in-doubt block of the file as
# it is now, "<key-hash> <ordinal> <start>-<end> <name>", and HINT to the
# changed-line hint for a whole-file key. A block is in doubt when a write
# created or changed it, when a write's blocks are unknown (all blocks), or
# when it holds or sits under a cant-fail-ok: marker and the file's count rose
# above the first recorded one (a created file starts from 0). A file the scanner cannot list, or whose lexer
# lost sync, is one whole-file key. A missing file is logged and skipped.
judge::derive() {
  local file whole base_ok names lines tmpd rc n=0 re line cur marks=() b s e o name keep m text=() i b_start b_end
  KEYS="" HINT=""
  IFS=$'\t' read -r file whole base_ok lines < <(jq -r '[.file, .whole, .base_ok, (.lines | join(","))] | @tsv' <<<"$1")
  if [[ ! -f "$file" ]]; then
    judge::log "skipped: $file no longer exists"
    return 0
  fi
  names=$'\n'"$(jq -r '.names[]' <<<"$1")"$'\n'
  tmpd="$(mktemp -d)" || return 0
  testing::run_scanner "${TEST_SCAN_TIMEOUT:-8}" "$tmpd/scan" --file "$file" --blocks
  rc=$SCAN_RC
  mapfile -t text <"$file"
  re=':([0-9]+)-([0-9]+) ([0-9]+) (.*)$'
  b=()
  if ((rc == 0)) && ! grep -q 'lost sync (not judged): [1-9]' "$tmpd/scan"; then
    while IFS= read -r line; do
      [[ "$line" == "block "* && "$line" =~ $re ]] && b+=("${BASH_REMATCH[3]} ${BASH_REMATCH[1]}-${BASH_REMATCH[2]} ${BASH_REMATCH[4]}")
    done <"$tmpd/scan"
    grep -q '^  adapter: bash-harness' "$tmpd/scan" && HINT="$lines"
  else
    ((rc == 0)) || judge::log "scanner exited $rc on $file: judged as one whole-file key"
    b=("0 1-${#text[@]} ${file##*/}")
    whole=true HINT="$lines"
  fi
  cur=0
  for i in "${!text[@]}"; do
    line="${text[$i]}"
    [[ "$line" == *cant-fail-ok:* ]] || continue
    marks+=($((i + 1)))
    while [[ "$line" == *cant-fail-ok:* ]]; do
      line="${line#*cant-fail-ok:}"
      cur=$((cur + 1))
    done
  done
  for s in "${b[@]}"; do
    o="${s%% *}" name="${s#* }" && name="${name#* }"
    e="${s#* }" && e="${e%% *}" && b_start="${e%-*}" b_end="${e#*-}"
    keep=0
    [[ "$whole" == true || "$names" == *$'\n'"$o $name"$'\n'* ]] && keep=1
    if ((keep == 0 && cur > base_ok)); then
      for m in "${marks[@]}"; do ((m >= b_start - 1 && m <= b_end)) && keep=1; done
    fi
    ((keep)) || continue
    n=$((n + 1))
    printf '%s::%s::%s::\n' "$file" "$name" "$o" >"$tmpd/k$n"
    printf '%s\n' "${text[@]:b_start-1:b_end-b_start+1}" >>"$tmpd/k$n"
    printf '%s\n' "$s" >"$tmpd/d$n"
  done
  if ((n)); then
    b=()
    while read -r m line; do
      b[${line##*/k}]="${m:0:32}"
    done < <(judge::sha "$tmpd"/k*)
    for ((i = 1; i <= n; i++)); do KEYS+="${b[i]} $(<"$tmpd/d$i")"$'\n'; done
  fi
  rm -rf "$tmpd"
}

# judge::verdict <key-hash>: set VERDICT to the key's ledger file in the
# session set and VOWNER to the session it sits under; false when there is none.
judge::verdict() {
  local s
  VERDICT="" VOWNER=""
  for s in "${SESSIONS[@]}"; do
    if [[ -f "$DATA/verdicts/$PKEY/$s/$1.json" ]]; then
      VERDICT="$DATA/verdicts/$PKEY/$s/$1.json" VOWNER="$s"
      return 0
    fi
  done
  return 1
}

# judge::relayed <key-hash>: true when any session in the set relayed it.
judge::relayed() {
  local s
  for s in "${SESSIONS[@]}"; do [[ -e "$DATA/relayed/$PKEY/$s/$1" ]] && return 0; done
  return 1
}

# judge::mark <path> [pid]: create a marker exclusively, holding "pid host start".
judge::mark() {
  local pid="${2:-$BASHPID}"
  judge::now
  (set -o noclobber && printf '%s %s %s\n' "$pid" "$JUDGE_HOST" "$NOW" >"$1") 2>/dev/null
}

# judge::stale <path> <seconds>: true when the marker is missing, older than
# the limit, or held by a dead process on this host.
judge::stale() {
  local pid="" host="" start=""
  [[ -e "$1" ]] || return 0
  read -r pid host start <"$1" 2>/dev/null
  # Empty: its writer is between create and write, unless it is minutes old.
  [[ -n "$pid" ]] || {
    [[ -n "$(find "$1" -mmin +3 2>/dev/null)" ]]
    return
  }
  judge::now
  [[ "$start" =~ ^[0-9]+$ ]] && ((NOW - start <= $2)) || return 0
  ((JUDGE_AGE_ONLY == 0)) && [[ "$host" == "$JUDGE_HOST" ]] && ! kill -0 "$pid" 2>/dev/null && return 0
  return 1
}

# judge::fail <key-hash> <why>: record one failed attempt.
judge::fail() {
  mkdir -p "$DATA/attempts"
  printf '%s\n' "$2" >>"$DATA/attempts/$1"
  judge::log "attempt failed: $1: $2"
}
judge::attempts() {
  local n=0
  [[ -f "$DATA/attempts/$1" ]] && n="$(wc -l <"$DATA/attempts/$1")"
  printf '%d' "$n"
}

# judge::lock <key-hash>: take the key's lock. A stale one is broken and
# counted as one failed attempt.
# ponytail: two processes breaking one stale lock at once can both take it; the
# verdict re-check after locking catches most of that.
judge::lock() {
  local l="$DATA/locks/$1"
  mkdir -p "$DATA/locks"
  judge::mark "$l" && return 0
  judge::stale "$l" "$JUDGE_STALE" || return 1
  judge::fail "$1" "stale lock broken"
  rm -f "$l"
  judge::mark "$l"
}

# judge::slot <deadline>: take one of the machine's judge slots, waiting until
# the deadline; sets SLOT.
judge::slot() {
  local i s
  SLOT=""
  mkdir -p "$DATA/slots"
  while :; do
    for ((i = 0; i < JUDGE_SLOTS; i++)); do
      s="$DATA/slots/$i"
      if judge::mark "$s" || { judge::stale "$s" "$JUDGE_STALE" && rm -f "$s" && judge::mark "$s"; }; then
        SLOT="$s"
        return 0
      fi
    done
    judge::now
    ((NOW < $1)) || return 1
    sleep 1
  done
}

# judge::busy <file> <key-hash>: true while a live background job owns the
# file or a live lock holds the key.
judge::busy() {
  local s p f
  for s in "${SESSIONS[@]}"; do
    for p in "$DATA/pending/$PKEY/$s"/*; do
      [[ -f "$p" ]] || continue
      f="$(sed -n 2p "$p")"
      [[ "$f" == "$1" ]] && ! judge::stale "$p" "$((${TEST_JUDGE_DEBOUNCE:-20} + JUDGE_STALE + 60))" && return 0
    done
  done
  [[ -e "$DATA/locks/$2" ]] && ! judge::stale "$DATA/locks/$2" "$JUDGE_STALE"
}

# judge::runs_left [planned]: true while the session's optional judge-run
# limit allows another run beyond the planned ones not yet started.
judge::runs_left() {
  local cap="${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_SESSION_RUNS:-}" n
  [[ "$cap" =~ ^[0-9]+$ ]] || return 0
  n="$(find "$DATA/runs/$PKEY/$SID" -type f 2>/dev/null | wc -l)"
  ((n + ${1:-0} < cap))
}

judge::class() {
  case "$1" in
  *fable*) echo fable ;;
  *opus*) echo opus ;;
  *sonnet*) echo sonnet ;;
  *haiku*) echo haiku ;;
  *) ;;
  esac
}

# judge::transcript_class <jsonl>: the class of the last assistant model in
# the transcript's last 400 lines, skipping <synthetic> lines.
judge::transcript_class() {
  [[ -f "$1" ]] || return 0
  judge::class "$(tail -n 400 "$1" | jq -Rr 'fromjson? | select(.type? == "assistant")
    | .message.model? | strings | select(. != "<synthetic>")' 2>/dev/null | tail -n 1)"
}

# judge::pick <writers json>: set MODEL to a judge class that differs from
# every writer class (the main session's always counts; each writing session's
# transcript and subagent transcript add theirs), and EFFORT; false when none
# remains. Walks the configured model, the fallback, then opus, sonnet, haiku.
judge::pick() {
  local tdir="${TPATH%[/\\]*}" writers=" " sid agent c m fb
  writers+="$(judge::transcript_class "$TPATH") "
  while IFS=$'\t' read -r sid agent; do
    writers+="$(judge::transcript_class "$tdir/$sid.jsonl") "
    [[ -z "$agent" ]] || writers+="$(judge::transcript_class "$tdir/$sid/subagents/agent-$agent.jsonl") "
  done < <(jq -r '.[] | [.sid, .agent] | @tsv' <<<"$1")
  m="${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_MODEL:-opus}"
  [[ "$m" =~ ^(fable|opus|sonnet|haiku)$ ]] || m=opus
  fb="${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_FALLBACK_MODEL:-sonnet}"
  [[ "$fb" =~ ^(fable|opus|sonnet|haiku)$ ]] || fb=sonnet
  EFFORT="${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_EFFORT:-medium}"
  [[ "$EFFORT" =~ ^(low|medium|high|xhigh|max)$ ]] || EFFORT=medium
  for c in "$m" "$fb" opus sonnet haiku; do
    if [[ "$writers" != *" $c "* ]]; then
      MODEL="$c"
      return 0
    fi
  done
  MODEL=""
  return 1
}

# judge::harvest <raw> [reason]: split a finished run's output (or, with a
# reason, UNKNOWN for every key) into one ledger file per key, each written to
# a temp file and renamed. The run's sidecar <raw>.keys names the keys. False
# when the output holds no usable result; a key the output leaves out gets no
# verdict. Any later reader may harvest a raw file whose writer died.
judge::harvest() {
  local raw="$1" dir="${1%/*}" kh json
  [[ -f "$raw.keys" ]] || return 1
  [[ -n "${2:-}" || -s "$raw" ]] || return 1
  out="$(jq -rn --slurpfile meta "$raw.keys" --rawfile raw "$raw" --arg forced "${2:-}" '
    $meta[0] as $m
    | (if $forced != "" then {reason: $forced}
       else ($raw | fromjson? // {}) as $e
       | if ($e | type) != "object" then null
         elif $e.subtype == "error_max_budget_usd" then {reason: "the judge hit its $\($m.budget) malfunction budget"}
         elif ($e.result | type) == "string" then
           ($e.result | (index("{") // -1) as $i | (rindex("}") // -1) as $j
             | if $i < 0 or $j < $i then null else .[$i:$j + 1] | fromjson? end) as $v
           | if ($v | type) == "object" then {verdicts: [$v.verdicts[]? | objects]} else null end
         else null end end) as $r
    | if $r == null then empty else
      $m.keys[] as $k
      | (if $r.reason then {verdict: "UNKNOWN", reason: $r.reason}
         else [$r.verdicts[] | select(.name == $k.name and ((.ordinal // $k.ordinal) | tostring) == ($k.ordinal | tostring))][0] end) as $v
      | select($v != null)
      | ($v.verdict | IN("FLAG", "PASS", "UNKNOWN")) as $ok
      | "\($k.kh) \({file: $m.file, repo: $m.repo, name: $k.name, ordinal: $k.ordinal, start: $k.start, end: $k.end,
          verdict: (if $ok then $v.verdict else "UNKNOWN" end),
          evidence: [$v.evidence[]? | strings], source: ($v.source // "" | tostring), diff: ($v.diff // "" | tostring),
          reason: (if $ok then ($v.reason // "" | tostring) else "the judge returned no valid verdict" end),
          model: $m.model, effort: $m.effort, judged_at: (now | todate)} | tojson)"
      end' 2>/dev/null)" || return 1
  [[ -n "$out" ]] || return 1
  while read -r kh json; do
    printf '%s\n' "$json" >"$dir/.$kh.tmp" && mv -f "$dir/.$kh.tmp" "$dir/$kh.json"
  done <<<"$out"
}

# judge::harvest_orphans: harvest the raw output of every run in the session
# set whose parent died before splitting it (a raw file still being written
# does not parse and is left alone).
judge::harvest_orphans() {
  local s r
  for s in "${SESSIONS[@]}"; do
    for r in "$DATA/verdicts/$PKEY/$s"/.run-*.keys; do
      [[ -f "$r" ]] || continue
      r="${r%.keys}"
      [[ -s "$r" ]] && judge::harvest "$r" && rm -f "$r" "$r.keys" "$r.err"
    done
  done
}

judge::section1() {
  awk '/^## 1\. /{f=1} f&&/^## /&&!/^## 1\. /{exit} f' "$HOOK_DIR/../skills/test-value/SKILL.md" 2>/dev/null
}

# judge::run <info> <keys> <seconds> <hint>: one judge run over the file's keys
# (the caller holds their locks and a slot), writing verdicts under the ledger
# of the file's last writer, so a successor that adopts that session finds
# them and their relay markers. A key left without a verdict gets a failed
# attempt.
judge::run() {
  local info="$1" keys="$2" t="$3" hint="$4" dir file repo owner n budget raw sys prompt rc kh here
  IFS=$'\t' read -r file repo owner < <(jq -r '[.file, (.repo // ""), (.owner // "")] | @tsv' <<<"$info")
  dir="$DATA/verdicts/$PKEY/${owner:-$SID}"
  [[ -n "$repo" && -d "$repo" ]] || repo="${file%/*}"
  n="$(grep -c . <<<"$keys")"
  budget="$((((n + 9) / 10) * 90))" && budget="$((budget / 100)).$(printf '%02d' $((budget % 100)))"
  mkdir -p "$dir" "$DATA/runs/$PKEY/$SID"
  raw="$dir/.run-$BASHPID-$RANDOM"
  judge::pick "$(jq -c .writers <<<"$info")"
  jq -Rn --arg file "$file" --arg repo "$repo" --arg model "$MODEL" --arg effort "$EFFORT" --arg budget "$budget" '
    {file: $file, repo: $repo, model: $model, effort: $effort, budget: $budget,
     keys: [inputs | select(. != "") | capture("^(?<kh>[^ ]+) (?<ordinal>[0-9]+) (?<start>[0-9]+)-(?<end>[0-9]+) (?<name>.*)$")
       | .ordinal |= tonumber | .start |= tonumber | .end |= tonumber]}' <<<"$keys" >"$raw.keys"
  if [[ -z "$MODEL" ]]; then
    : >"$raw"
    judge::harvest "$raw" "no judge class differs from the writers"
    rm -f "$raw" "$raw.keys"
    return 0
  fi
  sys="$(cat "$HOOK_DIR/test-judge-prompt.md" 2>/dev/null)"$'\n\n'"$(judge::section1)"
  prompt="Judge these test blocks in $file (block <ordinal> <start>-<end> <name>):"$'\n'"$(sed -n 's/^[^ ]* /block /p' <<<"$keys")"
  [[ -z "$hint" ]] || prompt+=$'\n'"Changed lines in this file, a hint to where the new tests are: $hint"
  if [[ "$sys" != *"## 1. "* ]]; then
    rc="the judge prompt or test-value section 1 is missing"
  else
    touch "$DATA/runs/$PKEY/$SID/$BASHPID-$RANDOM"
    # The hang guard is the process-group watchdog, not coreutils timeout.
    here="$PWD"
    cd "$repo" || return 0
    testing::run_bounded "$t" "$raw" "$raw.err" env TEST_JUDGE_ACTIVE=1 "${TEST_JUDGE_CMD:-claude}" -p --model "$MODEL" \
      --system-prompt "$sys" --tools Read,Grep,Glob \
      --allowedTools "Read($repo/**)" "Grep($repo/**)" "Glob($repo/**)" \
      --settings '{"disableAllHooks":true}' --setting-sources "" --strict-mcp-config \
      --disable-slash-commands --effort "$EFFORT" --max-budget-usd "$budget" \
      --no-session-persistence --output-format json "$prompt" </dev/null
    rc=$SCAN_RC
    cd "$here" || :
    grep -q '"error_max_budget_usd"' "$raw" 2>/dev/null && judge::log "malfunction: judge run on $file hit its \$$budget budget"
    judge::harvest "$raw" || rc="judge exited $rc with no usable result"
  fi
  while read -r kh _; do
    [[ -n "$kh" && ! -f "$dir/$kh.json" ]] && judge::fail "$kh" "$rc"
  done <<<"$keys"
  rm -f "$raw" "$raw.keys" "$raw.err"
}

# judge::label <verdict or info json fields: file name ordinal>: "<file>: <name>", with #n past the first.
judge::label() {
  local l="${1##*/}: $2"
  (($3 > 1)) && l+=" #$3"
  printf '%s' "$l"
}

# judge::validate <verdict file>: print the verdict as it may be relayed. A
# quote that is not in the current file, a FLAG with no diff, or a diff that
# fails `git apply --check` or touches another file makes it UNKNOWN, with the
# reason.
judge::validate() {
  local v="$1" file repo verdict why="" tmp p
  IFS=$'\t' read -r file repo verdict < <(jq -r '[.file, (.repo // ""), .verdict] | @tsv' "$v")
  [[ -n "$repo" && -d "$repo" ]] || repo="${file%/*}"
  if [[ ! -f "$file" ]]; then
    why="the test file no longer exists"
  elif [[ "$verdict" != UNKNOWN ]] && ! jq -e '.evidence | length > 0' "$v" >/dev/null; then
    why="the verdict quotes no evidence"
  elif ! jq -e --rawfile text "$file" 'all(.evidence[]; . as $q | $text | contains($q))' "$v" >/dev/null; then
    why="a quoted line is not in the file"
  elif [[ "$verdict" == FLAG ]]; then
    tmp="$(mktemp)"
    jq -r .diff "$v" >"$tmp"
    if ! jq -e '.diff | length > 0' "$v" >/dev/null; then
      why="the FLAG proposes no diff"
    elif ! (cd "$repo" && git apply --check "$tmp") >/dev/null 2>&1; then
      why="the proposed diff does not apply"
    else
      while IFS=$'\t' read -r _ _ p; do
        [[ "$repo/$p" == "$file" ]] || why="the proposed diff touches another file"
      done < <(cd "$repo" && git apply --numstat "$tmp" 2>/dev/null)
    fi
    rm -f "$tmp"
  fi
  jq -c --arg why "$why" 'if $why == "" then . else .verdict = "UNKNOWN" | .reason = $why end' "$v"
}

judge::slug() {
  local s
  s="$(printf '%s' "$1" | tr 'A-Z/' 'a-z-' | tr -c 'a-z0-9-' '-' | tr -s '-')"
  s="${s#-}" && s="${s%-}"
  if ((${#s} > 40)); then
    s="${s:0:40}"
    [[ "$s" == *-* ]] && s="${s%-*}"
  fi
  case "$s" in
  con | prn | aux | nul | com[1-9] | lpt[1-9]) s+=-x ;;
  *) ;;
  esac
  printf '%s' "${s:-detached}"
}

# judge::findings_dir <repo>: the findings directory the detector-findings
# contract resolves for a headless producer: .claude/topic-docs.yaml's
# memory_dir, else .work, then reviews/<branch-slug>/, with the memory root's
# self-ignoring .gitignore. No branch, no repository or a root-equivalent
# memory_dir: the plugin data directory.
judge::findings_dir() {
  local repo="$1" branch="" mem up real top
  [[ -n "$repo" && -d "$repo" ]] && branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
  if [[ -z "$branch" ]]; then
    printf '%s' "$DATA/findings"
    return
  fi
  mem="$(sed -n 's/^memory_dir:[[:space:]]*//p' "$repo/.claude/topic-docs.yaml" 2>/dev/null | head -n 1)"
  mem="${mem%%#*}" && mem="${mem//[\"\']/}" && mem="${mem%"${mem##*[![:space:]]}"}"
  mem="${mem:-.work}"
  case "$mem" in /* | ?:*) ;; *) mem="$repo/${mem#./}" ;; esac
  mem="${mem%/}"
  # The memory root must sit strictly inside the checkout, symlinks resolved
  # on its nearest existing ancestor, or the self-ignore write would land in
  # another tree.
  up="$mem"
  while [[ ! -d "$up" && "$up" == */* ]]; do up="${up%/*}"; done
  real="$(cd "$up" 2>/dev/null && pwd -P)/${mem#"$up"}" && real="${real%/}"
  top="$(cd "$repo" && pwd -P)"
  if [[ "/$mem/" == */../* || "/$mem/" == */./* || "$real" != "$top/"?* ]] || ! mkdir -p "$mem"; then
    printf '%s' "$DATA/findings"
    return
  fi
  [[ -f "$mem/.gitignore" ]] || printf '*\n' >"$mem/.gitignore"
  printf '%s' "$mem/reviews/$(judge::slug "$branch")"
}

# judge::findings <validated verdict lines>: write one findings file per
# repository in the detector-findings shape (FLAG rows under ## Findings; every
# verdict, its quoted evidence and proposed diff under ## Verdicts) and set
# FINDINGS to their paths, comma-separated.
judge::findings() {
  local all="$1" repo dir ts path i branch
  FINDINGS=""
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  while IFS= read -r repo; do
    dir="$(judge::findings_dir "$repo")"
    branch=""
    [[ -z "$repo" ]] || branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
    mkdir -p "$dir" || continue
    path="$dir/$ts-test-judge.md"
    i=2
    while [[ -e "$path" ]]; do
      path="$dir/$ts-test-judge-$i.md"
      i=$((i + 1))
    done
    jq -rs --arg repo "$repo" --arg branch "$branch" --arg rule "$JUDGE_RULE" '
      def esc: tostring | gsub("\\|"; "\\|") | gsub("[\r\n]+"; " ");
      def rel: .file | ltrimstr($repo + "/");
      def tname: "\(.name)\(if .ordinal > 1 then " #\(.ordinal)" else "" end)";
      map(select((.repo // "") == $repo)) as $v
      | ($v | map(select(.verdict == "FLAG"))) as $f
      | "---\ntype: review-findings\ndate: \(now | todate)\nbranch: \(if $branch == "" then "none" else $branch end)\n---\n\n## Findings\n\n"
      + "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |\n|------|------|------------|----------|------------|---------|--------|\n"
      + ([$f | to_entries[] | "| \(.key + 1) | SUGGESTION |  | \(.value | rel):\(.value.start) | testing:test-judge | \($rule): test \(.value | tname | esc) takes its expected value from the implementation: \(.value.source | esc) (threshold: a FLAG verdict, every quote found in the file, its diff applies to this file alone) | Replace the expected value with one from an independent source; the proposed diff (not applied) is under Verdicts, \(.value | rel) \(.value | tname | esc) |\n"] | join(""))
      + "\n## Surfaces\n\nRan: [testing:test-judge — \($v | length) test block(s) judged; findings: \($rule) \($f | length); declined (judged PASS): \($rule) \($v | map(select(.verdict == "PASS")) | length); UNKNOWN: \($v | map(select(.verdict == "UNKNOWN")) | length)]. Returned no result: [none].\n"
      + "\n## Verdicts\n\nEach verdict below is the judge'"'"'s output, quoted as data. Nothing here has been applied.\n"
      + ([$v[] | "\n### \(.verdict) \(rel) \(tname) (lines \(.start)-\(.end))\n\n"
        + (if .reason != "" then "Reason: \(.reason)\n\n" else "" end)
        + "Judge: \(.model) at \(.effort) effort.\n\n"
        + (if .source != "" then "Where the expected value came from: \(.source)\n\n" else "" end)
        + ([.evidence[] | "> " + gsub("[\r\n]+"; " ") + "\n"] | join(""))
        + (if .verdict == "FLAG" and .diff != "" then "\nProposed diff, not applied:\n\n````diff\n\(.diff | rtrimstr("\n"))\n````\n" else "" end)] | join(""))
      ' <<<"$all" >"$path" 2>/dev/null || continue
    FINDINGS+="${FINDINGS:+, }$path"
  done < <(jq -r '.repo // ""' <<<"$all" | sort -u)
}

# judge::counts <validated verdict lines>: "N tests (F FLAG, P PASS, U UNKNOWN)".
judge::counts() {
  jq -rs '"\(length) test\(if length == 1 then "" else "s" end) (\(map(select(.verdict == "FLAG")) | length) FLAG, \(map(select(.verdict == "PASS")) | length) PASS, \(map(select(.verdict == "UNKNOWN")) | length) UNKNOWN)"' <<<"$1"
}
