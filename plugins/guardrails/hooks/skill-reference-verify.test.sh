#!/usr/bin/env bash
# Contract test for skill-reference-verify.sh (guardrails plugin).
#
# Black-box subprocess invocation. Builds a synthetic marketplace working tree so
# the plugins-root and plugin-scope gates have both a hit and a miss to
# distinguish, then feeds a PostToolUse Write|Edit payload on stdin.

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
RC=0

# hook::buffer_stdin bounds its fd0 read at CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT
# seconds, default 2, and a timeout makes an advisory hook exit 0 silently. A
# single invocation costs 10-20 s of wall time on a loaded Windows/Git Bash box, so
# the default bound produces empty output and a false FAIL that looks like a logic
# defect. Raised here because these cases test detection, not the read bound.
export CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=30

# --- Synthetic marketplace ---------------------------------------------------
# Two plugins. `alpha`'s manifest name matches its directory. `beta`'s manifest
# name deliberately DIVERGES from its directory (`beta-dir`), which is what
# proves resolution goes through the manifest rather than the directory listing.
REPO="$TEST_TMPDIR/market"
mkdir -p "$REPO"
git -C "$REPO" init -q

mk_plugin() {
  local dir="$1" name="$2"
  mkdir -p "$REPO/plugins/$dir/.claude-plugin"
  MSYS_NO_PATHCONV=1 jq -n --arg n "$name" '{name:$n,version:"0.1.0"}' \
    >"$REPO/plugins/$dir/.claude-plugin/plugin.json"
}
# mk_skill <plugin-dir> <skill-dir> [frontmatter-name]
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
# Command name comes from frontmatter, not the directory.
mk_skill alpha legacy-dir renamed-command
# Quoted frontmatter name must resolve identically.
mk_skill alpha quoted-dir '"quoted-name"'

mk_plugin beta-dir beta
mk_skill beta-dir check

TARGET="$REPO/notes.md"
: >"$TARGET"

run() {
  local out
  out=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$TARGET" "$1")" 2>&1)
  RC=$?
  printf '%s' "$out"
}
run_edit() {
  local out
  out=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$TARGET" "$1")" 2>&1)
  RC=$?
  printf '%s' "$out"
}

# ============================ MUST FIRE =====================================

OUT=$(run 'Run `/alpha:nonexistent` next.')
assert_exit "unresolved skill → exit 0 (advisory)" 0 "$RC"
assert_contains "unresolved skill → named" "$OUT" "UNRESOLVED_SKILL: /alpha:nonexistent"
assert_contains "unresolved skill → names the searched plugin dir" "$OUT" "plugins/alpha/skills/"

OUT=$(run 'Both `/alpha:ghost` and `/beta:missing` are gone.')
assert_contains "two unresolved → count" "$OUT" "2 skill reference(s) do not resolve"
assert_contains "two unresolved → manifest-named plugin resolves to its real dir" "$OUT" \
  "plugins/beta-dir/skills/"

OUT=$(run_edit 'Now cites `/alpha:vanished`.')
assert_contains "Edit hunk scanned via new_string" "$OUT" "UNRESOLVED_SKILL: /alpha:vanished"

# The advisory must state its tier — the issue this guard ships under requires
# the third guard never read as deterministic.
OUT=$(run 'Run `/alpha:nonexistent`.')
assert_contains "advisory states detect-then-judge tier" "$OUT" "Detect-then-judge"

# Repro-first regressions for review findings on #1284.

# A bare directory under skills/ is NOT a skill. Without a SKILL.md there is no
# command, so the advisory must still fire — the old directory-only test
# suppressed it.
mkdir -p "$REPO/plugins/alpha/skills/ghost"
OUT=$(run 'Run `/alpha:ghost`.')
assert_contains "skills/ dir without SKILL.md → still unresolved" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost"
# Naming the searched directories must not have changed how the conventional
# layout reads — one root, rendered exactly as it always was.
assert_contains "a plugin declaring no paths still reads as plugins/<plugin>/skills/" "$OUT" \
  "(no such skill under plugins/alpha/skills/)"

# A frontmatter name carrying a trailing YAML comment is a valid rename and must
# resolve; the old end-of-line-anchored parser extracted nothing.
mk_skill alpha commented-dir 'commented-name # public command'
OUT=$(run 'Run `/alpha:commented-name`.')
assert_silent "frontmatter name with trailing YAML comment → resolves" "$OUT"

