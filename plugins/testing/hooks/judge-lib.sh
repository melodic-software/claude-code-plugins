# shellcheck shell=bash
# TEST_JUDGE_REUSE=0 turns verdict reuse off (judge::reuse).
# shellcheck disable=SC2034,SC2154 # globals shared with the sourcing hook

judge::num() {
  if [[ "$2" =~ ^[0-9]{1,6}$ ]]; then printf -v "$1" '%d' "$((10#$2))"; else printf -v "$1" '%d' "$3"; fi
}
JUDGE_RUN_TIMEOUT="" JUDGE_DEBOUNCE="" JUDGE_TIMEOUT="" JUDGE_SCAN_TIMEOUT=""
judge::num JUDGE_RUN_TIMEOUT "${TEST_JUDGE_RUN_TIMEOUT:-}" 150
judge::num JUDGE_DEBOUNCE "${TEST_JUDGE_DEBOUNCE:-}" 20
judge::num JUDGE_TIMEOUT "${TEST_JUDGE_TIMEOUT:-}" 180
judge::num JUDGE_SCAN_TIMEOUT "${TEST_SCAN_TIMEOUT:-}" 8
JUDGE_STALE=$((JUDGE_RUN_TIMEOUT + 30))
JUDGE_SLOTS=3
JUDGE_HOST="${HOSTNAME:-localhost}"
JUDGE_LOG="$DATA/test-judge.log"
JUDGE_RULE=testing/judge/rule-restated-expectation
case "${OSTYPE:-}" in msys* | cygwin*) JUDGE_AGE_ONLY=1 ;; *) JUDGE_AGE_ONLY=0 ;; esac
SCANNER="${TEST_SCAN_SCANNER:-$HOOK_DIR/../skills/audit/scripts/cant-fail-scan.sh}"

case "${TESTING_OSTYPE:-${OSTYPE:-}}" in msys* | cygwin*) JUDGE_WIN=1 ;; *) JUDGE_WIN=0 ;; esac

judge::same_path() {
  local a="$1" b="$2"
  if ((JUDGE_WIN)); then
    a="${a//\\//}" b="${b//\\//}"
    [[ "$a" =~ ^/([a-zA-Z])/(.*)$ ]] && a="${BASH_REMATCH[1]}:/${BASH_REMATCH[2]}"
    [[ "$b" =~ ^/([a-zA-Z])/(.*)$ ]] && b="${BASH_REMATCH[1]}:/${BASH_REMATCH[2]}"
    a="${a,,}" b="${b,,}"
  fi
  [[ "$a" == "$b" ]]
}

