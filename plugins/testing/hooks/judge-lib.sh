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

# judge::num <var> <value> <default>: set var to the value when it is a plain
# number, else to the default, so no setting is evaluated as shell arithmetic.
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
# Git Bash: a pid from another process tree cannot be probed, so markers go
# stale by age only.
case "${OSTYPE:-}" in msys* | cygwin*) JUDGE_AGE_ONLY=1 ;; *) JUDGE_AGE_ONLY=0 ;; esac
SCANNER="${TEST_SCAN_SCANNER:-$HOOK_DIR/../skills/audit/scripts/cant-fail-scan.sh}"

# Under Git Bash and Cygwin one file can be named C:\x (a payload), C:/x (git)
# or /c/x (MSYS), on a file system that ignores case.
case "${TESTING_OSTYPE:-${OSTYPE:-}}" in msys* | cygwin*) JUDGE_WIN=1 ;; *) JUDGE_WIN=0 ;; esac

# judge::same_path <a> <b>: true when the two paths name one file.
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

# judge::read_rule <var> <dir>: set var to the Read allow rule for everything
# under the directory. A rule path is absolute only with a leading `//`; one
# `/` anchors at the primary working directory for a CLI flag, and on Windows
# C:\a is matched as /c/a, so the rule is Read(//c/a/**). A Read rule also
# covers Grep and Glob; path rules for those two are never consulted. The
# rule is a gitignore pattern, so each \ * ? [ ] in the path is escaped with
# a backslash and the rule names that one directory, as the rules Claude Code
# writes itself are escaped.
# https://code.claude.com/docs/en/permissions#read-and-edit,
# https://git-scm.com/docs/gitignore#_pattern_format and
# https://code.claude.com/docs/en/tools-reference (as of 2026-10-04; recheck
# when the anchor table, the escaping of path rules or the tools a Read rule
# covers changes).
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