# The DIRECTORY name of a renamed skill is not an alias. `skills/legacy-dir/`
# declaring `name: renamed-command` answers to /alpha:renamed-command only — the
# stale pre-rename spelling must still fire, since suppressing it defeats the
# guard's whole purpose.
OUT=$(run 'Stale ref `/alpha:legacy-dir`.')
assert_contains "renamed skill's directory name is NOT an alias → fires" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:legacy-dir"
OUT=$(run 'Current ref `/alpha:renamed-command`.')
assert_silent "the declared frontmatter name still resolves" "$OUT"

# A skill declaring no frontmatter name answers to its directory name.
OUT=$(run 'Run `/alpha:setup`.')
assert_silent "no frontmatter name → directory name is the command" "$OUT"

# An invocation carrying arguments is the common form in this repo. The reference
# is the leading token of the span, not the whole span.
OUT=$(run 'Run `/alpha:ghost-arg --apply` now.')
assert_contains "argument-bearing invocation → leading token extracted" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-arg"
OUT=$(run 'Run `/alpha:audit --dry-run <target>`.')
assert_silent "argument-bearing invocation of a real skill → silent" "$OUT"

# ============================ MUST STAY QUIET ===============================

OUT=$(run 'Run `/alpha:setup` and `/alpha:audit` first.')
assert_exit "resolving skills → exit 0" 0 "$RC"
assert_silent "resolving skills → silent" "$OUT"

# Manifest name diverges from directory name; the reference uses the manifest name.
OUT=$(run 'Run `/beta:check`.')
assert_silent "plugin resolved via manifest name, not directory name → silent" "$OUT"

# Frontmatter name diverges from the skill directory name.
OUT=$(run 'Run `/alpha:renamed-command`.')
assert_silent "skill resolved via frontmatter name → silent" "$OUT"

OUT=$(run 'Run `/alpha:quoted-name`.')
assert_silent "skill resolved via quoted frontmatter name → silent" "$OUT"

# PLUGIN-SCOPE GATE: this repo does not own the plugin, so it has no authority.
OUT=$(run 'Install `/some-other-market:thing` from elsewhere.')
assert_silent "unowned plugin → not adjudicated" "$OUT"

# A reference to a directory that exists but carries no manifest is not a plugin.
mkdir -p "$REPO/plugins/not-a-plugin/skills/x"
OUT=$(run 'Run `/not-a-plugin:x`.')
assert_silent "directory without a manifest → not a plugin, silent" "$OUT"

OUT=$(run 'Unbackticked /alpha:nonexistent in prose is not a command.')
assert_silent "unbackticked reference → not scanned" "$OUT"

OUT=$(run 'A URL fragment `https://x.test/a:b` and a time `12:30` are not references.')
assert_silent "URL fragment and time → silent" "$OUT"

OUT=$(run 'Uppercase `/Alpha:Setup` does not match the command grammar.')
assert_silent "uppercase reference → silent (not command-shaped)" "$OUT"

# PLUGINS-ROOT GATE: outside a marketplace repo there is no local authority.
PLAIN="$TEST_TMPDIR/plain"
mkdir -p "$PLAIN"
git -C "$PLAIN" init -q
PLAIN_TARGET="$PLAIN/notes.md"
: >"$PLAIN_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$PLAIN" bash "$HOOK" <<<"$(write_json "$PLAIN_TARGET" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "no plugins/ tree → exit 0" 0 "$RC"
assert_silent "no plugins/ tree → silent (no local authority)" "$OUT"

# A plugins/ directory with no manifests is not a marketplace either.
EMPTY="$TEST_TMPDIR/empty-market"
mkdir -p "$EMPTY/plugins/whatever"
git -C "$EMPTY" init -q
EMPTY_TARGET="$EMPTY/notes.md"
: >"$EMPTY_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$EMPTY" bash "$HOOK" <<<"$(write_json "$EMPTY_TARGET" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "plugins/ with no manifests → exit 0" 0 "$RC"
assert_silent "plugins/ with no manifests → silent" "$OUT"

# Non-markdown files are out of scope.
SCRIPT="$REPO/tool.sh"
: >"$SCRIPT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$SCRIPT" 'echo `/alpha:nonexistent`')" 2>&1)
RC=$?
assert_exit "non-markdown file → exit 0" 0 "$RC"
assert_silent "non-markdown file → not scanned" "$OUT"

OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(notebook_json "$TARGET" '`/alpha:nonexistent`')" 2>&1)
RC=$?
assert_exit "NotebookEdit payload → exit 0" 0 "$RC"
assert_silent "NotebookEdit payload → silent" "$OUT"

OUTSIDE="$TEST_TMPDIR/outside.md"
: >"$OUTSIDE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "file outside project dir → exit 0" 0 "$RC"
assert_silent "file outside project dir → silent" "$OUT"

# A CHANGELOG is an append-only historical record — a rename entry must keep
# naming the old command, so the guard must not adjudicate one. Measured cause of
# 89% of this guard's findings on the marketplace corpus.
CL="$REPO/plugins/alpha/CHANGELOG.md"
: >"$CL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$CL" 'Renamed the `/alpha:nonexistent` skill to `/alpha:audit`.')" 2>&1)
RC=$?
assert_exit "CHANGELOG.md → exit 0" 0 "$RC"
assert_silent "CHANGELOG.md is historical by contract → silent" "$OUT"

# The exclusion is basename-scoped, not a substring: a file merely mentioning the
# word must still be adjudicated.
NOTCL="$REPO/docs-CHANGELOG-notes.md"
mkdir -p "$(dirname "$NOTCL")"
: >"$NOTCL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$NOTCL" 'Run `/alpha:nonexistent`.')" 2>&1)
assert_contains "CHANGELOG-in-name but not a CHANGELOG → still adjudicated" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:nonexistent"

# PARTIAL-EDIT RECONSTRUCTION. An Edit may replace an arbitrary substring, so a
# hunk can be a bare word with no command in it. The edit is already applied by
# PostToolUse time, so the containing reference is recovered from disk, anchored to
# the hunk's own text.
PARTIAL="$REPO/partial.md"
printf 'Run `/alpha:ghost-partial` to begin.\n' >"$PARTIAL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$PARTIAL" 'ghost-partial')" 2>&1)
RC=$?
assert_exit "bare-word Edit hunk → exit 0" 0 "$RC"
assert_contains "bare-word Edit hunk → containing reference recovered" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-partial"

# Diff-scope is preserved: a PRE-EXISTING unrelated broken reference on a
# neighbouring line must NOT fire just because reconstruction read from disk.
PARTIAL2="$REPO/partial2.md"
printf 'Stale `/alpha:untouched-ghost` here.\nRun `/alpha:ghost-two` to begin.\n' >"$PARTIAL2"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$PARTIAL2" 'ghost-two')" 2>&1)
assert_contains "reconstruction reports the edited reference" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-two"
assert_absent "reconstruction does NOT report an untouched neighbour" "$OUT" \
  "untouched-ghost"

# Diff-scope again, against the harder shape from #1453: the hunk is unrelated
# prose that merely SHARES A WORD TOKEN with an untouched broken reference
# elsewhere in the same file. Anchoring on the token alone (the pre-fix behavior)
# pulls that reference in — `legacy` occurs in both `ghost-legacy` and the prose —
# so the anchor has to be the hunk's own line, which occurs verbatim in exactly
# the line the edit landed in. Verified to fail against the pre-fix guard (which
# fired `UNRESOLVED_SKILL: /alpha:ghost-legacy`), the same shape #1432 proved for
# stale-path-verify's sibling defect.
SEGSHARE="$REPO/segshare.md"
printf 'Stale `/alpha:ghost-legacy` here.\nThe legacy naming convention was updated today.\n' \
  >"$SEGSHARE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$SEGSHARE" 'The legacy naming convention was updated today.')" 2>&1)
RC=$?
assert_exit "prose hunk sharing a word token → exit 0" 0 "$RC"
assert_silent "hunk sharing only a token does not drag in an untouched broken reference" "$OUT"

# The DEGENERATE shape of the same defect: the hunk IS the shared word, so its
# anchor is no longer than the token and matches BOTH the edited prose line and
# the untouched reference. Anchoring on lines cannot separate them here — only
# requiring the anchor to locate exactly ONE line does. An anchor matching several
# cannot say which the edit landed in, so it is dropped rather than unioned;
# unioning fired `UNRESOLVED_SKILL: /alpha:ghost-legacy` from an edit that never
# touched it, since `legacy` is also a substring of that skill segment and so
# clears the token filter. Trading this for a missed advisory when an edit lands
# in a verbatim-duplicated line is deliberate — an advisory guard is degraded
# worse by speaking wrongly than by staying quiet.
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

