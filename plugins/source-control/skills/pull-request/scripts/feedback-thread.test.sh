#!/usr/bin/env bash
# Tests for feedback-thread.sh, black-box, against a real git checkout. A `gh`
# stub on PATH records every call and answers none: the tool reads nothing
# from GitHub and posts nothing, so the call log stays empty.
# shellcheck disable=SC2016  # backticks and $vars are literal fixture text

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/feedback-thread.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

HEAD=$(printf 'a%.0s' {1..40})
FIX=$(printf 'f%.0s' {1..40})
TOKEN=ghs_secretlanetoken1234567890
# The stateless installation token is ghs_ then a JWT of about 520 characters: three
# base64url segments joined by '.', each segment obviously fake. Built at run time.
SEG=$(printf 'FAKE-not_a_token%.0s' {1..10})
STATELESS="ghs""_123456_$SEG.$SEG.$SEG"
JSEG=$(printf 'eyJGAKEnotAtoken%.0s' {1..10})
JWT_TOKEN="ghs""_$JSEG.$JSEG.$JSEG"

mkdir -p "$TEST_TMPDIR/bin"
cat >"$TEST_TMPDIR/bin/gh" <<'STUB_EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
echo "gh-stub: unrouted $*" >&2
exit 1
STUB_EOF
chmod +x "$TEST_TMPDIR/bin/gh"

fixture_git() {
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -C "$STUB/ws" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false "$@"
}

# setup: a fresh case with two kept threads and a checkout at the gated head,
# whose .git/info/exclude keeps .lane/ out as the read runner's does.
setup() {
  STUB=$(mktemp -d "$TEST_TMPDIR/case.XXXXXX")
  export STUB
  mkdir -p "$STUB/scratch" "$STUB/ws/src" "$STUB/ws/docs" "$STUB/ws/.github"
  : >"$STUB/calls"
  echo 'x' >"$STUB/ws/src/a.js"
  echo 'y' >"$STUB/ws/docs/b.md"
  echo 'z' >"$STUB/ws/src/other.js"
  echo 'w' >"$STUB/ws/.github/x.yml"
  echo 'ignored.log' >"$STUB/ws/.gitignore"
  fixture_git init -q -b main
  fixture_git add -A
  fixture_git commit -q -m head
  echo /.lane/ >>"$STUB/ws/.git/info/exclude"
  cat >"$STUB/threads.json" <<EOF
{"version":1,"repository":"o/r","pr":42,"head_sha":"$HEAD",
 "threads":[
  {"id":"PRRT_a","path":"src/a.js","line":3,"review_commit":"$HEAD","root_comment_id":100,"comments":[{"id":100,"body":"null deref at line 3"}]},
  {"id":"PRRT_b","path":"docs/b.md","line":1,"review_commit":"$HEAD","root_comment_id":200,"comments":[{"id":200,"body":"typo"}]}
 ]}
EOF
}

disposition() {
  printf '%s' "$1" >"$STUB/scratch/d.json"
}

run() {
  PATH="$TEST_TMPDIR/bin:$PATH" FEEDBACK_THREADS="$STUB/threads.json" FEEDBACK_LOG="$STUB/replies.jsonl" \
    FEEDBACK_SCRATCH="$STUB/scratch" FEEDBACK_WORKSPACE="$STUB/ws" \
    bash "$SCRIPT" "$@"
}

recorded() {
  if [[ -f $STUB/replies.jsonl ]]; then wc -l <"$STUB/replies.jsonl"; else echo 0; fi
}

# list
setup
out=$(run list)
assert_eq "list prints the kept thread ids" "PRRT_a PRRT_b" "$(jq -r 'map(.id) | join(" ")' <<<"$out")"

