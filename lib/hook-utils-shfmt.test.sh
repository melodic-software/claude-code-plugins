#!/usr/bin/env bash
# Contract tests for hook::bash_parse_segments_shfmt: what reaches the callback,
# what fills the HOOK_SEG_* arrays, and when the guard refuses the call. Where a
# row states a form bash runs, bash itself is asked; the other expectations are
# the contract documented at hook::bash_parse_segments_uncached.
set -uo pipefail

_T_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_T_DIR" == "${BASH_SOURCE[0]}" ]] && _T_DIR=.
_T_ROOT=$(cd "$_T_DIR/.." && pwd -P)
# shellcheck source=hook-utils.sh
source "$_T_ROOT/lib/hook-utils.sh"

PASS=0 FAIL=0
ok() {
  PASS=$((PASS + 1))
  printf 'ok   %s\n' "$1"
}
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1" >&2
}

_T_TMP=$(mktemp -d)
trap 'rm -rf "${_T_TMP:?}"' EXIT

hash shfmt jq 2>/dev/null || {
  fail "shfmt and jq are required by this suite"
  printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
  exit 1
}

segs=()
collect() { segs+=("$*"); }

# segs_are <desc> <command> <segment>...: every segment, in source order.
segs_are() {
  local desc=$1 cmd=$2 got want
  shift 2
  segs=()
  hook::bash_parse_segments_shfmt "$cmd" collect
  got=$(printf '%s|' ${segs[@]+"${segs[@]}"})
  want=$(printf '%s|' "$@")
  if [[ "$got" == "$want" ]]; then ok "$desc"; else fail "$desc: got [$got], want [$want]"; fi
}

# has_seg <desc> <command> <segment>: that segment is among them.
has_seg() {
  local desc=$1 cmd=$2 want=$3 s
  segs=()
  hook::bash_parse_segments_shfmt "$cmd" collect
  for s in ${segs[@]+"${segs[@]}"}; do
    if [[ "$s" == "$want" ]]; then
      ok "$desc"
      return
    fi
  done
  fail "$desc: [$want] not in [$(printf '%s|' ${segs[@]+"${segs[@]}"})]"
}