# judge::file_repo <file>: set FREPO to the git toplevel of the file's own
# directory, never the hook's: a recorded repository can be the hook's
# working directory's when the recorder misread a Windows path. Under Git Bash
# a payload path may use backslashes, so the directory is taken at either
# separator; a path with no separator has no directory to resolve, and is
# never read as the working directory. FREPO_OUT is the toplevel when git
# names one that does not hold the directory (core.worktree set elsewhere);
# FREPO is then empty, as it is for a file in no repository. Cached per file
# for the process.
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
  local d="$DATA/sessions/$PKEY/$1" last='[.[] | objects | .written_at? | strings | fromdate?] | max'
  compgen -G "$d/*.json" >/dev/null || return 1
  jq -en "[inputs] | $last" "$d"/*.json 2>/dev/null ||
    judge::records_json "$d"/*.json | jq -e "$last" 2>/dev/null
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
# IFILES holds each info's file path, the same index. One jq reads every
# record; only when a malformed record fails it does each file get its own.
judge::load() {
  local s f files=() out i group='map(select(.file | type == "string")) | group_by(.file)[] | {
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
  out="$(jq -rn "[inputs | objects | . + {sid: (input_filename | split(\"/\") | .[-2])}] | $group" "${files[@]}" 2>/dev/null)" ||
    out="$(judge::records_json "${files[@]}" | jq -r "$group" 2>/dev/null)"
  mapfile -t f <<<"$out"
  for ((i = 0; i + 1 < ${#f[@]}; i += 2)); do
    IFILES+=("${f[i]}")
    INFOS+=("${f[i + 1]}")
  done
}

# judge::derive <info>: set KEYS to one line per in-doubt block of the file as
# it is now, "<key-hash> <ordinal> <start>-<end> <name>", and HINT to the
# changed-line hint for a whole-file key. A block is in doubt when a write
# created or changed it, when a write's blocks are unknown (all blocks), or
# when it holds or sits under a cant-fail-ok: marker and the file's count rose
# above the first recorded one (a created file starts from 0). A file the scanner cannot list, or whose lexer
# lost sync, is one whole-file key. A missing file is logged and skipped.
#
# The result is cached under derive/, keyed by the sha256 of the info, this
# hook directory (so a plugin update re-derives), the file's current content
# and each testing config file (docs/conventions/testing.yaml and .md, and the
# .claude/testing.yaml layers): block identity is name and ordinal in the
# current text, so the same inputs give the same keys and the scanner runs
# again only when one of them changed. A scan that failed is never cached.
judge::derive() {
  local file whole base_ok names lines tmpd rc n=0 re line cur marks=() b s e o name keep m text=() i b_start b_end
  local root cfg cfgs=() key="" h cache c=()
  KEYS="" HINT=""
  testing::fields "$1" .file .whole .base_ok '.lines | join(",")' '.names | join("\n")' || return 0
  file="${FIELDS[0]}" whole="${FIELDS[1]}" base_ok="${FIELDS[2]:-0}" lines="${FIELDS[3]}"
  names=$'\n'"${FIELDS[4]}"$'\n'
  if [[ ! -f "$file" ]]; then
    judge::log "skipped: $file no longer exists"
    return 0
  fi
  judge::file_repo "$file"
  root="${FREPO:-${CLAUDE_PROJECT_DIR:-}}"
  for cfg in "${HOME:-}/.claude/testing.yaml" "$root/docs/conventions/testing.yaml" "$root/docs/conventions/testing.md" "$root/.claude/testing.yaml" "$root/.claude/testing.local.yaml"; do
    [[ -f "$cfg" ]] && cfgs+=("$cfg")
  done
  # sha256sum prefixes a line with \ when the file name holds a backslash.
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
# judge::spent <key-hash>: true after 2 failed attempts ("judge not run").
judge::spent() {
  local a=()
  [[ -f "$DATA/attempts/$1" ]] && mapfile -t a <"$DATA/attempts/$1"
  ((${#a[@]} >= 2))
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

# judge::wait_lock <key-hash>: wait while a live holder keeps the key's lock,
# until it is released or goes stale (at most JUDGE_STALE seconds).
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
      f=""
      { read -r _ && IFS= read -r f; } <"$p"
      [[ "$f" == "$1" ]] && ! judge::stale "$p" "$((JUDGE_DEBOUNCE + JUDGE_STALE + 60))" && return 0
    done
  done
  [[ -e "$DATA/locks/$2" ]] && ! judge::stale "$DATA/locks/$2" "$JUDGE_STALE"
}

# judge::reserve_run: reserve one judge run for the session and set RUNRES to
# its marker, or fail when the optional test_judge_session_runs limit is
# reached. Under a limit the marker is runs/<pkey>/<sid>/<n>, the first free
# n from 1 to the limit, created exclusively, so jobs that reach the check
# together cannot all take the last run. A reservation is kept when the
# judge starts and released (judge::release_run) when it does not; a job
# killed in between keeps it, which errs toward spending less.
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
  while IFS= read -r sid && IFS= read -r agent; do
    # Ids become path parts, so only the shape session and agent ids have.
    [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || continue
    writers+="$(judge::transcript_class "$tdir/$sid.jsonl") "
    [[ "$agent" =~ ^[A-Za-z0-9_-]+$ ]] && writers+="$(judge::transcript_class "$tdir/$sid/subagents/agent-$agent.jsonl") "
  done < <(jq -r '.[] | (.sid, .agent) | tostring | gsub("[\r\n]"; "")' <<<"$1")
  m="${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_MODEL:-sonnet}"
  [[ "$m" =~ ^(fable|opus|sonnet|haiku)$ ]] || m=sonnet
  fb="${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_FALLBACK_MODEL:-opus}"
  [[ "$fb" =~ ^(fable|opus|sonnet|haiku)$ ]] || fb=opus
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
# verdict. A run whose result lists permission_denials (the authoritative
# record of denied tool calls,
# https://code.claude.com/docs/en/agent-sdk/typescript, as of 2026-10-04;
# recheck when the result message's fields change) and that gives no key a
# FLAG or PASS is a malfunction: it gives no verdict, and JUDGE_MUTED is 1. A
# denial names a tool call, never a block, and one run judges every block of
# the file, so a run with any FLAG or PASS keeps its UNKNOWN verdicts too.
# Any later reader may harvest a raw file whose writer died.
judge::harvest() {
  local raw="$1" dir="${1%/*}" kh json
  JUDGE_MUTED=0
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
      | "\($k.kh) \({file: $m.file, repo: $m.repo, name: $k.name, ordinal: $k.ordinal, start: $k.start, end: $k.end,
          verdict: (if $ok then $v.verdict else "UNKNOWN" end),
          evidence: [$v.evidence[]? | strings], source: ($v.source // "" | tostring), diff: ($v.diff // "" | tostring),
          reason: (if $ok then ($v.reason // "" | tostring) else "the judge returned no valid verdict" end),
          model: $m.model, effort: $m.effort, judged_at: (now | todate)} | tojson)"
      end end' 2>/dev/null)" || return 1
  [[ -n "$out" ]] || return 1
  while read -r kh json; do
    [[ "$kh" == '!' ]] && JUDGE_MUTED=1 && continue
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

# judge::run <info> <keys> <seconds> <hint> <run reservation>: one judge run over the file's keys
# (the caller holds their locks and a slot), writing verdicts under the ledger
# of the file's last writer, so a successor that adopts that session finds
# them and their relay markers. A key left without a verdict gets a failed
# attempt.
judge::run() {
  local info="$1" keys="$2" t="$3" hint="$4" res="${5:-}" dir file repo owner writers n budget raw sys prompt rc kh here
  local rule denied
  testing::fields "$info" .file .repo .owner '.writers | tojson' || {
    judge::release_run "$res"
    return 0
  }
  file="${FIELDS[0]}" repo="${FIELDS[1]}" owner="${FIELDS[2]}" writers="${FIELDS[3]}"
  dir="$DATA/verdicts/$PKEY/${owner:-$SID}"
  # The judge's reads are scoped to the repository that holds the file; a
  # test file in none is not judged rather than given its directory as the
  # scope.
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
  n=0
  while read -r kh _; do [[ -z "$kh" ]] || n=$((n + 1)); done <<<"$keys"
  budget="$((((n + 9) / 10) * 90))" && budget="$((budget / 100)).$(printf '%02d' $((budget % 100)))"
  mkdir -p "$dir"
  raw="$dir/.run-$BASHPID-$RANDOM"
  judge::pick "$writers"
  jq -Rn --arg file "$file" --arg repo "$repo" --arg model "$MODEL" --arg effort "$EFFORT" --arg budget "$budget" '
    {file: $file, repo: $repo, model: $model, effort: $effort, budget: $budget,
     keys: [inputs | select(. != "") | capture("^(?<kh>[^ ]+) (?<ordinal>[0-9]+) (?<start>[0-9]+)-(?<end>[0-9]+) (?<name>.*)$")
       | .ordinal |= tonumber | .start |= tonumber | .end |= tonumber]}' <<<"$keys" >"$raw.keys"
  rc=""
  [[ -n "$MODEL" ]] || rc="no judge class differs from the writers"
  [[ -n "$repo" ]] || rc="no repository: the judge reads only inside a git repository, and this test file is in none"
  if [[ -n "$rc" ]]; then
    : >"$raw"
    judge::harvest "$raw" "$rc"
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
    # The hang guard is the process-group watchdog, not coreutils timeout.
    here="$PWD"
    cd "$repo" || {
      judge::release_run "$res"
      return 0
    }
    res="" # the judge starts: the run's reservation is kept
    # The repository is the run's working directory, where reads need no
    # rule; the absolute rule states the same scope. Not --add-dir: that
    # would repeat the working directory, and an added directory also loads
    # some of its own .claude/ configuration
    # (https://code.claude.com/docs/en/permissions#additional-directories-grant-file-access-not-configuration).
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
    # A run cut at its bound gives no verdict, even if it printed one after
    # the watchdog killed its tools: that answer was made without them.
    if ((rc > 128)); then
      rc="judge timed out after $t s"
    else
      if ! judge::harvest "$raw"; then
        rc="judge exited $rc with no usable result"
        [[ -z "$denied" ]] || rc+="; it was denied $denied"
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

# judge::label <verdict or info json fields: file name ordinal>: "<file>: <name>", with #n past the first.
judge::label() {
  local l="${1##*[/\\]}: $2"
  (($3 > 1)) && l+=" #$3"
  printf '%s' "$l"
}

# judge::quoted_in_repo <repo> <quote>...: true when every quote is verbatim
# in a file of the repository, the judge's read scope: git grep over its
# tracked and untracked (not ignored) files. One process per quote, and only
# for quotes the test file does not hold; with no repository, none passes.
judge::quoted_in_repo() {
  local dir="$1" q
  shift
  for q in "$@"; do
    [[ -n "$dir" && "$q" != *$'\n'* ]] || return 1
    git -C "$dir" grep --untracked -F -q -e "$q" -- . 2>/dev/null || return 1
  done
}

# judge::relay_reset: empty the relay set judge::validate fills.
judge::relay_reset() {
  RELAY="" RELAY_REPOS=() RELAY_N=0 RELAY_F=0 RELAY_P=0 RELAY_U=0
}
judge::relay_reset

# judge::validate <verdict file> [test file]: add the verdict, as it may be
# relayed, to RELAY (one compact JSON line each), its repository to
# RELAY_REPOS and its verdict to the counts. A quote that is not in the
# current file, a FLAG with no diff, or a diff that fails `git apply --check`
# or touches another file makes it UNKNOWN, with the reason. One jq reads the
# fields and runs the quote check; git runs only for a FLAG, and jq again only
# to rewrite a verdict that failed.
judge::validate() {
  local v="$1" file="${2:-}" json="" repo verdict ev diff why="" p n=0 known=0 text=(--arg text "")
  IFS= read -r -d '' json <"$v"
  json="${json%%$'\n'*}"
  if [[ -z "$file" ]]; then
    testing::fields "$json" .file || return 0
    file="${FIELDS[0]}"
  fi
  [[ -f "$file" ]] && text=(--rawfile text "$file")
  # The quotes, trimmed, that the test file does not hold follow the fixed
  # fields; each must then be in a file of the repository the judge could
  # read (an implementation line is a FLAG's best evidence), else it was
  # made up.
  FIELDS=()
  while IFS= read -r -d '' p; do FIELDS+=("$p"); done < <(jq -j "${text[@]}" '
    ((.evidence // []) | map(tostring | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) | map(select(. != ""))) as $e
    | (.repo // "" | tostring), "\u0000", (.verdict // "" | tostring), "\u0000",
      (if ($e | length) == 0 then "none" else "some" end), "\u0000", (.diff // "" | tostring), "\u0000",
      ($e[] | select(. as $q | $text | contains($q) | not) | (., "\u0000"))' <<<"$json" 2>/dev/null)
  ((${#FIELDS[@]} >= 4)) || return 0
  repo="${FIELDS[0]}" verdict="${FIELDS[1]}" ev="${FIELDS[2]}" diff="${FIELDS[3]}"
  [[ -n "$repo" && -d "$repo" ]] || repo=""
  ((JUDGE_WIN)) && repo="${repo//\\//}"
  if [[ ! -f "$file" ]]; then
    why="the test file no longer exists"
  elif [[ "$verdict" != UNKNOWN && "$ev" == none ]]; then
    why="the verdict quotes no evidence"
  elif ! judge::quoted_in_repo "$repo" "${FIELDS[@]:4}"; then
    why="a quoted line is in no file of the repository"
  elif [[ "$verdict" == FLAG && -z "$diff" ]]; then
    why="the FLAG proposes no diff"
  elif [[ "$verdict" == FLAG && -z "$repo" ]]; then
    why="no repository to check the proposed diff against"
  elif [[ "$verdict" == FLAG ]]; then
    # --check with --numstat -z: whether it applies and which files it
    # touches (paths unquoted), in one call that writes nothing.
    while IFS= read -r -d '' p; do
      [[ "$p" == ok ]] && n=1 && continue
      p="${p#*$'\t'}" && p="${p#*$'\t'}"
      judge::same_path "$repo/$p" "$file" || why="the proposed diff touches another file"
    done < <(git -C "$repo" apply --check --numstat -z 2>/dev/null <<<"$diff" && printf 'ok\0')
    ((n)) || why="the proposed diff does not apply"
  fi
  if [[ -n "$why" ]]; then
    verdict=UNKNOWN
    # Only the reason is shown: the evidence, source and diff failed.
    json="$(jq -c --arg why "$why" '.verdict = "UNKNOWN" | .reason = $why | .evidence = [] | .source = "" | .diff = ""' <<<"$json")" || return 0
  fi
  RELAY+="$json"$'\n'
  RELAY_N=$((RELAY_N + 1))
  case "$verdict" in
  FLAG) RELAY_F=$((RELAY_F + 1)) ;;
  PASS) RELAY_P=$((RELAY_P + 1)) ;;
  *) RELAY_U=$((RELAY_U + 1)) ;;
  esac
  for p in ${RELAY_REPOS[@]+"${RELAY_REPOS[@]}"}; do [[ "$p" == "${FIELDS[0]}" ]] && known=1; done
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

# judge::findings_dir <repo> <branch>: set FDIR to the findings
# directory the detector-findings contract resolves for a headless producer:
# <repo>/.work/reviews/<branch-slug>/, with the memory root's self-ignoring
# .gitignore. The directory must resolve physically (symbolic links followed)
# strictly inside the checkout, before and after it is created, and the
# .gitignore is created exclusively, never through an existing link. No
# branch, or a check that fails: the plugin data directory.
judge::findings_dir() {
  local repo="$1" branch="$2" mem target
  FDIR="$DATA/findings"
  if [[ -n "$branch" ]]; then
    mem="$repo/.work"
    judge::slug "$branch"
    target="$mem/reviews/$SLUG"
    # Both the memory root (where the .gitignore goes) and the findings
    # directory are checked, before mkdir and again after it.
    if judge::inside "$repo" "$mem" && judge::inside "$repo" "$target" &&
      { [[ -d "$target" ]] || mkdir -p "$target"; } &&
      judge::inside "$repo" "$mem" && judge::inside "$repo" "$target" && judge::self_ignore "$mem"; then
      FDIR="$target"
    fi
  fi
}

# judge::inside <repo> <path>: true when the path resolves physically strictly
# inside the repository, or, while it does not exist yet, when its nearest
# existing ancestor resolves to the repository or inside it. A dangling link
# on the way counts as existing and fails to resolve.
judge::inside() {
  local top r p="$2"
  while [[ ! -e "$p" && ! -L "$p" && "$p" == */* ]]; do p="${p%/*}"; done
  judge::phys top "$1" && judge::phys r "$p" || return 1
  [[ "$r" == "$top/"?* ]] || [[ "$p" != "$2" && "$r" == "$top" ]]
}

