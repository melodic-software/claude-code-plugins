# shellcheck shell=bash
# No test calls a real model: a `claude` first on PATH fails loudly.
# shellcheck disable=SC2034 # read by the sourcing test

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG TEST_JUDGE_ACTIVE CLAUDE_CODE_SESSION_ATTENDED
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/test-ok-fail.sh
source "$HOOK_DIR/../lib/test-ok-fail.sh"
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then ok "$1"; else fail "$1 (missing: $3; got: ${2:0:600})"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then ok "$1"; else fail "$1 (unexpected: $3; got: ${2:0:600})"; fi; }
assert_empty() { if [[ -z "$2" ]]; then ok "$1"; else fail "$1 (got: ${2:0:600})"; fi; }
finish() {
  echo
  echo "$PASS passed, $FAIL failed"
  ((FAIL == 0))
}

TMP="$(mktemp -d)"
SYS_TMP="${TMPDIR:-/tmp}"
SYS_TMP="${SYS_TMP%/}"
if [[ -z "$TMP" || ! -d "$TMP" || "$TMP" != "$SYS_TMP"/?* ]]; then
  echo "abort: mktemp gave '$TMP', not a directory under $SYS_TMP" >&2
  exit 1
fi
tmp_kill() {
  [[ -n "$TMP" && -d "$TMP" && "$2" == "$TMP"/* ]] || return 0
  if command -v pkill >/dev/null; then
    pkill "-$1" -f "$2"
    return 0
  fi
  local f p
  while IFS= read -r f; do
    p="${f#/proc/}"
    p="${p%/cmdline}"
    [[ "$p" == "$$" ]] || kill "-$1" "$p" 2>/dev/null
  done < <(grep -lF -- "$2" /proc/[0-9]*/cmdline 2>/dev/null)
  return 0
}
trap '[[ "$BASHPID" == "$$" && -n "$TMP" && -d "$TMP" ]] && {
  jobs -p | xargs -r kill 2>/dev/null
  tmp_kill TERM "$TMP/"
  sleep 0.5
  tmp_kill KILL "$TMP/"
  timeout 60 rm -rf -- "$TMP" || echo "cleanup: $TMP was not removed within 60 s; left in place" >&2
}' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/src" "$TMP/bin" "$TMP/stub"
git -C "$REPO" init -q -b feat/judge-test
printf 'scratch/\n.work/\n' >"$REPO/.gitignore"
printf 'other\n' >"$REPO/other.txt"
git -C "$REPO" add -A && git -C "$REPO" -c user.name=t -c user.email=t@t commit -qm init
cat >"$TMP/bin/claude" <<EOF
#!/usr/bin/env bash
echo "a real claude was called" >>"$TMP/real-claude-called"
exit 97
EOF
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"
export CLAUDE_PLUGIN_DATA="$TMP/data" CLAUDE_PROJECT_DIR="$REPO" HOME="$TMP/home"
export TEST_SCAN_SKIP_ROOT="$TMP/judge-skip-root"
export CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED=true
export TEST_JUDGE_DEBOUNCE=0 TEST_JUDGE_CMD="$TMP/judge-stub.sh" STUB_DIR="$TMP/stub"
export TEST_JUDGE_REUSE=0
DATA="$TMP/data"
TDIR="$TMP/transcripts/-repo"
mkdir -p "$TDIR"
sha256() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi; }
PKEY="$(printf '%s\n%s' "$REPO" "$TDIR" | sha256 | cut -c1-16)"

cat >"$TMP/judge-stub.sh" <<'EOF'
#!/usr/bin/env bash
n="$(date +%s)-$$-$RANDOM"
printf '%s\0' "$@" >"$STUB_DIR/call-$n.args"
printf '%s %s\n' "$PWD" "${TEST_JUDGE_ACTIVE:-}" >"$STUB_DIR/call-$n.env"
sleep "${STUB_SLEEP:-0}"
prompt="${!#}"
file="$(sed -n '1s/^Judge these test blocks in \(.*\) (block .*$/\1/p' <<<"$prompt")"
rel="${file#"$PWD"/}"
case "${STUB_MODE:-ok}" in
fail) exit 1 ;;
hang)
  sleep 60 &
  echo $! >"$STUB_DIR/hang.pid"
  wait
  exit 0
  ;;
