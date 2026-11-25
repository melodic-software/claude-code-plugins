#!/usr/bin/env bash
# shellcheck disable=SC2016
# Every fixture below is markdown fed to the hook as literal data, and backticks
# are the code-span delimiters the hook scans for — single quotes are required so
# nothing expands. Disabled file-wide rather than on ~20 individual lines.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/skill-reference-verify.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

unset CLAUDE_PROJECT_DIR

export CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=30

REPO="$TEST_TMPDIR/market"
mkdir -p "$REPO"
git -C "$REPO" init -q

mk_plugin() {
  local dir="$1" name="$2"
  mkdir -p "$REPO/plugins/$dir/.claude-plugin"
  MSYS_NO_PATHCONV=1 jq -n --arg n "$name" '{name:$n,version:"0.1.0"}' \
    >"$REPO/plugins/$dir/.claude-plugin/plugin.json"
}
mk_skill() {
  local pdir="$1" sdir="$2" fname="${3:-}"
  mkdir -p "$REPO/plugins/$pdir/skills/$sdir"
  local f="$REPO/plugins/$pdir/skills/$sdir/SKILL.md"
  if [[ -n "$fname" ]]; then
    {
      printf -- '---\n'
      printf 'name: %s\n' "$fname"
      printf 'description: x\n'
      printf -- '---\n'
    } >"$f"
  else
    : >"$f"
  fi
}

mk_plugin alpha alpha
mk_skill alpha setup
mk_skill alpha audit
mk_skill alpha legacy-dir renamed-command
mk_skill alpha quoted-dir '"quoted-name"'

mk_plugin beta-dir beta
mk_skill beta-dir check

TARGET="$REPO/notes.md"
: >"$TARGET"

GUARD_UNDER_TEST="$HOOK"


assert_run_helpers_propagate_exit

run 'Run `/alpha:nonexistent` next.'
assert_exit "unresolved skill → exit 0 (advisory)" 0 "$?"
assert_contains "unresolved skill → named" "$OUT" "  /alpha:nonexistent"
assert_contains "unresolved skill → names the searched plugin dir" "$OUT" "plugins/alpha/skills/"

run 'Both `/alpha:ghost` and `/beta:missing` are gone.'
assert_contains "two unresolved → both named" "$OUT" "  /alpha:ghost (no such skill"
assert_contains "two unresolved → the second named too" "$OUT" "  /beta:missing (no such skill"
assert_contains "two unresolved → manifest-named plugin resolves to its real dir" "$OUT" \
  "plugins/beta-dir/skills/"

run_edit 'Now cites `/alpha:vanished`.'
assert_contains "Edit hunk scanned via new_string" "$OUT" "  /alpha:vanished"

run 'Run `/alpha:nonexistent`.'
assert_absent "advisory carries no verdict trailer" "$OUT" "Detect-then-judge"
assert_contains "advisory exempts a deliberate reference" "$OUT" "A reference kept on purpose"

mkdir -p "$REPO/plugins/alpha/skills/ghost"
run 'Run `/alpha:ghost`.'
assert_contains "skills/ dir without SKILL.md → still unresolved" "$OUT" \
  "  /alpha:ghost"
assert_contains "a plugin declaring no paths still reads as plugins/<plugin>/skills/" "$OUT" \
  "(no such skill under plugins/alpha/skills/)"

mk_skill alpha commented-dir 'commented-name # public command'
run 'Run `/alpha:commented-name`.'
assert_silent "frontmatter name with trailing YAML comment → resolves" "$OUT"

run 'Stale ref `/alpha:legacy-dir`.'
assert_contains "renamed skill's directory name is NOT an alias → fires" "$OUT" \
  "  /alpha:legacy-dir"
run 'Current ref `/alpha:renamed-command`.'
assert_silent "the declared frontmatter name still resolves" "$OUT"

run 'Run `/alpha:setup`.'
assert_silent "no frontmatter name → directory name is the command" "$OUT"

run 'Run `/alpha:ghost-arg --apply` now.'
assert_contains "argument-bearing invocation → leading token extracted" "$OUT" \
  "  /alpha:ghost-arg"
run 'Run `/alpha:audit --dry-run <target>`.'
assert_silent "argument-bearing invocation of a real skill → silent" "$OUT"

run 'Run `/alpha:setup` and `/alpha:audit` first.'
assert_exit "resolving skills → exit 0" 0 "$?"
assert_silent "resolving skills → silent" "$OUT"

run 'Run `/beta:check`.'
assert_silent "plugin resolved via manifest name, not directory name → silent" "$OUT"

run 'Run `/alpha:renamed-command`.'
assert_silent "skill resolved via frontmatter name → silent" "$OUT"

run 'Run `/alpha:quoted-name`.'
assert_silent "skill resolved via quoted frontmatter name → silent" "$OUT"

run 'Install `/some-other-market:thing` from elsewhere.'
assert_silent "unowned plugin → not adjudicated" "$OUT"

mkdir -p "$REPO/plugins/not-a-plugin/skills/x"
run 'Run `/not-a-plugin:x`.'
assert_silent "directory without a manifest → not a plugin, silent" "$OUT"

run 'Unbackticked /alpha:nonexistent in prose is not a command.'
assert_silent "unbackticked reference → not scanned" "$OUT"

run 'A URL fragment `https://x.test/a:b` and a time `12:30` are not references.'
assert_silent "URL fragment and time → silent" "$OUT"

run 'Uppercase `/Alpha:Setup` does not match the command grammar.'
assert_silent "uppercase reference → silent (not command-shaped)" "$OUT"

PLAIN="$TEST_TMPDIR/plain"
mkdir -p "$PLAIN"
git -C "$PLAIN" init -q
PLAIN_TARGET="$PLAIN/notes.md"
: >"$PLAIN_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$PLAIN" bash "$HOOK" <<<"$(write_json "$PLAIN_TARGET" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "no plugins/ tree → exit 0" 0 "$RC"
assert_silent "no plugins/ tree → silent (no local authority)" "$OUT"

EMPTY="$TEST_TMPDIR/empty-market"
mkdir -p "$EMPTY/plugins/whatever"
git -C "$EMPTY" init -q
EMPTY_TARGET="$EMPTY/notes.md"
: >"$EMPTY_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$EMPTY" bash "$HOOK" <<<"$(write_json "$EMPTY_TARGET" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "plugins/ with no manifests → exit 0" 0 "$RC"
assert_silent "plugins/ with no manifests → silent" "$OUT"