# `replace_all` is the one shape where repetition is EXPECTED, not ambiguous:
# every occurrence is a place this call edited, so uniqueness must not be
# required or the guard goes silent on a genuine multi-site break. Built inline
# rather than through edit_json — that helper is shared across guard suites and
# gated by hook-utils-sync, so this suite's payload variant stays local to it.
replall_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg fp "$1" --arg s "$2" \
    '{tool_name:"Edit",tool_input:{file_path:$fp,new_string:$s,replace_all:true}}'
}
REPLALL="$REPO/replall.md"
printf 'First `/alpha:ghost-one` here.\nSecond `/alpha:ghost-two` there.\n' >"$REPLALL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(replall_json "$REPLALL" 'ghost')" 2>&1)
RC=$?
assert_exit "replace_all Edit → exit 0" 0 "$RC"
assert_contains "replace_all → first edited reference reported" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-one"
assert_contains "replace_all → second edited reference reported" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-two"

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
# Asserted with the trailing backtick so the needle cannot be satisfied by the
# `/alpha:ghost-old` line this case exists to exclude — otherwise the positive and
# the negative assertion below overlap, and only the pair is load-bearing.
assert_contains "replace_all + patch → the WRITTEN reference is still reported" \
  "$OUT" 'UNRESOLVED_SKILL: /alpha:ghost (no such skill'
assert_absent "replace_all + patch → the UNTOUCHED reference is not reported" \
  "$OUT" "/alpha:ghost-old"

# LIVENESS. The identical payload against a TRUNCATED, EMPTY target. Silence here
# is what proves the finding above came from READING THE FILE and not from the
# payload text — a filter that merely echoed `new_string` would speak either way.
EMPTYT="$REPO/replall-empty.md"
: >"$EMPTYT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(patch_one "$EMPTYT")" 2>&1)
assert_silent "replace_all + patch → empty target yields nothing at all" "$OUT"

# The filter must not cost a real multi-site finding: when the patch says BOTH
# lines were written, both references survive it.
BOTHW="$REPO/replall-both.md"
printf 'First `/alpha:ghost-one` here.\nSecond `/alpha:ghost-two` there.\n' >"$BOTHW"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(replall_patch_json "$BOTHW" 'ghost' \
  '-First `/alpha:setup-one` here.' \
  '-Second `/alpha:setup-two` there.' \
  '+First `/alpha:ghost-one` here.' \
  '+Second `/alpha:ghost-two` there.')" 2>&1)
assert_contains "replace_all + patch → first genuinely written ref survives" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-one"
assert_contains "replace_all + patch → second genuinely written ref survives" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-two"

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
  "$OUT" 'UNRESOLVED_SKILL: /alpha:ghost (no such skill'
# ...and the suppression is not simply switched off by the reflow: the untouched
# reference on an unreformatted line is still excluded in the same run.
assert_absent "reflowed line → the untouched reference is still suppressed" \
  "$OUT" "/alpha:ghost-old"

# The abstain rule. When the witness recognizes NO occurrence — a formatter that
# rewrote more than spacing — Gate 3 must fall back to the unfiltered set rather
# than mute the advisory entirely. Both references come back, which is exactly the
# pre-gate behaviour and the direction this guard accepts.
STALE="$REPO/replall-stale.md"
printf -- '- Run `/alpha:ghost` now (moved).\nLegacy `/alpha:ghost-old` stays.\n' >"$STALE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(patch_one "$STALE")" 2>&1)
assert_contains "stale witness → written reference still reported" \
  "$OUT" 'UNRESOLVED_SKILL: /alpha:ghost (no such skill'
assert_contains "stale witness → gate abstains rather than muting" \
  "$OUT" "UNRESOLVED_SKILL: /alpha:ghost-old"

# A hunk that already carries a full command is scanned directly.
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$PARTIAL2" 'Run `/alpha:ghost-three` now.')" 2>&1)
assert_contains "full-command hunk → scanned directly" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-three"
assert_absent "full-command hunk → no disk reconstruction leakage" "$OUT" \
  "untouched-ghost"

