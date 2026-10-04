#!/usr/bin/env bash
# Black-box test for setup-apply.mjs, the writer behind /education:setup apply.
#
# Self-contained and cwd-independent; it changes only its own mktemp dir.
# Expected values come from the key contract in plugins/education/reference/config.md:
# explain_starting_rung takes plain or peer, and the file is
# docs/conventions/education.yaml at the repository root.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/setup-apply.mjs"
READER="$HERE/../../explain/scripts/parse-concern-value.sh"
REL="docs/conventions/education.yaml"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
ok() { printf 'ok   - %s\n' "$1"; }
bad() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}
expect() { # expect <label> <condition...>
  local label="$1"
  shift
  if "$@"; then ok "$label"; else bad "$label"; fi
}

repo_new() {
  local d
  d="$(mktemp -d "$TMP/repo.XXXXXX")"
  git -C "$d" init -q
  printf '%s\n' "$d"
}

OUT=""
CODE=0
run() { # run <repo> [args...]
  local r="$1"
  shift
  OUT="$(node "$SUT" --root "$r" "$@" 2>&1)"
  CODE=$?
}
one_line() { [[ "$(printf '%s\n' "$OUT" | wc -l)" -eq 1 && "$OUT" != *"    at "* ]]; }

# A new file holds only the requested key and reads back through the reader.
repo="$(repo_new)"
f="$repo/$REL"
run "$repo" explain_starting_rung=peer
expect 'a fresh write exits 0' test "$CODE" -eq 0
expect 'the written value reads back as peer' test "$(bash "$READER" "$f" explain_starting_rung)" = peer
expect 'the new file holds one key line and the schema comment' test "$(grep -vc '^#' "$f")" -eq 1
expect 'no other file is created' test "$(find "$repo" -path "$repo/.git" -prune -o -type f -print | wc -l)" -eq 1
expect 'no temp file is left behind' test -z "$(find "$repo/docs" -name '.*.tmp')"

# The same value again changes nothing.
before="$(cat "$f")"
run "$repo" explain_starting_rung=peer
expect 'an unchanged value reports already configured' test "$CODE" -eq 0 -a "$(cat "$f")" = "$before"
[[ "$OUT" == *"already configured"* ]] || bad 'already configured message'

# An existing file that would change: diff without --yes, write with it.
repo="$(repo_new)"
f="$repo/$REL"
mkdir -p "$repo/docs/conventions"
printf '# chosen by the team\nexplain_starting_rung: plain\n' >"$f"
run "$repo" explain_starting_rung=peer
expect 'a change to an existing file exits 3 without --yes' test "$CODE" -eq 3
if [[ "$OUT" == *"-explain_starting_rung: plain"* && "$OUT" == *"+explain_starting_rung: peer"* ]]; then ok 'the refusal prints the diff'; else bad 'the refusal prints the diff'; fi
expect 'the file is untouched without --yes' test "$(cat "$f")" = $'# chosen by the team\nexplain_starting_rung: plain'
run "$repo" --yes explain_starting_rung=peer
expect 'with --yes the change is written and the comment kept' test "$CODE" -eq 0 -a "$(cat "$f")" = $'# chosen by the team\nexplain_starting_rung: peer'

# Bad input: value outside the list, unknown key, a key given twice.
repo="$(repo_new)"
run "$repo" explain_starting_rung=expert
expect 'a value outside plain and peer exits 1' test "$CODE" -eq 1
if [[ "$OUT" == *"explain_starting_rung=expert"* ]]; then ok 'the refusal names the key and value'; else bad 'the refusal names the key and value'; fi
run "$repo" explain_starting_rung=
expect 'an empty value on the command line exits 1' test "$CODE" -eq 1
run "$repo" quiz_policy=always
expect 'a key outside the schema exits 1' test "$CODE" -eq 1
run "$repo" explain_starting_rung=plain explain_starting_rung=peer
expect 'a key given twice on the command line exits 1' test "$CODE" -eq 1
expect 'none of the refusals created docs/' test ! -e "$repo/docs"

# Document shapes a schema validator rejects. --check warns on each; apply
# replaces a bare empty or null value line, and refuses every other shape,
# since replacing one line would not settle what the file was meant to say.
shape() { # shape <label> <refuse|replace> <content>
  local label="$1" want="$2" content="$3" r file before
  r="$(repo_new)"
  file="$r/$REL"
  mkdir -p "$r/docs/conventions"
  printf '%s' "$content" >"$file"
  before="$(cat "$file")"
  run "$r" --check
  expect "--check warns on $label" test "$CODE" -eq 1
  [[ "$OUT" == WARN* ]] || bad "--check output for $label starts with WARN"
  run "$r" --yes explain_starting_rung=peer
  if [[ "$want" == refuse ]]; then
    expect "apply refuses $label and leaves the file" test "$CODE" -eq 1 -a "$(cat "$file")" = "$before"
  else
    expect "apply replaces $label" test "$CODE" -eq 0 -a "$(cat "$file")" = 'explain_starting_rung: peer'
  fi
}
shape 'a duplicate key' refuse $'explain_starting_rung: plain\nexplain_starting_rung: peer\n'
shape 'a duplicate key spelled with a space before the colon' refuse $'explain_starting_rung: plain\nexplain_starting_rung : peer\n'
shape 'a duplicate key, once quoted' refuse $'explain_starting_rung: plain\n"explain_starting_rung": peer\n'
shape 'a map value' refuse $'explain_starting_rung:\n  level: peer\n'
shape 'a list value' refuse $'explain_starting_rung:\n  - peer\n'
shape 'a one-line flow list value' refuse $'explain_starting_rung: [peer]\n'
shape 'a one-line flow map value' refuse $'explain_starting_rung: {level: peer}\n'
shape 'an empty flow list' refuse $'explain_starting_rung: []\n'
shape 'an empty flow map' refuse $'explain_starting_rung: {}\n'
shape 'an empty double-quoted string' refuse $'explain_starting_rung: ""\n'
shape 'an empty single-quoted string' refuse $'explain_starting_rung: \'\'\n'
shape 'an empty value' replace $'explain_starting_rung:\n'
shape 'a null value' replace $'explain_starting_rung: null\n'
shape 'a value outside the list' replace $'explain_starting_rung: expert\n'
shape 'an unknown key' refuse $'explain_starting_rung: plain\nverbosity: high\n'

