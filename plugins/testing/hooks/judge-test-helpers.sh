# shellcheck shell=bash
# Fixtures shared by test-judge-bg.test.sh, test-judge.test.sh and
# test-judge-start.test.sh: a throwaway repository, the option gates, a stub
# judge behind TEST_JUDGE_CMD, and writers for the state test-scan leaves.
# No test calls a real model: a `claude` first on PATH fails loudly.
# shellcheck disable=SC2034 # read by the sourcing test

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG TEST_JUDGE_ACTIVE CLAUDE_CODE_SESSION_ATTENDED
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
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
# Only the suite's own shell cleans up: a forked child that gets a signal before its
# exec still holds this trap.
trap '[[ "$BASHPID" == "$$" ]] && { jobs -p | xargs -r kill 2>/dev/null; rm -rf "$TMP"; }' EXIT
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
# The recorders skip files under the temp root. These fixtures live there, so
# point the root at a directory that holds none of them (#6037).
export TEST_SCAN_SKIP_ROOT="$TMP/judge-skip-root"
export CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED=true CLAUDE_PLUGIN_OPTION_TEST_JUDGE_ENABLED=true
export TEST_JUDGE_DEBOUNCE=0 TEST_JUDGE_CMD="$TMP/judge-stub.sh" STUB_DIR="$TMP/stub"
DATA="$TMP/data"
TDIR="$TMP/transcripts/-repo"
mkdir -p "$TDIR"
sha256() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi; }
PKEY="$(printf '%s\n%s' "$REPO" "$TDIR" | sha256 | cut -c1-16)"

# The stub judge: logs its arguments (one file per call, NUL-separated), its
# cwd and TEST_JUDGE_ACTIVE, then answers per STUB_MODE for every
# `block <ordinal> <start>-<end> <name>` line of its prompt: FLAG (quoting the
# block's first line, with a diff that edits it) when the name holds "flag",
# else PASS. STUB_SLEEP delays the answer. STUB_MODE=denied answers UNKNOWN,
# "the Read permission was denied", for a name holding "deny" and lists a
# Read in the result's permission_denials; deniedtext gives the same answer
# with no denial listed.
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
  implquote) second="  ${STUB_IMPL_QUOTE:-}  " ;;
  otherfile) diff="$(printf 'other\n' | diff -u --label a/other.txt --label b/other.txt - <(printf 'changed\n'))" ;;
  denied | deniedtext)
    if [[ "$name" == *deny* ]]; then
      verdict=UNKNOWN first=""
      why="I could not read the test file because the Read permission was denied, so I have no evidence for this block."
    fi
    ;;
  esac
  verdicts+=("$(jq -cn --arg n "$name" --argjson o "$ord" --arg v "$verdict" --arg q "$first" --arg q2 "${second:-}" --arg d "$diff" \
    --arg why "$why" '{name: $n, ordinal: $o, verdict: $v, evidence: ([$q] + if $q2 == "" then [] else [$q2] end), source: "stub", diff: $d}
      + if $why == "" then {} else {reason: $why} end')")
done < <(grep '^block ' <<<"$prompt")
result="$(printf '%s\n' "${verdicts[@]}" | jq -cs '{verdicts: .}')"
denials='[]'
[[ "${STUB_MODE:-ok}" == denied ]] &&
  denials="$(jq -cn --arg f "$file" '[{tool_name: "Read", tool_use_id: "toolu_stub", tool_input: {file_path: $f}}]')"
jq -cn --arg r "Here you go: $result" --argjson d "$denials" \
  '{type: "result", subtype: "success", is_error: false, result: $r, permission_denials: $d}'
EOF
chmod +x "$TMP/judge-stub.sh"

# Windows conditions on Linux: WIN_JQ is a directory holding a `jq` that acts
# like the native Windows jq.exe (every LF it writes becomes CRLF unless it is
# given -b), and win <cmd>... runs a command with that jq first on PATH, the
# msys OSTYPE the hooks see under Git Bash, and no CLAUDE_PROJECT_DIR (so the
# payload's backslash cwd is the project directory).
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

# stub_calls: how many times the stub judge ran. stub_args <n>: the nth call's
# arguments, one per line (1-based, in call order).
stub_calls() { find "$STUB_DIR" -name 'call-*.args' | wc -l; }
stub_args() { tr '\0' '\n' <"$(find "$STUB_DIR" -name 'call-*.args' | sort | sed -n "${1}p")"; }
stub_reset() { rm -f "$STUB_DIR"/call-*; }

# transcript <sid> <model>...: a main transcript whose assistant lines carry
# those models, in order. subagent <sid> <agent> <model>: a subagent's.
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

# record <sid> <id> <file> <blocks json|null> [agent] [lines json|null] [ok markers] [written_at]:
# the session record test-scan writes for one write; CREATE=true marks it a create.
record() {
  local d="$DATA/sessions/$PKEY/$1"
  mkdir -p "$d"
  jq -n --arg f "$3" --arg r "$REPO" --argjson b "$4" --arg a "${5:-}" --argjson l "${6:-null}" \
    --argjson ok "${7:-0}" --arg w "${8:-$(date -u +%FT%TZ)}" --argjson c "${CREATE:-false}" \
    '{file: $f, repo: $r, agent_id: (if $a == "" then null else $a end), create: $c, blocks: $b,
      lines: $l, ok_markers: $ok, written_at: $w}' >"$d/$2.json"
}
# blocks <name:ordinal:start:end>...: a blocks array.
blocks() {
  local b out="[]" n o s e
  for b in "$@"; do
    IFS=: read -r n o s e <<<"$b"
    out="$(jq -c --arg n "$n" --argjson o "$o" --argjson s "$s" --argjson e "$e" '. + [{name: $n, ordinal: $o, start: $s, end: $e}]' <<<"$out")"
  done
  printf '%s' "$out"
}

# payload <sid> <id> <file> [extra jq object]: a hook payload.
payload() {
  jq -cn --arg s "$1" --arg u "$2" --arg f "$3" --arg t "$TDIR/$1.jsonl" --arg c "$REPO" --argjson x "${4:-{\}}" \
    '{hook_event_name: "PostToolUse", tool_name: "Edit", session_id: $s, tool_use_id: $u, transcript_path: $t,
      cwd: $c, tool_input: {file_path: $f}, stop_hook_active: false} + $x'
}

# verdict_files <sid>: the ledger files for a session. verdict_of <sid> <name>:
# the ledger entry for that block name, compact.
verdict_files() { find "$DATA/verdicts/$PKEY/$1" -name '*.json' 2>/dev/null; }
verdict_of() {
  local f
  for f in $(verdict_files "$1"); do jq -c --arg n "$2" 'select(.name == $n)' "$f"; done
}

# js_file <path> <name>...: a Vitest file with one test per name, each three
# lines (declaration, assertion, close) after a two-line header, so the kth
# test spans lines 3k to 3k+2.
js_file() {
  local p="$1" n
  shift
  printf '%s\n' "import { test, expect } from 'vitest';" "import { add } from './add';" >"$p"
  for n in "$@"; do
    printf '%s\n' "test('$n', () => {" "  expect(add(1, 2)).toBe(3);" "});" >>"$p"
  done
}