# judge::phys <var> <dir>: set var to the directory's physical path (every
# link resolved), with cd -P in this shell rather than a subshell.
judge::phys() {
  local here="$PWD" rc=0
  cd -P -- "$2" 2>/dev/null || return 1
  printf -v "$1" '%s' "$PWD"
  cd -- "$here" 2>/dev/null || rc=1
  return "$rc"
}

# judge::excl <file> <text>: write the text to a new file. Any name that
# already exists, as a file, a link (dangling or not), a FIFO or anything
# else, is refused before the open: noclobber adds O_EXCL only when the name
# is absent, and opens an existing non-regular name as it is.
judge::excl() {
  [[ -e "$1" || -L "$1" ]] && return 1
  local rc
  set -o noclobber
  { printf '%s\n' "$2" >"$1"; } 2>/dev/null
  rc=$?
  set +o noclobber
  return "$rc"
}

# judge::self_ignore <memory root>: make sure the root holds a .gitignore of
# its own: a regular file already there, or a new one. A link (dangling or
# not), a FIFO or any other kind of name there is refused, never written.
judge::self_ignore() {
  [[ -L "$1/.gitignore" ]] && return 1
  [[ -f "$1/.gitignore" ]] && return 0
  judge::excl "$1/.gitignore" '*'
}