# check-paths: path hygiene only. Any plain path in normal form passes, in or
# out of a thread's plugin, code, control and instruction files and
# .github/workflows/ included; the review lanes judge what a fix touches.
setup
for path in src/a.js docs/b.md src/other.js src/new.js plugins/q/evals/c/samples/y.json \
  plugins/p/hooks/hooks.json plugins/p/.claude-plugin/plugin.json plugins/p/AGENTS.md \
  plugins/p/skills/s/CLAUDE.md plugins/p/.claude/rules/r.md plugins/p/scripts/run.sh \
  plugins/p/.claude/settings.json plugins/p/package.json plugins/p/monitors/monitors.json \
  plugins/p/bin/tool plugins/p/.lsp.json CODEOWNERS .gitmodules .github/workflows/ci.yml \
  .GITHUB/WORKFLOWS/x.yml .github/scripts/x.mjs; do
  run check-paths "$path" >/dev/null 2>&1
  assert_exit "check-paths allows $path" 0 "$?"
done
for path in plugins/p/evals/c/../../../../.github/workflows/x.yml plugins/p/evals/c/./y.json \
  plugins/p/evals/c//y.json /src/a.js ./src/a.js "plugins/knowledge/a b.js" \
  "plugins/knowledge/hooKs/hooks.json" "plugins/knowledge/AGENTſ.md"; do
  run check-paths "$path" >/dev/null 2>&1
  assert_exit "check-paths refuses $path" 1 "$?"
done
run check-paths src/a.js ./src/a.js >/dev/null 2>&1
assert_exit "check-paths refuses a list holding one bad path" 1 "$?"
setup
echo 'fixed' >"$STUB/ws/src/other.js"
disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"fixed in src/other.js"}'
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "record takes a VALID fix made in a file no thread names" 0 "$?"

# record VALID: the uncommitted fix is checked in the working tree and the
# reply appended, with an empty fix_sha and no GitHub call
setup
echo 'guarded' >"$STUB/ws/src/a.js"
mkdir -p "$STUB/ws/.lane/scratch"
echo 'state' >"$STUB/ws/.lane/scratch/notes.txt"
echo 'log' >"$STUB/ws/ignored.log"
disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"Guarded the null case."}'
out=$(run record PRRT_a "$STUB/scratch/d.json" 2>&1)
assert_exit "a VALID record of an in-scope uncommitted fix succeeds" 0 "$?"
assert_eq "the replies file holds the disposition as written, keyed by thread" \
  '{"thread":"PRRT_a","disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"Guarded the null case."}' \
  "$(cat "$STUB/replies.jsonl")"
assert_eq "a VALID record makes no GitHub call" 0 "$(wc -l <"$STUB/calls")"
assert_contains "the tool says the reply job posts it" "$out" "reply job posts it"
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a second record on the same thread is refused" 1 "$?"
assert_eq "the refused second record appends nothing" 1 "$(recorded)"
# the CLI's empty scrub stubs at the top of the checkout are no fix: an
# untracked empty one is passed over; one with content, or a stub name below
# the top, is a plain path the record takes (the patch collector drops a
# root stub from the patch)
setup
echo 'guarded' >"$STUB/ws/src/a.js"
: >"$STUB/ws/package.json"
: >"$STUB/ws/.env"
disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"fixed"}'
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "untracked empty scrub stubs do not refuse the VALID record" 0 "$?"
setup
echo 'guarded' >"$STUB/ws/src/a.js"
echo 'TOKEN=x' >"$STUB/ws/.env"
disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"fixed"}'
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a scrub-stub name with content does not refuse the VALID record" 0 "$?"
setup
echo 'guarded' >"$STUB/ws/src/a.js"
mkdir -p "$STUB/ws/src/nested" && : >"$STUB/ws/src/nested/package.json"
disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"fixed"}'
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "an empty stub name below the top of the checkout does not refuse the VALID record" 0 "$?"
# The lane's sandbox masks a dotfile in the checkout with /dev/null, a device git
# will not add: it is no fix, while a symlink to /dev/null still is one.
if bwrap --bind / / --dev /dev true 2>/dev/null; then
  setup
  echo 'guarded' >"$STUB/ws/src/a.js"
  : >"$STUB/ws/.bash_profile"
  disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"fixed"}'
  PATH="$TEST_TMPDIR/bin:$PATH" FEEDBACK_THREADS="$STUB/threads.json" FEEDBACK_LOG="$STUB/replies.jsonl" \
    FEEDBACK_SCRATCH="$STUB/scratch" FEEDBACK_WORKSPACE="$STUB/ws" \
    bwrap --bind / / --dev /dev --ro-bind /dev/null "$STUB/ws/.bash_profile" \
    bash "$SCRIPT" record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
  assert_exit "a sandbox /dev/null mask over a dotfile does not refuse the VALID record" 0 "$?"