budget) echo '{"type":"result","subtype":"error_max_budget_usd","is_error":true}'; exit 1 ;;
garbage) echo 'not json'; exit 0 ;;
escape) echo '{"type":"result","result":"bad\u001b[2K\u0007 text"}'; exit 0 ;;
esac
verdicts=()
while read -r _ ord range name; do
  start="${range%-*}"
  first="$(sed -n "${start}p" "$file")"
  verdict=PASS diff="" second="" why=""
  if [[ "$name" == *flag* ]]; then
    verdict=FLAG
    sed "${start}s/\$/ \/\/ judged/" "$file" >"$STUB_DIR/mod"
    diff="$(diff -u --label "a/$rel" --label "b/$rel" "$file" "$STUB_DIR/mod")"
  fi
  case "${STUB_MODE:-ok}" in
  badquote) first="this line is not in the file" ;;
  renamed) name+=", renamed" ;;
  implquote) second="  ${STUB_IMPL_QUOTE:-}  " ;;
  otherfile) diff="$(printf 'other\n' | diff -u --label a/other.txt --label b/other.txt - <(printf 'changed\n'))" ;;
  commentdiff | realdiff)
    if [[ "$verdict" == FLAG ]]; then
      if [[ "$STUB_MODE" == commentdiff ]]; then
        awk -v n="$start" '{ print } NR == n { print "  // the expected value is 3" }' "$file" >"$STUB_DIR/mod"
      else
        awk -v n="$((start + 1))" 'NR == n { sub(/toBe\(3\)/, "toBe(1 + 2)") } { print }' "$file" >"$STUB_DIR/mod"
      fi
      diff="$(diff -u --label "a/$rel" --label "b/$rel" "$file" "$STUB_DIR/mod")"
    fi
    ;;
  denied | deniedtext)
    if [[ "$name" == *deny* ]]; then
      verdict=UNKNOWN first=""
      why="I could not read the test file because the Read permission was denied, so I have no evidence for this block."
    fi
    ;;
  esac
  verdicts+=("$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -cn --arg n "$name" --argjson o "$ord" --arg v "$verdict" --arg q "$first" --arg q2 "${second:-}" --arg d "$diff" \
    --arg why "$why" '{name: $n, ordinal: $o, verdict: $v, evidence: ([$q] + if $q2 == "" then [] else [$q2] end), source: "stub", diff: $d}
      + if $why == "" then {} else {reason: $why} end')")
done < <(grep '^block ' <<<"$prompt")
result="$(printf '%s\n' "${verdicts[@]}" | jq -cs '{verdicts: .}')"
denials='[]'
[[ "${STUB_MODE:-ok}" == denied ]] &&
  denials="$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -cn --arg f "$file" '[{tool_name: "Read", tool_use_id: "toolu_stub", tool_input: {file_path: $f}}]')"
jq -cn --arg r "Here you go: $result" --argjson d "$denials" \
  '{type: "result", subtype: "success", is_error: false, result: $r, permission_denials: $d}'
EOF
chmod +x "$TMP/judge-stub.sh"

WIN_JQ="$TMP/win-jq"
mkdir -p "$WIN_JQ"
cat >"$WIN_JQ/jq" <<EOF
#!/usr/bin/env bash
args=() bin=0
for a in "\$@"; do
  if [[ "\$a" == -b || "\$a" == --binary ]]; then bin=1; else args+=("\$a"); fi
done
((bin)) && exec "$(command -v jq)" "\${args[@]}"
set -o pipefail
"$(command -v jq)" "\${args[@]}" | perl -pe 's/\n/\r\n/'
EOF
chmod +x "$WIN_JQ/jq"
win() { env -u CLAUDE_PROJECT_DIR PATH="$WIN_JQ:$PATH" TESTING_OSTYPE=msys "$@"; }

stub_calls() { find "$STUB_DIR" -name 'call-*.args' | wc -l; }
stub_args() { tr '\0' '\n' <"$(find "$STUB_DIR" -name 'call-*.args' | sort | sed -n "${1}p")"; }
stub_reset() { rm -f "$STUB_DIR"/call-*; }

transcript() {
  local sid="$1" m
  shift
  : >"$TDIR/$sid.jsonl"
  for m in "$@"; do
    jq -cn --arg m "$m" '{type: "assistant", message: {model: $m, content: []}}' >>"$TDIR/$sid.jsonl"
  done
}
subagent() {
  mkdir -p "$TDIR/$1/subagents"
  jq -cn --arg m "$3" '{type: "assistant", message: {model: $m, content: []}}' >"$TDIR/$1/subagents/agent-$2.jsonl"
}

record() {
  local d="$DATA/sessions/$PKEY/$1"
  mkdir -p "$d"
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -n --arg f "$3" --arg r "$REPO" --argjson b "$4" --arg a "${5:-}" --argjson l "${6:-null}" \
    --argjson ok "${7:-0}" --arg w "${8:-$(date -u +%FT%TZ)}" --argjson c "${CREATE:-false}" \
    '{file: $f, repo: $r, agent_id: (if $a == "" then null else $a end), create: $c, blocks: $b,
      lines: $l, ok_markers: $ok, written_at: $w}' >"$d/$2.json"
}
blocks() {
  local b out="[]" n o s e
  for b in "$@"; do
    IFS=: read -r n o s e <<<"$b"
    out="$(jq -c --arg n "$n" --argjson o "$o" --argjson s "$s" --argjson e "$e" '. + [{name: $n, ordinal: $o, start: $s, end: $e}]' <<<"$out")"
  done
  printf '%s' "$out"
}

payload() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -cn --arg s "$1" --arg u "$2" --arg f "$3" --arg t "$TDIR/$1.jsonl" --arg c "$REPO" --argjson x "${4:-{\}}" \
    '{hook_event_name: "PostToolUse", tool_name: "Edit", session_id: $s, tool_use_id: $u, transcript_path: $t,
      cwd: $c, tool_input: {file_path: $f}, stop_hook_active: false} + $x'
}

verdict_files() { find "$DATA/verdicts/$PKEY/$1" -name '*.json' 2>/dev/null; }
verdict_of() {
  local f
  for f in $(verdict_files "$1"); do jq -c --arg n "$2" 'select(.name == $n)' "$f"; done
}

js_file() {
  local p="$1" n
  shift
  printf '%s\n' "import { test, expect } from 'vitest';" "import { add } from './add';" >"$p"
  for n in "$@"; do
    printf '%s\n' "test('$n', () => {" "  expect(add(1, 2)).toBe(3);" "});" >>"$p"
  done
}