SCRIPT="$REPO/tool.sh"
: >"$SCRIPT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$SCRIPT" 'echo `/alpha:nonexistent`')" 2>&1)
RC=$?
assert_exit "non-markdown file → exit 0" 0 "$RC"
assert_silent "non-markdown file → not scanned" "$OUT"

OUTSIDE="$TEST_TMPDIR/outside.md"
: >"$OUTSIDE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "file outside project dir → exit 0" 0 "$RC"
assert_silent "file outside project dir → silent" "$OUT"

CL="$REPO/plugins/alpha/CHANGELOG.md"
: >"$CL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$CL" 'Renamed the `/alpha:nonexistent` skill to `/alpha:audit`.')" 2>&1)
RC=$?
assert_exit "CHANGELOG.md → exit 0" 0 "$RC"
assert_silent "CHANGELOG.md is historical by contract → silent" "$OUT"

NOTCL="$REPO/docs-CHANGELOG-notes.md"
: >"$NOTCL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$NOTCL" 'Run `/alpha:nonexistent`.')" 2>&1)
assert_contains "CHANGELOG-in-name but not a CHANGELOG → still adjudicated" "$OUT" \
  "  /alpha:nonexistent"

PARTIAL="$REPO/partial.md"
printf 'Run `/alpha:ghost-partial` to begin.\n' >"$PARTIAL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$PARTIAL" 'ghost-partial')" 2>&1)
RC=$?
assert_exit "bare-word Edit hunk → exit 0" 0 "$RC"
assert_contains "bare-word Edit hunk → containing reference recovered" "$OUT" \
  "  /alpha:ghost-partial"

PARTIAL2="$REPO/partial2.md"
printf 'Stale `/alpha:untouched-ghost` here.\nRun `/alpha:ghost-two` to begin.\n' >"$PARTIAL2"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$PARTIAL2" 'ghost-two')" 2>&1)
assert_contains "reconstruction reports the edited reference" "$OUT" \
  "  /alpha:ghost-two"
assert_absent "reconstruction does NOT report an untouched neighbor" "$OUT" \
  "untouched-ghost"

# Diff-scope again, against the harder shape from #1453: the hunk is unrelated
# prose that merely SHARES A WORD TOKEN with an untouched broken reference
# elsewhere in the same file. Anchoring on the token alone (the pre-fix behavior)
# pulls that reference in — `legacy` occurs in both `ghost-legacy` and the prose —
# so the anchor has to be the hunk's own line, which occurs verbatim in exactly
# the line the edit landed in. Verified to fail against the pre-fix guard (which
# fired `  /alpha:ghost-legacy`), the same shape #1432 proved for
# stale-path-verify's sibling defect.
SEGSHARE="$REPO/segshare.md"
printf 'Stale `/alpha:ghost-legacy` here.\nThe legacy naming convention was updated today.\n' \
  >"$SEGSHARE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$SEGSHARE" 'The legacy naming convention was updated today.')" 2>&1)
RC=$?
assert_exit "prose hunk sharing a word token → exit 0" 0 "$RC"
assert_silent "hunk sharing only a token does not drag in an untouched broken reference" "$OUT"

OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$SEGSHARE" 'legacy')" 2>&1)
RC=$?
assert_exit "bare-token hunk matching several lines → exit 0" 0 "$RC"
assert_silent "ambiguous anchor is dropped, not unioned" "$OUT"

# Same defect one level finer: both occurrences of the anchor are on ONE physical
# line, so `grep` reports a single matching line and a line-count uniqueness check
# sees nothing wrong. Inserting `legacy` into a line that already carried an
# untouched reference must not report that reference — this call never wrote it.
# The gate therefore counts OCCURRENCES, which subsumes counting lines.
SAMELINE="$REPO/sameline.md"
printf 'Run `/alpha:ghost-sameline` and note the sameline convention.\n' >"$SAMELINE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$SAMELINE" 'sameline')" 2>&1)
RC=$?
assert_exit "anchor occurring twice on one line → exit 0" 0 "$RC"
assert_silent "two occurrences on a single line are ambiguous, not unique" "$OUT"

REPLALL="$REPO/replall.md"
printf 'First `/alpha:ghost-one` here.\nSecond `/alpha:ghost-two` there.\n' >"$REPLALL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(replall_json "$REPLALL" 'ghost')" 2>&1)
RC=$?
assert_exit "replace_all Edit → exit 0" 0 "$RC"
assert_contains "replace_all → first edited reference reported" "$OUT" \
  "  /alpha:ghost-one"
assert_contains "replace_all → second edited reference reported" "$OUT" \
  "  /alpha:ghost-two"

# ...but `replace_all` suspends the uniqueness gate, and with it the only thing
# separating an occurrence this call WROTE from one that merely reads the same.
# A pre-existing `/alpha:ghost-old` matches the `ghost` anchor and was reported as
# though the edit had produced it. `tool_input` genuinely cannot tell them apart;
# `tool_response.structuredPatch` can, marking the written lines with `+`.
#
# The payloads below carry it. Note the FIRST fixture above deliberately does not:
# absent `tool_response` the filter is inert, which is what keeps that case — and
# every consumer on a payload without one — behaving exactly as before.
#
# replall_patch_json <file> <new_string> <patch-line>... — each patch line keeps
# its unified-diff prefix (`+` written, `-` removed, ` ` untouched context).
#
# The lines reach jq on STDIN, not as `--args` positionals: every one of them
# starts with `-`, `+` or a space, and jq parses a leading `-` as an option
# (`-Run …` died on "Unknown option -u"), which yields an empty payload and a
# silent hook — a green `assert_absent` for entirely the wrong reason.
replall_patch_json() {
  local fp="$1" s="$2" lines_json
  shift 2
  lines_json=$(printf '%s\n' "$@" | jq -Rs 'split("\n")[:-1]')
  MSYS_NO_PATHCONV=1 jq -n --arg fp "$fp" --arg s "$s" --argjson l "$lines_json" \
    '{tool_name:"Edit",
      tool_input:{file_path:$fp,new_string:$s,replace_all:true},
      tool_response:{filePath:$fp,replaceAll:true,
        structuredPatch:[{oldStart:1,oldLines:2,newStart:1,newLines:2,lines:$l}]}}'
}
UNTOUCHED="$REPO/replall-untouched.md"
printf 'Run `/alpha:ghost` now.\nLegacy `/alpha:ghost-old` stays.\n' >"$UNTOUCHED"
patch_one() {
  replall_patch_json "$1" 'ghost' \
    '-Run `/alpha:setup` now.' \
    '+Run `/alpha:ghost` now.' \
    ' Legacy `/alpha:ghost-old` stays.'
}
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(patch_one "$UNTOUCHED")" 2>&1)
RC=$?
assert_exit "replace_all + structuredPatch → exit 0" 0 "$RC"
assert_contains "replace_all + patch → the WRITTEN reference is still reported" \
  "$OUT" '  /alpha:ghost (no such skill'