# Path guards: symlinks, a hard link, and the wrong kind of file in the way.
repo="$(repo_new)"
outside="$(mktemp -d "$TMP/outside.XXXXXX")"
mkdir -p "$repo/docs"
ln -s "$outside" "$repo/docs/conventions"
run "$repo" explain_starting_rung=peer
expect 'a symlinked docs/conventions is refused and nothing lands outside' test "$CODE" -eq 1 -a -z "$(ls -A "$outside")"

repo="$(repo_new)"
outside="$(mktemp -d "$TMP/outside.XXXXXX")"
printf 'explain_starting_rung: plain\n' >"$outside/education.yaml"
mkdir -p "$repo/docs/conventions"
ln -s "$outside/education.yaml" "$repo/$REL"
run "$repo" --yes explain_starting_rung=peer
expect 'a symlinked target is refused and its referent is untouched' test "$CODE" -eq 1 -a "$(cat "$outside/education.yaml")" = 'explain_starting_rung: plain'

repo="$(repo_new)"
outside="$(mktemp -d "$TMP/outside.XXXXXX")"
printf 'explain_starting_rung: plain\n' >"$outside/shared.yaml"
mkdir -p "$repo/docs/conventions"
ln "$outside/shared.yaml" "$repo/$REL"
run "$repo" --yes explain_starting_rung=peer
expect 'a hard-linked target is refused and the other link is untouched' test "$CODE" -eq 1 -a "$(cat "$outside/shared.yaml")" = 'explain_starting_rung: plain'
if [[ "$OUT" == *"hard link"* ]]; then ok 'the hard-link refusal says so'; else bad 'the hard-link refusal says so'; fi

# A link planted at the temp path: the O_EXCL open refuses it, nothing is
# written through it, and a file this run did not create is not removed.
repo="$(repo_new)"
outside="$(mktemp -d "$TMP/outside.XXXXXX")"
mkdir -p "$repo/docs/conventions"
ln -s "$outside/landed.yaml" "$repo/docs/conventions/.education.yaml.tmp"
run "$repo" explain_starting_rung=peer
expect 'a link at the temp path is refused' test "$CODE" -eq 1
if one_line; then ok 'the temp-path refusal is one line'; else bad 'the temp-path refusal is one line'; fi
expect 'nothing lands through the temp-path link' test ! -e "$outside/landed.yaml" -a ! -e "$repo/$REL"
expect 'the planted link is left in place' test -L "$repo/docs/conventions/.education.yaml.tmp"

repo="$(repo_new)"
mkdir -p "$repo/$REL"
run "$repo" --yes explain_starting_rung=peer
expect 'a directory at the target path is refused' test "$CODE" -eq 1
if one_line; then ok 'that refusal is one line with no stack trace'; else bad 'that refusal is one line with no stack trace'; fi
run "$repo" --check
expect '--check on a directory at the target path is refused' test "$CODE" -eq 1
if one_line; then ok 'the --check refusal is one line'; else bad 'the --check refusal is one line'; fi

repo="$(repo_new)"
printf 'a file\n' >"$repo/docs"
run "$repo" explain_starting_rung=peer
expect 'docs as a file is refused and left as it was' test "$CODE" -eq 1 -a "$(cat "$repo/docs")" = 'a file'
if one_line; then ok 'the docs-as-file refusal is one line'; else bad 'the docs-as-file refusal is one line'; fi

# --check on an absent and a valid file.
repo="$(repo_new)"
run "$repo" --check
expect '--check on a missing file exits 0' test "$CODE" -eq 0
if [[ "$OUT" == INFO*absent* ]]; then ok '--check reports the file absent'; else bad '--check reports the file absent'; fi
mkdir -p "$repo/docs/conventions"
printf 'explain_starting_rung: peer\n' >"$repo/$REL"
run "$repo" --check
expect '--check on a valid file exits 0 and prints the value' test "$CODE" -eq 0 -a "$OUT" = 'PASS explain_starting_rung: peer'
expect '--check writes nothing' test "$(cat "$repo/$REL")" = 'explain_starting_rung: peer'

# Usage errors.
run "$repo"
expect 'no <key>=<value> exits 2' test "$CODE" -eq 2
run "$repo" --check explain_starting_rung=peer
expect '--check with a pair exits 2' test "$CODE" -eq 2
OUT="$(cd "$TMP" && GIT_CEILING_DIRECTORIES="$TMP" node "$SUT" explain_starting_rung=peer 2>&1)"
CODE=$?
expect 'outside a git working tree without --root exits 2' test "$CODE" -eq 2

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo 'all setup-apply checks passed'