judge::read_rule() {
  local p="$2" q="" c i
  if ((JUDGE_WIN)); then
    p="${p//\\//}"
    [[ "$p" =~ ^([a-zA-Z]):(/.*)?$ ]] && p="/${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"
  fi
  while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
  [[ "$p" == / ]] && p=""
  for ((i = 0; i < ${#p}; i++)); do
    c="${p:i:1}"
    case "$c" in \\ | '*' | '?' | '[' | ']') q+=\\ ;; *) ;; esac
    q+="$c"
  done
  printf -v "$1" 'Read(/%s/**)' "$q"
}

declare -gA JUDGE_FREPO=() JUDGE_FREPO_OUT=()
judge::file_repo() {
  local f="$1" d="" c top pd pt cands=("$1")
  FREPO="" FREPO_OUT=""
  [[ -n "$f" ]] || return 0
  if [[ -n "${JUDGE_FREPO["$f"]+x}" ]]; then
    FREPO="${JUDGE_FREPO["$f"]}" FREPO_OUT="${JUDGE_FREPO_OUT["$f"]}"
    return 0
  fi
  ((JUDGE_WIN)) && cands=("${f//\\//}" "$f")
  for c in "${cands[@]}"; do
    [[ "$c" == */* ]] || continue
    c="${c%/*}"
    [[ -n "$c" ]] || c=/
    [[ -d "$c" ]] && d="$c" && break
  done
  if [[ -n "$d" ]]; then
    top="$(unset GIT_DIR GIT_WORK_TREE && git -C "$d" rev-parse --show-toplevel 2>/dev/null)"
    top="${top//$'\r'/}"
    if [[ -n "$top" ]]; then
      if judge::phys pt "$top" && judge::phys pd "$d" && [[ "$pd" == "$pt" || "$pd" == "$pt/"* ]]; then
        FREPO="$top"
      else
        FREPO_OUT="$top"
      fi
    fi
  fi
  JUDGE_FREPO["$f"]="$FREPO" JUDGE_FREPO_OUT["$f"]="$FREPO_OUT"
}

judge::log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$JUDGE_LOG" 2>/dev/null; }
judge::now() { NOW="${EPOCHSECONDS:-$(date +%s)}"; }
judge::sha() { if command -v sha256sum >/dev/null; then sha256sum -- "$@"; else shasum -a 256 -- "$@"; fi; }

judge::records_json() {
  local f
  jq -cn '[inputs | objects | . + {sid: (input_filename | split("/") | .[-2])}]' "$@" 2>/dev/null && return
  for f in "$@"; do
    jq -c 'objects | . + {sid: (input_filename | split("/") | .[-2])}' "$f" 2>/dev/null
  done | jq -cs .
}

judge::last_write() {
  local d="$DATA/sessions/$PKEY/$1" last='[.[] | objects | .written_at? | strings | fromdate?] | max'
  compgen -G "$d/*.json" >/dev/null || return 1
  jq -en "[inputs] | $last" "$d"/*.json 2>/dev/null ||
    judge::records_json "$d"/*.json | jq -e "$last" 2>/dev/null
}

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

judge::load() {
  # shellcheck disable=SC2016 # $skip and $a are jq variables
  local s f files=() out i fa group='map(select(.file | type == "string"))
    | group_by(.file)[]
    | select(all(.[]; (.agent_id // "" | tostring) as $a | $a == "" or ($skip | contains(" \($a) ") | not)))
    | {
      file: .[0].file,
      repo: (map(.repo | strings) | .[0] // null),
      whole: any(.[]; .blocks == null),
      names: ([.[].blocks | arrays | .[] | "\(.ordinal) \(.name)"] | unique),
      base_ok: (sort_by(.written_at) | .[0] | if .create == true then 0 else .ok_markers // 0 end),
      lines: ([.[].lines | arrays | .[]] | unique),
      writers: ([.[] | {sid, agent: (.agent_id // "")}] | unique),
      owner: (sort_by(.written_at) | .[-1].sid)} | (.file | gsub("[\r\n]"; "")), tojson'
  INFOS=() IFILES=()
  for s in "${SESSIONS[@]}"; do
    for f in "$DATA/sessions/$PKEY/$s"/*.json; do [[ -f "$f" ]] && files+=("$f"); done
  done
  ((${#files[@]})) || return 0
  fa=(--arg skip " ${JUDGE_AGENT_SKIP:-} ")
  out="$(jq -rn "${fa[@]}" "[inputs | objects | . + {sid: (input_filename | split(\"/\") | .[-2])}] | $group" "${files[@]}" 2>/dev/null)" ||
    out="$(judge::records_json "${files[@]}" | jq -r "${fa[@]}" "$group" 2>/dev/null)"
  mapfile -t f <<<"$out"
  for ((i = 0; i + 1 < ${#f[@]}; i += 2)); do
    IFILES+=("${f[i]}")
    INFOS+=("${f[i + 1]}")
  done
}

judge::drop() {
  # shellcheck disable=SC2016 # $f is a jq variable
  local s r recs=() hits q='objects | select(.file == $f) | input_filename'
  for s in "${SESSIONS[@]}"; do
    for r in "$DATA/sessions/$PKEY/$s"/*.json; do [[ -f "$r" ]] && recs+=("$r"); done
  done
  ((${#recs[@]})) || return 0
  hits="$(jq -r --arg f "$1" "$q" "${recs[@]}" 2>/dev/null)" ||
    hits="$(for r in "${recs[@]}"; do jq -r --arg f "$1" "$q" "$r" 2>/dev/null; done)"
  while IFS= read -r r; do
    [[ -n "$r" ]] || continue
    [[ -f "$1" ]] && return 0
    rm -f -- "$r"
  done <<<"$hits"
}

judge::derive() {
  local file whole base_ok names lines tmpd rc n=0 re line cur marks=() b s e o name keep m text=() i b_start b_end
  local root cfg cfgs=() key="" h cache c=()
  KEYS="" HINT=""
  testing::fields "$1" .file .whole .base_ok '.lines | join(",")' '.names | join("\n")' || return 0
  file="${FIELDS[0]}" whole="${FIELDS[1]}" base_ok="${FIELDS[2]:-0}" lines="${FIELDS[3]}"
  names=$'\n'"${FIELDS[4]}"$'\n'
  if [[ ! -f "$file" ]]; then
    judge::drop "$file"
    judge::log "skipped: $file no longer exists; dropped from the session's records"
    return 0
  fi
  judge::file_repo "$file"
  root="${FREPO:-${CLAUDE_PROJECT_DIR:-}}"
  for cfg in "${HOME:-}/.claude/testing.yaml" "$root/docs/conventions/testing.yaml" "$root/docs/conventions/testing.md" \
    "$root/docs/conventions/testing.local.yaml" "$root/.claude/testing.yaml" "$root/.claude/testing.local.yaml"; do
    [[ -f "$cfg" ]] && cfgs+=("$cfg")
  done
  while read -r h _; do
    h="${h#\\}"
    key+="${h:0:16}"
  done < <(printf '%s\n%s\n%s\n' "$1" "$HOOK_DIR" "$SCANNER" | judge::sha - "$file" "${cfgs[@]}")
  cache="$DATA/derive/$key"
  if ((${#key} >= 32)) && [[ -f "$cache" ]]; then
    mapfile -t c <"$cache"
    HINT="${c[0]:-}"
    for line in "${c[@]:1}"; do [[ -z "$line" ]] || KEYS+="$line"$'\n'; done
    return 0
  fi
  tmpd="$(mktemp -d)" || return 0
  testing::run_scanner "$JUDGE_SCAN_TIMEOUT" "$tmpd/scan" --file "$file" --blocks
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
    b=("0 1-${#text[@]} ${file##*[/\\]}")
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
  if ((rc == 0 && ${#key} >= 32)) && mkdir -p "$DATA/derive"; then
    printf '%s\n%s' "$HINT" "$KEYS" >"$cache.$$.tmp" && mv -f "$cache.$$.tmp" "$cache"
  fi
}

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

judge::relayed() {
  local s
  for s in "${SESSIONS[@]}"; do [[ -e "$DATA/relayed/$PKEY/$s/$1" ]] && return 0; done
  return 1
}

judge::mark() {
  local pid="${2:-$BASHPID}"
  judge::now
  (set -o noclobber && printf '%s %s %s\n' "$pid" "$JUDGE_HOST" "$NOW" >"$1") 2>/dev/null
}

judge::stale() {
  local pid="" host="" start=""
  [[ -e "$1" ]] || return 0
  read -r pid host start <"$1" 2>/dev/null
  [[ -n "$pid" ]] || {
    [[ -n "$(find "$1" -mmin +3 2>/dev/null)" ]]
    return
  }
  judge::now
  [[ "$start" =~ ^[0-9]+$ ]] && ((NOW - start <= $2)) || return 0
  ((JUDGE_AGE_ONLY == 0)) && [[ "$host" == "$JUDGE_HOST" ]] && ! kill -0 "$pid" 2>/dev/null && return 0
  return 1
}

judge::fail() {
  mkdir -p "$DATA/attempts"
  printf '%s\n' "$2" >>"$DATA/attempts/$1"
  judge::log "attempt failed: $1: $2"
}
judge::spent() {
  local a=()
  [[ -f "$DATA/attempts/$1" ]] && mapfile -t a <"$DATA/attempts/$1"
  ((${#a[@]} >= 2))
}

judge::lock() {
  local l="$DATA/locks/$1"
  mkdir -p "$DATA/locks"
  judge::mark "$l" && return 0
  judge::stale "$l" "$JUDGE_STALE" || return 1
  judge::fail "$1" "stale lock broken"
  rm -f "$l"
  judge::mark "$l"
}

judge::wait_lock() {
  local l="$DATA/locks/$1" until
  judge::now
  until=$((NOW + JUDGE_STALE))
  while [[ -e "$l" ]] && ! judge::stale "$l" "$JUDGE_STALE"; do
    judge::now
    ((NOW < until)) || return 1
    sleep 1
  done
}

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

judge::busy() {
  local s p f
  for s in "${SESSIONS[@]}"; do
    for p in "$DATA/pending/$PKEY/$s"/*; do
      [[ -f "$p" ]] || continue
      f=""
      { read -r _ && IFS= read -r f; } <"$p"
      [[ "$f" == "$1" ]] && ! judge::stale "$p" "$((JUDGE_DEBOUNCE + JUDGE_STALE + 60))" && return 0
    done
  done
  [[ -e "$DATA/locks/$2" ]] && ! judge::stale "$DATA/locks/$2" "$JUDGE_STALE"
}

judge::reserve_run() {
  local cap="${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_SESSION_RUNS:-}" d="$DATA/runs/$PKEY/$SID" n
  RUNRES=""
  [[ -d "$d" ]] || mkdir -p "$d" || return 1
  if [[ ! "$cap" =~ ^[0-9]{1,6}$ ]]; then
    RUNRES="$d/$BASHPID-$RANDOM"
    judge::excl "$RUNRES" "$BASHPID" || RUNRES=""
    return 0
  fi
  for ((n = 1; n <= 10#$cap; n++)); do
    judge::excl "$d/$n" "$BASHPID" && RUNRES="$d/$n" && return 0
  done
  return 1
}
judge::release_run() { [[ -z "${1:-}" ]] || rm -f -- "$1"; }

judge::class() {
  case "$1" in
  *fable*) echo fable ;;
  *opus*) echo opus ;;
  *sonnet*) echo sonnet ;;
  *haiku*) echo haiku ;;
  *) ;;
  esac
}

judge::transcript_class() {
  [[ -f "$1" ]] || return 0
  judge::class "$(tail -n 400 "$1" | jq -Rr 'fromjson? | select(.type? == "assistant")
    | .message.model? | strings | select(. != "<synthetic>")' 2>/dev/null | tail -n 1)"
}

judge::pick() {
  local tdir="${TPATH%[/\\]*}" writers=" " sid agent c m fb
  writers+="$(judge::transcript_class "$TPATH") "
  while IFS= read -r sid && IFS= read -r agent; do
    [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || continue
    writers+="$(judge::transcript_class "$tdir/$sid.jsonl") "
    [[ "$agent" =~ ^[A-Za-z0-9_-]+$ ]] && writers+="$(judge::transcript_class "$tdir/$sid/subagents/agent-$agent.jsonl") "
  done < <(jq -r '.[] | (.sid, .agent) | tostring | gsub("[\r\n]"; "")' <<<"$1")
  m="${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_MODEL:-sonnet}"
  [[ "$m" =~ ^(fable|opus|sonnet|haiku)$ ]] || m=sonnet
  fb="${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_FALLBACK_MODEL:-opus}"
  [[ "$fb" =~ ^(fable|opus|sonnet)$ ]] || fb=opus
  EFFORT="${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_EFFORT:-medium}"
  [[ "$EFFORT" =~ ^(low|medium|high|xhigh|max)$ ]] || EFFORT=medium
  for c in "$m" "$fb" opus sonnet; do
    if [[ "$writers" != *" $c "* ]]; then
      MODEL="$c"
      return 0
    fi
  done
  MODEL=""
  return 1
}

judge::harvest() {
  local raw="$1" dir="${1%/*}" kh json
  JUDGE_MUTED=0
  [[ -f "$raw.keys" ]] || return 1
  [[ -n "${2:-}" || -s "$raw" ]] || return 1
  out="$(jq -rn --slurpfile meta "$raw.keys" --rawfile raw "$raw" --arg forced "${2:-}" --arg fkind "${3:-}" '
    $meta[0] as $m
    | (if $forced != "" then {reason: $forced, kind: $fkind}
       else ($raw | fromjson? // {}) as $e
       | if ($e | type) != "object" then null
         elif $e.subtype == "error_max_budget_usd" then {reason: "the judge hit its $\($m.budget) malfunction budget", kind: "budget"}
         elif ($e.result | type) == "string" then
           ($e.result | (index("{") // -1) as $i | (rindex("}") // -1) as $j
             | if $i < 0 or $j < $i then null else .[$i:$j + 1] | fromjson? end) as $v
           | if ($v | type) == "object" then {verdicts: [$v.verdicts[]? | objects],
               denied: (($e.permission_denials | arrays | length > 0) // false)} else null end
         else null end end) as $r
    | if $r == null then empty else
      [$m.keys[] as $k
       | (if $r.reason then {verdict: "UNKNOWN", reason: $r.reason}
          else [$r.verdicts[] | select(.name == $k.name and ((.ordinal // $k.ordinal) | tostring) == ($k.ordinal | tostring))][0] end)
       | select(. != null) | {k: $k, v: .}] as $kv
      | if $r.denied == true and all($kv[]; .v.verdict | IN("FLAG", "PASS") | not) then "! muted" else
      $kv[] | .k as $k | .v as $v
      | ($v.verdict | IN("FLAG", "PASS", "UNKNOWN")) as $ok
      | (if $ok then $v.verdict else "UNKNOWN" end) as $verdict
      | "\($k.kh) \({file: $m.file, repo: $m.repo, name: $k.name, ordinal: $k.ordinal, start: $k.start, end: $k.end,
          verdict: $verdict,
          evidence: [$v.evidence[]? | strings], source: ($v.source // "" | tostring), diff: ($v.diff // "" | tostring),
          reason: (if $ok then ($v.reason // "" | tostring) else "the judge returned no valid verdict" end),
          model: $m.model, effort: $m.effort, blob: ($m.blob // ""), reuse_key: ($k.rk // ""), judged_at: (now | todate)}
        + (if $verdict != "UNKNOWN" then {}
           elif $r.reason then {reason_kind: $r.kind, origin: ""}
           elif $ok then {reason_kind: "judge", origin: "UNKNOWN"}
           else {reason_kind: "invalid", origin: ""} end) | tojson)"
      end end' 2>/dev/null)" || return 1
  [[ -n "$out" ]] || return 1
  while read -r kh json; do
    [[ "$kh" == '!' ]] && JUDGE_MUTED=1 && continue
    printf '%s\n' "$json" >"$dir/.$kh.tmp" && mv -f "$dir/.$kh.tmp" "$dir/$kh.json"
  done <<<"$out"
}

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

judge::reuse() {
  local file="$1" repo="$2" dir="$3" kh o r s e name rk src d f files=()
  local -A have=()
  RKEYS="" KEYS_LEFT=""
  if [[ "${TEST_JUDGE_REUSE:-1}" != 0 ]]; then
    for d in "${SESSIONS[@]}"; do
      for f in "$DATA/verdicts/$PKEY/$d"/*.json; do [[ -f "$f" ]] && files+=("$f"); done
    done
    if ((${#files[@]})); then
      while IFS=$'\t' read -r rk f; do
        [[ -n "$rk" && -z "${have[$rk]+x}" ]] && have[$rk]="$f"
      done < <(jq -Rr 'fromjson? | objects | select(.verdict == "PASS" and (.reuse_key // "") != "")
        | "\(.reuse_key)\t\(input_filename)"' "${files[@]}" 2>/dev/null)
    fi
  fi
  while read -r kh o r name; do
    [[ -n "$kh" ]] || continue
    judge::rkey "$file" "$o" "$r" "$name" "$repo"
    rk="$RK"
    RKEYS+="$kh $rk"$'\n'
    src="${rk:+${have[$rk]:-}}"
    if [[ -n "$src" ]] && judge::copy_verdict "$src" "$dir" "$kh" "$file" "$repo" "$o" "$r" "$name"; then
      judge::log "reused: $file: $name: the PASS verdict of ${src##*/}"
      continue
    fi
    KEYS_LEFT+="$kh $o $r $name"$'\n'
  done <<<"$4"
}

judge::rkey() {
  local file="$1" o="$2" r="$3" name="$4" repo="$5" s e line body="" named=0 text=() words=()
  RK=""
  [[ "$o" =~ ^[1-9][0-9]*$ && "$r" =~ ^([0-9]+)-([0-9]+)$ && -f "$file" ]] || return 0
  s="${BASH_REMATCH[1]}" e="${BASH_REMATCH[2]}"
  ((s >= 1 && e >= s)) || return 0
  if [[ -z "${JUDGE_PSHA:-}" ]]; then
    JUDGE_PSHA="$(judge::sha "$HOOK_DIR/test-judge-prompt.md" 2>/dev/null)" && JUDGE_PSHA="${JUDGE_PSHA#\\}" && JUDGE_PSHA="${JUDGE_PSHA%% *}"
  fi
  mapfile -t text <"$file" 2>/dev/null
  ((${#text[@]} >= e)) || return 0
  for line in "${text[@]:s-1:e-s+1}"; do
    if ((named == 0)) && [[ "$line" == *"$name"* ]]; then
      line="${line/"$name"/}"
      named=1
    fi
    read -r -a words <<<"${line%$'\r'}"
    body+="${words[*]-}"$'\n'
  done
  RK="$({
    printf '%s\n%s\n%s\n%s\n%s\n' "$body" "$MODEL" "$EFFORT" "${JUDGE_PSHA:-}" "$repo"
    printf '%s\n' "${text[@]:0:s-1}" "${text[@]:e}"
  } | judge::sha -)"
  RK="${RK#\\}" && RK="${RK:0:32}"
}

judge::copy_verdict() {
  local src="$1" dir="$2" kh="$3" s="${7%-*}" e="${7#*-}"
  jq -c --arg f "$4" --arg r "$5" --arg n "$8" --argjson o "$6" --argjson s "$s" --argjson e "$e" \
    --arg k "${9:-${src##*/}}" '. + {file: $f, repo: $r, name: $n, ordinal: $o, start: $s, end: $e, blob: "",
      reused_from: {file: .file, name: .name, ordinal: .ordinal, start: .start, key: ($k | rtrimstr(".json"))},
      reused_at: (now | todate)} | if .verdict == "FLAG" then .diff = "" else . end' \
    "$src" >"$dir/.$kh.tmp" 2>/dev/null && mv -f -- "$dir/.$kh.tmp" "$dir/$kh.json" && return 0
  rm -f -- "$dir/.$kh.tmp"
  return 1
}

judge::keep_unusable() {
  local raw="$1" kept out err
  judge::now
  kept="${raw%/*}/unusable-$NOW-$BASHPID.txt"
  {
    cat -- "$raw" 2>/dev/null
    printf '\n--- stderr ---\n'
    cat -- "$raw.err" 2>/dev/null
  } >"$kept" 2>/dev/null || [[ -s "$kept" ]] || kept=""
  out="$(jq -rs '[.[] | objects | .result? | strings] | join(" ") | select(. != "")' "$raw" 2>/dev/null)" ||
    out=""
  [[ -n "$out" ]] || out="$(head -c 2000 -- "$raw" 2>/dev/null)"
  err="$(head -c 2000 -- "$raw.err" 2>/dev/null)"
  out="$(printf '%s' "$out" | tr -s '\r\n\t ' ' ' | tr -d '\000-\037\177')"
  err="$(printf '%s' "$err" | tr -s '\r\n\t ' ' ' | tr -d '\000-\037\177')"
  out="${out:0:400}" err="${err:0:200}"
  judge::log "unusable judge output on $2${kept:+, kept in $kept}: result: ${out:-(none)}${err:+; stderr: $err}"
}

judge::section1() {
  awk '/^## 1\. /{f=1} f&&/^## /&&!/^## 1\. /{exit} f' "$HOOK_DIR/../skills/test-value/SKILL.md" 2>/dev/null
}

judge::run() {
  local info="$1" keys="$2" t="$3" hint="$4" res="${5:-}" dir file repo owner writers n budget raw sys prompt rc kh here
  local rule denied blob kind
  testing::fields "$info" .file .repo .owner '.writers | tojson' || {
    judge::release_run "$res"
    return 0
  }
  file="${FIELDS[0]}" repo="${FIELDS[1]}" owner="${FIELDS[2]}" writers="${FIELDS[3]}"
  dir="$DATA/verdicts/$PKEY/${owner:-$SID}"
  judge::file_repo "$file"
  [[ -z "$repo" || "$repo" == "$FREPO" ]] || judge::log "repository: $file is in ${FREPO:-no repository}, not the recorded $repo"
  repo="$FREPO"
  if [[ -n "$FREPO_OUT" ]]; then
    rc="the test file is outside the repository git names for it, $FREPO_OUT"
    judge::log "malfunction: $rc: $file"
    while read -r kh _; do [[ -z "$kh" ]] || judge::fail "$kh" "$rc"; done <<<"$keys"
    judge::release_run "$res"
    return 0
  fi
  mkdir -p "$dir"
  raw="$dir/.run-$BASHPID-$RANDOM"
  judge::pick "$writers"
  RKEYS=""
  if [[ -n "$MODEL" && -n "$repo" ]]; then
    judge::reuse "$file" "$repo" "$dir" "$keys"
    keys="$KEYS_LEFT"
    if [[ -z "$keys" ]]; then
      judge::release_run "$res"
      return 0
    fi
  fi
  n=0
  while read -r kh _; do [[ -z "$kh" ]] || n=$((n + 1)); done <<<"$keys"
  budget="$((((n + 9) / 10) * 90))" && budget="$((budget / 100)).$(printf '%02d' $((budget % 100)))"
  blob=""
  if [[ -n "$repo" ]]; then
    blob="$(unset GIT_DIR GIT_WORK_TREE && git -C "$repo" hash-object --no-filters -- "$file" 2>/dev/null)"
    blob="${blob//$'\r'/}"
    if [[ ! "$blob" =~ ^[0-9a-f]{40,64}$ ]]; then
      blob=""
    elif [[ -f "$dir/blob-$blob" ]]; then
      touch -- "$dir/blob-$blob" 2>/dev/null
    else
      cp -- "$file" "$dir/.blob-$blob.$BASHPID" 2>/dev/null && mv -f -- "$dir/.blob-$blob.$BASHPID" "$dir/blob-$blob" || blob=""
    fi
  fi
  jq -Rn --arg file "$file" --arg repo "$repo" --arg model "$MODEL" --arg effort "$EFFORT" --arg budget "$budget" --arg blob "$blob" \
    --arg rks "$RKEYS" '
    ($rks | split("\n") | map(select(. != "") | split(" ") | {key: .[0], value: (.[1] // "")}) | from_entries) as $rk
    | {file: $file, repo: $repo, model: $model, effort: $effort, budget: $budget, blob: $blob,
     keys: [inputs | select(. != "") | capture("^(?<kh>[^ ]+) (?<ordinal>[0-9]+) (?<start>[0-9]+)-(?<end>[0-9]+) (?<name>.*)$")
       | .ordinal |= tonumber | .start |= tonumber | .end |= tonumber | .rk = ($rk[.kh] // "")]}' <<<"$keys" >"$raw.keys"
  rc="" kind=""
  [[ -n "$MODEL" ]] || rc="no judge class differs from the writers" kind=no-judge-class
  [[ -n "$repo" ]] || rc="no repository: the judge reads only inside a git repository, and this test file is in none" kind=no-repository
  if [[ -n "$rc" ]]; then
    : >"$raw"
    judge::harvest "$raw" "$rc" "$kind"
    rm -f "$raw" "$raw.keys"
    judge::release_run "$res"
    return 0
  fi
  sys="$(cat "$HOOK_DIR/test-judge-prompt.md" 2>/dev/null)"$'\n\n'"$(judge::section1)"
  prompt="Judge these test blocks in $file (block <ordinal> <start>-<end> <name>):"$'\n'"$(sed -n 's/^[^ ]* /block /p' <<<"$keys")"
  [[ -z "$hint" ]] || prompt+=$'\n'"Changed lines in this file, a hint to where the new tests are: $hint"
  if [[ "$sys" != *"## 1. "* ]]; then
    rc="the judge prompt or test-value section 1 is missing"
  else
    here="$PWD"
    cd "$repo" || {
      judge::release_run "$res"
      return 0
    }
    res=""
    judge::read_rule rule "$repo"
    testing::run_bounded "$t" "$raw" "$raw.err" env TEST_JUDGE_ACTIVE=1 "${TEST_JUDGE_CMD:-claude}" -p --model "$MODEL" \
      --system-prompt "$sys" --tools Read,Grep,Glob --allowedTools "$rule" \
      --settings '{"disableAllHooks":true}' --setting-sources "" --strict-mcp-config \
      --disable-slash-commands --effort "$EFFORT" --max-budget-usd "$budget" \
      --no-session-persistence --output-format json "$prompt" </dev/null
    rc=$SCAN_RC
    cd "$here" || :
    grep -q '"error_max_budget_usd"' "$raw" 2>/dev/null && judge::log "malfunction: judge run on $file hit its \$$budget budget"
    denied="$(jq -r 'objects | .permission_denials | arrays | select(length > 0)
      | [.[] | (objects | .tool_name | strings) // "a tool"] | unique | join(", ")' "$raw" 2>/dev/null)"
    if ((rc > 128)); then
      rc="judge timed out after $t s"
    else
      if ! judge::harvest "$raw"; then
        rc="judge exited $rc with no usable result"
        [[ -z "$denied" ]] || rc+="; it was denied $denied"
        judge::keep_unusable "$raw" "$file"
      elif ((JUDGE_MUTED)); then
        rc="the judge was denied ${denied:-a tool} and gave no test a FLAG or PASS, so its UNKNOWN verdicts are a malfunction, not a judgment"
        judge::log "malfunction: judge run on $file: $rc"
      elif [[ -n "$denied" ]]; then
        judge::log "judge run on $file was denied $denied; it gave a FLAG or PASS, so its UNKNOWN verdicts stand"
      fi
    fi
  fi
  while read -r kh _; do
    [[ -n "$kh" && ! -f "$dir/$kh.json" ]] && judge::fail "$kh" "$rc"
  done <<<"$keys"
  rm -f "$raw" "$raw.keys" "$raw.err"
  judge::release_run "$res"
}

judge::quoted_in_repo() {
  local dir="$1" q
  shift
  for q in "$@"; do
    [[ -n "$dir" && "$q" != *$'\n'* ]] || return 1
    git -C "$dir" grep --untracked -F -q -e "$q" -- . 2>/dev/null || return 1
  done
}

judge::relay_reset() {
  RELAY="" RELAY_REPOS=() RELAY_N=0 RELAY_F=0 RELAY_P=0 RELAY_U=0 RELAY_UF=0
}
judge::relay_reset

judge::comment_only() {
  local style line body rest hunk=0 open=0 comment new
  case "${1,,}" in
  *.js | *.jsx | *.ts | *.tsx | *.mjs | *.cjs | *.mts | *.cts | *.cs | *.go) style=slash ;;
  *.sh | *.bash | *.bats | *.py) style=pound ;;
  *.ps1 | *.psm1) style=powershell ;;
  *) return 1 ;;
  esac
  while IFS= read -r line; do
    case "$line" in
    'diff --git '*) hunk=0 open=0 ;;
    '@@'*) hunk=1 open=0 ;;
    [+\ -]*)
      ((hunk)) || continue
      body="${line:1}" && body="${body//$'\r'/}"
      body="${body#"${body%%[![:space:]]*}"}"
      comment=0 new=1
      [[ "${line:0:1}" == - ]] && new=0
      if [[ -z "$body" ]]; then
        comment=1
      elif [[ "$style" == slash ]]; then
        if ((open)) && [[ "$body" == *\*/* ]]; then
          rest="${body#*\*/}"
          [[ -z "${rest//[[:space:]]/}" ]] && comment=1
          ((new)) && open=0
        elif ((open)); then
          [[ "$body" =~ ^\*([[:space:]]|$) ]] && comment=1
        elif [[ "$body" == //* ]]; then
          comment=1
        elif [[ "$body" == /\** ]]; then
          rest="${body#/\*}"
          if [[ "$rest" == *\*/* ]]; then
            rest="${rest#*\*/}"
            [[ -z "${rest//[[:space:]]/}" ]] && comment=1
          else
            comment=1
            ((new)) && open=1
          fi
        fi
      elif [[ "$style" == powershell ]]; then
        if ((open)) && [[ "$body" == *'#>'* ]]; then
          rest="${body#*'#>'}"
          [[ -z "${rest//[[:space:]]/}" ]] && comment=1
          ((new)) && open=0
        elif ((open)); then
          ((new)) && comment=1
        elif [[ "$body" == '<#'* ]]; then
          rest="${body#'<#'}"
          if [[ "$rest" == *'#>'* ]]; then
            rest="${rest#*'#>'}"
            [[ -z "${rest//[[:space:]]/}" ]] && comment=1
          else
            comment=1
            ((new)) && open=1
          fi
        elif [[ "$body" == \#* ]]; then
          comment=1
        fi
      else
        [[ "$body" == \#* ]] && comment=1
      fi
      [[ "${line:0:1}" == " " ]] || ((comment)) || return 1
      ;;
    *) ;;
    esac
  done <<<"$2"
  return 0
}

judge::grounded() {
  local repo="$1" snap="$2" q
  shift 2
  GROUND=""
  for q in "$@"; do
    judge::quoted_in_repo "$repo" "$q" && continue
    if [[ -n "$snap" && -f "$snap" && "$q" != *$'\n'* ]] && grep -qF -e "$q" -- "$snap" 2>/dev/null; then
      GROUND=stale
    else
      GROUND=ungrounded
      return 0
    fi
  done
}

judge::validate() {
  local v="$1" file="${2:-}" json="" repo verdict ev diff why="" kind="" origin blob reused snap="" p n=0 known=0 text=(--arg text "")
  IFS= read -r -d '' json <"$v"
  json="${json%%$'\n'*}"
  if [[ -z "$file" ]]; then
    testing::fields "$json" .file || return 0
    file="${FIELDS[0]}"
  fi
  [[ -f "$file" ]] && text=(--rawfile text "$file")
  FIELDS=()
  while IFS= read -r -d '' p; do FIELDS+=("$p"); done < <(jq -j "${text[@]}" '
    def s: tostring | gsub("\u0000"; "");
    ((.evidence // []) | map(s | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) | map(select(. != ""))) as $e
    | (.repo // "" | s), "\u0000", (.verdict // "" | s), "\u0000",
      (if ($e | length) == 0 then "none" else "some" end), "\u0000", (.diff // "" | s), "\u0000",
      (.origin // .verdict // "" | s), "\u0000", (.blob // "" | s), "\u0000",
      (if (.reused_from | type) == "object" then "reused" else "" end), "\u0000",
      ($e[] | select(. as $q | $text | contains($q) | not) | (., "\u0000"))' <<<"$json" 2>/dev/null)
  ((${#FIELDS[@]} >= 7)) || return 0
  repo="${FIELDS[0]}" verdict="${FIELDS[1]}" ev="${FIELDS[2]}" diff="${FIELDS[3]}" origin="${FIELDS[4]}" blob="${FIELDS[5]}"
  reused="${FIELDS[6]}"
  [[ -n "$repo" && -d "$repo" ]] || repo=""
  ((JUDGE_WIN)) && repo="${repo//\\//}"
  [[ "$blob" =~ ^[0-9a-f]{40,64}$ ]] && snap="${v%/*}/blob-$blob"
  GROUND=""
  [[ -f "$file" ]] && ((${#FIELDS[@]} > 7)) && judge::grounded "$repo" "$snap" "${FIELDS[@]:7}"
  if [[ ! -f "$file" ]]; then
    why="the test file no longer exists" kind=file-gone
  elif [[ "$verdict" != UNKNOWN && "$ev" == none ]]; then
    why="the verdict quotes no evidence" kind=no-evidence
  elif [[ "$GROUND" == ungrounded ]]; then
    why="a quoted line is in no file of the repository" kind=ungrounded
  elif [[ "$GROUND" == stale ]]; then
    why="the test file changed after the judge read it: a quoted line is no longer in it" kind=stale
  elif [[ "$verdict" == FLAG && -z "$diff" && "$reused" == reused ]]; then
    :
  elif [[ "$verdict" == FLAG && -z "$diff" ]]; then
    why="the FLAG proposes no diff" kind=no-diff
  elif [[ "$verdict" == FLAG && -z "$repo" ]]; then
    why="no repository to check the proposed diff against" kind=diff-no-repository
  elif [[ "$verdict" == FLAG ]]; then
    while IFS= read -r -d '' p; do
      [[ "$p" == ok ]] && n=1 && continue
      p="${p#*$'\t'}" && p="${p#*$'\t'}"
      judge::same_path "$repo/$p" "$file" || why="the proposed diff touches another file" kind=diff-other-file
    done < <(git -C "$repo" apply --check --numstat -z 2>/dev/null <<<"$diff" && printf 'ok\0')
    ((n)) || why="the proposed diff does not apply" kind=diff-not-apply
    [[ -z "$why" ]] && judge::comment_only "$file" "$diff" &&
      why="the proposed diff changes only comments or blank lines" kind=comment-only
  fi
  if [[ -n "$why" ]]; then
    verdict=UNKNOWN
    json="$(jq -c --arg why "$why" --arg kind "$kind" --arg origin "$origin" '.verdict = "UNKNOWN" | .reason = $why
      | .reason_kind = $kind | .origin = $origin | .evidence = [] | .source = "" | .diff = ""' <<<"$json")" || return 0
  fi
  RELAY+="$json"$'\n'
  RELAY_N=$((RELAY_N + 1))
  case "$verdict" in
  FLAG) RELAY_F=$((RELAY_F + 1)) ;;
  PASS) RELAY_P=$((RELAY_P + 1)) ;;
  *)
    RELAY_U=$((RELAY_U + 1))
    [[ "$origin" == FLAG ]] && RELAY_UF=$((RELAY_UF + 1))
    ;;
  esac
  for p in ${RELAY_REPOS[@]+"${RELAY_REPOS[@]}"}; do [[ "$p" == "${FIELDS[0]}" ]] && known=1 && break; done
  ((known)) || RELAY_REPOS+=("${FIELDS[0]}")
}

judge::slug() {
  local s="${1,,}"
  s="${s//[!a-z0-9-]/-}"
  while [[ "$s" == *--* ]]; do s="${s//--/-}"; done
  s="${s#-}" && s="${s%-}"
  if ((${#s} > 40)); then
    s="${s:0:40}"
    [[ "$s" == *-* ]] && s="${s%-*}"
  fi
  case "$s" in
  con | prn | aux | nul | com[1-9] | lpt[1-9]) s+=-x ;;
  *) ;;
  esac
  SLUG="${s:-detached}"
}

judge::findings_dir() {
  local repo="$1" branch="$2" mem target
  FDIR="$DATA/findings"
  if [[ -n "$branch" ]]; then
    mem="$repo/.work"
    judge::slug "$branch"
    target="$mem/reviews/$SLUG"
    if judge::inside "$repo" "$mem" && judge::inside "$repo" "$target" &&
      { [[ -d "$target" ]] || mkdir -p "$target"; } &&
      judge::inside "$repo" "$mem" && judge::inside "$repo" "$target" && judge::self_ignore "$mem"; then
      FDIR="$target"
    fi
  fi
}

judge::inside() {
  local top r p="$2"
  while [[ ! -e "$p" && ! -L "$p" && "$p" == */* ]]; do p="${p%/*}"; done
  judge::phys top "$1" && judge::phys r "$p" || return 1
  [[ "$r" == "$top/"?* ]] || [[ "$p" != "$2" && "$r" == "$top" ]]
}

judge::phys() {
  local here="$PWD" rc=0
  cd -P -- "$2" 2>/dev/null || return 1
  printf -v "$1" '%s' "$PWD"
  cd -- "$here" 2>/dev/null || rc=1
  return "$rc"
}

judge::excl() {
  [[ -e "$1" || -L "$1" ]] && return 1
  local rc
  set -o noclobber
  { printf '%s\n' "$2" >"$1"; } 2>/dev/null
  rc=$?
  set +o noclobber
  return "$rc"
}

judge::self_ignore() {
  [[ -L "$1/.gitignore" ]] && return 1
  [[ -f "$1/.gitignore" ]] && return 0
  judge::excl "$1/.gitignore" '*'
}

judge::findings() {
  local all="$RELAY" repo dir ts path i branch content tmp p base="${CLAUDE_PROJECT_DIR:-${pcwd:-}}"
  FINDINGS="" FINDINGS_SHOWN=""
  TZ=UTC0 printf -v ts '%(%Y%m%dT%H%M%SZ)T' -1
  for repo in ${RELAY_REPOS[@]+"${RELAY_REPOS[@]}"}; do
    branch=""
    [[ -z "$repo" || ! -d "$repo" ]] || branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
    judge::findings_dir "$repo" "$branch"
    content="$(jq -rs --arg win "$JUDGE_WIN" --arg repo "$repo" --arg branch "$branch" --arg rule "$JUDGE_RULE" '
      def cap($n): tostring | if length > $n then .[:$n] + " [cut at \($n) characters]" else . end;
      def esc: tostring | gsub("\\|"; "\\|") | gsub("[\r\n]+"; " ") | cap(500);
      def slash: if $win == "1" then gsub("\\\\"; "/") else . end;
      def norm: slash | if $win == "1" then ascii_downcase | sub("^/(?<d>[a-z])/"; "\(.d):/") else . end;
      def rel: (.file | slash) as $f
        | if ($f | norm | startswith(($repo | norm) + "/")) then $f[($repo | length) + 1:] else $f end;
      def tname: "\(.name)\(if .ordinal > 1 then " #\(.ordinal)" else "" end)";
      # A frontmatter value is quoted exactly when its plain form would
      # misparse, the predicate testing:audit and the other findings producers
      # share, so an ordinary branch stays a plain scalar the consumer matches.
      def yscalar:
        if test("^[-?:,\\[\\]{}#&*!|>%@`\"\u0027]") or test(": | #") or . == "" or test("[ \t]$")
          or test("^(true|True|TRUE|false|False|FALSE|yes|Yes|YES|no|No|NO|on|On|ON|off|Off|OFF|null|Null|NULL|~)$")
          or test("^[+-]?[0-9]+$") or test("^[+-]?[0-9]*\\.[0-9]+([eE][+-]?[0-9]+)?$")
          or test("^[0-9]{4}-[0-9]{2}-[0-9]{2}") or test("^0[xXoObB][0-9a-fA-F_]+$")
        then "\"" + (gsub("\\\\"; "\\\\") | gsub("\""; "\\\"")) + "\""
        else . end;
      map(select((.repo // "") == $repo)) as $v
      | ($v | map(select(.verdict == "FLAG"))) as $f
      | "---\ntype: review-findings\ndate: \(now | todate)\nbranch: \(if $branch == "" then "none" else ($branch | yscalar) end)\n---\n\n## Findings\n\n"
      + "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |\n|------|------|------------|----------|------------|---------|--------|\n"
      + ([$f | to_entries[] | "| \(.key + 1) | SUGGESTION |  | \(.value | rel | esc):\(.value.start | esc) | testing:test-judge | \($rule): test \(.value | tname | esc) takes its expected value from the implementation: \(.value.source | esc) (threshold: a FLAG verdict, every quote found in the test file or its repository, its diff applies to the test file alone) | Replace the expected value with one from an independent source; the proposed diff (not applied) is under Verdicts, \(.value | rel | esc) \(.value | tname | esc) |\n"] | join(""))
      + "\n## Surfaces\n\nRan: [testing:test-judge — \($v | length) test block(s) judged; findings: \($rule) \($f | length); declined (judged PASS): \($rule) \($v | map(select(.verdict == "PASS")) | length); UNKNOWN: \($v | map(select(.verdict == "UNKNOWN")) | length)]. Returned no result: [none].\n"
      + "\n## Verdicts\n\nEach verdict below is the judge'"'"'s output, quoted as data. Nothing here has been applied.\n"
      + ([$v[] | "\n### \(.verdict | esc) \(rel | esc) \(tname | esc) (lines \(.start | esc)-\(.end | esc))\n\n"
        + (if (.reason // "") != "" then "Reason: \(.reason | esc)\n\n" else "" end)
        + (if .verdict == "UNKNOWN" and ((.origin // "") | IN("FLAG", "PASS")) then "The judge said \(.origin); validation made it UNKNOWN.\n\n" else "" end)
        + "Judge: \(.model | esc) at \(.effort | esc) effort.\n\n"
        + (if (.source // "") != "" then "Where the expected value came from: \(.source | esc)\n\n" else "" end)
        + ([(.evidence // [])[:20][] | "> " + esc + "\n"] | join(""))
        + (if .verdict == "FLAG" and (.diff // "") != "" then
            (.diff | cap(20000) | rtrimstr("\n")) as $d
            | ("`" * ([4, ([$d | scan("`+") | length] | max // 0) + 1] | max)) as $fence
            | "\nProposed diff, not applied:\n\n\($fence)diff\n\($d)\n\($fence)\n" else "" end)
        + (if .verdict == "FLAG" and (.diff // "") == "" and (.reused_from | type) == "object" then
            "\nThis test has the same body as \(.reused_from | rel | esc) \(.reused_from | tname | esc), judged in the same run; the proposed diff is under that test'"'"'s verdict and edits that file only.\n"
          else "" end)] | join(""))
      ' <<<"$all" 2>/dev/null)" || continue
    path=""
    for dir in "$FDIR" "$DATA/findings"; do
      [[ -d "$dir" ]] || mkdir -p "$dir" || continue
      [[ "$dir" == "$DATA/findings" ]] || judge::inside "$repo" "$dir" || continue
      tmp="$dir/.test-judge.$BASHPID.$RANDOM.tmp"
      judge::excl "$tmp" "$content" || continue
      if [[ "$dir" == "$DATA/findings" ]] || judge::inside "$repo" "$dir"; then
        for ((i = 1; i <= 20; i++)); do
          p="$dir/$ts-test-judge.md"
          ((i == 1)) || p="$dir/$ts-test-judge-$i.md"
          [[ -e "$p" || -L "$p" ]] && continue
          mv -n -- "$tmp" "$p" 2>/dev/null
          [[ -e "$tmp" ]] || {
            path="$p"
            break
          }
        done
      fi
      [[ -e "$tmp" ]] && rm -f -- "$tmp"
      [[ -n "$path" ]] && break
    done
    [[ -n "$path" ]] || continue
    FINDINGS+="${FINDINGS:+, }$path"
    [[ -n "$base" && "$path" == "${base%/}/"* ]] && path="${path#"${base%/}"/}"
    FINDINGS_SHOWN+="${FINDINGS_SHOWN:+, }$path"
  done
}

judge::mark_relayed() {
  local m dirs=()
  for m in "$@"; do dirs+=("$DATA/relayed/$PKEY/${m%/*}"); done
  ((${#dirs[@]})) && mkdir -p "${dirs[@]}" || return 0
  for m in "$@"; do : >"$DATA/relayed/$PKEY/$m"; done
}

judge::counts() {
  local s=s
  ((RELAY_N == 1)) && s=""
  COUNTS="$RELAY_N test$s ($RELAY_F FLAG, $RELAY_P PASS, $RELAY_U UNKNOWN)"
}