# judge::findings <validated verdict lines>: write one findings file per
# repository in the detector-findings shape (FLAG rows under ## Findings; every
# verdict, its quoted evidence and proposed diff under ## Verdicts) and set
# FINDINGS to their paths, comma-separated.
judge::findings() {
  local all="$RELAY" repo dir ts path i branch content tmp p
  FINDINGS=""
  TZ=UTC0 printf -v ts '%(%Y%m%dT%H%M%SZ)T' -1
  for repo in ${RELAY_REPOS[@]+"${RELAY_REPOS[@]}"}; do
    branch=""
    [[ -z "$repo" || ! -d "$repo" ]] || branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
    judge::findings_dir "$repo" "$branch"
    # Judge text is data: every field is capped and kept on one line, so it
    # cannot open a heading, a table row or a fence of its own, and the diff's
    # fence is one backtick longer than any run of backticks inside it.
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
        + "Judge: \(.model | esc) at \(.effort | esc) effort.\n\n"
        + (if (.source // "") != "" then "Where the expected value came from: \(.source | esc)\n\n" else "" end)
        + ([(.evidence // [])[:20][] | "> " + esc + "\n"] | join(""))
        + (if .verdict == "FLAG" and (.diff // "") != "" then
            (.diff | cap(20000) | rtrimstr("\n")) as $d
            | ("`" * ([4, ([$d | scan("`+") | length] | max // 0) + 1] | max)) as $fence
            | "\nProposed diff, not applied:\n\n\($fence)diff\n\($d)\n\($fence)\n" else "" end)] | join(""))
      ' <<<"$all" 2>/dev/null)" || continue
    # The content goes to a new temp file in the checked directory, which is
    # checked again, and then takes the first free name with mv -n: a name
    # already taken, by anything, moves to the next suffix, and a directory
    # that fails a check or refuses every name falls back to the plugin data
    # directory. A local process racing these steps is an accepted residual.
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
    [[ -n "$path" ]] && FINDINGS+="${FINDINGS:+, }$path"
  done
}

# judge::counts <validated verdict lines>: "N tests (F FLAG, P PASS, U UNKNOWN)".
# judge::mark_relayed <owner sid>/<key-hash>...: record the keys as relayed,
# with one mkdir for every directory.
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