# shellcheck disable=SC2016  # the substitutions are the command text under test
{
  # --- every simple command in the tree reaches the callback ------------------
  has_seg 'command substitution' 'echo $(git reset --hard)' 'git reset --hard'
  has_seg 'command substitution in double quotes' 'echo "x $(git reset --hard)"' 'git reset --hard'
  has_seg 'backtick substitution' 'echo `git reset --hard`' 'git reset --hard'
  has_seg 'escaped backtick nested in backticks' 'echo `echo \`git reset --hard\``' 'git reset --hard'
  has_seg 'process substitution' 'cat <(git reset --hard)' 'git reset --hard'
  has_seg 'substitution inside a parameter expansion' 'echo ${x:-$(git reset --hard)}' 'git reset --hard'
  has_seg 'substitution inside arithmetic' 'echo $(( $(git reset --hard) ))' 'git reset --hard'
  has_seg 'substitution inside an array' 'a=($(git reset --hard))' 'git reset --hard'
  has_seg 'substitution in a redirect target' 'echo >$(git reset --hard)' 'git reset --hard'
  has_seg 'subshell, block, if, while, for, function bodies' \
    '(a); { b; }; if c; then d; fi; while e; do f; done; for g in 1; do git reset --hard; done' 'git reset --hard'
  has_seg 'function body' 'f() { git reset --hard; }' 'git reset --hard'
  has_seg 'a case clause body' 'case x in a|b) git reset --hard;; esac' 'git reset --hard'
  has_seg 'an unquoted here-doc body substitution' $'cat <<E\n$(git reset --hard)\nE' 'git reset --hard'
  has_seg 'a backtick in an unquoted here-doc body' $'cat <<E\n`git reset --hard`\nE' 'git reset --hard'
  has_seg 'the round-4 reading ends the first statement' \
    'echo $(case x in a|esac) :;; esac)#; git reset --hard' 'git reset --hard'
  has_seg 'extglob-off reading of !(…) runs the subshell' '!(git reset --hard)' 'git reset --hard'
  has_seg 'extglob-on reading of !(x)# runs what follows' '!(x)#; git reset --hard' 'git reset --hard'
  has_seg 'a backtick inside an extglob pattern' 'echo @(`git reset --hard`)' 'git reset --hard'
  has_seg 'a process substitution inside an extglob pattern' 'echo @(<(git reset --hard))' 'git reset --hard'
  has_seg 'array then # keeps what follows' 'a=(x)#y; git reset --hard' 'git reset --hard'

  # Multibyte UTF-8 is read as written; a byte that is not UTF-8 is refused.
  segs_are 'multibyte UTF-8 words are read as written' 'echo héllo 日本 ✓' 'echo héllo 日本 ✓'
  # A quoted here-doc body expands nothing, and is not a command.
  segs_are 'a quoted here-doc body runs nothing' $'cat <<\'E\'\n$(git reset --hard)\nE' 'cat'
  segs_are 'a comment after whitespace runs nothing' 'echo x #; git reset --hard' 'echo x'
  segs_are 'quoted text is one word' "echo 'git reset --hard'" 'echo git reset --hard'
  segs_are 'source order: statements, then here-doc bodies after them' \
    $'cat <<E; b\n$(c)\nE\nd' 'cat' 'b' 'd' 'c'
  # A body's substitutions come after the top-level commands, so a pipe into a
  # shell is read in order (destructive-guard reads the segment before).
  segs_are 'a body substitution comes after the pipe the body feeds' \
    $'cat <<EOF |\n$(date)\nrm -rf ~\nEOF\nbash' 'cat' 'bash' 'date'
  segs_are 'an assignment prefix is a word of its command' 'FOO=bar git status' 'FOO=bar git status'
  segs_are 'keywords are not words of a command' 'if a; then b; fi' 'a' 'b'
  segs_are 'a redirect with no command calls no callback' '> f'
}

# --- word text and quoting provenance ---------------------------------------
wq_seen=""
wq_collect() {
  [[ -n "$wq_seen" ]] || wq_seen="$(printf '%s|' "$@")${HOOK_SEG_WORD_QUOTED[*]}"
}
words_are() {
  local desc=$1 cmd=$2 want=$3
  wq_seen=""
  hook::bash_parse_segments_shfmt "$cmd" wq_collect
  if [[ "$wq_seen" == "$want" ]]; then ok "$desc"; else fail "$desc: got [$wq_seen], want [$want]"; fi
}
# shellcheck disable=SC2016  # the expansions are the command text under test
{
  words_are 'written, double-quoted, escaped' 'cat "a" b\ c' 'cat|a|b c|0 2 1'
  words_are 'quoted spans side by side are all quoted' "x 'a'\"b\"" 'x|ab|0 2'
  words_are 'a quoted span joined to plain text' 'x a"b"' 'x|ab|0 1'
  words_are 'an empty quoted word' 'x ""' 'x||0 2'
  words_are 'a double-quoted escape' 'x "a\"b\\c"' 'x|a"b\c|0 2'
  words_are 'ANSI-C quoting decodes' "x \$'a\\nb'" $'x|a\nb|0 2'
  words_are 'a backslash-newline joins the word' $'x a\\\nb' 'x|ab|0 1'
  words_are 'a parameter keeps its text' 'x $HOME/a "${y}b"' 'x|$HOME/a|${y}b|0 0 2'
  words_are 'a substitution keeps its text' 'x $(y z)' 'x|$(y z)|0 0'
  words_are 'multibyte text stays whole' 'x "héllo ✓" 日本語' 'x|héllo ✓|日本語|0 2 0'
  words_are 'a span after multibyte text keeps its place' 'é $(y) "$z"' 'é|$(y)|$z|0 0 2'
}