assert_absent "replace_all + patch → the UNTOUCHED reference is not reported" \
  "$OUT" "/alpha:ghost-old"

EMPTYT="$REPO/replall-empty.md"
: >"$EMPTYT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(patch_one "$EMPTYT")" 2>&1)
assert_silent "replace_all + patch → empty target yields nothing at all" "$OUT"

BOTHW="$REPO/replall-both.md"
printf 'First `/alpha:ghost-one` here.\nSecond `/alpha:ghost-two` there.\n' >"$BOTHW"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(replall_patch_json "$BOTHW" 'ghost' \
  '-First `/alpha:setup-one` here.' \
  '-Second `/alpha:setup-two` there.' \
  '+First `/alpha:ghost-one` here.' \
  '+Second `/alpha:ghost-two` there.')" 2>&1)
assert_contains "replace_all + patch → first genuinely written ref survives" "$OUT" \
  "  /alpha:ghost-one"
assert_contains "replace_all + patch → second genuinely written ref survives" "$OUT" \
  "  /alpha:ghost-two"

# Review finding on #2153: Gate 3 must not undo the reformatting tolerance the
# per-line fallback exists to provide. An earlier-ordered PostToolUse hook that
# reflows whitespace leaves the anchor locatable — a literal substring search does
# not care what surrounds it — while changing the physical line, so comparing raw
# text dropped a genuinely written reference. The target below carries the extra
# internal spacing a formatter would leave; the patch keeps the original spacing.
REFLOW="$REPO/replall-reflow.md"
printf 'Run  `/alpha:ghost`  now.\nLegacy `/alpha:ghost-old` stays.\n' >"$REFLOW"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(patch_one "$REFLOW")" 2>&1)
assert_contains "reflowed line → the written reference still surfaces" \
  "$OUT" '  /alpha:ghost (no such skill'
assert_absent "reflowed line → the untouched reference is still suppressed" \
  "$OUT" "/alpha:ghost-old"

STALE="$REPO/replall-stale.md"
printf -- '- Run `/alpha:ghost` now (moved).\nLegacy `/alpha:ghost-old` stays.\n' >"$STALE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(patch_one "$STALE")" 2>&1)
assert_contains "stale witness → written reference still reported" \
  "$OUT" '  /alpha:ghost (no such skill'
assert_contains "stale witness → gate abstains rather than muting" \
  "$OUT" "  /alpha:ghost-old"

OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$PARTIAL2" 'Run `/alpha:ghost-three` now.')" 2>&1)
assert_contains "full-command hunk → scanned directly" "$OUT" \
  "  /alpha:ghost-three"
assert_absent "full-command hunk → no disk reconstruction leakage" "$OUT" \
  "untouched-ghost"

SUBST="$REPO/substr.md"
printf 'Run `/alpha:sethost` to begin.\n' >"$SUBST"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$SUBST" 'host')" 2>&1)
assert_contains "substring Edit inside a segment → recovered" "$OUT" \
  "  /alpha:sethost"

MIXED="$REPO/mixed.md"
printf 'First `/alpha:ghost-mixed` here.\nSecond `/alpha:audit` is fine.\n' >"$MIXED"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$MIXED" $'ghost-mixed\nAlso now cites `/alpha:ghost-direct`.')" 2>&1)
assert_contains "mixed hunk → direct reference reported" "$OUT" \
  "  /alpha:ghost-direct"
assert_contains "mixed hunk → reconstructed reference also reported" "$OUT" \
  "  /alpha:ghost-mixed"

OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$MIXED" 'Run `/alpha:ghost-mixed` again.')" 2>&1)
assert_contains "reference reachable both ways → reported" "$OUT" \
  "  /alpha:ghost-mixed"
mixed_ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$OUT" 2>/dev/null)
assert_eq "reference reachable both ways → listed once" 1 \
  "$(grep -c '/alpha:ghost-mixed (' <<<"$mixed_ctx")"

ONELINE="$REPO/oneline.md"
printf 'Stale `/alpha:ghost-legacy` here. The legacy naming convention was updated today.\n' \
  >"$ONELINE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$ONELINE" 'The legacy naming convention was updated today.')" 2>&1)
RC=$?
assert_exit "unique anchor beside an untouched reference → exit 0" 0 "$RC"
assert_silent "a reference the anchor does not overlap is not reported" "$OUT"

ONELINE2="$REPO/oneline2.md"
printf 'Stale `/alpha:ghost-legacy` here. The legacy naming convention was updated today.\n' \
  >"$ONELINE2"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$ONELINE2" 'ghost-legacy')" 2>&1)
assert_contains "an anchor inside the reference still reports it" "$OUT" \
  "  /alpha:ghost-legacy"

SHORT="$REPO/short.md"
printf 'Run `/alpha:setxx` to begin.\n' >"$SHORT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$SHORT" 'xx')" 2>&1)
RC=$?
assert_exit "two-character Edit hunk → exit 0" 0 "$RC"
assert_contains "two-character Edit hunk → containing reference recovered" "$OUT" \
  "  /alpha:setxx"

# MULTIBYTE CONTENT AROUND THE ANCHOR. reconstruct_partial_edit pins LC_ALL=C so
# its scans are not charged the multibyte matcher's ~6.5x, which makes every offset
# it computes a BYTE offset. That is safe only if a slice never splits a character,
# so multibyte text goes on the line BEFORE the anchor (moving the anchor's
# absolute offset off a character boundary) and on both sides of it within its own
# line (moving the span's boundaries off one). The skill name itself stays ASCII
# because the command grammar is `[a-z0-9-]` — a non-ASCII name is unreportable by
# design, so putting one here would test the grammar, not the offsets.
#
# A byte/character confusion mangles the span, and a mangled span cannot parse as a
# command — so this case fails by going SILENT, the direction that would otherwise
# hide.
UTF8="$REPO/utf8.md"
printf 'Préambule des conventions — rien à voir ici.\nExécutez `/alpha:ghost-cafe` après le déploiement — voilà.\n' \
  >"$UTF8"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$UTF8" 'ghost-cafe')" 2>&1)