# An Edit can replace PART of a segment: `up` -> `host` turns `/alpha:setup` into
# `/alpha:sethost`. The hunk token is then a substring of the segment, not the
# whole of it, so the filter must match on substring.
SUBST="$REPO/substr.md"
printf 'Run `/alpha:sethost` to begin.\n' >"$SUBST"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$SUBST" 'host')" 2>&1)
assert_contains "substring Edit inside a segment → recovered" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:sethost"

# A hunk carrying BOTH a complete reference and a substring change to another must
# report both — gating reconstruction on an empty scan would miss the partial half.
# The two live on separate lines of the SAME hunk: a single Edit's new_string can
# span several lines of a replaced passage, and each line lands on disk verbatim,
# so line-anchoring finds the bare-word line while the complete reference on the
# other line is already caught by the direct scan of the whole hunk.
MIXED="$REPO/mixed.md"
printf 'First `/alpha:ghost-mixed` here.\nSecond `/alpha:audit` is fine.\n' >"$MIXED"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$MIXED" $'ghost-mixed\nAlso now cites `/alpha:ghost-direct`.')" 2>&1)
assert_contains "mixed hunk → direct reference reported" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-direct"
assert_contains "mixed hunk → reconstructed reference also reported" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-mixed"

# Reconstruction must not double-report a reference reachable both ways.
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$MIXED" 'Run `/alpha:ghost-mixed` again.')" 2>&1)
assert_contains "reference reachable both ways → reported" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-mixed"
assert_contains "reference reachable both ways → counted once" "$OUT" \
  "1 skill reference(s) do not resolve"

# Sharing a physical LINE with the hunk is not evidence the edit wrote a
# reference. Here the anchor is unique — so the uniqueness gate is satisfied and
# cannot help — and it sits on the same line as an untouched broken reference,
# which a shared word (`legacy`) then readmitted through the token filter. Only
# keeping the part of the line the anchor OVERLAPS separates them.
ONELINE="$REPO/oneline.md"
printf 'Stale `/alpha:ghost-legacy` here. The legacy naming convention was updated today.\n' \
  >"$ONELINE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$ONELINE" 'The legacy naming convention was updated today.')" 2>&1)
RC=$?
assert_exit "unique anchor beside an untouched reference → exit 0" 0 "$RC"
assert_silent "a reference the anchor does not overlap is not reported" "$OUT"

# The same line, edited INSIDE the reference this time: overlap must still admit
# it, or the fix above would have bought scope by going blind.
ONELINE2="$REPO/oneline2.md"
printf 'Stale `/alpha:ghost-legacy` here. The legacy naming convention was updated today.\n' \
  >"$ONELINE2"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$ONELINE2" 'ghost-legacy')" 2>&1)
assert_contains "an anchor inside the reference still reports it" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-legacy"

# A SHORT substring edit. Replacing `up` with `xx` inside `/alpha:setup` leaves
# `/alpha:setxx` on disk and a two-character hunk; a minimum token length left
# every such edit uncovered, while overlap has no length to clear.
SHORT="$REPO/short.md"
printf 'Run `/alpha:setxx` to begin.\n' >"$SHORT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$SHORT" 'xx')" 2>&1)
RC=$?
assert_exit "two-character Edit hunk → exit 0" 0 "$RC"
assert_contains "two-character Edit hunk → containing reference recovered" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:setxx"

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
# The prose is French only to get multibyte bytes cheaply; the words carry no
# meaning for the assertion. One French preposition was swapped out because the
# spell-check lane reads it as a truncated English word — a throwaway fixture is
# not worth a global dictionary entry. Keep any replacement wording clear of it.
printf 'Préambule des conventions — rien à voir ici.\nExécutez `/alpha:ghost-cafe` après le déploiement — voilà.\n' \
  >"$UTF8"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$UTF8" 'ghost-cafe')" 2>&1)
