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

# check-paths
setup
run check-paths src/a.js docs/b.md >/dev/null 2>&1
assert_exit "check-paths allows paths kept threads name" 0 "$?"
run check-paths src/a.js src/other.js >/dev/null 2>&1
assert_exit "check-paths refuses a path no kept thread names" 1 "$?"
jq '.threads += [{"id":"PRRT_g","path":".github/workflows/ci.yml","root_comment_id":300,"comments":[]},
  {"id":"PRRT_G","path":".GITHUB/WORKFLOWS/x.yml","root_comment_id":301,"comments":[]},
  {"id":"PRRT_s","path":".github/scripts/x.mjs","root_comment_id":302,"comments":[]}]' "$STUB/threads.json" >"$STUB/t2" &&
  mv "$STUB/t2" "$STUB/threads.json"
run check-paths .github/workflows/ci.yml >/dev/null 2>&1
assert_exit "check-paths refuses .github/workflows/ even when a thread names it" 1 "$?"
run check-paths .GITHUB/WORKFLOWS/x.yml >/dev/null 2>&1
assert_exit "check-paths refuses .github/workflows/ in any letter case" 1 "$?"
run check-paths .github/workflows/ci.test.yml >/dev/null 2>&1
assert_exit "check-paths refuses a test file beside a .github/workflows/ thread path" 1 "$?"
run check-paths .github/scripts/x.mjs .github/scripts/x.test.mjs >/dev/null 2>&1
assert_exit "check-paths allows a .github/scripts/ thread path and a test file beside it" 0 "$?"

# check-paths: a file in a kept thread's plugins/<p>/ directory other than permission config,
# package manifests and non-test code, and test files beside a thread path
setup
jq '.threads += [{"id":"PRRT_e","path":"plugins/p/evals/c/case.yaml","root_comment_id":400,"comments":[]},
  {"id":"PRRT_s","path":"plugins/planning/surface/round.py","root_comment_id":401,"comments":[]}]' \
  "$STUB/threads.json" >"$STUB/t2" && mv "$STUB/t2" "$STUB/threads.json"
for path in plugins/p/evals/c/samples/y.json plugins/p/evals/c/samples/deep/z.json \
  plugins/p/evals/other/samples/y.json plugins/p/skills/s/SKILL.md plugins/p/evals/x.json \
  plugins/p/hooks/hooks.json plugins/p/.claude-plugin/plugin.json plugins/p/AGENTS.md \
  plugins/p/skills/s/CLAUDE.md plugins/p/.claude/rules/r.md \
  plugins/planning/README.md plugins/planning/surface/test_round.py plugins/planning/surface/round_test.py src/a.test.js src/a.spec.ts; do
  run check-paths "$path" >/dev/null 2>&1
  assert_exit "check-paths allows $path" 0 "$?"
done
for path in plugins/q/evals/c/samples/y.json plugins/pp/README.md plugins/README.md \
  plugins/p/scripts/run.sh plugins/p/.claude/settings.json plugins/p/package.json plugins/p/lib/X.TS \
  plugins/planning/surface/helper.py plugins/planning/test_round.py \
  src/lib/a.test.js src/helper.js src/test_a.sh test_root.py \
  plugins/p/evals/c/../../../../.github/workflows/x.yml plugins/p/evals/c/./y.json plugins/p/evals/c//y.json \
  /src/a.js ./src/a.js; do
  run check-paths "$path" >/dev/null 2>&1
  assert_exit "check-paths refuses $path" 1 "$?"
done

# check-paths: a file the pull request already changes (pr_paths) joins every thread's scope while
# the gated head holds it; a new file and a .github/workflows/ path stay out even when pr_paths
# lists them (the select job leaves instruction and HIGH floor paths out of pr_paths)
setup
mkdir -p "$STUB/ws/.github/workflows"
echo 'c' >"$STUB/ws/.github/workflows/ci.yml"
fixture_git add -A
fixture_git commit -q -m more
run check-paths src/other.js >/dev/null 2>&1
assert_exit "check-paths refuses a file the pull request changes when pr_paths does not list it" 1 "$?"
jq '.pr_paths = ["src/other.js", "src/new.js", ".github/workflows/ci.yml"]' \
  "$STUB/threads.json" >"$STUB/t2" && mv "$STUB/t2" "$STUB/threads.json"
run check-paths src/other.js >/dev/null 2>&1
assert_exit "check-paths allows a file pr_paths lists, outside every thread's own scope" 0 "$?"
for path in src/new.js .github/workflows/ci.yml src/helper.js; do
  run check-paths "$path" >/dev/null 2>&1
  assert_exit "check-paths refuses $path with pr_paths set" 1 "$?"
