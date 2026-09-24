#!/usr/bin/env bash
# Stop hook: surface hook launch/exec failures that Claude Code records only as
# `hook_non_blocking_error` transcript attachments and shows to nobody (#2577).
#
# A hook that fails to LAUNCH is a non-blocking error: the tool call proceeds as
# if the hook had approved it, and the only durable trace is an attachment
# record in the session transcript that no human reads. The #1416 incident
# proved the class (a PreToolUse destructive guard dead for 140 recorded
# launches), and it also proved that an in-plugin detector is not shelter:
# disk-hygiene's own Stop-event `guard_launch_monitor.py` shared the guard's
# registration form and died the same launch death on all 23 of its runs. This
# hook is the DECOUPLED detector: it lives in a different plugin whose own
# registrations stayed alive through that entire incident, so a defect that
# kills a watched plugin's launch path does not take the detector with it. It
# also covers the stale-session window no source-side gate can reach: hook
# config is loaded at session start, so a session running when a fix lands on
# disk keeps executing the dead config until restart — 22 further failures were
# recorded in one live session AFTER the #2570 fix shipped (#2577).
#
# ADVISORY: never blocks, always exit 0. Registered on Stop, not
# PreToolUse/PostToolUse, for the cost rationale `guard_launch_monitor.py` and
# ADR 0004 (D-12) record: a failure record is already in the transcript by the
# time the turn ends, so once-per-turn cadence catches it as promptly as
# once-per-tool-call would at a fraction of the invocation count.
#
# The scan is INCREMENTAL, keyed on a per-session cursor holding the byte offset
# already audited. The transcript is the session's own JSONL and grows every
# turn, so no mtime or size sentinel on the FILE can mean "nothing new to audit"
# — the cheap signal has to be about the appended content. A Stop reads only the
# bytes past the cursor, with one `tail` and the shell's own pattern match, so
# its cost follows what the turn appended, not the transcript's size; a turn
# whose new bytes carry no candidate exits having spawned only that `tail`. The
# cold scan (first Stop of a session, or a reset) keeps the tail cap so that one
# unbounded read stays O(cap). See the cursor block below for the file's shape
# and its failure modes.
#
# Matching is STRUCTURAL, never substring: a record counts only when the
# top-level `.type == "attachment"` and `.attachment.type ==
# "hook_non_blocking_error"`. Two false-positive shapes make anything less
# strict wrong, both hit while mining the incident transcripts: a
# `hook_success` attachment whose stdout QUOTES an error, and a message record
# quoting a failure record as a plain string (#2577).
#
# Warns once per session PER DISTINCT failing hook REGISTRATION, identified by
# (hookName, command) — hookName alone is just event:matcher, which several
# plugins share: the first Stop after a registration starts failing warns,
# later turns stay silent unless a NEW registration starts failing. Marker
# bookkeeping degrades toward RE-WARNING, never toward silence — when no marker
# home is available the warning repeats rather than disappears, the same
# doctrine as `guard_launch_monitor.py`.
#
# Overlap with disk-hygiene's `guard_launch_monitor.py` is deliberate and
# accepted: that monitor keeps its guard-specific semantics; this one covers
# every hook of every plugin. A destructive-guard failure may be warned about
# twice — over-warning is the safe failure direction for this defect class.
#
# Kill switch: CLAUDE_PLUGIN_OPTION_HOOK_FAILURE_AUDIT_ENABLED=false.

set -uo pipefail
# Hook directory by parameter expansion, never `dirname`. GNU Bash forks a
# subshell for every command substitution even when the body is a builtin
# (Command Substitution, Bash Reference Manual). On Windows Git Bash that
# fork is a process. `${BASH_SOURCE[0]%/*}` equals dirname for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
hook::check_enabled "HOOK_FAILURE_AUDIT"

START=${EPOCHREALTIME:-}