RC=$?
assert_exit "multibyte content around the anchor → exit 0" 0 "$RC"
assert_contains "a reference reconstructed out of multibyte content is intact" "$OUT" \
  "  /alpha:ghost-cafe"

# THE PIN MUST NOT REACH THE CHILD PROCESSES. The case above passes with the pin,
# without it, and with an EXPORTED pin — both locales are internally consistent, so
# it cannot tell the three apart. This one can, and it is the reason the pin is
# written `local +x` rather than `local`.
#
# `local LC_ALL=C` inherits the export attribute when the CONSUMER exported LC_ALL,
# so the pin reaches emit_refs' grep/sed. Those tools classify some non-ASCII spaces
# as `[[:space:]]` under a UTF-8 locale but never under C, so an exported pin makes
# the hook silently drop a reference whose argument separator is one of them — a
# detection loss that buys nothing, since the whole cost the pin removes is bash's
# own matcher and the children measured identical in both locales.
#
# WHICH separator has that property is a property of the host's C library, not of
# this hook, and it is NOT portable. glibc removed U+00A0 and U+202F from `space`
# in 2.26 (a no-break space is deliberately not a separator); Cygwin/MSYS still
# classifies them. Hardcoding U+00A0 in this case passes on Windows and fails on
# Linux CI, asserting a libc's classification table as if it were this hook's
# behavior.
#
# So the separator is DISCOVERED rather than assumed: take the first candidate this
# host actually classifies differently between the two locales, probed through the
# very sed stage the assertion depends on. That cannot go vacuous (a candidate that
# does not discriminate is never selected) and cannot go platform-brittle (no
# codepoint is baked in). Every candidate is escape-built, never a literal byte, so
# an editor or transfer that normalizes whitespace cannot quietly turn it into an
# ASCII space — which is exactly what happened while this case was first written.
# MIRRORS skill-reference-verify.sh — emit_refs' reference-extraction sed,
# byte for byte. Nothing enforces that, so if you change the grammar there, change
# it here too. A drift cannot pass silently: the end-to-end assertion below still
# runs the REAL hook, so a separator discovered against a stale copy would fail
# `assert_contains` rather than quietly select the wrong codepoint.
SEP_SED='s|^(/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*)([[:space:]].*)?$|\1|p'
SEP='' SEP_NAME=''
# shellcheck disable=SC2059  # the candidate IS the format string: its \nnn octal
# escapes are the point, and passing them as %s data would emit the backslashes
# literally instead of the UTF-8 bytes this case needs.
for _cand in 'U+3000 IDEOGRAPHIC SPACE:\343\200\200' \
  'U+2000 EN QUAD:\342\200\200' \
  'U+2028 LINE SEPARATOR:\342\200\250' \
  'U+205F MEDIUM MATHEMATICAL SPACE:\342\201\237' \
  'U+00A0 NO-BREAK SPACE:\302\240'; do
  _probe=$(printf "/alpha:ghost-x${_cand#*:}arg")
  _u=$(printf '%s' "$_probe" | LC_ALL=en_US.UTF-8 sed -nE "$SEP_SED")
  _c=$(printf '%s' "$_probe" | LC_ALL=C sed -nE "$SEP_SED")
  if [[ -n "$_u" && -z "$_c" ]]; then
    # shellcheck disable=SC2059  # same reason as above
    SEP=$(printf "${_cand#*:}")
    SEP_NAME=${_cand%%:*}
    break
  fi
done
if [[ -z "$SEP" ]]; then
  ok "SKIP locale-contrast guard — NO SEPARATOR DISCRIMINATES on this host, the +x guard did NOT run ($(uname -s), no candidate classified as [[:space:]] under en_US.UTF-8 but not C)"
else
  SEPDOC="$REPO/sepspace.md"
  printf 'Intro line.\nRun `/alpha:ghost-sep%sarg` now.\n' "$SEP" >"$SEPDOC"
  OUT=$(LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 CLAUDE_PROJECT_DIR="$REPO" \
    bash "$HOOK" <<<"$(edit_json "$SEPDOC" 'ghost-sep')" 2>&1)
  RC=$?
  assert_exit "consumer-exported UTF-8 locale → exit 0" 0 "$RC"
  assert_contains "the pin does not reach the children: reference separated by $SEP_NAME survives" \
    "$OUT" "  /alpha:ghost-sep"
fi

SHORT2="$REPO/short2.md"
printf 'Run `/alpha:setxx` and note the xx convention.\n' >"$SHORT2"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$SHORT2" 'xx')" 2>&1)
assert_silent "a short anchor occurring twice is still ambiguous" "$OUT"

BIGDOC="$REPO/big.md"
BIGHUNK="$TEST_TMPDIR/bighunk.txt"
: >"$BIGDOC"
: >"$BIGHUNK"
{
  for ((i = 1; i <= 1000; i++)); do printf 'Line %s of the large replaced passage.\n' "$i"; done
} >"$BIGHUNK"
{
  cat "$BIGHUNK"
  printf 'Run `/alpha:ghost-big` at the end.\n'
} >"$BIGDOC"
big_start=$SECONDS
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$BIGDOC" "$(cat "$BIGHUNK")")" 2>&1)
RC=$?
big_elapsed=$((SECONDS - big_start))
assert_exit "1000-line Edit hunk → exit 0" 0 "$RC"
if ((big_elapsed < 30)); then
  ok "1000-line Edit hunk stays inside the hook's 30s timeout (${big_elapsed}s)"
else
  bad "1000-line Edit hunk took ${big_elapsed}s, at or past the hook's 30s timeout"
fi

SPLIT="$REPO/split.md"
printf 'First edited line.\n\nSecond line with `/alpha:ghost-split`.\n' >"$SPLIT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$SPLIT" 'First edited line.
Second line with `/alpha:ghost-split`.')" 2>&1)
RC=$?
assert_exit "hunk no longer contiguous on disk → exit 0" 0 "$RC"
assert_contains "per-line fallback still recovers the reference" "$OUT" \
  "  /alpha:ghost-split"

PAIR="$REPO/pair.md"
printf 'shared line\nother\nshared line\ntail with `/alpha:ghost-pair`.\n' >"$PAIR"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$PAIR" 'shared line
tail with `/alpha:ghost-pair`.')" 2>&1)
assert_contains "a unique whole hunk resolves lines that individually repeat" "$OUT" \
  "  /alpha:ghost-pair"