done
echo 'fixed' >"$STUB/ws/src/other.js"
disposition '{"disposition":"VALID","evidence":["src/other.js:1"],"fix_sha":"","note":"fixed in src/other.js"}'
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "record takes a VALID fix made in a pr_paths file" 0 "$?"

# check-paths: a kept thread's named_paths join its scope only in its own plugins/<p>/ directory,
# never under .github/, never an instruction path, and never off normal form. run-transcript.js is
# the file #8116's thread PRRT_kwDOTCGFQM6tojDu was refused.
setup
T=plugins/knowledge/skills/video-digest/extraction/transcript
run check-paths "$T/run-transcript.js" >/dev/null 2>&1
assert_exit "check-paths refuses a .js file no thread names" 1 "$?"
jq --arg t "$T" '.threads += [{"id":"PRRT_n","path":($t + "/write-transcript.js"),"root_comment_id":500,"comments":[],
  "named_paths":[($t + "/run-transcript.js"), "plugins/other/x.js", ".github/workflows/x.yml",
    "plugins/knowledge/AGENTS.md", "plugins/knowledge/hooks/guard.sh", "plugins/knowledge/.claude-plugin/plugin.json",
    "plugins/knowledge/.mcp.json", "plugins/knowledge/skills/s/CLAUDE.md", "plugins/knowledge/.claude/settings.json",
    "plugins/knowledge/../other/x.js", "plugins/knowledge/a b.js"]}]' \
  "$STUB/threads.json" >"$STUB/t2" && mv "$STUB/t2" "$STUB/threads.json"
run check-paths "$T/run-transcript.js" >/dev/null 2>&1
assert_exit "check-paths allows a same-plugin file a fix request named" 0 "$?"
for path in plugins/knowledge/AGENTS.md plugins/knowledge/hooks/guard.sh plugins/knowledge/.claude-plugin/plugin.json \
  plugins/knowledge/.mcp.json plugins/knowledge/skills/s/CLAUDE.md; do
  run check-paths "$path" >/dev/null 2>&1
  assert_exit "check-paths allows named $path" 0 "$?"
done
for path in plugins/other/x.js .github/workflows/x.yml \
  plugins/knowledge/.claude/settings.json plugins/knowledge/../other/x.js "plugins/knowledge/a b.js" "$T/run-watch.js"; do
  run check-paths "$path" >/dev/null 2>&1
  assert_exit "check-paths refuses named $path" 1 "$?"
done

# check-paths: more code files, package manifests and non-ASCII letters stay out of the
# plugin-wide scope; plugin monitors, bin and .lsp.json are in it
for path in plugins/knowledge/README.md plugins/knowledge/monitors/monitors.json plugins/knowledge/bin/tool \
  plugins/knowledge/.lsp.json; do
  run check-paths "$path" >/dev/null 2>&1
  assert_exit "check-paths allows $path in the named thread's plugin" 0 "$?"
done
for path in plugins/knowledge/package-lock.json plugins/knowledge/lib/x.cjs plugins/knowledge/lib/x.ps1 "plugins/knowledge/hooKs/hooks.json" "plugins/knowledge/AGENTſ.md"; do
  run check-paths "$path" >/dev/null 2>&1
  assert_exit "check-paths refuses $path" 1 "$?"
done

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
# untracked empty one is passed over, one with content is refused
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
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a scrub-stub name with content refuses the VALID record" 1 "$?"
setup
echo 'guarded' >"$STUB/ws/src/a.js"
mkdir -p "$STUB/ws/src/nested" && : >"$STUB/ws/src/nested/package.json"
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "an empty stub name below the top of the checkout refuses the VALID record" 1 "$?"

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

# a fix steered outside the thread paths, or into .github/, is not recorded:
# a tracked change, a new untracked file, or a removal
for edit in 'echo f >"$STUB/ws/src/other.js"' 'mkdir -p "$STUB/ws/.github/workflows" && echo f >"$STUB/ws/.github/workflows/release.yml"' \
  'mkdir -p "$STUB/ws/.GitHub" && echo f >"$STUB/ws/.GitHub/CODEOWNERS"' \
  'echo f >"$STUB/ws/src/new.js"' 'rm "$STUB/ws/src/other.js"'; do
  setup
  echo 'guarded' >"$STUB/ws/src/a.js"
  eval "$edit"
  disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"fixed"}'
  run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
  assert_exit "a working tree that also runs $edit refuses the VALID record" 1 "$?"
  assert_eq "nothing is recorded after $edit" 0 "$(recorded)"
done
setup
fixture_git mv .github/x.yml src/b.js
disposition '{"disposition":"VALID","evidence":["src/a.js:3"],"fix_sha":"","note":"fixed"}'
run record PRRT_a "$STUB/scratch/d.json" >/dev/null 2>&1
assert_exit "a rename out of .github/ refuses the VALID record" 1 "$?"
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
