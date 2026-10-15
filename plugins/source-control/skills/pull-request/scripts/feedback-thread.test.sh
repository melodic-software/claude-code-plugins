#!/usr/bin/env bash
# Tests for feedback-thread.sh, black-box with a stubbed `gh` on PATH. The
# stub serves only the compare read and records every call: the tool posts
# nothing, so any other call fails the case.
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

mkdir -p "$TEST_TMPDIR/bin"
cat >"$TEST_TMPDIR/bin/gh" <<'STUB_EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
[[ $1 == api ]] || { echo "gh-stub: unrouted $*" >&2; exit 1; }
shift
case "$*" in
  "repos/o/r/compare/"*) cat "$STUB/compare.json" ;;
  *) echo "gh-stub: unrouted $*" >&2; exit 1 ;;
esac
STUB_EOF
chmod +x "$TEST_TMPDIR/bin/gh"

# setup: a fresh case with two kept threads, a checkout, and the lane branch a
# clean VALID fix leaves.
setup() {
  STUB=$(mktemp -d "$TEST_TMPDIR/case.XXXXXX")
  export STUB
  mkdir -p "$STUB/scratch" "$STUB/ws/src" "$STUB/ws/docs"
  : >"$STUB/calls"
  echo 'x' >"$STUB/ws/src/a.js"
  echo 'y' >"$STUB/ws/docs/b.md"
  cat >"$STUB/threads.json" <<EOF
{"version":1,"repository":"o/r","pr":42,"head_sha":"$HEAD","lane_branch":"lane-commits/pr-unblock/address-feedback/7-1",
 "threads":[
  {"id":"PRRT_a","path":"src/a.js","line":3,"review_commit":"$HEAD","root_comment_id":100,"comments":[{"id":100,"body":"null deref at line 3"}]},
  {"id":"PRRT_b","path":"docs/b.md","line":1,"review_commit":"$HEAD","root_comment_id":200,"comments":[{"id":200,"body":"typo"}]}
 ]}
EOF
  printf '{"commits":[{"sha":"%s"}],"files":[{"filename":"src/a.js"}]}' "$FIX" >"$STUB/compare.json"
}

disposition() {
  printf '%s' "$1" >"$STUB/scratch/d.json"
}

run() {
  PATH="$TEST_TMPDIR/bin:$PATH" FEEDBACK_THREADS="$STUB/threads.json" FEEDBACK_LOG="$STUB/replies.jsonl" \
    FEEDBACK_SCRATCH="$STUB/scratch" FEEDBACK_WORKSPACE="$STUB/ws" GH_TOKEN="$TOKEN" \
    bash "$SCRIPT" "$@"
}

recorded() {
  if [[ -f $STUB/replies.jsonl ]]; then wc -l <"$STUB/replies.jsonl"; else echo 0; fi
}

# list
setup
out=$(run list)
assert_eq "list prints the kept thread ids" "PRRT_a PRRT_b" "$(jq -r 'map(.id) | join(" ")' <<<"$out")"

# check-paths
setup
run check-paths src/a.js docs/b.md >/dev/null 2>&1
assert_exit "check-paths allows paths kept threads name" 0 "$?"
run check-paths src/a.js src/other.js >/dev/null 2>&1
assert_exit "check-paths refuses a path no kept thread names" 1 "$?"
jq '.threads += [{"id":"PRRT_g","path":".github/workflows/ci.yml","root_comment_id":300,"comments":[]},
  {"id":"PRRT_G","path":".GITHUB/x.yml","root_comment_id":301,"comments":[]}]' "$STUB/threads.json" >"$STUB/t2" &&
  mv "$STUB/t2" "$STUB/threads.json"
run check-paths .github/workflows/ci.yml >/dev/null 2>&1
assert_exit "check-paths refuses .github/ even when a thread names it" 1 "$?"
run check-paths .GITHUB/x.yml >/dev/null 2>&1
assert_exit "check-paths refuses .github/ in any letter case" 1 "$?"

# record VALID: checked against the lane branch and appended, nothing posted
setup
disposition "{\"disposition\":\"VALID\",\"evidence\":[\"src/a.js:3\"],\"fix_sha\":\"$FIX\",\"note\":\"Guarded the null case.\"}"
out=$(run record PRRT_a "$STUB/scratch/d.json" 2>&1)
assert_exit "a VALID record succeeds" 0 "$?"
assert_eq "the replies file holds the disposition as written, keyed by thread" \
  "{\"thread\":\"PRRT_a\",\"disposition\":\"VALID\",\"evidence\":[\"src/a.js:3\"],\"fix_sha\":\"$FIX\",\"note\":\"Guarded the null case.\"}" \
  "$(cat "$STUB/replies.jsonl")"
assert_eq "the only API call is the compare read" \
  "api repos/o/r/compare/$HEAD...lane-commits/pr-unblock/address-feedback/7-1" "$(cat "$STUB/calls")"
assert_contains "the tool says the reply job posts it" "$out" "reply job posts it"
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a second record on the same thread is refused" 1 "$?"
assert_eq "the refused second record appends nothing" 1 "$(recorded)"

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

# a fix steered outside the thread paths, or into .github/, is not recorded
for changed in '.github/workflows/release.yml' 'src/other.js' '.GitHub/CODEOWNERS'; do
  setup
  printf '{"commits":[{"sha":"%s"}],"files":[{"filename":"src/a.js"},{"filename":"%s"}]}' "$FIX" "$changed" >"$STUB/compare.json"
  disposition "{\"disposition\":\"VALID\",\"evidence\":[\"src/a.js:3\"],\"fix_sha\":\"$FIX\",\"note\":\"fixed\"}"
  run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
  assert_exit "a lane branch that changes $changed refuses the VALID record" 1 "$?"
  assert_eq "nothing is recorded when the lane branch changes $changed" 0 "$(recorded)"
done
setup
printf '{"commits":[{"sha":"%s"}],"files":[{"filename":"src/b.js","previous_filename":".github/x.yml"}]}' "$FIX" >"$STUB/compare.json"
disposition "{\"disposition\":\"VALID\",\"evidence\":[\"src/a.js:3\"],\"fix_sha\":\"$FIX\",\"note\":\"fixed\"}"
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a rename out of .github/ refuses the VALID record" 1 "$?"

setup
printf '{"commits":[{"sha":"%s"}],"files":[{"filename":"src/a.js"}]}' "$HEAD" >"$STUB/compare.json"
disposition "{\"disposition\":\"VALID\",\"evidence\":[\"src/a.js:3\"],\"fix_sha\":\"$FIX\",\"note\":\"fixed\"}"
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a fix SHA that is not on the lane branch is refused" 1 "$?"

# the disposition file must match the template and live in the scratch dir
for bad in \
  "{\"disposition\":\"VALID\",\"evidence\":[\"src/a.js:3\"],\"note\":\"no sha\"}" \
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