# --- the redirection half of a segment --------------------------------------
redirs_seen=()
redirs_collect() {
  local rec="ARGV:$*" j
  for ((j = 0; j < ${#HOOK_SEG_REDIR_OP[@]}; j++)); do
    rec+=" R:${HOOK_SEG_REDIR_OP[j]}|${HOOK_SEG_REDIR_FD[j]}|${HOOK_SEG_REDIR_TARGET[j]}|${HOOK_SEG_REDIR_QUOTED[j]}|${HOOK_SEG_REDIR_OPAQUE[j]}"
  done
  redirs_seen+=("$rec")
}
redirs_are() {
  local desc=$1 cmd=$2 got want
  shift 2
  redirs_seen=()
  hook::bash_parse_segments_shfmt "$cmd" redirs_collect
  got="${redirs_seen[*]-}"
  want="$*"
  if [[ "$got" == "$want" ]]; then ok "$desc"; else fail "$desc: got [$got], want [$want]"; fi
}
redirs_are 'quoted target with whitespace is one word' 'echo x > "/dev/null ../etc"' \
  'ARGV:echo x R:>||/dev/null ../etc|1|0'
redirs_are 'here-doc opener then a glued redirect' $'cat <<EOF>file\nEOF' \
  'ARGV:cat R:<<||EOF|0|0 R:>||file|0|0'
redirs_are 'fd dup then a stdout redirect' 'echo x 2>&1 > file' \
  'ARGV:echo x R:>&|2|1|0|0 R:>||file|0|0'
redirs_are 'redirect ahead of the command word' '>file echo x' 'ARGV:echo x R:>||file|0|0'
redirs_are 'append and a stderr redirect' 'echo x >>f 2>err' 'ARGV:echo x R:>>||f|0|0 R:>|2|err|0|0'
redirs_are 'a here-string' 'read x <<<abc' 'ARGV:read x R:<<<||abc|0|0'
redirs_are 'a process substitution target is opaque' 'echo x > <(y)' \
  'ARGV:echo x R:>||<(y)|0|1' 'ARGV:y'
redirs_are '&> writes the file as > does' 'echo x &>f' 'ARGV:echo x R:>||f|0|0'
redirs_are 'a redirected block reports its target' '{ a; } >f' 'ARGV:} R:>||f|0|0' 'ARGV:a'
redirs_are 'a redirected subshell reports its target' '(a) >f' 'ARGV:) R:>||f|0|0' 'ARGV:a'

# --- HOOK_HEREDOC_BODIES ------------------------------------------------------
hd_are() {
  local desc=$1 cmd=$2 want=$3 got
  segs=()
  hook::bash_parse_segments_shfmt "$cmd" collect
  got=$(
    IFS='|'
    printf '%s' "${HOOK_HEREDOC_BODIES[*]-}"
  )
  if [[ "$got" == "$want" ]]; then ok "$desc"; else fail "$desc: got [$got], want [$want]"; fi
}
hd_are 'three on one line: quoted, <<- double-quoted, unquoted' \
  $'cat <<\'A\' <<-"B" <<C\na\nA\n\tb\n\tB\nc\nC\necho done' '21 25 1 1 A|25 31 1 1 B|31 35 0 1 C'
hd_are 'a multibyte body is counted in bytes' $'cat <<\'E\'\né\nE\n' '10 15 1 1 E'
hd_are 'a closing parenthesis ends the delimiter' $'(cat <<\'E\')\nx\nE\necho done' '12 16 1 1 E'
hd_are 'an opener inside double quotes is not one' $'echo "<<\'EOF\'"\nx\nEOF' ''
hd_are 'an empty body' $'cat <<E\nE\nx' '8 10 0 1 E'
hd_are 'a backslash-quoted delimiter' $'cat <<\\E\nx\nE\n' '9 13 1 1 E'

# --- the caller's locale is put back -----------------------------------------
(
  # shellcheck disable=SC2030,SC2031
  declare -x LC_ALL=C.UTF-8
  mb='é日'
  before=${#mb}
  # shellcheck disable=SC2016  # the substitution is the command text under test
  hook::bash_parse_segments_shfmt 'echo $(x) é' :
  now=$(declare -p LC_ALL 2>/dev/null)
  if [[ "${#mb}" == "$before" && "$now" == 'declare -x LC_ALL="C.UTF-8"' ]]; then
    ok "the caller's LC_ALL comes back"
  else
    fail "the caller's LC_ALL came back as [$now], \${#mb} $before -> ${#mb}"
  fi
)

# --- the guard refuses when no parse comes back -------------------------------
# reader_exit <PATH> <timeout>: the reader run on a clean command in a child; the
# status it exits with, and in _T_CB whether the callback ran.
# shellcheck disable=SC2016  # the child shell expands these
reader_child='source "$1/lib/hook-utils.sh"; HOOK_BPS_TIMEOUT=$2; cb() { printf "CALLED\n"; }; PATH=$3; hook::bash_parse_segments_shfmt "git status" cb; printf "RETURNED\n"'
BASH_BIN=$(type -P bash)
refused_with() {
  local desc=$1 path=$2 t=${3:-5} out rc s0 s1
  s0=$SECONDS
  # A HOME with no ~/.local/bin/shfmt, which the reader would otherwise use.
  mkdir -p "$_T_TMP/nohome"
  out=$(HOME="$_T_TMP/nohome" "$BASH_BIN" -c "$reader_child" -- "$_T_ROOT" "$t" "$path" 2>&1)
  rc=$?
  s1=$SECONDS
  if ((rc == 2)) && [[ "$out" == *BLOCKED* && "$out" != *CALLED* && "$out" != *RETURNED* ]]; then
    ok "$desc (exit 2, $((s1 - s0)) s)"
  else
    fail "$desc: exit $rc, output [$out]"
  fi
}
stub_dir() { # <name> -> creates $_T_TMP/<name> holding links to the tools it is given
  local d="$_T_TMP/$1" t
  shift
  mkdir -p "$d"
  for t in "$@"; do ln -s "$(type -P "$t")" "$d/$t"; done
  printf '%s' "$d"
}
stub_shfmt() { # <dir> <body>
  printf '#!%s\n%s\n' "$BASH_BIN" "$2" >"$1/shfmt"
  chmod +x "$1/shfmt"
}

# Missing: jq resolves, shfmt does not.
refused_with 'refused when shfmt is missing' "$(stub_dir no-shfmt jq)"
# Missing the other way: shfmt resolves, jq does not.
d=$(stub_dir no-jq shfmt)
refused_with 'refused when jq is missing' "$d"
# Exits non-zero, with no syntax error to blame.
d=$(stub_dir fails jq timeout)
stub_shfmt "$d" 'exit 3'
refused_with 'refused when shfmt exits non-zero' "$d"
# Exits zero with output jq cannot read.
d=$(stub_dir garbage jq timeout)
stub_shfmt "$d" 'printf "not json"'
refused_with 'refused when shfmt prints no JSON' "$d"
# Runs past the stated bound.
d=$(stub_dir slow jq sleep)
stub_shfmt "$d" 'exec sleep 30'
refused_with 'refused when shfmt exceeds the timeout' "$d" 1
# A syntax error from the real shfmt.
# shellcheck disable=SC2016  # the child shell expands these
out=$("$BASH_BIN" -c 'source "$1/lib/hook-utils.sh"; hook::bash_parse_segments_shfmt "echo (" :' -- "$_T_ROOT" 2>&1)
rc=$?
if ((rc == 2)) && [[ "$out" == *BLOCKED* ]]; then
  ok 'a syntax error is refused'
else
  fail "a syntax error: exit $rc, [$out]"
fi
# The refusal names its cause, which is what the model can act on.
# reason_is <desc> <expected text> <PATH> [timeout] [HOME]
reason_is() {
  local out
  out=$(HOME=${5:-$HOME} "$BASH_BIN" -c "$reader_child" -- "$_T_ROOT" "${4:-5}" "$3" 2>&1)
  if [[ "$out" == *"$2"* ]]; then ok "$1"; else fail "$1: [$2] not in [$out]"; fi
}
nohome="$_T_TMP/nohome"
reason_is 'the refusal names a missing shfmt' 'shfmt is not on PATH' "$(stub_dir no-shfmt jq)" 5 "$nohome"
reason_is 'the refusal names a missing jq' 'jq is not on PATH' "$(stub_dir no-jq shfmt)"
reason_is 'the refusal names the timeout' 'shfmt ran past 1 s' "$(stub_dir slow jq sleep)" 1
# shellcheck disable=SC2016  # the child shell expands these
out=$("$BASH_BIN" -c 'source "$1/lib/hook-utils.sh"; hook::bash_parse_segments_shfmt "cat <<E; echo x" :' -- "$_T_ROOT" 2>&1)
if [[ "$out" == *'shfmt rejects it as bash: '*'unclosed here-document'* ]]; then
  ok 'the refusal quotes the syntax error shfmt reports'
else
  fail "the refusal for a syntax error: [$out]"
fi
# A cloud session whose SessionStart install failed: the refusal says so.
cloudhome="$_T_TMP/cloudhome"
mkdir -p "$cloudhome/.local/state/claude-guardrails"
printf 'download failed: curl exit 6\n' >"$cloudhome/.local/state/claude-guardrails/shfmt-install-failed"
reason_is 'the refusal names a failed cloud install' \
  "the session's shfmt install failed: download failed: curl exit 6" "$(stub_dir no-shfmt jq)" 5 "$cloudhome"
# A shfmt in ~/.local/bin is used when PATH lacks it: the cloud install's target.
lbhome="$_T_TMP/lbhome"
mkdir -p "$lbhome/.local/bin"
ln -s "$(type -P shfmt)" "$lbhome/.local/bin/shfmt"
# shellcheck disable=SC2016  # the child shell expands these
if out=$(HOME=$lbhome "$BASH_BIN" -c 'source "$1/lib/hook-utils.sh"; cb() { printf "%s\n" "$*"; }; PATH=$2; hook::bash_parse_segments_shfmt "git status" cb' -- "$_T_ROOT" "$(stub_dir lb-no-shfmt jq)" 2>&1) &&
  [[ "$out" == 'git status' ]]; then
  ok 'a shfmt in ~/.local/bin parses when PATH lacks one'
else
  fail "a shfmt in ~/.local/bin: [$out]"
fi
# The paired success: a shfmt that answers in time, on a PATH with no sleep or
# timeout (the bound is the read -t builtin, so no timer process can be missing).
d=$(stub_dir answers jq shfmt)
# shellcheck disable=SC2016  # the child shell expands these
if out=$("$BASH_BIN" -c 'source "$1/lib/hook-utils.sh"; cb() { printf "%s\n" "$*"; }; PATH=$2; hook::bash_parse_segments_shfmt "git status" cb' -- "$_T_ROOT" "$d" 2>&1) &&
  [[ "$out" == 'git status' ]]; then
  ok 'a shfmt that answers in time returns the parse'
else
  fail "a shfmt that answers in time: [$out]"
fi

# --- each form plugins/guardrails/reference/shfmt-parse-differences.md lists --
# handled: bash runs the trailing command in some extglob mode, and the reader
# hands it to the callback. refused: the reader exits 2.
form_bash_hit() {
  local m o
  for m in +O -O; do
    o=$(cd "$_T_TMP" && exec "$BASH_BIN" "$m" extglob -c "$1" 2>&1 >/dev/null </dev/null)
    [[ $'\n'"$o"$'\n' == *$'\nHIT\n'* ]] && return 0
  done
  return 1
}
form() { # <handled|refused> <command>
  local want=$1 cmd=$2 out rc=0
  form_bash_hit "$cmd" || {
    fail "doc form: bash does not run HIT in [$cmd], so the row proves nothing"
    return
  }
  out=$(hook::bash_parse_segments_shfmt "$cmd" hit_print 2>/dev/null) || rc=$?
  if [[ "$want" == refused ]]; then
    if ((rc == 2)); then ok "doc form refused: $cmd"; else fail "doc form $cmd: want refused, exit $rc, [$out]"; fi
  elif ((rc == 0)) && [[ $'\n'"$out"$'\n' == *$'\necho HIT\n'* ]]; then
    ok "doc form handled: $cmd"
  else
    fail "doc form $cmd: want handled, exit $rc, [$out]"
  fi
}
hit_print() { printf '%s\n' "$*"; }
# shellcheck disable=SC2016  # the substitutions are the command text under test
{
  # Extglob.
  form handled '!(x)#; echo HIT >&2'
  form handled '@(x)#; echo HIT >&2'
  form handled 'echo @(a|b)#; echo HIT >&2'
  form handled 'echo @(x;y)#; echo HIT >&2'
  form handled '!(echo HIT >&2)'
  form handled 'echo @(`echo HIT >&2`)'
  form handled 'echo @(<(echo HIT >&2))'
  form refused 'f@()#; echo HIT >&2'
  # Nested: the extglob-off rewrite applies its edits in offset order.
  form handled $'cat <<E2; !(x)#\n$(cat <<E1; !(x)#\n$(echo HIT >&2\n)\nE1\n)\nE2'
  # The extglob-off reading runs a here-doc before its open quote's error.
  form refused $'!(x)#\'\ncat <<B\n$(echo HIT >&2)\nB\n\' ; cat <<C\nc\nC'
  # case patterns.
  form handled 'echo $(case x in a|esac) :;; esac)#; echo HIT >&2'
  form handled 'echo $(case x in esac)#; echo HIT >&2'
  form handled 'echo $(case x in (a) :;; esac)#; echo HIT >&2'
  # [[ =~ ]].
  form handled '[[ x =~ (a|b) ]]; echo HIT >&2'
  form handled '[[ x =~ k=(a|b) ]]; echo HIT >&2'
  form handled '[[ x =~ (a b) ]]; echo HIT >&2'
  form handled '[[ x =~ a|b ]]; echo HIT >&2'
  # A # after ).
  form handled 'a=(x)#; echo HIT >&2'
  form handled $'a=(x\ny)#; echo HIT >&2'
  form handled 'echo $(echo ${x/)/})#; echo HIT >&2'
  form handled 'echo $(echo ${x/(/})#; echo HIT >&2'
  # Arithmetic.
  form refused '((a|b) ); echo HIT >&2'
  form refused 'echo $((a|b) ); echo HIT >&2'
  form refused '((:)); echo HIT >&2'
  # Text bash reads lazily.
  form refused 'cat <<E; echo HIT >&2'
  form refused 'echo `case`; echo HIT >&2'
  form refused $'echo HIT >&2\nit\'s'
  form refused $'echo HIT >&2\necho (('
  # Other forms.
  form refused 'x[1]=2 echo HIT >&2'
  form refused $'echo HIT >&2\nprintf \xff'
  # Backticks: bash ends them at the first unescaped backtick.
  form refused "echo \`\$'\`; echo HIT >&2 #'\`"
  form refused "echo \`'\`; echo HIT >&2 #'"
  form refused $'echo `cat <<E`\necho HIT >&2\nE'
  # An opener before backticks that span lines, and an empty body: the reader
  # would place the body inside the backticks.
  form refused $'cat <<A; echo `:\necho HIT >&2`\nA'
  form handled 'echo `echo \`:\`#; echo HIT >&2`'
  form handled 'echo `echo \`echo \\\`echo HIT >&2\\\`\``'
  # A backslash-newline bash joins before it reads an unquoted here-doc body.
  form handled $'cat <<E\n$\\\n(echo HIT >&2)\nE'
  form handled $'cat <<E\nit\'s $\\\n(echo HIT >&2) ok\'\nE'
}
# CR LF: bash's last word carries the CR, so the guard's word is the written one.
segs_are 'doc form handled: a CR before a newline is dropped' $'git reset --hard\r\n' 'git reset --hard'

# --- block-dangerous-git refuses the bypasses the old reader missed ----------
# An attended session turns a refusal into an ask (refuse.sh).
unset CLAUDE_CODE_SESSION_ATTENDED
guard_rc() { # <guard path> <command> -> its exit status under the shfmt reader
  local payload
  payload=$(jq -cn --arg c "$2" --arg d "$_T_ROOT" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,session_id:"t",hook_event_name:"PreToolUse"}')
  (cd "$_T_ROOT" && "$BASH_BIN" "$1" <<<"$payload" >/dev/null 2>&1)
}
guard_blocks() { # <desc> <guard path> <command>
  guard_rc "$2" "$3"
  local rc=$?
  if ((rc == 2)); then ok "$1"; else fail "$1: exit $rc"; fi
}
GIT_GUARD="$_T_ROOT/plugins/guardrails/hooks/block-dangerous-git.sh"
ROOT_GUARD="$_T_ROOT/plugins/guardrails/hooks/block-root-delete-target.sh"
# shellcheck disable=SC2016  # the substitutions are the command text under test
{
  guard_blocks 'round-4: an esac pattern inside $(…) then #' "$GIT_GUARD" \
    'echo $(case x in a|esac) :;; esac)#; git reset --hard'
  guard_blocks 'nested escaped backtick' "$GIT_GUARD" \
    'echo `echo \` #\`; git reset --hard'
  guard_blocks '$(( with a backticked case, then #' "$GIT_GUARD" \
    'echo $((`case 1 in 1) echo 1;; esac`))#; git reset --hard'
  guard_blocks 'extglob holding a backticked ), then #' "$GIT_GUARD" \
    'echo @(`:)`)#; git reset --hard'
  guard_blocks '${…} holding a ), then #' "$GIT_GUARD" \
    'echo $(echo ${x/)/})#; git reset --hard'
  guard_blocks '${…} holding a (, then #' "$GIT_GUARD" \
    'echo $(echo ${x/(/})#; git reset --hard'
  guard_blocks 'a backtick in an abandoned $( ) in a here-doc body (git)' "$GIT_GUARD" \
    $'cat <<E\n$(cat <<\'X\'\n`\nX\n)\nit\'s $(git reset --hard) ok\'\nE'
  guard_blocks 'a backtick in an abandoned $( ) in a here-doc body (rm)' "$ROOT_GUARD" \
    $'cat <<E\n$(cat <<\'X\'\n`\nX\n)\nit\'s $(rm -rf /) ok\'\nE'
  guard_blocks 'apostrophes around $( ) after $(case …) in a here-doc body' "$GIT_GUARD" \
    $'cat <<E\n$(case x in x) :;; esac) it\'s $(git reset --hard) ok\'\nE'
  guard_blocks 'apostrophes around $( ) after $(cat <<X …) in a here-doc body' "$GIT_GUARD" \
    $'cat <<E\n$(cat <<X\nx\nX\n) it\'s $(git reset --hard) ok\'\nE'
}
# The paired allow: a clean command stays allowed under the same reader.
guard_rc "$GIT_GUARD" 'git status'
rc=$?
if ((rc == 0)); then ok 'a clean git command is allowed'; else fail "a clean git command: exit $rc"; fi

# --- every kind of call site fails closed on a refusal ----------------------
# The refusal is `exit 2` inside the library, so a call site that parsed in a
# subshell would exit only that and let the call through. Each row reaches one
# kind of call site with text shfmt rejects (`x[1]=2 cmd`, which bash runs) and
# wants exit 2 with the reader's refusal; its pair, the same text with a plain
# assignment, wants exit 0, so the refusal is what denied it.
refuses_at() { # <desc> <hook> <tool> <refused command> <allowed command>
  local payload rc err
  for c in "$4" "$5"; do
    payload=$(jq -cn --arg t "$3" --arg c "$c" --arg d "$_T_ROOT" '{tool_name:$t,tool_input:{command:$c},cwd:$d,session_id:"t",hook_event_name:"PreToolUse"}')
    err=$(cd "$_T_ROOT" && "$BASH_BIN" "$2" "${@:6}" <<<"$payload" 2>&1 >/dev/null)
    rc=$?
    if [[ "$c" == "$4" ]]; then
      if ((rc == 2)) && [[ "$err" == *'got no parse'* ]]; then ok "$1: refused"; else fail "$1: exit $rc, [${err:0:300}]"; fi
    else
      if ((rc == 0)); then ok "$1: the plain pair is allowed"; else fail "$1: the plain pair exits $rc, [${err:0:300}]"; fi
    fi
  done
}
GD="$_T_ROOT/plugins/guardrails/hooks"
# shellcheck disable=SC2016  # the commands are the text under test
{
  refuses_at 'top-level parse in a guard' "$GD/block-cd-prefix.sh" Bash \
    'cd /tmp; x[1]=2 echo hi' 'cd /tmp; x=2 echo hi'
  refuses_at 'an sh -c operand re-parsed from a callback' "$GIT_GUARD" Bash \
    "bash -c 'x[1]=2 git status'" "bash -c 'x=2 git status'"
  refuses_at "a git ! alias re-parsed from a callback" "$GD/block-no-verify.sh" Bash \
    "git -c 'alias.st=!x[1]=2 git status' st" "git -c 'alias.st=!x=2 git status' st"
  refuses_at 'the PowerShell reduction parsed by a guard' "$GD/block-convention-violation.sh" PowerShell \
    'x[1]=2 git status' 'x=2 git status'
  refuses_at 'the shared library entry (github-post)' "$GD/block-github-post-content.sh" Bash \
    'x[1]=2 gh pr comment 1 --body hi' 'x=2 gh pr comment 1 --body hi'
  refuses_at 'the dispatcher shared parse' "$GD/run-guards.sh" Bash \
    'x[1]=2 git status' 'x=2 git status' block-dangerous-git.sh block-no-verify.sh block-cd-prefix.sh
  refuses_at 'a callback name passed to a library (worktree-path-lib)' \
    "$_T_ROOT/plugins/source-control/hooks/worktree-add-containment-gate.sh" Bash \
    "bash -c 'x[1]=2 git worktree add ../x'" "bash -c 'x=2 git worktree add ../x'"
  # After a guard exits deep, run-guards runs the rest of the chain in a forked
  # process (run_guards::run_rest); a refusal there still denies.
  printf '#!/usr/bin/env bash\nd() { if (($1)); then d $(($1 - 1)); else exit 0; fi; }\nd 100\n' >"$_T_TMP/deep0.sh"
  refuses_at 'the forked rest of the chain after a deep exit' "$GD/run-guards.sh" Bash \
    'x[1]=2 git status' 'x=2 git status' "$_T_TMP/deep0.sh" block-dangerous-git.sh
  refuses_at 'repo-hygiene destructive-guard' \
    "$_T_ROOT/plugins/repo-hygiene/skills/clean/scripts/destructive-guard.sh" Bash \
    'x[1]=2 echo hi' 'x=2 echo hi'
}

printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
((FAIL == 0))