RC=$?
assert_exit "multibyte content around the anchor → exit 0" 0 "$RC"
assert_contains "a reference reconstructed out of multibyte content is intact" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-cafe"

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
# classifies them. An earlier revision of this case hardcoded U+00A0 and so passed
# on Windows and failed on Linux CI — asserting a libc's classification table as if
# it were this hook's behavior.
#
# So the separator is DISCOVERED rather than assumed: take the first candidate this
# host actually classifies differently between the two locales, probed through the
# very sed stage the assertion depends on. That cannot go vacuous (a candidate that
# does not discriminate is never selected) and cannot go platform-brittle (no
# codepoint is baked in). Every candidate is escape-built, never a literal byte, so
# an editor or transfer that normalizes whitespace cannot quietly turn it into an
# ASCII space — which is exactly what happened while this case was first written.
# MIRRORS skill-reference-verify.sh:220 — emit_refs' reference-extraction sed,
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
  # This is the ONLY case that separates `local +x LC_ALL=C` from a plain `local
  # LC_ALL=C` — every other case in this file passes identically under both. So a
  # skip here silently retires the single guard this fix exists to add, and a green
  # run would say nothing about it. Both platforms this was developed on select
  # U+3000, so this branch is expected to be DEAD in CI: a skip appearing in a log
  # is itself the finding, not a shrug. It stays a skip rather than a failure only
  # so a host with no UTF-8 locale, or a libc that classifies no non-ASCII space as
  # `[[:space:]]`, does not block a developer over something this hook does not own.
  ok "SKIP locale-contrast guard — NO SEPARATOR DISCRIMINATES on this host, the +x guard did NOT run ($(uname -s), no candidate classified as [[:space:]] under en_US.UTF-8 but not C)"
else
  SEPDOC="$REPO/sepspace.md"
  printf 'Intro line.\nRun `/alpha:ghost-sep%sarg` now.\n' "$SEP" >"$SEPDOC"
  # The hunk is a bare SUBSTRING, so the direct scan cannot see the reference and
  # only reconstruction can report it.
  OUT=$(LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 CLAUDE_PROJECT_DIR="$REPO" \
    bash "$HOOK" <<<"$(edit_json "$SEPDOC" 'ghost-sep')" 2>&1)
  RC=$?
  assert_exit "consumer-exported UTF-8 locale → exit 0" 0 "$RC"
  assert_contains "the pin does not reach the children: reference separated by $SEP_NAME survives" \
    "$OUT" "UNRESOLVED_SKILL: /alpha:ghost-sep"
fi

# A short anchor is still subject to the uniqueness gate — it buys no scope.
SHORT2="$REPO/short2.md"
printf 'Run `/alpha:setxx` and note the xx convention.\n' >"$SHORT2"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$SHORT2" 'xx')" 2>&1)
assert_silent "a short anchor occurring twice is still ambiguous" "$OUT"

# A large multiline Edit must cost neither a subprocess NOR a rescan per hunk line.
# Both are anchors times file size; removing only the subprocess left a thousand-line
# hunk spending the hook's own 30 s timeout (hooks.json) and losing the advisory. The
# hunk is located whole, so this is one scan. The ceiling is deliberately loose so
# the case fails only on the defect, not on a slow host.
# Every line here is span-free ON PURPOSE: a hunk whose lines carry code spans hits
# the span cap and stops early, which would hide the per-line rescan rather than
# measure it.
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

# The whole-hunk locate is a fast path, not the only one. When the text on disk is
# no longer the hunk verbatim — another PostToolUse hook reformatting the file
# between the write and this read is the realistic cause — the per-line walk must
# still recover the reference. Here a blank line separates two lines the Edit wrote
# together, so the whole hunk cannot be found and only the lines can.
SPLIT="$REPO/split.md"
printf 'First edited line.\n\nSecond line with `/alpha:ghost-split`.\n' >"$SPLIT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$SPLIT" 'First edited line.
Second line with `/alpha:ghost-split`.')" 2>&1)
RC=$?
assert_exit "hunk no longer contiguous on disk → exit 0" 0 "$RC"
assert_contains "per-line fallback still recovers the reference" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-split"

# A multi-line hunk whose every LINE repeats but whose whole text does not is where
# the whole-hunk locate is strictly better than the per-line walk: the walk drops
# every anchor as ambiguous, while the hunk itself names exactly one place.
PAIR="$REPO/pair.md"
printf 'shared line\nother\nshared line\ntail with `/alpha:ghost-pair`.\n' >"$PAIR"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$PAIR" 'shared line
tail with `/alpha:ghost-pair`.')" 2>&1)
assert_contains "a unique whole hunk resolves lines that individually repeat" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-pair"