fi
setup
echo 'guarded' >"$STUB/ws/src/a.js"
ln -s /dev/null "$STUB/ws/.bash_profile"
disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"fixed"}'
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "an untracked symlink to /dev/null is a plain path the VALID record takes" 0 "$?"

setup
disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"note":"fix_sha left out"}'
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a VALID record with fix_sha left out succeeds" 0 "$?"
assert_eq "a left-out fix_sha is recorded empty" '' "$(jq -r .fix_sha "$STUB/replies.jsonl")"

# record INCORRECT and UNCERTAIN: no API call at all
setup
disposition '{"disposition":"INCORRECT","evidence":["src/a.js:3","docs/b.md:1"],"note":"Line 3 is guarded at src/a.js:2."}'
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "an INCORRECT record succeeds" 0 "$?"
disposition '{"disposition":"UNCERTAIN","note":"Needs the vendor docs to settle."}'
run record PRRT_b "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "an UNCERTAIN record with no evidence succeeds" 0 "$?"
assert_eq "both are recorded in order" "INCORRECT UNCERTAIN" "$(jq -rs 'map(.disposition) | join(" ")' "$STUB/replies.jsonl")"
assert_eq "INCORRECT and UNCERTAIN make no API call" 0 "$(wc -l <"$STUB/calls")"

# a note naming a token placeholder and a commit sha is recorded, still with no API call
setup
disposition "{\"disposition\":\"UNCERTAIN\",\"note\":\"The fixture uses ghs_job; see $FIX.\"}"
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a note naming a token placeholder and a commit sha is recorded" 0 "$?"
assert_eq "the placeholder note record makes no API call" 0 "$(wc -l <"$STUB/calls")"

# the note limit counts code points, as the reply job does: 2000 emoji pass,
# 2001 are refused
setup
note=$(printf '😀%.0s' {1..2000})
disposition "{\"disposition\":\"INCORRECT\",\"evidence\":[\"src/a.js:3\"],\"note\":\"$note\"}"
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a note of exactly 2000 emoji is recorded" 0 "$?"
setup
disposition "{\"disposition\":\"INCORRECT\",\"evidence\":[\"src/a.js:3\"],\"note\":\"${note}😀\"}"
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a note of 2001 emoji is refused" 1 "$?"

# a fix that also changes another file, .github/ or a workflow is recorded:
# a tracked change, a new untracked file, or a removal
for edit in 'echo f >"$STUB/ws/src/other.js"' 'mkdir -p "$STUB/ws/.github/workflows" && echo f >"$STUB/ws/.github/workflows/release.yml"' \
  'mkdir -p "$STUB/ws/.GitHub" && echo f >"$STUB/ws/.GitHub/CODEOWNERS"' \
  'echo f >"$STUB/ws/src/new.js"' 'rm "$STUB/ws/src/other.js"'; do
  setup
  echo 'guarded' >"$STUB/ws/src/a.js"
  eval "$edit"
  disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"fixed"}'
  run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
  assert_exit "a working tree that also runs $edit takes the VALID record" 0 "$?"
  assert_eq "the record is kept after $edit" 1 "$(recorded)"