FBIG="$REPO/fallback-big.md"
FBIGHUNK="$TEST_TMPDIR/fallback-hunk.txt"
{
  printf 'ghost-fallback\n'
  for ((i = 2; i <= 300; i++)); do printf 'Body line %s of the reformatted passage.\n' "$i"; done
  printf 'ghost-deep\n'
  for ((i = 302; i <= 401; i++)); do printf 'Body line %s of the reformatted passage.\n' "$i"; done
} >"$FBIGHUNK"
{
  printf 'Opening line with `/alpha:ghost-fallback` in it.\n'
  for ((i = 2; i <= 300; i++)); do printf 'Body line %s of the reformatted passage.\n' "$i"; done
  printf 'Deep line with `/alpha:ghost-deep` in it.\n'
  for ((i = 302; i <= 401; i++)); do printf 'Body line %s of the reformatted passage.\n' "$i"; done
  for ((i = 1; i <= 1450; i++)); do
    printf 'Filler paragraph %s padding this file toward the reconstruction cap.\n' "$i"
  done
} >"$FBIG"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$FBIG" "$(cat "$FBIGHUNK")")" 2>&1)
RC=$?
assert_exit "large file forced onto the fallback path → exit 0" 0 "$RC"
assert_contains "the capped fallback still reports the reference it admits" "$OUT" \
  "  /alpha:ghost-fallback"
assert_absent "the fallback stops at the anchor cap instead of walking the hunk" "$OUT" \
  "  /alpha:ghost-deep"

OVER="$REPO/over-cap.md"
{
  printf 'Complete reference `/alpha:ghost-over` written by this edit.\n'
  for ((i = 1; i <= 2200; i++)); do
    printf 'Filler paragraph %s pushing this file past the reconstruction cap.\n' "$i"
  done
} >"$OVER"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$OVER" 'Complete reference `/alpha:ghost-over` written by this edit.')" 2>&1)
RC=$?
assert_exit "file past RECONSTRUCT_MAX_CHARS → exit 0" 0 "$RC"
assert_contains "the direct scan still reports a complete reference above the cap" "$OUT" \
  "  /alpha:ghost-over"

mk_plugin gamma gamma
mk_skill gamma conventional
mkdir -p "$REPO/plugins/gamma/custom/extras/declared"
printf -- '---\nname: declared\ndescription: x\n---\n' \
  >"$REPO/plugins/gamma/custom/extras/declared/SKILL.md"
mkdir -p "$REPO/plugins/gamma/solo"
printf -- '---\nname: solo-command\ndescription: x\n---\n' \
  >"$REPO/plugins/gamma/solo/SKILL.md"
MSYS_NO_PATHCONV=1 jq -n '{name:"gamma",version:"0.1.0",skills:["./custom/extras/","./solo/"]}' \
  >"$REPO/plugins/gamma/.claude-plugin/plugin.json"

run 'Run `/gamma:declared`.'
assert_exit "manifest-declared skill path → exit 0" 0 "$?"
assert_silent "skill under a manifest-declared path resolves" "$OUT"

run 'Run `/gamma:solo-command`.'
assert_silent "declared path pointing AT a skill directory resolves" "$OUT"

run 'Run `/gamma:conventional`.'
assert_silent "declared paths add to skills/, they do not replace it" "$OUT"

run 'Run `/gamma:nowhere`.'
assert_contains "declared paths do not suppress a genuinely missing command" "$OUT" \
  "  /gamma:nowhere"
assert_contains "the advisory names every directory the search covered" "$OUT" \
  "(no such skill under plugins/gamma/skills/, plugins/gamma/custom/extras/, plugins/gamma/solo/)"

run 'Run `/gamma:solo`.'
assert_contains "declared skill's directory name is NOT an alias" "$OUT" \
  "  /gamma:solo"

mk_plugin delta delta
mkdir -p "$REPO/plugins/delta/elsewhere/one"
printf -- '---\nname: one\ndescription: x\n---\n' \
  >"$REPO/plugins/delta/elsewhere/one/SKILL.md"
MSYS_NO_PATHCONV=1 jq -n '{name:"delta",version:"0.1.0",skills:"./elsewhere/"}' \
  >"$REPO/plugins/delta/.claude-plugin/plugin.json"
run 'Run `/delta:one`.'
assert_silent "a string skills value resolves like a one-element array" "$OUT"

mk_plugin epsilon epsilon
printf -- '---\nname: eps-command\ndescription: x\n---\n' >"$REPO/plugins/epsilon/SKILL.md"
run 'Run `/epsilon:eps-command`.'
assert_silent "root SKILL.md with no skills/ and no manifest key auto-loads" "$OUT"
run 'Run `/epsilon:missing`.'
assert_contains "single-skill plugin still fires for a command it does not have" "$OUT" \
  "  /epsilon:missing"

# The auto-load applies only under its documented conditions. A root SKILL.md
# BESIDE a populated `skills/` is not loaded, so it must not resolve — accepting it
# would suppress the advisory for a command Claude Code does not offer.
mk_plugin zeta zeta
mk_skill zeta real
printf -- '---\nname: zeta-root\ndescription: x\n---\n' >"$REPO/plugins/zeta/SKILL.md"
run 'Run `/zeta:zeta-root`.'
assert_contains "root SKILL.md beside a populated skills/ is not auto-loaded" "$OUT" \
  "  /zeta:zeta-root"

