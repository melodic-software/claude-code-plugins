#!/usr/bin/env bash
# Black-box test for setup-apply.mjs, the writer behind /docs-hygiene:setup apply.
#
# Self-contained and cwd-independent; it changes only its own mktemp dir.
# Expected values come from the key contract in plugins/docs-hygiene/reference/config.md:
# compress_articles takes keep or cut, and the file is
# docs/conventions/docs-hygiene.yaml at the repository root.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/setup-apply.mjs"
READER="$HERE/../../../lib/parse-concern-value.sh"
REL="docs/conventions/docs-hygiene.yaml"

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
run "$repo" compress_articles=cut
expect 'a fresh write exits 0' test "$CODE" -eq 0
expect 'the written value reads back as cut' test "$(bash "$READER" "$f" compress_articles)" = cut
expect 'the new file holds one key line and the schema comment' test "$(grep -vc '^#' "$f")" -eq 1
expect 'no other file is created' test "$(find "$repo" -path "$repo/.git" -prune -o -type f -print | wc -l)" -eq 1
expect 'no temp file is left behind' test -z "$(find "$repo/docs" -name '.*.tmp')"

# The same value again changes nothing.
before="$(cat "$f")"
run "$repo" compress_articles=cut
expect 'an unchanged value reports already configured' test "$CODE" -eq 0 -a "$(cat "$f")" = "$before"
[[ "$OUT" == *"already configured"* ]] || bad 'already configured message'

# An existing file that would change: diff without --yes, write with it.
repo="$(repo_new)"
f="$repo/$REL"
mkdir -p "$repo/docs/conventions"
printf '# chosen by the docs team\ncompress_articles: keep\n' >"$f"
run "$repo" compress_articles=cut
expect 'a change to an existing file exits 3 without --yes' test "$CODE" -eq 3
if [[ "$OUT" == *"-compress_articles: keep"* && "$OUT" == *"+compress_articles: cut"* ]]; then ok 'the refusal prints the diff'; else bad 'the refusal prints the diff'; fi
expect 'the file is untouched without --yes' test "$(cat "$f")" = $'# chosen by the docs team\ncompress_articles: keep'
run "$repo" --yes compress_articles=cut
expect 'with --yes the change is written and the comment kept' test "$CODE" -eq 0 -a "$(cat "$f")" = $'# chosen by the docs team\ncompress_articles: cut'

# A key given twice on the command line, with the file present: one line, file unchanged.
run "$repo" --yes compress_articles=keep compress_articles=cut
expect 'a key given twice with the file present exits 1' test "$CODE" -eq 1
if one_line; then ok 'that refusal is one line'; else bad 'that refusal is one line'; fi
expect 'the file is unchanged after that refusal' test "$(cat "$f")" = $'# chosen by the docs team\ncompress_articles: cut'

# Bad input with no file: value outside the list, empty value, unknown key, a key twice.
repo="$(repo_new)"
run "$repo" compress_articles=drop
expect 'a value outside keep and cut exits 1' test "$CODE" -eq 1
if [[ "$OUT" == *"compress_articles=drop"* ]]; then ok 'the refusal names the key and value'; else bad 'the refusal names the key and value'; fi
run "$repo" compress_articles=
expect 'an empty value on the command line exits 1' test "$CODE" -eq 1
run "$repo" verbosity=high
expect 'a key outside the schema exits 1' test "$CODE" -eq 1
run "$repo" compress_articles=keep compress_articles=cut
expect 'a key given twice with no file exits 1' test "$CODE" -eq 1
if one_line; then ok 'the no-file twice refusal is one line'; else bad 'the no-file twice refusal is one line'; fi
expect 'none of the refusals created docs/' test ! -e "$repo/docs"

# Document shapes a schema validator rejects. --check warns on each; apply
# replaces a bare empty or null value line or a value outside the list, and
# refuses every other shape, since replacing one line would not settle what the
# file was meant to say.
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
  run "$r" --yes compress_articles=cut
  if [[ "$want" == refuse ]]; then
    expect "apply refuses $label and leaves the file" test "$CODE" -eq 1 -a "$(cat "$file")" = "$before"
    if one_line; then ok "the refusal of $label is one line"; else bad "the refusal of $label is one line"; fi
  else
    expect "apply replaces $label" test "$CODE" -eq 0 -a "$(cat "$file")" = 'compress_articles: cut'
  fi
}
shape 'a duplicate key' refuse $'compress_articles: keep\ncompress_articles: cut\n'
shape 'a duplicate key spelled with a space before the colon' refuse $'compress_articles: keep\ncompress_articles : cut\n'
shape 'a duplicate key, once quoted' refuse $'compress_articles: keep\n"compress_articles": cut\n'
shape 'a map value' refuse $'compress_articles:\n  level: cut\n'
shape 'a list value' refuse $'compress_articles:\n  - cut\n'
shape 'a one-line flow list value' refuse $'compress_articles: [cut]\n'
shape 'a one-line flow map value' refuse $'compress_articles: {level: cut}\n'
shape 'an empty flow list' refuse $'compress_articles: []\n'
shape 'an empty flow map' refuse $'compress_articles: {}\n'
shape 'an empty double-quoted string' refuse $'compress_articles: ""\n'
shape 'an empty single-quoted string' refuse $'compress_articles: \'\'\n'
shape 'a parse error on the key line' refuse $'compress_articles: "cut\n'
shape 'a parse error on another line' refuse $'compress_articles: keep\nother: "open\n'
shape 'an empty value' replace $'compress_articles:\n'
shape 'a null value' replace $'compress_articles: null\n'
shape 'a tilde value' replace $'compress_articles: ~\n'
shape 'a value outside the list' replace $'compress_articles: drop\n'
shape 'an unknown key set twice' refuse $'compress_articles: keep\nverbosity: high\nverbosity: low\n'
shape 'an unknown key holding a list' refuse $'compress_articles: keep\nstray: [a]\n'