done
setup
fixture_git mv .github/x.yml src/b.js
disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"fixed"}'
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a rename out of .github/ takes the VALID record" 0 "$?"
assert_eq "a refused VALID record makes no GitHub call" 0 "$(wc -l <"$STUB/calls")"

setup
rm -rf "$STUB/ws/.git"
disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"fixed"}'
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a checkout git cannot read refuses the VALID record" 1 "$?"
assert_eq "an unreadable tree records nothing" 0 "$(recorded)"

# the disposition file must match the template and live in the scratch dir
for bad in \
  "{\"disposition\":\"VALID\",\"evidence\":[\"src/a.js:3\"],\"fix_sha\":\"$FIX\",\"note\":\"a fix sha on VALID\"}" \
  '{"disposition":"INCORRECT","note":"no evidence"}' \
  '{"disposition":"INCORRECT","evidence":["../../etc/passwd:1"],"note":"traversal"}' \
  '{"disposition":"INCORRECT","evidence":["src/missing.js:1"],"note":"missing file"}' \
  '{"disposition":"INCORRECT","evidence":["src/a.js"],"note":"no line"}' \
  "{\"disposition\":\"INCORRECT\",\"evidence\":[\"src/a.js:3\"],\"fix_sha\":\"$FIX\",\"note\":\"sha on INCORRECT\"}" \
  '{"disposition":"APPROVE","evidence":["src/a.js:3"],"note":"unknown"}' \
  '{"disposition":"INCORRECT","evidence":["src/a.js:3"],"note":""}' \
  '{"disposition":"INCORRECT","evidence":["src/a.js:3"],"note":"x","resolve":true}' \
  '{"disposition":"INCORRECT","evidence":["src/a.js:3"],"note":"hide <!-- pr-unblock:address-feedback-round --> here"}' \
  '{"disposition":"INCORRECT","evidence":["src/a.js:3"],"note":"bell \u0007 here"}' \
  '{"disposition":"INCORRECT","evidence":["src/a.js:3"],"note":"safe‮evil"}' \
  "{\"disposition\":\"INCORRECT\",\"evidence\":[\"src/a.js:3\"],\"note\":\"token $TOKEN\"}" \
  "{\"disposition\":\"INCORRECT\",\"evidence\":[\"src/a.js:3\"],\"note\":\"token $STATELESS\"}" \
  "{\"disposition\":\"INCORRECT\",\"evidence\":[\"src/a.js:3\"],\"note\":\"token $JWT_TOKEN\"}" \
  'not json'; do
  setup
  disposition "$bad"
  run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
  assert_exit "a disposition off the template is refused: $bad" 1 "$?"
  assert_eq "an off-template disposition records nothing: $bad" 0 "$(recorded)"
done
setup
printf '{"disposition":"INCORRECT","evidence":["src/a.js:3"],"note":"x"}' >"$STUB/outside.json"
run record PRRT_a "$STUB/outside.json" >/dev/null 2>&1
assert_exit "a disposition file outside the scratch dir is refused" 1 "$?"
ln -s "$STUB/outside.json" "$STUB/scratch/link.json"
run record PRRT_a "$STUB/scratch/link.json" >/dev/null 2>&1
assert_exit "a symlink out of the scratch dir is refused" 1 "$?"
disposition '{"disposition":"INCORRECT","evidence":["src/a.js:3"],"note":"x"}'
run record PRRT_zzz "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a thread the runner did not keep is refused" 1 "$?"
run record 'PRRT_a;rm' "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a malformed thread id is refused" 1 "$?"
run reply PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "the tool has no reply subcommand" 2 "$?"
assert_eq "refused calls record nothing" 0 "$(recorded)"
assert_eq "refused calls make no API call" 0 "$(wc -l <"$STUB/calls")"

run frobnicate >/dev/null 2>&1
assert_exit "an unknown subcommand exits 2" 2 "$?"

[[ $FAILED -eq 0 ]] || exit 1
exit 0