OUT=$(CLAUDE_PROJECT_DIR="$REPO" CLAUDE_PLUGIN_OPTION_SKILL_REFERENCE_VERIFY_ENABLED=false \
  bash "$HOOK" <<<"$(write_json "$TARGET" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "kill switch → exit 0" 0 "$RC"
assert_silent "kill switch → silent" "$OUT"

OUT=$(bash "$HOOK" </dev/null 2>&1)
RC=$?
assert_exit "empty stdin → exit 0" 0 "$RC"
assert_silent "empty stdin → no output" "$OUT"

HOOK_SRC=$(cat "$HOOK")
assert_contains "jq guard: uses hook::require jq" "$HOOK_SRC" 'hook::require jq'
# The directory comes from parameter expansion, not a `$(dirname …)` subshell:
# this hook runs on every Write and Edit, and a command substitution is a fork
# per call on Windows Git Bash. The anchor is still the FILE's directory, which
# is what this case exists to hold.
assert_contains "repo root is file-anchored" "$HOOK_SRC" 'hook::repo_root_to REPO_ROOT "$FILE_DIR"'
assert_contains "repo root anchor uses parameter expansion" "$HOOK_SRC" 'FILE_DIR="${FILE%/*}"'
assert_absent "repo root anchor forks no subshell" "$HOOK_SRC" 'hook::repo_root "$(dirname'
assert_file_dir_seam "$HOOK"

SHIM_DIR="$TEST_TMPDIR/jq-shim"
mkdir -p "$SHIM_DIR"
JQ_LOG="$TEST_TMPDIR/jq-manifest-calls"
REAL_JQ="$(command -v jq)"
{
  printf '#!/usr/bin/env bash\n'
  printf 'hit=0\n'
  printf 'for a in "$@"; do case "$a" in *plugin.json) printf "%%s\\n" "$a" >>"%s"; hit=1 ;; esac; done\n' "$JQ_LOG"
  printf '((hit)) && printf "INVOKE\\n" >>"%s"\n' "$JQ_LOG"
  printf 'exec "%s" "$@"\n' "$REAL_JQ"
} >"$SHIM_DIR/jq"
chmod +x "$SHIM_DIR/jq"

: >"$JQ_LOG"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" PATH="$SHIM_DIR:$PATH" bash "$HOOK" \
  <<<"$(write_json "$TARGET" 'Plain prose with a `code span` and no command.')" 2>&1)
assert_exit "lazy index: no-reference write exits 0" 0 "$?"
assert_silent "lazy index: no-reference write stays quiet" "$OUT"
assert_eq "lazy index: no-reference write reads no manifest" 0 "$(wc -l <"$JQ_LOG" | tr -d ' ')"

rm -f "$REPO/.git/guardrails-skill-index"
: >"$JQ_LOG"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" PATH="$SHIM_DIR:$PATH" bash "$HOOK" \
  <<<"$(write_json "$TARGET" 'Run `/alpha:nonexistent`.')" 2>&1)
assert_contains "lazy index: a reference still resolves against the index" "$OUT" "/alpha:nonexistent"
if (($(wc -l <"$JQ_LOG" | tr -d ' ') > 0)); then
  ok "lazy index: a reference-bearing write does read the manifests"
else
  bad "lazy index: index was never built for a reference-bearing write"
fi

rm -f "$REPO/.git/guardrails-skill-index"
: >"$JQ_LOG"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" PATH="$SHIM_DIR:$PATH" bash "$HOOK" \
  <<<"$(write_json "$TARGET" 'Both `/alpha:nonexistent` and `/alpha:missing-too`.')" 2>&1)
shopt -s nullglob
FIXTURE_MANIFEST_FILES=("$REPO"/plugins/*/.claude-plugin/plugin.json)
shopt -u nullglob
FIXTURE_MANIFESTS=${#FIXTURE_MANIFEST_FILES[@]}
MANIFEST_ARGS=$(grep -c 'plugin.json' "$JQ_LOG")
INVOKE_COUNT=$(grep -c 'INVOKE' "$JQ_LOG")
assert_eq "lazy index: one jq invocation builds the whole index" 1 "$INVOKE_COUNT"
assert_eq "lazy index: that invocation is handed every manifest once" \
  "$FIXTURE_MANIFESTS" "$MANIFEST_ARGS"
: >"$JQ_LOG"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" PATH="$SHIM_DIR:$PATH" bash "$HOOK" \
  <<<"$(write_json "$TARGET" 'Both `/alpha:nonexistent` and `/alpha:missing-too`.')" 2>&1)
assert_contains "index cache: a repeat reference still reports" "$OUT" "/alpha:nonexistent"
assert_eq "index cache: a repeat at the same manifests starts no jq" \
  0 "$(grep -c 'INVOKE' "$JQ_LOG" || true)"

# On Windows Git Bash a native jq is handed the MSYS-converted argument, so
# `input_filename` echoes `C:\...\plugin.json` rather than the string the hook
# globbed. The index must key on the plugin directory it can rebuild itself,
# not on the echo: keyed on the echo, no manifest is ever "seen" and every one
# is re-read through the per-manifest fallback (two more invocations each).
# Simulated here by a second shim that rewrites the echoed field of every batch
# row into that converted form before handing it back; the manifest arguments
# and the parse are the real jq's.
CONV_SHIM_DIR="$TEST_TMPDIR/jq-shim-conv"
mkdir -p "$CONV_SHIM_DIR"
export SRV_TEST_REAL_JQ="$REAL_JQ" SRV_TEST_JQ_LOG="$JQ_LOG"
cat >"$CONV_SHIM_DIR/jq" <<'SHIM'
#!/usr/bin/env bash
hit=0
for a in "$@"; do case "$a" in *plugin.json) hit=1 ;; esac; done
((hit)) || exec "$SRV_TEST_REAL_JQ" "$@"
printf 'INVOKE\n' >>"$SRV_TEST_JQ_LOG"
"$SRV_TEST_REAL_JQ" "$@" | while IFS= read -r line; do
  if [[ "$line" == /*$'\x1e'* ]]; then
    first="${line%%$'\x1e'*}"
    first="C:${first//\//\\}"
    printf '%s\x1e%s\n' "$first" "${line#*$'\x1e'}"
  else
    printf '%s\n' "$line"
  fi
done
exit "${PIPESTATUS[0]}"
SHIM
chmod +x "$CONV_SHIM_DIR/jq"

rm -f "$REPO/.git/guardrails-skill-index"
: >"$JQ_LOG"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" PATH="$CONV_SHIM_DIR:$PATH" bash "$HOOK" \
  <<<"$(write_json "$TARGET" 'Both `/alpha:nonexistent` and `/beta:check`.')" 2>&1)
assert_exit "converted echo: exits 0" 0 "$?"
assert_eq "converted echo: still one jq invocation, no per-manifest fallback" \
  1 "$(grep -c 'INVOKE' "$JQ_LOG")"
assert_contains "converted echo: the unresolved reference still reports" "$OUT" "/alpha:nonexistent"
assert_contains "converted echo: the index directory is the hook's own, not the echo" "$OUT" \
  "plugins/alpha/"
assert_absent "converted echo: no converted path leaks into the report" "$OUT" "C:\\"
if [[ "$OUT" == *"/beta:check"* ]]; then
  bad "converted echo: a resolvable reference was reported unresolved"
else
  ok "converted echo: a resolvable reference resolves through the rebuilt index"
fi
unset SRV_TEST_REAL_JQ SRV_TEST_JQ_LOG

mk_plugin_paths() {
  local dir="$1" name="$2" skills_json="$3"
  mkdir -p "$REPO/plugins/$dir/.claude-plugin"
  MSYS_NO_PATHCONV=1 jq -n --arg n "$name" --argjson s "$skills_json" \
    '{name:$n,version:"0.1.0",skills:$s}' \
    >"$REPO/plugins/$dir/.claude-plugin/plugin.json"
}
mk_plugin_paths gamma gamma '["./extra-skills","./more"]'
mkdir -p "$REPO/plugins/gamma/extra-skills/deep" "$REPO/plugins/gamma/more/wide" \
  "$REPO/plugins/gamma/undeclared/hidden"
: >"$REPO/plugins/gamma/extra-skills/deep/SKILL.md"
: >"$REPO/plugins/gamma/more/wide/SKILL.md"
: >"$REPO/plugins/gamma/undeclared/hidden/SKILL.md"
mk_plugin_paths delta delta '"./one"'
mkdir -p "$REPO/plugins/delta/one/solo"
: >"$REPO/plugins/delta/one/solo/SKILL.md"

run 'Use `/gamma:deep`, `/gamma:wide` and `/delta:solo`.'
assert_exit "declared paths: array and string paths resolve → exit 0" 0 "$?"
assert_silent "declared paths: array and string paths resolve → silent" "$OUT"

run 'Use `/gamma:hidden`.'
assert_contains "declared paths: an undeclared directory is not a skill root" "$OUT" \
  "  /gamma:hidden"

# A manifest with NO name but a skills key: the empty field must stay in place
# (a whitespace separator collapses it, and the paths land in the name slot),
# so the plugin indexes under its directory name with its declared path intact.
mkdir -p "$REPO/plugins/noname/.claude-plugin" "$REPO/plugins/noname/extra/inner"
MSYS_NO_PATHCONV=1 jq -n '{version:"0.1.0",skills:["./extra"]}' \
  >"$REPO/plugins/noname/.claude-plugin/plugin.json"
: >"$REPO/plugins/noname/extra/inner/SKILL.md"
run 'Use `/noname:inner`.'
assert_silent "nameless manifest: indexed by directory with its declared path" "$OUT"
run 'Use `/noname:absent`.'
assert_contains "nameless manifest: an absent skill still reports under plugins/noname/" "$OUT" \
  "plugins/noname/"

# A declared path carrying a backslash must arrive byte-identical (@tsv would
# double it); the directory literally named `.\extra` holds the skill.
mkdir -p "$REPO/plugins/bslash/.claude-plugin" "$REPO/plugins/bslash/.\\extra/held"
MSYS_NO_PATHCONV=1 jq -n '{name:"bslash",version:"0.1.0",skills:".\\extra"}' \
  >"$REPO/plugins/bslash/.claude-plugin/plugin.json"
: >"$REPO/plugins/bslash/.\\extra/held/SKILL.md"
run 'Use `/bslash:held`.'
assert_silent "backslash in a declared path: read byte-identical, skill resolves" "$OUT"

mkdir -p "$REPO/plugins/broken/.claude-plugin" "$REPO/plugins/broken/skills/works"
printf '{ not json' >"$REPO/plugins/broken/.claude-plugin/plugin.json"
: >"$REPO/plugins/broken/skills/works/SKILL.md"
run 'Use `/broken:works`.'
assert_exit "malformed manifest: plugin still indexed by directory → exit 0" 0 "$?"
assert_silent "malformed manifest: conventional skills/ still resolves → silent" "$OUT"
run 'Use `/gamma:deep` after a malformed sibling manifest.'
assert_silent "malformed manifest: the other manifests are still read" "$OUT"
rm -rf "$REPO/plugins/broken"

TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK="$(make_sink "cat >\"$TEL\"")"
CLAUDE_PROJECT_DIR="$REPO" HOOK_TELEMETRY_SINK="$SINK" \
  bash "$HOOK" <<<"$(write_json "$TARGET" 'Run `/alpha:nonexistent`.')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "skill-reference-verify"
  assert_contains "telemetry: status ok" "$(jq -r '.status' "$TEL")" "ok"
  assert_contains "telemetry: findings name the reference" "$(jq -r '.data.findings[]' "$TEL")" "/alpha:nonexistent"
  assert_absent "telemetry: file path is repo-relative, never absolute" \
    "$(jq -r '.data.file' "$TEL")" "$TEST_TMPDIR"
else
  bad "telemetry: no envelope written"
fi

parity "dispatched parity: unresolved reference" 'Run `/alpha:nonexistent`.' 0 \
  "  /alpha:nonexistent"
parity "dispatched parity: resolving reference" 'Run `/alpha:setup`.' 0 ""
parity "dispatched parity: manifest name, not directory" 'Run `/beta:check`.' 0 ""

IDX_REPO="$TEST_TMPDIR/idx-market"
mkdir -p "$IDX_REPO"
git -C "$IDX_REPO" init -q
for idx_p in alpha beta; do
  mkdir -p "$IDX_REPO/plugins/$idx_p/.claude-plugin" "$IDX_REPO/plugins/$idx_p/skills/setup"
  MSYS_NO_PATHCONV=1 jq -n --arg n "$idx_p" '{name:$n,version:"0.1.0"}' \
    >"$IDX_REPO/plugins/$idx_p/.claude-plugin/plugin.json"
  : >"$IDX_REPO/plugins/$idx_p/skills/setup/SKILL.md"
done
: >"$IDX_REPO/notes.md"
IDX_PAYLOAD=$(write_json "$IDX_REPO/notes.md" 'Run `/alpha:gone` and `/beta:gone`.')
IDX_CACHE="$IDX_REPO/.git/guardrails-skill-index"

idx_fire() {
  : >"$JQ_LOG"
  OUT=$(CLAUDE_PROJECT_DIR="$IDX_REPO" PATH="$SHIM_DIR:$PATH" bash "$HOOK" <<<"$IDX_PAYLOAD" 2>&1)
  IDX_JQ=$(grep -c 'INVOKE' "$JQ_LOG" || true)
}
idx_finds() {
  assert_contains "$1: alpha is still adjudicated" "$OUT" "  /alpha:gone"
  assert_contains "$1: beta is still adjudicated" "$OUT" "  /beta:gone"
}
idx_is_whole() {
  local -a l
  local n
  mapfile -t l <"$1"
  n=$((${#l[@]} - 5))
  ((n >= 0)) && [[ "${l[0]}" == 2 && "${l[3]}" == '---' && "${l[${#l[@]} - 1]}" == "end $n" ]] &&
    [[ "$(printf '%s\n' "${l[@]:4:n}" | grep -c '^end [0-9]')" == 0 ]]
}
assert_idx_whole() {
  if idx_is_whole "$IDX_CACHE"; then ok "$1"; else bad "$1: $(cat "$IDX_CACHE" 2>&1)"; fi
}

rm -f "$IDX_CACHE"
idx_fire
idx_finds "index cache: a cold fire"
assert_eq "index cache: a cold fire reads the manifests once" 1 "$IDX_JQ"
assert_idx_whole "index cache: a cold fire leaves a whole file"
mapfile -t IDX_GOOD <"$IDX_CACHE"

idx_fire
idx_finds "index cache: a whole file"
assert_eq "index cache: a whole file is trusted, no manifest read" 0 "$IDX_JQ"

printf '%s\n' "${IDX_GOOD[@]:0:4}" >"$IDX_CACHE"
idx_fire
idx_finds "index cache: a file cut after its header is a miss"
assert_eq "index cache: the cut file is rebuilt through jq" 1 "$IDX_JQ"
assert_idx_whole "index cache: the cut file is rebuilt whole"

{
  printf '%s\n' "${IDX_GOOD[@]:0:5}"
  printf '%s' "${IDX_GOOD[5]%???}"
} >"$IDX_CACHE"
idx_fire
idx_finds "index cache: a file cut inside its last row is a miss"
assert_eq "index cache: the file cut inside a row is rebuilt through jq" 1 "$IDX_JQ"
assert_idx_whole "index cache: the file cut inside a row is rebuilt whole"

printf '%s\n' "${IDX_GOOD[@]:0:5}" 'end 2' >"$IDX_CACHE"
idx_fire
idx_finds "index cache: a count that disagrees with the rows read is a miss"
assert_eq "index cache: the miscounted file is rebuilt through jq" 1 "$IDX_JQ"
assert_idx_whole "index cache: the miscounted file is rebuilt whole"

printf '%s\n' "${IDX_GOOD[@]:0:5}" 'end 9' 'end 2' >"$IDX_CACHE"
idx_fire
idx_finds "index cache: a sentinel inside the rows is a miss even when the count agrees"
assert_eq "index cache: the mixed file is rebuilt through jq" 1 "$IDX_JQ"

printf '%s\n' "${IDX_GOOD[0]}" /elsewhere/plugin.json "${IDX_GOOD[@]:2}" >"$IDX_CACHE"
idx_fire
idx_finds "index cache: a file for another manifest set is a miss"
assert_eq "index cache: the other-set file is rebuilt through jq" 1 "$IDX_JQ"
assert_idx_whole "index cache: the other-set file is rebuilt whole"

touch "$IDX_REPO/plugins/beta/.claude-plugin/plugin.json"
idx_fire
idx_finds "index cache: a file older than the manifests is a miss"
assert_eq "index cache: the stale file is rebuilt through jq" 1 "$IDX_JQ"
assert_idx_whole "index cache: the stale file is replaced whole"
idx_fire
assert_eq "index cache: the rebuilt file is newer than the manifests, so it is trusted" 0 "$IDX_JQ"

IDX_BAD=0
for _ in 1 2 3 4 5; do
  rm -f "$IDX_CACHE"
  (CLAUDE_PROJECT_DIR="$IDX_REPO" bash "$HOOK" <<<"$IDX_PAYLOAD" >"$TEST_TMPDIR/idx-a" 2>&1) &
  idx_pid_a=$!
  (CLAUDE_PROJECT_DIR="$IDX_REPO" bash "$HOOK" <<<"$IDX_PAYLOAD" >"$TEST_TMPDIR/idx-b" 2>&1) &
  idx_pid_b=$!
  wait "$idx_pid_a" || IDX_BAD=1
  wait "$idx_pid_b" || IDX_BAD=1
  for idx_out in "$TEST_TMPDIR/idx-a" "$TEST_TMPDIR/idx-b"; do
    [[ "$(cat "$idx_out")" == *"  /alpha:gone"* &&
      "$(cat "$idx_out")" == *"  /beta:gone"* ]] || IDX_BAD=1
  done
  idx_is_whole "$IDX_CACHE" || IDX_BAD=1
done
assert_eq "index cache: two cold fires at once both report the findings and leave a whole file" 0 "$IDX_BAD"
idx_fire
idx_finds "index cache: the file the concurrent fires left"
assert_eq "index cache: and it is trusted, so no manifest read runs" 0 "$IDX_JQ"

rm -f "$IDX_CACHE"
chmod 555 "$IDX_REPO/.git"
RO_ERR=$(CLAUDE_PROJECT_DIR="$IDX_REPO" bash "$HOOK" <<<"$IDX_PAYLOAD" 2>&1 >/dev/null)
chmod 755 "$IDX_REPO/.git"
assert_silent "index cache: an unwritable git directory leaves stderr empty" "$RO_ERR"

for HOST in codex cursor; do
  REPO="$TEST_TMPDIR/$HOST-market"
  mkdir -p "$REPO/plugins/$HOST-dir/.$HOST-plugin" "$REPO/plugins/$HOST-dir/skills/setup" \
    "$REPO/plugins/$HOST-dir/extra/held"
  git -C "$REPO" init -q
  MSYS_NO_PATHCONV=1 jq -n --arg n "$HOST-tools" '{name:$n,version:"0.1.0",skills:"./extra/"}' \
    >"$REPO/plugins/$HOST-dir/.$HOST-plugin/plugin.json"
  : >"$REPO/plugins/$HOST-dir/skills/setup/SKILL.md"
  : >"$REPO/plugins/$HOST-dir/extra/held/SKILL.md"
  TARGET="$REPO/notes.md"
  : >"$TARGET"
  run "Run \`/$HOST-tools:missing\` next."
  assert_contains "$HOST manifest: an unresolved skill is reported" "$OUT" "  /$HOST-tools:missing (no such skill"
  assert_contains "$HOST manifest: the plugin resolves by manifest name to its directory" "$OUT" \
    "plugins/$HOST-dir/skills/"
  run "Use \`/$HOST-tools:setup\` and \`/$HOST-tools:held\`."
  assert_silent "$HOST manifest: skills under skills/ and a declared path resolve" "$OUT"
done

report