# SCALE meets the FALLBACK. The two cases above force the fallback but on three
# lines, and the timing case above is large but takes the whole-hunk fast path, so
# neither measures what the original defect actually cost: one scan PER ANCHOR over
# a big file. This case combines them — a file near RECONSTRUCT_MAX_CHARS and a
# many-line hunk that a reformat has made non-contiguous — and it is the case the
# fallback's anchor cap exists for.
#
# What the cap DOES is asserted, not how long it takes. A wall-clock bound here
# measures the host: the same fixture read 21 s loaded and the smaller one below
# read 23 s, while the isolated scan it is supposed to be bounding is ~1 s at this
# size. A timing assertion that noisy is worse than none — it fails on load and
# passes on a regression that happens to run on a quiet box. The scan cost itself
# is measured directly (see the constants' docblock); what a test can pin
# deterministically is the cap's BEHAVIOR, so this case pins it from both sides.
#
# Both references are reached only through reconstruction: each hunk line carrying
# one is a bare SUBSTRING, never the reference itself, so the direct hunk scan
# cannot see either and an assertion cannot pass on the direct scan alone.
FBIG="$REPO/fallback-big.md"
FBIGHUNK="$TEST_TMPDIR/fallback-hunk.txt"
{
  printf 'ghost-fallback\n'
  for ((i = 2; i <= 300; i++)); do printf 'Body line %s of the reformatted passage.\n' "$i"; done
  printf 'ghost-deep\n'
  for ((i = 302; i <= 401; i++)); do printf 'Body line %s of the reformatted passage.\n' "$i"; done
} >"$FBIGHUNK"
# On disk those two lines read as part of code spans, so the hunk is not contiguous
# here and the whole-hunk locate cannot match it. Unrelated prose follows, putting
# the file just under RECONSTRUCT_MAX_CHARS (128 KiB).
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
# The bound ADMITS: the first hunk line is inside the anchor cap, so its reference
# is still recovered. A cap that had collapsed to nothing would stop guarding while
# passing every timing check ever written.
assert_contains "the capped fallback still reports the reference it admits" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-fallback"
# The bound BINDS: hunk line 301 is far past the cap this file size buys, so its
# reference is not reached. Asserting the silence is what makes the cap observable
# without a clock — if the anchor walk ever went unbounded again, this fails.
assert_absent "the fallback stops at the anchor cap instead of walking the hunk" "$OUT" \
  "UNRESOLVED_SKILL: /alpha:ghost-deep"

# Above the cap, reconstruction does not run at all — one scan of a file that size
# would spend the budget by itself. The direct hunk scan is unaffected, so a
# COMPLETE reference in the hunk is still reported; only partial-edit recovery
# stops, which is this guard's permitted failure direction.
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
  "UNRESOLVED_SKILL: /alpha:ghost-over"

# ============ MANIFEST-DECLARED SKILL PATHS =================================
# A manifest may declare `skills` paths, which ADD to the conventional `skills/`
# directory rather than replacing it. A command loaded from a declared location is
# real, so reporting it unresolved is a false advisory.
mk_plugin gamma gamma
mk_skill gamma conventional
mkdir -p "$REPO/plugins/gamma/custom/extras/declared"
printf -- '---\nname: declared\ndescription: x\n---\n' \
  >"$REPO/plugins/gamma/custom/extras/declared/SKILL.md"
# A declared path may point straight AT a skill directory, not only at a directory
# of them.
mkdir -p "$REPO/plugins/gamma/solo"
printf -- '---\nname: solo-command\ndescription: x\n---\n' \
  >"$REPO/plugins/gamma/solo/SKILL.md"
MSYS_NO_PATHCONV=1 jq -n '{name:"gamma",version:"0.1.0",skills:["./custom/extras/","./solo/"]}' \
  >"$REPO/plugins/gamma/.claude-plugin/plugin.json"

OUT=$(run 'Run `/gamma:declared`.')
RC=$?
assert_exit "manifest-declared skill path → exit 0" 0 "$RC"
assert_silent "skill under a manifest-declared path resolves" "$OUT"

OUT=$(run 'Run `/gamma:solo-command`.')
assert_silent "declared path pointing AT a skill directory resolves" "$OUT"

# Declared paths ADD to `skills/`; the conventional directory must still resolve.
OUT=$(run 'Run `/gamma:conventional`.')
assert_silent "declared paths add to skills/, they do not replace it" "$OUT"

# The guard must not go blind for a plugin that declares paths — a command in
# neither location still fires.
OUT=$(run 'Run `/gamma:nowhere`.')
assert_contains "declared paths do not suppress a genuinely missing command" "$OUT" \
  "UNRESOLVED_SKILL: /gamma:nowhere"