# A key outside the schema, with a value or empty, is named in one warning and
# ignored: apply writes the asked-for key and keeps that line byte for byte.
for extra in 'verbosity: high' 'stray:'; do
  repo="$(repo_new)"
  mkdir -p "$repo/docs/conventions"
  printf 'compress_articles: keep\n%s\n' "$extra" >"$repo/$REL"
  run "$repo" --yes compress_articles=cut
  expect "apply beside '$extra' exits 0 and keeps its line" test "$CODE" -eq 0 -a "$(cat "$repo/$REL")" = "compress_articles: cut"$'\n'"$extra"
  expect "apply beside '$extra' warns once" test "$(grep -c 'WARN.*is not in the schema' <<<"$OUT")" -eq 1
done

# --check names the effective repository value per key (ADR 0060 Decision 7):
# an invalid value drops this layer for its key, which then resolves to the
# schema default, keep, never to the lower userConfig layer; a key the schema
# does not list is reported and leaves the valid key in force, as
# articles-setting.sh reads it.
check_case() { # check_case <label> <content> <expected key line>
  local label="$1" content="$2" want="$3" r
  r="$(repo_new)"
  mkdir -p "$r/docs/conventions"
  printf '%s' "$content" >"$r/$REL"
  run "$r" --check
  if [[ $'\n'"$OUT"$'\n' == *$'\n'"$want"$'\n'* ]]; then ok "--check on $label prints: $want"; else bad "--check on $label prints: $want (got: $OUT)"; fi
}
dropped='WARN compress_articles: dropped from docs/conventions/docs-hygiene.yaml; resolves to its default, keep, not to userConfig'
check_case 'a value outside the list' $'compress_articles: drop\n' "$dropped"
check_case 'a key set twice' $'compress_articles: cut\ncompress_articles: cut\n' "$dropped"
check_case 'a parse error on another line' $'compress_articles: cut\nother: "open\n' "$dropped"
check_case 'an unknown key beside a valid value' $'compress_articles: cut\nverbosity: high\n' 'PASS compress_articles: cut'
check_case 'an unknown key beside a valid value' $'compress_articles: cut\nverbosity: high\n' 'WARN docs/conventions/docs-hygiene.yaml: key verbosity is not in the schema'

# CRLF line endings are kept and the key is updated in place; a file that mixes
# CRLF and LF is refused in one line and left as it was.
repo="$(repo_new)"
f="$repo/$REL"
mkdir -p "$repo/docs/conventions"
printf '# chosen by the docs team\r\ncompress_articles: keep\r\n' >"$f"
printf '# chosen by the docs team\r\ncompress_articles: cut\r\n' >"$TMP/crlf-want"
run "$repo" --yes compress_articles=cut
expect 'a CRLF file is updated in place with CRLF kept' test "$CODE" -eq 0
expect 'the CRLF file holds one key line, ending in CRLF' cmp -s "$f" "$TMP/crlf-want"
run "$repo" --yes compress_articles=cut
expect 'the same value on a CRLF file reports already configured' test "$CODE" -eq 0 -a "${OUT#*already configured}" != "$OUT"
printf '# chosen by the docs team\r\ncompress_articles: keep\n' >"$f"
cp "$f" "$TMP/mixed-before"
run "$repo" --yes compress_articles=cut
expect 'a file mixing CRLF and LF is refused' test "$CODE" -eq 1
if one_line; then ok 'the mixed line-ending refusal is one line'; else bad 'the mixed line-ending refusal is one line'; fi
expect 'the mixed file is unchanged' cmp -s "$f" "$TMP/mixed-before"

# Path guards: symlinks, a hard link, and the wrong kind of file in the way.
repo="$(repo_new)"
outside="$(mktemp -d "$TMP/outside.XXXXXX")"
mkdir -p "$repo/docs"
ln -s "$outside" "$repo/docs/conventions"
run "$repo" compress_articles=cut
expect 'a symlinked docs/conventions is refused and nothing lands outside' test "$CODE" -eq 1 -a -z "$(ls -A "$outside")"

repo="$(repo_new)"
outside="$(mktemp -d "$TMP/outside.XXXXXX")"
ln -s "$outside" "$repo/docs"
run "$repo" compress_articles=cut
expect 'a symlinked docs is refused and nothing lands outside' test "$CODE" -eq 1 -a -z "$(ls -A "$outside")"