# The payload fields are read by the SAME call that buffers stdin. Passing
# filters to hook::buffer_stdin_to fuses the library's `jq -e .` validation
# probe into the field read, and hook::jq_fields answers a well-formed payload's
# plain-string fields with the library's builtin parser — so a Stop envelope
# costs no process at all, where the unfused pair cost a fork and a jq exec.
#
# The fused call is also why hook::require_jq comes AFTER it rather than before:
# without jq the library returns an EMPTY field array and still reports success,
# and reading `${HOOK_JQ_FIELDS[0]}` from it under `set -u` would kill the hook
# with an unbound-variable error instead of failing open. The gate runs first,
# and the cardinality check behind it is what makes the array read safe.
hook::buffer_stdin_to INPUT '.transcript_path' '.session_id' || exit 0

# Advisory finding -> fail open, with the standard once-per-session notice.
hook::require_jq Stop claude-ops "$INPUT"

# An absent field arrives as the empty string rather than as a non-zero return,
# so each guard below is spelled out instead of riding on `||`.
((${#HOOK_JQ_FIELDS[@]} == 2)) || exit 0
TRANSCRIPT="${HOOK_JQ_FIELDS[0]}"
[[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]] || exit 0
SESSION="${HOOK_JQ_FIELDS[1]}"
[[ -n "$SESSION" ]] || SESSION="no-session"
# data.session_id (additive, hook-telemetry rule 1): the sink routes an
# envelope carrying one into the per-session log beside session-event-log.sh.
SESSION_ID=""
[[ "$SESSION" != "no-session" && "$SESSION" =~ ^[A-Za-z0-9._-]+$ ]] && SESSION_ID="$SESSION"
SESSION="${SESSION//[^A-Za-z0-9_-]/-}"

# `mapfile` is Bash 4.0+ and these hooks document 3.2+ support (hook-utils.sh).
# Only the cold path's uncapped read uses it; without it that read takes the
# grep pre-filter — the work this hook has always done, never a silent skip.
HAVE_MAPFILE=0
((BASH_VERSINFO[0] >= 4)) && HAVE_MAPFILE=1

# CURSOR: the byte offset this session has audited up to, always the end of a
# complete line, so the byte just before it is a newline. The file is
# "b<offset>\n<transcript_path>\n", beside the warning marker, under the same
# ${CLAUDE_PLUGIN_DATA} home and swept by the same 7-day prune. The `b` marks
# the unit: a cursor that counted lines has no prefix and reads as malformed.
#
# Every failure mode resolves toward RESCANNING, never toward silence — the same
# doctrine the marker follows:
#   - no marker home, an unreadable or malformed cursor -> 0, a full scan
#   - a line-count cursor with no `b` prefix -> 0
#   - a different transcript_path -> 0, this session was handed another file
#   - under C-1 bytes present, or no newline at byte C-1 -> 0, the transcript
#     shrank or was replaced
#   - a cursor pruned mid-session -> 0
#   - a non-canonical decimal (a leading zero, or over 15 digits), or an offset
#     below 2, too short to hold the anchor the warm read checks -> 0
# Rescanning cannot re-warn: the (hookName, command) marker below is what
# decides that, and it is unchanged.
#
# Two cases get past the anchor. A file cut to exactly C-1 bytes reads as
# "nothing new" until the next append. A same-path replacement with a newline
# at byte C-1 is accepted, and its first C bytes are never read; the line
# cursor had the same gap. Catching either needs a second process per Stop.
#
# The cursor covers COMPLETE lines only. A final line with no newline is still
# scanned this turn — skipping it could hide a record the full scan would have
# surfaced — but it is not counted, so the next Stop reads it again once the
# harness has finished writing it.
MARKER_DIR=""
CURSOR_FILE=""
CURSOR=0
if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
  MARKER_DIR="${CLAUDE_PLUGIN_DATA}/hook-failure-audit"
  # `-d` first: after the first turn the directory always exists, and `mkdir -p`
  # on an existing directory is a whole process to reach the same no-op. A
  # directory that exists but is unwritable reaches the writes below and fails
  # there, which is the degrade-toward-rescanning path.
  if [[ -d "$MARKER_DIR" ]] || mkdir -p "$MARKER_DIR" 2>/dev/null; then
    CURSOR_FILE="$MARKER_DIR/${SESSION}.cursor"
    CURSOR_BYTES=""
    CURSOR_PATH=""
    # Group redirect, not `$(<file)` twice: two builtin reads share one open
    # file and the group forks nothing. `2>/dev/null` is written BEFORE the
    # input redirect because redirections apply left to right — after it, a
    # failed open still prints its diagnostic, and a Stop hook's stderr is
    # user-visible output.
    [[ -f "$CURSOR_FILE" ]] &&
      {
        IFS= read -r CURSOR_BYTES
        IFS= read -r CURSOR_PATH
      } 2>/dev/null <"$CURSOR_FILE"
    CURSOR_BYTES="${CURSOR_BYTES%$'\r'}"
    CURSOR_PATH="${CURSOR_PATH%$'\r'}"
    # Canonical decimal only, capped at 15 digits (far below 2^63): a leading
    # zero such as "08" passes a bare `[0-9]+` test but bash's `((...))`
    # reads a leading zero as octal and errors on 8/9, and an uncapped digit
    # string can wrap in arithmetic. Both are rejected here, not coerced with
    # `10#`. A rejected value falls through to the CURSOR=0 cold path below,
    # the same outcome every other malformed cursor already gets.
    [[ "$CURSOR_BYTES" =~ ^b([1-9][0-9]{0,14})$ && "$CURSOR_PATH" == "$TRANSCRIPT" ]] &&
      CURSOR="${BASH_REMATCH[1]}"
    ((CURSOR >= 2)) || CURSOR=0
  else
    MARKER_DIR=""
  fi
fi

# Advanced only once the lines it covers have been DISPOSED of: no candidate, an
# empty structural selection, nothing left unwarned, or a warning emitted. A jq
# failure leaves the cursor where it stood so those lines are audited again.
# `2>/dev/null` ahead of the output redirect, as on the read above: an unwritable
# marker home must degrade to rescanning silently, not print at the user.
SCANNED=0
cursor_advance() {
  [[ -n "$CURSOR_FILE" ]] || return 0
  printf 'b%s\n%s\n' "$SCANNED" "$TRANSCRIPT" 2>/dev/null >"$CURSOR_FILE" || :
}

# Bounded COLD read: the first Stop of a session (or a reset) is the one read
# the cursor cannot bound, so the byte cap stays. When the cap truncates, the
# first in-window line is likely partial — drop it, as guard_launch_monitor.py
# does. The override exists for the contract test.
TAIL_BYTES="${HOOK_FAILURE_AUDIT_TAIL_BYTES:-2000000}"

# The pre-filter is a cheap candidate test only; the structural jq selection
# decides. The
# no-match common case exits on the pre-filter's emptiness, before paying for
# the jq spawn (an empty stream produced the same silent exit via "[]").
# `fromjson?` skips unparsable lines instead of aborting the stream.
# Identity is the REGISTRATION, not the matcher name: several plugins register
# on the same event+matcher (multiple PreToolUse:Bash guards exist in this very
# marketplace), and the attachment's command string is what tells them apart —
# grouping by hookName alone would let registration B's first failure hide
# behind registration A's earlier warning.
#
# `class` classifies the record THREE ways: a hook that never LAUNCHED, one that
# RAN and exited non-zero, and one whose record cannot settle which. They are
# different incidents with different remedies, and only the first is fixed by
# restarting the session (#2849). `exitCode` alone cannot carry the split — every
# record in the observed corpus has a non-null exitCode (175/175 on 2026-08-16),
# and 1 is the code the WSL relay reports for its exec failures, so "exitCode is
# not null" and "exitCode != 1" both misclassify. Neither can 126/127 on its own:
# a registered shell hook that DID launch exits 126 or 127 whenever a command IT
# ran was missing or not executable, and calling that a launch failure emits the
# restart-the-session remedy and reproduces exactly the misdiagnosis this hook
# exists to fix. The corpus shows the two signals are close to independent — 163
# records carry an `execvpe` signature at exitCode 1, and the single exitCode 127
# record carries no stderr signature at all — so neither alone is sufficient:
#   - launch failure        stderr carries an exec-failure signature. Signature
#                           evidence decides this REGARDLESS of exit code.
#   - completed non-zero    no signature, and exitCode is not 126 or 127.
#   - ambiguous             no signature, but exitCode is 126 or 127. Both
#                           readings stay possible; the message says so plainly
#                           and gives both remedies rather than picking one.
# #2849's 126/127-OR-signature rule is too loose for the reason above.
#
# The signature set stays narrow on purpose — `command not found`, `cannot
# execute`, and cmd.exe's `is not recognized as an internal or external command`
# are all excluded because a hook that launched fine prints them from a command
# IT ran, which would re-introduce this defect in a new shape. Classification
# reads the FULL stderr, before the 160-char truncation below: the observed
# `execvpe` signature STARTS at offset 90-94 across the measured records and
# survives truncation today, but that is luck, not contract.
#
# One accepted residual remains, resolved toward the launch-failure label because
# nothing in the attachment can settle it: a launched hook can print `execvpe`
# about a child of its own.
#
# The class is counted PER RECORD, not read off the last one. `group_by` below
# collapses a registration's records into one line, and a registration can fail
# more than one way within a single unwarned batch (an intermittent relay hiccup
# between two runs of the same hook). Inheriting the class from `last` the way
# `exitCode` and `stderr` do would relabel the whole group by whichever record
# happened to come last, and would drop the other classes' sentences from the
# message entirely — the same misclassification defect this hook exists to fix,
# in a narrower shape. The per-class counts below keep every class present in a
# group visible, and the message flags are computed from those counts, never
# from a single collapsed value.
#
# `[[ $line == *needle* ]]` is `grep -F` on one line, and it is the same fixed
# string: identical selection, no process. `mapfile` is read WITHOUT `-t` so
# every line keeps its newline, which makes the joined candidates byte-identical
# to what `$(grep …)` produced.
NEEDLE='"hook_non_blocking_error"'
RECORDS=""
LINES=()
N=0
scan_lines() { # <first index to test>
  local i
  for ((i = $1; i < N; i++)); do
    [[ "${LINES[i]}" == *"$NEEDLE"* ]] && RECORDS+="${LINES[i]}"
  done
  RECORDS="${RECORDS%$'\n'}"
}

# WARM read: only the bytes past the cursor. Bash has no builtin seek, and a
# builtin that skips to the offset (`mapfile -s`, `read -N`) still reads every
# earlier byte, so one `tail -c +N` is the cheapest read whose cost follows what
# was appended rather than the transcript's size. The substitution carries no
# redirection of its own, which keeps it one process (#3779); the group silences
# its stderr, and with it bash's own warning should a NUL byte be dropped.
#
# The read starts TWO bytes before the cursor: the last byte of the last audited
# line and the newline that ended it. That anchor proves in the same read that
# the transcript still has at least that many bytes and a line boundary where
# the cursor says; anything else means it shrank or was replaced. Two bytes, not
# one, because the substitution strips trailing newlines: a lone anchor newline
# would come back empty, the same result as a file cut short of it.
#
# That stripping also hides whether the final line ended with a newline, so the
# final line is scanned but never counted — the next Stop reads it again.
# `LC_ALL=C` makes every length and offset here count bytes, not characters.
# ponytail: re-reading the final line costs two jq and one find on the Stop
# after one whose last line is itself a failure record; counting it exactly
# would need a second process on every Stop.
warm_read() {
  local LC_ALL=C window body complete line
  mapfile -s $((CURSOR - 1)) LINES <"$TRANSCRIPT" 2>/dev/null
  { window=$(tail -c "+$((CURSOR - 1))" -- "$TRANSCRIPT"); } 2>/dev/null
  SCANNED=$CURSOR
  if [[ "$window" != ?$'\n'* ]]; then
    # Only the anchor's first byte: nothing but newlines past the cursor.
    [[ ${#window} == 1 ]]
    return
  fi
  body="${window:2}"
  if [[ "$body" == *$'\n'* ]]; then
    complete="${body%$'\n'*}"
    SCANNED=$((CURSOR + ${#complete} + 1))
  fi
  [[ "$body" == *"$NEEDLE"* ]] || return 0
  # Newline-only IFS splits on lines and drops empty ones, which never match;
  # `set -f` keeps a line from globbing.
  local IFS=$'\n'
  set -f
  for line in $body; do
    [[ "$line" == *"$NEEDLE"* ]] && RECORDS+="$line"$'\n'
  done
  set +f
  RECORDS="${RECORDS%$'\n'}"
}

if ((CURSOR > 0)); then
  warm_read || CURSOR=0
fi

if ((CURSOR == 0)); then
  # `wc -c -- <file>` gives the byte count the cap decision needs and the offset
  # the cursor starts from. Should the file end mid-line, that offset has no
  # newline before it, and the next Stop's anchor check sends it back here, so
  # the partial line is read again rather than skipped. Naming the file rather
  # than `< file` is what keeps it one process: bash runs the command of a
  # command substitution in the substitution's own subshell and skips the extra
  # fork ONLY when that command carries no redirection of its own (#3779).
  # `read` drops the filename column along with the leading padding some `wc`
  # builds emit, and the `2>/dev/null` rides on the surrounding single-command
  # group, where it silences the same stream without re-arming that fork.
  SIZE=""
  { read -r SIZE _ < <(wc -c -- "$TRANSCRIPT"); } 2>/dev/null
  [[ "$SIZE" =~ ^[0-9]+$ ]] || exit 0
  SCANNED=$SIZE
  if ((SIZE > TAIL_BYTES)); then
    # Over the cap the pipeline is unchanged — the truncated first in-window
    # line is likely partial and `sed '1d'` drops it, as guard_launch_monitor.py
    # does — and its `2>/dev/null` stays exactly where it was, on `tail`,
    # because a pipeline element forks either way and moving the redirect out
    # would newly silence sed and grep for no saving. Lines before the window
    # are not read here and never were; the cursor simply stops the next Stop
    # from re-deciding that.
    RECORDS=$(tail -c "$TAIL_BYTES" -- "$TRANSCRIPT" 2>/dev/null | sed '1d' |
      grep -F "$NEEDLE")
  elif ((HAVE_MAPFILE)); then
    mapfile LINES <"$TRANSCRIPT" 2>/dev/null
    N=${#LINES[@]}
    scan_lines 0
  else
    # Group-scoped redirect: `grep … 2>/dev/null` inside the substitution would
    # cost the extra fork the file-argument form just saved (#3779). The group
    # holds one command, so nothing beyond grep's own stderr is silenced.
    { RECORDS=$(grep -F "$NEEDLE" -- "$TRANSCRIPT"); } 2>/dev/null
  fi
fi
LINES=()
[[ -n "$RECORDS" ]] || {
  cursor_advance
  exit 0
}
# `printf | jq` and NOT a here-string, even though the pipeline costs a process
# the here-string would not. What is known, stated as known: hook::jq_field in
# the shared library documents this hazard and refuses the here-string form for
# it — bash fills a here-string's pipe itself, so a payload at or above the pipe
# capacity can block before jq is exec'd — and the reproduction behind that note
# is from this repo's Windows Git Bash hosts (#1587: 65536 bytes hung
# indefinitely, 65000 returned at once). It does NOT reproduce on Linux bash
# 5.2: 65535, 65536, 65537, 200 kB and 2 MB each return immediately, including
# under an unwritable TMPDIR. `$RECORDS` is every matching transcript record in
# the window and routinely clears that capacity, so this call keeps the
# library's conservative form rather than bet the hazard is Linux-only. The
# forgone saving is one fork on the warning path only: a turn with no failure
# record exits above, before this line.
SUMMARY=$(printf '%s' "$RECORDS" |
  jq -cRs '[
      split("\n")[] | fromjson?
      | select(.type? == "attachment") | .attachment
      | select(.type? == "hook_non_blocking_error")
      | {hookName: (.hookName // "unknown"),
         command: ((.command // "") | .[0:120]),
         exitCode: (.exitCode // null),
         class: (if ((.stderr // "")
                     | test("execvpe|execve\\(|exec format error"; "i"))
                 then "launch"
                 elif (.exitCode == 126 or .exitCode == 127) then "ambiguous"
                 else "completed" end),
         stderr: ((.stderr // "") | .[0:160])}
    ]
    | group_by(.hookName + "	" + .command)
    | map({hookName: .[0].hookName, command: .[0].command,
           count: length,
           launchCount: (map(select(.class == "launch")) | length),
           ambiguousCount: (map(select(.class == "ambiguous")) | length),
           completedCount: (map(select(.class == "completed")) | length),
           exitCode: last.exitCode, stderr: last.stderr})' 2>/dev/null)
# An EMPTY $SUMMARY is jq failing, not a clean selection: leave the cursor where
# it stood so the same lines are audited again. `[]` is a document, and one that
# disposes of them.
[[ -n "$SUMMARY" ]] || exit 0
[[ "$SUMMARY" != "[]" ]] || {
  cursor_advance
  exit 0
}

# Once per session per hook name. Markers live under ${CLAUDE_PLUGIN_DATA}
# (survives plugin updates) in the directory resolved above; stale sessions'
# markers and cursors are pruned together after 7 days. Any bookkeeping failure
# leaves WARNED empty, so everything found is treated as new — re-warn, never
# suppress.
MARKER=""
WARNED=""
if [[ -n "$MARKER_DIR" ]]; then
  find "$MARKER_DIR" -type f -mtime +7 -delete 2>/dev/null
  MARKER="$MARKER_DIR/${SESSION}"
  # `$(<file)`, not `$(cat -- file)`: bash reads the file itself here, with no
  # subshell and no exec at all. Same trailing-newline stripping as the
  # substitution around `cat` had.
  [[ -f "$MARKER" ]] && { WARNED=$(<"$MARKER"); } 2>/dev/null
fi

# Marker lines are "<hookName>\t<command>" fingerprints. `rtrimstr("\r")` on
# read and `tr -d '\r'` on write: some Windows jq builds emit CRLF, and a
# fingerprint that grows a carriage return on one side of the comparison would
# quietly re-warn (or worse, wrongly suppress) forever after.
NEW=$(jq -cn --argjson summary "$SUMMARY" --arg warned "$WARNED" '
  ($warned | split("\n") | map(rtrimstr("\r")) | map(select(length > 0))) as $seen
  | [$summary[] | select((.hookName + "	" + .command) as $k | $seen | index($k) | not)]')
[[ -n "$NEW" ]] || exit 0
[[ "$NEW" != "[]" ]] || {
  cursor_advance
  exit 0
}

TOTAL=$(jq -rn --argjson new "$NEW" '[$new[].count] | add')

# Claude Code synthesizes this exact sentence as the stderr of a hook that
# produced none, so an empty `.stderr` is a shape the harness does not emit —
# 0 of 175 observed records carry one, while 12 carry this literal (#2849).
# Passing it through verbatim reads as though the HOOK emitted the sentence;
# both shapes are rendered as the same explicit no-output marker instead. The
# match is exact, not a prefix: the string is the whole stderr in every
# observed record (12/12 exact, 0 needing whitespace trimming).
NO_STDERR_PLACEHOLDER='Failed with non-blocking status code: No stderr output'

DETAIL=$(jq -rn --argjson new "$NEW" --arg ph "$NO_STDERR_PLACEHOLDER" '
  [$new[] |
    (if (.stderr == "" or .stderr == $ph) then "(none — hook produced no stderr)"
     else .stderr end) as $err |
    (if .exitCode == null then "?" else (.exitCode|tostring) end) as $ec |
    ([{n: .launchCount, label: "launch failure"},
      {n: .ambiguousCount,
       label: "ambiguous: exit 126/127 with no exec-failure signature"},
      {n: .completedCount, label: "completed non-zero exit"}]
     | map(select(.n > 0))) as $classes |
    (if ($classes | length) == 1 then $classes[0].label
     else ($classes | map("\(.n) \(.label)") | join(" + ")) end) as $kind |
    "\(.hookName) [\(.command)] (\(.count)x; \($kind); exit \($ec); last stderr: \($err))"
  ] | join("; ")')

# Computed from the per-record class counts, never from a collapsed single
# value: a group whose only launch-failure record is not its last must still
# raise the launch flag, and its own line above must still show the mix.
#
# All three flags come from ONE jq process over the same document rather than
# three: a jq spawn is ~140 ms of fork() emulation on Windows Git Bash. `read`
# assigns every name it is given even when the stream is short, so all three
# stay defined under `set -u`. A Windows jq build ends the line with CRLF, and
# the carriage return lands on the last name.
read -r HAS_LAUNCH HAS_AMBIGUOUS HAS_COMPLETED < <(jq -rn --argjson new "$NEW" '
  [([$new[] | .launchCount > 0]    | any),
   ([$new[] | .ambiguousCount > 0] | any),
   ([$new[] | .completedCount > 0] | any)] | @tsv')
HAS_COMPLETED="${HAS_COMPLETED%$'\r'}"

# The diagnosis and the remedy are per-class, so several sentences can appear
# when one warning batches records of different classes; the per-registration
# `$kind` above says which records earned which. The launch-failure wording is
# kept VERBATIM where it is correct — it is right for the 163 signature-carrying
# records in the observed corpus — and is simply not asserted about a hook that
# ran to completion, nor about a record that cannot settle the question. The
# completed branch stays event-agnostic: 2593's record is a Stop hook, where
# there is no guarded tool call to proceed.
MSG="claude-ops: ${TOTAL} hook failure record(s) in this session's transcript were never surfaced: ${DETAIL}."
if [[ "$HAS_LAUNCH" == "true" ]]; then
  MSG="${MSG} A hook that fails to launch enforces nothing — the tool calls it guards proceed as if approved (fail-open)."
fi
if [[ "$HAS_AMBIGUOUS" == "true" ]]; then
  MSG="${MSG} Exit 126 or 127 with no exec-failure signature in stderr is ambiguous — a shell reports those codes both for a registered command it could not execute at all and for a hook that ran and could not execute a command of its own, and the record cannot tell them apart. Both are possible: check that the registered command exists, is executable, and resolves on this platform, AND read the hook's own logic for a command it could not run."
fi
if [[ "$HAS_COMPLETED" == "true" ]]; then
  MSG="${MSG} A hook that exited non-zero with no exec-failure evidence enforced nothing either, and Claude Code told nobody — but nothing here points at the launch path, so its own exit status and stderr above are where the failure is."
fi
MSG="${MSG} Confirm hook_failure_audit_enabled stays true via /plugin configure claude-ops@<marketplace> (default true)."
if [[ "$HAS_LAUNCH" == "true" || "$HAS_AMBIGUOUS" == "true" ]]; then
  MSG="${MSG} If a plugin update changed hook config on disk mid-session, this session still runs the config it loaded at startup — restart the session to load the fix."
fi

hook::emit_system_message "$MSG"

# The lines are disposed of the moment the warning is out. A marker write that
# fails after this point costs nothing: those registrations were warned about
# once, which is the contract.
cursor_advance

# Record what was warned about before telemetry: the warning is the contract,
# the envelope is best-effort.
# `tr -d '\r'` is gone, not its effect: the CRs come from a Windows jq build
# writing stdout in text mode, and bash strips them from the captured string
# for free. The pipeline cost a process to delete one byte class from a string
# bash can rewrite in place, and the substitution around a bare jq carries no
# redirection, so it costs one process rather than two.
if [[ -n "$MARKER" ]]; then
  FINGERPRINTS=""
  { FINGERPRINTS=$(jq -rn --argjson new "$NEW" '$new[] | .hookName + "	" + .command'); } 2>/dev/null
  [[ -n "$FINGERPRINTS" ]] && printf '%s\n' "${FINGERPRINTS//$'\r'/}" >>"$MARKER" 2>/dev/null
fi

# Telemetry subjects stay hookName-only (privacy-safe); the command detail is
# user-facing message content, not envelope data.
DATA=$(jq -cn --arg session_id "$SESSION_ID" --argjson new "$NEW" --argjson total "${TOTAL:-0}" \
  '{subjects: ([$new[].hookName] | unique), total: $total} + (if $session_id == "" then {} else {session_id: $session_id} end)')
hook::emit_telemetry "hook-failure-audit" "Stop" "error" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