# The message names WHERE it looked, and the advisory's next line tells the reader
# to confirm against the tree — so the full rendering is asserted, not its prefix.
# A prefix match passes on any wrong directory list, which is the whole subject
# here.
assert_contains "the advisory names every directory the search covered" "$OUT" \
  "(no such skill under plugins/gamma/skills/, plugins/gamma/custom/extras/, plugins/gamma/solo/)"

# A declared skill's DIRECTORY name is no more an alias than a conventional one's.
OUT=$(run 'Run `/gamma:solo`.')
assert_contains "declared skill's directory name is NOT an alias" "$OUT" \
  "UNRESOLVED_SKILL: /gamma:solo"

# A string `skills` value is as valid as an array.
mk_plugin delta delta
mkdir -p "$REPO/plugins/delta/elsewhere/one"
printf -- '---\nname: one\ndescription: x\n---\n' \
  >"$REPO/plugins/delta/elsewhere/one/SKILL.md"
MSYS_NO_PATHCONV=1 jq -n '{name:"delta",version:"0.1.0",skills:"./elsewhere/"}' \
  >"$REPO/plugins/delta/.claude-plugin/plugin.json"
OUT=$(run 'Run `/delta:one`.')
assert_silent "a string skills value resolves like a one-element array" "$OUT"

# The single-skill plugin layout: a SKILL.md at the plugin root, no `skills/`
# subdirectory and no `skills` key, auto-loads as one skill named by its
# frontmatter.
mk_plugin epsilon epsilon
printf -- '---\nname: eps-command\ndescription: x\n---\n' >"$REPO/plugins/epsilon/SKILL.md"
OUT=$(run 'Run `/epsilon:eps-command`.')
assert_silent "root SKILL.md with no skills/ and no manifest key auto-loads" "$OUT"
OUT=$(run 'Run `/epsilon:missing`.')
assert_contains "single-skill plugin still fires for a command it does not have" "$OUT" \
  "UNRESOLVED_SKILL: /epsilon:missing"

# The auto-load applies only under its documented conditions. A root SKILL.md
# BESIDE a populated `skills/` is not loaded, so it must not resolve — accepting it
# would suppress the advisory for a command Claude Code does not offer.
mk_plugin zeta zeta
mk_skill zeta real
printf -- '---\nname: zeta-root\ndescription: x\n---\n' >"$REPO/plugins/zeta/SKILL.md"
OUT=$(run 'Run `/zeta:zeta-root`.')
assert_contains "root SKILL.md beside a populated skills/ is not auto-loaded" "$OUT" \
  "UNRESOLVED_SKILL: /zeta:zeta-root"

# ============================ KILL SWITCH ===================================

OUT=$(CLAUDE_PROJECT_DIR="$REPO" CLAUDE_PLUGIN_OPTION_SKILL_REFERENCE_VERIFY_ENABLED=false \
  bash "$HOOK" <<<"$(write_json "$TARGET" 'Run `/alpha:nonexistent`.')" 2>&1)
RC=$?
assert_exit "kill switch → exit 0" 0 "$RC"
assert_silent "kill switch → silent" "$OUT"

# ============================ EMPTY STDIN ===================================

OUT=$(bash "$HOOK" </dev/null 2>&1)
RC=$?
assert_exit "empty stdin → exit 0" 0 "$RC"
assert_silent "empty stdin → no output" "$OUT"

# ============================ MISSING PREREQUISITE ==========================

# Runtime jq-removal is not portably simulable — an isolated bin dir without jq
# cannot host bash + coreutils across Git Bash and Linux, the same constraint
# secret-pattern-detection.test.sh and require-jq-notice-isolation.test.sh both
# document. Assert the fail-open guard is present via the shared helper;
# require_jq's own behavior is covered by lib/hook-utils.test.sh, and this hook's
# notice key is proven unique plugin-wide by require-jq-notice-isolation.test.sh.
HOOK_SRC=$(cat "$HOOK")
assert_contains "jq guard: uses hook::require_jq" "$HOOK_SRC" 'hook::require_jq'
assert_contains "jq guard: hook-specific notice key" "$HOOK_SRC" 'guardrails-skill-reference-verify'
assert_contains "repo root is file-anchored" "$HOOK_SRC" 'hook::repo_root "$(dirname "$FILE")"'

# ============================ TELEMETRY =====================================

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

report