repo="$(repo_new)"
outside="$(mktemp -d "$TMP/outside.XXXXXX")"
printf 'compress_articles: keep\n' >"$outside/docs-hygiene.yaml"
mkdir -p "$repo/docs/conventions"
ln -s "$outside/docs-hygiene.yaml" "$repo/$REL"
run "$repo" --yes compress_articles=cut
expect 'a symlinked target is refused and its referent is untouched' test "$CODE" -eq 1 -a "$(cat "$outside/docs-hygiene.yaml")" = 'compress_articles: keep'

repo="$(repo_new)"
outside="$(mktemp -d "$TMP/outside.XXXXXX")"
printf 'compress_articles: keep\n' >"$outside/shared.yaml"
mkdir -p "$repo/docs/conventions"
ln "$outside/shared.yaml" "$repo/$REL"
run "$repo" --yes compress_articles=cut
expect 'a hard-linked target is refused and the other link is untouched' test "$CODE" -eq 1 -a "$(cat "$outside/shared.yaml")" = 'compress_articles: keep'
if [[ "$OUT" == *"hard link"* ]]; then ok 'the hard-link refusal says so'; else bad 'the hard-link refusal says so'; fi

# A link planted at the temp path: the O_EXCL open refuses it, nothing is
# written through it, and a file this run did not create is not removed.
repo="$(repo_new)"
outside="$(mktemp -d "$TMP/outside.XXXXXX")"
mkdir -p "$repo/docs/conventions"
ln -s "$outside/landed.yaml" "$repo/docs/conventions/.docs-hygiene.yaml.tmp"
run "$repo" compress_articles=cut
expect 'a link at the temp path is refused' test "$CODE" -eq 1
if one_line; then ok 'the temp-path refusal is one line'; else bad 'the temp-path refusal is one line'; fi
expect 'nothing lands through the temp-path link' test ! -e "$outside/landed.yaml" -a ! -e "$repo/$REL"
expect 'the planted link is left in place' test -L "$repo/docs/conventions/.docs-hygiene.yaml.tmp"

repo="$(repo_new)"
mkdir -p "$repo/$REL"
run "$repo" --yes compress_articles=cut
expect 'a directory at the target path is refused' test "$CODE" -eq 1
if one_line; then ok 'that refusal is one line with no stack trace'; else bad 'that refusal is one line with no stack trace'; fi
run "$repo" --check
expect '--check on a directory at the target path is refused' test "$CODE" -eq 1
if one_line; then ok 'the --check refusal is one line'; else bad 'the --check refusal is one line'; fi

repo="$(repo_new)"
printf 'a file\n' >"$repo/docs"
run "$repo" compress_articles=cut
expect 'docs as a file is refused and left as it was' test "$CODE" -eq 1 -a "$(cat "$repo/docs")" = 'a file'
if one_line; then ok 'the docs-as-file refusal is one line'; else bad 'the docs-as-file refusal is one line'; fi

# A root at $HOME or above it: compress would never read the file, so apply refuses.
repo="$(repo_new)"
OUT="$(HOME="$repo" node "$SUT" --root "$repo" compress_articles=cut 2>&1)"
CODE=$?
expect "a root equal to \$HOME is refused" test "$CODE" -eq 1 -a ! -e "$repo/docs"
OUT="$(HOME="$repo/sub" node "$SUT" --root "$repo" compress_articles=cut 2>&1)"
CODE=$?
expect "a root above \$HOME is refused" test "$CODE" -eq 1 -a ! -e "$repo/docs"
OUT="$(HOME="${repo}x" node "$SUT" --root "$repo" compress_articles=cut 2>&1)"
CODE=$?
expect "a sibling path sharing a prefix with \$HOME is not refused" test "$CODE" -eq 0 -a -f "$repo/$REL"

# --check on an absent and a valid file.
repo="$(repo_new)"
run "$repo" --check
expect '--check on a missing file exits 0' test "$CODE" -eq 0
if [[ "$OUT" == INFO*absent* ]]; then ok '--check reports the file absent'; else bad '--check reports the file absent'; fi
mkdir -p "$repo/docs/conventions"
printf 'compress_articles: keep\n' >"$repo/$REL"
run "$repo" --check
expect '--check on a valid file exits 0 and prints the value' test "$CODE" -eq 0 -a "$OUT" = 'PASS compress_articles: keep'
expect '--check writes nothing' test "$(cat "$repo/$REL")" = 'compress_articles: keep'

# Usage errors.
run "$repo"
expect 'no <key>=<value> exits 2' test "$CODE" -eq 2
run "$repo" --check compress_articles=cut
expect '--check with a pair exits 2' test "$CODE" -eq 2
OUT="$(cd "$TMP" && GIT_CEILING_DIRECTORIES="$TMP" node "$SUT" compress_articles=cut 2>&1)"
CODE=$?
expect 'outside a git working tree without --root exits 2' test "$CODE" -eq 2

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo 'all setup-apply checks passed'
